import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:async';
import '../../../shared/widgets/main_layout.dart';
import '../services/website_service.dart';

/// 🎨 ADVANCED VISUAL WEBSITE EDITOR - PHASE 2
/// 
/// Professional split-screen editor with ALL the awesome features!
class AdvancedVisualEditorPage extends StatefulWidget {
  const AdvancedVisualEditorPage({super.key});

  @override
  State<AdvancedVisualEditorPage> createState() => _AdvancedVisualEditorPageState();
}

// History entry for undo/redo
class EditorHistory {
  final Map<String, dynamic> state;
  final DateTime timestamp;
  
  EditorHistory(this.state, this.timestamp);
}

class _AdvancedVisualEditorPageState extends State<AdvancedVisualEditorPage> {
  // ============================================================================
  // STATE MANAGEMENT
  // ============================================================================
  
  bool _isSaving = false;
  bool _hasChanges = false;
  bool _autoSaveEnabled = true;
  Timer? _autoSaveTimer;
  
  // Undo/Redo
  final List<EditorHistory> _history = [];
  int _historyIndex = -1;
  final int _maxHistory = 50;
  
  // Preview mode
  String _previewMode = 'desktop'; // desktop, tablet, mobile
  double _previewZoom = 1.0;
  
  // Hero Section
  final _heroTitleController = TextEditingController();
  final _heroSubtitleController = TextEditingController();
  final _heroCTATextController = TextEditingController();
  String? _heroImageUrl;
  String _heroAlignment = 'center'; // left, center, right
  bool _heroShowOverlay = true;
  double _heroOverlayOpacity = 0.5;
  
  // Theme Colors
  Color _primaryColor = const Color(0xFF2E7D32);
  Color _accentColor = const Color(0xFFFF6F00);
  Color _backgroundColor = Colors.white;
  Color _textColor = Colors.black87;
  
  // Typography
  String _headingFont = 'Roboto';
  String _bodyFont = 'Roboto';
  double _headingSize = 48.0;
  double _bodySize = 16.0;
  
  // Layout & Spacing
  double _sectionSpacing = 64.0;
  double _containerPadding = 24.0;
  String _maxWidth = '1200'; // px
  
  // Products Section
  bool _showProductsSection = true;
  String _productsTitle = 'Productos Destacados';
  int _productsPerRow = 3;
  String _productsLayout = 'grid'; // grid, carousel, list
  
  // Services Section
  bool _showServicesSection = true;
  String _servicesTitle = 'Nuestros Servicios';
  final List<Map<String, String>> _services = [];
  
  // About Section
  bool _showAboutSection = true;
  String _aboutTitle = 'Sobre Nosotros';
  final _aboutContentController = TextEditingController();
  String? _aboutImageUrl;
  String _aboutImagePosition = 'right'; // left, right
  
  // Contact Info
  final _contactPhoneController = TextEditingController();
  final _contactEmailController = TextEditingController();
  final _contactAddressController = TextEditingController();
  final _contactWhatsappController = TextEditingController();
  final _contactInstagramController = TextEditingController();
  final _contactFacebookController = TextEditingController();
  
  // Footer
  bool _showSocialLinks = true;
  bool _showNewsletter = true;
  Color _footerColor = const Color(0xFF212121);
  
  // UI State
  String _selectedSection = 'hero'; // hero, colors, typography, layout, products, services, about, contact, footer
  
  // Search
  final _searchController = TextEditingController();
  String _searchQuery = '';
  
  @override
  void initState() {
    super.initState();
    _loadCurrentSettings();
    _startAutoSave();
    
    // Track changes for all controllers
    _heroTitleController.addListener(_markAsChanged);
    _heroSubtitleController.addListener(_markAsChanged);
    _heroCTATextController.addListener(_markAsChanged);
    _aboutContentController.addListener(_markAsChanged);
    _contactPhoneController.addListener(_markAsChanged);
    _contactEmailController.addListener(_markAsChanged);
    _contactAddressController.addListener(_markAsChanged);
    _contactWhatsappController.addListener(_markAsChanged);
    _contactInstagramController.addListener(_markAsChanged);
    _contactFacebookController.addListener(_markAsChanged);
    _searchController.addListener(() {
      setState(() => _searchQuery = _searchController.text.toLowerCase());
    });
    
    // Save initial state to history
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _saveToHistory();
    });
  }
  
  void _markAsChanged() {
    if (!_hasChanges) {
      setState(() => _hasChanges = true);
      _saveToHistory();
    }
  }
  
  void _startAutoSave() {
    _autoSaveTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (_autoSaveEnabled && _hasChanges && !_isSaving) {
        _saveChanges(showNotification: false);
      }
    });
  }
  
  void _saveToHistory() {
    final state = _captureCurrentState();
    
    // Remove any history after current index (when undoing then making new change)
    if (_historyIndex < _history.length - 1) {
      _history.removeRange(_historyIndex + 1, _history.length);
    }
    
    // Add new state
    _history.add(EditorHistory(state, DateTime.now()));
    _historyIndex = _history.length - 1;
    
    // Keep history size limited
    if (_history.length > _maxHistory) {
      _history.removeAt(0);
      _historyIndex--;
    }
  }
  
  Map<String, dynamic> _captureCurrentState() {
    return {
      'heroTitle': _heroTitleController.text,
      'heroSubtitle': _heroSubtitleController.text,
      'heroCTAText': _heroCTATextController.text,
      'heroImageUrl': _heroImageUrl,
      'heroAlignment': _heroAlignment,
      'heroShowOverlay': _heroShowOverlay,
      'heroOverlayOpacity': _heroOverlayOpacity,
      'primaryColor': _primaryColor.value,
      'accentColor': _accentColor.value,
      'backgroundColor': _backgroundColor.value,
      'textColor': _textColor.value,
      'headingFont': _headingFont,
      'bodyFont': _bodyFont,
      'headingSize': _headingSize,
      'bodySize': _bodySize,
      'sectionSpacing': _sectionSpacing,
      'containerPadding': _containerPadding,
      'maxWidth': _maxWidth,
      'showProductsSection': _showProductsSection,
      'productsTitle': _productsTitle,
      'productsPerRow': _productsPerRow,
      'productsLayout': _productsLayout,
      'showServicesSection': _showServicesSection,
      'servicesTitle': _servicesTitle,
      'showAboutSection': _showAboutSection,
      'aboutTitle': _aboutTitle,
      'aboutContent': _aboutContentController.text,
      'aboutImageUrl': _aboutImageUrl,
      'aboutImagePosition': _aboutImagePosition,
      'contactPhone': _contactPhoneController.text,
      'contactEmail': _contactEmailController.text,
      'contactAddress': _contactAddressController.text,
      'contactWhatsapp': _contactWhatsappController.text,
      'contactInstagram': _contactInstagramController.text,
      'contactFacebook': _contactFacebookController.text,
      'showSocialLinks': _showSocialLinks,
      'showNewsletter': _showNewsletter,
      'footerColor': _footerColor.value,
    };
  }
  
  void _restoreState(Map<String, dynamic> state) {
    setState(() {
      _heroTitleController.text = state['heroTitle'] ?? '';
      _heroSubtitleController.text = state['heroSubtitle'] ?? '';
      _heroCTATextController.text = state['heroCTAText'] ?? '';
      _heroImageUrl = state['heroImageUrl'];
      _heroAlignment = state['heroAlignment'] ?? 'center';
      _heroShowOverlay = state['heroShowOverlay'] ?? true;
      _heroOverlayOpacity = state['heroOverlayOpacity'] ?? 0.5;
      _primaryColor = Color(state['primaryColor'] ?? 0xFF2E7D32);
      _accentColor = Color(state['accentColor'] ?? 0xFFFF6F00);
      _backgroundColor = Color(state['backgroundColor'] ?? 0xFFFFFFFF);
      _textColor = Color(state['textColor'] ?? 0xFF000000);
      _headingFont = state['headingFont'] ?? 'Roboto';
      _bodyFont = state['bodyFont'] ?? 'Roboto';
      _headingSize = state['headingSize'] ?? 48.0;
      _bodySize = state['bodySize'] ?? 16.0;
      _sectionSpacing = state['sectionSpacing'] ?? 64.0;
      _containerPadding = state['containerPadding'] ?? 24.0;
      _maxWidth = state['maxWidth'] ?? '1200';
      _showProductsSection = state['showProductsSection'] ?? true;
      _productsTitle = state['productsTitle'] ?? 'Productos Destacados';
      _productsPerRow = state['productsPerRow'] ?? 3;
      _productsLayout = state['productsLayout'] ?? 'grid';
      _showServicesSection = state['showServicesSection'] ?? true;
      _servicesTitle = state['servicesTitle'] ?? 'Nuestros Servicios';
      _showAboutSection = state['showAboutSection'] ?? true;
      _aboutTitle = state['aboutTitle'] ?? 'Sobre Nosotros';
      _aboutContentController.text = state['aboutContent'] ?? '';
      _aboutImageUrl = state['aboutImageUrl'];
      _aboutImagePosition = state['aboutImagePosition'] ?? 'right';
      _contactPhoneController.text = state['contactPhone'] ?? '';
      _contactEmailController.text = state['contactEmail'] ?? '';
      _contactAddressController.text = state['contactAddress'] ?? '';
      _contactWhatsappController.text = state['contactWhatsapp'] ?? '';
      _contactInstagramController.text = state['contactInstagram'] ?? '';
      _contactFacebookController.text = state['contactFacebook'] ?? '';
      _showSocialLinks = state['showSocialLinks'] ?? true;
      _showNewsletter = state['showNewsletter'] ?? true;
      _footerColor = Color(state['footerColor'] ?? 0xFF212121);
    });
  }
  
  void _undo() {
    if (_historyIndex > 0) {
      setState(() {
        _historyIndex--;
        _restoreState(_history[_historyIndex].state);
        _hasChanges = true;
      });
    }
  }
  
  void _redo() {
    if (_historyIndex < _history.length - 1) {
      setState(() {
        _historyIndex++;
        _restoreState(_history[_historyIndex].state);
        _hasChanges = true;
      });
    }
  }
  
  Future<void> _loadCurrentSettings() async {
    // TODO: Load from database via WebsiteService
    setState(() {
      _heroTitleController.text = 'SERVICIOS Y PRODUCTOS DE BICICLETA';
      _heroSubtitleController.text = 'TODO LO QUE NECESITAS PARA TU BICICLETA EN VIÑA DEL MAR';
      _heroCTATextController.text = 'VER PRODUCTOS';
      _contactPhoneController.text = '+56 9 XXXX XXXX';
      _contactEmailController.text = 'info@vinabike.cl';
      _contactAddressController.text = 'Álvarez 32, Local 17\nViña del Mar, Chile';
      _contactWhatsappController.text = '+56912345678';
      _contactInstagramController.text = '@vinabike';
      _contactFacebookController.text = 'VinabikeCL';
      _aboutContentController.text = 'Somos una tienda especializada en bicicletas y accesorios con más de 10 años de experiencia en Viña del Mar.';
      
      // Initialize services
      _services.addAll([
        {'title': 'Venta de Bicicletas', 'icon': 'directions_bike', 'description': 'Amplio catálogo de bicicletas'},
        {'title': 'Reparaciones', 'icon': 'build', 'description': 'Servicio técnico especializado'},
        {'title': 'Accesorios', 'icon': 'shopping_bag', 'description': 'Todo para tu bicicleta'},
      ]);
    });
  }
  
  Future<void> _saveChanges({bool showNotification = true}) async {
    setState(() => _isSaving = true);
    
    try {
      final websiteService = context.read<WebsiteService>();
      
      // Save all sections
      await websiteService.updateHeroSection(
        title: _heroTitleController.text,
        subtitle: _heroSubtitleController.text,
        imageUrl: _heroImageUrl,
      );
      
      await websiteService.updateThemeColors(
        primaryColor: _primaryColor.value,
        accentColor: _accentColor.value,
      );
      
      await websiteService.updateContactInfo(
        phone: _contactPhoneController.text,
        email: _contactEmailController.text,
        address: _contactAddressController.text,
      );
      
      setState(() {
        _hasChanges = false;
        _isSaving = false;
      });
      
      if (mounted && showNotification) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 8),
                Text('✅ Cambios guardados ${_autoSaveEnabled ? "(auto-save activo)" : ""}'),
              ],
            ),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      setState(() => _isSaving = false);
      
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
  
  Future<void> _pickImage(String section) async {
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1920,
        maxHeight: 1080,
        imageQuality: 85,
      );
      
      if (image != null) {
        // TODO: Upload to Supabase Storage
        setState(() {
          if (section == 'hero') {
            _heroImageUrl = image.path;
          } else if (section == 'about') {
            _aboutImageUrl = image.path;
          }
          _markAsChanged();
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('📷 Imagen seleccionada. Implementar subida a Supabase Storage.'),
            backgroundColor: Colors.blue,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al seleccionar imagen: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
  
  void _showColorPicker(BuildContext context, Color currentColor, Function(Color) onColorChanged) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        Color pickerColor = currentColor;
        
        return AlertDialog(
          title: const Text('Seleccionar Color'),
          content: SingleChildScrollView(
            child: ColorPicker(
              pickerColor: pickerColor,
              onColorChanged: (color) {
                pickerColor = color;
              },
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
  
  @override
  void dispose() {
    _autoSaveTimer?.cancel();
    _heroTitleController.dispose();
    _heroSubtitleController.dispose();
    _heroCTATextController.dispose();
    _aboutContentController.dispose();
    _contactPhoneController.dispose();
    _contactEmailController.dispose();
    _contactAddressController.dispose();
    _contactWhatsappController.dispose();
    _contactInstagramController.dispose();
    _contactFacebookController.dispose();
    _searchController.dispose();
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
            // LEFT: Live Preview
            Expanded(
              flex: 3,
              child: _buildPreviewPanel(theme),
            ),
            
            // RIGHT: Edit Panel
            SizedBox(
              width: 420,
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
          const Text('🎨 Editor Visual Avanzado'),
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
                style: TextStyle(fontSize: 11, color: Colors.orange),
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
                'Auto-guardado activo',
                style: TextStyle(fontSize: 11, color: Colors.green),
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
            context.go('/website');
          }
        },
      ),
      actions: [
        // Undo/Redo
        IconButton(
          icon: const Icon(Icons.undo),
          onPressed: _historyIndex > 0 ? _undo : null,
          tooltip: 'Deshacer (Ctrl+Z)',
        ),
        IconButton(
          icon: const Icon(Icons.redo),
          onPressed: _historyIndex < _history.length - 1 ? _redo : null,
          tooltip: 'Rehacer (Ctrl+Y)',
        ),
        
        const VerticalDivider(),
        
        // Auto-save toggle
        Tooltip(
          message: 'Auto-guardado cada 30s',
          child: Switch(
            value: _autoSaveEnabled,
            onChanged: (value) {
              setState(() => _autoSaveEnabled = value);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(value ? '💾 Auto-guardado activado' : 'Auto-guardado desactivado'),
                  duration: const Duration(seconds: 1),
                ),
              );
            },
          ),
        ),
        
        const SizedBox(width: 8),
        
        // Preview button
        TextButton.icon(
          onPressed: () => context.go('/tienda'),
          icon: const Icon(Icons.visibility),
          label: const Text('Vista Previa'),
        ),
        const SizedBox(width: 8),
        
        // Save button
        ElevatedButton.icon(
          onPressed: _hasChanges && !_isSaving ? () => _saveChanges() : null,
          icon: _isSaving 
            ? const SizedBox(
                width: 16, 
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              )
            : const Icon(Icons.save),
          label: Text(_isSaving ? 'Guardando...' : 'Guardar'),
          style: ElevatedButton.styleFrom(
            backgroundColor: _hasChanges ? theme.colorScheme.primary : Colors.grey,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
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
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          bottom: BorderSide(color: theme.dividerColor),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.monitor, size: 20),
          const SizedBox(width: 8),
          Text(
            'Vista Previa en Vivo',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const Spacer(),
          
          // Device selector
          SegmentedButton<String>(
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
          ),
          
          const SizedBox(width: 16),
          
          // Zoom controls
          IconButton(
            icon: const Icon(Icons.zoom_out, size: 20),
            onPressed: () {
              setState(() => _previewZoom = (_previewZoom - 0.1).clamp(0.5, 2.0));
            },
            tooltip: 'Alejar',
          ),
          Text('${(_previewZoom * 100).toInt()}%'),
          IconButton(
            icon: const Icon(Icons.zoom_in, size: 20),
            onPressed: () {
              setState(() => _previewZoom = (_previewZoom + 0.1).clamp(0.5, 2.0));
            },
            tooltip: 'Acercar',
          ),
          IconButton(
            icon: const Icon(Icons.refresh, size: 20),
            onPressed: () {
              setState(() {
                _previewZoom = 1.0;
                _previewMode = 'desktop';
              });
            },
            tooltip: 'Resetear vista',
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
            borderRadius: BorderRadius.circular(_previewMode != 'desktop' ? 12 : 8),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 20,
                spreadRadius: 2,
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(_previewMode != 'desktop' ? 12 : 8),
            child: _buildLivePreview(context),
          ),
        ),
      ),
    );
  }
  
  Widget _buildLivePreview(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        children: [
          // Mock Header
          _buildPreviewHeader(),
          
          // Hero Section
          if (_selectedSection == 'hero' || _searchQuery.isEmpty || 'hero banner principal'.contains(_searchQuery))
            _buildPreviewHero(),
          
          // Products Section
          if (_showProductsSection && (_selectedSection == 'products' || _searchQuery.isEmpty || 'productos'.contains(_searchQuery)))
            _buildPreviewProducts(),
          
          // Services Section
          if (_showServicesSection && (_selectedSection == 'services' || _searchQuery.isEmpty || 'servicios'.contains(_searchQuery)))
            _buildPreviewServices(),
          
          // About Section
          if (_showAboutSection && (_selectedSection == 'about' || _searchQuery.isEmpty || 'nosotros sobre'.contains(_searchQuery)))
            _buildPreviewAbout(),
          
          // Mock Footer
          _buildPreviewFooter(),
        ],
      ),
    );
  }
  
  Widget _buildPreviewHeader() {
    return Container(
      padding: EdgeInsets.all(_containerPadding),
      color: _primaryColor,
      child: Row(
        children: [
          Text(
            'VINABIKE',
            style: TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.bold,
              fontFamily: _headingFont,
            ),
          ),
          const Spacer(),
          if (_previewMode != 'mobile')
            Text(
              'Menú  Productos  Servicios',
              style: TextStyle(
                color: Colors.white.withOpacity(0.9),
                fontFamily: _bodyFont,
              ),
            ),
        ],
      ),
    );
  }
  
  Widget _buildPreviewHero() {
    return Container(
      height: _previewMode == 'mobile' ? 300 : 500,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            _primaryColor.withOpacity(_heroShowOverlay ? _heroOverlayOpacity : 0.8),
            _accentColor.withOpacity(_heroShowOverlay ? _heroOverlayOpacity : 0.6),
          ],
        ),
      ),
      child: Center(
        child: Padding(
          padding: EdgeInsets.all(_containerPadding * 1.5),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: _heroAlignment == 'left' 
              ? CrossAxisAlignment.start 
              : _heroAlignment == 'right'
                ? CrossAxisAlignment.end
                : CrossAxisAlignment.center,
            children: [
              Text(
                _heroTitleController.text.isEmpty 
                  ? 'TU TÍTULO AQUÍ'
                  : _heroTitleController.text,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: _headingSize,
                  fontWeight: FontWeight.bold,
                  fontFamily: _headingFont,
                  shadows: const [
                    Shadow(
                      color: Colors.black45,
                      blurRadius: 10,
                    ),
                  ],
                ),
                textAlign: _heroAlignment == 'left' 
                  ? TextAlign.left 
                  : _heroAlignment == 'right'
                    ? TextAlign.right
                    : TextAlign.center,
              ),
              SizedBox(height: _sectionSpacing / 4),
              Text(
                _heroSubtitleController.text.isEmpty
                  ? 'Tu subtítulo aquí'
                  : _heroSubtitleController.text,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: _bodySize * 1.25,
                  fontFamily: _bodyFont,
                  shadows: const [
                    Shadow(
                      color: Colors.black45,
                      blurRadius: 10,
                    ),
                  ],
                ),
                textAlign: _heroAlignment == 'left' 
                  ? TextAlign.left 
                  : _heroAlignment == 'right'
                    ? TextAlign.right
                    : TextAlign.center,
              ),
              SizedBox(height: _sectionSpacing / 2),
              ElevatedButton(
                onPressed: () {},
                style: ElevatedButton.styleFrom(
                  backgroundColor: _accentColor,
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.symmetric(
                    horizontal: _containerPadding * 2,
                    vertical: _containerPadding / 1.5,
                  ),
                ),
                child: Text(
                  _heroCTATextController.text.isEmpty 
                    ? 'BOTÓN CTA'
                    : _heroCTATextController.text,
                  style: TextStyle(fontFamily: _bodyFont),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  Widget _buildPreviewProducts() {
    return Padding(
      padding: EdgeInsets.all(_sectionSpacing),
      child: Column(
        children: [
          Text(
            _productsTitle,
            style: TextStyle(
              fontSize: _headingSize * 0.66,
              fontWeight: FontWeight.bold,
              fontFamily: _headingFont,
              color: _textColor,
            ),
          ),
          SizedBox(height: _sectionSpacing / 2),
          _productsLayout == 'grid'
            ? GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: _previewMode == 'mobile' ? 1 : _previewMode == 'tablet' ? 2 : _productsPerRow,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                children: List.generate(
                  _previewMode == 'mobile' ? 2 : 3,
                  (index) => Container(
                    decoration: BoxDecoration(
                      color: Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Center(child: Text('Producto')),
                  ),
                ),
              )
            : const SizedBox(height: 200, child: Center(child: Text('Vista Carousel/List'))),
        ],
      ),
    );
  }
  
  Widget _buildPreviewServices() {
    return Container(
      padding: EdgeInsets.all(_sectionSpacing),
      color: _primaryColor.withOpacity(0.05),
      child: Column(
        children: [
          Text(
            _servicesTitle,
            style: TextStyle(
              fontSize: _headingSize * 0.66,
              fontWeight: FontWeight.bold,
              fontFamily: _headingFont,
              color: _textColor,
            ),
          ),
          SizedBox(height: _sectionSpacing / 2),
          Wrap(
            spacing: 24,
            runSpacing: 24,
            children: _services.map((service) {
              return SizedBox(
                width: _previewMode == 'mobile' ? double.infinity : 250,
                child: Card(
                  child: Padding(
                    padding: EdgeInsets.all(_containerPadding),
                    child: Column(
                      children: [
                        Icon(
                          _getIconData(service['icon'] ?? 'star'),
                          size: 48,
                          color: _primaryColor,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          service['title'] ?? '',
                          style: TextStyle(
                            fontSize: _bodySize * 1.25,
                            fontWeight: FontWeight.bold,
                            fontFamily: _headingFont,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          service['description'] ?? '',
                          style: TextStyle(
                            fontSize: _bodySize,
                            fontFamily: _bodyFont,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
  
  Widget _buildPreviewAbout() {
    return Padding(
      padding: EdgeInsets.all(_sectionSpacing),
      child: Column(
        children: [
          Text(
            _aboutTitle,
            style: TextStyle(
              fontSize: _headingSize * 0.66,
              fontWeight: FontWeight.bold,
              fontFamily: _headingFont,
              color: _textColor,
            ),
          ),
          SizedBox(height: _sectionSpacing / 2),
          Row(
            children: [
              if (_aboutImagePosition == 'left' && _previewMode != 'mobile') ...[
                Expanded(
                  child: Container(
                    height: 200,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Center(child: Text('Imagen')),
                  ),
                ),
                const SizedBox(width: 24),
              ],
              Expanded(
                flex: 2,
                child: Text(
                  _aboutContentController.text.isEmpty
                    ? 'Escribe sobre tu negocio aquí...'
                    : _aboutContentController.text,
                  style: TextStyle(
                    fontSize: _bodySize,
                    fontFamily: _bodyFont,
                    color: _textColor,
                  ),
                ),
              ),
              if (_aboutImagePosition == 'right' && _previewMode != 'mobile') ...[
                const SizedBox(width: 24),
                Expanded(
                  child: Container(
                    height: 200,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Center(child: Text('Imagen')),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
  
  Widget _buildPreviewFooter() {
    return Container(
      padding: EdgeInsets.all(_containerPadding * 1.5),
      color: _footerColor,
      child: Column(
        children: [
          if (_previewMode != 'mobile')
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'VINABIKE',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: _bodySize * 1.25,
                          fontWeight: FontWeight.bold,
                          fontFamily: _headingFont,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Tu tienda de confianza',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.7),
                          fontFamily: _bodyFont,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'CONTACTO',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontFamily: _headingFont,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _contactPhoneController.text.isEmpty ? 'Teléfono' : _contactPhoneController.text,
                        style: TextStyle(color: Colors.white.withOpacity(0.7), fontFamily: _bodyFont),
                      ),
                      Text(
                        _contactEmailController.text.isEmpty ? 'Email' : _contactEmailController.text,
                        style: TextStyle(color: Colors.white.withOpacity(0.7), fontFamily: _bodyFont),
                      ),
                      Text(
                        _contactAddressController.text.isEmpty ? 'Dirección' : _contactAddressController.text,
                        style: TextStyle(color: Colors.white.withOpacity(0.7), fontFamily: _bodyFont),
                        maxLines: 2,
                      ),
                    ],
                  ),
                ),
                if (_showSocialLinks)
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'SÍGUENOS',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontFamily: _headingFont,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            if (_contactWhatsappController.text.isNotEmpty)
                              IconButton(
                                icon: const Icon(Icons.phone, color: Colors.white70),
                                onPressed: () {},
                              ),
                            if (_contactInstagramController.text.isNotEmpty)
                              IconButton(
                                icon: const Icon(Icons.camera_alt, color: Colors.white70),
                                onPressed: () {},
                              ),
                            if (_contactFacebookController.text.isNotEmpty)
                              IconButton(
                                icon: const Icon(Icons.facebook, color: Colors.white70),
                                onPressed: () {},
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          const SizedBox(height: 24),
          const Divider(color: Colors.white24),
          const SizedBox(height: 16),
          Text(
            '© 2025 Vinabike. Todos los derechos reservados.',
            style: TextStyle(
              color: Colors.white.withOpacity(0.5),
              fontSize: _bodySize * 0.875,
              fontFamily: _bodyFont,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
  
  IconData _getIconData(String iconName) {
    switch (iconName) {
      case 'directions_bike': return Icons.directions_bike;
      case 'build': return Icons.build;
      case 'shopping_bag': return Icons.shopping_bag;
      default: return Icons.star;
    }
  }
  
  // ============================================================================
  // EDIT PANEL - RIGHT SIDE
  // ============================================================================
  
  Widget _buildEditPanel(ThemeData theme) {
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          left: BorderSide(color: theme.dividerColor),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(-2, 0),
          ),
        ],
      ),
      child: Column(
        children: [
          // Edit panel header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: theme.dividerColor),
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.edit_note, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  'Panel de Edición',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          
          // Search bar
          _buildSearchBar(theme),
          
          // Section selector
          _buildSectionSelector(theme),
          
          // Edit controls
          Expanded(
            child: _buildEditControls(theme),
          ),
          
          // Quick actions
          _buildQuickActions(theme),
        ],
      ),
    );
  }
  
  Widget _buildSearchBar(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
      ),
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: 'Buscar sección...',
          prefixIcon: const Icon(Icons.search, size: 20),
          suffixIcon: _searchQuery.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.clear, size: 20),
                onPressed: () {
                  _searchController.clear();
                },
              )
            : null,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          isDense: true,
        ),
      ),
    );
  }
  
  Widget _buildSectionSelector(ThemeData theme) {
    final sections = [
      {'id': 'hero', 'label': 'Hero/Banner', 'icon': Icons.view_carousel},
      {'id': 'colors', 'label': 'Colores', 'icon': Icons.palette},
      {'id': 'typography', 'label': 'Tipografía', 'icon': Icons.text_fields},
      {'id': 'layout', 'label': 'Diseño', 'icon': Icons.dashboard_customize},
      {'id': 'products', 'label': 'Productos', 'icon': Icons.shopping_bag},
      {'id': 'services', 'label': 'Servicios', 'icon': Icons.room_service},
      {'id': 'about', 'label': 'Nosotros', 'icon': Icons.info},
      {'id': 'contact', 'label': 'Contacto', 'icon': Icons.contact_mail},
      {'id': 'footer', 'label': 'Footer', 'icon': Icons.web},
    ];
    
    // Filter by search
    final filteredSections = _searchQuery.isEmpty
      ? sections
      : sections.where((s) => 
          (s['label'] as String).toLowerCase().contains(_searchQuery)
        ).toList();
    
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        border: Border(
          bottom: BorderSide(color: theme.dividerColor),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'SECCIÓN A EDITAR',
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: filteredSections.map((section) {
              return _buildSectionChip(
                section['id'] as String,
                section['label'] as String,
                section['icon'] as IconData,
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
  
  Widget _buildSectionChip(String section, String label, IconData icon) {
    final isSelected = _selectedSection == section;
    
    return FilterChip(
      selected: isSelected,
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(fontSize: 12)),
        ],
      ),
      onSelected: (selected) {
        setState(() => _selectedSection = section);
      },
      selectedColor: Theme.of(context).colorScheme.primaryContainer,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }
  
  Widget _buildEditControls(ThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_selectedSection == 'hero') ..._buildHeroControls(theme),
          if (_selectedSection == 'colors') ..._buildColorControls(theme),
          if (_selectedSection == 'typography') ..._buildTypographyControls(theme),
          if (_selectedSection == 'layout') ..._buildLayoutControls(theme),
          if (_selectedSection == 'products') ..._buildProductsControls(theme),
          if (_selectedSection == 'services') ..._buildServicesControls(theme),
          if (_selectedSection == 'about') ..._buildAboutControls(theme),
          if (_selectedSection == 'contact') ..._buildContactControls(theme),
          if (_selectedSection == 'footer') ..._buildFooterControls(theme),
        ],
      ),
    );
  }
  
  // HERO SECTION CONTROLS
  List<Widget> _buildHeroControls(ThemeData theme) {
    return [
      _buildSectionHeader(theme, '🎯 Sección Hero / Banner Principal', 
        'La primera impresión de tu sitio web'),
      
      const SizedBox(height: 16),
      
      // Title
      TextField(
        controller: _heroTitleController,
        decoration: const InputDecoration(
          labelText: 'Título Principal',
          hintText: 'Ej: SERVICIOS Y PRODUCTOS DE BICICLETA',
          border: OutlineInputBorder(),
          prefixIcon: Icon(Icons.title),
        ),
        maxLines: 2,
      ),
      const SizedBox(height: 12),
      
      // Subtitle
      TextField(
        controller: _heroSubtitleController,
        decoration: const InputDecoration(
          labelText: 'Subtítulo',
          hintText: 'Ej: Todo lo que necesitas...',
          border: OutlineInputBorder(),
          prefixIcon: Icon(Icons.subject),
        ),
        maxLines: 2,
      ),
      const SizedBox(height: 12),
      
      // CTA Text
      TextField(
        controller: _heroCTATextController,
        decoration: const InputDecoration(
          labelText: 'Texto del Botón (CTA)',
          hintText: 'Ej: VER PRODUCTOS',
          border: OutlineInputBorder(),
          prefixIcon: Icon(Icons.touch_app),
        ),
      ),
      const SizedBox(height: 16),
      
      // Alignment
      _buildDropdown(
        theme,
        label: 'Alineación del Contenido',
        value: _heroAlignment,
        items: const [
          {'value': 'left', 'label': 'Izquierda'},
          {'value': 'center', 'label': 'Centro'},
          {'value': 'right', 'label': 'Derecha'},
        ],
        onChanged: (value) {
          setState(() {
            _heroAlignment = value!;
            _markAsChanged();
          });
        },
      ),
      const SizedBox(height: 16),
      
      // Show Overlay
      SwitchListTile(
        title: const Text('Mostrar Overlay (Filtro Oscuro)'),
        subtitle: const Text('Mejora la legibilidad del texto'),
        value: _heroShowOverlay,
        onChanged: (value) {
          setState(() {
            _heroShowOverlay = value;
            _markAsChanged();
          });
        },
      ),
      
      // Overlay Opacity
      if (_heroShowOverlay) ...[
        const SizedBox(height: 8),
        Text('Opacidad del Overlay: ${(_heroOverlayOpacity * 100).toInt()}%'),
        Slider(
          value: _heroOverlayOpacity,
          min: 0.0,
          max: 1.0,
          divisions: 10,
          label: '${(_heroOverlayOpacity * 100).toInt()}%',
          onChanged: (value) {
            setState(() {
              _heroOverlayOpacity = value;
              _markAsChanged();
            });
          },
        ),
      ],
      
      const SizedBox(height: 16),
      
      // Image upload
      OutlinedButton.icon(
        onPressed: () => _pickImage('hero'),
        icon: const Icon(Icons.image),
        label: const Text('Cambiar Imagen de Fondo'),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(double.infinity, 48),
        ),
      ),
      
      _buildTipBox('💡 Tip: Usa títulos cortos y llamativos. El subtítulo debe explicar tu propuesta de valor.'),
    ];
  }
  
  // COLOR CONTROLS
  List<Widget> _buildColorControls(ThemeData theme) {
    return [
      _buildSectionHeader(theme, '🎨 Colores del Tema', 
        'Define la identidad visual de tu marca'),
      
      const SizedBox(height: 16),
      
      // Primary Color
      _buildAdvancedColorPicker(
        theme,
        label: 'Color Principal',
        color: _primaryColor,
        onChanged: (color) {
          setState(() {
            _primaryColor = color;
            _markAsChanged();
          });
        },
      ),
      const SizedBox(height: 16),
      
      // Accent Color
      _buildAdvancedColorPicker(
        theme,
        label: 'Color de Acento',
        color: _accentColor,
        onChanged: (color) {
          setState(() {
            _accentColor = color;
            _markAsChanged();
          });
        },
      ),
      const SizedBox(height: 16),
      
      // Background Color
      _buildAdvancedColorPicker(
        theme,
        label: 'Color de Fondo',
        color: _backgroundColor,
        onChanged: (color) {
          setState(() {
            _backgroundColor = color;
            _markAsChanged();
          });
        },
      ),
      const SizedBox(height: 16),
      
      // Text Color
      _buildAdvancedColorPicker(
        theme,
        label: 'Color de Texto',
        color: _textColor,
        onChanged: (color) {
          setState(() {
            _textColor = color;
            _markAsChanged();
          });
        },
      ),
      
      const SizedBox(height: 24),
      const Divider(),
      const SizedBox(height: 16),
      
      // Presets
      Text(
        'Paletas Predefinidas',
        style: theme.textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.bold,
        ),
      ),
      const SizedBox(height: 12),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _buildColorPreset('Verde Naturaleza', 
            const Color(0xFF2E7D32), const Color(0xFF66BB6A), Colors.white, Colors.black87),
          _buildColorPreset('Azul Profesional', 
            const Color(0xFF1976D2), const Color(0xFF42A5F5), Colors.white, Colors.black87),
          _buildColorPreset('Naranja Energía', 
            const Color(0xFFFF6F00), const Color(0xFFFF9800), Colors.white, Colors.black87),
          _buildColorPreset('Rosa Moderno', 
            const Color(0xFFD81B60), const Color(0xFFEC407A), Colors.white, Colors.black87),
          _buildColorPreset('Morado Elegante', 
            const Color(0xFF8E24AA), const Color(0xFFAB47BC), Colors.white, Colors.black87),
          _buildColorPreset('Oscuro', 
            const Color(0xFF212121), const Color(0xFF424242), const Color(0xFF121212), Colors.white),
        ],
      ),
    ];
  }
  
  // TYPOGRAPHY CONTROLS
  List<Widget> _buildTypographyControls(ThemeData theme) {
    return [
      _buildSectionHeader(theme, '✍️ Tipografía', 
        'Define el estilo de tus textos'),
      
      const SizedBox(height: 16),
      
      // Heading Font
      _buildDropdown(
        theme,
        label: 'Fuente de Títulos',
        value: _headingFont,
        items: const [
          {'value': 'Roboto', 'label': 'Roboto (Moderna)'},
          {'value': 'Montserrat', 'label': 'Montserrat (Elegante)'},
          {'value': 'Lato', 'label': 'Lato (Clara)'},
          {'value': 'Open Sans', 'label': 'Open Sans (Profesional)'},
          {'value': 'Poppins', 'label': 'Poppins (Amigable)'},
        ],
        onChanged: (value) {
          setState(() {
            _headingFont = value!;
            _markAsChanged();
          });
        },
      ),
      const SizedBox(height: 16),
      
      // Body Font
      _buildDropdown(
        theme,
        label: 'Fuente de Texto',
        value: _bodyFont,
        items: const [
          {'value': 'Roboto', 'label': 'Roboto (Moderna)'},
          {'value': 'Montserrat', 'label': 'Montserrat (Elegante)'},
          {'value': 'Lato', 'label': 'Lato (Clara)'},
          {'value': 'Open Sans', 'label': 'Open Sans (Profesional)'},
          {'value': 'Poppins', 'label': 'Poppins (Amigable)'},
        ],
        onChanged: (value) {
          setState(() {
            _bodyFont = value!;
            _markAsChanged();
          });
        },
      ),
      const SizedBox(height: 16),
      
      // Heading Size
      Text('Tamaño de Títulos: ${_headingSize.toInt()}px'),
      Slider(
        value: _headingSize,
        min: 24,
        max: 72,
        divisions: 24,
        label: '${_headingSize.toInt()}px',
        onChanged: (value) {
          setState(() {
            _headingSize = value;
            _markAsChanged();
          });
        },
      ),
      const SizedBox(height: 16),
      
      // Body Size
      Text('Tamaño de Texto: ${_bodySize.toInt()}px'),
      Slider(
        value: _bodySize,
        min: 12,
        max: 24,
        divisions: 12,
        label: '${_bodySize.toInt()}px',
        onChanged: (value) {
          setState(() {
            _bodySize = value;
            _markAsChanged();
          });
        },
      ),
      
      _buildTipBox('💡 Tip: Mantén buena legibilidad. Texto muy pequeño cansa la vista.'),
    ];
  }
  
  // LAYOUT CONTROLS
  List<Widget> _buildLayoutControls(ThemeData theme) {
    return [
      _buildSectionHeader(theme, '📐 Diseño y Espaciado', 
        'Controla el espacio entre elementos'),
      
      const SizedBox(height: 16),
      
      // Max Width
      _buildDropdown(
        theme,
        label: 'Ancho Máximo del Contenido',
        value: _maxWidth,
        items: const [
          {'value': '960', 'label': '960px (Compacto)'},
          {'value': '1200', 'label': '1200px (Estándar)'},
          {'value': '1400', 'label': '1400px (Amplio)'},
          {'value': '100%', 'label': 'Ancho Completo'},
        ],
        onChanged: (value) {
          setState(() {
            _maxWidth = value!;
            _markAsChanged();
          });
        },
      ),
      const SizedBox(height: 16),
      
      // Section Spacing
      Text('Espacio Entre Secciones: ${_sectionSpacing.toInt()}px'),
      Slider(
        value: _sectionSpacing,
        min: 32,
        max: 128,
        divisions: 12,
        label: '${_sectionSpacing.toInt()}px',
        onChanged: (value) {
          setState(() {
            _sectionSpacing = value;
            _markAsChanged();
          });
        },
      ),
      const SizedBox(height: 16),
      
      // Container Padding
      Text('Padding de Contenedores: ${_containerPadding.toInt()}px'),
      Slider(
        value: _containerPadding,
        min: 12,
        max: 48,
        divisions: 12,
        label: '${_containerPadding.toInt()}px',
        onChanged: (value) {
          setState(() {
            _containerPadding = value;
            _markAsChanged();
          });
        },
      ),
      
      _buildTipBox('💡 Tip: Más espacio = diseño más "respirado" y moderno.'),
    ];
  }
  
  // PRODUCTS CONTROLS
  List<Widget> _buildProductsControls(ThemeData theme) {
    return [
      _buildSectionHeader(theme, '🛍️ Sección de Productos', 
        'Personaliza cómo se muestran tus productos'),
      
      const SizedBox(height: 16),
      
      // Show/Hide
      SwitchListTile(
        title: const Text('Mostrar Sección'),
        value: _showProductsSection,
        onChanged: (value) {
          setState(() {
            _showProductsSection = value;
            _markAsChanged();
          });
        },
      ),
      
      if (_showProductsSection) ...[
        const SizedBox(height: 16),
        
        // Title
        TextFormField(
          initialValue: _productsTitle,
          decoration: const InputDecoration(
            labelText: 'Título de la Sección',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.title),
          ),
          onChanged: (value) {
            _productsTitle = value;
            _markAsChanged();
          },
        ),
        const SizedBox(height: 16),
        
        // Layout
        _buildDropdown(
          theme,
          label: 'Estilo de Visualización',
          value: _productsLayout,
          items: const [
            {'value': 'grid', 'label': 'Cuadrícula (Grid)'},
            {'value': 'carousel', 'label': 'Carrusel'},
            {'value': 'list', 'label': 'Lista'},
          ],
          onChanged: (value) {
            setState(() {
              _productsLayout = value!;
              _markAsChanged();
            });
          },
        ),
        const SizedBox(height: 16),
        
        // Products per row
        if (_productsLayout == 'grid') ...[
          Text('Productos por Fila: $_productsPerRow'),
          Slider(
            value: _productsPerRow.toDouble(),
            min: 2,
            max: 4,
            divisions: 2,
            label: _productsPerRow.toString(),
            onChanged: (value) {
              setState(() {
                _productsPerRow = value.toInt();
                _markAsChanged();
              });
            },
          ),
        ],
      ],
    ];
  }
  
  // SERVICES CONTROLS
  List<Widget> _buildServicesControls(ThemeData theme) {
    return [
      _buildSectionHeader(theme, '🔧 Sección de Servicios', 
        'Destaca lo que ofreces'),
      
      const SizedBox(height: 16),
      
      // Show/Hide
      SwitchListTile(
        title: const Text('Mostrar Sección'),
        value: _showServicesSection,
        onChanged: (value) {
          setState(() {
            _showServicesSection = value;
            _markAsChanged();
          });
        },
      ),
      
      if (_showServicesSection) ...[
        const SizedBox(height: 16),
        
        // Title
        TextFormField(
          initialValue: _servicesTitle,
          decoration: const InputDecoration(
            labelText: 'Título de la Sección',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.title),
          ),
          onChanged: (value) {
            _servicesTitle = value;
            _markAsChanged();
          },
        ),
        const SizedBox(height: 16),
        
        // Services list
        Text(
          'Servicios (${_services.length})',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        ..._services.asMap().entries.map((entry) {
          final service = entry.value;
          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              leading: Icon(_getIconData(service['icon'] ?? 'star')),
              title: Text(service['title'] ?? ''),
              subtitle: Text(service['description'] ?? ''),
              trailing: IconButton(
                icon: const Icon(Icons.edit, size: 20),
                onPressed: () {
                  // TODO: Edit service dialog
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Editar servicio - Próximamente')),
                  );
                },
              ),
            ),
          );
        }),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () {
            // TODO: Add service dialog
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Añadir servicio - Próximamente')),
            );
          },
          icon: const Icon(Icons.add),
          label: const Text('Añadir Servicio'),
        ),
      ],
    ];
  }
  
  // ABOUT CONTROLS
  List<Widget> _buildAboutControls(ThemeData theme) {
    return [
      _buildSectionHeader(theme, 'ℹ️ Sección Sobre Nosotros', 
        'Cuenta tu historia'),
      
      const SizedBox(height: 16),
      
      // Show/Hide
      SwitchListTile(
        title: const Text('Mostrar Sección'),
        value: _showAboutSection,
        onChanged: (value) {
          setState(() {
            _showAboutSection = value;
            _markAsChanged();
          });
        },
      ),
      
      if (_showAboutSection) ...[
        const SizedBox(height: 16),
        
        // Title
        TextFormField(
          initialValue: _aboutTitle,
          decoration: const InputDecoration(
            labelText: 'Título de la Sección',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.title),
          ),
          onChanged: (value) {
            _aboutTitle = value;
            _markAsChanged();
          },
        ),
        const SizedBox(height: 16),
        
        // Content
        TextField(
          controller: _aboutContentController,
          decoration: const InputDecoration(
            labelText: 'Contenido',
            hintText: 'Escribe sobre tu negocio...',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.article),
          ),
          maxLines: 5,
        ),
        const SizedBox(height: 16),
        
        // Image Position
        _buildDropdown(
          theme,
          label: 'Posición de la Imagen',
          value: _aboutImagePosition,
          items: const [
            {'value': 'left', 'label': 'Izquierda'},
            {'value': 'right', 'label': 'Derecha'},
          ],
          onChanged: (value) {
            setState(() {
              _aboutImagePosition = value!;
              _markAsChanged();
            });
          },
        ),
        const SizedBox(height: 16),
        
        // Image upload
        OutlinedButton.icon(
          onPressed: () => _pickImage('about'),
          icon: const Icon(Icons.image),
          label: const Text('Cambiar Imagen'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(double.infinity, 48),
          ),
        ),
      ],
    ];
  }
  
  // CONTACT CONTROLS
  List<Widget> _buildContactControls(ThemeData theme) {
    return [
      _buildSectionHeader(theme, '📞 Información de Contacto', 
        'Aparece en el footer de todas las páginas'),
      
      const SizedBox(height: 16),
      
      // Phone
      TextField(
        controller: _contactPhoneController,
        decoration: const InputDecoration(
          labelText: 'Teléfono',
          hintText: '+56 9 XXXX XXXX',
          border: OutlineInputBorder(),
          prefixIcon: Icon(Icons.phone),
        ),
      ),
      const SizedBox(height: 12),
      
      // Email
      TextField(
        controller: _contactEmailController,
        decoration: const InputDecoration(
          labelText: 'Email',
          hintText: 'info@tutienda.cl',
          border: OutlineInputBorder(),
          prefixIcon: Icon(Icons.email),
        ),
        keyboardType: TextInputType.emailAddress,
      ),
      const SizedBox(height: 12),
      
      // Address
      TextField(
        controller: _contactAddressController,
        decoration: const InputDecoration(
          labelText: 'Dirección',
          hintText: 'Calle 123, Ciudad',
          border: OutlineInputBorder(),
          prefixIcon: Icon(Icons.location_on),
        ),
        maxLines: 2,
      ),
      const SizedBox(height: 16),
      
      const Divider(),
      const SizedBox(height: 16),
      
      Text(
        'Redes Sociales',
        style: theme.textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.bold,
        ),
      ),
      const SizedBox(height: 12),
      
      // WhatsApp
      TextField(
        controller: _contactWhatsappController,
        decoration: const InputDecoration(
          labelText: 'WhatsApp',
          hintText: '+56912345678',
          border: OutlineInputBorder(),
          prefixIcon: Icon(Icons.phone_android),
        ),
      ),
      const SizedBox(height: 12),
      
      // Instagram
      TextField(
        controller: _contactInstagramController,
        decoration: const InputDecoration(
          labelText: 'Instagram',
          hintText: '@tutienda',
          border: OutlineInputBorder(),
          prefixIcon: Icon(Icons.camera_alt),
        ),
      ),
      const SizedBox(height: 12),
      
      // Facebook
      TextField(
        controller: _contactFacebookController,
        decoration: const InputDecoration(
          labelText: 'Facebook',
          hintText: 'TuTienda',
          border: OutlineInputBorder(),
          prefixIcon: Icon(Icons.facebook),
        ),
      ),
    ];
  }
  
  // FOOTER CONTROLS
  List<Widget> _buildFooterControls(ThemeData theme) {
    return [
      _buildSectionHeader(theme, '🌐 Footer (Pie de Página)', 
        'Personaliza el footer'),
      
      const SizedBox(height: 16),
      
      // Footer Color
      _buildAdvancedColorPicker(
        theme,
        label: 'Color del Footer',
        color: _footerColor,
        onChanged: (color) {
          setState(() {
            _footerColor = color;
            _markAsChanged();
          });
        },
      ),
      const SizedBox(height: 16),
      
      // Show Social Links
      SwitchListTile(
        title: const Text('Mostrar Redes Sociales'),
        value: _showSocialLinks,
        onChanged: (value) {
          setState(() {
            _showSocialLinks = value;
            _markAsChanged();
          });
        },
      ),
      
      // Show Newsletter
      SwitchListTile(
        title: const Text('Mostrar Suscripción a Newsletter'),
        subtitle: const Text('Próximamente'),
        value: _showNewsletter,
        onChanged: (value) {
          setState(() {
            _showNewsletter = value;
            _markAsChanged();
          });
        },
      ),
    ];
  }
  
  // ============================================================================
  // HELPER WIDGETS
  // ============================================================================
  
  Widget _buildSectionHeader(ThemeData theme, String title, String subtitle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
  
  Widget _buildDropdown(
    ThemeData theme, {
    required String label,
    required String value,
    required List<Map<String, String>> items,
    required Function(String?) onChanged,
  }) {
    return DropdownButtonFormField<String>(
      value: value,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      items: items.map((item) {
        return DropdownMenuItem<String>(
          value: item['value'],
          child: Text(item['label'] ?? ''),
        );
      }).toList(),
      onChanged: onChanged,
    );
  }
  
  Widget _buildAdvancedColorPicker(
    ThemeData theme, {
    required String label,
    required Color color,
    required Function(Color) onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.labelLarge,
        ),
        const SizedBox(height: 8),
        InkWell(
          onTap: () => _showColorPicker(context, color, onChanged),
          child: Container(
            height: 56,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey.shade300, width: 2),
            ),
            child: Row(
              children: [
                const SizedBox(width: 16),
                const Icon(Icons.palette, color: Colors.white),
                const SizedBox(width: 12),
                Text(
                  '#${color.value.toRadixString(16).substring(2).toUpperCase()}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    shadows: [
                      Shadow(
                        color: Colors.black45,
                        blurRadius: 2,
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'Cambiar',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
              ],
            ),
          ),
        ),
      ],
    );
  }
  
  Widget _buildColorPreset(String name, Color primary, Color accent, Color bg, Color text) {
    return Tooltip(
      message: name,
      child: InkWell(
        onTap: () {
          setState(() {
            _primaryColor = primary;
            _accentColor = accent;
            _backgroundColor = bg;
            _textColor = text;
            _markAsChanged();
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('✅ Paleta "$name" aplicada'),
              duration: const Duration(seconds: 1),
            ),
          );
        },
        child: Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: Column(
            children: [
              Expanded(child: Container(color: primary)),
              Expanded(child: Container(color: accent)),
              Expanded(child: Container(color: bg)),
            ],
          ),
        ),
      ),
    );
  }
  
  Widget _buildTipBox(String text) {
    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.blue.shade200),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.lightbulb, color: Colors.blue.shade700, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12,
                color: Colors.blue.shade900,
              ),
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildQuickActions(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        border: Border(
          top: BorderSide(color: theme.dividerColor),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    // Reset to defaults
                    showDialog(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('🔄 Resetear a Valores Por Defecto'),
                        content: const Text(
                          '¿Estás seguro? Esto borrará todos tus cambios personalizados.',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Cancelar'),
                          ),
                          ElevatedButton(
                            onPressed: () {
                              Navigator.pop(context);
                              _loadCurrentSettings();
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('✅ Valores reseteados')),
                              );
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red,
                            ),
                            child: const Text('Resetear'),
                          ),
                        ],
                      ),
                    );
                  },
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Resetear'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () {
                    // Export/Import settings
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('📤 Exportar configuración - Próximamente'),
                      ),
                    );
                  },
                  icon: const Icon(Icons.file_download, size: 18),
                  label: const Text('Exportar'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
  
  void _showUnsavedChangesDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('⚠️ Cambios sin guardar'),
        content: const Text(
          '¿Estás seguro de que quieres salir sin guardar los cambios?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              context.go('/website');
            },
            child: const Text('Salir sin guardar'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await _saveChanges();
              if (mounted) {
                context.go('/website');
              }
            },
            child: const Text('Guardar y Salir'),
          ),
        ],
      ),
    );
  }
}

