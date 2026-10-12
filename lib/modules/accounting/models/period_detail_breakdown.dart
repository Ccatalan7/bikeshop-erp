import 'package:flutter/foundation.dart';

import '../../../shared/models/payment_method.dart';
import 'dashboard_metrics.dart';

/// Qué está mirando el detalle de una barra del panorama financiero. Decide
/// cómo se agrupan los movimientos.
enum PeriodDetailKind { incomeCash, incomeAccrual, expenseCash, expenseAccrual }

extension PeriodDetailKindX on PeriodDetailKind {
  bool get isIncome =>
      this == PeriodDetailKind.incomeCash ||
      this == PeriodDetailKind.incomeAccrual;

  bool get isCash =>
      this == PeriodDetailKind.incomeCash ||
      this == PeriodDetailKind.expenseCash;
}

/// Un grupo del desglose: «Tarjetas», «Transferencia», «Débito»…
@immutable
class PeriodDetailBucket {
  const PeriodDetailBucket({
    required this.key,
    required this.label,
    required this.amount,
    required this.count,
    this.children = const [],
  });

  final String key;
  final String label;
  final double amount;
  final int count;

  /// Sólo las tarjetas tienen hijos: débito, crédito, prepago o sin distinguir.
  final List<PeriodDetailBucket> children;

  bool get hasChildren => children.isNotEmpty;
}

/// Un día del período con sus movimientos, del más reciente al más antiguo.
@immutable
class PeriodDetailDay {
  const PeriodDetailDay({required this.date, required this.items});

  final DateTime date;
  final List<PeriodDetailItem> items;

  double get total => items.fold<double>(0, (sum, item) => sum + item.amount);
}

/// Desglose de los movimientos de un período.
///
/// En ingresos de caja agrupa por método y junta **todas las tarjetas** en
/// «Tarjetas», con débito y crédito como hijos: es la pregunta del dueño
/// («cuánto vendí por tarjeta, crédito más débito»). La regla de qué es una
/// tarjeta es la de la caja ([PaymentMethod.isCardMethod]), leída del código y
/// el instrumento del método, nunca del nombre.
///
/// En gastos agrupa por cuenta (proveedores y anticipos aparte). Las ventas
/// devengadas no se desglosan: todas son «Venta».
class PeriodDetailBreakdown {
  PeriodDetailBreakdown._({
    required this.kind,
    required this.buckets,
    required this.total,
    required this.count,
    required Set<String> mergedKeys,
  }) : _mergedKeys = mergedKeys;

  factory PeriodDetailBreakdown.of(
    List<PeriodDetailItem> items,
    PeriodDetailKind kind, {
    int maxBuckets = 5,
  }) {
    final total = items.fold<double>(0, (sum, item) => sum + item.amount);
    if (kind == PeriodDetailKind.incomeAccrual || items.isEmpty) {
      return PeriodDetailBreakdown._(
        kind: kind,
        buckets: const [],
        total: total,
        count: items.length,
        mergedKeys: const {},
      );
    }

    final tops = <String, _MutableBucket>{};
    for (final item in items) {
      final top = _rawTopOf(item, kind);
      final bucket = tops.putIfAbsent(
        top.key,
        () => _MutableBucket(top.key, top.label),
      )..add(item.amount);
      final child = _childOf(item, kind);
      if (child != null) {
        bucket.children
            .putIfAbsent(
                child.key, () => _MutableBucket(child.key, child.label))
            .add(item.amount);
      }
    }

    final sorted = tops.values.toList()..sort(_byAmountThenLast);
    final mergedKeys = <String>{};
    var kept = sorted;
    if (sorted.length > maxBuckets && maxBuckets >= 2) {
      kept = sorted.take(maxBuckets - 1).toList();
      final rest = sorted.skip(maxBuckets - 1).toList();
      mergedKeys.addAll(rest.map((bucket) => bucket.key));
      final others = _MutableBucket(
        othersKey,
        kind.isIncome ? 'Otros métodos' : 'Otras cuentas',
      );
      for (final bucket in rest) {
        others
          ..amount += bucket.amount
          ..count += bucket.count;
      }
      kept.add(others);
    }

    return PeriodDetailBreakdown._(
      kind: kind,
      buckets: [for (final bucket in kept) bucket.freeze()],
      total: total,
      count: items.length,
      mergedKeys: mergedKeys,
    );
  }

  static const String cardKey = 'card';
  static const String othersKey = 'others';
  static const String _noMethodKey = 'method:none';

  final PeriodDetailKind kind;
  final List<PeriodDetailBucket> buckets;
  final double total;
  final int count;
  final Set<String> _mergedKeys;

  bool get isEmpty => buckets.isEmpty;

  /// El grupo (o subgrupo) con esa llave, si existe en este período.
  PeriodDetailBucket? bucket(String? key) {
    if (key == null) return null;
    for (final top in buckets) {
      if (top.key == key) return top;
      for (final child in top.children) {
        if (child.key == key) return child;
      }
    }
    return null;
  }

  /// El grupo padre de un subgrupo (para «Débito», «Tarjetas»).
  PeriodDetailBucket? parentOf(String key) {
    for (final top in buckets) {
      if (top.children.any((child) => child.key == key)) return top;
    }
    return null;
  }

  String topKeyOf(PeriodDetailItem item) {
    final key = _rawTopOf(item, kind).key;
    return _mergedKeys.contains(key) ? othersKey : key;
  }

  String? childKeyOf(PeriodDetailItem item) => _childOf(item, kind)?.key;

  /// Si [item] pertenece al grupo [key]; sin llave, todo pertenece.
  bool matches(PeriodDetailItem item, String? key) {
    if (key == null) return true;
    return topKeyOf(item) == key || childKeyOf(item) == key;
  }

  List<PeriodDetailItem> filter(List<PeriodDetailItem> items, String? key) {
    if (key == null) return items;
    return [
      for (final item in items)
        if (matches(item, key)) item,
    ];
  }

  /// Agrupa por día del taller, del más reciente al más antiguo. Dentro del
  /// día, el último movimiento primero.
  static List<PeriodDetailDay> groupByDay(List<PeriodDetailItem> items) {
    final byDay = <DateTime, List<PeriodDetailItem>>{};
    for (final item in items) {
      final date = item.transactionDate;
      byDay
          .putIfAbsent(DateTime(date.year, date.month, date.day), () => [])
          .add(item);
    }
    final days = byDay.keys.toList()..sort((a, b) => b.compareTo(a));
    return [
      for (final day in days)
        PeriodDetailDay(
          date: day,
          items: [...byDay[day]!]..sort(_latestFirst),
        ),
    ];
  }

  static int _latestFirst(PeriodDetailItem a, PeriodDetailItem b) {
    final aAt = a.occurredAt ?? a.transactionDate;
    final bAt = b.occurredAt ?? b.transactionDate;
    final byTime = bAt.compareTo(aAt);
    if (byTime != 0) return byTime;
    return b.amount.compareTo(a.amount);
  }

  static int _byAmountThenLast(_MutableBucket a, _MutableBucket b) {
    // «Sin método» va al final aunque sume más: no es un método.
    final aLast = a.key == _noMethodKey ? 1 : 0;
    final bLast = b.key == _noMethodKey ? 1 : 0;
    if (aLast != bLast) return aLast - bLast;
    return b.amount.compareTo(a.amount);
  }

  static ({String key, String label}) _rawTopOf(
    PeriodDetailItem item,
    PeriodDetailKind kind,
  ) {
    if (kind.isIncome) {
      if (item.sourceType != 'sales_payment') {
        return (key: 'source:${item.sourceType}', label: 'Otros ingresos');
      }
      final code = item.paymentMethodCode;
      if (code != null &&
          PaymentMethod.isCardMethod(
            code: code,
            instrument: PaymentCardInstrument.fromDatabase(
              item.paymentInstrument,
            ),
          )) {
        return (key: cardKey, label: 'Tarjetas');
      }
      final name = item.description.trim();
      if (code == null && (name.isEmpty || name == 'Pago recibido')) {
        return (key: _noMethodKey, label: 'Sin método');
      }
      return (key: 'method:${code ?? name}', label: name);
    }

    switch (item.sourceType) {
      case 'purchase_payment':
        return (key: 'supplier', label: 'Proveedores');
      case 'employee_advance':
        return (key: 'advance', label: 'Anticipos al personal');
    }
    final label = item.secondaryText.trim();
    final identity = item.accountId ?? item.accountCode ?? label;
    return (
      key: 'account:$identity',
      label: label.isEmpty ? 'Sin clasificar' : label,
    );
  }

  static ({String key, String label})? _childOf(
    PeriodDetailItem item,
    PeriodDetailKind kind,
  ) {
    if (_rawTopOf(item, kind).key != cardKey) return null;
    return switch (PaymentCardInstrument.fromDatabase(item.paymentInstrument)) {
      PaymentCardInstrument.debit => (key: 'card:debit', label: 'Débito'),
      PaymentCardInstrument.credit => (key: 'card:credit', label: 'Crédito'),
      PaymentCardInstrument.prepaid => (key: 'card:prepaid', label: 'Prepago'),
      PaymentCardInstrument.unknown => (
          key: 'card:unknown',
          label: 'Sin distinguir',
        ),
    };
  }
}

class _MutableBucket {
  _MutableBucket(this.key, this.label);

  final String key;
  final String label;
  double amount = 0;
  int count = 0;
  final Map<String, _MutableBucket> children = {};

  void add(double value) {
    amount += value;
    count += 1;
  }

  PeriodDetailBucket freeze() {
    final frozenChildren = children.values.toList()
      ..sort((a, b) => b.amount.compareTo(a.amount));
    return PeriodDetailBucket(
      key: key,
      label: label,
      amount: amount,
      count: count,
      children: [for (final child in frozenChildren) child.freeze()],
    );
  }
}
