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
import '../../bikeshop/config/brake_canonical_data.dart';
import '../../bikeshop/models/bikeshop_models.dart';
import '../../bikeshop/services/service_wizard_service.dart';
import '../../bikeshop/widgets/service_wizard_dialog.dart';

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

class _ServiceWorkflowProfile {
  const _ServiceWorkflowProfile({
    required this.id,
    required this.key,
    required this.name,
    required this.serviceFamily,
    this.description,
    this.customerSummaryTemplate,
    this.mechanicSummaryTemplate,
    this.targetFamily,
    this.targetPositionMode,
  });

  final String id;
  final String key;
  final String name;
  final String serviceFamily;
  final String? description;
  final String? customerSummaryTemplate;
  final String? mechanicSummaryTemplate;
  final String? targetFamily;
  final String? targetPositionMode;
}

class _WizardPreviewCustomerOption {
  const _WizardPreviewCustomerOption({
    required this.id,
    required this.name,
  });

  final String id;
  final String name;
}

class _ServiceWizardPreviewConfig {
  const _ServiceWizardPreviewConfig({
    required this.profile,
    required this.initialAnswers,
    required this.hiddenQuestionKeys,
    required this.helperText,
    this.contextSummary,
    this.questionOverrides = const <String, ServiceWizardQuestionOverride>{},
    this.diagnosisLinkedQuestionKeys = const <String>{},
  });

  final ServiceWizardProfile profile;
  final Map<String, dynamic> initialAnswers;
  final Set<String> hiddenQuestionKeys;
  final String? helperText;
  final ServiceWizardContextSummary? contextSummary;
  final Map<String, ServiceWizardQuestionOverride> questionOverrides;
  final Set<String> diagnosisLinkedQuestionKeys;
}

enum _ServiceWizardBackboneBucket {
  upstreamTruth,
  diagnosisTruth,
  targetExecution,
  reviewNeeded,
}

class _ServiceWizardQuestionSemantics {
  const _ServiceWizardQuestionSemantics({
    required this.bucket,
    required this.summary,
    required this.detail,
  });

  final _ServiceWizardBackboneBucket bucket;
  final String summary;
  final String detail;
}

final List<ServiceQuestionOption> _serviceWizardPreviewBrakeSymptomOptions =
    kBrakeSymptomLabels.entries
        .map(
          (entry) => ServiceQuestionOption(
            value: entry.key,
            label: entry.value,
          ),
        )
        .toList(growable: false);

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
    with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();

  late inventory_services.InventoryService _inventoryService;
  late CategoryService _categoryService;
  late PurchaseService _purchaseService;
  late BrandService _brandService;
  late BarcodeScannerService _barcodeScannerService;

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

  // Hardware keyboard scanner state (for USB/Bluetooth barcode scanners)
  final StringBuffer _scanBuffer = StringBuffer();
  Timer? _hwScanTimer;
  DateTime? _lastScanKeyTime;
  static const Duration _scanKeyTimeout = Duration(milliseconds: 100);
  static const int _minBarcodeLen = 3;

  // ── Ficha Técnica (Spec Engine) ──────────────────────────────────────────
  SpecTemplate? _specTemplate;
  Map<String, dynamic> _specValues = {};
  bool _isLoadingSpecs = false;

  List<_ServiceWorkflowProfile> _serviceProfiles = [];
  bool _isLoadingServiceProfiles = false;
  String? _selectedServiceProfileId;
  final Map<String, ServiceWizardProfile> _serviceWizardProfileCache = {};
  ServiceWizardProfile? _selectedServiceWizardProfile;
  bool _isLoadingSelectedServiceWizardProfile = false;

  List<_WizardPreviewCustomerOption> _wizardPreviewCustomers = [];
  List<Bike> _wizardPreviewBikes = [];
  String? _selectedWizardPreviewCustomerId;
  String? _selectedWizardPreviewBikeId;
  BikeProfile? _selectedWizardPreviewBikeProfile;
  BikeMemoryLocation _selectedWizardPreviewLocation = BikeMemoryLocation.none;
  ServiceWizardResult? _lastServiceWizardPreviewResult;
  bool _isLoadingWizardPreviewCustomers = false;
  bool _isLoadingWizardPreviewBikes = false;
  bool _isLoadingWizardPreviewBikeProfile = false;

  late TabController _tabController;
  final Set<TabController> _retiredTabControllers = <TabController>{};
  int _prevTabIndex = 0;

  @override
  void initState() {
    super.initState();
    _createTabController();
    _inventoryService = Provider.of<inventory_services.InventoryService>(
        context,
        listen: false);
    _categoryService = Provider.of<CategoryService>(context, listen: false);
    _purchaseService = Provider.of<PurchaseService>(context, listen: false);
    _brandService = Provider.of<BrandService>(context, listen: false);
    _barcodeScannerService = context.read<BarcodeScannerService>();

    _inventoryQtyController.text = '0';
    _minStockController.text = '1';

    _priceController.addListener(_onPricingChanged);
    _costController.addListener(_onPricingChanged);

    _loadBrands();
    _loadCategories();
    _loadSuppliers();
    unawaited(_loadServiceBackboneData());

    if (widget.productId != null) {
      _loadProduct();
    }

    // Remote scans arrive via the unified barcode stream.
    _scanSubscription = _barcodeScannerService.barcodeStream.listen((barcode) {
      if (mounted && ModalRoute.of(context)!.isCurrent) {
        _handleBarcodeScan(barcode);
      }
    });

    // HID scanning is also scoped to this form so barcode readers can fill the
    // SKU even while a text field is focused.
    HardwareKeyboard.instance.addHandler(_hardwareKeyHandler);
  }

  @override
  void dispose() {
    _tabController.removeListener(_handleTabControllerChanged);
    _tabController.dispose();
    for (final controller in _retiredTabControllers.toList()) {
      controller.dispose();
    }
    _retiredTabControllers.clear();
    _scanSubscription?.cancel();
    HardwareKeyboard.instance.removeHandler(_hardwareKeyHandler);
    _hwScanTimer?.cancel();
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

  int get _tabCount => _isServiceForm ? 4 : 3;

  void _createTabController({int initialIndex = 0}) {
    _tabController = TabController(
      length: _tabCount,
      vsync: this,
      initialIndex: initialIndex,
    );
    _prevTabIndex = initialIndex;
    _tabController.addListener(_handleTabControllerChanged);
  }

  void _handleTabControllerChanged() {
    if (_tabController.indexIsChanging) {
      return;
    }

    if (mounted) {
      setState(() => _prevTabIndex = _tabController.index);
    }

    if (_isServiceForm && _tabController.index == 3) {
      unawaited(_ensureServiceWizardPreviewSeedData());
    }
  }

  void _disposeRetiredTabController(TabController controller) {
    if (!_retiredTabControllers.remove(controller)) {
      return;
    }
    controller.dispose();
  }

  void _scheduleRetiredTabControllerDisposal(TabController controller) {
    _retiredTabControllers.add(controller);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _disposeRetiredTabController(controller);
    });
  }

  void _syncTabControllerForCurrentMode() {
    final desiredLength = _tabCount;
    final previousController = _tabController;
    if (previousController.length == desiredLength) {
      return;
    }

    final currentIndex = previousController.index;
    final safeIndex =
        currentIndex >= desiredLength ? desiredLength - 1 : currentIndex;

    previousController.removeListener(_handleTabControllerChanged);

    final nextController = TabController(
      length: desiredLength,
      vsync: this,
      initialIndex: safeIndex,
    );
    nextController.addListener(_handleTabControllerChanged);

    setState(() {
      _tabController = nextController;
      _prevTabIndex = safeIndex;
    });

    _scheduleRetiredTabControllerDisposal(previousController);
  }

  bool _hardwareKeyHandler(KeyEvent event) {
    if (!mounted) return false;
    if (!(ModalRoute.of(context)?.isCurrent ?? true)) return false;
    if (event is! KeyDownEvent) return false;

    final now = DateTime.now();
    if (_lastScanKeyTime != null &&
        now.difference(_lastScanKeyTime!) > _scanKeyTimeout) {
      _scanBuffer.clear();
    }
    _lastScanKeyTime = now;
    _hwScanTimer?.cancel();

    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape) {
      _scanBuffer.clear();
      return false;
    }

    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      final barcode = _scanBuffer.toString().trim();
      _scanBuffer.clear();
      if (barcode.length >= _minBarcodeLen) {
        _handleBarcodeScan(barcode);
      }
      return false;
    }

    final char = event.character;
    if (char != null && char.trim().isNotEmpty) {
      _scanBuffer.write(char);
      _hwScanTimer = Timer(_scanKeyTimeout, () {
        final barcode = _scanBuffer.toString().trim();
        _scanBuffer.clear();
        if (barcode.length >= _minBarcodeLen && mounted) {
          _handleBarcodeScan(barcode);
        }
      });
    }

    return false;
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
      final categoryId = result.id;
      if (categoryId == null || categoryId.isEmpty) {
        return;
      }
      final categoryChanged = _selectedCategoryId != categoryId;
      setState(() => _selectedCategoryId = categoryId);
      if (categoryChanged) {
        unawaited(
          _loadSpecTemplate(categoryId, productId: _existingProduct?.id),
        );
      }
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

  bool get _isServiceForm => _selectedProductType == ProductType.service;

  _ServiceWorkflowProfile? get _selectedServiceProfile {
    final selectedServiceProfileId = _selectedServiceProfileId;
    if (selectedServiceProfileId == null || selectedServiceProfileId.isEmpty) {
      return null;
    }

    for (final profile in _serviceProfiles) {
      if (profile.id == selectedServiceProfileId) {
        return profile;
      }
    }

    return null;
  }

  String get _selectedServiceProfileLabel {
    final profile = _selectedServiceProfile;
    if (profile == null) {
      return 'Sin perfil estructurado';
    }

    final family =
        _serviceFamilyLabel(profile.targetFamily ?? profile.serviceFamily);
    return '$family · ${profile.name}';
  }

  String get _defaultServiceClientDescription {
    final profile = _selectedServiceProfile;
    if (profile == null) {
      return _nameController.text.trim();
    }

    final summarized = _resolveServiceTemplate(
      profile.customerSummaryTemplate,
      fallback: profile.description ?? profile.name,
    );
    return summarized.isEmpty ? profile.name : summarized;
  }

  String get _defaultServiceMechanicSummary {
    final profile = _selectedServiceProfile;
    if (profile == null) {
      return _nameController.text.trim();
    }

    final summarized = _resolveServiceTemplate(
      profile.mechanicSummaryTemplate,
      fallback: profile.description ?? profile.name,
    );
    return summarized.isEmpty ? profile.name : summarized;
  }

  String get _defaultServiceWebsiteDescription {
    final profile = _selectedServiceProfile;
    final base = _defaultServiceClientDescription;
    if (profile == null) {
      return base;
    }

    final description = profile.description?.trim();
    if (description == null || description.isEmpty) {
      return base;
    }

    return '$base. $description';
  }

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
        if (product.productType != ProductType.service &&
            product.categoryId != null) {
          _loadSpecTemplate(product.categoryId!, productId: product.id);
        } else {
          _specTemplate = null;
          _specValues = {};
        }

        unawaited(_loadConversionStatus(product.id));
        unawaited(
          _loadServiceBackboneData(
            productId: product.id,
            tenantId: product.tenantId,
          ),
        );
        _syncTabControllerForCurrentMode();
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

  Future<void> _loadServiceBackboneData({
    String? productId,
    String? tenantId,
  }) async {
    final resolvedTenantId = tenantId ?? await TenantService().getTenantId();
    if (resolvedTenantId == null) {
      return;
    }

    if (mounted) {
      setState(() => _isLoadingServiceProfiles = true);
    }

    try {
      final client = Supabase.instance.client;
      final rawProfiles = await client
          .from('service_profiles')
          .select(
            'id, key, name, service_family, description, customer_summary_template, mechanic_summary_template',
          )
          .or('tenant_id.is.null,tenant_id.eq.$resolvedTenantId')
          .eq('is_active', true)
          .order('service_family')
          .order('name');

      final rawTargets = await client
          .from('service_profile_targets')
          .select('service_profile_id, target_family, target_position_mode')
          .or('tenant_id.is.null,tenant_id.eq.$resolvedTenantId');

      String? mappedProfileId = _selectedServiceProfileId;
      if (productId != null && productId.isNotEmpty) {
        final mapping = await client
            .from('service_product_profile_mappings')
            .select('service_profile_id')
            .eq('tenant_id', resolvedTenantId)
            .eq('product_id', productId)
            .eq('status', 'active')
            .maybeSingle();
        mappedProfileId = mapping?['service_profile_id']?.toString();
      }

      final targetsByProfileId = <String, Map<String, dynamic>>{};
      for (final raw in rawTargets as List) {
        final row = Map<String, dynamic>.from(raw as Map);
        final serviceProfileId = row['service_profile_id']?.toString();
        if (serviceProfileId == null || serviceProfileId.isEmpty) {
          continue;
        }

        targetsByProfileId.putIfAbsent(serviceProfileId, () => row);
      }

      final profiles = (rawProfiles as List)
          .map((raw) {
            final row = Map<String, dynamic>.from(raw as Map);
            final profileId = row['id']?.toString() ?? '';
            final targetRow = targetsByProfileId[profileId];
            return _ServiceWorkflowProfile(
              id: profileId,
              key: row['key']?.toString() ?? '',
              name: row['name']?.toString() ?? '',
              serviceFamily: row['service_family']?.toString() ?? 'general',
              description: row['description']?.toString(),
              customerSummaryTemplate:
                  row['customer_summary_template']?.toString(),
              mechanicSummaryTemplate:
                  row['mechanic_summary_template']?.toString(),
              targetFamily: targetRow?['target_family']?.toString(),
              targetPositionMode:
                  targetRow?['target_position_mode']?.toString(),
            );
          })
          .where((profile) => profile.id.isNotEmpty)
          .toList(growable: false);

      if (!mounted) return;
      setState(() {
        _serviceProfiles = profiles;
        if (mappedProfileId != null && mappedProfileId.isNotEmpty) {
          _selectedServiceProfileId = mappedProfileId;
        } else if (_selectedServiceProfileId != null &&
            !_serviceProfiles.any(
              (profile) => profile.id == _selectedServiceProfileId,
            )) {
          _selectedServiceProfileId = null;
        }
      });

      _syncPreviewLocationForSelectedServiceProfile();
      await _loadSelectedServiceWizardProfile();
    } catch (e) {
      if (kDebugMode) {
        print('Error cargando backbone de servicios: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isLoadingServiceProfiles = false);
      }
    }
  }

  Future<void> _loadSelectedServiceWizardProfile() async {
    final workflowProfile = _selectedServiceProfile;
    final profileId = workflowProfile?.id;
    if (profileId == null || profileId.isEmpty) {
      if (mounted) {
        setState(() {
          _selectedServiceWizardProfile = null;
          _resetServiceWizardPreviewResult();
        });
      }
      return;
    }

    final cached = _serviceWizardProfileCache[profileId];
    if (cached != null) {
      if (mounted) {
        setState(() {
          _selectedServiceWizardProfile = cached;
          _resetServiceWizardPreviewResult();
        });
      }
      return;
    }

    if (mounted) {
      setState(() => _isLoadingSelectedServiceWizardProfile = true);
    }

    try {
      final rawQuestions = await Supabase.instance.client
          .from('service_profile_questions')
          .select()
          .eq('service_profile_id', profileId)
          .order('sort_order');

      final fullProfile = ServiceWizardService.normalizeProfile(
        ServiceWizardProfile(
          id: workflowProfile!.id,
          name: workflowProfile.name,
          serviceFamily: workflowProfile.serviceFamily,
          customerSummaryTemplate: workflowProfile.customerSummaryTemplate,
          questions: (rawQuestions as List)
              .map(
                (raw) => ServiceProfileQuestion.fromJson(
                  Map<String, dynamic>.from(raw as Map),
                ),
              )
              .toList(growable: false),
        ),
      );

      if (fullProfile == null) {
        return;
      }

      _serviceWizardProfileCache[profileId] = fullProfile;
      if (!mounted || _selectedServiceProfileId != profileId) {
        return;
      }

      setState(() {
        _selectedServiceWizardProfile = fullProfile;
        _resetServiceWizardPreviewResult();
      });
    } catch (e) {
      if (kDebugMode) {
        print('Error cargando perfil completo del wizard: $e');
      }
    } finally {
      if (mounted && _selectedServiceProfileId == profileId) {
        setState(() => _isLoadingSelectedServiceWizardProfile = false);
      }
    }
  }

  Future<void> _ensureServiceWizardPreviewSeedData() async {
    if (_wizardPreviewCustomers.isEmpty && !_isLoadingWizardPreviewCustomers) {
      await _loadWizardPreviewCustomers();
    }

    if (_selectedServiceProfile != null &&
        _selectedServiceWizardProfile == null &&
        !_isLoadingSelectedServiceWizardProfile) {
      await _loadSelectedServiceWizardProfile();
    }
  }

  Future<void> _loadWizardPreviewCustomers() async {
    final tenantId = await TenantService().getTenantId();
    if (tenantId == null) {
      return;
    }

    if (mounted) {
      setState(() => _isLoadingWizardPreviewCustomers = true);
    }

    try {
      final rawCustomers = await Supabase.instance.client
          .from('customers')
          .select('id, name')
          .eq('tenant_id', tenantId)
          .eq('is_active', true)
          .order('name');

      final customers = (rawCustomers as List)
          .map(
            (raw) => Map<String, dynamic>.from(raw as Map),
          )
          .map(
            (row) => _WizardPreviewCustomerOption(
              id: row['id']?.toString() ?? '',
              name: row['name']?.toString() ?? 'Cliente sin nombre',
            ),
          )
          .where((customer) => customer.id.isNotEmpty)
          .toList(growable: false);

      if (!mounted) {
        return;
      }

      setState(() {
        _wizardPreviewCustomers = customers;
        if (_selectedWizardPreviewCustomerId != null &&
            !_wizardPreviewCustomers.any(
              (customer) => customer.id == _selectedWizardPreviewCustomerId,
            )) {
          _selectedWizardPreviewCustomerId = null;
          _wizardPreviewBikes = [];
          _selectedWizardPreviewBikeId = null;
          _selectedWizardPreviewBikeProfile = null;
          _resetServiceWizardPreviewResult();
        }
      });
    } catch (e) {
      if (kDebugMode) {
        print('Error cargando clientes para el tester del wizard: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isLoadingWizardPreviewCustomers = false);
      }
    }
  }

  Future<void> _loadWizardPreviewBikes(String? customerId) async {
    final tenantId = await TenantService().getTenantId();
    if (tenantId == null || customerId == null || customerId.isEmpty) {
      if (mounted) {
        setState(() {
          _wizardPreviewBikes = [];
          _selectedWizardPreviewBikeId = null;
          _selectedWizardPreviewBikeProfile = null;
          _resetServiceWizardPreviewResult();
        });
      }
      return;
    }

    if (mounted) {
      setState(() => _isLoadingWizardPreviewBikes = true);
    }

    try {
      final rawBikes = await Supabase.instance.client
          .from('bikes')
          .select()
          .eq('tenant_id', tenantId)
          .eq('customer_id', customerId)
          .eq('is_active', true)
          .order('created_at', ascending: false);

      final bikes = (rawBikes as List)
          .map(
            (raw) => Bike.fromJson(Map<String, dynamic>.from(raw as Map)),
          )
          .toList(growable: false);

      if (!mounted) {
        return;
      }

      setState(() {
        _wizardPreviewBikes = bikes;
        if (_selectedWizardPreviewBikeId != null &&
            !_wizardPreviewBikes.any(
              (bike) => bike.id == _selectedWizardPreviewBikeId,
            )) {
          _selectedWizardPreviewBikeId = null;
          _selectedWizardPreviewBikeProfile = null;
          _resetServiceWizardPreviewResult();
        }
      });
    } catch (e) {
      if (kDebugMode) {
        print('Error cargando bicicletas para el tester del wizard: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isLoadingWizardPreviewBikes = false);
      }
    }
  }

  Future<void> _loadWizardPreviewBikeProfile(String? bikeId) async {
    if (bikeId == null || bikeId.isEmpty) {
      if (mounted) {
        setState(() {
          _selectedWizardPreviewBikeProfile = null;
          _resetServiceWizardPreviewResult();
        });
      }
      return;
    }

    if (mounted) {
      setState(() => _isLoadingWizardPreviewBikeProfile = true);
    }

    try {
      final rawProfile = await Supabase.instance.client
          .from('bike_profiles')
          .select()
          .eq('bike_id', bikeId)
          .maybeSingle();

      if (!mounted || _selectedWizardPreviewBikeId != bikeId) {
        return;
      }

      setState(() {
        _selectedWizardPreviewBikeProfile = rawProfile == null
            ? null
            : BikeProfile.fromJson(Map<String, dynamic>.from(rawProfile));
        _resetServiceWizardPreviewResult();
      });
    } catch (e) {
      if (kDebugMode) {
        print('Error cargando ficha técnica de la bici del tester: $e');
      }
    } finally {
      if (mounted && _selectedWizardPreviewBikeId == bikeId) {
        setState(() => _isLoadingWizardPreviewBikeProfile = false);
      }
    }
  }

  void _handleWizardPreviewCustomerChanged(String? customerId) {
    final normalizedId = customerId?.trim();
    setState(() {
      _selectedWizardPreviewCustomerId =
          normalizedId == null || normalizedId.isEmpty ? null : normalizedId;
      _wizardPreviewBikes = [];
      _selectedWizardPreviewBikeId = null;
      _selectedWizardPreviewBikeProfile = null;
      _resetServiceWizardPreviewResult();
    });

    unawaited(_loadWizardPreviewBikes(_selectedWizardPreviewCustomerId));
  }

  void _handleWizardPreviewBikeChanged(String? bikeId) {
    final normalizedId = bikeId?.trim();
    setState(() {
      _selectedWizardPreviewBikeId =
          normalizedId == null || normalizedId.isEmpty ? null : normalizedId;
      _selectedWizardPreviewBikeProfile = null;
      _resetServiceWizardPreviewResult();
    });

    unawaited(_loadWizardPreviewBikeProfile(_selectedWizardPreviewBikeId));
  }

  void _handleWizardPreviewLocationChanged(BikeMemoryLocation location) {
    if (_selectedWizardPreviewLocation == location) {
      return;
    }

    setState(() {
      _selectedWizardPreviewLocation = location;
      _resetServiceWizardPreviewResult();
    });
  }

  void _syncPreviewLocationForSelectedServiceProfile() {
    if (_selectedServiceProfile?.targetPositionMode == 'front_rear') {
      return;
    }

    _selectedWizardPreviewLocation = BikeMemoryLocation.none;
  }

  void _resetServiceWizardPreviewResult() {
    _lastServiceWizardPreviewResult = null;
  }

  Future<void> _syncServiceProfileMapping({
    required String tenantId,
    required String productId,
  }) async {
    final client = Supabase.instance.client;
    final selectedProfileId =
        _isServiceForm ? _selectedServiceProfileId?.trim() : null;
    final normalizedSelectedProfileId =
        (selectedProfileId == null || selectedProfileId.isEmpty)
            ? null
            : selectedProfileId;

    final activeRows = await client
        .from('service_product_profile_mappings')
        .select('id, service_profile_id')
        .eq('tenant_id', tenantId)
        .eq('product_id', productId)
        .eq('status', 'active');

    final activeMappings = (activeRows as List)
        .map((raw) => Map<String, dynamic>.from(raw as Map))
        .toList(growable: false);

    var hasActiveSelectedMapping = false;
    for (final mapping in activeMappings) {
      final mappingId = mapping['id']?.toString();
      final mappingProfileId = mapping['service_profile_id']?.toString();
      if (mappingId == null || mappingId.isEmpty) {
        continue;
      }

      if (normalizedSelectedProfileId != null &&
          mappingProfileId == normalizedSelectedProfileId) {
        hasActiveSelectedMapping = true;
        continue;
      }

      await client
          .from('service_product_profile_mappings')
          .update({'status': 'inactive'}).eq('id', mappingId);
    }

    if (normalizedSelectedProfileId == null || hasActiveSelectedMapping) {
      return;
    }

    final existingInactive = await client
        .from('service_product_profile_mappings')
        .select('id')
        .eq('tenant_id', tenantId)
        .eq('product_id', productId)
        .eq('service_profile_id', normalizedSelectedProfileId)
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();

    final inactiveId = existingInactive?['id']?.toString();
    if (inactiveId != null && inactiveId.isNotEmpty) {
      await client
          .from('service_product_profile_mappings')
          .update({'status': 'active'}).eq('id', inactiveId);
      return;
    }

    await client.from('service_product_profile_mappings').insert({
      'tenant_id': tenantId,
      'product_id': productId,
      'service_profile_id': normalizedSelectedProfileId,
      'status': 'active',
    });
  }

  String _resolveServiceTemplate(String? template, {String fallback = ''}) {
    var text = template?.trim() ?? fallback.trim();
    if (text.isEmpty) {
      return '';
    }

    final targetPositionMode = _selectedServiceProfile?.targetPositionMode;
    final replacements = <String, String>{
      'which_wheel':
          targetPositionMode == 'front_rear' ? 'delantero/trasero' : 'general',
      'brake_type': 'según sistema',
      'fluid_type': 'según sistema',
      'damage_level': 'según diagnóstico',
      'contamination_level': 'según diagnóstico',
      'pad_condition': 'según revisión',
      'symptom': 'según diagnóstico',
      'replace_seals': 'según revisión',
    };

    replacements.forEach((key, value) {
      text = text.replaceAll('{{$key}}', value);
    });
    text = text.replaceAll(RegExp(r'{{[^}]+}}'), '');
    text = text.replaceAll(RegExp(r'\s+'), ' ');
    text = text.replaceAll(RegExp(r'\s+,\s+'), ', ');
    text = text.replaceAll(RegExp(r'\s+\.\s*'), '. ');
    text = text.replaceAll(RegExp(r'\s+·\s+'), ' · ');
    text = text.replaceAll(RegExp(r'\s+:\s+'), ': ');
    text = text.replaceAll(RegExp(r'\s+/\s+'), '/');
    text = text.trim();

    if (text.endsWith(',')) {
      text = text.substring(0, text.length - 1).trim();
    }

    return text;
  }

  String _serviceFamilyLabel(String? value) {
    switch (value) {
      case 'brake':
        return 'Frenos';
      case 'drivetrain':
        return 'Transmisión';
      case 'wheels':
        return 'Ruedas';
      case 'suspension':
        return 'Suspensión';
      case 'cockpit':
        return 'Cockpit';
      case 'general':
      case 'none':
      case null:
      case '':
        return 'General';
      default:
        return value.replaceAll('_', ' ');
    }
  }

  String _servicePositionModeLabel(String? value) {
    switch (value) {
      case 'front_rear':
        return 'Delantero / trasero';
      case 'single':
        return 'Un solo componente';
      case 'none':
      case null:
      case '':
        return 'Sin posición obligatoria';
      default:
        return value.replaceAll('_', ' ');
    }
  }

  String _serviceFamilyCode(String? value) {
    switch (value) {
      case 'brake':
        return 'BRK';
      case 'drivetrain':
        return 'DRT';
      case 'wheels':
        return 'WHL';
      case 'suspension':
        return 'SUS';
      case 'cockpit':
        return 'CKP';
      default:
        return 'GEN';
    }
  }

  String _serviceOperationCode(String key) {
    final parts = key
        .split(RegExp(r'[_\-\s]+'))
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList(growable: false);
    if (parts.isEmpty) {
      return 'GEN';
    }

    final code =
        parts.take(3).map((part) => part.substring(0, 1).toUpperCase()).join();
    return code.padRight(2, 'X');
  }

  String _buildServiceSkuPrefix([_ServiceWorkflowProfile? profile]) {
    final currentProfile = profile ?? _selectedServiceProfile;
    if (currentProfile == null) {
      return 'SRV-GEN-GEN';
    }

    final familyCode = _serviceFamilyCode(
        currentProfile.targetFamily ?? currentProfile.serviceFamily);
    final operationCode = _serviceOperationCode(currentProfile.key);
    return 'SRV-$familyCode-$operationCode';
  }

  bool _looksLikeGeneratedServiceSku(String sku) {
    return RegExp(r'^SRV-[A-Z0-9]+-[A-Z0-9]+-\d{3}$')
        .hasMatch(sku.trim().toUpperCase());
  }

  Future<void> _generateServiceSku({bool autoTriggered = false}) async {
    if (mounted) {
      setState(() => _isGeneratingSku = true);
    }

    try {
      final prefix = _buildServiceSkuPrefix();
      final products = await _inventoryService.getProducts(forceRefresh: true);
      final pattern = RegExp('^${RegExp.escape(prefix)}-(\\d{3})\$');
      var maxSequence = 0;

      for (final product in products) {
        if (product.productType != ProductType.service) {
          continue;
        }

        final match = pattern.firstMatch(product.sku.trim().toUpperCase());
        if (match == null) {
          continue;
        }

        final sequence = int.tryParse(match.group(1) ?? '0') ?? 0;
        if (sequence > maxSequence) {
          maxSequence = sequence;
        }
      }

      if (!mounted) return;
      setState(() {
        _skuController.text =
            '$prefix-${(maxSequence + 1).toString().padLeft(3, '0')}';
      });
    } catch (e) {
      if (!mounted || autoTriggered) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo generar el código del servicio: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isGeneratingSku = false);
      }
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
    if (_isServiceForm) {
      await _generateServiceSku(autoTriggered: autoTriggered);
      return;
    }

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
                              .withValues(alpha: 0.45),
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
                          .withValues(alpha: 0.45),
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
        color:
            theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _canRestoreOriginalState
              ? theme.colorScheme.primary.withValues(alpha: 0.25)
              : theme.dividerColor.withValues(alpha: 0.3),
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
    final borderColor = theme.dividerColor.withValues(alpha: 0.35);

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
          color:
              theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
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
        color:
            theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
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
                        .withValues(alpha: 0.45),
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
        _selectedCategoryId = null;
        _specTemplate = null;
        _specValues = {};
        _isGoogleMerchant = false;
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

      if (value != ProductType.service) {
        _resetServiceWizardPreviewResult();
      }
    });

    _syncTabControllerForCurrentMode();

    if (value == ProductType.service) {
      if (_serviceProfiles.isEmpty && !_isLoadingServiceProfiles) {
        unawaited(_loadServiceBackboneData());
      }
      if (_selectedServiceProfile != null &&
          _descriptionController.text.trim().isEmpty) {
        _descriptionController.text = _defaultServiceClientDescription;
      }
      if (_skuController.text.trim().isEmpty) {
        unawaited(_generateSku(autoTriggered: true));
      }
      unawaited(_ensureServiceWizardPreviewSeedData());
    }
  }

  void _handleServiceProfileChanged(String? value) {
    final normalizedValue = value?.trim();
    final nextValue = (normalizedValue == null || normalizedValue.isEmpty)
        ? null
        : normalizedValue;
    final currentSku = _skuController.text.trim();
    final shouldRefreshSku =
        currentSku.isEmpty || _looksLikeGeneratedServiceSku(currentSku);

    setState(() => _selectedServiceProfileId = nextValue);
    _syncPreviewLocationForSelectedServiceProfile();
    _resetServiceWizardPreviewResult();

    if (_descriptionController.text.trim().isEmpty) {
      _descriptionController.text = _defaultServiceClientDescription;
    }
    if (_websiteDescriptionController.text.trim().isEmpty) {
      _websiteDescriptionController.text = _defaultServiceWebsiteDescription;
    }
    if (shouldRefreshSku) {
      unawaited(_generateSku(autoTriggered: true));
    }

    unawaited(_loadSelectedServiceWizardProfile());
  }

  void _applySuggestedServiceDescription() {
    final suggestion = _defaultServiceClientDescription;
    if (suggestion.isEmpty) {
      return;
    }

    setState(() {
      _descriptionController.text = suggestion;
    });
  }

  void _applySuggestedWebsiteDescription() {
    final suggestion = _defaultServiceWebsiteDescription;
    if (suggestion.isEmpty) {
      return;
    }

    setState(() {
      _websiteDescriptionController.text = suggestion;
    });
  }

  _WizardPreviewCustomerOption? get _selectedWizardPreviewCustomer {
    final selectedId = _selectedWizardPreviewCustomerId;
    if (selectedId == null || selectedId.isEmpty) {
      return null;
    }

    for (final customer in _wizardPreviewCustomers) {
      if (customer.id == selectedId) {
        return customer;
      }
    }

    return null;
  }

  Bike? get _selectedWizardPreviewBike {
    final selectedId = _selectedWizardPreviewBikeId;
    if (selectedId == null || selectedId.isEmpty) {
      return null;
    }

    for (final bike in _wizardPreviewBikes) {
      if (bike.id == selectedId) {
        return bike;
      }
    }

    return null;
  }

  String? _normalizeNullableText(String value) {
    final normalized = value.trim();
    return normalized.isEmpty ? null : normalized;
  }

  bool _isBrakeServiceFamily(String? family) {
    return family == 'brake' || family == 'brakes';
  }

  bool _isDiscBrakeType(String? rawValue) {
    return rawValue == 'mechanical_disc' || rawValue == 'hydraulic_disc';
  }

  String _formatBrakeType(String rawValue) {
    switch (rawValue) {
      case 'rim':
        return 'llanta';
      case 'mechanical_disc':
        return 'disco mecánico';
      case 'hydraulic_disc':
        return 'disco hidráulico';
      case 'roller_brake':
        return 'roller brake';
      case 'drum_brake':
        return 'tambor';
      case 'coaster_brake':
        return 'contrapedal';
      case 'band_brake':
        return 'banda';
      default:
        return rawValue;
    }
  }

  String? _formatRimBrakeFamily(String? rawValue) {
    switch (rawValue) {
      case 'v_brake':
        return 'V-Brake';
      case 'cantilever':
        return 'Cantilever';
      case 'road_caliper_short_reach':
        return 'caliper ruta corto';
      case 'road_caliper_long_reach':
        return 'caliper ruta largo';
      case 'u_brake':
        return 'U-Brake';
      case 'rod_brake':
        return 'freno de varilla';
      case 'other':
        return 'otro sistema de llanta';
      case 'unknown':
        return 'familia de llanta no confirmada';
      default:
        return rawValue;
    }
  }

  String _formatBrakeSystemDetail(
    String? rawBrakeType,
    String? rawRimBrakeFamily,
  ) {
    if (rawBrakeType == null || rawBrakeType.isEmpty) {
      return 'desconocido';
    }

    if (rawBrakeType == 'rim') {
      final rimBrakeFamily = _formatRimBrakeFamily(rawRimBrakeFamily);
      if (rimBrakeFamily != null && rimBrakeFamily.isNotEmpty) {
        return 'de llanta ($rimBrakeFamily)';
      }
    }

    return _formatBrakeType(rawBrakeType);
  }

  String? _firstMatchingWizardOption(
    ServiceProfileQuestion? question,
    List<String> candidates,
  ) {
    if (question == null) {
      return null;
    }

    final options = question.options.map((option) => option.value).toSet();
    for (final candidate in candidates) {
      if (options.contains(candidate)) {
        return candidate;
      }
    }

    return null;
  }

  String? _wizardLocationAnswer(
    ServiceProfileQuestion? question,
    BikeMemoryLocation location,
  ) {
    switch (location) {
      case BikeMemoryLocation.front:
        return _firstMatchingWizardOption(
          question,
          const ['front', 'delantero'],
        );
      case BikeMemoryLocation.rear:
        return _firstMatchingWizardOption(
          question,
          const ['rear', 'trasero'],
        );
      case BikeMemoryLocation.left:
        return _firstMatchingWizardOption(
          question,
          const ['left', 'izquierdo'],
        );
      case BikeMemoryLocation.right:
        return _firstMatchingWizardOption(
          question,
          const ['right', 'derecho'],
        );
      case BikeMemoryLocation.center:
        return _firstMatchingWizardOption(
          question,
          const ['center', 'centro'],
        );
      case BikeMemoryLocation.none:
        return null;
    }
  }

  String? _mappedRimBrakeFamilyWizardAnswer(
    String? rawRimBrakeFamily,
    ServiceProfileQuestion? question,
  ) {
    if (question == null ||
        rawRimBrakeFamily == null ||
        rawRimBrakeFamily.isEmpty) {
      return null;
    }

    final hints = switch (rawRimBrakeFamily) {
      'v_brake' => const ['v-brake', 'v brake', 'vbrake'],
      'cantilever' => const ['cantilever', 'canti'],
      'road_caliper_short_reach' => const [
          'short reach',
          'caliper corto',
          'caliper',
          'ruta'
        ],
      'road_caliper_long_reach' => const [
          'long reach',
          'caliper largo',
          'caliper',
          'ruta'
        ],
      'u_brake' => const ['u-brake', 'u brake', 'ubrake'],
      'rod_brake' => const ['varilla', 'rod brake'],
      _ => const <String>[],
    };

    if (hints.isEmpty) {
      return null;
    }

    return _firstMatchingWizardOption(question, hints);
  }

  String? _mappedBrakeTypeWizardAnswer(
    String? rawBrakeType,
    String? rawRimBrakeFamily,
    ServiceProfileQuestion? question,
  ) {
    if (question == null || rawBrakeType == null || rawBrakeType.isEmpty) {
      return null;
    }

    switch (rawBrakeType) {
      case 'hydraulic_disc':
        return _firstMatchingWizardOption(question, const ['hidraulico']);
      case 'mechanical_disc':
        return _firstMatchingWizardOption(question, const ['mecanico']);
      case 'rim':
        final exactFamily = _mappedRimBrakeFamilyWizardAnswer(
          rawRimBrakeFamily,
          question,
        );
        if (exactFamily != null) {
          return exactFamily;
        }
        if (rawRimBrakeFamily == null ||
            rawRimBrakeFamily.isEmpty ||
            rawRimBrakeFamily == 'unknown') {
          final genericRim = _firstMatchingWizardOption(
            question,
            const ['llanta', 'rim'],
          );
          if (genericRim != null) {
            return genericRim;
          }
          return _firstMatchingWizardOption(question, const ['mecanico']);
        }
        return null;
      case 'roller_brake':
        return _firstMatchingWizardOption(question, const ['roller']);
      case 'drum_brake':
        return _firstMatchingWizardOption(question, const ['tambor', 'drum']);
      case 'coaster_brake':
        return _firstMatchingWizardOption(
          question,
          const ['contrapedal', 'coaster'],
        );
      case 'band_brake':
        return _firstMatchingWizardOption(question, const ['banda', 'band']);
      default:
        return null;
    }
  }

  String? _mappedMechanicalBrakeTypeWizardAnswer(
    String? rawBrakeType,
    String? rawRimBrakeFamily,
    ServiceProfileQuestion? question,
  ) {
    if (question == null || rawBrakeType == null || rawBrakeType.isEmpty) {
      return null;
    }

    switch (rawBrakeType) {
      case 'mechanical_disc':
        return _firstMatchingWizardOption(
          question,
          const ['disco_mec', 'mecanico'],
        );
      case 'rim':
        return _mappedRimBrakeFamilyWizardAnswer(rawRimBrakeFamily, question);
      default:
        return null;
    }
  }

  bool _needsRimBrakeFamilyConfirmation(
    String? rawBrakeType,
    String? rawRimBrakeFamily,
  ) {
    return rawBrakeType == 'rim' &&
        (rawRimBrakeFamily == null ||
            rawRimBrakeFamily.isEmpty ||
            rawRimBrakeFamily == 'unknown');
  }

  String? _mappedRotorSizeWizardAnswer(
    ServiceProfileQuestion? question,
    Map<String, dynamic> technicalValues,
    BikeMemoryLocation location,
  ) {
    if (question == null) {
      return null;
    }

    final rawValue = switch (location) {
      BikeMemoryLocation.front => technicalValues['frontRotorSizeMm'],
      BikeMemoryLocation.rear => technicalValues['rearRotorSizeMm'],
      _ => null,
    };
    if (rawValue == null) {
      return null;
    }

    final normalized = rawValue.toString().trim();
    return _firstMatchingWizardOption(question, [normalized]);
  }

  List<String>? _mappedDerailleursWizardAnswer(
    String? drivetrainConfig,
    ServiceProfileQuestion? question,
  ) {
    if (question == null || question.questionType != 'multi_select') {
      return null;
    }

    final normalized = drivetrainConfig?.trim().toLowerCase();
    if (normalized == null || normalized.isEmpty) {
      return null;
    }

    final options = question.options.map((option) => option.value).toSet();
    if (!(options.contains('front') && options.contains('rear'))) {
      return null;
    }

    if (normalized.startsWith('2x') || normalized.startsWith('3x')) {
      return const ['front', 'rear'];
    }

    return null;
  }

  String? _buildDrivetrainProfileHint(Map<String, dynamic> technicalValues) {
    final config = _normalizeNullableText(
      technicalValues['drivetrainConfig']?.toString() ?? '',
    );
    final speeds = _normalizeNullableText(
      technicalValues['drivetrainSpeeds']?.toString() ?? '',
    );

    final parts = <String>[];
    if (config != null) {
      parts.add(config);
    }
    if (speeds != null) {
      parts.add('${speeds}v');
    }

    if (parts.isEmpty) {
      return null;
    }

    return parts.join(' · ');
  }

  _ServiceWizardPreviewConfig? _buildServiceWizardPreviewConfig() {
    final profile = _selectedServiceWizardProfile;
    if (profile == null) {
      return null;
    }

    final bike = _selectedWizardPreviewBike;
    final technicalValues =
        _selectedWizardPreviewBikeProfile?.technicalValues ??
            const <String, dynamic>{};
    final questionsByKey = {
      for (final question in profile.questions) question.key: question,
    };
    final initialAnswers = ServiceWizardService.normalizeAnswersForProfile(
      profile,
      const <String, dynamic>{},
    );
    final hiddenQuestionKeys = <String>{};
    final questionOverrides = <String, ServiceWizardQuestionOverride>{};
    final diagnosisLinkedQuestionKeys = <String>{};
    ServiceWizardContextSummary? contextSummary;

    final wheelAnswer = _wizardLocationAnswer(
      questionsByKey['which_wheel'],
      _selectedWizardPreviewLocation,
    );
    if (wheelAnswer != null) {
      initialAnswers['which_wheel'] = wheelAnswer;
    }

    String? helperText;
    if (_isBrakeServiceFamily(profile.serviceFamily)) {
      diagnosisLinkedQuestionKeys
          .addAll(kDiagnosisLinkedBrakeWizardQuestionKeys);
      if (_selectedWizardPreviewLocation != BikeMemoryLocation.none) {
        hiddenQuestionKeys.add('which_wheel');
      }

      final rawBrakeType = technicalValues['brakeType']?.toString();
      final rawRimBrakeFamily = technicalValues['rimBrakeFamily']?.toString();
      questionOverrides['symptom'] = ServiceWizardQuestionOverride(
        label: 'Síntomas observados',
        helperText:
            'Usa la misma lista del diagnóstico del freno para que el preview replique la base estructurada del taller.',
        options: _serviceWizardPreviewBrakeSymptomOptions,
      );

      final bikeLabel = bike?.displayName ?? 'Sin bici seleccionada';
      final bikeTypeLabel = bike?.bikeType?.displayName;
      final targetLabel = switch (_selectedWizardPreviewLocation) {
        BikeMemoryLocation.front => 'Freno delantero',
        BikeMemoryLocation.rear => 'Freno trasero',
        _ => 'Servicio de freno',
      };
      final needsRimBrakeFamilyConfirmation =
          _needsRimBrakeFamilyConfirmation(rawBrakeType, rawRimBrakeFamily);
      contextSummary = ServiceWizardContextSummary(
        title: bikeLabel,
        subtitle: targetLabel,
        chips: [
          if (bikeTypeLabel != null && bikeTypeLabel.isNotEmpty)
            ServiceWizardContextChip(
              icon: Icons.directions_bike_outlined,
              label: 'Tipo de bici: $bikeTypeLabel',
            ),
          if (rawBrakeType != null && rawBrakeType.isNotEmpty)
            ServiceWizardContextChip(
              icon: Icons.tune_outlined,
              label: needsRimBrakeFamilyConfirmation
                  ? 'Freno confirmado: llanta · falta familia'
                  : 'Freno confirmado: ${_formatBrakeSystemDetail(rawBrakeType, rawRimBrakeFamily)}',
            ),
        ],
      );

      if (needsRimBrakeFamilyConfirmation) {
        final rimFamilyOptions = (questionsByKey['brake_type']?.options ??
                const <ServiceQuestionOption>[])
            .where(
              (option) => kRimBrakeFamilyOptionValues.contains(option.value),
            )
            .toList(growable: false);
        questionOverrides['brake_type'] = ServiceWizardQuestionOverride(
          label: 'Familia de freno de llanta',
          helperText:
              'La plataforma ya viene confirmada desde la ficha de la bici. Aquí solo falta precisar la familia exacta.',
          lockedSelection: const ServiceWizardLockedSelection(
            label: 'Tipo de freno (desde la bicicleta)',
            valueLabel: 'Llanta (rim)',
          ),
          options: rimFamilyOptions,
        );
      }

      final mappedBrakeType = _mappedBrakeTypeWizardAnswer(
        rawBrakeType,
        rawRimBrakeFamily,
        questionsByKey['brake_type'],
      );
      if (mappedBrakeType != null) {
        initialAnswers['brake_type'] = mappedBrakeType;
        if (!needsRimBrakeFamilyConfirmation) {
          hiddenQuestionKeys.add('brake_type');
        }
      }

      final mappedMechanicalBrakeType = _mappedMechanicalBrakeTypeWizardAnswer(
        rawBrakeType,
        rawRimBrakeFamily,
        questionsByKey['brake_type_mech'],
      );
      if (mappedMechanicalBrakeType != null) {
        initialAnswers['brake_type_mech'] = mappedMechanicalBrakeType;
        hiddenQuestionKeys.add('brake_type_mech');
      }

      if (!_isDiscBrakeType(rawBrakeType)) {
        initialAnswers.remove('rotor_size');
        hiddenQuestionKeys.add('rotor_size');
      } else {
        final rotorSize = _mappedRotorSizeWizardAnswer(
          questionsByKey['rotor_size'],
          technicalValues,
          _selectedWizardPreviewLocation,
        );
        if (rotorSize != null) {
          initialAnswers['rotor_size'] = rotorSize;
          hiddenQuestionKeys.add('rotor_size');
        }
      }

      if (_selectedWizardPreviewLocation == BikeMemoryLocation.front) {
        helperText = 'Se actualizará la ficha del freno delantero.';
      } else if (_selectedWizardPreviewLocation == BikeMemoryLocation.rear) {
        helperText = 'Se actualizará la ficha del freno trasero.';
      } else {
        helperText =
            'Para dejarlo ligado a una ficha concreta, usa “Aplica a” y marca Del. o Tras.';
      }

      if (rawBrakeType != null && !_isDiscBrakeType(rawBrakeType)) {
        if (needsRimBrakeFamilyConfirmation) {
          helperText =
              '$helperText La bici ya confirma plataforma llanta. Aquí solo falta precisar la familia exacta, y por eso no se muestran rotores.';
        } else {
          final brakeDetail = _formatBrakeSystemDetail(
            rawBrakeType,
            rawRimBrakeFamily,
          );
          helperText =
              '$helperText La bici ya confirma freno $brakeDetail, así que el wizard no repite tipo ni rotores.';
        }
      } else if (rawBrakeType != null && rawBrakeType.isNotEmpty) {
        helperText =
            '$helperText La bici ya confirma freno ${_formatBrakeType(rawBrakeType)}.';
      }

      helperText =
          '$helperText Los campos marcados como “Diagnóstico” comparten la misma base que usa la ficha estructurada del freno.';
    } else if (profile.serviceFamily == 'drivetrain') {
      final derailleurs = _mappedDerailleursWizardAnswer(
        technicalValues['drivetrainConfig']?.toString(),
        questionsByKey['derailleurs'],
      );
      if (derailleurs != null) {
        initialAnswers['derailleurs'] = derailleurs;
        hiddenQuestionKeys.add('derailleurs');
      }

      final drivetrainHint = _buildDrivetrainProfileHint(technicalValues);
      helperText = drivetrainHint == null
          ? 'Esta configuración puede actualizar la ficha técnica de transmisión de esta bicicleta.'
          : 'Esta configuración puede actualizar la ficha técnica de transmisión de esta bicicleta. El perfil upstream ya marca $drivetrainHint.';

      if (bike != null) {
        contextSummary = ServiceWizardContextSummary(
          title: bike.displayName,
          subtitle: 'Transmisión',
          chips: [
            if (bike.bikeType != null)
              ServiceWizardContextChip(
                icon: Icons.directions_bike_outlined,
                label: 'Tipo de bici: ${bike.bikeType!.displayName}',
              ),
            if (drivetrainHint != null)
              ServiceWizardContextChip(
                icon: Icons.settings_input_component_outlined,
                label: 'Perfil confirmado: $drivetrainHint',
              ),
          ],
        );
      }
    }

    return _ServiceWizardPreviewConfig(
      profile: profile,
      initialAnswers: initialAnswers,
      hiddenQuestionKeys: hiddenQuestionKeys,
      helperText: helperText,
      contextSummary: contextSummary,
      questionOverrides: questionOverrides,
      diagnosisLinkedQuestionKeys: diagnosisLinkedQuestionKeys,
    );
  }

  Set<BikeMemoryLocation> _resolvePreviewBrakeDiagnosisTargets(
    BikeMemoryLocation location,
    Map<String, dynamic> answers,
  ) {
    if (location == BikeMemoryLocation.front) {
      return {BikeMemoryLocation.front};
    }
    if (location == BikeMemoryLocation.rear) {
      return {BikeMemoryLocation.rear};
    }

    switch (canonicalBrakeWheelValueFromAnswers(answers)) {
      case 'front':
        return {BikeMemoryLocation.front};
      case 'rear':
        return {BikeMemoryLocation.rear};
      case 'both':
        return {BikeMemoryLocation.front, BikeMemoryLocation.rear};
      default:
        return {};
    }
  }

  String _resolveDiagnosisDestinationLabel(
    ServiceWizardProfile profile,
    Map<String, dynamic> answers,
  ) {
    if (_isBrakeServiceFamily(profile.serviceFamily)) {
      final targets = _resolvePreviewBrakeDiagnosisTargets(
        _selectedWizardPreviewLocation,
        answers,
      );
      if (targets.isEmpty) {
        return 'Sin target cerrado todavía. En la pega el wizard usará “Aplica a” para decidir si escribe en la ficha del freno delantero, trasero o ambas.';
      }
      if (targets.length == 2) {
        return 'Escribe sobre las fichas de diagnóstico front_brake y rear_brake.';
      }
      if (targets.contains(BikeMemoryLocation.front)) {
        return 'Escribe sobre la ficha de diagnóstico front_brake.';
      }
      return 'Escribe sobre la ficha de diagnóstico rear_brake.';
    }

    if (profile.serviceFamily == 'drivetrain') {
      return 'Escribe sobre la ficha de diagnóstico drivetrain, elevando estado y anexando nota guiada cuando corresponde.';
    }

    return 'No hay sincronización estructurada directa definida para este perfil.';
  }

  Future<void> _openServiceWizardPreviewTester() async {
    final config = _buildServiceWizardPreviewConfig();
    if (config == null) {
      return;
    }

    final productName = _nameController.text.trim().isEmpty
        ? _selectedServiceProfile?.name ?? 'Servicio'
        : _nameController.text.trim();

    final result = await showServiceWizardDialog(
      context,
      productName: productName,
      productIsService: true,
      profile: config.profile,
      initialAnswers: config.initialAnswers,
      contextSummary: config.contextSummary,
      helperText: config.helperText,
      hiddenQuestionKeys: config.hiddenQuestionKeys,
      questionOverrides: config.questionOverrides,
      diagnosisLinkedQuestionKeys: config.diagnosisLinkedQuestionKeys,
    );

    if (result == null || !mounted) {
      return;
    }

    setState(() {
      _lastServiceWizardPreviewResult = result;
    });
  }

  String _resolveWizardPreviewValueLabel(
    ServiceProfileQuestion question,
    dynamic value,
    _ServiceWizardPreviewConfig config,
  ) {
    if (value is bool) {
      return value ? 'Sí' : 'No';
    }

    final overrideOptions = config.questionOverrides[question.key]?.options;
    if (value is List) {
      return value
          .map(
            (raw) => _resolveWizardPreviewSingleValueLabel(
              question,
              raw.toString(),
              overrideOptions,
            ),
          )
          .join(', ');
    }

    return _resolveWizardPreviewSingleValueLabel(
      question,
      value.toString(),
      overrideOptions,
    );
  }

  String _resolveWizardPreviewSingleValueLabel(
    ServiceProfileQuestion question,
    String rawValue,
    List<ServiceQuestionOption>? overrideOptions,
  ) {
    if (overrideOptions != null) {
      for (final option in overrideOptions) {
        if (option.value == rawValue) {
          return option.label;
        }
      }
    }

    return ServiceWizardService.resolveLabel(question, rawValue);
  }

  String _hiddenWizardQuestionReason(String key) {
    switch (key) {
      case 'which_wheel':
        return 'La ubicación ya quedó fijada por el target del servicio.';
      case 'brake_type':
        return 'La bici ya confirmó la plataforma o la familia de freno.';
      case 'brake_type_mech':
        return 'La ficha técnica ya resolvió la variante mecánica.';
      case 'rotor_size':
        return 'No aplica para esta bici o ya viene resuelto desde el perfil upstream.';
      case 'derailleurs':
        return 'La configuración de transmisión ya se dedujo desde drivetrainConfig.';
      default:
        return 'La respuesta ya llega predefinida desde el backbone.';
    }
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
      final categoryIdForSave =
          _isServiceForm ? _existingProduct?.categoryId : _selectedCategoryId;
      final supplierIdForSave =
          _isServiceForm ? _existingProduct?.supplierId : _selectedSupplierId;
      final supplierCodeForSave = _isServiceForm
          ? _existingProduct?.supplierCode
          : (_supplierCodeController.text.trim().isEmpty
              ? null
              : _supplierCodeController.text.trim());
      final normalizedBrandId = (() {
        if (_isServiceForm) return _existingProduct?.brandId;
        final candidate = potentialBrand?.id ?? _selectedBrandId;
        if (candidate == null) return null;
        final trimmed = candidate.trim();
        return trimmed.isEmpty ? null : trimmed;
      })();
      final normalizedBrandName = (() {
        if (_isServiceForm) return _existingProduct?.brand;
        if (potentialBrand != null) {
          final trimmed = potentialBrand.name.trim();
          return trimmed.isEmpty ? null : trimmed;
        }
        return rawBrand.isEmpty ? null : rawBrand;
      })();
      final normalizedModel = _isServiceForm
          ? _existingProduct?.model
          : (rawModel.isEmpty ? null : rawModel);
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
        if (category.id == categoryIdForSave) {
          selectedCategoryName = category.name;
          break;
        }
      }

      String? selectedSupplierName;
      for (final supplier in _suppliers) {
        if (supplier.id == supplierIdForSave) {
          selectedSupplierName = supplier.name;
          break;
        }
      }

      final normalizedGoogleMerchant =
          _isServiceForm ? false : _isGoogleMerchant;

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
            categoryId: categoryIdForSave,
            categoryName: selectedCategoryName,
            supplierId: supplierIdForSave,
            supplierName: selectedSupplierName,
            supplierCode: supplierCodeForSave,
            brandId: normalizedBrandId,
            brand: normalizedBrandName,
            model: normalizedModel,
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
            isGoogleMerchant: normalizedGoogleMerchant,
            purchaseTreatment: _selectedPurchaseTreatment,
            productType: _selectedProductType,
          );

      final product = baseProduct.copyWith(
        name: name,
        sku: sku,
        description: rawDescription.isEmpty ? null : rawDescription,
        websiteDescription: rawWebsiteDescription,
        categoryId: categoryIdForSave,
        categoryName: selectedCategoryName ?? baseProduct.categoryName,
        supplierId: supplierIdForSave,
        supplierName: selectedSupplierName ?? baseProduct.supplierName,
        supplierCode: supplierCodeForSave,
        brandId: normalizedBrandId,
        brandIdHasValue: true,
        brand: normalizedBrandName,
        brandHasValue: true,
        model: normalizedModel,
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
        isGoogleMerchant: normalizedGoogleMerchant,
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

      if (savedProduct.id != null) {
        await _syncServiceProfileMapping(
          tenantId: tenantId,
          productId: savedProduct.id!,
        );
      }

      // Create component products if this is a set
      if (_isSet && _setComponents.isNotEmpty && savedProduct.id != null) {
        await _createSetComponentProducts(savedProduct);
      }

      // Save Ficha Técnica spec values
      if (!_isServiceForm && _specTemplate != null && savedProduct.id != null) {
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
                      color: theme.colorScheme.primary.withValues(alpha: 0.1),
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
              color: theme.colorScheme.primary.withValues(alpha: 0.1),
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
              tabs: [
                const Tab(
                  icon: Icon(Icons.edit_note),
                  text: 'Detalles Generales',
                ),
                const Tab(
                  icon: Icon(Icons.language),
                  text: 'Tienda Online',
                ),
                Tab(
                  icon: Icon(
                    _isServiceForm ? Icons.alt_route_outlined : Icons.tune,
                  ),
                  text:
                      _isServiceForm ? 'Workflow de Servicio' : 'Ficha Técnica',
                ),
                if (_isServiceForm)
                  const Tab(
                    icon: Icon(Icons.playlist_add_check_circle_outlined),
                    text: 'Wizard y Diagnóstico',
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
                  tabView = _isServiceForm
                      ? _buildServiceWorkflowTab(
                          theme,
                          key: const ValueKey(2),
                        )
                      : _buildSpecTab(theme, key: const ValueKey(2));
                case 3:
                  tabView = _buildServiceWizardPreviewTab(
                    theme,
                    key: const ValueKey(3),
                  );
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
        if (_isServiceForm) ...[
          _buildSectionCard(
            theme,
            icon: Icons.alt_route_outlined,
            title: 'Backbone del servicio',
            children: _buildServiceBackboneFields(theme, compact: true),
          ),
          const SizedBox(height: 16),
        ],
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
          title:
              _isServiceForm ? 'Identidad del servicio' : 'Información básica',
          children: _buildBasicInfoFields(theme),
        ),
        const SizedBox(height: 16),
        _buildSectionCard(
          theme,
          icon: Icons.attach_money_outlined,
          title: _isServiceForm ? 'Tarifa y margen' : 'Precios y márgenes',
          children: _buildPricingFields(theme),
        ),
        const SizedBox(height: 16),
        _buildSectionCard(
          theme,
          icon: Icons.text_snippet_outlined,
          title: _isServiceForm
              ? 'Descripción facturable del servicio'
              : 'Descripción del producto',
          children: _buildDescriptionFields(theme),
        ),
        if (_isServiceForm) ...[
          const SizedBox(height: 16),
          _buildSectionCard(
            theme,
            icon: Icons.account_tree_outlined,
            title: 'Resumen estructurado',
            children: _buildServiceSummaryFields(theme),
          ),
        ],
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

  Widget _buildServiceWorkflowTab(ThemeData theme, {Key? key}) {
    return SingleChildScrollView(
      key: key,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionCard(
            theme,
            icon: Icons.alt_route_outlined,
            title: 'Mapa del backbone',
            children: _buildServiceBackboneFields(theme),
          ),
          const SizedBox(height: 16),
          _buildSectionCard(
            theme,
            icon: Icons.summarize_outlined,
            title: 'Resumen cliente e interno',
            children: _buildServiceSummaryFields(theme),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildServiceBackboneFields(
    ThemeData theme, {
    bool compact = false,
  }) {
    if (_isLoadingServiceProfiles && _serviceProfiles.isEmpty) {
      return const [LinearProgressIndicator(minHeight: 2)];
    }

    final profile = _selectedServiceProfile;
    if (profile == null) {
      return [
        Text(
          compact
              ? 'Selecciona un perfil estructurado para que este servicio deje de comportarse como un producto genérico.'
              : 'Selecciona un perfil estructurado en Detalles Generales. Eso conecta el servicio con el wizard, el targeting técnico y los resúmenes que reutiliza el taller.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            height: 1.4,
          ),
        ),
      ];
    }

    return [
      Text(
        compact
            ? 'Este servicio ya está vinculado al backbone operativo del taller.'
            : 'El servicio se comportará como una operación estructurada: perfil, target técnico y downstream del taller quedan alineados desde este formulario.',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          height: 1.4,
        ),
      ),
      const SizedBox(height: 12),
      _buildServiceFlowNode(
        theme,
        icon: Icons.sell_outlined,
        title: 'Servicio facturable',
        body: _nameController.text.trim().isEmpty
            ? 'Usa un nombre corto y cobrable.'
            : '${_nameController.text.trim()} · ${_skuController.text.trim().isEmpty ? 'Sin código' : _skuController.text.trim()}',
      ),
      _buildServiceFlowArrow(theme),
      _buildServiceFlowNode(
        theme,
        icon: Icons.hub_outlined,
        title: 'Perfil estructurado',
        body: '${profile.name} (${profile.key})',
        chips: [
          _serviceFamilyLabel(profile.serviceFamily),
          if ((profile.targetFamily ?? '').isNotEmpty)
            'Target: ${_serviceFamilyLabel(profile.targetFamily)}',
        ],
      ),
      _buildServiceFlowArrow(theme),
      _buildServiceFlowNode(
        theme,
        icon: Icons.filter_alt_outlined,
        title: 'Target técnico',
        body:
            '${_serviceFamilyLabel(profile.targetFamily ?? profile.serviceFamily)} · ${_servicePositionModeLabel(profile.targetPositionMode)}',
      ),
      _buildServiceFlowArrow(theme),
      _buildServiceFlowNode(
        theme,
        icon: Icons.construction_outlined,
        title: 'Downstream del taller',
        body:
            'Wizard guiado, diagnosis reutilizable, mechanic_job_items y resumen de factura.',
      ),
    ];
  }

  List<Widget> _buildServiceSummaryFields(ThemeData theme) {
    final clientSummary = _defaultServiceClientDescription;
    final mechanicSummary = _defaultServiceMechanicSummary;

    return [
      Text(
        'El resumen cliente debe ser corto y cobrable. El resumen interno puede retener más semántica técnica para el wizard y el equipo del taller.',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          height: 1.4,
        ),
      ),
      const SizedBox(height: 12),
      _buildServiceSummaryPreview(
        theme,
        label: 'Resumen sugerido para cliente / factura',
        value: clientSummary.isEmpty ? 'Aún no hay sugerencia.' : clientSummary,
      ),
      const SizedBox(height: 10),
      Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          onPressed:
              clientSummary.isEmpty ? null : _applySuggestedServiceDescription,
          icon: const Icon(Icons.assignment_outlined),
          label: const Text('Usar resumen cliente'),
        ),
      ),
      const SizedBox(height: 16),
      _buildServiceSummaryPreview(
        theme,
        label: 'Resumen interno / operativo',
        value: mechanicSummary.isEmpty
            ? 'Aún no hay sugerencia.'
            : mechanicSummary,
      ),
      const SizedBox(height: 10),
      Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          onPressed: _defaultServiceWebsiteDescription.isEmpty
              ? null
              : _applySuggestedWebsiteDescription,
          icon: const Icon(Icons.language_outlined),
          label: const Text('Usar texto base en web'),
        ),
      ),
    ];
  }

  Widget _buildServiceFlowArrow(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          const SizedBox(width: 16),
          Icon(
            Icons.south,
            size: 18,
            color: theme.colorScheme.primary,
          ),
        ],
      ),
    );
  }

  Widget _buildServiceFlowNode(
    ThemeData theme, {
    required IconData icon,
    required String title,
    required String body,
    List<String> chips = const [],
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color:
            theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: theme.dividerColor.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            body,
            style: theme.textTheme.bodySmall?.copyWith(height: 1.4),
          ),
          if (chips.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: chips
                  .map(
                    (chip) => Chip(
                      visualDensity: VisualDensity.compact,
                      label: Text(chip),
                    ),
                  )
                  .toList(growable: false),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildServiceSummaryPreview(
    ThemeData theme, {
    required String label,
    required String value,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(height: 1.45),
          ),
        ],
      ),
    );
  }

  Widget _buildServiceWizardPreviewTab(ThemeData theme, {Key? key}) {
    final previewConfig = _buildServiceWizardPreviewConfig();
    final profile = _selectedServiceWizardProfile;
    final previewAnswers = _lastServiceWizardPreviewResult?.answers ??
        previewConfig?.initialAnswers ??
        const <String, dynamic>{};

    return SingleChildScrollView(
      key: key,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionCard(
            theme,
            icon: Icons.play_arrow_outlined,
            title: 'Tester del wizard',
            children: _buildServiceWizardTesterFields(theme),
          ),
          const SizedBox(height: 16),
          _buildSectionCard(
            theme,
            icon: Icons.view_quilt_outlined,
            title: 'Comportamiento esperado',
            children: _buildServiceWizardBehaviorFields(
              theme,
              previewConfig: previewConfig,
            ),
          ),
          const SizedBox(height: 16),
          _buildSectionCard(
            theme,
            icon: Icons.account_tree_outlined,
            title: 'Semántica del backbone',
            children: _buildServiceBackboneSemanticsFields(
              theme,
              profile: profile,
              previewConfig: previewConfig,
            ),
          ),
          const SizedBox(height: 16),
          _buildSectionCard(
            theme,
            icon: Icons.sync_alt_outlined,
            title: 'Vinculación con diagnóstico',
            children: _buildServiceDiagnosisLinkFields(
              theme,
              profile: profile,
              previewConfig: previewConfig,
              previewAnswers: previewAnswers,
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildServiceWizardTesterFields(ThemeData theme) {
    final selectedBike = _selectedWizardPreviewBike;
    final selectedProfile = _selectedServiceProfile;

    return [
      Text(
        'Este tester no guarda nada. Simula cómo abrirá el wizard dentro de una pega usando el perfil estructurado del servicio y, si eliges una bici, la verdad upstream de esa bicicleta.',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          height: 1.4,
        ),
      ),
      const SizedBox(height: 16),
      if (_isLoadingWizardPreviewCustomers ||
          _isLoadingWizardPreviewBikes ||
          _isLoadingWizardPreviewBikeProfile ||
          _isLoadingSelectedServiceWizardProfile)
        const Padding(
          padding: EdgeInsets.only(bottom: 12),
          child: LinearProgressIndicator(minHeight: 2),
        ),
      Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          SizedBox(
            width: 280,
            child: DropdownButtonFormField<String>(
              initialValue: _selectedWizardPreviewCustomerId,
              decoration: const InputDecoration(
                labelText: 'Cliente para la simulación',
                helperText: 'Opcional. Filtra las bicicletas del tester.',
              ),
              items: _wizardPreviewCustomers
                  .map(
                    (customer) => DropdownMenuItem<String>(
                      value: customer.id,
                      child: Text(customer.name),
                    ),
                  )
                  .toList(growable: false),
              onChanged: _handleWizardPreviewCustomerChanged,
            ),
          ),
          SizedBox(
            width: 320,
            child: DropdownButtonFormField<String>(
              initialValue: _selectedWizardPreviewBikeId,
              decoration: InputDecoration(
                labelText: 'Bicicleta del cliente',
                helperText: _selectedWizardPreviewCustomerId == null
                    ? 'Selecciona un cliente para cargar sus bicicletas.'
                    : 'Sin bici = wizard genérico; con bici = preview adaptado.',
              ),
              items: _wizardPreviewBikes
                  .map(
                    (bike) => DropdownMenuItem<String>(
                      value: bike.id,
                      child: Text(
                          BikeProfileSummaryBuilder.buildIdentityLine(bike)),
                    ),
                  )
                  .toList(growable: false),
              onChanged: _selectedWizardPreviewCustomerId == null
                  ? null
                  : _handleWizardPreviewBikeChanged,
            ),
          ),
          if (selectedProfile?.targetPositionMode == 'front_rear')
            SizedBox(
              width: 320,
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Target técnico para el preview',
                  helperText:
                      'Simula si el ítem ya viene fijado en delantero o trasero.',
                ),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ChoiceChip(
                      label: const Text('Lo decide el wizard'),
                      selected: _selectedWizardPreviewLocation ==
                          BikeMemoryLocation.none,
                      onSelected: (_) => _handleWizardPreviewLocationChanged(
                        BikeMemoryLocation.none,
                      ),
                    ),
                    ChoiceChip(
                      label: const Text('Delantero'),
                      selected: _selectedWizardPreviewLocation ==
                          BikeMemoryLocation.front,
                      onSelected: (_) => _handleWizardPreviewLocationChanged(
                        BikeMemoryLocation.front,
                      ),
                    ),
                    ChoiceChip(
                      label: const Text('Trasero'),
                      selected: _selectedWizardPreviewLocation ==
                          BikeMemoryLocation.rear,
                      onSelected: (_) => _handleWizardPreviewLocationChanged(
                        BikeMemoryLocation.rear,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
      const SizedBox(height: 12),
      Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          FilledButton.icon(
            onPressed: _selectedServiceWizardProfile == null ||
                    _isLoadingSelectedServiceWizardProfile
                ? null
                : _openServiceWizardPreviewTester,
            icon: const Icon(Icons.play_arrow_outlined),
            label: Text(
              selectedBike == null
                  ? 'Probar wizard genérico'
                  : 'Probar con esta bici',
            ),
          ),
          OutlinedButton.icon(
            onPressed: _selectedWizardPreviewCustomerId == null &&
                    _selectedWizardPreviewBikeId == null
                ? null
                : () {
                    setState(() {
                      _selectedWizardPreviewCustomerId = null;
                      _selectedWizardPreviewBikeId = null;
                      _wizardPreviewBikes = [];
                      _selectedWizardPreviewBikeProfile = null;
                      _selectedWizardPreviewLocation = BikeMemoryLocation.none;
                      _resetServiceWizardPreviewResult();
                    });
                  },
            icon: const Icon(Icons.layers_clear_outlined),
            label: const Text('Limpiar contexto de bici'),
          ),
        ],
      ),
      if (_selectedWizardPreviewCustomerId != null &&
          !_isLoadingWizardPreviewBikes &&
          _wizardPreviewBikes.isEmpty) ...[
        const SizedBox(height: 12),
        Text(
          'Este cliente no tiene bicicletas activas para usar en la simulación.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
      if (selectedBike != null) ...[
        const SizedBox(height: 16),
        _buildWizardPreviewBikeSummary(theme, selectedBike),
      ],
      if (_lastServiceWizardPreviewResult != null) ...[
        const SizedBox(height: 16),
        _buildServiceSummaryPreview(
          theme,
          label: 'Último resultado probado en el tester',
          value: _lastServiceWizardPreviewResult!.summary.trim().isEmpty
              ? 'El wizard se cerró sin respuestas visibles.'
              : _lastServiceWizardPreviewResult!.summary,
        ),
      ],
    ];
  }

  Widget _buildWizardPreviewBikeSummary(ThemeData theme, Bike bike) {
    final technicalValues =
        _selectedWizardPreviewBikeProfile?.technicalValues ??
            const <String, dynamic>{};
    final technicalHighlights =
        BikeProfileSummaryBuilder.buildTechnicalHighlights(
      bike: bike,
      technicalValues: technicalValues,
    );
    final warnings = BikeProfileSummaryBuilder.buildWarnings(
      bike: bike,
      technicalValues: technicalValues,
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color:
            theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: theme.dividerColor.withValues(alpha: 0.25),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Contexto upstream de la bici seleccionada',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            BikeProfileSummaryBuilder.buildIdentityLine(bike),
            style: theme.textTheme.bodyMedium,
          ),
          if (_selectedWizardPreviewCustomer != null) ...[
            const SizedBox(height: 4),
            Text(
              'Cliente: ${_selectedWizardPreviewCustomer!.name}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          if (technicalHighlights.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: technicalHighlights
                  .map(
                    (line) => Chip(
                      visualDensity: VisualDensity.compact,
                      label: Text(line),
                    ),
                  )
                  .toList(growable: false),
            ),
          ],
          if (warnings.isNotEmpty) ...[
            const SizedBox(height: 12),
            ...warnings.map(
              (warning) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.warning_amber_outlined,
                      size: 16,
                      color: theme.colorScheme.tertiary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        warning,
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  List<Widget> _buildServiceWizardBehaviorFields(
    ThemeData theme, {
    required _ServiceWizardPreviewConfig? previewConfig,
  }) {
    if (_selectedServiceProfile == null) {
      return [
        Text(
          'Primero asigna un perfil estructurado al servicio. Sin eso no existe wizard real que mostrar.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ];
    }

    if (_isLoadingSelectedServiceWizardProfile && previewConfig == null) {
      return const [LinearProgressIndicator(minHeight: 2)];
    }

    if (previewConfig == null) {
      return [
        Text(
          'No se pudieron cargar las preguntas del wizard para este perfil.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.error,
          ),
        ),
      ];
    }

    final visibleQuestions = previewConfig.profile.questions
        .where(
          (question) =>
              !question.isAdvanced &&
              !previewConfig.hiddenQuestionKeys.contains(question.key),
        )
        .toList(growable: false);
    final hiddenQuestions = previewConfig.profile.questions
        .where((question) =>
            previewConfig.hiddenQuestionKeys.contains(question.key))
        .toList(growable: false);

    return [
      Text(
        'La vista usa el mismo perfil del taller y aplica la misma lógica upstream que luego consumirá la pega: contexto de bici, preguntas ocultas, bloqueos y prefills.',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          height: 1.4,
        ),
      ),
      if (previewConfig.contextSummary != null) ...[
        const SizedBox(height: 16),
        _buildWizardContextSummaryCard(theme, previewConfig.contextSummary!),
      ],
      if (previewConfig.helperText != null &&
          previewConfig.helperText!.trim().isNotEmpty) ...[
        const SizedBox(height: 16),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: theme.colorScheme.primary.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Text(
            previewConfig.helperText!,
            style: theme.textTheme.bodySmall?.copyWith(height: 1.45),
          ),
        ),
      ],
      const SizedBox(height: 16),
      Text(
        'Preguntas visibles en el wizard',
        style: theme.textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w700,
        ),
      ),
      const SizedBox(height: 10),
      if (visibleQuestions.isEmpty)
        Text(
          'Con la configuración actual no quedan preguntas visibles. Todo llega resuelto por la ficha técnica o por el target del servicio.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        )
      else
        ...visibleQuestions.map(
          (question) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _buildWizardPreviewQuestionCard(
              theme,
              question: question,
              previewConfig: previewConfig,
            ),
          ),
        ),
      if (hiddenQuestions.isNotEmpty) ...[
        const SizedBox(height: 8),
        Text(
          'Preguntas ocultas por contexto upstream',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 10),
        ...hiddenQuestions.map(
          (question) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.visibility_off_outlined,
                  size: 16,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${question.label}: ${_hiddenWizardQuestionReason(question.key)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    ];
  }

  Widget _buildWizardContextSummaryCard(
    ThemeData theme,
    ServiceWizardContextSummary contextSummary,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color:
            theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: theme.dividerColor.withValues(alpha: 0.25),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            contextSummary.title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          if (contextSummary.subtitle != null &&
              contextSummary.subtitle!.trim().isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              contextSummary.subtitle!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          if (contextSummary.chips.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: contextSummary.chips
                  .map(
                    (chip) => Chip(
                      visualDensity: VisualDensity.compact,
                      avatar: Icon(chip.icon, size: 16),
                      label: Text(chip.label),
                    ),
                  )
                  .toList(growable: false),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildWizardPreviewQuestionCard(
    ThemeData theme, {
    required ServiceProfileQuestion question,
    required _ServiceWizardPreviewConfig previewConfig,
  }) {
    final semantics = _serviceWizardQuestionSemantics(
      previewConfig.profile,
      question,
    );
    final override = previewConfig.questionOverrides[question.key];
    final prefillValue = previewConfig.initialAnswers[question.key];
    final prefillLabel = prefillValue == null
        ? null
        : _resolveWizardPreviewValueLabel(
            question, prefillValue, previewConfig);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: theme.dividerColor.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  override?.label ?? question.label,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                _wizardQuestionTypeLabel(question.questionType),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (question.isRequired)
                const Chip(
                  visualDensity: VisualDensity.compact,
                  label: Text('Obligatoria'),
                ),
              Chip(
                visualDensity: VisualDensity.compact,
                avatar: Icon(
                  _serviceWizardBackboneBucketIcon(semantics.bucket),
                  size: 16,
                ),
                label:
                    Text(_serviceWizardBackboneBucketLabel(semantics.bucket)),
              ),
              if (previewConfig.diagnosisLinkedQuestionKeys
                  .contains(question.key))
                const Chip(
                  visualDensity: VisualDensity.compact,
                  avatar: Icon(Icons.sync_alt_outlined, size: 16),
                  label: Text('Diagnóstico'),
                ),
              if (prefillLabel != null && prefillLabel.isNotEmpty)
                Chip(
                  visualDensity: VisualDensity.compact,
                  avatar: const Icon(Icons.auto_awesome_outlined, size: 16),
                  label: Text('Prefill: $prefillLabel'),
                ),
              if (override?.lockedSelection != null)
                Chip(
                  visualDensity: VisualDensity.compact,
                  avatar: const Icon(Icons.lock_outline, size: 16),
                  label: Text(
                    '${override!.lockedSelection!.label}: ${override.lockedSelection!.valueLabel}',
                  ),
                ),
            ],
          ),
          if (override?.helperText != null &&
              override!.helperText!.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              override.helperText!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.4,
              ),
            ),
          ] else ...[
            const SizedBox(height: 10),
            Text(
              semantics.detail,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.4,
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _wizardQuestionTypeLabel(String value) {
    switch (value) {
      case 'single_select':
        return 'Selección única';
      case 'multi_select':
        return 'Selección múltiple';
      case 'boolean':
        return 'Sí / No';
      case 'number':
        return 'Número';
      default:
        return 'Texto';
    }
  }

  List<Widget> _buildServiceBackboneSemanticsFields(
    ThemeData theme, {
    required ServiceWizardProfile? profile,
    required _ServiceWizardPreviewConfig? previewConfig,
  }) {
    if (profile == null || previewConfig == null) {
      return [
        Text(
          'Selecciona un perfil estructurado para clasificar cada campo entre verdad upstream, diagnóstico y ejecución.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ];
    }

    final questions = profile.questions
        .where((question) => !question.isAdvanced)
        .toList(growable: false);
    final grouped =
        <_ServiceWizardBackboneBucket, List<ServiceProfileQuestion>>{
      for (final bucket in _ServiceWizardBackboneBucket.values)
        bucket: <ServiceProfileQuestion>[],
    };

    for (final question in questions) {
      final semantics = _serviceWizardQuestionSemantics(profile, question);
      grouped[semantics.bucket]!.add(question);
    }

    final visibleUpstreamQuestions =
        grouped[_ServiceWizardBackboneBucket.upstreamTruth]!
            .where(
              (question) =>
                  !previewConfig.hiddenQuestionKeys.contains(question.key),
            )
            .toList(growable: false);

    final widgets = <Widget>[
      Text(
        'Aquí se separa qué pertenece a la ficha técnica upstream de la bici, qué es verdad diagnóstica de la visita y qué solo vive como target o detalle operativo del servicio.',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          height: 1.4,
        ),
      ),
    ];

    if (visibleUpstreamQuestions.isNotEmpty) {
      widgets.addAll([
        const SizedBox(height: 14),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: theme.colorScheme.errorContainer.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Deriva detectada en este perfil',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.onErrorContainer,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Estos campos siguen entrando por el wizard aunque arquitectónicamente pertenecen al backbone upstream. Deberían llegar desde bike profile / compatibilidad y el wizard solo debería consumirlos o confirmarlos.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onErrorContainer,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: visibleUpstreamQuestions
                    .map(
                      (question) => Chip(
                        visualDensity: VisualDensity.compact,
                        avatar:
                            const Icon(Icons.warning_amber_outlined, size: 16),
                        label: Text(question.label),
                      ),
                    )
                    .toList(growable: false),
              ),
            ],
          ),
        ),
      ]);
    }

    for (final bucket in _ServiceWizardBackboneBucket.values) {
      final bucketQuestions = grouped[bucket]!;
      if (bucketQuestions.isEmpty) {
        continue;
      }

      widgets.addAll([
        const SizedBox(height: 16),
        Text(
          _serviceWizardBackboneBucketTitle(bucket),
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 10),
        ...bucketQuestions.map(
          (question) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _buildServiceBackboneQuestionRow(
              theme,
              profile: profile,
              question: question,
              previewConfig: previewConfig,
            ),
          ),
        ),
      ]);
    }

    return widgets;
  }

  Widget _buildServiceBackboneQuestionRow(
    ThemeData theme, {
    required ServiceWizardProfile profile,
    required ServiceProfileQuestion question,
    required _ServiceWizardPreviewConfig previewConfig,
  }) {
    final semantics = _serviceWizardQuestionSemantics(profile, question);
    final isHidden = previewConfig.hiddenQuestionKeys.contains(question.key);
    final hasPrefill = previewConfig.initialAnswers.containsKey(question.key);
    final override = previewConfig.questionOverrides[question.key];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color:
            theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: theme.dividerColor.withValues(alpha: 0.18),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  question.label,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                question.key,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              Chip(
                visualDensity: VisualDensity.compact,
                avatar: Icon(
                  _serviceWizardBackboneBucketIcon(semantics.bucket),
                  size: 16,
                ),
                label:
                    Text(_serviceWizardBackboneBucketLabel(semantics.bucket)),
              ),
              if (isHidden)
                const Chip(
                  visualDensity: VisualDensity.compact,
                  avatar: Icon(Icons.visibility_off_outlined, size: 16),
                  label: Text('Oculta por upstream'),
                )
              else if (hasPrefill)
                const Chip(
                  visualDensity: VisualDensity.compact,
                  avatar: Icon(Icons.auto_awesome_outlined, size: 16),
                  label: Text('Prefill activo'),
                ),
              if (override?.lockedSelection != null)
                const Chip(
                  visualDensity: VisualDensity.compact,
                  avatar: Icon(Icons.lock_outline, size: 16),
                  label: Text('Selección bloqueada'),
                ),
              if (previewConfig.diagnosisLinkedQuestionKeys
                  .contains(question.key))
                const Chip(
                  visualDensity: VisualDensity.compact,
                  avatar: Icon(Icons.sync_alt_outlined, size: 16),
                  label: Text('Sync diagnóstico'),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            semantics.detail,
            style: theme.textTheme.bodySmall?.copyWith(height: 1.45),
          ),
        ],
      ),
    );
  }

  _ServiceWizardQuestionSemantics _serviceWizardQuestionSemantics(
    ServiceWizardProfile profile,
    ServiceProfileQuestion question,
  ) {
    final key = question.key;

    if (key == 'which_wheel') {
      return const _ServiceWizardQuestionSemantics(
        bucket: _ServiceWizardBackboneBucket.targetExecution,
        summary: 'Target técnico del ítem',
        detail:
            'No es verdad de la bici. Es metadata de target del servicio y debe salir del “Aplica a” o del contexto del item, no de la ficha técnica.',
      );
    }

    if (_isBrakeServiceFamily(profile.serviceFamily)) {
      if (kDiagnosisLinkedBrakeWizardQuestionKeys.contains(key)) {
        return const _ServiceWizardQuestionSemantics(
          bucket: _ServiceWizardBackboneBucket.diagnosisTruth,
          summary: 'Verdad diagnóstica de la visita',
          detail:
              'Es un hallazgo del estado actual del freno. Debe sincronizar con diagnosis_sheet_data y no vivir solo como resumen del wizard.',
        );
      }

      switch (key) {
        case 'brake_type':
        case 'brake_type_mech':
          return const _ServiceWizardQuestionSemantics(
            bucket: _ServiceWizardBackboneBucket.upstreamTruth,
            summary: 'Spec durable del sistema de freno',
            detail:
                'La plataforma o familia del freno pertenece a la verdad upstream de la bici. El wizard solo debería consumirla o confirmar el faltante, no convertirse en su primer almacenamiento.',
          );
        case 'rotor_size':
          return const _ServiceWizardQuestionSemantics(
            bucket: _ServiceWizardBackboneBucket.upstreamTruth,
            summary: 'Compatibilidad baseline del freno/rueda',
            detail:
                'El diámetro del rotor es una spec durable del target técnico. Cuando la bici y la rueda ya están resueltas, este valor debería venir del perfil/catálogo y no entrar como dato nuevo en cada servicio.',
          );
        case 'fluid_type':
          return const _ServiceWizardQuestionSemantics(
            bucket: _ServiceWizardBackboneBucket.upstreamTruth,
            summary: 'Spec durable del sistema hidráulico',
            detail:
                'El tipo de fluido no debería quedar atrapado en un solo purgado o sangrado. Si pasa a ser importante operativamente, debe crecer como verdad upstream del freno hidráulico y reutilizarse en compatibilidad y servicios.',
          );
        case 'piston_count':
          return const _ServiceWizardQuestionSemantics(
            bucket: _ServiceWizardBackboneBucket.upstreamTruth,
            summary: 'Spec durable del caliper',
            detail:
                'La cantidad de pistones describe la plataforma del caliper, no un hallazgo puntual de la visita. Si se vuelve relevante para productos/servicios, debe vivir en la capa upstream.',
          );
        case 'include_pads':
        case 'replace_pads':
        case 'replace_parts':
        case 'replace_seals':
        case 'fluid_check':
        case 'include_housing':
          return const _ServiceWizardQuestionSemantics(
            bucket: _ServiceWizardBackboneBucket.targetExecution,
            summary: 'Detalle operativo del servicio',
            detail:
                'Esto pertenece a cómo se ejecuta o cotiza el trabajo actual. Puede quedarse en el item del servicio o en la nota guiada, pero no debe promoverse a ficha técnica permanente de la bici.',
          );
      }
    }

    if (profile.serviceFamily == 'drivetrain') {
      switch (key) {
        case 'derailleurs':
          return const _ServiceWizardQuestionSemantics(
            bucket: _ServiceWizardBackboneBucket.upstreamTruth,
            summary: 'Layout durable de transmisión',
            detail:
                'Qué desviadores existen se deriva del drivetrainConfig y de la arquitectura upstream de la transmisión. El wizard no debería ser la primera fuente de esa verdad.',
          );
        case 'chain_wear':
        case 'cable_condition':
          return const _ServiceWizardQuestionSemantics(
            bucket: _ServiceWizardBackboneBucket.diagnosisTruth,
            summary: 'Hallazgo de la visita',
            detail:
                'Es estado actual de la transmisión y debe reflejarse en la ficha diagnóstica compartida, no quedarse solo como texto operativo del servicio.',
          );
        case 'lube_type':
        case 'derailleur_check':
        case 'include_housing':
          return const _ServiceWizardQuestionSemantics(
            bucket: _ServiceWizardBackboneBucket.targetExecution,
            summary: 'Detalle operativo del servicio',
            detail:
                'Define cómo se hará el trabajo o qué se incluye en la intervención actual. No es verdad durable de la bici.',
          );
      }
    }

    return const _ServiceWizardQuestionSemantics(
      bucket: _ServiceWizardBackboneBucket.reviewNeeded,
      summary: 'Pendiente de mapear',
      detail:
          'Este campo todavía no tiene una clasificación explícita dentro del backbone. Antes de expandirlo, hay que decidir si es verdad upstream, diagnóstico de visita o ejecución-only.',
    );
  }

  IconData _serviceWizardBackboneBucketIcon(
    _ServiceWizardBackboneBucket bucket,
  ) {
    switch (bucket) {
      case _ServiceWizardBackboneBucket.upstreamTruth:
        return Icons.account_tree_outlined;
      case _ServiceWizardBackboneBucket.diagnosisTruth:
        return Icons.medical_information_outlined;
      case _ServiceWizardBackboneBucket.targetExecution:
        return Icons.build_circle_outlined;
      case _ServiceWizardBackboneBucket.reviewNeeded:
        return Icons.help_outline;
    }
  }

  String _serviceWizardBackboneBucketLabel(
    _ServiceWizardBackboneBucket bucket,
  ) {
    switch (bucket) {
      case _ServiceWizardBackboneBucket.upstreamTruth:
        return 'Upstream / Perfil';
      case _ServiceWizardBackboneBucket.diagnosisTruth:
        return 'Diagnóstico';
      case _ServiceWizardBackboneBucket.targetExecution:
        return 'Target / Ejecución';
      case _ServiceWizardBackboneBucket.reviewNeeded:
        return 'Revisión pendiente';
    }
  }

  String _serviceWizardBackboneBucketTitle(
    _ServiceWizardBackboneBucket bucket,
  ) {
    switch (bucket) {
      case _ServiceWizardBackboneBucket.upstreamTruth:
        return 'Verdad upstream que debe vivir en la bici/perfil';
      case _ServiceWizardBackboneBucket.diagnosisTruth:
        return 'Verdad diagnóstica de la visita';
      case _ServiceWizardBackboneBucket.targetExecution:
        return 'Target o detalle de ejecución';
      case _ServiceWizardBackboneBucket.reviewNeeded:
        return 'Campos todavía sin mapping explícito';
    }
  }

  List<Widget> _buildServiceDiagnosisLinkFields(
    ThemeData theme, {
    required ServiceWizardProfile? profile,
    required _ServiceWizardPreviewConfig? previewConfig,
    required Map<String, dynamic> previewAnswers,
  }) {
    if (profile == null || previewConfig == null) {
      return [
        Text(
          'Selecciona un perfil estructurado para mostrar el wiring entre wizard y diagnóstico.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ];
    }

    final destinationLabel = _resolveDiagnosisDestinationLabel(
      profile,
      previewAnswers,
    );

    return [
      Text(
        'En la pega real, el mechanic_job_item abre este wizard, guarda un resumen en el ítem y luego sincroniza parte de las respuestas con diagnosis_sheet_data. Esta pestaña explica esa ruta sin tocar datos reales.',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          height: 1.4,
        ),
      ),
      const SizedBox(height: 12),
      _buildServiceFlowNode(
        theme,
        icon: Icons.playlist_add_check_outlined,
        title: '1. Servicio dentro de la pega',
        body:
            'El ítem del taller resuelve su perfil y abre el wizard con contexto de bici, target y respuestas iniciales.',
      ),
      _buildServiceFlowArrow(theme),
      _buildServiceFlowNode(
        theme,
        icon: Icons.rule_folder_outlined,
        title: '2. Gating por verdad upstream',
        body:
            'La ficha técnica de la bici decide qué preguntas se esconden, cuáles quedan bloqueadas y qué respuestas llegan predefinidas.',
      ),
      _buildServiceFlowArrow(theme),
      _buildServiceFlowNode(
        theme,
        icon: Icons.receipt_long_outlined,
        title: '3. Resumen persistido',
        body:
            'El wizard devuelve respuestas estructuradas + un resumen legible que queda asociado al ítem del trabajo.',
      ),
      _buildServiceFlowArrow(theme),
      _buildServiceFlowNode(
        theme,
        icon: Icons.medical_information_outlined,
        title: '4. Sync hacia diagnóstico',
        body: destinationLabel,
      ),
      const SizedBox(height: 16),
      Text(
        'Campos que impactan el diagnóstico',
        style: theme.textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w700,
        ),
      ),
      const SizedBox(height: 10),
      ..._buildDiagnosisLinkRows(theme, profile),
      if (_lastServiceWizardPreviewResult != null) ...[
        const SizedBox(height: 16),
        _buildServiceSummaryPreview(
          theme,
          label: 'Ruta que seguiría el último resultado probado',
          value: _resolveDiagnosisDestinationLabel(
            profile,
            _lastServiceWizardPreviewResult!.answers,
          ),
        ),
      ],
    ];
  }

  List<Widget> _buildDiagnosisLinkRows(
    ThemeData theme,
    ServiceWizardProfile profile,
  ) {
    final rows = <Map<String, String>>[];
    final questionKeys =
        profile.questions.map((question) => question.key).toSet();

    if (_isBrakeServiceFamily(profile.serviceFamily)) {
      if (questionKeys.contains('pad_condition') ||
          questionKeys.contains('pad_contaminated')) {
        rows.add({
          'title': 'Pastillas de freno',
          'body':
              'pad_condition y pad_contaminated alimentan desgaste y contaminación de la hoja front_brake / rear_brake según el target.',
        });
      }
      if (questionKeys.contains('rotor_condition') ||
          questionKeys.contains('damage_level') ||
          questionKeys.contains('contamination_level')) {
        rows.add({
          'title': 'Rotor / severidad',
          'body':
              'rotor_condition, damage_level y contamination_level actualizan trueness, contaminación o severidad del rotor del mismo freno.',
        });
      }
      if (questionKeys.contains('symptom')) {
        rows.add({
          'title': 'Síntomas del freno',
          'body':
              'symptom se proyecta a symptom_keys para que diagnóstico y wizard hablen el mismo vocabulario.',
        });
      }
    } else if (profile.serviceFamily == 'drivetrain') {
      rows.add({
        'title': 'Estado global de transmisión',
        'body':
            'chain_wear y cable_condition pueden elevar el overallStatus de drivetrain según la severidad elegida.',
      });
      rows.add({
        'title': 'Nota guiada persistente',
        'body':
            'El wizard agrega una nota marcada en drivetrain.notes para que el equipo vea el rastro operativo sin duplicar una verdad paralela.',
      });
    } else {
      rows.add({
        'title': 'Sin sync específico todavía',
        'body':
            'Este perfil todavía no declara una sincronización estructurada explícita hacia diagnosis_sheet_data.',
      });
    }

    return rows
        .map(
          (row) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest
                    .withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: theme.dividerColor.withValues(alpha: 0.18),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    row['title']!,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    row['body']!,
                    style: theme.textTheme.bodySmall?.copyWith(height: 1.45),
                  ),
                ],
              ),
            ),
          ),
        )
        .toList(growable: false);
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
                  backgroundColor:
                      theme.colorScheme.primary.withValues(alpha: 0.12),
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
    if (_isServiceForm) {
      return _buildServiceBasicInfoFields(theme);
    }

    return _buildProductBasicInfoFields(theme);
  }

  Widget _buildProductTypeField() {
    return DropdownButtonFormField<ProductType>(
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
    );
  }

  Widget _buildSkuFieldRow({
    required String labelText,
    required String hintText,
    String? helperText,
    required String buttonLabel,
  }) {
    return Row(
      children: [
        Expanded(
          flex: 3,
          child: TextFormField(
            controller: _skuController,
            decoration: InputDecoration(
              labelText: labelText,
              hintText: hintText,
              helperText: helperText,
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
            label: Text(buttonLabel),
          ),
        ),
      ],
    );
  }

  List<Widget> _buildServiceBasicInfoFields(ThemeData theme) {
    return [
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: theme.colorScheme.primaryContainer.withValues(alpha: 0.22),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          'Los servicios ya no dependen de categorías comerciales débiles. Aquí se define su identidad facturable y su vínculo con el backbone técnico del taller.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            height: 1.4,
          ),
        ),
      ),
      const SizedBox(height: 16),
      _buildProductTypeField(),
      const SizedBox(height: 16),
      TextFormField(
        controller: _nameController,
        decoration: const InputDecoration(
          labelText: 'Nombre facturable del servicio',
          hintText: 'Ej. Regulación de frenos delantero y trasero',
        ),
        validator: (value) {
          if (value == null || value.trim().isEmpty) {
            return 'Ingresa un nombre válido';
          }
          return null;
        },
      ),
      const SizedBox(height: 16),
      if (_isLoadingServiceProfiles) ...[
        const LinearProgressIndicator(minHeight: 2),
        const SizedBox(height: 16),
      ],
      DropdownButtonFormField<String?>(
        initialValue: _selectedServiceProfileId,
        decoration: const InputDecoration(
          labelText: 'Perfil estructurado de servicio',
          helperText:
              'Conecta este servicio con wizard, targeting técnico y resúmenes downstream.',
          prefixIcon: Icon(Icons.hub_outlined),
        ),
        items: [
          const DropdownMenuItem<String?>(
            value: null,
            child: Text('Sin perfil estructurado'),
          ),
          ..._serviceProfiles.map(
            (profile) => DropdownMenuItem<String?>(
              value: profile.id,
              child: Text(
                '${_serviceFamilyLabel(profile.targetFamily ?? profile.serviceFamily)} · ${profile.name}',
              ),
            ),
          ),
        ],
        onChanged: _handleServiceProfileChanged,
      ),
      if (_selectedServiceProfile != null) ...[
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            Chip(label: Text(_selectedServiceProfileLabel)),
            Chip(
              label: Text(
                _servicePositionModeLabel(
                  _selectedServiceProfile?.targetPositionMode,
                ),
              ),
            ),
          ],
        ),
      ],
      const SizedBox(height: 16),
      _buildSkuFieldRow(
        labelText: 'Código interno del servicio',
        hintText: 'Ej. ${_buildServiceSkuPrefix()}-001',
        helperText:
            'Se recomienda una secuencia SRV por familia + operación para distinguir servicios de productos físicos.',
        buttonLabel: 'Generar SRV',
      ),
    ];
  }

  List<Widget> _buildProductBasicInfoFields(ThemeData theme) {
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
      _buildSkuFieldRow(
        labelText: 'SKU interno',
        hintText: _usesAliExpressSkuSequence
            ? 'Se asigna automáticamente como AE####'
            : 'Ej. BIC-MTB-TRK-001',
        helperText: _usesAliExpressSkuSequence
            ? 'Proveedor AliExpress: usa la secuencia automática AE####.'
            : null,
        buttonLabel: _usesAliExpressSkuSequence ? 'Siguiente AE' : 'Generar',
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
      _buildProductTypeField(),
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
                      .withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color:
                        Theme.of(context).dividerColor.withValues(alpha: 0.1),
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
                          .withValues(alpha: 0.7),
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
                    color: Colors.orange.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: Colors.orange.withValues(alpha: 0.24)),
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
            color: Theme.of(context)
                .colorScheme
                .surfaceContainerHighest
                .withValues(alpha: 0.4),
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
              decoration: InputDecoration(
                labelText:
                    _isServiceForm ? 'Tarifa al cliente' : 'Precio de venta',
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
                  return _isServiceForm
                      ? 'Define la tarifa del servicio'
                      : 'Define el precio de venta';
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
              decoration: InputDecoration(
                labelText: _isServiceForm
                    ? 'Costo interno estimado'
                    : 'Costo unitario',
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
                  return _isServiceForm
                      ? 'Indica el costo interno del servicio'
                      : 'Indica el costo del producto';
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
          color: theme.colorScheme.primaryContainer.withValues(alpha: 0.25),
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
                  _isServiceForm
                      ? 'Margen estimado del servicio'
                      : 'Margen estimado',
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
                          color:
                              theme.colorScheme.primary.withValues(alpha: 0.12),
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
        title: Text(_isServiceForm ? 'Servicio activo' : 'Producto activo'),
        subtitle: Text(
          _isServiceForm
              ? 'Los servicios inactivos no aparecen en taller, ventas ni catálogos públicos.'
              : 'Los productos inactivos no aparecen en el POS ni en catálogos públicos.',
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
        _isServiceForm
            ? 'Configura cómo se presenta este servicio en la vitrina web.'
            : 'Configura la visibilidad y contenido del producto en la tienda online.',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      const SizedBox(height: 16),
      // Toggle: Published on Website (requires is_active)
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(
          _isServiceForm
              ? 'Publicado en el catálogo de servicios'
              : 'Publicado en la tienda online',
          style: TextStyle(
            color: _isActive ? null : theme.disabledColor,
          ),
        ),
        subtitle: Text(
          _isActive
              ? (_isServiceForm
                  ? 'Muestra este servicio en la web pública.'
                  : 'Muestra este producto en el catálogo web.')
              : (_isServiceForm
                  ? 'Requiere que el servicio esté activo.'
                  : 'Requiere que el producto esté activo.'),
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
      if (!_isServiceForm) ...[
        const SizedBox(height: 8),

        // Toggle: Google Merchant Center (requires is_published)
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Row(
            children: [
              Text(
                'Google Merchant Center',
                style: TextStyle(
                  color:
                      (_isActive && _isPublished) ? null : theme.disabledColor,
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
      ] else ...[
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest
                .withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            'Los servicios no se envían a Google Merchant. Su publicación web se controla solo con el catálogo público.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.4,
            ),
          ),
        ),
        const SizedBox(height: 16),
      ],
      const Divider(),
      const SizedBox(height: 16),
      TextFormField(
        controller: _websiteDescriptionController,
        decoration: InputDecoration(
          labelText: _isServiceForm
              ? 'Descripción web del servicio'
              : 'Descripción para web',
          hintText: _isServiceForm
              ? 'Explica el alcance comercial del servicio con lenguaje claro.'
              : 'Descripción optimizada para ventas online (SEO, marketing).',
          helperText: _isServiceForm
              ? 'Puedes partir desde el resumen estructurado del servicio y luego ampliarlo para la web.'
              : 'Esta descripción se mostrará en la página del producto en la web.',
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
      if (_isServiceForm) ...[
        Text(
          'Piensa este campo como el texto que verá el cliente en la factura. Debe ser breve, preciso y entendible, no una ficha técnica larga.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 12),
        _buildServiceSummaryPreview(
          theme,
          label: 'Base sugerida para factura',
          value: _defaultServiceClientDescription.isEmpty
              ? 'Selecciona un perfil estructurado para ver una sugerencia.'
              : _defaultServiceClientDescription,
        ),
        const SizedBox(height: 12),
      ],
      TextFormField(
        controller: _descriptionController,
        decoration: InputDecoration(
          labelText: _isServiceForm
              ? 'Descripción para factura / ventas'
              : 'Descripción detallada',
          hintText: _isServiceForm
              ? 'Ej. Regulación completa de frenos delantero y trasero.'
              : 'Materiales, especificaciones técnicas, beneficios y advertencias.',
        ),
        maxLines: 6,
      ),
      if (_isServiceForm) ...[
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: _defaultServiceClientDescription.isEmpty
                ? null
                : _applySuggestedServiceDescription,
            icon: const Icon(Icons.assignment_turned_in_outlined),
            label: const Text('Usar sugerencia estructurada'),
          ),
        ),
      ],
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
                    color: Colors.black.withValues(alpha: 0.6),
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
