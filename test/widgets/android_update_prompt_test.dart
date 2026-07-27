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
    Size size = const Size(384, 824),
    double textScale = 1,
    double bottomInset = 0,
    String? errorMessage,
    int consecutiveCheckFailures = 0,
    bool isDownloading = false,
    double? downloadProgress,
    String? statusMessage,
    bool installThrows = false,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final service = _FakeAndroidUpdateService(
      release,
      errorMessage: errorMessage,
      consecutiveCheckFailures: consecutiveCheckFailures,
      isDownloading: isDownloading,
      downloadProgress: downloadProgress,
      statusMessage: statusMessage,
      installThrows: installThrows,
    );
    addTearDown(service.dispose);
    await tester.pumpWidget(
      ChangeNotifierProvider<AndroidUpdateService>.value(
        value: service,
        child: MaterialApp(
          builder: (context, child) {
            final mediaQuery = MediaQuery.of(context);
            return MediaQuery(
              data: mediaQuery.copyWith(
                padding: EdgeInsets.only(bottom: bottomInset),
                textScaler: TextScaler.linear(textScale),
              ),
              child: child!,
            );
          },
          home: const Scaffold(
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
    'idle update stays compact and opens full notes only on request',
    (tester) async {
      await pumpPrompt(tester, release: release(notes: releaseNotes()));

      final prompt = find.byKey(
        const ValueKey('android-update-ready-prompt'),
      );
      final whatsNew = find.byKey(
        const ValueKey('android-update-whats-new-button'),
      );
      final install = find.byKey(
        const ValueKey('android-update-primary-button'),
      );
      final dismiss = find.byKey(
        const ValueKey('android-update-dismiss-button'),
      );
      expect(prompt, findsOneWidget);
      expect(whatsNew, findsOneWidget);
      expect(install, findsOneWidget);
      expect(dismiss, findsOneWidget);
      expect(tester.widget(whatsNew), isA<TextButton>());
      expect(tester.widget(install), isA<FilledButton>());
      expect(find.text('Versión 1.0.2'), findsOneWidget);
      expect(find.text('Instalar'), findsOneWidget);
      expect(
        find.text('Mejoramos tareas cotidianas del sistema.'),
        findsNothing,
      );
      expect(tester.getSize(prompt).height, lessThanOrEqualTo(84));
      expect(tester.getSize(whatsNew).height, greaterThanOrEqualTo(48));
      expect(tester.getSize(install).height, greaterThanOrEqualTo(48));
      expect(tester.getSize(dismiss).height, greaterThanOrEqualTo(48));
      expect(tester.getSize(dismiss).width, greaterThanOrEqualTo(48));
      expect(tester.takeException(), isNull);

      await tester.tap(whatsNew);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        find.byKey(const ValueKey('desktop-release-notes-dialog')),
        findsOneWidget,
      );
      expect(find.text('Novedades de esta actualización'), findsOneWidget);
      expect(
        find.text('Mejoramos tareas cotidianas del sistema.'),
        findsOneWidget,
      );
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

  testWidgets('keeps the same compact prompt when notes are absent',
      (tester) async {
    await pumpPrompt(
      tester,
      release: release(notes: 'Legacy notes are intentionally ignored.'),
    );

    expect(
      find.byKey(const ValueKey('android-update-whats-new-button')),
      findsNothing,
    );
    expect(find.text('Versión 1.0.2'), findsOneWidget);
    expect(
      find.text('Hay una nueva versión de Vinabike ERP.'),
      findsNothing,
    );
    expect(find.text('Instalar'), findsOneWidget);
    expect(
      tester
          .getSize(
            find.byKey(const ValueKey('android-update-ready-prompt')),
          )
          .height,
      lessThanOrEqualTo(84),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('install and dismiss actions keep their canonical callbacks',
      (tester) async {
    final service = await pumpPrompt(
      tester,
      release: release(notes: releaseNotes()),
    );

    await tester.tap(
      find.byKey(const ValueKey('android-update-primary-button')),
    );
    await tester.pump();
    expect(service.installCalls, 1);

    await tester.tap(
      find.byKey(const ValueKey('android-update-dismiss-button')),
    );
    await tester.pump();
    expect(service.dismissCalls, 1);
    expect(
      find.byKey(const ValueKey('android-update-ready-prompt')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('download progress expands only while the action is active',
      (tester) async {
    await pumpPrompt(
      tester,
      release: release(notes: releaseNotes()),
      isDownloading: true,
      downloadProgress: 0.42,
      statusMessage: 'Descargando actualización…',
    );

    final install = find.byKey(
      const ValueKey('android-update-primary-button'),
    );
    final progress = tester.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    );
    expect(find.text('Descargando…'), findsOneWidget);
    expect(tester.widget<FilledButton>(install).onPressed, isNull);
    expect(
      find.byKey(const ValueKey('android-update-dismiss-button')),
      findsNothing,
    );
    expect(progress.value, 0.42);
    expect(tester.takeException(), isNull);
  });

  testWidgets('installation failure stays recoverable in the same prompt',
      (tester) async {
    final service = await pumpPrompt(
      tester,
      release: release(notes: releaseNotes()),
      installThrows: true,
    );

    await tester.tap(
      find.byKey(const ValueKey('android-update-primary-button')),
    );
    await tester.pump();

    expect(
      find.text('No se pudo preparar la actualización.'),
      findsOneWidget,
    );
    expect(find.text('Reintentar'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);

    await tester.tap(
      find.byKey(const ValueKey('android-update-primary-button')),
    );
    await tester.pump();
    expect(service.installCalls, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('stays bounded across the responsive width matrix',
      (tester) async {
    await pumpPrompt(tester, release: release(notes: releaseNotes()));

    const widths = <double>[384, 599, 600, 899, 900, 1440];
    for (final width in widths) {
      tester.view.physicalSize = Size(width, width == 1440 ? 900 : 824);
      await tester.pump();

      final prompt = find.byKey(
        const ValueKey('android-update-ready-prompt'),
      );
      expect(tester.getSize(prompt).width, lessThanOrEqualTo(440));
      expect(
        tester
            .getSize(
              find.byKey(
                const ValueKey('android-update-whats-new-button'),
              ),
            )
            .height,
        greaterThanOrEqualTo(48),
      );
      expect(
        tester
            .getSize(
              find.byKey(
                const ValueKey('android-update-primary-button'),
              ),
            )
            .height,
        greaterThanOrEqualTo(48),
      );
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('adapts to larger text and the bottom safe area', (tester) async {
    const viewport = Size(384, 824);
    await pumpPrompt(
      tester,
      release: release(notes: releaseNotes()),
      size: viewport,
      textScale: 1.5,
      bottomInset: 24,
    );

    final prompt = find.byKey(
      const ValueKey('android-update-ready-prompt'),
    );
    expect(tester.getSize(prompt).height, lessThan(160));
    expect(
      viewport.height - tester.getBottomRight(prompt).dy,
      greaterThanOrEqualTo(36),
    );
    expect(
      tester
          .getSize(
            find.byKey(const ValueKey('android-update-primary-button')),
          )
          .height,
      greaterThanOrEqualTo(48),
    );
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
  AndroidReleaseManifest? release;
  String? checkError;
  final int checkFailureCount;
  final bool downloadInProgress;
  final double? currentDownloadProgress;
  final String? currentStatusMessage;
  final bool installThrows;
  bool dismissed = false;
  var installCalls = 0;
  var dismissCalls = 0;
  final List<bool> checkForces = [];

  _FakeAndroidUpdateService(
    this.release, {
    String? errorMessage,
    int consecutiveCheckFailures = 0,
    bool isDownloading = false,
    double? downloadProgress,
    String? statusMessage,
    this.installThrows = false,
  })  : checkError = errorMessage,
        checkFailureCount = consecutiveCheckFailures,
        downloadInProgress = isDownloading,
        currentDownloadProgress = downloadProgress,
        currentStatusMessage = statusMessage;

  @override
  bool get isSupported => true;

  @override
  bool get isChecking => false;

  @override
  bool get isDownloading => downloadInProgress;

  @override
  double? get downloadProgress => currentDownloadProgress;

  @override
  AndroidReleaseManifest? get availableUpdate => dismissed ? null : release;

  @override
  String? get errorMessage => checkError;

  @override
  int get consecutiveCheckFailures => checkFailureCount;

  @override
  String? get statusMessage => currentStatusMessage;

  @override
  Future<void> checkForUpdate({bool force = false}) async {
    checkForces.add(force);
  }

  @override
  Future<void> installAvailableUpdate() async {
    installCalls += 1;
    if (installThrows) {
      checkError = 'No se pudo preparar la actualización.';
      notifyListeners();
      throw StateError('Synthetic installation failure.');
    }
  }

  @override
  void dismissAvailableUpdate() {
    dismissCalls += 1;
    dismissed = true;
    notifyListeners();
  }
}
