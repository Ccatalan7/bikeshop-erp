import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String mainSource;
  late String mainLayoutSource;
  late String chatWindowSource;
  late String conversationTileSource;
  late String customerPanelSource;
  late String supplierPanelSource;
  late String customerChatSource;
  late String chatProviderSource;
  late String messagingServiceSource;
  late String notificationServiceSource;
  late String whatsAppServiceSource;
  late String whatsAppReceiptSource;

  setUpAll(() {
    mainSource = File('lib/main.dart').readAsStringSync();
    mainLayoutSource = File(
      'lib/shared/widgets/main_layout.dart',
    ).readAsStringSync();
    chatWindowSource = File(
      'lib/modules/messaging/widgets/chat_window.dart',
    ).readAsStringSync();
    conversationTileSource = File(
      'lib/modules/messaging/widgets/conversation_tile.dart',
    ).readAsStringSync();
    customerPanelSource = File(
      'lib/shared/widgets/quick_messages_panel.dart',
    ).readAsStringSync();
    supplierPanelSource = File(
      'lib/shared/widgets/quick_supplier_messages_panel.dart',
    ).readAsStringSync();
    customerChatSource = File(
      'lib/public_store/widgets/customer_chat_view.dart',
    ).readAsStringSync();
    chatProviderSource = File(
      'lib/modules/messaging/providers/chat_provider.dart',
    ).readAsStringSync();
    messagingServiceSource = File(
      'lib/modules/messaging/services/messaging_service.dart',
    ).readAsStringSync();
    notificationServiceSource = File(
      'lib/shared/services/notification_service.dart',
    ).readAsStringSync();
    whatsAppServiceSource = File(
      'lib/shared/services/whatsapp_service.dart',
    ).readAsStringSync();
    whatsAppReceiptSource = File(
      'lib/shared/services/whatsapp_send_receipt.dart',
    ).readAsStringSync();
  });

  test('the stable app shell owns the only workspace push listener', () {
    expect(
      RegExp(r'notificationService\.messageStream\.listen\(')
          .allMatches(mainSource),
      hasLength(1),
    );
    expect(mainSource, contains('_handleWorkspacePush'));
    expect(mainLayoutSource, isNot(contains('messageStream.listen(')));
    expect(
      mainLayoutSource,
      isNot(contains('_pushNotificationSubscription')),
    );
    expect(
      RegExp(r'!hasForegroundPresentationOwner')
          .allMatches(notificationServiceSource),
      hasLength(2),
      reason:
          'FCM and desktop Realtime must delegate sound/banner presentation '
          'to the stable shell before a duplicate can be announced.',
    );
    expect(mainSource, contains('notificationId: eventKey.hashCode'));
  });

  test(
      'workspace notification callbacks fail closed after shell disposal or '
      'session changes', () {
    expect(mainLayoutSource, isNot(contains('_refreshOnlineOrderAlerts')));
    expect(mainLayoutSource, isNot(contains('Timer.periodic(')));
    expect(mainSource, contains('_notificationLifecycleEpoch++;'));
    expect(mainSource, contains('_erpNotificationsRefreshTimer?.cancel();'));
    expect(mainSource, contains('_erpNotificationsChannel?.unsubscribe();'));
    expect(
      mainSource,
      matches(
        RegExp(
          r'bool _isCurrentNotificationLifecycle\(String userId, int epoch\) '
          r'\{\s*return mounted &&\s*'
          r'epoch == _notificationLifecycleEpoch &&\s*'
          r'_notificationUserId == userId &&\s*'
          r'Supabase\.instance\.client\.auth\.currentUser\?\.id == userId;',
        ),
      ),
    );
  });

  test('ChatWindow does not infer provider read receipts from replies', () {
    expect(chatWindowSource, isNot(contains('_whatsAppInferredReadWindow')));
    expect(chatWindowSource, isNot(contains('_isWhatsAppMessageRead')));
    expect(chatWindowSource, isNot(contains('has_later_inbound_message')));
    expect(chatWindowSource, contains('MessageDeliveryState.fromMessage'));
  });

  test('message rows and inbox previews use the shared delivery indicator', () {
    expect(chatWindowSource, contains('MessageDeliveryIndicator('));
    expect(
      conversationTileSource,
      contains('MessageDeliveryIndicator('),
    );
    expect(
      conversationTileSource,
      contains('MessageDeliveryState.fromConversationPreview'),
    );
  });

  test('inactive WhatsApp receipts use a targeted coalesced refresh', () {
    expect(
      messagingServiceSource,
      contains('onMessageReceiptUpdate?.call(receiptUpdate)'),
    );
    expect(
      messagingServiceSource,
      contains('getMessagesByIds('),
    );
    expect(
      messagingServiceSource,
      contains('getLatestMessagesForConversations('),
    );
    expect(chatProviderSource, contains('MessageReceiptRefreshCoalescer('));
    expect(chatProviderSource, contains('_refreshMessageReceipts('));
  });

  test('WhatsApp send results are immutable and never singleton last-state',
      () {
    expect(whatsAppReceiptSource, contains('class WhatsAppSendReceipt'));
    expect(whatsAppReceiptSource, contains('final String? messageId;'));
    expect(whatsAppReceiptSource, contains('final String? externalMessageId;'));
    expect(whatsAppServiceSource, isNot(contains('_lastDeliveryMethod')));
    expect(whatsAppServiceSource, isNot(contains('_lastErrorCode')));
    expect(whatsAppServiceSource, contains('on FunctionException catch'));
    expect(
        whatsAppServiceSource, contains('messageId: _extractMessageId(data)'));
    expect(chatWindowSource, isNot(contains('whatsappService.last')));
  });

  test('Cloud dispatch is not cancelled when ChatWindow is unmounted', () {
    expect(
      chatWindowSource,
      isNot(
        matches(
          RegExp(
            r'if \(!mounted\) return;\s*final receipt = await whatsappService\.',
          ),
        ),
      ),
    );
    expect(chatWindowSource, contains('fallbackContext: dispatchContext'));
    expect(chatWindowSource, contains("'server_ack_durable': true"));
    expect(chatWindowSource, contains("'external_status': 'failed'"));
  });

  test('quick customer and supplier filters are dropdowns, not chip strips',
      () {
    for (final source in [customerPanelSource, supplierPanelSource]) {
      expect(source, contains('PopupMenuButton<'));
      expect(source, isNot(contains('ChoiceChip(')));
      expect(source, isNot(contains('FilterChip(')));
      expect(source, isNot(contains('ActionChip(')));
      expect(source, isNot(contains('InputChip(')));
      expect(source, isNot(contains('RawChip(')));
    }
  });

  test('conversation removal is archival and never a destructive client call',
      () {
    for (final source in [
      chatProviderSource,
      messagingServiceSource,
      customerPanelSource,
      supplierPanelSource,
    ]) {
      expect(source, isNot(contains('deleteConversation(')));
      expect(source, isNot(contains("rpc('delete_conversation'")));
    }
    expect(messagingServiceSource, contains("rpc('archive_conversation'"));
  });

  test('customer quote decisions use the canonical secure response RPC', () {
    expect(customerChatSource,
        contains("rpc(\n        'respond_to_action_request'"));
    expect(
        customerChatSource, contains("'response_note': responseNote!.trim()"));
    expect(customerChatSource, isNot(contains('confirm_invoice_approval')));
    expect(customerChatSource, isNot(contains('updateInvoiceStatus')));
    expect(chatWindowSource, isNot(contains('confirm_invoice_approval')));
    expect(chatWindowSource, isNot(contains('updateInvoiceStatus')));
    expect(
      chatWindowSource,
      isNot(contains("rpc(\n        'respond_to_action_request'")),
      reason: 'The employee timeline must never answer a customer action card.',
    );
  });

  test('the latest stream is bounded while the timeline remains date-aware',
      () {
    expect(
      messagingServiceSource,
      contains('recentMessageStreamLimit = 250'),
    );
    expect(
      messagingServiceSource,
      contains('.limit(recentMessageStreamLimit)'),
    );
    expect(chatWindowSource, contains('_TimelineDaySeparator'));
    expect(chatWindowSource, contains('_MessageGrouping'));
    expect(chatWindowSource, contains('_showJumpToLatest'));
    expect(chatWindowSource, contains('Ir al mensaje más reciente'));
    // Message selection/copy and gesture arbitration are exercised by
    // chat_reply_and_draft_test and chat_message_interactions_test.
    // A SelectionArea here intercepts the bubble's long press.
  });

  test('the narrow composer exposes one progressive action menu', () {
    expect(chatWindowSource, contains('_showComposerActionsMenu'));
    expect(chatWindowSource, contains("title: 'Agregar al mensaje'"));
    expect(chatWindowSource, contains("title: 'Foto o archivo'"));
    expect(chatWindowSource, contains("? 'Solicitud al cliente'"));
    expect(chatWindowSource, isNot(contains('_smartActionsButtonKey')));
    expect(chatWindowSource, isNot(contains('_attachmentButtonKey')));
    expect(chatWindowSource, isNot(contains('_templateButtonKey')));
  });

  test('shared routes persist internal identity without URL metadata', () {
    expect(chatWindowSource, contains("'share_kind': 'route'"));
    expect(chatWindowSource, contains("'route': link.route"));
    expect(chatWindowSource, isNot(contains("'deep_link': link.uri")));
    expect(chatWindowSource, isNot(contains("'web_link': link.webUri")));
  });

  test('customer chat renders real receipts and private attachments', () {
    expect(customerChatSource, contains('MessageDeliveryIndicator('));
    expect(customerChatSource, contains('MessageDeliveryState.fromMessage'));
    expect(customerChatSource, contains('MessagingAttachmentService'));
    expect(customerChatSource, contains('_CustomerTimelineItem.day'));
    expect(customerChatSource, contains('Esta conversación está archivada'));
  });

  test('notification diagnostics never print tokens or raw message payloads',
      () {
    expect(notificationServiceSource, isNot(contains('FCM TOKEN')));
    expect(notificationServiceSource, isNot(contains('Message data:')));
    expect(notificationServiceSource, isNot(contains('Raw Data:')));
    expect(notificationServiceSource, isNot(contains(r"${message.data}")));
    expect(
      notificationServiceSource,
      contains("message.data['message_id']"),
    );
    expect(
      notificationServiceSource,
      isNot(contains("message.messageId ?? message.data['conversation_id']")),
    );
  });
}
