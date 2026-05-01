import 'package:flutter/material.dart';
import 'package:flutter_typeahead/flutter_typeahead.dart' as typeahead;
import 'package:provider/provider.dart';
import '../providers/public_store_tenant_provider.dart';
import '../services/address_autocomplete_service.dart';
import '../services/customer_account_service.dart';
import '../theme/public_store_theme.dart';
import '../../shared/models/customer_address.dart';
import '../widgets/customer_portal_layout.dart';

class CustomerAddressesPage extends StatelessWidget {
  const CustomerAddressesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final accountService = context.watch<CustomerAccountService>();

    return CustomerPortalLayout(
      title: 'Mis Direcciones',
      headerAction: FilledButton.icon(
        onPressed: () => _showAddressDialog(context, null),
        icon: const Icon(Icons.add, size: 18),
        label: const Text('Nueva dirección'),
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFF102A43),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildIntro(),
          const SizedBox(height: 18),
          if (accountService.addresses.isEmpty)
            _buildEmptyState(context)
          else
            _buildAddressesList(context, accountService),
        ],
      ),
    );
  }

  Widget _buildAddressesList(
      BuildContext context, CustomerAccountService accountService) {
    // Sort: Default first
    final addresses = List<CustomerAddress>.from(accountService.addresses);
    addresses.sort((a, b) => (b.isDefault ? 1 : 0) - (a.isDefault ? 1 : 0));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final useGrid = constraints.maxWidth >= 760;
            if (!useGrid) {
              return Column(
                children: addresses.map((address) {
                  return _AddressCard(
                    address: address,
                    onEdit: () => _showAddressDialog(context, address),
                    onDelete: () => _confirmDelete(context, address),
                    onSetDefault: () async {
                      await accountService.setDefaultAddress(address.id);
                    },
                  );
                }).toList(),
              );
            }
            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: addresses.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 14,
                mainAxisSpacing: 14,
                childAspectRatio: 2.25,
              ),
              itemBuilder: (context, index) {
                final address = addresses[index];
                return _AddressCard(
                  address: address,
                  onEdit: () => _showAddressDialog(context, address),
                  onDelete: () => _confirmDelete(context, address),
                  onSetDefault: () async {
                    await accountService.setDefaultAddress(address.id);
                  },
                );
              },
            );
          },
        ),
      ],
    );
  }

  Widget _buildIntro() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE0E4EA)),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.lock_outline, color: Color(0xFF102A43), size: 22),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Checkout más rápido y claro',
                  style: TextStyle(
                    color: Color(0xFF18212F),
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Guarda casa, trabajo u otra dirección frecuente para no volver a escribirla en cada compra.',
                  style: TextStyle(
                    color: Color(0xFF667085),
                    fontSize: 13,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE0E4EA)),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.location_off_outlined,
                size: 48, color: Colors.grey[400]),
          ),
          const SizedBox(height: 16),
          Text(
            'No tienes direcciones guardadas',
            style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.grey[800]),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () => _showAddressDialog(context, null),
            icon: const Icon(Icons.add),
            label: const Text('Agregar la primera dirección'),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF102A43),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ],
      ),
    );
  }

  void _showAddressDialog(BuildContext context, CustomerAddress? address) {
    showDialog(
      context: context,
      builder: (context) => _AddressFormDialog(address: address),
    );
  }

  void _confirmDelete(BuildContext context, CustomerAddress address) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar Dirección'),
        content: Text('¿Estás seguro de eliminar "${address.label}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () async {
              await context
                  .read<CustomerAccountService>()
                  .deleteAddress(address.id);
              if (context.mounted) Navigator.pop(context);
            },
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
  }
}

class _AddressCard extends StatelessWidget {
  final CustomerAddress address;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onSetDefault;

  const _AddressCard({
    required this.address,
    required this.onEdit,
    required this.onDelete,
    required this.onSetDefault,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE0E4EA)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF0F4F8),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.location_on_outlined,
                          color: Color(0xFF102A43), size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                address.label,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              if (address.isDefault) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFE6F4EA),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: const Text(
                                    'Principal',
                                    style: TextStyle(
                                      color: Color(0xFF1E7E34),
                                      fontSize: 10,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          Text(
                            address.recipientName,
                            style: TextStyle(
                                color: Colors.grey[600], fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                    PopupMenuButton(
                      icon: const Icon(Icons.more_vert, color: Colors.grey),
                      itemBuilder: (context) => [
                        const PopupMenuItem(
                          value: 'edit',
                          child: Row(
                            children: [
                              Icon(Icons.edit, size: 18),
                              SizedBox(width: 8),
                              Text('Editar'),
                            ],
                          ),
                        ),
                        if (!address.isDefault)
                          const PopupMenuItem(
                            value: 'default',
                            child: Row(
                              children: [
                                Icon(Icons.star, size: 18),
                                SizedBox(width: 8),
                                Text('Hacer principal'),
                              ],
                            ),
                          ),
                        const PopupMenuItem(
                          value: 'delete',
                          child: Row(
                            children: [
                              Icon(Icons.delete, size: 18, color: Colors.red),
                              SizedBox(width: 8),
                              Text('Eliminar',
                                  style: TextStyle(color: Colors.red)),
                            ],
                          ),
                        ),
                      ],
                      onSelected: (value) {
                        if (value == 'edit') onEdit();
                        if (value == 'delete') onDelete();
                        if (value == 'default') onSetDefault();
                      },
                    ),
                  ],
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Divider(height: 1),
                ),
                Text(
                  address.fullAddress,
                  style: const TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.phone, size: 14, color: Colors.grey[500]),
                    const SizedBox(width: 4),
                    Text(address.phone,
                        style:
                            TextStyle(color: Colors.grey[600], fontSize: 13)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AddressFormDialog extends StatefulWidget {
  final CustomerAddress? address;

  const _AddressFormDialog({this.address});

  @override
  State<_AddressFormDialog> createState() => _AddressFormDialogState();
}

class _AddressFormDialogState extends State<_AddressFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _labelController;
  late final TextEditingController _nameController;
  late final TextEditingController _phoneController;
  late final TextEditingController _streetController;
  late final TextEditingController _numberController;
  late final TextEditingController _apartmentController;
  late final TextEditingController _comunaController;
  late final TextEditingController _cityController;
  late final TextEditingController _regionController;
  late final TextEditingController _infoController;

  AddressAutocompleteService? _addressAutocompleteService;
  String? _postalCode;
  bool _isResolvingAddress = false;
  bool _useProfileContact = false;
  bool _isDefault = false;

  @override
  void initState() {
    super.initState();
    final addr = widget.address;
    final profile = context.read<CustomerAccountService>().customerProfile;
    final profileName = _readProfileText(profile, 'name');
    final profilePhone = _readProfileText(profile, 'phone');
    _labelController = TextEditingController(text: addr?.label);
    _nameController = TextEditingController(text: addr?.recipientName);
    _phoneController = TextEditingController(text: addr?.phone);
    _streetController = TextEditingController(text: addr?.streetAddress);
    _numberController = TextEditingController(text: addr?.streetNumber);
    _apartmentController = TextEditingController(text: addr?.apartment);
    _comunaController = TextEditingController(text: addr?.comuna);
    _cityController = TextEditingController(text: addr?.city);
    _regionController = TextEditingController(text: addr?.region);
    _infoController = TextEditingController(text: addr?.additionalInfo);
    _postalCode = addr?.postalCode;
    _useProfileContact = addr == null
        ? false
        : addr.recipientName.trim() == profileName &&
            addr.phone.trim() == profilePhone &&
            profileName.isNotEmpty &&
            profilePhone.isNotEmpty;
    _isDefault = addr?.isDefault ?? false;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final autocompleteService = context.read<AddressAutocompleteService>();
      autocompleteService.addListener(_onAutocompleteChanged);
      setState(() => _addressAutocompleteService = autocompleteService);

      final tenantId = context.read<PublicStoreTenantProvider>().tenantId;
      autocompleteService.initialize(tenantId: tenantId);
    });
  }

  @override
  void dispose() {
    _addressAutocompleteService?.removeListener(_onAutocompleteChanged);
    _labelController.dispose();
    _nameController.dispose();
    _phoneController.dispose();
    _streetController.dispose();
    _numberController.dispose();
    _apartmentController.dispose();
    _comunaController.dispose();
    _cityController.dispose();
    _regionController.dispose();
    _infoController.dispose();
    super.dispose();
  }

  void _onAutocompleteChanged() {
    if (!mounted) return;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final dialogMaxHeight = MediaQuery.sizeOf(context).height * 0.72;
    final profile = context.watch<CustomerAccountService>().customerProfile;
    final profileName = _readProfileText(profile, 'name');
    final profilePhone = _readProfileText(profile, 'phone');

    return AlertDialog(
      title:
          Text(widget.address == null ? 'Nueva Dirección' : 'Editar Dirección'),
      content: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: dialogMaxHeight),
        child: SizedBox(
          width: 500,
          child: SingleChildScrollView(
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: _labelController,
                    decoration: const InputDecoration(
                        labelText: 'Etiqueta (ej: Casa, Trabajo)'),
                    validator: (v) =>
                        v == null || v.isEmpty ? 'Requerido' : null,
                  ),
                  const SizedBox(height: 12),
                  _buildProfileContactOption(profileName, profilePhone),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _nameController,
                    enabled: !_useProfileContact,
                    decoration: const InputDecoration(
                        labelText: 'Nombre del destinatario'),
                    validator: (v) =>
                        v == null || v.isEmpty ? 'Requerido' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _phoneController,
                    enabled: !_useProfileContact,
                    decoration: const InputDecoration(labelText: 'Teléfono'),
                    validator: (v) =>
                        v == null || v.isEmpty ? 'Requerido' : null,
                  ),
                  if (_addressAutocompleteService?.isEnabled ?? false) ...[
                    const SizedBox(height: 12),
                    _buildAddressSearchField(),
                  ],
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: TextFormField(
                          controller: _streetController,
                          decoration: const InputDecoration(labelText: 'Calle'),
                          validator: (v) =>
                              v == null || v.isEmpty ? 'Requerido' : null,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: _numberController,
                          decoration:
                              const InputDecoration(labelText: 'Número'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _apartmentController,
                    decoration: const InputDecoration(
                        labelText: 'Depto/Oficina (opcional)'),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _comunaController,
                    decoration: const InputDecoration(labelText: 'Comuna'),
                    validator: (v) =>
                        v == null || v.isEmpty ? 'Requerido' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _cityController,
                    decoration: const InputDecoration(labelText: 'Ciudad'),
                    validator: (v) =>
                        v == null || v.isEmpty ? 'Requerido' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _regionController,
                    decoration: const InputDecoration(labelText: 'Región'),
                    validator: (v) =>
                        v == null || v.isEmpty ? 'Requerido' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _infoController,
                    decoration: const InputDecoration(
                        labelText: 'Referencias (opcional)'),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 12),
                  CheckboxListTile(
                    title: const Text('Dirección principal'),
                    value: _isDefault,
                    onChanged: (v) => setState(() => _isDefault = v ?? false),
                    contentPadding: EdgeInsets.zero,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      actions: [
        TextButton.icon(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.close, size: 18),
          label: const Text('Cancelar'),
          style: TextButton.styleFrom(
            foregroundColor: PublicStoreTheme.textSecondary,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
        FilledButton.icon(
          onPressed: _save,
          icon: const Icon(Icons.check, size: 18),
          label: const Text('Guardar'),
          style: FilledButton.styleFrom(
            backgroundColor: PublicStoreTheme.logoBlue,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildProfileContactOption(String profileName, String profilePhone) {
    final hasProfileContact = profileName.isNotEmpty && profilePhone.isNotEmpty;
    final contactLabel = [
      if (profileName.isNotEmpty) profileName,
      if (profilePhone.isNotEmpty) profilePhone,
    ].join(' · ');

    return InkWell(
      onTap: hasProfileContact
          ? () => _setUseProfileContact(
                !_useProfileContact,
                profileName: profileName,
                profilePhone: profilePhone,
              )
          : null,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFE0E4EA)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Checkbox(
              value: _useProfileContact,
              onChanged: hasProfileContact
                  ? (value) => _setUseProfileContact(
                        value ?? false,
                        profileName: profileName,
                        profilePhone: profilePhone,
                      )
                  : null,
              activeColor: PublicStoreTheme.logoBlue,
              visualDensity: VisualDensity.compact,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Usar mis datos de cuenta',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF18212F),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    hasProfileContact
                        ? contactLabel
                        : 'Agrega nombre y teléfono en tu perfil para reutilizarlos.',
                    style: const TextStyle(
                      color: Color(0xFF667085),
                      fontSize: 12,
                      height: 1.25,
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

  void _setUseProfileContact(
    bool value, {
    required String profileName,
    required String profilePhone,
  }) {
    setState(() {
      _useProfileContact = value;
      if (value) {
        if (profileName.isNotEmpty) _nameController.text = profileName;
        if (profilePhone.isNotEmpty) _phoneController.text = profilePhone;
      }
    });
  }

  static String _readProfileText(Map<String, dynamic>? profile, String key) {
    return (profile?[key] ?? '').toString().trim();
  }

  Widget _buildAddressSearchField() {
    return typeahead.TypeAheadField<AddressSuggestion>(
      suggestionsCallback: (pattern) async {
        return await _addressAutocompleteService?.fetchSuggestions(pattern) ??
            [];
      },
      builder: (context, controller, focusNode) {
        return TextFormField(
          controller: controller,
          focusNode: focusNode,
          decoration: InputDecoration(
            labelText: 'Buscar dirección en Google Maps',
            hintText: 'Ej: Álvarez 32, Viña del Mar',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: _isResolvingAddress
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : null,
          ),
          maxLines: 1,
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
      onSelected: _selectAddressSuggestion,
    );
  }

  Future<void> _selectAddressSuggestion(AddressSuggestion suggestion) async {
    FocusScope.of(context).unfocus();
    setState(() => _isResolvingAddress = true);

    try {
      final resolved =
          await _addressAutocompleteService?.resolvePlace(suggestion.placeId);
      if (!mounted) return;

      if (resolved == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No pudimos cargar esa dirección')),
        );
        return;
      }

      _applyResolvedAddress(resolved);
      _addressAutocompleteService?.resetSessionToken();
    } finally {
      if (mounted) {
        setState(() => _isResolvingAddress = false);
      }
    }
  }

  void _applyResolvedAddress(ResolvedAddress address) {
    final street = address.street.trim().isNotEmpty
        ? address.street.trim()
        : address.formattedAddress.split(',').first.trim();
    final comuna = address.comuna.trim().isNotEmpty
        ? address.comuna.trim()
        : address.city.trim();
    final city = address.city.trim().isNotEmpty ? address.city.trim() : comuna;

    setState(() {
      _streetController.text = street;
      _numberController.text = address.streetNumber?.trim() ?? '';
      if (address.apartment != null && address.apartment!.trim().isNotEmpty) {
        _apartmentController.text = address.apartment!.trim();
      }
      _comunaController.text = comuna;
      _cityController.text = city;
      _regionController.text = address.region.trim();
      _postalCode = address.postalCode?.trim();
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final accountService = context.read<CustomerAccountService>();
    final profile = accountService.customerProfile;
    if (profile == null) return;

    final address = CustomerAddress(
      id: widget.address?.id ?? '',
      customerId: profile['id'],
      label: _labelController.text.trim(),
      recipientName: _nameController.text.trim(),
      phone: _phoneController.text.trim(),
      streetAddress: _streetController.text.trim(),
      streetNumber: _numberController.text.trim().isNotEmpty
          ? _numberController.text.trim()
          : null,
      apartment: _apartmentController.text.trim().isNotEmpty
          ? _apartmentController.text.trim()
          : null,
      comuna: _comunaController.text.trim(),
      city: _cityController.text.trim(),
      region: _regionController.text.trim(),
      postalCode: _postalCode,
      additionalInfo: _infoController.text.trim().isNotEmpty
          ? _infoController.text.trim()
          : null,
      isDefault: _isDefault,
      createdAt: widget.address?.createdAt ?? DateTime.now(),
      updatedAt: DateTime.now(),
    );

    try {
      if (widget.address == null) {
        await accountService.addAddress(address);
      } else {
        await accountService.updateAddress(address);
      }

      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }
}
