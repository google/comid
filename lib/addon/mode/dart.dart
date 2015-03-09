// Copyright (c) 2015, the Comid Authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library comid.mode.dart;

import 'package:comid/codemirror.dart';
import 'clike.dart';

class DartMode extends ClikeMode {

  DartMode(Options config, Config parserConfig) : super(config, parserConfig);

  static bool _isInitialized = false;
  static initialize() {
    if (_isInitialized) return;
    ClikeMode.initialize();
    _isInitialized = true;
    var keywords =
      "this super static final const abstract class extends external factory " +
      "implements get native operator set typedef with enum throw rethrow " +
      "assert break case continue default in return new deferred async await " +
      "try catch finally do else for if switch while import library export " +
      "part of show hide is";
    var blockKeywords = "try catch finally do else for if switch while";
    var atoms = "true false null";
    var builtins = "void bool num int double dynamic var String";

    def("application/dart", new Config(
      name: "clike",
      keywords: words(keywords),
      multiLineStrings: true,
      blockKeywords: words(blockKeywords),
      builtin: words(builtins),
      atoms: words(atoms),
      hooks: {
        "@": (StringStream stream, ClikeState state) {
          stream.eatWhile(new RegExp(r'[\w\$_]/'));
          return "meta";
        }
      }
    ));

    CodeMirror.defineMode("dart", (conf, _) {
      return CodeMirror.getMode(conf, "application/dart");
    });

  }
}