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

  /// Whether a session transition can safely decide the fate of persisted
  /// mail data. Platforms without SQLite support have no local cache to leak;
  /// supported platforms require an open database before a user scope may be
  /// committed.
  bool get isAvailableForSessionIsolation =>
      !_supportsLocalCache || _database != null;

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
        version: 2,
        onCreate: (db, version) => _createSchema(db),
        onUpgrade: _upgradeSchema,
      );

      debugPrint('📧 [EmailCache] Database initialized');
    } catch (e) {
      _database = null;
      debugPrint('📧 [EmailCache] Local cache disabled: $e');
    } finally {
      _initialized = true;
    }
  }

  Future<void> _createSchema(Database db) async {
    await db.execute('''
      CREATE TABLE emails (
        id TEXT NOT NULL,
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
        cached_at INTEGER NOT NULL,
        PRIMARY KEY (provider_id, id)
      )
    ''');
    await db.execute('''
      CREATE TABLE email_content (
        provider_id TEXT NOT NULL,
        email_id TEXT NOT NULL,
        content TEXT NOT NULL,
        cached_at INTEGER NOT NULL,
        PRIMARY KEY (provider_id, email_id)
      )
    ''');
    await _createIndexes(db);
  }

  Future<void> _createIndexes(Database db) async {
    await db.execute(
      'CREATE INDEX idx_emails_provider ON emails(provider_id)',
    );
    await db.execute(
      'CREATE INDEX idx_emails_received ON emails(received_time DESC)',
    );
  }

  /// Version 1 keyed rows only by the provider message ID. Gmail and Zoho own
  /// independent ID namespaces, so one provider could replace the other's
  /// metadata/body or read flag. Version 2 makes the provider part of every
  /// persisted identity. Existing bodies are joined to the metadata row that
  /// owned the legacy ID; ambiguous legacy collisions were already impossible
  /// because the old primary key retained only one row.
  Future<void> _upgradeSchema(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    if (oldVersion >= 2) return;

    await db.execute('''
      CREATE TABLE emails_v2 (
        id TEXT NOT NULL,
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
        cached_at INTEGER NOT NULL,
        PRIMARY KEY (provider_id, id)
      )
    ''');
    await db.execute('''
      INSERT OR REPLACE INTO emails_v2 (
        id, provider_id, folder_id, subject, from_address, to_address,
        cc_address, summary, thread_id, received_time, sent_time, is_read,
        has_attachment, cached_at
      )
      SELECT
        id, provider_id, folder_id, subject, from_address, to_address,
        cc_address, summary, thread_id, received_time, sent_time, is_read,
        has_attachment, cached_at
      FROM emails
    ''');
    await db.execute('''
      CREATE TABLE email_content_v2 (
        provider_id TEXT NOT NULL,
        email_id TEXT NOT NULL,
        content TEXT NOT NULL,
        cached_at INTEGER NOT NULL,
        PRIMARY KEY (provider_id, email_id)
      )
    ''');
    await db.execute('''
      INSERT OR REPLACE INTO email_content_v2 (
        provider_id, email_id, content, cached_at
      )
      SELECT emails.provider_id, email_content.email_id,
             email_content.content, email_content.cached_at
      FROM email_content
      INNER JOIN emails ON emails.id = email_content.email_id
    ''');
    await db.execute('DROP TABLE email_content');
    await db.execute('DROP TABLE emails');
    await db.execute('ALTER TABLE emails_v2 RENAME TO emails');
    await db.execute(
      'ALTER TABLE email_content_v2 RENAME TO email_content',
    );
    await _createIndexes(db);
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
  Future<void> cacheContent(
    String providerId,
    String emailId,
    String content,
  ) async {
    if (_database == null || !_supportsLocalCache) return;

    await _database!.insert(
      'email_content',
      {
        'provider_id': providerId,
        'email_id': emailId,
        'content': content,
        'cached_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Get cached email content
  Future<String?> getCachedContent(String providerId, String emailId) async {
    if (_database == null || !_supportsLocalCache) return null;

    final rows = await _database!.query(
      'email_content',
      where: 'provider_id = ? AND email_id = ?',
      whereArgs: [providerId, emailId],
      limit: 1,
    );

    if (rows.isEmpty) return null;
    return rows.first['content'] as String;
  }

  /// Update email read status in cache
  Future<void> updateReadStatus(
    String providerId,
    String emailId,
    bool isRead,
  ) async {
    if (_database == null || !_supportsLocalCache) return;

    await _database!.update(
      'emails',
      {'is_read': isRead ? 1 : 0},
      where: 'provider_id = ? AND id = ?',
      whereArgs: [providerId, emailId],
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
