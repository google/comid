// Copyright (c) 2015, the Comid Authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library comid.clike.example;

import 'dart:html';
import 'package:comid/codemirror.dart';
import 'package:comid/addon/mode/clike.dart';
import 'package:comid/addon/edit/matchbrackets.dart';
import 'package:comid/addon/edit/closebrackets.dart';
import 'package:comid/addon/fold/fold-all.dart' as fold;

main() {
  ClikeMode.initialize();
  initializeBracketMatching();
  initializeBracketClosing();
  fold.initialize();
  var cEditor = CodeMirror.fromTextArea(document.getElementById("c-code"), {
    'lineNumbers': true,
    'matchBrackets': true,
    'autoCloseBrackets': true,
    'extraKeys': {"Ctrl-Q": ([cm]){ fold.foldCode(cm, cm.getCursor()); }},
    'mode': "text/x-csrc"
  });
  var cppEditor = CodeMirror.fromTextArea(document.getElementById("cpp-code"), {
    'lineNumbers': true,
    'matchBrackets': true,
    'autoCloseBrackets': true,
    'extraKeys': {"Ctrl-Q": ([cm]){ fold.foldCode(cm, cm.getCursor()); }},
    'mode': "text/x-c++src"
  });
  var javaEditor = CodeMirror.fromTextArea(document.getElementById("java-code"), {
    'lineNumbers': true,
    'matchBrackets': true,
    'autoCloseBrackets': true,
    'extraKeys': {"Ctrl-Q": ([cm]){ fold.foldCode(cm, cm.getCursor()); }},
    'mode': "text/x-java"
  });
  var objectivecEditor = CodeMirror.fromTextArea(document.getElementById("objectivec-code"), {
    'lineNumbers': true,
    'matchBrackets': true,
    'autoCloseBrackets': true,
    'extraKeys': {"Ctrl-Q": ([cm]){ fold.foldCode(cm, cm.getCursor()); }},
    'mode': "text/x-objectivec"
  });
  var scalaEditor = CodeMirror.fromTextArea(document.getElementById("scala-code"), {
    'lineNumbers': true,
    'matchBrackets': true,
    'autoCloseBrackets': true,
    'extraKeys': {"Ctrl-Q": ([cm]){ fold.foldCode(cm, cm.getCursor()); }},
    'mode': "text/x-scala"
  });
  cEditor.hashCode; cppEditor.hashCode; javaEditor.hashCode;
  objectivecEditor.hashCode; scalaEditor.hashCode;
  //var mac = CodeMirror.keyMap.default == CodeMirror.keyMap.macDefault;
  //CodeMirror.keyMap.default[(mac ? "Cmd" : "Ctrl") + "-Space"] = "autocomplete";
}
