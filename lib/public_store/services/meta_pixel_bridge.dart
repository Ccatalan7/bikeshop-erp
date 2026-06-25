import 'meta_pixel_bridge_stub.dart'
    if (dart.library.js_interop) 'meta_pixel_bridge_web.dart';

bool initializeMetaPixel(String pixelId) {
  return initializeMetaPixelImpl(pixelId);
}

bool trackMetaPixelEvent(
  String eventName,
  String payloadJson, {
  String? eventId,
}) {
  return trackMetaPixelEventImpl(
    eventName,
    payloadJson,
    eventId: eventId,
  );
}
