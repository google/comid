// Copyright (c) 2015, the Comid Authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

part of comid.test;

// Also see https://www.dartlang.org/articles/mocking-with-dart/

// CodeEditor tests
documentTest() {

  const bool verbose = false;

  group('Document,', () {
    Document editor;

    test('environ', () {
      if (verbose) {
        print("${navigator.userAgent}");
        print("gecko ${gecko}");
        print("ie ${ie}");
        print("webkit ${webkit}");
        print("chrome ${chrome}");
        print("presto ${presto}");
        print("safari ${safari}");
        print("khtml ${khtml}");
        print("ios ${ios}");
        print("mobile ${mobile}");
        print("mac ${mac}");
        print("windows ${windows}");
        print("flipCtrlCmd ${flipCtrlCmd}");
        print("captureRightClick ${captureRightClick}");
      }
    });

    test('create empty Document', () {
      editor = new Document("", null);
      expect(editor, isNotNull);
      expect(editor.children.isEmpty, isFalse);
      var sel;
      expect((sel = editor.sel), isNotNull);
      expect(sel.ranges.isEmpty, isFalse);
      expect(sel.ranges[0].anchor.compareTo(sel.ranges[0].head), equals(0));
      var line;
      expect((line = editor.getLineHandle(0)), isNotNull);
      expect(line.text, isEmpty);
      expect(editor.getValue('\n'), equals(""));
    });

    test('create non-empty Document', () {
      editor = new Document("with\ntwo lines\n", null);
      var line;
      expect((line = editor.getLineHandle(0)), isNotNull);
      expect(line.text.isEmpty, isFalse);
      expect((line = editor.getLineHandle(1)), isNotNull);
      expect(line.text.isEmpty, isFalse);
      expect((line = editor.getLineHandle(2)), isNotNull);
      expect(line.text.isEmpty, isTrue);
    });

    test('create multi-chunk Document', () {
      editor = new Document(sixtyTwoLineString, null);
      expect(editor.children.length, equals(2));
      expect(editor.children[1].lines.length, equals(25));
      expect(editor.children[0].parent, equals(editor));
      var line;
      expect((line = editor.getLineHandle(0)), isNotNull);
      expect(line.text.isEmpty, isFalse);
      expect((line = editor.getLineHandle(1)), isNotNull);
      expect(line.text.isEmpty, isFalse);
      expect((line = editor.getLineHandle(62)), isNotNull);
      expect(line.text.isEmpty, isTrue);
      expect((line = editor.getLineHandle(61)), isNotNull);
      expect(line.text, equals('LAST'));
    });

    test('create large Document', () {
      String s = "";
      for (int i = 0; i < 50; i++) s = s + sixtyTwoLineString;
      editor = new Document(s, null);
      expect(editor.children.length, equals(4));
      String ss = editor.getValue('\n');
      expect(ss, equals(s));

      int lineCount = 0;
      int maxDepth = 0;
      int depth(BtreeChunk node) {
        int depth = 0;
        while (node != null) {
          depth++;
          node = node.parent;
        }
        return depth;
      }
      editor.iter((Line line) {
        lineCount += 1;
        maxDepth = max(maxDepth, depth(line.parent));
      });

      expect(maxDepth >= 4, isTrue);
      // 50 X 62 = 3100, but there is newline at the end of the
      // base string, which combines with the first line each time
      // except the last, giving one additional line to the counter.
      expect(lineCount, equals(3101));
    });
  });

  group('StringStream,', () {

    test('StringStream initialization', () {
      StringStream ss = new StringStream('string to test', 4);
      expect(ss.tabSize, equals(4));
    });

    test('predicates', () {
      StringStream ss = new StringStream('string to test', 4);
      expect(ss.sol(), isTrue);
      expect(ss.eol(), isFalse);
      ss.skipToEnd();
      expect(ss.sol(), isFalse);
      expect(ss.eol(), isTrue);
    });

    test('char functions', () {
      StringStream ss = new StringStream('string to test', 4);
      expect(ss.next(), equals('s'));
      expect(ss.peek(), equals('t'));
      expect(ss.next(), equals('t'));
      expect(ss.eat('r'), equals('r'));
      expect(ss.eat(new RegExp(r'.')), equals('i'));
      expect(ss.eatWhile(new RegExp(r'[a-z]')), isTrue);
      expect(ss.eatSpace(), isTrue);
      expect(ss.skipTo(" "), isTrue);
      expect(ss.pos, equals(9));
      expect(ss.eatSpace(), isTrue);
    });

    test('indentation', () {
      StringStream ss = new StringStream('        string to test', 4);
      expect(ss.indentation(), equals(8));
      ss = new StringStream('\t\tstring to test', 4);
      expect(ss.indentation(), equals(8));
    });

    test('hideFirstChars', () {
      StringStream ss = new StringStream('        string to test', 4);
      expect(ss.hideFirstChars(4, () => ss.indentation()), equals(4));
      expect(ss.hideFirstChars(8, () => ss.column()), equals(-8));
      ss = new StringStream('\t\tstring to test', 4);
      expect(ss.hideFirstChars(1, () => ss.indentation()), equals(4));
      expect(ss.hideFirstChars(2, () => ss.column()), equals(-8));
    });

    test('match string', () {
      StringStream ss = new StringStream('string to test', 4);
      expect(ss.match('string'), isTrue);
      expect(ss.eatSpace(), isTrue);
      expect(ss.match('to'), isTrue);
    });

    test('match regexp', () {
      StringStream ss = new StringStream('[1].reduce(  );', 4);
      expect(ss.match(new RegExp(r'^\[[^\]]*\]')), isNotNull);
      ss = new StringStream('<div id=nav>', 2);
      expect(ss.match(new RegExp(r'^<[^>]*>')), isNotNull);
      ss.backUp(12);
      expect(ss.match(new RegExp(r'^\[[^\]]*\]')), isNull);
    });
  });

  group('Async events,', () {
    CodeMirror editor;

    test('change', () {
      int changed = 0;
      editor = makeEditor();
      editor.setValue("test");
      // Verify both editor and doc signal async "change" event.
      editor.onChange.listen((_) { changed++; });
      editor.doc.onChange.listen((_) { changed++; });
      editor.replaceRange("123", new Pos(0,0));
      new Future.value(null).then((_) {
        expect(changed, 2);
      });
    });

    test('changes', () {
      int changed = 0;
      editor = makeEditor();
      editor.setValue("test");
      // Verify final async "changes" event has valid data.
      editor.onChanges.listen((args) {
        List<Change> changeList = args[1];
        var change = changeList[0];
        changed = change.from.line + change.from.char;
        changed += change.to.line + change.to.char;
        changed += changeList.length;
      }, onError: (_) { fail("error"); });
      editor.replaceRange("123", new Pos(0,0));
      new Future.value(null).then((_) {
        expect(changed, 1);
      });
    });

    test('refresh', () {
      int changed = 0;
      editor = makeEditor();
      editor.setValue("test");
      // Verify editor signals async "refresh" event.
      editor.onRefresh.listen((_) { changed++; });
      editor.replaceRange("123", new Pos(0,0));
      editor.refresh();
      new Future.value(null).then((_) {
        expect(changed, 1);
      });
    });

  });
}

// A 62 line string with a newline at the end.
String sixtyTwoLineString = '''
line
line
line
line
line
line
line
line
line
line
line
line
line
line
line
line
line
line
line
line
line
line
line
line
line
line
line
line
line
line
line
line
line
line
line
line
line
line
line
line
line
line
line
line
line
line
line
line
line
line
line
line
line
line
line
line
line
line
line
line
line
LAST
''';