// Copyright (c) 2015, the Comid Authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

part of comid.test;

scrollTest() {
  // Test scrolling operations.
  group('Scrolling,', () {
    CodeMirror editor;

    test('bars_hidden', () {
      editor = makeEditor();
      for (var i = 0;; i++) {
        var wrapBox = editor.getWrapperElement().getBoundingClientRect();
        var scrollBox = editor.getScrollerElement().getBoundingClientRect();
        expect(wrapBox.bottom < scrollBox.bottom - 10, isTrue);
        expect(wrapBox.right < scrollBox.right - 10, isTrue);
        if (i == 1) break;
        editor.getWrapperElement().style.height = "auto";
        editor.refresh();
      }
    });

    test('movedown_fixed', () {
      editor = makeEditor();
      testMovedownFixed(editor, false);
    });

    test('movedown_hscroll_fixed', () {
      editor = makeEditor();
      testMovedownFixed(editor, true);
    });

    test('movedown_resize', () {
      editor = makeEditor();
      testMovedownResize(editor, false);
    });

    test('movedown_hscroll_resize', () {
      editor = makeEditor();
      testMovedownResize(editor, true);
    });

    test('moveright', () {
      editor = makeEditor();
      testMoveright(editor, false, false);
    });

    test('moveright_wrap', () {
      editor = makeEditor();
      testMoveright(editor, true, false);
    });

    test('moveright_scroll', () {
      editor = makeEditor();
      testMoveright(editor, false, true);
    });

    test('moveright_scroll_wrap', () {
      editor = makeEditor();
      testMoveright(editor, true, true);
    });
  });
}

Element barH(CodeMirror cm) {
  return byClassName(cm.getWrapperElement(), "CodeMirror-hscrollbar")[0];
}

Element barV(CodeMirror cm) {
  return byClassName(cm.getWrapperElement(), "CodeMirror-vscrollbar")[0];
}

num displayBottom(CodeMirror cm, scrollbar) {
  if (scrollbar)
    return barH(cm).getBoundingClientRect().top;
  else
    return cm.getWrapperElement().getBoundingClientRect().bottom - 1;
}

num displayRight(CodeMirror cm, bool scrollbar) {
  if (scrollbar)
    return barV(cm).getBoundingClientRect().left;
  else
    return cm.getWrapperElement().getBoundingClientRect().right - 1;
}

testMovedownFixed(CodeMirror cm, bool hScroll) {
  cm.setSize("100px", "100px");
  if (hScroll) cm.setValue(new List.filled(100, '').join("x"));
  var bottom = displayBottom(cm, hScroll);
  var cursorBottom;
  for (var i = 0; i < 30; i++) {
    cm.replaceSelection("x\n");
    cursorBottom = cm.cursorCoords(null, "window").bottom;
    expect(cursorBottom <= bottom, isTrue);
  }
  expect(cursorBottom >= bottom - 5, isTrue);
}

testMovedownResize(CodeMirror cm, bool hScroll) {
  cm.getWrapperElement().style.height = "auto";
  if (hScroll) cm.setValue(new List.filled(100, '').join("x"));
  cm.refresh();
  for (var i = 0; i < 30; i++) {
    cm.replaceSelection("x\n");
    var bottom = displayBottom(cm, hScroll);
    var cursorBottom = cm.cursorCoords(null, "window").bottom;
    expect(cursorBottom <= bottom, isTrue);
    expect(cursorBottom >= bottom - 5, isTrue);
  }
}

testMoveright(CodeMirror cm, bool wrap, bool scroll) {
  cm.setSize("100px", "100px");
  if (wrap) cm.setOption("lineWrapping", true);
  if (scroll) {
    cm.setValue("\n" + new List.filled(100, '').join("x\n"));
    cm.setCursor(new Pos(0, 0));
  }
  var right = displayRight(cm, scroll);
  var cursorRight;
  for (var i = 0; i < 10; i++) {
    cm.replaceSelection("xxxxxxxxxx");
    cursorRight = cm.cursorCoords(null, "window").right;
    expect(cursorRight < right, isTrue);
  }
  if (!wrap) expect(cursorRight > right - 20, isTrue);
}
