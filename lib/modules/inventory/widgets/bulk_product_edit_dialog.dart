import 'dart:async';
import 'dart:math' as math;

import 'package:cross_file/cross_file.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../shared/models/supplier.dart';
import '../../../shared/services/image_service.dart';
import '../../../shared/utils/chilean_utils.dart';
import '../models/brand_models.dart';
import '../models/bulk_product_edit_models.dart';
import '../models/category_models.dart';
import '../models/inventory_models.dart';
import '../services/bulk_product_edit_service.dart';

class BulkProductEditDialog extends StatefulWidget {
  const BulkProductEditDialog({
    super.key,
    required this.allProducts,
    required this.filteredProducts,
    required this.selectedProductIds,
    required this.categories,
    required this.brands,
    required this.suppliers,
    this.initialSource,
    this.lockSource = false,
  });

  final List<Product> allProducts;
  final List<Product> filteredProducts;
  final Set<String> selectedProductIds;
  final List<Category> categories;
  final List<ProductBrand> brands;
  final List<Supplier> suppliers;
  final BulkProductScopeSource? initialSource;
  final bool lockSource;

  @override
  State<BulkProductEditDialog> createState() => _BulkProductEditDialogState();
}

class _BulkProductEditDialogState extends State<BulkProductEditDialog> {
  final BulkProductEditService _service = BulkProductEditService();
  final ScrollController _rowsScrollController = ScrollController();
  final TextEditingController _keywordController = TextEditingController();
  final TextEditingController _specQueryController = TextEditingController();
  final TextEditingController _sharedNoteController = TextEditingController();
  final TextEditingController _sharedStockValueController =
      TextEditingController();
  final TextEditingController _priceValueController = TextEditingController();
  final TextEditingController _costValueController = TextEditingController();

  Timer? _scopeDebounce;
  int _stepIndex = 0;
  late BulkProductScopeSource _scopeSource;
  BulkProductEditOperation? _operation;
  BulkProductSmartFilters _filters = const BulkProductSmartFilters();

  BulkClassificationConfig _classificationConfig =
      const BulkClassificationConfig();
  BulkChannelsConfig _channelsConfig = const BulkChannelsConfig();
  BulkPricingConfig _pricingConfig = const BulkPricingConfig();
  late BulkStockSharedConfig _stockSharedConfig;

  bool _isRefreshingScope = false;
  bool _isApplying = false;
  bool _isDraggingImages = false;
  bool _onlyAssignWhenMissingImage = true;
  String? _applySummary;
  List<String> _applyErrors = const [];

  List<Product> _matchedProducts = const [];
  Set<String> _enabledRowIds = <String>{};
  Map<String, BulkClassificationRowDraft> _classificationDrafts =
      <String, BulkClassificationRowDraft>{};
  Map<String, BulkChannelsRowDraft> _channelsDrafts =
      <String, BulkChannelsRowDraft>{};
  Map<String, BulkPricingRowDraft> _pricingDrafts =
      <String, BulkPricingRowDraft>{};
  Map<String, BulkStockRowDraft> _stockDrafts = <String, BulkStockRowDraft>{};
  Map<String, BulkImageAssignment> _imageAssignments =
      <String, BulkImageAssignment>{};
  List<BulkImageFile> _imagePool = const [];

  static const Map<String, String> _reasonLabels = {
    'count': 'Reconteo / reevaluación',
    'found': 'Hallazgo / recuperación',
    'loss': 'Merma',
    'damage': 'Daño',
    'theft': 'Robo / extravío',
    'internal_use': 'Uso interno / taller',
    'manual': 'Otro ajuste manual',
  };

  static const List<String> _inboundReasonTypes = ['count', 'found', 'manual'];
  static const List<String> _outboundReasonTypes = [
    'count',
    'loss',
    'damage',
    'theft',
    'internal_use',
    'manual',
  ];

  List<String> _allowedDirectionsForReason(String reasonType) {
    switch (reasonType) {
      case 'loss':
      case 'damage':
      case 'theft':
      case 'internal_use':
        return const ['OUT'];
      case 'found':
        return const ['IN'];
      default:
        return const ['OUT', 'IN'];
    }
  }

  List<String> _reasonOptionsForDirection(String type) {
    return [..._outboundReasonTypes, ..._inboundReasonTypes]
        .toSet()
        .where((reasonType) =>
            _allowedDirectionsForReason(reasonType).contains(type))
        .toList(growable: false);
  }

  List<String> _sharedReasonOptionsForCurrentMode() {
    if (_stockSharedConfig.mode == BulkStockEditMode.target) {
      return const ['count', 'manual'];
    }
    return _stockSharedConfig.direction == BulkStockDirection.inwards
        ? _inboundReasonTypes
        : _outboundReasonTypes;
  }

  String? _directionForTargetDraft(Product product, BulkStockRowDraft draft) {
    if (draft.quantity > product.inventoryQty) return 'IN';
    if (draft.quantity < product.inventoryQty) return 'OUT';
    return null;
  }

  List<String> _reasonOptionsForDraft(
      Product product, BulkStockRowDraft draft) {
    if (_stockSharedConfig.mode == BulkStockEditMode.target) {
      final direction = _directionForTargetDraft(product, draft);
      if (direction == null) {
        return const ['count', 'manual'];
      }
      return _reasonOptionsForDirection(direction);
    }

    return _stockSharedConfig.direction == BulkStockDirection.inwards
        ? _inboundReasonTypes
        : _outboundReasonTypes;
  }

  void _normalizeStockDraftReasons() {
    _stockDrafts = {
      for (final product
          in _matchedProducts.where((product) => product.id != null))
        product.id!: () {
          final productId = product.id!;
          final draft = _stockDrafts[productId] ??
              BulkStockRowDraft(
                productId: productId,
                quantity: _stockSharedConfig.mode == BulkStockEditMode.target
                    ? product.inventoryQty
                    : (_stockSharedConfig.defaultQuantity ?? 0),
                reasonType: _stockSharedConfig.reasonType,
                note: _stockSharedConfig.sharedNote,
                enabled: true,
              );
          final allowedReasons = _reasonOptionsForDraft(product, draft);
          if (allowedReasons.contains(draft.reasonType)) {
            return draft;
          }
          return draft.copyWith(reasonType: allowedReasons.first);
        }(),
    };
  }

  @override
  void initState() {
    super.initState();
    _scopeSource = widget.initialSource ??
        (widget.selectedProductIds.isNotEmpty
            ? BulkProductScopeSource.selected
            : BulkProductScopeSource.filtered);
    _stockSharedConfig = BulkStockSharedConfig(
      effectiveAt: DateTime.now(),
    );
    _refreshScopePreview();
  }

  @override
  void dispose() {
    _scopeDebounce?.cancel();
    _rowsScrollController.dispose();
    _keywordController.dispose();
    _specQueryController.dispose();
    _sharedNoteController.dispose();
    _sharedStockValueController.dispose();
    _priceValueController.dispose();
    _costValueController.dispose();
    super.dispose();
  }

  List<Product> get _baseScopeProducts {
    switch (_scopeSource) {
      case BulkProductScopeSource.selected:
        return widget.allProducts
            .where((product) => widget.selectedProductIds.contains(product.id))
            .toList(growable: false);
      case BulkProductScopeSource.filtered:
        return widget.filteredProducts;
      case BulkProductScopeSource.all:
        return widget.allProducts;
    }
  }

  int get _missingCategoryCount => _matchedProducts
      .where((product) => (product.categoryId ?? '').trim().isEmpty)
      .length;

  int get _missingBrandCount => _matchedProducts
      .where((product) =>
          (product.brandId ?? '').trim().isEmpty &&
          (product.brand ?? '').trim().isEmpty)
      .length;

  int get _missingImageCount => _matchedProducts
      .where((product) => (product.imageUrl ?? '').trim().isEmpty)
      .length;

  Future<void> _refreshScopePreview() async {
    final baseProducts = _baseScopeProducts;
    setState(() {
      _isRefreshingScope = true;
      _applySummary = null;
      _applyErrors = const [];
    });

    Map<String, String> specIndex = const {};
    if (_filters.hasSpecQuery) {
      specIndex = await _service.loadSpecSearchIndex(
        baseProducts.map((product) => product.id).whereType<String>(),
      );
    }

    final matched = _service.applyScopeFilters(
      baseProducts: baseProducts,
      filters: _filters,
      specSearchIndex: specIndex,
    );

    if (!mounted) return;

    setState(() {
      _matchedProducts = matched;
      _enabledRowIds = {
        for (final product in matched)
          if (_enabledRowIds.isEmpty || _enabledRowIds.contains(product.id))
            if (product.id != null) product.id!,
      };
      if (_enabledRowIds.isEmpty) {
        _enabledRowIds = {
          for (final product in matched)
            if (product.id != null) product.id!,
        };
      }
      _syncClassificationDrafts();
      _syncChannelsDrafts();
      _syncPricingDrafts();
      _syncStockDrafts();
      _syncImageAssignments();
      _isRefreshingScope = false;
    });
  }

  void _scheduleScopeRefresh() {
    _scopeDebounce?.cancel();
    _scopeDebounce =
        Timer(const Duration(milliseconds: 220), _refreshScopePreview);
  }

  void _syncStockDrafts() {
    final next = <String, BulkStockRowDraft>{};
    for (final product
        in _matchedProducts.where((product) => product.id != null)) {
      final productId = product.id!;
      final existing = _stockDrafts[productId];
      next[productId] = existing ??
          BulkStockRowDraft(
            productId: productId,
            quantity: _stockSharedConfig.mode == BulkStockEditMode.target
                ? product.inventoryQty
                : (_stockSharedConfig.defaultQuantity ?? 0),
            reasonType: _stockSharedConfig.reasonType,
            note: _stockSharedConfig.sharedNote,
            enabled: true,
          );
    }
    _stockDrafts = next;
    _normalizeStockDraftReasons();
  }

  void _syncClassificationDrafts() {
    final next = <String, BulkClassificationRowDraft>{};
    for (final product
        in _matchedProducts.where((product) => product.id != null)) {
      final productId = product.id!;
      next[productId] = _classificationDrafts[productId] ??
          BulkClassificationRowDraft(
            productId: productId,
            categoryId: product.categoryId,
            categoryName: product.categoryName,
            brandId: product.brandId,
            brandName: product.brand,
            supplierId: product.supplierId,
            supplierName: product.supplierName,
          );
    }
    _classificationDrafts = next;
  }

  void _syncChannelsDrafts() {
    final next = <String, BulkChannelsRowDraft>{};
    for (final product
        in _matchedProducts.where((product) => product.id != null)) {
      final productId = product.id!;
      next[productId] = _channelsDrafts[productId] ??
          BulkChannelsRowDraft(
            productId: productId,
            website: product.isPublished,
            googleMerchant: product.isGoogleMerchant,
            active: product.isActive,
          );
    }
    _channelsDrafts = next;
  }

  void _syncPricingDrafts() {
    final next = <String, BulkPricingRowDraft>{};
    for (final product
        in _matchedProducts.where((product) => product.id != null)) {
      final productId = product.id!;
      next[productId] = _pricingDrafts[productId] ??
          BulkPricingRowDraft(
            productId: productId,
            price: product.price,
            cost: product.cost,
          );
    }
    _pricingDrafts = next;
  }

  void _syncImageAssignments() {
    final next = <String, BulkImageAssignment>{};
    for (final product
        in _matchedProducts.where((product) => product.id != null)) {
      final productId = product.id!;
      next[productId] = _imageAssignments[productId] ??
          BulkImageAssignment(productId: productId);
    }
    _imageAssignments = next;

    if (_imagePool.isNotEmpty) {
      final emptyTargets = _matchedProducts.where((product) {
        final assignment = _imageAssignments[product.id];
        return product.id != null && assignment?.file == null;
      }).toList(growable: false);
      final autoAssignments = _service.autoAssignImages(
        products: emptyTargets,
        files: _imagePool,
      );
      for (final entry in autoAssignments.entries) {
        final current = _imageAssignments[entry.key];
        if (current != null && current.file == null) {
          _imageAssignments[entry.key] = current.copyWith(file: entry.value);
        }
      }
    }
  }

  bool get _canMoveNextFromScope => _matchedProducts.isNotEmpty;

  bool get _canApply {
    switch (_operation) {
      case BulkProductEditOperation.classification:
        return _classificationDrafts.values.any((draft) => draft.enabled);
      case BulkProductEditOperation.channels:
        return _channelsDrafts.values.any((draft) => draft.enabled);
      case BulkProductEditOperation.pricing:
        return _pricingDrafts.values.any((draft) => draft.enabled);
      case BulkProductEditOperation.stock:
        return _stockDrafts.values.any((draft) => draft.enabled);
      case BulkProductEditOperation.images:
        return _imageAssignments.values
            .any((assignment) => assignment.enabled && assignment.file != null);
      case null:
        return false;
    }
  }

  Future<void> _handleApply() async {
    if (_operation == null || !_canApply) return;

    setState(() {
      _isApplying = true;
      _applySummary = null;
      _applyErrors = const [];
    });

    late final BulkUpdateResult result;
    switch (_operation!) {
      case BulkProductEditOperation.classification:
        result = await _service.applyClassification(
          products: _matchedProducts,
          drafts: _classificationDrafts,
        );
      case BulkProductEditOperation.channels:
        result = await _service.applyChannels(
          products: _matchedProducts,
          drafts: _channelsDrafts,
        );
      case BulkProductEditOperation.pricing:
        result = await _service.applyPricing(
          products: _matchedProducts,
          drafts: _pricingDrafts,
        );
      case BulkProductEditOperation.stock:
        result = await _service.applyStock(
          products: _matchedProducts,
          sharedConfig: _stockSharedConfig,
          drafts: _stockDrafts,
        );
      case BulkProductEditOperation.images:
        result = await _service.applyImages(
          products: _matchedProducts,
          assignments: _imageAssignments,
          onlyWhenMissingImage: _onlyAssignWhenMissingImage,
        );
    }

    if (!mounted) return;

    setState(() {
      _isApplying = false;
      _applySummary =
          'Se procesaron ${result.total} productos. ${result.succeeded} correctos, ${result.failed} con error.';
      _applyErrors = result.errors;
    });

    if (result.failed == 0 && result.succeeded > 0) {
      Navigator.of(context).pop(true);
    }
  }

  Future<void> _pickImageFiles() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: true,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;

    final files = <BulkImageFile>[];
    for (final file in result.files) {
      if (file.bytes == null) continue;
      files.add(BulkImageFile(name: file.name, bytes: file.bytes!));
    }

    if (files.isEmpty) return;

    setState(() {
      _imagePool = [..._imagePool, ...files];
      _syncImageAssignments();
    });
  }

  Future<void> _handleDroppedFiles(List<XFile> droppedFiles) async {
    final files = <BulkImageFile>[];
    for (final file in droppedFiles) {
      final bytes = await file.readAsBytes();
      files.add(BulkImageFile(name: file.name, bytes: bytes));
    }

    if (!mounted || files.isEmpty) return;

    setState(() {
      _imagePool = [..._imagePool, ...files];
      _isDraggingImages = false;
      _syncImageAssignments();
    });
  }

  Future<void> _pickEffectiveDate() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _stockSharedConfig.effectiveAt,
      firstDate: DateTime(2024),
      lastDate: DateTime.now().add(const Duration(days: 30)),
    );
    if (selected == null) return;

    final current = _stockSharedConfig.effectiveAt;
    setState(() {
      _stockSharedConfig = _stockSharedConfig.copyWith(
        effectiveAt: DateTime(
          selected.year,
          selected.month,
          selected.day,
          current.hour,
          current.minute,
        ),
      );
    });
  }

  void _copySharedStockDetailsToRows({required bool includeQuantity}) {
    setState(() {
      for (final entry in _stockDrafts.entries) {
        final current = entry.value;
        _stockDrafts[entry.key] = current.copyWith(
          quantity: includeQuantity
              ? (_stockSharedConfig.defaultQuantity ?? current.quantity)
              : current.quantity,
          reasonType: _stockSharedConfig.reasonType,
          note: _sharedNoteController.text.trim(),
        );
      }
    });
  }

  void _applyClassificationPresetToRows() {
    setState(() {
      for (final product
          in _matchedProducts.where((product) => product.id != null)) {
        final productId = product.id!;
        final current = _classificationDrafts[productId] ??
            BulkClassificationRowDraft(
              productId: productId,
              categoryId: product.categoryId,
              categoryName: product.categoryName,
              brandId: product.brandId,
              brandName: product.brand,
              supplierId: product.supplierId,
              supplierName: product.supplierName,
            );

        var next = current;

        final categoryEmpty = (product.categoryId ?? '').trim().isEmpty;
        if (_classificationConfig.categoryId != null &&
            (!_classificationConfig.onlyFillMissing || categoryEmpty)) {
          next = next.copyWith(
            categoryId: _classificationConfig.categoryId,
            categoryName: _classificationConfig.categoryName,
          );
        }

        final brandEmpty = (product.brandId ?? '').trim().isEmpty &&
            (product.brand ?? '').trim().isEmpty;
        if (_classificationConfig.brandId != null &&
            (!_classificationConfig.onlyFillMissing || brandEmpty)) {
          next = next.copyWith(
            brandId: _classificationConfig.brandId,
            brandName: _classificationConfig.brandName,
          );
        }

        final supplierEmpty = (product.supplierId ?? '').trim().isEmpty;
        if (_classificationConfig.supplierId != null &&
            (!_classificationConfig.onlyFillMissing || supplierEmpty)) {
          next = next.copyWith(
            supplierId: _classificationConfig.supplierId,
            supplierName: _classificationConfig.supplierName,
          );
        }

        _classificationDrafts[productId] = next;
      }
    });
  }

  void _applyChannelsPresetToRows() {
    setState(() {
      for (final entry in _channelsDrafts.entries) {
        var next = entry.value;
        if (_channelsConfig.website != BulkToggleState.keep) {
          next = next.copyWith(
            website: _channelsConfig.website == BulkToggleState.enable,
          );
        }
        if (_channelsConfig.googleMerchant != BulkToggleState.keep) {
          final merchant =
              _channelsConfig.googleMerchant == BulkToggleState.enable;
          next = next.copyWith(
            googleMerchant: merchant,
            website: merchant ? true : next.website,
          );
        }
        if (_channelsConfig.active != BulkToggleState.keep) {
          next = next.copyWith(
            active: _channelsConfig.active == BulkToggleState.enable,
          );
        }
        if (!next.website) {
          next = next.copyWith(googleMerchant: false);
        }
        _channelsDrafts[entry.key] = next;
      }
    });
  }

  void _applyPricingPresetToRows() {
    setState(() {
      for (final product
          in _matchedProducts.where((product) => product.id != null)) {
        final productId = product.id!;
        final current = _pricingDrafts[productId] ??
            BulkPricingRowDraft(
              productId: productId,
              price: product.price,
              cost: product.cost,
            );

        final nextPrice = _previewPrice(
          current.price,
          _pricingConfig.price,
          _pricingConfig.rounding,
        );
        final nextCost = _previewPrice(
          current.cost,
          _pricingConfig.cost,
          _pricingConfig.rounding,
        );

        _pricingDrafts[productId] = current.copyWith(
          price: nextPrice,
          cost: nextCost,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dialogWidth =
        math.min(MediaQuery.of(context).size.width - 48, 1260.0);
    final dialogHeight =
        math.min(MediaQuery.of(context).size.height - 48, 860.0);

    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: dialogWidth,
        height: dialogHeight,
        child: Column(
          children: [
            _buildHeader(theme),
            _buildStepper(theme),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: KeyedSubtree(
                  key: ValueKey<int>(_stepIndex),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
                    child: _buildStepContent(theme),
                  ),
                ),
              ),
            ),
            _buildFooter(theme),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 18, 16, 16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: theme.colorScheme.outlineVariant.withOpacity(0.35),
          ),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 30,
            margin: const EdgeInsets.only(right: 12),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Edición masiva inteligente',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Define el alcance, elige la operación y revisa solo los campos que importan para ese lote.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: _isApplying ? null : () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close_rounded),
            tooltip: 'Cerrar',
          ),
        ],
      ),
    );
  }

  Widget _buildStepper(ThemeData theme) {
    const labels = ['Alcance', 'Operación', 'Revisión'];
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 14, 24, 14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        border: Border(
          bottom: BorderSide(
            color: theme.colorScheme.outlineVariant.withOpacity(0.25),
          ),
        ),
      ),
      child: Row(
        children: List.generate(labels.length, (index) {
          final isActive = index == _stepIndex;
          final isDone = index < _stepIndex;
          return Expanded(
            child: Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: isActive || isDone
                        ? theme.colorScheme.primary
                        : theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '${index + 1}',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: isActive || isDone
                          ? theme.colorScheme.onPrimary
                          : theme.colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    labels[index],
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: isActive
                          ? theme.colorScheme.onSurface
                          : theme.colorScheme.onSurfaceVariant,
                      fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          );
        }),
      ),
    );
  }

  Widget _buildStepContent(ThemeData theme) {
    switch (_stepIndex) {
      case 0:
        return _buildScopeStep(theme);
      case 1:
        return _buildOperationStep(theme);
      case 2:
        return _buildReviewStep(theme);
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildScopeStep(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '1. Define el alcance del lote',
          style: theme.textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        Text(
          'Parte desde la selección actual, desde la lista filtrada o desde todo el inventario, y luego refina con filtros específicos para este lote.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 18),
        _buildScopeSourceSelector(theme),
        const SizedBox(height: 18),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 6,
                child: Column(
                  children: [
                    _buildSmartFilterPanel(theme),
                    const SizedBox(height: 16),
                    _buildScopeSummary(theme),
                  ],
                ),
              ),
              const SizedBox(width: 18),
              Expanded(
                flex: 5,
                child: _buildScopePreview(theme),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildScopeSourceSelector(ThemeData theme) {
    final options = [
      BulkProductScopeSource.selected,
      BulkProductScopeSource.filtered,
      BulkProductScopeSource.all,
    ];

    return Row(
      children: options.map((source) {
        final isSelected = source == _scopeSource;
        final isDisabled = source == BulkProductScopeSource.selected &&
            widget.selectedProductIds.isEmpty;
        final count = switch (source) {
          BulkProductScopeSource.selected => widget.selectedProductIds.length,
          BulkProductScopeSource.filtered => widget.filteredProducts.length,
          BulkProductScopeSource.all => widget.allProducts
              .where((product) => !product.isSetComponent)
              .length,
        };

        return Expanded(
          child: Padding(
            padding: const EdgeInsets.only(right: 12),
            child: InkWell(
              onTap: isDisabled || widget.lockSource
                  ? null
                  : () {
                      setState(() => _scopeSource = source);
                      _refreshScopePreview();
                    },
              borderRadius: BorderRadius.circular(14),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isSelected
                      ? theme.colorScheme.primary.withOpacity(0.08)
                      : theme.colorScheme.surfaceContainerLowest,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isSelected
                        ? theme.colorScheme.primary
                        : theme.colorScheme.outlineVariant.withOpacity(0.5),
                  ),
                ),
                child: Opacity(
                  opacity: isDisabled ? 0.45 : 1,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        source.label,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '$count productos base',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      if (source == BulkProductScopeSource.filtered) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Respeta los filtros y búsqueda ya aplicados en la lista.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      }).toList(growable: false),
    );
  }

  Widget _buildSmartFilterPanel(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withOpacity(0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Filtros inteligentes del lote',
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(width: 8),
              Tooltip(
                message:
                    'Úsalos para acotar este lote sin tocar la configuración global de la lista. Ejemplo: keyword + sin categoría + sin marca + sin imagen.',
                child: Icon(
                  Icons.info_outline_rounded,
                  size: 16,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _keywordController,
                  onChanged: (value) {
                    _filters = _filters.copyWith(keyword: value);
                    _scheduleScopeRefresh();
                  },
                  decoration: const InputDecoration(
                    labelText: 'Keyword / texto libre',
                    hintText: 'Ej: maza, cadena 7v, shimano',
                    prefixIcon: Icon(Icons.search_rounded),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _specQueryController,
                  onChanged: (value) {
                    _filters = _filters.copyWith(specQuery: value);
                    _scheduleScopeRefresh();
                  },
                  decoration: InputDecoration(
                    labelText: 'Filtro por especificación',
                    hintText: 'Ej: 7v, aluminio, 29',
                    prefixIcon: _isRefreshingScope && _filters.hasSpecQuery
                        ? const Padding(
                            padding: EdgeInsets.all(12),
                            child: SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : const Icon(Icons.tune_rounded),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildDropdownField<String?>(
                  theme: theme,
                  label: 'Categoría',
                  value: _filters.categoryId,
                  items: [
                    const DropdownMenuItem<String?>(
                        value: null, child: Text('Todas')),
                    ...widget.categories.map(
                      (category) => DropdownMenuItem<String?>(
                        value: category.id,
                        child: Text(category.name),
                      ),
                    ),
                  ],
                  onChanged: (value) {
                    setState(() => _filters = _filters.copyWith(
                        categoryId: value, clearCategoryId: value == null));
                    _scheduleScopeRefresh();
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildDropdownField<String?>(
                  theme: theme,
                  label: 'Marca',
                  value: _filters.brandId,
                  items: [
                    const DropdownMenuItem<String?>(
                        value: null, child: Text('Todas')),
                    ...widget.brands.map(
                      (brand) => DropdownMenuItem<String?>(
                        value: brand.id,
                        child: Text(brand.name),
                      ),
                    ),
                  ],
                  onChanged: (value) {
                    setState(() => _filters = _filters.copyWith(
                        brandId: value, clearBrandId: value == null));
                    _scheduleScopeRefresh();
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildDropdownField<String?>(
                  theme: theme,
                  label: 'Proveedor',
                  value: _filters.supplierId,
                  items: [
                    const DropdownMenuItem<String?>(
                        value: null, child: Text('Todos')),
                    ...widget.suppliers.map(
                      (supplier) => DropdownMenuItem<String?>(
                        value: supplier.id,
                        child: Text(supplier.name),
                      ),
                    ),
                  ],
                  onChanged: (value) {
                    setState(() => _filters = _filters.copyWith(
                        supplierId: value, clearSupplierId: value == null));
                    _scheduleScopeRefresh();
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildDropdownField<ProductType?>(
                  theme: theme,
                  label: 'Tipo de producto',
                  value: _filters.productType,
                  items: [
                    const DropdownMenuItem<ProductType?>(
                        value: null, child: Text('Todos')),
                    ...ProductType.values.map(
                      (type) => DropdownMenuItem<ProductType?>(
                        value: type,
                        child: Text(type.displayName),
                      ),
                    ),
                  ],
                  onChanged: (value) {
                    setState(() => _filters = _filters.copyWith(
                        productType: value, clearProductType: value == null));
                    _scheduleScopeRefresh();
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildDropdownField<BulkFilterStockState>(
                  theme: theme,
                  label: 'Inventario',
                  value: _filters.stockState,
                  items: BulkFilterStockState.values
                      .map(
                        (state) => DropdownMenuItem<BulkFilterStockState>(
                          value: state,
                          child: Text(state.label),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: (value) {
                    if (value == null) return;
                    setState(
                        () => _filters = _filters.copyWith(stockState: value));
                    _scheduleScopeRefresh();
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildDropdownField<BulkToggleState>(
                  theme: theme,
                  label: 'Website',
                  value: _filters.websiteState,
                  items: BulkToggleState.values
                      .map(
                        (state) => DropdownMenuItem<BulkToggleState>(
                          value: state,
                          child: Text(state.label),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() =>
                        _filters = _filters.copyWith(websiteState: value));
                    _scheduleScopeRefresh();
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildDropdownField<BulkToggleState>(
                  theme: theme,
                  label: 'Google Merchant',
                  value: _filters.googleMerchantState,
                  items: BulkToggleState.values
                      .map(
                        (state) => DropdownMenuItem<BulkToggleState>(
                          value: state,
                          child: Text(state.label),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() => _filters =
                        _filters.copyWith(googleMerchantState: value));
                    _scheduleScopeRefresh();
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildDropdownField<BulkToggleState>(
                  theme: theme,
                  label: 'Estado activo',
                  value: _filters.activeState,
                  items: BulkToggleState.values
                      .map(
                        (state) => DropdownMenuItem<BulkToggleState>(
                          value: state,
                          child: Text(state.label),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: (value) {
                    if (value == null) return;
                    setState(
                        () => _filters = _filters.copyWith(activeState: value));
                    _scheduleScopeRefresh();
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _buildFilterToggle(
                      theme,
                      label: 'Sin categoría',
                      value: _filters.onlyMissingCategory,
                      onChanged: (value) {
                        setState(() => _filters =
                            _filters.copyWith(onlyMissingCategory: value));
                        _scheduleScopeRefresh();
                      },
                    ),
                    _buildFilterToggle(
                      theme,
                      label: 'Sin marca',
                      value: _filters.onlyMissingBrand,
                      onChanged: (value) {
                        setState(() => _filters =
                            _filters.copyWith(onlyMissingBrand: value));
                        _scheduleScopeRefresh();
                      },
                    ),
                    _buildFilterToggle(
                      theme,
                      label: 'Sin imagen',
                      value: _filters.onlyMissingImage,
                      onChanged: (value) {
                        setState(() => _filters =
                            _filters.copyWith(onlyMissingImage: value));
                        _scheduleScopeRefresh();
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildScopeSummary(ThemeData theme) {
    return Row(
      children: [
        _buildSummaryCard(theme, 'Coincidencias', '${_matchedProducts.length}',
            Icons.dataset_rounded),
        const SizedBox(width: 12),
        _buildSummaryCard(theme, 'Sin categoría', '$_missingCategoryCount',
            Icons.category_outlined),
        const SizedBox(width: 12),
        _buildSummaryCard(
            theme, 'Sin marca', '$_missingBrandCount', Icons.sell_outlined),
        const SizedBox(width: 12),
        _buildSummaryCard(theme, 'Sin imagen', '$_missingImageCount',
            Icons.image_not_supported_outlined),
      ],
    );
  }

  Widget _buildScopePreview(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withOpacity(0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Vista previa del lote',
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              if (_isRefreshingScope)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            _matchedProducts.isEmpty
                ? 'No hay productos que cumplan con este alcance.'
                : 'Primeros ${math.min(_matchedProducts.length, 10)} productos del lote.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 14),
          Expanded(
            child: _matchedProducts.isEmpty
                ? Center(
                    child: Text(
                      'Ajusta los filtros para encontrar productos.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  )
                : ListView.separated(
                    itemCount: math.min(_matchedProducts.length, 10),
                    separatorBuilder: (_, __) => Divider(
                      height: 1,
                      color: theme.colorScheme.outlineVariant.withOpacity(0.3),
                    ),
                    itemBuilder: (context, index) {
                      final product = _matchedProducts[index];
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Row(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: SizedBox(
                                width: 44,
                                height: 44,
                                child: product.imageUrl != null
                                    ? ImageService.buildProductImage(
                                        imageUrl: product.imageUrl,
                                        size: 44,
                                      )
                                    : Container(
                                        color: theme.colorScheme.surfaceVariant,
                                        child: Icon(
                                          Icons.inventory_2_outlined,
                                          size: 18,
                                          color: theme
                                              .colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    product.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodyMedium
                                        ?.copyWith(fontWeight: FontWeight.w600),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${product.sku} · ${product.categoryName ?? 'Sin categoría'}',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (product.tracksInventory)
                              Text(
                                '${product.inventoryQty}',
                                style: theme.textTheme.titleSmall
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildOperationStep(ThemeData theme) {
    final cards = <({
      BulkProductEditOperation operation,
      IconData icon,
      String title,
      String description,
    })>[
      (
        operation: BulkProductEditOperation.classification,
        icon: Icons.account_tree_outlined,
        title: 'Clasificación',
        description:
            'Asigna categoría, marca o proveedor con reglas para rellenar solo vacíos.',
      ),
      (
        operation: BulkProductEditOperation.channels,
        icon: Icons.public_outlined,
        title: 'Canales y estado',
        description:
            'Publicación web, Google Merchant y activación comercial en un solo lote.',
      ),
      (
        operation: BulkProductEditOperation.pricing,
        icon: Icons.attach_money_rounded,
        title: 'Precios y costos',
        description:
            'Fija valores, aplica porcentajes o corrige costos con redondeo.',
      ),
      (
        operation: BulkProductEditOperation.stock,
        icon: Icons.inventory_outlined,
        title: 'Ajuste de stock',
        description:
            'Corrige stock objetivo o por diferencia con justificación compartida y ajustes por fila.',
      ),
      (
        operation: BulkProductEditOperation.images,
        icon: Icons.photo_library_outlined,
        title: 'Imágenes',
        description:
            'Arrastra archivos, autoasigna por SKU/nombre y corrige manualmente donde haga falta.',
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '2. Elige qué vas a editar',
          style: theme.textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        Text(
          'El flujo y la tabla final cambian según la operación elegida. Así se evita mostrar campos irrelevantes.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 18),
        Wrap(
          spacing: 16,
          runSpacing: 16,
          children: cards.map((card) {
            final isSelected = _operation == card.operation;
            return SizedBox(
              width: 286,
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () {
                  setState(() => _operation = card.operation);
                  _syncStockDrafts();
                  _syncImageAssignments();
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? theme.colorScheme.primary.withOpacity(0.08)
                        : theme.colorScheme.surfaceContainerLowest,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isSelected
                          ? theme.colorScheme.primary
                          : theme.colorScheme.outlineVariant.withOpacity(0.5),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        card.icon,
                        size: 24,
                        color: isSelected
                            ? theme.colorScheme.primary
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(height: 14),
                      Text(
                        card.title,
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        card.description,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }).toList(growable: false),
        ),
      ],
    );
  }

  Widget _buildReviewStep(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '3. Revisa y aplica',
          style: theme.textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        Text(
          _reviewDescription,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 18),
        Expanded(
          child: Row(
            children: [
              Expanded(
                flex: 4,
                child: _buildOperationConfigPanel(theme),
              ),
              const SizedBox(width: 18),
              Expanded(
                flex: 7,
                child: _buildOperationReviewTable(theme),
              ),
            ],
          ),
        ),
        if (_applySummary != null) ...[
          const SizedBox(height: 12),
          _buildApplySummary(theme),
        ],
      ],
    );
  }

  String get _reviewDescription {
    return switch (_operation) {
      BulkProductEditOperation.classification =>
        'Verifica qué campos de clasificación se completarán y en cuáles productos se aplicará el cambio.',
      BulkProductEditOperation.channels =>
        'Confirma la visibilidad comercial y el estado operativo antes de publicar el lote.',
      BulkProductEditOperation.pricing =>
        'Comprueba el impacto económico antes de sobrescribir precios o costos.',
      BulkProductEditOperation.stock =>
        'Cada ajuste quedará auditado. Usa un motivo claro y revisa bien el resultado final por fila.',
      BulkProductEditOperation.images =>
        'Arrastra archivos, revisa el match automático y corrige manualmente los casos dudosos.',
      null => 'Selecciona primero la operación que quieres ejecutar.',
    };
  }

  Widget _buildOperationConfigPanel(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withOpacity(0.5),
        ),
      ),
      child: switch (_operation) {
        BulkProductEditOperation.classification =>
          _buildClassificationConfig(theme),
        BulkProductEditOperation.channels => _buildChannelsConfig(theme),
        BulkProductEditOperation.pricing => _buildPricingConfig(theme),
        BulkProductEditOperation.stock => _buildStockConfig(theme),
        BulkProductEditOperation.images => _buildImagesConfig(theme),
        null => Center(
            child: Text(
              'Elige una operación en el paso anterior.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
      },
    );
  }

  Widget _buildOperationReviewTable(ThemeData theme) {
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withOpacity(0.5),
        ),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
            child: Row(
              children: [
                Text(
                  'Productos del lote',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(width: 10),
                Text(
                  '${_enabledRowIds.length} activos de ${_matchedProducts.length}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Divider(
              height: 1,
              color: theme.colorScheme.outlineVariant.withOpacity(0.3)),
          Expanded(
            child: switch (_operation) {
              BulkProductEditOperation.classification =>
                _buildClassificationRows(theme),
              BulkProductEditOperation.channels => _buildChannelsRows(theme),
              BulkProductEditOperation.pricing => _buildPricingRows(theme),
              BulkProductEditOperation.stock => _buildStockRows(theme),
              BulkProductEditOperation.images => _buildImageRows(theme),
              null => const SizedBox.shrink(),
            },
          ),
        ],
      ),
    );
  }

  Widget _buildClassificationConfig(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Campos compartidos',
            style: theme.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 14),
        _buildDropdownField<String?>(
          theme: theme,
          label: 'Nueva categoría',
          value: _classificationConfig.categoryId,
          items: [
            const DropdownMenuItem<String?>(
                value: null, child: Text('No cambiar')),
            ...widget.categories.map(
              (category) => DropdownMenuItem<String?>(
                  value: category.id, child: Text(category.name)),
            ),
          ],
          onChanged: (value) {
            final category =
                widget.categories.where((item) => item.id == value).firstOrNull;
            setState(() {
              _classificationConfig = _classificationConfig.copyWith(
                categoryId: value,
                categoryName: category?.name,
                clearCategory: value == null,
              );
            });
          },
        ),
        const SizedBox(height: 12),
        _buildDropdownField<String?>(
          theme: theme,
          label: 'Nueva marca',
          value: _classificationConfig.brandId,
          items: [
            const DropdownMenuItem<String?>(
                value: null, child: Text('No cambiar')),
            ...widget.brands.map(
              (brand) => DropdownMenuItem<String?>(
                  value: brand.id, child: Text(brand.name)),
            ),
          ],
          onChanged: (value) {
            final brand =
                widget.brands.where((item) => item.id == value).firstOrNull;
            setState(() {
              _classificationConfig = _classificationConfig.copyWith(
                brandId: value,
                brandName: brand?.name,
                clearBrand: value == null,
              );
            });
          },
        ),
        const SizedBox(height: 12),
        _buildDropdownField<String?>(
          theme: theme,
          label: 'Nuevo proveedor',
          value: _classificationConfig.supplierId,
          items: [
            const DropdownMenuItem<String?>(
                value: null, child: Text('No cambiar')),
            ...widget.suppliers.map(
              (supplier) => DropdownMenuItem<String?>(
                  value: supplier.id, child: Text(supplier.name)),
            ),
          ],
          onChanged: (value) {
            final supplier =
                widget.suppliers.where((item) => item.id == value).firstOrNull;
            setState(() {
              _classificationConfig = _classificationConfig.copyWith(
                supplierId: value,
                supplierName: supplier?.name,
                clearSupplier: value == null,
              );
            });
          },
        ),
        const SizedBox(height: 12),
        SwitchListTile(
          value: _classificationConfig.onlyFillMissing,
          onChanged: (value) {
            setState(() {
              _classificationConfig =
                  _classificationConfig.copyWith(onlyFillMissing: value);
            });
          },
          contentPadding: EdgeInsets.zero,
          title: const Text('Solo rellenar vacíos'),
          subtitle:
              const Text('Evita sobrescribir campos que ya estaban definidos.'),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _applyClassificationPresetToRows,
          icon: const Icon(Icons.auto_fix_high_outlined, size: 18),
          label: const Text('Aplicar preset a filas'),
        ),
      ],
    );
  }

  Widget _buildChannelsConfig(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Canales del lote',
            style: theme.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 14),
        _buildDropdownField<BulkToggleState>(
          theme: theme,
          label: 'Website',
          value: _channelsConfig.website,
          items: BulkToggleState.values
              .map((state) => DropdownMenuItem<BulkToggleState>(
                  value: state, child: Text(state.label)))
              .toList(growable: false),
          onChanged: (value) {
            if (value == null) return;
            setState(() =>
                _channelsConfig = _channelsConfig.copyWith(website: value));
          },
        ),
        const SizedBox(height: 12),
        _buildDropdownField<BulkToggleState>(
          theme: theme,
          label: 'Google Merchant',
          value: _channelsConfig.googleMerchant,
          items: BulkToggleState.values
              .map((state) => DropdownMenuItem<BulkToggleState>(
                  value: state, child: Text(state.label)))
              .toList(growable: false),
          onChanged: (value) {
            if (value == null) return;
            setState(() => _channelsConfig =
                _channelsConfig.copyWith(googleMerchant: value));
          },
        ),
        const SizedBox(height: 12),
        _buildDropdownField<BulkToggleState>(
          theme: theme,
          label: 'Activo',
          value: _channelsConfig.active,
          items: BulkToggleState.values
              .map((state) => DropdownMenuItem<BulkToggleState>(
                  value: state, child: Text(state.label)))
              .toList(growable: false),
          onChanged: (value) {
            if (value == null) return;
            setState(() =>
                _channelsConfig = _channelsConfig.copyWith(active: value));
          },
        ),
        const SizedBox(height: 12),
        Text(
          'Si activas Google Merchant, el producto quedará publicado automáticamente. Si despublicas del website, Merchant se desactiva.',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _applyChannelsPresetToRows,
          icon: const Icon(Icons.auto_fix_high_outlined, size: 18),
          label: const Text('Aplicar preset a filas'),
        ),
      ],
    );
  }

  Widget _buildPricingConfig(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Reglas de precio',
            style: theme.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 14),
        _buildNumericChangeEditor(
          theme: theme,
          label: 'Precio de venta',
          current: _pricingConfig.price,
          controller: _priceValueController,
          onChanged: (value) => setState(
              () => _pricingConfig = _pricingConfig.copyWith(price: value)),
        ),
        const SizedBox(height: 12),
        _buildNumericChangeEditor(
          theme: theme,
          label: 'Costo',
          current: _pricingConfig.cost,
          controller: _costValueController,
          onChanged: (value) => setState(
              () => _pricingConfig = _pricingConfig.copyWith(cost: value)),
        ),
        const SizedBox(height: 12),
        _buildDropdownField<BulkPriceRounding>(
          theme: theme,
          label: 'Redondeo final',
          value: _pricingConfig.rounding,
          items: BulkPriceRounding.values
              .map((rounding) => DropdownMenuItem<BulkPriceRounding>(
                  value: rounding, child: Text(rounding.label)))
              .toList(growable: false),
          onChanged: (value) {
            if (value == null) return;
            setState(() =>
                _pricingConfig = _pricingConfig.copyWith(rounding: value));
          },
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _applyPricingPresetToRows,
          icon: const Icon(Icons.auto_fix_high_outlined, size: 18),
          label: const Text('Aplicar preset a filas'),
        ),
      ],
    );
  }

  Widget _buildStockConfig(ThemeData theme) {
    final availableReasons = _sharedReasonOptionsForCurrentMode();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Política del ajuste',
            style: theme.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 14),
        _buildDropdownField<BulkStockEditMode>(
          theme: theme,
          label: 'Modo',
          value: _stockSharedConfig.mode,
          items: BulkStockEditMode.values
              .map((mode) => DropdownMenuItem<BulkStockEditMode>(
                  value: mode, child: Text(mode.label)))
              .toList(growable: false),
          onChanged: (value) {
            if (value == null) return;
            setState(() {
              final nextSharedReasons = value == BulkStockEditMode.target
                  ? const ['count', 'manual']
                  : (_stockSharedConfig.direction == BulkStockDirection.inwards
                      ? _inboundReasonTypes
                      : _outboundReasonTypes);
              _stockSharedConfig = _stockSharedConfig.copyWith(
                mode: value,
                reasonType:
                    nextSharedReasons.contains(_stockSharedConfig.reasonType)
                        ? _stockSharedConfig.reasonType
                        : nextSharedReasons.first,
              );
              _syncStockDrafts();
            });
          },
        ),
        if (_stockSharedConfig.mode == BulkStockEditMode.delta) ...[
          const SizedBox(height: 12),
          _buildDropdownField<BulkStockDirection>(
            theme: theme,
            label: 'Dirección compartida',
            value: _stockSharedConfig.direction,
            items: BulkStockDirection.values
                .map((direction) => DropdownMenuItem<BulkStockDirection>(
                    value: direction, child: Text(direction.label)))
                .toList(growable: false),
            onChanged: (value) {
              if (value == null) return;
              setState(() {
                final nextReasons = value == BulkStockDirection.inwards
                    ? _inboundReasonTypes
                    : _outboundReasonTypes;
                _stockSharedConfig = _stockSharedConfig.copyWith(
                  direction: value,
                  reasonType:
                      nextReasons.contains(_stockSharedConfig.reasonType)
                          ? _stockSharedConfig.reasonType
                          : nextReasons.first,
                );
                _normalizeStockDraftReasons();
              });
            },
          ),
        ],
        const SizedBox(height: 12),
        _buildDropdownField<String>(
          theme: theme,
          label: 'Motivo compartido',
          value: _stockSharedConfig.reasonType,
          items: availableReasons
              .map((type) => DropdownMenuItem<String>(
                  value: type, child: Text(_reasonLabels[type] ?? type)))
              .toList(growable: false),
          onChanged: (value) {
            if (value == null) return;
            setState(() => _stockSharedConfig =
                _stockSharedConfig.copyWith(reasonType: value));
          },
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _sharedNoteController,
          onChanged: (value) => _stockSharedConfig =
              _stockSharedConfig.copyWith(sharedNote: value),
          minLines: 2,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Detalle / observación compartida',
            hintText:
                'Se copiará a todas las filas si lo deseas, y luego podrás retocar algunas.',
          ),
        ),
        const SizedBox(height: 12),
        Text(
          _stockSharedConfig.mode == BulkStockEditMode.target
              ? 'Cuando fijas stock objetivo, un mismo lote puede mezclar subidas y bajas. Por eso el motivo compartido se limita a razones neutrales; luego puedes afinar fila por fila.'
              : 'En modo por diferencia, las razones siguen la misma lógica de entrada y salida del ajuste individual.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: _sharedStockValueController,
                keyboardType: TextInputType.number,
                onChanged: (value) {
                  _stockSharedConfig = _stockSharedConfig.copyWith(
                    defaultQuantity: int.tryParse(value),
                    clearDefaultQuantity: value.trim().isEmpty,
                  );
                },
                decoration: InputDecoration(
                  labelText: _stockSharedConfig.mode == BulkStockEditMode.target
                      ? 'Stock objetivo base'
                      : 'Cantidad base',
                ),
              ),
            ),
            const SizedBox(width: 12),
            OutlinedButton.icon(
              onPressed: () =>
                  _copySharedStockDetailsToRows(includeQuantity: false),
              icon: const Icon(Icons.assignment_turned_in_outlined, size: 18),
              label: const Text('Copiar detalle'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () => _copySharedStockDetailsToRows(includeQuantity: true),
          icon: const Icon(Icons.copy_all_rounded, size: 18),
          label: Text(
            _stockSharedConfig.mode == BulkStockEditMode.target
                ? 'Copiar stock objetivo a todas'
                : 'Copiar cantidad a todas',
          ),
        ),
        const SizedBox(height: 12),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.event_outlined),
          title: const Text('Fecha efectiva'),
          subtitle: Text(
            '${_stockSharedConfig.effectiveAt.day.toString().padLeft(2, '0')}/${_stockSharedConfig.effectiveAt.month.toString().padLeft(2, '0')}/${_stockSharedConfig.effectiveAt.year}',
          ),
          trailing: TextButton(
            onPressed: _pickEffectiveDate,
            child: const Text('Cambiar'),
          ),
        ),
      ],
    );
  }

  Widget _buildImagesConfig(ThemeData theme) {
    final assignedCount = _imageAssignments.values
        .where((assignment) => assignment.file != null)
        .length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Cargar y mapear imágenes',
            style: theme.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        DropTarget(
          onDragDone: (details) => _handleDroppedFiles(details.files),
          onDragEntered: (_) => setState(() => _isDraggingImages = true),
          onDragExited: (_) => setState(() => _isDraggingImages = false),
          child: GestureDetector(
            onTap: _pickImageFiles,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: _isDraggingImages
                    ? theme.colorScheme.primary.withOpacity(0.08)
                    : theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: _isDraggingImages
                      ? theme.colorScheme.primary
                      : theme.colorScheme.outlineVariant.withOpacity(0.5),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.cloud_upload_outlined,
                    size: 26,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Arrastra imágenes o haz clic para elegir archivos',
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Se intentará asociar cada archivo por SKU, código, nombre o coincidencias fuertes del nombre del producto.',
                          style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _onlyAssignWhenMissingImage,
          onChanged: (value) =>
              setState(() => _onlyAssignWhenMissingImage = value),
          title: const Text('Solo cuando falta imagen'),
          subtitle: const Text(
              'Evita reemplazar imágenes ya cargadas salvo que lo desactives.'),
        ),
        const SizedBox(height: 12),
        Text(
          'Archivos cargados: ${_imagePool.length} · asignados automáticamente: $assignedCount',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }

  Widget _buildClassificationRows(ThemeData theme) {
    return _buildRowList(
      theme: theme,
      rowBuilder: (product) {
        final productId = product.id;
        if (productId == null) return const SizedBox.shrink();
        final draft = _classificationDrafts[productId] ??
            BulkClassificationRowDraft(
              productId: productId,
              categoryId: product.categoryId,
              categoryName: product.categoryName,
              brandId: product.brandId,
              brandName: product.brand,
              supplierId: product.supplierId,
              supplierName: product.supplierName,
            );
        return _buildDataRowShell(
          theme: theme,
          product: product,
          enabled: _enabledRowIds.contains(productId),
          onEnabledChanged: (value) => _toggleRow(productId, value),
          trailing: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: _buildDropdownField<String?>(
                      theme: theme,
                      label: 'Categoría',
                      value: draft.categoryId,
                      items: [
                        const DropdownMenuItem<String?>(
                            value: null, child: Text('Sin categoría')),
                        ...widget.categories.map(
                          (category) => DropdownMenuItem<String?>(
                            value: category.id,
                            child: Text(category.name),
                          ),
                        ),
                      ],
                      onChanged: !_enabledRowIds.contains(productId)
                          ? null
                          : (value) {
                              final category = widget.categories
                                  .where((item) => item.id == value)
                                  .firstOrNull;
                              setState(() {
                                _classificationDrafts[productId] =
                                    draft.copyWith(
                                  categoryId: value,
                                  categoryName: category?.name,
                                  clearCategory: value == null,
                                );
                              });
                            },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildDropdownField<String?>(
                      theme: theme,
                      label: 'Marca',
                      value: draft.brandId,
                      items: [
                        const DropdownMenuItem<String?>(
                            value: null, child: Text('Sin marca')),
                        ...widget.brands.map(
                          (brand) => DropdownMenuItem<String?>(
                            value: brand.id,
                            child: Text(brand.name),
                          ),
                        ),
                      ],
                      onChanged: !_enabledRowIds.contains(productId)
                          ? null
                          : (value) {
                              final brand = widget.brands
                                  .where((item) => item.id == value)
                                  .firstOrNull;
                              setState(() {
                                _classificationDrafts[productId] =
                                    draft.copyWith(
                                  brandId: value,
                                  brandName: brand?.name,
                                  clearBrand: value == null,
                                );
                              });
                            },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildDropdownField<String?>(
                      theme: theme,
                      label: 'Proveedor',
                      value: draft.supplierId,
                      items: [
                        const DropdownMenuItem<String?>(
                            value: null, child: Text('Sin proveedor')),
                        ...widget.suppliers.map(
                          (supplier) => DropdownMenuItem<String?>(
                            value: supplier.id,
                            child: Text(supplier.name),
                          ),
                        ),
                      ],
                      onChanged: !_enabledRowIds.contains(productId)
                          ? null
                          : (value) {
                              final supplier = widget.suppliers
                                  .where((item) => item.id == value)
                                  .firstOrNull;
                              setState(() {
                                _classificationDrafts[productId] =
                                    draft.copyWith(
                                  supplierId: value,
                                  supplierName: supplier?.name,
                                  clearSupplier: value == null,
                                );
                              });
                            },
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildChannelsRows(ThemeData theme) {
    return _buildRowList(
      theme: theme,
      rowBuilder: (product) {
        final productId = product.id;
        if (productId == null) return const SizedBox.shrink();
        final draft = _channelsDrafts[productId] ??
            BulkChannelsRowDraft(
              productId: productId,
              website: product.isPublished,
              googleMerchant: product.isGoogleMerchant,
              active: product.isActive,
            );
        return _buildDataRowShell(
          theme: theme,
          product: product,
          enabled: _enabledRowIds.contains(productId),
          onEnabledChanged: (value) => _toggleRow(productId, value),
          trailing: Row(
            children: [
              Expanded(
                child: SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Website'),
                  value: draft.website,
                  onChanged: !_enabledRowIds.contains(productId)
                      ? null
                      : (value) {
                          setState(() {
                            _channelsDrafts[productId] = draft.copyWith(
                              website: value,
                              googleMerchant:
                                  value ? draft.googleMerchant : false,
                            );
                          });
                        },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Merchant'),
                  value: draft.googleMerchant,
                  onChanged: !_enabledRowIds.contains(productId)
                      ? null
                      : (value) {
                          setState(() {
                            _channelsDrafts[productId] = draft.copyWith(
                              googleMerchant: value,
                              website: value ? true : draft.website,
                            );
                          });
                        },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Activo'),
                  value: draft.active,
                  onChanged: !_enabledRowIds.contains(productId)
                      ? null
                      : (value) {
                          setState(() {
                            _channelsDrafts[productId] =
                                draft.copyWith(active: value);
                          });
                        },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPricingRows(ThemeData theme) {
    return _buildRowList(
      theme: theme,
      rowBuilder: (product) {
        final productId = product.id;
        if (productId == null) return const SizedBox.shrink();
        final draft = _pricingDrafts[productId] ??
            BulkPricingRowDraft(
              productId: productId,
              price: product.price,
              cost: product.cost,
            );
        return _buildDataRowShell(
          theme: theme,
          product: product,
          enabled: _enabledRowIds.contains(productId),
          onEnabledChanged: (value) => _toggleRow(productId, value),
          trailing: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      key: ValueKey('price-$productId-${draft.price}'),
                      initialValue: draft.price.toStringAsFixed(0),
                      enabled: _enabledRowIds.contains(productId),
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      onChanged: (value) {
                        final parsed =
                            double.tryParse(value.replaceAll(',', '.'));
                        if (parsed == null) return;
                        setState(() {
                          _pricingDrafts[productId] =
                              draft.copyWith(price: parsed);
                        });
                      },
                      decoration:
                          const InputDecoration(labelText: 'Precio final'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      key: ValueKey('cost-$productId-${draft.cost}'),
                      initialValue: draft.cost.toStringAsFixed(0),
                      enabled: _enabledRowIds.contains(productId),
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      onChanged: (value) {
                        final parsed =
                            double.tryParse(value.replaceAll(',', '.'));
                        if (parsed == null) return;
                        setState(() {
                          _pricingDrafts[productId] =
                              draft.copyWith(cost: parsed);
                        });
                      },
                      decoration:
                          const InputDecoration(labelText: 'Costo final'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Base: ${ChileanUtils.formatCurrency(product.price)} / ${ChileanUtils.formatCurrency(product.cost)} · Margen esperado: ${_marginText(draft.price, draft.cost)}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStockRows(ThemeData theme) {
    return ListView.separated(
      controller: _rowsScrollController,
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
      itemCount: _matchedProducts.length,
      separatorBuilder: (_, __) => Divider(
          height: 1, color: theme.colorScheme.outlineVariant.withOpacity(0.25)),
      itemBuilder: (context, index) {
        final product = _matchedProducts[index];
        final productId = product.id;
        if (productId == null) return const SizedBox.shrink();
        final draft = _stockDrafts[productId] ??
            BulkStockRowDraft(
              productId: productId,
              quantity: product.inventoryQty,
              reasonType: _stockSharedConfig.reasonType,
            );
        final rowReasons = _reasonOptionsForDraft(product, draft);
        final normalizedDraft = rowReasons.contains(draft.reasonType)
            ? draft
            : draft.copyWith(reasonType: rowReasons.first);
        final currentStock = product.inventoryQty;
        final nextStock = _stockSharedConfig.mode == BulkStockEditMode.target
            ? normalizedDraft.quantity
            : (_stockSharedConfig.direction == BulkStockDirection.inwards
                ? currentStock + normalizedDraft.quantity
                : currentStock - normalizedDraft.quantity);

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Checkbox(
                value: _enabledRowIds.contains(productId),
                onChanged: (value) => _toggleRow(productId, value ?? false),
              ),
              Expanded(
                flex: 4,
                child: _buildProductIdentity(theme, product),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Actual', style: theme.textTheme.labelSmall),
                    const SizedBox(height: 4),
                    Text('$currentStock',
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: TextFormField(
                  initialValue: normalizedDraft.quantity.toString(),
                  enabled: _enabledRowIds.contains(productId),
                  keyboardType: TextInputType.number,
                  onChanged: (value) {
                    final parsed = int.tryParse(value) ?? 0;
                    final updatedDraft =
                        normalizedDraft.copyWith(quantity: parsed);
                    final allowedReasons =
                        _reasonOptionsForDraft(product, updatedDraft);
                    setState(() {
                      _stockDrafts[productId] =
                          allowedReasons.contains(updatedDraft.reasonType)
                              ? updatedDraft
                              : updatedDraft.copyWith(
                                  reasonType: allowedReasons.first);
                    });
                  },
                  decoration: InputDecoration(
                    labelText:
                        _stockSharedConfig.mode == BulkStockEditMode.target
                            ? 'Objetivo'
                            : 'Cantidad',
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Resultado', style: theme.textTheme.labelSmall),
                    const SizedBox(height: 4),
                    Text(
                      '$nextStock',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: nextStock < 0 ? theme.colorScheme.error : null,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 3,
                child: _buildDropdownField<String>(
                  theme: theme,
                  label: 'Motivo',
                  value: normalizedDraft.reasonType,
                  items: rowReasons
                      .map((type) => DropdownMenuItem<String>(
                          value: type,
                          child: Text(_reasonLabels[type] ?? type)))
                      .toList(growable: false),
                  onChanged: !_enabledRowIds.contains(productId)
                      ? null
                      : (value) {
                          if (value == null) return;
                          setState(() {
                            _stockDrafts[productId] =
                                normalizedDraft.copyWith(reasonType: value);
                          });
                        },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 4,
                child: TextFormField(
                  initialValue: normalizedDraft.note,
                  enabled: _enabledRowIds.contains(productId),
                  onChanged: (value) {
                    _stockDrafts[productId] =
                        normalizedDraft.copyWith(note: value);
                  },
                  decoration: const InputDecoration(labelText: 'Detalle'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildImageRows(ThemeData theme) {
    return ListView.separated(
      controller: _rowsScrollController,
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
      itemCount: _matchedProducts.length,
      separatorBuilder: (_, __) => Divider(
          height: 1, color: theme.colorScheme.outlineVariant.withOpacity(0.25)),
      itemBuilder: (context, index) {
        final product = _matchedProducts[index];
        final productId = product.id;
        if (productId == null) return const SizedBox.shrink();
        final assignment = _imageAssignments[productId] ??
            BulkImageAssignment(productId: productId);
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            children: [
              Checkbox(
                value: _enabledRowIds.contains(productId),
                onChanged: (value) => _toggleRow(productId, value ?? false),
              ),
              Expanded(flex: 4, child: _buildProductIdentity(theme, product)),
              const SizedBox(width: 12),
              SizedBox(
                width: 62,
                height: 62,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: product.imageUrl != null
                      ? ImageService.buildProductImage(
                          imageUrl: product.imageUrl,
                          size: 62,
                        )
                      : Container(
                          color: theme.colorScheme.surfaceVariant,
                          child: Icon(Icons.image_not_supported_outlined,
                              color: theme.colorScheme.onSurfaceVariant),
                        ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 5,
                child: _buildDropdownField<String?>(
                  theme: theme,
                  label: 'Archivo asignado',
                  value: assignment.file?.name,
                  items: [
                    const DropdownMenuItem<String?>(
                        value: null, child: Text('Sin asignar')),
                    ..._imagePool.map(
                      (file) => DropdownMenuItem<String?>(
                        value: file.name,
                        child: Text(file.name, overflow: TextOverflow.ellipsis),
                      ),
                    ),
                  ],
                  onChanged: !_enabledRowIds.contains(productId)
                      ? null
                      : (value) {
                          final file = _imagePool
                              .where((item) => item.name == value)
                              .firstOrNull;
                          setState(() {
                            _imageAssignments[productId] = assignment.copyWith(
                              file: file,
                              clearFile: value == null,
                            );
                          });
                        },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildApplySummary(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _applyErrors.isEmpty
            ? theme.colorScheme.primary.withOpacity(0.08)
            : theme.colorScheme.error.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _applyErrors.isEmpty
              ? theme.colorScheme.primary.withOpacity(0.25)
              : theme.colorScheme.error.withOpacity(0.25),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _applySummary ?? '',
            style: theme.textTheme.bodyMedium
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          if (_applyErrors.isNotEmpty) ...[
            const SizedBox(height: 10),
            ..._applyErrors.take(6).map(
                  (error) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      '• $error',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    ),
                  ),
                ),
          ],
        ],
      ),
    );
  }

  Widget _buildFooter(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 14, 24, 18),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          top: BorderSide(
            color: theme.colorScheme.outlineVariant.withOpacity(0.3),
          ),
        ),
      ),
      child: Row(
        children: [
          TextButton(
            onPressed: _isApplying
                ? null
                : () {
                    if (_stepIndex == 0) {
                      Navigator.of(context).pop();
                    } else {
                      setState(() => _stepIndex -= 1);
                    }
                  },
            child: Text(_stepIndex == 0 ? 'Cancelar' : 'Atrás'),
          ),
          const Spacer(),
          if (_stepIndex < 2)
            FilledButton(
              onPressed: _isApplying
                  ? null
                  : () {
                      if (_stepIndex == 0 && !_canMoveNextFromScope) return;
                      if (_stepIndex == 1 && _operation == null) return;
                      setState(() => _stepIndex += 1);
                    },
              child: Text(_stepIndex == 1 ? 'Revisar lote' : 'Siguiente'),
            )
          else
            FilledButton.icon(
              onPressed: _isApplying || !_canApply ? null : _handleApply,
              icon: _isApplying
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.playlist_add_check_circle_outlined),
              label: const Text('Aplicar cambios'),
            ),
        ],
      ),
    );
  }

  Widget _buildDropdownField<T>({
    required ThemeData theme,
    required String label,
    required T value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?>? onChanged,
  }) {
    return DropdownButtonFormField<T>(
      value: value,
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      items: items,
      onChanged: onChanged,
    );
  }

  Widget _buildFilterToggle(
    ThemeData theme, {
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return FilterChip(
      label: Text(label),
      selected: value,
      onSelected: onChanged,
      showCheckmark: false,
      selectedColor: theme.colorScheme.primary.withOpacity(0.12),
      side:
          BorderSide(color: theme.colorScheme.outlineVariant.withOpacity(0.5)),
    );
  }

  Widget _buildSummaryCard(
      ThemeData theme, String label, String value, IconData icon) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: theme.colorScheme.outlineVariant.withOpacity(0.5)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: theme.colorScheme.primary),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                const SizedBox(height: 2),
                Text(value,
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNumericChangeEditor({
    required ThemeData theme,
    required String label,
    required BulkNumericChange current,
    required TextEditingController controller,
    required ValueChanged<BulkNumericChange> onChanged,
  }) {
    controller.text = current.value?.toString() ?? '';
    return Row(
      children: [
        Expanded(
          flex: 3,
          child: _buildDropdownField<BulkNumericChangeMode>(
            theme: theme,
            label: label,
            value: current.mode,
            items: BulkNumericChangeMode.values
                .map((mode) => DropdownMenuItem<BulkNumericChangeMode>(
                    value: mode, child: Text(mode.label)))
                .toList(growable: false),
            onChanged: (value) {
              if (value == null) return;
              onChanged(current.copyWith(mode: value));
            },
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 2,
          child: TextField(
            controller: controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (value) => onChanged(current.copyWith(
                value: double.tryParse(value.replaceAll(',', '.')))),
            decoration: const InputDecoration(labelText: 'Valor'),
          ),
        ),
      ],
    );
  }

  Widget _buildRowList({
    required ThemeData theme,
    required Widget Function(Product product) rowBuilder,
  }) {
    return ListView.separated(
      controller: _rowsScrollController,
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
      itemCount: _matchedProducts.length,
      separatorBuilder: (_, __) => Divider(
          height: 1, color: theme.colorScheme.outlineVariant.withOpacity(0.25)),
      itemBuilder: (context, index) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: rowBuilder(_matchedProducts[index]),
      ),
    );
  }

  Widget _buildDataRowShell({
    required ThemeData theme,
    required Product product,
    required bool enabled,
    required ValueChanged<bool> onEnabledChanged,
    required Widget trailing,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Checkbox(
            value: enabled,
            onChanged: (value) => onEnabledChanged(value ?? false)),
        Expanded(flex: 4, child: _buildProductIdentity(theme, product)),
        const SizedBox(width: 12),
        Expanded(flex: 6, child: trailing),
      ],
    );
  }

  Widget _buildProductIdentity(ThemeData theme, Product product) {
    return Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            width: 48,
            height: 48,
            child: product.imageUrl != null
                ? ImageService.buildProductImage(
                    imageUrl: product.imageUrl,
                    size: 48,
                  )
                : Container(
                    color: theme.colorScheme.surfaceVariant,
                    child: Icon(Icons.inventory_2_outlined,
                        color: theme.colorScheme.onSurfaceVariant),
                  ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(product.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(product.sku,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              if (product.brand != null || product.categoryName != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    [product.brand, product.categoryName]
                        .whereType<String>()
                        .join(' · '),
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  void _toggleRow(String productId, bool enabled) {
    setState(() {
      if (enabled) {
        _enabledRowIds.add(productId);
      } else {
        _enabledRowIds.remove(productId);
      }

      final classificationDraft = _classificationDrafts[productId];
      if (classificationDraft != null) {
        _classificationDrafts[productId] =
            classificationDraft.copyWith(enabled: enabled);
      }

      final channelsDraft = _channelsDrafts[productId];
      if (channelsDraft != null) {
        _channelsDrafts[productId] = channelsDraft.copyWith(enabled: enabled);
      }

      final pricingDraft = _pricingDrafts[productId];
      if (pricingDraft != null) {
        _pricingDrafts[productId] = pricingDraft.copyWith(enabled: enabled);
      }

      final stockDraft = _stockDrafts[productId];
      if (stockDraft != null) {
        _stockDrafts[productId] = stockDraft.copyWith(enabled: enabled);
      }

      final imageAssignment = _imageAssignments[productId];
      if (imageAssignment != null) {
        _imageAssignments[productId] =
            imageAssignment.copyWith(enabled: enabled);
      }
    });
  }

  double _previewPrice(
    double current,
    BulkNumericChange change,
    BulkPriceRounding rounding,
  ) {
    var next = change.apply(current);
    switch (rounding) {
      case BulkPriceRounding.none:
        break;
      case BulkPriceRounding.nearest10:
        next = (next / 10).round() * 10;
      case BulkPriceRounding.nearest100:
        next = (next / 100).round() * 100;
    }
    return next.clamp(0, double.infinity);
  }

  String _marginText(double price, double cost) {
    if (cost <= 0) return 'N/D';
    final pct = ((price - cost) / cost) * 100;
    return '${pct.toStringAsFixed(1)} %';
  }
}
