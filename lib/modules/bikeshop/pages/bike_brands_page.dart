import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../shared/widgets/main_layout.dart';
import '../../../shared/services/tenant_service.dart';
import '../models/bikeshop_models.dart';
import '../services/bikeshop_service.dart';

class BikeBrandsPage extends StatefulWidget {
  const BikeBrandsPage({super.key});

  @override
  State<BikeBrandsPage> createState() => _BikeBrandsPageState();
}

class _BikeBrandsPageState extends State<BikeBrandsPage> {
  final TextEditingController _searchController = TextEditingController();
  String? _expandedBrandId;
  bool _showInactive = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadBrands();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadBrands() async {
    final service = context.read<BikeshopService>();
    await service.getBikeBrands(activeOnly: !_showInactive);
  }

  void _showBrandDialog({BikeBrand? brand}) async {
    final result = await showDialog<BikeBrand>(
      context: context,
      builder: (context) => _BrandDialog(brand: brand),
    );

    if (result != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(brand == null
              ? 'Marca creada exitosamente'
              : 'Marca actualizada exitosamente'),
          backgroundColor: Colors.green,
        ),
      );
      _loadBrands();
    }
  }

  void _showModelDialog(String brandId, {BikeModel? model}) async {
    final result = await showDialog<BikeModel>(
      context: context,
      builder: (context) => _ModelDialog(brandId: brandId, model: model),
    );

    if (result != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(model == null
              ? 'Modelo creado exitosamente'
              : 'Modelo actualizado exitosamente'),
          backgroundColor: Colors.green,
        ),
      );
      _loadBrands();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MainLayout(
      title: 'Marcas y Modelos de Bicicletas',
      child: Column(
        children: [
          // Action bar
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              border: Border(
                bottom: BorderSide(
                  color: Theme.of(context).dividerColor,
                  width: 1,
                ),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Buscar marcas o modelos...',
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 16),
                FilterChip(
                  label: const Text('Mostrar inactivos'),
                  selected: _showInactive,
                  onSelected: (value) {
                    setState(() => _showInactive = value);
                    _loadBrands();
                  },
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  icon: const Icon(Icons.add),
                  label: const Text('Nueva Marca'),
                  onPressed: () => _showBrandDialog(),
                ),
              ],
            ),
          ),
          // Content
          Expanded(
            child: FutureBuilder<List<BikeBrand>>(
              future: context
                  .read<BikeshopService>()
                  .getBikeBrands(activeOnly: !_showInactive),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error_outline,
                            size: 64, color: Colors.red),
                        const SizedBox(height: 16),
                        Text('Error: ${snapshot.error}'),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: _loadBrands,
                          child: const Text('Reintentar'),
                        ),
                      ],
                    ),
                  );
                }

                final brands = snapshot.data ?? [];
                final filteredBrands = brands.where((brand) {
                  if (_searchController.text.isEmpty) return true;
                  final query = _searchController.text.toLowerCase();
                  return brand.name.toLowerCase().contains(query);
                }).toList();

                if (filteredBrands.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.branding_watermark,
                            size: 64, color: Colors.grey[400]),
                        const SizedBox(height: 16),
                        Text(
                          'No hay marcas registradas',
                          style: TextStyle(color: Colors.grey[600]),
                        ),
                        const SizedBox(height: 24),
                        ElevatedButton.icon(
                          onPressed: () => _showBrandDialog(),
                          icon: const Icon(Icons.add),
                          label: const Text('Crear Primera Marca'),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: filteredBrands.length,
                  itemBuilder: (context, index) {
                    final brand = filteredBrands[index];
                    final isExpanded = _expandedBrandId == brand.id;

                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: Column(
                        children: [
                          ListTile(
                            leading: CircleAvatar(
                              backgroundColor: brand.isActive
                                  ? Colors.blue.withOpacity(0.2)
                                  : Colors.grey.withOpacity(0.2),
                              child: Icon(
                                Icons.pedal_bike,
                                color: brand.isActive ? Colors.blue : Colors.grey,
                              ),
                            ),
                            title: Text(
                              brand.name,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: brand.isActive ? null : Colors.grey,
                              ),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (brand.country != null)
                                  Text('País: ${brand.country}'),
                                if (brand.description != null)
                                  Text(
                                    brand.description!,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                              ],
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (!brand.isActive)
                                  const Chip(
                                    label: Text('Inactivo'),
                                    backgroundColor: Colors.grey,
                                  ),
                                IconButton(
                                  icon: const Icon(Icons.edit, size: 20),
                                  onPressed: () => _showBrandDialog(brand: brand),
                                  tooltip: 'Editar marca',
                                ),
                                IconButton(
                                  icon: Icon(
                                    isExpanded
                                        ? Icons.expand_less
                                        : Icons.expand_more,
                                  ),
                                  onPressed: () {
                                    setState(() {
                                      _expandedBrandId =
                                          isExpanded ? null : brand.id;
                                    });
                                  },
                                  tooltip: 'Ver modelos',
                                ),
                              ],
                            ),
                          ),
                          if (isExpanded && brand.id != null)
                            _buildModelsSection(brand.id!),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModelsSection(String brandId) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        border: Border(
          top: BorderSide(color: Colors.grey[300]!),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Modelos',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              ElevatedButton.icon(
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Añadir Modelo'),
                style: ElevatedButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                onPressed: () => _showModelDialog(brandId),
              ),
            ],
          ),
          const SizedBox(height: 12),
          FutureBuilder<List<BikeModel>>(
            future: context
                .read<BikeshopService>()
                .getBikeModels(brandId: brandId, activeOnly: !_showInactive),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                    child: Padding(
                  padding: EdgeInsets.all(16.0),
                  child: CircularProgressIndicator(),
                ));
              }

              final models = snapshot.data ?? [];

              if (models.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Text(
                    'No hay modelos para esta marca',
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                );
              }

              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children: models.map((model) {
                  return ActionChip(
                    avatar: model.isActive
                        ? const Icon(Icons.bike_scooter, size: 18)
                        : const Icon(Icons.block, size: 18),
                    label: Text(model.displayName),
                    backgroundColor:
                        model.isActive ? Colors.blue[50] : Colors.grey[200],
                    onPressed: () => _showModelDialog(brandId, model: model),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}

// ============================================================
// BRAND DIALOG
// ============================================================

class _BrandDialog extends StatefulWidget {
  final BikeBrand? brand;

  const _BrandDialog({this.brand});

  @override
  State<_BrandDialog> createState() => _BrandDialogState();
}

class _BrandDialogState extends State<_BrandDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _countryController;
  late TextEditingController _websiteController;
  late TextEditingController _descriptionController;
  bool _isActive = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.brand?.name);
    _countryController = TextEditingController(text: widget.brand?.country);
    _websiteController = TextEditingController(text: widget.brand?.website);
    _descriptionController =
        TextEditingController(text: widget.brand?.description);
    _isActive = widget.brand?.isActive ?? true;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _countryController.dispose();
    _websiteController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      final service = context.read<BikeshopService>();
      final tenantService = context.read<TenantService>();
      final tenantId = await tenantService.getTenantId();

      if (tenantId == null) {
        throw Exception('No se pudo obtener el tenant ID');
      }

      final brand = BikeBrand(
        id: widget.brand?.id,
        tenantId: tenantId,
        name: _nameController.text.trim(),
        country: _countryController.text.trim().isEmpty
            ? null
            : _countryController.text.trim(),
        website: _websiteController.text.trim().isEmpty
            ? null
            : _websiteController.text.trim(),
        description: _descriptionController.text.trim().isEmpty
            ? null
            : _descriptionController.text.trim(),
        isActive: _isActive,
      );

      BikeBrand savedBrand;
      if (widget.brand == null) {
        savedBrand = await service.createBikeBrand(brand);
      } else {
        savedBrand = await service.updateBikeBrand(brand);
      }

      if (mounted) {
        Navigator.of(context).pop(savedBrand);
      }
    } catch (e) {
      setState(() => _isSaving = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _delete() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmar eliminación'),
        content: Text(
            '¿Está seguro que desea eliminar la marca "${_nameController.text}"?\n\nEsto también eliminará todos sus modelos asociados.'),
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

    if (confirm == true && widget.brand?.id != null) {
      setState(() => _isSaving = true);

      try {
        final service = context.read<BikeshopService>();
        await service.deleteBikeBrand(widget.brand!.id!);

        if (mounted) {
          Navigator.of(context).pop();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Marca eliminada exitosamente'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        setState(() => _isSaving = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error al eliminar: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.brand != null;

    return AlertDialog(
      title: Text(isEditing ? 'Editar Marca' : 'Nueva Marca'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Nombre *',
                  hintText: 'Trek, Giant, Specialized...',
                  prefixIcon: Icon(Icons.branding_watermark),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'El nombre es requerido';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _countryController,
                decoration: const InputDecoration(
                  labelText: 'País',
                  hintText: 'EE.UU., Italia, Alemania...',
                  prefixIcon: Icon(Icons.flag),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _websiteController,
                decoration: const InputDecoration(
                  labelText: 'Sitio Web',
                  hintText: 'https://...',
                  prefixIcon: Icon(Icons.link),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _descriptionController,
                decoration: const InputDecoration(
                  labelText: 'Descripción',
                  prefixIcon: Icon(Icons.description),
                ),
                maxLines: 3,
              ),
              const SizedBox(height: 16),
              SwitchListTile(
                title: const Text('Activo'),
                value: _isActive,
                onChanged: (value) => setState(() => _isActive = value),
              ),
            ],
          ),
        ),
      ),
      actions: [
        if (isEditing)
          TextButton(
            onPressed: _isSaving ? null : _delete,
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Eliminar'),
          ),
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: _isSaving ? null : _save,
          child: _isSaving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(isEditing ? 'Guardar' : 'Crear'),
        ),
      ],
    );
  }
}

// ============================================================
// MODEL DIALOG
// ============================================================

class _ModelDialog extends StatefulWidget {
  final String brandId;
  final BikeModel? model;

  const _ModelDialog({required this.brandId, this.model});

  @override
  State<_ModelDialog> createState() => _ModelDialogState();
}

class _ModelDialogState extends State<_ModelDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _yearController;
  late TextEditingController _descriptionController;
  bool _isActive = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.model?.name);
    _yearController =
        TextEditingController(text: widget.model?.year?.toString());
    _descriptionController =
        TextEditingController(text: widget.model?.description);
    _isActive = widget.model?.isActive ?? true;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _yearController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      final service = context.read<BikeshopService>();
      final tenantService = context.read<TenantService>();
      final tenantId = await tenantService.getTenantId();

      if (tenantId == null) {
        throw Exception('No se pudo obtener el tenant ID');
      }

      final model = BikeModel(
        id: widget.model?.id,
        tenantId: tenantId,
        brandId: widget.brandId,
        name: _nameController.text.trim(),
        year: int.tryParse(_yearController.text.trim()),
        description: _descriptionController.text.trim().isEmpty
            ? null
            : _descriptionController.text.trim(),
        isActive: _isActive,
      );

      BikeModel savedModel;
      if (widget.model == null) {
        savedModel = await service.createBikeModel(model);
      } else {
        savedModel = await service.updateBikeModel(model);
      }

      if (mounted) {
        Navigator.of(context).pop(savedModel);
      }
    } catch (e) {
      setState(() => _isSaving = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _delete() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmar eliminación'),
        content: Text(
            '¿Está seguro que desea eliminar el modelo "${_nameController.text}"?'),
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

    if (confirm == true && widget.model?.id != null) {
      setState(() => _isSaving = true);

      try {
        final service = context.read<BikeshopService>();
        await service.deleteBikeModel(widget.model!.id!);

        if (mounted) {
          Navigator.of(context).pop();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Modelo eliminado exitosamente'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        setState(() => _isSaving = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error al eliminar: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.model != null;

    return AlertDialog(
      title: Text(isEditing ? 'Editar Modelo' : 'Nuevo Modelo'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Nombre *',
                  hintText: 'Marlin, Domane, Stumpjumper...',
                  prefixIcon: Icon(Icons.bike_scooter),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'El nombre es requerido';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _yearController,
                decoration: const InputDecoration(
                  labelText: 'Año',
                  hintText: '2024',
                  prefixIcon: Icon(Icons.calendar_today),
                ),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _descriptionController,
                decoration: const InputDecoration(
                  labelText: 'Descripción',
                  prefixIcon: Icon(Icons.description),
                ),
                maxLines: 3,
              ),
              const SizedBox(height: 16),
              SwitchListTile(
                title: const Text('Activo'),
                value: _isActive,
                onChanged: (value) => setState(() => _isActive = value),
              ),
            ],
          ),
        ),
      ),
      actions: [
        if (isEditing)
          TextButton(
            onPressed: _isSaving ? null : _delete,
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Eliminar'),
          ),
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: _isSaving ? null : _save,
          child: _isSaving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(isEditing ? 'Guardar' : 'Crear'),
        ),
      ],
    );
  }
}
