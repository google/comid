// Copyright (c) 2015, the Comid Authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library comid.mode.clike;

import 'package:comid/codemirror.dart';

class ClikeMode extends Mode {

  static bool _isInitialized = false;
  static initialize() {
    if (_isInitialized) return;
    _initializeMode();
    _isInitialized = true;
  }

  final RegExp isOperatorChar = new RegExp(r'[+\-*&%=<>!?|\/]');
  String curPunc;

  // Parser configuration
  int indentUnit;
  int statementIndentUnit;
  bool dontAlignCalls;
  Set keywords;
  Set builtin;
  Set blockKeywords;
  Set atoms;
  Map hooks;
  bool multiLineStrings;
  bool indentStatements;

  ClikeMode(var config, var parserConfig) {
    Map emptyMapOr(Map val) => val == null ? {} : val;
    Set emptySetOr(Set val) => val == null ? new Set() : val;
    if (config is Map) config = new Options.from(config);
    if (parserConfig is Map) parserConfig = new Config();
    indentUnit = config.indentUnit;
    statementIndentUnit = parserConfig.statementIndentUnit == null
        ? indentUnit : parserConfig.statementIndentUnit;
    dontAlignCalls = parserConfig.dontAlignCalls;
    keywords = emptySetOr(parserConfig.keywords);
    builtin = emptySetOr(parserConfig.builtin);
    blockKeywords = emptySetOr(parserConfig.blockKeywords);
    atoms = emptySetOr(parserConfig.atoms);
    hooks = emptyMapOr(parserConfig.hooks);
    multiLineStrings = parserConfig.multiLineStrings;
    indentStatements = parserConfig.indentStatements != false;
    this['fold'] = 'brace';
  }

  String tokenBase(StringStream stream, ClikeState state) {
    var ch = stream.next();
    if (hooks[ch] != null) {
      var result = hooks[ch](stream, state);
      if (result != false) return result;
    }
    if (ch == '"' || ch == "'") {
      state.tokenize = tokenString(ch);
      return state.tokenize(stream, state);
    }
    if (new RegExp(r'[\[\]{}\(\),;\:\.]').hasMatch(ch)) {
      curPunc = ch;
      return null;
    }
    if (new RegExp(r'\d').hasMatch(ch)) {
      stream.eatWhile(new RegExp(r'[\w\.]'));
      return "number";
    }
    if (ch == "/") {
      if (stream.eat("*") != null) {
        state.tokenize = tokenComment;
        return tokenComment(stream, state);
      }
      if (stream.eat("/") != null) {
        stream.skipToEnd();
        return "comment";
      }
    }
    if (isOperatorChar.hasMatch(ch)) {
      stream.eatWhile(isOperatorChar);
      return "operator";
    }
    stream.eatWhile(new RegExp(r'[\w\$_\xa1-\uffff]'));
    var cur = stream.current();
    if (keywords.contains(cur)) {
      if (blockKeywords.contains(cur)) curPunc = "newstatement";
      return "keyword";
    }
    if (builtin.contains(cur)) {
      if (blockKeywords.contains(cur)) curPunc = "newstatement";
      return "builtin";
    }
    if (atoms.contains(cur)) return "atom";
    return "variable";
  }

  Function tokenString(quote) {
    return (StringStream stream, ClikeState state) {
      bool escaped = false, end = false;
      var next;
      while ((next = stream.next()) != null) {
        if (next == quote && !escaped) {
          end = true; break;
        }
        escaped = !escaped && next == "\\";
      }
      if (end || !(escaped || multiLineStrings))
        state.tokenize = null;
      return "string";
    };
  }

  String tokenComment(StringStream stream, ClikeState state) {
    bool maybeEnd = false;
    var ch;
    while ((ch = stream.next()) != null) {
      if (ch == "/" && maybeEnd) {
        state.tokenize = null;
        break;
      }
      maybeEnd = (ch == "*");
    }
    return "comment";
  }

  Context pushContext(ClikeState state, col, String type) {
    var indent = state.indented;
    if (state.context != null && state.context.type == "statement")
      indent = state.context.indented;
    return state.context = new Context(indent, col, type, null, state.context);
  }

  Context popContext(state) {
    var t = state.context.type;
    if (t == ")" || t == "]" || t == "}")
      state.indented = state.context.indented;
    return state.context = state.context.prev;
  }

  ClikeState startState([basecolumn, x]) {
    var ctx = new Context((basecolumn == null ? 0 : basecolumn) - indentUnit,
        0, "top", false);
    return new ClikeState(
      tokenize: null,
      context: ctx,
      indented: 0,
      startOfLine: true
    );
  }

  String token(StringStream stream, [ClikeState state]) {
    var ctx = state.context;
    if (stream.sol()) {
      if (ctx.align == null) ctx.align = false;
      state.indented = stream.indentation();
      state.startOfLine = true;
    }
    if (stream.eatSpace()) return null;
    curPunc = null;
    Function tokenizer = state.tokenize == null ? tokenBase : state.tokenize;
    var style = tokenizer(stream, state);
    if (style == "comment" || style == "meta") return style;
    if (ctx.align == null) ctx.align = true;

    if ((curPunc == ";" || curPunc == ":" || curPunc == ",") &&
        ctx.type == "statement") popContext(state);
    else if (curPunc == "{") pushContext(state, stream.column(), "}");
    else if (curPunc == "[") pushContext(state, stream.column(), "]");
    else if (curPunc == "(") pushContext(state, stream.column(), ")");
    else if (curPunc == "}") {
      while (ctx.type == "statement") ctx = popContext(state);
      if (ctx.type == "}") ctx = popContext(state);
      while (ctx.type == "statement") ctx = popContext(state);
    }
    else if (curPunc == ctx.type) popContext(state);
    else if (indentStatements &&
             (((ctx.type == "}" || ctx.type == "top") && curPunc != ';') ||
              (ctx.type == "statement" && curPunc == "newstatement")))
      pushContext(state, stream.column(), "statement");
    state.startOfLine = false;
    return style;
  }

  dynamic indent(ClikeState state, String textAfter, x) {
    if (state.tokenize != tokenBase && state.tokenize != null) {
      return Pass;
    }
    var ctx = state.context;
    String firstChar = textAfter == null || textAfter.isEmpty
        ? textAfter : textAfter.substring(0,1);
    if (ctx.type == "statement" && firstChar == "}") ctx = ctx.prev;
    var closing = firstChar == ctx.type;
    if (ctx.type == "statement") {
      return ctx.indented + (firstChar == "{" ? 0 : statementIndentUnit);
    } else if (ctx.align != null && ctx.align != false && (!dontAlignCalls || ctx.type != ")")) {
      return ctx.column + (closing ? 0 : 1);
    } else if (ctx.type == ")" && !closing) {
      return ctx.indented + statementIndentUnit;
    } else {
      return ctx.indented + (closing ? 0 : indentUnit);
    }
  }

  String get electricChars => "{}"; // C-like languages have a lot in common...
  String get blockCommentStart => "/*";
  String get blockCommentEnd => "*/";
  String get blockCommentContinue => " * ";
  String get lineComment => "//";
  dynamic get fold => this['fold']; // ... but folding does vary a bt.

  bool get hasIndent => true;
  bool get hasStartState => true;
  bool get hasElectricChars => true;
}

Set words(String str) {
  var words = str.split(" ");
  return new Set.from(words);
}

var cKeywords = "auto if break int case long char register continue " +
    "return default short do sizeof double static else struct entry " +
    "switch extern typedef float union for unsigned goto while enum " +
    "void const signed volatile";

dynamic cppHook(StringStream stream, ClikeState state) {
  if (!state.startOfLine) return false;
  for (;;) {
    if (stream.skipTo("\\")) {
      stream.next();
      if (stream.eol()) {
        state.tokenize = cppHook;
        break;
      }
    } else {
      stream.skipToEnd();
      state.tokenize = null;
      break;
    }
  }
  return "meta";
}

dynamic cpp11StringHook(StringStream stream, ClikeState state) {
  stream.backUp(1);
  // Raw strings.
  if (stream.match(new RegExp(r'(R|u8R|uR|UR|LR)')) != null) {
    Match match = stream.match(new RegExp(r'"([^\s\\()]{0,16})\('));
    if (match == null) {
      return false;
    }
    state.cpp11RawStringDelim = match.group(1);
    state.tokenize = tokenRawString;
    return tokenRawString(stream, state);
  }
  // Unicode strings/chars.
  if (stream.match(new RegExp(r'(u8|u|U|L)')) != null) {
    if (stream.match(new RegExp('["\']'), /* eat */ false) != null) {
      return "string";
    }
    return false;
  }
  // Ignore this hook.
  stream.next();
  return false;
}

// C#-style strings where "" escapes a quote.
String tokenAtString(StringStream stream, ClikeState state) {
  var next;
  while ((next = stream.next()) != null) {
    if (next == '"' && stream.eat('"') == null) {
      state.tokenize = null;
      break;
    }
  }
  return "string";
}

// C++11 raw string literal is <prefix>"<delim>( anything )<delim>", where
// <delim> can be a string up to 16 characters long.
String tokenRawString(StringStream stream, ClikeState state) {
  // Escape characters that have special regex meanings.
//  var delim1 = state.cpp11RawStringDelim.replace(/[^\w\s]/g, '\\$&');
  var delim = state.cpp11RawStringDelim.replaceAllMapped(
        new RegExp(r'[^\w\s]'),
        (Match m) => '\\${m[0]}');
//    var match = stream.match(new RegExp(".*?\\)" + delim + '"'));
    var match = stream.match(new RegExp('.*?\\)$delim"'));
    if (match != null)
      state.tokenize = null;
    else
      stream.skipToEnd();
  return "string";
}

String tokenTripleString(StringStream stream, ClikeState state) {
  var escaped = false;
  while (!stream.eol()) {
    if (!escaped && stream.match('"""')) {
      state.tokenize = null;
      break;
    }
    escaped = stream.next() != "\\" && !escaped;
  }
  return "string";
}

void def(dynamic mimes, Config mode) {
  if (mimes is String) mimes = [mimes];
  var words = [];
  add(obj) {
    if (obj != null) for (var prop in obj) {
      words.add(prop);
    }
  }
  add(mode.keywords);
  add(mode.builtin);
  add(mode.atoms);
  if (words.length > 0) {
    mode.helperType = mimes[0];
    CodeMirror.registerHelper("hintWords", mimes[0], words);
  }

  for (var i = 0; i < mimes.length; ++i)
    CodeMirror.defineMIME(mimes[i], mode);
}

void _initializeMode() {

  CodeMirror.defineMode("clike", (var a, var b) => new ClikeMode(a, b));

  def(["text/x-csrc", "text/x-c", "text/x-chdr"], new Config(
    name: "clike",
    keywords: words(cKeywords),
    blockKeywords: words("case do else for if switch while struct"),
    atoms: words("null"),
    hooks: {"#": cppHook},
    modeProps: {'fold': ["brace", "include"]}
  ));

  def(["text/x-c++src", "text/x-c++hdr"], new Config(
    name: "clike",
    keywords: words(cKeywords +
        " asm dynamic_cast namespace reinterpret_cast try bool explicit new " +
        "static_cast typeid catch operator template typename class friend " +
        "private this using const_cast inline public throw virtual delete " +
        "mutable protected wchar_t alignas alignof constexpr decltype nullptr " +
        "noexcept thread_local final static_assert override"),
    blockKeywords:
        words("catch class do else finally for if struct switch try while"),
    atoms: words("true false null"),
    hooks: {
      "#": cppHook,
      "u": cpp11StringHook,
      "U": cpp11StringHook,
      "L": cpp11StringHook,
      "R": cpp11StringHook
    },
    modeProps: {'fold': ["brace", "include"]}
  ));

  def("text/x-java", new Config(
    name: "clike",
    keywords: words(
        "abstract assert boolean break byte case catch char class const " +
        "continue default do double else enum extends final finally float " +
        "for goto if implements import instanceof int interface long native " +
        "new package private protected public return short static strictfp " +
        "super switch synchronized this throw throws transient try void " +
        "volatile while"),
    blockKeywords: words("catch class do else finally for if switch try while"),
    atoms: words("true false null"),
    hooks: {
      "@": (StringStream stream, ClikeState state) {
        stream.eatWhile(new RegExp(r'[\w\$_]'));
        return "meta";
      }
    },
    modeProps: {'fold': ["brace", "import"]}
  ));

  def("text/x-csharp", new Config(
    name: "clike",
    keywords: words(
        "abstract as base break case catch checked class const continue" +
        " default delegate do else enum event explicit extern finally fixed" +
        " for foreach goto if implicit in interface internal is lock" +
        " namespace new operator out override params private protected public" +
        " readonly ref return sealed sizeof stackalloc static struct switch" +
        " this throw try typeof unchecked unsafe using virtual void volatile" +
        " while add alias ascending descending dynamic from get global group" +
        " into join let orderby partial remove select set value var yield"),
    blockKeywords: words(
        "catch class do else finally for foreach if struct switch try while"),
    builtin: words(
        "Boolean Byte Char DateTime DateTimeOffset Decimal Double" +
        " Guid Int16 Int32 Int64 Object SByte Single String TimeSpan UInt16" +
        " UInt32 UInt64 bool byte char decimal double short int long object"  +
        " sbyte float string ushort uint ulong"),
    atoms: words("true false null"),
    hooks: {
      "@": (StringStream stream, ClikeState state) {
        if (stream.eat('"') != null) {
          state.tokenize = tokenAtString;
          return tokenAtString(stream, state);
        }
        stream.eatWhile(new RegExp(r'[\w\$_]'));
        return "meta";
      }
    }
  ));

  def("text/x-scala", new Config(
    name: "clike",
    keywords: words(

      /* scala */
      "abstract case catch class def do else extends false final finally for forSome if " +
      "implicit import lazy match new null object override package private protected return " +
      "sealed super this throw trait try trye type val var while with yield _ : = => <- <: " +
      "<% >: # @ " +

      /* package scala */
      "assert assume require print println printf readLine readBoolean readByte readShort " +
      "readChar readInt readLong readFloat readDouble " +

      "AnyVal App Application Array BufferedIterator BigDecimal BigInt Char Console Either " +
      "Enumeration Equiv Error Exception Fractional Function IndexedSeq Integral Iterable " +
      "Iterator List Map Numeric Nil NotNull Option Ordered Ordering PartialFunction PartialOrdering " +
      "Product Proxy Range Responder Seq Serializable Set Specializable Stream StringBuilder " +
      "StringContext Symbol Throwable Traversable TraversableOnce Tuple Unit Vector :: #:: " +

      /* package java.lang */
      "Boolean Byte Character CharSequence Class ClassLoader Cloneable Comparable " +
      "Compiler Double Exception Float Integer Long Math Number Object Package Pair Process " +
      "Runtime Runnable SecurityManager Short StackTraceElement StrictMath String " +
      "StringBuffer System Thread ThreadGroup ThreadLocal Throwable Triple Void"
    ),
    multiLineStrings: true,
    blockKeywords: words(
        "catch class do else finally for forSome if match switch try while"),
    atoms: words("true false null"),
    indentStatements: false,
    hooks: {
      "@": (StringStream stream, ClikeState state) {
        stream.eatWhile(new RegExp(r'[\w\$_]'));
        return "meta";
      },
      '"': (StringStream stream, ClikeState state) {
        if (!stream.match('""')) return false;
        state.tokenize = tokenTripleString;
        return state.tokenize(stream, state);
      }
    }
  ));

  def(["x-shader/x-vertex", "x-shader/x-fragment"], new Config(
    name: "clike",
    keywords: words("float int bool void " +
                    "vec2 vec3 vec4 ivec2 ivec3 ivec4 bvec2 bvec3 bvec4 " +
                    "mat2 mat3 mat4 " +
                    "sampler1D sampler2D sampler3D samplerCube " +
                    "sampler1DShadow sampler2DShadow " +
                    "const attribute uniform varying " +
                    "break continue discard return " +
                    "for while do if else struct " +
                    "in out inout"),
    blockKeywords: words("for while do if else struct"),
    builtin: words("radians degrees sin cos tan asin acos atan " +
                    "pow exp log exp2 sqrt inversesqrt " +
                    "abs sign floor ceil fract mod min max clamp mix step smoothstep " +
                    "length distance dot cross normalize ftransform faceforward " +
                    "reflect refract matrixCompMult " +
                    "lessThan lessThanEqual greaterThan greaterThanEqual " +
                    "equal notEqual any all not " +
                    "texture1D texture1DProj texture1DLod texture1DProjLod " +
                    "texture2D texture2DProj texture2DLod texture2DProjLod " +
                    "texture3D texture3DProj texture3DLod texture3DProjLod " +
                    "textureCube textureCubeLod " +
                    "shadow1D shadow2D shadow1DProj shadow2DProj " +
                    "shadow1DLod shadow2DLod shadow1DProjLod shadow2DProjLod " +
                    "dFdx dFdy fwidth " +
                    "noise1 noise2 noise3 noise4"),
    atoms: words("true false " +
                "gl_FragColor gl_SecondaryColor gl_Normal gl_Vertex " +
                "gl_MultiTexCoord0 gl_MultiTexCoord1 gl_MultiTexCoord2 gl_MultiTexCoord3 " +
                "gl_MultiTexCoord4 gl_MultiTexCoord5 gl_MultiTexCoord6 gl_MultiTexCoord7 " +
                "gl_FogCoord gl_PointCoord " +
                "gl_Position gl_PointSize gl_ClipVertex " +
                "gl_FrontColor gl_BackColor gl_FrontSecondaryColor gl_BackSecondaryColor " +
                "gl_TexCoord gl_FogFragCoord " +
                "gl_FragCoord gl_FrontFacing " +
                "gl_FragData gl_FragDepth " +
                "gl_ModelViewMatrix gl_ProjectionMatrix gl_ModelViewProjectionMatrix " +
                "gl_TextureMatrix gl_NormalMatrix gl_ModelViewMatrixInverse " +
                "gl_ProjectionMatrixInverse gl_ModelViewProjectionMatrixInverse " +
                "gl_TexureMatrixTranspose gl_ModelViewMatrixInverseTranspose " +
                "gl_ProjectionMatrixInverseTranspose " +
                "gl_ModelViewProjectionMatrixInverseTranspose " +
                "gl_TextureMatrixInverseTranspose " +
                "gl_NormalScale gl_DepthRange gl_ClipPlane " +
                "gl_Point gl_FrontMaterial gl_BackMaterial gl_LightSource gl_LightModel " +
                "gl_FrontLightModelProduct gl_BackLightModelProduct " +
                "gl_TextureColor gl_EyePlaneS gl_EyePlaneT gl_EyePlaneR gl_EyePlaneQ " +
                "gl_FogParameters " +
                "gl_MaxLights gl_MaxClipPlanes gl_MaxTextureUnits gl_MaxTextureCoords " +
                "gl_MaxVertexAttribs gl_MaxVertexUniformComponents gl_MaxVaryingFloats " +
                "gl_MaxVertexTextureImageUnits gl_MaxTextureImageUnits " +
                "gl_MaxFragmentUniformComponents gl_MaxCombineTextureImageUnits " +
                "gl_MaxDrawBuffers"),
    hooks: {"#": cppHook},
    modeProps: {'fold': ["brace", "include"]}
  ));

  def("text/x-nesc", new Config(
    name: "clike",
    keywords: words(cKeywords + "as atomic async call command component components configuration event generic " +
                    "implementation includes interface module new norace nx_struct nx_union post provides " +
                    "signal task uses abstract extends"),
    blockKeywords: words("case do else for if switch while struct"),
    atoms: words("null"),
    hooks: {"#": cppHook},
    modeProps: {'fold': ["brace", "include"]}
  ));

  def("text/x-objectivec", new Config(
    name: "clike",
    keywords: words(cKeywords + "inline restrict _Bool _Complex _Imaginery BOOL Class bycopy byref id IMP in " +
                    "inout nil oneway out Protocol SEL self super atomic nonatomic retain copy readwrite readonly"),
    atoms: words("YES NO NULL NILL ON OFF"),
    hooks: {
      "@": (StringStream stream, ClikeState state) {
        stream.eatWhile(new RegExp(r'[\w\$]'));
        return "keyword";
      },
      "#": cppHook
    },
    modeProps: {'fold': "brace"}
  ));

}

class Context {
  int indented;
  var column;
  String type;
  var align;
  Context prev;

  Context(this.indented, this.column, this.type, this.align, [this.prev]);

  String toString() {
    return "Context($indented, $column, $type, $align, $prev)";
  }
}

class ClikeState extends ModeState {
  int indented;
  Context context;
  Function tokenize;
  bool startOfLine;
  String cpp11RawStringDelim;

  ClikeState({this.indented, this.tokenize, this.context, this.startOfLine});

  ClikeState newInstance() {
    return new ClikeState();
  }

  void copyValues(ClikeState old) {
    indented = old.indented;
    context = old.context;
    tokenize = old.tokenize;
    startOfLine = old.startOfLine;
    cpp11RawStringDelim = old.cpp11RawStringDelim;
  }

  String toString() {
    var tok;
    if (tokenize == tokenAtString) tok = "tokenAtString";
    else if (tokenize == tokenRawString) tok = "tokenRawString";
    else if (tokenize == tokenTripleString) tok = "tokenTripleString";
    else tok = "<method>";
    return "ClikeState($indented, $startOfLine, $tok, $cpp11RawStringDelim, $context)";
  }
}

class Config {
  final String name;
  final Set keywords;
  final Set blockKeywords;
  final Set atoms;
  final Set builtin;
  final Map hooks;
  final Map modeProps;
  final bool multiLineStrings;
  final bool indentStatements;
  final bool dontAlignCalls;
  final int statementIndentUnit;
  String helperType;

  Config({this.name, this.keywords, this.blockKeywords, this.atoms,
    this.hooks, this.modeProps, this.multiLineStrings: false,
    this.indentStatements: true, this.builtin, this.dontAlignCalls: false,
    this.statementIndentUnit});

  dynamic operator [](String val) {
    switch(val) {
      case 'name': return name;
      case 'modeProps': return modeProps;
      case 'helperType': return helperType;
      default: return null;
    }
  }
}
