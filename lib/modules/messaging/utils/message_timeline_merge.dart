import '../models/message.dart';

Message? latestMessageByTimelineOrder(Iterable<Message> messages) {
  Message? latest;
  for (final message in messages) {
    if (latest == null || compareMessageTimelineOrder(latest, message) < 0) {
      latest = message;
    }
  }
  return latest;
}

bool hasMessageAfterReadCursor({
  required int? latestSequence,
  required int? readSequence,
  required DateTime latestCreatedAt,
  required DateTime readCreatedAt,
}) {
  if (latestSequence != null && readSequence != null) {
    return latestSequence > readSequence;
  }
  return latestCreatedAt.isAfter(readCreatedAt);
}

/// Oldest durable cursor currently represented in one conversation timeline.
/// Optimistic and legacy rows without a server sequence are intentionally
/// ignored because they cannot delimit an authoritative history page.
int? oldestDurableMessageSequence(Iterable<Message> messages) {
  int? oldest;
  for (final message in messages) {
    final sequence = message.messageSequence;
    if (sequence == null) continue;
    if (oldest == null || sequence < oldest) oldest = sequence;
  }
  return oldest;
}

/// Combines an older REST snapshot with the current live timeline without ever
/// dropping messages that are already known by Realtime. When both sources
/// contain the same server message, the current timeline wins because it can
/// include newer delivery/read metadata.
List<Message> mergeMessageTimelinesMonotonically({
  required Iterable<Message> olderSnapshot,
  required Iterable<Message> currentTimeline,
  int? limit = 250,
}) {
  final byId = <String, Message>{};
  for (final message in olderSnapshot) {
    byId[message.id] = message;
  }
  for (final message in currentTimeline) {
    byId[message.id] = message;
  }

  final merged = byId.values.toList(growable: false)
    ..sort(compareMessageTimelineOrder);
  if (limit == null || merged.length <= limit) return merged;
  if (limit <= 0) return const [];
  return merged.sublist(merged.length - limit);
}
