import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/messaging/models/message.dart';
import 'package:vinabike_erp/modules/messaging/utils/message_timeline_merge.dart';

Message _message(
  String id,
  int minute, {
  String status = 'sent',
  int? sequence,
}) {
  return Message(
    id: id,
    conversationId: 'conversation-1',
    content: id,
    type: 'text',
    metadata: {'external_status': status},
    createdAt: DateTime.utc(2026, 7, 19, 12, minute),
    messageSequence: sequence,
  );
}

void main() {
  test('parses the durable message sequence from database rows', () {
    final message = Message.fromJson({
      'id': 'm-sequenced',
      'conversation_id': 'conversation-1',
      'content': 'Hola',
      'type': 'text',
      'metadata': <String, dynamic>{},
      'created_at': '2026-07-19T12:01:00Z',
      'message_sequence': '42',
    });

    expect(message.messageSequence, 42);
  });

  test('older prefetch cannot drop messages already observed by Realtime', () {
    final merged = mergeMessageTimelinesMonotonically(
      olderSnapshot: [_message('m1', 1), _message('m2', 2)],
      currentTimeline: [_message('m1', 1), _message('m3', 3)],
    );

    expect(merged.map((message) => message.id), ['m1', 'm2', 'm3']);
  });

  test('current timeline wins when delivery metadata is newer', () {
    final merged = mergeMessageTimelinesMonotonically(
      olderSnapshot: [_message('m1', 1, status: 'sent')],
      currentTimeline: [_message('m1', 1, status: 'read')],
    );

    expect(merged.single.metadata['external_status'], 'read');
  });

  test('bounded merge keeps the newest messages', () {
    final merged = mergeMessageTimelinesMonotonically(
      olderSnapshot: [_message('m1', 1), _message('m2', 2)],
      currentTimeline: [_message('m3', 3)],
      limit: 2,
    );

    expect(merged.map((message) => message.id), ['m2', 'm3']);
  });

  test('history-page merge keeps every loaded row and deduplicates live rows',
      () {
    final merged = mergeMessageTimelinesMonotonically(
      olderSnapshot: [
        _message('m1', 1, sequence: 1),
        _message('m2', 2, sequence: 2, status: 'sent'),
      ],
      currentTimeline: [
        _message('m2', 2, sequence: 2, status: 'read'),
        _message('m3', 3, sequence: 3),
      ],
      limit: null,
    );

    expect(merged.map((message) => message.id), ['m1', 'm2', 'm3']);
    expect(merged[1].metadata['external_status'], 'read');
  });

  test('oldest durable cursor ignores optimistic messages', () {
    expect(
      oldestDurableMessageSequence([
        _message('optimistic', 0),
        _message('m42', 1, sequence: 42),
        _message('m41', 2, sequence: 41),
      ]),
      41,
    );
    expect(oldestDurableMessageSequence([_message('optimistic', 0)]), isNull);
  });

  test('durable sequence resolves equal server timestamps', () {
    final lowerSequence = _message('z-low', 1, sequence: 41);
    final higherSequence = _message('a-high', 1, sequence: 42);

    final merged = mergeMessageTimelinesMonotonically(
      olderSnapshot: [higherSequence],
      currentTimeline: [lowerSequence],
    );

    expect(merged.map((message) => message.id), ['z-low', 'a-high']);
    expect(
      latestMessageByTimelineOrder(merged)?.id,
      'a-high',
      reason: 'The exact later message must remain the read-through target.',
    );
  });

  test('legacy and optimistic ties fall back deterministically to ID', () {
    final merged = mergeMessageTimelinesMonotonically(
      olderSnapshot: [_message('message-b', 1)],
      currentTimeline: [_message('message-a', 1)],
    );

    expect(merged.map((message) => message.id), ['message-a', 'message-b']);
  });

  test('a higher sequence stays unread when createdAt is tied', () {
    final tiedTimestamp = DateTime.utc(2026, 7, 19, 12, 1);

    expect(
      hasMessageAfterReadCursor(
        latestSequence: 42,
        readSequence: 41,
        latestCreatedAt: tiedTimestamp,
        readCreatedAt: tiedTimestamp,
      ),
      isTrue,
    );
    expect(
      hasMessageAfterReadCursor(
        latestSequence: 41,
        readSequence: 41,
        latestCreatedAt: tiedTimestamp,
        readCreatedAt: tiedTimestamp,
      ),
      isFalse,
    );
  });
}
