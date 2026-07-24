import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../shared/utils/chilean_utils.dart';
import '../models/purchase_receipt.dart';

class PurchaseReceiptRecordsDropdown extends StatelessWidget {
  const PurchaseReceiptRecordsDropdown({
    super.key,
    required this.receipts,
    this.title = 'Recepciones de stock',
    this.onReceiptTap,
    this.initiallyExpanded = false,
  });

  final String title;
  final List<PurchaseReceiptRecord> receipts;
  final ValueChanged<PurchaseReceiptRecord>? onReceiptTap;
  final bool initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    if (receipts.isEmpty) return const SizedBox.shrink();

    return Container(
      key: const ValueKey('purchase-receipt-records-dropdown'),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFDCE3EF)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: initiallyExpanded,
          tilePadding: const EdgeInsets.symmetric(horizontal: 14),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
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
                  receipts.length.toString(),
                  style: const TextStyle(
                    color: Color(0xFF2563EB),
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          children: [
            PurchaseReceiptRecordsTable(
              receipts: receipts,
              onReceiptTap: onReceiptTap,
            ),
          ],
        ),
      ),
    );
  }
}

class PurchaseReceiptRecordsTable extends StatelessWidget {
  const PurchaseReceiptRecordsTable({
    super.key,
    required this.receipts,
    required this.onReceiptTap,
  });

  final List<PurchaseReceiptRecord> receipts;
  final ValueChanged<PurchaseReceiptRecord>? onReceiptTap;

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
                const _ReceiptHeaderRow(),
                for (final receipt in receipts)
                  _ReceiptDataRow(
                    receipt: receipt,
                    onTap: onReceiptTap == null
                        ? null
                        : () => onReceiptTap!(receipt),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ReceiptHeaderRow extends StatelessWidget {
  const _ReceiptHeaderRow();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      key: ValueKey('purchase-receipt-records-header'),
      height: 38,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Color(0xFFF6F8FC),
          border: Border(
            bottom: BorderSide(color: Color(0xFFE2E8F0)),
          ),
        ),
        child: Row(
          children: [
            _HeaderCell('FECHA', flex: 12),
            _HeaderCell('N° RECEPCIÓN', flex: 17),
            _HeaderCell('GUÍA / REFERENCIA', flex: 19),
            _HeaderCell('ESTADO', flex: 13),
            _HeaderCell('UBICACIÓN', flex: 18),
            _HeaderCell('ACEPTADO', flex: 10, alignEnd: true),
            _HeaderCell('DIFERENCIA', flex: 11, alignEnd: true),
          ],
        ),
      ),
    );
  }
}

class _ReceiptDataRow extends StatelessWidget {
  const _ReceiptDataRow({
    required this.receipt,
    required this.onTap,
  });

  final PurchaseReceiptRecord receipt;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final isPosted = receipt.status == 'posted';
    return Container(
      height: 38,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(color: Color(0xFFE2E8F0)),
        ),
      ),
      child: Row(
        children: [
          _BodyCell(
            ChileanUtils.formatDate(receipt.receivedAt.toLocal()),
            flex: 12,
          ),
          _BodyCell(
            receipt.number,
            flex: 17,
            isLink: true,
            onTap: onTap,
          ),
          _BodyCell(
            _textOrDash(receipt.deliveryReference),
            flex: 19,
          ),
          _ReceiptStatusCell(
            isPosted ? 'Registrada' : 'Anulada',
            flex: 13,
            isPosted: isPosted,
          ),
          _BodyCell(
            _textOrDash(receipt.locationLabel),
            flex: 18,
          ),
          _BodyCell(
            receipt.acceptedQuantity.toString(),
            flex: 10,
            alignEnd: true,
            isStrong: true,
          ),
          _BodyCell(
            receipt.discrepancyQuantity.toString(),
            flex: 11,
            alignEnd: true,
            color: receipt.discrepancyQuantity > 0
                ? const Color(0xFFD97706)
                : const Color(0xFF1F2937),
            isStrong: receipt.discrepancyQuantity > 0,
          ),
        ],
      ),
    );
  }
}

class _HeaderCell extends StatelessWidget {
  const _HeaderCell(
    this.text, {
    required this.flex,
    this.alignEnd = false,
  });

  final String text;
  final int flex;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: flex,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Align(
          alignment: alignEnd ? Alignment.centerRight : Alignment.centerLeft,
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFF64748B),
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.2,
            ),
          ),
        ),
      ),
    );
  }
}

class _BodyCell extends StatelessWidget {
  const _BodyCell(
    this.text, {
    required this.flex,
    this.alignEnd = false,
    this.color = const Color(0xFF1F2937),
    this.isStrong = false,
    this.isLink = false,
    this.onTap,
  });

  final String text;
  final int flex;
  final bool alignEnd;
  final Color color;
  final bool isStrong;
  final bool isLink;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final textStyle = TextStyle(
      color: isLink ? const Color(0xFF2563EB) : color,
      fontSize: 12,
      fontWeight: isStrong ? FontWeight.w800 : FontWeight.w500,
      decoration: isLink && onTap != null ? TextDecoration.underline : null,
      decorationColor: const Color(0xFF2563EB),
    );
    Widget content = Text(
      text,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: textStyle,
    );
    if (onTap != null) {
      content = Tooltip(
        message: 'Abrir recepción',
        child: Semantics(
          button: true,
          label: 'Abrir recepción $text',
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(3),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 1),
              child: content,
            ),
          ),
        ),
      );
    }

    return Expanded(
      flex: flex,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        child: Align(
          alignment: alignEnd ? Alignment.centerRight : Alignment.centerLeft,
          child: content,
        ),
      ),
    );
  }
}

class _ReceiptStatusCell extends StatelessWidget {
  const _ReceiptStatusCell(
    this.text, {
    required this.flex,
    required this.isPosted,
  });

  final String text;
  final int flex;
  final bool isPosted;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: flex,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color:
                  isPosted ? const Color(0xFF16A34A) : const Color(0xFFDC2626),
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

String _textOrDash(String? value) {
  final text = value?.trim();
  return text == null || text.isEmpty ? '—' : text;
}
