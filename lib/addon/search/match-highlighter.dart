// Copyright (c) 2015, the Comid Authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library comid.match;

import 'dart:html';
import 'dart:math';
import 'package:comid/codemirror.dart';
import 'package:comid/addon/search/search.dart'
    show Overlay, SearchMatch, getSearchCursor;

// Highlighting text that matches the selection
//
// Defines an option highlightSelectionMatches, which, when enabled,
// will style strings that match the selection throughout the
// document.
//
// The option can be set to true to simply enable it, or to a
// {minChars, style, wordsOnly, showToken, delay} object to explicitly
// configure it. minChars is the minimum amount of characters that should be
// selected for the behavior to occur, and style is the token style to
// apply to the matches. This will be prefixed by "cm-" to create an
// actual CSS class name. If wordsOnly is enabled, the matches will be
// highlighted only if the selected text is a word. showToken, when enabled,
// will cause the current token to be highlighted when nothing is selected.
// delay is used to specify how much time to wait, in milliseconds, before
// highlighting the matches.


const DEFAULT_MIN_CHARS = 2;
const DEFAULT_TOKEN_STYLE = "matchhighlight";
const DEFAULT_DELAY = 100;
const DEFAULT_WORDS_ONLY = false;
const DEFAULT_SEARCH_MATCH_CLASS_NAME = "CodeMirror-search-match";

class HighlightState {
  int minChars;
  String style;
  RegExp showToken;
  int delay;
  bool wordsOnly;
  var overlay;
  var timeout;

  HighlightState(options) {
    this.showToken = new RegExp(r'[\w$]');
    if (options is Map) {
      this.minChars = options['minChars'];
      this.style = options['style'];
      if (options.containsKey('showToken'))
        this.showToken = options['showToken']; // may be null
      this.delay = options['delay'];
      this.wordsOnly = options['wordsOnly'];
    }
    if (this.style == null) this.style = DEFAULT_TOKEN_STYLE;
    if (this.minChars == null) this.minChars = DEFAULT_MIN_CHARS;
    if (this.delay == null) this.delay = DEFAULT_DELAY;
    if (this.wordsOnly == null) this.wordsOnly = DEFAULT_WORDS_ONLY;
    this.overlay = this.timeout = null;
  }
}

initializeMatchHighlighting() {
  CodeMirror.defineOption("highlightSelectionMatches", false, (CodeMirror cm, val, old) {
    if (old != null && old != Options.Init) {
      var over = cm.state.matchHighlighter.overlay;
      if (over != null) cm.removeOverlay(over);
      clearTimeout(cm.state.matchHighlighter.timeout);
      cm.state.matchHighlighter = null;
      cm.off(cm, "cursorActivity", cursorActivity);
    }
    if (val != null) {
      cm.state.matchHighlighter = new HighlightState(val);
      highlightMatches(cm);
      cm.on(cm, "cursorActivity", cursorActivity);
    }
  });
}

void cursorActivity(CodeMirror cm) {
  HighlightState state = cm.state.matchHighlighter;
  clearTimeout(state.timeout);
  state.timeout = setTimeout(() {highlightMatches(cm);}, state.delay);
}

void highlightMatches(CodeMirror cm) {
  cm.operation(cm, () {
    HighlightState state = cm.state.matchHighlighter;
    if (state.overlay != null) {
      cm.removeOverlay(state.overlay);
      state.overlay = null;
    }
    if (!cm.somethingSelected() && state.showToken != null) {
      var re = state.showToken;
      var cur = cm.getCursor(), line = cm.getLine(cur.line), start = cur.char, end = start;
      while (start > 0 && re.hasMatch(line.substring(start - 1, start))) --start;
      while (end < line.length && re.hasMatch(line.substring(end, end + 1))) ++end;
      if (start < end)
        cm.addOverlay(state.overlay = makeOverlay(line.substring(start, end), re, state.style));
      return;
    }
    var from = cm.getCursor("from"), to = cm.getCursor("to");
    if (from.line != to.line) return;
    if (state.wordsOnly && !isWord(cm, from, to)) return;
    var selection = cm.getRange(from, to).replaceAll(new RegExp(r'^\s+|\s+$'), "");
    if (selection.length >= state.minChars)
      cm.addOverlay(state.overlay = makeOverlay(selection, null, state.style));
  })();
}

bool isWord(cm, from, to) {
  var str = cm.getRange(from, to);
  if (new RegExp(r'^\w+$').hasMatch(str) != null) {
      if (from.ch > 0) {
          var pos = new Pos(from.line, from.ch - 1);
          var chr = cm.getRange(pos, from);
          if (new RegExp(r'\W').hasMatch(chr) == null) return false;
      }
      if (to.ch < cm.getLine(from.line).length) {
          var pos = new Pos(to.line, to.ch + 1);
          var chr = cm.getRange(to, pos);
          if (new RegExp(r'\W').hasMatch(chr) == null) return false;
      }
      return true;
  } else {
    return false;
  }
}

bool boundariesAround(StringStream stream, RegExp re) {
  return (stream.start == 0 || !re.hasMatch(stream.string.substring(stream.start - 1, stream.start))) &&
    (stream.pos == stream.string.length || !re.hasMatch(stream.string.substring(stream.pos, stream.pos + 1)));
}

Overlay makeOverlay(String query, RegExp hasBoundary, style) {
  return new Overlay((StringStream stream) {
    if (stream.match(query) != null &&
        (hasBoundary == null || boundariesAround(stream, hasBoundary))) {
      return style;
    }
    stream.next();
    if (stream.skipTo(query.substring(0, 1)) == null) {
      stream.skipToEnd();
    }
  });
}

//// from matchonscrollbar

//  CodeMirror.defineExtension("showMatchesOnScrollbar", function(query, caseFold, className) {
showMatchesOnScrollbar(CodeMirror cm, query, caseFold, [options]) {
  if (options is String) options = new SearchOptions(className: options);
  if (options == null) options = new SearchOptions();
  return new SearchAnnotation(cm, query, caseFold, options);
}

class SearchAnnotation {
  CodeMirror cm;
  SearchOptions options;
  var annotation;
  var query;
  var caseFold;
  Span gap;
  List<SearchMatch> matches;
  var update;
  var changeHandler;

  SearchAnnotation(CodeMirror cm, query, bool caseFold, SearchOptions options) {
    this.cm = cm;
    this.options = options;
    if (options.listenForChanges == null) options.listenForChanges = false;
    if (options.className == null) options.className = DEFAULT_SEARCH_MATCH_CLASS_NAME;
    this.annotation = annotateScrollbar(cm, options);
    this.query = query;
    this.caseFold = caseFold;
    this.gap = new Span(cm.firstLine(), cm.lastLine() + 1);
    this.matches = [];
    this.update = null;

    findMatches();
    annotation.update(matches);

    changeHandler = (_cm, change) { onChange(change); };
    cm.on(cm, "change", changeHandler);
  }

  static const MAX_MATCHES = 1000;

  void findMatches() {
    if (gap == null) return;
    var i;
    for (i = 0; i < matches.length; i++) {
      var match = this.matches[i];
      if (match.from.line >= gap.to) break;
      if (match.to.line >= gap.from) matches.removeAt(i--);
    }
    var cursor = getSearchCursor(cm, query, new Pos(gap.from, 0), caseFold);
    int maxMatches = MAX_MATCHES;
    if (options != null && options.maxMatches > 0) {
      maxMatches = options.maxMatches;
    }
    while (cursor.findNext()) {
      var match = new SearchMatch(from: cursor.from(), to: cursor.to());
      if (match.from.line >= this.gap.to) break;
      matches.insert(i++, match);
      if (matches.length > maxMatches) break;
    }
    gap = null;
  }

  int offsetLine(int line, int changeStart, int sizeChange) {
    if (line <= changeStart) return line;
    return max(changeStart, line + sizeChange);
  }

  void onChange(Change change) {
    var startLine = change.from.line;
    var endLine = cm.changeEnd(change).line;
    var sizeChange = endLine - change.to.line;
    if (gap != null) {
      gap.from = min(offsetLine(gap.from, startLine, sizeChange), change.from.line);
      gap.to = max(offsetLine(gap.to, startLine, sizeChange), change.from.line);
    } else {
      gap =new Span(change.from.line, endLine + 1);
    }

    if (sizeChange) for (var i = 0; i < this.matches.length; i++) {
      var match = this.matches[i];
      var newFrom = offsetLine(match.from.line, startLine, sizeChange);
      if (newFrom != match.from.line) match.from = new Pos(newFrom, match.from.char);
      var newTo = offsetLine(match.to.line, startLine, sizeChange);
      if (newTo != match.to.line) match.to = new Pos(newTo, match.to.char);
    }
    clearTimeout(this.update);
    update = setTimeout(() { updateAfterChange(); }, 250);
  }

  void updateAfterChange() {
    findMatches();
    annotation.update(matches);
  }

  void clear() {
    cm.off(cm, "change", changeHandler);
    annotation.clear();
  }
}

//// from annotatescrollbar

//CodeMirror.defineExtension("annotateScrollbar", function(className) {
Annotation annotateScrollbar(CodeMirror cm, className) {
  return new Annotation(cm, className);
}

class Annotation {
  CodeMirror cm;
  SearchOptions options;
  int buttonHeight;
  List annotations;
  DivElement div;
  Function resizeHandler;
  Function changeHandler;
  num hScale;
  var doRedraw;
  var doUpdate;

  Annotation(CodeMirror cm, var options) {
    if (options is String) options = new SearchOptions(className: options);
    this.cm = cm;
    this.options = options as SearchOptions;
    this.buttonHeight = options.scrollButtonHeight;
    if (this.buttonHeight == 0) {
      this.buttonHeight = cm.getOption("scrollButtonHeight");
    }
    this.annotations = [];
    this.doRedraw = this.doUpdate = null;
    this.div = cm.getWrapperElement().append(document.createElement("div"));

    div.style.cssText = "position: absolute; right: 0; top: 0; z-index: 7; pointer-events: none";
    computeScale();

    scheduleRedraw(delay) {
      clearTimeout(this.doRedraw);
      this.doRedraw = setTimeout(() { this.redraw(); }, delay);
    }

    cm.on(cm, "refresh", resizeHandler = () {
      clearTimeout(doUpdate);
      doUpdate = setTimeout(() {
        if (computeScale()) scheduleRedraw(20);
      }, 100);
    });
    cm.on(cm, "markerAdded", resizeHandler);
    cm.on(cm, "markerCleared", resizeHandler);
    if (options.listenForChanges != false)
      cm.on(cm, "change", changeHandler = () {
        scheduleRedraw(250);
      });
  }

  bool computeScale() {
    var cm = this.cm;
    var hScale = (cm.getWrapperElement().clientHeight - cm.display.barHeight - buttonHeight * 2) /
      cm.heightAtLine(cm.lastLine() + 1, "local");
    if (hScale != this.hScale) {
      this.hScale = hScale;
      return true;
    }
    return false;
  }

  void update(annotations) {
    this.annotations = annotations;
    redraw();
  }

  void redraw([compute]) {
    if (compute != false) this.computeScale();
    var cm = this.cm, hScale = this.hScale;

    var frag = document.createDocumentFragment(), anns = this.annotations;

    bool wrapping = cm.getOption("lineWrapping");
    var singleLineH = wrapping ? cm.defaultTextHeight() * 1.5 : 0;
    var curLine = null, curLineObj = null;
    num getY(Pos pos, bool top) {
      if (curLine != pos.line) {
        curLine = pos.line;
        curLineObj = cm.getLineHandle(curLine);
      }
      if (wrapping && curLineObj.height > singleLineH) {
        var rect = cm.charCoords(pos, "local");
        return top ? rect.top : rect.bottom;
      }
      var topY = cm.heightAtLine(curLineObj, "local");
      return topY + (top ? 0 : curLineObj.height);
    }

    num nextTop = 0;
    if (cm.display.barWidth != 0) {
      for (var i = 0; i < anns.length; i++) {
        var ann = anns[i];
//        var top = nextTop;
//        if (top == 0) top = cm.charCoords(ann.from, "local").top * hScale;
//        var bottom = cm.charCoords(ann.to, "local").bottom * hScale;
        var top = nextTop != 0 ? nextTop : getY(ann.from, true) * hScale;
        var bottom = getY(ann.to, false) * hScale;
        while (i < anns.length - 1) {
          nextTop = getY(anns[i + 1].from, true) * hScale;
          if (nextTop > bottom + .9) break;
          ann = anns[++i];
          bottom = getY(ann.to, false) * hScale;
        }
        if (bottom == top) continue;
        var height = max(bottom - top, 3);

        DivElement elt = frag.append(document.createElement("div"));
        elt.style.cssText = "position: absolute; right: 0px; width: ${max(cm.display.barWidth - 1, 2)}px; top: ${top + buttonHeight}px; height: ${height}px";
        elt.className = options.className;
      }
    }
    div.text = "";
    div.append(frag);
  }

  void clear() {
    cm.off(cm, "refresh", resizeHandler);
    cm.off(cm, "markerAdded", resizeHandler);
    cm.off(cm, "markerCleared", resizeHandler);
    if (changeHandler != null) cm.off(cm, "change", changeHandler);
    div.remove();
  }
}

class SearchOptions {
  String className;
  bool listenForChanges;
  int scrollButtonHeight;
  int maxMatches;

  SearchOptions({this.className, this.listenForChanges: false,
    this.scrollButtonHeight: 0, this.maxMatches: 0});
}
