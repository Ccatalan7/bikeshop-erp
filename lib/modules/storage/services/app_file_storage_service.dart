import 'dart:typed_data';

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

      return AppStoredFile.fromJson(row);
    } catch (_) {
      await _supabase.storage.from(bucketName).remove([storagePath]);
      rethrow;
    }
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
