// Copyright (c) 2015, the Comid Authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

part of comid.test;

multiTest() {
  // Test multiple selection operations.
  group('Multi-select,', () {
    CodeMirror editor;

    test('getSelection', () {
      editor = makeEditor({'value': "1234\n5678\n90"});
      select(editor, [new Range(new Pos(0, 0), new Pos(1, 2)),
                      new Range(new Pos(2, 2), new Pos(2, 0))]);
      expect(editor.getSelection(), "1234\n56\n90");
      expect(editor.getSelection(false).join("|"), "1234|56|90");
      expect(editor.getSelections().join("|"), "1234\n56|90");
    });

    test('setSelection', () {
      editor = makeEditor({'value': "abcde\nabcde\nabcde\n"});
      select(editor, [new Pos(3, 0), new Pos(0, 0),
                      new Range(new Pos(2, 5), new Pos(1, 0))]);
      hasSelections(editor, [[0, 0, 0, 0],
                            [2, 5, 1, 0],
                            [3, 0, 3, 0]]);
      editor.setSelection(new Pos(1, 2), new Pos(1, 1));
      hasSelections(editor, [[1, 2, 1, 1]]);
      select(editor, [new Range(new Pos(1, 1), new Pos(2, 4)),
                     new Range(new Pos(0, 0), new Pos(1, 3)),
                     new Pos(3, 0),
                     new Pos(2, 2)]);
      hasSelections(editor, [[0, 0, 2, 4],
                            [3, 0, 3, 0]]);
      editor.setSelections([new Range(new Pos(0, 1), new Pos(0, 2)),
                            new Range(new Pos(1, 1), new Pos(1, 2)),
                            new Range(new Pos(2, 1), new Pos(2, 2))],
                           1);
      expect(editor.getCursor("head"), new Pos(1, 2));
      expect(editor.getCursor("anchor"), new Pos(1, 1));
      expect(editor.getCursor("from"), new Pos(1, 1));
      expect(editor.getCursor("to"), new Pos(1, 2));
      editor.setCursor(new Pos(1, 1));
      hasCursors(editor, [[1, 1]]);
    });

    test('somethingSelected', () {
      editor = makeEditor({'value': "123456789"});
      select(editor, [new Pos(0, 1), new Range(new Pos(0, 3), new Pos(0, 5))]);
      expect(editor.somethingSelected(), true);
      select(editor, [new Pos(0, 1), new Pos(0, 3), new Pos(0, 5)]);
      expect(editor.somethingSelected(), false);
    });

    test('extendSelection', () {
      editor = makeEditor({'value': "1234\n1234\n1234"});
      select(editor, [new Pos(0, 1), new Pos(1, 1), new Pos(2, 1)]);
      editor.setExtending(true);
      editor.extendSelections([new Pos(0, 2), new Pos(1, 0), new Pos(2, 3)]);
      hasSelections(editor, [[0, 1, 0, 2],
                            [1, 1, 1, 0],
                            [2, 1, 2, 3]]);
      editor.extendSelection(new Pos(2, 4), new Pos(2, 0));
      hasSelections(editor, [[2, 4, 2, 0]]);
    });

    test('addSelection', () {
      editor = makeEditor({'value': "1234\n1234\n1234"});
      select(editor, [new Pos(0, 1), new Pos(1, 1)]);
      editor.addSelection(new Pos(0, 0), new Pos(0, 4));
      hasSelections(editor, [[0, 0, 0, 4],
                            [1, 1, 1, 1]]);
      editor.addSelection(new Pos(2, 2));
      hasSelections(editor, [[0, 0, 0, 4],
                            [1, 1, 1, 1],
                            [2, 2, 2, 2]]);
    });

    test('replaceSelection', () {
      editor = makeEditor();
      var selections = [new Range(new Pos(0, 0), new Pos(0, 1)),
                        new Range(new Pos(0, 2), new Pos(0, 3)),
                        new Range(new Pos(0, 4), new Pos(0, 5)),
                        new Range(new Pos(2, 1), new Pos(2, 4)),
                        new Range(new Pos(2, 5), new Pos(2, 6))];
      var val = "123456\n123456\n123456";
      editor.setValue(val);
      editor.setSelections(selections);
      editor.replaceSelection("ab", "around");
      expect(editor.getValue(), "ab2ab4ab6\n123456\n1ab5ab");
      hasSelections(editor, [[0, 0, 0, 2],
                            [0, 3, 0, 5],
                            [0, 6, 0, 8],
                            [2, 1, 2, 3],
                            [2, 4, 2, 6]]);
      editor.setValue(val);
      editor.setSelections(selections);
      editor.replaceSelection("", "around");
      expect(editor.getValue(), "246\n123456\n15");
      hasSelections(editor, [[0, 0, 0, 0],
                            [0, 1, 0, 1],
                            [0, 2, 0, 2],
                            [2, 1, 2, 1],
                            [2, 2, 2, 2]]);
      editor.setValue(val);
      editor.setSelections(selections);
      editor.replaceSelection("X\nY\nZ", "around");
      hasSelections(editor, [[0, 0, 2, 1],
                            [2, 2, 4, 1],
                            [4, 2, 6, 1],
                            [8, 1, 10, 1],
                            [10, 2, 12, 1]]);
      editor.replaceSelection("a", "around");
      hasSelections(editor, [[0, 0, 0, 1],
                            [0, 2, 0, 3],
                            [0, 4, 0, 5],
                            [2, 1, 2, 2],
                            [2, 3, 2, 4]]);
      editor.replaceSelection("xy", "start");
      hasSelections(editor, [[0, 0, 0, 0],
                            [0, 3, 0, 3],
                            [0, 6, 0, 6],
                            [2, 1, 2, 1],
                            [2, 4, 2, 4]]);
      editor.replaceSelection("z\nf");
      hasSelections(editor, [[1, 1, 1, 1],
                            [2, 1, 2, 1],
                            [3, 1, 3, 1],
                            [6, 1, 6, 1],
                            [7, 1, 7, 1]]);
      expect(editor.getValue(), "z\nfxy2z\nfxy4z\nfxy6\n123456\n1z\nfxy5z\nfxy");
    });

    test('indentSelection', () {
      editor = makeEditor({'value': "foo\nbar\nbaz"});
      select(editor, [new Pos(0, 1), new Pos(1, 1)]);
      editor.indentSelection(4);
      expect(editor.getValue(), "    foo\n    bar\nbaz");

      select(editor, [new Pos(0, 2), new Pos(0, 3), new Pos(0, 4)]);
      editor.indentSelection(-2);
      expect(editor.getValue(), "  foo\n    bar\nbaz");

      select(editor, [new Range(new Pos(0, 0), new Pos(1, 2)),
                      new Range(new Pos(1, 3), new Pos(2, 0))]);
      editor.indentSelection(-2);
      expect(editor.getValue(), "foo\n  bar\nbaz");
    });

    test('killLine', () {
      editor = makeEditor({'value': "foo\nbar\nbaz"});
      select(editor, [new Pos(0, 1), new Pos(0, 2), new Pos(1, 1)]);
      editor.execCommand("killLine");
      expect(editor.getValue(), "f\nb\nbaz");
      editor.execCommand("killLine");
      expect(editor.getValue(), "fbbaz");
      editor.setValue("foo\nbar\nbaz");
      select(editor, [new Pos(0, 1), new Range(new Pos(0, 2), new Pos(2, 1))]);
      editor.execCommand("killLine");
      expect(editor.getValue(), "faz");
    });

    test('deleteLine', () {
      editor = makeEditor({'value': "1\n2\n3\n4\n5\n6\n7"});
      select(editor, [new Pos(0, 0),
                      new Range(new Pos(0, 1), new Pos(2, 0)),
                      new Pos(4, 0)]);
      editor.execCommand("deleteLine");
      expect(editor.getValue(), "4\n6\n7");
      select(editor, [new Pos(2, 1)]);
      editor.execCommand("deleteLine");
      expect(editor.getValue(), "4\n6\n");
    });

    test('deleteH', () {
      editor = makeEditor({'value': "foo bar baz\nabc def ghi\n"});
      select(editor, [new Pos(0, 4), new Range(new Pos(1, 4), new Pos(1, 5))]);
      editor.execCommand("delWordAfter");
      expect(editor.getValue(), "foo bar baz\nabc ef ghi\n");
      editor.execCommand("delWordAfter");
      expect(editor.getValue(), "foo  baz\nabc  ghi\n");
      editor.execCommand("delCharBefore");
      editor.execCommand("delCharBefore");
      expect(editor.getValue(), "fo baz\nab ghi\n");
      select(editor, [new Pos(0, 3), new Pos(0, 4), new Pos(0, 5)]);
      editor.execCommand("delWordAfter");
      expect(editor.getValue(), "fo \nab ghi\n");
    });

    test('goLineStart', () {
      editor = makeEditor({'value': "foo\nbar\nbaz"});
      select(editor, [new Pos(0, 2), new Pos(0, 3), new Pos(1, 1)]);
      editor.execCommand("goLineStart");
      hasCursors(editor, [[0, 0], [1, 0]]);
      select(editor, [new Pos(1, 1), new Pos(0, 1)]);
      editor.setExtending(true);
      editor.execCommand("goLineStart");
      hasSelections(editor, [[0, 1, 0, 0],
                             [1, 1, 1, 0]]);
    });

    test('moveV', () {
      editor = makeEditor({'value': "12345\n12345\n12345"});
      select(editor, [new Pos(0, 2), new Pos(1, 2)]);
      editor.execCommand("goLineDown");
      hasCursors(editor, [[1, 2], [2, 2]]);
      editor.execCommand("goLineUp");
      hasCursors(editor, [[0, 2], [1, 2]]);
      editor.execCommand("goLineUp");
      hasCursors(editor, [[0, 0], [0, 2]]);
      editor.execCommand("goLineUp");
      hasCursors(editor, [[0, 0]]);
      select(editor, [new Pos(0, 2), new Pos(1, 2)]);
      editor.setExtending(true);
      editor.execCommand("goLineDown");
      hasSelections(editor, [[0, 2, 2, 2]]);
    });

    test('moveH', () {
      editor = makeEditor({'value': "12345\n12345\n12345"});
      select(editor, [new Pos(0, 1), new Pos(0, 3), new Pos(0, 5), new Pos(2, 3)]);
      editor.execCommand("goCharRight");
      hasCursors(editor, [[0, 2], [0, 4], [1, 0], [2, 4]]);
      editor.execCommand("goCharLeft");
      hasCursors(editor, [[0, 1], [0, 3], [0, 5], [2, 3]]);
      for (var i = 0; i < 15; i++)
        editor.execCommand("goCharRight");
      hasCursors(editor, [[2, 4], [2, 5]]);
    });

    test('newlineAndIndent', () {
      if (1 != 0) return; // TODO Define javascript mode
      editor = makeEditor({'value': "x = [1];\ny = [2];", 'mode': "javascript"});
      select(editor, [new Pos(0, 5), new Pos(1, 5)]);
      editor.execCommand("newlineAndIndent");
      hasCursors(editor, [[1, 2], [3, 2]]);
      expect(editor.getValue(), "x = [\n  1];\ny = [\n  2];");
      editor.undo();
      expect(editor.getValue(), "x = [1];\ny = [2];");
      hasCursors(editor, [[0, 5], [1, 5]]);
      select(editor, [new Pos(0, 5), new Pos(0, 6)]);
      editor.execCommand("newlineAndIndent");
      hasCursors(editor, [[1, 2], [2, 0]]);
      expect(editor.getValue(), "x = [\n  1\n];\ny = [2];");
    });

    test('goDocStartEnd', () {
      editor = makeEditor({'value': "abc\ndef"});
      select(editor, [new Pos(0, 1), new Pos(1, 1)]);
      editor.execCommand("goDocStart");
      hasCursors(editor, [[0, 0]]);
      select(editor, [new Pos(0, 1), new Pos(1, 1)]);
      editor.execCommand("goDocEnd");
      hasCursors(editor, [[1, 3]]);
      select(editor, [new Pos(0, 1), new Pos(1, 1)]);
      editor.setExtending(true);
      editor.execCommand("goDocEnd");
      hasSelections(editor, [[1, 1, 1, 3]]);
    });

    test('selectionHistory', () {
      editor = makeEditor({'value': "1 2 3"});
      for (var i = 0; i < 3; ++i)
        editor.addSelection(new Pos(0, i * 2), new Pos(0, i * 2 + 1));
      editor.execCommand("undoSelection");
      expect(editor.getSelection(), "1\n2");
      editor.execCommand("undoSelection");
      expect(editor.getSelection(), "1");
      editor.execCommand("undoSelection");
      expect(editor.getSelection(), "");
      expect(editor.getCursor(), new Pos(0, 0));
      editor.execCommand("redoSelection");
      expect(editor.getSelection(), "1");
      editor.execCommand("redoSelection");
      expect(editor.getSelection(), "1\n2");
      editor.execCommand("redoSelection");
      expect(editor.getSelection(), "1\n2\n3");
    });
  });
}

select(CodeMirror editor, List<Object> args) {
  // args is a list of selection ranges (Range) or positions (Pos)
  List<Range> sels = [];
  for (var i = 0; i < args.length; i++) {
    var arg = args[i];
    if (arg is Range) sels.add(arg);
    else sels.add(new Range(arg, arg));
  }
  editor.setSelections(sels, sels.length - 1);
}

hasSelections(CodeMirror editor, List<List<int>> args) {
  // args is a list of 4-element selection ranges: [line1, col1, line2, col2]
  var sels = editor.listSelections();
  var given = args.length;
  expect(sels.length, given, reason: "expected ${given} selections, found ${sels.length}");
  for (var i = 0; i < given; i++) {
    var p = args[i];
    var anchor = new Pos(p[0], p[1]);
    var head = new Pos(p[2], p[3]);
    expect(sels[i].anchor, anchor, reason: "anchor of selection $i");
    expect(sels[i].head, head, reason: "head of selection $i");
  }
}

hasCursors(CodeMirror editor, List<List<int>> args) {
  // args is a list of 2-element cursor positions: [line, col]
  var sels = editor.listSelections();
  var given = args.length;
  expect(sels.length, given, reason: "expected ${given} selections, found ${sels.length}");
  for (var i = 0; i < given; i++) {
    var p = args[i];
    expect(sels[i].anchor, sels[i].head, reason: "something selected for $i");
    var head = new Pos(p[0], p[1]);
    expect(sels[i].head, head, reason: "selection $i");
  }
}
