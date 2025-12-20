import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/website_edit_mode_provider.dart';
import '../services/website_service.dart';

/// Floating toolbar that appears at the top when in edit mode.
/// Provides save, cancel, and add block actions.
class InlineEditToolbar extends StatelessWidget {
  final VoidCallback? onSave;
  final VoidCallback? onCancel;
  final VoidCallback? onAddBlock;
  final VoidCallback? onPreview;

  const InlineEditToolbar({
    super.key,
    this.onSave,
    this.onCancel,
    this.onAddBlock,
    this.onPreview,
  });

  @override
  Widget build(BuildContext context) {
    final editProvider = context.watch<WebsiteEditModeProvider>();
    
    if (!editProvider.isEditMode) {
      return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.grey.shade900,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: SafeArea(
        bottom: false,
        child: Row(
          children: [
            // Edit mode indicator
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.blue,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.edit, color: Colors.white, size: 16),
                  SizedBox(width: 6),
                  Text(
                    'Modo Edición',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            
            const SizedBox(width: 16),
            
            // Unsaved changes indicator
            if (editProvider.hasUnsavedChanges)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.orange.shade700,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.warning_amber, color: Colors.white, size: 14),
                    SizedBox(width: 4),
                    Text(
                      'Sin guardar',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),

            const Spacer(),

            // Settings button (header, footer, logo, contact)
            TextButton.icon(
              onPressed: () => _showSettingsDialog(context),
              icon: const Icon(Icons.settings, color: Colors.white, size: 18),
              label: const Text(
                'Configuración',
                style: TextStyle(color: Colors.white),
              ),
              style: TextButton.styleFrom(
                backgroundColor: Colors.grey.shade700,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              ),
            ),

            const SizedBox(width: 12),

            // Add block button
            TextButton.icon(
              onPressed: onAddBlock,
              icon: const Icon(Icons.add, color: Colors.white, size: 18),
              label: const Text(
                'Agregar Bloque',
                style: TextStyle(color: Colors.white),
              ),
              style: TextButton.styleFrom(
                backgroundColor: Colors.grey.shade700,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              ),
            ),

            const SizedBox(width: 12),

            // Preview button
            if (onPreview != null)
              TextButton.icon(
                onPressed: onPreview,
                icon: const Icon(Icons.visibility, color: Colors.white, size: 18),
                label: const Text(
                  'Vista Previa',
                  style: TextStyle(color: Colors.white),
                ),
                style: TextButton.styleFrom(
                  backgroundColor: Colors.grey.shade700,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                ),
              ),

            const SizedBox(width: 12),

            // Cancel button
            TextButton(
              onPressed: onCancel,
              child: const Text(
                'Cancelar',
                style: TextStyle(color: Colors.white70),
              ),
            ),

            const SizedBox(width: 8),

            // Save button
            ElevatedButton.icon(
              onPressed: editProvider.hasUnsavedChanges ? onSave : null,
              icon: const Icon(Icons.save, size: 18),
              label: const Text('Guardar'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                disabledBackgroundColor: Colors.grey.shade600,
                disabledForegroundColor: Colors.grey.shade400,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showSettingsDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => const WebsiteSettingsDialog(),
    );
  }
}

/// Dialog for editing website settings (header, footer, logo, contact info)
class WebsiteSettingsDialog extends StatefulWidget {
  const WebsiteSettingsDialog({super.key});

  @override
  State<WebsiteSettingsDialog> createState() => _WebsiteSettingsDialogState();
}

class _WebsiteSettingsDialogState extends State<WebsiteSettingsDialog> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  
  // Controllers for all settings
  final _storeNameController = TextEditingController();
  final _storeDescriptionController = TextEditingController();
  final _logoUrlController = TextEditingController();
  final _contactEmailController = TextEditingController();
  final _contactPhoneController = TextEditingController();
  final _contactAddressController = TextEditingController();
  final _whatsappController = TextEditingController();
  final _facebookController = TextEditingController();
  final _instagramController = TextEditingController();
  final _twitterController = TextEditingController();
  final _youtubeController = TextEditingController();
  final _topBannerTextController = TextEditingController();
  final _primaryColorController = TextEditingController();
  final _accentColorController = TextEditingController();
  
  bool _isLoading = false;
  bool _hasChanges = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _loadCurrentSettings();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _storeNameController.dispose();
    _storeDescriptionController.dispose();
    _logoUrlController.dispose();
    _contactEmailController.dispose();
    _contactPhoneController.dispose();
    _contactAddressController.dispose();
    _whatsappController.dispose();
    _facebookController.dispose();
    _instagramController.dispose();
    _twitterController.dispose();
    _youtubeController.dispose();
    _topBannerTextController.dispose();
    _primaryColorController.dispose();
    _accentColorController.dispose();
    super.dispose();
  }

  void _loadCurrentSettings() {
    final websiteService = context.read<WebsiteService>();
    
    _storeNameController.text = websiteService.getSetting('store_name', '');
    _storeDescriptionController.text = websiteService.getSetting('store_description', '');
    _logoUrlController.text = websiteService.getSetting('logo_url', '');
    _contactEmailController.text = websiteService.getSetting('contact_email', '');
    _contactPhoneController.text = websiteService.getSetting('contact_phone', '');
    _contactAddressController.text = websiteService.getSetting('contact_address', '');
    _whatsappController.text = websiteService.getSetting('whatsapp', '');
    _facebookController.text = websiteService.getSetting('facebook', '');
    _instagramController.text = websiteService.getSetting('instagram', '');
    _twitterController.text = websiteService.getSetting('twitter', '');
    _youtubeController.text = websiteService.getSetting('youtube', '');
    _topBannerTextController.text = websiteService.getSetting('top_banner_text', 'Envíos a todo Chile');
    _primaryColorController.text = websiteService.getSetting('theme_primary_color', '');
    _accentColorController.text = websiteService.getSetting('theme_accent_color', '');
    
    // Add listeners to track changes
    for (final controller in [
      _storeNameController, _storeDescriptionController, _logoUrlController,
      _contactEmailController, _contactPhoneController, _contactAddressController,
      _whatsappController, _facebookController, _instagramController,
      _twitterController, _youtubeController, _topBannerTextController,
      _primaryColorController, _accentColorController,
    ]) {
      controller.addListener(() {
        if (!_hasChanges && mounted) {
          setState(() => _hasChanges = true);
        }
      });
    }
  }

  Future<void> _saveSettings() async {
    setState(() => _isLoading = true);
    
    try {
      final websiteService = context.read<WebsiteService>();
      final editProvider = context.read<WebsiteEditModeProvider>();
      
      // Save all settings
      await websiteService.saveSettings({
        'store_name': _storeNameController.text,
        'store_description': _storeDescriptionController.text,
        'logo_url': _logoUrlController.text,
        'contact_email': _contactEmailController.text,
        'contact_phone': _contactPhoneController.text,
        'contact_address': _contactAddressController.text,
        'whatsapp': _whatsappController.text,
        'facebook': _facebookController.text,
        'instagram': _instagramController.text,
        'twitter': _twitterController.text,
        'youtube': _youtubeController.text,
        'top_banner_text': _topBannerTextController.text,
        'theme_primary_color': _primaryColorController.text,
        'theme_accent_color': _accentColorController.text,
      });
      
      // Mark as having changes so save button stays enabled
      editProvider.updateSetting('_settingsChanged', true);
      
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Configuración guardada'),
            backgroundColor: Colors.green,
          ),
        );
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
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        width: 600,
        height: 550,
        padding: const EdgeInsets.all(0),
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.settings, color: Colors.blue),
                  const SizedBox(width: 12),
                  const Text(
                    'Configuración del Sitio',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            
            // Tabs
            TabBar(
              controller: _tabController,
              labelColor: Colors.blue,
              unselectedLabelColor: Colors.grey,
              tabs: const [
                Tab(icon: Icon(Icons.store), text: 'General'),
                Tab(icon: Icon(Icons.contact_mail), text: 'Contacto'),
                Tab(icon: Icon(Icons.share), text: 'Redes'),
                Tab(icon: Icon(Icons.palette), text: 'Colores'),
              ],
            ),
            
            // Tab content
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildGeneralTab(),
                  _buildContactTab(),
                  _buildSocialTab(),
                  _buildColorsTab(),
                ],
              ),
            ),
            
            // Footer with save button
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                border: Border(top: BorderSide(color: Colors.grey.shade300)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancelar'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    onPressed: _hasChanges && !_isLoading ? _saveSettings : null,
                    icon: _isLoading 
                        ? const SizedBox(
                            width: 16, 
                            height: 16, 
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.save),
                    label: const Text('Guardar Configuración'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
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

  Widget _buildGeneralTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildTextField(
            controller: _storeNameController,
            label: 'Nombre de la Tienda',
            hint: 'Mi Tienda de Bicicletas',
            icon: Icons.store,
          ),
          const SizedBox(height: 16),
          _buildTextField(
            controller: _storeDescriptionController,
            label: 'Descripción',
            hint: 'Tu slogan o descripción corta',
            icon: Icons.description,
            maxLines: 2,
          ),
          const SizedBox(height: 16),
          _buildTextField(
            controller: _logoUrlController,
            label: 'URL del Logo',
            hint: 'https://ejemplo.com/logo.png',
            icon: Icons.image,
            helperText: 'Deja vacío para usar texto como logo',
          ),
          const SizedBox(height: 16),
          _buildTextField(
            controller: _topBannerTextController,
            label: 'Texto del Banner Superior',
            hint: 'Envíos a todo Chile',
            icon: Icons.announcement,
          ),
        ],
      ),
    );
  }

  Widget _buildContactTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildTextField(
            controller: _contactEmailController,
            label: 'Email de Contacto',
            hint: 'contacto@tutienda.cl',
            icon: Icons.email,
          ),
          const SizedBox(height: 16),
          _buildTextField(
            controller: _contactPhoneController,
            label: 'Teléfono',
            hint: '+56 9 1234 5678',
            icon: Icons.phone,
          ),
          const SizedBox(height: 16),
          _buildTextField(
            controller: _whatsappController,
            label: 'WhatsApp',
            hint: '+56912345678 (sin espacios)',
            icon: Icons.message,
            helperText: 'Número para botón flotante de WhatsApp',
          ),
          const SizedBox(height: 16),
          _buildTextField(
            controller: _contactAddressController,
            label: 'Dirección',
            hint: 'Calle 123, Ciudad',
            icon: Icons.location_on,
            maxLines: 2,
          ),
        ],
      ),
    );
  }

  Widget _buildSocialTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildTextField(
            controller: _facebookController,
            label: 'Facebook',
            hint: 'https://facebook.com/tutienda',
            icon: Icons.facebook,
          ),
          const SizedBox(height: 16),
          _buildTextField(
            controller: _instagramController,
            label: 'Instagram',
            hint: '@tutienda',
            icon: Icons.camera_alt,
          ),
          const SizedBox(height: 16),
          _buildTextField(
            controller: _twitterController,
            label: 'Twitter / X',
            hint: '@tutienda',
            icon: Icons.alternate_email,
          ),
          const SizedBox(height: 16),
          _buildTextField(
            controller: _youtubeController,
            label: 'YouTube',
            hint: '@tucanalyt',
            icon: Icons.play_circle,
          ),
        ],
      ),
    );
  }

  Widget _buildColorsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Colores del Tema',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 8),
          const Text(
            'Ingresa colores en formato hexadecimal (ej: #1B5E20)',
            style: TextStyle(color: Colors.grey, fontSize: 13),
          ),
          const SizedBox(height: 24),
          _buildColorField(
            controller: _primaryColorController,
            label: 'Color Primario',
            defaultColor: '#1B5E20',
            description: 'Color del header, botones principales, enlaces',
          ),
          const SizedBox(height: 24),
          _buildColorField(
            controller: _accentColorController,
            label: 'Color de Acento',
            defaultColor: '#FF6D00',
            description: 'Color de botones destacados, llamados a acción',
          ),
        ],
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    String? helperText,
    int maxLines = 1,
  }) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        helperText: helperText,
        prefixIcon: Icon(icon),
        border: const OutlineInputBorder(),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
      ),
    );
  }

  Widget _buildColorField({
    required TextEditingController controller,
    required String label,
    required String defaultColor,
    required String description,
  }) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            decoration: InputDecoration(
              labelText: label,
              hintText: defaultColor,
              helperText: description,
              border: const OutlineInputBorder(),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            color: _parseColor(controller.text.isEmpty ? defaultColor : controller.text),
            border: Border.all(color: Colors.grey),
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ],
    );
  }

  Color _parseColor(String value) {
    try {
      String hex = value.replaceAll('#', '');
      if (hex.length == 6) {
        hex = 'FF$hex';
      }
      return Color(int.parse(hex, radix: 16));
    } catch (_) {
      return Colors.grey;
    }
  }
}

/// Floating block action bar that appears when a block is selected.
class BlockActionBar extends StatelessWidget {
  final String blockId;
  final String blockType;
  final bool isFirst;
  final bool isLast;
  final bool isVisible;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;
  final VoidCallback? onDuplicate;
  final VoidCallback? onDelete;
  final VoidCallback? onToggleVisibility;

  const BlockActionBar({
    super.key,
    required this.blockId,
    required this.blockType,
    this.isFirst = false,
    this.isLast = false,
    this.isVisible = true,
    this.onMoveUp,
    this.onMoveDown,
    this.onDuplicate,
    this.onDelete,
    this.onToggleVisibility,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.blue,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Block type label
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              _blockTypeLabel(blockType),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),

          const SizedBox(width: 8),

          // Move up
          if (!isFirst)
            _ActionButton(
              icon: Icons.arrow_upward,
              tooltip: 'Mover arriba',
              onPressed: onMoveUp,
            ),

          // Move down
          if (!isLast)
            _ActionButton(
              icon: Icons.arrow_downward,
              tooltip: 'Mover abajo',
              onPressed: onMoveDown,
            ),

          _ActionButton(
            icon: isVisible ? Icons.visibility : Icons.visibility_off,
            tooltip: isVisible ? 'Ocultar' : 'Mostrar',
            onPressed: onToggleVisibility,
          ),

          _ActionButton(
            icon: Icons.copy,
            tooltip: 'Duplicar',
            onPressed: onDuplicate,
          ),

          _ActionButton(
            icon: Icons.delete,
            tooltip: 'Eliminar',
            onPressed: onDelete,
            isDestructive: true,
          ),
        ],
      ),
    );
  }

  String _blockTypeLabel(String type) {
    switch (type) {
      case 'hero':
        return 'HERO';
      case 'products':
        return 'PRODUCTOS';
      case 'about':
        return 'NOSOTROS';
      case 'services':
        return 'SERVICIOS';
      case 'testimonials':
        return 'TESTIMONIOS';
      case 'contact':
        return 'CONTACTO';
      case 'cta':
        return 'CTA';
      case 'gallery':
        return 'GALERÍA';
      case 'banner':
        return 'BANNER';
      default:
        return type.toUpperCase();
    }
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool isDestructive;

  const _ActionButton({
    required this.icon,
    required this.tooltip,
    this.onPressed,
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
            color: isDestructive ? Colors.red.shade200 : Colors.white,
            size: 18,
          ),
        ),
      ),
    );
  }
}

/// Dialog for adding a new block
class AddBlockDialog extends StatelessWidget {
  const AddBlockDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final blockTypes = [
      ('hero', 'Hero Banner', Icons.view_carousel, 'Banner principal con imagen y texto'),
      ('carousel', 'Carrusel', Icons.view_carousel_outlined, 'Carrusel de imágenes rotativas'),
      ('canvas', 'Canvas', Icons.dashboard_customize_outlined, 'Sección libre con elementos arrastrables (texto/botón)'),
      ('text', 'Texto', Icons.text_fields, 'Texto libre con edición inline'),
      ('button', 'Botón', Icons.smart_button, 'Botón con enlace (a páginas o secciones)'),
      ('divider', 'Separador', Icons.horizontal_rule, 'Línea/separador entre secciones'),
      ('products', 'Productos', Icons.shopping_bag, 'Muestra productos destacados'),
      ('about', 'Sobre Nosotros', Icons.info, 'Sección informativa'),
      ('services', 'Servicios', Icons.build, 'Lista de servicios'),
      ('features', 'Características', Icons.star, '¿Por qué elegirnos? / Beneficios'),
      ('testimonials', 'Testimonios', Icons.format_quote, 'Opiniones de clientes'),
      ('stats', 'Estadísticas', Icons.analytics, 'Números y métricas destacadas'),
      ('team', 'Equipo', Icons.people, 'Miembros del equipo'),
      ('faq', 'Preguntas Frecuentes', Icons.help_outline, 'FAQ / Preguntas y respuestas'),
      ('pricing', 'Precios', Icons.attach_money, 'Planes y precios'),
      ('contact', 'Contacto', Icons.contact_mail, 'Formulario de contacto'),
      ('cta', 'Llamado a Acción', Icons.touch_app, 'Botón con mensaje'),
      ('gallery', 'Galería', Icons.photo_library, 'Galería de imágenes'),
    ];

    return AlertDialog(
      title: const Text('Agregar Bloque'),
      content: SizedBox(
        width: 400,
        height: 450,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Selecciona el tipo de bloque que deseas agregar:',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: ListView(
                children: blockTypes.map((type) => ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.blue.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(type.$3, color: Colors.blue),
                  ),
                  title: Text(type.$2),
                  subtitle: Text(type.$4, style: const TextStyle(fontSize: 12)),
                  onTap: () => Navigator.pop(context, type.$1),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  hoverColor: Colors.blue.withValues(alpha: 0.05),
                )).toList(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
      ],
    );
  }
}
