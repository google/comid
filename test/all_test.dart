// Copyright (c) 2015, the Comid Authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library comid.test;

import 'dart:async';
import 'dart:math';
import 'dart:html' hide Document, Range, Selection;

import 'package:unittest/unittest.dart';
//import 'package:unittest/html_config.dart';
import 'package:comid/codemirror.dart';
import "package:comid/addon/mode/css.dart";
import "package:comid/addon/mode/xml.dart";
import "package:comid/addon/mode/dart.dart";
import "package:comid/addon/comment/comment.dart" as comment;
import "package:comid/addon/edit/show-hint.dart" as hint;
import "package:comid/addon/search/search.dart";

part 'codeeditor_test.dart';
part 'document_test.dart';
part 'doc_test.dart';
part 'multi_test.dart';
part 'scroll_test.dart';
part 'command_test.dart';
part 'mode_test.dart';
part 'cssmode_test.dart';
part 'xmlmode_test.dart';
part 'comment_test.dart';
part 'search_test.dart';

main() {
//  useHtmlConfiguration();
  document.getElementById("testground").innerHtml = "<form>" +
    "<textarea id=\"code\" name=\"code\"></textarea>" +
    "<input type=submit value=ok name=submit>" +
    "</form>";
  // Initialize new options early.
  hint.initialize();
  comment.initialize();
//   TODO Define a real javascript mode and enable dependent tests.
  CodeMirror.defineMode('javascript', new Mode());
  DartMode.initialize();
  CssMode.initialize();
  initializeSearch;
  runAllTests();
  for (int i = 0; i < 0; i++) {
    withTestEnvironment(() {
      runUnittests(runAllTests).whenComplete(() {
        TestConfiguration config = unittestConfiguration;
        expect(config.checkIfTestRan('CodeEditor, getRange'), true);
        expect(config.checkIfTestRan('Multi-select, selectionHistory'), true);
      });
    });
  }
}

runAllTests() {
  commandTest();
  editorTest();
  documentTest();
  multiDocTest();
  scrollTest();
  multiTest();
  cssModeTest();
  xmlModeTest();
  commentTest();
  searchTest();
}

Future runUnittests(Function callback) {
  TestConfiguration config = unittestConfiguration = new TestConfiguration();
  callback();

  return config.done;
}

class TestConfiguration extends SimpleConfiguration {
  final Completer _completer = new Completer();
  List<TestCase> _results;

  TestConfiguration();

  void onSummary(int passed, int failed, int errors, List<TestCase> results,
      String uncaughtError) {
    super.onSummary(passed, failed, errors, results, uncaughtError);
    _results = results;
  }

  Future get done => _completer.future;

  onDone(success) {
    new Future.sync(() => super.onDone(success))
        .then(_completer.complete)
        .catchError(_completer.completeError);
  }

  bool checkIfTestRan(String testName) {
    return _results.any((test) => test.description == testName);
  }
}
