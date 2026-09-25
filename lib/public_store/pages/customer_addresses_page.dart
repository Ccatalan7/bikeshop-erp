import 'package:flutter/material.dart';
import 'package:flutter_typeahead/flutter_typeahead.dart' as typeahead;
import 'package:provider/provider.dart';
import '../providers/public_store_tenant_provider.dart';
import '../services/address_autocomplete_service.dart';
import '../services/customer_account_service.dart';
import '../models/customer_portal_presentation.dart';
import '../../shared/models/customer_address.dart';
import '../widgets/customer_portal_layout.dart';
import '../widgets/customer_portal_style.dart';

class CustomerAddressesPage extends StatelessWidget {
  const CustomerAddressesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final accountService = context.watch<CustomerAccountService>();
    final addresses = List<CustomerAddress>.from(accountService.addresses)
      ..sort((a, b) => (b.isDefault ? 1 : 0) - (a.isDefault ? 1 : 0));

    return CustomerPortalLayout(
      title: 'Direcciones',
      subtitle: addresses.isEmpty
          ? null
          : 'La principal aparece primero al pagar un pedido.',
      headerAction: addresses.isEmpty
          ? null
          : OutlinedButton.icon(
              onPressed: () => _showAddressDialog(context, null),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Agregar dirección'),
              style: PortalStyle.of(context).secondaryButton,
            ),
      child: addresses.isEmpty
          ? PortalEmptyState(
              title: 'No tienes direcciones guardadas.',
              message: 'Guarda la de tu casa o tu trabajo y no tendrás que '
                  'escribirla en cada compra.',
              actions: [
                Padding(
                  padding: const EdgeInsets.only(top: 4, bottom: 4),
                  child: FilledButton.icon(
                    onPressed: () => _showAddressDialog(context, null),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Agregar la primera dirección'),
                    style: portalPrimaryButton(context),
                  ),
                ),
              ],
            )
          : LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 560;
                return PortalPanel(
                  children: [
                    for (final address in addresses)
                      _AddressRow(
                        address: address,
                        compact: compact,
                        onEdit: () => _showAddressDialog(context, address),
                        onDelete: () => _confirmDelete(context, address),
                        onSetDefault: () =>
                            _setDefault(context, accountService, address),
                      ),
                  ],
                );
              },
            ),
    );
  }

  void _showAddressDialog(BuildContext context, CustomerAddress? address) {
    final autocompleteService = context.read<AddressAutocompleteService>();
    showDialog(
      context: context,
      builder: (_) => ChangeNotifierProvider<AddressAutocompleteService>.value(
        value: autocompleteService,
        child: _AddressFormDialog(address: address),
      ),
    );
  }

  Future<void> _setDefault(
    BuildContext context,
    CustomerAccountService accountService,
    CustomerAddress address,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await accountService.setDefaultAddress(address.id);
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('No pudimos cambiar la principal. Intenta de nuevo.'),
        ),
      );
    }
  }

  void _confirmDelete(BuildContext context, CustomerAddress address) {
    final style = PortalStyle.of(context);
    final danger = Theme.of(context).colorScheme.error;
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: style.panel,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(PortalStyle.panelRadius),
        ),
        title: Text('¿Eliminar «${address.label}»?', style: style.rowTitle),
        content: Text(address.fullAddress, style: style.rowMeta),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            style: TextButton.styleFrom(foregroundColor: style.inkSecondary),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              try {
                await dialogContext
                    .read<CustomerAccountService>()
                    .deleteAddress(address.id);
              } catch (_) {
                messenger.showSnackBar(
                  const SnackBar(
                    content: Text(
                      'No pudimos eliminar la dirección. Intenta de nuevo.',
                    ),
                  ),
                );
              }
              if (dialogContext.mounted) Navigator.pop(dialogContext);
            },
            style: portalPrimaryButton(context).copyWith(
              backgroundColor: WidgetStatePropertyAll(danger),
              foregroundColor: WidgetStatePropertyAll(
                Theme.of(context).colorScheme.onError,
              ),
            ),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
  }
}

/// Una dirección: su nombre, la dirección completa y a quién se entrega. La
/// fila edita; el menú hace principal o elimina.
class _AddressRow extends StatelessWidget {
  const _AddressRow({
    required this.address,
    required this.compact,
    required this.onEdit,
    required this.onDelete,
    required this.onSetDefault,
  });

  final CustomerAddress address;
  final bool compact;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onSetDefault;

  @override
  Widget build(BuildContext context) {
    final style = PortalStyle.of(context);
    final contact = [
      address.recipientName.trim(),
      address.phone.trim(),
    ].where((part) => part.isNotEmpty).join(' · ');
    const principal = PortalStatusPill(
      label: 'Principal',
      tone: PortalTone.info,
    );
    return PortalRow(
      leading: const PortalThumb(fallbackIcon: Icons.location_on_outlined),
      title: address.label,
      meta: [address.fullAddress, if (contact.isNotEmpty) contact].join('\n'),
      footer: compact && address.isDefault ? principal : null,
      semanticsLabel: 'Editar ${address.label}',
      onTap: onEdit,
      showChevron: false,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!compact && address.isDefault) ...[
            principal,
            const SizedBox(width: 4),
          ],
          PopupMenuButton<String>(
            tooltip: 'Opciones de ${address.label}',
            icon: Icon(Icons.more_vert, color: style.inkSecondary),
            color: style.panel,
            surfaceTintColor: Colors.transparent,
            onSelected: (value) {
              if (value == 'edit') onEdit();
              if (value == 'default') onSetDefault();
              if (value == 'delete') onDelete();
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'edit', child: Text('Editar')),
              if (!address.isDefault)
                const PopupMenuItem(
                  value: 'default',
                  child: Text('Usar como principal'),
                ),
              PopupMenuItem(
                value: 'delete',
                child: Text(
                  'Eliminar',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            ],
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
  bool _isSaving = false;

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

    final style = PortalStyle.of(context);
    return AlertDialog(
      backgroundColor: style.panel,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(PortalStyle.panelRadius),
      ),
      title: Semantics(
        header: true,
        child: Text(
          (widget.address == null ? 'Nueva dirección' : 'Editar dirección')
              .toUpperCase(),
          style: style.pageTitle(compact: true).copyWith(fontSize: 22),
        ),
      ),
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
                    title: Text(
                      'Usar como dirección principal',
                      style: style.rowTitle,
                    ),
                    value: _isDefault,
                    activeColor: style.accent,
                    onChanged: (v) => setState(() => _isDefault = v ?? false),
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.pop(context),
          style: TextButton.styleFrom(
            foregroundColor: style.inkSecondary,
            minimumSize: const Size(0, 44),
          ),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _isSaving ? null : _save,
          style: portalPrimaryButton(context),
          child: Text(_isSaving ? 'Guardando…' : 'Guardar dirección'),
        ),
      ],
    );
  }

  Widget _buildProfileContactOption(String profileName, String profilePhone) {
    final style = PortalStyle.of(context);
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
          color: style.canvas,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: style.line),
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
              activeColor: style.accent,
              visualDensity: VisualDensity.compact,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Usar mis datos de cuenta', style: style.rowTitle),
                  const SizedBox(height: 2),
                  Text(
                    hasProfileContact
                        ? contactLabel
                        : 'Agrega nombre y teléfono en tu perfil para reutilizarlos.',
                    style: style.rowMeta,
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

    setState(() => _isSaving = true);
    try {
      if (widget.address == null) {
        await accountService.addAddress(address);
      } else {
        await accountService.updateAddress(address);
      }

      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No pudimos guardar la dirección. Intenta de nuevo.'),
          ),
        );
      }
    }
  }
}
