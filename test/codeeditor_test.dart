// Copyright (c) 2015, the Comid Authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

part of comid.test;

// Also see https://www.dartlang.org/articles/mocking-with-dart/

// CodeEditor tests
editorTest() {
  group('CodeEditor,', () {
    CodeMirror editor;

    setUp(() {
    });

    test('Document is initialized', () {
      DivElement wrapper;
      editor = new CodeEditor((div) { wrapper = div; });
      expect(wrapper is DivElement, isTrue);
      expect(editor.doc, isNotNull);
      expect(editor.options != null, isTrue);
    });

    test('getRange', () {
      editor = makeEditor({'value': "1234\n5678"});
      expect(editor.options != null, isTrue);
      expect(editor.doc.getLine(0), equals("1234"));
      expect(editor.doc.getLine(1), equals("5678"));
      expect(editor.doc.getLine(2), isNull);
      expect(editor.doc.getLine(-1), isNull);
      expect(editor.doc.getRange(new Pos(0, 0), new Pos(0, 3)), equals("123"));
      expect(editor.doc.getRange(new Pos(0, -1), new Pos(0, 200)), equals("1234"));
      expect(editor.doc.getRange(new Pos(0, 2), new Pos(1, 2)), equals("34\n56"));
      expect(editor.doc.getRange(new Pos(1, 2), new Pos(100, 0)), equals("78"));
    });

    test('replaceRange', () {
      editor = makeEditor();
      expect(editor.getValue(), "");
      editor.replaceRange("foo\n", new Pos(0, 0));
      expect(editor.getValue(), "foo\n");
      editor.replaceRange("a\nb", new Pos(0, 1));
      expect(editor.getValue(), "fa\nboo\n");
      expect(editor.lineCount(), 3);
      editor.replaceRange("xyzzy", new Pos(0, 0), new Pos(1, 1));
      expect(editor.getValue(), "xyzzyoo\n");
      editor.replaceRange("abc", new Pos(0, 0), new Pos(10, 0));
      expect(editor.getValue(), "abc");
      expect(editor.lineCount(), 1);
    });

    test('selection', () {
      editor = makeEditor({'value': "111111\n222222\n333333"});
      editor.setSelection(new Pos(0, 4), new Pos(2, 2));
      expect(editor.somethingSelected(), isTrue);
      expect(editor.getSelection(), equals("11\n222222\n33"));
      expect(editor.getCursor(false), equals(new Pos(2, 2)));
      expect(editor.getCursor(true), equals(new Pos(0, 4)));
      editor.setSelection(new Pos(1, 0));
      expect(!editor.somethingSelected(), isTrue);
      expect(editor.getSelection(), equals(""));
      expect(editor.getCursor(true), equals(new Pos(1, 0)));
      editor.replaceSelection("abc", "around");
      expect(editor.getSelection(), equals("abc"));
      expect(editor.getValue(), equals("111111\nabc222222\n333333"));
      editor.replaceSelection("def", "end");
      expect(editor.getSelection(), equals(""));
      expect(editor.getCursor(true), equals(new Pos(1, 3)));
      editor.setCursor(new Pos(2, 1));
      expect(editor.getCursor(true), equals(new Pos(2, 1)));
      editor.doc.setCursor(1, 2);
      expect(editor.getCursor(true), equals(new Pos(1, 2)));
    });

    test('extendSelection', () {
      editor = makeEditor();
      editor.setExtending(true);
      addDoc(editor, 10, 10);
      editor.setSelection(new Pos(3, 5));
      expect(editor.getCursor("head"), equals(new Pos(3, 5)));
      expect(editor.getCursor("anchor"), equals(new Pos(3, 5)));
      editor.setSelection(new Pos(2, 5), new Pos(5, 5));
      expect(editor.getCursor("head"), equals(new Pos(5, 5)));
      expect(editor.getCursor("anchor"), equals(new Pos(2, 5)));
      expect(editor.getCursor("start"), equals(new Pos(2, 5)));
      expect(editor.getCursor("end"), equals(new Pos(5, 5)));
      editor.setSelection(new Pos(5, 5), new Pos(2, 5));
      expect(editor.getCursor("head"), equals(new Pos(2, 5)));
      expect(editor.getCursor("anchor"), equals(new Pos(5, 5)));
      expect(editor.getCursor("start"), equals(new Pos(2, 5)));
      expect(editor.getCursor("end"), equals(new Pos(5, 5)));
      editor.extendSelection(new Pos(3, 2));
      expect(editor.getCursor("head"), equals(new Pos(3, 2)));
      expect(editor.getCursor("anchor"), equals(new Pos(5, 5)));
      editor.extendSelection(new Pos(6, 2));
      expect(editor.getCursor("head"), equals(new Pos(6, 2)));
      expect(editor.getCursor("anchor"), equals(new Pos(5, 5)));
      editor.extendSelection(new Pos(6, 3), new Pos(6, 4));
      expect(editor.getCursor("head"), equals(new Pos(6, 4)));
      expect(editor.getCursor("anchor"), equals(new Pos(5, 5)));
      editor.extendSelection(new Pos(0, 3), new Pos(0, 4));
      expect(editor.getCursor("head"), equals(new Pos(0, 3)));
      expect(editor.getCursor("anchor"), equals(new Pos(5, 5)));
      editor.extendSelection(new Pos(4, 5), new Pos(6, 5));
      expect(editor.getCursor("head"), equals(new Pos(6, 5)));
      expect(editor.getCursor("anchor"), equals(new Pos(4, 5)));
      editor.setExtending(false);
      editor.extendSelection(new Pos(0, 3), new Pos(0, 4));
      expect(editor.getCursor("head"), equals(new Pos(0, 3)));
      expect(editor.getCursor("anchor"), equals(new Pos(0, 4)));
    });

    test('lines', () {
      editor = makeEditor({'value': "111111\n222222\n333333"});
      expect(editor.getLine(0), equals("111111"));
      expect(editor.getLine(1), equals("222222"));
      expect(editor.getLine(-1), isNull);
      editor.replaceRange("", new Pos(1, 0), new Pos(2, 0));
      editor.replaceRange("abc", new Pos(1, 0), new Pos(1));
      expect(editor.getValue(), equals("111111\nabc"));
    });

    test('indent', () {
      editor = makeEditor({'value': "if (x) {\nblah();\n}", 'indentUnit': 3, 'indentWithTabs': true, 'tabSize': 8});
      editor.indentLine(1, "add"); // Specify "add" since there is no mode.
      expect(editor.getLine(1), equals("   blah();"));
      editor.setOption("indentUnit", 8);
      editor.indentLine(1, "add");
      expect(editor.getLine(1), equals("\t   blah();")); // Adjusted expectations.
      editor.setOption("indentUnit", 10);
      editor.setOption("tabSize", 4);
      editor.indentLine(1, "add");
      expect(editor.getLine(1), equals("\t\t\t\t blah();")); // ...twice
    });

    test('indentByNumber', () {
      editor = makeEditor({'value': "foo\nbar\nbaz"});
      editor.indentLine(0, 2);
      expect(editor.getLine(0), equals("  foo"));
      editor.indentLine(0, -200);
      expect(editor.getLine(0), equals("foo"));
      editor.setSelection(new Pos(0, 0), new Pos(1, 2));
      editor.indentSelection(3);
      expect(editor.getValue(), equals("   foo\n   bar\nbaz"));
    });

    test('core_defaults', () {
      editor = null;
      var defs = CodeMirror.defaults;
      var defsCopy = defs.copy();
      int origIndent = defs.indentUnit;
      defs['indentUnit'] = 5;
      defs['value'] = "uu";
      defs['indentWithTabs'] = true;
      defs['tabindex'] = 55;
      var place = document.getElementById("testground");
      CodeMirror cm = new CodeMirror(place);
      try {
        expect(cm.getOption("indentUnit"), equals(5));
        cm.setOption("indentUnit", 10);
        expect(defs.indentUnit, equals(5));
        expect(cm.getValue(), equals("uu"));
        expect(cm.getOption("indentWithTabs"), isTrue);
        expect(cm.getInputField().tabIndex, equals(55));
      }
      finally {
        defs['indentUnit'] = defsCopy.indentUnit;
        defs['value'] = defsCopy.value;
        defs['indentWithTabs'] = defsCopy.indentWithTabs;
        defs['tabindex'] = defsCopy.tabindex;
        cm.getWrapperElement().remove();
        expect(origIndent == defs.indentUnit, isTrue);
        expect(defsCopy.equals(defs), isTrue);
      }
    });

    test('lineInfo', () {
      editor = makeEditor({'value': "111111\n222222\n333333"});
      expect(editor.lineInfo(-1), isNull);
      var mark = document.createElement("span");
      var lh = editor.setGutterMarker(1, "FOO", mark);
      var info = editor.lineInfo(1);
      expect(info.text, equals("222222"));
      expect(info.gutterMarkers['FOO'], equals(mark));
      expect(info.line, equals(1));
      expect(editor.lineInfo(2).gutterMarkers, isNull);
      editor.setGutterMarker(lh, "FOO", null);
      expect(editor.lineInfo(1).gutterMarkers, isNull);
      editor.setGutterMarker(1, "FOO", mark);
      editor.setGutterMarker(0, "FOO", mark);
      editor.clearGutter("FOO");
      expect(editor.lineInfo(0).gutterMarkers, isNull);
      expect(editor.lineInfo(1).gutterMarkers, isNull);
    });

    test('coords', () {
      editor = makeEditor();
      editor.setSize(null, 100);
      addDoc(editor, 32, 200);
      var top = editor.charCoords(new Pos(0, 0));
      var bot = editor.charCoords(new Pos(200, 30));
      expect(top.left < bot.left, isTrue);
      expect(top.top < bot.top, isTrue);
      expect(top.top < top.bottom, isTrue);
      editor.scrollTo(null, 100);
      var top2 = editor.charCoords(new Pos(0, 0));
      expect(top.top > top2.top, isTrue);
      expect(top.left, equals(top2.left));
    });

    test('coordsChar', () {
      editor = makeEditor({'lineNumbers': true});
      addDoc(editor, 35, 70);
      for (var i = 0; i < 2; ++i) {
        var sys = i > 0 ? "local" : "page";
        for (var ch = 0; ch <= 35; ch += 5) {
          for (var line = 0; line < 70; line += 5) {
            editor.doc.setCursor(line, ch);
            var coords = editor.charCoords(new Pos(line, ch), sys);
            var pos = editor.coordsChar(new Loc(coords.top + 1, coords.left + 1), sys);
            expect(pos, equals(new Pos(line, ch)));
          }
        }
      }
    });

    test('posFromIndex', () {
      editor = makeEditor();
      editor.setValue(
        "This function should\n" +
        "convert a zero based index\n" +
        "to line and ch."
      );

      var examples = [
        { 'index': -1, 'line': 0, 'ch': 0  }, // <- Tests clipping
        { 'index': 0,  'line': 0, 'ch': 0  },
        { 'index': 10, 'line': 0, 'ch': 10 },
        { 'index': 39, 'line': 1, 'ch': 18 },
        { 'index': 55, 'line': 2, 'ch': 7  },
        { 'index': 63, 'line': 2, 'ch': 15 },
        { 'index': 64, 'line': 2, 'ch': 15 }  // <- Tests clipping
      ];

      for (var i = 0; i < examples.length; i++) {
        var example = examples[i];
        var pos = editor.doc.posFromIndex(example['index']);
        expect(pos.line, equals(example['line']));
        expect(pos.char, equals(example['ch']));
        if (example['index'] >= 0 && example['index'] < 64)
          expect(editor.doc.indexFromPos(pos), equals(example['index']));
      }
    });

    test('undo', () {
      editor = makeEditor({'value': "abc"});
      editor.replaceRange("def", new Pos(0, 0), new Pos(0));
      expect(editor.historySize().undo == 1, isTrue);
      editor.undo();
      expect(editor.getValue(), "abc");
      expect(editor.historySize().undo == 0, isTrue);
      expect(editor.historySize().redo == 1, isTrue);
      editor.redo();
      expect(editor.getValue(), "def");
      expect(editor.historySize().undo == 1, isTrue);
      expect(editor.historySize().redo == 0, isTrue);
      editor.setValue("1\n\n\n2");
      editor.clearHistory();
      expect(editor.historySize().undo == 0, isTrue);
      for (var i = 0; i < 20; ++i) {
        editor.replaceRange("a", new Pos(0, 0));
        editor.replaceRange("b", new Pos(3, 0));
      }
      expect(editor.historySize().undo == 40, isTrue);
      for (var i = 0; i < 40; ++i)
        editor.undo();
      expect(editor.historySize().redo == 40, isTrue);
      expect(editor.getValue(), "1\n\n\n2");
    });

    test('undoDepth', () {
      editor = makeEditor({'value': "abc", 'undoDepth': 4});
      editor.replaceRange("d", new Pos(0));
      editor.replaceRange("e", new Pos(0));
      editor.replaceRange("f", new Pos(0));
      editor.undo(); editor.undo(); editor.undo();
      expect(editor.getValue(), equals("abcd"));
    });

    test('undoDoesntClearValue', () {
      editor = makeEditor({'value': "x"});
      editor.undo();
      expect(editor.getValue(), equals("x"));
    });

    test('undoMultiLine', () {
      editor = makeEditor({'value': "abc\ndef\nghi"});
      editor.operation(editor, () {
        editor.replaceRange("x", new Pos(0, 0));
        editor.replaceRange("y", new Pos(1, 0));
      })();
      expect(editor.getValue(), equals("xabc\nydef\nghi"));
      editor.undo();
      expect(editor.getValue(), equals("abc\ndef\nghi"));
      editor.operation(editor, () {
        editor.replaceRange("y", new Pos(1, 0));
        editor.replaceRange("x", new Pos(0, 0));
      })();
      editor.undo();
      expect(editor.getValue(), equals("abc\ndef\nghi"));
      editor.operation(editor, () {
        editor.replaceRange("y", new Pos(2, 0));
        editor.replaceRange("x", new Pos(1, 0));
        editor.replaceRange("z", new Pos(2, 0));
      })();
      editor.undo();
      expect(editor.getValue(), equals("abc\ndef\nghi"));
    });

    test('undoComposite', () {
      editor = makeEditor({'value': "a\nb\nc\n"});
      editor.replaceRange("y", new Pos(1));
      editor.operation(editor, () {
        editor.replaceRange("x", new Pos(0));
        editor.replaceRange("z", new Pos(2));
      })();
      expect(editor.getValue(), equals("ax\nby\ncz\n"));
      editor.undo();
      expect(editor.getValue(), equals("a\nby\nc\n"));
      editor.undo();
      expect(editor.getValue(), equals("a\nb\nc\n"));
      editor.redo(); editor.redo();
      expect(editor.getValue(), equals("ax\nby\ncz\n"));
    });

    test('undoSelection', () {
      editor = makeEditor({'value': "abcdefgh\n"});
      editor.setSelection(new Pos(0, 2), new Pos(0, 4));
      editor.replaceSelection("");
      editor.setCursor(new Pos(1, 0));
      editor.undo();
      expect(editor.getCursor(true), equals(new Pos(0, 2)));
      expect(editor.getCursor(false), equals(new Pos(0, 4)));
      editor.setCursor(new Pos(1, 0));
      editor.redo();
      expect(editor.getCursor(true), equals(new Pos(0, 2)));
      expect(editor.getCursor(false), equals(new Pos(0, 2)));
    });

    test('undoSelectionAsBefore', () {
      editor = makeEditor();
      editor.replaceSelection("abc", "around");
      editor.undo();
      editor.redo();
      expect(editor.getSelection(), "abc"); // Laziness about equals() set in.
    });

    test('selectionChangeConfusesHistory', () {
      editor = makeEditor();
      editor.replaceSelection("abc", null, "dontmerge");
      editor.operation(editor, () {
        editor.setCursor(new Pos(0, 0));
        editor.replaceSelection("abc", null, "dontmerge");
      })();
      expect(editor.historySize().undo, 2);
    });

    test('markTextSingleLine', () {
      editor = makeEditor();
      var l = [{'a': 0, 'b': 1, 'c': "", 'f': 2, 't': 5},
               {'a': 0, 'b': 4, 'c': "", 'f': 0, 't': 2},
               {'a': 1, 'b': 2, 'c': "x", 'f': 3, 't': 6},
               {'a': 4, 'b': 5, 'c': "", 'f': 3, 't': 5},
               {'a': 4, 'b': 5, 'c': "xx", 'f': 3, 't': 7},
               {'a': 2, 'b': 5, 'c': "", 'f': 2, 't': 3},
               {'a': 2, 'b': 5, 'c': "abcd", 'f': 6, 't': 7},
               {'a': 2, 'b': 6, 'c': "x", 'f': null, 't': null},
               {'a': 3, 'b': 6, 'c': "", 'f': null, 't': null},
               {'a': 0, 'b': 9, 'c': "hallo", 'f': null, 't': null},
               {'a': 4, 'b': 6, 'c': "x", 'f': 3, 't': 4},
               {'a': 4, 'b': 8, 'c': "", 'f': 3, 't': 4},
               {'a': 6, 'b': 6, 'c': "a", 'f': 3, 't': 6},
               {'a': 8, 'b': 9, 'c': "", 'f': 3, 't': 6}];
      l.forEach((test) {
        editor.setValue("1234567890");
        var r = editor.markText(new Pos(0, 3), new Pos(0, 6), className: "foo");
        editor.replaceRange(test['c'], new Pos(0, test['a']), new Pos(0, test['b']));
        var f = r.find();
        if (f == null) {
          expect(f, test['f']);
          expect(f, test['t']);
        } else {
          expect(f.from.char, test['f']);
          expect(f.to.char, test['t']);
        }
      });
    });

    test('markTextMultiLine', () {
      editor = makeEditor();
      p(v) { return v == null ? null : new Pos(v[0], v[1]); }
      var l = [{'a': [0, 0], 'b': [0, 5], 'c': "", 'f': [0, 0], 't': [2, 5]},
               {'a': [0, 0], 'b': [0, 5], 'c': "foo\n", 'f': [1, 0], 't': [3, 5]},
               {'a': [0, 1], 'b': [0, 10], 'c': "", 'f': [0, 1], 't': [2, 5]},
               {'a': [0, 5], 'b': [0, 6], 'c': "x", 'f': [0, 6], 't': [2, 5]},
               {'a': [0, 0], 'b': [1, 0], 'c': "", 'f': [0, 0], 't': [1, 5]},
               {'a': [0, 6], 'b': [2, 4], 'c': "", 'f': [0, 5], 't': [0, 7]},
               {'a': [0, 6], 'b': [2, 4], 'c': "aa", 'f': [0, 5], 't': [0, 9]},
               {'a': [1, 2], 'b': [1, 8], 'c': "", 'f': [0, 5], 't': [2, 5]},
               {'a': [0, 5], 'b': [2, 5], 'c': "xx", 'f': null, 't': null},
               {'a': [0, 0], 'b': [2, 10], 'c': "x", 'f': null, 't': null},
               {'a': [1, 5], 'b': [2, 5], 'c': "", 'f': [0, 5], 't': [1, 5]},
               {'a': [2, 0], 'b': [2, 3], 'c': "", 'f': [0, 5], 't': [2, 2]},
               {'a': [2, 5], 'b': [3, 0], 'c': "a\nb", 'f': [0, 5], 't': [2, 5]},
               {'a': [2, 3], 'b': [3, 0], 'c': "x", 'f': [0, 5], 't': [2, 3]},
               {'a': [1, 1], 'b': [1, 9], 'c': "1\n2\n3", 'f': [0, 5], 't': [4, 5]}];
      l.forEach((test) {
        editor.setValue("aaaaaaaaaa\nbbbbbbbbbb\ncccccccccc\ndddddddd\n");
        var r = editor.markText(new Pos(0, 5), new Pos(2, 5), className: "CodeMirror-matchingbracket");
        editor.replaceRange(test['c'], p(test['a']), p(test['b']));
        var f = r.find();
        if (f == null) {
          expect(f, p(test['f']));
          expect(f, p(test['t']));
        } else {
          expect(f.from, p(test['f']));
          expect(f.to, p(test['t']));
        }
      });
    });

    test('markTextUndo', () {
      editor = makeEditor({'value': "1234\n56789\n00\n"});
      var marker1, marker2, bookmark;
      marker1 = editor.markText(new Pos(0, 1), new Pos(0, 3), className: "CodeMirror-matchingbracket");

      marker2 = editor.markText(new Pos(0, 0), new Pos(2, 1), className: "CodeMirror-matchingbracket");
      bookmark = editor.setBookmark(new Pos(1, 5));
      editor.operation(editor, (){
        editor.replaceRange("foo", new Pos(0, 2));
        editor.replaceRange("bar\nbaz\nbug\n", new Pos(2, 0), new Pos(3, 0));
      });
      var v1 = editor.getValue();
      editor.setValue("");
      expect(marker1.find(), isNull);
      expect(marker2.find(), isNull);
      expect(bookmark.find(), isNull);
      editor.undo();
      expect(bookmark.find(), new Pos(1, 5));
      editor.undo();
      var m1Pos = marker1.find(), m2Pos = marker2.find();
      expect(m1Pos.from, new Pos(0, 1));
      expect(m1Pos.to, new Pos(0, 3));
      expect(m2Pos.from, new Pos(0, 0));
      expect(m2Pos.to, new Pos(2, 1));
      expect(bookmark.find(), new Pos(1, 5));
      editor.redo(); editor.redo();
      expect(bookmark.find(), isNull);
      editor.undo();
      expect(bookmark.find(), new Pos(1, 5));
      expect(editor.getValue(), v1);
    });

    test('markTextStayGone', () {
      editor = makeEditor({'value': "hello"});
      var m1 = editor.markText(new Pos(0, 0), new Pos(0, 1));
      editor.replaceRange("hi", new Pos(0, 2));
      m1.clear();
      editor.undo();
      expect(m1.find(), isNull);
    });

    test('markTextAllowEmpty', () {
      editor = makeEditor({'value': "abcde"});
      var m1 = editor.markText(new Pos(0, 1), new Pos(0, 2), clearWhenEmpty: false);
      expect(m1.find(), isNotNull);
      editor.replaceRange("x", new Pos(0, 0));
      expect(m1.find(), isNotNull);
      editor.replaceRange("y", new Pos(0, 2));
      expect(m1.find(), isNotNull);
      editor.replaceRange("z", new Pos(0, 3), new Pos(0, 4));
      expect(m1.find(), isNull);
      var m2 = editor.markText(new Pos(0, 1), new Pos(0, 2), clearWhenEmpty: false,
          inclusiveLeft: true, inclusiveRight: true);
      editor.replaceRange("q", new Pos(0, 1), new Pos(0, 2));
      expect(m2.find(), isNotNull);
      editor.replaceRange("", new Pos(0, 0), new Pos(0, 3));
      expect(m2.find(), isNull);
      var m3 = editor.markText(new Pos(0, 1), new Pos(0, 1), clearWhenEmpty: false);
      editor.replaceRange("a", new Pos(0, 3));
      expect(m3.find(), isNotNull);
      editor.replaceRange("b", new Pos(0, 1));
      expect(m3.find(), isNull);
    });

    test('markTextStacked', () {
      editor = makeEditor({'value': "A"});
      var m1 = editor.markText(new Pos(0, 0), new Pos(0, 0), clearWhenEmpty: false);
      var m2 = editor.markText(new Pos(0, 0), new Pos(0, 0), clearWhenEmpty: false);
      editor.replaceRange("B", new Pos(0, 1));
      expect(m1.find(), isNotNull);
      expect(m2.find(), isNotNull);
    });

    test('undoPreservesNewMarks', () {
      editor = makeEditor({'value': "aaaa\nbbbb\ncccc\ndddd"});
      editor.markText(new Pos(0, 3), new Pos(0, 4));
      editor.markText(new Pos(1, 1), new Pos(1, 3));
      editor.replaceRange("", new Pos(0, 3), new Pos(3, 1));
      var mBefore = editor.markText(new Pos(0, 0), new Pos(0, 1));
      var mAfter = editor.markText(new Pos(0, 5), new Pos(0, 6));
      var mAround = editor.markText(new Pos(0, 2), new Pos(0, 4));
      editor.undo();
      expect(mBefore.find().from, new Pos(0, 0));
      expect(mBefore.find().to, new Pos(0, 1));
      expect(mAfter.find().from, new Pos(3, 3));
      expect(mAfter.find().to, new Pos(3, 4));
      expect(mAround.find().from, new Pos(0, 2));
      expect(mAround.find().to, new Pos(3, 2));
      var found = editor.findMarksAt(new Pos(2, 2));
      expect(found.length, 1);
      expect(found[0], mAround);
    });

    test('markClearBetween', () {
      editor = makeEditor();
      editor.setValue("aaa\nbbb\nccc\nddd\n");
      editor.markText(new Pos(0, 0), new Pos(2));
      editor.replaceRange("aaa\nbbb\nccc", new Pos(0, 0), new Pos(2));
      expect(editor.findMarksAt(new Pos(1, 1)).length, 0);
    });

    test('deleteSpanCollapsedInclusiveLeft', () {
      editor = makeEditor({'value': "abc\nX\ndef"});
      var from = new Pos(1, 0), to = new Pos(1, 1);
      editor.markText(from, to, collapsed: true, inclusiveLeft: true);
      // Delete collapsed span.
      editor.replaceRange("", from, to);
      expect(editor.getValue(), "abc\n\ndef");
    });

    test('markTextCSS', () {
      editor = makeEditor({'value': "abcdefgh"});
      present() {
        List<SpanElement> spans = getElementsByTagName(editor.display.lineDiv, "span");
        for (var i = 0; i < spans.length; i++) {
          if ((spans[i].style.color == "rgb(0, 255, 255)" ||
              // Added test for "cyan" to make Firefox happy.
              spans[i].style.color == "cyan") && spans[i].text == "cdef")
            return true;
        }
        return false;
      }
      var m = editor.markText(new Pos(0, 2), new Pos(0, 6), css: "color: cyan");
      expect(present(), isTrue, reason: 'mark not found');
      m.clear();
      expect(present(), isFalse,reason: 'mark not cleared');
    });

    test('bookmark', () {
      editor = makeEditor();
      p(v) { return v == null ? null : new Pos(v[0], v[1]); }
      var l = [{'a': [1, 0], 'b': [1, 1], 'c': "", 'd': [1, 4]},
               {'a': [1, 1], 'b': [1, 1], 'c': "xx", 'd': [1, 7]},
               {'a': [1, 4], 'b': [1, 5], 'c': "ab", 'd': [1, 6]},
               {'a': [1, 4], 'b': [1, 6], 'c': "", 'd': null},
               {'a': [1, 5], 'b': [1, 6], 'c': "abc", 'd': [1, 5]},
               {'a': [1, 6], 'b': [1, 8], 'c': "", 'd': [1, 5]},
               {'a': [1, 4], 'b': [1, 4], 'c': "\n\n", 'd': [3, 1]},
               {'bm': [1, 9], 'a': [1, 1], 'b': [1, 1], 'c': "\n", 'd': [2, 8]}];
      l.forEach((test) {
        editor.setValue("1234567890\n1234567890\n1234567890");
        var bm = p(test['bm']);
        var b = editor.setBookmark(bm != null ? bm : new Pos(1, 5));
        editor.replaceRange(test['c'], p(test['a']), p(test['b']));
        expect(b.find(), p(test['d']));
      });
    });

    test('bookmarkInsertLeft', () {
      editor = makeEditor({'value': "abcdef"});
      var br = editor.setBookmark(new Pos(0, 2), insertLeft: false);
      var bl = editor.setBookmark(new Pos(0, 2), insertLeft: true);
      editor.setCursor(new Pos(0, 2));
      editor.replaceSelection("hi");
      expect(br.find(), new Pos(0, 2));
      expect(bl.find(), new Pos(0, 4));
      editor.replaceRange("", new Pos(0, 4), new Pos(0, 5));
      editor.replaceRange("", new Pos(0, 2), new Pos(0, 4));
      editor.replaceRange("", new Pos(0, 1), new Pos(0, 2));
      // Verify that deleting next to bookmarks doesn't kill them
      expect(br.find(), new Pos(0, 1));
      expect(bl.find(), new Pos(0, 1));
    });

    test('bookmarkCursor', () {
      editor = makeEditor({'value': "foo\nbar\n\n\nx\ny"});
      var pos01 = editor.cursorCoords(new Pos(0, 1)), pos11 = editor.cursorCoords(new Pos(1, 1)),
          pos20 = editor.cursorCoords(new Pos(2, 0)), pos30 = editor.cursorCoords(new Pos(3, 0)),
          pos41 = editor.cursorCoords(new Pos(4, 1));
      editor.setBookmark(new Pos(0, 1), widget: new Text("←"), insertLeft: true);
      editor.setBookmark(new Pos(2, 0), widget: new Text("←"), insertLeft: true);
      editor.setBookmark(new Pos(1, 1), widget: new Text("→"));
      editor.setBookmark(new Pos(3, 0), widget: new Text("→"));
      var new01 = editor.cursorCoords(new Pos(0, 1)), new11 = editor.cursorCoords(new Pos(1, 1)),
          new20 = editor.cursorCoords(new Pos(2, 0)), new30 = editor.cursorCoords(new Pos(3, 0));
      near(new01.left, pos01.left, 1);
      near(new01.top, pos01.top, 1);
      expect(new11.left > pos11.left, isTrue, reason: "at right, middle of line");
      near(new11.top, pos11.top, 1);
      near(new20.left, pos20.left, 1);
      near(new20.top, pos20.top, 1);
      expect(new30.left > pos30.left, isTrue, reason: "at right, empty line");
      near(new30.top, pos30.top, 1);
      editor.setBookmark(new Pos(4, 0), widget: new Text("→"));
      expect(editor.cursorCoords(new Pos(4, 1)).left > pos41.left, isTrue, reason: "single-char bug");
    });

    test('multiBookmarkCursor', () {
      editor = makeEditor({'value': "abcdefg"});
      if (phantom) return;
      var ms = [];
      add(insertLeft) {
        for (var i = 0; i < 3; ++i) {
          var node = document.createElement("span");
          node.innerHtml = "X";
          ms.add(editor.setBookmark(new Pos(0, 1), widget: node, insertLeft: insertLeft));
        }
      }
      var base1 = editor.cursorCoords(new Pos(0, 1)).left;
      var base4 = editor.cursorCoords(new Pos(0, 4)).left;
      add(true);
      near(base1, editor.cursorCoords(new Pos(0, 1)).left, 1);
      ms.forEach((m) { m.clear(); });
      ms.clear;
      add(false);
      near(base4, editor.cursorCoords(new Pos(0, 1)).left, 1);
    });

    test('getAllMarks', () {
      editor = makeEditor();
      addDoc(editor, 10, 10);
      var m1 = editor.setBookmark(new Pos(0, 2));
      var m2 = editor.markText(new Pos(0, 2), new Pos(3, 2));
      var m3 = editor.markText(new Pos(1, 2), new Pos(1, 8));
      var m4 = editor.markText(new Pos(8, 0), new Pos(9, 0));
      expect(editor.getAllMarks().length, 4);
      m1.clear();
      m3.clear();
      expect(editor.getAllMarks().length, 2);
      m2.clear();
      m4.clear();
    });

    test('setValueClears', () {
      editor = makeEditor({'value': "a\nb"});
      editor.addLineClass(0, "wrap", "foo");
      var mark = editor.markText(new Pos(0, 0), new Pos(1, 1),
          inclusiveLeft: true, inclusiveRight: true);
      editor.setValue("foo");
      expect(editor.lineInfo(0).wrapClass, isNull);
      expect(mark.find(), isNull);
    });

    test('bug577', () {
      editor = makeEditor();
      editor.setValue("a\nb");
      editor.clearHistory();
      editor.setValue("fooooo");
      editor.undo();
      expect(editor.getValue(), "a\nb");
    });

    test('scrollSnap', () {
      editor = makeEditor();
      editor.setSize(100, 100);
      addDoc(editor, 200, 200);
      editor.setCursor(new Pos(100, 180));
      var info = editor.getScrollInfo();
      expect(info.left > 0 && info.top > 0, isTrue);
      editor.setCursor(new Pos(0, 0));
      info = editor.getScrollInfo();
      expect(info.left == 0 && info.top == 0, isTrue, reason: "scrolled clean to top");
      editor.setCursor(new Pos(100, 180));
      editor.setCursor(new Pos(199, 0));
      info = editor.getScrollInfo();
      expect(info.left == 0 &&
          info.top + 2 > info.height - editor.getScrollerElement().clientHeight,
        isTrue, reason: "scrolled clean to bottom");
    });

    test('scrollIntoView', () {
      editor = makeEditor();
      if (phantom) return;
      var outer = editor.getWrapperElement().getBoundingClientRect();
      test(line, ch, msg) {
        var pos = new Pos(line, ch);
        editor.scrollIntoView(pos);
        var box = editor.charCoords(pos, "window");
        expect(box.left >= outer.left, isTrue, reason: msg + " (left)");
        expect(box.right <= outer.right, isTrue, reason: msg + " (right)");
        expect(box.top >= outer.top, isTrue, reason: msg + " (top)");
        expect(box.bottom <= outer.bottom, isTrue, reason: msg + " (bottom)");
      }
      addDoc(editor, 200, 200);
      test(199, 199, "bottom right");
      test(0, 0, "top left");
      test(100, 100, "center");
      test(199, 0, "bottom left");
      test(0, 199, "top right");
      test(100, 100, "center again");
    });

    test('scrollBackAndForth', () {
      editor = makeEditor();
      addDoc(editor, 1, 200);
      editor.operation(editor, () {
        editor.scrollIntoView(new Pos(199, 0));
        editor.scrollIntoView(new Pos(4, 0));
      })();
      expect(editor.getScrollInfo().top > 0, isTrue);
    });

    test('selectAllNoScroll', () {
      editor = makeEditor();
      addDoc(editor, 1, 200);
      editor.execCommand("selectAll");
      expect(editor.getScrollInfo().top, 0);
      editor.doc.setCursor(199);
      editor.execCommand("selectAll");
      expect(editor.getScrollInfo().top > 0, isTrue);
    });

    test('selectionPos', () {
      editor = makeEditor(null);
      if (phantom || editor.getOption("inputStyle") != "textarea") return;
      editor.setSize(100, 100);
      addDoc(editor, 200, 100);
      editor.setSelection(new Pos(1, 100), new Pos(98, 100));
      var lineWidth = editor.charCoords(new Pos(0, 200), "local").left;
      var lineHeight = (editor.charCoords(new Pos(99)).top -
          editor.charCoords(new Pos(0)).top) / 100;
      editor.scrollTo(0, 0);
      var selElt = byClassName(editor.getWrapperElement(), "CodeMirror-selected");
      var outer = editor.getWrapperElement().getBoundingClientRect();
      var sawMiddle, sawTop, sawBottom;
      for (var i = 0, e = selElt.length; i < e; ++i) {
        var box = selElt[i].getBoundingClientRect();
        var atLeft = box.left - outer.left < 30;
        var width = box.right - box.left;
        var atRight = box.right - outer.left > .8 * lineWidth;
        if (atLeft && atRight) {
          sawMiddle = true;
          expect(box.bottom - box.top > 90 * lineHeight, isTrue, reason: "middle high");
          expect(width > .9 * lineWidth, isTrue, reason: "middle wide");
        } else {
          expect(width > .4 * lineWidth, isTrue, reason: "top/bot wide enough");
          expect(width < .6 * lineWidth, isTrue, reason: "top/bot slim enough");
          if (atLeft) {
            sawBottom = true;
            expect(box.top - outer.top > 96 * lineHeight, isTrue, reason: "bot below");
          } else if (atRight) {
            sawTop = true;
            expect(box.top - outer.top < 2.1 * lineHeight, isTrue, reason: "top above");
          }
        }
      }
      expect(sawTop && sawBottom && sawMiddle, isTrue, reason: "all parts");
    });

    test('restoreHistory', () {
      editor = makeEditor();
      editor.setValue("abc\ndef");
      editor.replaceRange("hello", new Pos(1, 0), new Pos(1));
      editor.replaceRange("goop", new Pos(0, 0), new Pos(0));
      editor.undo();
      var storedVal = editor.getValue(), storedHist = editor.getHistory();
//      if (window.JSON) storedHist = JSON.parse(JSON.stringify(storedHist));
      expect(storedVal, "abc\nhello");
      editor.setValue("");
      editor.clearHistory();
      expect(editor.historySize().undo, 0);
      editor.setValue(storedVal);
      editor.setHistory(storedHist);
      editor.redo();
      expect(editor.getValue(), "goop\nhello");
      editor.undo(); editor.undo();
      expect(editor.getValue(), "abc\ndef");
    });

    test('doubleScrollbar', () {
      editor = makeEditor();
      var dummy = document.body.append(document.createElement("p"));
      dummy.style.cssText = "height: 50px; overflow: scroll; width: 50px";
      var scrollbarWidth = dummy.offsetWidth + 1 - dummy.clientWidth;
      dummy.remove();
      if (scrollbarWidth < 2) return;
      editor.setSize(null, 100);
      addDoc(editor, 1, 300);
      var wrap = editor.getWrapperElement();
      var lines = byClassName(wrap, "CodeMirror-lines");
      expect(wrap.offsetWidth - lines[0].offsetWidth <= scrollbarWidth * 1.5, isTrue);
    });

    test('weirdLinebreaks', () {
      editor = makeEditor();
      editor.setValue("foo\nbar\rbaz\r\nquux\n\rplop");
      expect(editor.getValue(), "foo\nbar\nbaz\nquux\n\nplop");
      expect(editor.lineCount(), 6);
      editor.setValue("\n\n");
      expect(editor.lineCount(), 3);
    });

    test('setSize', () {
      editor = makeEditor();
      editor.setSize(100, 100);
      var wrap = editor.getWrapperElement();
      near(wrap.offsetWidth, 100, 3);
      near(wrap.offsetHeight, 100, 3);
      editor.setSize("100%", "3em");
      expect(wrap.style.width, "100%");
      expect(wrap.style.height, "3em");
      editor.setSize(null, 40);
      expect(wrap.style.width, "100%");
      expect(wrap.style.height, "40px");
    });

    test('collapsedLines', () {
      editor = makeEditor();
      addDoc(editor, 4, 10);
      var range = foldLines(editor, 4, 5), cleared = 0;
      editor.on(range, "clear", (a,b) {cleared++;}); // Closure arg count must be correct.
      editor.setCursor(new Pos(3, 0));
      editor.commands['goLineDown']();
      expect(editor.getCursor(), new Pos(5, 0));
      editor.replaceRange("abcdefg", new Pos(3, 0), new Pos(3));
      editor.setCursor(new Pos(3, 6));
      editor.commands['goLineDown']();
      expect(editor.getCursor(), new Pos(5, 4));
      editor.replaceRange("ab", new Pos(3, 0), new Pos(3));
      editor.setCursor(new Pos(3, 2));
      editor.commands['goLineDown']();
      expect(editor.getCursor(), new Pos(5, 2));
      editor.operation(editor, () {range.clear(); range.clear();})();
      expect(cleared, 1);
    });

    test('collapsedRangeCoordsChar', () {
      editor = makeEditor({'value': "123456\nabcdef\nghijkl\nmnopqr\n"});
      Rect pos_1_3 = editor.charCoords(new Pos(1, 3));
      pos_1_3.left += 2;
      pos_1_3.top += 2;
      var m1 = editor.markText(new Pos(0, 0), new Pos(2, 0), collapsed: true,
          inclusiveLeft: true, inclusiveRight: true);
      expect(editor.coordsChar(pos_1_3), new Pos(3, 3));
      m1.clear();
      m1 = editor.markText(new Pos(0, 0), new Pos(1, 1), collapsed: true,
          inclusiveLeft: true);
      var m2 = editor.markText(new Pos(1, 1), new Pos(2, 0), collapsed: true,
          inclusiveRight: true);
      expect(editor.coordsChar(pos_1_3), new Pos(3, 3));
      m1.clear(); m2.clear();
      m1 = editor.markText(new Pos(0, 0), new Pos(1, 6), collapsed: true,
          inclusiveLeft: true, inclusiveRight: true);
      expect(editor.coordsChar(pos_1_3), new Pos(3, 3));
    });

    test('collapsedRangeBetweenLinesSelected', () {
      editor = makeEditor({'value': "one\ntwo"});
      if (editor.getOption("inputStyle") != "textarea") return;
      SpanElement widget = document.createElement("span");
      widget.text = "\u2194";
      editor.markText(new Pos(0, 3), new Pos(1, 0), replacedWith: widget);
      editor.setSelection(new Pos(0, 3), new Pos(1, 0));
      var selElts = byClassName(editor.getWrapperElement(), "CodeMirror-selected");
      var w = 0;
      for (var i = 0; i < selElts.length; i++)
        w += selElts[i].offsetWidth;
      expect(w > 0, isTrue);
    });

    test('randomCollapsedRanges', () {
      editor = makeEditor();
      addDoc(editor, 20, 500);
      Random rnd = new Random(0);
      editor.operation(editor, () {
        for (var i = 0; i < 200; i++) {
          var start = new Pos(rnd.nextInt(500), rnd.nextInt(20));
          if (i % 4 != 0) {
            try {
              editor.markText(start, new Pos(start.line + 2, 1), collapsed: true);
            } catch(e) {
              var re = new RegExp("overlapping");
              if (!re.hasMatch(e.message)) {
                throw e;
              }
            }
          } else {
            editor.markText(start, new Pos(start.line, start.char + 4), className: "foo");
          }
        }
      })();
    });

    test('hiddenLinesAutoUnfold', () {
      editor = makeEditor({'value': "abc\ndef\nghi\njkl"});
      var range = foldLines(editor, 1, 3, true);
      var cleared = 0;
      editor.on(range, "clear", (a,b) {cleared++;}); // Closure args must match call
      editor.setCursor(new Pos(3, 0));
      expect(cleared, 0);
      editor.execCommand("goCharLeft");
      expect(cleared, 1);
      range = foldLines(editor, 1, 3, true);
      editor.on(range, "clear", (a,b) {cleared++;});
      expect(editor.getCursor(), new Pos(3, 0));
      editor.setCursor(new Pos(0, 3));
      editor.execCommand("goCharRight");
      expect(cleared, 2);
    });

    test('hiddenLinesSelectAll', () {
      editor = makeEditor();
      addDoc(editor, 4, 20);
      foldLines(editor, 0, 10);
      foldLines(editor, 11, 20);
      editor.commands['selectAll']();
      expect(editor.getCursor(true), new Pos(10, 0));
      expect(editor.getCursor(false), new Pos(10, 4));
    });

    test('everythingFolded', () {
      editor = makeEditor();
      addDoc(editor, 2, 2);
      enterPress() {
        var e = new KeyEvent("keydown", keyCode: 13);
        editor.triggerOnKeyDown(e);
      }
      var fold = foldLines(editor, 0, 2);
      enterPress();
      expect(editor.getValue(), "xx\nxx");
      fold.clear();
      fold = foldLines(editor, 0, 2, true);
      expect(fold.find(), isNull);
      enterPress();
      expect(editor.getValue(), "\nxx\nxx");
    });

    test('structuredFold', () {
      editor = makeEditor(null);
      if (phantom) return;
      addDoc(editor, 4, 8);
      var range = editor.markText(new Pos(1, 2), new Pos(6, 2),
        replacedWith: new Text("Q")
      );
      editor.doc.setCursor(0, 3);
      editor.commands['goLineDown']();
      expect(editor.getCursor(), new Pos(6, 2));
      editor.commands['goCharLeft']();
      expect(editor.getCursor(), new Pos(1, 2));
      editor.commands['delCharAfter']();
      expect(editor.getValue(), "xxxx\nxxxx\nxxxx");
      addDoc(editor, 4, 8);
      range = editor.markText(new Pos(1, 2), new Pos(6, 2),
        replacedWith: new Text("M"),
        clearOnEnter: true
      );
      var cleared = 0;
      editor.on(range, "clear", (a, b) { ++cleared; });
      editor.doc.setCursor(0, 3);
      editor.commands['goLineDown']();
      expect(editor.getCursor(), new Pos(6, 2));
      editor.commands['goCharLeft']();
      expect(editor.getCursor(), new Pos(6, 1));
      expect(cleared, 1);
      range.clear();
      expect(cleared, 1);
      range = editor.markText(new Pos(1, 2), new Pos(6, 2),
        replacedWith: new Text("Q"),
        clearOnEnter: true
      );
      range.clear();
      editor.doc.setCursor(1, 2);
      editor.commands['goCharRight']();
      expect(editor.getCursor(), new Pos(1, 3));
      range = editor.markText(new Pos(2, 0), new Pos(4, 4),
        replacedWith: new Text("M")
      );
      editor.doc.setCursor(1, 0);
      editor.commands['goLineDown']();
      expect(editor.getCursor(), new Pos(2, 0));
    });

    test('nestedFold', () {
      editor = makeEditor();
      addDoc(editor, 10, 3);
      fold(ll, cl, lr, cr) {
        return editor.markText(new Pos(ll, cl), new Pos(lr, cr), collapsed: true);
      }
      var inner1 = fold(0, 6, 1, 3), inner2 = fold(0, 2, 1, 8);
      var outer = fold(0, 1, 2, 3), inner0 = fold(0, 5, 0, 6);
      editor.doc.setCursor(0, 1);
      editor.commands['goCharRight']();
      expect(editor.getCursor(), new Pos(2, 3));
      inner0.clear();
      editor.commands['goCharLeft']();
      expect(editor.getCursor(), new Pos(0, 1));
      outer.clear();
      editor.commands['goCharRight']();
      expect(editor.getCursor(), new Pos(0, 2));
      editor.commands['goCharRight']();
      expect(editor.getCursor(), new Pos(1, 8));
      inner2.clear();
      editor.commands['goCharLeft']();
      expect(editor.getCursor(), new Pos(1, 7));
      editor.doc.setCursor(0, 5);
      editor.commands['goCharRight']();
      expect(editor.getCursor(), new Pos(0, 6));
      editor.commands['goCharRight']();
      expect(editor.getCursor(), new Pos(1, 3));
      inner1.clear();
    });

    test('badNestedFold', () {
      editor = makeEditor();
      addDoc(editor, 4, 4);
      editor.markText(new Pos(0, 2), new Pos(3, 2), collapsed: true);
      var caught;
      try { editor.markText(new Pos(0, 1), new Pos(0, 3), collapsed: true);}
      catch(e) { caught = e; }
      expect(caught is Error, isTrue, reason: "no error");
      expect(new RegExp('overlap', caseSensitive: false).hasMatch(caught.message), isTrue, reason: "wrong error");
    });

    test('nestedFoldOnSide', () {
      editor = makeEditor({'value': "ab\ncd\ef"});
      var m1 = editor.markText(new Pos(0, 1), new Pos(2, 1), collapsed: true, inclusiveRight: true);
      var m2 = editor.markText(new Pos(0, 1), new Pos(0, 2), collapsed: true);
      editor.markText(new Pos(0, 1), new Pos(0, 2), collapsed: true).clear();
      var caught;
      try {
        editor.markText(new Pos(0, 1), new Pos(0, 2), collapsed: true, inclusiveLeft: true);
      } catch(e) {
        caught = e;
      }
      var re = new RegExp('overlap', caseSensitive: false);
      expect(caught, isNotNull);
      expect(re.hasMatch(caught.message), isTrue);
      var m3 = editor.markText(new Pos(2, 0), new Pos(2, 1), collapsed: true);
      var m4 = editor.markText(new Pos(2, 0), new Pos(2, 1), collapsed: true, inclusiveRight: true);
      m1.clear(); m4.clear();
      m1 = editor.markText(new Pos(0, 1), new Pos(2, 1), collapsed: true);
      editor.markText(new Pos(2, 0), new Pos(2, 1), collapsed: true).clear();
      try {
        editor.markText(new Pos(2, 0), new Pos(2, 1), collapsed: true, inclusiveRight: true);
      } catch(e) {
        caught = e;
      }
      expect(caught, isNotNull);
      expect(re.hasMatch(caught.message), isTrue);
      m2.clear();
      m3.clear();
    });

    test('editInFold', () {
      editor = makeEditor();
      addDoc(editor, 4, 6);
      editor.markText(new Pos(1, 2), new Pos(3, 2), collapsed: true);
      editor.replaceRange("", new Pos(0, 0), new Pos(1, 3));
      editor.replaceRange("", new Pos(2, 1), new Pos(3, 3));
      editor.replaceRange("a\nb\nc\nd", new Pos(0, 1), new Pos(1, 0));
      editor.cursorCoords(new Pos(0, 0));
    });

    test('wrappingInlineWidget', () {
      editor = makeEditor({'value': "1 2 3 xxx 4", 'lineWrapping': true});
      editor.setSize("11em");
      SpanElement w = document.createElement("span");
      w.style.color = "red";
      w.innerHtml = "one two three four";
      editor.markText(new Pos(0, 6), new Pos(0, 9), replacedWith: w);
      var cur0 = editor.cursorCoords(new Pos(0, 0));
      var cur1 = editor.cursorCoords(new Pos(0, 10));
      expect(cur0.top < cur1.top, isTrue);
      expect(cur0.bottom < cur1.bottom, isTrue);
      var curL = editor.cursorCoords(new Pos(0, 6));
      var curR = editor.cursorCoords(new Pos(0, 9));
      expect(curL.top, cur0.top);
      expect(curL.bottom, cur0.bottom);
      expect(curR.top, cur1.top);
      expect(curR.bottom, cur1.bottom);
      editor.replaceRange("", new Pos(0, 9), new Pos(0));
      curR = editor.cursorCoords(new Pos(0, 9));
      if (phantom) return;
      expect(curR.top, cur1.top);
      expect(curR.bottom, cur1.bottom);
    });

    test('changedInlineWidget', () {
      editor = makeEditor({'value': "hello there"});
      editor.setSize("10em");
      SpanElement w = document.createElement("span");
      w.innerHtml = "x";
      var m = editor.markText(new Pos(0, 4), new Pos(0, 5), replacedWith: w);
      w.innerHtml = "and now the widget is really really long all of a sudden and a scrollbar is needed";
      m.changed();
      var hScroll = byClassName(editor.getWrapperElement(), "CodeMirror-hscrollbar")[0];
      expect(hScroll.scrollWidth > hScroll.clientWidth, isTrue);
    });

    test('changedBookmark', () {
      editor = makeEditor({'value': "abcdefg"});
      editor.setSize("10em");
      SpanElement w = document.createElement("span");
      w.innerHtml = "x";
      var m = editor.setBookmark(new Pos(0, 4), widget: w);
      w.innerHtml = "and now the widget is really really long all of a sudden and a scrollbar is needed";
      m.changed();
      var hScroll = byClassName(editor.getWrapperElement(), "CodeMirror-hscrollbar")[0];
      expect(hScroll.scrollWidth > hScroll.clientWidth, isTrue);
    });

    test('inlineWidget', () {
      editor = makeEditor({'value': "uuuu\nuuuuuu"});
      var w = editor.setBookmark(new Pos(0, 2), widget: new Text("uu"));
      editor.doc.setCursor(0, 2);
      editor.commands['goLineDown']();
      expect(editor.getCursor(), new Pos(1, 4));
      editor.doc.setCursor(0, 2);
      editor.replaceSelection("hi");
      expect(w.find(), new Pos(0, 2));
      editor.doc.setCursor(0, 1);
      editor.replaceSelection("ay");
      expect(w.find(), new Pos(0, 4));
      expect(editor.getLine(0), "uayuhiuu");
    });

    test('wrappingAndResizing', () {
      if (ie_lt8) fail("IE 8");
      editor = makeEditor(null);
      editor.setSize(null, "auto");
      editor.setOption("lineWrapping", true);
      var wrap = editor.getWrapperElement();
      var h0 = wrap.offsetHeight;
      var str = "xxx xxx xxx xxx xxx";
      editor.setValue(str);
      for (var step = 10, w = editor.charCoords(new Pos(0, 18), "div").right;; w += step) {
        editor.setSize(w);
        if (wrap.offsetHeight <= h0 * (opera_lt10 ? 1.2 : 1.5)) {
          if (step == 10) { w -= 10; step = 1; }
          else break;
        }
      }
      // Ensure that putting the cursor at the end of the maximally long
      // line doesn't cause wrapping to happen.
      editor.setCursor(new Pos(0, str.length));
      expect(wrap.offsetHeight, h0);
      editor.replaceSelection("x");
      expect(wrap.offsetHeight > h0, isTrue, reason: "wrapping happens");
      // Now add a max-height and, in a document consisting of
      // almost-wrapped lines, go over it so that a scrollbar appears.
      editor.setValue(str + "\n" + str + "\n");
      editor.getScrollerElement().style.maxHeight = "100px";
      editor.replaceRange("\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n!\n", new Pos(2, 0));
      var l = [new Pos(0, str.length), new Pos(0, str.length - 1),
               new Pos(0, 0), new Pos(1, str.length), new Pos(1, str.length - 1)];
      l.forEach((pos) {
        var coords = editor.charCoords(pos);
        expect(pos, editor.coordsChar(new Loc(coords.top + 5, coords.left + 2)));
      });
    });

    test('measureEndOfLine', () {
      if (ie_lt8 || opera_lt10) fail("Old browser");
      editor = makeEditor({'mode': "text/html", 'value': "<!-- foo barrr -->", 'lineWrapping': true});
      editor.setSize(null, "auto");
      var inner = byClassName(editor.getWrapperElement(), "CodeMirror-lines")[0].firstChild;
      var lh = inner.offsetHeight;
      var w = editor.charCoords(new Pos(0, 7), "div").right;
      for (var step = 10;; w += step) {
        editor.setSize(w);
        if (inner.offsetHeight < 2.5 * lh) {
          if (step == 10) { w -= 10; step = 1; }
          else break;
        }
      }
      editor.setValue(editor.getValue() + "\n\n");
      var endPos = editor.charCoords(new Pos(0, 18), "local");
      expect(endPos.top > lh * .8, isTrue, reason: "not at top");
      expect(endPos.left > w - 20, isTrue, reason: "not at right");
      endPos = editor.charCoords(new Pos(0, 18));
      expect(editor.coordsChar(new Loc(endPos.top + 5, endPos.left)), new Pos(0, 18));
    });

    test('scrollVerticallyAndHorizontally', () {
      editor = makeEditor({'lineNumbers': true});
      if (editor.getOption("inputStyle") != "textarea") return;
      editor.setSize(100, 100);
      addDoc(editor, 40, 40);
      editor.doc.setCursor(39);
      var wrap = editor.getWrapperElement();
      var bar = byClassName(wrap, "CodeMirror-vscrollbar")[0];
      expect(bar.offsetHeight < wrap.offsetHeight, isTrue,
          reason: "vertical scrollbar limited by horizontal one");
      var cursorBox = byClassName(wrap, "CodeMirror-cursor")[0].getBoundingClientRect();
      var editorBox = wrap.getBoundingClientRect();
      num scrollerHeight = editor.getScrollerElement().clientHeight;
      expect(cursorBox.bottom < editorBox.top + scrollerHeight, isTrue,
         reason: "bottom line visible");
    });

    test('moveVstuck', () {
      if (ie_lt8 || opera_lt10) fail("Old browser");
      editor = makeEditor({'lineWrapping': true});
      var lines = byClassName(editor.getWrapperElement(), "CodeMirror-lines")[0].firstChild;
      var h0 = lines.offsetHeight;
      var val = "fooooooooooooooooooooooooo baaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaar\n";
      editor.setValue(val);
      for (var w = editor.charCoords(new Pos(0, 26), "div").right * 2.8;; w += 5) {
        editor.setSize(w);
        if (lines.offsetHeight <= 3.5 * h0) break;
      }
      editor.setCursor(new Pos(0, val.length - 1));
      editor.moveV(-1, "line");
      expect(editor.getCursor(), new Pos(0, 26));
    });

    test('collapseOnMove', () {
      editor = makeEditor({'value': "aaaaa\nb\nccccc"});
      editor.setSelection(new Pos(0, 1), new Pos(2, 4));
      editor.execCommand("goLineUp");
      expect(editor.somethingSelected(), isFalse);
      expect(editor.getCursor(), new Pos(0, 1));
      editor.setSelection(new Pos(0, 1), new Pos(2, 4));
      editor.execCommand("goPageDown");
      expect(editor.somethingSelected(), isFalse);
      expect(editor.getCursor(), new Pos(2, 4));
      editor.execCommand("goLineUp");
      editor.execCommand("goLineUp");
      expect(editor.getCursor(), new Pos(0, 4));
      editor.setSelection(new Pos(0, 1), new Pos(2, 4));
      editor.execCommand("goCharLeft");
      expect(editor.somethingSelected(), isFalse);
      expect(editor.getCursor(), new Pos(0, 1));
    });

    test('clickTab', () {
      editor = makeEditor({'value': "\t\n\n", 'lineWrapping': true, 'tabSize': 8});
      var p0 = editor.charCoords(new Pos(0, 0));
      expect(editor.coordsChar(new Loc(p0.top + 5, p0.left + 5)), new Pos(0, 0));
      expect(editor.coordsChar(new Loc(p0.top + 5, p0.right - 5)), new Pos(0, 1));
    });

    test('verticalScroll', () {
      editor = makeEditor();
      editor.setSize(100, 200);
      editor.setValue("foo\nbar\nbaz\n");
      var sc = editor.getScrollerElement();
      var baseWidth = sc.scrollWidth;
      editor.replaceRange("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaah", new Pos(0, 0), new Pos(0));
      expect(sc.scrollWidth > baseWidth, isTrue, reason: "scrollbar present");
      editor.replaceRange("foo", new Pos(0, 0), new Pos(0));
      if (!phantom) expect(sc.scrollWidth, baseWidth, reason: "scrollbar gone");
      editor.replaceRange("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaah", new Pos(0, 0), new Pos(0));
      editor.replaceRange("bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbh", new Pos(1, 0), new Pos(1));
      expect(sc.scrollWidth > baseWidth, isTrue, reason: "present again");
      var curWidth = sc.scrollWidth;
      editor.replaceRange("foo", new Pos(0, 0), new Pos(0));
      expect(sc.scrollWidth < curWidth, isTrue, reason: "scrollbar smaller");
      expect(sc.scrollWidth > baseWidth, isTrue, reason: "but still present");
    });

    test('extraKeys', () {
      if (opera && mac) fail("Mac Opera failure");
      editor = makeEditor(null);
      var outcome;
      fakeKey(expected, code, {ctrlKey: false, altKey: false, shiftKey: false}) {
        if (code is String) code = code.codeUnitAt(0);
//        var e = {type: "keydown", keyCode: code, preventDefault: (){}, stopPropagation: (){}};
        var e = new KeyEvent("keydown", keyCode: code,
            ctrlKey: ctrlKey, altKey: altKey, shiftKey: shiftKey);
        outcome = null;
        editor.triggerOnKeyDown(e);
        expect(outcome, expected);
      }
      editor.commands['testCommand'] = (cm) {outcome = "tc";};
      editor.commands['goTestCommand'] = (cm) {outcome = "gtc";};
      editor.setOption("extraKeys", {"Shift-X": (cm) {outcome = "sx";},
                                     "X": (cm) {outcome = "x";},
                                     "Ctrl-Alt-U": (cm) {outcome = "cau";},
                                     "End": "testCommand",
                                     "Home": "goTestCommand",
                                     "Tab": false});
      fakeKey(null, "U");
      fakeKey("cau", "U", ctrlKey: true, altKey: true);
      fakeKey(null, "U", shiftKey: true, ctrlKey: true, altKey: true);
      fakeKey("x", "X");
      fakeKey("sx", "X", shiftKey: true);
      fakeKey("tc", 35);
      fakeKey(null, 35, shiftKey: true);
      fakeKey("gtc", 36);
      fakeKey("gtc", 36, shiftKey: true);
      fakeKey(null, 9);
    });

    test('wordMovementCommands', () {
      editor = makeEditor({'value': "this is (the) firstline.\na foo12\u00e9\u00f8\u00d7bar\n"});
      initHelpers(editor);
      editor.execCommand("goWordLeft");
      expect(editor.getCursor(), new Pos(0, 0));
      editor.execCommand("goWordRight"); editor.execCommand("goWordRight");
      expect(editor.getCursor(), new Pos(0, 7));
      editor.execCommand("goWordLeft");
      expect(editor.getCursor(), new Pos(0, 5));
      editor.execCommand("goWordRight"); editor.execCommand("goWordRight");
      expect(editor.getCursor(), new Pos(0, 12));
      editor.execCommand("goWordLeft");
      expect(editor.getCursor(), new Pos(0, 9));
      editor.execCommand("goWordRight"); editor.execCommand("goWordRight");
      editor.execCommand("goWordRight");
      expect(editor.getCursor(), new Pos(0, 24));
      editor.execCommand("goWordRight"); editor.execCommand("goWordRight");
      expect(editor.getCursor(), new Pos(1, 9));
      editor.execCommand("goWordRight");
      expect(editor.getCursor(), new Pos(1, 13));
      editor.execCommand("goWordRight"); editor.execCommand("goWordRight");
      expect(editor.getCursor(), new Pos(2, 0));
    });

    test('groupMovementCommands', () {
      editor = makeEditor({'value': "booo ba---quux. ffff\n  abc d"});
      editor.execCommand("goGroupLeft");
      expect(editor.getCursor(), new Pos(0, 0));
      editor.execCommand("goGroupRight");
      expect(editor.getCursor(), new Pos(0, 4));
      editor.execCommand("goGroupRight");
      expect(editor.getCursor(), new Pos(0, 7));
      editor.execCommand("goGroupRight");
      expect(editor.getCursor(), new Pos(0, 10));
      editor.execCommand("goGroupLeft");
      expect(editor.getCursor(), new Pos(0, 7));
      editor.execCommand("goGroupRight"); editor.execCommand("goGroupRight"); editor.execCommand("goGroupRight");
      expect(editor.getCursor(), new Pos(0, 15));
      editor.setCursor(new Pos(0, 17));
      editor.execCommand("goGroupLeft");
      expect(editor.getCursor(), new Pos(0, 16));
      editor.execCommand("goGroupLeft");
      expect(editor.getCursor(), new Pos(0, 14));
      editor.execCommand("goGroupRight"); editor.execCommand("goGroupRight");
      expect(editor.getCursor(), new Pos(0, 20));
      editor.execCommand("goGroupRight");
      expect(editor.getCursor(), new Pos(1, 0));
      editor.execCommand("goGroupRight");
      expect(editor.getCursor(), new Pos(1, 2));
      editor.execCommand("goGroupRight");
      expect(editor.getCursor(), new Pos(1, 5));
      editor.execCommand("goGroupLeft"); editor.execCommand("goGroupLeft");
      expect(editor.getCursor(), new Pos(1, 0));
      editor.execCommand("goGroupLeft");
      expect(editor.getCursor(), new Pos(0, 20));
      editor.execCommand("goGroupLeft");
      expect(editor.getCursor(), new Pos(0, 16));
    });

    test('groupsAndWhitespace', () {
      editor = makeEditor({'value': "  foo +++  \n  bar"});
      var positions = [new Pos(0, 0), new Pos(0, 2), new Pos(0, 5), new Pos(0, 9), new Pos(0, 11),
                       new Pos(1, 0), new Pos(1, 2), new Pos(1, 5)];
      for (var i = 1; i < positions.length; i++) {
        editor.execCommand("goGroupRight");
        expect(editor.getCursor(), positions[i]);
      }
      for (var i = positions.length - 2; i >= 0; i--) {
        editor.execCommand("goGroupLeft");
        expect(editor.getCursor(), i == 2 ? new Pos(0, 6) : positions[i]);
      }
    });

    test('charMovementCommands', () {
      editor = makeEditor({'value': "line1\n ine2\n"});
      editor.execCommand("goCharLeft"); editor.execCommand("goColumnLeft");
      expect(editor.getCursor(), new Pos(0, 0));
      editor.execCommand("goCharRight"); editor.execCommand("goCharRight");
      expect(editor.getCursor(), new Pos(0, 2));
      editor.setCursor(new Pos(1, 0));
      editor.execCommand("goColumnLeft");
      expect(editor.getCursor(), new Pos(1, 0));
      editor.execCommand("goCharLeft");
      expect(editor.getCursor(), new Pos(0, 5));
      editor.execCommand("goColumnRight");
      expect(editor.getCursor(), new Pos(0, 5));
      editor.execCommand("goCharRight");
      expect(editor.getCursor(), new Pos(1, 0));
      editor.execCommand("goLineEnd");
      expect(editor.getCursor(), new Pos(1, 5));
      editor.execCommand("goLineStartSmart");
      expect(editor.getCursor(), new Pos(1, 1));
      editor.execCommand("goLineStartSmart");
      expect(editor.getCursor(), new Pos(1, 0));
      editor.setCursor(new Pos(2, 0));
      editor.execCommand("goCharRight"); editor.execCommand("goColumnRight");
      expect(editor.getCursor(), new Pos(2, 0));
    });

    test('verticalMovementCommands', () {
      editor = makeEditor({'value': "line1\nlong long line2\nline3\n\nline5\n"});
      editor.execCommand("goLineUp");
      editor.execCommand("goLineUp");
      expect(editor.getCursor(), new Pos(0, 0));
      editor.execCommand("goLineDown");
      if (!phantom) // This fails in PhantomJS, though not in a real Webkit
        expect(editor.getCursor(), new Pos(1, 0));
      editor.setCursor(new Pos(1, 12));
      editor.execCommand("goLineDown");
      expect(editor.getCursor(), new Pos(2, 5));
      editor.execCommand("goLineDown");
      expect(editor.getCursor(), new Pos(3, 0));
      editor.execCommand("goLineUp");
      expect(editor.getCursor(), new Pos(2, 5));
      editor.execCommand("goLineUp");
      expect(editor.getCursor(), new Pos(1, 12));
      editor.execCommand("goPageDown");
      expect(editor.getCursor(), new Pos(5, 0));
      editor.execCommand("goPageDown"); editor.execCommand("goLineDown");
      expect(editor.getCursor(), new Pos(5, 0));
      editor.execCommand("goPageUp");
      expect(editor.getCursor(), new Pos(0, 0));
    });

    test('verticalMovementCommandsWrapping', () {
      editor = makeEditor({
        'value': "a very long line that wraps around somehow so that we can test cursor movement\nshortone\nk",
        'lineWrapping': true});
      editor.setSize(120);
      editor.setCursor(new Pos(0, 5));
      editor.execCommand("goLineDown");
      expect(editor.getCursor().line, 0);
      expect(editor.getCursor().char > 5, isTrue, reason: "moved beyond wrap");
      for (var i = 0; ; ++i) {
        expect(i < 20, isTrue, reason: "no endless loop");
        editor.execCommand("goLineDown");
        var cur = editor.getCursor();
        if (cur.line == 1) expect(cur.char, 5);
        if (cur.line == 2) { expect(cur.char, 1); break; }
      }
    });

    test('rtlMovement', () {
      if (ie_lt9) fail('IE9');
      editor = makeEditor(null);
      if (editor.getOption("inputStyle") != "textarea") return;
      var l = ["خحج", "خحabcخحج", "abخحخحجcd", "abخde", "abخح2342خ1حج", "خ1ح2خح3حxج",
               "خحcd", "1خحcd", "abcdeح1ج", "خمرحبها مها!", "foobarر", "خ ة ق",
               "<img src=\"/בדיקה3.jpg\">"];
      l.forEach((String line) {
        var inv = line.startsWith("خ");
        editor.setValue(line + "\n");
        editor.execCommand(inv ? "goLineEnd" : "goLineStart");
        var cursors = byClassName(editor.getWrapperElement(), "CodeMirror-cursors")[0];
        var cursor = cursors.firstChild;
        var prevX = cursor.offsetLeft, prevY = cursor.offsetTop;
        for (var i = 0; i <= line.length; ++i) {
          editor.execCommand("goCharRight");
          cursor = cursors.firstChild;
          if (i == line.length) expect(cursor.offsetTop > prevY, isTrue, reason: "next line");
          else expect(cursor.offsetLeft > prevX, isTrue, reason: "moved right");
          prevX = cursor.offsetLeft; prevY = cursor.offsetTop;
        }
        editor.doc.setCursor(0, 0);
        editor.execCommand(inv ? "goLineStart" : "goLineEnd");
        prevX = cursors.firstChild.offsetLeft;
        for (var i = 0; i < line.length; ++i) {
          editor.execCommand("goCharLeft");
          cursor = cursors.firstChild;
          expect(cursor.offsetLeft < prevX, isTrue, reason: "moved left");
          prevX = cursor.offsetLeft;
        }
      });
    });

    test('bidiUpdate', () {
      // Verify that updating a line clears its bidi ordering
      editor = makeEditor({'value': "abcd\n"});
      editor.doc.setCursor(new Pos(0, 2));
      editor.replaceSelection("خحج", "start");
      editor.execCommand("goCharRight");
      expect(editor.getCursor(), new Pos(0, 4));
    });

    test('movebyTextUnit', () {
      editor = makeEditor();
      editor.setValue("בְּרֵאשִ\nééé́\n");
      editor.execCommand("goLineEnd");
      for (var i = 0; i < 4; ++i) editor.execCommand("goCharRight");
      expect(editor.getCursor(), new Pos(0, 0));
      editor.execCommand("goCharRight");
      expect(editor.getCursor(), new Pos(1, 0));
      editor.execCommand("goCharRight");
      editor.execCommand("goCharRight");
      expect(editor.getCursor(), new Pos(1, 4));
      editor.execCommand("goCharRight");
      expect(editor.getCursor(), new Pos(1, 7));
    });

    test('lineChangeEvents', () {
      editor = makeEditor();
      addDoc(editor, 3, 5);
      var log = [];
      var want = ["ch 0", "ch 1", "del 2", "ch 0", "ch 0", "del 1", "del 3", "del 4"];
      for (var i = 0; i < 5; ++i) {
        editor.on(editor.getLineHandle(i), "delete", () { log.add("del $i"); });
        editor.on(editor.getLineHandle(i), "change", (l,c) { log.add("ch $i"); });
      }
      editor.replaceRange("x", new Pos(0, 1));
      editor.replaceRange("xy", new Pos(1, 1), new Pos(2));
      editor.replaceRange("foo\nbar", new Pos(0, 1));
      editor.replaceRange("", new Pos(0, 0), new Pos(editor.lineCount()));
      expect(log.length, want.length, reason: "same length");
      for (var i = 0; i < log.length; ++i)
        expect(log[i], want[i]);
    });

    test('scrollEntirelyToRight', () {
      editor = makeEditor();
      if (phantom || editor.getOption("inputStyle") != "textarea") return;
      addDoc(editor, 500, 2);
      editor.setCursor(new Pos(0, 500));
      var wrap = editor.getWrapperElement();
      var cur = byClassName(wrap, "CodeMirror-cursor")[0];
      var wrapper = wrap.getBoundingClientRect();
      var cursor = cur.getBoundingClientRect();
      expect(wrapper.right > cursor.left, isTrue);
    });

    test('lineWidgets', () {
      editor = makeEditor();
      addDoc(editor, 500, 3);
      var last = editor.charCoords(new Pos(2, 0));
      DivElement node = document.createElement("div");
      node.innerHtml = "hi";
      editor.addLineWidget(1, node);
      expect(last.top < editor.charCoords(new Pos(2, 0)).top, isTrue, reason: "took up space");
      editor.setCursor(new Pos(1, 1));
      editor.execCommand("goLineDown");
      expect(editor.getCursor(), new Pos(2, 1));
      editor.execCommand("goLineUp");
      expect(editor.getCursor(), new Pos(1, 1));
    });

    test('lineWidgetFocus', () {
      editor = makeEditor();
      var place = document.getElementById("testground");
      place.className = "offscreen";
      try {
        addDoc(editor, 500, 10);
        var node = document.createElement("input");
        editor.addLineWidget(1, node);
        node.focus();
        expect(document.activeElement, node);
        editor.replaceRange("new stuff", new Pos(1, 0));
        expect(document.activeElement, node);
      } finally {
        place.className = "";
      }
    });

    test('lineWidgetCautiousRedraw', () {
      editor = makeEditor({'value': "123\n456"});
      DivElement node = document.createElement("div");
      node.innerHtml = "hahah";
      var w = editor.addLineWidget(0, node);
      var redrawn = false;
      w.on(w, "redraw", () { redrawn = true; });
      editor.replaceSelection("0");
      expect(redrawn, isFalse);
    });

    test('lineWidgetChanged', () {
      editor = makeEditor();
      addDoc(editor, 2, 300);
      num halfScrollbarWidth = scrollbarWidth() / 2;
      editor.setOption('lineNumbers', true);
      editor.setSize(600, editor.defaultTextHeight() * 50);
      editor.scrollTo(null, editor.heightAtLine(125, "local"));
      var lst = ['','',''];

      var expectedWidgetHeight = 60;
      var expectedLinesInWidget = 3;
      DivElement w() {
        DivElement node = document.createElement("div");
        // we use these children with just under half width of the line to check measurements are made with correct width
        // when placed in the measure div.
        // If the widget is measured at a width much narrower than it is displayed at, the underHalf children will span two lines and break the test.
        // If the widget is measured at a width much wider than it is displayed at, the overHalf children will combine and break the test.
        // Note that this test only checks widgets where coverGutter is true, because these require extra styling to get the width right.
        // It may also be worthwhile to check this for non-coverGutter widgets.
        // Visually:
        // Good:
        // | ------------- display width ------------- |
        // | ------- widget-width when measured ------ |
        // | | -- under-half -- | | -- under-half -- | |
        // | | --- over-half --- |                     |
        // | | --- over-half --- |                     |
        // Height: measured as 3 lines, same as it will be when actually displayed

        // Bad (too narrow):
        // | ------------- display width ------------- |
        // | ------ widget-width when measured ----- |  < -- uh oh
        // | | -- under-half -- |                    |
        // | | -- under-half -- |                    |  < -- when measured, shoved to next line
        // | | --- over-half --- |                   |
        // | | --- over-half --- |                   |
        // Height: measured as 4 lines, more than expected . Will be displayed as 3 lines!

        // Bad (too wide):
        // | ------------- display width ------------- |
        // | -------- widget-width when measured ------- | < -- uh oh
        // | | -- under-half -- | | -- under-half -- |   |
        // | | --- over-half --- | | --- over-half --- | | < -- when measured, combined on one line
        // Height: measured as 2 lines, less than expected. Will be displayed as 3 lines!

        var barelyUnderHalfWidthHtml = '<div style="display: inline-block; height: 1px; width: ${285 - halfScrollbarWidth}px;"></div>';
        var barelyOverHalfWidthHtml = '<div style="display: inline-block; height: 1px; width: ${305 - halfScrollbarWidth}px;"></div>';
        var x = lst.join(barelyUnderHalfWidthHtml) + lst.join(barelyOverHalfWidthHtml);
        node.setInnerHtml(x, treeSanitizer: new NullTreeSanitizer());
        node.style.cssText = "background: yellow;font-size:0;line-height: ${expectedWidgetHeight / expectedLinesInWidget}px;";
        return node;
      }
      var info0 = editor.getScrollInfo();
      var w0 = editor.addLineWidget(0, w(), coverGutter: true);
      w0.node.style.background = "green";
      var w150 = editor.addLineWidget(150, w(), coverGutter: true);
      w150.node.style.background = "blue";
      var w300 = editor.addLineWidget(300, w(), coverGutter: true);
      w300.node.style.background = "red";
      var info1 = editor.getScrollInfo();
      expect(info0.height + (3 * expectedWidgetHeight), info1.height);
      expect(info0.top + expectedWidgetHeight, info1.top);
      expectedWidgetHeight = 12;
      w0.node.style.lineHeight = w150.node.style.lineHeight = w300.node.style.lineHeight =
          "${expectedWidgetHeight / expectedLinesInWidget}px";
      w0.changed(); w150.changed(); w300.changed();
      var info2 = editor.getScrollInfo();
      expect(info0.height + (3 * expectedWidgetHeight), info2.height);
      expect(info0.top + expectedWidgetHeight, info2.top);
    });

    test('getLineNumber', () {
      editor = makeEditor();
      addDoc(editor, 2, 20);
      var h1 = editor.getLineHandle(1);
      expect(editor.getLineNumber(h1), 1);
      editor.replaceRange("hi\nbye\n", new Pos(0, 0));
      expect(editor.getLineNumber(h1), 3);
      editor.setValue("");
      expect(editor.getLineNumber(h1), -1); // That's not null, but -1.
    });

    test('jumpTheGap', () {
      editor = makeEditor({'lineWrapping': true, 'value': "abc\ndef\nghi\njkl\n"});
      if (phantom) return;
      var longLine = "abcdef ghiklmnop qrstuvw xyz ";
      longLine += longLine; longLine += longLine; longLine += longLine;
      editor.replaceRange(longLine, new Pos(2, 0), new Pos(2));
      editor.setSize("200px", null);
      editor.getWrapperElement().style.lineHeight = "2";
      editor.refresh();
      editor.setCursor(new Pos(0, 1));
      editor.execCommand("goLineDown");
      expect(editor.getCursor(), new Pos(1, 1));
      editor.execCommand("goLineDown");
      expect(editor.getCursor(), new Pos(2, 1));
      editor.execCommand("goLineDown");
      expect(editor.getCursor().line, 2);
      expect(editor.getCursor().char > 1, isTrue);
      editor.execCommand("goLineUp");
      expect(editor.getCursor(), new Pos(2, 1));
      editor.execCommand("goLineUp");
      expect(editor.getCursor(), new Pos(1, 1));
      var node = document.createElement("div");
      node.innerHtml = "hi"; node.style.height = "30px";
      editor.addLineWidget(0, node);
      editor.addLineWidget(1, node.clone(true), above: true);
      editor.setCursor(new Pos(0, 2));
      editor.execCommand("goLineDown");
      expect(editor.getCursor(), new Pos(1, 2));
      editor.execCommand("goLineUp");
      expect(editor.getCursor(), new Pos(0, 2));
    });

    test('addLineClass', () {
      editor = makeEditor({'value': "hohoho\n", 'lineNumbers': true});
      cls(line, text, bg, wrap, gutter) {
        var i = editor.lineInfo(line);
        expect(i.textClass, text);
        expect(i.bgClass, bg);
        expect(i.wrapClass, wrap);
        if (i.handle.gutterClass != null) {
            expect(i.handle.gutterClass, gutter);
        }
      }
      editor.addLineClass(0, "text", "foo");
      editor.addLineClass(0, "text", "bar");
      editor.addLineClass(1, "background", "baz");
      editor.addLineClass(1, "wrap", "foo");
      editor.addLineClass(1, "gutter", "gutter-class");
      cls(0, "foo bar", null, null, null);
      cls(1, null, "baz", "foo", "gutter-class");
      var lines = editor.display.lineDiv;
      expect(byClassName(lines, "foo").length, 2);
      expect(byClassName(lines, "bar").length, 1);
      expect(byClassName(lines, "baz").length, 1);
      expect(byClassName(lines, "gutter-class").length, 1);
      editor.removeLineClass(0, "text", "foo");
      cls(0, "bar", null, null, null);
      editor.removeLineClass(0, "text", "foo");
      cls(0, "bar", null, null, null);
      editor.removeLineClass(0, "text", "bar");
      cls(0, null, null, null, null);

      editor.addLineClass(1, "wrap", "quux");
      cls(1, null, "baz", "foo quux", "gutter-class");
      editor.removeLineClass(1, "wrap");
      cls(1, null, "baz", null, "gutter-class");
      editor.removeLineClass(1, "gutter", "gutter-class");
      expect(byClassName(lines, "gutter-class").length, 0);
      cls(1, null, "baz", null, null);

      editor.addLineClass(1, "gutter", "gutter-class");
      cls(1, null, "baz", null, "gutter-class");
      editor.removeLineClass(1, "gutter", "gutter-class");
      cls(1, null, "baz", null, null);
    });

    test('atomicMarker', () {
      editor = makeEditor();
      addDoc(editor, 10, 10);
      atom(ll, cl, lr, cr, [li=false, ri=false]) {
        return editor.markText(new Pos(ll, cl), new Pos(lr, cr),
            atomic: true, inclusiveLeft: li, inclusiveRight: ri);
      }
      var m = atom(0, 1, 0, 5);
      editor.setCursor(new Pos(0, 1));
      editor.execCommand("goCharRight");
      expect(editor.getCursor(), new Pos(0, 5));
      editor.execCommand("goCharLeft");
      expect(editor.getCursor(), new Pos(0, 1));
      m.clear();
      m = atom(0, 0, 0, 5, true);
      expect(editor.getCursor(), new Pos(0, 5), reason: "pushed out");
      editor.execCommand("goCharLeft");
      expect(editor.getCursor(), new Pos(0, 5));
      m.clear();
      m = atom(8, 4, 9, 10, false, true);
      editor.setCursor(new Pos(9, 8));
      expect(editor.getCursor(), new Pos(8, 4), reason: "set");
      editor.execCommand("goCharRight");
      expect(editor.getCursor(), new Pos(8, 4), reason: "char right");
      editor.execCommand("goLineDown");
      expect(editor.getCursor(), new Pos(8, 4), reason: "line down");
      editor.execCommand("goCharLeft");
      expect(editor.getCursor(), new Pos(8, 3));
      m.clear();
      m = atom(1, 1, 3, 8);
      editor.setCursor(new Pos(0, 0));
      editor.setCursor(new Pos(2, 0));
      expect(editor.getCursor(), new Pos(3, 8));
      editor.execCommand("goCharLeft");
      expect(editor.getCursor(), new Pos(1, 1));
      editor.execCommand("goCharRight");
      expect(editor.getCursor(), new Pos(3, 8));
      editor.execCommand("goLineUp");
      expect(editor.getCursor(), new Pos(1, 1));
      editor.execCommand("goLineDown");
      expect(editor.getCursor(), new Pos(3, 8));
      editor.execCommand("delCharBefore");
      expect(editor.getValue().length, 80, reason: "del chunk");
      m = atom(3, 0, 5, 5);
      editor.setCursor(new Pos(3, 0));
      editor.execCommand("delWordAfter");
      expect(editor.getValue().length, 53, reason: "del chunk");
    });

    test('selectionBias', () {
      editor = makeEditor({'value': "12345"});
      editor.markText(new Pos(0, 1), new Pos(0, 3), atomic: true);
      editor.setCursor(new Pos(0, 2)); // Added editor.setCursor()
      expect(editor.getCursor(), new Pos(0, 3));
      editor.setCursor(new Pos(0, 2));
      expect(editor.getCursor(), new Pos(0, 1));
      editor.setCursor(new Pos(0, 2), bias: -1);
      expect(editor.getCursor(), new Pos(0, 1));
      editor.setCursor(new Pos(0, 4));
      editor.setCursor(new Pos(0, 2), bias: 1);
      expect(editor.getCursor(), new Pos(0, 3));
    });

    test('selectionHomeEnd', () {
      editor = makeEditor({'value': "ab\ncdef\ngh"});
      editor.markText(new Pos(1, 0), new Pos(1, 1), atomic: true, inclusiveLeft: true);
      editor.markText(new Pos(1, 3), new Pos(1, 4), atomic: true, inclusiveRight: true);
      editor.setCursor(new Pos(1, 2));
      editor.execCommand("goLineStart");
      expect(editor.getCursor(), new Pos(1, 1));
      editor.execCommand("goLineEnd");
      expect(editor.getCursor(), new Pos(1, 3));
    });

    test('readOnlyMarker', () {
      editor = makeEditor({'value': "abcde\nfghij\nklmno\n"});
      mark(ll, cl, lr, cr, [at=false]) {
        return editor.markText(new Pos(ll, cl), new Pos(lr, cr),
                               readOnly: true, atomic: at);
      }
      var m = mark(0, 1, 0, 4);
      editor.setCursor(new Pos(0, 2));
      editor.replaceSelection("hi", "end");
      expect(editor.getCursor(), new Pos(0, 2));
      expect(editor.getLine(0), "abcde");
      editor.execCommand("selectAll");
      editor.replaceSelection("oops", "around");
      expect(editor.getValue(), "oopsbcd");
      editor.undo();
      expect(m.find().from, new Pos(0, 1));
      expect(m.find().to, new Pos(0, 4));
      m.clear();
      editor.setCursor(new Pos(0, 2));
      editor.replaceSelection("hi", "around");
      expect(editor.getLine(0), "abhicde");
      expect(editor.getCursor(), new Pos(0, 4));
      m = mark(0, 2, 2, 2, true);
      editor.setSelection(new Pos(1, 1), new Pos(2, 4));
      editor.replaceSelection("t", "end");
      expect(editor.getCursor(), new Pos(2, 3));
      expect(editor.getLine(2), "klto");
      editor.execCommand("goCharLeft");
      editor.execCommand("goCharLeft");
      expect(editor.getCursor(), new Pos(0, 2));
      editor.setSelection(new Pos(0, 1), new Pos(0, 3));
      editor.replaceSelection("xx", "around");
      expect(editor.getCursor(), new Pos(0, 3));
      expect(editor.getLine(0), "axxhicde");
    });

    test('dirtyBit', () {
      editor = makeEditor();
      expect(editor.isClean(), isTrue);
      editor.replaceSelection("boo", null, "test");
      expect(editor.isClean(), isFalse);
      editor.undo();
      expect(editor.isClean(), isTrue);
      editor.replaceSelection("boo", null, "test");
      editor.replaceSelection("baz", null, "test");
      editor.undo();
      expect(editor.isClean(), isFalse);
      editor.markClean();
      expect(editor.isClean(), isTrue);
      editor.undo();
      expect(editor.isClean(), isFalse);
      editor.redo();
      expect(editor.isClean(), isTrue);
    });

    test('changeGeneration', () {
      editor = makeEditor();
      editor.replaceSelection("x");
      var softGen = editor.changeGeneration();
      editor.replaceSelection("x");
      editor.undo();
      expect(editor.getValue(), "");
      expect(editor.isClean(softGen), isFalse);
      editor.replaceSelection("x");
      var hardGen = editor.changeGeneration(true);
      editor.replaceSelection("x");
      editor.undo();
      expect(editor.getValue(), "x");
      expect(editor.isClean(hardGen), isTrue);
    });

    test('addKeyMap', () {
      editor = makeEditor({'value': "abc"});
      sendKey(code) {
        var e = new KeyEvent("keydown", keyCode: code);
        editor.triggerOnKeyDown(e);
      }
      sendKey(39);
      expect(editor.getCursor(), new Pos(0, 1));
      var test = 0;
      var map1 = {'Right':(cm) { ++test; }};
      var map2 = {'Right':(cm) { test += 10; }};
      editor.addKeyMap(map1);
      sendKey(39);
      expect(editor.getCursor(), new Pos(0, 1));
      expect(test, 1);
      editor.addKeyMap(map2, true);
      sendKey(39);
      expect(test, 2);
      editor.removeKeyMap(map1);
      sendKey(39);
      expect(test, 12);
      editor.removeKeyMap(map2);
      sendKey(39);
      expect(test, 12);
      expect(editor.getCursor(), new Pos(0, 2));
      editor.addKeyMap({'Right': (cm) { test = 55; }, 'name': "mymap"});
      sendKey(39);
      expect(test, 55);
      editor.removeKeyMap("mymap");
      sendKey(39);
      expect(editor.getCursor(), new Pos(0, 3));
    });

    test('findPosH', () {
      editor = makeEditor({'value': "line one\nline two.something.other\n"});
      var l = [{'from': new Pos(0, 0), 'to': new Pos(0, 1), 'by': 1},
               {'from': new Pos(0, 0), 'to': new Pos(0, 0), 'by': -1, 'hitSide': true},
               {'from': new Pos(0, 0), 'to': new Pos(0, 4), 'by': 1, 'unit': "word"},
               {'from': new Pos(0, 0), 'to': new Pos(0, 8), 'by': 2, 'unit': "word"},
               {'from': new Pos(0, 0), 'to': new Pos(2, 0), 'by': 20, 'unit': "word", 'hitSide': true},
               {'from': new Pos(0, 7), 'to': new Pos(0, 5), 'by': -1, 'unit': "word"},
               {'from': new Pos(0, 4), 'to': new Pos(0, 8), 'by': 1, 'unit': "word"},
               {'from': new Pos(1, 0), 'to': new Pos(1, 18), 'by': 3, 'unit': "word"},
               {'from': new Pos(1, 22), 'to': new Pos(1, 5), 'by': -3, 'unit': "word"},
               {'from': new Pos(1, 15), 'to': new Pos(1, 10), 'by': -5},
               {'from': new Pos(1, 15), 'to': new Pos(1, 10), 'by': -5, 'unit': "column"},
               {'from': new Pos(1, 15), 'to': new Pos(1, 0), 'by': -50, 'unit': "column", 'hitSide': true},
               {'from': new Pos(1, 15), 'to': new Pos(1, 24), 'by': 50, 'unit': "column", 'hitSide': true},
               {'from': new Pos(1, 15), 'to': new Pos(2, 0), 'by': 50, 'hitSide': true}];
      l.forEach((t) {
        var unit = t['unit'];
        if (unit == null) unit = "char";
        var r = editor.findPosH(t['from'], t['by'], unit);
        expect(r, t['to']);
        var hs = t['hitSide'];
        if (hs == null) hs = false;
        expect(r.hitSide, hs);
      });
    });

    test('beforeChange', () {
      editor = makeEditor({'value': "abcdefghijk"});
      editor.on(editor, "beforeChange", (cm, change) {
        var text = [];
        for (var i = 0; i < change.text.length; ++i) {
          text.add(change.text[i].replaceAll(" ", "_"));
        }
        change.update(null, null, text);
      });
      editor.setValue("hello, i am a\nnew document\n");
      expect(editor.getValue(), "hello,_i_am_a\nnew_document\n");
      editor.on(editor.getDoc(), "beforeChange", (doc, change) {
        if (change.from.line == 0) change.cancel();
      });
      editor.setValue("oops"); // Canceled
      expect(editor.getValue(), "hello,_i_am_a\nnew_document\n");
      editor.replaceRange("hey hey hey", new Pos(1, 0), new Pos(2, 0));
      expect(editor.getValue(), "hello,_i_am_a\nhey_hey_hey");
    });

    test('beforeChangeUndo', () {
      editor = makeEditor({'value': "one\ntwo"});
      editor.replaceRange("hi", new Pos(0, 0), new Pos(0));
      editor.replaceRange("bye", new Pos(0, 0), new Pos(0));
      expect(editor.historySize().undo, 2);
      editor.on(editor, "beforeChange", (cm, change) {
        expect(change.updateable, isFalse); // Name change: update => updateable
        change.cancel();
      });
      editor.undo();
      expect(editor.historySize().undo, 0);
      expect(editor.getValue(), "bye\ntwo");
    });

    test('beforeSelectionChange', () {
      editor = makeEditor();
      notAtEnd(doc, pos) {
        var len = editor.getLine(pos.line).length;
        if (len == 0 || pos.char == len) return new Pos(pos.line, pos.char - 1);
        return pos;
      }
      editor.on(editor, "beforeSelectionChange", (doc, obj) {
        obj.update([new Range(notAtEnd(doc, obj.ranges[0].anchor),
                              notAtEnd(doc, obj.ranges[0].head))]);
      });

      addDoc(editor, 10, 10);
      editor.execCommand("goLineEnd");
      expect(editor.getCursor(), new Pos(0, 9));
      editor.execCommand("selectAll");
      expect(editor.getCursor("start"), new Pos(0, 0));
      expect(editor.getCursor("end"), new Pos(9, 9));
    });

    test('change_removedText', () {
      editor = makeEditor();
      editor.setValue("abc\ndef");

      var removedText = [];
      editor.on(editor, "change", (editor, change) {
        removedText.add(change.removed);
      });

      editor.runInOp(editor, () {
        editor.replaceRange("xyz", new Pos(0, 0), new Pos(1,1));
        editor.replaceRange("123", new Pos(0,0));
      });

      expect(removedText.length, 2);
      expect(removedText[0].join("\n"), "abc\nd");
      expect(removedText[1].join("\n"), "");

      removedText = [];
      editor.undo();
      expect(removedText.length, 2);
      expect(removedText[0].join("\n"), "123");
      expect(removedText[1].join("\n"), "xyz");

      removedText = [];
      editor.redo();
      expect(removedText.length, 2);
      expect(removedText[0].join("\n"), "abc\nd");
      expect(removedText[1].join("\n"), "");
    });

    test('lineStyleFromMode', () {
      editor = makeEditor({'value': "line1: [br] [br]\nline2: (par) (par)\nline3: <tag> <tag>"});
      CodeEditor.defineMode("test_mode", new TestMode());
      editor.setOption("mode", "test_mode");
      var bracketElts = byClassName(editor.getWrapperElement(), "brackets");
      expect(bracketElts.length, 1, reason: "brackets count");
      expect(bracketElts[0].nodeName, "PRE");
      expect(new RegExp(r'brackets.*brackets').hasMatch(bracketElts[0].className), isFalse);
      var parenElts = byClassName(editor.getWrapperElement(), "parens");
      expect(parenElts.length, 1, reason: "parens count");
      expect(parenElts[0].nodeName, "DIV");
      expect(new RegExp(r'parens.*parens').hasMatch(parenElts[0].className), isFalse);
      expect(parenElts[0].parent.nodeName, "DIV");

      expect(byClassName(editor.getWrapperElement(), "bg").length, 1);
      expect(byClassName(editor.getWrapperElement(), "line").length, 1);
      var spanElts = byClassName(editor.getWrapperElement(), "cm-span");
      expect(spanElts.length, 2);
      expect(new RegExp(r'^\s*cm-span\s*$').hasMatch(spanElts[0].className), isTrue);
    });

    test('lineStyleFromBlankLine', () {
      editor = makeEditor({'value': "foo\n\nbar"});
      CodeEditor.defineMode("lineStyleFromBlankLine_mode", new BlankLineMode());
      editor.setOption("mode", "lineStyleFromBlankLine_mode");
      var blankElts = byClassName(editor.getWrapperElement(), "blank");
      expect(blankElts.length, 1);
      expect(blankElts[0].nodeName, "PRE");
      editor.replaceRange("x", new Pos(1, 0));
      blankElts = byClassName(editor.getWrapperElement(), "blank");
      expect(blankElts.length, 0);
    });

    test('helpers', () {
      editor = makeEditor();
      initHelpers(editor);
      editor.setOption("mode", "yyy");
      expect(editor.getHelpers(new Pos(0, 0), "xxx").join("/"), "A/B");
      editor.setOption("mode", {'name': "yyy", 'modeProps': {'xxx': "b", 'enableC': true}});
      expect(editor.getHelpers(new Pos(0, 0), "xxx").join("/"), "B/C");
      editor.setOption("mode", "javascript");
      expect(editor.getHelpers(new Pos(0, 0), "xxx").join("/"), "");
    });

    test('selectionHistory', () {
      editor = makeEditor({'value': "a b c d"});
      for (var i = 0; i < 3; i++) {
        editor.setExtending(true);
        editor.execCommand("goCharRight");
        editor.setExtending(false);
        editor.execCommand("goCharRight");
        editor.execCommand("goCharRight");
      }
      editor.execCommand("undoSelection");
      expect(editor.getSelection(), "c");
      editor.execCommand("undoSelection");
      expect(editor.getSelection(), "");
      expect(editor.getCursor(), new Pos(0, 4));
      editor.execCommand("undoSelection");
      expect(editor.getSelection(), "b");
      editor.execCommand("redoSelection");
      expect(editor.getSelection(), "");
      expect(editor.getCursor(), new Pos(0, 4));
      editor.execCommand("redoSelection");
      expect(editor.getSelection(), "c");
      editor.execCommand("redoSelection");
      expect(editor.getSelection(), "");
      expect(editor.getCursor(), new Pos(0, 6));
    });

    test('selectionChangeReducesRedo', () {
      editor = makeEditor({'value': "abc"});
      editor.replaceSelection("X");
      editor.execCommand("goCharRight");
      editor.undoSelection();
      editor.execCommand("selectAll");
      editor.undoSelection();
      expect(editor.getValue(), "Xabc");
      expect(editor.getCursor(), new Pos(0, 1));
      editor.undoSelection();
      expect(editor.getValue(), "abc");
    });

    test('selectionHistoryNonOverlapping', () {
      editor = makeEditor({'value': "1234"});
      editor.setSelection(new Pos(0, 0), new Pos(0, 1));
      editor.setSelection(new Pos(0, 2), new Pos(0, 3));
      editor.execCommand("undoSelection");
      expect(editor.getCursor("anchor"), new Pos(0, 0));
      expect(editor.getCursor("head"), new Pos(0, 1));
    });

    test('cursorMotionSplitsHistory', () {
      editor = makeEditor({'value': "1234"});
      editor.replaceSelection("a");
      editor.execCommand("goCharRight");
      editor.replaceSelection("b");
      editor.replaceSelection("c");
      editor.undo();
      expect(editor.getValue(), "a1234");
      expect(editor.getCursor(), new Pos(0, 2));
      editor.undo();
      expect(editor.getValue(), "1234");
      expect(editor.getCursor(), new Pos(0, 0));
    });

    test('selChangeInOperationDoesNotSplit', () {
      editor = makeEditor({'value': "a"});
      for (var i = 0; i < 4; i++) {
        editor.runInOp(editor, () {
          editor.replaceSelection("x");
          editor.setCursor(new Pos(0, editor.getCursor().char - 1));
        });
      }
      expect(editor.getCursor(), new Pos(0, 0));
      expect(editor.getValue(), "xxxxa");
      editor.undo();
      expect(editor.getValue(), "a");
    });

    test('alwaysMergeSelEventWithChangeOrigin', () {
      editor = makeEditor({'value': "a"});
      editor.replaceSelection("U", null, "foo");
      editor.setSelection(new Pos(0, 0), new Pos(0, 1), new SelectionOptions(origin: "foo"));
      editor.undoSelection();
      expect(editor.getValue(), "a");
      editor.replaceSelection("V", null, "foo");
      editor.setSelection(new Pos(0, 0), new Pos(0, 1), new SelectionOptions(origin: "bar"));
      editor.undoSelection();
      expect(editor.getValue(), "Va");
    });

    test('getTokenAt', () {
      editor = makeEditor({'value': "1+2", 'mode': "javascript"});
      var tokPlus = editor.getTokenAt(new Pos(0, 2));
// TODO Define javascript mode
//      expect(tokPlus.type, "operator");
//      expect(tokPlus.string, "+");
      var toks = editor.getLineTokens(0);
//      expect(toks.length, 3);
//      var l = [["number", "1"], ["operator", "+"], ["number", "2"]];
//      int i = 0;
//      l.forEach((expect) {
//        expect(toks[i].type, expect[0]);
//        expect(toks[i].string, expect[1]);
//        i++;
//      });
      tokPlus.hashCode;
      toks.hashCode;
    });

    test('getTokenTypeAt', () {
      editor = makeEditor({'value': "1 + 'foo'", 'mode': "javascript"});
// TODO Define javascript mode
//      expect(editor.getTokenTypeAt(new Pos(0, 0)), "number");
      var tok = editor.getTokenTypeAt(new Pos(0, 6));
//      expect(tok, "string");
      editor.addOverlay(new FooMode());
      expect(byClassName(editor.getWrapperElement(), "cm-foo").length, 1);
      tok = editor.getTokenTypeAt(new Pos(0, 6));
//      expect(tok, "string");
      tok.hashCode;
    });

    test('resizeLineWidget', () {
      editor = makeEditor();
      addDoc(editor, 200, 3);
      PreElement widget = document.createElement("pre");
      widget.innerHtml = "imwidget";
      widget.style.background = "yellow";
      editor.addLineWidget(1, widget, noHScroll: true);
      editor.setSize(40);
      expect(widget.parent.offsetWidth < 42, isTrue);
    });

    test('combinedOperations', () {
      editor = makeEditor({'value': "abc"});
      var place = document.getElementById("testground");
      var other = new CodeMirror(place, {'value': "123"});
      try {
        editor.runInOp(editor, () {
          editor.doc.addLineClass(0, "wrap", "foo");
          other.doc.addLineClass(0, "wrap", "foo");
        });
        expect(byClassName(editor.getWrapperElement(), "foo").length, 1);
        expect(byClassName(other.getWrapperElement(), "foo").length, 1);
        editor.runInOp(editor, () {
          editor.doc.removeLineClass(0, "wrap", "foo");
          other.doc.removeLineClass(0, "wrap", "foo");
        });
        expect(byClassName(editor.getWrapperElement(), "foo").length, 0);
        expect(byClassName(other.getWrapperElement(), "foo").length, 0);
      } finally {
        other.getWrapperElement().remove();
      }
    });

    test('eventOrder', () {
      editor = makeEditor();
      var seen = [];
      editor.on(editor, "change", (e,c) {
        if (seen.length == 0) editor.replaceSelection(".");
        seen.add("change");
      });
      editor.on(editor, "cursorActivity", (e) {
        editor.replaceSelection("!");
        seen.add("activity");
      });
      editor.replaceSelection("/");
      expect(seen.join(","), "change,change,activity,change");
    });

    test('core_rmClass', () {
      var node = document.createElement("div");
      node.className = "foo-bar baz-quux yadda";
      rmClass(node, "quux");
      expect(node.className, "foo-bar baz-quux yadda");
      rmClass(node, "baz-quux");
      expect(node.className, "foo-bar yadda");
      rmClass(node, "yadda");
      expect(node.className, "foo-bar");
      rmClass(node, "foo-bar");
      expect(node.className, "");
      node.className = " foo ";
      rmClass(node, "foo");
      expect(node.className, "");
    });

    test('core_addClass', () {
      var node = document.createElement("div");
      addClass(node, "a");
      expect(node.className, "a");
      addClass(node, "a");
      expect(node.className, "a");
      addClass(node, "b");
      expect(node.className, "a b");
      addClass(node, "a");
      addClass(node, "b");
      expect(node.className, "a b");
    });

    test('trailingspace', () {
      editor = makeEditor();
      editor.setOption("showTrailingSpace", true);
      editor.setValue(" text sp-tab-sp    ");
      editor.setOption("showTrailingSpace", false);
    });
  });
}

CodeMirror makeEditor([Map opts]) {
  var place = document.querySelector("#testground");
  while (place.firstChild.nextNode != null) place.firstChild.nextNode.remove();
  var cm = new CodeMirror(place, opts);
  return cm;
}

void addDoc(CodeMirror cm, int width, int height) {
  var content = [], line = "";
  for (var i = 0; i < width; ++i) line += "x";
  for (var i = 0; i < height; ++i) content.add(line);
  cm.doc.setValue(content.join("\n"));
}

// Shorthand to expect a and b to be within m units of each other.
near(a, b, m) => expect((a - b).abs() <= m, isTrue);

List<Element> byClassName(Element elt, String cls) {
  // Technically, this is a List<Node> but we only call it with Element names.
  return elt.getElementsByClassName(cls);
}

List<Element> getElementsByTagName(Node node, String name) {
  bool hasParent(Node child, Node parent) {
    if (child.parent == null) return false;
    if (child.parent == parent) return true;
    return hasParent(child.parent, parent);
  }
  List<Node> nodes = document.getElementsByTagName(name);
  return nodes.sublist(0)..retainWhere((n) => hasParent(n, node));
}

foldLines(CodeMirror cm, int start, int end, [bool autoClear = false]) {
  return cm.markText(new Pos(start, 0), new Pos(end - 1),
    inclusiveLeft: true,
    inclusiveRight: true,
    collapsed: true,
    clearOnEnter: autoClear
  );
}

int _knownScrollbarWidth;
int scrollbarWidth() {
  if (_knownScrollbarWidth != null) return _knownScrollbarWidth;
  var div = document.createElement('div');
  div.style.cssText = "width: 50px; height: 50px; overflow-x: scroll";
  document.body.append(div);
  _knownScrollbarWidth = div.offsetHeight - div.clientHeight;
  div.remove();
  return _knownScrollbarWidth;
}

class NullTreeSanitizer implements NodeTreeSanitizer {
  sanitizeTree(x){} // Disable all sanity checks
}

// TODO This helper init code should be global and apply to all editors in tests
initHelpers(CodeEditor editor) {
  CodeMirror.registerHelper("xxx", "a", "A");
  CodeMirror.registerHelper("xxx", "b", "B");
  var m = new Mode();
  m['xxx'] = ["a", "b", "q"];
  CodeEditor.defineMode("yyy", m);
  CodeMirror.registerGlobalHelper("xxx", "c", (m,[e]) { return m['enableC']; }, "C");
}

class TestMode extends Mode {
  token(StringStream stream, [dynamic state]) {
    if (stream.match(new RegExp(r'^\[[^\]]*\]')) != null) return "  line-brackets  ";
    if (stream.match(new RegExp(r'^\([^\)]*\)')) != null) return "  line-background-parens  ";
    if (stream.match(new RegExp(r'^<[^>]*>')) != null) return "  span  line-line  line-background-bg  ";
    stream.match(new RegExp(r'^\s+|^\S+'));
  }
}

class BlankLineMode extends Mode {
  token(stream, [dynamic state]) {
    stream.skipToEnd();
    return "comment";
  }
  bool get hasBlankLine => true;
  blankLine(dynamic state) {
    return "line-blank";
  }
}

class FooMode extends Mode {
  token(StringStream stream, [dynamic state]) {
    if (stream.match("foo") != null) return "foo";
    else stream.next();
  }
}

var ie_lt8 = new RegExp(r'MSIE [1-7]\b').hasMatch(navigator.userAgent);
var ie_lt9 = new RegExp(r'MSIE [1-8]\b').hasMatch(navigator.userAgent);
var mac = new RegExp(r'Mac').hasMatch(navigator.platform);
var phantom = new RegExp(r'PhantomJS').hasMatch(navigator.userAgent);
var opera = new RegExp(r'Opera\/\.').hasMatch(navigator.userAgent);
Iterable _opera_vsn = opera ? new RegExp(r'Version\/(\d+\.\d+)').allMatches(navigator.userAgent) : null;
var opera_version = _opera_vsn == null || _opera_vsn.isEmpty  ? 0 : num.parse(_opera_vsn.first);
var opera_lt10 = opera && (!opera_version || opera_version < 10);
