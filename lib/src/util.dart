// Copyright (c) 2015, the Comid Authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

part of comid;

class ClickTracker {
  static const MultiClickDuration = 400;

  DateTime clickTime;
  Pos clickLoc;

  ClickTracker(this.clickTime, this.clickLoc);

  bool isMultiClick(DateTime now, Pos loc) {
    if (cmp(loc, clickLoc) != 0) {
      return false;
    } else if (now.difference(clickTime).inMilliseconds > MultiClickDuration) {
      return false;
    }
    return true;
  }
}

// Create a new element whose type is specified by the given tag.
Element elt(String tag, [Object content, String className, String style]) {
  var element = document.createElement(tag);
  if (className != null) element.className = className;
  if (style != null) element.style.cssText = style;
  if (content != null) {
    if (content is String) {
      element.append(new Text(content));
    } else if (content is List) {
      for (var i = 0; i < content.length; ++i) {
        element.append(content[i] as Node);
      }
    }
  }
  return element;
}

DivElement eltdiv([Object content, String className, String style]) {
  return elt("div", content, className, style) as DivElement;
}

SpanElement eltspan([Object content, String className, String style]) {
  return elt("span", content, className, style) as SpanElement;
}

PreElement eltpre([Object content, String className, String style]) {
  return elt("pre", content, className, style) as PreElement;
}

ImageElement eltimg([Object content, String className, String style]) {
  return elt("img", content, className, style) as ImageElement;
}

html.Range range(node, start, end, [endNode]) {
  var r = document.createRange();
  r.setEnd(endNode == null ? node : endNode, end);
  r.setStart(node, start);
  return r;
}

// Remove all children from the element.
//Element removeChildren(Element element) {
//  for (var count = element.childNodes.length; count > 0; --count)
//    element.firstChild.remove();
//  return element;
//}
Element removeChildren(Element element) {
  var chiln = []..addAll(element.childNodes);
  for (var ch in chiln) {
    ch.remove();
  }
  return element;
}

// Remove all children from parent and add the new child element.
Node removeChildrenAndAdd(Element parent, Node element) {
  return removeChildren(parent).append(element);
}

// Returns true if parent is a container of some sort
// and child is contained by it.
bool contains(Element parent, Element child) {
  if (child.nodeType == 3) // Android browser always returns false when child is a textnode
    child = child.parentNode;
  if (_domElementDefinesContains(parent)) {
    return parent.contains(child);
  }
  while ((child = child.parentNode) != null) {
    if (child == parent) return true;
  }
  do {
    // TODO Possible problem when child is DocumentFragment, not ShadowRoot.
    if (child is ShadowRoot) child = (child as ShadowRoot).host;
    if (child == parent) return true;
  } while ((child = child.parentNode) != null);
  return false;
}

bool _domElementDefinesContains(Element elt) {
  return elt is Node;
}

// Return the active elememnt.
Element activeElt() {
  // Older versions of IE throws unspecified error when touching
  // document.activeElement in some cases (during loading, in iframe)
  //if (ie && ie_version < 11) activeElt = function() {
  try {
    return document.activeElement;
  } catch(e) {
    return document.body;
  }
}

var zwspSupported;
zeroWidthElement(Element measure) {
  if (zwspSupported == null) {
    var test = eltspan("\u200b");
    removeChildrenAndAdd(measure, eltspan([test, new Text("x")]));
    if ((measure.firstChild as Element).offsetHeight != 0) {
      zwspSupported = test.offsetWidth <= 1 && test.offsetHeight > 2;
    } else {
      zwspSupported = false;
    }
  }
  var node;
  if (zwspSupported) node = eltspan("\u200b");
  else node = eltspan("\u00a0", null,
      "display: inline-block; width: 1px; margin-right: -1px");
  node.setAttribute("cm-text", "");
  return node;
}

// Feature-detect IE's crummy client rect reporting for bidi text
bool _badBidiRects;
bool hasBadBidiRects(Element measure) {
  if (_badBidiRects != null) return _badBidiRects;
  var txt = removeChildrenAndAdd(measure, new Text("A\u062eA"));
  var r0 = range(txt, 0, 1).getBoundingClientRect();
  // Safari returns null in some cases (#2780)
  if (r0 == null || r0.left == r0.right) return false;
  var r1 = range(txt, 1, 2).getBoundingClientRect();
  return _badBidiRects = (r1.right - r0.right < 3);
}

bool hasSelection(te) {
  try { return te.selectionStart != te.selectionEnd; }
  catch(e) { return false; }
}

const bool hasCopyEvent = true;
//var hasCopyEvent = (function() {
//  var e = elt("div");
//  if ("oncopy" in e) return true;
//  e.setAttribute("oncopy", "return;");
//  return typeof e.oncopy == "function";
//})();

var _badZoomedRects = null;
hasBadZoomedRects(Element measure) {
  if (_badZoomedRects != null) return _badZoomedRects;
  var node = removeChildrenAndAdd(measure, eltspan("x"));
  var normal = node.getBoundingClientRect();
  var fromRange = range(node, 0, 1).getBoundingClientRect();
  return _badZoomedRects = (normal.left - fromRange.left).abs() > 1;
}

// A Pos instance represents a position within the text.
class Pos implements Comparable<Pos>{

  /*final*/ int line, char;

  Pos(this.line, [this.char]) {
    if (char == null) {
      char = 9999999; // Some large number > 50000, which is maxline length.
    }
  }

  // Compare two positions, return 0 if they are the same, a negative
  // number when a is less, and a positive number otherwise.
  int compareTo(Pos other) {
    int deltaLine = line - other.line;
    return deltaLine == 0 ? char - other.char : deltaLine;
  }
  Pos copy() {
    return new Pos(line, char);
  }
  Pos max(Pos other) {
    return compareTo(other) < 0 ? other : this;
  }
  Pos min(Pos other) {
    return compareTo(other) < 0 ? this : other;
  }
  Pos clipToLen(int linelen) {
    int ch = char;
    if (ch > linelen) return new Pos(line, linelen);
    else if (ch < 0) return new Pos(line, 0);
    else return this;
  }
  PosClipped clipped () => new PosClipped(line, char, true);
  bool get hitSide => false;
  String toString() => "Pos($line,$char)";
  bool operator == (other) {
    if (other is! Pos) return false;
    return other.line == line && other.char == char;
  }
  int get hashCode => line.hashCode + char.hashCode;
  bool get bad => false;
}

class PosClipped extends Pos {
  bool hitSide;

  PosClipped(int line, int char, [this.hitSide = false]) : super(line, char);
  String toString() => 'PosClipped($line, $char, hitSide: $hitSide)';
}

// Positions returned by coordsChar contain some extra information.
// xRel is the relative x position of the input coordinates compared
// to the found position (so xRel > 0 means the coordinates are to
// the right of the character position, for example). When outside
// is true, that means the coordinates lie outside the line's
// vertical range.
class PosWithInfo extends Pos {
  bool outside;
  int xRel;

  PosWithInfo(int line, int char, this.outside, this.xRel) : super(line, char);
  String toString() => 'PosWithInfo($line, $char, xRel: $xRel, outside: $outside)';
}

class LinePos {
  Line line;
  int char;

  LinePos(this.line, [this.char]) {
    if (char == null) {
      char = 9999999; // TODO Need a good constant for max line len.
    }
  }

  String toString() => 'LinePos($line, $char)';
}

// TODO Replace these with inline code and remove them.
int cmp(Pos a, Pos b) { return a.compareTo(b); }
Pos copyPos(Pos x) {return x.copy(); }
Pos maxPos(Pos a, Pos b) { return a.max(b); }
Pos minPos(Pos a, Pos b) { return a.min(b); }

// Selection objects are immutable. A new one is created every time
// the selection changes. A selection is one or more non-overlapping
// (and non-touching) ranges, sorted, and an integer that indicates
// which one is the primary selection (the one that's scrolled into
// view, that getCursor returns, etc).
class Selection implements HistoryItem {
  final List<Range> ranges;
  final int primIndex;

  Selection(this.ranges, this.primIndex);

  bool get isSelection => true;
  bool get copied => false;

  Range primary() {
    return ranges[primIndex];
  }
  bool equals(Object other) {
    if (other == this) return true;
    if (other is! Selection) return false; // Probably unnecessary.
    Selection o = other as Selection;
    if (o.primIndex != primIndex || o.ranges.length != ranges.length) {
      return false;
    }
    for (var i = 0; i < ranges.length; i++) {
      var here = this.ranges[i], there = o.ranges[i];
      if (cmp(here.anchor, there.anchor) != 0 ||
          cmp(here.head, there.head) != 0) {
        return false;
      }
    }
    return true;
  }
  Selection deepCopy() {
    List out = new List(ranges.length); // Fixed-length list is OK.
    for (int i = 0; i < ranges.length; i++)
      out[i] = new Range(ranges[i].anchor.copy(), ranges[i].head.copy());
    return new SelectionCopy(out, primIndex);
  }
  bool somethingSelected() {
    for (var i = 0; i < ranges.length; i++)
      if (!ranges[i].empty()) return true;
    return false;
  }
  // Return the index of the selection's range that contains the position(s).
  contains(Pos pos, [Pos end = null]) {
    if (end ==  null) end = pos;
    for (var i = 0; i < ranges.length; i++) {
      var range = ranges[i];
      if (cmp(end, range.from()) >= 0 && cmp(pos, range.to()) <= 0)
        return i;
    }
    return -1;
  }
}

class SelectionCopy extends Selection {
  SelectionCopy(ranges, primIndex) : super(ranges, primIndex);
  bool get copied => true;
}

// Give beforeSelectionChange handlers a change to influence a
// selection update. These objects are passed as event arguments.
// The selection ranges must be modified by creating a new list
// and giving it as the argument to update(). Modifying the Range
// objects will likely cause internal errors.
class SelectionUpdate {
  Document _doc;
  List<Range> _ranges;
  bool _wasUpdated;

  List<Range> get ranges => _ranges;
  bool get wasUpdated => _wasUpdated;

  SelectionUpdate(this._doc, this._ranges) {
    _wasUpdated = false;
    _ranges = new UnmodifiableListView(_ranges);
  }

  update(List<Range> ranges) {
    _ranges = [];
    for (var i = 0; i < ranges.length; i++) {
      _ranges.add(new Range(_doc.clipPos(ranges[i].anchor),
                            _doc.clipPos(ranges[i].head)));
    }
    _wasUpdated = true;
  }
}

class Range {
  final Pos anchor;
  final Pos head;
  int goalColumn; // TODO Try to eliminate this.

  Range(this.anchor, this.head);

  Pos from() {
    return minPos(this.anchor, this.head);
  }
  Pos to() {
    return maxPos(this.anchor, this.head);
  }
  bool empty() {
    return head.line == anchor.line && head.char == anchor.char;
  }
  String toString() => 'Range($anchor, $head)';
}

class Reach {
  Pos from, to;
  Reach(this.from, this.to);
  bool get cleared => false;
}

class ReachCleared extends Reach {
  ReachCleared(from, to) : super(from, to);
  bool get cleared => true;
}

class Padding {
  num left;
  num right;
  Padding(this.left, this.right);
  String toString() => 'Padding($left, $right)';
}

class Rect extends Loc {
  num right, bottom;
  bool bogus = false;
  num rtop, rbottom;
  Rect({left: 0, this.right: 0, top: 0, this.bottom: 0}) : super(top, left);
  String toString() => 'Rect({left: $left, right: $right, top: $top, bottom: $bottom})';
  get other => null;
}

class RectWithInfo extends Rect {
  var other;
  RectWithInfo(Rect rect, this.other) {
    left = rect.left; right = rect.right; top = rect.top; bottom = rect.bottom;
    bogus = rect.bogus; rtop = rect.rtop; rbottom = rect.rbottom;
  }
  String toString() => 'RectWithInfo({left: $left, right: $right, top: $top, bottom: $bottom})';
}

class DrawBox {
  Rect start, end;
  DrawBox(this.start, this.end);
}

class ScrollPos {
  int scrollTop, scrollLeft;
  String toString() => 'ScrollPos($scrollTop, $scrollLeft)';
}

// Take an unsorted, potentially overlapping set of ranges, and
// build a selection out of it. 'Consumes' ranges array (modifying
// it).
Selection normalizeSelection(List<Range> ranges, int primIndex) {
  var prim = ranges[primIndex];
  ranges.sort((a, b) { return cmp(a.from(), b.from()); });
  primIndex = ranges.indexOf(prim);
  for (var i = 1; i < ranges.length; i++) {
    Range cur = ranges[i], prev = ranges[i - 1];
    if (cmp(prev.to(), cur.from()) >= 0) {
      var from = minPos(prev.from(), cur.from()), to = maxPos(prev.to(), cur.to());
      var inv = prev.empty() ? cur.from() == cur.head : prev.from() == prev.head;
      if (i <= primIndex) --primIndex;
      ranges.removeAt(i);
      ranges[--i] = new Range(inv ? to : from, inv ? from : to);
    }
  }
  return new Selection(ranges, primIndex);
}

Selection simpleSelection(Pos anchor, [Pos head = null]) {
  return new Selection([new Range(anchor, head == null ? anchor : head)], 0);
}

// Counts the column offset in a string, taking tabs into account.
// Used mostly to find indentation.
int countColumn(String string, int end, int tabSize,
            [int startIndex = 0, int startValue = 0]) {
  if (end == null) {
    Match match = new RegExp(r'[^\s\u00a0]').firstMatch(string);
    if (match == null) {
      end = -1;
    } else {
      end = match.start;
    }
    if (end == -1) end = string.length;
  }
  for (var i = startIndex, n = startValue; ; ) {
    var nextTab = string.indexOf("\t", i);
    if (nextTab < 0 || nextTab >= end) {
      return n + (end - i);
    }
    n += nextTab - i;
    n += tabSize - (n % tabSize);
    i = nextTab + 1;
  }
  throw new StateError('countColumn() failed');
}

// The inverse of countColumn -- find the offset that corresponds to
// a particular column.
findColumn(String string, goal, tabSize) {
  for (var pos = 0, col = 0;;) {
    var nextTab = string.indexOf("\t", pos);
    if (nextTab == -1) nextTab = string.length;
    var skipped = nextTab - pos;
    if (nextTab == string.length || col + skipped >= goal)
      return pos + min(skipped, goal - col);
    col += nextTab - pos;
    col += tabSize - (col % tabSize);
    pos = nextTab + 1;
    if (col >= goal) return pos;
  }
}

// TODO Elminate lst()
dynamic lst(List arr) {
  int n = arr.length;
  return n == 0 ? null : arr[n-1];
}

List<String> _spaceStrs = [""];
String spaceStr(int n) {
  while (_spaceStrs.length <= n)
    _spaceStrs.add(_spaceStrs[_spaceStrs.length - 1] + " ");
  return _spaceStrs[n];
}

selectInput(TextAreaElement node) {
  if (ios) {
    // Mobile Safari apparently has a bug where select() is broken.
    // TODO See if this is fixed, since the problem was known in 2010
    node.selectionStart = 0; node.selectionEnd = node.value.length;
  } else {
    // Suppress mysterious IE10 errors by catching everything
    try {
      node.select();
    } catch(_e) {}
  }
}

var _nonASCIISingleCaseWordChar = new RegExp(r'[\u00df\u0587\u0590-\u05f4\u0600-\u06ff\u3040-\u309f\u30a0-\u30ff\u3400-\u4db5\u4e00-\u9fcc\uac00-\ud7af]');
var _simpleWordChar = new RegExp(r'\w');
_isWordCharBasic(String ch) {
  return _simpleWordChar.hasMatch(ch) || ch.codeUnitAt(0) > 0x80 &&
    (ch.toUpperCase() != ch.toLowerCase() ||
        _nonASCIISingleCaseWordChar.hasMatch(ch));
}
isWordChar(ch, [helper]) { // TODO Add isWordChar() to CodeMirror public API.
  if (ch.length == 0) return false;
  if (helper == null) return _isWordCharBasic(ch);
  if (helper.source.indexOf("\\w") > -1 && _isWordCharBasic(ch)) return true;
  return helper.test(ch);
}

const _x = const Object();

// TODO Dart does not have varargs so we hack it with this kludge.
// The only reason this exists is to simplify translation; it will be removed.
bind(f, [a1 = _x, a2 = _x, a3 = _x, a4 = _x, a5 = _x]) {
  if (a5 != _x) {
    return () => f(a1, a2, a3, a4, a5);
  } else if (a4 != _x) {
    return () => f(a1, a2, a3, a4);
  } else if (a3 != _x) {
    return () => f(a1, a2, a3);
  } else if (a2 != _x) {
    return () => f(a1, a2);
  } else if (a1 != _x) {
    return () => f(a1);
  } else {
    return () => f();
  }
}

RegExp classTest(cls) {
  return new RegExp(r"(^|\s)" + cls + r"(?:$|\s)\s*");
}
void rmClass(Element node, String cls) { // TODO Add to CodeMirror
  var current = node.className;
  var match = classTest(cls).firstMatch(current);
  if (match != null) {
    var end = match.end;
    var start = match.start;
    node.className = current.substring(0, start) + (start == 0 || end == current.length ? "" : " ") + current.substring(end);
  }
}
void addClass(Element node, String cls) { // TODO Add to CodeMirror
  var current = node.className;
  if (!classTest(cls).hasMatch(current)) node.className += (!current.isEmpty ? " " : "") + cls;
}
String joinClasses(String a, String b) {
  var as = a.split(" ");
  for (var i = 0; i < as.length; i++)
    if (as[i] != null && !classTest(as[i]).hasMatch(b)) b += " " + as[i];
  return b;
}

String getNodeData(Node node, String key) {
  return _getDataset(node)[key];
}
void setNodeData(Node node, String key, String value) {
  _getDataset(node)[key] = value;
}

_getDataset(Node node) {
  if (node is Element) {
    return node.dataset;
  } else {
    return node.parent.dataset;
  }
}
bool _isInsertLeft(Node node) {
  return _getDataset(node).containsKey('insertLeft');
}
void _doInsertLeft(Node node) {
  _getDataset(node)['insertLeft'] = "true";
}
bool _isIgnoreEvents(Element node) {
  return node.getAttribute("cm-ignore-events") == "true";
}
void _doIgnoreEvents(Element node) {
  node.setAttribute("cm-ignore-events", "true");
}
