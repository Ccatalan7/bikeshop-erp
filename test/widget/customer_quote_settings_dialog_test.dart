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

/// Answers like `customer_quote_settings_v1` and
/// `update_customer_quote_settings_v1` (20261103060000), without a database.
class _FakeSettings implements CustomerQuoteService {
  _FakeSettings({this.canEdit = true});

  final bool canEdit;
  Map<String, int>? saved;

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
      });

  @override
  Future<CustomerQuoteSettings> updateSettings({
    required int offerValidityHours,
    required int reminderHoursBefore,
    required int supplierTaskDueHours,
    required int supplierCheckFreshHours,
  }) async {
    saved = {
      'offer_validity_hours': offerValidityHours,
      'reminder_hours_before': reminderHoursBefore,
      'supplier_task_due_hours': supplierTaskDueHours,
      'supplier_check_fresh_hours': supplierCheckFreshHours,
    };
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
    expect(find.text('Ajustes de cotizaciones'), findsNothing);
    expect(tester.takeException(), isNull);
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
