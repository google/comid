// Copyright (c) 2015, the Comid Authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

part of comid;

Navigator navigator = window.navigator;
bool gecko = new RegExp(r'gecko/\d', caseSensitive: true).hasMatch(navigator.userAgent);
bool ie_upto10 = false; // not supported by Dart
Iterable ie_11up = new RegExp(r'Trident/(?:[7-9]|\d{2,})\..*rv:(\d+)')
    .allMatches(navigator.userAgent);
bool ie = ie_upto10 || ie_11up.isNotEmpty;
var ie_version = ie ? ie_11up.skip(1).first : null;
bool webkit = new RegExp(r'WebKit/').hasMatch(navigator.userAgent);
bool qtwebkit = webkit && new RegExp(r'Qt/\d+\.\d+').hasMatch(navigator.userAgent);
bool chrome = new RegExp(r'Chrome/').hasMatch(navigator.userAgent);
bool presto = new RegExp(r'Opera/').hasMatch(navigator.userAgent);
bool safari = new RegExp(r'Apple Computer').hasMatch(navigator.vendor);
bool mac_geMountainLion = new RegExp(r'Mac OS X 1\d\D([8-9]|\d\d)\D').hasMatch(navigator.userAgent);
bool phantom = new RegExp(r'PhantomJS').hasMatch(navigator.userAgent);

bool ios = new RegExp(r'AppleWebKit').hasMatch(navigator.userAgent) && new RegExp(r'Mobile/\w+')
    .hasMatch(navigator.userAgent);
// This is woefully incomplete. Suggestions for alternative methods welcome.
bool mobile = ios
    || new RegExp(r'Android|webOS|BlackBerry|Opera Mini|Opera Mobi|IEMobile/', caseSensitive: true)
    .hasMatch(navigator.userAgent);
bool mac = ios || new RegExp(r'Mac').hasMatch(navigator.platform);
bool windows = new RegExp(r'win', caseSensitive: true).hasMatch(navigator.platform);

num _presto_vsn() { // TODO: Is this needed? Not sure Dart supports Opera that far back.
  if (!presto) return 0;
  var match = new RegExp(navigator.userAgent).allMatches(r'Version/(\d*\.\d*)');
  num pv = num.parse(match.skip(1).first.group(0));
  if (pv != 0 && pv >= 15) {
    presto = false;
    webkit = true;
  }
  return pv;
}

// Some browsers use the wrong event properties to signal cmd/ctrl on OS X
bool flipCtrlCmd = mac && (qtwebkit || (presto && _presto_vsn() < 12.11));
bool captureRightClick = gecko || (ie && ie_version >= 9);

// Optimize some code when these features are not used.
// TODO These should not be global.
bool sawReadOnlySpans = false, sawCollapsedSpans = false;

// Number of pixels added to scroller and sizer to hide scrollbar.
const scrollerGap = 30;
// Returned or thrown by various protocols to signal 'I'm not
// handling this'.
const Pass = "CodeMirror.Pass";
