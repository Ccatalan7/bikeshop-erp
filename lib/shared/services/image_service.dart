import 'package:flutter/foundation.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:mime/mime.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'error_reporting_service.dart';
import '../constants/storage_constants.dart';

// Conditional import: use web implementation on web, mobile on other platforms
import 'package:file_picker/file_picker.dart';

import 'image_service_mobile.dart'
    if (dart.library.html) 'image_service_web.dart';

class ImageService {
  static final SupabaseClient _client = Supabase.instance.client;

  /// Sanitize filename to be storage-safe
  static String _sanitizeFileName(String fileName) {
    // Remove or replace problematic characters
    String sanitized = fileName
        .replaceAll(RegExp(r'[^\w\s\-\.]'),
            '_') // Replace special chars with underscore
        .replaceAll(RegExp(r'\s+'), '_') // Replace spaces with underscore
        .replaceAll(
            RegExp(r'_+'), '_') // Replace multiple underscores with single
        .replaceAll(
            RegExp(r'^_+|_+$'), ''); // Trim leading/trailing underscores

    // Ensure we have a valid extension
    if (!sanitized.contains('.')) {
      sanitized = '$sanitized.png';
    }

    return sanitized;
  }

  static String _inferContentType(Uint8List bytes, String fileName) {
    // Try mime package first (uses file name + header bytes)
    final inferred = lookupMimeType(fileName, headerBytes: bytes);
    if (inferred != null && inferred.isNotEmpty) {
      return inferred;
    }

    final lower = fileName.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    if (lower.endsWith('.gif')) return 'image/gif';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.svg')) return 'image/svg+xml';

    return 'application/octet-stream';
  }

  /// Upload image bytes directly - WEB ONLY VERSION
  static Future<String?> uploadBytes({
    required Uint8List bytes,
    required String fileName,
    required String bucket,
    required String folder,
    String? contentType,
  }) async {
    try {
      final sanitizedFileName = _sanitizeFileName(fileName);
      final uniqueFileName =
          '${DateTime.now().millisecondsSinceEpoch}_$sanitizedFileName';
      final normalizedFolder = _normalizePath(folder);
      final segments = <String>[];
      if (normalizedFolder.isNotEmpty) {
        segments.add(normalizedFolder);
      }
      segments.add(uniqueFileName);
      final objectPath = segments.join('/');

      final storageFile = _client.storage.from(bucket);

      final detectedContentType =
          contentType ?? _inferContentType(bytes, sanitizedFileName);

      final options = FileOptions(
        cacheControl: '3600',
        upsert: true,
        contentType: detectedContentType,
      );

      await storageFile.uploadBinary(objectPath, bytes, fileOptions: options);

      final publicUrl = storageFile.getPublicUrl(objectPath);
      return publicUrl;
    } catch (e, stackTrace) {
      ErrorReportingService.report('Image upload failed: $e', stackTrace);
      rethrow;
    }
  }

  // ============================================================
  // IMAGE OPTIMIZATION - Auto-create WebP versions
  // ============================================================

  /// Optimization settings
  static const int _maxOptimizedWidth = 1200;
  static const int _optimizedQuality = 80;

  /// Upload product image with automatic optimization.
  ///
  /// Returns both URLs: original (full quality) and optimized (compressed).
  /// The optimized version is resized to max 1200px width and compressed to JPEG.
  ///
  /// Usage:
  /// ```dart
  /// final result = await ImageService.uploadProductImageWithOptimization(
  ///   bytes: imageBytes,
  ///   fileName: 'product.jpg',
  /// );
  /// // result.originalUrl - Full quality image
  /// // result.optimizedUrl - Compressed version for web
  /// ```
  static Future<({String originalUrl, String? optimizedUrl})>
      uploadProductImageWithOptimization({
    required Uint8List bytes,
    required String fileName,
  }) async {
    try {
      // 1. Upload original image
      final originalUrl = await uploadBytes(
        bytes: bytes,
        fileName: fileName,
        bucket: StorageConfig.defaultBucket,
        folder: StorageFolders.productMain,
      );

      if (originalUrl == null) {
        throw Exception('Failed to upload original image');
      }

      // 2. Create and upload optimized version
      String? optimizedUrl;
      try {
        final optimizedBytes = await _createOptimizedImage(bytes, fileName);
        if (optimizedBytes != null) {
          // Generate optimized filename with .jpg extension
          final baseName = fileName.replaceAll(RegExp(r'\.[^.]+$'), '');
          final optimizedFileName = '${baseName}_optimized.jpg';

          optimizedUrl = await uploadBytes(
            bytes: optimizedBytes,
            fileName: optimizedFileName,
            bucket: StorageConfig.defaultBucket,
            folder: StorageFolders.productOptimized,
            contentType: 'image/jpeg',
          );

          if (optimizedUrl != null) {
            final originalKB = (bytes.length / 1024).toStringAsFixed(1);
            final optimizedKB =
                (optimizedBytes.length / 1024).toStringAsFixed(1);
            final reduction = ((1 - optimizedBytes.length / bytes.length) * 100)
                .toStringAsFixed(0);
            debugPrint(
                '📸 Image optimized: $originalKB KB → $optimizedKB KB ($reduction% smaller)');
          }
        }
      } catch (e) {
        // Don't fail the entire upload if optimization fails
        debugPrint('⚠️ Image optimization failed (using original only): $e');
      }

      return (originalUrl: originalUrl, optimizedUrl: optimizedUrl);
    } catch (e, stackTrace) {
      ErrorReportingService.report(
          'Product image upload failed: $e', stackTrace);
      rethrow;
    }
  }

  /// Create an optimized version of the image.
  /// Resizes to max width and compresses as JPEG.
  static Future<Uint8List?> _createOptimizedImage(
      Uint8List bytes, String fileName) async {
    try {
      // Decode the image
      final originalImage = img.decodeImage(bytes);
      if (originalImage == null) {
        debugPrint('⚠️ Could not decode image for optimization');
        return null;
      }

      // Resize if larger than max width
      img.Image optimized = originalImage;
      if (originalImage.width > _maxOptimizedWidth) {
        optimized = img.copyResize(originalImage, width: _maxOptimizedWidth);
        debugPrint(
            '📐 Resized: ${originalImage.width}x${originalImage.height} → ${optimized.width}x${optimized.height}');
      }

      // Encode as compressed JPEG
      final compressedBytes =
          img.encodeJpg(optimized, quality: _optimizedQuality);

      return Uint8List.fromList(compressedBytes);
    } catch (e) {
      debugPrint('⚠️ Image optimization error: $e');
      return null;
    }
  }

  /// Upload website block image with automatic optimization.
  ///
  /// For banners, heroes, and other website blocks.
  /// Returns optimized URL (falls back to original if optimization fails).
  ///
  /// Unlike product images, we only return the optimized URL since
  /// website blocks don't need dual storage tracking.
  static Future<String?> uploadWebsiteImageWithOptimization({
    required Uint8List bytes,
    required String fileName,
  }) async {
    try {
      // Try to create optimized version first
      Uint8List bytesToUpload = bytes;
      String uploadFileName = fileName;
      String folder = 'website/blocks';
      String? contentType;

      try {
        final optimizedBytes = await _createOptimizedImage(bytes, fileName);
        if (optimizedBytes != null && optimizedBytes.length < bytes.length) {
          // Optimization successful and smaller - use it
          bytesToUpload = optimizedBytes;
          final baseName = fileName.replaceAll(RegExp(r'\.[^.]+$'), '');
          uploadFileName = '${baseName}_optimized.jpg';
          folder = 'website/blocks/optimized';
          contentType = 'image/jpeg';

          final originalKB = (bytes.length / 1024).toStringAsFixed(1);
          final optimizedKB = (optimizedBytes.length / 1024).toStringAsFixed(1);
          final reduction = ((1 - optimizedBytes.length / bytes.length) * 100)
              .toStringAsFixed(0);
          debugPrint(
              '🌐 Website image optimized: $originalKB KB → $optimizedKB KB ($reduction% smaller)');
        }
      } catch (e) {
        debugPrint('⚠️ Website image optimization failed (using original): $e');
      }

      // Upload (either optimized or original)
      final url = await ImageService.uploadBytes(
        bytes: bytesToUpload,
        fileName: uploadFileName,
        bucket: StorageConfig.defaultBucket,
        folder: folder,
        contentType: contentType,
      );

      return url;
    } catch (e, stackTrace) {
      ErrorReportingService.report(
          'Website image upload failed: $e', stackTrace);
      rethrow;
    }
  }

  /// Pick image from file system - delegates to platform-specific implementation
  static Future<({Uint8List bytes, String name})?> pickImage() async {
    return ImageServicePlatform.pickImagePlatform();
  }

  /// Pick any file from file system
  static Future<({Uint8List bytes, String name})?> pickFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        withData:
            true, // Needed for web and some platforms to get bytes immediately
      );

      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        if (file.bytes != null) {
          return (bytes: file.bytes!, name: file.name);
        }
      }
      return null;
    } catch (e) {
      debugPrint('Error picking file: $e');
      return null;
    }
  }

  // Widget for displaying cached network images with fallback
  static Widget buildCachedImage({
    required String? imageUrl,
    double? width,
    double? height,
    BoxFit fit = BoxFit.cover,
    Widget? placeholder,
    Widget? errorWidget,
    bool isCircular = false,
  }) {
    Widget imageWidget;

    if (imageUrl == null || imageUrl.isEmpty) {
      imageWidget = errorWidget ?? _buildDefaultPlaceholder();
    } else {
      // Calculate optimal cache dimensions (scale down large images)
      final cacheWidth = width != null && width.isFinite
          ? (width * 2).toInt() // 2x for retina displays
          : 800; // Default max width for lists
      final cacheHeight =
          height != null && height.isFinite ? (height * 2).toInt() : 800;

      imageWidget = CachedNetworkImage(
        imageUrl: imageUrl,
        width: width,
        height: height,
        fit: fit,
        // CRITICAL: Memory cache optimization - prevents loading full resolution
        memCacheWidth: cacheWidth,
        memCacheHeight: cacheHeight,
        // CRITICAL: Disk cache optimization
        maxWidthDiskCache: cacheWidth,
        maxHeightDiskCache: cacheHeight,
        // CRITICAL: No fade animation for cached images (prevents flicker)
        fadeInDuration: const Duration(milliseconds: 0),
        fadeOutDuration: const Duration(milliseconds: 0),
        // Use URL as cache key for consistent caching
        cacheKey: imageUrl,
        placeholder: (context, url) =>
            placeholder ?? _buildLoadingPlaceholder(),
        errorWidget: (context, url, error) =>
            errorWidget ?? _buildDefaultPlaceholder(),
      );
    }

    if (isCircular) {
      return ClipOval(child: imageWidget);
    }

    return imageWidget;
  }

  // Default placeholder for missing images
  static Widget _buildDefaultPlaceholder() {
    return Container(
      color: Colors.grey[300],
      child: const Icon(
        Icons.image_not_supported,
        color: Colors.grey,
        size: 50,
      ),
    );
  }

  // Loading placeholder
  static Widget _buildLoadingPlaceholder() {
    return Container(
      color: Colors.grey[200],
      child: const Center(
        child: CircularProgressIndicator(),
      ),
    );
  }

  // Product image widget
  static Widget buildProductImage({
    required String? imageUrl,
    double size = 100,
    bool isListThumbnail = true,
  }) {
    // Handle infinite size for error widget
    final iconSize = size.isFinite ? size * 0.5 : 50.0;
    final containerSize = size.isFinite ? size : null;

    return buildCachedImage(
      imageUrl: imageUrl,
      width: containerSize,
      height: containerSize,
      fit: BoxFit
          .contain, // Changed from cover to contain - shows full image without cropping
      errorWidget: Container(
        width: containerSize,
        height: containerSize,
        color: Colors.grey[300],
        child: Center(
          child: Icon(
            Icons.pedal_bike,
            color: Colors.grey[600],
            size: iconSize,
          ),
        ),
      ),
    );
  }

  // Avatar image widget for customers/employees
  static Widget buildAvatarImage({
    required String? imageUrl,
    double radius = 25,
    String? initials,
  }) {
    if (imageUrl == null || imageUrl.isEmpty) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: Colors.blue[100],
        child: Text(
          initials ?? '?',
          style: TextStyle(
            color: Colors.blue[800],
            fontSize: radius * 0.8,
            fontWeight: FontWeight.bold,
          ),
        ),
      );
    }

    return buildCachedImage(
      imageUrl: imageUrl,
      width: radius * 2,
      height: radius * 2,
      isCircular: true,
      errorWidget: CircleAvatar(
        radius: radius,
        backgroundColor: Colors.grey[300],
        child: Icon(
          Icons.person,
          color: Colors.grey[600],
          size: radius,
        ),
      ),
    );
  }

  // Delete image from storage
  static Future<bool> deleteImage(String imageUrl, String bucket) async {
    try {
      final objectPath = _extractObjectPath(imageUrl, bucket);
      if (objectPath == null) {
        if (kDebugMode) {
          debugPrint(
              '[ImageService] Unable to determine object path for $imageUrl');
        }
        return false;
      }

      await _client.storage.from(bucket).remove([objectPath]);

      return true;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Image deletion error: $e');
      }
      return false;
    }
  }

  static String _normalizePath(String value) {
    return value
        .split(RegExp(r'[\\/]+'))
        .map((segment) => segment.trim())
        .where((segment) => segment.isNotEmpty)
        .join('/');
  }

  static String? _extractObjectPath(String imageUrl, String bucket) {
    if (imageUrl.isEmpty) return null;
    final uri = Uri.tryParse(imageUrl);
    if (uri == null) return null;

    const publicPattern = '/storage/v1/object/public/';
    const securePattern = '/storage/v1/object/sign/';

    final path = uri.path;
    if (path.contains(publicPattern)) {
      final index = path.indexOf(publicPattern) + publicPattern.length;
      final raw = path.substring(index);
      if (!raw.startsWith('$bucket/')) return null;
      return raw.substring(bucket.length + 1);
    }

    if (path.contains(securePattern)) {
      final index = path.indexOf(securePattern) + securePattern.length;
      final raw = path.substring(index);
      if (!raw.startsWith('$bucket/')) return null;
      final endIndex = raw.indexOf('?');
      final trimmed = endIndex == -1 ? raw : raw.substring(0, endIndex);
      return trimmed.substring(bucket.length + 1);
    }

    // Fallback: assume the last segments correspond to the object path.
    final segments = uri.pathSegments;
    final bucketIndex = segments.indexOf(bucket);
    if (bucketIndex == -1) return null;
    final objectSegments = segments.sublist(bucketIndex + 1);
    return objectSegments.join('/');
  }
}
