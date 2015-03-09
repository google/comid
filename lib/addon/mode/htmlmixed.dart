// Copyright (c) 2015, the Comid Authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library comid.mode.html;

import 'dart:math';
import 'package:comid/codemirror.dart';
import 'package:comid/addon/mode/xml.dart' as xml;
import 'package:comid/addon/mode/css.dart';

class HtmlMode extends Mode {

  static bool _initialized = false;
  static initialize() {
    if (_initialized) return;
    _initialized = true;
    CssMode.initialize();
    xml.XmlMode.initialize();
    CodeMirror.defineMode("htmlmixed", (config, parserConfig) => new HtmlMode(config, parserConfig));
    CodeMirror.defineMIME("text/html", "htmlmixed");
  }

  xml.XmlMode htmlMode;
  CssMode cssMode;
  List<ScriptType> scriptTypes;

  HtmlMode(conf, psrConf) {
    Options config = conf is Map ? new Options.from(conf) : conf;
    Config parserConfig = psrConf is Map ? new Config(psrConf) : psrConf;
    var htmlOpts = {
      'name': "xml",
      'htmlMode': true,
      'multilineTagIndentFactor': parserConfig.multilineTagIndentFactor,
      'multilineTagIndentPastTag': parserConfig.multilineTagIndentPastTag
    };
    htmlMode = CodeMirror.getMode(config, htmlOpts); // TODO parserConfig
    cssMode = CodeMirror.getMode(config, "css");

    scriptTypes = [];
    var scriptTypesConf = parserConfig.scriptTypes;
    var jsMatcher = r'^(?:text|application)\/(?:x-)?(?:java|ecma)script$|^$';
    scriptTypes.add(new ScriptType(
      matches: new RegExp(jsMatcher, caseSensitive: true),
      mode: CodeMirror.getMode(config, "javascript")
    ));
    if (scriptTypesConf != null) {
      for (var i = 0; i < scriptTypesConf.length; ++i) {
        var conf = scriptTypesConf[i];
        scriptTypes.add(new ScriptType(
          matches: conf['matches'],
          mode: conf['mode'] == null ? null : CodeMirror.getMode(config, conf['mode'])
        ));
      }
    }
    scriptTypes.add(new ScriptType(
      matches: new RegExp(r'.'),
      mode: CodeMirror.getMode(config, "text/plain")
    ));
  }

  html(StringStream stream, HtmlState state) {
    var tagName = state.htmlState.tagName;
    if (tagName != null) tagName = tagName.toLowerCase();
    var style = htmlMode.token(stream, state.htmlState);
    if (tagName == "script" && style != null &&
        new RegExp(r'\btag\b').hasMatch(style) && stream.current() == ">") {
      // Script block: mode to change to depends on type attribute
      var typer = new RegExp('\\btype\\s*=\\s*("[^"]+"|\'[^\']+\'|\\S+)[^<]*\$', caseSensitive: true);
      var scriptType = typer.firstMatch(stream.string.substring(max(0, stream.pos - 100), stream.pos));
      scriptType = scriptType != null ? scriptType[1] : "";
      if (!scriptType.isEmpty && new RegExp('[\"\']').hasMatch(scriptType.substring(0,1))) {
        scriptType = scriptType.substring(1, scriptType.length - 1);
      }
      for (var i = 0; i < scriptTypes.length; ++i) {
        var tp = scriptTypes[i];
        if (tp.matches is String ? scriptType == tp.matches : tp.matches.hasMatch(scriptType)) {
          if (tp.mode != null) {
            state.token = script;
            state.localMode = tp.mode;
            if (tp.mode.hasStartState) {
              state.localState = tp.mode.startState(htmlMode.indent(state.htmlState, "", null));
            }
          }
          break;
        }
      }
    } else if (tagName == "style" && style != null &&
        new RegExp(r'\btag\b').hasMatch(style) && stream.current() == ">") {
      state.token = css;
      state.localMode = cssMode;
      state.localState = cssMode.startState(htmlMode.indent(state.htmlState, "", null));
    }
    return style;
  }
  maybeBackup(stream, pat, style) {
    var cur = stream.current();
    var close = cur.indexOf(pat);
    if (close > -1) stream.backUp(cur.length - close);
    else if (new RegExp(r'<\/?$').hasMatch(cur)) {
      stream.backUp(cur.length);
      if (stream.match(pat, false) == null) stream.match(cur);
    }
    return style;
  }
  script(StringStream stream, HtmlState state) {
    if (stream.match(new RegExp(r'^<\/\s*script\s*>', caseSensitive: true), false) != null) {
      state.token = html;
      state.localState = state.localMode = null;
      return null;
    }
    return maybeBackup(stream, new RegExp(r'<\/\s*script\s*>'),
                       state.localMode.token(stream, state.localState));
  }
  css(StringStream stream, HtmlState state) {
    if (stream.match(new RegExp(r'^<\/\s*style\s*>', caseSensitive: true), false) != null) {
      state.token = html;
      state.localState = state.localMode = null;
      return null;
    }
    return maybeBackup(stream, new RegExp(r'<\/\s*style\s*>'),
                       cssMode.token(stream, state.localState));
  }

  bool get hasIndent => true;
  bool get hasStartState => true;
  bool get hasInnerMode => true;

  startState([x,y]) {
    var state = htmlMode.startState();
    return new HtmlState(token: html, localMode: null, localState: null, htmlState: state);
  }

  copyState(state) {
    return state.copy();
//    if (state.localState)
//      var local = CodeMirror.copyState(state.localMode, state.localState);
//    return {token: state.token, localMode: state.localMode, localState: local,
//            htmlState: CodeMirror.copyState(htmlMode, state.htmlState)};
  }

  token(StringStream stream, [HtmlState state]) {
    return state.token(stream, state);
  }

  indent(HtmlState state, String textAfter, x) {
    if (state.localMode == null || new RegExp(r'^\s*<\/').hasMatch(textAfter))
      return htmlMode.indent(state.htmlState, textAfter, x);
    else if (state.localMode.hasIndent)
      return state.localMode.indent(state.localState, textAfter, x);
    else
      return Pass;
  }

  innerMode([state]) {
    var st = state.localState == null ? state.htmlState : state.localState;
    var md = state.localMode == null ? htmlMode : state.localMode;
    return new Mode(mode: md, state: st);
  }
}

class HtmlState extends ModeState {
  Function token;
  Mode localMode;
  ModeState localState;
  xml.XmlState htmlState;

  HtmlState({this.token, this.localMode, this.localState, this.htmlState});

  HtmlState newInstance() {
    return new HtmlState();
  }

  void copyValues(HtmlState old) {
    token = old.token;
    localMode = old.localMode;
    localState = old.localState;
    htmlState = old.htmlState;
    if (localState != null) {
      localState = CodeMirror.copyState(localMode, localState);
    }
    if (htmlState != null) {
      htmlState = htmlState.copy();
    }
  }

  String toString() {
    return "HtmlState($token, $localMode, $localState, $htmlState)";
  }
}

class Config extends xml.Config {
  var scriptTypes;

  Config([conf]) : super(conf) {
    if (conf != null) {
      scriptTypes = conf['scriptTypes'];
    }
  }
}

class ScriptType {
  Pattern matches;
  Mode mode;

  ScriptType({this.matches, this.mode});
}
