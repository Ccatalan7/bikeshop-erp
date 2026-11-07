import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:vinabike_erp/modules/bikeshop/pages/workshop_customer_notices_page.dart';
import 'package:vinabike_erp/modules/bikeshop/services/workshop_customer_notice_service.dart';
import 'package:vinabike_erp/shared/themes/app_theme.dart';
import 'package:vinabike_erp/shared/themes/appearance_preset.dart';

/// Answers like `workshop_customer_notice_overview_v1` and
/// `update_workshop_customer_notice_settings_v1` (20261105130000) without a
/// database. The counts and names are invented.
class _FakeNotices implements WorkshopCustomerNoticeService {
  _FakeNotices({this.canEdit = true});

  final bool canEdit;
  final updates = <Map<String, Object?>>[];
  List<String>? created;
  var whatsappSwitch = true;
  var serviceDays = 14;
  var partsMonths = 2;

  Map<String, dynamic> _data() => {
        'started_at': '2026-11-05T09:00:00Z',
        'can_edit': canEdit,
        'email_switch': true,
        'whatsapp_switch': whatsappSwitch,
        'email_ready': true,
        'whatsapp_ready': true,
        'last_sent_at': '2026-11-05T15:02:00Z',
        'counts': [
          {'kind': 'received', 'channel': 'email', 'state': 'sent', 'count': 4},
          {
            'kind': 'received',
            'channel': 'whatsapp',
            'state': 'sent',
            'count': 21
          },
          {
            'kind': 'received',
            'channel': 'email',
            'state': 'skipped',
            'reason': 'no_email',
            'count': 17
          },
          {
            'kind': 'quote_ready',
            'channel': 'whatsapp',
            'state': 'sent',
            'count': 3
          },
          {
            'kind': 'ready',
            'channel': 'whatsapp',
            'state': 'skipped',
            'reason': 'already_delivered',
            'count': 5
          },
          {
            'kind': 'delivered',
            'channel': 'whatsapp',
            'state': 'pending',
            'count': 1
          },
        ],
        // La recibida con botón ya aprobada; el presupuesto con botón en
        // revisión sale con la anterior; la lista no existe en ninguna
        // versión; la entregada con botón en revisión y sin anterior espera.
        'templates': [
          {'name': 'taller_recibida_v2', 'status': 'APPROVED'},
          {'name': 'taller_recibida_v1', 'status': 'APPROVED'},
          {'name': 'taller_presupuesto_v2', 'status': 'PENDING'},
          {'name': 'taller_presupuesto_v1', 'status': 'APPROVED'},
          {'name': 'taller_entregada_v2', 'status': 'PENDING'},
        ],
        'warranty': {'service_days': serviceDays, 'parts_months': partsMonths},
      };

  @override
  Future<WorkshopNoticeOverview> load({bool refreshTemplates = true}) async =>
      WorkshopNoticeOverview.fromMap(_data(), templateCheckFailed: false);

  @override
  Future<List<WorkshopNoticeRecord>> recent({int limit = 12}) async => [
        WorkshopNoticeRecord(
          id: 'n1',
          jobId: 'job-1',
          kind: WorkshopNoticeKind.received,
          channel: WorkshopNoticeChannel.whatsapp,
          state: 'sent',
          reason: null,
          createdAt: DateTime(2026, 11, 5, 12, 0),
          sentAt: DateTime(2026, 11, 5, 12, 2),
          jobNumber: 'PG-00480',
          customerName: 'Rocío Fuentes',
        ),
        WorkshopNoticeRecord(
          id: 'n2',
          jobId: 'job-1',
          kind: WorkshopNoticeKind.received,
          channel: WorkshopNoticeChannel.email,
          state: 'skipped',
          reason: 'no_email',
          createdAt: DateTime(2026, 11, 5, 12, 0),
          sentAt: null,
          jobNumber: 'PG-00480',
          customerName: 'Rocío Fuentes',
        ),
      ];

  @override
  Future<WorkshopNoticeOverview> update({
    bool? emailEnabled,
    bool? whatsappEnabled,
    int? serviceWarrantyDays,
    int? partsWarrantyMonths,
  }) async {
    updates.add({
      'email': emailEnabled,
      'whatsapp': whatsappEnabled,
      'days': serviceWarrantyDays,
      'months': partsWarrantyMonths,
    });
    if (whatsappEnabled != null) whatsappSwitch = whatsappEnabled;
    if (serviceWarrantyDays != null) serviceDays = serviceWarrantyDays;
    if (partsWarrantyMonths != null) partsMonths = partsWarrantyMonths;
    return WorkshopNoticeOverview.fromMap(_data(), templateCheckFailed: false);
  }

  @override
  Future<int> createTemplates(Iterable<String> names) async {
    created = names.toList();
    return created!.length;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('es');
    await initializeDateFormatting('es_CL');
    final loader = FontLoader('Roboto');
    for (final asset in const <String>[
      'assets/fonts/Barlow-Regular.ttf',
      'assets/fonts/Barlow-Medium.ttf',
      'assets/fonts/Barlow-SemiBold.ttf',
    ]) {
      loader.addFont(rootBundle.load(asset));
    }
    await loader.load();
    final icons =
        File('${Platform.environment['FLUTTER_ROOT'] ?? '.fvm/flutter_sdk'}'
            '/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
    if (icons.existsSync()) {
      final bytes = icons.readAsBytesSync();
      await (FontLoader('MaterialIcons')
            ..addFont(Future.value(ByteData.view(bytes.buffer))))
          .load();
    }
  });

  Future<void> open(
    WidgetTester tester,
    WorkshopCustomerNoticeService service, {
    Size size = const Size(1600, 1000),
    Brightness brightness = Brightness.light,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.resolve(
        preset: AppearancePresets.vinabike,
        brightness: brightness,
      ),
      home: Scaffold(body: WorkshopCustomerNoticesView(service: service)),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets(
      'the four moments say what went out, how each template stands and '
      'what was skipped', (tester) async {
    await open(tester, _FakeNotices());

    expect(find.text('Avisos al cliente'), findsOneWidget);
    expect(find.text('28'), findsOneWidget, reason: '4 + 21 + 3 sent');
    for (final kind in WorkshopNoticeKind.values) {
      expect(find.byKey(ValueKey('workshop-notice-moment-${kind.code}')),
          findsOneWidget);
    }
    expect(find.text('Plantilla aprobada'), findsOneWidget);
    expect(find.text('En revisión · sale con la anterior'), findsOneWidget);
    expect(find.text('Falta crearla en Meta'), findsOneWidget);
    expect(find.text('En revisión de Meta · espera'), findsOneWidget);
    expect(find.text('Omitidos: 17 sin correo'), findsOneWidget);
    expect(find.text('Omitidos: 5 ya la retiraron'), findsOneWidget);
    expect(find.text('PG-00480 · Rocío Fuentes'), findsNWidgets(2));
    expect(find.text('Sin correo'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an admin turns WhatsApp off and creates the missing template',
      (tester) async {
    final service = _FakeNotices();
    await open(tester, service);

    await tester
        .tap(find.byKey(const ValueKey('workshop-notices-whatsapp-switch')));
    await tester.pumpAndSettle();
    expect(service.updates.single['whatsapp'], isFalse);
    expect(
        find.text('Apagado: no sale ningún aviso por aquí.'), findsOneWidget);

    await tester
        .tap(find.byKey(const Key('workshop-notices-create-templates')));
    await tester.pumpAndSettle();
    expect(service.created, ['taller_lista_v2']);
  });

  // 20261107120000: al llegar las plantillas con botón, todas faltaban en
  // Meta y la tarjeta las daba «en revisión». Una anterior aprobada cubre el
  // aviso, pero la tarjeta dice qué pasa con la nueva.
  test('the card tells a missing or rejected new template from one in review',
      () {
    WorkshopNoticeTemplateState state(List<Map<String, String>> templates) =>
        WorkshopNoticeOverview.fromMap(
          {'templates': templates},
          templateCheckFailed: false,
        ).templateState(WorkshopNoticeKind.received);

    const old = {'name': 'taller_recibida_v1', 'status': 'APPROVED'};
    expect(state([old]), WorkshopNoticeTemplateState.missingFallback);
    expect(
      state([
        old,
        {'name': 'taller_recibida_v2', 'status': 'REJECTED'},
      ]),
      WorkshopNoticeTemplateState.rejectedFallback,
    );
    expect(
      state([
        old,
        {'name': 'taller_recibida_v2', 'status': 'PENDING'},
      ]),
      WorkshopNoticeTemplateState.fallback,
    );
    expect(
      state([
        {'name': 'taller_recibida_v2', 'status': 'APPROVED'},
      ]),
      WorkshopNoticeTemplateState.approved,
    );
    expect(state(const []), WorkshopNoticeTemplateState.missing);
  });

  testWidgets('the warranty is saved only with valid values', (tester) async {
    final service = _FakeNotices();
    await open(tester, service);

    final save = find.byKey(const Key('workshop-warranty-save'));
    await tester.enterText(
        find.byKey(const Key('workshop-warranty-days')), '400');
    await tester.pump();
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(find.text('Entre 0 y 365 días.'), findsOneWidget);
    expect(service.updates, isEmpty);

    await tester.enterText(
        find.byKey(const Key('workshop-warranty-days')), '21');
    await tester.enterText(
        find.byKey(const Key('workshop-warranty-months')), '3');
    await tester.pump();
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(service.updates.single, {
      'email': null,
      'whatsapp': null,
      'days': 21,
      'months': 3,
    });
    expect(find.text('Garantía guardada. Rige desde la próxima entrega.'),
        findsOneWidget);
  });

  testWidgets('without permission everything reads but nothing changes',
      (tester) async {
    await open(tester, _FakeNotices(canEdit: false));

    final whatsapp = tester.widget<SwitchListTile>(
        find.byKey(const ValueKey('workshop-notices-whatsapp-switch')));
    expect(whatsapp.onChanged, isNull);
    expect(find.byKey(const Key('workshop-notices-create-templates')),
        findsNothing);
    expect(find.byKey(const Key('workshop-warranty-save')), findsNothing);
    expect(find.text('Sólo administración la cambia.'), findsOneWidget);
  });

  testWidgets('a phone stacks everything in one column, light and dark',
      (tester) async {
    for (final brightness in Brightness.values) {
      await open(tester, _FakeNotices(),
          size: const Size(390, 844), brightness: brightness);
      expect(tester.takeException(), isNull);
      final received = tester.getRect(
          find.byKey(const ValueKey('workshop-notice-moment-received')));
      final quote = tester.getRect(
          find.byKey(const ValueKey('workshop-notice-moment-quote_ready')));
      expect(quote.top, greaterThan(received.bottom),
          reason: 'one moment under the other');
    }
  });
}
