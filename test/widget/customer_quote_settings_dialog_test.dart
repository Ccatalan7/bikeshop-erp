import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:vinabike_erp/modules/sales/models/customer_quote.dart';
import 'package:vinabike_erp/modules/sales/services/customer_quote_service.dart';
import 'package:vinabike_erp/modules/sales/widgets/customer_quote_settings_dialog.dart';
import 'package:vinabike_erp/shared/themes/app_theme.dart';
import 'package:vinabike_erp/shared/themes/appearance_preset.dart';

/// Answers like `customer_quote_settings_v1`,
/// `update_customer_quote_settings_v1` (20261103060000) and
/// `customer_quote_sold_out_summary_v1` (20261103070000), without a database.
/// The counts are invented: three brands, one of them listed.
class _FakeSettings implements CustomerQuoteService {
  _FakeSettings({this.canEdit = true, this.summaryFails = false});

  final bool canEdit;
  final bool summaryFails;
  Map<String, int>? saved;
  List<String>? savedBrandIds;
  var savedBrands = false;

  @override
  Future<CustomerQuoteSettings> fetchSettings() async =>
      CustomerQuoteSettings.fromJson({
        'offer_validity_hours': 72,
        'reminder_hours_before': 24,
        'on_order_prepay_percent': 100,
        'supplier_task_due_hours': 24,
        'supplier_check_fresh_hours': 48,
        'can_edit': canEdit,
        'updated_at': '2026-11-02T13:20:00Z',
        'sold_out_brands': [
          {'id': 'brand-pedalia', 'name': 'Pedalia'},
        ],
      });

  @override
  Future<CustomerQuoteSoldOutSummary> fetchSoldOutSummary() async {
    if (summaryFails) throw StateError('sin conexión');
    return CustomerQuoteSoldOutSummary.fromJson({
      'sold_out': 120,
      'on_order': 4,
      'quote': 30,
      'none': 86,
      'quoted_by_product': 2,
      'brands': [
        {
          'id': 'brand-pedalia',
          'name': 'Pedalia',
          'published': 60,
          'sold_out': 25,
          'follows': 24,
          'listed': true,
        },
        {
          'id': 'brand-ruedex',
          'name': 'Ruedex',
          'published': 40,
          'sold_out': 18,
          'follows': 18,
          'listed': false,
        },
        {
          'id': 'brand-genera',
          'name': 'Genera',
          'published': 30,
          'sold_out': 0,
          'follows': 0,
          'listed': false,
        },
      ],
    });
  }

  @override
  Future<CustomerQuoteSettings> updateSettings({
    required int offerValidityHours,
    required int reminderHoursBefore,
    required int supplierTaskDueHours,
    required int supplierCheckFreshHours,
    List<String>? soldOutBrandIds,
  }) async {
    saved = {
      'offer_validity_hours': offerValidityHours,
      'reminder_hours_before': reminderHoursBefore,
      'supplier_task_due_hours': supplierTaskDueHours,
      'supplier_check_fresh_hours': supplierCheckFreshHours,
    };
    savedBrands = soldOutBrandIds != null;
    savedBrandIds = soldOutBrandIds;
    return fetchSettings();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('es');
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

  /// Set QUOTE_SHOTS=<dir> and run with --update-goldens to write the frames
  /// as PNG for a visual check; they are never compared in CI.
  final shotsDir = Platform.environment['QUOTE_SHOTS'];

  Future<bool?> open(
    WidgetTester tester,
    CustomerQuoteService service, {
    Size size = const Size(1280, 900),
    Brightness brightness = Brightness.light,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    bool? result;
    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.resolve(
        preset: AppearancePresets.vinabike,
        brightness: brightness,
      ),
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () async => result =
                  await showCustomerQuoteSettings(context, service: service),
              child: const Text('Abrir'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();
    return result;
  }

  Finder field(String key) => find.byKey(ValueKey('quote-setting-$key'));

  testWidgets(
      'the admin changes the validity and the reminder, each with '
      'what it means', (tester) async {
    final service = _FakeSettings();
    await open(tester, service);

    expect(find.text('Ajustes de cotizaciones'), findsOneWidget);
    expect(find.textContaining('Desde que se envía (3 días)'), findsOneWidget);
    expect(find.text('Lo que viene a pedido se paga completo al aceptar.'),
        findsOneWidget);

    await tester.enterText(field('offer_validity_hours'), '96');
    await tester.enterText(field('reminder_hours_before'), '12');
    await tester.pump();
    expect(find.textContaining('Desde que se envía (4 días)'), findsOneWidget);
    expect(find.textContaining('Le recordamos 12 horas antes'), findsOneWidget);

    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    expect(service.saved, {
      'offer_validity_hours': 96,
      'reminder_hours_before': 12,
      'supplier_task_due_hours': 24,
      'supplier_check_fresh_hours': 48,
    });
    expect(service.savedBrands, isFalse,
        reason: 'an untouched brand list is not rewritten');
    expect(find.text('Ajustes de cotizaciones'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'the admin chooses which brands are quoted without stock and sees '
      'how many sold-out products that offers', (tester) async {
    final service = _FakeSettings();
    await open(tester, service);

    // 4 on order + 2 by their form + 24 Pedalia that follow the brand.
    expect(find.text('Agotados en la tienda'), findsOneWidget);
    expect(find.text('30 de 120 agotados se pueden cotizar'), findsOneWidget);
    expect(find.text('Pedalia · 25'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('quote-sold-out-brand-add')));
    await tester.pumpAndSettle();
    expect(find.text('18 agotados de 40 publicados'), findsOneWidget);
    expect(find.text('Sin agotados · 30 publicados'), findsOneWidget);
    expect(find.text('Pedalia'), findsNothing,
        reason: 'a listed brand is not offered again');
    // The test host is Android: the focused search field draws its caret
    // handle over the first result, so the brand is picked by typing.
    await tester.enterText(find.byType(TextField).last, 'rued');
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(find.text('Ruedex · 18'), findsOneWidget);
    expect(find.text('48 de 120 agotados se pueden cotizar al guardar'),
        findsOneWidget);

    await tester.tap(find.byTooltip('Quitar Pedalia'));
    await tester.pumpAndSettle();
    expect(find.text('Pedalia · 25'), findsNothing);
    expect(find.text('24 de 120 agotados se pueden cotizar al guardar'),
        findsOneWidget);

    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    expect(service.savedBrandIds, ['brand-ruedex']);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'when the sold-out count cannot be read, the listed brands still show '
      'and it can be retried', (tester) async {
    await open(tester, _FakeSettings(summaryFails: true));

    expect(find.text('No se pudieron contar los agotados.'), findsOneWidget);
    expect(find.text('Reintentar'), findsOneWidget);
    expect(find.text('Pedalia'), findsOneWidget);
    expect(
        find.byKey(const ValueKey('quote-sold-out-brand-add')), findsNothing);
    expect(find.text('Guardar'), findsOneWidget);
  });

  testWidgets(
      'a reminder that falls on the sending, or a value out of '
      'bounds, is said in its field and nothing is saved', (tester) async {
    final service = _FakeSettings();
    await open(tester, service);

    await tester.enterText(field('reminder_hours_before'), '72');
    await tester.enterText(field('supplier_task_due_hours'), '0');
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();

    expect(find.text('Tiene que ser antes de que la oferta venza.'),
        findsOneWidget);
    expect(find.text('Entre 1 y 168 horas.'), findsOneWidget);
    expect(service.saved, isNull);
  });

  testWidgets('the rest of the team sees the values and cannot change them',
      (tester) async {
    await open(tester, _FakeSettings(canEdit: false));

    expect(
        find.text('Sólo administración cambia estos valores'), findsOneWidget);
    expect(find.text('Guardar'), findsNothing);
    expect(find.text('Cerrar'), findsOneWidget);
    expect(
      tester.widget<TextField>(field('offer_validity_hours')).enabled,
      isFalse,
    );
    expect(find.text('Pedalia · 25'), findsOneWidget);
    expect(find.byTooltip('Quitar Pedalia'), findsNothing);
    expect(
        find.byKey(const ValueKey('quote-sold-out-brand-add')), findsNothing);
  });

  for (final size in const [Size(1280, 900), Size(390, 844)]) {
    for (final brightness in Brightness.values) {
      final label = '${size.width.toInt()}-${brightness.name}';
      testWidgets('the settings fit at $label', (tester) async {
        await open(tester, _FakeSettings(), size: size, brightness: brightness);
        expect(tester.takeException(), isNull);
        expect(find.text('Guardar'), findsOneWidget);
        if (shotsDir != null) {
          await expectLater(
            find.byType(MaterialApp),
            matchesGoldenFile(
                Uri.file('$shotsDir/cotizaciones-ajustes-$label.png')),
          );
        }
      });
    }
  }
}
