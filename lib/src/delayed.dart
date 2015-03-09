// Copyright (c) 2015, the Comid Authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

part of comid;

setTimeout(var callback, var ms) {
  return new Timer(new Duration(milliseconds: ms), callback);
}

clearTimeout(Timer a) { if (a != null) a.cancel(); }

class Delayed {
  Timer id;

  void set(int ms, var f) {
    // TODO Is there anyway that Delayed.id could be set in original?
    if (id != null) clearTimeout(id);
    id = setTimeout(f, ms);
  }
}
