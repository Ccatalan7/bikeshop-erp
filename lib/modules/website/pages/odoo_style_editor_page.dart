import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../../../shared/widgets/main_layout.dart';
import '../../../shared/services/image_service.dart';
import '../../../shared/constants/storage_constants.dart';
import '../../../shared/services/inventory_service.dart';
import '../../../shared/models/product.dart';
import '../services/website_service.dart';
import '../widgets/website_block_renderer.dart';
import '../models/website_models.dart';
import '../models/website_block_registry.dart';
import '../models/website_block_definition.dart';
import '../models/website_block_type.dart';
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

// Block data model
class WebsiteBlock {
  final String id;
  final WebsiteBlockType type;
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
    WebsiteBlockType? type,
    Map<String, dynamic>? data,
    bool? isVisible,
  }) {
    Map<String, dynamic> cloneData(Map<String, dynamic> source) {
      return jsonDecode(jsonEncode(source)) as Map<String, dynamic>;
    }

    return WebsiteBlock(
      id: id ?? this.id,
      type: type ?? this.type,
      data: data != null ? cloneData(data) : cloneData(this.data),
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

  final Uuid _uuid = const Uuid();

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
  List<ThemePreset> _themePresets = [];
  final TextEditingController _presetNameController = TextEditingController();
  bool _isSavingPreset = false;
  final Set<String> _presetActionsInProgress = {};
  late final DateFormat _presetDateFormat = DateFormat('dd/MM HH:mm');
  final Map<String, double> _defaultPreviewWidths = const {
    'mobile': 390,
    'tablet': 960,
    'desktop': 1280,
  };
  final Map<String, double?> _customPreviewWidths = {
    'mobile': null,
    'tablet': null,
    'desktop': null,
  };
  final Map<String, RangeValues> _previewWidthRanges = const {
    'mobile': RangeValues(320, 480),
    'tablet': RangeValues(640, 1280),
    'desktop': RangeValues(960, 1600),
  };
  bool _showSafeAreaGuides = false;

  @override
  void initState() {
    super.initState();
    _loadFromDatabase();
    _loadThemeSettings();
    _startAutoSave();
  }

  static const List<String> _supportedBreakpoints = [
    'desktop',
    'tablet',
    'mobile'
  ];
  static const Map<String, String> _breakpointLabels = {
    'desktop': 'Escritorio',
    'tablet': 'Tablet',
    'mobile': 'Móvil',
  };
  static const Map<String, IconData> _breakpointIcons = {
    'desktop': Icons.desktop_windows_outlined,
    'tablet': Icons.tablet_mac_outlined,
    'mobile': Icons.smartphone_outlined,
  };

  Map<String, bool> _defaultBreakpointVisibility() {
    return {
      for (final breakpoint in _supportedBreakpoints) breakpoint: true,
    };
  }

  bool? _castToBool(dynamic value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      final normalized = value.trim().toLowerCase();
      if (normalized.isEmpty) return null;
      if (normalized == 'true' ||
          normalized == '1' ||
          normalized == 'sí' ||
          normalized == 'si') {
        return true;
      }
      if (normalized == 'false' || normalized == '0' || normalized == 'no') {
        return false;
      }
    }
    return null;
  }

  Map<String, bool> _normalizeVisibilityMap(dynamic raw) {
    final visibility = _defaultBreakpointVisibility();
    dynamic source = raw;

    if (source is String) {
      final trimmed = source.trim();
      if (trimmed.isEmpty) {
        source = null;
      } else {
        try {
          final decoded = jsonDecode(trimmed);
          if (decoded is Map) {
            source = decoded;
          }
        } catch (_) {
          source = null;
        }
      }
    }

    if (source is Map) {
      source.forEach((key, value) {
        final keyString = key.toString();
        if (!visibility.containsKey(keyString)) {
          return;
        }
        final parsed = _castToBool(value);
        if (parsed != null) {
          visibility[keyString] = parsed;
        }
      });
    }

    return visibility;
  }

  Map<String, bool> _ensureVisibilityForBlock(WebsiteBlock block) {
    final normalized = _normalizeVisibilityMap(block.data['visibility']);
    final resolved = Map<String, bool>.from(normalized);
    block.data['visibility'] = resolved;
    return resolved;
  }

  bool _isBlockVisibleOnBreakpoint(WebsiteBlock block, String breakpoint) {
    final visibility = _ensureVisibilityForBlock(block);
    return visibility[breakpoint] ?? true;
  }

  bool _isBlockVisibleForPreview(WebsiteBlock block) {
    if (!block.isVisible) {
      return false;
    }
    return _isBlockVisibleOnBreakpoint(block, _previewMode);
  }

  String _breakpointLabel(String breakpoint) {
    return _breakpointLabels[breakpoint] ?? breakpoint;
  }

  IconData _breakpointIcon(String breakpoint) {
    return _breakpointIcons[breakpoint] ?? Icons.devices_other;
  }

  void _updateBreakpointVisibility(
    WebsiteBlock block,
    String breakpoint,
    bool enabled,
  ) {
    if (!_supportedBreakpoints.contains(breakpoint)) {
      return;
    }

    setState(() {
      final current = Map<String, bool>.from(_ensureVisibilityForBlock(block));
      current[breakpoint] = enabled;
      block.data['visibility'] = current;
      _markAsChanged();
    });
  }

  Future<void> _loadThemeSettings() async {
    try {
      final service = context.read<WebsiteService>();
      await service.loadSettings();
      final primary = service.getSetting('theme_primary_color');
      final accent = service.getSetting('theme_accent_color');
      final background = service.getSetting('theme_background_color');
      final text = service.getSetting('theme_text_color');
      final headingFont = service.getSetting('theme_heading_font');
      final bodyFont = service.getSetting('theme_body_font');
      final headingSize = service.getSetting('theme_heading_size');
      final bodySize = service.getSetting('theme_body_size');
      final sectionSpacing = service.getSetting('theme_section_spacing');
      final containerPadding = service.getSetting('theme_container_padding');

      final parsedPrimary = _tryParseColor(primary);
      final parsedAccent = _tryParseColor(accent);
      final parsedBackground = _tryParseColor(background);
      final parsedText = _tryParseColor(text);
      final parsedHeadingSize = double.tryParse(headingSize);
      final parsedBodySize = double.tryParse(bodySize);
      final parsedSectionSpacing = double.tryParse(sectionSpacing);
      final parsedContainerPadding = double.tryParse(containerPadding);
      final presets = List<ThemePreset>.from(service.themePresets)
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

      if (!mounted) return;
      setState(() {
        if (parsedPrimary != null) {
          _primaryColor = parsedPrimary;
        }
        if (parsedAccent != null) {
          _accentColor = parsedAccent;
        }
        if (parsedBackground != null) {
          _backgroundColor = parsedBackground;
        }
        if (parsedText != null) {
          _textColor = parsedText;
        }
        if (headingFont.isNotEmpty) {
          _headingFont = headingFont;
        }
        if (bodyFont.isNotEmpty) {
          _bodyFont = bodyFont;
        }
        if (parsedHeadingSize != null) {
          _headingSize = parsedHeadingSize.clamp(24.0, 72.0).toDouble();
        }
        if (parsedBodySize != null) {
          _bodySize = parsedBodySize.clamp(12.0, 24.0).toDouble();
        }
        if (parsedSectionSpacing != null) {
          _sectionSpacing = parsedSectionSpacing.clamp(32.0, 128.0).toDouble();
        }
        if (parsedContainerPadding != null) {
          _containerPadding =
              parsedContainerPadding.clamp(16.0, 64.0).toDouble();
        }
        _themePresets = presets;
      });
    } catch (e) {
      debugPrint('[OdooEditor] Failed to load theme settings: $e');
    }
  }

  Future<void> _loadFromDatabase() async {
    try {
      final websiteService = context.read<WebsiteService>();
      final inventoryService = context.read<InventoryService>();

      await WebsiteBlockRegistry.ensureInitialized();

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
          final typeRaw = (blockData['block_type'] ?? 'hero').toString();
          final dataRaw =
              Map<String, dynamic>.from(blockData['block_data'] ?? {});
          final block = WebsiteBlock(
            id: blockData['id']?.toString() ?? _uuid.v4(),
            type: _parseBlockType(typeRaw),
            data: dataRaw,
            isVisible: blockData['is_visible'] ?? true,
          );
          _ensureVisibilityForBlock(block);
          return block;
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

  WebsiteBlockType _parseBlockType(String typeString) {
    return parseWebsiteBlockType(typeString);
  }

  Map<String, dynamic> _cloneBlockData(Map<String, dynamic> data) {
    return jsonDecode(jsonEncode(data)) as Map<String, dynamic>;
  }

  void _initializeDefaultBlocks() {
    final defaultTypes = [
      WebsiteBlockType.hero,
      WebsiteBlockType.products,
      WebsiteBlockType.services,
      WebsiteBlockType.about,
    ];

    _blocks = defaultTypes.map((type) {
      final definition = WebsiteBlockRegistry.definitionFor(type);
      final block = WebsiteBlock(
        id: _uuid.v4(),
        type: type,
        data: _cloneBlockData(definition.defaultData),
      );
      _ensureVisibilityForBlock(block);
      return block;
    }).toList();

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

  void _updateBlockData(
    WebsiteBlock block,
    String key,
    dynamic value,
  ) {
    setState(() {
      if (value == null) {
        block.data.remove(key);
      } else {
        block.data[key] = value;
      }
      if (key == 'buttonText') {
        block.data['ctaText'] = value;
      } else if (key == 'ctaText' && value == null) {
        block.data.remove('buttonText');
      }
    });
    _markAsChanged();
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

      await websiteService.updateThemeSettings(
        primaryColor: _primaryColor.toARGB32(),
        accentColor: _accentColor.toARGB32(),
        backgroundColor: _backgroundColor.toARGB32(),
        textColor: _textColor.toARGB32(),
        headingFont: _headingFont,
        bodyFont: _bodyFont,
        headingSize: _headingSize,
        bodySize: _bodySize,
        sectionSpacing: _sectionSpacing,
        containerPadding: _containerPadding,
      );

      if (!mounted) {
        return;
      }

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

  void _addBlock(WebsiteBlockType type) {
    final newBlock = _createBlockTemplate(type);

    setState(() {
      final insertIndex = _selectedBlockId != null
          ? _blocks.indexWhere((b) => b.id == _selectedBlockId) + 1
          : _blocks.length;
      final boundedIndex = insertIndex.clamp(0, _blocks.length);
      _blocks.insert(boundedIndex, newBlock);
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

  WebsiteBlock _createBlockTemplate(WebsiteBlockType type) {
    final definition = WebsiteBlockRegistry.definitionFor(type);
    final block = WebsiteBlock(
      id: _uuid.v4(),
      type: type,
      data: _cloneBlockData(definition.defaultData),
    );
    _ensureVisibilityForBlock(block);
    return block;
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
      id: _uuid.v4(),
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

  void _setBlockVisibility(
    String blockId,
    bool visible, {
    bool showFeedback = true,
  }) {
    final blockIndex = _blocks.indexWhere((b) => b.id == blockId);
    if (blockIndex == -1) {
      return;
    }

    if (_blocks[blockIndex].isVisible == visible) {
      return;
    }

    setState(() {
      _blocks[blockIndex].isVisible = visible;
      _markAsChanged();
    });

    if (!mounted || !showFeedback) {
      return;
    }

    final action = visible ? 'mostrado' : 'ocultado';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('✓ Bloque $action'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _toggleBlockVisibility(String blockId) {
    final blockIndex = _blocks.indexWhere((b) => b.id == blockId);
    if (blockIndex == -1) {
      return;
    }

    final shouldShow = !_blocks[blockIndex].isVisible;
    _setBlockVisibility(blockId, shouldShow);
  }

  String _getBlockTypeName(WebsiteBlockType type) {
    return WebsiteBlockRegistry.definitionFor(type).title;
  }

  IconData _getBlockTypeIcon(WebsiteBlockType type) {
    return type.icon;
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

  Future<String?> _pickAndUploadImage(
      {String folder = 'website/banners'}) async {
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

      if (!mounted) {
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

      if (!mounted) {
        return null;
      }

      ScaffoldMessenger.of(context).hideCurrentSnackBar();

      if (imageUrl == null) {
        if (!mounted) {
          return null;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('❌ No se pudo obtener la URL de la imagen'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 4),
          ),
        );
        return null;
      }

      if (!mounted) {
        return imageUrl;
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
      if (!mounted) {
        return null;
      }
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

    if (!mounted) {
      return;
    }

    final blockIndex = _blocks.indexWhere((b) => b.id == _selectedBlockId);
    if (blockIndex == -1) {
      return;
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _blocks[blockIndex].data['imageUrl'] = imageUrl;
      _hasChanges = true;
    });

    if (_autoSaveEnabled && mounted) {
      await _saveChanges(showNotification: false);
    }
  }

  @override
  void dispose() {
    _autoSaveEnabled = false;
    _autoSaveTimer?.cancel();
    _presetNameController.dispose();
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
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
                backgroundColor: WidgetStateProperty.resolveWith((states) {
                  if (states.contains(WidgetState.selected)) {
                    return Colors.blue;
                  }
                  return Colors.transparent;
                }),
                foregroundColor: WidgetStateProperty.all(Colors.white),
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

          const SizedBox(width: 12),

          Tooltip(
            message: 'Opciones de vista',
            child: IconButton(
              icon: const Icon(Icons.tune, color: Colors.white, size: 20),
              onPressed: _openPreviewOptions,
            ),
          ),
        ],
      ),
    );
  }

  double _resolvePreviewWidth(String mode, double maxWidth) {
    final defaultWidth = _defaultPreviewWidths[mode] ?? maxWidth;
    final customWidth = _customPreviewWidths[mode];
    final range = _previewWidthRanges[mode] ?? const RangeValues(320, 1600);
    final minWidth = range.start;
    final maxAllowed = math.max(minWidth, math.min(range.end, maxWidth));
    final desired = (customWidth ?? defaultWidth).clamp(minWidth, maxAllowed);
    return desired;
  }

  RangeValues _effectiveRangeForMode(String mode, double maxWidth) {
    final base = _previewWidthRanges[mode] ?? const RangeValues(320, 1600);
    final maxAllowed = math.max(base.start, math.min(base.end, maxWidth));
    return RangeValues(base.start, maxAllowed);
  }

  Future<void> _openPreviewOptions() async {
    if (!mounted) return;
    final mode = _previewMode;
    final mediaWidth = MediaQuery.sizeOf(context).width;
    final maxWidth = math.max(320.0, mediaWidth - 96);
    var range = _effectiveRangeForMode(mode, maxWidth);
    var localWidth =
        (_customPreviewWidths[mode] ?? _defaultPreviewWidths[mode] ?? range.end)
            .clamp(range.start, range.end);
    var localShowGuides = _showSafeAreaGuides;
    final defaultWidth = _defaultPreviewWidths[mode] ?? range.end;

    final applied = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text('Vista ${_breakpointLabel(mode)}'),
              content: SizedBox(
                width: 360,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Ancho de lienzo: ${localWidth.round()} px'),
                    Slider(
                      value: localWidth,
                      min: range.start,
                      max: range.end,
                      divisions:
                          (range.end - range.start).clamp(10, 80).round(),
                      onChanged: (value) {
                        setDialogState(() {
                          localWidth = value;
                        });
                      },
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: () {
                          setDialogState(() {
                            localWidth =
                                defaultWidth.clamp(range.start, range.end);
                          });
                        },
                        icon: const Icon(Icons.restart_alt_outlined),
                        label: const Text('Restaurar por defecto'),
                      ),
                    ),
                    const Divider(),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Mostrar guías de safe-area'),
                      subtitle: const Text(
                        'Visualiza las zonas seguras para contenido crítico.',
                      ),
                      value: localShowGuides,
                      onChanged: (value) {
                        setDialogState(() {
                          localShowGuides = value;
                        });
                      },
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () {
                        Navigator.of(dialogContext).pop(false);
                      },
                      child: const Text('Cancelar'),
                    ),
                  ],
                ),
              ),
              actions: [
                FilledButton(
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  child: const Text('Aplicar'),
                ),
              ],
            );
          },
        );
      },
    );

    if (applied == true && mounted) {
      setState(() {
        final defaultWidth = _defaultPreviewWidths[mode] ?? range.end;
        final normalizedWidth = localWidth.clamp(range.start, range.end);
        _customPreviewWidths[mode] =
            (normalizedWidth - defaultWidth).abs() < 0.5
                ? null
                : normalizedWidth;
        _showSafeAreaGuides = localShowGuides;
      });
    }
  }

  Widget _buildSafeAreaOverlay(String mode) {
    final EdgeInsets safeInsets;
    switch (mode) {
      case 'mobile':
        safeInsets = const EdgeInsets.fromLTRB(16, 48, 16, 34);
        break;
      case 'tablet':
        safeInsets = const EdgeInsets.fromLTRB(24, 48, 24, 32);
        break;
      default:
        safeInsets = const EdgeInsets.fromLTRB(32, 64, 32, 48);
        break;
    }

  final highlight = Colors.tealAccent.withValues(alpha: 0.85);

    return Positioned.fill(
      child: IgnorePointer(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: DecoratedBox(
            decoration: BoxDecoration(
        border: Border.all(
          color: highlight.withValues(alpha: 0.25), width: 2),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Padding(
              padding: safeInsets,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(color: highlight, width: 2),
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildResponsivePreview(ThemeData theme) {
    final mediaSize = MediaQuery.sizeOf(context);
    final maxWidth = math.max(320.0, mediaSize.width - 96);
    final previewWidth = _resolvePreviewWidth(_previewMode, maxWidth);
    final borderRadius =
        BorderRadius.circular(_previewMode != 'desktop' ? 16 : 12);
    final previewLabel =
        '${previewWidth.round()} px · ${_breakpointLabel(_previewMode)}';

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Expanded(
          child: Center(
            child: Transform.scale(
              scale: _previewZoom,
              child: Container(
                width: previewWidth,
                margin: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _backgroundColor,
                  borderRadius: borderRadius,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.12),
                      blurRadius: 24,
                      spreadRadius: 2,
                      offset: const Offset(0, 12),
                    ),
                  ],
                  border: Border.all(
                    color: Colors.black.withValues(alpha: 0.05),
                  ),
                ),
                child: ClipRRect(
                  borderRadius: borderRadius,
                  child: Stack(
                    children: [
                      _buildClickablePreview(context),
                      if (_showSafeAreaGuides)
                        _buildSafeAreaOverlay(_previewMode),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        DecoratedBox(
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: theme.colorScheme.outlineVariant),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 12,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              previewLabel,
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _buildClickablePreview(BuildContext context) {
    return ReorderableListView.builder(
      buildDefaultDragHandles: false,
      itemCount: _blocks.length,
      onReorder: (oldIndex, newIndex) {
        setState(() {
          if (newIndex > oldIndex) {
            newIndex--;
          }
          final block = _blocks.removeAt(oldIndex);
          _blocks.insert(newIndex, block);
          _markAsChanged();
        });
      },
      itemBuilder: (context, index) {
        final block = _blocks[index];
        final isSelected = block.id == _selectedBlockId;

        return GestureDetector(
          key: ValueKey(block.id),
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
                          color: Colors.blue.withValues(alpha: 0.3),
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
                              color: Colors.black.withValues(alpha: 0.2),
                              blurRadius: 8,
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Drag handle
                            ReorderableDragStartListener(
                              index: index,
                              child: const IconButton(
                                icon: Icon(Icons.drag_indicator,
                                    color: Colors.white, size: 16),
                                onPressed: null,
                                tooltip: 'Arrastrar para reordenar',
                              ),
                            ),

                            // Visibility toggle
                            IconButton(
                              icon: Icon(
                                block.isVisible
                                    ? Icons.visibility
                                    : Icons.visibility_off,
                                color: Colors.white,
                                size: 16,
                              ),
                              onPressed: () => _toggleBlockVisibility(block.id),
                              tooltip: block.isVisible
                                  ? 'Ocultar bloque'
                                  : 'Mostrar bloque',
                            ),

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
      },
    );
  }

  Widget _buildHiddenBlockPlaceholder({
    required IconData icon,
    required String title,
    required String description,
  }) {
    final theme = Theme.of(context);
    final foreground = theme.colorScheme.onSurfaceVariant;

    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: foreground),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleSmall?.copyWith(
                color: foreground,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              description,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: foreground.withValues(alpha: 0.75),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBlockPreview(WebsiteBlock block) {
    final baseTheme = Theme.of(context);
    final themedText = baseTheme.textTheme.apply(
      bodyColor: _textColor,
      displayColor: _textColor,
    );

    final themedData = baseTheme.copyWith(textTheme: themedText);
    final horizontalPadding = _containerPadding.clamp(0.0, 200.0).toDouble();
    final verticalPadding = (_sectionSpacing / 2).clamp(0.0, 200.0).toDouble();

    Widget content;

    // Show placeholder for hidden blocks in editor
    if (!block.isVisible) {
      content = _buildHiddenBlockPlaceholder(
        icon: Icons.visibility_off,
        title: 'Bloque oculto: ${_getBlockTypeName(block.type)}',
        description: 'Este bloque no se mostrará en el sitio público.',
      );
    } else if (!_isBlockVisibleForPreview(block)) {
      final label = _breakpointLabel(_previewMode);
      content = _buildHiddenBlockPlaceholder(
        icon: Icons.visibility_off_outlined,
        title: 'Oculto en vista $label',
        description:
            'Este bloque permanece disponible en otras vistas. Activa ${label.toLowerCase()} desde el panel derecho para mostrarlo aquí.',
      );
    } else {
      final blockType = block.type.name;
      final data = Map<String, dynamic>.from(block.data);
      final websiteService = context.read<WebsiteService>();
      final inventoryService = context.read<InventoryService>();

      final previewFeaturedProducts = block.type == WebsiteBlockType.products
          ? _resolveEditorFeaturedProducts(
              websiteService.featuredProducts,
              inventoryService.products,
            )
          : null;

      content = WebsiteBlockRenderer.build(
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

    return Padding(
      padding: EdgeInsets.fromLTRB(
        horizontalPadding,
        verticalPadding,
        horizontalPadding,
        verticalPadding,
      ),
      child: Theme(
        data: themedData,
        child: content,
      ),
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
    final sortedEntries = entries.where((entry) => entry.active).toList()
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
        ? theme.colorScheme.primaryContainer.withValues(alpha: 0.3)
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
    final definitions = WebsiteBlockRegistry.all();
    final byCategory = <String, List<WebsiteBlockDefinition>>{};
    for (final definition in definitions) {
      final category = definition.category;
      byCategory.putIfAbsent(category, () => []).add(definition);
    }

    final categories = byCategory.keys.toList()..sort();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Bloques Disponibles',
          style:
              theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        for (final category in categories) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              category,
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
      ...byCategory[category]!
        .map((definition) => _buildBlockDefinitionCard(definition, theme)),
          const SizedBox(height: 24),
        ],
      ],
    );
  }

  Widget _buildBlockDefinitionCard(
    WebsiteBlockDefinition definition,
    ThemeData theme,
  ) {
    final tagChips = definition.tags
        .map(
          (tag) => Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            margin: const EdgeInsets.only(right: 6, top: 6),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              tag,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
          ),
        )
        .toList();

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: theme.colorScheme.primaryContainer,
                  child: Icon(
                    _getBlockTypeIcon(definition.type),
                    color: theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        definition.title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        definition.description,
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                ElevatedButton(
                  onPressed: () => _addBlock(definition.type),
                  child: const Text('Añadir'),
                ),
              ],
            ),
            if (definition.previewBadge != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Chip(
                  label: Text(definition.previewBadge!),
                  backgroundColor: theme.colorScheme.secondaryContainer,
                  labelStyle: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSecondaryContainer,
                  ),
                ),
              ),
            if (tagChips.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Wrap(children: tagChips),
              ),
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Row(
                children: [
                  if (!definition.supportsResponsive)
                    Tooltip(
                      message: 'No admite overrides responsivos aún',
                      child: Icon(
                        Icons.devices_other_outlined,
                        color: theme.colorScheme.error,
                        size: 18,
                      ),
                    ),
                  if (!definition.supportsResponsive) const SizedBox(width: 8),
                  Text(
                    'v${definition.version}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
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
            const Icon(Icons.touch_app, size: 64, color: Colors.grey),
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

        _buildResponsiveVisibilityControls(block, theme),
        const Divider(height: 32),

        // Block-specific controls
        ...(_buildBlockEditControls(block, theme)),
      ],
    );
  }

  Widget _buildResponsiveVisibilityControls(
    WebsiteBlock block,
    ThemeData theme,
  ) {
    final visibility = _ensureVisibilityForBlock(block);
    final isBlockVisible = block.isVisible;
    final isHiddenInCurrentView =
        isBlockVisible && !_isBlockVisibleOnBreakpoint(block, _previewMode);

    Widget buildBanner({
      required IconData icon,
      required String message,
      required Color background,
      required Color foreground,
    }) {
      return Container(
        width: double.infinity,
        margin: const EdgeInsets.only(top: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(icon, color: foreground, size: 18),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: foreground,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      );
    }

    final chips = _supportedBreakpoints.map((breakpoint) {
      final label = _breakpointLabel(breakpoint) +
          (breakpoint == _previewMode ? ' · Vista actual' : '');
      final isEnabled = visibility[breakpoint] ?? true;
      final iconColor = !isBlockVisible
          ? theme.disabledColor
          : isEnabled
              ? theme.colorScheme.primary
              : theme.colorScheme.onSurfaceVariant;

      return Tooltip(
        message: isEnabled
            ? 'Visible en ${_breakpointLabel(breakpoint)}'
            : 'Oculto en ${_breakpointLabel(breakpoint)}',
        child: FilterChip(
          avatar: Icon(
            _breakpointIcon(breakpoint),
            size: 18,
            color: iconColor,
          ),
          label: Text(label),
          selected: isEnabled,
          showCheckmark: isBlockVisible,
          checkmarkColor: theme.colorScheme.primary,
          onSelected: isBlockVisible
              ? (selected) => _updateBreakpointVisibility(
                    block,
                    breakpoint,
                    selected,
                  )
              : null,
          backgroundColor: theme.colorScheme.surfaceContainerHigh,
      selectedColor:
        theme.colorScheme.primary.withValues(alpha: 0.18),
          disabledColor: theme.colorScheme.surfaceContainerHighest,
          labelStyle: theme.textTheme.bodyMedium?.copyWith(
            color: isBlockVisible
                ? theme.colorScheme.onSurface
                : theme.disabledColor,
            fontWeight:
                breakpoint == _previewMode ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
      );
    }).toList();

    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
    side: BorderSide(
      color: theme.dividerColor.withValues(alpha: 0.5)),
      ),
      elevation: 0,
      color: theme.colorScheme.surfaceContainerLowest,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.devices_other_outlined,
                    color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Visibilidad por dispositivo',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Controla en qué vistas aparece este bloque. Usa el selector superior para previsualizar cada breakpoint.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('Mostrar bloque en el sitio'),
              subtitle: Text(
                'Desactiva para ocultarlo en todas las vistas.',
                style: theme.textTheme.bodySmall,
              ),
              value: isBlockVisible,
              onChanged: (value) => _setBlockVisibility(
                block.id,
                value,
                showFeedback: false,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: chips,
            ),
            if (!isBlockVisible)
              buildBanner(
                icon: Icons.visibility_off,
                message:
                    'Este bloque está oculto globalmente. Actívalo para ajustar la visibilidad por dispositivo.',
                background: theme.colorScheme.errorContainer,
                foreground: theme.colorScheme.onErrorContainer,
              )
            else if (isHiddenInCurrentView)
              buildBanner(
                icon: Icons.visibility_off_outlined,
                message:
                    'Oculto en vista ${_breakpointLabel(_previewMode)}. Activa el chip correspondiente para mostrarlo.',
                background: theme.colorScheme.secondaryContainer,
                foreground: theme.colorScheme.onSecondaryContainer,
              ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildBlockEditControls(WebsiteBlock block, ThemeData theme) {
    final definition = WebsiteBlockRegistry.definitionFor(block.type);
    final schemaControls = _buildSchemaDrivenControls(block, definition, theme);
    if (schemaControls.isNotEmpty) {
      return schemaControls;
    }

    switch (block.type) {
      case WebsiteBlockType.carousel:
        return _buildCarouselEditControls(block, theme);
      case WebsiteBlockType.products:
        return _buildProductsEditControls(block, theme);
      case WebsiteBlockType.services:
        return _buildServicesEditControls(block, theme);
      case WebsiteBlockType.about:
        return _buildAboutEditControls(block, theme);
      default:
        return [
          const Text('Controles en desarrollo...'),
        ];
    }
  }

  List<Widget> _buildSchemaDrivenControls(
    WebsiteBlock block,
    WebsiteBlockDefinition definition,
    ThemeData theme,
  ) {
    if (definition.fields.isEmpty) {
      return const [];
    }

    final fieldMap = {
      for (final field in definition.fields) field.key: field,
    };

    final sections = definition.controlSections.isNotEmpty
        ? definition.controlSections
        : [
            WebsiteBlockControlSection(
              id: 'general',
              label: 'Contenido',
              fieldKeys: definition.fields.map((f) => f.key).toList(),
            ),
          ];

    final widgets = <Widget>[];
    for (final section in sections) {
      final sectionFields = section.fieldKeys
          .map((key) => fieldMap[key])
          .whereType<WebsiteBlockFieldSchema>()
          .toList();

      if (sectionFields.isEmpty) {
        continue;
      }

      widgets.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            section.label,
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
        ),
      );

      if (section.description != null && section.description!.isNotEmpty) {
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              section.description!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        );
      }

      for (final field in sectionFields) {
        widgets.addAll(
          _buildFieldControls(block, definition, field, theme),
        );
        widgets.add(const SizedBox(height: 16));
      }

      widgets.add(const Divider(height: 32));
    }

    if (widgets.isNotEmpty) {
      widgets.removeLast();
    }

    return widgets;
  }

  List<Widget> _buildFieldControls(
    WebsiteBlock block,
    WebsiteBlockDefinition definition,
    WebsiteBlockFieldSchema field,
    ThemeData theme,
  ) {
    final currentValue = block.data[field.key] ?? field.defaultValue;

    if (field.key == 'overlayOpacity' && block.data['showOverlay'] == false) {
      return [
        Text(
          'Activa el overlay para ajustar la opacidad',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ];
    }

    switch (field.type) {
      case WebsiteBlockFieldType.text:
      case WebsiteBlockFieldType.richtext:
        return [
          _buildSchemaTextField(
            label: field.label,
            value: currentValue?.toString() ?? '',
            maxLines: field.type == WebsiteBlockFieldType.richtext ? 4 : 1,
            onChanged: (value) => _updateBlockData(block, field.key, value),
          ),
        ];
      case WebsiteBlockFieldType.textarea:
        return [
          _buildSchemaTextField(
            label: field.label,
            value: currentValue?.toString() ?? '',
            maxLines: 5,
            onChanged: (value) => _updateBlockData(block, field.key, value),
          ),
        ];
      case WebsiteBlockFieldType.number:
        return [
          _buildNumberField(
            block: block,
            field: field,
            value: currentValue,
            theme: theme,
          ),
        ];
      case WebsiteBlockFieldType.toggle:
        final value =
            currentValue is bool ? currentValue : currentValue == 'true';
        return [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(field.label),
            value: value,
            onChanged: (newValue) =>
                _updateBlockData(block, field.key, newValue),
          ),
        ];
      case WebsiteBlockFieldType.select:
        final options = field.options;
        final value = currentValue?.toString();
        return [
          DropdownButtonFormField<String>(
            decoration: InputDecoration(
              labelText: field.label,
              border: const OutlineInputBorder(),
            ),
      initialValue:
        options.any((option) => option.value == value) ? value : null,
            items: options
                .map(
                  (option) => DropdownMenuItem<String>(
                    value: option.value,
                    child: Text(option.label),
                  ),
                )
                .toList(),
            onChanged: (selected) {
              if (selected == null) return;
              _updateBlockData(block, field.key, selected);
            },
          ),
        ];
      case WebsiteBlockFieldType.color:
        return [
          _buildColorField(
            block: block,
            field: field,
            value: currentValue?.toString(),
            theme: theme,
          ),
        ];
      case WebsiteBlockFieldType.image:
        return [
          _buildImageField(
            block: block,
            field: field,
            value: currentValue?.toString(),
            theme: theme,
          ),
        ];
      case WebsiteBlockFieldType.chips:
        return [
          _buildChipsField(
            block: block,
            field: field,
            value: currentValue,
            theme: theme,
          ),
        ];
      case WebsiteBlockFieldType.repeater:
        return [
          _buildRepeaterField(
            block: block,
            field: field,
            theme: theme,
          ),
        ];
    }
  }

  Widget _buildRepeaterField({
    required WebsiteBlock block,
    required WebsiteBlockFieldSchema field,
    required ThemeData theme,
  }) {
    final itemFields = field.itemFields;
    if (itemFields.isEmpty) {
      return const Text(
          'Configura `itemFields` en el esquema para editar esta lista.');
    }

    final items = _ensureListOfMaps(block.data[field.key]);
    final itemLabel = field.itemLabel ?? 'Elemento';
    final minItems = field.minItems ?? 0;
    final maxItems = field.maxItems;
    final canAddMore = maxItems == null || items.length < maxItems;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (items.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              'No hay ${itemLabel.toLowerCase()}s aún.',
              style: theme.textTheme.bodySmall,
            ),
          ),
        ...items.asMap().entries.map(
              (entry) => _buildRepeaterItemCard(
                block: block,
                listKey: field.key,
                items: items,
                index: entry.key,
                itemLabel: itemLabel,
                itemFields: itemFields,
                theme: theme,
                minItems: minItems,
              ),
            ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: canAddMore
              ? () {
                  final newItem = _buildDefaultRepeaterItem(itemFields);
                  setState(() {
                    items.add(newItem);
                    block.data[field.key] = items;
                  });
                  _markAsChanged();
                }
              : null,
          icon: const Icon(Icons.add),
          label: Text(canAddMore
              ? 'Añadir ${itemLabel.toLowerCase()}'
              : 'Límite alcanzado'),
        ),
      ],
    );
  }

  Widget _buildRepeaterItemCard({
    required WebsiteBlock block,
    required String listKey,
    required List<Map<String, dynamic>> items,
    required int index,
    required String itemLabel,
    required List<WebsiteBlockFieldSchema> itemFields,
    required ThemeData theme,
    required int minItems,
  }) {
    final total = items.length;
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
                  '$itemLabel ${index + 1}',
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
                            final moved = items.removeAt(index);
                            items.insert(index - 1, moved);
                            block.data[listKey] = items;
                          });
                          _markAsChanged();
                        },
                ),
                IconButton(
                  tooltip: 'Mover abajo',
                  icon: const Icon(Icons.arrow_downward),
                  onPressed: index >= total - 1
                      ? null
                      : () {
                          setState(() {
                            final moved = items.removeAt(index);
                            items.insert(index + 1, moved);
                            block.data[listKey] = items;
                          });
                          _markAsChanged();
                        },
                ),
                IconButton(
                  tooltip: 'Eliminar',
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                  onPressed: total <= minItems
                      ? null
                      : () {
                          setState(() {
                            items.removeAt(index);
                            block.data[listKey] = items;
                          });
                          _markAsChanged();
                        },
                ),
              ],
            ),
            const SizedBox(height: 12),
            ..._buildNestedFieldControls(
              block: block,
              listKey: listKey,
              items: items,
              index: index,
              itemFields: itemFields,
              theme: theme,
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildNestedFieldControls({
    required WebsiteBlock block,
    required String listKey,
    required List<Map<String, dynamic>> items,
    required int index,
    required List<WebsiteBlockFieldSchema> itemFields,
    required ThemeData theme,
  }) {
    final item = items[index];
    final widgets = <Widget>[];

    for (final field in itemFields) {
      final value = item[field.key];
      switch (field.type) {
        case WebsiteBlockFieldType.text:
        case WebsiteBlockFieldType.richtext:
          widgets.add(
            _buildSchemaTextField(
              label: field.label,
              value: value?.toString() ?? '',
              maxLines: field.type == WebsiteBlockFieldType.richtext ? 4 : 1,
              onChanged: (newValue) => _updateRepeaterItem(
                block: block,
                listKey: listKey,
                items: items,
                index: index,
                fieldKey: field.key,
                value: newValue,
              ),
            ),
          );
          break;
        case WebsiteBlockFieldType.textarea:
          widgets.add(
            _buildSchemaTextField(
              label: field.label,
              value: value?.toString() ?? '',
              maxLines: 5,
              onChanged: (newValue) => _updateRepeaterItem(
                block: block,
                listKey: listKey,
                items: items,
                index: index,
                fieldKey: field.key,
                value: newValue,
              ),
            ),
          );
          break;
        case WebsiteBlockFieldType.select:
          widgets.add(
            DropdownButtonFormField<String>(
              decoration: InputDecoration(
                labelText: field.label,
                border: const OutlineInputBorder(),
              ),
              initialValue: _resolveSelectValue(field, value?.toString()),
              items: field.options
                  .map(
                    (option) => DropdownMenuItem<String>(
                      value: option.value,
                      child: Text(option.label),
                    ),
                  )
                  .toList(),
              onChanged: (newValue) {
                if (newValue == null) return;
                _updateRepeaterItem(
                  block: block,
                  listKey: listKey,
                  items: items,
                  index: index,
                  fieldKey: field.key,
                  value: newValue,
                );
              },
            ),
          );
          break;
        case WebsiteBlockFieldType.number:
          widgets.add(
            _buildNestedNumberField(
              block: block,
              listKey: listKey,
              items: items,
              index: index,
              field: field,
              theme: theme,
            ),
          );
          break;
        case WebsiteBlockFieldType.toggle:
        case WebsiteBlockFieldType.color:
        case WebsiteBlockFieldType.repeater:
          widgets.add(
            Text(
              'El campo "${field.label}" aún no soporta edición dentro de listas.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          );
          break;
        case WebsiteBlockFieldType.image:
          widgets.add(
            _buildNestedImageField(
              block: block,
              listKey: listKey,
              items: items,
              index: index,
              field: field,
              theme: theme,
            ),
          );
          break;
        case WebsiteBlockFieldType.chips:
          widgets.add(
            _buildNestedChipsField(
              block: block,
              listKey: listKey,
              items: items,
              index: index,
              field: field,
              theme: theme,
            ),
          );
          break;
      }

      widgets.add(const SizedBox(height: 12));
    }

    if (widgets.isNotEmpty) {
      widgets.removeLast();
    }

    return widgets;
  }

  String? _resolveSelectValue(
    WebsiteBlockFieldSchema field,
    String? currentValue,
  ) {
    if (field.options.isEmpty) {
      return null;
    }

    if (currentValue == null) {
      return field.options.first.value;
    }

    final hasValue =
        field.options.any((option) => option.value == currentValue);
    if (hasValue) {
      return currentValue;
    }

    return field.options.first.value;
  }

  List<Map<String, dynamic>> _ensureListOfMaps(dynamic raw) {
    if (raw is List) {
      return raw
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
    }
    return <Map<String, dynamic>>[];
  }

  List<String> _ensureStringList(dynamic raw) {
    if (raw is List) {
      return raw
          .where((item) => item != null)
          .map((item) => item.toString())
          .toList();
    }
    if (raw is String && raw.isNotEmpty) {
      return [raw];
    }
    return <String>[];
  }

  Map<String, dynamic> _buildDefaultRepeaterItem(
    List<WebsiteBlockFieldSchema> fields,
  ) {
    final map = <String, dynamic>{};
    for (final field in fields) {
      if (field.defaultValue != null) {
        map[field.key] = field.defaultValue;
        continue;
      }

      switch (field.type) {
        case WebsiteBlockFieldType.toggle:
          map[field.key] = false;
          break;
        case WebsiteBlockFieldType.number:
          map[field.key] = field.min ?? 0;
          break;
        case WebsiteBlockFieldType.select:
          if (field.options.isNotEmpty) {
            map[field.key] = field.options.first.value;
          }
          break;
        case WebsiteBlockFieldType.color:
          map[field.key] = '#000000';
          break;
        case WebsiteBlockFieldType.image:
          map[field.key] = null;
          break;
        case WebsiteBlockFieldType.text:
        case WebsiteBlockFieldType.textarea:
        case WebsiteBlockFieldType.richtext:
          map[field.key] = '';
          break;
        case WebsiteBlockFieldType.chips:
          map[field.key] = <String>[];
          break;
        case WebsiteBlockFieldType.repeater:
          map[field.key] = '';
          break;
      }
    }
    return map;
  }

  void _updateRepeaterItem({
    required WebsiteBlock block,
    required String listKey,
    required List<Map<String, dynamic>> items,
    required int index,
    required String fieldKey,
    required dynamic value,
  }) {
    setState(() {
      if (value == null) {
        items[index].remove(fieldKey);
      } else {
        items[index][fieldKey] = value;
      }
      block.data[listKey] = items;
    });
    _markAsChanged();
  }

  Widget _buildChipsField({
    required WebsiteBlock block,
    required WebsiteBlockFieldSchema field,
    required dynamic value,
    required ThemeData theme,
  }) {
    final chips = _ensureStringList(value);
    final minItems = field.minItems ?? 0;
    final maxItems = field.maxItems;
    String pendingValue = '';

    void addChip(
        String rawValue, void Function(void Function()) setLocalState) {
      final trimmed = rawValue.trim();
      if (trimmed.isEmpty) {
        return;
      }
      if (maxItems != null && chips.length >= maxItems) {
        return;
      }
      final updated = List<String>.from(chips)..add(trimmed);
      _updateBlockData(block, field.key, updated);
      setLocalState(() {
        chips
          ..clear()
          ..addAll(updated);
        pendingValue = '';
      });
    }

    void removeChip(
        int chipIndex, void Function(void Function()) setLocalState) {
      if (chips.length <= minItems ||
          chipIndex < 0 ||
          chipIndex >= chips.length) {
        return;
      }
      final updated = List<String>.from(chips)..removeAt(chipIndex);
      _updateBlockData(block, field.key, updated);
      setLocalState(() {
        chips
          ..clear()
          ..addAll(updated);
      });
    }

    return StatefulBuilder(
      builder: (context, setLocalState) {
        final canAddMore = maxItems == null || chips.length < maxItems;
        final controller = TextEditingController(text: pendingValue)
          ..selection = TextSelection.collapsed(offset: pendingValue.length);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InputDecorator(
              decoration: InputDecoration(
                labelText: field.label,
                helperText: field.helpText,
                border: const OutlineInputBorder(),
              ),
              child: chips.isEmpty
                  ? Text(
                      'Agrega elementos con el campo inferior.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    )
                  : Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (var i = 0; i < chips.length; i++)
                          InputChip(
                            label: Text(chips[i]),
                            onDeleted: chips.length <= minItems
                                ? null
                                : () => removeChip(i, setLocalState),
                          ),
                      ],
                    ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              decoration: InputDecoration(
                labelText: 'Nuevo elemento',
                hintText: 'Escribe y presiona Enter para agregar',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  tooltip: 'Agregar',
                  icon: const Icon(Icons.add),
                  onPressed: canAddMore && pendingValue.trim().isNotEmpty
                      ? () => addChip(pendingValue, setLocalState)
                      : null,
                ),
              ),
              onChanged: (text) => setLocalState(() {
                pendingValue = text;
              }),
              onSubmitted: (text) => addChip(text, setLocalState),
              enabled: canAddMore,
            ),
            if (!canAddMore)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Has alcanzado el máximo de elementos ($maxItems).',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildNestedChipsField({
    required WebsiteBlock block,
    required String listKey,
    required List<Map<String, dynamic>> items,
    required int index,
    required WebsiteBlockFieldSchema field,
    required ThemeData theme,
  }) {
    final chips = _ensureStringList(items[index][field.key]);
    final minItems = field.minItems ?? 0;
    final maxItems = field.maxItems;
    String pendingValue = '';

    void updateChips(
        List<String> updated, void Function(void Function()) setLocalState) {
      _updateRepeaterItem(
        block: block,
        listKey: listKey,
        items: items,
        index: index,
        fieldKey: field.key,
        value: updated,
      );
      setLocalState(() {
        chips
          ..clear()
          ..addAll(updated);
        pendingValue = '';
      });
    }

    return StatefulBuilder(
      builder: (context, setLocalState) {
        final canAddMore = maxItems == null || chips.length < maxItems;
        final controller = TextEditingController(text: pendingValue)
          ..selection = TextSelection.collapsed(offset: pendingValue.length);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InputDecorator(
              decoration: InputDecoration(
                labelText: field.label,
                helperText: field.helpText,
                border: const OutlineInputBorder(),
              ),
              child: chips.isEmpty
                  ? Text(
                      'Agrega elementos con el campo inferior.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    )
                  : Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (var i = 0; i < chips.length; i++)
                          InputChip(
                            label: Text(chips[i]),
                            onDeleted: chips.length <= minItems
                                ? null
                                : () {
                                    final updated = List<String>.from(chips)
                                      ..removeAt(i);
                                    updateChips(updated, setLocalState);
                                  },
                          ),
                      ],
                    ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              decoration: InputDecoration(
                labelText: 'Nuevo elemento',
                hintText: 'Escribe y presiona Enter para agregar',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  tooltip: 'Agregar',
                  icon: const Icon(Icons.add),
                  onPressed: canAddMore && pendingValue.trim().isNotEmpty
                      ? () {
                          final updated = List<String>.from(chips)
                            ..add(pendingValue.trim());
                          updateChips(updated, setLocalState);
                        }
                      : null,
                ),
              ),
              onChanged: (text) => setLocalState(() {
                pendingValue = text;
              }),
              onSubmitted: (text) {
                final trimmed = text.trim();
                if (trimmed.isEmpty || !canAddMore) {
                  return;
                }
                final updated = List<String>.from(chips)..add(trimmed);
                updateChips(updated, setLocalState);
              },
              enabled: canAddMore,
            ),
            if (!canAddMore)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Has alcanzado el máximo de elementos ($maxItems).',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildNestedImageField({
    required WebsiteBlock block,
    required String listKey,
    required List<Map<String, dynamic>> items,
    required int index,
    required WebsiteBlockFieldSchema field,
    required ThemeData theme,
  }) {
    final imageUrl = items[index][field.key]?.toString();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          field.label,
          style: theme.textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        if (imageUrl != null && imageUrl.isNotEmpty) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.network(
              imageUrl,
              height: 120,
              width: double.infinity,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => Container(
                height: 120,
                color: theme.colorScheme.surfaceContainerHighest,
                child: Center(
                  child: Icon(
                    Icons.broken_image,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final newUrl =
                        await _pickAndUploadImage(folder: 'website/gallery');
                    if (newUrl != null) {
                      _updateRepeaterItem(
                        block: block,
                        listKey: listKey,
                        items: items,
                        index: index,
                        fieldKey: field.key,
                        value: newUrl,
                      );
                    }
                  },
                  icon: const Icon(Icons.image),
                  label: const Text('Cambiar'),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: () {
                  _updateRepeaterItem(
                    block: block,
                    listKey: listKey,
                    items: items,
                    index: index,
                    fieldKey: field.key,
                    value: null,
                  );
                },
                icon: const Icon(Icons.delete_outline),
                label: const Text('Eliminar'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: theme.colorScheme.error,
                ),
              ),
            ],
          ),
        ] else ...[
          OutlinedButton.icon(
            onPressed: () async {
              final newUrl =
                  await _pickAndUploadImage(folder: 'website/gallery');
              if (newUrl != null) {
                _updateRepeaterItem(
                  block: block,
                  listKey: listKey,
                  items: items,
                  index: index,
                  fieldKey: field.key,
                  value: newUrl,
                );
              }
            },
            icon: const Icon(Icons.add_photo_alternate),
            label: const Text('Seleccionar imagen'),
          ),
        ],
      ],
    );
  }

  Widget _buildNestedNumberField({
    required WebsiteBlock block,
    required String listKey,
    required List<Map<String, dynamic>> items,
    required int index,
    required WebsiteBlockFieldSchema field,
    required ThemeData theme,
  }) {
    final min = field.min?.toDouble();
    final max = field.max?.toDouble();
    final step = field.step?.toDouble();
    final rawValue = items[index][field.key];

    double value = _parseNumericValue(rawValue) ??
        (field.defaultValue is num
            ? (field.defaultValue as num).toDouble()
            : (min ?? 0));

    if (min != null) {
      value = math.max(value, min);
    }
    if (max != null) {
      value = math.min(value, max);
    }

    if (min != null && max != null) {
      final sliderValue = value.clamp(min, max);
      final label = _formatNumberLabel(sliderValue, step);
      int? divisions;
      if (step != null && step > 0) {
        final rawDivisions = ((max - min) / step).round();
        if (rawDivisions > 0) {
          divisions = rawDivisions;
        }
      }

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${field.label}: $label'),
          Slider(
            value: sliderValue,
            min: min,
            max: max,
            divisions: divisions,
            label: label,
            onChanged: (newValue) {
              final normalised = _normaliseNumericValue(newValue, step: step);
              _updateRepeaterItem(
                block: block,
                listKey: listKey,
                items: items,
                index: index,
                fieldKey: field.key,
                value: normalised,
              );
            },
          ),
        ],
      );
    }

    final displayValue = _formatNumberLabel(value, step);
    final controller = TextEditingController(text: displayValue)
      ..selection = TextSelection.collapsed(offset: displayValue.length);

    return TextField(
      controller: controller,
      decoration: InputDecoration(
        labelText: field.label,
        border: const OutlineInputBorder(),
      ),
      keyboardType: TextInputType.number,
      onChanged: (newValue) {
        final parsed = _parseNumericValue(newValue);
        if (parsed == null) {
          return;
        }
        final normalised = _normaliseNumericValue(parsed, step: step);
        _updateRepeaterItem(
          block: block,
          listKey: listKey,
          items: items,
          index: index,
          fieldKey: field.key,
          value: normalised,
        );
      },
    );
  }

  Widget _buildSchemaTextField({
    required String label,
    required String value,
    required ValueChanged<String> onChanged,
    int maxLines = 1,
  }) {
    final controller = TextEditingController(text: value)
      ..selection = TextSelection.collapsed(offset: value.length);

    return TextField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      maxLines: maxLines,
      onChanged: onChanged,
    );
  }

  Widget _buildNumberField({
    required WebsiteBlock block,
    required WebsiteBlockFieldSchema field,
    required dynamic value,
    required ThemeData theme,
  }) {
    final min = field.min?.toDouble();
    final max = field.max?.toDouble();
    final step = field.step?.toDouble();
    final parsedValue = _parseNumericValue(value) ?? 0;

    if (min != null && max != null) {
      final clamped = parsedValue.clamp(min, max);
      final label = _formatNumberLabel(clamped, step);
      int? divisions;
      if (step != null && step > 0) {
        divisions = ((max - min) / step).round();
        if (divisions <= 0) {
          divisions = null;
        }
      }

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${field.label}: $label'),
          Slider(
            value: clamped,
            min: min,
            max: max,
            divisions: divisions,
            label: label,
            onChanged: (newValue) {
              final normalised = _normaliseNumericValue(newValue, step: step);
              _updateBlockData(block, field.key, normalised);
            },
          ),
        ],
      );
    }

    final displayValue = _formatNumberLabel(parsedValue, step);
    final controller = TextEditingController(text: displayValue)
      ..selection = TextSelection.collapsed(offset: displayValue.length);

    return TextField(
      controller: controller,
      decoration: InputDecoration(
        labelText: field.label,
        border: const OutlineInputBorder(),
      ),
      keyboardType: TextInputType.number,
      onChanged: (newValue) {
        final parsed = _parseNumericValue(newValue);
        if (parsed != null) {
          final normalised = _normaliseNumericValue(parsed, step: step);
          _updateBlockData(block, field.key, normalised);
        }
      },
    );
  }

  Widget _buildColorField({
    required WebsiteBlock block,
    required WebsiteBlockFieldSchema field,
    required String? value,
    required ThemeData theme,
  }) {
    final parsedColor = value != null ? _tryParseColor(value) : null;
    final color = parsedColor ?? theme.colorScheme.primary;
    final displayValue = value ?? _colorToHex(color);

    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(field.label),
      subtitle: Text(displayValue),
      trailing: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: theme.dividerColor),
        ),
      ),
      onTap: () => _showColorPicker(
        color,
        (selected) => _updateBlockData(block, field.key, _colorToHex(selected)),
      ),
    );
  }

  Widget _buildImageField({
    required WebsiteBlock block,
    required WebsiteBlockFieldSchema field,
    required String? value,
    required ThemeData theme,
  }) {
    final hasImage = value != null && value.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(field.label, style: theme.textTheme.bodyMedium),
        const SizedBox(height: 8),
        Container(
          height: 160,
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: theme.dividerColor),
          ),
          child: hasImage
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.network(
                    value,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => Center(
                      child: Icon(Icons.broken_image,
                          color: theme.colorScheme.error),
                    ),
                  ),
                )
              : Center(
                  child: Icon(Icons.image_outlined,
                      color: theme.colorScheme.onSurfaceVariant),
                ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            ElevatedButton.icon(
              onPressed: () async {
                final imageUrl = await _pickAndUploadImage(
                  folder: 'website/${block.type.name}',
                );
                if (imageUrl != null) {
                  _updateBlockData(block, field.key, imageUrl);
                }
              },
              icon: const Icon(Icons.image),
              label: Text(hasImage ? 'Cambiar imagen' : 'Seleccionar imagen'),
            ),
            const SizedBox(width: 12),
            if (hasImage)
              TextButton(
                onPressed: () => _updateBlockData(block, field.key, null),
                child: const Text('Quitar'),
              ),
          ],
        ),
      ],
    );
  }

  double? _parseNumericValue(dynamic value) {
    if (value is num) {
      return value.toDouble();
    }
    if (value is String) {
      return double.tryParse(value.replaceAll(',', '.'));
    }
    return null;
  }

  num _normaliseNumericValue(double value, {double? step}) {
    if (step == null) {
      return value % 1 == 0
          ? value.round()
          : double.parse(value.toStringAsFixed(2));
    }

    final decimals = _resolveDecimalPlaces(step);
    if (decimals <= 0) {
      return value.round();
    }

    final factor = math.pow(10, decimals) as double;
    return (value * factor).round() / factor;
  }

  String _formatNumberLabel(double value, double? step) {
    if (step == null) {
      return value % 1 == 0
          ? value.round().toString()
          : value.toStringAsFixed(2);
    }

    final decimals = _resolveDecimalPlaces(step);
    if (decimals <= 0) {
      return value.round().toString();
    }

    return value.toStringAsFixed(decimals);
  }

  int _resolveDecimalPlaces(double? step) {
    if (step == null || step >= 1) {
      return 0;
    }

    final stepString = step.toString();
    if (!stepString.contains('.')) {
      return 0;
    }

    final parts = stepString.split('.');
    if (parts.length < 2) {
      return 0;
    }

    var decimals = parts.last.length;
    if (decimals == 0) {
      decimals = 1;
    }
    if (decimals > 4) {
      decimals = 4;
    }
    return decimals;
  }

  String _colorToHex(Color color) {
    int toChannel(double component) {
      final scaled = (component * 255.0).round();
      if (scaled < 0) return 0;
      if (scaled > 255) return 255;
      return scaled;
    }

    final red = toChannel(color.r).toRadixString(16).padLeft(2, '0');
    final green = toChannel(color.g).toRadixString(16).padLeft(2, '0');
    final blue = toChannel(color.b).toRadixString(16).padLeft(2, '0');
    return '#$red$green$blue'.toUpperCase();
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
        initialValue: animation,
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
      }),
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
                            color: theme.colorScheme.surfaceContainerHighest,
                            alignment: Alignment.center,
                            child: const Icon(Icons.broken_image, size: 40),
                          );
                        },
                      )
                    : Container(
                        color: theme.colorScheme.surfaceContainerHighest,
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
              Text(
                  'Opacidad del overlay: ${overlayOpacity.toStringAsFixed(1)}'),
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
        initialValue: block.data['layout'] ?? 'grid',
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
        initialValue: block.data['imagePosition'] ?? 'right',
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

        _buildThemePresetSection(theme),
        const Divider(height: 32),

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
          initialValue: _headingFont,
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
          initialValue: _bodyFont,
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

  Widget _buildThemePresetSection(ThemeData theme) {
    final helperStyle = theme.textTheme.bodySmall?.copyWith(
  color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.7),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Presets de Tema',
          style: theme.textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Text(
          'Guarda combinaciones de colores, tipografías y espaciados para reutilizarlas en futuros lanzamientos.',
          style: helperStyle,
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _presetNameController,
                decoration: const InputDecoration(
                  labelText: 'Nombre del preset',
                  hintText: 'Ej. Campaña de primavera',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 12),
            FilledButton.icon(
              onPressed: _isSavingPreset ? null : _handleSavePreset,
              icon: _isSavingPreset
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_alt),
              label: Text(_isSavingPreset ? 'Guardando...' : 'Guardar preset'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (_themePresets.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest
          .withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              'Todavía no tienes presets guardados. Configura el tema y presiona "Guardar preset" para construir tu biblioteca reutilizable.',
              style: helperStyle,
            ),
          )
        else
          Column(
            children: _themePresets
                .map((preset) => _buildThemePresetTile(preset, theme))
                .toList(),
          ),
      ],
    );
  }

  Widget _buildThemePresetTile(ThemePreset preset, ThemeData theme) {
    final bool isActive = _isPresetActive(preset);
    final bool isDeleting = _presetActionsInProgress.contains(preset.id);

    final Color borderColor = isActive
        ? theme.colorScheme.secondary
  : theme.dividerColor.withValues(alpha: 0.5);

    final Color backgroundColor = isActive
  ? theme.colorScheme.secondaryContainer.withValues(alpha: 0.6)
        : theme.colorScheme.surface;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        leading: _buildPresetColorPreview(preset),
        title: Row(
          children: [
            Expanded(
              child: Text(
                preset.name,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (isActive)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: theme.colorScheme.secondary,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  'Activo',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSecondary,
                  ),
                ),
              ),
          ],
        ),
        subtitle: Text(
          'Actualizado ${_formatPresetDate(preset.updatedAt)}',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.65),
          ),
        ),
        trailing: Wrap(
          spacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            TextButton.icon(
              onPressed: () => _handleApplyPreset(preset),
              icon: const Icon(Icons.play_arrow),
              label: const Text('Aplicar'),
            ),
            if (isDeleting)
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              IconButton(
                tooltip: 'Eliminar preset',
                onPressed: () => _handleDeletePreset(preset),
                icon: const Icon(Icons.delete_outline),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPresetColorPreview(ThemePreset preset) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.black12),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(preset.primaryColor),
            Color(preset.accentColor),
          ],
        ),
      ),
    );
  }

  Future<void> _handleSavePreset() async {
    final name = _presetNameController.text.trim();

    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ingresa un nombre para guardar el preset.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() => _isSavingPreset = true);

    final service = context.read<WebsiteService>();
    ThemePreset? existing;

    for (final preset in _themePresets) {
      if (preset.name.toLowerCase() == name.toLowerCase()) {
        existing = preset;
        break;
      }
    }

    final now = DateTime.now().toUtc();

    final ThemePreset presetToSave = (existing != null)
        ? existing.copyWith(
            primaryColor: _primaryColor.toARGB32(),
            accentColor: _accentColor.toARGB32(),
            backgroundColor: _backgroundColor.toARGB32(),
            textColor: _textColor.toARGB32(),
            headingFont: _headingFont,
            bodyFont: _bodyFont,
            headingSize: _headingSize,
            bodySize: _bodySize,
            sectionSpacing: _sectionSpacing,
            containerPadding: _containerPadding,
            updatedAt: now,
          )
        : ThemePreset(
            id: _uuid.v4(),
            name: name,
            description: null,
            primaryColor: _primaryColor.toARGB32(),
            accentColor: _accentColor.toARGB32(),
            backgroundColor: _backgroundColor.toARGB32(),
            textColor: _textColor.toARGB32(),
            headingFont: _headingFont,
            bodyFont: _bodyFont,
            headingSize: _headingSize,
            bodySize: _bodySize,
            sectionSpacing: _sectionSpacing,
            containerPadding: _containerPadding,
            createdAt: now,
            updatedAt: now,
          );

    try {
      await service.saveThemePreset(presetToSave);
      if (!mounted) return;

      _presetNameController.clear();
      FocusScope.of(context).unfocus();
      final updatedPresets = List<ThemePreset>.from(service.themePresets)
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      setState(() {
        _themePresets = updatedPresets;
      });

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(existing != null
                ? 'Preset actualizado exitosamente.'
                : 'Preset guardado exitosamente.'),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 3),
          ),
        );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('Error al guardar preset: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
    } finally {
      if (mounted) {
        setState(() => _isSavingPreset = false);
      }
    }
  }

  void _handleApplyPreset(ThemePreset preset) {
    FocusScope.of(context).unfocus();

    setState(() {
      _primaryColor = Color(preset.primaryColor);
      _accentColor = Color(preset.accentColor);
      _backgroundColor = Color(preset.backgroundColor);
      _textColor = Color(preset.textColor);
      _headingFont = preset.headingFont;
      _bodyFont = preset.bodyFont;
      _headingSize = preset.headingSize.clamp(24.0, 72.0).toDouble();
      _bodySize = preset.bodySize.clamp(12.0, 24.0).toDouble();
      _sectionSpacing = preset.sectionSpacing.clamp(32.0, 128.0).toDouble();
      _containerPadding = preset.containerPadding.clamp(16.0, 64.0).toDouble();
    });

    _markAsChanged();

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('Preset aplicado. Guarda los cambios para publicarlo.'),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 3),
        ),
      );
  }

  Future<void> _handleDeletePreset(ThemePreset preset) async {
    FocusScope.of(context).unfocus();

    final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Eliminar preset'),
            content: Text(
              '¿Eliminar el preset "${preset.name}"? Esta acción no se puede deshacer.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('Eliminar'),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirmed || !mounted) {
      return;
    }

    setState(() {
      _presetActionsInProgress.add(preset.id);
    });

    final service = context.read<WebsiteService>();

    try {
      await service.deleteThemePreset(preset.id);
      if (!mounted) return;

      final updatedPresets = List<ThemePreset>.from(service.themePresets)
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      setState(() {
        _themePresets = updatedPresets;
      });
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('Preset "${preset.name}" eliminado.'),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 3),
          ),
        );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('Error al eliminar preset: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
    } finally {
      if (mounted) {
        setState(() {
          _presetActionsInProgress.remove(preset.id);
        });
      }
    }
  }

  bool _isPresetActive(ThemePreset preset) {
    const double tolerance = 0.5;

  return preset.primaryColor == _primaryColor.toARGB32() &&
    preset.accentColor == _accentColor.toARGB32() &&
    preset.backgroundColor == _backgroundColor.toARGB32() &&
    preset.textColor == _textColor.toARGB32() &&
        preset.headingFont == _headingFont &&
        preset.bodyFont == _bodyFont &&
        (_headingSize - preset.headingSize).abs() <= tolerance &&
        (_bodySize - preset.bodySize).abs() <= tolerance &&
        (_sectionSpacing - preset.sectionSpacing).abs() <= tolerance &&
        (_containerPadding - preset.containerPadding).abs() <= tolerance;
  }

  String _formatPresetDate(DateTime date) {
    return _presetDateFormat.format(date.toLocal());
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
                    '#${color.toARGB32().toRadixString(16).substring(2).toUpperCase()}',
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
