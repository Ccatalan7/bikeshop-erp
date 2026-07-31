import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import 'order_confirmation_pdf.dart' deferred as order_pdf;
import '../utils/web_utils.dart' as web_utils;
import '../theme/public_store_theme.dart';
import '../providers/public_store_tenant_provider.dart';
import '../providers/cart_provider.dart';
import '../models/storefront_tax_summary.dart';
import '../models/order_confirmation_policy.dart';
import '../services/cart_store.dart';
import '../services/checkout_session_store.dart';
import '../services/meta_pixel_service.dart';
import '../widgets/public_store_layout.dart';
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
    this.callbackUriProvider,
    this.orderLoadDelay = const Duration(milliseconds: 800),
  });

  /// Injectable only so same-State query transitions are deterministic in
  /// widget tests. Production always reads a fresh [Uri.base].
  @visibleForTesting
  final Uri Function()? callbackUriProvider;

  @visibleForTesting
  final Duration orderLoadDelay;

  @visibleForTesting
  static void clearCachesForTesting() {
    _OrderConfirmationCache.processedCallbackIdentities.clear();
    _OrderConfirmationCache.callbackClaims.clear();
    _OrderConfirmationCache.callbackResults.clear();
    _OrderConfirmationCache.loadedOrders.clear();
    _OrderConfirmationCache.inFlightOrderLoads.clear();
    _OrderConfirmationCache.orderLoadGenerations.clear();
    _OrderConfirmationCache.loadErrors.clear();
    _OrderConfirmationCache.cartPreservationWarningOrderIds.clear();
  }

  @override
  State<OrderConfirmationPage> createState() => _OrderConfirmationPageState();
}

// Static cache to persist state across widget rebuilds during provider notifications
class _OrderConfirmationCache {
  static final Set<String> processedCallbackIdentities = {};
  static final Map<String, Future<_CallbackResult>> callbackClaims = {};
  static final Map<String, _CallbackResult> callbackResults = {};
  static final Map<String, OnlineOrder> loadedOrders = {};
  static final Map<String, _OrderLoadTicket> inFlightOrderLoads = {};
  static final Map<String, int> orderLoadGenerations = {};
  static final Map<String, String?> loadErrors = {};
  static final Set<String> cartPreservationWarningOrderIds = {};
}

class _OrderLoadTicket {
  const _OrderLoadTicket({
    required this.generation,
    required this.future,
  });

  final int generation;
  final Future<void> future;
}

class _CallbackObservation {
  const _CallbackObservation({
    required this.orderId,
    required this.orderAccessToken,
    required this.routeEpoch,
    required this.rawStatus,
    required this.statusGroup,
    required this.paymentId,
    required this.identity,
  });

  final String orderId;
  final String orderAccessToken;
  final int routeEpoch;
  final String? rawStatus;
  final String? statusGroup;
  final String paymentId;
  final String? identity;
}

enum _CallbackProcessingOutcome {
  completed,
  retryableFailure,
}

class _CallbackResult {
  const _CallbackResult({
    required this.outcome,
    required this.message,
  });

  final _CallbackProcessingOutcome outcome;
  final String? message;
}

enum _PaymentPresentation {
  cancelled,
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
  static const String _cartPreservationWarningText =
      'Tu pedido se completó. Revisa tu carrito: puede que aún contenga '
      'artículos comprados.';

  OnlineOrder? _order;
  bool _isLoading = true;
  bool _isRetryingPayment = false;
  bool _showCartPreservationWarning = false;
  bool _isAcknowledgingCartPreservationWarning = false;
  String? _error;
  String? _paymentMessage;
  String? _orderAccessToken;
  String? _confirmationTenantId;
  String? _lastObservedPaymentStatus;
  String? _lastObservedPaymentId;
  String? _lastObservedCallbackIdentity;
  int _routeEpoch = 0;
  int _initializationGeneration = 0;

  // Keep this page alive in memory to prevent reloading on navigation
  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    debugPrint(
        '🎉 [OrderConfirmationPage] initState() - orderId: ${widget.orderId}, status: ${widget.paymentStatus}');
    _showCartPreservationWarning = _OrderConfirmationCache
        .cartPreservationWarningOrderIds
        .contains(widget.orderId);

    _orderAccessToken = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_initializeCurrentOrderRoute());
    });
  }

  @override
  void didUpdateWidget(covariant OrderConfirmationPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.orderId != widget.orderId) {
      _orderAccessToken = null;
      _order = null;
      _paymentMessage = null;
      _confirmationTenantId = null;
      _showCartPreservationWarning = _OrderConfirmationCache
          .cartPreservationWarningOrderIds
          .contains(widget.orderId);
      _isAcknowledgingCartPreservationWarning = false;
      _error = null;
      _isLoading = true;
      _lastObservedPaymentStatus = null;
      _lastObservedPaymentId = null;
      _lastObservedCallbackIdentity = null;
      unawaited(_initializeCurrentOrderRoute());
      return;
    }
    _evaluateObservedRoute();
  }

  Future<void> _initializeCurrentOrderRoute() async {
    final generation = ++_initializationGeneration;
    final orderId = widget.orderId;
    final tenantProvider = context.read<PublicStoreTenantProvider>();
    final store = context.read<CheckoutSessionStore>();

    final tenantId = await _resolveTenantIdFrom(tenantProvider);
    if (!_ownsInitialization(orderId, generation) ||
        tenantId == null ||
        tenantId.isEmpty) {
      if (_ownsInitialization(orderId, generation)) {
        setState(() {
          _error = 'No pudimos identificar la tienda de este pedido.';
          _isLoading = false;
        });
      }
      return;
    }

    String? token;
    var showPreservationWarning = _OrderConfirmationCache
        .cartPreservationWarningOrderIds
        .contains(orderId);
    try {
      final durableAccess = await store.readOrderAccess(
        tenantId: tenantId,
        orderId: orderId,
      );
      token = durableAccess?.accessToken;
      final snapshot = await store.read(tenantId);
      if (snapshot?.receipt?.orderId == orderId) {
        final receipt = snapshot!.receipt!;
        // The protected exact-order receipt is authoritative over a stale
        // process/session cache left by an earlier route instance.
        token = receipt.accessToken;
        await store.saveOrderAccess(
          tenantId: tenantId,
          access: receipt,
        );
      }
      final cartOutcome = await store.settleCartOutcomeForPresentation(
        tenantId: tenantId,
        orderId: orderId,
      );
      if (cartOutcome != null) {
        showPreservationWarning = cartOutcome.showsWarning;
        if (showPreservationWarning) {
          _OrderConfirmationCache.cartPreservationWarningOrderIds.add(orderId);
        } else {
          _OrderConfirmationCache.cartPreservationWarningOrderIds
              .remove(orderId);
        }
      }
    } catch (error) {
      debugPrint(
        '🎉 [OrderConfirmationPage] Secure checkout recovery read failed.',
      );
      // Never hide a possible preserved outcome just because its durable
      // backend is temporarily unavailable.
      showPreservationWarning = true;
      if (token == null && _ownsInitialization(orderId, generation)) {
        setState(() {
          _confirmationTenantId = tenantId;
          _showCartPreservationWarning = true;
          _error = 'No pudimos abrir la recuperación segura de este pedido. '
              'Reinicia la aplicación e inténtalo nuevamente.';
          _isLoading = false;
        });
        return;
      }
    }

    if (!_ownsInitialization(orderId, generation)) return;
    if (token == null) {
      setState(() {
        _confirmationTenantId = tenantId;
        _showCartPreservationWarning = showPreservationWarning;
        _error =
            'Esta sesión no tiene acceso a ese pedido. Vuelve al checkout o abre el enlace seguro enviado por la tienda.';
        _isLoading = false;
      });
      return;
    }

    setState(() {
      _confirmationTenantId = tenantId;
      _orderAccessToken = token;
      _showCartPreservationWarning = showPreservationWarning;
      _error = null;
    });

    unawaited(_loadWebsiteSettingsForTenant(tenantId));
    try {
      await _finalizeTransferCheckoutSessionOnEntry(
        orderId: orderId,
        tenantId: tenantId,
        store: store,
      );
    } catch (error) {
      debugPrint(
        '🎉 [OrderConfirmationPage] Transfer checkout finalization failed.',
      );
      if (_ownsInitialization(orderId, generation)) {
        setState(() => _showCartPreservationWarning = true);
      }
    }
    if (_ownsInitialization(orderId, generation)) {
      _evaluateObservedRoute(force: true);
    }
  }

  bool _ownsInitialization(String orderId, int generation) =>
      mounted &&
      widget.orderId == orderId &&
      _initializationGeneration == generation;

  Future<void> _loadWebsiteSettingsForTenant(String tenantId) async {
    try {
      await context.read<WebsiteService>().loadSettingsForTenant(tenantId);
    } catch (e) {
      debugPrint(
          '🎉 [OrderConfirmationPage] Error loading website settings: $e');
    }
  }

  Future<String?> _resolveTenantIdFrom(
    PublicStoreTenantProvider tenantProvider, {
    Duration timeout = const Duration(seconds: 8),
  }) async {
    final startedAt = DateTime.now();

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

  Future<void> _finalizeTransferCheckoutSessionOnEntry({
    required String orderId,
    required String tenantId,
    required CheckoutSessionStore store,
  }) async {
    final snapshot = await store.read(tenantId);
    if (snapshot?.receipt?.orderId != orderId ||
        snapshot!.handoff.paymentMethod != 'transfer') {
      return;
    }

    // A transfer has no provider callback that can close the checkout later.
    // Complete (or durably preserve) the one-shot cart outcome now, then
    // retire only the receipt belonging to this confirmation route.
    await _consumeCheckoutCartIfNeeded(
      tenantId,
      orderId: orderId,
      store: store,
    );

    await store.takeTransferReceiptIfMatches(
      tenantId: tenantId,
      orderId: orderId,
      requireTerminalCartOutcome: true,
    );
  }

  _CallbackObservation _observeCallback({required int routeEpoch}) {
    final rawStatus = widget.paymentStatus?.trim().toLowerCase();
    final statusGroup = switch (rawStatus) {
      'success' || 'approved' => 'approved',
      'pending' || 'in_process' => 'pending',
      'failure' || 'failed' || 'rejected' => 'failure',
      _ => null,
    };
    final uri = widget.callbackUriProvider?.call() ?? Uri.base;
    final paymentId = (uri.queryParameters['payment_id'] ??
            uri.queryParameters['collection_id'] ??
            '')
        .trim();
    final identity = statusGroup == null
        ? null
        : '${widget.orderId}\u0000$statusGroup\u0000$paymentId';
    return _CallbackObservation(
      orderId: widget.orderId,
      orderAccessToken: _orderAccessToken!,
      routeEpoch: routeEpoch,
      rawStatus: rawStatus,
      statusGroup: statusGroup,
      paymentId: paymentId,
      identity: identity,
    );
  }

  void _evaluateObservedRoute({bool force = false}) {
    if (!mounted || _orderAccessToken == null) return;
    var observation = _observeCallback(routeEpoch: _routeEpoch);
    final changed = force ||
        observation.rawStatus != _lastObservedPaymentStatus ||
        observation.paymentId != _lastObservedPaymentId ||
        observation.identity != _lastObservedCallbackIdentity;
    if (!changed) return;

    _routeEpoch++;
    observation = _observeCallback(routeEpoch: _routeEpoch);
    _lastObservedPaymentStatus = observation.rawStatus;
    _lastObservedPaymentId = observation.paymentId;
    _lastObservedCallbackIdentity = observation.identity;

    if (observation.identity == null) {
      if (_OrderConfirmationCache.loadedOrders
              .containsKey(observation.orderId) ||
          _OrderConfirmationCache.loadErrors.containsKey(observation.orderId)) {
        _applyCachedOrderState(
          orderId: observation.orderId,
          routeEpoch: observation.routeEpoch,
          callbackIdentity: null,
        );
      } else {
        unawaited(
          _loadOrder(
            orderId: observation.orderId,
            orderAccessToken: observation.orderAccessToken,
            routeEpoch: observation.routeEpoch,
            callbackIdentity: null,
          ),
        );
      }
      return;
    }

    unawaited(_handleObservedCallback(observation));
  }

  Future<void> _handleObservedCallback(
    _CallbackObservation observation,
  ) async {
    final identity = observation.identity!;
    if (_OrderConfirmationCache.processedCallbackIdentities
        .contains(identity)) {
      await _loadOrder(
        orderId: observation.orderId,
        orderAccessToken: observation.orderAccessToken,
        routeEpoch: observation.routeEpoch,
        callbackIdentity: identity,
      );
      return;
    }

    final existingClaim = _OrderConfirmationCache.callbackClaims[identity];
    if (existingClaim != null) {
      final existingResult = await existingClaim;
      _releaseRetryableCallbackObservation(
        identity: identity,
        routeEpoch: observation.routeEpoch,
        result: existingResult,
      );
      if (mounted) {
        await _loadOrder(
          orderId: observation.orderId,
          orderAccessToken: observation.orderAccessToken,
          routeEpoch: observation.routeEpoch,
          callbackIdentity: identity,
        );
      }
      return;
    }

    // Claim synchronously before the first await. A second State observing the
    // same callback can only wait for this exact event.
    final claim = Completer<_CallbackResult>();
    _OrderConfirmationCache.callbackClaims[identity] = claim.future;
    late _CallbackResult result;
    try {
      result = await _runClaimedCallback(observation);
    } catch (error) {
      result = const _CallbackResult(
        outcome: _CallbackProcessingOutcome.retryableFailure,
        message:
            'Estamos confirmando tu pago. Si ya fue aprobado, el pedido se actualizará en unos segundos.',
      );
      _OrderConfirmationCache.callbackResults[identity] = result;
    } finally {
      _releaseRetryableCallbackObservation(
        identity: identity,
        routeEpoch: observation.routeEpoch,
        result: result,
      );
      if (identical(
        _OrderConfirmationCache.callbackClaims[identity],
        claim.future,
      )) {
        _OrderConfirmationCache.callbackClaims.remove(identity);
      }
      claim.complete(result);
    }
  }

  void _releaseRetryableCallbackObservation({
    required String identity,
    required int routeEpoch,
    required _CallbackResult result,
  }) {
    if (result.outcome == _CallbackProcessingOutcome.retryableFailure &&
        mounted &&
        routeEpoch == _routeEpoch &&
        _lastObservedCallbackIdentity == identity) {
      // A later didUpdate/re-navigation with the identical URI must be able to
      // claim the event again regardless of which pre-processing step failed.
      _lastObservedCallbackIdentity = null;
    }
  }

  Future<_CallbackResult> _runClaimedCallback(
    _CallbackObservation observation,
  ) async {
    final identity = observation.identity!;
    final websiteService = context.read<WebsiteService>();
    final orderLoadDelay = widget.orderLoadDelay;
    final callbackStatus = observation.rawStatus;
    _invalidateCachedOrder(
      observation.orderId,
      supersedeInFlightLoad: true,
    );

    late _CallbackResult result;
    try {
      result = await _processCallback(observation);
    } catch (error) {
      debugPrint(
        '🎉 [OrderConfirmationPage] Error processing callback: $error',
      );
      result = const _CallbackResult(
        outcome: _CallbackProcessingOutcome.retryableFailure,
        message:
            'Estamos confirmando tu pago. Si ya fue aprobado, el pedido se actualizará en unos segundos.',
      );
    }

    if (result.outcome == _CallbackProcessingOutcome.completed) {
      _OrderConfirmationCache.processedCallbackIdentities.add(identity);
    }
    _OrderConfirmationCache.callbackResults[identity] = result;
    // Every observed callback invalidates stale order state and owns a fresh
    // generation. A pre-existing no-status load cannot satisfy this refresh.
    await _loadOrder(
      orderId: observation.orderId,
      orderAccessToken: observation.orderAccessToken,
      routeEpoch: observation.routeEpoch,
      callbackIdentity: identity,
      forceRefresh: true,
      capturedWebsiteService: websiteService,
      capturedDelay: orderLoadDelay,
      capturedCallbackStatus: callbackStatus,
    );
    return result;
  }

  Future<_CallbackResult> _processCallback(
    _CallbackObservation observation,
  ) async {
    debugPrint(
      '🎉 [OrderConfirmationPage] Processing Mercado Pago callback: '
      'status=${observation.rawStatus}, payment=${observation.paymentId}',
    );

    switch (observation.statusGroup) {
      case 'pending':
        return const _CallbackResult(
          outcome: _CallbackProcessingOutcome.completed,
          message:
              'Tu pago está pendiente de confirmación. Te notificaremos cuando se procese.',
        );
      case 'failure':
        return const _CallbackResult(
          outcome: _CallbackProcessingOutcome.completed,
          message: 'El pago no se completó. Puedes intentar nuevamente.',
        );
      case 'approved':
        if (observation.paymentId.isEmpty) {
          return const _CallbackResult(
            outcome: _CallbackProcessingOutcome.retryableFailure,
            message:
                'MercadoPago no devolvió un identificador de pago. Revisaremos el pedido y te contactaremos si el pago se acredita.',
          );
        }

        // Capture all effect owners before the first await. A later route
        // update cannot retarget this callback to another order or token.
        final tenantProvider = context.read<PublicStoreTenantProvider>();
        final mercadopagoService = context.read<MercadoPagoService>();
        final checkoutStore = context.read<CheckoutSessionStore>();
        final cartProvider = context.read<CartProvider>();
        final tenantId = await _resolveTenantIdFrom(tenantProvider);
        if (tenantId == null || tenantId.isEmpty) {
          throw StateError(
            'No se pudo detectar la tienda para verificar el pago.',
          );
        }
        await mercadopagoService.initialize(tenantId: tenantId);

        final payment = await mercadopagoService.getPaymentStatus(
          observation.paymentId,
          orderId: observation.orderId,
          orderAccessToken: observation.orderAccessToken,
        );
        final paymentStatus =
            payment?['status']?.toString().trim().toLowerCase();
        final paymentOrderId = payment?['order_id']?.toString().trim();
        if (paymentStatus != 'approved' ||
            paymentOrderId != observation.orderId) {
          return const _CallbackResult(
            outcome: _CallbackProcessingOutcome.retryableFailure,
            message:
                'MercadoPago todavía no confirmó el pago. Te notificaremos cuando se procese.',
          );
        }

        await _consumeCheckoutCartIfNeeded(
          tenantId,
          orderId: observation.orderId,
          store: checkoutStore,
          cartProvider: cartProvider,
        );

        // Only provider verification bound to this exact order may retire its
        // Mercado Pago recovery receipt.
        await checkoutStore.clearReceiptIfMatches(
          tenantId: tenantId,
          orderId: observation.orderId,
          requireTerminalCartOutcome: true,
        );
        return const _CallbackResult(
          outcome: _CallbackProcessingOutcome.completed,
          message: '¡Pago exitoso! Tu pedido está siendo procesado.',
        );
      default:
        return const _CallbackResult(
          outcome: _CallbackProcessingOutcome.retryableFailure,
          message: null,
        );
    }
  }

  void _invalidateCachedOrder(
    String orderId, {
    bool supersedeInFlightLoad = false,
  }) {
    _OrderConfirmationCache.loadedOrders.remove(orderId);
    _OrderConfirmationCache.loadErrors.remove(orderId);
    if (supersedeInFlightLoad) {
      _OrderConfirmationCache.orderLoadGenerations[orderId] =
          (_OrderConfirmationCache.orderLoadGenerations[orderId] ?? 0) + 1;
    }
  }

  Future<void> _consumeCheckoutCartIfNeeded(
    String tenantId, {
    required String orderId,
    required CheckoutSessionStore store,
    CartProvider? cartProvider,
  }) async {
    // Capture the provider before any await so a later route transition cannot
    // make this durable effect depend on a disposed BuildContext.
    final activeCartProvider = cartProvider ?? context.read<CartProvider>();
    final outcome = await store.consumeCartOnce(
      tenantId: tenantId,
      orderId: orderId,
      consume: (snapshot) async {
        final revision = snapshot.cartRevision;
        if (revision == null || revision.isEmpty) return false;
        final orderedLines = snapshot.orderItems
            .map(
              (item) => PersistedCartLine(
                productId: item['product_id'].toString(),
                quantity: item['quantity'] as int,
              ),
            )
            .toList(growable: false);
        final result = await activeCartProvider.consumeOrderedLines(
          tenantId: tenantId,
          orderedLines: orderedLines,
          expectedRevision: revision,
        );
        return result.applied;
      },
    );
    final showWarning = outcome.showsWarning;
    if (showWarning) {
      _OrderConfirmationCache.cartPreservationWarningOrderIds.add(orderId);
    } else {
      _OrderConfirmationCache.cartPreservationWarningOrderIds.remove(orderId);
    }
    if (!mounted ||
        widget.orderId != orderId ||
        _showCartPreservationWarning == showWarning) {
      return;
    }
    setState(() => _showCartPreservationWarning = showWarning);
  }

  Future<void> _acknowledgeCartPreservationWarning() async {
    if (_isAcknowledgingCartPreservationWarning) return;
    final tenantId = _confirmationTenantId;
    final orderId = widget.orderId;
    if (tenantId == null || tenantId.isEmpty) return;

    final store = context.read<CheckoutSessionStore>();
    setState(() => _isAcknowledgingCartPreservationWarning = true);
    try {
      await store.acknowledgeCartPreservationWarning(
        tenantId: tenantId,
        orderId: orderId,
      );
      _OrderConfirmationCache.cartPreservationWarningOrderIds.remove(orderId);
      if (mounted && widget.orderId == orderId) {
        setState(() => _showCartPreservationWarning = false);
      }
    } catch (error) {
      if (mounted && widget.orderId == orderId) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No pudimos confirmar el aviso. Inténtalo nuevamente.',
            ),
          ),
        );
      }
    } finally {
      if (mounted && widget.orderId == orderId) {
        setState(() => _isAcknowledgingCartPreservationWarning = false);
      }
    }
  }

  bool _canRetryMercadoPago(OnlineOrder order) {
    final method = (order.paymentMethod ?? '').toLowerCase();
    final presentation = OrderConfirmationPolicy.resolve(
      order,
      callbackStatus: widget.paymentStatus,
    );

    return method == 'mercadopago' &&
        OrderConfirmationPolicy.allowsPaymentAction(presentation);
  }

  Future<void> _retryMercadoPagoPayment(OnlineOrder order) async {
    if (_isRetryingPayment) return;

    setState(() => _isRetryingPayment = true);

    final tenantProvider = context.read<PublicStoreTenantProvider>();
    final tenantId = tenantProvider.tenantId ?? order.tenantId;
    final mercadopagoService = context.read<MercadoPagoService>();

    try {
      final durableAccess = _orderAccessToken == null
          ? await context.read<CheckoutSessionStore>().readOrderAccess(
                tenantId: tenantId,
                orderId: widget.orderId,
              )
          : null;
      final orderAccessToken = _orderAccessToken ?? durableAccess?.accessToken;
      if (orderAccessToken == null) {
        throw Exception('La sesión segura del pedido venció.');
      }

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
        orderAccessToken: orderAccessToken,
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
        final launched = await launchUrl(
          url,
          mode: LaunchMode.externalApplication,
        );
        if (!launched) {
          throw Exception('No se pudo abrir MercadoPago.');
        }
      }
    } catch (error) {
      debugPrint('MercadoPago retry failed: $error');
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No pudimos reintentar el pago. '
            'Inténtalo nuevamente en unos minutos.',
          ),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 8),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isRetryingPayment = false);
      }
    }
  }

  Future<void> _loadOrder({
    required String orderId,
    required String orderAccessToken,
    required int routeEpoch,
    required String? callbackIdentity,
    bool forceRefresh = false,
    WebsiteService? capturedWebsiteService,
    Duration? capturedDelay,
    String? capturedCallbackStatus,
  }) async {
    if (!forceRefresh &&
        (_OrderConfirmationCache.loadedOrders.containsKey(orderId) ||
            _OrderConfirmationCache.loadErrors.containsKey(orderId))) {
      _applyCachedOrderState(
        orderId: orderId,
        routeEpoch: routeEpoch,
        callbackIdentity: callbackIdentity,
      );
      return;
    }

    var ticket = _OrderConfirmationCache.inFlightOrderLoads[orderId];
    if (forceRefresh || ticket == null) {
      WebsiteService websiteService;
      try {
        websiteService =
            capturedWebsiteService ?? context.read<WebsiteService>();
      } catch (error) {
        _OrderConfirmationCache.loadErrors[orderId] =
            'Error al cargar el pedido: $error';
        _applyCachedOrderState(
          orderId: orderId,
          routeEpoch: routeEpoch,
          callbackIdentity: callbackIdentity,
        );
        return;
      }
      ticket = _startOrderLoad(
        orderId: orderId,
        orderAccessToken: orderAccessToken,
        websiteService: websiteService,
        delay: capturedDelay ?? widget.orderLoadDelay,
        callbackStatus: capturedCallbackStatus ?? widget.paymentStatus,
      );
    }

    if (_ownsRouteEpoch(orderId, routeEpoch)) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }

    await ticket.future;
    if (!_ownsRouteEpoch(orderId, routeEpoch)) return;

    // A callback force-refresh may have superseded the ticket this State
    // originally awaited. Adopt only the newest generation.
    final latestGeneration =
        _OrderConfirmationCache.orderLoadGenerations[orderId];
    if (ticket.generation != latestGeneration) {
      final latest = _OrderConfirmationCache.inFlightOrderLoads[orderId];
      if (latest != null && latest.generation == latestGeneration) {
        await latest.future;
      }
      if (!_ownsRouteEpoch(orderId, routeEpoch)) return;
    }
    _applyCachedOrderState(
      orderId: orderId,
      routeEpoch: routeEpoch,
      callbackIdentity: callbackIdentity,
    );
  }

  _OrderLoadTicket _startOrderLoad({
    required String orderId,
    required String orderAccessToken,
    required WebsiteService websiteService,
    required Duration delay,
    required String? callbackStatus,
  }) {
    final generation =
        (_OrderConfirmationCache.orderLoadGenerations[orderId] ?? 0) + 1;
    _OrderConfirmationCache.orderLoadGenerations[orderId] = generation;

    late final _OrderLoadTicket ticket;
    final future = _performOrderLoad(
      orderId: orderId,
      generation: generation,
      orderAccessToken: orderAccessToken,
      websiteService: websiteService,
      delay: delay,
      callbackStatus: callbackStatus,
    );
    ticket = _OrderLoadTicket(
      generation: generation,
      future: future,
    );
    _OrderConfirmationCache.inFlightOrderLoads[orderId] = ticket;
    unawaited(
      future.whenComplete(() {
        if (identical(
          _OrderConfirmationCache.inFlightOrderLoads[orderId],
          ticket,
        )) {
          _OrderConfirmationCache.inFlightOrderLoads.remove(orderId);
        }
      }),
    );
    return ticket;
  }

  Future<void> _performOrderLoad({
    required String orderId,
    required int generation,
    required String orderAccessToken,
    required WebsiteService websiteService,
    required Duration delay,
    required String? callbackStatus,
  }) async {
    try {
      if (delay > Duration.zero) {
        await Future<void>.delayed(delay);
      }
      final order = await websiteService.getPublicOrderById(
        orderId: orderId,
        accessToken: orderAccessToken,
      );
      if (order == null) throw StateError('Order not found');

      if (_OrderConfirmationCache.orderLoadGenerations[orderId] != generation) {
        return;
      }
      _OrderConfirmationCache.loadedOrders[orderId] = order;
      _OrderConfirmationCache.loadErrors.remove(orderId);
      _trackPurchaseIfEligible(order, callbackStatus: callbackStatus);
    } catch (error, stackTrace) {
      debugPrint('🎉 [OrderConfirmationPage] ERROR loading order: $error');
      debugPrint(
        '🎉 [OrderConfirmationPage] Stack trace: $stackTrace',
      );
      if (_OrderConfirmationCache.orderLoadGenerations[orderId] == generation) {
        _OrderConfirmationCache.loadedOrders.remove(orderId);
        _OrderConfirmationCache.loadErrors[orderId] =
            'Error al cargar el pedido: $error';
      }
    }
  }

  bool _ownsRouteEpoch(String orderId, int routeEpoch) =>
      mounted && widget.orderId == orderId && _routeEpoch == routeEpoch;

  void _applyCachedOrderState({
    required String orderId,
    required int routeEpoch,
    required String? callbackIdentity,
  }) {
    if (!_ownsRouteEpoch(orderId, routeEpoch)) return;
    setState(() {
      _order = _OrderConfirmationCache.loadedOrders[orderId];
      _paymentMessage = callbackIdentity == null
          ? null
          : _OrderConfirmationCache.callbackResults[callbackIdentity]?.message;
      _error = _OrderConfirmationCache.loadErrors[orderId];
      _isLoading = false;
    });
  }

  void _trackPurchaseIfEligible(
    OnlineOrder order, {
    required String? callbackStatus,
  }) {
    final paymentFailed = const {'failure', 'failed', 'rejected'}.contains(
      callbackStatus?.toLowerCase(),
    );
    if (order.status.toLowerCase() == 'cancelled' ||
        order.paymentStatus.toLowerCase() == 'failed' ||
        paymentFailed) {
      return;
    }

    final metaItems = order.items
        .map(
          (item) => MetaCatalogEventItem(
            contentId: MetaPixelService.catalogContentId(
              sku: item.productSku ?? item.liveProductSku,
              productId: item.productId,
            ),
            quantity: item.quantity,
            itemPrice: item.unitPrice,
          ),
        )
        .where((item) => item.contentId.isNotEmpty)
        .toList();
    MetaPixelService.instance.trackPurchase(
      orderId: order.id,
      items: metaItems,
      value: order.total,
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin

    // Return just the content - PublicStoreLayout handles Scaffold and scrolling
    late final Widget content;
    if (_isLoading) {
      content = const Center(child: BrandedLoading());
    } else if (_error != null) {
      content = _buildError();
    } else if (_order == null) {
      content = _buildNotFound();
    } else {
      content = _buildConfirmation();
    }

    if (!_showCartPreservationWarning) return content;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildCartPreservationWarning(),
        content,
      ],
    );
  }

  Widget _buildCartPreservationWarning() {
    return Container(
      key: const ValueKey('checkout-cart-preservation-warning'),
      width: double.infinity,
      constraints: const BoxConstraints(maxWidth: 1320),
      margin: const EdgeInsets.fromLTRB(16, 20, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7ED),
        border: Border.all(color: const Color(0xFFF59E0B)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.info_outline,
            color: Color(0xFF92400E),
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  _cartPreservationWarningText,
                  style: TextStyle(
                    color: Color(0xFF78350F),
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF78350F),
                        side: const BorderSide(color: Color(0xFFB45309)),
                        minimumSize: const Size(0, 48),
                      ),
                      onPressed: () => PublicStoreLayout.navigateToHref(
                        context,
                        '/tienda/carrito',
                      ),
                      child: const Text('VER CARRITO'),
                    ),
                    TextButton(
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFF78350F),
                        minimumSize: const Size(0, 48),
                      ),
                      onPressed: _isAcknowledgingCartPreservationWarning
                          ? null
                          : _acknowledgeCartPreservationWarning,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_isAcknowledgingCartPreservationWarning) ...[
                            const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            const SizedBox(width: 8),
                          ],
                          const Text('ENTENDIDO'),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildError() {
    return _buildStateView(
      icon: Icons.error_outline,
      title: 'No pudimos cargar tu pedido',
      message: _error ?? 'Error desconocido',
      actionLabel: 'VOLVER AL INICIO',
      onPressed: () => PublicStoreLayout.navigateToHref(context, '/tienda'),
      accentColor: const Color(0xFFB91C1C),
    );
  }

  Widget _buildNotFound() {
    return _buildStateView(
      icon: Icons.shopping_bag_outlined,
      title: 'Pedido no encontrado',
      message: 'No pudimos encontrar este pedido.',
      actionLabel: 'VOLVER AL INICIO',
      onPressed: () => PublicStoreLayout.navigateToHref(context, '/tienda'),
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

        // PublicStoreLayout owns the single scroll viewport for checkout and
        // order routes. A second viewport here receives an unbounded height
        // from that outer scrollable and can leave this subtree unlaid out on
        // Flutter Web after the order finishes loading.
        return Center(
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
                  if (paymentPresentation ==
                      _PaymentPresentation.transferPending) ...[
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
                            if (paymentPresentation ==
                                _PaymentPresentation.transferPending) ...[
                              const SizedBox(height: 24),
                              _buildTransferSection(
                                order,
                                hasTransferDestination: hasTransferDestination,
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

        // Scrolling is deliberately delegated to PublicStoreLayout; this
        // state must remain a regular box inside its inline route column.
        return Center(
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
                        fontFamily: null,
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
        final statusLine = paymentPresentation == _PaymentPresentation.cancelled
            ? _presentationStatusLine(paymentPresentation)
            : _paymentMessage ?? _presentationStatusLine(paymentPresentation);

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
                    fontFamily: null,
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
                fontFamily: null,
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
                fontFamily: null,
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
                order.storefrontIdentity.displayName.toUpperCase(),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: null,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: Colors.white.withValues(alpha: 0.68),
                  letterSpacing: 1.1,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'PEDIDO',
                style: TextStyle(
                  fontFamily: null,
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
                  fontFamily: null,
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
            fontFamily: null,
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
              fontFamily: null,
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
            paymentPresentation == _PaymentPresentation.cancelled
                ? Icons.block_outlined
                : paymentPresentation == _PaymentPresentation.failed
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
                fontFamily: null,
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
      if (order.customerName.trim().isNotEmpty)
        MapEntry('Nombre', order.customerName),
      if (order.customerEmail.trim().isNotEmpty)
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
              fontFamily: null,
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
                fontFamily: null,
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
                fontFamily: null,
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
    final taxSummary = StorefrontTaxSummary.calculate(
      order.items.map(
        (item) => StorefrontTaxLineInput(
          label: item.productName,
          grossUnitPrice: item.unitPrice,
          quantity: item.quantity,
          taxRate: item.taxRate,
        ),
      ),
    );
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
              fontFamily: null,
              fontSize: 32,
              fontWeight: FontWeight.w700,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            order.orderNumber,
            style: const TextStyle(
              fontFamily: null,
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
            taxSummary.isValid ? taxSummary.netLabel : 'Neto',
            ChileanUtils.formatCurrency(order.subtotal),
          ),
          if (order.taxAmount > 0 || taxSummary.isValid) ...[
            const SizedBox(height: 12),
            _buildSummaryMetric(
              taxSummary.isValid ? taxSummary.ivaLabel : 'IVA incluido',
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
                  fontFamily: null,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: PublicStoreTheme.textSecondary,
                  letterSpacing: 0.8,
                ),
              ),
              Text(
                ChileanUtils.formatCurrency(order.total),
                style: const TextStyle(
                  fontFamily: null,
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
              label: const Text('DESCARGAR RESUMEN DEL PEDIDO'),
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
          const SizedBox(height: 6),
          Text(
            'Documento informativo: no acredita pago ni reemplaza una boleta o voucher oficial.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () =>
                  PublicStoreLayout.navigateToHref(context, '/productos'),
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
              onPressed: () =>
                  PublicStoreLayout.navigateToHref(context, '/tienda'),
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
              fontFamily: null,
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
              fontFamily: null,
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
                fontFamily: null,
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
                fontFamily: null,
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
                    fontFamily: null,
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
                      fontFamily: null,
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
              fontFamily: null,
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: PublicStoreTheme.textSecondary,
            ),
          ),
          const SizedBox(width: 16),
          Text(
            ChileanUtils.formatCurrency(item.subtotal),
            style: const TextStyle(
              fontFamily: null,
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
                fontFamily: null,
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
                fontFamily: null,
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
                fontFamily: null,
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
            fontFamily: null,
            fontSize: 15,
            color: secondary
                ? PublicStoreTheme.textSecondary
                : PublicStoreTheme.textPrimary,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontFamily: null,
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
          fontFamily: null,
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
            fontFamily: null,
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
    return switch (OrderConfirmationPolicy.resolve(
      order,
      callbackStatus: widget.paymentStatus,
    )) {
      OrderConfirmationState.cancelled => _PaymentPresentation.cancelled,
      OrderConfirmationState.paid => _PaymentPresentation.paid,
      OrderConfirmationState.failed => _PaymentPresentation.failed,
      OrderConfirmationState.pending => _PaymentPresentation.pending,
      OrderConfirmationState.transferPending =>
        _PaymentPresentation.transferPending,
      OrderConfirmationState.orderReceived =>
        _PaymentPresentation.orderReceived,
    };
  }

  Color _presentationAccentColor(_PaymentPresentation paymentPresentation) {
    switch (paymentPresentation) {
      case _PaymentPresentation.cancelled:
        return const Color(0xFFB45309);
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
      case _PaymentPresentation.cancelled:
        return Icons.block;
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
      case _PaymentPresentation.cancelled:
        return 'PEDIDO CANCELADO';
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
      case _PaymentPresentation.cancelled:
        return 'Este pedido fue cancelado.';
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
      case _PaymentPresentation.cancelled:
        return 'No realices ni reintentes un pago para este pedido. Los montos quedan visibles solo como registro de lo solicitado.';
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
      case _PaymentPresentation.cancelled:
        return 'El pedido está cerrado. No se preparará ni debe pagarse.';
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
      case _PaymentPresentation.cancelled:
        return 'PEDIDO CANCELADO';
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
      case _PaymentPresentation.cancelled:
        return 'Este pedido está cerrado. Conserva el número solo como referencia y no realices un pago.';
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
      case _PaymentPresentation.cancelled:
        return const [
          'No realices ni reintentes el pago de este pedido.',
          'Si ya habías pagado, contáctanos con el número de pedido para revisar el estado del reembolso.',
          'Si todavía quieres los productos, inicia un pedido nuevo.',
        ];
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
