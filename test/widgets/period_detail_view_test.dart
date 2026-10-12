import 'package:flutter/material.dart';
import 'dart:ui' show Tristate;

import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:vinabike_erp/modules/accounting/models/dashboard_metrics.dart';
import 'package:vinabike_erp/modules/accounting/models/period_detail_breakdown.dart';
import 'package:vinabike_erp/modules/accounting/widgets/period_detail_view.dart';
import 'package:vinabike_erp/shared/themes/app_theme.dart';
import 'package:vinabike_erp/shared/themes/appearance_preset.dart';
import 'package:vinabike_erp/shared/themes/vinabike_theme_roles.dart';
import 'package:vinabike_erp/shared/widgets/vb_date_range_picker.dart';

PeriodDetailItem _payment(
  String id,
  double amount, {
  required String code,
  required String name,
  String? instrument,
  int day = 10,
}) {
  return PeriodDetailItem(
    id: id,
    documentNumber: 'FV-$id',
    description: name,
    secondaryText: 'Cliente $id',
    amount: amount,
    transactionDate: DateTime(2026, 10, day),
    sourceType: 'sales_payment',
    paymentMethodCode: code,
    paymentInstrument: instrument,
    occurredAt: DateTime(2026, 10, day, 14, 30),
  );
}

final _items = [
  _payment('1', 69000,
      code: 'card_debit', name: 'Tarjeta de débito', instrument: 'debit'),
  _payment('2', 79000,
      code: 'card_credit',
      name: 'Tarjeta de crédito',
      instrument: 'credit',
      day: 8),
  _payment('3', 30000, code: 'transfer', name: 'Transferencia'),
  _payment('4', 5000, code: 'cash', name: 'Efectivo', day: 9),
];

class _Host extends StatefulWidget {
  const _Host({required this.width, this.mode = PeriodDetailMode.movements});

  final double width;
  final PeriodDetailMode mode;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  String? selected;
  late PeriodDetailMode mode = widget.mode;
  final opened = <String>[];

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SizedBox(
        width: widget.width,
        height: 560,
        child: Material(
          child: PeriodDetailView(
            kind: PeriodDetailKind.incomeCash,
            range: DateTimeRange(
              start: DateTime(2026, 10, 1),
              end: DateTime(2026, 10, 12),
            ),
            today: DateTime(2026, 10, 12),
            items: _items,
            isLoading: false,
            hasError: false,
            mode: mode,
            selectedBucketKey: selected,
            expandedDays: const {},
            onBack: () {},
            onPickRange: (_) {},
            onStepRange: (_) {},
            onModeChanged: (value) => setState(() => mode = value),
            onBucketSelected: (key) => setState(() => selected = key),
            onToggleDay: (_) {},
            onRetry: () {},
            canOpenItem: (_) => true,
            onOpenItem: (item) => opened.add(item.id),
            openItemKey: null,
            loadingItemKey: null,
            expandedItemBuilder: (_) => null,
          ),
        ),
      ),
    );
  }
}

Future<void> _pump(WidgetTester tester, Widget child, {Size? size}) async {
  tester.view.physicalSize = size ?? const Size(1280, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.resolve(
        preset: AppearancePresets.all.first,
        brightness: Brightness.light,
      ),
      home: Scaffold(body: child),
    ),
  );
  await tester.pump();
}

void main() {
  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    await initializeDateFormatting('es_CL');
  });

  testWidgets('el total y Tarjetas (crédito + débito) se leen de una vez',
      (tester) async {
    await _pump(tester, const _Host(width: 860));

    expect(find.text('Octubre 2026'), findsOneWidget);
    expect(find.text('Total · 4 cobros'), findsOneWidget);
    expect(find.text(r'$183.000'), findsOneWidget);
    expect(find.text('Tarjetas · 81 %'), findsOneWidget);
    expect(find.text(r'$148.000'), findsOneWidget);
    // Los movimientos van por día, con método y hora.
    expect(find.text('SÁB 10 OCT'), findsOneWidget);
    expect(find.text('FV-1 · 14:30'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('elegir Tarjetas filtra la lista y abre débito y crédito',
      (tester) async {
    await _pump(tester, const _Host(width: 860));

    await tester.tap(find.text('Tarjetas · 81 %'));
    await tester.pump();

    expect(find.text('Cliente 1'), findsOneWidget);
    expect(find.text('Cliente 2'), findsOneWidget);
    expect(find.text('Cliente 3'), findsNothing);
    expect(find.text('Débito'), findsWidgets);
    expect(find.text('Crédito'), findsWidgets);

    await tester.tap(find.bySemanticsLabel(RegExp(r'^Crédito, \$79\.000')));
    await tester.pump();
    expect(find.text('Cliente 1'), findsNothing);
    expect(find.text('Cliente 2'), findsOneWidget);
  });

  testWidgets('tocar un cobro lo abre (su desglose en productos)',
      (tester) async {
    await _pump(tester, const _Host(width: 860));
    await tester.tap(find.text('Cliente 3'));
    await tester.pump();
    final state = tester.state<_HostState>(find.byType(_Host));
    expect(state.opened, ['3']);
  });

  testWidgets('por día con Tarjetas: columnas de débito y crédito',
      (tester) async {
    await _pump(
      tester,
      const _Host(width: 860, mode: PeriodDetailMode.days),
    );
    await tester.tap(find.text('Tarjetas · 81 %'));
    await tester.pump();

    expect(find.text('DÉBITO'), findsOneWidget);
    expect(find.text('CRÉDITO'), findsOneWidget);
    expect(find.text('TOTAL DEL PERÍODO'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('en teléfono el encabezado se recompone sin desbordes',
      (tester) async {
    await _pump(
      tester,
      const _Host(width: 360),
      size: const Size(390, 844),
    );
    expect(find.text('Total · 4 cobros'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  group('selector de período', () {
    Future<DateTimeRange?> open(
      WidgetTester tester, {
      required DateTimeRange initial,
    }) async {
      DateTimeRange? result;
      await _pump(
        tester,
        Builder(
          builder: (context) => Center(
            child: SizedBox(
              width: 492,
              child: Material(
                child: VbDateRangePanel(
                  initialRange: initial,
                  firstDate: DateTime(2023),
                  lastDate: DateTime(2026, 10, 12),
                  today: DateTime(2026, 10, 12),
                  presets: vbReportDateRangePresets(DateTime(2026, 10, 12)),
                  onApply: (range) => result = range,
                  onCancel: () {},
                ),
              ),
            ),
          ),
        ),
      );
      // Devuelve el resultado al final de la prueba a través del cierre.
      return result;
    }

    testWidgets('hoy se anuncia y un clic elige un solo día', (tester) async {
      DateTimeRange? applied;
      await _pump(
        tester,
        Center(
          child: SizedBox(
            width: 492,
            child: Material(
              child: VbDateRangePanel(
                initialRange: DateTimeRange(
                  start: DateTime(2026, 10, 1),
                  end: DateTime(2026, 10, 12),
                ),
                firstDate: DateTime(2023),
                lastDate: DateTime(2026, 10, 12),
                today: DateTime(2026, 10, 12),
                presets: vbReportDateRangePresets(DateTime(2026, 10, 12)),
                onApply: (range) => applied = range,
                onCancel: () {},
              ),
            ),
          ),
        ),
      );

      expect(
        find.bySemanticsLabel(RegExp(r'^lunes 12 de octubre, hoy$')),
        findsOneWidget,
      );
      // Un día futuro no se puede elegir.
      final future = tester.getSemantics(
        find.bySemanticsLabel(RegExp(r'^martes 13 de octubre$')),
      );
      expect(future.flagsCollection.isEnabled, Tristate.isFalse);

      await tester.tap(find.bySemanticsLabel(RegExp(r'^jueves 8 de octubre$')));
      await tester.pump();
      await tester.tap(find.text('Aplicar'));
      expect(applied?.start, DateTime(2026, 10, 8));
      expect(applied?.end, DateTime(2026, 10, 8));
    });

    testWidgets('la banda del rango se pinta entre el inicio y el fin',
        (tester) async {
      await open(
        tester,
        initial: DateTimeRange(
          start: DateTime(2026, 10, 1),
          end: DateTime(2026, 10, 12),
        ),
      );
      final roles = VinabikeThemeRoles.of(
        tester.element(find.byType(VbDateRangePanel)),
      );
      final bands = tester
          .widgetList<ColoredBox>(find.byType(ColoredBox))
          .where((box) => box.color == roles.selectionContainer);
      expect(bands, isNotEmpty);
      for (final band in bands.take(3)) {
        final size = tester.getSize(find.byWidget(band));
        expect(size.height, greaterThan(20));
      }
    });

    testWidgets('un atajo aplica de una', (tester) async {
      DateTimeRange? applied;
      await _pump(
        tester,
        Center(
          child: SizedBox(
            width: 492,
            child: Material(
              child: VbDateRangePanel(
                initialRange: DateTimeRange(
                  start: DateTime(2026, 9, 1),
                  end: DateTime(2026, 9, 30),
                ),
                firstDate: DateTime(2023),
                lastDate: DateTime(2026, 10, 12),
                today: DateTime(2026, 10, 12),
                presets: vbReportDateRangePresets(DateTime(2026, 10, 12)),
                onApply: (range) => applied = range,
                onCancel: () {},
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Hoy'));
      expect(applied?.start, DateTime(2026, 10, 12));
      expect(applied?.end, DateTime(2026, 10, 12));
    });
  });
}
