import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String provider;
  late String service;
  late String tile;
  late String customerPanel;
  late String supplierPanel;
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
    customerPanel = File(
      'lib/shared/widgets/quick_messages_panel.dart',
    ).readAsStringSync();
    supplierPanel = File(
      'lib/shared/widgets/quick_supplier_messages_panel.dart',
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
}
