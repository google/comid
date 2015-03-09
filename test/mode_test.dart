// Copyright (c) 2015, the Comid Authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

part of comid.test;

/**
 * Helper to test CodeMirror highlighting modes. It pretty prints output of the
 * highlighter and can check against expected styles.
 *
 * Mode tests are registered by calling test.mode(testName, mode,
 * tokens), where mode is a mode object as returned by
 * CodeMirror.getMode, and tokens is an array of lines that make up
 * the test.
 *
 * These lines are strings, in which styled stretches of code are
 * enclosed in brackets `[]`, and prefixed by their style. For
 * example, `[keyword if]`. Brackets in the code itself must be
 * duplicated to prevent them from being interpreted as token
 * boundaries. For example `a[[i]]` for `a[i]`. If a token has
 * multiple styles, the styles must be separated by ampersands, for
 * example `[tag&error </hmtl>]`.
 *
 * See the test.js files in the css, markdown, gfm, and stex mode
 * directories for examples.
 */

findSingle(String str, int pos, String ch) {
  for (;;) {
    var found = str.indexOf(ch, pos);
    if (found == -1) return null;
    if (found + 1 == str.length) return found;
    if (str.substring(found + 1, found + 2) != ch) return found;
    pos = found + 2;
  }
}

RegExp styleName = new RegExp(r'[\w&-_]+'); //global
parseTokens(List<String> strs) {
  var tokens = [];
  var plain = "";
  for (var i = 0; i < strs.length; ++i) {
    if (i > 0) plain += "\n";
    var str = strs[i], pos = 0;
    while (pos < str.length) {
      var style = null;
      String text;
      if (str.substring(pos, pos+1) == "[" && str.substring(pos+1, pos+2) != "[") {
        var ms = styleName.allMatches(str, pos + 1);
        Match m = ms.first;
        style = m[0].replaceAll("&", " ");
        var textStart = pos + style.length + 2;
        var end = findSingle(str, textStart, "]");
        if (end == null) throw new StateError("Unterminated token at " + pos + " in '" + str + "'" + style);
        text = str.substring(textStart, end);
        pos = end + 1;
      } else {
        var end = findSingle(str, pos, "[");
        if (end == null) end = str.length;
        text = str.substring(pos, end);
        pos = end;
      }
      text = text.replaceAllMapped(new RegExp(r'\[\[|\]\]'), (s) {return s[0].substring(0,1);});
      tokens.add({'style': style, 'text': text});
      plain += text;
    }
  }
  return {'tokens': tokens, 'plain': plain};
}

test_mode(String name, Mode mode, tokens, [String modeName]) { // test.mode
  return test((modeName == null ? mode.name : modeName) + "_" + name, () {
    var data = parseTokens(tokens);
    return compare(data['plain'], data['tokens'], mode, name);
  });
}

esc(String str) {
  return str.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll(r'>', "&gt;").replaceAll(':', "&quot;").replaceAll("'", "&#039;");
  }

compare(text, expected, mode, name) {

  var expectedOutput = [];
  for (var i = 0; i < expected.length; ++i) {
    String sty = expected[i]['style'];
    if (sty != null && sty.indexOf(" ") >= 0) sty = ((sty.split(' '))..sort()).join(' ');
    expectedOutput.add({'style': sty, 'text': expected[i]['text']});
  }

  var out = highlight(text, mode);
  var observedOutput = out[0], indentFailures = out[1];

  var s = "";
  var diff = highlightOutputsDifferent(expectedOutput, observedOutput);
  if (diff != null) {
    s += '<div class="mt-test mt-fail">';
    s +=   '<pre>' + esc(text) + '</pre>';
    s +=   '<div class="cm-s-default">';
    s += 'expected:';
    s +=   prettyPrintOutputTable(expectedOutput, diff);
    s += 'observed: [<a onclick="this.parentElement.className+=\' mt-state-unhide\'">display states</a>]';
    s +=   prettyPrintOutputTable(observedOutput, diff);
    s +=   '</div>';
    s += '</div>';
  }
  if (indentFailures != null) {
    for (var i = 0; i < indentFailures.length; i++)
      s += "<div class='mt-test mt-fail'>" + esc(indentFailures[i]) + "</div>";
  }
  if (!s.isEmpty) failed(name, s);
}

failed(name, s) {
  addOutput(name, "", s);
  fail(name);
}

addOutput(name, className, code){
   var newOutput = document.createElement("dl");
   var newTitle = document.createElement("dt");
   newTitle.className = className;
   newTitle.append(new Text(name));
   newOutput.append(newTitle);
   var newMessage = document.createElement("dd");
   newMessage.setInnerHtml(code, treeSanitizer: new NullTreeSanitizer());
   newOutput.append(newTitle);
   newOutput.append(newMessage);
   var output = document.getElementById("output");
   output.append(newOutput);
 }

highlight(String string, Mode mode) {
  var state = mode.startState();

  var lines = string.replaceAll(new RegExp(r'\r\n'),'\n').split('\n');
  var st = [], pos = 0;
  var indentFailures;
  for (var i = 0; i < lines.length; ++i) {
    var line = lines[i], newLine = true;
    if (mode.hasIndent) {
      var ws = new RegExp(r'^\s*').firstMatch(line)[0];
      var indent = mode.indent(state, line.substring(ws.length), null);
      if (indent != Pass && indent != ws.length) {
        if (indentFailures == null) indentFailures = [];
        indentFailures.add(
          "Indentation of line ${i + 1} is $indent expected ${ws.length}");
      }
    }
    var stream = new StringStream(line);
    if (line == "" && mode.hasBlankLine) mode.blankLine(state);
    /* Start copied code from CodeMirror.highlight */
    while (!stream.eol()) {
      int j;
      String compare;
      for (j = 0; j < 10 && stream.start >= stream.pos; j++)
        compare = mode.token(stream, state);
      if (j == 10)
        fail("Failed to advance the stream." + stream.string + " " + stream.pos);
      var substr = stream.current();
      if (compare != null && compare.indexOf(" ") > -1) compare = ((compare.split(' '))..sort()).join(' ');
      stream.start = stream.pos;
      if (pos > 0 && st[pos-1]['style'] == compare && !newLine) {
        st[pos-1]['text'] += substr;
      } else if (substr != null) {
        pos++;
        st.add({'style': compare, 'text': substr, 'state': "$state"});
      }
      // Give up when line is ridiculously long
      if (stream.pos > 5000) {
        pos++;
        st.add({'style': null, 'text': string.substring(stream.pos)});
        break;
      }
      newLine = false;
    }
  }

  return [st, indentFailures];
}

highlightOutputsDifferent(o1, o2) {
  var minLen = min(o1.length, o2.length);
  for (var i = 0; i < minLen; ++i)
    if (o1[i]['style'] != o2[i]['style'] || o1[i]['text'] != o2[i]['text']) return i;
  if (o1.length > minLen || o2.length > minLen) return minLen;
}

prettyPrintOutputTable(output, diffAt) {
  var s = '<table class="mt-output">';
  s += '<tr>';
  for (var i = 0; i < output.length; ++i) {
    var style = output[i]['style'], val = output[i]['text'];
    s +=
    '<td class="mt-token"' + (i == diffAt * 2 ? " style='background: pink'" : "") + '>' +
      '<span class="cm-' + esc("$style") + '">' +
      esc(val.replaceAll(' ','\xb7')) +  // · MIDDLE DOT
      '</span>' +
      '</td>';
  }
  s += '</tr><tr>';
  for (var i = 0; i < output.length; ++i) { // Not sure if "null" should be quoted
    var styleVal = output[i]['style'] == null ? "null" : output[i]['style'];
    s += '<td class="mt-style"><span>$styleVal</span></td>';
  }
  if (output[0]['state'] != null) {
    s += '</tr><tr class="mt-state-row" title="State AFTER each token">';
    for (var i = 0; i < output.length; ++i) {
      s += '<td class="mt-state"><pre>' + esc(output[i]['state']) + '</pre></td>';
    }
  }
  s += '</tr></table>';
  return s;
}

List varargs([_0, _1, _2, _3, _4, _5, _6, _7, _8, _9, _a, _b, _c, _d, _e]) {
  if (_e != null) return [_0, _1, _2, _3, _4, _5, _6, _7, _8, _9, _a, _b, _c, _d, _e];
  if (_d != null) return [_0, _1, _2, _3, _4, _5, _6, _7, _8, _9, _a, _b, _c, _d];
  if (_c != null) return [_0, _1, _2, _3, _4, _5, _6, _7, _8, _9, _a, _b, _c];
  if (_b != null) return [_0, _1, _2, _3, _4, _5, _6, _7, _8, _9, _a, _b];
  if (_a != null) return [_0, _1, _2, _3, _4, _5, _6, _7, _8, _9, _a];
  if (_9 != null) return [_0, _1, _2, _3, _4, _5, _6, _7, _8, _9];
  if (_8 != null) return [_0, _1, _2, _3, _4, _5, _6, _7, _8];
  if (_7 != null) return [_0, _1, _2, _3, _4, _5, _6, _7];
  if (_6 != null) return [_0, _1, _2, _3, _4, _5, _6];
  if (_5 != null) return [_0, _1, _2, _3, _4, _5];
  if (_4 != null) return [_0, _1, _2, _3, _4];
  if (_3 != null) return [_0, _1, _2, _3];
  if (_2 != null) return [_0, _1, _2];
  if (_1 != null) return [_0, _1];
  if (_0 != null) return [_0];
  return [];
}
