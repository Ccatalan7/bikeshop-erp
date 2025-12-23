import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../shared/constants/storage_constants.dart';
import '../../../shared/services/image_service.dart';
import '../../../shared/services/inventory_service.dart' as shared_inventory;
import '../../../shared/services/tenant_service.dart';
import '../../../shared/services/error_reporting_service.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/branded_loading.dart';
import '../../../shared/widgets/main_layout.dart';
import '../../../shared/models/supplier.dart';
import '../../purchases/services/purchase_service.dart';
import '../models/category_models.dart' as category_models;
import '../models/brand_models.dart';
import '../models/inventory_models.dart';
import '../../../shared/models/product.dart' show SetType;
import '../services/category_service.dart';
import '../services/brand_service.dart';
import '../services/inventory_service.dart' as inventory_services;
import '../widgets/set_configuration_widget.dart';
import '../../../shared/services/barcode_scanner_service.dart';

class ProductFormPage extends StatefulWidget {
  final String? productId;
  final bool showInDialog; // Hide MainLayout when true

  const ProductFormPage({super.key, this.productId, this.showInDialog = false});

  @override
  State<ProductFormPage> createState() => _ProductFormPageState();
}

class _ProductFormPageState extends State<ProductFormPage> {
  final _formKey = GlobalKey<FormState>();

  late inventory_services.InventoryService _inventoryService;
  late CategoryService _categoryService;
  late PurchaseService _purchaseService;
  late BrandService _brandService;

  final _nameController = TextEditingController();
  final _skuController = TextEditingController();
  final _supplierCodeController = TextEditingController();
  final _descriptionController = TextEditingController();
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

  // SET CONFIGURATION STATE
  bool _isSet = false;
  SetType? _setType;
  List<SetComponentDraft> _setComponents = [];

  String? _imageUrl;
  // --- ARCHITECTURAL FIX ---
  // Do not store XFile in state. Store only pure, platform-agnostic data.
  Uint8List? _selectedImageBytes;
  String? _selectedImageName;
  final List<String> _additionalImages = [];
  bool _isUploadingGalleryImage = false;

  bool _isLoading = false;
  bool _isSaving = false;
  Product? _existingProduct;

  // Debug error tracking
  String? _lastError;
  String? _lastStackTrace;

  StreamSubscription? _scanSubscription;

  @override
  void initState() {
    super.initState();
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
    _scanSubscription?.cancel();
    _nameController.dispose();
    _skuController.dispose();
    _supplierCodeController.dispose();
    _descriptionController.dispose();
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
      }
    } catch (e) {
      // Suppliers are optional, silently fail
      if (!mounted) return;
    }
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
        _isActive = product.isActive;
        _isPublished = product.isPublished;
        _isGoogleMerchant = product.isGoogleMerchant;
        _imageUrl = product.imageUrl;
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

  void _generateSku() {
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

  double get _marginPercentage {
    final price =
        double.tryParse(_priceController.text.replaceAll(',', '.')) ?? 0;
    final cost =
        double.tryParse(_costController.text.replaceAll(',', '.')) ?? 0;
    if (cost <= 0) return 0;
    return ((price - cost) / cost) * 100;
  }

  bool get _isChildProduct => _existingProduct?.parentSetId != null;

  Future<void> _saveProduct() async {
    if (!_formKey.currentState!.validate()) return;

    FocusScope.of(context).unfocus();
    setState(() => _isSaving = true);
    debugPrint("[DIAGNOSTIC] _saveProduct: Save process started.");

    try {
      final tenantId = await TenantService().getTenantId();
      if (tenantId == null) {
        throw Exception('User does not have a tenant_id. Cannot proceed.');
      }

      String? finalImageUrl = _imageUrl;

      // --- ARCHITECTURAL FIX ---
      // Use the platform-agnostic bytes and name from the state.
      if (_selectedImageBytes != null && _selectedImageName != null) {
        final uploadUrl = await ImageService.uploadBytes(
          bytes: _selectedImageBytes!,
          fileName: _selectedImageName!,
          bucket: StorageConfig.defaultBucket,
          folder: StorageFolders.productMain,
        );
        if (uploadUrl == null) {
          throw Exception('No se pudo subir la imagen principal.');
        }
        finalImageUrl = uploadUrl;
      }

      // --- SAFEGUARD ---
      // Ensure only valid strings are passed to the model.
      final safeAdditionalImages =
          _additionalImages.whereType<String>().toList(growable: false);

      final name = _nameController.text.trim();
      final sku = _skuController.text.trim();
      final rawDescription = _descriptionController.text.trim();
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
      final inventoryQty =
          int.tryParse(_inventoryQtyController.text.trim()) ?? 0;
      final minStockLevel = int.tryParse(_minStockController.text.trim()) ?? 1;
      final maxStockLevel = _existingProduct?.maxStockLevel ?? 100;

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

      final baseProduct = _existingProduct ??
          Product(
            id: null,
            tenantId: tenantId,
            name: name,
            sku: sku,
            description: rawDescription.isEmpty ? null : rawDescription,
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
            additionalImages: safeAdditionalImages,
            isActive: _isActive,
            isPublished: _isPublished,
            isGoogleMerchant: _isGoogleMerchant,
            productType: _selectedProductType,
          );

      final product = baseProduct.copyWith(
        name: name,
        sku: sku,
        description: rawDescription.isEmpty ? null : rawDescription,
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
        additionalImages: safeAdditionalImages,
        isActive: _isActive,
        isPublished: _isPublished,
        isGoogleMerchant: _isGoogleMerchant,
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
                child: SingleChildScrollView(
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
                  onPressed: () => Navigator.of(context).pop(),
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

          if (isWide) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Child Product Banner (Wide)
                      if (_isChildProduct)
                        Container(
                          margin: const EdgeInsets.only(bottom: 16),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.tertiaryContainer,
                            borderRadius: BorderRadius.circular(12),
                            border:
                                Border.all(color: theme.colorScheme.tertiary),
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
                                      style:
                                          theme.textTheme.titleSmall?.copyWith(
                                        color: theme
                                            .colorScheme.onTertiaryContainer,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    Text(
                                      'Este producto es parte de un set (${_existingProduct?.componentLabel ?? "Componente"}).',
                                      style:
                                          theme.textTheme.bodySmall?.copyWith(
                                        color: theme
                                            .colorScheme.onTertiaryContainer,
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
                      if (_selectedProductType != ProductType.service &&
                          !_isChildProduct) ...[
                        const SizedBox(height: 16),
                        _buildSectionCard(
                          theme,
                          icon: Icons.inventory_2_outlined,
                          title: 'Configuración de Juego/Set',
                          children: _buildSetConfigurationFields(theme),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 24),
                SizedBox(
                  width: 360,
                  child: Column(
                    children: [
                      _buildSectionCard(
                        theme,
                        icon: Icons.image_outlined,
                        title: 'Imágenes',
                        children: _buildMediaFields(theme),
                      ),
                      // Only show inventory for products, not services
                      if (_selectedProductType != ProductType.service) ...[
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
                  ),
                ),
              ],
            );
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Child Product Banner (Narrow)
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
                icon: Icons.image_outlined,
                title: 'Imágenes',
                children: _buildMediaFields(theme),
              ),
              const SizedBox(height: 16),
              _buildSectionCard(
                theme,
                icon: Icons.attach_money_outlined,
                title: 'Precios y márgenes',
                children: _buildPricingFields(theme),
              ),
              const SizedBox(height: 16),
              // Only show inventory for products, not services
              if (_selectedProductType != ProductType.service)
                _buildSectionCard(
                  theme,
                  icon: Icons.inventory_outlined,
                  title: 'Inventario',
                  children: _buildInventoryFields(theme),
                ),
              if (_selectedProductType != ProductType.service)
                const SizedBox(height: 16),
              _buildSectionCard(
                theme,
                icon: Icons.settings_outlined,
                title: 'Estado y visibilidad',
                children: _buildStatusFields(theme),
              ),
              const SizedBox(height: 16),
              _buildSectionCard(
                theme,
                icon: Icons.text_snippet_outlined,
                title: 'Descripción del producto',
                children: _buildDescriptionFields(theme),
              ),
              // Only show set configuration for products, not services AND not child products
              if (_selectedProductType != ProductType.service &&
                  !_isChildProduct) ...[
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
        },
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
              decoration: const InputDecoration(
                labelText: 'SKU interno',
                hintText: 'Ej. BIC-MTB-TRK-001',
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
              onPressed: _generateSku,
              icon: const Icon(Icons.auto_fix_high_outlined),
              label: const Text('Generar'),
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
        value: _selectedProductType,
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
            setState(() => _selectedProductType = value);
          }
        },
      ),
      const SizedBox(height: 16),
      DropdownButtonFormField<String?>(
        value: _selectedSupplierId,
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
        onChanged: (value) => setState(() => _selectedSupplierId = value),
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
    return [
      Text(
        'Controla cantidades disponibles y stock mínimo para alertas.',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      const SizedBox(height: 16),
      LayoutBuilder(builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 600;
        final children = [
          Expanded(
            flex: isMobile ? 0 : 1,
            child: TextFormField(
              controller: _inventoryQtyController,
              decoration: const InputDecoration(
                labelText: 'Stock disponible',
              ),
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
              ],
            ),
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
                    .toList())
            : Row(children: children);
      }),
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
      const SizedBox(height: 8),

      // Toggle 2: Published on Website (requires is_active)
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
              ? 'Controla si este producto se muestra en la web y en el catálogo público.'
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

      // Toggle 3: Google Merchant Center (requires is_published)
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
                  : 'Incluye este producto en el feed de Google Shopping para aparecer en búsquedas de Google.',
          style: TextStyle(
            color: (_isActive && _isPublished) ? null : theme.disabledColor,
          ),
        ),
        value: _isActive && _isPublished && _isGoogleMerchant,
        onChanged: (_isActive && _isPublished)
            ? (value) => setState(() => _isGoogleMerchant = value)
            : null,
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
