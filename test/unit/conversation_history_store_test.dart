import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/messaging/models/message.dart';
import 'package:vinabike_erp/modules/messaging/services/conversation_history_store.dart';

/// A chat opens on what this device already has. The store keeps the recent
/// durable rows of a conversation and hands them back on the next launch;
/// optimistic rows belong to the session that made them and are never saved.
Message _row(
  String id, {
  int? sequence,
  bool pending = false,
  String conversationId = 'conv-1',
}) {
  return Message(
    id: id,
    conversationId: conversationId,
    senderId: 'user-1',
    content: 'hola $id',
    type: 'text',
    metadata: {if (pending) 'pending': true, 'client_message_id': id},
    createdAt: DateTime.utc(2026, 9, 3, 12, sequence ?? 0),
    messageSequence: sequence,
  );
}

void main() {
  late Directory directory;
  late ConversationHistoryStore store;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('chat-history-test');
    store = ConversationHistoryStore(
      directory: directory,
      messagesPerConversation: 3,
      writeDebounce: const Duration(milliseconds: 10),
    );
  });

  tearDown(() async {
    store.dispose();
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  test('saves the newest durable rows and reads them back in order', () async {
    store.scheduleWrite('conv-1', [
      _row('m1', sequence: 1),
      _row('m2', sequence: 2),
      _row('m3', sequence: 3),
      _row('m4', sequence: 4),
      _row('temp-5', pending: true),
      _row('draft-6'),
    ]);
    await Future<void>.delayed(const Duration(milliseconds: 60));

    final restored = await store.read('conv-1', currentUserId: 'user-1');
    expect(restored.map((m) => m.id), ['m2', 'm3', 'm4'],
        reason: 'Three newest durable rows; optimistic rows are not history.');
    expect(restored.every((m) => m.isMe), isTrue);
    expect(restored.first.messageSequence, 2);
  });

  test('the last scheduled snapshot wins and a missing chat is empty',
      () async {
    store.scheduleWrite('conv-1', [_row('m1', sequence: 1)]);
    store.scheduleWrite('conv-1', [_row('m9', sequence: 9)]);
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect((await store.read('conv-1')).map((m) => m.id), ['m9']);
    expect(await store.read('conv-none'), isEmpty);
  });

  test('a corrupt file is an empty start, never an error', () async {
    await File('${directory.path}/conv-1.json').writeAsString('{not json');
    expect(await store.read('conv-1'), isEmpty);
  });

  test('clear drops every saved conversation', () async {
    store.scheduleWrite('conv-1', [_row('m1', sequence: 1)]);
    await Future<void>.delayed(const Duration(milliseconds: 60));
    await store.clear();
    expect(await store.read('conv-1'), isEmpty);
  });
}
