import 'dart:convert';
import 'dart:typed_data';

class AndroidReleaseManifest {
  static const schemaVersion = 1;
  static const packageName = 'com.vinabike.erp';
  static const maximumApkBytes = 250 * 1024 * 1024;
  static const maximumPartBytes = 40 * 1024 * 1024;
  static const maximumPartCount = 8;

  final int versionCode;
  final String versionName;
  final String apkObjectPath;
  final String sha256;
  final int sizeBytes;
  final List<AndroidReleasePart> parts;
  final DateTime publishedAt;
  final String? releaseNotes;

  const AndroidReleaseManifest({
    required this.versionCode,
    required this.versionName,
    required this.apkObjectPath,
    required this.sha256,
    required this.sizeBytes,
    required this.parts,
    required this.publishedAt,
    this.releaseNotes,
  });

  factory AndroidReleaseManifest.fromBytes(
    Uint8List bytes, {
    required String tenantId,
  }) {
    if (bytes.length > 128 * 1024) {
      throw const FormatException('The Android release manifest is too large.');
    }

    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('The Android release manifest is invalid.');
    }

    return AndroidReleaseManifest.fromJson(decoded, tenantId: tenantId);
  }

  factory AndroidReleaseManifest.fromJson(
    Map<String, dynamic> json, {
    required String tenantId,
  }) {
    final manifestSchema = json['schema_version'];
    final manifestPackage = json['package_name'];
    final versionCode = json['version_code'];
    final versionName = json['version_name'];
    final apkObjectPath = json['apk_object_path'];
    final sha256Value = json['sha256'];
    final sizeBytes = json['size_bytes'];
    final partsValue = json['apk_parts'];
    final publishedAtValue = json['published_at'];
    final releaseNotesValue = json['release_notes'];

    if (manifestSchema != schemaVersion) {
      throw const FormatException('Unsupported Android manifest schema.');
    }
    if (manifestPackage != packageName) {
      throw const FormatException('Unexpected Android application package.');
    }
    if (versionCode is! int || versionCode <= 0) {
      throw const FormatException('Invalid Android version code.');
    }
    if (versionName is! String ||
        versionName.isEmpty ||
        versionName.length > 64) {
      throw const FormatException('Invalid Android version name.');
    }
    if (apkObjectPath is! String ||
        !_isValidObjectPath(apkObjectPath, tenantId)) {
      throw const FormatException('Invalid Android APK object path.');
    }
    if (sha256Value is! String ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(sha256Value)) {
      throw const FormatException('Invalid Android APK SHA-256.');
    }
    if (sizeBytes is! int || sizeBytes <= 0 || sizeBytes > maximumApkBytes) {
      throw const FormatException('Invalid Android APK size.');
    }
    if (partsValue is! List ||
        partsValue.isEmpty ||
        partsValue.length > maximumPartCount) {
      throw const FormatException('Invalid Android APK parts.');
    }
    final parts = <AndroidReleasePart>[];
    for (var index = 0; index < partsValue.length; index += 1) {
      final partValue = partsValue[index];
      if (partValue is! Map<String, dynamic>) {
        throw const FormatException('Invalid Android APK part.');
      }
      parts.add(
        AndroidReleasePart.fromJson(
          partValue,
          expectedApkObjectPath: apkObjectPath,
          expectedIndex: index,
        ),
      );
    }
    final partBytes = parts.fold<int>(
      0,
      (total, part) => total + part.sizeBytes,
    );
    if (partBytes != sizeBytes) {
      throw const FormatException('Android APK part sizes do not add up.');
    }
    if (publishedAtValue is! String) {
      throw const FormatException('Invalid Android publication timestamp.');
    }

    final publishedAt = DateTime.tryParse(publishedAtValue)?.toUtc();
    if (publishedAt == null) {
      throw const FormatException('Invalid Android publication timestamp.');
    }

    return AndroidReleaseManifest(
      versionCode: versionCode,
      versionName: versionName,
      apkObjectPath: apkObjectPath,
      sha256: sha256Value,
      sizeBytes: sizeBytes,
      parts: List.unmodifiable(parts),
      publishedAt: publishedAt,
      releaseNotes: releaseNotesValue is String && releaseNotesValue.isNotEmpty
          ? releaseNotesValue
          : null,
    );
  }

  static String latestManifestPath(String tenantId) =>
      '$tenantId/android/latest.json';

  static bool _isValidObjectPath(String value, String tenantId) {
    final requiredPrefix = '$tenantId/android/releases/';
    return value.startsWith(requiredPrefix) &&
        value.endsWith('.apk') &&
        !value.contains('..') &&
        !value.contains('\\') &&
        Uri.tryParse(value)?.hasScheme != true;
  }
}

class AndroidReleasePart {
  final String objectPath;
  final String sha256;
  final int sizeBytes;

  const AndroidReleasePart({
    required this.objectPath,
    required this.sha256,
    required this.sizeBytes,
  });

  factory AndroidReleasePart.fromJson(
    Map<String, dynamic> json, {
    required String expectedApkObjectPath,
    required int expectedIndex,
  }) {
    final objectPath = json['object_path'];
    final sha256Value = json['sha256'];
    final sizeBytes = json['size_bytes'];
    final expectedSuffix = '.part${expectedIndex.toString().padLeft(3, '0')}';

    if (objectPath is! String ||
        objectPath != '$expectedApkObjectPath$expectedSuffix' ||
        objectPath.contains('..') ||
        objectPath.contains('\\') ||
        Uri.tryParse(objectPath)?.hasScheme == true) {
      throw const FormatException('Invalid Android APK part path.');
    }
    if (sha256Value is! String ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(sha256Value)) {
      throw const FormatException('Invalid Android APK part SHA-256.');
    }
    if (sizeBytes is! int ||
        sizeBytes <= 0 ||
        sizeBytes > AndroidReleaseManifest.maximumPartBytes) {
      throw const FormatException('Invalid Android APK part size.');
    }

    return AndroidReleasePart(
      objectPath: objectPath,
      sha256: sha256Value,
      sizeBytes: sizeBytes,
    );
  }
}
