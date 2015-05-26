// Copyright (c) 2015, the Comid Authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library comid.closebrackets;

import 'package:comid/codemirror.dart';

var defaults = {
  'pairs': "()[]{}''\"\"",
  'triples': "",
  'explode': "[]{}"
};

bool _isInitialized = false;
initializeBracketClosing() {
  if (_isInitialized) return;
  _isInitialized = true;

  handler(String ch) {
    return (CodeEditor cm) { return handleChar(cm, ch); };
  }
  for (var i = 0; i < bind.length; i++) {
    String char = bind.substring(i, i+1);
    keyMap["'" + char + "'"] = handler(char);
  }

  CodeMirror.defineOption("autoCloseBrackets", false, (CodeEditor cm, val, old) {
    if (old != Options.Init) {
      cm.removeKeyMap(keyMap);
      cm.state.closeBrackets = null;
    }
    if (val != null && val != false) {
      cm.state.closeBrackets = val;
      cm.addKeyMap(keyMap);
    }
  });
}

  String getOption(dynamic conf, String name) {
    if (name == "pairs" && conf is String) return conf;
    if (conf is Map && conf[name] != null) return conf[name];
    return defaults[name];
  }

  String bind = defaults['pairs'] + "`";
  Map keyMap = {'Backspace': handleBackspace, 'Enter': handleEnter};

  dynamic getConfig(CodeEditor cm) {
    var deflt = cm.state.closeBrackets;
    if (deflt == null || deflt == false) return null;
    Mode mode = cm.getModeAt(cm.getCursor());
    if (mode.closeBrackets == null) {
      return deflt;
    } else {
      return mode.closeBrackets;
    }
  }

  dynamic handleBackspace(CodeEditor cm) {
    var conf = getConfig(cm);
    if (conf == null || cm.getOption("disableInput")) return Pass;

    var pairs = getOption(conf, "pairs");
    var ranges = cm.listSelections();
    for (var i = 0; i < ranges.length; i++) {
      if (!ranges[i].empty()) return Pass;
      String around = charsAround(cm, ranges[i].head);
      if (around == null || pairs.indexOf(around) % 2 != 0) return Pass;
    }
    for (var i = ranges.length - 1; i >= 0; i--) {
      var cur = ranges[i].head;
      cm.replaceRange("", new Pos(cur.line, cur.char - 1),
          new Pos(cur.line, cur.char + 1));
    }
    return null;
  }

  dynamic handleEnter(CodeEditor cm) {
    var conf = getConfig(cm);
    String explode = conf != null ? getOption(conf, "explode") : null;
    if (explode == null || cm.getOption("disableInput")) return Pass;

    var ranges = cm.listSelections();
    for (var i = 0; i < ranges.length; i++) {
      if (!ranges[i].empty()) return Pass;
      String around = charsAround(cm, ranges[i].head);
      if (around == null || explode.indexOf(around) % 2 != 0) return Pass;
    }
    cm.operation(cm, () {
      cm.replaceSelection("\n\n", null);
      cm.execCommand("goCharLeft");
      ranges = cm.listSelections();
      for (var i = 0; i < ranges.length; i++) {
        var line = ranges[i].head.line;
        cm.indentLine(line, null, true);
        cm.indentLine(line + 1, null, true);
      }
    })();
    return null;
  }

  dynamic handleChar(CodeEditor cm, String ch) {
    var conf = getConfig(cm);
    if (!conf || cm.getOption("disableInput")) return Pass;

    var pairs = getOption(conf, "pairs");
    var pos = pairs.indexOf(ch);
    if (pos == -1) return Pass;
    var triples = getOption(conf, "triples");

    var identical = pairs.substring(pos + 1, pos + 2) == ch;
    var ranges = cm.listSelections();
    var opening = pos % 2 == 0;

    var type;
    for (var i = 0; i < ranges.length; i++) {
      var range = ranges[i], cur = range.head, curType;
      var next = cm.getRange(cur, new Pos(cur.line, cur.char + 1));
      if (opening && !range.empty()) {
        curType = "surround";
      } else if ((identical || !opening) && next == ch) {
        if (triples.indexOf(ch) >= 0 &&
            cm.getRange(cur, new Pos(cur.line, cur.char + 3)) == ch + ch + ch)
          curType = "skipThree";
        else
          curType = "skip";
      } else if (identical && cur.char > 1 && triples.indexOf(ch) >= 0 &&
          cm.getRange(new Pos(cur.line, cur.char - 2), cur) == "$ch$ch" &&
          (cur.char <= 2 || cm.getRange(new Pos(cur.line, cur.char - 3),
              new Pos(cur.line, cur.char - 2)) != ch)) {
        curType = "addFour";
      } else if (identical) {
        if (!isWordChar(next) && enteringString(cm, cur, ch)) curType = "both";
        else return Pass;
      } else if (opening && (cm.getLine(cur.line).length == cur.char ||
                             isClosingBracket(next, pairs) ||
                             new RegExp(r'\s').hasMatch(next))) {
        curType = "both";
      } else {
        return Pass;
      }
      if (type == null) type = curType;
      else if (type != curType) return Pass;
    }

    var left = pos % 2 != 0 ? pairs.substring(pos - 1, pos) : ch;
    var right = pos % 2 != 0 ? ch : pairs.substring(pos + 1, pos + 2);
    cm.operation(cm, () {
      if (type == "skip") {
        cm.execCommand("goCharRight");
      } else if (type == "skipThree") {
        for (var i = 0; i < 3; i++)
          cm.execCommand("goCharRight");
      } else if (type == "surround") {
        var sels = cm.getSelections();
        for (var i = 0; i < sels.length; i++) {
          sels[i] = left + sels[i] + right;
        }
        cm.replaceSelections(sels, "around");
      } else if (type == "both") {
        cm.replaceSelection(left + right, null);
        cm.triggerElectric(left + right);
        cm.execCommand("goCharLeft");
      } else if (type == "addFour") {
        cm.replaceSelection(left + left + left + left, "before");
        cm.execCommand("goCharRight");
      }
    })();
    return null;
  }

  bool isClosingBracket(String ch, String pairs) {
    var pos = pairs.lastIndexOf(ch);
    return pos > -1 && pos % 2 == 1;
  }

String charsAround(CodeMirror cm, Pos pos) {
  var str = cm.getRange(new Pos(pos.line, pos.char - 1),
                        new Pos(pos.line, pos.char + 1));
  return str.length == 2 ? str : null;
}

// Project the token type that will exists after the given char is
// typed, and use it to determine whether it would cause the start
// of a string token.
dynamic enteringString(CodeMirror cm, Pos pos, ch) {
  var line = cm.getLine(pos.line);
  var token = cm.getTokenAt(pos);
  if (new RegExp('\bstring2?\b').hasMatch(token.type)) return false;
  var str = line.substring(0, pos.char) + ch + line.substring(pos.char);
  var stream = new StringStream(str, 4);
  stream.pos = stream.start = token.start;
  for (;;) {
    var type1 = cm.doc.getMode().token(stream, token.state);
    if (stream.pos >= pos.char + 1) {
//      return new RegExp('\bstring2?\b').hasMatch(type1);
      // Bug in Dart regexp prevents previous line from working.
      return "string" == type1 || "string2" == type1 ||
          new RegExp('\bstring2?\b').hasMatch(type1);
    }
    stream.start = stream.pos;
  }
}
