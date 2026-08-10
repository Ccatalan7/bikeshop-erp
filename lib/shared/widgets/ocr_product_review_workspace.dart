import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../modules/inventory/models/brand_models.dart';
import '../../modules/inventory/models/category_models.dart';
import '../../modules/inventory/models/inventory_models.dart';
import '../../modules/inventory/models/product_duplicate_candidate.dart';
import '../themes/vinabike_theme_roles.dart';
import 'vb_notice.dart';
import 'vb_searchable_select.dart';
import 'vb_status_badge.dart';

enum OcrProductReviewStatus {
  needsSearch,
  searching,
  ready,
  noCandidates,
  failed,
  linked,
  newProductReady,
  readOnly,
}

enum OcrProductFieldOrigin {
  invoice,
  aiCleaned,
  aiSuggested,
  nameDerived,
  pricePolicy,
  reserved,
  user,
}

@immutable
class OcrProductDraftControllers {
  const OcrProductDraftControllers({
    required this.sku,
    required this.name,
    required this.cost,
    required this.price,
  });

  final TextEditingController sku;
  final TextEditingController name;
  final TextEditingController cost;
  final TextEditingController price;
}

@immutable
class OcrProductReviewLine {
  const OcrProductReviewLine({
    required this.id,
    required this.sku,
    required this.originalTitle,
    required this.controllers,
    required this.status,
    this.supplierCode,
    this.sourceQuantity,
    this.sourceLineTotal,
    this.imageUrl,
    this.imageBytes,
    this.candidates = const [],
    this.categories = const [],
    this.brands = const [],
    this.category,
    this.brand,
    this.nameOrigin = OcrProductFieldOrigin.aiCleaned,
    this.skuOrigin = OcrProductFieldOrigin.reserved,
    this.categoryOrigin = OcrProductFieldOrigin.aiSuggested,
    this.brandOrigin = OcrProductFieldOrigin.aiSuggested,
    this.costOrigin = OcrProductFieldOrigin.invoice,
    this.priceOrigin = OcrProductFieldOrigin.pricePolicy,
    this.isSold = true,
    this.evidenceDegraded = false,
    this.isUploadingImage = false,
    this.isReservingSku = false,
    this.skuIsReadOnly = false,
    this.skuErrorMessage,
    this.errorMessage,
    this.searchSummary,
    this.categoryValidationMessage,
    this.brandValidationMessage,
    this.brandWarning,
    this.siblingSuggestion,
    this.siblingLineId,
    this.resolvedProductName,
    this.resolvedProductSku,
    this.isSelected = true,
  });

  final String id;
  final String sku;
  final String originalTitle;
  final String? supplierCode;
  final double? sourceQuantity;
  final double? sourceLineTotal;
  final String? imageUrl;
  final Uint8List? imageBytes;
  final OcrProductDraftControllers controllers;
  final OcrProductReviewStatus status;
  final List<ProductDuplicateCandidate> candidates;
  final List<Category> categories;
  final List<ProductBrand> brands;
  final Category? category;
  final ProductBrand? brand;
  final OcrProductFieldOrigin nameOrigin;
  final OcrProductFieldOrigin skuOrigin;
  final OcrProductFieldOrigin categoryOrigin;
  final OcrProductFieldOrigin brandOrigin;
  final OcrProductFieldOrigin costOrigin;
  final OcrProductFieldOrigin priceOrigin;
  final bool isSold;
  final bool evidenceDegraded;
  final bool isUploadingImage;

  /// The row is asking the database for its canonical `AE0xxx`.
  final bool isReservingSku;

  /// The SKU belongs to the database, not to this form. The cell shows it and
  /// refuses to be typed into.
  final bool skuIsReadOnly;

  /// Why that reservation failed, when it did. A blank SKU that silently
  /// failed is worse than an empty one: the worker cannot label the box and
  /// nothing says why.
  final String? skuErrorMessage;

  final String? errorMessage;
  final String? searchSummary;
  final String? categoryValidationMessage;
  final String? brandValidationMessage;
  final String? brandWarning;
  final String? siblingSuggestion;
  final String? siblingLineId;
  final String? resolvedProductName;
  final String? resolvedProductSku;
  final bool isSelected;

  bool get isResolved => switch (status) {
        OcrProductReviewStatus.linked ||
        OcrProductReviewStatus.newProductReady ||
        OcrProductReviewStatus.readOnly =>
          true,
        _ => false,
      };

  ProductDuplicateCandidate? get bestCandidate =>
      candidates.isEmpty ? null : candidates.first;
}

@immutable
class OcrProductReviewCallbacks {
  const OcrProductReviewCallbacks({
    this.onLineSelected,
    this.onSelectionChanged,
    this.onLinkCandidate,
    this.onConfirmNewProduct,
    this.onRetryLine,
    this.onRetrySkuReservation,
    this.onSearchPending,
    this.onOpenCandidates,
    this.onSkuChanged,
    this.onNameChanged,
    this.onCategoryChanged,
    this.onBrandChanged,
    this.onCostChanged,
    this.onPriceChanged,
    this.onSoldChanged,
    this.onCopySibling,
    this.onReplaceImage,
    this.onRemoveImage,
    this.onChangeDecision,
    this.onCostIncludesVatChanged,
    this.onBack,
    this.onPrimary,
  });

  final ValueChanged<String>? onLineSelected;
  final void Function(String lineId, bool selected)? onSelectionChanged;
  final void Function(String lineId, Product product)? onLinkCandidate;
  final ValueChanged<String>? onConfirmNewProduct;
  final ValueChanged<String>? onRetryLine;

  /// Ask again for this row's reserved SKU.
  final ValueChanged<String>? onRetrySkuReservation;

  final VoidCallback? onSearchPending;

  /// Opens the centred picker for one line. Alternatives are never expanded
  /// inside the row: doing that made every row a different height and pushed
  /// the rest of the invoice out of view.
  final ValueChanged<String>? onOpenCandidates;

  final void Function(String lineId, String value)? onSkuChanged;
  final void Function(String lineId, String value)? onNameChanged;
  final void Function(String lineId, Category? value)? onCategoryChanged;
  final void Function(String lineId, ProductBrand? value)? onBrandChanged;
  final void Function(String lineId, String value)? onCostChanged;
  final void Function(String lineId, String value)? onPriceChanged;
  final void Function(String lineId, bool value)? onSoldChanged;
  final void Function(String lineId, String siblingLineId)? onCopySibling;
  final ValueChanged<String>? onReplaceImage;
  final ValueChanged<String>? onRemoveImage;
  final ValueChanged<String>? onChangeDecision;
  final ValueChanged<bool>? onCostIncludesVatChanged;
  final VoidCallback? onBack;
  final VoidCallback? onPrimary;
}

@immutable
class OcrProductReviewProgress {
  const OcrProductReviewProgress({
    required this.total,
    required this.resolved,
    required this.pending,
    required this.failed,
  });

  factory OcrProductReviewProgress.fromLines(
    List<OcrProductReviewLine> lines,
  ) {
    final selected = lines.where((line) => line.isSelected).toList();
    final resolved = selected.where((line) => line.isResolved).length;
    final failed = selected
        .where((line) => line.status == OcrProductReviewStatus.failed)
        .length;
    return OcrProductReviewProgress(
      total: selected.length,
      resolved: resolved,
      pending: selected.length - resolved - failed,
      failed: failed,
    );
  }

  final int total;
  final int resolved;
  final int pending;
  final int failed;

  bool get isComplete => total > 0 && pending == 0 && failed == 0;

  String get label {
    final parts = <String>[
      '$resolved ${resolved == 1 ? 'lista' : 'listas'}',
      '$pending por decidir',
    ];
    if (failed > 0) {
      parts.add('$failed ${failed == 1 ? 'con problema' : 'con problemas'}');
    }
    return parts.join(' · ');
  }

  /// The one sentence the footer states: what the operator does next.
  String get nextStep {
    if (total == 0) return 'No hay líneas seleccionadas.';
    if (failed > 0) {
      return 'Reintenta las $failed que fallaron.';
    }
    if (pending > 0) {
      return 'Decide $pending ${pending == 1 ? 'línea' : 'líneas'}: '
          'vincula la existente o crea la nueva.';
    }
    return 'Todo decidido. Crea los productos y vuelve a la factura.';
  }
}

/// Full-page reconciliation of the products read from one purchase invoice.
///
/// **One source line is one table row, and every row is the same height.**
/// The rejected composition broke both halves of that sentence: it opened a
/// fixed 1680 px `DataTable` inside a permanent horizontal scroll, gave each
/// row a 108 px floor that grew when its alternatives were expanded in place,
/// and left the operator dragging sideways to reach the decision. What repeated
/// business fields need is a stable header and vertical comparison — the
/// invoice read top to bottom, in invoice order, with one decision per row.
///
/// Three deliberate compositions, not one shrinking table:
///
/// * **≥1180** the full table, every column visible without sideways scroll;
/// * **900–1180** the same table with price and sale-use folded away, which the
///   surface registry allows explicitly for tablet;
/// * **<900** the same controllers and commands as divider-separated line
///   editors — not cards, not an accordion, not a wizard.
class OcrProductReviewWorkspace extends StatefulWidget {
  const OcrProductReviewWorkspace({
    super.key,
    required this.lines,
    required this.callbacks,
    required this.primaryLabel,
    required this.pricingPolicyLabel,
    this.selectedLineId,
    this.primaryEnabled = false,
    this.primaryBlockingReason,
    this.costIncludesVat = true,
    this.readOnly = false,
  });

  final List<OcrProductReviewLine> lines;
  final OcrProductReviewCallbacks callbacks;
  final String? selectedLineId;
  final String primaryLabel;
  final String pricingPolicyLabel;
  final bool primaryEnabled;
  final String? primaryBlockingReason;
  final bool costIncludesVat;
  final bool readOnly;

  /// Below this the shell itself is compact and every target is 48 px.
  static const double touchBreakpoint = 900;

  /// Above this the full column set fits without compression.
  static const double fullTableBreakpoint = 1180;

  @override
  State<OcrProductReviewWorkspace> createState() =>
      _OcrProductReviewWorkspaceState();
}

class _OcrProductReviewWorkspaceState extends State<OcrProductReviewWorkspace> {
  static const double touchTarget = kMinInteractiveDimension;
  static const double hairline = 1;
  static const double radius = 8;
  static const double space1 = 4;
  static const double space2 = 8;
  static const double space3 = 12;
  static const double space4 = 16;
  static const double space5 = 20;
  static const double space6 = 24;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        final touch = width < OcrProductReviewWorkspace.touchBreakpoint;
        final dense = width < OcrProductReviewWorkspace.fullTableBreakpoint;

        return Material(
          color: Theme.of(context).colorScheme.surface,
          child: Semantics(
            container: true,
            label: 'Revisión de productos de la factura',
            child: Column(
              children: [
                Expanded(
                  child: widget.lines.isEmpty
                      ? const _EmptyWorkspace()
                      : _ReviewBatch(
                          lines: widget.lines,
                          selectedLineId: widget.selectedLineId,
                          callbacks: widget.callbacks,
                          touch: touch,
                          dense: dense,
                          readOnly: widget.readOnly,
                        ),
                ),
                _WorkspaceFooter(
                  primaryLabel: widget.primaryLabel,
                  pricingPolicyLabel: widget.pricingPolicyLabel,
                  progress: OcrProductReviewProgress.fromLines(widget.lines),
                  primaryEnabled: widget.primaryEnabled && !widget.readOnly,
                  primaryBlockingReason: widget.primaryBlockingReason,
                  costIncludesVat: widget.costIncludesVat,
                  onCostIncludesVatChanged: widget.readOnly
                      ? null
                      : widget.callbacks.onCostIncludesVatChanged,
                  onBack: widget.readOnly ? null : widget.callbacks.onBack,
                  onPrimary:
                      widget.readOnly ? null : widget.callbacks.onPrimary,
                  touch: touch,
                  readOnly: widget.readOnly,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _EmptyWorkspace extends StatelessWidget {
  const _EmptyWorkspace();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(_OcrProductReviewWorkspaceState.space6),
        child: VbNotice(
          title: 'No hay productos para revisar',
          body: 'Vuelve a la factura y revisa las líneas detectadas.',
          tone: VbNoticeTone.neutral,
        ),
      ),
    );
  }
}

// ───────────────────────────────────────────────────────────────────────────
// Column model
// ───────────────────────────────────────────────────────────────────────────

/// One column of the reconciliation table.
///
/// Header and body read the same list, so a column can never be added to one
/// and forgotten in the other — which is how a table stops lining up.
class _ReviewColumn {
  const _ReviewColumn({
    required this.id,
    required this.label,
    this.fixed,
    this.flex = 0,
    this.min = 0,
    this.numeric = false,
  });

  final String id;
  final String label;

  /// A column that never grows: an index, a code, a switch.
  final double? fixed;

  /// Share of the leftover width.
  final int flex;

  /// Never narrower than this, even while sharing.
  final double min;

  final bool numeric;
}

const double _columnGap = 10;

/// How much of the invoice the table shows, densest last.
///
/// The tier is chosen from the width the table is actually given, not from the
/// page width. Deriving it from the page was wrong by exactly the padding the
/// page adds: at a 900 px viewport the table receives about 836 px while the
/// reduced column set needs 938, so it overflowed on every host between 900
/// and roughly 1001 px — the local window sizes this shop uses most.
enum _TableTier { full, reduced, tight }

List<_ReviewColumn> _columnsFor(_TableTier tier) {
  final reduced = tier != _TableTier.full;
  final tight = tier == _TableTier.tight;
  return <_ReviewColumn>[
    const _ReviewColumn(id: 'index', label: '#', fixed: 30),
    _ReviewColumn(
      id: 'source',
      label: 'Producto de la factura',
      flex: 30,
      min: tight ? 132 : 180,
    ),
    _ReviewColumn(id: 'sku', label: 'SKU', fixed: tight ? 62 : 74),
    _ReviewColumn(
      id: 'name',
      label: 'Nombre',
      flex: 20,
      min: tight ? 104 : 130,
    ),
    _ReviewColumn(
      id: 'category',
      label: 'Categoría',
      flex: 14,
      min: tight ? 88 : 104,
    ),
    _ReviewColumn(id: 'brand', label: 'Marca', flex: 10, min: tight ? 76 : 88),
    _ReviewColumn(
      id: 'cost',
      label: 'Costo',
      fixed: tight ? 60 : 72,
      numeric: true,
    ),
    if (!reduced)
      const _ReviewColumn(
        id: 'price',
        label: 'Precio',
        fixed: 72,
        numeric: true,
      ),
    _ReviewColumn(
      id: 'decision',
      label: 'Decisión',
      flex: 20,
      min: tight ? 160 : 190,
    ),
    if (!reduced) const _ReviewColumn(id: 'sold', label: 'Vende', fixed: 52),
  ];
}

/// Narrowest width at which a column set still honours every minimum.
double _requiredWidth(List<_ReviewColumn> columns) {
  var total = _columnGap * (columns.length - 1);
  for (final column in columns) {
    total += column.fixed ?? column.min;
  }
  return total;
}

/// Resolves the declared columns against the real width.
///
/// Flexible columns share what is left after the fixed ones; a column that
/// would fall under its minimum takes its minimum and stops sharing. The result
/// is a table that fills its host at any width instead of a fixed canvas the
/// operator has to drag sideways.
List<double> _resolveWidths(List<_ReviewColumn> columns, double available) {
  final widths = List<double>.filled(columns.length, 0);
  var remaining = available - _columnGap * (columns.length - 1);
  var flexTotal = 0;

  for (var index = 0; index < columns.length; index++) {
    final column = columns[index];
    if (column.fixed != null) {
      widths[index] = column.fixed!;
      remaining -= column.fixed!;
    } else {
      flexTotal += column.flex;
    }
  }

  if (flexTotal == 0) return widths;

  // Two passes: give everyone their share, then repair anyone below its floor
  // by taking from those still above theirs.
  var share = remaining;
  var pool = flexTotal;
  final settled = List<bool>.filled(columns.length, false);
  var changed = true;
  while (changed) {
    changed = false;
    for (var index = 0; index < columns.length; index++) {
      final column = columns[index];
      if (column.fixed != null || settled[index]) continue;
      final candidate = pool == 0 ? 0.0 : share * column.flex / pool;
      if (candidate < column.min) {
        widths[index] = column.min;
        settled[index] = true;
        share -= column.min;
        pool -= column.flex;
        changed = true;
      }
    }
  }
  for (var index = 0; index < columns.length; index++) {
    final column = columns[index];
    if (column.fixed != null || settled[index]) continue;
    widths[index] = pool == 0 ? column.min : share * column.flex / pool;
  }
  return widths;
}

// ───────────────────────────────────────────────────────────────────────────
// Batch
// ───────────────────────────────────────────────────────────────────────────

class _ReviewBatch extends StatelessWidget {
  const _ReviewBatch({
    required this.lines,
    required this.selectedLineId,
    required this.callbacks,
    required this.touch,
    required this.dense,
    required this.readOnly,
  });

  final List<OcrProductReviewLine> lines;
  final String? selectedLineId;
  final OcrProductReviewCallbacks callbacks;
  final bool touch;
  final bool dense;
  final bool readOnly;

  @override
  Widget build(BuildContext context) {
    final horizontal = touch
        ? _OcrProductReviewWorkspaceState.space3
        : _OcrProductReviewWorkspaceState.space5;
    final progress = OcrProductReviewProgress.fromLines(lines);

    return CustomScrollView(
      key: const Key('ocr-review-batch'),
      slivers: [
        SliverPadding(
          padding: EdgeInsets.fromLTRB(
            horizontal,
            _OcrProductReviewWorkspaceState.space4,
            horizontal,
            _OcrProductReviewWorkspaceState.space3,
          ),
          sliver: SliverToBoxAdapter(
            child: _ReviewHeading(
              progress: progress,
              onSearchPending: readOnly ? null : callbacks.onSearchPending,
            ),
          ),
        ),
        SliverPadding(
          padding: EdgeInsets.fromLTRB(
            horizontal,
            0,
            horizontal,
            _OcrProductReviewWorkspaceState.space6,
          ),
          sliver: SliverToBoxAdapter(
            child: touch
                ? _CompactLineList(
                    lines: lines,
                    selectedLineId: selectedLineId,
                    callbacks: callbacks,
                    readOnly: readOnly,
                  )
                : _ReconciliationTable(
                    lines: lines,
                    selectedLineId: selectedLineId,
                    callbacks: callbacks,
                    readOnly: readOnly,
                    dense: dense,
                  ),
          ),
        ),
      ],
    );
  }
}

class _ReviewHeading extends StatelessWidget {
  const _ReviewHeading({
    required this.progress,
    required this.onSearchPending,
  });

  final OcrProductReviewProgress progress;
  final VoidCallback? onSearchPending;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Productos de la factura',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: _OcrProductReviewWorkspaceState.space1),
              Text(
                progress.label,
                key: const Key('ocr-review-progress'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        if (onSearchPending != null)
          TextButton.icon(
            key: const Key('ocr-review-search-pending'),
            onPressed: onSearchPending,
            icon: const Icon(Icons.manage_search, size: 18),
            label: const Text('Buscar pendientes'),
          ),
      ],
    );
  }
}

// ───────────────────────────────────────────────────────────────────────────
// Desktop / tablet table
// ───────────────────────────────────────────────────────────────────────────

class _ReconciliationTable extends StatelessWidget {
  const _ReconciliationTable({
    required this.lines,
    required this.selectedLineId,
    required this.callbacks,
    required this.readOnly,
    required this.dense,
  });

  final List<OcrProductReviewLine> lines;
  final String? selectedLineId;
  final OcrProductReviewCallbacks callbacks;
  final bool readOnly;
  final bool dense;

  /// The height every ordinary row shares. Controls inside are single-line and
  /// the same height, which is what makes a column scannable at a glance.
  ///
  /// It is a floor, not a cap: a row whose category is still missing, or whose
  /// suggested brand had no evidence, must be able to *say so* under the
  /// control. Clipping a mandatory validation message to keep a table tidy
  /// hides the exact reason the invoice cannot be applied.
  static const double rowHeight = 60;
  static const double headerHeight = 38;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final inner =
            constraints.maxWidth - _OcrProductReviewWorkspaceState.space3 * 2;
        final tier = _tierFor(inner);
        if (tier == null) {
          // No column set fits honestly. A divider-separated line editor is
          // the truthful answer; a squeezed table with an overflow stripe is
          // not.
          return _CompactLineList(
            lines: lines,
            selectedLineId: selectedLineId,
            callbacks: callbacks,
            readOnly: readOnly,
          );
        }
        return _buildTable(context, _columnsFor(tier), inner);
      },
    );
  }

  /// The richest column set that fits [inner], or `null` when none does.
  _TableTier? _tierFor(double inner) {
    for (final tier in <_TableTier>[
      if (!dense) _TableTier.full,
      _TableTier.reduced,
      _TableTier.tight,
    ]) {
      if (_requiredWidth(_columnsFor(tier)) <= inner) return tier;
    }
    return null;
  }

  Widget _buildTable(
    BuildContext context,
    List<_ReviewColumn> columns,
    double inner,
  ) {
    final theme = Theme.of(context);

    return Semantics(
      container: true,
      label: 'Tabla de conciliación de productos',
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: theme.colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(
            _OcrProductReviewWorkspaceState.radius,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(
            _OcrProductReviewWorkspaceState.radius,
          ),
          child: Builder(
            builder: (context) {
              final widths = _resolveWidths(columns, inner);
              return Column(
                key: const Key('ocr-review-table'),
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _TableHeader(columns: columns, widths: widths),
                  for (var index = 0; index < lines.length; index++) ...[
                    if (index > 0)
                      Divider(height: 1, color: theme.dividerColor),
                    _TableRow(
                      key:
                          ValueKey<String>('ocr-review-row-${lines[index].id}'),
                      line: lines[index],
                      index: index,
                      columns: columns,
                      widths: widths,
                      selected: lines[index].id == selectedLineId,
                      callbacks: callbacks,
                      readOnly: readOnly,
                    ),
                  ],
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _TableHeader extends StatelessWidget {
  const _TableHeader({required this.columns, required this.widths});

  final List<_ReviewColumn> columns;
  final List<double> widths;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      key: const Key('ocr-review-table-header'),
      height: _ReconciliationTable.headerHeight,
      padding: const EdgeInsets.symmetric(
        horizontal: _OcrProductReviewWorkspaceState.space3,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: Row(
        children: [
          for (var index = 0; index < columns.length; index++) ...[
            if (index > 0) const SizedBox(width: _columnGap),
            SizedBox(
              width: widths[index],
              child: Align(
                alignment: columns[index].numeric
                    ? Alignment.centerRight
                    : Alignment.centerLeft,
                child: Text(
                  columns[index].label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _TableRow extends StatelessWidget {
  const _TableRow({
    super.key,
    required this.line,
    required this.index,
    required this.columns,
    required this.widths,
    required this.selected,
    required this.callbacks,
    required this.readOnly,
  });

  final OcrProductReviewLine line;
  final int index;
  final List<_ReviewColumn> columns;
  final List<double> widths;
  final bool selected;
  final OcrProductReviewCallbacks callbacks;
  final bool readOnly;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final roles = VinabikeThemeRoles.of(context);
    // A row whose SKU is being reserved holds an operation against the
    // shared AE sequence. Its controls stay inert until that settles.
    final disabled = readOnly || !line.isSelected || line.isReservingSku;

    Widget cell(String id) {
      switch (id) {
        case 'index':
          return _IndexCell(
            line: line,
            index: index,
            enabled: !readOnly,
            callbacks: callbacks,
          );
        case 'source':
          return _SourceCell(
            line: line,
            index: index,
            callbacks: callbacks,
            readOnly: readOnly,
          );
        case 'sku':
          return _SkuCell(
            line: line,
            enabled: !disabled,
            callbacks: callbacks,
          );
        case 'name':
          return _CompactField(
            fieldKey: Key('ocr-review-name-${line.id}'),
            controller: line.controllers.name,
            enabled: !disabled,
            origin: line.nameOrigin,
            onChanged: callbacks.onNameChanged == null
                ? null
                : (value) => callbacks.onNameChanged!(line.id, value),
          );
        case 'category':
          return _CategorySelector(
            line: line,
            enabled: !disabled,
            showLabel: false,
            onChanged: callbacks.onCategoryChanged == null
                ? null
                : (value) => callbacks.onCategoryChanged!(line.id, value),
          );
        case 'brand':
          return _BrandSelector(
            line: line,
            enabled: !disabled,
            showLabel: false,
            onChanged: callbacks.onBrandChanged == null
                ? null
                : (value) => callbacks.onBrandChanged!(line.id, value),
          );
        case 'cost':
          return _CompactField(
            fieldKey: Key('ocr-review-cost-${line.id}'),
            controller: line.controllers.cost,
            enabled: !disabled,
            numeric: true,
            origin: line.costOrigin,
            onChanged: callbacks.onCostChanged == null
                ? null
                : (value) => callbacks.onCostChanged!(line.id, value),
          );
        case 'price':
          return _CompactField(
            fieldKey: Key('ocr-review-price-${line.id}'),
            controller: line.controllers.price,
            enabled: !disabled,
            numeric: true,
            origin: line.priceOrigin,
            onChanged: callbacks.onPriceChanged == null
                ? null
                : (value) => callbacks.onPriceChanged!(line.id, value),
          );
        case 'decision':
          return _DecisionCell(
            line: line,
            callbacks: callbacks,
            enabled: !disabled,
          );
        case 'sold':
          return Align(
            alignment: Alignment.center,
            child: Switch(
              key: Key('ocr-review-sold-${line.id}'),
              value: line.isSold,
              onChanged: disabled || callbacks.onSoldChanged == null
                  ? null
                  : (value) => callbacks.onSoldChanged!(line.id, value),
            ),
          );
      }
      return const SizedBox.shrink();
    }

    return Material(
      color: selected ? roles.selectionContainer : theme.colorScheme.surface,
      child: InkWell(
        onTap: callbacks.onLineSelected == null
            ? null
            : () => callbacks.onLineSelected!(line.id),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: _ReconciliationTable.rowHeight,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: _OcrProductReviewWorkspaceState.space3,
              vertical: _OcrProductReviewWorkspaceState.space1,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                for (var i = 0; i < columns.length; i++) ...[
                  if (i > 0) const SizedBox(width: _columnGap),
                  SizedBox(width: widths[i], child: cell(columns[i].id)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _IndexCell extends StatelessWidget {
  const _IndexCell({
    required this.line,
    required this.index,
    required this.enabled,
    required this.callbacks,
  });

  final OcrProductReviewLine line;
  final int index;
  final bool enabled;
  final OcrProductReviewCallbacks callbacks;

  @override
  Widget build(BuildContext context) {
    // Only the checkbox. The line number rides with the source title, where it
    // reads as «1 · WAKE-vástago…» — stacking a number under a checkbox in a
    // 30 px column made the cell taller than the row it lives in.
    return Align(
      alignment: Alignment.center,
      child: Checkbox(
        key: Key('ocr-review-select-${line.id}'),
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        value: line.isSelected,
        onChanged: !enabled || callbacks.onSelectionChanged == null
            ? null
            : (selected) => callbacks.onSelectionChanged!(
                  line.id,
                  selected ?? false,
                ),
      ),
    );
  }
}

class _SourceCell extends StatelessWidget {
  const _SourceCell({
    required this.line,
    required this.index,
    required this.callbacks,
    required this.readOnly,
  });

  final OcrProductReviewLine line;
  final int index;
  final OcrProductReviewCallbacks callbacks;
  final bool readOnly;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final facts = <String>[
      if ((line.supplierCode ?? '').trim().isNotEmpty)
        line.supplierCode!.trim(),
      if (line.sourceQuantity != null) '${_number(line.sourceQuantity!)} un.',
    ];

    final sibling = line.siblingSuggestion;
    final siblingLineId = line.siblingLineId;

    return Row(
      children: [
        _EditableSourceImage(
          line: line,
          callbacks: callbacks,
          size: 36,
          enabled: !readOnly,
        ),
        const SizedBox(width: _OcrProductReviewWorkspaceState.space2),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${index + 1} · ${line.originalTitle}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall,
              ),
              if (facts.isNotEmpty)
                Text(
                  facts.join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
        // Two variants of one supplier listing may reuse family and brand
        // without being merged. It used to be a notice card inside the row,
        // which cost 60 px of height on every line to say something that
        // applies to two of them. Same capability, no height.
        if (sibling != null &&
            siblingLineId != null &&
            !readOnly &&
            callbacks.onCopySibling != null)
          IconButton(
            key: Key('ocr-review-copy-sibling-${line.id}'),
            tooltip: sibling,
            iconSize: 15,
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
            icon: const Icon(Icons.copy_all_outlined),
            onPressed: () => callbacks.onCopySibling!(line.id, siblingLineId),
          ),
      ],
    );
  }

  static String _number(double value) {
    if (value == value.roundToDouble()) return value.round().toString();
    return value.toStringAsFixed(2);
  }
}

/// The SKU cell, which is also where a row says it is still getting its number.
class _SkuCell extends StatelessWidget {
  const _SkuCell({
    required this.line,
    required this.enabled,
    required this.callbacks,
  });

  final OcrProductReviewLine line;
  final bool enabled;
  final OcrProductReviewCallbacks callbacks;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final roles = VinabikeThemeRoles.of(context);

    if (line.isReservingSku) {
      return Row(
        key: Key('ocr-review-sku-reserving-${line.id}'),
        children: [
          const SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: _OcrProductReviewWorkspaceState.space2),
          Expanded(
            child: Text(
              'Reservando…',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      );
    }

    if (line.skuErrorMessage != null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            line.skuErrorMessage!,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              color: roles.danger.accent,
            ),
          ),
          TextButton(
            key: Key('ocr-review-sku-retry-${line.id}'),
            onPressed: enabled && callbacks.onRetrySkuReservation != null
                ? () => callbacks.onRetrySkuReservation!(line.id)
                : null,
            style: _tinyButtonStyle,
            child: const Text('Reintentar'),
          ),
        ],
      );
    }

    if (line.skuIsReadOnly) {
      final hasCode = line.controllers.sku.text.trim().isNotEmpty;
      return Tooltip(
        message: hasCode
            ? 'SKU reservado por la base de datos'
            : 'Se reserva al confirmar «Nuevo»',
        waitDuration: const Duration(milliseconds: 600),
        child: SizedBox(
          height: 34,
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              hasCode ? line.controllers.sku.text.trim() : line.sku,
              key: Key('ocr-review-sku-readonly-${line.id}'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
                color: hasCode
                    ? theme.colorScheme.onSurface
                    : theme.colorScheme.onSurfaceVariant,
                fontWeight: hasCode ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
        ),
      );
    }

    return _CompactField(
      fieldKey: Key('ocr-review-sku-${line.id}'),
      controller: line.controllers.sku,
      enabled: enabled,
      origin: line.skuOrigin,
      onChanged: callbacks.onSkuChanged == null
          ? null
          : (value) => callbacks.onSkuChanged!(line.id, value),
    );
  }
}

/// A single-line editable cell, 34 px tall like every other control in the row.
class _CompactField extends StatelessWidget {
  const _CompactField({
    required this.fieldKey,
    required this.controller,
    required this.enabled,
    required this.origin,
    required this.onChanged,
    this.numeric = false,
  });

  final Key fieldKey;
  final TextEditingController controller;
  final bool enabled;
  final OcrProductFieldOrigin origin;
  final ValueChanged<String>? onChanged;
  final bool numeric;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Tooltip(
      message: _originLabel(origin),
      waitDuration: const Duration(milliseconds: 600),
      child: SizedBox(
        height: 34,
        child: TextField(
          key: fieldKey,
          controller: controller,
          enabled: enabled,
          textAlign: numeric ? TextAlign.right : TextAlign.start,
          keyboardType: numeric
              ? const TextInputType.numberWithOptions(decimal: true)
              : TextInputType.text,
          inputFormatters: numeric
              ? <TextInputFormatter>[
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                ]
              : null,
          style: theme.textTheme.bodySmall,
          decoration: const InputDecoration(
            isDense: true,
            contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          ),
          onChanged: onChanged,
        ),
      ),
    );
  }
}

class _CategorySelector extends StatelessWidget {
  const _CategorySelector({
    required this.line,
    required this.enabled,
    required this.onChanged,
    this.showLabel = true,
  });

  final OcrProductReviewLine line;
  final bool enabled;
  final ValueChanged<Category?>? onChanged;
  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    // `Adaptadores` exists under three different branches in this catalog, so
    // two options can be indistinguishable by name alone. The closed field
    // still says the short name the operator picked — that was the owner's
    // correction — while the parent branch is published everywhere it does
    // disambiguate: inside every search result, as the helper line once a
    // duplicated leaf is chosen, and in the accessible value.
    final byName = <String, int>{};
    for (final category in line.categories) {
      byName[category.name] = (byName[category.name] ?? 0) + 1;
    }
    final selected = line.category;
    final selectedIsAmbiguous =
        selected != null && (byName[selected.name] ?? 0) > 1;
    final selectedParent =
        selectedIsAmbiguous ? _parentPath(selected.fullPath) : null;

    return VbSearchableSelect<Category>(
      key: Key('ocr-review-category-${line.id}'),
      value: selected,
      label: 'Categoría',
      showLabel: showLabel,
      sheetTitle: 'Elegir categoría',
      placeholder: 'Elegir',
      semanticLabel: selectedParent == null
          ? 'Categoría del producto'
          : 'Categoría del producto, en $selectedParent',
      helperText: selectedParent == null ? null : 'en $selectedParent',
      errorText: line.categoryValidationMessage,
      onChanged: enabled ? onChanged : null,
      options: <VbSearchableSelectOption<Category>>[
        for (final category in line.categories)
          VbSearchableSelectOption<Category>(
            value: category,
            label: category.name,
            context:
                (byName[category.name] ?? 0) > 1 ? category.fullPath : null,
            searchText: category.fullPath,
          ),
      ],
    );
  }

  /// `Accesorios / Adaptadores` → `Accesorios`.
  static String? _parentPath(String fullPath) {
    final parts = fullPath
        .split('/')
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList(growable: false);
    if (parts.length < 2) return null;
    return parts.sublist(0, parts.length - 1).join(' / ');
  }
}

class _BrandSelector extends StatelessWidget {
  const _BrandSelector({
    required this.line,
    required this.enabled,
    required this.onChanged,
    this.showLabel = true,
  });

  final OcrProductReviewLine line;
  final bool enabled;
  final ValueChanged<ProductBrand?>? onChanged;
  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    return VbSearchableSelect<ProductBrand>(
      key: Key('ocr-review-brand-${line.id}'),
      value: line.brand,
      label: 'Marca',
      showLabel: showLabel,
      sheetTitle: 'Elegir marca',
      placeholder: 'Sin marca',
      semanticLabel: 'Marca del producto',
      allowClear: true,
      errorText: line.brandValidationMessage,
      helperText: line.brandWarning,
      onChanged: enabled ? onChanged : null,
      options: <VbSearchableSelectOption<ProductBrand>>[
        for (final brand in line.brands)
          VbSearchableSelectOption<ProductBrand>(
            value: brand,
            label: brand.name,
          ),
      ],
    );
  }
}

/// The one cell that says what happens to this line, and offers the two peer
/// decisions. Alternatives open centred; nothing expands in place.
class _DecisionCell extends StatelessWidget {
  const _DecisionCell({
    required this.line,
    required this.callbacks,
    required this.enabled,
  });

  final OcrProductReviewLine line;
  final OcrProductReviewCallbacks callbacks;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final roles = VinabikeThemeRoles.of(context);

    switch (line.status) {
      case OcrProductReviewStatus.searching:
        return Row(
          children: [
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: _OcrProductReviewWorkspaceState.space2),
            Expanded(
              child: Text(
                'Buscando parecidos',
                key: Key('ocr-review-searching-${line.id}'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        );

      case OcrProductReviewStatus.failed:
        return _DecisionActions(
          message: line.errorMessage ?? 'No se pudo revisar',
          tone: roles.danger,
          primaryLabel: 'Reintentar',
          primaryKey: Key('ocr-review-retry-${line.id}'),
          onPrimary: enabled && callbacks.onRetryLine != null
              ? () => callbacks.onRetryLine!(line.id)
              : null,
        );

      case OcrProductReviewStatus.needsSearch:
        return _DecisionActions(
          message: 'Sin revisar',
          tone: roles.neutral,
          primaryLabel: 'Buscar',
          primaryKey: Key('ocr-review-search-${line.id}'),
          onPrimary: enabled && callbacks.onRetryLine != null
              ? () => callbacks.onRetryLine!(line.id)
              : null,
        );

      case OcrProductReviewStatus.linked:
      case OcrProductReviewStatus.newProductReady:
      case OcrProductReviewStatus.readOnly:
        final resolved = line.status == OcrProductReviewStatus.linked
            ? 'Vinculado a ${line.resolvedProductSku ?? ''} '
                    '${line.resolvedProductName ?? ''}'
                .trim()
            : 'Se creará nuevo';
        return Row(
          children: [
            Icon(Icons.check_circle, size: 15, color: roles.success.accent),
            const SizedBox(width: _OcrProductReviewWorkspaceState.space2),
            Expanded(
              child: Text(
                resolved,
                key: Key('ocr-review-resolved-${line.id}'),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall,
              ),
            ),
            if (enabled && callbacks.onChangeDecision != null)
              TextButton(
                key: Key('ocr-review-change-${line.id}'),
                onPressed: () => callbacks.onChangeDecision!(line.id),
                style: _tinyButtonStyle,
                child: const Text('Cambiar'),
              ),
          ],
        );

      case OcrProductReviewStatus.noCandidates:
        return _DecisionActions(
          message: 'Sin coincidencia fiable',
          tone: roles.neutral,
          primaryLabel: 'Crear nuevo',
          primaryKey: Key('ocr-review-new-${line.id}'),
          onPrimary: enabled && callbacks.onConfirmNewProduct != null
              ? () => callbacks.onConfirmNewProduct!(line.id)
              : null,
          secondaryLabel: 'Buscar',
          secondaryKey: Key('ocr-review-alternatives-${line.id}'),
          onSecondary: enabled && callbacks.onOpenCandidates != null
              ? () => callbacks.onOpenCandidates!(line.id)
              : null,
        );

      case OcrProductReviewStatus.ready:
        final best = line.bestCandidate;
        if (best == null) {
          return _DecisionActions(
            message: 'Sin coincidencia fiable',
            tone: roles.neutral,
            primaryLabel: 'Crear nuevo',
            primaryKey: Key('ocr-review-new-${line.id}'),
            onPrimary: enabled && callbacks.onConfirmNewProduct != null
                ? () => callbacks.onConfirmNewProduct!(line.id)
                : null,
          );
        }
        final evidence = _EvidencePresentation.forTier(best.matchTier);
        final tone = evidence.resolveTone(roles);
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: tone.container,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: tone.border),
                  ),
                  child: Text(
                    evidence.label,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: tone.onContainer,
                      fontWeight: FontWeight.w600,
                      fontSize: 10,
                    ),
                  ),
                ),
                const SizedBox(width: _OcrProductReviewWorkspaceState.space1),
                Expanded(
                  child: Text(
                    best.product.name,
                    key: Key(
                      'ocr-review-candidate-${line.id}-${best.product.id ?? best.product.sku}',
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            _ActionRow(
              children: [
                // The two peer decisions stay in the row, as the surface
                // registry requires. Everything else about the choice —
                // the other candidates, a manual search, the photos — lives
                // one click away in the centred picker, because a row this
                // narrow cannot hold them without either truncating a label
                // or growing taller than its neighbours.
                FilledButton(
                  key: Key('ocr-review-link-${line.id}'),
                  onPressed: enabled && callbacks.onLinkCandidate != null
                      ? () => callbacks.onLinkCandidate!(line.id, best.product)
                      : null,
                  style: _tinyFilledStyle,
                  child: const Text('Vincular'),
                ),
                const SizedBox(width: _OcrProductReviewWorkspaceState.space1),
                TextButton(
                  key: Key('ocr-review-new-${line.id}'),
                  onPressed: enabled && callbacks.onConfirmNewProduct != null
                      ? () => callbacks.onConfirmNewProduct!(line.id)
                      : null,
                  style: _tinyButtonStyle,
                  child: const Text('Nuevo'),
                ),
                const SizedBox(width: _OcrProductReviewWorkspaceState.space1),
                IconButton(
                  key: Key('ocr-review-alternatives-${line.id}'),
                  onPressed: enabled && callbacks.onOpenCandidates != null
                      ? () => callbacks.onOpenCandidates!(line.id)
                      : null,
                  tooltip: line.candidates.length > 1
                      ? 'Ver los ${line.candidates.length} parecidos'
                      : 'Ver el parecido y buscar otro',
                  iconSize: 16,
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 26,
                    minHeight: 26,
                  ),
                  icon: const Icon(Icons.more_horiz),
                ),
              ],
            ),
          ],
        );
    }
  }
}

class _DecisionActions extends StatelessWidget {
  const _DecisionActions({
    required this.message,
    required this.tone,
    required this.primaryLabel,
    required this.primaryKey,
    required this.onPrimary,
    this.secondaryLabel,
    this.secondaryKey,
    this.onSecondary,
  });

  final String message;
  final VinabikeSemanticTone tone;
  final String primaryLabel;
  final Key primaryKey;
  final VoidCallback? onPrimary;
  final String? secondaryLabel;
  final Key? secondaryKey;
  final VoidCallback? onSecondary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          message,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.labelSmall?.copyWith(color: tone.accent),
        ),
        const SizedBox(height: 2),
        _ActionRow(
          children: [
            FilledButton(
              key: primaryKey,
              onPressed: onPrimary,
              style: _tinyFilledStyle,
              child: Text(primaryLabel),
            ),
            if (secondaryLabel != null) ...[
              const SizedBox(width: _OcrProductReviewWorkspaceState.space1),
              TextButton(
                key: secondaryKey,
                onPressed: onSecondary,
                style: _tinyButtonStyle,
                child: Text(secondaryLabel!),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

/// A row of row-level actions that never overflows its cell.
///
/// Real desktop text fits comfortably in the decision column. Text scaling,
/// a longer localisation, or the widget-test font (which measures about double)
/// can still push three controls past the cell, and an overflow stripe is a
/// defect even when the pixels are only in a test. Scaling down is the graceful
/// degradation; clipping the operator's only action is not.
class _ActionRow extends StatelessWidget {
  const _ActionRow({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Row(mainAxisSize: MainAxisSize.min, children: children),
    );
  }
}

final ButtonStyle _tinyButtonStyle = TextButton.styleFrom(
  minimumSize: const Size(0, 26),
  padding: const EdgeInsets.symmetric(horizontal: 8),
  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
  textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
);

final ButtonStyle _tinyFilledStyle = FilledButton.styleFrom(
  minimumSize: const Size(0, 26),
  padding: const EdgeInsets.symmetric(horizontal: 10),
  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
  textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
);

// ───────────────────────────────────────────────────────────────────────────
// Compact composition
// ───────────────────────────────────────────────────────────────────────────

/// Phone and small-tablet hosts get the same controllers and commands as one
/// divider-separated line editor per source row.
///
/// Not cards: a bordered box per record turned a seven-line invoice into a wall
/// the operator had to scroll through twice to compare two prices. Dividers
/// keep the batch readable as a single list while every field stays full width
/// and every target stays 48 px.
class _CompactLineList extends StatelessWidget {
  const _CompactLineList({
    required this.lines,
    required this.selectedLineId,
    required this.callbacks,
    required this.readOnly,
  });

  final List<OcrProductReviewLine> lines;
  final String? selectedLineId;
  final OcrProductReviewCallbacks callbacks;
  final bool readOnly;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var index = 0; index < lines.length; index++) ...[
          if (index > 0)
            Divider(height: 1, thickness: 1, color: theme.dividerColor),
          _CompactLineEditor(
            key: ValueKey<String>('ocr-review-row-${lines[index].id}'),
            line: lines[index],
            index: index,
            selected: lines[index].id == selectedLineId,
            callbacks: callbacks,
            readOnly: readOnly,
          ),
        ],
      ],
    );
  }
}

class _CompactLineEditor extends StatelessWidget {
  const _CompactLineEditor({
    super.key,
    required this.line,
    required this.index,
    required this.selected,
    required this.callbacks,
    required this.readOnly,
  });

  final OcrProductReviewLine line;
  final int index;
  final bool selected;
  final OcrProductReviewCallbacks callbacks;
  final bool readOnly;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final roles = VinabikeThemeRoles.of(context);
    // A row whose SKU is being reserved holds an operation against the
    // shared AE sequence. Its controls stay inert until that settles.
    final disabled = readOnly || !line.isSelected || line.isReservingSku;
    final status = _StatusPresentation.forStatus(line.status);

    return Container(
      color: selected ? roles.selectionContainer : null,
      padding: const EdgeInsets.symmetric(
        vertical: _OcrProductReviewWorkspaceState.space3,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: _OcrProductReviewWorkspaceState.touchTarget,
                height: _OcrProductReviewWorkspaceState.touchTarget,
                child: Checkbox(
                  key: Key('ocr-review-select-${line.id}'),
                  value: line.isSelected,
                  onChanged: readOnly || callbacks.onSelectionChanged == null
                      ? null
                      : (value) => callbacks.onSelectionChanged!(
                            line.id,
                            value ?? false,
                          ),
                ),
              ),
              _EditableSourceImage(
                line: line,
                callbacks: callbacks,
                size: 44,
                enabled: !readOnly,
              ),
              const SizedBox(width: _OcrProductReviewWorkspaceState.space3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${index + 1} · ${line.originalTitle}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(
                      height: _OcrProductReviewWorkspaceState.space1,
                    ),
                    VbStatusBadge(label: status.label, tone: status.tone),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: _OcrProductReviewWorkspaceState.space3),
          _CompactFieldPair(
            first: _LabeledField(
              label: 'SKU',
              origin: line.skuOrigin,
              child: _SkuCell(
                line: line,
                enabled: !disabled,
                callbacks: callbacks,
              ),
            ),
            second: _LabeledField(
              label: 'Nombre',
              origin: line.nameOrigin,
              child: _CompactField(
                fieldKey: Key('ocr-review-name-${line.id}'),
                controller: line.controllers.name,
                enabled: !disabled,
                origin: line.nameOrigin,
                onChanged: callbacks.onNameChanged == null
                    ? null
                    : (value) => callbacks.onNameChanged!(line.id, value),
              ),
            ),
          ),
          const SizedBox(height: _OcrProductReviewWorkspaceState.space2),
          _CompactFieldPair(
            first: _CategorySelector(
              line: line,
              enabled: !disabled,
              onChanged: callbacks.onCategoryChanged == null
                  ? null
                  : (value) => callbacks.onCategoryChanged!(line.id, value),
            ),
            second: _BrandSelector(
              line: line,
              enabled: !disabled,
              onChanged: callbacks.onBrandChanged == null
                  ? null
                  : (value) => callbacks.onBrandChanged!(line.id, value),
            ),
          ),
          const SizedBox(height: _OcrProductReviewWorkspaceState.space2),
          _CompactFieldPair(
            first: _LabeledField(
              label: 'Costo',
              origin: line.costOrigin,
              child: _CompactField(
                fieldKey: Key('ocr-review-cost-${line.id}'),
                controller: line.controllers.cost,
                enabled: !disabled,
                numeric: true,
                origin: line.costOrigin,
                onChanged: callbacks.onCostChanged == null
                    ? null
                    : (value) => callbacks.onCostChanged!(line.id, value),
              ),
            ),
            second: _LabeledField(
              label: 'Precio',
              origin: line.priceOrigin,
              child: _CompactField(
                fieldKey: Key('ocr-review-price-${line.id}'),
                controller: line.controllers.price,
                enabled: !disabled,
                numeric: true,
                origin: line.priceOrigin,
                onChanged: callbacks.onPriceChanged == null
                    ? null
                    : (value) => callbacks.onPriceChanged!(line.id, value),
              ),
            ),
          ),
          const SizedBox(height: _OcrProductReviewWorkspaceState.space3),
          Row(
            children: [
              Expanded(
                child: _DecisionCell(
                  line: line,
                  callbacks: callbacks,
                  enabled: !disabled,
                ),
              ),
              const SizedBox(width: _OcrProductReviewWorkspaceState.space2),
              Semantics(
                label: 'Se vende',
                child: Switch(
                  key: Key('ocr-review-sold-${line.id}'),
                  value: line.isSold,
                  onChanged: disabled || callbacks.onSoldChanged == null
                      ? null
                      : (value) => callbacks.onSoldChanged!(line.id, value),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CompactFieldPair extends StatelessWidget {
  const _CompactFieldPair({required this.first, required this.second});

  final Widget first;
  final Widget second;

  /// Under this the two fields stack: a 160 px selector next to a 160 px field
  /// is two unusable controls, not a compact row.
  static const double pairBreakpoint = 460;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < pairBreakpoint) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              first,
              const SizedBox(height: _OcrProductReviewWorkspaceState.space2),
              second,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: first),
            const SizedBox(width: _OcrProductReviewWorkspaceState.space3),
            Expanded(child: second),
          ],
        );
      },
    );
  }
}

class _LabeledField extends StatelessWidget {
  const _LabeledField({
    required this.label,
    required this.origin,
    required this.child,
  });

  final String label;
  final OcrProductFieldOrigin origin;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(width: _OcrProductReviewWorkspaceState.space1),
            Text(
              _originLabel(origin),
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontSize: 10,
              ),
            ),
          ],
        ),
        const SizedBox(height: 5),
        child,
      ],
    );
  }
}

// ───────────────────────────────────────────────────────────────────────────
// Footer
// ───────────────────────────────────────────────────────────────────────────

class _WorkspaceFooter extends StatelessWidget {
  const _WorkspaceFooter({
    required this.primaryLabel,
    required this.pricingPolicyLabel,
    required this.progress,
    required this.primaryEnabled,
    required this.primaryBlockingReason,
    required this.costIncludesVat,
    required this.onCostIncludesVatChanged,
    required this.onBack,
    required this.onPrimary,
    required this.touch,
    required this.readOnly,
  });

  final String primaryLabel;
  final String pricingPolicyLabel;
  final OcrProductReviewProgress progress;
  final bool primaryEnabled;
  final String? primaryBlockingReason;
  final bool costIncludesVat;
  final ValueChanged<bool>? onCostIncludesVatChanged;
  final VoidCallback? onBack;
  final VoidCallback? onPrimary;
  final bool touch;
  final bool readOnly;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final roles = VinabikeThemeRoles.of(context);
    final reason = readOnly
        ? 'Creando productos. Espera a que termine antes de volver.'
        : !primaryEnabled
            ? (primaryBlockingReason ?? progress.nextStep)
            : progress.nextStep;

    final policy = Semantics(
      container: true,
      label:
          '$pricingPolicyLabel. ${costIncludesVat ? 'El costo incluye IVA' : 'El costo no incluye IVA'}',
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Switch(
              value: costIncludesVat,
              onChanged: onCostIncludesVatChanged,
            ),
            const SizedBox(width: _OcrProductReviewWorkspaceState.space2),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    costIncludesVat ? 'Costo con IVA' : 'Costo sin IVA',
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    pricingPolicyLabel,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );

    final buttons = <Widget>[
      if (onBack != null)
        OutlinedButton(
          key: const Key('ocr-review-back'),
          onPressed: onBack,
          style: _footerButtonStyle(touch),
          child: const Text('Volver a la factura'),
        ),
      FilledButton.icon(
        key: const Key('ocr-review-primary'),
        onPressed: primaryEnabled ? onPrimary : null,
        icon: const Icon(Icons.check),
        label: Text(primaryLabel),
        style: _footerButtonStyle(touch),
      ),
    ];

    return Material(
      color: theme.colorScheme.surface,
      shadowColor: roles.shadow,
      elevation: theme.brightness == Brightness.dark ? 0 : 1,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: touch
              ? _OcrProductReviewWorkspaceState.space3
              : _OcrProductReviewWorkspaceState.space5,
          vertical: touch
              ? _OcrProductReviewWorkspaceState.space2
              : _OcrProductReviewWorkspaceState.space3,
        ),
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(
              color: theme.colorScheme.outlineVariant,
              width: _OcrProductReviewWorkspaceState.hairline,
            ),
          ),
        ),
        child: touch
            ? Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  policy,
                  const SizedBox(
                    height: _OcrProductReviewWorkspaceState.space1,
                  ),
                  _NextStep(reason: reason, blocking: !primaryEnabled),
                  const SizedBox(
                    height: _OcrProductReviewWorkspaceState.space2,
                  ),
                  Row(
                    children: [
                      for (var index = 0; index < buttons.length; index++) ...[
                        Expanded(child: buttons[index]),
                        if (index != buttons.length - 1)
                          const SizedBox(
                            width: _OcrProductReviewWorkspaceState.space2,
                          ),
                      ],
                    ],
                  ),
                ],
              )
            : Row(
                children: [
                  Flexible(flex: 3, child: policy),
                  const SizedBox(
                    width: _OcrProductReviewWorkspaceState.space4,
                  ),
                  Expanded(
                    child: _NextStep(
                      reason: reason,
                      blocking: !primaryEnabled,
                    ),
                  ),
                  const SizedBox(
                    width: _OcrProductReviewWorkspaceState.space3,
                  ),
                  for (var index = 0; index < buttons.length; index++) ...[
                    buttons[index],
                    if (index != buttons.length - 1)
                      const SizedBox(
                        width: _OcrProductReviewWorkspaceState.space2,
                      ),
                  ],
                ],
              ),
      ),
    );
  }
}

/// Says the exact next step, always — not only when something is blocked.
class _NextStep extends StatelessWidget {
  const _NextStep({required this.reason, required this.blocking});

  final String reason;
  final bool blocking;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final roles = VinabikeThemeRoles.of(context);
    final color =
        blocking ? roles.warning.accent : theme.colorScheme.onSurfaceVariant;
    return Semantics(
      liveRegion: true,
      label: reason,
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              blocking ? Icons.info_outline : Icons.check_circle_outline,
              size: 16,
              color: color,
            ),
            const SizedBox(width: _OcrProductReviewWorkspaceState.space2),
            Flexible(
              child: Text(
                reason,
                key: const Key('ocr-review-next-step'),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(color: color),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ───────────────────────────────────────────────────────────────────────────
// Shared bits
// ───────────────────────────────────────────────────────────────────────────

class _EditableSourceImage extends StatelessWidget {
  const _EditableSourceImage({
    required this.line,
    required this.callbacks,
    required this.size,
    required this.enabled,
  });

  final OcrProductReviewLine line;
  final OcrProductReviewCallbacks callbacks;
  final double size;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final canReplace = enabled && callbacks.onReplaceImage != null;
    final canRemove = enabled &&
        line.imageUrl?.trim().isNotEmpty == true &&
        callbacks.onRemoveImage != null;

    if (!canReplace && !canRemove) {
      return _ProductImage(
        imageUrl: line.imageUrl,
        imageBytes: line.imageBytes,
        size: size,
      );
    }

    return PopupMenuButton<_SourceImageAction>(
      key: Key('ocr-review-image-${line.id}'),
      tooltip: line.imageUrl?.trim().isNotEmpty == true
          ? 'Cambiar imagen del producto'
          : 'Agregar imagen al producto',
      enabled: !line.isUploadingImage,
      onSelected: (action) {
        switch (action) {
          case _SourceImageAction.replace:
            callbacks.onReplaceImage?.call(line.id);
            break;
          case _SourceImageAction.remove:
            callbacks.onRemoveImage?.call(line.id);
            break;
        }
      },
      itemBuilder: (context) => [
        if (canReplace)
          const PopupMenuItem(
            value: _SourceImageAction.replace,
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.add_photo_alternate_outlined),
              title: Text('Reemplazar imagen'),
            ),
          ),
        if (canRemove)
          PopupMenuItem(
            key: Key('ocr-review-remove-image-${line.id}'),
            value: _SourceImageAction.remove,
            child: const ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.delete_outline),
              title: Text('Quitar imagen'),
            ),
          ),
      ],
      child: _ProductImage(
        imageUrl: line.imageUrl,
        imageBytes: line.imageBytes,
        size: size,
        busy: line.isUploadingImage,
      ),
    );
  }
}

enum _SourceImageAction { replace, remove }

class _ProductImage extends StatelessWidget {
  const _ProductImage({
    required this.imageUrl,
    required this.size,
    this.imageBytes,
    this.busy = false,
  });

  final String? imageUrl;
  final Uint8List? imageBytes;
  final double size;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final url = imageUrl?.trim();
    final memoryBytes = imageBytes;
    final fallback = ColoredBox(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Icon(
        Icons.inventory_2_outlined,
        size: size * 0.5,
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
    return ExcludeSemantics(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: SizedBox(
          width: size,
          height: size,
          child: busy
              ? const Center(
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : memoryBytes != null
                  ? Image.memory(
                      memoryBytes,
                      width: size,
                      height: size,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => fallback,
                    )
                  : url == null || url.isEmpty
                      ? fallback
                      : Image.network(
                          url,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => fallback,
                        ),
        ),
      ),
    );
  }
}

@immutable
class _StatusPresentation {
  const _StatusPresentation(this.label, this.tone);

  factory _StatusPresentation.forStatus(OcrProductReviewStatus status) {
    return switch (status) {
      OcrProductReviewStatus.needsSearch =>
        const _StatusPresentation('Sin revisar', VbStatusTone.info),
      OcrProductReviewStatus.searching =>
        const _StatusPresentation('Buscando', VbStatusTone.info),
      OcrProductReviewStatus.ready =>
        const _StatusPresentation('Por decidir', VbStatusTone.warning),
      OcrProductReviewStatus.noCandidates =>
        const _StatusPresentation('Sin coincidencia', VbStatusTone.info),
      OcrProductReviewStatus.failed =>
        const _StatusPresentation('No se pudo revisar', VbStatusTone.danger),
      OcrProductReviewStatus.linked =>
        const _StatusPresentation('Vinculado', VbStatusTone.success),
      OcrProductReviewStatus.newProductReady =>
        const _StatusPresentation('Producto nuevo', VbStatusTone.success),
      OcrProductReviewStatus.readOnly =>
        const _StatusPresentation('Solo lectura', VbStatusTone.neutral),
    };
  }

  final String label;
  final VbStatusTone tone;
}

@immutable
class _EvidencePresentation {
  const _EvidencePresentation(this.label, this.tone);

  factory _EvidencePresentation.forTier(ProductDuplicateMatchTier tier) {
    return switch (tier) {
      ProductDuplicateMatchTier.exact =>
        const _EvidencePresentation('Es el mismo', VbStatusTone.success),
      ProductDuplicateMatchTier.strong =>
        const _EvidencePresentation('Casi seguro', VbStatusTone.info),
      ProductDuplicateMatchTier.possible =>
        const _EvidencePresentation('Parecido', VbStatusTone.neutral),
      // A row never recommends a ruled-out product. It only reaches this
      // surface if one is passed in by mistake, and it must still read
      // honestly rather than borrow another tier's word.
      ProductDuplicateMatchTier.ruledOut =>
        const _EvidencePresentation('Descartado', VbStatusTone.warning),
    };
  }

  final String label;
  final VbStatusTone tone;

  VinabikeSemanticTone resolveTone(VinabikeThemeRoles roles) {
    return switch (tone) {
      VbStatusTone.neutral => roles.neutral,
      VbStatusTone.info => roles.info,
      VbStatusTone.success => roles.success,
      VbStatusTone.warning => roles.warning,
      VbStatusTone.danger => roles.danger,
    };
  }
}

ButtonStyle _footerButtonStyle(bool touch) {
  return ButtonStyle(
    minimumSize: WidgetStatePropertyAll(
      Size(
        _OcrProductReviewWorkspaceState.touchTarget,
        touch ? _OcrProductReviewWorkspaceState.touchTarget : 40,
      ),
    ),
  );
}

String _originLabel(OcrProductFieldOrigin origin) {
  return switch (origin) {
    OcrProductFieldOrigin.invoice => 'de la factura',
    OcrProductFieldOrigin.aiCleaned => 'limpiado por IA',
    OcrProductFieldOrigin.aiSuggested => 'sugerida por IA',
    OcrProductFieldOrigin.nameDerived => 'deducido del nombre',
    OcrProductFieldOrigin.pricePolicy => 'costo × 2',
    OcrProductFieldOrigin.reserved => 'reservado',
    OcrProductFieldOrigin.user => 'tuyo',
  };
}
