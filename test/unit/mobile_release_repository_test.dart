import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vinabike_erp/shared/services/mobile_release_repository.dart';

void main() {
  const tenantId = '5443b130-cc28-45af-a420-cd500b288890';
  const commit = '2222222222222222222222222222222222222222';
  const sha256 =
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  const manifestPath = '$tenantId/android/latest.json';
  const signedPath =
      '/object/sign/${MobileReleaseRepository.bucketName}/$manifestPath';

  Map<String, dynamic> manifest() {
    const apkPath =
        '$tenantId/android/releases/vinabike-erp-1.0.3+7-arm64-v8a.apk';
    return {
      'schema_version': 1,
      'package_name': 'com.vinabike.erp',
      'version_name': '1.0.3',
      'version_code': 7,
      'apk_object_path': apkPath,
      'sha256': sha256,
      'size_bytes': 1024,
      'apk_parts': [
        {
          'object_path': '$apkPath.part000',
          'sha256': sha256,
          'size_bytes': 1024,
        },
      ],
      'published_at': '2026-07-26T21:30:00Z',
      'commit': commit,
    };
  }

  test(
    'loads latest.json through a short signed no-cache URL with a fresh token',
    () async {
      final signRequests = <http.Request>[];
      final supabase = SupabaseClient(
        'https://example.supabase.co',
        'test-anon-key',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient((request) async {
          signRequests.add(request);
          expect(request.method, 'POST');
          expect(
            request.url.path,
            '/storage/v1/object/sign/'
            '${MobileReleaseRepository.bucketName}/$manifestPath',
          );
          expect(jsonDecode(request.body), {'expiresIn': 60});
          return http.Response(
            jsonEncode({
              'signedURL': '$signedPath?token=private-manifest-token',
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      addTearDown(supabase.dispose);

      final downloadRequests = <http.Request>[];
      final downloadClient = MockClient((request) async {
        downloadRequests.add(request);
        return http.Response(
          jsonEncode(manifest()),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      var checkNumber = 0;
      final repository = MobileReleaseRepository(
        supabase: supabase,
        httpClient: downloadClient,
        now: () => DateTime.fromMicrosecondsSinceEpoch(
          1722030000000000 + checkNumber++,
          isUtc: true,
        ),
      );
      addTearDown(repository.dispose);

      final first = await repository.fetchLatestAndroidRelease(
        tenantId: tenantId,
      );
      final second = await repository.fetchLatestAndroidRelease(
        tenantId: tenantId,
      );

      expect(first.versionCode, 7);
      expect(second.commit, commit);
      expect(signRequests, hasLength(2));
      expect(downloadRequests, hasLength(2));
      expect(
        downloadRequests.map(
          (request) => request.url.queryParameters['release_check'],
        ),
        ['1722030000000000', '1722030000000001'],
      );
      for (final request in downloadRequests) {
        expect(request.method, 'GET');
        expect(
          request.url.path,
          '/storage/v1/object/sign/'
          '${MobileReleaseRepository.bucketName}/$manifestPath',
        );
        expect(
          request.url.queryParameters['token'],
          'private-manifest-token',
        );
        expect(
          request.headers['Cache-Control'],
          'no-cache, no-store, max-age=0',
        );
        expect(request.headers['Pragma'], 'no-cache');
      }
    },
  );
}
