import 'dart:js_interop';

// `web/index.html` define `gtag` antes de cargar Flutter y encola los eventos
// en `dataLayer` hasta que llega el script de Google.
@JS('gtag')
external void _gtag(JSString command, JSString eventName, JSAny? params);

bool trackGa4EventImpl(String eventName, Map<String, Object?> params) {
  try {
    _gtag('event'.toJS, eventName.toJS, params.jsify());
    return true;
  } catch (_) {
    return false;
  }
}
