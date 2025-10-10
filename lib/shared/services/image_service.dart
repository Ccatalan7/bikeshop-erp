import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

class ImageService {
  static final FirebaseStorage _storage = FirebaseStorage.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;
  static final http.Client _httpClient = http.Client();
  static final ImagePicker _picker = ImagePicker();
  
  // Upload image to Firebase Storage
  static Future<String?> uploadImage(File imageFile, String bucket, String folder) async {
    try {
      final fileName = _buildFileName(imageFile);
      final isExplicitBucket = bucket.startsWith('gs://') || bucket.startsWith('https://');
      final storage = isExplicitBucket
          ? FirebaseStorage.instanceFor(bucket: bucket)
          : _storage;

      Reference ref = storage.ref();
      if (!isExplicitBucket) {
        final normalizedBucket = _normalizePath(bucket);
        if (normalizedBucket.isNotEmpty) {
          ref = ref.child(normalizedBucket);
        }
      }

      final normalizedFolder = _normalizePath(folder);
      if (normalizedFolder.isNotEmpty) {
        ref = ref.child(normalizedFolder);
      }

      ref = ref.child(fileName);

      final fullPath = ref.fullPath;

      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
        return await _uploadImageWindows(imageFile, fullPath, fileName, ref.bucket);
      }

      final metadata = SettableMetadata(contentType: _inferContentType(fileName));

      if (kDebugMode) {
        debugPrint('[ImageService] Uploading to ${ref.fullPath} (bucket: ${ref.bucket})');
      }

      final uploadTask = ref.putFile(imageFile, metadata);
      final snapshot = await uploadTask;

      if (kDebugMode) {
        debugPrint('[ImageService] Upload complete (state: ${snapshot.state.name})');
      }

      FirebaseException? lastError;
      for (var attempt = 0; attempt < 3; attempt++) {
        try {
          final downloadUrl = await snapshot.ref.getDownloadURL();
          if (kDebugMode) {
            debugPrint('[ImageService] Download URL fetched on attempt ${attempt + 1}');
          }
          return downloadUrl;
        } on FirebaseException catch (e) {
          lastError = e;
          if (kDebugMode) {
            debugPrint('[ImageService] getDownloadURL attempt ${attempt + 1} failed: ${e.code}');
          }
          if (e.code == 'object-not-found') {
            await Future.delayed(Duration(milliseconds: 300 * (attempt + 1)));
            continue;
          }
          rethrow;
        }
      }

      if (lastError != null) throw lastError;

      return null;
    } catch (e) {
      if (kDebugMode) print('Image upload error: $e');
      rethrow;
    }
  }
  
  // Pick image from gallery or camera
  static Future<File?> pickImage({ImageSource source = ImageSource.gallery}) async {
    try {
      if (!kIsWeb && (Platform.isWindows || Platform.isLinux)) {
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
      // Extract file path from Firebase Storage URL
      final ref = _storage.refFromURL(imageUrl);
      if (kDebugMode) {
        debugPrint('[ImageService] Deleting ${ref.fullPath}');
      }
      await ref.delete();
      
      return true;
    } catch (e) {
      if (kDebugMode) print('Image deletion error: $e');
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

  static Future<String?> _uploadImageWindows(
    File imageFile,
    String fullPath,
    String fileName,
    String bucket,
  ) async {
    final candidateBuckets = _candidateBuckets(bucket);
    FirebaseException? lastError;

    for (final candidate in candidateBuckets) {
      final uploadUri = Uri.https(
        'firebasestorage.googleapis.com',
        '/upload/storage/v1/b/$candidate/o',
        {
          'uploadType': 'media',
          'name': fullPath,
        },
      );

      final headers = {
        'Content-Type': _inferContentType(fileName) ?? 'application/octet-stream',
        'Accept': 'application/json',
      };

      User? user = _auth.currentUser;
      if (user == null) {
        try {
          if (kDebugMode) {
            debugPrint('[ImageService] No authenticated user; attempting anonymous sign-in for Windows upload.');
          }
          final credential = await _auth.signInAnonymously();
          user = credential.user;
        } catch (e) {
          if (kDebugMode) {
            debugPrint('[ImageService] Anonymous sign-in failed: $e');
          }
        }
      }

      if (user != null) {
        final token = await user.getIdToken();
        if (token != null && token.isNotEmpty) {
          headers['Authorization'] = 'Bearer $token';
          if (kDebugMode) {
            debugPrint('[ImageService] Windows REST using auth token (length: ${token.length}) for user ${user.uid}');
          }
        } else {
          if (kDebugMode) {
            debugPrint('[ImageService] Windows REST user ${user.uid} has no ID token available');
          }
        }
      } else {
        if (kDebugMode) {
          debugPrint('[ImageService] Windows REST upload proceeding WITHOUT auth token (no current user).');
        }
      }

      final bytes = await imageFile.readAsBytes();

      if (kDebugMode) {
        debugPrint('[ImageService] Windows REST upload attempt using bucket "$candidate" -> ${uploadUri.toString()}');
      }

      http.Response response;
      try {
        response = await _httpClient.post(uploadUri, headers: headers, body: bytes);
      } on SocketException catch (e) {
        if (kDebugMode) {
          debugPrint('[ImageService] Windows REST upload socket error for bucket "$candidate": $e');
        }
        lastError = FirebaseException(
          plugin: 'firebase_storage',
          code: 'network-error',
          message: 'Windows REST upload failed due to network error: $e',
        );
        continue;
      }

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final tokensRaw = json['downloadTokens'];
        final downloadToken = tokensRaw is String && tokensRaw.isNotEmpty
            ? tokensRaw.split(',').first
            : null;
        final encodedPath = Uri.encodeComponent(fullPath);
        final tokenQuery = downloadToken != null ? '&token=$downloadToken' : '';
  final downloadUrl = 'https://firebasestorage.googleapis.com/v0/b/$candidate/o/$encodedPath?alt=media$tokenQuery';

        if (kDebugMode) {
          debugPrint('[ImageService] Windows upload success via REST using bucket "$candidate".');
        }

        return downloadUrl;
      }

      if (kDebugMode) {
        debugPrint('[ImageService] Windows REST upload failed for bucket "$candidate": ${response.statusCode} ${response.body}');
      }

      lastError = FirebaseException(
        plugin: 'firebase_storage',
        code: 'rest-upload-failed',
        message: 'Windows REST upload failed (${response.statusCode}): ${response.body}',
      );
    }

    throw lastError ?? FirebaseException(
      plugin: 'firebase_storage',
      code: 'rest-upload-failed',
      message: 'Windows REST upload failed: No candidate bucket succeeded.',
    );
  }

  static List<String> _candidateBuckets(String bucket) {
    var value = bucket.trim();
    if (value.startsWith('gs://')) {
      value = value.substring(5);
    }

    if (value.startsWith('http://') || value.startsWith('https://')) {
      value = Uri.parse(value).host;
    }

    final candidates = <String>{value};
    if (value.endsWith('.firebasestorage.app')) {
      candidates.add(value.replaceFirst('.firebasestorage.app', '.appspot.com'));
    }
    return candidates.toList();
  }
}