import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// Provider for website inline edit mode state.
/// Tracks edit mode, selected block, and pending changes.
/// 
/// Two modes:
/// - Preview mode: Shows the site with a top "Editar" bar (isPreviewMode = true, isEditMode = false)
/// - Edit mode: Shows the site with the side panel editor (isEditMode = true)
class WebsiteEditModeProvider extends ChangeNotifier {
  bool _isPreviewMode = false; // Preview with top bar
  bool _isEditMode = false;    // Full edit with side panel
  String? _selectedBlockId;
  bool _hasUnsavedChanges = false;
  List<Map<String, dynamic>> _blocks = [];
  Map<String, dynamic> _settings = {};
  
  // Getters
  bool get isPreviewMode => _isPreviewMode;
  bool get isEditMode => _isEditMode;
  bool get isInEditorContext => _isPreviewMode || _isEditMode; // Either preview or edit
  String? get selectedBlockId => _selectedBlockId;
  bool get hasUnsavedChanges => _hasUnsavedChanges;
  List<Map<String, dynamic>> get blocks => _blocks;
  Map<String, dynamic> get settings => _settings;

  /// Enter preview mode (shows top bar with "Editar" button)
  void enterPreviewMode(List<Map<String, dynamic>> blocks, Map<String, dynamic> settings) {
    _isPreviewMode = true;
    _isEditMode = false;
    _blocks = blocks.map((b) => Map<String, dynamic>.from(b)).toList();
    _settings = Map<String, dynamic>.from(settings);
    _hasUnsavedChanges = false;
    _selectedBlockId = null;
    notifyListeners();
  }

  /// Enter edit mode (shows side panel editor)
  void enterEditMode(List<Map<String, dynamic>> blocks, Map<String, dynamic> settings) {
    _isPreviewMode = false;
    _isEditMode = true;
    _blocks = blocks.map((b) => Map<String, dynamic>.from(b)).toList();
    _settings = Map<String, dynamic>.from(settings);
    _hasUnsavedChanges = false;
    _selectedBlockId = null;
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

  /// Exit completely (back to normal visitor view)
  void exitEditMode() {
    _isPreviewMode = false;
    _isEditMode = false;
    _selectedBlockId = null;
    _hasUnsavedChanges = false;
    _blocks = [];
    _settings = {};
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
    notifyListeners();
  }

  /// Update block data
  void updateBlockData(String blockId, String key, dynamic value) {
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
      debugPrint('🔼 [EditProvider] Cannot move up - already at top or not found');
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
    debugPrint('🔽 [EditProvider] Block index: $index, total blocks: ${_blocks.length}');
    if (index == -1 || index >= _blocks.length - 1) {
      debugPrint('🔽 [EditProvider] Cannot move down - already at bottom or not found');
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
    duplicate['id'] = _uuid.v4();  // Use proper UUID for database compatibility
    duplicate['block_data'] = Map<String, dynamic>.from(original['block_data'] ?? {});
    
    _blocks.insert(index + 1, duplicate);
    _updateSortOrders();  // Update sort_order values after duplicate
    _selectedBlockId = duplicate['id'] as String?;
    _hasUnsavedChanges = true;
    notifyListeners();
    debugPrint('📋 [EditProvider] Duplicated block at index $index with new ID: ${duplicate['id']}');
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
      'id': _uuid.v4(),  // Use proper UUID for database compatibility
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
      case 'about':
        return {
          'title': 'Sobre Nosotros',
          'description': 'Somos una tienda especializada en bicicletas y accesorios. Contamos con años de experiencia brindando productos de calidad y el mejor servicio a nuestros clientes.',
          'image': '',
        };
      case 'services':
        return {
          'title': 'Nuestros Servicios',
          'services': [
            {'icon': 'build', 'title': 'Reparación', 'description': 'Servicio técnico profesional'},
            {'icon': 'tune', 'title': 'Mantención', 'description': 'Mantención preventiva y correctiva'},
            {'icon': 'shopping_bag', 'title': 'Venta', 'description': 'Bicicletas y accesorios'},
          ],
        };
      case 'features':
        return {
          'title': '¿Por qué elegirnos?',
          'features': [
            {'icon': 'local_shipping', 'title': 'Envío Rápido', 'description': 'Envíos a todo Chile en 24-48 horas'},
            {'icon': 'verified', 'title': 'Productos Originales', 'description': 'Garantía de autenticidad'},
            {'icon': 'support_agent', 'title': 'Atención Personalizada', 'description': 'Asesoramiento experto'},
          ],
        };
      case 'testimonials':
        return {
          'title': 'Lo que dicen nuestros clientes',
          'testimonials': [
            {'name': 'Cliente Satisfecho', 'text': 'Excelente servicio y productos de calidad.', 'rating': 5},
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
            {'question': '¿Cuál es el horario de atención?', 'answer': 'Lunes a Viernes de 9:00 a 18:00'},
            {'question': '¿Hacen envíos a regiones?', 'answer': 'Sí, enviamos a todo Chile'},
          ],
        };
      case 'pricing':
        return {
          'title': 'Nuestros Planes',
          'plans': [
            {'name': 'Básico', 'price': '9.990', 'features': ['Feature 1', 'Feature 2']},
            {'name': 'Pro', 'price': '19.990', 'features': ['Feature 1', 'Feature 2', 'Feature 3'], 'highlighted': true},
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
