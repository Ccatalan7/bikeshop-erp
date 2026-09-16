import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Block 2a of the residual-load plan (2026-09-16): ERP notifications and
/// messaging signals travel as tenant-private Broadcast rows emitted by
/// triggers instead of postgres_changes subscriptions that Realtime has to
/// re-authorize per WAL change.
void main() {
  final migration = File(
    'supabase/migrations/'
    '20260916010000_realtime_broadcast_notifications_and_messaging.sql',
  ).readAsStringSync();
  final readback = File(
    'supabase/migrations/'
    'verify_realtime_broadcast_notifications_and_messaging.sql',
  ).readAsStringSync();
  final hub = File('lib/shared/services/tenant_broadcast_channel.dart')
      .readAsStringSync();
  final appShell = File('lib/main.dart').readAsStringSync();
  final notificationService =
      File('lib/shared/services/notification_service.dart').readAsStringSync();
  final messagingService =
      File('lib/modules/messaging/services/messaging_service.dart')
          .readAsStringSync();
  final chatProvider =
      File('lib/modules/messaging/providers/chat_provider.dart')
          .readAsStringSync();
  final storeShell = File('lib/main_store.dart').readAsStringSync();

  test('notification topics are private, per recipient and tenant-scoped', () {
    expect(migration,
        contains("'erp-notifications:' || (v_record ->> 'tenant_id') || ':'"));
    expect(
        migration,
        contains(
            "coalesce(nullif(v_record ->> 'recipient_user_id', ''), 'all')"));
    expect(
        migration,
        contains(
            "'erp-notifications:' || (select public.user_tenant_id())::text || ':all'"));
    expect(migration, contains("|| (select auth.uid())::text"));
    expect(migration, contains("extension = 'broadcast'"));
    expect(migration, isNot(contains('alter publication supabase_realtime')));
    // Authorization rows are synthetic and rolled back: never filter them
    // by the durable `private` column (20260726170500).
    expect(migration, isNot(contains('and private is true')));
    expect(readback, contains("qual like '%erp-notifications:%'"));
  });

  test('messaging payload carries ids and delivery status, never content', () {
    expect(migration, contains("'messaging:' || v_tenant_id::text"));
    expect(migration, contains("'message_id', v_record ->> 'id'"));
    expect(migration,
        contains("'external_status', v_record ->> 'external_status'"));
    expect(migration, isNot(contains("'content'")));
    expect(migration, isNot(contains("'sender_id'")));
    expect(readback, contains('messaging_payload_carries_no_content'));
    expect(migration, contains('trg_conversation_participants_broadcast'));
  });

  test('the hub joins each topic once, privately, with the session token', () {
    expect(hub, contains('RealtimeChannelConfig(private: true)'));
    expect(hub, contains('client.realtime.setAuth('));
    expect(hub, contains("onBroadcast(event: 'changed'"));
    expect(hub, contains('if (listeners.isNotEmpty) return;'));
    expect(hub, isNot(contains('onPostgresChanges')));
  });

  test('the workspace no longer subscribes to erp_notifications changes', () {
    expect(appShell, isNot(contains("table: 'erp_notifications'")));
    expect(
        appShell,
        contains(
            "erpNotificationsTopic(tenantId: tenantId, recipient: userId)"));
    expect(
        appShell,
        contains(
            "erpNotificationsTopic(tenantId: tenantId, recipient: 'all')"));
    expect(appShell,
        contains("allowPresentation: payload['operation'] == 'insert'"));
    expect(appShell, contains('ChatInboxTransport.tenantBroadcast'));
  });

  test('desktop toasts re-read the message under RLS before presenting', () {
    expect(notificationService, isNot(contains("table: 'messages'")));
    expect(notificationService, contains('messagingTopic(tenantId)'));
    expect(notificationService, contains("payload['operation'] != 'insert'"));
    expect(notificationService, contains(".from('messages')"));
    expect(notificationService, contains('.maybeSingle()'));
    expect(notificationService,
        contains('if (senderId == currentUserId) return;'));
  });

  test('the staff inbox uses the broadcast topic and keeps a fallback', () {
    expect(messagingService, contains('subscribeToTenantMessagingUpdates'));
    expect(messagingService, contains("payload['operation'] == 'update'"));
    expect(chatProvider, contains('_initTenantBroadcastListener'));
    expect(chatProvider, contains('_initPostgresChangesListener(epoch)'));
    expect(chatProvider, contains('TenantBroadcastStatus.degraded'));
    // Receipts from the broadcast path never merge into cached messages:
    // the payload has no content and the coalesced re-read paints them.
    final broadcastListener = chatProvider.substring(
      chatProvider.indexOf('Future<void> _initTenantBroadcastListener'),
      chatProvider.indexOf('_inboxBroadcastListener = listener;'),
    );
    expect(broadcastListener, isNot(contains('_applyRealtimeReceipt(')));
    // The storefront keeps the RLS-scoped postgres_changes inbox.
    expect(storeShell, contains('ChatProvider()'));
    expect(storeShell, isNot(contains('ChatInboxTransport.tenantBroadcast')));
  });
}
