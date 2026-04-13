import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../../../shared/models/product.dart';
import '../../../shared/models/customer.dart';
import '../../../shared/models/tax_treatment.dart';
import '../../../shared/models/payment_method.dart' as pm;
import '../../../shared/widgets/branded_loading.dart';
import '../../crm/services/customer_service.dart';
import '../../inventory/models/category_models.dart' as inventory_models;
import '../../inventory/services/category_service.dart';
import '../../../shared/services/inventory_service.dart';
import '../../../shared/services/payment_method_service.dart';
import '../../../shared/services/barcode_scanner_service.dart';
import '../../../shared/services/tenant_service.dart';
import '../../sales/models/sales_models.dart';
import '../../sales/services/sales_service.dart';
import '../services/pos_service.dart';
import '../models/pos_cart_item.dart';
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

  // Cart panel width (resizable)
  static const double _cartMinWidth = 280.0;
  static const double _cartMaxWidth = 600.0;
  static const double _cartDefaultWidth = 380.0;
  double _cartPanelWidth = _cartDefaultWidth;
  static const String _cartWidthPrefKey = 'pos_cart_panel_width';

  // ── Filtered products cache (never recomputed on cart/customer changes) ─
  List<Product> _cachedFilteredProducts = const [];
  bool _inventoryIsLoading = true;
  bool _inventoryHasLoaded = false;
  InventoryService? _inventoryServiceRef;

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
    // Load persisted cart panel width
    SharedPreferences.getInstance().then((prefs) {
      final saved = prefs.getDouble(_cartWidthPrefKey);
      if (saved != null && mounted) {
        setState(
            () => _cartPanelWidth = saved.clamp(_cartMinWidth, _cartMaxWidth));
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final inventoryService =
          Provider.of<InventoryService>(context, listen: false);
      final paymentMethodService =
          Provider.of<PaymentMethodService>(context, listen: false);
      final categoryService =
          Provider.of<CategoryService>(context, listen: false);

      _inventoryServiceRef = inventoryService;
      inventoryService.addListener(_onInventoryChanged);
      // Seed cache from whatever is already preloaded
      _inventoryIsLoading = inventoryService.isLoading;
      _inventoryHasLoaded = inventoryService.hasLoaded;
      _cachedFilteredProducts = _getFilteredProducts(
        inventoryService.products,
        categoryMatchers: const <String>{},
      );
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
    _inventoryServiceRef?.removeListener(_onInventoryChanged);
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
      final matchesSearch =
          _searchQuery.isEmpty || _matchesTokenSearch(_searchQuery, product);

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

  String _normalizeText(String text) {
    if (text.isEmpty) return text;

    String normalized = text.toLowerCase();
    normalized = normalized.replaceAll(RegExp(r'[áàäâ]'), 'a');
    normalized = normalized.replaceAll(RegExp(r'[éèëê]'), 'e');
    normalized = normalized.replaceAll(RegExp(r'[íìïî]'), 'i');
    normalized = normalized.replaceAll(RegExp(r'[óòöô]'), 'o');
    normalized = normalized.replaceAll(RegExp(r'[úùüû]'), 'u');
    normalized = normalized.replaceAll(RegExp(r'[ñ]'), 'n');
    normalized = normalized.replaceAll(RegExp(r'[ç]'), 'c');
    return normalized;
  }

  String _stemSearchTerm(String term) {
    if (term.length <= 3) return term;

    if (term.endsWith('es')) {
      if (term == 'mes' || term == 'tres') return term;
      final beforeEs = term.substring(0, term.length - 2);
      if (beforeEs.isNotEmpty) {
        final lastChar = beforeEs[beforeEs.length - 1];
        if ('ldrn'.contains(lastChar)) return beforeEs;
      }
    }

    if (term.endsWith('s')) {
      if (term == 'cas' ||
          term == 'dos' ||
          term == 'mas' ||
          term == 'las' ||
          term == 'los' ||
          term == 'sus') {
        return term;
      }
      return term.substring(0, term.length - 1);
    }

    return term;
  }

  bool _matchesTokenSearch(String query, Product product) {
    if (query.isEmpty) return true;

    final rawTokens = query.toLowerCase().split(RegExp(r'\s+'));
    final tokens = rawTokens
        .map((token) => _stemSearchTerm(_normalizeText(token)))
        .toList();

    final searchableText = [
      _normalizeText(product.name),
      _normalizeText(product.sku),
      _normalizeText(product.supplierCode ?? ''),
      _normalizeText(product.brand ?? ''),
      _normalizeText(product.model ?? ''),
      _normalizeText(_categoryLabelFor(product)),
    ].join(' ');

    return tokens.every((token) {
      if (RegExp(r'^\d+$').hasMatch(token)) {
        return RegExp('(?:^|\\s|[^0-9])$token(?:\$|\\s|[^0-9])')
            .hasMatch(searchableText);
      }
      return searchableText.contains(token);
    });
  }

  bool get _hasActiveProductFilters =>
      _searchQuery.isNotEmpty ||
      _selectedCategoryKey != null ||
      _selectedProductType != null;

  void _onProductSearchChanged(String value) {
    final svc = _inventoryServiceRef;
    setState(() {
      _searchQuery = value.trim();
      if (svc != null) {
        _cachedFilteredProducts = _getFilteredProducts(
          svc.products,
          categoryMatchers: _selectedCategoryMatchers,
        );
      }
    });
  }

  void _resetProductFilters() {
    final svc = _inventoryServiceRef;
    setState(() {
      _searchController.clear();
      _searchQuery = '';
      _selectedCategoryKey = null;
      _selectedCategoryMatchers = const <String>{};
      _selectedProductType = null;
      if (svc != null) {
        _cachedFilteredProducts = _getFilteredProducts(
          svc.products,
          categoryMatchers: const <String>{},
        );
      }
    });
  }

  void _onInventoryChanged() {
    if (!mounted) return;
    final svc = _inventoryServiceRef;
    if (svc == null) return;
    setState(() {
      _inventoryIsLoading = svc.isLoading;
      _inventoryHasLoaded = svc.hasLoaded;
      _cachedFilteredProducts = _getFilteredProducts(
        svc.products,
        categoryMatchers: _selectedCategoryMatchers,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    debugPrint('🔴 [POS] _POSDashboardPageState.build() called');
    final theme = Theme.of(context);
    final screenWidth = MediaQuery.of(context).size.width;
    final isWide = screenWidth > 900;

    return SafeArea(
      child: Column(
        children: [
          _POSHeaderBar(screenWidth: screenWidth),
          Expanded(
            child: isWide
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        flex: 8,
                        child: Selector<POSService, (bool, Invoice?)>(
                          selector: (_, svc) =>
                              (svc.isInvoicePaymentMode, svc.linkedInvoice),
                          builder: (context, invoiceState, child) {
                            debugPrint(
                                '🟡 [POS] Selector<POSService> builder called (isInvoiceMode=${invoiceState.$1})');
                            final isInvoiceMode = invoiceState.$1;
                            final linkedInvoice = invoiceState.$2;
                            if (isInvoiceMode && linkedInvoice != null) {
                              return _buildInvoiceDetailsView(
                                  theme, linkedInvoice);
                            }
                            return _buildProductPanel(theme);
                          },
                        ),
                      ),
                      // ── Resizable cart pane ────────────────────────────
                      // A thin 8px drag strip sits over the left border only.
                      // The rest of the pane keeps the default cursor.
                      SizedBox(
                        width: _cartPanelWidth,
                        child: Stack(
                          children: [
                            // Cart content (full width)
                            Positioned.fill(
                              child: Container(
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.surface,
                                  border: Border(
                                    left: BorderSide(
                                      color: theme.colorScheme.outlineVariant
                                          .withValues(alpha: 0.5),
                                    ),
                                  ),
                                ),
                                child: const _CashierPanel(),
                              ),
                            ),
                            // 8px drag strip on the left edge only
                            Positioned(
                              left: 0,
                              top: 0,
                              bottom: 0,
                              width: 8,
                              child: MouseRegion(
                                cursor: SystemMouseCursors.resizeColumn,
                                child: GestureDetector(
                                  behavior: HitTestBehavior.translucent,
                                  onHorizontalDragUpdate: (details) {
                                    setState(() {
                                      _cartPanelWidth = (_cartPanelWidth -
                                              details.delta.dx)
                                          .clamp(_cartMinWidth, _cartMaxWidth);
                                    });
                                  },
                                  onHorizontalDragEnd: (_) {
                                    SharedPreferences.getInstance().then(
                                      (prefs) => prefs.setDouble(
                                          _cartWidthPrefKey, _cartPanelWidth),
                                    );
                                  },
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  )
                : Column(
                    children: [
                      Expanded(child: _buildProductPanel(theme)),
                      _MobileCartSummary(onTap: _showMobileCheckout),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildProductPanel(ThemeData theme) {
    debugPrint('🟠 [POS] _buildProductPanel() called');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Search + Filter toolbar ──────────────────────────────────────
        Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerLowest,
            border: Border(
              bottom: BorderSide(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
              ),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                height: 42,
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color:
                        theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
                  ),
                ),
                child: TextField(
                  controller: _searchController,
                  onChanged: _onProductSearchChanged,
                  textAlignVertical: TextAlignVertical.center,
                  style: theme.textTheme.bodyMedium,
                  decoration: InputDecoration(
                    hintText:
                        'Buscar por nombre, SKU, marca, modelo o categoría...',
                    hintStyle: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant
                          .withValues(alpha: 0.7),
                    ),
                    prefixIcon: Padding(
                      padding: const EdgeInsets.only(left: 12, right: 8),
                      child: Icon(
                        Icons.search_rounded,
                        size: 20,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    prefixIconConstraints:
                        const BoxConstraints(minWidth: 0, minHeight: 0),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: Icon(Icons.close_rounded,
                                size: 18,
                                color: theme.colorScheme.onSurfaceVariant),
                            onPressed: _resetProductFilters,
                          )
                        : null,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    border: InputBorder.none,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Builder(
                builder: (context) {
                  final categoryOptions = _serviceCategoryOptions;
                  final selectedCategory = _selectedCategoryKey == null
                      ? null
                      : _findCategoryOptionByKey(
                          categoryOptions, _selectedCategoryKey!);

                  return Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _SearchableSelectorField<ProductType>(
                        width: 150,
                        hint: 'Tipo',
                        allLabel: 'Tipo: Todos',
                        value: _selectedProductType,
                        items: ProductType.values,
                        labelBuilder: (type) => type.displayName,
                        onChanged: (value) {
                          final svc = _inventoryServiceRef;
                          setState(() {
                            _selectedProductType = value;
                            if (svc != null) {
                              _cachedFilteredProducts = _getFilteredProducts(
                                svc.products,
                                categoryMatchers: _selectedCategoryMatchers,
                              );
                            }
                          });
                        },
                      ),
                      if (_isLoadingCategories && categoryOptions.isEmpty)
                        Container(
                          width: 190,
                          height: 36,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: theme.colorScheme.outlineVariant,
                            ),
                          ),
                          alignment: Alignment.centerLeft,
                          child: SizedBox(
                            height: 2,
                            child: LinearProgressIndicator(
                              backgroundColor: Colors.transparent,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        )
                      else
                        _SearchableSelectorField<_CategoryOption>(
                          width: 190,
                          hint: 'Categoría',
                          allLabel: 'Categoría: Todas',
                          value: selectedCategory,
                          items: categoryOptions,
                          labelBuilder: (option) => option.label,
                          onChanged: (value) {
                            final svc = _inventoryServiceRef;
                            setState(() {
                              _selectedCategoryKey = value?.key;
                              _selectedCategoryMatchers =
                                  value?.matchers ?? const <String>{};
                              if (svc != null) {
                                _cachedFilteredProducts = _getFilteredProducts(
                                  svc.products,
                                  categoryMatchers:
                                      value?.matchers ?? const <String>{},
                                );
                              }
                            });
                          },
                        ),
                      if (_hasActiveProductFilters)
                        TextButton.icon(
                          onPressed: _resetProductFilters,
                          icon: const Icon(Icons.close_rounded, size: 14),
                          label: const Text('Limpiar'),
                          style: TextButton.styleFrom(
                            minimumSize: const Size(0, 36),
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
        // ── Product Grid (cached, not rebuilt on cart/customer changes) ──
        Expanded(
          child: _buildProductGrid(theme),
        ),
      ],
    );
  }

  Widget _buildProductGrid(ThemeData theme) {
    final allProducts = _inventoryServiceRef?.products ?? const [];

    if (allProducts.isEmpty && (_inventoryIsLoading || !_inventoryHasLoaded)) {
      return const Center(child: BrandedLoading());
    }
    if (allProducts.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inventory_2_outlined,
                size: 72, color: theme.colorScheme.outlineVariant),
            const SizedBox(height: 16),
            Text('Sin productos',
                style: theme.textTheme.titleLarge
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ],
        ),
      );
    }
    if (_cachedFilteredProducts.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off_rounded,
                size: 72, color: theme.colorScheme.outlineVariant),
            const SizedBox(height: 16),
            Text('Sin resultados',
                style: theme.textTheme.titleLarge
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            const SizedBox(height: 6),
            Text(
              'Prueba con otros filtros o términos',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 220,
        childAspectRatio: 0.68,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
      ),
      itemCount: _cachedFilteredProducts.length,
      itemBuilder: (context, index) {
        final product = _cachedFilteredProducts[index];
        return ProductTile(
          key: ValueKey(product.id),
          product: product,
          onTap: () => _addToCart(product),
        );
      },
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
  bool _isLoadingCustomers = true;

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
    _loadCustomers();
  }

  @override
  void dispose() {
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

        // Show receipt view if transaction completed
        if (_showReceiptView && _completedTransaction != null) {
          return _buildReceiptView(theme, _completedTransaction!);
        }

        // Show payment view if activated
        if (_showPaymentView) {
          return _buildPaymentView(theme, posService);
        }

        // Show cart/checkout view
        return _buildCartView(theme, posService);
      },
    );
  }

  Widget _buildInvoicePaymentForm(ThemeData theme, POSService posService) {
    final invoice = posService.linkedInvoice!;
    final currencyFormat =
        NumberFormat.currency(symbol: '\$', decimalDigits: 0);

    return Column(
      children: [
        // ── Header (fixed top) ──────────────────────────────────────────
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerLowest,
            border: Border(
              bottom: BorderSide(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
              ),
            ),
          ),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_rounded, size: 22),
                onPressed: () {
                  posService.exitInvoicePaymentMode();
                  setState(() => _showPendingInvoices = true);
                },
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Abonar a Factura',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.2,
                      ),
                    ),
                    Text(
                      invoice.invoiceNumber,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // ── Form Content (scrollable middle) ────────────────────────────
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Financial Info Box
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    children: [
                      _buildSummaryRow(theme, 'Cliente',
                          invoice.customerName ?? 'Sin nombre',
                          valueColor: theme.colorScheme.onSurface),
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Divider(height: 1),
                      ),
                      _buildSummaryRow(theme, 'Total Factura',
                          currencyFormat.format(invoice.total),
                          valueColor: theme.colorScheme.onSurface),
                      if (invoice.paidAmount > 0) ...[
                        const SizedBox(height: 6),
                        _buildSummaryRow(theme, 'Pagado',
                            currencyFormat.format(invoice.paidAmount),
                            valueColor: theme.colorScheme.tertiary),
                      ],
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.errorContainer,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Deuda',
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: theme.colorScheme.onErrorContainer,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              currencyFormat.format(invoice.balance),
                              style: theme.textTheme.titleMedium?.copyWith(
                                color: theme.colorScheme.onErrorContainer,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // Amount
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Monto a Pagar',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () {
                        setState(() {
                          _paymentAmountController.text =
                              invoice.balance.toStringAsFixed(0);
                        });
                      },
                      icon: const Icon(Icons.check_circle_outline_rounded,
                          size: 16),
                      label: const Text('Completar Total'),
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _paymentAmountController,
                  keyboardType: TextInputType.number,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                  decoration: InputDecoration(
                    prefixText: '\$ ',
                    prefixStyle: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    filled: true,
                    fillColor: theme.colorScheme.surface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 24),

                // Payment Method Selector
                Text(
                  'Método de Pago',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                Consumer<PaymentMethodService>(
                  builder: (context, paymentMethodService, _) {
                    final methods = paymentMethodService.paymentMethods;
                    return Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: methods.map((method) {
                        final isSelected =
                            _selectedPaymentMethodId == method.id;
                        return FilterChip(
                          showCheckmark: false,
                          selected: isSelected,
                          label: Text(
                            method.name,
                            style: TextStyle(
                              fontWeight: isSelected
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                            ),
                          ),
                          onSelected: (selected) {
                            if (selected)
                              setState(
                                  () => _selectedPaymentMethodId = method.id);
                          },
                        );
                      }).toList(),
                    );
                  },
                ),
                const SizedBox(height: 24),

                // Reference
                TextField(
                  controller: _paymentReferenceController,
                  decoration: InputDecoration(
                    labelText: 'Referencia (Opcional)',
                    hintText: 'Nº transferencia, cheque, etc.',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        // ── Action Buttons (fixed bottom) ──────────────────────────────
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            border: Border(
              top: BorderSide(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
              ),
            ),
          ),
          child: SizedBox(
            width: double.infinity,
            height: 54,
            child: FilledButton.icon(
              onPressed: _selectedPaymentMethodId != null && !_isProcessing
                  ? () => _processInvoicePayment(posService, invoice)
                  : null,
              icon: _isProcessing
                  ? Container(
                      width: 20,
                      height: 20,
                      padding: const EdgeInsets.all(2),
                      child: const CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.payment_rounded, size: 20),
              label: Text(
                _isProcessing ? 'Procesando...' : 'Registrar Pago',
                style: const TextStyle(
                    fontWeight: FontWeight.w700, letterSpacing: 0.5),
              ),
            ),
          ),
        ),
      ],
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

  Widget _buildCartView(ThemeData theme, POSService posService) {
    // Show pending invoices list if customer has pending invoices
    if (_showPendingInvoices) {
      return _buildPendingInvoicesView(theme, posService);
    }

    // Show invoice payment form if in payment mode
    if (posService.isInvoicePaymentMode && posService.linkedInvoice != null) {
      return _buildInvoicePaymentForm(theme, posService);
    }

    final hasItems = posService.cartItems.isNotEmpty;
    final currencyFormat =
        NumberFormat.currency(symbol: '\$', decimalDigits: 0);

    return Column(
      children: [
        // ── Customer section (fixed top) ─────────────────────────────────
        Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerLowest,
            border: Border(
              bottom: BorderSide(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
              ),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.person_outline_rounded,
                      size: 15, color: theme.colorScheme.onSurfaceVariant),
                  const SizedBox(width: 6),
                  Text(
                    'Cliente',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (_isLoadingCustomers)
                const SizedBox(height: 36, child: LinearProgressIndicator())
              else
                _CustomerSearchField(
                  key: ValueKey(_selectedCustomer?.id ?? 'none'),
                  value: _selectedCustomer,
                  customers: _customers,
                  onChanged: (customer) async {
                    setState(() => _selectedCustomer = customer);
                    context.read<POSService>().setCustomer(customer);
                    if (customer != null) {
                      await _checkPendingInvoices(customer);
                    }
                  },
                ),
            ],
          ),
        ),

        // ── Cart items (scrollable middle) ───────────────────────────────
        Expanded(
          child: hasItems
              ? ListView.builder(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  itemCount: posService.cartItems.length +
                      (_showAdHocForm ? 1 : 0) +
                      1, // +1 for "add item" row
                  itemBuilder: (context, index) {
                    // Ad-hoc form at top when visible
                    if (_showAdHocForm && index == 0) {
                      return _buildAdHocFormInline(theme);
                    }
                    final itemIndex = _showAdHocForm ? index - 1 : index;
                    // "Add custom item" button
                    if (itemIndex == posService.cartItems.length) {
                      return Padding(
                        padding: const EdgeInsets.only(top: 6, bottom: 2),
                        child: GestureDetector(
                          onTap: _toggleAdHocForm,
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 9),
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: theme.colorScheme.outlineVariant
                                    .withValues(alpha: 0.5),
                                width: 1,
                              ),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.add_circle_outline_rounded,
                                    size: 16, color: theme.colorScheme.primary),
                                const SizedBox(width: 6),
                                Text(
                                  'Agregar item personalizado',
                                  style: theme.textTheme.labelMedium?.copyWith(
                                    color: theme.colorScheme.primary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }
                    final item = posService.cartItems[itemIndex];
                    return _buildCartItemRow(theme, posService, item);
                  },
                )
              : _buildEmptyCart(theme),
        ),

        // ── Totals + payment + CTA (fixed bottom) ──────────────────────
        Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            border: Border(
              top: BorderSide(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
              ),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Totals area
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Column(
                  children: [
                    _totalRow(
                      theme,
                      label: 'Subtotal',
                      value: currencyFormat.format(posService.cartNetAmount),
                    ),
                    if (posService.cartDiscountAmount > 0) ...[
                      const SizedBox(height: 4),
                      _totalRow(
                        theme,
                        label: 'Descuento',
                        value:
                            '-${currencyFormat.format(posService.cartDiscountAmount)}',
                        valueColor: theme.colorScheme.error,
                      ),
                    ],
                    if (posService.taxTreatment ==
                        TaxTreatment.taxIncluded) ...[
                      const SizedBox(height: 4),
                      _totalRow(
                        theme,
                        label: 'IVA (19%)',
                        value: currencyFormat.format(posService.cartTaxAmount),
                      ),
                    ],
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Divider(
                        height: 1,
                        color: theme.colorScheme.outlineVariant
                            .withValues(alpha: 0.4),
                      ),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'TOTAL',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.5,
                          ),
                        ),
                        Text(
                          currencyFormat.format(posService.cartTotal),
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.5,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Checkout button
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: FilledButton.icon(
                    onPressed: hasItems ? _proceedToPayment : null,
                    icon: const Icon(Icons.arrow_forward_rounded, size: 20),
                    label: Text(
                      hasItems ? 'Proceder al Pago' : 'Carrito vacío',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCartItemRow(
      ThemeData theme, POSService posService, POSCartItem item) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          _CartItemThumbnail(item: item),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.displayName,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    height: 1.2,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (item.product?.sku.isNotEmpty == true)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      'SKU: ${item.product!.sku}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    '\$${item.unitPrice.toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.')} c/u',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          // Quantity controls
          Container(
            decoration: BoxDecoration(
              border: Border.all(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                GestureDetector(
                  onTap: () => posService.updateCartItemQuantity(
                      item.id, item.quantity - 1),
                  child: Container(
                    width: 30,
                    height: 30,
                    alignment: Alignment.center,
                    child: Icon(Icons.remove_rounded,
                        size: 15, color: theme.colorScheme.onSurfaceVariant),
                  ),
                ),
                Container(
                  width: 32,
                  height: 30,
                  alignment: Alignment.center,
                  child: Text(
                    '${item.quantity}',
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: () => posService.updateCartItemQuantity(
                      item.id, item.quantity + 1),
                  child: Container(
                    width: 30,
                    height: 30,
                    alignment: Alignment.center,
                    child: Icon(Icons.add_rounded,
                        size: 15, color: theme.colorScheme.primary),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Line total
          Text(
            '\$${item.total.toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.')}',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: theme.colorScheme.onSurface,
            ),
          ),
          const SizedBox(width: 6),
          // Remove
          GestureDetector(
            onTap: () => posService.removeFromCart(item.id),
            child: Icon(
              Icons.close_rounded,
              size: 16,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAdHocFormInline(ThemeData theme) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.25),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Item Personalizado',
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.primary,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: _toggleAdHocForm,
                child: Icon(Icons.close_rounded,
                    size: 18, color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _adHocDescriptionController,
            autofocus: true,
            decoration: InputDecoration(
              hintText: 'Descripción del item',
              isDense: true,
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                flex: 2,
                child: TextField(
                  controller: _adHocPriceController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    hintText: 'Precio',
                    prefixText: '\$',
                    isDense: true,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8)),
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _adHocQuantityController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    hintText: 'Cant.',
                    isDense: true,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8)),
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _addAdHocItem,
                style: FilledButton.styleFrom(
                  minimumSize: const Size(44, 40),
                  padding: EdgeInsets.zero,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                child: const Icon(Icons.check_rounded, size: 20),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyCart(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(
                Icons.shopping_cart_outlined,
                size: 36,
                color:
                    theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Carrito vacío',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Toca un producto para agregar',
              style: theme.textTheme.bodySmall?.copyWith(
                color:
                    theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: _toggleAdHocForm,
              icon: const Icon(Icons.add_circle_outline_rounded, size: 16),
              label: const Text('Agregar item personalizado'),
              style: OutlinedButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _totalRow(ThemeData theme,
      {required String label, required String value, Color? valueColor}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        Text(
          value,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: valueColor ?? theme.colorScheme.onSurface,
          ),
        ),
      ],
    );
  }

  Widget _buildPaymentView(ThemeData theme, POSService posService) {
    final currencyFormat =
        NumberFormat.currency(symbol: '\$', decimalDigits: 0);

    return Column(
      children: [
        // ── Header (fixed top) ──────────────────────────────────────────
        Container(
          padding: const EdgeInsets.fromLTRB(8, 14, 16, 12),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerLowest,
            border: Border(
              bottom: BorderSide(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
              ),
            ),
          ),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_rounded, size: 22),
                onPressed: _cancelPayment,
                padding: const EdgeInsets.all(8),
                constraints: const BoxConstraints(),
              ),
              const SizedBox(width: 8),
              Text(
                'Completar Pago',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                ),
              ),
            ],
          ),
        ),

        // ── Scrollable Middle area ──────────────────────────────────────
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Highlighted Total Box
                Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer
                        .withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    children: [
                      Text(
                        'Total a Pagar',
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: theme.colorScheme.onPrimaryContainer
                              .withValues(alpha: 0.8),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        currencyFormat.format(posService.cartTotal),
                        style: theme.textTheme.displaySmall?.copyWith(
                          fontWeight: FontWeight.w900,
                          letterSpacing: -1,
                          color: theme.colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // Payment Method Selector
                Text(
                  'Método de Pago',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                Consumer<PaymentMethodService>(
                  builder: (context, paymentMethodService, _) {
                    final methods = paymentMethodService.paymentMethods
                        .where((m) => m.isActive)
                        .toList();
                    return Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: methods.map((method) {
                        final isSelected =
                            _selectedPaymentMethod?.id == method.id;
                        return GestureDetector(
                          onTap: () {
                            setState(() {
                              _selectedPaymentMethod = method;
                              // Auto-set amount for non-cash
                              if (method.code != 'cash') {
                                _amountReceived = posService.cartTotal;
                                _amountController.text =
                                    posService.cartTotal.toStringAsFixed(0);
                              } else {
                                _amountReceived = 0;
                                _amountController.clear();
                              }
                            });
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 12),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? theme.colorScheme.primary
                                  : theme.colorScheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isSelected
                                    ? theme.colorScheme.primary
                                    : theme.colorScheme.outlineVariant
                                        .withValues(alpha: 0.4),
                                width: 1,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  _getPaymentMethodIcon(method.code),
                                  size: 18,
                                  color: isSelected
                                      ? theme.colorScheme.onPrimary
                                      : theme.colorScheme.onSurfaceVariant,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  method.name,
                                  style: theme.textTheme.labelLarge?.copyWith(
                                    fontWeight: isSelected
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                    color: isSelected
                                        ? theme.colorScheme.onPrimary
                                        : theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                                if (isSelected) ...[
                                  const SizedBox(width: 6),
                                  Icon(Icons.check_circle_rounded,
                                      size: 16,
                                      color: theme.colorScheme.onPrimary),
                                ]
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    );
                  },
                ),

                const SizedBox(height: 32),

                // Cash Amount input
                if (_selectedPaymentMethod?.code == 'cash') ...[
                  Text(
                    'Monto Entregado',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
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
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                    decoration: InputDecoration(
                      prefixText: '\$ ',
                      prefixStyle: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      filled: true,
                      fillColor: theme.colorScheme.surface,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      hintText: posService.cartTotal.toStringAsFixed(0),
                      hintStyle: theme.textTheme.headlineSmall?.copyWith(
                        color: theme.colorScheme.outlineVariant,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Change calculation
                  if (_amountReceived >= posService.cartTotal)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.secondaryContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Vuelto a entregar',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: theme.colorScheme.onSecondaryContainer,
                            ),
                          ),
                          Text(
                            currencyFormat
                                .format(_amountReceived - posService.cartTotal),
                            style: theme.textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w900,
                              color: theme.colorScheme.onSecondaryContainer,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),

        // ── Action Buttons (fixed bottom) ──────────────────────────────
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            border: Border(
              top: BorderSide(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
              ),
            ),
          ),
          child: SizedBox(
            width: double.infinity,
            height: 54,
            child: FilledButton.icon(
              onPressed: (_selectedPaymentMethod != null &&
                      _amountReceived >= posService.cartTotal &&
                      !_isProcessing)
                  ? _processPayment
                  : null,
              icon: _isProcessing
                  ? Container(
                      width: 24,
                      height: 24,
                      padding: const EdgeInsets.all(2),
                      child: const CircularProgressIndicator(
                        strokeWidth: 3,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.check_circle_rounded),
              label: Text(
                _isProcessing ? 'Procesando...' : 'Confirmar Venta',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ),
        ),
      ],
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
    return Column(
      children: [
        // ── Header (fixed top) ──────────────────────────────────────────
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.check_circle_rounded,
                size: 28,
                color: theme.colorScheme.onPrimaryContainer,
              ),
              const SizedBox(width: 10),
              Text(
                '¡Venta Exitosa!',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              ),
            ],
          ),
        ),

        // ── Receipt Details (scrollable middle) ─────────────────────────
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: theme.colorScheme.outlineVariant
                          .withValues(alpha: 0.5),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(
                        'VINABIKE',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w900,
                          letterSpacing: 2,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Venta de Bicicletas y Accesorios',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          letterSpacing: 0.5,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 20),
                        child: Divider(height: 1),
                      ),
                      _buildReceiptRow('Recibo Nº:',
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
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 20),
                        child: Divider(height: 1),
                      ),
                      // Items
                      ...transaction.items.map((item) => Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${item.quantity}x',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: theme.colorScheme.primary,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        item.displayName,
                                        style: theme.textTheme.bodyMedium
                                            ?.copyWith(
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      Text(
                                        '\$${item.unitPrice.toStringAsFixed(0)} c/u',
                                        style: theme.textTheme.labelSmall
                                            ?.copyWith(
                                          color: theme
                                              .colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Text(
                                  '\$${item.subtotal.toStringAsFixed(0)}',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          )),
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Divider(height: 1),
                      ),
                      _buildReceiptRow(
                          'Subtotal:',
                          '\$${transaction.subtotal.toStringAsFixed(0)}',
                          theme),
                      _buildReceiptRow(
                          'IVA (19%):',
                          '\$${transaction.taxAmount.toStringAsFixed(0)}',
                          theme),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'TOTAL',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1,
                              ),
                            ),
                            Text(
                              '\$${transaction.total.toStringAsFixed(0)}',
                              style: theme.textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w900,
                                color: theme.colorScheme.primary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      // Payment Info
                      ...transaction.payments.map((payment) => _buildReceiptRow(
                            'Pago (${payment.method.name})',
                            '\$${payment.amount.toStringAsFixed(0)}',
                            theme,
                          )),
                      const SizedBox(height: 32),
                      Text(
                        '¡Gracias por su compra!',
                        style: theme.textTheme.labelMedium?.copyWith(
                          fontStyle: FontStyle.italic,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Garantía 30 días con boleta',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant
                              .withValues(alpha: 0.6),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),

        // ── Action Buttons (fixed bottom) ──────────────────────────────
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            border: Border(
              top: BorderSide(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
              ),
            ),
          ),
          child: SizedBox(
            width: double.infinity,
            height: 54,
            child: FilledButton.icon(
              onPressed: _finishTransaction,
              icon: const Icon(Icons.add_shopping_cart_rounded, size: 20),
              label: const Text(
                'Nueva Venta',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildReceiptRow(String label, String value, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w700,
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

// ── Premium POS Header Bar ─────────────────────────────────────────────────────

class _POSHeaderBar extends StatelessWidget {
  final double screenWidth;
  const _POSHeaderBar({required this.screenWidth});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.point_of_sale_rounded,
              size: 20, color: theme.colorScheme.primary),
          const SizedBox(width: 10),
          Text(
            'Punto de Venta',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: -0.3,
            ),
          ),
          const Spacer(),
          Consumer<POSService>(
            builder: (context, posService, _) {
              final itemCount = posService.cartTotalItems;
              final total = posService.cartTotal;
              final customerName = posService.selectedCustomer?.name;
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (customerName != null) ...[
                    Icon(Icons.person_outline_rounded,
                        size: 16, color: theme.colorScheme.onSurfaceVariant),
                    const SizedBox(width: 4),
                    Text(
                      customerName,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(width: 16),
                  ],
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: itemCount > 0
                          ? theme.colorScheme.primaryContainer
                          : theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.shopping_cart_rounded,
                          size: 15,
                          color: itemCount > 0
                              ? theme.colorScheme.onPrimaryContainer
                              : theme.colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          itemCount > 0
                              ? '\$${total.toStringAsFixed(0)}'
                              : 'Carrito vacío',
                          style: theme.textTheme.labelMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: itemCount > 0
                                ? theme.colorScheme.onPrimaryContainer
                                : theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        if (itemCount > 0) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primary,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '$itemCount',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                color: theme.colorScheme.onPrimary,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _CustomerSearchField extends StatefulWidget {
  final Customer? value;
  final List<Customer> customers;
  final Future<void> Function(Customer?) onChanged;

  const _CustomerSearchField({
    super.key,
    required this.value,
    required this.customers,
    required this.onChanged,
  });

  @override
  State<_CustomerSearchField> createState() => _CustomerSearchFieldState();
}

class _CustomerSearchFieldState extends State<_CustomerSearchField> {
  late TextEditingController _textController;
  final FocusNode _focusNode = FocusNode();

  String _labelFor(Customer c) {
    final parts = <String>[
      if ((c.rut ?? '').trim().isNotEmpty) c.rut!.trim(),
      if ((c.email ?? '').trim().isNotEmpty) c.email!.trim(),
    ];
    return parts.isEmpty ? c.name : '${c.name} • ${parts.join(' • ')}';
  }

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController(
      text: widget.value == null ? '' : _labelFor(widget.value!),
    );
  }

  @override
  void dispose() {
    _textController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasValue = widget.value != null;

    return RawAutocomplete<Customer>(
      textEditingController: _textController,
      focusNode: _focusNode,
      displayStringForOption: _labelFor,
      optionsBuilder: (textEditingValue) {
        final query = textEditingValue.text.trim().toLowerCase();
        final active = widget.customers.where((c) => c.isActive);
        if (query.isEmpty) return active.take(50);
        return active
            .where((c) =>
                c.name.toLowerCase().contains(query) ||
                (c.rut ?? '').toLowerCase().contains(query) ||
                (c.email ?? '').toLowerCase().contains(query))
            .take(50);
      },
      fieldViewBuilder:
          (context, textEditingController, focusNode, onFieldSubmitted) {
        return Stack(
          alignment: Alignment.centerRight,
          children: [
            TextField(
              controller: textEditingController,
              focusNode: focusNode,
              style: theme.textTheme.bodySmall?.copyWith(
                color: hasValue
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurface,
                fontWeight: hasValue ? FontWeight.w600 : FontWeight.normal,
              ),
              decoration: InputDecoration(
                hintText: 'Cliente Genérico',
                hintStyle: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                prefixIcon: Padding(
                  padding: const EdgeInsets.only(left: 10, right: 6),
                  child: Icon(
                    Icons.person_outline_rounded,
                    size: 16,
                    color: hasValue
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                prefixIconConstraints:
                    const BoxConstraints(minWidth: 0, minHeight: 0),
                suffixIcon: hasValue
                    ? IconButton(
                        icon: Icon(Icons.close_rounded,
                            size: 16,
                            color: theme.colorScheme.onSurfaceVariant),
                        padding: EdgeInsets.zero,
                        constraints:
                            const BoxConstraints(minWidth: 28, minHeight: 28),
                        onPressed: () {
                          textEditingController.clear();
                          _focusNode.unfocus();
                          widget.onChanged(null);
                        },
                      )
                    : Icon(Icons.arrow_drop_down,
                        size: 18, color: theme.colorScheme.onSurfaceVariant),
                isDense: true,
                filled: true,
                fillColor: hasValue
                    ? theme.colorScheme.primaryContainer.withValues(alpha: 0.3)
                    : Colors.transparent,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(21),
                  borderSide: BorderSide(
                      color: hasValue
                          ? Colors.transparent
                          : theme.colorScheme.outlineVariant),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(21),
                  borderSide: BorderSide(
                      color: hasValue
                          ? Colors.transparent
                          : theme.colorScheme.outlineVariant),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(21),
                  borderSide:
                      BorderSide(color: theme.colorScheme.primary, width: 1.5),
                ),
              ),
            ),
          ],
        );
      },
      optionsViewBuilder: (context, onSelected, options) {
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(8),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 300),
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 4),
                shrinkWrap: true,
                itemCount: options.length + 1,
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return ListTile(
                      dense: true,
                      leading: Icon(Icons.person_off_outlined,
                          size: 18, color: theme.colorScheme.primary),
                      title: Text(
                        'Cliente Genérico',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      onTap: () {
                        _textController.clear();
                        _focusNode.unfocus();
                        widget.onChanged(null);
                      },
                    );
                  }
                  final customer = options.elementAt(index - 1);
                  return ListTile(
                    dense: true,
                    title: Text(
                      customer.name,
                      style: theme.textTheme.bodySmall,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: (customer.rut ?? '').isNotEmpty ||
                            (customer.email ?? '').isNotEmpty
                        ? Text(
                            [
                              if ((customer.rut ?? '').isNotEmpty)
                                customer.rut!,
                              if ((customer.email ?? '').isNotEmpty)
                                customer.email!,
                            ].join(' • '),
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                            overflow: TextOverflow.ellipsis,
                          )
                        : null,
                    onTap: () => onSelected(customer),
                  );
                },
              ),
            ),
          ),
        );
      },
      onSelected: (customer) {
        _textController.text = _labelFor(customer);
        widget.onChanged(customer);
      },
    );
  }
}

class _SearchableSelectorField<T> extends StatelessWidget {
  final double width;
  final double height;
  final String hint;
  final String allLabel;
  final T? value;
  final List<T> items;
  final String Function(T) labelBuilder;
  final ValueChanged<T?> onChanged;

  const _SearchableSelectorField({
    required this.width,
    required this.hint,
    required this.allLabel,
    required this.value,
    required this.items,
    required this.labelBuilder,
    required this.onChanged,
    this.height = 36,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasValue = value != null;
    final previewItems = items.take(4).map(labelBuilder).toList();
    final previewText = previewItems.isEmpty
        ? 'Sin opciones disponibles'
        : '${items.length} opciones • ${previewItems.join(', ')}';

    return Container(
      width: width,
      height: height,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: hasValue
            ? theme.colorScheme.primaryContainer.withValues(alpha: 0.3)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(height / 2),
        border: Border.all(
          color:
              hasValue ? Colors.transparent : theme.colorScheme.outlineVariant,
        ),
      ),
      child: Tooltip(
        message: previewText,
        waitDuration: const Duration(milliseconds: 400),
        child: DropdownMenu<T?>(
          key: ValueKey('${hint}_${value.hashCode}_${items.length}'),
          width: width,
          initialSelection: value,
          hintText: hint,
          menuHeight: 300,
          enableFilter: true,
          requestFocusOnTap: true,
          textStyle: theme.textTheme.bodySmall?.copyWith(
            color: hasValue
                ? theme.colorScheme.primary
                : theme.colorScheme.onSurface,
            fontWeight: hasValue ? FontWeight.w600 : FontWeight.normal,
          ),
          inputDecorationTheme: InputDecorationTheme(
            isDense: true,
            contentPadding: const EdgeInsets.only(left: 12, right: 8),
            border: InputBorder.none,
            filled: true,
            fillColor: Colors.transparent,
            constraints: BoxConstraints(maxHeight: height),
            hintStyle: theme.textTheme.bodySmall?.copyWith(
              color: hasValue
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w500,
            ),
          ),
          trailingIcon: Icon(
            Icons.arrow_drop_down,
            size: 18,
            color: hasValue
                ? theme.colorScheme.primary
                : theme.colorScheme.onSurfaceVariant,
          ),
          selectedTrailingIcon: Icon(
            Icons.arrow_drop_up,
            size: 18,
            color: hasValue
                ? theme.colorScheme.primary
                : theme.colorScheme.onSurfaceVariant,
          ),
          dropdownMenuEntries: [
            DropdownMenuEntry<T?>(
              value: null,
              label: allLabel,
              style: ButtonStyle(
                textStyle: WidgetStateProperty.all(
                  theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
            ),
            ...items.map(
              (item) => DropdownMenuEntry<T?>(
                value: item,
                label: labelBuilder(item),
                style: ButtonStyle(
                  textStyle: WidgetStateProperty.all(theme.textTheme.bodySmall),
                ),
              ),
            ),
          ],
          onSelected: onChanged,
        ),
      ),
    );
  }
}

class _CartItemThumbnail extends StatelessWidget {
  final POSCartItem item;

  const _CartItemThumbnail({required this.item});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final product = item.product;
    final imageUrl = product?.imageUrlOptimized?.trim().isNotEmpty == true
        ? product!.imageUrlOptimized!.trim()
        : product?.imageUrl?.trim();
    final isService = product?.productType == ProductType.service;

    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: 46,
        height: 46,
        color: theme.colorScheme.surfaceContainerHighest,
        child: imageUrl != null && imageUrl.isNotEmpty
            ? CachedNetworkImage(
                imageUrl: imageUrl,
                fit: BoxFit.cover,
                placeholder: (_, __) => Center(
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
                errorWidget: (_, __, ___) => Icon(
                  isService
                      ? Icons.design_services
                      : Icons.inventory_2_outlined,
                  size: 20,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              )
            : Icon(
                item.isAdHoc
                    ? Icons.edit_note_rounded
                    : isService
                        ? Icons.design_services_outlined
                        : Icons.inventory_2_outlined,
                size: 20,
                color: theme.colorScheme.onSurfaceVariant,
              ),
      ),
    );
  }
}

// ─── Product card that cascades in (fall-down stagger animation) ─────────────
