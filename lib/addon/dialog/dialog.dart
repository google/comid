// Copyright (c) 2015, the Comid Authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library comid.dialog;

import 'dart:html';
import 'package:comid/codemirror.dart';

class NullTreeSanitizer implements NodeTreeSanitizer {
  sanitizeTree(x){} // Disable all sanity checks
}

DivElement dialogDiv(CodeMirror cm, dynamic template, bool bottom) {
  var wrap = cm.getWrapperElement();
  DivElement dialog;
  dialog = wrap.append(document.createElement("div"));
  if (bottom)
    dialog.className = "CodeMirror-dialog CodeMirror-dialog-bottom";
  else
    dialog.className = "CodeMirror-dialog CodeMirror-dialog-top";

  if (template is String) {
    dialog.setInnerHtml(template, treeSanitizer: new NullTreeSanitizer());
  } else { // Assuming it's a detached DOM element.
    dialog.append(template);
  }
  return dialog;
}

void closeNotification(CodeMirror cm, Function newVal) {
  if (cm.state.currentNotificationClose != null)
    cm.state.currentNotificationClose();
  cm.state.currentNotificationClose = newVal;
}

List<Element> getElementsByTagName(Node node, String name) {
  bool hasParent(Node child, Node parent) {
    if (child.parent == null) return false;
    if (child.parent == parent) return true;
    return hasParent(child.parent, parent);
  }
  List<Node> nodes = document.getElementsByTagName(name);
  nodes.sublist(0)..retainWhere((n) => hasParent(n, node));
  if (nodes.isEmpty) nodes.add(null); // always return at least one element
  return nodes;
}

//CodeMirror.defineExtension("openDialog", function(template, callback, options) {
Function openDialog(CodeMirror cm, dynamic template, Function callback, [Map options]) {
  if (options == null) options = {};

  closeNotification(cm, null);

  bool bottom = options['bottom'];
  if (bottom == null) bottom = false;
  DivElement dialog = dialogDiv(cm, template, bottom);
  bool closed = false;
  InputElement inp;
  ButtonElement button;

  close([newVal]) {
    if (newVal is String) {
      inp.value = newVal;
    } else {
      if (closed) return;
      closed = true;
      dialog.remove();
      cm.focus();

      if (options.containsKey('onClose')) options['onClose'](dialog);
    }
  }

  inp = getElementsByTagName(dialog, "input")[0];
  if (inp != null) {
    if (options.containsKey('value')) {
      inp.value = options['value'];
      if (options['selectValueOnOpen'] != false) {
        inp.select();
      }
    }

    if (options.containsKey('onInput'))
      cm.on(inp, "input", (Event e) { options['onInput'](e, inp.value, close);});
    if (options.containsKey('onKeyUp'))
      cm.on(inp, "keyup", (KeyboardEvent e) {options['onKeyUp'](e, inp.value, close);});

    cm.on(inp, "keydown", (KeyboardEvent e) {
      if (options.containsKey('keyDown') && options['onKeyDown'](e, inp.value, close)) {
        return;
      }
      if (e.keyCode == 27 || (options['closeOnEnter'] != false && e.keyCode == 13)) {
        inp.blur();
        cm.e_stop(e);
        close();
      }
      if (e.keyCode == 13) callback(inp.value);
    });

    if (options['closeOnBlur'] != false) cm.on(inp, "blur", close);

    inp.focus();
  } else if ((button = getElementsByTagName(dialog, "button")[0]) != null) {
    cm.on(button, "click", (MouseEvent e) {
      close();
      cm.focus();
    });

    if (options['closeOnBlur'] != false) cm.on(button, "blur", close);

    button.focus();
  }
  return close;
}

//CodeMirror.defineExtension("openConfirm", function(template, callbacks, options) {
void openConfirm(CodeMirror cm, dynamic template, List<Function>callbacks, [Map options]) {
  closeNotification(cm, null);
  var bottom = options != null && options.containsKey('bottom')
      ? options['bottom'] : false;
  var dialog = dialogDiv(cm, template, bottom);
  var buttons = getElementsByTagName(dialog, "button");
  var closed = false, blurring = 1;
  close() {
    if (closed) return;
    closed = true;
    dialog.remove();
    cm.focus();
  }
  buttons[0].focus(); // must be at least one button
  for (var i = 0; i < buttons.length; ++i) {
    var b = buttons[i];
    ((callback) {
      cm.on(b, "click", (e) {
        cm.e_preventDefault(e);
        close();
        if (callback != null) callback();
        b.focus();
      });
      cm.on(b, "keydown", (KeyboardEvent e) {
        if (e.keyCode == 27) {
          cm.e_stop(e);
          close();
        }
      });
    })(i < callbacks.length ? callbacks[i] : null);
    cm.on(b, "blur", (e) {
      --blurring;
      setTimeout(() { if (blurring <= 0) close(); }, 200);
    });
    cm.on(b, "focus", (e) { ++blurring; });
  }
}

/*
 * openNotification
 * Opens a notification, that can be closed with an optional timer
 * (default 5000ms timer) and always closes on click.
 *
 * If a notification is opened while another is opened, it will close the
 * currently opened one and open the new one immediately.
 */
//CodeMirror.defineExtension("openNotification", function(template, options) {
Function openNotification(CodeMirror cm, dynamic template, [Map options]) {
  if (options == null) options = {};
  var dialog;
  var bottom = options.containsKey('bottom') ? options['bottom'] : false;
  var closed = false, doneTimer;
  var duration = options.containsKey('duration') ? options['duration'] : 5000;

  close() {
    if (closed) return;
    closed = true;
    clearTimeout(doneTimer);
    dialog.remove();
  }
  closeNotification(cm, close);
  dialog = dialogDiv(cm, template, bottom);

  cm.on(dialog, 'click', (MouseEvent e) {
    cm.e_preventDefault(e);
    close();
  });

  if (duration != null && duration != 0) {
    doneTimer = setTimeout(close, duration);
  }
  return close;
}
