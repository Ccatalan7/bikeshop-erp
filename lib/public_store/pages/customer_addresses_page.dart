import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/customer_account_service.dart';
import '../theme/public_store_theme.dart';
import '../../shared/models/customer_address.dart';

class CustomerAddressesPage extends StatelessWidget {
  const CustomerAddressesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final accountService = context.watch<CustomerAccountService>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mis Direcciones'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () {
              _showAddressDialog(context, null);
            },
            tooltip: 'Agregar dirección',
          ),
        ],
      ),
      body: accountService.addresses.isEmpty
          ? _buildEmptyState(context)
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: accountService.addresses.length,
              itemBuilder: (context, index) {
                final address = accountService.addresses[index];
                return _AddressCard(
                  address: address,
                  onEdit: () => _showAddressDialog(context, address),
                  onDelete: () => _confirmDelete(context, address),
                  onSetDefault: () async {
                    await accountService.setDefaultAddress(address.id);
                  },
                );
              },
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddressDialog(context, null),
        icon: const Icon(Icons.add),
        label: const Text('Nueva Dirección'),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.location_off_outlined, size: 64),
          const SizedBox(height: 16),
          const Text('No tienes direcciones guardadas'),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () => _showAddressDialog(context, null),
            icon: const Icon(Icons.add),
            label: const Text('AGREGAR DIRECCIÓN'),
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
        content: Text('¿Eliminar "${address.label}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () async {
              await context.read<CustomerAccountService>().deleteAddress(address.id);
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
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    address.label,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (address.isDefault)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: PublicStoreTheme.success,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      'PRINCIPAL',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                IconButton(
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: onEdit,
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: onDelete,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              address.recipientName,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 4),
            Text(address.fullAddress),
            Text(address.phone),
            if (!address.isDefault) ...[
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: onSetDefault,
                icon: const Icon(Icons.star_outline, size: 16),
                label: const Text('Establecer como principal'),
              ),
            ],
          ],
        ),
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
      title: Text(widget.address == null ? 'Nueva Dirección' : 'Editar Dirección'),
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
                  decoration: const InputDecoration(labelText: 'Etiqueta (ej: Casa, Trabajo)'),
                  validator: (v) => v == null || v.isEmpty ? 'Requerido' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(labelText: 'Nombre del destinatario'),
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
                        validator: (v) => v == null || v.isEmpty ? 'Requerido' : null,
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
                  decoration: const InputDecoration(labelText: 'Depto/Oficina (opcional)'),
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
                  decoration: const InputDecoration(labelText: 'Referencias (opcional)'),
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
