import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/models/product.dart';
import '../../../shared/models/customer.dart';
import '../../../shared/themes/app_theme.dart';
import '../../crm/services/customer_service.dart';
import '../../../shared/services/inventory_service.dart';
import '../../../shared/widgets/search_bar_widget.dart';
import '../services/pos_service.dart';
import '../widgets/product_tile.dart';

class POSDashboardPage extends StatefulWidget {
  const POSDashboardPage({super.key});

  @override
  State<POSDashboardPage> createState() => _POSDashboardPageState();
}

class _POSDashboardPageState extends State<POSDashboardPage> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String? _selectedCategoryId;

  @override
  void initState() {
    super.initState();
    // Load products from Firestore when page loads
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final inventoryService = Provider.of<InventoryService>(context, listen: false);
      inventoryService.getProducts();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _addToCart(Product product, {int quantity = 1}) {
    final posService = Provider.of<POSService>(context, listen: false);
    
    // Check stock availability
    if (product.stockQuantity < quantity) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Stock insuficiente. Disponible: ${product.stockQuantity}'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    try {
      posService.addToCart(product, quantity: quantity);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${product.name} agregado al carrito'),
            action: SnackBarAction(
              label: 'Ver Carrito',
              onPressed: () {
                if (mounted) {
                  context.push('/pos/cart');
                }
              },
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al agregar producto: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  List<Product> _getFilteredProducts(List<Product> products) {
    return products.where((product) {
      final matchesSearch = _searchQuery.isEmpty ||
          product.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          product.sku.toLowerCase().contains(_searchQuery.toLowerCase());

      final matchesCategory = _selectedCategoryId == null ||
          product.category.name == _selectedCategoryId;

      return matchesSearch && matchesCategory && product.stockQuantity > 0;
    }).toList();
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
                        FloatingActionButton.extended(
                          onPressed: () => context.push('/pos/cart'),
                          icon: const Icon(Icons.shopping_cart),
                          label: Text(
                            '\$${posService.cartTotal.toStringAsFixed(0)}',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
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
                          padding: const EdgeInsets.only(left: 16, right: 8, bottom: 16),
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
                              // Category filter
                              SizedBox(
                                height: 40,
                                child: ListView(
                                  scrollDirection: Axis.horizontal,
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.only(right: 8),
                                      child: FilterChip(
                                        label: const Text('Todos'),
                                        selected: _selectedCategoryId == null,
                                        onSelected: (selected) {
                                          setState(() {
                                            _selectedCategoryId = null;
                                          });
                                        },
                                      ),
                                    ),
                                    ...ProductCategory.values.map((category) {
                                      final isSelected = _selectedCategoryId == category.name;
                                      return Padding(
                                        padding: const EdgeInsets.only(right: 8),
                                        child: FilterChip(
                                          label: Text(category.displayName),
                                          selected: isSelected,
                                          onSelected: (selected) {
                                            setState(() {
                                              _selectedCategoryId = selected ? category.name : null;
                                            });
                                          },
                                        ),
                                      );
                                    }),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 12),
                              // Products grid
                              Expanded(
                                child: Consumer<InventoryService>(
                                  builder: (context, inventoryService, child) {
                                    final products = inventoryService.products;
                                    final filteredProducts = _getFilteredProducts(products);
                                    if (products.isEmpty) {
                                      return const Center(
                                        child: Column(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Icon(
                                              Icons.inventory_2_outlined,
                                              size: 100,
                                              color: Colors.grey,
                                            ),
                                            SizedBox(height: 16),
                                            Text(
                                              'No hay productos disponibles',
                                              style: TextStyle(fontSize: 18, color: Colors.grey),
                                            ),
                                          ],
                                        ),
                                      );
                                    }
                                    if (filteredProducts.isEmpty) {
                                      return Center(
                                        child: Column(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Icon(
                                              Icons.search_off,
                                              size: 100,
                                              color: theme.colorScheme.outline,
                                            ),
                                            const SizedBox(height: 16),
                                            Text(
                                              'No se encontraron productos',
                                              style: theme.textTheme.headlineSmall?.copyWith(
                                                color: theme.colorScheme.onSurfaceVariant,
                                              ),
                                            ),
                                            const SizedBox(height: 8),
                                            Text(
                                              'Intenta cambiar los filtros de búsqueda',
                                              style: theme.textTheme.bodyLarge?.copyWith(
                                                color: theme.colorScheme.onSurfaceVariant,
                                              ),
                                            ),
                                          ],
                                        ),
                                      );
                                    }
                                    return GridView.builder(
                                      padding: const EdgeInsets.all(8),
                                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                        crossAxisCount: 2,
                                        childAspectRatio: 0.8,
                                        crossAxisSpacing: 12,
                                        mainAxisSpacing: 12,
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
                              const SizedBox(height: 8),
                              SizedBox(
                                height: 40,
                                child: ListView(
                                  scrollDirection: Axis.horizontal,
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.only(right: 8),
                                      child: FilterChip(
                                        label: const Text('Todos'),
                                        selected: _selectedCategoryId == null,
                                        onSelected: (selected) {
                                          setState(() {
                                            _selectedCategoryId = null;
                                          });
                                        },
                                      ),
                                    ),
                                    ...ProductCategory.values.map((category) {
                                      final isSelected = _selectedCategoryId == category.name;
                                      return Padding(
                                        padding: const EdgeInsets.only(right: 8),
                                        child: FilterChip(
                                          label: Text(category.displayName),
                                          selected: isSelected,
                                          onSelected: (selected) {
                                            setState(() {
                                              _selectedCategoryId = selected ? category.name : null;
                                            });
                                          },
                                        ),
                                      );
                                    }),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 8),
                              Expanded(
                                child: Consumer<InventoryService>(
                                  builder: (context, inventoryService, child) {
                                    final products = inventoryService.products;
                                    final filteredProducts = _getFilteredProducts(products);
                                    if (products.isEmpty) {
                                      return const Center(
                                        child: Column(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Icon(
                                              Icons.inventory_2_outlined,
                                              size: 100,
                                              color: Colors.grey,
                                            ),
                                            SizedBox(height: 16),
                                            Text(
                                              'No hay productos disponibles',
                                              style: TextStyle(fontSize: 18, color: Colors.grey),
                                            ),
                                          ],
                                        ),
                                      );
                                    }
                                    if (filteredProducts.isEmpty) {
                                      return Center(
                                        child: Column(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Icon(
                                              Icons.search_off,
                                              size: 100,
                                              color: theme.colorScheme.outline,
                                            ),
                                            const SizedBox(height: 16),
                                            Text(
                                              'No se encontraron productos',
                                              style: theme.textTheme.headlineSmall?.copyWith(
                                                color: theme.colorScheme.onSurfaceVariant,
                                              ),
                                            ),
                                            const SizedBox(height: 8),
                                            Text(
                                              'Intenta cambiar los filtros de búsqueda',
                                              style: theme.textTheme.bodyLarge?.copyWith(
                                                color: theme.colorScheme.onSurfaceVariant,
                                              ),
                                            ),
                                          ],
                                        ),
                                      );
                                    }
                                    return GridView.builder(
                                      padding: const EdgeInsets.all(8),
                                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                        crossAxisCount: 2,
                                        childAspectRatio: 0.8,
                                        crossAxisSpacing: 12,
                                        mainAxisSpacing: 12,
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
  final TextEditingController _customerSearchController = TextEditingController();

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
    _loadCustomers();
  }

  @override
  void dispose() {
    _customerSearchController.removeListener(_onSearchChanged);
    _customerSearchController.dispose();
    super.dispose();
  }

  Future<void> _loadCustomers() async {
    try {
      final customerService = Provider.of<CustomerService>(context, listen: false);
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
          final emailMatch = (customer.email ?? '').toLowerCase().contains(query);
          return nameMatch || rutMatch || emailMatch;
        }).toList();
      }
    });
  }

  void _proceedToPayment() {
    final posService = Provider.of<POSService>(context, listen: false);
    if (posService.hasItemsInCart) {
      posService.setCustomer(_selectedCustomer);
      context.push('/pos/payment');
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

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Resumen de Caja',
                style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
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
                          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 12),
                        ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: posService.cartItems.length,
                          separatorBuilder: (_, __) => Divider(color: theme.colorScheme.outline.withOpacity(0.1)),
                          itemBuilder: (context, index) {
                            final item = posService.cartItems[index];
                            return Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        item.product.name,
                                        style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'SKU: ${item.product.sku}',
                                        style: theme.textTheme.bodySmall,
                                      ),
                                    ],
                                  ),
                                ),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text('x${item.quantity}', style: theme.textTheme.bodyMedium),
                                    Text(
                                      '\$${item.subtotal.toStringAsFixed(0)}',
                                      style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
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
                        Icon(Icons.shopping_cart_outlined, color: theme.colorScheme.outline),
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
                            style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
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
                style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
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
                        child: Text('${customer.name} - ${(customer.rut ?? customer.email ?? 'Sin RUT')}'),
                      );
                    }).toList(),
                    if (_selectedCustomer != null &&
                        !_filteredCustomers.any((c) => c.id == _selectedCustomer!.id))
                      DropdownMenuItem<Customer>(
                        value: _selectedCustomer,
                        child: Text('${_selectedCustomer!.name} - ${( _selectedCustomer!.rut ?? _selectedCustomer!.email ?? 'Sin RUT')}'),
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
      },
    );
  }
}