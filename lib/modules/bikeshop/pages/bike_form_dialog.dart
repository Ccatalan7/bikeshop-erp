import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'dart:typed_data';

import '../models/bikeshop_models.dart';
import '../services/bikeshop_service.dart';
import '../../../shared/services/image_service.dart';

class BikeFormDialog extends StatefulWidget {
  final String customerId;
  final Bike? bike; // Null for new bike, existing bike for edit

  const BikeFormDialog({
    super.key,
    required this.customerId,
    this.bike,
  });

  @override
  State<BikeFormDialog> createState() => _BikeFormDialogState();
}

class _BikeFormDialogState extends State<BikeFormDialog> {
  final _formKey = GlobalKey<FormState>();
  
  // Controllers
  late TextEditingController _brandController;
  late TextEditingController _modelController;
  late TextEditingController _yearController;
  late TextEditingController _serialNumberController;
  late TextEditingController _colorController;
  late TextEditingController _frameSizeController;
  late TextEditingController _wheelSizeController;
  late TextEditingController _notesController;
  
  BikeType _selectedType = BikeType.mountain;
  DateTime? _purchaseDate;
  DateTime? _warrantyUntil;
  
  // Image handling
  List<String> _imageUrls = [];
  List<({Uint8List bytes, String name})> _newImages = [];
  bool _isUploadingImage = false;
  
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    
    // Initialize controllers with existing bike data if editing
    _brandController = TextEditingController(text: widget.bike?.brand);
    _modelController = TextEditingController(text: widget.bike?.model);
    _yearController = TextEditingController(text: widget.bike?.year?.toString() ?? '');
    _serialNumberController = TextEditingController(text: widget.bike?.serialNumber);
    _colorController = TextEditingController(text: widget.bike?.color);
    _frameSizeController = TextEditingController(text: widget.bike?.frameSize);
    _wheelSizeController = TextEditingController(text: widget.bike?.wheelSize);
    _notesController = TextEditingController(text: widget.bike?.notes);
    
    if (widget.bike != null) {
      _selectedType = widget.bike!.bikeType ?? BikeType.mountain;
      _purchaseDate = widget.bike!.purchaseDate;
      _warrantyUntil = widget.bike!.warrantyUntil;
      _imageUrls = List.from(widget.bike!.imageUrls);
    }
  }

  @override
  void dispose() {
    _brandController.dispose();
    _modelController.dispose();
    _yearController.dispose();
    _serialNumberController.dispose();
    _colorController.dispose();
    _frameSizeController.dispose();
    _wheelSizeController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _selectDate(BuildContext context, bool isPurchaseDate) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: isPurchaseDate 
          ? (_purchaseDate ?? DateTime.now())
          : (_warrantyUntil ?? DateTime.now().add(const Duration(days: 365))),
      firstDate: DateTime(2000),
      lastDate: DateTime(2030),
      // Removed locale parameter - it can cause freezes on web
    );
    
    if (picked != null && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {
            if (isPurchaseDate) {
              _purchaseDate = picked;
            } else {
              _warrantyUntil = picked;
            }
          });
        }
      });
    }
  }

  Future<void> _pickImage() async {
    try {
      setState(() {
        _isUploadingImage = true;
      });

      final result = await ImageService.pickImage();

      setState(() {
        _isUploadingImage = false;
      });

      if (result != null) {
        setState(() {
          _newImages.add(result);
        });
      }
    } catch (e) {
      setState(() {
        _isUploadingImage = false;
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al seleccionar imagen: $e')),
        );
      }
    }
  }

  void _removeImage(int index, bool isNew) {
    setState(() {
      if (isNew) {
        _newImages.removeAt(index);
      } else {
        _imageUrls.removeAt(index);
      }
    });
  }

  Future<void> _saveBike() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      final bikeshopService = Provider.of<BikeshopService>(context, listen: false);
      
      // Upload new images to Supabase Storage
      List<String> uploadedUrls = List.from(_imageUrls);
      
      if (_newImages.isNotEmpty) {
        setState(() {
          _isUploadingImage = true;
        });
        
        for (var imageData in _newImages) {
          try {
            final timestamp = DateTime.now().millisecondsSinceEpoch;
            final fileName = 'bike_${widget.customerId}_$timestamp.jpg';
            
            final url = await ImageService.uploadBytes(
              bytes: imageData.bytes,
              fileName: fileName,
              bucket: 'bike-images',
              folder: widget.customerId,
            );
            
            if (url != null) {
              uploadedUrls.add(url);
            }
          } catch (e) {
            debugPrint('Error uploading image: $e');
            // Continue with other images even if one fails
          }
        }
        
        setState(() {
          _isUploadingImage = false;
        });
      }
      
      final bike = Bike(
        id: widget.bike?.id,
        customerId: widget.customerId,
        brand: _brandController.text.trim(),
        model: _modelController.text.trim(),
        year: int.tryParse(_yearController.text.trim()),
        bikeType: _selectedType,
        serialNumber: _serialNumberController.text.trim().isEmpty ? null : _serialNumberController.text.trim(),
        color: _colorController.text.trim().isEmpty ? null : _colorController.text.trim(),
        frameSize: _frameSizeController.text.trim().isEmpty ? null : _frameSizeController.text.trim(),
        wheelSize: _wheelSizeController.text.trim().isEmpty ? null : _wheelSizeController.text.trim(),
        purchaseDate: _purchaseDate,
        warrantyUntil: _warrantyUntil,
        notes: _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
        imageUrls: uploadedUrls,
      );

      if (widget.bike == null) {
        // Create new bike
        await bikeshopService.createBike(bike);
      } else {
        // Update existing bike
        await bikeshopService.updateBike(bike);
      }

      if (mounted) {
        Navigator.of(context).pop(true); // Return true to indicate success
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(widget.bike == null ? 'Bicicleta creada exitosamente' : 'Bicicleta actualizada exitosamente'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      setState(() {
        _isSaving = false;
        _isUploadingImage = false;
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al guardar bicicleta: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _confirmDelete() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmar eliminación'),
        content: Text('¿Está seguro que desea eliminar la bicicleta "${_brandController.text} ${_modelController.text}"?\n\nEsta acción no se puede deshacer.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirm == true && widget.bike?.id != null) {
      setState(() => _isSaving = true);
      
      try {
        final bikeshopService = Provider.of<BikeshopService>(context, listen: false);
        await bikeshopService.deleteBike(widget.bike!.id!);
        
        if (mounted) {
          Navigator.of(context).pop(null); // Return null to indicate deletion
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Bicicleta eliminada exitosamente'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        setState(() => _isSaving = false);
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error al eliminar bicicleta: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.bike != null;
    
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600, maxHeight: 700),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).primaryColor,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(4),
                  topRight: Radius.circular(4),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    isEditing ? Icons.edit : Icons.add_circle_outline,
                    color: Colors.white,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    isEditing ? 'Editar Bicicleta' : 'Nueva Bicicleta',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            
            // Form
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Brand & Model
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _brandController,
                              decoration: const InputDecoration(
                                labelText: 'Marca *',
                                hintText: 'Trek, Giant, Specialized...',
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(Icons.branding_watermark),
                              ),
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return 'La marca es requerida';
                                }
                                return null;
                              },
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: TextFormField(
                              controller: _modelController,
                              decoration: const InputDecoration(
                                labelText: 'Modelo *',
                                hintText: 'Marlin 7, Escape 3...',
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(Icons.directions_bike),
                              ),
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return 'El modelo es requerido';
                                }
                                return null;
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      
                      // Type & Year
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<BikeType>(
                              value: _selectedType,
                              decoration: const InputDecoration(
                                labelText: 'Tipo de Bicicleta',
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(Icons.category),
                              ),
                              items: BikeType.values.map((type) {
                                return DropdownMenuItem(
                                  value: type,
                                  child: Text(type.displayName),
                                );
                              }).toList(),
                              onChanged: (value) {
                                if (value != null) {
                                  setState(() {
                                    _selectedType = value;
                                  });
                                }
                              },
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: TextFormField(
                              controller: _yearController,
                              decoration: const InputDecoration(
                                labelText: 'Año',
                                hintText: '2024',
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(Icons.calendar_today),
                              ),
                              keyboardType: TextInputType.number,
                              validator: (value) {
                                if (value != null && value.isNotEmpty) {
                                  final year = int.tryParse(value);
                                  if (year == null || year < 1900 || year > DateTime.now().year + 1) {
                                    return 'Año inválido';
                                  }
                                }
                                return null;
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      
                      // Serial Number & Color
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _serialNumberController,
                              decoration: const InputDecoration(
                                labelText: 'Número de Serie',
                                hintText: 'ABC-12345',
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(Icons.qr_code),
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: TextFormField(
                              controller: _colorController,
                              decoration: const InputDecoration(
                                labelText: 'Color',
                                hintText: 'Rojo, Azul, Negro...',
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(Icons.palette),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      
                      // Frame Size & Wheel Size
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _frameSizeController,
                              decoration: const InputDecoration(
                                labelText: 'Talla del Cuadro',
                                hintText: 'M, L, 17", 54cm...',
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(Icons.straighten),
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: TextFormField(
                              controller: _wheelSizeController,
                              decoration: const InputDecoration(
                                labelText: 'Aro',
                                hintText: '29", 27.5", 26"...',
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(Icons.settings),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      
                      // Purchase Date & Warranty
                      Row(
                        children: [
                          Expanded(
                            child: InkWell(
                              onTap: () => _selectDate(context, true),
                              child: InputDecorator(
                                decoration: const InputDecoration(
                                  labelText: 'Fecha de Compra',
                                  border: OutlineInputBorder(),
                                  prefixIcon: Icon(Icons.shopping_cart),
                                ),
                                child: Text(
                                  _purchaseDate != null
                                      ? DateFormat('dd/MM/yyyy').format(_purchaseDate!)
                                      : 'Seleccionar fecha',
                                  style: TextStyle(
                                    color: _purchaseDate != null ? null : Colors.grey,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: InkWell(
                              onTap: () => _selectDate(context, false),
                              child: InputDecorator(
                                decoration: const InputDecoration(
                                  labelText: 'Garantía Hasta',
                                  border: OutlineInputBorder(),
                                  prefixIcon: Icon(Icons.verified_user),
                                ),
                                child: Text(
                                  _warrantyUntil != null
                                      ? DateFormat('dd/MM/yyyy').format(_warrantyUntil!)
                                      : 'Seleccionar fecha',
                                  style: TextStyle(
                                    color: _warrantyUntil != null ? null : Colors.grey,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      
                      // Images Section
                      const Text(
                        'Fotos de la Bicicleta',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      
                      // Image Grid
                      if (_imageUrls.isNotEmpty || _newImages.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey[300]!),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Wrap(
                            spacing: 12,
                            runSpacing: 12,
                            children: [
                              // Existing images from database
                              ..._imageUrls.asMap().entries.map((entry) {
                                final index = entry.key;
                                final url = entry.value;
                                return Stack(
                                  children: [
                                    Container(
                                      width: 120,
                                      height: 120,
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(color: Colors.grey[300]!),
                                        image: DecorationImage(
                                          image: NetworkImage(url),
                                          fit: BoxFit.cover,
                                        ),
                                      ),
                                    ),
                                    Positioned(
                                      top: 4,
                                      right: 4,
                                      child: InkWell(
                                        onTap: () => _removeImage(index, false),
                                        child: Container(
                                          padding: const EdgeInsets.all(4),
                                          decoration: BoxDecoration(
                                            color: Colors.red,
                                            shape: BoxShape.circle,
                                          ),
                                          child: const Icon(
                                            Icons.close,
                                            size: 16,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                );
                              }),
                              
                              // New images (not yet uploaded)
                              ..._newImages.asMap().entries.map((entry) {
                                final index = entry.key;
                                final imageData = entry.value;
                                return Stack(
                                  children: [
                                    Container(
                                      width: 120,
                                      height: 120,
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(color: Colors.blue[300]!, width: 2),
                                        image: DecorationImage(
                                          image: MemoryImage(imageData.bytes),
                                          fit: BoxFit.cover,
                                        ),
                                      ),
                                    ),
                                    Positioned(
                                      top: 4,
                                      right: 4,
                                      child: InkWell(
                                        onTap: () => _removeImage(index, true),
                                        child: Container(
                                          padding: const EdgeInsets.all(4),
                                          decoration: BoxDecoration(
                                            color: Colors.red,
                                            shape: BoxShape.circle,
                                          ),
                                          child: const Icon(
                                            Icons.close,
                                            size: 16,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                    ),
                                    Positioned(
                                      bottom: 4,
                                      left: 4,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: Colors.blue,
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: const Text(
                                          'NUEVA',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                );
                              }),
                            ],
                          ),
                        ),
                      const SizedBox(height: 12),
                      
                      // Add Image Button
                      OutlinedButton.icon(
                        onPressed: _isUploadingImage ? null : _pickImage,
                        icon: _isUploadingImage 
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.add_photo_alternate),
                        label: Text(_isUploadingImage ? 'Subiendo...' : 'Agregar Foto'),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(double.infinity, 48),
                        ),
                      ),
                      const SizedBox(height: 16),
                      
                      // Notes
                      TextFormField(
                        controller: _notesController,
                        decoration: const InputDecoration(
                          labelText: 'Notas',
                          hintText: 'Información adicional sobre la bicicleta...',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.note),
                        ),
                        maxLines: 3,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            
            // Actions
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                border: Border(top: BorderSide(color: Colors.grey[300]!)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Delete button (only show when editing)
                  if (widget.bike != null)
                    TextButton.icon(
                      onPressed: _isSaving ? null : _confirmDelete,
                      icon: const Icon(Icons.delete, color: Colors.red),
                      label: const Text('Eliminar', style: TextStyle(color: Colors.red)),
                    )
                  else
                    const SizedBox.shrink(),
                  // Right side buttons
                  Row(
                    children: [
                      TextButton(
                        onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
                        child: const Text('Cancelar'),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton.icon(
                        onPressed: _isSaving ? null : _saveBike,
                        icon: _isSaving
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.save),
                        label: Text(_isSaving ? 'Guardando...' : 'Guardar'),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
