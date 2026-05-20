import 'package:flutter/foundation.dart'
    show TargetPlatform, debugPrint, defaultTargetPlatform, kIsWeb;
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import '../providers/email_provider.dart';

/// Local SQLite cache for emails to enable instant loading and offline access
class EmailCacheService {
  static final EmailCacheService _instance = EmailCacheService._internal();
  factory EmailCacheService() => _instance;
  EmailCacheService._internal();

  Database? _database;
  bool _initialized = false;

  bool get _supportsLocalCache {
    if (kIsWeb) return false;

    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS;
  }

  /// Initialize the cache database
  Future<void> initialize() async {
    if (_initialized) return;
    if (!_supportsLocalCache) {
      _initialized = true;
      debugPrint(
        '📧 [EmailCache] Local SQLite cache skipped on $defaultTargetPlatform',
      );
      return;
    }

    try {
      final dbPath = await getDatabasesPath();
      final path = p.join(dbPath, 'email_cache.db');

      _database = await openDatabase(
        path,
        version: 1,
        onCreate: (db, version) async {
          // Emails table - stores email metadata
          await db.execute('''
          CREATE TABLE emails (
            id TEXT PRIMARY KEY,
            provider_id TEXT NOT NULL,
            folder_id TEXT NOT NULL,
            subject TEXT NOT NULL,
            from_address TEXT NOT NULL,
            to_address TEXT NOT NULL,
            cc_address TEXT,
            summary TEXT,
            thread_id TEXT,
            received_time INTEGER NOT NULL,
            sent_time INTEGER,
            is_read INTEGER NOT NULL DEFAULT 0,
            has_attachment INTEGER NOT NULL DEFAULT 0,
            cached_at INTEGER NOT NULL
          )
        ''');

          // Email content table - stores full email body separately
          await db.execute('''
          CREATE TABLE email_content (
            email_id TEXT PRIMARY KEY,
            content TEXT NOT NULL,
            cached_at INTEGER NOT NULL
          )
        ''');

          // Index for faster queries
          await db.execute(
              'CREATE INDEX idx_emails_provider ON emails(provider_id)');
          await db.execute(
              'CREATE INDEX idx_emails_received ON emails(received_time DESC)');
        },
      );

      debugPrint('📧 [EmailCache] Database initialized');
    } catch (e) {
      _database = null;
      debugPrint('📧 [EmailCache] Local cache disabled: $e');
    } finally {
      _initialized = true;
    }
  }

  /// Cache a list of emails (metadata only)
  Future<void> cacheEmails(List<Email> emails) async {
    if (_database == null || !_supportsLocalCache) return;

    final batch = _database!.batch();
    final now = DateTime.now().millisecondsSinceEpoch;

    for (final email in emails) {
      batch.insert(
        'emails',
        {
          'id': email.id,
          'provider_id': email.providerId,
          'folder_id': email.folderId,
          'subject': email.subject,
          'from_address': email.fromAddress,
          'to_address': email.toAddress,
          'cc_address': email.ccAddress,
          'summary': email.summary,
          'thread_id': email.threadId,
          'received_time': email.receivedTime.millisecondsSinceEpoch,
          'sent_time': email.sentTime?.millisecondsSinceEpoch,
          'is_read': email.isRead ? 1 : 0,
          'has_attachment': email.hasAttachment ? 1 : 0,
          'cached_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }

    await batch.commit(noResult: true);
    debugPrint('📧 [EmailCache] Cached ${emails.length} emails');
  }

  /// Get cached emails (sorted by received time, newest first)
  Future<List<Email>> getCachedEmails({String? providerId}) async {
    if (_database == null || !_supportsLocalCache) return [];

    final where = providerId != null ? 'provider_id = ?' : null;
    final whereArgs = providerId != null ? [providerId] : null;

    final rows = await _database!.query(
      'emails',
      where: where,
      whereArgs: whereArgs,
      orderBy: 'received_time DESC',
      limit: 500, // Keep enough local history for real inbox navigation.
    );

    return rows.map((row) {
      final sentTimeMs = row['sent_time'] as int?;
      return Email(
        id: row['id'] as String,
        providerId: row['provider_id'] as String,
        folderId: row['folder_id'] as String,
        subject: row['subject'] as String,
        fromAddress: row['from_address'] as String,
        toAddress: row['to_address'] as String,
        ccAddress: row['cc_address'] as String?,
        summary: row['summary'] as String?,
        threadId: row['thread_id'] as String?,
        receivedTime:
            DateTime.fromMillisecondsSinceEpoch(row['received_time'] as int),
        sentTime: sentTimeMs != null
            ? DateTime.fromMillisecondsSinceEpoch(sentTimeMs)
            : null,
        isRead: (row['is_read'] as int) == 1,
        hasAttachment: (row['has_attachment'] as int) == 1,
      );
    }).toList();
  }

  /// Cache email content (full body)
  Future<void> cacheContent(String emailId, String content) async {
    if (_database == null || !_supportsLocalCache) return;

    await _database!.insert(
      'email_content',
      {
        'email_id': emailId,
        'content': content,
        'cached_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Get cached email content
  Future<String?> getCachedContent(String emailId) async {
    if (_database == null || !_supportsLocalCache) return null;

    final rows = await _database!.query(
      'email_content',
      where: 'email_id = ?',
      whereArgs: [emailId],
      limit: 1,
    );

    if (rows.isEmpty) return null;
    return rows.first['content'] as String;
  }

  /// Update email read status in cache
  Future<void> updateReadStatus(String emailId, bool isRead) async {
    if (_database == null || !_supportsLocalCache) return;

    await _database!.update(
      'emails',
      {'is_read': isRead ? 1 : 0},
      where: 'id = ?',
      whereArgs: [emailId],
    );
  }

  /// Clear all cached data (for logout)
  Future<void> clearCache() async {
    if (_database == null || !_supportsLocalCache) return;

    await _database!.delete('emails');
    await _database!.delete('email_content');
    debugPrint('📧 [EmailCache] Cache cleared');
  }

  /// Check if cache is stale (older than threshold)
  Future<bool> isCacheStale(
      {Duration threshold = const Duration(minutes: 30)}) async {
    if (_database == null || !_supportsLocalCache) return true;

    final rows = await _database!.query(
      'emails',
      columns: ['cached_at'],
      orderBy: 'cached_at DESC',
      limit: 1,
    );

    if (rows.isEmpty) return true;

    final lastCached =
        DateTime.fromMillisecondsSinceEpoch(rows.first['cached_at'] as int);
    return DateTime.now().difference(lastCached) > threshold;
  }
}
