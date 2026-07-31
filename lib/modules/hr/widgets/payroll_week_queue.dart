import 'package:flutter/material.dart';

import '../models/payroll_voucher.dart';
import 'payroll_format.dart';
import 'payroll_money_bar.dart';

/// Horizontal, chronological week strip for the payroll workspace.
///
/// Payroll is a backlog of weeks: one bank statement can settle several of
/// them, so the overview keeps the accumulated weeks visible side by side as
/// selectable summaries. The oldest pending week is the natural first task and
/// arrives already selected; the strip itself never opens detail inline.
class PayrollWeekQueue extends StatelessWidget {
  const PayrollWeekQueue({
    super.key,
    required this.vouchers,
    required this.selectedVoucherId,
    required this.onSelected,
    this.scrollController,
  });

  /// Strip height including its own padding.
  static const double stripHeight = 104;

  final List<PayrollVoucher> vouchers;
  final String? selectedVoucherId;
  final ValueChanged<PayrollVoucher> onSelected;
  final ScrollController? scrollController;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (vouchers.isEmpty) {
      return SizedBox(
        height: stripHeight,
        child: Center(
          child: Text(
            'No hay semanas en esta vista.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    return SizedBox(
      height: stripHeight,
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Four weeks side by side when the width allows it; below that the
          // strip scrolls horizontally with the same card geometry.
          const gap = 10.0;
          const horizontalPadding = 16.0;
          final available = constraints.maxWidth - horizontalPadding * 2;
          final targetCount = vouchers.length.clamp(1, 4);
          final rawWidth = (available - gap * (targetCount - 1)) / targetCount;
          final cardWidth = rawWidth.clamp(196.0, 300.0);

          return ListView.separated(
            controller: scrollController,
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(
              horizontalPadding,
              10,
              horizontalPadding,
              12,
            ),
            itemCount: vouchers.length,
            separatorBuilder: (_, __) => const SizedBox(width: gap),
            itemBuilder: (context, index) {
              final voucher = vouchers[index];
              return _WeekCard(
                voucher: voucher,
                width: cardWidth,
                isSelected:
                    voucher.id != null && voucher.id == selectedVoucherId,
                onTap: () => onSelected(voucher),
              );
            },
          );
        },
      ),
    );
  }
}

class _WeekCard extends StatelessWidget {
  const _WeekCard({
    required this.voucher,
    required this.width,
    required this.isSelected,
    required this.onTap,
  });

  final PayrollVoucher voucher;
  final double width;
  final bool isSelected;
  final VoidCallback onTap;

  double get _pending => voucher.lines
      .where((line) => line.isIncluded)
      .fold<double>(0, (sum, line) => sum + line.balance);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final stage = payrollStageFor(voucher.status);
    final range = payrollPeriodLabel(voucher);
    final pending = _pending;
    final hasPending = pending > 0.01;

    return Semantics(
      selected: isSelected,
      button: true,
      label: '$range. ${stage.label}. '
          '${hasPending ? 'Pendiente ${formatPayrollClp(pending)}.' : 'Sin saldo pendiente.'}',
      excludeSemantics: true,
      child: Material(
        color: isSelected
            ? theme.colorScheme.surfaceContainerHighest
            : theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            width: width,
            padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isSelected
                    ? theme.colorScheme.primary
                    : theme.colorScheme.outlineVariant,
                width: isSelected ? 1.5 : 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  range,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Row(
                  children: [
                    Icon(
                      stage.icon,
                      size: 13,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(
                        '${stage.label} · ${voucher.employeeCount} '
                        '${voucher.employeeCount == 1 ? 'persona' : 'personas'}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                hasPending
                    ? Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: formatPayrollClp(pending),
                              style: payrollMoneyTextStyle(
                                context,
                                emphasis: true,
                              ).copyWith(fontSize: 15),
                            ),
                            TextSpan(
                              text: '  pendiente',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      )
                    : Text(
                        'Sin saldo pendiente',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
