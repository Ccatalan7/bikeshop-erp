// Conditional import for browser URL utilities
// Uses dart:html on web, stub on other platforms
export 'browser_url_stub.dart'
    if (dart.library.js_interop) 'browser_url_web.dart';
