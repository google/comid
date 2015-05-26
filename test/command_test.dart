// Copyright (c) 2015, the Comid Authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

part of comid.test;

commandTest() {
  // Test character commands that aren't exercised in multiTest().
  group('Commands,', () {
    CodeMirror editor;

    test('characters', () {
      editor = makeEditor({'value': "1 2 3\na b c",
        'indentUnit': 2, 'indentWithTabs': true, 'tabSize': 8});
      select(editor, [new Pos(0,2), new Pos(1,2)]);
      editor.execCommand("transposeChars");
      expect(editor.getValue(), "12  3\nab  c");
      editor.execCommand("insertSoftTab");
      expect(editor.getValue(), "12        3\nab        c");
      editor.execCommand("defaultTab");
      expect(editor.getValue(), "12       \t 3\nab       \t c");
      select(editor, [new Range(new Pos(0,1), new Pos(0,2))]);
      editor.execCommand("defaultTab");
      expect(editor.getValue(), "  12       \t 3\nab       \t c");
      select(editor, [new Pos(0)]);
    });

    test('select', () {
      editor = makeEditor({'value': "1 2 3\na b c",
        'indentUnit': 2, 'indentWithTabs': true, 'tabSize': 8});
      editor.execCommand("selectAll");
      expect(editor.getSelection(), "1 2 3\na b c");
      editor.execCommand('singleSelection');
      expect(editor.getSelection(), "1 2 3\na b c");
    });

    test('addWidget', () {
      editor = makeEditor({'value': "1 2 3\na b c"});
      var node = eltspan("Hello", "cm-test-widget");
      editor.addWidget(new Pos(1,1), node, true, "above", "middle");
      var ns = byClassName(editor.getWrapperElement(), "cm-test-widget");
      expect(ns, isNotNull);
      expect(ns.length, 1);
      node.remove();
    });

    test('delLine', () {
      editor = makeEditor({'value': "line1\nlong long line2\nline3\n\nline5\n"});
      editor.setCursor(new Pos(0, 4));
      editor.execCommand('delLineLeft');
      expect(editor.getValue(), "1\nlong long line2\nline3\n\nline5\n");
      editor.execCommand('undo');
      expect(editor.getLine(0), "line1");
      editor.execCommand('redo');
      expect(editor.getLineHandleVisualStart(0).text, "1");
      editor.setCursor(new Pos(1, 5));
      editor.execCommand('delWrappedLineLeft');
      expect(editor.getLine(1), "long line2");
      editor.execCommand('goCharRight');
      editor.execCommand('delWrappedLineRight');
      expect(editor.getLine(1), "l");
    });

    test('findPosV', () {
      editor = makeEditor({'value': "line1\nlong long line2\nline3\n\nline5\n"});
      Pos p = editor.findPosV(new Pos(0, 1), 1, "page");
      expect(p.line, 5);
      expect(p.char, 0);
      expect(p.hitSide, isTrue);
      int n = editor.lastLine();
      expect(n, 5);
      expect(editor.isLine(n), isTrue);
    });

    test('findWord', () {
      editor = makeEditor({'value': "a line full of words"});
      editor.toggleOverwrite();
      Range p = editor.findWordAt(new PosWithInfo(0, 4, false, 0));
      expect(p.from(), new Pos(0, 2));
      expect(p.to(), new Pos(0, 6));
      editor.setSelection(p.anchor, p.head);
      expect(editor.getSelection(), "line");
    });

    test('options', () {
      editor = makeEditor({'value': "a line full of words", 'scrollbarStyle': 'null'});
      expect(byClassName(editor.getWrapperElement(), "CodeMirror-hscrollbar"), isEmpty);
    });
  });
}
