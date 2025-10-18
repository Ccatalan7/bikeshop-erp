import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../../shared/models/product.dart';
import '../../../shared/models/customer.dart';
import '../../crm/services/customer_service.dart';
import '../../inventory/models/category_models.dart' as inventory_models;
import '../../inventory/services/category_service.dart';
import '../../../shared/services/inventory_service.dart';
import '../../../shared/services/payment_method_service.dart';
import '../../../shared/widgets/search_bar_widget.dart';
import '../services/pos_service.dart';
import '../widgets/product_tile.dart';
import '../models/payment_method.dart';
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
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
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
                      // Left: Product list, search, filters
                      Expanded(
                        flex: 2,
                        child: Padding(
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
                                          value: _selectedProductType,
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
                                          value: _selectedCategoryKey,
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
                              // Products grid
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
                                        crossAxisCount: 4,
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
                      // Right: Cashier/cart summary
                      Container(
                        width: 380,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceVariant,
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
                                          value: _selectedProductType,
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
                                          value: _selectedCategoryKey,
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
                      // Cashier panel
                      SizedBox(
                        width: double.infinity,
                        child: const _CashierPanel(),
                      ),
                    ],
                  ),
          ),
        ],
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

  // Payment flow state
  bool _showPaymentView = false;
  bool _showReceiptView = false;
  POSTransaction? _completedTransaction;
  PaymentMethod? _selectedPaymentMethod;
  final TextEditingController _amountController = TextEditingController();
  double _amountReceived = 0.0;
  bool _isProcessing = false;
  final Uuid _uuid = const Uuid();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final posService = context.read<POSService>();
      setState(() {
        _selectedCustomer = posService.selectedCustomer;
      });
    });
    _customerSearchController.addListener(_onSearchChanged);
    _selectedPaymentMethod = PaymentMethod.cash;
    _loadCustomers();
  }

  @override
  void dispose() {
    _customerSearchController.removeListener(_onSearchChanged);
    _customerSearchController.dispose();
    _amountController.dispose();
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

  void _proceedToPayment() {
    final posService = Provider.of<POSService>(context, listen: false);
    if (posService.hasItemsInCart) {
      posService.setCustomer(_selectedCustomer);
      setState(() {
        _showPaymentView = true;
        _amountReceived = posService.cartTotal;
        _amountController.text = posService.cartTotal.toStringAsFixed(0);
      });
    }
  }

  void _cancelPayment() {
    setState(() {
      _showPaymentView = false;
      _showReceiptView = false;
      _completedTransaction = null;
      _selectedPaymentMethod = PaymentMethod.cash;
      _amountReceived = 0.0;
      _amountController.clear();
    });
  }

  void _finishTransaction() {
    setState(() {
      _showPaymentView = false;
      _showReceiptView = false;
      _completedTransaction = null;
      _selectedPaymentMethod = PaymentMethod.cash;
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

    setState(() {
      _isProcessing = true;
    });

    try {
      final payment = POSPayment(
        id: _uuid.v4(),
        method: _selectedPaymentMethod!,
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

  Widget _buildCartView(
      ThemeData theme, POSService posService, String currentQuery) {
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
          if (posService.cartItems.isNotEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Productos (${posService.cartTotalItems})',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
                    ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: posService.cartItems.length,
                      separatorBuilder: (_, __) => Divider(
                          color: theme.colorScheme.outline.withOpacity(0.1)),
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
                                        item.product.name,
                                        style: theme.textTheme.titleSmall
                                            ?.copyWith(
                                                fontWeight: FontWeight.w600),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'SKU: ${item.product.sku}',
                                        style: theme.textTheme.bodySmall,
                                      ),
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
                                            if (item.quantity <
                                                item.product.stockQuantity) {
                                              posService.updateCartItemQuantity(
                                                  item.id, item.quantity + 1);
                                            } else {
                                              ScaffoldMessenger.of(context)
                                                  .showSnackBar(
                                                SnackBar(
                                                  content: Text(
                                                      'Stock máximo: ${item.product.stockQuantity}'),
                                                  duration: const Duration(
                                                      seconds: 1),
                                                ),
                                              );
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
                child: Row(
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
              ),
            ),
          if (posService.cartItems.isNotEmpty) const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Subtotal:', style: theme.textTheme.bodyLarge),
                      Text('\$${posService.cartNetAmount.toStringAsFixed(0)}'),
                    ],
                  ),
                  if (posService.cartDiscountAmount > 0)
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
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('IVA (19%):', style: theme.textTheme.bodyLarge),
                      Text('\$${posService.cartTaxAmount.toStringAsFixed(0)}'),
                    ],
                  ),
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
              value: _selectedCustomer,
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
              onChanged: (customer) {
                setState(() {
                  _selectedCustomer = customer;
                });
                context.read<POSService>().setCustomer(customer);
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
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: PaymentMethod.defaultMethods.map((method) {
              final isSelected = _selectedPaymentMethod?.id == method.id;
              return FilterChip(
                label: Text(method.name),
                selected: isSelected,
                onSelected: (selected) {
                  setState(() {
                    _selectedPaymentMethod = method;
                    if (method != PaymentMethod.cash) {
                      _amountReceived = posService.cartTotal;
                      _amountController.text =
                          posService.cartTotal.toStringAsFixed(0);
                    }
                  });
                },
                avatar: Icon(
                  _getPaymentIcon(method.type),
                  size: 18,
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
          // Amount Received (only for cash)
          if (_selectedPaymentMethod == PaymentMethod.cash) ...[
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

  IconData _getPaymentIcon(PaymentType type) {
    switch (type) {
      case PaymentType.cash:
        return Icons.attach_money;
      case PaymentType.card:
        return Icons.credit_card;
      case PaymentType.voucher:
        return Icons.receipt;
      case PaymentType.transfer:
        return Icons.account_balance;
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
                              item.product.name,
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
