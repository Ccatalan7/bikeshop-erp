import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:vinabike_erp/modules/website/models/website_seo_center_models.dart';
import 'package:vinabike_erp/modules/website/pages/seo_settings_page.dart';
import 'package:vinabike_erp/modules/website/services/website_seo_operations_service.dart';
import 'package:vinabike_erp/modules/website/widgets/seo_center_lists.dart';
import 'package:vinabike_erp/modules/website/widgets/seo_google_operations_panel.dart';
import 'package:vinabike_erp/modules/website/widgets/seo_center_scope_rail.dart';
import 'package:vinabike_erp/modules/website/services/storefront_publication_service.dart';
import 'package:vinabike_erp/modules/website/widgets/storefront_publication_band.dart';
import 'package:vinabike_erp/modules/website/widgets/seo_readiness_badge.dart';

/// These tests fix the product rules that the SEO center exists to protect:
///
/// * the three planes stay separate and are never merged into a score;
/// * absent Google evidence never becomes an implied "indexado";
/// * a deliberate owner decision (5 of 133 published collections) reads as
///   scope, never as a deficit; and
/// * an inherited or generated product title reads as provenance, never as a
///   missing field.
void main() {
  const eligible = SeoBadgeState(
    label: 'Elegible',
    tone: SeoBadgeTone.confirmed,
  );
  const included = SeoBadgeState(
    label: 'Incluido',
    tone: SeoBadgeTone.confirmed,
    detail: 'sitemap.xml · build 32404d3',
  );
  const notConsulted = SeoBadgeState(
    label: 'Sin consultar',
    tone: SeoBadgeTone.unknown,
  );
  const notBuilt = SeoBadgeState(
    label: 'Sin evidencia de publicación',
    tone: SeoBadgeTone.unknown,
  );

  Widget host(Widget child, {Size size = const Size(1280, 900)}) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: size.width,
            height: size.height,
            child: child,
          ),
        ),
      ),
    );
  }

  SeoCenterList buildList(
    SeoCenterGroup group, {
    ValueChanged<SeoCenterHandoff>? onHandoff,
    ValueChanged<SeoCenterEntityRow>? onRowSelected,
    bool onlyAttention = false,
  }) {
    return SeoCenterList(
      group: group,
      query: '',
      searchController: TextEditingController(),
      onQueryChanged: (_) {},
      onlyAttention: onlyAttention,
      onOnlyAttentionChanged: (_) {},
      onRowSelected: onRowSelected ?? (_) {},
      onHandoff: onHandoff ?? (_) {},
    );
  }

  group('three planes stay separate', () {
    testWidgets('renders one badge per plane with human wording',
        (tester) async {
      await tester.pumpWidget(
        host(
          const Align(
            alignment: Alignment.topLeft,
            child: SeoReadinessBadgeGroup(
              appEligibility: eligible,
              buildInclusion: included,
              googleIndex: notConsulted,
            ),
          ),
        ),
      );

      expect(find.byType(SeoReadinessBadge), findsNWidgets(3));
      expect(find.text('Elegible'), findsOneWidget);
      expect(find.text('Incluido'), findsOneWidget);
      expect(find.text('Sin consultar'), findsOneWidget);
    });

    testWidgets('never renders a merged score, percentage or progress bar',
        (tester) async {
      await tester.pumpWidget(
        host(
          const Align(
            alignment: Alignment.topLeft,
            child: SeoReadinessBadgeGroup(
              appEligibility: eligible,
              buildInclusion: included,
              googleIndex: notConsulted,
            ),
          ),
        ),
      );

      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.textContaining('%'), findsNothing);
      expect(find.textContaining('Listo para'), findsNothing);
    });

    testWidgets('captions name each owner without promising indexing',
        (tester) async {
      await tester.pumpWidget(
        host(
          const SingleChildScrollView(
            child: SeoReadinessBadgeGroup(
              appEligibility: eligible,
              buildInclusion: included,
              googleIndex: notConsulted,
              showPlaneCaptions: true,
            ),
          ),
        ),
      );

      expect(find.text('Elegibilidad · nuestra app'), findsOneWidget);
      expect(find.text('Publicación · último build'), findsOneWidget);
      expect(find.text('Google · evidencia'), findsOneWidget);
      expect(
        find.textContaining('Google decide si indexa'),
        findsOneWidget,
      );
    });
  });

  group('google evidence', () {
    testWidgets('absent evidence stays unknown and never says indexado',
        (tester) async {
      await tester.pumpWidget(
        host(
          const Align(
            alignment: Alignment.topLeft,
            child: SeoReadinessBadge(state: notConsulted),
          ),
        ),
      );

      expect(find.text('Sin consultar'), findsOneWidget);
      expect(find.text('Indexado'), findsNothing);
      expect(find.text('No indexado'), findsNothing);
      expect(find.byIcon(Icons.help_outline_rounded), findsOneWidget);
    });

    testWidgets('present evidence shows date and origin', (tester) async {
      await tester.pumpWidget(
        host(
          const Align(
            alignment: Alignment.topLeft,
            child: SeoReadinessBadge(
              state: SeoBadgeState(
                label: 'Indexado',
                tone: SeoBadgeTone.confirmed,
                detail: '12 jul 2026 · Search Console',
              ),
            ),
          ),
        ),
      );

      expect(find.text('Indexado'), findsOneWidget);
      expect(find.text('12 jul 2026 · Search Console'), findsOneWidget);
    });
  });

  group('collections read as scope, not as a deficit', () {
    const collections = SeoCenterGroup(
      scope: SeoCenterScope.collections,
      summary: '5 colecciones publicadas por decisión · 128 ocultas.',
      counts: [
        SeoCenterSummaryCount(
          label: 'publicadas',
          value: '5',
          tone: SeoBadgeTone.confirmed,
        ),
        SeoCenterSummaryCount(label: 'ocultas por decisión', value: '128'),
      ],
      rows: [
        SeoCenterEntityRow(
          id: 'cat-empty',
          title: 'Rutas',
          subtitle: '/productos/categoria/rutas',
          appEligibility: SeoBadgeState(
            label: 'No elegible actualmente',
            tone: SeoBadgeTone.attention,
            detail: 'Publicada sin productos elegibles',
          ),
          buildInclusion: notBuilt,
          googleIndex: notConsulted,
          needsAttention: true,
        ),
        SeoCenterEntityRow(
          id: 'cat-hidden',
          title: 'Repuestos internos',
          subtitle: 'Oculta del sitio',
          appEligibility: SeoBadgeState(
            label: 'No elegible',
            tone: SeoBadgeTone.neutral,
            detail: 'Oculta por decisión del catálogo',
          ),
          buildInclusion: SeoBadgeState(
            label: 'No incluida',
            tone: SeoBadgeTone.neutral,
          ),
          googleIndex: notConsulted,
        ),
      ],
    );

    testWidgets('summary states the decision without a completion metric',
        (tester) async {
      await tester.pumpWidget(host(buildList(collections)));
      await tester.pumpAndSettle();

      expect(
        find.text('5 colecciones publicadas por decisión · 128 ocultas.'),
        findsOneWidget,
      );
      expect(find.text('128 ocultas por decisión'), findsOneWidget);
      expect(find.textContaining('%'), findsNothing);
      expect(find.textContaining('falta'), findsNothing);
      expect(find.textContaining('Falta'), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsNothing);
    });

    testWidgets('a hidden collection is neutral, not an error', (tester) async {
      await tester.pumpWidget(host(buildList(collections)));
      await tester.pumpAndSettle();

      final hidden = tester.widget<SeoReadinessBadge>(
        find.ancestor(
          of: find.text('No elegible'),
          matching: find.byType(SeoReadinessBadge),
        ),
      );
      expect(hidden.state.tone, SeoBadgeTone.neutral);
    });

    testWidgets(
        'a published empty collection warns without inventing build evidence',
        (tester) async {
      await tester.pumpWidget(host(buildList(collections)));
      await tester.pumpAndSettle();

      final excluded = tester.widget<SeoReadinessBadge>(
        find.ancestor(
          of: find.text('No elegible actualmente'),
          matching: find.byType(SeoReadinessBadge),
        ),
      );
      expect(excluded.state.tone, SeoBadgeTone.attention);
      expect(excluded.state.tone, isNot(SeoBadgeTone.unknown));
      expect(find.text('Sin evidencia de publicación'), findsWidgets);
    });
  });

  group('product metadata provenance', () {
    testWidgets('no override reads as Heredado, never as missing',
        (tester) async {
      await tester.pumpWidget(
        host(
          SeoCenterDetail(
            row: const SeoCenterEntityRow(
              id: 'p1',
              title: 'Cámara aro 26',
              subtitle: 'SKU AE0037',
              source: SeoBadgeState(
                label: 'Heredado',
                tone: SeoBadgeTone.neutral,
                detail: 'Usa el nombre y la descripción del producto',
              ),
              appEligibility: eligible,
              buildInclusion: included,
              googleIndex: notConsulted,
              facts: [
                SeoCenterFact(label: 'Título efectivo', value: 'Cámara aro 26'),
                SeoCenterFact(
                  label: 'Origen de la descripción',
                  value: 'Generado',
                ),
              ],
            ),
            onHandoff: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Heredado'), findsOneWidget);
      expect(find.text('Generado'), findsOneWidget);
      expect(find.textContaining('faltante'), findsNothing);
      expect(find.textContaining('Falta'), findsNothing);
    });
  });

  group('actions are non-destructive handoffs', () {
    testWidgets('detail exposes only the canonical owner route',
        (tester) async {
      SeoCenterHandoff? received;
      await tester.pumpWidget(
        host(
          SeoCenterDetail(
            row: const SeoCenterEntityRow(
              id: 'page-1',
              title: 'Términos y condiciones',
              subtitle: '/terminos',
              appEligibility: eligible,
              buildInclusion: included,
              googleIndex: notConsulted,
              handoff: SeoCenterHandoff(
                label: 'Abrir en Páginas',
                route: '/website/pages',
                helper: 'Estructura > Páginas',
              ),
            ),
            onHandoff: (handoff) => received = handoff,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.delete_outline), findsNothing);
      expect(find.text('Eliminar'), findsNothing);
      expect(find.byType(TextField), findsNothing);

      await tester.tap(find.text('Abrir en Páginas'));
      await tester.pumpAndSettle();
      expect(received?.route, '/website/pages');
    });
  });

  group('honest degraded states', () {
    testWidgets('a partial read failure is visible and keeps states unknown',
        (tester) async {
      const group = SeoCenterGroup(
        scope: SeoCenterScope.pages,
        summary: '8 páginas.',
        partialError:
            'No se pudo leer la evidencia del último build publicado. '
            'La publicación aparece como «Sin evidencia».',
        rows: [
          SeoCenterEntityRow(
            id: 'inicio',
            title: 'Inicio',
            subtitle: '/',
            appEligibility: eligible,
            buildInclusion: SeoBadgeState(
              label: 'Sin evidencia de publicación',
              tone: SeoBadgeTone.unknown,
            ),
            googleIndex: notConsulted,
          ),
        ],
      );

      await tester.pumpWidget(host(buildList(group)));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('No se pudo leer la evidencia'),
        findsOneWidget,
      );
      final buildBadge = tester.widget<SeoReadinessBadge>(
        find.ancestor(
          of: find.text('Sin evidencia de publicación'),
          matching: find.byType(SeoReadinessBadge),
        ),
      );
      expect(buildBadge.state.tone, SeoBadgeTone.unknown);
    });
  });

  group('responsive composition', () {
    const row = SeoCenterEntityRow(
      id: 'r1',
      title: 'Cámara aro 26 Kenda',
      subtitle: '/productos/camara-aro-26-kenda/AE0037',
      appEligibility: eligible,
      buildInclusion: included,
      googleIndex: notConsulted,
      handoff: SeoCenterHandoff(
        label: 'Abrir producto',
        route: '/inventory/products/p1/edit',
      ),
    );

    testWidgets('row lays out in one line above the stack width',
        (tester) async {
      await tester.pumpWidget(
        host(
          SeoCenterRowTile(row: row, onTap: () {}),
          size: const Size(900, 400),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.chevron_right_rounded), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('row stacks on phone width without horizontal scroll',
        (tester) async {
      tester.view.physicalSize = const Size(390, 780);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        host(
          SeoCenterRowTile(row: row, onTap: () {}),
          size: const Size(390, 780),
        ),
      );
      await tester.pumpAndSettle();

      // The stacked composition drops the trailing chevron and keeps every
      // badge reachable without panning.
      expect(find.byIcon(Icons.chevron_right_rounded), findsNothing);
      expect(find.byType(SeoReadinessBadge), findsNWidgets(3));
      final horizontalScrollables = find
          .byWidgetPredicate(
            (widget) => widget is Scrollable && widget.axis == Axis.horizontal,
          )
          .evaluate();
      expect(horizontalScrollables, isEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets('scope rail switches to a wrapping selector', (tester) async {
      await tester.pumpWidget(
        host(
          SeoCenterScopeRail(
            selected: SeoCenterScope.pages,
            onSelected: (_) {},
            layout: SeoCenterScopeRailLayout.horizontal,
          ),
          size: const Size(390, 400),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(Wrap), findsWidgets);
      expect(find.text('Sitio'), findsOneWidget);
      expect(find.text('Páginas'), findsOneWidget);
      expect(find.text('Productos'), findsOneWidget);
      expect(find.text('Colecciones'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('collapsed copy announces state and keeps a 44px target',
        (tester) async {
      await tester.pumpWidget(
        host(
          const SeoCollapsibleText(
            text: 'Esta explicación es deliberadamente extensa para ocupar más '
                'de dos líneas en un ancho compacto y habilitar el control.',
          ),
          size: const Size(280, 220),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.bySemanticsLabel('Ver más'), findsOneWidget);
      final control = find.ancestor(
        of: find.text('Ver más'),
        matching: find.byType(InkWell),
      );
      expect(tester.getSize(control).height, greaterThanOrEqualTo(44));

      await tester.tap(find.bySemanticsLabel('Ver más'));
      await tester.pumpAndSettle();

      expect(find.bySemanticsLabel('Ver menos'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('SeoSettingsPage integration', () {
    WebsiteSeoEffectiveValue value(
      String text,
      WebsiteSeoValueSource source, {
      WebsiteSeoEntityKind ownerKind = WebsiteSeoEntityKind.site,
      String ownerId = 'site',
    }) {
      return WebsiteSeoEffectiveValue(
        value: text,
        source: source,
        ownerKind: ownerKind,
        ownerId: ownerId,
      );
    }

    WebsiteSeoEffectiveMetadata metadata({
      required WebsiteSeoEffectiveValue title,
      WebsiteSeoEffectiveValue? description,
      WebsiteSeoEffectiveValue? imageUrl,
      WebsiteSeoEffectiveValue? keywords,
    }) {
      final inherited =
          value('Heredado del sitio', WebsiteSeoValueSource.inherited);
      return WebsiteSeoEffectiveMetadata(
        title: title,
        description: description ?? inherited,
        imageUrl: imageUrl ?? inherited,
        keywords: keywords ?? inherited,
      );
    }

    WebsiteSeoEntityProjection entity({
      required WebsiteSeoEntityKind kind,
      required String id,
      required String label,
      required String canonicalPath,
      WebsiteSeoValueSource titleSource = WebsiteSeoValueSource.explicit,
      List<WebsiteSeoAppEligibilityIssue> issues = const [],
    }) {
      return WebsiteSeoEntityProjection(
        kind: kind,
        id: id,
        label: label,
        canonicalPath: canonicalPath,
        metadata: metadata(
          title: value(label, titleSource, ownerKind: kind, ownerId: id),
        ),
        appEligibility: WebsiteSeoAppEligibilityEvidence(issues: issues),
        buildEvidence: const WebsiteSeoBuildEvidence.unknown(),
        googleEvidence: const WebsiteSeoGoogleEvidence.unknown(),
      );
    }

    WebsiteSeoCenterProjection projection({
      WebsiteSeoSiteStatus? status,
      List<WebsiteSeoEntityProjection>? collections,
    }) {
      final observedAt = DateTime.utc(2026, 7, 27, 3, 33);
      return WebsiteSeoCenterProjection(
        generatedAt: observedAt,
        siteStatus: status ??
            WebsiteSeoSiteStatus.unavailable(
              observedAt: observedAt,
              error: 'site_status no está desplegada.',
            ),
        site: entity(
          kind: WebsiteSeoEntityKind.site,
          id: 'site',
          label: 'Viñabike',
          canonicalPath: '/',
        ),
        pages: [
          entity(
            kind: WebsiteSeoEntityKind.page,
            id: 'page-terminos',
            label: 'Términos y condiciones',
            canonicalPath: '/terminos',
          ),
        ],
        products: [
          entity(
            kind: WebsiteSeoEntityKind.product,
            id: 'prod-1',
            label: 'Cámara aro 26',
            canonicalPath: '/productos/camara-aro-26/AE0037',
            titleSource: WebsiteSeoValueSource.ownerFallback,
          ),
        ],
        collections: collections ??
            [
              entity(
                kind: WebsiteSeoEntityKind.collection,
                id: 'cat-1',
                label: 'Rutas',
                canonicalPath: '/productos/categoria/rutas',
                issues: const [
                  WebsiteSeoAppEligibilityIssue.noEligibleContent,
                ],
              ),
            ],
        categoryOwnerTotal: 133,
      );
    }

    Future<GoRouter> pumpPage(
      WidgetTester tester, {
      required WebsiteSeoCenterProjection data,
      Size size = const Size(1400, 1000),
    }) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final router = GoRouter(
        initialLocation: '/website/seo',
        routes: [
          GoRoute(
            path: '/website/seo',
            builder: (context, state) => SeoSettingsPage(
              embedded: true,
              loadProjection: (_) async => data,
            ),
          ),
          for (final path in const [
            '/website/settings',
            '/website/pages',
            '/website/product-visibility',
            '/inventory/products/:id/edit',
          ])
            GoRoute(
              path: path,
              // Echo the resolved location so a test can assert the exact
              // route the SEO center pushed, not just that something opened.
              builder: (context, state) => Scaffold(
                body: Text('owner:${state.uri}'),
              ),
            ),
        ],
      );

      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();
      return router;
    }

    String location(GoRouter router) =>
        router.routerDelegate.currentConfiguration.uri.toString();

    /// Scrolls a target into view before tapping. A handoff button that sits
    /// below the fold must still be reachable, and a silent off-viewport tap
    /// would make this test pass for the wrong reason.
    Future<void> tapVisible(WidgetTester tester, Finder finder) async {
      final insideScrollable = find
          .ancestor(of: finder, matching: find.byType(Scrollable))
          .evaluate()
          .isNotEmpty;
      if (insideScrollable) {
        await tester.ensureVisible(finder);
        await tester.pumpAndSettle();
      }
      await tester.tap(finder);
      await tester.pumpAndSettle();
    }

    testWidgets('opens on the site scope and never offers a save action',
        (tester) async {
      await pumpPage(tester, data: projection());

      expect(find.text('SEO y visibilidad'), findsOneWidget);
      expect(find.text('Guardar'), findsNothing);
      expect(find.byType(Switch), findsNothing);
      expect(find.byType(DataTable), findsNothing);
      expect(find.byIcon(Icons.delete_outline), findsNothing);
      expect(find.textContaining('Listo para Google Merchant'), findsNothing);
      expect(find.byType(Scaffold), findsNothing);
      expect(find.byType(AppBar), findsNothing);
      expect(find.byType(Card), findsNothing);
    });

    /// Brings a lazily built sliver row into view.
    ///
    /// The site scope leads with the Google operations panel, so its metadata
    /// rows are below the fold and not yet built; `ensureVisible` only works
    /// on an element that already exists.
    Future<void> scrollTo(WidgetTester tester, Finder finder) async {
      if (finder.evaluate().isNotEmpty) return;
      await tester.scrollUntilVisible(
        finder,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
    }

    testWidgets('site metadata is read-only with an owner handoff',
        (tester) async {
      final router = await pumpPage(tester, data: projection());

      await scrollTo(tester, find.text('Título base'));
      expect(find.text('Título base'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);

      await tapVisible(tester, find.text('Abrir Configuración del sitio'));
      expect(
        find.text('owner:/website/settings?section=seo'),
        findsOneWidget,
      );
      // `push` keeps the SEO center underneath instead of replacing it.
      expect(router.canPop(), isTrue);
    });

    testWidgets('a published empty collection warns instead of failing',
        (tester) async {
      await pumpPage(tester, data: projection());

      await tapVisible(tester, find.text('Colecciones'));

      expect(find.text('No elegible actualmente'), findsOneWidget);
      expect(find.textContaining('1 de 133 categorías'), findsOneWidget);
      expect(find.text('1 publicadas'), findsOneWidget);
      expect(find.text('132 no publicadas'), findsOneWidget);
      expect(find.textContaining('%'), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsNothing);
    });

    testWidgets('an unpublished category is inventoried with reason and action',
        (tester) async {
      final router = await pumpPage(
        tester,
        data: projection(
          collections: [
            entity(
              kind: WebsiteSeoEntityKind.collection,
              id: 'cat-interna',
              label: 'Interna',
              canonicalPath: '/productos/categoria/interna',
              issues: const [
                WebsiteSeoAppEligibilityIssue.ownerNotPublished,
                WebsiteSeoAppEligibilityIssue.noEligibleContent,
              ],
            ),
          ],
        ),
      );

      await tapVisible(tester, find.text('Colecciones'));

      // Not published is a deliberate decision: stated, never escalated.
      expect(find.text('No publicada'), findsOneWidget);
      // The load-bearing guard: an unpublished empty category must never be
      // labelled "Publicada sin productos elegibles".
      expect(find.textContaining('Publicada sin'), findsNothing);
      expect(find.text('No elegible actualmente'), findsNothing);

      await tapVisible(tester, find.text('Interna'));
      expect(find.text('Ruta si se publica'), findsOneWidget);
      expect(find.text('Ruta canónica'), findsNothing);
      expect(
        find.textContaining('No se proyecta al mega-menú'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Sin contenido elegible'),
        findsNothing,
        reason: 'an unpublished owner decision hides consequence diagnostics',
      );

      await tapVisible(tester, find.text('Publicar en Catálogo web'));
      expect(
        find.text('owner:/website/product-visibility?section=categories'),
        findsOneWidget,
      );
      expect(router.canPop(), isTrue);
    });

    testWidgets('the center never offers a publish toggle of its own',
        (tester) async {
      await pumpPage(
        tester,
        data: projection(
          collections: [
            entity(
              kind: WebsiteSeoEntityKind.collection,
              id: 'cat-interna',
              label: 'Interna',
              canonicalPath: '/productos/categoria/interna',
              issues: const [
                WebsiteSeoAppEligibilityIssue.ownerNotPublished,
              ],
            ),
          ],
        ),
      );

      await tapVisible(tester, find.text('Colecciones'));

      // Inventorying an unpublished category must not turn this read-only
      // surface into a second publisher.
      expect(find.byType(Switch), findsNothing);
      expect(find.byType(Checkbox), findsNothing);
      expect(find.text('Guardar'), findsNothing);
      expect(find.textContaining('Mostrar en el sitio'), findsNothing);
    });

    testWidgets('collection detail hands off to Catálogo web with push',
        (tester) async {
      final router = await pumpPage(tester, data: projection());

      await tapVisible(tester, find.text('Colecciones'));
      await tapVisible(tester, find.text('Rutas'));
      await tapVisible(tester, find.text('Abrir en Catálogo web'));
      expect(
        find.text('owner:/website/product-visibility?section=categories'),
        findsOneWidget,
      );

      // `push` keeps the SEO center underneath instead of replacing it.
      expect(router.canPop(), isTrue);
    });

    testWidgets('a generated product title reads as provenance',
        (tester) async {
      await pumpPage(tester, data: projection());

      await tapVisible(tester, find.text('Productos'));

      expect(find.text('Generado'), findsWidgets);
      expect(find.textContaining('faltante'), findsNothing);
    });

    testWidgets('missing deploy evidence stays unknown across every row',
        (tester) async {
      await pumpPage(tester, data: projection());

      await tapVisible(tester, find.text('Páginas'));

      expect(find.text('Sin evidencia de publicación'), findsWidgets);
      expect(find.text('Incluido'), findsNothing);
      expect(
        find.textContaining('No se pudo leer la evidencia del sitio publicado'),
        findsOneWidget,
      );
    });

    testWidgets('desktop shows the detail as a side pane, without a back step',
        (tester) async {
      await pumpPage(tester, data: projection(), size: const Size(1400, 1000));

      await tapVisible(tester, find.text('Páginas'));
      await tapVisible(tester, find.text('Términos y condiciones'));

      // The list stays visible beside the detail, so there is nothing to
      // return from.
      expect(find.text('Volver a la lista'), findsNothing);
      expect(find.byType(SeoCenterList), findsOneWidget);
      expect(find.byType(SeoCenterDetail), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('narrow desktop falls back to contextual navigation',
        (tester) async {
      // Boundary for the internal detail-pane threshold: at 1000 px the rail
      // plus a list plus a 380 px pane would leave the list unreadable, so the
      // detail replaces the body exactly like on tablet.
      await pumpPage(tester, data: projection(), size: const Size(1000, 900));

      await tapVisible(tester, find.text('Páginas'));
      await tapVisible(tester, find.text('Términos y condiciones'));

      expect(find.text('Volver a la lista'), findsOneWidget);
      expect(find.byType(SeoCenterList), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('tablet uses the wrapping selector and contextual detail',
        (tester) async {
      await pumpPage(tester, data: projection(), size: const Size(834, 1112));

      await tapVisible(tester, find.text('Colecciones'));
      await tapVisible(tester, find.text('Rutas'));

      expect(find.text('Volver a la lista'), findsOneWidget);
      expect(find.text('No elegible actualmente'), findsWidgets);
      final horizontalScrollables = find
          .byWidgetPredicate(
            (widget) => widget is Scrollable && widget.axis == Axis.horizontal,
          )
          .evaluate();
      expect(horizontalScrollables, isEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets('phone width stacks the scope selector and the detail',
        (tester) async {
      final router = await pumpPage(
        tester,
        data: projection(),
        size: const Size(390, 820),
      );

      await tapVisible(tester, find.text('Páginas'));
      await tapVisible(tester, find.text('Términos y condiciones'));

      // The detail replaces the body and offers the contextual back control.
      expect(find.text('Volver a la lista'), findsOneWidget);
      await tapVisible(tester, find.text('Volver a la lista'));
      expect(find.text('Volver a la lista'), findsNothing);
      expect(location(router), '/website/seo');
      expect(router.canPop(), isFalse);
      expect(tester.takeException(), isNull);
    });

    /// Site operations belong to the site. A product form may diagnose one
    /// product, but offering "enviar sitemap" from a product — or from the
    /// Pages scope — makes a site operation look entity-scoped.
    group('Google operations placement', () {
      Future<GoRouter> pumpWithOperations(
        WidgetTester tester, {
        Size size = const Size(1400, 1000),
      }) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final service = WebsiteSeoOperationsService(
          invoke: (function, body) async => (
            status: 200,
            data: {
              'connected': true,
              'connection': {
                'account_email': 'owner@example.cl',
                'site_url': 'sc-domain:example.cl',
              },
            },
          ),
          clock: () => DateTime.utc(2026, 7, 28, 12),
        );

        final router = GoRouter(
          initialLocation: '/website/seo',
          routes: [
            GoRoute(
              path: '/website/seo',
              builder: (context, state) => SeoSettingsPage(
                embedded: true,
                loadProjection: (_) async => projection(),
                operationsService: service,
                launchExternalUrl: (_) async => true,
              ),
            ),
          ],
        );

        await tester.pumpWidget(MaterialApp.router(routerConfig: router));
        await tester.pumpAndSettle();
        return router;
      }

      testWidgets('appears in the site scope only', (tester) async {
        await pumpWithOperations(tester);

        expect(find.byType(SeoGoogleOperationsPanel), findsOneWidget);
        expect(find.text('Enviar sitemap'), findsOneWidget);

        await tapVisible(tester, find.text('Páginas'));
        expect(find.byType(SeoGoogleOperationsPanel), findsNothing);
        expect(find.text('Enviar sitemap'), findsNothing);

        await tapVisible(tester, find.text('Productos'));
        expect(find.byType(SeoGoogleOperationsPanel), findsNothing);
      });

      testWidgets('is available at phone width too', (tester) async {
        await pumpWithOperations(tester, size: const Size(390, 820));

        expect(find.byType(SeoGoogleOperationsPanel), findsOneWidget);
        expect(find.text('Enviar sitemap'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets('an operation never writes an owner value', (tester) async {
        await pumpWithOperations(tester);

        // The center still has no form and no save affordance after the
        // operations panel exists.
        expect(find.byType(TextField), findsNothing);
        expect(find.text('Guardar'), findsNothing);
        expect(find.byType(Switch), findsNothing);
      });
    });

    group('Storefront publication band integration', () {
      const failureUuid = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
      const requestUuid = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';

      Map<String, Object?> statusJson({
        bool configured = true,
        bool dispatchEnabled = true,
        String? requestState,
        bool canRetry = false,
        int desired = 8,
        int published = 7,
        Map<String, Object?>? active,
        Map<String, Object?>? latestFailure,
      }) {
        return {
          'supported': true,
          'configured': configured,
          'dispatch_enabled': dispatchEnabled,
          'desired_revision': desired,
          'last_published_revision': published,
          'request_state': requestState,
          'request_id': requestUuid,
          'last_published_request_id': '',
          'can_retry': canRetry,
          'status_message': 'server copy',
          'target_key': 'vinabike-store',
          'expected_store_origin': 'https://vinabike.cl',
          'expected_firebase_origin': 'https://vinabike-store.web.app',
          'active': active,
          'latest_failure': latestFailure,
        };
      }

      Map<String, Object?> failedJson() => statusJson(
            requestState: 'failed',
            canRetry: true,
            latestFailure: {
              'request_id': failureUuid,
              'state': 'failed',
              'requested_revision': 8,
              'attempt_no': 2,
              'failure_stage': 'build',
              'error_class': 'build_failed',
              'error_message': 'raw stack',
              'finished_at': '2026-07-29T11:00:00Z',
            },
          );

      Future<GoRouter> pumpWithPublication(
        WidgetTester tester, {
        required FutureOr<Object?> Function(
          String rpc,
          Map<String, dynamic> params,
        ) publicationHandler,
        List<(String, Map<String, dynamic>)>? rpcLog,
        int Function()? projectionLoads,
        WebsiteSeoOperationsService? operationsService,
        Future<String?> Function()? resolveTenantId,
        Listenable? authorityListenable,
        Future<bool> Function(Uri url)? launchExternalUrl,
        Size size = const Size(1400, 1000),
        bool settle = true,
      }) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        var loads = 0;
        final publication = StorefrontPublicationService(
          invoke: (rpc, params) async {
            rpcLog?.add((rpc, Map<String, dynamic>.from(params)));
            return await publicationHandler(rpc, params);
          },
          clock: () => DateTime.utc(2026, 7, 29, 12),
        );
        final operations = operationsService ??
            WebsiteSeoOperationsService(
              invoke: (function, body) async => (
                status: 200,
                data: {
                  'connected': true,
                  'connection': {
                    'account_email': 'owner@example.cl',
                    'site_url': 'sc-domain:example.cl',
                  },
                },
              ),
              clock: () => DateTime.utc(2026, 7, 29, 12),
            );

        final router = GoRouter(
          initialLocation: '/website/seo',
          routes: [
            GoRoute(
              path: '/website/seo',
              builder: (context, state) => SeoSettingsPage(
                embedded: true,
                loadProjection: (_) async {
                  loads += 1;
                  return projection();
                },
                operationsService: operations,
                publicationService: publication,
                resolvePublicationTenantId:
                    resolveTenantId ?? () async => 'tenant-seo',
                authorityListenable: authorityListenable,
                launchExternalUrl: launchExternalUrl ?? (_) async => true,
              ),
            ),
          ],
        );
        addTearDown(router.dispose);
        // Surface the projection-load counter to the caller through a probe.
        _projectionLoadProbe = () => loads;

        await tester.pumpWidget(MaterialApp.router(routerConfig: router));
        if (settle) {
          await tester.pumpAndSettle();
        } else {
          await tester.pump();
          await tester.pump();
        }
        return router;
      }

      testWidgets(
          'renders exactly once, in Sitio, before the Google panel, and in '
          'no other scope', (tester) async {
        await pumpWithPublication(
          tester,
          publicationHandler: (rpc, _) => statusJson(
            requestState: 'running',
            active: {
              'request_id': requestUuid,
              'state': 'running',
              'requested_revision': 8,
            },
          ),
        );

        expect(find.byType(StorefrontPublicationBand), findsOneWidget);
        final bandTop =
            tester.getTopLeft(find.byType(StorefrontPublicationBand)).dy;
        final panelTop =
            tester.getTopLeft(find.byType(SeoGoogleOperationsPanel)).dy;
        expect(bandTop, lessThan(panelTop),
            reason: 'the band precedes the Google panel');

        for (final scope in const ['Páginas', 'Productos', 'Colecciones']) {
          await tapVisible(tester, find.text(scope));
          expect(find.byType(StorefrontPublicationBand), findsNothing,
              reason: 'no band in $scope');
        }
        await tapVisible(tester, find.text('Sitio'));
        expect(find.byType(StorefrontPublicationBand), findsOneWidget);
      });

      testWidgets(
          '"Actualizar evidencia" refreshes projection, publication '
          'and Google connection together', (tester) async {
        final log = <(String, Map<String, dynamic>)>[];
        await pumpWithPublication(
          tester,
          rpcLog: log,
          publicationHandler: (rpc, _) => statusJson(),
        );

        final statusCallsBefore = log
            .where((e) => e.$1 == StorefrontPublicationService.statusRpc)
            .length;
        final projectionBefore = _projectionLoadProbe!();

        await tapVisible(tester, find.text('Actualizar evidencia'));
        await tester.pumpAndSettle();

        expect(_projectionLoadProbe!(), projectionBefore + 1);
        expect(
          log
              .where((e) => e.$1 == StorefrontPublicationService.statusRpc)
              .length,
          statusCallsBefore + 1,
        );
      });

      testWidgets('the global busy state lasts until the slowest plane ends',
          (tester) async {
        final delayedConnection = Completer<({int status, Object? data})>();
        var connectionReads = 0;
        final operations = WebsiteSeoOperationsService(
          invoke: (function, body) async {
            connectionReads += 1;
            if (connectionReads == 2) return delayedConnection.future;
            return (
              status: 200,
              data: {
                'connected': true,
                'connection': {
                  'account_email': 'owner@example.cl',
                  'site_url': 'sc-domain:example.cl',
                },
              },
            );
          },
          clock: () => DateTime.utc(2026, 7, 29, 12),
        );
        await pumpWithPublication(
          tester,
          operationsService: operations,
          publicationHandler: (rpc, _) => statusJson(),
        );

        await tester.ensureVisible(find.text('Actualizar evidencia'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Actualizar evidencia'));
        await tester.pump();

        final refresh = tester.widget<OutlinedButton>(
          find.ancestor(
            of: find.text('Consultando…'),
            matching: find.byType(OutlinedButton),
          ),
        );
        expect(refresh.onPressed, isNull);
        expect(connectionReads, 2);

        delayedConnection.complete((
          status: 200,
          data: {
            'connected': true,
            'connection': {
              'account_email': 'new-owner@example.cl',
              'site_url': 'sc-domain:example.cl',
            },
          },
        ));
        await tester.pumpAndSettle();

        expect(find.text('Actualizar evidencia'), findsOneWidget);
        expect(connectionReads, 2);
        expect(tester.takeException(), isNull);
      });

      testWidgets('a publication read failure never replaces the SEO center',
          (tester) async {
        await pumpWithPublication(
          tester,
          publicationHandler: (rpc, _) =>
              throw StateError('publication backend down'),
        );

        // The band fails closed on its own…
        expect(
          find.text('No se pudo consultar el estado de publicación.'),
          findsOneWidget,
        );
        // …while the center keeps its header, rail and evidence intact.
        expect(find.text('SEO y visibilidad'), findsOneWidget);
        expect(find.text('Páginas'), findsOneWidget);
        expect(find.text('No se pudo cargar el estado SEO'), findsNothing);
        expect(tester.takeException(), isNull);
      });

      testWidgets('the Sitio attention dot derives from the band presentation',
          (tester) async {
        await pumpWithPublication(
          tester,
          publicationHandler: (rpc, _) => statusJson(
            requestState: 'running',
            active: {
              'request_id': requestUuid,
              'state': 'running',
              'requested_revision': 8,
            },
          ),
        );
        int dots() => find
            .byWidgetPredicate(
              (w) => w.runtimeType.toString() == '_AttentionDot',
            )
            .evaluate()
            .length;
        final baseline = dots();

        await pumpWithPublication(
          tester,
          publicationHandler: (rpc, _) => failedJson(),
        );
        expect(
          dots(),
          baseline + 1,
          reason: 'a failed publication lights exactly the Sitio dot',
        );
      });

      testWidgets(
          'retry sends the recorded failure id and the accepted queue '
          'state replaces the old failure', (tester) async {
        final log = <(String, Map<String, dynamic>)>[];
        await pumpWithPublication(
          tester,
          rpcLog: log,
          publicationHandler: (rpc, params) {
            if (rpc == StorefrontPublicationService.retryRpc) {
              return {
                'accepted': true,
                'enqueued': true,
                'reason': 'manual_retry',
                'status': statusJson(
                  requestState: 'queued',
                  active: null,
                )..['queue'] = {
                    'request_id': requestUuid,
                    'state': 'queued',
                    'requested_revision': 8,
                    'coalesced_count': 1,
                  },
              };
            }
            return failedJson();
          },
        );

        expect(find.text('La publicación falló'), findsOneWidget);
        await tapVisible(tester, find.text('Reintentar publicación'));

        final retryCall = log.singleWhere(
          (e) => e.$1 == StorefrontPublicationService.retryRpc,
        );
        expect(
          retryCall.$2['p_failed_request_id'],
          failureUuid,
          reason: 'retry must target the recorded failure, never the flat '
              'request id',
        );
        // The fresh queued state replaces the old failure immediately.
        expect(find.text('Cambios en cola · rev. 8'), findsOneWidget);
        expect(find.text('La publicación falló'), findsNothing);
      });

      testWidgets(
          'retry and evidence refresh share one lock so an accepted queue '
          'cannot be overwritten by the previous failure', (tester) async {
        final retry = Completer<Object?>();
        final log = <(String, Map<String, dynamic>)>[];
        await pumpWithPublication(
          tester,
          rpcLog: log,
          publicationHandler: (rpc, _) {
            if (rpc == StorefrontPublicationService.retryRpc) {
              return retry.future;
            }
            return failedJson();
          },
        );

        await tester.ensureVisible(find.text('Reintentar publicación'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Reintentar publicación'));
        await tester.pump();

        final globalRefresh = tester.widget<OutlinedButton>(
          find.ancestor(
            of: find.text('Consultando…'),
            matching: find.byType(OutlinedButton),
          ),
        );
        expect(globalRefresh.onPressed, isNull);
        expect(
          log
              .where(
                  (entry) => entry.$1 == StorefrontPublicationService.statusRpc)
              .length,
          1,
          reason: 'no second status read may overtake the retry',
        );

        retry.complete({
          'accepted': true,
          'enqueued': true,
          'reason': 'manual_retry',
          'status': statusJson(requestState: 'queued')
            ..['queue'] = {
              'request_id': requestUuid,
              'state': 'queued',
              'requested_revision': 8,
              'coalesced_count': 1,
            },
        });
        await tester.pumpAndSettle();

        expect(find.text('Cambios en cola · rev. 8'), findsOneWidget);
        expect(find.text('La publicación falló'), findsNothing);
      });

      testWidgets('a tenant change refreshes before any retry is attempted',
          (tester) async {
        var tenantId = 'tenant-a';
        final log = <(String, Map<String, dynamic>)>[];
        await pumpWithPublication(
          tester,
          rpcLog: log,
          resolveTenantId: () async => tenantId,
          publicationHandler: (rpc, params) {
            if (rpc == StorefrontPublicationService.retryRpc) {
              fail('retry must not target a failure from another tenant');
            }
            return params['p_tenant_id'] == 'tenant-a'
                ? failedJson()
                : statusJson(desired: 9, published: 9);
          },
        );

        tenantId = 'tenant-b';
        await tapVisible(tester, find.text('Reintentar publicación'));
        await tester.pumpAndSettle();

        expect(
          log.where(
            (entry) =>
                entry.$1 == StorefrontPublicationService.statusRpc &&
                entry.$2['p_tenant_id'] == 'tenant-b',
          ),
          hasLength(1),
        );
        expect(
          log.where(
            (entry) => entry.$1 == StorefrontPublicationService.retryRpc,
          ),
          isEmpty,
        );
        expect(
          find.textContaining('La tienda activa cambió.'),
          findsOneWidget,
        );
      });

      testWidgets(
          'a tenant change while status is in flight clears A and reloads B',
          (tester) async {
        final authority = ChangeNotifier();
        final tenantAStatus = Completer<Object?>();
        var tenantId = 'tenant-a';
        final log = <(String, Map<String, dynamic>)>[];
        await pumpWithPublication(
          tester,
          settle: false,
          authorityListenable: authority,
          rpcLog: log,
          resolveTenantId: () async => tenantId,
          publicationHandler: (rpc, params) {
            if (params['p_tenant_id'] == 'tenant-a') {
              return tenantAStatus.future;
            }
            return statusJson(desired: 9, published: 9);
          },
        );
        expect(
          log.where(
            (entry) => entry.$2['p_tenant_id'] == 'tenant-a',
          ),
          hasLength(1),
        );

        tenantId = 'tenant-b';
        authority.notifyListeners();
        await tester.pump();
        expect(find.text('La publicación falló'), findsNothing);

        tenantAStatus.complete(failedJson());
        await tester.pumpAndSettle();

        expect(
          log.where(
            (entry) => entry.$2['p_tenant_id'] == 'tenant-b',
          ),
          hasLength(1),
        );
        expect(find.text('La publicación falló'), findsNothing);
        expect(find.text('Sin publicaciones registradas.'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets('a run opening failure is handled with human feedback',
          (tester) async {
        await pumpWithPublication(
          tester,
          launchExternalUrl: (_) async => false,
          publicationHandler: (rpc, _) => statusJson(
            requestState: 'running',
            active: {
              'request_id': requestUuid,
              'state': 'running',
              'requested_revision': 8,
              'github_run_url':
                  'https://github.com/Ccatalan7/bikeshop-erp/actions/runs/12345',
            },
          ),
        );

        await tapVisible(tester, find.text('Ver run'));
        await tester.pumpAndSettle();

        expect(
          find.text('No pudimos abrir el run. Inténtalo nuevamente.'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      });

      testWidgets(
          'a tenant change while a run opens drains the reload and drops '
          'stale feedback', (tester) async {
        final authority = ChangeNotifier();
        final launcher = Completer<bool>();
        var tenantId = 'tenant-a';
        final log = <(String, Map<String, dynamic>)>[];
        await pumpWithPublication(
          tester,
          authorityListenable: authority,
          rpcLog: log,
          resolveTenantId: () async => tenantId,
          launchExternalUrl: (_) => launcher.future,
          publicationHandler: (rpc, params) => statusJson(
            requestState: 'running',
            active: {
              'request_id': requestUuid,
              'state': 'running',
              'requested_revision': 8,
              'github_run_url':
                  'https://github.com/Ccatalan7/bikeshop-erp/actions/runs/12345',
            },
          ),
        );

        final openRun = find.text('Ver run');
        await tester.ensureVisible(openRun);
        await tester.pumpAndSettle();
        await tester.tap(openRun);
        await tester.pump();

        tenantId = 'tenant-b';
        authority.notifyListeners();
        await tester.pump();

        launcher.complete(false);
        await tester.pumpAndSettle();

        expect(
          log.where(
            (entry) =>
                entry.$1 == StorefrontPublicationService.statusRpc &&
                entry.$2['p_tenant_id'] == 'tenant-b',
          ),
          hasLength(1),
        );
        expect(
          find.text('No pudimos abrir el run. Inténtalo nuevamente.'),
          findsNothing,
        );
        expect(find.byType(StorefrontPublicationBand), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets(
          'the complete host fits the disabled automation state at 1180',
          (tester) async {
        await pumpWithPublication(
          tester,
          size: const Size(1180, 1000),
          publicationHandler: (rpc, _) => statusJson(
            dispatchEnabled: false,
          ),
        );

        expect(find.byType(StorefrontPublicationBand), findsOneWidget);
        expect(find.text('Automatización desactivada'), findsOneWidget);
        expect(
          tester.getSize(find.byType(StorefrontPublicationBand)).width,
          lessThan(1180),
        );
        expect(tester.takeException(), isNull);
      });
    });
  });
}

/// Probe wired by the publication pump so tests can observe projection loads.
int Function()? _projectionLoadProbe;
