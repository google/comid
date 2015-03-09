// Copyright (c) 2015, the Comid Authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

part of comid.test;

cssModeTest() {
  baseModeTest();
  scssModeTest();
  lessModeTest();
}

baseModeTest() {
  CssMode.initialize();
  Mode mode = CodeMirror.getMode({'indentUnit': 2}, "text/css");
  MT(String name, [_0, _1, _2, _3, _4, _5, _6, _7, _8, _9, _a, _b, _c, _d, _e]) {
    List args = varargs(_0, _1, _2, _3, _4, _5, _6, _7, _8, _9, _a, _b, _c, _d, _e);
    test_mode(name, mode, args);
  }

  // Error, because "foobarhello" is neither a known type or property, but
  // property was expected (after "and"), and it should be in parenthese.
  MT("atMediaUnknownType",
     "[def @media] [attribute screen] [keyword and] [error foobarhello] { }");

  // Soft error, because "foobarhello" is not a known property or type.
  MT("atMediaUnknownProperty",
     "[def @media] [attribute screen] [keyword and] ([error foobarhello]) { }");

  // Make sure nesting works with media queries
  MT("atMediaMaxWidthNested",
     "[def @media] [attribute screen] [keyword and] ([property max-width]: [number 25px]) { [tag foo] { } }");

  MT("tagSelector",
     "[tag foo] { }");

  MT("classSelector",
     "[qualifier .foo-bar_hello] { }");

  MT("idSelector",
     "[builtin #foo] { [error #foo] }");

  MT("tagSelectorUnclosed",
     "[tag foo] { [property margin]: [number 0] } [tag bar] { }");

  MT("tagStringNoQuotes",
     "[tag foo] { [property font-family]: [variable hello] [variable world]; }");

  MT("tagStringDouble",
     "[tag foo] { [property font-family]: [string \"hello world\"]; }");

  MT("tagStringSingle",
     "[tag foo] { [property font-family]: [string 'hello world']; }");

  MT("tagColorKeyword",
     "[tag foo] {",
     "  [property color]: [keyword black];",
     "  [property color]: [keyword navy];",
     "  [property color]: [keyword yellow];",
     "}");

  MT("tagColorHex3",
     "[tag foo] { [property background]: [atom #fff]; }");

  MT("tagColorHex6",
     "[tag foo] { [property background]: [atom #ffffff]; }");

  MT("tagColorHex4",
     "[tag foo] { [property background]: [atom&error #ffff]; }");

  MT("tagColorHexInvalid",
     "[tag foo] { [property background]: [atom&error #ffg]; }");

  MT("tagNegativeNumber",
     "[tag foo] { [property margin]: [number -5px]; }");

  MT("tagPositiveNumber",
     "[tag foo] { [property padding]: [number 5px]; }");

  MT("tagVendor",
     "[tag foo] { [meta -foo-][property box-sizing]: [meta -foo-][atom border-box]; }");

  MT("tagBogusProperty",
     "[tag foo] { [property&error barhelloworld]: [number 0]; }");

  MT("tagTwoProperties",
     "[tag foo] { [property margin]: [number 0]; [property padding]: [number 0]; }");

  MT("tagTwoPropertiesURL",
     "[tag foo] { [property background]: [atom url]([string //example.com/foo.png]); [property padding]: [number 0]; }");

  MT("commentSGML",
     "[comment <!--comment-->]");

  MT("commentSGML2",
     "[comment <!--comment]",
     "[comment -->] [tag div] {}");

  MT("indent_tagSelector",
     "[tag strong], [tag em] {",
     "  [property background]: [atom rgba](",
     "    [number 255], [number 255], [number 0], [number .2]",
     "  );",
     "}");

  MT("indent_atMedia",
     "[def @media] {",
     "  [tag foo] {",
     "    [property color]:",
     "      [keyword yellow];",
     "  }",
     "}");

  MT("indent_comma",
     "[tag foo] {",
     "  [property font-family]: [variable verdana],",
     "    [atom sans-serif];",
     "}");

  MT("indent_parentheses",
     "[tag foo]:[variable-3 before] {",
     "  [property background]: [atom url](",
     "[string     blahblah]",
     "[string     etc]",
     "[string   ]) [keyword !important];",
     "}");

  MT("font_face",
     "[def @font-face] {",
     "  [property font-family]: [string 'myfont'];",
     "  [error nonsense]: [string 'abc'];",
     "  [property src]: [atom url]([string http://blah]),",
     "    [atom url]([string http://foo]);",
     "}");

  MT("empty_url",
     "[def @import] [tag url]() [tag screen];");

  MT("parens",
     "[qualifier .foo] {",
     "  [property background-image]: [variable fade]([atom #000], [number 20%]);",
     "  [property border-image]: [variable linear-gradient](",
     "    [atom to] [atom bottom],",
     "    [variable fade]([atom #000], [number 20%]) [number 0%],",
     "    [variable fade]([atom #000], [number 20%]) [number 100%]",
     "  );",
     "}");
}

scssModeTest() {
  CssMode.initialize();
  Mode mode = CodeMirror.getMode({'indentUnit': 2}, "text/x-scss");
  MT(String name, [_0, _1, _2, _3, _4, _5, _6, _7, _8, _9, _a, _b, _c, _d, _e]) {
    List args = varargs(_0, _1, _2, _3, _4, _5, _6, _7, _8, _9, _a, _b, _c, _d, _e);
    test_mode(name, mode, args, "scss");
  }

  MT('url_with_quotation',
    "[tag foo] { [property background]:[atom url]([string test.jpg]) }");

  MT('url_with_double_quotes',
    "[tag foo] { [property background]:[atom url]([string \"test.jpg\"]) }");

  MT('url_with_single_quotes',
    "[tag foo] { [property background]:[atom url]([string \'test.jpg\']) }");

  MT('string',
    "[def @import] [string \"compass/css3\"]");

  MT('important_keyword',
    "[tag foo] { [property background]:[atom url]([string \'test.jpg\']) [keyword !important] }");

  MT('variable',
    "[variable-2 \$blue]:[atom #333]");

  MT('variable_as_attribute',
    "[tag foo] { [property color]:[variable-2 \$blue] }");

  MT('numbers',
    "[tag foo] { [property padding]:[number 10px] [number 10] [number 10em] [number 8in] }");

  MT('number_percentage',
    "[tag foo] { [property width]:[number 80%] }");

  MT('selector',
    "[builtin #hello][qualifier .world]{}");

  MT('singleline_comment',
    "[comment // this is a comment]");

  MT('multiline_comment',
    "[comment /*foobar*/]");

  MT('attribute_with_hyphen',
    "[tag foo] { [property font-size]:[number 10px] }");

  MT('string_after_attribute',
    "[tag foo] { [property content]:[string \"::\"] }");

  MT('directives',
    "[def @include] [qualifier .mixin]");

  MT('basic_structure',
    "[tag p] { [property background]:[keyword red]; }");

  MT('nested_structure',
    "[tag p] { [tag a] { [property color]:[keyword red]; } }");

  MT('mixin',
    "[def @mixin] [tag table-base] {}");

  MT('number_without_semicolon',
    "[tag p] {[property width]:[number 12]}",
    "[tag a] {[property color]:[keyword red];}");

  MT('atom_in_nested_block',
    "[tag p] { [tag a] { [property color]:[atom #000]; } }");

  MT('interpolation_in_property',
    "[tag foo] { #{[variable-2 \$hello]}:[number 2]; }");

  MT('interpolation_in_selector',
    "[tag foo]#{[variable-2 \$hello]} { [property color]:[atom #000]; }");

  MT('interpolation_error',
    "[tag foo]#{[error foo]} { [property color]:[atom #000]; }");

  MT("divide_operator",
    "[tag foo] { [property width]:[number 4] [operator /] [number 2] }");

  MT('nested_structure_with_id_selector',
    "[tag p] { [builtin #hello] { [property color]:[keyword red]; } }");

  MT('indent_mixin',
     "[def @mixin] [tag container] (",
     "  [variable-2 \$a]: [number 10],",
     "  [variable-2 \$b]: [number 10])",
     "{}");

  MT('indent_nested',
     "[tag foo] {",
     "  [tag bar] {",
     "  }",
     "}");

  MT('indent_parentheses',
     "[tag foo] {",
     "  [property color]: [variable darken]([variable-2 \$blue],",
     "    [number 9%]);",
     "}");

  MT('indent_vardef',
     "[variable-2 \$name]:",
     "  [string 'val'];",
     "[tag tag] {",
     "  [tag inner] {",
     "    [property margin]: [number 3px];",
     "  }",
     "}");
}

lessModeTest() {
  CssMode.initialize();
  Mode mode = CodeMirror.getMode({'indentUnit': 2}, "text/x-less");
  MT(String name, [_0, _1, _2, _3, _4, _5, _6, _7, _8, _9, _a, _b, _c, _d, _e]) {
    List args = varargs(_0, _1, _2, _3, _4, _5, _6, _7, _8, _9, _a, _b, _c, _d, _e);
    test_mode(name, mode, args, "less");
  }

  MT("variable",
     "[variable-2 @base]: [atom #f04615];",
     "[qualifier .class] {",
     "  [property width]: [variable percentage]([number 0.5]); [comment // returns `50%`]",
     "  [property color]: [variable saturate]([variable-2 @base], [number 5%]);",
     "}");

  MT("amp",
     "[qualifier .child], [qualifier .sibling] {",
     "  [qualifier .parent] [atom &] {",
     "    [property color]: [keyword black];",
     "  }",
     "  [atom &] + [atom &] {",
     "    [property color]: [keyword red];",
     "  }",
     "}");

  MT("mixin",
     "[qualifier .mixin] ([variable dark]; [variable-2 @color]) {",
     "  [property color]: [variable darken]([variable-2 @color], [number 10%]);",
     "}",
     "[qualifier .mixin] ([variable light]; [variable-2 @color]) {",
     "  [property color]: [variable lighten]([variable-2 @color], [number 10%]);",
     "}",
     "[qualifier .mixin] ([variable-2 @_]; [variable-2 @color]) {",
     "  [property display]: [atom block];",
     "}",
     "[variable-2 @switch]: [variable light];",
     "[qualifier .class] {",
     "  [qualifier .mixin]([variable-2 @switch]; [atom #888]);",
     "}");

  MT("nest",
     "[qualifier .one] {",
     "  [def @media] ([property width]: [number 400px]) {",
     "    [property font-size]: [number 1.2em];",
     "    [def @media] [attribute print] [keyword and] [property color] {",
     "      [property color]: [keyword blue];",
     "    }",
     "  }",
     "}");

}