import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/shared/models/android_release_manifest.dart';

void main() {
  const tenantId = '5443b130-cc28-45af-a420-cd500b288890';
  const fromCommit = '1111111111111111111111111111111111111111';
  const toCommit = '2222222222222222222222222222222222222222';
  final validSha256 = List.filled(64, 'a').join();
  final secondSha256 = List.filled(64, 'b').join();

  Map<String, dynamic> validReleaseNotes() => {
        'schema_version': 1,
        'locale': 'es-CL',
        'source': 'ai',
        'from_commit': fromCommit,
        'to_commit': toCommit,
        'title': 'Novedades de esta actualización',
        'summary': 'Mejoramos tareas cotidianas del sistema.',
        'modules': [
          {
            'id': 'workshop',
            'label': 'Taller',
            'items': [
              'Ahora es más fácil revisar y descargar presupuestos.',
            ],
            'evidence_paths': [
              'lib/modules/bikeshop/pages/pegas_table_page.dart',
            ],
          },
        ],
      };

  Map<String, dynamic> validManifest() => {
        'schema_version': 1,
        'package_name': 'com.vinabike.erp',
        'version_name': '1.0.2',
        'version_code': 4,
        'apk_object_path':
            '$tenantId/android/releases/vinabike-erp-1.0.2+4-arm64-v8a.apk',
        'sha256': validSha256,
        'size_bytes': 42 * 1024 * 1024,
        'apk_parts': [
          {
            'object_path': '$tenantId/android/releases/'
                'vinabike-erp-1.0.2+4-arm64-v8a.apk.part000',
            'sha256': validSha256,
            'size_bytes': 21 * 1024 * 1024,
          },
          {
            'object_path': '$tenantId/android/releases/'
                'vinabike-erp-1.0.2+4-arm64-v8a.apk.part001',
            'sha256': secondSha256,
            'size_bytes': 21 * 1024 * 1024,
          },
        ],
        'published_at': '2026-07-26T01:00:00Z',
        'commit': toCommit,
        'release_notes': validReleaseNotes(),
      };

  test('parses the exact tenant-scoped Android release contract', () {
    final bytes = Uint8List.fromList(utf8.encode(jsonEncode(validManifest())));

    final release = AndroidReleaseManifest.fromBytes(bytes, tenantId: tenantId);

    expect(release.versionCode, 4);
    expect(release.versionName, '1.0.2');
    expect(release.sha256, validSha256);
    expect(release.parts, hasLength(2));
    expect(release.parts.last.sha256, secondSha256);
    expect(release.commit, toCommit);
    expect(release.releaseNotes?.title, 'Novedades de esta actualización');
    expect(release.releaseNotes?.modules.single.label, 'Taller');
    expect(
      AndroidReleaseManifest.latestManifestPath(tenantId),
      '$tenantId/android/latest.json',
    );
  });

  test('rejects another application package', () {
    final manifest = validManifest()..['package_name'] = 'com.attacker.fake';

    expect(
      () => AndroidReleaseManifest.fromJson(manifest, tenantId: tenantId),
      throwsFormatException,
    );
  });

  test('ignores optional release notes that do not match the release commit',
      () {
    final manifest = validManifest();
    (manifest['release_notes'] as Map<String, dynamic>)['to_commit'] =
        fromCommit;

    final release = AndroidReleaseManifest.fromJson(
      manifest,
      tenantId: tenantId,
    );

    expect(release.commit, toCommit);
    expect(release.releaseNotes, isNull);
  });

  test('ignores malformed or oversized optional notes without blocking update',
      () {
    final malformed = validManifest()..['release_notes'] = 'Piloto privado.';
    final oversized = validManifest();
    ((oversized['release_notes'] as Map<String, dynamic>)['modules'] as List)
        .first['items'] = [List.filled(161, 'x').join()];

    expect(
      AndroidReleaseManifest.fromJson(
        malformed,
        tenantId: tenantId,
      ).releaseNotes,
      isNull,
    );
    expect(
      AndroidReleaseManifest.fromJson(
        oversized,
        tenantId: tenantId,
      ).releaseNotes,
      isNull,
    );
  });

  test('rejects an invalid publication commit', () {
    final manifest = validManifest()..['commit'] = 'not-a-commit';

    expect(
      () => AndroidReleaseManifest.fromJson(manifest, tenantId: tenantId),
      throwsFormatException,
    );
  });

  test('rejects an APK path outside the active tenant', () {
    final manifest = validManifest()
      ..['apk_object_path'] =
          '00000000-0000-0000-0000-000000000000/android/releases/fake.apk';

    expect(
      () => AndroidReleaseManifest.fromJson(manifest, tenantId: tenantId),
      throwsFormatException,
    );
  });

  test('rejects traversal and non-APK release paths', () {
    final traversal = validManifest()
      ..['apk_object_path'] = '$tenantId/android/releases/../private.json';
    final wrongType = validManifest()
      ..['apk_object_path'] = '$tenantId/android/releases/release.zip';

    expect(
      () => AndroidReleaseManifest.fromJson(traversal, tenantId: tenantId),
      throwsFormatException,
    );
    expect(
      () => AndroidReleaseManifest.fromJson(wrongType, tenantId: tenantId),
      throwsFormatException,
    );
  });

  test('rejects reordered, oversized, and mismatched APK parts', () {
    final reordered = validManifest();
    (reordered['apk_parts'] as List<dynamic>)[0]['object_path'] =
        '$tenantId/android/releases/'
        'vinabike-erp-1.0.2+4-arm64-v8a.apk.part001';
    final oversizedPart = validManifest();
    (oversizedPart['apk_parts'] as List<dynamic>)[0]['size_bytes'] =
        AndroidReleaseManifest.maximumPartBytes + 1;
    final mismatchedTotal = validManifest()..['size_bytes'] = 41 * 1024 * 1024;

    expect(
      () => AndroidReleaseManifest.fromJson(reordered, tenantId: tenantId),
      throwsFormatException,
    );
    expect(
      () => AndroidReleaseManifest.fromJson(oversizedPart, tenantId: tenantId),
      throwsFormatException,
    );
    expect(
      () =>
          AndroidReleaseManifest.fromJson(mismatchedTotal, tenantId: tenantId),
      throwsFormatException,
    );
  });

  test('rejects invalid digest and oversized artifacts', () {
    final invalidDigest = validManifest()..['sha256'] = 'not-a-digest';
    final oversized = validManifest()
      ..['size_bytes'] = AndroidReleaseManifest.maximumApkBytes + 1;

    expect(
      () => AndroidReleaseManifest.fromJson(invalidDigest, tenantId: tenantId),
      throwsFormatException,
    );
    expect(
      () => AndroidReleaseManifest.fromJson(oversized, tenantId: tenantId),
      throwsFormatException,
    );
  });
}
