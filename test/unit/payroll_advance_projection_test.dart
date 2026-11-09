import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/hr/models/payroll_advance_projection.dart';
import 'package:vinabike_erp/modules/hr/models/payroll_voucher.dart';

// El caso real del 2026-11-08: Braulio recibió $20.000 el viernes 7 de
// noviembre, una hora después de crear el borrador de la S45 (02–08 nov), y la
// semana seguía pidiendo pagarle sus $77.700 completos.
void main() {
  group('PayrollAdvanceProjection', () {
    test('un anticipo entregado dentro de la semana la descuenta', () {
      final s45 = _week('s45', start: DateTime(2026, 11, 2), lines: [
        _line('braulio-s45', employee: 'braulio', balance: 77700),
        _line('vicente-s45', employee: 'vicente', balance: 130200),
      ]);
      final projection = PayrollAdvanceProjection.of(
        weeks: [s45],
        advances: [
          _advance('a1',
              employee: 'braulio', amount: 20000, paid: DateTime(2026, 11, 7)),
        ],
      );

      expect(projection.clpFor('braulio-s45'), 20000);
      expect(projection.clpFor('vicente-s45'), 0);
      expect(projection.clpForWeek(s45), 20000);
      expect(projection.clpOf(lineId: 'braulio-s45', advanceId: 'a1'), 20000);
      expect(projection.sharesFor('braulio-s45').single.advance.id, 'a1');
    });

    test('el anticipo del domingo de cierre todavía es de esa semana', () {
      final s45 = _week('s45', start: DateTime(2026, 11, 2), lines: [
        _line('braulio-s45', employee: 'braulio', balance: 77700),
      ]);
      final projection = PayrollAdvanceProjection.of(
        weeks: [s45],
        advances: [
          _advance('a1',
              employee: 'braulio', amount: 20000, paid: DateTime(2026, 11, 8)),
        ],
      );

      expect(projection.clpFor('braulio-s45'), 20000);
    });

    test('un anticipo posterior al cierre no descuenta esa semana', () {
      final s45 = _week('s45', start: DateTime(2026, 11, 2), lines: [
        _line('braulio-s45', employee: 'braulio', balance: 77700),
      ]);
      final projection = PayrollAdvanceProjection.of(
        weeks: [s45],
        advances: [
          _advance('a1',
              employee: 'braulio', amount: 20000, paid: DateTime(2026, 11, 9)),
        ],
      );

      expect(projection.clpFor('braulio-s45'), 0);
      expect(projection.isEmpty, isTrue);
    });

    test(
        'va a la semana impaga más antigua y no se cuenta dos veces aunque '
        'calce con varias', () {
      final s44 = _week('s44', start: DateTime(2026, 10, 26), lines: [
        _line('braulio-s44', employee: 'braulio', balance: 92400),
      ]);
      final s45 = _week('s45', start: DateTime(2026, 11, 2), lines: [
        _line('braulio-s45', employee: 'braulio', balance: 77700),
      ]);
      // El orden de entrada no decide: la semana más antigua manda.
      final projection = PayrollAdvanceProjection.of(
        weeks: [s45, s44],
        advances: [
          _advance('a1',
              employee: 'braulio', amount: 20000, paid: DateTime(2026, 10, 30)),
        ],
      );

      expect(projection.clpFor('braulio-s44'), 20000);
      expect(projection.clpFor('braulio-s45'), 0);
    });

    test('lo que una semana no alcanza a cubrir pasa a la siguiente', () {
      final s44 = _week('s44', start: DateTime(2026, 10, 26), lines: [
        _line('braulio-s44', employee: 'braulio', balance: 60000),
      ]);
      final s45 = _week('s45', start: DateTime(2026, 11, 2), lines: [
        _line('braulio-s45', employee: 'braulio', balance: 77700),
      ]);
      final projection = PayrollAdvanceProjection.of(
        weeks: [s44, s45],
        advances: [
          _advance('a1',
              employee: 'braulio',
              amount: 100000,
              paid: DateTime(2026, 10, 27)),
        ],
      );

      expect(projection.clpFor('braulio-s44'), 60000);
      expect(projection.clpFor('braulio-s45'), 40000);
    });

    test(
        'semanas pagadas o anuladas, líneas excluidas o sin saldo no '
        'descuentan nada', () {
      final paid = _week(
        's43',
        start: DateTime(2026, 10, 19),
        status: PayrollVoucherStatus.paid,
        lines: [_line('braulio-s43', employee: 'braulio', balance: 50000)],
      );
      final voided = _week(
        's44',
        start: DateTime(2026, 10, 26),
        status: PayrollVoucherStatus.voided,
        lines: [_line('braulio-s44', employee: 'braulio', balance: 50000)],
      );
      final s45 = _week('s45', start: DateTime(2026, 11, 2), lines: [
        _line('braulio-excluded',
            employee: 'braulio', balance: 30000, included: false),
        _line('braulio-zero', employee: 'braulio', balance: 0),
        _line('braulio-s45', employee: 'braulio', balance: 77700),
      ]);
      final projection = PayrollAdvanceProjection.of(
        weeks: [paid, voided, s45],
        advances: [
          _advance('a1',
              employee: 'braulio', amount: 20000, paid: DateTime(2026, 10, 20)),
        ],
      );

      expect(projection.clpFor('braulio-s43'), 0);
      expect(projection.clpFor('braulio-s44'), 0);
      expect(projection.clpFor('braulio-excluded'), 0);
      expect(projection.clpFor('braulio-zero'), 0);
      expect(projection.clpFor('braulio-s45'), 20000);
      expect(projection.clpForWeek(s45), 20000);
    });

    test('una semana confirmada y una con pago parcial también descuentan', () {
      final confirmed = _week(
        's44',
        start: DateTime(2026, 10, 26),
        status: PayrollVoucherStatus.confirmed,
        lines: [_line('braulio-s44', employee: 'braulio', balance: 5000)],
      );
      final partial = _week(
        's45',
        start: DateTime(2026, 11, 2),
        status: PayrollVoucherStatus.partial,
        lines: [_line('braulio-s45', employee: 'braulio', balance: 30000)],
      );
      final projection = PayrollAdvanceProjection.of(
        weeks: [confirmed, partial],
        advances: [
          _advance('a1',
              employee: 'braulio', amount: 20000, paid: DateTime(2026, 10, 28)),
        ],
      );

      expect(projection.clpFor('braulio-s44'), 5000);
      expect(projection.clpFor('braulio-s45'), 15000);
    });

    test('cada persona descuenta sólo sus propios anticipos', () {
      final s45 = _week('s45', start: DateTime(2026, 11, 2), lines: [
        _line('braulio-s45', employee: 'braulio', balance: 77700),
        _line('rodrigo-s45', employee: 'rodrigo', balance: 58000),
      ]);
      final projection = PayrollAdvanceProjection.of(
        weeks: [s45],
        advances: [
          _advance('a1',
              employee: 'rodrigo', amount: 36000, paid: DateTime(2026, 11, 4)),
        ],
      );

      expect(projection.clpFor('braulio-s45'), 0);
      expect(projection.clpFor('rodrigo-s45'), 36000);
    });

    test(
        'sólo cuenta lo vigente: un parcial descuenta su saldo, uno aplicado o '
        'anulado nada', () {
      final s45 = _week('s45', start: DateTime(2026, 11, 2), lines: [
        _line('braulio-s45', employee: 'braulio', balance: 77700),
      ]);
      final projection = PayrollAdvanceProjection.of(
        weeks: [s45],
        advances: [
          _advance('partial',
              employee: 'braulio',
              amount: 30000,
              applied: 10000,
              status: 'partially_applied',
              paid: DateTime(2026, 11, 3)),
          _advance('applied',
              employee: 'braulio',
              amount: 15000,
              applied: 15000,
              status: 'applied',
              paid: DateTime(2026, 11, 3)),
          _advance('voided',
              employee: 'braulio',
              amount: 9000,
              status: 'voided',
              paid: DateTime(2026, 11, 3)),
        ],
      );

      expect(projection.clpFor('braulio-s45'), 20000);
      expect(
        projection.sharesFor('braulio-s45').map((share) => share.advance.id),
        <String>['partial'],
      );
    });

    test('varios anticipos se consumen del más antiguo al más nuevo', () {
      final s45 = _week('s45', start: DateTime(2026, 11, 2), lines: [
        _line('braulio-s45', employee: 'braulio', balance: 20000),
      ]);
      final s46 = _week('s46', start: DateTime(2026, 11, 9), lines: [
        _line('braulio-s46', employee: 'braulio', balance: 70000),
      ]);
      final projection = PayrollAdvanceProjection.of(
        weeks: [s45, s46],
        advances: [
          _advance('newer',
              employee: 'braulio', amount: 10000, paid: DateTime(2026, 11, 6)),
          _advance('older',
              employee: 'braulio', amount: 15000, paid: DateTime(2026, 11, 3)),
        ],
      );

      final s45Shares = projection.sharesFor('braulio-s45');
      expect(s45Shares.map((share) => share.advance.id), ['older', 'newer']);
      expect(s45Shares.map((share) => share.amountClp), [15000, 5000]);
      expect(projection.clpOf(lineId: 'braulio-s46', advanceId: 'newer'), 5000);
      expect(projection.clpFor('braulio-s46'), 5000);
    });

    test('redondea a pesos y nunca descuenta más que el saldo', () {
      final s45 = _week('s45', start: DateTime(2026, 11, 2), lines: [
        _line('braulio-s45', employee: 'braulio', balance: 12000.4),
      ]);
      final projection = PayrollAdvanceProjection.of(
        weeks: [s45],
        advances: [
          _advance('a1',
              employee: 'braulio',
              amount: 50000.6,
              paid: DateTime(2026, 11, 2)),
        ],
      );

      expect(projection.clpFor('braulio-s45'), 12000);
    });

    test('sin anticipos vigentes el reparto queda vacío', () {
      final s45 = _week('s45', start: DateTime(2026, 11, 2), lines: [
        _line('braulio-s45', employee: 'braulio', balance: 77700),
      ]);
      final projection = PayrollAdvanceProjection.of(
        weeks: [s45],
        advances: const <EmployeeAdvance>[],
      );

      expect(projection.isEmpty, isTrue);
      expect(projection.sharesFor('braulio-s45'), isEmpty);
      expect(projection.clpFor(null), 0);
    });
  });
}

PayrollVoucher _week(
  String id, {
  required DateTime start,
  required List<PayrollVoucherLine> lines,
  PayrollVoucherStatus status = PayrollVoucherStatus.draft,
}) {
  return PayrollVoucher(
    id: id,
    tenantId: 'tenant',
    voucherNumber: 'NOM-$id',
    periodStart: start,
    periodEnd: start.add(const Duration(days: 6)),
    status: status,
    createdAt: start,
    updatedAt: start,
    lines: [
      for (final line in lines)
        PayrollVoucherLine(
          id: line.id,
          voucherId: id,
          employeeId: line.employeeId,
          employeeName: line.employeeName,
          totalAmount: line.totalAmount,
          isIncluded: line.isIncluded,
          balance: line.balance,
        ),
    ],
  );
}

PayrollVoucherLine _line(
  String id, {
  required String employee,
  required double balance,
  bool included = true,
}) {
  return PayrollVoucherLine(
    id: id,
    voucherId: 'pending',
    employeeId: employee,
    employeeName: employee,
    totalAmount: balance,
    isIncluded: included,
    balance: balance,
  );
}

EmployeeAdvance _advance(
  String id, {
  required String employee,
  required double amount,
  required DateTime paid,
  double applied = 0,
  String status = 'open',
}) {
  return EmployeeAdvance(
    id: id,
    employeeId: employee,
    amount: amount,
    amountApplied: applied,
    // Chile: medianoche civil = 03:00 UTC en noviembre.
    paidAt: DateTime.utc(paid.year, paid.month, paid.day, 3),
    paidCivilDate: paid,
    status: status,
  );
}
