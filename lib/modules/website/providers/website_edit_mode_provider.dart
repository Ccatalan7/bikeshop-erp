import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// Device preview modes for the website editor
enum DevicePreviewMode {
  desktop,
  tablet,
  mobile,
}

/// Provider for website inline edit mode state.
/// Tracks edit mode, selected block, and pending changes.
///
/// Two modes:
/// - Preview mode: Shows the top bar (isPreviewMode = true)
/// - Edit mode: Shows the side panel (isEditMode = true)
class WebsiteEditModeProvider extends ChangeNotifier {
  bool _isPreviewMode = false; // Preview with top bar
  bool _isEditMode = false; // Full edit with side panel
  DevicePreviewMode _devicePreviewMode =
      DevicePreviewMode.desktop; // Persist preview options

  String? _selectedBlockId;
  int _selectionVersion = 0; // Tracks explicit selection events
  bool _hasUnsavedChanges = false;
  bool _hasHeaderChanges = false; // Track header-specific changes
  List<Map<String, dynamic>> _blocks = [];
  Map<String, dynamic> _settings = {};

  // Multi-page editing support (Dec 2025)
  String? _currentPageId; // The page ID being edited (null = home page)
  String? _currentPageSlug; // The page slug for navigation

  // Screenshot capability
  final GlobalKey _screenshotKey = GlobalKey();
  GlobalKey get screenshotKey => _screenshotKey;

  // Pending header settings (to be saved with main save button)
  Map<String, String> _pendingHeaderSettings = {};

  // Pending theme settings for live preview
  // These are applied immediately in the UI but only saved when user clicks "Guardar"
  Map<String, String> _pendingThemeSettings = {};
  bool _hasThemeChanges = false;

  // History for undo/redo
  final List<List<Map<String, dynamic>>> _history = [];
  int _historyIndex = -1;
  final int _maxHistory = 50;

  // Getters
  bool get isPreviewMode => _isPreviewMode;
  bool get isEditMode => _isEditMode;
  bool get isInEditorContext =>
      _isPreviewMode || _isEditMode; // Either preview or edit
  DevicePreviewMode get devicePreviewMode => _devicePreviewMode;
  String? get selectedBlockId => _selectedBlockId;
  int get selectionVersion => _selectionVersion;
  bool get hasUnsavedChanges =>
      _hasUnsavedChanges || _hasHeaderChanges || _hasThemeChanges;
  bool get hasHeaderChanges => _hasHeaderChanges;
  bool get hasThemeChanges => _hasThemeChanges;
  List<Map<String, dynamic>> get blocks => _blocks;
  Map<String, dynamic> get settings => _settings;
  Map<String, String> get pendingHeaderSettings => _pendingHeaderSettings;
  Map<String, String> get pendingThemeSettings => _pendingThemeSettings;
  bool get canUndo => _historyIndex > 0;
  bool get canRedo => _historyIndex < _history.length - 1;

  // Multi-page editing getters
  String? get currentPageId => _currentPageId;
  String? get currentPageSlug => _currentPageSlug;
  bool get isEditingHomePage => _currentPageId == null;

  /// Update the current page context without resetting blocks/settings.
  ///
  /// Useful when the page row is created/resolved at save-time and we want
  /// subsequent saves to target the correct page.
  void updateCurrentPageContext({
    String? pageId,
    String? pageSlug,
  }) {
    _currentPageId = pageId;
    _currentPageSlug = pageSlug;
    notifyListeners();
  }

  /// Mark header as having unsaved changes
  void markHeaderChanged() {
    _hasHeaderChanges = true;
    notifyListeners();
  }

  /// Update pending header settings (will be saved with main save button)
  void updateHeaderSettings(Map<String, String> settings) {
    _pendingHeaderSettings = Map<String, String>.from(settings);
    _hasHeaderChanges = true;
    debugPrint(
        '📝 [EditProvider] Header settings updated: ${settings.keys.join(', ')}');
    notifyListeners();
  }

  /// Clear header changed flag (after save)
  void clearHeaderChanged() {
    _hasHeaderChanges = false;
    _pendingHeaderSettings = {};
    notifyListeners();
  }

  /// Update a single theme setting for live preview
  void updateThemeSetting(String key, String value) {
    _pendingThemeSettings[key] = value;
    _hasThemeChanges = true;
    debugPrint('🎨 [EditProvider] Theme setting updated: $key = $value');
    notifyListeners();
  }

  /// Update multiple theme settings at once
  void updateThemeSettings(Map<String, String> settings) {
    _pendingThemeSettings.addAll(settings);
    _hasThemeChanges = true;
    debugPrint(
        '🎨 [EditProvider] Theme settings updated: ${settings.keys.join(', ')}');
    notifyListeners();
  }

  /// Get effective theme setting (pending value if exists, otherwise from settings)
  String getEffectiveThemeSetting(String key, String defaultValue) {
    // First check pending theme settings (live preview)
    if (_pendingThemeSettings.containsKey(key)) {
      return _pendingThemeSettings[key]!;
    }
    // Fall back to saved settings
    final saved = _settings[key];
    if (saved != null) return saved.toString();
    return defaultValue;
  }

  /// Clear theme changed flag (after save)
  void clearThemeChanges() {
    _hasThemeChanges = false;
    _pendingThemeSettings = {};
    notifyListeners();
  }

  /// Enter preview mode (shows top bar with "Editar" button)
  /// [pageId] - Optional page ID for multi-page editing (null = home page)
  /// [pageSlug] - Optional page slug for navigation
  void enterPreviewMode(
    List<Map<String, dynamic>> blocks,
    Map<String, dynamic> settings, {
    String? pageId,
    String? pageSlug,
  }) {
    _isPreviewMode = true;
    _isEditMode = false;
    _blocks = blocks.map((b) => Map<String, dynamic>.from(b)).toList();
    _settings = Map<String, dynamic>.from(settings);
    _hasUnsavedChanges = false;
    _hasHeaderChanges = false;
    _selectedBlockId = null;
    _currentPageId = pageId;
    _currentPageSlug = pageSlug;
    notifyListeners();
  }

  /// Enter edit mode (shows side panel editor)
  /// [pageId] - Optional page ID for multi-page editing (null = home page)
  /// [pageSlug] - Optional page slug for navigation
  void enterEditMode(
    List<Map<String, dynamic>> blocks,
    Map<String, dynamic> settings, {
    String? pageId,
    String? pageSlug,
  }) {
    _isPreviewMode = false;
    _isEditMode = true;
    _blocks = blocks.map((b) => Map<String, dynamic>.from(b)).toList();
    _settings = Map<String, dynamic>.from(settings);
    _hasUnsavedChanges = false;
    _hasHeaderChanges = false;
    _selectedBlockId = null;
    _currentPageId = pageId;
    _currentPageSlug = pageSlug;

    // Initialize history with current state
    _history.clear();
    _history.add(_blocks.map((b) => Map<String, dynamic>.from(b)).toList());
    _historyIndex = 0;

    debugPrint(
        '✏️ [EditProvider] Entered edit mode for page: ${pageSlug ?? "home"} (id: $pageId)');
    notifyListeners();
  }

  /// Switch from preview to edit mode (keeps blocks)
  void switchToEditMode() {
    _isPreviewMode = false;
    _isEditMode = true;
    notifyListeners();
  }

  /// Switch from edit mode back to preview (after save/discard)
  void switchToPreviewMode() {
    _isEditMode = false;
    _isPreviewMode = true;
    _selectedBlockId = null;
    notifyListeners();
  }

  /// Set device preview mode (desktop, tablet, mobile)
  void setDevicePreviewMode(DevicePreviewMode mode) {
    _devicePreviewMode = mode;
    notifyListeners();
  }

  /// Exit completely (back to normal visitor view)
  void exitEditMode() {
    if (!_isPreviewMode && !_isEditMode) return;

    _isPreviewMode = false;
    _isEditMode = false;
    _selectedBlockId = null;
    _hasUnsavedChanges = false;
    _hasHeaderChanges = false;
    _blocks = [];
    _settings = {};
    _currentPageId = null;
    _currentPageSlug = null;
    notifyListeners();
  }

  /// Update blocks after successful save (refresh with database data)
  void updateBlocksAfterSave(List<Map<String, dynamic>> freshBlocks) {
    _blocks = freshBlocks.map((b) => Map<String, dynamic>.from(b)).toList();
    _hasUnsavedChanges = false;
    notifyListeners();
  }

  /// Select a block for editing
  void selectBlock(String? blockId) {
    _selectedBlockId = blockId;
    _selectionVersion++;
    debugPrint(
        '👉 [EditProvider] Block Selected: $blockId (v$_selectionVersion)');
    notifyListeners();
  }

  /// Update block data without notifying listeners (for real-time drag preview)
  /// Use this during drag operations to avoid rebuilding the entire widget tree
  void updateBlockDataSilent(String blockId, String key, dynamic value) {
    final blockIndex = _blocks.indexWhere((b) => b['id'] == blockId);
    if (blockIndex == -1) return;

    final block = _blocks[blockIndex];
    final blockData = Map<String, dynamic>.from(block['block_data'] ?? {});
    blockData[key] = value;
    _blocks[blockIndex] = {
      ...block,
      'block_data': blockData,
    };
    _hasUnsavedChanges = true;
    // Don't call notifyListeners() - caller is responsible for UI updates
  }

  /// Update block data
  /// [saveHistory] - Set to false for transient updates (like activeElementId changes) to avoid history pollution
  void updateBlockData(String blockId, String key, dynamic value,
      {bool saveHistory = true}) {
    final blockIndex = _blocks.indexWhere((b) => b['id'] == blockId);
    if (blockIndex == -1) {
      debugPrint('⚠️ [EditProvider] updateBlockData: block $blockId not found');
      return;
    }

    final block = _blocks[blockIndex];
    final blockData = Map<String, dynamic>.from(block['block_data'] ?? {});
    blockData[key] = value;
    _blocks[blockIndex] = {
      ...block,
      'block_data': blockData,
    };
    _hasUnsavedChanges = true;
    if (saveHistory) {
      _saveToHistory();
    }
    debugPrint(
        '✅ [EditProvider] updateBlockData: blockId=$blockId, key=$key, hasUnsavedChanges=$_hasUnsavedChanges');
    notifyListeners();
  }

  /// Update multiple block data keys atomically (single notification)
  /// Use this when updating related values that should be saved together
  void updateBlockDataMultiple(String blockId, Map<String, dynamic> updates,
      {bool saveHistory = true}) {
    final blockIndex = _blocks.indexWhere((b) => b['id'] == blockId);
    if (blockIndex == -1) {
      debugPrint(
          '⚠️ [EditProvider] updateBlockDataMultiple: block $blockId not found');
      return;
    }

    final block = _blocks[blockIndex];
    final blockData = Map<String, dynamic>.from(block['block_data'] ?? {});

    // Apply all updates atomically
    for (final entry in updates.entries) {
      blockData[entry.key] = entry.value;
    }

    _blocks[blockIndex] = {
      ...block,
      'block_data': blockData,
    };
    _hasUnsavedChanges = true;
    if (saveHistory) {
      _saveToHistory();
    }
    debugPrint(
        '✅ [EditProvider] updateBlockDataMultiple: blockId=$blockId, keys=${updates.keys.join(", ")}');
    notifyListeners();
  }

  /// Convenience: add a Canvas element to the currently selected Canvas block.
  /// Returns true if an element was added.
  bool addCanvasElementToSelectedCanvas(String elementType) {
    final selected = _selectedBlockId;
    if (selected == null) return false;
    return addCanvasElementToCanvasBlock(selected, elementType);
  }

  /// Add a Canvas element to a specific Canvas block by id.
  /// Returns true if successful.
  bool addCanvasElementToCanvasBlock(String canvasBlockId, String elementType) {
    final blockIndex = _blocks.indexWhere((b) => b['id'] == canvasBlockId);
    if (blockIndex == -1) return false;
    final block = _blocks[blockIndex];
    final blockType = (block['block_type'] ?? block['type'] ?? '').toString();
    if (blockType != 'canvas') return false;

    final data = Map<String, dynamic>.from(block['block_data'] ?? {});
    final rawElements = data['elements'];
    final elements = rawElements is List
        ? rawElements
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList()
        : <Map<String, dynamic>>[];

    final now = DateTime.now().microsecondsSinceEpoch;
    final id = 'el_$now';
    final next = <String, dynamic>{
      'id': id,
      'type': elementType,
      'x': 24.0,
      'y': 24.0,
      'w': switch (elementType) {
        'button' => 220.0,
        'image' => 320.0,
        'product' => 280.0,
        'productsGallery' => 520.0,
        _ => 360.0,
      },
      'h': switch (elementType) {
        'button' => 56.0,
        'image' => 200.0,
        'product' => 320.0,
        'productsGallery' => 360.0,
        _ => 72.0,
      },
      'anim': 'none', // none | fade | fadeUp
    };

    if (elementType == 'button') {
      next.addAll({
        'label': 'Botón',
        'style': 'filled', // filled|outline|text
        'bgColor': '#00A09D',
        'fgColor': '#FFFFFF',
        'radius': 12.0,
        'fontSize': 14.0,
        'letterSpacing': 0.0,
        'uppercase': false,
        'shadow': false,
        'link': '/',
      });
    } else if (elementType == 'image') {
      next.addAll({
        'imageUrl': '',
        'fit': 'cover', // cover|contain
        'radius': 12.0,
      });
    } else if (elementType == 'product') {
      next.addAll({
        'productId': '',
        'showPrice': true,
      });
    } else if (elementType == 'productsGallery') {
      next.addAll({
        'mode': 'latest', // latest|manual
        'productIds': <String>[],
        'maxProducts': 6,
        'layout': 'grid', // grid|carousel
        'columns': 3,
        'cardWidth': 300,
        'showPrice': true,
      });
    } else {
      // text
      next.addAll({
        'text': 'Texto',
        'fontSize': 28.0,
        'fontWeight': 'w700',
        'color': '#111111',
        'align': 'left',
      });
    }

    elements.add(next);
    updateBlockData(canvasBlockId, 'elements', elements);
    // Don't save to history for activeElementId - it's transient
    updateBlockData(canvasBlockId, 'activeElementId', id, saveHistory: false);
    return true;
  }

  /// Save current state to history
  void _saveToHistory() {
    // Remove any future history if we're not at the end
    if (_historyIndex < _history.length - 1) {
      _history.removeRange(_historyIndex + 1, _history.length);
    }

    // Deep copy blocks
    final snapshot = _blocks.map((b) => Map<String, dynamic>.from(b)).toList();
    _history.add(snapshot);
    _historyIndex = _history.length - 1;

    // Limit history size
    if (_history.length > _maxHistory) {
      _history.removeAt(0);
      _historyIndex--;
    }

    debugPrint(
        '💾 [EditProvider] Saved to history: index=$_historyIndex, total=${_history.length}, canUndo=$canUndo, canRedo=$canRedo');
  }

  /// Undo last change
  void undo() {
    if (!canUndo) return;

    _historyIndex--;
    _blocks = _history[_historyIndex]
        .map((b) => Map<String, dynamic>.from(b))
        .toList();
    _hasUnsavedChanges = true;
    debugPrint('⏪ [EditProvider] Undo: index=$_historyIndex');
    notifyListeners();
  }

  /// Redo last undone change
  void redo() {
    if (!canRedo) return;

    _historyIndex++;
    _blocks = _history[_historyIndex]
        .map((b) => Map<String, dynamic>.from(b))
        .toList();
    _hasUnsavedChanges = true;
    debugPrint('⏩ [EditProvider] Redo: index=$_historyIndex');
    notifyListeners();
  }

  /// Get block by ID
  Map<String, dynamic>? getBlock(String blockId) {
    try {
      return _blocks.firstWhere((b) => b['id'] == blockId);
    } catch (_) {
      return null;
    }
  }

  /// Get block data
  Map<String, dynamic> getBlockData(String blockId) {
    final block = getBlock(blockId);
    return Map<String, dynamic>.from(block?['block_data'] ?? {});
  }

  /// Move block up
  void moveBlockUp(String blockId) {
    debugPrint('🔼 [EditProvider] moveBlockUp called for blockId: $blockId');
    final index = _blocks.indexWhere((b) => b['id'] == blockId);
    debugPrint('🔼 [EditProvider] Block index: $index');
    if (index <= 0) {
      debugPrint(
          '🔼 [EditProvider] Cannot move up - already at top or not found');
      return;
    }

    final block = _blocks.removeAt(index);
    _blocks.insert(index - 1, block);

    // Update sort_order for all blocks to match new positions
    _updateSortOrders();

    _hasUnsavedChanges = true;
    debugPrint('🔼 [EditProvider] Moved block from $index to ${index - 1}');
    notifyListeners();
  }

  /// Move block down
  void moveBlockDown(String blockId) {
    debugPrint('🔽 [EditProvider] moveBlockDown called for blockId: $blockId');
    final index = _blocks.indexWhere((b) => b['id'] == blockId);
    debugPrint(
        '🔽 [EditProvider] Block index: $index, total blocks: ${_blocks.length}');
    if (index == -1 || index >= _blocks.length - 1) {
      debugPrint(
          '🔽 [EditProvider] Cannot move down - already at bottom or not found');
      return;
    }

    final block = _blocks.removeAt(index);
    _blocks.insert(index + 1, block);

    // Update sort_order for all blocks to match new positions
    _updateSortOrders();

    _hasUnsavedChanges = true;
    debugPrint('🔽 [EditProvider] Moved block from $index to ${index + 1}');
    notifyListeners();
  }

  /// Reorder blocks via drag-and-drop (Structure panel).
  void reorderBlocks(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= _blocks.length) return;
    if (newIndex < 0) return;
    if (newIndex > _blocks.length) newIndex = _blocks.length;

    // Flutter's ReorderableListView gives newIndex in the "post-removal" space.
    if (newIndex > oldIndex) newIndex -= 1;
    if (oldIndex == newIndex) return;

    final item = _blocks.removeAt(oldIndex);
    _blocks.insert(newIndex, item);

    _updateSortOrders();
    _hasUnsavedChanges = true;
    _saveToHistory();
    notifyListeners();
  }

  /// Update sort_order values to match current list positions
  void _updateSortOrders() {
    for (int i = 0; i < _blocks.length; i++) {
      _blocks[i] = {
        ..._blocks[i],
        'sort_order': i,
        'order_index': i,
      };
    }
  }

  /// Delete block
  void deleteBlock(String blockId) {
    _blocks.removeWhere((b) => b['id'] == blockId);
    if (_selectedBlockId == blockId) {
      _selectedBlockId = null;
    }
    // Update sort_order for remaining blocks
    _updateSortOrders();
    _hasUnsavedChanges = true;
    notifyListeners();
  }

  /// Duplicate block
  void duplicateBlock(String blockId) {
    final index = _blocks.indexWhere((b) => b['id'] == blockId);
    if (index == -1) return;

    final original = _blocks[index];
    final duplicate = Map<String, dynamic>.from(original);
    duplicate['id'] = _uuid.v4(); // Use proper UUID for database compatibility
    duplicate['block_data'] =
        Map<String, dynamic>.from(original['block_data'] ?? {});

    _blocks.insert(index + 1, duplicate);
    _updateSortOrders(); // Update sort_order values after duplicate
    _selectedBlockId = duplicate['id'] as String?;
    _hasUnsavedChanges = true;
    notifyListeners();
    debugPrint(
        '📋 [EditProvider] Duplicated block at index $index with new ID: ${duplicate['id']}');
  }

  /// Toggle block visibility
  void toggleBlockVisibility(String blockId) {
    final blockIndex = _blocks.indexWhere((b) => b['id'] == blockId);
    if (blockIndex == -1) return;

    final block = _blocks[blockIndex];
    _blocks[blockIndex] = {
      ...block,
      'is_visible': !(block['is_visible'] ?? true),
    };
    _hasUnsavedChanges = true;
    notifyListeners();
  }

  /// Add a new block
  void addBlock(String blockType, {int? atIndex}) {
    final newBlock = {
      'id': _uuid.v4(), // Use proper UUID for database compatibility
      'block_type': blockType,
      'block_data': _getDefaultDataForType(blockType),
      'is_visible': true,
      'sort_order': _blocks.length,
    };

    if (atIndex != null && atIndex >= 0 && atIndex <= _blocks.length) {
      _blocks.insert(atIndex, newBlock);
    } else {
      _blocks.add(newBlock);
    }

    // Update sort_order for all blocks
    _updateSortOrders();

    _selectedBlockId = newBlock['id'] as String?;
    _selectionVersion++;
    _hasUnsavedChanges = true;
    notifyListeners();
  }

  /// Get default data for block type
  Map<String, dynamic> _getDefaultDataForType(String blockType) {
    switch (blockType) {
      case 'hero':
        return {
          'title': 'Servicios y Productos de Bicicleta',
          'subtitle': 'Todo lo que necesitas para tu bicicleta',
          'buttonText': 'Ver Productos',
          'buttonLink': '/tienda/productos',
          'backgroundImage': '',
        };
      case 'carousel':
        return {
          'slides': [
            {
              'title': 'Bienvenido a nuestra tienda',
              'subtitle': 'Descubre los mejores productos para tu bicicleta',
              'imageUrl': '',
              'ctaText': 'Ver catálogo',
              'ctaLink': '/tienda/productos',
              'showOverlay': true,
              'overlayOpacity': 0.55,
            },
            {
              'title': 'Servicio técnico certificado',
              'subtitle': 'Agenda tu mantención sin salir de casa',
              'imageUrl': '',
              'ctaText': 'Agendar ahora',
              'ctaLink': '/tienda/servicios',
              'showOverlay': true,
              'overlayOpacity': 0.55,
            },
          ],
          'autoPlay': true,
          'intervalSeconds': 5,
          'showIndicators': true,
          'showArrows': true,
          'animation': 'slide',
        };
      case 'products':
        return {
          'title': 'Productos Destacados',
          'subtitle': 'Los mejores productos para ti',
          'showPrice': true,
          'maxProducts': 8,
        };
      case 'text':
        return {
          'text': 'Haz clic para editar este texto',
          'preset': 'paragraph', // heading | subheading | paragraph | caption
          'maxWidth': 800,
          'formatting': const <String, dynamic>{},
        };
      case 'canvas':
        return {
          'blockHeight': 420.0,
          'heightMode': 'fixed', // fixed | viewport
          'vhPct': 0.7, // viewport height percentage (0.2..1.0)
          'fullBleed': false,
          'backgroundColor': '#FFFFFF',
          'backgroundImageUrl': '',
          'backgroundVideoUrl': '',
          'backgroundYoutubeId': '',
          'overlayEnabled': false,
          'overlayOpacity': 0.35,
          'overlayColor': '#000000',
          'backgroundFit': 'cover', // cover | contain
          'showGrid': true,
          'gridSize': 8.0,
          'snap': true,
          'snapDistance': 6.0,
          'activeElementId': null,
          'elements': [
            {
              'id': 'el_${DateTime.now().microsecondsSinceEpoch}',
              'type': 'text',
              'x': 24.0,
              'y': 24.0,
              'w': 360.0,
              'h': 72.0,
              'text': 'Arrástrame (Canvas)',
              'fontSize': 28.0,
              'fontWeight': 'w700',
              'color': '#111111',
              'align': 'left',
            },
            {
              'id': 'el_${DateTime.now().microsecondsSinceEpoch + 1}',
              'type': 'button',
              'x': 24.0,
              'y': 120.0,
              'w': 220.0,
              'h': 56.0,
              'label': 'Botón',
              'style': 'filled',
              'bgColor': '#00A09D',
              'fgColor': '#FFFFFF',
              'radius': 12.0,
              'link': '/',
            },
          ],
        };
      case 'button':
        return {
          'label': 'Botón',
          'link': '/',
          'style': 'filled', // filled | outline | text
        };
      case 'divider':
        return {
          'thickness': 1.0,
          'color': '#E0E0E0',
          'widthPct': 1.0,
        };
      case 'about':
        return {
          'title': 'Sobre Nosotros',
          'description':
              'Somos una tienda especializada en bicicletas y accesorios. Contamos con años de experiencia brindando productos de calidad y el mejor servicio a nuestros clientes.',
          'image': '',
        };
      case 'services':
        return {
          'title': 'Nuestros Servicios',
          'services': [
            {
              'icon': 'build',
              'title': 'Reparación',
              'description': 'Servicio técnico profesional'
            },
            {
              'icon': 'tune',
              'title': 'Mantención',
              'description': 'Mantención preventiva y correctiva'
            },
            {
              'icon': 'shopping_bag',
              'title': 'Venta',
              'description': 'Bicicletas y accesorios'
            },
          ],
        };
      case 'features':
        return {
          'title': '¿Por qué elegirnos?',
          'features': [
            {
              'icon': 'local_shipping',
              'title': 'Envío Rápido',
              'description': 'Envíos a todo Chile en 24-48 horas'
            },
            {
              'icon': 'verified',
              'title': 'Productos Originales',
              'description': 'Garantía de autenticidad'
            },
            {
              'icon': 'support_agent',
              'title': 'Atención Personalizada',
              'description': 'Asesoramiento experto'
            },
          ],
        };
      case 'testimonials':
        return {
          'title': 'Lo que dicen nuestros clientes',
          'testimonials': [
            {
              'name': 'Cliente Satisfecho',
              'text': 'Excelente servicio y productos de calidad.',
              'rating': 5
            },
          ],
        };
      case 'stats':
        return {
          'title': 'Nuestros Números',
          'stats': [
            {'value': '1000+', 'label': 'Clientes Satisfechos'},
            {'value': '500+', 'label': 'Productos'},
            {'value': '10+', 'label': 'Años de Experiencia'},
          ],
        };
      case 'team':
        return {
          'title': 'Nuestro Equipo',
          'members': [
            {'name': 'Nombre', 'role': 'Cargo', 'image': ''},
          ],
        };
      case 'faq':
        return {
          'title': 'Preguntas Frecuentes',
          'questions': [
            {
              'question': '¿Cuál es el horario de atención?',
              'answer': 'Lunes a Viernes de 9:00 a 18:00'
            },
            {
              'question': '¿Hacen envíos a regiones?',
              'answer': 'Sí, enviamos a todo Chile'
            },
          ],
        };
      case 'pricing':
        return {
          'title': 'Nuestros Planes',
          'plans': [
            {
              'name': 'Básico',
              'price': '9.990',
              'features': ['Feature 1', 'Feature 2']
            },
            {
              'name': 'Pro',
              'price': '19.990',
              'features': ['Feature 1', 'Feature 2', 'Feature 3'],
              'highlighted': true
            },
          ],
        };
      case 'contact':
        return {
          'title': 'Contáctanos',
          'subtitle': 'Estamos aquí para ayudarte',
          'showMap': false,
          'showForm': true,
        };
      case 'cta':
        return {
          'title': '¿Listo para empezar?',
          'description': 'Visítanos o contáctanos para más información',
          'buttonText': 'Contactar',
          'buttonLink': '/tienda/contacto',
        };
      case 'gallery':
        return {
          'title': 'Galería',
          'images': [],
        };
      case 'categoryGrid':
        return {
          'title': 'Explora Nuestras Categorías',
          'subtitle': 'Encuentra lo que buscas',
          'categories': [
            {
              'title': 'Mountain Bike',
              'subtitle': 'Conquista cualquier terreno',
              'imageUrl': '',
              'ctaText': 'Ver colección',
              'ctaLink': '/tienda/productos?categoria=mtb',
              'size': 'large',
            },
            {
              'title': 'Ruta',
              'subtitle': 'Velocidad y rendimiento',
              'imageUrl': '',
              'ctaText': 'Ver colección',
              'ctaLink': '/tienda/productos?categoria=ruta',
              'size': 'large',
            },
            {
              'title': 'Urbano',
              'subtitle': 'Movilidad en la ciudad',
              'imageUrl': '',
              'ctaText': 'Ver gama',
              'ctaLink': '/tienda/productos?categoria=urbano',
              'size': 'medium',
            },
            {
              'title': 'Accesorios',
              'subtitle': 'Todo lo que necesitas',
              'imageUrl': '',
              'ctaText': 'Explorar',
              'ctaLink': '/tienda/productos?categoria=accesorios',
              'size': 'medium',
            },
          ],
        };
      case 'videoBanner':
        return {
          'title': 'Vive la Aventura',
          'subtitle': 'La experiencia de rodar sin límites',
          'imageUrl': '',
          'videoUrl': '',
          'ctaText': 'Descubrir más',
          'ctaLink': '/tienda/productos',
          'showCta': true,
          'overlayOpacity': 0.5,
        };
      case 'partnersBanner':
        return {
          'title': 'Nuestras Ubicaciones',
          'imageUrl': '',
          'items': [
            'Santiago, Chile',
            'Viña del Mar, Chile',
            'Concepción, Chile',
          ],
        };
      case 'brandLogos':
        return {
          'title': 'MARCAS',
          'accentColor': '#E53935',
          'brands': [
            {'name': 'Marca 1', 'imageUrl': '', 'link': ''},
            {'name': 'Marca 2', 'imageUrl': '', 'link': ''},
            {'name': 'Marca 3', 'imageUrl': '', 'link': ''},
          ],
        };
      default:
        return {};
    }
  }

  /// Update settings
  void updateSetting(String key, dynamic value) {
    _settings[key] = value;
    _hasUnsavedChanges = true;
    notifyListeners();
  }

  /// Mark changes as saved
  void markAsSaved() {
    _hasUnsavedChanges = false;
    notifyListeners();
  }
}
