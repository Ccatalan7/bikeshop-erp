import 'dart:js_interop';

@JS('window.vinabikeMetaPixelInit')
external JSBoolean _initializeMetaPixel(JSString pixelId);

@JS('window.vinabikeMetaPixelTrack')
external JSBoolean _trackMetaPixelEvent(
  JSString eventName,
  JSString payloadJson,
  JSString eventId,
);

bool initializeMetaPixelImpl(String pixelId) {
  try {
    return _initializeMetaPixel(pixelId.toJS).toDart;
  } catch (_) {
    return false;
  }
}

bool trackMetaPixelEventImpl(
  String eventName,
  String payloadJson, {
  String? eventId,
}) {
  try {
    return _trackMetaPixelEvent(
      eventName.toJS,
      payloadJson.toJS,
      (eventId ?? '').toJS,
    ).toDart;
  } catch (_) {
    return false;
  }
}
