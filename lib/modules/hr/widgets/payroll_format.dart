import 'package:flutter/material.dart';

import '../models/payroll_voucher.dart';

/// How a voucher stage reads to a person, derived only from domain status.
///
/// The UI never invents a stage and never shows a settled/"conciliado" tone
/// before the server acknowledges an apply. There is deliberately no positive
/// accent for [PayrollVoucherStatus.paid] beyond the neutral brand role.
@immutable
class PayrollStageDescriptor {
  const PayrollStageDescriptor({
    required this.label,
    required this.meaning,
    required this.icon,
  });

  final String label;
  final String meaning;
  final IconData icon;
}

PayrollStageDescriptor payrollStageFor(PayrollVoucherStatus status) {
  return switch (status) {
    PayrollVoucherStatus.draft => const PayrollStageDescriptor(
        label: 'Borrador',
        meaning: 'Todavía no compromete dinero. Puedes ajustar la semana.',
        icon: Icons.edit_note_rounded,
      ),
    PayrollVoucherStatus.confirmed => const PayrollStageDescriptor(
        label: 'Confirmada',
        meaning: 'La obligación está reconocida. Falta registrar los pagos.',
        icon: Icons.assignment_turned_in_outlined,
      ),
    PayrollVoucherStatus.partial => const PayrollStageDescriptor(
        label: 'Pago parcial',
        meaning: 'Parte de la semana está pagada y queda saldo pendiente.',
        icon: Icons.incomplete_circle_rounded,
      ),
    PayrollVoucherStatus.paid => const PayrollStageDescriptor(
        label: 'Pagada',
        meaning: 'Todos los saldos de la semana quedaron en cero.',
        icon: Icons.done_all_rounded,
      ),
    PayrollVoucherStatus.voided => const PayrollStageDescriptor(
        label: 'Anulada',
        meaning: 'La semana fue anulada y no genera sueldos por pagar.',
        icon: Icons.block_rounded,
      ),
  };
}

const List<String> _payrollShortMonths = [
  'ene',
  'feb',
  'mar',
  'abr',
  'may',
  'jun',
  'jul',
  'ago',
  'sep',
  'oct',
  'nov',
  'dic',
];

/// Short Chilean week range, e.g. `21 – 27 jul`.
String formatPayrollWeekRange(DateTime start, DateTime end) {
  final startMonth = _payrollShortMonths[start.month - 1];
  final endMonth = _payrollShortMonths[end.month - 1];
  if (start.year == end.year && start.month == end.month) {
    return '${start.day} – ${end.day} $endMonth';
  }
  return '${start.day} $startMonth – ${end.day} $endMonth';
}

String formatPayrollDate(DateTime value) {
  final local = value.toLocal();
  return '${local.day} ${_payrollShortMonths[local.month - 1]} ${local.year}';
}

/// Resolves the display label of the voucher period.
String payrollPeriodLabel(PayrollVoucher voucher) {
  final label = voucher.periodLabel?.trim();
  if (label != null && label.isNotEmpty) return label;
  return formatPayrollWeekRange(voucher.periodStart, voucher.periodEnd);
}
