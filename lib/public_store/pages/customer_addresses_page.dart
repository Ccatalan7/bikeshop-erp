import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/customer_account_service.dart';
import '../../shared/models/customer_address.dart';
import '../widgets/customer_portal_layout.dart';

class CustomerAddressesPage extends StatelessWidget {
  const CustomerAddressesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final accountService = context.watch<CustomerAccountService>();

    return CustomerPortalLayout(
      title: 'Mis Direcciones',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
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
        // Add Button Row
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              FilledButton.icon(
                onPressed: () => _showAddressDialog(context, null),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Nueva Dirección'),
                style: FilledButton.styleFrom(
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ],
          ),
        ),
        // List
        ...addresses.map((address) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _AddressCard(
              address: address,
              onEdit: () => _showAddressDialog(context, address),
              onDelete: () => _confirmDelete(context, address),
              onSetDefault: () async {
                await accountService.setDefaultAddress(address.id);
              },
            ),
          );
        }),
      ],
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
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
          OutlinedButton.icon(
            onPressed: () => _showAddressDialog(context, null),
            icon: const Icon(Icons.add),
            label: const Text('Agregar la primera dirección'),
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
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 5,
            offset: const Offset(0, 2),
          ),
        ],
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
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.location_on_outlined,
                          color: Colors.blue, size: 20),
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
                                    color: Colors.green.shade100,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    'PRINCIPAL',
                                    style: TextStyle(
                                      color: Colors.green.shade800,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
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

  bool _isDefault = false;

  @override
  void initState() {
    super.initState();
    final addr = widget.address;
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
    _isDefault = addr?.isDefault ?? false;
  }

  @override
  void dispose() {
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

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title:
          Text(widget.address == null ? 'Nueva Dirección' : 'Editar Dirección'),
      content: SingleChildScrollView(
        child: SizedBox(
          width: 500,
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _labelController,
                  decoration: const InputDecoration(
                      labelText: 'Etiqueta (ej: Casa, Trabajo)'),
                  validator: (v) => v == null || v.isEmpty ? 'Requerido' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                      labelText: 'Nombre del destinatario'),
                  validator: (v) => v == null || v.isEmpty ? 'Requerido' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _phoneController,
                  decoration: const InputDecoration(labelText: 'Teléfono'),
                  validator: (v) => v == null || v.isEmpty ? 'Requerido' : null,
                ),
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
                        decoration: const InputDecoration(labelText: 'Número'),
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
                  validator: (v) => v == null || v.isEmpty ? 'Requerido' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _cityController,
                  decoration: const InputDecoration(labelText: 'Ciudad'),
                  validator: (v) => v == null || v.isEmpty ? 'Requerido' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _regionController,
                  decoration: const InputDecoration(labelText: 'Región'),
                  validator: (v) => v == null || v.isEmpty ? 'Requerido' : null,
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
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _save,
          child: const Text('Guardar'),
        ),
      ],
    );
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
