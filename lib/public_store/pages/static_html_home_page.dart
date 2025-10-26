// Conditional export: uses web implementation on web, stub on other platforms
export 'static_html_home_page_web.dart' if (dart.library.io) 'static_html_home_page_stub.dart';
