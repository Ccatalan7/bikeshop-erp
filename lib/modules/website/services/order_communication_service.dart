import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/order_communication.dart';

/// Read-only access to the immutable communication evidence for one order.
///
/// Sending, retrying and delivery-state mutation remain server-owned. This
/// service intentionally exposes no client-side resend or status writer.
class OrderCommunicationService {
  OrderCommunicationService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Future<List<OrderCommunication>> listForOrder(String orderId) async {
    final rawMessages = await _client
        .from('transactional_email_outbox')
        .select(
          'id,order_id,message_kind,template_version,recipient_email,subject,'
          'delivery_mode,state,attempt_count,provider,provider_message_id,'
          'last_error_class,last_error_message,created_at,rendered_at,'
          'submitted_at,delivered_at,bounced_at,complained_at,failed_at',
        )
        .eq('order_id', orderId)
        .order('created_at', ascending: false);

    final messageRows = List<Map<String, dynamic>>.from(rawMessages);
    if (messageRows.isEmpty) return const [];

    final messageIds = messageRows.map((row) => row['id'] as String).toList();
    final rawEvents = await _client
        .from('transactional_email_provider_events')
        .select('id,outbox_id,event_type,occurred_at,received_at')
        .inFilter('outbox_id', messageIds)
        .order('occurred_at');

    final eventsByMessage = <String, List<OrderCommunicationProviderEvent>>{};
    for (final row in List<Map<String, dynamic>>.from(rawEvents)) {
      final outboxId = row['outbox_id'] as String?;
      if (outboxId == null) continue;
      eventsByMessage
          .putIfAbsent(outboxId, () => [])
          .add(OrderCommunicationProviderEvent.fromJson(row));
    }

    return messageRows
        .map(
          (row) => OrderCommunication.fromJson(
            row,
            providerEvents: eventsByMessage[row['id']] ?? const [],
          ),
        )
        .toList(growable: false);
  }
}
