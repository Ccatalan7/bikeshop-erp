import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:mime/mime.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../../shared/services/tenant_service.dart';
import '../models/app_stored_file.dart';

class PayrollAdvanceReceiptValidation {
  const PayrollAdvanceReceiptValidation({
    required this.fileName,
    required this.mimeType,
  });

  final String fileName;
  final String mimeType;
}

/// Client-side mirror of the versioned SQL receipt policy.
///
/// SQL remains authoritative for persisted Storage/app_files rows. This mirror
/// rejects malformed bytes before any upload or financial write can happen.
class PayrollAdvanceReceiptPolicyV1 {
  const PayrollAdvanceReceiptPolicyV1._();

  static const int maxSizeBytes = 12582912;
  static const List<String> allowedMimeTypes = <String>[
    'application/pdf',
    'image/jpeg',
    'image/png',
    'image/webp',
  ];

  static PayrollAdvanceReceiptValidation validate({
    required Uint8List bytes,
    required String fileName,
    String? mimeType,
  }) {
    final cleanFileName = fileName.trim();
    if (bytes.isEmpty) {
      throw ArgumentError('El comprobante está vacío.');
    }
    if (bytes.length > maxSizeBytes) {
      throw ArgumentError('El comprobante supera el máximo de 12 MiB.');
    }
    if (cleanFileName.isEmpty) {
      throw ArgumentError('El comprobante necesita un nombre de archivo.');
    }

    final signatureMime = _mimeFromSignature(bytes);
    final extensionMime = _mimeFromFileName(cleanFileName);
    final declaredMime = normalizeMimeType(mimeType);
    if (signatureMime == null ||
        extensionMime == null ||
        signatureMime != extensionMime ||
        (declaredMime.isNotEmpty && declaredMime != signatureMime)) {
      throw ArgumentError(
        'El comprobante debe ser PDF, JPG, PNG o WEBP y su contenido, '
        'extensión y tipo deben coincidir.',
      );
    }

    return PayrollAdvanceReceiptValidation(
      fileName: cleanFileName,
      mimeType: signatureMime,
    );
  }

  static String normalizeMimeType(String? value) =>
      (value ?? '').split(';').first.trim().toLowerCase();

  static String? _mimeFromFileName(String fileName) {
    final separator = fileName.lastIndexOf('.');
    if (separator < 0 || separator == fileName.length - 1) return null;
    switch (fileName.substring(separator + 1).toLowerCase()) {
      case 'pdf':
        return 'application/pdf';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
    }
    return null;
  }

  static String? _mimeFromSignature(Uint8List bytes) {
    if (bytes.length >= 5 &&
        bytes[0] == 0x25 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x44 &&
        bytes[3] == 0x46 &&
        bytes[4] == 0x2D) {
      return 'application/pdf';
    }
    if (bytes.length >= 3 &&
        bytes[0] == 0xFF &&
        bytes[1] == 0xD8 &&
        bytes[2] == 0xFF) {
      return 'image/jpeg';
    }
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47 &&
        bytes[4] == 0x0D &&
        bytes[5] == 0x0A &&
        bytes[6] == 0x1A &&
        bytes[7] == 0x0A) {
      return 'image/png';
    }
    if (bytes.length >= 12 &&
        bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50) {
      return 'image/webp';
    }
    return null;
  }
}

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
  static const int _historicalFilePageSize = 500;

  Stream<AppStoredFile> get savedFiles => _savedFileController.stream;

  /// Payroll advance receipts are write-once from the moment their metadata
  /// row exists, not only after the money command links them. The path check
  /// mirrors the restrictive Storage policies and protects callers that hold
  /// a stale or partially populated [AppStoredFile].
  static bool isImmutablePayrollAdvanceEvidence(AppStoredFile file) {
    final segments = file.storagePath.split('/');
    final usesEvidenceNamespace = file.storageBucket == bucketName &&
        segments.length >= 4 &&
        segments[1] == 'evidence' &&
        segments[2] == 'payroll_advance';
    return usesEvidenceNamespace ||
        (file.sourceType == 'payroll_advance' &&
            file.contextType == 'payroll_advance_operation');
  }

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

  /// Lists every active file created within [startsAt, endsAt).
  ///
  /// The boundaries are normalized to UTC and every page remains explicitly
  /// tenant-scoped. This does not alter the existing latest-files behavior in
  /// [listFiles].
  Future<List<AppStoredFile>> listFilesForRange({
    required DateTime startsAt,
    required DateTime endsAt,
  }) async {
    final startUtc = startsAt.toUtc();
    final endUtc = endsAt.toUtc();
    if (!endUtc.isAfter(startUtc)) {
      throw ArgumentError.value(
        endsAt,
        'endsAt',
        'Must be after startsAt.',
      );
    }

    final tenantId = await _requireTenantId();
    final files = <AppStoredFile>[];
    var offset = 0;

    while (true) {
      final rows = await _supabase
          .from('app_files')
          .select()
          .eq('tenant_id', tenantId)
          .isFilter('deleted_at', null)
          .gte('created_at', startUtc.toIso8601String())
          .lt('created_at', endUtc.toIso8601String())
          .order('created_at', ascending: false)
          .order('id', ascending: false)
          .range(offset, offset + _historicalFilePageSize - 1);
      final page = (rows as List<dynamic>)
          .map(
            (row) => AppStoredFile.fromJson(row as Map<String, dynamic>),
          )
          .toList(growable: false);
      files.addAll(page);
      if (page.length < _historicalFilePageSize) break;
      offset += _historicalFilePageSize;
    }

    return files;
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

  /// Persists immutable evidence without destructive compensation.
  ///
  /// The storage path is deterministic for `operationKey + sha256Hex`, so a
  /// lost response can be recovered by read-back. Unlike [saveFile], this
  /// method never deletes the blob after an ambiguous metadata result: a
  /// retry either returns the exact existing evidence or fails loudly while
  /// preserving the bytes for deliberate recovery.
  Future<AppStoredFile> saveImmutableEvidenceFile({
    required Uint8List bytes,
    required String fileName,
    String? mimeType,
    required AppFileContext context,
    required String operationKey,
    required String sha256Hex,
  }) async {
    final receipt = PayrollAdvanceReceiptPolicyV1.validate(
      bytes: bytes,
      fileName: fileName,
      mimeType: mimeType,
    );
    final tenantId = await _requireTenantId();
    final safeName = _safeFileName(receipt.fileName);
    final digest = sha256Hex.trim().toLowerCase();
    final cleanOperationKey = operationKey.trim();
    final contextType = context.contextType?.trim();
    final contextId = context.contextId?.trim();
    final resolvedMime = receipt.mimeType;
    if (bytes.isEmpty ||
        operationKey != cleanOperationKey ||
        !RegExp(r'^[A-Za-z0-9:_-]{8,200}$').hasMatch(cleanOperationKey) ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(digest) ||
        sha256.convert(bytes).toString() != digest ||
        context.sourceType.trim().isEmpty ||
        context.sourceId != cleanOperationKey ||
        contextType == null ||
        contextType.isEmpty ||
        contextId != cleanOperationKey ||
        context.metadata['sha256']?.toString().toLowerCase() != digest ||
        context.metadata['operation_key']?.toString() != cleanOperationKey) {
      throw ArgumentError('Invalid immutable evidence identity');
    }

    final existing = await _findImmutableEvidenceRows(
      tenantId: tenantId,
      sourceType: context.sourceType,
      contextType: contextType,
      contextId: cleanOperationKey,
    );
    if (existing.length > 1) {
      throw StateError('Multiple immutable evidence rows share one operation.');
    }
    if (existing.length == 1) {
      return _verifyImmutableEvidence(
        existing.single,
        expectedTenantId: tenantId,
        expectedBytes: bytes,
        expectedFileName: safeName,
        expectedMimeType: resolvedMime,
        expectedSha256: digest,
        expectedOperationKey: cleanOperationKey,
        expectedContext: context,
      );
    }

    final sourceSegment =
        context.sourceType.trim().replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_');
    final operationHash = sha256
        .convert(utf8.encode('$tenantId:$cleanOperationKey'))
        .toString()
        .substring(0, 32);
    final storagePath =
        '$tenantId/evidence/$sourceSegment/$operationHash/$digest-$safeName';

    try {
      await _supabase.storage.from(bucketName).uploadBinary(
            storagePath,
            bytes,
            fileOptions: FileOptions(
              contentType: resolvedMime,
              upsert: false,
            ),
          );
    } catch (error, stackTrace) {
      try {
        final storedBytes =
            await _supabase.storage.from(bucketName).download(storagePath);
        if (sha256.convert(storedBytes).toString() != digest) {
          Error.throwWithStackTrace(error, stackTrace);
        }
      } catch (_) {
        Error.throwWithStackTrace(error, stackTrace);
      }
    }

    Map<String, dynamic> row;
    try {
      final inserted = await _supabase
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
      row = Map<String, dynamic>.from(inserted);
    } catch (error, stackTrace) {
      try {
        final recovered = await _findImmutableEvidenceRows(
          tenantId: tenantId,
          sourceType: context.sourceType,
          contextType: contextType,
          contextId: cleanOperationKey,
        );
        if (recovered.length == 1) {
          return _verifyImmutableEvidence(
            recovered.single,
            expectedTenantId: tenantId,
            expectedBytes: bytes,
            expectedFileName: safeName,
            expectedMimeType: resolvedMime,
            expectedSha256: digest,
            expectedOperationKey: cleanOperationKey,
            expectedContext: context,
          );
        }
      } catch (_) {
        // Preserve the original ambiguous result and, crucially, the blob.
      }
      Error.throwWithStackTrace(error, stackTrace);
    }

    final saved = await _verifyImmutableEvidence(
      row,
      expectedTenantId: tenantId,
      expectedBytes: bytes,
      expectedFileName: safeName,
      expectedMimeType: resolvedMime,
      expectedSha256: digest,
      expectedOperationKey: cleanOperationKey,
      expectedContext: context,
    );
    _savedFileController.add(saved);
    return saved;
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
    if (isImmutablePayrollAdvanceEvidence(file)) {
      throw StateError(
        'El comprobante original de un anticipo no se puede reemplazar.',
      );
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
    if (isImmutablePayrollAdvanceEvidence(file)) {
      throw StateError(
        'El comprobante original de un anticipo no se puede eliminar.',
      );
    }
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

  Future<List<Map<String, dynamic>>> _findImmutableEvidenceRows({
    required String tenantId,
    required String sourceType,
    required String contextType,
    required String contextId,
  }) async {
    final rows = await _supabase
        .from('app_files')
        .select()
        .eq('tenant_id', tenantId)
        .eq('source_type', sourceType)
        .eq('context_type', contextType)
        .eq('context_id', contextId)
        .isFilter('deleted_at', null)
        .limit(2);
    return (rows as List<dynamic>)
        .map(
          (row) => Map<String, dynamic>.from(
            row as Map<dynamic, dynamic>,
          ),
        )
        .toList(growable: false);
  }

  Future<AppStoredFile> _verifyImmutableEvidence(
    Map<String, dynamic> row, {
    required String expectedTenantId,
    required Uint8List expectedBytes,
    required String expectedFileName,
    required String expectedMimeType,
    required String expectedSha256,
    required String expectedOperationKey,
    required AppFileContext expectedContext,
  }) async {
    final file = AppStoredFile.fromJson(row);
    final expectedMetadataMatches = expectedContext.metadata.entries.every(
      (entry) => file.metadata[entry.key]?.toString() == entry.value.toString(),
    );
    final expectedTags = expectedContext.tags.toSet();
    final actualTags = file.tags.toSet();
    final recordMatches = file.id.trim().isNotEmpty &&
        file.tenantId == expectedTenantId &&
        file.uploadedBy?.trim().isNotEmpty == true &&
        file.fileName == expectedFileName &&
        file.storageBucket == bucketName &&
        file.storagePath.trim().isNotEmpty &&
        file.mimeType == expectedMimeType &&
        file.sizeBytes == expectedBytes.length &&
        file.sourceType == expectedContext.sourceType &&
        file.sourceId == expectedContext.sourceId &&
        file.sourceProvider == expectedContext.sourceProvider &&
        file.sourceRoute == expectedContext.sourceRoute &&
        file.contextType == expectedContext.contextType &&
        file.contextId == expectedOperationKey &&
        file.contextTitle == expectedContext.contextTitle &&
        file.contextSubtitle == expectedContext.contextSubtitle &&
        expectedTags.length == actualTags.length &&
        actualTags.containsAll(expectedTags) &&
        expectedMetadataMatches &&
        file.metadata['sha256']?.toString().toLowerCase() == expectedSha256 &&
        file.metadata['operation_key']?.toString() == expectedOperationKey &&
        file.deletedAt == null;
    if (!recordMatches) {
      throw StateError(
        'Stored immutable evidence does not match the requested operation.',
      );
    }

    final storedBytes = await _supabase.storage
        .from(file.storageBucket)
        .download(file.storagePath);
    if (storedBytes.length != expectedBytes.length ||
        sha256.convert(storedBytes).toString() != expectedSha256) {
      throw StateError('Stored immutable evidence bytes do not match.');
    }
    return file;
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
