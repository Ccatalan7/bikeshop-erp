import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../shared/constants/storage_constants.dart';
import '../../../shared/services/image_service.dart';
import '../../../shared/services/tenant_service.dart';
import 'website_image_upload_processor.dart';
import 'website_service.dart';

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

  String? get productId => metadata['productId']?.toString();
  int get productImageIndex => (metadata['imageIndex'] as num?)?.round() ?? 0;
  bool get linksProduct => metadata['linkProduct'] == true;
  bool get comesFromProduct => metadata['source'] == 'product';
  bool get isWebOptimized =>
      metadata['websiteVariant'] == 'web' ||
      metadata['website_variant'] == 'web' ||
      name.toLowerCase().endsWith('.webp');
  String? get sourceUrl =>
      (metadata['sourceUrl'] ?? metadata['source_url'])?.toString();
  String? get sourcePath =>
      (metadata['sourcePath'] ?? metadata['source_path'])?.toString();
  String get thumbnailUrl =>
      (metadata['thumbnailUrl'] ?? metadata['thumbnail_url'])?.toString() ??
      publicUrl;
  int? get sourceByteLength =>
      ((metadata['sourceBytes'] ?? metadata['source_bytes']) as num?)?.round();
  int? get webByteLength =>
      ((metadata['webBytes'] ?? metadata['web_bytes']) as num?)?.round();
  int? get width => (metadata['width'] as num?)?.round();
  int? get height => (metadata['height'] as num?)?.round();
}

/// A catalog product and every image already associated with it.
///
/// Products without images remain visible in the picker so the user can tell
/// that the catalog item exists but is not yet usable as campaign media.
class WebsiteProductMediaItem {
  const WebsiteProductMediaItem({
    required this.id,
    required this.name,
    required this.sku,
    required this.imageUrls,
    this.brand,
    this.categoryName,
    this.inventoryQty = 0,
    this.isSet = false,
    this.parentSetId,
    this.isActive = true,
    this.isPublished = false,
  });

  final String id;
  final String name;
  final String sku;
  final String? brand;
  final String? categoryName;
  final int inventoryQty;
  final bool isSet;
  final String? parentSetId;
  final bool isActive;
  final bool isPublished;
  final List<String> imageUrls;

  int get availableStockQuantity => inventoryQty;

  String get searchableText => <String>[
        name,
        sku,
        brand ?? '',
        categoryName ?? '',
      ].join(' ').toLowerCase();

  WebsiteMediaAsset assetFor(
    String imageUrl, {
    bool linkProduct = false,
  }) {
    final imageIndex = imageUrls.indexOf(imageUrl);
    return WebsiteMediaAsset(
      name: name,
      path: 'product/$id/${imageIndex < 0 ? 0 : imageIndex}',
      publicUrl: imageUrl,
      metadata: <String, dynamic>{
        'source': 'product',
        'productId': id,
        'productName': name,
        'sku': sku,
        'brand': brand,
        'categoryName': categoryName,
        'inventoryQty': inventoryQty,
        'isSet': isSet,
        'parentSetId': parentSetId,
        'isActive': isActive,
        'isPublished': isPublished,
        'imageIndex': imageIndex < 0 ? 0 : imageIndex,
        'linkProduct': linkProduct,
      },
    );
  }

  static List<WebsiteProductMediaItem> fromRows(
    Iterable<Map<String, dynamic>> rows,
  ) {
    return rows
        .map((row) {
          final images = <String>[];

          void addImage(dynamic value) {
            final url = value?.toString().trim() ?? '';
            if (url.isNotEmpty && !images.contains(url)) images.add(url);
          }

          void addImages(dynamic values) {
            if (values is! Iterable) return;
            for (final value in values) {
              addImage(value);
            }
          }

          // Prefer the image explicitly prepared for the website, then the main
          // inventory image. Optimized variants are fallbacks, not duplicate cards.
          addImage(row['website_image_url']);
          if (images.isEmpty) addImage(row['website_image_url_optimized']);
          if (images.isEmpty) addImage(row['image_url']);
          if (images.isEmpty) addImage(row['image_url_optimized']);
          addImages(row['website_image_urls']);
          addImages(row['image_urls']);

          return WebsiteProductMediaItem(
            id: row['id']?.toString() ?? '',
            name: row['name']?.toString() ?? 'Producto sin nombre',
            sku: row['sku']?.toString() ?? '',
            brand: row['brand']?.toString(),
            categoryName: row['category_name']?.toString(),
            inventoryQty:
                ((row['stock_quantity'] ?? row['inventory_qty']) as num?)
                        ?.round() ??
                    0,
            isSet: row['is_set'] == true,
            parentSetId: row['parent_set_id']?.toString(),
            isActive: row['is_active'] != false,
            isPublished: row['is_published'] == true,
            imageUrls: List<String>.unmodifiable(images),
          );
        })
        .where((product) => product.id.isNotEmpty)
        .toList(growable: false);
  }
}

/// Canonical storage boundary for Website Builder media.
///
/// Inline editing, schema fields and Canvas all use this service, so an asset
/// uploaded in any editor surface is immediately reusable in the others.
class WebsiteMediaService {
  WebsiteMediaService({
    SupabaseClient? client,
    TenantService? tenantService,
  })  : _client = client ?? Supabase.instance.client,
        _tenantService = tenantService;

  final SupabaseClient _client;
  final TenantService? _tenantService;

  static const String libraryFolder = 'website/media';
  static const String sourceFolder = '$libraryFolder/sources';
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
    final tenantId = await (_tenantService ?? TenantService()).getTenantId();
    final folders = <String>[
      if (tenantId != null && tenantId.isNotEmpty) '$libraryFolder/$tenantId',
      libraryFolder,
      ..._legacyFolders,
    ];

    for (final folder in folders) {
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

  Future<List<WebsiteProductMediaItem>> listProductMedia() async {
    final tenantId = await (_tenantService ?? TenantService()).getTenantId();
    if (tenantId == null || tenantId.isEmpty) {
      throw StateError('No se pudo determinar la tienda activa.');
    }

    final response = await _client
        .from('products')
        .select(
          'id,name,sku,brand,category_name,stock_quantity,inventory_qty,'
          'is_set,parent_set_id,'
          'is_active,is_published,image_url,image_url_optimized,image_urls,'
          'website_image_url,website_image_url_optimized,website_image_urls',
        )
        .eq('tenant_id', tenantId)
        .order('name', ascending: true)
        .limit(2000);

    final rows = (response as List)
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList(growable: false);
    for (final row in rows.where((row) => row['is_set'] == true)) {
      final preview = await _client.rpc(
        'preview_product_stock_impact',
        params: {'p_product_id': row['id'], 'p_quantity': 1},
      );
      final payload = preview is Map
          ? Map<String, dynamic>.from(preview)
          : preview is List && preview.length == 1 && preview.first is Map
              ? Map<String, dynamic>.from(preview.first as Map)
              : null;
      final available = (payload?['available_quantity'] as num?)?.round();
      if (available != null) {
        row['inventory_qty'] = available;
        row['stock_quantity'] = available;
      }
    }
    return WebsiteProductMediaItem.fromRows(rows);
  }

  Future<WebsiteMediaAsset> uploadImage({
    required Uint8List bytes,
    required String fileName,
    String? tenantId,
    WebsiteEditorWriteGuard? writeGuard,
    String operation = 'upload',
    String? originalUrl,
  }) async {
    final resolvedTenantId =
        tenantId ?? await (_tenantService ?? TenantService()).getTenantId();
    if (resolvedTenantId == null || resolvedTenantId.isEmpty) {
      throw StateError('No se pudo determinar la tienda activa.');
    }
    final prepared = await WebsiteImageUploadProcessor.prepare(
      bytes: bytes,
      fileName: fileName,
    );
    writeGuard?.call();
    final uploadedSource = await ImageService.uploadBytesWithDetails(
      bytes: prepared.bytes,
      fileName: prepared.fileName,
      bucket: StorageConfig.defaultBucket,
      folder: '$sourceFolder/$resolvedTenantId',
      contentType: prepared.contentType,
      cacheControl: '31536000',
      upsert: false,
      metadata: <String, dynamic>{
        'website_variant': 'source',
        'tenant_id': resolvedTenantId,
        'operation': operation,
        'original_file_name': fileName,
        'original_width': prepared.originalWidth,
        'original_height': prepared.originalHeight,
        'source_width': prepared.width,
        'source_height': prepared.height,
        'original_bytes': prepared.originalByteLength,
        'source_bytes': prepared.bytes.length,
        'has_transparency': prepared.hasTransparency,
        'was_normalized': prepared.wasNormalized,
        if (originalUrl != null && originalUrl.isNotEmpty)
          'original_url': originalUrl,
      },
    );

    try {
      writeGuard?.call();
      return await optimizeStoredImage(
        sourcePath: uploadedSource.objectPath,
        sourceUrl: uploadedSource.publicUrl,
        fileName: fileName,
        operation: operation,
        originalUrl: originalUrl,
        writeGuard: writeGuard,
        sourceMetadata: <String, dynamic>{
          'originalWidth': prepared.originalWidth,
          'originalHeight': prepared.originalHeight,
          'sourceWidth': prepared.width,
          'sourceHeight': prepared.height,
          'originalBytes': prepared.originalByteLength,
          'sourceBytes': prepared.bytes.length,
          'hasTransparency': prepared.hasTransparency,
          'wasNormalized': prepared.wasNormalized,
        },
      );
    } catch (_) {
      try {
        await _client.storage
            .from(StorageConfig.defaultBucket)
            .remove(<String>[uploadedSource.objectPath]);
      } catch (_) {
        // The hidden source remains recoverable if cleanup is not permitted.
      }
      rethrow;
    }
  }

  Future<WebsiteMediaAsset> optimizeStoredImage({
    required String sourcePath,
    required String sourceUrl,
    required String fileName,
    String operation = 'upload',
    String? originalUrl,
    WebsiteEditorWriteGuard? writeGuard,
    Map<String, dynamic> sourceMetadata = const <String, dynamic>{},
  }) async {
    writeGuard?.call();
    final response = await _client.functions.invoke(
      'website-optimize-image',
      body: <String, dynamic>{
        'sourcePath': sourcePath,
        'sourceUrl': sourceUrl,
        'fileName': fileName,
        'operation': operation,
        if (originalUrl != null && originalUrl.isNotEmpty)
          'originalUrl': originalUrl,
        'sourceMetadata': sourceMetadata,
      },
    );
    writeGuard?.call();
    final data = response.data;
    if (response.status < 200 || response.status >= 300 || data is! Map) {
      final message = data is Map
          ? data['error']?.toString()
          : 'No se pudo optimizar la imagen.';
      throw StateError(message ?? 'No se pudo optimizar la imagen.');
    }

    final path = data['path']?.toString().trim() ?? '';
    final publicUrl = data['publicUrl']?.toString().trim() ?? '';
    if (path.isEmpty || publicUrl.isEmpty) {
      throw StateError('El optimizador no devolvió una imagen válida.');
    }
    final metadata = <String, dynamic>{
      'websiteVariant': 'web',
      'sourcePath': sourcePath,
      'sourceUrl': sourceUrl,
      'operation': operation,
      if (originalUrl != null && originalUrl.isNotEmpty)
        'originalUrl': originalUrl,
      ...sourceMetadata,
      if (data['width'] is num) 'width': data['width'],
      if (data['height'] is num) 'height': data['height'],
      if (data['sourceBytes'] is num) 'sourceBytes': data['sourceBytes'],
      if (data['webBytes'] is num) 'webBytes': data['webBytes'],
      if (data['quality'] is num) 'quality': data['quality'],
      if (data['thumbnailPath'] != null) 'thumbnailPath': data['thumbnailPath'],
      if (data['thumbnailUrl'] != null) 'thumbnailUrl': data['thumbnailUrl'],
      if (data['thumbnailBytes'] is num)
        'thumbnailBytes': data['thumbnailBytes'],
    };
    return WebsiteMediaAsset(
      name: data['name']?.toString().trim().isNotEmpty == true
          ? data['name'].toString()
          : fileName,
      path: path,
      publicUrl: publicUrl,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      metadata: metadata,
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
