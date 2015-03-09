// Copyright (c) 2015, the Comid Authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

part of comid;

class Mode {
  String name;
  var helperType;
  Mode mode;
  ModeState state;
  Map props;

  Mode({this.name, this.mode, this.state, this.helperType});

  String token(StringStream stream, [dynamic state]) {
    stream.skipToEnd();
    return null;
  }

  operator [](prop) => props == null ? null : props[prop];
  operator []=(prop, val) {
    if (props == null) props = {};
    props[prop] = val;
  }

  // TODO Need to eliminate these; too error-prone for general use.
  bool get hasIndent => false;
  bool get hasInnerMode => false;
  bool get hasStartState => false;
  bool get hasFlattenSpans => false;
  bool get hasBlankLine => false;
  bool get hasElectricChars => false;
  bool get hasElectricInput => false;

  bool get flattenSpans => throw new StateError("flattenSpans not defined");
  bool get opaque => false;

  void blankLine(dynamic state) {
  }

  ModeState copyState(ModeState state) {
    return state.copy();
  }

  dynamic indent(dynamic state, String prefix, String line) {
    return Pass;
  }

  Mode innerMode([var state]) { // bool or ModeState
    return null;
  }

  ModeState startState([a1, a2]) {
    return state = new ModeState();
  }

  String get electricChars=> "";

  RegExp get electricInput => null;

  // Options to control comment toggle
  String get lineComment => null;
  String get blockCommentStart => null;
  String get blockCommentEnd => null;
  String get blockCommentLead => null;
  String get blockCommentContinue => null;
}

class ModeState {

  ModeState copy() {
    return newInstance()..copyValues(this);
  }

  ModeState newInstance() {
    return new ModeState();
  }

  void copyValues(ModeState old) {
  }

  String toString() {
    return "ModeState subclasses should construct a debug string";
  }
}