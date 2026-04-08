// Stub file for non-web platforms (dart:html doesn't exist on mobile/desktop)
// This provides a fake 'window' object that does nothing.

class _FakeStorage {
  final Map<String, String> _store = {};
  String? operator [](String key) => _store[key];
  void operator []=(String key, String value) => _store[key] = value;
  String? remove(String key) => _store.remove(key);
  String? getItem(String key) => _store[key];
  void setItem(String key, String value) => _store[key] = value;
  void removeItem(String key) => _store.remove(key);
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
