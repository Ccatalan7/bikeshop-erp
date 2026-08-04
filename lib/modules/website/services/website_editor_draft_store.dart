import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/website_block_document_sanitizer.dart';
import '../models/website_editor_capability.dart';
import '../models/website_responsive_authoring.dart';

const _websiteEditorDraftVersion = 1;
const _websiteEditorDraftPrefix = 'website_editor_draft_v1';

enum WebsiteEditorDraftReadDisposition {
  absent,
  restorable,
  staleBase,
  authorityMismatch,
  expired,
  invalid,
}

class WebsiteEditorDraftReadResult {
  const WebsiteEditorDraftReadResult._(
    this.disposition, {
    this.snapshot,
  });

  const WebsiteEditorDraftReadResult.absent()
      : this._(WebsiteEditorDraftReadDisposition.absent);

  final WebsiteEditorDraftReadDisposition disposition;
  final WebsiteEditorDraftSnapshot? snapshot;

  bool get canRestore =>
      disposition == WebsiteEditorDraftReadDisposition.restorable &&
      snapshot != null;
}

/// Typed local identity for one recoverable Website Builder page draft.
///
/// The storage key is opaque and includes the capability fingerprint, so a
/// second authenticated identity cannot overwrite or discover the first
/// identity's draft for the same tenant/page. The payload repeats every typed
/// authority field plus [authorityEpoch] and is revalidated when read; the key
/// is only an index, never the trust boundary.
class WebsiteEditorDraftIdentity {
  const WebsiteEditorDraftIdentity({
    required this.identity,
    required this.activeTenantId,
    required this.storefrontTenantId,
    required this.hasAuthority,
    required this.authorityEpoch,
    required this.pageKey,
  });

  factory WebsiteEditorDraftIdentity.forPage({
    required WebsiteEditorCapabilitySnapshot capability,
    String? pageId,
    String? pageSlug,
  }) {
    if (!capability.granted) {
      throw ArgumentError.value(
        capability,
        'capability',
        'A durable draft requires a granted editor capability.',
      );
    }
    final normalizedPageId = pageId?.trim() ?? '';
    final normalizedSlug = _normalizeSlug(pageSlug);
    final pageKey = normalizedPageId.isNotEmpty
        ? 'id:$normalizedPageId'
        : normalizedSlug.isEmpty
            ? 'home'
            : 'slug:$normalizedSlug';

    return WebsiteEditorDraftIdentity(
      identity: capability.identity,
      activeTenantId: capability.activeTenantId,
      storefrontTenantId: capability.storefrontTenantId,
      hasAuthority: capability.hasAuthority,
      authorityEpoch: capability.authorityEpoch,
      pageKey: pageKey,
    );
  }

  final String identity;
  final String activeTenantId;
  final String storefrontTenantId;
  final bool hasAuthority;
  final int authorityEpoch;
  final String pageKey;

  String get capabilityFingerprint =>
      '$identity|$activeTenantId|$storefrontTenantId|$hasAuthority';

  String get storageKey {
    final index = sha256
        .convert(
          utf8.encode(
            '$capabilityFingerprint|$storefrontTenantId|$pageKey',
          ),
        )
        .toString();
    return '$_websiteEditorDraftPrefix:$index';
  }

  bool matches(WebsiteEditorDraftIdentity other) =>
      identity == other.identity &&
      activeTenantId == other.activeTenantId &&
      storefrontTenantId == other.storefrontTenantId &&
      hasAuthority == other.hasAuthority &&
      authorityEpoch == other.authorityEpoch &&
      pageKey == other.pageKey;

  Map<String, dynamic> toJson() => {
        'identity': identity,
        'activeTenantId': activeTenantId,
        'storefrontTenantId': storefrontTenantId,
        'hasAuthority': hasAuthority,
        'authorityEpoch': authorityEpoch,
        'pageKey': pageKey,
      };

  static WebsiteEditorDraftIdentity fromJson(Map<String, dynamic> json) {
    final identity = json['identity'];
    final activeTenantId = json['activeTenantId'];
    final storefrontTenantId = json['storefrontTenantId'];
    final hasAuthority = json['hasAuthority'];
    final authorityEpoch = json['authorityEpoch'];
    final pageKey = json['pageKey'];
    if (identity is! String ||
        activeTenantId is! String ||
        storefrontTenantId is! String ||
        hasAuthority is! bool ||
        authorityEpoch is! int ||
        pageKey is! String ||
        identity.isEmpty ||
        storefrontTenantId.isEmpty ||
        pageKey.isEmpty) {
      throw const FormatException('Malformed Website editor draft identity.');
    }
    return WebsiteEditorDraftIdentity(
      identity: identity,
      activeTenantId: activeTenantId,
      storefrontTenantId: storefrontTenantId,
      hasAuthority: hasAuthority,
      authorityEpoch: authorityEpoch,
      pageKey: pageKey,
    );
  }
}

/// Sanitized, versioned page draft that can survive process suspension.
///
/// Only authored block content and minimal recovery context are durable. Open
/// sheets, focus nodes, hover, Canvas `activeElementId` and other transient UI
/// state are deliberately excluded. The current document baseline is stored as
/// a digest: a remote edit never receives a silent local overlay; callers get a
/// [WebsiteEditorDraftReadDisposition.staleBase] result and must offer an
/// explicit discard/reconciliation path instead.
class WebsiteEditorDraftSnapshot {
  const WebsiteEditorDraftSnapshot._({
    required this.identity,
    required this.updatedAt,
    required this.baseDocumentDigest,
    required this.blocks,
    required this.previewViewport,
    required this.writeScope,
    required this.selectedBlockId,
  });

  factory WebsiteEditorDraftSnapshot.capture({
    required WebsiteEditorDraftIdentity identity,
    required DateTime updatedAt,
    required Iterable<Map<String, dynamic>> baseBlocks,
    required Iterable<Map<String, dynamic>> draftBlocks,
    required WebsiteViewport previewViewport,
    required WebsiteWriteScope writeScope,
    String? selectedBlockId,
  }) {
    final sanitizedDraft = sanitizeWebsiteBlocksForPersistence(draftBlocks);
    final selected = selectedBlockId?.trim();
    final hasSelectedBlock = selected != null &&
        selected.isNotEmpty &&
        sanitizedDraft.any((block) => block['id']?.toString() == selected);
    final effectiveScope = previewViewport == WebsiteViewport.desktop
        ? WebsiteWriteScope.shared
        : writeScope;

    return WebsiteEditorDraftSnapshot._(
      identity: identity,
      updatedAt: updatedAt.toUtc(),
      baseDocumentDigest: digestBlocks(baseBlocks),
      blocks: sanitizedDraft,
      previewViewport: previewViewport,
      writeScope: effectiveScope,
      selectedBlockId: hasSelectedBlock ? selected : null,
    );
  }

  final WebsiteEditorDraftIdentity identity;
  final DateTime updatedAt;
  final String baseDocumentDigest;
  final List<Map<String, dynamic>> blocks;
  final WebsiteViewport previewViewport;
  final WebsiteWriteScope writeScope;
  final String? selectedBlockId;

  static String digestBlocks(Iterable<Map<String, dynamic>> blocks) {
    final sanitized = sanitizeWebsiteBlocksForPersistence(blocks);
    return sha256.convert(utf8.encode(_canonicalJson(sanitized))).toString();
  }

  Map<String, dynamic> _payloadJson() => {
        'blocks': blocks,
        'previewViewport': previewViewport.name,
        'writeScope': writeScope.name,
        'selectedBlockId': selectedBlockId,
      };

  String encode() {
    final payload = _payloadJson();
    return jsonEncode({
      'version': _websiteEditorDraftVersion,
      'identity': identity.toJson(),
      'updatedAt': updatedAt.toIso8601String(),
      'baseDocumentDigest': baseDocumentDigest,
      'payload': payload,
      'payloadDigest':
          sha256.convert(utf8.encode(_canonicalJson(payload))).toString(),
    });
  }

  static WebsiteEditorDraftSnapshot decode(String encoded) {
    final raw = jsonDecode(encoded);
    if (raw is! Map) {
      throw const FormatException('Website editor draft is not an object.');
    }
    final json = Map<String, dynamic>.from(raw);
    if (json['version'] != _websiteEditorDraftVersion) {
      throw const FormatException('Unsupported Website editor draft version.');
    }
    final rawIdentity = json['identity'];
    final rawPayload = json['payload'];
    final updatedAt = DateTime.tryParse(json['updatedAt']?.toString() ?? '');
    final baseDocumentDigest = json['baseDocumentDigest'];
    final payloadDigest = json['payloadDigest'];
    if (rawIdentity is! Map ||
        rawPayload is! Map ||
        updatedAt == null ||
        baseDocumentDigest is! String ||
        payloadDigest is! String) {
      throw const FormatException('Malformed Website editor draft envelope.');
    }

    final payload = Map<String, dynamic>.from(rawPayload);
    final actualDigest =
        sha256.convert(utf8.encode(_canonicalJson(payload))).toString();
    if (actualDigest != payloadDigest) {
      throw const FormatException('Website editor draft integrity mismatch.');
    }

    final rawBlocks = payload['blocks'];
    if (rawBlocks is! List) {
      throw const FormatException('Website editor draft blocks are malformed.');
    }
    final blocks = rawBlocks.map<Map<String, dynamic>>((rawBlock) {
      if (rawBlock is! Map) {
        throw const FormatException('Website editor draft block is malformed.');
      }
      return Map<String, dynamic>.from(rawBlock);
    }).toList(growable: false);
    final sanitized = sanitizeWebsiteBlocksForPersistence(blocks);
    if (_canonicalJson(sanitized) != _canonicalJson(blocks)) {
      throw const FormatException(
        'Website editor draft contains transient or non-canonical content.',
      );
    }

    final viewport = WebsiteViewport.values
        .where((value) => value.name == payload['previewViewport'])
        .firstOrNull;
    final requestedScope = WebsiteWriteScope.values
        .where((value) => value.name == payload['writeScope'])
        .firstOrNull;
    if (viewport == null || requestedScope == null) {
      throw const FormatException('Website editor draft context is malformed.');
    }
    final scope = viewport == WebsiteViewport.desktop
        ? WebsiteWriteScope.shared
        : requestedScope;
    final selectedCandidate = payload['selectedBlockId'];
    if (selectedCandidate != null && selectedCandidate is! String) {
      throw const FormatException(
        'Website editor draft selection is malformed.',
      );
    }
    final selected = selectedCandidate?.trim();
    final hasSelected = selected != null &&
        selected.isNotEmpty &&
        sanitized.any((block) => block['id']?.toString() == selected);

    return WebsiteEditorDraftSnapshot._(
      identity: WebsiteEditorDraftIdentity.fromJson(
        Map<String, dynamic>.from(rawIdentity),
      ),
      updatedAt: updatedAt.toUtc(),
      baseDocumentDigest: baseDocumentDigest,
      blocks: sanitized,
      previewViewport: viewport,
      writeScope: scope,
      selectedBlockId: hasSelected ? selected : null,
    );
  }
}

abstract interface class WebsiteEditorDraftStorage {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class SharedPreferencesWebsiteEditorDraftStorage
    implements WebsiteEditorDraftStorage {
  const SharedPreferencesWebsiteEditorDraftStorage();

  @override
  Future<String?> read(String key) async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getString(key);
  }

  @override
  Future<void> write(String key, String value) async {
    final preferences = await SharedPreferences.getInstance();
    final written = await preferences.setString(key, value);
    if (!written) {
      throw StateError('No se pudo guardar el borrador local del sitio.');
    }
  }

  @override
  Future<void> delete(String key) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(key);
  }
}

class WebsiteEditorDraftStore {
  WebsiteEditorDraftStore({
    WebsiteEditorDraftStorage storage =
        const SharedPreferencesWebsiteEditorDraftStorage(),
    this.retention = const Duration(days: 7),
    DateTime Function()? clock,
  })  : _storage = storage,
        _clock = clock ?? DateTime.now;

  final WebsiteEditorDraftStorage _storage;
  final Duration retention;
  final DateTime Function() _clock;

  Future<void> save(WebsiteEditorDraftSnapshot snapshot) => _storage.write(
        snapshot.identity.storageKey,
        snapshot.encode(),
      );

  Future<WebsiteEditorDraftReadResult> read({
    required WebsiteEditorDraftIdentity identity,
    required Iterable<Map<String, dynamic>> currentBaseBlocks,
  }) async {
    final encoded = await _storage.read(identity.storageKey);
    if (encoded == null || encoded.isEmpty) {
      return const WebsiteEditorDraftReadResult.absent();
    }

    late final WebsiteEditorDraftSnapshot snapshot;
    try {
      snapshot = WebsiteEditorDraftSnapshot.decode(encoded);
    } on Object {
      await _storage.delete(identity.storageKey);
      return const WebsiteEditorDraftReadResult._(
        WebsiteEditorDraftReadDisposition.invalid,
      );
    }

    if (!snapshot.identity.matches(identity)) {
      return WebsiteEditorDraftReadResult._(
        WebsiteEditorDraftReadDisposition.authorityMismatch,
        snapshot: snapshot,
      );
    }
    if (_clock().toUtc().difference(snapshot.updatedAt) > retention) {
      await _storage.delete(identity.storageKey);
      return WebsiteEditorDraftReadResult._(
        WebsiteEditorDraftReadDisposition.expired,
        snapshot: snapshot,
      );
    }

    final currentDigest =
        WebsiteEditorDraftSnapshot.digestBlocks(currentBaseBlocks);
    if (currentDigest != snapshot.baseDocumentDigest) {
      return WebsiteEditorDraftReadResult._(
        WebsiteEditorDraftReadDisposition.staleBase,
        snapshot: snapshot,
      );
    }
    return WebsiteEditorDraftReadResult._(
      WebsiteEditorDraftReadDisposition.restorable,
      snapshot: snapshot,
    );
  }

  Future<void> discard(WebsiteEditorDraftIdentity identity) =>
      _storage.delete(identity.storageKey);
}

String _canonicalJson(dynamic value) => jsonEncode(_canonicalize(value));

dynamic _canonicalize(dynamic value) {
  if (value == null || value is bool || value is num || value is String) {
    return value;
  }
  if (value is DateTime) return value.toUtc().toIso8601String();
  if (value is Map) {
    final keys = value.keys.map((key) => key.toString()).toList()..sort();
    return <String, dynamic>{
      for (final key in keys) key: _canonicalize(value[key]),
    };
  }
  if (value is Iterable) {
    return value.map(_canonicalize).toList(growable: false);
  }
  throw FormatException(
    'Unsupported Website editor draft value: ${value.runtimeType}.',
  );
}

String _normalizeSlug(String? value) {
  var normalized = value?.trim().toLowerCase() ?? '';
  while (normalized.startsWith('/')) {
    normalized = normalized.substring(1);
  }
  while (normalized.endsWith('/')) {
    normalized = normalized.substring(0, normalized.length - 1);
  }
  return normalized == 'home' || normalized == 'inicio' ? '' : normalized;
}

extension<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
