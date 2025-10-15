import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../constants/storage_constants.dart';

class ImageService {
  static final SupabaseClient _client = Supabase.instance.client;
  static final ImagePicker _picker = ImagePicker();

  // Upload image to Supabase Storage
  static Future<String?> uploadImage(
    File imageFile,
    String bucket,
    String folder,
  ) async {
    try {
      final fileName = _buildFileName(imageFile);
      final normalizedFolder = _normalizePath(folder);
      final segments = <String>[];
      if (normalizedFolder.isNotEmpty) {
        segments.add(normalizedFolder);
      }
      segments.add(fileName);
      final objectPath = segments.join('/');

      final bytes = await imageFile.readAsBytes();
      final storageFile = _client.storage.from(bucket);

      final options = FileOptions(
        cacheControl: '3600',
        upsert: true,
        contentType: _inferContentType(fileName),
      );

      if (kDebugMode) {
        debugPrint('[ImageService] Uploading to bucket="$bucket" path="$objectPath"');
      }

      await storageFile.uploadBinary(objectPath, bytes, fileOptions: options);

      final publicUrl = storageFile.getPublicUrl(objectPath);

      if (kDebugMode) {
        debugPrint('[ImageService] Upload complete. Public URL: $publicUrl');
      }

      return publicUrl;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Image upload error: $e');
      }
      rethrow;
    }
  }

  static Future<String?> uploadToDefaultBucket(
    File imageFile,
    String folder,
  ) {
    return uploadImage(imageFile, StorageConfig.defaultBucket, folder);
  }
  
  // Pick image from gallery or camera
  static Future<File?> pickImage({ImageSource source = ImageSource.gallery}) async {
    try {
      // On desktop platforms (Windows, Linux), use file_selector
      if (!kIsWeb) {
        try {
          if (Platform.isWindows || Platform.isLinux) {
            final typeGroup = XTypeGroup(
              label: 'Imágenes',
              extensions: const ['jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp', 'heic'],
            );

            final XFile? selectedFile = await openFile(
              acceptedTypeGroups: [typeGroup],
            );

            if (selectedFile == null || selectedFile.path.isEmpty) {
              return null;
            }

            return File(selectedFile.path);
          }
        } catch (e) {
          // Platform check failed, fall through to image_picker
          if (kDebugMode) print('Platform check failed: $e');
        }
      }

      // For web and mobile, use image_picker
      final XFile? pickedFile = await _picker.pickImage(
        source: source,
        maxWidth: 1920,
        maxHeight: 1080,
        imageQuality: 85,
      );
      
      if (pickedFile != null) {
        return File(pickedFile.path);
      }
      return null;
    } catch (e) {
      if (kDebugMode) print('Image picker error: $e');
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
      imageWidget = CachedNetworkImage(
        imageUrl: imageUrl,
        width: width,
        height: height,
        fit: fit,
        placeholder: (context, url) => placeholder ?? _buildLoadingPlaceholder(),
        errorWidget: (context, url, error) => errorWidget ?? _buildDefaultPlaceholder(),
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
          debugPrint('[ImageService] Unable to determine object path for $imageUrl');
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

  static String _buildFileName(File imageFile) {
    final originalName = imageFile.uri.pathSegments.isNotEmpty
        ? imageFile.uri.pathSegments.last
        : imageFile.path.split(Platform.pathSeparator).last;
    return '${DateTime.now().millisecondsSinceEpoch}_${originalName.replaceAll(' ', '_')}';
  }

  static String _normalizePath(String value) {
    return value
        .split(RegExp(r'[\\/]+'))
        .map((segment) => segment.trim())
        .where((segment) => segment.isNotEmpty)
        .join('/');
  }

  static String? _inferContentType(String fileName) {
    final extension = fileName.split('.').last.toLowerCase();
    switch (extension) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'gif':
        return 'image/gif';
      case 'bmp':
        return 'image/bmp';
      case 'webp':
        return 'image/webp';
      case 'heic':
      case 'heif':
        return 'image/heic';
      default:
        return 'image/jpeg';
    }
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