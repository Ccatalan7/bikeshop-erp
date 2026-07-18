import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../shared/constants/storage_constants.dart';
import '../../../shared/services/image_service.dart';
import '../../../shared/services/tenant_service.dart';

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
    this.isActive = true,
    this.isPublished = false,
  });

  final String id;
  final String name;
  final String sku;
  final String? brand;
  final String? categoryName;
  final int inventoryQty;
  final bool isActive;
  final bool isPublished;
  final List<String> imageUrls;

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

  Future<List<WebsiteProductMediaItem>> listProductMedia() async {
    final tenantId = await (_tenantService ?? TenantService()).getTenantId();
    if (tenantId == null || tenantId.isEmpty) {
      throw StateError('No se pudo determinar la tienda activa.');
    }

    final response = await _client
        .from('products')
        .select(
          'id,name,sku,brand,category_name,stock_quantity,inventory_qty,'
          'is_active,is_published,image_url,image_url_optimized,image_urls,'
          'website_image_url,website_image_url_optimized,website_image_urls',
        )
        .eq('tenant_id', tenantId)
        .order('name', ascending: true)
        .limit(2000);

    return WebsiteProductMediaItem.fromRows(
      (response as List)
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row)),
    );
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
