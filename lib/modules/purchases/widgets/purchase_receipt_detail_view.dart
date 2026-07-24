import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../shared/utils/chilean_utils.dart';
import '../models/purchase_invoice.dart';
import '../models/purchase_receipt.dart';
import '../models/purchase_receipt_resolution.dart';
import 'purchase_receipt_resolution_register.dart';

class PurchaseReceiptDetailView extends StatelessWidget {
  const PurchaseReceiptDetailView({
    super.key,
    required this.receipt,
    required this.invoice,
    this.onClose,
    this.onRefresh,
    this.onOpenInvoice,
    this.resolutionCases = const [],
    this.resolving = false,
    this.onResolveCase,
    this.onOpenAllocation,
    this.onResolutionDocumentTap,
    this.onVoidLoss,
    this.productImageUrls = const {},
  });

  final PurchaseReceiptDetailRecord receipt;
  final PurchaseInvoice invoice;
  final VoidCallback? onClose;
  final Future<void> Function()? onRefresh;
  final VoidCallback? onOpenInvoice;
  final List<PurchaseReceiptResolutionCase> resolutionCases;
  final bool resolving;
  final ValueChanged<PurchaseReceiptResolutionCase>? onResolveCase;
  final ValueChanged<PurchaseReceiptResolutionAllocation>? onOpenAllocation;
  final PurchaseReceiptResolutionDocumentTap? onResolutionDocumentTap;
  final ValueChanged<PurchaseReceiptResolutionAllocation>? onVoidLoss;
  final Map<String, String> productImageUrls;

  @override
  Widget build(BuildContext context) {
    final baseTheme = Theme.of(context);
    final detailTheme = baseTheme.copyWith(
      colorScheme: baseTheme.colorScheme.copyWith(
        primary: _ReceiptDetailPalette.ink,
        secondary: _ReceiptDetailPalette.ink,
        surface: _ReceiptDetailPalette.surface,
        onSurface: _ReceiptDetailPalette.text,
        onSurfaceVariant: _ReceiptDetailPalette.muted,
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: _ReceiptDetailPalette.ink,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: _ReceiptDetailPalette.ink,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(5),
          ),
        ),
      ),
    );

    return Theme(
      data: detailTheme,
      child: ColoredBox(
        color: _ReceiptDetailPalette.canvas,
        child: Column(
          children: [
            _DetailHeader(
              receipt: receipt,
              invoice: invoice,
              resolutionCases: resolutionCases,
              onClose: onClose,
              onRefresh: onRefresh,
              onOpenInvoice: onOpenInvoice,
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: onRefresh ?? () async {},
                color: _ReceiptDetailPalette.ink,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _ReceiptSummary(receipt: receipt),
                      _ReceiptLineTable(
                        lines: receipt.lines,
                        productImageUrls: productImageUrls,
                      ),
                      if (resolutionCases.isNotEmpty)
                        _ReceiptResolutionSection(
                          cases: resolutionCases,
                          resolving: resolving,
                          onResolveCase: onResolveCase,
                          onOpenAllocation: onOpenAllocation,
                          onResolutionDocumentTap: onResolutionDocumentTap,
                          onVoidLoss: onVoidLoss,
                        ),
                      if (_hasText(receipt.notes))
                        _DocumentNotes(notes: receipt.notes!.trim()),
                      if (!receipt.canVoid) _VoidEvidence(receipt: receipt),
                      _TraceEvidence(receipt: receipt),
                      const SizedBox(height: 28),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReceiptDetailPalette {
  const _ReceiptDetailPalette._();

  static const canvas = Color(0xFFF6F8FA);
  static const surface = Color(0xFFFFFFFF);
  static const surfaceRaised = Color(0xFFF7F9FA);
  static const tableHeader = Color(0xFFF1F4F6);
  static const border = Color(0xFFD8DEE3);
  static const borderSoft = Color(0xFFE3E8EC);
  static const ink = Color(0xFF235466);
  static const positive = Color(0xFF2F6F62);
  static const warning = Color(0xFF8A5B14);
  static const danger = Color(0xFF874B4E);
  static const dangerSoft = Color(0xFFF8F3F3);
  static const text = Color(0xFF20262C);
  static const textSecondary = Color(0xFF37434B);
  static const muted = Color(0xFF68747D);
}

class _DetailHeader extends StatelessWidget {
  const _DetailHeader({
    required this.receipt,
    required this.invoice,
    required this.resolutionCases,
    required this.onClose,
    required this.onRefresh,
    required this.onOpenInvoice,
  });

  final PurchaseReceiptDetailRecord receipt;
  final PurchaseInvoice invoice;
  final List<PurchaseReceiptResolutionCase> resolutionCases;
  final VoidCallback? onClose;
  final Future<void> Function()? onRefresh;
  final VoidCallback? onOpenInvoice;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 920;
        final identity = _ReceiptIdentity(
          receipt: receipt,
          invoice: invoice,
        );
        final controls = _HeaderControls(
          receipt: receipt,
          resolutionCases: resolutionCases,
          onRefresh: onRefresh,
          onOpenInvoice: onOpenInvoice,
        );

        return Semantics(
          container: true,
          label: 'Detalle de la recepción ${receipt.number}',
          child: Container(
            constraints: BoxConstraints(minHeight: compact ? 104 : 72),
            padding: EdgeInsets.fromLTRB(
              compact ? 12 : 16,
              8,
              compact ? 8 : 12,
              8,
            ),
            decoration: const BoxDecoration(
              color: _ReceiptDetailPalette.surface,
              border: Border(
                bottom: BorderSide(color: _ReceiptDetailPalette.border),
              ),
            ),
            child: compact
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(child: identity),
                          if (onClose != null)
                            IconButton(
                              onPressed: onClose,
                              tooltip: 'Cerrar',
                              icon: const Icon(Icons.close, size: 20),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: controls,
                      ),
                    ],
                  )
                : Row(
                    children: [
                      Expanded(child: identity),
                      controls,
                      if (onClose != null) ...[
                        const SizedBox(width: 6),
                        IconButton(
                          onPressed: onClose,
                          tooltip: 'Cerrar',
                          icon: const Icon(Icons.close, size: 20),
                        ),
                      ],
                    ],
                  ),
          ),
        );
      },
    );
  }
}

class _ReceiptIdentity extends StatelessWidget {
  const _ReceiptIdentity({
    required this.receipt,
    required this.invoice,
  });

  final PurchaseReceiptDetailRecord receipt;
  final PurchaseInvoice invoice;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(
          Icons.inventory_2_outlined,
          size: 21,
          color: _ReceiptDetailPalette.ink,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'RECEPCIÓN DE COMPRA',
                style: TextStyle(
                  color: _ReceiptDetailPalette.ink,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.7,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                'Recepción ${receipt.number}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: _ReceiptDetailPalette.text,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                'Factura ${invoice.invoiceNumber} · '
                '${invoice.supplierName ?? 'Proveedor sin nombre'}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: _ReceiptDetailPalette.muted,
                  fontSize: 12.5,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _HeaderControls extends StatelessWidget {
  const _HeaderControls({
    required this.receipt,
    required this.resolutionCases,
    required this.onRefresh,
    required this.onOpenInvoice,
  });

  final PurchaseReceiptDetailRecord receipt;
  final List<PurchaseReceiptResolutionCase> resolutionCases;
  final Future<void> Function()? onRefresh;
  final VoidCallback? onOpenInvoice;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (onOpenInvoice != null)
          TextButton.icon(
            onPressed: onOpenInvoice,
            icon: const Icon(Icons.receipt_long_outlined, size: 17),
            label: const Text('Abrir factura'),
          ),
        if (onRefresh != null)
          IconButton(
            onPressed: () => onRefresh!(),
            tooltip: 'Actualizar',
            icon: const Icon(Icons.refresh, size: 19),
          ),
        const SizedBox(width: 8),
        _ReceiptStatusLabel(status: receipt.status),
        if (resolutionCases.isNotEmpty) ...[
          const SizedBox(width: 14),
          _ResolutionStatusLabel(cases: resolutionCases),
        ],
      ],
    );
  }
}

class _ReceiptSummary extends StatelessWidget {
  const _ReceiptSummary({required this.receipt});

  final PurchaseReceiptDetailRecord receipt;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: const BoxDecoration(
        color: _ReceiptDetailPalette.surfaceRaised,
        border: Border(
          bottom: BorderSide(color: _ReceiptDetailPalette.border),
        ),
      ),
      child: Wrap(
        spacing: 32,
        runSpacing: 10,
        children: [
          _Metadata(
            label: 'FECHA DE RECEPCIÓN',
            value: ChileanUtils.formatDateTime(receipt.receivedAt.toLocal()),
          ),
          _Metadata(
            label: 'UBICACIÓN',
            value: _textOrDash(receipt.locationLabel),
          ),
          _Metadata(
            label: 'GUÍA / REFERENCIA',
            value: _textOrDash(receipt.deliveryReference),
          ),
          _Metadata(
            label: 'ACEPTADO',
            value: '${receipt.acceptedQuantity} un.',
          ),
          _Metadata(
            label: 'DIFERENCIA',
            value: '${receipt.discrepancyQuantity} un.',
            valueColor: receipt.discrepancyQuantity > 0
                ? _ReceiptDetailPalette.warning
                : _ReceiptDetailPalette.positive,
          ),
        ],
      ),
    );
  }
}

class _Metadata extends StatelessWidget {
  const _Metadata({
    required this.label,
    required this.value,
    this.valueColor,
  });

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 128, maxWidth: 230),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: _ReceiptDetailPalette.muted,
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: valueColor ?? _ReceiptDetailPalette.text,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _ReceiptLineTable extends StatefulWidget {
  const _ReceiptLineTable({
    required this.lines,
    required this.productImageUrls,
  });

  final List<PurchaseReceiptLineRecord> lines;
  final Map<String, String> productImageUrls;

  @override
  State<_ReceiptLineTable> createState() => _ReceiptLineTableState();
}

class _ReceiptLineTableState extends State<_ReceiptLineTable> {
  final ScrollController _horizontalController = ScrollController();

  @override
  void dispose() {
    _horizontalController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
            child: Row(
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'DETALLE POR PRODUCTO',
                        style: TextStyle(
                          color: _ReceiptDetailPalette.textSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.4,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Cantidades inmutables registradas en esta recepción.',
                        style: TextStyle(
                          color: _ReceiptDetailPalette.muted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  '${widget.lines.length} '
                  '${widget.lines.length == 1 ? 'línea' : 'líneas'}',
                  style: const TextStyle(
                    color: _ReceiptDetailPalette.muted,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          LayoutBuilder(
            builder: (context, constraints) {
              final metrics = _ReceiptLineMetrics.forWidth(
                constraints.maxWidth.isFinite
                    ? constraints.maxWidth
                    : _ReceiptLineMetrics.minimumWidth,
              );
              return Container(
                decoration: const BoxDecoration(
                  color: _ReceiptDetailPalette.surface,
                  border: Border(
                    top: BorderSide(color: _ReceiptDetailPalette.border),
                    bottom: BorderSide(color: _ReceiptDetailPalette.border),
                  ),
                ),
                child: Scrollbar(
                  controller: _horizontalController,
                  thumbVisibility: true,
                  trackVisibility: true,
                  scrollbarOrientation: ScrollbarOrientation.bottom,
                  thickness: 7,
                  radius: const Radius.circular(3),
                  child: SingleChildScrollView(
                    controller: _horizontalController,
                    scrollDirection: Axis.horizontal,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: SizedBox(
                        width: metrics.totalWidth,
                        child: Column(
                          children: [
                            _LineHeader(metrics: metrics),
                            if (widget.lines.isEmpty)
                              const SizedBox(
                                height: 72,
                                child: Center(
                                  child: Text(
                                    'La recepción no contiene líneas.',
                                  ),
                                ),
                              )
                            else
                              for (final line in widget.lines)
                                _LineRow(
                                  line: line,
                                  metrics: metrics,
                                  imageUrl:
                                      widget.productImageUrls[line.productId],
                                ),
                          ],
                        ),
                      ),
                    ),
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

class _ReceiptLineMetrics {
  const _ReceiptLineMetrics({
    required this.product,
    required this.evidence,
  });

  static const minimumWidth = 980.0;
  static const ordered = 78.0;
  static const received = 92.0;
  static const difference = 92.0;

  final double product;
  final double evidence;

  factory _ReceiptLineMetrics.forWidth(double availableWidth) {
    final extra = math.max(0, availableWidth - minimumWidth);
    return _ReceiptLineMetrics(
      product: 326 + (extra * 0.52),
      evidence: 392 + (extra * 0.48),
    );
  }

  double get totalWidth => product + ordered + received + difference + evidence;
}

class _LineHeader extends StatelessWidget {
  const _LineHeader({required this.metrics});

  final _ReceiptLineMetrics metrics;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      decoration: const BoxDecoration(
        color: _ReceiptDetailPalette.tableHeader,
        border: Border(
          bottom: BorderSide(color: _ReceiptDetailPalette.border),
        ),
      ),
      child: Row(
        children: [
          _TableHeader('PRODUCTO', width: metrics.product),
          const _TableHeader(
            'PEDIDO',
            width: _ReceiptLineMetrics.ordered,
            alignEnd: true,
            tooltip: 'Cantidad incluida en la factura',
          ),
          const _TableHeader(
            'RECIBIDO',
            width: _ReceiptLineMetrics.received,
            alignEnd: true,
            tooltip: 'Cantidad aceptada físicamente en esta recepción',
          ),
          const _TableHeader(
            'DIFERENCIA',
            width: _ReceiptLineMetrics.difference,
            alignEnd: true,
            tooltip: 'Cantidad dañada, rechazada o faltante registrada ahora',
          ),
          _TableHeader(
            'MOTIVO / EVIDENCIA',
            width: metrics.evidence,
          ),
        ],
      ),
    );
  }
}

class _LineRow extends StatelessWidget {
  const _LineRow({
    required this.line,
    required this.metrics,
    required this.imageUrl,
  });

  final PurchaseReceiptLineRecord line;
  final _ReceiptLineMetrics metrics;
  final String? imageUrl;

  @override
  Widget build(BuildContext context) {
    final history = <String>[
      _treatmentLabel(line.purchaseTreatment),
      if (line.previouslyReceivedQuantity > 0)
        'Recibido antes: ${line.previouslyReceivedQuantity}',
      'Costo unit.: ${ChileanUtils.formatCurrency(line.unitCost)}',
    ];

    return Container(
      constraints: const BoxConstraints(minHeight: 76),
      decoration: const BoxDecoration(
        color: _ReceiptDetailPalette.surface,
        border: Border(
          bottom: BorderSide(color: _ReceiptDetailPalette.borderSoft),
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: metrics.product,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              child: Row(
                children: [
                  _ProductThumbnail(
                    key: ValueKey('purchase-receipt-thumbnail-${line.id}'),
                    imageUrl: imageUrl,
                    semanticLabel: line.productName,
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          line.productName,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: _ReceiptDetailPalette.text,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            height: 1.15,
                          ),
                        ),
                        if (_hasText(line.productSku)) ...[
                          const SizedBox(height: 2),
                          Text(
                            'SKU ${line.productSku!.trim()}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: _ReceiptDetailPalette.muted,
                              fontSize: 10.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                        const SizedBox(height: 2),
                        Text(
                          history.join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: _ReceiptDetailPalette.ink,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w500,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          _QuantityCell(
            line.expectedQuantity,
            width: _ReceiptLineMetrics.ordered,
          ),
          _QuantityCell(
            line.acceptedQuantity,
            width: _ReceiptLineMetrics.received,
            emphasized: true,
          ),
          _QuantityCell(
            line.discrepancyQuantity,
            width: _ReceiptLineMetrics.difference,
            warning: line.hasDiscrepancy,
          ),
          SizedBox(
            width: metrics.evidence,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: _LineEvidence(line: line),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProductThumbnail extends StatelessWidget {
  const _ProductThumbnail({
    super.key,
    required this.imageUrl,
    required this.semanticLabel,
  });

  static const size = 44.0;

  final String? imageUrl;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final source = imageUrl?.trim();
    const placeholder = ColoredBox(
      color: _ReceiptDetailPalette.surfaceRaised,
      child: Icon(
        Icons.inventory_2_outlined,
        size: 18,
        color: _ReceiptDetailPalette.muted,
      ),
    );

    Widget image = placeholder;
    if (source?.isNotEmpty == true) {
      if (source!.startsWith('asset:')) {
        image = Image.asset(
          source.substring('asset:'.length),
          fit: BoxFit.contain,
          semanticLabel: semanticLabel,
          errorBuilder: (_, __, ___) => placeholder,
        );
      } else {
        image = CachedNetworkImage(
          imageUrl: source,
          fit: BoxFit.contain,
          fadeInDuration: const Duration(milliseconds: 120),
          placeholder: (_, __) => placeholder,
          errorWidget: (_, __, ___) => placeholder,
        );
      }
    }

    return Semantics(
      image: true,
      label: 'Imagen de $semanticLabel',
      child: Container(
        width: size,
        height: size,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: _ReceiptDetailPalette.surface,
          border: Border.all(color: _ReceiptDetailPalette.border),
          borderRadius: BorderRadius.circular(5),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: image,
        ),
      ),
    );
  }
}

class _LineEvidence extends StatelessWidget {
  const _LineEvidence({required this.line});

  final PurchaseReceiptLineRecord line;

  @override
  Widget build(BuildContext context) {
    final facts = <String>[
      if (line.damagedQuantity > 0) 'Dañado ${line.damagedQuantity}',
      if (line.rejectedQuantity > 0) 'Rechazado ${line.rejectedQuantity}',
      if (line.shortageQuantity > 0) 'Faltante ${line.shortageQuantity}',
    ];
    final movementCount = line.movements.length;
    final movementLabel = movementCount == 0
        ? 'Sin movimiento de stock'
        : '$movementCount movimiento${movementCount == 1 ? '' : 's'} de stock';
    final secondaryEvidence = <String>[
      movementLabel,
      if (line.remainingQuantity > 0)
        'Saldo pendiente: ${line.remainingQuantity}',
    ].join(' · ');

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          facts.isEmpty ? 'Sin diferencia registrada' : facts.join(' · '),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: facts.isEmpty
                ? _ReceiptDetailPalette.positive
                : _ReceiptDetailPalette.warning,
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
          ),
        ),
        if (_hasText(line.discrepancyReason)) ...[
          const SizedBox(height: 2),
          Text(
            line.discrepancyReason!.trim(),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: _ReceiptDetailPalette.textSecondary,
              fontSize: 11.5,
            ),
          ),
        ],
        const SizedBox(height: 2),
        Text(
          secondaryEvidence,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: _ReceiptDetailPalette.muted,
            fontSize: 10.5,
          ),
        ),
      ],
    );
  }
}

class _QuantityCell extends StatelessWidget {
  const _QuantityCell(
    this.value, {
    required this.width,
    this.emphasized = false,
    this.warning = false,
  });

  final int value;
  final double width;
  final bool emphasized;
  final bool warning;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 9),
        child: Align(
          alignment: Alignment.centerRight,
          child: Text(
            value.toString(),
            style: TextStyle(
              color: warning
                  ? _ReceiptDetailPalette.warning
                  : emphasized
                      ? _ReceiptDetailPalette.text
                      : _ReceiptDetailPalette.textSecondary,
              fontSize: 12.5,
              fontWeight:
                  warning || emphasized ? FontWeight.w800 : FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ),
    );
  }
}

class _TableHeader extends StatelessWidget {
  const _TableHeader(
    this.text, {
    required this.width,
    this.alignEnd = false,
    this.tooltip,
  });

  final String text;
  final double width;
  final bool alignEnd;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Tooltip(
        message: tooltip ?? text,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 9),
          child: Align(
            alignment: alignEnd ? Alignment.centerRight : Alignment.centerLeft,
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.clip,
              textAlign: alignEnd ? TextAlign.right : TextAlign.left,
              style: const TextStyle(
                color: _ReceiptDetailPalette.ink,
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.25,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ReceiptResolutionSection extends StatelessWidget {
  const _ReceiptResolutionSection({
    required this.cases,
    required this.resolving,
    required this.onResolveCase,
    required this.onOpenAllocation,
    required this.onResolutionDocumentTap,
    required this.onVoidLoss,
  });

  final List<PurchaseReceiptResolutionCase> cases;
  final bool resolving;
  final ValueChanged<PurchaseReceiptResolutionCase>? onResolveCase;
  final ValueChanged<PurchaseReceiptResolutionAllocation>? onOpenAllocation;
  final PurchaseReceiptResolutionDocumentTap? onResolutionDocumentTap;
  final ValueChanged<PurchaseReceiptResolutionAllocation>? onVoidLoss;

  @override
  Widget build(BuildContext context) {
    final openCount = cases.where((item) => item.isOpen).length;
    final resolvedCount = cases.where((item) => item.isResolved).length;
    final summary = openCount > 0
        ? '$openCount ${openCount == 1 ? 'pendiente' : 'pendientes'}'
        : resolvedCount > 0
            ? '$resolvedCount ${resolvedCount == 1 ? 'resuelta' : 'resueltas'}'
            : '${cases.length} sin efecto';

    return Container(
      margin: const EdgeInsets.only(top: 18),
      decoration: const BoxDecoration(
        color: _ReceiptDetailPalette.surface,
        border: Border(
          top: BorderSide(color: _ReceiptDetailPalette.border),
          bottom: BorderSide(color: _ReceiptDetailPalette.border),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
            color: _ReceiptDetailPalette.surfaceRaised,
            child: Row(
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'DIFERENCIAS Y RESOLUCIONES',
                        style: TextStyle(
                          color: _ReceiptDetailPalette.textSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.35,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'La recepción física y su resolución comercial '
                        'se registran por separado.',
                        style: TextStyle(
                          color: _ReceiptDetailPalette.muted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  summary,
                  style: TextStyle(
                    color: openCount > 0
                        ? _ReceiptDetailPalette.warning
                        : _ReceiptDetailPalette.positive,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          for (final resolutionCase in cases)
            _ResolutionCaseRow(
              resolutionCase: resolutionCase,
              resolving: resolving,
              onResolve: onResolveCase == null
                  ? null
                  : () => onResolveCase!(resolutionCase),
              onOpenAllocation: onOpenAllocation,
              onResolutionDocumentTap: onResolutionDocumentTap,
              onVoidLoss: onVoidLoss,
            ),
        ],
      ),
    );
  }
}

class _ResolutionCaseRow extends StatelessWidget {
  const _ResolutionCaseRow({
    required this.resolutionCase,
    required this.resolving,
    required this.onResolve,
    required this.onOpenAllocation,
    required this.onResolutionDocumentTap,
    required this.onVoidLoss,
  });

  final PurchaseReceiptResolutionCase resolutionCase;
  final bool resolving;
  final VoidCallback? onResolve;
  final ValueChanged<PurchaseReceiptResolutionAllocation>? onOpenAllocation;
  final PurchaseReceiptResolutionDocumentTap? onResolutionDocumentTap;
  final ValueChanged<PurchaseReceiptResolutionAllocation>? onVoidLoss;

  @override
  Widget build(BuildContext context) {
    final open = resolutionCase.isOpen;
    final resolved = resolutionCase.isResolved;
    final statusLabel = open
        ? '${resolutionCase.openQuantity} de '
            '${resolutionCase.reportedQuantity} pendientes'
        : resolved
            ? '${resolutionCase.resolvedQuantity} de '
                '${resolutionCase.reportedQuantity} resueltas'
            : 'Caso sin efecto';
    final statusTone = open
        ? _ReceiptDetailPalette.warning
        : resolved
            ? _ReceiptDetailPalette.positive
            : _ReceiptDetailPalette.muted;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
      decoration: const BoxDecoration(
        border: Border(
          top: BorderSide(color: _ReceiptDetailPalette.borderSoft),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 760;
              final identity = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${resolutionCase.number} · ${resolutionCase.productName}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _ReceiptDetailPalette.text,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    [
                      resolutionCase.kind.label,
                      if (_hasText(resolutionCase.purchaseReceiptNumber))
                        resolutionCase.purchaseReceiptNumber!.trim(),
                      if (_hasText(resolutionCase.productSku))
                        'SKU ${resolutionCase.productSku!.trim()}',
                    ].join(' · '),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _ReceiptDetailPalette.muted,
                      fontSize: 11.5,
                    ),
                  ),
                ],
              );
              final status = Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _InlineStatus(label: statusLabel, tone: statusTone),
                  if (open && onResolve != null) ...[
                    const SizedBox(width: 10),
                    FilledButton(
                      onPressed: resolving ? null : onResolve,
                      child: const Text('Resolver'),
                    ),
                  ],
                ],
              );

              if (compact) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    identity,
                    const SizedBox(height: 8),
                    Align(alignment: Alignment.centerLeft, child: status),
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(child: identity),
                  const SizedBox(width: 16),
                  status,
                ],
              );
            },
          ),
          if (_hasText(resolutionCase.discrepancyReason)) ...[
            const SizedBox(height: 7),
            Text(
              'Observación: ${resolutionCase.discrepancyReason!.trim()}',
              style: const TextStyle(
                color: _ReceiptDetailPalette.textSecondary,
                fontSize: 11.5,
              ),
            ),
          ],
          if (resolutionCase.allocations.isEmpty) ...[
            const SizedBox(height: 8),
            Text(
              open
                  ? 'Pendiente de una resolución comercial u operativa.'
                  : 'No existe una resolución vigente vinculada.',
              style: const TextStyle(
                color: _ReceiptDetailPalette.muted,
                fontSize: 11.5,
              ),
            ),
          ] else
            for (final allocation in resolutionCase.allocations)
              _ResolutionAllocationRow(
                resolutionCase: resolutionCase,
                allocation: allocation,
                onOpenAllocation: onOpenAllocation,
                onDocumentTap: onResolutionDocumentTap,
                onVoidLoss: allocation.outcome ==
                            PurchaseReceiptResolutionOutcome.documentedLoss &&
                        allocation.isActive &&
                        onVoidLoss != null
                    ? () => onVoidLoss!(allocation)
                    : null,
              ),
        ],
      ),
    );
  }
}

class _ResolutionAllocationRow extends StatelessWidget {
  const _ResolutionAllocationRow({
    required this.resolutionCase,
    required this.allocation,
    required this.onOpenAllocation,
    required this.onDocumentTap,
    required this.onVoidLoss,
  });

  final PurchaseReceiptResolutionCase resolutionCase;
  final PurchaseReceiptResolutionAllocation allocation;
  final ValueChanged<PurchaseReceiptResolutionAllocation>? onOpenAllocation;
  final PurchaseReceiptResolutionDocumentTap? onDocumentTap;
  final VoidCallback? onVoidLoss;

  @override
  Widget build(BuildContext context) {
    final documents = _allocationDocuments(allocation);
    final statusLabel = allocation.outcome ==
            PurchaseReceiptResolutionOutcome.documentedLossReversal
        ? 'Reversa auditada'
        : allocation.isActive
            ? 'Vigente'
            : 'Revertida';
    final statusTone = allocation.outcome ==
            PurchaseReceiptResolutionOutcome.documentedLossReversal
        ? _ReceiptDetailPalette.muted
        : allocation.isActive
            ? _ReceiptDetailPalette.positive
            : _ReceiptDetailPalette.danger;

    return Container(
      margin: const EdgeInsets.only(top: 9),
      padding: const EdgeInsets.fromLTRB(12, 9, 10, 9),
      decoration: const BoxDecoration(
        color: _ReceiptDetailPalette.surfaceRaised,
        border: Border(
          left: BorderSide(
            color: _ReceiptDetailPalette.border,
            width: 2,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                '${allocation.outcome.label} · ${allocation.quantity} un.',
                style: const TextStyle(
                  color: _ReceiptDetailPalette.textSecondary,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
              _InlineStatus(label: statusLabel, tone: statusTone),
              if (onVoidLoss != null)
                TextButton(
                  onPressed: onVoidLoss,
                  child: const Text('Revertir'),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 12,
            runSpacing: 4,
            children: [
              for (final document in documents)
                _DocumentEvidence(
                  label: document.reference.label,
                  onTap: _documentTap(document),
                ),
            ],
          ),
          if (_hasText(allocation.reason)) ...[
            const SizedBox(height: 4),
            Text(
              'Motivo: ${allocation.reason!.trim()}',
              style: const TextStyle(
                color: _ReceiptDetailPalette.muted,
                fontSize: 11,
              ),
            ),
          ],
          if (_hasText(allocation.voidReason)) ...[
            const SizedBox(height: 3),
            Text(
              'Reversa: ${allocation.voidReason!.trim()}',
              style: const TextStyle(
                color: _ReceiptDetailPalette.danger,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }

  VoidCallback? _documentTap(_AllocationDocument document) {
    final reference = document.reference;
    if (!document.navigable || reference.id.isEmpty) return null;
    if (onDocumentTap != null) {
      return () => onDocumentTap!(
            resolutionCase,
            allocation,
            reference,
          );
    }
    if (document.legacyAllocationDestination && onOpenAllocation != null) {
      return () => onOpenAllocation!(allocation);
    }
    return null;
  }
}

class _DocumentEvidence extends StatelessWidget {
  const _DocumentEvidence({
    required this.label,
    required this.onTap,
  });

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    if (onTap == null) {
      return Text(
        label,
        style: const TextStyle(
          color: _ReceiptDetailPalette.textSecondary,
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
        ),
      );
    }
    return Semantics(
      button: true,
      label: 'Abrir $label',
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Text(
            label,
            style: const TextStyle(
              color: _ReceiptDetailPalette.ink,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              decoration: TextDecoration.underline,
              decorationColor: _ReceiptDetailPalette.ink,
            ),
          ),
        ),
      ),
    );
  }
}

class _DocumentNotes extends StatelessWidget {
  const _DocumentNotes({required this.notes});

  final String notes;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 18),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: const BoxDecoration(
        color: _ReceiptDetailPalette.surface,
        border: Border(
          top: BorderSide(color: _ReceiptDetailPalette.border),
          bottom: BorderSide(color: _ReceiptDetailPalette.border),
        ),
      ),
      child: Text.rich(
        TextSpan(
          children: [
            const TextSpan(
              text: 'Nota general: ',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            TextSpan(text: notes),
          ],
        ),
        style: const TextStyle(
          color: _ReceiptDetailPalette.textSecondary,
          fontSize: 12.5,
          height: 1.4,
        ),
      ),
    );
  }
}

class _VoidEvidence extends StatelessWidget {
  const _VoidEvidence({required this.receipt});

  final PurchaseReceiptDetailRecord receipt;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 18),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: const BoxDecoration(
        color: _ReceiptDetailPalette.dangerSoft,
        border: Border(
          top: BorderSide(color: Color(0xFFE2C9CA)),
          bottom: BorderSide(color: Color(0xFFE2C9CA)),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.history_outlined,
            size: 19,
            color: _ReceiptDetailPalette.danger,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Recepción anulada mediante reversa auditada',
                  style: TextStyle(
                    color: Color(0xFF713F42),
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  [
                    if (receipt.voidedAt != null)
                      ChileanUtils.formatDateTime(receipt.voidedAt!.toLocal()),
                    _textOrDash(receipt.voidReason),
                  ].join(' · '),
                  style: const TextStyle(
                    color: Color(0xFF714F51),
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TraceEvidence extends StatelessWidget {
  const _TraceEvidence({required this.receipt});

  final PurchaseReceiptDetailRecord receipt;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 18),
      decoration: const BoxDecoration(
        color: _ReceiptDetailPalette.surface,
        border: Border(
          top: BorderSide(color: _ReceiptDetailPalette.border),
          bottom: BorderSide(color: _ReceiptDetailPalette.border),
        ),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          key: const ValueKey('purchase-receipt-trace-disclosure'),
          initiallyExpanded: false,
          maintainState: false,
          tilePadding: const EdgeInsets.symmetric(horizontal: 20),
          childrenPadding: EdgeInsets.zero,
          iconColor: _ReceiptDetailPalette.ink,
          collapsedIconColor: _ReceiptDetailPalette.muted,
          title: const Text(
            'Trazabilidad técnica',
            style: TextStyle(
              color: _ReceiptDetailPalette.textSecondary,
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          subtitle: const Text(
            'IDs de operación y movimientos vinculados',
            style: TextStyle(
              color: _ReceiptDetailPalette.muted,
              fontSize: 11.5,
            ),
          ),
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
              decoration: const BoxDecoration(
                color: _ReceiptDetailPalette.surfaceRaised,
                border: Border(
                  top: BorderSide(color: _ReceiptDetailPalette.border),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _TraceRow(label: 'ID recepción', value: receipt.id),
                  _TraceRow(
                    label: 'Operación de registro',
                    value: receipt.operationId,
                  ),
                  _TraceRow(
                    label: 'Registrada',
                    value: ChileanUtils.formatDateTime(
                      receipt.createdAt.toLocal(),
                    ),
                  ),
                  if (_hasText(receipt.createdBy))
                    _TraceRow(
                      label: 'Registrada por',
                      value: receipt.createdBy!.trim(),
                    ),
                  if (_hasText(receipt.voidOperationId))
                    _TraceRow(
                      label: 'Operación de reversa',
                      value: receipt.voidOperationId!.trim(),
                    ),
                  if (_hasText(receipt.voidedBy))
                    _TraceRow(
                      label: 'Revertida por',
                      value: receipt.voidedBy!.trim(),
                    ),
                  _TraceRow(
                    label: 'Movimientos vinculados',
                    value: receipt.stockMovementCount.toString(),
                  ),
                  for (final line in receipt.lines) ...[
                    if (_hasText(line.stockMovementId))
                      _TraceRow(
                        label: '${line.productName} · movimiento principal',
                        value: line.stockMovementId!.trim(),
                      ),
                    for (final movement in line.movements)
                      _TraceRow(
                        label: '${line.productName} · '
                            '${_movementRoleLabel(movement.role)}',
                        value: '${movement.stockMovementId} · '
                            '${movement.quantity} un. · '
                            'producto ${movement.productId}',
                      ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TraceRow extends StatelessWidget {
  const _TraceRow({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 620;
        final labelWidget = Text(
          label,
          style: const TextStyle(
            color: _ReceiptDetailPalette.muted,
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
          ),
        );
        final valueWidget = SelectableText(
          value,
          style: const TextStyle(
            color: _ReceiptDetailPalette.textSecondary,
            fontSize: 11.5,
            fontFamily: 'monospace',
          ),
        );

        return Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: compact
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    labelWidget,
                    const SizedBox(height: 2),
                    valueWidget,
                  ],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(width: 210, child: labelWidget),
                    Expanded(child: valueWidget),
                  ],
                ),
        );
      },
    );
  }
}

class _ReceiptStatusLabel extends StatelessWidget {
  const _ReceiptStatusLabel({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final normalized = status.trim().toLowerCase();
    final (label, tone) = switch (normalized) {
      'posted' => ('Registrada', _ReceiptDetailPalette.positive),
      'voided' || 'cancelled' => ('Anulada', _ReceiptDetailPalette.danger),
      _ => (
          normalized.isEmpty ? 'Estado desconocido' : status,
          _ReceiptDetailPalette.muted,
        ),
    };
    return _InlineStatus(label: label, tone: tone);
  }
}

class _ResolutionStatusLabel extends StatelessWidget {
  const _ResolutionStatusLabel({required this.cases});

  final List<PurchaseReceiptResolutionCase> cases;

  @override
  Widget build(BuildContext context) {
    final openCount = cases.where((item) => item.isOpen).length;
    final resolvedCount = cases.where((item) => item.isResolved).length;
    if (openCount > 0) {
      return _InlineStatus(
        label: '$openCount '
            '${openCount == 1 ? 'diferencia pendiente' : 'diferencias pendientes'}',
        tone: _ReceiptDetailPalette.warning,
      );
    }
    if (resolvedCount > 0) {
      return const _InlineStatus(
        label: 'Diferencias resueltas',
        tone: _ReceiptDetailPalette.positive,
      );
    }
    return const _InlineStatus(
      label: 'Diferencias sin efecto',
      tone: _ReceiptDetailPalette.muted,
    );
  }
}

class _InlineStatus extends StatelessWidget {
  const _InlineStatus({
    required this.label,
    required this.tone,
  });

  final String label;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: tone,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: tone,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _AllocationDocument {
  const _AllocationDocument({
    required this.reference,
    required this.navigable,
    this.legacyAllocationDestination = false,
  });

  final PurchaseReceiptResolutionDocumentReference reference;
  final bool navigable;
  final bool legacyAllocationDestination;
}

List<_AllocationDocument> _allocationDocuments(
  PurchaseReceiptResolutionAllocation allocation,
) {
  final documents = <_AllocationDocument>[];
  switch (allocation.outcome) {
    case PurchaseReceiptResolutionOutcome.creditNote:
      documents.add(
        _AllocationDocument(
          reference: PurchaseReceiptResolutionDocumentReference(
            kind: PurchaseReceiptResolutionDocumentKind.creditNote,
            id: allocation.purchaseCreditNoteId ?? '',
            label: allocation.purchaseCreditNoteNumber ?? 'Nota de crédito',
          ),
          navigable: true,
          legacyAllocationDestination: true,
        ),
      );
      break;
    case PurchaseReceiptResolutionOutcome.laterDelivery:
      documents.add(
        _AllocationDocument(
          reference: PurchaseReceiptResolutionDocumentReference(
            kind: PurchaseReceiptResolutionDocumentKind.laterReceipt,
            id: allocation.laterPurchaseReceiptId ?? '',
            label: allocation.laterPurchaseReceiptNumber ?? 'Entrega posterior',
          ),
          navigable: true,
          legacyAllocationDestination: true,
        ),
      );
      break;
    case PurchaseReceiptResolutionOutcome.documentedLoss:
      documents.add(
        _AllocationDocument(
          reference: PurchaseReceiptResolutionDocumentReference(
            kind: PurchaseReceiptResolutionDocumentKind.documentedLoss,
            id: '',
            label: _hasText(allocation.lossJournalEntryNumber)
                ? 'Ajuste ${allocation.lossJournalEntryNumber!.trim()}'
                : 'Pérdida documentada',
          ),
          navigable: false,
        ),
      );
      break;
    case PurchaseReceiptResolutionOutcome.documentedLossReversal:
      documents.add(
        _AllocationDocument(
          reference: PurchaseReceiptResolutionDocumentReference(
            kind: PurchaseReceiptResolutionDocumentKind.documentedLossReversal,
            id: '',
            label: _hasText(allocation.lossJournalEntryNumber)
                ? 'Reversa ${allocation.lossJournalEntryNumber!.trim()}'
                : 'Reversa de pérdida',
          ),
          navigable: false,
        ),
      );
      break;
    case PurchaseReceiptResolutionOutcome.unknown:
      documents.add(
        const _AllocationDocument(
          reference: PurchaseReceiptResolutionDocumentReference(
            kind: PurchaseReceiptResolutionDocumentKind.documentedLoss,
            id: '',
            label: 'Resolución no reconocida',
          ),
          navigable: false,
        ),
      );
      break;
  }

  if (_hasText(allocation.supplierReturnNumber)) {
    documents.add(
      _AllocationDocument(
        reference: PurchaseReceiptResolutionDocumentReference(
          kind: PurchaseReceiptResolutionDocumentKind.supplierReturn,
          id: allocation.supplierReturnId ?? '',
          label: 'Devolución ${allocation.supplierReturnNumber!.trim()}',
        ),
        navigable: true,
      ),
    );
  }
  for (final refund in allocation.supplierRefunds) {
    documents.add(
      _AllocationDocument(
        reference: PurchaseReceiptResolutionDocumentReference(
          kind: PurchaseReceiptResolutionDocumentKind.supplierRefund,
          id: refund.id,
          label: 'Reembolso ${refund.number}',
        ),
        navigable: true,
      ),
    );
  }
  return documents;
}

String _treatmentLabel(String treatment) {
  return switch (treatment) {
    'inventory' => 'Inventario',
    'expense' => 'Gasto',
    'asset' => 'Activo',
    'service' => 'Servicio',
    _ => treatment,
  };
}

String _movementRoleLabel(String role) {
  return switch (role) {
    'accepted' => 'Aceptado',
    'component' => 'Componente',
    'reversal' => 'Reversa',
    _ => role.isEmpty ? 'Movimiento' : role,
  };
}

String _textOrDash(String? value) {
  final text = value?.trim();
  return text == null || text.isEmpty ? '—' : text;
}

bool _hasText(String? value) => value?.trim().isNotEmpty == true;
