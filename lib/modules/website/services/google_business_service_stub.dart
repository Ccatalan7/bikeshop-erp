// Stub file for non-web platforms (dart:html doesn't exist on mobile/desktop)
// This provides a fake 'window' object that does nothing.

class _FakeStorage {
  String? operator [](String key) => null;
  void operator []=(String key, String value) {}
  String? remove(String key) => null;
}

class _FakeWindow {
  final localStorage = _FakeStorage();
}

final window = _FakeWindow();
