// An email the ERP itself wrote (its HTML document), drawn the way a mail
// app draws it, for a preview before sending (2026-10-13: the «va en camino»
// email). Links never navigate inside the preview; they open outside.
//
// The browser draws it in a sandboxed frame, natively, with no HTML engine of
// our own: on 2026-10-14 the Dart HTML widget (`flutter_widget_from_html` and
// its parser, ~0.6 MB of JavaScript) had reached the storefront's editor
// bundle through the shipment dialog and pushed it over its budget, and vinabike.cl
// stopped publishing. The native apps keep the browser view and the HTML
// widget fallback.
export 'email_html_view_io.dart'
    if (dart.library.js_interop) 'email_html_view_web.dart';
