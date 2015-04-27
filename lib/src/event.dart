// Copyright (c) 2015, the Comid Authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

part of comid;

var orphanDelayedCallbacks = null; // TODO Determine if this is global.

// Lightweight event framework. on/off also work on DOM nodes,
// registering native DOM handlers.
abstract class EventManager {
  // Using signalLater() requires operationGroup to be hooked up correctly.
  OperationGroup get operationGroup;
  Map _handlers;

  // Define some Dart-like async event registration methods (not comprehensive).

  Stream get onChange => onEvent('change', 2);
  Stream get onChanges => onEvent('changes', 2);
  Stream get onRefresh => onEvent('refresh', 1);
  Stream get onScroll => onEvent('scroll', 1);
  Stream get onMarkerAdded => onEvent('markerAdded', 2);
  Stream get onCursorActivity => onEvent('cursorActivity', 1);
  Stream get onOverwriteToggle => onEvent('overwriteToggle', 2);
  Stream get onMousedown => onEvent('mousedown', 2); // onMouseDown is taken

  Stream onEvent(String eventName, [int argCount = 0]) {
    if (_handlers == null) _handlers = {};
    Map handlers = _handlers[#eventListeners];
    if (handlers == null) {
      _handlers[#eventListeners] = handlers = {};
    }
    if (!handlers.containsKey(eventName)) {
      handlers[eventName] = new _EventListener(this, eventName, argCount);
    }
    return handlers[eventName].stream;
  }

  /**
   * This method should be called if #onChange or other Dart-like event
   * registering methods were used to add an event listener to an editor object.
   * Directly calling CodeMirror's #on method does not require #dispose.
   */
  void dispose() {
    Map handlers = _handlers[#eventListeners];
    if (handlers == null) return;
    for (var event in handlers.values) {
      if (event is _EventListener) event.dispose();
    }
  }

  /**
   * Register an event handler for the given [emitter] for events named
   * [type]. The [callback] will be triggered when the event fires.
   */
  void on(dynamic emitter, String type, Function callback) {
    if (emitter is EventTarget) {
      emitter.addEventListener(type, callback, false);
    } else if (emitter is EventManager) {
      if (emitter._handlers == null) emitter._handlers = {};
      var map = emitter._handlers;
      if (map[type] == null) map[type] = [];
      map[type].add(callback);
    }
  }

  /**
   * Unregister an event handler by removing the [callback] from the list
   * of handlers for the event named [type] for the given [emitter].
   */
  void off(dynamic emitter, String type, Function callback) {
    if (emitter is EventTarget) {
      emitter.removeEventListener(type, callback, false);
    } else {
      if (emitter._handlers == null) return;
      var arr = emitter._handlers[type];
      if (arr == null) return;
      for (var i = 0; i < arr.length; ++i) {
        if (arr[i] == callback) {
          arr.removeAt(i);
          break;
        }
      }
    }
  }

  void signal(dynamic emitter, String type, [a1 = _x, a2 = _x, a3 = _x, a4 = _x]) {
    var arr;
    if (emitter._handlers != null) arr = emitter._handlers[type];
    if (arr == null) return;
    for (var i = 0; i < arr.length; ++i) bind(arr[i], a1, a2, a3, a4)();
  }

  // Often, we want to signal events at a point where we are in the
  // middle of some work, but don't want the handler to start calling
  // other methods on the editor, which might be in an inconsistent
  // state or simply not expect any other events to happen.
  // signalLater looks whether there are any handlers, and schedules
  // them to be executed when the last operation ends, or, if no
  // operation is active, when a timeout fires.
  void signalLater(dynamic emitter, String type, [a1 = _x, a2 = _x, a3 = _x, a4 = _x]) {
    var arr;
    if (emitter._handlers != null) arr = emitter._handlers[type];
    if (arr == null) return;
    var list;
    if (emitter.operationGroup != null) {
      list = emitter.operationGroup.delayedCallbacks;
    } else if (orphanDelayedCallbacks != null) {
      list = orphanDelayedCallbacks;
    } else {
      list = orphanDelayedCallbacks = [];
      setTimeout(fireOrphanDelayed, 0);
    }
    bnd(f) { return bind(f, a1, a2, a3, a4); };
    for (var i = 0; i < arr.length; ++i) {
      list.add(bnd(arr[i]));
    }
  }

  void fireOrphanDelayed() {
    var delayed = orphanDelayedCallbacks;
    orphanDelayedCallbacks = null;
    for (var i = 0; i < delayed.length; ++i) delayed[i]();
  }

  // The DOM events that CodeMirror handles can be overridden by
  // registering a (non-DOM) handler on the editor for the event name,
  // and preventDefault-ing the event in that handler.
  bool signalDOMEvent(CodeMirror cm, dynamic e, [override]) {
    if (e is String) e = new DomEvent(e);
    signal(cm, override == null ? e.type : override, cm, e);
    return e_defaultPrevented(e);
  }

  void signalCursorActivity(CodeEditor cm) {
    if (cm._handlers == null) return;
    var arr = cm._handlers['cursorActivity'];
    if (arr == null) return;
    if (cm.curOp.cursorActivityHandlers == null) {
      cm.curOp.cursorActivityHandlers = [];
    }
    List set = cm.curOp.cursorActivityHandlers;
    for (var i = 0; i < arr.length; ++i) {
      if (set.indexOf(arr[i]) == -1) {
        set.add(arr[i]);
      }
    }
  }

  bool hasHandler(EventManager emitter, String type) {
    if (emitter._handlers == null || emitter._handlers.isEmpty) return false;
    var arr = emitter._handlers[type];
    return arr != null && arr.length > 0;
  }

  void e_preventDefault(dynamic e) {
    if (e is Event) e.preventDefault();
    else e.returnValue = false;
  }
  void e_stopPropagation(dynamic e) {
    if (e is Event) e.stopPropagation();
    else e.cancelBubble = true;
  }
  bool e_defaultPrevented(e) {
    return (e is Event) ? e.defaultPrevented : e.returnValue == false;
  }
  e_stop(dynamic e) { e_preventDefault(e); e_stopPropagation(e); }

  e_target(dynamic e) { return (e is Event) ? e.target : e.srcElement; }

}

class DomEvent {
  String type;
  bool defaultPrevented;
  bool cancelBubble;
  dynamic returnValue;
  DomEvent(this.type);
  preventDefault() { defaultPrevented = true; }
}

/**
 * Add an event listener to CodeMirror objects. This uses CodeMirror's `on`
 * and `off` convention. It can listen for events that result in one or two
 * event parameters, and can optionally convert the event object into a
 * different object.
 */
class _EventListener {
  final EventManager proxy;
  final String name;
  final int argCount;

  StreamController controller;
  Function callback;

  _EventListener(this.proxy, this.name, this.argCount);

  Stream get stream {
    if (controller == null) {
      controller = new StreamController.broadcast(
        onListen: () {
          switch (argCount) {
            case 0:
              callback = () {
                controller.add(null);
              };
              proxy.on(proxy, name, callback);
              break;
            case 1:
              callback = (cm) {
                controller.add(cm);
              };
              proxy.on(proxy, name, callback);
              break;
            case 2:
              callback = (cm, arg) {
                controller.add([cm, arg]);
              };
              proxy.on(proxy, name, callback);
              break;
            case 3:
              callback = (cm, arg1, arg2) {
                controller.add([cm, arg1, arg2]);
              };
              proxy.on(proxy, name, callback);
              break;
          }
        },
        onCancel: () {
          proxy.off(proxy, name, callback);
          callback = null;
        }
      );
    }
    return controller.stream;
  }

  Future dispose() {
    if (controller == null) return new Future.value();
    return controller.close();
  }
}
