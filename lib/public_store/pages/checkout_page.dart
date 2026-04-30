import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_typeahead/flutter_typeahead.dart' as typeahead;
import '../utils/web_utils.dart' as web_utils;
import '../theme/public_store_theme.dart';
import '../providers/cart_provider.dart';
import '../providers/public_store_tenant_provider.dart';
import '../services/customer_account_service.dart';
import '../services/address_autocomplete_service.dart';
import '../../modules/website/services/website_service.dart';
import '../../modules/website/services/mercadopago_service.dart';
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
  static const Color _logoBlue = Color(0xFF093357);
  static const Color _warmLine = Color(0xFFE8E2D8);
  static const Color _warmSurface = Color(0xFFF7F4EE);
  static const Color _softSurface = Color(0xFFFCFBF8);

  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController();
  final _notesController = TextEditingController();
  final _accountPasswordController = TextEditingController();
  final _accountPasswordConfirmController = TextEditingController();

  String _paymentMethod =
      'mercadopago'; // mercadopago, transfer, cash_on_delivery
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
      final formatted = resolved.formattedAddress;
      _addressController.text =
          formatted.isNotEmpty ? formatted : resolved.formatForDisplay();
      _addressLabelController.text = address.label;
      _saveAddressToAccount = false;
    });

    if (_nameController.text.isEmpty) {
      _nameController.text = address.recipientName;
    }

    if (_phoneController.text.isEmpty) {
      _phoneController.text = address.phone;
    }
  }

  void _applyResolvedAddress(ResolvedAddress resolved) {
    setState(() {
      _selectedAddress = null;
      _resolvedAddress = resolved;
      final formatted = resolved.formattedAddress;
      _addressController.text =
          formatted.isNotEmpty ? formatted : resolved.formatForDisplay();
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
            backgroundColor: Colors.red,
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
      streetAddress: resolved.street.isNotEmpty
          ? resolved.street
          : _addressController.text.trim(),
      streetNumber: resolved.streetNumber,
      apartment: resolved.apartment,
      comuna: resolved.comuna.isNotEmpty ? resolved.comuna : resolved.city,
      city: resolved.city.isNotEmpty ? resolved.city : resolved.comuna,
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
    final manualAddress = _addressController.text.trim();
    return _resolvedAddress ??
        ResolvedAddress(
          formattedAddress: manualAddress,
          street: manualAddress,
          comuna: '',
          city: '',
          region: '',
        );
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
      final resolvedAddress = _shippingAddressForOrder();
      debugPrint(
          '🔵 [Checkout] Profile: ${profile != null ? "exists" : "null"}, shipping address prepared');

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

      // ============================================================================
      // TAX HANDLING BASED ON PAYMENT METHOD
      // ============================================================================
      debugPrint(
          '🔵 [Checkout] Calculating tax... paymentMethod: $_paymentMethod');
      // MercadoPago/Card: IVA is charged (tax_included)
      // Wire Transfer/Cash: No IVA (no_tax) per Chilean informal sale rules
      // ============================================================================
      final bool chargesIva =
          _paymentMethod == 'mercadopago' || _paymentMethod == 'card';
      debugPrint('🔵 [Checkout] chargesIva: $chargesIva');
      final double taxAmount = chargesIva ? cart.ivaAmount : 0.0;
      debugPrint('🔵 [Checkout] taxAmount: $taxAmount');
      final double subtotalAmount = chargesIva ? cart.subtotal : cart.total;
      debugPrint('🔵 [Checkout] subtotalAmount: $subtotalAmount');

      debugPrint('🔵 [Checkout] Creating orderData map...');
      // Create order data (database will generate id and orderNumber)
      final orderData = {
        'tenant_id': tenantId, // ⚠️ REQUIRED for multi-tenant isolation
        'customer_email': _emailController.text.trim(),
        'customer_name': _nameController.text.trim(),
        'customer_phone': _phoneController.text.trim(),
        'customer_address': resolvedAddress.formatForDisplay().isNotEmpty
            ? resolvedAddress.formatForDisplay()
            : _addressController.text.trim(),
        'delivery_type': 'shipping',
        'shipping_address_line1': resolvedAddress.street.isNotEmpty
            ? [
                resolvedAddress.street,
                resolvedAddress.streetNumber,
              ].whereType<String>().where((value) => value.isNotEmpty).join(' ')
            : _addressController.text.trim(),
        'shipping_address_line2': resolvedAddress.apartment,
        'shipping_city': resolvedAddress.city.isNotEmpty
            ? resolvedAddress.city
            : resolvedAddress.comuna,
        'shipping_state':
            resolvedAddress.region.isNotEmpty ? resolvedAddress.region : null,
        'shipping_postal_code': resolvedAddress.postalCode,
        'shipping_country': 'Chile',
        'subtotal': subtotalAmount,
        'tax_amount': taxAmount,
        'shipping_cost': 0, // Will be calculated later
        'discount_amount': 0,
        'total': cart.total, // Total stays the same (what customer pays)
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
        return {
          'tenant_id': tenantId, // ⚠️ REQUIRED for multi-tenant isolation
          'product_id': item.product.id,
          'product_name': item.product.name,
          'product_sku': item.product.sku,
          'quantity': item.quantity,
          'unit_price': item.product.price,
          'subtotal': item.product.price * item.quantity,
        };
      }).toList();
      debugPrint(
          '🔵 [Checkout] orderItems created: ${orderItems.length} items');

      debugPrint('🔵 [Checkout] Calling websiteService.createOrder()...');
      final orderId = await websiteService.createOrder(orderData, orderItems);
      debugPrint('🔵 [Checkout] ✅ Order created! orderId: $orderId');

      if (!mounted) return;

      final accountMessage = await _createAccountFromCheckout(accountService);
      if (accountMessage != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(accountMessage),
              duration: const Duration(seconds: 6)),
        );
      }

      if ((_accountService?.isAuthenticated ?? false) &&
          _saveAddressToAccount &&
          profile != null &&
          profile['id'] != null) {
        await _saveAddressForCustomer(
          accountService,
          resolvedAddress,
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

          final order = await websiteService.getOrderById(orderId);
          if (order == null) {
            debugPrint('❌ [Checkout] Order not found: $orderId');
            throw Exception('Order not found');
          }
          debugPrint('✅ [Checkout] Order found: ${order.orderNumber}');

          debugPrint('🔵 [Checkout] Creating MercadoPago preference...');
          final preference = await mercadopagoService.createPreference(
            orderId: orderId,
            orderNumber: order.orderNumber,
            total: cart.total,
            items: cart.items
                .map((item) => {
                      'title': item.product.name,
                      'quantity': item.quantity,
                      'unit_price': item.product.price,
                    })
                .toList(),
            customerEmail: _emailController.text.trim(),
            customerName: _nameController.text.trim(),
          );
          debugPrint('✅ [Checkout] Preference created: ${preference.keys}');

          // Open MercadoPago checkout
          final initPoint = preference['init_point'] as String?;
          debugPrint('🔵 [Checkout] init_point: $initPoint');

          if (initPoint == null || initPoint.isEmpty) {
            debugPrint('❌ [Checkout] No init_point in preference!');
            throw Exception('MercadoPago no devolvió URL de pago');
          }

          debugPrint('🚀 [Checkout] Redirecting to MercadoPago: $initPoint');
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
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 10),
            ),
          );
        }
      } else {
        // Traditional payment methods (transfer, cash on delivery)
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
    _accountService ??=
        Provider.of<CustomerAccountService>(context, listen: false);

    debugPrint(
        '🛒 [CheckoutPage.build] cart.isEmpty: ${cart.isEmpty}, items: ${cart.items.length}');

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
        const Text(
          'Completa tus datos de contacto, entrega y pago para confirmar tu pedido con el mismo lenguaje claro del resto de la tienda.',
          style: TextStyle(
            fontFamily: PublicStoreTheme.defaultBodyFont,
            fontSize: 15,
            color: PublicStoreTheme.textSecondary,
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
                  color: _softSurface,
                  border: Border.all(color: _warmLine),
                ),
                child: const Icon(
                  Icons.shopping_cart_outlined,
                  size: 62,
                  color: PublicStoreTheme.textMuted,
                ),
              ),
              const SizedBox(height: 32),
              _buildSectionHeading('No hay productos para finalizar'),
              const SizedBox(height: 16),
              const Text(
                'Vuelve al catálogo, revisa productos y agrega artículos antes de continuar al checkout.',
                style: TextStyle(
                  fontFamily: PublicStoreTheme.defaultBodyFont,
                  fontSize: 15,
                  color: PublicStoreTheme.textSecondary,
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
                  backgroundColor: _logoBlue,
                  foregroundColor: Colors.white,
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
                    if (!value.contains('@')) {
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
                    return null;
                  },
                ),
                if (!(_accountService?.isAuthenticated ?? false)) ...[
                  const SizedBox(height: 18),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(color: _warmLine),
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
                          title: const Text(
                            'Crear una cuenta con estos datos',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: Colors.black87,
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
            title: '2. Dirección de envío',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if ((_accountService?.isAuthenticated ?? false) &&
                    _savedAddresses.isNotEmpty) ...[
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
                if (_addressAutocompleteService != null &&
                    _addressAutocompleteService!.isEnabled) ...[
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
                          label: 'Dirección completa *',
                          icon: Icons.location_on_outlined,
                          hintText: 'Busca tu dirección y selecciónala',
                        ),
                        maxLines: 2,
                        onChanged: (value) {
                          if (value.trim().isEmpty) {
                            setState(() {
                              _selectedAddress = null;
                              _resolvedAddress = null;
                            });
                          }
                        },
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'La dirección es requerida';
                          }
                          return null;
                        },
                      );
                    },
                    itemBuilder: (context, suggestion) => ListTile(
                      leading: const Icon(Icons.place_outlined),
                      title: Text(suggestion.description),
                    ),
                    loadingBuilder: (context) => const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Center(
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                    emptyBuilder: (context) => const Padding(
                      padding: EdgeInsets.all(12),
                      child: Text('No encontramos coincidencias'),
                    ),
                    onSelected: (suggestion) async {
                      final resolved = await _addressAutocompleteService
                          ?.resolvePlace(suggestion.placeId);
                      if (resolved != null) {
                        _applyResolvedAddress(resolved);
                        _addressAutocompleteService?.resetSessionToken();
                      }
                    },
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Utilizamos Google Maps para validar la dirección de entrega.',
                    style: TextStyle(
                      fontFamily: PublicStoreTheme.defaultBodyFont,
                      fontSize: 12,
                      color: PublicStoreTheme.textSecondary,
                    ),
                  ),
                  if ((_accountService?.isAuthenticated ?? false) &&
                      _selectedAddress == null) ...[
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
                  ] else if ((_accountService?.isAuthenticated ?? false) &&
                      _selectedAddress != null) ...[
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () =>
                            context.go('/tienda/cuenta/direcciones'),
                        style: TextButton.styleFrom(
                          foregroundColor: _logoBlue,
                          padding: EdgeInsets.zero,
                          minimumSize: const Size(0, 0),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        icon: const Icon(Icons.open_in_new, size: 16),
                        label:
                            const Text('Gestionar mis direcciones guardadas'),
                      ),
                    ),
                  ],
                ] else ...[
                  TextFormField(
                    controller: _addressController,
                    decoration: _fieldDecoration(
                      label: 'Dirección completa *',
                      icon: Icons.location_on_outlined,
                      hintText: 'Calle, número, comuna, región',
                    ),
                    maxLines: 3,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'La dirección es requerida';
                      }
                      return null;
                    },
                  ),
                  if (_addressAutocompleteService != null &&
                      !_addressAutocompleteService!.isEnabled)
                    const Padding(
                      padding: EdgeInsets.only(top: 8.0),
                      child: Text(
                        'Puedes escribir la dirección manualmente. Revisaremos los datos antes del despacho si hace falta.',
                        style: TextStyle(
                          fontFamily: PublicStoreTheme.defaultBodyFont,
                          fontSize: 12,
                          color: PublicStoreTheme.textSecondary,
                        ),
                      ),
                    ),
                ],
              ],
            ),
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
                        'Pago seguro con tarjeta de crédito, débito o efectivo.',
                    badgeLabel: 'RECOMENDADO',
                  ),
                  _buildPaymentOption(
                    value: 'transfer',
                    title: 'Transferencia bancaria',
                    subtitle:
                        'Recibirás los datos para completar la transferencia.',
                  ),
                  _buildPaymentOption(
                    value: 'cash_on_delivery',
                    title: 'Pago contra entrega',
                    subtitle: 'Paga cuando recibas tu pedido.',
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

  Widget _buildOrderSummary(CartProvider cart, {required bool isMobile}) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(isMobile ? 20 : 24),
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
            'RESUMEN DEL PEDIDO',
            style: TextStyle(
              fontFamily: PublicStoreTheme.defaultHeadingFont,
              fontSize: isMobile ? 28 : 32,
              fontWeight: FontWeight.w700,
              color: Colors.black87,
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
            color: _warmLine,
          ),
          const SizedBox(height: 18),
          _buildSummaryMetric(
            'Subtotal',
            ChileanUtils.formatCurrency(cart.subtotal),
          ),
          const SizedBox(height: 12),
          _buildSummaryMetric(
            'IVA (19%)',
            ChileanUtils.formatCurrency(cart.ivaAmount),
            secondary: true,
          ),
          const SizedBox(height: 12),
          _buildSummaryMetric(
            'Envío',
            'Por calcular',
            secondary: true,
          ),
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
                ChileanUtils.formatCurrency(cart.total),
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
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _isProcessing ? null : _placeOrder,
              style: FilledButton.styleFrom(
                backgroundColor: _logoBlue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 18),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
              child: _isProcessing
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
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
                foregroundColor: _logoBlue,
                side: const BorderSide(color: _logoBlue),
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
            color: _warmLine,
          ),
          const SizedBox(height: 18),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 7,
                height: 7,
                margin: const EdgeInsets.only(top: 6),
                decoration: const BoxDecoration(
                  color: _logoBlue,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Tus datos están protegidos y serán utilizados únicamente para procesar tu pedido.',
                  style: TextStyle(
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

  InputDecoration _fieldDecoration({
    required String label,
    required IconData icon,
    String? hintText,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hintText,
      prefixIcon: Icon(icon, color: PublicStoreTheme.textSecondary, size: 20),
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: const BorderSide(color: _warmLine),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: const BorderSide(color: _warmLine),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: const BorderSide(color: _logoBlue, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: const BorderSide(color: PublicStoreTheme.error),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: const BorderSide(color: PublicStoreTheme.error, width: 1.5),
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
            color: isLast ? Colors.transparent : _warmLine,
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
                activeColor: _logoBlue,
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
                            style: TextStyle(
                              fontFamily: PublicStoreTheme.defaultBodyFont,
                              fontSize: 15,
                              fontWeight: isSelected
                                  ? FontWeight.w700
                                  : FontWeight.w600,
                              color: Colors.black87,
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
                      style: const TextStyle(
                        fontFamily: PublicStoreTheme.defaultBodyFont,
                        fontSize: 13,
                        color: PublicStoreTheme.textSecondary,
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
    final displayImageUrl =
        item.product.imageUrlOptimized ?? item.product.imageUrl;

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
          Container(
            width: 62,
            height: 62,
            color: _softSurface,
            padding: const EdgeInsets.all(8),
            child: displayImageUrl != null
                ? Image.network(
                    displayImageUrl,
                    fit: BoxFit.contain,
                    alignment: Alignment.center,
                    errorBuilder: (context, error, stackTrace) {
                      return const Icon(
                        Icons.image_not_supported_outlined,
                        size: 22,
                        color: PublicStoreTheme.textMuted,
                      );
                    },
                  )
                : const Icon(
                    Icons.pedal_bike_outlined,
                    size: 22,
                    color: PublicStoreTheme.textMuted,
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.product.name,
                  style: const TextStyle(
                    fontFamily: PublicStoreTheme.defaultBodyFont,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                    height: 1.45,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                Text(
                  'Cantidad: ${item.quantity}',
                  style: const TextStyle(
                    fontFamily: PublicStoreTheme.defaultBodyFont,
                    fontSize: 12,
                    color: PublicStoreTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
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

  Widget _buildMiniPill(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: _logoBlue.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontFamily: PublicStoreTheme.defaultBodyFont,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: _logoBlue,
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
          style: const TextStyle(
            fontFamily: PublicStoreTheme.defaultHeadingFont,
            fontSize: 32,
            fontWeight: FontWeight.w700,
            color: Colors.black,
            height: 1,
          ),
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
}
