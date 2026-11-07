import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../shared/services/tenant_service.dart';
import 'mail_work_models.dart';

/// El correo guardado en el servidor (20261106200000) y la función que lo
/// trae (`mail-sync`). Todo pasa por funciones que exigen personal del taller:
/// un cliente con cuenta en el portal nunca lee el correo.
class MailWorkService {
  MailWorkService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Future<List<MailItem>> inbox({
    required MailView view,
    String? space,
    String? query,
    String? mailbox,
    int limit = 120,
    DateTime? before,
  }) async {
    final result = await _client.rpc('mail_inbox_v2', params: {
      'p_view': view.code,
      'p_space': space,
      'p_query': (query?.trim().isEmpty ?? true) ? null : query!.trim(),
      'p_limit': limit,
      'p_before': before?.toUtc().toIso8601String(),
      'p_mailbox': mailbox,
    });
    return _items(result);
  }

  Future<MailItem> message(String id) async {
    final result = await _client.rpc('mail_message_v1', params: {
      'p_message_id': id,
    });
    return MailItem.fromJson(Map<String, dynamic>.from(result as Map));
  }

  /// Los conteos de una casilla, o de todas cuando [mailbox] es null.
  Future<MailCounts> counts({String? mailbox}) async {
    final result = await _client.rpc('mail_counts_v2', params: {
      'p_mailbox': mailbox,
    });
    return MailCounts.fromJson(result);
  }

  /// Las casillas conectadas en el ERP, encendidas o no. Antes se le pide al
  /// servidor que registre las que alguien conectó hace poco.
  Future<List<MailboxInfo>> mailboxes() async {
    try {
      final response = await _client.functions
          .invoke('mail-sync', body: {'action': 'prepare'});
      final data = response.data;
      if (data is Map && data['mailboxes'] is List) {
        return _mailboxes(data['mailboxes'] as List);
      }
    } catch (_) {
      // Sin la función igual se listan las que ya existen.
    }
    final tenants = TenantService();
    final tenantId = tenants.currentTenantId ?? await tenants.getTenantId();
    if (tenantId == null) return const [];
    final rows = await _client
        .from('mail_mailboxes')
        .select(
            'id, provider, address, is_active, last_synced_at, last_sync_error, backfilled_at')
        .eq('tenant_id', tenantId)
        .order('address');
    return _mailboxes(rows as List);
  }

  List<MailboxInfo> _mailboxes(List rows) => rows
      .whereType<Map>()
      .map((raw) => MailboxInfo.fromJson(Map<String, dynamic>.from(raw)))
      .toList(growable: false);

  /// Sólo el dueño o un administrador: una casilla encendida la lee todo el
  /// equipo.
  Future<void> setMailboxActive(String id, bool active) {
    return _client.rpc('mail_set_mailbox_active_v1', params: {
      'p_mailbox_id': id,
      'p_active': active,
    });
  }

  /// `read`, `unread`, `done`, `undone`, `archive` o `unarchive`.
  Future<int> mark(List<String> ids, String op) async {
    if (ids.isEmpty) return 0;
    final result = await _client.rpc('mail_mark_v1', params: {
      'p_message_ids': ids,
      'p_op': op,
    });
    return (result as num?)?.toInt() ?? 0;
  }

  Future<List<MailLink>> link(
    String messageId,
    String recordType,
    String recordId, {
    bool remove = false,
  }) async {
    final result = await _client.rpc('mail_link_v1', params: {
      'p_message_id': messageId,
      'p_record_type': recordType,
      'p_record_id': recordId,
      'p_remove': remove,
    });
    return (result as List? ?? const [])
        .whereType<Map>()
        .map((raw) => MailLink.fromJson(Map<String, dynamic>.from(raw)))
        .toList(growable: false);
  }

  /// Corrige el tipo; si es promoción o ruido, el remitente queda aprendido.
  Future<void> setKind(String messageId, String kind, {bool remember = true}) {
    return _client.rpc('mail_set_kind_v1', params: {
      'p_message_id': messageId,
      'p_kind': kind,
      'p_remember': remember,
    });
  }

  /// Los correos de un registro: su historia en el trabajo, el cliente, el
  /// proveedor, la compra o el pedido.
  Future<List<MailItem>> recordMessages(
      String recordType, String recordId) async {
    final result = await _client.rpc('mail_record_messages_v1', params: {
      'p_record_type': recordType,
      'p_record_id': recordId,
    });
    return _items(result);
  }

  /// Dónde registrar una transferencia: las facturas con saldo de quien
  /// transfirió y sus pedidos web sin pagar (o, sin nombre, los de saldo
  /// exacto).
  Future<List<MailPaymentCandidate>> paymentCandidates(String messageId) async {
    final result = await _client.rpc('mail_payment_candidates_v1', params: {
      'p_message_id': messageId,
    });
    return (result as List? ?? const [])
        .whereType<Map>()
        .map((raw) =>
            MailPaymentCandidate.fromJson(Map<String, dynamic>.from(raw)))
        .toList(growable: false);
  }

  /// Pide traer lo nuevo ahora (el servidor igual lo hace cada 2 minutos).
  Future<void> syncNow() async {
    await _client.functions.invoke('mail-sync', body: {'action': 'sync'});
  }

  /// El original, para leerlo como llegó.
  Future<({String? html, String? text})> original(String messageId) async {
    final response = await _client.functions.invoke('mail-sync', body: {
      'action': 'body',
      'message_id': messageId,
    });
    final data = response.data;
    if (data is! Map) return (html: null, text: null);
    return (
      html: data['html'] is String ? data['html'] as String : null,
      text: data['text'] is String ? data['text'] as String : null,
    );
  }

  Future<MailAttachmentData> attachment(
    String messageId,
    MailAttachmentRef ref,
  ) async {
    final response = await _client.functions.invoke('mail-sync', body: {
      'action': 'attachment',
      'message_id': messageId,
      if (ref.attachmentId != null) 'attachment_id': ref.attachmentId,
      if (ref.attachmentId == null && ref.partId != null) 'part_id': ref.partId,
    });
    final data = response.data;
    if (data is! Map || data['data_base64'] is! String) {
      throw StateError('El adjunto no llegó.');
    }
    return MailAttachmentData(
      filename: '${data['filename'] ?? ref.filename}',
      mimeType: '${data['mime_type'] ?? ref.mimeType}',
      bytes: base64Decode(data['data_base64'] as String),
    );
  }

  List<MailItem> _items(Object? result) => (result as List? ?? const [])
      .whereType<Map>()
      .map((raw) => MailItem.fromJson(Map<String, dynamic>.from(raw)))
      .where((item) => item.id.isNotEmpty)
      .toList(growable: false);
}
