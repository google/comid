// Copyright (c) 2015, the Comid Authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library comid.mode.fold.indent;

import 'package:comid/codemirror.dart';

initialize() {
  CodeMirror.registerHelper("fold", "indent", foldIndent);
}

Reach foldIndent(CodeMirror cm, Pos start) {
  int tabSize = cm.getOption("tabSize");
  String firstLine = cm.getLine(start.line);
  if (!new RegExp(r'\S').hasMatch(firstLine)) {
    return null;
  }
  int getIndent(String line) {
    return countColumn(line, null, tabSize);
  };
  var myIndent = getIndent(firstLine);
  int lastLineInFold = -1;
  // Go through lines until we find a line that definitely doesn't belong in
  // the block we're folding, or to the end.
  for (var i = start.line + 1, end = cm.lastLine(); i <= end; ++i) {
    var curLine = cm.getLine(i);
    var curIndent = getIndent(curLine);
    if (curIndent > myIndent) {
      // Lines with a greater indent are considered part of the block.
      lastLineInFold = i;
    } else if (!new RegExp(r'\S').hasMatch(curLine)) {
      // Empty lines might be breaks within the block we're trying to fold.
    } else {
      // A non-empty line at an indent equal to or less than ours marks the
      // start of another block.
      break;
    }
  }
  if (lastLineInFold >= 0) {
    var from = new Pos(start.line, firstLine.length);
    var to = new Pos(lastLineInFold, cm.getLine(lastLineInFold).length);
    return new Reach(from, to);
  } else {
    return null;
  }
}
