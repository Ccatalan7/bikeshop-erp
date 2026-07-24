import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_typeahead/flutter_typeahead.dart' as typeahead;
import 'package:uuid/uuid.dart';
import '../utils/web_utils.dart' as web_utils;
import '../theme/public_store_surface_theme.dart';
import '../models/public_commerce_product_projection.dart';
import '../providers/cart_provider.dart';
import '../providers/public_store_tenant_provider.dart';
import '../services/customer_account_service.dart';
import '../services/address_autocomplete_service.dart';
import '../services/meta_pixel_service.dart';
import '../services/public_order_access_token_store.dart';
import '../../modules/website/services/website_service.dart';
import '../../modules/website/services/mercadopago_service.dart';
import '../../modules/website/models/public_shipping_quote.dart';
import '../../modules/website/providers/website_edit_mode_provider.dart';
import '../../shared/utils/chilean_utils.dart';
import '../../shared/models/customer_address.dart';
import '../../shared/widgets/safe_layout_builder.dart';

class CheckoutPage extends StatefulWidget {
  const CheckoutPage({super.key});

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
  String _paymentMethod = 'mercadopago'; // mercadopago, transfer
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
  // Stable for this checkout page so a timeout/retry returns the same order.
  final String _checkoutIdempotencyKey = const Uuid().v4();

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

      final cart = context.read<CartProvider>();
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
        value: cart.total,
      );

      _handleCheckoutQueryParameters();
    });
  }

  @override
  void dispose() {
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
      if (!mounted || generation != _shippingQuoteGeneration) return null;
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

    service.setTenantId(context.read<PublicStoreTenantProvider>().tenantId);

    try {
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
    debugPrint('🔵 [Checkout] _placeOrder() CALLED!');

    if (!_formKey.currentState!.validate()) {
      debugPrint('🔵 [Checkout] Form validation FAILED');
      return;
    }
    debugPrint('🔵 [Checkout] Form validation PASSED');

    final cart = Provider.of<CartProvider>(context, listen: false);
    debugPrint('🔵 [Checkout] Cart items: ${cart.items.length}');

    if (cart.items.isEmpty) {
      debugPrint('🔵 [Checkout] Cart is EMPTY, showing snackbar');
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

    debugPrint('🔵 [Checkout] Setting _isProcessing = true');
    setState(() => _isProcessing = true);

    try {
      debugPrint('🔵 [Checkout] Getting services...');
      final websiteService =
          Provider.of<WebsiteService>(context, listen: false);
      debugPrint('🔵 [Checkout] Got WebsiteService');

      final mercadopagoService =
          Provider.of<MercadoPagoService>(context, listen: false);
      debugPrint('🔵 [Checkout] Got MercadoPagoService');

      final accountService = _accountService ??
          Provider.of<CustomerAccountService>(context, listen: false);
      debugPrint('🔵 [Checkout] Got CustomerAccountService');

      final profile = accountService.customerProfile;
      final isPickup = _deliveryType == 'pickup';
      final resolvedAddress = isPickup ? null : _shippingAddressForOrder();
      debugPrint(
          '🔵 [Checkout] Profile: ${profile != null ? "exists" : "null"}, delivery type: $_deliveryType');

      // ⚠️ CRITICAL: Get tenant_id from detected tenant (subdomain)
      debugPrint('🔵 [Checkout] Getting tenant provider...');
      final tenantProvider = context.read<PublicStoreTenantProvider>();
      debugPrint(
          '🔵 [Checkout] Got tenant provider, tenantId: ${tenantProvider.tenantId}');
      final tenantId = tenantProvider.tenantId;
      debugPrint('🔵 [Checkout] tenantId assigned: $tenantId');

      if (tenantId == null) {
        debugPrint('🔵 [Checkout] ❌ tenantId is NULL! Throwing exception...');
        throw Exception(
            'No se pudo detectar la tienda. Por favor recarga la página.');
      }
      debugPrint('🔵 [Checkout] ✅ tenantId is valid, continuing...');

      debugPrint('🔵 [Checkout] Creating orderData map...');
      // Create order data (database will generate id and orderNumber)
      final Map<String, dynamic> orderData = {
        'tenant_id': tenantId, // ⚠️ REQUIRED for multi-tenant isolation
        'checkout_idempotency_key': _checkoutIdempotencyKey,
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
      debugPrint(
          '🔵 [Checkout] orderData created: ${orderData.keys.join(', ')}');

      if (profile != null && profile['id'] != null) {
        orderData['customer_id'] = profile['id'];
        debugPrint('🔵 [Checkout] Added customer_id to orderData');
      }

      debugPrint('🔵 [Checkout] Creating orderItems...');
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
      debugPrint(
          '🔵 [Checkout] orderItems created: ${orderItems.length} items');

      debugPrint('🔵 [Checkout] Calling websiteService.createOrder()...');
      final checkoutAccess =
          await websiteService.createOrder(orderData, orderItems);
      final orderId = checkoutAccess.orderId;

      // Persist before any external redirect or local navigation. The token is
      // never appended to the URL, logged, or copied into Mercado Pago URLs.
      PublicOrderAccessTokenStore.save(
        orderId: orderId,
        accessToken: checkoutAccess.accessToken,
      );
      debugPrint('🔵 [Checkout] ✅ Secure order created');

      if (!mounted) return;

      final accountMessage = await _createAccountFromCheckout(accountService);
      if (accountMessage != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(accountMessage),
              duration: const Duration(seconds: 6)),
        );
      }

      if (!isPickup &&
          (_accountService?.isAuthenticated ?? false) &&
          _saveAddressToAccount &&
          profile != null &&
          profile['id'] != null) {
        await _saveAddressForCustomer(
          accountService,
          resolvedAddress!,
          profile['id'] as String,
        );
      }

      // Handle payment based on selected method
      if (_paymentMethod == 'mercadopago') {
        // Redirect to MercadoPago checkout
        try {
          debugPrint(
              '🔵 [Checkout] Starting MercadoPago flow for order: $orderId');

          // Initialize MercadoPago with tenant context
          debugPrint(
              '🔵 [Checkout] Initializing MercadoPago with tenant: $tenantId');
          await mercadopagoService.initialize(tenantId: tenantId);

          if (!mercadopagoService.isConfigured) {
            debugPrint('❌ [Checkout] MercadoPago not configured!');
            throw Exception(
                'MercadoPago no está configurado para esta tienda.');
          }
          debugPrint('✅ [Checkout] MercadoPago is configured');

          debugPrint('🔵 [Checkout] Creating MercadoPago preference...');
          final preference = await mercadopagoService.createPreference(
            orderId: orderId,
            orderAccessToken: checkoutAccess.accessToken,
          );
          debugPrint('✅ [Checkout] Preference created: ${preference.keys}');

          // Open MercadoPago checkout
          final initPoint = preference['init_point'] as String?;
          debugPrint(
            '🔵 [Checkout] MercadoPago checkout URL received: '
            '${initPoint?.isNotEmpty == true}',
          );

          if (initPoint == null || initPoint.isEmpty) {
            debugPrint('❌ [Checkout] No init_point in preference!');
            throw Exception('MercadoPago no devolvió URL de pago');
          }

          debugPrint('🚀 [Checkout] Redirecting to MercadoPago');
          if (kIsWeb) {
            // For web, use window.open to redirect to MercadoPago
            web_utils.WebUtils.openUrl(initPoint);
          } else {
            // For mobile/desktop, use url_launcher
            final url = Uri.parse(initPoint);
            if (await canLaunchUrl(url)) {
              await launchUrl(url, mode: LaunchMode.externalApplication);
            }
          }

          // Clear cart (only for non-web or after redirect)
          if (!kIsWeb) {
            while (cart.items.isNotEmpty) {
              cart.removeProduct(cart.items.first.product.id);
            }

            // Navigate to order confirmation
            if (mounted) {
              context.go('/tienda/pedido/$orderId');
            }
          }
        } catch (e, stackTrace) {
          debugPrint('❌ [Checkout] MercadoPago error: $e');
          debugPrint('❌ [Checkout] Stack trace: $stackTrace');
          if (!mounted) return;

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error al procesar pago con MercadoPago: $e'),
              backgroundColor: _storeTheme.error,
              duration: const Duration(seconds: 10),
            ),
          );
        }
      } else {
        // Offline payment methods such as bank transfer
        // Clear cart
        while (cart.items.isNotEmpty) {
          cart.removeProduct(cart.items.first.product.id);
        }

        // Navigate to order confirmation
        if (!mounted) return;
        context.go('/tienda/pedido/$orderId');
      }
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al crear pedido: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin
    final cart = context.watch<CartProvider>();
    context.watch<CustomerAccountService>();
    context.watch<PublicStoreTenantProvider>();
    _accountService ??=
        Provider.of<CustomerAccountService>(context, listen: false);

    debugPrint(
        '🛒 [CheckoutPage.build] cart.isEmpty: ${cart.isEmpty}, items: ${cart.items.length}');

    if (cart.isNotEmpty) {
      _scheduleShippingQuoteRefresh(cart);
    }

    // Get edit mode for key to prevent element reactivation conflicts
    final editProvider = context.watch<WebsiteEditModeProvider>();
    final modeKey = editProvider.isEditMode
        ? 'edit'
        : (editProvider.isPreviewMode ? 'preview' : 'normal');

    debugPrint('🛒 [CheckoutPage.build] Cart has items, showing checkout form');
    return MediaQueryLayoutBuilder(
      key: ValueKey('checkout_layout_$modeKey'),
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 980;
        final horizontalMargin = constraints.maxWidth < 760 ? 16.0 : 24.0;
        final verticalMargin = isMobile ? 28.0 : 44.0;

        if (cart.isEmpty) {
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
                    _buildCheckoutForm(isMobile: true),
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
                          _buildCheckoutForm(isMobile: false),
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
          'Completa tus datos de contacto, entrega y pago para confirmar tu pedido con el mismo lenguaje claro del resto de la tienda.',
          style: _storeTheme.text.bodyMedium?.copyWith(
            fontSize: 15,
            color: _storeTheme.textSecondary,
            height: 1.55,
          ),
        ),
      ],
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
                onPressed: () => context.go('/productos'),
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
                              if (value == null || value.length < 6) {
                                return 'Usa al menos 6 caracteres';
                              }
                              return null;
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
                              if (value != _accountPasswordController.text) {
                                return 'Las contraseñas no coinciden';
                              }
                              return null;
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
            child: RadioGroup<String>(
              groupValue: _paymentMethod,
              onChanged: (value) {
                if (value == null) return;
                setState(() => _paymentMethod = value);
              },
              child: Column(
                children: [
                  _buildPaymentOption(
                    value: 'mercadopago',
                    title: 'MercadoPago',
                    subtitle:
                        'Pago seguro con tarjeta de crédito, débito o saldo de Mercado Pago.',
                    badgeLabel: 'RECOMENDADO',
                  ),
                  _buildPaymentOption(
                    value: 'transfer',
                    title: 'Transferencia bancaria',
                    subtitle:
                        'Recibirás los datos para completar la transferencia.',
                    isLast: true,
                  ),
                ],
              ),
            ),
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
            if (value == null) return;
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
                onPressed: () => context.go('/tienda/cuenta/direcciones'),
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
        onTap: () => _selectDeliveryType(value),
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
    final taxSummary = cart.taxSummary;
    final hasCurrentShippingQuote = _hasCurrentShippingQuote(cart);
    final shippingQuote = hasCurrentShippingQuote ? _shippingQuote : null;
    final shippingLabel = shippingQuote == null
        ? (_shippingQuoteLoading ? 'Calculando…' : '—')
        : shippingQuote.isPickup
            ? 'Sin costo'
            : ChileanUtils.formatCurrency(
                shippingQuote.shippingGross.toDouble(),
              );
    final orderTotalLabel = shippingQuote == null
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
          if (taxSummary.isValid) ...[
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
          ],
          const SizedBox(height: 12),
          _buildSummaryMetric(
            _deliveryType == 'pickup' ? 'Retiro' : 'Envío',
            shippingLabel,
            secondary: true,
          ),
          if (shippingQuote != null && !shippingQuote.isPickup) ...[
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
          if (_shippingQuoteLoading) ...[
            const SizedBox(height: 12),
            const LinearProgressIndicator(minHeight: 2),
          ],
          if (_shippingQuoteError != null) ...[
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
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _isProcessing ||
                      _shippingQuoteLoading ||
                      !taxSummary.isValid ||
                      !hasCurrentShippingQuote
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
                  : const Text('REALIZAR PEDIDO'),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: _isProcessing ? null : () => context.go('/carrito'),
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
        onTap: () => setState(() => _paymentMethod = value),
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
