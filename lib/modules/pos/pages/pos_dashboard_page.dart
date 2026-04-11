import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../../shared/models/product.dart';
import '../../../shared/models/customer.dart';
import '../../../shared/models/tax_treatment.dart';
import '../../../shared/models/payment_method.dart' as pm;
import '../../crm/services/customer_service.dart';
import '../../inventory/models/category_models.dart' as inventory_models;
import '../../inventory/services/category_service.dart';
import '../../../shared/services/inventory_service.dart';
import '../../../shared/services/payment_method_service.dart';
import '../../../shared/services/barcode_scanner_service.dart';
import '../../../shared/services/tenant_service.dart';
import '../../../shared/widgets/search_bar_widget.dart';
import '../../sales/models/sales_models.dart';
import '../../sales/services/sales_service.dart';
import '../services/pos_service.dart';
import '../widgets/product_tile.dart';
import '../models/payment_method.dart' as old_pm; // Old enum-based model
import '../models/pos_transaction.dart';

class POSDashboardPage extends StatefulWidget {
  const POSDashboardPage({super.key});

  @override
  State<POSDashboardPage> createState() => _POSDashboardPageState();
}

class _POSDashboardPageState extends State<POSDashboardPage> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String? _selectedCategoryKey;
  Set<String> _selectedCategoryMatchers = const <String>{};
  List<_CategoryOption> _serviceCategoryOptions = [];
  bool _isLoadingCategories = false;
  ProductType? _selectedProductType;
  StreamSubscription? _scanSubscription;

  // Hardware keyboard scanner state (USB/Bluetooth barcode scanners)
  final StringBuffer _scanBuffer = StringBuffer();
  Timer? _hwScanTimer;
  DateTime? _lastScanKeyTime;
  static const Duration _scanKeyTimeout = Duration(milliseconds: 100);
  static const int _minBarcodeLen = 3;

  @override
  void initState() {
    super.initState();
    // Load products and payment methods when page loads
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final inventoryService =
          Provider.of<InventoryService>(context, listen: false);
      final paymentMethodService =
          Provider.of<PaymentMethodService>(context, listen: false);
      final categoryService =
          Provider.of<CategoryService>(context, listen: false);

      inventoryService.getProducts();
      paymentMethodService.loadPaymentMethods();
      _loadCategories(categoryService);
    });

    // Listen for barcode scans from remote/phone scanner
    _scanSubscription =
        context.read<BarcodeScannerService>().barcodeStream.listen((barcode) {
      if (mounted && (ModalRoute.of(context)?.isCurrent ?? true)) {
        _handleBarcodeScan(barcode);
      }
    });

    // Register hardware handler for USB/Bluetooth keyboard-emulating scanners.
    // HardwareKeyboard bypasses the focus system so it works even when
    // the search bar or customer field is focused.
    HardwareKeyboard.instance.addHandler(_hardwareKeyHandler);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scanSubscription?.cancel();
    HardwareKeyboard.instance.removeHandler(_hardwareKeyHandler);
    _hwScanTimer?.cancel();
    super.dispose();
  }

  /// Hardware keyboard handler for USB/Bluetooth barcode scanners.
  /// Returns false so key events still reach focused widgets (text fields).
  bool _hardwareKeyHandler(KeyEvent event) {
    if (!mounted) return false;
    if (!(ModalRoute.of(context)?.isCurrent ?? true)) return false;
    if (event is! KeyDownEvent) return false;

    if (_isTextInputFocused) {
      _scanBuffer.clear();
      _hwScanTimer?.cancel();
      return false;
    }

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
      _hwScanTimer?.cancel();
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

    return false; // Never consume — let events reach text fields normally
  }

  bool get _isTextInputFocused {
    final focusedContext = FocusManager.instance.primaryFocus?.context;
    if (focusedContext == null) return false;

    try {
      if (focusedContext.widget is EditableText) {
        return true;
      }

      return focusedContext.findAncestorWidgetOfExactType<EditableText>() !=
          null;
    } catch (_) {
      return false;
    }
  }

  Future<void> _handleBarcodeScan(String barcode) async {
    final inventoryService =
        Provider.of<InventoryService>(context, listen: false);

    // Search for product by SKU or barcode
    final product = inventoryService.products.cast<Product?>().firstWhere(
          (p) =>
              p!.sku.toLowerCase() == barcode.toLowerCase() ||
              p.barcode?.toLowerCase() == barcode.toLowerCase(),
          orElse: () => null,
        );

    if (product != null) {
      _addToCart(product);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Producto no encontrado: $barcode'),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  void _addToCart(Product product, {int quantity = 1}) {
    final posService = Provider.of<POSService>(context, listen: false);

    final requiresStock =
        product.productType == ProductType.product && product.trackStock;
    if (requiresStock && product.stockQuantity < quantity) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text('Stock insuficiente. Disponible: ${product.stockQuantity}'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    try {
      posService.addToCart(product, quantity: quantity);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${product.name} agregado al carrito'),
          duration: const Duration(seconds: 1),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al agregar producto: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _loadCategories([CategoryService? existingService]) async {
    final service =
        existingService ?? Provider.of<CategoryService>(context, listen: false);

    if (mounted) {
      setState(() {
        _isLoadingCategories = true;
      });
    }

    try {
      final categories = await service.getCategories(activeOnly: true);
      if (!mounted) return;

      final options = <_CategoryOption>[];
      for (final inventory_models.Category category in categories) {
        final id = category.id?.trim();
        final normalizedName = _normalizeCategoryName(category.name);
        final key = id != null && id.isNotEmpty ? id : (normalizedName ?? '');
        if (key.isEmpty) {
          continue;
        }

        final matchers = <String>[
          if (id != null && id.isNotEmpty) id,
          if (normalizedName != null) normalizedName,
        ];

        options.add(
          _CategoryOption(
            key: key,
            label: category.name,
            matchers: matchers,
          ),
        );
      }

      options.sort((a, b) => a.label.compareTo(b.label));

      final selectedKey = _selectedCategoryKey;
      _CategoryOption? updatedSelectedOption;
      if (selectedKey != null) {
        updatedSelectedOption = _findCategoryOptionByKey(options, selectedKey);
      }

      setState(() {
        _serviceCategoryOptions = options;
        if (updatedSelectedOption != null) {
          _selectedCategoryMatchers = updatedSelectedOption.matchers;
        }
      });
    } catch (e) {
      if (!mounted) return;
      final theme = Theme.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al cargar categorías: $e'),
          backgroundColor: theme.colorScheme.error,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingCategories = false;
        });
      }
    }
  }

  String? _normalizeCategoryName(String? value) {
    if (value == null) {
      return null;
    }
    final normalized = value.trim().toLowerCase();
    return normalized.isEmpty ? null : normalized;
  }

  _CategoryOption? _findCategoryOptionByKey(
    Iterable<_CategoryOption> options,
    String key,
  ) {
    for (final option in options) {
      if (option.key == key || option.matchers.contains(key)) {
        return option;
      }
    }
    return null;
  }

  String _categoryKeyFor(Product product) {
    final id = product.categoryId?.trim();
    if (id != null && id.isNotEmpty) {
      return id;
    }

    final name = product.categoryName?.trim();
    if (name != null && name.isNotEmpty) {
      return name.toLowerCase();
    }

    return product.category.name;
  }

  String _categoryLabelFor(Product product) {
    final name = product.categoryName?.trim();
    if (name != null && name.isNotEmpty) {
      return name;
    }

    return product.category.displayName;
  }

  List<Product> _getFilteredProducts(
    List<Product> products, {
    Set<String> categoryMatchers = const <String>{},
  }) {
    return products.where((product) {
      final matchesSearch = _searchQuery.isEmpty ||
          product.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          product.sku.toLowerCase().contains(_searchQuery.toLowerCase());

      final categoryKey = _categoryKeyFor(product);
      final normalizedLabel =
          _normalizeCategoryName(_categoryLabelFor(product));
      final productCategoryId = product.categoryId?.trim();
      final matchesCategory = _selectedCategoryKey == null ||
          categoryKey == _selectedCategoryKey ||
          (productCategoryId != null &&
              productCategoryId == _selectedCategoryKey) ||
          categoryMatchers.contains(categoryKey) ||
          (productCategoryId != null &&
              categoryMatchers.contains(productCategoryId)) ||
          (normalizedLabel != null &&
              categoryMatchers.contains(normalizedLabel)) ||
          categoryMatchers.contains(product.category.name);

      final matchesType = _selectedProductType == null ||
          product.productType == _selectedProductType;

      final requiresStock =
          product.productType == ProductType.product && product.trackStock;
      final hasStock = !requiresStock || product.stockQuantity > 0;

      return matchesSearch && matchesCategory && matchesType && hasStock;
    }).toList();
  }

  List<_CategoryOption> _getCategoryOptions(List<Product> products) {
    final Map<String, _CategoryOption> options = {
      for (final option in _serviceCategoryOptions) option.key: option,
    };

    for (final product in products) {
      final key = _categoryKeyFor(product);
      final label = _categoryLabelFor(product);
      final normalizedLabel = _normalizeCategoryName(label);
      final productCategoryId = product.categoryId?.trim();
      final categoryDisplayMatcher =
          _normalizeCategoryName(product.category.displayName);

      final matchers = <String>[
        if (productCategoryId != null && productCategoryId.isNotEmpty)
          productCategoryId,
        if (normalizedLabel != null) normalizedLabel,
        product.category.name,
        if (categoryDisplayMatcher != null) categoryDisplayMatcher,
      ];

      final existing = options[key];
      if (existing != null) {
        options[key] = _CategoryOption(
          key: existing.key,
          label: existing.label,
          matchers: {...existing.matchers, ...matchers},
        );
      } else {
        options[key] = _CategoryOption(
          key: key,
          label: label,
          matchers: matchers,
        );
      }
    }

    final list = options.values.toList()
      ..sort((a, b) => a.label.compareTo(b.label));
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isWide = MediaQuery.of(context).size.width > 900;

    return SafeArea(
      child: Column(
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Punto de Venta',
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                // Scanner toggle button
                // Scanner is globally active, no toggle needed
                /*
                IconButton(
                  onPressed: () {},
                  icon: const Icon(Icons.qr_code_scanner, color: Colors.green),
                  tooltip: 'Escáner Activo',
                ),
                */
                const SizedBox(width: 8),
                Consumer<POSService>(
                  builder: (context, posService, child) {
                    return Row(
                      children: [
                        Icon(Icons.person, color: theme.colorScheme.primary),
                        const SizedBox(width: 8),
                        Text(
                          posService.selectedCustomer?.name ?? 'Caja',
                          style: theme.textTheme.titleMedium,
                        ),
                        const SizedBox(width: 16),
                        Chip(
                          avatar: const Icon(Icons.shopping_cart, size: 18),
                          label: Text(
                            '\$${posService.cartTotal.toStringAsFixed(0)}',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          backgroundColor: theme.colorScheme.primaryContainer,
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
          Expanded(
            child: isWide
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Left: Product list OR invoice details (when paying invoice)
                      Expanded(
                        flex: 2,
                        child: Consumer<POSService>(
                          builder: (context, posService, child) {
                            // Show invoice details if in payment mode
                            if (posService.isInvoicePaymentMode &&
                                posService.linkedInvoice != null) {
                              return _buildInvoiceDetailsView(
                                  theme, posService.linkedInvoice!);
                            }
                            // Show normal product grid
                            return Padding(
                              padding: const EdgeInsets.only(
                                  left: 16, right: 8, bottom: 16),
                              child: Column(
                                children: [
                                  // Search bar
                                  SearchBarWidget(
                                    controller: _searchController,
                                    hintText: 'Buscar productos...',
                                    onChanged: (value) {
                                      setState(() {
                                        _searchQuery = value;
                                      });
                                    },
                                  ),
                                  const SizedBox(height: 12),
                                  // Filters
                                  Consumer<InventoryService>(
                                    builder:
                                        (context, inventoryService, child) {
                                      final categoryOptions =
                                          _getCategoryOptions(
                                              inventoryService.products);
                                      final optionsByKey = {
                                        for (final option in categoryOptions)
                                          option.key: option,
                                      };
                                      return Row(
                                        children: [
                                          FilterChip(
                                            label: const Text('Todos'),
                                            selected: _selectedCategoryKey ==
                                                    null &&
                                                _selectedProductType == null,
                                            onSelected: (_) {
                                              setState(() {
                                                _selectedCategoryKey = null;
                                                _selectedCategoryMatchers =
                                                    const <String>{};
                                                _selectedProductType = null;
                                              });
                                            },
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: DropdownButtonFormField<
                                                ProductType?>(
                                              initialValue:
                                                  _selectedProductType,
                                              decoration: const InputDecoration(
                                                labelText: 'Tipo',
                                                border: OutlineInputBorder(),
                                              ),
                                              items: const [
                                                DropdownMenuItem<ProductType?>(
                                                  value: null,
                                                  child:
                                                      Text('Todos los tipos'),
                                                ),
                                                DropdownMenuItem<ProductType?>(
                                                  value: ProductType.product,
                                                  child: Text('Productos'),
                                                ),
                                                DropdownMenuItem<ProductType?>(
                                                  value: ProductType.service,
                                                  child: Text('Servicios'),
                                                ),
                                              ],
                                              onChanged: (value) {
                                                setState(() {
                                                  _selectedProductType = value;
                                                });
                                              },
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: DropdownButtonFormField<
                                                String?>(
                                              initialValue:
                                                  _selectedCategoryKey,
                                              decoration: InputDecoration(
                                                labelText: 'Categorías',
                                                border:
                                                    const OutlineInputBorder(),
                                                suffixIcon: _isLoadingCategories
                                                    ? const Padding(
                                                        padding:
                                                            EdgeInsets.all(12),
                                                        child: SizedBox(
                                                          width: 16,
                                                          height: 16,
                                                          child:
                                                              CircularProgressIndicator(
                                                            strokeWidth: 2,
                                                          ),
                                                        ),
                                                      )
                                                    : null,
                                              ),
                                              isExpanded: true,
                                              items: [
                                                const DropdownMenuItem<String?>(
                                                  value: null,
                                                  child: Text(
                                                      'Todas las categorías'),
                                                ),
                                                ...categoryOptions.map(
                                                  (option) =>
                                                      DropdownMenuItem<String?>(
                                                    value: option.key,
                                                    child: Text(option.label),
                                                  ),
                                                ),
                                              ],
                                              onChanged: (value) {
                                                setState(() {
                                                  _selectedCategoryKey = value;
                                                  _selectedCategoryMatchers =
                                                      value != null
                                                          ? (optionsByKey[value]
                                                                  ?.matchers ??
                                                              const <String>{})
                                                          : const <String>{};
                                                });
                                              },
                                            ),
                                          ),
                                        ],
                                      );
                                    },
                                  ),
                                  const SizedBox(height: 12),
                                  // Products grid
                                  Expanded(
                                    child: Consumer<InventoryService>(
                                      builder:
                                          (context, inventoryService, child) {
                                        final products =
                                            inventoryService.products;
                                        final filteredProducts =
                                            _getFilteredProducts(
                                          products,
                                          categoryMatchers:
                                              _selectedCategoryMatchers,
                                        );
                                        if (products.isEmpty) {
                                          return const Center(
                                            child: Column(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.center,
                                              children: [
                                                Icon(
                                                  Icons.inventory_2_outlined,
                                                  size: 100,
                                                  color: Colors.grey,
                                                ),
                                                SizedBox(height: 16),
                                                Text(
                                                  'No hay productos disponibles',
                                                  style: TextStyle(
                                                      fontSize: 18,
                                                      color: Colors.grey),
                                                ),
                                              ],
                                            ),
                                          );
                                        }
                                        if (filteredProducts.isEmpty) {
                                          return Center(
                                            child: Column(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.center,
                                              children: [
                                                Icon(
                                                  Icons.search_off,
                                                  size: 100,
                                                  color:
                                                      theme.colorScheme.outline,
                                                ),
                                                const SizedBox(height: 16),
                                                Text(
                                                  'No se encontraron productos',
                                                  style: theme
                                                      .textTheme.headlineSmall
                                                      ?.copyWith(
                                                    color: theme.colorScheme
                                                        .onSurfaceVariant,
                                                  ),
                                                ),
                                                const SizedBox(height: 8),
                                                Text(
                                                  'Intenta cambiar los filtros de búsqueda',
                                                  style: theme
                                                      .textTheme.bodyLarge
                                                      ?.copyWith(
                                                    color: theme.colorScheme
                                                        .onSurfaceVariant,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          );
                                        }
                                        return GridView.builder(
                                          padding: const EdgeInsets.all(8),
                                          gridDelegate:
                                              const SliverGridDelegateWithFixedCrossAxisCount(
                                            crossAxisCount: 4,
                                            childAspectRatio: 0.75,
                                            crossAxisSpacing: 8,
                                            mainAxisSpacing: 8,
                                          ),
                                          itemCount: filteredProducts.length,
                                          itemBuilder: (context, index) {
                                            final product =
                                                filteredProducts[index];
                                            return ProductTile(
                                              product: product,
                                              onTap: () => _addToCart(product),
                                            );
                                          },
                                        );
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                      // Right: Cashier/cart summary
                      Container(
                        width: 380,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHighest,
                          border: Border(
                            left: BorderSide(
                              color: theme.colorScheme.outline,
                              width: 1,
                            ),
                          ),
                        ),
                        child: const _CashierPanel(),
                      ),
                    ],
                  )
                : Column(
                    children: [
                      // Product list
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Column(
                            children: [
                              SearchBarWidget(
                                controller: _searchController,
                                hintText: 'Buscar productos...',
                                onChanged: (value) {
                                  setState(() {
                                    _searchQuery = value;
                                  });
                                },
                              ),
                              const SizedBox(height: 12),
                              Consumer<InventoryService>(
                                builder: (context, inventoryService, child) {
                                  final categoryOptions = _getCategoryOptions(
                                      inventoryService.products);
                                  final optionsByKey = {
                                    for (final option in categoryOptions)
                                      option.key: option,
                                  };
                                  return Row(
                                    children: [
                                      FilterChip(
                                        label: const Text('Todos'),
                                        selected:
                                            _selectedCategoryKey == null &&
                                                _selectedProductType == null,
                                        onSelected: (_) {
                                          setState(() {
                                            _selectedCategoryKey = null;
                                            _selectedCategoryMatchers =
                                                const <String>{};
                                            _selectedProductType = null;
                                          });
                                        },
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: DropdownButtonFormField<
                                            ProductType?>(
                                          initialValue: _selectedProductType,
                                          decoration: const InputDecoration(
                                            labelText: 'Tipo',
                                            border: OutlineInputBorder(),
                                          ),
                                          items: const [
                                            DropdownMenuItem<ProductType?>(
                                              value: null,
                                              child: Text('Todos los tipos'),
                                            ),
                                            DropdownMenuItem<ProductType?>(
                                              value: ProductType.product,
                                              child: Text('Productos'),
                                            ),
                                            DropdownMenuItem<ProductType?>(
                                              value: ProductType.service,
                                              child: Text('Servicios'),
                                            ),
                                          ],
                                          onChanged: (value) {
                                            setState(() {
                                              _selectedProductType = value;
                                            });
                                          },
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: DropdownButtonFormField<String?>(
                                          initialValue: _selectedCategoryKey,
                                          decoration: InputDecoration(
                                            labelText: 'Categorías',
                                            border: const OutlineInputBorder(),
                                            suffixIcon: _isLoadingCategories
                                                ? const Padding(
                                                    padding: EdgeInsets.all(12),
                                                    child: SizedBox(
                                                      width: 16,
                                                      height: 16,
                                                      child:
                                                          CircularProgressIndicator(
                                                        strokeWidth: 2,
                                                      ),
                                                    ),
                                                  )
                                                : null,
                                          ),
                                          isExpanded: true,
                                          items: [
                                            const DropdownMenuItem<String?>(
                                              value: null,
                                              child:
                                                  Text('Todas las categorías'),
                                            ),
                                            ...categoryOptions.map(
                                              (option) =>
                                                  DropdownMenuItem<String?>(
                                                value: option.key,
                                                child: Text(option.label),
                                              ),
                                            ),
                                          ],
                                          onChanged: (value) {
                                            setState(() {
                                              _selectedCategoryKey = value;
                                              _selectedCategoryMatchers =
                                                  value != null
                                                      ? (optionsByKey[value]
                                                              ?.matchers ??
                                                          const <String>{})
                                                      : const <String>{};
                                            });
                                          },
                                        ),
                                      ),
                                    ],
                                  );
                                },
                              ),
                              const SizedBox(height: 12),
                              Expanded(
                                child: Consumer<InventoryService>(
                                  builder: (context, inventoryService, child) {
                                    final products = inventoryService.products;
                                    final filteredProducts =
                                        _getFilteredProducts(
                                      products,
                                      categoryMatchers:
                                          _selectedCategoryMatchers,
                                    );
                                    if (products.isEmpty) {
                                      return const Center(
                                        child: Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Icon(
                                              Icons.inventory_2_outlined,
                                              size: 100,
                                              color: Colors.grey,
                                            ),
                                            SizedBox(height: 16),
                                            Text(
                                              'No hay productos disponibles',
                                              style: TextStyle(
                                                  fontSize: 18,
                                                  color: Colors.grey),
                                            ),
                                          ],
                                        ),
                                      );
                                    }
                                    if (filteredProducts.isEmpty) {
                                      return Center(
                                        child: Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Icon(
                                              Icons.search_off,
                                              size: 100,
                                              color: theme.colorScheme.outline,
                                            ),
                                            const SizedBox(height: 16),
                                            Text(
                                              'No se encontraron productos',
                                              style: theme
                                                  .textTheme.headlineSmall
                                                  ?.copyWith(
                                                color: theme.colorScheme
                                                    .onSurfaceVariant,
                                              ),
                                            ),
                                            const SizedBox(height: 8),
                                            Text(
                                              'Intenta cambiar los filtros de búsqueda',
                                              style: theme.textTheme.bodyLarge
                                                  ?.copyWith(
                                                color: theme.colorScheme
                                                    .onSurfaceVariant,
                                              ),
                                            ),
                                          ],
                                        ),
                                      );
                                    }
                                    return GridView.builder(
                                      padding: const EdgeInsets.all(8),
                                      gridDelegate:
                                          const SliverGridDelegateWithFixedCrossAxisCount(
                                        crossAxisCount: 3,
                                        childAspectRatio: 0.75,
                                        crossAxisSpacing: 8,
                                        mainAxisSpacing: 8,
                                      ),
                                      itemCount: filteredProducts.length,
                                      itemBuilder: (context, index) {
                                        final product = filteredProducts[index];
                                        return ProductTile(
                                          product: product,
                                          onTap: () => _addToCart(product),
                                        );
                                      },
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      // Mobile Cart Summary (Sticky Bottom)
                      _MobileCartSummary(
                        onTap: _showMobileCheckout,
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  // Invoice details view - shown in LEFT panel when paying invoice
  Widget _buildInvoiceDetailsView(ThemeData theme, Invoice invoice) {
    final currencyFormat =
        NumberFormat.currency(symbol: '\$', decimalDigits: 0);
    final dateFormat = DateFormat('dd/MM/yyyy');

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with back button
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () {
                  context.read<POSService>().exitInvoicePaymentMode();
                  // Return to pending invoices list
                  final cashierPanel =
                      context.findAncestorStateOfType<_CashierPanelState>();
                  cashierPanel?.setState(() {
                    cashierPanel._showPendingInvoices = true;
                  });
                },
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Pago de Factura',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      invoice.invoiceNumber,
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.orange.shade100,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.orange),
                ),
                child: Text(
                  invoice.status.name.toUpperCase(),
                  style: TextStyle(
                    color: Colors.orange.shade900,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const Divider(height: 32),

          // Invoice info
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Fecha', style: theme.textTheme.bodySmall),
                    const SizedBox(height: 4),
                    Text(
                      dateFormat.format(invoice.date),
                      style: theme.textTheme.bodyLarge,
                    ),
                  ],
                ),
              ),
              if (invoice.reference != null && invoice.reference!.isNotEmpty)
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Referencia', style: theme.textTheme.bodySmall),
                      const SizedBox(height: 4),
                      Text(
                        invoice.reference!,
                        style: theme.textTheme.bodyLarge,
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 24),

          // Line items
          Text(
            'Artículos',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              border: Border.all(color: theme.colorScheme.outline),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Column(
              children: [
                // Header
                Container(
                  padding: const EdgeInsets.all(12),
                  color: theme.colorScheme.surfaceContainerHighest,
                  child: Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: Text(
                          'Producto',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 80,
                        child: Text(
                          'Cant.',
                          textAlign: TextAlign.right,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      SizedBox(
                        width: 100,
                        child: Text(
                          'Precio',
                          textAlign: TextAlign.right,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      SizedBox(
                        width: 100,
                        child: Text(
                          'Total',
                          textAlign: TextAlign.right,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // Items
                ...invoice.items.map((item) {
                  return Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      border: Border(
                        top: BorderSide(color: theme.colorScheme.outline),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.description ?? item.productName ?? '',
                                style: theme.textTheme.bodyLarge,
                              ),
                            ],
                          ),
                        ),
                        SizedBox(
                          width: 80,
                          child: Text(
                            '${item.quantity}',
                            textAlign: TextAlign.right,
                            style: theme.textTheme.bodyLarge,
                          ),
                        ),
                        const SizedBox(width: 16),
                        SizedBox(
                          width: 100,
                          child: Text(
                            currencyFormat.format(item.unitPrice),
                            textAlign: TextAlign.right,
                            style: theme.textTheme.bodyLarge,
                          ),
                        ),
                        const SizedBox(width: 16),
                        SizedBox(
                          width: 100,
                          child: Text(
                            currencyFormat.format(item.lineTotal),
                            textAlign: TextAlign.right,
                            style: theme.textTheme.bodyLarge?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Financial summary
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              children: [
                _buildSummaryRow(
                    theme, 'Subtotal', currencyFormat.format(invoice.subtotal)),
                const SizedBox(height: 8),
                _buildSummaryRow(theme, 'IVA (19%)',
                    currencyFormat.format(invoice.ivaAmount)),
                const Divider(height: 24),
                _buildSummaryRow(
                    theme, 'Total', currencyFormat.format(invoice.total),
                    isTotal: true),
                if (invoice.paidAmount > 0) ...[
                  const SizedBox(height: 8),
                  _buildSummaryRow(theme, 'Pagado',
                      currencyFormat.format(invoice.paidAmount),
                      valueColor: Colors.green),
                  const Divider(height: 24),
                  _buildSummaryRow(
                      theme, 'Saldo', currencyFormat.format(invoice.balance),
                      isTotal: true, valueColor: Colors.red),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryRow(ThemeData theme, String label, String value,
      {bool isTotal = false, Color? valueColor}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: isTotal
              ? theme.textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.bold)
              : theme.textTheme.titleMedium,
        ),
        Text(
          value,
          style: isTotal
              ? theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: valueColor,
                )
              : theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: valueColor,
                ),
        ),
      ],
    );
  }

  void _showMobileCheckout() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.9,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            // Handle for better UX
            Container(
              height: 4,
              width: 40,
              margin: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const Expanded(child: _CashierPanel()),
          ],
        ),
      ),
    );
  }
}

class _CategoryOption {
  _CategoryOption({
    required this.key,
    required this.label,
    Iterable<String> matchers = const <String>[],
  }) : matchers = Set.unmodifiable(
          {
            key,
            ...matchers
                .map((matcher) => matcher.trim())
                .where((value) => value.isNotEmpty),
          },
        );

  final String key;
  final String label;
  final Set<String> matchers;
}

class _CashierPanel extends StatefulWidget {
  const _CashierPanel();

  @override
  State<_CashierPanel> createState() => _CashierPanelState();
}

class _CashierPanelState extends State<_CashierPanel> {
  Customer? _selectedCustomer;
  List<Customer> _customers = [];
  List<Customer> _filteredCustomers = [];
  bool _isLoadingCustomers = true;
  final TextEditingController _customerSearchController =
      TextEditingController();

  // Pending invoices state
  List<Invoice> _pendingInvoices = [];
  bool _showPendingInvoices = false;

  // Invoice payment form state
  String? _selectedPaymentMethodId;
  final TextEditingController _paymentAmountController =
      TextEditingController();
  final TextEditingController _paymentReferenceController =
      TextEditingController();

  // Payment flow state
  bool _showPaymentView = false;
  bool _showReceiptView = false;
  POSTransaction? _completedTransaction;
  pm.PaymentMethod? _selectedPaymentMethod; // ✅ Use shared payment method model
  final TextEditingController _amountController = TextEditingController();
  double _amountReceived = 0.0;
  bool _isProcessing = false;
  final Uuid _uuid = const Uuid();

  // Ad-hoc item inline form state
  bool _showAdHocForm = false;
  final TextEditingController _adHocDescriptionController =
      TextEditingController();
  final TextEditingController _adHocPriceController = TextEditingController();
  final TextEditingController _adHocQuantityController =
      TextEditingController(text: '1');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final posService = context.read<POSService>();
      final paymentMethodService = context.read<PaymentMethodService>();
      paymentMethodService.loadPaymentMethods();
      setState(() {
        _selectedCustomer = posService.selectedCustomer;
      });
    });
    _customerSearchController.addListener(_onSearchChanged);
    // ❌ DON'T initialize to hardcoded value - will be set from cart selection
    _loadCustomers();
  }

  @override
  void dispose() {
    _customerSearchController.removeListener(_onSearchChanged);
    _customerSearchController.dispose();
    _amountController.dispose();
    _adHocDescriptionController.dispose();
    _adHocPriceController.dispose();
    _adHocQuantityController.dispose();
    super.dispose();
  }

  Future<void> _loadCustomers() async {
    try {
      final customerService =
          Provider.of<CustomerService>(context, listen: false);
      final crmCustomers = await customerService.getCustomers();
      final customers = crmCustomers.map((crmCustomer) {
        final fallbackId = crmCustomer.id?.toString() ??
            (crmCustomer.rut.isNotEmpty ? crmCustomer.rut : crmCustomer.name);
        return Customer(
          id: fallbackId,
          name: crmCustomer.name,
          email: crmCustomer.email,
          phone: crmCustomer.phone,
          rut: crmCustomer.rut,
          address: crmCustomer.address,
          city: null,
          region: crmCustomer.region,
          comuna: null,
          type: CustomerType.individual,
          notes: null,
          isActive: crmCustomer.isActive,
          createdAt: crmCustomer.createdAt,
          updatedAt: crmCustomer.updatedAt,
        );
      }).toList();
      if (mounted) {
        setState(() {
          _customers = customers;
          _filteredCustomers = customers;
          _isLoadingCustomers = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingCustomers = false;
        });
      }
    }
  }

  void _onSearchChanged() {
    final query = _customerSearchController.text.toLowerCase();
    setState(() {
      if (query.isEmpty) {
        _filteredCustomers = _customers;
      } else {
        _filteredCustomers = _customers.where((customer) {
          final nameMatch = customer.name.toLowerCase().contains(query);
          final rutMatch = (customer.rut ?? '').toLowerCase().contains(query);
          final emailMatch =
              (customer.email ?? '').toLowerCase().contains(query);
          return nameMatch || rutMatch || emailMatch;
        }).toList();
      }
    });
  }

  void _toggleAdHocForm() {
    setState(() {
      _showAdHocForm = !_showAdHocForm;
      if (!_showAdHocForm) {
        // Clear form when hiding
        _adHocDescriptionController.clear();
        _adHocPriceController.clear();
        _adHocQuantityController.text = '1';
      }
    });
  }

  void _addAdHocItem() {
    final description = _adHocDescriptionController.text.trim();
    final price = double.tryParse(_adHocPriceController.text) ?? 0.0;
    final quantity = int.tryParse(_adHocQuantityController.text) ?? 1;

    if (description.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('La descripción es obligatoria'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    if (price <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('El precio debe ser mayor a 0'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    final posService = Provider.of<POSService>(context, listen: false);
    posService.addAdHocItem(
      description: description,
      price: price,
      quantity: quantity,
    );

    // Clear form and hide
    _adHocDescriptionController.clear();
    _adHocPriceController.clear();
    _adHocQuantityController.text = '1';
    setState(() => _showAdHocForm = false);
  }

  void _proceedToPayment() {
    final posService = Provider.of<POSService>(context, listen: false);
    if (posService.hasItemsInCart) {
      posService.setCustomer(_selectedCustomer);
      setState(() {
        _showPaymentView = true;
        _amountReceived = posService.cartTotal;
        _amountController.text = posService.cartTotal.toStringAsFixed(0);
        // ✅ CRITICAL: Copy selected payment method from cart to payment view
        _selectedPaymentMethod = posService.selectedPaymentMethod;
      });
    }
  }

  void _cancelPayment() {
    setState(() {
      _showPaymentView = false;
      _showReceiptView = false;
      _completedTransaction = null;
      _selectedPaymentMethod =
          null; // ✅ Reset to null instead of hardcoded enum
      _amountReceived = 0.0;
      _amountController.clear();
    });
  }

  /// Check if customer has pending invoices and show them in right panel
  Future<void> _checkPendingInvoices(Customer customer) async {
    if (!mounted) return;

    setState(() {
      _showPendingInvoices = false;
    });

    try {
      final salesService = Provider.of<SalesService>(context, listen: false);

      // Query pending invoices for this customer
      final pendingInvoices = await salesService.getPendingInvoices(
        customerId: customer.id,
      );

      if (!mounted) return;

      setState(() {
        _pendingInvoices = pendingInvoices;
        _showPendingInvoices = pendingInvoices.isNotEmpty;
      });
    } catch (e) {
      debugPrint('Error checking pending invoices: $e');
      if (mounted) {
        setState(() {
          _showPendingInvoices = false;
        });
      }
    }
  }

  void _continueWithNormalSale() {
    setState(() {
      _showPendingInvoices = false;
      _pendingInvoices = [];
    });
  }

  Future<void> _processInvoicePayment(
      POSService posService, Invoice invoice) async {
    // Validate payment method selected
    if (_selectedPaymentMethodId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Por favor seleccione un método de pago'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // Parse payment amount
    final amountText = _paymentAmountController.text.trim();

    // Simple cleaning: just remove $ symbol and spaces, keep the number
    final cleanedText = amountText
        .replaceAll('\$', '')
        .replaceAll(' ', '')
        .replaceAll(',', '') // Remove thousands separator if user typed it
        .trim();

    // Parse as double (handles both integers and decimals)
    final amount = double.tryParse(cleanedText);

    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Por favor ingrese un monto válido'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (amount > invoice.balance) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('El monto ingresado es mayor al saldo pendiente'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() {
      _isProcessing = true;
    });

    try {
      final salesService = Provider.of<SalesService>(context, listen: false);
      final tenantService = TenantService();
      final tenantId = await tenantService.getTenantId();

      if (tenantId == null) {
        throw Exception('No se pudo obtener el tenant ID');
      }

      // CRITICAL: Check if invoice needs to be posted first
      bool wasPosted = false;
      List<String> processedActions = [];

      if (invoice.status == InvoiceStatus.sent ||
          invoice.status == InvoiceStatus.draft) {
        // Invoice hasn't been confirmed/posted yet - need to do it now
        debugPrint(
            '🔄 POS Payment: Invoice ${invoice.invoiceNumber} is in ${invoice.status.name} status');
        debugPrint(
            '📋 POS Payment: Posting invoice first to trigger accounting & inventory...');

        await salesService.updateInvoiceStatus(
            invoice.id!, InvoiceStatus.confirmed);
        wasPosted = true;

        processedActions.add('Factura confirmada');
        processedActions.add('Asiento contable creado');
        processedActions.add('Inventario actualizado');

        debugPrint('✅ POS Payment: Invoice posted successfully');

        // Refresh invoice to get updated data
        final refreshedInvoice =
            await salesService.fetchInvoice(invoice.id!, refresh: true);
        if (refreshedInvoice != null) {
          // Update POSService with refreshed invoice
          posService.enterInvoicePaymentMode(refreshedInvoice);
        }
      }

      // Create payment object
      final payment = Payment(
        tenantId: tenantId,
        invoiceId: invoice.id!,
        invoiceReference:
            invoice.invoiceNumber.isNotEmpty ? invoice.invoiceNumber : null,
        paymentMethodId: _selectedPaymentMethodId!,
        amount: amount,
        date: DateTime.now(),
        reference: _paymentReferenceController.text.trim().isEmpty
            ? null
            : _paymentReferenceController.text.trim(),
      );

      // Register payment
      debugPrint(
          '💰 POS Payment: Recording payment of \$${amount.toStringAsFixed(0)}');
      await salesService.registerPayment(payment);
      processedActions.add('Pago registrado');

      if (!mounted) return;

      // Show detailed success message
      String successMessage =
          'Pago de \$${amount.toStringAsFixed(0)} registrado exitosamente';
      if (wasPosted) {
        successMessage += '\n✓ ${processedActions.join('\n✓ ')}';
        debugPrint('📊 POS Payment: All processes completed:');
        for (var action in processedActions) {
          debugPrint('   ✓ $action');
        }
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(successMessage),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 4),
        ),
      );

      // Clear form
      _paymentAmountController.clear();
      _paymentReferenceController.clear();
      setState(() {
        _selectedPaymentMethodId = null;
      });

      // Exit payment mode and return to pending invoices
      posService.exitInvoicePaymentMode();

      // Reload pending invoices for customer
      if (_selectedCustomer != null) {
        await _checkPendingInvoices(_selectedCustomer!);
      }
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al procesar el pago: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  void _finishTransaction() {
    setState(() {
      _showPaymentView = false;
      _showReceiptView = false;
      _completedTransaction = null;
      _selectedPaymentMethod = null; // ✅ Reset to null
      _amountReceived = 0.0;
      _amountController.clear();
    });
  }

  Future<void> _processPayment() async {
    if (_selectedPaymentMethod == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Seleccione un método de pago')),
      );
      return;
    }

    final posService = context.read<POSService>();
    posService.setCustomer(_selectedCustomer);

    if (_amountReceived < posService.cartTotal) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Monto insuficiente')),
      );
      return;
    }

    // ⚠️ WARN when paying with card but no tax included
    if (_selectedPaymentMethod?.code == 'card' &&
        posService.taxTreatment == TaxTreatment.noTax) {
      final result = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.warning_amber, color: Colors.orange, size: 28),
              SizedBox(width: 12),
              Text('Venta sin IVA - Pago con Tarjeta'),
            ],
          ),
          content: const Text(
            '⚠️ Estás cobrando con TARJETA pero la venta NO tiene IVA.\n\n'
            '¿Cómo proceder?\n\n'
            '• Pagos con tarjeta DEBEN llevar IVA (19%)\n'
            '• Efectivo/transferencia pueden ser sin IVA',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, 'cancel'),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, 'add_tax'),
              style: FilledButton.styleFrom(backgroundColor: Colors.green),
              child: const Text('✓ Agregar IVA (19%)'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, 'no_tax'),
              style: FilledButton.styleFrom(backgroundColor: Colors.orange),
              child: const Text('Continuar sin IVA'),
            ),
          ],
        ),
      );

      if (result == 'cancel' || result == null) return; // User cancelled

      if (result == 'add_tax') {
        // User chose to add tax - update and continue
        posService.setTaxTreatment(TaxTreatment.taxIncluded);
        // UI will update automatically via Consumer
      }
      // If 'no_tax' - just continue
    }

    setState(() {
      _isProcessing = true;
    });

    try {
      final tenantService = Provider.of<TenantService>(context, listen: false);
      final tenantId = await tenantService.getTenantId();
      if (tenantId == null) {
        throw Exception('No se pudo obtener el tenant ID');
      }

      // ✅ Convert new PaymentMethod to old enum-based format for transaction
      final oldMethod = _convertToOldPaymentMethod(_selectedPaymentMethod!);

      final payment = POSPayment(
        id: _uuid.v4(),
        tenantId: tenantId,
        method: oldMethod,
        amount: _amountReceived,
        createdAt: DateTime.now(),
      );

      final transaction = await posService.checkout([payment]);

      if (mounted && transaction != null) {
        setState(() {
          _showPaymentView = false;
          _showReceiptView = true;
          _completedTransaction = transaction;
          _isProcessing = false;
        });
      } else {
        throw Exception('Failed to process transaction');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al procesar pago: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Consumer<POSService>(
      builder: (context, posService, child) {
        final serviceSelected = posService.selectedCustomer;
        if ((serviceSelected?.id ?? '') != (_selectedCustomer?.id ?? '')) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            setState(() {
              _selectedCustomer = serviceSelected;
            });
          });
        }

        final currentQuery = _customerSearchController.text;

        // Show receipt view if transaction completed
        if (_showReceiptView && _completedTransaction != null) {
          return _buildReceiptView(theme, _completedTransaction!);
        }

        // Show payment view if activated
        if (_showPaymentView) {
          return _buildPaymentView(theme, posService);
        }

        // Show cart/checkout view
        return _buildCartView(theme, posService, currentQuery);
      },
    );
  }

  Widget _buildInvoicePaymentForm(ThemeData theme, POSService posService) {
    final invoice = posService.linkedInvoice!;
    final currencyFormat =
        NumberFormat.currency(symbol: '\$', decimalDigits: 0);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Icon(Icons.payment, color: theme.colorScheme.primary, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Procesar Pago',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      invoice.invoiceNumber,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const Divider(height: 32),

          // Customer info
          Text('Cliente', style: theme.textTheme.bodySmall),
          const SizedBox(height: 4),
          Text(
            invoice.customerName ?? 'Sin nombre',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 24),

          // Financial summary
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              children: [
                _buildSummaryRow(
                  theme,
                  'Total Factura',
                  currencyFormat.format(invoice.total),
                ),
                if (invoice.paidAmount > 0) ...[
                  const SizedBox(height: 8),
                  _buildSummaryRow(
                    theme,
                    'Pagado',
                    currencyFormat.format(invoice.paidAmount),
                    valueColor: Colors.green,
                  ),
                  const Divider(height: 20),
                ],
                _buildSummaryRow(
                  theme,
                  'Saldo a Pagar',
                  currencyFormat.format(invoice.balance),
                  isTotal: true,
                  valueColor: Colors.red,
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Payment method selector
          Text(
            'Método de Pago',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          Consumer<PaymentMethodService>(
            builder: (context, paymentMethodService, child) {
              final paymentMethods = paymentMethodService.paymentMethods;
              if (paymentMethods.isEmpty) {
                return const Text('No hay métodos de pago disponibles');
              }

              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children: paymentMethods.map((method) {
                  final isSelected = _selectedPaymentMethodId == method.id;
                  return FilterChip(
                    selected: isSelected,
                    label: Text(method.name),
                    onSelected: (selected) {
                      if (selected) {
                        setState(() {
                          _selectedPaymentMethodId = method.id;
                        });
                      }
                    },
                  );
                }).toList(),
              );
            },
          ),
          const SizedBox(height: 24),

          // Amount input
          Row(
            children: [
              Expanded(
                child: Text(
                  'Monto a Pagar',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              TextButton(
                onPressed: () {
                  setState(() {
                    _paymentAmountController.text =
                        invoice.balance.toStringAsFixed(0);
                  });
                },
                child: const Text('Pagar Total'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _paymentAmountController,
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              labelText: 'Monto en pesos',
              prefix: const Text('\$ '),
              helperText:
                  'Ingrese solo números. Ej: ${invoice.balance.toStringAsFixed(0)}',
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_paymentAmountController.text.isNotEmpty)
                    IconButton(
                      icon: const Icon(Icons.clear, size: 20),
                      onPressed: () {
                        _paymentAmountController.clear();
                        setState(() {});
                      },
                    ),
                ],
              ),
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: false),
            textAlign: TextAlign.right,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
            onChanged: (value) {
              // Trigger rebuild to show/hide clear button
              setState(() {});
            },
          ),
          const SizedBox(height: 24),

          // Payment reference (optional)
          TextField(
            controller: _paymentReferenceController,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'Referencia (opcional)',
              hintText: 'Nº cheque, comprobante, etc.',
            ),
          ),
          const SizedBox(height: 32),

          // Action buttons
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    posService.exitInvoicePaymentMode();
                    setState(() {
                      _showPendingInvoices = true;
                    });
                  },
                  child: const Text('Cancelar'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: FilledButton.icon(
                  onPressed: _selectedPaymentMethodId != null
                      ? () => _processInvoicePayment(posService, invoice)
                      : null,
                  icon: const Icon(Icons.check),
                  label: const Text('Procesar Pago'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // Helper method to access _buildSummaryRow from parent state
  Widget _buildSummaryRow(ThemeData theme, String label, String value,
      {bool isTotal = false, Color? valueColor}) {
    // Access parent's method
    final parentState =
        context.findAncestorStateOfType<_POSDashboardPageState>();
    if (parentState != null) {
      return parentState._buildSummaryRow(theme, label, value,
          isTotal: isTotal, valueColor: valueColor);
    }
    // Fallback implementation
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: theme.textTheme.titleMedium),
        Text(value,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: valueColor,
            )),
      ],
    );
  }

  Widget _buildPendingInvoicesView(ThemeData theme, POSService posService) {
    final currencyFormat =
        NumberFormat.currency(symbol: '\$', decimalDigits: 0);
    final dateFormat = DateFormat('dd/MM/yyyy');

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Icon(Icons.receipt_long,
                  color: theme.colorScheme.primary, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Facturas Pendientes',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      _selectedCustomer?.name ?? '',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // List of pending invoices
          ..._pendingInvoices.map((invoice) {
            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: InkWell(
                onTap: () {
                  // Enter invoice payment mode
                  posService.enterInvoicePaymentMode(invoice);
                  setState(() {
                    _showPendingInvoices = false;
                    // Pre-fill the payment amount with the invoice balance (only if empty)
                    if (_paymentAmountController.text.isEmpty) {
                      _paymentAmountController.text =
                          invoice.balance.toStringAsFixed(0);
                    }
                  });
                },
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            invoice.invoiceNumber,
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.orange.shade100,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: Colors.orange),
                            ),
                            child: Text(
                              invoice.status.name.toUpperCase(),
                              style: TextStyle(
                                color: Colors.orange.shade900,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Fecha: ${dateFormat.format(invoice.date)}',
                        style: theme.textTheme.bodyMedium,
                      ),
                      if (invoice.reference != null &&
                          invoice.reference!.isNotEmpty)
                        Text(
                          'Ref: ${invoice.reference}',
                          style: theme.textTheme.bodyMedium,
                        ),
                      const Divider(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Total', style: theme.textTheme.bodySmall),
                              const SizedBox(height: 4),
                              Text(
                                currencyFormat.format(invoice.total),
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text('Saldo', style: theme.textTheme.bodySmall),
                              const SizedBox(height: 4),
                              Text(
                                currencyFormat.format(invoice.balance),
                                style: theme.textTheme.headlineSmall?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.red,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),

          const SizedBox(height: 20),

          // Continue with normal sale button
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _continueWithNormalSale,
              icon: const Icon(Icons.shopping_cart),
              label: const Text('Continuar con Venta Normal'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCartView(
      ThemeData theme, POSService posService, String currentQuery) {
    // Show pending invoices list if customer has pending invoices
    if (_showPendingInvoices) {
      return _buildPendingInvoicesView(theme, posService);
    }

    // Show invoice payment form if in payment mode
    if (posService.isInvoicePaymentMode && posService.linkedInvoice != null) {
      return _buildInvoicePaymentForm(theme, posService);
    }

    // Show normal cart view
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Resumen de Caja',
            style: theme.textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),

          // Inline ad-hoc item form (shows always)
          if (_showAdHocForm) ...[
            Card(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest
                      .withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: theme.colorScheme.primary.withValues(alpha: 0.3),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.edit_note,
                          size: 20,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Nuevo Item Personalizado',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          icon: const Icon(Icons.close, size: 18),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          onPressed: _toggleAdHocForm,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _adHocDescriptionController,
                      decoration: const InputDecoration(
                        labelText: 'Descripción',
                        hintText: 'Ej: Servicio de ajuste',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                      autofocus: true,
                      textCapitalization: TextCapitalization.sentences,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: TextField(
                            controller: _adHocPriceController,
                            decoration: const InputDecoration(
                              labelText: 'Precio',
                              prefixText: '\$',
                              isDense: true,
                              border: OutlineInputBorder(),
                            ),
                            keyboardType: TextInputType.number,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: _adHocQuantityController,
                            decoration: const InputDecoration(
                              labelText: 'Cant.',
                              isDense: true,
                              border: OutlineInputBorder(),
                            ),
                            keyboardType: TextInputType.number,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _addAdHocItem,
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('Agregar al Carrito'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],

          if (posService.cartItems.isNotEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Productos (${posService.cartTotalItems})',
                          style: theme.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        IconButton(
                          icon: Icon(
                            _showAdHocForm
                                ? Icons.remove_circle_outline
                                : Icons.add_circle_outline,
                            size: 20,
                          ),
                          tooltip: _showAdHocForm
                              ? 'Cancelar'
                              : 'Agregar item personalizado',
                          onPressed: () => _toggleAdHocForm(),
                          style: IconButton.styleFrom(
                            padding: EdgeInsets.zero,
                            minimumSize: const Size(32, 32),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: posService.cartItems.length,
                      separatorBuilder: (_, __) => Divider(
                          color: theme.colorScheme.outline.withValues(alpha: 0.1)),
                      itemBuilder: (context, index) {
                        final item = posService.cartItems[index];
                        return Column(
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        item.displayName,
                                        style: theme.textTheme.titleSmall
                                            ?.copyWith(
                                                fontWeight: FontWeight.w600),
                                      ),
                                      if (item.product != null) ...[
                                        const SizedBox(height: 4),
                                        Text(
                                          'SKU: ${item.product!.sku}',
                                          style: theme.textTheme.bodySmall,
                                        ),
                                      ],
                                      const SizedBox(height: 4),
                                      Text(
                                        '\$${item.unitPrice.toStringAsFixed(0)} c/u',
                                        style:
                                            theme.textTheme.bodySmall?.copyWith(
                                          color: theme.colorScheme.primary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      '\$${item.subtotal.toStringAsFixed(0)}',
                                      style: theme.textTheme.bodyMedium
                                          ?.copyWith(
                                              fontWeight: FontWeight.bold),
                                    ),
                                    const SizedBox(height: 4),
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                          icon: const Icon(
                                              Icons.remove_circle_outline,
                                              size: 20),
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(),
                                          onPressed: () {
                                            if (item.quantity > 1) {
                                              posService.updateCartItemQuantity(
                                                  item.id, item.quantity - 1);
                                            } else {
                                              posService
                                                  .removeFromCart(item.id);
                                            }
                                          },
                                        ),
                                        Padding(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 8),
                                          child: Text(
                                            '${item.quantity}',
                                            style: theme.textTheme.bodyMedium
                                                ?.copyWith(
                                                    fontWeight:
                                                        FontWeight.bold),
                                          ),
                                        ),
                                        IconButton(
                                          icon: const Icon(
                                              Icons.add_circle_outline,
                                              size: 20),
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(),
                                          onPressed: () {
                                            final stockQuantity =
                                                item.product?.stockQuantity;
                                            if (stockQuantity != null &&
                                                item.quantity < stockQuantity) {
                                              posService.updateCartItemQuantity(
                                                  item.id, item.quantity + 1);
                                            } else if (stockQuantity != null) {
                                              ScaffoldMessenger.of(context)
                                                  .showSnackBar(
                                                SnackBar(
                                                  content: Text(
                                                      'Stock máximo: $stockQuantity'),
                                                  duration: const Duration(
                                                      seconds: 1),
                                                ),
                                              );
                                            } else {
                                              // Ad-hoc item (no stock limit)
                                              posService.updateCartItemQuantity(
                                                  item.id, item.quantity + 1);
                                            }
                                          },
                                        ),
                                        const SizedBox(width: 4),
                                        IconButton(
                                          icon: Icon(Icons.delete_outline,
                                              size: 20,
                                              color: theme.colorScheme.error),
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(),
                                          onPressed: () {
                                            posService.removeFromCart(item.id);
                                          },
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          if (posService.cartItems.isNotEmpty)
            const SizedBox(height: 16)
          else
            Card(
              color: theme.colorScheme.surface,
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Icon(Icons.shopping_cart_outlined,
                            color: theme.colorScheme.outline),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'El carrito está vacío. Selecciona productos para comenzar.',
                            style: theme.textTheme.bodyMedium,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        OutlinedButton.icon(
                          onPressed: () => _toggleAdHocForm(),
                          icon: Icon(
                            _showAdHocForm
                                ? Icons.remove_circle_outline
                                : Icons.add_circle_outline,
                            size: 18,
                          ),
                          label: Text(_showAdHocForm
                              ? 'Cancelar'
                              : 'Agregar Item Personalizado'),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          if (posService.cartItems.isNotEmpty) const SizedBox(height: 16),

          // Payment method selector (auto-sets tax treatment)
          if (posService.cartItems.isNotEmpty) ...[
            Text(
              'Método de Pago',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Consumer<PaymentMethodService>(
              builder: (context, paymentMethodService, _) {
                final methods = paymentMethodService.paymentMethods
                    .where((m) => m.isActive)
                    .toList();

                return DropdownButtonFormField<String>(
                  initialValue: posService.selectedPaymentMethod?.id,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.payment),
                    helperText:
                        'El IVA se aplica automáticamente según el método',
                  ),
                  hint: const Text('Seleccionar método'),
                  items: methods.map((method) {
                    return DropdownMenuItem(
                      value: method.id,
                      child: Row(
                        children: [
                          Icon(_getPaymentMethodIcon(method.code), size: 20),
                          const SizedBox(width: 8),
                          Text(method.name),
                        ],
                      ),
                    );
                  }).toList(),
                  onChanged: (methodId) {
                    if (methodId != null) {
                      final method = methods.firstWhere(
                        (m) => m.id == methodId,
                      );
                      posService.setPaymentMethod(method);
                    }
                  },
                );
              },
            ),
            const SizedBox(height: 16),
          ],

          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Show subtotal and discount (before tax)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Subtotal:', style: theme.textTheme.bodyLarge),
                      Text('\$${posService.cartNetAmount.toStringAsFixed(0)}'),
                    ],
                  ),
                  if (posService.cartDiscountAmount > 0) ...[
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Descuento:', style: theme.textTheme.bodyLarge),
                        Text(
                          '-\$${posService.cartDiscountAmount.toStringAsFixed(0)}',
                          style: TextStyle(color: theme.colorScheme.error),
                        ),
                      ],
                    ),
                  ],

                  // Show tax breakdown if tax is included
                  if (posService.taxTreatment == TaxTreatment.taxIncluded) ...[
                    const SizedBox(height: 8),
                    const Divider(),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Neto:', style: theme.textTheme.bodyLarge),
                        Text(
                            '\$${(posService.cartTotal / 1.19).toStringAsFixed(0)}'),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('IVA (19%):', style: theme.textTheme.bodyLarge),
                        Text(
                            '\$${posService.cartTaxAmount.toStringAsFixed(0)}'),
                      ],
                    ),
                  ],

                  const Divider(),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'TOTAL:',
                        style: theme.textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        '\$${posService.cartTotal.toStringAsFixed(0)}',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Cliente',
            style: theme.textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _customerSearchController,
            decoration: const InputDecoration(
              labelText: 'Buscar cliente por nombre, RUT o email',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          if (_isLoadingCustomers)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: LinearProgressIndicator(),
            )
          else ...[
            if (_filteredCustomers.isEmpty && currentQuery.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  'No se encontraron clientes para "$currentQuery"',
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            DropdownButtonFormField<Customer>(
              initialValue: _selectedCustomer,
              decoration: const InputDecoration(
                labelText: 'Seleccionar Cliente (Opcional)',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.person),
              ),
              isExpanded: true,
              items: [
                const DropdownMenuItem<Customer>(
                  value: null,
                  child: Text('Cliente Genérico'),
                ),
                ..._filteredCustomers.map((customer) {
                  return DropdownMenuItem<Customer>(
                    value: customer,
                    child: Text(
                        '${customer.name} - ${(customer.rut ?? customer.email ?? 'Sin RUT')}'),
                  );
                }),
                if (_selectedCustomer != null &&
                    !_filteredCustomers
                        .any((c) => c.id == _selectedCustomer!.id))
                  DropdownMenuItem<Customer>(
                    value: _selectedCustomer,
                    child: Text(
                        '${_selectedCustomer!.name} - ${(_selectedCustomer!.rut ?? _selectedCustomer!.email ?? 'Sin RUT')}'),
                  ),
              ],
              onChanged: (customer) async {
                setState(() {
                  _selectedCustomer = customer;
                });
                context.read<POSService>().setCustomer(customer);

                // Check for pending invoices when customer is selected
                if (customer != null) {
                  await _checkPendingInvoices(customer);
                }
              },
            ),
          ],
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: posService.hasItemsInCart ? _proceedToPayment : null,
              icon: const Icon(Icons.payment),
              label: const Text('Proceder al Pago'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentView(ThemeData theme, POSService posService) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: _cancelPayment,
              ),
              Expanded(
                child: Text(
                  'Procesar Pago',
                  style: theme.textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Order Summary
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Resumen',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Subtotal:', style: theme.textTheme.bodyMedium),
                      Text('\$${posService.cartNetAmount.toStringAsFixed(0)}'),
                    ],
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('IVA (19%):', style: theme.textTheme.bodyMedium),
                      Text('\$${posService.cartTaxAmount.toStringAsFixed(0)}'),
                    ],
                  ),
                  const Divider(),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'TOTAL:',
                        style: theme.textTheme.titleLarge
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        '\$${posService.cartTotal.toStringAsFixed(0)}',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Payment Method
          Text(
            'Método de Pago',
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Consumer<PaymentMethodService>(
            builder: (context, paymentMethodService, _) {
              final methods = paymentMethodService.paymentMethods
                  .where((m) => m.isActive)
                  .toList();

              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children: methods.map((method) {
                  final isSelected = _selectedPaymentMethod?.id == method.id;
                  return FilterChip(
                    label: Text(method.name),
                    selected: isSelected,
                    onSelected: (selected) {
                      setState(() {
                        _selectedPaymentMethod = method;
                        // Auto-set amount for non-cash payments
                        if (method.code != 'cash') {
                          _amountReceived = posService.cartTotal;
                          _amountController.text =
                              posService.cartTotal.toStringAsFixed(0);
                        }
                      });
                    },
                    avatar: Icon(
                      _getPaymentMethodIcon(method.code),
                      size: 18,
                    ),
                  );
                }).toList(),
              );
            },
          ),
          const SizedBox(height: 16),
          // Amount Received (only for cash)
          if (_selectedPaymentMethod?.code == 'cash') ...[
            Text(
              'Monto Recibido',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _amountController,
              onChanged: (value) {
                setState(() {
                  _amountReceived = double.tryParse(value) ?? 0.0;
                });
              },
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Monto en efectivo',
                prefixText: '\$',
                border: const OutlineInputBorder(),
                hintText: posService.cartTotal.toStringAsFixed(0),
              ),
            ),
            const SizedBox(height: 12),
            if (_amountReceived >= posService.cartTotal)
              Card(
                color: theme.colorScheme.primaryContainer,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Vuelto:',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.onPrimaryContainer,
                        ),
                      ),
                      Text(
                        '\$${(_amountReceived - posService.cartTotal).toStringAsFixed(0)}',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 16),
          ],
          // Confirm Payment Button
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _isProcessing ? null : _processPayment,
              icon: _isProcessing
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check),
              label: Text(_isProcessing ? 'Procesando...' : 'Confirmar Pago'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Convert new PaymentMethod model to old enum-based PaymentMethod for transactions
  old_pm.PaymentMethod _convertToOldPaymentMethod(pm.PaymentMethod newMethod) {
    switch (newMethod.code.toLowerCase()) {
      case 'cash':
        return old_pm.PaymentMethod.cash;
      case 'card':
        return old_pm.PaymentMethod.card;
      case 'transfer':
        return old_pm.PaymentMethod.transfer;
      case 'check':
      case 'voucher':
        return old_pm.PaymentMethod.voucher;
      default:
        return old_pm.PaymentMethod.cash; // Default fallback
    }
  }

  IconData _getPaymentMethodIcon(String code) {
    switch (code.toLowerCase()) {
      case 'cash':
        return Icons.attach_money;
      case 'card':
        return Icons.credit_card;
      case 'transfer':
        return Icons.account_balance;
      case 'check':
        return Icons.receipt;
      default:
        return Icons.payment;
    }
  }

  Widget _buildReceiptView(ThemeData theme, POSTransaction transaction) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Success Header
          Card(
            color: theme.colorScheme.primaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Icon(
                    Icons.check_circle,
                    size: 64,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '¡Venta Exitosa!',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
                  Text(
                    'Transacción completada correctamente',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Receipt Details
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'VINABIKE',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const Center(
                    child: Text(
                      'Venta de Bicicletas y Accesorios',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                  const Divider(height: 24),
                  _buildReceiptRow('Recibo:',
                      transaction.receiptNumber ?? transaction.id, theme),
                  _buildReceiptRow(
                    'Fecha:',
                    '${transaction.createdAt.day.toString().padLeft(2, '0')}/${transaction.createdAt.month.toString().padLeft(2, '0')}/${transaction.createdAt.year} ${transaction.createdAt.hour.toString().padLeft(2, '0')}:${transaction.createdAt.minute.toString().padLeft(2, '0')}',
                    theme,
                  ),
                  _buildReceiptRow(
                    'Cliente:',
                    transaction.customer?.name ?? 'Cliente Genérico',
                    theme,
                  ),
                  const Divider(height: 24),
                  // Items
                  ...transaction.items.map((item) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.displayName,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  '${item.quantity} x \$${item.unitPrice.toStringAsFixed(0)}',
                                  style: theme.textTheme.bodySmall,
                                ),
                                Text(
                                  '\$${item.subtotal.toStringAsFixed(0)}',
                                  style: theme.textTheme.bodyMedium,
                                ),
                              ],
                            ),
                          ],
                        ),
                      )),
                  const Divider(height: 24),
                  _buildReceiptRow('Subtotal:',
                      '\$${transaction.subtotal.toStringAsFixed(0)}', theme),
                  _buildReceiptRow('IVA (19%):',
                      '\$${transaction.taxAmount.toStringAsFixed(0)}', theme),
                  const Divider(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'TOTAL:',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        '\$${transaction.total.toStringAsFixed(0)}',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 24),
                  // Payment Info
                  ...transaction.payments.map((payment) => _buildReceiptRow(
                        payment.method.name,
                        '\$${payment.amount.toStringAsFixed(0)}',
                        theme,
                      )),
                  const SizedBox(height: 16),
                  const Center(
                    child: Text(
                      '¡Gracias por su compra!',
                      style: TextStyle(
                        fontSize: 12,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                  const Center(
                    child: Text(
                      'Garantía 30 días',
                      style: TextStyle(fontSize: 10),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Actions
          FilledButton.icon(
            onPressed: _finishTransaction,
            icon: const Icon(Icons.check),
            label: const Text('Nueva Venta'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReceiptRow(String label, String value, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: theme.textTheme.bodyMedium),
          Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _MobileCartSummary extends StatelessWidget {
  final VoidCallback onTap;

  const _MobileCartSummary({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Consumer<POSService>(
      builder: (context, posService, _) {
        final itemCount =
            posService.cartItems.fold(0, (sum, item) => sum + item.quantity);
        final total = posService.cartTotal;

        return Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                blurRadius: 8,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '$itemCount items',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        Text(
                          '\$${total.toStringAsFixed(0)}',
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: onTap,
                    icon: const Icon(Icons.shopping_cart_checkout),
                    label: const Text('Ver Carrito'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
