// Copyright (c) 2015, the Comid Authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library comid.mode.fold.markdown;

import 'package:comid/codemirror.dart';

initialize() {
  CodeMirror.registerHelper("fold", "markdown", foldMarkdown);
}

Reach foldMarkdown(CodeMirror cm, Pos start) {
  var maxDepth = 100;

  bool isHeader(int lineNo) {
    var tokentype = cm.getTokenTypeAt(new Pos(lineNo, 0));
    return tokentype != null && new RegExp(r'\bheader\b').hasMatch(tokentype);
  }

  int headerLevel(int lineNo, String line, String nextLine) {
    var match = line == null
        ? null : new RegExp(r'^#+').firstMatch(line);
    if (match != null && isHeader(lineNo)) {
      return match[0].length;
    }
    match = nextLine == null
        ? null : new RegExp(r'^[=\-]+\s*$').firstMatch(nextLine);
    if (match != null && isHeader(lineNo + 1)) {
      return nextLine.startsWith("=") ? 1 : 2;
    }
    return maxDepth;
  }

  var firstLine = cm.getLine(start.line);
  var nextLine = cm.getLine(start.line + 1);
  var level = headerLevel(start.line, firstLine, nextLine);
  if (level == maxDepth) return null;//undefined;

  var lastLineNo = cm.lastLine();
  var end = start.line, nextNextLine = cm.getLine(end + 2);
  while (end < lastLineNo) {
    if (headerLevel(end + 1, nextLine, nextNextLine) <= level) break;
    ++end;
    nextLine = nextNextLine;
    nextNextLine = cm.getLine(end + 2);
  }

  var from = new Pos(start.line, firstLine.length);
  var to = new Pos(end, cm.getLine(end).length);
  return new Reach(from, to);
}
