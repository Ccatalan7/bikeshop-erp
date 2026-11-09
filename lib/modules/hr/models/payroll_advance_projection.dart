import 'package:flutter/foundation.dart';

import 'payroll_voucher.dart';

/// Lo que un anticipo vigente le descuenta a una línea de nómina.
@immutable
class PayrollAdvanceShare {
  const PayrollAdvanceShare({
    required this.advance,
    required this.amountClp,
  });

  final EmployeeAdvance advance;
  final int amountClp;
}

/// Reparte los anticipos vigentes entre las semanas que todavía no se pagan.
///
/// Un anticipo es sueldo entregado antes de tiempo, así que se descuenta del
/// primer sueldo que queda por pagar después de entregarlo: la semana impaga
/// más antigua que cierra el mismo día o después del anticipo. Lo que esa
/// semana no alcanza a cubrir pasa a la siguiente, y cada peso se cuenta una
/// sola vez aunque el anticipo calce con varias semanas abiertas.
///
/// Hasta el 2026-11-08 la semana sólo restaba lo que alguien ya había aplicado
/// a mano al registrar el pago. Un anticipo vigente no aparecía ni en la tabla
/// ni en el pie: `A PAGAR` mostraba el sueldo completo y quien paga desde el
/// banco mirando esa cifra le pagaba dos veces el anticipo al trabajador
/// (Braulio, S45: $77.700 en vez de $57.700).
///
/// Es una proyección, no un asiento. La imputación contable sigue ocurriendo
/// al registrar el pago, que parte con estos montos ya aplicados y se puede
/// corregir antes de guardar. Por eso este cálculo es el único dueño de la
/// pregunta «¿qué anticipo le toca a esta semana?»: la tabla, la tarjeta de la
/// semana, el pie y los dos pagos (transferencia y efectivo) leen de acá, y no
/// pueden contradecirse entre sí.
class PayrollAdvanceProjection {
  const PayrollAdvanceProjection._(this._sharesByLineId);

  static const PayrollAdvanceProjection empty =
      PayrollAdvanceProjection._(<String, List<PayrollAdvanceShare>>{});

  /// Proyecta [advances] sobre las semanas abiertas de [weeks].
  ///
  /// Las semanas pagadas o anuladas no reciben nada aunque vengan en la lista:
  /// su sueldo ya no espera dinero. Una línea excluida, sin identidad o sin
  /// saldo tampoco, y un anticipo aplicado o anulado no tiene nada que repartir.
  factory PayrollAdvanceProjection.of({
    required Iterable<PayrollVoucher> weeks,
    required Iterable<EmployeeAdvance> advances,
  }) {
    final pendingByEmployee = <String, List<_PendingAdvance>>{};
    for (final advance in advances) {
      if (!_isVigente(advance)) continue;
      final available = advance.availableAmount.round();
      if (available <= 0) continue;
      pendingByEmployee
          .putIfAbsent(advance.employeeId, () => <_PendingAdvance>[])
          .add(_PendingAdvance(advance, available));
    }
    if (pendingByEmployee.isEmpty) return empty;
    for (final pending in pendingByEmployee.values) {
      pending.sort(_byPaidDate);
    }

    final openWeeks = weeks.where(_isOpen).toList(growable: false)
      ..sort(_byPeriod);
    final shares = <String, List<PayrollAdvanceShare>>{};
    for (final week in openWeeks) {
      final close = _civil(week.periodEnd);
      for (final line in week.lines) {
        final lineId = line.id?.trim() ?? '';
        if (!line.isIncluded || lineId.isEmpty) continue;
        var capacity = line.balance.round();
        if (capacity <= 0) continue;
        final pending = pendingByEmployee[line.employeeId];
        if (pending == null) continue;
        for (final item in pending) {
          if (capacity <= 0) break;
          // Ordenados por fecha: si éste se entregó después del cierre, los
          // que siguen también. Un anticipo del jueves no descuenta la semana
          // que terminó el domingo anterior.
          if (_civil(item.advance.paidCivilDate).isAfter(close)) break;
          if (item.remainingClp <= 0) continue;
          final take =
              item.remainingClp < capacity ? item.remainingClp : capacity;
          item.remainingClp -= take;
          capacity -= take;
          shares.putIfAbsent(lineId, () => <PayrollAdvanceShare>[]).add(
                PayrollAdvanceShare(advance: item.advance, amountClp: take),
              );
        }
      }
    }
    return PayrollAdvanceProjection._(<String, List<PayrollAdvanceShare>>{
      for (final entry in shares.entries)
        entry.key: List<PayrollAdvanceShare>.unmodifiable(entry.value),
    });
  }

  final Map<String, List<PayrollAdvanceShare>> _sharesByLineId;

  bool get isEmpty => _sharesByLineId.isEmpty;

  /// Los anticipos que descuenta esta línea, del más antiguo al más nuevo.
  List<PayrollAdvanceShare> sharesFor(String? lineId) {
    final key = lineId?.trim() ?? '';
    if (key.isEmpty) return const <PayrollAdvanceShare>[];
    return _sharesByLineId[key] ?? const <PayrollAdvanceShare>[];
  }

  /// Pesos de anticipo que esta línea descontará al pagarse.
  int clpFor(String? lineId) => sharesFor(lineId).fold<int>(
        0,
        (sum, share) => sum + share.amountClp,
      );

  /// Lo que le toca a [advanceId] dentro de esta línea; cero si no le toca.
  int clpOf({required String? lineId, required String advanceId}) =>
      sharesFor(lineId)
          .where((share) => share.advance.id == advanceId)
          .fold<int>(0, (sum, share) => sum + share.amountClp);

  /// Pesos de anticipo que descuenta la semana completa (líneas incluidas).
  int clpForWeek(PayrollVoucher week) => week.lines
      .where((line) => line.isIncluded)
      .fold<int>(0, (sum, line) => sum + clpFor(line.id));

  static bool _isOpen(PayrollVoucher week) =>
      week.status == PayrollVoucherStatus.draft ||
      week.status == PayrollVoucherStatus.confirmed ||
      week.status == PayrollVoucherStatus.partial;

  /// `employee_advances_status_check`: `open | partially_applied | applied |
  /// voided`. Sólo los dos primeros tienen saldo que descontar.
  static bool _isVigente(EmployeeAdvance advance) {
    final status = advance.status.trim().toLowerCase();
    return status == 'open' || status == 'partially_applied';
  }

  static DateTime _civil(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  static int _byPaidDate(_PendingAdvance a, _PendingAdvance b) {
    final byCivil = _civil(a.advance.paidCivilDate)
        .compareTo(_civil(b.advance.paidCivilDate));
    if (byCivil != 0) return byCivil;
    final byInstant = a.advance.paidAt.compareTo(b.advance.paidAt);
    if (byInstant != 0) return byInstant;
    return a.advance.id.compareTo(b.advance.id);
  }

  static int _byPeriod(PayrollVoucher a, PayrollVoucher b) {
    final byEnd = _civil(a.periodEnd).compareTo(_civil(b.periodEnd));
    if (byEnd != 0) return byEnd;
    final byStart = _civil(a.periodStart).compareTo(_civil(b.periodStart));
    if (byStart != 0) return byStart;
    return (a.id ?? '').compareTo(b.id ?? '');
  }
}

class _PendingAdvance {
  _PendingAdvance(this.advance, this.remainingClp);

  final EmployeeAdvance advance;
  int remainingClp;
}
