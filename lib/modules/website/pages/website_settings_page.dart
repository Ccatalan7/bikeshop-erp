import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/website_service.dart';

/// Page for configuring website settings
class WebsiteSettingsPage extends StatefulWidget {
  const WebsiteSettingsPage({super.key});

  @override
  State<WebsiteSettingsPage> createState() => _WebsiteSettingsPageState();
}

class _WebsiteSettingsPageState extends State<WebsiteSettingsPage> {
  final _formKey = GlobalKey<FormState>();
  
  // Store info
  late final TextEditingController _storeNameController;
  late final TextEditingController _storeUrlController;
  late final TextEditingController _storeDescriptionController;
  
  // Contact info
  late final TextEditingController _contactEmailController;
  late final TextEditingController _contactPhoneController;
  late final TextEditingController _contactAddressController;
  late final TextEditingController _whatsappController;
  
  // Social media
  late final TextEditingController _facebookController;
  late final TextEditingController _instagramController;
  late final TextEditingController _twitterController;
  late final TextEditingController _youtubeController;
  
  // SEO
  late final TextEditingController _metaTitleController;
  late final TextEditingController _metaDescriptionController;
  late final TextEditingController _metaKeywordsController;
  
  // Feature toggles
  bool _enableOrders = true;
  bool _showPrices = true;
  bool _requireLogin = false;
  bool _enableReviews = false;
  bool _showStock = true;
  
  bool _isLoading = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    
    // Initialize controllers
    _storeNameController = TextEditingController();
    _storeUrlController = TextEditingController();
    _storeDescriptionController = TextEditingController();
    _contactEmailController = TextEditingController();
    _contactPhoneController = TextEditingController();
    _contactAddressController = TextEditingController();
    _whatsappController = TextEditingController();
    _facebookController = TextEditingController();
    _instagramController = TextEditingController();
    _twitterController = TextEditingController();
    _youtubeController = TextEditingController();
    _metaTitleController = TextEditingController();
    _metaDescriptionController = TextEditingController();
    _metaKeywordsController = TextEditingController();
    
    // Load settings
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadSettings();
    });
  }

  @override
  void dispose() {
    _storeNameController.dispose();
    _storeUrlController.dispose();
    _storeDescriptionController.dispose();
    _contactEmailController.dispose();
    _contactPhoneController.dispose();
    _contactAddressController.dispose();
    _whatsappController.dispose();
    _facebookController.dispose();
    _instagramController.dispose();
    _twitterController.dispose();
    _youtubeController.dispose();
    _metaTitleController.dispose();
    _metaDescriptionController.dispose();
    _metaKeywordsController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    setState(() => _isLoading = true);
    
    try {
      final service = context.read<WebsiteService>();
      await service.loadSettings();
      
      if (mounted) {
        setState(() {
          // Store info
          _storeNameController.text = service.getSetting('store_name', 'Vinabike');
          _storeUrlController.text = service.getSetting('store_url', 'https://tienda.vinabike.cl');
          _storeDescriptionController.text = service.getSetting('store_description', 'Tienda de bicicletas y accesorios en Chile');
          
          // Contact
          _contactEmailController.text = service.getSetting('contact_email', 'contacto@vinabike.cl');
          _contactPhoneController.text = service.getSetting('contact_phone', '+56 2 2345 6789');
          _contactAddressController.text = service.getSetting('contact_address', 'Av. Providencia 123, Santiago');
          _whatsappController.text = service.getSetting('whatsapp', '+56912345678');
          
          // Social media
          _facebookController.text = service.getSetting('facebook', 'vinabikechile');
          _instagramController.text = service.getSetting('instagram', '@vinabikecl');
          _twitterController.text = service.getSetting('twitter', '@vinabike');
          _youtubeController.text = service.getSetting('youtube', '@vinabikechannel');
          
          // SEO
          _metaTitleController.text = service.getSetting('meta_title', 'Vinabike - Tienda de Bicicletas');
          _metaDescriptionController.text = service.getSetting('meta_description', 'Las mejores bicicletas y accesorios en Chile. Envío a todo el país.');
          _metaKeywordsController.text = service.getSetting('meta_keywords', 'bicicletas, mtb, ruta, accesorios, ciclismo, chile');
          
          // Feature toggles
          _enableOrders = service.getSetting('enable_orders', 'true') == 'true';
          _showPrices = service.getSetting('show_prices', 'true') == 'true';
          _requireLogin = service.getSetting('require_login', 'false') == 'true';
          _enableReviews = service.getSetting('enable_reviews', 'false') == 'true';
          _showStock = service.getSetting('show_stock', 'true') == 'true';
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('Configuración del Sitio'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadSettings,
            tooltip: 'Recargar',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  // Store Information Section
                  _buildSection(
                    icon: Icons.store,
                    title: 'Información de la Tienda',
                    color: Colors.blue,
                    children: [
                      TextFormField(
                        controller: _storeNameController,
                        decoration: const InputDecoration(
                          labelText: 'Nombre de la Tienda',
                          hintText: 'Ej: Vinabike',
                          prefixIcon: Icon(Icons.storefront),
                        ),
                        validator: (value) =>
                            value?.isEmpty ?? true ? 'Campo requerido' : null,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _storeUrlController,
                        decoration: const InputDecoration(
                          labelText: 'URL de la Tienda',
                          hintText: 'https://tienda.ejemplo.cl',
                          prefixIcon: Icon(Icons.link),
                        ),
                        validator: (value) {
                          if (value?.isEmpty ?? true) return 'Campo requerido';
                          if (!value!.startsWith('http')) {
                            return 'Debe comenzar con http:// o https://';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _storeDescriptionController,
                        decoration: const InputDecoration(
                          labelText: 'Descripción',
                          hintText: 'Breve descripción de tu tienda',
                          prefixIcon: Icon(Icons.description),
                        ),
                        maxLines: 3,
                      ),
                    ],
                  ),

                  const SizedBox(height: 32),

                  // Contact Information Section
                  _buildSection(
                    icon: Icons.contact_mail,
                    title: 'Información de Contacto',
                    color: Colors.green,
                    children: [
                      TextFormField(
                        controller: _contactEmailController,
                        decoration: const InputDecoration(
                          labelText: 'Email de Contacto',
                          hintText: 'contacto@ejemplo.cl',
                          prefixIcon: Icon(Icons.email),
                        ),
                        keyboardType: TextInputType.emailAddress,
                        validator: (value) {
                          if (value?.isEmpty ?? true) return 'Campo requerido';
                          if (!value!.contains('@')) return 'Email inválido';
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _contactPhoneController,
                        decoration: const InputDecoration(
                          labelText: 'Teléfono',
                          hintText: '+56 2 2345 6789',
                          prefixIcon: Icon(Icons.phone),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _whatsappController,
                        decoration: const InputDecoration(
                          labelText: 'WhatsApp',
                          hintText: '+56912345678',
                          prefixIcon: Icon(Icons.chat),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _contactAddressController,
                        decoration: const InputDecoration(
                          labelText: 'Dirección',
                          hintText: 'Calle, Ciudad',
                          prefixIcon: Icon(Icons.location_on),
                        ),
                        maxLines: 2,
                      ),
                    ],
                  ),

                  const SizedBox(height: 32),

                  // Social Media Section
                  _buildSection(
                    icon: Icons.share,
                    title: 'Redes Sociales',
                    color: Colors.purple,
                    children: [
                      TextFormField(
                        controller: _facebookController,
                        decoration: InputDecoration(
                          labelText: 'Facebook',
                          hintText: 'usuario o URL',
                          prefixIcon: Icon(Icons.facebook, color: Colors.blue[700]),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _instagramController,
                        decoration: InputDecoration(
                          labelText: 'Instagram',
                          hintText: '@usuario',
                          prefixIcon: Icon(Icons.camera_alt, color: Colors.pink[400]),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _twitterController,
                        decoration: InputDecoration(
                          labelText: 'Twitter / X',
                          hintText: '@usuario',
                          prefixIcon: Icon(Icons.alternate_email, color: Colors.blue[400]),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _youtubeController,
                        decoration: InputDecoration(
                          labelText: 'YouTube',
                          hintText: '@canal',
                          prefixIcon: Icon(Icons.video_library, color: Colors.red[600]),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 32),

                  // SEO Section
                  _buildSection(
                    icon: Icons.search,
                    title: 'SEO - Optimización en Buscadores',
                    color: Colors.orange,
                    children: [
                      TextFormField(
                        controller: _metaTitleController,
                        decoration: const InputDecoration(
                          labelText: 'Título SEO',
                          hintText: 'Título que aparece en Google',
                          prefixIcon: Icon(Icons.title),
                          helperText: 'Máximo 60 caracteres',
                        ),
                        maxLength: 60,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _metaDescriptionController,
                        decoration: const InputDecoration(
                          labelText: 'Meta Descripción',
                          hintText: 'Descripción que aparece en resultados de búsqueda',
                          prefixIcon: Icon(Icons.description),
                          helperText: 'Máximo 160 caracteres',
                        ),
                        maxLines: 3,
                        maxLength: 160,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _metaKeywordsController,
                        decoration: const InputDecoration(
                          labelText: 'Palabras Clave',
                          hintText: 'palabra1, palabra2, palabra3',
                          prefixIcon: Icon(Icons.label),
                          helperText: 'Separadas por comas',
                        ),
                        maxLines: 2,
                      ),
                    ],
                  ),

                  const SizedBox(height: 32),

                  // Feature Toggles Section
                  _buildSection(
                    icon: Icons.tune,
                    title: 'Funcionalidades',
                    color: Colors.teal,
                    children: [
                      SwitchListTile(
                        title: const Text('Habilitar Pedidos Online'),
                        subtitle: const Text('Los clientes pueden hacer compras'),
                        value: _enableOrders,
                        onChanged: (value) => setState(() => _enableOrders = value),
                        secondary: Icon(
                          Icons.shopping_cart,
                          color: _enableOrders ? Colors.green : Colors.grey,
                        ),
                      ),
                      const Divider(),
                      SwitchListTile(
                        title: const Text('Mostrar Precios'),
                        subtitle: const Text('Precios visibles para visitantes'),
                        value: _showPrices,
                        onChanged: (value) => setState(() => _showPrices = value),
                        secondary: Icon(
                          Icons.attach_money,
                          color: _showPrices ? Colors.green : Colors.grey,
                        ),
                      ),
                      const Divider(),
                      SwitchListTile(
                        title: const Text('Mostrar Stock'),
                        subtitle: const Text('Cantidad disponible visible'),
                        value: _showStock,
                        onChanged: (value) => setState(() => _showStock = value),
                        secondary: Icon(
                          Icons.inventory,
                          color: _showStock ? Colors.green : Colors.grey,
                        ),
                      ),
                      const Divider(),
                      SwitchListTile(
                        title: const Text('Requiere Login para Comprar'),
                        subtitle: const Text('Los clientes deben crear cuenta'),
                        value: _requireLogin,
                        onChanged: (value) => setState(() => _requireLogin = value),
                        secondary: Icon(
                          Icons.login,
                          color: _requireLogin ? Colors.orange : Colors.grey,
                        ),
                      ),
                      const Divider(),
                      SwitchListTile(
                        title: const Text('Habilitar Reseñas'),
                        subtitle: const Text('Los clientes pueden dejar comentarios'),
                        value: _enableReviews,
                        onChanged: (value) => setState(() => _enableReviews = value),
                        secondary: Icon(
                          Icons.star,
                          color: _enableReviews ? Colors.amber : Colors.grey,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 32),

                  // Save Button
                  ElevatedButton.icon(
                    onPressed: _isSaving ? null : _saveSettings,
                    icon: _isSaving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save),
                    label: Text(_isSaving ? 'Guardando...' : 'Guardar Configuración'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      minimumSize: const Size.fromHeight(50),
                    ),
                  ),

                  const SizedBox(height: 32),
                ],
              ),
            ),
    );
  }

  Widget _buildSection({
    required IconData icon,
    required String title,
    required Color color,
    required List<Widget> children,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(width: 12),
            Text(
              title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Card(
          elevation: 1,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: children,
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _saveSettings() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      final service = context.read<WebsiteService>();
      
      // Save all settings
      final settings = {
        // Store
        'store_name': _storeNameController.text,
        'store_url': _storeUrlController.text,
        'store_description': _storeDescriptionController.text,
        
        // Contact
        'contact_email': _contactEmailController.text,
        'contact_phone': _contactPhoneController.text,
        'contact_address': _contactAddressController.text,
        'whatsapp': _whatsappController.text,
        
        // Social
        'facebook': _facebookController.text,
        'instagram': _instagramController.text,
        'twitter': _twitterController.text,
        'youtube': _youtubeController.text,
        
        // SEO
        'meta_title': _metaTitleController.text,
        'meta_description': _metaDescriptionController.text,
        'meta_keywords': _metaKeywordsController.text,
        
        // Features
        'enable_orders': _enableOrders.toString(),
        'show_prices': _showPrices.toString(),
        'require_login': _requireLogin.toString(),
        'enable_reviews': _enableReviews.toString(),
        'show_stock': _showStock.toString(),
      };

      for (final entry in settings.entries) {
        await service.saveSetting(entry.key, entry.value);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Configuración guardada exitosamente'),
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
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }
}

