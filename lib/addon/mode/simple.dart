// Copyright (c) 2015, the Comid Authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library comid.mode.simple;

import 'package:comid/codemirror.dart';

// Work-in-progress. Need to define SimpleModeState, handle regexp's.

class SimpleMode extends Mode {
  var states, config, meta, states_;
  var hasIndentation;

  SimpleMode(config, states) {
    ensureState(states, "start");
    states_ = {};
    meta = states.meta == null ? {} : states.meta;
    hasIndentation = false;
    for (var state in states) {
      if (state != meta) {
        var list = states_[state] = [], orig = states[state];
        for (var i = 0; i < orig.length; i++) {
          var data = orig[i];
          list.add(new Rule(data, states));
          if (data.indent || data.dedent) hasIndentation = true;
        }
      }
    }
    if (meta != null) {
      for (var prop in meta.keys) {
        this[prop] = meta[prop];
      }
    }
  }

  startState([a1, a2]) {
    return {'state': "start", 'pending': null,
            'local': null, 'localState': null,
            'indent': hasIndentation ? [] : null};
  }

  copyState(state) {
    var s = {'state': state.state, 'pending': state.pending,
             'local': state.local, 'localState': null,
             'indent': state.indent == null ? null : state.indent.sublist(0)};
    if (state['localState'] != null) {
      s['localState'] = copyModeState(state['local']['mode'], state['localState']);
    }
    if (state['stack'] != null)
      s['stack'] = state.stack.sublist(0);
    for (var pers = state['persistentStates']; pers != null; pers = pers['next']) {
      s['persistentStates'] = {
          'mode': pers['mode'],
          'spec': pers['spec'],
          'state': pers['state'] == state['localState']
              ? s['localState']
              : copyModeState(pers['mode'], pers['state']),
          'next': s['persistentStates']
      };
    }
    return s;
  }

  innerMode([var state]) {
    return state.local == null ? null : {mode: state.local.mode, state: state.localState};
  }

  indent(state, textAfter, line) {
    if (state.local != null && state.local.mode.hasIndent)
      return state.local.mode.indent(state.localState, textAfter, line);
    if (state.indent == null || state.local != null ||
        meta.dontIndentStates != null &&
          meta.dontIndentStates.indexOf(state.state) > -1)
      return Pass;

    var pos = state.indent.length - 1, rules = states[state.state];
    scan: for (;;) {
      for (var i = 0; i < rules.length; i++) {
        var rule = rules[i], m = rule.regex.exec(textAfter);
        if (m && m[0]) {
          if (rule.data.dedent && rule.data.dedentIfLineStart != false) pos--;
          if (rule.next || rule.push) rules = states[rule.next || rule.push];
          textAfter = textAfter.slice(m[0].length);
          continue scan;
        }
      }
      break;
    }
    return pos < 0 ? 0 : state.indent[pos];
  }

  token(StringStream stream, [dynamic state]) {
    if (state.pending) {
      var pend = state.pending.shift();
      if (state.pending.length == 0) state.pending = null;
      stream.pos += pend.text.length;
      return pend.token;
    }

    if (state.local != null) {
      if (state.local.end != null && stream.match(state.local.end)) {
        var tok = state.local.endToken || null;
        state.local = state.localState = null;
        return tok;
      } else {
        var tok = state.local.mode.token(stream, state.localState);
        var m;
        if (state.local.endScan != null) {
          m = new RegExp(state.local.endScan).firstMatch(stream.current());
          if (null != m) {
            stream.pos = stream.start + m.start;
          }
        }
        return tok;
      }
    }

    var curState = states[state.state];
    for (var i = 0; i < curState.length; i++) {
      var rule = curState[i];
      var matches = stream.match(rule.regex);
      if (matches) {
        if (rule.data.next) {
          state.state = rule.data.next;
        } else if (rule.data.push) {
          if (state.stack == null) state.stack = [];
          state.stack.add(state.state);
          state.state = rule.data.push;
        } else if (rule.data.pop && state.stack && state.stack.length) {
          state.state = state.stack.pop();
        }

        if (rule.data.mode) {
          enterLocalMode(config, state, rule.data.mode, rule.token);
        }
        if (rule.data.indent) {
          state.indent.add(stream.indentation() + config.indentUnit);
        }
        if (rule.data.dedent) {
          state.indent.removeLast();
        }
        if (matches.length > 2) {
          state.pending = [];
          for (var j = 2; j < matches.length; j++) {
            if (matches[j]) {
              state.pending.add(
                  {'text': matches[j], 'token': rule.token[j - 1]});
            }
          }
          var back = matches[1] != null ? matches[1].length : 0;
          stream.backUp(matches[0].length - back);
          return rule.token[0];
        } else if (rule.token != null && rule.token is List) {
          return rule.token[0];
        } else {
          return rule.token;
        }
      }
    }
    stream.next();
    return null;
  }

  cmp(Map a, Map b) {
    if (a == b) return true;
    if (a == null || b == null) return false;
    var props = 0;
    for (var prop in a.keys) {
      if (!b.containsKey(prop) || !cmp(a[prop], b[prop])) return false;
      props++;
    }
    return props == b.length;
  }

  enterLocalMode(config, state, spec, token) {
    var pers;
    if (spec.persistent) {
      for (var p = state.persistentStates; p && !pers; p = p.next) {
        if (spec.spec ? cmp(spec.spec, p.spec) : spec.mode == p.mode) pers = p;
      }
    }
    var mode = pers != null ? pers.mode :
        spec.mode != null ? spec.mode : CodeEditor.getMode(config, spec.spec);
    var lState = pers != null ? pers.state : startState(mode);
    if (spec.persistent && pers == null)
      state.persistentStates = {
          'mode': mode, 'spec': spec.spec, 'state': lState,
          'next': state.persistentStates
      };

    state.localState = lState;
    state.local = {
        'mode': mode,
        'end': spec.end == null
            ? null : toRegex(spec.end),
        'endScan': spec.end != null && spec.forceEnd != false
            ? toRegex(spec.end, false) : null,
        'endToken': token != null && token is List
            ? token[token.length - 1] : token
    };
  }

  copyModeState(mode, state) {
    if (state == true) return state;
    if (mode is Mode) return mode.copyState(state);
    var nstate = {};
    for (var n in state.keys) {
      var val = state[n];
      if (val is List) val = val.sublist(0);
      nstate[n] = val;
    }
    return nstate;
  }
}

ensureState(states, name) {
  if (!states.containsKey(name))
    throw new StateError("Undefined state '$name' in simple mode");
}

toRegex(val, [caret = false]) {
  if (!val) return new RegExp(r'(?:)');
  String str;
  bool isCaseSensitive = false;
  if (val is RegExp) {
    isCaseSensitive = val.isCaseSensitive;
    str = val.pattern;
  } else {
    str = val as String;
  }
  String pattern = (caret == false ? "" : "^") + "(?:" + str + ")";
  return new RegExp(pattern, caseSensitive: isCaseSensitive);
}

asToken(val) {
  if (val == null) return null;
  if (val is String) return val.replaceAll(".", " ");
  var result = [];
  for (var i = 0; i < val.length; i++)
    result.add(val[i] != null ? val[i].replaceAll(".", " ") : null);
  return result;
}

class Rule {
  var regex, token, data;
  Rule(data, states) {
    if (data.next || data.push) ensureState(states, data.next || data.push);
    this.regex = toRegex(data.regex);
    this.token = asToken(data.token);
    this.data = data;
  }
}
