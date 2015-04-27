// Copyright (c) 2015, the Comid Authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library comid.mode.fold.gutter;

import 'dart:html';

import 'package:comid/codemirror.dart';
import 'package:comid/addon/fold/foldcode.dart';

initialize() {
  CodeMirror.defineOption("foldGutter", false, (CodeMirror cm, val, old) {
    if (old != false && old != Options.Init) {
      cm.clearGutter(cm.state.foldGutter.options.gutter);
      cm.state.foldGutter = null;
      cm.off(cm, "gutterClick", onGutterClick);
      cm.off(cm, "change", onChange);
      cm.off(cm, "viewportChange", onViewportChange);
      cm.off(cm, "fold", onFold);
      cm.off(cm, "unfold", onFold);
      cm.off(cm, "swapDoc", updateInViewport);
    }
    if (val != false) {
      cm.state.foldGutter = new State(parseOptions(val));
      updateInViewport(cm);
      cm.on(cm, "gutterClick", onGutterClick);
      cm.on(cm, "change", onChange);
      cm.on(cm, "viewportChange", onViewportChange);
      cm.on(cm, "fold", onFold);
      cm.on(cm, "unfold", onFold);
      cm.on(cm, "swapDoc", updateInViewport);
    }
  });
}

class State {
  FoldOptions options;
  var from, to, changeUpdate;

  State(this.options) {
    this.from = this.to = 0;
  }
}

class FoldOptions {
  static List<String> _optNames = ['gutter', 'indicatorOpen', 'indicatorFolded',
      'updateViewportTimeSpan', 'foldOnChangeTimeSpan', 'rangeFinder'];

  String gutter, indicatorOpen, indicatorFolded;
  int updateViewportTimeSpan, foldOnChangeTimeSpan;
  Function rangeFinder;

  bool containsKey(var name) => _optNames.contains(name);

  dynamic operator [](name) {
    switch(name) {
      case 'gutter': return gutter;
      case 'indicatorOpen': return indicatorOpen;
      case 'indicatorFolded': return indicatorFolded;
      case 'updateViewportTimeSpan': return updateViewportTimeSpan;
      case 'foldOnChangeTimeSpan': return foldOnChangeTimeSpan;
      case 'rangeFinder': return rangeFinder;
    }
    return null;
  }
}

FoldOptions parseOptions(var optsIn) {
  FoldOptions opts = new FoldOptions();
  if (optsIn != true) {
    opts.gutter = optsIn['gutter'];
    opts.indicatorOpen = optsIn['indicatorOpen'];
    opts.indicatorFolded = optsIn['indicatorFolded'];
    opts.foldOnChangeTimeSpan = optsIn['foldOnChangeTimeSpan'];
    opts.updateViewportTimeSpan = optsIn['updateViewportTimeSpan'];
  }
  if (opts.gutter == null) opts.gutter = "CodeMirror-foldgutter";
  if (opts.indicatorOpen == null) opts.indicatorOpen = "CodeMirror-foldgutter-open";
  if (opts.indicatorFolded == null) opts.indicatorFolded = "CodeMirror-foldgutter-folded";
  if (opts.updateViewportTimeSpan == null) opts.updateViewportTimeSpan = 400;
  if (opts.foldOnChangeTimeSpan == null) opts.foldOnChangeTimeSpan = 600;
  return opts;
}

TextMarker isFolded(CodeMirror cm, line) {
  var marks = cm.findMarksAt(new Pos(line));
  for (var i = 0; i < marks.length; ++i) {
    if (marks[i].isFold && marks[i].find().from.line == line) return marks[i];
  }
  return null;
}

Element marker(spec) {
  if (spec is String) {
    var elt = document.createElement("div");
    elt.className = spec + " CodeMirror-guttermarker-subtle";
    return elt;
  } else {
    return (spec as Element).clone(true);
  }
}

void updateFoldInfo(CodeMirror cm, from, to) {
  var opts = cm.state.foldGutter.options, cur = from;
  var minSize = foldOption(cm, opts, "minFoldSize");
  var func = foldOption(cm, opts, "rangeFinder");
  cm.doc.eachLine(from, to, (line) {
    var mark = null;
    if (isFolded(cm, cur) != null) {
      mark = marker(opts.indicatorFolded);
    } else {
      var pos = new Pos(cur, 0);
      Reach range = func != null ? func(cm, pos) : null;
      if (range != null && range.to.line - range.from.line >= minSize)
        mark = marker(opts.indicatorOpen);
    }
    cm.setGutterMarker(line, opts.gutter, mark);
    ++cur;
  });
}

void updateInViewport(CodeMirror cm) {
  var vp = cm.getViewport(), state = cm.state.foldGutter;
  if (state == null) return;
  cm.operation(cm, () {
    updateFoldInfo(cm, vp.from, vp.to);
  })();
  state.from = vp.from; state.to = vp.to;
}

void onGutterClick(CodeMirror cm, line, gutter, MouseEvent e) {
  var state = cm.state.foldGutter;
  if (state == null) return;
  var opts = state.options;
  if (gutter != opts.gutter) return;
  var folded = isFolded(cm, line);
  if (folded != null) folded.clear();
  else foldCode(cm, new Pos(line, 0), opts.rangeFinder);
}

void onChange(CodeMirror cm, Change change) {
  var state = cm.state.foldGutter;
  if (state == null) return;
  var opts = state.options;
  state.from = state.to = 0;
  clearTimeout(state.changeUpdate);
  state.changeUpdate = setTimeout(() { updateInViewport(cm); }, opts.foldOnChangeTimeSpan);
}

void onViewportChange(CodeMirror cm, int from, int to) {
  var state = cm.state.foldGutter;
  if (state == null) return;
  var opts = state.options;
  clearTimeout(state.changeUpdate);
  state.changeUpdate = setTimeout(() {
    var vp = cm.getViewport();
    if (state.from == state.to || vp.from - state.to > 20 || state.from - vp.to > 20) {
      updateInViewport(cm);
    } else {
      cm.operation(cm, () {
        if (vp.from < state.from) {
          updateFoldInfo(cm, vp.from, state.from);
          state.from = vp.from;
        }
        if (vp.to > state.to) {
          updateFoldInfo(cm, state.to, vp.to);
          state.to = vp.to;
        }
      })();
    }
  }, opts.updateViewportTimeSpan);
}

void onFold(CodeMirror cm, Pos from, Pos to) {
  var state = cm.state.foldGutter;
  if (state == null) return;
  var line = from.line;
  if (line >= state.from && line < state.to)
    updateFoldInfo(cm, line, line + 1);
}
