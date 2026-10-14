import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vinabike_erp/modules/website/presence/presence_controller.dart';
import 'package:vinabike_erp/modules/website/presence/presence_models.dart';
import 'package:vinabike_erp/modules/website/presence/presence_service.dart';
import 'package:vinabike_erp/modules/website/presence/website_presence_page.dart';
import 'package:vinabike_erp/shared/services/tenant_service.dart';
import 'package:vinabike_erp/shared/themes/app_theme.dart';
import 'package:vinabike_erp/shared/themes/appearance_preset.dart';

/// «Presencia en internet» (2026-10-14) with rows shaped like the
/// `web_presence_*` tables: every block draws on desktop and phone, light and
/// dark; the period compares whole halves ending on Search Console's last
/// day; Analytics without access says what to do instead of an empty chart.
void main() {
  setUpAll(() async {
    await initializeDateFormatting('es');
    await initializeDateFormatting('es_CL');
  });

  final end = DateTime(2026, 10, 11);
  String day(int back) =>
      end.subtract(Duration(days: back)).toIso8601String().substring(0, 10);

  // 120 days: the last 28 with 2 clicks and 100 views a day at position 8,
  // the 28 before with 1 click and 80 views at position 12.
  final searchRows = [
    for (var back = 119; back >= 0; back--)
      {
        'day': day(back),
        'clicks': back < 28 ? 2 : 1,
        'impressions': back < 28 ? 100 : 80,
        'position': back < 28 ? 8.0 : 12.0,
      },
  ];

  ThemeData theme(Brightness brightness) => AppTheme.resolve(
        preset: AppearancePresets.all.first,
        brightness: brightness,
      );

  late _FakePresenceService service;
  late PresenceController controller;

  PresenceController build({bool withTraffic = false, bool noAccess = false}) {
    service = _FakePresenceService(
      search: searchRows,
      withTraffic: withTraffic,
      noAccess: noAccess,
      day: day,
    );
    return controller = PresenceController(
      service: service,
      tenantService: TenantService.testing(
        currentUserId: () => 'user-1',
        profileLookup: (_) async => [
          {'tenant_id': 'tenant-1', 'role': 'admin', 'permissions': {}},
        ],
      ),
    );
  }

  Future<void> pump(
    WidgetTester tester, {
    required Size size,
    Brightness brightness = Brightness.light,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: theme(brightness),
      home: Scaffold(
        body: WebsitePresencePage(controller: controller, embedded: true),
      ),
    ));
    await tester.pumpAndSettle();
  }

  for (final (label, size) in [
    ('desktop', const Size(1600, 1000)),
    ('tablet', const Size(834, 1112)),
    ('phone', const Size(390, 844)),
  ]) {
    for (final dark in [false, true]) {
      final mode = dark ? 'dark' : 'light';
      testWidgets('every block draws on $label, $mode', (tester) async {
        build(withTraffic: true);
        await pump(
          tester,
          size: size,
          brightness: dark ? Brightness.dark : Brightness.light,
        );
        for (final r in tester.allRenderObjects.whereType<RenderFlex>()) {
          if (r.direction != Axis.horizontal || !r.hasSize) continue;
          var sum = 0.0;
          r.visitChildren((c) => sum += (c as RenderBox).size.width);
          if (sum > r.size.width + 0.5) {
            debugPrint('OVERFLOW ${r.size.width} < $sum: ${r.debugCreator}');
          }
        }
        final error = tester.takeException();
        expect(error, isNull,
            reason: error is FlutterError ? error.toStringDeep() : '$error');
        for (final title in [
          'Día a día',
          'Lo que la gente busca',
          'Páginas que aparecen',
          'Páginas en Google',
          'Visitas al sitio',
          'Bitácora',
        ]) {
          final target = find.text(title);
          await tester.scrollUntilVisible(target, 300,
              scrollable: find.byType(Scrollable).first);
          expect(target, findsOneWidget, reason: '$title on $label $mode');
        }
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets(
      'the period ends on the last Search Console day and compares '
      'with the one before', (tester) async {
    build();
    await pump(tester, size: const Size(1600, 1000));
    expect(controller.currentRange!.to, end);
    expect(controller.current.clicks, 56);
    expect(controller.previous.clicks, 28);
    expect(controller.current.position, closeTo(8, 0.001));
    // 56 against 28: doubled; position 12 → 8 climbs four places.
    expect(find.text('▲ 100 %'), findsWidgets);
    expect(find.text('▲ 4,0 lugares'), findsOneWidget);
    expect(service.termCalls.last.$2, end);
    expect(service.termCalls.last.$1, end.subtract(const Duration(days: 27)));

    controller.setPeriod(PresencePeriod.week);
    await tester.pumpAndSettle();
    expect(service.termCalls.last.$1, end.subtract(const Duration(days: 6)));
    expect(controller.current.clicks, 14);
  });

  testWidgets('a read in any order still ends the period on the last day',
      (tester) async {
    build();
    service.search = searchRows.reversed.toList();
    await pump(tester, size: const Size(1600, 1000));
    expect(controller.currentRange!.to, end);
    expect(controller.current.clicks, 56);
  });

  testWidgets('a read that never answers is tried again, not waited forever',
      (tester) async {
    build(withTraffic: true);
    service.hangOnce.addAll({'runs', 'traffic'});
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: theme(Brightness.light),
      home: Scaffold(
        body: WebsitePresencePage(controller: controller, embedded: true),
      ),
    ));
    await tester.pump(const Duration(seconds: 16));
    await tester.pump(const Duration(seconds: 16));
    await tester.pumpAndSettle();
    expect(controller.hasData, isTrue);
    expect(controller.hasTraffic, isTrue);
    expect(find.text('Día a día'), findsOneWidget);
  });

  testWidgets('a page outside https is shown whole', (tester) async {
    build();
    service.pages = [
      'http://tienda.example/',
      'https://tienda.example/servicios'
    ];
    await pump(tester, size: const Size(1600, 1000));
    final whole = find.text('http://tienda.example/');
    await tester.scrollUntilVisible(whole, 300,
        scrollable: find.byType(Scrollable).first);
    expect(whole, findsOneWidget);
    expect(find.text('/servicios'), findsOneWidget);
  });

  testWidgets('Analytics without access names the account to add',
      (tester) async {
    build(noAccess: true);
    await pump(tester, size: const Size(1600, 1000));
    final notice = find.text('Analytics todavía no deja leer las visitas');
    await tester.scrollUntilVisible(notice, 300,
        scrollable: find.byType(Scrollable).first);
    expect(notice, findsOneWidget);
    expect(
        find.text('cuenta@proyecto.iam.gserviceaccount.com'), findsOneWidget);
    expect(find.text('falta acceso'), findsOneWidget);
  });

  testWidgets('visits by channel and the funnel read Analytics',
      (tester) async {
    build(withTraffic: true);
    await pump(tester, size: const Size(1600, 1000));
    final organic = controller.organic!;
    expect(organic.sessions, 28 * 6);
    expect(organic.previousSessions, 28 * 3);
    final funnel = controller.funnel;
    expect(funnel['purchase'], (2, 0));
    final row = find.text('Búsqueda orgánica');
    await tester.scrollUntilVisible(row, 300,
        scrollable: find.byType(Scrollable).first);
    expect(row, findsOneWidget);
    expect(find.text('Compraron'), findsOneWidget);
  });

  testWidgets('a coverage state opens its addresses', (tester) async {
    build();
    await pump(tester, size: const Size(1600, 1000));
    final state = find.text('Descubierta, aún sin rastrear');
    await tester.scrollUntilVisible(state, 300,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(state);
    await tester.pumpAndSettle();
    expect(service.stateCalls, ['Discovered - currently not indexed']);
    expect(find.text('/producto/bolso-de-cuadro'), findsOneWidget);
    expect(find.text('Google no la ha rastreado'), findsOneWidget);
  });

  test('the position of a period is weighted by impressions', () {
    final totals = SearchTotals.of([
      SearchDay(day: end, clicks: 1, impressions: 90, position: 10),
      SearchDay(day: end, clicks: 0, impressions: 10, position: 50),
    ]);
    expect(totals.position, closeTo(14, 0.0001));
    expect(totals.ctr, closeTo(0.01, 0.0001));
  });
}

class _FakePresenceService extends PresenceService {
  _FakePresenceService({
    required this.search,
    required this.withTraffic,
    required this.noAccess,
    required this.day,
  }) : super(SupabaseClient(
          'http://localhost:54321',
          'test-anon-key',
          // Built inside the test's fake clock: no token refresh timer.
          authOptions: const AuthClientOptions(autoRefreshToken: false),
        ));

  List<Map<String, dynamic>> search;
  List<String>? pages;
  final bool withTraffic;
  final bool noAccess;
  final String Function(int back) day;
  final termCalls = <(DateTime, DateTime)>[];
  final hangOnce = <String>{};

  Future<T> _maybeHang<T>(String name, Future<T> Function() answer) =>
      hangOnce.remove(name) ? Completer<T>().future : answer();
  final stateCalls = <String>[];

  @override
  Future<List<SearchDay>> searchDays(String tenantId) async =>
      [for (final row in search) SearchDay.fromRow(row)];

  @override
  Future<List<IndexDay>> indexDays(String tenantId) async => [
        IndexDay.fromRow({
          'day': day(0),
          'sitemap_urls': 1283,
          'inspected': 307,
          'indexed': 240,
          'by_state': {
            'Submitted and indexed': 240,
            'Discovered - currently not indexed': 50,
            'Crawled - currently not indexed': 12,
            'Page with redirect': 5,
          },
          'sitemap_submitted': 1283,
          'sitemap_last_read': '2026-10-13T16:10:42Z',
        }),
      ];

  @override
  Future<List<TrafficRow>> traffic(
          String tenantId, PresenceScope scope, DateTime from) =>
      _maybeHang('traffic', () async => _traffic());

  List<TrafficRow> _traffic() {
    if (!withTraffic) return const [];
    return [
      for (var back = 55; back >= 0; back--) ...[
        TrafficRow.fromRow({
          'day': day(back),
          'channel': 'Organic Search',
          'sessions': back < 28 ? 6 : 3,
          'engaged_sessions': back < 28 ? 5 : 2,
          'users': 4,
          'key_events': 0,
        }),
        TrafficRow.fromRow({
          'day': day(back),
          'channel': 'Direct',
          'sessions': 2,
          'engaged_sessions': 1,
          'users': 2,
          'key_events': 0,
        }),
      ],
    ];
  }

  @override
  Future<List<EventRow>> events(
      String tenantId, PresenceScope scope, DateTime from) async {
    if (!withTraffic) return const [];
    return [
      EventRow.fromRow(
          {'day': day(3), 'event_name': 'view_item', 'event_count': 40}),
      EventRow.fromRow(
          {'day': day(3), 'event_name': 'purchase', 'event_count': 2}),
      EventRow.fromRow(
          {'day': day(40), 'event_name': 'view_item', 'event_count': 20}),
    ];
  }

  @override
  Future<List<PresenceTerm>> terms(
    String tenantId, {
    required String kind,
    required DateTime from,
    required DateTime to,
    int limit = 50,
  }) async {
    termCalls.add((from, to));
    return kind == 'query'
        ? [
            PresenceTerm.fromRow({
              'term': 'taller de bicicletas',
              'clicks': 12,
              'impressions': 300,
              'avg_position': 6.2,
              'previous_clicks': 4,
              'previous_impressions': 210,
              'previous_avg_position': 11.0,
            }),
            PresenceTerm.fromRow({
              'term': 'cambio de pastillas de freno',
              'clicks': 0,
              'impressions': 14,
              'avg_position': 31.0,
              'previous_clicks': 0,
              'previous_impressions': 0,
              'previous_avg_position': null,
            }),
          ]
        : pages != null
            ? [
                for (final page in pages!)
                  PresenceTerm.fromRow({
                    'term': page,
                    'clicks': 1,
                    'impressions': 10,
                    'avg_position': 5.0,
                    'previous_clicks': 1,
                    'previous_impressions': 10,
                    'previous_avg_position': 5.0,
                  }),
              ]
            : [
                PresenceTerm.fromRow({
                  'term': 'https://tienda.example/servicios',
                  'clicks': 9,
                  'impressions': 120,
                  'avg_position': 7.5,
                  'previous_clicks': 1,
                  'previous_impressions': 30,
                  'previous_avg_position': 15.0,
                }),
              ];
  }

  @override
  Future<List<PresenceNote>> notes(String tenantId) async => [
        PresenceNote.fromRow({
          'id': 'n1',
          'kind': 'cambio',
          'day': day(10),
          'title': 'La ficha muestra la marca en el nombre',
          'body': 'catalogo: la ficha muestra la marca en el nombre.',
          'source': 'wiki',
        }),
        PresenceNote.fromRow({
          'id': 'n2',
          'kind': 'analisis',
          'day': day(2),
          'title': 'Las búsquedas del taller suben',
          'body': 'Análisis semanal.',
          'source': 'analisis',
        }),
      ];

  @override
  Future<List<PresenceRun>> runs(String tenantId, {int limit = 12}) =>
      _maybeHang('runs', () async => _runs());

  List<PresenceRun> _runs() => [
        PresenceRun.fromRow({
          'task': 'collect',
          'status': 'ok',
          'started_at': '2026-10-14T09:23:00Z',
          'finished_at': '2026-10-14T09:24:00Z',
          'detail': {
            'errors': <String>[],
            if (noAccess)
              'traffic': {
                'noAccess': true,
                'property': '123456789',
                'account': 'cuenta@proyecto.iam.gserviceaccount.com',
              },
          },
        }),
      ];

  @override
  Future<PresenceSettings> settings(String tenantId) async =>
      PresenceSettings.fromRow({
        'enabled': true,
        'ga4_property_id': '123456789',
        'gsc_site': 'sc-domain:tienda.example',
      });

  @override
  Future<List<PresenceUrl>> urlsInState(String tenantId, String state,
      {int limit = 200}) async {
    stateCalls.add(state);
    return [
      PresenceUrl.fromRow({
        'url': 'https://tienda.example/producto/bolso-de-cuadro',
        'coverage_state': state,
        'verdict': 'NEUTRAL',
        'last_crawl_at': null,
        'inspected_at': '2026-10-14T09:00:00Z',
        'google_canonical': null,
      }),
    ];
  }
}
