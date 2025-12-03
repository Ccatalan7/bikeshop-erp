import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/website_edit_mode_provider.dart';
import '../services/website_service.dart';

/// Professional side panel editor for website blocks
/// Inspired by Odoo's website builder - clean, functional, elegant
class WebsiteEditorPanel extends StatefulWidget {
  final VoidCallback? onSave;
  final VoidCallback? onDiscard;

  const WebsiteEditorPanel({
    super.key,
    this.onSave,
    this.onDiscard,
  });

  @override
  State<WebsiteEditorPanel> createState() => _WebsiteEditorPanelState();
}

class _WebsiteEditorPanelState extends State<WebsiteEditorPanel> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _activeTab = 'edit'; // 'add', 'edit', 'theme'

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final editProvider = context.watch<WebsiteEditModeProvider>();
    
    if (!editProvider.isEditMode) {
      return const SizedBox.shrink();
    }

    return Container(
      width: 320,
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        border: Border(
          left: BorderSide(
            color: Colors.white.withValues(alpha: 0.1),
            width: 1,
          ),
        ),
      ),
      child: Column(
        children: [
          _buildHeader(editProvider),
          _buildTabBar(),
          Expanded(
            child: _buildTabContent(editProvider),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(WebsiteEditModeProvider editProvider) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF2D2D2D),
        border: Border(
          bottom: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
        ),
      ),
      child: Row(
        children: [
          // Undo/Redo buttons
          _buildIconButton(Icons.undo, 'Deshacer', null),
          _buildIconButton(Icons.redo, 'Rehacer', null),
          const SizedBox(width: 8),
          // Preview button
          _buildIconButton(Icons.phone_android, 'Vista móvil', () {}),
          const Spacer(),
          // Discard button
          TextButton(
            onPressed: widget.onDiscard,
            style: TextButton.styleFrom(
              foregroundColor: Colors.white70,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            child: const Text('Descartar'),
          ),
          const SizedBox(width: 8),
          // Save button
          ElevatedButton(
            onPressed: editProvider.hasUnsavedChanges ? widget.onSave : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00A09D),
              foregroundColor: Colors.white,
              disabledBackgroundColor: const Color(0xFF00A09D).withValues(alpha: 0.5),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
            ),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
  }

  Widget _buildIconButton(IconData icon, String tooltip, VoidCallback? onPressed) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          padding: const EdgeInsets.all(8),
          child: Icon(
            icon,
            color: onPressed != null ? Colors.white70 : Colors.white30,
            size: 18,
          ),
        ),
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF2D2D2D),
        border: Border(
          bottom: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
        ),
      ),
      child: Row(
        children: [
          _buildTab('add', '+ Agregar', Icons.add_box_outlined),
          _buildTab('edit', 'Editar', Icons.edit_outlined),
          _buildTab('theme', 'Tema', Icons.palette_outlined),
        ],
      ),
    );
  }

  Widget _buildTab(String id, String label, IconData icon) {
    final isActive = _activeTab == id;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _activeTab = id),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: isActive ? const Color(0xFF00A09D) : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 16,
                color: isActive ? const Color(0xFF00A09D) : Colors.white54,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: isActive ? Colors.white : Colors.white54,
                  fontSize: 13,
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTabContent(WebsiteEditModeProvider editProvider) {
    switch (_activeTab) {
      case 'add':
        return _AddBlocksTab(editProvider: editProvider);
      case 'edit':
        return _EditBlockTab(editProvider: editProvider);
      case 'theme':
        return _ThemeTab();
      default:
        return const SizedBox.shrink();
    }
  }
}

/// Tab for adding new blocks - shows available block types in a grid
class _AddBlocksTab extends StatelessWidget {
  final WebsiteEditModeProvider editProvider;

  const _AddBlocksTab({required this.editProvider});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSection('Estructura', [
            _BlockOption('hero', 'Hero', Icons.view_carousel_rounded),
            _BlockOption('carousel', 'Carrusel', Icons.view_array_rounded),
          ]),
          _buildSection('Contenido', [
            _BlockOption('products', 'Productos', Icons.shopping_bag_rounded),
            _BlockOption('about', 'Nosotros', Icons.info_rounded),
            _BlockOption('services', 'Servicios', Icons.build_rounded),
            _BlockOption('features', 'Beneficios', Icons.star_rounded),
          ]),
          _buildSection('Social', [
            _BlockOption('testimonials', 'Testimonios', Icons.format_quote_rounded),
            _BlockOption('team', 'Equipo', Icons.groups_rounded),
            _BlockOption('stats', 'Estadísticas', Icons.analytics_rounded),
          ]),
          _buildSection('Conversión', [
            _BlockOption('cta', 'Call to Action', Icons.touch_app_rounded),
            _BlockOption('pricing', 'Precios', Icons.payments_rounded),
            _BlockOption('contact', 'Contacto', Icons.contact_mail_rounded),
            _BlockOption('faq', 'FAQ', Icons.help_outline_rounded),
          ]),
          _buildSection('Media', [
            _BlockOption('gallery', 'Galería', Icons.photo_library_rounded),
          ]),
        ],
      ),
    );
  }

  Widget _buildSection(String title, List<_BlockOption> options) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12, top: 8),
          child: Text(
            title,
            style: const TextStyle(
              color: Colors.white54,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 1,
            ),
          ),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: options.map((opt) => _buildBlockCard(opt)).toList(),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildBlockCard(_BlockOption option) {
    return Builder(
      builder: (context) => Draggable<String>(
        data: option.type,
        feedback: Material(
          color: Colors.transparent,
          child: Container(
            width: 90,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF00A09D),
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(option.icon, color: Colors.white, size: 24),
                const SizedBox(height: 6),
                Text(
                  option.label,
                  style: const TextStyle(color: Colors.white, fontSize: 11),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
        childWhenDragging: Opacity(
          opacity: 0.4,
          child: _buildCardContent(option),
        ),
        onDragEnd: (details) {
          // Block will be added via drop target in main content area
        },
        child: GestureDetector(
          onTap: () {
            editProvider.addBlock(option.type);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Bloque "${option.label}" agregado'),
                duration: const Duration(seconds: 2),
                backgroundColor: const Color(0xFF00A09D),
              ),
            );
          },
          child: _buildCardContent(option),
        ),
      ),
    );
  }

  Widget _buildCardContent(_BlockOption option) {
    return Container(
      width: 90,
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF2D2D2D),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(option.icon, color: Colors.white70, size: 22),
          const SizedBox(height: 8),
          Text(
            option.label,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 11,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _BlockOption {
  final String type;
  final String label;
  final IconData icon;

  _BlockOption(this.type, this.label, this.icon);
}

/// Tab for editing selected block - shows controls based on block type
class _EditBlockTab extends StatelessWidget {
  final WebsiteEditModeProvider editProvider;

  const _EditBlockTab({required this.editProvider});

  @override
  Widget build(BuildContext context) {
    final selectedId = editProvider.selectedBlockId;
    
    if (selectedId == null) {
      return _buildNoSelection();
    }

    final block = editProvider.getBlock(selectedId);
    if (block == null) {
      return _buildNoSelection();
    }

    final blockType = block['block_type']?.toString() ?? '';
    final blockData = Map<String, dynamic>.from(block['block_data'] ?? {});
    final isVisible = block['is_visible'] ?? true;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildBlockHeader(blockType, isVisible, selectedId),
          const SizedBox(height: 20),
          _buildBlockControls(blockType, blockData, selectedId),
        ],
      ),
    );
  }

  Widget _buildNoSelection() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.touch_app_outlined,
              size: 48,
              color: Colors.white.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 16),
            Text(
              'Selecciona un bloque',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5),
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Haz clic en cualquier bloque de la página para editar sus propiedades',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.3),
                fontSize: 12,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBlockHeader(String blockType, bool isVisible, String blockId) {
    final typeNames = {
      'hero': 'Hero Banner',
      'carousel': 'Carrusel',
      'products': 'Productos',
      'about': 'Sobre Nosotros',
      'services': 'Servicios',
      'features': 'Características',
      'testimonials': 'Testimonios',
      'stats': 'Estadísticas',
      'team': 'Equipo',
      'faq': 'FAQ',
      'pricing': 'Precios',
      'contact': 'Contacto',
      'cta': 'Call to Action',
      'gallery': 'Galería',
    };

    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: const Color(0xFF00A09D).withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(
            _getBlockIcon(blockType),
            color: const Color(0xFF00A09D),
            size: 20,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                typeNames[blockType] ?? blockType,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                isVisible ? 'Visible' : 'Oculto',
                style: TextStyle(
                  color: isVisible ? const Color(0xFF00A09D) : Colors.orange,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
        // Quick actions
        _QuickActionButton(
          icon: isVisible ? Icons.visibility : Icons.visibility_off,
          tooltip: isVisible ? 'Ocultar' : 'Mostrar',
          onPressed: () => editProvider.toggleBlockVisibility(blockId),
        ),
        _QuickActionButton(
          icon: Icons.content_copy,
          tooltip: 'Duplicar',
          onPressed: () => editProvider.duplicateBlock(blockId),
        ),
        _QuickActionButton(
          icon: Icons.delete_outline,
          tooltip: 'Eliminar',
          onPressed: () => editProvider.deleteBlock(blockId),
          isDestructive: true,
        ),
      ],
    );
  }

  IconData _getBlockIcon(String type) {
    return switch (type) {
      'hero' => Icons.view_carousel_rounded,
      'carousel' => Icons.view_array_rounded,
      'products' => Icons.shopping_bag_rounded,
      'about' => Icons.info_rounded,
      'services' => Icons.build_rounded,
      'features' => Icons.star_rounded,
      'testimonials' => Icons.format_quote_rounded,
      'stats' => Icons.analytics_rounded,
      'team' => Icons.groups_rounded,
      'faq' => Icons.help_outline_rounded,
      'pricing' => Icons.payments_rounded,
      'contact' => Icons.contact_mail_rounded,
      'cta' => Icons.touch_app_rounded,
      'gallery' => Icons.photo_library_rounded,
      _ => Icons.widgets_rounded,
    };
  }

  Widget _buildBlockControls(String blockType, Map<String, dynamic> data, String blockId) {
    // Build controls based on block type
    switch (blockType) {
      case 'hero':
        return _HeroBlockControls(data: data, blockId: blockId, provider: editProvider);
      case 'products':
        return _ProductsBlockControls(data: data, blockId: blockId, provider: editProvider);
      case 'about':
        return _AboutBlockControls(data: data, blockId: blockId, provider: editProvider);
      case 'cta':
        return _CtaBlockControls(data: data, blockId: blockId, provider: editProvider);
      case 'features':
        return _FeaturesBlockControls(data: data, blockId: blockId, provider: editProvider);
      default:
        return _GenericBlockControls(data: data, blockId: blockId, provider: editProvider);
    }
  }
}

class _QuickActionButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final bool isDestructive;

  const _QuickActionButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.isDestructive = false,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          padding: const EdgeInsets.all(6),
          child: Icon(
            icon,
            color: isDestructive ? Colors.red.shade300 : Colors.white54,
            size: 18,
          ),
        ),
      ),
    );
  }
}

/// Hero block controls
class _HeroBlockControls extends StatelessWidget {
  final Map<String, dynamic> data;
  final String blockId;
  final WebsiteEditModeProvider provider;

  const _HeroBlockControls({
    required this.data,
    required this.blockId,
    required this.provider,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _EditorTextField(
          label: 'Título',
          value: data['title']?.toString() ?? '',
          onChanged: (v) => provider.updateBlockData(blockId, 'title', v),
        ),
        const SizedBox(height: 16),
        _EditorTextField(
          label: 'Subtítulo',
          value: data['subtitle']?.toString() ?? '',
          onChanged: (v) => provider.updateBlockData(blockId, 'subtitle', v),
          maxLines: 2,
        ),
        const SizedBox(height: 16),
        _EditorTextField(
          label: 'Texto del botón',
          value: data['buttonText']?.toString() ?? '',
          onChanged: (v) => provider.updateBlockData(blockId, 'buttonText', v),
        ),
        const SizedBox(height: 16),
        _EditorTextField(
          label: 'Enlace del botón',
          value: data['buttonLink']?.toString() ?? '',
          onChanged: (v) => provider.updateBlockData(blockId, 'buttonLink', v),
          hint: '/tienda/productos',
        ),
        const SizedBox(height: 20),
        _SectionHeader('Imagen de fondo'),
        const SizedBox(height: 12),
        _ImagePicker(
          currentUrl: data['backgroundImage']?.toString(),
          onChanged: (url) => provider.updateBlockData(blockId, 'backgroundImage', url),
        ),
      ],
    );
  }
}

/// Products block controls
class _ProductsBlockControls extends StatelessWidget {
  final Map<String, dynamic> data;
  final String blockId;
  final WebsiteEditModeProvider provider;

  const _ProductsBlockControls({
    required this.data,
    required this.blockId,
    required this.provider,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _EditorTextField(
          label: 'Título',
          value: data['title']?.toString() ?? '',
          onChanged: (v) => provider.updateBlockData(blockId, 'title', v),
        ),
        const SizedBox(height: 16),
        _EditorTextField(
          label: 'Subtítulo',
          value: data['subtitle']?.toString() ?? '',
          onChanged: (v) => provider.updateBlockData(blockId, 'subtitle', v),
        ),
        const SizedBox(height: 16),
        _EditorSlider(
          label: 'Máximo de productos',
          value: (data['maxProducts'] as num?)?.toDouble() ?? 8,
          min: 4,
          max: 16,
          divisions: 3,
          onChanged: (v) => provider.updateBlockData(blockId, 'maxProducts', v.toInt()),
        ),
        const SizedBox(height: 16),
        _EditorToggle(
          label: 'Mostrar precios',
          value: data['showPrice'] ?? true,
          onChanged: (v) => provider.updateBlockData(blockId, 'showPrice', v),
        ),
      ],
    );
  }
}

/// About block controls
class _AboutBlockControls extends StatelessWidget {
  final Map<String, dynamic> data;
  final String blockId;
  final WebsiteEditModeProvider provider;

  const _AboutBlockControls({
    required this.data,
    required this.blockId,
    required this.provider,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _EditorTextField(
          label: 'Título',
          value: data['title']?.toString() ?? '',
          onChanged: (v) => provider.updateBlockData(blockId, 'title', v),
        ),
        const SizedBox(height: 16),
        _EditorTextField(
          label: 'Descripción',
          value: data['description']?.toString() ?? '',
          onChanged: (v) => provider.updateBlockData(blockId, 'description', v),
          maxLines: 5,
        ),
        const SizedBox(height: 20),
        _SectionHeader('Imagen'),
        const SizedBox(height: 12),
        _ImagePicker(
          currentUrl: data['image']?.toString(),
          onChanged: (url) => provider.updateBlockData(blockId, 'image', url),
        ),
      ],
    );
  }
}

/// CTA block controls
class _CtaBlockControls extends StatelessWidget {
  final Map<String, dynamic> data;
  final String blockId;
  final WebsiteEditModeProvider provider;

  const _CtaBlockControls({
    required this.data,
    required this.blockId,
    required this.provider,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _EditorTextField(
          label: 'Título',
          value: data['title']?.toString() ?? '',
          onChanged: (v) => provider.updateBlockData(blockId, 'title', v),
        ),
        const SizedBox(height: 16),
        _EditorTextField(
          label: 'Descripción',
          value: data['description']?.toString() ?? '',
          onChanged: (v) => provider.updateBlockData(blockId, 'description', v),
          maxLines: 2,
        ),
        const SizedBox(height: 16),
        _EditorTextField(
          label: 'Texto del botón',
          value: data['buttonText']?.toString() ?? '',
          onChanged: (v) => provider.updateBlockData(blockId, 'buttonText', v),
        ),
        const SizedBox(height: 16),
        _EditorTextField(
          label: 'Enlace',
          value: data['buttonLink']?.toString() ?? '',
          onChanged: (v) => provider.updateBlockData(blockId, 'buttonLink', v),
        ),
      ],
    );
  }
}

/// Features block controls
class _FeaturesBlockControls extends StatelessWidget {
  final Map<String, dynamic> data;
  final String blockId;
  final WebsiteEditModeProvider provider;

  const _FeaturesBlockControls({
    required this.data,
    required this.blockId,
    required this.provider,
  });

  @override
  Widget build(BuildContext context) {
    final features = (data['features'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _EditorTextField(
          label: 'Título',
          value: data['title']?.toString() ?? '',
          onChanged: (v) => provider.updateBlockData(blockId, 'title', v),
        ),
        const SizedBox(height: 20),
        _SectionHeader('Características (${features.length})'),
        const SizedBox(height: 12),
        ...features.asMap().entries.map((entry) {
          final i = entry.key;
          final feature = entry.value;
          return _FeatureItem(
            index: i,
            feature: feature,
            onUpdate: (updated) {
              final newFeatures = List<Map<String, dynamic>>.from(features);
              newFeatures[i] = updated;
              provider.updateBlockData(blockId, 'features', newFeatures);
            },
            onDelete: () {
              final newFeatures = List<Map<String, dynamic>>.from(features);
              newFeatures.removeAt(i);
              provider.updateBlockData(blockId, 'features', newFeatures);
            },
          );
        }),
        const SizedBox(height: 12),
        _AddItemButton(
          label: 'Agregar característica',
          onPressed: () {
            final newFeatures = List<Map<String, dynamic>>.from(features);
            newFeatures.add({
              'icon': 'star',
              'title': 'Nueva característica',
              'description': 'Descripción...',
            });
            provider.updateBlockData(blockId, 'features', newFeatures);
          },
        ),
      ],
    );
  }
}

class _FeatureItem extends StatelessWidget {
  final int index;
  final Map<String, dynamic> feature;
  final Function(Map<String, dynamic>) onUpdate;
  final VoidCallback onDelete;

  const _FeatureItem({
    required this.index,
    required this.feature,
    required this.onUpdate,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF2D2D2D),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Text(
                '#${index + 1}',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 12),
              ),
              const Spacer(),
              InkWell(
                onTap: onDelete,
                child: Icon(Icons.close, size: 16, color: Colors.red.shade300),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _MiniTextField(
            value: feature['title']?.toString() ?? '',
            hint: 'Título',
            onChanged: (v) => onUpdate({...feature, 'title': v}),
          ),
          const SizedBox(height: 8),
          _MiniTextField(
            value: feature['description']?.toString() ?? '',
            hint: 'Descripción',
            onChanged: (v) => onUpdate({...feature, 'description': v}),
          ),
        ],
      ),
    );
  }
}

/// Generic block controls for types without specific UI
class _GenericBlockControls extends StatelessWidget {
  final Map<String, dynamic> data;
  final String blockId;
  final WebsiteEditModeProvider provider;

  const _GenericBlockControls({
    required this.data,
    required this.blockId,
    required this.provider,
  });

  @override
  Widget build(BuildContext context) {
    // Show title and subtitle if they exist
    final hasTitle = data.containsKey('title');
    final hasSubtitle = data.containsKey('subtitle');
    final hasDescription = data.containsKey('description');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (hasTitle) ...[
          _EditorTextField(
            label: 'Título',
            value: data['title']?.toString() ?? '',
            onChanged: (v) => provider.updateBlockData(blockId, 'title', v),
          ),
          const SizedBox(height: 16),
        ],
        if (hasSubtitle) ...[
          _EditorTextField(
            label: 'Subtítulo',
            value: data['subtitle']?.toString() ?? '',
            onChanged: (v) => provider.updateBlockData(blockId, 'subtitle', v),
          ),
          const SizedBox(height: 16),
        ],
        if (hasDescription) ...[
          _EditorTextField(
            label: 'Descripción',
            value: data['description']?.toString() ?? '',
            onChanged: (v) => provider.updateBlockData(blockId, 'description', v),
            maxLines: 3,
          ),
        ],
        if (!hasTitle && !hasSubtitle && !hasDescription)
          Center(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                'Edición avanzada disponible próximamente',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
              ),
            ),
          ),
      ],
    );
  }
}

/// Theme tab for global settings
class _ThemeTab extends StatefulWidget {
  @override
  State<_ThemeTab> createState() => _ThemeTabState();
}

class _ThemeTabState extends State<_ThemeTab> {
  final _storeNameController = TextEditingController();
  final _primaryColorController = TextEditingController();
  final _accentColorController = TextEditingController();
  final _logoUrlController = TextEditingController();
  final _topBannerController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _whatsappController = TextEditingController();
  
  bool _loaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_loaded) {
      _loadSettings();
      _loaded = true;
    }
  }

  void _loadSettings() {
    final service = context.read<WebsiteService>();
    _storeNameController.text = service.getSetting('store_name', '');
    _primaryColorController.text = service.getSetting('theme_primary_color', '#1B5E20');
    _accentColorController.text = service.getSetting('theme_accent_color', '#FF6D00');
    _logoUrlController.text = service.getSetting('logo_url', '');
    _topBannerController.text = service.getSetting('top_banner_text', 'Envíos a todo Chile');
    _emailController.text = service.getSetting('contact_email', '');
    _phoneController.text = service.getSetting('contact_phone', '');
    _whatsappController.text = service.getSetting('whatsapp', '');
  }

  Future<void> _saveSettings() async {
    final service = context.read<WebsiteService>();
    await service.saveSettings({
      'store_name': _storeNameController.text,
      'theme_primary_color': _primaryColorController.text,
      'theme_accent_color': _accentColorController.text,
      'logo_url': _logoUrlController.text,
      'top_banner_text': _topBannerController.text,
      'contact_email': _emailController.text,
      'contact_phone': _phoneController.text,
      'whatsapp': _whatsappController.text,
    });
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Configuración guardada'),
          backgroundColor: Color(0xFF00A09D),
        ),
      );
    }
  }

  @override
  void dispose() {
    _storeNameController.dispose();
    _primaryColorController.dispose();
    _accentColorController.dispose();
    _logoUrlController.dispose();
    _topBannerController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _whatsappController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader('Identidad'),
          const SizedBox(height: 12),
          _EditorTextField(
            label: 'Nombre de la tienda',
            value: _storeNameController.text,
            controller: _storeNameController,
            onChanged: (_) {},
          ),
          const SizedBox(height: 16),
          _EditorTextField(
            label: 'URL del logo',
            value: _logoUrlController.text,
            controller: _logoUrlController,
            onChanged: (_) {},
            hint: 'https://...',
          ),
          const SizedBox(height: 16),
          _EditorTextField(
            label: 'Texto del banner',
            value: _topBannerController.text,
            controller: _topBannerController,
            onChanged: (_) {},
          ),
          
          const SizedBox(height: 24),
          _SectionHeader('Colores'),
          const SizedBox(height: 12),
          _ColorField(
            label: 'Color primario',
            controller: _primaryColorController,
          ),
          const SizedBox(height: 12),
          _ColorField(
            label: 'Color de acento',
            controller: _accentColorController,
          ),
          
          const SizedBox(height: 24),
          _SectionHeader('Contacto'),
          const SizedBox(height: 12),
          _EditorTextField(
            label: 'Email',
            value: _emailController.text,
            controller: _emailController,
            onChanged: (_) {},
          ),
          const SizedBox(height: 16),
          _EditorTextField(
            label: 'Teléfono',
            value: _phoneController.text,
            controller: _phoneController,
            onChanged: (_) {},
          ),
          const SizedBox(height: 16),
          _EditorTextField(
            label: 'WhatsApp',
            value: _whatsappController.text,
            controller: _whatsappController,
            onChanged: (_) {},
            hint: '+56912345678',
          ),
          
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _saveSettings,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00A09D),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: const Text('Guardar configuración'),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================
// REUSABLE EDITOR COMPONENTS
// ============================================

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Text(
      title.toUpperCase(),
      style: TextStyle(
        color: Colors.white.withValues(alpha: 0.5),
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 1,
      ),
    );
  }
}

class _EditorTextField extends StatelessWidget {
  final String label;
  final String value;
  final Function(String) onChanged;
  final TextEditingController? controller;
  final int maxLines;
  final String? hint;

  const _EditorTextField({
    required this.label,
    required this.value,
    required this.onChanged,
    this.controller,
    this.maxLines = 1,
    this.hint,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          initialValue: controller == null ? value : null,
          maxLines: maxLines,
          style: const TextStyle(color: Colors.white, fontSize: 13),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.3)),
            filled: true,
            fillColor: const Color(0xFF2D2D2D),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: const BorderSide(color: Color(0xFF00A09D)),
            ),
          ),
          onChanged: onChanged,
        ),
      ],
    );
  }
}

class _MiniTextField extends StatelessWidget {
  final String value;
  final String hint;
  final Function(String) onChanged;

  const _MiniTextField({
    required this.value,
    required this.hint,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      initialValue: value,
      style: const TextStyle(color: Colors.white, fontSize: 12),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 12),
        filled: true,
        fillColor: const Color(0xFF1E1E1E),
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: BorderSide.none,
        ),
      ),
      onChanged: onChanged,
    );
  }
}

class _EditorToggle extends StatelessWidget {
  final String label;
  final bool value;
  final Function(bool) onChanged;

  const _EditorToggle({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 13),
        ),
        Switch(
          value: value,
          onChanged: onChanged,
          activeColor: const Color(0xFF00A09D),
        ),
      ],
    );
  }
}

class _EditorSlider extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final int? divisions;
  final Function(double) onChanged;

  const _EditorSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.divisions,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFF2D2D2D),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                value.toInt().toString(),
                style: const TextStyle(color: Color(0xFF00A09D), fontSize: 12),
              ),
            ),
          ],
        ),
        SliderTheme(
          data: SliderThemeData(
            activeTrackColor: const Color(0xFF00A09D),
            inactiveTrackColor: Colors.white.withValues(alpha: 0.1),
            thumbColor: const Color(0xFF00A09D),
            overlayColor: const Color(0xFF00A09D).withValues(alpha: 0.2),
          ),
          child: Slider(
            value: value,
            min: min,
            max: max,
            divisions: divisions,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}

class _ImagePicker extends StatelessWidget {
  final String? currentUrl;
  final Function(String) onChanged;

  const _ImagePicker({
    this.currentUrl,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final hasImage = currentUrl != null && currentUrl!.isNotEmpty;
    
    return Column(
      children: [
        Container(
          height: 120,
          width: double.infinity,
          decoration: BoxDecoration(
            color: const Color(0xFF2D2D2D),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
            image: hasImage
                ? DecorationImage(
                    image: NetworkImage(currentUrl!),
                    fit: BoxFit.cover,
                  )
                : null,
          ),
          child: hasImage
              ? null
              : Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.image_outlined, color: Colors.white.withValues(alpha: 0.3), size: 32),
                    const SizedBox(height: 8),
                    Text(
                      'Sin imagen',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 12),
                    ),
                  ],
                ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextFormField(
                initialValue: currentUrl ?? '',
                style: const TextStyle(color: Colors.white, fontSize: 11),
                decoration: InputDecoration(
                  hintText: 'URL de imagen',
                  hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 11),
                  filled: true,
                  fillColor: const Color(0xFF2D2D2D),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(4),
                    borderSide: BorderSide.none,
                  ),
                ),
                onChanged: onChanged,
              ),
            ),
            if (hasImage) ...[
              const SizedBox(width: 8),
              InkWell(
                onTap: () => onChanged(''),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.red.shade700,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Icon(Icons.close, color: Colors.white, size: 16),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

class _ColorField extends StatelessWidget {
  final String label;
  final TextEditingController controller;

  const _ColorField({
    required this.label,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: _parseColor(controller.text),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
              const SizedBox(height: 4),
              TextFormField(
                controller: controller,
                style: const TextStyle(color: Colors.white, fontSize: 12),
                decoration: InputDecoration(
                  hintText: '#RRGGBB',
                  hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 12),
                  filled: true,
                  fillColor: const Color(0xFF2D2D2D),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(4),
                    borderSide: BorderSide.none,
                  ),
                ),
                onChanged: (_) {
                  // Trigger rebuild to update color preview
                  (context as Element).markNeedsBuild();
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  Color _parseColor(String value) {
    try {
      String hex = value.replaceAll('#', '');
      if (hex.length == 6) {
        return Color(int.parse('FF$hex', radix: 16));
      }
    } catch (_) {}
    return Colors.grey;
  }
}

class _AddItemButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;

  const _AddItemButton({
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          border: Border.all(
            color: const Color(0xFF00A09D).withValues(alpha: 0.5),
            style: BorderStyle.solid,
          ),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.add, color: Color(0xFF00A09D), size: 18),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(color: Color(0xFF00A09D), fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}
