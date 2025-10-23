import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'error_reporting_service.dart';

// Conditional import: use web implementation on web, mobile on other platforms
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

      final options = FileOptions(
        cacheControl: '3600',
        upsert: true,
        contentType: contentType ?? 'image/jpeg',
      );

      await storageFile.uploadBinary(objectPath, bytes, fileOptions: options);

      final publicUrl = storageFile.getPublicUrl(objectPath);
      return publicUrl;
    } catch (e, stackTrace) {
      ErrorReportingService.report('Image upload failed: $e', stackTrace);
      rethrow;
    }
  }

  /// Pick image from file system - delegates to platform-specific implementation
  static Future<({Uint8List bytes, String name})?> pickImage() async {
    return ImageServicePlatform.pickImagePlatform();
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
      imageWidget = CachedNetworkImage(
        imageUrl: imageUrl,
        width: width,
        height: height,
        fit: fit,
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
      fit: BoxFit.cover,
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

    final publicPattern = '/storage/v1/object/public/';
    final securePattern = '/storage/v1/object/sign/';

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
