import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/message.dart';

/// The last messages of each conversation, on this device.
///
/// WhatsApp opens a chat on what it already has and syncs behind it. The ERP
/// kept its conversation history only in memory, so every app launch opened
/// each chat on a spinner and a network round trip. This store writes the
/// recent timeline after every change and hands it back before the stream's
/// first frame; the stream then merges over it as it always did. It is a
/// projection, never authority: a corrupt or missing file is simply an empty
/// start, and nothing here is written back to the server.
class ConversationHistoryStore {
  ConversationHistoryStore({
    int? messagesPerConversation,
    Directory? directory,
    Duration? writeDebounce,
  })  : messagesPerConversation = messagesPerConversation ?? 80,
        _writeDebounce = writeDebounce ?? const Duration(milliseconds: 600),
        _directory = directory == null ? null : Future.value(directory);

  final int messagesPerConversation;
  final Duration _writeDebounce;
  Future<Directory?>? _directory;
  final Map<String, Timer> _pendingWrites = <String, Timer>{};
  final Map<String, List<Message>> _pendingSnapshots =
      <String, List<Message>>{};

  Future<Directory?> _root() {
    if (kIsWeb) return Future.value(null);
    return _directory ??= () async {
      try {
        final base = await getApplicationSupportDirectory();
        final directory = Directory('${base.path}/chat-history');
        await directory.create(recursive: true);
        return directory;
      } catch (error) {
        debugPrint('ConversationHistoryStore: sin directorio: $error');
        return null;
      }
    }();
  }

  Future<File?> _fileFor(String conversationId) async {
    final directory = await _root();
    if (directory == null) return null;
    final safe = conversationId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    return File('${directory.path}/$safe.json');
  }

  /// Messages saved for [conversationId], oldest first; empty when none.
  Future<List<Message>> read(
    String conversationId, {
    String? currentUserId,
  }) async {
    final file = await _fileFor(conversationId);
    if (file == null) return const [];
    try {
      if (!await file.exists()) return const [];
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map || decoded['messages'] is! List) return const [];
      final rows = (decoded['messages'] as List).whereType<Map>();
      final messages = <Message>[];
      for (final row in rows) {
        try {
          messages.add(
            Message.fromJson(
              Map<String, dynamic>.from(row),
              currentUserId: currentUserId,
            ),
          );
        } catch (_) {
          // One bad row does not cost the whole chat.
        }
      }
      messages.sort(compareMessageTimelineOrder);
      return messages;
    } catch (error) {
      debugPrint('ConversationHistoryStore: no se pudo leer: $error');
      return const [];
    }
  }

  /// Schedules a write of the newest [messagesPerConversation] rows.
  /// Optimistic rows (no durable sequence, or still pending) are skipped:
  /// they belong to this session, not to the next launch.
  void scheduleWrite(String conversationId, List<Message> messages) {
    if (kIsWeb) return;
    final durable = messages
        .where(
          (message) =>
              message.messageSequence != null &&
              message.metadata['pending'] != true,
        )
        .toList(growable: false);
    final tail = durable.length > messagesPerConversation
        ? durable.sublist(durable.length - messagesPerConversation)
        : durable;
    _pendingSnapshots[conversationId] = tail;
    _pendingWrites[conversationId]?.cancel();
    _pendingWrites[conversationId] = Timer(_writeDebounce, () {
      _pendingWrites.remove(conversationId);
      final snapshot = _pendingSnapshots.remove(conversationId);
      if (snapshot != null) unawaited(_write(conversationId, snapshot));
    });
  }

  Future<void> _write(String conversationId, List<Message> messages) async {
    final file = await _fileFor(conversationId);
    if (file == null) return;
    try {
      final payload = jsonEncode({
        'version': 1,
        'conversation_id': conversationId,
        'saved_at': DateTime.now().toUtc().toIso8601String(),
        'messages': messages.map((message) => message.toJson()).toList(),
      });
      final temp = File('${file.path}.tmp');
      await temp.writeAsString(payload, flush: true);
      await temp.rename(file.path);
    } catch (error) {
      debugPrint('ConversationHistoryStore: no se pudo escribir: $error');
    }
  }

  /// Drops every saved conversation (sign-out, tenant change).
  Future<void> clear() async {
    for (final timer in _pendingWrites.values) {
      timer.cancel();
    }
    _pendingWrites.clear();
    _pendingSnapshots.clear();
    final directory = await _root();
    if (directory == null) return;
    try {
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
      _directory = null;
    } catch (error) {
      debugPrint('ConversationHistoryStore: no se pudo limpiar: $error');
    }
  }

  void dispose() {
    for (final timer in _pendingWrites.values) {
      timer.cancel();
    }
    _pendingWrites.clear();
    _pendingSnapshots.clear();
  }
}
