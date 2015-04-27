// Copyright (c) 2015, the Comid Authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

part of comid;

abstract class InputStyle extends Object with EventManager {
  CodeEditor cm;
  DivElement div;
  Composing composing;

  // This will be set to an array of strings when copying, so that,
  // when pasting, we know what kind of selections the copied text
  // was made out of.
  List lastCopied = null;

  InputStyle(this.cm);

  OperationGroup get operationGroup => cm.operationGroup;

  void init(Display display);
  void reset([bool typing = false]);
  void focus();
  void setUneditable(Element element);
  void showSelection(DrawnSelection drawn);
  bool supportsTouch();
  void onKeyPress(KeyboardEvent e);
  void receivedFocus();
  Element getField();
  void resetPosition();
  bool get needsContentAttribute;
  void ensurePolled();

  void ensureFocus() {
    if (!cm.state.focused) {
      cm.display.input.focus();
      cm.onFocus(cm);
    }
  }

  bool isReadOnly() {
    return cm.options.readOnly != false || cm.doc.cantEdit;
  }

  void applyTextInput(CodeEditor cm, [String inserted, int deleted = 0, Selection sel]) {
    Document doc = cm.doc;
    cm.display.shift = false;
    if (sel == null) sel = doc.sel;

    var textLines = doc.splitLines(inserted);
    var multiPaste = null;
    // When pasing N lines into N selections, insert one line per selection
    if (cm.state.pasteIncoming && sel.ranges.length > 1) {
      if (lastCopied != null && lastCopied.join("\n") == inserted) {
        multiPaste = sel.ranges.length % lastCopied.length == 0
            ? lastCopied.map(doc.splitLines).toList() : null;
      } else if (textLines.length == sel.ranges.length) {
        multiPaste = textLines.map((l) => [l]).toList();
      }
    }

    // Normal behavior is to insert the new text into every selection
    var updateInput;
    for (var i = sel.ranges.length - 1; i >= 0; i--) {
      var range = sel.ranges[i];
      var from = range.from();
      var to = range.to();
      if (range.empty()) {
        if (deleted > 0) { // Handle deletion
          from = new Pos(from.line, from.char - deleted);
        } else if (cm.state.overwrite && !cm.state.pasteIncoming) { // Handle overwrite
          to = new Pos(to.line,
                        min(doc._getLine(to.line).text.length,
                            to.char + lst(textLines).length));
        }
      }
      updateInput = cm.curOp.updateInput;
      var changeEvent = new Change(from, to,
          multiPaste != null ? multiPaste[i % multiPaste.length] : textLines,
          cm.state.pasteIncoming ? "paste" : cm.state.cutIncoming ? "cut" : "+input");
      doc.makeChange(changeEvent);
      signalLater(cm, "inputRead", cm, changeEvent);
      // When an 'electric' character is inserted, immediately trigger a reindent
      if (inserted != null && !cm.state.pasteIncoming && cm.options.electricChars &&
          cm.options.smartIndent && range.head.char < 100 &&
          (i == 0 || sel.ranges[i - 1].head.line != range.head.line)) {
        var mode = cm.getModeAt(range.head);
        var end = cm.changeEnd(changeEvent);
        if (mode.electricChars != null) {
          for (var j = 0; j < mode.electricChars.length; j++) {
            if (inserted.indexOf(mode.electricChars.substring(j,j+1)) > -1) {
              cm.indentLine(end.line, "smart");
              break;
            }
          }
        } else if (mode.electricInput != null) {
          if (mode.electricInput.hasMatch(doc._getLine(end.line).text.substring(0, end.char))) {
            cm.indentLine(end.line, "smart");
          }
        }
      }
    }
    cm.ensureCursorVisible();
    cm.curOp.updateInput = updateInput;
    cm.curOp.typing = true;
    cm.state.pasteIncoming = cm.state.cutIncoming = false;
  }

  CopyableRanges copyableRanges(CodeEditor cm) {
    var text = [], ranges = [];
    for (var i = 0; i < cm.doc.sel.ranges.length; i++) {
      var line = cm.doc.sel.ranges[i].head.line;
      var lineRange = new Range(new Pos(line, 0), new Pos(line + 1, 0));
      ranges.add(lineRange);
      text.add(cm.getRange(lineRange.anchor, lineRange.head));
    }
    return new CopyableRanges(text, ranges);
  }

  void disableBrowserMagic(Element field) {
    field.setAttribute("autocorrect", "off");
    field.setAttribute("autocapitalize", "off");
    field.setAttribute("spellcheck", "false");
  }

  DivElement hiddenTextarea() {
    var te = elt("textarea", null, null, "position: absolute; padding: 0; width: 1px; height: 1em; outline: none");
    var div = elt("div", [te], null, "overflow: hidden; position: relative; width: 3px; height: 0px;");
    // The textarea is kept positioned near the cursor to prevent the
    // fact that it'll be scrolled into view on input from scrolling
    // our fake cursor out of view. On webkit, when wrap=off, paste is
    // very slow. So make the area wide instead.
    if (webkit) te.style.width = "1000px";
    else te.setAttribute("wrap", "off");
    // If border: 0; -- iOS fails to open keyboard (issue #1287)
    if (ios) te.style.border = "1px solid black";
    disableBrowserMagic(te);
    return div;
  }

}

class TextareaInput extends InputStyle {
  String prevInput;
  bool pollingFast;
  Delayed polling;
  bool inaccurateSelection;
  String textSelection; // Renamed hasSelection to textSelection to avoid conflict with global hasSelection()
  DivElement wrapper;
  TextAreaElement textarea;
  bool contextMenuPending = false;

  TextareaInput(CodeEditor cm) : super(cm) {
    // See input.poll and input.reset
    this.prevInput = "";

    // Flag that indicates whether we expect input to appear real soon
    // now (after some event like 'keypress' or 'input') and are
    // polling intensively.
    this.pollingFast = false;
    // Self-resetting timeout for the poller
    this.polling = new Delayed();
    // Tracks when input.reset has punted to just putting a short
    // string into the textarea instead of the full selection.
    this.inaccurateSelection = false;
    // Used to work around IE issue with selection being forgotten when focus moves away from textarea
    this.textSelection = null;
  }

  init(Displ display) {
    var input = this;

    // Wraps and hides input textarea
    var div = this.wrapper = hiddenTextarea();
    // The semihidden textarea that is focused when the editor is
    // focused, and receives input.
    var te = this.textarea = div.firstChild;
    display.wrapper.insertBefore(div, display.wrapper.firstChild);

    // Needed to hide big blue blinking cursor on Mobile Safari (doesn't seem to work in iOS 8 anymore)
    if (ios) te.style.width = "0px";

    on(te, "input", (e) {
      if (ie && ie_version >= 9) input.textSelection = null;
      input.poll();
    });

    on(te, "paste", (e) {
      // Workaround for webkit bug https://bugs.webkit.org/show_bug.cgi?id=90206
      // Add a char to the end of textarea before paste occur so that
      // selection doesn't span to the end of textarea.
      if (webkit && !cm.state.fakedLastChar && cm.state.lastMiddleDown != null) {
        DateTime cur = new DateTime.now();
        Duration dur = cur.difference(cm.state.lastMiddleDown);
        num deltaTime = dur.inMilliseconds;
        if (!(deltaTime < 200)) {
          var start = te.selectionStart, end = te.selectionEnd;
          te.value += r"$";
          // The selection end needs to be set before the start, otherwise there
          // can be an intermediate non-empty selection between the two, which
          // can override the middle-click paste buffer on linux and cause the
          // wrong thing to get pasted.
          te.selectionEnd = end;
          te.selectionStart = start;
          cm.state.fakedLastChar = true;
        }
      }
      cm.state.pasteIncoming = true;
      input.fastPoll();
    });

    prepareCopyCut(e) {
      if (cm.somethingSelected()) {
        lastCopied = cm.getSelections();
        if (input.inaccurateSelection) {
          input.prevInput = "";
          input.inaccurateSelection = false;
          te.value = lastCopied.join("\n");
          selectInput(te);
        }
      } else {
        var ranges = copyableRanges(cm);
        lastCopied = ranges.text;
        if (e.type == "cut") {
          cm.setSelections(ranges.ranges, null, sel_dontScroll);
        } else {
          input.prevInput = "";
          te.value = ranges.text.join("\n");
          selectInput(te);
        }
      }
      if (e.type == "cut") cm.state.cutIncoming = true;
    }
    on(te, "cut", prepareCopyCut);
    on(te, "copy", prepareCopyCut);

    on(display.scroller, "paste", (e) {
      if (cm.eventInWidget(display, e)) return;
      cm.state.pasteIncoming = true;
      input.focus();
    });

    // Prevent normal selection in the editor (we handle our own)
    on(display.lineSpace, "selectstart", (e) {
      if (!cm.eventInWidget(display, e)) e_preventDefault(e);
    });
  }

  DrawnSelection prepareSelection() {
    // Redraw the selection and/or cursor
    var display = cm.display, doc = cm.doc;
    var result = display.prepareSelection(cm);

    // Move the hidden textarea near the cursor to prevent scrolling artifacts
    if (cm.options.moveInputWithCursor) {
      var headPos = cm.cursorCoords(doc.sel.primary().head, "div");
      var wrapOff = display.wrapper.getBoundingClientRect(), lineOff = display.lineDiv.getBoundingClientRect();
      result.teTop = max(0, min(display.wrapper.clientHeight - 10,
                                          headPos.top + lineOff.top - wrapOff.top));
      result.teLeft = max(0, min(display.wrapper.clientWidth - 10,
                                           headPos.left + lineOff.left - wrapOff.left));
    }
    return result;
  }

  void showSelection(DrawnSelection drawn) {
    var cm = this.cm, display = cm.display;
    removeChildrenAndAdd(display.cursorDiv, drawn.cursors);
    removeChildrenAndAdd(display.selectionDiv, drawn.selection);
    if (drawn.teTop != null) {
      wrapper.style.top = "${drawn.teTop}px";
      wrapper.style.left = "${drawn.teLeft}px";
    }
  }

  // Reset the input to correspond to the selection (or to be empty,
  // when not typing and nothing is selected)
  void reset([bool typing = false]) {
    if (contextMenuPending) return;
    var minimal, selected;
    var cm = this.cm;
    var doc = cm.doc;
    if (cm.somethingSelected()) {
      prevInput = "";
      var range = doc.sel.primary();
      minimal = hasCopyEvent &&
          (range.to().line - range.from().line > 100 ||
              (selected = cm.getSelection()).length > 1000);
      var content = minimal ? "-" : selected == null ? cm.getSelection() : selected;
      textarea.value = content;
      if (cm.state.focused) selectInput(textarea);
      if (ie && ie_version >= 9) textSelection = content;
    } else if (!typing) {
      prevInput = textarea.value = "";
      if (ie && ie_version >= 9) textSelection = null;
    }
    inaccurateSelection = minimal;
  }

  Element getField() { return this.textarea; }

  bool supportsTouch() { return false; }

  void focus() {
    if (cm.options.readOnly != "nocursor" && (!mobile || activeElt() != this.textarea)) {
      try { textarea.focus(); }
      catch (e) {} // IE8 will throw if the textarea is display: none or not in DOM
    }
  }

  void blur() { this.textarea.blur(); }

  void resetPosition() {
    wrapper.style.top = wrapper.style.left = '0';
  }

  void receivedFocus() {
    slowPoll();
  }

  // Poll for input changes, using the normal rate of polling. This
  // runs as long as the editor is focused.
  void slowPoll() {
    var input = this;
    if (input.pollingFast) return;
    input.polling.set(cm.options.pollInterval, () {
      input.poll();
      if (input.cm.state.focused) input.slowPoll();
    });
  }

  // When an event has just come in that is likely to add or change
  // something in the input textarea, we poll faster, to ensure that
  // the change appears on the screen quickly.
  void fastPoll() {
    var missed = false, input = this;
    input.pollingFast = true;
    p() {
      var changed = input.poll();
      if (!changed && !missed) {
        missed = true;
        input.polling.set(60, p);
      } else {
        input.pollingFast = false;
        input.slowPoll();
      }
    }
    input.polling.set(20, p);
  }

  // Read input from the textarea, and update the document to match.
  // When something is selected, it is present in the textarea, and
  // selected (unless it is huge, in which case a placeholder is
  // used). When nothing is selected, the cursor sits after previously
  // seen text (can be empty), which is stored in prevInput (we must
  // not reset the textarea when typing, because that breaks IME).
  bool poll() {
    var cm = this.cm, input = this.textarea;
    String prevInput = this.prevInput;
    // Since this is called a *lot*, try to bail out as cheaply as
    // possible when it is clear that nothing happened. hasSelection
    // will be the case when there is a lot of text in the textarea,
    // in which case reading its value would be expensive.
    if (!cm.state.focused || (hasSelection(input) && prevInput.isEmpty) ||
        isReadOnly() || cm.options.disableInput || cm.state.keySeq != null)
      return false;
    // See paste handler for more on the fakedLastChar kludge
    if (cm.state.pasteIncoming && cm.state.fakedLastChar) {
      input.value = input.value.substring(0, input.value.length - 1);
      cm.state.fakedLastChar = false;
    }
    var text = input.value;
    // If nothing changed, bail.
    if (text == prevInput && !cm.somethingSelected()) return false;
    // Work around nonsensical selection resetting in IE9/10, and
    // inexplicable appearance of private area unicode characters on
    // some key combos in Mac (#2689).
    if (ie && ie_version >= 9 && this.textSelection == text ||
        mac && new RegExp(r'[\uf700-\uf7ff]').hasMatch(text)) {
      cm.display.input.reset();
      return false;
    }

    if (text.codeUnitAt(0) == 0x200b &&
        cm.doc.sel == cm.display.selForContextMenu && prevInput.isEmpty) {
      prevInput = "\u200b";
    }
    // Find the part of the input that is actually new
    var same = 0, l = min(prevInput.length, text.length);
    while (same < l && prevInput.codeUnitAt(same) == text.codeUnitAt(same)) ++same;

    var self = this;
    cm.runInOp(cm, () {
      applyTextInput(cm, text.substring(same), prevInput.length - same);

      // Don't leave long text in the textarea, since it makes further polling slow
      if (text.length > 1000 || text.indexOf("\n") > -1) input.value = self.prevInput = "";
      else self.prevInput = text;
    });
    return true;
  }

  void ensurePolled() {
    if (this.pollingFast && this.poll()) this.pollingFast = false;
  }

  void onKeyPress(KeyboardEvent e) {
    if (ie && ie_version >= 9) this.textSelection = null;
    this.fastPoll();
  }

  void onContextMenu(MouseEvent e) {
    var input = this, cm = input.cm, display = cm.display, te = input.textarea;
    var pos = cm.posFromMouse(cm, e), scrollPos = display.scroller.scrollTop;
    if (pos == null || presto) return; // Opera is difficult.

    // Reset the current text selection only if the click is done outside of the selection
    // and 'resetSelectionOnContextMenu' option is true.
    var reset = cm.options.resetSelectionOnContextMenu;
    if (reset && cm.doc.sel.contains(pos) == -1) {
      cm.operation(cm, cm.doc._setSelection(simpleSelection(pos), sel_dontScroll))();
    }

    var oldCSS = te.style.cssText;
    input.wrapper.style.position = "absolute";
    te.style.cssText = "position: fixed; width: 30px; height: 30px; top: " +
      "${e.client.y - 5}px; left: ${e.client.x - 5}px; z-index: 1000; background: " +
      (ie ? "rgba(255, 255, 255, .05)" : "transparent") +
      "; outline: none; border-width: 0; outline: none; overflow: hidden; " +
      "opacity: .05; filter: alpha(opacity=5);";
    var oldScrollY;
    if (webkit) oldScrollY = window.scrollY; // Work around Chrome issue (#2712)
    display.input.focus();
    if (webkit) window.scrollTo(null, oldScrollY);
    display.input.reset();
    // Adds "Select all" to context menu in FF
    if (!cm.somethingSelected()) te.value = input.prevInput = " ";
    input.contextMenuPending = true;
    display.selForContextMenu = cm.doc.sel;
    clearTimeout(display.detectingSelectAll);

    // Select-all will be greyed out if there's nothing to select, so
    // this adds a zero-width space so that we can later check whether
    // it got selected.
    prepareSelectAllHack() {
      if (te.selectionStart != null) {
        var selected = cm.somethingSelected();
        var extval = te.value = "\u200b" + (selected ? te.value : "");
        input.prevInput = selected ? "" : "\u200b";
        te.selectionStart = 1; te.selectionEnd = extval.length;
        // Re-set this, in case some other handler touched the
        // selection in the meantime.
        display.selForContextMenu = cm.doc.sel;
      }
    }
    rehide() {
      input.contextMenuPending = false;
      input.wrapper.style.position = "relative";
      te.style.cssText = oldCSS;
      if (ie && ie_version < 9) {
        display.scrollbars.setScrollTop(display.scroller.scrollTop = scrollPos);
      }

      // Try to detect the user choosing select-all
      if (te.selectionStart != null) {
        if (!ie || (ie && ie_version < 9)) prepareSelectAllHack();
        var i = 0, poll;
        poll = () {
          if (display.selForContextMenu == cm.doc.sel && te.selectionStart == 0) {
            cm.operation(cm, cm.commands['selectAll'](cm))();
          }
          else if (i++ < 10) display.detectingSelectAll = setTimeout(poll, 500);
          else display.input.reset();
        };
        display.detectingSelectAll = setTimeout(poll, 200);
      }
    }

    if (ie && ie_version >= 9) prepareSelectAllHack();
    if (captureRightClick) {
      e_stop(e);
      var mouseup;
      mouseup = () {
        off(window, "mouseup", mouseup);
        setTimeout(rehide, 20);
      };
      on(window, "mouseup", mouseup);
    } else {
      setTimeout(rehide, 50);
    }
  }

  void setUneditable(Element element) {}
  bool get needsContentAttribute => false;

}

class ContentEditableInput extends InputStyle {
  Timer gracePeriod = null;
  Element lastAnchorNode, lastFocusNode;
  int lastAnchorOffset, lastFocusOffset;
  Delayed polling = new Delayed();

  ContentEditableInput(CodeEditor cm) : super(cm);

  void init(Display display) {
    var input = this;
    div = display.lineDiv;
    div.contentEditable = "true";
    disableBrowserMagic(div);

    on(div, "paste", (Event e) {
      var pasted = e.clipboardData == null
          ? null : e.clipboardData.getData("text/plain");
      if (pasted != null) {
//        window.console.debug("paste");
        e.preventDefault();
        cm.replaceSelection(pasted, null, "paste");
      }
    });

    on(div, "compositionstart", (CompositionEvent e) {
      String data = e.data;
      input.composing = new Composing(cm.doc.sel, data, data);
      if (data == null) return;
      var prim = cm.doc.sel.primary();
      var line = cm.getLine(prim.head.line);
      var found = line.indexOf(data, max(0, prim.head.char - data.length));
      if (found > -1 && found <= prim.head.char)
        input.composing.sel = simpleSelection(
            new Pos(prim.head.line, found),
            new Pos(prim.head.line, found + data.length));
    });
    on(div, "compositionupdate", (CompositionEvent e) {
      input.composing.data = e.data;
    });
    on(div, "compositionend", (CompositionEvent e) {
      var ours = input.composing;
      if (ours == null) return;
      if (e.data != ours.startData && !new RegExp(r'\u200b').hasMatch(e.data)) {
        ours.data = e.data;
      }
      // Need a small delay to prevent other code (input event,
      // selection polling) from doing damage when fired right after
      // compositionend.
      setTimeout(() {
        if (!ours.handled)
          input.applyComposition(ours);
        if (input.composing == ours)
          input.composing = null;
      }, 50);
    });

    on(div, "touchstart", ([TouchEvent e]) {
      input.forceCompositionEnd();
    });

    on(div, "input", ([e]) {
      if (input.composing != null) return;
      if (!input.pollContent()) {
        cm.runInOp(input.cm, () { cm.regChange(); });
      }
    });

    onCopyCut(TouchEvent e) {
      if (cm.somethingSelected()) {
        lastCopied = cm.getSelections();
        if (e.type == "cut") cm.replaceSelection("", null, "cut");
      } else {
        var ranges = copyableRanges(cm);
        lastCopied = ranges.text;
        if (e.type == "cut") {
          cm.operation(cm, () {
            cm.setSelections(ranges.ranges, 0, sel_dontScroll);
            cm.replaceSelection("", null, "cut");
          })();
        }
      }
      // iOS exposes the clipboard API, but seems to discard content inserted into it
      if (e.clipboardData != null && !ios) {
        e.preventDefault();
        e.clipboardData.clearData();
        e.clipboardData.setData("text/plain", lastCopied.join("\n"));
      } else {
        // Old-fashioned briefly-focus-a-textarea hack
        var kludge = hiddenTextarea();
        var te = kludge.firstChild;
        DivElement lineSpace = cm.display.lineSpace;
        lineSpace.insertBefore(kludge, lineSpace.firstChild);
        te.value = lastCopied.join("\n");
        var hadFocus = document.activeElement;
        selectInput(te);
        setTimeout(() {
          kludge.remove();
          hadFocus.focus();
        }, 50);
      }
    }
    on(div, "copy", onCopyCut);
    on(div, "cut", onCopyCut);
  }

  DrawnSelection prepareSelection() {
    var result = cm.display.prepareSelection(cm, false);
    result.focus = this.cm.state.focused;
    return result;
  }

  void showSelection(DrawnSelection info) {
    if (info == null || cm.display.view.length == 0) return;
    if (info.focus) showPrimarySelection();
    showMultipleSelections(info);
  }

  void showPrimarySelection() {
    var sel = window.getSelection();
    var prim = cm.doc.sel.primary();
    var curAnchor = domToPos(cm, sel.anchorNode, sel.anchorOffset);
    var curFocus = domToPos(cm, sel.focusNode, sel.focusOffset);
    if (curAnchor != null && !curAnchor.bad &&
        curFocus != null && !curFocus.bad &&
        cmp(minPos(curAnchor, curFocus), prim.from()) == 0 &&
        cmp(maxPos(curAnchor, curFocus), prim.to()) == 0)
      return;

    var start = posToDOM(cm, prim.from());
    var end = posToDOM(cm, prim.to());
    if (start == null && end == null) return;

    var view = cm.display.view;
    var old = sel.rangeCount != 0 ? sel.getRangeAt(0) : null;
    if (start == null) {
      start = new NodeOffset(view[0].measure.map[2], 0);
    } else if (end == null) { // FIXME dangerously hacky
      var measure = view[view.length - 1].measure;
      var map = measure.maps
          ? measure.maps[measure.maps.length - 1] : measure.map;
      end = new NodeOffset(map[map.length - 1],
          map[map.length - 2] - map[map.length - 3]);
    }

    var rng;
    try { rng = range(start.node, start.offset, end.offset, end.node); }
    catch(e) {} // Our model of the DOM might be outdated, in which case the range we try to set can be impossible
    if (rng != null) {
      sel.removeAllRanges();
      sel.addRange(rng);
      if (old != null && sel.anchorNode == null) sel.addRange(old);
      else if (gecko) startGracePeriod();
    }
    rememberSelection();
  }

  void startGracePeriod() {
    clearTimeout(gracePeriod);
    this.gracePeriod = setTimeout(() {
      gracePeriod = null;
      if (selectionChanged())
        cm.operation(cm, () { cm.curOp.selectionChanged = true; })();
    }, 20);
  }

  void showMultipleSelections(DrawnSelection info) {
    removeChildrenAndAdd(cm.display.cursorDiv, info.cursors);
    removeChildrenAndAdd(cm.display.selectionDiv, info.selection);
  }

  void rememberSelection() {
    var sel = window.getSelection();
    lastAnchorNode = sel.anchorNode;
    lastAnchorOffset = sel.anchorOffset;
    lastFocusNode = sel.focusNode;
    lastFocusOffset = sel.focusOffset;
  }

  bool selectionInEditor() {
    var sel = window.getSelection();
    if (sel.rangeCount == 0) return false;
    var node = sel.getRangeAt(0).commonAncestorContainer;
    return contains(div, node);
  }

  void focus() {
    if (cm.options.readOnly != "nocursor") div.focus();
  }

  void blur() {
    div.blur();
  }

  Element getField() => this.div;

  bool supportsTouch() => true;

  void receivedFocus() {
    if (selectionInEditor()) {
      pollSelection();
    } else {
      cm.runInOp(cm, () { cm.curOp.selectionChanged = true; });
    }

    poll() {
      if (cm.state.focused) {
        pollSelection();
        polling.set(cm.options.pollInterval, poll);
      }
    }
    this.polling.set(cm.options.pollInterval, poll);
  }

  bool selectionChanged() {
    var sel = window.getSelection();
    return sel.anchorNode != this.lastAnchorNode ||
        sel.anchorOffset != this.lastAnchorOffset ||
        sel.focusNode != this.lastFocusNode ||
        sel.focusOffset != this.lastFocusOffset;
  }

  void pollSelection() {
    if (composing == null && gracePeriod == null && selectionChanged()) {
      var sel = window.getSelection();
      rememberSelection();
      var anchor = domToPos(cm, sel.anchorNode, sel.anchorOffset);
      var head = domToPos(cm, sel.focusNode, sel.focusOffset);
      if (anchor != null && head != null) {
        cm.runInOp(cm, () {
          cm.doc._setSelection(simpleSelection(anchor, head), sel_dontScroll);
          if (anchor.bad || head.bad) cm.curOp.selectionChanged = true;
        });
      }
    }
  }

  bool pollContent() {
    var display = cm.display, sel = cm.doc.sel.primary();
    var from = sel.from(), to = sel.to();
    if (from.line < display.viewFrom || to.line > display.viewTo - 1) {
      return false;
    }

    var fromIndex, fromLine, fromNode, toLine, toNode;
    if (from.line == display.viewFrom ||
        (fromIndex = display.findViewIndex(from.line)) == 0) {
      fromLine = display.view[0].line.lineNo();
      fromNode = display.view[0].node;
    } else {
      fromLine = display.view[fromIndex].line.lineNo();
      fromNode = display.view[fromIndex - 1].node.nextNode;
    }
    var toIndex = display.findViewIndex(to.line);
    if (toIndex == display.view.length - 1) {
      toLine = display.viewTo - 1;
      toNode = display.view[toIndex].node;
    } else {
      toLine = display.view[toIndex + 1].line.lineNo() - 1;
      toNode = display.view[toIndex + 1].node.previousNode;
    }

    var newText = cm.doc.splitLines(
        domTextBetween(cm, fromNode, toNode, fromLine, toLine));
    var oldText = cm.doc.getBetween(new Pos(fromLine, 0),
        new Pos(toLine, cm.doc._getLine(toLine).text.length));
    while (newText.length > 1 && oldText.length > 1) {
      if (lst(newText) == lst(oldText)) {
        newText.removeLast();
        oldText.removeLast();
        toLine--;
      }
      else if (newText[0] == oldText[0]) {
        newText.remove(0);
        oldText.remove(0);
        fromLine++;
      }
      else break;
    }

    var cutFront = 0, cutEnd = 0;
    var newTop = newText[0], oldTop = oldText[0];
    var maxCutFront = min(newTop.length, oldTop.length);
    while (cutFront < maxCutFront &&
        newTop.codeUnitAt(cutFront) == oldTop.codeUnitAt(cutFront)) {
      ++cutFront;
    }
    String newBot = lst(newText), oldBot = lst(oldText);
    var maxCutEnd = min(newBot.length - (newText.length == 1 ? cutFront : 0),
                        oldBot.length - (oldText.length == 1 ? cutFront : 0));
    while (cutEnd < maxCutEnd &&
           newBot.codeUnitAt(newBot.length - cutEnd - 1) ==
           oldBot.codeUnitAt(oldBot.length - cutEnd - 1)) {
      ++cutEnd;
    }

    newText[newText.length - 1] = newBot.substring(0, newBot.length - cutEnd);
    newText[0] = newText[0].substring(cutFront);

    var chFrom = new Pos(fromLine, cutFront);
    int chEnd = oldText.length > 0 ? lst(oldText).length - cutEnd : 0;
    var chTo = new Pos(toLine, chEnd);
    if (newText.length > 1 || newText[0] != null || cmp(chFrom, chTo) != 0) {
      cm.doc.replaceRange(newText, chFrom, chTo, "+input");
      return true;
    }
    return false;
  }

  void ensurePolled() {
    forceCompositionEnd();
  }

  void reset([bool typing = false]) {
    forceCompositionEnd();
  }

  void forceCompositionEnd() {
    if (composing == null || composing.handled) return;
    applyComposition(composing);
    composing.handled = true;
    div.blur();
    div.focus();
  }

  void applyComposition(Composing composing) {
    if (composing.data != null && composing.data != composing.startData) {
      cm.operation(cm, () {
        applyTextInput(this.cm, composing.data, 0, composing.sel);
      })();
    }
  }

  void setUneditable(Element node) {
    node.setAttribute("contenteditable", "false");
  }

  void onKeyPress(KeyboardEvent e) {
    e.preventDefault();
    cm.operation(cm, () {
      int code = e.charCode == null ? e.keyCode : e.charCode;
      applyTextInput(cm, new String.fromCharCode(code), 0);
    })();
  }

  void onContextMenu(e) {}
  void resetPosition() {}
  bool get needsContentAttribute => true;

}

CoverNode posToDOM(CodeEditor cm, Pos pos) {
  LineView view = cm.doc.findViewForLine(pos.line);
  if (view == null || view.hidden) return null;
  var line = cm.doc._getLine(pos.line);
  var info = cm.doc.mapFromLineView(view, line, pos.line);

//  var order = cm.doc.getOrder(line), side = "left";
//  if (order != null && order != false) {
//    var partPos = cm.getBidiPartAt(order, pos.char);
//    side = partPos % 2 != 0 ? "right" : "left";
//  }
  var result = cm.doc.nodeAndOffsetInLineMap(info.map, pos.char, "left");
  result.offset = result.collapse == "right" ? result.end : result.start;
  return result;
}

Pos badPos(pos, bad) {
  if (bad) {
    return new BadPos(pos);
  } else {
    return pos;
  }
}

Pos domToPos(CodeEditor cm, Node node, int offset) {
  Node lineNode;
  if (node == cm.display.lineDiv) {
    if (offset < cm.display.lineDiv.childNodes.length) {
      lineNode = cm.display.lineDiv.childNodes[offset];
    }
    if (lineNode == null) {
      return badPos(cm.doc.clipPos(new Pos(cm.display.viewTo - 1)), true);
    }
    node = null;
    offset = 0;
  } else {
    for (lineNode = node;; lineNode = lineNode.parentNode) {
      if (lineNode == null || lineNode == cm.display.lineDiv) return null;
      if (lineNode.parentNode != null && lineNode.parentNode == cm.display.lineDiv) break;
    }
  }
  for (var i = 0; i < cm.display.view.length; i++) {
    var lineView = cm.display.view[i];
    if (lineView.node == lineNode)
      return locateNodeInLineView(lineView, node, offset);
  }
  return null;
}

Pos locateNodeInLineView(LineView lineView, Node node, int offset) {
  var wrapper = lineView.text.firstChild, bad = false;
  if (node == null || !contains(wrapper, node)) {
    return badPos(new Pos(lineView.line.lineNo(), 0), true);
  }
  if (node == wrapper) {
    bad = true;
    node = wrapper.childNodes[offset];
    offset = 0;
    if (node == null) {
      var line = lineView.rest != null ? lst(lineView.rest) : lineView.line;
      return badPos(new Pos(line.lineNo(), line.text.length), bad);
    }
  }

  Node textNode = node.nodeType == 3 ? node : null, topNode = node;
  if (textNode == null &&
      node.childNodes.length == 1 && node.firstChild.nodeType == 3) {
    textNode = node.firstChild;
    if (offset != 0) offset = textNode.nodeValue.length;
  }
  while (topNode.parentNode != wrapper) topNode = topNode.parentNode;
  var measure = lineView.measure, maps = measure.maps;

  Pos find(Object textNode, Object topNode, int offset) {
    for (var i = -1; i < (maps != null ? maps.length : 0); i++) {
      var map = i < 0 ? measure.map : maps[i];
      for (var j = 0; j < map.length; j += 3) {
        var curNode = map[j + 2];
        if (curNode == textNode || curNode == topNode) {
          var line = (i < 0 ? lineView.line : lineView.rest[i]).lineNo();
          var ch = map[j] + offset;
          if (offset < 0 || curNode != textNode) {
            ch = map[j + (offset != 0 ? 1 : 0)];
          }
          return new Pos(line, ch);
        }
      }
    }
    return null;
  }
  var found = find(textNode, topNode, offset);
  if (found != null) return badPos(found, bad);

  // FIXME this is all really shaky. might handle the few cases it needs to handle, but likely to cause problems
  var after = topNode.nextNode;
  for (var dist = textNode != null ? textNode.nodeValue.length - offset : 0;
      after;
      after = after.nextNode) {
    found = find(after, after.firstChild, 0);
    if (found != null) {
      return badPos(new Pos(found.line, found.char - dist), bad);
    } else {
      dist += after.text.length;
    }
  }
  for (var before = topNode.previousNode,
      dist = offset; before;
      before = before.previousNode) {
    found = find(before, before.firstChild, -1);
    if (found != null) {
      return badPos(new Pos(found.line, found.char + dist), bad);
    } else {
      dist += after.text.length;
    }
  }
  return null;
}

String domTextBetween(CodeEditor cm, Element from, Element to,
                      int fromLine, int toLine) {
  var text = "", closing = false;

  recognizeMarker(int id) {
    return (TextMarker marker) { return marker.id == id; };
  }

  walk(Element node) {
    if (node.nodeType == 1) {
      var cmText = node.getAttribute("cm-text");
      if (cmText != null) {
        if (cmText == "") {
          cmText = node.text.replaceAll(new RegExp(r'\u200b'), "");
        }
        text += cmText;
        return;
      }
      var markerID = node.getAttribute("cm-marker"), range;
      if (markerID != null) {
        var found = cm.findMarks(
            new Pos(fromLine, 0),
            new Pos(toLine + 1, 0),
            recognizeMarker(int.parse(markerID)));
        if (found.length > 0 && (range = found[0].find()) != null) {
          text += cm.doc.getBetween(range.from, range.to).join("\n");
        }
        return;
      }
      if (node.getAttribute("contenteditable") == "false") return;
      for (var i = 0; i < node.childNodes.length; i++) {
        walk(node.childNodes[i]);
      }
      var closeExpr = new RegExp(r'^(pre|div|p)$', caseSensitive: false);
      if (closeExpr.hasMatch(node.nodeName)) {
        closing = true;
      }
    } else if (node.nodeType == 3) {
      var val = node.nodeValue;
      if (val == null) return;
      if (closing) {
        text += "\n";
        closing = false;
      }
      text += val;
    }
  }

  for (;;) {
    walk(from);
    if (from == to) break;
    from = from.nextElementSibling;
  }
  return text;
}

class Composing {
  var sel;
  String data, startData;
  bool handled;

  Composing(this.sel, this.data, this.startData) {
    handled = false;
  }
}

class CopyableRanges {
  List<String> text;
  List<Range> ranges;

  CopyableRanges(this.text, this.ranges);
}

class NodeOffset {
  var node, offset;

  NodeOffset(this.node, this.offset);
}

class BadPos extends Pos {

  BadPos(Pos pos) : super(pos.line, pos.char);

  bool get bad => true;
}

