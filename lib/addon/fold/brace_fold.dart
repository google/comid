// Copyright (c) 2015, the Comid Authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library comid.mode.fold.brace;

import 'dart:math';

import 'package:comid/codemirror.dart';

initialize() {
  CodeMirror.registerHelper("fold", "brace", foldBrace);
  CodeMirror.registerHelper("fold", "import", foldImport);
  CodeMirror.registerHelper("fold", "include", foldInclude);
}

Reach foldBrace(CodeMirror cm, Pos start) {
  var line = start.line, lineText = cm.getLine(line);
  int startCh;
  String tokenType;

   int findOpening(openCh) {
    for (var at = start.char, pass = 0;;) {
      var found = at <= 0 ? -1 : lineText.lastIndexOf(openCh, at - 1);
      if (found == -1) {
        if (pass == 1) break;
        pass = 1;
        at = lineText.length;
        continue;
      }
      if (pass == 1 && found < start.char) break;
      tokenType = cm.getTokenTypeAt(new Pos(line, found + 1));
      if (tokenType == null || !new RegExp(r'^(comment|string)').hasMatch(tokenType)) {
        return found + 1;
      }
      at = found - 1;
    }
    return -1;
  }

  var startToken = "{", endToken = "}";
  startCh = findOpening("{");
  if (startCh == null) {
    startToken = "[";
    endToken = "]";
    startCh = findOpening("[");
  }

  if (startCh == -1) return null;
  var count = 1, lastLine = cm.lastLine(), end, endCh;
  outer: for (var i = line; i <= lastLine; ++i) {
    var text = cm.getLine(i), pos = i == line ? startCh : 0;
    for (;;) {
      var nextOpen = text.indexOf(startToken, pos);
      var nextClose = text.indexOf(endToken, pos);
      if (nextOpen < 0) nextOpen = text.length;
      if (nextClose < 0) nextClose = text.length;
      pos = min(nextOpen, nextClose);
      if (pos == text.length) break;
      if (cm.getTokenTypeAt(new Pos(i, pos + 1)) == tokenType) {
        if (pos == nextOpen) ++count;
        else if (--count == 0) { end = i; endCh = pos; break outer; }
      }
      ++pos;
    }
  }
  if (end == null || line == end && endCh == startCh) return null;
  return new Reach(new Pos(line, startCh), new Pos(end, endCh));
}

Reach foldImport(CodeMirror cm, Pos startPos) {
  Map hasImport(line) {
    if (line < cm.firstLine() || line > cm.lastLine()) return null;
    var start = cm.getTokenAt(new Pos(line, 1));
    if (!new RegExp(r'\S').hasMatch(start.string)) {
      start = cm.getTokenAt(new Pos(line, start.end + 1));
    }
    if (start.type != "keyword" || start.string != "import") return null;
    // Now find closing semicolon, return its position
    for (var i = line, e = min(cm.lastLine(), line + 10); i <= e; ++i) {
      var text = cm.getLine(i), semi = text.indexOf(";");
      if (semi != -1) {
        return {'startCh': start.end, 'end': new Pos(i, semi)};
      }
    }
    return null;
  }

  var start = startPos.line;
  var has = hasImport(start), prev;
  if (has == null || hasImport(start - 1) != null ||
      ((prev = hasImport(start - 2)) != null && prev['end'].line == start - 1)) {
    return null;
  }
  var end;
  for (end = has['end'];;) {
    var next = hasImport(end.line + 1);
    if (next == null) break;
    end = next['end'];
  }
  return new Reach(cm.doc.clipPos(new Pos(start, has['startCh'] + 1)), end);
}

Reach foldInclude(CodeMirror cm, Pos startPos) {
  int hasInclude(line) {
    if (line < cm.firstLine() || line > cm.lastLine()) return 0;
    var start = cm.getTokenAt(new Pos(line, 1));
    if (!new RegExp(r'\S').hasMatch(start.string)) {
      start = cm.getTokenAt(new Pos(line, start.end + 1));
    }
    if (start.type == "meta" && start.string.substring(0, 8) == "#include") {
      return start.start + 8;
    }
    return 0;
  }

  var start = startPos.line;
  var has = hasInclude(start);
  if (has == 0 || hasInclude(start - 1) != 0) return null;
  var end;
  for (end = start;;) {
    var next = hasInclude(end + 1);
    if (next == 0) break;
    ++end;
  }
  return new Reach(new Pos(start, has + 1), cm.doc.clipPos(new Pos(end)));
}
