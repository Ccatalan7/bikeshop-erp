import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:vinabike_erp/modules/accounting/models/dashboard_metrics.dart';
import 'package:vinabike_erp/modules/accounting/models/period_detail_breakdown.dart';
import 'package:vinabike_erp/modules/accounting/widgets/period_detail_view.dart';

PeriodDetailItem _payment(
  String id,
  double amount, {
  required String code,
  required String name,
  String? instrument,
  DateTime? day,
  DateTime? at,
}) {
  return PeriodDetailItem(
    id: id,
    documentNumber: 'FV-$id',
    description: name,
    secondaryText: 'Cliente $id',
    amount: amount,
    transactionDate: day ?? DateTime(2026, 10, 10),
    sourceType: 'sales_payment',
    paymentMethodCode: code,
    paymentInstrument: instrument,
    occurredAt: at,
  );
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('es_CL');
  });

  group('PeriodDetailBreakdown, ingresos de caja', () {
    final items = [
      _payment('1', 570500,
          code: 'card_debit', name: 'Tarjeta de débito', instrument: 'debit'),
      _payment('2', 102000,
          code: 'card_credit',
          name: 'Tarjeta de crédito',
          instrument: 'credit'),
      _payment('3', 20000,
          code: 'card',
          name: 'Tarjeta de Crédito/Débito',
          instrument: 'unknown'),
      _payment('4', 104000, code: 'transfer', name: 'Transferencia'),
      _payment('5', 44000, code: 'cash', name: 'Efectivo'),
    ];
    final breakdown =
        PeriodDetailBreakdown.of(items, PeriodDetailKind.incomeCash);

    test('junta crédito, débito y la tarjeta sin distinguir en «Tarjetas»', () {
      final cards = breakdown.bucket(PeriodDetailBreakdown.cardKey)!;
      expect(cards.label, 'Tarjetas');
      expect(cards.amount, 692500);
      expect(cards.count, 3);
      expect(
        cards.children.map((child) => '${child.label} ${child.amount}'),
        ['Débito 570500.0', 'Crédito 102000.0', 'Sin distinguir 20000.0'],
      );
    });

    test('los demás métodos quedan por su nombre, del mayor al menor', () {
      expect(
        breakdown.buckets.map((bucket) => bucket.label),
        ['Tarjetas', 'Transferencia', 'Efectivo'],
      );
      expect(breakdown.total, 840500);
    });

    test('filtrar por Tarjetas o por Débito deja sólo esos cobros', () {
      expect(
        breakdown
            .filter(items, PeriodDetailBreakdown.cardKey)
            .map((item) => item.id),
        ['1', '2', '3'],
      );
      expect(
        breakdown.filter(items, 'card:debit').map((item) => item.id),
        ['1'],
      );
      expect(breakdown.parentOf('card:credit')?.key, 'card');
    });

    test('la tarjeta se reconoce por código e instrumento, no por el nombre',
        () {
      final renamed = PeriodDetailBreakdown.of(
        [
          _payment('9', 10000,
              code: 'card_debit', name: 'Redcompra', instrument: 'debit'),
        ],
        PeriodDetailKind.incomeCash,
      );
      expect(renamed.buckets.single.label, 'Tarjetas');
    });
  });

  test('con más de cinco grupos, los menores se juntan en «Otros métodos»', () {
    final items = [
      for (var i = 0; i < 7; i++)
        _payment('$i', 1000.0 * (7 - i), code: 'm$i', name: 'Método $i'),
    ];
    final breakdown =
        PeriodDetailBreakdown.of(items, PeriodDetailKind.incomeCash);
    expect(breakdown.buckets, hasLength(5));
    expect(breakdown.buckets.last.label, 'Otros métodos');
    expect(breakdown.buckets.last.amount, 3000 + 2000 + 1000);
    expect(
      breakdown.filter(items, PeriodDetailBreakdown.othersKey),
      hasLength(3),
    );
  });

  test('las ventas devengadas no se desglosan', () {
    final breakdown = PeriodDetailBreakdown.of(
      [
        PeriodDetailItem(
          id: 'i1',
          documentNumber: 'FV-1',
          description: 'Venta',
          secondaryText: 'Cliente',
          amount: 1000,
          transactionDate: DateTime(2026, 10, 1),
          sourceType: 'sales_invoice',
        ),
      ],
      PeriodDetailKind.incomeAccrual,
    );
    expect(breakdown.isEmpty, isTrue);
    expect(breakdown.total, 1000);
  });

  test('agrupa por día del taller, el día y el cobro más recientes primero',
      () {
    final days = PeriodDetailBreakdown.groupByDay([
      _payment('a', 1,
          code: 'cash',
          name: 'Efectivo',
          day: DateTime(2026, 10, 9),
          at: DateTime(2026, 10, 9, 10)),
      _payment('b', 1,
          code: 'cash',
          name: 'Efectivo',
          day: DateTime(2026, 10, 10),
          at: DateTime(2026, 10, 10, 9)),
      _payment('c', 1,
          code: 'cash',
          name: 'Efectivo',
          day: DateTime(2026, 10, 10),
          at: DateTime(2026, 10, 10, 18)),
    ]);
    expect(days.map((day) => day.date.day), [10, 9]);
    expect(days.first.items.map((item) => item.id), ['c', 'b']);
  });

  group('período del detalle', () {
    final today = DateTime(2026, 10, 12);

    test('etiquetas', () {
      expect(
        periodDetailRangeLabel(
          DateTimeRange(start: today, end: today),
          today,
        ),
        'Hoy',
      );
      expect(
        periodDetailRangeLabel(
          DateTimeRange(
            start: DateTime(2026, 10, 11),
            end: DateTime(2026, 10, 11),
          ),
          today,
        ),
        'Ayer',
      );
      expect(
        periodDetailRangeLabel(
          DateTimeRange(start: DateTime(2026, 10, 1), end: today),
          today,
        ),
        'Octubre 2026',
      );
      expect(
        periodDetailRangeLabel(
          DateTimeRange(
            start: DateTime(2026, 9, 1),
            end: DateTime(2026, 9, 30),
          ),
          today,
        ),
        'Septiembre 2026',
      );
    });

    test('las flechas avanzan con la misma forma y nunca después de hoy', () {
      final october = DateTimeRange(start: DateTime(2026, 10, 1), end: today);
      final september = periodDetailStep(october, -1, today)!;
      expect(september.start, DateTime(2026, 9, 1));
      expect(september.end, DateTime(2026, 9, 30));
      expect(periodDetailStep(september, 1, today)!.end, today);
      expect(periodDetailStep(october, 1, today), isNull);

      final day = DateTimeRange(start: today, end: today);
      expect(
        periodDetailStep(day, -1, today)!.start,
        DateTime(2026, 10, 11),
      );
      expect(periodDetailStep(day, 1, today), isNull);
    });
  });
}
