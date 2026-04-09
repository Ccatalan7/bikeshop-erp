import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../shared/constants/storage_constants.dart';
import '../../../shared/services/image_service.dart';
import '../../../shared/services/inventory_service.dart' as shared_inventory;
import '../../../shared/services/tenant_service.dart';
import '../../../shared/services/error_reporting_service.dart';
import '../../../shared/utils/chilean_utils.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/branded_loading.dart';
import '../../../shared/widgets/main_layout.dart';
import '../../../shared/models/supplier.dart';
import '../../purchases/services/purchase_service.dart';
import '../models/category_models.dart' as category_models;
import '../models/brand_models.dart';
import '../models/inventory_models.dart';
import '../../../shared/models/product.dart' show PurchaseTreatment, SetType;
import '../services/category_service.dart';
import '../services/brand_service.dart';
import '../services/inventory_service.dart' as inventory_services;
import '../widgets/set_configuration_widget.dart';
import '../../../shared/services/barcode_scanner_service.dart';
import '../services/spec_engine_service.dart';

class ProductFormPage extends StatefulWidget {
  final String? productId;
  final bool showInDialog; // Hide MainLayout when true

  const ProductFormPage({super.key, this.productId, this.showInDialog = false});

  @override
  State<ProductFormPage> createState() => _ProductFormPageState();
}

class _RestoreProductConversionOptions {
  const _RestoreProductConversionOptions({
    required this.reason,
    required this.restoreInventory,
  });

  final String reason;
  final bool restoreInventory;
}

class _StockAdjustmentReasonOption {
  const _StockAdjustmentReasonOption({
    required this.key,
    required this.label,
    required this.description,
  });

  final String key;
  final String label;
  final String description;
}

class _StockAdjustmentDialogResult {
  const _StockAdjustmentDialogResult({
    required this.quantity,
    required this.type,
    required this.reasonType,
    required this.note,
    required this.effectiveAt,
  });

  final int quantity;
  final String type;
  final String reasonType;
  final String note;
  final DateTime effectiveAt;
}

const List<_StockAdjustmentReasonOption> _stockAdjustmentReasonOptions = [
  _StockAdjustmentReasonOption(
    key: 'count',
    label: 'Reconteo / reevaluación',
    description: 'Regulariza diferencias detectadas al contar o revisar stock.',
  ),
  _StockAdjustmentReasonOption(
    key: 'loss',
    label: 'Merma',
    description: 'Baja por merma, vencimiento o deterioro no recuperable.',
  ),
  _StockAdjustmentReasonOption(
    key: 'damage',
    label: 'Daño',
    description: 'Baja por producto roto, defectuoso o inutilizable.',
  ),
  _StockAdjustmentReasonOption(
    key: 'theft',
    label: 'Robo / extravío',
    description: 'Baja por robo, pérdida o faltante no localizado.',
  ),
  _StockAdjustmentReasonOption(
    key: 'internal_use',
    label: 'Uso interno / taller',
    description: 'Consumo interno de inventario para operaciones del taller.',
  ),
  _StockAdjustmentReasonOption(
    key: 'found',
    label: 'Hallazgo / recuperación',
    description: 'Alta por unidades recuperadas o detectadas físicamente.',
  ),
  _StockAdjustmentReasonOption(
    key: 'manual',
    label: 'Otro ajuste manual',
    description: 'Uso excepcional cuando ninguna razón estructurada aplica.',
  ),
];

class _ProductFormPageState extends State<ProductFormPage>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();

  late inventory_services.InventoryService _inventoryService;
  late CategoryService _categoryService;
  late PurchaseService _purchaseService;
  late BrandService _brandService;

  final _nameController = TextEditingController();
  final _skuController = TextEditingController();
  final _supplierCodeController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _websiteDescriptionController = TextEditingController();
  final _brandController = TextEditingController();
  final _modelController = TextEditingController();
  final _priceController = TextEditingController();
  final _costController = TextEditingController();
  final _inventoryQtyController = TextEditingController();
  final _minStockController = TextEditingController();

  String? _selectedCategoryId;
  String? _selectedSupplierId;
  List<category_models.Category> _categories = [];
  List<Supplier> _suppliers = [];
  List<ProductBrand> _brands = [];
  bool _isLoadingBrands = false;
  String? _selectedBrandId;
  ProductBrand? _selectedBrand;
  bool _isActive = true;
  bool _isPublished = true;
  bool _isGoogleMerchant = false;
  ProductType _selectedProductType = ProductType.product;
  PurchaseTreatment _selectedPurchaseTreatment = PurchaseTreatment.inventory;

  // SET CONFIGURATION STATE
  bool _isSet = false;
  SetType? _setType;
  List<SetComponentDraft> _setComponents = [];

  String? _imageUrl;
  String? _imageUrlOptimized; // Optimized WebP version for fast web loading
  // --- ARCHITECTURAL FIX ---
  // Do not store XFile in state. Store only pure, platform-agnostic data.
  Uint8List? _selectedImageBytes;
  String? _selectedImageName;
  final List<String> _additionalImages = [];
  bool _isUploadingGalleryImage = false;

  bool _isLoading = false;
  bool _isSaving = false;
  bool _isApplyingStockAdjustment = false;
  bool _isGeneratingSku = false;
  bool _isLoadingConversionStatus = false;
  bool _isRestoringConversion = false;
  Product? _existingProduct;
  Map<String, dynamic>? _conversionStatus;

  // Debug error tracking
  String? _lastError;
  String? _lastStackTrace;

  StreamSubscription? _scanSubscription;

  // ── Ficha Técnica (Spec Engine) ──────────────────────────────────────────
  SpecTemplate? _specTemplate;
  Map<String, dynamic> _specValues = {};
  bool _isLoadingSpecs = false;

  late TabController _tabController;
  int _prevTabIndex = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() => _prevTabIndex = _tabController.index);
      }
    });
    _inventoryService = Provider.of<inventory_services.InventoryService>(
        context,
        listen: false);
    _categoryService = Provider.of<CategoryService>(context, listen: false);
    _purchaseService = Provider.of<PurchaseService>(context, listen: false);
    _brandService = Provider.of<BrandService>(context, listen: false);

    _inventoryQtyController.text = '0';
    _minStockController.text = '1';

    _priceController.addListener(_onPricingChanged);
    _costController.addListener(_onPricingChanged);

    _loadBrands();
    _loadCategories();
    _loadSuppliers();

    if (widget.productId != null) {
      _loadProduct();
    }

    // Listen for unified barcode scans
    _scanSubscription =
        context.read<BarcodeScannerService>().barcodeStream.listen((barcode) {
      if (mounted && ModalRoute.of(context)!.isCurrent) {
        _handleBarcodeScan(barcode);
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _scanSubscription?.cancel();
    _nameController.dispose();
    _skuController.dispose();
    _supplierCodeController.dispose();
    _descriptionController.dispose();
    _websiteDescriptionController.dispose();
    _brandController.dispose();
    _modelController.dispose();
    _priceController
      ..removeListener(_onPricingChanged)
      ..dispose();
    _costController
      ..removeListener(_onPricingChanged)
      ..dispose();
    _inventoryQtyController.dispose();
    _minStockController.dispose();
    super.dispose();
  }

  void _handleBarcodeScan(String barcode) {
    setState(() {
      _skuController.text = barcode;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('✅ SKU escaneado: $barcode'),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 1),
      ),
    );
  }

  void _onPricingChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadCategories() async {
    try {
      final categories = await _categoryService.getCategories(activeOnly: true);
      if (mounted) {
        setState(() {
          _categories = categories;

          // Validate that selected category exists in loaded categories
          if (_selectedCategoryId != null) {
            final categoryExists =
                _categories.any((c) => c.id == _selectedCategoryId);
            if (!categoryExists) {
              // Category doesn't exist, reset to first available or null
              _selectedCategoryId =
                  _categories.isNotEmpty ? _categories.first.id : null;
              if (kDebugMode) {
                print(
                    'Warning: Product category not found, reset to: ${_categories.firstOrNull?.fullPath}');
              }
            }
          }
        });
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error cargando categorías: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _showCategorySearchDialog(BuildContext context) async {
    final result = await showDialog<category_models.Category>(
      context: context,
      builder: (context) => _CategorySearchDialog(categories: _categories),
    );

    if (result != null) {
      setState(() => _selectedCategoryId = result.id);
    }
  }

  Future<void> _loadSuppliers() async {
    try {
      final suppliers = await _purchaseService.getSuppliers(activeOnly: true);
      if (mounted) {
        setState(() => _suppliers = suppliers);
        unawaited(_maybeAutoGenerateSupplierSku());
      }
    } catch (e) {
      // Suppliers are optional, silently fail
      if (!mounted) return;
    }
  }

  Supplier? get _selectedSupplier {
    final selectedSupplierId = _selectedSupplierId;
    if (selectedSupplierId == null || selectedSupplierId.isEmpty) {
      return null;
    }

    for (final supplier in _suppliers) {
      if (supplier.id == selectedSupplierId) {
        return supplier;
      }
    }

    return null;
  }

  bool get _usesAliExpressSkuSequence =>
      _inventoryService.isAliExpressSupplierName(_selectedSupplier?.name);

  Future<void> _loadBrands() async {
    if (!mounted) return;
    setState(() => _isLoadingBrands = true);
    try {
      final brands = await _brandService.getBrands();
      if (!mounted) return;
      final matched = _matchBrandSelection(brands);
      setState(() {
        _brands = brands;
        _selectedBrand = matched;
        if (matched != null) {
          _selectedBrandId = matched.id;
          _brandController.text = matched.name;
        }
        _isLoadingBrands = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoadingBrands = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error cargando marcas: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _ensureBrandsLoaded() async {
    if (_brands.isEmpty && !_isLoadingBrands) {
      await _loadBrands();
    }
  }

  ProductBrand? _matchBrandSelection([List<ProductBrand>? source]) {
    final list = source ?? _brands;
    if (_selectedBrandId != null) {
      for (final brand in list) {
        if (brand.id == _selectedBrandId) {
          return brand;
        }
      }
    }

    final text = _brandController.text.trim();
    if (text.isNotEmpty) {
      final needle = text.toLowerCase();
      for (final brand in list) {
        if (brand.name.toLowerCase() == needle) {
          return brand;
        }
      }
    }

    return null;
  }

  void _syncBrandSelection() {
    if (!mounted) return;
    final matched = _matchBrandSelection();
    setState(() {
      _selectedBrand = matched;
      if (matched != null) {
        _selectedBrandId = matched.id;
        _brandController.text = matched.name;
      }
    });
  }

  Future<void> _openBrandPicker() async {
    await _ensureBrandsLoaded();
    if (!mounted) return;

    final searchController = TextEditingController();
    bool includeInactive = false;

    List<ProductBrand> applyFilter() {
      final query = searchController.text.trim().toLowerCase();
      final filtered = _brands.where((brand) {
        if (!includeInactive && !brand.isActive) return false;
        if (query.isEmpty) return true;
        final description = brand.description ?? '';
        final website = brand.website ?? '';
        final country = brand.country ?? '';
        return brand.name.toLowerCase().contains(query) ||
            description.toLowerCase().contains(query) ||
            website.toLowerCase().contains(query) ||
            country.toLowerCase().contains(query);
      }).toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      return filtered;
    }

    var filteredBrands = applyFilter();

    final result = await showModalBottomSheet<dynamic>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom,
            ),
            child: DraggableScrollableSheet(
              expand: false,
              initialChildSize: 0.85,
              minChildSize: 0.5,
              maxChildSize: 0.95,
              builder: (context, scrollController) {
                return StatefulBuilder(
                  builder: (context, setModalState) {
                    void refresh() {
                      setModalState(() {
                        filteredBrands = applyFilter();
                      });
                    }

                    return Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          child: Row(
                            children: [
                              const Expanded(
                                child: Text(
                                  'Selecciona una marca',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.close),
                                onPressed: () => Navigator.of(context).pop(),
                              ),
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                          ),
                          child: TextField(
                            controller: searchController,
                            decoration: const InputDecoration(
                              labelText: 'Buscar marcas...',
                              prefixIcon: Icon(Icons.search),
                              border: OutlineInputBorder(),
                            ),
                            onChanged: (_) => refresh(),
                          ),
                        ),
                        SwitchListTile.adaptive(
                          title: const Text('Incluir marcas inactivas'),
                          value: includeInactive,
                          onChanged: (value) {
                            includeInactive = value;
                            refresh();
                          },
                        ),
                        ListTile(
                          leading: const Icon(Icons.add_circle_outline),
                          title: const Text('Crear nueva marca'),
                          onTap: () => Navigator.of(context).pop('_create'),
                        ),
                        ListTile(
                          leading: const Icon(Icons.clear),
                          title: const Text('Sin marca'),
                          onTap: () => Navigator.of(context).pop('_clear'),
                        ),
                        const Divider(height: 1),
                        Expanded(
                          child: filteredBrands.isEmpty
                              ? const Center(
                                  child: Text('No se encontraron marcas'),
                                )
                              : ListView.builder(
                                  controller: scrollController,
                                  itemCount: filteredBrands.length,
                                  itemBuilder: (context, index) {
                                    final brand = filteredBrands[index];
                                    final isSelected =
                                        brand.id == _selectedBrandId;
                                    return ListTile(
                                      leading: Icon(
                                        Icons.workspace_premium_outlined,
                                        color: isSelected
                                            ? Theme.of(context)
                                                .colorScheme
                                                .primary
                                            : null,
                                      ),
                                      title: Text(brand.name),
                                      subtitle: Text(
                                        [
                                          if (brand.country != null &&
                                              brand.country!.isNotEmpty)
                                            brand.country!,
                                          if (brand.website != null &&
                                              brand.website!.isNotEmpty)
                                            brand.website!,
                                        ].join(' • '),
                                      ),
                                      trailing: brand.isActive
                                          ? null
                                          : const Chip(
                                              label: Text('Inactiva'),
                                              avatar: Icon(
                                                Icons.pause_circle_outline,
                                                size: 16,
                                              ),
                                            ),
                                      onTap: () =>
                                          Navigator.of(context).pop(brand),
                                    );
                                  },
                                ),
                        ),
                      ],
                    );
                  },
                );
              },
            ),
          ),
        );
      },
    );

    searchController.dispose();

    if (!mounted) return;

    if (result == '_create') {
      await context.push('/inventory/brands/new');
      if (!mounted) return;
      await _loadBrands();
      await _openBrandPicker();
      return;
    }

    if (result == '_clear') {
      setState(() {
        _selectedBrand = null;
        _selectedBrandId = null;
        _brandController.clear();
      });
      return;
    }

    if (result is ProductBrand) {
      setState(() {
        _selectedBrand = result;
        _selectedBrandId = result.id;
        _brandController.text = result.name;
      });
    }
  }

  Future<void> _loadProduct() async {
    setState(() => _isLoading = true);
    try {
      final product = await _inventoryService.getProductById(widget.productId!);
      if (product != null) {
        _existingProduct = product;
        _nameController.text = product.name;
        _skuController.text = product.sku;
        _supplierCodeController.text = product.supplierCode ?? '';
        _descriptionController.text = product.description ?? '';
        _websiteDescriptionController.text = product.websiteDescription ?? '';
        _brandController.text = product.brand ?? '';
        _selectedBrandId = product.brandId;
        _modelController.text = product.model ?? '';
        _priceController.text = product.price.toStringAsFixed(0);
        _costController.text = product.cost.toStringAsFixed(0);
        _inventoryQtyController.text = product.inventoryQty.toString();
        _minStockController.text = product.minStockLevel.toString();
        _selectedCategoryId = product.categoryId;
        _selectedSupplierId = product.supplierId;
        _selectedProductType = product.productType;
        _selectedPurchaseTreatment = product.purchaseTreatment;
        _isActive = product.isActive;
        _isPublished = product.isPublished;
        _isGoogleMerchant = product.isGoogleMerchant;
        _imageUrl = product.imageUrl;
        _imageUrlOptimized = product.imageUrlOptimized;
        _additionalImages
          ..clear()
          ..addAll(product.additionalImages);
        _syncBrandSelection();

        // Load set configuration
        _isSet = product.isSet;
        _setType = _parseSetType(product.setType);

        // Load existing components if this is a set
        if (_isSet && product.id != null) {
          await _loadSetComponents(product.id!);
        }

        // Load Ficha Técnica spec template and saved values
        if (product.categoryId != null) {
          _loadSpecTemplate(product.categoryId!, productId: product.id);
        }

        unawaited(_loadConversionStatus(product.id));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error cargando producto: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadSpecTemplate(String categoryId, {String? productId}) async {
    if (mounted) setState(() => _isLoadingSpecs = true);
    try {
      final template =
          await SpecEngineService.instance.getTemplateForCategory(categoryId);
      if (!mounted) return;
      final values = (template != null && productId != null)
          ? await SpecEngineService.instance.getProductSpecValues(productId)
          : <String, dynamic>{};
      setState(() {
        _specTemplate = template;
        _specValues = values;
      });
    } finally {
      if (mounted) setState(() => _isLoadingSpecs = false);
    }
  }

  /// Parse set type from string stored in database
  SetType? _parseSetType(String? value) {
    if (value == null || value.isEmpty) return null;
    return SetType.values.firstWhere(
      (t) => t.name == value,
      orElse: () => SetType.custom,
    );
  }

  /// Load existing component products for a set
  Future<void> _loadSetComponents(String parentSetId) async {
    try {
      // Get all products from cache/service
      final allProducts = await _inventoryService.getProducts();

      // Filter to get components of this set
      final components = allProducts
          .where((p) => p.parentSetId == parentSetId)
          .toList()
        ..sort((a, b) =>
            (a.componentPosition ?? 0).compareTo(b.componentPosition ?? 0));

      if (components.isNotEmpty) {
        // Convert Product objects to SetComponentDraft for the widget
        _setComponents = components.map((comp) {
          // Calculate ratio if we have parent price/cost
          final parentPrice =
              double.tryParse(_priceController.text.replaceAll(',', '.')) ?? 0;
          final parentCost =
              double.tryParse(_costController.text.replaceAll(',', '.')) ?? 0;

          return SetComponentDraft(
            label: comp.componentLabel ?? comp.name,
            name: comp.name,
            skuSuffix: comp.sku.split('-').last, // Extract suffix from SKU
            position: comp.componentPosition ?? 1,
            costRatio: parentCost > 0 ? comp.cost / parentCost : null,
            priceRatio: parentPrice > 0 ? comp.price / parentPrice : null,
            cost: comp.cost,
            price: comp.price,
          );
        }).toList();

        debugPrint('[SET] Loaded ${_setComponents.length} existing components');
      }
    } catch (e) {
      debugPrint('[SET] Error loading components: $e');
    }
  }

  Future<void> _selectMainImage() async {
    try {
      final result = await ImageService.pickImage();
      if (result != null) {
        print(
            'PRODUCT FORM: Got image result - name: ${result.name}, bytes length: ${result.bytes.length}');
        print('PRODUCT FORM: Bytes type: ${result.bytes.runtimeType}');

        setState(() {
          _selectedImageBytes = result.bytes;
          _selectedImageName = result.name;
        });

        print(
            'PRODUCT FORM: State updated - _selectedImageBytes is null? ${_selectedImageBytes == null}');

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Imagen seleccionada correctamente'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 1),
            ),
          );
        }
      }
    } catch (e, stackTrace) {
      print('PRODUCT FORM ERROR: $e');
      print('PRODUCT FORM STACK: $stackTrace');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error seleccionando imagen: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _clearMainImage() {
    setState(() {
      _selectedImageBytes = null;
      _selectedImageName = null;
      _imageUrl = null;
      _imageUrlOptimized = null;
    });
  }

  Future<void> _addGalleryImage() async {
    setState(() => _isUploadingGalleryImage = true);
    try {
      final result = await ImageService.pickImage();
      if (result == null) {
        setState(() => _isUploadingGalleryImage = false);
        return;
      }

      final url = await ImageService.uploadBytes(
        bytes: result.bytes,
        fileName: result.name,
        bucket: StorageConfig.defaultBucket,
        folder: StorageFolders.productGallery,
      );

      if (url == null) {
        throw Exception('No se pudo subir la imagen. Intenta nuevamente.');
      }

      if (mounted) {
        setState(() {
          _additionalImages.add(url);
          _isUploadingGalleryImage = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isUploadingGalleryImage = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error subiendo imagen adicional: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _removeGalleryImage(String url) {
    setState(() => _additionalImages.remove(url));
  }

  Future<void> _generateSku({bool autoTriggered = false}) async {
    if (_usesAliExpressSkuSequence) {
      await _generateAliExpressSku(autoTriggered: autoTriggered);
      return;
    }

    _generateDefaultSku();
  }

  Future<void> _generateAliExpressSku({bool autoTriggered = false}) async {
    final supplier = _selectedSupplier;
    if (supplier == null) return;

    if (mounted) {
      setState(() => _isGeneratingSku = true);
    }

    try {
      final nextSku = await _inventoryService.getNextAliExpressSku(
        supplierId: supplier.id,
        supplierName: supplier.name,
      );

      if (!mounted) return;
      setState(() {
        _skuController.text = nextSku;
      });
    } catch (e) {
      if (!mounted || autoTriggered) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo generar el SKU de AliExpress: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isGeneratingSku = false);
      }
    }
  }

  void _generateDefaultSku() {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;

    final brand = _brandController.text.trim();
    final category = _categories.firstWhere(
      (c) => c.id == _selectedCategoryId,
      orElse: () => _categories.isNotEmpty
          ? _categories.first
          : category_models.Category(
              id: null, tenantId: '', name: 'PRD', fullPath: 'PRD'),
    );

    final categorySegment = category.name
        .replaceAll(RegExp(r'[^A-Za-z0-9]'), '')
        .padRight(3, 'X')
        .substring(0, 3)
        .toUpperCase();
    final brandSegment = brand.isEmpty
        ? ''
        : '-${brand.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').padRight(3, 'X').substring(0, 3).toUpperCase()}';
    final nameSegment = name
        .replaceAll(RegExp(r'[^A-Za-z0-9]'), '')
        .padRight(3, 'X')
        .substring(0, 3)
        .toUpperCase();
    final timestamp =
        DateTime.now().millisecondsSinceEpoch.toString().substring(8);

    setState(() {
      _skuController.text =
          '$categorySegment$brandSegment-$nameSegment-$timestamp';
    });
  }

  Future<void> _handleSupplierChanged(String? value) async {
    if (_selectedSupplierId == value) return;

    setState(() => _selectedSupplierId = value);
    await _maybeAutoGenerateSupplierSku();
  }

  Future<void> _maybeAutoGenerateSupplierSku() async {
    if (widget.productId != null) return;
    if (_skuController.text.trim().isNotEmpty) return;
    if (!_usesAliExpressSkuSequence) return;

    await _generateSku(autoTriggered: true);
  }

  double get _marginPercentage {
    final price =
        double.tryParse(_priceController.text.replaceAll(',', '.')) ?? 0;
    final cost =
        double.tryParse(_costController.text.replaceAll(',', '.')) ?? 0;
    if (cost <= 0) return 0;
    final netPrice = price / 1.19;
    return ((netPrice - cost) / cost) * 100;
  }

  bool get _tracksInventoryInForm =>
      _selectedProductType != ProductType.service &&
      _selectedPurchaseTreatment == PurchaseTreatment.inventory;

  bool get _canAdjustExistingStock =>
      _existingProduct?.id != null &&
      _tracksInventoryInForm &&
      !_isChildProduct;

  int get _existingTrackedStockQuantity {
    final product = _existingProduct;
    if (product == null) return 0;

    return product.inventoryQty;
  }

  double get _existingTrackedInventoryValue {
    final product = _existingProduct;
    if (product == null) return 0;
    return _existingTrackedStockQuantity * product.cost;
  }

  bool get _hasConversionHistory =>
      _conversionStatus?['has_conversion_history'] == true;

  _StockAdjustmentReasonOption _stockAdjustmentOption(String reasonType) {
    return _stockAdjustmentReasonOptions.firstWhere(
      (option) => option.key == reasonType,
      orElse: () => _stockAdjustmentReasonOptions.first,
    );
  }

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

  List<_StockAdjustmentReasonOption> _reasonOptionsForDirection(String type) {
    return _stockAdjustmentReasonOptions
        .where(
            (option) => _allowedDirectionsForReason(option.key).contains(type))
        .toList();
  }

  String _directionLabel(String type) {
    return type == 'IN' ? 'Entrada' : 'Salida';
  }

  String _stockAdjustmentCounterpartPreview(String reasonType, String type) {
    if (type == 'IN') {
      if (reasonType == 'found') {
        return 'Recuperaciones de Inventario (4202)';
      }
      return 'Ajustes Positivos de Inventario (4203)';
    }

    switch (reasonType) {
      case 'internal_use':
        return 'Consumibles de Taller (5101)';
      case 'damage':
        return 'Pérdidas por Daño de Inventario (6196)';
      case 'theft':
        return 'Pérdidas por Robo de Inventario (6197)';
      case 'loss':
        return 'Mermas de Inventario (6195)';
      default:
        return 'Diferencias de Inventario (6198)';
    }
  }

  Future<_StockAdjustmentDialogResult?> _promptStockAdjustment() async {
    final existingProduct = _existingProduct;
    if (existingProduct?.id == null) return null;
    final product = existingProduct!;

    final quantityController = TextEditingController();
    final noteController = TextEditingController();
    final currentUserEmail =
        Supabase.instance.client.auth.currentUser?.email ?? 'Usuario actual';
    var type = 'OUT';
    var reasonType = 'count';
    var effectiveAt = DateTime.now();
    String? validationMessage;

    Future<void> pickDate(
      BuildContext dialogContext,
      void Function(void Function()) setModalState,
    ) async {
      final picked = await showDatePicker(
        context: dialogContext,
        initialDate: effectiveAt,
        firstDate: DateTime(2020),
        lastDate: DateTime.now().add(const Duration(days: 30)),
      );

      if (picked == null) return;
      setModalState(() {
        effectiveAt = DateTime(
          picked.year,
          picked.month,
          picked.day,
          effectiveAt.hour,
          effectiveAt.minute,
        );
      });
    }

    Future<void> pickTime(
      BuildContext dialogContext,
      void Function(void Function()) setModalState,
    ) async {
      final picked = await showTimePicker(
        context: dialogContext,
        initialTime: TimeOfDay.fromDateTime(effectiveAt),
      );

      if (picked == null) return;
      setModalState(() {
        effectiveAt = DateTime(
          effectiveAt.year,
          effectiveAt.month,
          effectiveAt.day,
          picked.hour,
          picked.minute,
        );
      });
    }

    final result = await showDialog<_StockAdjustmentDialogResult>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final reasonOptions = _reasonOptionsForDirection(type);
            if (!reasonOptions.any((option) => option.key == reasonType)) {
              reasonType = reasonOptions.first.key;
            }

            final option = _stockAdjustmentOption(reasonType);
            final quantity = int.tryParse(quantityController.text.trim()) ?? 0;
            final estimatedValue = quantity * product.cost;

            return AlertDialog(
              title: const Text('Registrar ajuste de stock'),
              content: SizedBox(
                width: 560,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        product.name,
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                      ),
                      if (product.sku.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          product.sku,
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest
                              .withOpacity(0.45),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Stock actual: ${product.inventoryQty} unidades',
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Costo unitario: ${ChileanUtils.formatCurrency(product.cost)}',
                            ),
                            const SizedBox(height: 4),
                            Text('Responsable: $currentUserEmail'),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Dirección del movimiento',
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        children: ['OUT', 'IN']
                            .map(
                              (direction) => ChoiceChip(
                                label: Text(_directionLabel(direction)),
                                selected: type == direction,
                                onSelected: (_) {
                                  setModalState(() {
                                    type = direction;
                                    final nextReasonOptions =
                                        _reasonOptionsForDirection(direction);
                                    if (!nextReasonOptions.any(
                                      (option) => option.key == reasonType,
                                    )) {
                                      reasonType = nextReasonOptions.first.key;
                                    }
                                    validationMessage = null;
                                  });
                                },
                              ),
                            )
                            .toList(),
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        initialValue: reasonType,
                        decoration: const InputDecoration(
                          labelText: 'Motivo del ajuste',
                        ),
                        items: reasonOptions
                            .map(
                              (reason) => DropdownMenuItem<String>(
                                value: reason.key,
                                child: Text(reason.label),
                              ),
                            )
                            .toList(),
                        onChanged: (value) {
                          if (value == null) return;
                          setModalState(() {
                            reasonType = value;
                            validationMessage = null;
                          });
                        },
                      ),
                      const SizedBox(height: 8),
                      Text(
                        option.description,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: quantityController,
                        decoration: const InputDecoration(
                          labelText: 'Cantidad',
                        ),
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        onChanged: (_) {
                          if (validationMessage != null) {
                            setModalState(() => validationMessage = null);
                          }
                        },
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => pickDate(context, setModalState),
                              icon: const Icon(
                                Icons.calendar_today_outlined,
                                size: 18,
                              ),
                              label: Text(ChileanUtils.formatDate(effectiveAt)),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => pickTime(context, setModalState),
                              icon: const Icon(
                                Icons.schedule_outlined,
                                size: 18,
                              ),
                              label: Text(
                                '${effectiveAt.hour.toString().padLeft(2, '0')}:${effectiveAt.minute.toString().padLeft(2, '0')}',
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: noteController,
                        minLines: 2,
                        maxLines: 4,
                        decoration: const InputDecoration(
                          labelText: 'Detalle / observación',
                          hintText:
                              'Explica el contexto del ajuste para auditoría y contabilidad.',
                        ),
                      ),
                      const SizedBox(height: 16),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Theme.of(context).dividerColor,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Impacto esperado',
                              style: Theme.of(context).textTheme.labelLarge,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              type == 'IN'
                                  ? 'Débita Inventario (1105) y acredita ${_stockAdjustmentCounterpartPreview(reasonType, type)}.'
                                  : 'Débita ${_stockAdjustmentCounterpartPreview(reasonType, type)} y acredita Inventario (1105).',
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Valor estimado: ${ChileanUtils.formatCurrency(estimatedValue)}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            if (product.cost <= 0) ...[
                              const SizedBox(height: 4),
                              Text(
                                'Este producto no tiene costo valorizado. El ajuste quedará auditado, pero no generará monto contable hasta que exista costo.',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                    ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (validationMessage != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          validationMessage!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancelar'),
                ),
                FilledButton.icon(
                  onPressed: () {
                    final quantity =
                        int.tryParse(quantityController.text.trim()) ?? 0;
                    if (quantity <= 0) {
                      setModalState(() {
                        validationMessage =
                            'Ingresa una cantidad mayor a cero.';
                      });
                      return;
                    }

                    if (!_allowedDirectionsForReason(reasonType)
                        .contains(type)) {
                      setModalState(() {
                        validationMessage =
                            'El motivo seleccionado no corresponde a la dirección elegida.';
                      });
                      return;
                    }

                    if (type == 'OUT' && quantity > product.inventoryQty) {
                      setModalState(() {
                        validationMessage =
                            'La salida no puede dejar stock negativo. Stock actual: ${product.inventoryQty}.';
                      });
                      return;
                    }

                    Navigator.of(context).pop(
                      _StockAdjustmentDialogResult(
                        quantity: quantity,
                        type: type,
                        reasonType: reasonType,
                        note: noteController.text.trim(),
                        effectiveAt: effectiveAt,
                      ),
                    );
                  },
                  icon: const Icon(Icons.inventory_2_outlined, size: 18),
                  label: const Text('Registrar ajuste'),
                ),
              ],
            );
          },
        );
      },
    );

    quantityController.dispose();
    noteController.dispose();
    return result;
  }

  Future<void> _handleStockAdjustment() async {
    final product = _existingProduct;
    if (product?.id == null || _isApplyingStockAdjustment) return;

    final dialogResult = await _promptStockAdjustment();
    if (dialogResult == null) return;

    FocusScope.of(context).unfocus();
    setState(() => _isApplyingStockAdjustment = true);

    try {
      final detail = await _inventoryService.applyStockAdjustment(
        productId: product!.id!,
        quantity: dialogResult.quantity,
        type: dialogResult.type,
        reasonType: dialogResult.reasonType,
        note: dialogResult.note,
        effectiveAt: dialogResult.effectiveAt,
      );

      if (!mounted) return;

      setState(() {
        _existingProduct = product.copyWith(
          inventoryQty: detail.stockAfter,
          updatedAt: DateTime.now(),
        );
        _inventoryQtyController.text = detail.stockAfter.toString();
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            detail.journalEntryNumber != null &&
                    detail.journalEntryNumber!.isNotEmpty
                ? 'Ajuste ${detail.referenceNumber} registrado. Asiento ${detail.journalEntryNumber} generado.'
                : 'Ajuste ${detail.referenceNumber} registrado correctamente.',
          ),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo registrar el ajuste: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isApplyingStockAdjustment = false);
      }
    }
  }

  bool get _canRestoreOriginalState =>
      _conversionStatus?['can_restore'] == true;

  String? get _conversionReference {
    final raw = _conversionStatus?['conversion_reference'];
    if (raw == null) return null;
    final value = raw.toString().trim();
    return value.isEmpty ? null : value;
  }

  int get _conversionOriginalInventoryQty {
    final originalState = _conversionStatus?['original_state'];
    if (originalState is Map && originalState['inventory_qty'] != null) {
      return int.tryParse(originalState['inventory_qty'].toString()) ?? 0;
    }
    return 0;
  }

  double get _conversionInventoryValuePreview {
    final raw = _conversionStatus?['inventory_value'];
    if (raw == null) return 0;
    return double.tryParse(raw.toString()) ?? 0;
  }

  DateTime? _parseStatusDateTime(dynamic value) {
    if (value == null) return null;
    return DateTime.tryParse(value.toString());
  }

  String _formatStatusDateTime(dynamic value) {
    final parsed = _parseStatusDateTime(value);
    if (parsed == null) return '-';
    return ChileanUtils.formatDateTime(parsed.toLocal());
  }

  Future<void> _loadConversionStatus(String? productId) async {
    if (productId == null || productId.isEmpty) {
      if (mounted) {
        setState(() => _conversionStatus = null);
      }
      return;
    }

    if (mounted) {
      setState(() => _isLoadingConversionStatus = true);
    }

    try {
      final status = await _inventoryService.getProductConversionStatus(
        productId: productId,
      );
      if (!mounted) return;
      setState(() => _conversionStatus = status);
    } catch (e) {
      if (!mounted) return;
      setState(() => _conversionStatus = null);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error cargando historial de conversión: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoadingConversionStatus = false);
      }
    }
  }

  Future<_RestoreProductConversionOptions?> _promptRestoreOptions() async {
    final defaultReason = _conversionOriginalInventoryQty > 0
        ? 'Restauración completa del estado original del producto'
        : 'Restauración de configuración original del producto';
    final controller = TextEditingController(text: defaultReason);
    bool restoreInventory = _conversionOriginalInventoryQty > 0;

    final result = await showDialog<_RestoreProductConversionOptions>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => AlertDialog(
          title: const Text('Restaurar estado original'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Se usará el snapshot guardado en la última conversión para devolver este producto a su estado original.',
                  ),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .surfaceContainerHighest
                          .withOpacity(0.45),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Última conversión: ${_formatStatusDateTime(_conversionStatus?['conversion_created_at'])}',
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Cantidad original: $_conversionOriginalInventoryQty',
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Valor original: ${ChileanUtils.formatCurrency(_conversionInventoryValuePreview)}',
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    value: restoreInventory,
                    onChanged: _conversionOriginalInventoryQty <= 0
                        ? null
                        : (value) {
                            setModalState(() => restoreInventory = value);
                          },
                    title: const Text('Restaurar stock y valor contable'),
                    subtitle: Text(
                      _conversionOriginalInventoryQty <= 0
                          ? 'No hay stock original para restaurar.'
                          : 'Si hubo actividad posterior, el sistema bloqueará esta opción para evitar inconsistencias.',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: controller,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Motivo de la restauración',
                      hintText: 'Describe por qué restauras el estado original',
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () {
                final reason = controller.text.trim();
                Navigator.of(context).pop(
                  _RestoreProductConversionOptions(
                    reason: reason.isEmpty ? defaultReason : reason,
                    restoreInventory: restoreInventory,
                  ),
                );
              },
              child: const Text('Restaurar'),
            ),
          ],
        ),
      ),
    );

    controller.dispose();
    return result;
  }

  Future<void> _restoreOriginalProductState() async {
    final product = _existingProduct;
    if (product?.id == null || !_canRestoreOriginalState) return;

    final options = await _promptRestoreOptions();
    if (options == null) return;

    FocusScope.of(context).unfocus();
    setState(() => _isRestoringConversion = true);

    try {
      final restoredProduct =
          await _inventoryService.restoreProductConversionState(
        productId: product!.id!,
        reason: options.reason,
        restoreInventory: options.restoreInventory,
        conversionReference: _conversionReference,
      );

      _existingProduct = restoredProduct;
      await _loadProduct();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            options.restoreInventory
                ? 'Estado original restaurado con stock y valor contable.'
                : 'Configuración original restaurada sin reconstruir stock.',
          ),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error restaurando estado original: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isRestoringConversion = false);
      }
    }
  }

  Future<void> _showMissingConversionSnapshotInfo() async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sin restauracion automatica'),
        content: const Text(
          'Este producto no tiene una conversion registrada con snapshot. Fue creado como consumible de taller o se modifico antes de implementar el flujo reversible, por eso aqui no aparece el boton de restaurar.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Entendido'),
          ),
        ],
      ),
    );
  }

  Widget _buildConversionStatusCard() {
    if (_selectedProductType == ProductType.service) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final isWorkshopConsumable =
        _selectedPurchaseTreatment == PurchaseTreatment.workshopConsumable;

    if (_isLoadingConversionStatus) {
      return const Padding(
        padding: EdgeInsets.only(top: 10),
        child: LinearProgressIndicator(minHeight: 2),
      );
    }

    if (!_hasConversionHistory && !isWorkshopConsumable) {
      return const SizedBox.shrink();
    }

    if (!_hasConversionHistory) {
      return const SizedBox.shrink();
    }

    final restored = _conversionStatus?['restored'] == true;
    final convertedQuantity =
        _conversionStatus?['converted_quantity']?.toString() ?? '0';
    final conversionReason = (_conversionStatus?['conversion_reason']
                ?.toString()
                .trim()
                .isNotEmpty ??
            false)
        ? _conversionStatus!['conversion_reason'].toString().trim()
        : 'Sin motivo registrado';

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.35),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _canRestoreOriginalState
              ? theme.colorScheme.primary.withOpacity(0.25)
              : theme.dividerColor.withOpacity(0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                restored ? Icons.restore : Icons.history,
                size: 18,
                color: restored
                    ? Colors.green.shade700
                    : theme.colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  restored
                      ? 'Última conversión restaurada'
                      : 'Estado original disponible para restaurar',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Conversión: ${_formatStatusDateTime(_conversionStatus?['conversion_created_at'])}',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 4),
          Text(
            'Cantidad convertida: $convertedQuantity | Valor: ${ChileanUtils.formatCurrency(_conversionInventoryValuePreview)}',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 4),
          Text(
            'Motivo: $conversionReason',
            style: theme.textTheme.bodySmall,
          ),
          if (restored) ...[
            const SizedBox(height: 4),
            Text(
              'Restaurado: ${_formatStatusDateTime(_conversionStatus?['restored_at'])}',
              style: theme.textTheme.bodySmall,
            ),
          ],
          if (_canRestoreOriginalState) ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: _isRestoringConversion
                    ? null
                    : _restoreOriginalProductState,
                icon: _isRestoringConversion
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.restore_outlined),
                label: Text(
                  _isRestoringConversion
                      ? 'Restaurando...'
                      : 'Restaurar estado original',
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildConversionJournalPreview(BuildContext context) {
    final theme = Theme.of(context);
    final inventoryValue = _existingTrackedInventoryValue;
    final borderColor = theme.dividerColor.withOpacity(0.35);

    Widget buildHeader() {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: borderColor),
          ),
        ),
        child: Row(
          children: [
            const Expanded(
              child: Text(
                'Cuenta',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            SizedBox(
              width: 110,
              child: Text(
                'Debe',
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: Colors.green.shade700,
                ),
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 110,
              child: Text(
                'Haber',
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: Colors.red.shade700,
                ),
              ),
            ),
          ],
        ),
      );
    }

    Widget buildLine({
      required String accountCode,
      required String accountName,
      String? debitAmount,
      String? creditAmount,
    }) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: borderColor,
            ),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                '$accountCode - $accountName',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            SizedBox(
              width: 110,
              child: Text(
                debitAmount ?? '',
                textAlign: TextAlign.right,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: debitAmount == null ? null : Colors.green.shade700,
                ),
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 110,
              child: Text(
                creditAmount ?? '',
                textAlign: TextAlign.right,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: creditAmount == null ? null : Colors.red.shade700,
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (inventoryValue <= 0) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.45),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          'Preview contable: no se generará asiento porque el costo promedio actual es ${ChileanUtils.formatCurrency(0)}. Solo se descargará el stock físico.',
          style: theme.textTheme.bodySmall,
        ),
      );
    }

    final formattedValue = ChileanUtils.formatCurrency(inventoryValue);

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.45),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
            child: Text(
              'Preview del asiento contable',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              'Se reclasifica el valor del inventario existente hacia consumo interno.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(height: 8),
          buildHeader(),
          buildLine(
            accountCode: '5101',
            accountName: 'Consumibles de Taller',
            debitAmount: formattedValue,
          ),
          buildLine(
            accountCode: '1105',
            accountName: 'Inventarios',
            creditAmount: formattedValue,
          ),
        ],
      ),
    );
  }

  bool _wouldTrackInventory({
    ProductType? productType,
    PurchaseTreatment? purchaseTreatment,
  }) {
    final nextProductType = productType ?? _selectedProductType;
    final nextPurchaseTreatment =
        purchaseTreatment ?? _selectedPurchaseTreatment;

    return nextProductType != ProductType.service &&
        nextPurchaseTreatment == PurchaseTreatment.inventory;
  }

  bool get _requiresInventoryConversion {
    final product = _existingProduct;
    if (product == null || !product.tracksInventory) {
      return false;
    }

    return _existingTrackedStockQuantity > 0 && !_wouldTrackInventory();
  }

  String _inventoryConversionTargetLabel({
    ProductType? productType,
    PurchaseTreatment? purchaseTreatment,
  }) {
    final nextProductType = productType ?? _selectedProductType;
    final nextPurchaseTreatment =
        purchaseTreatment ?? _selectedPurchaseTreatment;

    if (nextProductType == ProductType.service) {
      return 'servicio';
    }

    if (nextPurchaseTreatment == PurchaseTreatment.workshopConsumable) {
      return 'consumible de taller';
    }

    return 'producto no inventariable';
  }

  Future<String?> _promptInventoryConversionReason() async {
    final targetLabel = _inventoryConversionTargetLabel();
    final defaultReason = _selectedProductType == ProductType.service
        ? 'Conversión interna de inventario a servicio'
        : 'Conversión interna de inventario a consumible de taller';
    final controller = TextEditingController(text: defaultReason);

    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Convertir inventario existente'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Este producto tiene $_existingTrackedStockQuantity unidades en stock. Al guardarlo como $targetLabel se hará la conversión interna automáticamente.',
                ),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest
                        .withOpacity(0.45),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                          'Unidades a descargar: $_existingTrackedStockQuantity'),
                      const SizedBox(height: 4),
                      Text(
                        'Valor a reclasificar: ${ChileanUtils.formatCurrency(_existingTrackedInventoryValue)}',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                _buildConversionJournalPreview(context),
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Motivo de la conversión',
                    hintText: 'Describe por qué este stock pasa a uso interno',
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              final reason = controller.text.trim();
              Navigator.of(context).pop(
                reason.isEmpty ? defaultReason : reason,
              );
            },
            child: const Text('Convertir y guardar'),
          ),
        ],
      ),
    );

    controller.dispose();
    return result;
  }

  void _handleProductTypeChanged(ProductType value) {
    setState(() {
      _selectedProductType = value;
      if (value == ProductType.service) {
        _selectedPurchaseTreatment = PurchaseTreatment.inventory;
        _inventoryQtyController.text = '0';
        _minStockController.text = '0';
      } else if (_selectedPurchaseTreatment ==
          PurchaseTreatment.workshopConsumable) {
        _inventoryQtyController.text = '0';
        _minStockController.text = '0';
      } else if (_minStockController.text.trim().isEmpty ||
          _minStockController.text.trim() == '0') {
        _minStockController.text = '1';
      }
    });
  }

  void _handlePurchaseTreatmentChanged(PurchaseTreatment value) {
    setState(() {
      _selectedPurchaseTreatment = value;
      if (value == PurchaseTreatment.workshopConsumable) {
        _inventoryQtyController.text = '0';
        _minStockController.text = '0';
      } else if (_selectedProductType != ProductType.service &&
          (_minStockController.text.trim().isEmpty ||
              _minStockController.text.trim() == '0')) {
        _minStockController.text = '1';
      }
    });
  }

  bool get _isChildProduct => _existingProduct?.parentSetId != null;

  Future<void> _saveProduct() async {
    if (!_formKey.currentState!.validate()) return;

    final requiresInventoryConversion = _requiresInventoryConversion;
    String? conversionReason;
    if (requiresInventoryConversion) {
      conversionReason = await _promptInventoryConversionReason();
      if (conversionReason == null) return;
    }

    FocusScope.of(context).unfocus();
    setState(() => _isSaving = true);
    debugPrint("[DIAGNOSTIC] _saveProduct: Save process started.");

    try {
      final tenantId = await TenantService().getTenantId();
      if (tenantId == null) {
        throw Exception('User does not have a tenant_id. Cannot proceed.');
      }

      String? finalImageUrl = _imageUrl;
      String? finalImageUrlOptimized = _imageUrlOptimized;

      // --- IMAGE UPLOAD WITH AUTO-OPTIMIZATION ---
      // Use the platform-agnostic bytes and name from the state.
      // Automatically creates both original + optimized WebP version.
      if (_selectedImageBytes != null && _selectedImageName != null) {
        final uploadResult =
            await ImageService.uploadProductImageWithOptimization(
          bytes: _selectedImageBytes!,
          fileName: _selectedImageName!,
        );
        finalImageUrl = uploadResult.originalUrl;
        finalImageUrlOptimized = uploadResult.optimizedUrl;
      }

      // --- SAFEGUARD ---
      // Ensure only valid strings are passed to the model.
      final safeAdditionalImages =
          _additionalImages.whereType<String>().toList(growable: false);

      final name = _nameController.text.trim();
      final sku = _skuController.text.trim();
      final rawDescription = _descriptionController.text.trim();
      final rawWebsiteDescription = _websiteDescriptionController.text.trim();
      final rawBrand = _brandController.text.trim();
      final rawModel = _modelController.text.trim();
      final potentialBrand = _selectedBrand ?? _matchBrandSelection();
      final normalizedBrandId = (() {
        final candidate = potentialBrand?.id ?? _selectedBrandId;
        if (candidate == null) return null;
        final trimmed = candidate.trim();
        return trimmed.isEmpty ? null : trimmed;
      })();
      final normalizedBrandName = (() {
        if (potentialBrand != null) {
          final trimmed = potentialBrand.name.trim();
          return trimmed.isEmpty ? null : trimmed;
        }
        return rawBrand.isEmpty ? null : rawBrand;
      })();
      final price =
          double.tryParse(_priceController.text.replaceAll(',', '.')) ?? 0;
      final cost =
          double.tryParse(_costController.text.replaceAll(',', '.')) ?? 0;
      final tracksInventory = _tracksInventoryInForm;
      final inventoryQty = tracksInventory
          ? (_existingProduct != null
              ? _existingProduct!.inventoryQty
              : (int.tryParse(_inventoryQtyController.text.trim()) ?? 0))
          : 0;
      final minStockLevel = tracksInventory
          ? (int.tryParse(_minStockController.text.trim()) ?? 1)
          : 0;
      final existingMaxStock = _existingProduct?.maxStockLevel ?? 100;
      final maxStockLevel =
          tracksInventory ? (existingMaxStock > 0 ? existingMaxStock : 100) : 0;

      String? selectedCategoryName;
      for (final category in _categories) {
        if (category.id == _selectedCategoryId) {
          selectedCategoryName = category.name;
          break;
        }
      }

      String? selectedSupplierName;
      for (final supplier in _suppliers) {
        if (supplier.id == _selectedSupplierId) {
          selectedSupplierName = supplier.name;
          break;
        }
      }

      if (requiresInventoryConversion &&
          _existingProduct != null &&
          _existingProduct!.id != null &&
          conversionReason != null) {
        final convertedProduct =
            await _inventoryService.convertProductInventoryToNonStock(
          productId: _existingProduct!.id!,
          targetPurchaseTreatment: _selectedPurchaseTreatment,
          targetProductType: _selectedProductType,
          reason: conversionReason,
        );
        _existingProduct = convertedProduct;
        _inventoryQtyController.text = '0';
      }

      final baseProduct = _existingProduct ??
          Product(
            id: null,
            tenantId: tenantId,
            name: name,
            sku: sku,
            description: rawDescription.isEmpty ? null : rawDescription,
            websiteDescription: rawWebsiteDescription,
            categoryId: _selectedCategoryId,
            categoryName: selectedCategoryName,
            supplierId: _selectedSupplierId,
            supplierName: selectedSupplierName,
            supplierCode: _supplierCodeController.text.trim().isEmpty
                ? null
                : _supplierCodeController.text.trim(),
            brandId: normalizedBrandId,
            brand: normalizedBrandName,
            model: rawModel.isEmpty ? null : rawModel,
            price: price,
            cost: cost,
            inventoryQty: inventoryQty,
            minStockLevel: minStockLevel,
            maxStockLevel: maxStockLevel,
            imageUrl: finalImageUrl,
            imageUrlOptimized: finalImageUrlOptimized,
            additionalImages: safeAdditionalImages,
            isActive: _isActive,
            isPublished: _isPublished,
            isGoogleMerchant: _isGoogleMerchant,
            purchaseTreatment: _selectedPurchaseTreatment,
            productType: _selectedProductType,
          );

      final product = baseProduct.copyWith(
        name: name,
        sku: sku,
        description: rawDescription.isEmpty ? null : rawDescription,
        websiteDescription: rawWebsiteDescription,
        categoryId: _selectedCategoryId,
        categoryName: selectedCategoryName ?? baseProduct.categoryName,
        supplierId: _selectedSupplierId,
        supplierName: selectedSupplierName ?? baseProduct.supplierName,
        supplierCode: _supplierCodeController.text.trim().isEmpty
            ? null
            : _supplierCodeController.text.trim(),
        brandId: normalizedBrandId,
        brandIdHasValue: true,
        brand: normalizedBrandName,
        brandHasValue: true,
        model: rawModel.isEmpty ? null : rawModel,
        price: price,
        cost: cost,
        inventoryQty: inventoryQty,
        minStockLevel: minStockLevel,
        maxStockLevel: maxStockLevel,
        imageUrl: finalImageUrl,
        imageUrlOptimized: finalImageUrlOptimized,
        additionalImages: safeAdditionalImages,
        isActive: _isActive,
        isPublished: _isPublished,
        isGoogleMerchant: _isGoogleMerchant,
        purchaseTreatment: _selectedPurchaseTreatment,
        productType: _selectedProductType,
        // Set configuration
        isSet: _isSet,
        setType: _setType?.name,
        updatedAt: DateTime.now(),
      );

      Product savedProduct;
      if (_existingProduct != null) {
        savedProduct = await _inventoryService.updateProduct(product);
      } else {
        savedProduct = await _inventoryService.createProduct(product);
      }

      // Create component products if this is a set
      if (_isSet && _setComponents.isNotEmpty && savedProduct.id != null) {
        await _createSetComponentProducts(savedProduct);
      }

      // Save Ficha Técnica spec values
      if (_specTemplate != null && savedProduct.id != null) {
        final tenantId = await TenantService().getTenantId();
        if (tenantId != null) {
          await SpecEngineService.instance.saveProductSpecValues(
            productId: savedProduct.id!,
            tenantId: tenantId,
            template: _specTemplate!,
            values: _specValues,
          );
        }
      }

      _notifySharedInventory();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _existingProduct != null
                ? 'Producto actualizado con éxito'
                : 'Producto creado con éxito',
          ),
          backgroundColor: Colors.green,
        ),
      );

      // Use Navigator.pop() instead of context.pop() to work in dialogs
      Navigator.of(context).pop(true);
    } catch (e, stackTrace) {
      // Log to console immediately
      print('🔴🔴🔴 PRODUCT SAVE ERROR 🔴🔴🔴');
      print('Error: $e');
      print('Error Type: ${e.runtimeType}');
      print('Stack Trace:');
      print(stackTrace.toString());

      // Save error for display
      setState(() {
        _lastError = e.toString();
        _lastStackTrace = stackTrace.toString();
      });
      ErrorReportingService.report('Error guardando producto: $e', stackTrace);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error guardando producto: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  /// Create component products for a set
  Future<void> _createSetComponentProducts(Product parentProduct) async {
    final parentId = parentProduct.id;
    if (parentId == null) return;

    debugPrint(
        '[SET] Creating ${_setComponents.length} component products for set ${parentProduct.sku}');

    // 1. Identify and delete orphaned components
    // (Components that exist in DB for this set but are NOT in the current list)
    try {
      final allProducts = await _inventoryService.getProducts();
      final existingSetComponents =
          allProducts.where((p) => p.parentSetId == parentId).toList();

      final currentSkus =
          _setComponents.map((c) => c.generateSku(parentProduct.sku)).toSet();

      for (final existing in existingSetComponents) {
        if (!currentSkus.contains(existing.sku)) {
          if (existing.id != null) {
            debugPrint('[SET] Deleting orphaned component: ${existing.sku}');
            await _inventoryService.deleteProduct(existing.id!);
          }
        }
      }
    } catch (e) {
      debugPrint('[SET] Error cleaning up orphans: $e');
    }

    // 2. Create or update current components
    for (final component in _setComponents) {
      try {
        // Generate component SKU
        final componentSku = component.generateSku(parentProduct.sku);

        // Check if component already exists (for updates)
        final existingComponent =
            await _inventoryService.getProductBySku(componentSku);

        if (existingComponent != null) {
          // Update existing component
          debugPrint('[SET] Updating existing component: $componentSku');
          await _inventoryService.updateProduct(existingComponent.copyWith(
            name: component.name.isNotEmpty
                ? component.name
                : '${parentProduct.name} - ${component.label}',
            price: component.price,
            cost: component.cost,
            componentLabel: component.label,
            componentPosition: component.position,
          ));
        } else {
          // Create new component product
          debugPrint('[SET] Creating new component: $componentSku');
          final componentProduct = Product(
            tenantId: parentProduct.tenantId,
            name: component.name.isNotEmpty
                ? component.name
                : '${parentProduct.name} - ${component.label}',
            sku: componentSku,
            description: '${component.label} del set ${parentProduct.name}',
            categoryId: parentProduct.categoryId,
            supplierId: parentProduct.supplierId,
            brand: parentProduct.brand,
            price: component.price,
            cost: component.cost,
            inventoryQty: 0, // Components start with 0 stock
            minStockLevel: parentProduct.minStockLevel,
            imageUrl: parentProduct.imageUrl,
            isActive: parentProduct.isActive,
            isPublished: false, // Components are not published directly
            productType: ProductType.product,
            // Link to parent set
            parentSetId: parentId,
            componentLabel: component.label,
            componentPosition: component.position,
          );

          debugPrint('[SET] Component data: ${componentProduct.toJson()}');
          final created =
              await _inventoryService.createProduct(componentProduct);
          debugPrint(
              '[SET] ✅ Created component ${component.label} with ID: ${created.id}');
        }
      } catch (e, stackTrace) {
        debugPrint('[SET] ❌ Error creating component ${component.label}: $e');
        debugPrint('[SET] Stack: $stackTrace');
        // Continue with other components even if one fails
      }
    }

    debugPrint('[SET] Finished creating component products');
  }

  void _notifySharedInventory() {
    try {
      final shared = context.read<shared_inventory.InventoryService>();
      unawaited(shared.refresh());
    } catch (_) {
      // Ignored: shared inventory not available in certain contexts.
    }
  }

  /// Show confirmation dialog and delete product
  Future<void> _confirmDeleteProduct() async {
    final product = _existingProduct;
    if (product == null || product.id == null) return;

    // Check if this is a set with components
    final allProducts = await _inventoryService.getProducts();
    final components =
        allProducts.where((p) => p.parentSetId == product.id).toList();

    final hasComponents = components.isNotEmpty;
    final componentText = hasComponents
        ? '\n\n⚠️ Este set tiene ${components.length} componentes que quedarán huérfanos.'
        : '';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Eliminar producto?'),
        content: Text(
          'Esta acción eliminará permanentemente "${product.name}".$componentText\n\n'
          '¿Estás seguro?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () async {
              try {
                // Delete components first
                debugPrint(
                    '[DELETE] Deleting ${components.length} components...');
                for (final comp in components) {
                  if (comp.id != null) {
                    debugPrint(
                        '[DELETE] Deleting component ${comp.sku} (${comp.id})');
                    await _inventoryService.deleteProduct(comp.id!);
                  }
                }
                debugPrint('[DELETE] All components deleted successfully');
                if (context.mounted) Navigator.of(context).pop(true);
              } catch (e) {
                debugPrint('[DELETE] Error deleting components: $e');
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Error eliminando componentes: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                  // Close dialog anyway to allow retry of main product or manual fix
                  Navigator.of(context).pop(true);
                }
              }
            },
            child: Text(
              'Eliminar set y componentes',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: Text(hasComponents ? 'Solo eliminar set' : 'Eliminar'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      try {
        await _inventoryService.deleteProduct(product.id!);
        _notifySharedInventory();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Producto eliminado'),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.of(context).pop(true);
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error eliminando producto: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final content = _isLoading
        ? const Center(child: BrandedLoading())
        : Column(
            children: [
              // Debug error banner
              if (_lastError != null)
                Container(
                  width: double.infinity,
                  color: Colors.red,
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('ERROR:',
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold)),
                      SelectableText(_lastError!,
                          style: const TextStyle(color: Colors.white)),
                      const SizedBox(height: 8),
                      const Text('STACK:',
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 10)),
                      SelectableText(_lastStackTrace ?? '',
                          style: const TextStyle(
                              color: Colors.white, fontSize: 8)),
                    ],
                  ),
                ),
              _buildHeader(theme),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: _buildForm(theme),
                ),
              ),
            ],
          );

    // Skip MainLayout when shown in dialog
    if (widget.showInDialog) {
      return content;
    }

    return MainLayout(child: content);
  }

  Widget _buildHeader(ThemeData theme) {
    final title =
        _existingProduct != null ? 'Editar producto' : 'Nuevo producto';
    final isMobile = MediaQuery.of(context).size.width < 600;

    if (isMobile) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                IconButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  icon: const Icon(Icons.arrow_back),
                  tooltip: 'Volver',
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (_existingProduct != null)
                  IconButton(
                    onPressed: _isSaving ? null : _confirmDeleteProduct,
                    icon: const Icon(Icons.delete_outline),
                    tooltip: 'Eliminar producto',
                    color: theme.colorScheme.error,
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Mantén los datos comerciales y de inventario al día.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.percent,
                            size: 16, color: theme.colorScheme.primary),
                        const SizedBox(width: 6),
                        Text(
                          'Margen ${_marginPercentage.toStringAsFixed(1)}%',
                          style: theme.textTheme.labelMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                AppButton(
                  text: 'Guardar',
                  icon: Icons.save_outlined,
                  onPressed: _isSaving ? null : _saveProduct,
                  isLoading: _isSaving,
                ),
              ],
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.arrow_back),
            tooltip: 'Volver',
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Mantén los datos comerciales y de inventario al día para el POS y la contabilidad.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              children: [
                Icon(Icons.percent, size: 16, color: theme.colorScheme.primary),
                const SizedBox(width: 6),
                Text(
                  'Margen ${_marginPercentage.toStringAsFixed(1)}%',
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          // Delete button - only for existing products
          if (_existingProduct != null) ...[
            IconButton(
              onPressed: _isSaving ? null : _confirmDeleteProduct,
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Eliminar producto',
              color: theme.colorScheme.error,
            ),
            const SizedBox(width: 8),
          ],
          AppButton(
            text: 'Guardar',
            icon: Icons.save_outlined,
            onPressed: _isSaving ? null : _saveProduct,
            isLoading: _isSaving,
          ),
        ],
      ),
    );
  }

  Widget _buildForm(ThemeData theme) {
    return Form(
      key: _formKey,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth > 1080;
          final tabBar = Container(
            color: theme.colorScheme.surface,
            margin: const EdgeInsets.only(bottom: 16),
            child: TabBar(
              controller: _tabController,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              labelColor: theme.colorScheme.primary,
              unselectedLabelColor: theme.colorScheme.onSurfaceVariant,
              indicatorSize: TabBarIndicatorSize.label,
              tabs: const [
                Tab(
                  icon: Icon(Icons.edit_note),
                  text: 'Detalles Generales',
                ),
                Tab(
                  icon: Icon(Icons.language),
                  text: 'Tienda Online',
                ),
                Tab(
                  icon: Icon(Icons.tune),
                  text: 'Ficha Técnica',
                ),
              ],
            ),
          );

          final leftContent = ListenableBuilder(
            listenable: _tabController,
            builder: (context, _) {
              final goingRight = _tabController.index >= _prevTabIndex;
              final Widget tabView;
              switch (_tabController.index) {
                case 0:
                  tabView = SingleChildScrollView(
                    key: const ValueKey(0),
                    padding: const EdgeInsets.only(bottom: 100),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildGeneralTabLeft(theme),
                        // On narrow screens, sidebar cards appear inline
                        if (!isWide) ...[
                          const SizedBox(height: 16),
                          _buildRightSidebar(theme),
                        ],
                      ],
                    ),
                  );
                case 1:
                  tabView = _buildWebsiteTab(theme, key: const ValueKey(1));
                case 2:
                  tabView = _buildSpecTab(theme, key: const ValueKey(2));
                default:
                  tabView = const SizedBox.shrink(key: ValueKey(-1));
              }
              return AnimatedSwitcher(
                duration: const Duration(milliseconds: 280),
                layoutBuilder: (currentChild, previousChildren) => Stack(
                  alignment: Alignment.topLeft,
                  children: [
                    ...previousChildren,
                    if (currentChild != null) currentChild,
                  ],
                ),
                transitionBuilder: (child, animation) {
                  final isEntering =
                      child.key == ValueKey(_tabController.index);
                  final slideIn = Tween<Offset>(
                    begin: isEntering
                        ? Offset(goingRight ? 0.06 : -0.06, 0)
                        : Offset(goingRight ? -0.06 : 0.06, 0),
                    end: Offset.zero,
                  ).animate(CurvedAnimation(
                    parent: animation,
                    curve: Curves.easeOutCubic,
                  ));
                  return FadeTransition(
                    opacity: animation,
                    child: SlideTransition(position: slideIn, child: child),
                  );
                },
                child: tabView,
              );
            },
          );

          if (isWide) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    children: [
                      tabBar,
                      Expanded(child: leftContent),
                    ],
                  ),
                ),
                const SizedBox(width: 24),
                SizedBox(
                  width: 360,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.only(bottom: 100),
                    child: _buildRightSidebar(theme),
                  ),
                ),
              ],
            );
          }

          // Narrow layout: everything stacked, right sidebar inside general tab
          return Column(
            children: [
              tabBar,
              Expanded(child: leftContent),
            ],
          );
        },
      ),
    );
  }

  /// Right sidebar — always visible on wide screens (images, inventory, status).
  Widget _buildRightSidebar(ThemeData theme) {
    return Column(
      children: [
        _buildSectionCard(
          theme,
          icon: Icons.image_outlined,
          title: 'Imágenes',
          children: _buildMediaFields(theme),
        ),
        if (_tracksInventoryInForm) ...[
          const SizedBox(height: 16),
          _buildSectionCard(
            theme,
            icon: Icons.inventory_outlined,
            title: 'Inventario',
            children: _buildInventoryFields(theme),
          ),
        ],
        const SizedBox(height: 16),
        _buildSectionCard(
          theme,
          icon: Icons.settings_outlined,
          title: 'Estado y visibilidad',
          children: _buildStatusFields(theme),
        ),
      ],
    );
  }

  /// Left column content for the General tab (wide layout).
  /// On narrow screens this includes the sidebar cards too (via [_buildGeneralTab]).
  Widget _buildGeneralTabLeft(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Child Product Banner
        if (_isChildProduct)
          Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.tertiaryContainer,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: theme.colorScheme.tertiary),
            ),
            child: Row(
              children: [
                Icon(Icons.extension,
                    color: theme.colorScheme.onTertiaryContainer),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Componente de Set',
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: theme.colorScheme.onTertiaryContainer,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Este producto es parte de un set (${_existingProduct?.componentLabel ?? "Componente"}).',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onTertiaryContainer,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        _buildSectionCard(
          theme,
          icon: Icons.description_outlined,
          title: 'Información básica',
          children: _buildBasicInfoFields(theme),
        ),
        const SizedBox(height: 16),
        _buildSectionCard(
          theme,
          icon: Icons.attach_money_outlined,
          title: 'Precios y márgenes',
          children: _buildPricingFields(theme),
        ),
        const SizedBox(height: 16),
        _buildSectionCard(
          theme,
          icon: Icons.text_snippet_outlined,
          title: 'Descripción del producto',
          children: _buildDescriptionFields(theme),
        ),
        // Only show set configuration for products, not services AND not child products
        if (_tracksInventoryInForm && !_isChildProduct) ...[
          const SizedBox(height: 16),
          _buildSectionCard(
            theme,
            icon: Icons.inventory_2_outlined,
            title: 'Configuración de Juego/Set',
            children: _buildSetConfigurationFields(theme),
          ),
        ],
      ],
    );
  }

  // ── Ficha Técnica tab ──────────────────────────────────────────────────

  Widget _buildSpecTab(ThemeData theme, {Key? key}) {
    if (_isLoadingSpecs) {
      return Center(key: key, child: const CircularProgressIndicator());
    }

    if (_specTemplate == null) {
      return Center(
        key: key,
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.tune_outlined,
                  size: 48, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(height: 16),
              Text(
                'Sin ficha técnica',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _selectedCategoryId == null
                    ? 'Asigna una categoría al producto para ver su ficha técnica.'
                    : 'Esta categoría no tiene ficha técnica configurada.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final template = _specTemplate!;
    final sections = template.sections;
    final sectionLabels = <String, String>{
      'identification': 'Identificación',
      'compatibility': 'Compatibilidad',
      'specs': 'Especificaciones',
      'hydraulic': 'Sistema Hidráulico',
      'mounting': 'Montaje',
      'features': 'Características',
      'installation': 'Instalación',
      'general': 'General',
    };

    return SingleChildScrollView(
      key: key,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Template name chip
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Row(
              children: [
                Icon(Icons.tune, size: 16, color: theme.colorScheme.primary),
                const SizedBox(width: 6),
                Text(
                  template.name,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          for (final section in sections)
            ..._buildSpecSection(
              theme: theme,
              section: section,
              label: sectionLabels[section] ?? section,
              template: template,
            ),
        ],
      ),
    );
  }

  List<Widget> _buildSpecSection({
    required ThemeData theme,
    required String section,
    required String label,
    required SpecTemplate template,
  }) {
    final fields = template
        .fieldsForSection(section)
        .where((f) => f.isVisible(_specValues))
        .toList();
    if (fields.isEmpty) return [];

    const sectionIcons = <String, IconData>{
      'hydraulic': Icons.water_drop_outlined,
      'identification': Icons.label_outline,
      'compatibility': Icons.link_outlined,
      'specs': Icons.tune,
      'mounting': Icons.build_outlined,
      'features': Icons.star_outline,
      'installation': Icons.handyman_outlined,
      'general': Icons.list_alt_outlined,
    };

    final fieldWidgets = <Widget>[];
    for (int i = 0; i < fields.length; i++) {
      fieldWidgets.add(_buildSpecField(theme: theme, field: fields[i]));
      if (i < fields.length - 1) fieldWidgets.add(const SizedBox(height: 16));
    }

    return [
      _buildSectionCard(
        theme,
        icon: sectionIcons[section] ?? Icons.tune,
        title: label,
        children: fieldWidgets,
      ),
      const SizedBox(height: 16),
    ];
  }

  Widget _buildSpecField({
    required ThemeData theme,
    required SpecTemplateField field,
  }) {
    final def = field.definition;
    if (def == null) return const SizedBox.shrink();

    final currentValue = _specValues[def.key];
    final label = def.label + (field.isRequired ? ' *' : '');

    switch (def.dataType) {
      case 'boolean':
        return Row(
          children: [
            Expanded(
              child: Text(label, style: theme.textTheme.bodyMedium),
            ),
            Switch(
              value: currentValue == true ||
                  currentValue?.toString().toLowerCase() == 'true',
              onChanged: (v) =>
                  setState(() => _specValues = {..._specValues, def.key: v}),
            ),
          ],
        );

      case 'single_select':
        return DropdownButtonFormField<String>(
          initialValue: currentValue?.toString(),
          decoration: InputDecoration(
            labelText: label,
            suffixText: def.unit,
          ),
          items: def.options
              .map((o) => DropdownMenuItem(value: o, child: Text(o)))
              .toList(),
          onChanged: (v) =>
              setState(() => _specValues = {..._specValues, def.key: v}),
        );

      case 'multi_select':
        final selected = (currentValue is List)
            ? Set<String>.from(currentValue.map((e) => e.toString()))
            : (currentValue != null ? {currentValue.toString()} : <String>{});
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: def.options.map((o) {
                final isSelected = selected.contains(o);
                return FilterChip(
                  label: Text(o),
                  selected: isSelected,
                  onSelected: (v) {
                    final next = Set<String>.from(selected);
                    if (v) {
                      next.add(o);
                    } else {
                      next.remove(o);
                    }
                    setState(() =>
                        _specValues = {..._specValues, def.key: next.toList()});
                  },
                );
              }).toList(),
            ),
          ],
        );

      case 'number':
        return TextFormField(
          initialValue: currentValue?.toString() ?? '',
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: label,
            suffixText: def.unit,
          ),
          validator: field.isRequired
              ? (v) => (v == null || v.trim().isEmpty) ? 'Requerido' : null
              : null,
          onChanged: (v) {
            final parsed = double.tryParse(v);
            setState(
                () => _specValues = {..._specValues, def.key: parsed ?? v});
          },
        );

      default: // text
        return TextFormField(
          initialValue: currentValue?.toString() ?? '',
          decoration: InputDecoration(
            labelText: label,
            suffixText: def.unit,
          ),
          validator: field.isRequired
              ? (v) => (v == null || v.trim().isEmpty) ? 'Requerido' : null
              : null,
          onChanged: (v) =>
              setState(() => _specValues = {..._specValues, def.key: v.trim()}),
        );
    }
  }

  Widget _buildWebsiteTab(ThemeData theme, {Key? key}) {
    return SingleChildScrollView(
      key: key,
      padding: const EdgeInsets.only(top: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionCard(
            theme,
            icon: Icons.language,
            title: 'Tienda Online',
            children: _buildWebsiteFields(theme),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionCard(
    ThemeData theme, {
    required IconData icon,
    required String title,
    required List<Widget> children,
  }) {
    return Card(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: theme.colorScheme.primary.withOpacity(0.12),
                  child: Icon(icon, color: theme.colorScheme.primary, size: 18),
                ),
                const SizedBox(width: 12),
                Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            ...children,
          ],
        ),
      ),
    );
  }

  List<Widget> _buildBasicInfoFields(ThemeData theme) {
    return [
      TextFormField(
        controller: _nameController,
        decoration: const InputDecoration(
          labelText: 'Nombre del producto',
          hintText: 'Ej. Bicicleta Trek Marlin 7',
        ),
        validator: (value) {
          if (value == null || value.trim().isEmpty) {
            return 'Ingresa un nombre válido';
          }
          return null;
        },
      ),
      const SizedBox(height: 16),
      Row(
        children: [
          Expanded(
            flex: 3,
            child: TextFormField(
              controller: _skuController,
              decoration: InputDecoration(
                labelText: 'SKU interno',
                hintText: _usesAliExpressSkuSequence
                    ? 'Se asigna automáticamente como AE####'
                    : 'Ej. BIC-MTB-TRK-001',
                helperText: _usesAliExpressSkuSequence
                    ? 'Proveedor AliExpress: usa la secuencia automática AE####.'
                    : null,
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'El SKU es requerido';
                }
                return null;
              },
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _isGeneratingSku ? null : () => _generateSku(),
              icon: _isGeneratingSku
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.auto_fix_high_outlined),
              label:
                  Text(_usesAliExpressSkuSequence ? 'Siguiente AE' : 'Generar'),
            ),
          ),
        ],
      ),
      const SizedBox(height: 16),
      TextFormField(
        controller: _supplierCodeController,
        decoration: const InputDecoration(
          labelText: 'Código Proveedor',
          hintText: 'Ej. KMC-2025-001',
        ),
      ),
      const SizedBox(height: 16),
      // Searchable Category Selector
      InkWell(
        onTap: () => _showCategorySearchDialog(context),
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: 'Categoría',
            helperText: 'Determina reportes y navegación en el POS',
            suffixIcon: const Icon(Icons.arrow_drop_down),
            errorText:
                _selectedCategoryId == null ? 'Seleccione una categoría' : null,
          ),
          child: Text(
            _selectedCategoryId != null
                ? (_categories
                    .firstWhere(
                      (c) => c.id == _selectedCategoryId,
                      orElse: () => category_models.Category(
                        id: '',
                        tenantId: '', // Display-only fallback
                        name: 'Categoría no encontrada',
                        fullPath: 'Categoría no encontrada',
                        createdAt: DateTime.now(),
                        updatedAt: DateTime.now(),
                      ),
                    )
                    .fullPath)
                : 'Seleccione una categoría...',
            style: TextStyle(
              color: _selectedCategoryId != null ? null : Colors.grey,
            ),
          ),
        ),
      ),
      const SizedBox(height: 16),
      // Product Type Selector
      DropdownButtonFormField<ProductType>(
        initialValue: _selectedProductType,
        decoration: const InputDecoration(
          labelText: 'Tipo de producto',
          helperText:
              'Los productos pueden ser comprados y vendidos, los servicios solo se venden',
          prefixIcon: Icon(Icons.category),
        ),
        items: ProductType.values.map((type) {
          return DropdownMenuItem<ProductType>(
            value: type,
            child: Row(
              children: [
                Icon(
                  type == ProductType.product ? Icons.inventory_2 : Icons.build,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(type.displayName),
              ],
            ),
          );
        }).toList(),
        onChanged: (value) {
          if (value != null) {
            _handleProductTypeChanged(value);
          }
        },
      ),
      const SizedBox(height: 16),
      if (_selectedProductType != ProductType.service) ...[
        InputDecorator(
          decoration: const InputDecoration(
            labelText: 'Tratamiento de compra',
            helperText:
                'Define si las compras de este producto entran a inventario o se consumen directo en taller',
            prefixIcon: Icon(Icons.build_circle_outlined),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SegmentedButton<PurchaseTreatment>(
                segments: const [
                  ButtonSegment<PurchaseTreatment>(
                    value: PurchaseTreatment.inventory,
                    icon: Icon(Icons.inventory_2_outlined),
                    label: Text('Inventario'),
                  ),
                  ButtonSegment<PurchaseTreatment>(
                    value: PurchaseTreatment.workshopConsumable,
                    icon: Icon(Icons.build_outlined),
                    label: Text('Consumible taller'),
                  ),
                ],
                selected: <PurchaseTreatment>{_selectedPurchaseTreatment},
                onSelectionChanged: (selection) {
                  if (selection.isNotEmpty) {
                    _handlePurchaseTreatmentChanged(selection.first);
                  }
                },
                showSelectedIcon: false,
              ),
              const SizedBox(height: 12),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: Theme.of(context)
                      .colorScheme
                      .surfaceContainerHighest
                      .withOpacity(0.25),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Theme.of(context).dividerColor.withOpacity(0.1),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      _selectedPurchaseTreatment == PurchaseTreatment.inventory
                          ? Icons.inventory_2_outlined
                          : Icons.build_circle_outlined,
                      size: 16,
                      color: Theme.of(context)
                          .colorScheme
                          .onSurfaceVariant
                          .withOpacity(0.7),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _selectedPurchaseTreatment ==
                                PurchaseTreatment.inventory
                            ? 'Se capitaliza como inventario y requiere control de stock.'
                            : 'Se compra para uso rápido en taller, no sube stock y se reconoce como costo directo.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                              height: 1.4,
                            ),
                      ),
                    ),
                    if (_selectedPurchaseTreatment ==
                            PurchaseTreatment.workshopConsumable &&
                        !_hasConversionHistory &&
                        !_isLoadingConversionStatus)
                      Padding(
                        padding: const EdgeInsets.only(left: 8.0),
                        child: Tooltip(
                          message:
                              'Este producto fue creado como consumible o modificado antes de existir el historial.',
                          child: InkWell(
                            onTap: _showMissingConversionSnapshotInfo,
                            borderRadius: BorderRadius.circular(12),
                            child: Padding(
                              padding: const EdgeInsets.all(2.0),
                              child: Icon(
                                Icons.help_outline,
                                size: 18,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (_requiresInventoryConversion) ...[
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.orange.withOpacity(0.24)),
                  ),
                  child: Text(
                    'Al guardar se descargará el stock existente y se reclasificará su valor contable automáticamente para convertir este producto en ${_inventoryConversionTargetLabel()}.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
              _buildConversionStatusCard(),
            ],
          ),
        ),
      ] else ...[
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color:
                Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.4),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(
                Icons.info_outline,
                size: 18,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Los servicios no manejan stock ni tratamiento de compra.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ),
            ],
          ),
        ),
      ],
      const SizedBox(height: 16),
      DropdownButtonFormField<String?>(
        initialValue: _selectedSupplierId,
        decoration: const InputDecoration(
          labelText: 'Proveedor',
          helperText: 'Proveedor principal de este producto (opcional)',
        ),
        items: [
          const DropdownMenuItem<String?>(
            value: null,
            child: Text('Sin proveedor'),
          ),
          ..._suppliers.map(
            (supplier) => DropdownMenuItem<String?>(
              value: supplier.id,
              child: Text(supplier.name),
            ),
          ),
        ],
        onChanged: _handleSupplierChanged,
      ),
      const SizedBox(height: 16),
      Row(
        children: [
          Expanded(
            child: TextFormField(
              controller: _brandController,
              readOnly: true,
              enableInteractiveSelection: false,
              decoration: InputDecoration(
                labelText: 'Marca',
                hintText: _brands.isEmpty
                    ? 'Toca para seleccionar'
                    : 'Selecciona una marca',
                suffixIcon: _isLoadingBrands
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : SizedBox(
                        width: _selectedBrand != null ? 96 : 72,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            if (_selectedBrand != null)
                              IconButton(
                                tooltip: 'Limpiar marca',
                                iconSize: 20,
                                icon: const Icon(Icons.clear),
                                onPressed: () {
                                  setState(() {
                                    _selectedBrand = null;
                                    _selectedBrandId = null;
                                    _brandController.clear();
                                  });
                                },
                              ),
                            IconButton(
                              tooltip: 'Nueva marca',
                              iconSize: 20,
                              icon: const Icon(Icons.add_circle_outline),
                              onPressed: () async {
                                await context.push('/inventory/brands/new');
                                if (!mounted) return;
                                await _loadBrands();
                                await _openBrandPicker();
                              },
                            ),
                            const Icon(Icons.arrow_drop_down),
                          ],
                        ),
                      ),
              ),
              onTap: () async {
                FocusScope.of(context).unfocus();
                await _openBrandPicker();
              },
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: TextFormField(
              controller: _modelController,
              decoration: const InputDecoration(
                labelText: 'Modelo',
                hintText: 'Ej. Marlin 7 2025',
              ),
            ),
          ),
        ],
      ),
    ];
  }

  // ... _buildForm ... (omitted, assuming no changes here, or handled separately)
  // Wait, I need to check where _buildForm ends relative to this replacement.
  // No, I am replacing _buildHeader and subsequent methods. I should break this down.

  // Let's replace _buildHeader separately first to be safe, but since I have a large chunk target,
  // I will just replace the methods I need to change.

  // Actually, I can use LayoutBuilder inside the helper methods _buildPricingFields and _buildInventoryFields.
  // The tool call replaced the content up to line 1862.

  // Re-reading code... I will replace _buildHeader, _buildPricingFields, and _buildInventoryFields.

  List<Widget> _buildPricingFields(ThemeData theme) {
    return [
      LayoutBuilder(builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 600;
        final children = [
          Expanded(
            flex: isMobile ? 0 : 1,
            child: TextFormField(
              controller: _priceController,
              decoration: const InputDecoration(
                labelText: 'Precio de venta',
                prefixText: 'CLP ',
              ),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9,.]')),
              ],
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Define el precio de venta';
                }
                return null;
              },
            ),
          ),
          SizedBox(width: 16, height: isMobile ? 16 : 0),
          Expanded(
            flex: isMobile ? 0 : 1,
            child: TextFormField(
              controller: _costController,
              decoration: const InputDecoration(
                labelText: 'Costo unitario',
                prefixText: 'CLP ',
              ),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9,.]')),
              ],
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Indica el costo del producto';
                }
                return null;
              },
            ),
          ),
        ];

        return isMobile
            ? Column(
                children: children
                    .map((w) => w is Expanded
                        ? SizedBox(width: double.infinity, child: w.child)
                        : w)
                    .toList())
            : Row(children: children);
      }),
      const SizedBox(height: 16),
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.colorScheme.primaryContainer.withOpacity(0.25),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Icon(Icons.show_chart, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  'Margen estimado',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
            Text(
              '${_marginPercentage.isFinite ? _marginPercentage.toStringAsFixed(1) : '0.0'}%',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: _marginPercentage < 0
                    ? theme.colorScheme.error
                    : theme.colorScheme.primary,
              ),
            ),
          ],
        ),
      ),
    ];
  }

  List<Widget> _buildInventoryFields(ThemeData theme) {
    final stockIsManagedByAdjustments = _canAdjustExistingStock;
    final stockAdjustmentTooltip =
        'Stock valorizado actual: ${ChileanUtils.formatCurrency(_existingTrackedInventoryValue)}\n\n'
        'Cada ajuste queda referenciado en movimientos de stock y, si el producto tiene costo, genera el asiento contable correspondiente.';

    return [
      Text(
        stockIsManagedByAdjustments
            ? 'El stock actual solo cambia mediante ajustes auditables con motivo, fecha, usuario y asiento contable.'
            : 'Controla cantidades disponibles y stock mínimo para alertas.',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      const SizedBox(height: 16),
      LayoutBuilder(
        builder: (context, constraints) {
          final isMobile = constraints.maxWidth < 600;

          final stockField = TextFormField(
            controller: _inventoryQtyController,
            readOnly: stockIsManagedByAdjustments,
            decoration: InputDecoration(
              labelText: stockIsManagedByAdjustments
                  ? 'Stock actual'
                  : 'Stock disponible',
              helperText: stockIsManagedByAdjustments
                  ? 'Haz clic en el ícono azul para registrar un ajuste.'
                  : null,
              suffixIcon: stockIsManagedByAdjustments
                  ? Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Tooltip(
                        message: stockAdjustmentTooltip,
                        waitDuration: const Duration(milliseconds: 150),
                        showDuration: const Duration(seconds: 6),
                        preferBelow: false,
                        child: Material(
                          color: theme.colorScheme.primary.withOpacity(0.12),
                          shape: const CircleBorder(),
                          child: IconButton(
                            tooltip: 'Registrar ajuste de stock',
                            onPressed: _isApplyingStockAdjustment
                                ? null
                                : _handleStockAdjustment,
                            color: theme.colorScheme.primary,
                            splashRadius: 20,
                            icon: _isApplyingStockAdjustment
                                ? SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: theme.colorScheme.primary,
                                    ),
                                  )
                                : const Icon(
                                    Icons.playlist_add_check_circle,
                                    size: 20,
                                  ),
                          ),
                        ),
                      ),
                    )
                  : null,
            ),
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
            ],
          );

          final children = [
            Expanded(
              flex: isMobile ? 0 : 1,
              child: stockField,
            ),
            SizedBox(width: 16, height: isMobile ? 16 : 0),
            Expanded(
              flex: isMobile ? 0 : 1,
              child: TextFormField(
                controller: _minStockController,
                decoration: const InputDecoration(
                  labelText: 'Stock mínimo',
                ),
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                ],
              ),
            ),
          ];

          return isMobile
              ? Column(
                  children: children
                      .map((w) => w is Expanded
                          ? SizedBox(width: double.infinity, child: w.child)
                          : w)
                      .toList(),
                )
              : Row(children: children);
        },
      ),
    ];
  }

  List<Widget> _buildStatusFields(ThemeData theme) {
    return [
      // Toggle 1: Product Active (base toggle)
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Producto activo'),
        subtitle: const Text(
          'Los productos inactivos no aparecen en el POS ni en catálogos públicos.',
        ),
        value: _isActive,
        onChanged: (value) {
          setState(() {
            _isActive = value;
            // CASCADE: If deactivating, turn off all dependent toggles
            if (!_isActive) {
              _isPublished = false;
              _isGoogleMerchant = false;
            }
          });
        },
      ),
    ];
  }

  List<Widget> _buildWebsiteFields(ThemeData theme) {
    return [
      Text(
        'Configura la visibilidad y contenido del producto en la tienda online.',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      const SizedBox(height: 16),
      // Toggle: Published on Website (requires is_active)
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(
          'Publicado en la tienda online',
          style: TextStyle(
            color: _isActive ? null : theme.disabledColor,
          ),
        ),
        subtitle: Text(
          _isActive
              ? 'Muestra este producto en el catálogo web.'
              : 'Requiere que el producto esté activo.',
          style: TextStyle(
            color: _isActive ? null : theme.disabledColor,
          ),
        ),
        value: _isActive && _isPublished,
        onChanged: _isActive
            ? (value) {
                setState(() {
                  _isPublished = value;
                  // CASCADE: If unpublishing, turn off Google Merchant
                  if (!_isPublished) {
                    _isGoogleMerchant = false;
                  }
                });
              }
            : null,
      ),
      const SizedBox(height: 8),

      // Toggle: Google Merchant Center (requires is_published)
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Row(
          children: [
            Text(
              'Google Merchant Center',
              style: TextStyle(
                color: (_isActive && _isPublished) ? null : theme.disabledColor,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                'Shopping',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              ),
            ),
          ],
        ),
        subtitle: Text(
          !_isActive
              ? 'Requiere que el producto esté activo.'
              : !_isPublished
                  ? 'Requiere que el producto esté publicado en la tienda.'
                  : 'Incluye este producto en el feed de Google Shopping.',
          style: TextStyle(
            color: (_isActive && _isPublished) ? null : theme.disabledColor,
          ),
        ),
        value: _isActive && _isPublished && _isGoogleMerchant,
        onChanged: (_isActive && _isPublished)
            ? (value) => setState(() => _isGoogleMerchant = value)
            : null,
      ),
      const SizedBox(height: 16),
      const Divider(),
      const SizedBox(height: 16),
      TextFormField(
        controller: _websiteDescriptionController,
        decoration: const InputDecoration(
          labelText: 'Descripción para web',
          hintText:
              'Descripción optimizada para ventas online (SEO, marketing).',
          helperText:
              'Esta descripción se mostrará en la página del producto en la web.',
        ),
        maxLines: 6,
      ),
    ];
  }

  List<Widget> _buildSetConfigurationFields(ThemeData theme) {
    final price =
        double.tryParse(_priceController.text.replaceAll(',', '.')) ?? 0;
    final cost =
        double.tryParse(_costController.text.replaceAll(',', '.')) ?? 0;

    return [
      SetConfigurationWidget(
        isSet: _isSet,
        setType: _setType,
        components: _setComponents,
        onIsSetChanged: (value) => setState(() => _isSet = value),
        onSetTypeChanged: (value) => setState(() => _setType = value),
        onComponentsChanged: (value) => setState(() => _setComponents = value),
        parentProductName: _nameController.text.trim(),
        parentProductSku: _skuController.text.trim(),
        parentPrice: price,
        parentCost: cost,
      ),
    ];
  }

  List<Widget> _buildDescriptionFields(ThemeData theme) {
    return [
      TextFormField(
        controller: _descriptionController,
        decoration: const InputDecoration(
          labelText: 'Descripción detallada',
          hintText:
              'Materiales, especificaciones técnicas, beneficios y advertencias.',
        ),
        maxLines: 6,
      ),
    ];
  }

  List<Widget> _buildMediaFields(ThemeData theme) {
    return [
      AspectRatio(
        aspectRatio: 1,
        child: Stack(
          children: [
            Positioned.fill(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: _selectedImageBytes != null
                    ? Image.memory(
                        _selectedImageBytes!,
                        fit: BoxFit.cover,
                      )
                    : ImageService.buildProductImage(
                        imageUrl: _imageUrl,
                        size: double.infinity,
                        isListThumbnail: false,
                      ),
              ),
            ),
            Positioned(
              bottom: 12,
              left: 12,
              right: 12,
              child: FilledButton.icon(
                onPressed: _selectMainImage,
                icon: const Icon(Icons.upload_outlined),
                label: Text(
                  _selectedImageBytes != null || _imageUrl != null
                      ? 'Cambiar imagen principal'
                      : 'Agregar imagen',
                ),
              ),
            ),
            if (_selectedImageBytes != null || _imageUrl != null)
              Positioned(
                top: 8,
                right: 8,
                child: Material(
                  color: theme.colorScheme.errorContainer,
                  shape: const CircleBorder(),
                  child: IconButton(
                    onPressed: _clearMainImage,
                    icon: Icon(Icons.delete_outline,
                        color: theme.colorScheme.error),
                    tooltip: 'Quitar imagen',
                  ),
                ),
              ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Galería adicional',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          Text(
            '${_additionalImages.length} imágenes',
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
      const SizedBox(height: 12),
      Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          if (_isUploadingGalleryImage)
            SizedBox(
              width: 64,
              height: 64,
              child: Card(
                elevation: 0,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
            ),
          ..._additionalImages.map(
            (url) => Stack(
              clipBehavior: Clip.none,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox(
                    width: 68,
                    height: 68,
                    child: ImageService.buildProductImage(
                      imageUrl: url,
                      size: 68,
                      isListThumbnail: true,
                    ),
                  ),
                ),
                Positioned(
                  top: -8,
                  right: -8,
                  child: Material(
                    shape: const CircleBorder(),
                    color: Colors.black.withOpacity(0.6),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () => _removeGalleryImage(url),
                      child: const Padding(
                        padding: EdgeInsets.all(4),
                        child: Icon(
                          Icons.close,
                          size: 14,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          OutlinedButton.icon(
            onPressed: _isUploadingGalleryImage ? null : _addGalleryImage,
            icon: const Icon(Icons.add_photo_alternate_outlined),
            label: const Text('Agregar foto'),
          ),
        ],
      ),
    ];
  }
}

// Searchable Category Dialog
class _CategorySearchDialog extends StatefulWidget {
  final List<category_models.Category> categories;

  const _CategorySearchDialog({required this.categories});

  @override
  State<_CategorySearchDialog> createState() => _CategorySearchDialogState();
}

class _CategorySearchDialogState extends State<_CategorySearchDialog> {
  final TextEditingController _searchController = TextEditingController();
  List<category_models.Category> _filteredCategories = [];

  @override
  void initState() {
    super.initState();
    _filteredCategories = widget.categories;
    _searchController.addListener(_filterCategories);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _filterCategories() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      if (query.isEmpty) {
        _filteredCategories = widget.categories;
      } else {
        _filteredCategories = widget.categories
            .where((cat) => cat.fullPath.toLowerCase().contains(query))
            .toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final isMobile = MediaQuery.of(context).size.width < 600;

      return Dialog(
        insetPadding: isMobile
            ? const EdgeInsets.all(16)
            : const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
        child: Container(
          width: isMobile ? double.infinity : 500,
          height: 600,
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Seleccionar Categoría',
                      style:
                          TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // Search bar
              TextField(
                controller: _searchController,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: 'Buscar categoría',
                  hintText: 'Escriba para filtrar...',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _searchController.clear();
                            _filterCategories();
                          },
                        )
                      : null,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              // Results count
              Text(
                '${_filteredCategories.length} categoría${_filteredCategories.length != 1 ? 's' : ''} encontrada${_filteredCategories.length != 1 ? 's' : ''}',
                style: TextStyle(color: Colors.grey[600], fontSize: 12),
              ),
              const SizedBox(height: 8),
              const Divider(),
              // Category list
              Expanded(
                child: _filteredCategories.isEmpty
                    ? const Center(
                        child: Text(
                          'No se encontraron categorías',
                          style: TextStyle(color: Colors.grey),
                        ),
                      )
                    : ListView.builder(
                        itemCount: _filteredCategories.length,
                        itemBuilder: (context, index) {
                          final category = _filteredCategories[index];
                          final indent = category.level * 16.0;

                          return ListTile(
                            contentPadding: EdgeInsets.only(
                              left: 16 + indent,
                              right: 16,
                            ),
                            leading: Icon(
                              category.level == 0
                                  ? Icons.folder
                                  : Icons.subdirectory_arrow_right,
                              color: Theme.of(context).primaryColor,
                            ),
                            title: Text(
                              category.name,
                              style: TextStyle(
                                fontWeight: category.level == 0
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                            ),
                            subtitle: category.level > 0
                                ? Text(
                                    category.fullPath,
                                    style: const TextStyle(fontSize: 12),
                                  )
                                : null,
                            onTap: () => Navigator.pop(context, category),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      );
    });
  }
}
