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
  bool isDefKeyword;

  // Parser configuration
  int indentUnit;
  int statementIndentUnit;
  bool dontAlignCalls;
  Set keywords;
  Set types;
  Set builtin;
  Set blockKeywords;
  Set defKeywords;
  Set atoms;
  Map hooks;
  bool multiLineStrings;
  bool indentStatements;
  bool indentSwitch;
  bool typeFirstDefinitions;

  ClikeMode(var config, var parserConfig) {
    Map emptyMapOr(Map val) => val == null ? {} : val;
    Set emptySetOr(Set val) => val == null ? new Set() : val;
    if (config is Map) config = new Options.from(config);
    if (parserConfig is Map) parserConfig = new Config();
    name = parserConfig.name;
    indentUnit = config.indentUnit;
    statementIndentUnit = parserConfig.statementIndentUnit == null
        ? indentUnit : parserConfig.statementIndentUnit;
    dontAlignCalls = parserConfig.dontAlignCalls;
    keywords = emptySetOr(parserConfig.keywords);
    types = emptySetOr(parserConfig.types);
    builtin = emptySetOr(parserConfig.builtin);
    blockKeywords = emptySetOr(parserConfig.blockKeywords);
    defKeywords = emptySetOr(parserConfig.defKeywords);
    atoms = emptySetOr(parserConfig.atoms);
    hooks = emptyMapOr(parserConfig.hooks);
    multiLineStrings = parserConfig.multiLineStrings;
    indentStatements = parserConfig.indentStatements != false;
    indentSwitch = parserConfig.indentSwitch != false;
    typeFirstDefinitions = parserConfig.typeFirstDefinitions != false;
    this['fold'] = 'brace';
    this['closeBrackets'] = null; // Use defaults w/o customization.
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
      if (defKeywords.contains(cur)) isDefKeyword = true;
      return "keyword";
    }
    if (types.contains(cur)) return "variable-3";
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

  bool isStatement(context) {
    return context.type == "statement" || context.type == "switchstatement";
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

  bool typeBefore(stream, state) {
    if (state.prevToken == "variable" || state.prevToken == "variable-3") return true;
    if (new RegExp(r'/\S[>*\]]\s*$|\*$/').hasMatch(stream.string.substring(0, stream.start))) return true;
    return false;
  }

  ClikeState startState([basecolumn, x]) {
    var ctx = new Context((basecolumn == null ? 0 : basecolumn) - indentUnit,
        0, "top", false);
    return new ClikeState(
      tokenize: null,
      context: ctx,
      indented: 0,
      startOfLine: true,
      prevToken: null
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
    isDefKeyword = false;
    Function tokenizer = state.tokenize == null ? tokenBase : state.tokenize;
    var style = tokenizer(stream, state);
    if (style == "comment" || style == "meta") return style;
    if (ctx.align == null) ctx.align = true;

    if ((curPunc == ";" || curPunc == ":" || curPunc == ",") &&
        isStatement(ctx)) popContext(state);
    else if (curPunc == "{") pushContext(state, stream.column(), "}");
    else if (curPunc == "[") pushContext(state, stream.column(), "]");
    else if (curPunc == "(") pushContext(state, stream.column(), ")");
    else if (curPunc == "}") {
      while (isStatement(ctx)) ctx = popContext(state);
      if (ctx.type == "}") ctx = popContext(state);
      while (isStatement(ctx)) ctx = popContext(state);
    }
    else if (curPunc == ctx.type) popContext(state);
    else if (indentStatements &&
             (((ctx.type == "}" || ctx.type == "top") && curPunc != ';') ||
                 (isStatement(ctx) && curPunc == "newstatement"))) {
      var type = "statement";
      if (curPunc == "newstatement" && indentSwitch && stream.current() == "switch")
        type = "switchstatement";
      pushContext(state, stream.column(), type);
    }

    if (style == "variable" &&
        ((state.prevToken == "def" ||
          (typeFirstDefinitions && typeBefore(stream, state) &&
           stream.match(new RegExp(r'^\s*\('), false) != null))))
      style = "def";

    state.startOfLine = false;
    state.prevToken = isDefKeyword ? "def" : style;
    return style;
  }

  dynamic indent(ClikeState state, String textAfter, x) {
    if (state.tokenize != tokenBase && state.tokenize != null) {
      return Pass;
    }
    var ctx = state.context;
    String firstChar = textAfter == null || textAfter.isEmpty
        ? textAfter : textAfter.substring(0,1);
    if (isStatement(ctx) && firstChar == "}") ctx = ctx.prev;
    bool closing = firstChar == ctx.type;
    bool switchBlock = ctx.prev != null && ctx.prev.type == "switchstatement";
    if (isStatement(ctx)) {
      return ctx.indented + (firstChar == "{" ? 0 : statementIndentUnit);
    } else if (ctx.align != null && ctx.align != false && (!dontAlignCalls || ctx.type != ")")) {
      return ctx.column + (closing ? 0 : 1);
    } else if (ctx.type == ")" && !closing) {
      return ctx.indented + statementIndentUnit;
    } else {
      return ctx.indented + (closing ? 0 : indentUnit) +
          (!closing && switchBlock &&
              !new RegExp(r'^(?:case|default)\b').hasMatch(textAfter)
            ? indentUnit
            : 0);
    }
  }

  String get electricChars => "{}"; // C-like languages have a lot in common...
  RegExp get electricInput => indentSwitch
      ? new RegExp(r'^\s*(?:case .*?:|default:|\{|\})$')
      : new RegExp(r'^\s*[{}]$');
  String get blockCommentStart => "/*";
  String get blockCommentEnd => "*/";
  String get blockCommentContinue => " * ";
  String get lineComment => "//";
  dynamic get fold => this['fold']; // ... but folding does vary a bt.
  dynamic get closeBrackets => this['closeBrackets'];

  bool get hasIndent => true;
  bool get hasStartState => true;
  bool get hasElectricChars => true;
  bool get hasElectricInput => true;
}

Set words(String str) {
  var words = str.split(" ");
  return new Set.from(words);
}

var cKeywords = "auto if break case register continue return default do sizeof " +
  "static else struct switch extern typedef float union for " +
  "goto while enum const volatile true false";
var cTypes = "int long char short double float unsigned signed void size_t ptrdiff_t";

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

dynamic pointerHook(_stream, state) {
  if (state.prevToken == "variable-3") return "variable-3";
  return false;
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
    escaped = stream.next() == "\\" && !escaped;
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
  add(mode.types);
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
    types: words(cTypes + " bool _Complex _Bool float_t double_t intptr_t intmax_t " +
                 "int8_t int16_t int32_t int64_t uintptr_t uintmax_t uint8_t uint16_t " +
                 "uint32_t uint64_t"),
    blockKeywords: words("case do else for if switch while struct"),
    defKeywords: words("struct"),
    typeFirstDefinitions: true,
    atoms: words("null"),
    hooks: {"#": cppHook, "*": pointerHook},
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
    types: words(cTypes + "bool wchar_t"),
    blockKeywords:
        words("catch class do else finally for if struct switch try while"),
    defKeywords: words("class namespace struct enum union"),
    typeFirstDefinitions: true,
    atoms: words("true false null"),
    hooks: {
      "#": cppHook,
      "*": pointerHook,
      "u": cpp11StringHook,
      "U": cpp11StringHook,
      "L": cpp11StringHook,
      "R": cpp11StringHook
    },
    modeProps: {'fold': ["brace", "include"]}
  ));

  def("text/x-java", new Config(
    name: "clike",
    keywords: words("abstract assert break case catch class const continue default " +
                    "do else enum extends final finally float for goto if implements import " +
                    "instanceof interface native new package private protected public " +
                    "return static strictfp super switch synchronized this throw throws transient " +
                    "try volatile while"),
    types: words("byte short int long float double boolean char void Boolean Byte Character Double Float " +
                 "Integer Long Number Object Short String StringBuffer StringBuilder Void"),
    blockKeywords: words("catch class do else finally for if switch try while"),
    defKeywords: words("class interface package enum"),
    typeFirstDefinitions: true,
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
    keywords: words("abstract as async await base break case catch checked class const continue" +
                    " default delegate do else enum event explicit extern finally fixed for" +
                    " foreach goto if implicit in interface internal is lock namespace new" +
                    " operator out override params private protected public readonly ref return sealed" +
                    " sizeof stackalloc static struct switch this throw try typeof unchecked" +
                    " unsafe using virtual void volatile while add alias ascending descending dynamic from get" +
                    " global group into join let orderby partial remove select set value var yield"),
    types: words("Action Boolean Byte Char DateTime DateTimeOffset Decimal Double Func" +
                 " Guid Int16 Int32 Int64 Object SByte Single String Task TimeSpan UInt16 UInt32" +
                 " UInt64 bool byte char decimal double short int long object"  +
                 " sbyte float string ushort uint ulong"),
    blockKeywords: words("catch class do else finally for foreach if struct switch try while"),
    defKeywords: words("class interface namespace struct var"),
    typeFirstDefinitions: true,
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
      name: 'clike',
      keywords: words(

        /* scala */
        "abstract case catch class def do else extends false final finally for forSome if " +
        "implicit import lazy match new null object override package private protected return " +
        "sealed super this throw trait try type val var while with yield _ : = => <- <: " +
        "<% >: # @ " +

        /* package scala */
        "assert assume require print println printf readLine readBoolean readByte readShort " +
        "readChar readInt readLong readFloat readDouble " +

        ":: #:: "
      ),
      types: words(
        "AnyVal App Application Array BufferedIterator BigDecimal BigInt Char Console Either " +
        "Enumeration Equiv Error Exception Fractional Function IndexedSeq Integral Iterable " +
        "Iterator List Map Numeric Nil NotNull Option Ordered Ordering PartialFunction PartialOrdering " +
        "Product Proxy Range Responder Seq Serializable Set Specializable Stream StringBuilder " +
        "StringContext Symbol Throwable Traversable TraversableOnce Tuple Unit Vector " +

        /* package java.lang */
        "Boolean Byte Character CharSequence Class ClassLoader Cloneable Comparable " +
        "Compiler Double Exception Float Integer Long Math Number Object Package Pair Process " +
        "Runtime Runnable SecurityManager Short StackTraceElement StrictMath String " +
        "StringBuffer System Thread ThreadGroup ThreadLocal Throwable Triple Void"
      ),
      multiLineStrings: true,
      blockKeywords: words("catch class do else finally for forSome if match switch try while"),
      defKeywords: words("class def object package trait type val var"),
      atoms: words("true false null"),
      indentStatements: false,
      indentSwitch: false,
    hooks: {
      "@": (StringStream stream, ClikeState state) {
        stream.eatWhile(new RegExp(r'[\w\$_]'));
        return "meta";
      },
      '"': (StringStream stream, ClikeState state) {
        if (!stream.match('""')) return false;
        state.tokenize = tokenTripleString;
        return state.tokenize(stream, state);
      },
      "'": (StringStream stream, ClikeState state) {
        stream.eatWhile(new RegExp(r'[\w\$_\xa1-\uffff]'));
        return "atom";
      }
    },
    modeProps: {'closeBrackets': {'triples': '"'}}
  ));

  def(["x-shader/x-vertex", "x-shader/x-fragment"], new Config(
    name: "clike",
    keywords: words("sampler1D sampler2D sampler3D samplerCube " +
                    "sampler1DShadow sampler2DShadow " +
                    "const attribute uniform varying " +
                    "break continue discard return " +
                    "for while do if else struct " +
                    "in out inout"),
    types: words("float int bool void " +
                 "vec2 vec3 vec4 ivec2 ivec3 ivec4 bvec2 bvec3 bvec4 " +
                 "mat2 mat3 mat4"),
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
    indentSwitch: false,
    hooks: {"#": cppHook},
    modeProps: {'fold': ["brace", "include"]}
  ));

  def("text/x-nesc", new Config(
    name: "clike",
    keywords: words(cKeywords + "as atomic async call command component components configuration event generic " +
                    "implementation includes interface module new norace nx_struct nx_union post provides " +
                    "signal task uses abstract extends"),
    types: words(cTypes),
    blockKeywords: words("case do else for if switch while struct"),
    atoms: words("null"),
    hooks: {"#": cppHook},
    modeProps: {'fold': ["brace", "include"]}
  ));

  def("text/x-objectivec", new Config(
    name: "clike",
    keywords: words(cKeywords + "inline restrict _Bool _Complex _Imaginery BOOL Class bycopy byref id IMP in " +
                    "inout nil oneway out Protocol SEL self super atomic nonatomic retain copy readwrite readonly"),
                    types: words(cTypes),
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
  String prevToken;

  ClikeState({this.indented, this.tokenize, this.context, this.startOfLine, this.prevToken});

  ClikeState newInstance() {
    return new ClikeState();
  }

  void copyValues(ClikeState old) {
    indented = old.indented;
    context = old.context;
    tokenize = old.tokenize;
    startOfLine = old.startOfLine;
    cpp11RawStringDelim = old.cpp11RawStringDelim;
    prevToken = old.prevToken;
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
  final Set types;
  final Set blockKeywords;
  final Set defKeywords;
  final Set atoms;
  final Set builtin;
  final Map hooks;
  final Map modeProps;
  final bool multiLineStrings;
  final bool indentStatements;
  final bool indentSwitch;
  final bool dontAlignCalls;
  final bool typeFirstDefinitions;
  final int statementIndentUnit;
  String helperType;

  Config({this.name, this.keywords, this.types, this.blockKeywords, this.atoms,
    this.defKeywords, this.hooks, this.modeProps, this.multiLineStrings: false,
    this.indentStatements: true, this.builtin, this.dontAlignCalls: false,
    this.indentSwitch: true, this.statementIndentUnit,
    this.typeFirstDefinitions: false});

  dynamic operator [](String val) {
    switch(val) {
      case 'name': return name;
      case 'modeProps': return modeProps;
      case 'helperType': return helperType;
      default: return null;
    }
  }
}
