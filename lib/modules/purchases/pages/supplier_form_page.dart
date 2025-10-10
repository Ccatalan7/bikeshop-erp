import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../shared/models/supplier.dart';
import '../../../shared/utils/chilean_utils.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/main_layout.dart';
import '../services/purchase_service.dart';

class SupplierFormPage extends StatefulWidget {
  final String? supplierId;

  const SupplierFormPage({super.key, this.supplierId});

  @override
  State<SupplierFormPage> createState() => _SupplierFormPageState();
}

class _SupplierFormPageState extends State<SupplierFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _rutController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController();
  final _cityController = TextEditingController();
  final _regionController = TextEditingController();
  final _comunaController = TextEditingController();
  final _contactController = TextEditingController();
  final _websiteController = TextEditingController();
  final _notesController = TextEditingController();

  SupplierType _type = SupplierType.local;
  PaymentTerms _paymentTerms = PaymentTerms.net30;
  bool _isActive = true;

  bool _isSaving = false;
  bool _isLoading = true;
  Supplier? _existing;

  late PurchaseService _purchaseService;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initialize());
  }

  @override
  void dispose() {
    _nameController.dispose();
    _rutController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _cityController.dispose();
    _regionController.dispose();
    _comunaController.dispose();
    _contactController.dispose();
    _websiteController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  void _closePage({bool saved = false}) {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final navigator = Navigator.of(context);
      if (navigator.canPop()) {
        navigator.pop(saved ? true : null);
      } else {
        context.go('/purchases/suppliers');
      }
    });
  }

  Future<void> _initialize() async {
    _purchaseService = context.read<PurchaseService>();
    if (widget.supplierId == null) {
      setState(() => _isLoading = false);
      return;
    }

    try {
      final supplier = await _purchaseService.getSupplier(widget.supplierId!);
      if (supplier != null) {
        _existing = supplier;
        _nameController.text = supplier.name;
        _rutController.text = supplier.rut ?? '';
        _emailController.text = supplier.email ?? '';
        _phoneController.text = supplier.phone ?? '';
        _addressController.text = supplier.address ?? '';
        _cityController.text = supplier.city ?? '';
        _regionController.text = supplier.region ?? '';
        _comunaController.text = supplier.comuna ?? '';
        _contactController.text = supplier.contactPerson ?? '';
        _websiteController.text = supplier.website ?? '';
        _notesController.text = supplier.notes ?? '';
        _type = supplier.type;
        _paymentTerms = supplier.paymentTerms;
        _isActive = supplier.isActive;
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al cargar proveedor: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final now = DateTime.now();
    final supplier = Supplier(
      id: _existing?.id ?? '',
      name: _nameController.text.trim(),
      email: _emailController.text.trim().isEmpty ? null : _emailController.text.trim(),
      phone: _phoneController.text.trim().isEmpty ? null : _phoneController.text.trim(),
      rut: _rutController.text.trim().isEmpty ? null : _rutController.text.trim(),
      address: _addressController.text.trim().isEmpty ? null : _addressController.text.trim(),
      city: _cityController.text.trim().isEmpty ? null : _cityController.text.trim(),
      region: _regionController.text.trim().isEmpty ? null : _regionController.text.trim(),
      comuna: _comunaController.text.trim().isEmpty ? null : _comunaController.text.trim(),
      type: _type,
      contactPerson: _contactController.text.trim().isEmpty ? null : _contactController.text.trim(),
      website: _websiteController.text.trim().isEmpty ? null : _websiteController.text.trim(),
      bankDetails: _existing?.bankDetails ?? const {},
      paymentTerms: _paymentTerms,
      notes: _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
      isActive: _isActive,
      createdAt: _existing?.createdAt ?? now,
      updatedAt: now,
    );

    setState(() => _isSaving = true);

    try {
      await _purchaseService.saveSupplier(supplier);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_existing == null ? 'Proveedor creado correctamente' : 'Proveedor actualizado'),
          backgroundColor: Colors.green,
        ),
      );
      _closePage(saved: true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo guardar el proveedor: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return MainLayout(
      child: Form(
        key: _formKey,
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _buildForm(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Row(
        children: [
          IconButton(
            onPressed: () => _closePage(),
            icon: const Icon(Icons.arrow_back),
          ),
          Expanded(
            child: Text(
              widget.supplierId != null ? 'Editar proveedor' : 'Nuevo proveedor',
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
          ),
          AppButton(
            text: 'Guardar',
            icon: Icons.save,
            onPressed: _isSaving ? null : _save,
            isLoading: _isSaving,
          ),
        ],
      ),
    );
  }

  Widget _buildForm() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: ListView(
        children: [
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: Colors.grey[300]!),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Datos del proveedor', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      labelText: 'Nombre legal',
                      hintText: 'Ej: Importadora Vinabike Ltda.',
                    ),
                    validator: (value) => (value == null || value.trim().isEmpty)
                        ? 'Ingresa el nombre del proveedor'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _rutController,
                    decoration: const InputDecoration(
                      labelText: 'RUT',
                      hintText: '11.111.111-1',
                    ),
                    autovalidateMode: AutovalidateMode.onUserInteraction,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) return null;
                      return ChileanUtils.isValidRut(value.trim())
                          ? null
                          : 'RUT inválido';
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(labelText: 'Correo electrónico'),
                    autovalidateMode: AutovalidateMode.onUserInteraction,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) return null;
                      return ChileanUtils.isValidEmail(value.trim())
                          ? null
                          : 'Correo inválido';
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _phoneController,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(labelText: 'Teléfono'),
                    autovalidateMode: AutovalidateMode.onUserInteraction,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) return null;
                      return ChileanUtils.isValidChileanPhone(value.trim())
                          ? null
                          : 'Teléfono inválido';
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: Colors.grey[300]!),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Dirección y contacto', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _addressController,
                    decoration: const InputDecoration(labelText: 'Dirección'),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _comunaController,
                    decoration: const InputDecoration(labelText: 'Comuna'),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _cityController,
                    decoration: const InputDecoration(labelText: 'Ciudad'),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _regionController,
                    decoration: const InputDecoration(labelText: 'Región'),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _contactController,
                    decoration: const InputDecoration(labelText: 'Persona de contacto'),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _websiteController,
                    decoration: const InputDecoration(labelText: 'Sitio web'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: Colors.grey[300]!),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Condiciones comerciales', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<SupplierType>(
                          value: _type,
                          decoration: const InputDecoration(labelText: 'Tipo de proveedor'),
                          items: SupplierType.values
                              .map((type) => DropdownMenuItem(
                                    value: type,
                                    child: Text(type.displayName),
                                  ))
                              .toList(),
                          onChanged: (value) {
                            if (value != null) {
                              setState(() => _type = value);
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: DropdownButtonFormField<PaymentTerms>(
                          value: _paymentTerms,
                          decoration: const InputDecoration(labelText: 'Condiciones de pago'),
                          items: PaymentTerms.values
                              .map((term) => DropdownMenuItem(
                                    value: term,
                                    child: Text(term.displayName),
                                  ))
                              .toList(),
                          onChanged: (value) {
                            if (value != null) {
                              setState(() => _paymentTerms = value);
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Proveedor activo'),
                    subtitle: const Text('Controla la visibilidad en las listas de selección.'),
                    value: _isActive,
                    onChanged: (value) => setState(() => _isActive = value),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _notesController,
                    decoration: const InputDecoration(
                      labelText: 'Notas internas',
                      hintText: 'Información relevante para compras o contabilidad',
                    ),
                    maxLines: 3,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}