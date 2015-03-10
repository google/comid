// Copyright (c) 2015, the Comid Authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library comid.search;

import 'dart:math';
import 'package:comid/codemirror.dart';
import 'package:comid/addon/dialog/dialog.dart' as ui;
import 'package:comid/addon/search/match-highlighter.dart'
    show showMatchesOnScrollbar, initializeMatchHighlighting;

class Overlay extends Mode {
  var tokenFn;
  Overlay(this.tokenFn) {name = "Overlay";}
  token(stream, [b]) => tokenFn(stream);
}

Overlay searchOverlay(queryArg, [bool caseInsensitive = false]) {
  RegExp query;
    if (queryArg is String) {
      query = new RegExp(
          queryArg.replaceAllMapped(
              new RegExp(r'[\-\[\]\/\{\}\(\)\*\+\?\.\\\^\$\|]'),
              (s) => "\\$s"), caseSensitive: !caseInsensitive);
    } else if (queryArg is RegExp) {
      query = queryArg;
    } else {
      return null;
    }

    return new Overlay((stream) {
      //query.lastIndex = stream.pos;
      var match, matches = query.allMatches(stream.string, stream.pos);
      if (!matches.isEmpty) match = matches.first;
      if (match != null && match.start == stream.pos) {
        stream.pos += match[0].length;
        return "searching";
      } else if (match != null) {
        stream.pos = match.start;
      } else {
        stream.skipToEnd();
      }
    });
  }

class SearchState {
  Pos posFrom, posTo;
  dynamic query; // Pattern: String or RegExp
  var overlay, annotate;

  SearchState();
}

SearchState getSearchState(CodeMirror cm) {
  if (cm.state.search == null) cm.state.search = new SearchState();
  return cm.state.search;
}
bool queryCaseInsensitive(query) {
  return query is String && query == query.toLowerCase();
}
SearchCursor getSearchCursor(CodeMirror cm, query, [pos, caseFold]) {
  // Heuristic: if the query string is all lowercase, do a case insensitive search.
  if (caseFold == null) caseFold = queryCaseInsensitive(query);
  return new SearchCursor(cm.doc, query, pos, caseFold);
}
void dialog(CodeMirror cm, text, shortText, deflt, f) {
  ui.openDialog(cm, text, f, {'value': deflt});
}
void confirmDialog(CodeMirror cm, text, shortText, fs) {
  ui.openConfirm(cm, text, fs);
}
dynamic parseQuery(query) { // Pattern: String or RegExp
  var isRE = new RegExp(r'^\/(.*)\/([a-z]*)$').firstMatch(query);
  if (isRE != null) {
    try { query = new RegExp(isRE[1], caseSensitive: isRE[2].indexOf("i") != -1); }
    catch(e) {} // Not a regular expression after all, do a string search
  }
  if (query is String ? query == "" : query.hasMatch(""))
    query = new RegExp(r'x^');
  return query;
}

var queryDialog =
  'Search: <input type="text" style="width: 10em" class="CodeMirror-search-field"/> <span style="color: #888" class="CodeMirror-search-hint">(Use /re/ syntax for regexp search)</span>';

doSearch([CodeMirror cm, bool rev = false]) {
  if (cm == null) return;
  var state = getSearchState(cm);
  if (state.query != null) {
    findNext(cm, rev);
    return;
  }
  dialog(cm, queryDialog, "Search for:", cm.getSelection(), (query) {
    cm.operation(cm, () {
      if (query == null || state.query != null) return;
      state.query = parseQuery(query);
      cm.removeOverlay(state.overlay);
      state.overlay = searchOverlay(state.query, queryCaseInsensitive(state.query));
      cm.addOverlay(state.overlay);
      if (showMatchesOnScrollbar != null) {
        if (state.annotate != null) {
          state.annotate.clear();
          state.annotate = null;
        }
        state.annotate = showMatchesOnScrollbar(cm, state.query, queryCaseInsensitive(state.query));
      }
      state.posFrom = state.posTo = cm.getCursor();
      findNext(cm, rev);
    })();
  });
}
findNext(CodeMirror cm, [bool rev = false]) {
  cm.operation(cm, () {
    var state = getSearchState(cm);
    var cursor = getSearchCursor(cm, state.query, rev ? state.posFrom : state.posTo);
    if (!cursor.find(rev)) {
      cursor = getSearchCursor(cm, state.query, rev ? new Pos(cm.lastLine()) : new Pos(cm.firstLine(), 0));
      if (!cursor.find(rev)) return;
    }
    cm.setSelection(cursor.from(), cursor.to());
    cm.scrollIntoView(new Range(cursor.from(), cursor.to()));
    state.posFrom = cursor.from(); state.posTo = cursor.to();
  })();
}
clearSearch([CodeMirror cm]) {
  if (cm == null) return;
  cm.operation(cm, () {
    var state = getSearchState(cm);
    if (state.query == null) return;
    state.query = null;
    cm.removeOverlay(state.overlay);
    if (state.annotate != null) {
      state.annotate.clear();
      state.annotate = null;
    }
  })();
}

var replaceQueryDialog =
  'Replace: <input type="text" style="width: 10em" class="CodeMirror-search-field"/> <span style="color: #888" class="CodeMirror-search-hint">(Use /re/ syntax for regexp search)</span>';
var replacementQueryDialog = 'With: <input type="text" style="width: 10em" class="CodeMirror-search-field"/>';
var doReplaceConfirm = "Replace? <button>Yes</button> <button>No</button> <button>Stop</button>";

_extract(Match matchOfSubstIndex, Match matchToExtract) {
  int index = int.parse(matchOfSubstIndex[1]);
  if (index < 0 || index > matchToExtract.groupCount) return '';
  return matchToExtract[index];
}

// Undocumented feature: a query of '/(...)...(...)/' contains capture groups
// that can be re-arranged by a replacement like '$2...$1'
replace([CodeMirror cm, bool all = false]) {
  if (cm == null) return;
  if (cm.getOption("readOnly")) return;
  dialog(cm, replaceQueryDialog, "Replace:", cm.getSelection(), (query) {
    if (query == null) return;
    query = parseQuery(query);
    dialog(cm, replacementQueryDialog, "Replace with:", "", (String text) {
      if (all) {
        cm.operation(cm, () {
          for (var cursor = getSearchCursor(cm, query); cursor.findNext();) {
            if (query is! String) {
              Match match = query.firstMatch(cm.getRange(cursor.from(), cursor.to()));
              cursor.replace(text.replaceAllMapped(
                  new RegExp(r'\$(\d)'),
                  (Match m) => _extract(m, match)));
            } else cursor.replace(text);
          }
        })();
      } else {
        clearSearch(cm);
        var cursor = getSearchCursor(cm, query, cm.getCursor());
        var advance;
        var doReplace;
        advance = () {
          var start = cursor.from();
          if (!(cursor.findNext())) {
            cursor = getSearchCursor(cm, query);
            if (!(cursor.findNext()) ||
                (start != null && cursor.from().line == start.line &&
                    cursor.from().char == start.char)) {
              return;
            }
          }
          cm.setSelection(cursor.from(), cursor.to());
          cm.scrollIntoView(new Range(cursor.from(), cursor.to()));
          confirmDialog(cm, doReplaceConfirm, "Replace?",
                        [ () { doReplace(cursor.match); }, advance ]);
        };
        doReplace = (Match match) {
          cursor.replace(query is String ? text :
                         text.replaceAllMapped(
                             new RegExp(r'\$(\d)'),
                             (Match m) => _extract(m, match)));
          advance();
        };
        advance();
      }
    });
  });
}

initializeSearch() {
  initializeMatchHighlighting();
  CodeMirror.defaultCommands['find'] = ([cm]) {clearSearch(cm); doSearch(cm);};
  CodeMirror.defaultCommands['findNext'] = doSearch;
  CodeMirror.defaultCommands['findPrev'] = ([cm]) {doSearch(cm, true);};
  CodeMirror.defaultCommands['clearSearch'] = clearSearch;
  CodeMirror.defaultCommands['replace'] = replace;
  CodeMirror.defaultCommands['replaceAll'] = ([cm]) {replace(cm, true);};

//  CodeMirror.defineExtension("getSearchCursor", (query, pos, caseFold) {
//    return new SearchCursor(cm.doc, query, pos, caseFold);
//  });
//  CodeMirror.defineDocExtension("getSearchCursor", (query, pos, caseFold) {
//    return new SearchCursor(cm, query, pos, caseFold);
//  });

  CodeMirror.defaultCommands["selectMatches"] = ([CodeMirror cm, query, caseFold]) {
    var ranges = [];
    var cur = getSearchCursor(query, cm.getCursor("from"), caseFold);
    while (cur.findNext()) {
      if (CodeMirror.cmpPos(cur.to(), cm.getCursor("to")) > 0) {
        break;
      }
      ranges.add(new Range(cur.from(), cur.to()));
    }
    if (ranges.length > 0) {
      cm.setSelections(ranges, 0);
    }
  };
}

class SearchCursor {
  bool atOccurrence;
  Doc doc;
  SearchMatch pos;
  Function matches;

  Match get match => pos == null ? null : pos.match;

  SearchCursor(Doc docx, Pattern pattern, [Pos posx, bool caseFold = false]) {
    // query may be String or RegExp
    this.atOccurrence = false; this.doc = docx;

    var ps = posx != null ? doc.clipPos(posx) : new Pos(0, 0);
    this.pos = new SearchMatch(from: ps, to: ps);

    // The matches method is filled in based on the type of query.
    // It takes a position and a direction, and returns an object
    // describing the next occurrence of the query, or null if no
    // more matches were found.
    if (pattern is! String) { // Regexp match
      RegExp query = pattern;
      this.matches = (bool reverse, Pos pos) {
        Match match;
        int start, matchLen;
        if (reverse) {
          var line = doc.getLine(pos.line).substring(0, pos.char);
          int cutOff = 0;
          int searchStart = 0;
          for (;;) {
            searchStart = cutOff;
            var newMatchIter = query.allMatches(line, searchStart);
            if (newMatchIter.isEmpty) break;
            Match newMatch = newMatchIter.first;
            match = newMatch;
            start = match.start;
            cutOff = match.start + max(match[0].length, 1);
            if (cutOff == line.length) break;
          }
          matchLen = match != null ? match[0].length : 0;
          if (matchLen == 0) {
            if (start == 0 && line.length == 0) {
              match = null;
            } else if (start != doc.getLine(pos.line).length) {
              matchLen++;
            }
          }
        } else {
          var line = doc.getLine(pos.line);
          int searchStart = pos.char;
          var matchIter = query.allMatches(line, searchStart);
          if (matchIter.isEmpty) {
            match = null;
            matchLen = 0;
          } else {
            match = matchIter.first;
            matchLen = match != null ? match[0].length : 0;
            start = match != null ? match.start : 0;
            if (start + matchLen != line.length && matchLen == 0) {
              matchLen = 1;
            }
          }
        }
        if (match != null && matchLen != 0) {
          return new SearchMatch(
              from: new Pos(pos.line, start),
              to: new Pos(pos.line, start + matchLen),
              match: match);
        }
        return null;
      };
    } else { // String query
      String query = pattern; // Need declaration since warnings are broken
      var origQuery = query;  // when param declared: Pattern query.
      if (caseFold) query = query.toLowerCase();
      var fold = caseFold
          ? (str) { return str.toLowerCase(); }
          : (str) { return str; };
      var target = query.split("\n");
      // Different methods for single-line and multi-line queries
      if (target.length == 1) {
        if (query.length == 0) {
          // Empty string would match anything and never progress, so
          // we define it to match nothing instead.
          this.matches = () { return null; };
        } else {
          this.matches = (bool reverse, Pos pos) {
            if (reverse) {
              var orig = doc.getLine(pos.line).substring(0, pos.char);
              String line = fold(orig);
              var match = line.lastIndexOf(query);
              if (match > -1) {
                match = _adjustPos(orig, line, match);
                return new SearchMatch(
                    from: new Pos(pos.line, match),
                    to: new Pos(pos.line, match + origQuery.length));
              }
             } else {
               var orig = doc.getLine(pos.line).substring(pos.char);
               String line = fold(orig);
               var match = line.indexOf(query);
               if (match > -1) {
                 match = _adjustPos(orig, line, match) + pos.char;
                 return new SearchMatch(
                     from: new Pos(pos.line, match),
                     to: new Pos(pos.line, match + origQuery.length));
               }
            }
            return null;
          };
        }
      } else {
        var origTarget = origQuery.split("\n");
        this.matches = (bool reverse, Pos pos) {
          var last = target.length - 1;
          if (reverse) {
            if (pos.line - (target.length - 1) < doc.firstLine()) {
              return null;
            }
            if (fold(doc.getLine(pos.line).substring(0, origTarget[last].length))
                != target[target.length - 1]) {
              return null;
            }
            var to = new Pos(pos.line, origTarget[last].length);
            var ln = pos.line - 1;
            for (var i = last - 1; i >= 1; --i, --ln) {
              if (target[i] != fold(doc.getLine(ln))) {
                return null;
              }
            }
            var line = doc.getLine(ln);
            var cut = line.length - origTarget[0].length;
            if (fold(line.substring(cut)) != target[0]) {
              return null;
            }
            return new SearchMatch(
                from: new Pos(ln, cut),
                to: to);
          } else {
            if (pos.line + (target.length - 1) > doc.lastLine()) {
              return null;
            }
            var line = doc.getLine(pos.line);
            var cut = line.length - origTarget[0].length;
            if (fold(line.substring(cut)) != target[0]) {
              return null;
            }
            var from = new Pos(pos.line, cut);
            var ln = pos.line + 1;
            for (var i = 1; i < last; ++i, ++ln)
              if (target[i] != fold(doc.getLine(ln))) {
                return null;
              }
            if (fold(doc.getLine(ln).substring(0, origTarget[last].length)) !=
                target[last]) {
              return null;
            }
            return new SearchMatch(
                from: from,
                to: new Pos(ln, origTarget[last].length));
          }
        };
      }
    }
  }

  bool findNext() => find(false);
  bool findPrevious() => find(true);

  bool find(bool reverse) {
    var clippedPos = doc.clipPos(reverse ? pos.from : pos.to);
    savePosAndFail(line) {
      var begin = new Pos(line, 0);
      pos = new SearchMatch(from: begin, to: begin);
      atOccurrence = false;
      return false;
    }

    for (;;) {
      if ((this.pos = matches(reverse, clippedPos)) != null) {
        atOccurrence = true;
        return true; //this.pos.match == null ? true : this.pos.match;
      }
      if (reverse) {
        if (clippedPos.line == 0) return savePosAndFail(0);
        clippedPos = new Pos(clippedPos.line-1, doc.getLine(clippedPos.line-1).length);
      }
      else {
        var maxLine = doc.lineCount();
        if (clippedPos.line == maxLine - 1) return savePosAndFail(maxLine);
        clippedPos = new Pos(clippedPos.line + 1, 0);
      }
    }
  }

  Pos from() => atOccurrence ? pos.from : null;
  Pos to() => atOccurrence ? pos.to : null;

  void replace(String newText) {
    if (!atOccurrence) return;
    var lines = doc.splitLines(newText);
    doc.replaceRange(lines, pos.from, pos.to);
    pos.to = new Pos(
        pos.from.line + lines.length - 1,
        lines[lines.length - 1].length +
            (lines.length == 1 ? pos.from.char : 0));
  }

  // Maps a position in a case-folded line back to a position in the original line
  // (compensating for codepoints increasing in number during folding)
  int _adjustPos(String orig, String folded, int pos) {
    if (orig.length == folded.length) return pos;
    for (int pos1 = min(pos, orig.length) ;; ) {
      var len1 = orig.substring(0, pos1).toLowerCase().length;
      if (len1 < pos) ++pos1;
      else if (len1 > pos) --pos1;
      else return pos1;
    }
  }
}

class SearchMatch {
  Pos from, to;
  Match match;

  SearchMatch({this.from, this.to, this.match});
}
