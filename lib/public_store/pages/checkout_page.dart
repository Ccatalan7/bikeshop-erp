import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:html' as html show window;
import 'package:flutter_typeahead/flutter_typeahead.dart' as typeahead;
import '../theme/public_store_theme.dart';
import '../providers/cart_provider.dart';
import '../services/customer_account_service.dart';
import '../services/address_autocomplete_service.dart';
import '../../modules/website/services/website_service.dart';
import '../../modules/website/services/mercadopago_service.dart';
import '../../shared/utils/chilean_utils.dart';
import '../../shared/models/customer_address.dart';

class CheckoutPage extends StatefulWidget {
  const CheckoutPage({super.key});

  @override
  State<CheckoutPage> createState() => _CheckoutPageState();
}

class _CheckoutPageState extends State<CheckoutPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController();
  final _notesController = TextEditingController();

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
      autocompleteService.initialize();

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
      html.window.history.replaceState(null, 'Checkout', cleaned.toString());
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

  Future<void> _placeOrder() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final cart = Provider.of<CartProvider>(context, listen: false);
    if (cart.items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('El carrito está vacío')),
      );
      return;
    }

    setState(() => _isProcessing = true);

    try {
      final websiteService =
          Provider.of<WebsiteService>(context, listen: false);
      final mercadopagoService =
          Provider.of<MercadoPagoService>(context, listen: false);
      final accountService = _accountService ??
          Provider.of<CustomerAccountService>(context, listen: false);

      final profile = accountService.customerProfile;
      final resolvedAddress = _resolvedAddress;

      // Create order data (database will generate id and orderNumber)
      final orderData = {
        'customer_email': _emailController.text.trim(),
        'customer_name': _nameController.text.trim(),
        'customer_phone': _phoneController.text.trim(),
        'customer_address': resolvedAddress?.formatForDisplay() ??
            _addressController.text.trim(),
        'subtotal': cart.subtotal,
        'tax_amount': cart.ivaAmount,
        'shipping_cost': 0, // Will be calculated later
        'discount_amount': 0,
        'total': cart.total,
        'status': 'pending',
        'payment_status': 'pending',
        'payment_method': _paymentMethod,
        'customer_notes': _notesController.text.trim().isNotEmpty
            ? _notesController.text.trim()
            : null,
      };

      if (profile != null && profile['id'] != null) {
        orderData['customer_id'] = profile['id'];
      }

      final orderItems = cart.items.map((item) {
        return {
          'product_id': item.product.id,
          'product_name': item.product.name,
          'product_sku': item.product.sku,
          'quantity': item.quantity,
          'unit_price': item.product.price,
          'subtotal': item.product.price * item.quantity,
        };
      }).toList();

      final orderId = await websiteService.createOrder(orderData, orderItems);

      if (!mounted) return;

      if ((_accountService?.isAuthenticated ?? false) &&
          _saveAddressToAccount &&
          resolvedAddress != null &&
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
          final order = await websiteService.getOrderById(orderId);
          if (order == null) throw Exception('Order not found');

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

          // Open MercadoPago checkout
          final initPoint = preference['init_point'] as String;

          if (kIsWeb) {
            // For web, use window.open to redirect to MercadoPago
            html.window.open(initPoint, '_self');
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
        } catch (e) {
          if (!mounted) return;

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error al procesar pago con MercadoPago: $e'),
              backgroundColor: Colors.red,
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
    final cart = context.watch<CartProvider>();
    context.watch<CustomerAccountService>();
    _accountService ??=
        Provider.of<CustomerAccountService>(context, listen: false);

    if (cart.isEmpty) {
      return _buildEmptyCart(context);
    }

    return Container(
      constraints: const BoxConstraints(maxWidth: 1200),
      margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Checkout Form (Left - 60%)
          Expanded(
            flex: 60,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Finalizar Compra',
                  style: Theme.of(context).textTheme.displaySmall,
                ),
                const SizedBox(height: 32),
                _buildCheckoutForm(),
              ],
            ),
          ),

          const SizedBox(width: 32),

          // Order Summary (Right - 40%)
          Expanded(
            flex: 40,
            child: _buildOrderSummary(context, cart),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyCart(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.shopping_cart_outlined,
            size: 64,
            color: PublicStoreTheme.textMuted,
          ),
          const SizedBox(height: 16),
          Text(
            'El carrito está vacío',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: () => context.go('/tienda/productos'),
            child: const Text('IR A COMPRAR'),
          ),
        ],
      ),
    );
  }

  Widget _buildCheckoutForm() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Customer Information
          Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '1. Información de Contacto',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 24),

                  // Name
                  TextFormField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      labelText: 'Nombre completo *',
                      prefixIcon: Icon(Icons.person_outline),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'El nombre es requerido';
                      }
                      return null;
                    },
                  ),

                  const SizedBox(height: 20),

                  // Email
                  TextFormField(
                    controller: _emailController,
                    decoration: const InputDecoration(
                      labelText: 'Correo electrónico *',
                      prefixIcon: Icon(Icons.email_outlined),
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

                  const SizedBox(height: 20),

                  // Phone
                  TextFormField(
                    controller: _phoneController,
                    decoration: const InputDecoration(
                      labelText: 'Teléfono *',
                      prefixIcon: Icon(Icons.phone_outlined),
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
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),

          // Shipping Address
          Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '2. Dirección de Envío',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 24),
                  if ((_accountService?.isAuthenticated ?? false) &&
                      _savedAddresses.isNotEmpty) ...[
                    DropdownButtonFormField<CustomerAddress>(
                      value: _selectedAddress,
                      decoration: const InputDecoration(
                        labelText: 'Usar dirección guardada',
                        prefixIcon: Icon(Icons.bookmark_outline),
                      ),
                      items: _savedAddresses
                          .map(
                            (address) => DropdownMenuItem<CustomerAddress>(
                              value: address,
                              child: Text(
                                '${address.label} • ${address.comuna}',
                              ),
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
                          decoration: const InputDecoration(
                            labelText: 'Dirección completa *',
                            prefixIcon: Icon(Icons.location_on_outlined),
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
                    Text(
                      'Utilizamos Google Maps para validar la dirección de entrega.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: PublicStoreTheme.textSecondary,
                          ),
                    ),
                    if ((_accountService?.isAuthenticated ?? false) &&
                        _selectedAddress == null) ...[
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _addressLabelController,
                        decoration: const InputDecoration(
                          labelText: 'Etiqueta (ej: Casa, Trabajo)',
                          prefixIcon: Icon(Icons.label_outline),
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
                        title:
                            const Text('Guardar esta dirección en mi cuenta'),
                      ),
                    ] else if ((_accountService?.isAuthenticated ?? false) &&
                        _selectedAddress != null) ...[
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: () =>
                              context.go('/tienda/cuenta/direcciones'),
                          icon: const Icon(Icons.open_in_new),
                          label:
                              const Text('Gestionar mis direcciones guardadas'),
                        ),
                      ),
                    ],
                  ] else ...[
                    TextFormField(
                      controller: _addressController,
                      decoration: const InputDecoration(
                        labelText: 'Dirección completa *',
                        prefixIcon: Icon(Icons.location_on_outlined),
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
                      Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: Text(
                          'Configura la clave de Google Places en Supabase para habilitar la búsqueda inteligente.',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: PublicStoreTheme.textSecondary),
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),

          // Payment Method
          Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '3. Método de Pago',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 24),
                  RadioListTile<String>(
                    value: 'mercadopago',
                    groupValue: _paymentMethod,
                    onChanged: (value) =>
                        setState(() => _paymentMethod = value!),
                    title: Row(
                      children: [
                        const Text('MercadoPago'),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade100,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'RECOMENDADO',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Colors.blue.shade700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    subtitle: const Text(
                        'Pago seguro con tarjeta de crédito/débito o efectivo'),
                    contentPadding: EdgeInsets.zero,
                  ),
                  RadioListTile<String>(
                    value: 'transfer',
                    groupValue: _paymentMethod,
                    onChanged: (value) =>
                        setState(() => _paymentMethod = value!),
                    title: const Text('Transferencia Bancaria'),
                    subtitle: const Text(
                        'Recibirás los datos para realizar la transferencia'),
                    contentPadding: EdgeInsets.zero,
                  ),
                  RadioListTile<String>(
                    value: 'cash_on_delivery',
                    groupValue: _paymentMethod,
                    onChanged: (value) =>
                        setState(() => _paymentMethod = value!),
                    title: const Text('Pago contra entrega'),
                    subtitle: const Text('Paga cuando recibas tu pedido'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),

          // Additional Notes
          Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Notas adicionales (opcional)',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _notesController,
                    decoration: const InputDecoration(
                      hintText: 'Alguna instrucción especial para tu pedido...',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 4,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOrderSummary(BuildContext context, CartProvider cart) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Resumen del Pedido',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 24),

            // Product List
            ...cart.items.map((item) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Thumbnail
                    Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        color: PublicStoreTheme.surface,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: item.product.imageUrl != null
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.network(
                                item.product.imageUrl!,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) {
                                  return const Icon(Icons.image_not_supported,
                                      size: 24);
                                },
                              ),
                            )
                          : const Icon(Icons.pedal_bike, size: 24),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.product.name,
                            style: Theme.of(context).textTheme.bodyMedium,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Cantidad: ${item.quantity}',
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: PublicStoreTheme.textSecondary,
                                    ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      ChileanUtils.formatCurrency(item.subtotal),
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ],
                ),
              );
            }).toList(),

            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 16),

            // Subtotal
            _buildSummaryRow(
              context,
              'Subtotal',
              ChileanUtils.formatCurrency(cart.subtotal),
            ),
            const SizedBox(height: 12),

            // IVA
            _buildSummaryRow(
              context,
              'IVA (19%)',
              ChileanUtils.formatCurrency(cart.ivaAmount),
              isSecondary: true,
            ),

            const SizedBox(height: 12),

            // Shipping
            _buildSummaryRow(
              context,
              'Envío',
              'Por calcular',
              isSecondary: true,
            ),

            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 16),

            // Total
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Total',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                Text(
                  ChileanUtils.formatCurrency(cart.total),
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        color: PublicStoreTheme.primaryBlue,
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),

            const SizedBox(height: 32),

            // Place Order Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isProcessing ? null : _placeOrder,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 20),
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

            // Back to Cart
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed:
                    _isProcessing ? null : () => context.go('/tienda/carrito'),
                child: const Text('VOLVER AL CARRITO'),
              ),
            ),

            const SizedBox(height: 24),

            // Security Notice
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: PublicStoreTheme.info.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border:
                    Border.all(color: PublicStoreTheme.info.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.lock_outline,
                    color: PublicStoreTheme.info,
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Tus datos están protegidos y serán utilizados únicamente para procesar tu pedido.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: PublicStoreTheme.info,
                          ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryRow(
    BuildContext context,
    String label,
    String value, {
    bool isSecondary = false,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: isSecondary
                    ? PublicStoreTheme.textSecondary
                    : PublicStoreTheme.textPrimary,
              ),
        ),
        Text(
          value,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: isSecondary
                    ? PublicStoreTheme.textSecondary
                    : PublicStoreTheme.textPrimary,
              ),
        ),
      ],
    );
  }
}
