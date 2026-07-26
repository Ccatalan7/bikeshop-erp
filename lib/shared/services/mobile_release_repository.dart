import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/android_release_manifest.dart';

class MobileReleaseRepository {
  static const bucketName = 'erp-mobile-releases';

  final SupabaseClient _supabase;

  MobileReleaseRepository({SupabaseClient? supabase})
      : _supabase = supabase ?? Supabase.instance.client;

  Future<AndroidReleaseManifest> fetchLatestAndroidRelease({
    required String tenantId,
  }) async {
    final path = AndroidReleaseManifest.latestManifestPath(tenantId);
    final bytes = await _supabase.storage.from(bucketName).download(path);

    return AndroidReleaseManifest.fromBytes(bytes, tenantId: tenantId);
  }

  Future<String> createAndroidApkPartDownloadUrl(AndroidReleasePart part) {
    return _supabase.storage
        .from(bucketName)
        .createSignedUrl(part.objectPath, 10 * 60);
  }
}
