import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../shared/constants/storage_constants.dart';
import '../../../shared/services/image_service.dart';

/// A reusable image stored in the Website Builder media library.
class WebsiteMediaAsset {
  const WebsiteMediaAsset({
    required this.name,
    required this.path,
    required this.publicUrl,
    this.createdAt,
    this.updatedAt,
    this.metadata = const <String, dynamic>{},
  });

  final String name;
  final String path;
  final String publicUrl;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final Map<String, dynamic> metadata;

  bool get hasTransparency {
    final lower = name.toLowerCase();
    return lower.endsWith('.png') || lower.endsWith('.webp');
  }
}

/// Canonical storage boundary for Website Builder media.
///
/// Inline editing, schema fields and Canvas all use this service, so an asset
/// uploaded in any editor surface is immediately reusable in the others.
class WebsiteMediaService {
  WebsiteMediaService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  static const String libraryFolder = 'website/media';
  static const List<String> _legacyFolders = <String>[
    'website/blocks',
    'website/blocks/optimized',
    'website-images',
    'website-images/background-removed',
    StorageFolders.marketingAssets,
  ];

  Future<List<WebsiteMediaAsset>> listAssets({String query = ''}) async {
    final assets = <WebsiteMediaAsset>[];
    final seenUrls = <String>{};

    for (final folder in <String>[libraryFolder, ..._legacyFolders]) {
      try {
        final objects = await _client.storage
            .from(StorageConfig.defaultBucket)
            .list(path: folder, searchOptions: const SearchOptions(limit: 100));
        for (final object in objects) {
          if (!_isImageName(object.name)) continue;
          final path = '$folder/${object.name}';
          final url = _client.storage
              .from(StorageConfig.defaultBucket)
              .getPublicUrl(path);
          if (!seenUrls.add(url)) continue;
          assets.add(
            WebsiteMediaAsset(
              name: object.name,
              path: path,
              publicUrl: url,
              createdAt: _parseDate(object.createdAt),
              updatedAt: _parseDate(object.updatedAt),
              metadata: Map<String, dynamic>.from(
                object.metadata ?? const <String, dynamic>{},
              ),
            ),
          );
        }
      } catch (_) {
        // A legacy folder may not exist or may not be listable for this role.
        // Keep the rest of the library usable instead of failing the picker.
      }
    }

    final normalizedQuery = query.trim().toLowerCase();
    if (normalizedQuery.isNotEmpty) {
      assets.removeWhere(
        (asset) => !asset.name.toLowerCase().contains(normalizedQuery),
      );
    }
    assets.sort((a, b) {
      final aDate = a.updatedAt ?? a.createdAt;
      final bDate = b.updatedAt ?? b.createdAt;
      if (aDate == null && bDate == null) return a.name.compareTo(b.name);
      if (aDate == null) return 1;
      if (bDate == null) return -1;
      return bDate.compareTo(aDate);
    });
    return assets;
  }

  Future<WebsiteMediaAsset> uploadImage({
    required Uint8List bytes,
    required String fileName,
  }) async {
    final publicUrl = await ImageService.uploadBytes(
      bytes: bytes,
      fileName: fileName,
      bucket: StorageConfig.defaultBucket,
      folder: libraryFolder,
    );
    if (publicUrl == null) {
      throw StateError('No se pudo guardar la imagen.');
    }
    return WebsiteMediaAsset(
      name: fileName,
      path: '$libraryFolder/$fileName',
      publicUrl: publicUrl,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
  }

  static bool _isImageName(String name) {
    final lower = name.toLowerCase();
    return lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.png') ||
        lower.endsWith('.webp') ||
        lower.endsWith('.gif');
  }

  static DateTime? _parseDate(String? value) =>
      value == null ? null : DateTime.tryParse(value);
}
