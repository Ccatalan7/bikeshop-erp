import 'dart:typed_data';
import 'dart:async';

import 'package:mime/mime.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../../shared/services/tenant_service.dart';
import '../models/app_stored_file.dart';

class AppFileStorageService {
  AppFileStorageService._();

  static final AppFileStorageService instance = AppFileStorageService._();

  static const String bucketName = 'vinabike-files';

  final SupabaseClient _supabase = Supabase.instance.client;
  final Uuid _uuid = const Uuid();
  final StreamController<AppStoredFile> _savedFileController =
      StreamController<AppStoredFile>.broadcast();
  List<_SupplierUrlCandidate>? _supplierUrlCandidates;
  DateTime? _supplierUrlCandidatesLoadedAt;
  static const Duration _supplierUrlCacheMaxAge = Duration(minutes: 5);

  Stream<AppStoredFile> get savedFiles => _savedFileController.stream;

  Future<List<AppStoredFile>> listFiles({
    String? query,
    String? sourceType,
    int limit = 120,
  }) async {
    final tenantId = await _requireTenantId();

    var request = _supabase
        .from('app_files')
        .select()
        .eq('tenant_id', tenantId)
        .isFilter('deleted_at', null);

    final trimmedQuery = query?.trim();
    if (trimmedQuery != null && trimmedQuery.isNotEmpty) {
      final safeQuery = trimmedQuery.replaceAll(',', ' ').replaceAll('%', '');
      request = request.or(
        'file_name.ilike.%$safeQuery%,'
        'context_title.ilike.%$safeQuery%,'
        'context_subtitle.ilike.%$safeQuery%,'
        'source_provider.ilike.%$safeQuery%',
      );
    }

    if (sourceType != null && sourceType != 'all') {
      if (sourceType == 'email' ||
          sourceType == 'chat' ||
          sourceType == 'expense') {
        request = request.ilike('source_type', '$sourceType%');
      } else {
        request = request.eq('source_type', sourceType);
      }
    }

    final rows =
        await request.order('created_at', ascending: false).limit(limit);
    return (rows as List<dynamic>)
        .map((row) => AppStoredFile.fromJson(row as Map<String, dynamic>))
        .toList(growable: false);
  }

  Future<AppStoredFile?> getFileById(String fileId) async {
    final tenantId = await _requireTenantId();
    final normalizedFileId = fileId.trim();
    if (normalizedFileId.isEmpty) return null;

    final row = await _supabase
        .from('app_files')
        .select()
        .eq('tenant_id', tenantId)
        .eq('id', normalizedFileId)
        .isFilter('deleted_at', null)
        .maybeSingle();
    return row == null ? null : AppStoredFile.fromJson(row);
  }

  Future<AppStoredFile> saveFile({
    required Uint8List bytes,
    required String fileName,
    String? mimeType,
    AppFileContext context = const AppFileContext(),
  }) async {
    final tenantId = await _requireTenantId();
    final safeName = _safeFileName(fileName);
    final resolvedMime = mimeType?.trim().isNotEmpty == true
        ? mimeType!.trim()
        : lookupMimeType(safeName, headerBytes: bytes) ??
            'application/octet-stream';
    final now = DateTime.now().toUtc();
    final objectId = _uuid.v4();
    final storagePath =
        '$tenantId/${now.year}/${_twoDigits(now.month)}/$objectId-$safeName';

    await _supabase.storage.from(bucketName).uploadBinary(
          storagePath,
          bytes,
          fileOptions: FileOptions(
            contentType: resolvedMime,
            upsert: false,
          ),
        );

    try {
      final row = await _supabase
          .from('app_files')
          .insert({
            'tenant_id': tenantId,
            'file_name': safeName,
            'storage_bucket': bucketName,
            'storage_path': storagePath,
            'mime_type': resolvedMime,
            'size_bytes': bytes.length,
            'source_type': context.sourceType,
            'source_id': context.sourceId,
            'source_provider': context.sourceProvider,
            'source_route': context.sourceRoute,
            'context_type': context.contextType,
            'context_id': context.contextId,
            'context_title': context.contextTitle,
            'context_subtitle': context.contextSubtitle,
            'tags': context.tags,
            'metadata': context.metadata,
          })
          .select()
          .single();

      final savedFile = AppStoredFile.fromJson(row);
      _savedFileController.add(savedFile);
      return savedFile;
    } catch (_) {
      await _supabase.storage.from(bucketName).remove([storagePath]);
      rethrow;
    }
  }

  Future<AppStoredFile> replaceFileBytes({
    required AppStoredFile file,
    required Uint8List bytes,
    String? mimeType,
    List<String> addTags = const [],
    Map<String, dynamic> metadataPatch = const {},
  }) async {
    final tenantId = await _requireTenantId();
    if (file.tenantId != tenantId) {
      throw StateError('El archivo pertenece a otro tenant.');
    }

    final resolvedMime = mimeType?.trim().isNotEmpty == true
        ? mimeType!.trim()
        : lookupMimeType(file.fileName, headerBytes: bytes) ?? file.mimeType;

    await _supabase.storage.from(file.storageBucket).uploadBinary(
          file.storagePath,
          bytes,
          fileOptions: FileOptions(
            contentType: resolvedMime,
            upsert: true,
          ),
        );

    final tags = <String>{
      ...file.tags,
      ...addTags,
    }.toList(growable: false);
    final metadata = Map<String, dynamic>.from(file.metadata)
      ..addAll(metadataPatch);

    final row = await _supabase
        .from('app_files')
        .update({
          'mime_type': resolvedMime,
          'size_bytes': bytes.length,
          'tags': tags,
          'metadata': metadata,
        })
        .eq('tenant_id', tenantId)
        .eq('id', file.id)
        .select()
        .single();

    final updatedFile = AppStoredFile.fromJson(row);
    _savedFileController.add(updatedFile);
    return updatedFile;
  }

  Future<AppFileSupplierMatch?> matchSupplierForUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
      return null;
    }

    final candidates = await _loadSupplierUrlCandidates();
    _SupplierUrlCandidate? best;
    for (final candidate in candidates) {
      if (!candidate.matches(uri)) continue;
      if (best == null || candidate.score > best.score) {
        best = candidate;
      }
    }

    final match = best;
    if (match == null) return null;
    return AppFileSupplierMatch(
      id: match.id,
      name: match.name,
      website: match.website,
    );
  }

  Future<AppStoredFile> attachSupplierContext({
    required AppStoredFile file,
    required AppFileSupplierMatch supplier,
  }) async {
    final metadata = Map<String, dynamic>.from(file.metadata)
      ..addAll({
        'supplier_id': supplier.id,
        'supplier_name': supplier.name,
        'supplier_website': supplier.website,
        'smart_folder': 'supplier:${supplier.id}',
      });
    final tags = <String>{
      ...file.tags,
      'proveedor',
    }.toList(growable: false);

    final row = await _supabase
        .from('app_files')
        .update({
          'source_id': supplier.id,
          'context_type': 'supplier',
          'context_id': supplier.id,
          'context_title': supplier.name,
          'context_subtitle': 'Portal proveedor',
          'tags': tags,
          'metadata': metadata,
        })
        .eq('id', file.id)
        .select()
        .single();

    return AppStoredFile.fromJson(row);
  }

  Future<Uint8List> downloadFile(AppStoredFile file) {
    return _supabase.storage
        .from(file.storageBucket)
        .download(file.storagePath);
  }

  Future<void> deleteFile(AppStoredFile file) async {
    await _supabase
        .from('app_files')
        .update({'deleted_at': DateTime.now().toUtc().toIso8601String()}).eq(
            'id', file.id);

    try {
      await _supabase.storage
          .from(file.storageBucket)
          .remove([file.storagePath]);
    } catch (_) {
      // The metadata is already hidden. A storage cleanup retry can happen later.
    }
  }

  Future<List<_SupplierUrlCandidate>> _loadSupplierUrlCandidates() async {
    final now = DateTime.now();
    final cached = _supplierUrlCandidates;
    if (cached != null &&
        _supplierUrlCandidatesLoadedAt != null &&
        now.difference(_supplierUrlCandidatesLoadedAt!) <
            _supplierUrlCacheMaxAge) {
      return cached;
    }

    final tenantId = await _requireTenantId();
    final rows = await _supabase
        .from('suppliers')
        .select('id, name, website, is_active')
        .eq('tenant_id', tenantId);

    final candidates = <_SupplierUrlCandidate>[];
    for (final row in rows as List<dynamic>) {
      final map = row as Map<String, dynamic>;
      if (map['is_active'] == false) continue;
      final id = map['id']?.toString();
      final name = map['name']?.toString();
      final website = map['website']?.toString();
      if (id == null ||
          id.trim().isEmpty ||
          name == null ||
          name.trim().isEmpty ||
          website == null ||
          website.trim().isEmpty) {
        continue;
      }

      final candidate = _SupplierUrlCandidate.tryCreate(
        id: id,
        name: name,
        website: website,
      );
      if (candidate != null) candidates.add(candidate);
    }

    candidates.sort((a, b) => b.score.compareTo(a.score));
    _supplierUrlCandidates = candidates;
    _supplierUrlCandidatesLoadedAt = now;
    return candidates;
  }

  Future<String> _requireTenantId() async {
    final tenantId =
        TenantService().currentTenantId ?? await TenantService().getTenantId();
    if (tenantId == null || tenantId.isEmpty) {
      throw StateError('No se encontro el tenant activo.');
    }
    return tenantId;
  }

  String _safeFileName(String value) {
    final cleaned = value
        .trim()
        .split(RegExp(r'[\\/]'))
        .last
        .replaceAll(RegExp(r'[^A-Za-z0-9._ -]+'), '_')
        .replaceAll(RegExp(r'_+'), '_');
    return cleaned.isEmpty ? 'archivo' : cleaned;
  }

  String _twoDigits(int value) => value.toString().padLeft(2, '0');
}

class AppFileSupplierMatch {
  final String id;
  final String name;
  final String website;

  const AppFileSupplierMatch({
    required this.id,
    required this.name,
    required this.website,
  });
}

class _SupplierUrlCandidate {
  final String id;
  final String name;
  final String website;
  final String host;
  final String pathPrefix;
  final int score;

  const _SupplierUrlCandidate({
    required this.id,
    required this.name,
    required this.website,
    required this.host,
    required this.pathPrefix,
    required this.score,
  });

  static _SupplierUrlCandidate? tryCreate({
    required String id,
    required String name,
    required String website,
  }) {
    final uri = _normalizeWebsite(website);
    if (uri == null || uri.host.isEmpty) return null;
    final host = _normalizeHost(uri.host);
    if (host.isEmpty) return null;
    final pathPrefix = _normalizePathPrefix(uri.path);
    return _SupplierUrlCandidate(
      id: id,
      name: name.trim(),
      website: website.trim(),
      host: host,
      pathPrefix: pathPrefix,
      score: host.length + pathPrefix.length,
    );
  }

  bool matches(Uri target) {
    final targetHost = _normalizeHost(target.host);
    if (targetHost != host && !targetHost.endsWith('.$host')) {
      return false;
    }
    if (pathPrefix.isEmpty) return true;
    final targetPath = _normalizePathPrefix(target.path);
    return targetPath == pathPrefix || targetPath.startsWith('$pathPrefix/');
  }

  static Uri? _normalizeWebsite(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;
    final withScheme = trimmed.contains('://') ? trimmed : 'https://$trimmed';
    return Uri.tryParse(withScheme);
  }

  static String _normalizeHost(String value) {
    final lower = value.trim().toLowerCase();
    return lower.startsWith('www.') ? lower.substring(4) : lower;
  }

  static String _normalizePathPrefix(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty || trimmed == '/') return '';
    return trimmed.replaceAll(RegExp(r'/+$'), '');
  }
}
