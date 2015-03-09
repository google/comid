// Copyright (c) 2015, the Comid Authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library comid.mode.xml;

import 'package:comid/codemirror.dart';

class XmlMode extends Mode {

  static bool _initialized = false;
  static initialize() {
    if (_initialized) return;
    _initialized = true;
    CodeMirror.defineMode("xml", (dynamic config, dynamic parserConfig) {
      return new XmlMode(config, parserConfig);
    });
    CodeMirror.defineMIME("text/xml", "xml");
    CodeMirror.defineMIME("application/xml", "xml");
    CodeMirror.defineMIME("text/html", {'name': "xml", 'htmlMode': true});
  }

  int indentUnit;
  num multilineTagIndentFactor;
  bool multilineTagIndentPastTag;
  bool alignCDATA;
  bool htmlMode;

  // Return variables for tokenizers
  String type, setStyle;

  // Simple html support (formerly Kludges)
  Map autoSelfClosers = {};
  Map implicitlyClosed = {};
  Map contextGrabbers = {};
  Map doNotIndent = {};
  bool allowUnquoted = false;
  bool allowMissing = false;
  bool caseFold = false;

  Function isInAttribute;

  XmlMode(var conf, var parserConf) {
    Options config = conf is Map ? new Options.from(conf) : conf;
    Config parserConfig = parserConf is Map ? new Config(parserConf) : parserConf;
    indentUnit = config.indentUnit;
    multilineTagIndentFactor = parserConfig.multilineTagIndentFactor;
    if (multilineTagIndentFactor == null || multilineTagIndentFactor == 0) {
      multilineTagIndentFactor = 1;
    }
    multilineTagIndentPastTag = parserConfig.multilineTagIndentPastTag;
    if (multilineTagIndentPastTag == null) {
      multilineTagIndentPastTag = true;
    }
    htmlMode = parserConfig.htmlMode;
    if (htmlMode) {
      autoSelfClosers = {'area': true, 'base': true, 'br': true, 'col': true, 'command': true,
                         'embed': true, 'frame': true, 'hr': true, 'img': true, 'input': true,
                         'keygen': true, 'link': true, 'meta': true, 'param': true, 'source': true,
                         'track': true, 'wbr': true, 'menuitem': true};
      implicitlyClosed = {'dd': true, 'li': true, 'optgroup': true, 'option': true, 'p': true,
                          'rp': true, 'rt': true, 'tbody': true, 'td': true, 'tfoot': true,
                          'th': true, 'tr': true};
      contextGrabbers = {
        'dd': {'dd': true, 'dt': true},
        'dt': {'dd': true, 'dt': true},
        'li': {'li': true},
        'option': {'option': true, 'optgroup': true},
        'optgroup': {'optgroup': true},
        'p': {'address': true, 'article': true, 'aside': true, 'blockquote': true, 'dir': true,
              'div': true, 'dl': true, 'fieldset': true, 'footer': true, 'form': true,
              'h1': true, 'h2': true, 'h3': true, 'h4': true, 'h5': true, 'h6': true,
              'header': true, 'hgroup': true, 'hr': true, 'menu': true, 'nav': true, 'ol': true,
              'p': true, 'pre': true, 'section': true, 'table': true, 'ul': true},
        'rp': {'rp': true, 'rt': true},
        'rt': {'rp': true, 'rt': true},
        'tbody': {'tbody': true, 'tfoot': true},
        'td': {'td': true, 'th': true},
        'tfoot': {'tbody': true},
        'th': {'td': true, 'th': true},
        'thead': {'tbody': true, 'tfoot': true},
        'tr': {'tr': true}
      };
      doNotIndent = {"pre": true};
      allowUnquoted = true;
      allowMissing = true;
      caseFold = true;
    }
    alignCDATA = parserConfig.alignCDATA;
  }

  inText(StringStream stream, XmlState state) {
    chain(parser) {
      state.tokenize = parser;
      return parser(stream, state);
    }

    var ch = stream.next();
    if (ch == "<") {
      if (stream.eat("!") != null) {
        if (stream.eat("[") != null) {
          if (stream.match("CDATA[") != null) return chain(inBlock("atom", "]]>"));
          else return null;
        } else if (stream.match("--") != null) {
          return chain(inBlock("comment", "-->"));
        } else if (stream.match("DOCTYPE", true, true) != null) {
          stream.eatWhile(new RegExp(r'[\w\._\-]'));
          return chain(doctype(1));
        } else {
          return null;
        }
      } else if (stream.eat("?") != null) {
        stream.eatWhile(new RegExp(r'[\w\._\-]'));
        state.tokenize = inBlock("meta", "?>");
        return "meta";
      } else {
        type = stream.eat("/") != null ? "closeTag" : "openTag";
        state.tokenize = inTag;
        return "tag bracket";
      }
    } else if (ch == "&") {
      var ok;
      if (stream.eat("#") != null) {
        if (stream.eat("x") != null) {
          ok = stream.eatWhile(new RegExp(r'[a-fA-F\d]')) && stream.eat(";") != null;
        } else {
          ok = stream.eatWhile(new RegExp(r'[\d]')) && stream.eat(";") != null;
        }
      } else {
        ok = stream.eatWhile(new RegExp(r'[\w\.\-:]')) && stream.eat(";") != null;
      }
      return ok ? "atom" : "error";
    } else {
      stream.eatWhile(new RegExp(r'[^&<]'));
      return null;
    }
  }

  inTag(StringStream stream, XmlState state) {
    var ch = stream.next();
    if (ch == ">" || (ch == "/" && stream.eat(">") != null)) {
      state.tokenize = inText;
      type = ch == ">" ? "endTag" : "selfcloseTag";
      return "tag bracket";
    } else if (ch == "=") {
      type = "equals";
      return null;
    } else if (ch == "<") {
      state.tokenize = inText;
      state.state = baseState;
      state.tagName = state.tagStart = null;
      var next = state.tokenize(stream, state);
      return next ? next + " tag error" : "tag error";
    } else if (new RegExp('[\'\"]').hasMatch(ch)) {
      state.tokenize = inAttribute(ch);
      state.stringStartCol = stream.column();
      return state.tokenize(stream, state);
    } else {
      stream.match(new RegExp('^[^\\s\\u00a0=<>\"\']*[^\\s\\u00a0=<>\"\'\/]'));
      return "word";
    }
  }

  inAttribute(String quote) {
    var closure = (StringStream stream, XmlState state) {
      while (!stream.eol()) {
        if (stream.next() == quote) {
          state.tokenize = inTag;
          break;
        }
      }
      return "string";
    };
    isInAttribute = closure;

    return closure;
  }

  inBlock(String style, String terminator) {
    return (StringStream stream, XmlState state) {
      while (!stream.eol()) {
        if (stream.match(terminator) != null) {
          state.tokenize = inText;
          break;
        }
        stream.next();
      }
      return style;
    };
  }
  doctype(int depth) {
    return (StringStream stream, XmlState state) {
      var ch;
      while ((ch = stream.next()) != null) {
        if (ch == "<") {
          state.tokenize = doctype(depth + 1);
          return state.tokenize(stream, state);
        } else if (ch == ">") {
          if (depth == 1) {
            state.tokenize = inText;
            break;
          } else {
            state.tokenize = doctype(depth - 1);
            return state.tokenize(stream, state);
          }
        }
      }
      return "meta";
    };
  }
  popContext(XmlState state) {
    if (state.context != null) state.context = state.context.prev;
  }
  maybePopContext(XmlState state, String nextTagName) {
    var parentTagName;
    while (true) {
      if (state.context == null) {
        return;
      }
      parentTagName = state.context.tagName;
      if (!contextGrabbers.containsKey(parentTagName) ||
          !contextGrabbers[parentTagName].containsKey(nextTagName)) {
        return;
      }
      popContext(state);
    }
  }

  baseState(String type, StringStream stream, XmlState state) {
    if (type == "openTag") {
      state.tagStart = stream.column();
      return tagNameState;
    } else if (type == "closeTag") {
      return closeTagNameState;
    } else {
      return baseState;
    }
  }
  tagNameState(String type, StringStream stream, XmlState state) {
    if (type == "word") {
      state.tagName = stream.current();
      setStyle = "tag";
      return attrState;
    } else {
      setStyle = "error";
      return tagNameState;
    }
  }
  closeTagNameState(String type, StringStream stream, XmlState state) {
    if (type == "word") {
      var tagName = stream.current();
      if (state.context != null && state.context.tagName != tagName &&
          implicitlyClosed.containsKey(state.context.tagName))
        popContext(state);
      if (state.context != null && state.context.tagName == tagName) {
        setStyle = "tag";
        return closeState;
      } else {
        setStyle = "tag error";
        return closeStateErr;
      }
    } else {
      setStyle = "error";
      return closeStateErr;
    }
  }

  closeState(String type, StringStream stream, XmlState state) {
    if (type != "endTag") {
      setStyle = "error";
      return closeState;
    }
    popContext(state);
    return baseState;
  }
  closeStateErr(String type, StringStream stream, XmlState state) {
    setStyle = "error";
    return closeState(type, stream, state);
  }

  attrState(String type, StringStream stream, XmlState state) {
    if (type == "word") {
      setStyle = "attribute";
      return attrEqState;
    } else if (type == "endTag" || type == "selfcloseTag") {
      var tagName = state.tagName, tagStart = state.tagStart;
      state.tagName = state.tagStart = null;
      if (type == "selfcloseTag" ||
          autoSelfClosers.containsKey(tagName)) {
        maybePopContext(state, tagName);
      } else {
        maybePopContext(state, tagName);
        bool noIn = doNotIndent.containsKey(tagName) || (state.context != null && state.context.noIndent);
        state.context = new Context(state, tagName, tagStart == state.indented, noIn);
      }
      return baseState;
    }
    setStyle = "error";
    return attrState;
  }
  attrEqState(String type, StringStream stream, XmlState state) {
    if (type == "equals") return attrValueState;
    if (!allowMissing) setStyle = "error";
    return attrState(type, stream, state);
  }
  attrValueState(String type, StringStream stream, XmlState state) {
    if (type == "string") return attrContinuedState;
    if (type == "word" && allowUnquoted) {
      setStyle = "string"; return attrState;
    }
    setStyle = "error";
    return attrState(type, stream, state);
  }
  attrContinuedState(String type, StringStream stream, XmlState state) {
    if (type == "string") {
      return attrContinuedState;
    } else {
      return attrState(type, stream, state);
    }
  }

  startState([int base, x]) {
    return new XmlState(
        tokenize: inText,
        state: baseState,
        indented: 0,
        tagName: null,
        tagStart: null,
        context: null
      );
    }

  token(StringStream stream, [XmlState state]) {
    if (state.tagName == null && stream.sol())
      state.indented = stream.indentation();

    if (stream.eatSpace()) return null;
    type = null;
    var style = state.tokenize(stream, state);
    if ((style != null || type != null) && style != "comment") {
      setStyle = null;
      state.state = state.state(type == null ? style : type, stream, state);
      if (setStyle != null) {
        style = setStyle == "error" ? "$style error" : setStyle;
      }
    }
    return style;
  }

  indent(XmlState state, String textAfter, String fullLine) {
    Context context = state.context;
    // Indent multi-line strings (e.g. css).
    if (state.tokenize == isInAttribute) {
      if (state.tagStart == state.indented) {
        return state.stringStartCol + 1;
      } else {
        return state.indented + indentUnit;
      }
    }
    if (context != null && context.noIndent) return Pass;
    if (state.tokenize != inTag && state.tokenize != inText)
      return fullLine != null
          ? new RegExp(r'^(\s*)').firstMatch(fullLine)[0].length : 0;
    // Indent the starts of attribute names.
    if (state.tagName != null) {
      if (multilineTagIndentPastTag) {
        return state.tagStart + state.tagName.length + 2;
      } else {
        return state.tagStart + indentUnit * multilineTagIndentFactor;
      }
    }
    if (alignCDATA && new RegExp(r'<!\[CDATA\[').hasMatch(textAfter)) {
      return 0;
    }
    Match tagAfter = textAfter == null
        ? null : new RegExp(r'^<(\/)?([\w_:\.-]*)').firstMatch(textAfter);
    if (tagAfter != null && tagAfter[1] != null) { // Closing tag spotted
      while (context != null) {
        if (context.tagName == tagAfter[2]) {
          context = context.prev;
          break;
        } else if (implicitlyClosed.containsKey(context.tagName)) {
          context = context.prev;
        } else {
          break;
        }
      }
    } else if (tagAfter != null) { // Opening tag spotted
      while (context != null) {
        var grabbers = contextGrabbers[context.tagName];
        if (grabbers != null && grabbers.containsKey(tagAfter[2]))
          context = context.prev;
        else
          break;
      }
    }
    while (context != null && !context.startOfLine)
      context = context.prev;
    if (context != null) {
      return context.indent + indentUnit;
    } else {
      return 0;
    }
  }

  XmlState get state => super.state;

  get electricInput => new RegExp(r'<\/[\s\w:]+>$');
  get blockCommentStart => "<!--";
  get blockCommentEnd => "-->";

  get configuration => htmlMode ? "html" : "xml";
  get helperType => htmlMode ? "html" : "xml";

  bool get hasIndent => true;
  bool get hasStartState => true;
  bool get hasElectricChars => true;

}

class Context {
  Context prev;
  int indent;
  String tagName;
  bool startOfLine;
  bool noIndent;

  Context(state, this.tagName, this.startOfLine, this.noIndent) {
    this.prev = state.context;
    this.indent = state.indented;
  }

  String toString() {
    return "Context($tagName, $indent, $startOfLine, $noIndent, $prev)";
  }
}

class XmlState extends ModeState {
  Context context;
  Function tokenize;
  Function state; // f(a,b,c) => XmlState
  String tagName;
  int indented;
  int tagStart;
  int stringStartCol;

  XmlState({
    this.tokenize,
    this.state,
    this.indented,
    this.tagName,
    this.tagStart,
    this.context
  });

  XmlState newInstance() {
    return new XmlState();
  }

  void copyValues(XmlState old) {
    context = old.context;
    state = old.state;
    tokenize = old.tokenize;
    tagName = old.tagName;
    indented = old.indented;
    tagStart = old.tagStart;
    stringStartCol = old.stringStartCol;
  }

  String toString() {
    return "XmlState($indented, $tagName, $tagStart, $stringStartCol, $context)";
  }
}

class Config {
  num multilineTagIndentFactor;
  bool multilineTagIndentPastTag;
  bool alignCDATA = false;
  bool htmlMode = false;

  Config([conf]) {
    if (conf != null) {
      if (conf['htmlMode'] != null) htmlMode = conf['htmlMode'];
      if (conf['alignCDATA'] != null) alignCDATA = conf['alignCDATA'];
      if (conf['multilineTagIndentPastTag'] != null) multilineTagIndentPastTag = conf['multilineTagIndentPastTag'];
      if (conf['multilineTagIndentFactor'] != null) multilineTagIndentFactor = conf['multilineTagIndentFactor'];
    }
  }
}
