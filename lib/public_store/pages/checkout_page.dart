import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_typeahead/flutter_typeahead.dart' as typeahead;
import 'package:uuid/uuid.dart';
import '../utils/web_utils.dart' as web_utils;
import '../theme/public_store_surface_theme.dart';
import '../models/checkout_submission_session.dart';
import '../models/public_commerce_product_projection.dart';
import '../models/public_checkout_capabilities.dart';
import '../../modules/website/models/public_order_access.dart';
import '../providers/cart_provider.dart';
import '../providers/public_store_tenant_provider.dart';
import '../services/customer_account_service.dart';
import '../services/address_autocomplete_service.dart';
import '../services/checkout_exit_guard.dart';
import '../services/checkout_session_store.dart';
import '../services/cart_store.dart';
import '../services/meta_pixel_service.dart';
import '../services/public_checkout_capability_service.dart';
import '../widgets/public_store_layout.dart';
import '../../modules/website/services/website_service.dart';
import '../../modules/website/services/mercadopago_service.dart';
import '../../modules/website/models/public_shipping_quote.dart';
import '../../shared/utils/chilean_utils.dart';
import '../../shared/utils/auth_input_validation.dart';
import '../../shared/models/customer_address.dart';
import '../../shared/widgets/safe_layout_builder.dart';

void _checkoutDebugLog(String message) {
  if (kDebugMode || const bool.fromEnvironment('STORE_PERF_LOGS')) {
    debugPrint(message);
  }
}

class _CreatedOrderContext {
  const _CreatedOrderContext({
    required this.tenantId,
    required this.paymentMethod,
    required this.isPickup,
    required this.resolvedAddress,
    required this.customerId,
    required this.shouldSaveAddress,
  });

  final String tenantId;
  final String paymentMethod;
  final bool isPickup;
  final ResolvedAddress? resolvedAddress;
  final String? customerId;
  final bool shouldSaveAddress;
}

class CheckoutPage extends StatefulWidget {
  const CheckoutPage({
    super.key,
    this.capabilityLoader,
  });

  final PublicCheckoutCapabilityLoader? capabilityLoader;

  @override
  State<CheckoutPage> createState() => _CheckoutPageState();
}

class _CheckoutPageState extends State<CheckoutPage>
    with AutomaticKeepAliveClientMixin {
  static final RegExp _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  PublicStoreSurfaceTheme get _storeTheme =>
      PublicStoreSurfaceTheme.of(context);

  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController();
  final _streetController = TextEditingController();
  final _streetNumberController = TextEditingController();
  final _apartmentController = TextEditingController();
  final _comunaController = TextEditingController();
  final _cityController = TextEditingController();
  final _regionController = TextEditingController();
  final _postalCodeController = TextEditingController();
  final _notesController = TextEditingController();
  final _accountPasswordController = TextEditingController();
  final _accountPasswordConfirmController = TextEditingController();

  String _deliveryType = 'shipping'; // shipping, pickup
  String _paymentMethod = '';
  PublicCheckoutCapabilities? _paymentCapabilities;
  String? _paymentCapabilitiesTenantId;
  String? _paymentCapabilitiesRequestedTenantId;
  String? _paymentCapabilitiesError;
  bool _paymentCapabilitiesLoading = true;
  int _paymentCapabilitiesGeneration = 0;
  bool _isProcessing = false;
  CustomerAccountService? _accountService;
  AddressAutocompleteService? _addressAutocompleteService;
  List<CustomerAddress> _savedAddresses = [];
  CustomerAddress? _selectedAddress;
  ResolvedAddress? _resolvedAddress;
  final TextEditingController _addressLabelController =
      TextEditingController(text: 'Dirección de entrega');
  bool _saveAddressToAccount = true;
  bool _createAccountAfterCheckout = false;
  bool _obscureAccountPassword = true;
  PublicShippingQuote? _shippingQuote;
  bool _shippingQuoteLoading = false;
  String? _shippingQuoteError;
  String? _shippingQuoteSignature;
  String? _shippingQuoteAttemptedSignature;
  int _shippingQuoteGeneration = 0;
  CheckoutSubmissionSession _submission = CheckoutSubmissionSession(
    idempotencyKey: const Uuid().v4(),
  );
  CheckoutSessionStore? _sessionStore;
  CheckoutSessionSnapshot? _durableSnapshot;
  CheckoutExitLease? _exitLease;
  final Object _exitLeaseOwner = Object();
  bool _sessionRestoring = true;
  bool _sessionStorageUnavailable = false;
  bool _isRestoredCheckoutSession = false;
  _CreatedOrderContext? _createdOrderContext;
  bool _postOrderAccountAttempted = false;
  bool _postOrderAddressAttempted = false;
  String? _outcomeUnknownMessage;
  String? _postOrderRecoveryMessage;

  bool get _checkoutLocked =>
      (_exitLease?.isCurrent ?? false) || _submission.hasStarted;

  // Keep this page alive in memory to prevent reloading on navigation
  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      final accountService = context.read<CustomerAccountService>();
      _accountService = accountService;
      accountService.addListener(_onAccountServiceChanged);
      _prefillFromAccount(force: true);

      final autocompleteService = context.read<AddressAutocompleteService>();
      _addressAutocompleteService = autocompleteService;
      autocompleteService.addListener(_onAutocompleteChanged);
      final tenantId = context.read<PublicStoreTenantProvider>().tenantId;
      autocompleteService.initialize(tenantId: tenantId);
      unawaited(_restoreDurableCheckoutSession(tenantId));
      unawaited(_loadPaymentCapabilities(tenantId));

      final cart = context.read<CartProvider>();
      final checkoutTotal = cart.total;
      if (checkoutTotal != null) {
        MetaPixelService.instance.trackInitiateCheckout(
          items: cart.items
              .map(
                (item) {
                  final commerce = item.commerce;
                  return MetaCatalogEventItem(
                    contentId: MetaPixelService.catalogContentId(
                      sku: commerce.sku,
                      productId: commerce.id,
                    ),
                    quantity: item.quantity,
                    itemPrice: commerce.price,
                  );
                },
              )
              .where((item) => item.contentId.isNotEmpty)
              .toList(),
          value: checkoutTotal,
        );
      }

      _handleCheckoutQueryParameters();
    });
  }

  Future<PublicCheckoutCapabilities?> _loadPaymentCapabilities(
    String? tenantId, {
    bool force = false,
    bool preserveSelection = false,
  }) async {
    final normalizedTenantId = tenantId?.trim() ?? '';
    if (normalizedTenantId.isEmpty) {
      if (mounted) {
        setState(() {
          _paymentCapabilities = null;
          _paymentCapabilitiesTenantId = null;
          _paymentCapabilitiesRequestedTenantId = normalizedTenantId;
          _paymentCapabilitiesLoading = false;
          _paymentCapabilitiesError =
              'No pudimos identificar la tienda para consultar sus medios de pago.';
          if (!_submission.hasStarted) _paymentMethod = '';
        });
      }
      return null;
    }
    if (!force &&
        _paymentCapabilitiesTenantId == normalizedTenantId &&
        _paymentCapabilities != null) {
      return _paymentCapabilities;
    }
    if (!force &&
        _paymentCapabilitiesRequestedTenantId == normalizedTenantId &&
        _paymentCapabilitiesLoading) {
      return null;
    }

    final generation = ++_paymentCapabilitiesGeneration;
    _paymentCapabilitiesRequestedTenantId = normalizedTenantId;
    if (mounted) {
      setState(() {
        _paymentCapabilitiesLoading = true;
        _paymentCapabilitiesError = null;
      });
    }

    try {
      final loader = widget.capabilityLoader ??
          const PublicCheckoutCapabilityService().load;
      final capabilities = await loader(normalizedTenantId);
      if (!mounted || generation != _paymentCapabilitiesGeneration) {
        return null;
      }

      final selectionStillAvailable = capabilities.isAvailable(_paymentMethod);
      setState(() {
        _paymentCapabilities = capabilities;
        _paymentCapabilitiesTenantId = normalizedTenantId;
        _paymentCapabilitiesLoading = false;
        _paymentCapabilitiesError = null;
        if (!_submission.hasStarted &&
            !selectionStillAvailable &&
            !preserveSelection) {
          final methods = capabilities.availableMethods;
          _paymentMethod = methods.isEmpty ? '' : methods.first.wireValue;
        }
      });
      return capabilities;
    } catch (error) {
      debugPrint('Checkout payment capability load failed: $error');
      if (!mounted || generation != _paymentCapabilitiesGeneration) {
        return null;
      }
      setState(() {
        _paymentCapabilities = null;
        _paymentCapabilitiesTenantId = null;
        _paymentCapabilitiesLoading = false;
        _paymentCapabilitiesError =
            'No pudimos verificar los medios de pago disponibles. Reintenta antes de crear el pedido.';
        if (!_submission.hasStarted) _paymentMethod = '';
      });
      return null;
    }
  }

  void _schedulePaymentCapabilityRefresh(String? tenantId) {
    final normalizedTenantId = tenantId?.trim() ?? '';
    if (_paymentCapabilitiesRequestedTenantId == normalizedTenantId) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_loadPaymentCapabilities(normalizedTenantId));
    });
  }

  @override
  void dispose() {
    _exitLease?.release();
    _accountService?.removeListener(_onAccountServiceChanged);
    _addressAutocompleteService?.removeListener(_onAutocompleteChanged);
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _streetController.dispose();
    _streetNumberController.dispose();
    _apartmentController.dispose();
    _comunaController.dispose();
    _cityController.dispose();
    _regionController.dispose();
    _postalCodeController.dispose();
    _notesController.dispose();
    _addressLabelController.dispose();
    _accountPasswordController.dispose();
    _accountPasswordConfirmController.dispose();
    super.dispose();
  }

  Future<void> _restoreDurableCheckoutSession(String? tenantId) async {
    final normalizedTenantId = tenantId?.trim() ?? '';
    if (normalizedTenantId.isEmpty) {
      if (mounted) setState(() => _sessionRestoring = false);
      return;
    }

    final store = _sessionStore ??= context.read<CheckoutSessionStore>();
    final CheckoutSessionSnapshot? snapshot;
    try {
      snapshot = await store.read(normalizedTenantId);
    } catch (error) {
      debugPrint('Checkout durable session read failed.');
      if (!mounted) return;
      setState(() {
        _sessionRestoring = false;
        _sessionStorageUnavailable = true;
        _outcomeUnknownMessage =
            'No pudimos revisar la recuperación segura de este checkout. '
            'Por protección, no enviaremos un pedido nuevo mientras el '
            'almacenamiento no esté disponible. Recarga la aplicación e '
            'inténtalo nuevamente.';
        _postOrderRecoveryMessage = null;
      });
      return;
    }
    if (!mounted) return;
    if (snapshot == null) {
      setState(() {
        _sessionRestoring = false;
        _sessionStorageUnavailable = false;
      });
      return;
    }
    final restoredSnapshot = snapshot;

    final websiteService = context.read<WebsiteService>();
    final restoredSubmission = restoredSnapshot.receipt == null
        ? CheckoutSubmissionSession.restorePending(
            idempotencyKey: restoredSnapshot.idempotencyKey,
            creator: (idempotencyKey) {
              if (idempotencyKey != restoredSnapshot.idempotencyKey) {
                throw StateError(
                  'La recuperación no corresponde al intento guardado.',
                );
              }
              // These are the exact payload values persisted before the first
              // RPC. Never rebuild them from the current form or cart.
              return websiteService.createOrder(
                restoredSnapshot.orderData,
                restoredSnapshot.orderItems,
              );
            },
          )
        : CheckoutSubmissionSession.restoreReceipt(
            idempotencyKey: restoredSnapshot.idempotencyKey,
            receipt: restoredSnapshot.receipt!,
          );

    final restoredContext = _CreatedOrderContext(
      tenantId: normalizedTenantId,
      paymentMethod: restoredSnapshot.handoff.paymentMethod,
      isPickup: restoredSnapshot.handoff.deliveryType == 'pickup',
      resolvedAddress: null,
      customerId: null,
      shouldSaveAddress: false,
    );
    final lease = context.read<CheckoutExitGuard>().acquire(
          owner: _exitLeaseOwner,
          phase: restoredSnapshot.receipt == null
              ? CheckoutExitPhase.recoveringOrder
              : CheckoutExitPhase.orderCreated,
        );

    final receipt = restoredSnapshot.receipt;
    if (receipt != null) {
      try {
        await store.saveOrderAccess(
          tenantId: normalizedTenantId,
          access: receipt,
        );
      } catch (error) {
        lease.release();
        if (!mounted) return;
        setState(() {
          _sessionRestoring = false;
          _sessionStorageUnavailable = true;
          _outcomeUnknownMessage =
              'Recuperamos tu pedido, pero no pudimos verificar su acceso '
              'seguro en este dispositivo. Reinicia la aplicación e inténtalo '
              'nuevamente.';
        });
        return;
      }
    }

    setState(() {
      _submission = restoredSubmission;
      _durableSnapshot = restoredSnapshot;
      _exitLease = lease;
      _isRestoredCheckoutSession = true;
      _createdOrderContext = restoredContext;
      _deliveryType = restoredSnapshot.handoff.deliveryType;
      _paymentMethod = restoredSnapshot.handoff.paymentMethod;
      _postOrderAccountAttempted = true;
      _postOrderAddressAttempted = true;
      _sessionRestoring = false;
      _sessionStorageUnavailable = false;
      if (receipt == null) {
        _outcomeUnknownMessage =
            'Recuperamos el intento seguro de esta sesión. Reintenta la '
            'confirmación para consultar el mismo pedido, sin reconstruir sus '
            'datos. Por seguridad no repetiremos tareas opcionales de cuenta '
            'o dirección.';
        _postOrderRecoveryMessage = null;
      } else {
        _outcomeUnknownMessage = null;
        _postOrderRecoveryMessage =
            'Recuperamos el pedido ya creado en esta sesión. Continúa para '
            'retomar el pago o la confirmación sin crear otro. Por seguridad '
            'no repetiremos tareas opcionales de cuenta o dirección.';
      }
    });
  }

  void _onAccountServiceChanged() {
    if (!mounted) return;
    _prefillFromAccount();
  }

  void _onAutocompleteChanged() {
    if (!mounted) return;
    setState(() {});
  }

  int? _wholeClpCartTotal(CartProvider cart) {
    final value = cart.total;
    if (value == null) return null;
    if (!value.isFinite || value < 0) return null;
    final rounded = value.round();
    return (value - rounded).abs() <= 0.000001 ? rounded : null;
  }

  String? _shippingSignature(CartProvider cart) {
    final tenantId = context.read<PublicStoreTenantProvider>().tenantId;
    final itemGross = _wholeClpCartTotal(cart);
    if (tenantId == null || tenantId.isEmpty || itemGross == null) return null;
    return '$tenantId|$_deliveryType|$itemGross';
  }

  bool _hasCurrentShippingQuote(CartProvider cart) {
    final signature = _shippingSignature(cart);
    final quote = _shippingQuote;
    return signature != null &&
        signature == _shippingQuoteSignature &&
        quote != null &&
        quote.deliveryType == _deliveryType &&
        quote.itemGross == _wholeClpCartTotal(cart);
  }

  void _scheduleShippingQuoteRefresh(CartProvider cart) {
    final signature = _shippingSignature(cart);
    if (signature == null ||
        signature == _shippingQuoteSignature ||
        signature == _shippingQuoteAttemptedSignature) {
      return;
    }
    _shippingQuoteAttemptedSignature = signature;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          _shippingSignature(context.read<CartProvider>()) != signature) {
        return;
      }
      _loadShippingQuote();
    });
  }

  Future<PublicShippingQuote?> _loadShippingQuote({bool force = false}) async {
    final cart = context.read<CartProvider>();
    final tenantId = context.read<PublicStoreTenantProvider>().tenantId;
    final itemGross = _wholeClpCartTotal(cart);
    if (tenantId == null || tenantId.isEmpty || itemGross == null) {
      if (mounted) {
        setState(() {
          _shippingQuoteLoading = false;
          _shippingQuoteError = itemGross == null
              ? 'El carrito contiene un monto que no puede expresarse en pesos completos.'
              : 'No pudimos identificar la tienda para calcular el despacho.';
        });
      }
      return null;
    }

    final deliveryType = _deliveryType;
    final signature = '$tenantId|$deliveryType|$itemGross';
    if (!force &&
        _shippingQuoteSignature == signature &&
        _shippingQuote != null) {
      return _shippingQuote;
    }

    final generation = ++_shippingQuoteGeneration;
    _shippingQuoteAttemptedSignature = signature;
    if (mounted) {
      setState(() {
        _shippingQuoteLoading = true;
        _shippingQuoteError = null;
      });
    }

    try {
      final quote = await context.read<WebsiteService>().quotePublicShipping(
            tenantId: tenantId,
            deliveryType: deliveryType,
            itemGross: itemGross,
          );
      if (quote.deliveryType != deliveryType || quote.itemGross != itemGross) {
        throw const FormatException(
          'La cotización recibida no corresponde al carrito actual.',
        );
      }
      if (!mounted ||
          generation != _shippingQuoteGeneration ||
          _shippingSignature(context.read<CartProvider>()) != signature) {
        return null;
      }
      setState(() {
        _shippingQuote = quote;
        _shippingQuoteSignature = signature;
        _shippingQuoteLoading = false;
        _shippingQuoteError = null;
      });
      return quote;
    } catch (error) {
      if (!mounted || generation != _shippingQuoteGeneration) return null;
      debugPrint('Checkout shipping quote failed: $error');
      setState(() {
        _shippingQuote = null;
        _shippingQuoteSignature = null;
        _shippingQuoteLoading = false;
        _shippingQuoteError =
            'No pudimos calcular el despacho. Reintenta antes de pagar.';
      });
      return null;
    }
  }

  void _selectDeliveryType(String value) {
    if (_checkoutLocked) return;
    if (value == _deliveryType) return;
    setState(() {
      _deliveryType = value;
      _shippingQuote = null;
      _shippingQuoteSignature = null;
      _shippingQuoteError = null;
    });
  }

  void _prefillFromAccount({bool force = false}) {
    final service = _accountService;
    if (service == null) return;

    final profile = service.customerProfile;

    if (profile != null) {
      final name = (profile['name'] ?? '').toString();
      if ((_nameController.text.isEmpty || force) && name.isNotEmpty) {
        _nameController.text = name;
      }

      final email = (profile['email'] ?? '').toString();
      if ((_emailController.text.isEmpty || force) && email.isNotEmpty) {
        _emailController.text = email;
      }

      final phone = profile['phone']?.toString();
      if ((_phoneController.text.isEmpty || force) &&
          phone != null &&
          phone.isNotEmpty) {
        _phoneController.text = phone;
      }
    }

    final addresses = service.addresses;
    setState(() {
      _savedAddresses = List<CustomerAddress>.from(addresses);
    });

    final defaultAddress = service.defaultAddress;
    if (defaultAddress != null &&
        (_selectedAddress == null ||
            _selectedAddress!.id != defaultAddress.id ||
            force)) {
      _applyAddressFromCustomer(defaultAddress);
    }
  }

  void _applyAddressFromCustomer(CustomerAddress address) {
    final resolved = ResolvedAddress(
      formattedAddress: address.fullAddress,
      street: address.streetAddress,
      streetNumber: address.streetNumber,
      apartment: address.apartment,
      comuna: address.comuna,
      city: address.city,
      region: address.region,
      postalCode: address.postalCode,
    );

    setState(() {
      _selectedAddress = address;
      _resolvedAddress = resolved;
      _addressController.text = resolved.formatForDisplay();
      _addressLabelController.text = address.label;
      _saveAddressToAccount = false;
    });
    _fillAddressFields(resolved);

    if (_nameController.text.isEmpty) {
      _nameController.text = address.recipientName;
    }

    if (_phoneController.text.isEmpty) {
      _phoneController.text = address.phone;
    }
  }

  void _applyResolvedAddress(
    ResolvedAddress resolved, {
    required String selectedLabel,
  }) {
    setState(() {
      _selectedAddress = null;
      _resolvedAddress = resolved;
      _addressController.text = selectedLabel.trim().isNotEmpty
          ? selectedLabel.trim()
          : resolved.formatForDisplay();
      if (_addressLabelController.text.trim().isEmpty ||
          _addressLabelController.text == 'Dirección de entrega') {
        final locationLabel = resolved.comuna.isNotEmpty
            ? resolved.comuna
            : resolved.city.isNotEmpty
                ? resolved.city
                : 'Entrega';
        _addressLabelController.text = 'Dirección $locationLabel';
      }
      _saveAddressToAccount = _accountService?.isAuthenticated ?? false;
    });
    _fillAddressFields(resolved);
  }

  void _fillAddressFields(ResolvedAddress resolved) {
    final city = _normalizeAddressCity(
      city: resolved.city,
      comuna: resolved.comuna,
      region: resolved.region,
    );

    _streetController.text = resolved.street;
    _streetNumberController.text = resolved.streetNumber ?? '';
    _apartmentController.text = resolved.apartment ?? '';
    _comunaController.text = resolved.comuna;
    _cityController.text = city;
    _regionController.text = resolved.region;
    _postalCodeController.text = resolved.postalCode ?? '';
  }

  String _normalizeAddressCity({
    required String city,
    required String comuna,
    required String region,
  }) {
    final cleanCity = city.trim();
    final cleanComuna = comuna.trim();
    final cleanRegion = region.trim();

    if (cleanComuna.isEmpty) return cleanCity;
    if (cleanCity.isEmpty) return cleanComuna;
    if (cleanCity.toLowerCase() == cleanRegion.toLowerCase()) {
      return cleanComuna;
    }
    return cleanCity;
  }

  void _handleCheckoutQueryParameters() {
    final params = Uri.base.queryParameters;
    final status = params['status'];
    final orderId = params['pedido'] ?? params['order'];

    if (status == null) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      if (status == 'failure') {
        final message = orderId != null
            ? 'El pago del pedido $orderId fue cancelado. Puedes intentarlo nuevamente.'
            : 'El pago no se completó. Inténtalo nuevamente.';

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: _storeTheme.error,
          ),
        );
      } else if (status == 'pending' && orderId != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'El pago del pedido $orderId está pendiente. Te avisaremos cuando se confirme.'),
          ),
        );
      }
    });

    if (kIsWeb && status.isNotEmpty) {
      final cleaned = Uri.base.removeFragment().replace(queryParameters: {});
      web_utils.WebUtils.replaceHistoryState(cleaned.toString());
    }
  }

  Future<void> _saveAddressForCustomer(
    CustomerAccountService accountService,
    ResolvedAddress resolved,
    String customerId,
  ) async {
    final label = _addressLabelController.text.trim().isNotEmpty
        ? _addressLabelController.text.trim()
        : 'Dirección ${resolved.comuna.isNotEmpty ? resolved.comuna : 'de entrega'}';

    final newAddress = CustomerAddress(
      id: '',
      customerId: customerId,
      label: label,
      recipientName: _nameController.text.trim(),
      phone: _phoneController.text.trim(),
      streetAddress: resolved.street,
      streetNumber: resolved.streetNumber,
      apartment: resolved.apartment,
      comuna: resolved.comuna,
      city: resolved.city,
      region: resolved.region,
      postalCode: resolved.postalCode,
      additionalInfo: null,
      isDefault: accountService.addresses.isEmpty,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    final alreadyExists = accountService.addresses.any(
      (address) =>
          address.fullAddress.toLowerCase() ==
          newAddress.fullAddress.toLowerCase(),
    );

    if (!alreadyExists) {
      await accountService.addAddress(newAddress);
      if (mounted) {
        setState(() {
          _saveAddressToAccount = false;
        });
      }
    }
  }

  ResolvedAddress _shippingAddressForOrder() {
    final searchText = _addressController.text.trim();
    final street = _streetController.text.trim();
    final streetNumber = _streetNumberController.text.trim();
    final apartment = _apartmentController.text.trim();
    final comuna = _comunaController.text.trim();
    final city = _cityController.text.trim();
    final region = _regionController.text.trim();
    final postalCode = _postalCodeController.text.trim();

    return ResolvedAddress(
      formattedAddress: searchText.isNotEmpty
          ? searchText
          : _formatAddressForDisplay(
              street: street,
              streetNumber: streetNumber,
              apartment: apartment,
              comuna: comuna,
              city: city,
              region: region,
            ),
      street: street.isNotEmpty ? street : searchText,
      streetNumber: streetNumber.isNotEmpty ? streetNumber : null,
      apartment: apartment.isNotEmpty ? apartment : null,
      comuna: comuna.isNotEmpty ? comuna : city,
      city: city.isNotEmpty ? city : comuna,
      region: region,
      postalCode: postalCode.isNotEmpty ? postalCode : null,
      latitude: _resolvedAddress?.latitude,
      longitude: _resolvedAddress?.longitude,
    );
  }

  String _pickupPointLabel(WebsiteService websiteService) {
    final storeName = websiteService.getSetting('store_name', 'la tienda');
    final address = websiteService.getSetting('contact_address', '').trim();
    if (address.isNotEmpty) return address;
    return 'Retiro en $storeName';
  }

  String _pickupCustomerAddress(WebsiteService websiteService) {
    final pickupPoint = _pickupPointLabel(websiteService);
    return pickupPoint.toLowerCase().startsWith('retiro')
        ? pickupPoint
        : 'Retiro en tienda: $pickupPoint';
  }

  String _formatAddressForDisplay({
    required String street,
    required String streetNumber,
    required String apartment,
    required String comuna,
    required String city,
    required String region,
  }) {
    final streetLine = [street, streetNumber]
        .where((part) => part.trim().isNotEmpty)
        .join(' ')
        .trim();
    final normalizedComuna = comuna.trim().toLowerCase();
    final normalizedCity = city.trim().toLowerCase();
    final normalizedRegion = region.trim().toLowerCase();
    final parts = <String>[
      if (streetLine.isNotEmpty) streetLine,
      if (apartment.trim().isNotEmpty) apartment.trim(),
      if (comuna.trim().isNotEmpty) comuna.trim(),
      if (city.trim().isNotEmpty && normalizedCity != normalizedComuna)
        city.trim(),
      if (region.trim().isNotEmpty && normalizedRegion != normalizedCity)
        region.trim(),
      'Chile',
    ];
    return parts.join(', ');
  }

  Future<String?> _createAccountFromCheckout(
      CustomerAccountService service) async {
    if (!_createAccountAfterCheckout || service.isAuthenticated) return null;

    try {
      service.setTenantId(context.read<PublicStoreTenantProvider>().tenantId);
      final result = await service.signUp(
        email: _emailController.text.trim(),
        password: _accountPasswordController.text,
        name: _nameController.text.trim(),
        phone: _phoneController.text.trim(),
      );

      if (result == CustomerAuthResult.emailVerificationRequired) {
        return 'Te enviamos un correo para activar tu cuenta. Tus pedidos quedarán asociados a este email.';
      }

      return 'Cuenta creada. Desde Mi Cuenta podrás revisar pedidos, direcciones y servicios.';
    } catch (error) {
      debugPrint('Checkout account creation failed: $error');
      return 'El pedido fue creado, pero no pudimos crear la cuenta automáticamente. Puedes iniciar sesión o recuperar acceso con este mismo correo.';
    }
  }

  Future<void> _placeOrder() async {
    _checkoutDebugLog('🔵 [Checkout] _placeOrder() CALLED!');

    if (_isProcessing || _sessionRestoring || _sessionStorageUnavailable) {
      return;
    }

    final cart = context.read<CartProvider>();
    if (_submission.hasReceipt) {
      await _resumeCreatedOrder();
      return;
    }
    if (_submission.hasCreationAttempt) {
      await _retryOriginalOrderCreation();
      return;
    }

    if (!_formKey.currentState!.validate()) {
      _checkoutDebugLog('🔵 [Checkout] Form validation FAILED');
      return;
    }
    _checkoutDebugLog('🔵 [Checkout] Form validation PASSED');

    _checkoutDebugLog('🔵 [Checkout] Cart items: ${cart.items.length}');

    if (cart.items.isEmpty) {
      _checkoutDebugLog('🔵 [Checkout] Cart is EMPTY, showing snackbar');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('El carrito está vacío')),
      );
      return;
    }

    if (cart.items.any((item) =>
        item.commerce.availability == PublicCommerceAvailability.outOfStock)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Uno de los productos ya no está disponible. Vuelve al carrito para actualizarlo.',
          ),
        ),
      );
      return;
    }

    final taxSummary = cart.taxSummary;
    if (!taxSummary.isValid) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            taxSummary.checkoutBlockMessage ??
                'No podemos validar los impuestos de este carrito.',
          ),
          duration: const Duration(seconds: 8),
        ),
      );
      return;
    }

    final checkoutTenantId =
        context.read<PublicStoreTenantProvider>().tenantId?.trim();
    if (checkoutTenantId == null || checkoutTenantId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No pudimos identificar la tienda. Recarga la página antes de crear el pedido.',
          ),
        ),
      );
      return;
    }
    final selectedPaymentMethod = _paymentMethod;
    final currentCapabilities = await _loadPaymentCapabilities(
      checkoutTenantId,
      force: true,
      preserveSelection: true,
    );
    if (!mounted) return;
    if (currentCapabilities == null ||
        !currentCapabilities.isAvailable(selectedPaymentMethod)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'El medio de pago seleccionado ya no está disponible. Revisa las opciones antes de crear el pedido.',
          ),
          duration: Duration(seconds: 7),
        ),
      );
      return;
    }

    final shippingQuote = await _loadShippingQuote(force: true);
    if (!mounted) return;
    if (shippingQuote == null ||
        shippingQuote.deliveryType != _deliveryType ||
        shippingQuote.itemGross != _wholeClpCartTotal(cart)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Necesitamos confirmar el costo de entrega antes de crear el pedido.',
          ),
        ),
      );
      return;
    }

    _checkoutDebugLog('🔵 [Checkout] Setting _isProcessing = true');
    final exitGuard = context.read<CheckoutExitGuard>();
    final attemptLease = exitGuard.acquire(
      owner: _exitLeaseOwner,
      phase: CheckoutExitPhase.preparingOrder,
    );
    _exitLease = attemptLease;
    CheckoutSessionSnapshot? attemptedPendingSnapshot;
    setState(() {
      _isProcessing = true;
      _outcomeUnknownMessage = null;
      _postOrderRecoveryMessage = null;
    });

    try {
      _checkoutDebugLog('🔵 [Checkout] Getting services...');
      final websiteService =
          Provider.of<WebsiteService>(context, listen: false);
      _checkoutDebugLog('🔵 [Checkout] Got WebsiteService');

      final mercadopagoService =
          Provider.of<MercadoPagoService>(context, listen: false);
      _checkoutDebugLog('🔵 [Checkout] Got MercadoPagoService');

      final accountService = _accountService ??
          Provider.of<CustomerAccountService>(context, listen: false);
      _checkoutDebugLog('🔵 [Checkout] Got CustomerAccountService');

      final profile = accountService.customerProfile;
      final isPickup = _deliveryType == 'pickup';
      final resolvedAddress = isPickup ? null : _shippingAddressForOrder();
      _checkoutDebugLog(
          '🔵 [Checkout] Profile: ${profile != null ? "exists" : "null"}, delivery type: $_deliveryType');

      // ⚠️ CRITICAL: Get tenant_id from detected tenant (subdomain)
      _checkoutDebugLog('🔵 [Checkout] Getting tenant provider...');
      final tenantProvider = context.read<PublicStoreTenantProvider>();
      _checkoutDebugLog(
          '🔵 [Checkout] Got tenant provider, tenantId: ${tenantProvider.tenantId}');
      final tenantId = checkoutTenantId;
      _checkoutDebugLog('🔵 [Checkout] tenantId assigned: $tenantId');
      _checkoutDebugLog('🔵 [Checkout] ✅ tenantId is valid, continuing...');

      _checkoutDebugLog('🔵 [Checkout] Creating orderData map...');
      // Create order data (database will generate id and orderNumber)
      final Map<String, dynamic> orderData = {
        'tenant_id': tenantId, // ⚠️ REQUIRED for multi-tenant isolation
        'checkout_idempotency_key': _submission.idempotencyKey,
        'customer_email': _emailController.text.trim(),
        'customer_name': _nameController.text.trim(),
        'customer_phone': _phoneController.text.trim(),
        'customer_address': isPickup
            ? _pickupCustomerAddress(websiteService)
            : resolvedAddress!.formatForDisplay().isNotEmpty
                ? resolvedAddress.formatForDisplay()
                : _addressController.text.trim(),
        'delivery_type': _deliveryType,
        'shipping_address_line1': isPickup
            ? null
            : resolvedAddress!.street.isNotEmpty
                ? [
                    resolvedAddress.street,
                    resolvedAddress.streetNumber,
                  ]
                    .whereType<String>()
                    .where((value) => value.isNotEmpty)
                    .join(' ')
                : _addressController.text.trim(),
        'shipping_address_line2': isPickup ? null : resolvedAddress!.apartment,
        'shipping_city': isPickup
            ? null
            : resolvedAddress!.city.isNotEmpty
                ? resolvedAddress.city
                : resolvedAddress.comuna,
        'shipping_state': isPickup
            ? null
            : resolvedAddress!.region.isNotEmpty
                ? resolvedAddress.region
                : null,
        'shipping_postal_code': isPickup ? null : resolvedAddress!.postalCode,
        'shipping_country': isPickup ? null : 'Chile',
        // Informational mirror only. The database re-reads product prices and
        // tax classifications, then calculates the immutable order snapshot.
        'subtotal': taxSummary.netAmount,
        'tax_amount': taxSummary.taxAmount,
        // Consent snapshot only. The database independently derives this
        // amount from authoritative prices and rejects a stale quote.
        'shipping_quote_cost': shippingQuote.shippingGross,
        'shipping_cost': shippingQuote.shippingGross,
        'discount_amount': 0,
        'total': shippingQuote.orderGross,
        'status': 'pending',
        'payment_status': 'pending',
        'payment_method': _paymentMethod,
        'customer_notes': _notesController.text.trim().isNotEmpty
            ? _notesController.text.trim()
            : null,
      };
      _checkoutDebugLog(
          '🔵 [Checkout] orderData created: ${orderData.keys.join(', ')}');

      if (profile != null && profile['id'] != null) {
        orderData['customer_id'] = profile['id'];
        _checkoutDebugLog('🔵 [Checkout] Added customer_id to orderData');
      }

      _checkoutDebugLog('🔵 [Checkout] Creating orderItems...');
      final orderItems = cart.items.map((item) {
        final commerce = item.commerce;
        return {
          'tenant_id': tenantId, // ⚠️ REQUIRED for multi-tenant isolation
          'product_id': commerce.id,
          'product_name': commerce.title,
          'product_sku': commerce.sku,
          'quantity': item.quantity,
          'unit_price': commerce.price,
          'subtotal': commerce.price * item.quantity,
        };
      }).toList();
      _checkoutDebugLog(
          '🔵 [Checkout] orderItems created: ${orderItems.length} items');

      final orderContext = _CreatedOrderContext(
        tenantId: tenantId,
        paymentMethod: _paymentMethod,
        isPickup: isPickup,
        resolvedAddress: resolvedAddress,
        customerId: profile?['id']?.toString(),
        shouldSaveAddress: !isPickup &&
            accountService.isAuthenticated &&
            _saveAddressToAccount &&
            profile?['id'] != null,
      );
      final checkoutSessionStore =
          _sessionStore ??= context.read<CheckoutSessionStore>();

      late final CheckoutSessionSnapshot initialSnapshot;
      try {
        final orderedCartLines = orderItems
            .map(
              (item) => PersistedCartLine(
                productId: item['product_id'].toString(),
                quantity: item['quantity'] as int,
              ),
            )
            .toList(growable: false);
        final cartRevision = await cart.captureDurableCheckoutRevision(
          tenantId: tenantId,
          orderedLines: orderedCartLines,
        );
        if (!mounted || !attemptLease.isCurrent) {
          attemptLease.release();
          if (identical(_exitLease, attemptLease)) {
            _exitLease = null;
          }
          return;
        }
        final pendingSnapshot = CheckoutSessionSnapshot.create(
          tenantId: tenantId,
          savedAt: DateTime.now().toUtc(),
          idempotencyKey: _submission.idempotencyKey,
          orderData: orderData,
          orderItems: orderItems,
          handoff: CheckoutHandoffSnapshot(
            paymentMethod: _paymentMethod,
            deliveryType: _deliveryType,
          ),
          cartRevision: cartRevision,
        );
        attemptedPendingSnapshot = pendingSnapshot;
        // This awaited durability boundary must round-trip the exact payload
        // before the RPC can be attempted on web or native.
        initialSnapshot =
            await checkoutSessionStore.createPendingIfAbsent(pendingSnapshot);
      } catch (error) {
        debugPrint('Checkout durable session save failed before creation.');
        final pendingSnapshot = attemptedPendingSnapshot;
        if (pendingSnapshot != null) {
          try {
            await checkoutSessionStore.clearPendingIfMatches(
              tenantId: pendingSnapshot.tenantId,
              idempotencyKey: pendingSnapshot.idempotencyKey,
            );
          } catch (_) {
            // The exact compare-before-clear guard protects any newer attempt.
          }
        }
        attemptLease.release();
        if (identical(_exitLease, attemptLease)) {
          _exitLease = null;
        }
        if (mounted) {
          const message =
              'No pudimos guardar una recuperación segura en este dispositivo. '
              'El pedido no fue enviado. Recarga la aplicación e inténtalo '
              'nuevamente.';
          setState(() {
            _outcomeUnknownMessage = message;
            _postOrderRecoveryMessage = null;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(message),
              duration: Duration(seconds: 9),
            ),
          );
        }
        return;
      }

      if (!mounted || !attemptLease.isCurrent) {
        await checkoutSessionStore.clearPendingIfMatches(
          tenantId: tenantId,
          idempotencyKey: initialSnapshot.idempotencyKey,
        );
        attemptLease.release();
        if (identical(_exitLease, attemptLease)) {
          _exitLease = null;
        }
        return;
      }
      _durableSnapshot = initialSnapshot;
      // Publish the execution context only after the exact snapshot has
      // round-tripped through durable storage. A pre-RPC save failure leaves
      // checkout editable, so the next attempt must rebuild both values from
      // the customer's latest delivery and payment choices.
      _createdOrderContext = orderContext;
      attemptLease.updatePhase(CheckoutExitPhase.recoveringOrder);

      _checkoutDebugLog(
          '🔵 [Checkout] Calling websiteService.createOrder()...');
      final checkoutAccess = await _submission.ensureOrderCreated(
        (idempotencyKey) {
          if (idempotencyKey != initialSnapshot.idempotencyKey) {
            throw StateError(
              'La sesión no corresponde al intento durable guardado.',
            );
          }
          return websiteService.createOrder(
            initialSnapshot.orderData,
            initialSnapshot.orderItems,
          );
        },
      );
      await _ensureReceiptDurable(checkoutAccess);
      if (!mounted || !attemptLease.isCurrent) return;
      _checkoutDebugLog('🔵 [Checkout] ✅ Secure order created');

      await _completeCreatedOrder(
        checkoutAccess: checkoutAccess,
        orderContext: orderContext,
        accountService: accountService,
        mercadopagoService: mercadopagoService,
      );
    } catch (error, stackTrace) {
      debugPrint('❌ [Checkout] Submission error: $error');
      debugPrint('❌ [Checkout] Stack trace: $stackTrace');
      if (!_submission.hasCreationAttempt && !_submission.hasReceipt) {
        final pendingSnapshot = attemptedPendingSnapshot;
        final store = _sessionStore;
        if (pendingSnapshot != null && store != null) {
          try {
            await store.clearPendingIfMatches(
              tenantId: pendingSnapshot.tenantId,
              idempotencyKey: pendingSnapshot.idempotencyKey,
            );
          } catch (_) {
            // A cleanup failure keeps the conservative recovery record.
          }
        }
        attemptLease.release();
        if (identical(_exitLease, attemptLease)) {
          _exitLease = null;
        }
      }
      if (!mounted) return;

      if (_submission.hasReceipt) {
        _showPostOrderRecovery();
      } else {
        _showOutcomeUnknownRecovery();
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  Future<void> _retryOriginalOrderCreation() async {
    final orderContext = _createdOrderContext;
    if (orderContext == null) {
      _showOutcomeUnknownRecovery();
      return;
    }

    setState(() {
      _isProcessing = true;
      _outcomeUnknownMessage = null;
      _postOrderRecoveryMessage = null;
    });

    try {
      final checkoutAccess = await _submission.retryOriginalOrder();
      await _ensureReceiptDurable(checkoutAccess);
      if (!mounted) return;
      await _completeCreatedOrder(
        checkoutAccess: checkoutAccess,
        orderContext: orderContext,
        accountService:
            _accountService ?? context.read<CustomerAccountService>(),
        mercadopagoService: context.read<MercadoPagoService>(),
      );
    } catch (error, stackTrace) {
      debugPrint('❌ [Checkout] Original order retry error: $error');
      debugPrint('❌ [Checkout] Stack trace: $stackTrace');
      if (!mounted) return;
      if (_submission.hasReceipt) {
        _showPostOrderRecovery();
      } else {
        _showOutcomeUnknownRecovery();
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  Future<void> _resumeCreatedOrder() async {
    final checkoutAccess = _submission.receipt;
    final orderContext = _createdOrderContext;
    if (checkoutAccess == null || orderContext == null) {
      _showPostOrderRecovery();
      return;
    }

    setState(() {
      _isProcessing = true;
      _outcomeUnknownMessage = null;
      _postOrderRecoveryMessage = null;
    });

    try {
      await _completeCreatedOrder(
        checkoutAccess: checkoutAccess,
        orderContext: orderContext,
        accountService:
            _accountService ?? context.read<CustomerAccountService>(),
        mercadopagoService: context.read<MercadoPagoService>(),
      );
    } catch (error, stackTrace) {
      debugPrint('❌ [Checkout] Post-order handoff error: $error');
      debugPrint('❌ [Checkout] Stack trace: $stackTrace');
      if (mounted) _showPostOrderRecovery();
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  Future<void> _completeCreatedOrder({
    required PublicOrderCheckoutAccess checkoutAccess,
    required _CreatedOrderContext orderContext,
    required CustomerAccountService accountService,
    required MercadoPagoService mercadopagoService,
  }) async {
    if (!(_exitLease?.isCurrent ?? false)) {
      if (!mounted) return;
      final route = ModalRoute.of(context);
      if (route?.isCurrent != true) return;
      _exitLease = context.read<CheckoutExitGuard>().acquire(
            owner: _exitLeaseOwner,
            phase: CheckoutExitPhase.orderCreated,
          );
    }

    await _submission.handOff((receipt) async {
      await _ensureReceiptDurable(receipt);
      // Persist before any external redirect or local navigation. Retrying this
      // post-order step is safe and never invokes createOrder again.
      final store = _sessionStore;
      if (store == null) {
        throw StateError(
          'No existe un almacén seguro para abrir el pedido creado.',
        );
      }
      await store.saveOrderAccess(
        tenantId: orderContext.tenantId,
        access: receipt,
      );

      await _runNonBlockingPostOrderTasks(
        accountService: accountService,
        orderContext: orderContext,
      );
      if (!mounted || !(_exitLease?.isCurrent ?? false)) return;

      if (orderContext.paymentMethod == 'mercadopago') {
        await _openMercadoPagoForCreatedOrder(
          checkoutAccess: checkoutAccess,
          tenantId: orderContext.tenantId,
          mercadopagoService: mercadopagoService,
        );
        return;
      }

      await _consumeOrderedCartLinesOnce();
      if (!mounted) return;
      // The checkout operation is complete and durable at this point. Release
      // its lease before the shared navigation boundary runs so only an
      // editor draft (if any) can block the transition to confirmation.
      _exitLease?.release();
      await PublicStoreLayout.navigateToHref(
        context,
        '/tienda/pedido/${checkoutAccess.orderId}',
      );
    });

    if (mounted) {
      setState(() {
        _outcomeUnknownMessage = null;
        _postOrderRecoveryMessage = null;
      });
    }
  }

  Future<void> _ensureReceiptDurable(
    PublicOrderCheckoutAccess receipt,
  ) async {
    final snapshot = _durableSnapshot;
    if (snapshot == null) {
      throw StateError(
        'No existe una sesión durable para guardar el recibo del pedido.',
      );
    }
    final existingReceipt = snapshot.receipt;
    if (existingReceipt != null &&
        (existingReceipt.orderId != receipt.orderId ||
            existingReceipt.accessToken != receipt.accessToken)) {
      throw StateError(
        'El recibo no corresponde a la sesión durable del checkout.',
      );
    }

    final store = _sessionStore;
    if (store == null) {
      throw StateError(
        'No existe un almacén durable para guardar el recibo del pedido.',
      );
    }
    final durable = await store.attachReceiptIfMatches(
      tenantId: snapshot.tenantId,
      idempotencyKey: snapshot.idempotencyKey,
      receipt: receipt,
    );
    _durableSnapshot = durable;
    _exitLease?.updatePhase(CheckoutExitPhase.orderCreated);
  }

  Future<void> _consumeOrderedCartLinesOnce() async {
    final snapshot = _durableSnapshot;
    final store = _sessionStore;
    if (snapshot == null || snapshot.receipt == null || store == null) {
      return;
    }
    final cart = context.read<CartProvider>();

    final outcome = await store.consumeCartOnce(
      tenantId: snapshot.tenantId,
      orderId: snapshot.receipt!.orderId,
      consume: (claimed) async {
        final cartRevision = claimed.cartRevision;
        if (cartRevision == null || cartRevision.isEmpty) return false;
        final orderedLines = claimed.orderItems
            .map(
              (item) => PersistedCartLine(
                productId: item['product_id'].toString(),
                quantity: item['quantity'] as int,
              ),
            )
            .toList(growable: false);
        final result = await cart.consumeOrderedLines(
          tenantId: claimed.tenantId,
          orderedLines: orderedLines,
          expectedRevision: cartRevision,
        );
        return result.applied;
      },
    );
    try {
      final refreshed = await store.read(snapshot.tenantId);
      if (refreshed?.receipt?.orderId == snapshot.receipt!.orderId) {
        _durableSnapshot = refreshed;
      }
    } catch (_) {
      // The independently verified terminal outcome is authoritative. A
      // best-effort UI refresh must not turn a completed one-shot operation
      // back into a retry.
    }
    if (outcome.showsWarning) {
      _showCartConsumptionWarning();
    }
  }

  void _showCartConsumptionWarning() {
    if (!mounted) return;
    const message =
        'Tu pedido se completó. Revisa tu carrito: puede que aún contenga '
        'artículos comprados.';
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(message),
        duration: Duration(seconds: 9),
      ),
    );
  }

  Future<void> _runNonBlockingPostOrderTasks({
    required CustomerAccountService accountService,
    required _CreatedOrderContext orderContext,
  }) async {
    if (!_postOrderAccountAttempted) {
      _postOrderAccountAttempted = true;
      final accountMessage = await _createAccountFromCheckout(accountService);
      if (accountMessage != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(accountMessage),
            duration: const Duration(seconds: 6),
          ),
        );
      }
    }

    if (_postOrderAddressAttempted ||
        !orderContext.shouldSaveAddress ||
        orderContext.resolvedAddress == null ||
        orderContext.customerId == null) {
      return;
    }

    _postOrderAddressAttempted = true;
    try {
      await _saveAddressForCustomer(
        accountService,
        orderContext.resolvedAddress!,
        orderContext.customerId!,
      );
    } catch (error) {
      debugPrint('Checkout address save failed after order creation: $error');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Tu pedido quedó guardado, pero no pudimos guardar la dirección '
            'en tu cuenta.',
          ),
          duration: Duration(seconds: 7),
        ),
      );
    }
  }

  Future<void> _openMercadoPagoForCreatedOrder({
    required PublicOrderCheckoutAccess checkoutAccess,
    required String tenantId,
    required MercadoPagoService mercadopagoService,
  }) async {
    _checkoutDebugLog(
      '🔵 [Checkout] Starting MercadoPago flow for order: '
      '${checkoutAccess.orderId}',
    );
    // Availability was confirmed by the tenant-scoped server contract before
    // order creation. The public client only supplies routing context here;
    // provider credentials remain server-side.
    mercadopagoService.setTenantId(tenantId);

    final preference = await mercadopagoService.createPreference(
      orderId: checkoutAccess.orderId,
      orderAccessToken: checkoutAccess.accessToken,
    );
    final initPoint = preference['init_point'] as String?;
    if (initPoint == null || initPoint.isEmpty) {
      throw const FormatException('MercadoPago preference has no init point.');
    }

    if (kIsWeb) {
      if (!mounted || !(_exitLease?.isCurrent ?? false)) return;
      web_utils.WebUtils.openUrl(initPoint);
      return;
    }

    final url = Uri.parse(initPoint);
    if (!await canLaunchUrl(url)) {
      throw StateError('MercadoPago checkout could not be opened.');
    }
    if (!mounted || !(_exitLease?.isCurrent ?? false)) return;
    final launched = await launchUrl(
      url,
      mode: LaunchMode.externalApplication,
    );
    if (!launched) {
      throw StateError('MercadoPago checkout could not be opened.');
    }

    if (!mounted) return;
    // The external handoff succeeded; the local confirmation transition no
    // longer represents an abandoned checkout.
    _exitLease?.release();
    await PublicStoreLayout.navigateToHref(
      context,
      '/tienda/pedido/${checkoutAccess.orderId}',
    );
  }

  void _showPostOrderRecovery() {
    if (!mounted) return;
    const message =
        'Tu pedido ya quedó guardado. No pudimos completar el siguiente paso. '
        'Continúa para retomar el mismo pedido sin crear otro.';
    setState(() {
      _outcomeUnknownMessage = null;
      _postOrderRecoveryMessage = message;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(message),
        duration: Duration(seconds: 10),
      ),
    );
  }

  void _showOutcomeUnknownRecovery() {
    if (!mounted) return;
    const message =
        'No pudimos confirmar el resultado del intento. Tu carrito sigue aquí. '
        'Reintenta con los mismos datos: si el pedido ya existe, recuperaremos '
        'ese mismo pedido.';
    setState(() {
      _outcomeUnknownMessage = message;
      _postOrderRecoveryMessage = null;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(message),
        duration: Duration(seconds: 10),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin
    final cart = context.watch<CartProvider>();
    context.watch<CheckoutExitGuard>();
    context.watch<CustomerAccountService>();
    final tenantProvider = context.watch<PublicStoreTenantProvider>();
    _accountService ??=
        Provider.of<CustomerAccountService>(context, listen: false);
    _schedulePaymentCapabilityRefresh(tenantProvider.tenantId);

    _checkoutDebugLog(
        '🛒 [CheckoutPage.build] cart.isEmpty: ${cart.isEmpty}, items: ${cart.items.length}');

    if (_durableSnapshot == null && cart.isNotEmpty && cart.total != null) {
      _scheduleShippingQuoteRefresh(cart);
    }

    // Get edit mode for key to prevent element reactivation conflicts

    _checkoutDebugLog(
        '🛒 [CheckoutPage.build] Building ${cart.isEmpty ? "empty-cart" : "checkout"} state');
    return MediaQueryLayoutBuilder(
      key: const ValueKey('checkout_layout'),
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 980;
        final horizontalMargin = constraints.maxWidth < 760 ? 16.0 : 24.0;
        final verticalMargin = isMobile ? 28.0 : 44.0;

        if (cart.isEmpty && _durableSnapshot == null) {
          return _buildEmptyCart(
            context,
            horizontalMargin: horizontalMargin,
            verticalMargin: verticalMargin,
          );
        }

        return Container(
          constraints: const BoxConstraints(maxWidth: 1320),
          margin: EdgeInsets.symmetric(
            horizontal: horizontalMargin,
            vertical: verticalMargin,
          ),
          child: isMobile
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildPageHeader(),
                    const SizedBox(height: 28),
                    if (_isRestoredCheckoutSession)
                      _buildRestoredCheckoutNotice()
                    else
                      IgnorePointer(
                        ignoring: _checkoutLocked,
                        child: _buildCheckoutForm(isMobile: true),
                      ),
                    const SizedBox(height: 32),
                    _buildOrderSummary(cart, isMobile: true),
                  ],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 7,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildPageHeader(),
                          const SizedBox(height: 34),
                          if (_isRestoredCheckoutSession)
                            _buildRestoredCheckoutNotice()
                          else
                            IgnorePointer(
                              ignoring: _checkoutLocked,
                              child: _buildCheckoutForm(isMobile: false),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 28),
                    Expanded(
                      flex: 4,
                      child: _buildOrderSummary(cart, isMobile: false),
                    ),
                  ],
                ),
        );
      },
    );
  }

  Widget _buildPageHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeading('Finalizar compra'),
        const SizedBox(height: 12),
        Text(
          'Completa tus datos de contacto, elige la forma de entrega y '
          'selecciona el medio de pago antes de confirmar tu pedido.',
          style: _storeTheme.text.bodyMedium?.copyWith(
            fontSize: 15,
            color: _storeTheme.textSecondary,
            height: 1.55,
          ),
        ),
      ],
    );
  }

  Widget _buildRestoredCheckoutNotice() {
    return Container(
      key: const ValueKey('checkout-restored-session-notice'),
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _storeTheme.softSurface,
        border: Border(
          left: BorderSide(color: _storeTheme.primary, width: 4),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.restore_rounded,
            color: _storeTheme.primary,
            size: 26,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'PEDIDO RECUPERADO',
                  style: _storeTheme.text.labelLarge?.copyWith(
                    color: _storeTheme.primary,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Los productos y totales mostrados pertenecen al intento '
                  'guardado. No se reemplazan con el carrito actual.',
                  style: _storeTheme.text.bodyMedium?.copyWith(
                    color: _storeTheme.textSecondary,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyCart(
    BuildContext context, {
    required double horizontalMargin,
    required double verticalMargin,
  }) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 1320),
      margin: EdgeInsets.symmetric(
        horizontal: horizontalMargin,
        vertical: verticalMargin,
      ),
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 560),
          padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 148,
                height: 148,
                decoration: BoxDecoration(
                  color: _storeTheme.softSurface,
                  border: Border.all(color: _storeTheme.line),
                ),
                child: Icon(
                  Icons.shopping_cart_outlined,
                  size: 62,
                  color: _storeTheme.textMuted,
                ),
              ),
              const SizedBox(height: 32),
              _buildSectionHeading('No hay productos para finalizar'),
              const SizedBox(height: 16),
              Text(
                'Vuelve al catálogo, revisa productos y agrega artículos antes de continuar al checkout.',
                style: _storeTheme.text.bodyMedium?.copyWith(
                  fontSize: 15,
                  color: _storeTheme.textSecondary,
                  height: 1.6,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              FilledButton.icon(
                onPressed: () =>
                    PublicStoreLayout.navigateToHref(context, '/productos'),
                icon: const Icon(Icons.shopping_bag_outlined),
                label: const Text('EXPLORAR PRODUCTOS'),
                style: FilledButton.styleFrom(
                  backgroundColor: _storeTheme.primary,
                  foregroundColor: _storeTheme.onPrimary,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 30, vertical: 18),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCheckoutForm({required bool isMobile}) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildFormSection(
            title: '1. Información de contacto',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextFormField(
                  controller: _nameController,
                  decoration: _fieldDecoration(
                    label: 'Nombre completo *',
                    icon: Icons.person_outline,
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'El nombre es requerido';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 18),
                TextFormField(
                  controller: _emailController,
                  decoration: _fieldDecoration(
                    label: 'Correo electrónico *',
                    icon: Icons.email_outlined,
                  ),
                  keyboardType: TextInputType.emailAddress,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'El correo es requerido';
                    }
                    if (!_emailPattern.hasMatch(value.trim())) {
                      return 'Ingresa un correo válido';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 18),
                TextFormField(
                  controller: _phoneController,
                  decoration: _fieldDecoration(
                    label: 'Teléfono *',
                    icon: Icons.phone_outlined,
                    hintText: '+56 9 1234 5678',
                  ),
                  keyboardType: TextInputType.phone,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'El teléfono es requerido';
                    }
                    final digits = value.replaceAll(RegExp(r'\D'), '');
                    if (digits.length < 8 || digits.length > 15) {
                      return 'Ingresa un teléfono válido';
                    }
                    return null;
                  },
                ),
                if (!(_accountService?.isAuthenticated ?? false)) ...[
                  const SizedBox(height: 18),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: _storeTheme.surface,
                      border: Border.all(color: _storeTheme.line),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CheckboxListTile(
                          value: _createAccountAfterCheckout,
                          onChanged: (value) {
                            setState(() {
                              _createAccountAfterCheckout = value ?? false;
                            });
                          },
                          contentPadding: EdgeInsets.zero,
                          controlAffinity: ListTileControlAffinity.leading,
                          title: Text(
                            'Crear una cuenta con estos datos',
                            style: _storeTheme.text.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: _storeTheme.textPrimary,
                            ),
                          ),
                          subtitle: const Text(
                            'Te enviaremos una confirmación por correo para activar el acceso a pedidos, direcciones y servicios.',
                          ),
                        ),
                        if (_createAccountAfterCheckout) ...[
                          const SizedBox(height: 14),
                          TextFormField(
                            controller: _accountPasswordController,
                            obscureText: _obscureAccountPassword,
                            decoration: _fieldDecoration(
                              label: 'Contraseña para tu cuenta *',
                              icon: Icons.lock_outline,
                            ).copyWith(
                              helperText:
                                  AuthInputValidation.strongPasswordHelper,
                              suffixIcon: IconButton(
                                onPressed: () {
                                  setState(() {
                                    _obscureAccountPassword =
                                        !_obscureAccountPassword;
                                  });
                                },
                                icon: Icon(
                                  _obscureAccountPassword
                                      ? Icons.visibility_outlined
                                      : Icons.visibility_off_outlined,
                                ),
                              ),
                            ),
                            validator: (value) {
                              if (!_createAccountAfterCheckout) return null;
                              return AuthInputValidation.validatePassword(
                                value,
                                isNewPassword: true,
                              );
                            },
                          ),
                          const SizedBox(height: 14),
                          TextFormField(
                            controller: _accountPasswordConfirmController,
                            obscureText: _obscureAccountPassword,
                            decoration: _fieldDecoration(
                              label: 'Confirmar contraseña *',
                              icon: Icons.lock_reset_outlined,
                            ),
                            validator: (value) {
                              if (!_createAccountAfterCheckout) return null;
                              return AuthInputValidation
                                  .validatePasswordConfirmation(
                                value,
                                password: _accountPasswordController.text,
                              );
                            },
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 24),
          _buildFormSection(
            title: '2. Entrega',
            child: _buildDeliverySection(),
          ),
          const SizedBox(height: 24),
          _buildFormSection(
            title: '3. Método de pago',
            child: _buildPaymentMethodSection(),
          ),
          const SizedBox(height: 24),
          _buildFormSection(
            title: 'Notas adicionales (opcional)',
            child: TextFormField(
              controller: _notesController,
              decoration: _fieldDecoration(
                label: 'Instrucciones especiales para tu pedido',
                icon: Icons.note_alt_outlined,
              ),
              maxLines: 4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDeliverySection() {
    final autocompleteEnabled = _addressAutocompleteService?.isEnabled ?? false;
    final isAuthenticated = _accountService?.isAuthenticated ?? false;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RadioGroup<String>(
          groupValue: _deliveryType,
          onChanged: (value) {
            if (_checkoutLocked || value == null) return;
            _selectDeliveryType(value);
          },
          child: Column(
            children: [
              _buildDeliveryOption(
                value: 'shipping',
                title: 'Despacho a domicilio',
                subtitle:
                    'Chile continental, 3 a 12 días hábiles. Verás el costo exacto antes de realizar el pedido.',
                icon: Icons.local_shipping_outlined,
              ),
              _buildDeliveryOption(
                value: 'pickup',
                title: 'Retiro en tienda',
                subtitle:
                    'Compra online y retira cuando recibas la confirmación de que tu pedido está listo.',
                icon: Icons.storefront_outlined,
                isLast: true,
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        if (_deliveryType == 'pickup') ...[
          _buildPickupInstructions(),
        ] else ...[
          if (isAuthenticated && _savedAddresses.isNotEmpty) ...[
            DropdownButtonFormField<CustomerAddress>(
              initialValue: _selectedAddress,
              decoration: _fieldDecoration(
                label: 'Usar dirección guardada',
                icon: Icons.bookmark_outline,
              ),
              items: _savedAddresses
                  .map(
                    (address) => DropdownMenuItem<CustomerAddress>(
                      value: address,
                      child: Text('${address.label} • ${address.comuna}'),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value != null) {
                  _applyAddressFromCustomer(value);
                }
              },
            ),
            const SizedBox(height: 16),
          ],
          if (autocompleteEnabled) ...[
            typeahead.TypeAheadField<AddressSuggestion>(
              controller: _addressController,
              suggestionsCallback: (pattern) async {
                return await _addressAutocompleteService
                        ?.fetchSuggestions(pattern) ??
                    [];
              },
              builder: (context, controller, focusNode) {
                return TextFormField(
                  controller: controller,
                  focusNode: focusNode,
                  decoration: _fieldDecoration(
                    label: 'Buscar dirección',
                    icon: Icons.search,
                    hintText: 'Ej: Álvarez 32, Viña del Mar',
                  ),
                  maxLines: 1,
                  onChanged: (value) {
                    if (value.trim().isEmpty) {
                      setState(() {
                        _selectedAddress = null;
                        _resolvedAddress = null;
                      });
                    }
                  },
                );
              },
              itemBuilder: (context, suggestion) => ListTile(
                leading: const Icon(Icons.place_outlined),
                title: Text(suggestion.description),
              ),
              loadingBuilder: (context) => const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              ),
              emptyBuilder: (context) => const Padding(
                padding: EdgeInsets.all(12),
                child: Text('No encontramos coincidencias'),
              ),
              onSelected: (suggestion) async {
                FocusScope.of(context).unfocus();
                final resolved = await _addressAutocompleteService
                    ?.resolvePlace(suggestion.placeId);
                if (resolved != null) {
                  _applyResolvedAddress(
                    resolved,
                    selectedLabel: suggestion.description,
                  );
                  _addressAutocompleteService?.resetSessionToken();
                }
              },
            ),
            const SizedBox(height: 8),
            Text(
              'Selecciona una sugerencia y revisa los datos antes de confirmar.',
              style: _storeTheme.text.bodySmall?.copyWith(
                fontSize: 12,
                color: _storeTheme.textSecondary,
              ),
            ),
          ] else if (_addressAutocompleteService != null) ...[
            Text(
              'Puedes escribir tu dirección manualmente. Separarla nos ayuda a guardarla mejor en tu cuenta.',
              style: _storeTheme.text.bodySmall?.copyWith(
                fontSize: 12,
                color: _storeTheme.textSecondary,
              ),
            ),
          ],
          const SizedBox(height: 18),
          _buildAddressDetailsFields(),
          if (isAuthenticated && _selectedAddress == null) ...[
            const SizedBox(height: 16),
            TextFormField(
              controller: _addressLabelController,
              decoration: _fieldDecoration(
                label: 'Etiqueta (ej: Casa, Trabajo)',
                icon: Icons.label_outline,
              ),
            ),
            CheckboxListTile(
              value: _saveAddressToAccount,
              onChanged: (value) {
                setState(() {
                  _saveAddressToAccount = value ?? false;
                });
              },
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text('Guardar esta dirección en mi cuenta'),
            ),
          ] else if (isAuthenticated && _selectedAddress != null) ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _checkoutLocked
                    ? null
                    : () => PublicStoreLayout.navigateToHref(
                          context,
                          '/tienda/cuenta/direcciones',
                        ),
                style: TextButton.styleFrom(
                  foregroundColor: _storeTheme.primary,
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(0, 0),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                icon: const Icon(Icons.open_in_new, size: 16),
                label: const Text('Gestionar mis direcciones guardadas'),
              ),
            ),
          ],
        ],
      ],
    );
  }

  Widget _buildDeliveryOption({
    required String value,
    required String title,
    required String subtitle,
    required IconData icon,
    bool isLast = false,
  }) {
    final isSelected = _deliveryType == value;

    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: isLast ? Colors.transparent : _storeTheme.line,
          ),
        ),
      ),
      child: InkWell(
        onTap: _checkoutLocked ? null : () => _selectDeliveryType(value),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Radio<String>(
                value: value,
                activeColor: _storeTheme.primary,
              ),
              const SizedBox(width: 8),
              Icon(
                icon,
                size: 22,
                color: isSelected
                    ? _storeTheme.primary
                    : _storeTheme.textSecondary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: _storeTheme.text.bodyMedium?.copyWith(
                        fontSize: 15,
                        fontWeight:
                            isSelected ? FontWeight.w700 : FontWeight.w600,
                        color: _storeTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: _storeTheme.text.bodySmall?.copyWith(
                        fontSize: 13,
                        color: _storeTheme.textSecondary,
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPickupInstructions() {
    final websiteService = context.watch<WebsiteService>();
    final storeName = websiteService.getSetting('store_name', 'la tienda');
    final address = websiteService.getSetting('contact_address', '').trim();
    final phone = websiteService.getSetting('contact_phone', '').trim();

    final rows = [
      if (address.isNotEmpty) ('Punto de retiro', address),
      ('Cuándo retirar', 'Espera la confirmación de que el pedido está listo.'),
      ('Qué llevar', 'Número de pedido y nombre de quien compra.'),
      ('Retira otra persona', 'Indícalo en notas para coordinar sin fricción.'),
      if (phone.isNotEmpty) ('Contacto tienda', phone),
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _storeTheme.surface,
        border: Border.all(color: _storeTheme.line),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.storefront_outlined,
                color: _storeTheme.primary,
                size: 22,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Retiro en $storeName',
                      style: _storeTheme.text.bodyMedium?.copyWith(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: _storeTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'La tienda preparará tu pedido y te avisará antes de que pases a buscarlo.',
                      style: _storeTheme.text.bodySmall?.copyWith(
                        fontSize: 13,
                        color: _storeTheme.textSecondary,
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          for (final row in rows) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 128,
                  child: Text(
                    row.$1,
                    style: _storeTheme.text.labelSmall?.copyWith(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: _storeTheme.textSecondary,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    row.$2,
                    style: _storeTheme.text.bodySmall?.copyWith(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: _storeTheme.textPrimary,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
            if (row != rows.last) const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }

  Widget _buildAddressDetailsFields() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final useTwoColumns = constraints.maxWidth >= 640;
        return Column(
          children: [
            _buildAddressFieldRow(
              useTwoColumns: useTwoColumns,
              left: TextFormField(
                controller: _streetController,
                decoration: _fieldDecoration(
                  label: 'Calle *',
                  icon: Icons.signpost_outlined,
                  hintText: 'Ej: Álvarez',
                ),
                validator: (value) {
                  if (_deliveryType == 'pickup') return null;
                  if (value == null || value.trim().isEmpty) {
                    return 'La calle es requerida';
                  }
                  return null;
                },
              ),
              right: TextFormField(
                controller: _streetNumberController,
                decoration: _fieldDecoration(
                  label: 'Número',
                  icon: Icons.pin_outlined,
                  hintText: 'Ej: 32',
                ),
              ),
            ),
            const SizedBox(height: 14),
            _buildAddressFieldRow(
              useTwoColumns: useTwoColumns,
              left: TextFormField(
                controller: _apartmentController,
                decoration: _fieldDecoration(
                  label: 'Depto / oficina / local',
                  icon: Icons.apartment_outlined,
                  hintText: 'Opcional',
                ),
              ),
              right: TextFormField(
                controller: _comunaController,
                decoration: _fieldDecoration(
                  label: 'Comuna *',
                  icon: Icons.location_city_outlined,
                  hintText: 'Ej: Viña del Mar',
                ),
                validator: (value) {
                  if (_deliveryType == 'pickup') return null;
                  if (value == null || value.trim().isEmpty) {
                    return 'La comuna es requerida';
                  }
                  return null;
                },
              ),
            ),
            const SizedBox(height: 14),
            _buildAddressFieldRow(
              useTwoColumns: useTwoColumns,
              left: TextFormField(
                controller: _cityController,
                decoration: _fieldDecoration(
                  label: 'Ciudad',
                  icon: Icons.domain_outlined,
                  hintText: 'Ej: Viña del Mar',
                ),
              ),
              right: TextFormField(
                controller: _regionController,
                decoration: _fieldDecoration(
                  label: 'Región *',
                  icon: Icons.map_outlined,
                  hintText: 'Ej: Valparaíso',
                ),
                validator: (value) {
                  if (_deliveryType == 'pickup') return null;
                  if (value == null || value.trim().isEmpty) {
                    return 'La región es requerida';
                  }
                  return null;
                },
              ),
            ),
            const SizedBox(height: 14),
            Align(
              alignment: Alignment.centerLeft,
              child: SizedBox(
                width: useTwoColumns ? constraints.maxWidth / 2 - 8 : null,
                child: TextFormField(
                  controller: _postalCodeController,
                  decoration: _fieldDecoration(
                    label: 'Código postal',
                    icon: Icons.markunread_mailbox_outlined,
                    hintText: 'Opcional',
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildAddressFieldRow({
    required bool useTwoColumns,
    required Widget left,
    required Widget right,
  }) {
    if (!useTwoColumns) {
      return Column(
        children: [
          left,
          const SizedBox(height: 14),
          right,
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: left),
        const SizedBox(width: 14),
        Expanded(child: right),
      ],
    );
  }

  Widget _buildOrderSummary(CartProvider cart, {required bool isMobile}) {
    final snapshot = _durableSnapshot;
    final usesDurableSnapshot = snapshot != null;
    final taxSummary = cart.taxSummary;
    final knownGross = cart.grossMerchandiseAmountClp;
    final hasCurrentShippingQuote =
        !usesDurableSnapshot && _hasCurrentShippingQuote(cart);
    final hasUsablePaymentMethod = _submission.hasStarted ||
        (!_paymentCapabilitiesLoading &&
            _paymentCapabilities?.isAvailable(_paymentMethod) == true);
    final canPlaceOrResumeOrder = _checkoutLocked ||
        (!_shippingQuoteLoading &&
            taxSummary.isValid &&
            hasCurrentShippingQuote &&
            hasUsablePaymentMethod);
    final recoveryMessage = _postOrderRecoveryMessage ?? _outcomeUnknownMessage;
    final shippingQuote = hasCurrentShippingQuote ? _shippingQuote : null;
    final frozenShipping =
        snapshot == null ? null : _snapshotAmount(snapshot, 'shipping_cost');
    final frozenSubtotal =
        snapshot == null ? null : _snapshotAmount(snapshot, 'subtotal');
    final frozenTax =
        snapshot == null ? null : _snapshotAmount(snapshot, 'tax_amount');
    final frozenTotal =
        snapshot == null ? null : _snapshotAmount(snapshot, 'total');
    final shippingLabel = usesDurableSnapshot
        ? (snapshot.handoff.deliveryType == 'pickup' || frozenShipping == 0
            ? 'Sin costo'
            : frozenShipping == null
                ? '—'
                : ChileanUtils.formatCurrency(frozenShipping))
        : shippingQuote == null
            ? (_shippingQuoteLoading ? 'Calculando…' : '—')
            : shippingQuote.isPickup
                ? 'Sin costo'
                : ChileanUtils.formatCurrency(
                    shippingQuote.shippingGross.toDouble(),
                  );
    final orderTotalLabel = usesDurableSnapshot
        ? (frozenTotal == null ? '—' : ChileanUtils.formatCurrency(frozenTotal))
        : shippingQuote == null
            ? '—'
            : ChileanUtils.formatCurrency(shippingQuote.orderGross.toDouble());
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(isMobile ? 20 : 24),
      decoration: BoxDecoration(
        color: _storeTheme.raisedSurface,
        border: Border(
          top: BorderSide(color: _storeTheme.line),
          bottom: BorderSide(color: _storeTheme.line),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'RESUMEN DEL PEDIDO',
            style: _storeTheme.text.headlineMedium?.copyWith(
              fontSize: isMobile ? 28 : 32,
              fontWeight: FontWeight.w700,
              color: _storeTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 18),
          if (_isRestoredCheckoutSession) ...[
            Container(
              key: const ValueKey('checkout-frozen-order-summary'),
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              color: _storeTheme.softSurface,
              child: Text(
                'RESUMEN CONGELADO DEL PEDIDO RECUPERADO',
                style: _storeTheme.text.labelSmall?.copyWith(
                  color: _storeTheme.primary,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
          if (snapshot != null)
            for (var index = 0; index < snapshot.orderItems.length; index++)
              _buildSnapshotSummaryProductRow(
                snapshot.orderItems[index],
                isLast: index == snapshot.orderItems.length - 1,
              )
          else
            for (var index = 0; index < cart.items.length; index++)
              _buildSummaryProductRow(
                cart.items[index],
                isLast: index == cart.items.length - 1,
              ),
          const SizedBox(height: 18),
          Container(
            width: double.infinity,
            height: 1,
            color: _storeTheme.line,
          ),
          const SizedBox(height: 18),
          if (snapshot != null) ...[
            _buildSummaryMetric(
              'Subtotal neto',
              frozenSubtotal == null
                  ? '—'
                  : ChileanUtils.formatCurrency(frozenSubtotal),
            ),
            const SizedBox(height: 12),
            _buildSummaryMetric(
              'IVA',
              frozenTax == null ? '—' : ChileanUtils.formatCurrency(frozenTax),
              secondary: true,
            ),
          ] else if (taxSummary.isValid) ...[
            _buildSummaryMetric(
              taxSummary.netLabel,
              ChileanUtils.formatCurrency(taxSummary.netAmount.toDouble()),
            ),
            const SizedBox(height: 12),
            _buildSummaryMetric(
              taxSummary.ivaLabel,
              ChileanUtils.formatCurrency(taxSummary.taxAmount.toDouble()),
              secondary: true,
            ),
          ] else ...[
            _buildTaxConfigurationWarning(
              taxSummary.checkoutBlockMessage ??
                  'No podemos validar los impuestos de este carrito.',
            ),
            const SizedBox(height: 12),
            _buildSummaryMetric(
              'Total productos',
              knownGross == null
                  ? '—'
                  : ChileanUtils.formatCurrency(knownGross.toDouble()),
            ),
          ],
          const SizedBox(height: 12),
          _buildSummaryMetric(
            (snapshot?.handoff.deliveryType ?? _deliveryType) == 'pickup'
                ? 'Retiro'
                : 'Envío',
            shippingLabel,
            secondary: true,
          ),
          if (!usesDurableSnapshot &&
              shippingQuote != null &&
              !shippingQuote.isPickup) ...[
            const SizedBox(height: 8),
            Text(
              'IVA incluido · entrega estimada entre '
              '${shippingQuote.estimatedMinBusinessDays} y '
              '${shippingQuote.estimatedMaxBusinessDays} días hábiles.',
              style: _storeTheme.text.bodySmall?.copyWith(
                fontSize: 12,
                color: _storeTheme.textMuted,
                height: 1.45,
              ),
            ),
          ],
          if (!usesDurableSnapshot && _shippingQuoteLoading) ...[
            const SizedBox(height: 12),
            const LinearProgressIndicator(minHeight: 2),
          ],
          if (!usesDurableSnapshot && _shippingQuoteError != null) ...[
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.error_outline,
                  size: 18,
                  color: _storeTheme.error,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _shippingQuoteError!,
                    style: _storeTheme.text.bodySmall?.copyWith(
                      fontSize: 13,
                      color: _storeTheme.error,
                      height: 1.4,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: _shippingQuoteLoading
                      ? null
                      : () => _loadShippingQuote(force: true),
                  child: const Text('REINTENTAR'),
                ),
              ],
            ),
          ],
          const SizedBox(height: 18),
          Container(
            width: double.infinity,
            height: 1,
            color: _storeTheme.line,
          ),
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                'TOTAL',
                style: _storeTheme.text.labelSmall?.copyWith(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: _storeTheme.textSecondary,
                  letterSpacing: 0.8,
                ),
              ),
              Text(
                orderTotalLabel,
                style: _storeTheme.text.displaySmall?.copyWith(
                  fontSize: 44,
                  fontWeight: FontWeight.w700,
                  color: _storeTheme.primary,
                  height: 0.95,
                ),
              ),
            ],
          ),
          const SizedBox(height: 26),
          if (recoveryMessage != null) ...[
            Container(
              key: ValueKey(
                _submission.hasReceipt
                    ? 'checkout-post-order-recovery'
                    : 'checkout-outcome-unknown-recovery',
              ),
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 12,
              ),
              decoration: BoxDecoration(
                color: _storeTheme.warningSurface,
                border: Border(
                  left: BorderSide(color: _storeTheme.warning, width: 3),
                ),
              ),
              child: Text(
                recoveryMessage,
                style: _storeTheme.text.bodySmall?.copyWith(
                  fontSize: 13,
                  color: _storeTheme.onWarningSurface,
                  height: 1.45,
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _isProcessing ||
                      _sessionRestoring ||
                      _sessionStorageUnavailable ||
                      !canPlaceOrResumeOrder
                  ? null
                  : _placeOrder,
              style: FilledButton.styleFrom(
                backgroundColor: _storeTheme.primary,
                foregroundColor: _storeTheme.onPrimary,
                padding: const EdgeInsets.symmetric(vertical: 18),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
              child: _isProcessing
                  ? SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: _storeTheme.onPrimary,
                      ),
                    )
                  : Text(
                      _submission.hasReceipt
                          ? 'CONTINUAR CON PEDIDO'
                          : _submission.hasCreationAttempt
                              ? 'REINTENTAR CONFIRMACIÓN'
                              : 'REALIZAR PEDIDO',
                    ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: _isProcessing || _sessionRestoring || _checkoutLocked
                  ? null
                  : () => PublicStoreLayout.navigateToHref(context, '/carrito'),
              style: OutlinedButton.styleFrom(
                foregroundColor: _storeTheme.primary,
                side: BorderSide(color: _storeTheme.primary),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
              child: const Text('VOLVER AL CARRITO'),
            ),
          ),
          const SizedBox(height: 26),
          Container(
            width: double.infinity,
            height: 1,
            color: _storeTheme.line,
          ),
          const SizedBox(height: 18),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 7,
                height: 7,
                margin: const EdgeInsets.only(top: 6),
                decoration: BoxDecoration(
                  color: _storeTheme.primary,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Tus datos están protegidos y serán utilizados únicamente para procesar tu pedido.',
                  style: _storeTheme.text.bodyMedium?.copyWith(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: _storeTheme.textPrimary,
                    height: 1.5,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFormSection({
    required String title,
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: _storeTheme.softSurface,
        border: Border(
          top: BorderSide(color: _storeTheme.line),
          bottom: BorderSide(color: _storeTheme.line),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.toUpperCase(),
            style: _storeTheme.text.headlineSmall?.copyWith(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: _storeTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 18),
          child,
        ],
      ),
    );
  }

  InputDecoration _fieldDecoration({
    required String label,
    required IconData icon,
    String? hintText,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hintText,
      prefixIcon: Icon(icon, color: _storeTheme.textSecondary, size: 20),
      filled: true,
      fillColor: _storeTheme.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: BorderSide(color: _storeTheme.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: BorderSide(color: _storeTheme.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: BorderSide(color: _storeTheme.primary, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: BorderSide(color: _storeTheme.error),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: BorderSide(color: _storeTheme.error, width: 1.5),
      ),
    );
  }

  Widget _buildPaymentMethodSection() {
    if (_paymentCapabilitiesLoading) {
      return Row(
        key: const ValueKey('checkout-payment-capabilities-loading'),
        children: [
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: _storeTheme.primary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Verificando medios de pago disponibles…',
              style: _storeTheme.text.bodyMedium?.copyWith(
                color: _storeTheme.textSecondary,
              ),
            ),
          ),
        ],
      );
    }

    final capabilities = _paymentCapabilities;
    final availableMethods =
        capabilities?.availableMethods ?? const <PublicCheckoutPaymentCode>[];
    if (_paymentCapabilitiesError != null || availableMethods.isEmpty) {
      final tenantId = context.read<PublicStoreTenantProvider>().tenantId;
      return Container(
        key: const ValueKey('checkout-payment-capabilities-unavailable'),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: _storeTheme.warningSurface,
          border: Border(
            left: BorderSide(color: _storeTheme.warning, width: 3),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _paymentCapabilitiesError ??
                  'Esta tienda todavía no tiene un medio de pago disponible.',
              style: _storeTheme.text.bodySmall?.copyWith(
                color: _storeTheme.onWarningSurface,
                height: 1.45,
              ),
            ),
            if (_paymentCapabilitiesError != null) ...[
              const SizedBox(height: 8),
              TextButton(
                onPressed: _checkoutLocked
                    ? null
                    : () => unawaited(
                          _loadPaymentCapabilities(tenantId, force: true),
                        ),
                child: const Text('REINTENTAR'),
              ),
            ],
          ],
        ),
      );
    }

    return RadioGroup<String>(
      groupValue: _paymentMethod,
      onChanged: (value) {
        if (_checkoutLocked || value == null) return;
        setState(() => _paymentMethod = value);
      },
      child: Column(
        children: [
          for (var index = 0; index < availableMethods.length; index += 1)
            _buildPaymentOptionForCode(
              availableMethods[index],
              isLast: index == availableMethods.length - 1,
              showRecommended: availableMethods.length > 1 && index == 0,
            ),
        ],
      ),
    );
  }

  Widget _buildPaymentOptionForCode(
    PublicCheckoutPaymentCode code, {
    required bool isLast,
    required bool showRecommended,
  }) {
    return switch (code) {
      PublicCheckoutPaymentCode.mercadopago => _buildPaymentOption(
          value: code.wireValue,
          title: 'MercadoPago',
          subtitle:
              'Pago seguro con tarjeta de crédito, débito o saldo de Mercado Pago.',
          badgeLabel: showRecommended ? 'RECOMENDADO' : null,
          isLast: isLast,
        ),
      PublicCheckoutPaymentCode.transfer => _buildPaymentOption(
          value: code.wireValue,
          title: 'Transferencia bancaria',
          subtitle: 'Recibirás los datos para completar la transferencia.',
          badgeLabel: showRecommended ? 'RECOMENDADO' : null,
          isLast: isLast,
        ),
    };
  }

  Widget _buildPaymentOption({
    required String value,
    required String title,
    required String subtitle,
    String? badgeLabel,
    bool isLast = false,
  }) {
    final isSelected = _paymentMethod == value;

    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: isLast ? Colors.transparent : _storeTheme.line,
          ),
        ),
      ),
      child: InkWell(
        onTap: _checkoutLocked
            ? null
            : () => setState(() => _paymentMethod = value),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Radio<String>(
                value: value,
                activeColor: _storeTheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            title,
                            style: _storeTheme.text.bodyMedium?.copyWith(
                              fontSize: 15,
                              fontWeight: isSelected
                                  ? FontWeight.w700
                                  : FontWeight.w600,
                              color: _storeTheme.textPrimary,
                            ),
                          ),
                        ),
                        if (badgeLabel != null) ...[
                          const SizedBox(width: 8),
                          _buildMiniPill(badgeLabel),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: _storeTheme.text.bodySmall?.copyWith(
                        fontSize: 13,
                        color: _storeTheme.textSecondary,
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryProductRow(CartItem item, {bool isLast = false}) {
    final commerce = item.commerce;
    final displayImageUrl =
        commerce.imageUrls.isNotEmpty ? commerce.imageUrls.first : null;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: isLast ? Colors.transparent : _storeTheme.line,
          ),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 62,
            height: 62,
            color: _storeTheme.softSurface,
            padding: const EdgeInsets.all(8),
            child: displayImageUrl != null
                ? Image.network(
                    displayImageUrl,
                    fit: BoxFit.contain,
                    alignment: Alignment.center,
                    errorBuilder: (context, error, stackTrace) {
                      return Icon(
                        Icons.image_not_supported_outlined,
                        size: 22,
                        color: _storeTheme.textMuted,
                      );
                    },
                  )
                : Icon(
                    Icons.pedal_bike_outlined,
                    size: 22,
                    color: _storeTheme.textMuted,
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  commerce.title,
                  style: _storeTheme.text.bodyMedium?.copyWith(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: _storeTheme.textPrimary,
                    height: 1.45,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                Text(
                  'Cantidad: ${item.quantity}',
                  style: _storeTheme.text.bodySmall?.copyWith(
                    fontSize: 12,
                    color: _storeTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            ChileanUtils.formatCurrency(item.subtotal),
            style: _storeTheme.text.bodyMedium?.copyWith(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: _storeTheme.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  double? _snapshotAmount(
    CheckoutSessionSnapshot snapshot,
    String key,
  ) {
    final value = snapshot.orderData[key];
    if (value is! num) return null;
    final amount = value.toDouble();
    return amount.isFinite && amount >= 0 ? amount : null;
  }

  Widget _buildSnapshotSummaryProductRow(
    Map<String, dynamic> item, {
    bool isLast = false,
  }) {
    final productName = item['product_name']?.toString() ?? 'Producto';
    final productSku = item['product_sku']?.toString().trim() ?? '';
    final quantity = item['quantity'] as int;
    final subtotal = (item['subtotal'] as num).toDouble();

    return Container(
      key: ValueKey('checkout-snapshot-item-${item['product_id']}'),
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: isLast ? Colors.transparent : _storeTheme.line,
          ),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 62,
            height: 62,
            color: _storeTheme.softSurface,
            alignment: Alignment.center,
            child: Icon(
              Icons.receipt_long_outlined,
              size: 24,
              color: _storeTheme.textMuted,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  productName,
                  style: _storeTheme.text.bodyMedium?.copyWith(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: _storeTheme.textPrimary,
                    height: 1.45,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                Text(
                  [
                    if (productSku.isNotEmpty) 'SKU: $productSku',
                    'Cantidad: $quantity',
                  ].join(' · '),
                  style: _storeTheme.text.bodySmall?.copyWith(
                    fontSize: 12,
                    color: _storeTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            ChileanUtils.formatCurrency(subtotal),
            style: _storeTheme.text.bodyMedium?.copyWith(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: _storeTheme.textPrimary,
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
            color:
                secondary ? _storeTheme.textSecondary : _storeTheme.textPrimary,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontFamily: null,
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color:
                secondary ? _storeTheme.textSecondary : _storeTheme.textPrimary,
          ),
        ),
      ],
    );
  }

  Widget _buildTaxConfigurationWarning(String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: _storeTheme.warningSurface,
        border: Border(
          left: BorderSide(color: _storeTheme.warning, width: 3),
        ),
      ),
      child: Text(
        message,
        style: _storeTheme.text.bodySmall?.copyWith(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: _storeTheme.onWarningSurface,
          height: 1.45,
        ),
      ),
    );
  }

  Widget _buildMiniPill(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: _storeTheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: _storeTheme.text.labelSmall?.copyWith(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: _storeTheme.primary,
          letterSpacing: 0.7,
        ),
      ),
    );
  }

  Widget _buildSectionHeading(String title) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title.toUpperCase(),
          style: _storeTheme.text.headlineMedium?.copyWith(
            fontSize: 32,
            fontWeight: FontWeight.w700,
            color: _storeTheme.textPrimary,
            height: 1,
          ),
        ),
        const SizedBox(height: 10),
        Container(
          width: 72,
          height: 2,
          color: _storeTheme.primary,
        ),
      ],
    );
  }
}
