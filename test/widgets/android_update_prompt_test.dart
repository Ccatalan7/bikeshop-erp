import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vinabike_erp/shared/models/android_release_manifest.dart';
import 'package:vinabike_erp/shared/services/android_update_service.dart';
import 'package:vinabike_erp/shared/widgets/android_update_prompt.dart';

void main() {
  const tenantId = '5443b130-cc28-45af-a420-cd500b288890';
  const commit = '2222222222222222222222222222222222222222';
  const sha256 =
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://example.supabase.co',
      anonKey: 'test-anon-key',
      authOptions: const FlutterAuthClientOptions(autoRefreshToken: false),
    );
  });

  Map<String, dynamic> releaseNotes() => {
        'schema_version': 1,
        'locale': 'es-CL',
        'source': 'ai',
        'from_commit': '1111111111111111111111111111111111111111',
        'to_commit': commit,
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

  AndroidReleaseManifest release({Object? notes}) {
    const apkPath =
        '$tenantId/android/releases/vinabike-erp-1.0.2+4-arm64-v8a.apk';
    return AndroidReleaseManifest.fromJson(
      {
        'schema_version': 1,
        'package_name': 'com.vinabike.erp',
        'version_name': '1.0.2',
        'version_code': 4,
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
        'published_at': '2026-07-26T01:00:00Z',
        'commit': commit,
        'release_notes': notes,
      },
      tenantId: tenantId,
    );
  }

  Future<_FakeAndroidUpdateService> pumpPrompt(
    WidgetTester tester, {
    required AndroidReleaseManifest release,
  }) async {
    tester.view.physicalSize = const Size(384, 824);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final service = _FakeAndroidUpdateService(release);
    addTearDown(service.dispose);
    await tester.pumpWidget(
      ChangeNotifierProvider<AndroidUpdateService>.value(
        value: service,
        child: const MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                AndroidUpdatePrompt(),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    return service;
  }

  testWidgets(
    'shows a 48px Novedades action beside the primary install action at 384px',
    (tester) async {
      await pumpPrompt(tester, release: release(notes: releaseNotes()));

      final whatsNew = find.byKey(
        const ValueKey('android-update-whats-new-button'),
      );
      final install = find.byKey(
        const ValueKey('android-update-primary-button'),
      );
      expect(whatsNew, findsOneWidget);
      expect(install, findsOneWidget);
      expect(tester.widget(whatsNew), isA<TextButton>());
      expect(tester.widget(install), isA<FilledButton>());
      expect(find.text('Actualizar'), findsOneWidget);
      expect(tester.getSize(whatsNew).height, greaterThanOrEqualTo(48));
      expect(tester.getSize(install).height, greaterThanOrEqualTo(48));
      expect(tester.takeException(), isNull);

      await tester.tap(whatsNew);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        find.byKey(const ValueKey('desktop-release-notes-dialog')),
        findsOneWidget,
      );
      expect(find.text('Novedades de esta actualización'), findsOneWidget);
      expect(find.text('Taller'), findsOneWidget);
      expect(
        find.text('Ahora es más fácil revisar y descargar presupuestos.'),
        findsOneWidget,
      );
      expect(
        find.text('lib/modules/bikeshop/pages/pegas_table_page.dart'),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('keeps the generic message when validated notes are absent',
      (tester) async {
    await pumpPrompt(
      tester,
      release: release(notes: 'Legacy notes are intentionally ignored.'),
    );

    expect(
      find.byKey(const ValueKey('android-update-whats-new-button')),
      findsNothing,
    );
    expect(find.text('Hay una nueva versión de Vinabike ERP.'), findsOneWidget);
    expect(find.text('Actualizar'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _FakeAndroidUpdateService extends AndroidUpdateService {
  final AndroidReleaseManifest release;
  var installCalls = 0;

  _FakeAndroidUpdateService(this.release);

  @override
  bool get isSupported => true;

  @override
  bool get isChecking => false;

  @override
  bool get isDownloading => false;

  @override
  AndroidReleaseManifest? get availableUpdate => release;

  @override
  String? get errorMessage => null;

  @override
  String? get statusMessage => null;

  @override
  Future<void> checkForUpdate({bool force = false}) async {}

  @override
  Future<void> installAvailableUpdate() async {
    installCalls += 1;
  }

  @override
  void dismissAvailableUpdate() {}
}
