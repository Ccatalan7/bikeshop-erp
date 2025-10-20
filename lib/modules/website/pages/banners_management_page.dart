import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/website_service.dart';
import '../models/website_models.dart';

/// Page for managing website banners (hero images, promotional banners)
class BannersManagementPage extends StatefulWidget {
  const BannersManagementPage({super.key});

  @override
  State<BannersManagementPage> createState() => _BannersManagementPageState();
}

class _BannersManagementPageState extends State<BannersManagementPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<WebsiteService>().loadBanners();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final websiteService = context.watch<WebsiteService>();

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('Banners del Sitio'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => websiteService.loadBanners(),
            tooltip: 'Actualizar',
          ),
        ],
      ),
      body: websiteService.isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Info banner
                Container(
                  padding: const EdgeInsets.all(16),
                  margin: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Los banners aparecen en la página principal del sitio web. Arrastra para reordenar.',
                          style: TextStyle(
                            color: theme.colorScheme.onPrimaryContainer,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Banners list
                Expanded(
                  child: websiteService.banners.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.image_outlined,
                                size: 64,
                                color: Colors.grey[400],
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'No hay banners',
                                style: TextStyle(
                                  fontSize: 18,
                                  color: Colors.grey[600],
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Agrega tu primer banner',
                                style: TextStyle(
                                  color: Colors.grey[500],
                                ),
                              ),
                            ],
                          ),
                        )
                      : ReorderableListView(
                          padding: const EdgeInsets.all(16),
                          onReorder: (oldIndex, newIndex) {
                            _reorderBanners(
                              websiteService,
                              oldIndex,
                              newIndex,
                            );
                          },
                          children: websiteService.banners.map((banner) {
                            return _buildBannerCard(
                              context,
                              banner,
                              websiteService,
                            );
                          }).toList(),
                        ),
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showBannerDialog(context),
        icon: const Icon(Icons.add),
        label: const Text('Nuevo Banner'),
      ),
    );
  }

  Widget _buildBannerCard(
    BuildContext context,
    WebsiteBanner banner,
    WebsiteService service,
  ) {
    final theme = Theme.of(context);

    return Card(
      key: ValueKey(banner.id),
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Image preview
          if (banner.imageUrl != null)
            ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(8),
              ),
              child: CachedNetworkImage(
                imageUrl: banner.imageUrl!,
                height: 200,
                width: double.infinity,
                fit: BoxFit.cover,
                placeholder: (context, url) => Container(
                  height: 200,
                  color: Colors.grey[300],
                  child: const Center(
                    child: CircularProgressIndicator(),
                  ),
                ),
                errorWidget: (context, url, error) => Container(
                  height: 200,
                  color: Colors.grey[300],
                  child: const Icon(
                    Icons.broken_image,
                    size: 48,
                    color: Colors.grey,
                  ),
                ),
              ),
            ),

          // Banner info
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    // Drag handle
                    Icon(
                      Icons.drag_handle,
                      color: Colors.grey[400],
                    ),
                    const SizedBox(width: 8),

                    // Title
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            banner.title,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (banner.subtitle != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              banner.subtitle!,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),

                    // Active toggle
                    Switch(
                      value: banner.active,
                      onChanged: (value) {
                        _toggleBannerActive(service, banner, value);
                      },
                    ),
                    const SizedBox(width: 8),
                    Text(
                      banner.active ? 'Activo' : 'Inactivo',
                      style: TextStyle(
                        color: banner.active
                            ? Colors.green
                            : Colors.grey[600],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),

                // CTA info
                if (banner.ctaText != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.touch_app,
                          size: 16,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          banner.ctaText!,
                          style: TextStyle(
                            color: theme.colorScheme.onPrimaryContainer,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                // Actions
                const SizedBox(height: 12),
                Row(
                  children: [
                    TextButton.icon(
                      onPressed: () => _showBannerDialog(
                        context,
                        banner: banner,
                      ),
                      icon: const Icon(Icons.edit),
                      label: const Text('Editar'),
                    ),
                    const SizedBox(width: 8),
                    TextButton.icon(
                      onPressed: () => _deleteBanner(context, service, banner),
                      icon: const Icon(Icons.delete),
                      label: const Text('Eliminar'),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.red,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _reorderBanners(
    WebsiteService service,
    int oldIndex,
    int newIndex,
  ) {
    if (newIndex > oldIndex) {
      newIndex -= 1;
    }

    final banners = List<WebsiteBanner>.from(service.banners);
    final banner = banners.removeAt(oldIndex);
    banners.insert(newIndex, banner);

    // Update order_index for all banners
    final reordered = banners.asMap().entries.map((entry) {
      return entry.value.copyWith(orderIndex: entry.key);
    }).toList();

    service.reorderBanners(reordered);
  }

  void _toggleBannerActive(
    WebsiteService service,
    WebsiteBanner banner,
    bool active,
  ) {
    final updated = banner.copyWith(active: active);
    service.saveBanner(updated);
  }

  Future<void> _deleteBanner(
    BuildContext context,
    WebsiteService service,
    WebsiteBanner banner,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar Banner'),
        content: Text('¿Estás seguro de eliminar "${banner.title}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      try {
        await service.deleteBanner(banner.id);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Banner eliminado')),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e')),
          );
        }
      }
    }
  }

  void _showBannerDialog(BuildContext context, {WebsiteBanner? banner}) {
    showDialog(
      context: context,
      builder: (context) => _BannerFormDialog(banner: banner),
    );
  }
}

/// Dialog for adding/editing banners
class _BannerFormDialog extends StatefulWidget {
  final WebsiteBanner? banner;

  const _BannerFormDialog({this.banner});

  @override
  State<_BannerFormDialog> createState() => _BannerFormDialogState();
}

class _BannerFormDialogState extends State<_BannerFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleController;
  late final TextEditingController _subtitleController;
  late final TextEditingController _imageUrlController;
  late final TextEditingController _linkController;
  late final TextEditingController _ctaTextController;
  late final TextEditingController _ctaLinkController;
  late bool _active;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.banner?.title ?? '');
    _subtitleController = TextEditingController(text: widget.banner?.subtitle ?? '');
    _imageUrlController = TextEditingController(text: widget.banner?.imageUrl ?? '');
    _linkController = TextEditingController(text: widget.banner?.link ?? '');
    _ctaTextController = TextEditingController(text: widget.banner?.ctaText ?? '');
    _ctaLinkController = TextEditingController(text: widget.banner?.ctaLink ?? '');
    _active = widget.banner?.active ?? true;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _subtitleController.dispose();
    _imageUrlController.dispose();
    _linkController.dispose();
    _ctaTextController.dispose();
    _ctaLinkController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.banner == null ? 'Nuevo Banner' : 'Editar Banner'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: SizedBox(
            width: 500,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Title
                TextFormField(
                  controller: _titleController,
                  decoration: const InputDecoration(
                    labelText: 'Título *',
                    hintText: 'Ej: Bienvenido a Vinabike',
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'El título es requerido';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // Subtitle
                TextFormField(
                  controller: _subtitleController,
                  decoration: const InputDecoration(
                    labelText: 'Subtítulo',
                    hintText: 'Ej: Las mejores bicicletas de Chile',
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 16),

                // Image URL
                TextFormField(
                  controller: _imageUrlController,
                  decoration: const InputDecoration(
                    labelText: 'URL de Imagen *',
                    hintText: 'https://...',
                    helperText: 'Por ahora ingresa una URL. Próximamente: subir archivo',
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'La URL de imagen es requerida';
                    }
                    if (!value.startsWith('http')) {
                      return 'Debe ser una URL válida (http/https)';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // Link
                TextFormField(
                  controller: _linkController,
                  decoration: const InputDecoration(
                    labelText: 'Enlace',
                    hintText: '/productos o https://...',
                  ),
                ),
                const SizedBox(height: 16),

                // CTA Text
                TextFormField(
                  controller: _ctaTextController,
                  decoration: const InputDecoration(
                    labelText: 'Texto del Botón',
                    hintText: 'Ej: Ver Catálogo',
                  ),
                ),
                const SizedBox(height: 16),

                // CTA Link
                TextFormField(
                  controller: _ctaLinkController,
                  decoration: const InputDecoration(
                    labelText: 'Enlace del Botón',
                    hintText: '/catalogo',
                  ),
                ),
                const SizedBox(height: 16),

                // Active toggle
                SwitchListTile(
                  title: const Text('Banner activo'),
                  subtitle: const Text('Solo banners activos se muestran en el sitio'),
                  value: _active,
                  onChanged: (value) {
                    setState(() => _active = value);
                  },
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: _isSaving ? null : _saveBanner,
          child: _isSaving
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Guardar'),
        ),
      ],
    );
  }

  Future<void> _saveBanner() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      final service = context.read<WebsiteService>();
      
      final banner = WebsiteBanner(
        id: widget.banner?.id ?? DateTime.now().millisecondsSinceEpoch.toString(),
        title: _titleController.text.trim(),
        subtitle: _subtitleController.text.trim().isEmpty
            ? null
            : _subtitleController.text.trim(),
        imageUrl: _imageUrlController.text.trim(),
        link: _linkController.text.trim().isEmpty
            ? null
            : _linkController.text.trim(),
        ctaText: _ctaTextController.text.trim().isEmpty
            ? null
            : _ctaTextController.text.trim(),
        ctaLink: _ctaLinkController.text.trim().isEmpty
            ? null
            : _ctaLinkController.text.trim(),
        active: _active,
        orderIndex: widget.banner?.orderIndex ?? service.banners.length,
        createdAt: widget.banner?.createdAt ?? DateTime.now(),
        updatedAt: DateTime.now(),
      );

      await service.saveBanner(banner);

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Banner guardado exitosamente')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }
}
