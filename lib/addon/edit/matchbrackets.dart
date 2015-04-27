// Copyright (c) 2015, the Comid Authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library comid.matchbrackets;

import 'dart:math';
import 'package:comid/codemirror.dart';

var matching = {"(": ")>", ")": "(<", "[": "]>", "]": "[<", "{": "}>", "}": "{<"};

findMatchingBracket(CodeMirror cm, Pos where, bool strict, MatchLimits config) {
  var line = cm.getLineHandle(where.line);
  var pos = where.char - 1;
  String match = pos >= 0 && pos < line.text.length
      ? matching[line.text.substring(pos, pos + 1)]
      : null;
  if (match == null && ++pos < line.text.length) {
    match = matching[line.text.substring(pos, pos + 1)];
  }
  if (match == null) return null;
  var dir = match.endsWith(">") ? 1 : -1;
  if (strict && (dir > 0) != (pos == where.char)) return null;
  var style = cm.getTokenTypeAt(new Pos(where.line, pos + 1));

  var found = scanForBracket(cm, new Pos(where.line, pos + (dir > 0 ? 1 : 0)),
      dir, style, config);
  if (found == false) return null;
  return new BracketMatch(
    new Pos(where.line, pos),
    found != null ? found['pos'] : null,
    found != null ? found['ch'] == match.substring(0,1) : false,
    dir > 0
  );
}

// bracketRegex is used to specify which type of bracket to scan
// should be a regexp, e.g. /[[\]]/
//
// Note: If "where" is on an open bracket, then this bracket is ignored.
//
// Returns false when no bracket was found, null when it reached
// maxScanLines and gave up
scanForBracket(CodeMirror cm, Pos where, int dir, [String style, MatchLimits config]) {
  int maxScanLen = config.maxScanLineLength;
  int maxScanLines = config.maxScanLines;

  var stack = [];
  RegExp re = config.bracketRegexp;
  var lineEnd = dir > 0 ? min(where.line + maxScanLines, cm.lastLine() + 1)
                        : max(cm.firstLine() - 1, where.line - maxScanLines);
  var lineNo;
  for (lineNo = where.line; lineNo != lineEnd; lineNo += dir) {
    var line = cm.getLine(lineNo);
    if (line == null) continue;
    var pos = dir > 0 ? 0 : line.length - 1, end = dir > 0 ? line.length : -1;
    if (line.length > maxScanLen) continue;
    if (lineNo == where.line) pos = where.char - (dir < 0 ? 1 : 0);
    for (; pos != end; pos += dir) {
      var ch = line.substring(pos, pos + 1);
      if (re.hasMatch(ch) &&
          (style == null ||
            cm.getTokenTypeAt(new Pos(lineNo, pos + 1)) == style)) {
        String match = matching[ch];
        if ((match.endsWith(">")) == (dir > 0)) stack.add(ch);
        else if (stack.length == 0) {
          return {'pos': new Pos(lineNo, pos), 'ch': ch};
        } else {
          stack.removeLast();
        }
      }
    }
  }
  return lineNo - dir == (dir > 0 ? cm.lastLine() : cm.firstLine())
      ? false : null;
}

matchBrackets(CodeMirror cm, bool autoclear, MatchLimits config) {
  // Disable brace matching in long lines, since it'll cause hugely slow updates
  int maxHighlightLen = 1000;
  if (cm.state.matchBrackets != null) {
    int n = cm.state.matchBrackets.maxHighlightLineLength;
    if (n != null) maxHighlightLen = n;
  }
  var marks = [], ranges = cm.listSelections();
  for (var i = 0; i < ranges.length; i++) {
    BracketMatch match = ranges[i].empty()
        ? findMatchingBracket(cm, ranges[i].head, false, config) : null;
    if (match != null && cm.getLine(match.from.line).length <= maxHighlightLen) {
      var style = match.match
          ? "CodeMirror-matchingbracket" : "CodeMirror-nonmatchingbracket";
      var loc = new Pos(match.from.line, match.from.char + 1);
      marks.add(cm.markText(match.from, loc, className: style));
      if (match.to != null &&
          cm.getLine(match.to.line).length <= maxHighlightLen) {
        loc = new Pos(match.to.line, match.to.char + 1);
        marks.add(cm.markText(match.to, loc, className: style));
      }
    }
  }

  if (marks.length > 0) {
    var clear = () {
      cm.operation(cm, () {
        for (var i = 0; i < marks.length; i++) marks[i].clear();
      })();
    };
    if (autoclear) setTimeout(clear, 800);
    else return clear;
  }
}

var _currentlyHighlighted = null;
doMatchBrackets(CodeMirror cm) {
  cm.operation(cm, () {
    if (_currentlyHighlighted != null) {
      _currentlyHighlighted();
      _currentlyHighlighted = null;
    }
    _currentlyHighlighted = matchBrackets(cm, false, cm.state.matchBrackets);
  })();
}

bool _isInitialized = false;
initializeBracketMatching() {
  if (_isInitialized) return;
  _isInitialized = true;
  CodeMirror.defineOption("matchBrackets", false,
      (CodeMirror cm, bool val, var old) {
        if (old == true)
          cm.off(cm, "cursorActivity", doMatchBrackets);
        if (val == true) {
          cm.state.matchBrackets = val is MatchLimits ? val : new MatchLimits();
          cm.on(cm, "cursorActivity", doMatchBrackets);
        }
  });

//  CodeMirror.defineExtension("matchBrackets", function() {matchBrackets(this, true);});
//  CodeMirror.defineExtension("findMatchingBracket", function(pos, strict, config){
//    return findMatchingBracket(this, pos, strict, config);
//  });
//  CodeMirror.defineExtension("scanForBracket", function(pos, dir, style, config){
//    return scanForBracket(this, pos, dir, style, config);
//  });
}

class BracketMatch {
  Pos from, to;
  bool match, forward;

  BracketMatch(this.from, this.to, this.match, this.forward);
}

class MatchLimits {
  int maxScanLineLength;
  int maxScanLines;
  int maxHighlightLineLength;
  RegExp bracketRegexp;

  MatchLimits({this.maxScanLineLength: 10000, this.maxScanLines: 1000,
    this.maxHighlightLineLength: 1000, this.bracketRegexp}) {
    if (bracketRegexp == null) bracketRegexp = new RegExp(r'[(){}[\]]');
  }
}
