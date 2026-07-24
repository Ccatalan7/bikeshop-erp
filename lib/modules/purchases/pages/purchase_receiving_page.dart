import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import '../models/purchase_invoice.dart';
import '../models/purchase_receipt.dart';
import '../services/purchase_receiving_service.dart';

typedef PurchaseReceiptPreviousLoader = Future<Map<int, int>> Function(
  String invoiceId,
);
typedef PurchaseReceiptResolutionLoader = Future<Map<int, int>> Function(
  String invoiceId,
);
typedef PurchaseReceiptProductImageLoader = Future<Map<String, String>>
    Function(
  Iterable<String> productIds,
);
typedef PurchaseReceiptCreator = Future<PurchaseReceiptResult> Function({
  required String invoiceId,
  required List<PurchaseReceiptLineDraft> lines,
  required DateTime receivedAt,
  required String idempotencyKey,
  String? deliveryReference,
  String? locationLabel,
  String? notes,
});
typedef PurchaseReceiptCompleted = Future<void> Function(
  PurchaseReceiptResult result,
);

class _ReceiptPalette {
  const _ReceiptPalette({
    required this.canvas,
    required this.surface,
    required this.surfaceRaised,
    required this.tableHeader,
    required this.border,
    required this.ink,
    required this.positive,
    required this.warning,
    required this.warningSoft,
    required this.danger,
    required this.dangerSoft,
    required this.text,
    required this.muted,
  });

  final Color canvas;
  final Color surface;
  final Color surfaceRaised;
  final Color tableHeader;
  final Color border;
  final Color ink;
  final Color positive;
  final Color warning;
  final Color warningSoft;
  final Color danger;
  final Color dangerSoft;
  final Color text;
  final Color muted;

  static _ReceiptPalette of(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    if (dark) {
      return const _ReceiptPalette(
        canvas: Color(0xFF171C20),
        surface: Color(0xFF1C2328),
        surfaceRaised: Color(0xFF222A30),
        tableHeader: Color(0xFF26313A),
        border: Color(0xFF39444D),
        ink: Color(0xFF93BFCE),
        positive: Color(0xFF7FB9AA),
        warning: Color(0xFFE1B867),
        warningSoft: Color(0xFF30363A),
        danger: Color(0xFFD58C8C),
        dangerSoft: Color(0xFF422C2D),
        text: Color(0xFFF0F3F1),
        muted: Color(0xFFAFBAB7),
      );
    }
    return const _ReceiptPalette(
      canvas: Color(0xFFF6F8FA),
      surface: Color(0xFFFFFFFF),
      surfaceRaised: Color(0xFFF7F9FA),
      tableHeader: Color(0xFFF1F4F6),
      border: Color(0xFFD8DEE3),
      ink: Color(0xFF235466),
      positive: Color(0xFF2F6F62),
      warning: Color(0xFF996719),
      warningSoft: Color(0xFFF1F4F5),
      danger: Color(0xFF9B4D50),
      dangerSoft: Color(0xFFFAF1F2),
      text: Color(0xFF20262C),
      muted: Color(0xFF68747D),
    );
  }
}

class PurchaseReceivingWorkspace extends StatefulWidget {
  const PurchaseReceivingWorkspace({
    super.key,
    required this.invoice,
    required this.onCancel,
    required this.onCompleted,
    this.service,
    this.previousLoader,
    this.resolutionLoader,
    this.productImageLoader,
    this.receiptCreator,
  });

  final PurchaseInvoice invoice;
  final VoidCallback onCancel;
  final PurchaseReceiptCompleted onCompleted;
  final PurchaseReceivingService? service;
  final PurchaseReceiptPreviousLoader? previousLoader;
  final PurchaseReceiptResolutionLoader? resolutionLoader;
  final PurchaseReceiptProductImageLoader? productImageLoader;
  final PurchaseReceiptCreator? receiptCreator;

  @override
  State<PurchaseReceivingWorkspace> createState() =>
      _PurchaseReceivingWorkspaceState();
}

class _PurchaseReceivingWorkspaceState
    extends State<PurchaseReceivingWorkspace> {
  final _formKey = GlobalKey<FormState>();
  final _deliveryReference = TextEditingController();
  final _location = TextEditingController(text: 'Bodega principal');
  final _notes = TextEditingController();
  PurchaseReceivingService? _service;
  late String _idempotencyKey;
  List<PurchaseReceiptLineDraft> _lines = const [];
  DateTime _receivedAt = DateTime.now();
  String? _loadError;
  bool _loading = true;
  bool _submitting = false;

  PurchaseReceivingService get _receivingService =>
      _service ??= widget.service ?? PurchaseReceivingService();

  @override
  void initState() {
    super.initState();
    _idempotencyKey = const Uuid().v4();
    _load();
  }

  @override
  void didUpdateWidget(covariant PurchaseReceivingWorkspace oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.invoice.id != widget.invoice.id) {
      _idempotencyKey = const Uuid().v4();
      _deliveryReference.clear();
      _location.text = 'Bodega principal';
      _notes.clear();
      _receivedAt = DateTime.now();
      _load();
    }
  }

  @override
  void dispose() {
    _deliveryReference.dispose();
    _location.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final invoiceId = widget.invoice.id;
      if (invoiceId == null) {
        throw StateError('La factura aún no está guardada.');
      }
      final productIds = widget.invoice.items
          .map((item) => item.productId)
          .where((id) => id.isNotEmpty)
          .toList(growable: false);
      final previousFuture = (widget.previousLoader ??
          _receivingService.getPreviouslyReceivedByLine)(invoiceId);
      final resolutionsFuture = widget.resolutionLoader != null
          ? widget.resolutionLoader!(invoiceId)
          : widget.previousLoader != null
              ? Future<Map<int, int>>.value(const {})
              : _receivingService.getNonPhysicalResolutionsByLine(invoiceId);
      final imagesFuture = _loadProductImages(productIds);
      final previous = await previousFuture;
      final resolutions = await resolutionsFuture;
      final productImages = await imagesFuture;
      final lines = <PurchaseReceiptLineDraft>[];
      for (var index = 0; index < widget.invoice.items.length; index++) {
        final item = widget.invoice.items[index];
        if (item.quantity != item.quantity.roundToDouble()) {
          throw StateError(
            '${item.productName ?? 'Producto'} usa una cantidad fraccionaria. '
            'La recepción física exige unidades enteras.',
          );
        }
        final expected = item.quantity.toInt();
        final received = previous[index] ?? 0;
        final resolved = resolutions[index] ?? 0;
        if (received + resolved > expected) {
          throw StateError(
            '${item.productName ?? 'Producto'} registra ${received + resolved} '
            'unidades recibidas o resueltas sobre $expected esperadas.',
          );
        }
        lines.add(
          PurchaseReceiptLineDraft(
            lineIndex: index,
            productName: item.productName ?? item.description ?? 'Producto',
            productSku: item.productSku,
            productImageUrl: productImages[item.productId],
            expectedQuantity: expected,
            previouslyReceivedQuantity: received,
            previouslyResolvedQuantity: resolved,
            acceptedQuantity: expected - received - resolved,
          ),
        );
      }
      if (!mounted) return;
      setState(() {
        _lines = lines;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadError = error.toString();
        _loading = false;
      });
    }
  }

  Future<Map<String, String>> _loadProductImages(
    List<String> productIds,
  ) async {
    if (productIds.isEmpty) return const {};
    try {
      return await (widget.productImageLoader ??
          _receivingService.getProductImageUrls)(productIds);
    } catch (error) {
      debugPrint(
        'No se pudieron cargar miniaturas para la recepción: $error',
      );
      return const {};
    }
  }

  void _replaceLine(int position, PurchaseReceiptLineDraft line) {
    setState(() {
      final updated = List<PurchaseReceiptLineDraft>.from(_lines);
      updated[position] = line;
      _lines = updated;
    });
  }

  int get _acceptedTotal =>
      _lines.fold(0, (sum, line) => sum + line.acceptedQuantity);
  int get _previousTotal =>
      _lines.fold(0, (sum, line) => sum + line.previouslyReceivedQuantity);
  int get _previouslyResolvedTotal =>
      _lines.fold(0, (sum, line) => sum + line.previouslyResolvedQuantity);
  int get _remainingTotal =>
      _lines.fold(0, (sum, line) => sum + line.remainingAfter);
  bool get _alreadyComplete =>
      _lines.isNotEmpty && _lines.every((line) => line.remainingBefore == 0);

  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _receivedAt,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _receivedAt = DateTime(
        picked.year,
        picked.month,
        picked.day,
        _receivedAt.hour,
        _receivedAt.minute,
      );
    });
  }

  Future<void> _submit() async {
    if (_submitting || !_formKey.currentState!.validate()) return;
    final selected = _lines.where((line) => line.hasEffect).toList();
    if (selected.isEmpty) {
      _showError('No hay cantidades nuevas para registrar.');
      return;
    }
    for (final line in selected) {
      final error = line.validate();
      if (error != null) {
        _showError(error);
        return;
      }
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Registrar recepción'),
        content: Text(
          'Se incorporarán $_acceptedTotal unidades al inventario y '
          '$_remainingTotal quedarán registradas como diferencia abierta.\n\n'
          'Este paso no genera notas de crédito, pérdidas ni otras '
          'resoluciones. Esas decisiones se registran después, cuando exista '
          'un acuerdo con el proveedor.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Volver'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Registrar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _submitting = true);
    try {
      final creator = widget.receiptCreator ?? _receivingService.createReceipt;
      final result = await creator(
        invoiceId: widget.invoice.id!,
        lines: selected,
        receivedAt: _receivedAt,
        idempotencyKey: _idempotencyKey,
        deliveryReference: _deliveryReference.text,
        locationLabel: _location.text,
        notes: _notes.text,
      );
      if (mounted) await widget.onCompleted(result);
    } catch (error) {
      if (mounted) _showError(error.toString());
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _showError(String message) {
    final colorScheme = Theme.of(context).colorScheme;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: colorScheme.error,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = _ReceiptPalette.of(context);
    final receiptTheme = theme.copyWith(
      colorScheme: theme.colorScheme.copyWith(
        primary: palette.ink,
        secondary: palette.ink,
        surface: palette.surface,
        onSurface: palette.text,
        onSurfaceVariant: palette.muted,
      ),
      inputDecorationTheme: theme.inputDecorationTheme.copyWith(
        filled: true,
        fillColor: palette.surfaceRaised,
        hintStyle: theme.textTheme.bodyMedium?.copyWith(color: palette.muted),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(5),
          borderSide: BorderSide(color: palette.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(5),
          borderSide: BorderSide(color: palette.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(5),
          borderSide: BorderSide(color: palette.ink, width: 1.4),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: palette.ink,
          foregroundColor: const Color(0xFFF8FBFB),
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(5),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: palette.ink),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: palette.ink,
          side: BorderSide(color: palette.border),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(5),
          ),
        ),
      ),
    );
    return Theme(
      data: receiptTheme,
      child: ColoredBox(
        color: palette.canvas,
        child: Column(
          children: [
            _buildWorkspaceHeader(receiptTheme),
            Expanded(
              child: _loading
                  ? Center(
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: palette.ink,
                      ),
                    )
                  : _loadError != null
                      ? _ErrorState(message: _loadError!, onRetry: _load)
                      : Form(
                          key: _formKey,
                          child: Column(
                            children: [
                              _buildReceiptMeta(receiptTheme),
                              Expanded(child: _buildReceiptBody(receiptTheme)),
                            ],
                          ),
                        ),
            ),
            if (!_loading && _loadError == null) _buildFooter(receiptTheme),
          ],
        ),
      ),
    );
  }

  Widget _buildWorkspaceHeader(ThemeData theme) {
    final palette = _ReceiptPalette.of(context);
    return Container(
      height: 68,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: palette.surface,
        border: Border(bottom: BorderSide(color: palette.border)),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: _submitting ? null : widget.onCancel,
            icon: const Icon(Icons.arrow_back, size: 20),
            tooltip: 'Volver a la factura',
            style: IconButton.styleFrom(
              foregroundColor: palette.ink,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'RECEPCIÓN DE COMPRA',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: palette.ink,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  'Recepción de productos',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: palette.text,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  'Factura ${widget.invoice.invoiceNumber} · '
                  '${widget.invoice.supplierName ?? 'Sin proveedor'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: palette.muted,
                  ),
                ),
              ],
            ),
          ),
          _StatusLabel(
            label:
                widget.invoice.balance <= 0 ? 'PAGO REGISTRADO' : 'POR PAGAR',
            tone: widget.invoice.balance <= 0
                ? palette.positive
                : palette.warning,
          ),
        ],
      ),
    );
  }

  Widget _buildReceiptMeta(ThemeData theme) {
    final palette = _ReceiptPalette.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      decoration: BoxDecoration(
        color: palette.surface,
        border: Border(bottom: BorderSide(color: palette.border)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final singleColumn = constraints.maxWidth < 620;
          final twoColumns =
              constraints.maxWidth >= 620 && constraints.maxWidth < 980;
          final fieldWidth = singleColumn
              ? constraints.maxWidth
              : twoColumns
                  ? (constraints.maxWidth - 12) / 2
                  : null;
          final fields = [
            _LabeledField(
              label: 'Ubicación *',
              width: fieldWidth ?? 190,
              child: TextFormField(
                controller: _location,
                decoration: _fieldDecoration('Bodega principal'),
                validator: (value) => value?.trim().isEmpty ?? true
                    ? 'Indica una ubicación.'
                    : null,
              ),
            ),
            _LabeledField(
              label: 'Guía o referencia',
              width: fieldWidth ?? 190,
              child: TextFormField(
                controller: _deliveryReference,
                decoration: _fieldDecoration('Opcional'),
              ),
            ),
            _LabeledField(
              label: 'Fecha de recepción',
              width: fieldWidth ?? 150,
              child: OutlinedButton.icon(
                onPressed: _selectDate,
                icon: Icon(
                  Icons.calendar_today_outlined,
                  size: 15,
                  color: palette.ink,
                ),
                style: OutlinedButton.styleFrom(
                  backgroundColor: palette.surfaceRaised,
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  minimumSize: const Size.fromHeight(38),
                ),
                label: Text(
                  '${_receivedAt.day.toString().padLeft(2, '0')}/'
                  '${_receivedAt.month.toString().padLeft(2, '0')}/'
                  '${_receivedAt.year}',
                ),
              ),
            ),
            _LabeledField(
              label: 'Nota general',
              width: fieldWidth ??
                  math.max(220, constraints.maxWidth - 566).toDouble(),
              child: TextFormField(
                controller: _notes,
                decoration: _fieldDecoration('Opcional'),
              ),
            ),
          ];
          return Wrap(
            spacing: 12,
            runSpacing: 10,
            children: fields,
          );
        },
      ),
    );
  }

  InputDecoration _fieldDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      isDense: true,
      filled: true,
      floatingLabelBehavior: FloatingLabelBehavior.never,
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
    );
  }

  Widget _buildReceiptBody(ThemeData theme) {
    final palette = _ReceiptPalette.of(context);
    return Column(
      children: [
        Container(
          color: palette.surface,
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 9),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Detalle de recepción',
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: palette.text,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _alreadyComplete
                          ? 'Todas las líneas ya tienen recepción completa.'
                          : 'Indica cuánto llegó. Si existe una diferencia, '
                              'selecciona únicamente su motivo.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: palette.muted,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                '${_lines.length} líneas',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: palette.ink,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _ReceiptGrid(
                  lines: _lines,
                  onChanged: _replaceLine,
                ),
                if (_remainingTotal > 0) ...[
                  _buildResolutionNote(theme),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildResolutionNote(ThemeData theme) {
    final palette = _ReceiptPalette.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: palette.surface,
        border: Border(
          top: BorderSide(color: palette.border),
          bottom: BorderSide(color: palette.border),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.call_split_rounded,
            color: palette.warning,
            size: 19,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'La recepción y la resolución son pasos separados',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: palette.text,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'Registrar ahora documenta lo recibido e ingresa a stock '
                  'sólo lo aceptado. La diferencia queda pendiente para '
                  'resolver después mediante nota de crédito, devolución, '
                  'reembolso, pérdida documentada o una entrega posterior.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: palette.muted,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter(ThemeData theme) {
    final palette = _ReceiptPalette.of(context);
    return Container(
      constraints: const BoxConstraints(minHeight: 60),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: palette.surface,
        border: Border(
          top: BorderSide(color: palette.border),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 860;
          final metrics = Wrap(
            spacing: 18,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _FooterMetric(
                label: 'Anterior',
                value: _previousTotal,
              ),
              if (_previouslyResolvedTotal > 0)
                _FooterMetric(
                  label: 'Resuelto',
                  value: _previouslyResolvedTotal,
                ),
              _FooterMetric(
                label: 'Recibido ahora',
                value: _acceptedTotal,
              ),
              _FooterMetric(
                label: 'Diferencia',
                value: _remainingTotal,
                valueColor: _remainingTotal > 0 ? palette.warning : null,
              ),
            ],
          );
          final actions = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextButton(
                onPressed: _submitting ? null : widget.onCancel,
                child: Text(
                  _alreadyComplete ? 'Volver a factura' : 'Cancelar',
                ),
              ),
              if (!_alreadyComplete) ...[
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _submitting ? null : _submit,
                  child: _submitting
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Registrar recepción'),
                ),
              ],
            ],
          );
          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                metrics,
                const SizedBox(height: 6),
                Align(alignment: Alignment.centerRight, child: actions),
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: metrics),
              const SizedBox(width: 16),
              actions,
            ],
          );
        },
      ),
    );
  }
}

class _ReceiptGrid extends StatefulWidget {
  const _ReceiptGrid({
    required this.lines,
    required this.onChanged,
  });

  final List<PurchaseReceiptLineDraft> lines;
  final void Function(int position, PurchaseReceiptLineDraft line) onChanged;

  @override
  State<_ReceiptGrid> createState() => _ReceiptGridState();
}

class _ReceiptGridState extends State<_ReceiptGrid> {
  final ScrollController _horizontalController = ScrollController();

  @override
  void dispose() {
    _horizontalController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = _ReceiptPalette.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final metrics = _ReceiptGridMetrics.forWidth(
          constraints.maxWidth.isFinite
              ? constraints.maxWidth
              : _ReceiptGridMetrics.minimumWidth,
        );
        return Container(
          decoration: BoxDecoration(
            color: palette.surface,
            border: Border(
              top: BorderSide(color: palette.border),
              bottom: BorderSide(color: palette.border),
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
                      _ReceiptGridHeader(metrics: metrics),
                      for (final entry in widget.lines.asMap().entries)
                        _ReceiptGridRow(
                          line: entry.value,
                          metrics: metrics,
                          onChanged: (line) =>
                              widget.onChanged(entry.key, line),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ReceiptGridMetrics {
  const _ReceiptGridMetrics({
    required this.product,
    required this.reason,
  });

  static const double minimumWidth = 900;
  static const double ordered = 78;
  static const double receivedNow = 132;
  static const double difference = 104;

  final double product;
  final double reason;

  factory _ReceiptGridMetrics.forWidth(double availableWidth) {
    final extra = math.max(0, availableWidth - minimumWidth);
    return _ReceiptGridMetrics(
      product: 340 + (extra * 0.58),
      reason: 246 + (extra * 0.42),
    );
  }

  double get totalWidth =>
      product + ordered + receivedNow + difference + reason;
}

class _ReceiptGridHeader extends StatelessWidget {
  const _ReceiptGridHeader({required this.metrics});

  final _ReceiptGridMetrics metrics;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = _ReceiptPalette.of(context);
    final style = theme.textTheme.labelSmall?.copyWith(
      color: palette.ink,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.25,
    );
    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: palette.tableHeader,
        border: Border(
          bottom: BorderSide(
            color: palette.ink.withValues(alpha: 0.18),
          ),
        ),
      ),
      child: Row(
        children: [
          _header('PRODUCTO', metrics.product, style),
          _header(
            'PEDIDO',
            _ReceiptGridMetrics.ordered,
            style,
            right: true,
            tooltip: 'Cantidad incluida en la factura',
          ),
          _header(
            'RECIBIDO AHORA',
            _ReceiptGridMetrics.receivedNow,
            style,
            right: true,
            tooltip: 'Cantidad aceptada físicamente en esta recepción',
          ),
          _header(
            'DIFERENCIA',
            _ReceiptGridMetrics.difference,
            style,
            right: true,
            tooltip: 'Saldo previo menos lo recibido ahora',
          ),
          _header('MOTIVO / EVIDENCIA', metrics.reason, style),
        ],
      ),
    );
  }

  Widget _header(
    String label,
    double width,
    TextStyle? style, {
    bool right = false,
    String? tooltip,
  }) {
    return SizedBox(
      width: width,
      child: Tooltip(
        message: tooltip ?? label,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 5),
          child: Align(
            alignment: right ? Alignment.centerRight : Alignment.centerLeft,
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.clip,
              textAlign: right ? TextAlign.right : TextAlign.left,
              style: style,
            ),
          ),
        ),
      ),
    );
  }
}

enum _ReceiptDifferenceReason {
  shortage,
  damaged,
  rejected,
}

extension on _ReceiptDifferenceReason {
  String get label => switch (this) {
        _ReceiptDifferenceReason.shortage => 'Faltante / no llegó',
        _ReceiptDifferenceReason.damaged => 'Dañado',
        _ReceiptDifferenceReason.rejected => 'Rechazado / no conforme',
      };
}

_ReceiptDifferenceReason? _differenceReasonFor(
  PurchaseReceiptLineDraft line,
) {
  if (line.shortageQuantity > 0) return _ReceiptDifferenceReason.shortage;
  if (line.damagedQuantity > 0) return _ReceiptDifferenceReason.damaged;
  if (line.rejectedQuantity > 0) return _ReceiptDifferenceReason.rejected;
  return null;
}

const _receiptEvidenceSeparator = ' · ';

String _receiptEvidenceDetail(
  PurchaseReceiptLineDraft line,
  _ReceiptDifferenceReason? reason,
) {
  final raw = line.discrepancyReason?.trim() ?? '';
  if (raw.isEmpty) return '';
  final label = reason?.label;
  if (label == null || label.isEmpty) return raw;
  if (raw == label) return '';
  final prefix = '$label$_receiptEvidenceSeparator';
  return raw.startsWith(prefix) ? raw.substring(prefix.length).trim() : raw;
}

String? _composedDiscrepancyReason(
  _ReceiptDifferenceReason? reason,
  String evidenceDetail,
) {
  if (reason == null) return null;
  final detail = evidenceDetail.trim();
  return detail.isEmpty
      ? reason.label
      : '${reason.label}$_receiptEvidenceSeparator$detail';
}

PurchaseReceiptLineDraft _applyReceiptDecision(
  PurchaseReceiptLineDraft line, {
  required int acceptedQuantity,
  required _ReceiptDifferenceReason? reason,
  String? evidenceDetail,
}) {
  final difference = math.max(0, line.remainingBefore - acceptedQuantity);
  final detail = evidenceDetail ?? _receiptEvidenceDetail(line, reason);
  return PurchaseReceiptLineDraft(
    lineIndex: line.lineIndex,
    productName: line.productName,
    productSku: line.productSku,
    productImageUrl: line.productImageUrl,
    expectedQuantity: line.expectedQuantity,
    previouslyReceivedQuantity: line.previouslyReceivedQuantity,
    previouslyResolvedQuantity: line.previouslyResolvedQuantity,
    acceptedQuantity: acceptedQuantity,
    shortageQuantity:
        reason == _ReceiptDifferenceReason.shortage ? difference : 0,
    damagedQuantity:
        reason == _ReceiptDifferenceReason.damaged ? difference : 0,
    rejectedQuantity:
        reason == _ReceiptDifferenceReason.rejected ? difference : 0,
    discrepancyReason:
        difference > 0 ? _composedDiscrepancyReason(reason, detail) : null,
  );
}

class _ReceiptGridRow extends StatelessWidget {
  const _ReceiptGridRow({
    required this.line,
    required this.metrics,
    required this.onChanged,
  });

  final PurchaseReceiptLineDraft line;
  final _ReceiptGridMetrics metrics;
  final ValueChanged<PurchaseReceiptLineDraft> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = _ReceiptPalette.of(context);
    final completed = line.remainingBefore == 0;
    final difference = line.remainingBefore - line.acceptedQuantity;
    final selectedReason = _differenceReasonFor(line);
    final hasHistory = line.previouslyReceivedQuantity > 0 ||
        line.previouslyResolvedQuantity > 0;
    final history = <String>[
      if (line.previouslyReceivedQuantity > 0)
        'Recibido antes: ${line.previouslyReceivedQuantity}',
      if (line.previouslyResolvedQuantity > 0)
        'Resuelto: ${line.previouslyResolvedQuantity}',
      if (hasHistory) 'Saldo previo: ${line.remainingBefore}',
    ].join(' · ');
    return Container(
      constraints: BoxConstraints(
        minHeight: difference > 0 ? 116 : (hasHistory ? 76 : 64),
      ),
      decoration: BoxDecoration(
        color: palette.surface,
        border: Border(
          bottom: BorderSide(color: palette.border),
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: metrics.product,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Row(
                children: [
                  _ProductThumbnail(
                    key: ValueKey('product-thumbnail-${line.lineIndex}'),
                    imageUrl: line.productImageUrl,
                    semanticLabel: line.productName,
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          line.productName,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: palette.text,
                            fontWeight: FontWeight.w600,
                            height: 1.1,
                          ),
                        ),
                        if (line.productSku?.isNotEmpty ?? false) ...[
                          const SizedBox(height: 2),
                          Text(
                            'SKU ${line.productSku}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: palette.muted,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ],
                        if (hasHistory) ...[
                          const SizedBox(height: 2),
                          Text(
                            history,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: palette.ink,
                              fontWeight: FontWeight.w500,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          _number(
            line.expectedQuantity,
            _ReceiptGridMetrics.ordered,
            theme,
            palette,
          ),
          _QuantityCell(
            width: _ReceiptGridMetrics.receivedNow,
            fieldKey: 'accepted-${line.lineIndex}',
            value: line.acceptedQuantity,
            enabled: !completed,
            maximum: line.remainingBefore,
            accent: palette.positive,
            softBackground: palette.surfaceRaised,
            highlightWhenPositive: false,
            onChanged: (value) => onChanged(
              _applyReceiptDecision(
                line,
                acceptedQuantity: value,
                reason: selectedReason,
                evidenceDetail: _receiptEvidenceDetail(line, selectedReason),
              ),
            ),
          ),
          _number(
            difference,
            _ReceiptGridMetrics.difference,
            theme,
            palette,
            key: ValueKey('difference-${line.lineIndex}'),
            emphasized: true,
            warning: difference > 0,
          ),
          SizedBox(
            key: ValueKey('reason-${line.lineIndex}'),
            width: metrics.reason,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  DropdownButtonFormField<_ReceiptDifferenceReason>(
                    key: ValueKey(
                      'reason-field-${line.lineIndex}-'
                      '${selectedReason?.name ?? 'none'}-$difference',
                    ),
                    initialValue: selectedReason,
                    isExpanded: true,
                    decoration: InputDecoration(
                      hintText: difference > 0
                          ? 'Seleccionar motivo'
                          : 'Sin diferencia',
                      isDense: true,
                      filled: true,
                      fillColor: difference > 0
                          ? palette.warningSoft
                          : palette.surfaceRaised,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 8,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(4),
                        borderSide: BorderSide(
                          color: difference > 0
                              ? palette.warning.withValues(alpha: 0.55)
                              : palette.border,
                        ),
                      ),
                    ),
                    items: _ReceiptDifferenceReason.values
                        .map(
                          (reason) => DropdownMenuItem(
                            value: reason,
                            child: Text(
                              reason.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(growable: false),
                    validator: (_) => difference > 0 && selectedReason == null
                        ? 'Selecciona el motivo.'
                        : null,
                    onChanged: completed || difference <= 0
                        ? null
                        : (reason) => onChanged(
                              _applyReceiptDecision(
                                line,
                                acceptedQuantity: line.acceptedQuantity,
                                reason: reason,
                                evidenceDetail: _receiptEvidenceDetail(
                                    line, selectedReason),
                              ),
                            ),
                  ),
                  if (difference > 0) ...[
                    const SizedBox(height: 6),
                    TextFormField(
                      key: ValueKey('evidence-field-${line.lineIndex}'),
                      initialValue:
                          _receiptEvidenceDetail(line, selectedReason),
                      enabled: !completed && selectedReason != null,
                      minLines: 1,
                      maxLines: 2,
                      decoration: InputDecoration(
                        hintText: selectedReason == null
                            ? 'Selecciona primero el motivo'
                            : 'Detalle / evidencia (opcional)',
                        isDense: true,
                        filled: true,
                        fillColor: palette.surface,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 8,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(4),
                          borderSide: BorderSide(color: palette.border),
                        ),
                      ),
                      onChanged: completed || selectedReason == null
                          ? null
                          : (detail) => onChanged(
                                _applyReceiptDecision(
                                  line,
                                  acceptedQuantity: line.acceptedQuantity,
                                  reason: selectedReason,
                                  evidenceDetail: detail,
                                ),
                              ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _number(
    int value,
    double width,
    ThemeData theme,
    _ReceiptPalette palette, {
    Key? key,
    bool emphasized = false,
    bool warning = false,
  }) {
    return SizedBox(
      key: key,
      width: width,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7),
        child: Text(
          '$value',
          textAlign: TextAlign.right,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontFeatures: const [FontFeature.tabularFigures()],
            fontWeight: emphasized ? FontWeight.w700 : FontWeight.w500,
            color: warning
                ? palette.warning
                : emphasized
                    ? palette.text
                    : palette.muted,
          ),
        ),
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

  static const double size = 44;

  final String? imageUrl;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final palette = _ReceiptPalette.of(context);
    final source = imageUrl?.trim();
    final placeholder = ColoredBox(
      color: palette.surfaceRaised,
      child: Icon(
        Icons.inventory_2_outlined,
        size: 18,
        color: palette.muted,
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
          color: palette.surface,
          border: Border.all(color: palette.border),
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

class _QuantityCell extends StatelessWidget {
  const _QuantityCell({
    required this.width,
    required this.fieldKey,
    required this.value,
    required this.enabled,
    this.maximum,
    required this.accent,
    required this.softBackground,
    required this.highlightWhenPositive,
    required this.onChanged,
  });

  final double width;
  final String fieldKey;
  final int value;
  final bool enabled;
  final int? maximum;
  final Color accent;
  final Color softBackground;
  final bool highlightWhenPositive;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = _ReceiptPalette.of(context);
    final active = highlightWhenPositive && value > 0;
    return SizedBox(
      width: width,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 6),
        child: TextFormField(
          key: ValueKey(fieldKey),
          initialValue: value.toString(),
          enabled: enabled,
          textAlign: TextAlign.right,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          style: TextStyle(
            color: active ? accent : palette.text,
            fontWeight: active ? FontWeight.w700 : FontWeight.w500,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: active ? softBackground : palette.surfaceRaised,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 7, vertical: 8),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(4),
              borderSide: BorderSide(
                color: active ? accent.withValues(alpha: 0.55) : palette.border,
              ),
            ),
            disabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(4),
              borderSide: BorderSide(color: palette.border),
            ),
          ),
          validator: (raw) {
            final parsed = int.tryParse(raw ?? '');
            if (parsed == null) return 'Ingresa una cantidad.';
            if (maximum != null && parsed > maximum!) {
              return 'Máximo $maximum.';
            }
            return null;
          },
          onChanged: (raw) => onChanged(int.tryParse(raw) ?? 0),
        ),
      ),
    );
  }
}

class _LabeledField extends StatelessWidget {
  const _LabeledField({
    required this.label,
    required this.width,
    required this.child,
  });

  final String label;
  final double width;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = _ReceiptPalette.of(context);
    return SizedBox(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: palette.muted,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.15,
            ),
          ),
          const SizedBox(height: 5),
          SizedBox(height: 38, child: child),
        ],
      ),
    );
  }
}

class _StatusLabel extends StatelessWidget {
  const _StatusLabel({
    required this.label,
    required this.tone,
  });

  final String label;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
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
        const SizedBox(width: 7),
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: tone,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.45,
          ),
        ),
      ],
    );
  }
}

class _FooterMetric extends StatelessWidget {
  const _FooterMetric({
    required this.label,
    required this.value,
    this.valueColor,
  });

  final String label;
  final int value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = _ReceiptPalette.of(context);
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '$label ',
            style: theme.textTheme.labelMedium?.copyWith(
              color: palette.muted,
              fontWeight: FontWeight.w500,
            ),
          ),
          TextSpan(
            text: '$value',
            style: theme.textTheme.labelLarge?.copyWith(
              color: valueColor ?? palette.text,
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
      maxLines: 1,
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.error_outline,
                size: 34,
                color: theme.colorScheme.error,
              ),
              const SizedBox(height: 12),
              Text(
                'No se puede preparar la recepción',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                message,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: onRetry,
                child: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
