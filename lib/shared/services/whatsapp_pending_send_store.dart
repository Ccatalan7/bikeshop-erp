import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A WhatsApp send that the device has not seen the server accept yet.
@immutable
class PendingWhatsAppSend {
  const PendingWhatsAppSend({
    required this.clientMessageId,
    required this.userId,
    required this.tenantId,
    required this.body,
    required this.savedAt,
  });

  final String clientMessageId;
  final String userId;
  final String tenantId;
  final Map<String, dynamic> body;
  final DateTime savedAt;

  String? get conversationId => body['conversationId']?.toString();

  String get text => body['message']?.toString() ?? '';

  Map<String, dynamic> toJson() => {
        'client_message_id': clientMessageId,
        'user_id': userId,
        'tenant_id': tenantId,
        'body': body,
        'saved_at': savedAt.toUtc().toIso8601String(),
      };

  static PendingWhatsAppSend? fromJson(Object? json) {
    if (json is! Map) return null;
    final clientMessageId = json['client_message_id']?.toString();
    final userId = json['user_id']?.toString();
    final tenantId = json['tenant_id']?.toString();
    final body = json['body'];
    final savedAt = DateTime.tryParse(json['saved_at']?.toString() ?? '');
    if (clientMessageId == null ||
        userId == null ||
        tenantId == null ||
        body is! Map ||
        savedAt == null) {
      return null;
    }
    return PendingWhatsAppSend(
      clientMessageId: clientMessageId,
      userId: userId,
      tenantId: tenantId,
      body: Map<String, dynamic>.from(body),
      savedAt: savedAt,
    );
  }
}

/// Sends that left the composer but whose acceptance the device never heard.
///
/// **Por qué existe (2026-10-08).** Con mala señal el teléfono mostraba el
/// reloj y, si la respuesta del servidor no llegaba, marcaba el mensaje como
/// «resultado incierto» y lo abandonaba: no se reintentaba, y en el escritorio
/// —otra cuenta— no había nada que ver. El dueño: «¿cómo podría saber otro
/// usuario que hay un mensaje pendiente de envío? Podría intentar enviar otro
/// y sería redundante». La aceptación en la base es idempotente por la llave
/// del cliente (misma llave y mismo cuerpo devuelven la misma fila), así que
/// repetirla es seguro: se guarda aquí antes de pedirla, se reintenta hasta que
/// el servidor la tiene —desde ahí todos los dispositivos la ven con su
/// reloj— y sobrevive al cierre de la app. Un envío de otra persona o de otro
/// taller nunca se repite desde aquí.
class WhatsAppPendingSendStore {
  WhatsAppPendingSendStore._();

  static final WhatsAppPendingSendStore instance = WhatsAppPendingSendStore._();

  static const String _key = 'whatsapp.pending_sends.v1';

  /// Older than this the 24-hour window and the operator's intent are stale:
  /// the send is dropped instead of surprising a customer.
  static const Duration maxAge = Duration(hours: 12);

  /// Every change is read-modify-write of one JSON value: two sends that
  /// overlap would each write their own copy and the first one would vanish
  /// (revisión cruzada, 2026-10-08). They run one after another.
  Future<void> _tail = Future<void>.value();

  Future<T> _serial<T>(Future<T> Function() operation) {
    final result = _tail.then((_) => operation());
    _tail = result.then<void>((_) {}, onError: (_) {});
    return result;
  }

  Future<Map<String, Object?>> _read(SharedPreferences prefs) async {
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map ? Map<String, Object?>.from(decoded) : {};
    } catch (_) {
      return {};
    }
  }

  Future<void> remember(PendingWhatsAppSend send) =>
      _serial(() => _remember(send));

  Future<void> _remember(PendingWhatsAppSend send) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final all = await _read(prefs);
      all[send.clientMessageId] = send.toJson();
      await prefs.setString(_key, jsonEncode(all));
    } catch (error) {
      debugPrint('ℹ️ [WhatsAppPendingSend] could not remember: $error');
    }
  }

  Future<void> forget(String clientMessageId) =>
      _serial(() => _forget(clientMessageId));

  Future<void> _forget(String clientMessageId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final all = await _read(prefs);
      if (all.remove(clientMessageId) == null) return;
      await prefs.setString(_key, jsonEncode(all));
    } catch (error) {
      debugPrint('ℹ️ [WhatsAppPendingSend] could not forget: $error');
    }
  }

  /// Pending sends of [userId] in [tenantId]; expired ones are dropped.
  Future<List<PendingWhatsAppSend>> pendingFor({
    required String userId,
    required String tenantId,
    DateTime? now,
  }) =>
      _serial(
        () => _pendingFor(userId: userId, tenantId: tenantId, now: now),
      );

  Future<List<PendingWhatsAppSend>> _pendingFor({
    required String userId,
    required String tenantId,
    DateTime? now,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final all = await _read(prefs);
      final at = now ?? DateTime.now();
      final keep = <String, Object?>{};
      final mine = <PendingWhatsAppSend>[];
      for (final entry in all.entries) {
        final send = PendingWhatsAppSend.fromJson(entry.value);
        if (send == null || at.difference(send.savedAt) > maxAge) continue;
        keep[entry.key] = entry.value;
        if (send.userId == userId && send.tenantId == tenantId) {
          mine.add(send);
        }
      }
      if (keep.length != all.length) {
        await prefs.setString(_key, jsonEncode(keep));
      }
      mine.sort((a, b) => a.savedAt.compareTo(b.savedAt));
      return mine;
    } catch (error) {
      debugPrint('ℹ️ [WhatsAppPendingSend] could not read: $error');
      return const [];
    }
  }
}
