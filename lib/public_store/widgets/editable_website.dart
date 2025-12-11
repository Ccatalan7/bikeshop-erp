import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../modules/website/models/website_block_type.dart';
import '../../modules/website/models/website_block_registry.dart';
import '../../modules/website/services/website_service.dart';
import '../../modules/website/widgets/website_block_renderer.dart';
import '../../shared/models/product.dart';
// import '../../shared/widgets/branded_loading.dart'; // Unused
import '../providers/cart_provider.dart';
import '../providers/public_store_tenant_provider.dart';
import '../theme/public_store_theme.dart';

/// A unified website renderer that can toggle edit mode
/// 
/// When editMode is true:
/// - Shows edit controls overlaid on actual elements
/// - Allows clicking elements to edit them
/// - Shows a toolbar for adding blocks, changing theme
/// 
/// When editMode is false:
/// - Renders the public website exactly as visitors see it
class EditableWebsite extends StatefulWidget {
  final bool editMode;
  final VoidCallback? onExitEditMode;
  
  const EditableWebsite({
    super.key,
    this.editMode = false,
    this.onExitEditMode,
  });

  @override
  State<EditableWebsite> createState() => _EditableWebsiteState();
}

class _EditableWebsiteState extends State<EditableWebsite> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _blocks = [];
  List<Product> _featuredProducts = [];
  String? _selectedBlockId;
  String? _hoveredBlockId;
  bool _hasChanges = false;
  
  // Edit panel state
  String _activePanel = 'none'; // none, blocks, theme, settings
  
  @override
  void initState() {
    super.initState();
    _loadData();
  }
  
  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    
    try {
      final websiteService = context.read<WebsiteService>();
      
      // Load all website data
      await Future.wait([
        websiteService.loadSettings(),
        websiteService.loadBlocks(),
        websiteService.loadFeaturedProducts(),
      ]);
      
      _blocks = List<Map<String, dynamic>>.from(websiteService.blocks);
      
      // Load featured products
      final featuredEntries = websiteService.featuredProducts
          .where((fp) => fp.active)
          .toList();
      _featuredProducts = await _fetchFeaturedProducts(featuredEntries);
      
    } catch (e) {
      debugPrint('[EditableWebsite] Error loading data: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }
  
  Future<List<Product>> _fetchFeaturedProducts(List<dynamic> entries) async {
    // Similar to public_home_page logic
    if (entries.isEmpty) return [];
    
    final tenantProvider = context.read<PublicStoreTenantProvider>();
    final tenantId = tenantProvider.tenantId;
    if (tenantId == null) return [];
    
    final productIds = entries
        .map((e) => e.productId as String)
        .toSet()
        .toList();
    
    try {
      final response = await Supabase.instance.client
          .from('products')
          .select()
          .eq('tenant_id', tenantId)
          .inFilter('id', productIds)
          .eq('show_on_website', true)
          .eq('is_active', true);
      
      return (response as List).map((row) {
        final map = Map<String, dynamic>.from(row as Map);
        return Product.fromJson(map);
      }).toList();
    } catch (e) {
      debugPrint('[EditableWebsite] Error fetching products: $e');
      return [];
    }
  }

  @override
  Widget build(BuildContext context) {
    final websiteService = context.watch<WebsiteService>();
    
    // Get theme settings
    final primaryColor = _resolveColor(
      websiteService.getSetting('theme_primary_color', ''),
      PublicStoreTheme.primaryBlue,
    );
    final accentColor = _resolveColor(
      websiteService.getSetting('theme_accent_color', ''),
      PublicStoreTheme.accentGreen,
    );
    final backgroundColor = _resolveColor(
      websiteService.getSetting('theme_background_color', ''),
      Colors.white,
    );
    
    // Don't show loading screen - just render with defaults until data loads
    
    return Scaffold(
      backgroundColor: backgroundColor,
      body: Stack(
        children: [
          // The actual website content
          Column(
            children: [
              // Header - editable in edit mode
              _buildHeader(
                context: context,
                websiteService: websiteService,
                primaryColor: primaryColor,
                accentColor: accentColor,
              ),
              
              // Main content area
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      // Render all blocks
                      ..._blocks.map((block) => _buildEditableBlock(
                        block: block,
                        primaryColor: primaryColor,
                        accentColor: accentColor,
                        websiteService: websiteService,
                      )),
                      
                      // Add block button (edit mode only)
                      if (widget.editMode)
                        _buildAddBlockButton(primaryColor),
                      
                      // Footer
                      _buildFooter(
                        context: context,
                        websiteService: websiteService,
                        primaryColor: primaryColor,
                        accentColor: accentColor,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          
          // Edit mode toolbar
          if (widget.editMode)
            _buildEditToolbar(primaryColor, accentColor),
          
          // Side panel for editing selected element
          if (widget.editMode && _activePanel != 'none')
            _buildSidePanel(websiteService, primaryColor),
        ],
      ),
    );
  }
  
  Widget _buildHeader({
    required BuildContext context,
    required WebsiteService websiteService,
    required Color primaryColor,
    required Color accentColor,
  }) {
    final storeName = websiteService.getSetting('store_name', 'VINABIKE');
    final contactPhone = websiteService.getSetting('contact_phone', '+56 9 XXXX XXXX');
    final contactEmail = websiteService.getSetting('contact_email', 'contacto@vinabike.cl');
    final cart = context.watch<CartProvider>();
    
    final header = Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: PublicStoreTheme.shadow,
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // Top bar
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
            color: primaryColor,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.local_shipping_outlined, color: Colors.white, size: 16),
                const SizedBox(width: 8),
                const Text('Envíos a todo Chile', style: TextStyle(color: Colors.white, fontSize: 13)),
                const SizedBox(width: 24),
                const Icon(Icons.phone_outlined, color: Colors.white, size: 16),
                const SizedBox(width: 8),
                Text('Contáctanos: $contactPhone', style: const TextStyle(color: Colors.white, fontSize: 13)),
                const SizedBox(width: 24),
                const Icon(Icons.email_outlined, color: Colors.white, size: 16),
                const SizedBox(width: 8),
                Text(contactEmail, style: const TextStyle(color: Colors.white, fontSize: 13)),
              ],
            ),
          ),
          
          // Navigation bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            child: Row(
              children: [
                // Logo
                Text(
                  storeName.toUpperCase(),
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: primaryColor,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(width: 48),
                
                // Navigation links
                _buildNavLink('Inicio', '/', primaryColor),
                _buildNavLink('Productos', '/tienda/productos', primaryColor),
                _buildNavLink('Contacto', '/contacto', primaryColor),
                
                const Spacer(),
                
                // Search, Cart, Login
                IconButton(
                  icon: const Icon(Icons.search),
                  onPressed: () {},
                ),
                Stack(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.shopping_cart_outlined),
                      onPressed: () => context.go('/tienda/carrito'),
                    ),
                    if (cart.itemCount > 0)
                      Positioned(
                        right: 0,
                        top: 0,
                        child: IgnorePointer(
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: accentColor,
                              shape: BoxShape.circle,
                            ),
                            child: Text(
                              '${cart.itemCount}',
                              style: const TextStyle(color: Colors.white, fontSize: 10),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: () => context.go('/tienda/cuenta'),
                  icon: const Icon(Icons.person_outline, size: 18),
                  label: const Text('INICIAR SESIÓN'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryColor,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
    
    // Wrap with edit overlay if in edit mode
    if (widget.editMode) {
      return _wrapWithEditOverlay(
        child: header,
        id: 'header',
        label: 'Encabezado',
        onEdit: () => setState(() => _activePanel = 'settings'),
      );
    }
    
    return header;
  }
  
  Widget _buildNavLink(String label, String route, Color primaryColor) {
    final isActive = GoRouterState.of(context).uri.path == route;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: InkWell(
        onTap: widget.editMode ? null : () => context.go(route),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                color: isActive ? primaryColor : Colors.black87,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
            if (isActive)
              Container(
                margin: const EdgeInsets.only(top: 4),
                height: 2,
                width: 24,
                color: primaryColor,
              ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildEditableBlock({
    required Map<String, dynamic> block,
    required Color primaryColor,
    required Color accentColor,
    required WebsiteService websiteService,
  }) {
    final blockId = block['id']?.toString() ?? '';
    final blockType = block['block_type']?.toString() ?? 'hero';
    final blockData = Map<String, dynamic>.from(block['block_data'] ?? {});
    final isVisible = block['is_visible'] ?? true;
    
    if (!isVisible && !widget.editMode) {
      return const SizedBox.shrink();
    }
    
    // Get theme settings
    final headingFont = websiteService.getSetting('theme_heading_font', '');
    final bodyFont = websiteService.getSetting('theme_body_font', '');
    final headingSize = double.tryParse(websiteService.getSetting('theme_heading_size', '48')) ?? 48.0;
    final bodySize = double.tryParse(websiteService.getSetting('theme_body_size', '16')) ?? 16.0;
    
    final blockWidget = WebsiteBlockRenderer.build(
      context: context,
      blockType: blockType,
      data: blockData,
      primaryColor: primaryColor,
      accentColor: accentColor,
      featuredProducts: blockType == 'products' ? _featuredProducts : null,
      previewMode: widget.editMode,
      headingFont: headingFont.isNotEmpty ? headingFont : null,
      bodyFont: bodyFont.isNotEmpty ? bodyFont : null,
      headingSize: headingSize,
      bodySize: bodySize,
      onNavigate: widget.editMode ? (_) {} : (route) => context.go(route),
    );
    
    if (!widget.editMode) {
      return blockWidget;
    }
    
    // Wrap with edit overlay
    return _wrapWithEditOverlay(
      child: Opacity(
        opacity: isVisible ? 1.0 : 0.5,
        child: blockWidget,
      ),
      id: blockId,
      label: _getBlockTypeName(blockType),
      onEdit: () {
        setState(() {
          _selectedBlockId = blockId;
          _activePanel = 'blocks';
        });
      },
      showVisibilityToggle: true,
      isVisible: isVisible,
      onToggleVisibility: () => _toggleBlockVisibility(blockId),
      onDelete: () => _deleteBlock(blockId),
      onMoveUp: _blocks.indexWhere((b) => b['id'] == blockId) > 0
          ? () => _moveBlock(blockId, -1)
          : null,
      onMoveDown: _blocks.indexWhere((b) => b['id'] == blockId) < _blocks.length - 1
          ? () => _moveBlock(blockId, 1)
          : null,
    );
  }
  
  Widget _wrapWithEditOverlay({
    required Widget child,
    required String id,
    required String label,
    required VoidCallback onEdit,
    bool showVisibilityToggle = false,
    bool isVisible = true,
    VoidCallback? onToggleVisibility,
    VoidCallback? onDelete,
    VoidCallback? onMoveUp,
    VoidCallback? onMoveDown,
  }) {
    final isHovered = _hoveredBlockId == id;
    final isSelected = _selectedBlockId == id;
    
    return MouseRegion(
      onEnter: (_) => setState(() => _hoveredBlockId = id),
      onExit: (_) => setState(() => _hoveredBlockId = null),
      child: GestureDetector(
        onTap: onEdit,
        child: Stack(
          children: [
            // The actual content
            child,
            
            // Hover/selection border
            if (isHovered || isSelected)
              Positioned.fill(
                child: IgnorePointer(
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: isSelected ? Colors.blue : Colors.blue.withOpacity(0.5),
                        width: isSelected ? 3 : 2,
                      ),
                    ),
                  ),
                ),
              ),
            
            // Label badge
            if (isHovered || isSelected)
              Positioned(
                top: 8,
                left: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.blue,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            
            // Action buttons
            if (isHovered || isSelected)
              Positioned(
                top: 8,
                right: 8,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (onMoveUp != null)
                      _buildActionButton(Icons.arrow_upward, onMoveUp, 'Mover arriba'),
                    if (onMoveDown != null)
                      _buildActionButton(Icons.arrow_downward, onMoveDown, 'Mover abajo'),
                    if (showVisibilityToggle)
                      _buildActionButton(
                        isVisible ? Icons.visibility : Icons.visibility_off,
                        onToggleVisibility ?? () {},
                        isVisible ? 'Ocultar' : 'Mostrar',
                      ),
                    _buildActionButton(Icons.edit, onEdit, 'Editar'),
                    if (onDelete != null)
                      _buildActionButton(Icons.delete, onDelete, 'Eliminar', isDestructive: true),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildActionButton(IconData icon, VoidCallback onTap, String tooltip, {bool isDestructive = false}) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Tooltip(
        message: tooltip,
        child: Material(
          color: isDestructive ? Colors.red : Colors.white,
          borderRadius: BorderRadius.circular(4),
          elevation: 2,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(4),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Icon(
                icon,
                size: 18,
                color: isDestructive ? Colors.white : Colors.black87,
              ),
            ),
          ),
        ),
      ),
    );
  }
  
  Widget _buildAddBlockButton(Color primaryColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Center(
        child: OutlinedButton.icon(
          onPressed: () => setState(() => _activePanel = 'blocks'),
          icon: const Icon(Icons.add),
          label: const Text('Agregar Bloque'),
          style: OutlinedButton.styleFrom(
            foregroundColor: primaryColor,
            side: BorderSide(color: primaryColor, style: BorderStyle.solid),
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
          ),
        ),
      ),
    );
  }
  
  Widget _buildFooter({
    required BuildContext context,
    required WebsiteService websiteService,
    required Color primaryColor,
    required Color accentColor,
  }) {
    final storeName = websiteService.getSetting('store_name', 'VINABIKE');
    final storeDescription = websiteService.getSetting('store_description', 'Todo lo que necesitas para tu bicicleta');
    final contactEmail = websiteService.getSetting('contact_email', 'contacto@vinabike.cl');
    final contactPhone = websiteService.getSetting('contact_phone', '+56 9 XXXX XXXX');
    final contactAddress = websiteService.getSetting('contact_address', 'Viña del Mar, Chile');
    
    final footer = Container(
      color: const Color(0xFF1A1A2E),
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // About column
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      storeName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      storeDescription,
                      style: TextStyle(color: Colors.grey.shade400),
                    ),
                  ],
                ),
              ),
              
              // Links column
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'ENLACES',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _buildFooterLink('Inicio', '/'),
                    _buildFooterLink('Productos', '/tienda/productos'),
                    _buildFooterLink('Contacto', '/contacto'),
                  ],
                ),
              ),
              
              // Contact column
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'CONTACTO',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Icon(Icons.email_outlined, color: Colors.grey.shade400, size: 16),
                        const SizedBox(width: 8),
                        Text(contactEmail, style: TextStyle(color: Colors.grey.shade400)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(Icons.phone_outlined, color: Colors.grey.shade400, size: 16),
                        const SizedBox(width: 8),
                        Text(contactPhone, style: TextStyle(color: Colors.grey.shade400)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.location_on_outlined, color: Colors.grey.shade400, size: 16),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(contactAddress, style: TextStyle(color: Colors.grey.shade400)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 32),
          const Divider(color: Colors.grey),
          const SizedBox(height: 16),
          
          Text(
            '© ${DateTime.now().year} $storeName. Todos los derechos reservados.',
            style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
          ),
        ],
      ),
    );
    
    if (widget.editMode) {
      return _wrapWithEditOverlay(
        child: footer,
        id: 'footer',
        label: 'Pie de Página',
        onEdit: () => setState(() => _activePanel = 'settings'),
      );
    }
    
    return footer;
  }
  
  Widget _buildFooterLink(String label, String route) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: widget.editMode ? null : () => context.go(route),
        child: Text(
          label,
          style: TextStyle(color: Colors.grey.shade400),
        ),
      ),
    );
  }
  
  Widget _buildEditToolbar(Color primaryColor, Color accentColor) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        color: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            // Exit button
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: widget.onExitEditMode,
              tooltip: 'Salir del editor',
            ),
            
            const SizedBox(width: 16),
            
            Text(
              'Modo Edición',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: primaryColor,
              ),
            ),
            
            const Spacer(),
            
            // Panel toggles
            _buildToolbarButton(
              icon: Icons.add_box_outlined,
              label: 'Bloques',
              isActive: _activePanel == 'blocks',
              onTap: () => setState(() => _activePanel = _activePanel == 'blocks' ? 'none' : 'blocks'),
            ),
            _buildToolbarButton(
              icon: Icons.palette_outlined,
              label: 'Tema',
              isActive: _activePanel == 'theme',
              onTap: () => setState(() => _activePanel = _activePanel == 'theme' ? 'none' : 'theme'),
            ),
            _buildToolbarButton(
              icon: Icons.settings_outlined,
              label: 'Ajustes',
              isActive: _activePanel == 'settings',
              onTap: () => setState(() => _activePanel = _activePanel == 'settings' ? 'none' : 'settings'),
            ),
            
            const SizedBox(width: 24),
            
            // Save button
            if (_hasChanges)
              FilledButton.icon(
                onPressed: _saveChanges,
                icon: const Icon(Icons.save, size: 18),
                label: const Text('Guardar'),
                style: FilledButton.styleFrom(
                  backgroundColor: accentColor,
                ),
              ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildToolbarButton({
    required IconData icon,
    required String label,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: TextButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 18),
        label: Text(label),
        style: TextButton.styleFrom(
          backgroundColor: isActive ? Colors.blue.withOpacity(0.1) : null,
          foregroundColor: isActive ? Colors.blue : Colors.black87,
        ),
      ),
    );
  }
  
  Widget _buildSidePanel(WebsiteService websiteService, Color primaryColor) {
    return Positioned(
      top: 56, // Below toolbar
      right: 0,
      bottom: 0,
      width: 360,
      child: Material(
        elevation: 8,
        child: Container(
          color: Colors.white,
          child: Column(
            children: [
              // Panel header
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
                ),
                child: Row(
                  children: [
                    Text(
                      _getPanelTitle(),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => setState(() => _activePanel = 'none'),
                    ),
                  ],
                ),
              ),
              
              // Panel content
              Expanded(
                child: _buildPanelContent(websiteService, primaryColor),
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  String _getPanelTitle() {
    switch (_activePanel) {
      case 'blocks':
        return _selectedBlockId != null ? 'Editar Bloque' : 'Agregar Bloque';
      case 'theme':
        return 'Tema';
      case 'settings':
        return 'Ajustes del Sitio';
      default:
        return '';
    }
  }
  
  Widget _buildPanelContent(WebsiteService websiteService, Color primaryColor) {
    switch (_activePanel) {
      case 'blocks':
        if (_selectedBlockId != null) {
          return _buildBlockEditor(websiteService);
        }
        return _buildBlockPicker(primaryColor);
      case 'theme':
        return _buildThemeEditor(websiteService);
      case 'settings':
        return _buildSettingsEditor(websiteService);
      default:
        return const SizedBox.shrink();
    }
  }
  
  Widget _buildBlockPicker(Color primaryColor) {
    final definitions = WebsiteBlockRegistry.all();
    
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Haz clic para agregar un bloque',
          style: TextStyle(color: Colors.grey),
        ),
        const SizedBox(height: 16),
        ...definitions.map((def) => Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: primaryColor.withOpacity(0.1),
              child: Icon(_getBlockIcon(def.type), color: primaryColor),
            ),
            title: Text(def.title),
            subtitle: Text(def.description, maxLines: 1, overflow: TextOverflow.ellipsis),
            trailing: const Icon(Icons.add),
            onTap: () => _addBlock(def.type),
          ),
        )),
      ],
    );
  }
  
  Widget _buildBlockEditor(WebsiteService websiteService) {
    final block = _blocks.firstWhere(
      (b) => b['id'] == _selectedBlockId,
      orElse: () => <String, dynamic>{},
    );
    
    if (block.isEmpty) {
      return const Center(child: Text('Bloque no encontrado'));
    }
    
    final blockType = block['block_type']?.toString() ?? 'hero';
    final blockData = Map<String, dynamic>.from(block['block_data'] ?? {});
    
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          _getBlockTypeName(blockType),
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        
        // Build form fields based on block type
        ..._buildBlockFields(blockType, blockData),
        
        const SizedBox(height: 24),
        OutlinedButton(
          onPressed: () => setState(() => _selectedBlockId = null),
          child: const Text('Cerrar'),
        ),
      ],
    );
  }
  
  List<Widget> _buildBlockFields(String blockType, Map<String, dynamic> data) {
    // Common fields based on block type
    switch (blockType) {
      case 'hero':
        return [
          _buildTextField('Título', data['title'] ?? '', (v) => _updateBlockData('title', v)),
          _buildTextField('Subtítulo', data['subtitle'] ?? '', (v) => _updateBlockData('subtitle', v)),
          _buildTextField('Texto del botón', data['buttonText'] ?? 'Ver Catálogo', (v) => _updateBlockData('buttonText', v)),
          _buildTextField('Enlace del botón', data['buttonLink'] ?? '/tienda/productos', (v) => _updateBlockData('buttonLink', v)),
          _buildTextField('URL de imagen', data['imageUrl'] ?? '', (v) => _updateBlockData('imageUrl', v)),
        ];
      case 'products':
        return [
          _buildTextField('Título', data['title'] ?? 'Productos Destacados', (v) => _updateBlockData('title', v)),
        ];
      case 'services':
        return [
          _buildTextField('Título', data['title'] ?? 'Nuestros Servicios', (v) => _updateBlockData('title', v)),
        ];
      default:
        return [
          const Text('Editor no disponible para este tipo de bloque'),
        ];
    }
  }
  
  Widget _buildTextField(String label, String value, ValueChanged<String> onChanged) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextFormField(
        initialValue: value,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
        onChanged: onChanged,
      ),
    );
  }
  
  Widget _buildThemeEditor(WebsiteService websiteService) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('Colores', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        _buildColorPicker('Color Primario', 'theme_primary_color', websiteService),
        _buildColorPicker('Color de Acento', 'theme_accent_color', websiteService),
        _buildColorPicker('Color de Fondo', 'theme_background_color', websiteService),
        _buildColorPicker('Color de Texto', 'theme_text_color', websiteService),
        const SizedBox(height: 24),
        const Text('Tipografía', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        // Add font pickers...
      ],
    );
  }
  
  Widget _buildColorPicker(String label, String settingKey, WebsiteService websiteService) {
    final currentValue = websiteService.getSetting(settingKey, '');
    final color = _resolveColor(currentValue, Colors.grey);
    
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey.shade300),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextFormField(
              initialValue: currentValue,
              decoration: InputDecoration(
                labelText: label,
                border: const OutlineInputBorder(),
                hintText: '#RRGGBB',
              ),
              onChanged: (value) {
                websiteService.saveSetting(settingKey, value);
                setState(() => _hasChanges = true);
              },
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildSettingsEditor(WebsiteService websiteService) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('Información de la Tienda', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        _buildSettingField('Nombre de la tienda', 'store_name', websiteService),
        _buildSettingField('Descripción', 'store_description', websiteService, maxLines: 3),
        const SizedBox(height: 24),
        const Text('Contacto', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        _buildSettingField('Email', 'contact_email', websiteService),
        _buildSettingField('Teléfono', 'contact_phone', websiteService),
        _buildSettingField('Dirección', 'contact_address', websiteService, maxLines: 2),
        const SizedBox(height: 24),
        const Text('Redes Sociales', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        _buildSettingField('WhatsApp', 'whatsapp', websiteService),
        _buildSettingField('Instagram', 'instagram', websiteService),
        _buildSettingField('Facebook', 'facebook', websiteService),
      ],
    );
  }
  
  Widget _buildSettingField(String label, String key, WebsiteService websiteService, {int maxLines = 1}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextFormField(
        initialValue: websiteService.getSetting(key, ''),
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
        maxLines: maxLines,
        onChanged: (value) {
          websiteService.saveSetting(key, value);
          setState(() => _hasChanges = true);
        },
      ),
    );
  }
  
  // Helper methods
  Color _resolveColor(String? value, Color fallback) {
    if (value == null || value.isEmpty) return fallback;
    try {
      final hex = value.replaceAll('#', '');
      if (hex.length == 6) {
        return Color(int.parse('FF$hex', radix: 16));
      }
    } catch (_) {}
    return fallback;
  }
  
  String _getBlockTypeName(String type) {
    const names = {
      'hero': 'Hero / Banner',
      'carousel': 'Carrusel',
      'products': 'Productos',
      'services': 'Servicios',
      'about': 'Acerca de',
      'cta': 'Llamado a Acción',
      'features': 'Características',
      'testimonials': 'Testimonios',
      'contact': 'Contacto',
      'faq': 'Preguntas Frecuentes',
    };
    return names[type] ?? type;
  }
  
  IconData _getBlockIcon(WebsiteBlockType type) {
    const icons = {
      WebsiteBlockType.hero: Icons.image,
      WebsiteBlockType.carousel: Icons.view_carousel,
      WebsiteBlockType.products: Icons.shopping_bag,
      WebsiteBlockType.services: Icons.build,
      WebsiteBlockType.about: Icons.info,
      WebsiteBlockType.cta: Icons.ads_click,
      WebsiteBlockType.features: Icons.star,
      WebsiteBlockType.testimonials: Icons.format_quote,
      WebsiteBlockType.contact: Icons.contact_mail,
      WebsiteBlockType.faq: Icons.help,
    };
    return icons[type] ?? Icons.widgets;
  }
  
  // Block manipulation methods
  void _addBlock(WebsiteBlockType type) {
    final definition = WebsiteBlockRegistry.definitionFor(type);
    final newBlock = {
      'id': DateTime.now().millisecondsSinceEpoch.toString(),
      'block_type': type.name,
      'block_data': Map<String, dynamic>.from(definition.defaultData),
      'order_index': _blocks.length,
      'is_visible': true,
    };
    
    setState(() {
      _blocks.add(newBlock);
      _selectedBlockId = newBlock['id'] as String;
      _hasChanges = true;
    });
  }
  
  void _updateBlockData(String key, dynamic value) {
    if (_selectedBlockId == null) return;
    
    final index = _blocks.indexWhere((b) => b['id'] == _selectedBlockId);
    if (index == -1) return;
    
    setState(() {
      final blockData = Map<String, dynamic>.from(_blocks[index]['block_data'] ?? {});
      blockData[key] = value;
      _blocks[index]['block_data'] = blockData;
      _hasChanges = true;
    });
  }
  
  void _toggleBlockVisibility(String blockId) {
    final index = _blocks.indexWhere((b) => b['id'] == blockId);
    if (index == -1) return;
    
    setState(() {
      _blocks[index]['is_visible'] = !(_blocks[index]['is_visible'] ?? true);
      _hasChanges = true;
    });
  }
  
  void _deleteBlock(String blockId) {
    setState(() {
      _blocks.removeWhere((b) => b['id'] == blockId);
      if (_selectedBlockId == blockId) {
        _selectedBlockId = null;
      }
      _hasChanges = true;
    });
  }
  
  void _moveBlock(String blockId, int direction) {
    final index = _blocks.indexWhere((b) => b['id'] == blockId);
    if (index == -1) return;
    
    final newIndex = index + direction;
    if (newIndex < 0 || newIndex >= _blocks.length) return;
    
    setState(() {
      final block = _blocks.removeAt(index);
      _blocks.insert(newIndex, block);
      _hasChanges = true;
    });
  }
  
  Future<void> _saveChanges() async {
    final websiteService = context.read<WebsiteService>();
    
    try {
      // Normalize block payload for saving
      final blocksForSave = _blocks.asMap().entries.map((entry) {
        final index = entry.key;
        final block = entry.value;
        final blockType = block['block_type'] ?? block['type'];
        final blockData = block['block_data'] ?? block['data'] ?? {};
        final isVisible = block['is_visible'] ?? block['isVisible'] ?? true;

        return {
          'id': block['id'],
          'type': blockType,
          'data': blockData,
          'isVisible': isVisible,
          'order_index': index,
        };
      }).toList();

      await websiteService.saveBlocks(blocksForSave);
      setState(() => _hasChanges = false);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Cambios guardados'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al guardar: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}
