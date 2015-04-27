// Copyright (c) 2015, the Comid Authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

part of comid.test;

multiDocTest() {
  // Test multiple document operations.
  group('Multi-doc,', () {

    test('basic', () {
      testDoc("A='x' B<A", testBasic);
    });

    test('basicSeparate', () {
      testDoc("A='x' B<~A", testBasic);
    });

    test('sharedHist', () {
      testDoc("A='ab\ncd\nef' B<A", (CodeMirror a, CodeMirror b) {
        a.replaceRange("x", new Pos(0));
        b.replaceRange("y", new Pos(1));
        a.replaceRange("z", new Pos(2));
        eqAll("abx\ncdy\nefz", [a, b]);
        a.undo();
        a.undo();
        eqAll("abx\ncd\nef", [a, b]);
        a.redo();
        eqAll("abx\ncdy\nef", [a, b]);
        b.redo();
        eqAll("abx\ncdy\nefz", [a, b]);
        a.undo(); b.undo(); a.undo(); a.undo();
        eqAll("ab\ncd\nef", [a, b]);
      });
    });

    test('undoIntact', () {
      testDoc("A='ab\ncd\nef' B<~A", (CodeMirror a, CodeMirror b) {
        a.replaceRange("x", new Pos(0));
        b.replaceRange("y", new Pos(1));
        a.replaceRange("z", new Pos(2));
        a.replaceRange("q", new Pos(0));
        eqAll("abxq\ncdy\nefz", [a, b]);
        a.undo();
        a.undo();
        eqAll("abx\ncdy\nef", [a, b]);
        b.undo();
        eqAll("abx\ncd\nef", [a, b]);
        a.redo();
        eqAll("abx\ncd\nefz", [a, b]);
        a.redo();
        eqAll("abxq\ncd\nefz", [a, b]);
        a.undo(); a.undo(); a.undo(); a.undo();
        eqAll("ab\ncd\nef", [a, b]);
        b.redo();
        eqAll("ab\ncdy\nef", [a, b]);
      });
    });

    test('undoConflict', () {
      testDoc("A='ab\ncd\nef' B<~A", (CodeMirror a, CodeMirror b) {
        a.replaceRange("x", new Pos(0));
        a.replaceRange("z", new Pos(2));
        // This should clear the first undo event in a, but not the second
        b.replaceRange("y", new Pos(0));
        a.undo(); a.undo();
        eqAll("abxy\ncd\nef", [a, b]);
        a.replaceRange("u", new Pos(2));
        a.replaceRange("v", new Pos(0));
        // This should clear both events in a
        b.replaceRange("w", new Pos(0));
        a.undo(); a.undo();
        eqAll("abxyvw\ncd\nefu", [a, b]);
      });
    });

    test('doubleRebase', () {
      testDoc("A='ab\ncd\nef\ng' B<~A C<B", (CodeMirror a, CodeMirror b, CodeMirror c) {
        c.replaceRange("u", new Pos(3));
        a.replaceRange("", new Pos(0, 0), new Pos(1, 0));
        c.undo();
        eqAll("cd\nef\ng", [a, b, c]);
      });
    });

    test('undoUpdate', () {
      testDoc("A='ab\ncd\nef' B<~A", (CodeMirror a, CodeMirror b) {
        a.replaceRange("x", new Pos(2));
        b.replaceRange("u\nv\nw\n", new Pos(0, 0));
        a.undo();
        eqAll("u\nv\nw\nab\ncd\nef", [a, b]);
        a.redo();
        eqAll("u\nv\nw\nab\ncd\nefx", [a, b]);
        a.undo();
        eqAll("u\nv\nw\nab\ncd\nef", [a, b]);
        b.undo();
        a.redo();
        eqAll("ab\ncd\nefx", [a, b]);
        a.undo();
        eqAll("ab\ncd\nef", [a, b]);
      });
    });

    test('undoKeepRanges', () {
      testDoc("A='abcdefg' B<A", (CodeMirror a, CodeMirror b) {
        var m = a.markText(new Pos(0, 1), new Pos(0, 3), className: "foo");
        b.replaceRange("x", new Pos(0, 0));
        expect(m.find().from, new Pos(0, 2));
        b.replaceRange("yzzy", new Pos(0, 1), new Pos(0));
        expect(m.find(), null);
        b.undo();
        expect(m.find().from, new Pos(0, 2));
        b.undo();
        expect(m.find().from, new Pos(0, 1));
      });
    });

    test('longChain', () {
      testDoc("A='uv' B<A C<B D<C", (CodeMirror a, CodeMirror b, CodeMirror c, CodeMirror d) {
        a.replaceSelection("X");
        eqAll("Xuv", [a, b, c, d]);
        d.replaceRange("Y", new Pos(0));
        eqAll("XuvY", [a, b, c, d]);
      });
    });

    test('broadCast', () {
      testDoc("B<A C<A D<A E<A", (CodeMirror a, CodeMirror b, CodeMirror c, CodeMirror d, CodeMirror e) {
        b.setValue("uu");
        eqAll("uu", [a, b, c, d, e]);
        a.replaceRange("v", new Pos(0, 1));
        eqAll("uvu", [a, b, c, d, e]);
      });
    });

    test('islands', () {
      // A and B share a history, C and D share a separate one
      testDoc("A='x\ny\nz' B<A C<~A D<C", (CodeMirror a, CodeMirror b, CodeMirror c, CodeMirror d) {
        a.replaceRange("u", new Pos(0));
        d.replaceRange("v", new Pos(2));
        b.undo();
        eqAll("x\ny\nzv", [a, b, c, d]);
        c.undo();
        eqAll("x\ny\nz", [a, b, c, d]);
        a.redo();
        eqAll("xu\ny\nz", [a, b, c, d]);
        d.redo();
        eqAll("xu\ny\nzv", [a, b, c, d]);
      });
    });

    test('unlink', () {
      testDoc("B<A C<A D<B", (CodeMirror a, CodeMirror b, CodeMirror c, CodeMirror d) {
        a.setValue("hi");
        b.unlinkDoc(a);
        d.setValue("aye");
        eqAll("hi", [a, c]);
        eqAll("aye", [b, d]);
        a.setValue("oo");
        eqAll("oo", [a, c]);
        eqAll("aye", [b, d]);
      });
    });

    test('bareDoc', () {
      testDoc("A*='foo' B*<A C<B", (Doc a, Doc b, CodeMirror c) {
        expect(a is Doc, isTrue);
        expect(b is Doc, isTrue);
        expect(c is CodeMirror, isTrue);
        eqAll("foo", [a, b, c]);
        a.replaceRange("hey", new Pos(0, 0), new Pos(0));
        c.replaceRange("!", new Pos(0));
        eqAll("hey!", [a, b, c]);
        b.unlinkDoc(a);
        b.setValue("x");
        eqAll("x", [b, c]);
        eqAll("hey!", [a]);
      });
    });

    test('swapDoc', () {
      testDoc("A='a' B*='b' C<A", (CodeMirror a, Doc b, CodeMirror c) {
        var d = a.swapDoc(b);
        d.setValue("x");
        eqAll("x", [c, d]);
        eqAll("b", [a, b]);
      });
    });

    test('docKeepsScroll', () {
      testDoc("A='x' B*='y'", (CodeMirror a, Doc b) {
        addDoc(a, 200, 200);
        a.scrollIntoView(new Pos(199, 200));
        var c = a.swapDoc(b);
        a.swapDoc(c);
        var pos = a.getScrollInfo();
        expect(pos.left > 0, isTrue, reason: "not at left");
        expect(pos.top > 0, isTrue, reason: "not at top");
      });
    });

    test('copyDoc', () {
      testDoc("A='u'", (CodeMirror a) {
        var copy = a.getDoc().copy(true);
        a.setValue("foo");
        copy.setValue("bar");
        var old = a.swapDoc(copy);
        expect(a.getValue(), "bar");
        a.undo();
        expect(a.getValue(), "u");
        a.swapDoc(old);
        expect(a.getValue(), "foo");
        expect(old.historySize().undo, 1);
        expect(old.copy(false).historySize().undo, 0);
      });
    });

    test('docKeepsMode', () {
      // NOTE: These mode/mime definitions should be standard.
      CodeEditor.defineMode("markdown", new TestMode()..name="markdown");
      CodeEditor.defineMode("javascript", new TestMode()..name="javascript");
      CodeEditor.defineMIME("text/x-markdown", "markdown");
      CodeEditor.defineMIME("text/javascript", "javascript");
      testDoc("A='1+1'", (CodeMirror a) {
        var other = new Doc("hi", "text/x-markdown");
        a.setOption("mode", "text/javascript");
        var old = a.swapDoc(other);
        expect(a.getOption("mode"), "text/x-markdown");
        expect(a.doc.getMode().name, "markdown");
        a.swapDoc(old);
        expect(a.getOption("mode"), "text/javascript");
        expect(a.doc.getMode().name, "javascript");
      });
    });

    test('subview', () {
      testDoc("A='1\n2\n3\n4\n5' B<~A/1-3", (CodeMirror a, CodeMirror b) {
        expect(b.getValue(), "2\n3");
        expect(b.firstLine(), 1);
        b.setCursor(new Pos(4));
        expect(b.getCursor(), new Pos(2, 1));
        a.replaceRange("-1\n0\n", new Pos(0, 0));
        expect(b.firstLine(), 3);
        expect(b.getCursor(), new Pos(4, 1));
        a.undo();
        expect(b.getCursor(), new Pos(2, 1));
        b.replaceRange("oyoy\n", new Pos(2, 0));
        expect(a.getValue(), "1\n2\noyoy\n3\n4\n5");
        b.undo();
        expect(a.getValue(), "1\n2\n3\n4\n5");
      });
    });

    test('subviewEditOnBoundary', () {
      testDoc("A='11\n22\n33\n44\n55' B<~A/1-4", (CodeMirror a, CodeMirror b) {
        a.replaceRange("x\nyy\nz", new Pos(0, 1), new Pos(2, 1));
        expect(b.firstLine(), 2);
        expect(b.lineCount(), 2);
        expect(b.getValue(), "z3\n44");
        a.replaceRange("q\nrr\ns", new Pos(3, 1), new Pos(4, 1));
        expect(b.firstLine(), 2);
        expect(b.getValue(), "z3\n4q");
        expect(a.getValue(), "1x\nyy\nz3\n4q\nrr\ns5");
        a.execCommand("selectAll");
        a.replaceSelection("!");
        eqAll("!", [a, b]);
      });
    });

    test('sharedMarker', () {
      testDoc("A='ab\ncd\nef\ngh' B<A C<~A/1-2", (CodeMirror a, CodeMirror b, CodeMirror c) {
        SharedTextMarker mark = b.markText(new Pos(0, 1), new Pos(3, 1),
                              className: "cm-searching", shared: true);
        var found = a.findMarksAt(new Pos(0, 2));
        expect(found.length, 1);
        expect(found[0], mark);
        expect(c.findMarksAt(new Pos(1, 1)).length, 1);
        expect(mark.find().from, new Pos(0, 1));
        expect(mark.find().to, new Pos(3, 1));
        b.replaceRange("x\ny\n", new Pos(0, 0));
        expect(mark.find().from, new Pos(2, 1));
        expect(mark.find().to, new Pos(5, 1));
        var cleared = 0;
        clear() { ++cleared; };
        b.on(mark, "clear", clear);
        b.runInOp(b, () { mark.clear(); });
        b.off(mark, "clear", clear);
        expect(a.findMarksAt(new Pos(3, 1)).length, 0);
        expect(b.findMarksAt(new Pos(3, 1)).length, 0);
        expect(c.findMarksAt(new Pos(3, 1)).length, 0);
        expect(mark.find(), null);
        expect(cleared, 1);
      });
    });

    test('sharedMarkerCopy', () {
      testDoc("A='abcde'", (CodeMirror a) {
        var shared = a.markText(new Pos(0, 1), new Pos(0, 3), shared: true);
        var b = a.linkedDoc();
        var found = b.findMarksAt(new Pos(0, 2));
        expect(found.length, 1);
        expect(found[0], shared);
        shared.clear();
        expect(b.findMarksAt(new Pos(0, 2)), []);
      });
    });

    test('sharedMarkerDetach', () {
      testDoc("A='abcde' B<A C<B", (CodeMirror a, CodeMirror b, CodeMirror c) {
        var shared = a.markText(new Pos(0, 1), new Pos(0, 3), shared: true);
        a.unlinkDoc(b);
        var inB = b.findMarksAt(new Pos(0, 2));
        expect(inB.length, 1);
        expect(inB[0] != shared, isTrue);
        var inC = c.findMarksAt(new Pos(0, 2));
        expect(inC.length, 1);
        expect(inC[0] == shared, isFalse);
        inC[0].clear();
        expect(shared.find(), isNotNull);
      });
    });

    test('sharedBookmark', () {
      testDoc("A='ab\ncd\nef\ngh' B<A C<~A/1-2", (CodeMirror a, CodeMirror b, CodeMirror c) {
        var mark = b.setBookmark(new Pos(1, 1), shared: true);
        var found = a.findMarksAt(new Pos(1, 1));
        expect(found.length, 1);
        expect(found[0], mark);
        expect(c.findMarksAt(new Pos(1, 1)).length, 1);
        expect(mark.find().toString(), new Span(new Pos(1, 1), new Pos(1, 1)).toString());
        b.replaceRange("x\ny\n", new Pos(0, 0));
        expect(mark.find().toString(), new Span(new Pos(3, 1), new Pos(3, 1)).toString());
        var cleared = 0;
        clear() { ++cleared; };
        b.on(mark, "clear", clear);
        b.runInOp(b, () { mark.clear(); });
        b.off(mark, "clear", clear);
        expect(a.findMarks(new Pos(0, 0), new Pos(5)).length, 0);
        expect(b.findMarks(new Pos(0, 0), new Pos(5)).length, 0);
        expect(c.findMarks(new Pos(0, 0), new Pos(5)).length, 0);
        expect(mark.find(), null);
        expect(cleared, 1);
      });
    });

    test('undoInSubview', () {
      testDoc("A='line 0\nline 1\nline 2\nline 3\nline 4' B<A/1-4", (CodeMirror a, CodeMirror b) {
        b.replaceRange("x", new Pos(2, 0));
        a.undo();
        expect(a.getValue(), "line 0\nline 1\nline 2\nline 3\nline 4");
        expect(b.getValue(), "line 1\nline 2\nline 3");
      });
    });

  });
}

void testDoc(String spec, Function run, [Map opts=null]) {
  if (opts == null) opts = {};
  var editors = instantiateSpec(spec, opts);
  var successful = false;

  try {
    Function.apply(run, editors);
    successful = true;
  } finally {
    if (!successful) {
      Element place = document.getElementById("testground");
      place.style.visibility = "visible";
    } else {
      for (var i = 0; i < editors.length; ++i)
        if (editors[i] is CodeMirror)
          editors[i].getWrapperElement().remove();
    }
  }
}

// A minilanguage for instantiating linked CodeMirror instances and Docs.
//
// Example 1: "A='multi-line content' B<A C<~A/1-2"
// A, B, and C are names of editors on the same 'multi-line content'.
// A and B have identical behavior, including shared undo history.
// C has separate undo history, and only 'sees' lines 1-2 of the shared content.
//
// Example 2: "A*='content' B*<A C<B"
// A and B are names of documents; C is an editor; all have same 'content'.
// Undo history is shared between all three.
//
List instantiateSpec(String spec, Map options) {
  Element place = document.getElementById("testground");
  var names = {}, editors = [];
  while (!spec.isEmpty) {
    var re = new RegExp(r"^(\w+)(\*?)(?:='([^\']*)'|<(~?)(\w+)(?:\/(\d+)-(\d+))?)\s*");
    Match m = re.firstMatch(spec);
    var cur, name = m.group(1);
    bool isDoc = !m.group(2).isEmpty;
    Options opts = new Options.from(options);
    var g3 = m.group(3);
    if (g3 != null) {
      opts['value'] = g3;
      cur = isDoc ? new Doc(g3, null) : new CodeMirror(place, opts);
    } else {
      var other = m.group(5);
      if (!names.containsKey(other)) {
        names[other] = editors.length;
        editors.add(new CodeMirror(place, opts));
      }
      var doc = editors[names[other]].linkedDoc(
        sharedHist: m.group(4).isEmpty,
        from: m.group(6) != null ? int.parse(m.group(6)) : -1,
        to: m.group(7) != null ? int.parse(m.group(7)) : -1
      );
      cur = isDoc ? doc : new CodeMirror(place, opts.copy()..['value']=doc);
    }
    names[name] = editors.length;
    editors.add(cur);
    spec = spec.substring(m.group(0).length);
  }
  return editors;
}

void testBasic(CodeMirror a, CodeMirror b) {
  eqAll("x", [a, b]);
  a.setValue("hey");
  eqAll("hey", [a, b]);
  b.setValue("wow");
  eqAll("wow", [a, b]);
  a.replaceRange("u\nv\nw", new Pos(0, 3));
  b.replaceRange("i", new Pos(0, 4));
  b.replaceRange("j", new Pos(2, 1));
  eqAll("wowui\nv\nwj", [a, b]);
}

eqAll(String val, List args, [String msg='']) {
  // The args list may contain CodeEditor or Document instances.
  if (args == null || args.length == 0) fail("No editors provided to eqAll");
  for (var i = 0; i < args.length; ++i) {
    expect(args[i] is Doc || args[i] is CodeMirror, isTrue);
    expect(args[i].getValue(), val, reason: "index: $i $msg");
  }
}
