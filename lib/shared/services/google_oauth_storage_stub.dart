// Minimal stub for non-web builds.
class _LocalStorageStub {
  final Map<String, String> _store = {};

  String? operator [](String key) => _store[key];
  void operator []=(String key, String value) => _store[key] = value;

  void remove(String key) => _store.remove(key);
  void removeItem(String key) => _store.remove(key);
}

class _WindowStub {
  final localStorage = _LocalStorageStub();
}

final window = _WindowStub();
