// Conditional export for web URL utilities
// Uses web implementation on web, stub on other platforms

export 'web_url_stub.dart' if (dart.library.html) 'web_url_web.dart';
