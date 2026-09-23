import 'ga4_bridge_stub.dart'
    if (dart.library.js_interop) 'ga4_bridge_web.dart';

bool trackGa4Event(String eventName, Map<String, Object?> params) {
  return trackGa4EventImpl(eventName, params);
}
