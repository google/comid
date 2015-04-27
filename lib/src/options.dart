// Copyright (c) 2015, the Comid Authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

part of comid;

class Options {
  Map _opts = new Map<String, Object>();

  Options() {
    _opts.addAll(defaults);
  }
  Options.from(Map others) {
    _opts.addAll(defaults);
    _opts.addAll(others);
  }

  Options copy() => new Options.from(_opts);

  bool equals(Options other) {
    if (_opts.length != other._opts.length) return false;
    other._opts.forEach((k, v) {
      if (_opts[k] != v) return false;
    });
    return true;
  }

  Object operator [](String key) => _opts[key];
  void operator []=(String key, Object value) { _opts[key] = value; }

  dynamic get value => _opts['value']; // String | Doc
  dynamic get mode => _opts['mode']; // String | Map
  int get indentUnit => _opts['indentUnit'];
  bool get indentWithTabs => _opts['indentWithTabs'];
  bool get smartIndent => _opts['smartIndent'];
  int get tabSize => _opts['tabSize'];
  RegExp get specialChars => _opts['specialChars'];
  Function get specialCharPlaceholder => _opts['specialCharPlaceholder'];
  bool get electricChars => _opts['electricChars'];
  bool get rtlMoveVisually => _opts['rtlMoveVisually'];
  bool get wholeLineUpdateBefore => _opts['wholeLineUpdateBefore'];
  String get theme => _opts['theme'];
  String get keyMap => _opts['keyMap'];
  Map get extraKeys => _opts['extraKeys'];
  bool get lineWrapping => _opts['lineWrapping'];
  List<String> get gutters => _opts['gutters'];
  bool get fixedGutter => _opts['fixedGutter'];
  bool get coverGutterNextToScrollbar => _opts['coverGutterNextToScrollbar'];
  bool get lineNumbers => _opts['lineNumbers'];
  int get firstLineNumber => _opts['firstLineNumber'];
  Function get lineNumberFormatter => _opts['lineNumberFormatter'];
  bool get showCursorWhenSelecting => _opts['showCursorWhenSelecting'];
  bool get resetSelectionOnContextMenu=>_opts['resetSelectionOnContextMenu'];
  dynamic get readOnly => _opts['readOnly']; // true | false | "nocursor"
  bool get disableInput => _opts['disableInput'];
  bool get dragDrop => _opts['dragDrop'];
  num get cursorBlinkRate => _opts['cursorBlinkRate'];
  num get cursorScrollMargin => _opts['cursorScrollMargin'];
  num get cursorHeight => _opts['cursorHeight'];
  bool get singleCursorHeightPerLine => _opts['singleCursorHeightPerLine'];
  num get workTime => _opts['workTime'];
  num get workDelay => _opts['workDelay'];
  bool get flattenSpans => _opts['flattenSpans'];
  bool get addModeClass => _opts['addModeClass'];
  num get pollInterval => _opts['pollInterval'];
  int get undoDepth => _opts['undoDepth'];
  int get historyEventDelay => _opts['historyEventDelay'];
  int get viewportMargin => _opts['viewportMargin'];
  num get maxHighlightLength => _opts['maxHighlightLength'];
  bool get moveInputWithCursor => _opts['moveInputWithCursor'];
  int get tabindex => _opts['tabindex'];
  bool get autofocus => _opts['autofocus'];
  String get scrollbarStyle => _opts['scrollbarStyle'];
  String get inputStyle => _opts['inputStyle'];

  // Option for configuration of code completion & folding
  Object get hintOptions => _opts['hintOptions'];
  Object get foldOptions => _opts['foldOptions'];

  // Options to control comment toggle
  String get lineComment => _opts['lineComment'];
  String get blockCommentStart => _opts['blockCommentStart'];
  String get blockCommentEnd => _opts['blockCommentEnd'];
  String get blockCommentLead => _opts['blockCommentLead'];
  String get padding => _opts['padding'];
  bool get fullLines => _opts['fullLines'];
  bool get commentBlankLines => _opts['commentBlankLines'];
  bool get indent => _opts['indent'];
  int get scrollButtonHeight => _opts['scrollButtonHeight'];

  // Make sure the gutters options contains the element
  // "CodeMirror-linenumbers" when the lineNumbers option is true.
  void setGuttersForLineNumbers() {
    var found = gutters.indexOf("CodeMirror-linenumbers");
    if (found == -1 && lineNumbers) {
      gutters.add("CodeMirror-linenumbers");
    } else if (found > -1 && !lineNumbers) {
      gutters.remove("CodeMirror-linenumbers");
    }
  }

  // Initialization

  static Options _defaultOptions;
  static Options get defaultOptions {defaults; return _defaultOptions;}
  static Map<String, Handler> optionHandlers = new Map<String, Handler>();
  static Map<String, Object> _defaults;
  static Map<String, Object> get defaults {
    if (_defaults == null) {
      _defaults = new Map<String, Object>();
      _setDefaults();
      _defaultOptions = new Options();
      _defaultOptions._opts = _defaults;
    }
    return _defaults;
  }
  static const _specialChars =
      r"[\t\u0000-\u0019\u00ad\u200b-\u200f\u2028\u2029\ufeff]";

  static void option(String name, Object deflt,
                     [Handler handler = null, bool notOnInit = false]) {
    defaults[name] = deflt;
    if (handler != null) {
      optionHandlers[name] =
          notOnInit
            ? (cm, val, old) { if (old != Init) handler(cm, val, old); }
            : handler;
    }
  }

  // Passed to option handlers when there is no old value.
  static var Init = new Object();

  // This runs at start-up. When a CodeEditor is created it always creates
  // a new Options, which will ensure this is run one time only.
  static void _setDefaults() {
    // These two are, on init, called from the constructor because they
    // have to be initialized before the editor can start at all.
    option("value", "", (cm, val, old) {
      cm.doc.setValue(val);
    }, true);
    option("mode", null, (cm, val, old) {
      cm.doc.modeOption = val == null ? "" : val;
      cm.loadMode();
    }, true);

    option("indentUnit", 2, loadMode, true);
    option("indentWithTabs", false);
    option("smartIndent", true);
    option("tabSize", 4, (cm, val, old) {
      cm.resetModeState();
      cm.clearCaches();
      cm.regChange();
    }, true);
    option("specialChars", new RegExp(_specialChars), (cm, val, old) {
      String str = val.pattern;
      if (!val.hasMatch("\t")) { str += r"|\t"; }
      cm.state.specialChars = new RegExp(str, multiLine: true);
      if (old != Init) cm.refresh();
    });
    option("specialCharPlaceholder", _specialCharPlaceholder, (cm, val, old) {
      cm.refresh();
    }, true);
    option("electricChars", true);
    option("inputStyle", mobile ? "contenteditable" : "textarea", (cm, val, old) {
      throw new StateError("inputStyle can not (yet) be changed in a running editor"); // FIXME
    }, true);
    option("rtlMoveVisually", !windows);
    option("wholeLineUpdateBefore", true);

    option("theme", "default", (cm, val, old) {
      cm.themeChanged();
      cm.guttersChanged();
    }, true);
    option("keyMap", "default", (cm, val, old) {
      var next = cm.getKeyMap(val);
      var prev = null;
      if (old != Init) prev = cm.getKeyMap(old);
      if (prev != null) prev.detach(cm, next);
      // TODO 'attach' is used in the vim key map. Is it needed?
//      next.attach(cm, prev);
    });
    option("extraKeys", null);

    option("lineWrapping", false, wrappingChanged, true);
    option("gutters", [], (cm, val, old) {
      cm.options.setGuttersForLineNumbers();
      cm.guttersChanged();
    }, true);
    option("fixedGutter", true, (cm, val, old) {
      cm.display.gutters.style.left =
          val ? cm.display.compensateForHScroll() + "px" : "0";
      cm.refresh();
    }, true);
    option("coverGutterNextToScrollbar", false, updateScrollbars, true);
    option("coverGutterNextToScrollbar", false, (cm, val, old) {
      cm.updateScrollbars();
    }, true);
    option("scrollbarStyle", "native", (cm, val, old) {
      cm.display.initScrollbars(cm);
      cm.updateScrollbars();
      cm.display.scrollbars.setScrollTop(cm.doc.scrollTop);
      cm.display.scrollbars.setScrollLeft(cm.doc.scrollLeft);
    }, true);
    option("lineNumbers", false, (cm, val, old) {
      cm.options.setGuttersForLineNumbers();
      cm.guttersChanged();
    }, true);
    option("firstLineNumber", 1, guttersChanged, true);
    option("lineNumberFormatter", (integer) {
      return integer.toString();
    }, guttersChanged, true);
    option("showCursorWhenSelecting", false, updateSelection, true);

    option("resetSelectionOnContextMenu", true);

    option("readOnly", false, (cm, val, old) {
      if (val == "nocursor") {
        cm.onBlur(cm);
        cm.display.input.blur();
        cm.display.disabled = true;
      } else {
        cm.display.disabled = false;
        if (val != null) cm.display.input.reset();
      }
    });
    option("disableInput", false, (cm, val, old) {
      if (val != null) cm.display.input.reset();
    }, true);
    option("dragDrop", true);

    option("cursorBlinkRate", 530);
    option("cursorScrollMargin", 0);
    option("cursorHeight", 1, updateSelection, true);
    option("singleCursorHeightPerLine", true, updateSelection, true);
    option("workTime", 100);
    option("workDelay", 100);
    option("flattenSpans", true, resetModeState, true);
    option("addModeClass", false, resetModeState, true);
    option("pollInterval", 100);
    option("undoDepth", 200, (cm, val, old) {
      cm.doc.history.undoDepth = val;
    });
    option("historyEventDelay", 1250);
    option("viewportMargin", 10, (cm, val, old) { cm.refresh(); }, true);
    option("maxHighlightLength", 10000, resetModeState, true);
    option("moveInputWithCursor", true, (cm, val, old) {
      if (val != null) {
        cm.display.input.resetPosition();
      }
    });

    option("tabindex", null, (cm, val, old) {
      if (val is int) {
        cm.display.input.getField().tabIndex = val;
      } else {
        cm.display.input.getField().tabIndex = 0;
      }
    });
    option("autofocus", null);
    option("showTrailingSpace", false, (cm, val, prev) {
      // From addon/edit/trailingspace.js
      if (prev == Init) prev = false;
      if (prev && !val)
        cm.removeOverlay(_TrailingspaceMode.NAME);
      else if (!prev && val)
        cm.addOverlay(new _TrailingspaceMode());
    });
    option("scrollButtonHeight", 0);
  }
}

// Functions referenced in option handlers.

loadMode(CodeEditor cm, Object value, Object old) {
  cm.loadMode();
}
wrappingChanged(CodeEditor cm, Object value, Object old) {
  cm.wrappingChanged();
}
updateScrollbars(CodeEditor cm, Object value, Object old) {
  cm.updateScrollbars();
}
guttersChanged(CodeEditor cm, Object value, Object old) {
  cm.guttersChanged();
}
updateSelection(CodeEditor cm, Object value, Object old) {
  cm.updateSelection();
}
resetModeState(CodeEditor cm, Object value, Object old) {
  cm.resetModeState();
}

dynamic _specialCharPlaceholder(ch) {
  var token = eltspan("\u2022", "cm-invalidchar");
  token.title = "\\u" + ch.charCodeAt(0).toString(16);
  token.setAttribute("aria-label", token.title);
  return token;
}

class _TrailingspaceMode extends Mode {
  static const String NAME = "trailingspace";
  _TrailingspaceMode() {
    name = NAME;
  }
  token(stream, [state]) {
    var i, l = stream.string.length;
    var regexp = new RegExp(r'\s');
    for (i = l; i > 0 && regexp.hasMatch(stream.string.substring(i - 1, i)); --i) {}
    if (i > stream.pos) {
      stream.pos = i;
      return null;
    }
    stream.pos = l;
    return NAME;
  }
}
