// Copyright (c) 2015, the Comid Authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

part of comid.test;

clikeModeTest() {
  ClikeMode.initialize();
  Mode mode = CodeMirror.getMode({'indentUnit': 2}, "text/x-c");
  MT(String name, [_0, _1, _2, _3, _4, _5, _6, _7, _8, _9, _a, _b, _c, _d, _e]) {
    List args = varargs(_0, _1, _2, _3, _4, _5, _6, _7, _8, _9, _a, _b, _c, _d, _e);
    test_mode(name, mode, args);
  }

  MT("indent",
     "[variable-3 void] [def foo]([variable-3 void*] [variable a], [variable-3 int] [variable b]) {",
     "  [variable-3 int] [variable c] [operator =] [variable b] [operator +]",
     "    [number 1];",
     "  [keyword return] [operator *][variable a];",
     "}");

  MT("indent_switch",
     "[keyword switch] ([variable x]) {",
     "  [keyword case] [number 10]:",
     "    [keyword return] [number 20];",
     "  [keyword default]:",
     "    [variable printf]([string \"foo %c\"], [variable x]);",
     "}");

  MT("def",
     "[variable-3 void] [def foo]() {}",
     "[keyword struct] [def bar]{}",
     "[variable-3 int] [variable-3 *][def baz]() {}");
}