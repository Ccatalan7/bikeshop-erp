import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/conversation_context_hint.dart';

/// Device-local, tenant-and-user-scoped snapshot of the last context rendered
/// in the messaging inbox. The server remains authoritative; this snapshot only
/// avoids blank context rows while a fresh read is in flight after app startup.
class ConversationContextHintCache {
  static const _keyPrefix = 'messaging_context_hints_v1';
  static const _version = 1;

  Future<Map<String, ConversationContextHint>> read({
    required String tenantId,
    required String userId,
  }) async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(_key(tenantId, userId));
    if (raw == null || raw.isEmpty) return {};

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map ||
          decoded['version'] != _version ||
          decoded['tenant_id'] != tenantId ||
          decoded['user_id'] != userId ||
          decoded['hints'] is! Map) {
        return {};
      }

      final hints = <String, ConversationContextHint>{};
      for (final entry in (decoded['hints'] as Map).entries) {
        final conversationId = entry.key?.toString().trim();
        final value = entry.value;
        if (conversationId == null || conversationId.isEmpty || value is! Map) {
          continue;
        }
        hints[conversationId] = ConversationContextHint.fromJson(
          Map<String, dynamic>.from(value),
        );
      }
      return hints;
    } catch (_) {
      return {};
    }
  }

  Future<void> write({
    required String tenantId,
    required String userId,
    required Map<String, ConversationContextHint> hints,
  }) async {
    final preferences = await SharedPreferences.getInstance();
    final key = _key(tenantId, userId);
    if (hints.isEmpty) {
      await preferences.remove(key);
      return;
    }

    await preferences.setString(
      key,
      jsonEncode({
        'version': _version,
        'tenant_id': tenantId,
        'user_id': userId,
        'cached_at': DateTime.now().toUtc().toIso8601String(),
        'hints': {
          for (final entry in hints.entries) entry.key: entry.value.toJson(),
        },
      }),
    );
  }

  String _key(String tenantId, String userId) {
    return '$_keyPrefix:$tenantId:$userId';
  }
}
