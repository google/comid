// Copyright (c) 2015, the Comid Authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library comid.closebrackets;

import 'package:comid/codemirror.dart';

var DEFAULT_BRACKETS = "()[]{}<>''\"\"";
var DEFAULT_EXPLODE_ON_ENTER = "[]{}";
RegExp SPACE_CHAR_REGEX = new RegExp(r'\s');

bool _isInitialized = false;
initializeBracketClosing() {
  if (_isInitialized) return;
  _isInitialized = true;

  CodeMirror.defineOption("autoCloseBrackets", false, (cm, val, old) {
    if (old != Options.Init && old != null)
      cm.removeKeyMap("autoCloseBrackets");
    if (val == null) return;
    var pairs = DEFAULT_BRACKETS, explode = DEFAULT_EXPLODE_ON_ENTER;
    if (val is String) pairs = val;
    else if (val is Map) {
      if (val['pairs'] != null) pairs = val['pairs'];
      if (val['explode'] != null) explode = val['explode'];
    }
    var map = buildKeymap(pairs);
    if (explode != null) map['Enter'] = buildExplodeHandler(explode);
    cm.addKeyMap(map);
  });
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

Map buildKeymap(String pairs) {
  Map map = {
    'name' : "autoCloseBrackets",
    'Backspace': (CodeMirror cm) {
      if (cm.getOption("disableInput")) return Pass;
      var ranges = cm.listSelections();
      for (var i = 0; i < ranges.length; i++) {
        if (!ranges[i].empty()) return Pass;
        var around = charsAround(cm, ranges[i].head);
        if (around  == null || pairs.indexOf(around) % 2 != 0) return Pass;
      }
      for (var i = ranges.length - 1; i >= 0; i--) {
        var cur = ranges[i].head;
        cm.replaceRange("", new Pos(cur.line, cur.char - 1), new Pos(cur.line, cur.char + 1));
      }
    }
  };
  var closingBrackets = "";
  for (var i = 0; i < pairs.length; i += 2) ((left, right) {
    closingBrackets += right;
    map["'" + left + "'"] = (CodeMirror cm) {
      if (cm.getOption("disableInput")) return Pass;
      var ranges = cm.listSelections(), type, next;
      for (var i = 0; i < ranges.length; i++) {
        var range = ranges[i], cur = range.head, curType;
        var next = cm.getRange(cur, new Pos(cur.line, cur.char + 1));
        if (!range.empty()) {
          curType = "surround";
        } else if (left == right && next == right) {
          if (cm.getRange(cur, new Pos(cur.line, cur.char + 3)) == left + left + left) {
            curType = "skipThree";
          } else {
            curType = "skip";
          }
        } else if (left == right && cur.char > 1 &&
                   cm.getRange(new Pos(cur.line, cur.char - 2), cur) == left + left &&
                   (cur.char <= 2 || cm.getRange(new Pos(cur.line, cur.char - 3), new Pos(cur.line, cur.char - 2)) != left)) {
          curType = "addFour";
        } else if (left == '"' || left == "'") {
          if (!isWordChar(next) && enteringString(cm, cur, left)) curType = "both";
          else return Pass;
        } else if (cm.getLine(cur.line).length == cur.char ||
            closingBrackets.indexOf(next) >= 0 || SPACE_CHAR_REGEX.hasMatch(next)) {
          curType = "both";
        } else {
          return Pass;
        }
        if (type == null) type = curType;
        else if (type != curType) return Pass;
      }

      cm.operation(cm, () {
        if (type == "skip") {
          cm.execCommand("goCharRight");
        } else if (type == "skipThree") {
          for (var i = 0; i < 3; i++)
            cm.execCommand("goCharRight");
        } else if (type == "surround") {
          var sels = cm.getSelections();
          for (var i = 0; i < sels.length; i++)
            sels[i] = left + sels[i] + right;
          cm.replaceSelections(sels, "around");
        } else if (type == "both") {
          cm.replaceSelection(left + right, null);
          cm.execCommand("goCharLeft");
        } else if (type == "addFour") {
          cm.replaceSelection(left + left + left + left, "before");
          cm.execCommand("goCharRight");
        }
      })();
    };
    if (left != right) map["'" + right + "'"] = (CodeMirror cm) {
      var ranges = cm.listSelections();
      for (var i = 0; i < ranges.length; i++) {
        var range = ranges[i];
        if (!range.empty() ||
            cm.getRange(range.head, new Pos(range.head.line, range.head.char + 1)) != right)
          return Pass;
      }
      cm.execCommand("goCharRight");
    };
  })(pairs.substring(i, i + 1), pairs.substring(i + 1, i + 2));
  return map;
}

buildExplodeHandler(String pairs) {
  return (CodeMirror cm) {
    if (cm.getOption("disableInput")) return Pass;
    var ranges = cm.listSelections();
    for (var i = 0; i < ranges.length; i++) {
      if (!ranges[i].empty()) return Pass;
      var around = charsAround(cm, ranges[i].head);
      if (around == null || pairs.indexOf(around) % 2 != 0) return Pass;
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
  };
}
