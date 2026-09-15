import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as path;
import 'package:vinabike_erp/shared/services/desktop_update_service_io.dart';

void main() {
  const windowsTag = 'windows-v1.0.1_3-42';
  const macosTag = 'macos-v1.0.1-42';
  const fromCommit = '1111111111111111111111111111111111111111';
  const toCommit = '2222222222222222222222222222222222222222';

  String repeated(String value, int count) => List.filled(count, value).join();

  Map<String, dynamic> releaseNotes() => {
        'schema_version': 1,
        'locale': 'es-CL',
        'source': 'ai',
        'from_commit': fromCommit,
        'to_commit': toCommit,
        'title': 'Novedades de esta actualización',
        'summary': 'Mejoramos varias tareas del sistema.',
        'modules': [
          {
            'id': 'inventory',
            'label': 'Inventario',
            'items': ['Ahora es más fácil revisar la disponibilidad.'],
            'evidence_paths': ['lib/modules/inventory/pages/product_list.dart'],
          },
        ],
      };

  List<Map<String, dynamic>> windowsReleaseResponse() {
    const base =
        'https://github.com/Ccatalan7/bikeshop-erp/releases/download/$windowsTag';
    const zipName = 'vinabike_erp_windows_1.0.1_3-42.zip';
    return [
      {
        'draft': false,
        'prerelease': false,
        'tag_name': windowsTag,
        'name': 'Vinabike ERP Windows',
        'target_commitish': toCommit,
        'assets': [
          {
            'name': zipName,
            'browser_download_url': '$base/$zipName',
          },
          {
            'name': '$zipName.sha256',
            'browser_download_url': '$base/$zipName.sha256',
          },
          {
            'name': 'install_vinabike_erp.ps1',
            'browser_download_url': '$base/install_vinabike_erp.ps1',
          },
          {
            'name': 'windows-release-manifest.json',
            'browser_download_url': '$base/windows-release-manifest.json',
          },
        ],
      },
    ];
  }

  Map<String, dynamic> windowsManifest() => {
        'tag_name': windowsTag,
        'commit': toCommit,
        'zip_name': 'vinabike_erp_windows_1.0.1_3-42.zip',
        'zip_sha256': repeated('a', 64),
        'installer_name': 'install_vinabike_erp.ps1',
        'installer_sha256': repeated('b', 64),
        'release_notes': releaseNotes(),
      };

  Map<String, dynamic> macosManifest() {
    const archiveName = 'vinabike_erp_macos_1.0.1-42.zip';
    const base =
        'https://github.com/Ccatalan7/bikeshop-erp/releases/download/$macosTag';
    return {
      'tag_name': macosTag,
      'app_name': 'Vinabike ERP.app',
      'bundle_id': 'com.vinabike.vinabikeErp',
      'bundle_version': '42',
      'short_version': '1.0.1',
      'archive_name': archiveName,
      'archive_url': '$base/$archiveName',
      'archive_sha256': repeated('b', 64),
      'installer_url': '$base/install_vinabike_erp_macos.sh',
      'installer_sha256': repeated('c', 64),
      'commit': toCommit,
      'run_id': '42',
      'built_at': '2026-07-24T12:00:00Z',
      'release_notes': releaseNotes(),
    };
  }

  test('Windows loads notes only from a manifest bound to release and zip',
      () async {
    var manifestRequests = 0;
    final client = MockClient((request) async {
      if (request.url.host == 'api.github.com') {
        return http.Response(jsonEncode(windowsReleaseResponse()), 200);
      }
      if (request.url.path.endsWith('/windows-release-manifest.json')) {
        manifestRequests += 1;
        return http.Response(jsonEncode(windowsManifest()), 200);
      }
      return http.Response('not found', 404);
    });
    final service = DesktopUpdateService(httpClient: client);
    addTearDown(service.dispose);

    final update = await service.fetchLatestWindowsReleaseForTesting();

    expect(manifestRequests, 1);
    expect(update.tag, windowsTag);
    expect(update.commit, toCommit);
    expect(update.assetName, 'vinabike_erp_windows_1.0.1_3-42.zip');
    expect(update.releaseNotes?.modules.single.label, 'Inventario');
  });

  test('Windows rejects a manifest from another commit', () async {
    final client = MockClient((request) async {
      if (request.url.host == 'api.github.com') {
        return http.Response(jsonEncode(windowsReleaseResponse()), 200);
      }
      final manifest = windowsManifest()
        ..['commit'] = '3333333333333333333333333333333333333333';
      return http.Response(jsonEncode(manifest), 200);
    });
    final service = DesktopUpdateService(httpClient: client);
    addTearDown(service.dispose);

    await expectLater(
      service.fetchLatestWindowsReleaseForTesting(),
      throwsA(isA<FormatException>()),
    );
  });

  List<Map<String, dynamic>> otherPlatformReleases(int count) => List.generate(
      count,
      (index) => {
            'draft': false,
            'prerelease': false,
            'tag_name': 'macos-v1.0.3-$index',
            'assets': [
              {'name': 'vinabike_erp_macos_1.0.3-$index.zip'},
            ],
          });

  test('Windows discovery continues past a full page of macOS releases',
      () async {
    final requestedPages = <String?>[];
    final client = MockClient((request) async {
      if (request.url.host == 'api.github.com') {
        final page = request.url.queryParameters['page'] ?? '1';
        requestedPages.add(page);
        final releases =
            page == '1' ? otherPlatformReleases(100) : windowsReleaseResponse();
        return http.Response(jsonEncode(releases), 200);
      }
      return http.Response(jsonEncode(windowsManifest()), 200);
    });
    final service = DesktopUpdateService(httpClient: client);
    addTearDown(service.dispose);

    final update = await service.fetchLatestWindowsReleaseForTesting();

    expect(requestedPages, ['1', '2']);
    expect(update.tag, windowsTag);
    expect(update.commit, toCommit);
    expect(update.releaseNotes?.toCommit, toCommit);
  });

  test('Windows discovery stops at the end of the release list', () async {
    var requests = 0;
    final client = MockClient((request) async {
      requests += 1;
      return http.Response(jsonEncode(otherPlatformReleases(3)), 200);
    });
    final service = DesktopUpdateService(httpClient: client);
    addTearDown(service.dispose);

    await expectLater(
      service.fetchLatestWindowsReleaseForTesting(),
      throwsA(isA<StateError>()),
    );
    expect(requests, 1);
  });

  test('Windows discovery has a bounded budget when no Windows release exists',
      () async {
    var requests = 0;
    final client = MockClient((request) async {
      requests += 1;
      return http.Response(jsonEncode(otherPlatformReleases(100)), 200);
    });
    final service = DesktopUpdateService(httpClient: client);
    addTearDown(service.dispose);

    await expectLater(
      service.fetchLatestWindowsReleaseForTesting(),
      throwsA(isA<StateError>()),
    );
    expect(requests, 10);
  });

  test('Windows discovery preserves a later-page HTTP failure', () async {
    var requests = 0;
    final client = MockClient((request) async {
      requests += 1;
      if (requests == 1) {
        return http.Response(jsonEncode(otherPlatformReleases(100)), 200);
      }
      return http.Response('Unavailable', 503);
    });
    final service = DesktopUpdateService(httpClient: client);
    addTearDown(service.dispose);

    await expectLater(
      service.fetchLatestWindowsReleaseForTesting(),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'upstream status',
          contains('503'),
        ),
      ),
    );
    expect(requests, 2);
  });

  test('macOS ignores remote notes and reads the matching prepared copy',
      () async {
    final temporaryHome =
        await Directory.systemTemp.createTemp('vinabike-update-notes-');
    addTearDown(() => temporaryHome.delete(recursive: true));
    final client = MockClient(
      (_) async => http.Response(jsonEncode(macosManifest()), 200),
    );
    final service = DesktopUpdateService(
      httpClient: client,
      macosUserHomeOverride: temporaryHome.path,
    );
    addTearDown(service.dispose);

    final update = await service.fetchLatestMacosReleaseForTesting();
    expect(update.releaseNotes, isNull);

    final coordinationDirectory = Directory(
      path.join(
        temporaryHome.path,
        'Library',
        'Application Support',
        'VinabikeERP',
        'coordination',
      ),
    );
    await coordinationDirectory.create(recursive: true);
    final preparedManifest = File(
      path.join(coordinationDirectory.path, 'prepared-manifest.json'),
    );

    final mismatchedManifest = macosManifest()..['tag_name'] = 'macos-v-old';
    await preparedManifest.writeAsString(jsonEncode(mismatchedManifest));
    expect(
      await service.readPreparedMacosReleaseNotesForTesting(update),
      isNull,
    );

    await preparedManifest.writeAsString(jsonEncode(macosManifest()));
    final notes = await service.readPreparedMacosReleaseNotesForTesting(update);
    expect(notes?.toCommit, toCommit);
    expect(notes?.modules.single.items.single, contains('disponibilidad'));
  });
}
