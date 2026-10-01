import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// An upload can leave private bytes without a task link when its response is
/// lost. Keep only the IDs needed to find that object again; file bytes and
/// names remain outside preferences.
class TaskUploadCleanupIntent {
  const TaskUploadCleanupIntent({
    required this.tenantId,
    required this.userId,
    required this.taskId,
    required this.attachmentId,
    required this.ownerSession,
    required this.createdAt,
    this.abandonedAt,
  });

  final String tenantId;
  final String userId;
  final String taskId;
  final String attachmentId;
  final String ownerSession;
  final DateTime createdAt;
  final DateTime? abandonedAt;

  static const _prefix = 'task-upload-cleanup-v1';
  static final _uuid = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );

  static String scopePrefix(String tenantId, String userId) {
    if (!_uuid.hasMatch(tenantId) || !_uuid.hasMatch(userId)) {
      throw const FormatException('Invalid task upload cleanup scope');
    }
    return '$_prefix:$tenantId:$userId:';
  }

  String get key {
    if (!_uuid.hasMatch(taskId) ||
        !_uuid.hasMatch(attachmentId) ||
        !_uuid.hasMatch(ownerSession)) {
      throw const FormatException('Invalid task upload cleanup identity');
    }
    return '${scopePrefix(tenantId, userId)}$attachmentId';
  }

  String encode() => jsonEncode({
        'tenant_id': tenantId,
        'user_id': userId,
        'task_id': taskId,
        'attachment_id': attachmentId,
        'owner_session': ownerSession,
        'created_at': createdAt.toUtc().toIso8601String(),
        if (abandonedAt != null)
          'abandoned_at': abandonedAt!.toUtc().toIso8601String(),
      });

  static TaskUploadCleanupIntent decode(String key, String encoded) {
    final value = jsonDecode(encoded);
    if (value is! Map<String, dynamic>) {
      throw const FormatException('Invalid task upload cleanup record');
    }
    final intent = TaskUploadCleanupIntent(
      tenantId: value['tenant_id'] as String,
      userId: value['user_id'] as String,
      taskId: value['task_id'] as String,
      attachmentId: value['attachment_id'] as String,
      ownerSession: value['owner_session'] as String,
      createdAt: DateTime.parse(value['created_at'] as String),
      abandonedAt: value['abandoned_at'] == null
          ? null
          : DateTime.parse(value['abandoned_at'] as String),
    );
    if (intent.key != key) {
      throw const FormatException('Task upload cleanup identity mismatch');
    }
    return intent;
  }

  TaskUploadCleanupIntent abandon(DateTime now) => TaskUploadCleanupIntent(
        tenantId: tenantId,
        userId: userId,
        taskId: taskId,
        attachmentId: attachmentId,
        ownerSession: ownerSession,
        createdAt: createdAt,
        abandonedAt: now,
      );
}

abstract interface class TaskUploadCleanupStore {
  Future<Map<String, String>> readAll(String prefix);
  Future<void> write(String key, String value);
  Future<void> remove(String key);
}

class SharedPreferencesTaskUploadCleanupStore
    implements TaskUploadCleanupStore {
  SharedPreferences? _preferences;

  Future<SharedPreferences> _instance() async =>
      _preferences ??= await SharedPreferences.getInstance();

  @override
  Future<Map<String, String>> readAll(String prefix) async {
    final preferences = await _instance();
    await preferences.reload();
    return {
      for (final key in preferences.getKeys())
        if (key.startsWith(prefix) && preferences.getString(key) != null)
          key: preferences.getString(key)!,
    };
  }

  @override
  Future<void> write(String key, String value) async {
    if (!await (await _instance()).setString(key, value)) {
      throw StateError('Task upload cleanup intent was not saved');
    }
  }

  @override
  Future<void> remove(String key) async {
    if (!await (await _instance()).remove(key)) {
      throw StateError('Task upload cleanup intent was not removed');
    }
  }
}

class TaskUploadCleanupJournal {
  TaskUploadCleanupJournal({TaskUploadCleanupStore? store})
      : _store = store ?? SharedPreferencesTaskUploadCleanupStore();

  final TaskUploadCleanupStore _store;

  Future<void> remember(TaskUploadCleanupIntent intent) async {
    final previous = (await _store.readAll(
      TaskUploadCleanupIntent.scopePrefix(intent.tenantId, intent.userId),
    ))[intent.key];
    if (previous != null) {
      final existing = TaskUploadCleanupIntent.decode(intent.key, previous);
      if (existing.taskId != intent.taskId ||
          existing.ownerSession != intent.ownerSession) {
        throw StateError(
          'El archivo pendiente pertenece a otra sesión o tarea; '
          'vuelve a seleccionarlo',
        );
      }
    }
    await _store.write(intent.key, intent.encode());
  }

  Future<void> forget(TaskUploadCleanupIntent intent) async {
    final previous = (await _store.readAll(
      TaskUploadCleanupIntent.scopePrefix(intent.tenantId, intent.userId),
    ))[intent.key];
    if (previous == null) return;
    final existing = TaskUploadCleanupIntent.decode(intent.key, previous);
    if (existing.taskId != intent.taskId ||
        existing.ownerSession != intent.ownerSession) {
      // A concurrent session may have replaced this value between the link
      // acknowledgement and local cleanup. Leave its recovery intent intact.
      return;
    }
    await _store.remove(intent.key);
  }

  Future<List<TaskUploadCleanupIntent>> pendingFor(
    String tenantId,
    String userId,
  ) async {
    final entries = await _store.readAll(
      TaskUploadCleanupIntent.scopePrefix(tenantId, userId),
    );
    final intents = [
      for (final entry in entries.entries)
        TaskUploadCleanupIntent.decode(entry.key, entry.value),
    ]..sort((a, b) {
        final byTime = a.createdAt.compareTo(b.createdAt);
        return byTime != 0 ? byTime : a.attachmentId.compareTo(b.attachmentId);
      });
    return intents;
  }
}
