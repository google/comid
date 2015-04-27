// Copyright (c) 2015, the Comid Authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library comid.showhints;

import 'dart:math';
import 'dart:html';
import 'package:comid/codemirror.dart';

var HINT_ELEMENT_CLASS        = "CodeMirror-hint";
var ACTIVE_HINT_ELEMENT_CLASS = "CodeMirror-hint-active";
var WORD = new RegExp(r'[\w$]+');
var RANGE = 500;


// This is the old interface, kept around for now to stay
// backwards-compatible. TODO: Remove this.
//CodeMirror.showHint = function(cm, getHints, options) {
//  if (!getHints) return cm.showHint(options);
//  if (options && options.async) getHints.async = true;
//  var newOpts = {hint: getHints};
//  if (options) for (var prop in options) newOpts[prop] = options[prop];
//  return cm.showHint(newOpts);
//};

var asyncRunID = 0;
retrieveHints(getter, cm, completion, then) {
  if (completion.options.async) {
    var id = ++asyncRunID;
    // Note that last two args are swapped w.r.t. CodeMirror
    getter(cm, completion.options, (hints) {
      if (asyncRunID == id) then(hints);
    });
  } else {
    then(getter(cm, completion.options));
  }
}

void showHint([CodeMirror cm, CompletionOptions options]) {
  if (cm == null) return null;
  // We want a single cursor position.
  if (cm.listSelections().length > 1 || cm.somethingSelected()) {
    return null;
  }

  if (cm.state.completionActive != null) {
    cm.state.completionActive.close();
  }
  var completion = cm.state.completionActive = new Completion(cm, options);
  var getHints = completion.options.hint;
  if (getHints == null) {
    return null;
  }

  cm.signal(cm, "startCompletion", cm);
  return retrieveHints(getHints, cm, completion, (hints) { completion.showHints(hints); });
}

initialize() {
  if (!CodeMirror.defaultCommands.containsKey('showHint')) {
    CodeMirror.defaultCommands['showHint'] = showHint;
  }
  if (!CodeMirror.defaultCommands.containsKey('autocomplete')) {
    CodeMirror.defaultCommands['autocomplete'] = showHint;
  }
  CodeMirror.defineOption("hintOptions", null);
  _initializeHelpers();
}

class Completion {
  final CodeMirror cm;
  CompletionOptions options;
  var widget;
  var onClose;


  Completion(this.cm, CompletionOptions options) {
    this.options = this.buildOptions(options);
    this.widget = this.onClose = null;
  }

  close() {
    if (!active()) {
      return;
    }
    cm.state.completionActive = null;

    if (widget != null) {
      widget.close();
    }
    if (onClose != null) {
      onClose();
    }
    cm.signal(cm, "endCompletion", cm);
  }

  active() {
    return cm.state.completionActive == this;
  }

  pick(ProposalList data, i) {
    var completion = data[i];
    if (completion.hint != null) {
      completion.hint(cm, data, completion);
    } else {
      var from = completion.from == null ? data.from : completion.from;
      var to = completion.to == null ? data.to : completion.to;
      cm.replaceRange(getText(completion), from, to, "complete");
    }
    cm.signal(data, "pick", completion);
    close();
  }

  showHints(ProposalList data) {
    if (data == null || data.isEmpty || !active()) return close();

    if (options.completeSingle && data.length == 1) {
      pick(data, 0);
    } else {
      showWidget(data);
    }
  }

  showWidget(ProposalList data) {
    widget = new Widget(this, data);
    cm.signal(data, "shown");

    int debounce = 0;
    Completion completion = this;
    bool finished = false;
    var closeOn = options.closeCharacters;
    var startPos = cm.getCursor();
    var startLen = cm.getLine(startPos.line).length;

    var requestAnimationFrame = window.requestAnimationFrame;
    var cancelAnimationFrame = window.cancelAnimationFrame;

    Function done;

    finishUpdate(ProposalList data_) {
      data = data_;
      if (finished) {
        return;
      }
      if (data == null || data.isEmpty) {
        done();
        return;
      }
      if (completion.widget) {
        completion.widget.close();
      }
      completion.widget = new Widget(completion, data);
    }

    update(num x) {
      if (finished) return;
      cm.signal(data, "update");
      retrieveHints(completion.options.hint, completion.cm, completion, finishUpdate);
    }

    clearDebounce() {
      if (debounce > 0) {
        cancelAnimationFrame(debounce);
        debounce = 0;
      }
    }

    activity(e) {
      clearDebounce();
      var pos = completion.cm.getCursor(), line = completion.cm.getLine(pos.line);
      if (pos.line != startPos.line || line.length - pos.char != startLen - startPos.char ||
          pos.char < startPos.char || completion.cm.somethingSelected() ||
          (pos.char != 0 && closeOn.hasMatch(line.substring(pos.char - 1, pos.char)))) {
        completion.close();
      } else {
        debounce = requestAnimationFrame(update);
        if (completion.widget != null) completion.widget.close();
      }
    }

    done = () {
      if (finished) return;
      finished = true;
      completion.close();
      completion.cm.off(cm, "cursorActivity", activity);
      if (data != null) cm.signal(data, "close");
    };

    cm.on(cm, "cursorActivity", activity);
    onClose = done;
  }

  CompletionOptions buildOptions(CompletionOptions options) {
    if (options != null) return options;
    var opts = cm.options.hintOptions;
    if (opts == null) opts = new CompletionOptions();
    return opts;
//    editor.hint = options['hint'];
//    for (var prop in defaultOptions) out[prop] = defaultOptions[prop];
//    if (editor) for (var prop in editor)
//      if (editor[prop] != null) out[prop] = editor[prop];
//    if (options) for (var prop in options)
//      if (options[prop] != null) out[prop] = options[prop];
//    return out;
  }
}

getText(completion) {
  if (completion is String) return completion;
  else return completion.text;
}

buildKeyMap(Completion completion, KeyHandle handle) {
  var baseMap = {
    'Up': ([cm]) { handle.moveFocus(-1); },
    'Down': ([cm]) { handle.moveFocus(1);},
    'PageUp': ([cm]) { handle.moveFocus(-handle.menuSize() + 1, true); },
    'PageDown': ([cm]) { handle.moveFocus(handle.menuSize() - 1, true); },
    'Home': ([cm]) { handle.setFocus(0); },
    'End': ([cm]) { handle.setFocus(handle.length - 1); },
    'Enter': handle.pick,
    'Tab': handle.pick,
    'Esc': handle.close
  };
  Map custom = completion.options.customKeys;
  var ourMap = custom != null ? {} : baseMap;
  addBinding(key, val) {
    var bound;
    if (val is String)
      bound = (cm) { return val(cm, handle); };
    // This mechanism is deprecated
    else if (baseMap[val] != null)
      bound = baseMap[val];
    else
      bound = val;
    ourMap[key] = bound;
  }
  if (custom != null)
    for (var key in custom.keys) if (custom[key] != null)
      addBinding(key, custom[key]);
  var extra = completion.options.extraKeys;
  if (extra != null)
    for (var key in extra.keys) if (extra[key] != null)
      addBinding(key, extra[key]);
  return ourMap;
}

Element getHintElement(Element hintsElement, Element el) {
  while (el != null && el != hintsElement) {
    if (el.nodeName.toUpperCase() == "LI" && el.parentNode == hintsElement) return el;
    el = el.parentNode;
  }
  return null;
}

Proposal proposal(var target) {
  if (target is Proposal) return target;
  else return new Proposal(target);
}

class Widget {
  Completion completion;
  ProposalList data;
  UListElement hints;
  int selectedHint;
  Map keyMap;
  Function onFocus, onBlur, onScroll;

  Widget(Completion completion, ProposalList data) {
    this.completion = completion;
    this.data = data;

    var widget = this;
    CodeMirror cm = completion.cm;

    hints = document.createElement("ul");
    hints.className = "CodeMirror-hints";
    selectedHint = data.selectedHint == null ? 0 : data.selectedHint;

    for (var i = 0; i < data.length; ++i) {
      LIElement elt = hints.append(document.createElement("li"));
      var cur = proposal(data[i]);
      var className = HINT_ELEMENT_CLASS +
          (i != selectedHint ? "" : " " + ACTIVE_HINT_ELEMENT_CLASS);
      if (cur.className != null) className = cur.className + " " + className;
      elt.className = className;
      if (cur.render != null) {
        cur.render(elt, data, cur);
      } else {
        String text = cur.displayText;
        if (text == null) text = getText(cur);
        elt.append(new Text(text));
      }
      setNodeData(elt, 'hintId', "$i"); //elt.hintId = i;
    }

    var pos = cm.cursorCoords(completion.options.alignWithWord ? data.from : null);
    var left = pos.left, top = pos.bottom;
    bool below = true;
    hints.style.left = "${left}px";
    hints.style.top = "${top}px";
    // If we're at the edge of the screen, then we want the menu to appear on the left of the cursor.
    num winW = window.innerWidth == 0
        ? max(document.body.offsetWidth, document.documentElement.offsetWidth)
        : window.innerWidth;
    num winH = window.innerHeight == 0
        ? max(document.body.offsetHeight, document.documentElement.offsetHeight)
        : window.innerHeight;
    Element target = completion.options.container;
    if (target == null) target = document.body;
    target.append(hints);
    var box = hints.getBoundingClientRect();
    num overlapY = box.bottom - winH;
    if (overlapY > 0) {
      var height = box.bottom - box.top, curTop = pos.top - (pos.bottom - box.top);
      if (curTop - height > 0) { // Fits above cursor
        hints.style.top = "${top = pos.top - height}px";
        below = false;
      } else if (height > winH) {
        hints.style.height = "${winH - 5}px";
        hints.style.top = "${top = pos.bottom - box.top}px";
        var cursor = cm.getCursor();
        if (data.from.char != cursor.char) {
          pos = cm.cursorCoords(cursor);
          hints.style.left = "${left = pos.left}px";
          box = hints.getBoundingClientRect();
        }
      }
    }
    num overlapX = box.right - winW;
    if (overlapX > 0) {
      if (box.right - box.left > winW) {
        hints.style.width = "${winW - 5}px";
        overlapX -= (box.right - box.left) - winW;
      }
      hints.style.left = "${left = pos.left - overlapX}px";
    }

    keyMap = buildKeyMap(completion, new KeyHandle(
      moveFocus: (int n, [bool avoidWrap = false]) {
          widget.changeActive(widget.selectedHint + n, avoidWrap);
        },
      setFocus: (int n) { widget.changeActive(n); },
      menuSize: () { return widget.screenAmount(); },
      length: data.length,
      close: ([cm]) { completion.close(); },
      pick: ([cm]) { widget.pick(); },
      data: data
    ));
    cm.addKeyMap(keyMap);

    if (completion.options.closeOnUnfocus) {
      var closingOnBlur;
      onBlur = (cm) { closingOnBlur = setTimeout(() { completion.close(); }, 100); };
      onFocus = (cm) { clearTimeout(closingOnBlur); };
      cm.on(cm, "blur", onBlur);
      cm.on(cm, "focus", onFocus);
    }

    var startScroll = cm.getScrollInfo();
    onScroll = (e) {
      var curScroll = cm.getScrollInfo();
      var editor = cm.getWrapperElement().getBoundingClientRect();
      var newTop = top + startScroll.top - curScroll.top;
      var point = newTop - _scrollOffset();
      if (!below) point += hints.offsetHeight;
      if (point <= editor.top || point >= editor.bottom) {
        return completion.close();
      }
      hints.style.top = "${newTop}px";
      hints.style.left = "${left + startScroll.left - curScroll.left}px";
    };
    cm.on(cm, "scroll", onScroll);

    cm.on(hints, "dblclick", (MouseEvent e) {
      var t = getHintElement(hints, e.target);
      if (t == null) return;
      String hintId = getNodeData(t, "hintId");
      if (hintId != null) {
        widget.changeActive(int.parse(hintId)); widget.pick();
      }
    });

    cm.on(hints, "click", (MouseEvent e) {
      var t = getHintElement(hints, e.target);
      if (t == null) return;
      String hintId = getNodeData(t, "hintId");
      if (hintId != null) {
        widget.changeActive(int.parse(hintId));
        if (completion.options.completeOnSingleClick) widget.pick();
      }
    });

    cm.on(hints, "mousedown", (MouseEvent e) {
      setTimeout(() { cm.focus(); }, 20);
    });

    cm.signal(data, "select", data[0], hints.firstChild);
  }

  close() {
    if (completion.widget != this) return;
    completion.widget = null;
    hints.remove();
    completion.cm.removeKeyMap(keyMap);

    var cm = completion.cm;
    if (completion.options.closeOnUnfocus) {
      cm.off(cm, "blur", onBlur);
      cm.off(cm, "focus", onFocus);
    }
    cm.off(cm, "scroll", onScroll);
  }

  pick() {
    completion.pick(data, selectedHint);
  }

  changeActive(int i, [bool avoidWrap = false]) {
    if (i >= data.length)
      i = avoidWrap ? data.length - 1 : 0;
    else if (i < 0)
      i = avoidWrap ? 0  : data.length - 1;
    if (selectedHint == i) return;
    var node = hints.childNodes[selectedHint];
//    node.className = node.className.replace(" " + ACTIVE_HINT_ELEMENT_CLASS, "");
    rmClass(node, ACTIVE_HINT_ELEMENT_CLASS);
    node = hints.childNodes[selectedHint = i];
    node.className += " " + ACTIVE_HINT_ELEMENT_CLASS;
    if (node.offsetTop < hints.scrollTop)
      hints.scrollTop = node.offsetTop - 3;
    else if (node.offsetTop + node.offsetHeight > hints.scrollTop + hints.clientHeight)
      hints.scrollTop = node.offsetTop + node.offsetHeight - hints.clientHeight + 3;
    var cm = completion.cm;
    cm.signal(data, "select", data[selectedHint], node);
  }

  screenAmount() {
    num amt = hints.clientHeight / (hints.firstChild as Element).offsetHeight;
    int amount = amt.floor();
    return amount == 0 ? 1 : amount;
  }
}

int _scrollOffset() {
  if (window.pageYOffset == 0) {
    if (document.documentElement == null) {
      return document.body.scrollTop;
    } else {
      return document.documentElement.scrollTop;
    }
  } else {
    return window.pageYOffset;
  }
}

class KeyHandle {
  Function moveFocus;
  Function setFocus;
  Function menuSize;
  int length;
  Function close;
  Function pick;
  ProposalList data;

  KeyHandle({
    this.moveFocus: null,
    this.setFocus: null,
    this.menuSize: null,
    this.length: 0,
    this.close: null,
    this.pick: null,
    this.data: null
  }) {
    if (moveFocus == null || setFocus == null || menuSize == null ||
        length == 0 || close == null || pick == null || data == null) {
      throw new StateError("All parameters to KeyHandle() are required");
    }
  }
}

class Proposal {
  /// String to insert if completion is selected.
  String text;
  /// CSS class name appended after hint and active-hint classes.
  String className;
  /// Function to do custom rendering of displayText into the
  /// LIElement: f(Element, ProposalList, Proposal). Normally, a single Text
  /// node is appended but this could be used to append multiple Text nodes
  /// with font and color changes.
  Function render;

  Proposal(this.text, {this.className, this.render});

  /// String to display in completion list (may be overridden by subclass).
  String get displayText => text;
  /// Start position of text to be replaced when selected.
  Pos get from => null;
  /// End position of text to be replaced when selected.
  Pos get to => null;
  /// Function f(CodeMirror, ProposalList, Proposal) called to do custom
  /// editing. It should replace the editor's selection with the proposal text.
  Function get hint => null;
}

class ProposalList extends Object with EventManager {
  Pos from, to;
  List _list;
  var selectedHint;

  get operationGroup => throw new StateError("No operation group; cannot use signalLater()");

  ProposalList({list, this.from, this.to}) : this._list = list {
    if (list == null || from == null || to == null) {
      throw new StateError("All parameters to ProposalList() are required:");
    }
  }

  bool get isEmpty => _list.isEmpty;
  int get length => _list.length;
  Proposal operator [] (n) {
    var x = _list[n];
    if (x is String) x = new Proposal(x);
    return x;
  }
}

_initializeHelpers() {
  // Functions registered as helpers for 'hint' must return a ProposalList.
  CodeMirror.registerHelper("hint", "auto", (CodeMirror cm, var options) {
    var helpers = cm.getHelpers(cm.getCursor(), "hint"), words;
    if (helpers.length > 0) {
      for (var i = 0; i < helpers.length; i++) {
        ProposalList cur = helpers[i](cm, options);
        if (cur != null && cur.length > 0) return cur;
      }
    } else if ((words = cm.getHelper(cm.getCursor(), "hintWords")) != null) {
      if (words != null) {
        return CodeMirror.getNamedHelper('hint', 'fromList')(cm, {'words': words});
      }
    } else if (CodeMirror.getNamedHelper('hint', 'anyword') != null) {
      return CodeMirror.getNamedHelper('hint', 'anyword')(cm, options);
    }
  });

  CodeMirror.registerHelper("hint", "fromList", (CodeMirror cm, var options) {
    var cur = cm.getCursor(), token = cm.getTokenAt(cur);
    var found = [];
    if (options is Map) {
      for (var i = 0; i < options['words'].length; i++) {
        var word = options['words'][i];
        if (word.startsWith(token.string)) {
          found.add(word);
        }
      }
    }

    if (found.length > 0) {
      return new ProposalList(
        list: found,
        from: new Pos(cur.line, token.start),
        to: new Pos(cur.line, token.end)
      );
    } else if (CodeMirror.getNamedHelper('hint', 'anyword') != null) {
      return CodeMirror.getNamedHelper('hint', 'anyword')(cm, options);
    }
  });

  CodeMirror.registerHelper("hint", "anyword", (CodeMirror editor, var options) {
    RegExp word = WORD;
    int range = RANGE;
    if (options is Map) {
      if (options['word'] != null) word = options['word'];
      if (options['range'] != null) range = options['range'];
    }
    Pos cur = editor.getCursor();
    String curLine = editor.getLine(cur.line);
    int end = cur.char, start = end;
    while (start > 0 && word.hasMatch(curLine.substring(start - 1, start))) --start;
    var curWord = start != end ? curLine.substring(start, end) : null;

    var list = [], seen = {};
    var re = new RegExp(word.pattern);
    for (var dir = -1; dir <= 1; dir += 2) {
      var line = cur.line, endLine = min(max(line + dir * range, editor.firstLine()), editor.lastLine()) + dir;
      for (; line != endLine; line += dir) {
        var text = editor.getLine(line);
        Iterable<Match> ms;
        if ((ms = re.allMatches(text)) != null) {
          for (Match m in ms) {
            if (line == cur.line && m[0] == curWord) continue;
            if ((curWord == null || m[0].lastIndexOf(curWord, 0) == 0) && !(seen.containsKey(m[0]))) {
              seen[m[0]] = true;
              list.add(m[0]);
            }
          }
        }
      }
    }
    var token = editor.getTokenAt(cur);
    return new ProposalList(
        list: list,
        from: new Pos(cur.line, token.start),
        to: new Pos(cur.line, token.end)
    );
  });
}

/// The CompletionProvider computes a list of completions and returns a
/// ProposalList. If called in async mode it has an optional third argument,
/// which is the internal function used to display the proposals.
typedef ProposalList CompletionProvider(
    CodeMirror cm,
    var options, // CompletionOptions or Map
    [ShowProposals callback]);

typedef void ShowProposals(ProposalList list); // showHints, finishUpdate

class CompletionOptions {
  static RegExp defaultCloseChars = new RegExp(r'[\s()\[\]{};:>,]');
  Function hint;
  bool completeSingle;
  bool alignWithWord;
  RegExp closeCharacters;
  bool closeOnUnfocus;
  bool completeOnSingleClick;
  bool async;
  var container;
  var customKeys;
  var extraKeys;

  CompletionOptions({
    hint: null,
    this.completeSingle: true,
    this.alignWithWord: true,
    closeCharacters: null,
    this.closeOnUnfocus: true,
    this.completeOnSingleClick: false,
    this.async: false,
    this.container: null,
    this.customKeys: null,
    this.extraKeys: null
  }) {
    if (hint == null) {
      this.hint = CodeMirror.getNamedHelper('hint', 'auto');
    } else {
      this.hint = hint;
    }
    if (closeCharacters is String) {
      this.closeCharacters = new RegExp(closeCharacters);
    } else if (closeCharacters == null) {
      this.closeCharacters = defaultCloseChars;
    } else {
      this.closeCharacters = closeCharacters;
    }
  }
}