// Copyright (c) 2015, the Comid Authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library comid.mode.yaml;

import 'package:comid/codemirror.dart';

class YamlMode extends Mode {

  static bool _initialized = false;
  static initialize() {
    if (_initialized) return;
    _initialized = true;
    CodeMirror.defineMode("yaml", (options, config) => new YamlMode(options, config));
    CodeMirror.defineMIME("text/x-yaml", "yaml");
    // Changed [^#]*? to [^#]* because dart regexp wouldn't match original.
    var s = r'^\s*(?:[,\[\]{}&*!|>"%@`][^\s":]|[^,\[\]{}#&*!|>"%@`])[^#]*(?=\s*:($|\s))';
    s = s.replaceAll('"', '\'"');
    pairMatcher = new RegExp(s);
  }

  static var cons = ['true', 'false', 'on', 'off', 'yes', 'no'];
  static RegExp keywordRegex = new RegExp("\\b(("+cons.join(")|(")+"))\$",
      caseSensitive: true);
  static RegExp pairMatcher;

  YamlMode(options, config) {
  }

  token(StringStream stream, [YamlState state]) {
    var ch = stream.peek();
    var esc = state.escaped;
    state.escaped = false;
    /* comments */
    if (ch == "#" && (stream.pos == 0 ||
        new RegExp(r'\s').hasMatch(stream.string.substring(stream.pos - 1, stream.pos)))) {
      stream.skipToEnd();
      return "comment";
    }

    if (stream.match(new RegExp('^(\'([^\']|\\.)*\'?|"([^"]|\\.)*"?)')) != null)
      return "string";

    if (state.literal && stream.indentation() > state.keyCol) {
      stream.skipToEnd();
      return "string";
    } else if (state.literal) {
      state.literal = false;
    }
    if (stream.sol()) {
      state.keyCol = 0;
      state.pair = false;
      state.pairStart = false;
      /* document start */
      if(stream.match('---') != null) {
        return "def";
      }
      /* document end */
      if (stream.match(new RegExp(r'\.\.\.')) != null) {
        return "def";
      }
      /* array list item */
      if (stream.match(new RegExp(r'\s*-\s+')) != null) {
        return 'meta';
      }
    }
    /* inline pairs/lists */
    if (stream.match(new RegExp(r'^(\{|\}|\[|\])')) != null) {
      if (ch == '{')
        state.inlinePairs++;
      else if (ch == '}')
        state.inlinePairs--;
      else if (ch == '[')
        state.inlineList++;
      else
        state.inlineList--;
      return 'meta';
    }

    /* list seperator */
    if (state.inlineList > 0 && !esc && ch == ',') {
      stream.next();
      return 'meta';
    }
    /* pairs seperator */
    if (state.inlinePairs > 0 && !esc && ch == ',') {
      state.keyCol = 0;
      state.pair = false;
      state.pairStart = false;
      stream.next();
      return 'meta';
    }

    /* start of value of a pair */
    if (state.pairStart) {
      /* block literals */
      if (stream.match(new RegExp(r'^\s*(\||\>)\s*')) != null) {
        state.literal = true;
        return 'meta';
      }
      /* references */
      if (stream.match(new RegExp(r'^\s*(\&|\*)[a-z0-9\._-]+\b', caseSensitive: true)) != null) {
        return 'variable-2';
      }
      /* numbers */
      if (state.inlinePairs == 0 && stream.match(new RegExp(r'^\s*-?[0-9\.\,]+\s?$')) != null) {
        return 'number';
      }
      if (state.inlinePairs > 0 && stream.match(new RegExp(r'^\s*-?[0-9\.\,]+\s?(?=(,|}))')) != null) {
        return 'number';
      }
      /* keywords */
      if (stream.match(keywordRegex) != null) {
        return 'keyword';
      }
    }

    /* pairs (associative arrays) -> key */
    if (!state.pair && stream.match(pairMatcher) != null) {
      state.pair = true;
      state.keyCol = stream.indentation();
      return "atom";
    }
    if (state.pair && stream.match(new RegExp(r'^:\s*')) != null) {
      state.pairStart = true;
      return 'meta';
    }

    /* nothing found, continue */
    state.pairStart = false;
    state.escaped = (ch == '\\');
    stream.next();
    return null;
  }

  startState([a, b]) {
    return new YamlState(
      pair: false,
      pairStart: false,
      keyCol: 0,
      inlinePairs: 0,
      inlineList: 0,
      literal: false,
      escaped: false
    );
  }

  bool get hasStartState => true;
}

class YamlState extends ModeState {
  bool pair;
  bool pairStart;
  int keyCol;
  int inlinePairs;
  int inlineList;
  bool literal;
  bool escaped;

  YamlState({this.pair, this.pairStart, this.keyCol, this.inlinePairs,
      this.inlineList, this.literal, this.escaped});

  YamlState newInstance() {
    return new YamlState();
  }

  void copyValues(YamlState old) {
    pair = old.pair;
    pairStart = old.pairStart;
    keyCol = old.keyCol;
    inlinePairs = old.inlinePairs;
    inlineList = old.inlineList;
    literal = old.literal;
    escaped = old.escaped;
  }

  String toString() {
    return "YamlState($pair, $pairStart, $keyCol, $inlineList, $literal, $escaped)";
  }
}
