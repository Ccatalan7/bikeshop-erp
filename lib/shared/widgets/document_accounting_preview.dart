import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/document_accounting_context_service.dart';
import '../utils/chilean_utils.dart';

class DocumentPaperStatus {
  final String label;
  final Color foreground;
  final Color background;
  final Color border;

  const DocumentPaperStatus({
    required this.label,
    required this.foreground,
    required this.background,
    required this.border,
  });
}

class DocumentPaperShell extends StatelessWidget {
  final double width;
  final DocumentPaperStatus? status;
  final Widget child;

  const DocumentPaperShell({
    super.key,
    required this.width,
    required this.child,
    this.status,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      constraints: const BoxConstraints(minHeight: 560),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          child,
          if (status != null)
            Positioned(
              left: 0,
              top: 0,
              child: _PaperStatusBadge(status: status!),
            ),
        ],
      ),
    );
  }
}

class _PaperStatusBadge extends StatelessWidget {
  final DocumentPaperStatus status;

  const _PaperStatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 190),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: status.background,
          border: Border(
            right: BorderSide(color: status.border),
            bottom: BorderSide(color: status.border),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Text(
            status.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: status.foreground,
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.7,
            ),
          ),
        ),
      ),
    );
  }
}

class DocumentPaymentsDropdown extends StatelessWidget {
  final String title;
  final List<DocumentPaymentRecord> payments;

  const DocumentPaymentsDropdown({
    super.key,
    required this.title,
    required this.payments,
  });

  @override
  Widget build(BuildContext context) {
    if (payments.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFDCE3EF)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Theme(
        data: theme.copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 14),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          initiallyExpanded: false,
          iconColor: const Color(0xFF475569),
          collapsedIconColor: const Color(0xFF475569),
          title: Row(
            children: [
              Flexible(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF334155),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  payments.length.toString(),
                  style: const TextStyle(
                    color: Color(0xFF2563EB),
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          children: [_PaymentRows(payments: payments)],
        ),
      ),
    );
  }
}

class DocumentJournalEntriesSection extends StatelessWidget {
  final List<DocumentJournalEntryRecord> entries;
  final String documentLabel;
  final String emptyReference;

  const DocumentJournalEntriesSection({
    super.key,
    required this.entries,
    required this.documentLabel,
    required this.emptyReference,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.only(top: 34),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _JournalHeader(),
          const SizedBox(height: 12),
          if (entries.isEmpty)
            _EmptyJournalState(reference: emptyReference)
          else
            ...entries.map(
              (entry) => Padding(
                padding: const EdgeInsets.only(bottom: 18),
                child: _JournalEntryTable(
                  entry: entry,
                  documentLabel: documentLabel,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class DocumentAccountingLoadingStrip extends StatelessWidget {
  const DocumentAccountingLoadingStrip({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 42,
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE2E8F0)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: 10),
          Text(
            'Cargando pagos y diario...',
            style: TextStyle(
              fontSize: 12,
              color: Color(0xFF64748B),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _PaymentRows extends StatelessWidget {
  final List<DocumentPaymentRecord> payments;

  const _PaymentRows({required this.payments});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const minTableWidth = 900.0;
        final tableWidth = constraints.hasBoundedWidth
            ? math.max(constraints.maxWidth, minTableWidth)
            : minTableWidth;

        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: tableWidth,
            child: Column(
              children: [
                _row(
                  children: const [
                    _HeaderCell('FECHA', flex: 1),
                    _HeaderCell('N° DE PAGO', flex: 1),
                    _HeaderCell('N° DE REFERENCIA', flex: 2),
                    _HeaderCell('ESTADO', flex: 1),
                    _HeaderCell('FORMA DE PAGO', flex: 2),
                    _HeaderCell('IMPORTE', flex: 1, alignRight: true),
                  ],
                  color: const Color(0xFFF6F8FC),
                ),
                ...payments.map((payment) {
                  return _row(
                    children: [
                      _BodyCell(ChileanUtils.formatDate(payment.date), flex: 1),
                      _BodyCell(payment.number, flex: 1, isLink: true),
                      _BodyCell(payment.reference ?? '-', flex: 2),
                      _StatusCell(payment.status, flex: 1),
                      _BodyCell(payment.methodName, flex: 2),
                      _BodyCell(
                        ChileanUtils.formatCurrency(payment.amount),
                        flex: 1,
                        alignRight: true,
                        isStrong: true,
                      ),
                    ],
                  );
                }),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _row({required List<Widget> children, Color? color}) {
    return Container(
      height: 38,
      decoration: BoxDecoration(
        color: color,
        border: const Border(
          bottom: BorderSide(color: Color(0xFFE2E8F0)),
        ),
      ),
      child: Row(children: children),
    );
  }
}

class _JournalHeader extends StatelessWidget {
  const _JournalHeader();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          decoration: const BoxDecoration(
            border: Border(
              bottom: BorderSide(color: Color(0xFFD8DEE9)),
            ),
          ),
          child: const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text(
              'Diario',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: Color(0xFF1E293B),
              ),
            ),
          ),
        ),
        const SizedBox(height: 9),
        Row(
          children: [
            const Flexible(
              child: Text(
                'El importe se muestra en su moneda base',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  color: Color(0xFF64748B),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFF2F7D20),
                borderRadius: BorderRadius.circular(2),
              ),
              child: const Text(
                'CLP',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _JournalEntryTable extends StatelessWidget {
  final DocumentJournalEntryRecord entry;
  final String documentLabel;

  const _JournalEntryTable({
    required this.entry,
    required this.documentLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE2E8F0)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    documentLabel,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF1E293B),
                    ),
                  ),
                ),
                Text(
                  entry.entryNumber,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ),
          LayoutBuilder(
            builder: (context, constraints) {
              const minTableWidth = 920.0;
              final tableWidth = constraints.hasBoundedWidth
                  ? math.max(constraints.maxWidth, minTableWidth)
                  : minTableWidth;

              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: tableWidth,
                  child: Column(
                    children: [
                      Container(
                        height: 36,
                        color: const Color(0xFFF6F8FC),
                        child: const Row(
                          children: [
                            _HeaderCell('CUENTA', flex: 5),
                            _HeaderCell('DÉBITO', flex: 2, alignRight: true),
                            _HeaderCell('CRÉDITO', flex: 2, alignRight: true),
                          ],
                        ),
                      ),
                      ...entry.lines.map((line) {
                        final account = [
                          line.accountCode,
                          line.accountName,
                        ].where((part) => part.trim().isNotEmpty).join('  ');
                        return Container(
                          constraints: const BoxConstraints(minHeight: 34),
                          decoration: const BoxDecoration(
                            border: Border(
                              bottom: BorderSide(color: Color(0xFFE2E8F0)),
                            ),
                          ),
                          child: Row(
                            children: [
                              _BodyCell(
                                account.isEmpty ? '-' : account,
                                flex: 5,
                              ),
                              _BodyCell(
                                line.debitAmount == 0
                                    ? '0'
                                    : ChileanUtils.formatCurrency(
                                        line.debitAmount,
                                      ),
                                flex: 2,
                                alignRight: true,
                              ),
                              _BodyCell(
                                line.creditAmount == 0
                                    ? '0'
                                    : ChileanUtils.formatCurrency(
                                        line.creditAmount,
                                      ),
                                flex: 2,
                                alignRight: true,
                              ),
                            ],
                          ),
                        );
                      }),
                      Container(
                        height: 38,
                        color: Colors.white,
                        child: Row(
                          children: [
                            const Spacer(flex: 5),
                            _BodyCell(
                              ChileanUtils.formatCurrency(entry.totalDebit),
                              flex: 2,
                              alignRight: true,
                              isStrong: true,
                            ),
                            _BodyCell(
                              ChileanUtils.formatCurrency(entry.totalCredit),
                              flex: 2,
                              alignRight: true,
                              isStrong: true,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _EmptyJournalState extends StatelessWidget {
  final String reference;

  const _EmptyJournalState({required this.reference});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE2E8F0)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Icon(
              Icons.receipt_long_outlined,
              size: 16,
              color: Color(0xFF64748B),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Sin asiento contable asociado para $reference.',
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF64748B),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeaderCell extends StatelessWidget {
  final String text;
  final int flex;
  final bool alignRight;

  const _HeaderCell(
    this.text, {
    required this.flex,
    this.alignRight = false,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: flex,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Align(
          alignment: alignRight ? Alignment.centerRight : Alignment.centerLeft,
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: Color(0xFF64748B),
              letterSpacing: 0.2,
            ),
          ),
        ),
      ),
    );
  }
}

class _BodyCell extends StatelessWidget {
  final String text;
  final int flex;
  final bool alignRight;
  final bool isStrong;
  final bool isLink;

  const _BodyCell(
    this.text, {
    required this.flex,
    this.alignRight = false,
    this.isStrong = false,
    this.isLink = false,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: flex,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        child: Align(
          alignment: alignRight ? Alignment.centerRight : Alignment.centerLeft,
          child: Text(
            text,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              fontWeight: isStrong ? FontWeight.w800 : FontWeight.w500,
              color: isLink ? const Color(0xFF2563EB) : const Color(0xFF1F2937),
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusCell extends StatelessWidget {
  final String text;
  final int flex;

  const _StatusCell(this.text, {required this.flex});

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(text);
    return Expanded(
      flex: flex,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            text,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }

  Color _statusColor(String value) {
    final normalized = value.toLowerCase();
    if (normalized.contains('pend')) return const Color(0xFFD97706);
    if (normalized.contains('parcial')) return const Color(0xFF7C3AED);
    if (normalized.contains('anulad')) return const Color(0xFFDC2626);
    if (normalized.contains('program')) return const Color(0xFF475569);
    return const Color(0xFF16A34A);
  }
}
