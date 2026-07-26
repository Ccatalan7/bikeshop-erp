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
    required AndroidReleaseManifest? release,
    String? errorMessage,
    int consecutiveCheckFailures = 0,
  }) async {
    tester.view.physicalSize = const Size(384, 824);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final service = _FakeAndroidUpdateService(
      release,
      errorMessage: errorMessage,
      consecutiveCheckFailures: consecutiveCheckFailures,
    );
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

  testWidgets(
    'checks immediately, only polls in foreground, and rechecks on resume',
    (tester) async {
      final service = await pumpPrompt(
        tester,
        release: release(notes: releaseNotes()),
      );

      expect(service.checkForces, [isTrue]);

      service.checkForces.clear();
      tester.binding.handleAppLifecycleStateChanged(
        AppLifecycleState.paused,
      );
      await tester.pump(const Duration(minutes: 10));
      expect(service.checkForces, isEmpty);

      tester.binding.handleAppLifecycleStateChanged(
        AppLifecycleState.resumed,
      );
      await tester.pump();
      expect(service.checkForces, [isTrue]);

      service.checkForces.clear();
      await tester.pump(const Duration(minutes: 4, seconds: 59));
      expect(service.checkForces, isEmpty);
      await tester.pump(const Duration(seconds: 1));
      expect(service.checkForces, [isTrue]);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'shows a bounded check failure with a 48px retry action',
    (tester) async {
      final service = await pumpPrompt(
        tester,
        release: null,
        errorMessage: 'No se pudo revisar la actualización privada.',
        consecutiveCheckFailures: 1,
      );

      expect(
        find.byKey(const ValueKey('android-update-check-error')),
        findsOneWidget,
      );
      expect(
        find.text('No pudimos comprobar si hay una actualización.'),
        findsOneWidget,
      );
      final retry = find.byKey(
        const ValueKey('android-update-retry-button'),
      );
      expect(retry, findsOneWidget);
      expect(tester.getSize(retry).height, greaterThanOrEqualTo(48));

      service.checkForces.clear();
      await tester.tap(retry);
      await tester.pump();
      expect(service.checkForces, [isTrue]);
      expect(tester.takeException(), isNull);
    },
  );
}

class _FakeAndroidUpdateService extends AndroidUpdateService {
  final AndroidReleaseManifest? release;
  final String? checkError;
  final int checkFailureCount;
  var installCalls = 0;
  final List<bool> checkForces = [];

  _FakeAndroidUpdateService(
    this.release, {
    String? errorMessage,
    int consecutiveCheckFailures = 0,
  })  : checkError = errorMessage,
        checkFailureCount = consecutiveCheckFailures;

  @override
  bool get isSupported => true;

  @override
  bool get isChecking => false;

  @override
  bool get isDownloading => false;

  @override
  AndroidReleaseManifest? get availableUpdate => release;

  @override
  String? get errorMessage => checkError;

  @override
  int get consecutiveCheckFailures => checkFailureCount;

  @override
  String? get statusMessage => null;

  @override
  Future<void> checkForUpdate({bool force = false}) async {
    checkForces.add(force);
  }

  @override
  Future<void> installAvailableUpdate() async {
    installCalls += 1;
  }

  @override
  void dismissAvailableUpdate() {}
}
