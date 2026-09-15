import 'dart:async';
import 'dart:typed_data';

import 'package:file/file.dart' as fs;
import 'package:file/local.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:path_provider/path_provider.dart';

import '../models/message.dart';
import 'messaging_attachment_service.dart';

/// Durable local copy of every chat attachment the operator has seen or sent.
///
/// WhatsApp keeps a photo on the phone once it has been opened; opening the
/// chat a week later shows it at once. The ERP used to key its image cache
/// on the five-minute signed URL, so every reopen after that window — and
/// every app launch — downloaded the same bytes again, and a photo the
/// operator had just sent was downloaded back to draw its own bubble.
///
/// Here the key is the attachment's durable identity (the private storage
/// path, the registry id, or the WhatsApp media id), never the URL. Bytes are
/// written to the application support directory — the temp directory the
/// default cache uses is purged by the OS — and kept for months. Sent files
/// enter the cache from the bytes already in memory, before the upload.
class ChatMediaCache {
  ChatMediaCache._();

  static final ChatMediaCache instance = ChatMediaCache._();

  static const String _cacheKey = 'vinabike-chat-media';
  static const Duration _stalePeriod = Duration(days: 180);
  static const int _maxObjects = 4000;

  /// Same object for the same key across builds, so Flutter's image cache
  /// (keyed by provider equality) keeps the decoded picture too.
  final Map<String, Uint8List> _bytesByKey = <String, Uint8List>{};
  final List<String> _bytesOrder = <String>[];
  static const int _memoryEntries = 96;

  final Map<String, Future<Uint8List?>> _inflight =
      <String, Future<Uint8List?>>{};

  CacheManager? _manager;
  Future<CacheManager>? _managerFuture;

  Future<CacheManager> _cacheManager() {
    final existing = _manager;
    if (existing != null) return Future.value(existing);
    return _managerFuture ??= () async {
      // On the web the package picks its in-memory file system itself.
      final config = kIsWeb
          ? Config(
              _cacheKey,
              stalePeriod: _stalePeriod,
              maxNrOfCacheObjects: _maxObjects,
            )
          : Config(
              _cacheKey,
              stalePeriod: _stalePeriod,
              maxNrOfCacheObjects: _maxObjects,
              fileSystem: _SupportDirectoryFileSystem(_cacheKey),
            );
      final manager = CacheManager(config);
      _manager = manager;
      return manager;
    }();
  }

  /// Durable identity of the media behind [message], or `null` when the
  /// message carries none (an external link, plain text).
  static String? keyFor(Message message) {
    final metadata = message.metadata;
    final local = _text(metadata['local_media_key']);
    final path = MessagingAttachmentService.storagePath(message);
    if (path != null) return 'path:$path';
    final attachmentId = MessagingAttachmentService.attachmentId(message);
    if (attachmentId != null) return 'attachment:$attachmentId';
    for (final field in const ['whatsapp_media_id', 'media_id']) {
      final value = _text(metadata[field]);
      if (value != null) return 'wa:$value';
    }
    if (local != null) return 'local:$local';
    return null;
  }

  /// Key of the bytes that were on this device before the server knew the
  /// file: the composer's own copy. Read after [keyFor] misses.
  static String? localKeyFor(Message message) {
    final local = _text(message.metadata['local_media_key']);
    return local == null ? null : 'local:$local';
  }

  static String? _text(Object? value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }

  /// Bytes already in memory, without touching the disk.
  Uint8List? peek(String key) => _bytesByKey[key];

  /// Bytes for [key] if they are in memory or on disk; never downloads.
  Future<Uint8List?> read(String key) async {
    final inMemory = _bytesByKey[key];
    if (inMemory != null) return inMemory;
    try {
      final manager = await _cacheManager();
      final info = await manager.getFileFromCache(key);
      if (info == null) return null;
      final bytes = await info.file.readAsBytes();
      _remember(key, bytes);
      return bytes;
    } catch (error) {
      debugPrint('ChatMediaCache: no se pudo leer $key: $error');
      return null;
    }
  }

  /// Bytes for [key], downloading through [resolveUrl] only when neither
  /// memory nor disk has them. Concurrent callers share one download.
  Future<Uint8List?> fetch(
    String key, {
    required Future<String?> Function() resolveUrl,
    String? fileExtension,
  }) {
    final inMemory = _bytesByKey[key];
    if (inMemory != null) return Future.value(inMemory);
    return _inflight.putIfAbsent(key, () async {
      try {
        final cached = await read(key);
        if (cached != null) return cached;
        final url = await resolveUrl();
        if (url == null || url.isEmpty) return null;
        final manager = await _cacheManager();
        debugPrint('ChatMediaCache: descargando $key (no estaba en el equipo)');
        final file = await manager.getSingleFile(url, key: key);
        final bytes = await file.readAsBytes();
        _remember(key, bytes);
        return bytes;
      } catch (error) {
        debugPrint('ChatMediaCache: no se pudo traer $key: $error');
        return null;
      } finally {
        _inflight.remove(key);
      }
    });
  }

  /// Path of the cached file for [key] on this device, for players that
  /// read from disk. `null` on the web and when the file is not here.
  Future<String?> filePath(String key) async {
    if (kIsWeb) return null;
    try {
      final manager = await _cacheManager();
      final info = await manager.getFileFromCache(key);
      return info?.file.path;
    } catch (_) {
      return null;
    }
  }

  /// Stores bytes the app already holds — a file the operator just chose —
  /// so its own bubble and every later open come from here.
  Future<void> put(
    String key,
    Uint8List bytes, {
    String? fileExtension,
  }) async {
    _remember(key, bytes);
    try {
      final manager = await _cacheManager();
      await manager.putFile(
        key,
        bytes,
        key: key,
        fileExtension: _normalizedExtension(fileExtension),
        maxAge: _stalePeriod,
      );
    } catch (error) {
      debugPrint('ChatMediaCache: no se pudo guardar $key: $error');
    }
  }

  /// The composer's copy becomes the server's copy: same bytes, new identity.
  Future<void> alias(String fromKey, String toKey) async {
    if (fromKey == toKey) return;
    final bytes = _bytesByKey[fromKey] ?? await read(fromKey);
    if (bytes == null) return;
    await put(toKey, bytes);
  }

  void forget(String key) {
    _bytesByKey.remove(key);
    _bytesOrder.remove(key);
  }

  static String _normalizedExtension(String? extension) {
    final value = extension?.trim().toLowerCase().replaceAll('.', '') ?? '';
    return value.isEmpty ? 'bin' : value;
  }

  void _remember(String key, Uint8List bytes) {
    if (!_bytesByKey.containsKey(key)) {
      _bytesOrder.add(key);
    }
    _bytesByKey[key] = bytes;
    while (_bytesOrder.length > _memoryEntries) {
      final evicted = _bytesOrder.removeAt(0);
      _bytesByKey.remove(evicted);
    }
  }

  /// Image provider that stays equal across rebuilds for the same key, so
  /// the decoded picture survives in Flutter's image cache.
  ImageProvider providerFor(String key, Uint8List bytes) =>
      _KeyedMemoryImage(key, bytes);
}

class _KeyedMemoryImage extends MemoryImage {
  const _KeyedMemoryImage(this.cacheKey, super.bytes);

  final String cacheKey;

  @override
  bool operator ==(Object other) =>
      other is _KeyedMemoryImage &&
      other.cacheKey == cacheKey &&
      other.scale == scale;

  @override
  int get hashCode => Object.hash(cacheKey, scale);
}

/// Cache files under the application support directory instead of the
/// temporary one: macOS purges temp, and a purged cache is exactly the
/// "load it again" the operator complained about.
class _SupportDirectoryFileSystem implements FileSystem {
  _SupportDirectoryFileSystem(this.cacheKey);

  final String cacheKey;
  Future<fs.Directory>? _directory;

  Future<fs.Directory> _root() {
    return _directory ??= () async {
      final base = await getApplicationSupportDirectory();
      const fileSystem = LocalFileSystem();
      final directory =
          fileSystem.directory(base.path).childDirectory(cacheKey);
      await directory.create(recursive: true);
      return directory;
    }();
  }

  @override
  Future<fs.File> createFile(String name) async {
    final directory = await _root();
    return directory.childFile(name);
  }
}
