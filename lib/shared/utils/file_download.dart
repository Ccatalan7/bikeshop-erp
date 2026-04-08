// Conditional export for file download utilities
// Uses web implementation on web, native on other platforms

export 'file_download_stub.dart'
    if (dart.library.js_interop) 'file_download_web.dart';
