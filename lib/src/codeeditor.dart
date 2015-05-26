// Copyright (c) 2015, the Comid Authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

part of comid;

class CodeEditor extends Object with EventManager implements CodeMirror {
  /**
   * It contains a string that indicates the version of the library. This is a
   * triple of integers "major.minor.patch", where patch is zero for releases,
   * and something else (usually one) for dev snapshots.
   */
  static const version = "5.3.1";

//  static Options defaults = new Options();
  static Map<String, CommandHandler> defaultCommands = {};

  static Map<DivElement,CodeEditor> _elementCache = new Map();
  // Called on the unload event to unlink the DivElement and the CodeEditor
  static void _dispose(var edToRemove) {
    var divToRemove = null;
    _elementCache.forEach((div, ed) {
      if (edToRemove == ed) {
        divToRemove = div;
      }
    });
    if (divToRemove != null) {
      _elementCache.remove(divToRemove);
    }
  }
  static Map<String, Function> inputStyles = {
    "textarea" : (cm) => new TextareaInput(cm),
    "contenteditable": (cm) => new ContentEditableInput(cm)
  };

  Options options;
  Document doc;
  Displ display;
  EditState state;
  Operation curOp;
  List<Function> initHooks = [];
  Map scrollbarModel;
  Map<String, Function> commands;
  // This will be set to an array of strings when copying, so that,
  // when pasting, we know what kind of selections the copied text
  // was made out of.
  var lastCopied = null;
  Map<String,KeyMap> keyMap = new Map();

  factory CodeEditor.fromTextArea(TextAreaElement textarea, Options options) {
    return new CodeEditorArea.fromTextArea(textarea,  options);
  }

  CodeEditor(var place, [var opts]) {
    initMode();
    KeyMap.initDefaultKeys(this);
    defcommands();
    options = opts == null ? Options.defaultOptions.copy() :
        (opts is Map ? new Options.from(opts) : opts);
    options.setGuttersForLineNumbers();
    scrollbarModel = {
      "native": (place, scroll, cm) => new NativeScrollbars(place, scroll, cm),
      "null": (place, scroll, cm) => new NullScrollbars(place, scroll, cm)
    };

    var doc = options['value'];
    if (doc is String) doc = new Doc(doc, options['mode']);
    this.doc = doc as Doc;
    this.doc.cm = this;

    InputStyle input = inputStyles[options.inputStyle](this);
    display = new Display(place, doc, input);

//    display = new Display(place, doc);
//    display.wrapper.CodeMirror = this;
    // Link the DivElement and the CodeEditor for global event dispatching.
    _elementCache[display.wrapper] = this;
    updateGutters();
    themeChanged();
    if (options['lineWrapping'])
      display.wrapper.className += " CodeMirror-wrap";
    if (options['autofocus'] == true && !mobile) display.input.focus();
    display.initScrollbars(this);

    state = new EditState();

    // Override magic textarea content restore that IE sometimes does
    // on our hidden textarea on reload.
    if (ie && ie_version < 11) {
      setTimeout(() { display.input.reset(true); }, 20);
    }

    registerEventHandlers(this);
    _ensureGlobalHandlers();

    startOperation(this);
    curOp.forceUpdate = true;
    doc.attachDoc(this, doc);

    if ((options['autofocus'] != null && !mobile) || hasFocus())
      setTimeout(bind(onFocus, this), 20);
    else
      onBlur(this);

    Options.optionHandlers.forEach((k,v) => v(this, options[k], Options.Init));
    maybeUpdateLineNumberWidth();
//    options.finishInit(this); // Redefine several (read-only, in Dart) methods
    for (var i = 0; i < initHooks.length; ++i) {
      initHooks[i](this);
    }
    endOperation(this);
    // Suppress optimizelegibility in Webkit, since it breaks text
    // measuring on line wrapping boundaries.
    if (webkit && options.lineWrapping &&
        display.lineDiv.getComputedStyle().textRendering == "optimizelegibility")
      display.lineDiv.style.textRendering = "auto";
  }

  void focus() {
//    window.focus();
    display.input.focus();
  }

  updateSelection() {
    display.updateSelection(this);
  }

  void updateScrollbars() {
    display.updateScrollbars(this);
  }

  void clearCaches() {
    doc.clearCaches();
  }

  void setOption(String option, Object value) {
    var old = options[option];
    if (options[option] == value && option != "mode") {
      return;
    }
    options[option] = value;
    if (Options.optionHandlers.containsKey(option)) {
      operation(this, () { Options.optionHandlers[option](this, value, old); })();
    }
  }

  Object getOption(String option) {
    return options[option];
  }

  Doc getDoc() {
    return doc;
  }

  void addKeyMap(dynamic map, [bool bottom = false]) {
    if (bottom) {
      state.keyMaps.add(getKeyMap(map));
    } else {
      state.keyMaps.insert(0, getKeyMap(map));
    }
  }
  bool removeKeyMap(dynamic map) {
    var maps = state.keyMaps;
    for (var i = 0; i < maps.length; ++i) {
      if (maps[i] == map || maps[i]['name'] == map) {
        maps.removeAt(i);
        return true;
      }
    }
    return false;
  }

  void addOverlay(dynamic spec, [dynamic options]) {
    methodOp(() {
      Mode mode = spec is Mode ? spec : getMode(options, spec);
      if (mode.hasStartState) throw new StateError("Overlays may not be stateful.");
      state.overlays.add({'mode': mode, 'modeSpec': spec,
        'opaque': options == null ? false : options.opaque});
      state.modeGen++;
      regChange();
    })();
  }
  void removeOverlay(dynamic spec) {
    methodOp(() {
      var overlays = state.overlays;
      for (var i = 0; i < overlays.length; ++i) {
        var cur = overlays[i]['modeSpec'];
        if (cur == spec || spec is String && cur.name == spec) {
          overlays.removeAt(i);
          state.modeGen++;
          regChange();
          return;
        }
      }
    })();
  }

  bool indentLine(int n, [dynamic dir, bool aggressive = false]) {
    return methodOp(() {
      if (dir is! String && dir is! num) {
        if (dir == null) dir = options.smartIndent ? "smart" : "prev";
        else dir = dir ? "add" : "subtract";
      }
      if (doc.isLine(n)) {
        return _indentLine(n, dir, aggressive);
      }
      return false;
    })();
  }

  void indentSelection(dynamic how) {
    methodOp(() {
      var ranges = doc.sel.ranges;
      int end = -1;
      for (var i = 0; i < ranges.length; i++) {
        var range = ranges[i];
        if (!range.empty()) {
          var from = range.from(), to = range.to();
          var start = max(end, from.line);
          end = min(doc.lastLine(), to.line - (to.char != 0 ? 0 : 1)) + 1;
          for (var j = start; j < end; ++j) {
            _indentLine(j, how, false);
          }
          var newRanges = doc.sel.ranges;
          if (from.char == 0 &&
              ranges.length == newRanges.length &&
              newRanges[i].from().char > 0) {
            doc.replaceOneSelection(i,
                new Range(from, newRanges[i].to()), sel_dontScroll);
          }
        } else if (range.head.line > end) {
          _indentLine(range.head.line, how, true);
          end = range.head.line;
          if (i == doc.sel.primIndex) ensureCursorVisible();
        }
      }
    })();
  }


  // Fetch the parser token for a given character. Useful for hacks
  // that want to inspect the mode state (say, for completion).
  Token getTokenAt(Pos pos, [bool precise = false]) {
    return takeToken(pos, precise, false);
  }

  List<Token> getLineTokens(int line, [bool precise = false]) {
    return takeToken(new Pos(line), precise, true);
  }

  String getTokenTypeAt(Pos pos) {
    pos = doc.clipPos(pos);
    var styles = getLineStyles(doc._getLine(pos.line), -1);
    int before = 0, after = (styles.length - 1) ~/ 2, ch = pos.char;
    String type;
    if (ch == 0) type = styles[2];
    else for (;;) {
      var mid = (before + after) >> 1;
      if ((mid != 0 ? styles[mid * 2 - 1] : 0) >= ch) after = mid;
      else if (styles[mid * 2 + 1] < ch) before = mid + 1;
      else { type = styles[mid * 2 + 2]; break; }
    }
    var cut = type != null ? type.indexOf("cm-overlay ") : -1;
    return cut < 0 ? type : cut == 0 ? null : type.substring(0, cut - 1);
  }

  Mode getModeAt(Pos pos) {
    var mode = doc.mode;
    if (!mode.hasInnerMode) return mode;
    return innerMode(mode, getTokenAt(pos).state);
  }

  Object getHelper(Pos pos, String type) {
    var list = getHelpers(pos, type);
    if (list.isEmpty) return null;
    return list[0];
  }

  dynamic getHelpers(Pos pos, String type) {
    var found = [];
    //if (!helpers.hasOwnProperty(type)) return found;
    var help = helpers[type];
    if (help == null) return helpers;
    var mode = getModeAt(pos);
    if (mode[type] is String) {
      if (help[mode[type]] != null) found.add(help[mode[type]]);
    } else if (mode[type] != null) {
      for (var i = 0; i < mode[type].length; i++) {
        var val = help[mode[type][i]];
        if (val != null) found.add(val);
      }
    } else if (mode.helperType != null && help[mode.helperType] != null) {
      found.add(help[mode.helperType]);
    } else if (help != null && help[mode.name] != null) {
      found.add(help[mode.name]);
    }
    for (var i = 0; i < help['_global'].length; i++) {
      var cur = help['_global'][i];
      if (cur['pred'](mode, this) != null && found.indexOf(cur['val']) == -1)
        found.add(cur['val']);
    }
    return found;
  }

  dynamic getStateAfter([int ln, bool precise = false]) {
    int line = doc.clipLine(ln == null ? doc.first + doc.size - 1: ln);
    return getStateBefore(line + 1, precise);
  }

  Rect cursorCoords(var start, [String mode = "page"]) {
    // start may be true,false,Pos. mode may be "local","page".
    var pos, range = doc.sel.primary();
    if (start == null) pos = range.head;
    else if (start is Pos) pos = doc.clipPos(start);
    else pos = start ? range.from() : range.to();
    return doc.cursorCoords(pos, mode);
  }

  Rect charCoords(Pos pos, [String mode = "page"]) {
    return doc.charCoords(doc.clipPos(pos), mode);
  }

  PosWithInfo coordsChar(Loc loc, [String mode = "page"]) {
    var coords = doc.fromCoordSystem(loc, mode);
    return doc.coordsChar(coords.left, coords.top);
  }

  int lineAtHeight(int ht, [String mode = "page"]) {
    var height = doc.fromCoordSystem(new Loc(ht, 0), mode).top;
    return doc.lineAtHeight(doc, height + display.viewOffset);
  }
  num heightAtLine(var line, [String mode = "page"]) {
    var end = false, lineObj;
    if (line is num) {
      var last = doc.first + doc.size - 1;
      if (line < doc.first) {
        line = doc.first;
      } else if (line > last) {
        line = last;
        end = true;
      }
      lineObj = doc._getLine(line);
    } else {
      lineObj = line;
    }
    return doc.intoCoordSystem(lineObj, new Rect(), mode).top +
      (end ? doc.height - doc.heightAtLine(lineObj) : 0);
  }

  num defaultTextHeight() { return display.textHeight(); }
  num defaultCharWidth() { return display.charWidth(); }

  LineHandle setGutterMarker(dynamic lineNo, String gutterID, Element value) {
    return methodOp(() {
      return doc.changeLine(lineNo, "gutter", (Line line) {
        if (line.gutterMarkers == null) line.gutterMarkers = {};
        var markers = line.gutterMarkers;
        if (value == null) {
          markers.remove(gutterID);
          if (markers.isEmpty) line.gutterMarkers = null;
        } else {
          markers[gutterID] = value;
        }
        return true;
      });
    })();
  }

  void clearGutter(Object gutterID) {
    methodOp(() {
      int i = doc.first;
      doc.iter((Line line) {
        if (line.gutterMarkers != null && line.gutterMarkers[gutterID] != null) {
          line.gutterMarkers.remove(gutterID);
          regLineChange(i, "gutter");
          if (line.gutterMarkers.isEmpty) line.gutterMarkers = null;
        }
        ++i;
      });
    })();
  }

  LineWidget addLineWidget(dynamic handle, Node node,
      {coverGutter: false, noHScroll: false,
      above: false, handleMouseEvents: false, insertAt: -1}) {
    var options = new LineWidgetOptions(coverGutter: coverGutter,
        noHScroll: noHScroll, above: above,
        handleMouseEvents: handleMouseEvents, insertAt: insertAt);
    return methodOp(() {
      return display.addLineWidget(doc, handle, node, options);
    })();
  }

  void removeLineWidget(LineWidget widget) { widget.clear(); }

  LineInfo lineInfo(dynamic line) { // Line or int
    int n;
    LineHandle handle;
    if (line is num) {
      if (!doc.isLine(line)) return null;
      n = line;
      handle = doc._getLine(line);
      if (handle == null) return null;
    } else {
      n = (line as Line).lineNo();
      if (n == -1) return null;
      handle = line;
    }
    return new LineInfo(n, handle);
  }

  Viewport getViewport() => new Viewport(display.viewFrom, display.viewTo);

  // Some projects use this for a completion pop-up.
  // Others place the widget independently.
  void addWidget(Pos loc, Element node,
            [bool scroll = false, String vert = "below", String horiz = "right"]) {
    Rect pos = cursorCoords(doc.clipPos(loc));
    num top = pos.bottom, left = pos.left;
    node.style.position = "absolute";
    _doIgnoreEvents(node);
    display.input.setUneditable(node);
    display.sizer.append(node);
    if (vert == "over") {
      top = pos.top;
    } else if (vert == "above" || vert == "near") {
      int vspace = max(display.wrapper.clientHeight, doc.height);
      int hspace = max(display.sizer.clientWidth,display.lineSpace.clientWidth);
      // Default to positioning above (if specified and possible);
      // otherwise default to positioning below
      if ((vert == 'above' || pos.bottom + node.offsetHeight > vspace) &&
          pos.top > node.offsetHeight)
        top = pos.top - node.offsetHeight;
      else if (pos.bottom + node.offsetHeight <= vspace)
        top = pos.bottom;
      if (left + node.offsetWidth > hspace)
        left = hspace - node.offsetWidth;
    }
    node.style.top = "${top}px";
    node.style.left = node.style.right = "";
    if (horiz == "right") {
      left = display.sizer.clientWidth - node.offsetWidth;
      node.style.right = "0px";
    } else {
      if (horiz == "left") {
        left = 0;
      } else if (horiz == "middle") {
        left = (display.sizer.clientWidth - node.offsetWidth) / 2;
      }
      node.style.left = "${left}px";
    }
    if (scroll)
      _scrollIntoView(left, top, left + node.offsetWidth,
          top + node.offsetHeight);
  }

  void triggerOnKeyDown(e) { methodOp(() { onKeyDown(e); })(); }
  void triggerOnKeyPress(e) { methodOp(() { onKeyPress(e); })(); }
  void triggerOnKeyUp(e) { onKeyUp(e); }

  void execCommand(String cmd) {
    if (commands.containsKey(cmd)) {
      commands[cmd](this);
    }
  }

  void triggerElectric(String text) {
    methodOp(() { display.input.triggerElectric(this, text); })();
  }

  Pos findPosH(Pos from, int amount, String unit, [bool visually = false]) {
    // unit is 'car', 'column' or 'word'
    var dir = 1;
    if (amount < 0) { dir = -1; amount = -amount; }
    Pos cur = doc.clipPos(from);
    for (var i = 0; i < amount; ++i) {
      cur = _findPosH(doc, cur, dir, unit, visually);
      if (cur.hitSide) break;
    }
    return cur;
  }

  // Used for horizontal relative motion. Dir is -1 or 1 (left or
  // right), unit can be "char", "column" (like char, but doesn't
  // cross line boundaries), "word" (across next word), or "group" (to
  // the start of next group of word or non-word-non-whitespace
  // chars). The visually param controls whether, in right-to-left
  // text, direction 1 means to move towards the next index in the
  // string, or towards the character to the right of the current
  // position. The resulting position will have a hitSide=true
  // property if it reached the end of the document.
  Pos _findPosH(Document doc, Pos pos, int dir, String unit, bool visually) {
    var line = pos.line, ch = pos.char, origDir = dir;
    Line lineObj = doc._getLine(line);
    bool possible = true;
    dynamic findNextLine() {
      var l = line + dir;
      if (l < doc.first || l >= doc.first + doc.size) return (possible = false);
      line = l;
      lineObj = doc._getLine(l);
      return true;
    }
    bool moveOnce([boundToLine = false]) {
      var moveMethod = visually ? moveVisually : moveLogically;
      var next = moveMethod(lineObj, ch, dir, true);
      if (next == null) {
        if (!boundToLine && findNextLine()) {
          if (visually) ch = (dir < 0 ? lineRight : lineLeft)(lineObj);
          else ch = dir < 0 ? lineObj.text.length : 0;
        } else return (possible = false);
      } else ch = next;
      return true;
    }

    if (unit == "char") moveOnce();
    else if (unit == "column") moveOnce(true);
    else if (unit == "word" || unit == "group") {
      var sawType = null, group = unit == "group";
      var helper = getHelper(pos, "wordChars");
      for (bool first = true;; first = false) {
        if (dir < 0 && !moveOnce(!first)) break;
        // There is an implicit newline at the end of each line
        var cur = ch < lineObj.text.length ? lineObj.text.substring(ch, ch+1) : "\n";
        var type = isWordChar(cur, helper) ? "w"
          : group && cur == "\n" ? "n"
          : !group || new RegExp(r'\s').hasMatch(cur) ? null
          : "p";
        if (group && !first && type == null) type = "s";
        if (sawType != null && sawType != type) {
          if (dir < 0) {dir = 1; moveOnce();}
          break;
        }

        if (type != null) sawType = type;
        if (dir > 0 && !moveOnce(!first)) break;
      }
    }
    var result = doc.skipAtomic(new Pos(line, ch), origDir, true);
    if (!possible) result = result.clipped();
    return result;
  }

  void moveH(dir, unit) {
    methodOp(() {
      doc.extendSelectionsBy((range) {
        if (display.shift || doc.extend || range.empty())
          return _findPosH(doc, range.head, dir, unit, options.rtlMoveVisually);
        else
          return dir < 0 ? range.from() : range.to();
      }, sel_move);
    })();
  }

  void deleteH(int dir, unit) {
    methodOp(() {
      var sel = doc.sel;
      if (sel.somethingSelected())
        doc.replaceSelection("", null, "+delete");
      else
        deleteNearSelection((Range range) {
          var other = _findPosH(doc, range.head, dir, unit, false);
          return dir < 0
              ? new Span(other, range.head)
              : new Span(range.head, other);
        });
    })();
  }

  Pos findPosV(Pos from, int amount, String unit, [goalColumn]) {
    // unit may be 'line' or 'page'
    var dir = 1, x = goalColumn;
    if (amount < 0) { dir = -1; amount = -amount; }
    Pos cur = doc.clipPos(from);
    for (var i = 0; i < amount; ++i) {
      var coords = cursorCoords(cur, "div");
      if (x == null) x = coords.left;
      else coords.left = x;
      cur = _findPosV(coords, dir, unit);
      if (cur.hitSide) break;
    }
    return cur;
  }

  // Handle the interaction of a change to a document with the editor
  // that this document is part of.
  void makeChangeSingleDocInEditor(Change change, List<List<MarkedSpan>> spans) {
    var from = change.from, to = change.to;

    var recomputeMaxLength = false, checkWidthStart = from.line;
    if (!options.lineWrapping) {
      checkWidthStart = doc.lineNo(doc._getLine(from.line).visualLine());
      doc.iter(checkWidthStart, to.line + 1, (Line line) {
        if (line == display.maxLine) {
          recomputeMaxLength = true;
          return true;
        }
      });
    }

    if (doc.sel.contains(change.from, change.to) > -1)
      signalCursorActivity(this);

    updateDoc(doc, change, spans, estimateHeight());

    if (!options.lineWrapping) {
      doc.iter(checkWidthStart, from.line + change.text.length, (Line line) {
        var len = line.lineLength();
        if (len > display.maxLineLength) {
          display.maxLine = line;
          display.maxLineLength = len;
          display.maxLineChanged = true;
          recomputeMaxLength = false;
        }
      });
      if (recomputeMaxLength) curOp.updateMaxLine = true;
    }

    // Adjust frontier, schedule worker
    doc.frontier = min(doc.frontier, from.line);
    display.startWorker(this, 400);

    var lendiff = change.text.length - (to.line - from.line) - 1;
    // Remember that these lines changed, for updating the display
    if (change.full)
      regChange();
    else if (from.line == to.line && change.text.length == 1 &&
            !isWholeLineUpdate(doc, change))
      regLineChange(from.line, "text");
    else
      regChange(from.line, to.line + 1, lendiff);

    bool changesHandler = hasHandler(this, "changes");
    bool changeHandler = hasHandler(this, "change");
    if (changeHandler || changesHandler) {
      var obj = new Change(
        from, to,
        change.text,
        change.origin,
        change.removed
      );
      if (changeHandler) signalLater(this, "change", this, obj);
      if (curOp.changeObjs == null) curOp.changeObjs = [];
      if (changesHandler) curOp.changeObjs.add(obj);
    }
    display.selForContextMenu = null;
  }

  // For relative vertical movement. Dir may be -1 or 1. Unit can be
  // "page" or "line". The resulting position will have a hitSide=true
  // property if it reached the end of the document.
  Pos _findPosV(pos, dir, unit) {
    num x = pos.left, y;
    if (unit == "page") {
      int wh = window.innerHeight;
      int pageSize = min(display.wrapper.clientHeight,
          wh == 0 ? document.documentElement.clientHeight : wh);
      y = pos.top + dir * (pageSize - (dir < 0 ? 1.5 : .5) *
          display.textHeight());
    } else if (unit == "line") {
      y = dir > 0 ? pos.bottom + 3 : pos.top - 3;
    }
    var target;
    for (;;) {
      target = doc.coordsChar(x, y);
      if (!target.outside) break;
      if (dir < 0 ? y <= 0 : y >= doc.height) {
        target = target.clipped();
        break;
      }
      y += dir * 5;
    }
    return target;
  }

  void moveV(dir, unit) {
    methodOp(() {
      List goals = [];
      var collapse = !display.shift && !doc.extend && doc.sel.somethingSelected();
      doc.extendSelectionsBy((Range range) {
        if (collapse)
          return dir < 0 ? range.from() : range.to();
        var headPos = cursorCoords(range.head, "div");
        if (range.goalColumn != null) headPos.left = range.goalColumn;
        goals.add(headPos.left);
        var pos = _findPosV(headPos, dir, unit);
        if (unit == "page" && range == doc.sel.primary())
          addToScrollPos(null, charCoords(pos, "div").top - headPos.top);
        return pos;
      }, sel_move);
      if (goals.length > 0) {
        for (var i = 0; i < doc.sel.ranges.length; i++) {
          doc.sel.ranges[i].goalColumn = goals[i].round();
        }
      }
    })();
  }

  // Find the word at the given position (as returned by coordsChar).
  Range findWordAt(PosWithInfo pos) {
    String line = doc._getLine(pos.line).text;
    int start = pos.char, end = pos.char;
    if (!line.isEmpty) {
      var helper = getHelper(pos, "wordChars");
      if ((pos.xRel < 0 || end == line.length) && start != 0) {
        --start;
      } else {
        ++end;
      }
      var startChar = line.substring(start, start+1);
      var check = isWordChar(startChar, helper)
        ? (ch) { return isWordChar(ch, helper); }
        : new RegExp(r'\s').hasMatch(startChar)
          ? (ch) { return new RegExp(r'\s').hasMatch(ch); }
          : (ch) { return new RegExp(r'\s').hasMatch(ch) && !isWordChar(ch); };
      while (start > 0 && check(line.substring(start - 1, start))) --start;
      while (end < line.length && check(line.substring(end, end + 1))) ++end;
    }
    return new Range(new Pos(pos.line, start), new Pos(pos.line, end));
  }

  void toggleOverwrite([bool value]) {
    if (value != null && value == state.overwrite) return;
    if (state.overwrite = !state.overwrite)
      addClass(display.cursorDiv, "CodeMirror-overwrite");
    else
      rmClass(display.cursorDiv, "CodeMirror-overwrite");

    signal(this, "overwriteToggle", this, state.overwrite);
  }
  bool hasFocus() { return display.input.getField() == activeElt(); }

  void scrollTo(num x, num y) {
    methodOp(() {
      if (x != null || y != null) resolveScrollToPos();
      if (x != null) curOp.scrollLeft = x.round();
      if (y != null) curOp.scrollTop = y.round();
    })();
  }
  ScrollInfo getScrollInfo() {
    var scroller = this.display.scroller;
    return new ScrollInfo(scroller.scrollLeft, scroller.scrollTop,
            scroller.scrollHeight - display.scrollGap() - this.display.barHeight,
            scroller.scrollWidth - display.scrollGap() - this.display.barWidth,
            display.displayHeight(), display.displayWidth());
  }

  void scrollIntoView(range, [margin]) {
    methodOp(() {
      if (range == null) {
        range = new ScrollDelta(doc.sel.primary().head, null);
        if (margin == null) margin = options.cursorScrollMargin;
      } else if (range is num) {
        range = new ScrollDelta(new Pos(range, 0), null);
      } else if (range is Pos) {
        range = new ScrollDelta(range, null);
      } else if (range is Range) {
        range = new ScrollDelta(range.from(), range.to());
      }
      if (range.to == null) range.to = range.from;
      range.margin = margin != null ? margin : 0;

      if (range.from.line != null) {
        resolveScrollToPos();
        curOp.scrollToPos = range;
      } else {
        var sPos = calculateScrollPos(min(range.from.left, range.to.left),
                                      min(range.from.top, range.to.top) - range.margin,
                                      max(range.from.right, range.to.right),
                                      max(range.from.bottom, range.to.bottom) + range.margin);
        scrollTo(sPos.scrollLeft, sPos.scrollTop);
      }
    })();
  }

  void setSize([dynamic width, dynamic height]) {
    methodOp(() {
      interpret(val) {
        return val is num || new RegExp(r'^\d+$').hasMatch(val.toString())
            ? "${val}px" : val;
      }
      if (width != null) display.wrapper.style.width = interpret(width);
      if (height != null) display.wrapper.style.height = interpret(height);
      if (options.lineWrapping) doc.clearLineMeasurementCache();
      var lineNo = display.viewFrom;
      doc.iter(lineNo, display.viewTo, (Line line) {
        if (line.widgets != null) {
          for (var i = 0; i < line.widgets.length; i++) {
            if (line.widgets[i].noHScroll) {
              regLineChange(lineNo, "widget");
              break;
            }
          }
        }
        ++lineNo;
      });
      curOp.forceUpdate = true;
      signal(this, "refresh", this);
    })();
  }

  dynamic doOperation(f) { return runInOp(this, f); }

  void refresh() {
    methodOp(() {
      var oldHeight = display.cachedTextHeight;
      regChange();
      curOp.forceUpdate = true;
      clearCaches();
      scrollTo(doc.scrollLeft, doc.scrollTop);
      updateGutterSpace();
      if (oldHeight == null || (oldHeight - display.textHeight()).abs() > .5)
        estimateLineHeights();
      signal(this, "refresh", this);
    })();
  }

  Document swapDoc(Document doc) {
    return methodOp(() {
      var old = this.doc;
      old.cm = null;
      doc.attachDoc(this, doc);
      clearCaches();
      display.input.reset();
      scrollTo(doc.scrollLeft, doc.scrollTop);
      curOp.forceScroll = true;
      signalLater(this, "swapDoc", this, old);
      return old;
    })();
  }

  Element getInputField() { return display.input.getField(); }
  DivElement getWrapperElement() { return display.wrapper; }
  DivElement getScrollerElement() { return display.scroller; }
  DivElement getGutterElement() { return display.gutters; }

  // Added as a convience to bundle all options into single method.
  AbstractTextMarker markText(from, to,
      {collapsed: false, clearWhenEmpty: false, clearOnEnter: false,
      replacedWith, handleMouseEvents: false, addToHistory: false,
      className, title, startStyle, endStyle, atomic: false, readOnly: false,
      inclusiveLeft: false,  inclusiveRight: false, shared: false,
      insertLeft: false, widgetNode, css}) {
    var opts = new TextMarkerOptions(
        collapsed: collapsed, clearWhenEmpty: clearWhenEmpty,
        clearOnEnter: clearOnEnter, replacedWith: replacedWith,
        handleMouseEvents: handleMouseEvents, addToHistory: addToHistory,
        className: className, title: title, startStyle: startStyle,
        endStyle: endStyle, atomic: atomic, readOnly: readOnly, css: css,
        inclusiveLeft: inclusiveLeft,  inclusiveRight: inclusiveRight,
        shared: shared, insertLeft: insertLeft, widgetNode: widgetNode);
    return doc.markText(from, to, opts);
  }
  AbstractTextMarker setBookmark(Pos pos, {widget, insertLeft: false, shared: false}) {
    var opts = new BookmarkOptions(
        widget: widget, insertLeft: insertLeft, shared: shared);
    return doc.setBookmark(pos, opts);
  }
  void setCursor(Pos pos, {bias, origin, scroll: true, clearRedo}) {
    var opts = new SelectionOptions(
        bias: bias, origin: origin, scroll: scroll, clearRedo: clearRedo);
    doc.setCursor(pos, null, opts);
  }

  // Duplicate of Doc public API, for convenience.

  Pos getCursor([dynamic start]) => doc.getCursor(start);
  Doc linkedDoc({bool sharedHist: false, int from: -1, int to: -1, Object mode}) {
    return doc.linkedDoc(sharedHist: sharedHist, from: from, to: to, mode: mode);
  }
  void unlinkDoc(dynamic other) { doc.unlinkDoc(other); }
  String getValue([String lineSep]) => doc.getValue(lineSep);
  void setValue(String code) { doc.setValue(code); }
  void replaceRange(String code, Pos from, [Pos to, String origin]) {
    doc.replaceRange(code, from, to, origin);
  }
  String getRange(Pos from, Pos to, [String lineSep = "\n"]) {
    return doc.getRange(from, to, lineSep);
  }
  String getLine(int lineNo) => doc.getLine(lineNo);
  LineHandle getLineHandle(int lineNo) => doc.getLineHandle(lineNo);
  int getLineNumber(LineHandle line) => doc.getLineNumber(line);
  LineHandle getLineHandleVisualStart(dynamic line) {
    return doc.getLineHandleVisualStart(line);
  }
  int lineCount() => doc.lineCount();
  int firstLine() => doc.firstLine();
  int lastLine() => doc.lastLine();
  bool isLine(int l) => doc.isLine(l);
  List<Range> listSelections() => doc.listSelections();
  bool somethingSelected() => doc.somethingSelected();
  void setSelection(Pos anchor, [Pos head, SelectionOptions options]) {
    doc.setSelection(anchor, head, options);
  }
  void extendSelection(Pos head, [Pos other, SelectionOptions options]) {
    doc.extendSelection(head, other, options);
  }
  void extendSelections(List<Pos> heads, [SelectionOptions options]) {
    doc.extendSelections(heads, options);
  }
  void extendSelectionsBy(RangeFn f, [SelectionOptions options]) {
    doc.extendSelectionsBy(f, options);
  }
  void setSelections(List<Range> ranges, [int primary, SelectionOptions options]) {
    doc.setSelections(ranges, primary, options);
  }
  void addSelection(Pos anchor, [Pos head, SelectionOptions options]) {
    doc.addSelection(anchor, head, options);
  }
  dynamic getSelection([dynamic lineSep = '\n']) => doc.getSelection(lineSep);
  List getSelections([dynamic lineSep = '\n']) => doc.getSelections(lineSep);
  void replaceSelection(String code, [String collapse, String origin]) {
    doc.replaceSelection(code, collapse, origin);
  }
  void replaceSelections(List<String> code, [String collapse, String origin]) {
    doc.replaceSelections(code, collapse, origin);
  }
  void undo() { doc.undo(); }
  void redo() { doc.redo(); }
  void undoSelection() { doc.undoSelection(); }
  void redoSelection() { doc.redoSelection(); }
  void setExtending(bool val) { doc.setExtending(val); }
  bool getExtending() => doc.getExtending();
  HistorySize historySize() => doc.historySize();
  void clearHistory() { doc.clearHistory(); }
  void markClean() { doc.markClean(); }
  int changeGeneration([bool forceSplit = false]) {
    return doc.changeGeneration(forceSplit);
  }
  bool isClean([int gen]) => doc.isClean(gen);
  HistoryRecord getHistory() => doc.getHistory();
  void setHistory(HistoryRecord histData) { doc.setHistory(histData); }
  Line addLineClass(dynamic handle, String where, String cls) {
    return doc.addLineClass(handle, where, cls);
  }
  Line removeLineClass(dynamic handle, String where, [String cls]) {
    return doc.removeLineClass(handle,  where, cls);
  }
  List<TextMarker> findMarksAt(Pos pos) => doc.findMarksAt(pos);
  List<TextMarker> findMarks(Pos from, Pos to, [Function filter]) {
    return doc.findMarks(from, to, filter);
  }
  List<TextMarker> getAllMarks() =>doc.getAllMarks();
  void setHistoryDepth(int n) { doc.setHistoryDepth(n); }

  // End of Doc public API dup.


  // Known modes, by name and by MIME
  static Map<String,Mode> modes = {};
  static Map mimeModes = {};

  // Extra arguments are stored as the mode's dependencies, which is
  // used by (legacy) mechanisms like loadmode.js to automatically
  // load a mode. (Preferred mechanism is the require/define calls.)
  // TODO mode.dependencies is not supported
  static defineMode(name, var mode) {
    initMode();
    if (CodeMirror.defaults.mode == null && name != "null") {
      CodeMirror.defaults['mode'] = name;
    }
    modes[name] = mode;
  }
  static defineSimpleMode(name, states, [props]) {
    defineMode(name, (config, spec) {
      print("Simple modes not yet supported");
      //return new SimpleMode(config, states, props);
      return new Mode();
    });
  }
  static defineMIME(mime, spec) {
    mimeModes[mime] = spec;
  }

  // Given a MIME type, a {name, ...options} config object, or a name
  // string, return a mode config object.
  static resolveMode(dynamic spec) {
    if (spec is String && mimeModes.containsKey(spec)) {
      spec = mimeModes[spec];
    } else if (spec is String && new RegExp(r'^[\w\-]+\/[\w\-]+\+xml$').hasMatch(spec)) {
      return resolveMode("application/xml");
    } else if (spec != null && spec is! String && spec['name'] is String && mimeModes.containsKey(spec['name'])) {
      var found = mimeModes[spec.name];
      if (found is String) found = {'name': found};
//      spec = createObj(found, spec);
      spec.addAll(found);
      spec.name = found.name;
    }
    if (spec is String) return {'name': spec};
    else if (spec != null) return spec;
    else return {'name': "null"};
  }

  // Given a mode spec (anything that resolveMode accepts), find and
  // initialize an actual mode object.
  static Mode getMode(dynamic options, dynamic spec) {
    spec = resolveMode(spec);
    var name = (spec is Map) ? spec['name'] : spec.name;
    var mfactory = modes[name];
    if (mfactory == null) return getMode(options, "text/plain");
    Mode modeObj;
    if (mfactory is Mode) {
      modeObj = mfactory;
    } else {
      modeObj = mfactory(options, spec);
    }
//    if (modeExtensions.containsKey(spec.name)) {
//      var exts = modeExtensions[spec.name];
//      for (var prop in exts) {
//        if (!exts.hasOwnProperty(prop)) continue;
//        if (modeObj.hasOwnProperty(prop)) modeObj["_" + prop] = modeObj[prop];
//        modeObj[prop] = exts[prop];
//      }
//    }
    if (spec is Map) {
      modeObj.name = spec['name'];
      if (spec['helperType'] != null) {
        modeObj.helperType = spec['helperType'];
      }
      if (spec['modeProps'] != null) {
        for (var prop in spec['modeProps'].keys) {
          modeObj[prop] = spec['modeProps'][prop];
        }
      }
    }

    return modeObj;
  }

  // Minimal default mode.
  static initMode() {
    if (!modes.isEmpty) return;
    modes["null"] =  new Mode();
//    defineMode("null", new Mode());
    defineMIME("text/plain", "null");
  }

  // This can be used to attach properties to mode objects from
  // outside the actual mode definition.
  Map modeExtensions = {};
  extendMode(mode, properties) {
    var msg = "Mode extensions are not supported; define a subclass of Mode.";
    throw new StateError(msg);
    if (!modeExtensions.containsKey(mode)) modeExtensions[mode] = {};
    Map exts = modeExtensions[mode];
//    copyObj(properties, exts);
    exts.addAll(properties);
  }

  // EXTENSIONS

  defineExtension(name, func) {
//    CodeMirror.prototype[name] = func;
    throw new StateError("Extensions are not supported.");
  }
  defineDocExtension(name, func) {
//    Doc.prototype[name] = func;
    throw new StateError("Extensions are not supported.");
  }
//  CodeMirror.defineOption = option;

  defineInitHook(f) { initHooks.add(f); }

  static var helpers = {};
  static registerHelper(type, name, value) {
    if (!helpers.containsKey(type)) helpers[type] =  {'_global': []};
    helpers[type][name] = value;
  }
  static registerGlobalHelper(type, name, predicate, value) {
    registerHelper(type, name, value);
    helpers[type]['_global'].add({'pred': predicate, 'val': value});
  }

  // MODE STATE HANDLING

  // Utility functions for working with state. Exported because nested
  // modes need to do this for their inner modes.

  static dynamic copyState(Mode mode, dynamic state) {
    if (state == true) return state;
//    if (mode.copyState != null) return mode.copyState(state);
//    var nstate = {};
//    for (var n in state) {
//      var val = state[n];
//      if (val is List) val = val.sublist(0);
//      nstate[n] = val;
//    }
//    return nstate;
    return mode.copyState(state);
  }

  startState(mode, [a1, a2]) {
    return mode.hasStartState ? mode.startState(a1, a2) : true;
  }

  // Given a mode and a state (for that mode), find the inner mode and
  // state at the position that the state refers to.
  Mode innerMode(Mode mode, var state) {
    var info;
    while (mode.hasInnerMode) {
      info = mode.innerMode(state);
      if (info == null || info.mode == mode) break;
      state = info.state;
      mode = info.mode;
    }
    return info == null ? new Mode(mode: mode, state: state) : info;
  }

  // Finds the line to start with when starting a parse. Tries to
  // find a line with a stateAfter, so that it can start with a
  // valid state. If that fails, it returns the line with the
  // smallest indentation, which tends to need the least context to
  // parse correctly.
  int findStartLine(int n, bool precise) {
    int minindent, minline;
    int lim = precise ? -1 : n - (doc.mode.innerMode != null ? 1000 : 100);
    for (var search = n; search > lim; --search) {
      if (search <= doc.first) return doc.first;
      var line = doc._getLine(search - 1);
      if (line.stateAfter != null && (!precise || search <= doc.frontier)) {
        return search;
      }
      var indented = countColumn(line.text, null, options.tabSize);
      if (minline == null || minindent > indented) {
        minline = search - 1;
        minindent = indented;
      }
    }
    return minline;
  }

  dynamic getStateBefore(int n, [bool precise = false]) {
    if (!doc.mode.hasStartState) return true;
    int pos = findStartLine(n, precise);
    var state = pos > doc.first ? doc._getLine(pos-1).stateAfter : null;
    if (state == null) state = startState(doc.mode);
    else state = copyState(doc.mode, state);
    doc.iter(pos, n, (Line line) {
      processLine(line.text, state);
      var save = pos == n - 1 || pos % 5 == 0 ||
          pos >= display.viewFrom && pos < display.viewTo;
      line.stateAfter = save ? copyState(doc.mode, state) : null;
      ++pos;
    });
    if (precise) doc.frontier = pos;
    return state;
  }

  // Commands are parameter-less actions that can be performed on an
  // editor, mostly used for keybindings.
  defcommands() {
    commands = {
      'selectAll': ([cm]) {
        doc.setSelection(new Pos(doc.firstLine(), 0), new Pos(doc.lastLine()),
            sel_dontScroll);
      },
      'singleSelection': ([cm]) {
        doc.setSelection(doc.getCursor("anchor"), doc.getCursor("head"),
            sel_dontScroll);
      },
      'killLine': ([cm]) {
        deleteNearSelection((Range range) {
          if (range.empty()) {
            var len = doc._getLine(range.head.line).text.length;
            if (range.head.char == len && range.head.line < doc.lastLine())
              return new Span(range.head, new Pos(range.head.line + 1, 0));
            else
              return new Span(range.head, new Pos(range.head.line, len));
          } else {
            return new Span(range.from(), range.to());
          }
        });
      },
      'deleteLine': ([cm]) {
        deleteNearSelection((Range range) {
          return new Span(new Pos(range.from().line, 0),
                  doc.clipPos(new Pos(range.to().line + 1, 0)));
        });
      },
      'delLineLeft': ([cm]) {
        deleteNearSelection((Range range) {
          return new Span(new Pos(range.from().line, 0), range.from());
        });
      },
      'delWrappedLineLeft': ([cm]) {
        deleteNearSelection((Range range) {
          var top = charCoords(range.head, "div").top + 5;
          var leftPos = coordsChar(new Loc(top, 0), "div");
          return new Span(leftPos, range.from());
        });
      },
      'delWrappedLineRight': ([cm]) {
        deleteNearSelection((Range range) {
          var top = charCoords(range.head, "div").top + 5;
          var rightPos = coordsChar(
              new Loc(top, display.lineDiv.offsetWidth + 100), "div");
          return new Span(range.from(), rightPos);
        });
      },
      'undo': ([cm]) { doc.undo(); },
      'redo': ([cm]) { doc.redo(); },
      'undoSelection': ([cm]) { doc.undoSelection(); },
      'redoSelection': ([cm]) { doc.redoSelection(); },
      'goDocStart': ([cm]) { doc.extendSelection(new Pos(doc.firstLine(), 0)); },
      'goDocEnd': ([cm]) { doc.extendSelection(new Pos(doc.lastLine())); },
      'goLineStart': ([cm]) {
        doc.extendSelectionsBy(
            (range) {
              return lineStart(range.head.line);
            },
            new SelectionOptions(origin: "+move", bias: 1));
      },
      'goLineStartSmart': ([cm]) {
        doc.extendSelectionsBy(
            (range) {
              return lineStartSmart(range.head);
            },
            new SelectionOptions(origin: "+move", bias: 1));
      },
      'goLineEnd': ([cm]) {
        doc.extendSelectionsBy(
            (range) { return lineEnd(range.head.line); },
            new SelectionOptions(origin: "+move", bias: -1));
      },
      'goLineRight': ([cm]) {
        doc.extendSelectionsBy(
            (range) {
              var top = charCoords(range.head, "div").top + 5;
              return coordsChar(new Loc(top, display.lineDiv.offsetWidth + 100),
                  "div");
            },
            sel_move);
      },
      'goLineLeft': ([cm]) {
        doc.extendSelectionsBy(
            (range) {
              var top = charCoords(range.head, "div").top + 5;
              return coordsChar(new Loc(top, 0), "div");
            },
            sel_move);
      },
      'goLineLeftSmart': ([cm]) {
        doc.extendSelectionsBy(
            (range) {
              var top = charCoords(range.head, "div").top + 5;
              var pos = coordsChar(new Loc(top, 0), "div");
              Match m = new RegExp(r'\S').firstMatch(doc.getLine(pos.line));
              if (pos.char < m.start) {
                return lineStartSmart(range.head);
              }
              return pos;
            },
            sel_move);
      },
      'goLineUp': ([cm]) { moveV(-1, "line"); },
      'goLineDown': ([cm]) { moveV(1, "line"); },
      'goPageUp': ([cm]) { moveV(-1, "page"); },
      'goPageDown': ([cm]) { moveV(1, "page"); },
      'goCharLeft': ([cm]) { moveH(-1, "char"); },
      'goCharRight': ([cm]) { moveH(1, "char"); },
      'goColumnLeft': ([cm]) { moveH(-1, "column"); },
      'goColumnRight': ([cm]) { moveH(1, "column"); },
      'goWordLeft': ([cm]) { moveH(-1, "word"); },
      'goGroupRight': ([cm]) { moveH(1, "group"); },
      'goGroupLeft': ([cm]) { moveH(-1, "group"); },
      'goWordRight': ([cm]) { moveH(1, "word"); },
      'delCharBefore': ([cm]) { deleteH(-1, "char"); },
      'delCharAfter': ([cm]) { deleteH(1, "char"); },
      'delWordBefore': ([cm]) { deleteH(-1, "word"); },
      'delWordAfter': ([cm]) { deleteH(1, "word"); },
      'delGroupBefore': ([cm]) { deleteH(-1, "group"); },
      'delGroupAfter': ([cm]) { deleteH(1, "group"); },
      'indentAuto': ([cm]) { indentSelection("smart"); },
      'indentMore': ([cm]) { indentSelection("add"); },
      'indentLess': ([cm]) { indentSelection("subtract"); },
      'insertTab': ([cm]) { doc.replaceSelection("\t"); },
      'insertSoftTab': ([cm]) {
        List spaces = [];
        var ranges = doc.listSelections();
        int tabSize = options.tabSize;
        for (var i = 0; i < ranges.length; i++) {
          var pos = ranges[i].from();
          var col = countColumn(doc.getLine(pos.line), pos.char, tabSize);
          int n = tabSize - col % tabSize + 1;
          //var sp = (new List(n)..fillRange(0, n, "")).join(" ");
          spaces.add(spaceStr(n));
        }
        doc.replaceSelections(spaces);
      },
      'defaultTab': ([cm]) {
        if (doc.somethingSelected()) indentSelection("add");
        else execCommand("insertTab");
      },
      'transposeChars': ([cm]) {
        runInOp(this, () {
          var ranges = doc.listSelections(), newSel = [];
          for (var i = 0; i < ranges.length; i++) {
            var cur = ranges[i].head, line = doc._getLine(cur.line).text;
            if (line != null) {
              if (cur.char == line.length) {
                cur = new Pos(cur.line, cur.char - 1);
              }
              if (cur.char > 0) {
                cur = new Pos(cur.line, cur.char + 1);
                String ch1 = line.substring(cur.char - 1, cur.char);
                String ch2 = line.substring(cur.char - 2, cur.char - 1);
                doc.replaceRange(ch1 + ch2,
                    new Pos(cur.line, cur.char - 2),
                    cur, "+transpose");
              } else if (cur.line > doc.first) {
                var prev = doc._getLine(cur.line - 1).text;
                if (prev) {
                  String ch1 = line.substring(0, 1);
                  String ch2 = prev.substring(prev.length - 1, prev.length);
                  doc.replaceRange(ch1 + "\n" + ch2,
                      new Pos(cur.line - 1, prev.length - 1),
                      new Pos(cur.line, 1), "+transpose");
                }
              }
            }
            newSel.add(new Range(cur, cur));
          }
          doc.setSelections(newSel);
        });
      },
      'newlineAndIndent': ([cm]) {
        runInOp(this, () {
          var len = doc.listSelections().length;
          for (var i = 0; i < len; i++) {
            var range = doc.listSelections()[i];
            doc.replaceRange("\n", range.anchor, range.head, "+input");
            indentLine(range.from().line + 1, null, true);
            ensureCursorVisible();
          }
        });
      },
      'toggleOverwrite': ([cm]) { toggleOverwrite(); }
    };
    for (String cmd in defaultCommands.keys){
      commands[cmd] = defaultCommands[cmd];
    }
  }

  // Indent the given line. The how parameter can be "smart",
  // "add"/null, "subtract", or "prev". When aggressive is false
  // (typically set to true for forced single-line indents), empty
  // lines are not indented, and places where the mode returns Pass
  // are left alone.
  bool _indentLine(int n, dynamic how, bool aggressive) {
    var state;
    if (how == null) how = "add";
    if (how == "smart") {
      // Fall back to "prev" when the mode doesn't have an indentation method.
      if (!doc.mode.hasIndent) {
        how = "prev";
      } else {
        state = getStateBefore(n, false);
      }
    }

    var tabSize = options.tabSize;
    var line = doc._getLine(n);
    int curSpace = countColumn(line.text, null, tabSize);
    line.stateAfter = null;
    var curSpaceString=new RegExp(r'^\s*').allMatches(line.text).first.group(0);
    var indentation;
    if (!aggressive && !(new RegExp(r'\S').hasMatch(line.text))) {
      indentation = 0;
      how = "not";
    } else if (how == "smart") {
      indentation = doc.mode.indent(state,
          line.text.substring(curSpaceString.length), line.text);
      if (indentation == Pass || indentation > 150) {
        if (!aggressive) return false;
        how = "prev";
      }
    }
    if (how == "prev") {
      if (n > doc.first) {
        indentation = countColumn(doc._getLine(n-1).text, null, tabSize);
      } else {
        indentation = 0;
      }
    } else if (how == "add") {
      indentation = curSpace + options.indentUnit;
    } else if (how == "subtract") {
      indentation = curSpace - options.indentUnit;
    } else if (how is num) {
      indentation = curSpace + how;
    }
    indentation = max(0, indentation);

    var indentString = "", pos = 0;
    if (options.indentWithTabs) {
      for (var i = (indentation / tabSize).floor(); i != 0; --i) {
        pos += tabSize; indentString += "\t";
      }
    }
    if (pos < indentation) indentString += spaceStr(indentation - pos);

    if (indentString != curSpaceString) {
      doc.replaceRange(indentString, new Pos(n, 0),
          new Pos(n, curSpaceString.length), "+input");
      line.stateAfter = null;
      return true;
    } else {
      // Ensure that, if the cursor was in the whitespace at the start
      // of the line, it is moved to the end of that space.
      for (var i = 0; i < doc.sel.ranges.length; i++) {
        var range = doc.sel.ranges[i];
        if (range.head.line == n && range.head.char < curSpaceString.length) {
          var pos = new Pos(n, curSpaceString.length);
          doc.replaceOneSelection(i, new Range(pos, pos));
          break;
        }
      }
    }
    return false;
  }

  // Methods to get the editor into a consistent state again when options change.

  void loadMode() {
    doc.mode = getMode(options, doc.modeOption);
    resetModeState();
  }

  void resetModeState() {
    doc.iter((Line line) {
      if (line.stateAfter != null) line.stateAfter = null;
      if (line.styles != null) line.styles = null;
    });
    doc.frontier = doc.first;
    display.startWorker(this, 100);
    state.modeGen++;
    if (curOp != null) regChange();
  }

  void wrappingChanged() {
    if (options.lineWrapping) {
      addClass(display.wrapper, "CodeMirror-wrap");
      display.sizer.style.minWidth = "";
      display.sizerWidth = null;
    } else {
      rmClass(display.wrapper, "CodeMirror-wrap");
      findMaxLine();
    }
    estimateLineHeights();
    regChange();
    clearCaches();
    setTimeout(() { updateScrollbars(); }, 100);
  }

  // Returns a function that estimates the height of a line, to use as
  // first approximation until the line becomes visible (and is thus
  // properly measurable).
  Object estimateHeight() {
    num th = display.textHeight();
    bool wrapping = options.lineWrapping;
    var perLine = wrapping
        ? max(5, display.scroller.clientWidth / display.charWidth() - 3)
        : 0;
    return (Line line) {
      if (doc.lineIsHidden(line)) return 0;

      var widgetsHeight = 0;
      if (line.widgets != null) {
        for (var i = 0; i < line.widgets.length; i++) {
          if (line.widgets[i].height != 0) widgetsHeight += line.widgets[i].height;
        }
      }

      if (wrapping) {
        int h = (line.text.length / perLine).ceil();
        return widgetsHeight + (h == 0 ? 1 : h) * th;
      } else
        return widgetsHeight + th;
    };
  }

  void estimateLineHeights() {
    var est = estimateHeight();
    doc.iter((Line line) {
      var estHeight = est(line);
      if (estHeight != line.height) line.updateLineHeight(estHeight);
    });
  }

  void themeChanged() {
    display.wrapper.className =
        display.wrapper.className.replaceAll(new RegExp(r'\s*cm-s-\S+'), "") +
        options.theme.replaceAll(new RegExp(r'(^|\s)\s*'), " cm-s-");
    clearCaches();
  }

  void guttersChanged() {
    updateGutters();
    regChange();
    setTimeout(() { alignHorizontally(); }, 20);
  }

  // Rebuild the gutter elements, ensure the margin to the left of the
  // code matches their width.
  void updateGutters() {
    var gutters = display.gutters, specs = options.gutters;
    removeChildren(gutters);
    for (var i = 0; i < specs.length; ++i) {
      var gutterClass = specs[i];
      var gElt = gutters.append(eltdiv(null, "CodeMirror-gutter "+gutterClass));
      if (gutterClass == "CodeMirror-linenumbers") {
        display.lineGutter = gElt;
        gElt.style.width = "${max(display.lineNumWidth, 1)}px";
      }
    }
    gutters.style.display = specs.length != 0 ? "" : "none";
    updateGutterSpace();
  }

  void updateGutterSpace() {
    var width = display.gutters.offsetWidth;
    display.sizer.style.marginLeft = "${width}px";
  }

  // Find the longest line in the document.
  findMaxLine() {
    Displ d = display;
    d.maxLine = doc._getLine(doc.first);
    d.maxLineLength = d.maxLine.lineLength();
    d.maxLineChanged = true;
    doc.iter((Line line) {
      var len = line.lineLength();
      if (len > d.maxLineLength) {
        d.maxLineLength = len;
        d.maxLine = line;
      }
    });
  }

  // Create a range of LineView objects for the given lines.
  List<LineView> buildViewArray(int from, int to) {
    var array = [], nextPos;
    for (var pos = from; pos < to; pos = nextPos) {
      var view = new LineView(doc, doc._getLine(pos), pos);
      nextPos = pos + view.size;
      array.add(view);
    }
    return array;
  }

  // Updates the display.view data structure for a given change to the
  // document. From and to are in pre-change coordinates. Lendiff is
  // the amount of lines added or subtracted by the change. This is
  // used for changes that span multiple lines, or change the way
  // lines are divided into visual lines. regLineChange (below)
  // registers single-line changes.
  void regChange([int from = -1, int to = -1, int lendiff = 0]) {
    if (from < 0) from = doc.first;
    if (to < 0) to = doc.first + doc.size;

    if (lendiff != 0 && to < display.viewTo &&
        (display.updateLineNumbers == null || display.updateLineNumbers > from))
      display.updateLineNumbers = from;

    curOp.viewChanged = true;

    if (from >= display.viewTo) { // Change after
      if (sawCollapsedSpans && doc.visualLineNo(from) < display.viewTo)
        resetView();
    } else if (to <= display.viewFrom) { // Change before
      if (sawCollapsedSpans &&
          doc.visualLineEndNo(to + lendiff) > display.viewFrom) {
        resetView();
      } else {
        display.viewFrom += lendiff;
        display.viewTo += lendiff;
      }
    } else if (from <= display.viewFrom && to >= display.viewTo) {
      // Full overlap
      resetView();
    } else if (from <= display.viewFrom) { // Top overlap
      var cut = viewCuttingPoint(to, to + lendiff, 1);
      if (cut != null) {
        display.view = display.view.sublist(cut.index);
        display.viewFrom = cut.lineN;
        display.viewTo += lendiff;
      } else {
        resetView();
      }
    } else if (to >= display.viewTo) { // Bottom overlap
      var cut = viewCuttingPoint(from, from, -1);
      if (cut != null) {
        display.view = display.view.sublist(0, cut.index);
        display.viewTo = cut.lineN;
      } else {
        resetView();
      }
    } else { // Gap in the middle
      var cutTop = viewCuttingPoint(from, from, -1);
      var cutBot = viewCuttingPoint(to, to + lendiff, 1);
      if (cutTop != null && cutBot != null) {
        var tmp = display.view.sublist(0, cutTop.index)
          ..addAll(buildViewArray(cutTop.lineN, cutBot.lineN))
          ..addAll(display.view.sublist(cutBot.index));
        display.view = tmp;
        display.viewTo += lendiff;
      } else {
        resetView();
      }
    }

    var ext = display.externalMeasured;
    if (ext != null) {
      if (to < ext.lineN)
        ext.lineN += lendiff;
      else if (from < ext.lineN + ext.size)
        display.externalMeasured = null;
    }
  }

  resetView() {
    display.resetView(this);
  }

  // Register a change to a single line. Type must be one of "text",
  // "gutter", "class", "widget"
  void regLineChange(int line, String type) {
    curOp.viewChanged = true;
    var ext = display.externalMeasured;
    if (ext != null && line >= ext.lineN && line < ext.lineN + ext.size)
      display.externalMeasured = null;

    if (line < display.viewFrom || line >= display.viewTo) return;
    var lineView = display.view[display.findViewIndex(line)];
    if (lineView.node == null) return;
    if (lineView.changes == null) lineView.changes = [];
    var arr = lineView.changes;
    if (arr.indexOf(type) == -1) arr.add(type);
  }

  CutPoint viewCuttingPoint(int oldN, int newN, [int dir]) {
    int index = display.findViewIndex(oldN), diff;
    var view = display.view;
    if (!sawCollapsedSpans || newN == doc.first + doc.size)
      return new CutPoint(index, newN);
    var n = display.viewFrom;
    for (var i = 0; i < index; i++)
      n += view[i].size;
    if (n != oldN) {
      if (dir > 0) {
        if (index == view.length - 1) return null;
        diff = (n + view[index].size) - oldN;
        index++;
      } else {
        diff = n - oldN;
      }
      oldN += diff; newN += diff;
    }
    while (doc.visualLineNo(newN) != newN) {
      if (index == (dir < 0 ? 0 : view.length - 1)) return null;
      newN += dir * view[index - (dir < 0 ? 1 : 0)].size;
      index += dir;
    }
    return new CutPoint(index, newN);
  }

  // Force the view to cover a given range, adding empty view element
  // or clipping off existing ones as needed.
  adjustView(int from, int to) {
    var view = display.view;
    if (view.length == 0 || from >= display.viewTo || to <= display.viewFrom) {
      display.view = buildViewArray(from, to);
      display.viewFrom = from;
    } else {
      if (display.viewFrom > from) {
        var prev = display.view;
        display.view = buildViewArray(from, display.viewFrom);
        display.view.addAll(prev);
      }
      else if (display.viewFrom < from) {
        display.view = display.view.sublist(display.findViewIndex(from));
      }
      display.viewFrom = from;
      if (display.viewTo < to) {
        display.view = display.view.sublist(0);
        display.view.addAll(buildViewArray(display.viewTo, to));
      } else if (display.viewTo > to) {
        display.view = display.view.sublist(0, display.findViewIndex(to));
      }
    }
    display.viewTo = to;
  }

  // Count the number of lines in the view whose DOM representation is
  // out of date (or nonexistent).
  countDirtyView() {
    var view = display.view, dirty = 0;
    for (var i = 0; i < view.length; i++) {
      var lineView = view[i];
      if (!lineView.hidden && (lineView.node == null || lineView.changes != null)) ++dirty;
    }
    return dirty;
  }

  // Attach the necessary event handlers when initializing the editor
  registerEventHandlers(CodeEditor cm) {
    var d = cm.display;
    on(d.scroller, "mousedown", (e) => operation(cm, () { onMouseDown(e); })());
    // Older IE's will not fire a second mousedown for a double click
    if (ie && ie_version < 11) {
      on(d.scroller, "dblclick", (e) => operation(cm, () {
        if (signalDOMEvent(cm, e)) return;
        var pos = posFromMouse(cm, e);
        if (!pos || clickInGutter(cm, e) || eventInWidget(cm.display, e)) return;
        e_preventDefault(e);
        var word = cm.findWordAt(pos);
        cm.doc._extendSelection(word.anchor, word.head);
      })());
    } else {
      on(d.scroller, "dblclick", (e) {
        if (signalDOMEvent(cm, e) != false) e_preventDefault(e);
      });
    }
    // Some browsers fire contextmenu *after* opening the menu, at
    // which point we can't mess with it anymore. Context menu is
    // handled in onMouseDown for these browsers.
    if (!captureRightClick) {
      on(d.scroller, "contextmenu", (e) { onContextMenu(cm, e); });
    }

    // Used to suppress mouse event handling when a touch happens
    var touchFinished;
    TouchTime prevTouch = new TouchTime.def();
    void finishTouch(TouchEvent e) {
      if (d.activeTouch != null) {
        touchFinished = setTimeout(() {d.activeTouch = null;}, 1000);
        prevTouch = d.activeTouch;
        prevTouch.end = new DateTime.now();
      }
    };
    bool isMouseLikeTouchEvent(TouchEvent e) {
      if (e.touches.length != 1) return false;
      var touch = e.touches[0];
      return touch.radiusX <= 1 && touch.radiusY <= 1;
    }
    bool farAway(touch, other) {
      if (other.left == null) return true;
      var dx = other.left - touch.left, dy = other.top - touch.top;
      return dx * dx + dy * dy > 20 * 20;
    }
    on(d.scroller, "touchstart", (TouchEvent e) {
      if (!isMouseLikeTouchEvent(e)) {
        clearTimeout(touchFinished);
        var now = new DateTime.now();
        d.activeTouch = new TouchTime(now, now.difference(prevTouch.end).inMilliseconds <= 300 ? prevTouch : null, false);
        if (e.touches.length == 1) {
          d.activeTouch.left = e.touches[0].page.x;
          d.activeTouch.top = e.touches[0].page.y;
        }
      }
    });
    on(d.scroller, "touchmove", (TouchEvent e) {
      if (d.activeTouch != null) d.activeTouch.moved = true;
    });
    on(d.scroller, "touchend", (TouchEvent e) {
      var touch = d.activeTouch;
      if (touch != null && !eventInWidget(d, e) && touch.left != null &&
          !touch.moved && new DateTime.now().difference(touch.start).inMilliseconds < 300) {
        var pos = cm.coordsChar(d.activeTouch, "page"), range;
        if (touch.prev == null || farAway(touch, touch.prev)) // Single tap
          range = new Range(pos, pos);
        else if (touch.prev.prev == null || farAway(touch, touch.prev.prev)) // Double tap
          range = cm.findWordAt(pos);
        else // Triple tap
          range = new Range(new Pos(pos.line, 0), cm.doc.clipPos(new Pos(pos.line + 1, 0)));
        cm.setSelection(range.anchor, range.head);
        cm.focus();
        e_preventDefault(e);
      }
      finishTouch(null);
    });
    on(d.scroller, "touchcancel", finishTouch);

    // Sync scrolling between fake scrollbars and real scrollable
    // area, ensure viewport is updated when scrolling.
    on(d.scroller, "scroll", (e) {
      if (d.scroller.clientHeight != 0) {
        setScrollTop(d.scroller.scrollTop);
        setScrollLeft(d.scroller.scrollLeft, true);
        signal(cm, "scroll", cm);
      }
    });

    // Listen to wheel events in order to try and update the viewport on time.
    on(d.scroller, "mousewheel", (e) { onScrollWheel(cm, e); });
    on(d.scroller, "DOMMouseScroll", (e) { onScrollWheel(cm, e); });

    // Prevent wrapper from ever scrolling
    on(d.wrapper, "scroll", (e) {
      d.wrapper.scrollTop = d.wrapper.scrollLeft = 0;
    });

    d.dragFunctions = new DragFunctions(
      simple: (e) {if (!signalDOMEvent(cm, e)) e_stop(e);},
      start: (e) {onDragStart(cm, e);},
      drop: (e) {operation(cm, onDrop(e))();}
    );

    var inp = d.input.getField();
    on(inp, "keyup", (e) { onKeyUp(e); });
    on(inp, "keydown", (e) => operation(cm, () { onKeyDown(e); })());
    on(inp, "keypress", (e) => operation(cm, () { onKeyPress(e); })());
    on(inp, "focus", (e) => onFocus(cm));
    on(inp, "blur", (e) => onBlur(cm));
  }

  dragDropChanged(value, old) {
    var wasOn = old != Options.Init;
    if (!value != !wasOn) {
      var funcs = display.dragFunctions;
      var toggle = value ? on : off;
      toggle(display.scroller, "dragstart", funcs.start);
      toggle(display.scroller, "dragenter", funcs.simple);
      toggle(display.scroller, "dragover", funcs.simple);
      toggle(display.scroller, "drop", funcs.drop);
    }
  }

  // Called when the window resizes
  void onResize(CodeEditor cm) {
    var d = cm.display;
    if (d.lastWrapHeight == d.wrapper.clientHeight &&
        d.lastWrapWidth == d.wrapper.clientWidth)
      return;
    // Might be a text scaling operation, clear size caches.
    d.cachedCharWidth = d.cachedTextHeight = 0;
    d.cachedPaddingH = null;
    d.scrollbarsClipped = false;
    cm.setSize();
  }

  // Return true when the given mouse event happened in a widget
  eventInWidget(Display display, e) {
    for (Node n = e_target(e); n != display.wrapper; n = n.parentNode) {
      if (n == null || (n.nodeType == 1 && _isIgnoreEvents(n)) ||
          (n.parentNode == display.sizer && n != display.mover)) {
        return true;
      }
    }
    return false;
  }

  // Given a mouse event, find the corresponding position. If liberal
  // is false, it checks whether a gutter or scrollbar was clicked,
  // and returns null if it was. forRect is used by rectangular
  // selections, and tries to estimate a character position even for
  // coordinates beyond the right of the text.
  Pos posFromMouse(CodeEditor cm, MouseEvent e,
                   [bool liberal = false, bool forRect = false]) {
    var display = cm.display;
    if (!liberal && e_target(e).getAttribute("cm-not-content") == "true") {
      return null;
    }
    var x, y, space = display.lineSpace.getBoundingClientRect();
    // Fails unpredictably on IE[67] when mouse is dragged around quickly.
    //try { x = e.clientX - space.left; y = e.clientY - space.top; }
    //catch (e) { return null; }
    x = e.client.x - space.left; y = e.client.y - space.top;
    PosWithInfo coords = doc.coordsChar(x, y);
    String line;
    if (forRect && coords.xRel == 1 &&
        (line = cm.doc._getLine(coords.line).text).length == coords.char) {
      var colDiff = countColumn(line, line.length, cm.options.tabSize) -
          line.length;
      num hw = ((x - display.paddingH().left) / display.charWidth()).round();
      return new Pos(coords.line, max(0, hw - colDiff));
    }
    return coords;
  }

  // Helper function from event.dart
  int e_button(MouseEvent e) {
    int b = e.which;
    if (b == null) b = e.button + 1;
    if (mac && e.ctrlKey && b == 1) b = 3;
    return b;
  }

  // A mouse down can be a single click, double click, triple click,
  // start of selection drag, start of text drag, new cursor
  // (ctrl-click), rectangle drag (alt-drag), or xwin
  // middle-click-paste. Or it might be a click on something we should
  // not interfere with, such as a scrollbar or widget.
  onMouseDown(MouseEvent e) {
    CodeEditor cm = this;
    Displ display = cm.display;
    if (display.activeTouch != null && display.input.supportsTouch() ||
        signalDOMEvent(cm, e)) {
      return;
    }
    display.shift = e.shiftKey;

    if (eventInWidget(display, e)) {
      if (!webkit) {
        // Briefly turn off draggability, to allow widgets to do
        // normal dragging things.
        display.scroller.draggable = false;
        setTimeout((){display.scroller.draggable = true;}, 100);
      }
      return;
    }
    if (clickInGutter(cm, e)) return;
    var start = posFromMouse(cm, e);
    //window.focus();

    switch (e_button(e)) {
    case 1:
      if (start != null)
        leftButtonDown(cm, e, start);
      else if (e_target(e) == display.scroller)
        e_preventDefault(e);
      break;
    case 2:
      if (webkit) cm.state.lastMiddleDown = new DateTime.now();
      if (start != null) doc._extendSelection(start);
      setTimeout(() { display.input.focus(); }, 20);
      e_preventDefault(e);
      break;
    case 3:
      if (captureRightClick) onContextMenu(cm, e);
      else delayBlurEvent();
      break;
    }
  }

  ClickTracker lastClick, lastDoubleClick;
  leftButtonDown(CodeEditor cm, MouseEvent e, Pos start) {
    if (ie) setTimeout(display.input.ensureFocus, 0);//bind(ensureFocus, cm), 0);
    else curOp.focus = activeElt();

    var now = new DateTime.now();
    String type;
    if (lastDoubleClick != null && lastDoubleClick.isMultiClick(now, start)) {
      type = "triple";
    } else if (lastClick != null && lastClick.isMultiClick(now, start)) {
      type = "double";
      lastDoubleClick = new ClickTracker(now, start);
    } else {
      type = "single";
      lastClick = new ClickTracker(now, start);
    }

    var sel = cm.doc.sel, modifier = mac ? e.metaKey : e.ctrlKey, contained;
    if (cm.options.dragDrop && !display.input.isReadOnly() &&
        type == "single" && (contained = sel.contains(start)) > -1 &&
        !sel.ranges[contained].empty()) {
      leftButtonStartDrag(cm, e, start, modifier);
    } else {
      leftButtonSelect(cm, e, start, type, modifier);
    }
  }

  // Start a text drag. When it ends, see if any dragging actually
  // happen, and treat as a click if it didn't.
  leftButtonStartDrag(CodeEditor cm, MouseEvent e, start, modifier) {
    var display = cm.display;
    var startTime = new DateTime.now();
//    var dragEnd;
    dragEnd(MouseEvent e) => operation(cm, () {
      if (webkit) display.scroller.draggable = false;
      cm.state.draggingText = null;
      off(document, "mouseup", dragEnd);
      off(display.scroller, "drop", dragEnd);
      if ((e.client.x - e.client.x).abs() +
          (e.client.y - e.client.y).abs() < 10) {
        e_preventDefault(e);
        if (!modifier) {
          var endTime = new DateTime.now();
          var minTime = endTime.subtract(new Duration(milliseconds: 200));
          if (minTime.isBefore(startTime)) doc._extendSelection(start);
        }
        // Work around unexplainable focus problem in IE9 (#2127) and Chrome (#3081)
        //if (ie && ie_version == 9)
        if (webkit) {
          setTimeout(() { document.body.focus(); display.input.focus(); }, 20);
        } else {
          display.input.focus();
        }
      }
    })();
    // Let the drag handler handle this.
    if (webkit) display.scroller.draggable = true;
    cm.state.draggingText = dragEnd;
    // IE's approach to draggable
    // if (display.scroller.dragDrop) display.scroller.dragDrop();
    on(document, "mouseup", dragEnd);
    on(display.scroller, "drop", dragEnd);
  }

  // Normal selection, as opposed to text dragging.
  leftButtonSelect(CodeEditor cm, MouseEvent e, start, type, addNew) {
    var display = cm.display, doc = cm.doc;
    e_preventDefault(e);

    var ourRange, ourIndex, startSel = doc.sel, ranges = startSel.ranges;
    if (addNew && !e.shiftKey) {
      ourIndex = doc.sel.contains(start);
      if (ourIndex > -1)
        ourRange = ranges[ourIndex];
      else
        ourRange = new Range(start, start);
    } else {
      ourRange = doc.sel.primary();
      ourIndex = doc.sel.primIndex;
    }

    if (e.altKey) {
      type = "rect";
      if (!addNew) ourRange = new Range(start, start);
      start = posFromMouse(cm, e, true, true);
      ourIndex = -1;
    } else if (type == "double") {
      var word = cm.findWordAt(start);
      if (cm.display.shift || doc.extend)
        ourRange = doc.extendRange(ourRange, word.anchor, word.head);
      else
        ourRange = word;
    } else if (type == "triple") {
      var line = new Range(new Pos(start.line, 0),
                            doc.clipPos(new Pos(start.line + 1, 0)));
      if (cm.display.shift || doc.extend)
        ourRange = doc.extendRange(ourRange, line.anchor, line.head);
      else
        ourRange = line;
    } else {
      ourRange = doc.extendRange(ourRange, start);
    }

    if (!addNew) {
      ourIndex = 0;
      doc._setSelection(new Selection([ourRange], 0), sel_mouse);
      startSel = doc.sel;
    } else if (ourIndex == -1) {
      ourIndex = ranges.length;
      var list = ranges.sublist(0);
      list.add(ourRange);
      doc._setSelection(normalizeSelection(list, ourIndex),
                   new SelectionOptions(scroll: false, origin: "*mouse"));
    } else if (ranges.length > 1 && ranges[ourIndex].empty() &&
        type == "single" && !e.shiftKey) {
      var list = ranges.sublist(0, ourIndex);
      list.addAll(ranges.sublist(ourIndex + 1));
      doc._setSelection(normalizeSelection(list, 0));
      startSel = doc.sel;
    } else {
      doc.replaceOneSelection(ourIndex, ourRange, sel_mouse);
    }

    var lastPos = start;
    extendTo(pos) {
      if (cmp(lastPos, pos) == 0) return;
      lastPos = pos;

      if (type == "rect") {
        var ranges = [], tabSize = cm.options.tabSize;
        var startCol = countColumn(doc._getLine(start.line).text,
            start.char, tabSize);
        var posCol = countColumn(doc._getLine(pos.line).text, pos.char,tabSize);
        var left = min(startCol, posCol), right = max(startCol, posCol);
        for (var line = min(start.line, pos.line), end = min(cm.doc.lastLine(),
              max(start.line, pos.line)); line <= end; line++) {
          var text = doc._getLine(line).text;
          var leftPos = findColumn(text, left, tabSize);
          if (left == right) {
            ranges.add(
                new Range(new Pos(line, leftPos), new Pos(line, leftPos)));
          } else if (text.length > leftPos) {
            ranges.add(new Range(new Pos(line, leftPos),
                new Pos(line, findColumn(text, right, tabSize))));
          }
        }
        if (ranges.isEmpty) ranges.add(new Range(start, start));
        var r = startSel.ranges.sublist(0, ourIndex);
        r.addAll(ranges);
        doc._setSelection(normalizeSelection(r, ourIndex),
            new SelectionOptions(origin: "*mouse", scroll: false));
        cm.scrollIntoView(pos);
      } else {
        var oldRange = ourRange;
        var anchor = oldRange.anchor, head = pos;
        var range;
        if (type != "single") {
          if (type == "double")
            range = cm.findWordAt(pos);
          else
            range = new Range(new Pos(pos.line, 0), doc.clipPos(new Pos(pos.line + 1, 0)));
          if (cmp(range.anchor, anchor) > 0) {
            head = range.head;
            anchor = minPos(oldRange.from(), range.anchor);
          } else {
            head = range.anchor;
            anchor = maxPos(oldRange.to(), range.head);
          }
        }
        var ranges = startSel.ranges.sublist(0);
        ranges[ourIndex] = new Range(doc.clipPos(anchor), head);
        doc._setSelection(normalizeSelection(ranges, ourIndex), sel_mouse);
      }
    }

    Rectangle editorSize = display.wrapper.getBoundingClientRect();
    // Used to ensure timeout re-tries don't fire when another extend
    // happened in the meantime (clearTimeout isn't reliable -- at
    // least on Chrome, the timeouts still happen even when cleared,
    // if the clear happens after their scheduled firing time).
    num counter = 0;

    extend(MouseEvent e) {
      var curCount = ++counter;
      var cur = posFromMouse(cm, e, true, type == "rect");
      if (cur == null) return;
      if (cmp(cur, lastPos) != 0) {
        cm.curOp.focus = activeElt();
        extendTo(cur);
        var visible = display.visibleLines(doc);
        if (cur.line >= visible.to || cur.line < visible.from)
          setTimeout(() => operation(cm, () {
            if (counter == curCount) extend(e);
          })(), 150);
      } else {
        var outside = e.client.y < editorSize.top
            ? -20
            : e.client.y > editorSize.bottom
                ? 20 : 0;
        if (outside != 0) setTimeout(() =>operation(cm, () {
          if (counter != curCount) return;
          display.scroller.scrollTop += outside;
          extend(e);
        })(), 50);
      }
    }

    Function done;

    move(MouseEvent e) {
      operation(cm, () {
        if (e_button(e) == 0) done(e);
        else extend(e);
      })();
    };
    up(MouseEvent e) {
      operation(cm, () {
        done(e);
      })();
    };

    done = (MouseEvent e) {
      counter = double.INFINITY;
      e_preventDefault(e);
      display.input.focus();
      off(document, "mousemove", move);
      off(document, "mouseup", up);
      doc.history.lastSelOrigin = null;
    };

    on(document, "mousemove", move);
    on(document, "mouseup", up);
  }

  // Determines whether an event happened in the gutter, and fires the
  // handlers for the corresponding event.
  bool gutterEvent(CodeEditor cm, MouseEvent e, String type, bool prevent, Object signalfn) {
    num mX = e.client.x, mY = e.client.y;
    if (mX >= (cm.display.gutters.getBoundingClientRect().right).floor()) return false;
    if (prevent) e_preventDefault(e);

    var display = cm.display;
    var lineBox = display.lineDiv.getBoundingClientRect();

    if (mY > lineBox.bottom || !hasHandler(cm, type)) return e_defaultPrevented(e);
    mY -= lineBox.top - display.viewOffset;

    for (var i = 0; i < cm.options.gutters.length; ++i) {
      var g = display.gutters.childNodes[i];
      if (g != null && g.getBoundingClientRect().right >= mX) {
        var line = doc.lineAtHeight(cm.doc, mY);
        var gutter = cm.options.gutters[i];
        signalfn(cm, type, cm, line, gutter, e);
        return e_defaultPrevented(e);
      }
    }
    return false;
  }

  clickInGutter(CodeEditor cm, Event e) {
    return gutterEvent(cm, e, "gutterClick", true, signalLater);
  }

  // Kludge to work around strange IE behavior where it'll sometimes
  // re-fire a series of drag-related events right after the drop (#1551)
  DateTime lastDrop;

  onDrop(MouseEvent e) {
    final CodeEditor cm = this;
    if (signalDOMEvent(cm, e) || eventInWidget(cm.display, e))
      return;
    e_preventDefault(e);
    if (ie) lastDrop = new DateTime.now();
    var pos = posFromMouse(cm, e, true);
    List files = e.dataTransfer.files;
    if (pos == null || display.input.isReadOnly()) return;
    // Might be a file drop, in which case we simply extract the text
    // and insert it.
    if (files != null && files.length > 0) {
      var n = files.length, text = new List(n), read = 0;
      var loadFile = (file, i) {
        var reader = new FileReader();
        reader.onLoad.listen((fileEvent) { operation(cm, () {
          text[i] = reader.result;
          if (++read == n) {
            pos = cm.doc.clipPos(pos);
            var change = new Change(pos, pos, doc.splitLines(text.join("\n")), "paste");
            doc.makeChange(change);
            doc.setSelectionReplaceHistory(simpleSelection(pos, changeEnd(change)));
          }
        })(); });
        reader.readAsText(file);
      };
      for (var i = 0; i < n; ++i) loadFile(files[i], i);
    } else { // Normal drop
      // Don't do a replace if the drop happened inside of the selected text.
      if (cm.state.draggingText != null && cm.doc.sel.contains(pos) > -1) {
        // At this point draggingText is a function built by operation().
        // It needs to be evaluated with the current event as its arg.
        cm.state.draggingText(e);
        // Ensure the editor is re-focused
        setTimeout(() { cm.display.input.focus(); }, 20);
        return;
      }
      try {
        var text = e.dataTransfer.getData("Text");
        if (!text.isEmpty) {
          var selected;
          if (cm.state.draggingText != null && !(mac ? e.altKey : e.ctrlKey))
            selected = doc.listSelections();
          doc.setSelectionNoUndo(simpleSelection(pos, pos));
          if (selected.length != 0) {
            for (var i = 0; i < selected.length; ++i) {
              doc.replaceRange("", selected[i].anchor, selected[i].head, "drag");
            }
          }
          doc.replaceSelection(text, "around", "paste");
          cm.display.input.focus();
        }
      }
      catch (e) {
        print("$e"); // TODO Remove this debug code.
      }
    }
  }

  onDragStart(CodeEditor cm, MouseEvent e) {
    if (ie) {
      num deltaTime = new DateTime.now().difference(lastDrop).inMilliseconds;
      if (cm.state.draggingText == null || deltaTime < 100) {
        e_stop(e);
        return;
      }
    }
    if (signalDOMEvent(cm, e) || eventInWidget(cm.display, e)) return;

    e.dataTransfer.setData("Text", cm.doc.getSelection());

    // Use dummy image instead of default browsers image.
    // Recent Safari (~6.0.2) have a tendency to segfault when this happens,
    // so we don't do it there.
    if (e.dataTransfer.setDragImage != null && !safari) {
      ImageElement img = eltimg(null,null, "position: fixed; left: 0; top: 0;");
      img.src = // Split this long line.
"data:image/gif;base64,R0lGODlhAQABAAAAACH5BAEKAAEALAAAAAABAAEAAAICTAEAOw==";
      if (presto) {
        img.width = img.height = 1;
        cm.display.wrapper.append(img);
        // Force a relayout, or Opera won't use our image for some obscure reason
//        img._top = img.offsetTop;
      }
      e.dataTransfer.setDragImage(img, 0, 0);
      if (presto) img.remove();
    }
  }

  // SCROLL EVENTS

  // Sync the scrollable area and scrollbars, ensure the viewport
  // covers the visible area.
  void setScrollTop(num val) {
    if (val == null) val = 0; else val = val.round();
    if ((doc.scrollTop - val).abs() < 2) return;
    doc.scrollTop = val;
    if (!gecko) display.updateDisplaySimple(this, new Viewport(val));
    if (display.scroller.scrollTop != val) {
      display.scroller.scrollTop = val;
    }
    display.scrollbars.setScrollTop(val);
    if (gecko) display.updateDisplaySimple(this, null);
    display.startWorker(this, 100);
  }
  // Sync scroller and scrollbar, ensure the gutter elements are
  // aligned.
  setScrollLeft(num val, [bool isScroller = false]) {
    if (val == null) val = 0; else val = val.round();
    if ((isScroller && val == doc.scrollLeft) ||
        (doc.scrollLeft - val).abs() < 2) {
      return;
    }
    DivElement scrlr = display.scroller;
    val = min(val, scrlr.scrollWidth - scrlr.clientWidth).round();
    doc.scrollLeft = val;
    alignHorizontally();
    if (display.scroller.scrollLeft != val) {
      display.scroller.scrollLeft = val;
    }
    display.scrollbars.setScrollLeft(val);
  }

  // Since the delta values reported on mouse wheel events are
  // unstandardized between browsers and even browser versions, and
  // generally horribly unpredictable, this code starts by measuring
  // the scroll effect that the first few mouse wheel events have,
  // and, from that, detects the way it can convert deltas to pixel
  // offsets afterwards.
  //
  // The reason we want to know the amount a wheel event will scroll
  // is that it gives us a chance to update the display before the
  // actual scrolling happens, reducing flickering.
  var wheelSamples = 0;
  static double wheelPixelsPerUnit = initWheelPixelsPerUnit();
  // Fill in a browser-detected starting value on browsers where we
  // know one. These don't have to be accurate -- the result of them
  // being wrong would just be a slight flicker on the first wheel
  // scroll (if it is large enough).
  static double initWheelPixelsPerUnit() {
    double wppu = 0.0;
    if (ie) wppu = -.53;
    else if (gecko) wppu = 15.0;
    else if (chrome) wppu = -.7;
    else if (safari) wppu = -1/3;
    return wppu;
  }

  wheelEventDelta(WheelEvent e) {
    var dx = e.wheelDeltaX, dy = e.wheelDeltaY;
    // Comment out old Firefox code
    //if(dx == null && e.detail != 0 && e.axis == e.HORIZONTAL_AXIS)dx=e.detail;
    //if(dy == null && e.detail != 0 && e.axis == e.VERTICAL_AXIS)dy=e.detail;
    //else if (dy == null) dy = e.wheelDelta;
    return [dx, dy];
  }
  wheelEventPixels(WheelEvent e) {
    var delta = wheelEventDelta(e);
    delta[0] *= wheelPixelsPerUnit;
    delta[1] *= wheelPixelsPerUnit;
    return delta;
  }

  onScrollWheel(cm, e) {
    var delta = wheelEventDelta(e), dx = delta[0], dy = delta[1];

    var display = cm.display, scroll = display.scroller;
    // Quit if there's nothing to scroll here
    if (!(dx != 0 && scroll.scrollWidth > scroll.clientWidth ||
          dy != 0 && scroll.scrollHeight > scroll.clientHeight)) {
      return;
    }

    // Webkit browsers on OS X abort momentum scrolls when the target
    // of the scroll event is removed from the scrollable element.
    // This hack (see related code in patchDisplay) makes sure the
    // element is kept around.
    if (dy != 0 && mac && webkit) {
      var view = display.view;
      outer: for (var cur = e.target; cur != scroll; cur = cur.parentNode) {
        for (var i = 0; i < view.length; i++) {
          if (view[i].node == cur) {
            cm.display.currentWheelTarget = cur;
            break outer;
          }
        }
      }
    }

    // On some browsers, horizontal scrolling will cause redraws to
    // happen before the gutter has been realigned, causing it to
    // wriggle around in a most unseemly way. When we have an
    // estimated pixels/delta value, we just handle horizontal
    // scrolling entirely here. It'll be slightly off from native, but
    // better than glitching out.
    if (dx != 0 && !gecko && !presto && wheelPixelsPerUnit != null) {
      if (dy != 0) {
        setScrollTop(max(0,
            min(scroll.scrollTop + dy * wheelPixelsPerUnit,
                    scroll.scrollHeight - scroll.clientHeight)));
      }
      setScrollLeft(max(0,
            min(scroll.scrollLeft + dx * wheelPixelsPerUnit,
                    scroll.scrollWidth - scroll.clientWidth)));
      e_preventDefault(e);
      display.wheelStartX = null; // Abort measurement, if in progress
      return;
    }

    // 'Project' the visible viewport to cover the area that is being
    // scrolled into view (if we know enough to estimate it).
    if (dy != 0 && wheelPixelsPerUnit != 0) {
      num pixels = dy * wheelPixelsPerUnit;
      num top = cm.doc.scrollTop, bot = top + display.wrapper.clientHeight;
      if (pixels < 0) top = max(0, top + pixels - 50);
      else bot = min(cm.doc.height, bot + pixels + 50);
      display.updateDisplaySimple(cm, new Viewport(top, bot));
    }

    if (wheelSamples < 20) {
      if (display.wheelStartX == null) {
        display.wheelStartX = scroll.scrollLeft;
        display.wheelStartY = scroll.scrollTop;
        display.wheelDX = dx;
        display.wheelDY = dy;
        setTimeout(() {
          if (display.wheelStartX == null) return;
          var movedX = scroll.scrollLeft - display.wheelStartX;
          var movedY = scroll.scrollTop - display.wheelStartY;
          num sample = 0;
          if (movedY != 0 && display.wheelDY != 0) {
            sample = movedY / display.wheelDY;
          } else if (movedX != 0 && display.wheelDX != 0) {
            sample = movedX / display.wheelDX;
          }
          display.wheelStartX = display.wheelStartY = null;
          if (sample == 0) return;
          wheelPixelsPerUnit = (wheelPixelsPerUnit * wheelSamples + sample) /
              (wheelSamples + 1);
          ++wheelSamples;
        }, 200);
      } else {
        display.wheelDX += dx;
        display.wheelDY += dy;
      }
    }
  }

  // Run a handler that was bound to a key.
  doHandleBinding(bound, [bool dropShift = false]) {
    if (bound is String) {
      bound = commands[bound];
      if (bound == null) return false;
    }
    // Ensure previous input has been read, so that the handler sees a
    // consistent view of the document
    display.input.ensurePolled();
    var prevShift = display.shift, done = false;
    try {
      if (display.input.isReadOnly()) state.suppressEdits = true;
      if (dropShift) display.shift = false;
      done = bound(this) != Pass;
    } finally {
      display.shift = prevShift;
      state.suppressEdits = false;
    }
    return done;
  }

  lookupKeyForEditor(String name, Function handle) {
    for (var i = 0; i < state.keyMaps.length; i++) {
      var result = lookupKey(name, state.keyMaps[i], handle);
      if (result != null) return result;
    }
    var result;
    if (options.extraKeys != null) result = lookupKey(name, options.extraKeys, handle);
    if (result == null) result = lookupKey(name, options.keyMap, handle);
    return result;
  }

  var stopSeq = new Delayed();
  dynamic dispatchKey(String name, e, Function handle) { // bool or String
    var seq = state.keySeq;
    if (seq != null) {
      if (isModifierKey(name)) return "handled";
      stopSeq.set(50, () {
        if (state.keySeq == seq) {
          state.keySeq = null;
          display.input.reset();
        }
      });
      name = seq + " " + name;
    }
    var result = lookupKeyForEditor(name, handle);

    if (result == "multi")
      state.keySeq = name;
    if (result == "handled")
      signalLater(this, "keyHandled", this, name, e);

    if (result == "handled" || result == "multi") {
      e_preventDefault(e);
      display.restartBlink(this);
    }

    if (seq != null && result == null && new RegExp(r"\'$").hasMatch(name)) {
      e_preventDefault(e);
      return true;
    }
    return result == null ? false : result;
  }

  // Handle a key from the keydown event.
  handleKeyBinding(e) {
    var name = keyName(e, true);
    if (name == null) return false;

    if (e.shiftKey && state.keySeq == null) {
      // First try to resolve full name (including 'Shift-'). Failing
      // that, see if there is a cursor-motion command (starting with
      // 'go') bound to the keyname without 'Shift-'.
      var disShift =  dispatchKey("Shift-" + name, e, (b) { return doHandleBinding(b, true); });
      if (disShift != false) return disShift;
      return dispatchKey(name, e, (b) {
               if (b is String ? b.startsWith("go") : b is KeySpec) {
                 return doHandleBinding(b);
               } else {
                 return false;
               }
             });
    } else {
      return dispatchKey(name, e, (b) { return doHandleBinding(b); });
    }
  }

  // Handle a key from the keypress event
  handleCharBinding(e, String ch) {
    return dispatchKey("'" + ch + "'", e,
                       (b) { return doHandleBinding(b, true); });
  }

  var lastStoppedKey = null;
  onKeyDown(var e) {
    curOp.focus = activeElt();
    if (signalDOMEvent(this, e)) return;
    // IE does strange things with escape. (Ignoring pre 11)
//    if (ie && ie_version < 11 && e.keyCode == 27) e.returnValue = false;
    var code = e.keyCode;
    display.shift = code == 16 || e.shiftKey;
    var handled = handleKeyBinding(e);
    if (presto) {
      lastStoppedKey = handled ? code : null;
      // Opera has no cut event... we try to at least catch the key combo
      if (!handled && code == 88 && !hasCopyEvent && (mac ? e.metaKey : e.ctrlKey))
        doc.replaceSelection("", null, "cut");
    }

    // Turn mouse into crosshair when Alt is held on Mac.
    if (code == 18 && !new RegExp(r'\bCodeMirror-crosshair\b').hasMatch(display.lineDiv.className))
      showCrossHair();
  }

  showCrossHair() {
    var lineDiv = display.lineDiv;
    addClass(lineDiv, "CodeMirror-crosshair");

    up(e) {
      if ((e is! MouseEvent && e.keyCode == 18) || !e.altKey) {
        rmClass(lineDiv, "CodeMirror-crosshair");
        off(document, "keyup", up);
        off(document, "mouseover", up);
      }
    }
    on(document, "keyup", up);
    on(document, "mouseover", up);
  }

  onKeyUp(KeyboardEvent e) {
    // The original code has doc.sel.shift = false but that looks like a bug.
    if (e.keyCode == 16) display.shift = false;
    signalDOMEvent(this, e);
  }

  onKeyPress(KeyboardEvent e) {
    if (eventInWidget(display, e) || signalDOMEvent(this, e) ||
        e.ctrlKey && !e.altKey || mac && e.metaKey) {
      return;
    }
    var keyCode = e.keyCode, charCode = e.charCode;
    if (presto && keyCode == lastStoppedKey) {
      lastStoppedKey = null; e_preventDefault(e);
      return;
    }
    if (((presto && (e.which < 10))) && handleKeyBinding(e)) {
      return;
    }
    var ch = new String.fromCharCode(charCode == null ? keyCode : charCode);
    if (handleCharBinding(e, ch) != null) return;
    display.input.onKeyPress(e);
  }

  // FOCUS/BLUR EVENTS

  delayBlurEvent() {
    state.delayingBlurEvent = true;
    setTimeout(() {
      if (state.delayingBlurEvent) {
        state.delayingBlurEvent = false;
        onBlur(this);
      }
    }, 100);
  }

  onFocus(CodeEditor cm) {
    if (cm.state.delayingBlurEvent) cm.state.delayingBlurEvent = false;

    if (options.readOnly == "nocursor") return;
    if (!state.focused) {
      signal(this, "focus", this);
      state.focused = true;
      addClass(display.wrapper, "CodeMirror-focused");
      // This test prevents this from firing when a context
      // menu is closed (since the input reset would kill the
      // select-all detection hack)
      if (curOp == null && display.selForContextMenu != doc.sel) {
        cm.display.input.reset();
        if (webkit) setTimeout(() { cm.display.input.reset(true); }, 20); // Issue #1730
      }
      cm.display.input.receivedFocus();
    }
    display.restartBlink(this);
  }
  onBlur(CodeEditor cm) {
    if (cm.state.delayingBlurEvent) return;

    if (state.focused) {
      signal(this, "blur", this);
      state.focused = false;
      rmClass(display.wrapper, "CodeMirror-focused");
    }
    display.stopBlink();
    setTimeout(() { if (!state.focused) display.shift = false; }, 150);
  }

  // To make the context menu work, we need to briefly unhide the
  // textarea (making it as unobtrusive as possible) to let the
  // right-click take effect on it.
  onContextMenu(cm, e) {
    if (eventInWidget(cm.display, e) || contextMenuInGutter(cm, e)) return;
    cm.display.input.onContextMenu(e);
  }

  contextMenuInGutter(cm, e) {
    if (!hasHandler(cm, "gutterContextMenu")) return false;
    return gutterEvent(cm, e, "gutterContextMenu", false, signal);
  }

  // Compute the position of the end of a change (its 'to' property
  // refers to the pre-change end).
  Pos changeEnd(Change change) => doc.changeEnd(change);

  // If an editor sits on the top or bottom of the window, partially
  // scrolled out of view, this ensures that the cursor is visible.
  void maybeScrollWindow(Rect coords) {
    if (signalDOMEvent(this, "scrollCursorIntoView")) return;

    var box = display.sizer.getBoundingClientRect(), doScroll = null;
    if (coords.top + box.top < 0) {
      doScroll = true;
    } else if (coords.bottom + box.top >
        (window.innerHeight == 0
            ? document.documentElement.clientHeight
            : window.innerHeight)) {
      doScroll = false;
    }
    if (doScroll != null && !phantom) {
      var scrollNode = eltdiv("\u200b", null,
          "position: absolute; " +
          "top: ${coords.top - display.viewOffset - display.paddingTop()}px; " +
          "height: ${coords.bottom - coords.top + display.scrollGap() + display.barHeight}px; " +
          "left: ${coords.left}px; width: 2px;");
      display.lineSpace.append(scrollNode);
      scrollNode.scrollIntoView(doScroll ? ScrollAlignment.TOP : ScrollAlignment.BOTTOM);
      scrollNode.remove();
    }
  }

  // Scroll a given position into view (immediately), verifying that
  // it actually became visible (as line heights are accurately
  // measured, the position of something may 'drift' during drawing).
  Rect scrollPosIntoView(Pos pos, Pos end, [int margin = 0]) {
    var coords;
    for (var limit = 0; limit < 5; limit++) {
      var changed = false;
      coords = doc.cursorCoords(pos);
      var endCoords = end == null || end == pos ? coords : doc.cursorCoords(end);
      var scrollPos = calculateScrollPos(min(coords.left, endCoords.left),
                                         min(coords.top, endCoords.top) - margin,
                                         max(coords.left, endCoords.left),
                                         max(coords.bottom, endCoords.bottom) + margin);
      var startTop = doc.scrollTop, startLeft = doc.scrollLeft;
      if (scrollPos.scrollTop != null) {
        setScrollTop(scrollPos.scrollTop);
        if ((doc.scrollTop - startTop).abs() > 1) changed = true;
      }
      if (scrollPos.scrollLeft != null) {
        setScrollLeft(scrollPos.scrollLeft);
        if ((doc.scrollLeft - startLeft).abs() > 1) changed = true;
      }
      if (!changed) break;
    }
    return coords;
  }

  // Scroll a given set of coordinates into view (immediately).
  void _scrollIntoView(x1, y1, x2, y2) {
    var scrollPos = calculateScrollPos(x1, y1, x2, y2);
    if (scrollPos.scrollTop != 0) setScrollTop(scrollPos.scrollTop);
    if (scrollPos.scrollLeft != 0) setScrollLeft(scrollPos.scrollLeft);
  }

  // Calculate a new scroll position needed to scroll the given
  // rectangle into view. Returns an object with scrollTop and
  // scrollLeft properties. When these are undefined, the
  // vertical/horizontal position does not need to be adjusted.
  ScrollPos calculateScrollPos(num x1, num y1, num x2, num y2) {
    var snapMargin = display.textHeight();
    if (y1 < 0) y1 = 0;
    var screentop = curOp != null && curOp.scrollTop >= 0 ? curOp.scrollTop : display.scroller.scrollTop;
    int screen = display.displayHeight();
    var result = new ScrollPos();
    if (y2 - y1 > screen) y2 = y1 + screen;
    var docBottom = doc.height + display.paddingVert();
    bool atTop = y1 < snapMargin;
    bool atBottom = y2 > docBottom - snapMargin;
    if (y1 < screentop) {
      result.scrollTop = atTop ? 0 : y1.round();
    } else if (y2 > screentop + screen) {
      var newTop = min(y1, (atBottom ? docBottom : y2) - screen);
      if (newTop != screentop) result.scrollTop = newTop.round();
    }

    var screenleft = curOp != null && curOp.scrollLeft >= 0 ? curOp.scrollLeft : display.scroller.scrollLeft;
    var screenw = display.displayWidth() - (options.fixedGutter ? display.gutters.offsetWidth : 0);
    var tooWide = x2 - x1 > screenw;
    if (tooWide) x2 = x1 + screenw;
    if (x1 < 10)
      result.scrollLeft = 0;
    else if (x1 < screenleft)
      result.scrollLeft = max(0, x1 - (tooWide ? 0 : 10)).round();
    else if (x2 > screenw + screenleft - 3)
      result.scrollLeft = (x2 + (tooWide ? 0 : 10) - screenw).round();
    return result;
  }

  // Store a relative adjustment to the scroll position in the current
  // operation (to be applied when the operation finishes).
  void addToScrollPos(num left, num top) {
    if (left != null || top != null) resolveScrollToPos();
    if (left != null)
      curOp.scrollLeft = (curOp.scrollLeft < 0 ? doc.scrollLeft : curOp.scrollLeft) + left.round();
    if (top != null)
      curOp.scrollTop = (curOp.scrollTop < 0 ? doc.scrollTop : curOp.scrollTop) + top.round();
  }

  // Make sure that at the end of the operation the current cursor is
  // shown.
  void ensureCursorVisible() {
    resolveScrollToPos();
    var cur = doc.getCursor(null), from = cur, to = cur;
    if (!options.lineWrapping) {
      from = cur.char > 0 ? new Pos(cur.line, cur.char - 1) : cur;
      to = new Pos(cur.line, cur.char + 1);
    }
    curOp.scrollToPos = new ScrollDelta(from, to, options.cursorScrollMargin, true);
  }

  // When an operation has its scrollToPos property set, and another
  // scroll action is applied before the end of the operation, this
  // 'simulates' scrolling that position into view in a cheap way, so
  // that the effect of intermediate scroll commands is not ignored.
  void resolveScrollToPos() {
    var range = curOp.scrollToPos;
    if (range != null) {
      curOp.scrollToPos = null;
      var from = doc.estimateCoords(range.from), to = doc.estimateCoords(range.to);
      var sPos = calculateScrollPos(min(from.left, to.left),
                                    min(from.top, to.top) - range.margin,
                                    max(from.right, to.right),
                                    max(from.bottom, to.bottom) + range.margin);
      scrollTo(sPos.scrollLeft, sPos.scrollTop);
    }
  }

  // Helper for deleting text near the selection(s), used to implement
  // backspace, delete, and similar functionality.
  void deleteNearSelection(RangeFn compute) {
    var ranges = doc.sel.ranges, kill = [];
    // Build up a set of ranges to kill first, merging overlapping ranges.
    for (var i = 0; i < ranges.length; i++) {
      var toKill = compute(ranges[i]);
      while (kill.length > 0 && cmp(toKill.from, lst(kill).to) <= 0) {
        var replaced = kill.removeLast();
        if (cmp(replaced.from, toKill.from) < 0) {
          toKill.from = replaced.from;
          break;
        }
      }
      kill.add(toKill);
    }
    // Next, remove those actual ranges.
    runInOp(this, () {
      for (var i = kill.length - 1; i >= 0; i--)
        doc.replaceRange("", kill[i].from, kill[i].to, "+delete");
      ensureCursorVisible();
    });
  }

  adjustScrollWhenAboveVisible(line, diff) {
    if (doc.heightAtLine(line) < (curOp != null && curOp.scrollTop == -1 ? doc.scrollTop : curOp.scrollTop))
      addToScrollPos(null, diff);
  }

  // KEYMAP DISPATCH

  String normalizeKeyName(String nm) {
    var parts = nm.split(new RegExp(r'-(?!$)'));
    var name = parts[parts.length - 1];
    bool alt, ctrl, shift, cmd;
    bool test(String pattern, String candidate) {
      RegExp exp = new RegExp(pattern, caseSensitive: false);
      return exp.hasMatch(candidate);
    }
    for (var i = 0; i < parts.length - 1; i++) {
      var mod = parts[i];
      if (test(r'^(cmd|meta|m)$', mod)) cmd = true;
      else if (test(r'^a(lt)?$', mod)) alt = true;
      else if (test(r'^(c|ctrl|control)$', mod)) ctrl = true;
      else if (test(r'^s(hift)$', mod)) shift = true;
      else throw new StateError("Unrecognized modifier name: " + mod);
    }
    if (alt) name = "Alt-" + name;
    if (ctrl) name = "Ctrl-" + name;
    if (cmd) name = "Cmd-" + name;
    if (shift) name = "Shift-" + name;
    return name;
  }

  // This is a kludge to keep keymaps mostly working as raw objects
  // (backwards compatibility) while at the same time support features
  // like normalization and multi-stroke key bindings. It compiles a
  // new normalized keymap, and then updates the old object to reflect
  // this.
  Map normalizeKeyMap(Map keymap) {
    var copy = {};
    for (String keyname in keymap) if (keymap.containsKey(keyname)) {
      var value = keymap[keyname];
      if (new RegExp(r'^(name|fallthrough|(de|at)tach)$').hasMatch(keyname)) continue;
      if (value == "...") { keymap.remove(keyname); continue; }

      var keys = keyname.split(" ").map(normalizeKeyName);
      for (var i = 0; i < keys.length; i++) {
        var val, name;
        if (i == keys.length - 1) {
          name = keys.join(" ");
          val = value;
        } else {
          name = keys.sublist(0, i + 1).join(" ");
          val = "...";
        }
        var prev = copy[name];
        if (!prev) copy[name] = val;
        else if (prev != val) throw new StateError("Inconsistent bindings for " + name);
      }
      keymap.remove(keyname);
    }
    for (var prop in copy) keymap[prop] = copy[prop];
    return keymap;
  }

  lookupKey(key, map, handle, [context]) {
    map = getKeyMap(map);
    var found = /*map.call ? map.call(key, context) :*/ map[key];
    if (found == false) return "nothing";
    if (found == "...") return "multi";
    if (found != null && handle(found)) return "handled";

    if (map is KeyMap && map.fallthrough != null) {
      for (var i = 0; i < map.fallthrough.length; i++) {
        var result = lookupKey(key, map.fallthrough[i], handle, context);
        if (result != null) return result;
      }
    }
    return null;
  }

  // Modifier key presses don't count as 'real' key presses for the
  // purpose of keymap fallthrough.
  isModifierKey(value) {
    var name = value is String ? value : KeyMap.keyNames[value.keyCode];
    return name == "Ctrl" || name == "Alt" || name == "Shift" || name == "Mod";
  }

  // Look up the name of a key as indicated by an event object.
  keyName(event, noShift) {
//    if (presto && event.keyCode == 34 && event["char"]) return false; // TODO presto
    var base = KeyMap.keyNames[event.keyCode], name = base;
    if (event.altKey && base != "Alt") name = "Alt-" + name;
    if ((flipCtrlCmd ? event.metaKey : event.ctrlKey) && base != "Ctrl") name = "Ctrl-" + name;
    if ((flipCtrlCmd ? event.ctrlKey : event.metaKey) && base != "Cmd") name = "Cmd-" + name;
    if (!noShift && event.shiftKey && base != "Shift") name = "Shift-" + name;
    return name;
  }

  dynamic getKeyMap(dynamic val) {
    return val is String ? keyMap[val] : val;
  }

  // These must be handled carefully, because naively registering a
  // handler for each editor will cause the editors to never be
  // garbage collected.
  void _registerGlobalHandlers() {
    // When the window resizes, we need to refresh active editors.
    var resizeTimer;
    on(window, "resize", (e) {
      if (resizeTimer == null) resizeTimer = setTimeout(() {
        resizeTimer = null;
        forEachCodeMirror(onResize);
      }, 100);
    });
    // When the window loses focus, we want to show the editor as blurred
    on(window, "blur", (e) {
      forEachCodeMirror(onBlur);
    });
    on(window, "unload", (e) {
      // remove CodeMirror from DivElement->CodeMirror map
      forEachCodeMirror(_dispose);
    });
  }

  void forEachCodeMirror(f) {
    List<Node> byClass = document.body.getElementsByClassName("CodeMirror");
    for (var i = 0; i < byClass.length; i++) {
//      var cm = byClass[i].CodeMirror;
      var cm = _elementCache[byClass[i]];
      if (cm != null) f(cm);
    }
  }

  static bool _globalsRegistered = false;
  void _ensureGlobalHandlers() {
    if (_globalsRegistered) return;
    _registerGlobalHandlers();
    _globalsRegistered = true;
  }

  // Re-align line numbers and gutter marks to compensate for
  // horizontal scrolling.
  void alignHorizontally() {
    if (!display.alignWidgets &&
        (display.gutters.firstChild == null || !options.fixedGutter)) {
      return;
    }
    var view = display.view;
    var comp = display.compensateForHScroll() -
        display.scroller.scrollLeft + doc.scrollLeft;
    var gutterW = display.gutters.offsetWidth;
    var left = "${comp}px";
    for (var i = 0; i < view.length; i++) if (!view[i].hidden) {
      if (options.fixedGutter && view[i].gutter != null)
        view[i].gutter.style.left = left;
      var align = view[i].alignable;
      if (align != null) {
        for (var j = 0; j < align.length; j++) {
          align[j].style.left = left;
        }
      }
    }
    if (options.fixedGutter)
      display.gutters.style.left = "${comp + gutterW}px";
  }

  // Used to ensure that the line number gutter is still the right
  // size for the current document size. Returns true when an update
  // is needed.
  bool maybeUpdateLineNumberWidth() {
    if (!options.lineNumbers) return false;
    var last = lineNumberFor(doc.first + doc.size - 1);
    if (last.length != display.lineNumChars) {
      var test = display.measure.append(eltdiv([eltdiv(last)],
                            "CodeMirror-linenumber CodeMirror-gutter-elt"));
      var innerW = test.firstChild.offsetWidth;
      var padding = test.offsetWidth - innerW;
      display.lineGutter.style.width = "";
      display.lineNumInnerWidth = max(innerW, display.lineGutter.offsetWidth - padding);
      display.lineNumWidth = display.lineNumInnerWidth + padding;
      display.lineNumChars = display.lineNumInnerWidth != 0 ? last.length : -1;
      display.lineGutter.style.width = "${display.lineNumWidth}px";
      updateGutterSpace();
      return true;
    }
    return false;
  }

  String lineNumberFor(i) {
    return options.lineNumberFormatter(i + options.firstLineNumber);
  }

  extractLineClasses(type, output) {
    if (type != null) for (;;) {
      Match lineClass = new RegExp(r"(?:^|\s+)line-(background-)?(\S+)").firstMatch(type);
      if (lineClass == null) break;
      type = type.substring(0, lineClass.start) + type.substring(lineClass.start + lineClass.group(0).length);
      var prop = lineClass.group(1) != null ? "bgClass" : "textClass";
      if (output.getClass(prop) == null)
        output.setClass(prop, lineClass.group(2));
      else if (!(new RegExp(r"(?:^|\s)" + lineClass.group(2) + r"(?:$|\s)")).hasMatch(output.getClass(prop)))
        output.setClass(prop, "${output.getClass(prop)} ${lineClass.group(2)}");
    }
    return type;
  }

  callBlankLine(Mode mode, dynamic state) {
    if (mode.hasBlankLine) return mode.blankLine(state);
    if (!mode.hasInnerMode) return null;
    var inner = innerMode(mode, state);
    if (inner.hasBlankLine) return inner.blankLine(inner.state);
    return null;
  }

  readToken(Mode mode, StringStream stream, dynamic state, [inner]) {
    for (var i = 0; i < 10; i++) {
      if (inner != null && inner != false) inner[0] = innerMode(mode, state);
      var style = mode.token(stream, state);
      if (stream.pos > stream.start) return style;
    }
    throw new StateError("Mode ${mode.name} failed to advance stream.");
  }

  // Utility for getTokenAt and getLineTokens
  takeToken(pos, precise, asArray) {
    var stream, style, state;
    getObj(bool copy) {
      return new Token(stream.start, stream.pos,
              stream.current(),
              style == null ? "" : style,
              copy ? copyState(doc.mode, state) : state);
    }

    var mode = doc.mode;
    pos = doc.clipPos(pos);
    var line = doc._getLine(pos.line);
    state = getStateBefore(pos.line, precise);
    stream = new StringStream(line.text, options.tabSize);
    var tokens;
    if (asArray) tokens = [];
    while ((asArray || stream.pos < pos.char) && !stream.eol()) {
      stream.start = stream.pos;
      style = readToken(mode, stream, state);
      if (asArray) tokens.add(getObj(true));
    }
    return asArray ? tokens : getObj(false);
  }

  // Run the given mode's parser over a line, calling f for each token.
  runMode(CodeEditor cm, text, mode, state, f, lineClasses, [bool forceToEnd = false]) {
    bool flattenSpans;
    if (mode != true && mode.hasFlattenSpans) flattenSpans = mode.flattenSpans;
    else flattenSpans = cm.options.flattenSpans;
    var curStart = 0, curStyle = null;
    var stream = new StringStream(text, cm.options.tabSize), style;
    var inner;
    if (cm.options.addModeClass) {
      inner = [null];
    } else {
      inner = false;
    }
    if (text == "") extractLineClasses(callBlankLine(mode, state), lineClasses);
    while (!stream.eol()) {
      if (stream.pos > cm.options.maxHighlightLength) {
        flattenSpans = false;
        if (forceToEnd) processLine(text, state, stream.pos);
        stream.pos = text.length;
        style = null;
      } else {
        style = extractLineClasses(readToken(mode, stream, state, inner), lineClasses);
      }
      if (inner != null && inner != false) {
        var mName = inner[0].name;
        if (mName) style = "m-" + (style != null ? mName + " " + style : mName);
      }
      if (!flattenSpans || curStyle != style) {
        while (curStart < stream.start) {
          curStart = min(stream.start, curStart + 50000);
          f(curStart, curStyle);
        }
        curStyle = style;
      }
      stream.start = stream.pos;
    }
    while (curStart < stream.pos) {
      // Webkit seems to refuse to render text nodes longer than 57444 characters
      var pos = min(stream.pos, curStart + 50000);
      f(pos, curStyle);
      curStart = pos;
    }
  }

  // Compute a style array (an array starting with a mode generation
  // -- for invalidation -- followed by pairs of end positions and
  // style strings), which is used to highlight the tokens on the
  // line.
  LineHighlight highlightLine(Line line, state, [bool forceToEnd = false]) {
    // A styles array always starts with a number identifying the
    // mode/overlays that it is based on (for easy invalidation).
    var st = [this.state.modeGen], lineClasses = new LineClasses();
    // Compute the base array of styles
    runMode(this, line.text, doc.mode, state, (end, style) {
      st..add(end)..add(style);
    }, lineClasses, forceToEnd);

    // Run overlays, adjust style array.
    for (var o = 0; o < this.state.overlays.length; ++o) {
      var overlay = this.state.overlays[o], i = 1, at = 0;
      runMode(this, line.text, overlay['mode'], true, (end, style) {
        var start = i;
        // Ensure there's a token end at the current position, and that i points at it
        while (at < end) {
          var i_end = st[i];
          if (i_end > end) {
            st.removeAt(i);
            st..insert(i, end)..insert(i + 1, st[i+1])..insert(i+2, i_end);
//            st.splice(i, 1, end, st[i+1], i_end);
          }
          i += 2;
          at = min(end, i_end);
        }
        if (style == null) return;
        if (overlay['opaque']) {
          st.removeRange(start, i);
          st..insert(start, end)..insert(start + 1, "cm-overlay " + style);
//          st.splice(start, i - start, end, "cm-overlay " + style);
          i = start + 2;
        } else {
          for (; start < i; start += 2) {
            var cur = st[start+1];
            st[start+1] = (cur != null ? cur + " " : "") + "cm-overlay " + style;
          }
        }
      }, lineClasses);
    }

    return new LineHighlight(st,
        lineClasses.bgClass != null || lineClasses.textClass != null
          ? lineClasses : null);
  }

  List getLineStyles(Line line, int updateFrontier) {
    if (line.styles == null || line.styles[0] != state.modeGen) {
      var result = highlightLine(line, line.stateAfter = getStateBefore(line.lineNo()));
      line.styles = result.styles;
      if (result.classes != null) line.styleClasses = result.classes;
      else if (line.styleClasses != null) line.styleClasses = null;
      if (updateFrontier == doc.frontier) doc.frontier++;
    }
    return line.styles;
  }

  // Lightweight form of highlight -- proceed over this line and
  // update state, but don't save a style array. Used for lines that
  // aren't currently visible.
  void processLine(String text, state, [int startAt = 0]) {
    var mode = doc.mode;
    var stream = new StringStream(text, options.tabSize);
    stream.start = stream.pos = startAt;
    if (text == "") callBlankLine(mode, state);
    while (!stream.eol() && stream.pos <= options.maxHighlightLength) {
      readToken(mode, stream, state);
      stream.start = stream.pos;
    }
  }

  // Convert a style as returned by a mode (either null, or a string
  // containing one or more styles) to a CSS style. This is cached,
  // and also looks for line-wide styles.
  var styleToClassCache = {}, styleToClassCacheWithMode = {};
  String interpretTokenStyle(String style, options) {
    if (style == null || new RegExp(r'^\s*$').hasMatch(style)) {
      return null;
    }
    var cache = options.addModeClass
        ? styleToClassCacheWithMode : styleToClassCache;
    if (cache[style] == null) {
      cache[style] = style.replaceAllMapped(
          new RegExp(r'\S+'),
          (Match m) => "cm-${m.group(0)}");
    }
    return cache[style];
  }

  // Render the DOM representation of the text of a line. Also builds
  // up a 'line map', which points at the DOM nodes that represent
  // specific stretches of text, and is used by the measuring code.
  // The returned object contains the DOM node, this map, and
  // information about line-wide styles that were set by the mode.
  LineBuilder buildLineContent(LineView lineView) {
    // The padding-right forces the element to have a 'border', which
    // is needed on Webkit to be able to get line-level bounding
    // rectangles for it (in measureChar).
    var content = eltspan(null, null, webkit ? "padding-right: .1px" : null);
    dynamic builder = new LineBuilder(eltpre([content]), content,  0, 0, this,
        (ie || webkit) && getOption("lineWrapping") == true);
    lineView.measure = new LineMeasurement();

    // Iterate over the logical lines that make up this visual line.
    for (var i = 0; i <= (lineView.rest != null ? lineView.rest.length : 0); i++) {
      var line = i > 0 ? lineView.rest[i - 1] : lineView.line;
      var order;
      builder.pos = 0;
      builder.addToken = builder.buildToken;
      // Optionally wire in some hacks into the token-rendering
      // algorithm, to deal with browser quirks.
      if (hasBadBidiRects(display.measure) && (order = doc.getOrder(line)) != false)
        builder.addToken = builder.buildTokenBadBidi(builder.addToken, order);
      builder.map = [];
      var allowFrontierUpdate = lineView != display.externalMeasured ? line.lineNo() : -1;
      builder.insertLineContent(line, getLineStyles(line, allowFrontierUpdate));
      if (line.styleClasses != null) {
        if (line.styleClasses.bgClass != null)
          builder.bgClass = joinClasses(line.styleClasses.bgClass, builder.bgClass);
        if (line.styleClasses.textClass != null)
          builder.textClass = joinClasses(line.styleClasses.textClass, builder.textClass);
      }

      // Ensure at least a single node is present, for measuring.
      if (builder.map.length == 0) {
        Element zwe = zeroWidthElement(display.measure);
        builder.content.append(zwe);
        builder.map..add(0)..add(0)..add(zwe);
      }

      // Store the map and a cache object for the current logical line
      if (i == 0) {
        lineView.measure.map = builder.map;
        lineView.measure.cache = {};
      } else {
        if (lineView.measure.maps == null) lineView.measure.maps = [];
        lineView.measure.maps.add(builder.map);
        if (lineView.measure.caches == null) lineView.measure.caches = [];
        lineView.measure.caches.add({});
      }
    }

    // See issue #2901
    if (webkit && (builder.content.lastChild is Element) &&
        new RegExp(r'\bcm-tab\b').hasMatch(builder.content.lastChild.className)) {
      builder.content.className = "cm-tab-wrap-hack";
    }
    signal(this, "renderLine", this, lineView.line, builder.pre);
    if (builder.pre.className != null && !builder.pre.className.isEmpty)
      builder.textClass = joinClasses(builder.pre.className, builder.textClass);

    return builder;
  }

  iterateBidiSections(order, from, to, f) {
    if (!order) return f(from, to, "ltr");
    var found = false;
    for (var i = 0; i < order.length; ++i) {
      var part = order[i];
      if (part.from < to && part.to > from || from == to && part.to == from) {
        f(max(part.from, from), min(part.to, to), part.level == 1 ? "rtl" : "ltr");
        found = true;
      }
    }
    if (!found) f(from, to, "ltr");
  }

  bidiLeft(part) { return part.level % 2 != 0 ? part.to : part.from; }
  bidiRight(part) { return part.level % 2 != 0 ? part.from : part.to; }

  lineLeft(line) { var order = doc.getOrder(line); return order != false ? bidiLeft(order[0]) : 0; }
  lineRight(line) {
    var order = doc.getOrder(line);
    if (order == false) return line.text.length;
    return bidiRight(lst(order));
  }

  Pos lineStart(int lineN) {
    var line = doc._getLine(lineN);
    var visual = line.visualLine();
    if (visual != line) lineN = doc.lineNo(visual);
    var order = doc.getOrder(visual);
    var ch = order == false ? 0 : order[0].level % 2 != 0 ? lineRight(visual) : lineLeft(visual);
    return new Pos(lineN, ch);
  }
  Pos lineEnd(int lineN) {
    var merged, line = doc._getLine(lineN);
    while ((merged = line.collapsedSpanAtEnd()) != null) {
      line = merged.find(1, true).line;
      lineN = null;
    }
    var order = doc.getOrder(line);
    var ch = order == false ? line.text.length : order[0].level % 2 != 0
        ? lineLeft(line) : lineRight(line);
    return new Pos(lineN == null ? doc.lineNo(line) : lineN, ch);
  }
  Pos lineStartSmart(Pos pos) {
    var start = lineStart(pos.line);
    var line = doc._getLine(start.line);
    var order = doc.getOrder(line);
    if (!order || order[0].level == 0) {
      var firstNonWS = max(0, line.text.indexOf(new RegExp(r'\S')));
      var inWS = pos.line == start.line && pos.char <= firstNonWS && pos.char > 0;
      return new Pos(start.line, inWS ? 0 : firstNonWS);
    }
    return start;
  }

  bool compareBidiLevel(order, a, b) {
    var linedir = order[0].level;
    if (a == linedir) return true;
    if (b == linedir) return false;
    return a < b;
  }

  getBidiPartAt(order, pos) {
    doc.bidiOther = null;
    var found;
    for (var i = 0; i < order.length; ++i) {
      var cur = order[i];
      if (cur.from < pos && cur.to > pos) return i;
      if ((cur.from == pos || cur.to == pos)) {
        if (found == null) {
          found = i;
        } else if (compareBidiLevel(order, cur.level, order[found].level)) {
          if (cur.from != cur.to) doc.bidiOther = found;
          return i;
        } else {
          if (cur.from != cur.to) doc.bidiOther = i;
          return found;
        }
      }
    }
    return found;
  }

  int moveInLine(Line line, int pos, int dir, bool byUnit) {
    if (!byUnit) return pos + dir;
    do pos += dir;
    while (pos > 0 && pos < line.text.length && isExtendingChar(line.text.substring(pos,pos+1)));
    return pos;
  }

  // This is needed in order to move 'visually' through bi-directional
  // text -- i.e., pressing left should make the cursor go left, even
  // when in RTL text. The tricky part is the 'jumps', where RTL and
  // LTR text touch each other. This often requires the cursor offset
  // to move more than one unit, in order to visually move one unit.
  moveVisually(Line line, int start, int dir, [bool byUnit = false]) {
    var bidi = doc.getOrder(line);
    if (bidi == false) return moveLogically(line, start, dir, byUnit);
    var pos = getBidiPartAt(bidi, start), part = bidi[pos];
    var target = moveInLine(line, start, part.level % 2 != 0 ? -dir : dir, byUnit);

    for (;;) {
      if (target > part.from && target < part.to) return target;
      if (target == part.from || target == part.to) {
        if (getBidiPartAt(bidi, target) == pos) return target;
        part = bidi[pos += dir];
        return (dir > 0) == (part.level % 2 != 0) ? part.to : part.from;
      } else {
        pos += dir;
        if (pos >= bidi.length) return null;
        part = bidi[pos];
//        if (!part) return null;
        if ((dir > 0) == (part.level % 2 != 0))
          target = moveInLine(line, part.to, -1, byUnit);
        else
          target = moveInLine(line, part.from, 1, byUnit);
      }
    }
  }

  moveLogically(Line line, int start, int dir, bool byUnit) {
    var target = start + dir;
    if (byUnit) {
      int n = line.text.length;
      while (target > 0 && target < n && isExtendingChar(line.text.substring(target, target+1))) {
        target += dir;
      }
    }
    return target < 0 || target > line.text.length ? null : target;
  }

  // Bidirectional ordering algorithm
  // See http://unicode.org/reports/tr9/tr9-13.html for the algorithm
  // that this (partially) implements.
  //
  // One-char codes used for character types:
  // L (L):   Left-to-Right
  // R (R):   Right-to-Left
  // r (AL):  Right-to-Left Arabic
  // 1 (EN):  European Number
  // + (ES):  European Number Separator
  // % (ET):  European Number Terminator
  // n (AN):  Arabic Number
  // , (CS):  Common Number Separator
  // m (NSM): Non-Spacing Mark
  // b (BN):  Boundary Neutral
  // s (B):   Paragraph Separator
  // t (S):   Segment Separator
  // w (WS):  Whitespace
  // N (ON):  Other Neutrals
  //
  // Returns null if characters are ordered as they appear
  // (left-to-right), or an array of sections ({from, to, level}
  // BidiSpan objects) in the order in which they occur visually.
  Function bidiOrdering = (() {
    // Character types for codepoints 0 to 0xff
    var lowTypes = "bbbbbbbbbtstwsbbbbbbbbbbbbbbssstwNN%%%NNNNNN,N,N1111111111NNNNNNNLLLLLLLLLLLLLLLLLLLLLLLLLLNNNNNNLLLLLLLLLLLLLLLLLLLLLLLLLLNNNNbbbbbbsbbbbbbbbbbbbbbbbbbbbbbbbbb,N%%%%NNNNLNNNNN%%11NLNNN1LNNNNNLLLLLLLLLLLLLLLLLLLLLLLNLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLN";
    // Character types for codepoints 0x600 to 0x6ff
    var arabicTypes = "rrrrrrrrrrrr,rNNmmmmmmrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrmmmmmmmmmmmmmmrrrrrrrnnnnnnnnnn%nnrrrmrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrmmmmmmmmmmmmmmmmmmmNmmmm";
    charType(code) {
      if (code <= 0xf7) return lowTypes.substring(code, code+1);
      else if (0x590 <= code && code <= 0x5f4) return "R";
      else if (0x600 <= code && code <= 0x6ed) return arabicTypes.substring(code - 0x600, code - 0x600 + 1);
      else if (0x6ee <= code && code <= 0x8ac) return "r";
      else if (0x2000 <= code && code <= 0x200b) return "w";
      else if (code == 0x200c) return "b";
      else return "L";
    }

    var bidiRE = new RegExp(r'[\u0590-\u05f4\u0600-\u06ff\u0700-\u08ac]');
    var isNeutral = new RegExp(r'[stwN]');
    var isStrong = new RegExp(r'[LRr]');
    var countsAsLeft = new RegExp(r'[Lb1n]');
    var countsAsNum = new RegExp(r'[1n]');
    // Browsers seem to always treat the boundaries of block elements as being L.
    var outerType = "L";

    return (String str) {
      if (!bidiRE.hasMatch(str)) return false;
      var len = str.length, types = [];
      for (var i = 0; i < len; ++i)
        types.add(charType(str.codeUnitAt(i)));

      // W1. Examine each non-spacing mark (NSM) in the level run, and
      // change the type of the NSM to the type of the previous
      // character. If the NSM is at the start of the level run, it will
      // get the type of sor.
      for (var i = 0, prev = outerType; i < len; ++i) {
        var type = types[i];
        if (type == "m") types[i] = prev;
        else prev = type;
      }

      // W2. Search backwards from each instance of a European number
      // until the first strong type (R, L, AL, or sor) is found. If an
      // AL is found, change the type of the European number to Arabic
      // number.
      // W3. Change all ALs to R.
      for (var i = 0, cur = outerType; i < len; ++i) {
        var type = types[i];
        if (type == "1" && cur == "r") types[i] = "n";
        else if (isStrong.hasMatch(type)) { cur = type; if (type == "r") types[i] = "R"; }
      }

      // W4. A single European separator between two European numbers
      // changes to a European number. A single common separator between
      // two numbers of the same type changes to that type.
      for (var i = 1, prev = types[0]; i < len - 1; ++i) {
        var type = types[i];
        if (type == "+" && prev == "1" && types[i+1] == "1") types[i] = "1";
        else if (type == "," && prev == types[i+1] &&
                 (prev == "1" || prev == "n")) types[i] = prev;
        prev = type;
      }

      // W5. A sequence of European terminators adjacent to European
      // numbers changes to all European numbers.
      // W6. Otherwise, separators and terminators change to Other
      // Neutral.
      for (var i = 0; i < len; ++i) {
        var type = types[i];
        if (type == ",") types[i] = "N";
        else if (type == "%") {
          var end;
          for (end = i + 1; end < len && types[end] == "%"; ++end) {}
          var replace = (i && types[i-1] == "!") || (end < len && types[end] == "1") ? "1" : "N";
          for (var j = i; j < end; ++j) types[j] = replace;
          i = end - 1;
        }
      }

      // W7. Search backwards from each instance of a European number
      // until the first strong type (R, L, or sor) is found. If an L is
      // found, then change the type of the European number to L.
      for (var i = 0, cur = outerType; i < len; ++i) {
        var type = types[i];
        if (cur == "L" && type == "1") types[i] = "L";
        else if (isStrong.hasMatch(type)) cur = type;
      }

      // N1. A sequence of neutrals takes the direction of the
      // surrounding strong text if the text on both sides has the same
      // direction. European and Arabic numbers act as if they were R in
      // terms of their influence on neutrals. Start-of-level-run (sor)
      // and end-of-level-run (eor) are used at level run boundaries.
      // N2. Any remaining neutrals take the embedding direction.
      for (var i = 0; i < len; ++i) {
        if (isNeutral.hasMatch(types[i])) {
          var end;
          for (end = i + 1; end < len && isNeutral.hasMatch(types[end]); ++end) {}
          var before = (i > 0 ? types[i-1] : outerType) == "L";
          var after = (end < len ? types[end] : outerType) == "L";
          var replace = before || after ? "L" : "R";
          for (var j = i; j < end; ++j) types[j] = replace;
          i = end - 1;
        }
      }

      // Here we depart from the documented algorithm, in order to avoid
      // building up an actual levels array. Since there are only three
      // levels (0, 1, 2) in an implementation that doesn't take
      // explicit embedding into account, we can build up the order on
      // the fly, without following the level-based algorithm.
      var order = [];
      Match m;
      for (var i = 0; i < len;) {
        if (countsAsLeft.hasMatch(types[i])) {
          var start = i;
          for (i += 1; i < len && countsAsLeft.hasMatch(types[i]); ++i) {}
          order.add(new BidiSpan(0, start, i));
        } else {
          var pos = i, at = order.length;
          for (i += 1; i < len && types[i] != "L"; ++i) {}
          for (var j = pos; j < i;) {
            if (countsAsNum.hasMatch(types[j])) {
              if (pos < j) order.insert(at, new BidiSpan(1, pos, j));
              var nstart = j;
              for (j += 1; j < i && countsAsNum.hasMatch(types[j]); ++j) {}
              order.insert(at, new BidiSpan(2, nstart, j));
              pos = j;
            } else ++j;
          }
          if (pos < i) order.insert(at, new BidiSpan(1, pos, i));
        }
      }
      if (order[0].level == 1 && (m = new RegExp(r'^\s+').firstMatch(str)) != null) {
        order[0].from = m.group(0).length;
        order.insert(0, new BidiSpan(0, 0, m.group(0).length));
      }
      if (lst(order).level == 1 && (m = new RegExp(r'\s+$').firstMatch(str)) != null) {
        lst(order).to -= m.group(0).length;
        order.add(new BidiSpan(0, len - m.group(0).length, len));
      }
      if (order[0].level == 2)
        order.insert(0, new BidiSpan(1, order[0].to, order[0].to));
      if (order[0].level != lst(order).level)
        order.add(new BidiSpan(order[0].level, len, len));

      return order;
    };
  })();

  // Run the given function in an operation
  dynamic runInOp(cm, f) {
    if (cm.curOp != null) {
      return f();
    }
    startOperation(cm);
    try {
      return f();
    } finally {
      endOperation(cm);
    }
  }

  // Wraps a function in an operation. Returns the wrapped function.
  // Example from Code Mirror:
  // operation(cm, setSelection)(cm.doc, simpleSelection(pos), sel_dontScroll);
  // Where 'arguments' is [cm.doc, simpleSelection(pos), sel_dontScroll]
  // This will create and evaluate a closure equivalent to:
  // () {
  //   startOperation(cm);
  //   result=cm.setSelection(cm.doc, simpleSelection(pos), sel_dontScroll)
  //   endOperation(cm)
  //   return result;
  // }
  dynamic operation(cm, f) {
    return () {
      if (cm.curOp != null) {
        return f();
      }
      startOperation(cm);
      try {
        return f();
      } finally {
        endOperation(cm);
      }
    };
  }

  // This is similar to runInOp() and operation(). Also, Doc.docMethodOp().
  // They all do about the same thing, but
  // 1. methodOp() is used to define the public CodeMirror API
  // 2. docMethodOp() is used to define the public Doc API
  // 3. operation() is for general internal use
  // 4. runInOp() is like operation() but directly evaluates its function arg
  dynamic methodOp(f) {
    return () {
      if (curOp != null) {
        return f();
      }
      startOperation(this);
      try {
        return f();
      } finally {
        endOperation(this);
      }
    };
  }

  OperationGroup operationGroup = null;
  // Start a new operation.
  void startOperation(CodeEditor cm) {
    cm.curOp = new Operation(
        cm: cm,
        viewChanged: false,      // Flag that indicates that lines might need to be redrawn
        startHeight: cm.doc.height, // Used to detect need to update scrollbar
        forceUpdate: false,      // Used to force a redraw
        updateInput: null,       // Whether to reset the input textarea
        typing: false,           // Whether this reset should be careful to leave existing text (for compositing)
        changeObjs: null,        // Accumulated changes, for firing change events
        cursorActivityHandlers: null, // Set of handlers to fire cursorActivity on
        cursorActivityCalled: 0, // Tracks which cursorActivity handlers have been called already
        selectionChanged: false, // Whether the selection needs to be redrawn
        updateMaxLine: false,    // Set when the widest line needs to be determined anew
        scrollLeft: -1,
        scrollTop: -1,           // Intermediate scroll position, not pushed to DOM yet
        scrollToPos: null       // Used to scroll to a specific position
    );
    if (operationGroup != null) {
      operationGroup.ops.add(cm.curOp);
    } else {
      cm.curOp.ownsGroup = operationGroup = new OperationGroup(
        ops: [cm.curOp],
        delayedCallbacks: []
      );
    }
  }

  // Finish an operation, updating the display and signalling delayed events
  void endOperation(CodeEditor cm) {
    Operation op = cm.curOp;
    OperationGroup group = op.ownsGroup;
    if (group == null) return;

    try {
      group.fireCallbacksForOps();
    } finally {
      operationGroup = null;
      for (var i = 0; i < group.ops.length; i++)
        group.ops[i].cm.curOp = null;
      group.endOperations();
    }
  }

  /**
   * Copy the content of the editor into the textarea.
   *
   * Only available if the CodeMirror instance was created using the
   * `CodeMirror.fromTextArea` constructor.
   */
  save(e) {
    throw new StateError("Only defined for CodeMirror.fromTextArea()");
  }

  /**
   * Returns the textarea that the instance was based on.
   *
   * Only available if the CodeMirror instance was created using the
   * `CodeMirror.fromTextArea` constructor.
   */
  TextAreaElement getTextArea() {
    throw new StateError("Only defined for CodeMirror.fromTextArea()");
  }

  /**
   * Remove the editor, and restore the original textarea (with the editor's
   * current content).
   *
   * Only available if the CodeMirror instance was created using the
   * `CodeMirror.fromTextArea` constructor.
   */
  toTextArea() {
    throw new StateError("Only defined for CodeMirror.fromTextArea()");
  }
}

class CodeEditorArea extends CodeEditor {
  TextAreaElement textArea;
  var realSubmit;

  CodeEditorArea(var place, [var opts]) : super(place, opts);

  factory CodeEditorArea.fromTextArea(TextAreaElement textarea, dynamic options) {
    if (options == null) options = new Options();
    else if (options is Map) options = new Options.from(options);
    else options = options.copy();
    options['value'] = textarea.value;
    if (options.tabindex == null && textarea.tabIndex != null) {
      options['tabindex'] = textarea.tabIndex;
    }
    // Set autofocus to true if this textarea is focused, or if it has
    // autofocus and no other element is focused.
    if (options.autofocus == null) {
      var hasFocus = activeElt();
      options['autofocus'] = hasFocus == textarea ||
        textarea.getAttribute("autofocus") != null && hasFocus == document.body;
    }

    var cm = new CodeEditorArea((node) {
      textarea.parentNode.insertBefore(node, textarea.nextNode);
    }, options);
    cm.initFromTextArea(textarea, options);
    return cm;
  }
  void initFromTextArea(TextAreaElement textarea, Options options) {
    textArea = textarea;
    if (textarea.form != null) {
      on(textarea.form, "submit", save);
      textArea.form.onSubmit.listen((Event e) { save(e); } );
      // Deplorable hack to make the submit method do the right thing.
      if (options['leaveSubmitMethodAlone'] != true) {
        FormElement form = textarea.form;
        realSubmit = form.submit;
        try {
//          var wrappedSubmit;
          // TODO Consider cusom JS code to hack the submit function.
//          form.submit = () {
//            save();
//            form.submit = realSubmit;
//            form.submit();
//            form.submit = wrappedSubmit;
//          };
//          wrappedSubmit = form.submit;
        } catch(e) {}
      }
    }
    textarea.style.display = "none";
  }

  /**
   * Copy the content of the editor into the textarea.
   *
   * Only available if the CodeMirror instance was created using the
   * `CodeMirror.fromTextArea` constructor.
   */
  save(e) { textArea.value = doc.getValue(null); }

  /**
   * Returns the textarea that the instance was based on.
   *
   * Only available if the CodeMirror instance was created using the
   * `CodeMirror.fromTextArea` constructor.
   */
  TextAreaElement getTextArea() { return textArea; }

  /**
   * Remove the editor, and restore the original textarea (with the editor's
   * current content).
   *
   * Only available if the CodeMirror instance was created using the
   * `CodeMirror.fromTextArea` constructor.
   */
  toTextArea() {
  // Prevent this from being ran twice
    if (textArea == null) throw new StateError("Already converted");
    save(null);
    getWrapperElement().remove();
    textArea.style.display = "";
    if (textArea.form != null) {
      off(textArea.form, "submit", save);
      // TODO Consider cusom JS code to hack the submit function.
//      textArea.form.submit = realSubmit;
    }
    textArea = null;
  }
}

class OperationGroup {
  List<Operation> ops;
  List delayedCallbacks;
  OperationGroup({this.ops, this.delayedCallbacks});

  fireCallbacksForOps() {
    // Calls delayed callbacks and cursorActivity handlers until no
    // new ones appear
    var callbacks = delayedCallbacks, i = 0;
    do {
      for (; i < callbacks.length; i++)
        callbacks[i]();
      for (var j = 0; j < ops.length; j++) {
        var op = ops[j];
        if (op.cursorActivityHandlers != null)
          while (op.cursorActivityCalled < op.cursorActivityHandlers.length)
            op.cursorActivityHandlers[op.cursorActivityCalled++](op.cm);
      }
    } while (i < callbacks.length);
  }

  // The DOM updates done when an operation finishes are batched so
  // that the minimum number of relayouts are required.
  endOperations() {
    for (var i = 0; i < ops.length; i++) // Read DOM
      ops[i].endOperation_R1();
    for (var i = 0; i < ops.length; i++) // Write DOM (maybe)
      ops[i].endOperation_W1();
    for (var i = 0; i < ops.length; i++) // Read DOM
      ops[i].endOperation_R2();
    for (var i = 0; i < ops.length; i++) // Write DOM (maybe)
      ops[i].endOperation_W2();
    for (var i = 0; i < ops.length; i++) // Read DOM
      ops[i].endOperation_finish();
  }

}

// Operations are used to wrap a series of changes to the editor
// state in such a way that each change won't have to update the
// cursor and display (which would be awkward, slow, and
// error-prone). Instead, display updates are batched and then all
// combined and executed at once.
class Operation {

  static int nextOpId = 0;

  CodeEditor cm;
  bool viewChanged;      // Flag that indicates that lines might need to be redrawn
  num startHeight;       // Used to detect need to update scrollbar
  bool forceUpdate;      // Used to force a redraw
  var updateInput;       // Whether to reset the input textarea
  bool typing;           // Whether this reset should be careful to leave existing text (for compositing)
  List<Change> changeObjs; // Accumulated changes, for firing change events
  List cursorActivityHandlers; // Set of handlers to fire cursorActivity on
  int cursorActivityCalled; // Tracks which cursorActivity handlers have been called already
  bool selectionChanged; // Whether the selection needs to be redrawn
  bool updateMaxLine;    // Set when the widest line needs to be determined anew
  int scrollLeft;
  int scrollTop;         // Intermediate scroll position, not pushed to DOM yet
  ScrollDelta scrollToPos;       // Used to scroll to a specific position
  Element focus = null;
  int id = ++nextOpId;   // Unique ID
  OperationGroup ownsGroup;
  bool mustUpdate = false;
  DisplayUpdate update;
  bool updatedDisplay = false;
  ScrollMeasure barMeasure;
  num adjustWidthTo;
  num maxScrollLeft;
  DrawnSelection preparedSelection;
  bool forceScroll = false;
  List maybeHiddenMarkers;
  List maybeUnhiddenMarkers;

  Operation({ // The parameters are all required. Names are preserved for documentation.
            this.cm,
            this.viewChanged,
            this.startHeight,
            this.forceUpdate,
            this.updateInput,
            this.typing,
            this.changeObjs,
            this.cursorActivityHandlers,
            this.cursorActivityCalled,
            this.selectionChanged,
            this.updateMaxLine,
            this.scrollLeft,
            this.scrollTop,
            this.scrollToPos
  });

  endOperation_R1() {
    var display = cm.display;
    display.maybeClipScrollbars();
    if (updateMaxLine) cm.findMaxLine();

    mustUpdate = viewChanged || forceUpdate || scrollTop >= 0 ||
      scrollToPos != null && (scrollToPos.from.line < display.viewFrom ||
                              scrollToPos.to.line >= display.viewTo) ||
      display.maxLineChanged && cm.options.lineWrapping;
    if (mustUpdate) {
      update = new DisplayUpdate(cm, mustUpdate
            ? new Viewport(scrollTop, null, scrollToPos)
            : null,
          forceUpdate);
    }
  }

  endOperation_W1() {
    updatedDisplay = mustUpdate && cm.display.updateDisplayIfNeeded(cm, update);
  }

  endOperation_R2() {
    var display = cm.display;
    if (updatedDisplay) cm.display.updateHeightsInViewport(cm);

    barMeasure = cm.display.measureForScrollbars(cm);

    // If the max line changed since it was last measured, measure it,
    // and ensure the document's width matches it.
    // updateDisplay_W2 will use these properties to do the actual resizing
    if (display.maxLineChanged && !cm.options.lineWrapping) {
      if (display.maxLine != null) {
        adjustWidthTo = cm.doc.measureChar(display.maxLine, display.maxLine.text.length).left + 3;
      }
      cm.display.sizerWidth = adjustWidthTo;
      barMeasure.scrollWidth =
        max(display.scroller.clientWidth,
            display.sizer.offsetLeft + adjustWidthTo + display.scrollGap() + cm.display.barWidth);
      maxScrollLeft = max(0, display.sizer.offsetLeft + adjustWidthTo - display.displayWidth());
    }

    if (updatedDisplay || selectionChanged)
      preparedSelection = display.input.prepareSelection();
  }

  endOperation_W2() {

    if (adjustWidthTo != null) {
      cm.display.sizer.style.minWidth = "${adjustWidthTo}px";
      if (maxScrollLeft < cm.doc.scrollLeft) {
        cm.setScrollLeft(min(cm.display.scroller.scrollLeft, maxScrollLeft),
            true);
      }
      cm.display.maxLineChanged = false;
    }

    if (preparedSelection != null) {
      cm.display.input.showSelection(preparedSelection);
    }
    if (updatedDisplay) {
      cm.display.setDocumentHeight(barMeasure);
    }
    if (updatedDisplay || startHeight != cm.doc.height) {
      cm.display.updateScrollbars(cm, barMeasure);
    }

    if (selectionChanged) cm.display.restartBlink(cm);

    if (cm.state.focused && updateInput != null) {
      cm.display.input.reset(typing);
    }
    if (focus != null && focus == activeElt()) cm.display.input.ensureFocus();
  }

  endOperation_finish() {
    var display = cm.display, doc = cm.doc;

    if (updatedDisplay) display.postUpdateDisplay(cm, update);

    // Abort mouse wheel delta measurement, when scrolling explicitly
    if (display.wheelStartX != null && (scrollTop >= 0 || scrollLeft >= 0 || scrollToPos != null))
      display.wheelStartX = display.wheelStartY = null;

    // Propagate the scroll position to the actual DOM scroller
    if (scrollTop >= 0 && (display.scroller.scrollTop != scrollTop || forceScroll)) {
      doc.scrollTop = max(0, min(display.scroller.scrollHeight - display.scroller.clientHeight, scrollTop));
      display.scrollbars.setScrollTop(doc.scrollTop);
      display.scroller.scrollTop = doc.scrollTop;
    }
    if (scrollLeft >= 0 && (display.scroller.scrollLeft != scrollLeft || forceScroll)) {
      doc.scrollLeft = max(0, min(display.scroller.scrollWidth - display.displayWidth(), scrollLeft));
      display.scrollbars.setScrollLeft(doc.scrollLeft);
      display.scroller.scrollLeft = doc.scrollLeft;
      cm.alignHorizontally();
    }
    // If we need to scroll a specific position into view, do so.
    if (scrollToPos != null) {
      var coords = cm.scrollPosIntoView(doc.clipPos(scrollToPos.from),
                                        doc.clipPos(scrollToPos.to),
                                        scrollToPos.margin);
      if (scrollToPos.isCursor && cm.state.focused) cm.maybeScrollWindow(coords);
    }

    // Fire events for markers that are hidden/unidden by editing or undoing
    var hidden = maybeHiddenMarkers, unhidden = maybeUnhiddenMarkers;
    if (hidden != null) {
      for (var i = 0; i < hidden.length; ++i) {
        if (!(hidden[i].lines.length > 0)) cm.signal(hidden[i], "hide");
      }
    }
    if (unhidden != null) {
      for (var i = 0; i < unhidden.length; ++i) {
        if (unhidden[i].lines.length > 0) cm.signal(unhidden[i], "unhide");
      }
    }

    if (display.wrapper.offsetHeight != 0) {
      doc.scrollTop = cm.display.scroller.scrollTop;
    }

    // Fire change events, and delayed event handlers
    if (changeObjs != null) {
      cm.signal(cm, "changes", cm, changeObjs);
    }
    if (update != null) {
      update.finish();
    }
  }

}

class KeyMap {
  static KeyMap basic;
  static KeyMap pcDefault;
  static KeyMap emacsy;
  static KeyMap macDefault;

  static initDefaultKeys(CodeEditor cm) {
    initKeyNames();
    // STANDARD KEYMAPS
    basic = new KeyMap({
      "Left": "goCharLeft", "Right": "goCharRight", "Up": "goLineUp", "Down": "goLineDown",
      "End": "goLineEnd", "Home": "goLineStartSmart", "PageUp": "goPageUp", "PageDown": "goPageDown",
      "Delete": "delCharAfter", "Backspace": "delCharBefore", "Shift-Backspace": "delCharBefore",
      "Tab": "defaultTab", "Shift-Tab": "indentAuto",
      "Enter": "newlineAndIndent", "Insert": "toggleOverwrite",
      "Esc": "singleSelection"
    });
    // Note that the save and find-related commands aren't defined by
    // default. User code or addons can define them. Unknown commands
    // are simply ignored.
    pcDefault = new KeyMap({
      "Ctrl-A": "selectAll", "Ctrl-D": "deleteLine", "Ctrl-Z": "undo", "Shift-Ctrl-Z": "redo", "Ctrl-Y": "redo",
      "Ctrl-Home": "goDocStart", "Ctrl-End": "goDocEnd", "Ctrl-Up": "goLineUp", "Ctrl-Down": "goLineDown",
      "Ctrl-Left": "goGroupLeft", "Ctrl-Right": "goGroupRight", "Alt-Left": "goLineStart", "Alt-Right": "goLineEnd",
      "Ctrl-Backspace": "delGroupBefore", "Ctrl-Delete": "delGroupAfter", "Ctrl-S": "save", "Ctrl-F": "find",
      "Ctrl-G": "findNext", "Shift-Ctrl-G": "findPrev", "Shift-Ctrl-F": "replace", "Shift-Ctrl-R": "replaceAll",
      "Ctrl-[": "indentLess", "Ctrl-]": "indentMore",
      "Ctrl-U": "undoSelection", "Shift-Ctrl-U": "redoSelection", "Alt-U": "redoSelection"},
      fallthrough: ["basic"]
    );
    // Very basic readline/emacs-style bindings, which are standard on Mac.
    emacsy = new KeyMap({
      "Ctrl-F": "goCharRight", "Ctrl-B": "goCharLeft", "Ctrl-P": "goLineUp", "Ctrl-N": "goLineDown",
      "Alt-F": "goWordRight", "Alt-B": "goWordLeft", "Ctrl-A": "goLineStart", "Ctrl-E": "goLineEnd",
      "Ctrl-V": "goPageDown", "Shift-Ctrl-V": "goPageUp", "Ctrl-D": "delCharAfter", "Ctrl-H": "delCharBefore",
      "Alt-D": "delWordAfter", "Alt-Backspace": "delWordBefore", "Ctrl-K": "killLine", "Ctrl-T": "transposeChars"
    });
    macDefault = new KeyMap({
      "Cmd-A": "selectAll", "Cmd-D": "deleteLine", "Cmd-Z": "undo", "Shift-Cmd-Z": "redo", "Cmd-Y": "redo",
      "Cmd-Home": "goDocStart", "Cmd-Up": "goDocStart", "Cmd-End": "goDocEnd", "Cmd-Down": "goDocEnd", "Alt-Left": "goGroupLeft",
      "Alt-Right": "goGroupRight", "Cmd-Left": "goLineLeft", "Cmd-Right": "goLineRight", "Alt-Backspace": "delGroupBefore",
      "Ctrl-Alt-Backspace": "delGroupAfter", "Alt-Delete": "delGroupAfter", "Cmd-S": "save", "Cmd-F": "find",
      "Cmd-G": "findNext", "Shift-Cmd-G": "findPrev", "Cmd-Alt-F": "replace", "Shift-Cmd-Alt-F": "replaceAll",
      "Cmd-[": "indentLess", "Cmd-]": "indentMore", "Cmd-Backspace": "delWrappedLineLeft", "Cmd-Delete": "delWrappedLineRight",
      "Cmd-U": "undoSelection", "Shift-Cmd-U": "redoSelection", "Ctrl-Up": "goDocStart", "Ctrl-Down": "goDocEnd"},
      fallthrough: ["basic", "emacsy"]
    );
    cm.keyMap["default"] = mac ? macDefault : pcDefault;
    cm.keyMap["basic"] = basic;
    cm.keyMap["emacsy"] = emacsy;
  }

  Map<String,String> _keys;
  List<String> fallthrough = []; // Always a list, never a String.

  KeyMap(this._keys, {this.fallthrough});

  String operator [](String key) => _keys[key];
  void operator []=(String key, String value) { _keys[key] = value; }

  static Map<int,String> keyNames = {
      3: "Enter", 8: "Backspace", 9: "Tab", 13: "Enter", 16: "Shift", 17: "Ctrl", 18: "Alt",
      19: "Pause", 20: "CapsLock", 27: "Esc", 32: "Space", 33: "PageUp", 34: "PageDown", 35: "End",
      36: "Home", 37: "Left", 38: "Up", 39: "Right", 40: "Down", 44: "PrintScrn", 45: "Insert",
      46: "Delete", 59: ";", 61: "=", 91: "Mod", 92: "Mod", 93: "Mod", 107: "=", 109: "-", 127: "Delete",
      173: "-", 186: ";", 187: "=", 188: ",", 189: "-", 190: ".", 191: "/", 192: "`", 219: "[", 220: "\\",
      221: "]", 222: "'", 63232: "Up", 63233: "Down", 63234: "Left", 63235: "Right", 63272: "Delete",
      63273: "Home", 63275: "End", 63276: "PageUp", 63277: "PageDown", 63302: "Insert"
  };

  static initKeyNames() {
    // Number keys
    for (var i = 0; i < 10; i++) keyNames[i + 48] = keyNames[i + 96] = "$i";
    // Alphabetic keys
    for (var i = 65; i <= 90; i++) keyNames[i] = new String.fromCharCode(i);
    // Function keys
    for (var i = 1; i <= 12; i++) keyNames[i + 111] = keyNames[i + 63235] = "F$i";
  }
}

class SelectionOptions {
  bool scroll;
  String origin;
  int bias;
  bool clearRedo;
  SelectionOptions({this.scroll, this.origin, this.bias, this.clearRedo});
}

// Reused option objects for setSelection & friends
final sel_dontScroll = new SelectionOptions(scroll: false);
final sel_mouse = new SelectionOptions(origin: "*mouse");
final sel_move = new SelectionOptions(origin: "+move");

class EditState {
  List keyMaps = [];  // stores maps added by addKeyMap
  List overlays = []; // highlighting overlays, as added by addOverlay
  int modeGen = 0;   // bumped when mode/overlay changes, used to invalidate highlighting info
  bool overwrite = false;
  bool delayingBlurEvent = false;
  bool focused = false;
  bool suppressEdits = false; // used to disable editing during key handlers when in readOnly mode
  bool pasteIncoming = false; // help recognize paste/cut edits in readInput
  bool cutIncoming = false; // help recognize paste/cut edits in input.poll
  Object draggingText = null;
  Delayed highlight = new Delayed(); // stores highlight worker timeout
  String keySeq = null;  // Unfinished key sequence
  RegExp specialChars = null;
  // The rest are defined for use by add-ons
  DateTime lastMiddleDown;
  bool fakedLastChar = false;
  var matchBrackets;
  var completionActive;
  var search;
  var matchHighlighter;
  Function currentNotificationClose;
  var foldGutter;
  var closeBrackets;

  EditState copy() {
    return new EditState()..copyValues(this);
  }

  void copyValues(EditState old) {
    keyMaps = old.keyMaps;
    overlays = old.overlays;
    modeGen = old.modeGen;
    overwrite = old.overwrite;
    delayingBlurEvent = old.delayingBlurEvent;
    focused = old.focused;
    suppressEdits = old.suppressEdits;
    pasteIncoming = old.pasteIncoming;
    cutIncoming = old.cutIncoming;
    draggingText = old.draggingText;
    highlight = old.highlight;
    keySeq = old.keySeq;
    specialChars = old.specialChars;
    lastMiddleDown = old.lastMiddleDown;
    fakedLastChar = old.fakedLastChar;
    matchBrackets = old.matchBrackets;
    completionActive = old.completionActive;
    search = old.search;
    matchHighlighter = old.matchHighlighter;
    currentNotificationClose = old.currentNotificationClose;
    foldGutter = old.foldGutter;
  }

}

// {pre: eltpre([content]), content: content, col: 0, pos: 0, cm: this};
class LineBuilder {
  PreElement pre;
  var content;
  int col;
  int pos;
  CodeEditor cm;
  var addToken;
  List map; // Each "element" is a triple: int, int, Node
  String bgClass = "", textClass = "";
  bool shouldSplitSpaces;

  LineBuilder(this.pre, this.content, this.col, this.pos, this.cm, this.shouldSplitSpaces);

  // Build up the DOM representation for a single token, and add it to
  // the line map. Takes care to render special characters separately.
  buildToken(String text, [String style, String startStyle, String endStyle, String title, String css=""]) {
    if (text == null) return null;
    var content;
    var displayText = shouldSplitSpaces
        ? text.replaceAllMapped(new RegExp(r' {3,}'), splitSpaces)
        : text;
    var special = cm.state.specialChars, mustWrap = false;
    if (!special.hasMatch(text)) {
      col += text.length;
      content = new Text(displayText);
      map..add(pos)..add(pos + text.length)..add(content);
//      if (ie && ie_version < 9) mustWrap = true;
      pos += text.length;
    } else {
      content = document.createDocumentFragment();
      var pos = 0;
      while (true) {
//        special.lastIndex = pos;
        Match m = special.matchAsPrefix(text, pos);
        var skipped = m != null ? m.start - pos : text.length - pos;
        if (skipped != 0) {
          var txt = new Text(displayText.substring(pos, pos + skipped));
//          if (ie && ie_version < 9) content.appendChild(elt("span", [txt]));
//          else
          content.append(txt);
          this.map..add(this.pos)..add(this.pos + skipped)..add(txt);
          this.col += skipped;
          this.pos += skipped;
        }
        if (m == null) break;
        var txt;
        pos += skipped + 1;
        if (m.group(0) == "\t") {
          var tabSize = cm.options.tabSize, tabWidth = tabSize - col % tabSize;
          txt = content.append(eltspan(spaceStr(tabWidth), "cm-tab"));
          txt.setAttribute("role", "presentation");
          txt.setAttribute("cm-text", "\t");
          this.col += tabWidth;
        } else {
          txt = cm.options.specialCharPlaceholder(m.group(0));
          txt.setAttribute("cm-text", m[0]);
//          if (ie && ie_version < 9) content.appendChild(elt("span", [txt]));
//          else
          content.append(txt);
          this.col += 1;
        }
        this.map..add(this.pos)..add(this.pos + 1)..add(txt);
        this.pos++;
      }
    }
    if (style != null || startStyle != null || endStyle != null || mustWrap || css != null) {
      var fullStyle = style == null ? "" : style;
      if (startStyle!= null) fullStyle += startStyle;
      if (endStyle != null) fullStyle += endStyle;
      var token = eltspan([content], fullStyle, css);
      if (title != null) token.title = title;
      return this.content.append(token);
    }
    this.content.append(content);
    return null;
  }

  splitSpaces(Match match) {
    String old = match[0];
    var out = " ";
    for (var i = 0; i < old.length - 2; ++i) {
      out += i % 2 != 0 ? " " : "\u00a0";
    }
    out += " ";
    return out;
  }

  // Work around nonsense dimensions being reported for stretches of
  // right-to-left text.
  buildTokenBadBidi(inner, order) {
    return (text, [style, startStyle, endStyle, title, css=""]) {
      style = style != null ? style + " cm-force-border" : "cm-force-border";
      var start = pos, end = start + text.length;
      for (;;) {
        var part;
        // Find the part that overlaps with the start of this text
        for (var i = 0; i < order.length; i++) {
          part = order[i];
          if (part.to > start && part.from <= start) break;
        }
        if (part.to >= end) return inner(text, style, startStyle, endStyle, title, css);
        inner(text.substring(0, part.to - start), style, startStyle, null, title, css);
        startStyle = null;
        text = text.substring(part.to - start);
        start = part.to;
      }
    };
  }

  buildCollapsedSpan(size, marker, [bool ignoreWidget = false]) {
    if (!ignoreWidget) {
      var widget =  marker.widgetNode;
      if (widget != null) {
        map..add(pos)..add(pos + size)..add(widget);
      }
      if (cm.display.input.needsContentAttribute) {
        if (widget == null) {
          widget = content.append(document.createElement("span"));
        }
        widget.setAttribute("cm-marker", "${marker.id}");
      }
      if (widget != null) {
        cm.display.input.setUneditable(widget);
        content.append(widget);
      }
    }
    pos += size;
  }

  // Outputs a number of spans to make up a line, taking highlighting
  // and marked text into account.
  insertLineContent(Line line, List styles) {
    var spans = line.markedSpans, allText = line.text, at = 0;
    if (spans == null) {
      for (var i = 1; i < styles.length; i+=2)
        addToken(allText.substring(at, at = styles[i]), cm.interpretTokenStyle(styles[i+1], cm.options));
      return;
    }

    var len = allText.length, pos = 0, i = 1;
    String text = "", style;
    var nextChange = 0;
    String spanStyle, spanEndStyle, spanStartStyle, title, css;
    MarkedSpan collapsed;
    for (;;) {
      if (nextChange == pos) { // Update current marker set
        spanStyle = spanEndStyle = spanStartStyle = title = css = "";
        collapsed = null; nextChange = double.INFINITY;
        var foundBookmarks = [];
        for (var j = 0; j < spans.length; ++j) {
          var sp = spans[j];
          var m = sp.marker;
          if (m.type == "bookmark" && sp.from == pos && m.widgetNode != null) {
            foundBookmarks.add(m);
          } else if ((sp.from == null || sp.from <= pos) && (sp.to == null || sp.to > pos ||
              m.collapsed && sp.to == pos && sp.from == pos)) {
            if (sp.to != null && sp.to != pos && nextChange > sp.to) {
              nextChange = sp.to;
              spanEndStyle = "";
            }
            if (m.className != null && !m.className.isEmpty) spanStyle += " " + m.className;
            if (m.css != null) css = m.css;
            if (m.startStyle != null && sp.from == pos) spanStartStyle += " " + m.startStyle;
            if (m.endStyle != null && sp.to == nextChange) spanEndStyle += " " + m.endStyle;
            if (m.title != null && title == null) title = m.title;
            if (m.collapsed && (collapsed == null || Line.compareCollapsedMarkers(collapsed.marker, m) < 0))
              collapsed = sp;
          } else if ((sp.from != null && sp.from > pos) && nextChange > sp.from) {
            nextChange = sp.from;
          }
        }
        if (collapsed != null && (collapsed.from == null ? 0 : collapsed.from) == pos) {
          buildCollapsedSpan((collapsed.to == null ? len + 1 : collapsed.to) - pos,
                             collapsed.marker, collapsed.from == null);
          if (collapsed.to == null) return;
          if (collapsed.to == pos) collapsed = null;
        }
        if (collapsed == null) {
          for (var j = 0; j < foundBookmarks.length; ++j) {
            buildCollapsedSpan(0, foundBookmarks[j]);
          }
        }
      }
      if (pos >= len) break;

      var upto = min(len, nextChange);
      while (true) {
        if (text != null) {
          var end = pos + text.length;
          if (collapsed == null) {
            var tokenText = end > upto ? text.substring(0, upto - pos) : text;
            addToken(tokenText, style != null ? style + spanStyle : spanStyle,
                     spanStartStyle,
                     pos + tokenText.length == nextChange ? spanEndStyle : "",
                     title, css);
          }
          if (end >= upto) {
            text = text.substring(upto - pos);
            pos = upto; break;
          }
          pos = end;
          spanStartStyle = "";
        }
        text = allText.substring(at, at = styles[i++]);
        style = cm.interpretTokenStyle(styles[i++], cm.options);
      }
    }
  }
}

class BidiSpan {
  var level, from, to;

  BidiSpan(level, from, to) {
    this.level = level;
    this.from = from;
    this.to = to;
  }
  String toString() => 'BidiSpan($level, $from, $to)';
}

// {from: from, to: to, margin: margin, isCursor: isCursor}
class ScrollDelta {
  Pos from, to;
  int margin;
  bool isCursor;
  ScrollDelta(this.from, this.to, [this.margin, this.isCursor = false]);
  String toString() => 'ScrollDelta($from, $to, $margin, $isCursor)';
}

// {index: index, lineN: newN}
class CutPoint {
  int index, lineN;
  CutPoint(this.index, this.lineN);
  String toString() => 'CutPoint($index, $lineN)';
}

class KeySpec {
  // Used in keymaps for emacs & vi
  var motion;
  var keys;
  var type;
  var operator;
  var motionArgs;
}

class TouchTime extends Loc {
  static DateTime base = new DateTime.fromMillisecondsSinceEpoch(0);

  DateTime start;
  TouchTime prev;
  bool moved;
  DateTime end;

  TouchTime(this.start, this.prev, this.moved) : super(0, 0) {
    end = base;
  }

  TouchTime.def() : super(0, 0) {
    end = base;
  }
}
