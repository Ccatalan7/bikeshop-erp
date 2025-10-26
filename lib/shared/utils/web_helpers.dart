// Conditional export for web-specific utilities
export 'web_helpers_web.dart' if (dart.library.io) 'web_helpers_stub.dart';
