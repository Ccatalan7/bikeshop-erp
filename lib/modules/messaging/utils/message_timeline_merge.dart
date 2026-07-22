import '../models/message.dart';

String? _messageIdentityValue(Object? value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}

/// Reconciles one optimistic row only from exact durable identities whenever
/// they exist. The text/time fallback is reserved for legacy optimistic rows
/// that predate client/server/provider IDs.
bool hasMatchingServerMessage({
  required Message optimistic,
  required Iterable<Message> serverMessages,
  Duration legacyMatchWindow = const Duration(seconds: 20),
}) {
  final serverMessageId =
      _messageIdentityValue(optimistic.metadata['server_message_id']);
  final clientMessageId =
      _messageIdentityValue(optimistic.metadata['client_message_id']);
  final externalMessageId =
      _messageIdentityValue(optimistic.metadata['external_message_id']);
  final hasDurableIdentity = serverMessageId != null ||
      clientMessageId != null ||
      externalMessageId != null;

  for (final message in serverMessages) {
    if (message.id == optimistic.id) return true;
    if (message.conversationId != optimistic.conversationId) continue;
    if (serverMessageId != null && message.id == serverMessageId) return true;

    final messageClientId =
        _messageIdentityValue(message.metadata['client_message_id']);
    if (clientMessageId != null && messageClientId == clientMessageId) {
      return true;
    }

    final messageExternalId =
        _messageIdentityValue(message.metadata['external_message_id']);
    if (externalMessageId != null && messageExternalId == externalMessageId) {
      return true;
    }

    if (hasDurableIdentity) continue;
    if (message.senderId != optimistic.senderId ||
        message.content != optimistic.content) {
      continue;
    }
    final deltaMs =
        message.createdAt.difference(optimistic.createdAt).inMilliseconds.abs();
    if (deltaMs < legacyMatchWindow.inMilliseconds) return true;
  }
  return false;
}

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
