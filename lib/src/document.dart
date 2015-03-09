// Copyright (c) 2015, the Comid Authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

part of comid;

// By default, updates that start and end at the beginning of a line
// are treated specially, in order to make the association of line
// widgets and marker elements with the text behave more intuitive.
isWholeLineUpdate(Document doc, change) {
  return change.from.char == 0 && change.to.char == 0 && lst(change.text) == "" &&
    (doc.cm == null || doc.cm.options.wholeLineUpdateBefore);
}

// Perform a change on the document data structure.
updateDoc(Document doc, Change change,
          [List<List<MarkedSpan>> markedSpans, Function estimateHeight]) {
  var from = change.from, to = change.to, text = change.text;

  List<MarkedSpan> spansFor(int n) {
    return markedSpans != null ? markedSpans[n] : null;
  }
  void update(Line line, String text, List<MarkedSpan> spans) {
    line.updateLine(text, spans, estimateHeight);
    doc.signalLater(line, "change", line, change);
  }
  List<Line> linesFor(int start, int end) {
    var result = [];
    for (var i = start; i < end; ++i)
      result.add(new Line(text[i], spansFor(i), estimateHeight));
    return result;
  }

  var firstLine = doc._getLine(from.line), lastLine = doc._getLine(to.line);
  String lastText = lst(text);
  var lastSpans = spansFor(text.length - 1);
  var nlines = to.line - from.line;

  // Adjust the line structure
  if (change.full) {
    doc.insert(0, linesFor(0, text.length));
    doc.remove(text.length, doc.size - text.length);
  } else if (isWholeLineUpdate(doc, change)) {
    // This is a whole-line replace. Treated specially to make
    // sure line objects move the way they are supposed to.
    List<Line> added = linesFor(0, text.length - 1);
    update(lastLine, lastLine.text, lastSpans);
    if (nlines > 0) doc.remove(from.line, nlines);
    if (added.length > 0) doc.insert(from.line, added);
  } else if (firstLine == lastLine) {
    if (text.length == 1) {
      update(firstLine,
          firstLine.text.substring(0, from.char) + lastText +
              firstLine.text.substring(to.char),
          lastSpans);
    } else {
      List<Line> added = linesFor(1, text.length - 1);
      added.add(new Line(lastText + firstLine.text.substring(to.char), lastSpans,
          estimateHeight));
      update(firstLine, firstLine.text.substring(0, from.char) + text[0], spansFor(0));
      doc.insert(from.line + 1, added);
    }
  } else if (text.length == 1) {
    update(firstLine,
        firstLine.text.substring(0, from.char) + text[0] + lastLine.text.substring(to.char),
        spansFor(0));
    doc.remove(from.line + 1, nlines);
  } else {
    update(firstLine, firstLine.text.substring(0, from.char) + text[0], spansFor(0));
    update(lastLine, lastText + lastLine.text.substring(to.char), lastSpans);
    List<Line> added = linesFor(1, text.length - 1);
    if (nlines > 1) doc.remove(from.line + 1, nlines - 1);
    doc.insert(from.line + 1, added);
  }

  if (doc.cm != null) doc.cm.signalLater(doc, "change", doc, change);
}

// The document is represented as a BTree consisting of leaves, with
// chunk of lines in them, and branches, with up to ten leaves or
// other branch nodes below them. The top node is always a branch
// node, and is the document object itself (meaning it has
// additional methods and properties).
//
// All nodes have parent links. The tree is used both to go from
// line numbers to line objects, and to go from objects to numbers.
// It also indexes by height, and is used to convert between height
// and line object, and to find the total height of the document.
//
// See also http://marijnhaverbeke.nl/blog/codemirror-line-tree.html
abstract class BtreeChunk {
  num height;
  int first;
  BranchChunk get parent;
  void set parent(p);
  List<BtreeChunk> get children => null;
  List<Line> get lines => null;
  int chunkSize();
  bool get isLeaf => false;
  void collapse(lines);

  Document doc() {
    BtreeChunk node = this;
    while (node is! Document) node = node.parent;
    return node;
  }
}

class LeafChunk extends BtreeChunk with EventManager {
  List<Line> lines;
  BranchChunk parent;

  OperationGroup get operationGroup => doc().operationGroup;

  LeafChunk(this.lines) {
    num h = 0;
    for (var i = 0; i < lines.length; ++i) {
      lines[i].parent = this;
      h += lines[i].height;
    }
    height = h;
  }

  bool get isLeaf => true;

  int chunkSize() {
    return lines.length;
  }
  // Remove the n lines at offset 'at'.
  removeInner(at, n) {
    int end = at + n;
    for (var i = at; i < end; ++i) {
      var line = lines[i];
      height -= line.height;
      // Swapped next two lines so single gets queued before parent is null'd
      signalLater(line, "delete");
      line.cleanUpLine();
    }
//    lines.splice(at, n);
    lines.removeRange(at, end);
  }
  // Helper used to collapse a small branch into a single leaf.
  void collapse(lines) {
    lines.addAll(this.lines);
  }
  // Insert the given array of lines at offset 'at', count them as
  // having the given height.
  insertInner(int at, List lines, num height) {
    this.height += height;
    this.lines.insertAll(at, lines);
    for (var i = 0; i < lines.length; ++i) {
      lines[i].parent = this;
    }
  }
  // Used to iterate over a part of the tree.
  bool iterN(int at, int n, LineFn op) {
    for (var e = at + n; at < e; ++at) {
      if (op(lines[at]) != null) return true;
    }
    return false;
  }
}

class BranchChunk extends BtreeChunk {
  BranchChunk parent;
  List<BtreeChunk> children;
  int size;

  BranchChunk(this.children) {
    int size = 0;
    num height = 0;
    for (var i = 0; i < children.length; ++i) {
      var ch = children[i];
      size += ch.chunkSize();
      height += ch.height;
      ch.parent = this;
    }
    this.size = size;
    this.height = height.round();
    this.parent = null;
  }

  int chunkSize() {
    return size;
  }
  void removeInner(int at, int n) {
    size -= n;
    for (var i = 0; i < children.length; ++i) {
      var child = children[i];
      int sz = child.chunkSize();
      if (at < sz) {
        var rm = min(n, sz - at), oldHeight = child.height;
        child.removeInner(at, rm);
        height -= oldHeight - child.height;
        if (sz == rm) {
          children.removeAt(i--);
          child.parent = null;
        }
        if ((n -= rm) == 0) break;
        at = 0;
      } else at -= sz;
    }
    // If the result is smaller than 25 lines, ensure that it is a
    // single leaf node.
    if (size - n < 25 &&
        (children.length > 1 || !(children.length == 1 && children[0] is LeafChunk))) {
      var lines = [];
      collapse(lines);
      children = [new LeafChunk(lines)];
      children[0].parent = this;
    }
  }
  void collapse(lines) {
    for (var i = 0; i < children.length; ++i) {
      children[i].collapse(lines);
    }
  }
  insertInner(int at, lines, height) {
    this.size += lines.length;
    this.height += height;
    for (var i = 0; i < children.length; ++i) {
      var child = children[i];
      int sz = child.chunkSize();
      if (at <= sz) {
        child.insertInner(at, lines, height);
        if (child.lines != null && child.lines.length > 50) {
          while (child.lines.length > 50) {
            var spilled = child.lines.sublist(child.lines.length - 25);
            child.lines.removeRange(child.lines.length - 25, child.lines.length);
            var newleaf = new LeafChunk(spilled);
            child.height -= newleaf.height;
            children.insert(i + 1, newleaf);
            newleaf.parent = this;
          }
          maybeSpill();
        }
        break;
      }
      at -= sz;
    }
  }
  // When a node has grown, check whether it should be split.
  maybeSpill() {
    if (children.length <= 10) return;
    var me = this;
    do {
      var spilled = me.children.sublist(me.children.length - 5, me.children.length);
      me.children.removeRange(me.children.length - 5, me.children.length);
      var sibling = new BranchChunk(spilled);
      if (me.parent == null) { // Become the parent node
        var copy = new BranchChunk(me.children);
        copy.parent = me;
        me.children = [copy, sibling];
        me = copy;
      } else {
        me.size -= sibling.size;
        me.height -= sibling.height;
        var myIndex = me.parent.children.indexOf(me);
        me.parent.children.insert(myIndex + 1, sibling);
      }
      sibling.parent = me.parent;
    } while (me.children.length > 10);
    me.parent.maybeSpill();
  }
  iterN(int at, int n, LineFn op) {
    for (var i = 0; i < children.length; ++i) {
      var child = children[i], sz = child.chunkSize();
      if (at < sz) {
        var used = min(n, sz - at);
        if (child.iterN(at, used, op)) return true;
        if ((n -= used) == 0) break;
        at = 0;
      } else at -= sz;
    }
    return false;
  }
}

// Line objects. These hold state related to a line, including
// highlighting info (the styles array).
class Line extends Object with EventManager implements LineHandle {
  String text;
  num height;
  LeafChunk parent;
  List styles;
  var styleClasses;
  var stateAfter;
  var order;
  Map gutterMarkers;
  List<MarkedSpan> markedSpans;
  List<LineWidget> widgets;
  Map<String,String> lineClasses;

  Line(String text, [List<MarkedSpan> markedSpans, Function estimateHeight]) {
    this.text = text;
    attachMarkedSpans(markedSpans);
    this.height = estimateHeight != null ? estimateHeight(this) : 1;
  }

  OperationGroup get operationGroup => parent.operationGroup;

  String get textClass => this['textClass'];
  String get bgClass => this['bgClass'];
  String get wrapClass => this['wrapClass'];
  String get gutterClass => this['gutterClass'];

  String operator [](String x) => lineClasses == null ? null : lineClasses[x];
  void operator []= (String x, String y) {
    if (lineClasses == null) lineClasses = {};
    if (y == null) {
      lineClasses.remove(x);
      if (lineClasses.isEmpty) lineClasses = null;
    } else {
      if (y.isEmpty) {
        this[x] = null;
      } else {
        lineClasses[x] = y;
      }
    }
  }

  // Given a line object, find its line number by walking up through
  // its parent links.
  int lineNo() {
    LeafChunk leaf = parent;
    if (leaf == null) return -1;
    BtreeChunk cur = leaf;
    int no = leaf.lines.indexOf(this);
    BranchChunk chunk;
    for (chunk = cur.parent; chunk != null; cur = chunk, chunk = chunk.parent) {
     for (var i = 0;; ++i) {
       if (chunk.children[i] == cur) break;
       no += chunk.children[i].chunkSize();
     }
    }
    return no + cur.first;
  }

   // Compute the character length of a line, taking into account
  // collapsed ranges (see markText) that might hide parts, and join
  // other lines onto it.
  int lineLength() {
    if (height == 0) return 0;
    var len = text.length, merged, cur = this;
    while ((merged = cur.collapsedSpanAtStart()) != null) {
      var found = merged.find(0, true);
      cur = found.from.line;
      len += found.from.char - found.to.char;
    }
    cur = this;
    while ((merged = cur.collapsedSpanAtEnd()) != null) {
      var found = merged.find(0, true);
      len -= cur.text.length - found.from.char;
      cur = found.to.line;
      len += cur.text.length - found.to.char;
    }
    return len;
  }

  // Change the content (text, markers) of a line. Automatically
  // invalidates cached information and tries to re-estimate the
  // line's height.
  void updateLine(String text, List<MarkedSpan> markedSpans, [Function htFn]) {
    this.text = text;
    if (stateAfter != null) stateAfter = null;
    if (styles != null) styles = null;
    if (order != null) order = null;
    detachMarkedSpans();
    attachMarkedSpans(markedSpans);
    var estHeight = htFn != null ? htFn(this) : 1;
    if (estHeight != height) updateLineHeight(estHeight);
  }

  // Detach a line from the document tree and its markers.
  void cleanUpLine() {
    parent = null;
    detachMarkedSpans();
  }

  // Connect or disconnect spans from a line.
  void detachMarkedSpans() {
    var spans = markedSpans;
    if (spans == null) return;
    for (var i = 0; i < spans.length; ++i)
      spans[i].marker.detachLine(this);
    markedSpans = null;
  }
  void attachMarkedSpans(List<MarkedSpan> spans) {
    if (spans == null || spans.isEmpty) return;
    for (var i = 0; i < spans.length; ++i)
      spans[i].marker.attachLine(this);
    markedSpans = spans;
  }

  // Helpers used when computing which overlapping collapsed span
  // counts as the larger one.
  static int extraLeft(TextMarker marker) { return marker.inclusiveLeft ? -1 : 0; }
  static int extraRight(TextMarker marker) { return marker.inclusiveRight ? 1 : 0; }

  // Returns a number indicating which of two overlapping collapsed
  // spans is larger (and thus includes the other). Falls back to
  // comparing ids when the spans cover exactly the same range.
  static int compareCollapsedMarkers(TextMarker a, TextMarker b) {
    var lenDiff = a.lines.length - b.lines.length;
    if (lenDiff != 0) return lenDiff;
    Span aPos = a.find(), bPos = b.find();
    var fromCmp = cmp(aPos.from, bPos.from);
    if (fromCmp == 0) fromCmp = extraLeft(a) - extraLeft(b);
    if (fromCmp != 0) return -fromCmp;
    var toCmp = cmp(aPos.to, bPos.to);
    if (toCmp == 0) toCmp = extraRight(a) - extraRight(b);
    if (toCmp != 0) return toCmp;
    return b.id - a.id;
  }

  // Find out whether a line ends or starts in a collapsed span. If
  // so, return the marker for that span.
  TextMarker collapsedSpanAtSide(bool start) {
    if (!sawCollapsedSpans) return null;
    var sps = markedSpans;
    TextMarker found;
    if (sps != null) {
      for (var sp, i = 0; i < sps.length; ++i) {
        sp = sps[i];
        if (sp.marker.collapsed && (start ? sp.from : sp.to) == null &&
            (found == null || compareCollapsedMarkers(found, sp.marker) < 0)) {
          found = sp.marker;
        }
      }
    }
    return found;
  }
  TextMarker collapsedSpanAtStart() { return collapsedSpanAtSide(true); }
  TextMarker collapsedSpanAtEnd() { return collapsedSpanAtSide(false); }

  // A visual line is a line as drawn on the screen. Folding, for
  // example, can cause multiple logical lines to appear on the same
  // visual line. This finds the start of the visual line that the
  // given line is part of (usually that is the line itself).
  Line visualLine() {
    TextMarker merged;
    var line = this;
    while ((merged = line.collapsedSpanAtStart()) != null)
      line = merged.find(-1, true).line;
    return line;
  }

  // Returns an array of logical lines that continue the visual line
  // started by the argument, or undefined if there are no such lines.
  List<Line> visualLineContinued() {
    var merged, lines = [];
    var line = this;
    while ((merged = line.collapsedSpanAtEnd()) != null) {
      line = merged.find(1, true).line;
      lines.add(line);
    }
    return lines.isEmpty ? null : lines;
  }

  // Compute whether a line is hidden. Lines count as hidden when they
  // are part of a visual line that starts with another line, or when
  // they are entirely covered by collapsed, non-widget span.
  bool isHidden() {
    if (!sawCollapsedSpans) return false;
    var sps = markedSpans;
    if (sps != null) {
      for (var sp, i = 0; i < sps.length; ++i) {
        sp = sps[i];
        if (!sp.marker.collapsed) continue;
        if (sp.from == null) return true;
        if (sp.marker.widgetNode != null) continue;
        if (sp.from == 0 && sp.marker.inclusiveLeft && _isHiddenInner(sp)) {
          return true;
        }
      }
    }
    return false;
  }
  bool _isHiddenInner(MarkedSpan span) {
    if (span.to == null) {
      var end = span.marker.find(1, true);
      var spans = span.marker.getMarkedSpanFor(end.line.markedSpans);
      return end.line._isHiddenInner(spans);
    }
    if (span.marker.inclusiveRight && span.to == text.length)
      return true;
    for (var sp, i = 0; i < markedSpans.length; ++i) {
      sp = markedSpans[i];
      if (sp.marker.collapsed && sp.marker.widgetNode == null &&
          sp.from == span.to &&
          (sp.to == null || sp.to != span.from) &&
          (sp.marker.inclusiveLeft || span.marker.inclusiveRight) &&
          _isHiddenInner(sp)) {
        return true;
      }
    }
    return false;
  }

  // Remove a span from an array, returning undefined if no spans are
  // left (we don't store arrays for lines without spans).
  List<MarkedSpan> removeMarkedSpan(span) {
    var r = [];
    for (var i = 0; i < markedSpans.length; ++i)
      if (markedSpans[i] != span) r.add(markedSpans[i]);
    return r.isEmpty ? null : r;
  }

  // Add a span to a line.
  void addMarkedSpan(MarkedSpan span) {
    if (markedSpans == null) {
      markedSpans = [];
    }
    markedSpans.add(span);
    span.marker.attachLine(this);
  }

  // Update the height of a line, propagating the height change
  // upwards to parent nodes.
  void updateLineHeight(num height) {
    num diff = height - this.height;
    this.height = height;
    if (diff != 0) {
      for (BtreeChunk n = this.parent; n != null; n = n.parent) {
        n.height += diff;
      }
    }
  }

}

class Document extends BranchChunk with EventManager implements Doc {
  static int nextDocId = 0;
  CodeEditor cm;
  String content;
  Options options;
  int first;
  Mode mode;
  var modeOption;
  Selection sel;
  num scrollTop;
  int scrollLeft;
  bool cantEdit;
  int cleanGeneration;
  int frontier;
  History history;
  int id;
  var bidiOther;
  bool extend;
  List<DocumentLink> linked;

  BranchChunk get parent => null;

  Document(text, mode, [int firstLine = 0]) :
      super([new LeafChunk([new Line("", null)])]) {
    //BranchChunk.call(this, [new LeafChunk([new Line("", null)])]);
    this.first = firstLine;
    this.scrollTop = this.scrollLeft = 0;
    this.cantEdit = false;
    this.cleanGeneration = 1;
    this.frontier = firstLine;
    var start = new Pos(firstLine, 0);
    this.sel = simpleSelection(start);
    this.history = new History(null);
    this.id = ++nextDocId;
    this.modeOption = mode;
    this.extend = false;

    if (text is String) text = splitLines(text);
    updateDoc(this, new Change(start, start, text));
    _setSelection(simpleSelection(start), sel_dontScroll);
  }

  OperationGroup get operationGroup => cm.operationGroup;

  void setValue(String code) {
    docMethodOp(() {
      var top = new Pos(first, 0);
      var last = first + size - 1;
      makeChange(
        new Change(
          top,
          new Pos(last, _getLine(last).text.length),
          splitLines(code),
          "setValue",
          null,
          true
        ),
        true);
      _setSelection(simpleSelection(top));
    })();
  }

  dynamic docMethodOp(f) {
    return () {
      if (cm == null || cm.curOp != null) return f();
      cm.startOperation(cm);
      try {
        return f();
      } finally {
        cm.endOperation(cm);
      }
    };
  }

  // Compute the position of the end of a change (its 'to' property
  // refers to the pre-change end).
  Pos changeEnd(Change change) {
    if (change.text == null) return change.to;
    return new Pos(change.from.line + change.text.length - 1,
               lst(change.text).length + (change.text.length == 1
                                            ? change.from.char : 0));
  }

  // Adjust a position to refer to the post-change position of the
  // same text, or the end of the change if the change covers it.
  Pos adjustForChange(Pos pos, Change change) {
    if (cmp(pos, change.from) < 0) return pos;
    if (cmp(pos, change.to) <= 0) return changeEnd(change);

    var line = pos.line + change.text.length -
        (change.to.line - change.from.line) - 1;
    var ch = pos.char;
    if (pos.line == change.to.line) {
      ch += changeEnd(change).char - change.to.char;
    }
    return new Pos(line, ch);
  }

  Selection computeSelAfterChange(Change change) {
    var out = [];
    for (var i = 0; i < sel.ranges.length; i++) {
      var range = sel.ranges[i];
      out.add(new Range(adjustForChange(range.anchor, change),
                        adjustForChange(range.head, change)));
    }
    return normalizeSelection(out, sel.primIndex);
  }

  Pos offsetPos(Pos pos, Pos old, Pos nw) {
    if (pos.line == old.line) {
      return new Pos(nw.line, pos.char - old.char + nw.char);
    } else {
      return new Pos(nw.line + (pos.line - old.line), pos.char);
    }
  }

  // Used by replaceSelections to allow moving the selection to the
  // start or around the replaced test. Hint may be "start" or "around".
  Selection computeReplacedSel(List<Change> changes, [String hint]) {
    var out = [];
    var oldPrev = new Pos(first, 0), newPrev = oldPrev;
    for (var i = 0; i < changes.length; i++) {
      var change = changes[i];
      var from = offsetPos(change.from, oldPrev, newPrev);
      var to = offsetPos(changeEnd(change), oldPrev, newPrev);
      oldPrev = change.to;
      newPrev = to;
      if (hint == "around") {
        var range = sel.ranges[i], inv = cmp(range.head, range.anchor) < 0;
        out.add(new Range(inv ? to : from, inv ? from : to));
      } else {
        out.add(new Range(from, from));
      }
    }
    return new Selection(out, sel.primIndex);
  }

  // Allow "beforeChange" event handlers to influence a change
  Change filterChange(Change change, bool update) {
    var obj = new ChangeFilter(change, update, this);
    signal(this, "beforeChange", this, obj);
    if (cm != null) signal(cm, "beforeChange", cm, obj);
    if (obj.canceled) return null;
    return new Change(obj.from, obj.to, obj.text, obj.origin);
  }

  // Apply a change to a document, and add it to the document's
  // history, and propagating it to all linked documents.
  void makeChange(Change change, [bool ignoreReadOnly = false]) {
    if (cm != null) {
      if (cm.curOp == null) {
        return cm.operation(cm, () => makeChange(change, ignoreReadOnly))();
      }
      if (cm.state.suppressEdits) return null;
    }

    if (hasHandler(this, "beforeChange") ||
        cm != null && hasHandler(cm, "beforeChange")) {
      change = filterChange(change, true);
      if (change == null) return null;
    }

    // Possibly split or suppress the update based on the presence
    // of read-only spans in its range.
    List split = sawReadOnlySpans && !ignoreReadOnly
        ? removeReadOnlyRanges(change.from, change.to) : null;
    if (split != null) {
      for (var i = split.length - 1; i >= 0; --i) {
        makeChangeInner(new Change(split[i].from, split[i].to,
            i > 0 ? [""] : change.text));
      }
    } else {
      makeChangeInner(change);
    }
  }

  void makeChangeInner(Change change) {
    if (change.text.length == 1 && change.text[0] == "" && cmp(change.from, change.to) == 0) return;
    var selAfter = computeSelAfterChange(change);
    addChangeToHistory(change, selAfter, cm != null ? cm.curOp.id : 0);

    makeChangeSingleDoc(change, selAfter, stretchSpansOverChange(change));
    var rebased = [];

    linkedDocs(this, (Document doc, bool sharedHist) {
      if (!sharedHist && rebased.indexOf(doc.history) == -1) {
        doc.rebaseHist(doc.history, change);
        rebased.add(doc.history);
      }
      doc.makeChangeSingleDoc(change, null, doc.stretchSpansOverChange(change));
    });
  }

  // Revert a change stored in a document's history.
  void makeChangeFromHistory(String type, [bool allowSelectionOnly = false]) {
    if (cm != null && cm.state.suppressEdits) return;

    var hist = history, event, selAfter = sel;
    var source = type == "undo" ? hist.done : hist.undone, dest = type == "undo" ? hist.undone : hist.done;

    // Verify that there is a useable event (so that ctrl-z won't
    // needlessly clear selection events)
    int i;
    for (i = 0; i < source.length; i++) {
      event = source[i];
      if (allowSelectionOnly ? event.isSelection && !event.equals(sel) : !event.isSelection)
        break;
    }
    if (i == source.length) return;
    hist.lastOrigin = hist.lastSelOrigin = null;

    for (;;) {
      event = source.removeLast();
      if (event.isSelection) {
        pushSelectionToHistory(event, dest);
        if (allowSelectionOnly && !event.equals(sel)) {
          _setSelection(event, new SelectionOptions(clearRedo: false));
          return;
        }
        selAfter = event;
      } else {
        break;
      }
    }

    // Build up a reverse change object to add to the opposite history
    // stack (redo when undoing, and vice versa).
    var antiChanges = [];
    pushSelectionToHistory(selAfter, dest);
    dest.add(new HistoryEvent(antiChanges, hist.generation));
    hist.generation = event.generation != 0 ? event.generation : ++hist.maxGeneration;

    var filter = hasHandler(this, "beforeChange") || cm != null && hasHandler(cm, "beforeChange");

    for (var i = event.changes.length - 1; i >= 0; --i) {
      Change change = event.changes[i];
      change.origin = type;
      if (filter && filterChange(change, false) == null) {
        source.length = 0;
        return;
      }

      antiChanges.add(History.historyChangeFromChange(this, change));

      Selection after = i > 0 ? computeSelAfterChange(change) : lst(source);
      makeChangeSingleDoc(change, after, mergeOldSpans(change));
      if (i != 0 && cm != null) cm.scrollIntoView(new Range(change.from, changeEnd(change)));
      var rebased = [];

      // Propagate to the linked documents
      linkedDocs(this, (Document doc, bool sharedHist) {
        if (!sharedHist && rebased.indexOf(doc.history) == -1) {
          doc.rebaseHist(doc.history, change);
          rebased.add(doc.history);
        }
        doc.makeChangeSingleDoc(change, null, doc.mergeOldSpans(change));
      });
    }
  }

  // Sub-views need their line numbers shifted when text is added
  // above or below them in the parent document.
  void shiftDoc(distance) {
    if (distance == 0) return null;
    first += distance;
    sel = new Selection(sel.ranges.map((range) {
      return new Range(new Pos(range.anchor.line + distance, range.anchor.char),
                       new Pos(range.head.line + distance, range.head.char));
    }).toList(), sel.primIndex);
    if (cm != null) {
      cm.regChange(first, first - distance, distance);
      for (var d = cm.display, l = d.viewFrom; l < d.viewTo; l++)
        cm.regLineChange(l, "gutter");
    }
  }

  // More lower-level change function, handling only a single document
  // (not linked ones).
  makeChangeSingleDoc(Change change, selAfter, List<List<MarkedSpan>> spans) {
    if (cm != null && cm.curOp == null)
      return cm.operation(cm, () => makeChangeSingleDoc(change, selAfter, spans))();

    if (change.to.line < first) {
      shiftDoc(change.text.length - 1 - (change.to.line - change.from.line));
      return null;
    }
    if (change.from.line > lastLine()) return null;

    // Clip the change to the size of this doc
    if (change.from.line < first) {
      var shift = change.text.length - 1 - (first - change.from.line);
      shiftDoc(shift);
      change = new Change(new Pos(first, 0), new Pos(change.to.line + shift, change.to.char),
                          [lst(change.text)], change.origin);
    }
    var last = lastLine();
    if (change.to.line > last) {
      change = new Change(change.from, new Pos(last, _getLine(last).text.length),
                [change.text[0]],  change.origin);
    }

    change.removed = getBetween(change.from, change.to);

    if (selAfter == null) selAfter = computeSelAfterChange(change);
    if (cm != null) cm.makeChangeSingleDocInEditor(change, spans);
    else updateDoc(this, change, spans);
    setSelectionNoUndo(selAfter, sel_dontScroll);
    return null;
  }

  void _replaceRange(dynamic code, Pos from, [Pos to, String origin]) {
    // code is String or List<String>
    if (to == null) to = from;
    if (cmp(to, from) < 0) { var tmp = to; to = from; from = tmp; }
    if (code is String) code = splitLines(code);
    makeChange(new Change(from, to, code, origin), false);
  }

  List<String> splitLines(String string) {
    // ~15 lines deleted since we don't care about IE's broken split().
    return string.split(new RegExp(r'\r\n?|\n'));
  }

  // Iterate over the document. Supports two forms -- with only one
  // argument, it calls that for each line in the document. With
  // three, it iterates over the range given by the first two (with
  // the second being non-inclusive).
  void iter(dynamic from, [int to, LineFn op]) {
    if (op != null) iterN(from - first, to - from, op);
    else iterN(first, first + size, from as LineFn);
  }
  void eachLine(dynamic from, [int to, LineFn op]) {
    iter(from, to, op);
  }

  // Non-public interface for adding and removing lines.
  void insert(int at, List<Line> lines) {
    var height = 0;
    for (var i = 0; i < lines.length; ++i) height += lines[i].height;
    insertInner(at - first, lines, height);
  }
  void remove(int at, int n) { removeInner(at - first, n); }

  // From here, the methods are part of the public interface. Most
  // are also available from CodeMirror (editor) instances.

  String getValue([String lineSep]) {
    var lines = getLines(first, first + size);
    if (lineSep == false) return lines;
    return lines.join(lineSep == null ? "\n" : lineSep);
  }
  void replaceRange(dynamic code, Pos from, [Pos to, String origin]) {
    from = clipPos(from);
    to = to != null ? clipPos(to) : from;
    _replaceRange(code, from, to, origin);
  }
  String getRange(Pos from, Pos to, [String lineSep = "\n"]) {
    var lines = getBetween(clipPos(from), clipPos(to));
    if (lineSep == false) return lines;
    return lines.join(lineSep);
  }

  String getLine(int line) {
    var l = getLineHandle(line);
    if (l == null) return null;
    return l.text;
  }

  LineHandle getLineHandle(int line) {
    if (isLine(line)) return _getLine(line); else return null;
  }
  int getLineNumber(LineHandle line) { return lineNo(line); }

  LineHandle getLineHandleVisualStart(dynamic line) {
    if (line is num) line = _getLine(line);
    return line.visualLine();
  }

  int lineCount() { return size; }
  int firstLine() { return first; }
  int lastLine() { return first + size - 1; }

// Most of the external API clips given positions to make sure they
// actually exist within the document.

  int clipLine(int n) {
    return max(first, min(n, first + size - 1));
  }
  Pos clipPos(Pos pos) {
    if (pos.line < first) return new Pos(first, 0);
    var last = first + size - 1;
    if (pos.line > last) return new Pos(last, _getLine(last).text.length);
    return pos.clipToLen(_getLine(pos.line).text.length);
  }
  List<Pos> clipPosArray(List<Pos>array) {
    List<Pos> out = new List(array.length);
    for (int i = 0; i < array.length; i++) {
      out[i] = clipPos(array[i]);
    }
    return out;
  }
  bool isLine(int l) {
    return l >= first && l < first + size;
  }

  Pos getCursor([dynamic start]) {
    Range range = sel.primary();
    Pos pos;
    if (start == null || start == "head") pos = range.head;
    else if (start == "anchor") pos = range.anchor;
    else if (start == "end" || start == "to" || start == false) pos = range.to();
    else pos = range.from();
    return pos;
  }
  List<Range> listSelections() { return sel.ranges; }
  bool somethingSelected() { return sel.somethingSelected(); }

  void setCursor(dynamic line, [int ch, SelectionOptions options]) {
    docMethodOp(() {
      Pos anchor = clipPos(line is num ? new Pos(line, ch) : line);
      setSimpleSelection(anchor, null, options);
    })();
  }
  void setSelection(Pos anchor, [Pos head, SelectionOptions options]) {
    docMethodOp(() {
      Pos to = clipPos(head == null ?  anchor : head);
      setSimpleSelection(clipPos(anchor), to, options);
    })();
  }
  void extendSelection(Pos head, [Pos other, SelectionOptions options]) {
    docMethodOp(() {
      other = other == null ? null :  clipPos(other);
      _extendSelection(clipPos(head), other, options);
    })();
  }
  void extendSelections(List<Pos> heads, [SelectionOptions options]) {
    docMethodOp(() { // CodeMirror has a bug here -- options in wrong arg list
      _extendSelections(clipPosArray(heads), options);
    })();
  }
  void extendSelectionsBy(RangeFn f, [SelectionOptions options]) {
    docMethodOp(() {
      _extendSelections(sel.ranges.map(f), options);
    })();
  }
  void setSelections(List<Range> ranges, [int primary, SelectionOptions options]) {
    docMethodOp(() {
      if (ranges.length == 0) return;
      List out = [];
      for (var i = 0; i < ranges.length; i++)
        out.add(new Range(clipPos(ranges[i].anchor),
                          clipPos(ranges[i].head)));
      if (primary == null) primary = min(ranges.length - 1, sel.primIndex);
      _setSelection(normalizeSelection(out, primary), options);
    })();
  }
  void addSelection(Pos anchor, [Pos head, SelectionOptions options]) {
    docMethodOp(() {
      List<Range> ranges = sel.ranges.sublist(0);
      ranges.add(new Range(clipPos(anchor),
          clipPos(head == null ? anchor : head)));
      _setSelection(normalizeSelection(ranges, ranges.length - 1), options);
    })();
  }

  dynamic getSelection([dynamic lineSep = '\n']) {
    var ranges = sel.ranges;
    List lines;
    for (var i = 0; i < ranges.length; i++) {
      var sel = getBetween(ranges[i].from(), ranges[i].to());
      if (lines == null) {
        lines = sel;
      } else {
        lines.addAll(sel);
      }
//      lines = lines != null ? lines.concat(sel) : sel;
    }
    if (lineSep == false) return lines;
    else return lines.join(lineSep as String);
  }
  List getSelections([dynamic lineSep = '\n']) {
    var parts = [], ranges = sel.ranges;
    for (var i = 0; i < ranges.length; i++) {
      var sel = getBetween(ranges[i].from(), ranges[i].to());
      if (lineSep != false) sel = sel.join(lineSep);
      parts.add(sel);
    }
    return parts;
  }
  void replaceSelection(String code, [String collapse, String origin]) {
    var dup = [];
    for (var i = 0; i < sel.ranges.length; i++) {
      dup.add(code);
    }
    replaceSelections(dup, collapse, origin == null ? "+input" : origin);
  }
  void replaceSelections(List<String> code, [String collapse, String origin]) {
    docMethodOp(() {
      var changes = [], sel = this.sel;
      for (var i = 0; i < sel.ranges.length; i++) {
        var range = sel.ranges[i];
        var ls = splitLines(code[i]);
        changes.add(new Change(range.from(), range.to(), ls, origin));
      }
      var newSel;
      if (collapse != null && collapse != "end") {
        newSel = computeReplacedSel(changes, collapse);
      }
      for (var i = changes.length - 1; i >= 0; i--) {
        makeChange(changes[i]);
      }
      if (newSel != null) setSelectionReplaceHistory(newSel);
      else if (cm != null) cm.ensureCursorVisible();
    })();
  }
  undo() {
    docMethodOp(() { makeChangeFromHistory("undo"); })();
  }
  redo() {
    docMethodOp(() { makeChangeFromHistory("redo"); })();
  }
  undoSelection() {
    docMethodOp(() { makeChangeFromHistory("undo", true); })();
  }
  redoSelection() {
    docMethodOp(() { makeChangeFromHistory("redo", true); })();
  }

  void setExtending(bool val) { extend = val; }
  bool getExtending() { return extend; }

  HistorySize historySize() {
    var hist = this.history;
    int done = 0, undone = 0;
    for (var i = 0; i < hist.done.length; i++) if (!hist.done[i].isSelection) ++done;
    for (var i = 0; i < hist.undone.length; i++) if (!hist.undone[i].isSelection) ++undone;
    return new HistorySize(done, undone);
  }
  void clearHistory() { history = new History(history.maxGeneration); }

  void markClean() {
    this.cleanGeneration = this.changeGeneration(true);
  }
  int changeGeneration([bool forceSplit = false]) {
    if (forceSplit)
      history.lastOp = history.lastSelOp = history.lastOrigin = null;
    return history.generation;
  }
  bool isClean([int gen]) {
    return history.generation == (gen == null ? cleanGeneration : gen);
  }

  HistoryRecord getHistory() {
    return new HistoryRecord(
        copyHistoryArray(history.done),
        copyHistoryArray(history.undone));
  }
  void setHistory(HistoryRecord histData) {
    var hist = history = new History(history.maxGeneration);
    hist.done = copyHistoryArray(histData.done/*.slice(0)*/, null, true);
    hist.undone = copyHistoryArray(histData.undone/*.slice(0)*/, null, true);
  }

  Line addLineClass(dynamic handle, String where, String cls) {
    return docMethodOp(() {
      return changeLine(handle, where == "gutter" ? "gutter" : "class", (Line line) {
        var prop = where == "text" ? "textClass"
                 : where == "background" ? "bgClass"
                 : where == "gutter" ? "gutterClass" : "wrapClass";
        if (line[prop] == null) line[prop] = cls;
        else if (classTest(cls).hasMatch(line[prop])) return false;
        else line[prop] += " " + cls;
        return true;
      });
    })();
  }
  Line removeLineClass(dynamic handle, String where, [String cls]) {
    return docMethodOp(() {
      return changeLine(handle, where == "gutter" ? "gutter" : "class", (Line line) {
        var prop = where == "text" ? "textClass"
                 : where == "background" ? "bgClass"
                 : where == "gutter" ? "gutterClass" : "wrapClass";
        var cur = line[prop];
        if (cur == null) return false;
        else if (cls == null) line[prop] = null;
        else {
          var found = classTest(cls).firstMatch(cur);
          if (found == null) return false;
          var end = found.end;
          var start = found.start;
          line[prop] = cur.substring(0, start) +
              (start == 0 || end == cur.length ? "" : " ") +
                  cur.substring(end);
        }
        return true;
      });
    })();
  }

  AbstractTextMarker markText(Pos from, Pos to, [TextMarkerOptions options]) {
    return _markText(this, clipPos(from), clipPos(to), options, "range");
  }
  AbstractTextMarker setBookmark(Pos pos, [BookmarkOptions options]) {
    if (options == null) options = new BookmarkOptions();
    var realOpts = new TextMarkerOptions();
    realOpts.replacedWith = options.widget;
    realOpts.insertLeft = options.insertLeft;
    realOpts.clearWhenEmpty = false;
    realOpts.shared = options.shared;
    pos = clipPos(pos);
    return _markText(this, pos, pos, realOpts, "bookmark");
  }
  List<TextMarker> findMarksAt(Pos pos) {
    pos = clipPos(pos);
    var markers = [], spans = _getLine(pos.line).markedSpans;
    if (spans != null) {
      for (var i = 0; i < spans.length; ++i) {
        var span = spans[i];
        if ((span.from == null || span.from <= pos.char) &&
            (span.to == null || span.to >= pos.char)) {
          var p = span.marker.parent;
          markers.add(p == null ? span.marker : p);
        }
      }
    }
    return markers;
  }
  List<TextMarker> findMarks(Pos from, Pos to, [Function filter]) {
    from = clipPos(from); to = clipPos(to);
    var found = [], lineNo = from.line;
    this.iter(from.line, to.line + 1, (Line line) {
      var spans = line.markedSpans;
      if (spans != null) {
        for (var i = 0; i < spans.length; i++) {
          var span = spans[i];
          if (!(lineNo == from.line && from.char > span.to ||
                span.from == null && lineNo != from.line ||
                lineNo == to.line && span.from > to.char) &&
              (filter == null || filter(span.marker) != null)) {
            var p = span.marker.parent;
            found.add(p == null ? span.marker : p);
          }
        }
      }
      ++lineNo;
    });
    return found;
  }
  List<TextMarker> getAllMarks() {
    var markers = [];
    this.iter((Line line) {
      var sps = line.markedSpans;
      if (sps != null) for (var i = 0; i < sps.length; ++i)
        if (sps[i].from != null) markers.add(sps[i].marker);
    });
    return markers;
  }

  Pos posFromIndex(int off) {
    var ch, lineNo = this.first;
    this.iter((Line line) {
      var sz = line.text.length + 1;
      if (sz > off) { ch = off; return true; }
      off -= sz;
      ++lineNo;
    });
    return clipPos(new Pos(lineNo, ch));
  }
  int indexFromPos(Pos coords) {
    coords = clipPos(coords);
    var index = coords.char;
    if (coords.line < this.first || coords.char < 0) return 0;
    this.iter(this.first, coords.line, (Line line) {
      index += line.text.length + 1;
    });
    return index;
  }

  Doc copy([bool copyHistory = false]) {
    var doc = new Doc(getLines(first, first + size), modeOption, first);
    doc.scrollTop = scrollTop; doc.scrollLeft = scrollLeft;
    doc.sel = sel;
    doc.extend = false;
    if (copyHistory) {
      doc.history.undoDepth = history.undoDepth;
      doc.setHistory(getHistory());
    }
    return doc;
  }

  Document linkedDoc({bool sharedHist: false, int from: -1, int to: -1, Object mode}) {
    int fromx = first, tox = first + size;
    if (from >= 0 && from > fromx) fromx = from;
    if (to >= 0 && to < tox) tox = to;
    if (mode == null) mode = modeOption;
    Document copy = new Doc(getLines(fromx, tox), mode, fromx);
    if (sharedHist) copy.history = this.history;
    if (linked == null) linked = [];
    linked.add(new DocumentLink(copy, sharedHist));
    copy.linked = [new DocumentLink(this, sharedHist, true)];
    var sharedMarkers = SharedTextMarker.findSharedMarkers(this);
    SharedTextMarker.copySharedMarkers(copy, sharedMarkers);
    return copy;
  }
  void unlinkDoc(dynamic other) {
    if (other is CodeMirror) other = other.doc;
    if (this.linked != null) {
      for (var i = 0; i < this.linked.length; ++i) {
        var link = this.linked[i];
        if (link.doc != other) continue;
        this.linked.removeAt(i);
        other.unlinkDoc(this);
        var sharedMarkers = SharedTextMarker.findSharedMarkers(this);
        SharedTextMarker.detachSharedMarkers(sharedMarkers);
        break;
      }
    }
    // If the histories were shared, split them again
    if (other.history == this.history) {
      var splitIds = [other.id];
      linkedDocs(other, (Document doc, bool shared) {splitIds.add(doc.id);}, true);
      other.history = new History(null);
      other.history.done = copyHistoryArray(this.history.done, splitIds);
      other.history.undone = copyHistoryArray(this.history.undone, splitIds);
    }
  }
  void iterLinkedDocs(Function f) { linkedDocs(this, f); }

  Mode getMode() { return mode; }
  CodeMirror getEditor() { return cm; }
  void setHistoryDepth(int n) { history.undoDepth = n; }

  // Call f for all linked documents.
  linkedDocs(Document doc, Function f, [bool sharedHistOnly = false]) {
    propagate(Document doc, Document skip, bool sharedHist) {
      if (doc.linked != null) {
        for (var i = 0; i < doc.linked.length; ++i) {
          var rel = doc.linked[i];
          if (rel.doc == skip) continue;
          var shared = sharedHist && rel.sharedHist;
          if (sharedHistOnly && !shared) continue;
          f(rel.doc, shared);
          propagate(rel.doc, doc, shared);
        }
      }
    }
    propagate(doc, null, true);
  }

  // Attach a document to an editor.
  attachDoc(CodeEditor cm, Document doc) {
    if (doc.cm != null && cm.doc != this) throw new StateError("This document is already in use.");
    cm.doc = doc;
    doc.cm = cm;
    cm.estimateLineHeights();
    cm.loadMode();
    if (!cm.options.lineWrapping) cm.findMaxLine();
    cm.options['mode'] = doc.modeOption;
    cm.regChange();
  }

  // Find the line object corresponding to the given line number.
  Line _getLine(n) {
    n -= first;
    if (n < 0 || n >= size)
      throw new StateError("No such line number: ${n + first}");
    BtreeChunk chunk;
    for (chunk = this; !chunk.isLeaf;) {
      for (var i = 0;; ++i) {
        var child = chunk.children[i];
        int sz = child.chunkSize();
        if (n < sz) {
          chunk = child;
          break;
        }
        n -= sz;
      }
    }
    return chunk.lines[n];
  }

  // Get the part of a document between two positions, as an array of strings.
  List<String> getBetween(Pos start, Pos end) {
    var out = [], n = start.line;
    iter(start.line, end.line + 1, (Line line) {
      var text = line.text;
      if (n == end.line) text = text.substring(0, end.char);
      if (n == start.line) text = text.substring(start.char);
      out.add(text);
      ++n;
    });
    return out;
  }
  // Get the lines between from and to, as array of strings.
  List<LineHandle> getLines(int from, int to) {
    var out = [];
    iter(from, to, (Line line) { out.add(line.text); });
    return out;
  }

  // Update the height of a line, propagating the height change
  // upwards to parent nodes.
  updateLineHeight(line, height) {
    var diff = height - line.height;
    if (diff) for (var n = line; n; n = n.parent) n.height += diff;
  }

  // Given a line object, find its line number by walking up through
  // its parent links.
  int lineNo(LineHandle line) {
    return line.lineNo();
//    if (line.parent == null) return null;
//    var cur = line.parent, no = cur.lines.indexOf(line);
//    for (var chunk = cur.parent; chunk; cur = chunk, chunk = chunk.parent) {
//      for (var i = 0;; ++i) {
//        if (chunk.children[i] == cur) break;
//        no += chunk.children[i].chunkSize();
//      }
//    }
//    return no + cur.first;
  }

  // Find the line at the given vertical position, using the height
  // information in the document tree.
  int lineAtHeight(BtreeChunk chunk, num h) {
    var n = chunk.first;
    outer: do {
      for (var i = 0; i < chunk.children.length; ++i) {
        var child = chunk.children[i];
        num ch = child.height;
        if (h < ch) { chunk = child; continue outer; }
        h -= ch;
        n += child.chunkSize();
      }
      return n;
    } while (!chunk.isLeaf);
    int i;
    for (i = 0; i < chunk.lines.length; ++i) {
      var line = chunk.lines[i], lh = line.height;
      if (h < lh) break;
      h -= lh;
    }
    return n + i;
  }

  // Find the height above the given line.
  num heightAtLine(Line lineObj) {
    lineObj = lineObj.visualLine();

    num h = 0;
    LeafChunk chunk = lineObj.parent;
    for (var i = 0; i < chunk.lines.length; ++i) {
      var line = chunk.lines[i];
      if (line == lineObj) break;
      else h += line.height;
    }
    BtreeChunk node = chunk;
    for (var p = node.parent; p != null; node = p, p = node.parent) {
      for (var i = 0; i < p.children.length; ++i) {
        var cur = p.children[i];
        if (cur == node) break;
        else h += cur.height;
      }
    }
    return h;
  }

  // Get the bidi ordering for the given line (and cache it). Returns
  // false for lines that are fully left-to-right, and an array of
  // BidiSpan objects otherwise.
  getOrder(line) {
    var order = line.order;
    if (order == null)
      order = line.order = cm.bidiOrdering(line.text);
    return order;
  }

  // Find the top change event in the history. Pop off selection
  // events that are in the way.
  lastChangeEvent(HistoryRecord hist, [bool force = false]) {
    // TODO Move to HistoryRecord.
    if (force) {
      clearSelectionEvents(hist.done);
      return lst(hist.done);
    } else if (hist.done.length > 0 && lst(hist.done) is! Selection) {
      return lst(hist.done);
    } else if (hist.done.length > 1 && hist.done[hist.done.length - 2] is! Selection) {
      hist.done.removeLast();
      return lst(hist.done);
    }
  }

  // Register a change in the history. Merges changes that are within
  // a single operation, ore are close together with an origin that
  // allows merging (starting with "+") into a single event.
  addChangeToHistory(Change change, Selection selAfter, Object opId) {
    var hist = history;
    hist.undone.length = 0;
    var time = new DateTime.now().millisecondsSinceEpoch;
    HistoryEvent cur;
    var last;

    if ((hist.lastOp == opId ||
         hist.lastOrigin == change.origin && change.origin != null &&
         ((change.origin.startsWith("+") && cm != null &&
          hist.lastModTime > time - cm.options.historyEventDelay) ||
          change.origin.startsWith("*"))) &&
        (cur = lastChangeEvent(hist, hist.lastOp == opId)) != null) {
      // Merge this change into the last event
      last = lst(cur.changes);
      if (cmp(change.from, change.to) == 0 && cmp(change.from, last.to) == 0) {
        // Optimized case for simple insertion -- don't want to add
        // new changesets for every character typed
        last.to = changeEnd(change);
      } else {
        // Add new sub-event
        cur.changes.add(History.historyChangeFromChange(this, change));
      }
    } else {
      // Can not be merged, start a new event.
      var before = lst(hist.done);
      if (before == null || !before.isSelection) {
        pushSelectionToHistory(sel, hist.done);
      }
      cur = new HistoryEvent([History.historyChangeFromChange(this, change)],
             hist.generation);
      hist.done.add(cur);
      while (hist.done.length > hist.undoDepth) {
        hist.done.removeAt(0);
        if (!hist.done[0].isSelection) hist.done.removeAt(0);
      }
    }
    hist.done.add(selAfter);
    hist.generation = ++hist.maxGeneration;
    hist.lastModTime = hist.lastSelTime = time;
    hist.lastOp = hist.lastSelOp = opId;
    hist.lastOrigin = hist.lastSelOrigin = change.origin;

    if (last == null) signal(this, "historyAdded");
  }

  selectionEventCanBeMerged(String origin, prev, sel) {
    var ch = origin.substring(0,1);
    return ch == "*" ||
      ch == "+" &&
      prev.ranges.length == sel.ranges.length &&
      prev.somethingSelected() == sel.somethingSelected() &&
      new DateTime.now().millisecondsSinceEpoch - history.lastSelTime <=
        (cm != null ? cm.options.historyEventDelay : 500);
  }

  // Utility for applying a change to a line by handle or number,
  // returning the number and optionally registering the line as
  // changed.
  changeLine(dynamic handle, String changeType, Function op) {
    Line line;
    int no;
    if (handle is num) {
      no = handle;
      line = _getLine(clipLine(handle));
    } else {
      no = lineNo(handle);
      line = handle;
    }
    if (no < 0) return null;
    if (op(line) && cm != null) { // Delete 'no' arg to op.
      cm.regLineChange(no, changeType);
    }
    return line;
  }

  pushSelectionToHistory(var sel, List dest) {
    if (dest.isEmpty) {
      dest.add(sel);
    } else {
      var top = lst(dest);
      if (!(top != null && top.isSelection && top.equals(sel)))
        dest.add(sel);
    }
  }

  // Used to store marked span information in the history.
  attachLocalSpans(change, from, to) {
    String name = "spans_$id";
    var existing = change[name];
    var n = 0;
    iter(max(first, from), min(first + size, to), (Line line) {
      if (line.markedSpans != null) {
        if (existing == null) change[name] = existing = {};// TODO new Something()
        (existing)[n] = line.markedSpans;
      }
      ++n;
    });
  }

  // When un/re-doing restores text containing marked spans, those
  // that have been explicitly cleared should not be restored.
  removeClearedSpans(List spans) {
    if (spans == null) return null;
    var out;
    for (var i = 0; i < spans.length; ++i) {
      if (spans[i].marker.explicitlyCleared) {
        if (out == null) out = spans.sublist(0, i);
      } else if (out != null) {
        out.push(spans[i]);
      }
    }
    return out == null ? spans : out.length > 0 ? out : null;
  }

  // Retrieve and filter the old marked spans stored in a change event.
  getOldSpans(change) {
    var found = change["spans_$id"];
    if (found == null) return null;
    var nw = [];
    for (var i = 0; i < change.text.length; ++i)
      nw.add(removeClearedSpans(found[i]));
    return nw;
  }

  // Used both to provide a JSON-safe object in .getHistory, and, when
  // detaching a document, to split the history in two
  copyHistoryArray(List events, [List newGroup, bool instantiateSel = false]) {
    var copy = [];
    for (var i = 0; i < events.length; ++i) {
      var event = events[i];
      if (event is Selection) {
        copy.add(instantiateSel ? event.deepCopy() : event);
        continue;
      }
      var changes = (event as HistoryEvent).changes, newChanges = [];
      copy.add(new HistoryEvent(newChanges));
      for (var j = 0; j < changes.length; ++j) {
        var change = changes[j], m;
        newChanges.add(new Change(change.from, change.to, change.text));
        if (newGroup != null) {
          int i = 0;
          // TODO Define a Change method to do what this loop does.
          for (var prop in [change.from, change.to, change.text, change.origin, change.removed]) {
            if (prop is! String) continue;
            m = new RegExp(r'^spans_(\d+)$').matchAsPrefix(prop);
            if (m != null) {
              if (newGroup.indexOf(int.parse(m[1])) > -1) {
                // TODO Not sure this is correct but I think the original
                // was enumerating the properties and moving selected ones.
                var newCh = lst(newChanges);
                switch (i) {
                  case 0:
                    newCh.from = change.from;
                    change.from = null;
                    break;
                  case 1:
                    newCh.to = change.to;
                    change.to = null;
                    break;
                  case 2:
                    newCh.text = change.text;
                    change.text = null;
                    break;
                }
//                lst(newChanges)[prop] = change[prop];
//                change.remove(prop);
              }
            }
            i += 1;
          }
        }
      }
    }
    return copy;
  }

  // Rebasing/resetting history to deal with externally-sourced changes
  rebaseHistSelSingle(Pos pos, int from, int to, int diff) {
    if (to < pos.line) {
      pos.line += diff;
    } else if (from < pos.line) {
      pos.line = from;
      pos.char = 0;
    }
  }

  // Tries to rebase an array of history events given a change in the
  // document. If the change touches the same lines as the event, the
  // event, and everything 'behind' it, is discarded. If the change is
  // before the event, the event's positions are updated. Uses a
  // copy-on-write scheme for the positions, to avoid having to
  // reallocate them all on every rebase, but also avoid problems with
  // shared position objects being unsafely updated.
  rebaseHistArray(List array, from, to, diff) {
    for (var i = 0; i < array.length; ++i) {
      var sub = array[i], ok = true;
      if (sub.isSelection) {
        if (!sub.copied) {
          sub = array[i] = sub.deepCopy(); //sub.copied = true;
        }
        for (var j = 0; j < sub.ranges.length; j++) {
          rebaseHistSelSingle(sub.ranges[j].anchor, from, to, diff);
          rebaseHistSelSingle(sub.ranges[j].head, from, to, diff);
        }
        continue;
      }
      for (var j = 0; j < sub.changes.length; ++j) {
        var cur = sub.changes[j];
        if (to < cur.from.line) {
          cur.from = new Pos(cur.from.line + diff, cur.from.char);
          cur.to = new Pos(cur.to.line + diff, cur.to.char);
        } else if (from <= cur.to.line) {
          ok = false;
          break;
        }
      }
      if (!ok) {
        array.removeRange(0, i + 1);
        i = 0;
      }
    }
  }

  rebaseHist(HistoryRecord hist, Change change) {
    var from = change.from.line, to = change.to.line, diff = change.text.length - (to - from) - 1;
    rebaseHistArray(hist.done, from, to, diff);
    rebaseHistArray(hist.undone, from, to, diff);
  }

  // Ensure the lineView.wrapping.heights array is populated. This is
  // an array of bottom offsets for the lines that make up a drawn
  // line. When lineWrapping is on, there might be more than one
  // height.
  ensureLineHeights(LineView lineView, var rect) {
    var wrapping = cm.options.lineWrapping;
    num curWidth = wrapping ? cm.display.displayWidth() : 0;
    if (lineView.measure.heights == null ||
        wrapping && lineView.measure.width != curWidth) {
      var heights = lineView.measure.heights = [];
      if (wrapping) {
        lineView.measure.width = curWidth;
        var rects = (lineView.text.firstChild as Element).getClientRects();
        for (var i = 0; i < rects.length - 1; i++) {
          var cur = rects[i], next = rects[i + 1];
          if ((cur.bottom - next.bottom).abs() > 2)
            heights.add((cur.bottom + next.top) / 2 - rect.top);
        }
      }
      heights.add(rect.bottom - rect.top);
    }
  }

  // Find a line map (mapping character offsets to text nodes) and a
  // measurement cache for the given line number. (A line view might
  // contain multiple lines when collapsed ranges are present.)
  LineMap mapFromLineView(LineView lineView, Line line, int lineN) {
    if (lineView.line == line)
      return new LineMap(lineView.measure.map, lineView.measure.cache);
    for (var i = 0; i < lineView.rest.length; i++)
      if (lineView.rest[i] == line)
        return new LineMap(lineView.measure.maps[i], lineView.measure.caches[i]);
    for (var i = 0; i < lineView.rest.length; i++)
      if (lineNo(lineView.rest[i]) > lineN)
        return new LineMap(lineView.measure.maps[i], lineView.measure.caches[i], true);
    return null;
  }

  // Render a line into the hidden node display.externalMeasured. Used
  // when measurement is needed for a line that's not in the viewport.
  LineView updateExternalMeasurement(Line line) {
    line = line.visualLine();
    int lineN = line.lineNo();
    var view = cm.display.externalMeasured = new LineView(cm.doc, line, lineN);
    view.lineN = lineN;
    LineBuilder built = view.built = cm.buildLineContent(view);
    view.text = built.pre;
    removeChildrenAndAdd(cm.display.lineMeasure, built.pre);
    return view;
  }

  // Get a {top, bottom, left, right} box (in line-local coordinates)
  // for a given character.
  measureChar(Line line, int ch, [String bias]) {
    return measureCharPrepared(prepareMeasureForLine(line), ch, bias);
  }

  // Find a line view that corresponds to the given line number.
  findViewForLine(int lineN) {
    if (lineN >= cm.display.viewFrom && lineN < cm.display.viewTo)
      return cm.display.view[cm.display.findViewIndex(lineN)];
    var ext = cm.display.externalMeasured;
    if (ext != null && lineN >= ext.lineN && lineN < ext.lineN + ext.size)
      return ext;
  }

  // Measurement can be split in two steps, the set-up work that
  // applies to the whole line, and the measurement of the actual
  // character. Functions like coordsChar, that need to do a lot of
  // measurements in a row, can thus ensure that the set-up work is
  // only done once.
  prepareMeasureForLine(Line line) {
    var lineN = lineNo(line);
    LineView view = findViewForLine(lineN);
    if (view != null && view.text == null)
      view = null;
    else if (view != null && view.changes != null)
      view.updateLineForChanges(cm, lineN, cm.display.getDimensions(cm));
    if (view == null)
      view = updateExternalMeasurement(line);

    var info = mapFromLineView(view, line, lineN);
    return new LineMeasurement(line, view, null, info.map,
        info.cache, info.before, false);
  }

  // Given a prepared measurement object, measures the position of an
  // actual character (or fetches it from the cache).
  Rect measureCharPrepared(LineMeasurement prepared, int ch,
                           String bias, [varHeight = false]) {
    if (prepared.before != null) ch = -1;
    String key = bias == null ? "$ch" : "$ch$bias";
    var found;
    if (prepared.cache.containsKey(key)) {
      found = prepared.cache[key];
    } else {
      if (prepared.rect == null)
        prepared.rect = prepared.view.text.getBoundingClientRect();
      if (!prepared.hasHeights) {
        ensureLineHeights(prepared.view, prepared.rect);
        prepared.hasHeights = true;
      }
      found = measureCharInner(prepared, ch, bias);
      if (!found.bogus) prepared.cache[key] = found;
    }
    return new Rect(left: found.left, right: found.right,
            top: varHeight ? found.rtop : found.top,
            bottom: varHeight ? found.rbottom : found.bottom);
  }

  static final Rect nullRect = new Rect(left: 0, right: 0, top: 0, bottom: 0);

  measureCharInner(LineMeasurement prepared, int ch, String bias) {
    var map = prepared.map;

    Node node;
    var start, end;
    String collapse;
    var mStart, mEnd;
    // First, search the line map for the text node corresponding to,
    // or closest to, the target character.
    for (var i = 0; i < map.length; i += 3) {
      mStart = map[i];
      mEnd = map[i + 1];
      if (ch < mStart) {
        start = 0; end = 1;
        collapse = "left";
      } else if (ch < mEnd) {
        start = ch - mStart;
        end = start + 1;
      } else if (i == map.length - 3 || ch == mEnd && map[i + 3] > ch) {
        end = mEnd - mStart;
        start = end - 1;
        if (ch >= mEnd) collapse = "right";
      }
      if (start != null) {
        node = map[i + 2];
        if (mStart == mEnd && bias == (_isInsertLeft(node) ? "left" : "right"))
          collapse = bias;
        if (bias == "left" && start == 0)
          while (i > 0 && map[i - 2] == map[i - 3] && _isInsertLeft(map[i - 1])) {
            node = map[(i -= 3) + 2];
            collapse = "left";
          }
        if (bias == "right" && start == mEnd - mStart)
          while (i < map.length - 3 && map[i + 3] == map[i + 4] &&
              !_isInsertLeft(map[i + 5])) {
            node = map[(i += 3) + 2];
            collapse = "right";
          }
        break;
      }
    }

    var rect;
    if (node.nodeType == 3) {
      // If it is a text node, use a range to retrieve the coordinates.
      for (var i = 0; i < 4; i++) {
        // Retry a maximum of 4 times when nonsense rectangles are returned
        var prepLine = prepared.line.text;
        var prepLineLen = prepLine.length;
        while (start > 0 && mStart + start + 1 <= prepLineLen &&
            isExtendingChar(prepLine.substring(mStart + start, mStart + start + 1))) {
          --start;
        }
        while (mStart + end < mEnd && mStart + end + 1 <= prepLineLen &&
            isExtendingChar(prepLine.substring(mStart + end, mStart + end + 1))) {
          ++end;
        }
        if (ie && ie_version < 9 && start == 0 && end == mEnd - mStart) {
          rect = (node.parentNode as Element).getBoundingClientRect();
        } else if (ie && cm.options.lineWrapping) {
          var rects = range(node, start, end).getClientRects();
          if (rects.length)
            rect = rects[bias == "right" ? rects.length - 1 : 0];
          else
            rect = nullRect;
        } else {
          rect = range(node, start, end).getBoundingClientRect();
          if (rect == null) rect = nullRect;
        }
        if (rect.left != 0 || rect.right != 0 || start == 0) break;
        end = start;
        start = start - 1;
        collapse = "right";
      }
//      if (ie && ie_version < 11) {
//        rect = maybeUpdateRectForZooming(cm.display.measure, rect);
//      }
    } else { // If it is a widget, simply get the box for the whole widget.
      if (start > 0) collapse = bias = "right";
      var element = node as Element;
      var rects;
      if (cm.options.lineWrapping && (rects = element.getClientRects()).length > 1)
        rect = rects[bias == "right" ? rects.length - 1 : 0];
      else
        rect = element.getBoundingClientRect();
    }
//    if (ie && ie_version < 9 && !start && (!rect || !rect.left && !rect.right)) {
//      var rSpan = node.parentNode.getClientRects()[0];
//      if (rSpan)
//        rect = new Rect(left: rSpan.left,
//            right: rSpan.left + charWidth(cm.display),
//            top: rSpan.top, bottom: rSpan.bottom);
//      else
//        rect = nullRect;
//    }

    var rtop = rect.top - prepared.rect.top;
    var rbot = rect.bottom - prepared.rect.top;
    var mid = (rtop + rbot) / 2;
    var heights = prepared.view.measure.heights;
    int i;
    for (i = 0; i < heights.length - 1; i++)
      if (mid < heights[i]) break;
    var top = i > 0 ? heights[i - 1] : 0;
    var bot = heights[i];
    var l = (collapse == "right" ? rect.right : rect.left) - prepared.rect.left;
    var rt = (collapse == "left" ? rect.left : rect.right) - prepared.rect.left;
    var result = new Rect(left: l, right: rt, top: top, bottom: bot);
    if (rect.left == 0 && rect.right == 0) result.bogus = true;
    if (!cm.options.singleCursorHeightPerLine) {
      result.rtop = rtop;
      result.rbottom = rbot;
    }

    return result;
  }

  // Work around problem with bounding client rects on ranges being
  // returned incorrectly when zoomed on IE10 and below.
  maybeUpdateRectForZooming(measure, rect) {
    throw new StateError('Need work-around for IE10 scaling problem');
//    if (window.screen == null || window.screen.logicalXDPI == null ||
//        window.screen.logicalXDPI == window.screen.deviceXDPI ||
//        !hasBadZoomedRects(measure))
//      return rect;
//    var scaleX = screen.logicalXDPI / screen.deviceXDPI;
//    var scaleY = screen.logicalYDPI / screen.deviceYDPI;
//    return {left: rect.left * scaleX, right: rect.right * scaleX,
//            top: rect.top * scaleY, bottom: rect.bottom * scaleY};
  }

  clearLineMeasurementCacheFor(LineView lineView) { // Not sure of type.
    if (lineView.measure != null) {
      lineView.measure.cache = {};
      lineView.measure.heights = null;
      if (lineView.rest != null) {
        for (var i = 0; i < lineView.rest.length; i++) {
          lineView.measure.caches[i] = {};
        }
      }
    }
  }

  clearLineMeasurementCache() {
    // The original has a bug where externalMeasured has no 'd'.
    cm.display.externalMeasured = null;
    removeChildren(cm.display.lineMeasure);
    for (var i = 0; i < cm.display.view.length; i++)
      clearLineMeasurementCacheFor(cm.display.view[i]);
  }

  clearCaches() {
    clearLineMeasurementCache();
    cm.display.cachedCharWidth = cm.display.cachedTextHeight = 0;
    cm.display.cachedPaddingH = null;
    if (!cm.options.lineWrapping) cm.display.maxLineChanged = true;
    cm.display.lineNumChars = null;
  }

  pageScrollX() {
    if (window.pageXOffset != 0) {
      return window.pageXOffset;
    } else if (document.documentElement != null) {
      return document.documentElement.scrollLeft;
    } else {
      return document.body.scrollLeft;
    }
  }
  pageScrollY() {
    if (window.pageYOffset != 0) {
      return window.pageYOffset;
    } else if (document.documentElement != null) {
      return document.documentElement.scrollTop;
    } else {
      return document.body.scrollTop;
    }
  }

  // Converts a {top, bottom, left, right} box from line-local
  // coordinates into another coordinate system. Context may be one of
  // "line", "div" (display.lineDiv), "local"/null (editor), "window",
  // or "page".
  Rect intoCoordSystem(Line lineObj, rect, context) {
    if (lineObj.widgets != null) {
      for (var i = 0; i < lineObj.widgets.length; ++i) {
        if (lineObj.widgets[i].above) {
          var size = lineObj.widgets[i].widgetHeight();
          rect.top += size;
          rect.bottom += size;
        }
      }
    }
    if (context == "line") return rect;
    if (context == null) context = "local";
    var yOff = heightAtLine(lineObj);
    if (context == "local") yOff += cm.display.paddingTop();
    else yOff -= cm.display.viewOffset;
    if (context == "page" || context == "window") {
      var lOff = cm.display.lineSpace.getBoundingClientRect();
      yOff += lOff.top + (context == "window" ? 0 : pageScrollY());
      var xOff = lOff.left + (context == "window" ? 0 : pageScrollX());
      rect.left += xOff; rect.right += xOff;
    }
    rect.top += yOff; rect.bottom += yOff;
    return rect;
  }

  // Coverts a box from "div" coords to another coordinate system.
  // Context may be "window", "page", "div", or "local"/null.
  Loc fromCoordSystem(Loc coords, String context) {
    if (context == "div") return coords;
    var left = coords.left, top = coords.top;
    // First move into "page" coordinate system
    if (context == "page") {
      left -= pageScrollX();
      top -= pageScrollY();
    } else if (context == "local" || context == null) {
      var localBox = cm.display.sizer.getBoundingClientRect();
      left += localBox.left;
      top += localBox.top;
    }

    var lineSpaceBox = cm.display.lineSpace.getBoundingClientRect();
    return new Rect(left: left - lineSpaceBox.left, top: top - lineSpaceBox.top);
  }

  Rect charCoords(Pos pos, String context, [Line lineObj, bias]) {
    if (lineObj == null) lineObj = _getLine(pos.line);
    return intoCoordSystem(lineObj,
        measureChar(lineObj, pos.char, bias), context);
  }

  // Returns a box for a given cursor position, which may have an
  // 'other' property containing the position of the secondary cursor
  // on a bidi boundary.
  Rect cursorCoords(Pos pos, [String context, Line lineObj, preparedMeasure, bool varHeight = false]) {
    if (lineObj == null) lineObj = _getLine(pos.line);
    if (preparedMeasure == null ) preparedMeasure = prepareMeasureForLine(lineObj);
    var order = getOrder(lineObj);
    int ch = pos.char;
    get(int ch, bool right) {
      var m = measureCharPrepared(preparedMeasure, ch, right ? "right" : "left", varHeight);
      if (right) m.left = m.right; else m.right = m.left;
      return intoCoordSystem(lineObj, m, context);
    }
    getBidi(int ch, int partPos) {
      var part = order[partPos], right = part.level % 2 != 0;
      if (ch == cm.bidiLeft(part) && partPos > 0 && part.level < order[partPos - 1].level) {
        part = order[--partPos];
        ch = cm.bidiRight(part) - (part.level % 2 != 0 ? 0 : 1);
        right = true;
      } else if (ch == cm.bidiRight(part) && partPos < order.length - 1 && part.level < order[partPos + 1].level) {
        part = order[++partPos];
        ch = cm.bidiLeft(part) - part.level % 2;
        right = false;
      }
      if (right && ch == part.to && ch > part.from) return get(ch - 1, false);
      return get(ch, right != 0 && right != false);
    }
    if (order == false) return get(ch, false);
    var partPos = cm.getBidiPartAt(order, ch);
    Rect val = getBidi(ch, partPos);
    if (bidiOther != null) {
      val = new RectWithInfo(val, getBidi(ch, bidiOther));
    }
    return val;
  }

  // Used to cheaply estimate the coordinates for a position. Used for
  // intermediate scroll updates.
  Rect estimateCoords(Pos pos) {
    var left = 0;
    pos = clipPos(pos);
    if (!cm.options.lineWrapping) left = cm.display.charWidth() * pos.char;
    var lineObj = _getLine(pos.line);
    var top = heightAtLine(lineObj) + cm.display.paddingTop();
    return new Rect(left: left, right: left, top: top, bottom: top + lineObj.height);
  }

  // The 'scroll' parameter given to many of these indicated whether
  // the new cursor position should be scrolled into view after
  // modifying the selection.

  // If shift is held or the extend flag is set, extends a range to
  // include a given position (and optionally a second position).
  // Otherwise, simply returns the range between the given positions.
  // Used for cursor motion and such.
  extendRange(Range range, Pos head, [Pos other]) {
    if (cm != null && cm.display.shift || extend) {
      var anchor = range.anchor;
      if (other != null) {
        var posBefore = cmp(head, anchor) < 0;
        if (posBefore != (cmp(other, anchor) < 0)) {
          anchor = head;
          head = other;
        } else if (posBefore != (cmp(head, other) < 0)) {
          head = other;
        }
      }
      return new Range(anchor, head);
    } else {
      return new Range(other == null ? head : other, head);
    }
  }

  // Extend the primary selection range, discard the rest.
  _extendSelection(head, [other, options]) {
    _setSelection(new Selection([extendRange(sel.primary(), head, other)], 0), options);
  }

  // Extend all selections (pos is an array of selections with length
  // equal the number of selections)
  _extendSelections(Iterable heads, [SelectionOptions options]) {
    var out = [];
    var iter = heads.iterator;
    for (var i = 0; i < sel.ranges.length; i++) {
      iter.moveNext();
      out.add(extendRange(sel.ranges[i], iter.current, null));
    }
    var newSel = normalizeSelection(out, sel.primIndex);
    _setSelection(newSel, options);
  }

  // Updates a single range in the selection.
  replaceOneSelection(i, range, [SelectionOptions options]) {
    var ranges = sel.ranges.sublist(0);
    ranges[i] = range;
    _setSelection(normalizeSelection(ranges, sel.primIndex), options);
  }

  // Reset the selection to a single range.
  setSimpleSelection(anchor, head, [SelectionOptions options]) {
    _setSelection(simpleSelection(anchor, head), options);
  }

  // Give beforeSelectionChange handlers a change to influence a
  // selection update.
  filterSelectionChange(Selection sel) {
    SelectionUpdate obj = new SelectionUpdate(this, sel.ranges);
    signal(this, "beforeSelectionChange", this, obj);
    if (cm != null) signal(cm, "beforeSelectionChange", cm, obj);
    if (obj.wasUpdated) {
      return normalizeSelection(obj.ranges, obj.ranges.length - 1);
    } else {
      return sel;
    }
  }

  setSelectionReplaceHistory(Selection sel, [SelectionOptions options]) {
    var last;
    List done = history.done;
    if (done.length > 0) last = lst(done);
    if (last != null && last is Selection) {
      done[done.length - 1] = sel;
      setSelectionNoUndo(sel, options);
    } else {
      _setSelection(sel, options);
    }
  }

  // Set a new selection.
  _setSelection(Selection sel, [SelectionOptions options]) {
    setSelectionNoUndo(sel, options);
    addSelectionToHistory(this.sel, cm != null ? cm.curOp.id : double.NAN, options);
  }

  // Compute the character position closest to the given coordinates.
  // Input must be lineSpace-local ("div" coordinate system).
  PosWithInfo coordsChar(num x, num y) {
    y += cm.display.viewOffset;
    if (y < 0) return new PosWithInfo(first, 0, true, -1);
    var lineN = lineAtHeight(this, y), last = first + size - 1;
    if (lineN > last) {
      var l = _getLine(last).text.length;
      return new PosWithInfo(first + size - 1, l, true, 1);
    }
    if (x < 0) x = 0;

    var lineObj = _getLine(lineN);
    for (;;) {
      var found = coordsCharInner(lineObj, lineN, x, y);
      var merged = lineObj.collapsedSpanAtEnd();
      var mergedPos = merged != null ? merged.find(0, true) : null;
      if (merged != null &&
          (found.char > mergedPos.from.char ||
              found.char == mergedPos.from.char && found.xRel > 0)) {
        lineN = lineNo(lineObj = mergedPos.to.line);
      } else {
        return found;
      }
    }
  }

  PosWithInfo coordsCharInner(Line lineObj, int lineNo, num x, num y) {
    var innerOff = y - heightAtLine(lineObj);
    var wrongLine = false, adjust = 2 * cm.display.wrapper.clientWidth;
    var preparedMeasure = prepareMeasureForLine(lineObj);

    num getX(int ch) {
      var sp = cursorCoords(new Pos(lineNo, ch), "line", lineObj, preparedMeasure);
      wrongLine = true;
      if (innerOff > sp.bottom) return sp.left - adjust;
      else if (innerOff < sp.top) return sp.left + adjust;
      else wrongLine = false;
      return sp.left;
    }

    var bidi = getOrder(lineObj), dist = lineObj.text.length;
    var from = cm.lineLeft(lineObj), to = cm.lineRight(lineObj);
    var fromX = getX(from), fromOutside = wrongLine, toX = getX(to);
    var toOutside = wrongLine;

    if (x > toX) return new PosWithInfo(lineNo, to, toOutside, 1);
    // Do a binary search between these bounds.
    for (;;) {
      if (bidi != false ? to == from || to == cm.moveVisually(lineObj, from, 1) : to - from <= 1) {
        var ch = x < fromX || x - fromX <= toX - x ? from : to;
        var xDiff = x - (ch == from ? fromX : toX);
        while (ch < lineObj.text.length && isExtendingChar(lineObj.text.substring(ch, ch+1))) ++ch;
        var pos = new PosWithInfo(lineNo, ch, ch == from ? fromOutside : toOutside,
                                  xDiff < -1 ? -1 : xDiff > 1 ? 1 : 0);
        return pos;
      }
      var step = (dist / 2).ceil(), middle = from + step;
      if (bidi != false) {
        middle = from;
        for (var i = 0; i < step; ++i) middle = cm.moveVisually(lineObj, middle, 1);
      }
      var middleX = getX(middle);
      if (middleX > x) {
        to = middle; toX = middleX;
        if (toOutside = wrongLine) toX += 1000;
        dist = step;
      } else {
        from = middle; fromX = middleX;
        fromOutside = wrongLine; dist -= step;
      }
    }
  }

  // Called whenever the selection changes, sets the new selection as
  // the pending selection in the history, and pushes the old pending
  // selection into the 'done' array when it was significantly
  // different (in number of selected ranges, emptiness, or time).
  addSelectionToHistory(Selection sel, num opId, [SelectionOptions options]) {
    var hist = history;
    String origin = options == null ? null : options.origin;

    // A new event is started when the previous origin does not match
    // the current, or the origins don't allow matching. Origins
    // starting with * are always merged, those starting with + are
    // merged when similar and close together in time.
    if (opId == hist.lastSelOp ||
        (origin != null && hist.lastSelOrigin == origin &&
         (hist.lastModTime == hist.lastSelTime && hist.lastOrigin == origin ||
          selectionEventCanBeMerged(origin, lst(hist.done), sel))))
      hist.done[hist.done.length - 1] = sel;
    else
      pushSelectionToHistory(sel, hist.done);

    hist.lastSelTime = new DateTime.now().millisecondsSinceEpoch;
    hist.lastSelOrigin = origin;
    hist.lastSelOp = opId;
    if (options != null && options.clearRedo != false)
      clearSelectionEvents(hist.undone);
  }

  setSelectionNoUndo(sel, [options]) {
    if (hasHandler(this, "beforeSelectionChange") ||
        cm != null && hasHandler(cm, "beforeSelectionChange"))
      sel = filterSelectionChange(sel);

    var bias;
    if (options != null && options.bias != null) {
      bias = options.bias;
    } else {
      bias = (cmp(sel.primary().head, this.sel.primary().head) < 0) ? -1 : 1;
    }
    setSelectionInner(skipAtomicInSelection(sel, bias, true));

    if (!(options != null && options.scroll == false) && cm != null)
      cm.ensureCursorVisible();
  }

  setSelectionInner(sel) {
    if (sel.equals(this.sel)) return;

    this.sel = sel;

    if (cm != null) {
      cm.curOp.updateInput = cm.curOp.selectionChanged = true;
      signalCursorActivity(cm);
    }
    signalLater(this, "cursorActivity", this);
  }

  // Verify that the selection does not partially select any atomic
  // marked ranges.
  reCheckSelection() { // CodeMirror includes sel_dontScroll on next line
    setSelectionInner(skipAtomicInSelection(sel, null, false));
  }

  // Return a selection that does not partially select any atomic
  // ranges.
  skipAtomicInSelection(sel, bias, mayClear) {
    var out;
    for (var i = 0; i < sel.ranges.length; i++) {
      var range = sel.ranges[i];
      var newAnchor = skipAtomic(range.anchor, bias, mayClear);
      var newHead = skipAtomic(range.head, bias, mayClear);
      if (out != null || newAnchor != range.anchor || newHead != range.head) {
        if (out == null) out = sel.ranges.sublist(0, i);
        out.add(new Range(newAnchor, newHead));
      }
    }
    return out != null ? normalizeSelection(out, sel.primIndex) : sel;
  }

  // Ensure a given position is not inside an atomic range.
  skipAtomic(Pos pos, bias, mayClear) {
    var flipped = false, curPos = pos;
    int dir = 1;
    if (bias != null) dir = bias as int;
    cantEdit = false;
    search: for (;;) {
      var line = _getLine(curPos.line);
      if (line.markedSpans != null) {
        for (var i = 0; i < line.markedSpans.length; ++i) {
          var sp = line.markedSpans[i];
          TextMarker m = sp.marker;
          if ((sp.from == null || (m.inclusiveLeft ? sp.from <= curPos.char : sp.from < curPos.char)) &&
              (sp.to == null || (m.inclusiveRight ? sp.to >= curPos.char : sp.to > curPos.char))) {
            if (mayClear) {
              signal(m, "beforeCursorEnter");
              if (m.explicitlyCleared) {
                if (line.markedSpans == null) break;
                else {--i; continue;}
              }
            }
            if (!m.atomic) continue;
            Pos newPos = m.find(dir < 0 ? -1 : 1);
            if (cmp(newPos, curPos) == 0) {
//              newPos.char += dir;
              newPos = new Pos(newPos.line, newPos.char + dir);
              if (newPos.char < 0) {
                if (newPos.line > first) newPos = clipPos(new Pos(newPos.line - 1));
                else newPos = null;
              } else if (newPos.char > line.text.length) {
                if (newPos.line < first + size - 1) newPos = new Pos(newPos.line + 1, 0);
                else newPos = null;
              }
              if (newPos == null) {
                if (flipped) {
                  // Driven in a corner -- no valid cursor position found at all
                  // -- try again *with* clearing, if we didn't already
                  if (!mayClear) return skipAtomic(pos, bias, true);
                  // Otherwise, turn off editing until further notice, and return the start of the doc
                  cantEdit = true;
                  return new Pos(first, 0);
                }
                flipped = true; newPos = pos; dir = -dir;
              }
            }
            curPos = newPos;
            continue search;
          }
        }
      }
      return curPos;
    }
  }

  // Pop all selection events off the end of a history array. Stop at
  // a change event.
  void clearSelectionEvents(List array) {
    while (array.length > 0) {
      var last = lst(array);
      if (last.isSelection) array.removeLast();
      else break;
    }
  }

  bool lineIsHidden(Line line) {
    return line.isHidden();
  }
  MarkedSpan getMarkedSpansFor(spans, TextMarker mark) {
    return mark.getMarkedSpanFor(spans);
  }

  // Used for the algorithm that adjusts markers for a change in the
  // document. These functions cut an array of spans at a given
  // character position, returning an array of remaining chunks (or
  // undefined if nothing remains).
  List<MarkedSpan>markedSpansBefore(List<MarkedSpan>old, int startCh, bool isInsert) {
    List<MarkedSpan> nw = [];
    if (old != null) {
      for (var i = 0; i < old.length; ++i) {
        var span = old[i], marker = span.marker;
        var startsBefore = span.from == null || (marker.inclusiveLeft ? span.from <= startCh : span.from < startCh);
        if (startsBefore || span.from == startCh && marker.type == "bookmark" && (!isInsert || !span.marker.insertLeft)) {
          var endsAfter = span.to == null || (marker.inclusiveRight ? span.to >= startCh : span.to > startCh);
          nw.add(new MarkedSpan(marker, span.from, endsAfter ? null : span.to));
        }
      }
    }
    return nw.isEmpty ? null : nw;
  }
  List<MarkedSpan>markedSpansAfter(List<MarkedSpan> old, int endCh, bool isInsert) {
    List<MarkedSpan> nw = [];
    if (old != null) {
      for (var i = 0; i < old.length; ++i) {
        var span = old[i], marker = span.marker;
        var endsAfter = span.to == null || (marker.inclusiveRight ? span.to >= endCh : span.to > endCh);
        if (endsAfter || span.from == endCh && marker.type == "bookmark" && (!isInsert || span.marker.insertLeft)) {
          var startsBefore = span.from == null || (marker.inclusiveLeft ? span.from <= endCh : span.from < endCh);
          nw.add(new MarkedSpan(marker, startsBefore ? null : span.from - endCh,
                                                span.to == null ? null : span.to - endCh));
        }
      }
    }
    return nw.isEmpty ? null : nw;
  }

  // Given a change object, compute the new set of marker spans that
  // cover the line in which the change took place. Removes spans
  // entirely within the change, reconnects spans belonging to the
  // same marker that appear on both sides of the change, and cuts off
  // spans partially within the change. Returns an array of span
  // arrays with one element for each line in (after) the change.
  List<List<MarkedSpan>> stretchSpansOverChange(Change change) {
    if (change.full) return null;
    List<MarkedSpan> oldFirst = isLine(change.from.line) ? _getLine(change.from.line).markedSpans : null;
    List<MarkedSpan> oldLast = isLine(change.to.line) ? _getLine(change.to.line).markedSpans : null;
    if (oldFirst == null && oldLast == null) return null;

    var startCh = change.from.char;
    var endCh = change.to.char;
    var isInsert = cmp(change.from, change.to) == 0;
    // Get the spans that 'stick out' on both sides
    List<MarkedSpan> first = markedSpansBefore(oldFirst, startCh, isInsert);
    List<MarkedSpan> last = markedSpansAfter(oldLast, endCh, isInsert);

    // Next, merge those two ends
    var sameLine = change.text.length == 1;
    var offset = lst(change.text).length + (sameLine ? startCh : 0);
    if (first != null) {
      // Fix up .to properties of first
      for (var i = 0; i < first.length; ++i) {
        MarkedSpan span = first[i];
        if (span.to == null) {
          MarkedSpan found = span.marker.getMarkedSpanFor(last);
          if (found == null) span.to = startCh;
          else if (sameLine) span.to = found.to == null ? null : found.to + offset;
        }
      }
    }
    if (last != null) {
      // Fix up .from in last (or move them into first in case of sameLine)
      for (var i = 0; i < last.length; ++i) {
        var span = last[i];
        if (span.to != null) span.to += offset;
        if (span.from == null) {
          MarkedSpan found = span.marker.getMarkedSpanFor(first);
          if (found == null) {
            span.from = offset;
            if (sameLine) {
              if (first == null) first = [];
              first.add(span);
            }
          }
        } else {
          span.from += offset;
          if (sameLine) {
            if (first == null) first = [];
            first.add(span);
          }
        }
      }
    }
    // Make sure we didn't create any zero-length spans
    if (first != null) first = clearEmptySpans(first);
    if (last != null && last != first) last = clearEmptySpans(last);

    var newMarkers = [first];
    if (!sameLine) {
      // Fill gap with whole-line-spans
      var gap = change.text.length - 2;
      List<MarkedSpan> gapMarkers;
      if (gap > 0 && first != null)
        for (var i = 0; i < first.length; ++i)
          if (first[i].to == null) {
            if (gapMarkers == null) gapMarkers = [];
            gapMarkers.add(new MarkedSpan(first[i].marker, null, null));
          }
      for (var i = 0; i < gap; ++i)
        newMarkers.add(gapMarkers);
      newMarkers.add(last);
    }
    return newMarkers;
  }

  // Remove spans that are empty and don't have a clearWhenEmpty
  // option of false.
  List<Span> clearEmptySpans(List<Span> spans) {
    for (var i = 0; i < spans.length; ++i) {
      var span = spans[i];
      if (span.from != null && span.from == span.to && span.marker.clearWhenEmpty != false)
        spans.removeAt(i--);
    }
    if (spans.isEmpty) return null;
    return spans;
  }

  // Used for un/re-doing changes from the history. Combines the
  // result of computing the existing spans with the set of spans that
  // existed in the history (so that deleting around a span and then
  // undoing brings back the span).
  mergeOldSpans(change) {
    List old = getOldSpans(change);
    List stretched = stretchSpansOverChange(change);
    if (old == null) return stretched;
    if (stretched == null) return old;

    for (var i = 0; i < old.length; ++i) {
      List oldCur = old[i], stretchCur = stretched[i];
      if (oldCur != null && stretchCur != null) {
        spans: for (var j = 0; j < stretchCur.length; ++j) {
          var span = stretchCur[j];
          for (var k = 0; k < oldCur.length; ++k)
            if (oldCur[k].marker == span.marker) continue spans;
          oldCur.add(span);
        }
      } else if (stretchCur != null) {
        old[i] = stretchCur;
      }
    }
    return old;
  }

  // Used to 'clip' out readOnly ranges when making a change.
  removeReadOnlyRanges(from, to) {
    List markers = null;
    iter(from.line, to.line + 1, (Line line) {
      if (line.markedSpans != null) {
        for (var i = 0; i < line.markedSpans.length; ++i) {
          var mark = line.markedSpans[i].marker;
          if (mark.readOnly && (markers == null || markers.indexOf(mark) == -1)) {
            if (markers == null) markers = [];
            markers.add(mark);
          }
        }
      }
    });
    if (markers == null) return null;
    List parts = [new Span(from, to)];
    for (var i = 0; i < markers.length; ++i) {
      var mk = markers[i], m = mk.find(0);
      for (var j = 0; j < parts.length; ++j) {
        var p = parts[j];
        if (cmp(p.to, m.from) < 0 || cmp(p.from, m.to) > 0) continue;
        var newParts = [/*j, 1*/];
        var dfrom = cmp(p.from, m.from), dto = cmp(p.to, m.to);
        if (dfrom < 0 || !mk.inclusiveLeft && dfrom == 0)
          newParts.add(new Span(p.from, m.from));
        if (dto > 0 || !mk.inclusiveRight && dto == 0)
          newParts.add(new Span(m.to, p.to));
        parts.removeAt(j);
        parts.addAll(newParts);
        j += newParts.length - 1;
      }
    }
    return parts;
  }

  // Test whether there exists a collapsed span that partially
  // overlaps (covers the start or end, but not both) of a new span.
  // Such overlap is not allowed.
  bool conflictingCollapsedRange(lineNo, from, to, marker) {
    var line = _getLine(lineNo);
    List<MarkedSpan> sps = sawCollapsedSpans ? line.markedSpans : null;
    if (sps != null) {
      for (var i = 0; i < sps.length; ++i) {
        var sp = sps[i];
        if (!sp.marker.collapsed) continue;
        var found = sp.marker.find(0);
        var fromCmp = cmp(found.from, from);
        if (fromCmp == 0) fromCmp = Line.extraLeft(sp.marker) - Line.extraLeft(marker);
        var toCmp = cmp(found.to, to);
        if (toCmp == 0) toCmp = Line.extraRight(sp.marker) - Line.extraRight(marker);
        if (fromCmp >= 0 && toCmp <= 0 || fromCmp <= 0 && toCmp >= 0) continue;
        if (fromCmp <= 0 && (cmp(found.to, from) > 0 || (sp.marker.inclusiveRight && marker.inclusiveLeft)) ||
            fromCmp >= 0 && (cmp(found.from, to) < 0 || (sp.marker.inclusiveLeft && marker.inclusiveRight))) {
          return true;
        }
      }
    }
    return false;
  }

  // Get the line number of the start of the visual line that the
  // given line number is part of.
  int visualLineNo(int lineN) {
    var line = _getLine(lineN), vis = line.visualLine();
    if (line == vis) return lineN;
    return lineNo(vis);
  }
  // Get the line number of the start of the next visual line after
  // the given line.
  int visualLineEndNo(int lineN) {
    if (lineN > lastLine()) return lineN;
    var line = _getLine(lineN), merged;
    if (!line.isHidden()) return lineN;
    while ((merged = line.collapsedSpanAtEnd()) != null) {
      line = merged.find(1, true).line;
    }
    return lineNo(line) + 1;
  }
}

// Collapsed markers have unique ids, in order to be able to order
// them, which is needed for uniquely determining an outer marker
// when they overlap (they may nest, but not partially overlap).
var nextMarkerId = 0;

// Create a marker, wire it up to the right lines
AbstractTextMarker _markText(Document doc, from, to, TextMarkerOptions options, type) {
  // Shared markers (across linked documents) are handled separately
  // (markTextShared will call out to this again, once per
  // document).
  if (options != null && options.shared) {
    return SharedTextMarker.markTextShared(doc, from, to, options, type);
  }
  // Ensure we are in an operation.
  if (doc.cm != null && doc.cm.curOp == null) {
    return doc.cm.doOperation(() => _markText(doc, from, to, options, type));
  }

  TextMarker marker = new TextMarker(doc, type, options);
  var diff = cmp(from, to);
  // Don't connect empty markers unless clearWhenEmpty is false
  if (diff > 0 || diff == 0 && marker.clearWhenEmpty != false)
    return marker;
  if (marker.replacedWith != null) {
    // Showing up as a widget implies collapsed (widget replaces text)
    marker.collapsed = true;
    marker.widgetNode = eltspan([marker.replacedWith], "CodeMirror-widget");
    // NOTE: Using dataset to add ignoreEvents and insertLeft to Elements?
    if (!options.handleMouseEvents) _doIgnoreEvents(marker.widgetNode);
    if (options.insertLeft) _doInsertLeft(marker.widgetNode);
  }
  if (marker.collapsed) {
    if (doc.conflictingCollapsedRange(from.line, from, to, marker) ||
        from.line != to.line && doc.conflictingCollapsedRange(to.line, from, to, marker))
      throw new StateError("Inserting collapsed marker partially overlapping an existing one");
    sawCollapsedSpans = true;
  }
  if (marker.addToHistory) {
    var change = new Change(from, to, null, "markText");
    doc.addChangeToHistory(change, doc.sel, double.NAN);
  }
  var curLine = from.line;
  bool updateMaxLine = false;
  CodeEditor cm = doc.cm;
  doc.iter(curLine, to.line + 1, (Line line) {
    if (cm != null && marker.collapsed && !cm.options.lineWrapping && line.visualLine() == cm.display.maxLine)
      updateMaxLine = true;
    if (marker.collapsed && curLine != from.line) line.updateLineHeight(0);
    line.addMarkedSpan(new MarkedSpan(marker,
                                      curLine == from.line ? from.char : null,
                                      curLine == to.line ? to.char : null));
    ++curLine;
  });
  // lineIsHidden depends on the presence of the spans, so needs a second pass
  if (marker.collapsed) {
    doc.iter(from.line, to.line + 1, (Line line) {
      if (doc.lineIsHidden(line)) line.updateLineHeight(0);
    });
  }

  if (marker.clearOnEnter) {
    marker.on(marker, "beforeCursorEnter", () { marker.clear(); });
  }

  if (marker.readOnly) {
    sawReadOnlySpans = true;
    if (doc.history.done.length != 0 || doc.history.undone.length != 0)
      doc.clearHistory();
  }
  if (marker.collapsed) {
    marker.id = ++nextMarkerId;
    marker.atomic = true;
  }
  if (cm != null) {
    // Sync editor state
    if (updateMaxLine) cm.curOp.updateMaxLine = true;
    if (marker.collapsed)
      cm.regChange(from.line, to.line + 1);
    else if (marker.affectsLayout())
      for (var i = from.line; i <= to.line; i++) cm.regLineChange(i, "text");
    if (marker.atomic) cm.doc.reCheckSelection();
    cm.signalLater(cm, "markerAdded", cm, marker);
  }
  return marker;
}

// Fed to the mode parsers, provides helper functions to make
// parsers more succinct.
class StringStream {
  int pos;
  int start;
  String string;
  int tabSize;
  int lastColumnPos;
  int lastColumnValue;
  int lineStart;

  StringStream(String string, [int tabSize = 0]) {
    this.pos = this.start = 0;
    this.string = string;
    this.tabSize = tabSize == 0 ? 8 : tabSize;
    this.lastColumnPos = this.lastColumnValue = 0;
    this.lineStart = 0;
  }

  bool eol() {
    return pos >= string.length;
  }
  bool sol() {
    return pos == lineStart;
  }
  String peek() {
    if (pos >= string.length) return null;
    return string.substring(pos, pos + 1);
  }
  String next() {
    if (pos < string.length) {
      return string.substring(pos, ++pos);
    } else {
      return null;
    }
  }
  String eat(match) {
    if (pos >= string.length) return null;
    String ch = string.substring(pos, pos + 1);
    bool ok;
    if (match is String) ok = ch == match;
    else if (match is RegExp) ok = match.hasMatch(ch);
    else ok = match(ch);
    if (ok) {
      ++pos;
      return ch;
    }
    return null;
  }
  bool eatWhile(match) {
    var start = pos;
    while (eat(match) != null) {}
    return pos > start;
  }
  bool eatSpace() {
    int start = pos;
    while (pos < string.length && new RegExp(r'[\s\u00a0]').hasMatch(string.substring(pos, pos + 1))) {
      ++pos;
    }
    return pos > start;
  }
  void skipToEnd() {
    pos = string.length;
  }
  bool skipTo(ch) {
    int found = string.indexOf(ch, pos);
    if (found > -1) {
      pos = found;
      return true;
    } else {
      return false;
    }
  }
  void backUp(n) {
    pos -= n;
  }
  int column() {
    if (lastColumnPos < start) {
      lastColumnValue = countColumn(string, start, tabSize, lastColumnPos,
          lastColumnValue);
      lastColumnPos = start;
    }
    return lastColumnValue -
        (lineStart > 0 ? countColumn(this.string, lineStart, tabSize) : 0);
  }
  int indentation() {
    return countColumn(string, null, tabSize) -
      (lineStart > 0 ? countColumn(string, lineStart, tabSize) : 0);
  }
  dynamic match(pattern, [bool consume = true, bool caseInsensitive = false]) {
    if (pattern is String) {
      String cased(str) { return caseInsensitive ? str.toLowerCase() : str; };
      // CodeMirror has a bug on the next line. It does not add pos to length.
      var substr = string.substring(pos, min(pos + pattern.length, string.length));
      if (cased(substr) == cased(pattern)) {
        if (consume != false) pos += pattern.length;
        return true;
      }
    } else {
      Match mat = (pattern as RegExp).matchAsPrefix(string.substring(pos));
      if (mat == null) return null;
      if (consume != false) pos += mat.end;
      return mat;
    }
    return null;
  }
  String current() {
    return string.substring(start, pos);
  }
  dynamic hideFirstChars(n, inner) {
    lineStart += n;
    try {
      return inner();
    } finally {
      lineStart -= n;
    }
  }
}

abstract class AbstractTextMarker extends Object with EventManager {
  bool explicitlyCleared = false;
  AbstractTextMarker parent;
  int height;

  find([int side, bool lineObj]);
  clear();
}

// Created with markText and setBookmark methods. A TextMarker is a
// handle that can be used to clear or find a marked position in the
// document. Line objects hold arrays (markedSpans) containing
// {from, to, marker} object pointing to such marker objects, and
// indicating that such a marker is present on that line. Multiple
// lines may point to the same marker when it spans across lines.
// The spans will have null for their from/to properties when the
// marker continues beyond the start/end of the line. Markers have
// links back to the lines they currently touch.
class TextMarker extends AbstractTextMarker {
  int id;
  List<Line> lines;
  String type; // 'range' or 'bookmark'
  Document doc;
  bool collapsed = false;
  SpanElement widgetNode;
  bool clearWhenEmpty = false;
  bool clearOnEnter = false;
  Node replacedWith;
  bool handleMouseEvents = false;
  bool addToHistory = false;
  String className;
  String title;
  String startStyle;
  String endStyle;
  bool atomic = false;
  bool readOnly = false;
  bool inclusiveLeft = false, inclusiveRight = false, insertLeft = false;
  bool shared = false;
  String css;
  var isFold;

  TextMarker(this.doc, this.type, TextMarkerOptions options) {
    this.lines = [];
    if (options != null) {
      collapsed = options.collapsed;
      clearWhenEmpty = options.clearWhenEmpty;
      clearOnEnter = options.clearOnEnter;
      replacedWith = options.replacedWith;
      handleMouseEvents = options.handleMouseEvents;
      addToHistory = options.addToHistory;
      className = options.className;
      title = options.title;
      startStyle = options.startStyle;
      endStyle = options.endStyle;
      atomic = options.atomic;
      readOnly = options.readOnly;
      inclusiveLeft = options.inclusiveLeft;
      inclusiveRight = options.inclusiveRight;
      insertLeft = options.insertLeft;
      shared = options.shared;
      css = options.css;
    }
    isFold = false;
  }

  OperationGroup get operationGroup => doc.operationGroup;

  // Clear the marker.
  void clear() {
    if (explicitlyCleared) return;
    CodeEditor cm = doc.cm;
    bool withOp = cm != null && cm.curOp == null;
    if (withOp) cm.startOperation(cm);
    if (hasHandler(this, "clear")) {
      var found = find();
      if (found != null) signalLater(this, "clear", found.from, found.to);
    }
    int min = -1, max = -1;
    for (int i = 0; i < this.lines.length; ++i) {
      var line = this.lines[i];
      var span = getMarkedSpanFor(line.markedSpans);
      if (cm != null && !collapsed) cm.regLineChange(line.lineNo(), "text");
      else if (cm != null) {
        if (span.to != null) max = line.lineNo();
        if (span.from != null) min = line.lineNo();
      }
      line.markedSpans = line.removeMarkedSpan(span);
      if (span.from == null && this.collapsed &&
          !doc.lineIsHidden(line) && cm != null)
        line.updateLineHeight(cm.display.textHeight());
    }
    if (cm != null && this.collapsed && !cm.options.lineWrapping) {
      for (var i = 0; i < this.lines.length; ++i) {
        Line visual = lines[i].visualLine();
        var len = visual.lineLength();
        if (len > cm.display.maxLineLength) {
          cm.display.maxLine = visual;
          cm.display.maxLineLength = len;
          cm.display.maxLineChanged = true;
        }
      }
    }

    if (min >= 0 && cm != null && collapsed) cm.regChange(min, max + 1);
    lines.length = 0;
    explicitlyCleared = true;
    if (atomic && doc.cantEdit) {
      doc.cantEdit = false;
      if (cm != null) cm.doc.reCheckSelection();
    }
    if (cm != null) signalLater(cm, "markerCleared", cm, this);
    if (withOp) cm.endOperation(cm);
    if (parent != null) parent.clear();
  }

  // Find the position of the marker in the document. Returns a {from,
  // to} object by default. Side can be passed to get a specific side
  // -- 0 (both), -1 (left), or 1 (right). When lineObj is true, the
  // Pos objects returned contain a line object, rather than a line
  // number (used to prevent looking up the same line twice).
  dynamic find([int side, bool lineObj = false]) {
    if (side == null) {
      side = (type == "bookmark") ? 1 : 0;
    }
    var from, to;
    for (int i = 0; i < lines.length; ++i) {
      var line = lines[i];
      var span = getMarkedSpanFor(line.markedSpans);
      if (span.from != null) {
        if (lineObj) {
          from = new LinePos(line, span.from);
        } else {
          from = new Pos(line.lineNo(), span.from);
        }
        if (side == -1) return from;
      }
      if (span.to != null) {
        if (lineObj) {
          to = new LinePos(line, span.to);
        } else {
          to = new Pos(line.lineNo(), span.to);
        }
        if (side == 1) return to;
      }
    }
    if (from != null) {
      return new Span(from, to);
    } else {
      return null;
    }
  }

  // Signals that the marker's widget changed, and surrounding layout
  // should be recomputed.
  void changed() {
    var pos = find(-1, true), widget = this;
    CodeEditor cm = doc.cm;
    if (pos == null || cm == null) return;
    cm.runInOp(cm, () {
      Line line = pos.line;
      int lineN = pos.line.lineNo();
      var view = doc.findViewForLine(lineN);
      if (view != null) {
        doc.clearLineMeasurementCacheFor(view);
        cm.curOp.selectionChanged = cm.curOp.forceUpdate = true;
      }
      cm.curOp.updateMaxLine = true;
      if (!widget.doc.lineIsHidden(line) && widget.height != null) {
        var oldHeight = widget.height;
        widget.height = 0;
        var dHeight = widget.widgetHeight() - oldHeight;
        if (dHeight)
          line.updateLineHeight(line.height + dHeight);
      }
    });
  }

  widgetHeight() {
    // NOTE: This is derived from LineWidget.widgetHeight().
    if (height != null) return height;
    if (!contains(document.body, widgetNode)) {
      var parentStyle = "position: relative;";
      removeChildrenAndAdd(doc.cm.display.measure,
          eltdiv([widgetNode], null, parentStyle));
    }
    return height = widgetNode.offsetHeight;
  }

  void attachLine(Line line) {
    if (lines.length != 0 && doc.cm != null) {
      var op = doc.cm.curOp;
      var hidden = op.maybeHiddenMarkers;
      if (hidden == null || hidden.indexOf(this) == -1) {
        if (op.maybeUnhiddenMarkers == null) op.maybeUnhiddenMarkers = [];
        op.maybeUnhiddenMarkers.add(this);
      }
    }
    lines.add(line);
  }
  void detachLine(Line line) {
    lines.remove(line);
    if (lines.length != 0 && doc.cm != null) {
      var op = doc.cm.curOp;
      if (op.maybeHiddenMarkers == null) op.maybeHiddenMarkers = [];
      op.maybeHiddenMarkers.add(this);
    }
  }

  bool affectsLayout() {
    return className != null || title != null ||
        startStyle != null || endStyle != null || css != null;
  }

  // Search an array of spans for a span matching the given marker.
  MarkedSpan getMarkedSpanFor(List<MarkedSpan> spans) {
    if (spans == null) return null;
    for (var i = 0; i < spans.length; ++i) {
      var span = spans[i];
      if (span.marker == this) return span;
    }
    return null;
  }

  TextMarkerOptions options() {
    return new TextMarkerOptions(
        collapsed: collapsed, clearWhenEmpty: clearWhenEmpty, clearOnEnter: clearOnEnter,
        replacedWith: replacedWith, handleMouseEvents: handleMouseEvents, addToHistory: addToHistory,
        className: className, title: title, startStyle: startStyle, endStyle: endStyle, atomic: atomic,
        readOnly: readOnly, inclusiveLeft: inclusiveLeft, inclusiveRight: inclusiveRight, shared: shared,
        insertLeft: insertLeft, widgetNode: widgetNode, css: css
    );
  }

}

// A shared marker spans multiple linked documents. It is
// implemented as a meta-marker-object controlling multiple normal
// markers.
class SharedTextMarker extends AbstractTextMarker {
  List<TextMarker> markers;
  TextMarker primary;

  OperationGroup get operationGroup {
    if (primary.operationGroup != null) return primary.operationGroup;
    for (int i = 0; i < markers.length; i++) {
      var group = markers[i].operationGroup;
      if (group != null) {
        return group;
      }
    }
    return null; // This should not happen, but might if a coding error fails to establish an operation.
  }

  SharedTextMarker(this.markers, this.primary) {
    for (var i = 0; i < markers.length; ++i) {
      markers[i].parent = this;
    }
  }

  void clear() {
    if (explicitlyCleared) return;
    explicitlyCleared = true;
    for (var i = 0; i < markers.length; ++i)
      markers[i].clear();
    signalLater(this, "clear");
  }
  dynamic find([int side = 0, bool lineObj = false]) {
    return primary.find(side, lineObj);
  }

  static SharedTextMarker markTextShared(Document doc, from, to, TextMarkerOptions options, type) {
    options = options.copy();
    options.shared = false;
    List<TextMarker> markers = [_markText(doc, from, to, options, type)];
    TextMarker primary = markers[0];
    var widget = options.widgetNode;
    doc.linkedDocs(doc, (Document doc, bool shared) {
      if (widget != null) options.widgetNode = widget.clone(true);
      markers.add(_markText(doc, doc.clipPos(from), doc.clipPos(to), options, type));
      for (var i = 0; i < doc.linked.length; ++i)
        if (doc.linked[i].isParent) return;
      primary = lst(markers);
    });
    return new SharedTextMarker(markers, primary);
  }

  static List<TextMarker> findSharedMarkers(Document doc) {
    return doc.findMarks(
        new Pos(doc.first, 0),
        doc.clipPos(new Pos(doc.lastLine())),
        (m) { return m.parent; });
  }

  static copySharedMarkers(doc, markers) {
    for (var i = 0; i < markers.length; i++) {
      var marker = markers[i], pos = marker.find();
      var mFrom = doc.clipPos(pos.from), mTo = doc.clipPos(pos.to);
      if (cmp(mFrom, mTo) != 0) {
        var subMark = _markText(doc, mFrom, mTo, marker.primary.options(), marker.primary.type);
        marker.markers.add(subMark);
        subMark.parent = marker;
      }
    }
  }

  static detachSharedMarkers(markers) {
    for (var i = 0; i < markers.length; i++) {
      var marker = markers[i], linked = [marker.primary.doc];
      marker.primary.doc.linkedDocs(marker.primary.doc, (d) { linked.add(d); });
      for (var j = 0; j < marker.markers.length; j++) {
        var subMarker = marker.markers[j];
        if (linked.indexOf(subMarker.doc) == -1) {
          subMarker.parent = null;
          marker.markers.removeAt(j--);
        }
      }
    }
  }
}

abstract class HistoryItem {
  bool get isSelection;
}

// {changes: changes, generation: n}
class HistoryEvent implements HistoryItem {
  List<Change> changes;
  int generation;

  HistoryEvent(this.changes, [this.generation]);

  bool get isSelection => false;
}

// {done: d, undone: u}
class HistoryRecord {
  List<HistoryItem> done, undone;
  HistoryRecord(this.done, this.undone);
}

class History extends HistoryRecord {
  num undoDepth;
  int lastModTime, lastSelTime;
  Object lastOp, lastSelOp;
  Object lastOrigin, lastSelOrigin;
  int generation, maxGeneration;

  History([int startGen = 1]) : super([], []) {
    // Arrays of change events and selections. Doing something adds an
    // event to done and clears undo. Undoing moves events from done
    // to undone, redoing moves them in the other direction.
    undoDepth = double.INFINITY;
    // Used to track when changes can be merged into a single undo
    // event
    lastModTime = lastSelTime = 0;
    lastOp = lastSelOp = null;
    lastOrigin = lastSelOrigin = null;
    // Used by the isClean() method
    if (startGen == null) startGen = 1;
    generation = maxGeneration = startGen;
  }

  // Create a history change event from an updateDoc-style change
  // object.
  static Change historyChangeFromChange(Document doc, Change change) {
    Pos to = doc.changeEnd(change);
    var text = doc.getBetween(change.from, change.to);
    var histChange = new Change(copyPos(change.from), to, text);
    doc.attachLocalSpans(histChange, change.from.line, change.to.line + 1);
    doc.linkedDocs(doc, (Document doc, bool shared) {
        doc.attachLocalSpans(histChange, change.from.line, change.to.line + 1);
      },
      true);
    return histChange;
  }
}

// Classes derived from property maps

class DocumentLink {
  Document doc;
  bool sharedHist;
  bool isParent;
  DocumentLink(this.doc, this.sharedHist, [this.isParent = false]);
}

class TextMarkerOptions {
  bool collapsed;
  bool clearWhenEmpty;
  bool clearOnEnter;
  Node replacedWith;
  bool handleMouseEvents;
  bool addToHistory;
  String className;
  String title;
  String startStyle;
  String endStyle;
  bool atomic;
  bool readOnly;
  bool inclusiveLeft;
  bool inclusiveRight;
  bool shared;
  bool insertLeft; // NOTE: Not sure this is used other than setBookmark()
  Element widgetNode;
  String css;

  TextMarkerOptions({this.collapsed: false, this.clearWhenEmpty: false, this.clearOnEnter: false,
      this.replacedWith, this.handleMouseEvents: false, this.addToHistory: false,
      this.className, this.title, this.startStyle, this.endStyle, this.atomic: false,
      this.readOnly: false, this.inclusiveLeft: false, this.inclusiveRight: false, this.shared: false,
      this.insertLeft: false, this.widgetNode, this.css});

  TextMarkerOptions copy() {
    var copy = new TextMarkerOptions();
    copy.collapsed = collapsed;
    copy.clearWhenEmpty = clearWhenEmpty;
    copy.clearOnEnter = clearOnEnter;
    copy.replacedWith = replacedWith;
    copy.handleMouseEvents = handleMouseEvents;
    copy.addToHistory = addToHistory;
    copy.className = className;
    copy.title = title;
    copy.startStyle = startStyle;
    copy.endStyle = endStyle;
    copy.atomic = atomic;
    copy.readOnly = readOnly;
    copy.inclusiveLeft = inclusiveLeft;
    copy.inclusiveRight = inclusiveRight;
    copy.shared = shared;
    copy.insertLeft = insertLeft;
    copy.widgetNode = widgetNode;
    return copy;
  }
}

// {from: start, to: start, text: text, origin: "setValue"}
class Change implements HistoryItem {
  Pos from, to;
  List<String> text;
  String origin;
  var removed;
  Map<int,List<MarkedSpan>> named = new Map();
  bool full;

  Change(this.from, this.to, this.text, [this.origin, this.removed, this.full = false]);

  bool get isSelection => false;
  operator [](key) => named[key];
  operator []=(key, value) { named[key] = value; }
}

// The objects are passed as a parameter to the "beforeChange" event handlers.
class ChangeFilter {
  bool _canceled;
  Pos _from;
  Pos _to;
  var _text;
  var _origin;
  final bool _updateable;
  final Document _doc;

  bool get canceled => _canceled;
  bool get updateable => _updateable;
  Pos get from => _from;
  Pos get to => _to;
  get text => _text;
  get origin => _origin;

  ChangeFilter(Change change, this._updateable, this._doc) {
    if (!_updateable) return;
    _canceled = false;
    _from = change.from;
    _to = change.to;
    _text = change.text;
    _origin = change.origin;
  }

  void cancel() { _canceled = true; }

  update([Pos from, Pos to, text, origin]) {
    if (_updateable) {
      if (from != null) _from = _doc.clipPos(from);
      if (to != null) _to = _doc.clipPos(to);
      if (text != null) _text = text;
      if (origin != null) _origin = origin;
    }
  }
}

// {from: from, to: to}
class Span {
  var from; // int or null
  var to; // int or null
  Span(this.from, this.to);
  String toString() => 'Span($from, $to)';
}

class LabeledSpan extends Span {
  String origin;
  LabeledSpan(from, to, this.origin) : super(from, to);
}

// {from: from, to: to, origin: "markText"}
class MarkedSpan extends Span {
  TextMarker marker;
  MarkedSpan(this.marker, from, to) : super(from, to);
}

// {start: start, string: string, type: type, state: state}
class Token {
  int start, end;
  String string;
  var type, state;
  Token(this.start, this.end, this.string, this.type, this.state);
}

// {styles: st classes: null}
class LineHighlight {
  List<String> styles;
  var classes;
  LineHighlight(this.styles, this.classes);
}

// {left: left, top: top}
class Loc {
  num left, top;
  Loc(this.top, this.left);
  String toString() => 'Loc($top, $left)';
}

// {undo: done, redo: undone}
class HistorySize {
  int undo, redo;
  HistorySize(this.undo, this.redo);
}

// {line: line, view: view, rect: null,
//  map: info.map, cache: info.cache, before: info.before,
//  hasHeights: false}
class LineMeasurement {
  Line line;
  var view, rect,
        cache, before,
        hasHeights;
  List heights;
  int width;
  List map;
  List<List> maps;
  List<Map> caches;
  LineMeasurement([this.line, this.view, this.rect, this.map, this.cache,
      this.before, this.hasHeights]);
}

// {map: measure.maps[i], cache: measure.caches[i], before: true}
class LineMap {
  var map;
  var cache;
  bool before;
  LineMap(this.map, this.cache, [this.before]);
}

class BookmarkOptions {
  Node widget;
  bool insertLeft, shared;
  BookmarkOptions({this.widget, this.insertLeft: false, this.shared: false});
}
