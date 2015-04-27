// Copyright (c) 2015, the Comid Authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library comid.mode.css;

import 'package:comid/codemirror.dart';

class CssMode extends Mode {

  static initialize() {
    _initialize();
  }

  int indentUnit;
  var tokenHooks;
  var documentTypes;
  var mediaTypes;
  var mediaFeatures;
  var propertyKeywords;
  var nonStandardPropertyKeywords;
  var fontProperties;
  var counterDescriptors;
  var colorKeywords;
  var valueKeywords;
  bool allowNested;

  var type, override;
  Map states;

  CssMode(var options, var parserConfig) {
//    if (!parserConfig.propertyKeywords) parserConfig = CodeMirror.resolveMode("text/css");

    if (options is Map) options = new Options.from(options);
    if (parserConfig is Map) parserConfig = new Config();
    indentUnit = options.indentUnit;
    tokenHooks = parserConfig.tokenHooks;
    documentTypes = parserConfig.documentTypes;
    mediaTypes = parserConfig.mediaTypes;
    mediaFeatures = parserConfig.mediaFeatures;
    propertyKeywords = parserConfig.propertyKeywords;
    nonStandardPropertyKeywords = parserConfig.nonStandardPropertyKeywords;
    fontProperties = parserConfig.fontProperties;
    counterDescriptors = parserConfig.counterDescriptors;
    colorKeywords = parserConfig.colorKeywords;
    valueKeywords = parserConfig.valueKeywords;
    allowNested = parserConfig.allowNested;
    name = parserConfig.name;
    helperType = parserConfig.helperType;
    states = {};
    states['top'] = top;
    states['block'] = block;
    states['maybeprop'] = maybeprop;
    states['prop'] = prop;
    states['propBlock'] = propBlock;
    states['parens'] = parens;
    states['pseudo'] = pseudo;
    states['atBlock'] = atBlock;
    states['atBlock_parens'] = atBlock_parens;
    states['restricted_atBlock_before'] = restricted_atBlock_before;
    states['restricted_atBlock'] = restricted_atBlock;
    states['keyframes'] = keyframes;
    states['at'] = at;
    states['interpolation'] = interpolation;
  }

  ret(style, tp) { type = tp; return style; }

// Tokenizers

  tokenBase(StringStream stream, CssState state) {
    var ch = stream.next();
    if (tokenHooks != null && tokenHooks[ch] != null) {
      var result = tokenHooks[ch](stream, state);
      if (result != false) return result;
    }
    if (ch == "@") {
      stream.eatWhile(new RegExp(r'[\w\\\-]'));
      return ret("def", stream.current());
    } else if (ch == "=" || (ch == "~" || ch == "|") && stream.eat("=") != null) {
      return ret(null, "compare");
    } else if (ch == "\"" || ch == "'") {
      state.tokenize = tokenString(ch);
      return state.tokenize(stream, state);
    } else if (ch == "#") {
      stream.eatWhile(new RegExp(r'[\w\\\-]'));
      return ret("atom", "hash");
    } else if (ch == "!") {
      stream.match(new RegExp(r'^\s*\w*'));
      return ret("keyword", "important");
    } else if (new RegExp(r'\d').hasMatch(ch) || ch == "." && stream.eat(new RegExp(r'\d')) != null) {
      stream.eatWhile(new RegExp(r'[\w.%]'));
      return ret("number", "unit");
    } else if (ch == "-") {
      if (new RegExp(r'[\d.]').hasMatch(stream.peek())) {
        stream.eatWhile(new RegExp(r'[\w.%]'));
        return ret("number", "unit");
      } else if (stream.match(new RegExp(r'^-[\w\\\-]+')) != null) {
        stream.eatWhile(new RegExp(r'[\w\\\-]'));
        if (stream.match(new RegExp(r'^\s*:'), false) != null) {
          return ret("variable-2", "variable-definition");
        }
        return ret("variable-2", "variable");
      } else if (stream.match(new RegExp(r'^\w+-')) != null) {
        return ret("meta", "meta");
      }
    } else if (new RegExp(r'[,+>*\/]').hasMatch(ch)) {
      return ret(null, "select-op");
    } else if (ch == "." &&
        stream.match(new RegExp(r'^-?[_a-z][_a-z0-9-]*', caseSensitive: false)) != null) {
      return ret("qualifier", "qualifier");
    } else if (new RegExp(r'[:;{}\[\]\(\)]').hasMatch(ch)) {
      return ret(null, ch);
    } else if (ch == "u" && stream.match(new RegExp(r"rl(-prefix)?\(")) != null ||
              (ch == "d" && stream.match("omain(") != null) ||
              (ch == "r" && stream.match("egexp(") != null)) {
      stream.backUp(1);
      state.tokenize = tokenParenthesized;
      return ret("property", "word");
    } else if (new RegExp(r'[\w\\\-]').hasMatch(ch)) {
      stream.eatWhile(new RegExp(r'[\w\\\-]'));
      return ret("property", "word");
    } else {
      return ret(null, null);
    }
  }

  tokenString(String quote) {
    return (StringStream stream, CssState state) {
      var escaped = false, ch;
      while ((ch = stream.next()) != null) {
        if (ch == quote && !escaped) {
          if (quote == ")") stream.backUp(1);
          break;
        }
        escaped = !escaped && ch == "\\";
      }
      if (ch == quote || !escaped && quote != ")") state.tokenize = null;
      return ret("string", "string");
    };
  }

  tokenParenthesized(StringStream stream, CssState state) {
    stream.next(); // Must be '('
    if (stream.match(new RegExp('\s*[\"\')]'), false) == null)
      state.tokenize = tokenString(")");
    else
      state.tokenize = null;
    return ret(null, "(");
  }

  startState([int base, x]) {
    return new CssState(
        tokenize: null,
        state: "top",
        stateArg: null,
        context: new Context("top", base, null));
  }

  token(StringStream stream, [CssState state]) {
    if (state.tokenize == null && stream.eatSpace()) return null;
    var style = (state.tokenize == null ? tokenBase : state.tokenize)(stream, state);
    if (style != null && style is List) {
      type = style[1];
      style = style[0];
    }
    override = style;
    state.state = states[state.state](type, stream, state);
    return override;
  }

  indent(CssState state, String textAfter, x) {
    Context cx = state.context;
    String ch = textAfter == null || textAfter.isEmpty ? null : textAfter.substring(0,1);
    var indent = cx.indent;
    if (cx.type == "prop" && (ch == "}" || ch == ")")) cx = cx.prev;
    if (cx.prev != null &&
        (ch == "}" && (cx.type == "block" || cx.type == "top" || cx.type == "interpolation" || cx.type == "restricted_atBlock") ||
         ch == ")" && (cx.type == "parens" || cx.type == "atBlock_parens") ||
         ch == "{" && (cx.type == "at" || cx.type == "atBlock"))) {
      indent = cx.indent - indentUnit;
      cx = cx.prev;
    }
    return indent;
  }

  String get electricChars => "}";
  String get blockCommentStart => "/*";
  String get blockCommentEnd => "*/";
  String get blockCommentContinue => " * ";
  dynamic get fold => "brace";

  bool get hasIndent => true;
  bool get hasStartState => true;
  bool get hasElectricChars => true;

  // Context management

  pushContext(CssState state, StringStream stream, String type) {
    state.context = new Context(type, stream.indentation() + indentUnit, state.context);
    return type;
  }

  popContext(CssState state) {
    state.context = state.context.prev;
    return state.context.type;
  }

  pass(type, StringStream stream, CssState state) {
    return states[state.context.type](type, stream, state);
  }

  popAndPass(type, StringStream stream, CssState state, [int n = 1]) {
    for (var i = n; i > 0; i--)
      state.context = state.context.prev;
    return pass(type, stream, state);
  }

  // Parser

  wordAsValue(StringStream stream) {
    var word = stream.current().toLowerCase();
    if (valueKeywords != null && valueKeywords.containsKey(word))
      override = "atom";
    else if (colorKeywords != null && colorKeywords.containsKey(word))
      override = "keyword";
    else
      override = "variable";
  }

  top(String type, StringStream stream, CssState state) {
    if (type == null) {
      return state.context.type;
    } else if (type == "{") {
      return pushContext(state, stream, "block");
    } else if (type == "}" && state.context.prev != null) {
      return popContext(state);
    } else if (new RegExp(r'@(media|supports|(-moz-)?document)').hasMatch(type)) {
      return pushContext(state, stream, "atBlock");
    } else if (new RegExp(r'@(font-face|counter-style)').hasMatch(type)) {
      state.stateArg = type;
      return "restricted_atBlock_before";
    } else if (new RegExp(r'^@(-(moz|ms|o|webkit)-)?keyframes$').hasMatch(type)) {
      return "keyframes";
    } else if (type.substring(0,1) == "@") {
      return pushContext(state, stream, "at");
    } else if (type == "hash") {
      override = "builtin";
    } else if (type == "word") {
      override = "tag";
    } else if (type == "variable-definition") {
      return "maybeprop";
    } else if (type == "interpolation") {
      return pushContext(state, stream, "interpolation");
    } else if (type == ":") {
      return "pseudo";
    } else if (allowNested && type == "(") {
      return pushContext(state, stream, "parens");
    }
    return state.context.type;
  }

  block(String type, StringStream stream, CssState state) {
    if (type == "word") {
      var word = stream.current().toLowerCase();
      if (propertyKeywords != null && propertyKeywords.containsKey(word)) {
        override = "property";
        return "maybeprop";
      } else if (nonStandardPropertyKeywords != null && nonStandardPropertyKeywords.containsKey(word)) {
        override = "string-2";
        return "maybeprop";
      } else if (allowNested) {
        override = stream.match(new RegExp(r'^\s*:(?:\s|$)'), false) != null
            ? "property" : "tag";
        return "block";
      } else {
        override += " error";
        return "maybeprop";
      }
    } else if (type == "meta") {
      return "block";
    } else if (!allowNested && (type == "hash" || type == "qualifier")) {
      override = "error";
      return "block";
    } else {
      return states['top'](type, stream, state);
    }
  }

  maybeprop(String type, StringStream stream, CssState state) {
    if (type == ":") return pushContext(state, stream, "prop");
    return pass(type, stream, state);
  }

  prop(String type, StringStream stream, CssState state) {
    if (type == ";") return popContext(state);
    if (type == "{" && allowNested) return pushContext(state, stream, "propBlock");
    if (type == "}" || type == "{") return popAndPass(type, stream, state);
    if (type == "(") return pushContext(state, stream, "parens");

    if (type == "hash" && !new RegExp(r'^#([0-9a-fA-f]{3}|[0-9a-fA-f]{6})$').hasMatch(stream.current())) {
      override += " error";
    } else if (type == "word") {
      wordAsValue(stream);
    } else if (type == "interpolation") {
      return pushContext(state, stream, "interpolation");
    }
    return "prop";
  }

  propBlock(String type, StringStream stream, CssState state) {
    if (type == "}") return popContext(state);
    if (type == "word") { override = "property"; return "maybeprop"; }
    return state.context.type;
  }

  parens(String type, StringStream stream, CssState state) {
    if (type == "{" || type == "}") return popAndPass(type, stream, state);
    if (type == ")") return popContext(state);
    if (type == "(") return pushContext(state, stream, "parens");
    if (type == "interpolation") return pushContext(state, stream, "interpolation");
    if (type == "word") wordAsValue(stream);
    return "parens";
  }

  pseudo(String type, StringStream stream, CssState state) {
    if (type == "word") {
      override = "variable-3";
      return state.context.type;
    }
    return pass(type, stream, state);
  }

  atBlock(String type, StringStream stream, CssState state) {
    if (type == "(") return pushContext(state, stream, "atBlock_parens");
    if (type == "}") return popAndPass(type, stream, state);
    if (type == "{") {
      var val = popContext(state);
      if (val != null) {
        val = pushContext(state, stream, allowNested ? "block" : "top");
      }
      return val;
    }

    if (type == "word") {
      var word = stream.current().toLowerCase();
      if (word == "only" || word == "not" || word == "and" || word == "or")
        override = "keyword";
      else if (documentTypes != null && documentTypes.containsKey(word))
        override = "tag";
      else if (mediaTypes != null && mediaTypes.containsKey(word))
        override = "attribute";
      else if (mediaFeatures != null && mediaFeatures.containsKey(word))
        override = "property";
      else if (propertyKeywords != null && propertyKeywords.containsKey(word))
        override = "property";
      else if (nonStandardPropertyKeywords != null && nonStandardPropertyKeywords.containsKey(word))
        override = "string-2";
      else if (valueKeywords != null && valueKeywords.containsKey(word))
        override = "atom";
      else
        override = "error";
    }
    return state.context.type;
  }

  atBlock_parens(String type, StringStream stream, CssState state) {
    if (type == ")") return popContext(state);
    if (type == "{" || type == "}") return popAndPass(type, stream, state, 2);
    return states['atBlock'](type, stream, state);
  }

  restricted_atBlock_before(type, StringStream stream, state) {
    if (type == "{")
      return pushContext(state, stream, "restricted_atBlock");
    if (type == "word" && state.stateArg == "@counter-style") {
      override = "variable";
      return "restricted_atBlock_before";
    }
    return pass(type, stream, state);
  }

  restricted_atBlock(String type, StringStream stream, CssState state) {
    if (type == "}") {
      state.stateArg = null;
      return popContext(state);
    }
    if (type == "word") {
      String word = stream.current().toLowerCase();
      if ((state.stateArg == "@font-face" && (fontProperties == null || !fontProperties.containsKey(word))) ||
          (state.stateArg == "@counter-style" && (counterDescriptors == null || !counterDescriptors.containsKey(word))))
        override = "error";
      else
        override = "property";
      return "maybeprop";
    }
    return "restricted_atBlock";
  }

  keyframes(String type, StringStream stream, CssState state) {
    if (type == "word") { override = "variable"; return "keyframes"; }
    if (type == "{") return pushContext(state, stream, "top");
    return pass(type, stream, state);
  }

  at(String type, StringStream stream, CssState state) {
    if (type == ";") return popContext(state);
    if (type == "{" || type == "}") return popAndPass(type, stream, state);
    if (type == "word") override = "tag";
    else if (type == "hash") override = "builtin";
    return "at";
  }

  interpolation(String type, StringStream stream, CssState state) {
    if (type == "}") return popContext(state);
    if (type == "{" || type == ";") return popAndPass(type, stream, state);
    if (type != "variable") override = "error";
    return "interpolation";
  }
}

class CssState extends ModeState {
  Function tokenize;
  String state;
  String stateArg;
  Context context;

  CssState({this.context, this.tokenize, this.state, this.stateArg});

  CssState newInstance() {
    return new CssState();
  }

  void copyValues(CssState old) {
    context = old.context;
    state = old.state;
    tokenize = old.tokenize;
    stateArg = old.stateArg;
  }

  String toString() {
    var tok;
    if (tokenize == tokenCComment) tok = "tokenCComment";
    else if (tokenize == tokenSGMLComment) tok = "tokenSGMLComment";
    else tok = "<method>";
    return "CssState($state, $tok, $stateArg, $context)";
  }
}

class Context {
  String type;
  int indent;
  Context prev;

  Context(this.type, this.indent, this.prev) {
    if (this.indent == null) this.indent = 0;
  }

  String toString() {
    return "Context($type, $indent, $prev)";
  }
}

bool _initialized = false;
_initialize() {
  if (_initialized) return;
  _initialized = true;

  var documentTypes_ = [
    "domain", "regexp", "url", "url-prefix"
  ], documentTypes = keySet(documentTypes_);

  var mediaTypes_ = [
    "all", "aural", "braille", "handheld", "print", "projection", "screen",
    "tty", "tv", "embossed"
  ], mediaTypes = keySet(mediaTypes_);

  var mediaFeatures_ = [
    "width", "min-width", "max-width", "height", "min-height", "max-height",
    "device-width", "min-device-width", "max-device-width", "device-height",
    "min-device-height", "max-device-height", "aspect-ratio",
    "min-aspect-ratio", "max-aspect-ratio", "device-aspect-ratio",
    "min-device-aspect-ratio", "max-device-aspect-ratio", "color", "min-color",
    "max-color", "color-index", "min-color-index", "max-color-index",
    "monochrome", "min-monochrome", "max-monochrome", "resolution",
    "min-resolution", "max-resolution", "scan", "grid"
  ], mediaFeatures = keySet(mediaFeatures_);

  var propertyKeywords_ = [
    "align-content", "align-items", "align-self", "alignment-adjust",
    "alignment-baseline", "anchor-point", "animation", "animation-delay",
    "animation-direction", "animation-duration", "animation-fill-mode",
    "animation-iteration-count", "animation-name", "animation-play-state",
    "animation-timing-function", "appearance", "azimuth", "backface-visibility",
    "background", "background-attachment", "background-clip", "background-color",
    "background-image", "background-origin", "background-position",
    "background-repeat", "background-size", "baseline-shift", "binding",
    "bleed", "bookmark-label", "bookmark-level", "bookmark-state",
    "bookmark-target", "border", "border-bottom", "border-bottom-color",
    "border-bottom-left-radius", "border-bottom-right-radius",
    "border-bottom-style", "border-bottom-width", "border-collapse",
    "border-color", "border-image", "border-image-outset",
    "border-image-repeat", "border-image-slice", "border-image-source",
    "border-image-width", "border-left", "border-left-color",
    "border-left-style", "border-left-width", "border-radius", "border-right",
    "border-right-color", "border-right-style", "border-right-width",
    "border-spacing", "border-style", "border-top", "border-top-color",
    "border-top-left-radius", "border-top-right-radius", "border-top-style",
    "border-top-width", "border-width", "bottom", "box-decoration-break",
    "box-shadow", "box-sizing", "break-after", "break-before", "break-inside",
    "caption-side", "clear", "clip", "color", "color-profile", "column-count",
    "column-fill", "column-gap", "column-rule", "column-rule-color",
    "column-rule-style", "column-rule-width", "column-span", "column-width",
    "columns", "content", "counter-increment", "counter-reset", "crop", "cue",
    "cue-after", "cue-before", "cursor", "direction", "display",
    "dominant-baseline", "drop-initial-after-adjust",
    "drop-initial-after-align", "drop-initial-before-adjust",
    "drop-initial-before-align", "drop-initial-size", "drop-initial-value",
    "elevation", "empty-cells", "fit", "fit-position", "flex", "flex-basis",
    "flex-direction", "flex-flow", "flex-grow", "flex-shrink", "flex-wrap",
    "float", "float-offset", "flow-from", "flow-into", "font", "font-feature-settings",
    "font-family", "font-kerning", "font-language-override", "font-size", "font-size-adjust",
    "font-stretch", "font-style", "font-synthesis", "font-variant",
    "font-variant-alternates", "font-variant-caps", "font-variant-east-asian",
    "font-variant-ligatures", "font-variant-numeric", "font-variant-position",
    "font-weight", "grid", "grid-area", "grid-auto-columns", "grid-auto-flow",
    "grid-auto-position", "grid-auto-rows", "grid-column", "grid-column-end",
    "grid-column-start", "grid-row", "grid-row-end", "grid-row-start",
    "grid-template", "grid-template-areas", "grid-template-columns",
    "grid-template-rows", "hanging-punctuation", "height", "hyphens",
    "icon", "image-orientation", "image-rendering", "image-resolution",
    "inline-box-align", "justify-content", "left", "letter-spacing",
    "line-break", "line-height", "line-stacking", "line-stacking-ruby",
    "line-stacking-shift", "line-stacking-strategy", "list-style",
    "list-style-image", "list-style-position", "list-style-type", "margin",
    "margin-bottom", "margin-left", "margin-right", "margin-top",
    "marker-offset", "marks", "marquee-direction", "marquee-loop",
    "marquee-play-count", "marquee-speed", "marquee-style", "max-height",
    "max-width", "min-height", "min-width", "move-to", "nav-down", "nav-index",
    "nav-left", "nav-right", "nav-up", "object-fit", "object-position",
    "opacity", "order", "orphans", "outline",
    "outline-color", "outline-offset", "outline-style", "outline-width",
    "overflow", "overflow-style", "overflow-wrap", "overflow-x", "overflow-y",
    "padding", "padding-bottom", "padding-left", "padding-right", "padding-top",
    "page", "page-break-after", "page-break-before", "page-break-inside",
    "page-policy", "pause", "pause-after", "pause-before", "perspective",
    "perspective-origin", "pitch", "pitch-range", "play-during", "position",
    "presentation-level", "punctuation-trim", "quotes", "region-break-after",
    "region-break-before", "region-break-inside", "region-fragment",
    "rendering-intent", "resize", "rest", "rest-after", "rest-before", "richness",
    "right", "rotation", "rotation-point", "ruby-align", "ruby-overhang",
    "ruby-position", "ruby-span", "shape-image-threshold", "shape-inside", "shape-margin",
    "shape-outside", "size", "speak", "speak-as", "speak-header",
    "speak-numeral", "speak-punctuation", "speech-rate", "stress", "string-set",
    "tab-size", "table-layout", "target", "target-name", "target-new",
    "target-position", "text-align", "text-align-last", "text-decoration",
    "text-decoration-color", "text-decoration-line", "text-decoration-skip",
    "text-decoration-style", "text-emphasis", "text-emphasis-color",
    "text-emphasis-position", "text-emphasis-style", "text-height",
    "text-indent", "text-justify", "text-outline", "text-overflow", "text-shadow",
    "text-size-adjust", "text-space-collapse", "text-transform", "text-underline-position",
    "text-wrap", "top", "transform", "transform-origin", "transform-style",
    "transition", "transition-delay", "transition-duration",
    "transition-property", "transition-timing-function", "unicode-bidi",
    "vertical-align", "visibility", "voice-balance", "voice-duration",
    "voice-family", "voice-pitch", "voice-range", "voice-rate", "voice-stress",
    "voice-volume", "volume", "white-space", "widows", "width", "word-break",
    "word-spacing", "word-wrap", "z-index",
    // SVG-specific
    "clip-path", "clip-rule", "mask", "enable-background", "filter", "flood-color",
    "flood-opacity", "lighting-color", "stop-color", "stop-opacity", "pointer-events",
    "color-interpolation", "color-interpolation-filters",
    "color-rendering", "fill", "fill-opacity", "fill-rule", "image-rendering",
    "marker", "marker-end", "marker-mid", "marker-start", "shape-rendering", "stroke",
    "stroke-dasharray", "stroke-dashoffset", "stroke-linecap", "stroke-linejoin",
    "stroke-miterlimit", "stroke-opacity", "stroke-width", "text-rendering",
    "baseline-shift", "dominant-baseline", "glyph-orientation-horizontal",
    "glyph-orientation-vertical", "text-anchor", "writing-mode"
  ], propertyKeywords = keySet(propertyKeywords_);

  var nonStandardPropertyKeywords_ = [
    "scrollbar-arrow-color", "scrollbar-base-color", "scrollbar-dark-shadow-color",
    "scrollbar-face-color", "scrollbar-highlight-color", "scrollbar-shadow-color",
    "scrollbar-3d-light-color", "scrollbar-track-color", "shape-inside",
    "searchfield-cancel-button", "searchfield-decoration", "searchfield-results-button",
    "searchfield-results-decoration", "zoom"
  ], nonStandardPropertyKeywords = keySet(nonStandardPropertyKeywords_);

  var fontProperties_ = [
    "font-family", "src", "unicode-range", "font-variant", "font-feature-settings",
    "font-stretch", "font-weight", "font-style"
  ], fontProperties = keySet(fontProperties_);

  var counterDescriptors_ = [
    "additive-symbols", "fallback", "negative", "pad", "prefix", "range",
    "speak-as", "suffix", "symbols", "system"
  ], counterDescriptors = keySet(counterDescriptors_);

  var colorKeywords_ = [
    "aliceblue", "antiquewhite", "aqua", "aquamarine", "azure", "beige",
    "bisque", "black", "blanchedalmond", "blue", "blueviolet", "brown",
    "burlywood", "cadetblue", "chartreuse", "chocolate", "coral", "cornflowerblue",
    "cornsilk", "crimson", "cyan", "darkblue", "darkcyan", "darkgoldenrod",
    "darkgray", "darkgreen", "darkkhaki", "darkmagenta", "darkolivegreen",
    "darkorange", "darkorchid", "darkred", "darksalmon", "darkseagreen",
    "darkslateblue", "darkslategray", "darkturquoise", "darkviolet",
    "deeppink", "deepskyblue", "dimgray", "dodgerblue", "firebrick",
    "floralwhite", "forestgreen", "fuchsia", "gainsboro", "ghostwhite",
    "gold", "goldenrod", "gray", "grey", "green", "greenyellow", "honeydew",
    "hotpink", "indianred", "indigo", "ivory", "khaki", "lavender",
    "lavenderblush", "lawngreen", "lemonchiffon", "lightblue", "lightcoral",
    "lightcyan", "lightgoldenrodyellow", "lightgray", "lightgreen", "lightpink",
    "lightsalmon", "lightseagreen", "lightskyblue", "lightslategray",
    "lightsteelblue", "lightyellow", "lime", "limegreen", "linen", "magenta",
    "maroon", "mediumaquamarine", "mediumblue", "mediumorchid", "mediumpurple",
    "mediumseagreen", "mediumslateblue", "mediumspringgreen", "mediumturquoise",
    "mediumvioletred", "midnightblue", "mintcream", "mistyrose", "moccasin",
    "navajowhite", "navy", "oldlace", "olive", "olivedrab", "orange", "orangered",
    "orchid", "palegoldenrod", "palegreen", "paleturquoise", "palevioletred",
    "papayawhip", "peachpuff", "peru", "pink", "plum", "powderblue",
    "purple", "rebeccapurple", "red", "rosybrown", "royalblue", "saddlebrown",
    "salmon", "sandybrown", "seagreen", "seashell", "sienna", "silver", "skyblue",
    "slateblue", "slategray", "snow", "springgreen", "steelblue", "tan",
    "teal", "thistle", "tomato", "turquoise", "violet", "wheat", "white",
    "whitesmoke", "yellow", "yellowgreen"
  ], colorKeywords = keySet(colorKeywords_);

  var valueKeywords_ = [
    "above", "absolute", "activeborder", "additive", "activecaption", "afar",
    "after-white-space", "ahead", "alias", "all", "all-scroll", "alphabetic", "alternate",
    "always", "amharic", "amharic-abegede", "antialiased", "appworkspace",
    "arabic-indic", "armenian", "asterisks", "attr", "auto", "avoid", "avoid-column", "avoid-page",
    "avoid-region", "background", "backwards", "baseline", "below", "bidi-override", "binary",
    "bengali", "blink", "block", "block-axis", "bold", "bolder", "border", "border-box",
    "both", "bottom", "break", "break-all", "break-word", "bullets", "button", "button-bevel",
    "buttonface", "buttonhighlight", "buttonshadow", "buttontext", "calc", "cambodian",
    "capitalize", "caps-lock-indicator", "caption", "captiontext", "caret",
    "cell", "center", "checkbox", "circle", "cjk-decimal", "cjk-earthly-branch",
    "cjk-heavenly-stem", "cjk-ideographic", "clear", "clip", "close-quote",
    "col-resize", "collapse", "column", "compact", "condensed", "contain", "content",
    "content-box", "context-menu", "continuous", "copy", "counter", "counters", "cover", "crop",
    "cross", "crosshair", "currentcolor", "cursive", "cyclic", "dashed", "decimal",
    "decimal-leading-zero", "default", "default-button", "destination-atop",
    "destination-in", "destination-out", "destination-over", "devanagari",
    "disc", "discard", "disclosure-closed", "disclosure-open", "document",
    "dot-dash", "dot-dot-dash",
    "dotted", "double", "down", "e-resize", "ease", "ease-in", "ease-in-out", "ease-out",
    "element", "ellipse", "ellipsis", "embed", "end", "ethiopic", "ethiopic-abegede",
    "ethiopic-abegede-am-et", "ethiopic-abegede-gez", "ethiopic-abegede-ti-er",
    "ethiopic-abegede-ti-et", "ethiopic-halehame-aa-er",
    "ethiopic-halehame-aa-et", "ethiopic-halehame-am-et",
    "ethiopic-halehame-gez", "ethiopic-halehame-om-et",
    "ethiopic-halehame-sid-et", "ethiopic-halehame-so-et",
    "ethiopic-halehame-ti-er", "ethiopic-halehame-ti-et", "ethiopic-halehame-tig",
    "ethiopic-numeric", "ew-resize", "expanded", "extends", "extra-condensed",
    "extra-expanded", "fantasy", "fast", "fill", "fixed", "flat", "flex", "footnotes",
    "forwards", "from", "geometricPrecision", "georgian", "graytext", "groove",
    "gujarati", "gurmukhi", "hand", "hangul", "hangul-consonant", "hebrew",
    "help", "hidden", "hide", "higher", "highlight", "highlighttext",
    "hiragana", "hiragana-iroha", "horizontal", "hsl", "hsla", "icon", "ignore",
    "inactiveborder", "inactivecaption", "inactivecaptiontext", "infinite",
    "infobackground", "infotext", "inherit", "initial", "inline", "inline-axis",
    "inline-block", "inline-flex", "inline-table", "inset", "inside", "intrinsic", "invert",
    "italic", "japanese-formal", "japanese-informal", "justify", "kannada",
    "katakana", "katakana-iroha", "keep-all", "khmer",
    "korean-hangul-formal", "korean-hanja-formal", "korean-hanja-informal",
    "landscape", "lao", "large", "larger", "left", "level", "lighter",
    "line-through", "linear", "linear-gradient", "lines", "list-item", "listbox", "listitem",
    "local", "logical", "loud", "lower", "lower-alpha", "lower-armenian",
    "lower-greek", "lower-hexadecimal", "lower-latin", "lower-norwegian",
    "lower-roman", "lowercase", "ltr", "malayalam", "match", "matrix", "matrix3d",
    "media-controls-background", "media-current-time-display",
    "media-fullscreen-button", "media-mute-button", "media-play-button",
    "media-return-to-realtime-button", "media-rewind-button",
    "media-seek-back-button", "media-seek-forward-button", "media-slider",
    "media-sliderthumb", "media-time-remaining-display", "media-volume-slider",
    "media-volume-slider-container", "media-volume-sliderthumb", "medium",
    "menu", "menulist", "menulist-button", "menulist-text",
    "menulist-textfield", "menutext", "message-box", "middle", "min-intrinsic",
    "mix", "mongolian", "monospace", "move", "multiple", "myanmar", "n-resize",
    "narrower", "ne-resize", "nesw-resize", "no-close-quote", "no-drop",
    "no-open-quote", "no-repeat", "none", "normal", "not-allowed", "nowrap",
    "ns-resize", "numbers", "numeric", "nw-resize", "nwse-resize", "oblique", "octal", "open-quote",
    "optimizeLegibility", "optimizeSpeed", "oriya", "oromo", "outset",
    "outside", "outside-shape", "overlay", "overline", "padding", "padding-box",
    "painted", "page", "paused", "persian", "perspective", "plus-darker", "plus-lighter",
    "pointer", "polygon", "portrait", "pre", "pre-line", "pre-wrap", "preserve-3d",
    "progress", "push-button", "radial-gradient", "radio", "read-only",
    "read-write", "read-write-plaintext-only", "rectangle", "region",
    "relative", "repeat", "repeating-linear-gradient",
    "repeating-radial-gradient", "repeat-x", "repeat-y", "reset", "reverse",
    "rgb", "rgba", "ridge", "right", "rotate", "rotate3d", "rotateX", "rotateY",
    "rotateZ", "round", "row-resize", "rtl", "run-in", "running",
    "s-resize", "sans-serif", "scale", "scale3d", "scaleX", "scaleY", "scaleZ",
    "scroll", "scrollbar", "se-resize", "searchfield",
    "searchfield-cancel-button", "searchfield-decoration",
    "searchfield-results-button", "searchfield-results-decoration",
    "semi-condensed", "semi-expanded", "separate", "serif", "show", "sidama",
    "simp-chinese-formal", "simp-chinese-informal", "single",
    "skew", "skewX", "skewY", "skip-white-space", "slide", "slider-horizontal",
    "slider-vertical", "sliderthumb-horizontal", "sliderthumb-vertical", "slow",
    "small", "small-caps", "small-caption", "smaller", "solid", "somali",
    "source-atop", "source-in", "source-out", "source-over", "space", "spell-out", "square",
    "square-button", "start", "static", "status-bar", "stretch", "stroke", "sub",
    "subpixel-antialiased", "super", "sw-resize", "symbolic", "symbols", "table",
    "table-caption", "table-cell", "table-column", "table-column-group",
    "table-footer-group", "table-header-group", "table-row", "table-row-group",
    "tamil",
    "telugu", "text", "text-bottom", "text-top", "textarea", "textfield", "thai",
    "thick", "thin", "threeddarkshadow", "threedface", "threedhighlight",
    "threedlightshadow", "threedshadow", "tibetan", "tigre", "tigrinya-er",
    "tigrinya-er-abegede", "tigrinya-et", "tigrinya-et-abegede", "to", "top",
    "trad-chinese-formal", "trad-chinese-informal",
    "translate", "translate3d", "translateX", "translateY", "translateZ",
    "transparent", "ultra-condensed", "ultra-expanded", "underline", "up",
    "upper-alpha", "upper-armenian", "upper-greek", "upper-hexadecimal",
    "upper-latin", "upper-norwegian", "upper-roman", "uppercase", "urdu", "url",
    "var", "vertical", "vertical-text", "visible", "visibleFill", "visiblePainted",
    "visibleStroke", "visual", "w-resize", "wait", "wave", "wider",
    "window", "windowframe", "windowtext", "words", "x-large", "x-small", "xor",
    "xx-large", "xx-small"
  ], valueKeywords = keySet(valueKeywords_);

  var allWords = []..addAll(documentTypes_)..addAll(mediaTypes_)..addAll(mediaFeatures_)..addAll(propertyKeywords_)
    ..addAll(nonStandardPropertyKeywords_)..addAll(colorKeywords_)..addAll(valueKeywords_);

  CodeMirror.registerHelper("hintWords", "css", allWords);
  CodeMirror.defineMode("css", (dynamic a, dynamic b) => new CssMode(a, b));

  CodeMirror.defineMIME("text/css", new Config(
    documentTypes: documentTypes,
    mediaTypes: mediaTypes,
    mediaFeatures: mediaFeatures,
    propertyKeywords: propertyKeywords,
    nonStandardPropertyKeywords: nonStandardPropertyKeywords,
    fontProperties: fontProperties,
    counterDescriptors: counterDescriptors,
    colorKeywords: colorKeywords,
    valueKeywords: valueKeywords,
    tokenHooks: {
      "<": (StringStream stream, state) {
        if (stream.match("!--") == null) return false;
        state.tokenize = tokenSGMLComment;
        return tokenSGMLComment(stream, state);
      },
      "/": (StringStream stream, state) {
        if (stream.eat("*") == null) return false;
        state.tokenize = tokenCComment;
        return tokenCComment(stream, state);
      }
    },
    name: "css"
  ));

  CodeMirror.defineMIME("text/x-scss", new Config(
    mediaTypes: mediaTypes,
    mediaFeatures: mediaFeatures,
    propertyKeywords: propertyKeywords,
    nonStandardPropertyKeywords: nonStandardPropertyKeywords,
    colorKeywords: colorKeywords,
    valueKeywords: valueKeywords,
    fontProperties: fontProperties,
    allowNested: true,
    tokenHooks: {
      "/": (StringStream stream, state) {
        if (stream.eat("/") != null) {
          stream.skipToEnd();
          return ["comment", "comment"];
        } else if (stream.eat("*") != null) {
          state.tokenize = tokenCComment;
          return tokenCComment(stream, state);
        } else {
          return ["operator", "operator"];
        }
      },
      ":": (StringStream stream, state) {
        if (stream.match(new RegExp(r'\s*\{')) != null)
          return [null, "{"];
        return false;
      },
      r"$": (StringStream stream, state) {
        stream.match(new RegExp(r'^[\w-]+'));
        if (stream.match(new RegExp(r'^\s*:'), false) != null)
          return ["variable-2", "variable-definition"];
        return ["variable-2", "variable"];
      },
      "#": (StringStream stream, state) {
        if (stream.eat("{") == null) return false;
        return [null, "interpolation"];
      }
    },
    name: "css",
    helperType: "scss"
  ));

  CodeMirror.defineMIME("text/x-less", new Config(
    mediaTypes: mediaTypes,
    mediaFeatures: mediaFeatures,
    propertyKeywords: propertyKeywords,
    nonStandardPropertyKeywords: nonStandardPropertyKeywords,
    colorKeywords: colorKeywords,
    valueKeywords: valueKeywords,
    fontProperties: fontProperties,
    allowNested: true,
    tokenHooks: {
      "/": (StringStream stream, state) {
        if (stream.eat("/") != null) {
          stream.skipToEnd();
          return ["comment", "comment"];
        } else if (stream.eat("*") != null) {
          state.tokenize = tokenCComment;
          return tokenCComment(stream, state);
        } else {
          return ["operator", "operator"];
        }
      },
      "@": (StringStream stream, state) {
        var meta = r"^(charset|document|font-face|import|(-(moz|ms|o|webkit)-)?keyframes|media|namespace|page|supports)\b";
        if (stream.match(new RegExp(meta), false) != null) return false;
        stream.eatWhile(new RegExp(r'[\w\\\-]'));
        if (stream.match(new RegExp(r'^\s*:'), false) != null)
          return ["variable-2", "variable-definition"];
        return ["variable-2", "variable"];
      },
      "&": (StringStream stream, state) {
        return ["atom", "atom"];
      }
    },
    name: "css",
    helperType: "less"
  ));
}

keySet(array) {
  var keys = {};
  for (var i = 0; i < array.length; ++i) {
    keys[array[i]] = true;
  }
  return keys;
}

tokenCComment(StringStream stream, state) {
  var maybeEnd = false, ch;
  while ((ch = stream.next()) != null) {
    if (maybeEnd && ch == "/") {
      state.tokenize = null;
      break;
    }
    maybeEnd = (ch == "*");
  }
  return ["comment", "comment"];
}

tokenSGMLComment(StringStream stream, state) {
  if (stream.skipTo("-->")) {
    stream.match("-->");
    state.tokenize = null;
  } else {
    stream.skipToEnd();
  }
  return ["comment", "comment"];
}

class Config {
  var mediaTypes;
  var mediaFeatures;
  var propertyKeywords;
  var nonStandardPropertyKeywords;
  var colorKeywords;
  var valueKeywords;
  var fontProperties;
  var counterDescriptors;
  var documentTypes;
  bool allowNested;
  Map tokenHooks;
  String name;
  String helperType;

  Config({
    this.mediaTypes,
    this.mediaFeatures,
    this.propertyKeywords,
    this.nonStandardPropertyKeywords,
    this.colorKeywords,
    this.valueKeywords,
    this.fontProperties,
    this.counterDescriptors,
    this.allowNested: false,
    this.tokenHooks,
    this.documentTypes,
    this.name,
    this.helperType
  });
}
