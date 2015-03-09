// Copyright (c) 2015, the Comid Authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library comid.mode.fold.all;

import 'foldcode.dart' as code;
import 'comment-fold.dart' as comment;
import 'brace-fold.dart' as brace;
import 'foldgutter.dart' as gutter;
import 'indent-fold.dart' as indent;
import 'markdown-fold.dart' as markdown;
import 'xml-fold.dart' as xml;

export 'foldcode.dart';

initialize() {
  code.initialize();
  comment.initialize();
  brace.initialize();
  gutter.initialize();
  indent.initialize();
  markdown.initialize();
  xml.initialize();
}
