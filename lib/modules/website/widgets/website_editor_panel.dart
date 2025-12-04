import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../shared/constants/storage_constants.dart';
import '../providers/website_edit_mode_provider.dart';
import '../services/website_backup_service.dart';
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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
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
          // Backup button
          _buildIconButton(Icons.backup, 'Copias de seguridad', () => _showBackupsDialog(context)),
          // Preview button
          _buildIconButton(Icons.phone_android, 'Vista móvil', () {}),
          const Spacer(),
          // Discard button
          TextButton(
            onPressed: widget.onDiscard,
            style: TextButton.styleFrom(
              foregroundColor: Colors.white70,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text('Descartar', style: TextStyle(fontSize: 13)),
          ),
          const SizedBox(width: 6),
          // Save button
          ElevatedButton(
            onPressed: editProvider.hasUnsavedChanges ? widget.onSave : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00A09D),
              foregroundColor: Colors.white,
              disabledBackgroundColor: const Color(0xFF00A09D).withValues(alpha: 0.5),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
            ),
            child: const Text('Guardar', style: TextStyle(fontSize: 13)),
          ),
        ],
      ),
    );
  }

  void _showBackupsDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogContext) => _BackupsDialog(
        onRestoreComplete: () {
          // Signal that restore happened - caller should reload
          widget.onSave?.call(); // Re-use save callback to trigger reload
        },
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
            _BlockOption('categoryGrid', 'Categorías', Icons.grid_view_rounded),
          ]),
          _buildSection('Contenido', [
            _BlockOption('products', 'Productos', Icons.shopping_bag_rounded),
            _BlockOption('about', 'Nosotros', Icons.info_rounded),
            _BlockOption('services', 'Servicios', Icons.build_rounded),
            _BlockOption('features', 'Beneficios', Icons.star_rounded),
          ]),
          _buildSection('Media', [
            _BlockOption('gallery', 'Galería', Icons.photo_library_rounded),
            _BlockOption('videoBanner', 'Video Banner', Icons.play_circle_outline_rounded),
            _BlockOption('brandLogos', 'Logos Marcas', Icons.branding_watermark_rounded),
            _BlockOption('partnersBanner', 'Partners', Icons.handshake_rounded),
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
/// Also handles special elements: 'header' and 'footer'
class _EditBlockTab extends StatelessWidget {
  final WebsiteEditModeProvider editProvider;

  const _EditBlockTab({required this.editProvider});

  @override
  Widget build(BuildContext context) {
    final selectedId = editProvider.selectedBlockId;
    
    if (selectedId == null) {
      return _buildNoSelection();
    }

    // Handle special elements (header/footer) - these are not blocks
    if (selectedId == 'header') {
      return _HeaderBlockControls(provider: editProvider);
    }
    if (selectedId == 'footer') {
      return _FooterBlockControls(provider: editProvider);
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
      'categoryGrid' => Icons.grid_view_rounded,
      'videoBanner' => Icons.play_circle_outline_rounded,
      'partnersBanner' => Icons.handshake_rounded,
      'brandLogos' => Icons.branding_watermark_rounded,
      _ => Icons.widgets_rounded,
    };
  }

  Widget _buildBlockControls(String blockType, Map<String, dynamic> data, String blockId) {
    // Build controls based on block type
    switch (blockType) {
      case 'hero':
        return _HeroBlockControls(data: data, blockId: blockId, provider: editProvider);
      case 'carousel':
        return _CarouselBlockControls(data: data, blockId: blockId, provider: editProvider);
      case 'products':
        return _ProductsBlockControls(data: data, blockId: blockId, provider: editProvider);
      case 'about':
        return _AboutBlockControls(data: data, blockId: blockId, provider: editProvider);
      case 'cta':
        return _CtaBlockControls(data: data, blockId: blockId, provider: editProvider);
      case 'features':
        return _FeaturesBlockControls(data: data, blockId: blockId, provider: editProvider);
      case 'categoryGrid':
        return _CategoryGridBlockControls(data: data, blockId: blockId, provider: editProvider);
      case 'videoBanner':
        return _VideoBannerBlockControls(data: data, blockId: blockId, provider: editProvider);
      case 'partnersBanner':
        return _PartnersBannerBlockControls(data: data, blockId: blockId, provider: editProvider);
      case 'brandLogos':
        return _BrandLogosBlockControls(data: data, blockId: blockId, provider: editProvider);
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

/// Carousel block controls with slides management
class _CarouselBlockControls extends StatefulWidget {
  final Map<String, dynamic> data;
  final String blockId;
  final WebsiteEditModeProvider provider;

  const _CarouselBlockControls({
    required this.data,
    required this.blockId,
    required this.provider,
  });

  @override
  State<_CarouselBlockControls> createState() => _CarouselBlockControlsState();
}

class _CarouselBlockControlsState extends State<_CarouselBlockControls> {
  int _selectedSlideIndex = 0;

  List<Map<String, dynamic>> get _slides {
    final rawSlides = widget.data['slides'];
    if (rawSlides is List) {
      return rawSlides.map((s) => Map<String, dynamic>.from(s as Map)).toList();
    }
    return [];
  }

  void _updateSlides(List<Map<String, dynamic>> newSlides) {
    widget.provider.updateBlockData(widget.blockId, 'slides', newSlides);
  }

  void _updateSlide(int index, String key, dynamic value) {
    final slides = List<Map<String, dynamic>>.from(_slides);
    if (index >= 0 && index < slides.length) {
      slides[index] = {...slides[index], key: value};
      _updateSlides(slides);
    }
  }

  void _addSlide() {
    final slides = List<Map<String, dynamic>>.from(_slides);
    slides.add({
      'title': 'Nuevo Slide',
      'subtitle': 'Descripción del slide',
      'imageUrl': '',
      'ctaText': 'Ver más',
      'ctaLink': '/tienda/productos',
      'showOverlay': true,
      'overlayOpacity': 0.55,
    });
    _updateSlides(slides);
    setState(() => _selectedSlideIndex = slides.length - 1);
  }

  void _removeSlide(int index) {
    final slides = List<Map<String, dynamic>>.from(_slides);
    if (slides.length > 1 && index >= 0 && index < slides.length) {
      slides.removeAt(index);
      _updateSlides(slides);
      setState(() {
        if (_selectedSlideIndex >= slides.length) {
          _selectedSlideIndex = slides.length - 1;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final slides = _slides;
    final autoPlay = widget.data['autoPlay'] ?? true;
    final intervalSeconds = (widget.data['intervalSeconds'] as num?)?.toInt() ?? 5;
    final showIndicators = widget.data['showIndicators'] ?? true;
    final showArrows = widget.data['showArrows'] ?? true;
    final animation = widget.data['animation']?.toString() ?? 'slide';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Carousel Settings Section
        _SectionHeader('Configuración'),
        const SizedBox(height: 12),
        _EditorToggle(
          label: 'Reproducción automática',
          value: autoPlay,
          onChanged: (v) => widget.provider.updateBlockData(widget.blockId, 'autoPlay', v),
        ),
        const SizedBox(height: 12),
        if (autoPlay) ...[
          _EditorSlider(
            label: 'Intervalo (segundos)',
            value: intervalSeconds.toDouble(),
            min: 2,
            max: 15,
            divisions: 13,
            onChanged: (v) => widget.provider.updateBlockData(widget.blockId, 'intervalSeconds', v.toInt()),
          ),
          const SizedBox(height: 12),
        ],
        _EditorDropdown(
          label: 'Animación',
          value: animation,
          options: const [
            ('slide', 'Deslizar'),
            ('fade', 'Desvanecer'),
            ('zoom', 'Zoom'),
          ],
          onChanged: (v) => widget.provider.updateBlockData(widget.blockId, 'animation', v),
        ),
        const SizedBox(height: 12),
        _EditorToggle(
          label: 'Mostrar indicadores',
          value: showIndicators,
          onChanged: (v) => widget.provider.updateBlockData(widget.blockId, 'showIndicators', v),
        ),
        const SizedBox(height: 12),
        _EditorToggle(
          label: 'Mostrar flechas',
          value: showArrows,
          onChanged: (v) => widget.provider.updateBlockData(widget.blockId, 'showArrows', v),
        ),
        
        const SizedBox(height: 24),
        // Slides Section
        Row(
          children: [
            const Expanded(child: _SectionHeader('Slides')),
            InkWell(
              onTap: _addSlide,
              borderRadius: BorderRadius.circular(4),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF00A09D).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.add, size: 14, color: Color(0xFF00A09D)),
                    SizedBox(width: 4),
                    Text('Agregar', style: TextStyle(color: Color(0xFF00A09D), fontSize: 12)),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        
        // Slide tabs
        if (slides.isNotEmpty) ...[
          SizedBox(
            height: 40,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: slides.length,
              itemBuilder: (context, index) {
                final isSelected = index == _selectedSlideIndex;
                return GestureDetector(
                  onTap: () => setState(() => _selectedSlideIndex = index),
                  child: Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: isSelected ? const Color(0xFF00A09D) : Colors.white.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    alignment: Alignment.center,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Slide ${index + 1}',
                          style: TextStyle(
                            color: isSelected ? Colors.white : Colors.white70,
                            fontSize: 13,
                            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                          ),
                        ),
                        if (slides.length > 1) ...[
                          const SizedBox(width: 6),
                          InkWell(
                            onTap: () => _removeSlide(index),
                            child: Icon(
                              Icons.close,
                              size: 14,
                              color: isSelected ? Colors.white70 : Colors.white38,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 16),
          
          // Selected slide editor - key forces rebuild when switching slides
          if (_selectedSlideIndex < slides.length)
            _SlideEditor(
              key: ValueKey('slide_$_selectedSlideIndex'),
              slide: slides[_selectedSlideIndex],
              onUpdate: (key, value) => _updateSlide(_selectedSlideIndex, key, value),
            ),
        ] else
          Center(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Icon(Icons.image_outlined, size: 40, color: Colors.white.withValues(alpha: 0.3)),
                  const SizedBox(height: 12),
                  Text(
                    'No hay slides',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
                  ),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: _addSlide,
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Agregar slide'),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// Individual slide editor
class _SlideEditor extends StatelessWidget {
  final Map<String, dynamic> slide;
  final void Function(String key, dynamic value) onUpdate;

  const _SlideEditor({
    super.key,
    required this.slide,
    required this.onUpdate,
  });

  @override
  Widget build(BuildContext context) {
    final showOverlay = slide['showOverlay'] ?? true;
    final overlayOpacity = (slide['overlayOpacity'] as num?)?.toDouble() ?? 0.55;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _EditorTextField(
          label: 'Título',
          value: slide['title']?.toString() ?? '',
          onChanged: (v) => onUpdate('title', v),
        ),
        const SizedBox(height: 12),
        _EditorTextField(
          label: 'Subtítulo',
          value: slide['subtitle']?.toString() ?? '',
          onChanged: (v) => onUpdate('subtitle', v),
          maxLines: 2,
        ),
        const SizedBox(height: 16),
        _SectionHeader('Imagen de fondo'),
        const SizedBox(height: 8),
        _ImagePicker(
          currentUrl: slide['imageUrl']?.toString(),
          onChanged: (url) => onUpdate('imageUrl', url),
        ),
        const SizedBox(height: 16),
        _EditorToggle(
          label: 'Mostrar overlay oscuro',
          value: showOverlay,
          onChanged: (v) => onUpdate('showOverlay', v),
        ),
        if (showOverlay) ...[
          const SizedBox(height: 12),
          _EditorSlider(
            label: 'Opacidad del overlay',
            value: overlayOpacity,
            min: 0.1,
            max: 0.9,
            divisions: 8,
            onChanged: (v) => onUpdate('overlayOpacity', v),
          ),
        ],
        const SizedBox(height: 16),
        _SectionHeader('Botón'),
        const SizedBox(height: 8),
        _EditorTextField(
          label: 'Texto del botón',
          value: slide['ctaText']?.toString() ?? '',
          onChanged: (v) => onUpdate('ctaText', v),
        ),
        const SizedBox(height: 12),
        _EditorTextField(
          label: 'Enlace',
          value: slide['ctaLink']?.toString() ?? '',
          onChanged: (v) => onUpdate('ctaLink', v),
          hint: '/tienda/productos',
        ),
      ],
    );
  }
}

/// Products block controls - Enhanced with product selection, layout, and display options
class _ProductsBlockControls extends StatefulWidget {
  final Map<String, dynamic> data;
  final String blockId;
  final WebsiteEditModeProvider provider;

  const _ProductsBlockControls({
    required this.data,
    required this.blockId,
    required this.provider,
  });

  @override
  State<_ProductsBlockControls> createState() => _ProductsBlockControlsState();
}

class _ProductsBlockControlsState extends State<_ProductsBlockControls> {
  List<Map<String, dynamic>> _availableProducts = [];
  List<Map<String, dynamic>> _availableCategories = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final supabase = Supabase.instance.client;
      
      // Load products
      final productsResponse = await supabase
          .from('products')
          .select('id, name, sku, price, image_url, category_id, is_active, is_published')
          .eq('is_active', true)
          .order('name');
      
      // Load categories
      final categoriesResponse = await supabase
          .from('product_categories')
          .select('id, name')
          .order('name');
      
      if (mounted) {
        setState(() {
          _availableProducts = List<Map<String, dynamic>>.from(productsResponse);
          _availableCategories = List<Map<String, dynamic>>.from(categoriesResponse);
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading products: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _updateField(String field, dynamic value) {
    widget.provider.updateBlockData(widget.blockId, field, value);
  }

  List<String> get _selectedProductIds {
    final raw = widget.data['selectedProducts'];
    if (raw is List) return raw.cast<String>();
    return [];
  }

  String get _productSource => widget.data['productSource']?.toString() ?? 'featured';
  String? get _selectedCategoryId => widget.data['categoryId']?.toString();
  int get _itemsPerRow => (widget.data['itemsPerRow'] as num?)?.toInt() ?? 3;
  int get _maxProducts => (widget.data['maxProducts'] as num?)?.toInt() ?? 8;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _EditorTextField(
          label: 'Título de sección',
          value: widget.data['title']?.toString() ?? '',
          onChanged: (v) => _updateField('title', v),
        ),
        const SizedBox(height: 12),
        _EditorTextField(
          label: 'Subtítulo',
          value: widget.data['subtitle']?.toString() ?? '',
          onChanged: (v) => _updateField('subtitle', v),
        ),
        
        const SizedBox(height: 20),
        _SectionHeader('FUENTE DE PRODUCTOS'),
        const SizedBox(height: 12),
        
        // Product source selector
        _buildSourceSelector(),
        
        const SizedBox(height: 16),
        
        // Conditional content based on source
        if (_productSource == 'category') _buildCategorySelector(),
        if (_productSource == 'manual') _buildProductSelector(),
        
        const SizedBox(height: 20),
        _SectionHeader('DISEÑO'),
        const SizedBox(height: 12),
        
        // Items per row
        Text('Productos por fila', style: const TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Row(
          children: [2, 3, 4].map((count) {
            final isSelected = _itemsPerRow == count;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onTap: () => _updateField('itemsPerRow', count),
                child: Container(
                  width: 44,
                  height: 36,
                  decoration: BoxDecoration(
                    color: isSelected ? const Color(0xFF00A09D) : const Color(0xFF2D2D2D),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: isSelected ? const Color(0xFF00A09D) : Colors.white24,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      '$count',
                      style: TextStyle(
                        color: isSelected ? Colors.white : Colors.white70,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        
        const SizedBox(height: 16),
        _EditorSlider(
          label: 'Máximo de productos',
          value: _maxProducts.toDouble(),
          min: 4,
          max: 16,
          divisions: 6,
          onChanged: (v) => _updateField('maxProducts', v.toInt()),
        ),
        
        const SizedBox(height: 20),
        _SectionHeader('MOSTRAR'),
        const SizedBox(height: 12),
        
        _EditorToggle(
          label: 'Mostrar precios',
          value: widget.data['showPrice'] ?? true,
          onChanged: (v) => _updateField('showPrice', v),
        ),
        const SizedBox(height: 8),
        _EditorToggle(
          label: 'Mostrar botón "Ver todos"',
          value: widget.data['showViewAll'] ?? true,
          onChanged: (v) => _updateField('showViewAll', v),
        ),
        const SizedBox(height: 8),
        _EditorToggle(
          label: 'Mostrar SKU',
          value: widget.data['showSku'] ?? false,
          onChanged: (v) => _updateField('showSku', v),
        ),
        const SizedBox(height: 8),
        _EditorToggle(
          label: 'Mostrar marca',
          value: widget.data['showBrand'] ?? false,
          onChanged: (v) => _updateField('showBrand', v),
        ),
        
        // View all link
        if (widget.data['showViewAll'] != false) ...[
          const SizedBox(height: 16),
          _EditorTextField(
            label: 'Link "Ver todos"',
            value: widget.data['viewAllLink']?.toString() ?? '/tienda/productos',
            onChanged: (v) => _updateField('viewAllLink', v),
          ),
        ],
      ],
    );
  }

  Widget _buildSourceSelector() {
    final sources = [
      {'id': 'featured', 'label': 'Destacados', 'icon': Icons.star},
      {'id': 'category', 'label': 'Categoría', 'icon': Icons.category},
      {'id': 'manual', 'label': 'Selección manual', 'icon': Icons.checklist},
      {'id': 'newest', 'label': 'Más recientes', 'icon': Icons.schedule},
    ];
    
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: sources.map((source) {
        final isSelected = _productSource == source['id'];
        return GestureDetector(
          onTap: () => _updateField('productSource', source['id']),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: isSelected ? const Color(0xFF00A09D) : const Color(0xFF2D2D2D),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: isSelected ? const Color(0xFF00A09D) : Colors.white24,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  source['icon'] as IconData,
                  size: 14,
                  color: isSelected ? Colors.white : Colors.white54,
                ),
                const SizedBox(width: 6),
                Text(
                  source['label'] as String,
                  style: TextStyle(
                    color: isSelected ? Colors.white : Colors.white70,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildCategorySelector() {
    if (_isLoading) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        Text('Seleccionar categoría', style: const TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFF2D2D2D),
            borderRadius: BorderRadius.circular(4),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _selectedCategoryId,
              hint: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: Text('Seleccionar...', style: TextStyle(color: Colors.white54, fontSize: 13)),
              ),
              isExpanded: true,
              dropdownColor: const Color(0xFF2D2D2D),
              icon: const Icon(Icons.expand_more, color: Colors.white54),
              items: _availableCategories.map((cat) {
                return DropdownMenuItem<String>(
                  value: cat['id'].toString(),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text(
                      cat['name']?.toString() ?? 'Sin nombre',
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                    ),
                  ),
                );
              }).toList(),
              onChanged: (value) => _updateField('categoryId', value),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildProductSelector() {
    if (_isLoading) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        Row(
          children: [
            Text(
              'Productos seleccionados (${_selectedProductIds.length})',
              style: const TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.w600),
            ),
            const Spacer(),
            TextButton(
              onPressed: () => _showProductPicker(context),
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF00A09D),
                padding: EdgeInsets.zero,
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('Agregar', style: TextStyle(fontSize: 12)),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_selectedProductIds.isEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF2D2D2D),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: Colors.white12),
            ),
            child: const Center(
              child: Text(
                'No hay productos seleccionados\nToca "Agregar" para elegir productos',
                style: TextStyle(color: Colors.white38, fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ),
          )
        else
          ...(_selectedProductIds.map((productId) {
            final product = _availableProducts.firstWhere(
              (p) => p['id'].toString() == productId,
              orElse: () => <String, dynamic>{},
            );
            if (product.isEmpty) return const SizedBox.shrink();
            
            return Container(
              margin: const EdgeInsets.only(bottom: 4),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFF2D2D2D),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                children: [
                  // Product image
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: const Color(0xFF3D3D3D),
                      borderRadius: BorderRadius.circular(4),
                      image: product['image_url'] != null
                          ? DecorationImage(
                              image: NetworkImage(product['image_url']),
                              fit: BoxFit.cover,
                            )
                          : null,
                    ),
                    child: product['image_url'] == null
                        ? const Icon(Icons.image, size: 16, color: Colors.white24)
                        : null,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          product['name']?.toString() ?? '',
                          style: const TextStyle(color: Colors.white, fontSize: 12),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          product['sku']?.toString() ?? '',
                          style: const TextStyle(color: Colors.white38, fontSize: 10),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 16),
                    color: Colors.white38,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () {
                      final newList = List<String>.from(_selectedProductIds)..remove(productId);
                      _updateField('selectedProducts', newList);
                    },
                  ),
                ],
              ),
            );
          })),
      ],
    );
  }

  void _showProductPicker(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => _ProductPickerDialog(
        availableProducts: _availableProducts,
        selectedIds: _selectedProductIds,
        onConfirm: (selectedIds) {
          _updateField('selectedProducts', selectedIds);
        },
      ),
    );
  }
}

/// Product picker dialog
class _ProductPickerDialog extends StatefulWidget {
  final List<Map<String, dynamic>> availableProducts;
  final List<String> selectedIds;
  final Function(List<String>) onConfirm;

  const _ProductPickerDialog({
    required this.availableProducts,
    required this.selectedIds,
    required this.onConfirm,
  });

  @override
  State<_ProductPickerDialog> createState() => _ProductPickerDialogState();
}

class _ProductPickerDialogState extends State<_ProductPickerDialog> {
  late Set<String> _selected;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _selected = Set<String>.from(widget.selectedIds);
  }

  List<Map<String, dynamic>> get _filteredProducts {
    if (_searchQuery.isEmpty) return widget.availableProducts;
    final query = _searchQuery.toLowerCase();
    return widget.availableProducts.where((p) {
      final name = (p['name']?.toString() ?? '').toLowerCase();
      final sku = (p['sku']?.toString() ?? '').toLowerCase();
      return name.contains(query) || sku.contains(query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF1E1E1E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Container(
        width: 400,
        height: 500,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text(
                  'Seleccionar productos',
                  style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white54),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Search field
            TextField(
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Buscar por nombre o SKU...',
                hintStyle: const TextStyle(color: Colors.white38, fontSize: 13),
                prefixIcon: const Icon(Icons.search, color: Colors.white38, size: 20),
                filled: true,
                fillColor: const Color(0xFF2D2D2D),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide: BorderSide.none,
                ),
              ),
              onChanged: (v) => setState(() => _searchQuery = v),
            ),
            const SizedBox(height: 12),
            Text(
              '${_selected.length} productos seleccionados',
              style: const TextStyle(color: Colors.white54, fontSize: 11),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                itemCount: _filteredProducts.length,
                itemBuilder: (context, index) {
                  final product = _filteredProducts[index];
                  final productId = product['id'].toString();
                  final isSelected = _selected.contains(productId);
                  
                  return InkWell(
                    onTap: () {
                      setState(() {
                        if (isSelected) {
                          _selected.remove(productId);
                        } else {
                          _selected.add(productId);
                        }
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                      decoration: BoxDecoration(
                        color: isSelected ? const Color(0xFF00A09D).withValues(alpha: 0.2) : Colors.transparent,
                        border: Border(
                          bottom: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
                        ),
                      ),
                      child: Row(
                        children: [
                          // Checkbox
                          Container(
                            width: 20,
                            height: 20,
                            decoration: BoxDecoration(
                              color: isSelected ? const Color(0xFF00A09D) : const Color(0xFF2D2D2D),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: isSelected ? const Color(0xFF00A09D) : Colors.white24,
                              ),
                            ),
                            child: isSelected
                                ? const Icon(Icons.check, size: 14, color: Colors.white)
                                : null,
                          ),
                          const SizedBox(width: 12),
                          // Image
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: const Color(0xFF3D3D3D),
                              borderRadius: BorderRadius.circular(4),
                              image: product['image_url'] != null
                                  ? DecorationImage(
                                      image: NetworkImage(product['image_url']),
                                      fit: BoxFit.cover,
                                    )
                                  : null,
                            ),
                            child: product['image_url'] == null
                                ? const Icon(Icons.image, size: 20, color: Colors.white24)
                                : null,
                          ),
                          const SizedBox(width: 12),
                          // Details
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  product['name']?.toString() ?? '',
                                  style: const TextStyle(color: Colors.white, fontSize: 13),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  'SKU: ${product['sku'] ?? '-'} · \$${NumberFormat('#,###', 'es_CL').format(product['price'] ?? 0)}',
                                  style: const TextStyle(color: Colors.white38, fontSize: 11),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  style: TextButton.styleFrom(foregroundColor: Colors.white54),
                  child: const Text('Cancelar'),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () {
                    widget.onConfirm(_selected.toList());
                    Navigator.pop(context);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00A09D),
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Confirmar'),
                ),
              ],
            ),
          ],
        ),
      ),
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

/// Theme tab for global site-wide settings (colors, typography, button styles)
/// Header and Footer are edited via the "Editar" tab when selected
class _ThemeTab extends StatefulWidget {
  @override
  State<_ThemeTab> createState() => _ThemeTabState();
}

class _ThemeTabState extends State<_ThemeTab> {
  // Colors
  final _primaryColorController = TextEditingController();
  final _accentColorController = TextEditingController();
  
  // Typography
  String _headingFont = 'Inter';
  String _bodyFont = 'Inter';
  String _headingSize = 'normal';
  String _bodySize = 'normal';
  
  // Button styles
  String _buttonStyle = 'rounded';
  String _buttonSize = 'medium';
  
  // Background
  String _pageBackground = 'white';
  
  bool _loaded = false;

  final _fonts = ['Inter', 'Roboto', 'Open Sans', 'Montserrat', 'Poppins', 'Lato', 'Oswald', 'Playfair Display'];
  final _sizes = {'small': 'Pequeño', 'normal': 'Normal', 'large': 'Grande'};
  final _buttonStyles = {'rounded': 'Redondeado', 'square': 'Cuadrado', 'pill': 'Pill'};
  final _buttonSizes = {'small': 'Pequeño', 'medium': 'Mediano', 'large': 'Grande'};
  final _backgrounds = {'white': 'Blanco', 'light': 'Gris claro', 'dark': 'Oscuro'};

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
    _primaryColorController.text = service.getSetting('theme_primary_color', '#1B5E20');
    _accentColorController.text = service.getSetting('theme_accent_color', '#FF6D00');
    _headingFont = service.getSetting('heading_font', 'Inter');
    _bodyFont = service.getSetting('body_font', 'Inter');
    _headingSize = service.getSetting('heading_size', 'normal');
    _bodySize = service.getSetting('body_size', 'normal');
    _buttonStyle = service.getSetting('button_style', 'rounded');
    _buttonSize = service.getSetting('button_size', 'medium');
    _pageBackground = service.getSetting('page_background', 'white');
  }

  Future<void> _saveSettings() async {
    final service = context.read<WebsiteService>();
    await service.saveSettings({
      'theme_primary_color': _primaryColorController.text,
      'theme_accent_color': _accentColorController.text,
      'heading_font': _headingFont,
      'body_font': _bodyFont,
      'heading_size': _headingSize,
      'body_size': _bodySize,
      'button_style': _buttonStyle,
      'button_size': _buttonSize,
      'page_background': _pageBackground,
    });
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Tema guardado'),
          backgroundColor: Color(0xFF00A09D),
        ),
      );
    }
  }

  @override
  void dispose() {
    _primaryColorController.dispose();
    _accentColorController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Info banner
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, color: Colors.blue.shade300, size: 20),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Para editar el header o footer, haz clic directamente sobre ellos en la página.',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 24),
          
          // ========== COLORS SECTION ==========
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
          
          // ========== TYPOGRAPHY SECTION ==========
          _SectionHeader('Tipografía'),
          const SizedBox(height: 12),
          
          _buildDropdown(
            label: 'Fuente de títulos',
            value: _headingFont,
            items: _fonts,
            onChanged: (v) => setState(() => _headingFont = v!),
          ),
          const SizedBox(height: 12),
          
          _buildDropdown(
            label: 'Tamaño de títulos',
            value: _headingSize,
            items: _sizes.keys.toList(),
            labels: _sizes,
            onChanged: (v) => setState(() => _headingSize = v!),
          ),
          const SizedBox(height: 16),
          
          _buildDropdown(
            label: 'Fuente de texto',
            value: _bodyFont,
            items: _fonts,
            onChanged: (v) => setState(() => _bodyFont = v!),
          ),
          const SizedBox(height: 12),
          
          _buildDropdown(
            label: 'Tamaño de texto',
            value: _bodySize,
            items: _sizes.keys.toList(),
            labels: _sizes,
            onChanged: (v) => setState(() => _bodySize = v!),
          ),
          
          const SizedBox(height: 24),
          
          // ========== BUTTON STYLES SECTION ==========
          _SectionHeader('Estilo de botones'),
          const SizedBox(height: 12),
          
          _buildDropdown(
            label: 'Forma',
            value: _buttonStyle,
            items: _buttonStyles.keys.toList(),
            labels: _buttonStyles,
            onChanged: (v) => setState(() => _buttonStyle = v!),
          ),
          const SizedBox(height: 12),
          
          _buildDropdown(
            label: 'Tamaño',
            value: _buttonSize,
            items: _buttonSizes.keys.toList(),
            labels: _buttonSizes,
            onChanged: (v) => setState(() => _buttonSize = v!),
          ),
          
          const SizedBox(height: 24),
          
          // ========== BACKGROUND SECTION ==========
          _SectionHeader('Fondo de página'),
          const SizedBox(height: 12),
          
          _buildDropdown(
            label: 'Color de fondo',
            value: _pageBackground,
            items: _backgrounds.keys.toList(),
            labels: _backgrounds,
            onChanged: (v) => setState(() => _pageBackground = v!),
          ),
          
          const SizedBox(height: 32),
          
          // Save button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _saveSettings,
              icon: const Icon(Icons.save, size: 18),
              label: const Text('Guardar tema'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00A09D),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildDropdown({
    required String label,
    required String value,
    required List<String> items,
    Map<String, String>? labels,
    required void Function(String?) onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
        const SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFF2D2D2D),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: value,
              isExpanded: true,
              dropdownColor: const Color(0xFF2D2D2D),
              style: const TextStyle(color: Colors.white, fontSize: 14),
              items: items.map((item) {
                return DropdownMenuItem(
                  value: item,
                  child: Text(labels?[item] ?? item),
                );
              }).toList(),
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }
}

/// Logo uploader widget with image preview
class _LogoUploader extends StatefulWidget {
  final String? currentUrl;
  final Function(String) onChanged;

  const _LogoUploader({
    this.currentUrl,
    required this.onChanged,
  });

  @override
  State<_LogoUploader> createState() => _LogoUploaderState();
}

class _LogoUploaderState extends State<_LogoUploader> {
  bool _isUploading = false;

  Future<void> _pickAndUploadLogo() async {
    try {
      final picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 500,
        maxHeight: 200,
        imageQuality: 90,
      );

      if (image == null) return;

      setState(() => _isUploading = true);

      final bytes = await image.readAsBytes();
      final fileName = 'logo_${DateTime.now().millisecondsSinceEpoch}_${image.name}';
      final filePath = 'website-images/$fileName';

      final supabase = Supabase.instance.client;
      
      await supabase.storage.from(StorageConfig.defaultBucket).uploadBinary(
        filePath,
        bytes,
        fileOptions: FileOptions(
          contentType: _getContentType(image.name),
          upsert: true,
        ),
      );

      final publicUrl = supabase.storage.from(StorageConfig.defaultBucket).getPublicUrl(filePath);

      setState(() => _isUploading = false);
      widget.onChanged(publicUrl);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Logo actualizado'),
            backgroundColor: Color(0xFF00A09D),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      setState(() => _isUploading = false);
      debugPrint('Error uploading logo: $e');
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

  String _getContentType(String fileName) {
    final ext = fileName.split('.').last.toLowerCase();
    switch (ext) {
      case 'png': return 'image/png';
      case 'jpg':
      case 'jpeg': return 'image/jpeg';
      case 'webp': return 'image/webp';
      case 'svg': return 'image/svg+xml';
      default: return 'image/png';
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasLogo = widget.currentUrl != null && widget.currentUrl!.isNotEmpty;
    
    return InkWell(
      onTap: _isUploading ? null : _pickAndUploadLogo,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        height: 80,
        width: double.infinity,
        decoration: BoxDecoration(
          color: const Color(0xFF2D2D2D),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: _isUploading 
                ? const Color(0xFF00A09D) 
                : Colors.white.withValues(alpha: 0.1),
          ),
        ),
        child: _isUploading
            ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
            : hasLogo
                ? Row(
                    children: [
                      const SizedBox(width: 16),
                      Container(
                        height: 50,
                        constraints: const BoxConstraints(maxWidth: 150),
                        child: Image.network(
                          widget.currentUrl!,
                          fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) => const Icon(
                            Icons.broken_image,
                            color: Colors.white38,
                          ),
                        ),
                      ),
                      const Spacer(),
                      Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.edit, color: Colors.white38, size: 18),
                            const SizedBox(height: 4),
                            Text(
                              'Cambiar',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.5),
                                fontSize: 10,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  )
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.add_photo_alternate, color: Colors.white38, size: 28),
                      const SizedBox(height: 6),
                      Text(
                        'Subir logo',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.5),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
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

class _EditorDropdown extends StatelessWidget {
  final String label;
  final String value;
  final List<(String, String)> options; // (value, label)
  final Function(String) onChanged;

  const _EditorDropdown({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF2D2D2D),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: value,
              isExpanded: true,
              dropdownColor: const Color(0xFF2D2D2D),
              style: const TextStyle(color: Colors.white, fontSize: 13),
              icon: const Icon(Icons.expand_more, color: Colors.white54, size: 18),
              items: options.map((opt) => DropdownMenuItem(
                value: opt.$1,
                child: Text(opt.$2),
              )).toList(),
              onChanged: (v) => onChanged(v ?? value),
            ),
          ),
        ),
      ],
    );
  }
}

class _ImagePicker extends StatefulWidget {
  final String? currentUrl;
  final Function(String) onChanged;

  const _ImagePicker({
    this.currentUrl,
    required this.onChanged,
  });

  @override
  State<_ImagePicker> createState() => _ImagePickerState();
}

class _ImagePickerState extends State<_ImagePicker> {
  bool _isUploading = false;
  double _uploadProgress = 0;

  Future<void> _pickAndUploadImage() async {
    try {
      final picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1920,
        maxHeight: 1080,
        imageQuality: 85,
      );

      if (image == null) return;

      setState(() {
        _isUploading = true;
        _uploadProgress = 0;
      });

      // Read file bytes
      final bytes = await image.readAsBytes();
      final fileName = 'website_${DateTime.now().millisecondsSinceEpoch}_${image.name}';
      final filePath = 'website-images/$fileName';

      // Upload to Supabase Storage
      final supabase = Supabase.instance.client;
      
      // Use the standard vinabike-assets bucket
      await supabase.storage.from(StorageConfig.defaultBucket).uploadBinary(
        filePath,
        bytes,
        fileOptions: FileOptions(
          contentType: _getContentType(image.name),
          upsert: true,
        ),
      );

      setState(() => _uploadProgress = 0.8);

      // Get public URL
      final publicUrl = supabase.storage.from(StorageConfig.defaultBucket).getPublicUrl(filePath);

      setState(() {
        _isUploading = false;
        _uploadProgress = 1;
      });

      widget.onChanged(publicUrl);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Imagen subida correctamente'),
            backgroundColor: Color(0xFF00A09D),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      setState(() => _isUploading = false);
      debugPrint('Error uploading image: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al subir imagen: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  String _getContentType(String fileName) {
    final ext = fileName.split('.').last.toLowerCase();
    switch (ext) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'gif':
        return 'image/gif';
      case 'webp':
        return 'image/webp';
      default:
        return 'image/jpeg';
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasImage = widget.currentUrl != null && widget.currentUrl!.isNotEmpty;
    
    return Column(
      children: [
        // Image preview / upload area
        InkWell(
          onTap: _isUploading ? null : _pickAndUploadImage,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            height: 140,
            width: double.infinity,
            decoration: BoxDecoration(
              color: const Color(0xFF2D2D2D),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: _isUploading 
                    ? const Color(0xFF00A09D) 
                    : Colors.white.withValues(alpha: 0.1),
                width: _isUploading ? 2 : 1,
              ),
              image: hasImage && !_isUploading
                  ? DecorationImage(
                      image: NetworkImage(widget.currentUrl!),
                      fit: BoxFit.cover,
                    )
                  : null,
            ),
            child: _isUploading
                ? Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(
                        width: 32,
                        height: 32,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF00A09D)),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Subiendo imagen...',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.7),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  )
                : hasImage
                    ? Stack(
                        children: [
                          Positioned(
                            top: 8,
                            right: 8,
                            child: Row(
                              children: [
                                _buildActionButton(
                                  icon: Icons.edit,
                                  tooltip: 'Cambiar imagen',
                                  onTap: _pickAndUploadImage,
                                ),
                                const SizedBox(width: 4),
                                _buildActionButton(
                                  icon: Icons.delete,
                                  tooltip: 'Eliminar',
                                  onTap: () => widget.onChanged(''),
                                  isDestructive: true,
                                ),
                              ],
                            ),
                          ),
                        ],
                      )
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFF00A09D).withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(50),
                            ),
                            child: const Icon(
                              Icons.cloud_upload_outlined,
                              color: Color(0xFF00A09D),
                              size: 28,
                            ),
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'Haz clic para subir imagen',
                            style: TextStyle(
                              color: Color(0xFF00A09D),
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'JPG, PNG, WebP • Máx 1920x1080',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.4),
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
          ),
        ),
      ],
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
    bool isDestructive = false,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: isDestructive 
                ? Colors.red.shade700.withValues(alpha: 0.9)
                : Colors.black.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Icon(icon, color: Colors.white, size: 16),
        ),
      ),
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

// ============================================================================
// CATEGORY GRID BLOCK CONTROLS
// ============================================================================
class _CategoryGridBlockControls extends StatefulWidget {
  final Map<String, dynamic> data;
  final String blockId;
  final WebsiteEditModeProvider provider;

  const _CategoryGridBlockControls({
    required this.data,
    required this.blockId,
    required this.provider,
  });

  @override
  State<_CategoryGridBlockControls> createState() => _CategoryGridBlockControlsState();
}

class _CategoryGridBlockControlsState extends State<_CategoryGridBlockControls> {
  int _selectedCategoryIndex = 0;

  List<Map<String, dynamic>> get _categories {
    final raw = widget.data['categories'];
    if (raw is List) {
      return raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    }
    return [];
  }

  void _updateField(String field, dynamic value) {
    widget.provider.updateBlockData(widget.blockId, field, value);
  }

  void _updateCategory(int index, String field, dynamic value) {
    final categories = List<Map<String, dynamic>>.from(_categories);
    if (index < categories.length) {
      categories[index] = Map<String, dynamic>.from(categories[index]);
      categories[index][field] = value;
      _updateField('categories', categories);
    }
  }

  void _addCategory() {
    final categories = List<Map<String, dynamic>>.from(_categories);
    categories.add({
      'title': 'Nueva Categoría',
      'subtitle': 'Descripción breve',
      'imageUrl': '',
      'ctaText': 'Ver más',
      'ctaLink': '/tienda/productos',
      'size': categories.length < 2 ? 'large' : 'medium',
    });
    _updateField('categories', categories);
    setState(() => _selectedCategoryIndex = categories.length - 1);
  }

  void _removeCategory(int index) {
    final categories = List<Map<String, dynamic>>.from(_categories);
    if (categories.length > 1) {
      categories.removeAt(index);
      _updateField('categories', categories);
      setState(() {
        if (_selectedCategoryIndex >= categories.length) {
          _selectedCategoryIndex = categories.length - 1;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _EditorTextField(
          label: 'Título de sección',
          value: widget.data['title']?.toString() ?? '',
          onChanged: (v) => _updateField('title', v),
        ),
        const SizedBox(height: 12),
        _EditorTextField(
          label: 'Subtítulo',
          value: widget.data['subtitle']?.toString() ?? '',
          onChanged: (v) => _updateField('subtitle', v),
        ),
        const SizedBox(height: 20),
        Text('Categorías', style: const TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 1)),
        const SizedBox(height: 8),
        // Category selector chips
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              ..._categories.asMap().entries.map((entry) {
                final index = entry.key;
                final cat = entry.value;
                final isSelected = index == _selectedCategoryIndex;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GestureDetector(
                    onTap: () => setState(() => _selectedCategoryIndex = index),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: isSelected ? const Color(0xFF00A09D) : const Color(0xFF2D2D2D),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isSelected ? const Color(0xFF00A09D) : Colors.white24,
                        ),
                      ),
                      child: Text(
                        cat['title']?.toString() ?? 'Cat ${index + 1}',
                        style: TextStyle(
                          color: isSelected ? Colors.white : Colors.white70,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                );
              }),
              GestureDetector(
                onTap: _addCategory,
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2D2D2D),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: const Icon(Icons.add, color: Color(0xFF00A09D), size: 16),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // Selected category editor
        if (_categories.isNotEmpty && _selectedCategoryIndex < _categories.length) ...[
          // Image picker for this category
          _SectionHeader('Imagen de categoría'),
          const SizedBox(height: 8),
          _ImagePicker(
            currentUrl: _categories[_selectedCategoryIndex]['imageUrl']?.toString(),
            onChanged: (url) => _updateCategory(_selectedCategoryIndex, 'imageUrl', url),
          ),
          const SizedBox(height: 16),
          _EditorTextField(
            label: 'Título categoría',
            value: _categories[_selectedCategoryIndex]['title']?.toString() ?? '',
            onChanged: (v) => _updateCategory(_selectedCategoryIndex, 'title', v),
          ),
          const SizedBox(height: 12),
          _EditorTextField(
            label: 'Subtítulo',
            value: _categories[_selectedCategoryIndex]['subtitle']?.toString() ?? '',
            onChanged: (v) => _updateCategory(_selectedCategoryIndex, 'subtitle', v),
          ),
          const SizedBox(height: 12),
          _EditorTextField(
            label: 'Texto botón',
            value: _categories[_selectedCategoryIndex]['ctaText']?.toString() ?? '',
            onChanged: (v) => _updateCategory(_selectedCategoryIndex, 'ctaText', v),
          ),
          const SizedBox(height: 12),
          _EditorTextField(
            label: 'Link botón',
            value: _categories[_selectedCategoryIndex]['ctaLink']?.toString() ?? '',
            onChanged: (v) => _updateCategory(_selectedCategoryIndex, 'ctaLink', v),
          ),
          const SizedBox(height: 12),
          // Size selector
          Text('Tamaño', style: const TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 1)),
          const SizedBox(height: 8),
          Row(
            children: ['large', 'medium'].map((size) {
              final isSelected = _categories[_selectedCategoryIndex]['size'] == size;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: GestureDetector(
                  onTap: () => _updateCategory(_selectedCategoryIndex, 'size', size),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: isSelected ? const Color(0xFF00A09D) : const Color(0xFF2D2D2D),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      size == 'large' ? 'Grande' : 'Mediano',
                      style: TextStyle(
                        color: isSelected ? Colors.white : Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
          // Delete category button
          if (_categories.length > 1)
            TextButton.icon(
              onPressed: () => _removeCategory(_selectedCategoryIndex),
              icon: const Icon(Icons.delete_outline, size: 16),
              label: const Text('Eliminar categoría'),
              style: TextButton.styleFrom(foregroundColor: Colors.red.shade300),
            ),
        ],
      ],
    );
  }
}

// ============================================================================
// VIDEO BANNER BLOCK CONTROLS
// ============================================================================
class _VideoBannerBlockControls extends StatelessWidget {
  final Map<String, dynamic> data;
  final String blockId;
  final WebsiteEditModeProvider provider;

  const _VideoBannerBlockControls({
    required this.data,
    required this.blockId,
    required this.provider,
  });

  void _updateField(String field, dynamic value) {
    provider.updateBlockData(blockId, field, value);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _EditorTextField(
          label: 'Título',
          value: data['title']?.toString() ?? '',
          onChanged: (v) => _updateField('title', v),
        ),
        const SizedBox(height: 12),
        _EditorTextField(
          label: 'Subtítulo',
          value: data['subtitle']?.toString() ?? '',
          onChanged: (v) => _updateField('subtitle', v),
          maxLines: 2,
        ),
        const SizedBox(height: 12),
        _EditorTextField(
          label: 'URL Imagen de fondo',
          value: data['imageUrl']?.toString() ?? '',
          onChanged: (v) => _updateField('imageUrl', v),
        ),
        const SizedBox(height: 12),
        _EditorTextField(
          label: 'URL Video (opcional)',
          value: data['videoUrl']?.toString() ?? '',
          onChanged: (v) => _updateField('videoUrl', v),
        ),
        const SizedBox(height: 16),
        // Show CTA toggle
        Row(
          children: [
            const Text('Mostrar botón', style: TextStyle(color: Colors.white70, fontSize: 13)),
            const Spacer(),
            Switch(
              value: data['showCta'] != false,
              onChanged: (v) => _updateField('showCta', v),
              activeColor: const Color(0xFF00A09D),
            ),
          ],
        ),
        if (data['showCta'] != false) ...[
          const SizedBox(height: 12),
          _EditorTextField(
            label: 'Texto botón',
            value: data['ctaText']?.toString() ?? '',
            onChanged: (v) => _updateField('ctaText', v),
          ),
          const SizedBox(height: 12),
          _EditorTextField(
            label: 'Link botón',
            value: data['ctaLink']?.toString() ?? '',
            onChanged: (v) => _updateField('ctaLink', v),
          ),
        ],
        const SizedBox(height: 16),
        Text('Opacidad overlay', style: const TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 1)),
        Slider(
          value: (data['overlayOpacity'] as num?)?.toDouble() ?? 0.5,
          min: 0,
          max: 1,
          divisions: 10,
          activeColor: const Color(0xFF00A09D),
          onChanged: (v) => _updateField('overlayOpacity', v),
        ),
      ],
    );
  }
}

// ============================================================================
// PARTNERS BANNER BLOCK CONTROLS
// ============================================================================
class _PartnersBannerBlockControls extends StatefulWidget {
  final Map<String, dynamic> data;
  final String blockId;
  final WebsiteEditModeProvider provider;

  const _PartnersBannerBlockControls({
    required this.data,
    required this.blockId,
    required this.provider,
  });

  @override
  State<_PartnersBannerBlockControls> createState() => _PartnersBannerBlockControlsState();
}

class _PartnersBannerBlockControlsState extends State<_PartnersBannerBlockControls> {
  List<String> get _items {
    final raw = widget.data['items'];
    if (raw is List) {
      return raw.map((e) => e.toString()).toList();
    }
    return [];
  }

  void _updateField(String field, dynamic value) {
    widget.provider.updateBlockData(widget.blockId, field, value);
  }

  void _updateItem(int index, String value) {
    final items = List<String>.from(_items);
    if (index < items.length) {
      items[index] = value;
      _updateField('items', items);
    }
  }

  void _addItem() {
    final items = List<String>.from(_items);
    items.add('Nuevo elemento');
    _updateField('items', items);
  }

  void _removeItem(int index) {
    final items = List<String>.from(_items);
    if (items.length > 1) {
      items.removeAt(index);
      _updateField('items', items);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _EditorTextField(
          label: 'Título superior',
          value: widget.data['title']?.toString() ?? '',
          onChanged: (v) => _updateField('title', v),
        ),
        const SizedBox(height: 12),
        _EditorTextField(
          label: 'URL Imagen de fondo',
          value: widget.data['imageUrl']?.toString() ?? '',
          onChanged: (v) => _updateField('imageUrl', v),
        ),
        const SizedBox(height: 20),
        Text('Elementos de lista', style: const TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 1)),
        const SizedBox(height: 8),
        ..._items.asMap().entries.map((entry) {
          final index = entry.key;
          final item = entry.value;
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Expanded(
                  child: _EditorTextField(
                    label: 'Elemento ${index + 1}',
                    value: item,
                    onChanged: (v) => _updateItem(index, v),
                  ),
                ),
                if (_items.length > 1)
                  IconButton(
                    icon: Icon(Icons.remove_circle_outline, color: Colors.red.shade300, size: 20),
                    onPressed: () => _removeItem(index),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
              ],
            ),
          );
        }),
        const SizedBox(height: 8),
        _AddItemButton(
          label: 'Agregar elemento',
          onPressed: _addItem,
        ),
      ],
    );
  }
}

// ============================================================================
// BRAND LOGOS BLOCK CONTROLS
// Editor for brand logos carousel/grid
// ============================================================================
class _BrandLogosBlockControls extends StatefulWidget {
  final Map<String, dynamic> data;
  final String blockId;
  final WebsiteEditModeProvider provider;

  const _BrandLogosBlockControls({
    required this.data,
    required this.blockId,
    required this.provider,
  });

  @override
  State<_BrandLogosBlockControls> createState() => _BrandLogosBlockControlsState();
}

class _BrandLogosBlockControlsState extends State<_BrandLogosBlockControls> {
  int _currentIndex = 0;

  List<Map<String, dynamic>> get _brands {
    final raw = widget.data['brands'];
    if (raw is List) {
      return raw
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    return [];
  }

  void _updateField(String field, dynamic value) {
    widget.provider.updateBlockData(widget.blockId, field, value);
  }

  void _updateBrand(int index, String field, String value) {
    final brands = List<Map<String, dynamic>>.from(_brands);
    if (index < brands.length) {
      brands[index] = Map<String, dynamic>.from(brands[index]);
      brands[index][field] = value;
      _updateField('brands', brands);
    }
  }

  void _addBrand() {
    final brands = List<Map<String, dynamic>>.from(_brands);
    brands.add({
      'name': '',
      'imageUrl': '',
      'link': '',
    });
    _updateField('brands', brands);
    // Navigate to the new brand
    setState(() => _currentIndex = brands.length - 1);
  }

  void _removeBrand(int index) {
    final brands = List<Map<String, dynamic>>.from(_brands);
    if (brands.length > 1) {
      brands.removeAt(index);
      _updateField('brands', brands);
      // Adjust current index if needed
      if (_currentIndex >= brands.length) {
        setState(() => _currentIndex = brands.length - 1);
      }
    }
  }

  void _goToPrevious() {
    if (_currentIndex > 0) {
      setState(() => _currentIndex--);
    }
  }

  void _goToNext() {
    if (_currentIndex < _brands.length - 1) {
      setState(() => _currentIndex++);
    }
  }

  @override
  Widget build(BuildContext context) {
    final brands = _brands;
    // Ensure current index is valid
    if (_currentIndex >= brands.length && brands.isNotEmpty) {
      _currentIndex = brands.length - 1;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _EditorTextField(
          label: 'Título de la sección',
          value: widget.data['title']?.toString() ?? 'MARCAS',
          onChanged: (v) => _updateField('title', v),
        ),
        const SizedBox(height: 12),
        _EditorTextField(
          label: 'Color de acento (línea bajo título)',
          value: widget.data['accentColor']?.toString() ?? '',
          onChanged: (v) => _updateField('accentColor', v),
          hint: '#E53935 o dejar vacío',
        ),
        const SizedBox(height: 16),
        // Logo size selector
        const Text(
          'TAMAÑO DE LOGOS',
          style: TextStyle(
            color: Colors.white54,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            _LogoSizeOption(
              label: 'S',
              tooltip: 'Pequeño',
              value: 'small',
              currentValue: widget.data['logoSize']?.toString() ?? 'medium',
              onTap: () => _updateField('logoSize', 'small'),
            ),
            const SizedBox(width: 8),
            _LogoSizeOption(
              label: 'M',
              tooltip: 'Mediano',
              value: 'medium',
              currentValue: widget.data['logoSize']?.toString() ?? 'medium',
              onTap: () => _updateField('logoSize', 'medium'),
            ),
            const SizedBox(width: 8),
            _LogoSizeOption(
              label: 'L',
              tooltip: 'Grande',
              value: 'large',
              currentValue: widget.data['logoSize']?.toString() ?? 'medium',
              onTap: () => _updateField('logoSize', 'large'),
            ),
            const SizedBox(width: 8),
            _LogoSizeOption(
              label: 'XL',
              tooltip: 'Extra Grande',
              value: 'xlarge',
              currentValue: widget.data['logoSize']?.toString() ?? 'medium',
              onTap: () => _updateField('logoSize', 'xlarge'),
            ),
          ],
        ),
        const SizedBox(height: 20),
        
        // Horizontal brand navigator
        Row(
          children: [
            const Text(
              'MARCAS',
              style: TextStyle(
                color: Colors.white54,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFF00A09D).withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '${brands.length}',
                style: const TextStyle(
                  color: Color(0xFF00A09D),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const Spacer(),
            // Add button
            GestureDetector(
              onTap: _addBrand,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF00A09D),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.add, size: 14, color: Colors.white),
                    SizedBox(width: 4),
                    Text(
                      'Nueva',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        
        // Navigation arrows + current brand indicator
        if (brands.isNotEmpty) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Left arrow
              GestureDetector(
                onTap: _currentIndex > 0 ? _goToPrevious : null,
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: _currentIndex > 0
                        ? const Color(0xFF2D2D2D)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: _currentIndex > 0
                          ? Colors.white24
                          : Colors.white12,
                    ),
                  ),
                  child: Icon(
                    Icons.chevron_left,
                    size: 20,
                    color: _currentIndex > 0 ? Colors.white70 : Colors.white24,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Page indicators
              ...List.generate(brands.length, (index) {
                final isSelected = index == _currentIndex;
                return GestureDetector(
                  onTap: () => setState(() => _currentIndex = index),
                  child: Container(
                    width: isSelected ? 24 : 8,
                    height: 8,
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? const Color(0xFF00A09D)
                          : Colors.white24,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                );
              }),
              const SizedBox(width: 12),
              // Right arrow
              GestureDetector(
                onTap: _currentIndex < brands.length - 1 ? _goToNext : null,
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: _currentIndex < brands.length - 1
                        ? const Color(0xFF2D2D2D)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: _currentIndex < brands.length - 1
                          ? Colors.white24
                          : Colors.white12,
                    ),
                  ),
                  child: Icon(
                    Icons.chevron_right,
                    size: 20,
                    color: _currentIndex < brands.length - 1 ? Colors.white70 : Colors.white24,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          
          // Current brand editor (compact)
          _BrandLogoEditorCompact(
            index: _currentIndex,
            brand: brands[_currentIndex],
            totalBrands: brands.length,
            onUpdateField: (field, value) => _updateBrand(_currentIndex, field, value),
            onRemove: brands.length > 1 ? () => _removeBrand(_currentIndex) : null,
          ),
        ] else ...[
          // Empty state
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
            ),
            child: Column(
              children: [
                Icon(Icons.branding_watermark_outlined, size: 32, color: Colors.white38),
                const SizedBox(height: 8),
                Text(
                  'Sin marcas',
                  style: TextStyle(color: Colors.white54, fontSize: 13),
                ),
                const SizedBox(height: 4),
                Text(
                  'Agrega logos de marcas que trabajas',
                  style: TextStyle(color: Colors.white38, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// Size selector button for brand logos
class _LogoSizeOption extends StatelessWidget {
  final String label;
  final String tooltip;
  final String value;
  final String currentValue;
  final VoidCallback onTap;

  const _LogoSizeOption({
    required this.label,
    required this.tooltip,
    required this.value,
    required this.currentValue,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isSelected = value == currentValue;
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 40,
          height: 36,
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF00A09D) : const Color(0xFF2D2D2D),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: isSelected ? const Color(0xFF00A09D) : Colors.white24,
            ),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.white70,
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Individual brand logo editor with image upload (legacy - kept for compatibility)
class _BrandLogoEditor extends StatefulWidget {
  final int index;
  final Map<String, dynamic> brand;
  final int totalBrands;
  final void Function(String field, String value) onUpdateField;
  final VoidCallback onRemove;

  const _BrandLogoEditor({
    required this.index,
    required this.brand,
    required this.totalBrands,
    required this.onUpdateField,
    required this.onRemove,
  });

  @override
  State<_BrandLogoEditor> createState() => _BrandLogoEditorState();
}

class _BrandLogoEditorState extends State<_BrandLogoEditor> {
  bool _isUploading = false;

  Future<void> _pickAndUploadImage() async {
    final picker = ImagePicker();
    
    try {
      final pickedFile = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 400,
        maxHeight: 200,
      );
      
      if (pickedFile == null) return;
      
      setState(() => _isUploading = true);
      
      final bytes = await pickedFile.readAsBytes();
      final fileName = pickedFile.name;
      
      // Upload to Supabase Storage
      final supabase = Supabase.instance.client;
      final uniqueName = '${DateTime.now().millisecondsSinceEpoch}_$fileName';
      final path = 'brand-logos/$uniqueName';
      
      await supabase.storage.from('vinabike-assets').uploadBinary(
        path,
        bytes,
        fileOptions: const FileOptions(
          cacheControl: '3600',
          upsert: true,
        ),
      );
      
      final publicUrl = supabase.storage.from('vinabike-assets').getPublicUrl(path);
      
      widget.onUpdateField('imageUrl', publicUrl);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Logo subido correctamente'),
            backgroundColor: Color(0xFF00A09D),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error uploading brand logo: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Error al subir: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isUploading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.brand['name']?.toString() ?? '';
    final imageUrl = widget.brand['imageUrl']?.toString() ?? '';
    final link = widget.brand['link']?.toString() ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with reorder buttons and delete
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF00A09D).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'Marca ${widget.index + 1}',
                  style: const TextStyle(
                    color: Color(0xFF00A09D),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const Spacer(),
              if (widget.totalBrands > 1)
                IconButton(
                  icon: Icon(Icons.delete_outline, size: 16, color: Colors.red.shade300),
                  onPressed: widget.onRemove,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  tooltip: 'Eliminar',
                ),
            ],
          ),
          const SizedBox(height: 12),
          // Image upload area
          GestureDetector(
            onTap: _isUploading ? null : _pickAndUploadImage,
            child: Container(
              width: double.infinity,
              height: 80,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: imageUrl.isNotEmpty 
                      ? const Color(0xFF00A09D) 
                      : Colors.white.withValues(alpha: 0.2),
                  width: imageUrl.isNotEmpty ? 2 : 1,
                  style: imageUrl.isEmpty ? BorderStyle.solid : BorderStyle.solid,
                ),
              ),
              child: _isUploading
                  ? const Center(
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Color(0xFF00A09D),
                        ),
                      ),
                    )
                  : imageUrl.isNotEmpty
                      ? Stack(
                          children: [
                            Center(
                              child: Padding(
                                padding: const EdgeInsets.all(8),
                                child: Image.network(
                                  imageUrl,
                                  fit: BoxFit.contain,
                                  errorBuilder: (context, error, stackTrace) {
                                    return const Icon(Icons.broken_image, color: Colors.white38, size: 32);
                                  },
                                ),
                              ),
                            ),
                            Positioned(
                              top: 4,
                              right: 4,
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF00A09D),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Icon(Icons.edit, size: 12, color: Colors.white),
                              ),
                            ),
                          ],
                        )
                      : Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.cloud_upload_outlined, size: 28, color: Colors.white.withValues(alpha: 0.4)),
                            const SizedBox(height: 4),
                            Text(
                              'Click para subir logo',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.white.withValues(alpha: 0.5),
                              ),
                            ),
                            Text(
                              'PNG transparente recomendado',
                              style: TextStyle(
                                fontSize: 9,
                                color: Colors.white.withValues(alpha: 0.3),
                              ),
                            ),
                          ],
                        ),
            ),
          ),
          const SizedBox(height: 12),
          // Name field
          _EditorTextField(
            label: 'Nombre (opcional)',
            value: name,
            onChanged: (v) => widget.onUpdateField('name', v),
            hint: 'Ej: Shimano, SRAM...',
          ),
          const SizedBox(height: 8),
          // Link field (optional)
          _EditorTextField(
            label: 'Enlace (opcional)',
            value: link,
            onChanged: (v) => widget.onUpdateField('link', v),
            hint: 'https://marca.com',
          ),
        ],
      ),
    );
  }
}

/// Compact brand logo editor for horizontal navigation
class _BrandLogoEditorCompact extends StatefulWidget {
  final int index;
  final Map<String, dynamic> brand;
  final int totalBrands;
  final void Function(String field, String value) onUpdateField;
  final VoidCallback? onRemove;

  const _BrandLogoEditorCompact({
    required this.index,
    required this.brand,
    required this.totalBrands,
    required this.onUpdateField,
    this.onRemove,
  });

  @override
  State<_BrandLogoEditorCompact> createState() => _BrandLogoEditorCompactState();
}

class _BrandLogoEditorCompactState extends State<_BrandLogoEditorCompact> {
  bool _isUploading = false;

  Future<void> _pickAndUploadImage() async {
    final picker = ImagePicker();
    
    try {
      final pickedFile = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 400,
        maxHeight: 200,
      );
      
      if (pickedFile == null) return;
      
      setState(() => _isUploading = true);
      
      final bytes = await pickedFile.readAsBytes();
      final fileName = pickedFile.name;
      
      // Upload to Supabase Storage
      final supabase = Supabase.instance.client;
      final uniqueName = '${DateTime.now().millisecondsSinceEpoch}_$fileName';
      final path = 'brand-logos/$uniqueName';
      
      await supabase.storage.from('vinabike-assets').uploadBinary(
        path,
        bytes,
        fileOptions: const FileOptions(
          cacheControl: '3600',
          upsert: true,
        ),
      );
      
      final publicUrl = supabase.storage.from('vinabike-assets').getPublicUrl(path);
      
      widget.onUpdateField('imageUrl', publicUrl);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Logo subido correctamente'),
            backgroundColor: Color(0xFF00A09D),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error uploading brand logo: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Error al subir: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isUploading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.brand['name']?.toString() ?? '';
    final imageUrl = widget.brand['imageUrl']?.toString() ?? '';
    final link = widget.brand['link']?.toString() ?? '';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF00A09D).withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with brand number and delete
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF00A09D),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'Marca ${widget.index + 1}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const Spacer(),
              if (widget.onRemove != null)
                GestureDetector(
                  onTap: widget.onRemove,
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Icon(Icons.delete_outline, size: 16, color: Colors.red.shade300),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          
          // Image upload area
          GestureDetector(
            onTap: _isUploading ? null : _pickAndUploadImage,
            child: Container(
              width: double.infinity,
              height: 100,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: imageUrl.isNotEmpty 
                      ? const Color(0xFF00A09D) 
                      : Colors.white.withValues(alpha: 0.2),
                  width: imageUrl.isNotEmpty ? 2 : 1,
                ),
              ),
              child: _isUploading
                  ? const Center(
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Color(0xFF00A09D),
                        ),
                      ),
                    )
                  : imageUrl.isNotEmpty
                      ? Stack(
                          children: [
                            Center(
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Image.network(
                                  imageUrl,
                                  fit: BoxFit.contain,
                                  errorBuilder: (context, error, stackTrace) {
                                    return const Icon(Icons.broken_image, color: Colors.white38, size: 32);
                                  },
                                ),
                              ),
                            ),
                            Positioned(
                              top: 4,
                              right: 4,
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF00A09D),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Icon(Icons.edit, size: 12, color: Colors.white),
                              ),
                            ),
                          ],
                        )
                      : Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.cloud_upload_outlined, size: 32, color: Colors.white.withValues(alpha: 0.4)),
                            const SizedBox(height: 6),
                            Text(
                              'Click para subir logo',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.white.withValues(alpha: 0.5),
                              ),
                            ),
                            Text(
                              'PNG transparente recomendado',
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.white.withValues(alpha: 0.3),
                              ),
                            ),
                          ],
                        ),
            ),
          ),
          const SizedBox(height: 12),
          
          // Name field
          _EditorTextField(
            label: 'Nombre (opcional)',
            value: name,
            onChanged: (v) => widget.onUpdateField('name', v),
            hint: 'Ej: Shimano, SRAM...',
          ),
          const SizedBox(height: 8),
          
          // Link field
          _EditorTextField(
            label: 'Enlace (opcional)',
            value: link,
            onChanged: (v) => widget.onUpdateField('link', v),
            hint: 'https://marca.com',
          ),
        ],
      ),
    );
  }
}

/// Controls for editing the site header (special element, not a block)
class _HeaderBlockControls extends StatefulWidget {
  final WebsiteEditModeProvider provider;

  const _HeaderBlockControls({required this.provider});

  @override
  State<_HeaderBlockControls> createState() => _HeaderBlockControlsState();
}

class _HeaderBlockControlsState extends State<_HeaderBlockControls> {
  final _storeNameController = TextEditingController();
  final _logoUrlController = TextEditingController();
  final _topBannerController = TextEditingController();
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
    _logoUrlController.text = service.getSetting('logo_url', '');
    _topBannerController.text = service.getSetting('top_banner_text', 'Envíos a todo Chile');
  }

  Future<void> _saveSettings() async {
    final service = context.read<WebsiteService>();
    await service.saveSettings({
      'store_name': _storeNameController.text,
      'logo_url': _logoUrlController.text,
      'top_banner_text': _topBannerController.text,
    });
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Header guardado'),
          backgroundColor: Color(0xFF00A09D),
        ),
      );
    }
  }

  @override
  void dispose() {
    _storeNameController.dispose();
    _logoUrlController.dispose();
    _topBannerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with icon and title
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.web_asset, color: Colors.blue, size: 20),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Header',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      'Encabezado del sitio',
                      style: TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 24),
          
          // Logo section
          _SectionHeader('Logo'),
          const SizedBox(height: 12),
          _LogoUploader(
            currentUrl: _logoUrlController.text,
            onChanged: (url) {
              _logoUrlController.text = url;
              setState(() {});
            },
          ),
          
          const SizedBox(height: 20),
          
          // Store name
          _EditorTextField(
            label: 'Nombre de la tienda',
            value: _storeNameController.text,
            controller: _storeNameController,
            onChanged: (_) {},
            hint: 'Mi Tienda',
          ),
          
          const SizedBox(height: 16),
          
          // Top banner text
          _EditorTextField(
            label: 'Texto del banner superior',
            value: _topBannerController.text,
            controller: _topBannerController,
            onChanged: (_) {},
            hint: 'Envíos gratis en compras sobre \$50.000',
          ),
          
          const SizedBox(height: 24),
          
          // Save button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _saveSettings,
              icon: const Icon(Icons.save, size: 18),
              label: const Text('Guardar header'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00A09D),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Controls for editing the site footer (special element, not a block)
class _FooterBlockControls extends StatefulWidget {
  final WebsiteEditModeProvider provider;

  const _FooterBlockControls({required this.provider});

  @override
  State<_FooterBlockControls> createState() => _FooterBlockControlsState();
}

class _FooterBlockControlsState extends State<_FooterBlockControls> {
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _whatsappController = TextEditingController();
  final _addressController = TextEditingController();
  final _facebookController = TextEditingController();
  final _instagramController = TextEditingController();
  final _twitterController = TextEditingController();
  final _youtubeController = TextEditingController();
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
    _emailController.text = service.getSetting('contact_email', '');
    _phoneController.text = service.getSetting('contact_phone', '');
    _whatsappController.text = service.getSetting('whatsapp', '');
    _addressController.text = service.getSetting('contact_address', '');
    _facebookController.text = service.getSetting('facebook_handle', '');
    _instagramController.text = service.getSetting('instagram_handle', '');
    _twitterController.text = service.getSetting('twitter_handle', '');
    _youtubeController.text = service.getSetting('youtube_handle', '');
  }

  Future<void> _saveSettings() async {
    final service = context.read<WebsiteService>();
    await service.saveSettings({
      'contact_email': _emailController.text,
      'contact_phone': _phoneController.text,
      'whatsapp': _whatsappController.text,
      'contact_address': _addressController.text,
      'facebook_handle': _facebookController.text,
      'instagram_handle': _instagramController.text,
      'twitter_handle': _twitterController.text,
      'youtube_handle': _youtubeController.text,
    });
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Footer guardado'),
          backgroundColor: Color(0xFF00A09D),
        ),
      );
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _phoneController.dispose();
    _whatsappController.dispose();
    _addressController.dispose();
    _facebookController.dispose();
    _instagramController.dispose();
    _twitterController.dispose();
    _youtubeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with icon and title
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.web_asset_off, color: Colors.green, size: 20),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Footer',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      'Pie de página del sitio',
                      style: TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 24),
          
          // Contact section
          _SectionHeader('Contacto'),
          const SizedBox(height: 12),
          
          _EditorTextField(
            label: 'Email',
            value: _emailController.text,
            controller: _emailController,
            onChanged: (_) {},
            hint: 'contacto@mitienda.cl',
          ),
          const SizedBox(height: 12),
          
          _EditorTextField(
            label: 'Teléfono',
            value: _phoneController.text,
            controller: _phoneController,
            onChanged: (_) {},
            hint: '+56 2 1234 5678',
          ),
          const SizedBox(height: 12),
          
          _EditorTextField(
            label: 'WhatsApp',
            value: _whatsappController.text,
            controller: _whatsappController,
            onChanged: (_) {},
            hint: '+56912345678',
          ),
          const SizedBox(height: 12),
          
          _EditorTextField(
            label: 'Dirección',
            value: _addressController.text,
            controller: _addressController,
            onChanged: (_) {},
            hint: 'Av. Principal 123, Santiago',
          ),
          
          const SizedBox(height: 20),
          
          // Social media section
          _SectionHeader('Redes sociales'),
          const SizedBox(height: 12),
          
          _EditorTextField(
            label: 'Facebook',
            value: _facebookController.text,
            controller: _facebookController,
            onChanged: (_) {},
            hint: 'mitienda',
          ),
          const SizedBox(height: 12),
          
          _EditorTextField(
            label: 'Instagram',
            value: _instagramController.text,
            controller: _instagramController,
            onChanged: (_) {},
            hint: '@mitienda',
          ),
          const SizedBox(height: 12),
          
          _EditorTextField(
            label: 'Twitter/X',
            value: _twitterController.text,
            controller: _twitterController,
            onChanged: (_) {},
            hint: '@mitienda',
          ),
          const SizedBox(height: 12),
          
          _EditorTextField(
            label: 'YouTube',
            value: _youtubeController.text,
            controller: _youtubeController,
            onChanged: (_) {},
            hint: 'mitienda',
          ),
          
          const SizedBox(height: 24),
          
          // Save button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _saveSettings,
              icon: const Icon(Icons.save, size: 18),
              label: const Text('Guardar footer'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00A09D),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
        ],
      ),
    );
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

/// Dialog for managing website backups
class _BackupsDialog extends StatefulWidget {
  final VoidCallback? onRestoreComplete;

  const _BackupsDialog({this.onRestoreComplete});

  @override
  State<_BackupsDialog> createState() => _BackupsDialogState();
}

class _BackupsDialogState extends State<_BackupsDialog> {
  final WebsiteBackupService _backupService = WebsiteBackupService();
  List<WebsiteBackup> _backups = [];
  bool _isLoading = true;
  bool _isCreating = false;
  bool _isRestoring = false;
  String? _error;

  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadBackups();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _loadBackups() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final backups = await _backupService.loadBackups();
      if (mounted) {
        setState(() {
          _backups = backups;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _createBackup() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('El nombre es requerido')),
      );
      return;
    }

    setState(() => _isCreating = true);

    try {
      await _backupService.createBackup(
        name: name,
        description: _descriptionController.text.trim().isEmpty
            ? null
            : _descriptionController.text.trim(),
      );

      _nameController.clear();
      _descriptionController.clear();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Copia de seguridad creada'),
            backgroundColor: Colors.green,
          ),
        );
        await _loadBackups();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isCreating = false);
      }
    }
  }

  Future<void> _restoreBackup(WebsiteBackup backup) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Restaurar copia de seguridad?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Se restaurará: "${backup.name}"'),
            const SizedBox(height: 12),
            const Text(
              'Se creará automáticamente una copia de seguridad del estado actual antes de restaurar.',
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00A09D),
            ),
            child: const Text('Restaurar'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isRestoring = true);

    try {
      await _backupService.restoreBackup(backup.id);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Copia de seguridad restaurada'),
            backgroundColor: Colors.green,
          ),
        );
        widget.onRestoreComplete?.call();
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
        setState(() => _isRestoring = false);
      }
    }
  }

  Future<void> _deleteBackup(WebsiteBackup backup) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Eliminar copia de seguridad?'),
        content: Text('Se eliminará: "${backup.name}"'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await _backupService.deleteBackup(backup.id);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Copia de seguridad eliminada'),
            backgroundColor: Colors.orange,
          ),
        );
        await _loadBackups();
      }
    } catch (e) {
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

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        width: 500,
        constraints: const BoxConstraints(maxHeight: 600),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E1E),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.backup, color: Color(0xFF00A09D)),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Copias de Seguridad',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white54),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            // Create new backup section
            Container(
              padding: const EdgeInsets.all(16),
              color: const Color(0xFF2D2D2D),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Nueva copia de seguridad',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.white70,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _nameController,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Nombre (ej: "Antes de rediseño")',
                      hintStyle: TextStyle(color: Colors.white38),
                      filled: true,
                      fillColor: const Color(0xFF1E1E1E),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _descriptionController,
                    style: const TextStyle(color: Colors.white),
                    maxLines: 2,
                    decoration: InputDecoration(
                      hintText: 'Descripción (opcional)',
                      hintStyle: TextStyle(color: Colors.white38),
                      filled: true,
                      fillColor: const Color(0xFF1E1E1E),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _isCreating ? null : _createBackup,
                      icon: _isCreating
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.add),
                      label: Text(_isCreating ? 'Creando...' : 'Crear copia de seguridad'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF00A09D),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Divider
            const Divider(height: 1, color: Colors.white12),

            // Backups list
            Expanded(
              child: Container(
                color: const Color(0xFF1E1E1E),
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _error != null
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.error_outline, color: Colors.red, size: 48),
                                const SizedBox(height: 8),
                                Text(
                                  'Error cargando copias',
                                  style: TextStyle(color: Colors.red),
                                ),
                                TextButton(
                                  onPressed: _loadBackups,
                                  child: const Text('Reintentar'),
                                ),
                              ],
                            ),
                          )
                        : _backups.isEmpty
                            ? Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.inventory_2_outlined, color: Colors.white24, size: 48),
                                    const SizedBox(height: 8),
                                    const Text(
                                      'No hay copias de seguridad',
                                      style: TextStyle(color: Colors.white38),
                                    ),
                                  ],
                                ),
                              )
                            : ListView.builder(
                                padding: const EdgeInsets.symmetric(vertical: 8),
                              itemCount: _backups.length,
                              itemBuilder: (context, index) {
                                final backup = _backups[index];
                                return _BackupListItem(
                                  backup: backup,
                                  onRestore: () => _restoreBackup(backup),
                                  onDelete: () => _deleteBackup(backup),
                                  isRestoring: _isRestoring,
                                );
                              },
                            ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BackupListItem extends StatelessWidget {
  final WebsiteBackup backup;
  final VoidCallback onRestore;
  final VoidCallback onDelete;
  final bool isRestoring;

  const _BackupListItem({
    required this.backup,
    required this.onRestore,
    required this.onDelete,
    required this.isRestoring,
  });

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('dd/MM/yyyy HH:mm');
    
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF2D2D2D),
        borderRadius: BorderRadius.circular(8),
        border: backup.isAutoBackup
            ? Border.all(color: Colors.orange.withValues(alpha: 0.3))
            : null,
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        leading: CircleAvatar(
          backgroundColor: backup.isAutoBackup ? Colors.orange.withValues(alpha: 0.2) : const Color(0xFF00A09D).withValues(alpha: 0.2),
          child: Icon(
            backup.isAutoBackup ? Icons.autorenew : Icons.backup,
            color: backup.isAutoBackup ? Colors.orange : const Color(0xFF00A09D),
            size: 20,
          ),
        ),
        title: Text(
          backup.name,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w500,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (backup.description != null && backup.description!.isNotEmpty)
              Text(
                backup.description!,
                style: const TextStyle(color: Colors.white54, fontSize: 12),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            const SizedBox(height: 2),
            Row(
              children: [
                if (backup.isAutoBackup)
                  Container(
                    margin: const EdgeInsets.only(right: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      'AUTO',
                      style: TextStyle(
                        color: Colors.orange,
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                Text(
                  dateFormat.format(backup.createdAt.toLocal()),
                  style: const TextStyle(color: Colors.white38, fontSize: 11),
                ),
              ],
            ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: isRestoring
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.restore, size: 20),
              color: const Color(0xFF00A09D),
              tooltip: 'Restaurar',
              onPressed: isRestoring ? null : onRestore,
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 20),
              color: Colors.red.shade300,
              tooltip: 'Eliminar',
              onPressed: isRestoring ? null : onDelete,
            ),
          ],
        ),
      ),
    );
  }
}