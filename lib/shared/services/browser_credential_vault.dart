import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class BrowserSavedCredential {
  const BrowserSavedCredential({
    required this.origin,
    required this.username,
    required this.password,
    required this.updatedAt,
    required this.supplierNoMatchConfirmed,
  });

  final String origin;
  final String username;
  final String password;
  final DateTime updatedAt;
  final bool supplierNoMatchConfirmed;

  String encode() => jsonEncode({
        'origin': origin,
        'username': username,
        'password': password,
        'updatedAt': updatedAt.toUtc().toIso8601String(),
        'supplierNoMatchConfirmed': supplierNoMatchConfirmed,
      });

  static BrowserSavedCredential? tryDecode(
    String? value, {
    required String expectedOrigin,
  }) {
    if (value == null || value.isEmpty) return null;
    try {
      final decoded = jsonDecode(value);
      if (decoded is! Map<String, dynamic>) return null;
      final origin = BrowserCredentialVault.normalizeOrigin(
        decoded['origin']?.toString(),
      );
      final username = decoded['username'];
      final password = decoded['password'];
      if (origin != expectedOrigin ||
          username is! String ||
          username.trim().isEmpty ||
          username.length > 512 ||
          password is! String ||
          password.isEmpty ||
          password.length > 4096) {
        return null;
      }
      return BrowserSavedCredential(
        origin: origin!,
        username: username,
        password: password,
        updatedAt: DateTime.tryParse('${decoded['updatedAt']}')?.toUtc() ??
            DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        supplierNoMatchConfirmed:
            decoded['supplierNoMatchConfirmed'] as bool? ?? false,
      );
    } catch (_) {
      return null;
    }
  }
}

abstract interface class BrowserCredentialSecureStore {
  Future<String?> read(String key);

  Future<void> write(String key, String value);

  Future<void> delete(String key);
}

class PlatformBrowserCredentialSecureStore
    implements BrowserCredentialSecureStore {
  const PlatformBrowserCredentialSecureStore();

  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

/// Per-ERP-user, per-HTTPS-origin credential storage backed by the OS vault.
class BrowserCredentialVault {
  BrowserCredentialVault({BrowserCredentialSecureStore? store})
      : _store = store ?? const PlatformBrowserCredentialSecureStore();

  static final BrowserCredentialVault instance = BrowserCredentialVault();
  static const _keyPrefix = 'vinabike.browser.credential.v1';
  static final Map<String, Future<void>> _writeTails = {};

  final BrowserCredentialSecureStore _store;

  Future<BrowserSavedCredential?> load({
    required String userId,
    required String origin,
  }) async {
    final identity = _normalizeUserId(userId);
    final normalizedOrigin = normalizeOrigin(origin);
    if (identity == null || normalizedOrigin == null) return null;
    await (_writeTails[identity] ?? Future<void>.value());
    final encoded =
        await _store.read(_credentialKey(identity, normalizedOrigin));
    return BrowserSavedCredential.tryDecode(
      encoded,
      expectedOrigin: normalizedOrigin,
    );
  }

  Future<void> save({
    required String userId,
    required String origin,
    required String username,
    required String password,
    required bool supplierNoMatchConfirmed,
  }) {
    final identity = _normalizeUserId(userId);
    final normalizedOrigin = normalizeOrigin(origin);
    final cleanUsername = username.trim();
    if (identity == null ||
        normalizedOrigin == null ||
        cleanUsername.isEmpty ||
        cleanUsername.length > 512 ||
        password.isEmpty ||
        password.length > 4096) {
      return Future<void>.value();
    }

    return _serialize(identity, () async {
      final credential = BrowserSavedCredential(
        origin: normalizedOrigin,
        username: cleanUsername,
        password: password,
        updatedAt: DateTime.now().toUtc(),
        supplierNoMatchConfirmed: supplierNoMatchConfirmed,
      );
      final origins = await _readIndex(identity)
        ..add(normalizedOrigin);
      await _writeIndex(identity, origins);
      await _store.write(
        _credentialKey(identity, normalizedOrigin),
        credential.encode(),
      );
    });
  }

  Future<void> delete({
    required String userId,
    required String origin,
  }) {
    final identity = _normalizeUserId(userId);
    final normalizedOrigin = normalizeOrigin(origin);
    if (identity == null || normalizedOrigin == null) {
      return Future<void>.value();
    }

    return _serialize(identity, () async {
      await _store.delete(_credentialKey(identity, normalizedOrigin));
      final origins = await _readIndex(identity)
        ..remove(normalizedOrigin);
      await _writeIndex(identity, origins);
    });
  }

  Future<void> clearUser(String userId) {
    final identity = _normalizeUserId(userId);
    if (identity == null) return Future<void>.value();

    return _serialize(identity, () async {
      final origins = await _readIndex(identity);
      for (final origin in origins) {
        await _store.delete(_credentialKey(identity, origin));
      }
      await _store.delete(_indexKey(identity));
    });
  }

  Future<Set<String>> _readIndex(String identity) async {
    final encoded = await _store.read(_indexKey(identity));
    if (encoded == null || encoded.isEmpty) return <String>{};
    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! List) return <String>{};
      return decoded
          .whereType<String>()
          .map(normalizeOrigin)
          .whereType<String>()
          .toSet();
    } catch (_) {
      return <String>{};
    }
  }

  Future<void> _writeIndex(String identity, Set<String> origins) async {
    if (origins.isEmpty) {
      await _store.delete(_indexKey(identity));
      return;
    }
    final sorted = origins.toList()..sort();
    await _store.write(_indexKey(identity), jsonEncode(sorted));
  }

  Future<void> _serialize(
    String identity,
    Future<void> Function() operation,
  ) {
    final previous = _writeTails[identity] ?? Future<void>.value();
    final ready = previous.then<void>(
      (_) {},
      onError: (_, __) {},
    );
    final next = ready.then((_) => operation());
    _writeTails[identity] = next;
    return next.whenComplete(() {
      if (identical(_writeTails[identity], next)) {
        _writeTails.remove(identity);
      }
    });
  }

  static String? normalizeOrigin(String? value) {
    final uri = Uri.tryParse(value?.trim() ?? '');
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) return null;
    return uri.origin;
  }

  static String? _normalizeUserId(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty || normalized == 'anonymous') return null;
    return normalized;
  }

  static String _credentialKey(String identity, String origin) =>
      '$_keyPrefix.value.${_token(identity)}.${_token(origin)}';

  static String _indexKey(String identity) =>
      '$_keyPrefix.index.${_token(identity)}';

  static String _token(String value) =>
      base64Url.encode(utf8.encode(value)).replaceAll('=', '');
}
