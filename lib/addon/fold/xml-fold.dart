// Copyright (c) 2015, the Comid Authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library comid.mode.fold.xml;

import 'package:comid/codemirror.dart';

class _Iter {

  static const nameStartChar = "A-Z_a-z\\u00C0-\\u00D6\\u00D8-\\u00F6\\u00F8-\\u02FF\\u0370-\\u037D\\u037F-\\u1FFF\\u200C-\\u200D\\u2070-\\u218F\\u2C00-\\u2FEF\\u3001-\\uD7FF\\uF900-\\uFDCF\\uFDF0-\\uFFFD";
  static String nameChar = nameStartChar + "\-\:\.0-9\\u00B7\\u0300-\\u036F\\u203F-\\u2040";
  static RegExp xmlTagStart = new RegExp("<(/?)([" + nameStartChar + "][" + nameChar + "]*)"); // global

  CodeMirror cm;
  int line, ch;
  String text;
  int min, max;

  _Iter(this.cm, this.line, this.ch, [Span range]) {
    this.text = cm.getLine(line);
    this.min = range != null ? range.from : cm.firstLine();
    this.max = range != null ? range.to - 1 : cm.lastLine();
  }

  int cmp(Pos other) {
    int deltaLine = line - other.line;
    return deltaLine == 0 ? ch - other.char : deltaLine;
  }

  bool tagAt(int ch) {
    var type = cm.getTokenTypeAt(new Pos(line, ch));
    return type != null && new RegExp(r'\btag\b').hasMatch (type);
  }

  bool nextLine() {
    if (line >= max) return false;
    ch = 0;
    text = cm.getLine(++line);
    return true;
  }

  bool prevLine() {
    if (line <= min) return false;
    text = cm.getLine(--line);
    ch = text.length;
    return true;
  }

  String toTagEnd() {
    for (;;) {
      var gt = text.indexOf(">", ch);
      if (gt == -1) {
        if (nextLine()) {
          continue;
        } else {
          return null;
        }
      }
      if (!tagAt(gt + 1)) {
        ch = gt + 1;
        continue;
      }
      var lastSlash = text.lastIndexOf("/", gt);
      var selfClose = lastSlash > -1 &&
          !new RegExp(r'\S').hasMatch(text.substring(lastSlash + 1, gt));
      ch = gt + 1;
      return selfClose ? "selfClose" : "regular";
    }
  }

  Match toTagStart() {
    for (;;) {
      var lt = ch > 0 ? text.lastIndexOf("<", ch - 1) : -1;
      if (lt == -1) {
        if (prevLine()) {
          continue;
        } else {
          return null;
        }
      }
      if (!tagAt(lt + 1)) {
        ch = lt;
        continue;
      }
      ch = lt;
      var matches = xmlTagStart.allMatches(text, lt);
      if (matches.isEmpty) return null;
      var match = matches.first;
      if (match.start == lt) return match;
      return null;
    }
  }

  Match toNextTag() {
    for (;;) {
      var finds = xmlTagStart.allMatches(text, ch);
      if (finds.isEmpty) {
        if (nextLine()) {
          continue;
        } else {
          return null;
        }
      }
      var found = finds.first;
      if (!tagAt(found.start + 1)) {
        ch = found.start + 1;
        continue;
      }
      ch = found.start + found[0].length;
      return found;
    }
  }

  String toPrevTag() {
    for (;;) {
      var gt = ch > 0 ? text.lastIndexOf(">", ch - 1) : -1;
      if (gt == -1) {
        if (prevLine()) {
          continue;
        } else {
          return null;
        }
      }
      if (!tagAt(gt + 1)) {
        ch = gt;
        continue;
      }
      var lastSlash = text.lastIndexOf("/", gt);
      var selfClose = lastSlash > -1 &&
          !new RegExp(r'\S').hasMatch(text.substring(lastSlash + 1, gt));
      ch = gt + 1;
      return selfClose ? "selfClose" : "regular";
    }
  }

  TagSpan findMatchingClose([String tag]) {
    var stack = [];
    for (;;) {
      var next = toNextTag();
      String end;
      int startLine = line;
      int startCh = ch - (next != null ? next[0].length : 0);
      if (next == null || (end = toTagEnd()) == null) {
        return null;
      }
      if (end == "selfClose") {
        continue;
      }
      if (next[1]) { // closing tag
        var i;
        for (i = stack.length - 1; i >= 0; --i) {
          if (stack[i] == next[2]) {
            stack.length = i;
            break;
          }
        }
        if (i < 0 && (tag == null || tag == next[2])) {
          return new TagSpan(
            tag: next[2],
            from: new Pos(startLine, startCh),
            to: new Pos(line, ch)
          );
        }
      } else { // opening tag
        stack.add(next[2]);
      }
    }
  }

  TagSpan findMatchingOpen([String tag]) {
    var stack = [];
    for (;;) {
      var prev = toPrevTag();
      if (prev == null) {
        return null;
      }
      if (prev == "selfClose") {
        toTagStart();
        continue;
      }
      var endLine = line, endCh = ch;
      var start = toTagStart();
      if (start == null) {
        return null;
      }
      if (start[1] != null) { // closing tag
        stack.add(start[2]);
      } else { // opening tag
        var i;
        for (i = stack.length - 1; i >= 0; --i) {
          if (stack[i] == start[2]) {
            stack.length = i;
            break;
          }
        }
        if (i < 0 && (tag == null || tag == start[2])) {
          return new TagSpan(
            tag: start[2],
            from: new Pos(line, ch),
            to: new Pos(endLine, endCh)
          );
        }
      }
    }
  }
}

Reach foldXml(CodeMirror cm, Pos start) {
  var iter = new _Iter(cm, start.line, 0);
  for (;;) {
    var openTag = iter.toNextTag(), end;
    if (openTag == null || iter.line != start.line ||
        (end = iter.toTagEnd()) == null) {
      return null;
    }
    if (openTag[1] == null && end != "selfClose") {
      var start = new Pos(iter.line, iter.ch);
      var close = iter.findMatchingClose(openTag[2]);
      if (close != null) {
        return new Reach(start, close.from);
      } else {
        return null;
      }
    }
  }
}

findMatchingTag(CodeMirror cm, Pos pos, [Span range]) {
  var iter = new _Iter(cm, pos.line, pos.char, range);
  if (iter.text.indexOf(">") == -1 && iter.text.indexOf("<") == -1) {
    return null;
  }
  var end = iter.toTagEnd();
  var to = end == null ? null : new Pos(iter.line, iter.ch);
  var start = end == null ? null : iter.toTagStart();
  if (end == null || start == null || iter.cmp(pos) > 0) {
    return null;
  }
  var here = new TagSpan(from: new Pos(iter.line, iter.ch), to: to, tag: start[2]);
  if (end == "selfClose") {
    return new TagPair(open: here, close: null, at: "open");
  }

  if (start[1]) { // closing tag
    return new TagPair(open: iter.findMatchingOpen(start[2]), close: here, at: "close");
  } else { // opening tag
    iter = new _Iter(cm, to.line, to.ch, range);
    return new TagPair(open: here, close: iter.findMatchingClose(start[2]), at: "open");
  }
}

findEnclosingTag(CodeMirror cm, Pos pos, [Span range]) {
  var iter = new _Iter(cm, pos.line, pos.char, range);
  for (;;) {
    var open = iter.findMatchingOpen();
    if (open == null) break;
    var forward = new _Iter(cm, pos.line, pos.char, range);
    var close = forward.findMatchingClose(open.tag);
    if (close != null) {
      return new TagPair(open: open, close: close);
    } else {
      return null;
    }
  }
}

// Used by addon/edit/closetag.js
scanForClosingTag(CodeMirror cm, Pos pos, [String name, int end]) {
  var rng = end != null ? new Span(0, end) : null;
  var iter = new _Iter(cm, pos.line, pos.char, rng);
  return iter.findMatchingClose(name);
}

class TagSpan extends Reach {
  String tag;
  TagSpan({Pos from, Pos to, this.tag}) : super(from, to);
}

class TagPair {
  TagSpan open, close;
  String at;
  TagPair({this.open, this.close, this.at});
}

initialize() {
  CodeMirror.registerHelper("fold", "xml", foldXml);

  //CodeMirror.findMatchingTag = findMatchingTag;
  //CodeMirror.findEnclosingTag = findEnclosingTag;

  // Used by addon/edit/closetag.js
  //CodeMirror.scanForClosingTag = scanForClosingTag;
}
