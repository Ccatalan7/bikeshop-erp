import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import 'order_confirmation_pdf.dart' deferred as order_pdf;
import '../utils/web_utils.dart' as web_utils;
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

enum _PaymentPresentation {
  paid,
  failed,
  pending,
  transferPending,
  orderReceived,
}

class _OrderConfirmationPageState extends State<OrderConfirmationPage>
    with AutomaticKeepAliveClientMixin {
  static const Color _logoBlue = Color(0xFF093357);
  static const Color _warmLine = Color(0xFFE8E2D8);
  static const Color _warmSurface = Color(0xFFF7F4EE);
  static const Color _softSurface = Color(0xFFFCFBF8);
  static const Color _successGreen = Color(0xFF10B981);

  OnlineOrder? _order;
  bool _isLoading = true;
  bool _isRetryingPayment = false;
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
      final tenantId = await _resolveTenantId(
        timeout: const Duration(seconds: 4),
      );
      if (!mounted || tenantId == null) return;

      await context.read<WebsiteService>().loadSettingsForTenant(tenantId);
    } catch (e) {
      debugPrint(
          '🎉 [OrderConfirmationPage] Error loading website settings: $e');
    }
  }

  Future<String?> _resolveTenantId({
    Duration timeout = const Duration(seconds: 8),
  }) async {
    final startedAt = DateTime.now();
    final tenantProvider = context.read<PublicStoreTenantProvider>();

    while (mounted && DateTime.now().difference(startedAt) < timeout) {
      final tenantId = tenantProvider.tenantId;

      if (tenantId != null && tenantId.isNotEmpty) {
        return tenantId;
      }

      if (!tenantProvider.isLoading) {
        await tenantProvider.detectTenant();
        final detectedTenantId = tenantProvider.tenantId;
        if (detectedTenantId != null && detectedTenantId.isNotEmpty) {
          return detectedTenantId;
        }
      }

      await Future.delayed(const Duration(milliseconds: 80));
    }

    if (!mounted) return null;
    return tenantProvider.tenantId;
  }

  /// Wait for another instance to finish loading, then use cached data
  Future<void> _waitForLoading() async {
    // Poll until loading is complete
    while (_OrderConfirmationCache.currentlyLoading.contains(widget.orderId)) {
      await Future.delayed(const Duration(milliseconds: 100));
      if (!mounted) return;
    }

    final cachedOrder = _OrderConfirmationCache.loadedOrders[widget.orderId];
    final cachedError = _OrderConfirmationCache.loadErrors[widget.orderId];

    if (cachedOrder == null && cachedError == null) {
      debugPrint(
          '🎉 [OrderConfirmationPage] Loader finished without cache, retrying from active instance...');
      await _loadOrder();
      return;
    }

    // Use cached data
    if (mounted) {
      setState(() {
        _order = cachedOrder;
        _paymentMessage =
            _OrderConfirmationCache.paymentMessages[widget.orderId];
        _error = cachedError;
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

    if (!mounted) return;
    setState(() {
      _isLoading = true;
    });

    var callbackProcessed = false;

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
        final tenantId = await _resolveTenantId();

        if (tenantId == null || tenantId.isEmpty) {
          throw Exception(
              'No se pudo detectar la tienda para verificar el pago.');
        }

        await mercadopagoService.initialize(tenantId: tenantId);

        if (paymentId == null || paymentId.isEmpty) {
          _paymentMessage =
              'MercadoPago no devolvió un identificador de pago. Revisaremos el pedido y te contactaremos si el pago se acredita.';
          callbackProcessed = true;
          await _loadOrder();
          return;
        }

        final payment = await mercadopagoService.getPaymentStatus(
          paymentId,
          orderId: widget.orderId,
        );
        final paymentStatus = payment?['status']?.toString();
        final externalReference = payment?['external_reference']?.toString();

        if (payment == null ||
            paymentStatus != 'approved' ||
            externalReference != widget.orderId) {
          _paymentMessage =
              'MercadoPago todavía no confirmó el pago. Te notificaremos cuando se procese.';
          callbackProcessed = true;
          await _loadOrder();
          return;
        }

        _paymentMessage = '¡Pago exitoso! Tu pedido está siendo procesado.';
        callbackProcessed = true;

        // Clear the cart
        if (mounted) {
          final cart = Provider.of<CartProvider>(context, listen: false);
          cart.clear();
        }
      } else if (status == 'pending' || status == 'in_process') {
        _paymentMessage =
            'Tu pago está pendiente de confirmación. Te notificaremos cuando se procese.';
        callbackProcessed = true;
      } else if (status == 'failure' || status == 'rejected') {
        _paymentMessage = 'El pago no se completó. Puedes intentar nuevamente.';
        callbackProcessed = true;
      }
    } catch (e) {
      debugPrint('🎉 [OrderConfirmationPage] Error processing callback: $e');
      _paymentMessage =
          'Estamos confirmando tu pago. Si ya fue aprobado, el pedido se actualizará en unos segundos.';
    } finally {
      if (callbackProcessed) {
        _OrderConfirmationCache.processedOrderIds.add(widget.orderId);
      }
    }

    // Load the order regardless of payment processing result
    await _loadOrder();
  }

  bool _canRetryMercadoPago(OnlineOrder order) {
    final method = (order.paymentMethod ?? '').toLowerCase();
    final paymentStatus = order.paymentStatus.toLowerCase();
    final orderStatus = order.status.toLowerCase();

    return method == 'mercadopago' &&
        paymentStatus != 'paid' &&
        orderStatus != 'cancelled';
  }

  Future<void> _retryMercadoPagoPayment(OnlineOrder order) async {
    if (_isRetryingPayment) return;

    setState(() => _isRetryingPayment = true);

    final tenantProvider = context.read<PublicStoreTenantProvider>();
    final tenantId = tenantProvider.tenantId ?? order.tenantId;
    final mercadopagoService = context.read<MercadoPagoService>();

    try {
      if (tenantId.isEmpty) {
        throw Exception(
            'No se pudo detectar la tienda para reintentar el pago.');
      }

      await mercadopagoService.initialize(tenantId: tenantId);

      if (!mercadopagoService.isConfigured) {
        throw Exception('MercadoPago no está configurado para esta tienda.');
      }

      final preference = await mercadopagoService.createPreference(
        orderId: order.id,
        orderNumber: order.orderNumber,
        total: order.total,
        items: order.items
            .map((item) => {
                  'title': item.productName,
                  'quantity': item.quantity,
                  'unit_price': item.unitPrice,
                })
            .toList(),
        customerEmail: order.customerEmail,
        customerName: order.customerName,
      );

      final initPoint = preference['init_point'] as String?;
      if (initPoint == null || initPoint.isEmpty) {
        throw Exception('MercadoPago no devolvió URL de pago.');
      }

      if (kIsWeb) {
        web_utils.WebUtils.openUrl(initPoint);
      } else {
        final url = Uri.parse(initPoint);
        if (!await canLaunchUrl(url)) {
          throw Exception('No se pudo abrir MercadoPago.');
        }
        await launchUrl(url, mode: LaunchMode.externalApplication);
      }
    } catch (error) {
      debugPrint('MercadoPago retry failed: $error');
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No pudimos reintentar el pago: $error'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 8),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isRetryingPayment = false);
      }
    }
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
      if (!mounted) return;

      debugPrint(
          '🎉 [OrderConfirmationPage] Loading order directly from Supabase...');

      final websiteService =
          Provider.of<WebsiteService>(context, listen: false);
      final tenantId = await _resolveTenantId();

      if (tenantId == null || tenantId.isEmpty) {
        throw Exception('No se pudo detectar la tienda del pedido');
      }

      final order = await websiteService.getPublicOrderById(
        orderId: widget.orderId,
        tenantId: tenantId,
      );

      if (order == null) {
        throw Exception('Order not found');
      }

      debugPrint(
          '🎉 [OrderConfirmationPage] Order data received: ${order.orderNumber}');
      debugPrint(
          '🎉 [OrderConfirmationPage] Order parsed: ${order.orderNumber}');

      // Cache the result regardless of mount state
      _OrderConfirmationCache.loadedOrders[widget.orderId] = order;
      _OrderConfirmationCache.paymentMessages[widget.orderId] = _paymentMessage;
      _OrderConfirmationCache.loadErrors.remove(widget.orderId);

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

      if (mounted) {
        setState(() {
          _error = 'Error al cargar el pedido: $e';
          _isLoading = false;
        });
      }
    } finally {
      _OrderConfirmationCache.currentlyLoading.remove(widget.orderId);
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
    return _buildStateView(
      icon: Icons.error_outline,
      title: 'No pudimos cargar tu pedido',
      message: _error ?? 'Error desconocido',
      actionLabel: 'VOLVER AL INICIO',
      onPressed: () => context.go('/tienda'),
      accentColor: const Color(0xFFB91C1C),
    );
  }

  Widget _buildNotFound() {
    return _buildStateView(
      icon: Icons.shopping_bag_outlined,
      title: 'Pedido no encontrado',
      message: 'No pudimos encontrar este pedido.',
      actionLabel: 'VOLVER AL INICIO',
      onPressed: () => context.go('/tienda'),
      accentColor: _logoBlue,
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

    final paymentPresentation = _paymentPresentationFor(order);

    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 980;
        final horizontalMargin = constraints.maxWidth < 760 ? 16.0 : 24.0;
        final verticalMargin = isMobile ? 28.0 : 44.0;

        return SingleChildScrollView(
          child: Center(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 1320),
              margin: EdgeInsets.symmetric(
                horizontal: horizontalMargin,
                vertical: verticalMargin,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildConfirmationHero(
                    order: order,
                    paymentPresentation: paymentPresentation,
                  ),
                  const SizedBox(height: 32),
                  if (isMobile) ...[
                    _buildSummaryRail(
                      order,
                      paymentPresentation: paymentPresentation,
                    ),
                    const SizedBox(height: 24),
                    _buildOrderDetailsSection(order),
                    const SizedBox(height: 24),
                    _buildProductsSection(order),
                    if (order.paymentMethod == 'transfer') ...[
                      const SizedBox(height: 24),
                      _buildTransferSection(
                        order,
                        hasTransferDestination: hasTransferDestination,
                        transferBankName: transferBankName,
                        transferAccountType: transferAccountType,
                        transferAccountNumber: transferAccountNumber,
                        transferAccountHolder: transferAccountHolder,
                        transferRut: transferRut,
                        transferProofInstructions: transferProofInstructions,
                      ),
                    ],
                    const SizedBox(height: 24),
                    _buildNextStepsSection(paymentPresentation),
                  ] else ...[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 7,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildOrderDetailsSection(order),
                              const SizedBox(height: 24),
                              _buildProductsSection(order),
                              if (order.paymentMethod == 'transfer') ...[
                                const SizedBox(height: 24),
                                _buildTransferSection(
                                  order,
                                  hasTransferDestination:
                                      hasTransferDestination,
                                  transferBankName: transferBankName,
                                  transferAccountType: transferAccountType,
                                  transferAccountNumber: transferAccountNumber,
                                  transferAccountHolder: transferAccountHolder,
                                  transferRut: transferRut,
                                  transferProofInstructions:
                                      transferProofInstructions,
                                ),
                              ],
                              const SizedBox(height: 24),
                              _buildNextStepsSection(paymentPresentation),
                            ],
                          ),
                        ),
                        const SizedBox(width: 28),
                        Expanded(
                          flex: 4,
                          child: _buildSummaryRail(
                            order,
                            paymentPresentation: paymentPresentation,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildStateView({
    required IconData icon,
    required String title,
    required String message,
    required String actionLabel,
    required VoidCallback onPressed,
    required Color accentColor,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final horizontalMargin = constraints.maxWidth < 760 ? 16.0 : 24.0;

        return SingleChildScrollView(
          child: Center(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 1320),
              margin: EdgeInsets.symmetric(
                horizontal: horizontalMargin,
                vertical: 44,
              ),
              child: Center(
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 560),
                  padding:
                      const EdgeInsets.symmetric(vertical: 36, horizontal: 8),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Container(
                        width: 148,
                        height: 148,
                        decoration: BoxDecoration(
                          color: accentColor.withValues(alpha: 0.08),
                          border: Border.all(
                            color: accentColor.withValues(alpha: 0.2),
                          ),
                        ),
                        child: Icon(
                          icon,
                          size: 62,
                          color: accentColor,
                        ),
                      ),
                      const SizedBox(height: 32),
                      _buildSectionHeading(title),
                      const SizedBox(height: 16),
                      Text(
                        message,
                        style: const TextStyle(
                          fontFamily: PublicStoreTheme.defaultBodyFont,
                          fontSize: 15,
                          color: PublicStoreTheme.textSecondary,
                          height: 1.6,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 32),
                      FilledButton(
                        onPressed: onPressed,
                        style: FilledButton.styleFrom(
                          backgroundColor: _logoBlue,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 30,
                            vertical: 18,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                        child: Text(actionLabel),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildConfirmationHero({
    required OnlineOrder order,
    required _PaymentPresentation paymentPresentation,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 820;
        final statusLine =
            _paymentMessage ?? _presentationStatusLine(paymentPresentation);

        final titleBlock = Column(
          crossAxisAlignment:
              isCompact ? CrossAxisAlignment.start : CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: _presentationAccentColor(paymentPresentation),
                    borderRadius: BorderRadius.circular(17),
                  ),
                  child: Icon(
                    _presentationIcon(paymentPresentation),
                    size: 22,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  _presentationKicker(paymentPresentation),
                  style: TextStyle(
                    fontFamily: PublicStoreTheme.defaultBodyFont,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: Colors.white.withValues(alpha: 0.78),
                    letterSpacing: 1.4,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 28),
            Text(
              _presentationTitle(paymentPresentation),
              style: const TextStyle(
                fontFamily: PublicStoreTheme.defaultHeadingFont,
                fontSize: 52,
                fontWeight: FontWeight.w700,
                color: Colors.white,
                height: 0.98,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              _presentationSubtitle(paymentPresentation),
              style: TextStyle(
                fontFamily: PublicStoreTheme.defaultBodyFont,
                fontSize: 16,
                color: Colors.white.withValues(alpha: 0.78),
                height: 1.55,
              ),
            ),
          ],
        );

        final orderBlock = Container(
          width: isCompact ? double.infinity : 360,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.08),
            border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'PEDIDO',
                style: TextStyle(
                  fontFamily: PublicStoreTheme.defaultBodyFont,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: Colors.white.withValues(alpha: 0.68),
                  letterSpacing: 1.3,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                order.orderNumber,
                style: const TextStyle(
                  fontFamily: PublicStoreTheme.defaultHeadingFont,
                  fontSize: 34,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  height: 0.98,
                ),
              ),
              const SizedBox(height: 18),
              Container(
                height: 1,
                color: Colors.white.withValues(alpha: 0.16),
              ),
              const SizedBox(height: 18),
              _buildHeroFact('Total', ChileanUtils.formatCurrency(order.total)),
              const SizedBox(height: 12),
              _buildHeroFact(
                'Pago',
                _formatPaymentMethod(order.paymentMethod ?? ''),
              ),
            ],
          ),
        );

        return Container(
          width: double.infinity,
          padding: EdgeInsets.symmetric(
            horizontal: isCompact ? 22 : 34,
            vertical: isCompact ? 32 : 42,
          ),
          decoration: const BoxDecoration(color: _logoBlue),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (isCompact) ...[
                titleBlock,
                const SizedBox(height: 28),
                orderBlock,
              ] else
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(child: titleBlock),
                    const SizedBox(width: 44),
                    orderBlock,
                  ],
                ),
              if (statusLine != null) ...[
                const SizedBox(height: 28),
                _buildHeroStatusLine(
                  statusLine,
                  paymentPresentation: paymentPresentation,
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeroFact(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label.toUpperCase(),
          style: TextStyle(
            fontFamily: PublicStoreTheme.defaultBodyFont,
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: Colors.white.withValues(alpha: 0.62),
            letterSpacing: 0.9,
          ),
        ),
        const SizedBox(width: 20),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: const TextStyle(
              fontFamily: PublicStoreTheme.defaultBodyFont,
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: Colors.white,
              height: 1.35,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHeroStatusLine(
    String message, {
    required _PaymentPresentation paymentPresentation,
  }) {
    final accent = _presentationAccentColor(paymentPresentation);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        border: Border(
          left: BorderSide(color: accent, width: 3),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            paymentPresentation == _PaymentPresentation.failed
                ? Icons.error_outline
                : paymentPresentation == _PaymentPresentation.paid
                    ? Icons.check_circle_outline
                    : Icons.info_outline,
            size: 20,
            color: accent,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                fontFamily: PublicStoreTheme.defaultBodyFont,
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: Colors.white,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOrderDetailsSection(OnlineOrder order) {
    final rows = <MapEntry<String, String>>[
      MapEntry('Número de pedido', order.orderNumber),
      MapEntry('Nombre', order.customerName),
      MapEntry('Email', order.customerEmail),
      if (order.customerPhone != null && order.customerPhone!.trim().isNotEmpty)
        MapEntry('Teléfono', order.customerPhone!),
      MapEntry('Entrega', order.deliveryDisplayName),
      if (order.customerAddress != null &&
          order.customerAddress!.trim().isNotEmpty)
        MapEntry(
          order.deliveryType == 'pickup' ? 'Punto de retiro' : 'Dirección',
          order.customerAddress!,
        ),
    ];

    return _buildContentSection(
      title: 'Detalle del pedido',
      child: Column(
        children: [
          for (var index = 0; index < rows.length; index++)
            _buildInfoRow(
              rows[index].key,
              rows[index].value,
              isLast: index == rows.length - 1,
            ),
        ],
      ),
    );
  }

  Widget _buildProductsSection(OnlineOrder order) {
    return _buildContentSection(
      title: 'Productos',
      child: Column(
        children: [
          for (var index = 0; index < order.items.length; index++)
            _buildOrderItem(
              order.items[index],
              isLast: index == order.items.length - 1,
            ),
        ],
      ),
    );
  }

  Widget _buildTransferSection(
    OnlineOrder order, {
    required bool hasTransferDestination,
    required String transferBankName,
    required String transferAccountType,
    required String transferAccountNumber,
    required String transferAccountHolder,
    required String transferRut,
    required String transferProofInstructions,
  }) {
    final details = <MapEntry<String, String>>[
      if (transferBankName.isNotEmpty) MapEntry('Banco', transferBankName),
      if (transferAccountNumber.isNotEmpty)
        MapEntry(
          transferAccountType.isNotEmpty ? transferAccountType : 'Cuenta',
          transferAccountNumber,
        ),
      if (transferRut.isNotEmpty) MapEntry('RUT', transferRut),
      if (transferAccountHolder.isNotEmpty)
        MapEntry('Nombre', transferAccountHolder),
      MapEntry('Monto', ChileanUtils.formatCurrency(order.total)),
    ];

    return _buildContentSection(
      title: 'Instrucciones de pago',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Para completar tu pedido, realiza una transferencia bancaria a:',
            style: TextStyle(
              fontFamily: PublicStoreTheme.defaultBodyFont,
              fontSize: 14,
              color: Colors.black87,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 16),
          for (var index = 0; index < details.length; index++)
            _buildPaymentInfo(
              details[index].key,
              details[index].value,
              isLast: index == details.length - 1,
            ),
          if (!hasTransferDestination) ...[
            const SizedBox(height: 14),
            const Text(
              'Nuestro equipo te compartirá los datos de transferencia para completar el pago.',
              style: TextStyle(
                fontFamily: PublicStoreTheme.defaultBodyFont,
                fontSize: 12,
                color: PublicStoreTheme.textSecondary,
                height: 1.5,
              ),
            ),
          ],
          if (transferProofInstructions.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(
              transferProofInstructions,
              style: const TextStyle(
                fontFamily: PublicStoreTheme.defaultBodyFont,
                fontSize: 12,
                color: PublicStoreTheme.textSecondary,
                height: 1.5,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildNextStepsSection(_PaymentPresentation paymentPresentation) {
    final steps = _nextStepsFor(paymentPresentation);

    return _buildContentSection(
      title: 'Qué sigue',
      child: Column(
        children: [
          for (var index = 0; index < steps.length; index++)
            _buildNextStep(
              steps[index],
              isLast: index == steps.length - 1,
            ),
        ],
      ),
    );
  }

  Widget _buildSummaryRail(
    OnlineOrder order, {
    required _PaymentPresentation paymentPresentation,
  }) {
    final retryLabel = paymentPresentation == _PaymentPresentation.failed
        ? 'PAGAR CON OTRO MEDIO'
        : 'REINTENTAR PAGO';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: _warmSurface.withValues(alpha: 0.56),
        border: const Border(
          top: BorderSide(color: _warmLine),
          bottom: BorderSide(color: _warmLine),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            paymentPresentation == _PaymentPresentation.paid
                ? 'RESUMEN DE COMPRA'
                : 'RESUMEN DEL PEDIDO',
            style: const TextStyle(
              fontFamily: PublicStoreTheme.defaultHeadingFont,
              fontSize: 32,
              fontWeight: FontWeight.w700,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            order.orderNumber,
            style: const TextStyle(
              fontFamily: PublicStoreTheme.defaultHeadingFont,
              fontSize: 34,
              fontWeight: FontWeight.w700,
              color: _logoBlue,
              height: 0.95,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildMetaPill(
                _formatPaymentMethod(order.paymentMethod ?? ''),
              ),
              _buildMetaPill(
                _summaryPaymentLabel(paymentPresentation),
                accent: _presentationAccentColor(paymentPresentation),
              ),
            ],
          ),
          const SizedBox(height: 18),
          _buildSummaryMetric(
            'Subtotal',
            ChileanUtils.formatCurrency(order.subtotal),
          ),
          if (order.taxAmount > 0) ...[
            const SizedBox(height: 12),
            _buildSummaryMetric(
              'IVA (19%)',
              ChileanUtils.formatCurrency(order.taxAmount),
              secondary: true,
            ),
          ],
          if (order.shippingCost > 0) ...[
            const SizedBox(height: 12),
            _buildSummaryMetric(
              'Envío',
              ChileanUtils.formatCurrency(order.shippingCost),
              secondary: true,
            ),
          ],
          if (order.discountAmount > 0) ...[
            const SizedBox(height: 12),
            _buildSummaryMetric(
              'Descuento',
              ChileanUtils.formatCurrency(-order.discountAmount),
              secondary: true,
            ),
          ],
          const SizedBox(height: 18),
          Container(
            width: double.infinity,
            height: 1,
            color: _warmLine,
          ),
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Text(
                'TOTAL',
                style: TextStyle(
                  fontFamily: PublicStoreTheme.defaultBodyFont,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: PublicStoreTheme.textSecondary,
                  letterSpacing: 0.8,
                ),
              ),
              Text(
                ChileanUtils.formatCurrency(order.total),
                style: const TextStyle(
                  fontFamily: PublicStoreTheme.defaultHeadingFont,
                  fontSize: 44,
                  fontWeight: FontWeight.w700,
                  color: _logoBlue,
                  height: 0.95,
                ),
              ),
            ],
          ),
          const SizedBox(height: 26),
          if (_canRetryMercadoPago(order)) ...[
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _isRetryingPayment
                    ? null
                    : () => _retryMercadoPagoPayment(order),
                icon: _isRetryingPayment
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.payment, size: 18),
                label: Text(
                  _isRetryingPayment ? 'ABRIENDO MERCADOPAGO' : retryLabel,
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: _logoBlue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _downloadOrderPdf(order),
              icon: const Icon(Icons.download, size: 18),
              label: const Text('DESCARGAR PEDIDO'),
              style: OutlinedButton.styleFrom(
                foregroundColor: _logoBlue,
                side: const BorderSide(color: _logoBlue),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () => context.go('/productos'),
              style: OutlinedButton.styleFrom(
                foregroundColor: _logoBlue,
                side: const BorderSide(color: _logoBlue),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
              child: const Text('SEGUIR COMPRANDO'),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => context.go('/tienda'),
              style: FilledButton.styleFrom(
                backgroundColor: _logoBlue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 18),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
              child: const Text('VOLVER AL INICIO'),
            ),
          ),
          const SizedBox(height: 26),
          Container(
            width: double.infinity,
            height: 1,
            color: _warmLine,
          ),
          const SizedBox(height: 18),
          Text(
            _summaryFooterText(paymentPresentation),
            style: const TextStyle(
              fontFamily: PublicStoreTheme.defaultBodyFont,
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContentSection({
    required String title,
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: _softSurface.withValues(alpha: 0.62),
        border: const Border(
          top: BorderSide(color: _warmLine),
          bottom: BorderSide(color: _warmLine),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.toUpperCase(),
            style: const TextStyle(
              fontFamily: PublicStoreTheme.defaultHeadingFont,
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 18),
          child,
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, {bool isLast = false}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: isLast ? Colors.transparent : _warmLine,
          ),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label.toUpperCase(),
              style: const TextStyle(
                fontFamily: PublicStoreTheme.defaultBodyFont,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: PublicStoreTheme.textSecondary,
                letterSpacing: 0.7,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontFamily: PublicStoreTheme.defaultBodyFont,
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOrderItem(OnlineOrderItem item, {bool isLast = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: isLast ? Colors.transparent : _warmLine,
          ),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.productName,
                  style: const TextStyle(
                    fontFamily: PublicStoreTheme.defaultBodyFont,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                    height: 1.45,
                  ),
                ),
                if (item.productSku != null && item.productSku!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    'SKU: ${item.productSku}',
                    style: const TextStyle(
                      fontFamily: PublicStoreTheme.defaultBodyFont,
                      fontSize: 12,
                      color: PublicStoreTheme.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 16),
          Text(
            'x${item.quantity}',
            style: const TextStyle(
              fontFamily: PublicStoreTheme.defaultBodyFont,
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: PublicStoreTheme.textSecondary,
            ),
          ),
          const SizedBox(width: 16),
          Text(
            ChileanUtils.formatCurrency(item.subtotal),
            style: const TextStyle(
              fontFamily: PublicStoreTheme.defaultBodyFont,
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentInfo(
    String label,
    String value, {
    bool isLast = false,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: isLast ? Colors.transparent : _warmLine,
          ),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label.toUpperCase(),
              style: const TextStyle(
                fontFamily: PublicStoreTheme.defaultBodyFont,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: PublicStoreTheme.textSecondary,
                letterSpacing: 0.7,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontFamily: PublicStoreTheme.defaultBodyFont,
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNextStep(String text, {bool isLast = false}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: isLast ? Colors.transparent : _warmLine,
          ),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 7,
            height: 7,
            margin: const EdgeInsets.only(top: 7),
            decoration: const BoxDecoration(
              color: _logoBlue,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontFamily: PublicStoreTheme.defaultBodyFont,
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryMetric(
    String label,
    String value, {
    bool secondary = false,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontFamily: PublicStoreTheme.defaultBodyFont,
            fontSize: 15,
            color: secondary
                ? PublicStoreTheme.textSecondary
                : PublicStoreTheme.textPrimary,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontFamily: PublicStoreTheme.defaultBodyFont,
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: secondary ? PublicStoreTheme.textSecondary : Colors.black87,
          ),
        ),
      ],
    );
  }

  Widget _buildMetaPill(String label, {Color? accent}) {
    final tone = accent ?? _logoBlue;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: PublicStoreTheme.defaultBodyFont,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: tone,
          letterSpacing: 0.8,
        ),
      ),
    );
  }

  Widget _buildSectionHeading(String title) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          title.toUpperCase(),
          style: const TextStyle(
            fontFamily: PublicStoreTheme.defaultHeadingFont,
            fontSize: 32,
            fontWeight: FontWeight.w700,
            color: Colors.black,
            height: 1,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 10),
        Container(
          width: 72,
          height: 2,
          color: Colors.black,
        ),
      ],
    );
  }

  _PaymentPresentation _paymentPresentationFor(OnlineOrder order) {
    final callbackStatus = (widget.paymentStatus ?? '').trim().toLowerCase();
    final paymentStatus = order.paymentStatus.trim().toLowerCase();
    final paymentMethod = (order.paymentMethod ?? '').trim().toLowerCase();

    if (paymentStatus == 'paid' || order.paidAt != null) {
      return _PaymentPresentation.paid;
    }

    if (callbackStatus == 'failure' ||
        callbackStatus == 'rejected' ||
        paymentStatus == 'failed' ||
        paymentStatus == 'refunded') {
      return _PaymentPresentation.failed;
    }

    if (callbackStatus == 'pending' ||
        callbackStatus == 'in_process' ||
        (paymentMethod == 'mercadopago' && paymentStatus == 'pending')) {
      return _PaymentPresentation.pending;
    }

    if (paymentMethod == 'transfer') {
      return _PaymentPresentation.transferPending;
    }

    return _PaymentPresentation.orderReceived;
  }

  Color _presentationAccentColor(_PaymentPresentation paymentPresentation) {
    switch (paymentPresentation) {
      case _PaymentPresentation.paid:
      case _PaymentPresentation.orderReceived:
        return _successGreen;
      case _PaymentPresentation.failed:
        return const Color(0xFFDC2626);
      case _PaymentPresentation.pending:
        return const Color(0xFFF59E0B);
      case _PaymentPresentation.transferPending:
        return _logoBlue;
    }
  }

  IconData _presentationIcon(_PaymentPresentation paymentPresentation) {
    switch (paymentPresentation) {
      case _PaymentPresentation.paid:
      case _PaymentPresentation.orderReceived:
        return Icons.check;
      case _PaymentPresentation.failed:
        return Icons.close;
      case _PaymentPresentation.pending:
        return Icons.schedule;
      case _PaymentPresentation.transferPending:
        return Icons.account_balance;
    }
  }

  String _presentationKicker(_PaymentPresentation paymentPresentation) {
    switch (paymentPresentation) {
      case _PaymentPresentation.paid:
        return 'PAGO CONFIRMADO';
      case _PaymentPresentation.failed:
        return 'PAGO NO COMPLETADO';
      case _PaymentPresentation.pending:
        return 'PAGO EN REVISIÓN';
      case _PaymentPresentation.transferPending:
        return 'PAGO POR CONFIRMAR';
      case _PaymentPresentation.orderReceived:
        return 'PEDIDO RECIBIDO';
    }
  }

  String _presentationTitle(_PaymentPresentation paymentPresentation) {
    switch (paymentPresentation) {
      case _PaymentPresentation.paid:
        return 'Pago confirmado. Estamos preparando tu pedido.';
      case _PaymentPresentation.failed:
        return 'El pago no se completó.';
      case _PaymentPresentation.pending:
        return 'Estamos confirmando tu pago.';
      case _PaymentPresentation.transferPending:
        return 'Pedido recibido. Falta confirmar el pago.';
      case _PaymentPresentation.orderReceived:
        return 'Pedido recibido.';
    }
  }

  String _presentationSubtitle(_PaymentPresentation paymentPresentation) {
    switch (paymentPresentation) {
      case _PaymentPresentation.paid:
        return 'Recibimos tu pago y dejaremos el pedido listo para retiro o despacho.';
      case _PaymentPresentation.failed:
        return 'Tu pedido quedó guardado, pero no será preparado hasta que completes el pago. Puedes reintentar Mercado Pago desde el resumen.';
      case _PaymentPresentation.pending:
        return 'Mercado Pago todavía está revisando la operación. Evita pagar de nuevo mientras el estado siga pendiente.';
      case _PaymentPresentation.transferPending:
        return 'Realiza la transferencia con los datos indicados y envía el comprobante para que podamos preparar el pedido.';
      case _PaymentPresentation.orderReceived:
        return 'Recibimos el pedido y te avisaremos apenas el equipo lo prepare para retiro o despacho.';
    }
  }

  String? _presentationStatusLine(_PaymentPresentation paymentPresentation) {
    switch (paymentPresentation) {
      case _PaymentPresentation.failed:
        return 'El pago no se completó. Puedes intentar nuevamente.';
      case _PaymentPresentation.pending:
        return 'El pago sigue pendiente de confirmación en Mercado Pago.';
      case _PaymentPresentation.transferPending:
        return 'Esperamos el comprobante de transferencia para confirmar el pago.';
      case _PaymentPresentation.paid:
      case _PaymentPresentation.orderReceived:
        return null;
    }
  }

  String _summaryPaymentLabel(_PaymentPresentation paymentPresentation) {
    switch (paymentPresentation) {
      case _PaymentPresentation.paid:
        return 'PAGO PROCESADO';
      case _PaymentPresentation.failed:
        return 'PAGO FALLIDO';
      case _PaymentPresentation.pending:
        return 'PAGO EN REVISIÓN';
      case _PaymentPresentation.transferPending:
        return 'ESPERANDO TRANSFERENCIA';
      case _PaymentPresentation.orderReceived:
        return 'PAGO POR CONFIRMAR';
    }
  }

  String _summaryFooterText(_PaymentPresentation paymentPresentation) {
    switch (paymentPresentation) {
      case _PaymentPresentation.paid:
        return 'Guarda tu número de pedido y revisa tu correo para seguir el estado de la compra.';
      case _PaymentPresentation.failed:
        return 'Tu pedido está guardado, pero debes completar el pago para que podamos prepararlo.';
      case _PaymentPresentation.pending:
        return 'Guarda tu número de pedido. Te avisaremos cuando Mercado Pago confirme el resultado.';
      case _PaymentPresentation.transferPending:
        return 'Guarda tu número de pedido y envía el comprobante para confirmar la compra.';
      case _PaymentPresentation.orderReceived:
        return 'Guarda tu número de pedido y revisa tu correo para seguir el estado del pedido.';
    }
  }

  List<String> _nextStepsFor(_PaymentPresentation paymentPresentation) {
    switch (paymentPresentation) {
      case _PaymentPresentation.paid:
        return const [
          'Te enviaremos un email de confirmación con los detalles de tu pedido.',
          'Procesaremos tu pedido en 1-2 días hábiles.',
          'Te contactaremos si necesitamos más información.',
        ];
      case _PaymentPresentation.failed:
        return const [
          'Reintenta el pago desde el resumen del pedido.',
          'Si Mercado Pago vuelve a rechazarlo, prueba con otro medio de pago.',
          'Te podemos ayudar si nos escribes con tu número de pedido.',
        ];
      case _PaymentPresentation.pending:
        return const [
          'Mercado Pago está revisando el pago.',
          'No vuelvas a pagar mientras el estado siga pendiente.',
          'Te notificaremos apenas se confirme o si necesitamos otro medio de pago.',
        ];
      case _PaymentPresentation.transferPending:
        return const [
          'Realiza la transferencia por el total indicado.',
          'Envía el comprobante con tu número de pedido.',
          'Prepararemos el pedido cuando el pago quede confirmado.',
        ];
      case _PaymentPresentation.orderReceived:
        return const [
          'Te enviaremos un email de confirmación con los detalles de tu pedido.',
          'Procesaremos tu pedido en 1-2 días hábiles.',
          'Te contactaremos si necesitamos más información.',
        ];
    }
  }

  String _formatPaymentMethod(String paymentMethod) {
    final normalized = paymentMethod.trim().toLowerCase();
    if (normalized == ['cash', 'on', 'delivery'].join('_')) {
      return 'POR DEFINIR';
    }

    switch (normalized) {
      case 'mercadopago':
        return 'MERCADOPAGO';
      case 'transfer':
        return 'TRANSFERENCIA';
      default:
        return paymentMethod.toUpperCase();
    }
  }

  Future<void> _downloadOrderPdf(OnlineOrder order) async {
    await order_pdf.loadLibrary();
    await order_pdf.downloadOrderPdf(order);
  }
}
