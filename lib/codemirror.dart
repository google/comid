// Copyright (c) 2015, the Comid Authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// The comid library.
library comid;

import 'dart:async' show Timer, Stream, StreamController, Future;
import 'dart:collection';
import 'dart:html' hide Document, Range, Selection;
import 'dart:html' as html show Document, Range, Selection;
import 'dart:math';

part 'src/codeeditor.dart';
part 'src/delayed.dart';
part 'src/display.dart';
part 'src/document.dart';
part 'src/environ.dart';
part 'src/event.dart';
part 'src/options.dart';
part 'src/util.dart';
part 'src/utilext.dart';
part 'src/mode.dart';
part 'src/inputstyle.dart';

typedef void Handler(CodeMirror cm, Object dflt, Object old);
typedef void CommandHandler([CodeMirror cm]);
typedef dynamic LineFn(Line line);
typedef Span RangeFn(Range range);

abstract class CodeMirror implements EventManager {
  /**
   * It contains a string that indicates the version of the library. This is a
   * triple of integers "major.minor.patch", where patch is zero for releases,
   * and something else (usually one) for dev snapshots.
   */
  static const version = CodeEditor.version;

  static defineOption(String name, Object deflt,
      [Handler handler = null, bool notOnInit = false]) {
    Options.option(name, deflt, handler, notOnInit);
    defaults = Options.defaultOptions;
  }
  static Options defaults = Options.defaultOptions;
  // Add new, global commands to defaultCommands BEFORE instantiating an editor.
  static Map<String, CommandHandler> defaultCommands = CodeEditor.defaultCommands;

  factory CodeMirror(var place, [var opts]) => new CodeEditor(place, opts);

  static Mode getMode(dynamic options, dynamic spec) {
    CodeEditor.initMode();
    return CodeEditor.getMode(options, spec);
  }
  static defineMode(name, var mode) { CodeEditor.defineMode(name, mode); }
  static resolveMode(dynamic spec) => CodeEditor.resolveMode(spec);
  static defineSimpleMode(name, states, [props]) { CodeEditor.defineSimpleMode(name, states, props); }
  static defineMIME(mime, spec) { CodeEditor.defineMIME(mime, spec); }
  static registerHelper(type, name, value) { CodeEditor.registerHelper(type, name, value); }
  static registerGlobalHelper(type, name, predicate, value) { CodeEditor.registerGlobalHelper(type, name, predicate, value); }
  static defineExtension(name, func) { throw new StateError("Extensions not supported"); }

  static fromTextArea(TextAreaElement textarea, dynamic options) {
    return new CodeEditorArea.fromTextArea(textarea,  options);
  }

  static getNamedHelper(String help, String name) {
    var names = CodeEditor.helpers[help];
    if (names == null) return null;
    return names[name];
  }

  Doc get doc;
  Display get display;
  Options get options;
  Object get curOp;
  EditState get state;

  void signal(dynamic emitter, String type, [a1, a2, a3, a4]);
  void loadMode();
  void wrappingChanged();
  void updateScrollbars();
  void guttersChanged();
  void updateSelection();
  void resetModeState();
  void refresh();
  void onBlur(CodeMirror editor);
  void onFocus(CodeMirror editor);
  dynamic getKeyMap(dynamic k);
  void themeChanged();
  void clearCaches();
  void regChange([int from = -1, int to = -1, int lendiff = 0]);
  void regLineChange(int line, String type);
  dynamic runInOp(cm, f);
  void focus();
  void setOption(String option, Object value);
  Object getOption(String option);
  Doc getDoc();
  void addKeyMap(dynamic map, [bool bottom = false]);
  bool removeKeyMap(dynamic map);
  void addOverlay(dynamic spec, [dynamic options]);
  void removeOverlay(dynamic spec);
  void indentLine(int n, [dynamic dir, bool aggressive]);
  void indentSelection(dynamic how);
  static dynamic copyState(Mode mode, dynamic state)
      => CodeEditor.copyState(mode, state);
  static int cmpPos(Pos a, Pos b) => a.compareTo(b);

  /**
   * Given a mode and a state (for that mode), find the inner mode and
   * state at the position that the state refers to.
   */
  Mode innerMode(Mode mode, var state);

  /**
   * Retrieves information about the token the current mode found before the
   * given posi)tion.
   *
   * If [precise] is true, the token will be guaranteed to be accurate based on
   * recent edits. If false or not specified, the token will use cached state
   * information, which will be faster but might not be accurate if edits were
   * recently made and highlighting has not yet completed.
   */
  Token getTokenAt(Pos pos, [bool precise = false]);

  /**
   * This is similar to getTokenAt, but collects all tokens for a given line
   * into an array. It is much cheaper than repeatedly calling getTokenAt,
   * which re-parses the part of the line before the token for every call.
   */
  List<Token> getLineTokens(int line, [bool precise = false]);

  /**
   * This is a (much) cheaper version of getTokenAt useful for when you just
   * need the type of the token at a given position, and no other information.
   * Will return null for unstyled tokens, and a string, potentially containing
   * multiple space-separated style names, otherwise.
   */
  String getTokenTypeAt(Pos pos);

  /**
   * Gets the inner mode at a given position. This will return the same as
   * getMode for simple modes, but will return an inner mode for nesting modes
   * (such as htmlmixed).
   *
   * The returned mode is a `JsObject`.
   */
  Mode getModeAt(Pos pos);

  /**
   * Returns the first applicable helper value.
   */
  Object getHelper(Pos pos, String type);

  /**
   * Fetch the set of applicable helper values for the given position. Helpers
   * provide a way to look up functionality appropriate for a mode. The type
   * argument provides the helper namespace (see registerHelper), in which the
   * values will be looked up. When the mode itself has a property that
   * corresponds to the type, that directly determines the keys that are used to
   * look up the helper values (it may be either a single string, or an array of
   * strings). Failing that, the mode's helperType property and finally the
   * mode's name are used.
   *
   * For example, the JavaScript mode has a property fold containing "brace".
   * When the brace-fold addon is loaded, that defines a helper named brace in
   * the fold namespace. This is then used by the foldcode addon to figure out
   * that it can use that folding function to fold JavaScript code.
   *
   * When any 'global' helpers are defined for the given namespace, their
   * predicates are called on the current mode and editor, and all those that
   * declare they are applicable will also be added to the array that is
   * returned.
   */
  dynamic getHelpers(Pos pos, String type);
  dynamic getStateAfter([int ln, bool precise = false]);
  Rect cursorCoords(var start, [String mode]);
  Rect charCoords(Pos pos, [String mode]);
  PosWithInfo coordsChar(Loc coords, [String mode]);
  int lineAtHeight(int height, [String mode]);
  num heightAtLine(dynamic line, [String mode]);
  num defaultTextHeight();
  num defaultCharWidth();

  /**
   * Sets the gutter marker for the given gutter (identified by its CSS class,
   * see the gutters option) to the given value. Value can be either null, to
   * clear the marker, or a DOM element, to set it. The DOM element will be
   * shown in the specified gutter next to the specified line.
   */
  LineHandle setGutterMarker(dynamic lineNo, String gutterID, Element value);

  /**
   * Remove all gutter markers in the gutter with the given ID.
   */
  void clearGutter(Object gutterID);

  /**
   * Adds a line widget, an element shown below a line, spanning the whole of
   * the editor's width, and moving the lines below it downwards. [line] should
   * be either an integer or a [LineHandle], and node should be a DOM node,
   * which will be displayed below the given line.
   *
   * [coverGutter]: whether the widget should cover the gutter.
   * [noHScroll]: whether the widget should stay fixed in the face of horizontal
   * scrolling.
   * [above]: causes the widget to be placed above instead of below the text of
   * the line.
   * [handleMouseEvents]: determines whether the editor will capture mouse and
   * drag events occurring in this widget. Default is false — the events will be
   * left alone for the default browser handler, or specific handlers on the
   * widget, to capture.
   * [insertAt]: by default, the widget is added below other widgets for the
   * line. This option can be used to place it at a different position (zero for
   * the top, N to put it after the Nth other widget). Note that this only has
   * effect once, when the widget is created.
   */
  LineWidget addLineWidget(dynamic handle, Node node,
      {coverGutter: false, noHScroll: false,
      above: false, handleMouseEvents: false, insertAt: -1});
  void removeLineWidget(LineWidget widget);
  LineInfo lineInfo(dynamic line);
  Viewport getViewport();

  /**
   * Puts node, which should be an absolutely positioned DOM node, into the
   * editor, positioned right below the given {line, ch} position. When
   * scrollIntoView is true, the editor will ensure that the entire node is
   * visible (if possible). To remove the widget again, simply use DOM methods
   * (move it somewhere else, or call removeChild on its parent).
   */
  void addWidget(Pos pos, Element node, [bool scroll, String vert, String horiz]);
  void triggerOnKeyDown(e);
  void triggerOnKeyPress(e);
  void triggerOnKeyUp(e);
  void execCommand(String cmd);
  Pos findPosH(Pos from, int amount, String unit, [bool visually]);
  void moveH(dir, unit);
  void deleteH(dir, unit);
  PosClipped findPosV(Pos from, int amount, String unit, [goalColumn]);
  void moveV(dir, unit);
  Range findWordAt(PosWithInfo pos);
  void toggleOverwrite([bool value]);

  /**
   * Scroll the editor to a given (pixel) position. Both arguments may be left
   * as null or undefined to have no effect.
   */
  void scrollTo(num x, num y);
  ScrollInfo getScrollInfo();
  void scrollIntoView(range, [margin]);

  /**
   * Programatically set the size of the editor (overriding the applicable CSS
   * rules). [width] and [height] can be either numbers (interpreted as pixels)
   * or CSS units ("100%", for example). You can pass `null` for either of them
   * to indicate that that dimension should not be changed.
   */
  void setSize([dynamic width, dynamic height]);
  dynamic doOperation(f); // TODO Should be 'operation'
  Doc swapDoc(Doc doc);
  TextAreaElement getInputField();
  DivElement getWrapperElement();
  DivElement getScrollerElement();
  DivElement getGutterElement();

  /**
   * Can be used to mark a range of text with a specific CSS class name.
   *
   * [className]: assigns a CSS class to the marked stretch of text.
   * [inclusiveLeft]: determines whether text inserted on the left of the marker
   * will end up inside or outside of it.
   * [inclusiveRight]: like inclusiveLeft, but for the right side.
   * [atomic]: atomic ranges act as a single unit when cursor movement is
   * concerned — i.e. it is impossible to place the cursor inside of them. In
   * atomic ranges, inclusiveLeft and inclusiveRight have a different meaning —
   * they will prevent the cursor from being placed respectively directly before
   * and directly after the range.
   * [collapsed]: collapsed ranges do not show up in the display. Setting a
   * range to be collapsed will automatically make it atomic.
   * [clearOnEnter]: when enabled, will cause the mark to clear itself whenever
   * the cursor enters its range. This is mostly useful for text - replacement
   * widgets that need to 'snap open' when the user tries to edit them. The
   * "clear" event fired on the range handle can be used to be notified when
   * this happens.
   * [clearWhenEmpty]: determines whether the mark is automatically cleared when
   * it becomes empty. Default is true.
   * [replacedWith]: use a given node to display this range. Implies both
   * collapsed and atomic. The given DOM node must be an inline element (as
   * opposed to a block element).
   * [handleMouseEvents]: when replacedWith is given, this determines whether
   * the editor will capture mouse and drag events occurring in this widget.
   * Default is false — the events will be left alone for the default browser
   * handler, or specific handlers on the widget, to capture.
   * [readOnly]: a read-only span can, as long as it is not cleared, not be
   * modified except by calling setValue to reset the whole document. Note:
   * adding a read-only span currently clears the undo history of the editor,
   * because existing undo events being partially nullified by read-only spans
   * would corrupt the history (in the current implementation).
   * [addToHistory]: when set to true (default is false), adding this marker
   * will create an event in the undo history that can be individually undone
   * (clearing the marker).
   * [startStyle]: can be used to specify an extra CSS class to be applied to
   * the leftmost span that is part of the marker.
   * [endStyle]: equivalent to startStyle, but for the rightmost span.
   * [css] a string of CSS to be applied to the covered text. For example
   * "color: #fe3".
   * [title]: when given, will give the nodes created for this span a HTML title
   * attribute with the given value.
   * [shared]: when the target document is linked to other documents, you can
   * set shared to true to make the marker appear in all documents. By default,
   * a marker appears only in its target document.
   */
  AbstractTextMarker markText(from, to,
        {collapsed: false, clearWhenEmpty: false, clearOnEnter: false,
        replacedWith, handleMouseEvents: false, addToHistory: false,
        className, title, startStyle, endStyle, atomic: false, readOnly: false,
        inclusiveLeft: false,  inclusiveRight: false, shared: false,
        insertLeft: false, widgetNode, css});

  /**
   * Inserts a bookmark, a handle that follows the text around it as it is being
   * edited, at the given position. A bookmark has two methods find() and
   * clear(). The first returns the current position of the bookmark, if it is
   * still in the document, and the second explicitly removes the bookmark.
   *
   * [widget] can be used to display a DOM node at the current location of the
   * bookmark (analogous to the replacedWith option to markText). [insertLeft]:
   * by default, text typed when the cursor is on top of the bookmark will end
   * up to the right of the bookmark. Set this option to true to make it go to
   * the left instead. [shared]: when the target document is linked to other
   * documents, you can set shared to true to make the marker appear in all
   * documents. By default, a marker appears only in its target document.
   */
  AbstractTextMarker setBookmark(Pos pos,
        {widget, insertLeft: false, shared: false});

  /**
   * Compute the position of the end of a change (its 'to' property
   * refers to the pre-change end).
   */
  Pos changeEnd(Change change);

  /**
   * Set the cursor position. See Doc.setCursor() for the optional-argument
   * version. Will replace all selections with a single, empty selection at
   * the given position. The supported options are the same as for setSelection.
   */
  void setCursor(Pos pos, {bias, origin, scroll: true, clearRedo});

  Stream get onChange;
  Stream get onChanges;
  Stream get onRefresh;
  Stream get onScroll;
  Stream get onMarkerAdded;
  Stream get onOverwriteToggle;
  Stream get onCursorActivity;

  /**
   * This method should be called if #onChange or other Dart-like event
   * registering methods were used to add an event listener to an editor object.
   * Directly calling CodeMirror's #on method does not require #dispose.
   */
  void dispose();

  /**
   * Register an event handler for the given [emitter] for events named
   * [type]. The [callback] will be triggered when the event fires.
   */
  void on(dynamic emitter, String type, Function f);

  /**
   * Unregister an event handler by removing the [callback] from the list
   * of handlers for the event named [type] for the given [emitter].
   */
  void off(dynamic emitter, String type, Function f);

  Map<String, Function> get commands;
  dynamic operation(cm, f); // TODO This is too weird to make public.

  // Duplicate of Doc public API, for convenience.

  /**
   * Retrieve one end of the primary selection. start is a an optional string
   * indicating which end of the selection to return. It may be "from", "to",
   * "head" (the side of the selection that moves when you press shift+arrow),
   * or "anchor" (the fixed side of the selection). Omitting the argument is the
   * same as passing "head". A {line, ch} object will be returned.
   */
  Pos getCursor([dynamic start]);

  /**
   * Create a new document that's linked to the target document.
   * Linked documents will stay in sync (changes to one are also
   * applied to the other) until <a href="#unlinkDoc">unlinked</a>.
   * These are the options that are supported:
   * [sharedHist] When turned on, the linked copy will share an undo
   * history with the original. Thus, something done in one of
   * the two can be undone in the other, and vice versa.
   * [from] [to] Can be given to make the new document a subview of the
   * original. Subviews only show a given range of lines. Note
   * that line coordinates inside the subview will be consistent
   * with those of the parent, so that for example a subview
   * starting at line 10 will refer to its first line as line 10, not 0.
   * [mode] By default, the new document inherits the mode of the
   * parent. This option can be set tomode spec to give it a
   * different mode.
   */
  Doc linkedDoc({bool sharedHist: false, int from: -1, int to: -1, Object mode});

  /**
   * Break the link between two documents. After calling this,
   * changes will no longer propagate between the documents, and, if
   * they had a shared history, the history will become separate.
   */
  void unlinkDoc(dynamic other);

  /**
   * Get the current editor content. You can pass it an optional
   * argument to specify the string to be used to separate lines
   * (defaults to [:"\n":]).
   */
  String getValue([String lineSep]);

  /**
   * Set the editor content.
   */
  void setValue(String code);

  /**
   * Replace the part of the document between [from] and [to] with the given
   * string. [to] can be left off to simply insert the string at position
   * [from].
   *
   * When origin is given, it will be passed on to "change" events, and its
   * first letter will be used to determine whether this change can be merged
   * with previous history events, in the way described for selection origins.
   */
  void replaceRange(String code, Pos from, [Pos to, String origin]);

  /**
   * Get the text between the given points in the editor, which should be
   * {line, ch} objects. An optional third argument can be given to indicate the
   * line separator string to use (defaults to "\n").
   */
  String getRange(Pos from, Pos to, [String lineSep = "\n"]);

  /**
   * Get the content of line n.
   */
  String getLine(int lineNo);

  /**
   * Fetches the line handle for the given line number.
   */
  LineHandle getLineHandle(int lineNo);

  /**
   * Given a line handle, returns the current position of that line (or `null`
   * when it is no longer in the document).
   */
  int getLineNumber(LineHandle line);

  LineHandle getLineHandleVisualStart(dynamic line);

  /**
   * Get the number of lines in the editor.
   */
  int lineCount();

  /**
   * Get the first line of the editor. This will usually be zero but for linked
   * sub-views, or documents instantiated with a non-zero first line, it might
   * return other values.
   */
  int firstLine();

  /**
   * Get the last line of the editor. This will usually be doc.lineCount() - 1,
   * but for linked sub-views, it might return other values.
   */
  int lastLine();

  bool isLine(int l);

  /**
   * Retrieves a list of all current selections. These will
   * always be sorted, and never overlap (overlapping selections are
   * merged). Each Range object in the array contains [:anchor:]
   * and [:head:] properties referring to [:{line, ch}:] Pos objects.</dd>
   */
  List<Range> listSelections();

  /**
   * Return true if any text is selected.
   */
  bool somethingSelected();

  /**
   * Set a single selection range. anchor and head should be {line, ch} objects.
   * head defaults to anchor when not given. These options are supported:
   *
   * `scroll`: determines whether the selection head should be scrolled into
   * view. Defaults to true.
   *
   * `origin`: detemines whether the selection history event may be merged with
   * the previous one. When an origin starts with the character +, and the last
   * recorded selection had the same origin and was similar (close in time, both
   * collapsed or both non-collapsed), the new one will replace the old one.
   * When it starts with *, it will always replace the previous event (if that
   * had the same origin). Built-in motion uses the "+move" origin.
   *
   * `bias`: determine the direction into which the selection endpoints should
   * be adjusted when they fall inside an atomic range. Can be either -1
   * (backward) or 1 (forward). When not given, the bias will be based on the
   * relative position of the old selection—the editor will try to move further
   * away from that, to prevent getting stuck.
   */
  void setSelection(Pos anchor, [Pos head, SelectionOptions options]);

  /**
   * Similar to [setSelection], but will, if shift is held or
   * the `extending` flag is set, move the
   * head of the selection while leaving the anchor at its current
   * place. [to] is optional, and can be passed to ensure
   * a region (for example a word or paragraph) will end up selected
   * (in addition to whatever lies between that region and the
   * current anchor). When multiple selections are present, all but
   * the primary selection will be dropped by this method.
   * Supports the same options as [setSelection].
   */
  void extendSelection(Pos head, [Pos other, SelectionOptions options]);

  /**
   * An equivalent of [extendSelection]
   * that acts on all selections at once.
   */
  void extendSelections(List<Pos> heads, [SelectionOptions options]);

  /**
   * Applies the given function to all existing selections, and
   * calls [extendSelections] on the result.
   */
  void extendSelectionsBy(RangeFn f, [SelectionOptions options]);

  /**
   * Sets a new set of selections. There must be at least one
   * selection in the given array. When [primary] is a
   * number, it determines which selection is the primary one. When
   * it is not given, the primary index is taken from the previous
   * selection, or set to the last range if the previous selection
   * had less ranges than the new one. Supports the same options
   * as [setSelection].
   */
  void setSelections(List<Range> ranges, [int primary, SelectionOptions options]);

  /**
   * Adds a new selection to the existing set of selections, and
   * makes it the primary selection.
   */
  void addSelection(Pos anchor, [Pos head, SelectionOptions options]);

  /**
   * Get the currently selected code. Optionally pass a line separator to put
   * between the lines in the output. When multiple selections are present, they
   * are concatenated with instances of [lineSep] in between.
   */
  dynamic getSelection([dynamic lineSep = '\n']);

  /**
   * Returns an array containing a string for each selection,
   * representing the content of the selections.
   */
  List getSelections([dynamic lineSep = '\n']);

  /**
   * Replace the selection(s) with the given string. By default, the new
   * selection ends up after the inserted text. The optional select argument can
   * be used to change this. Passing `around`: will cause the new text to be
   * selected; `start`: will collapse the selection to the start of the inserted
   * text.
   */
  void replaceSelection(String code, [String collapse, String origin]);

  /**
   * The length of the given array should be the same as the
   * number of active selections. Replaces the content of the
   * selections with the strings in the array. The [origin] argument works
   * the same as in [replaceSelection].
   */
  void replaceSelections(List<String> code, [String collapse, String origin]);

  /**
   * Undo one edit (if any undo events are stored).
   */
  void undo();

  /**
   * Redo one undone edit.
   */
  void redo();

  /**
   * Undo one edit or selection change.
   */
  void undoSelection();

  /**
   * Redo one undone edit or selection change.
   */
  void redoSelection();

  /**
   * Sets or clears the 'extending' flag, which acts similar to
   * the shift key, in that it will cause cursor movement and calls
   * to [extendSelection] to leave the selection anchor in place.
   */
  void setExtending(bool val);

  /**
   * Get the value of the 'extending' flag.
   */
  bool getExtending();

  /**
   * Returns an object with [{undo, redo}] properties,
   * both of which hold integers, indicating the amount of stored
   * undo and redo operations.
   */
  HistorySize historySize();

  /**
   * Clears the editor's undo history.
   */
  void clearHistory();

  /**
   * Set the editor content as 'clean', a flag that it will retain until it is
   * edited, and which will be set again when such an edit is undone again.
   * Useful to track whether the content needs to be saved. This function is
   * deprecated in favor of changeGeneration, which allows multiple subsystems
   * to track different notions of cleanness without interfering.
   */
  void markClean();

  /**
   * Returns a number that can later be passed to [isClean] to test whether any
   * edits were made (and not undone) in the meantime. If closeEvent is true,
   * the current history event will be 'closed', meaning it can't be combined
   * with further changes (rapid typing or deleting events are typically
   * combined).
   */
  int changeGeneration([bool forceSplit = false]);

  /**
   * Returns whether the document is currently clean, not modified since
   * initialization or the last call to [markClean] if no argument is passed, or
   * since the matching call to [changeGeneration] if a generation value is
   * given.
   */
  bool isClean([int gen]);

  /**
   * Get a (JSON-serializeable) representation of the undo history.
   */
  HistoryRecord getHistory();

  /**
   * Replace the editor's undo history with the one provided,
   * which must be a value as returned by [getHistory]. Note that
   * this will have entirely undefined results if the editor content
   * isn't also the same as it was when [getHistory] was called.
   */
  void setHistory(HistoryRecord histData);

  /**
   * Set a CSS class name for the given line. [line] can be a number or a
   * [LineHandle]. [where] determines to which element this class should be
   * applied, can can be one of "text" (the text element, which lies in front of
   * the selection), "background" (a background element that will be behind the
   * selection), "gutter" (the line's gutter space), or "wrap" (the wrapper node
   * that wraps all of the line's elements, including gutter elements).
   * [cssClass] should be the name of the class to apply.
   */
  Line addLineClass(dynamic handle, String where, String cls);

  /**
   * Remove a CSS class from a line. [line] can be a [LineHandle] or number.
   * [where] should be one of "text", "background", or "wrap" (see
   * [addLineClass]). [cssClass] can be left off to remove all classes for the
   * specified node, or be a string to remove only a specific class.
   */
  Line removeLineClass(dynamic handle, String where, [String cls]);

  /**
   * Returns an array of all the bookmarks and marked ranges present at the
   * given position.
   */
  List<TextMarker> findMarksAt(Pos pos);

  /**
   * Returns an array of all the bookmarks and marked ranges found between the
   * given positions.
   */
  List<TextMarker> findMarks(Pos from, Pos to, [Function filter]);

  /**
   * Returns an array containing all marked ranges in the document.
   */
  List<TextMarker> getAllMarks();

  void setHistoryDepth(int n);

  /**
   * Copy the content of the editor into the textarea.
   *
   * Only available if the CodeMirror instance was created using the
   * `CodeMirror.fromTextArea` constructor.
   */
  save(e);

  /**
   * Returns the textarea that the instance was based on.
   *
   * Only available if the CodeMirror instance was created using the
   * `CodeMirror.fromTextArea` constructor.
   */
  TextAreaElement getTextArea();

  /**
   * Remove the editor, and restore the original textarea (with the editor's
   * current content).
   *
   * Only available if the CodeMirror instance was created using the
   * `CodeMirror.fromTextArea` constructor.
   */
  toTextArea();
}

abstract class Doc implements EventManager {
  factory Doc(var text, var mode, [int firstLine = 0]) {
    return new Document(text, mode, firstLine);
  }

  CodeMirror get cm;
  String get content;
  Options get options;
  int get first;
  get mode;
  set mode(Object m);
  get modeOption;
  get size;
  Selection get sel;
  int get scrollTop;
  int get scrollLeft;
  void set scrollTop(int n);
  void set scrollLeft(int n);
  bool get cantEdit;
  int get cleanGeneration;
  int get frontier;
  void set frontier(int n);
  int get id;
  int get height;

  // Protocol duplicated in CodeMirror

  /**
   * Retrieve one end of the primary selection. start is a an optional string
   * indicating which end of the selection to return. It may be "from", "to",
   * "head" (the side of the selection that moves when you press shift+arrow),
   * or "anchor" (the fixed side of the selection). Omitting the argument is the
   * same as passing "head". A {line, ch} object will be returned.
   */
  Pos getCursor([dynamic start]);

  /**
   * Create a new document that's linked to the target document.
   * Linked documents will stay in sync (changes to one are also
   * applied to the other) until <a href="#unlinkDoc">unlinked</a>.
   * These are the options that are supported:
   * [sharedHist] When turned on, the linked copy will share an undo
   * history with the original. Thus, something done in one of
   * the two can be undone in the other, and vice versa.
   * [from] [to] Can be given to make the new document a subview of the
   * original. Subviews only show a given range of lines. Note
   * that line coordinates inside the subview will be consistent
   * with those of the parent, so that for example a subview
   * starting at line 10 will refer to its first line as line 10, not 0.
   * [mode] By default, the new document inherits the mode of the
   * parent. This option can be set tomode spec to give it a
   * different mode.
   */
  Doc linkedDoc({bool sharedHist: false, int from: -1, int to: -1, Object mode});

  /**
   * Break the link between two documents. After calling this,
   * changes will no longer propagate between the documents, and, if
   * they had a shared history, the history will become separate.
   */
  void unlinkDoc(dynamic other);

  /**
   * Get the current editor content. You can pass it an optional
   * argument to specify the string to be used to separate lines
   * (defaults to [:"\n":]).
   */
  String getValue([String lineSep]);

  /**
   * Set the editor content.
   */
  void setValue(String code);

  Stream get onChange;
  Stream get onChanges;

  /**
   * This method should be called if #onChange or other Dart-like event
   * registering methods were used to add an event listener to an editor object.
   * Directly calling CodeMirror's #on method does not require #dispose.
   */
  void dispose();

  /**
   * Register an event handler for the given [emitter] for events named
   * [type]. The [callback] will be triggered when the event fires.
   */
  void on(dynamic emitter, String type, Function f);

  /**
   * Unregister an event handler by removing the [callback] from the list
   * of handlers for the event named [type] for the given [emitter].
   */
  void off(dynamic emitter, String type, Function f);

  /**
   * Replace the part of the document between [from] and [to] with the given
   * string. [to] can be left off to simply insert the string at position
   * [from]. [code] may be a string or a list of strings that represent a
   * multi-line replacement.
   *
   * When origin is given, it will be passed on to "change" events, and its
   * first letter will be used to determine whether this change can be merged
   * with previous history events, in the way described for selection origins.
   */
  void replaceRange(dynamic code, Pos from, [Pos to, String origin]);

  /**
   * Get the text between the given points in the editor, which should be
   * {line, ch} objects. An optional third argument can be given to indicate the
   * line separator string to use (defaults to "\n").
   */
  String getRange(Pos from, Pos to, [String lineSep = "\n"]);

  /**
   * Get the content of line n.
   */
  String getLine(int lineNo);

  /**
   * Fetches the line handle for the given line number.
   */
  LineHandle getLineHandle(int lineNo);

  /**
   * Given a line handle, returns the current position of that line (or `null`
   * when it is no longer in the document).
   */
  int getLineNumber(LineHandle line);

  LineHandle getLineHandleVisualStart(dynamic line);

  /**
   * Get the number of lines in the editor.
   */
  int lineCount();

  /**
   * Get the first line of the editor. This will usually be zero but for linked
   * sub-views, or documents instantiated with a non-zero first line, it might
   * return other values.
   */
  int firstLine();

  /**
   * Get the last line of the editor. This will usually be doc.lineCount() - 1,
   * but for linked sub-views, it might return other values.
   */
  int lastLine();

  bool isLine(int l);

  /**
   * Retrieves a list of all current selections. These will
   * always be sorted, and never overlap (overlapping selections are
   * merged). Each Range object in the array contains [:anchor:]
   * and [:head:] properties referring to [:{line, ch}:] Pos objects.</dd>
   */
  List<Range> listSelections();

  /**
   * Return true if any text is selected.
   */
  bool somethingSelected();

  /**
   * Set a single selection range. anchor and head should be {line, ch} objects.
   * head defaults to anchor when not given. These options are supported:
   *
   * `scroll`: determines whether the selection head should be scrolled into
   * view. Defaults to true.
   *
   * `origin`: detemines whether the selection history event may be merged with
   * the previous one. When an origin starts with the character +, and the last
   * recorded selection had the same origin and was similar (close in time, both
   * collapsed or both non-collapsed), the new one will replace the old one.
   * When it starts with *, it will always replace the previous event (if that
   * had the same origin). Built-in motion uses the "+move" origin.
   *
   * `bias`: determine the direction into which the selection endpoints should
   * be adjusted when they fall inside an atomic range. Can be either -1
   * (backward) or 1 (forward). When not given, the bias will be based on the
   * relative position of the old selection—the editor will try to move further
   * away from that, to prevent getting stuck.
   */
  void setSelection(Pos anchor, [Pos head, SelectionOptions options]);

  /**
   * Similar to [setSelection], but will, if shift is held or
   * the `extending` flag is set, move the
   * head of the selection while leaving the anchor at its current
   * place. [to] is optional, and can be passed to ensure
   * a region (for example a word or paragraph) will end up selected
   * (in addition to whatever lies between that region and the
   * current anchor). When multiple selections are present, all but
   * the primary selection will be dropped by this method.
   * Supports the same options as [setSelection].
   */
  void extendSelection(Pos from, [Pos to, SelectionOptions options]);

  /**
   * An equivalent of [extendSelection]
   * that acts on all selections at once.
   */
  void extendSelections(List<Pos> heads, [SelectionOptions options]);

  /**
   * Applies the given function to all existing selections, and
   * calls [extendSelections] on the result.
   */
  void extendSelectionsBy(RangeFn f, [SelectionOptions options]);

  /**
   * Sets a new set of selections. There must be at least one
   * selection in the given array. When [primary] is a
   * number, it determines which selection is the primary one. When
   * it is not given, the primary index is taken from the previous
   * selection, or set to the last range if the previous selection
   * had less ranges than the new one. Supports the same options
   * as [setSelection].
   */
  void setSelections(List<Range> ranges, [int primary, SelectionOptions options]);

  /**
   * Adds a new selection to the existing set of selections, and
   * makes it the primary selection.
   */
  void addSelection(Pos anchor, [Pos head, SelectionOptions options]);

  /**
   * Get the currently selected code. Optionally pass a line separator to put
   * between the lines in the output. When multiple selections are present, they
   * are concatenated with instances of [lineSep] in between.
   */
  dynamic getSelection([dynamic lineSep = '\n']);

  /**
   * Returns an array containing a string for each selection,
   * representing the content of the selections.
   */
  List getSelections([dynamic lineSep = '\n']);

  /**
   * Replace the selection(s) with the given string. By default, the new
   * selection ends up after the inserted text. The optional origin argument can
   * be used to change this. Passing `around`: will cause the new text to be
   * selected; `start`: will collapse the selection to the start of the inserted
   * text.
   */
  void replaceSelection(String code, [String collapse, String origin]);

  /**
   * The length of the given array should be the same as the
   * number of active selections. Replaces the content of the
   * selections with the strings in the array. The [origin] argument works
   * the same as in [replaceSelection].
   */
  void replaceSelections(List<String> code, [String collapse, String origin]);

  /**
   * Undo one edit (if any undo events are stored).
   */
  void undo();

  /**
   * Redo one undone edit.
   */
  void redo();

  /**
   * Undo one edit or selection change.
   */
  void undoSelection();

  /**
   * Redo one undone edit or selection change.
   */
  void redoSelection();

  /**
   * Sets or clears the 'extending' flag, which acts similar to
   * the shift key, in that it will cause cursor movement and calls
   * to [extendSelection] to leave the selection anchor in place.
   */
  void setExtending(bool val);

  /**
   * Get the value of the 'extending' flag.
   */
  bool getExtending();

  /**
   * Returns an object with [{undo, redo}] properties,
   * both of which hold integers, indicating the amount of stored
   * undo and redo operations.
   */
  HistorySize historySize();

  /**
   * Clears the editor's undo history.
   */
  void clearHistory();

  /**
   * Set the editor content as 'clean', a flag that it will retain until it is
   * edited, and which will be set again when such an edit is undone again.
   * Useful to track whether the content needs to be saved. This function is
   * deprecated in favor of changeGeneration, which allows multiple subsystems
   * to track different notions of cleanness without interfering.
   */
  void markClean();

  /**
   * Returns a number that can later be passed to [isClean] to test whether any
   * edits were made (and not undone) in the meantime. If closeEvent is true,
   * the current history event will be 'closed', meaning it can't be combined
   * with further changes (rapid typing or deleting events are typically
   * combined).
   */
  int changeGeneration([bool forceSplit = false]);

  /**
   * Returns whether the document is currently clean, not modified since
   * initialization or the last call to [markClean] if no argument is passed, or
   * since the matching call to [changeGeneration] if a generation value is
   * given.
   */
  bool isClean([int gen]);

  /**
   * Get a (JSON-serializeable) representation of the undo history.
   */
  HistoryRecord getHistory();

  /**
   * Replace the editor's undo history with the one provided,
   * which must be a value as returned by [getHistory]. Note that
   * this will have entirely undefined results if the editor content
   * isn't also the same as it was when [getHistory] was called.
   */
  void setHistory(HistoryRecord histData);

  /**
   * Set a CSS class name for the given line. [line] can be a number or a
   * [LineHandle]. [where] determines to which element this class should be
   * applied, can can be one of "text" (the text element, which lies in front of
   * the selection), "background" (a background element that will be behind the
   * selection), "gutter" (the line's gutter space), or "wrap" (the wrapper node
   * that wraps all of the line's elements, including gutter elements).
   * [cssClass] should be the name of the class to apply.
   */
  Line addLineClass(dynamic handle, String where, String cls);

  /**
   * Remove a CSS class from a line. [line] can be a [LineHandle] or number.
   * [where] should be one of "text", "background", or "wrap" (see
   * [addLineClass]). [cssClass] can be left off to remove all classes for the
   * specified node, or be a string to remove only a specific class.
   */
  Line removeLineClass(dynamic handle, String where, [String cls]);

  /**
   * Returns an array of all the bookmarks and marked ranges present at the
   * given position.
   */
  List<TextMarker> findMarksAt(Pos pos);

  /**
   * Returns an array of all the bookmarks and marked ranges found between the
   * given positions.
   */
  List<TextMarker> findMarks(Pos from, Pos to, [Function filter]);

  /**
   * Returns an array containing all marked ranges in the document.
   */
  List<TextMarker> getAllMarks();

  void setHistoryDepth(int n);

  // Protocol unique to Doc
  void eachLine(dynamic from, [int to, LineFn op]);
  List<String> splitLines(String string);

  /**
   * Set the cursor position. You can either pass a single {line, ch} object, or
   * the line and the character as two separate parameters. Will replace all
   * selections with a single, empty selection at the given position. The
   * supported options are the same as for setSelection.
   */
  void setCursor(dynamic line, [int ch, SelectionOptions options]);

  /**
   * Can be used to mark a range of text with a specific CSS class name.
   *
   * [className]: assigns a CSS class to the marked stretch of text.
   * [inclusiveLeft]: determines whether text inserted on the left of the marker
   * will end up inside or outside of it.
   * [inclusiveRight]: like inclusiveLeft, but for the right side.
   * [atomic]: atomic ranges act as a single unit when cursor movement is
   * concerned — i.e. it is impossible to place the cursor inside of them. In
   * atomic ranges, inclusiveLeft and inclusiveRight have a different meaning —
   * they will prevent the cursor from being placed respectively directly before
   * and directly after the range.
   * [collapsed]: collapsed ranges do not show up in the display. Setting a
   * range to be collapsed will automatically make it atomic.
   * [clearOnEnter]: when enabled, will cause the mark to clear itself whenever
   * the cursor enters its range. This is mostly useful for text - replacement
   * widgets that need to 'snap open' when the user tries to edit them. The
   * "clear" event fired on the range handle can be used to be notified when
   * this happens.
   * [clearWhenEmpty]: determines whether the mark is automatically cleared when
   * it becomes empty. Default is true.
   * [replacedWith]: use a given node to display this range. Implies both
   * collapsed and atomic. The given DOM node must be an inline element (as
   * opposed to a block element).
   * [handleMouseEvents]: when replacedWith is given, this determines whether
   * the editor will capture mouse and drag events occurring in this widget.
   * Default is false — the events will be left alone for the default browser
   * handler, or specific handlers on the widget, to capture.
   * [readOnly]: a read-only span can, as long as it is not cleared, not be
   * modified except by calling setValue to reset the whole document. Note:
   * adding a read-only span currently clears the undo history of the editor,
   * because existing undo events being partially nullified by read-only spans
   * would corrupt the history (in the current implementation).
   * [addToHistory]: when set to true (default is false), adding this marker
   * will create an event in the undo history that can be individually undone
   * (clearing the marker).
   * [startStyle]: can be used to specify an extra CSS class to be applied to
   * the leftmost span that is part of the marker.
   * [endStyle]: equivalent to startStyle, but for the rightmost span.
   * [css] a string of CSS to be applied to the covered text. For example
   * "color: #fe3".
   * [title]: when given, will give the nodes created for this span a HTML title
   * attribute with the given value.
   * [shared]: when the target document is linked to other documents, you can
   * set shared to true to make the marker appear in all documents. By default,
   * a marker appears only in its target document.
   */
  AbstractTextMarker markText(Pos from, Pos to, [TextMarkerOptions options]);

  /**
   * Inserts a bookmark, a handle that follows the text around it as it is being
   * edited, at the given position. A bookmark has two methods find() and
   * clear(). The first returns the current position of the bookmark, if it is
   * still in the document, and the second explicitly removes the bookmark.
   *
   * [widget] can be used to display a DOM node at the current location of the
   * bookmark (analogous to the replacedWith option to markText). [insertLeft]:
   * by default, text typed when the cursor is on top of the bookmark will end
   * up to the right of the bookmark. Set this option to true to make it go to
   * the left instead. [shared]: when the target document is linked to other
   * documents, you can set shared to true to make the marker appear in all
   * documents. By default, a marker appears only in its target document.
   */
  AbstractTextMarker setBookmark(Pos pos, [BookmarkOptions options]);

  /**
   * Calculates and returns a `Position` object for a zero-based index who's
   * value is relative to the start of the editor's text. If the index is out of
   * range of the text then the returned object is clipped to start or end of
   * the text respectively.
   */
  Pos posFromIndex(int offset);
  Pos clipPos(Pos pos);
  int clipLine(int n);
  List<Pos> clipPosArray(List<Pos>array);

  /**
   * The reverse of [posFromIndex].
   */
  int indexFromPos(Pos coords);
  Doc copy([bool copyHistory = false]);
  void iterLinkedDocs(Function iterFn);

  /**
   * Gets the (outer) mode object for the editor. Note that this is distinct
   * from getOption("mode"), which gives you the mode specification, rather than
   * the resolved, instantiated mode object.
   *
   * The returned mode is a `JsObject`.
   */
  Mode getMode();
  CodeMirror getEditor();
  bool lineIsHidden(Line line);
}

abstract class Display {
  factory Display(var place, Doc doc, InputStyle input) {
    return new Displ(place, doc, input);
  }
  DivElement get wrapper;
  InputStyle get input;
  DivElement get scrollbarFiller;
  DivElement get gutterFiller;
  DivElement get lineDiv;
  DivElement get selectionDiv;
  DivElement get cursorDiv;
  DivElement get measure;
  DivElement get lineMeasure;
  DivElement get lineSpace;
  DivElement get mover;
  DivElement get sizer;
  DivElement get heightForcer;
  DivElement get gutters;
  DivElement get lineGutter;
  void set lineGutter(Node n);
  DivElement get scroller;
  int get viewFrom;
  int get viewTo;
  List get view;
  get externalMeasured;
  int get viewOffset;
  int get lastWrapHeight;
  int get lastWrapWidth;
  get updateLineNumbers;
  int get lineNumWidth;
  int get lineNumInnerWidth;
  int get lineNumChars;
  void set lineNumWidth(int n);
  void set lineNumInnerWidth(int n);
  void set lineNumChars(int n);
  bool get alignWidgets;
  int get cachedCharWidth;
  int get cachedTextHeight;
  Padding get cachedPaddingH;
  get maxLine;
  int get maxLineLength;
  bool get maxLineChanged;
  void set maxLine(l);
  void set maxLineLength(int n);
  void set maxLineChanged(bool b);
  int get wheelDX;
  int get wheelDY;
  int get wheelStartX;
  int get wheelStartY;
  bool get shift;
  void set shift(bool b);
  get selForContextMenu;
  bool get disabled;
  void set disabled(bool val);
  Element get currentWheelTarget;
  void set currentWheelTarget(Node target);

  compensateForHScroll();
}

abstract class LineHandle {
  String get text;
  void set text(String txt);
  int get height;
  void set height(int n);
  get styles;
  get styleClasses;
  get stateAfter;
  get order;
  set styles(x);
  set styleClasses(x);
  set stateAfter(x);
  set order(x);
  Map get gutterMarkers;
  void set gutterMarkers(Map x);
  List<LineWidget> get widgets;
  String get textClass;
  String get bgClass;
  String get wrapClass;
  int lineNo();
}

class LineInfo {
  final int line;
  final LineHandle handle;

  LineInfo(this.line, this.handle);

  String get text => handle.text;
  Map get gutterMarkers => handle.gutterMarkers;
  String get textClass => handle.textClass;
  String get bgClass => handle.bgClass;
  String get wrapClass => handle.wrapClass;
  List<LineWidget> get widgets => handle.widgets;
}

class ScrollInfo {
  num left;
  num top;
  num height;
  num width;
  num clientHeight;
  num clientWidth;

  ScrollInfo(this.left, this.top, this.height, this.width,
      this.clientHeight, this.clientWidth);
}
