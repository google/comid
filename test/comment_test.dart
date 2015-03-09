// Copyright (c) 2015, the Comid Authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

part of comid.test;

commentTest() {
  group('Comment,', () {

    testc("block", "application/dart", (cm) {
      blockComment(cm, new Pos(0, 3), new Pos(3, 0), {'blockCommentLead': " *"});
    }, simpleProg + "\n", "/* foo() {\n *   return bar;\n * }\n */");

    testc("blockToggle", "clike", (cm) {
      blockComment(cm, new Pos(0, 3), new Pos(2, 0), {'blockCommentLead': " *"});
      uncomment(cm, new Pos(0, 3), new Pos(2, 0), {'blockCommentLead': " *"});
    }, simpleProg, simpleProg);

    testc("blockToggle2", "clike", (cm) {
      cm.setCursor(new Pos(0,7) /* inside the block comment */);
      cm.execCommand("toggleComment");
    }, inlineBlock, "foo(bar true);");

// This test should work but currently fails.
//    testc("blockToggle3", "clike", (cm) {
//      cm.setCursor(new Pos(0,7) /* inside the first block comment */);
//      cm.execCommand("toggleComment");
//    }, inlineBlocks, "foo(bar true, /* baz */ false);");

    testc("line", "clike", (cm) {
      lineComment(cm, new Pos(1, 1), new Pos(1, 1));
    }, simpleProg, "foo() {\n//   return bar;\n}");

    testc("lineToggle", "clike", (cm) {
      lineComment(cm, new Pos(0, 0), new Pos(2, 1));
      uncomment(cm, new Pos(0, 0), new Pos(2, 1));
    }, simpleProg, simpleProg);

    testc("fallbackToBlock", "css", (cm) {
      lineComment(cm, new Pos(0, 0), new Pos(2, 1));
    }, "html {\n  border: none;\n}", "/* html {\n  border: none;\n} */");

//    testc("fallbackToLine", "ruby", (cm) {
//      blockComment(cm, new Pos(0, 0), new Pos(1));
//    }, "def blah()\n  return hah\n", "# def blah()\n#   return hah\n");

    testc("ignoreExternalBlockComments", "clike", (cm) {
      cm.execCommand("toggleComment");
    }, inlineBlocks, "// " + inlineBlocks);

    testc("ignoreExternalBlockComments2", "clike", (cm) {
      cm.setCursor(new Pos(0) /* eol */);
      cm.execCommand("toggleComment");
    }, inlineBlocks, "// " + inlineBlocks);

    testc("ignoreExternalBlockCommentsMultiLineAbove", "clike", (cm) {
      cm.setSelection(new Pos(0,0), new Pos(1,1));
      cm.execCommand("toggleComment");
    }, multiLineInlineBlock.join("\n"), ["// " + multiLineInlineBlock[0],
                                         "// " + multiLineInlineBlock[1],
                                         multiLineInlineBlock[2]].join("\n"));

    testc("ignoreExternalBlockCommentsMultiLineBelow", "clike", (cm) {
      cm.setSelection(new Pos(1,13) /* after end of block comment */, new Pos(2,1));
      cm.execCommand("toggleComment");
    }, multiLineInlineBlock.join("\n"), [multiLineInlineBlock[0],
                                         "// " + multiLineInlineBlock[1],
                                         "// " + multiLineInlineBlock[2]].join("\n"));

    testc("commentRange", "clike", (cm) {
      blockComment(cm, new Pos(1, 2), new Pos(1, 13), {'fullLines': false});
    }, simpleProg, "foo() {\n  /*return bar;*/\n}");

    testc("indented", "clike", (cm) {
      lineComment(cm, new Pos(1, 0), new Pos(2), {'indent': true});
    }, simpleProg, "foo() {\n  // return bar;\n  // }");

    testc("singleEmptyLine", "clike", (cm) {
      cm.setCursor(new Pos(1));
      cm.execCommand("toggleComment");
    }, "a;\n\nb;", "a;\n// \nb;");

    testc("dontMessWithStrings", "clike", (cm) {
      cm.execCommand("toggleComment");
    }, "console.log(\"/*string*/\");", "// console.log(\"/*string*/\");");

    testc("dontMessWithStrings2", "clike", (cm) {
      cm.execCommand("toggleComment");
    }, "console.log(\"// string\");", "// console.log(\"// string\");");

    testc("dontMessWithStrings3", "clike", (cm) {
      cm.execCommand("toggleComment");
    }, "// console.log(\"// string\");", "console.log(\"// string\");");

  });
}

var simpleProg = "foo() {\n  return bar;\n}";
var inlineBlock = "foo(/* bar */ true);";
var inlineBlocks = "foo(/* bar */ true, /* baz */ false);";
var multiLineInlineBlock = ["above();", "foo(/* bar */ true);", "below();"];

testc(name, mode, run, before, after) {
  var cm = makeEditor({'value': before, 'mode': mode});
  test(name, () {
    run(cm);
    expect(cm.getValue(), after);
  });
}
_o(opts) => opts == null ? Options.defaultOptions : new Options.from(opts);
blockComment(cm, from, to, [opts]) => comment.blockComment(cm, from, to, _o(opts));
lineComment(cm, from, to, [opts]) => comment.lineComment(cm, from, to, _o(opts));
uncomment(cm, from, to, [opts]) => comment.uncomment(cm, from, to, _o(opts));
