// Copyright (c) 2015, the Comid Authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library comid.mode.fold.comment;

import 'dart:math';

import 'package:comid/codemirror.dart';

initialize() {
  CodeMirror.registerGlobalHelper("fold", "comment", _hasBlocks, foldComment);
}

bool _hasBlocks(Mode mode, CodeMirror cm) {
  return mode.blockCommentStart != null && mode.blockCommentEnd != null;
}

Reach foldComment(CodeMirror cm, Pos start) {
  var mode = cm.getModeAt(start);
  var startToken = mode.blockCommentStart;
  var endToken = mode.blockCommentEnd;
  if (startToken == null || endToken == null) {
    return null;
  }
  var line = start.line, lineText = cm.getLine(line);

  var startCh;
  for (var at = start.char, pass = 0;;) {
    var found = at <= 0 ? -1 : lineText.lastIndexOf(startToken, at - 1);
    if (found == -1) {
      if (pass == 1) {
        return null;
      }
      pass = 1;
      at = lineText.length;
      continue;
    }
    if (pass == 1 && found < start.char) {
      return null;
    }
    var pos = new Pos(line, found + 1);
    if (new RegExp(r'comment').hasMatch(cm.getTokenTypeAt(pos))) {
      startCh = found + startToken.length;
      break;
    }
    at = found - 1;
  }

  var depth = 1, lastLine = cm.lastLine(), end, endCh;
  outer: for (var i = line; i <= lastLine; ++i) {
    var text = cm.getLine(i);
    var pos = i == line ? startCh : 0;
    for (;;) {
      var nextOpen = text.indexOf(startToken, pos);
      var nextClose = text.indexOf(endToken, pos);
      if (nextOpen < 0) nextOpen = text.length;
      if (nextClose < 0) nextClose = text.length;
      pos = min(nextOpen, nextClose);
      if (pos == text.length) {
        break;
      }
      if (pos == nextOpen) ++depth;
      else if (!(--depth == 0)) {
        end = i; endCh = pos;
        break outer;
      }
      ++pos;
    }
  }
  if (end == null || line == end && endCh == startCh) {
    return null;
  } else {
    return new Reach(new Pos(line, startCh),  new Pos(end, endCh));
  }
}

