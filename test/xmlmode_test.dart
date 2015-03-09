// Copyright (c) 2015, the Comid Authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

part of comid.test;

xmlModeTest() {
  XmlMode.initialize();
  var mode = CodeMirror.getMode({'indentUnit': 2}, "xml"), mname = "xml";
  MT(String name, [_0, _1, _2, _3, _4, _5, _6, _7, _8, _9, _a, _b, _c, _d, _e]) {
    List args = varargs(_0, _1, _2, _3, _4, _5, _6, _7, _8, _9, _a, _b, _c, _d, _e);
    test_mode(name, mode, args, mname);
  }

  MT("matching",
     "[tag&bracket <][tag top][tag&bracket >]",
     "  text",
     "  [tag&bracket <][tag inner][tag&bracket />]",
     "[tag&bracket </][tag top][tag&bracket >]");

  MT("nonmatching",
     "[tag&bracket <][tag top][tag&bracket >]",
     "  [tag&bracket <][tag inner][tag&bracket />]",
     "  [tag&bracket </][tag&error tip][tag&bracket&error >]");

  MT("doctype",
     "[meta <!doctype foobar>]",
     "[tag&bracket <][tag top][tag&bracket />]");

  MT("cdata",
     "[tag&bracket <][tag top][tag&bracket >]",
     "  [atom <![CDATA[foo]",
     "[atom barbazguh]]]]>]",
     "[tag&bracket </][tag top][tag&bracket >]");

  // HTML tests
  mode = CodeMirror.getMode({'indentUnit': 2}, "text/html");

  MT("selfclose",
     "[tag&bracket <][tag html][tag&bracket >]",
     "  [tag&bracket <][tag link] [attribute rel]=[string stylesheet] [attribute href]=[string \"/foobar\"][tag&bracket >]",
     "[tag&bracket </][tag html][tag&bracket >]");

  MT("list",
     "[tag&bracket <][tag ol][tag&bracket >]",
     "  [tag&bracket <][tag li][tag&bracket >]one",
     "  [tag&bracket <][tag li][tag&bracket >]two",
     "[tag&bracket </][tag ol][tag&bracket >]");

  MT("valueless",
     "[tag&bracket <][tag input] [attribute type]=[string checkbox] [attribute checked][tag&bracket />]");

  MT("pThenArticle",
     "[tag&bracket <][tag p][tag&bracket >]",
     "  foo",
     "[tag&bracket <][tag article][tag&bracket >]bar");

}
