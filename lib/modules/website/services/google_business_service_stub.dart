// Stub file for non-web platforms (dart:html doesn't exist on mobile/desktop)
// This provides a fake 'window' object that does nothing.

class _FakeStorage {
  String? operator [](String key) => null;
  void operator []=(String key, String value) {}
  String? remove(String key) => null;
}

class _FakeLocation {
  String get href => '';
  void reload() {}
  void assign(String url) {}
}

class _FakeWindow {
  final localStorage = _FakeStorage();
  final location = _FakeLocation();
}

final window = _FakeWindow();
