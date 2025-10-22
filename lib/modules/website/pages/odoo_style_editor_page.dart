import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';
import 'dart:async';
import '../../../shared/widgets/main_layout.dart';
import '../../../shared/services/image_service.dart';
import '../../../shared/constants/storage_constants.dart';
import '../../../shared/services/inventory_service.dart';
import '../../../shared/models/product.dart';
import '../services/website_service.dart';
import '../widgets/website_block_renderer.dart';
import '../models/website_models.dart';
// import '../services/website_service.dart';

/// 🎨 ODOO-STYLE VISUAL EDITOR - PHASE 3
///
/// Professional block-based editor inspired by Odoo:
/// - Click blocks directly to edit them
/// - 3-tab panel: Agregar (Add) | Editar (Edit) | Tema (Theme)
/// - Visual block selection with highlighting
/// - Drag & drop block templates
/// - Context-aware controls
/// - Block reordering
///
/// This is the ULTIMATE version! 🚀

// Block types that can be added
enum BlockType {
  hero,
  carousel,
  products,
  services,
  about,
  testimonials,
  features,
  cta,
  gallery,
  contact,
}

// Block data model
class WebsiteBlock {
  final String id;
  final BlockType type;
  final Map<String, dynamic> data;
  bool isVisible;

  WebsiteBlock({
    required this.id,
    required this.type,
    required this.data,
    this.isVisible = true,
  });

  WebsiteBlock copyWith({
    String? id,
    BlockType? type,
    Map<String, dynamic>? data,
    bool? isVisible,
  }) {
    return WebsiteBlock(
      id: id ?? this.id,
      type: type ?? this.type,
      data: data ?? Map.from(this.data),
      isVisible: isVisible ?? this.isVisible,
    );
  }
}

class OdooStyleEditorPage extends StatefulWidget {
  const OdooStyleEditorPage({super.key});

  @override
  State<OdooStyleEditorPage> createState() => _OdooStyleEditorPageState();
}

class _OdooStyleEditorPageState extends State<OdooStyleEditorPage> {
  // ============================================================================
  // STATE MANAGEMENT
  // ============================================================================

  bool _isSaving = false;
  bool _hasChanges = false;
  bool _autoSaveEnabled = true;
  Timer? _autoSaveTimer;

  // History for undo/redo
  final List<List<WebsiteBlock>> _history = [];
  int _historyIndex = -1;
  final int _maxHistory = 50;

  // Preview mode
  String _previewMode = 'desktop'; // desktop, tablet, mobile
  double _previewZoom = 1.0;

  // Tab state
  String _activeTab = 'editar'; // agregar, editar, tema

  // Blocks
  List<WebsiteBlock> _blocks = [];
  String? _selectedBlockId;

  // Global theme settings
  Color _primaryColor = const Color(0xFF2E7D32);
  Color _accentColor = const Color(0xFFFF6F00);
  Color _backgroundColor = Colors.white;
  Color _textColor = Colors.black87;
  String _headingFont = 'Roboto';
  String _bodyFont = 'Roboto';
  double _headingSize = 48.0;
  double _bodySize = 16.0;
  double _sectionSpacing = 64.0;
  double _containerPadding = 24.0;

  @override
  void initState() {
    super.initState();
    _loadFromDatabase();
    _loadThemeSettings();
    _startAutoSave();
  }

  Future<void> _loadThemeSettings() async {
    try {
      final service = context.read<WebsiteService>();
      await service.loadSettings();
      final primary = service.getSetting('theme_primary_color');
      final accent = service.getSetting('theme_accent_color');
      final headingFont = service.getSetting('theme_heading_font');
      final bodyFont = service.getSetting('theme_body_font');

      final parsedPrimary = _tryParseColor(primary);
      final parsedAccent = _tryParseColor(accent);

      setState(() {
        if (parsedPrimary != null) {
          _primaryColor = parsedPrimary;
        }
        if (parsedAccent != null) {
          _accentColor = parsedAccent;
        }
        if (headingFont.isNotEmpty) {
          _headingFont = headingFont;
        }
        if (bodyFont.isNotEmpty) {
          _bodyFont = bodyFont;
        }
      });
    } catch (e) {
      debugPrint('[OdooEditor] Failed to load theme settings: $e');
    }
  }

  Future<void> _loadFromDatabase() async {
    try {
      final websiteService = context.read<WebsiteService>();
      final inventoryService = context.read<InventoryService>();

      await Future.wait([
        websiteService.loadBlocks(),
        websiteService.loadFeaturedProducts(),
        inventoryService.getProducts(),
      ]);

      final loadedBlocks = List<Map<String, dynamic>>.from(
        websiteService.blocks,
      );

      if (loadedBlocks.isEmpty) {
        // No blocks in database, use defaults
        _initializeDefaultBlocks();
      } else {
        // Convert database blocks to WebsiteBlock objects
        _blocks = loadedBlocks.map((blockData) {
          return WebsiteBlock(
            id: blockData['id'] ?? '',
            type: _parseBlockType(blockData['block_type'] ?? 'hero'),
            data: Map<String, dynamic>.from(blockData['block_data'] ?? {}),
            isVisible: blockData['is_visible'] ?? true,
          );
        }).toList();

        if (_blocks.isNotEmpty) {
          _selectedBlockId = _blocks.first.id;
        }
      }

      if (mounted) {
        setState(() {});
        _saveToHistory();
      }
    } catch (e) {
      debugPrint('[OdooEditor] Error loading blocks: $e');
      // Fallback to defaults on error
      _initializeDefaultBlocks();
      if (mounted) {
        setState(() {});
        _saveToHistory();
      }
    }
  }

  BlockType _parseBlockType(String typeString) {
    switch (typeString) {
      case 'hero':
        return BlockType.hero;
      case 'carousel':
        return BlockType.carousel;
      case 'products':
        return BlockType.products;
      case 'services':
        return BlockType.services;
      case 'about':
        return BlockType.about;
      case 'testimonials':
        return BlockType.testimonials;
      case 'features':
        return BlockType.features;
      case 'cta':
        return BlockType.cta;
      case 'gallery':
        return BlockType.gallery;
      case 'contact':
        return BlockType.contact;
      default:
        return BlockType.hero;
    }
  }

  void _initializeDefaultBlocks() {
    const uuid = Uuid();
    _blocks = [
      WebsiteBlock(
        id: uuid.v4(),
        type: BlockType.hero,
        data: {
          'title': 'SERVICIOS Y PRODUCTOS DE BICICLETA',
          'subtitle': 'TODO LO QUE NECESITAS PARA TU BICICLETA EN VIÑA DEL MAR',
          'ctaText': 'VER PRODUCTOS',
          'alignment': 'center',
          'showOverlay': true,
          'overlayOpacity': 0.5,
          'imageUrl': null,
        },
      ),
      WebsiteBlock(
        id: uuid.v4(),
        type: BlockType.products,
        data: {
          'title': 'Productos Destacados',
          'layout': 'grid',
          'itemsPerRow': 3,
        },
      ),
      WebsiteBlock(
        id: uuid.v4(),
        type: BlockType.services,
        data: {
          'title': 'Nuestros Servicios',
          'services': [
            {
              'title': 'Venta de Bicicletas',
              'icon': 'directions_bike',
              'description': 'Amplio catálogo'
            },
            {
              'title': 'Reparaciones',
              'icon': 'build',
              'description': 'Servicio técnico'
            },
            {
              'title': 'Accesorios',
              'icon': 'shopping_bag',
              'description': 'Todo para tu bici'
            },
          ],
        },
      ),
      WebsiteBlock(
        id: uuid.v4(),
        type: BlockType.about,
        data: {
          'title': 'Sobre Nosotros',
          'content':
              'Somos una tienda especializada en bicicletas con más de 10 años de experiencia.',
          'imageUrl': null,
          'imagePosition': 'right',
        },
      ),
    ];

    if (_blocks.isNotEmpty) {
      _selectedBlockId = _blocks.first.id;
    }
  }

  void _markAsChanged() {
    if (!_hasChanges) {
      setState(() => _hasChanges = true);
      _saveToHistory();
    }
  }

  void _startAutoSave() {
    _autoSaveTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (_autoSaveEnabled && _hasChanges && !_isSaving && mounted) {
        _saveChanges(showNotification: false);
      }
    });
  }

  void _saveToHistory() {
    if (_historyIndex < _history.length - 1) {
      _history.removeRange(_historyIndex + 1, _history.length);
    }

    _history.add(_blocks.map((b) => b.copyWith()).toList());
    _historyIndex = _history.length - 1;

    if (_history.length > _maxHistory) {
      _history.removeAt(0);
      _historyIndex--;
    }
  }

  void _undo() {
    if (_historyIndex > 0) {
      setState(() {
        _historyIndex--;
        _blocks = _history[_historyIndex].map((b) => b.copyWith()).toList();
        _hasChanges = true;
      });
    }
  }

  void _redo() {
    if (_historyIndex < _history.length - 1) {
      setState(() {
        _historyIndex++;
        _blocks = _history[_historyIndex].map((b) => b.copyWith()).toList();
        _hasChanges = true;
      });
    }
  }

  Future<void> _saveChanges({bool showNotification = true}) async {
    if (!mounted) return;

    setState(() => _isSaving = true);

    try {
      final websiteService = context.read<WebsiteService>();

      // Convert WebsiteBlock objects to database format
      final blocksData = _blocks.map((block) {
        return {
          'id': block.id,
          'type': block.type.name, // Convert enum to string
          'data': block.data,
          'isVisible': block.isVisible,
        };
      }).toList();

      // Save to database
      await websiteService.saveBlocks(blocksData);

      if (mounted) {
        setState(() {
          _hasChanges = false;
          _isSaving = false;
        });
      }

      if (mounted && showNotification) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white),
                SizedBox(width: 8),
                Text('✅ Cambios guardados exitosamente'),
              ],
            ),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Error al guardar: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Color? _tryParseColor(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return null;
    }

    int? intValue;
    var cleaned = trimmed.toLowerCase();

    if (cleaned.startsWith('color(')) {
      final inside = cleaned.replaceAll(RegExp(r'color\(|\)'), '');
      intValue = int.tryParse(inside);
    }

    intValue ??= int.tryParse(cleaned);
    if (intValue == null && cleaned.startsWith('0x')) {
      intValue = int.tryParse(cleaned);
    }

    if (intValue == null) {
      cleaned = cleaned.replaceAll('#', '');
      intValue = int.tryParse(cleaned, radix: 16);
      if (intValue != null && cleaned.length <= 6) {
        intValue = 0xFF000000 | intValue;
      }
    }

    if (intValue != null) {
      return Color(intValue);
    }

    return null;
  }

  void _selectBlock(String blockId) {
    setState(() {
      _selectedBlockId = blockId;
      _activeTab = 'editar'; // Switch to edit tab when selecting a block
    });
  }

  void _addBlock(BlockType type) {
    final newBlock = _createBlockTemplate(type);
    setState(() {
      _blocks.add(newBlock);
      _selectedBlockId = newBlock.id;
      _activeTab = 'editar';
      _markAsChanged();
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('✅ Bloque "${_getBlockTypeName(type)}" añadido'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  WebsiteBlock _createBlockTemplate(BlockType type) {
    const uuid = Uuid();
    final id = uuid.v4(); // Generate proper UUID

    switch (type) {
      case BlockType.hero:
        return WebsiteBlock(
          id: id,
          type: type,
          data: {
            'title': 'Nuevo Título',
            'subtitle': 'Nuevo subtítulo',
            'ctaText': 'BOTÓN',
            'alignment': 'center',
            'showOverlay': true,
            'overlayOpacity': 0.5,
          },
        );
      case BlockType.carousel:
        return WebsiteBlock(
          id: id,
          type: type,
          data: {
            'autoPlay': true,
            'intervalSeconds': 5,
            'animation': 'slide',
            'showIndicators': true,
            'showArrows': true,
            'slides': [
              {
                'title': 'Destaca tus ofertas',
                'subtitle': 'Promociones semanales para ciclistas',
                'ctaText': 'Ver catálogo',
                'ctaLink': '/tienda/productos',
                'imageUrl': null,
                'showOverlay': true,
                'overlayOpacity': 0.55,
              },
            ],
          },
        );
      case BlockType.products:
        return WebsiteBlock(
          id: id,
          type: type,
          data: {
            'title': 'Productos',
            'layout': 'grid',
            'itemsPerRow': 3,
          },
        );
      case BlockType.services:
        return WebsiteBlock(
          id: id,
          type: type,
          data: {
            'title': 'Servicios',
            'services': [],
          },
        );
      case BlockType.about:
        return WebsiteBlock(
          id: id,
          type: type,
          data: {
            'title': 'Sobre Nosotros',
            'content': 'Contenido...',
            'imagePosition': 'right',
          },
        );
      case BlockType.testimonials:
        return WebsiteBlock(
          id: id,
          type: type,
          data: {
            'title': 'Testimonios',
            'testimonials': [],
          },
        );
      case BlockType.features:
        return WebsiteBlock(
          id: id,
          type: type,
          data: {
            'title': 'Características',
            'features': [],
          },
        );
      case BlockType.cta:
        return WebsiteBlock(
          id: id,
          type: type,
          data: {
            'title': 'Llamado a la Acción',
            'buttonText': 'COMENZAR',
          },
        );
      case BlockType.gallery:
        return WebsiteBlock(
          id: id,
          type: type,
          data: {
            'title': 'Galería',
            'images': [],
          },
        );
      case BlockType.contact:
        return WebsiteBlock(
          id: id,
          type: type,
          data: {
            'title': 'Contacto',
            'showForm': true,
          },
        );
    }
  }

  void _removeBlock(String blockId) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('🗑️ Eliminar Bloque'),
        content:
            const Text('¿Estás seguro de que quieres eliminar este bloque?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              setState(() {
                _blocks.removeWhere((b) => b.id == blockId);
                if (_selectedBlockId == blockId && _blocks.isNotEmpty) {
                  _selectedBlockId = _blocks.first.id;
                }
                _markAsChanged();
              });
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('✅ Bloque eliminado')),
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
  }

  void _duplicateBlock(String blockId) {
    final block = _blocks.firstWhere((b) => b.id == blockId);
    final newBlock = block.copyWith(
      id: '${block.type.name}_${DateTime.now().millisecondsSinceEpoch}',
    );

    setState(() {
      final index = _blocks.indexOf(block);
      _blocks.insert(index + 1, newBlock);
      _selectedBlockId = newBlock.id;
      _markAsChanged();
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('✅ Bloque duplicado')),
    );
  }

  void _moveBlock(int oldIndex, int newIndex) {
    setState(() {
      if (oldIndex < 0 || oldIndex >= _blocks.length) {
        return;
      }

      final block = _blocks.removeAt(oldIndex);

      var targetIndex = newIndex;
      if (targetIndex < 0) {
        targetIndex = 0;
      }
      if (targetIndex > _blocks.length) {
        targetIndex = _blocks.length;
      }

      _blocks.insert(targetIndex, block);
      _markAsChanged();
    });
  }

  void _moveBlockToTop(int index) {
    _moveBlock(index, 0);
  }

  void _moveBlockToBottom(int index) {
    _moveBlock(index, _blocks.length - 1);
  }

  String _getBlockTypeName(BlockType type) {
    switch (type) {
      case BlockType.hero:
        return 'Hero / Banner';
      case BlockType.carousel:
        return 'Carrusel Banner';
      case BlockType.products:
        return 'Productos';
      case BlockType.services:
        return 'Servicios';
      case BlockType.about:
        return 'Sobre Nosotros';
      case BlockType.testimonials:
        return 'Testimonios';
      case BlockType.features:
        return 'Características';
      case BlockType.cta:
        return 'Llamado a la Acción';
      case BlockType.gallery:
        return 'Galería';
      case BlockType.contact:
        return 'Contacto';
    }
  }

  IconData _getBlockTypeIcon(BlockType type) {
    switch (type) {
      case BlockType.hero:
        return Icons.view_carousel;
      case BlockType.carousel:
        return Icons.slideshow;
      case BlockType.products:
        return Icons.shopping_bag;
      case BlockType.services:
        return Icons.room_service;
      case BlockType.about:
        return Icons.info;
      case BlockType.testimonials:
        return Icons.format_quote;
      case BlockType.features:
        return Icons.star;
      case BlockType.cta:
        return Icons.touch_app;
      case BlockType.gallery:
        return Icons.photo_library;
      case BlockType.contact:
        return Icons.contact_mail;
    }
  }

  void _showColorPicker(Color currentColor, Function(Color) onColorChanged) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        Color pickerColor = currentColor;

        return AlertDialog(
          title: const Text('Seleccionar Color'),
          content: SingleChildScrollView(
            child: ColorPicker(
              pickerColor: pickerColor,
              onColorChanged: (color) => pickerColor = color,
              pickerAreaHeightPercent: 0.8,
              enableAlpha: false,
              displayThumbColor: true,
              labelTypes: const [
                ColorLabelType.rgb,
                ColorLabelType.hsv,
                ColorLabelType.hsl,
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('CANCELAR'),
            ),
            ElevatedButton(
              onPressed: () {
                onColorChanged(pickerColor);
                Navigator.of(context).pop();
              },
              child: const Text('APLICAR'),
            ),
          ],
        );
      },
    );
  }

  Future<String?> _pickAndUploadImage({String folder = 'website/banners'}) async {
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1920,
        maxHeight: 1080,
        imageQuality: 85,
      );

      if (image == null) {
        return null;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              ),
              SizedBox(width: 12),
              Text('📤 Subiendo imagen...'),
            ],
          ),
          duration: Duration(seconds: 30),
        ),
      );

      final bytes = await image.readAsBytes();
      final imageUrl = await ImageService.uploadBytes(
        bytes: bytes,
        fileName: image.name,
        bucket: StorageConfig.defaultBucket,
        folder: folder,
      );

      ScaffoldMessenger.of(context).hideCurrentSnackBar();

      if (imageUrl == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('❌ No se pudo obtener la URL de la imagen'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 4),
          ),
        );
        return null;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Imagen subida exitosamente'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );

      return imageUrl;
    } catch (e) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Error al subir imagen: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
        ),
      );
      return null;
    }
  }

  Future<void> _pickImage() async {
    if (_selectedBlockId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('❌ No hay ningún bloque seleccionado'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final imageUrl = await _pickAndUploadImage(folder: 'website/banners');
    if (imageUrl == null) {
      return;
    }

    final blockIndex = _blocks.indexWhere((b) => b.id == _selectedBlockId);
    if (blockIndex == -1) {
      return;
    }

    setState(() {
      _blocks[blockIndex].data['imageUrl'] = imageUrl;
      _hasChanges = true;
    });

    if (_autoSaveEnabled) {
      await _saveChanges(showNotification: false);
    }
  }

  @override
  void dispose() {
    _autoSaveTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return MainLayout(
      child: Scaffold(
        backgroundColor: theme.colorScheme.surfaceContainerLowest,
        appBar: _buildAppBar(theme),
        body: Row(
          children: [
            // LEFT: Live Preview with Clickable Blocks
            Expanded(
              flex: 3,
              child: _buildPreviewPanel(theme),
            ),

            // RIGHT: 3-Tab Edit Panel
            SizedBox(
              width: 380,
              child: _buildEditPanel(theme),
            ),
          ],
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(ThemeData theme) {
    return AppBar(
      title: Row(
        children: [
          const Text('🎨 Editor Odoo-Style'),
          const SizedBox(width: 12),
          if (_hasChanges)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.orange.shade100,
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                'Sin guardar',
                style: TextStyle(
                    fontSize: 11,
                    color: Colors.orange,
                    fontWeight: FontWeight.bold),
              ),
            ),
          if (_autoSaveEnabled && !_hasChanges)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.green.shade100,
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                'Auto-guardado ✓',
                style: TextStyle(
                    fontSize: 11,
                    color: Colors.green,
                    fontWeight: FontWeight.bold),
              ),
            ),
        ],
      ),
      backgroundColor: theme.colorScheme.surface,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: () {
          if (_hasChanges) {
            _showUnsavedChangesDialog();
          } else {
            // If we can pop (opened via Navigator.push), go back
            // Otherwise use GoRouter to navigate to /website
            if (Navigator.canPop(context)) {
              Navigator.pop(context);
            } else {
              context.go('/website');
            }
          }
        },
      ),
      actions: [
        // Undo/Redo
        IconButton(
          icon: const Icon(Icons.undo),
          onPressed: _historyIndex > 0 ? _undo : null,
          tooltip: 'Deshacer',
        ),
        IconButton(
          icon: const Icon(Icons.redo),
          onPressed: _historyIndex < _history.length - 1 ? _redo : null,
          tooltip: 'Rehacer',
        ),

        const VerticalDivider(),

        // Auto-save toggle
        Tooltip(
          message: 'Auto-guardado',
          child: Switch(
            value: _autoSaveEnabled,
            onChanged: (value) => setState(() => _autoSaveEnabled = value),
          ),
        ),
        const SizedBox(width: 8),

        // Preview - More prominent button
        ElevatedButton.icon(
          onPressed: _isSaving
              ? null
              : () async {
                  try {
                    // Ensure latest changes are persisted before previewing
                    if (_hasChanges) {
                      await _saveChanges(showNotification: false);
                    }

                    if (!mounted) return;

                    final websiteService = context.read<WebsiteService>();
                    await Future.wait([
                      websiteService.loadBlocks(),
                      websiteService.loadSettings(),
                      websiteService.loadBanners(),
                      websiteService.loadFeaturedProducts(),
                    ]);

                    if (!mounted) return;

                    // If opened via Navigator.push (from preview), close editor first
                    if (Navigator.canPop(context)) {
                      Navigator.pop(context);
                      await Future.delayed(const Duration(milliseconds: 100));
                    }

                    if (mounted) {
                      context.go('/tienda');
                    }
                  } catch (error) {
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content:
                            Text('❌ Error al preparar la vista previa: $error'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                },
          icon: const Icon(Icons.visibility),
          label: const Text('Vista Previa'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.green.shade600,
            foregroundColor: Colors.white,
          ),
        ),
        const SizedBox(width: 8),

        // Save
        ElevatedButton.icon(
          onPressed: _hasChanges && !_isSaving ? () => _saveChanges() : null,
          icon: _isSaving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : const Icon(Icons.save),
          label: Text(_isSaving ? 'Guardando...' : 'Guardar'),
          style: ElevatedButton.styleFrom(
            backgroundColor:
                _hasChanges ? theme.colorScheme.primary : Colors.grey,
            foregroundColor: Colors.white,
          ),
        ),
        const SizedBox(width: 16),
      ],
    );
  }

  Widget _buildPreviewPanel(ThemeData theme) {
    return Container(
      color: theme.colorScheme.surfaceContainerLow,
      child: Column(
        children: [
          // Preview toolbar
          _buildPreviewToolbar(theme),

          // Preview content
          Expanded(
            child: _buildResponsivePreview(theme),
          ),
        ],
      ),
    );
  }

  Widget _buildPreviewToolbar(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF37474F), // Dark blue-grey for better contrast
        border: Border(bottom: BorderSide(color: Colors.grey.shade700)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Icon(Icons.touch_app, size: 20, color: Colors.white),
          const SizedBox(width: 12),
          Text(
            '👆 Haz clic en los bloques para editarlos',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const Spacer(),

          // Device selector
          Container(
            decoration: BoxDecoration(
              color: Colors.black26,
              borderRadius: BorderRadius.circular(8),
            ),
            child: SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                  value: 'mobile',
                  icon: Icon(Icons.smartphone, size: 16),
                  label: Text('Móvil'),
                ),
                ButtonSegment(
                  value: 'tablet',
                  icon: Icon(Icons.tablet, size: 16),
                  label: Text('Tablet'),
                ),
                ButtonSegment(
                  value: 'desktop',
                  icon: Icon(Icons.computer, size: 16),
                  label: Text('Desktop'),
                ),
              ],
              selected: {_previewMode},
              onSelectionChanged: (Set<String> newSelection) {
                setState(() => _previewMode = newSelection.first);
              },
              style: ButtonStyle(
                backgroundColor: MaterialStateProperty.resolveWith((states) {
                  if (states.contains(MaterialState.selected)) {
                    return Colors.blue;
                  }
                  return Colors.transparent;
                }),
                foregroundColor: MaterialStateProperty.all(Colors.white),
              ),
            ),
          ),

          const SizedBox(width: 20),

          // Zoom controls
          Container(
            decoration: BoxDecoration(
              color: Colors.black26,
              borderRadius: BorderRadius.circular(8),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon:
                      const Icon(Icons.zoom_out, size: 20, color: Colors.white),
                  onPressed: () => setState(() =>
                      _previewZoom = (_previewZoom - 0.1).clamp(0.5, 2.0)),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
                const SizedBox(width: 12),
                Text(
                  '${(_previewZoom * 100).toInt()}%',
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w500),
                ),
                const SizedBox(width: 12),
                IconButton(
                  icon:
                      const Icon(Icons.zoom_in, size: 20, color: Colors.white),
                  onPressed: () => setState(() =>
                      _previewZoom = (_previewZoom + 0.1).clamp(0.5, 2.0)),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResponsivePreview(ThemeData theme) {
    double previewWidth;
    switch (_previewMode) {
      case 'mobile':
        previewWidth = 375;
        break;
      case 'tablet':
        previewWidth = 768;
        break;
      default:
        previewWidth = double.infinity;
    }

    return Center(
      child: Transform.scale(
        scale: _previewZoom,
        child: Container(
          width: previewWidth,
          margin: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _backgroundColor,
            borderRadius:
                BorderRadius.circular(_previewMode != 'desktop' ? 12 : 8),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 20,
                spreadRadius: 2,
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius:
                BorderRadius.circular(_previewMode != 'desktop' ? 12 : 8),
            child: _buildClickablePreview(context),
          ),
        ),
      ),
    );
  }

  Widget _buildClickablePreview(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        children: _blocks.asMap().entries.map((entry) {
          final index = entry.key;
          final block = entry.value;
          final isSelected = block.id == _selectedBlockId;

          return GestureDetector(
            onTap: () => _selectBlock(block.id),
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: isSelected ? Colors.blue : Colors.transparent,
                    width: 3,
                  ),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: Colors.blue.withOpacity(0.3),
                            blurRadius: 10,
                            spreadRadius: 2,
                          ),
                        ]
                      : null,
                ),
                child: Stack(
                  children: [
                    _buildBlockPreview(block),

                    // Block actions overlay (shown on hover when selected)
                    if (isSelected)
                      Positioned(
                        top: 8,
                        right: 8,
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.blue,
                            borderRadius: BorderRadius.circular(8),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.2),
                                blurRadius: 8,
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Move to top
                              if (index > 0)
                                IconButton(
                                  icon: const Icon(Icons.vertical_align_top,
                                      color: Colors.white, size: 16),
                                  onPressed: () => _moveBlockToTop(index),
                                  tooltip: 'Mover al principio',
                                ),

                              // Move up
                              if (index > 0)
                                IconButton(
                                  icon: const Icon(Icons.arrow_upward,
                                      color: Colors.white, size: 16),
                                  onPressed: () => _moveBlock(index, index - 1),
                                  tooltip: 'Mover arriba',
                                ),

                              // Move down
                              if (index < _blocks.length - 1)
                                IconButton(
                                  icon: const Icon(Icons.arrow_downward,
                                      color: Colors.white, size: 16),
                                  onPressed: () => _moveBlock(index, index + 1),
                                  tooltip: 'Mover abajo',
                                ),

                              // Move to bottom
                              if (index < _blocks.length - 1)
                                IconButton(
                                  icon: const Icon(Icons.vertical_align_bottom,
                                      color: Colors.white, size: 16),
                                  onPressed: () => _moveBlockToBottom(index),
                                  tooltip: 'Mover al final',
                                ),

                              // Duplicate
                              IconButton(
                                icon: const Icon(Icons.content_copy,
                                    color: Colors.white, size: 16),
                                onPressed: () => _duplicateBlock(block.id),
                                tooltip: 'Duplicar',
                              ),

                              // Delete
                              IconButton(
                                icon: const Icon(Icons.delete,
                                    color: Colors.white, size: 16),
                                onPressed: () => _removeBlock(block.id),
                                tooltip: 'Eliminar',
                              ),
                            ],
                          ),
                        ),
                      ),

                    // Block label
                    if (isSelected)
                      Positioned(
                        top: 8,
                        left: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.blue,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(_getBlockTypeIcon(block.type),
                                  color: Colors.white, size: 14),
                              const SizedBox(width: 6),
                              Text(
                                _getBlockTypeName(block.type),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildBlockPreview(WebsiteBlock block) {
    final blockType = block.type.name;
    final data = Map<String, dynamic>.from(block.data);
    final websiteService = context.read<WebsiteService>();
    final inventoryService = context.read<InventoryService>();

    final previewFeaturedProducts = block.type == BlockType.products
        ? _resolveEditorFeaturedProducts(
            websiteService.featuredProducts,
            inventoryService.products,
          )
        : null;

    return WebsiteBlockRenderer.build(
      context: context,
      blockType: blockType,
      data: data,
      primaryColor: _primaryColor,
      accentColor: _accentColor,
      featuredProducts: previewFeaturedProducts,
      previewMode: true,
      headingFont: _headingFont,
      bodyFont: _bodyFont,
      headingSize: _headingSize,
      bodySize: _bodySize,
      onNavigate: (_) {},
    );
  }

  List<Product>? _resolveEditorFeaturedProducts(
    List<FeaturedProduct> entries,
    List<Product> products,
  ) {
    if (entries.isEmpty || products.isEmpty) {
      return null;
    }

    final productMap = {for (final product in products) product.id: product};
    final sortedEntries = entries
        .where((entry) => entry.active)
        .toList()
      ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));

    final resolvedProducts = <Product>[];
    for (final entry in sortedEntries) {
      final product = productMap[entry.productId];
      if (product != null && product.isActive) {
        resolvedProducts.add(product);
      }
    }

    return resolvedProducts.isEmpty ? null : resolvedProducts;
  }

  // ============================================================================
  // EDIT PANEL - 3 TABS: AGREGAR | EDITAR | TEMA
  // ============================================================================

  Widget _buildEditPanel(ThemeData theme) {
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(left: BorderSide(color: theme.dividerColor)),
      ),
      child: Column(
        children: [
          // Tab bar
          _buildTabBar(theme),

          // Tab content
          Expanded(
            child: _buildTabContent(theme),
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar(ThemeData theme) {
    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: theme.dividerColor)),
      ),
      child: Row(
        children: [
          _buildTab('agregar', '➕ Agregar', theme),
          _buildTab('editar', '✏️ Editar', theme),
          _buildTab('tema', '🎨 Tema', theme),
        ],
      ),
    );
  }

  Widget _buildTab(String tab, String label, ThemeData theme) {
    final isActive = _activeTab == tab;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _activeTab = tab),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            color: isActive
                ? theme.colorScheme.primaryContainer.withOpacity(0.3)
                : null,
            border: Border(
              bottom: BorderSide(
                color:
                    isActive ? theme.colorScheme.primary : Colors.transparent,
                width: 3,
              ),
            ),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
              color: isActive
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurface,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTabContent(ThemeData theme) {
    switch (_activeTab) {
      case 'agregar':
        return _buildAgregarTab(theme);
      case 'editar':
        return _buildEditarTab(theme);
      case 'tema':
        return _buildTemaTab(theme);
      default:
        return const SizedBox();
    }
  }

  // ============================================================================
  // TAB 1: AGREGAR (Add Block Templates)
  // ============================================================================

  Widget _buildAgregarTab(ThemeData theme) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Bloques Disponibles',
          style:
              theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        ...BlockType.values.map((type) {
          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: theme.colorScheme.primaryContainer,
                child: Icon(_getBlockTypeIcon(type),
                    color: theme.colorScheme.primary),
              ),
              title: Text(
                _getBlockTypeName(type),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Text(_getBlockTypeDescription(type)),
              trailing: ElevatedButton(
                onPressed: () => _addBlock(type),
                child: const Text('Añadir'),
              ),
            ),
          );
        }),
      ],
    );
  }

  String _getBlockTypeDescription(BlockType type) {
    switch (type) {
      case BlockType.hero:
        return 'Banner principal con imagen y CTA';
      case BlockType.carousel:
        return 'Carrusel de imágenes con CTA';
      case BlockType.products:
        return 'Catálogo de productos';
      case BlockType.services:
        return 'Lista de servicios';
      case BlockType.about:
        return 'Sección sobre nosotros';
      case BlockType.testimonials:
        return 'Testimonios de clientes';
      case BlockType.features:
        return 'Características destacadas';
      case BlockType.cta:
        return 'Llamado a la acción';
      case BlockType.gallery:
        return 'Galería de imágenes';
      case BlockType.contact:
        return 'Formulario de contacto';
    }
  }

  // ============================================================================
  // TAB 2: EDITAR (Edit Selected Block)
  // ============================================================================

  Widget _buildEditarTab(ThemeData theme) {
    if (_selectedBlockId == null || _blocks.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.touch_app, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            Text(
              'Selecciona un bloque\npara editarlo',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600, fontSize: 16),
            ),
          ],
        ),
      );
    }

    final block = _blocks.firstWhere((b) => b.id == _selectedBlockId);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Block header
        Row(
          children: [
            CircleAvatar(
              backgroundColor: theme.colorScheme.primaryContainer,
              child: Icon(_getBlockTypeIcon(block.type),
                  color: theme.colorScheme.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _getBlockTypeName(block.type),
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    'ID: ${block.id}',
                    style:
                        theme.textTheme.bodySmall?.copyWith(color: Colors.grey),
                  ),
                ],
              ),
            ),
          ],
        ),
        const Divider(height: 32),

        // Block-specific controls
        ...(_buildBlockEditControls(block, theme)),
      ],
    );
  }

  List<Widget> _buildBlockEditControls(WebsiteBlock block, ThemeData theme) {
    switch (block.type) {
      case BlockType.hero:
        return _buildHeroEditControls(block, theme);
      case BlockType.carousel:
        return _buildCarouselEditControls(block, theme);
      case BlockType.products:
        return _buildProductsEditControls(block, theme);
      case BlockType.services:
        return _buildServicesEditControls(block, theme);
      case BlockType.about:
        return _buildAboutEditControls(block, theme);
      default:
        return [
          const Text('Controles en desarrollo...'),
        ];
    }
  }

  List<Widget> _buildHeroEditControls(WebsiteBlock block, ThemeData theme) {
    return [
      _buildTextField(
        label: 'Título',
        value: block.data['title'] ?? '',
        onChanged: (value) {
          block.data['title'] = value;
          setState(() => _markAsChanged());
        },
      ),
      const SizedBox(height: 16),
      _buildTextField(
        label: 'Subtítulo',
        value: block.data['subtitle'] ?? '',
        maxLines: 2,
        onChanged: (value) {
          block.data['subtitle'] = value;
          setState(() => _markAsChanged());
        },
      ),
      const SizedBox(height: 16),
      _buildTextField(
        label: 'Texto del Botón',
        value: block.data['ctaText'] ?? '',
        onChanged: (value) {
          block.data['ctaText'] = value;
          setState(() => _markAsChanged());
        },
      ),
      const SizedBox(height: 16),
      Row(
        children: [
          const Text('Mostrar Overlay'),
          const Spacer(),
          Switch(
            value: block.data['showOverlay'] ?? true,
            onChanged: (value) {
              setState(() {
                block.data['showOverlay'] = value;
                _markAsChanged();
              });
            },
          ),
        ],
      ),
      const SizedBox(height: 16),
      if (block.data['showOverlay'] == true) ...[
        Text(
            'Opacidad del Overlay: ${(block.data['overlayOpacity'] ?? 0.5).toStringAsFixed(1)}'),
        Slider(
          value: block.data['overlayOpacity'] ?? 0.5,
          min: 0.0,
          max: 1.0,
          divisions: 10,
          onChanged: (value) {
            setState(() {
              block.data['overlayOpacity'] = value;
              _markAsChanged();
            });
          },
        ),
        const SizedBox(height: 16),
      ],
      ElevatedButton.icon(
        onPressed: _pickImage,
        icon: const Icon(Icons.image),
        label: const Text('Cambiar Imagen de Fondo'),
      ),
    ];
  }

  List<Widget> _buildCarouselEditControls(WebsiteBlock block, ThemeData theme) {
    final slides = _getCarouselSlides(block);

    double intervalSeconds = 5;
    final rawInterval = block.data['intervalSeconds'];
    if (rawInterval is num) {
      intervalSeconds = rawInterval.toDouble();
    } else if (rawInterval is String) {
      intervalSeconds = double.tryParse(rawInterval) ?? 5;
    }
    intervalSeconds = intervalSeconds.clamp(1, 20);

    final animation = (block.data['animation'] ?? 'slide').toString();
    final autoPlay = (block.data['autoPlay'] ?? true) == true;
    final showIndicators = (block.data['showIndicators'] ?? true) == true;
    final showArrows = (block.data['showArrows'] ?? true) == true;

    return [
      SwitchListTile(
        title: const Text('Reproducción automática'),
        value: autoPlay,
        onChanged: (value) {
          setState(() {
            block.data['autoPlay'] = value;
          });
          _markAsChanged();
        },
      ),
      const SizedBox(height: 8),
      Text('Tiempo entre imágenes: ${intervalSeconds.round()} s'),
      Slider(
        value: intervalSeconds,
        min: 2,
        max: 15,
        divisions: 13,
        label: '${intervalSeconds.round()} s',
        onChanged: (value) {
          setState(() {
            block.data['intervalSeconds'] = value.round();
          });
          _markAsChanged();
        },
      ),
      const SizedBox(height: 16),
      DropdownButtonFormField<String>(
        decoration: const InputDecoration(
          labelText: 'Animación',
          border: OutlineInputBorder(),
        ),
        value: animation,
        items: const [
          DropdownMenuItem(value: 'slide', child: Text('Deslizar')),
          DropdownMenuItem(value: 'fade', child: Text('Desvanecer')),
          DropdownMenuItem(value: 'zoom', child: Text('Zoom')),
        ],
        onChanged: (value) {
          if (value == null) return;
          setState(() {
            block.data['animation'] = value;
          });
          _markAsChanged();
        },
      ),
      const SizedBox(height: 16),
      SwitchListTile(
        title: const Text('Mostrar indicadores'),
        value: showIndicators,
        onChanged: (value) {
          setState(() {
            block.data['showIndicators'] = value;
          });
          _markAsChanged();
        },
      ),
      SwitchListTile(
        title: const Text('Mostrar flechas'),
        value: showArrows,
        onChanged: (value) {
          setState(() {
            block.data['showArrows'] = value;
          });
          _markAsChanged();
        },
      ),
      const Divider(height: 32),
      if (slides.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Text(
            'Aún no hay diapositivas. Agrega una para comenzar.',
            style: TextStyle(color: Colors.grey),
          ),
        ),
      ...slides.asMap().entries.map((entry) {
        final index = entry.key;
        return _buildCarouselSlideCard(block, slides, index, theme);
      }).toList(),
      if (slides.isNotEmpty) const SizedBox(height: 16),
      OutlinedButton.icon(
        onPressed: () {
          setState(() {
            slides.add({
              'title': 'Nueva diapositiva',
              'subtitle': 'Describe tu promoción',
              'ctaText': 'Ver más',
              'ctaLink': '/tienda/productos',
              'imageUrl': null,
              'showOverlay': true,
              'overlayOpacity': 0.55,
            });
            block.data['slides'] = slides;
          });
          _markAsChanged();
        },
        icon: const Icon(Icons.add),
        label: const Text('Añadir diapositiva'),
      ),
    ];
  }

  Widget _buildCarouselSlideCard(
    WebsiteBlock block,
    List<Map<String, dynamic>> slides,
    int index,
    ThemeData theme,
  ) {
    final slide = slides[index];
    final imageUrl = (slide['imageUrl'] ?? '').toString();
    final hasImage = imageUrl.isNotEmpty;
    final showOverlay = (slide['showOverlay'] ?? true) == true;

    double overlayOpacity = 0.55;
    final rawOverlay = slide['overlayOpacity'];
    if (rawOverlay is num) {
      overlayOpacity = rawOverlay.toDouble();
    } else if (rawOverlay is String) {
      overlayOpacity = double.tryParse(rawOverlay) ?? 0.55;
    }
    overlayOpacity = overlayOpacity.clamp(0.0, 1.0);

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'Diapositiva ${index + 1}',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'Mover arriba',
                  icon: const Icon(Icons.arrow_upward),
                  onPressed: index == 0
                      ? null
                      : () {
                          setState(() {
                            final item = slides.removeAt(index);
                            slides.insert(index - 1, item);
                            block.data['slides'] = slides;
                          });
                          _markAsChanged();
                        },
                ),
                IconButton(
                  tooltip: 'Mover abajo',
                  icon: const Icon(Icons.arrow_downward),
                  onPressed: index >= slides.length - 1
                      ? null
                      : () {
                          setState(() {
                            final item = slides.removeAt(index);
                            slides.insert(index + 1, item);
                            block.data['slides'] = slides;
                          });
                          _markAsChanged();
                        },
                ),
                IconButton(
                  tooltip: 'Eliminar',
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                  onPressed: () {
                    setState(() {
                      slides.removeAt(index);
                      block.data['slides'] = slides;
                    });
                    _markAsChanged();
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),
            AspectRatio(
              aspectRatio: 16 / 9,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: hasImage
                    ? Image.network(
                        imageUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return Container(
                            color: theme.colorScheme.surfaceVariant,
                            alignment: Alignment.center,
                            child: const Icon(Icons.broken_image, size: 40),
                          );
                        },
                      )
                    : Container(
                        color: theme.colorScheme.surfaceVariant,
                        alignment: Alignment.center,
                        child: const Icon(Icons.image, size: 48),
                      ),
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => _pickCarouselImage(block, index),
                icon: const Icon(Icons.image_outlined),
                label: const Text('Cambiar imagen'),
              ),
            ),
            const SizedBox(height: 16),
            _buildTextField(
              label: 'Título',
              value: slide['title']?.toString() ?? '',
              onChanged: (value) {
                setState(() {
                  slides[index]['title'] = value;
                  block.data['slides'] = slides;
                });
                _markAsChanged();
              },
            ),
            const SizedBox(height: 12),
            _buildTextField(
              label: 'Subtítulo',
              value: slide['subtitle']?.toString() ?? '',
              maxLines: 2,
              onChanged: (value) {
                setState(() {
                  slides[index]['subtitle'] = value;
                  block.data['slides'] = slides;
                });
                _markAsChanged();
              },
            ),
            const SizedBox(height: 12),
            _buildTextField(
              label: 'Texto del botón',
              value: slide['ctaText']?.toString() ?? '',
              onChanged: (value) {
                setState(() {
                  slides[index]['ctaText'] = value;
                  block.data['slides'] = slides;
                });
                _markAsChanged();
              },
            ),
            const SizedBox(height: 12),
            _buildTextField(
              label: 'Enlace del botón',
              value: slide['ctaLink']?.toString() ?? '/tienda/productos',
              onChanged: (value) {
                setState(() {
                  slides[index]['ctaLink'] = value;
                  block.data['slides'] = slides;
                });
                _markAsChanged();
              },
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Mostrar overlay'),
              value: showOverlay,
              onChanged: (value) {
                setState(() {
                  slides[index]['showOverlay'] = value;
                  block.data['slides'] = slides;
                });
                _markAsChanged();
              },
            ),
            if (showOverlay) ...[
              Text('Opacidad del overlay: ${overlayOpacity.toStringAsFixed(1)}'),
              Slider(
                value: overlayOpacity,
                min: 0,
                max: 1,
                divisions: 10,
                onChanged: (value) {
                  setState(() {
                    slides[index]['overlayOpacity'] = value;
                    block.data['slides'] = slides;
                  });
                  _markAsChanged();
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  List<Map<String, dynamic>> _getCarouselSlides(WebsiteBlock block) {
    final rawSlides = block.data['slides'];
    if (rawSlides is List) {
      return rawSlides
          .whereType<Map>()
          .map((slide) => Map<String, dynamic>.from(slide))
          .toList();
    }
    return [];
  }

  Future<void> _pickCarouselImage(WebsiteBlock block, int index) async {
    final imageUrl = await _pickAndUploadImage(folder: 'website/carousel');
    if (imageUrl == null) {
      return;
    }

    final slides = _getCarouselSlides(block);
    if (index < 0 || index >= slides.length) {
      return;
    }

    setState(() {
      slides[index]['imageUrl'] = imageUrl;
      block.data['slides'] = slides;
      _hasChanges = true;
    });

    if (_autoSaveEnabled) {
      await _saveChanges(showNotification: false);
    }
  }

  List<Widget> _buildProductsEditControls(WebsiteBlock block, ThemeData theme) {
    return [
      _buildTextField(
        label: 'Título de la Sección',
        value: block.data['title'] ?? '',
        onChanged: (value) {
          block.data['title'] = value;
          setState(() => _markAsChanged());
        },
      ),
      const SizedBox(height: 16),
      Text('Productos por Fila: ${block.data['itemsPerRow'] ?? 3}'),
      Slider(
        value: (block.data['itemsPerRow'] ?? 3).toDouble(),
        min: 2,
        max: 4,
        divisions: 2,
        onChanged: (value) {
          setState(() {
            block.data['itemsPerRow'] = value.toInt();
            _markAsChanged();
          });
        },
      ),
      const SizedBox(height: 16),
      DropdownButtonFormField<String>(
        decoration: const InputDecoration(
          labelText: 'Layout',
          border: OutlineInputBorder(),
        ),
        value: block.data['layout'] ?? 'grid',
        items: const [
          DropdownMenuItem(value: 'grid', child: Text('Grilla')),
          DropdownMenuItem(value: 'list', child: Text('Lista')),
          DropdownMenuItem(value: 'carousel', child: Text('Carrusel')),
        ],
        onChanged: (value) {
          setState(() {
            block.data['layout'] = value;
            _markAsChanged();
          });
        },
      ),
    ];
  }

  List<Widget> _buildServicesEditControls(WebsiteBlock block, ThemeData theme) {
    return [
      _buildTextField(
        label: 'Título de la Sección',
        value: block.data['title'] ?? '',
        onChanged: (value) {
          block.data['title'] = value;
          setState(() => _markAsChanged());
        },
      ),
      const SizedBox(height: 16),
      const Text('Servicios:', style: TextStyle(fontWeight: FontWeight.bold)),
      const SizedBox(height: 8),
      const Text('Añadir/editar servicios en desarrollo...',
          style: TextStyle(color: Colors.grey)),
    ];
  }

  List<Widget> _buildAboutEditControls(WebsiteBlock block, ThemeData theme) {
    return [
      _buildTextField(
        label: 'Título',
        value: block.data['title'] ?? '',
        onChanged: (value) {
          block.data['title'] = value;
          setState(() => _markAsChanged());
        },
      ),
      const SizedBox(height: 16),
      _buildTextField(
        label: 'Contenido',
        value: block.data['content'] ?? '',
        maxLines: 5,
        onChanged: (value) {
          block.data['content'] = value;
          setState(() => _markAsChanged());
        },
      ),
      const SizedBox(height: 16),
      DropdownButtonFormField<String>(
        decoration: const InputDecoration(
          labelText: 'Posición de Imagen',
          border: OutlineInputBorder(),
        ),
        value: block.data['imagePosition'] ?? 'right',
        items: const [
          DropdownMenuItem(value: 'left', child: Text('Izquierda')),
          DropdownMenuItem(value: 'right', child: Text('Derecha')),
        ],
        onChanged: (value) {
          setState(() {
            block.data['imagePosition'] = value;
            _markAsChanged();
          });
        },
      ),
      const SizedBox(height: 16),
      ElevatedButton.icon(
        onPressed: _pickImage,
        icon: const Icon(Icons.image),
        label: const Text('Cambiar Imagen'),
      ),
    ];
  }

  Widget _buildTextField({
    required String label,
    required String value,
    required Function(String) onChanged,
    int maxLines = 1,
  }) {
    return TextField(
      controller: TextEditingController(text: value)
        ..selection = TextSelection.collapsed(offset: value.length),
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      maxLines: maxLines,
      onChanged: onChanged,
    );
  }

  // ============================================================================
  // TAB 3: TEMA (Global Theme Settings)
  // ============================================================================

  Widget _buildTemaTab(ThemeData theme) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          '🎨 Configuración Global del Tema',
          style:
              theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 24),

        // Colors section
        Text(
          'Colores',
          style: theme.textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),

        _buildColorPicker(
          label: 'Color Primario',
          color: _primaryColor,
          onColorChanged: (color) {
            setState(() {
              _primaryColor = color;
              _markAsChanged();
            });
          },
        ),
        const SizedBox(height: 12),

        _buildColorPicker(
          label: 'Color Acento',
          color: _accentColor,
          onColorChanged: (color) {
            setState(() {
              _accentColor = color;
              _markAsChanged();
            });
          },
        ),
        const SizedBox(height: 12),

        _buildColorPicker(
          label: 'Color de Fondo',
          color: _backgroundColor,
          onColorChanged: (color) {
            setState(() {
              _backgroundColor = color;
              _markAsChanged();
            });
          },
        ),
        const SizedBox(height: 12),

        _buildColorPicker(
          label: 'Color de Texto',
          color: _textColor,
          onColorChanged: (color) {
            setState(() {
              _textColor = color;
              _markAsChanged();
            });
          },
        ),

        const Divider(height: 32),

        // Typography section
        Text(
          'Tipografía',
          style: theme.textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),

        DropdownButtonFormField<String>(
          decoration: const InputDecoration(
            labelText: 'Fuente de Encabezados',
            border: OutlineInputBorder(),
          ),
          value: _headingFont,
          items: const [
            DropdownMenuItem(value: 'Roboto', child: Text('Roboto')),
            DropdownMenuItem(value: 'Montserrat', child: Text('Montserrat')),
            DropdownMenuItem(value: 'Poppins', child: Text('Poppins')),
            DropdownMenuItem(value: 'Open Sans', child: Text('Open Sans')),
            DropdownMenuItem(value: 'Lato', child: Text('Lato')),
          ],
          onChanged: (value) {
            setState(() {
              _headingFont = value!;
              _markAsChanged();
            });
          },
        ),
        const SizedBox(height: 12),

        DropdownButtonFormField<String>(
          decoration: const InputDecoration(
            labelText: 'Fuente del Cuerpo',
            border: OutlineInputBorder(),
          ),
          value: _bodyFont,
          items: const [
            DropdownMenuItem(value: 'Roboto', child: Text('Roboto')),
            DropdownMenuItem(value: 'Montserrat', child: Text('Montserrat')),
            DropdownMenuItem(value: 'Poppins', child: Text('Poppins')),
            DropdownMenuItem(value: 'Open Sans', child: Text('Open Sans')),
            DropdownMenuItem(value: 'Lato', child: Text('Lato')),
          ],
          onChanged: (value) {
            setState(() {
              _bodyFont = value!;
              _markAsChanged();
            });
          },
        ),
        const SizedBox(height: 16),

        Text('Tamaño de Encabezados: ${_headingSize.toInt()}px'),
        Slider(
          value: _headingSize,
          min: 24,
          max: 72,
          divisions: 24,
          onChanged: (value) {
            setState(() {
              _headingSize = value;
              _markAsChanged();
            });
          },
        ),
        const SizedBox(height: 12),

        Text('Tamaño del Cuerpo: ${_bodySize.toInt()}px'),
        Slider(
          value: _bodySize,
          min: 12,
          max: 24,
          divisions: 12,
          onChanged: (value) {
            setState(() {
              _bodySize = value;
              _markAsChanged();
            });
          },
        ),

        const Divider(height: 32),

        // Spacing section
        Text(
          'Espaciado',
          style: theme.textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),

        Text('Espaciado entre Secciones: ${_sectionSpacing.toInt()}px'),
        Slider(
          value: _sectionSpacing,
          min: 32,
          max: 128,
          divisions: 12,
          onChanged: (value) {
            setState(() {
              _sectionSpacing = value;
              _markAsChanged();
            });
          },
        ),
        const SizedBox(height: 12),

        Text('Padding de Contenedores: ${_containerPadding.toInt()}px'),
        Slider(
          value: _containerPadding,
          min: 16,
          max: 64,
          divisions: 12,
          onChanged: (value) {
            setState(() {
              _containerPadding = value;
              _markAsChanged();
            });
          },
        ),
      ],
    );
  }

  Widget _buildColorPicker({
    required String label,
    required Color color,
    required Function(Color) onColorChanged,
  }) {
    return InkWell(
      onTap: () => _showColorPicker(color, onColorChanged),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Colors.grey),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  Text(
                    '#${color.value.toRadixString(16).substring(2).toUpperCase()}',
                    style: const TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                ],
              ),
            ),
            const Icon(Icons.edit, size: 20),
          ],
        ),
      ),
    );
  }

  // ============================================================================
  // HELPER DIALOGS
  // ============================================================================

  void _showUnsavedChangesDialog() {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('⚠️ Cambios sin Guardar'),
        content: const Text(
            'Tienes cambios sin guardar. ¿Quieres guardarlos antes de salir?'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext); // Close dialog
              // Navigate back appropriately
              if (Navigator.canPop(context)) {
                Navigator.pop(context); // Go back in Navigator stack
              } else {
                context.go('/website'); // Use GoRouter
              }
            },
            child: const Text('Descartar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(dialogContext); // Close dialog
              await _saveChanges();
              if (mounted) {
                // Navigate back appropriately
                if (Navigator.canPop(context)) {
                  Navigator.pop(context); // Go back in Navigator stack
                } else {
                  context.go('/website'); // Use GoRouter
                }
              }
            },
            child: const Text('Guardar y Salir'),
          ),
        ],
      ),
    );
  }
}
