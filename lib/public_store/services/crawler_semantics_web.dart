import 'dart:js_interop';

@JS('navigator.userAgent')
external JSString? get _userAgent;

String currentUserAgentImpl() {
  try {
    return _userAgent?.toDart ?? '';
  } catch (_) {
    return '';
  }
}
