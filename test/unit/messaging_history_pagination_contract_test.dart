import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String serviceSource;
  late String providerSource;
  late String employeeTimelineSource;
  late String customerTimelineSource;

  setUpAll(() {
    serviceSource = File(
      'lib/modules/messaging/services/messaging_service.dart',
    ).readAsStringSync();
    providerSource = File(
      'lib/modules/messaging/providers/chat_provider.dart',
    ).readAsStringSync();
    employeeTimelineSource = File(
      'lib/modules/messaging/widgets/chat_window.dart',
    ).readAsStringSync();
    customerTimelineSource = File(
      'lib/public_store/widgets/customer_chat_view.dart',
    ).readAsStringSync();
  });

  test('older history uses an exclusive durable sequence cursor', () {
    expect(serviceSource,
        contains('Future<MessageHistoryPage> getMessagesBefore('));
    expect(serviceSource, contains(".lt('message_sequence', beforeSequence)"));
    expect(serviceSource, contains('.limit(safeLimit + 1)'));
    expect(serviceSource, contains('nextBeforeSequence: nextBeforeSequence'));
  });

  test('late pages merge into the requested chat without replacing selection',
      () {
    expect(providerSource, contains('Future<void> loadOlderMessages('));
    expect(
      providerSource,
      contains('_activeConversationId != conversationId'),
    );
    expect(providerSource, contains('currentTimeline: latestTimeline'));
    expect(providerSource, contains('preserveFullHistory: true'));
    expect(providerSource, contains('nextCursor < currentCursor'));
  });

  test('employee and customer readers load at the oldest edge and can retry',
      () {
    for (final source in [employeeTimelineSource, customerTimelineSource]) {
      expect(source, contains('_requestOlderMessagesIfAtStart'));
      expect(source, contains('provider.loadOlderMessages(conversationId)'));
      expect(source, contains('provider.retryOlderMessages(conversationId)'));
      expect(source, contains('provider.retryConversationMessages('));
      expect(source, contains('Cargar mensajes anteriores'));
    }
  });

  test('stream failure is scoped to the conversation and remains recoverable',
      () {
    expect(providerSource, contains('_messageStreamErrorByConversation'));
    expect(providerSource, contains('messageStreamErrorForConversation('));
    expect(providerSource, contains('retryConversationMessages('));
    expect(providerSource, contains('_messagesRetryAttempt = 0'));
  });
}
