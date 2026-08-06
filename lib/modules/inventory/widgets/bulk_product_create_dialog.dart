import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';

import '../../../shared/themes/vinabike_theme_roles.dart';
import 'package:provider/provider.dart';

import '../../ai_assistant/services/ai_service.dart';
import '../../../shared/models/product.dart' show PurchaseTreatment;
import '../../../shared/models/supplier.dart';
import '../../../shared/services/database_service.dart';
import '../../../shared/services/image_service.dart';
import '../../../shared/services/tenant_service.dart';
import '../../purchases/services/purchase_service.dart';
import '../models/brand_models.dart';
import '../models/category_models.dart';
import '../models/inventory_models.dart';
import '../models/product_duplicate_candidate.dart';
import '../services/brand_service.dart';
import '../services/category_service.dart';
import '../services/inventory_service.dart' as inv_service;
import '../services/product_duplicate_matcher_service.dart';
import '../services/product_image_fingerprint_service.dart';
import 'product_duplicate_review_dialog.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Entry model for one row in the bulk-create table
// ─────────────────────────────────────────────────────────────────────────────

class _ProductDraft {
  bool isSelected = true;
  bool isUploadingImage = false;
  bool isHoveringImage = false;
  bool isWorkshopConsumable = false;
  bool isGeneratingSku = false;
  bool isCheckingDuplicates = false;
  bool hasCheckedDuplicates = false;
  bool hasReservedAliExpressSku = false;
  String? aliExpressSkuReservationOperationKey;
  final TextEditingController skuController;
  final TextEditingController nameController;
  final TextEditingController descriptionController;
  final TextEditingController costController;
  final TextEditingController priceController;
  final TextEditingController stockController;
  final TextEditingController minStockController;
  Category? selectedCategory;
  ProductBrand? selectedBrand;
  Supplier? selectedSupplier;
  String? imageUrl;
  String? imageUrlOptimized;
  Uint8List? imageBytes;
  String? imageFileName;
  String? duplicateCheckError;
  List<ProductDuplicateCandidate> duplicateCandidates = const [];

  _ProductDraft({
    String? initialSku,
    String? initialName,
  })  : skuController = TextEditingController(text: initialSku ?? ''),
        nameController = TextEditingController(text: initialName ?? ''),
        descriptionController = TextEditingController(),
        costController = TextEditingController(),
        priceController = TextEditingController(),
        stockController = TextEditingController(),
        minStockController = TextEditingController(text: '1');

  bool get isValid =>
      nameController.text.trim().isNotEmpty &&
      priceController.text.trim().isNotEmpty &&
      (double.tryParse(priceController.text.replaceAll(',', '.')) ?? 0) > 0;

  void dispose() {
    skuController.dispose();
    nameController.dispose();
    descriptionController.dispose();
    costController.dispose();
    priceController.dispose();
    stockController.dispose();
    minStockController.dispose();
  }

  String get sku => skuController.text.trim();
  double get cost =>
      double.tryParse(costController.text.replaceAll(',', '.')) ?? 0;
  double? get price =>
      double.tryParse(priceController.text.replaceAll(',', '.'));
  int get initialStock =>
      int.tryParse(stockController.text.replaceAll(',', '.')) ?? 0;
  int get minStock =>
      int.tryParse(minStockController.text.replaceAll(',', '.')) ?? 1;

  bool get hasPotentialDuplicates => duplicateCandidates.isNotEmpty;
  double? get topDuplicateScore => duplicateCandidates.isEmpty
      ? null
      : duplicateCandidates.first.overallScore;
}

// ─────────────────────────────────────────────────────────────────────────────
// Dialog
// ─────────────────────────────────────────────────────────────────────────────

class BulkProductCreateDialog extends StatefulWidget {
  const BulkProductCreateDialog({super.key});

  @override
  State<BulkProductCreateDialog> createState() =>
      _BulkProductCreateDialogState();
}

class _BulkProductCreateDialogState extends State<BulkProductCreateDialog> {
  static final RegExp _aliExpressSkuPattern =
      RegExp(r'^AE(\d+)$', caseSensitive: false);

  final List<_ProductDraft> _rows = [];
  List<Category> _categories = [];
  List<ProductBrand> _brands = [];
  List<Supplier> _suppliers = [];
  bool _isLoadingRef = true;
  bool _isCreating = false;
  bool _hasAttemptedCreate = false;
  String? _resultMessage;
  bool _resultIsError = false;

  // ── Global column defaults ────────────────────────────────────────────────
  Category? _defaultCategory;
  ProductBrand? _defaultBrand;
  Supplier? _defaultSupplier;
  bool _defaultWorkshop = false;
  bool _isCheckingDuplicates = false;

  late final inv_service.InventoryService _inventoryService;
  final AIAssistantService _aiAssistantService = AIAssistantService();

  final _horizontalScrollController = ScrollController();

  bool get _isGeminiConfigured => _aiAssistantService.isGeminiConfigured;

  int get _rowsWithDuplicateWarnings =>
      _rows.where((row) => row.isSelected && row.hasPotentialDuplicates).length;

  @override
  void initState() {
    super.initState();
    final dbService = DatabaseService();
    final tenantService = TenantService();
    _inventoryService = inv_service.InventoryService(dbService, tenantService);
    _loadRefData();
    // Start with 3 blank rows
    _addRows(3);
  }

  @override
  void dispose() {
    for (final r in _rows) {
      r.dispose();
    }
    _horizontalScrollController.dispose();
    super.dispose();
  }

  Future<void> _loadRefData() async {
    try {
      final dbService = DatabaseService();
      final tenantService = TenantService();
      final categoryService = CategoryService(dbService, tenantService);
      final brandService = BrandService(dbService);
      final purchaseService = context.read<PurchaseService>();

      final results = await Future.wait([
        categoryService.getCategories(activeOnly: true),
        brandService.getBrands(activeOnly: true),
        purchaseService.getSuppliers(activeOnly: true),
      ]);

      if (mounted) {
        setState(() {
          _categories = results[0] as List<Category>;
          _brands = results[1] as List<ProductBrand>;
          _suppliers = results[2] as List<Supplier>;
          _isLoadingRef = false;
        });
      }
    } catch (e) {
      debugPrint('BulkCreate: error loading ref data: $e');
      if (mounted) setState(() => _isLoadingRef = false);
    }
  }

  void _addRows(int count) {
    setState(() {
      for (int i = 0; i < count; i++) {
        final draft = _ProductDraft();
        _applyDefaultsToRow(draft);
        _rows.add(draft);
      }
    });
    // If default supplier is AliExpress, auto-generate SKUs for new blank rows
    if (_defaultSupplier != null &&
        _inventoryService.isAliExpressSupplierName(_defaultSupplier!.name)) {
      final newRows = _rows.reversed.take(count).toList().reversed.toList();
      for (final draft in newRows) {
        _generateSkuForRow(draft);
      }
    }
  }

  void _applyDefaultsToRow(_ProductDraft draft) {
    draft.selectedCategory ??= _defaultCategory;
    draft.selectedBrand ??= _defaultBrand;
    draft.selectedSupplier ??= _defaultSupplier;
    draft.isWorkshopConsumable = _defaultWorkshop;
  }

  Future<void> _applyDefaultsToAll() async {
    // Apply values to every row
    for (final draft in _rows) {
      _invalidateDuplicateCheck(draft);
      if (_defaultCategory != null) draft.selectedCategory = _defaultCategory;
      if (_defaultBrand != null) draft.selectedBrand = _defaultBrand;
      if (_defaultSupplier != null) draft.selectedSupplier = _defaultSupplier;
      draft.hasReservedAliExpressSku = false;
      draft.aliExpressSkuReservationOperationKey = null;
      draft.isWorkshopConsumable = _defaultWorkshop;
    }
    setState(() {});

    // Auto-generate AliExpress SKUs for rows that have empty SKU
    if (_defaultSupplier != null &&
        _inventoryService.isAliExpressSupplierName(_defaultSupplier!.name)) {
      final rowsNeedingSku =
          _rows.where((r) => r.skuController.text.trim().isEmpty).toList();
      for (final draft in rowsNeedingSku) {
        await _generateSkuForRow(draft);
      }
    }
  }

  Future<void> _onGlobalSupplierChanged(Supplier? supplier) async {
    setState(() => _defaultSupplier = supplier);
    await _applyDefaultsToAll();
  }

  void _removeRow(int index) {
    final draft = _rows[index];
    draft.dispose();
    setState(() => _rows.removeAt(index));
  }

  Future<void> _uploadImage(
      _ProductDraft draft, Uint8List bytes, String fileName) async {
    _invalidateDuplicateCheck(draft);
    setState(() => draft.isUploadingImage = true);
    try {
      final result = await ImageService.uploadProductImageWithOptimization(
          bytes: bytes, fileName: fileName);
      setState(() {
        draft.imageUrl = result.optimizedUrl ?? result.originalUrl;
        draft.imageUrlOptimized = result.optimizedUrl;
        draft.imageBytes = bytes;
        draft.imageFileName = fileName;
      });
    } catch (e) {
      debugPrint('Error uploading image: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al subir imagen: $e')),
        );
      }
    } finally {
      setState(() => draft.isUploadingImage = false);
    }
  }

  // ─── AliExpress SKU auto-generation ──────────────────────────────────────

  Future<void> _generateSkuForRow(_ProductDraft draft) async {
    if (draft.skuController.text.trim().isNotEmpty) return;
    final supplier = draft.selectedSupplier;
    if (supplier == null) return;
    if (!_inventoryService.isAliExpressSupplierName(supplier.name)) return;

    if (mounted) setState(() => draft.isGeneratingSku = true);
    try {
      final nextSkuFromDatabase = await _inventoryService.getNextAliExpressSku(
        supplierId: supplier.id,
        supplierName: supplier.name,
      );

      var maxSequence =
          (_sequenceForAliExpressSku(nextSkuFromDatabase) ?? 1) - 1;

      for (final row in _rows) {
        if (identical(row, draft)) continue;

        final sequence =
            _sequenceForAliExpressSku(row.skuController.text.trim());
        if (sequence == null) continue;

        if (sequence > maxSequence) {
          maxSequence = sequence;
        }
      }

      final nextSku = 'AE${(maxSequence + 1).toString().padLeft(4, '0')}';

      if (mounted) setState(() => draft.skuController.text = nextSku);
    } catch (e) {
      debugPrint('BulkCreate: AliExpress SKU generation failed: $e');
    } finally {
      if (mounted) setState(() => draft.isGeneratingSku = false);
    }
  }

  int? _sequenceForAliExpressSku(String sku) {
    final match = _aliExpressSkuPattern.firstMatch(sku.trim());
    if (match == null) return null;

    final sequence = int.tryParse(match.group(1) ?? '');
    if (sequence == null) return null;

    return sequence;
  }

  Future<void> _onSupplierSelected(
      _ProductDraft draft, Supplier? supplier) async {
    _invalidateDuplicateCheck(draft);
    setState(() {
      draft.selectedSupplier = supplier;
      draft.hasReservedAliExpressSku = false;
      draft.aliExpressSkuReservationOperationKey = null;
    });
    await _generateSkuForRow(draft);
  }

  void _invalidateDuplicateCheck(_ProductDraft draft) {
    draft.hasCheckedDuplicates = false;
    draft.isCheckingDuplicates = false;
    draft.duplicateCheckError = null;
    draft.duplicateCandidates = const [];
  }

  bool _hasSimilarityProbe(_ProductDraft draft) {
    return draft.nameController.text.trim().isNotEmpty ||
        draft.descriptionController.text.trim().isNotEmpty ||
        draft.imageBytes != null;
  }

  Future<void> _checkPotentialDuplicates() async {
    final rowsToCheck = _rows
        .where((draft) => draft.isSelected && _hasSimilarityProbe(draft))
        .toList();
    final usingLocalOnlyFallback = !_isGeminiConfigured;

    if (rowsToCheck.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text('Agrega al menos nombre o imagen para revisar parecidos.'),
        ),
      );
      return;
    }

    setState(() {
      _isCheckingDuplicates = true;
      _resultMessage = null;
      _resultIsError = false;
    });

    try {
      final products = await _inventoryService.getProducts();

      for (final draft in rowsToCheck) {
        await _runDuplicateCheckForDraft(draft, products);
      }

      final flaggedRows = rowsToCheck
          .where((draft) => draft.hasPotentialDuplicates)
          .toList(growable: false);
      final errorRows = rowsToCheck
          .where((draft) => draft.duplicateCheckError != null)
          .length;

      if (!mounted) return;

      setState(() {
        if (flaggedRows.isEmpty) {
          _resultMessage =
              'No se encontraron parecidos fuertes en ${rowsToCheck.length} fila(s).';
        } else {
          _resultMessage =
              'Revisa ${flaggedRows.length} fila(s) con posibles duplicados.';
        }
        if (usingLocalOnlyFallback) {
          _resultMessage =
              '${_resultMessage!} Vision IA no configurada: se uso coincidencia local conservadora.';
        }
        if (errorRows > 0) {
          _resultMessage =
              '${_resultMessage!} $errorRows fila(s) usaron sólo coincidencia local.';
        }
        _resultIsError = false;
      });

      if (flaggedRows.isNotEmpty) {
        await _showDuplicateReviewDialog(flaggedRows);
      }
    } finally {
      if (mounted) {
        setState(() => _isCheckingDuplicates = false);
      }
    }
  }

  Future<void> _runDuplicateCheckForDraft(
    _ProductDraft draft,
    List<Product> products,
  ) async {
    setState(() {
      draft.isCheckingDuplicates = true;
      draft.hasCheckedDuplicates = false;
      draft.duplicateCheckError = null;
      draft.duplicateCandidates = const [];
    });

    try {
      final candidates =
          await _findDuplicateCandidatesForDraft(draft, products);

      if (!mounted) return;

      setState(() {
        draft.duplicateCandidates = candidates;
        draft.hasCheckedDuplicates = true;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        draft.duplicateCheckError = e.toString();
        draft.hasCheckedDuplicates = true;
      });
    } finally {
      if (mounted) {
        setState(() => draft.isCheckingDuplicates = false);
      }
    }
  }

  Future<List<ProductDuplicateCandidate>> _findDuplicateCandidatesForDraft(
    _ProductDraft draft,
    List<Product> products,
  ) async {
    final matcher = ProductDuplicateMatcherService(
      inventoryService: _inventoryService,
      aiAssistantService: _aiAssistantService,
    );
    return matcher.findCandidates(
      probe: ProductDuplicateProbe(
        name: draft.nameController.text,
        description: draft.descriptionController.text,
        sku: draft.sku,
        categoryName: draft.selectedCategory?.name,
        brandName: draft.selectedBrand?.name,
        supplierId: draft.selectedSupplier?.id,
        supplierName: draft.selectedSupplier?.name,
        imageUrl: draft.imageUrl,
        imageBytes: draft.imageBytes,
        imageFileName: draft.imageFileName,
        price: draft.price,
        cost: draft.cost,
      ),
      products: products,
    );
  }

  Future<void> _showDuplicateReviewDialog(List<_ProductDraft> rows) async {
    if (!mounted) return;

    final flaggedRows =
        rows.where((draft) => draft.hasPotentialDuplicates).toList();
    if (flaggedRows.isEmpty) return;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => ProductDuplicateReviewDialog(
        rows: flaggedRows
            .map(
              (draft) => ProductDuplicateReviewRow(
                title: draft.nameController.text.trim().isEmpty
                    ? 'Producto sin nombre'
                    : draft.nameController.text.trim(),
                imageUrl: draft.imageUrl,
                badges: [
                  if (draft.sku.isNotEmpty) draft.sku,
                  if ((draft.selectedCategory?.name ?? '').isNotEmpty)
                    draft.selectedCategory!.name,
                  if ((draft.selectedBrand?.name ?? '').isNotEmpty)
                    draft.selectedBrand!.name,
                ],
                candidates: draft.duplicateCandidates,
              ),
            )
            .toList(growable: false),
        subtitle: _isGeminiConfigured
            ? '${flaggedRows.length} fila(s) con señales fuertes. No bloquea creación: sólo te da los mejores candidatos.'
            : '${flaggedRows.length} fila(s) con señales fuertes. Vision IA no configurada: se muestran solo coincidencias locales muy fuertes.',
        footerText:
            'Las filas marcadas siguen siendo editables. Si una te convence como duplicado, simplemente desmárcala en la tabla.',
      ),
    );
  }

  Widget? _buildDuplicateStatusIcon(_ProductDraft draft) {
    if (draft.isCheckingDuplicates) {
      return const SizedBox(
        width: 14,
        height: 14,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }

    if (draft.hasPotentialDuplicates) {
      return Tooltip(
        message:
            '${draft.duplicateCandidates.length} parecido(s) detectado(s). Clic para revisar.',
        child: InkWell(
          onTap: () => _showDuplicateReviewDialog([draft]),
          borderRadius: BorderRadius.circular(999),
          child: Icon(
            Icons.warning_amber_rounded,
            size: 16,
            color: VinabikeThemeRoles.of(context).warning.accent,
          ),
        ),
      );
    }

    if (draft.hasCheckedDuplicates && draft.duplicateCheckError == null) {
      return Tooltip(
        message: 'Sin señales fuertes de duplicado en esta fila.',
        child: Icon(
          Icons.verified_outlined,
          size: 16,
          color: VinabikeThemeRoles.of(context).success.accent,
        ),
      );
    }

    return null;
  }

  Future<void> _createProducts() async {
    final selectedRows = _rows.where((r) => r.isSelected && r.isValid).toList();
    if (selectedRows.isEmpty) return;

    setState(() {
      _isCreating = true;
      _hasAttemptedCreate = true;
      _resultMessage = null;
    });

    try {
      final inventoryService = _inventoryService;
      final tenantService = TenantService();
      int created = 0;
      final List<String> failed = [];
      final createdDrafts = <_ProductDraft>[];

      for (final draft in selectedRows) {
        final supplier = draft.selectedSupplier;
        if (supplier != null &&
            inventoryService.isAliExpressSupplierName(supplier.name) &&
            !draft.hasReservedAliExpressSku) {
          draft.aliExpressSkuReservationOperationKey ??=
              'bulk-product-${DateTime.now().microsecondsSinceEpoch}-'
              '${identityHashCode(draft)}';
          final reserved = await inventoryService.reserveAliExpressSkus(
            count: 1,
            operationKey: draft.aliExpressSkuReservationOperationKey!,
            supplierId: supplier.id,
            supplierName: supplier.name,
          );
          draft.skuController.text = reserved.single;
          draft.hasReservedAliExpressSku = true;
        }
        final product = Product(
          tenantId: tenantService.currentTenantId ?? '',
          name: draft.nameController.text.trim(),
          sku: draft.sku.isEmpty ? '' : draft.sku,
          description: draft.descriptionController.text.trim().isEmpty
              ? null
              : draft.descriptionController.text.trim(),
          price: draft.price!,
          cost: draft.cost > 0 ? draft.cost : 0,
          inventoryQty: draft.initialStock,
          minStockLevel: draft.minStock,
          maxStockLevel: 100,
          categoryId: draft.selectedCategory?.id,
          categoryName: draft.selectedCategory?.name,
          brandId: draft.selectedBrand?.id,
          brand: draft.selectedBrand?.name,
          supplierId: draft.selectedSupplier?.id,
          supplierName: draft.selectedSupplier?.name,
          isActive: true,
          isPublished: true,
          purchaseTreatment: draft.isWorkshopConsumable
              ? PurchaseTreatment.workshopConsumable
              : PurchaseTreatment.inventory,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          imageUrl: draft.imageUrl,
          imageUrlOptimized: draft.imageUrlOptimized,
          imageFingerprint: draft.imageBytes == null
              ? null
              : ProductImageFingerprintService.computeStorageJson(
                  draft.imageBytes!,
                ),
        );

        try {
          await inventoryService.createProduct(product);
          created++;
          createdDrafts.add(draft);
        } catch (e) {
          debugPrint('❌ Failed to create product "${product.name}": $e');
          failed.add(draft.nameController.text.trim());
        }
      }

      if (createdDrafts.isNotEmpty) {
        setState(() {
          _rows.removeWhere((draft) => createdDrafts.contains(draft));
        });
        for (final draft in createdDrafts) {
          draft.dispose();
        }
      }

      // Refresh shared cache
      if (created > 0) {
        inventoryService.invalidateProductsCache();
      }

      if (mounted) {
        String msg = '✅ $created producto(s) creado(s)';
        if (failed.isNotEmpty) {
          msg += ' — ${failed.length} error(es): ${failed.join(', ')}';
        }
        setState(() {
          _resultMessage = msg;
          _resultIsError = failed.isNotEmpty && created == 0;
        });

        if (failed.isEmpty) {
          // All succeeded — close after brief delay
          await Future.delayed(const Duration(milliseconds: 800));
          if (mounted) Navigator.of(context).pop(true);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _resultMessage = 'Error: $e';
          _resultIsError = true;
        });
      }
    } finally {
      if (mounted) setState(() => _isCreating = false);
    }
  }

  // ─── Column layout constants ─────────────────────────────────────────────

  static const double _wChk = 40;
  static const double _wImg = 58;
  static const double _wSku = 120;
  static const double _wName = 230;
  static const double _wDesc = 180;
  static const double _wCost = 100;
  static const double _wPrice = 100;
  static const double _wStock = 80;
  static const double _wCat = 160;
  static const double _wBrand = 150;
  static const double _wSupplier = 150;
  static const double _wTaller = 68;
  static const double _wDel = 36;
  static const double _gap = 8;
  static const double _hPad = 12;

  double get _minTableWidth =>
      _hPad * 2 +
      _wChk +
      _wImg +
      _wSku +
      _wName +
      _wDesc +
      _wCost +
      _wPrice +
      _wStock +
      _wCat +
      _wBrand +
      _wSupplier +
      _wTaller +
      _wDel +
      _gap * 12;

  // ─── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final screenSize = MediaQuery.of(context).size;

    return Dialog(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SizedBox(
        width: math.min(screenSize.width * 0.97, 1600),
        height: math.min(screenSize.height * 0.90, 900),
        child: Column(
          children: [
            // ── Title bar ────────────────────────────────────────────────
            _buildTitleBar(theme),

            // ── Global defaults toolbar ───────────────────────────────────
            if (!_isLoadingRef) _buildDefaultsBar(theme),

            // ── Loading overlay or table ──────────────────────────────────
            Expanded(
              child: _isLoadingRef
                  ? const Center(child: CircularProgressIndicator())
                  : _buildBody(theme),
            ),

            // ── Footer ────────────────────────────────────────────────────
            _buildFooter(theme),
          ],
        ),
      ),
    );
  }

  Widget _buildTitleBar(ThemeData theme) {
    final validCount = _rows.where((r) => r.isSelected && r.isValid).length;
    final duplicateWarningCount = _rowsWithDuplicateWarnings;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          bottom: BorderSide(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3)),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.inventory_2_outlined,
              size: 20, color: theme.colorScheme.primary),
          const SizedBox(width: 10),
          Text('Creación masiva',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest
                  .withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '${_rows.length} filas · $validCount listos',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const Spacer(),
          // Add rows buttons
          TextButton.icon(
            onPressed: () => _addRows(1),
            icon: const Icon(Icons.add_rounded, size: 16),
            label: const Text('+1'),
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              textStyle:
                  const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 2),
          TextButton.icon(
            onPressed: () => _addRows(5),
            icon: const Icon(Icons.add_rounded, size: 16),
            label: const Text('+5'),
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              textStyle:
                  const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: _isCheckingDuplicates ? null : _checkPotentialDuplicates,
            icon: _isCheckingDuplicates
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.find_in_page_outlined, size: 16),
            label: Text(
              _isCheckingDuplicates ? 'Buscando...' : 'Parecidos',
            ),
            style: OutlinedButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              textStyle:
                  const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
          if (duplicateWarningCount > 0) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: VinabikeThemeRoles.of(context).warning.container,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '$duplicateWarningCount con parecidos',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: VinabikeThemeRoles.of(context).warning.accent,
                ),
              ),
            ),
          ],
          const SizedBox(width: 4),
          Container(
            width: 1,
            height: 20,
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
          ),
          const SizedBox(width: 4),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            onPressed: () => Navigator.of(context).pop(false),
            visualDensity: VisualDensity.compact,
            style: IconButton.styleFrom(
              padding: const EdgeInsets.all(6),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDefaultsBar(ThemeData theme) {
    final isAliExpress =
        _inventoryService.isAliExpressSupplierName(_defaultSupplier?.name);
    final hasDefaults = _defaultCategory != null ||
        _defaultBrand != null ||
        _defaultSupplier != null;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow.withValues(alpha: 0.6),
        border: Border(
          bottom: BorderSide(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3)),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.auto_fix_high_rounded,
              size: 14,
              color: theme.colorScheme.primary.withValues(alpha: 0.7)),
          const SizedBox(width: 6),
          Text(
            'Defaults:',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(width: 10),

          // ── Default Category ─────────────────────────────────────────
          _compactDropdown<Category>(
            theme: theme,
            width: 150,
            hint: 'Categoría',
            value: _defaultCategory,
            entries: _categories
                .map(
                    (c) => DropdownMenuEntry<Category>(value: c, label: c.name))
                .toList(),
            onSelected: (v) {
              setState(() => _defaultCategory = v);
              if (v != null) {
                for (final r in _rows) {
                  _invalidateDuplicateCheck(r);
                  r.selectedCategory = v;
                }
              }
            },
          ),
          const SizedBox(width: 6),

          // ── Default Brand ────────────────────────────────────────────
          _compactDropdown<ProductBrand>(
            theme: theme,
            width: 140,
            hint: 'Marca',
            value: _defaultBrand,
            entries: _brands
                .map((b) =>
                    DropdownMenuEntry<ProductBrand>(value: b, label: b.name))
                .toList(),
            onSelected: (v) {
              setState(() => _defaultBrand = v);
              if (v != null) {
                for (final r in _rows) {
                  _invalidateDuplicateCheck(r);
                  r.selectedBrand = v;
                }
              }
            },
          ),
          const SizedBox(width: 6),

          // ── Default Supplier ─────────────────────────────────────────
          _compactDropdown<Supplier>(
            theme: theme,
            width: 150,
            hint: 'Proveedor',
            value: _defaultSupplier,
            entries: _suppliers
                .map(
                    (s) => DropdownMenuEntry<Supplier>(value: s, label: s.name))
                .toList(),
            onSelected: (v) => _onGlobalSupplierChanged(v),
          ),
          const SizedBox(width: 6),

          // ── Default Workshop toggle ──────────────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              color: _defaultWorkshop
                  ? theme.colorScheme.primaryContainer.withValues(alpha: 0.3)
                  : Colors.transparent,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Taller',
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                const SizedBox(width: 2),
                Transform.scale(
                  scale: 0.7,
                  child: Switch.adaptive(
                    value: _defaultWorkshop,
                    onChanged: (v) {
                      setState(() => _defaultWorkshop = v);
                      for (final r in _rows) {
                        r.isWorkshopConsumable = v;
                      }
                    },
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ],
            ),
          ),

          if (isAliExpress) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color:
                    theme.colorScheme.primaryContainer.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.bolt_rounded,
                      size: 12, color: theme.colorScheme.primary),
                  const SizedBox(width: 3),
                  Text('AE####',
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.primary)),
                ],
              ),
            ),
          ],

          const Spacer(),

          // ── Clear defaults ────────────────────────────────────────────
          if (hasDefaults)
            TextButton.icon(
              onPressed: () {
                setState(() {
                  _defaultCategory = null;
                  _defaultBrand = null;
                  _defaultSupplier = null;
                  _defaultWorkshop = false;
                });
              },
              icon: const Icon(Icons.clear_all_rounded, size: 13),
              label: const Text('Limpiar'),
              style: TextButton.styleFrom(
                foregroundColor: theme.colorScheme.onSurfaceVariant,
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                textStyle: const TextStyle(fontSize: 11),
              ),
            ),
        ],
      ),
    );
  }

  Widget _compactDropdown<T>({
    required ThemeData theme,
    required double width,
    required String hint,
    required T? value,
    required List<DropdownMenuEntry<T>> entries,
    required void Function(T?) onSelected,
  }) {
    return SizedBox(
      width: width,
      height: 32,
      child: DropdownMenu<T>(
        width: width,
        menuHeight: 300,
        initialSelection: value,
        hintText: hint,
        textStyle: const TextStyle(fontSize: 11),
        inputDecorationTheme: InputDecorationTheme(
          isDense: true,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: BorderSide(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: BorderSide(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5)),
          ),
          filled: true,
          fillColor: theme.colorScheme.surface,
          constraints: const BoxConstraints(maxHeight: 32),
        ),
        enableFilter: true,
        requestFocusOnTap: true,
        dropdownMenuEntries: entries,
        onSelected: onSelected,
      ),
    );
  }

  Widget _buildBody(ThemeData theme) {
    return Column(
      children: [
        // Result message banner
        if (_resultMessage != null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            color: _resultIsError ? Theme.of(context).colorScheme.errorContainer : VinabikeThemeRoles.of(context).success.container,
            child: Row(
              children: [
                Icon(
                  _resultIsError ? Icons.error_outline : Icons.check_circle,
                  color: _resultIsError
                      ? Theme.of(context).colorScheme.error
                      : VinabikeThemeRoles.of(context).success.accent,
                  size: 18,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _resultMessage!,
                    style: TextStyle(
                      color: _resultIsError
                          ? Theme.of(context).colorScheme.error
                          : VinabikeThemeRoles.of(context).success.onContainer,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 16),
                  onPressed: () => setState(() => _resultMessage = null),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ),

        // Table
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final tableWidth = math.max(_minTableWidth, constraints.maxWidth);

              return Scrollbar(
                controller: _horizontalScrollController,
                thumbVisibility: true,
                notificationPredicate: (n) => n.metrics.axis == Axis.horizontal,
                child: SingleChildScrollView(
                  controller: _horizontalScrollController,
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: tableWidth,
                    child: Column(
                      children: [
                        _buildTableHeader(theme, tableWidth),
                        Expanded(
                          child: ListView.builder(
                            itemCount: _rows.length,
                            itemBuilder: (context, index) =>
                                _buildRow(context, theme, index, tableWidth),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildTableHeader(ThemeData theme, double tableWidth) {
    Widget hCell(String label, double width,
            {TextAlign align = TextAlign.left}) =>
        SizedBox(
          width: width,
          child: Text(
            label.toUpperCase(),
            textAlign: align,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 10,
              letterSpacing: 0.5,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
            ),
          ),
        );

    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: _hPad),
      decoration: BoxDecoration(
        color:
            theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
        border: Border(
          bottom: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: _wChk,
            child: Text('#',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 10,
                  letterSpacing: 0.5,
                  color:
                      theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                )),
          ),
          hCell('Img', _wImg),
          const SizedBox(width: _gap),
          hCell('SKU', _wSku),
          const SizedBox(width: _gap),
          hCell('Nombre *', _wName),
          const SizedBox(width: _gap),
          hCell('Descripción', _wDesc),
          const SizedBox(width: _gap),
          hCell('Costo', _wCost, align: TextAlign.center),
          const SizedBox(width: _gap),
          hCell('Precio *', _wPrice, align: TextAlign.center),
          const SizedBox(width: _gap),
          hCell('Stock', _wStock, align: TextAlign.center),
          const SizedBox(width: _gap),
          hCell('Categoría', _wCat),
          const SizedBox(width: _gap),
          hCell('Marca', _wBrand),
          const SizedBox(width: _gap),
          hCell('Proveedor', _wSupplier),
          const SizedBox(width: _gap),
          hCell('Taller', _wTaller, align: TextAlign.center),
          const SizedBox(width: _gap),
          const SizedBox(width: _wDel), // delete
        ],
      ),
    );
  }

  Widget _buildRow(
      BuildContext context, ThemeData theme, int index, double tableWidth) {
    final draft = _rows[index];
    final isEven = index % 2 == 0;

    return StatefulBuilder(
      builder: (context, rowSetState) {
        final rowBg = draft.isCheckingDuplicates
            ? theme.colorScheme.primaryContainer.withValues(alpha: 0.18)
            : draft.hasPotentialDuplicates
                ? VinabikeThemeRoles.of(context).warning.container
                : draft.hasCheckedDuplicates &&
                        draft.duplicateCheckError == null
                    ? VinabikeThemeRoles.of(context).success.container.withValues(alpha: 0.45)
                    : draft.isSelected
                        ? (isEven
                            ? theme.colorScheme.surface
                            : theme.colorScheme.surfaceContainerLowest)
                        : Theme.of(context).colorScheme.surfaceContainerLow.withValues(alpha: 0.5);

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: _hPad, vertical: 4),
          decoration: BoxDecoration(
            color: rowBg,
            border: Border(
              bottom: BorderSide(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.15),
              ),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // ── Row number + Checkbox ──────────────────────────────────
              SizedBox(
                width: _wChk,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 16,
                      child: Text(
                        '${index + 1}',
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          fontSize: 10,
                          color: theme.colorScheme.onSurfaceVariant
                              .withValues(alpha: 0.5),
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 24,
                      child: Checkbox(
                        value: draft.isSelected,
                        onChanged: (v) {
                          setState(() => draft.isSelected = v ?? false);
                        },
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  ],
                ),
              ),

              // ── Image (drag & drop + click) ─────────────────────────────
              SizedBox(
                width: _wImg - _gap,
                child: DropTarget(
                  onDragDone: (d) async {
                    if (d.files.isNotEmpty) {
                      final f = d.files.first;
                      await _uploadImage(draft, await f.readAsBytes(), f.name);
                    }
                  },
                  onDragEntered: (_) =>
                      setState(() => draft.isHoveringImage = true),
                  onDragExited: (_) =>
                      setState(() => draft.isHoveringImage = false),
                  child: MouseRegion(
                    onEnter: (_) =>
                        setState(() => draft.isHoveringImage = true),
                    onExit: (_) =>
                        setState(() => draft.isHoveringImage = false),
                    cursor: SystemMouseCursors.click,
                    child: Stack(
                      children: [
                        InkWell(
                          onTap: () async {
                            final r = await ImageService.pickImage();
                            if (r != null) {
                              await _uploadImage(draft, r.bytes, r.name);
                            }
                          },
                          borderRadius: BorderRadius.circular(6),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: draft.isHoveringImage
                                  ? theme.colorScheme.primary
                                      .withValues(alpha: 0.06)
                                  : theme.colorScheme.surfaceContainerHigh
                                      .withValues(alpha: 0.3),
                              border: Border.all(
                                color: draft.isHoveringImage
                                    ? theme.colorScheme.primary
                                        .withValues(alpha: 0.5)
                                    : theme.colorScheme.outlineVariant
                                        .withValues(alpha: 0.3),
                                width: 1,
                              ),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: draft.isUploadingImage
                                ? const Center(
                                    child: SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2),
                                    ),
                                  )
                                : draft.imageUrl != null
                                    ? ClipRRect(
                                        borderRadius: BorderRadius.circular(5),
                                        child: ImageService.buildProductImage(
                                          imageUrl: draft.imageUrl,
                                          size: 42,
                                        ),
                                      )
                                    : Icon(
                                        draft.isHoveringImage
                                            ? Icons.add_photo_alternate_rounded
                                            : Icons.image_outlined,
                                        size: 16,
                                        color: draft.isHoveringImage
                                            ? theme.colorScheme.primary
                                            : theme.colorScheme.onSurfaceVariant
                                                .withValues(alpha: 0.3),
                                      ),
                          ),
                        ),
                        // Remove image button (on hover when image exists)
                        if (draft.imageUrl != null && draft.isHoveringImage)
                          Positioned(
                            right: -2,
                            top: -2,
                            child: GestureDetector(
                              onTap: () => setState(() {
                                _invalidateDuplicateCheck(draft);
                                draft.imageUrl = null;
                                draft.imageUrlOptimized = null;
                                draft.imageBytes = null;
                                draft.imageFileName = null;
                              }),
                              child: Container(
                                width: 15,
                                height: 15,
                                decoration: BoxDecoration(
                                  color: Theme.of(context).colorScheme.error,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                      color: Colors.white, width: 1.5),
                                ),
                                child: const Icon(Icons.close,
                                    size: 9, color: Colors.white),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: _gap),

              // ── SKU ─────────────────────────────────────────────────────
              _textField(
                controller: draft.skuController,
                width: _wSku,
                enabled: draft.isSelected && !draft.isGeneratingSku,
                hint: draft.isGeneratingSku ? 'Generando...' : 'ABC-001',
                monospace: true,
                suffixIcon: draft.isGeneratingSku
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : null,
              ),
              const SizedBox(width: _gap),

              // ── Name ────────────────────────────────────────────────────
              _textField(
                controller: draft.nameController,
                width: _wName,
                enabled: draft.isSelected,
                hint: 'Nombre del producto',
                maxLines: 2,
                onChanged: (_) {
                  _invalidateDuplicateCheck(draft);
                  setState(() {});
                },
                errorText: _hasAttemptedCreate &&
                        draft.nameController.text.trim().isEmpty &&
                        draft.isSelected
                    ? 'Requerido'
                    : null,
                suffixIcon: _buildDuplicateStatusIcon(draft),
              ),
              const SizedBox(width: _gap),

              // ── Description ─────────────────────────────────────────────
              _textField(
                controller: draft.descriptionController,
                width: _wDesc,
                enabled: draft.isSelected,
                hint: 'Descripción...',
                maxLines: 2,
                onChanged: (_) {
                  _invalidateDuplicateCheck(draft);
                  setState(() {});
                },
              ),
              const SizedBox(width: _gap),

              // ── Cost ────────────────────────────────────────────────────
              _textField(
                controller: draft.costController,
                width: _wCost,
                enabled: draft.isSelected,
                hint: '0',
                prefix: '\$ ',
                numeric: true,
                textAlign: TextAlign.right,
                onChanged: (_) {
                  _invalidateDuplicateCheck(draft);
                  setState(() {});
                },
              ),
              const SizedBox(width: _gap),

              // ── Price ───────────────────────────────────────────────────
              _textField(
                controller: draft.priceController,
                width: _wPrice,
                enabled: draft.isSelected,
                hint: '0',
                prefix: '\$ ',
                numeric: true,
                textAlign: TextAlign.right,
                onChanged: (_) {
                  _invalidateDuplicateCheck(draft);
                  setState(() {});
                },
                errorText: _hasAttemptedCreate &&
                        draft.isSelected &&
                        (draft.priceController.text.isEmpty ||
                            (double.tryParse(draft.priceController.text
                                        .replaceAll(',', '.')) ??
                                    0) <=
                                0)
                    ? '> 0'
                    : null,
              ),
              const SizedBox(width: _gap),

              // ── Initial Stock ────────────────────────────────────────────
              _textField(
                controller: draft.stockController,
                width: _wStock,
                enabled: draft.isSelected,
                hint: '0',
                numeric: true,
                textAlign: TextAlign.center,
                onChanged: (_) {
                  _invalidateDuplicateCheck(draft);
                  setState(() {});
                },
              ),
              const SizedBox(width: _gap),

              // ── Category ─────────────────────────────────────────────────
              _dropdownMenu<Category>(
                width: _wCat,
                enabled: draft.isSelected,
                hint: 'Categoría',
                initialSelection: draft.selectedCategory,
                entries: _categories
                    .map((c) =>
                        DropdownMenuEntry<Category>(value: c, label: c.name))
                    .toList(),
                onSelected: (v) {
                  _invalidateDuplicateCheck(draft);
                  setState(() => draft.selectedCategory = v);
                },
              ),
              const SizedBox(width: _gap),

              // ── Brand ────────────────────────────────────────────────────
              _dropdownMenu<ProductBrand>(
                width: _wBrand,
                enabled: draft.isSelected,
                hint: 'Marca',
                initialSelection: draft.selectedBrand,
                entries: _brands
                    .map((b) => DropdownMenuEntry<ProductBrand>(
                        value: b, label: b.name))
                    .toList(),
                onSelected: (v) {
                  _invalidateDuplicateCheck(draft);
                  setState(() => draft.selectedBrand = v);
                },
              ),
              const SizedBox(width: _gap),

              // ── Supplier ─────────────────────────────────────────────────
              _dropdownMenu<Supplier>(
                width: _wSupplier,
                enabled: draft.isSelected,
                hint: 'Proveedor',
                initialSelection: draft.selectedSupplier,
                entries: _suppliers
                    .map((s) =>
                        DropdownMenuEntry<Supplier>(value: s, label: s.name))
                    .toList(),
                onSelected: (v) => _onSupplierSelected(draft, v),
              ),
              const SizedBox(width: _gap),

              // ── Workshop toggle ───────────────────────────────────────────
              SizedBox(
                width: _wTaller,
                child: Tooltip(
                  message: 'Consumible de taller\n(no reduce stock en ventas)',
                  child: Center(
                    child: Transform.scale(
                      scale: 0.82,
                      child: Switch.adaptive(
                        value: draft.isWorkshopConsumable,
                        onChanged: draft.isSelected
                            ? (v) =>
                                setState(() => draft.isWorkshopConsumable = v)
                            : null,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: _gap),

              // ── Delete row ───────────────────────────────────────────────
              SizedBox(
                width: _wDel,
                child: IconButton(
                  icon: Icon(Icons.delete_outline,
                      size: 16, color: Theme.of(context).colorScheme.error),
                  onPressed: () => _removeRow(index),
                  tooltip: 'Eliminar fila',
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildFooter(ThemeData theme) {
    final selectedCount = _rows.where((r) => r.isSelected).length;
    final validCount = _rows.where((r) => r.isSelected && r.isValid).length;
    final invalidCount = selectedCount - validCount;
    final duplicateWarningCount = _rowsWithDuplicateWarnings;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          top: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
          ),
        ),
      ),
      child: Row(
        children: [
          // Legend
          if (invalidCount > 0) ...[
            Icon(Icons.warning_amber_rounded,
                size: 14, color: VinabikeThemeRoles.of(context).warning.accent),
            const SizedBox(width: 5),
            Text(
              '$invalidCount incompleta(s)',
              style: TextStyle(
                fontSize: 11,
                color: VinabikeThemeRoles.of(context).warning.accent,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '· nombre y precio requeridos',
              style: TextStyle(
                fontSize: 11,
                color: VinabikeThemeRoles.of(context).warning.border,
              ),
            ),
            if (duplicateWarningCount > 0) ...[
              const SizedBox(width: 10),
              Text(
                '· $duplicateWarningCount con parecidos',
                style: TextStyle(
                  fontSize: 11,
                  color: VinabikeThemeRoles.of(context).warning.accent,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ] else
            Text(
              duplicateWarningCount > 0
                  ? '$validCount producto(s) listos · $duplicateWarningCount con parecidos'
                  : '$validCount producto(s) listos',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          const Spacer(),
          // Cancel
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            ),
            child: const Text('Cancelar'),
          ),
          const SizedBox(width: 8),
          // Create
          FilledButton.icon(
            onPressed: validCount > 0 && !_isCreating ? _createProducts : null,
            icon: _isCreating
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.check_rounded, size: 16),
            label: Text(
              _isCreating
                  ? 'Creando...'
                  : 'Crear $validCount producto${validCount != 1 ? 's' : ''}',
              style: const TextStyle(fontSize: 13),
            ),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Helper widgets ───────────────────────────────────────────────────────

  Widget _textField({
    required TextEditingController controller,
    required double width,
    bool enabled = true,
    String? hint,
    String? prefix,
    bool numeric = false,
    bool monospace = false,
    int maxLines = 1,
    TextAlign textAlign = TextAlign.left,
    void Function(String)? onChanged,
    String? errorText,
    Widget? suffixIcon,
  }) {
    return SizedBox(
      width: width,
      child: TextField(
        controller: controller,
        enabled: enabled,
        maxLines: maxLines,
        minLines: 1,
        textAlign: textAlign,
        keyboardType: numeric
            ? const TextInputType.numberWithOptions(decimal: true)
            : TextInputType.text,
        onChanged: onChanged,
        decoration: InputDecoration(
          isDense: true,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(5),
            borderSide: BorderSide(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(5),
            borderSide: BorderSide(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(5),
            borderSide: BorderSide(
              color: Theme.of(context).colorScheme.primary,
              width: 1.5,
            ),
          ),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 7, vertical: 7),
          hintText: hint,
          prefixText: prefix,
          prefixStyle: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          suffixIcon: suffixIcon != null
              ? Padding(
                  padding: const EdgeInsets.all(10),
                  child: suffixIcon,
                )
              : null,
          errorText: errorText,
          errorStyle: const TextStyle(fontSize: 9, height: 0.8),
          hintStyle: TextStyle(color: Theme.of(context).colorScheme.outline, fontSize: 11),
        ),
        style: TextStyle(
          fontSize: 12,
          fontFamily: monospace ? 'monospace' : null,
        ),
      ),
    );
  }

  Widget _dropdownMenu<T>({
    required double width,
    required bool enabled,
    required String hint,
    required T? initialSelection,
    required List<DropdownMenuEntry<T>> entries,
    required void Function(T?) onSelected,
  }) {
    return SizedBox(
      width: width,
      child: DropdownMenu<T>(
        width: width,
        menuHeight: 280,
        initialSelection: initialSelection,
        hintText: hint,
        textStyle: const TextStyle(fontSize: 11),
        inputDecorationTheme: InputDecorationTheme(
          isDense: true,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 7, vertical: 7),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(5),
            borderSide: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(5),
            borderSide: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
          ),
        ),
        enabled: enabled,
        enableFilter: true,
        requestFocusOnTap: true,
        dropdownMenuEntries: entries,
        onSelected: onSelected,
      ),
    );
  }
}
