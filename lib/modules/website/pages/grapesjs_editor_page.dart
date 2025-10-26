// Conditional export: uses web implementation on web, stub on other platforms
export 'grapesjs_editor_page_web.dart' if (dart.library.io) 'grapesjs_editor_page_stub.dart';
