// Copyright (c) 2015, the Comid Authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library comid.showhints.xml;

import 'dart:math';

import 'package:comid/codemirror.dart';
import 'package:comid/addon/edit/show_hint.dart';
import 'package:comid/addon/mode/xml.dart';

getHints(CodeMirror cm, Map options) {
  Map tags;
  String quote;
  if (options is Map) {
    tags = options['schemaInfo'];
    quote = options['quoteChar'];
    if (quote == null) quote = '"';
  }
  if (tags == null) {
    return null;
  }
  var cur = cm.getCursor();
  var token = cm.getTokenAt(cur);
  if (token.end > cur.char) {
    token.end = cur.char;
    token.string = token.string.substring(0, cur.char - token.start);
  }
  var innr = cm.innerMode(cm.doc.getMode(), token.state);
  if (innr.mode.name != "xml") {
    return null;
  }
  XmlMode inner = innr as XmlMode;
  List<String> result = [];
  bool replaceToken = false;
  String prefix;
  bool tag = new RegExp(r'\btag\b').hasMatch(token.type) &&
      !new RegExp(r'>$').hasMatch(token.string);
  bool tagName = tag ? new RegExp(r'^\w').hasMatch(token.string) : false;
  int tagStart;
  String tagType;

  if (tagName) {
    var before = cm.getLine(cur.line);
    before = before.substring(max(0, token.start - 2), token.start);
    tagType = new RegExp(r'<\/$').hasMatch(before)
        ? "close" : new RegExp(r'<$').hasMatch(before) ? "open" : null;
    if (tagType != null) tagStart = token.start - (tagType == "close" ? 2 : 1);
  } else if (tag && token.string == "<") {
    tagType = "open";
  } else if (tag && token.string == "</") {
    tagType = "close";
  }

  if (!tag && inner.state.tagName == null || tagType != null) {
    if (tagName) {
      prefix = token.string;
    }
    replaceToken = tagType != null;
    var cx = inner.state.context;
    var curTag = cx != null ? tags[cx.tagName] : null;
    var childList = cx != null
        ? (curTag != null ? curTag.children : null) : tags["!top"];
    if (childList != null && tagType != "close") {
      for (var i = 0; i < childList.length; ++i) {
        if (prefix == null || childList[i].lastIndexOf(prefix, 0) == 0) {
          result.add("<" + childList[i]);
        }
      }
    } else if (tagType != "close") {
      for (var name in tags.keys)
        if (name != "!top" && name != "!attrs" &&
            (prefix == null || name.lastIndexOf(prefix, 0) == 0))
          result.add("<" + name);
    }
    if (cx != null && (prefix == null || tagType == "close" &&
                          cx.tagName.lastIndexOf(prefix, 0) == 0)) {
      result.add("</" + cx.tagName + ">");
    }
  } else {
    // Attribute completion
    Map curTag = tags[inner.state.tagName];
    Map attrs = curTag != null ? curTag['attrs'] : null;
    Map globalAttrs = tags["!attrs"];
    if (attrs == null && globalAttrs == null) {
      return null;
    }
    if (attrs == null) {
      attrs = globalAttrs;
    } else if (globalAttrs != null) { // Combine tag-local and global attributes
      var set = {};
      for (var nm in globalAttrs.keys) set[nm] = globalAttrs[nm];
      for (var nm in attrs.keys) set[nm] = attrs[nm];
      attrs = set;
    }
    if (token.type == "string" || token.string == "=") { // A value
      var before = cm.getRange(new Pos(cur.line, max(0, cur.char - 60)),
                               new Pos(cur.line, token.type == "string"
                                    ? token.start : token.end));
      var atName = new RegExp('([^\\s\\u00a0=<>\"\']+)=\$').firstMatch(before);
      var atValues;
      if (atName == null || !attrs.containsKey(atName[1]) ||
          (atValues = attrs[atName[1]]) == null) {
        return null;
      }
      // Functions can be used to supply values for autocomplete widget.
      if (atValues is Function) atValues = atValues.call(cm);
      if (token.type is String) {
        prefix = token.string;
        var n = 0;
        if (new RegExp('[\'\"]').hasMatch(token.string.substring(0, 1))) {
          quote = token.string.substring(0, 1);
          prefix = token.string.substring(1);
          n++;
        }
        var len = token.string.length;
        if (new RegExp('[\'\"]').hasMatch(token.string.substring(len - 1, len))) {
          quote = token.string.substring(len - 1, len);
          prefix = token.string.substring(n, len - 2);
        }
        replaceToken = true;
      }
      for (var i = 0; i < atValues.length; ++i) {
        if (prefix == null || atValues[i].lastIndexOf(prefix, 0) == 0) {
          result.add(quote + atValues[i] + quote);
        }
      }
    } else { // An attribute name
      if (token.type == "attribute") {
        prefix = token.string;
        replaceToken = true;
      }
      for (var attr in attrs.keys) {
        if ((prefix == null || attr.lastIndexOf(prefix, 0) == 0)) {
          result.add(attr);
        }
      }
    }
  }
  var from = cur, to = cur;
  if (replaceToken) {
    from = new Pos(cur.line, tagStart == null ? token.start : tagStart);
    to = new Pos(cur.line, token.end);
  }
  return new ProposalList(list: result, from: from, to: to);
}

initialize() {
  XmlMode.initialize();
  CodeMirror.registerHelper("hint", "xml", getHints);
}

