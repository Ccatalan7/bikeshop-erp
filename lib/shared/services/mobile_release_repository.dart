import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/android_release_manifest.dart';

class MobileReleaseRepository {
  static const bucketName = 'erp-mobile-releases';
  static const _manifestSignedUrlLifetimeSeconds = 60;

  final SupabaseClient _supabase;
  final http.Client _httpClient;
  final bool _ownsHttpClient;
  final DateTime Function() _now;

  MobileReleaseRepository({
    SupabaseClient? supabase,
    http.Client? httpClient,
    DateTime Function()? now,
  })  : _supabase = supabase ?? Supabase.instance.client,
        _httpClient = httpClient ?? http.Client(),
        _ownsHttpClient = httpClient == null,
        _now = now ?? DateTime.now;

  Future<AndroidReleaseManifest> fetchLatestAndroidRelease({
    required String tenantId,
  }) async {
    final path = AndroidReleaseManifest.latestManifestPath(tenantId);
    final signedUrl = await _supabase.storage
        .from(bucketName)
        .createSignedUrl(path, _manifestSignedUrlLifetimeSeconds);
    final signedUri = Uri.parse(signedUrl);
    final requestUri = signedUri.replace(
      queryParameters: {
        ...signedUri.queryParameters,
        'release_check': _now().toUtc().microsecondsSinceEpoch.toString(),
      },
    );
    final response = await _httpClient.get(
      requestUri,
      headers: const {
        'Cache-Control': 'no-cache, no-store, max-age=0',
        'Pragma': 'no-cache',
      },
    );
    if (response.statusCode != 200) {
      throw StorageException(
        'Could not download the latest Android release manifest.',
        statusCode: response.statusCode.toString(),
      );
    }

    return AndroidReleaseManifest.fromBytes(
      response.bodyBytes,
      tenantId: tenantId,
    );
  }

  Future<String> createAndroidApkPartDownloadUrl(AndroidReleasePart part) {
    return _supabase.storage
        .from(bucketName)
        .createSignedUrl(part.objectPath, 10 * 60);
  }

  void dispose() {
    if (_ownsHttpClient) {
      _httpClient.close();
    }
  }
}
