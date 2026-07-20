import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// Logical command families must stay separate even when their inputs match.
enum MessagingCommandNamespace {
  customerSupportRequest('customer-support-request'),
  whatsappSupportOpen('whatsapp-support-open'),
  staffSupportCreate('staff-support-create'),
  staffInternalCreate('staff-internal-create');

  const MessagingCommandNamespace(this.storageValue);

  final String storageValue;
}

/// Minimal persistence boundary used to fail closed before a remote command.
///
/// The production adapter stores only an opaque UUID under a SHA-256 key. The
/// interface also makes persistence failures deterministic in unit tests.
abstract interface class MessagingCommandKeyPersistence {
  String? getString(String key);

  bool containsKey(String key);

  Future<bool> setString(String key, String value);

  Future<bool> remove(String key);
}

class MessagingCommandPersistenceException implements Exception {
  const MessagingCommandPersistenceException(this.message);

  final String message;

  @override
  String toString() => 'MessagingCommandPersistenceException: $message';
}

typedef MessagingCommandPersistenceLoader
    = Future<MessagingCommandKeyPersistence> Function();
typedef MessagingCommandKeyFactory = String Function();

/// Crash-safe local ownership for messaging command idempotency keys.
///
/// A key is durably persisted before [command] can run and is removed only
/// after the callback returns a confirmed, validated result. Network errors,
/// lost acknowledgements, app termination, and local cleanup failures retain
/// the same key for the next attempt. Identical concurrent calls share one
/// Future so one caller cannot clear the key while another is still in flight.
class MessagingCommandIdempotencyStore {
  MessagingCommandIdempotencyStore({
    MessagingCommandPersistenceLoader? persistenceLoader,
    MessagingCommandKeyFactory? commandKeyFactory,
  })  : _persistenceLoader =
            persistenceLoader ?? _loadSharedPreferencesPersistence,
        _commandKeyFactory = commandKeyFactory ?? _defaultCommandKeyFactory;

  static const _storagePrefix = 'messaging-command-idempotency-v1';
  static const _fingerprintVersion = 1;

  static final Map<String, Future<String>> _inFlightCommands = {};

  final MessagingCommandPersistenceLoader _persistenceLoader;
  final MessagingCommandKeyFactory _commandKeyFactory;

  Future<String> execute({
    required MessagingCommandNamespace namespace,
    required String userId,
    required String tenantId,
    required List<Object?> fingerprintParts,
    required Future<String> Function(String commandKey) command,
  }) async {
    final storageKey = _storageKey(
      namespace: namespace,
      userId: userId,
      tenantId: tenantId,
      fingerprintParts: fingerprintParts,
    );

    final running = _inFlightCommands[storageKey];
    if (running != null) return running;

    final future = _executePersisted(
      storageKey: storageKey,
      command: command,
    );
    _inFlightCommands[storageKey] = future;

    try {
      return await future;
    } finally {
      if (identical(_inFlightCommands[storageKey], future)) {
        _inFlightCommands.remove(storageKey);
      }
    }
  }

  Future<String> _executePersisted({
    required String storageKey,
    required Future<String> Function(String commandKey) command,
  }) async {
    final persistence = await _loadPersistence();
    final commandKey = await _readOrPersistCommandKey(
      persistence: persistence,
      storageKey: storageKey,
    );

    // Any exception before this callback returns keeps the durable key. That
    // includes a server commit whose acknowledgement was lost in transit.
    final result = await command(commandKey);
    if (result.trim().isEmpty) {
      throw const MessagingCommandPersistenceException(
        'El comando remoto no confirmó un resultado válido',
      );
    }

    await _clearConfirmedCommand(
      persistence: persistence,
      storageKey: storageKey,
      commandKey: commandKey,
    );
    return result;
  }

  Future<MessagingCommandKeyPersistence> _loadPersistence() async {
    try {
      return await _persistenceLoader();
    } catch (_) {
      throw const MessagingCommandPersistenceException(
        'No se pudo abrir el almacenamiento local de operaciones pendientes',
      );
    }
  }

  Future<String> _readOrPersistCommandKey({
    required MessagingCommandKeyPersistence persistence,
    required String storageKey,
  }) async {
    final existing = _readPersistedKey(persistence, storageKey);
    if (existing != null) return existing;

    final commandKey = _commandKeyFactory();
    if (!Uuid.isValidUUID(fromString: commandKey)) {
      throw const MessagingCommandPersistenceException(
        'No se pudo generar una clave de operación válida',
      );
    }

    try {
      final written = await persistence.setString(storageKey, commandKey);
      final readBack = persistence.getString(storageKey);
      if (!written || readBack != commandKey) {
        throw const MessagingCommandPersistenceException(
          'No se pudo respaldar la operación antes de enviarla',
        );
      }
    } on MessagingCommandPersistenceException {
      rethrow;
    } catch (_) {
      throw const MessagingCommandPersistenceException(
        'No se pudo respaldar la operación antes de enviarla',
      );
    }

    return commandKey;
  }

  String? _readPersistedKey(
    MessagingCommandKeyPersistence persistence,
    String storageKey,
  ) {
    try {
      final existing = persistence.getString(storageKey);
      if (existing == null && !persistence.containsKey(storageKey)) {
        return null;
      }
      if (existing == null || !Uuid.isValidUUID(fromString: existing)) {
        throw const MessagingCommandPersistenceException(
          'La operación pendiente guardada no es válida',
        );
      }
      return existing;
    } on MessagingCommandPersistenceException {
      rethrow;
    } catch (_) {
      throw const MessagingCommandPersistenceException(
        'No se pudo leer la operación pendiente guardada',
      );
    }
  }

  Future<void> _clearConfirmedCommand({
    required MessagingCommandKeyPersistence persistence,
    required String storageKey,
    required String commandKey,
  }) async {
    try {
      final current = persistence.getString(storageKey);
      if (current == null && !persistence.containsKey(storageKey)) {
        // A coalesced successful caller may already have completed cleanup.
        return;
      }
      if (current != commandKey) {
        throw const MessagingCommandPersistenceException(
          'La operación pendiente cambió antes de confirmar su resultado',
        );
      }

      final removed = await persistence.remove(storageKey);
      if (!removed || persistence.containsKey(storageKey)) {
        throw const MessagingCommandPersistenceException(
          'La operación fue confirmada, pero su respaldo local sigue pendiente',
        );
      }
    } on MessagingCommandPersistenceException {
      rethrow;
    } catch (_) {
      throw const MessagingCommandPersistenceException(
        'No se pudo cerrar la operación local confirmada',
      );
    }
  }

  String _storageKey({
    required MessagingCommandNamespace namespace,
    required String userId,
    required String tenantId,
    required List<Object?> fingerprintParts,
  }) {
    final normalizedUserId = userId.trim();
    final normalizedTenantId = tenantId.trim();
    if (normalizedUserId.isEmpty || normalizedTenantId.isEmpty) {
      throw const MessagingCommandPersistenceException(
        'La sesión no tiene usuario y tenant válidos',
      );
    }

    final canonicalFingerprint = jsonEncode({
      'version': _fingerprintVersion,
      'namespace': namespace.storageValue,
      'user_id': normalizedUserId,
      'tenant_id': normalizedTenantId,
      'parts': fingerprintParts,
    });
    final digest = sha256.convert(utf8.encode(canonicalFingerprint));
    return '$_storagePrefix:${namespace.storageValue}:$digest';
  }

  static Future<MessagingCommandKeyPersistence>
      _loadSharedPreferencesPersistence() async {
    return _SharedPreferencesMessagingCommandKeyPersistence(
      await SharedPreferences.getInstance(),
    );
  }

  static String _defaultCommandKeyFactory() => const Uuid().v4();
}

class _SharedPreferencesMessagingCommandKeyPersistence
    implements MessagingCommandKeyPersistence {
  const _SharedPreferencesMessagingCommandKeyPersistence(this._preferences);

  final SharedPreferences _preferences;

  @override
  bool containsKey(String key) => _preferences.containsKey(key);

  @override
  String? getString(String key) => _preferences.getString(key);

  @override
  Future<bool> remove(String key) => _preferences.remove(key);

  @override
  Future<bool> setString(String key, String value) =>
      _preferences.setString(key, value);
}
