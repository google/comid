// Copyright (c) 2015, the Comid Authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library comid.mode.fold;

import 'dart:html';

import 'package:comid/codemirror.dart';

void doFold(CodeMirror cm, var posi, var opts, String force) {
  Function finder;
  Map options;
  if (opts is Function) {
    finder = opts;
    options = null;
  } else {
    options = opts;
    finder = getOption(cm, options, "rangeFinder");
  }
  Pos pos;
  if (posi is num) pos = new Pos(posi, 0); else pos = posi;
  var minSize = getOption(cm, options, "minFoldSize");

  Reach getRange(allowFolded) {
    Reach range = finder(cm, pos);
    if (range == null || range.to.line - range.from.line < minSize) return null;
    var marks = cm.findMarksAt(range.from);
    for (var i = 0; i < marks.length; ++i) {
      if (marks[i].isFold && force != "fold") {
        if (!allowFolded) return null;
        range = new ReachCleared(range.from, range.to);
        marks[i].clear();
      }
    }
    return range;
  }

  var range = getRange(true);
  if (getOption(cm, options, "scanUp")) {
    while (!range && pos.line > cm.firstLine()) {
      pos = new Pos(pos.line - 1, 0);
      range = getRange(false);
    }
  }
  if (range == null || range.cleared || force == "unfold") return;

  var myWidget = makeWidget(cm, options);
  TextMarker myRange;
  cm.on(myWidget, "mousedown", (e) {
    myRange.clear();
    cm.e_preventDefault(e);
  });
  myRange = cm.markText(range.from, range.to,
    replacedWith: myWidget,
    clearOnEnter: true
  );
  myRange.isFold = true;
  myRange.on(myRange, "clear", (from, to) {
    cm.signal(cm, "unfold", cm, from, to);
  });
  cm.signal(cm, "fold", cm, range.from, range.to);
}

Element makeWidget(cm, options) {
  var widget = getOption(cm, options, "widget");
  if (widget is String) {
    var text = new Text(widget);
    widget = document.createElement("span");
    widget.append(text);
    widget.className = "CodeMirror-foldmarker";
  }
  return widget;
}

void foldCode(CodeMirror cm, Pos pos, [options, force]) {
  doFold(cm, pos, options, force);
}

bool isFolded(CodeMirror cm, Pos pos) {
  var marks = cm.findMarksAt(pos);
  for (var i = 0; i < marks.length; ++i) {
    if (marks[i].isFold) return true;
  }
  return false;
}
dynamic foldOption(CodeMirror cm, options, String name) {
  return getOption(cm, options, name);
}
dynamic getOption(CodeMirror cm, options, String name) {
  if (options != null && options.containsKey(name))
    return options[name];
  var editorOptions = cm.options.foldOptions;
  if (editorOptions != null && editorOptions.containsKey(name))
    return editorOptions[name];
  return defaultOptions[name];
}

Reach autoFoldHelper(CodeMirror cm, Pos start) {
  var helpers = cm.getHelpers(start, "fold");
  for (var i = 0; i < helpers.length; i++) {
    var cur = helpers[i](cm, start);
    if (cur != null) return cur;
  }
  return null;
}

var defaultOptions = {
  'rangeFinder': autoFoldHelper,
  'widget': "\u2194",
  'minFoldSize': 0,
  'scanUp': false
};

// Clumsy backwards-compatible interface
//CodeMirror.newFoldFunction = function(rangeFinder, widget) {
//  return function(cm, pos) { doFold(cm, pos, {rangeFinder: rangeFinder, widget: widget}); };
//};

initialize() {
  // New-style interface

  CodeMirror.defaultCommands['toggleFold'] = ([CodeMirror cm]) {
    foldCode(cm, cm.getCursor());
  };
  CodeMirror.defaultCommands['fold'] = ([CodeMirror cm]) {
    foldCode(cm, cm.getCursor(), null, "fold");
  };
  CodeMirror.defaultCommands['unfold'] = ([CodeMirror cm]) {
    foldCode(cm, cm.getCursor(), null, "unfold");
  };
  CodeMirror.defaultCommands['foldAll'] = ([CodeMirror cm]) {
    cm.operation(cm, () {
      for (var i = cm.firstLine(), e = cm.lastLine(); i <= e; i++)
        foldCode(cm, new Pos(i, 0), null, "fold");
    })();
  };
  CodeMirror.defaultCommands['unfoldAll'] = ([CodeMirror cm]) {
    cm.operation(cm, () {
      for (var i = cm.firstLine(), e = cm.lastLine(); i <= e; i++)
        foldCode(cm, new Pos(i, 0), null, "unfold");
    })();
  };

  CodeMirror.registerHelper("fold", "combine", (List<Function> funcs) {
    //var funcs = Array.prototype.slice.call(arguments, 0);
    return (CodeMirror cm, start) {
      for (var i = 0; i < funcs.length; ++i) {
        var found = funcs[i](cm, start);
        if (found) return found;
      }
    };
  });

  CodeMirror.registerHelper("fold", "auto", autoFoldHelper);

  CodeMirror.defineOption("foldOptions", null);

  //CodeMirror.defineExtension("foldOption", (options, name) {
  //  return getOption(this, options, name);
  //});
}
