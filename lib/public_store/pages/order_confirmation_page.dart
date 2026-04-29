import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'order_confirmation_pdf.dart' deferred as order_pdf;
import '../theme/public_store_theme.dart';
import '../providers/public_store_tenant_provider.dart';
import '../providers/cart_provider.dart';
import '../../modules/website/services/mercadopago_service.dart';
import '../../modules/website/services/website_service.dart';
import '../../modules/website/models/website_models.dart';
import '../../shared/utils/chilean_utils.dart';
import '../../shared/widgets/branded_loading.dart';

class OrderConfirmationPage extends StatefulWidget {
  final String orderId;
  final String?
      paymentStatus; // 'success', 'failure', 'pending' from MercadoPago callback

  const OrderConfirmationPage({
    super.key,
    required this.orderId,
    this.paymentStatus,
  });

  @override
  State<OrderConfirmationPage> createState() => _OrderConfirmationPageState();
}

// Static cache to persist state across widget rebuilds during provider notifications
class _OrderConfirmationCache {
  static final Set<String> processedOrderIds = {};
  static final Map<String, OnlineOrder> loadedOrders = {};
  static final Set<String> currentlyLoading = {};
  static final Map<String, String?> loadErrors = {};
  static final Map<String, String?> paymentMessages = {};
}

class _OrderConfirmationPageState extends State<OrderConfirmationPage>
    with AutomaticKeepAliveClientMixin {
  OnlineOrder? _order;
  bool _isLoading = true;
  String? _error;
  String? _paymentMessage;

  // Keep this page alive in memory to prevent reloading on navigation
  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    debugPrint(
        '🎉 [OrderConfirmationPage] initState() - orderId: ${widget.orderId}, status: ${widget.paymentStatus}');

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadWebsiteSettings();
    });

    // Check if order is already cached (survives widget rebuilds)
    if (_OrderConfirmationCache.loadedOrders.containsKey(widget.orderId)) {
      debugPrint('🎉 [OrderConfirmationPage] Using cached order data');
      _order = _OrderConfirmationCache.loadedOrders[widget.orderId];
      _paymentMessage = _OrderConfirmationCache.paymentMessages[widget.orderId];
      _error = _OrderConfirmationCache.loadErrors[widget.orderId];
      _isLoading = false;
      return;
    }

    // Check if this order was already processed (prevents duplicate on page rebuild)
    if (_OrderConfirmationCache.processedOrderIds.contains(widget.orderId)) {
      debugPrint(
          '🎉 [OrderConfirmationPage] Order already processed, skipping callback');
      // Check if another instance is already loading
      if (!_OrderConfirmationCache.currentlyLoading.contains(widget.orderId)) {
        _loadOrder();
      } else {
        debugPrint(
            '🎉 [OrderConfirmationPage] Another instance is loading, waiting...');
        _waitForLoading();
      }
    } else {
      _handleMercadoPagoCallback();
    }
  }

  Future<void> _loadWebsiteSettings() async {
    try {
      await context.read<WebsiteService>().loadSettings();
    } catch (e) {
      debugPrint(
          '🎉 [OrderConfirmationPage] Error loading website settings: $e');
    }
  }

  /// Wait for another instance to finish loading, then use cached data
  Future<void> _waitForLoading() async {
    // Poll until loading is complete
    while (_OrderConfirmationCache.currentlyLoading.contains(widget.orderId)) {
      await Future.delayed(const Duration(milliseconds: 100));
      if (!mounted) return;
    }

    // Use cached data
    if (mounted) {
      setState(() {
        _order = _OrderConfirmationCache.loadedOrders[widget.orderId];
        _paymentMessage =
            _OrderConfirmationCache.paymentMessages[widget.orderId];
        _error = _OrderConfirmationCache.loadErrors[widget.orderId];
        _isLoading = false;
      });
    }
  }

  /// Handle MercadoPago callback when returning from payment
  Future<void> _handleMercadoPagoCallback() async {
    final status = widget.paymentStatus;

    if (status == null || status.isEmpty) {
      // No payment callback, just load the order
      _loadOrder();
      return;
    }

    debugPrint(
        '🎉 [OrderConfirmationPage] Processing MercadoPago callback: status=$status');

    // Mark as processed to prevent duplicate calls on rebuild
    _OrderConfirmationCache.processedOrderIds.add(widget.orderId);

    if (!mounted) return;
    setState(() {
      _isLoading = true;
    });

    try {
      // Get payment_id from URL query params (MercadoPago adds it)
      String? paymentId;
      if (kIsWeb) {
        final params = Uri.base.queryParameters;
        paymentId = params['payment_id'] ?? params['collection_id'];
        debugPrint(
            '🎉 [OrderConfirmationPage] Payment ID from URL: $paymentId');
      }

      if (status == 'success' || status == 'approved') {
        // Payment successful - update order status
        debugPrint(
            '🎉 [OrderConfirmationPage] Payment SUCCESS - processing...');

        final mercadopagoService =
            Provider.of<MercadoPagoService>(context, listen: false);
        final tenantProvider =
            Provider.of<PublicStoreTenantProvider>(context, listen: false);

        if (tenantProvider.tenantId != null) {
          await mercadopagoService.initialize(
              tenantId: tenantProvider.tenantId!);
        }

        // Process the payment callback
        // NOTE: This updates the order status. The webhook will create the invoice.
        // If webhook already processed, this will just update the order.
        await mercadopagoService.processPaymentCallback(
          orderId: widget.orderId,
          paymentId: paymentId ?? 'unknown',
          status: 'approved',
        );

        _paymentMessage = '¡Pago exitoso! Tu pedido está siendo procesado.';

        // Clear the cart
        if (mounted) {
          final cart = Provider.of<CartProvider>(context, listen: false);
          cart.clear();
        }
      } else if (status == 'pending' || status == 'in_process') {
        _paymentMessage =
            'Tu pago está pendiente de confirmación. Te notificaremos cuando se procese.';
      } else if (status == 'failure' || status == 'rejected') {
        _paymentMessage = 'El pago no se completó. Puedes intentar nuevamente.';
      }
    } catch (e) {
      debugPrint('🎉 [OrderConfirmationPage] Error processing callback: $e');
      // Don't show error to user - the order was created, payment might have gone through
    }

    // Load the order regardless of payment processing result
    await _loadOrder();
  }

  Future<void> _loadOrder() async {
    debugPrint('🎉 [OrderConfirmationPage] _loadOrder() started');

    // Check if already loading (another instance might be doing it)
    if (_OrderConfirmationCache.currentlyLoading.contains(widget.orderId)) {
      debugPrint(
          '🎉 [OrderConfirmationPage] Already loading in another instance, waiting...');
      await _waitForLoading();
      return;
    }

    // Check if already cached
    if (_OrderConfirmationCache.loadedOrders.containsKey(widget.orderId)) {
      debugPrint('🎉 [OrderConfirmationPage] Using cached order');
      if (mounted) {
        setState(() {
          _order = _OrderConfirmationCache.loadedOrders[widget.orderId];
          _paymentMessage =
              _OrderConfirmationCache.paymentMessages[widget.orderId];
          _error = _OrderConfirmationCache.loadErrors[widget.orderId];
          _isLoading = false;
        });
      }
      return;
    }

    // Mark as loading
    _OrderConfirmationCache.currentlyLoading.add(widget.orderId);

    if (mounted) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }

    try {
      // Small delay to let database trigger complete
      await Future.delayed(const Duration(milliseconds: 800));

      debugPrint(
          '🎉 [OrderConfirmationPage] Loading order directly from Supabase...');

      // Load order directly from Supabase - NO Provider dependency
      // This prevents issues when widget rebuilds during provider notifications
      final supabase = Supabase.instance.client;

      final response = await supabase.from('online_orders').select('''
            *,
            online_order_items (*)
          ''').eq('id', widget.orderId).maybeSingle();

      if (response == null) {
        throw Exception('Order not found');
      }

      debugPrint(
          '🎉 [OrderConfirmationPage] Order data received: ${response['order_number']}');

      final order = OnlineOrder.fromJson(response);
      debugPrint(
          '🎉 [OrderConfirmationPage] Order parsed: ${order.orderNumber}');

      // Cache the result regardless of mount state
      _OrderConfirmationCache.loadedOrders[widget.orderId] = order;
      _OrderConfirmationCache.paymentMessages[widget.orderId] = _paymentMessage;
      _OrderConfirmationCache.currentlyLoading.remove(widget.orderId);

      if (mounted) {
        setState(() {
          _order = order;
          _isLoading = false;
        });
        debugPrint(
            '🎉 [OrderConfirmationPage] setState complete, _order is SET');
      } else {
        debugPrint(
            '🎉 [OrderConfirmationPage] Widget unmounted but order cached for next instance');
      }
    } catch (e, stackTrace) {
      debugPrint('🎉 [OrderConfirmationPage] ERROR loading order: $e');
      debugPrint('🎉 [OrderConfirmationPage] Stack trace: $stackTrace');

      // Cache the error
      _OrderConfirmationCache.loadErrors[widget.orderId] =
          'Error al cargar el pedido: $e';
      _OrderConfirmationCache.currentlyLoading.remove(widget.orderId);

      if (mounted) {
        setState(() {
          _error = 'Error al cargar el pedido: $e';
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin

    // Return just the content - PublicStoreLayout handles Scaffold and scrolling
    if (_isLoading) {
      return const Center(child: BrandedLoading());
    }
    if (_error != null) {
      return _buildError();
    }
    if (_order == null) {
      return _buildNotFound();
    }
    return _buildConfirmation();
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Color(0xFFEF4444)),
            const SizedBox(height: 16),
            Text(
              _error ?? 'Error desconocido',
              style: const TextStyle(
                  fontSize: 16, color: PublicStoreTheme.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => context.go('/tienda'),
              style: ElevatedButton.styleFrom(
                backgroundColor: PublicStoreTheme.primaryBlue,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              ),
              child: const Text('Volver al Inicio'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNotFound() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.shopping_bag_outlined,
                size: 64, color: PublicStoreTheme.textSecondary),
            const SizedBox(height: 16),
            const Text(
              'Pedido no encontrado',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'No pudimos encontrar este pedido.',
              style: TextStyle(
                  fontSize: 16, color: PublicStoreTheme.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => context.go('/tienda'),
              style: ElevatedButton.styleFrom(
                backgroundColor: PublicStoreTheme.primaryBlue,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              ),
              child: const Text('Volver al Inicio'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConfirmation() {
    final order = _order!;
    final websiteService = context.watch<WebsiteService>();
    final transferBankName =
        websiteService.getSetting('payment_transfer_bank_name', '').trim();
    final transferAccountType =
        websiteService.getSetting('payment_transfer_account_type', '').trim();
    final transferAccountNumber =
        websiteService.getSetting('payment_transfer_account_number', '').trim();
    final transferAccountHolder =
        websiteService.getSetting('payment_transfer_account_holder', '').trim();
    final transferRut =
        websiteService.getSetting('payment_transfer_rut', '').trim();
    final transferContactEmail = websiteService
        .getSetting(
          'payment_transfer_contact_email',
          websiteService.getSetting('contact_email', ''),
        )
        .trim();
    final transferInstructions =
        websiteService.getSetting('payment_transfer_instructions', '').trim();
    final hasTransferDestination = [
      transferBankName,
      transferAccountNumber,
      transferAccountHolder,
      transferRut,
    ].any((value) => value.isNotEmpty);
    final transferProofInstructions = transferInstructions.isNotEmpty
        ? transferInstructions
        : transferContactEmail.isNotEmpty
            ? 'Una vez realizada la transferencia, envía el comprobante a $transferContactEmail con tu número de pedido.'
            : '';

    return SingleChildScrollView(
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 800),
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Success Icon
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check_circle,
                  size: 80,
                  color: Color(0xFF10B981),
                ),
              ),
              const SizedBox(height: 24),

              // Thank You Message
              const Text(
                '¡Pedido Recibido!',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: PublicStoreTheme.textPrimary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              const Text(
                'Gracias por tu compra. Hemos recibido tu pedido y lo procesaremos pronto.',
                style: TextStyle(
                  fontSize: 16,
                  color: PublicStoreTheme.textSecondary,
                ),
                textAlign: TextAlign.center,
              ),

              // Payment Status Message (from MercadoPago callback)
              if (_paymentMessage != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: _paymentMessage!.contains('exitoso') ||
                            _paymentMessage!.contains('confirmado')
                        ? const Color(0xFF10B981).withValues(alpha: 0.1)
                        : Colors.orange.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: _paymentMessage!.contains('exitoso') ||
                              _paymentMessage!.contains('confirmado')
                          ? const Color(0xFF10B981)
                          : Colors.orange,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _paymentMessage!.contains('exitoso') ||
                                _paymentMessage!.contains('confirmado')
                            ? Icons.check_circle
                            : Icons.info_outline,
                        color: _paymentMessage!.contains('exitoso') ||
                                _paymentMessage!.contains('confirmado')
                            ? const Color(0xFF10B981)
                            : Colors.orange,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _paymentMessage!,
                          style: TextStyle(
                            color: _paymentMessage!.contains('exitoso') ||
                                    _paymentMessage!.contains('confirmado')
                                ? const Color(0xFF059669)
                                : Colors.orange.shade800,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 32),

              // Order Details Card
              Card(
                elevation: 2,
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Número de Pedido',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            order.orderNumber,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: PublicStoreTheme.primaryBlue,
                            ),
                          ),
                        ],
                      ),
                      const Divider(height: 32),

                      // Customer Info
                      _buildInfoRow('Nombre', order.customerName),
                      _buildInfoRow('Email', order.customerEmail),
                      if (order.customerPhone != null)
                        _buildInfoRow('Teléfono', order.customerPhone!),
                      if (order.customerAddress != null)
                        _buildInfoRow('Dirección', order.customerAddress!),
                      const Divider(height: 32),

                      // Order Items
                      const Text(
                        'Productos',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      ...order.items.map((item) => _buildOrderItem(item)),
                      const Divider(height: 32),

                      // Totals - Only show IVA if taxAmount > 0 (MercadoPago/Card)
                      _buildTotalRow('Subtotal', order.subtotal),
                      if (order.taxAmount > 0)
                        _buildTotalRow('IVA (19%)', order.taxAmount),
                      if (order.shippingCost > 0)
                        _buildTotalRow('Envío', order.shippingCost),
                      if (order.discountAmount > 0)
                        _buildTotalRow('Descuento', -order.discountAmount),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: PublicStoreTheme.primaryBlue
                              .withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Total',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              ChileanUtils.formatCurrency(order.total),
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: PublicStoreTheme.primaryBlue,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Payment Instructions (if payment method is transfer)
              if (order.paymentMethod == 'transfer')
                Card(
                  elevation: 2,
                  color: const Color(0xFFF59E0B).withValues(alpha: 0.1),
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.info_outline, color: Color(0xFFF59E0B)),
                            SizedBox(width: 8),
                            Text(
                              'Instrucciones de Pago',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Para completar tu pedido, realiza una transferencia bancaria a:',
                          style: TextStyle(fontSize: 14),
                        ),
                        const SizedBox(height: 12),
                        if (transferBankName.isNotEmpty)
                          _buildPaymentInfo('Banco', transferBankName),
                        if (transferAccountNumber.isNotEmpty)
                          _buildPaymentInfo(
                            transferAccountType.isNotEmpty
                                ? transferAccountType
                                : 'Cuenta',
                            transferAccountNumber,
                          ),
                        if (transferRut.isNotEmpty)
                          _buildPaymentInfo('RUT', transferRut),
                        if (transferAccountHolder.isNotEmpty)
                          _buildPaymentInfo('Nombre', transferAccountHolder),
                        _buildPaymentInfo(
                            'Monto', ChileanUtils.formatCurrency(order.total)),
                        if (!hasTransferDestination) ...[
                          const SizedBox(height: 12),
                          const Text(
                            'Nuestro equipo te compartirá los datos de transferencia para completar el pago.',
                            style: TextStyle(
                              fontSize: 12,
                              color: PublicStoreTheme.textSecondary,
                            ),
                          ),
                        ],
                        if (transferProofInstructions.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Text(
                            transferProofInstructions,
                            style: const TextStyle(
                              fontSize: 12,
                              color: PublicStoreTheme.textSecondary,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 24),

              // What's Next
              Card(
                elevation: 2,
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '¿Qué sigue?',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      _buildNextStep(
                        Icons.email_outlined,
                        'Te enviaremos un email de confirmación con los detalles de tu pedido.',
                      ),
                      _buildNextStep(
                        Icons.local_shipping_outlined,
                        'Procesaremos tu pedido en 1-2 días hábiles.',
                      ),
                      _buildNextStep(
                        Icons.phone_outlined,
                        'Te contactaremos si necesitamos más información.',
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 32),

              // Action Buttons
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _downloadOrderPdf(order),
                      icon: const Icon(Icons.download, size: 18),
                      label: const Text('Descargar'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        side: const BorderSide(
                            color: PublicStoreTheme.primaryBlue),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => context.go('/productos'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        side: const BorderSide(
                            color: PublicStoreTheme.primaryBlue),
                      ),
                      child: const Text('Seguir Comprando'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => context.go('/tienda'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: PublicStoreTheme.primaryBlue,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: const Text('Volver al Inicio'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: const TextStyle(
                color: PublicStoreTheme.textSecondary,
                fontSize: 14,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOrderItem(OnlineOrderItem item) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.productName,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (item.productSku != null)
                  Text(
                    'SKU: ${item.productSku}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: PublicStoreTheme.textSecondary,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Text(
            'x${item.quantity}',
            style: const TextStyle(
              fontSize: 14,
              color: PublicStoreTheme.textSecondary,
            ),
          ),
          const SizedBox(width: 16),
          Text(
            ChileanUtils.formatCurrency(item.subtotal),
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTotalRow(String label, double amount) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              color: PublicStoreTheme.textSecondary,
            ),
          ),
          Text(
            ChileanUtils.formatCurrency(amount),
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentInfo(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            child: Text(
              '$label:',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNextStep(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 24, color: PublicStoreTheme.primaryBlue),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _downloadOrderPdf(OnlineOrder order) async {
    await order_pdf.loadLibrary();
    await order_pdf.downloadOrderPdf(order);
  }
}
