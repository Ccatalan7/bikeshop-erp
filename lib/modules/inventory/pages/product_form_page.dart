import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../shared/constants/storage_constants.dart';
import '../../../shared/services/database_service.dart';
import '../../../shared/services/image_service.dart';
import '../../../shared/services/inventory_service.dart' as shared_inventory;
import '../../../shared/services/error_reporting_service.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/main_layout.dart';
import '../../../shared/models/supplier.dart';
import '../../purchases/services/purchase_service.dart';
import '../models/category_models.dart' as category_models;
import '../models/inventory_models.dart';
import '../services/category_service.dart';
import '../services/inventory_service.dart' as inventory_services;

class ProductFormPage extends StatefulWidget {
  final String? productId;

  const ProductFormPage({super.key, this.productId});

  @override
  State<ProductFormPage> createState() => _ProductFormPageState();
}

class _ProductFormPageState extends State<ProductFormPage> {
  final _formKey = GlobalKey<FormState>();

  late inventory_services.InventoryService _inventoryService;
  late CategoryService _categoryService;
  late PurchaseService _purchaseService;

  final _nameController = TextEditingController();
  final _skuController = TextEditingController();
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
  bool _isActive = true;
  ProductType _selectedProductType = ProductType.product;

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

    @override
    void initState() {
      super.initState();
      final database = Provider.of<DatabaseService>(context, listen: false);
      _inventoryService = inventory_services.InventoryService(database);
      _categoryService = CategoryService(database);
      _purchaseService = PurchaseService(database);

      _inventoryQtyController.text = '0';
      _minStockController.text = '1';

      _priceController.addListener(_onPricingChanged);
      _costController.addListener(_onPricingChanged);

      _loadCategories();
      _loadSuppliers();

      if (widget.productId != null) {
        _loadProduct();
      }
    }


    @override
    void dispose() {
      _nameController.dispose();
      _skuController.dispose();
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

    void _onPricingChanged() {
      if (mounted) setState(() {});
    }

    Future<void> _loadCategories() async {
      try {
        final categories = await _categoryService.getCategories(activeOnly: true);
        if (mounted) {
          setState(() => _categories = categories);
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

    Future<void> _loadProduct() async {
      setState(() => _isLoading = true);
      try {
        final product = await _inventoryService.getProductById(widget.productId!);
        if (product != null) {
          _existingProduct = product;
          _nameController.text = product.name;
          _skuController.text = product.sku;
          _descriptionController.text = product.description ?? '';
          _brandController.text = product.brand ?? '';
          _modelController.text = product.model ?? '';
          _priceController.text = product.price.toStringAsFixed(0);
          _costController.text = product.cost.toStringAsFixed(0);
          _inventoryQtyController.text = product.inventoryQty.toString();
          _minStockController.text = product.minStockLevel.toString();
          _selectedCategoryId = product.categoryId;
          _selectedSupplierId = product.supplierId;
          _selectedProductType = product.productType;
          _isActive = product.isActive;
          _imageUrl = product.imageUrl;
          _additionalImages
            ..clear()
            ..addAll(product.additionalImages);
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

    Future<void> _selectMainImage() async {
      try {
        final result = await ImageService.pickImage();
        if (result != null) {
          setState(() {
            _selectedImageBytes = result.bytes;
            _selectedImageName = result.name;
          });

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
            : category_models.Category(id: null, name: 'PRD'),
      );

      final categorySegment = category.name
          .replaceAll(RegExp(r'[^A-Za-z0-9]'), '')
          .padRight(3, 'X')
          .substring(0, 3)
          .toUpperCase();
      final brandSegment = brand.isEmpty
          ? ''
          : '-${brand.replaceAll(RegExp(r'[^A-Za-z0-9]'), '')
              .padRight(3, 'X')
              .substring(0, 3)
              .toUpperCase()}';
      final nameSegment = name
          .replaceAll(RegExp(r'[^A-Za-z0-9]'), '')
          .padRight(3, 'X')
          .substring(0, 3)
          .toUpperCase();
      final timestamp =
          DateTime.now().millisecondsSinceEpoch.toString().substring(8);

      setState(() {
        _skuController.text = '$categorySegment$brandSegment-$nameSegment-$timestamp';
      });
    }

    double get _marginPercentage {
      final price = double.tryParse(_priceController.text.replaceAll(',', '.')) ?? 0;
      final cost = double.tryParse(_costController.text.replaceAll(',', '.')) ?? 0;
      if (cost <= 0) return 0;
      return ((price - cost) / cost) * 100;
    }

    Future<void> _saveProduct() async {
      if (!_formKey.currentState!.validate()) return;

      FocusScope.of(context).unfocus();
      setState(() => _isSaving = true);
      debugPrint("[DIAGNOSTIC] _saveProduct: Save process started.");

      try {
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
        final safeAdditionalImages = _additionalImages.whereType<String>().toList();

        final product = Product(
          id: _existingProduct?.id,
          name: _nameController.text.trim(),
          sku: _skuController.text.trim(),
          description: _descriptionController.text.trim().isEmpty
              ? null
              : _descriptionController.text.trim(),
          categoryId: _selectedCategoryId,
          supplierId: _selectedSupplierId,
          brand: _brandController.text.trim().isEmpty
              ? null
              : _brandController.text.trim(),
          model: _modelController.text.trim().isEmpty
              ? null
              : _modelController.text.trim(),
          price: double.parse(_priceController.text.replaceAll(',', '.')),
          cost: double.parse(_costController.text.replaceAll(',', '.')),
          inventoryQty: int.tryParse(_inventoryQtyController.text) ?? 0,
          minStockLevel: int.tryParse(_minStockController.text) ?? 1,
          imageUrl: finalImageUrl,
          additionalImages: safeAdditionalImages,
          isActive: _isActive,
          productType: _selectedProductType,
        );

        if (_existingProduct != null) {
          await _inventoryService.updateProduct(product);
        } else {
          await _inventoryService.createProduct(product);
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

        context.pop();
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

    void _notifySharedInventory() {
      try {
        final shared = context.read<shared_inventory.InventoryService>();
        unawaited(shared.refresh());
      } catch (_) {
        // Ignored: shared inventory not available in certain contexts.
      }
    }

    @override
    Widget build(BuildContext context) {
      final theme = Theme.of(context);
      return MainLayout(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
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
                          const Text('ERROR:', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                          SelectableText(_lastError!, style: const TextStyle(color: Colors.white)),
                          const SizedBox(height: 8),
                          const Text('STACK:', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 10)),
                          SelectableText(_lastStackTrace ?? '', style: const TextStyle(color: Colors.white, fontSize: 8)),
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
              ),
      );
    }

    Widget _buildHeader(ThemeData theme) {
      final title = _existingProduct != null
          ? 'Editar producto'
          : 'Nuevo producto';

      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Row(
          children: [
            IconButton(
              onPressed: () => context.pop(),
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
                        const SizedBox(height: 16),
                        _buildSectionCard(
                          theme,
                          icon: Icons.inventory_outlined,
                          title: 'Inventario',
                          children: _buildInventoryFields(theme),
                        ),
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
                _buildSectionCard(
                  theme,
                  icon: Icons.inventory_outlined,
                  title: 'Inventario',
                  children: _buildInventoryFields(theme),
                ),
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
                    backgroundColor:
                        theme.colorScheme.primary.withOpacity(0.12),
                    child: Icon(icon,
                        color: theme.colorScheme.primary, size: 18),
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
        DropdownButtonFormField<String>(
          value: _selectedCategoryId,
          decoration: const InputDecoration(
            labelText: 'Categoría',
            helperText: 'Determina reportes y navegación en el POS',
          ),
          items: _categories
              .map(
                (category) => DropdownMenuItem<String>(
                  value: category.id,
                  child: Text(category.name),
                ),
              )
              .toList(),
          onChanged: (value) => setState(() => _selectedCategoryId = value),
        ),
        const SizedBox(height: 16),
        // Product Type Selector
        DropdownButtonFormField<ProductType>(
          value: _selectedProductType,
          decoration: const InputDecoration(
            labelText: 'Tipo de producto',
            helperText: 'Los productos pueden ser comprados y vendidos, los servicios solo se venden',
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
                decoration: const InputDecoration(
                  labelText: 'Marca',
                  hintText: 'Ej. Trek, Specialized, Giant',
                ),
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

    List<Widget> _buildPricingFields(ThemeData theme) {
      return [
        Row(
          children: [
            Expanded(
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
            const SizedBox(width: 16),
            Expanded(
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
          ],
        ),
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
                  Icon(Icons.show_chart,
                      color: theme.colorScheme.primary),
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
        Row(
          children: [
            Expanded(
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
            const SizedBox(width: 16),
            Expanded(
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
          ],
        ),
      ];
    }

    List<Widget> _buildStatusFields(ThemeData theme) {
      return [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Producto activo'),
          subtitle: const Text(
            'Los productos inactivos no aparecen en el POS ni en catálogos públicos.',
          ),
          value: _isActive,
          onChanged: (value) => setState(() => _isActive = value),
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