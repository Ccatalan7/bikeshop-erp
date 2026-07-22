import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Meta messaging frontend architecture', () {
    test('canonical inbox keeps both Meta channels and a future fallback', () {
      final source = File(
        'lib/modules/messaging/pages/employee_chat_page.dart',
      ).readAsStringSync();

      expect(source, contains('conversation.isInstagram'));
      expect(source, contains('conversation.isFacebookMessenger'));
      expect(source, contains("title: 'Instagram'"));
      expect(source, contains("title: 'Facebook Messenger'"));
      expect(source, contains('otherChannelConvs'));
    });

    test('Meta text never falls through to the local message insert path', () {
      final windowSource = File(
        'lib/modules/messaging/widgets/chat_window.dart',
      ).readAsStringSync();
      final providerSource = File(
        'lib/modules/messaging/providers/chat_provider.dart',
      ).readAsStringSync();

      expect(windowSource, contains('_dispatchMetaSend'));
      expect(windowSource, contains('_metaMessagingService.sendText'));
      expect(
        windowSource,
        contains('!_isWhatsAppConversation && !_isMetaConversation'),
      );
      expect(windowSource, contains("'retry_disabled': true"));
      expect(windowSource, contains('_supportsOutgoingAttachments'));
      expect(providerSource, contains('targetConversation?.isMetaMessaging'));
      expect(providerSource, contains('transporte Meta server-side'));
    });

    test('open and resume recover exact durable outbound attempts', () {
      final serviceSource = File(
        'lib/modules/messaging/services/meta_messaging_service.dart',
      ).readAsStringSync();
      final providerSource = File(
        'lib/modules/messaging/providers/chat_provider.dart',
      ).readAsStringSync();
      final windowSource = File(
        'lib/modules/messaging/widgets/chat_window.dart',
      ).readAsStringSync();

      expect(
        serviceSource,
        contains("'list_meta_outbound_send_receipts'"),
      );
      expect(serviceSource, contains("'p_conversation_id': conversationId"));
      expect(providerSource, contains('refreshMetaConversationState'));
      expect(providerSource, contains('_reconcileMetaOutboundReceipts'));
      expect(providerSource, contains('setApplicationForeground'));
      expect(windowSource, contains('recovered_outbound_attempt'));
      expect(
        windowSource,
        contains('Preparado, resultado incierto · no reenviar'),
      );
      expect(windowSource, contains('Resultado incierto · no reenviar'));
    });

    test('composer uses least-privilege transport state and fails closed', () {
      final serviceSource = File(
        'lib/modules/messaging/services/meta_messaging_service.dart',
      ).readAsStringSync();
      final providerSource = File(
        'lib/modules/messaging/providers/chat_provider.dart',
      ).readAsStringSync();
      final windowSource = File(
        'lib/modules/messaging/widgets/chat_window.dart',
      ).readAsStringSync();

      expect(
        serviceSource,
        contains("'get_meta_conversation_transport'"),
      );
      expect(serviceSource, isNot(contains('meta_conversation_bindings')));
      expect(serviceSource, contains("'p_conversation_id': conversationId"));
      expect(providerSource, contains('_metaOutboundReceiptSnapshots'));
      expect(
        providerSource,
        contains('hasCompleteMetaConversationStateSnapshot'),
      );
      expect(providerSource, contains('transport?.canReply == true'));
      expect(providerSource, contains('canReplyToMetaConversation'));
      expect(
        windowSource,
        contains('hasCompleteMetaConversationStateSnapshot'),
      );
      expect(
        windowSource,
        contains('canReplyToMetaConversation'),
      );
    });

    test('notification entries route to the exact conversation', () {
      final panelSource = File(
        'lib/shared/widgets/notifications_panel.dart',
      ).readAsStringSync();
      final mainSource = File('lib/main.dart').readAsStringSync();

      expect(
        panelSource,
        contains("queryParameters: {'conversation': conversation.id}"),
      );
      expect(panelSource, contains("startsWith('meta_instagram_')"));
      expect(panelSource, contains("startsWith('meta_facebook_')"));
      expect(mainSource, contains("startsWith('meta_instagram_')"));
      expect(mainSource, contains("startsWith('meta_facebook_')"));
      expect(
        mainSource,
        contains("queryParameters: {'conversation': conversationId}"),
      );
    });
  });
}
