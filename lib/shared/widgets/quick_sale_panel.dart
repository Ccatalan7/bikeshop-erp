import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';

import '../models/product.dart';
import '../models/payment_method.dart' as pm;
import '../services/inventory_service.dart';
import '../services/number_generation_service.dart';
import '../services/payment_method_service.dart';
import '../services/tenant_service.dart';
import '../services/barcode_scanner_service.dart';
import '../../modules/sales/models/sales_models.dart';
import '../../modules/sales/services/sales_service.dart';
import '../services/workspace_manager.dart';

// ─── Cart item model ─────────────────────────────────────────────────
class _CartItem {
  final Product product;
  int quantity;
  double unitPrice;

  _CartItem({required this.product, this.quantity = 1, double? unitPrice})
      : unitPrice = unitPrice ?? product.price;

  double get lineTotal => quantity * unitPrice;
  double get totalCost => quantity * product.cost;
  String get displayName => product.name;
}

// ─── Quick Sale Panel ────────────────────────────────────────────────
enum _QuickSaleStep { cart, payment, confirmation }

class QuickSalePanel extends StatefulWidget {
  const QuickSalePanel({super.key});

  @override
  State<QuickSalePanel> createState() => _QuickSalePanelState();
}

class _QuickSalePanelState extends State<QuickSalePanel> {
  // State
  _QuickSaleStep _step = _QuickSaleStep.cart;
  final List<_CartItem> _cart = [];
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();
  final _amountController = TextEditingController();
  List<Product> _searchResults = [];
  bool _isSearching = false;
  Timer? _debounce;

  // View mode: list vs cards
  bool _cardView = false;
  Product? _viewingProduct;

  // Barcode scanner
  bool _scannerEnabled = false;
  StreamSubscription<String>? _barcodeSub;

  void _showProductMenu(BuildContext context, Product p, Offset position) {
    showMenu(
      context: context,
      position: RelativeRect.fromLTRB(position.dx, position.dy, position.dx + 1, position.dy + 1),
      items: [
        PopupMenuItem(
          value: 'details',
          child: Row(
            children: [
              const Icon(Icons.info_outline, size: 20),
              const SizedBox(width: 8),
              Text('Ver detalles', style: Theme.of(context).textTheme.bodyMedium),
            ],
          ),
        ),
      ],
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ).then((value) {
      if (value == 'details') {
        setState(() => _viewingProduct = p);
      }
    });
  }

  // Payment state
  pm.PaymentMethod? _selectedPaymentMethod;
  bool _isProcessing = false;

  // Confirmation state
  String? _invoiceNumber;
  double _totalPaid = 0;
  double _change = 0;
  String? _savedInvoiceId;

  // ─── Computed ────────────────────────────────────────────────────
  double get _subtotal => _cart.fold(0.0, (s, i) => s + i.lineTotal);
  double get _total => _subtotal;
  int get _itemCount => _cart.fold(0, (s, i) => s + i.quantity);

  // ─── Lifecycle ───────────────────────────────────────────────────
  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    _amountController.dispose();
    _debounce?.cancel();
    _barcodeSub?.cancel();
    super.dispose();
  }

  // ─── Barcode scanner ─────────────────────────────────────────────
  void _toggleScanner() {
    setState(() => _scannerEnabled = !_scannerEnabled);
    if (_scannerEnabled) {
      final barcodeService = context.read<BarcodeScannerService>();
      _barcodeSub?.cancel();
      _barcodeSub = barcodeService.barcodeStream.listen(_onBarcodeScanned);
    } else {
      _barcodeSub?.cancel();
      _barcodeSub = null;
    }
  }

  Future<void> _onBarcodeScanned(String barcode) async {
    if (_step != _QuickSaleStep.cart) return;
    try {
      final inventory = context.read<InventoryService>();
      final results = await inventory.searchProducts(barcode.trim(), limit: 5);
      if (results.isNotEmpty && mounted) {
        _addToCart(results.first);
      }
    } catch (_) {}
  }

  // ─── Search ──────────────────────────────────────────────────────
  void _onSearchChanged(String query) {
    _debounce?.cancel();
    if (query.trim().isEmpty) {
      setState(() {
        _searchResults = [];
        _isSearching = false;
      });
      return;
    }
    setState(() => _isSearching = true);
    _debounce = Timer(const Duration(milliseconds: 250), () async {
      try {
        final inventory = context.read<InventoryService>();
        final results = await inventory.searchProducts(query.trim(), limit: 20);
        if (mounted) {
          setState(() {
            _searchResults = results;
            _isSearching = false;
          });
        }
      } catch (_) {
        if (mounted) setState(() => _isSearching = false);
      }
    });
  }

  void _addToCart(Product product) {
    setState(() {
      final idx = _cart.indexWhere((i) => i.product.id == product.id);
      if (idx >= 0) {
        _cart[idx].quantity++;
      } else {
        _cart.add(_CartItem(product: product));
      }
      _searchController.clear();
      _searchResults = [];
    });
    _searchFocusNode.requestFocus();
  }

  void _removeFromCart(int index) {
    setState(() => _cart.removeAt(index));
  }

  void _updateQty(int index, int delta) {
    setState(() {
      _cart[index].quantity += delta;
      if (_cart[index].quantity <= 0) _cart.removeAt(index);
    });
  }

  // ─── Payment ─────────────────────────────────────────────────────
  void _goToPayment() {
    if (_cart.isEmpty) return;
    _amountController.text = _total.toStringAsFixed(0);
    setState(() => _step = _QuickSaleStep.payment);
  }

  Future<void> _confirmPayment() async {
    if (_isProcessing) return;
    final amount = double.tryParse(_amountController.text) ?? 0;
    if (amount <= 0 || amount < _total) return;
    if (_selectedPaymentMethod == null) return;

    setState(() => _isProcessing = true);

    try {
      final salesService = context.read<SalesService>();
      final tenantService = context.read<TenantService>();
      final tenantId = await tenantService.getTenantId();
      if (tenantId == null) throw Exception('No tenant');

      final numberService = NumberGenerationService();
      final invoiceNumber = await numberService.nextSalesInvoiceNumber();

      final invoiceItems = _cart.map((item) => InvoiceItem(
            productId: item.product.id,
            productName: item.displayName,
            productSku: item.product.sku,
            quantity: item.quantity.toDouble(),
            unitPrice: item.unitPrice,
            discount: 0,
            lineTotal: item.lineTotal,
            cost: item.totalCost,
          )).toList();

      final taxTreatment = _selectedPaymentMethod!.defaultTaxTreatment;
      double netAmount = _total;
      double ivaAmount = 0;
      if (taxTreatment.name == 'taxIncluded') {
        netAmount = _total / 1.19;
        ivaAmount = _total - netAmount;
      }

      final invoice = Invoice(
        tenantId: tenantId,
        invoiceNumber: invoiceNumber,
        customerName: 'Cliente Mostrador',
        date: DateTime.now(),
        dueDate: DateTime.now(),
        status: InvoiceStatus.confirmed,
        subtotal: _total,
        netAmount: netAmount,
        ivaAmount: ivaAmount,
        total: _total,
        taxTreatment: taxTreatment,
        items: invoiceItems,
        invoiceType: 'sale',
      );

      final saved = await salesService.saveInvoice(invoice);
      if (saved.id == null) throw Exception('Invoice save failed');

      final payment = Payment(
        tenantId: tenantId,
        invoiceId: saved.id!,
        invoiceReference: saved.invoiceNumber,
        paymentMethodId: _selectedPaymentMethod!.id,
        amount: _total,
        date: DateTime.now(),
      );
      await salesService.registerPayment(payment);

      try {
        await context.read<InventoryService>().getProducts(forceRefresh: true);
      } catch (_) {}

      if (mounted) {
        setState(() {
          _invoiceNumber = saved.invoiceNumber;
          _totalPaid = amount;
          _change = amount - _total;
          _savedInvoiceId = saved.id;
          _step = _QuickSaleStep.confirmation;
          _isProcessing = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isProcessing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _newSale() {
    setState(() {
      _cart.clear();
      _searchController.clear();
      _searchResults = [];
      _selectedPaymentMethod = null;
      _amountController.clear();
      _invoiceNumber = null;
      _totalPaid = 0;
      _change = 0;
      _savedInvoiceId = null;
      _step = _QuickSaleStep.cart;
    });
    _searchFocusNode.requestFocus();
  }

  // ─── Build ───────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF1A1A1A) : Colors.white;

    return Container(
      color: bg,
      child: _viewingProduct != null
          ? _buildProductDetailsStep(theme, isDark)
          : switch (_step) {
              _QuickSaleStep.cart => _buildCartStep(theme, isDark),
              _QuickSaleStep.payment => _buildPaymentStep(theme, isDark),
              _QuickSaleStep.confirmation => _buildConfirmationStep(theme, isDark),
            },
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // STEP 1 — Cart
  // ═══════════════════════════════════════════════════════════════════
  Widget _buildCartStep(ThemeData theme, bool isDark) {
    return Column(
      children: [
        // Action bar: scanner toggle + view mode toggle
        _buildActionBar(theme, isDark),

        // Search bar
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
          child: TextField(
            controller: _searchController,
            focusNode: _searchFocusNode,
            autofocus: true,
            onChanged: _onSearchChanged,
            onSubmitted: (value) async {
              if (value.trim().isEmpty) return;
              try {
                final inventory = context.read<InventoryService>();
                final results =
                    await inventory.searchProducts(value.trim(), limit: 1);
                if (results.isNotEmpty && mounted) {
                  _addToCart(results.first);
                }
              } catch (_) {}
            },
            decoration: InputDecoration(
              hintText: 'Buscar producto...',
              prefixIcon: const Icon(Icons.search, size: 20),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () {
                        _searchController.clear();
                        _onSearchChanged('');
                      },
                    )
                  : null,
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(
                  color: isDark
                      ? const Color(0xFF3A3A3A)
                      : const Color(0xFFDDE0E4),
                ),
              ),
              filled: true,
              fillColor:
                  isDark ? const Color(0xFF252525) : const Color(0xFFF5F6F8),
            ),
            style: const TextStyle(fontSize: 14),
          ),
        ),

        // Search results (expanded, fills available space when searching)
        if (_searchResults.isNotEmpty || _isSearching)
          Expanded(child: _buildSearchResults(theme, isDark))
        else ...[
          // Cart items
          Expanded(
            child: _cart.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.shopping_cart_outlined,
                            size: 48,
                            color:
                                theme.colorScheme.onSurface.withOpacity(0.15)),
                        const SizedBox(height: 8),
                        Text('Busca y agrega productos',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color:
                                  theme.colorScheme.onSurface.withOpacity(0.4),
                            )),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    itemCount: _cart.length,
                    itemBuilder: (ctx, i) =>
                        _buildCartRow(_cart[i], i, theme, isDark),
                  ),
          ),
        ],

        // Totals + Cobrar button
        _buildCartFooter(theme, isDark),
      ],
    );
  }

  // ─── Action bar (scanner + view toggle) ──────────────────────────
  Widget _buildActionBar(ThemeData theme, bool isDark) {
    final borderColor =
        isDark ? const Color(0xFF2E2E2E) : const Color(0xFFEAECEF);

    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: borderColor, width: 0.5)),
      ),
      child: Row(
        children: [
          // Scanner toggle
          _ActionToggle(
            icon: Icons.qr_code_scanner,
            label: 'Escáner',
            isActive: _scannerEnabled,
            onTap: _toggleScanner,
            theme: theme,
            isDark: isDark,
          ),
          const Spacer(),
          // View mode toggle
          _ActionToggle(
            icon: _cardView ? Icons.view_list_rounded : Icons.grid_view_rounded,
            label: _cardView ? 'Lista' : 'Tarjetas',
            isActive: false,
            onTap: () => setState(() => _cardView = !_cardView),
            theme: theme,
            isDark: isDark,
          ),
        ],
      ),
    );
  }

  // ─── Search results (fills remaining space) ──────────────────────
  Widget _buildSearchResults(ThemeData theme, bool isDark) {
    final cardBg = isDark ? const Color(0xFF252525) : Colors.white;
    final borderColor =
        isDark ? const Color(0xFF3A3A3A) : const Color(0xFFDDE0E4);

    return Container(
      margin: const EdgeInsets.fromLTRB(10, 4, 10, 4),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.3 : 0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: _isSearching
          ? const Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          : ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: _cardView
                  ? _buildCardGrid(theme, isDark, borderColor)
                  : _buildListView(theme, isDark, borderColor),
            ),
    );
  }

  // ── List view ──
  Widget _buildListView(ThemeData theme, bool isDark, Color borderColor) {
    return ListView.separated(
      padding: EdgeInsets.zero,
      itemCount: _searchResults.length,
      separatorBuilder: (_, __) => Divider(
        height: 1,
        color: borderColor.withOpacity(0.5),
      ),
      itemBuilder: (ctx, i) => _buildListTile(_searchResults[i], theme, isDark),
    );
  }

  Widget _buildListTile(Product p, ThemeData theme, bool isDark) {
    final imgUrl = p.imageUrlOptimized ?? p.imageUrl;
    final inCart = _cart.any((item) => item.product.id == p.id);

    return GestureDetector(
      onSecondaryTapDown: (details) => _showProductMenu(context, p, details.globalPosition),
      onLongPressStart: (details) => _showProductMenu(context, p, details.globalPosition),
      child: InkWell(
        onTap: () => _addToCart(p),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          children: [
            // Product image
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                width: 44,
                height: 44,
                child: _productImage(imgUrl, isDark, 20),
              ),
            ),
            const SizedBox(width: 10),
            // Name / SKU
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    p.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    p.sku,
                    style: TextStyle(
                      fontSize: 11,
                      color: theme.colorScheme.onSurface.withOpacity(0.5),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            // Price + stock + badge
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '\$${p.price.toStringAsFixed(0)}',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (inCart) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 4, vertical: 1),
                        decoration: BoxDecoration(
                          color:
                              theme.colorScheme.primary.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text('En carrito',
                            style: TextStyle(
                              fontSize: 9,
                              color: theme.colorScheme.primary,
                              fontWeight: FontWeight.w600,
                            )),
                      ),
                      const SizedBox(width: 4),
                    ],
                    Text(
                      p.trackStock
                          ? '${p.stockQuantity} uds'
                          : 'Servicio',
                      style: TextStyle(
                        fontSize: 10,
                        color: p.trackStock && p.stockQuantity <= 0
                            ? Colors.red
                            : theme.colorScheme.onSurface.withOpacity(0.45),
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
}

  // ── Card / Grid view ──
  Widget _buildCardGrid(ThemeData theme, bool isDark, Color borderColor) {
    return GridView.builder(
      padding: const EdgeInsets.all(8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 0.82,
      ),
      itemCount: _searchResults.length,
      itemBuilder: (ctx, i) => _buildCardTile(_searchResults[i], theme, isDark, borderColor),
    );
  }

  Widget _buildCardTile(
      Product p, ThemeData theme, bool isDark, Color borderColor) {
    final imgUrl = p.imageUrlOptimized ?? p.imageUrl;
    final inCart = _cart.any((item) => item.product.id == p.id);

    return GestureDetector(
      onSecondaryTapDown: (details) => _showProductMenu(context, p, details.globalPosition),
      onLongPressStart: (details) => _showProductMenu(context, p, details.globalPosition),
      child: InkWell(
        onTap: () => _addToCart(p),
        borderRadius: BorderRadius.circular(8),
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF222222) : const Color(0xFFFAFAFA),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: inCart ? theme.colorScheme.primary.withOpacity(0.5) : borderColor,
            width: inCart ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Image
            Expanded(
              flex: 3,
              child: ClipRRect(
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(7)),
                child: _productImage(imgUrl, isDark, 28),
              ),
            ),
            // Info
            Expanded(
              flex: 2,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(6, 5, 6, 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      p.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 11, fontWeight: FontWeight.w500),
                    ),
                    const Spacer(),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '\$${p.price.toStringAsFixed(0)}',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                        Text(
                          p.trackStock
                              ? '${p.stockQuantity}'
                              : 'Srv',
                          style: TextStyle(
                            fontSize: 10,
                            color: p.trackStock && p.stockQuantity <= 0
                                ? Colors.red
                                : theme.colorScheme.onSurface.withOpacity(0.4),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

  // ─── Shared product image builder ────────────────────────────────
  Widget _productImage(String? imgUrl, bool isDark, double iconSize) {
    if (imgUrl != null && imgUrl.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: imgUrl,
        fit: BoxFit.cover,
        placeholder: (_, __) => Container(
          color: isDark ? const Color(0xFF333333) : const Color(0xFFEEEEEE),
          child:
              Icon(Icons.image_outlined, size: iconSize, color: Colors.grey),
        ),
        errorWidget: (_, __, ___) => Container(
          color: isDark ? const Color(0xFF333333) : const Color(0xFFEEEEEE),
          child:
              Icon(Icons.inventory_2, size: iconSize, color: Colors.grey),
        ),
      );
    }
    return Container(
      color: isDark ? const Color(0xFF333333) : const Color(0xFFEEEEEE),
      child: Icon(Icons.inventory_2, size: iconSize, color: Colors.grey),
    );
  }

  // ─── Cart row ────────────────────────────────────────────────────
  Widget _buildCartRow(
      _CartItem item, int index, ThemeData theme, bool isDark) {
    final imgUrl = item.product.imageUrlOptimized ?? item.product.imageUrl;
    final borderColor =
        isDark ? const Color(0xFF2E2E2E) : const Color(0xFFEEEEEE);

    return GestureDetector(
      onSecondaryTapDown: (details) => _showProductMenu(context, item.product, details.globalPosition),
      onLongPressStart: (details) => _showProductMenu(context, item.product, details.globalPosition),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF222222) : const Color(0xFFFAFAFA),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              width: 36,
              height: 36,
              child: _productImage(imgUrl, isDark, 16),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w500),
                ),
                Text(
                  '\$${item.unitPrice.toStringAsFixed(0)} c/u',
                  style: TextStyle(
                    fontSize: 11,
                    color: theme.colorScheme.onSurface.withOpacity(0.5),
                  ),
                ),
              ],
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _miniButton(
                  Icons.remove, () => _updateQty(index, -1), theme),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Text('${item.quantity}',
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600)),
              ),
              _miniButton(Icons.add, () => _updateQty(index, 1), theme),
            ],
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 60,
            child: Text(
              '\$${item.lineTotal.toStringAsFixed(0)}',
              textAlign: TextAlign.right,
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
          InkWell(
            onTap: () => _removeFromCart(index),
            borderRadius: BorderRadius.circular(4),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(Icons.close,
                  size: 14,
                  color: theme.colorScheme.onSurface.withOpacity(0.35)),
            ),
          ),
        ],
      ),
    ),
  );
}

  Widget _miniButton(IconData icon, VoidCallback onTap, ThemeData theme) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
              color: theme.colorScheme.onSurface.withOpacity(0.15)),
        ),
        child: Icon(icon, size: 14),
      ),
    );
  }

  // ─── Product Details Step ──────────────────────────────────────────
  Widget _buildProductDetailsStep(ThemeData theme, bool isDark) {
    final p = _viewingProduct!;
    final imgUrl = p.imageUrl ?? p.imageUrlOptimized; // Use high-res for details if possible
    final cardBg = isDark ? const Color(0xFF252525) : const Color(0xFFF8F9FA);
    final borderColor = isDark ? const Color(0xFF3A3A3A) : const Color(0xFFDDE0E4);

    return Column(
      children: [
        // Header
        Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: borderColor, width: 0.5)),
          ),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back, size: 20),
                onPressed: () => setState(() => _viewingProduct = null),
                tooltip: 'Volver',
              ),
              const SizedBox(width: 4),
              const Text('Detalle del Producto',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
        // Content
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Image
              Container(
                height: 200,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1A1A1A) : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: borderColor),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(11),
                  child: _productImage(imgUrl, isDark, 64),
                ),
              ),
              const SizedBox(height: 16),
              // Name and SKU
              Text(
                p.name,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, height: 1.2),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Text(
                    'SKU: ${p.sku}',
                    style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withOpacity(0.6)),
                  ),
                  if (p.brand != null) ...[
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        p.brand!,
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: theme.colorScheme.primary),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 16),
              // Info Grid
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: borderColor),
                ),
                child: Column(
                  children: [
                    _detailRow('Categoría', p.category.displayName, theme),
                    const Divider(height: 16),
                    _detailRow('Stock', p.trackStock ? '${p.stockQuantity} unidades' : 'Servicio', theme,
                        valueColor: p.trackStock && p.stockQuantity <= 0 ? Colors.red : null),
                    const Divider(height: 16),
                    _detailRow('Costo Unitario', '\$${p.cost.toStringAsFixed(0)}', theme),
                    const Divider(height: 16),
                    _detailRow('Precio de Venta', '\$${p.price.toStringAsFixed(0)}', theme, 
                        isBold: true, valueColor: theme.colorScheme.primary),
                  ],
                ),
              ),
              
              if (p.description != null && p.description!.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text('Descripción', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: theme.colorScheme.onSurface.withOpacity(0.7))),
                const SizedBox(height: 6),
                Text(p.description!, style: TextStyle(fontSize: 13, color: theme.colorScheme.onSurface, height: 1.4)),
              ],
            ],
          ),
        ),
        // Add to cart footer
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: borderColor)),
            color: isDark ? const Color(0xFF1E1E1E) : const Color(0xFFF8F9FA),
          ),
          child: SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton.icon(
              icon: const Icon(Icons.add_shopping_cart, size: 18),
              label: const Text('Agregar a la venta', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              style: FilledButton.styleFrom(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () {
                _addToCart(p);
                setState(() => _viewingProduct = null);
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _detailRow(String label, String value, ThemeData theme, {bool isBold = false, Color? valueColor}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(fontSize: 13, color: theme.colorScheme.onSurface.withOpacity(0.6))),
        Text(value, style: TextStyle(fontSize: 13, fontWeight: isBold ? FontWeight.bold : FontWeight.w500, color: valueColor ?? theme.colorScheme.onSurface)),
      ],
    );
  }

  Widget _buildCartFooter(ThemeData theme, bool isDark) {
    final borderColor =
        isDark ? const Color(0xFF2E2E2E) : const Color(0xFFDDE0E4);

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: borderColor)),
        color: isDark ? const Color(0xFF1E1E1E) : const Color(0xFFF8F9FA),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Total ($_itemCount ${_itemCount == 1 ? "ítem" : "ítems"})',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              Text(
                '\$${_total.toStringAsFixed(0)}',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            height: 42,
            child: ElevatedButton.icon(
              onPressed: _cart.isNotEmpty ? _goToPayment : null,
              icon: const Icon(Icons.payment, size: 18),
              label: const Text('Cobrar',
                  style:
                      TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              style: ElevatedButton.styleFrom(
                backgroundColor: theme.colorScheme.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                elevation: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // STEP 2 — Payment
  // ═══════════════════════════════════════════════════════════════════
  Widget _buildPaymentStep(ThemeData theme, bool isDark) {
    final paymentMethodService = context.watch<PaymentMethodService>();
    final methods = paymentMethodService.paymentMethods
        .where((m) => m.isActive)
        .toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

    if (_selectedPaymentMethod == null && methods.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _selectedPaymentMethod == null) {
          setState(() => _selectedPaymentMethod = methods.first);
        }
      });
    }

    final amount = double.tryParse(_amountController.text) ?? 0;
    final changeAmount = amount - _total;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 12, 0),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back, size: 20),
                onPressed: () => setState(() => _step = _QuickSaleStep.cart),
                padding: EdgeInsets.zero,
                constraints:
                    const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
              const SizedBox(width: 4),
              Text('Cobrar',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w600)),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF252525)
                        : const Color(0xFFF5F6F8),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      Text('Total a cobrar',
                          style: TextStyle(
                            fontSize: 13,
                            color: theme.colorScheme.onSurface
                                .withOpacity(0.6),
                          )),
                      const SizedBox(height: 4),
                      Text(
                        '\$${_total.toStringAsFixed(0)}',
                        style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w700,
                          color: theme.colorScheme.primary,
                          letterSpacing: 1,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Text('Método de pago',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onSurface.withOpacity(0.6),
                    )),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: methods.map((m) {
                    final isSelected =
                        _selectedPaymentMethod?.id == m.id;
                    return _buildMethodChip(
                        m, isSelected, theme, isDark);
                  }).toList(),
                ),
                const SizedBox(height: 16),
                Text('Monto recibido',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onSurface.withOpacity(0.6),
                    )),
                const SizedBox(height: 8),
                TextField(
                  controller: _amountController,
                  keyboardType: const TextInputType.numberWithOptions(
                      decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[\d.]')),
                  ],
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    prefixText: '\$ ',
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 14),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _quickAmountBtn('Exacto', _total, theme),
                    if (_selectedPaymentMethod?.code == 'cash') ...[
                      _quickAmountBtn(
                        '\$${_roundUp(_total, 1000).toStringAsFixed(0)}',
                        _roundUp(_total, 1000),
                        theme,
                      ),
                      _quickAmountBtn(
                        '\$${_roundUp(_total, 5000).toStringAsFixed(0)}',
                        _roundUp(_total, 5000),
                        theme,
                      ),
                      _quickAmountBtn(
                        '\$${_roundUp(_total, 10000).toStringAsFixed(0)}',
                        _roundUp(_total, 10000),
                        theme,
                      ),
                    ],
                  ],
                ),
                if (changeAmount > 0) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF388E3C).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color:
                              const Color(0xFF388E3C).withOpacity(0.3)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Vuelto',
                            style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500)),
                        Text(
                          '\$${changeAmount.toStringAsFixed(0)}',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF388E3C),
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
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
          child: SizedBox(
            width: double.infinity,
            height: 44,
            child: ElevatedButton(
              onPressed: (!_isProcessing &&
                      _selectedPaymentMethod != null &&
                      amount >= _total)
                  ? _confirmPayment
                  : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF388E3C),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
                elevation: 0,
              ),
              child: _isProcessing
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('Confirmar Pago',
                      style: TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w600)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMethodChip(
      pm.PaymentMethod method, bool isSelected, ThemeData theme, bool isDark) {
    IconData icon;
    switch (method.code) {
      case 'cash':
        icon = Icons.payments_outlined;
        break;
      case 'card':
        icon = Icons.credit_card;
        break;
      case 'transfer':
        icon = Icons.swap_horiz;
        break;
      default:
        icon = Icons.payment;
    }

    return InkWell(
      onTap: () => setState(() => _selectedPaymentMethod = method),
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected
              ? theme.colorScheme.primary.withOpacity(isDark ? 0.25 : 0.1)
              : isDark
                  ? const Color(0xFF2A2A2A)
                  : const Color(0xFFF0F1F3),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected
                ? theme.colorScheme.primary
                : isDark
                    ? const Color(0xFF3A3A3A)
                    : const Color(0xFFDDE0E4),
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 18,
                color: isSelected
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurface.withOpacity(0.6)),
            const SizedBox(width: 6),
            Text(
              method.name,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                color: isSelected
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _quickAmountBtn(String label, double amount, ThemeData theme) {
    return OutlinedButton(
      onPressed: () {
        _amountController.text = amount.toStringAsFixed(0);
        setState(() {});
      },
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        side: BorderSide(
            color: theme.colorScheme.onSurface.withOpacity(0.15)),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Text(label, style: const TextStyle(fontSize: 12)),
    );
  }

  double _roundUp(double value, double step) {
    return (value / step).ceil() * step;
  }

  // ═══════════════════════════════════════════════════════════════════
  // STEP 3 — Confirmation
  // ═══════════════════════════════════════════════════════════════════
  Widget _buildConfirmationStep(ThemeData theme, bool isDark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: const BoxDecoration(
                color: Color(0xFF388E3C),
                shape: BoxShape.circle,
              ),
              child:
                  const Icon(Icons.check, size: 36, color: Colors.white),
            ),
            const SizedBox(height: 16),
            Text('¡Venta completada!',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF252525)
                    : const Color(0xFFF5F6F8),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _invoiceNumber ?? '',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.primary,
                  letterSpacing: 1.5,
                ),
              ),
            ),
            const SizedBox(height: 16),
            _confirmRow(
                'Total', '\$${_total.toStringAsFixed(0)}', theme),
            _confirmRow(
                'Pagado', '\$${_totalPaid.toStringAsFixed(0)}', theme),
            if (_change > 0)
              _confirmRow(
                  'Vuelto', '\$${_change.toStringAsFixed(0)}', theme,
                  valueColor: const Color(0xFF388E3C)),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 42,
              child: ElevatedButton.icon(
                onPressed: _newSale,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Nueva Venta',
                    style: TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w600)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.colorScheme.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  elevation: 0,
                ),
              ),
            ),
            const SizedBox(height: 8),
            if (_savedInvoiceId != null)
              TextButton(
                onPressed: () {
                  try {
                    final wm = context.read<WorkspaceManager>();
                    wm.addWorkspace(
                      title: _invoiceNumber ?? 'Factura',
                      initialRoute:
                          '/sales/invoices/$_savedInvoiceId',
                    );
                  } catch (_) {}
                },
                child: const Text('Ver factura →',
                    style: TextStyle(fontSize: 13)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _confirmRow(String label, String value, ThemeData theme,
      {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(
                fontSize: 14,
                color: theme.colorScheme.onSurface.withOpacity(0.6),
              )),
          Text(value,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: valueColor ?? theme.colorScheme.onSurface,
              )),
        ],
      ),
    );
  }
}

// ─── Minimalistic action toggle button ─────────────────────────────
class _ActionToggle extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;
  final ThemeData theme;
  final bool isDark;

  const _ActionToggle({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.onTap,
    required this.theme,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final activeColor = theme.colorScheme.primary;
    final inactiveColor = theme.colorScheme.onSurface.withOpacity(0.5);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 16, color: isActive ? activeColor : inactiveColor),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                color: isActive ? activeColor : inactiveColor,
              ),
            ),
            if (isActive) ...[
              const SizedBox(width: 3),
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: const Color(0xFF388E3C),
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
