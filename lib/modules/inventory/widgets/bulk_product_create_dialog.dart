import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
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
import '../services/brand_service.dart';
import '../services/category_service.dart';
import '../services/inventory_service.dart' as inv_service;
import '../services/product_image_fingerprint_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Entry model for one row in the bulk-create table
// ─────────────────────────────────────────────────────────────────────────────

class _PotentialDuplicateCandidate {
  const _PotentialDuplicateCandidate({
    required this.product,
    required this.overallScore,
    required this.keywordScore,
    required this.semanticScore,
    required this.imageScore,
    required this.aiTypeScore,
    required this.identityScore,
    required this.metadataScore,
    required this.hasProductImage,
    required this.signals,
  });

  final Product product;
  final double overallScore;
  final double keywordScore;
  final double semanticScore;
  final double imageScore;
  final double aiTypeScore;
  final double identityScore;
  final double metadataScore;
  final bool hasProductImage;
  final List<String> signals;
}

class _ProductDraft {
  bool isSelected = true;
  bool isUploadingImage = false;
  bool isHoveringImage = false;
  bool isWorkshopConsumable = false;
  bool isGeneratingSku = false;
  bool isCheckingDuplicates = false;
  bool hasCheckedDuplicates = false;
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
  AIProductImageAnalysis? aiImageAnalysis;
  String? aiImageAnalysisError;
  bool hasAttemptedAiImageAnalysis = false;
  String? duplicateCheckError;
  List<_PotentialDuplicateCandidate> duplicateCandidates = const [];

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
  static const Set<String> _duplicateStopWords = {
    'de',
    'del',
    'la',
    'las',
    'el',
    'los',
    'y',
    'con',
    'sin',
    'para',
    'por',
    'the',
    'and',
    'for',
    'kit',
    'pack',
    'set',
    'pieza',
    'piezas',
  };

  /// Bidirectional synonym groups for bike parts.
  /// When a token matches any word in a group, ALL words in the group
  /// are added so that "cambio trasero" matches "desviador trasero".
  static const List<Set<String>> _bikeSynonymGroups = [
    {'cambio', 'desviador', 'derailleur'},
    {'manilla', 'shifter', 'palanca'},
    {'pinon', 'cassette', 'freewheel'},
    {'plato', 'chainring', 'corona'},
    {'freno', 'brake'},
    {'llanta', 'rim', 'aro'},
    {'cubierta', 'neumatico', 'tire', 'tyre'},
    {'camara', 'tube', 'tubo'},
    {'horquilla', 'fork', 'suspension'},
    {'manubrio', 'handlebar', 'manillar'},
    {'pedal', 'pedalier'},
    {'cadena', 'chain'},
    {'poste', 'stem', 'potencia'},
  ];

  /// Generic category words that describe product TYPE, not identity.
  /// These are filtered out when computing identity boost so that
  /// "shimano deore" is treated as an identity signal while
  /// "cambio trasero" is treated as a category signal.
  static const Set<String> _genericCategoryTokens = {
    // Spanish bike part categories
    'cambio', 'desviador', 'trasero', 'delantero', 'freno', 'disco',
    'llanta', 'cubierta', 'camara', 'cadena', 'pinon', 'cassette',
    'plato', 'manilla', 'pedal', 'horquilla', 'manubrio', 'poste',
    'potencia', 'tija', 'sillin', 'eje', 'maza', 'radio', 'rayo',
    'neumatico', 'valvula', 'patin', 'zapata', 'rotor', 'pastilla',
    'cable', 'funda', 'tornillo', 'perno', 'tuerca', 'abrazadera',
    'casco', 'luz', 'bomba', 'candado', 'porta', 'botella', 'parrilla',
    // English bike part categories
    'derailleur', 'brake', 'rim', 'tire', 'tyre', 'tube', 'chain',
    'chainring', 'freewheel', 'shifter', 'fork', 'handlebar', 'stem',
    'seatpost', 'saddle', 'hub', 'spoke', 'pad', 'lever',
    'housing', 'crank',
    // Generic qualifiers
    'mtb', 'ruta', 'road', 'bmx', 'speed', 'vel', 'velocidades',
    'par', 'set', 'juego', 'kit', 'piezas', 'pieza', 'generico',
    'generica', 'genericas', 'genericos', 'compatible', 'universal',
    'adaptador', 'adaptadores', 'adapter', 'adaptor', 'bracket', 'mount',
    'postmount', 'post', 'caliper',
    'negro', 'negra', 'plata', 'rojo', 'azul', 'blanco', 'gris',
    'rear', 'front', 'left', 'right', 'index', 'friction',
    // Size/count qualifiers
    'mm', 'cm', 'pulgadas', 'inch', 'tornillos', 'pernos',
  };

  static const double _semanticDuplicateThreshold = 0.56;
  static const int _semanticDuplicateLimit = 10;
  static const int _duplicateResultLimit = 4;
  static const int _imageSimilarityBatchSize = 12;
  static const int _imageFirstCoarsePool = 40;
  static const int _imageFirstDetailedPool = 20;
  static const int _textOnlyDetailedPool = 8;

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
  final Map<String, ProductImageFingerprint?> _productImageHashCache = {};
  final Map<String, Uint8List?> _productImageBytesCache = {};

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
    _resetAiImageAnalysis(draft);
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
    setState(() => draft.selectedSupplier = supplier);
    await _generateSkuForRow(draft);
  }

  void _invalidateDuplicateCheck(_ProductDraft draft) {
    draft.hasCheckedDuplicates = false;
    draft.isCheckingDuplicates = false;
    draft.duplicateCheckError = null;
    draft.duplicateCandidates = const [];
  }

  void _resetAiImageAnalysis(_ProductDraft draft) {
    draft.aiImageAnalysis = null;
    draft.aiImageAnalysisError = null;
    draft.hasAttemptedAiImageAnalysis = false;
  }

  Future<AIProductImageAnalysis?> _getAiImageAnalysis(
    _ProductDraft draft,
  ) async {
    final imageBytes = draft.imageBytes;
    if (imageBytes == null || imageBytes.isEmpty) return null;

    if (draft.aiImageAnalysis != null) {
      return draft.aiImageAnalysis;
    }

    if (draft.hasAttemptedAiImageAnalysis) {
      return null;
    }

    draft.hasAttemptedAiImageAnalysis = true;

    try {
      final analysis = await _aiAssistantService.analyzeProductImage(
        imageBytes,
        fileName: draft.imageFileName,
        typedName: draft.nameController.text.trim(),
        typedDescription: draft.descriptionController.text.trim(),
      );
      draft.aiImageAnalysis = analysis;
      draft.aiImageAnalysisError = null;
      return analysis;
    } catch (e) {
      debugPrint('BulkCreate: AI image analysis failed: $e');
      draft.aiImageAnalysisError = e.toString();
      return null;
    }
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
      final productsById = <String, Product>{
        for (final product in products)
          if (product.id != null && product.id!.isNotEmpty)
            product.id!: product,
      };

      for (final draft in rowsToCheck) {
        await _runDuplicateCheckForDraft(draft, products, productsById);
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
    Map<String, Product> productsById,
  ) async {
    setState(() {
      draft.isCheckingDuplicates = true;
      draft.hasCheckedDuplicates = false;
      draft.duplicateCheckError = null;
      draft.duplicateCandidates = const [];
    });

    try {
      final candidates =
          await _findDuplicateCandidatesForDraft(draft, products, productsById);

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

  Future<List<_PotentialDuplicateCandidate>> _findDuplicateCandidatesForDraft(
    _ProductDraft draft,
    List<Product> products,
    Map<String, Product> productsById,
  ) async {
    // ── 0. Setup ──
    final aiImageAnalysis = await _getAiImageAnalysis(draft);
    final probeText = _buildDuplicateProbeText(
      draft,
      aiImageAnalysis: aiImageAnalysis,
    );
    final probeTokens = _extractSimilarityTokens(probeText);
    final normalizedName = _normalizeSimilarityText(draft.nameController.text);
    final sparseTextProbe = _hasSparseTextSimilarityProbe(draft, probeTokens);
    final semanticScores = <String, double>{};
    final candidatesById = <String, Product>{};

    final draftImageFingerprint = draft.imageBytes == null
        ? null
        : ProductImageFingerprintService.fromBytes(draft.imageBytes!);

    // ── Supplier-scoped product pool ──
    // When a supplier is selected, limit image matching to that supplier's
    // products. This makes matching faster AND more relevant (e.g. for
    // AliExpress batches).
    final supplierScopedProducts = _supplierScopedProducts(
      products,
      draft.selectedSupplier,
    );

    // ════════════════════════════════════════════════════════════════════════
    // PATH A: IMAGE-FIRST (when draft has an image)
    // ════════════════════════════════════════════════════════════════════════
    if (draftImageFingerprint != null) {
      // ── A1. Coarse image scan: compare against ALL products with images ──
      // This is hash-based (~instant per product), so scanning 500 is fine.
      final coarseImageResults = <({
        Product product,
        double coarseScore,
      })>[];

      final productsWithImages = supplierScopedProducts.where((product) {
        final productId = product.id;
        if (productId == null || productId.isEmpty) return false;
        if (!product.isActive || product.isService) return false;
        return (_productPreviewUrl(product)?.trim().isNotEmpty ?? false);
      }).toList(growable: false);

      debugPrint('🔍 [DUP] Image-first: scanning ${productsWithImages.length} '
          'products with images'
          '${draft.selectedSupplier != null ? ' (supplier: ${draft.selectedSupplier!.name})' : ' (all suppliers)'}');

      for (var start = 0;
          start < productsWithImages.length;
          start += _imageSimilarityBatchSize) {
        final batch = productsWithImages
            .skip(start)
            .take(_imageSimilarityBatchSize)
            .toList(growable: false);

        final batchScores = await Future.wait(
          batch.map((product) async {
            final score = await _computeProductImageSimilarity(
              product,
              draftImageFingerprint,
            );
            return (product: product, coarseScore: score);
          }),
        );

        coarseImageResults.addAll(batchScores);
      }

      // Sort by visual similarity and take top N
      coarseImageResults.sort((a, b) => b.coarseScore.compareTo(a.coarseScore));
      final topVisual = coarseImageResults
          .take(_imageFirstCoarsePool)
          .toList(growable: false);

      for (final entry in topVisual) {
        final productId = entry.product.id;
        if (productId != null) {
          candidatesById[productId] = entry.product;
        }
      }

      // ── DEBUG: Top visual matches ──
      for (var i = 0; i < topVisual.length && i < 10; i++) {
        debugPrint('🔍 [DUP] visual#${i + 1}: '
            'coarse=${topVisual[i].coarseScore.toStringAsFixed(3)} '
            '"${topVisual[i].product.name}" [${topVisual[i].product.sku}]');
      }

      // ── A2. Also inject text-based candidates (secondary) ──
      // These cover products without images or outside the visual top-N.
      if (probeText.isNotEmpty) {
        final vector = await _aiAssistantService.generateEmbedding(probeText);
        if (vector != null) {
          try {
            final semanticMatches =
                await _inventoryService.searchProductsSemantic(
              vector,
              threshold: _semanticDuplicateThreshold,
              limit: _semanticDuplicateLimit,
            );
            for (final result in semanticMatches) {
              final id = result['id']?.toString();
              if (id == null || id.isEmpty) continue;
              final product = productsById[id];
              if (product == null || !product.isActive || product.isService) {
                continue;
              }
              final similarity =
                  (((result['similarity'] as num?)?.toDouble() ?? 0)
                          .clamp(0, 1))
                      .toDouble();
              semanticScores[id] =
                  math.max(semanticScores[id] ?? 0, similarity);
              candidatesById.putIfAbsent(id, () => product);
            }
          } catch (e) {
            debugPrint('BulkCreate: semantic duplicate search failed: $e');
          }
        }
      }

      // Inject a few strong keyword matches not already in the pool.
      for (final product in supplierScopedProducts) {
        final productId = product.id;
        if (productId == null || candidatesById.containsKey(productId)) {
          continue;
        }
        if (!product.isActive || product.isService) continue;
        final aiTypeScore = _computeAiImageTypeScore(product, aiImageAnalysis);
        if (aiTypeScore >= 0.72) {
          candidatesById[productId] = product;
        }
      }

      debugPrint(
          '🔍 [DUP] Image-first: ${candidatesById.length} total candidates '
          'after visual+text merge');

      // ── A3. Score ALL candidates with all signals ──
      final coarseScoreMap = <String, double>{
        for (final entry in coarseImageResults)
          if (entry.product.id != null) entry.product.id!: entry.coarseScore,
      };

      final preliminary = <({
        Product product,
        bool hasProductImage,
        double keywordScore,
        double metadataScore,
        double semanticScore,
        double aiTypeScore,
        double identityScore,
        double coarseImageScore,
        double prelimScore,
      })>[];

      for (final product in candidatesById.values) {
        final productId = product.id!;
        final keywordScore =
            _computeKeywordScore(draft, product, probeTokens, normalizedName);
        final metadataScore = _computeMetadataScore(draft, product);
        final semanticScore = semanticScores[productId] ?? 0;
        final aiTypeScore = _computeAiImageTypeScore(product, aiImageAnalysis);
        final hasProductImage = _productHasPreviewImage(product);
        final coarseImageScore = coarseScoreMap[productId] ?? 0.0;
        final identityScore = _computeAiIdentityBoost(
          product,
          aiImageAnalysis,
        );
        final basePrelimScore = _combineDuplicateScores(
          keywordScore: keywordScore,
          semanticScore: semanticScore,
          metadataScore: metadataScore,
          imageScore: coarseImageScore,
          aiTypeScore: aiTypeScore,
          identityScore: identityScore,
        );
        final dimensionPenalty = _computeDimensionMismatchPenalty(
          product,
          aiImageAnalysis,
        );
        final brakeFamilyPenalty = _computeBrakeFamilyPenalty(
          product,
          aiImageAnalysis,
        );
        final passesCategoryGate = _passesAiCategoryGate(
          product,
          aiImageAnalysis,
          keywordScore: keywordScore,
          identityScore: identityScore,
          metadataScore: metadataScore,
        );
        if (!passesCategoryGate) continue;

        preliminary.add((
          product: product,
          hasProductImage: hasProductImage,
          keywordScore: keywordScore,
          metadataScore: metadataScore,
          semanticScore: semanticScore,
          aiTypeScore: aiTypeScore,
          identityScore: identityScore,
          coarseImageScore: coarseImageScore,
          prelimScore: (_adjustPreliminaryScoreForImageProbe(
                    prelimScore: basePrelimScore,
                    hasImageProbe: true,
                    candidateHasImage: hasProductImage,
                    sparseTextProbe: sparseTextProbe,
                  ) *
                  dimensionPenalty *
                  brakeFamilyPenalty)
              .clamp(0.0, 1.0),
        ));
      }

      preliminary.sort((a, b) => b.prelimScore.compareTo(a.prelimScore));

      // ── DEBUG: AI identity terms + top preliminary ──
      if (aiImageAnalysis != null) {
        final idTerms = _extractAiIdentityTerms(aiImageAnalysis);
        debugPrint('🔍 [DUP] AI: type="${aiImageAnalysis.primaryType}" '
            'terms=${aiImageAnalysis.catalogTerms} '
            'identity=$idTerms '
            'conf=${aiImageAnalysis.confidence}');
      }
      for (var i = 0; i < preliminary.length && i < 15; i++) {
        final e = preliminary[i];
        debugPrint('🔍 [DUP] prelim#${i + 1}: '
            'coarseImg=${e.coarseImageScore.toStringAsFixed(3)} '
            'aiType=${e.aiTypeScore.toStringAsFixed(3)} '
            'kw=${e.keywordScore.toStringAsFixed(3)} '
            'id=${e.identityScore.toStringAsFixed(3)} '
            'prelim=${e.prelimScore.toStringAsFixed(3)} '
            '"${e.product.name}" [${e.product.sku}]');
      }

      // ── A4. Detailed image comparison on top candidates ──
      final detailedPool = math.min(
        _imageFirstDetailedPool,
        preliminary.length,
      );
      debugPrint('🔍 [DUP] Detailed comparison: $detailedPool candidates');

      final scoredCandidates = <_PotentialDuplicateCandidate>[];

      for (final entry in preliminary.take(detailedPool)) {
        final imageScore = await _computeVerifiedProductImageSimilarity(
          entry.product,
          draftImageFingerprint,
          draftImageBytes: draft.imageBytes,
        );
        final baseOverallScore = _combineDuplicateScores(
          keywordScore: entry.keywordScore,
          semanticScore: entry.semanticScore,
          metadataScore: entry.metadataScore,
          imageScore: imageScore,
          aiTypeScore: entry.aiTypeScore,
          identityScore: entry.identityScore,
        );
        final adjustedScore = _adjustFinalScoreForImageProbe(
          overallScore: baseOverallScore,
          hasImageProbe: true,
          candidateHasImage: entry.hasProductImage,
          imageScore: imageScore,
          keywordScore: entry.keywordScore,
          metadataScore: entry.metadataScore,
          aiTypeScore: entry.aiTypeScore,
          sparseTextProbe: sparseTextProbe,
        );
        final categoryPenalty = _computeCategoryMismatchPenalty(
          entry.product,
          aiImageAnalysis,
        );
        final accessoryPenalty = _computeAccessoryMismatchPenalty(
          entry.product,
          aiImageAnalysis,
        );
        final brakeFamilyPenalty = _computeBrakeFamilyPenalty(
          entry.product,
          aiImageAnalysis,
        );
        final dimensionPenalty = _computeDimensionMismatchPenalty(
          entry.product,
          aiImageAnalysis,
        );
        final overallScore = (adjustedScore *
                categoryPenalty *
                accessoryPenalty *
                brakeFamilyPenalty *
                dimensionPenalty)
            .clamp(0.0, 1.0);

        // ── DEBUG: detailed scores for interesting candidates ──
        final nameLC = entry.product.name.toLowerCase();
        if (nameLC.contains('deore') ||
            nameLC.contains('shimano') ||
            nameLC.contains('disco') ||
            nameLC.contains('rotor') ||
            nameLC.contains('adapt') ||
            overallScore >= 0.60) {
          debugPrint('🔍 [DUP] detailed: '
              'coarse=${entry.coarseImageScore.toStringAsFixed(3)} '
              'verified=${imageScore.toStringAsFixed(3)} '
              'id=${entry.identityScore.toStringAsFixed(3)} '
              'catPen=${categoryPenalty.toStringAsFixed(2)} '
              'accPen=${accessoryPenalty.toStringAsFixed(2)} '
              'famPen=${brakeFamilyPenalty.toStringAsFixed(2)} '
              'dimPen=${dimensionPenalty.toStringAsFixed(2)} '
              'overall=${overallScore.toStringAsFixed(3)} '
              '"${entry.product.name}" [${entry.product.sku}]');
        }

        final candidate = _PotentialDuplicateCandidate(
          product: entry.product,
          overallScore: overallScore,
          keywordScore: entry.keywordScore,
          semanticScore: entry.semanticScore,
          imageScore: imageScore,
          aiTypeScore: entry.aiTypeScore,
          identityScore: entry.identityScore,
          metadataScore: entry.metadataScore,
          hasProductImage: entry.hasProductImage,
          signals: _buildDuplicateSignals(
            entry.product,
            keywordScore: entry.keywordScore,
            semanticScore: entry.semanticScore,
            imageScore: imageScore,
            aiTypeScore: entry.aiTypeScore,
            identityScore: entry.identityScore,
            metadataScore: entry.metadataScore,
            aiPrimaryType: aiImageAnalysis?.primaryType,
          ),
        );

        if (_shouldKeepDuplicateCandidate(candidate)) {
          scoredCandidates.add(candidate);
        }
      }

      return _sortAndLimitCandidates(scoredCandidates);
    }

    // ════════════════════════════════════════════════════════════════════════
    // PATH B: TEXT-ONLY (no image uploaded)
    // ════════════════════════════════════════════════════════════════════════

    // ── B1. Semantic search ──
    if (probeText.isNotEmpty) {
      final vector = await _aiAssistantService.generateEmbedding(probeText);
      if (vector != null) {
        try {
          final semanticMatches =
              await _inventoryService.searchProductsSemantic(
            vector,
            threshold: _semanticDuplicateThreshold,
            limit: _semanticDuplicateLimit,
          );
          for (final result in semanticMatches) {
            final id = result['id']?.toString();
            if (id == null || id.isEmpty) continue;
            final product = productsById[id];
            if (product == null || !product.isActive || product.isService) {
              continue;
            }
            final similarity =
                (((result['similarity'] as num?)?.toDouble() ?? 0).clamp(0, 1))
                    .toDouble();
            semanticScores[id] = math.max(semanticScores[id] ?? 0, similarity);
            candidatesById[id] = product;
          }
        } catch (e) {
          debugPrint('BulkCreate: semantic duplicate search failed: $e');
        }
      }
    }

    // ── B2. Keyword pre-filter ──
    final keywordRanked = <({Product product, double score})>[];

    for (final product in supplierScopedProducts) {
      final productId = product.id;
      if (productId == null || productId.isEmpty) continue;
      if (!product.isActive || product.isService) continue;

      final keywordScore =
          _computeKeywordScore(draft, product, probeTokens, normalizedName);
      final aiTypeScore = _computeAiImageTypeScore(product, aiImageAnalysis);
      final metadataScore = _computeMetadataScore(draft, product);
      final exactSku = draft.sku.isNotEmpty &&
          product.sku.trim().toLowerCase() == draft.sku.toLowerCase();
      final preScore = exactSku
          ? 1.0
          : math.max(
              math.max(keywordScore, aiTypeScore),
              keywordScore * 0.50 + metadataScore * 0.20 + aiTypeScore * 0.30,
            );

      if (preScore >= 0.32 ||
          metadataScore >= 0.72 ||
          aiTypeScore >= 0.72 ||
          exactSku) {
        keywordRanked.add((product: product, score: preScore));
      }
    }

    keywordRanked.sort((a, b) => b.score.compareTo(a.score));
    for (final candidate in keywordRanked.take(16)) {
      final productId = candidate.product.id;
      if (productId == null) continue;
      candidatesById[productId] = candidate.product;
    }

    // ── B3. Score and rank ──
    final preliminary = candidatesById.values.map((product) {
      final productId = product.id!;
      final keywordScore =
          _computeKeywordScore(draft, product, probeTokens, normalizedName);
      final metadataScore = _computeMetadataScore(draft, product);
      final semanticScore = semanticScores[productId] ?? 0;
      final aiTypeScore = _computeAiImageTypeScore(product, aiImageAnalysis);
      final basePrelimScore = _combineDuplicateScores(
        keywordScore: keywordScore,
        semanticScore: semanticScore,
        metadataScore: metadataScore,
        imageScore: 0,
        aiTypeScore: aiTypeScore,
        identityScore: 0,
      );

      return (
        product: product,
        hasProductImage: _productHasPreviewImage(product),
        keywordScore: keywordScore,
        metadataScore: metadataScore,
        semanticScore: semanticScore,
        aiTypeScore: aiTypeScore,
        prelimScore: basePrelimScore,
      );
    }).toList(growable: false)
      ..sort((a, b) => b.prelimScore.compareTo(a.prelimScore));

    debugPrint('🔍 [DUP] Text-only: ${candidatesById.length} candidates');

    final scoredCandidates = <_PotentialDuplicateCandidate>[];

    for (final entry in preliminary.take(_textOnlyDetailedPool)) {
      final candidate = _PotentialDuplicateCandidate(
        product: entry.product,
        overallScore: entry.prelimScore,
        keywordScore: entry.keywordScore,
        semanticScore: entry.semanticScore,
        imageScore: 0,
        aiTypeScore: entry.aiTypeScore,
        identityScore: 0,
        metadataScore: entry.metadataScore,
        hasProductImage: entry.hasProductImage,
        signals: _buildDuplicateSignals(
          entry.product,
          keywordScore: entry.keywordScore,
          semanticScore: entry.semanticScore,
          imageScore: 0,
          aiTypeScore: entry.aiTypeScore,
          identityScore: 0,
          metadataScore: entry.metadataScore,
          aiPrimaryType: aiImageAnalysis?.primaryType,
        ),
      );

      if (_shouldKeepDuplicateCandidate(candidate)) {
        scoredCandidates.add(candidate);
      }
    }

    return _sortAndLimitCandidates(scoredCandidates);
  }

  /// Filter products by supplier when one is selected.
  /// Falls back to full product list when no supplier is set.
  List<Product> _supplierScopedProducts(
    List<Product> allProducts,
    Supplier? supplier,
  ) {
    if (supplier == null) return allProducts;

    // For AliExpress-family suppliers, match any AliExpress variant
    final isAliExpress =
        _inventoryService.isAliExpressSupplierName(supplier.name);

    final scoped = allProducts.where((product) {
      if (isAliExpress) {
        return _inventoryService.isAliExpressSupplierName(product.supplierName);
      }
      return product.supplierId == supplier.id;
    }).toList(growable: false);

    // If scoping yields very few products, fall back to all so we don't
    // miss obvious duplicates that were imported under a different supplier.
    if (scoped.length < 5) return allProducts;

    debugPrint('🔍 [DUP] Supplier scope: ${scoped.length} products '
        'for "${supplier.name}" (of ${allProducts.length} total)');
    return scoped;
  }

  List<_PotentialDuplicateCandidate> _sortAndLimitCandidates(
    List<_PotentialDuplicateCandidate> candidates,
  ) {
    candidates.sort((a, b) {
      final overallCompare = b.overallScore.compareTo(a.overallScore);
      if (overallCompare != 0) return overallCompare;

      final identityCompare = b.identityScore.compareTo(a.identityScore);
      if (identityCompare != 0) return identityCompare;

      final aiTypeCompare = b.aiTypeScore.compareTo(a.aiTypeScore);
      if (aiTypeCompare != 0) return aiTypeCompare;

      final imagePresenceCompare =
          (b.hasProductImage ? 1 : 0).compareTo(a.hasProductImage ? 1 : 0);
      if (imagePresenceCompare != 0) return imagePresenceCompare;

      final imageCompare = b.imageScore.compareTo(a.imageScore);
      if (imageCompare != 0) return imageCompare;

      return b.keywordScore.compareTo(a.keywordScore);
    });

    return candidates.take(_duplicateResultLimit).toList(growable: false);
  }

  bool _hasSparseTextSimilarityProbe(
    _ProductDraft draft,
    Set<String> probeTokens,
  ) {
    if (draft.descriptionController.text.trim().isNotEmpty) return false;
    if (draft.nameController.text.trim().isEmpty) return false;
    return probeTokens.length <= 3;
  }

  String _buildDuplicateProbeText(
    _ProductDraft draft, {
    AIProductImageAnalysis? aiImageAnalysis,
  }) {
    final parts = <String>[
      draft.nameController.text.trim(),
      draft.descriptionController.text.trim(),
      draft.selectedCategory?.name ?? '',
      draft.selectedBrand?.name ?? '',
      _normalizeFileNameHint(draft.imageFileName),
    ];

    if (aiImageAnalysis != null) {
      if (aiImageAnalysis.primaryType.isNotEmpty) {
        parts.add('imagen ${aiImageAnalysis.primaryType}');
      }
      if (aiImageAnalysis.catalogTerms.isNotEmpty) {
        parts.add(aiImageAnalysis.catalogTerms.join(' '));
      }
      if (aiImageAnalysis.textConflict &&
          aiImageAnalysis.primaryType.isNotEmpty) {
        parts.add('priorizar foto ${aiImageAnalysis.primaryType}');
      }
    }

    if (draft.price != null && draft.price! > 0) {
      parts.add('precio ${draft.price!.toStringAsFixed(0)}');
    }
    if (draft.cost > 0) {
      parts.add('costo ${draft.cost.toStringAsFixed(0)}');
    }

    return parts.where((part) => part.trim().isNotEmpty).join(' ');
  }

  String _normalizeFileNameHint(String? fileName) {
    if (fileName == null || fileName.trim().isEmpty) return '';
    final normalized = fileName
        .replaceAll(RegExp(r'\.[^.]+$'), '')
        .replaceAll(RegExp(r'[_\-]+'), ' ');
    return normalized;
  }

  String _normalizeSimilarityText(String text) {
    const accents = {
      'á': 'a',
      'à': 'a',
      'ä': 'a',
      'â': 'a',
      'é': 'e',
      'è': 'e',
      'ë': 'e',
      'ê': 'e',
      'í': 'i',
      'ì': 'i',
      'ï': 'i',
      'î': 'i',
      'ó': 'o',
      'ò': 'o',
      'ö': 'o',
      'ô': 'o',
      'ú': 'u',
      'ù': 'u',
      'ü': 'u',
      'û': 'u',
      'ñ': 'n',
    };

    var normalized = text.trim().toLowerCase();
    accents.forEach((from, to) {
      normalized = normalized.replaceAll(from, to);
    });

    return normalized.replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
  }

  Set<String> _extractSimilarityTokens(String text) {
    return _normalizeSimilarityText(text).split(RegExp(r'\s+')).where((token) {
      if (token.isEmpty) return false;
      if (_duplicateStopWords.contains(token)) return false;
      if (token.length == 1) return false;
      return true;
    }).toSet();
  }

  /// Expand a token set with synonym equivalents.
  /// If tokens contain "cambio", adds "desviador", "derailleur", etc.
  Set<String> _expandWithSynonyms(Set<String> tokens) {
    final expanded = Set<String>.of(tokens);
    for (final group in _bikeSynonymGroups) {
      if (tokens.any(group.contains)) {
        expanded.addAll(group);
      }
    }
    return expanded;
  }

  double _computeKeywordScore(
    _ProductDraft draft,
    Product product,
    Set<String> probeTokens,
    String normalizedName,
  ) {
    final productText = _buildProductSimilarityText(product);

    final productTokens =
        _expandWithSynonyms(_extractSimilarityTokens(productText));
    final expandedProbe = _expandWithSynonyms(probeTokens);
    final tokenScore = _tokenOverlapScore(expandedProbe, productTokens);
    final nameScore = _stringContainmentScore(
      normalizedName,
      _normalizeSimilarityText(product.name),
    );

    return math.max(tokenScore, nameScore).clamp(0, 1);
  }

  String _buildProductSimilarityText(Product product) {
    return [
      product.name,
      product.description ?? '',
      product.brand ?? '',
      product.categoryName ?? '',
      product.model ?? '',
      product.manufacturer ?? '',
      product.manufacturerSku ?? '',
      product.supplierCode ?? '',
      product.supplierReference ?? '',
      product.tags.join(' '),
    ].join(' ');
  }

  /// Extract identity-specific terms from AI analysis (brand, model, series)
  /// by filtering out generic category words. Returns normalized tokens.
  Set<String> _extractAiIdentityTerms(AIProductImageAnalysis? analysis) {
    if (analysis == null) return const {};

    final allTerms = _extractSimilarityTokens(
      [analysis.primaryType, ...analysis.catalogTerms].join(' '),
    );

    // Remove generic category tokens — what remains are identity markers
    // like "shimano", "deore", "sram", "microshift", "m5100", "slx", etc.
    final identity = allTerms.difference(_genericCategoryTokens);

    // Remove pure numbers and broad short prefixes like "sm" that inflate
    // weak matches across many Shimano SKUs.
    identity.removeWhere(
      (t) =>
          RegExp(r'^\d+$').hasMatch(t) ||
          (t.length <= 2 && !RegExp(r'\d').hasMatch(t)),
    );

    return identity;
  }

  bool _isDimensionIdentityToken(String token) {
    return RegExp(r'^\d+(mm|cm|v|vel|sp)$').hasMatch(token);
  }

  bool _isModelIdentityToken(String token) {
    if (_isDimensionIdentityToken(token)) return false;
    return RegExp(r'^(?=.*[a-z])(?=.*\d)[a-z0-9]+$').hasMatch(token);
  }

  bool _containsFamilyToken(Set<String> tokens, Set<String> familyTokens) {
    return tokens.any(
      (token) => familyTokens.any(
        (family) => token == family || token.startsWith(family),
      ),
    );
  }

  String _classifyBrakeFamilyFromTokens(Set<String> tokens) {
    const padTokens = {
      'pastilla',
      'pastillas',
      'pad',
      'pads',
      'patin',
      'patines',
      'zapata',
      'zapatas',
    };
    const accessoryTokens = {
      'adaptador',
      'adaptadores',
      'adapter',
      'adaptor',
      'bracket',
      'mount',
      'postmount',
      'post',
    };
    const caliperTokens = {
      'caliper',
      'calipers',
      'mordaza',
      'mordazas',
    };
    const boltTokens = {
      'tornillo',
      'tornillos',
      'perno',
      'pernos',
      'bolt',
      'bolts',
    };
    const rotorTokens = {
      'rotor',
      'rotores',
      'disco',
      'discos',
    };

    if (_containsFamilyToken(tokens, padTokens)) return 'pad';
    if (_containsFamilyToken(tokens, accessoryTokens)) return 'accessory';
    if (_containsFamilyToken(tokens, caliperTokens)) return 'caliper';
    if (_containsFamilyToken(tokens, boltTokens)) return 'bolt';
    if (_containsFamilyToken(tokens, rotorTokens)) return 'rotor';
    return 'unknown';
  }

  String _classifyCandidateBrakeFamily(Product candidate) {
    final categoryTokens = _expandWithSynonyms(
      _extractSimilarityTokens(candidate.categoryName ?? ''),
    );
    final categoryFamily = _classifyBrakeFamilyFromTokens(categoryTokens);
    if (categoryFamily != 'unknown') return categoryFamily;

    final nameTokens = _expandWithSynonyms(
      _extractSimilarityTokens(candidate.name),
    );
    return _classifyBrakeFamilyFromTokens(nameTokens);
  }

  String _classifyAiBrakeFamily(AIProductImageAnalysis? analysis) {
    if (analysis == null) return 'unknown';
    final aiTokens = _expandWithSynonyms(
      _extractSimilarityTokens(
        [analysis.primaryType, ...analysis.catalogTerms].join(' '),
      ),
    );
    return _classifyBrakeFamilyFromTokens(aiTokens);
  }

  /// Compute how well a candidate matches AI-identified brand/model terms.
  /// Returns 0..1 — high when candidate name contains specific identity
  /// markers like "shimano deore" that the AI saw in the uploaded image.
  double _computeAiIdentityBoost(
    Product product,
    AIProductImageAnalysis? analysis,
  ) {
    final identityTerms = _extractAiIdentityTerms(analysis);
    if (identityTerms.isEmpty) return 0;

    // Search across name + brand + category for identity matches
    final productText = _normalizeSimilarityText(
      '${product.name} ${product.brand ?? ''} ${product.categoryName ?? ''}',
    );
    final productTokens = _extractSimilarityTokens(productText);
    if (productTokens.isEmpty) return 0;

    final modelTerms = identityTerms.where(_isModelIdentityToken).toSet();

    double tokenWeight(String token) {
      if (_isModelIdentityToken(token)) return 0.58;
      if (_isDimensionIdentityToken(token)) return 0.17;
      return 0.25;
    }

    var totalWeight = 0.0;
    var matchedWeight = 0.0;
    var matchedModelWeight = 0.0;

    for (final aiTerm in identityTerms) {
      final weight = tokenWeight(aiTerm);
      totalWeight += weight;

      if (productTokens.contains(aiTerm)) {
        matchedWeight += weight;
        if (modelTerms.contains(aiTerm)) {
          matchedModelWeight += weight;
        }
        continue;
      }

      // Allow near-miss OCR/vision reads like RT66 vs RT56, but only for
      // model-like tokens. Brand/size fuzziness inflates false positives.
      if (!modelTerms.contains(aiTerm) || aiTerm.length < 3) continue;

      for (final prodTerm in productTokens) {
        if (!_isModelIdentityToken(prodTerm) || prodTerm.length < 3) {
          continue;
        }
        if ((aiTerm.length - prodTerm.length).abs() > 1) continue;

        final editDist = _levenshteinDistance(aiTerm, prodTerm);
        if (editDist == 1) {
          final fuzzyWeight = weight * 0.55;
          matchedWeight += fuzzyWeight;
          matchedModelWeight += fuzzyWeight;
          break;
        }
        if (editDist == 2 && aiTerm.length >= 4) {
          final fuzzyWeight = weight * 0.30;
          matchedWeight += fuzzyWeight;
          matchedModelWeight += fuzzyWeight;
          break;
        }
      }
    }

    if (matchedWeight <= 0 || totalWeight <= 0) return 0;

    var score = math
        .pow(
          (matchedWeight / totalWeight).clamp(0.0, 1.0),
          0.72,
        )
        .clamp(0.0, 1.0)
        .toDouble();

    // Brand + size alone should never look like a near-identity hit when the
    // AI identified an actual model token.
    if (modelTerms.isNotEmpty && matchedModelWeight <= 0) {
      score = math.min(score, 0.38);
    }

    // ── Dimensional conflict penalty ──
    // If the AI identified a specific dimension (e.g. "180mm") and the
    // candidate product has a DIFFERENT dimension (e.g. "160mm"), penalize.
    // This prevents a 160mm rotor from outranking a 180mm rotor when the
    // AI clearly identified "180mm".
    final aiDimensions = identityTerms.where(_isDimensionIdentityToken).toSet();
    if (aiDimensions.isNotEmpty) {
      final productDimensions =
          productTokens.where(_isDimensionIdentityToken).toSet();
      if (productDimensions.isNotEmpty) {
        final hasMatchingDim =
            aiDimensions.any((d) => productDimensions.contains(d));
        final hasConflictingDim =
            productDimensions.any((d) => !aiDimensions.contains(d));
        if (!hasMatchingDim && hasConflictingDim) {
          // Product has a dimension but it's wrong (e.g. 160mm vs 180mm)
          score *= 0.55;
        }
      }
    }

    return score.clamp(0, 1).toDouble();
  }

  /// Returns a penalty multiplier (0.0–1.0) when the AI-identified product
  /// type clearly doesn't match the candidate's product category.
  ///
  /// Example: AI says "disco de freno" (rotor) but candidate is categorized
  /// as "Adaptadores" or "Pastillas" → penalty.
  /// If candidate is in "Rotores" or has no category → no penalty (1.0).
  double _computeCategoryMismatchPenalty(
    Product candidate,
    AIProductImageAnalysis? analysis,
  ) {
    if (analysis == null || analysis.primaryType.isEmpty) return 1.0;

    final candidateCategory =
        _normalizeSimilarityText(candidate.categoryName ?? '');
    if (candidateCategory.isEmpty) return 1.0; // no category → no penalty

    // Check if the AI type matches the candidate's category.
    // Use the same synonym-expanded containment that aiTypeScore uses.
    final aiTypeTokens = _expandWithSynonyms(
      _extractSimilarityTokens(analysis.primaryType),
    );
    final categoryTokens = _expandWithSynonyms(
      _extractSimilarityTokens(candidateCategory),
    );

    // If any AI type token appears in the category, it's a match.
    final hasTypeInCategory = aiTypeTokens.any(
      (t) => categoryTokens.any((c) => c.contains(t) || t.contains(c)),
    );
    if (hasTypeInCategory) return 1.0; // category matches AI type → no penalty

    // Also check the product name — some products have generic categories
    // but specific names (e.g., category "Shimano" but name "Disco freno...")
    final candidateNameTokens = _expandWithSynonyms(
      _extractSimilarityTokens(candidate.name),
    );
    final aiTypeInName = aiTypeTokens.any(
      (t) => candidateNameTokens.any((c) => c.contains(t) || t.contains(c)),
    );
    if (aiTypeInName) return 1.0; // name contains AI type → no penalty

    // Category exists, is different from AI type, and name doesn't contain
    // the AI type either → this is likely a different product family.
    return 0.88; // ~12% penalty
  }

  double _computeAccessoryMismatchPenalty(
    Product candidate,
    AIProductImageAnalysis? analysis,
  ) {
    if (analysis == null) return 1.0;

    final aiFamily = _classifyAiBrakeFamily(analysis);
    final candidateFamily = _classifyCandidateBrakeFamily(candidate);
    if (candidateFamily != 'accessory' || aiFamily == 'accessory') {
      return 1.0;
    }

    if (aiFamily == 'rotor') return 0.58;

    return 0.76;
  }

  double _computeBrakeFamilyPenalty(
    Product candidate,
    AIProductImageAnalysis? analysis,
  ) {
    if (analysis == null) return 1.0;

    final aiFamily = _classifyAiBrakeFamily(analysis);
    if (aiFamily != 'rotor') return 1.0;

    final candidateFamily = _classifyCandidateBrakeFamily(candidate);
    if (candidateFamily == 'pad') return 0.42;
    if (candidateFamily == 'caliper') return 0.56;
    if (candidateFamily == 'bolt') return 0.38;
    if (candidateFamily == 'accessory') return 0.58;

    return 1.0;
  }

  bool _passesAiCategoryGate(
    Product candidate,
    AIProductImageAnalysis? analysis, {
    required double keywordScore,
    required double identityScore,
    required double metadataScore,
  }) {
    if (analysis == null || analysis.confidence < 0.78) return true;

    final aiFamily = _classifyAiBrakeFamily(analysis);
    final candidateFamily = _classifyCandidateBrakeFamily(candidate);

    final strongOverride =
        identityScore >= 0.62 || keywordScore >= 0.90 || metadataScore >= 0.82;
    if (strongOverride) return true;

    if (aiFamily != 'rotor') return true;

    if (candidateFamily == 'pad' ||
        candidateFamily == 'accessory' ||
        candidateFamily == 'caliper' ||
        candidateFamily == 'bolt') {
      return false;
    }

    if (analysis.confidence >= 0.90) {
      return candidateFamily == 'rotor';
    }

    return true;
  }

  double _computeDimensionMismatchPenalty(
    Product candidate,
    AIProductImageAnalysis? analysis,
  ) {
    if (analysis == null) return 1.0;

    final aiDimensions = _extractAiIdentityTerms(analysis)
        .where(_isDimensionIdentityToken)
        .toSet();
    if (aiDimensions.isEmpty) return 1.0;

    final candidateTokens = _extractSimilarityTokens(
      _normalizeSimilarityText(_buildProductSimilarityText(candidate)),
    );
    final candidateDimensions =
        candidateTokens.where(_isDimensionIdentityToken).toSet();
    if (candidateDimensions.isEmpty) return 1.0;

    final hasMatchingDim = aiDimensions
        .any((dimension) => candidateDimensions.contains(dimension));
    if (hasMatchingDim) return 1.0;

    final hasConflictingDim = candidateDimensions
        .any((dimension) => !aiDimensions.contains(dimension));
    if (!hasConflictingDim) return 1.0;

    return 0.58;
  }

  double _computeAiImageTypeScore(
    Product product,
    AIProductImageAnalysis? analysis,
  ) {
    if (analysis == null) return 0;

    final productText = _buildProductSimilarityText(product);
    final productTokens =
        _expandWithSynonyms(_extractSimilarityTokens(productText));
    if (productTokens.isEmpty) return 0;

    final productNameAndCategory = _normalizeSimilarityText(
      '${product.name} ${product.categoryName ?? ''}',
    );
    final positiveTokens = _expandWithSynonyms(_extractSimilarityTokens(
      [analysis.primaryType, ...analysis.catalogTerms].join(' '),
    ));
    final negativeTokens = _extractSimilarityTokens(
      analysis.excludedTerms.join(' '),
    );

    var score = 0.0;

    if (analysis.primaryType.isNotEmpty) {
      // Expand both sides for synonym-aware containment.
      final expandedType = _expandWithSynonyms(
        _extractSimilarityTokens(analysis.primaryType),
      ).join(' ');
      final expandedNameCat = _expandWithSynonyms(
        _extractSimilarityTokens(productNameAndCategory),
      ).join(' ');
      score = math.max(
        score,
        _stringContainmentScore(expandedType, expandedNameCat),
      );
      // Also compare the original texts for exact substring matches.
      score = math.max(
        score,
        _stringContainmentScore(
          _normalizeSimilarityText(analysis.primaryType),
          productNameAndCategory,
        ),
      );
    }

    if (positiveTokens.isNotEmpty) {
      score =
          math.max(score, _tokenOverlapScore(positiveTokens, productTokens));
    }

    if (analysis.confidence >= 0.80 && score > 0) {
      score = (score + 0.08).clamp(0, 1).toDouble();
    }

    if (negativeTokens.isNotEmpty) {
      final negativeScore = _tokenOverlapScore(negativeTokens, productTokens);
      if (negativeScore >= 0.34 && score < 0.90) {
        score = math.max(0, score - negativeScore * 0.45);
      }
    }

    return score.clamp(0, 1).toDouble();
  }

  double _computeMetadataScore(_ProductDraft draft, Product product) {
    var weightedTotal = 0.0;
    var appliedWeight = 0.0;

    void addWeighted(double score, double weight) {
      weightedTotal += score * weight;
      appliedWeight += weight;
    }

    final draftCategory =
        _normalizeSimilarityText(draft.selectedCategory?.name ?? '');
    final productCategory =
        _normalizeSimilarityText(product.categoryName ?? '');
    if (draftCategory.isNotEmpty && productCategory.isNotEmpty) {
      addWeighted(
          _stringContainmentScore(draftCategory, productCategory), 0.35);
    }

    final draftBrand =
        _normalizeSimilarityText(draft.selectedBrand?.name ?? '');
    final productBrand = _normalizeSimilarityText(product.brand ?? '');
    if (draftBrand.isNotEmpty && productBrand.isNotEmpty) {
      addWeighted(_stringContainmentScore(draftBrand, productBrand), 0.30);
    }

    final draftSupplier =
        _normalizeSimilarityText(draft.selectedSupplier?.name ?? '');
    final productSupplier =
        _normalizeSimilarityText(product.supplierName ?? '');
    if (draftSupplier.isNotEmpty && productSupplier.isNotEmpty) {
      final supplierScore = draftSupplier == productSupplier
          ? 1.0
          : (_inventoryService
                      .isAliExpressSupplierName(draft.selectedSupplier?.name) &&
                  _inventoryService
                      .isAliExpressSupplierName(product.supplierName)
              ? 0.25
              : 0.0);
      addWeighted(supplierScore, 0.10);
    }

    if (draft.price != null && draft.price! > 0 && product.price > 0) {
      final ratio = math.min(draft.price!, product.price) /
          math.max(draft.price!, product.price);
      addWeighted(ratio.clamp(0, 1), 0.15);
    }

    if (draft.cost > 0 && product.cost > 0) {
      final ratio = math.min(draft.cost, product.cost) /
          math.max(draft.cost, product.cost);
      addWeighted(ratio.clamp(0, 1), 0.10);
    }

    if (appliedWeight == 0) return 0;
    return (weightedTotal / appliedWeight).clamp(0, 1);
  }

  double _tokenOverlapScore(Set<String> left, Set<String> right) {
    if (left.isEmpty || right.isEmpty) return 0;

    final shared = left.intersection(right).length.toDouble();
    if (shared == 0) return 0;

    final recall = shared / left.length;
    final precision = shared / right.length;
    return (recall * 0.72 + precision * 0.28).clamp(0, 1);
  }

  /// Levenshtein edit distance between two strings.
  static int _levenshteinDistance(String a, String b) {
    if (a == b) return 0;
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;

    // Use single-row DP for memory efficiency.
    var prev = List<int>.generate(b.length + 1, (i) => i);
    var curr = List<int>.filled(b.length + 1, 0);

    for (var i = 1; i <= a.length; i++) {
      curr[0] = i;
      for (var j = 1; j <= b.length; j++) {
        final cost = a[i - 1] == b[j - 1] ? 0 : 1;
        curr[j] = math.min(
          math.min(curr[j - 1] + 1, prev[j] + 1),
          prev[j - 1] + cost,
        );
      }
      final tmp = prev;
      prev = curr;
      curr = tmp;
    }
    return prev[b.length];
  }

  double _stringContainmentScore(String left, String right) {
    if (left.isEmpty || right.isEmpty) return 0;
    if (left == right) return 1;

    final overlap = _tokenOverlapScore(
      _extractSimilarityTokens(left),
      _extractSimilarityTokens(right),
    );

    if (left.contains(right) || right.contains(left)) {
      final shorter = math.min(left.length, right.length).toDouble();
      final longer = math.max(left.length, right.length).toDouble();
      return math.max(overlap, (0.72 + (shorter / longer) * 0.18).clamp(0, 1));
    }

    return overlap;
  }

  double _combineDuplicateScores({
    required double keywordScore,
    required double semanticScore,
    required double imageScore,
    required double aiTypeScore,
    required double identityScore,
    required double metadataScore,
  }) {
    // Fixed denominator: ALL weights always count.
    // A zero score means "no match" and should pull the score DOWN,
    // not inflate remaining signals by shrinking the denominator.
    const wAiType = 0.30;
    const wIdentity = 0.22;
    const wImage = 0.18;
    const wKeyword = 0.16;
    const wSemantic = 0.08;
    const wMeta = 0.06;

    final weightedTotal = aiTypeScore * wAiType +
        identityScore * wIdentity +
        imageScore * wImage +
        keywordScore * wKeyword +
        semanticScore * wSemantic +
        metadataScore * wMeta;

    var overall = weightedTotal.clamp(0.0, 1.0);
    final hasSupportingSignals = keywordScore > 0 ||
        semanticScore > 0 ||
        metadataScore > 0 ||
        aiTypeScore > 0 ||
        identityScore > 0;

    // AI identity + aiType synergy: when both are strong, boost floor.
    // This is the ONLY boost floor — it rewards AI-derived signal
    // corroboration, NOT pixel similarity.
    if (aiTypeScore >= 0.70 && identityScore >= 0.50) {
      final synergy = aiTypeScore * 0.50 + identityScore * 0.50;
      overall = math.max(overall, synergy);
    }

    // Text-only corroboration floor (no image involved)
    if (keywordScore >= 0.90 && metadataScore >= 0.70) {
      overall = math.max(overall, 0.86);
    }

    // Image-only cap: when image is the ONLY signal, cap very aggressively.
    // Pixel comparison on product photos is a category filter at best.
    if (imageScore > 0 && !hasSupportingSignals) {
      if (imageScore >= 0.96) {
        overall = math.min(overall, 0.50);
      } else {
        overall = math.min(overall, imageScore * 0.42);
      }
    }

    return (overall.clamp(0, 1)).toDouble();
  }

  double _adjustPreliminaryScoreForImageProbe({
    required double prelimScore,
    required bool hasImageProbe,
    required bool candidateHasImage,
    required bool sparseTextProbe,
  }) {
    if (!hasImageProbe) return prelimScore;

    if (candidateHasImage) {
      return (prelimScore + (sparseTextProbe ? 0.08 : 0.04))
          .clamp(0, 1)
          .toDouble();
    }

    final cap = sparseTextProbe ? 0.72 : 0.80;
    final penalty = sparseTextProbe ? 0.82 : 0.90;
    return math.min(prelimScore * penalty, cap).clamp(0, 1).toDouble();
  }

  double _adjustFinalScoreForImageProbe({
    required double overallScore,
    required bool hasImageProbe,
    required bool candidateHasImage,
    required double imageScore,
    required double keywordScore,
    required double metadataScore,
    required double aiTypeScore,
    required bool sparseTextProbe,
  }) {
    if (!hasImageProbe) return overallScore;

    if (!candidateHasImage) {
      final strongTextOnly = keywordScore >= 0.92 && metadataScore >= 0.70;
      final cap = strongTextOnly
          ? (sparseTextProbe ? 0.78 : 0.84)
          : (sparseTextProbe ? 0.72 : 0.80);
      final penalty = sparseTextProbe ? 0.84 : 0.92;
      return math.min(overallScore * penalty, cap).clamp(0, 1).toDouble();
    }

    var adjusted = overallScore;
    final strongestSupport =
        math.max(keywordScore, math.max(metadataScore, aiTypeScore));
    final hasAnySupportSignal = strongestSupport >= 0.15;

    // ── NO BOOST FLOORS ──
    // The weighted scoring in _combineDuplicateScores already ranks
    // candidates correctly. Boost floors that use imageScore destroy
    // that ranking because pixel hashes are noise within the same
    // product category (adapter ≈ rotor ≈ pads ≈ bolts at 80-87%).
    // Only caps and penalties are applied here.

    // ── Hard cap: no non-image support at all → image hash is unreliable ──
    if (!hasAnySupportSignal) {
      if (imageScore >= 0.96) {
        adjusted = math.min(adjusted, 0.52);
      } else if (imageScore >= 0.90) {
        adjusted = math.min(adjusted, imageScore * 0.50);
      } else {
        adjusted = math.min(adjusted, imageScore * 0.42);
      }
    }

    final weakSupportingSignals =
        keywordScore < 0.18 && metadataScore < 0.18 && aiTypeScore < 0.22;
    if (sparseTextProbe && weakSupportingSignals) {
      if (imageScore < 0.74) {
        adjusted = math.min(adjusted, imageScore * 0.55);
      } else {
        adjusted = math.min(adjusted, imageScore * 0.65);
      }
    }

    // Hard cap: sparse text probe + no AI type match → image alone is unreliable
    if (sparseTextProbe && imageScore >= 0.70 && aiTypeScore < 0.12) {
      adjusted = math.min(adjusted, imageScore * 0.52);
    }

    return adjusted.clamp(0, 1).toDouble();
  }

  bool _shouldKeepDuplicateCandidate(_PotentialDuplicateCandidate candidate) {
    final hasNonImageSupport = candidate.aiTypeScore >= 0.18 ||
        candidate.keywordScore >= 0.20 ||
        candidate.semanticScore >= 0.15 ||
        candidate.metadataScore >= 0.15 ||
        candidate.identityScore >= 0.15;

    // Image-only candidates (no AI, no text, no identity match) are almost
    // always false positives — pixel hashes can't distinguish product types.
    // Only keep them if image is near-identical AND Gemini is off.
    if (!hasNonImageSupport && candidate.imageScore > 0) {
      return candidate.imageScore >= 0.96;
    }

    // Without AI and without text/metadata support, image alone is unreliable
    // due to coarse hash inflation on white-background product photos.
    if (!_isGeminiConfigured && !hasNonImageSupport) {
      return candidate.imageScore >= 0.88;
    }

    if (candidate.overallScore >= 0.56) return true;
    if (candidate.imageScore >= 0.90 && hasNonImageSupport) {
      return true;
    }
    if (candidate.keywordScore >= 0.88 && candidate.metadataScore >= 0.60) {
      return true;
    }
    if (candidate.semanticScore >= 0.80 && candidate.keywordScore >= 0.55) {
      return true;
    }
    return false;
  }

  List<String> _buildDuplicateSignals(
    Product product, {
    required double keywordScore,
    required double semanticScore,
    required double imageScore,
    required double aiTypeScore,
    required double identityScore,
    required double metadataScore,
    String? aiPrimaryType,
  }) {
    final signals = <String>[];

    if (imageScore >= 0.90) signals.add('Imagen casi igual');
    if (keywordScore >= 0.86) signals.add('Nombre muy parecido');
    if (semanticScore >= 0.78) signals.add('Coincidencia IA fuerte');
    if (aiTypeScore >= 0.72 &&
        aiPrimaryType != null &&
        aiPrimaryType.isNotEmpty) {
      signals.add('Vision IA: $aiPrimaryType');
    }
    if (identityScore >= 0.50) signals.add('Marca/modelo coincide');
    if (metadataScore >= 0.78) signals.add('Marca/categoría alineadas');
    if (signals.isEmpty && metadataScore >= 0.55) {
      signals.add('Metadatos compatibles');
    }

    if (product.inventoryQty > 0) {
      signals.add('Stock: ${product.inventoryQty}');
    }

    return signals;
  }

  Future<double> _computeProductImageSimilarity(
    Product product,
    ProductImageFingerprint draftFingerprint,
  ) async {
    final candidateFingerprint = await _getProductImageHash(product);
    if (candidateFingerprint == null) return 0;

    return ProductImageFingerprintService.similarity(
      draftFingerprint,
      candidateFingerprint,
    );
  }

  Future<double> _computeVerifiedProductImageSimilarity(
    Product product,
    ProductImageFingerprint draftFingerprint, {
    Uint8List? draftImageBytes,
  }) async {
    final coarseScore = await _computeProductImageSimilarity(
      product,
      draftFingerprint,
    );
    if (coarseScore <= 0 ||
        draftImageBytes == null ||
        draftImageBytes.isEmpty) {
      return coarseScore;
    }

    // Lower cutoff so more candidates reach the much-better detailed check
    if (coarseScore < 0.45) {
      return coarseScore;
    }

    final candidateImageBytes = await _getProductImageBytes(product);
    if (candidateImageBytes == null || candidateImageBytes.isEmpty) {
      // If we can't download candidate image, don't trust the coarse score
      return (coarseScore * 0.55).clamp(0, 1).toDouble();
    }

    final detailedScore =
        ProductImageFingerprintService.detailedSimilarityFromBytes(
      draftImageBytes,
      candidateImageBytes,
    );
    if (detailedScore <= 0) {
      return (coarseScore * 0.50).clamp(0, 1).toDouble();
    }

    // Detailed (18×18 grid) is vastly more accurate than coarse (8×8 hash).
    // Let detailed score dominate the blend.
    var refinedScore = detailedScore * 0.92 + coarseScore * 0.08;
    if (detailedScore < 0.50) {
      refinedScore = math.min(refinedScore, detailedScore + 0.03);
    }

    return refinedScore.clamp(0, 1).toDouble();
  }

  Future<ProductImageFingerprint?> _getProductImageHash(Product product) async {
    final imageUrl = _productPreviewUrl(product);

    if (imageUrl != null && imageUrl.isNotEmpty) {
      if (_productImageHashCache.containsKey(imageUrl)) {
        return _productImageHashCache[imageUrl];
      }

      final storedFingerprint = ProductImageFingerprint.fromStorageJson(
        product.imageFingerprint,
      );
      if (storedFingerprint != null) {
        _productImageHashCache[imageUrl] = storedFingerprint;
        return storedFingerprint;
      }
    }

    if (imageUrl == null || imageUrl.isEmpty) return null;

    try {
      final response = await http.get(Uri.parse(imageUrl));
      if (response.statusCode != 200) {
        _productImageHashCache[imageUrl] = null;
        return null;
      }

      final fingerprint = ProductImageFingerprintService.fromBytes(
        response.bodyBytes,
      );
      _productImageHashCache[imageUrl] = fingerprint;
      if (fingerprint != null) {
        unawaited(
          _inventoryService.storeProductImageFingerprint(
            productId: product.id!,
            imageFingerprint: fingerprint.toStorageJson(),
          ),
        );
      }
      return fingerprint;
    } catch (e) {
      debugPrint(
          'BulkCreate: failed to fetch candidate image for similarity: $e');
      _productImageHashCache[imageUrl] = null;
      return null;
    }
  }

  Future<Uint8List?> _getProductImageBytes(Product product) async {
    final imageUrl = _productPreviewUrl(product);
    if (imageUrl == null || imageUrl.isEmpty) return null;

    if (_productImageBytesCache.containsKey(imageUrl)) {
      return _productImageBytesCache[imageUrl];
    }

    try {
      final response = await http.get(Uri.parse(imageUrl));
      if (response.statusCode != 200 || response.bodyBytes.isEmpty) {
        _productImageBytesCache[imageUrl] = null;
        return null;
      }

      _productImageBytesCache[imageUrl] = response.bodyBytes;
      return response.bodyBytes;
    } catch (e) {
      debugPrint(
        'BulkCreate: failed to fetch candidate image bytes for verification: $e',
      );
      _productImageBytesCache[imageUrl] = null;
      return null;
    }
  }

  String? _productPreviewUrl(Product product) {
    if (product.imageUrlOptimized != null &&
        product.imageUrlOptimized!.trim().isNotEmpty) {
      return product.imageUrlOptimized;
    }
    if (product.imageUrl != null && product.imageUrl!.trim().isNotEmpty) {
      return product.imageUrl;
    }
    if (product.additionalImages.isNotEmpty) {
      return product.additionalImages.first;
    }
    return null;
  }

  bool _productHasPreviewImage(Product product) {
    return (_productPreviewUrl(product)?.trim().isNotEmpty ?? false);
  }

  Future<void> _showDuplicateReviewDialog(List<_ProductDraft> rows) async {
    if (!mounted) return;

    final flaggedRows =
        rows.where((draft) => draft.hasPotentialDuplicates).toList();
    if (flaggedRows.isEmpty) return;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final theme = Theme.of(dialogContext);
        final screenSize = MediaQuery.of(dialogContext).size;

        return Dialog(
          clipBehavior: Clip.antiAlias,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: SizedBox(
            width: math.min(screenSize.width * 0.82, 1100),
            height: math.min(screenSize.height * 0.82, 760),
            child: Column(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    border: Border(
                      bottom: BorderSide(
                        color: theme.colorScheme.outlineVariant
                            .withValues(alpha: 0.3),
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.find_in_page_outlined,
                          color: theme.colorScheme.primary),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Revisión de parecidos',
                              style: theme.textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            Text(
                              _isGeminiConfigured
                                  ? '${flaggedRows.length} fila(s) con señales fuertes. No bloquea creación: sólo te da los mejores candidatos.'
                                  : '${flaggedRows.length} fila(s) con señales fuertes. Vision IA no configurada: se muestran solo coincidencias locales muy fuertes.',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(dialogContext).pop(),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: flaggedRows.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 14),
                    itemBuilder: (context, index) {
                      final draft = flaggedRows[index];
                      return _buildDuplicateReviewCard(theme, draft, index + 1);
                    },
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    border: Border(
                      top: BorderSide(
                        color: theme.colorScheme.outlineVariant
                            .withValues(alpha: 0.3),
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      Text(
                        'Las filas marcadas siguen siendo editables. Si una te convence como duplicado, simplemente desmárcala en la tabla.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const Spacer(),
                      FilledButton.tonal(
                        onPressed: () => Navigator.of(dialogContext).pop(),
                        child: const Text('Volver a la tabla'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildDuplicateReviewCard(
    ThemeData theme,
    _ProductDraft draft,
    int reviewIndex,
  ) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Colors.orange.shade100,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: 58,
                  height: 58,
                  child: draft.imageUrl != null
                      ? ImageService.buildProductImage(
                          imageUrl: draft.imageUrl,
                          size: 58,
                        )
                      : Container(
                          color: theme.colorScheme.surfaceContainerHighest,
                          child: Icon(
                            Icons.inventory_2_outlined,
                            color: theme.colorScheme.onSurfaceVariant,
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
                      'Fila ${_rows.indexOf(draft) + 1}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      draft.nameController.text.trim().isEmpty
                          ? 'Producto sin nombre'
                          : draft.nameController.text.trim(),
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        if (draft.sku.isNotEmpty)
                          _buildMetricChip(theme, draft.sku, tone: 'neutral'),
                        if ((draft.selectedCategory?.name ?? '').isNotEmpty)
                          _buildMetricChip(
                            theme,
                            draft.selectedCategory!.name,
                            tone: 'neutral',
                          ),
                        if ((draft.selectedBrand?.name ?? '').isNotEmpty)
                          _buildMetricChip(
                            theme,
                            draft.selectedBrand!.name,
                            tone: 'neutral',
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '${draft.duplicateCandidates.length} candidato${draft.duplicateCandidates.length == 1 ? '' : 's'}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Colors.orange.shade700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...draft.duplicateCandidates.map(
            (candidate) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _buildDuplicateCandidateTile(theme, candidate),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDuplicateCandidateTile(
    ThemeData theme,
    _PotentialDuplicateCandidate candidate,
  ) {
    final product = candidate.product;
    final scorePercent = (candidate.overallScore * 100).round();

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: 52,
              height: 52,
              child: ImageService.buildProductImage(
                imageUrl: _productPreviewUrl(product),
                size: 52,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            product.name,
                            style: theme.textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${product.sku} · ${product.brand ?? 'Sin marca'} · ${product.categoryName ?? 'Sin categoría'}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '$scorePercent%',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: candidate.overallScore >= 0.8
                                ? Colors.orange.shade700
                                : theme.colorScheme.primary,
                          ),
                        ),
                        Text(
                          'score total',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                LinearProgressIndicator(
                  value: candidate.overallScore,
                  minHeight: 6,
                  borderRadius: BorderRadius.circular(999),
                  backgroundColor: theme.colorScheme.surfaceContainerHighest
                      .withValues(alpha: 0.4),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    if (candidate.keywordScore > 0)
                      _buildMetricChip(
                        theme,
                        'Texto ${(candidate.keywordScore * 100).round()}%',
                      ),
                    if (candidate.semanticScore > 0)
                      _buildMetricChip(
                        theme,
                        'IA ${(candidate.semanticScore * 100).round()}%',
                        tone: 'primary',
                      ),
                    if (candidate.aiTypeScore > 0)
                      _buildMetricChip(
                        theme,
                        'Vision ${(candidate.aiTypeScore * 100).round()}%',
                        tone: candidate.aiTypeScore >= 0.75
                            ? 'warning'
                            : 'primary',
                      ),
                    if (candidate.identityScore > 0)
                      _buildMetricChip(
                        theme,
                        'ID ${(candidate.identityScore * 100).round()}%',
                        tone: candidate.identityScore >= 0.60
                            ? 'warning'
                            : 'primary',
                      ),
                    if (candidate.imageScore > 0)
                      _buildMetricChip(
                        theme,
                        'Imagen ${(candidate.imageScore * 100).round()}%',
                        tone:
                            candidate.imageScore >= 0.9 ? 'warning' : 'primary',
                      ),
                    if (!candidate.hasProductImage)
                      _buildMetricChip(
                        theme,
                        'Sin imagen',
                        tone: 'neutral',
                      ),
                    if (candidate.metadataScore > 0)
                      _buildMetricChip(
                        theme,
                        'Meta ${(candidate.metadataScore * 100).round()}%',
                      ),
                    if (product.price > 0)
                      _buildMetricChip(
                        theme,
                        '\$${product.price.toStringAsFixed(0)}',
                        tone: 'neutral',
                      ),
                  ],
                ),
                if (candidate.signals.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: candidate.signals
                        .map((signal) => _buildMetricChip(
                              theme,
                              signal,
                              tone: 'soft',
                            ))
                        .toList(growable: false),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricChip(
    ThemeData theme,
    String label, {
    String tone = 'default',
  }) {
    Color background;
    Color foreground;

    switch (tone) {
      case 'primary':
        background = theme.colorScheme.primaryContainer.withValues(alpha: 0.45);
        foreground = theme.colorScheme.primary;
        break;
      case 'warning':
        background = Colors.orange.shade50;
        foreground = Colors.orange.shade700;
        break;
      case 'soft':
        background =
            theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5);
        foreground = theme.colorScheme.onSurfaceVariant;
        break;
      case 'neutral':
        background =
            theme.colorScheme.surfaceContainerHigh.withValues(alpha: 0.4);
        foreground = theme.colorScheme.onSurfaceVariant;
        break;
      default:
        background = theme.colorScheme.surfaceContainerLow;
        foreground = theme.colorScheme.onSurfaceVariant;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: foreground,
        ),
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
            color: Colors.orange.shade700,
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
          color: Colors.green.shade600,
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

      for (final draft in selectedRows) {
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
        } catch (e) {
          debugPrint('❌ Failed to create product "${product.name}": $e');
          failed.add(draft.nameController.text.trim());
        }
      }

      // Refresh shared cache
      if (created > 0) {
        Provider.of<inv_service.InventoryService>(context, listen: false)
            .invalidateProductsCache();
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
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '$duplicateWarningCount con parecidos',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Colors.orange.shade700,
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
            color: _resultIsError ? Colors.red.shade50 : Colors.green.shade50,
            child: Row(
              children: [
                Icon(
                  _resultIsError ? Icons.error_outline : Icons.check_circle,
                  color: _resultIsError
                      ? Colors.red.shade700
                      : Colors.green.shade700,
                  size: 18,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _resultMessage!,
                    style: TextStyle(
                      color: _resultIsError
                          ? Colors.red.shade800
                          : Colors.green.shade800,
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
                ? Colors.orange.shade50
                : draft.hasCheckedDuplicates &&
                        draft.duplicateCheckError == null
                    ? Colors.green.shade50.withValues(alpha: 0.45)
                    : draft.isSelected
                        ? (isEven
                            ? theme.colorScheme.surface
                            : theme.colorScheme.surfaceContainerLowest)
                        : Colors.grey.shade50.withValues(alpha: 0.5);

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
                                _resetAiImageAnalysis(draft);
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
                                  color: Colors.red.shade400,
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
                      size: 16, color: Colors.red.shade300),
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
                size: 14, color: Colors.orange.shade600),
            const SizedBox(width: 5),
            Text(
              '$invalidCount incompleta(s)',
              style: TextStyle(
                fontSize: 11,
                color: Colors.orange.shade700,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '· nombre y precio requeridos',
              style: TextStyle(
                fontSize: 11,
                color: Colors.orange.shade400,
              ),
            ),
            if (duplicateWarningCount > 0) ...[
              const SizedBox(width: 10),
              Text(
                '· $duplicateWarningCount con parecidos',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.orange.shade700,
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
              color: Colors.grey.shade300,
            ),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(5),
            borderSide: BorderSide(
              color: Colors.grey.shade300,
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
            color: Colors.grey.shade500,
          ),
          suffixIcon: suffixIcon != null
              ? Padding(
                  padding: const EdgeInsets.all(10),
                  child: suffixIcon,
                )
              : null,
          errorText: errorText,
          errorStyle: const TextStyle(fontSize: 9, height: 0.8),
          hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 11),
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
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(5),
            borderSide: BorderSide(color: Colors.grey.shade300),
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
