// Copyright (c) 2015, the Comid Authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library comid.showhints.css;

import 'package:comid/codemirror.dart';
import 'package:comid/addon/edit/show-hint.dart';
import 'package:comid/addon/mode/css.dart';

initialize() {
  CssMode.initialize();

  var pseudoClasses = {
      'link': 1, 'visited': 1, 'active': 1, 'hover': 1, 'focus': 1,
      "first-letter": 1, "first-line": 1, "first-child": 1,
      'before': 1, 'after': 1, 'lang': 1
  };

  CodeMirror.registerHelper("hint", "css", (CodeMirror cm) {
    var cur = cm.getCursor(), token = cm.getTokenAt(cur);
    var inner = cm.innerMode(cm.doc.getMode(), token.state);
    if (inner.mode.name != "css") return null;

    var start = token.start, end = cur.char;
    var word = token.string.substring(0, end - start);
    if (new RegExp(r'[^\w$_-]').hasMatch(word)) {
      word = ""; start = end = cur.char;
    }

    var spec = CodeMirror.resolveMode("text/css");

    var result = [];
    void add(keywords) {
      for (var name in keywords)
        if (word == null || name.lastIndexOf(word, 0) == 0)
          result.add(name);
    }

    var st = inner.state.state;
    if (st == "pseudo" || token.type == "variable-3") {
      add(pseudoClasses);
    } else if (st == "block" || st == "maybeprop") {
      add(spec.propertyKeywords);
    } else if (st == "prop" || st == "parens" || st == "at" || st == "params") {
      add(spec.valueKeywords);
      add(spec.colorKeywords);
    } else if (st == "media" || st == "media_parens") {
      add(spec.mediaTypes);
      add(spec.mediaFeatures);
    }

    if (result.length > 0) {
      return new ProposalList(
          list: result,
          from: new Pos(cur.line, start),
          to: new Pos(cur.line, end)
      );
    }
  });
}
