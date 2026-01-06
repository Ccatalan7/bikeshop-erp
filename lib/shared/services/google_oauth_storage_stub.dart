// Minimal stub for non-web builds.
class _LocalStorageStub {
  final Map<String, String> _store = {};

  String? operator [](String key) => _store[key];
  void operator []=(String key, String value) => _store[key] = value;
}

class _WindowStub {
  final localStorage = _LocalStorageStub();
}

final window = _WindowStub();
