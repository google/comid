// Copyright (c) 2015, the Comid Authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

part of comid;

// The display handles the DOM integration, both for input reading
// and content drawing. It holds references to DOM nodes and
// display-related state.
class Displ implements Display {
  DivElement wrapper;
  TextAreaElement input;
  DivElement inputDiv, /*scrollbarH, scrollbarV,*/ scrollbarFiller, gutterFiller;
  DivElement lineDiv, selectionDiv, cursorDiv, measure, lineMeasure, lineSpace;
  DivElement mover, sizer, heightForcer, gutters, lineGutter, scroller;
  var sizerWidth, reportedViewFrom, reportedViewTo, renderedView; // NEW
  int nativeBarWidth, barHeight, barWidth; // NEW
  bool scrollbarsClipped; // NEW
  NullScrollbars scrollbars; // NEW
  bool contextMenuPending = false; // NEW

  int viewFrom, viewTo;
  List<LineView> view;
  var externalMeasured;
  num viewOffset;
  int lastWrapHeight, lastWrapWidth;
  var updateLineNumbers;
  int lineNumWidth, lineNumInnerWidth;
  var lineNumChars;
  String prevInput;
  bool alignWidgets;
  bool pollingFast;
  Delayed poll;
  num cachedCharWidth, cachedTextHeight;
  Padding cachedPaddingH;
  bool inaccurateSelection;
  Line maxLine;
  int maxLineLength;
  bool maxLineChanged;
  int wheelDX, wheelDY, wheelStartX, wheelStartY;
  bool shift;
  var selForContextMenu;
  bool disabled;
  Element currentWheelTarget;
  String inputHasSelection; // This is a hack for IE.
  int knownScrollbarWidth;
  var detectingSelectAll;
  Timer blinker;

  /// Create a new Display. If [place] is a Node then the Div element will be
  /// appended to it. [place] may be null, in which case the Div is not attached
  /// to anything. It may also be an arbitrary function which takes the Div as
  /// a parameter.
  Displ(var place, Doc doc) {
    // The semihidden textarea that is focused when the editor is
    // focused, and receives input.
    var inputElt = elt("textarea", null, null,
      "position: absolute; padding: 0; width: 1px; height: 1em; outline: none");
    input = inputElt as TextAreaElement;
    // The textarea is kept positioned near the cursor to prevent the
    // fact that it'll be scrolled into view on input from scrolling
    // our fake cursor out of view. On webkit, when wrap=off, paste is
    // very slow. So make the area wide instead.
    if (webkit) input.style.width = "1000px";
    else input.setAttribute("wrap", "off");
    // If border: 0; -- iOS fails to open keyboard (issue #1287)
    if (ios) input.style.border = "1px solid black";
    input.setAttribute("autocorrect", "off");
    input.setAttribute("autocapitalize", "off");
    input.setAttribute("spellcheck", "false");

    // Wraps and hides input textarea
    inputDiv = eltdiv([input], null,
        "overflow: hidden; position: relative; width: 3px; height: 0px;");
// NEW TO REMOVE
//    // The fake scrollbar elements.
//    scrollbarH = eltdiv(
//        [eltdiv(null, null, "height: 100%; min-height: 1px")],
//        "CodeMirror-hscrollbar");
//    scrollbarV = eltdiv(
//        [eltdiv(null, null, "min-width: 1px")],
//        "CodeMirror-vscrollbar");
    // Covers bottom-right square when both scrollbars are present.
    scrollbarFiller = eltdiv(null, "CodeMirror-scrollbar-filler");
    scrollbarFiller.setAttribute("not-content", "true");
    // Covers bottom of gutter when coverGutterNextToScrollbar is on
    // and h scrollbar is present.
    gutterFiller = eltdiv(null, "CodeMirror-gutter-filler");
    gutterFiller.setAttribute("not-content", "true");
    // Will contain the actual code, positioned to cover the viewport.
    lineDiv = eltdiv(null, "CodeMirror-code");
    // Elements are added to these to represent selection and cursors.
    selectionDiv = eltdiv(null, null, "position: relative; z-index: 1");
    cursorDiv = eltdiv(null, "CodeMirror-cursors");
    // A visibility: hidden element used to find the size of things.
    measure = eltdiv(null, "CodeMirror-measure");
    // When lines outside of the viewport are measured, they are drawn in this.
    lineMeasure = eltdiv(null, "CodeMirror-measure");
    // Wraps everything that needs to exist inside the
    // vertically-padded coordinate system
    lineSpace = eltdiv(
        [measure, lineMeasure, selectionDiv, cursorDiv, lineDiv],
        null, "position: relative; outline: none");
    // Moved around its parent to cover visible view.
    mover = eltdiv([eltdiv([lineSpace], "CodeMirror-lines")], null,
        "position: relative");
    // Set to the height of the document, allowing scrolling.
    sizer = eltdiv([mover], "CodeMirror-sizer");
    sizerWidth = null;
    // Behavior of elts with overflow: auto and padding is
    // inconsistent across browsers. This is used to ensure the
    // scrollable area is big enough.
    heightForcer = eltdiv(null, null,
        "position: absolute; height: ${scrollerGap}px; width: 1px;");
    // Will contain the gutters, if any.
    gutters = eltdiv(null, "CodeMirror-gutters");
    lineGutter = null;
    // Actual scrollable element.
    scroller = eltdiv(
        [sizer, heightForcer, gutters],
        "CodeMirror-scroll");
    scroller.setAttribute("tabIndex", "-1");
    // The element in which the editor lives.
    wrapper = eltdiv(
        [inputDiv, scrollbarFiller, gutterFiller, scroller],
        "CodeMirror");

    // Needed to hide big blue blinking cursor on Mobile Safari
    if (ios) input.style.width = "0px";
    if (!webkit) scroller.draggable = true;
    // Needed to handle Tab key in KHTML
    if (khtml) {
      inputDiv.style.height = "1px";
      inputDiv.style.position = "absolute";
    }

    if (place != null) {
      if (place is Node) place.append(wrapper);
      else place(wrapper);
    }

    // Current rendered range (may be bigger than the view window).
    viewFrom = viewTo = doc.first;
    reportedViewFrom = reportedViewTo = doc.first;
    // Information about the rendered lines.
    view = [];
    renderedView = null;
    // Holds info about a single rendered line when it was rendered
    // for measurement, while not in view.
    externalMeasured = null;
    // Empty space (in pixels) above the view
    viewOffset = 0;
    lastWrapHeight = lastWrapWidth = 0;
    updateLineNumbers = null;

    nativeBarWidth = barHeight = barWidth = 0;
    scrollbarsClipped = false;

    // Used to only resize the line number gutter when necessary (when
    // the amount of lines crosses a boundary that makes its width change)
    lineNumWidth = lineNumInnerWidth = lineNumChars = 0;
    // See readInput and resetInput
    prevInput = "";
    // Set to true when a non-horizontal-scrolling line widget is
    // added. As an optimization, line widget aligning is skipped when
    // this is false.
    alignWidgets = false;
    // Flag that indicates whether we expect input to appear real soon
    // now (after some event like 'keypress' or 'input') and are
    // polling intensively.
    pollingFast = false;
    // Self-resetting timeout for the poller
    poll = new Delayed();

    cachedCharWidth = cachedTextHeight = 0;
    var cachedPaddingH = null;

    // Tracks when resetInput has punted to just putting a short
    // string into the textarea instead of the full selection.
    inaccurateSelection = false;

    // Tracks the maximum line length so that the horizontal scrollbar
    // can be kept static when scrolling.
    maxLine = null;
    maxLineLength = 0;
    maxLineChanged = false;

    // Used for measuring wheel scrolling granularity
    wheelDX = wheelDY = wheelStartX = wheelStartY = 0;

    // True when shift is held down.
    shift = false;

    // Used to track whether anything happened since the context menu
    // was opened.
    selForContextMenu = null;
  }

  // Computes display.scroller.scrollLeft + display.gutters.offsetWidth,
  // but using getBoundingClientRect to get a sub-pixel-accurate
  // result.
  compensateForHScroll() {
    return scroller.getBoundingClientRect().left -
        sizer.getBoundingClientRect().left;
  }

  // Prepare DOM reads needed to update the scrollbars. Done in one
  // shot to minimize update/measure roundtrips.
  ScrollMeasure measureForScrollbars(CodeEditor cm) {
    var gutterW = gutters.offsetWidth;
    var docH = (cm.doc.height + paddingVert()).round();
    return new ScrollMeasure(
      scroller.clientHeight,
      wrapper.clientHeight,
      scroller.scrollWidth,
      scroller.clientWidth,
      wrapper.clientWidth,
      cm.options.fixedGutter ? gutterW : 0,
      docH,
      docH + scrollGap() + barHeight,
      nativeBarWidth,
      gutterW
    );
  }

  initScrollbars(CodeEditor cm) {
    if (scrollbars != null) {
      scrollbars.clear();
//      if (!scrollbars.addClass.isEmpty)
//        rmClass(wrapper, scrollbars.addClass);
    }

    scrollbars = cm.scrollbarModel[cm.options.scrollbarStyle](
        (node) {
          wrapper.insertBefore(node, cm.display.scrollbarFiller);
          cm.on(node, "mousedown", (e) {
            if (cm.state.focused) setTimeout(cm.focusInput, 0);
          });
          node.setAttribute("not-content", "true");
        },
        (pos, axis) {
          if (axis == "horizontal") cm.setScrollLeft(pos);
          else cm.setScrollTop(pos);
        },
        cm);
//    if (scrollbars.addClass)
//      addClass(cm.display.wrapper, cm.display.scrollbars.addClass);
  }

  updateScrollbars(cm, [measure]) {
    if (measure == null) measure = measureForScrollbars(cm);
    var startWidth = barWidth, startHeight = barHeight;
    updateScrollbarsInner(cm, measure);
    for (var i = 0; i < 4 && startWidth != barWidth || startHeight != barHeight; i++) {
      if (startWidth != barWidth && cm.options.lineWrapping)
        updateHeightsInViewport(cm);
      updateScrollbarsInner(cm, measureForScrollbars(cm));
      startWidth = barWidth; startHeight = barHeight;
    }
  }

  // Re-synchronize the fake scrollbars with the actual size of the
  // content.
  updateScrollbarsInner(CodeEditor cm, ScrollMeasure measure) {
    Rect sizes = scrollbars.update(measure);

    sizer.style.paddingRight = "${barWidth = sizes.right}px";
    sizer.style.paddingBottom = "${barHeight = sizes.bottom}px";

    if (sizes.right != 0 && sizes.bottom != 0) {
      scrollbarFiller.style.display = "block";
      scrollbarFiller.style.height = "${sizes.bottom}px";
      scrollbarFiller.style.width = "${sizes.right}px";
    } else {
      scrollbarFiller.style.display = "";
    }
    if (sizes.bottom != 0 && cm.options.coverGutterNextToScrollbar && cm.options.fixedGutter) {
      gutterFiller.style.display = "block";
      gutterFiller.style.height = "${sizes.bottom}px";
      gutterFiller.style.width = "${measure.gutterWidth}px";
    } else {
      gutterFiller.style.display = "";
    }
  }

  maybeClipScrollbars() {
    if (!scrollbarsClipped && scroller.offsetWidth != 0) {
      nativeBarWidth = scroller.offsetWidth - scroller.clientWidth;
      heightForcer.style.height = "${scrollGap()}px";
      sizer.style.marginBottom = "${-nativeBarWidth}px";
      sizer.style.borderRightWidth = "${scrollGap()}px";
      scrollbarsClipped = true;
    }
  }

  // Compute the lines that are visible in a given viewport (defaults
  // the the current scroll position). viewport may contain top,
  // height, and ensure (see op.scrollToPos) properties.
  Span visibleLines(Document doc, [Viewport viewport]) {
    num top = viewport != null && viewport.top != -1
        ? max(0, viewport.top) : scroller.scrollTop;
    top = (top - paddingTop()).floor();
    num bottom = viewport != null && viewport.bottom != null
        ? viewport.bottom : top + wrapper.clientHeight;

    int from = doc.lineAtHeight(doc, top);
    int to = doc.lineAtHeight(doc, bottom);
    // Ensure is a {from: {line, ch}, to: {line, ch}} object (Range), and
    // forces those lines into the viewport (if possible).
    if (viewport != null && viewport.ensure != null) {
      int ensureFrom = viewport.ensure.from.line;
      int ensureTo = viewport.ensure.to.line;
      if (ensureFrom < from) {
        from = ensureFrom;
        to = doc.lineAtHeight(doc,
            doc.heightAtLine(doc._getLine(ensureFrom)) +
                wrapper.clientHeight);
      } else if (min(ensureTo, doc.lastLine()) >= to) {
        from = doc.lineAtHeight(doc,
            doc.heightAtLine(doc._getLine(ensureTo)) -
                wrapper.clientHeight);
        to = ensureTo;
      }
    }
    return new Span(from,  max(to, from + 1));
  }

  // Redraw the selection and/or cursor
  DrawnSelection drawSelection(cm) {
    var display = cm.display, doc = cm.doc, result = new DrawnSelection();
    var curFragment = result.cursors = document.createDocumentFragment();
    var selFragment = result.selection = document.createDocumentFragment();

    for (var i = 0; i < doc.sel.ranges.length; i++) {
      var range = doc.sel.ranges[i];
      var collapsed = range.empty();
      if (collapsed || cm.options.showCursorWhenSelecting)
        drawSelectionCursor(cm, range, curFragment);
      if (!collapsed)
        drawSelectionRange(cm, range, selFragment);
    }

    // Move the hidden textarea near the cursor to prevent scrolling artifacts
    if (cm.options.moveInputWithCursor) {
      var headPos = cm.cursorCoords(doc.sel.primary().head, "div");
      var wrapOff = display.wrapper.getBoundingClientRect();
      var lineOff = display.lineDiv.getBoundingClientRect();
      result.teTop = max(0, min(display.wrapper.clientHeight - 10,
                                headPos.top + lineOff.top - wrapOff.top));
      result.teLeft = max(0, min(display.wrapper.clientWidth - 10,
                                 headPos.left + lineOff.left - wrapOff.left));
    }

    return result;
  }

  showSelection(cm, drawn) {
    removeChildrenAndAdd(cm.display.cursorDiv, drawn.cursors);
    removeChildrenAndAdd(cm.display.selectionDiv, drawn.selection);
    if (drawn.teTop != null) {
      cm.display.inputDiv.style.top = "${drawn.teTop}px";
      cm.display.inputDiv.style.left = "${drawn.teLeft}px";
    }
  }

  updateSelection(cm) {
    showSelection(cm, drawSelection(cm));
  }

  // Draws a cursor for the given range
  drawSelectionCursor(CodeEditor cm, Range range, Node output) {
    var pos = cm.doc.cursorCoords(range.head, "div", null, null,
        !cm.options.singleCursorHeightPerLine);

    var cursor = output.append(elt("div", "\u00a0", "CodeMirror-cursor"));
    cursor.style.left = "${pos.left}px";
    cursor.style.top = "${pos.top}px";
    cursor.style.height = (max(0, pos.bottom - pos.top) *
        cm.options.cursorHeight).toString() + "px";

    if (pos.other != null) {
      // Secondary cursor, shown when on a 'jump' in bi-directional text
      var otherCursor = output.append(
          eltdiv("\u00a0", "CodeMirror-cursor CodeMirror-secondarycursor"));
      otherCursor.style.display = "";
      otherCursor.style.left = "${pos.other.left}px";
      otherCursor.style.top = "${pos.other.top}px";
      otherCursor.style.height =
          ((pos.other.bottom - pos.other.top) * .85).toString() + "px";
    }
  }

  // Draws the given range as a highlighted selection
  drawSelectionRange(CodeEditor cm, range, output) {
    Displ display = cm.display;
    Document doc = cm.doc;
    var fragment = document.createDocumentFragment();
    var padding = paddingH();
    num leftSide = padding.left;
    num wid = display.sizerWidth == null ? 0 : display.sizerWidth;
    num rightSide = max(wid, displayWidth() - display.sizer.offsetLeft) - padding.right;

    add(num left, num top, num width, num bottom) {
      if (top < 0) top = 0;
      top = top.round();
      bottom = bottom.round();
      fragment.append(eltdiv(null,
          "CodeMirror-selected", "position: absolute; " +
          "left: ${left}px; top: ${top}px; width: " +
          "${width == null ? rightSide - left : width}px; " +
          "height: ${bottom - top}px"));
    }

    drawForLine(line, [fromArg, toArg]) {
      var lineObj = doc._getLine(line);
      var lineLen = lineObj.text.length;
      Rect start, end;
      Rect coords(ch, bias) {
        return doc.charCoords(new Pos(line, ch), "div", lineObj, bias);
      }

      cm.iterateBidiSections(doc.getOrder(lineObj),
          fromArg == null ? 0 : fromArg,
          toArg == null ? lineLen : toArg,
          (from, to, dir) {
        Rect leftPos = coords(from, "left"), rightPos;
        var left, right;
        if (from == to) {
          rightPos = leftPos;
          left = right = leftPos.left;
        } else {
          rightPos = coords(to - 1, "right");
          if (dir == "rtl") { var tmp = leftPos; leftPos = rightPos; rightPos = tmp; }
          left = leftPos.left;
          right = rightPos.right;
        }
        if (fromArg == null && from == 0) left = leftSide;
        if (rightPos.top - leftPos.top > 3) { // Different lines, draw top part
          add(left, leftPos.top, null, leftPos.bottom);
          left = leftSide;
          if (leftPos.bottom < rightPos.top) add(left, leftPos.bottom, null, rightPos.top);
        }
        if (toArg == null && to == lineLen) right = rightSide;
        if (start == null || leftPos.top < start.top ||
            leftPos.top == start.top && leftPos.left < start.left) {
          start = leftPos;
        }
        if (end == null || rightPos.bottom > end.bottom ||
            rightPos.bottom == end.bottom && rightPos.right > end.right) {
          end = rightPos;
        }
        if (left < leftSide + 1) left = leftSide;
        add(left, rightPos.top, right - left, rightPos.bottom);
      });
      return new DrawBox(start, end);
    }

    var sFrom = range.from(), sTo = range.to();
    if (sFrom.line == sTo.line) {
      drawForLine(sFrom.line, sFrom.char, sTo.char);
    } else {
      var fromLine = doc._getLine(sFrom.line), toLine = doc._getLine(sTo.line);
      var singleVLine = fromLine.visualLine() == toLine.visualLine();
      Rect leftEnd = drawForLine(sFrom.line, sFrom.char, singleVLine ? fromLine.text.length + 1 : null).end;
      Rect rightStart = drawForLine(sTo.line, singleVLine ? 0 : null, sTo.char).start;
      if (singleVLine) {
        if (leftEnd.top < rightStart.top - 2) {
          add(leftEnd.right, leftEnd.top, null, leftEnd.bottom);
          add(leftSide, rightStart.top, rightStart.left, rightStart.bottom);
        } else {
          add(leftEnd.right, leftEnd.top, rightStart.left - leftEnd.right, leftEnd.bottom);
        }
      }
      if (leftEnd.bottom < rightStart.top)
        add(leftSide, leftEnd.bottom, null, rightStart.top);
    }

    output.append(fragment);
  }

  // Cursor-blinking
  restartBlink(cm) {
    if (!cm.state.focused) return;
    stopBlink();
    var on = true;
    blinkCallback(Timer t) {
      cursorDiv.style.visibility = (on = !on) ? "" : "hidden";
    }
    cursorDiv.style.visibility = "";
    if (cm.options.cursorBlinkRate > 0) {
      var delay = new Duration(milliseconds: cm.options.cursorBlinkRate);
      blinker = new Timer.periodic(delay, blinkCallback);
    } else if (cm.options.cursorBlinkRate < 0)
      cursorDiv.style.visibility = "hidden";
  }
  stopBlink() {
    if (blinker != null) blinker.cancel();
    blinker = null;
  }

  // HIGHLIGHT WORKER

  startWorker(CodeEditor cm, time) {
    if (cm.doc.mode.hasStartState && cm.doc.frontier < cm.display.viewTo)
      cm.state.highlight.set(time, bind(highlightWorker, cm));
  }

  highlightWorker(CodeEditor cm) {
    Document doc = cm.doc;
    if (doc.frontier < doc.first) doc.frontier = doc.first;
    if (doc.frontier >= cm.display.viewTo) return;
    DateTime end = new DateTime.now().add(
        new Duration(milliseconds: cm.options.workTime));
    var state = CodeEditor.copyState(doc.mode, cm.getStateBefore(doc.frontier));
    List changedLines = [];

    int to = min(doc.first + doc.size, cm.display.viewTo + 500);
    doc.iter(doc.frontier, to, (Line line) {
      if (doc.frontier >= cm.display.viewFrom) { // Visible
        var oldStyles = line.styles;
        var highlighted = cm.highlightLine(line, state, true);
        line.styles = highlighted.styles;
        var oldCls = line.styleClasses, newCls = highlighted.classes;
        if (newCls != null) line.styleClasses = newCls;
        else if (oldCls != null) line.styleClasses = null;
        var ischange = oldStyles == null || oldStyles.length != line.styles.length ||
          oldCls != newCls && (oldCls == null || newCls == null ||
          oldCls.bgClass != newCls.bgClass || oldCls.textClass != newCls.textClass);
        for (var i = 0; !ischange && i < oldStyles.length; ++i) ischange = oldStyles[i] != line.styles[i];
        if (ischange) changedLines.add(doc.frontier);
        line.stateAfter = CodeEditor.copyState(doc.mode, state);
      } else {
        cm.processLine(line.text, state);
        line.stateAfter = doc.frontier % 5 == 0 ? CodeEditor.copyState(doc.mode, state) : null;
      }
      ++doc.frontier;
      if (new DateTime.now().compareTo(end) > 0) {
        startWorker(cm, cm.options.workDelay);
        return true;
      }
    });
    if (changedLines.length != 0) cm.runInOp(cm, () {
      for (var i = 0; i < changedLines.length; i++)
        cm.regLineChange(changedLines[i], "text");
    });
  }

  int paddingTop() => lineSpace.offsetTop;
  int paddingVert() => mover.offsetHeight - lineSpace.offsetHeight;
  Padding paddingH() {
    if (cachedPaddingH != null) return cachedPaddingH;
    Element e = removeChildrenAndAdd(measure, eltpre("x"));
    var style = e.getComputedStyle();
    prs(String x) {
      if (x.endsWith('px')) x = x.substring(0, x.length - 2);
      return num.parse(x, (s) => double.NAN);
    }
    var data = new Padding(prs(style.paddingLeft),
                           prs(style.paddingRight));
    if (!data.left.isNaN && !data.right.isNaN) {
      cachedPaddingH = data;
    }
    return data;
  }

  scrollGap() {
    return scrollerGap - nativeBarWidth;
  }
  displayWidth() {
    return scroller.clientWidth - scrollGap() - barWidth;
  }
  displayHeight() {
    return scroller.clientHeight - scrollGap() - barHeight;
  }

  Element measureText;
  // Compute the default text height.
  num textHeight() {
    if (cachedTextHeight != 0) return cachedTextHeight;
    if (measureText == null) {
      measureText = eltpre();
      // Measure a bunch of lines, for browsers that compute
      // fractional heights.
      for (var i = 0; i < 49; ++i) {
        measureText.append(new Text("x"));
        measureText.append(elt("br"));
      }
      measureText.append(new Text("x"));
    }
    removeChildrenAndAdd(measure, measureText);
    var height = measureText.offsetHeight / 50;
    if (height > 3) cachedTextHeight = height;
    removeChildren(measure);
    return height == 0 ? 1 : height;
  }

  // Compute the default character width.
  num charWidth() {
    if (cachedCharWidth != 0) return cachedCharWidth;
    var anchor = eltspan("xxxxxxxxxx");
    var pre = eltpre([anchor]);
    removeChildrenAndAdd(measure, pre);
    var rect = anchor.getBoundingClientRect();
    num width = (rect.right - rect.left) / 10;
    if (width > 2) cachedCharWidth = width; // Why 2 instead of 10?
    return width == 0 ? 10 : width;
  }

  // Clear the view.
  void resetView(CodeEditor cm) {
    viewFrom = viewTo = cm.doc.first;
    view = [];
    viewOffset = 0;
  }

  // Find the view element corresponding to a given line. Return null
  // when the line isn't visible.
  int findViewIndex(int n) {
    if (n >= viewTo) return -1;
    n -= viewFrom;
    if (n < 0) return -1;
    for (var i = 0; i < view.length; i++) {
      n -= view[i].size;
      if (n < 0) return i;
    }
    return -1;
  }

  LineWidget addLineWidget(CodeEditor cm, dynamic handle, Node node,
                           LineWidgetOptions options) {
    // handle may be int or LineHandle
    var widget = new LineWidget(cm, node, options);
    if (widget.noHScroll) cm.display.alignWidgets = true;
    cm.doc.changeLine(handle, "widget", (Line line) {
      if (line.widgets == null) line.widgets = [];
      var widgets = line.widgets;
      if (widget.insertAt == -1) {
        widgets.add(widget);
      } else {
        widgets.insert(min(widgets.length-1, max(0, widget.insertAt)), widget);
      }
      widget.line = line;
      if (!line.isHidden()) {
        var aboveVisible = cm.doc.heightAtLine(line) < cm.doc.scrollTop;
        line.updateLineHeight(line.height + widget.widgetHeight());
        if (aboveVisible) cm.addToScrollPos(null, widget.height);
        cm.curOp.forceUpdate = true;
      }
      return true;
    });
    return widget;
  }

  // Does the actual updating of the line display. Bails out
  // (returning false) when there is nothing to be done and forced is
  // false.
  bool updateDisplayIfNeeded(CodeEditor cm, DisplayUpdate update) {
    var display = cm.display, doc = cm.doc;

    if (update.editorIsHidden) {
      resetView(cm);
      return false;
    }

    // Bail out if the visible area is already rendered and nothing changed.
    if (!update.force &&
        update.visible.from >= display.viewFrom && update.visible.to <= display.viewTo &&
        (display.updateLineNumbers == null || display.updateLineNumbers >= display.viewTo) &&
        display.renderedView == display.view && cm.countDirtyView() == 0)
      return false;

    if (cm.maybeUpdateLineNumberWidth()) {
      resetView(cm);
      update.dims = getDimensions(cm);
    }

    // Compute a suitable new viewport (from & to)
    var end = doc.first + doc.size;
    var from = max(update.visible.from - cm.options.viewportMargin, doc.first);
    var to = min(end, update.visible.to + cm.options.viewportMargin);
    if (display.viewFrom < from && from - display.viewFrom < 20) from = max(doc.first, display.viewFrom);
    if (display.viewTo > to && display.viewTo - to < 20) to = min(end, display.viewTo);
    if (sawCollapsedSpans) {
      from = cm.doc.visualLineNo(from);
      to = cm.doc.visualLineEndNo(to);
    }

    var different = from != display.viewFrom || to != display.viewTo ||
      display.lastWrapHeight != update.wrapperHeight || display.lastWrapWidth != update.wrapperWidth;
    cm.adjustView(from, to);

    display.viewOffset = cm.doc.heightAtLine(cm.doc._getLine(display.viewFrom));
    // Position the mover div to align with the current scroll position
    cm.display.mover.style.top = "${display.viewOffset}px";

    var toUpdate = cm.countDirtyView();
    if (!different && toUpdate == 0 && !update.force && display.renderedView == display.view &&
        (display.updateLineNumbers == null || display.updateLineNumbers >= display.viewTo))
      return false;

    // For big changes, we hide the enclosing element during the
    // update, since that speeds up the operations on most browsers.
    Element focused = activeElt();
    if (toUpdate > 4) display.lineDiv.style.display = "none";
    patchDisplay(cm, display.updateLineNumbers, update.dims);
    if (toUpdate > 4) display.lineDiv.style.display = "";
    display.renderedView = display.view;
    // There might have been a widget with a focused element that got
    // hidden or updated, if so re-focus it.
    if (focused != null && activeElt() != focused && focused.offsetHeight != 0) focused.focus();

    // Prevent selection and cursors from interfering with the scroll
    // width and height.
    removeChildren(display.cursorDiv);
    removeChildren(display.selectionDiv);
    display.gutters.style.height = "0";

    if (different) {
      display.lastWrapHeight = update.wrapperHeight;
      display.lastWrapWidth = update.wrapperWidth;
      startWorker(cm, 400);
    }

    display.updateLineNumbers = null;

    return true;
  }

  void postUpdateDisplay(CodeEditor cm, DisplayUpdate update) {
    var force = update.force;
    var viewport = update.viewport;
    for (var first = true;; first = false) {
      if (first && cm.options.lineWrapping && update.oldDisplayWidth != displayWidth()) {
        force = true;
      } else {
        force = false;
        // Clip forced viewport to actual scrollable area.
        if (viewport != null && viewport.top != -1)
          viewport = new Viewport(min(cm.doc.height + paddingVert() - displayHeight(), viewport.top));
        // Updated line heights might result in the drawn area not
        // actually covering the viewport. Keep looping until it does.
        update.visible = visibleLines(cm.doc, viewport);
        if (update.visible.from >= cm.display.viewFrom && update.visible.to <= cm.display.viewTo)
          break;
      }
      if (!updateDisplayIfNeeded(cm, update)) break;
      updateHeightsInViewport(cm);
      var barMeasure = measureForScrollbars(cm);
      updateSelection(cm);
      setDocumentHeight(barMeasure);
      updateScrollbars(cm, barMeasure);
    }

    cm.signalLater(cm, "update", cm);
    if (cm.display.viewFrom != cm.display.reportedViewFrom ||
        cm.display.viewTo != cm.display.reportedViewTo) {
      cm.signalLater(cm, "viewportChange", cm, cm.display.viewFrom, cm.display.viewTo);
      cm.display.reportedViewFrom = cm.display.viewFrom;
      cm.display.reportedViewTo = cm.display.viewTo;
    }
  }

  void updateDisplaySimple(CodeEditor cm, Viewport viewport) {
    var update = new DisplayUpdate(cm, viewport);
    if (updateDisplayIfNeeded(cm, update)) {
      updateHeightsInViewport(cm);
      postUpdateDisplay(cm, update);
      var barMeasure = measureForScrollbars(cm);
      updateSelection(cm);
      setDocumentHeight(barMeasure);
      updateScrollbars(cm, barMeasure);
    }
  }

  void setDocumentHeight(ScrollMeasure measure) {
    sizer.style.minHeight = "${measure.docHeight}px";
    var total = measure.docHeight + barHeight;
    heightForcer.style.top = "${total}px";
    num ht = max(total + scrollGap(), measure.clientHeight);
    gutters.style.height = "${ht}px";
  }

  // Read the actual heights of the rendered lines, and update their
  // stored heights to match.
  updateHeightsInViewport(CodeEditor cm) {
    var prevBottom = lineDiv.offsetTop;
    for (var i = 0; i < view.length; i++) {
      var cur = view[i], height;
      if (cur.hidden) continue;
      if (ie && ie_version < 8) {
        var bot = cur.node.offsetTop + cur.node.offsetHeight;
        height = bot - prevBottom;
        prevBottom = bot;
      } else {
        var box = cur.node.getBoundingClientRect();
        height = box.bottom - box.top;
      }
      var diff = cur.line.height - height;
      if (height < 2) height = textHeight();
      if (diff > .001 || diff < -.001) {
        cur.line.updateLineHeight(height);
        updateWidgetHeight(cur.line);
        if (cur.rest != null) {
          for (var j = 0; j < cur.rest.length; j++) {
          updateWidgetHeight(cur.rest[j]);
          }
        }
      }
    }
  }

  // Read and store the height of line widgets associated with the
  // given line.
  updateWidgetHeight(Line line) {
    if (line.widgets != null) {
      for (var i = 0; i < line.widgets.length; ++i) {
        line.widgets[i].height = line.widgets[i].node.offsetHeight;
      }
    }
  }

  // Do a bulk-read of the DOM positions and sizes needed to draw the
  // view, so that we don't interleave reading and writing to the DOM.
  Dimensions getDimensions(cm) {
    var d = this, left = {}, width = {};
    var gutterLeft = d.gutters.clientLeft;
    for (var n = d.gutters.firstChild, i = 0; n != null; n = n.nextNode, ++i) {
      left[cm.options.gutters[i]] = n.offsetLeft + n.clientLeft + gutterLeft;
      width[cm.options.gutters[i]] = n.clientWidth;
    }
    return new Dimensions(
        compensateForHScroll(),
        d.gutters.offsetWidth,
        left,
        width,
        d.wrapper.clientWidth);
  }

  // Sync the actual display DOM structure with display.view, removing
  // nodes for lines that are no longer in view, and creating the ones
  // that are not there yet, and updating the ones that are out of
  // date.
  patchDisplay(CodeEditor cm, updateNumbersFrom, Dimensions dims) {
    bool lineNumbers = cm.options.lineNumbers;
    DivElement container = lineDiv;
    Node cur = container.firstChild;

    Node rm(Element node) {
      var next = node.nextNode;
      // Works around a throw-scroll bug in OS X Webkit
      if (webkit && mac && cm.display.currentWheelTarget == node)
        node.style.display = "none";
      else
        node.remove();
      return next;
    }

    var lineN = viewFrom;
    // Loop over the elements in the view, syncing cur (the DOM nodes
    // in display.lineDiv) with the view as we go.
    for (var i = 0; i < view.length; i++) {
      var lineView = view[i];
      if (lineView.hidden) {
      } else if (lineView.node == null) { // Not drawn yet
        var node = lineView.buildLineElement(cm, lineN, dims);
        container.insertBefore(node, cur);
      } else { // Already drawn
        while (cur != lineView.node) cur = rm(cur);
        var updateNumber = lineNumbers && updateNumbersFrom != null &&
          updateNumbersFrom <= lineN && lineView.lineNumber != null;
        if (lineView.changes != null) {
          if (lineView.changes.indexOf("gutter") > -1) updateNumber = false;
          lineView.updateLineForChanges(cm, lineN, dims);
        }
        if (updateNumber) {
          removeChildren(lineView.lineNumber);
          lineView.lineNumber.append(new Text(cm.lineNumberFor(lineN)));
        }
        cur = lineView.node.nextNode;
      }
      lineN += lineView.size;
    }
    while (cur != null) cur = rm(cur);
  }

}

// TODO Use this as a mixin for all classes that need these fields.
class LineClasses {
  String textClass;
  String bgClass;
  String getClass(String which) {
    if (which == "textClass") return textClass;
    if (which == "bgClass") return bgClass;
    return null;
  }
  void setClass(String which, String value) {
    if (which == "textClass") textClass = value;
    if (which == "bgClass") bgClass = value;
  }
}

// These objects are used to represent the visible (currently drawn)
// part of the document. A LineView may correspond to multiple
// logical lines, if those are connected by collapsed ranges.
class LineView {
  Line line;
  List<Line> rest;
  int size;
  Element node;
  PreElement text;
  Element lineNumber;
  bool hidden;
  int lineN;
  LineBuilder built;
  LineMeasurement measure;
  Element gutter;
  var alignable;
  List<String> changes;
  String bgClass;
  String textClass;
  Element background;

  LineView(Document doc, Line line, int lineN) {
    // The starting line
    this.line = line;
    // Continuing lines, if any
    this.rest = line.visualLineContinued();
    // Number of logical lines in this visual line
    this.size = this.rest != null ? doc.lineNo(lst(this.rest)) - lineN + 1 : 1;
    this.node = this.text = null;
    this.hidden = doc.lineIsHidden(line);
  }

  // When an aspect of a line changes, a string is added to
  // lineView.changes. This updates the relevant part of the line's
  // DOM structure.
  void updateLineForChanges(cm, lineN, dims) {
    for (var j = 0; j < changes.length; j++) {
      var type = changes[j];
      if (type == "text") updateLineText(cm);
      else if (type == "gutter") updateLineGutter(cm, lineN, dims);
      else if (type == "class") updateLineClasses();
      else if (type == "widget") updateLineWidgets(dims);
    }
    changes = null;
  }

  // Lines with gutter elements, widgets or a background class need to
  // be wrapped, and have the extra elements added to the wrapper div
  Element ensureLineWrapped() {
    if (node == text) {
      node = eltdiv(null, null, "position: relative");
      if (text.parentNode != null)
        text.replaceWith(node);
      node.append(text);
      if (ie && ie_version < 8) node.style.zIndex = "2";
    }
    return node;
  }

  void updateLineBackground() {
    defined(cls) => cls != null && !cls.isEmpty;
    var cls = defined(bgClass)
        ? bgClass + " " + (line.bgClass == null ? "" : line.bgClass)
        : defined(line.bgClass) ? line.bgClass : null;
    if (cls != null) cls += " CodeMirror-linebackground";
    if (background != null) {
      if (cls != null) background.className = cls;
      else {
        background.remove();
        background = null;
      }
    } else if (cls != null) {
      var wrap = ensureLineWrapped();
      background = wrap.insertBefore(eltdiv(null, cls), wrap.firstChild);
    }
  }

  // Wrapper around buildLineContent which will reuse the structure
  // in display.externalMeasured when possible.
  LineBuilder getLineContent(CodeEditor cm) {
    var ext = cm.display.externalMeasured;
    if (ext != null && ext.line == line) {
      cm.display.externalMeasured = null;
      measure = ext.measure;
      return ext.built;
    }
    return cm.buildLineContent(this);
  }

  // Redraw the line's text. Interacts with the background and text
  // classes because the mode may output tokens that influence these
  // classes.
  void updateLineText(CodeEditor cm) {
    var cls = text.className;
    LineBuilder built = getLineContent(cm);
    if (text == node) node = built.pre;
    text.replaceWith(built.pre);
    text = built.pre;
    if (built.bgClass != bgClass || built.textClass != textClass) {
      bgClass = built.bgClass;
      textClass = built.textClass;
      updateLineClasses();
    } else if (cls != null) {
      text.className = cls;
    }
  }

  void updateLineClasses() {
    updateLineBackground();
    if (line.wrapClass != null)
      ensureLineWrapped().className = line.wrapClass;
    else if (node != text)
      node.className = "";
    var txClass = textClass != null && !(textClass.isEmpty) ? textClass + " " +
        (line['textClass'] == null ? "" : line['textClass']) : line['textClass'];
    text.className = txClass == null ? "" : txClass;
  }

  void updateLineGutter(CodeEditor cm, int lineN, Dimensions dims) {
    if (gutter != null) {
      gutter.remove();
      gutter = null;
    }
    var markers = line.gutterMarkers;
    if (cm.options.lineNumbers || markers != null) {
      var wrap = ensureLineWrapped();
      var gutterWrap = gutter =
        wrap.insertBefore(eltdiv(null, "CodeMirror-gutter-wrapper", "left: " +
                      (cm.options.fixedGutter
                          ? dims.fixedPos
                          : -dims.gutterTotalWidth).toString() +
                      "px; width: ${dims.gutterTotalWidth}px"),
                  text);
      if (line.gutterClass != null)
        gutterWrap.className += " " + line.gutterClass;
      if (cm.options.lineNumbers &&
          (markers == null || markers["CodeMirror-linenumbers"] == null))
        lineNumber = gutterWrap.append(
          eltdiv(cm.lineNumberFor(lineN),
              "CodeMirror-linenumber CodeMirror-gutter-elt",
              "left: " + dims.gutterLeft["CodeMirror-linenumbers"].toString() +
              "px; width: ${cm.display.lineNumInnerWidth}px"));
      if (markers != null) {
        for (var k = 0; k < cm.options.gutters.length; ++k) {
          var id = cm.options.gutters[k], found = markers[id];
          if (found != null)
            gutterWrap.append(eltdiv([found], "CodeMirror-gutter-elt",
                "left: ${dims.gutterLeft[id]}px; " +
                    "width: ${dims.gutterWidth[id]}px"));
        }
      }
    }
  }

  void updateLineWidgets(Dimensions dims) {
    alignable = null;
    var next;
    for (var child = node.firstChild; child != null; child = next) {
      next = child.nextNode;
      if (child.className == "CodeMirror-linewidget")
        child.remove();
    }
    insertLineWidgets(dims);
  }

  // Build a line's DOM representation from scratch
  Element buildLineElement(CodeEditor cm, int lineN, Dimensions dims) {
    LineBuilder built = getLineContent(cm);
    text = node = built.pre;
    if (built.bgClass != null) bgClass = built.bgClass;
    if (built.textClass != null) textClass = built.textClass;

    updateLineClasses();
    updateLineGutter(cm, lineN, dims);
    insertLineWidgets(dims);
    return node;
  }

  // A lineView may contain multiple logical lines (when merged by
  // collapsed spans). The widgets for all of them need to be drawn.
  void insertLineWidgets(Dimensions dims) {
    insertLineWidgetsFor(line, dims, true);
    if (rest != null) {
      for (var i = 0; i < rest.length; i++) {
        insertLineWidgetsFor(rest[i], dims, false);
      }
    }
  }

  void insertLineWidgetsFor(Line line, Dimensions dims, bool allowAbove) {
    if (line.widgets == null) return;
    var wrap = ensureLineWrapped();
    for (var i = 0, ws = line.widgets; i < ws.length; ++i) {
      var widget = ws[i], node = eltdiv([widget.node], "CodeMirror-linewidget");
      if (!widget.handleMouseEvents) _doIgnoreEvents(node);
      positionLineWidget(widget, node, dims);
      if (allowAbove && widget.above)
        wrap.insertBefore(node, gutter == null ? text : gutter);
      else
        wrap.append(node);
      line.signalLater(widget, "redraw");
    }
  }

  positionLineWidget(LineWidget widget, Element node, Dimensions dims) {
    if (widget.noHScroll) {
      if (alignable == null )alignable = [];
      alignable.add(node);
      var width = dims.wrapperWidth;
      node.style.left = "${dims.fixedPos}px";
      if (!widget.coverGutter) {
        width -= dims.gutterTotalWidth;
        node.style.paddingLeft = "${dims.gutterTotalWidth}px";
      }
      node.style.width = "${width}px";
    }
    if (widget.coverGutter) {
      node.style.zIndex = "5";
      node.style.position = "relative";
      if (!widget.noHScroll) {
        node.style.marginLeft = "${-dims.gutterTotalWidth}px";
      }
    }
  }

}

// Line widgets are block elements displayed above or below a line.
class LineWidget extends Object with EventManager {
  CodeEditor cm;
  Element node;
  Line line;
  num height;
  bool coverGutter, noHScroll, above, handleMouseEvents;
  var insertAt;

  LineWidget(this.cm, this.node, LineWidgetOptions options) {
    if (options == null) {
      // TODO Remove this branch.
      coverGutter = false;
      noHScroll = false;
      above = false;
      handleMouseEvents = false;
      insertAt = -1;
    } else {
      coverGutter = options.coverGutter;
      noHScroll = options.noHScroll;
      above = options.above;
      handleMouseEvents = options.handleMouseEvents;
      insertAt = options.insertAt;
    }
  }

  OperationGroup get operationGroup => cm.operationGroup;

  void clear() {
    var ws = line.widgets;
    int no = line.lineNo();
    if (no == -1 || ws == null) return;
    for (var i = 0; i < ws.length; ++i) {
      if (ws[i] == this) ws.removeAt(i--);
    }
    if (ws.length == 0) line.widgets = null;
    var height = widgetHeight();
    cm.runInOp(cm, () {
      cm.adjustScrollWhenAboveVisible(line, -height);
      cm.regLineChange(no, "widget");
      line.updateLineHeight(max(0, line.height - height));
    });
  }
  changed() {
    var oldH = height;
    height = null;
    var diff = widgetHeight() - oldH;
    if (diff == 0) return;
    cm.runInOp(cm, () {
      cm.curOp.forceUpdate = true;
      cm.adjustScrollWhenAboveVisible(line, diff);
      line.updateLineHeight(line.height + diff);
    });
  }

  widgetHeight() {
    if (height != null) return height;
    if (!contains(document.body, node)) {
      var parentStyle = "position: relative;";
      if (coverGutter)
        parentStyle += "margin-left: -${cm.display.gutters.offsetWidth}px;";
      if (noHScroll)
        parentStyle += "width: ${cm.display.wrapper.clientWidth}px;";
      removeChildrenAndAdd(cm.display.measure,
          eltdiv([node], null, parentStyle));
    }
    return height = node.offsetHeight;
  }
}

class NullScrollbars {
  NullScrollbars(Function place, Function scroll, CodeEditor cm);

  update(ScrollMeasure measure) { return new Rect(bottom: 0, right: 0); }
  setScrollLeft(int pos) {}
  setScrollTop(int pos) {}
  clear() {}
  }

class NativeScrollbars extends NullScrollbars {
  CodeEditor cm;
  DivElement vert, horiz;
  bool checkedOverlay;

  NativeScrollbars(Function place, Function scroll, CodeEditor cm)
      : super(place, scroll, cm) {
    this.cm = cm;
    vert = eltdiv([eltdiv(null, null, "min-width: 1px")],
        "CodeMirror-vscrollbar");
    horiz = eltdiv([eltdiv(null, null, "height: 100%; min-height: 1px")],
        "CodeMirror-hscrollbar");
    place(vert); place(horiz);

    cm.on(vert, "scroll", (Event e) {
      if (vert.clientHeight != 0) scroll(vert.scrollTop, "vertical");
    });
    cm.on(horiz, "scroll", (Event e) {
      if (horiz.clientWidth != 0) scroll(horiz.scrollLeft, "horizontal");
    });

    checkedOverlay = false;
    // Need to set a minimum width to see the scrollbar on IE7 (but must not set it on IE8).
    if (ie && ie_version < 8) this.horiz.style.minHeight = this.vert.style.minWidth = "18px";
  }

  update(ScrollMeasure measure) {
    bool needsH = measure.scrollWidth > measure.clientWidth + 1;
    bool needsV = measure.scrollHeight > measure.clientHeight + 1;
    var sWidth = measure.nativeBarWidth;

    Element child = vert.firstChild;
    if (needsV) {
      vert.style.display = "block";
      vert.style.bottom = needsH ? "${sWidth}px" : "0";
      var totalHeight = measure.viewHeight - (needsH ? sWidth : 0);
      // A bug in IE8 can cause this value to be negative, so guard it.
      child.style.height =
        "${max(0, measure.scrollHeight - measure.clientHeight + totalHeight)}px";
    } else {
      vert.style.display = "";
      child.style.height = "0";
    }

    child = horiz.firstChild;
    if (needsH) {
      horiz.style.display = "block";
      horiz.style.right = needsV ? "${sWidth}px" : "0";
      horiz.style.left = "${measure.barLeft}px";
      var totalWidth = measure.viewWidth - measure.barLeft - (needsV ? sWidth : 0);
      child.style.width =
        "${measure.scrollWidth - measure.clientWidth + totalWidth}px";
    } else {
      horiz.style.display = "";
      child.style.width = "0";
    }

    if (!checkedOverlay && measure.clientHeight > 0) {
      if (sWidth == 0) _overlayHack();
      checkedOverlay = true;
    }

    return new Rect(right: needsV ? sWidth : 0, bottom: needsH ? sWidth : 0);
  }

  setScrollLeft(int pos) {
    if (horiz.scrollLeft != pos) horiz.scrollLeft = pos;
  }

  setScrollTop(int pos) {
    if (vert.scrollTop != pos) vert.scrollTop = pos;
  }

  clear() {
    horiz.remove();
    vert.remove();
  }

  _overlayHack() {
    var w = mac && !mac_geMountainLion ? "12px" : "18px";
    horiz.style.minHeight = vert.style.minWidth = w;
    barMouseDown(e) {
      if (cm.e_target(e) != vert && cm.e_target(e) != horiz)
        cm.operation(cm, () => cm.onMouseDown(e))();
    };
    cm.on(vert, "mousedown", barMouseDown);
    cm.on(horiz, "mousedown", barMouseDown);
  }
}

class Dimensions {
  num fixedPos;
  int gutterTotalWidth;
  Map<String,int> gutterLeft;
  Map<String,int> gutterWidth;
  var wrapperWidth;
  Dimensions(this.fixedPos,
             this.gutterTotalWidth,
             this.gutterLeft,
             this.gutterWidth,
             this.wrapperWidth);
}

class DisplayUpdate {
  Displ display;
  Viewport viewport;
  // Store some values that we'll need later (but don't want to force a relayout for)
  Span visible;
  bool editorIsHidden;
  int wrapperHeight;
  int wrapperWidth;
  var oldDisplayWidth;
  bool force;
  Dimensions dims;

  DisplayUpdate(CodeEditor cm, viewport, [bool force = false]) {
    this.display = cm.display;
    this.viewport = viewport;
    // Store some values that we'll need later (but don't want to force a relayout for)
    this.visible = display.visibleLines(cm.doc, viewport);
    this.editorIsHidden = display.wrapper.offsetWidth == 0;
    this.wrapperHeight = display.wrapper.clientHeight;
    this.wrapperWidth = display.wrapper.clientWidth;
    this.oldDisplayWidth = display.displayWidth();
    this.force = force;
    this.dims = cm.display.getDimensions(cm);
  }
}

class Viewport {
  num top;
  num bottom;
  ScrollDelta ensure;
  Viewport(this.top, [this.bottom, this.ensure]);
  num get from => top;
  num get to => bottom;
}

class LineWidgetOptions {
  bool coverGutter, noHScroll, above, handleMouseEvents;
  int insertAt = -1;

  LineWidgetOptions({this.coverGutter: false, this.noHScroll: false,
    this.above: false, this.handleMouseEvents, this.insertAt});
}

// {pre: elt("pre", [content]), content: content, col: 0, pos: 0, cm: cm};
class LineContent {
  PreElement pre;
  var content;
  int col, pos;
  CodeEditor cm;
  String bgClass, textClass;

  LineContent({this.pre, this.content, this.col: 0, this.pos: 0, this.cm});
}

class DrawnSelection {
  Node cursors, selection;
  num teTop, teLeft;
}

class ScrollMeasure {
  num clientHeight, viewHeight, scrollWidth, clientWidth, viewWidth;
  num barLeft, docHeight, scrollHeight, nativeBarWidth, gutterWidth;

  ScrollMeasure(this.clientHeight, this.viewHeight, this.scrollWidth,
      this.clientWidth, this.viewWidth, this.barLeft, this.docHeight,
      this.scrollHeight, this.nativeBarWidth, this.gutterWidth);
}