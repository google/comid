// Copyright (c) 2015, the Comid Authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library comid.dart;

import 'dart:html';
import 'package:comid/codemirror.dart';
import 'package:comid/addon/mode/dart.dart';
import 'package:comid/addon/edit/matchbrackets.dart';
import 'package:comid/addon/edit/closebrackets.dart';
import 'package:comid/addon/edit/show-hint.dart' as hints;
import 'package:comid/addon/edit/html-hint.dart' as html;
import 'package:comid/addon/comment/comment.dart' as comments;
import "package:comid/addon/search/search.dart";

var options = {
  'lineNumbers': true,
  'matchBrackets': true,
  'autoCloseBrackets': true,
  'theme': 'vibrant-ink', // 'red-light', 'vibrant-ink', 'zenburn'
  'extraKeys': {
    "Ctrl-Space": "autocomplete",
    (mac ? "Cmd-/" : "Ctrl-/"): "toggleComment"
  },
  'mode': 'dart',
  'continueComments': {
    'continueLineComment': true
  }
};

main() {
  initialize();
  Node text = document.getElementById("code");
  CodeMirror editor = CodeMirror.fromTextArea(text, options);
  loadTheme(options['theme']);
  // Display the editor after everything is initialized.
  text.parent.hidden = false;
  editor.refresh();
  editor.focus();
}

initialize() {
  DartMode.initialize();
  hints.initialize();
  html.initialize();
  comments.initialize();
  initializeBracketMatching();
  initializeBracketClosing();
  initializeSearch();
  var opts = new hints.CompletionOptions(
//      completeSingle: false,
      hint: CodeMirror.getNamedHelper('hint', 'auto'));
  CodeMirror.defaultCommands['autocomplete'] = ([CodeMirror cm]) {
    cm.commands['showHint'](cm, opts);
  };
}

Node _currentThemeElement;
loadTheme(String name) {
  if (_currentThemeElement != null) _currentThemeElement.remove();
  if (name == null) return;
  var fileref=document.createElement("link");
  fileref.setAttribute("rel", "stylesheet");
  fileref.setAttribute("type", "text/css");
  fileref.setAttribute("href", "packages/comid/theme/$name.css");
  _currentThemeElement = fileref;
  document.getElementsByTagName("head")[0].append(fileref);
//  var body = document.getElementsByTagName("body")[0];
//  body.style.backgroundColor = "black";
//  body.style.color = "white";
}