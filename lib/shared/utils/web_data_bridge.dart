import 'web_data_bridge_stub.dart'
    if (dart.library.js_interop) 'web_data_bridge_web.dart';

/// Bridge to access data pre-fetched by index.html
/// Uses conditional imports to be safe for Android/iOS
class WebDataBridge {
  /// Check if there is preloaded store data available from JS
  /// Returns null if not on web, or if no data is available/failed
  static Future<Map<String, dynamic>?> getPreloadedStoreData() {
    return getPreloadedStoreDataImpl();
  }
}
