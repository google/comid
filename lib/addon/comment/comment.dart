// Copyright (c) 2015, the Comid Authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library comid.comment;

import 'dart:math';
import 'package:comid/codemirror.dart';

initialize() {
  CodeMirror.defaultCommands['toggleComment'] = ([CodeMirror cm]) {
    if (cm == null) return;
    var minLine = double.INFINITY;
    var ranges = cm.listSelections();
    var mode = null;
    for (var i = ranges.length - 1; i >= 0; i--) {
      var from = ranges[i].from();
      var to = ranges[i].to();
      if (from.line >= minLine) continue;
      if (to.line >= minLine) to = new Pos(minLine.round(), 0);
      minLine = from.line;
      if (mode == null) {
        if (uncomment(cm, from, to)) {
          mode = "un";
        } else {
          lineComment(cm, from, to);
          mode = "line";
        }
      } else if (mode == "un") {
        uncomment(cm, from, to);
      } else {
        lineComment(cm, from, to);
      }
    }
  };

  CodeMirror.defineOption("continueComments", null, (CodeMirror cm, val, prev) {
    if (prev != null && prev != Options.Init)
      cm.removeKeyMap("continueComment");
    if (val != null) {
      String key = "Enter";
      if (val is String)
        key = val;
      else if (val is Map && val.containsKey('key'))
        key = val['key'];
      var map = {'name': "continueComment"};
      map[key] = continueComment;
      cm.addKeyMap(map);
    }
  });
}

//  CodeMirror.defineExtension("lineComment", function(from, to, options) {
void lineComment(CodeMirror cm, Pos from, Pos to, [Options options]) {
  if (options == null) options = _noOptions;
  var mode = cm.getModeAt(from);
  String commentString = _firstNotNull(options.lineComment, mode.lineComment);
  if (commentString == null) {
    if (_firstNotNull(options.blockCommentStart, mode.blockCommentStart) != null) {
      options['fullLines'] = true;
      blockComment(cm, from, to, options);
    }
    return;
  }
  var firstLine = cm.getLine(from.line);
  if (firstLine == null) return;
  var end = min(to.char != 0 || to.line == from.line ? to.line + 1 : to.line, cm.lastLine() + 1);
  String pad = options.padding == null ? " " : options.padding;
  bool blankLines = options.commentBlankLines == true || from.line == to.line;

  cm.operation(cm, () {
    if (options.indent == true) {
      var baseString = firstLine.substring(0, _firstNonWS(firstLine));
      for (var i = from.line; i < end; ++i) {
        var line = cm.getLine(i);
        var cut = baseString.length;
        if (!blankLines && !_nonWS.hasMatch(line)) continue;
        if (line.substring(0, min(cut, line.length)) != baseString) cut = _firstNonWS(line);
        cm.replaceRange(baseString + commentString + pad, new Pos(i, 0), new Pos(i, cut));
      }
    } else {
      for (var i = from.line; i < end; ++i) {
        if (blankLines || _nonWS.hasMatch(cm.getLine(i)))
          cm.replaceRange(commentString + pad, new Pos(i, 0));
      }
    }
  })();
}

//  CodeMirror.defineExtension("blockComment", function(cm, from, to, options) {
void blockComment(CodeMirror cm, Pos from, Pos to, [Options options]) {
  if (options == null) options = _noOptions;
  var mode = cm.getModeAt(from);
  String startString = _firstNotNull(options.blockCommentStart, mode.blockCommentStart);
  String endString = _firstNotNull(options.blockCommentEnd, mode.blockCommentEnd);
  if (startString == null || endString == null) {
    if ((_firstNotNull(options.lineComment, mode.lineComment) != null) && options.fullLines != false)
      lineComment(cm, from, to, options);
    return;
  }

  var end = min(to.line, cm.lastLine());
  if (end != from.line && to.char == 0 && _nonWS.hasMatch(cm.getLine(end))) --end;

  var pad = options.padding == null ? " " : options.padding;
  if (from.line > end) return;

  cm.operation(cm, () {
    if (options.fullLines != false) {
      var lastLineHasText = _nonWS.hasMatch(cm.getLine(end));
      cm.replaceRange(pad + endString, new Pos(end));
      cm.replaceRange(startString + pad, new Pos(from.line, 0));
      String lead = _firstNotNull(options.blockCommentLead, mode.blockCommentLead);
      if (lead != null) for (var i = from.line + 1; i <= end; ++i)
        if (i != end || lastLineHasText)
          cm.replaceRange(lead + pad, new Pos(i, 0));
    } else {
      cm.replaceRange(endString, to);
      cm.replaceRange(startString, from);
    }
  })();
}

//  CodeMirror.defineExtension("uncomment", function(from, to, options) {
bool uncomment(CodeMirror cm, Pos from, Pos to, [Options options]) {
  if (options == null) options = _noOptions;
  var mode = cm.getModeAt(from);
  var end = min(to.char != 0 || to.line == from.line ? to.line : to.line - 1, cm.lastLine());
  var start = min(from.line, end);

  // Try finding line comments
  var lineString = _firstNotNull(options.lineComment, mode.lineComment);
  var lines = [];
  var pad = options.padding == null ? " " : options.padding;
  bool didSomething = false;
  lineComment: {
    if (lineString == null) break lineComment;
    for (var i = start; i <= end; ++i) {
      var line = cm.getLine(i);
      var found = line.indexOf(lineString);
      if (found > -1 && !(new RegExp('comment').hasMatch(cm.getTokenTypeAt(new Pos(i, found + 1))))) {
        found = -1;
      }
      if (found == -1 && (i != end || i == start) && _nonWS.hasMatch(line)) {
        break lineComment;
      }
      if (found > -1 && _nonWS.hasMatch(line.substring(0, found))) {
        break lineComment;
      }
      lines.add(line);
    }
    cm.operation(cm, () {
      for (var i = start; i <= end; ++i) {
        String line = lines[i - start];
        var pos = line.indexOf(lineString), endPos = pos + lineString.length;
        if (pos < 0) continue;
        if (line.substring(endPos, endPos + pad.length) == pad) endPos += pad.length;
        didSomething = true;
        cm.replaceRange("", new Pos(i, pos), new Pos(i, endPos));
      }
    })();
    if (didSomething) {
      return true;
    }
  }

  // Try block comments
  String startString = _firstNotNull(options.blockCommentStart, mode.blockCommentStart);
  String endString = _firstNotNull(options.blockCommentEnd, mode.blockCommentEnd);
  if (startString == null || endString == null) {
    return false;
  }
  String lead = _firstNotNull(options.blockCommentLead, mode.blockCommentLead);
  var startLine = cm.getLine(start);
  var endLine = end == start ? startLine : cm.getLine(end);
  var open = startLine.indexOf(startString);
  var close = endLine.lastIndexOf(endString);
  if (close == -1 && start != end) {
    endLine = cm.getLine(--end);
    close = endLine.lastIndexOf(endString);
  }
  if (open == -1 || close == -1 ||
      !(new RegExp('comment').hasMatch(cm.getTokenTypeAt(new Pos(start, open + 1)))) ||
      !(new RegExp('comment').hasMatch(cm.getTokenTypeAt(new Pos(end, close + 1)))))
    return false;

  // Avoid killing block comments completely outside the selection.
  // Positions of the last startString before the start of the selection, and the first endString after it.
  var lastStart = startLine.lastIndexOf(startString, from.char);
  var ls;
  var firstEnd = lastStart == -1
      ? -1 : (ls = startLine.substring(0, from.char)).indexOf(endString, min(ls.length, lastStart + startString.length));
  if (lastStart != -1 && firstEnd != -1 && firstEnd + endString.length != from.char) {
    return false;
  }
  // Positions of the first endString after the end of the selection, and the last startString before it.
  firstEnd = endLine.indexOf(endString, to.char);
  var almostLastStart = endLine.substring(to.char).lastIndexOf(startString, max(0, firstEnd - to.char));
  lastStart = (firstEnd == -1 || almostLastStart == -1)
      ? -1 : to.char + almostLastStart;
  if (firstEnd != -1 && lastStart != -1 && lastStart != to.char) {
    return false;
  }

  cm.operation(cm, () {
    cm.replaceRange("",
        new Pos(end, close - (pad != null && endLine.substring(close - pad.length, close) == pad ? pad.length : 0)),
        new Pos(end, close + endString.length));
    var openEnd = open + startString.length;
    if (pad != null && startLine.substring(openEnd, openEnd + pad.length) == pad) {
      openEnd += pad.length;
    }
    cm.replaceRange("", new Pos(start, open), new Pos(start, openEnd));
    if (lead != null) {
      for (var i = start + 1; i <= end; ++i) {
        var line = cm.getLine(i), found = line.indexOf(lead);
        if (found == -1 || _nonWS.hasMatch(line.substring(0, found))) {
          continue;
        }
        var foundEnd = found + lead.length;
        if (pad != null && line.substring(foundEnd, foundEnd + pad.length) == pad) {
          foundEnd += pad.length;
        }
        cm.replaceRange("", new Pos(i, found), new Pos(i, foundEnd));
      }
    }
  })();
  return true;
}

Options _noOptions = new Options();
RegExp _nonWS = new RegExp(r'[^\s\u00a0]');

int _firstNonWS(String str) {
  var found = str.indexOf(_nonWS);
  return found == -1 ? 0 : found;
}

String _firstNotNull(String a, String b) => a == null ? b : a;

continueComment([CodeMirror cm]) {
  if (cm == null) return Pass;
  if (cm.getOption("disableInput")) return Pass;
  var ranges = cm.listSelections();
  Mode mode;
  var inserts = [];
  for (var i = 0; i < ranges.length; i++) {
    var pos = ranges[i].head;
    var token = cm.getTokenAt(pos);
    if (token.type != "comment") return Pass;
    var modeHere = cm.innerMode(cm.doc.getMode(), token.state).mode;
    if (mode == null) mode = modeHere;
    else if (mode != modeHere) return Pass;

    String insert = null;
    if (mode.blockCommentStart != null && mode.blockCommentContinue != null) {
      var end = token.string.indexOf(mode.blockCommentEnd);
      var full = cm.getRange(new Pos(pos.line, 0), new Pos(pos.line, token.end)), found;
      if (end != -1 && end == token.string.length - mode.blockCommentEnd.length && pos.char >= end) {
        // Comment ended, don't continue it
      } else if (token.string.indexOf(mode.blockCommentStart) == 0) {
        insert = full.substring(0, token.start);
        if (!new RegExp(r'^\s*$').hasMatch(insert)) {
          insert = "";
          for (var j = 0; j < token.start; ++j) insert += " ";
        }
      } else if ((found = full.indexOf(mode.blockCommentContinue)) != -1 &&
                 found + mode.blockCommentContinue.length > token.start &&
                 new RegExp(r'^\s*$').hasMatch(full.substring(0, found))) {
        insert = full.substring(0, found);
      }
      if (insert != null) insert += mode.blockCommentContinue;
    }
    if (insert == null && mode.lineComment != null && _continueLineCommentEnabled(cm)) {
      var line = cm.getLine(pos.line);
      var found = line.indexOf(mode.lineComment);
      if (found > -1) {
        insert = line.substring(0, found);
        if (new RegExp(r'\S').hasMatch(insert)) insert = null;
        else insert += mode.lineComment + new RegExp(r'^\s*').firstMatch(line.substring(found + mode.lineComment.length))[0];
      }
    }
    if (insert == null) return Pass;
    inserts.add("\n" + insert);
  }

  cm.operation(cm, () {
    for (var i = ranges.length - 1; i >= 0; i--)
      cm.replaceRange(inserts[i], ranges[i].from(), ranges[i].to(), "+insert");
  })();
}

bool _continueLineCommentEnabled(cm) {
  var opt = cm.getOption("continueComments");
  if (opt is Map)
    return opt['continueLineComment'] != false;
  return true;
}
