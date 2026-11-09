import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// Calls [onActivity] when a browser tab becomes visible or its window regains
/// focus. Flutter lifecycle events alone are not reliable for every web
/// browser, especially when a tab remains open across a deployment.
class BrowserActivityListener {
  BrowserActivityListener(void Function() onActivity)
    : _focus = ((web.Event _) => onActivity()).toJS,
      _visibility = ((web.Event _) {
        if (web.document.visibilityState == 'visible') onActivity();
      }).toJS {
    web.window.addEventListener('focus', _focus);
    web.document.addEventListener('visibilitychange', _visibility);
  }

  final JSFunction _focus;
  final JSFunction _visibility;

  void dispose() {
    web.window.removeEventListener('focus', _focus);
    web.document.removeEventListener('visibilitychange', _visibility);
  }
}
