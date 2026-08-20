import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String provider;
  late String service;
  late String tile;
  late String inboxHost;
  late String customerPanel;
  late String supplierPanel;
  late String customerChat;
  late String customerHub;
  late String registry;

  setUpAll(() {
    provider = File(
      'lib/modules/messaging/providers/chat_provider.dart',
    ).readAsStringSync();
    service = File(
      'lib/modules/messaging/services/messaging_service.dart',
    ).readAsStringSync();
    tile = File(
      'lib/modules/messaging/widgets/conversation_tile.dart',
    ).readAsStringSync();
    // 2026-08-20 · Clientes y Proveedores comparten su ciclo de vida en
    // `ConversationInboxHost`. Lo que antes estaba copiado en los dos paneles
    // ahora vive ahí una sola vez, así que cada panel se lee JUNTO al común:
    // el contrato es sobre el comportamiento, no sobre el archivo.
    inboxHost = File(
      'lib/shared/widgets/conversation_inbox_host.dart',
    ).readAsStringSync();
    customerPanel = inboxHost +
        File(
          'lib/shared/widgets/quick_messages_panel.dart',
        ).readAsStringSync();
    supplierPanel = inboxHost +
        File(
          'lib/shared/widgets/quick_supplier_messages_panel.dart',
        ).readAsStringSync();
    customerChat = File(
      'lib/public_store/widgets/customer_chat_view.dart',
    ).readAsStringSync();
    customerHub = File(
      'lib/public_store/pages/customer_chat_hub_page.dart',
    ).readAsStringSync();
    registry = File(
      'docs/architecture/canonical-ui-surfaces.md',
    ).readAsStringSync();
  });

  test('queued inbox callers await the coalesced authoritative refresh', () {
    expect(provider, contains('return pendingCompleter.future'));
    expect(provider, contains('_pendingConversationRefreshCompleter'));
    expect(provider, contains('await loadConversations('));
    expect(provider, contains('pendingCompleter.complete()'));
  });

  test('toolbar panels refresh context without repeating the full inbox read',
      () {
    expect(service, contains('getConversationContextHints('));
    expect(provider, contains('refreshConversationContextHints()'));
    expect(
      customerPanel,
      contains('.refreshConversationContextHints()'),
    );
    expect(
      supplierPanel,
      contains('.refreshConversationContextHints()'),
    );
    expect(
      customerPanel,
      contains('loadConversations(refreshContextHints: false)'),
    );
    expect(
      supplierPanel,
      contains('loadConversations(refreshContextHints: false)'),
    );
  });

  test('shared chips animate only when their visible context signature changes',
      () {
    expect(tile, contains('AnimatedSwitcher('));
    expect(tile, contains('ValueKey(signature)'));
    expect(tile, contains('Duration(milliseconds: 180)'));
    expect(tile, contains('FadeTransition('));
    expect(tile, contains('SlideTransition('));
    expect(tile, isNot(contains('ScaleTransition(')));
  });

  test('all routed and right-toolbar messaging hosts remain registered', () {
    expect(registry, contains('## Messaging Inbox Surfaces'));
    expect(registry, contains('Routed employee inbox'));
    expect(registry, contains('Right-toolbar customer messages'));
    expect(registry, contains('Right-toolbar supplier messages'));
    expect(registry, contains('tenant-and-user-scoped'));
  });

  test('session switches invalidate every messaging cache and stale callback',
      () {
    expect(provider, contains('synchronizeSessionScope('));
    expect(provider, contains('_invalidateSessionState('));
    expect(provider, contains('_sessionEpoch += 1'));
    expect(provider, contains('_messageCacheByConversation.clear()'));
    expect(provider, contains('_optimisticMessages.clear()'));
    expect(provider, contains('_isCurrentSession(operationEpoch)'));
  });

  test('prefetch cannot replace a newer realtime timeline', () {
    expect(provider, contains('revisionAtRequest'));
    expect(provider, contains('revisionNow == revisionAtRequest'));
    expect(provider, contains('mergeMessageTimelinesMonotonically('));
  });

  test('customer conversation lifecycle is realtime and fail-closed', () {
    expect(service, contains('subscribeToConversationLifecycleUpdates('));
    expect(customerHub, contains('subscribeToConversationLifecycleUpdates(()'));
    expect(customerChat,
        contains('_messagingService.subscribeToConversationLifecycleUpdates('));
    expect(customerChat, contains("status == 'loading'"));
    expect(customerChat, contains("status == 'unavailable'"));
    expect(customerChat, contains('if (!isClosed)'));
  });

  test('customer signed URL preview cache expires before server authorization',
      () {
    expect(customerChat, contains('signedUrlLifetimeSeconds - 30'));
    expect(customerChat, contains('_attachmentUrlRefreshTimer'));
    expect(customerChat, contains('entry.shouldRefresh'));
    expect(customerChat, contains('createRuntimeSignedUrl(message)'));
  });
}
