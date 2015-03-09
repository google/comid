// Copyright (c) 2015, the Comid Authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

part of comid.test;

searchTest() {
  // Test search add-on.
  group('Search,', () {

    testSearch("simple", ["abcdefg", "abcdefg"], (doc) {
      run(doc, "cde", false, [0, 2, 0, 5, 1, 2, 1, 5]);
    });

    testSearch("multiline", ["hallo", "goodbye"], (doc) {
      run(doc, "llo\ngoo", false, [0, 2, 1, 3]);
      run(doc, "blah\nhall", false);
      run(doc, "bye\neye", false);
    });

    testSearch("regexp", ["abcde", "abcde"], (doc) {
      run(doc, new RegExp('bcd'), false, [0, 1, 0, 4, 1, 1, 1, 4]);
      run(doc, new RegExp('BCD'), false);
      run(doc, new RegExp('BCD', caseSensitive: false), false, [0, 1, 0, 4, 1, 1, 1, 4]);
    });

    testSearch("insensitive", ["hallo", "HALLO", "oink", "hAllO"], (doc) {
      run(doc, "All", false, [3, 1, 3, 4]);
      run(doc, "All", true, [0, 1, 0, 4, 1, 1, 1, 4, 3, 1, 3, 4]);
    });

    testSearch("multilineInsensitive", ["zie ginds komT", "De Stoomboot", "uit Spanje weer aan"], (doc) {
      run(doc, "komt\nde stoomboot\nuit", false);
      run(doc, "komt\nde stoomboot\nuit", true, [0, 10, 2, 3]);
      run(doc, "kOMt\ndE stOOmboot\nuiT", true, [0, 10, 2, 3]);
    });

    testSearch("expandingCaseFold", ["<b>İİ İİ</b>", "<b>uu uu</b>"], (doc) {
      if (phantom) return; // A Phantom bug makes this hang
      run(doc, "</b>", true, [0, 8, 0, 12, 1, 8, 1, 12]);
      run(doc, "İİ", true, [0, 3, 0, 5, 0, 6, 0, 8]);
    });

  });
}

void testSearch(String name, List<String> content, Function testBody) {
  test(name, () {
    var editor = makeEditor({'value': content.join('\n')});
    testBody(editor);
  });
}

void run(CodeMirror cm, Pattern query, bool insensitive, [List arguments]) {
  if (arguments == null) arguments = [];
  var cursor = getSearchCursor(cm, query, null, insensitive);
  for (var i = 0; i < arguments.length; i += 4) {
    var found = cursor.findNext();
    expect(found, isTrue, reason: "not enough results (forward)");
    expect(new Pos(arguments[i], arguments[i + 1]), cursor.from(), reason: "from, forward, ${i / 4}");
    expect(new Pos(arguments[i + 2], arguments[i + 3]), cursor.to(), reason: "to, forward, ${i / 4}");
  }
  expect(cursor.findNext(), isFalse, reason: "too many matches (forward)");
  for (var i = arguments.length - 4; i >= 0; i -= 4) {
    var found = cursor.findPrevious();
    expect(found, isTrue, reason: "not enough results (backwards)");
    expect(new Pos(arguments[i], arguments[i + 1]), cursor.from(), reason: "from, backwards, ${i / 4}");
    expect(new Pos(arguments[i + 2], arguments[i + 3]), cursor.to(), reason: "to, backwards, ${i / 4}");
  }
  expect(cursor.findPrevious(), isFalse, reason:"too many matches (backwards)");
}