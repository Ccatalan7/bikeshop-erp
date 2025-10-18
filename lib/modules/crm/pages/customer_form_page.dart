import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:cross_file/cross_file.dart';

import '../../../shared/widgets/main_layout.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/services/database_service.dart';
import '../../../shared/services/image_service.dart';
import '../../../shared/constants/storage_constants.dart';
import '../../../shared/utils/chilean_utils.dart';
import '../models/crm_models.dart';
import '../services/customer_service.dart';

class CustomerFormPage extends StatefulWidget {
  final String? customerId;
  
  const CustomerFormPage({super.key, this.customerId});

  @override
  State<CustomerFormPage> createState() => _CustomerFormPageState();
}

class _CustomerFormPageState extends State<CustomerFormPage> {
  final _formKey = GlobalKey<FormState>();
  late CustomerService _customerService;
  
  final _nameController = TextEditingController();
  final _rutController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController();
  
  String? _selectedRegion;
  bool _isActive = true;
  String? _imageUrl;
  Uint8List? _selectedImageBytes;
  String? _selectedImageName;
  
  bool _isLoading = false;
  bool _isSaving = false;
  Customer? _existingCustomer;

  @override
  void initState() {
    super.initState();
    _customerService = CustomerService(
      Provider.of<DatabaseService>(context, listen: false),
    );
    if (widget.customerId != null) {
      _loadCustomer();
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _rutController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  Future<void> _loadCustomer() async {
    setState(() => _isLoading = true);
    try {
      final customer = await _customerService.getCustomerById(widget.customerId!);
      if (customer != null) {
        _existingCustomer = customer;
        _nameController.text = customer.name;
        _rutController.text = customer.rut;
        _emailController.text = customer.email ?? '';
        _phoneController.text = customer.phone ?? '';
        _addressController.text = customer.address ?? '';
        _selectedRegion = customer.region;
        _isActive = customer.isActive;
        _imageUrl = customer.imageUrl;
      }
      setState(() => _isLoading = false);
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error cargando cliente: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _selectImage() async {
    try {
      final result = await ImageService.pickImage();
      if (result != null) {
        setState(() {
          _selectedImageBytes = result.bytes;
          _selectedImageName = result.name;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error seleccionando imagen: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _saveCustomer() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);
    try {
      String? finalImageUrl = _imageUrl;
      
      // Upload image if selected
      if (_selectedImageBytes != null && _selectedImageName != null) {
        final uploadUrl = await ImageService.uploadBytes(
          bytes: _selectedImageBytes!,
          fileName: _selectedImageName!,
          bucket: StorageConfig.defaultBucket,
          folder: StorageFolders.customers,
        );

        if (uploadUrl == null) {
          throw Exception('No se pudo subir la imagen del cliente. Intenta nuevamente.');
        }

        finalImageUrl = uploadUrl;
      }

      final customer = Customer(
        id: _existingCustomer?.id,
        name: _nameController.text.trim(),
        rut: _rutController.text.trim(),
        email: _emailController.text.trim().isEmpty ? null : _emailController.text.trim(),
        phone: _phoneController.text.trim().isEmpty ? null : _phoneController.text.trim(),
        address: _addressController.text.trim().isEmpty ? null : _addressController.text.trim(),
        region: _selectedRegion,
        imageUrl: finalImageUrl,
        isActive: _isActive,
      );

      if (_existingCustomer != null) {
        await _customerService.updateCustomer(customer);
      } else {
        await _customerService.createCustomer(customer);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_existingCustomer != null 
                ? 'Cliente actualizado exitosamente'
                : 'Cliente creado exitosamente'),
            backgroundColor: Colors.green,
          ),
        );
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error guardando cliente: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() => _isSaving = false);
    }
  }

  String? _validateRut(String? value) {
    // RUT is now optional - only validate if provided
    if (value == null || value.isEmpty) {
      return null; // No error if empty
    }
    if (!ChileanUtils.isValidRut(value)) {
      return 'RUT inválido';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return MainLayout(
      child: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _buildForm(),
    );
  }

  Widget _buildForm() {
    return Form(
      key: _formKey,
      child: Column(
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                IconButton(
                  onPressed: () => context.pop(),
                  icon: const Icon(Icons.arrow_back),
                ),
                Expanded(
                  child: Text(
                    _existingCustomer != null 
                        ? 'Editar Cliente'
                        : 'Nuevo Cliente',
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                AppButton(
                  text: 'Guardar',
                  icon: Icons.save,
                  onPressed: _saveCustomer,
                  isLoading: _isSaving,
                ),
              ],
            ),
          ),
          
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Image section
                  Center(
                    child: Column(
                      children: [
                        GestureDetector(
                          onTap: _selectImage,
                          child: Container(
                            width: 120,
                            height: 120,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.grey[300]!,
                                width: 2,
                              ),
                            ),
                            child: _selectedImageBytes != null
                                ? ClipOval(
                                    child: Image.memory(
                                      _selectedImageBytes!,
                                      fit: BoxFit.cover,
                                    ),
                                  )
                                : ImageService.buildAvatarImage(
                                    imageUrl: _imageUrl,
                                    radius: 60,
                                    initials: '?', // Temporarily disabled to debug freeze
                                  ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextButton.icon(
                          onPressed: _selectImage,
                          icon: const Icon(Icons.camera_alt),
                          label: const Text('Cambiar Foto'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),
                  
                  // Personal information
                  const Text(
                    'Información Personal',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  TextFormField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      labelText: 'Nombre Completo',
                      prefixIcon: Icon(Icons.person),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'El nombre es requerido';
                      }
                      return null;
                    },
                    // No onChanged - avatar updates via ListenableBuilder
                  ),
                  const SizedBox(height: 16),
                  
                  TextFormField(
                    controller: _rutController,
                    decoration: const InputDecoration(
                      labelText: 'RUT (opcional)',
                      prefixIcon: Icon(Icons.badge),
                      hintText: '12.345.678-9',
                    ),
                    validator: _validateRut,
                    onChanged: (value) {
                      // Auto-format RUT as user types
                      final formatted = ChileanUtils.formatRut(value);
                      if (formatted != value) {
                        _rutController.value = TextEditingValue(
                          text: formatted,
                          selection: TextSelection.collapsed(offset: formatted.length),
                        );
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  
                  TextFormField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'Correo Electrónico (Opcional)',
                      prefixIcon: Icon(Icons.email),
                    ),
                    validator: (value) {
                      if (value != null && value.isNotEmpty && !value.contains('@')) {
                        return 'Ingrese un correo válido';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  
                  TextFormField(
                    controller: _phoneController,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'Teléfono (Opcional)',
                      prefixIcon: Icon(Icons.phone),
                    ),
                  ),
                  const SizedBox(height: 32),
                  
                  // Address information
                  const Text(
                    'Información de Ubicación',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  DropdownButtonFormField<String>(
                    value: _selectedRegion,
                    decoration: const InputDecoration(
                      labelText: 'Región',
                      prefixIcon: Icon(Icons.location_on),
                    ),
                    items: ChileanUtils.getChileanRegions().map((region) {
                      return DropdownMenuItem<String>(
                        value: region,
                        child: Text(region),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setState(() => _selectedRegion = value);
                    },
                  ),
                  const SizedBox(height: 16),
                  
                  TextFormField(
                    controller: _addressController,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Dirección (Opcional)',
                      prefixIcon: Icon(Icons.home),
                      hintText: 'Calle, número, comuna',
                    ),
                  ),
                  const SizedBox(height: 32),
                  
                  // Status
                  const Text(
                    'Estado del Cliente',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  SwitchListTile(
                    title: const Text('Cliente Activo'),
                    subtitle: Text(_isActive 
                        ? 'El cliente puede realizar compras'
                        : 'Cliente deshabilitado'),
                    value: _isActive,
                    onChanged: (value) {
                      setState(() => _isActive = value);
                    },
                  ),
                  
                  const SizedBox(height: 32),
                  
                  // Actions
                  Row(
                    children: [
                      Expanded(
                        child: AppButton(
                          text: 'Cancelar',
                          type: ButtonType.outline,
                          onPressed: () => context.pop(),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: AppButton(
                          text: _existingCustomer != null ? 'Actualizar' : 'Crear Cliente',
                          onPressed: _saveCustomer,
                          isLoading: _isSaving,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}