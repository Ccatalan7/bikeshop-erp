import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../modules/inventory/models/brand_models.dart';
import '../../modules/inventory/models/category_models.dart';
import '../../modules/inventory/models/inventory_models.dart';
import '../../modules/inventory/models/product_duplicate_candidate.dart';
import '../themes/vinabike_theme_roles.dart';
import '../services/ocr_purchase_review_flow.dart';
import 'vb_notice.dart';
import 'vb_money_text.dart';
import 'ocr_review_evidence.dart';
import 'vb_searchable_select.dart';
import 'vb_status_badge.dart';

part 'ocr_product_review_steps.dart';

enum OcrProductReviewStatus {
  needsSearch,
  searching,
  ready,
  abstained,
  noCandidates,
  failed,
  linked,
  newProductReady,
  readOnly,
}

enum OcrProductResolvedMode {
  catalogLink,
  rememberedLink,
  rememberedComposite,
  rememberedPack,
  rememberedSet,
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
    this.resolutionComponents = const [],
    this.imageUrl,
    this.imageBytes,
    this.candidates = const [],
    this.viableCandidateCount = 0,
    this.discardedCandidateCount = 0,
    this.categoryConflictCount = 0,
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
    this.aiCompositeProposal,
    this.canConfirmCompositeProposal = false,
    this.hasRememberedSuggestion = false,
    this.isPreparingNewProduct = false,
    this.canConfirmNewProduct = true,
    this.newProductUnitsController,
    this.newProductInventoryQuantity,
    this.categoryValidationMessage,
    this.brandValidationMessage,
    this.brandWarning,
    this.siblingSuggestion,
    this.siblingLineId,
    this.resolvedProductName,
    this.resolvedProductSku,
    this.resolvedOutcomeSummary,
    this.resolvedMode = OcrProductResolvedMode.catalogLink,
    this.canChangeResolvedDecision = true,
    this.isSelected = true,
    this.inspectionOnly = false,
    this.identityDecision = OcrProductIdentityDecision.undecided,
    this.inventoryProduct,
    this.inventoryOrigin,
    this.purchaseQuantityController,
    this.purchaseUnitCostController,
    this.purchaseTotalController,
    this.purchaseUnitsController,
    this.purchaseAmountsConfirmed = false,
    this.purchaseAmountsValid = false,
    this.appliedComposition = false,
    this.productAlreadyCreated = false,
  });

  final String id;
  final String sku;
  final String originalTitle;
  final String? supplierCode;
  final double? sourceQuantity;
  final double? sourceLineTotal;
  final List<OcrReviewComponent> resolutionComponents;
  final bool hasRememberedSuggestion;
  final bool isPreparingNewProduct;
  final bool canConfirmNewProduct;
  final TextEditingController? newProductUnitsController;
  final double? newProductInventoryQuantity;
  final String? imageUrl;
  final Uint8List? imageBytes;
  final OcrProductDraftControllers controllers;
  final OcrProductReviewStatus status;
  final List<ProductDuplicateCandidate> candidates;

  /// Cached same-category products that survived the identity gates. This may
  /// include viable rows below the recommendation floor; it never includes a
  /// product that the matcher discarded.
  final int viableCandidateCount;

  /// Cached same-family products that an identity gate discarded. They remain
  /// inspectable in the picker, but are never described as suggestions.
  final int discardedCandidateCount;

  /// Same-family products found outside the row's authoritative category.
  /// They require an explicit catalog-conflict review and never rank normally.
  final int categoryConflictCount;
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

  /// Cached proposal that this supplier line represents multiple catalog
  /// units. It is evidence until the operator confirms it; only then may the
  /// host persist an authoritative supplier-resolution graph.
  final String? aiCompositeProposal;
  final bool canConfirmCompositeProposal;

  final String? categoryValidationMessage;
  final String? brandValidationMessage;
  final String? brandWarning;
  final String? siblingSuggestion;
  final String? siblingLineId;
  final String? resolvedProductName;
  final String? resolvedProductSku;
  final String? resolvedOutcomeSummary;
  final OcrProductResolvedMode resolvedMode;
  final bool canChangeResolvedDecision;
  final bool isSelected;
  final bool inspectionOnly;
  final OcrProductIdentityDecision identityDecision;
  final Product? inventoryProduct;
  final String? inventoryOrigin;
  final TextEditingController? purchaseQuantityController;
  final TextEditingController? purchaseUnitCostController;
  final TextEditingController? purchaseTotalController;
  final TextEditingController? purchaseUnitsController;
  final bool purchaseAmountsConfirmed;
  final bool purchaseAmountsValid;
  final bool productAlreadyCreated;
  final bool appliedComposition;

  bool get identityConfirmed =>
      identityDecision == OcrProductIdentityDecision.newProduct ||
      (identityDecision == OcrProductIdentityDecision.existing &&
          inventoryProduct?.id != null);

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
    this.onPrepareNewProduct,
    this.onConfirmRememberedResolution,
    this.onNewProductUnitsChanged,
    this.onConfirmCompositeProposal,
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
    this.onOpenInventoryProduct,
    this.onEditComposition,
    this.onConfirmAmounts,
    this.onAmountsChanged,
  });

  final ValueChanged<String>? onLineSelected;
  final void Function(String lineId, bool selected)? onSelectionChanged;
  final void Function(String lineId, Product product)? onLinkCandidate;
  final ValueChanged<String>? onConfirmNewProduct;
  final ValueChanged<String>? onPrepareNewProduct;
  final ValueChanged<String>? onConfirmRememberedResolution;
  final void Function(String lineId, String value)? onNewProductUnitsChanged;
  final ValueChanged<String>? onConfirmCompositeProposal;
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
  final ValueChanged<Product>? onOpenInventoryProduct;
  final ValueChanged<String>? onEditComposition;
  final ValueChanged<String>? onConfirmAmounts;
  final void Function(String lineId, String field)? onAmountsChanged;
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

/// One ordered purchase batch with source, inventory outcome and explicit decisions.
/// Product editing and composition details are disclosed only for the chosen row;
/// controllers and commands remain owned by the uploader across every host.
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
    this.readOnlyReason,
    this.step = OcrPurchaseReviewStep.identify,
    this.backLabel = 'Volver a la factura',
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
  final String? readOnlyReason;
  final OcrPurchaseReviewStep step;
  final String backLabel;

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
  static const double space1 = 4;
  static const double space2 = 8;
  static const double space3 = 12;
  static const double space4 = 16;
  static const double space5 = 16;
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
                          step: widget.step,
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
                  backLabel: widget.backLabel,
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
                  readOnlyReason: widget.readOnlyReason,
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

/// T-01/T-03 batch and disclosure, F-04 spacing, F-06 touch density.
/// Values read from the canonical DesignSync component guide (cached tool result
/// c430e08f/.../bkyc7j0gj.txt). No feature palette or independent field family.
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
          height: MediaQuery.sizeOf(context).width < 900 ? 48 : 34,
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
        height: MediaQuery.sizeOf(context).width < 900 ? 48 : 34,
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
  });

  final OcrProductReviewLine line;
  final bool enabled;
  final ValueChanged<Category?>? onChanged;

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
      showLabel: true,
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
  });

  final OcrProductReviewLine line;
  final bool enabled;
  final ValueChanged<ProductBrand?>? onChanged;

  @override
  Widget build(BuildContext context) {
    return VbSearchableSelect<ProductBrand>(
      key: Key('ocr-review-brand-${line.id}'),
      value: line.brand,
      label: 'Marca',
      showLabel: true,
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

class _NewProductFields extends StatelessWidget {
  const _NewProductFields(
      {required this.line, required this.callbacks, required this.enabled});
  final OcrProductReviewLine line;
  final OcrProductReviewCallbacks callbacks;
  final bool enabled;
  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (line.newProductUnitsController != null) ...[
          _CompactFieldPair(
              first: TextField(
                  key: Key('ocr-review-new-units-${line.id}'),
                  controller: line.newProductUnitsController,
                  enabled: enabled,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                      labelText: 'Unidades de esta ficha por compra'),
                  onChanged: callbacks.onNewProductUnitsChanged == null
                      ? null
                      : (value) =>
                          callbacks.onNewProductUnitsChanged!(line.id, value)),
              second: Text(
                  line.newProductInventoryQuantity == null
                      ? 'Cantidad de inventario por definir'
                      : '${line.newProductInventoryQuantity! % 1 == 0 ? line.newProductInventoryQuantity!.toInt() : line.newProductInventoryQuantity} unidades al recibir',
                  style: Theme.of(context).textTheme.bodyMedium)),
          const SizedBox(height: 12),
        ],
        _CompactFieldPair(
          first: _LabeledField(
            label: 'SKU',
            origin: line.skuOrigin,
            child: _SkuCell(
              line: line,
              enabled: enabled,
              callbacks: callbacks,
            ),
          ),
          second: _LabeledField(
            label: 'Nombre',
            origin: line.nameOrigin,
            child: _CompactField(
              fieldKey: Key('ocr-review-name-${line.id}'),
              controller: line.controllers.name,
              enabled: enabled,
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
            enabled: enabled,
            onChanged: callbacks.onCategoryChanged == null
                ? null
                : (value) => callbacks.onCategoryChanged!(line.id, value),
          ),
          second: _BrandSelector(
            line: line,
            enabled: enabled,
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
              enabled: enabled,
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
              enabled: enabled,
              numeric: true,
              origin: line.priceOrigin,
              onChanged: callbacks.onPriceChanged == null
                  ? null
                  : (value) => callbacks.onPriceChanged!(line.id, value),
            ),
          ),
        ),
        SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Se vende'),
            value: line.isSold,
            onChanged: enabled && callbacks.onSoldChanged != null
                ? (value) => callbacks.onSoldChanged!(line.id, value)
                : null),
        if (callbacks.onReplaceImage != null)
          Row(children: [
            _EditableSourceImage(
                line: line, callbacks: callbacks, size: 48, enabled: enabled),
            const SizedBox(width: 12),
            const Text('Imagen del producto'),
          ]),
        if (line.siblingLineId != null && callbacks.onCopySibling != null)
          TextButton(
              onPressed: enabled
                  ? () => callbacks.onCopySibling!(line.id, line.siblingLineId!)
                  : null,
              child: const Text(
                  'Reutilizar categoría y marca de la otra variante')),
      ]);
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
    this.showOrigin = true,
  });

  final String label;
  final OcrProductFieldOrigin origin;
  final Widget child;
  final bool showOrigin;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Wrap(
          spacing: _OcrProductReviewWorkspaceState.space1,
          runSpacing: _OcrProductReviewWorkspaceState.space1,
          children: [
            Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
            ),
            if (showOrigin)
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
    required this.backLabel,
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
    this.readOnlyReason,
  });

  final String primaryLabel;
  final String backLabel;
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
  final String? readOnlyReason;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final roles = VinabikeThemeRoles.of(context);
    final reason = readOnly
        ? (readOnlyReason?.trim().isNotEmpty == true
            ? readOnlyReason!.trim()
            : 'Operación en curso. Espera a que termine antes de volver.')
        : !primaryEnabled
            ? (primaryBlockingReason ?? '')
            : '';

    final policy = PopupMenuButton<bool>(
      key: const Key('ocr-review-pricing'),
      tooltip: pricingPolicyLabel,
      enabled: onCostIncludesVatChanged != null,
      initialValue: costIncludesVat,
      onSelected: onCostIncludesVatChanged,
      itemBuilder: (_) => [
        CheckedPopupMenuItem(
            value: true,
            checked: costIncludesVat,
            child: const Text('Costo con IVA')),
        CheckedPopupMenuItem(
            value: false,
            checked: !costIncludesVat,
            child: const Text('Costo sin IVA')),
      ],
      child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(costIncludesVat ? 'Costo con IVA' : 'Costo sin IVA',
                style: theme.textTheme.labelSmall),
            const Icon(Icons.expand_more, size: 16),
          ])),
    );

    final buttons = <Widget>[
      if (onBack != null)
        OutlinedButton(
          key: const Key('ocr-review-back'),
          onPressed: onBack,
          style: _footerButtonStyle(touch),
          child: Text(backLabel),
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
                  Row(children: [
                    Expanded(
                        child: _NextStep(
                            reason: reason, blocking: !primaryEnabled)),
                    const SizedBox(width: 8),
                    policy
                  ]),
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
    OcrProductFieldOrigin.user => 'Revisión manual',
  };
}
