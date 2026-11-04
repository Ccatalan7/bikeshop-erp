import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../shared/services/database_service.dart';
import '../../../shared/services/image_service.dart';
import '../../../shared/services/return_navigation.dart';
import '../../../shared/services/workspace_manager.dart';
import '../../../shared/widgets/branded_loading.dart';
import '../../../shared/services/tenant_service.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/main_layout.dart';
import '../../../shared/widgets/vb_status_badge.dart';
import '../../purchases/models/supplier_brand.dart';
import '../../purchases/services/supplier_brand_service.dart';
import '../../purchases/widgets/brand_mark.dart';
import '../../purchases/widgets/supplier_avatar.dart';
import '../models/brand_models.dart';
import '../services/brand_service.dart';

/// Una marca del catálogo. Al editar, dice también qué proveedores la traen
/// (`brand_suppliers_v1`, 20261103090000): una marca la traen varios y cada
/// uno se abre encima, sin perder la marca.
class BrandFormPage extends StatefulWidget {
  final String? brandId;

  /// Para pruebas: de dónde lee los proveedores de la marca.
  final SupplierBrandService? supplierBrandService;

  const BrandFormPage({super.key, this.brandId, this.supplierBrandService});

  @override
  State<BrandFormPage> createState() => _BrandFormPageState();
}

class _BrandFormPageState extends State<BrandFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _websiteController = TextEditingController();
  final _countryController = TextEditingController();

  late BrandService _brandService;
  late final SupplierBrandService _supplierBrandService =
      widget.supplierBrandService ?? SupplierBrandService();
  List<BrandSupplier>? _suppliers;
  Object? _suppliersError;
  ProductBrand? _existingBrand;
  bool _isActive = true;
  bool _isLoading = false;
  bool _isSaving = false;
  bool _logoSaving = false;

  @override
  void initState() {
    super.initState();
    _brandService = BrandService(
      Provider.of<DatabaseService>(context, listen: false),
    );

    if (widget.brandId != null) {
      _loadBrand();
      _loadSuppliers();
    }
  }

  Future<void> _loadSuppliers() async {
    try {
      final suppliers =
          await _supplierBrandService.suppliersOf(widget.brandId!);
      if (!mounted) return;
      setState(() {
        _suppliers = suppliers;
        _suppliersError = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _suppliersError = error);
    }
  }

  /// La ficha del proveedor se empuja en el espacio activo; al volver se
  /// releen por si cambió algo allá.
  Future<void> _openSupplier(BrandSupplier supplier) async {
    final route = '/purchases/suppliers/${supplier.supplierId}';
    WorkspaceManager? workspace;
    try {
      workspace = context.read<WorkspaceManager>();
    } on ProviderNotFoundException {
      workspace = null;
    }
    if (workspace != null) {
      await workspace.pushActiveWorkspace<void>(route);
    } else {
      await context.push<void>(route);
    }
    if (mounted) await _loadSuppliers();
  }

  void _close() =>
      ReturnNavigation.close(context, fallbackRoute: '/inventory/brands');

  /// El logo de una marca del taller: una imagen cuadrada en
  /// `vinabike-assets/brands/<taller>/<marca>`. Las del catálogo compartido
  /// las cura la plataforma.
  Future<void> _changeLogo({bool remove = false}) async {
    final brand = _existingBrand;
    if (brand == null || brand.id == null || brand.isShared || _logoSaving) {
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    String? url;
    if (!remove) {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.image,
        withData: true,
      );
      final file = picked?.files.singleOrNull;
      final bytes = file?.bytes;
      if (file == null || bytes == null || bytes.isEmpty || !mounted) return;
      setState(() => _logoSaving = true);
      try {
        url = await ImageService.uploadBytes(
          bytes: bytes,
          fileName: file.name,
          bucket: 'vinabike-assets',
          folder: 'brands/${brand.tenantId}/${brand.id}',
        );
        if (url == null) throw StateError('La imagen no se pudo subir.');
      } catch (error) {
        if (mounted) {
          setState(() => _logoSaving = false);
          messenger.showSnackBar(
            SnackBar(content: Text('No se pudo subir el logo: $error')),
          );
        }
        return;
      }
    } else {
      setState(() => _logoSaving = true);
    }
    try {
      await _brandService.updateBrandLogo(brand.id!, url);
      if (!mounted) return;
      setState(() => _existingBrand = brand.copyWithLogo(url));
      messenger.showSnackBar(
        SnackBar(content: Text(remove ? 'Logo quitado' : 'Logo actualizado')),
      );
    } catch (error) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text('No se pudo guardar el logo: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _logoSaving = false);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _websiteController.dispose();
    _countryController.dispose();
    super.dispose();
  }

  Future<void> _loadBrand() async {
    setState(() => _isLoading = true);
    try {
      final brand = await _brandService.getBrandById(widget.brandId!);
      if (brand != null) {
        setState(() {
          _existingBrand = brand;
          _nameController.text = brand.name;
          _descriptionController.text = brand.description ?? '';
          _websiteController.text = brand.website ?? '';
          _countryController.text = brand.country ?? '';
          _isActive = brand.isActive;
        });
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error cargando marca: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _saveBrand() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      final normalizedWebsite = _websiteController.text.trim();
      if (normalizedWebsite.isNotEmpty) {
        final uri = Uri.tryParse(normalizedWebsite);
        if (uri == null || (!uri.hasScheme && !uri.hasAuthority)) {
          throw Exception('Ingresa un sitio web válido (incluye https://)');
        }
      }

      final tenantId = await TenantService().getTenantId();
      if (tenantId == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Error: No se pudo obtener el tenant ID')),
          );
        }
        return;
      }

      final brand = ProductBrand(
        id: _existingBrand?.id,
        tenantId: tenantId,
        logoUrl: _existingBrand?.logoUrl,
        name: _nameController.text.trim(),
        description: _descriptionController.text.trim().isEmpty
            ? null
            : _descriptionController.text.trim(),
        website: normalizedWebsite.isEmpty ? null : normalizedWebsite,
        country: _countryController.text.trim().isEmpty
            ? null
            : _countryController.text.trim(),
        isActive: _isActive,
      );

      if (_existingBrand != null) {
        await _brandService.updateBrand(brand);
      } else {
        await _brandService.createBrand(brand);
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_existingBrand != null
              ? 'Marca actualizada correctamente'
              : 'Marca creada correctamente'),
          backgroundColor: Colors.green,
        ),
      );
      _close();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo guardar la marca: $e'),
          backgroundColor: Colors.red,
        ),
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
      child: _isLoading
          ? const Center(child: BrandedLoading())
          : _buildForm(context),
    );
  }

  Widget _buildForm(BuildContext context) {
    return Form(
      key: _formKey,
      child: Column(
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final isMobile = constraints.maxWidth < 600;

              if (isMobile) {
                return Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.arrow_back),
                            onPressed: _close,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _existingBrand != null
                                  ? 'Editar Marca'
                                  : 'Nueva Marca',
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: AppButton(
                          text: 'Guardar',
                          icon: Icons.save,
                          onPressed: _isSaving ? null : _saveBrand,
                          isLoading: _isSaving,
                        ),
                      ),
                    ],
                  ),
                );
              }

              return Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back),
                      onPressed: _close,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _existingBrand != null ? 'Editar Marca' : 'Nueva Marca',
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    AppButton(
                      text: 'Guardar',
                      icon: Icons.save,
                      onPressed: _isSaving ? null : _saveBrand,
                      isLoading: _isSaving,
                    ),
                  ],
                ),
              );
            },
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Center(
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 640),
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.04),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_existingBrand case final brand?) ...[
                        _BrandLogoBlock(
                          brand: brand,
                          saving: _logoSaving,
                          onChange: () => _changeLogo(),
                          onRemove: () => _changeLogo(remove: true),
                        ),
                        const SizedBox(height: 20),
                      ],
                      const Text(
                        'Información de la marca',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _nameController,
                        decoration: const InputDecoration(
                          labelText: 'Nombre *',
                          hintText: 'Ej: Trek, Specialized, Shimano',
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'El nombre es obligatorio';
                          }
                          if (value.trim().length < 2) {
                            return 'El nombre debe tener al menos 2 caracteres';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _descriptionController,
                        maxLines: 3,
                        decoration: const InputDecoration(
                          labelText: 'Descripción',
                          hintText:
                              'Resumen breve para identificar fortalezas de la marca',
                          border: OutlineInputBorder(),
                          alignLabelWithHint: true,
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _websiteController,
                        decoration: const InputDecoration(
                          labelText: 'Sitio web',
                          hintText: 'https://example.com',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.link_outlined),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _countryController,
                        decoration: const InputDecoration(
                          labelText: 'País de origen',
                          hintText: 'Ej: Estados Unidos, Chile, Italia',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.public_outlined),
                        ),
                      ),
                      const SizedBox(height: 24),
                      SwitchListTile(
                        title: const Text('Marca activa'),
                        subtitle: Text(
                          _isActive
                              ? 'La marca estará disponible para asignar a productos.'
                              : 'La marca permanecerá oculta, pero conservará su historial.',
                        ),
                        value: _isActive,
                        onChanged: (value) {
                          setState(() => _isActive = value);
                        },
                      ),
                      if (widget.brandId != null) ...[
                        const SizedBox(height: 24),
                        const Divider(height: 1),
                        const SizedBox(height: 20),
                        _BrandSuppliersSection(
                          brandName: _nameController.text.trim().isEmpty
                              ? 'esta marca'
                              : _nameController.text.trim(),
                          suppliers: _suppliers,
                          error: _suppliersError,
                          onRetry: _loadSuppliers,
                          onOpen: _openSupplier,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Quién trae la marca: primero el representante oficial, luego los demás
/// por lo último que se les compró. Cada uno abre su ficha.
class _BrandSuppliersSection extends StatelessWidget {
  const _BrandSuppliersSection({
    required this.brandName,
    required this.suppliers,
    required this.error,
    required this.onRetry,
    required this.onOpen,
  });

  final String brandName;
  final List<BrandSupplier>? suppliers;
  final Object? error;
  final VoidCallback onRetry;
  final ValueChanged<BrandSupplier> onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final list = suppliers;
    final Widget body;
    if (error != null) {
      body = Row(
        children: [
          Expanded(
            child: Text(
              'No pudimos cargar quién la trae.',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
          TextButton(
            onPressed: onRetry,
            style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
            child: const Text('Reintentar'),
          ),
        ],
      );
    } else if (list == null) {
      body = Text(
        'Buscando quién la trae…',
        style: theme.textTheme.bodyMedium
            ?.copyWith(color: scheme.onSurfaceVariant),
      );
    } else if (list.isEmpty) {
      body = Text(
        'Ningún proveedor la tiene asignada todavía. Se agrega desde la ficha '
        'del proveedor, en Marcas.',
        style: theme.textTheme.bodyMedium
            ?.copyWith(color: scheme.onSurfaceVariant),
      );
    } else {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var index = 0; index < list.length; index++)
            _BrandSupplierRow(
              supplier: list[index],
              first: index == 0,
              onTap: () => onOpen(list[index]),
            ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            const Expanded(
              child: Text(
                'Proveedores que la traen',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            if (list != null && list.isNotEmpty)
              Text(
                '${list.length}',
                style: theme.textTheme.labelLarge
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'A quién pedirle $brandName.',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 12),
        body,
      ],
    );
  }
}

class _BrandSupplierRow extends StatelessWidget {
  const _BrandSupplierRow({
    required this.supplier,
    required this.first,
    required this.onTap,
  });

  final BrandSupplier supplier;
  final bool first;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    String two(int n) => n.toString().padLeft(2, '0');
    final last = supplier.lastPurchase?.toLocal();
    final facts = supplier.purchases > 0
        ? '${supplier.purchases} ${supplier.purchases == 1 ? 'compra' : 'compras'}'
            '${last == null ? '' : ' · la última el ${two(last.day)}/${two(last.month)}/${last.year}'}'
        : 'Sin compras de esta marca en el ERP';
    return InkWell(
      key: ValueKey('brand-supplier-${supplier.supplierId}'),
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 56),
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          border: first
              ? null
              : Border(top: BorderSide(color: scheme.outlineVariant)),
        ),
        child: Row(
          children: [
            SupplierAvatar(
              name: supplier.name,
              imageUrl: supplier.imageUrl,
              size: 38,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        supplier.name,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: supplier.isActive
                              ? scheme.onSurface
                              : scheme.onSurfaceVariant,
                        ),
                      ),
                      if (supplier.official)
                        const VbStatusBadge(
                          label: 'Representante oficial',
                          tone: VbStatusTone.success,
                          dense: true,
                        ),
                      if (!supplier.isActive)
                        const VbStatusBadge(
                          label: 'Inactivo',
                          tone: VbStatusTone.neutral,
                          dense: true,
                        ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    facts,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

/// El logo de la marca arriba de su ficha: grande, con cambiar y quitar si
/// es del taller; las del catálogo compartido sólo se ven.
class _BrandLogoBlock extends StatelessWidget {
  const _BrandLogoBlock({
    required this.brand,
    required this.saving,
    required this.onChange,
    required this.onRemove,
  });

  final ProductBrand brand;
  final bool saving;
  final VoidCallback onChange;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final hasLogo = (brand.logoUrl ?? '').isNotEmpty;
    return Row(
      children: [
        BrandMark(name: brand.name, logoUrl: brand.logoUrl, size: 72),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                brand.name,
                style: theme.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              if (brand.isShared)
                Text(
                  hasLogo
                      ? 'Marca del catálogo compartido: su logo lo cuida Viñabike.'
                      : 'Marca del catálogo compartido: todavía sin logo.',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                )
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    TextButton.icon(
                      key: const ValueKey('brand-logo-change'),
                      onPressed: saving ? null : onChange,
                      style: TextButton.styleFrom(
                        minimumSize: const Size(48, 40),
                      ),
                      icon: const Icon(Icons.image_outlined, size: 18),
                      label: Text(hasLogo ? 'Cambiar logo' : 'Agregar logo'),
                    ),
                    if (hasLogo)
                      TextButton(
                        key: const ValueKey('brand-logo-remove'),
                        onPressed: saving ? null : onRemove,
                        style: TextButton.styleFrom(
                          minimumSize: const Size(48, 40),
                        ),
                        child: const Text('Quitar logo'),
                      ),
                  ],
                ),
            ],
          ),
        ),
      ],
    );
  }
}
