import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../models/product.dart';
import '../models/payment_method.dart' as pm;
import '../models/tax_treatment.dart';
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
  int quantity = 1;
  double unitPrice;

  _CartItem({required this.product, double? unitPrice})
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
  final _priceOverrideController = TextEditingController();
  final _inlinePriceController = TextEditingController();
  final _inlinePriceFocusNode = FocusNode();
  List<Product> _searchResults = [];
  bool _isSearching = false;
  Timer? _debounce;

  // View mode: list vs cards
  bool _cardView = false;

  // Barcode scanner
  bool _scannerEnabled = false;
  StreamSubscription<String>? _barcodeSub;

  // Payment state
  pm.PaymentMethod? _selectedPaymentMethod;
  TaxTreatment _taxTreatment =
      TaxTreatment.noTax; // Default sin IVA, igual al flujo normal de facturas
  bool _isProcessing = false;
  String _paymentIdempotencyKey = const Uuid().v4();

  // Confirmation state
  String? _invoiceNumber;
  double _totalPaid = 0;
  double _change = 0;
  String? _savedInvoiceId;

  // Product inspector state
  Product? _inspectedProduct;
  int? _inspectedCartIndex;
  int? _editingPriceIndex;

  // ─── Computed ────────────────────────────────────────────────────
  double get _subtotal => _cart.fold(0.0, (s, i) => s + i.lineTotal);
  double get _total => _subtotal;
  double get _ivaAmount => _taxTreatment == TaxTreatment.taxIncluded
      ? _total - (_total / 1.19)
      : 0.0;
  double get _netAmount => _total - _ivaAmount;
  int get _itemCount => _cart.fold(0, (s, i) => s + i.quantity);

  // ─── Lifecycle ───────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    // Ensure payment methods are loaded — required for the payment step
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<PaymentMethodService>().loadPaymentMethods();
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    _amountController.dispose();
    _priceOverrideController.dispose();
    _inlinePriceController.dispose();
    _inlinePriceFocusNode.dispose();
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

  Future<Product?> _resolveBarcodeProduct(String barcode) async {
    final normalizedBarcode = barcode.trim();
    if (normalizedBarcode.isEmpty) {
      return null;
    }

    final inventory = context.read<InventoryService>();
    Product? exactMatch = await inventory.getProductBySku(normalizedBarcode);
    exactMatch ??= await inventory.getProductByBarcode(normalizedBarcode);
    exactMatch ??= await inventory.getProductBySupplierCode(normalizedBarcode);
    if (exactMatch != null) {
      return exactMatch;
    }

    final results =
        await inventory.searchProducts(normalizedBarcode, limit: 10);
    final normalizedCode = normalizedBarcode.toLowerCase();
    return results.cast<Product?>().firstWhere(
          (product) =>
              product != null &&
              (product.sku.toLowerCase() == normalizedCode ||
                  product.barcode?.toLowerCase() == normalizedCode ||
                  product.supplierCode?.trim().toLowerCase() == normalizedCode),
          orElse: () => null,
        );
  }

  Future<void> _onBarcodeScanned(String barcode) async {
    if (_step != _QuickSaleStep.cart) return;
    try {
      final product = await _resolveBarcodeProduct(barcode);
      if (product != null && mounted) {
        _addToCart(product);
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
        final results = await inventory.searchProducts(query.trim());
        if (mounted) {
          setState(() {
            _searchResults = results.take(20).toList(growable: false);
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
    setState(() {
      _cart.removeAt(index);

      if (_inspectedCartIndex == null) return;
      if (_inspectedCartIndex == index) {
        _inspectedCartIndex = null;
        _inspectedProduct = null;
        _priceOverrideController.clear();
      } else if (_inspectedCartIndex! > index) {
        _inspectedCartIndex = _inspectedCartIndex! - 1;
      }

      if (_editingPriceIndex == index) {
        _editingPriceIndex = null;
        _inlinePriceController.clear();
      } else if (_editingPriceIndex != null && _editingPriceIndex! > index) {
        _editingPriceIndex = _editingPriceIndex! - 1;
      }
    });
  }

  void _updateQty(int index, int delta) {
    setState(() {
      final nextQty = _cart[index].quantity + delta;
      if (nextQty <= 0) {
        _cart.removeAt(index);
        if (_inspectedCartIndex == index) {
          _inspectedCartIndex = null;
          _inspectedProduct = null;
          _priceOverrideController.clear();
        } else if (_inspectedCartIndex != null &&
            _inspectedCartIndex! > index) {
          _inspectedCartIndex = _inspectedCartIndex! - 1;
        }

        if (_editingPriceIndex == index) {
          _editingPriceIndex = null;
          _inlinePriceController.clear();
        } else if (_editingPriceIndex != null && _editingPriceIndex! > index) {
          _editingPriceIndex = _editingPriceIndex! - 1;
        }
        return;
      }
      _cart[index].quantity = nextQty;
    });
  }

  void _startInlinePriceEdit(int index) {
    setState(() {
      _editingPriceIndex = index;
      _inlinePriceController.text = _cart[index].unitPrice.toStringAsFixed(0);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _editingPriceIndex != index) return;
      _inlinePriceFocusNode.requestFocus();
      _inlinePriceController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _inlinePriceController.text.length,
      );
    });
  }

  void _saveInlinePriceEdit(int index) {
    if (index < 0 || index >= _cart.length) return;

    final parsed = double.tryParse(
      _inlinePriceController.text.trim().replaceAll(',', '.'),
    );

    if (parsed == null || parsed <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ingresa un precio valido mayor a 0.')),
      );
      return;
    }

    setState(() {
      _cart[index].unitPrice = parsed;
      _editingPriceIndex = null;
      _inlinePriceController.clear();

      if (_inspectedCartIndex == index) {
        _priceOverrideController.text = parsed.toStringAsFixed(0);
      }
    });

    _inlinePriceFocusNode.unfocus();
  }

  void _openProductDetails(Product product, {int? cartIndex}) {
    setState(() {
      _inspectedProduct = product;
      _inspectedCartIndex = cartIndex;
      _priceOverrideController.text =
          (cartIndex != null && cartIndex < _cart.length)
              ? _cart[cartIndex].unitPrice.toStringAsFixed(0)
              : product.price.toStringAsFixed(0);
    });
  }

  void _closeProductDetails() {
    setState(() {
      _inspectedProduct = null;
      _inspectedCartIndex = null;
      _priceOverrideController.clear();
    });
  }

  void _resetOverrideToListPrice() {
    final product = _inspectedProduct;
    if (product == null) return;
    _priceOverrideController.text = product.price.toStringAsFixed(0);
    _applyPriceOverride(showFeedback: false);
  }

  void _applyPriceOverride({bool showFeedback = true}) {
    final cartIndex = _inspectedCartIndex;
    if (cartIndex == null || cartIndex >= _cart.length) return;

    final parsed = double.tryParse(
      _priceOverrideController.text.trim().replaceAll(',', '.'),
    );

    if (parsed == null || parsed <= 0) {
      if (showFeedback && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Ingresa un precio valido mayor a 0.'),
          ),
        );
      }
      return;
    }

    setState(() {
      _cart[cartIndex].unitPrice = parsed;
    });

    if (showFeedback && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Precio actualizado a ${_money(parsed)}.'),
          duration: const Duration(milliseconds: 1400),
        ),
      );
    }
  }

  void _addInspectedProductToCart() {
    final product = _inspectedProduct;
    if (product == null) return;

    final existingIndex =
        _cart.indexWhere((item) => item.product.id == product.id);
    if (existingIndex >= 0) {
      setState(() {
        _cart[existingIndex].quantity++;
        _inspectedCartIndex = existingIndex;
        _priceOverrideController.text =
            _cart[existingIndex].unitPrice.toStringAsFixed(0);
      });
      return;
    }

    setState(() {
      _cart.add(_CartItem(product: product));
      _inspectedCartIndex = _cart.length - 1;
      _priceOverrideController.text = product.price.toStringAsFixed(0);
    });
  }

  void _openProductWorkspace(Product product) {
    try {
      final wm = context.read<WorkspaceManager>();
      wm.addWorkspace(
        title: product.name,
        initialRoute: '/inventory/products/${product.id}/edit',
      );
    } catch (_) {}
  }

  String _money(num value) {
    final rounded = value.round().toString();
    final buffer = StringBuffer();
    for (int index = 0; index < rounded.length; index++) {
      final reverseIndex = rounded.length - index;
      buffer.write(rounded[index]);
      if (reverseIndex > 1 && reverseIndex % 3 == 1) {
        buffer.write('.');
      }
    }
    return '\$${buffer.toString()}';
  }

  double _marginPercent(double salePrice, double cost) {
    if (cost <= 0) return 100;
    // El precio de venta incluye IVA (19%). Calculamos el neto.
    final netPrice = salePrice / 1.19;
    final pct = ((netPrice - cost) / cost) * 100;
    if (pct.isInfinite || pct.isNaN) return 100.0;
    return pct.clamp(-999.0, 999.0);
  }

  // ─── Payment ─────────────────────────────────────────────────────
  void _goToPayment() {
    if (_cart.isEmpty) return;
    _amountController.text = _total.toStringAsFixed(0);
    setState(() {
      _paymentIdempotencyKey = const Uuid().v4();
      _step = _QuickSaleStep.payment;
    });
  }

  Future<void> _confirmPayment() async {
    if (_isProcessing) return;
    final salesService = context.read<SalesService>();
    final tenantService = context.read<TenantService>();
    final amount = double.tryParse(_amountController.text) ?? 0;
    if (amount <= 0 || amount < _total) return;
    if (_selectedPaymentMethod == null) return;

    // ⚠️ WARN when paying with card but no IVA — same logic as POS dashboard
    if (_selectedPaymentMethod!.code == 'card' &&
        _taxTreatment == TaxTreatment.noTax) {
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
      if (result == null || result == 'cancel') return;
      if (result == 'add_tax') {
        setState(() => _taxTreatment = TaxTreatment.taxIncluded);
      }
    }

    setState(() => _isProcessing = true);

    try {
      final tenantId = await tenantService.getTenantId();
      if (tenantId == null) throw Exception('No tenant');

      final numberService = NumberGenerationService();
      final invoiceNumber = await numberService.nextSalesInvoiceNumber();

      final invoiceItems = _cart
          .map((item) => InvoiceItem(
                productId: item.product.id,
                productName: item.displayName,
                productSku: item.product.sku,
                quantity: item.quantity.toDouble(),
                unitPrice: item.unitPrice,
                discount: 0,
                lineTotal: item.lineTotal,
                cost: item.product.cost,
                purchaseTreatment: item.product.purchaseTreatment,
                isService: item.product.isService,
              ))
          .toList();

      // Use the user-selected (or dialog-updated) tax treatment
      final taxTreatment = _taxTreatment;
      double netAmount = _total;
      double ivaAmount = 0;
      if (taxTreatment == TaxTreatment.taxIncluded) {
        netAmount = _total / 1.19;
        ivaAmount = _total - netAmount;
      }

      // Step 1: Save as DRAFT (no journal entry yet) — mirrors normal invoice flow
      final invoice = Invoice(
        tenantId: tenantId,
        invoiceNumber: invoiceNumber,
        customerName: 'Cliente Mostrador',
        date: DateTime.now(),
        dueDate: DateTime.now(),
        status: InvoiceStatus.draft,
        subtotal: _total,
        netAmount: netAmount,
        ivaAmount: ivaAmount,
        total: _total,
        taxTreatment: taxTreatment,
        items: invoiceItems,
        invoiceType: 'sale',
        source: 'pos',
      );

      final saved = await salesService.saveInvoice(invoice);
      if (saved.id == null) throw Exception('Invoice save failed');

      // Step 2: Post to CONFIRMED — triggers DB to create sales invoice journal entry
      // (DR Cuentas por Cobrar / CR Ventas + IVA) — same path as normal invoice flow
      await salesService.updateInvoiceStatus(
          saved.id!, InvoiceStatus.confirmed);

      // Safety net: explicitly ensure the invoice JE was created.
      // Idempotent — if the trigger already created it this is a no-op.
      // Needed because older deployed trigger versions don't handle draft→confirmed.
      try {
        await Supabase.instance.client.rpc(
          'ensure_sales_invoice_journal_entry',
          params: {'p_invoice_id': saved.id!},
        );
      } catch (e) {
        // Non-fatal: log but don't abort the sale — payment JE is still correct
        debugPrint('⚠️ ensure_sales_invoice_journal_entry: $e');
      }

      final payment = Payment(
        tenantId: tenantId,
        invoiceId: saved.id!,
        invoiceReference: saved.invoiceNumber,
        paymentMethodId: _selectedPaymentMethod!.id,
        idempotencyKey: _paymentIdempotencyKey,
        amount: _total,
        date: DateTime.now(),
      );
      await salesService.registerPayment(payment);

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
      _taxTreatment = TaxTreatment.noTax; // reset to default for next sale
      _amountController.clear();
      _invoiceNumber = null;
      _totalPaid = 0;
      _change = 0;
      _savedInvoiceId = null;
      _paymentIdempotencyKey = const Uuid().v4();
      _step = _QuickSaleStep.cart;
    });
    _searchFocusNode.requestFocus();
  }

  // ─── Build ───────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return ColoredBox(
      color: Colors.transparent,
      child: switch (_step) {
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
        if (_inspectedProduct != null)
          Expanded(child: _buildProductInspector(theme, isDark))
        else if (_searchResults.isNotEmpty || _isSearching)
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
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: 0.15)),
                        const SizedBox(height: 8),
                        Text('Busca y agrega productos',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurface
                                  .withValues(alpha: 0.4),
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
            color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.06),
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
        color: borderColor.withValues(alpha: 0.5),
      ),
      itemBuilder: (ctx, i) => _buildListTile(_searchResults[i], theme, isDark),
    );
  }

  Widget _buildListTile(Product p, ThemeData theme, bool isDark) {
    final imgUrl = p.imageUrlOptimized ?? p.imageUrl;
    final inCart = _cart.any((item) => item.product.id == p.id);

    return InkWell(
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
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: () => _openProductDetails(p),
              tooltip: 'Ver detalles',
              icon: Icon(
                Icons.info_outline,
                size: 18,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
              ),
              visualDensity: VisualDensity.compact,
            ),
            const SizedBox(width: 6),
            // Price + stock + badge
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  _money(p.price),
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
                              theme.colorScheme.primary.withValues(alpha: 0.15),
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
                      p.trackStock ? '${p.stockQuantity} uds' : 'Servicio',
                      style: TextStyle(
                        fontSize: 10,
                        color: p.trackStock && p.stockQuantity <= 0
                            ? Colors.red
                            : theme.colorScheme.onSurface
                                .withValues(alpha: 0.45),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
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
      itemBuilder: (ctx, i) =>
          _buildCardTile(_searchResults[i], theme, isDark, borderColor),
    );
  }

  Widget _buildCardTile(
      Product p, ThemeData theme, bool isDark, Color borderColor) {
    final imgUrl = p.imageUrlOptimized ?? p.imageUrl;
    final inCart = _cart.any((item) => item.product.id == p.id);

    return Stack(
      children: [
        InkWell(
          onTap: () => _addToCart(p),
          borderRadius: BorderRadius.circular(8),
          child: Container(
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF222222) : const Color(0xFFFAFAFA),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: inCart
                    ? theme.colorScheme.primary.withValues(alpha: 0.5)
                    : borderColor,
                width: inCart ? 1.5 : 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 3,
                  child: ClipRRect(
                    borderRadius:
                        const BorderRadius.vertical(top: Radius.circular(7)),
                    child: _productImage(imgUrl, isDark, 28),
                  ),
                ),
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
                              _money(p.price),
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: theme.colorScheme.primary,
                              ),
                            ),
                            Text(
                              p.trackStock ? '${p.stockQuantity}' : 'Srv',
                              style: TextStyle(
                                fontSize: 10,
                                color: p.trackStock && p.stockQuantity <= 0
                                    ? Colors.red
                                    : theme.colorScheme.onSurface
                                        .withValues(alpha: 0.4),
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
        Positioned(
          top: 6,
          right: 6,
          child: Material(
            color: Colors.black.withValues(alpha: 0.28),
            borderRadius: BorderRadius.circular(999),
            child: InkWell(
              onTap: () => _openProductDetails(p),
              borderRadius: BorderRadius.circular(999),
              child: const Padding(
                padding: EdgeInsets.all(6),
                child: Icon(Icons.info_outline, size: 16, color: Colors.white),
              ),
            ),
          ),
        ),
      ],
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
          child: Icon(Icons.image_outlined, size: iconSize, color: Colors.grey),
        ),
        errorWidget: (_, __, ___) => Container(
          color: isDark ? const Color(0xFF333333) : const Color(0xFFEEEEEE),
          child: Icon(Icons.inventory_2, size: iconSize, color: Colors.grey),
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
    final isEditingPrice = _editingPriceIndex == index;

    return Container(
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
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
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
                  const SizedBox(height: 4),
                  InkWell(
                    onTap: () =>
                        _openProductDetails(item.product, cartIndex: index),
                    borderRadius: BorderRadius.circular(4),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Text(
                        'Ver detalle',
                        style: TextStyle(
                          fontSize: 10,
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _miniButton(Icons.remove, () => _updateQty(index, -1), theme),
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
            width: isEditingPrice ? 84 : 64,
            child: isEditingPrice
                ? TextField(
                    controller: _inlinePriceController,
                    focusNode: _inlinePriceFocusNode,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[\d.,]')),
                    ],
                    textAlign: TextAlign.right,
                    onSubmitted: (_) => _saveInlinePriceEdit(index),
                    onTapOutside: (_) => _saveInlinePriceEdit(index),
                    decoration: InputDecoration(
                      isDense: true,
                      prefixText: '\$ ',
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 8,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  )
                : GestureDetector(
                    onTap: () => _startInlinePriceEdit(index),
                    child: Container(
                      padding: const EdgeInsets.only(bottom: 2),
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(
                            color: theme.colorScheme.primary
                                .withValues(alpha: 0.4),
                            width: 1.5,
                          ),
                        ),
                      ),
                      child: Text(
                        _money(item.unitPrice),
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
          ),
          InkWell(
            onTap: () => _removeFromCart(index),
            borderRadius: BorderRadius.circular(4),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(Icons.close,
                  size: 14,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.35)),
            ),
          ),
        ],
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
              color: theme.colorScheme.onSurface.withValues(alpha: 0.15)),
        ),
        child: Icon(icon, size: 14),
      ),
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
                _money(_total),
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
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
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

  Widget _buildProductInspector(ThemeData theme, bool isDark) {
    final product = _inspectedProduct!;
    final cartIndex = _inspectedCartIndex;
    final inCart =
        cartIndex != null && cartIndex >= 0 && cartIndex < _cart.length;
    final cartItem = inCart ? _cart[cartIndex] : null;
    final salePrice = cartItem?.unitPrice ?? product.price;
    final imageUrl = product.imageUrlOptimized ?? product.imageUrl;
    final specs = product.specifications.entries
        .where((entry) =>
            entry.key.trim().isNotEmpty && entry.value.trim().isNotEmpty)
        .take(6)
        .toList(growable: false);
    final subtleBorder = theme.colorScheme.outline.withValues(alpha: 0.14);
    final cardBg = isDark ? const Color(0xFF232323) : Colors.white;
    final mutedColor = theme.colorScheme.onSurface.withValues(alpha: 0.52);
    final isLowStock =
        product.trackStock && product.stockQuantity <= product.minStockLevel;
    final margin = _marginPercent(salePrice, product.cost);
    final marginColor = salePrice < product.cost
        ? Colors.redAccent
        : margin < 10
            ? Colors.orange
            : theme.colorScheme.onSurface;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Top nav bar ──────────────────────────────────────────
          Row(
            children: [
              InkWell(
                onTap: _closeProductDetails,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: Icon(Icons.arrow_back,
                      size: 18,
                      color:
                          theme.colorScheme.onSurface.withValues(alpha: 0.7)),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Ficha del producto',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              TextButton.icon(
                onPressed: () => _openProductWorkspace(product),
                icon: const Icon(Icons.open_in_new, size: 14),
                label: const Text('Abrir'),
                style: TextButton.styleFrom(
                  foregroundColor: theme.colorScheme.primary,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  textStyle: const TextStyle(fontSize: 13),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // ── Product header card ──────────────────────────────────
          Container(
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: subtleBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Image banner
                ClipRRect(
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(12)),
                  child: SizedBox(
                    height: 160,
                    child: imageUrl != null && imageUrl.isNotEmpty
                        ? Container(
                            color: isDark
                                ? const Color(0xFF1E1E1E)
                                : const Color(0xFFF5F6F8),
                            child: CachedNetworkImage(
                              imageUrl: imageUrl,
                              fit: BoxFit.contain,
                              width: double.infinity,
                              height: 160,
                              placeholder: (_, __) => const Center(
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2)),
                              errorWidget: (_, __, ___) => Icon(
                                  Icons.inventory_2,
                                  size: 40,
                                  color: theme.colorScheme.onSurface
                                      .withValues(alpha: 0.18)),
                            ),
                          )
                        : Container(
                            color: isDark
                                ? const Color(0xFF2A2A2A)
                                : const Color(0xFFF5F6F8),
                            child: Icon(Icons.pedal_bike_outlined,
                                size: 56,
                                color: theme.colorScheme.onSurface
                                    .withValues(alpha: 0.18)),
                          ),
                  ),
                ),
                // Name + meta
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        product.name,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          height: 1.25,
                        ),
                      ),
                      const SizedBox(height: 6),
                      // SKU + category pill row
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          _pill(theme, isDark, subtleBorder,
                              'SKU: ${product.sku}',
                              isCode: true),
                          if ((product.brand ?? '').isNotEmpty)
                            _pill(theme, isDark, subtleBorder, product.brand!),
                          if ((product.supplierName ?? '').isNotEmpty)
                            _pill(theme, isDark, subtleBorder,
                                product.supplierName!),
                          if ((product.supplierCode ?? '').isNotEmpty)
                            _pill(theme, isDark, subtleBorder,
                                'Prov: ${product.supplierCode}',
                                isCode: true),
                          if ((product.categoryName ?? '').isNotEmpty)
                            _pill(theme, isDark, subtleBorder,
                                product.categoryName!),
                          if ((product.model ?? '').isNotEmpty)
                            _pill(theme, isDark, subtleBorder, product.model!),
                          if (!product.trackStock)
                            _pill(theme, isDark, subtleBorder, 'Servicio',
                                accent: theme.colorScheme.primary),
                        ],
                      ),
                      if ((product.warehouseLocation ?? '').isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Row(children: [
                          Icon(Icons.location_on_outlined,
                              size: 13, color: mutedColor),
                          const SizedBox(width: 4),
                          Text(product.warehouseLocation!,
                              style:
                                  TextStyle(fontSize: 12, color: mutedColor)),
                        ]),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // ── Key stats row ────────────────────────────────────────
          IntrinsicHeight(
            child: Row(
              children: [
                Expanded(
                    child: _statTile(theme, isDark, subtleBorder,
                        label: 'Precio lista',
                        value: _money(product.price),
                        sub: product.priceCurrency)),
                const SizedBox(width: 6),
                Expanded(
                    child: _statTile(theme, isDark, subtleBorder,
                        label: 'Costo',
                        value: _money(product.cost),
                        sub: product.costCurrency)),
                const SizedBox(width: 6),
                Expanded(
                    child: _statTile(theme, isDark, subtleBorder,
                        label: product.trackStock ? 'Stock' : 'Tipo',
                        value: product.trackStock
                            ? '${product.stockQuantity}'
                            : 'Servicio',
                        sub: product.trackStock
                            ? 'Mín ${product.minStockLevel}'
                            : product.lifecycleStatus,
                        valueColor: isLowStock ? Colors.redAccent : null)),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // ── Price override + actions ─────────────────────────────
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: subtleBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(Icons.edit_outlined,
                        size: 13,
                        color:
                            theme.colorScheme.primary.withValues(alpha: 0.7)),
                    const SizedBox(width: 5),
                    Text(
                      inCart ? 'Precio de esta venta' : 'Precio de venta',
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color:
                            theme.colorScheme.primary.withValues(alpha: 0.85),
                      ),
                    ),
                    const Spacer(),
                    if (inCart)
                      Text('× ${cartItem!.quantity}',
                          style: TextStyle(
                              fontSize: 12,
                              color: mutedColor,
                              fontWeight: FontWeight.w600)),
                  ],
                ),
                const SizedBox(height: 8),
                // Price field
                TextField(
                  controller: _priceOverrideController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[\d.,]'))
                  ],
                  onSubmitted: (_) => _applyPriceOverride(),
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.w700),
                  decoration: InputDecoration(
                    prefixText: '\$ ',
                    prefixStyle: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.onSurface
                            .withValues(alpha: 0.55)),
                    suffixIcon: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.edit,
                            size: 13,
                            color: theme.colorScheme.primary
                                .withValues(alpha: 0.45)),
                        const SizedBox(width: 4),
                        if (inCart)
                          IconButton(
                            onPressed: _resetOverrideToListPrice,
                            tooltip: 'Volver a precio lista',
                            icon: Icon(Icons.history,
                                size: 18, color: mutedColor),
                          )
                        else
                          const SizedBox(width: 8),
                      ],
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(
                          color:
                              theme.colorScheme.primary.withValues(alpha: 0.45),
                          width: 1.5),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(
                          color: theme.colorScheme.primary, width: 2),
                    ),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8)),
                    filled: true,
                    fillColor: isDark
                        ? theme.colorScheme.primary.withValues(alpha: 0.12)
                        : theme.colorScheme.primary.withValues(alpha: 0.07),
                  ),
                ),
                const SizedBox(height: 10),
                // Margin + line total strip
                Row(
                  children: [
                    Icon(Icons.trending_up, size: 14, color: marginColor),
                    const SizedBox(width: 4),
                    Text(
                      'Margen ${margin.toStringAsFixed(1)}%',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: marginColor),
                    ),
                    const SizedBox(width: 4),
                    Text('· dif ${_money(salePrice - product.cost)}',
                        style: TextStyle(fontSize: 12, color: mutedColor)),
                    if (inCart) ...[
                      const Spacer(),
                      Text('= ${_money(cartItem!.lineTotal)}',
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: theme.colorScheme.primary)),
                    ],
                  ],
                ),
                const SizedBox(height: 12),
                // Action buttons
                if (inCart) ...[
                  Row(children: [
                    Expanded(
                      flex: 3,
                      child: ElevatedButton.icon(
                        onPressed: _applyPriceOverride,
                        icon: const Icon(Icons.check, size: 15),
                        label: const Text('Aplicar precio'),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: OutlinedButton.icon(
                        onPressed: () => _updateQty(cartIndex, 1),
                        icon: const Icon(Icons.add, size: 15),
                        label: const Text('Sumar 1'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: OutlinedButton.icon(
                        onPressed: () => _updateQty(cartIndex, -1),
                        icon: const Icon(Icons.remove, size: 15),
                        label: const Text('Quitar'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          foregroundColor: Colors.redAccent,
                        ),
                      ),
                    ),
                  ]),
                ] else
                  ElevatedButton.icon(
                    onPressed: _addInspectedProductToCart,
                    icon: const Icon(Icons.add_shopping_cart, size: 16),
                    label: const Text('Agregar al carrito'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
              ],
            ),
          ),
          if ((product.description ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            _buildInfoSection(
              theme: theme,
              title: 'Descripción',
              child: Text(
                product.description!.trim(),
                style: TextStyle(
                  fontSize: 13,
                  height: 1.5,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.78),
                ),
              ),
            ),
          ],
          if (specs.isNotEmpty) ...[
            const SizedBox(height: 12),
            _buildInfoSection(
              theme: theme,
              title: 'Especificaciones',
              child: Column(
                children: specs
                    .map(
                      (entry) => _buildInfoRow(
                        theme,
                        entry.key,
                        entry.value,
                      ),
                    )
                    .toList(growable: false),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _pill(ThemeData theme, bool isDark, Color border, String label,
      {bool isCode = false, Color? accent}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: accent != null
            ? accent.withValues(alpha: 0.1)
            : isDark
                ? const Color(0xFF2A2A2A)
                : const Color(0xFFF2F3F5),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: accent ?? border),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontFamily: isCode ? 'monospace' : null,
          fontWeight: isCode ? FontWeight.w600 : FontWeight.w500,
          color: accent ?? theme.colorScheme.onSurface.withValues(alpha: 0.75),
        ),
      ),
    );
  }

  Widget _statTile(ThemeData theme, bool isDark, Color border,
      {required String label,
      required String value,
      required String sub,
      Color? valueColor}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF232323) : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                  letterSpacing: 0.3)),
          const SizedBox(height: 4),
          Text(value,
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: valueColor ?? theme.colorScheme.onSurface)),
          const SizedBox(height: 2),
          Text(sub,
              style: TextStyle(
                  fontSize: 10,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.48))),
        ],
      ),
    );
  }

  Widget _buildInfoSection({
    required ThemeData theme,
    required String title,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.brightness == Brightness.dark
            ? const Color(0xFF232323)
            : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: theme.colorScheme.outline.withValues(alpha: 0.14)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }

  Widget _buildInfoRow(ThemeData theme, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 118,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.58),
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.82),
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
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
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
                                .withValues(alpha: 0.6),
                          )),
                      const SizedBox(height: 4),
                      Text(
                        _money(_total),
                        style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w700,
                          color: theme.colorScheme.primary,
                          letterSpacing: 1,
                        ),
                      ),
                      // IVA breakdown
                      if (_taxTreatment == TaxTreatment.taxIncluded) ...[
                        const SizedBox(height: 8),
                        Divider(
                            height: 1,
                            color: theme.colorScheme.outline
                                .withValues(alpha: 0.2)),
                        const SizedBox(height: 6),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('Neto',
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: theme.colorScheme.onSurface
                                          .withValues(alpha: 0.55))),
                              Text(_money(_netAmount),
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: theme.colorScheme.onSurface
                                          .withValues(alpha: 0.55))),
                            ],
                          ),
                        ),
                        const SizedBox(height: 2),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('IVA (19%)',
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: theme.colorScheme.onSurface
                                          .withValues(alpha: 0.55))),
                              Text(_money(_ivaAmount),
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: theme.colorScheme.onSurface
                                          .withValues(alpha: 0.55))),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Text('Método de pago',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    )),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: methods.map((m) {
                    final isSelected = _selectedPaymentMethod?.id == m.id;
                    return _buildMethodChip(m, isSelected, theme, isDark);
                  }).toList(),
                ),
                const SizedBox(height: 12),
                // IVA toggle — same as terminal de pago en facturas normales
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: const Text('Incluye IVA (19%)',
                      style:
                          TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                  secondary: Icon(
                    _taxTreatment == TaxTreatment.taxIncluded
                        ? Icons.receipt_long
                        : Icons.receipt_outlined,
                    color: _taxTreatment == TaxTreatment.taxIncluded
                        ? theme.colorScheme.primary
                        : null,
                    size: 20,
                  ),
                  value: _taxTreatment == TaxTreatment.taxIncluded,
                  onChanged: (value) => setState(() {
                    _taxTreatment =
                        value ? TaxTreatment.taxIncluded : TaxTreatment.noTax;
                  }),
                ),
                const SizedBox(height: 4),
                Text('Monto recibido',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    )),
                const SizedBox(height: 8),
                TextField(
                  controller: _amountController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
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
                      color: const Color(0xFF388E3C).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color:
                              const Color(0xFF388E3C).withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Vuelto',
                            style: TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w500)),
                        Text(
                          _money(changeAmount),
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
                      style:
                          TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
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
      onTap: () => setState(() {
        _selectedPaymentMethod = method;
        // Auto-set IVA based on method's default — same as payment_form.dart
        _taxTreatment = method.defaultTaxTreatment;
      }),
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected
              ? theme.colorScheme.primary.withValues(alpha: isDark ? 0.25 : 0.1)
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
                    : theme.colorScheme.onSurface.withValues(alpha: 0.6)),
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
            color: theme.colorScheme.onSurface.withValues(alpha: 0.15)),
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
              child: const Icon(Icons.check, size: 36, color: Colors.white),
            ),
            const SizedBox(height: 16),
            Text('¡Venta completada!',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color:
                    isDark ? const Color(0xFF252525) : const Color(0xFFF5F6F8),
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
            _confirmRow('Total', _money(_total), theme),
            _confirmRow('Pagado', _money(_totalPaid), theme),
            if (_change > 0)
              _confirmRow('Vuelto', _money(_change), theme,
                  valueColor: const Color(0xFF388E3C)),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 42,
              child: ElevatedButton.icon(
                onPressed: _newSale,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Nueva Venta',
                    style:
                        TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
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
                      initialRoute: '/sales/invoices/$_savedInvoiceId',
                    );
                  } catch (_) {}
                },
                child:
                    const Text('Ver factura →', style: TextStyle(fontSize: 13)),
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
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
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
    final inactiveColor = theme.colorScheme.onSurface.withValues(alpha: 0.5);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: isActive ? activeColor : inactiveColor),
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
              const SizedBox(
                width: 6,
                height: 6,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Color(0xFF388E3C),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
