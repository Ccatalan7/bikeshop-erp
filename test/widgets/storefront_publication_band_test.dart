import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/website/models/storefront_publication_status.dart';
import 'package:vinabike_erp/modules/website/models/website_seo_center_models.dart';
import 'package:vinabike_erp/modules/website/widgets/storefront_publication_band.dart';

/// Behavioural contract of the Editor → build → deploy stage band.
///
/// The band is operational state only. It must honor the mandated
/// presentational precedence, it may only say "Publicado y verificado" when
/// the ledger success matches the live release exactly, it never offers a
/// blind retry for an ambiguous dispatch, and it never leaks a raw server
/// error message.
void main() {
  const requestUuid = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
  const failureUuid = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
  final shaOwner = 'a' * 64;
  final shaBuild = 'b' * 64;
  final shaManifest = 'c' * 64;
  const runUrl = 'https://github.com/Ccatalan7/bikeshop-erp/actions/runs/12345';

  Map<String, Object?> baseJson({
    bool supported = true,
    bool configured = true,
    bool dispatchEnabled = true,
    int desired = 7,
    int published = 7,
    String? requestState,
    bool canRetry = false,
    Map<String, Object?>? queue,
    Map<String, Object?>? active,
    Map<String, Object?>? lastSuccess,
    Map<String, Object?>? latestFailure,
  }) {
    return {
      'supported': supported,
      'configured': configured,
      'dispatch_enabled': dispatchEnabled,
      'desired_revision': desired,
      'last_published_revision': published,
      'request_state': requestState,
      'request_id': requestUuid,
      'last_published_request_id': lastSuccess == null ? '' : requestUuid,
      'can_retry': canRetry,
      'status_message': 'server copy in english',
      'target_key': 'vinabike-store',
      'expected_store_origin': 'https://vinabike.cl',
      'expected_firebase_origin': 'https://vinabike-store.web.app',
      'last_owner_change_at': '2026-07-29T10:00:00Z',
      'queue': queue,
      'active': active,
      'last_success': lastSuccess,
      'latest_failure': latestFailure,
    };
  }

  Map<String, Object?> successJson({int revision = 7}) => {
        'request_id': requestUuid,
        'attempt_id': failureUuid,
        'published_revision': revision,
        'github_run_id': '12345',
        'github_run_attempt': 1,
        'github_sha': 'deadbeef',
        'github_run_url': runUrl,
        'owner_source_sha256': shaOwner,
        'build_input_sha256': shaBuild,
        'release_manifest_sha256': shaManifest,
        'release_built_at': '2026-07-29T10:05:00Z',
        'primary_verified_at': '2026-07-29T10:10:00Z',
        'custom_verified_at': '2026-07-29T10:11:00Z',
        'completed_at': '2026-07-29T10:12:00Z',
      };

  Map<String, Object?> failureJson({String state = 'failed'}) => {
        'request_id': failureUuid,
        'attempt_id': requestUuid,
        'state': state,
        'requested_revision': 8,
        'attempt_no': 3,
        'failure_stage': 'build',
        'error_class': 'build_failed',
        'error_message': 'raw server stack boom',
        'finished_at': '2026-07-29T11:00:00Z',
      };

  StorefrontPublicationStatus status(Map<String, Object?> json) =>
      StorefrontPublicationStatus.fromJson(json);

  WebsiteSeoReleaseArtifactEvidence release({
    String? overrideOwnerSha,
    int ownerRevision = 7,
  }) {
    return WebsiteSeoReleaseArtifactEvidence.fromJson({
      'url': 'https://vinabike.cl/release.json',
      'deployValid': true,
      'documentValid': true,
      'commit': 'deadbeef',
      'run': '12345',
      'builtAt': '2026-07-29T10:05:00Z',
      'target': 'store',
      'source': 'github-actions',
      'dirty': false,
      'publicationTracked': true,
      'publicationValid': true,
      'publication': {
        'requestId': requestUuid,
        'ownerRevision': ownerRevision,
        'ownerSourceSha256': overrideOwnerSha ?? shaOwner,
        'buildInputSha256': shaBuild,
      },
    });
  }

  Future<void> pumpBand(
    WidgetTester tester, {
    StorefrontPublicationStatus? bandStatus,
    WebsiteSeoReleaseArtifactEvidence? liveRelease,
    String? notice,
    VoidCallback? onRetry,
    VoidCallback? onRefresh,
    Future<void> Function(Uri url)? onOpenRun,
    bool provideOpenRun = true,
    double width = 1400,
    double textScale = 1.0,
  }) async {
    tester.view.physicalSize = Size(width, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(
            size: Size(width, 2000),
            textScaler: TextScaler.linear(textScale),
          ),
          child: Scaffold(
            body: SingleChildScrollView(
              child: SizedBox(
                width: width,
                child: StorefrontPublicationBand(
                  status: bandStatus,
                  release: liveRelease,
                  isBusy: false,
                  notice: notice,
                  onRetry: onRetry ?? () {},
                  onRefreshStatus: onRefresh ?? () {},
                  onOpenRun: provideOpenRun ? onOpenRun ?? (_) async {} : null,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('presentational state matrix', () {
    testWidgets('readFailed offers a status refresh, never a retry',
        (tester) async {
      var refreshed = false;
      await pumpBand(
        tester,
        bandStatus: const StorefrontPublicationStatus.readFailure(
          statusMessage: 'transport down',
        ),
        onRefresh: () => refreshed = true,
      );

      expect(
        find.text('No se pudo consultar el estado de publicación.'),
        findsOneWidget,
      );
      expect(find.text('Reintentar publicación'), findsNothing);
      await tester.tap(find.text('Actualizar estado'));
      expect(refreshed, isTrue);
    });

    testWidgets('unsupported and notConfigured are distinct honest states',
        (tester) async {
      await pumpBand(tester, bandStatus: status({'supported': false}));
      expect(
        find.text('La publicación automática no está soportada.'),
        findsOneWidget,
      );

      await pumpBand(
        tester,
        bandStatus: status(baseJson(configured: false)),
      );
      expect(
        find.text('Publicación automática no disponible en esta tienda.'),
        findsOneWidget,
      );
    });

    testWidgets('no editorial revision never reads as rev. 0', (tester) async {
      await pumpBand(
        tester,
        bandStatus: status(baseJson(desired: 0, published: 0)),
      );
      expect(find.text('Sin revisión editorial que publicar.'), findsOneWidget);
      expect(find.textContaining('rev. 0'), findsNothing);
    });

    testWidgets('disabled automation is stated as its own honest chip',
        (tester) async {
      await pumpBand(
        tester,
        bandStatus: status(
          baseJson(desired: 0, published: 0, dispatchEnabled: false),
        ),
      );
      expect(find.text('Automatización desactivada'), findsOneWidget);
      expect(find.text('Sin revisión editorial que publicar.'), findsOneWidget);
    });

    testWidgets('a notice without facts never renders an empty disclosure',
        (tester) async {
      await pumpBand(
        tester,
        bandStatus: status(baseJson(desired: 0, published: 0)),
        notice: 'No pudimos abrir el run. Inténtalo nuevamente.',
      );

      expect(
        find.text('No pudimos abrir el run. Inténtalo nuevamente.'),
        findsOneWidget,
      );
      expect(find.text('Ver detalle'), findsNothing);
    });

    testWidgets('queued shows revision and coalesced changes', (tester) async {
      await pumpBand(
        tester,
        bandStatus: status(
          baseJson(
            desired: 3,
            published: 2,
            requestState: 'queued',
            queue: {
              'request_id': requestUuid,
              'state': 'queued',
              'requested_revision': 3,
              'coalesced_count': 4,
              'available_at': '2026-07-29T12:00:00Z',
            },
          ),
        ),
      );
      // Queue facts live in the supporting line, visible without disclosure.
      expect(find.text('Cambios en cola · rev. 3'), findsOneWidget);
      expect(find.textContaining('4 cambios agrupados'), findsOneWidget);
    });

    testWidgets('dispatching, dispatched, running and sealed each read clearly',
        (tester) async {
      final expectations = {
        'dispatching': 'Despachando la publicación…',
        'dispatched': 'Despacho confirmado · esperando la ejecución',
        'running': 'Publicando · rev. 5 en ejecución',
        'sealed': 'Build sellado · verificando los orígenes publicados',
      };
      for (final entry in expectations.entries) {
        await pumpBand(
          tester,
          bandStatus: status(
            baseJson(
              desired: 5,
              published: 4,
              requestState: entry.key,
              active: {
                'request_id': requestUuid,
                'state': entry.key,
                'requested_revision': 5,
                'attempt_no': 1,
                'github_run_url': runUrl,
              },
            ),
          ),
        );
        expect(find.text(entry.value), findsOneWidget, reason: entry.key);
      }
    });

    testWidgets(
        'an ambiguous dispatch outranks an old failure and never retries '
        'blindly', (tester) async {
      var retried = false;
      await pumpBand(
        tester,
        bandStatus: status(
          baseJson(
            desired: 8,
            published: 7,
            requestState: 'dispatch_unknown',
            canRetry: true,
            active: {
              'request_id': requestUuid,
              'state': 'dispatch_unknown',
              'requested_revision': 8,
            },
            latestFailure: failureJson(),
          ),
        ),
        onRetry: () => retried = true,
      );

      expect(
        find.text('Despacho sin confirmación de GitHub'),
        findsOneWidget,
      );
      expect(find.text('La publicación falló'), findsNothing);
      expect(find.text('Reintentar publicación'), findsNothing);
      expect(retried, isFalse);
    });

    testWidgets(
        'a current failure surfaces stage and class, never the raw '
        'server message', (tester) async {
      await pumpBand(
        tester,
        bandStatus: status(
          baseJson(
            desired: 8,
            published: 7,
            requestState: 'failed',
            canRetry: true,
            latestFailure: failureJson(),
          ),
        ),
      );

      expect(find.text('La publicación falló'), findsOneWidget);
      await tester.tap(find.text('Ver detalle'));
      await tester.pumpAndSettle();
      expect(find.text('Etapa: build'), findsOneWidget);
      expect(find.text('Clase: build_failed'), findsOneWidget);
      expect(find.textContaining('raw server stack boom'), findsNothing);
      expect(find.text('Reintentar publicación'), findsOneWidget);
    });

    testWidgets('dead-letter reads as stopped and still allows the retry',
        (tester) async {
      await pumpBand(
        tester,
        bandStatus: status(
          baseJson(
            desired: 8,
            published: 7,
            requestState: 'dead_letter',
            canRetry: true,
            latestFailure: failureJson(state: 'dead_letter'),
          ),
        ),
      );
      expect(
        find.text('Publicación detenida tras varios intentos'),
        findsOneWidget,
      );
      expect(find.text('Reintentar publicación'), findsOneWidget);
    });

    testWidgets('retry is absent without canRetry', (tester) async {
      await pumpBand(
        tester,
        bandStatus: status(
          baseJson(
            desired: 8,
            published: 7,
            requestState: 'failed',
            canRetry: false,
            latestFailure: failureJson(),
          ),
        ),
      );
      expect(find.text('Reintentar publicación'), findsNothing);
    });

    testWidgets('stale changes outrank a previous verified success',
        (tester) async {
      await pumpBand(
        tester,
        bandStatus: status(
          baseJson(desired: 9, published: 7, lastSuccess: successJson()),
        ),
        liveRelease: release(),
      );

      expect(
        find.text('Cambios sin publicar · rev. 9 pendiente'),
        findsOneWidget,
      );
      expect(find.textContaining('Publicado y verificado'), findsNothing);
      await tester.tap(find.text('Ver detalle'));
      await tester.pumpAndSettle();
      // The previous live-verified publication survives as an honest fact.
      expect(
        find.textContaining('El sitio muestra la rev. 7 verificada'),
        findsOneWidget,
      );
    });

    testWidgets(
        'published-and-verified exists only with the exact live correlation',
        (tester) async {
      await pumpBand(
        tester,
        bandStatus: status(baseJson(lastSuccess: successJson())),
        liveRelease: release(),
      );
      expect(
        find.text('Publicado y verificado · rev. 7'),
        findsOneWidget,
      );
      expect(find.text('Ver run'), findsOneWidget);
    });

    testWidgets('a ledger success without a live release is inconclusive',
        (tester) async {
      await pumpBand(
        tester,
        bandStatus: status(baseJson(lastSuccess: successJson())),
        liveRelease: null,
      );
      expect(
        find.text('Éxito registrado · sin verificación en vivo'),
        findsOneWidget,
      );
      expect(find.textContaining('Publicado y verificado'), findsNothing);
    });

    testWidgets('a hash mismatch against the live release is inconclusive',
        (tester) async {
      await pumpBand(
        tester,
        bandStatus: status(baseJson(lastSuccess: successJson())),
        liveRelease: release(overrideOwnerSha: 'd' * 64),
      );
      expect(
        find.text('Éxito registrado · sin verificación en vivo'),
        findsOneWidget,
      );
      expect(find.textContaining('Publicado y verificado'), findsNothing);
    });
  });

  group('run link safety', () {
    testWidgets('only an exact public GitHub Actions run URL renders a link',
        (tester) async {
      for (final bad in const [
        'http://github.com/x/y/actions/runs/1',
        'https://evil.example/actions/runs/1',
        'https://api.github.com/x/y/actions/runs/1',
        'https://status.github.com/x/y/actions/runs/1',
        'https://github.com.evil.example/x/y/actions/runs/1',
        'https://user@github.com/x/y/actions/runs/1',
        'https://github.com:444/x/y/actions/runs/1',
        'https://github.com/x/y/issues/1',
        'https://github.com/x/y/actions/runs/not-a-number',
        'https://github.com/x/y/actions/runs/1?attempt=2',
        'https://github.com/x/y/actions/runs/1#details',
        '',
      ]) {
        await pumpBand(
          tester,
          bandStatus: status(
            baseJson(
              desired: 5,
              published: 4,
              requestState: 'running',
              active: {
                'request_id': requestUuid,
                'state': 'running',
                'requested_revision': 5,
                'github_run_url': bad,
              },
            ),
          ),
        );
        expect(find.text('Ver run'), findsNothing, reason: 'url: $bad');
      }
    });

    testWidgets('a failure renders no fabricated run link', (tester) async {
      await pumpBand(
        tester,
        bandStatus: status(
          baseJson(
            desired: 8,
            published: 7,
            requestState: 'failed',
            canRetry: true,
            latestFailure: failureJson(),
          ),
        ),
      );
      expect(find.text('Ver run'), findsNothing);
    });

    testWidgets('a valid run URL opens through the injected launcher',
        (tester) async {
      Uri? opened;
      await pumpBand(
        tester,
        bandStatus: status(baseJson(lastSuccess: successJson())),
        liveRelease: release(),
        onOpenRun: (uri) async => opened = uri,
      );
      await tester.tap(find.text('Ver run'));
      expect(opened, Uri.parse(runUrl));
    });

    testWidgets('a run URL without an opening capability renders no action',
        (tester) async {
      await pumpBand(
        tester,
        bandStatus: status(baseJson(lastSuccess: successJson())),
        liveRelease: release(),
        provideOpenRun: false,
      );

      expect(find.text('Ver run'), findsNothing);
    });
  });

  group('accessibility and responsive composition', () {
    testWidgets(
        'state is announced through a live region and the disclosure '
        'is a real expandable button', (tester) async {
      await pumpBand(
        tester,
        bandStatus: status(
          baseJson(
            desired: 8,
            published: 7,
            requestState: 'failed',
            canRetry: true,
            latestFailure: failureJson(),
          ),
        ),
      );

      expect(
        find.bySemanticsLabel(RegExp('Estado de publicación:.*falló')),
        findsOneWidget,
      );

      expect(
        tester.getSemantics(find.text('Ver detalle')),
        matchesSemantics(
          isButton: true,
          hasExpandedState: true,
          isExpanded: false,
          hasTapAction: true,
          isFocusable: true,
          hasFocusAction: true,
          label: 'Ver detalle',
        ),
      );

      await tester.tap(find.text('Ver detalle'));
      await tester.pumpAndSettle();
      expect(find.text('Ocultar detalle'), findsOneWidget);
    });

    testWidgets('actions honor the 48 px target', (tester) async {
      await pumpBand(
        tester,
        bandStatus: status(
          baseJson(
            desired: 8,
            published: 7,
            requestState: 'failed',
            canRetry: true,
            latestFailure: failureJson(),
          ),
        ),
      );

      final retry = find.ancestor(
        of: find.text('Reintentar publicación'),
        matching: find.byWidgetPredicate((w) => w is FilledButton),
      );
      expect(tester.getSize(retry).height, greaterThanOrEqualTo(48));

      final disclosure = find.ancestor(
        of: find.text('Ver detalle'),
        matching: find.byType(InkWell),
      );
      expect(tester.getSize(disclosure).height, greaterThanOrEqualTo(48));
    });

    for (final width in const [390.0, 834.0, 1180.0, 1400.0]) {
      testWidgets('lays out at ${width.toInt()} px without overflow',
          (tester) async {
        await pumpBand(
          tester,
          width: width,
          bandStatus: status(
            baseJson(
              desired: 8,
              published: 7,
              requestState: 'failed',
              canRetry: true,
              latestFailure: failureJson(),
            ),
          ),
          notice: 'El reintento no está disponible: espera cinco minutos '
              'antes de volver a intentarlo desde esta cuenta.',
        );
        expect(
          tester.getSize(find.byType(StorefrontPublicationBand)).width,
          width,
        );
        await tester.tap(find.text('Ver detalle'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('survives large text scale without overflow', (tester) async {
      await pumpBand(
        tester,
        width: 390,
        textScale: 1.4,
        bandStatus: status(
          baseJson(
            desired: 8,
            published: 7,
            requestState: 'failed',
            canRetry: true,
            latestFailure: failureJson(),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('shared attention verdict', () {
    test(
        'failure, dead-letter, stale, inconclusive and readFailed demand '
        'attention; working and verified do not', () {
      bool attention(Map<String, Object?> json,
          {WebsiteSeoReleaseArtifactEvidence? liveRelease}) {
        return StorefrontPublicationPresentation.resolve(
          status: status(json),
          release: liveRelease,
        ).needsAttention;
      }

      expect(
        attention(baseJson(
          desired: 8,
          published: 7,
          requestState: 'failed',
          latestFailure: failureJson(),
        )),
        isTrue,
      );
      expect(
        attention(baseJson(desired: 9, published: 7)),
        isTrue,
        reason: 'stale',
      );
      expect(
        attention(baseJson(lastSuccess: successJson())),
        isTrue,
        reason: 'inconclusive without live release',
      );
      expect(
        StorefrontPublicationPresentation.resolve(
          status: const StorefrontPublicationStatus.readFailure(
            statusMessage: 'down',
          ),
        ).needsAttention,
        isTrue,
      );
      expect(
        attention(
          baseJson(lastSuccess: successJson()),
          liveRelease: release(),
        ),
        isFalse,
        reason: 'verified success',
      );
      expect(
        attention(baseJson(
          desired: 5,
          published: 4,
          requestState: 'running',
          active: {
            'request_id': requestUuid,
            'state': 'running',
            'requested_revision': 5,
          },
        )),
        isFalse,
        reason: 'working',
      );
    });
  });
}
