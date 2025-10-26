import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:go_router/go_router.dart';
import '../../../shared/services/tenant_service.dart';
import 'odoo_style_editor_page.dart';
import '../templates/website_templates.dart';

/// 🚀 Website Setup Wizard
/// 
/// Guides new tenants through:
/// 1. Choose template
/// 2. Configure basic info (shop name, subdomain)
/// 3. Deploy website to Firebase
/// 4. Configure custom domain (optional)
class WebsiteSetupWizardPage extends StatefulWidget {
  const WebsiteSetupWizardPage({super.key});

  @override
  State<WebsiteSetupWizardPage> createState() => _WebsiteSetupWizardPageState();
}

class _WebsiteSetupWizardPageState extends State<WebsiteSetupWizardPage> {
  int _currentStep = 0;
  
  // Step 1: Template Selection
  String _selectedTemplate = 'modern-store';
  
  // Step 2: Configuration
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _shopNameController = TextEditingController();
  final TextEditingController _subdomainController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  bool _subdomainAvailable = false;
  bool _checkingSubdomain = false;
  
  // Step 3: Deployment
  bool _isDeploying = false;
  String _deploymentStatus = '';
  String? _websiteUrl;
  
  // Step 4: Custom Domain (optional)
  final TextEditingController _customDomainController = TextEditingController();
  
  @override
  void dispose() {
    _shopNameController.dispose();
    _subdomainController.dispose();
    _descriptionController.dispose();
    _customDomainController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Configurar Mi Sitio Web'),
        backgroundColor: theme.colorScheme.surface,
        elevation: 0,
      ),
      body: Stepper(
        currentStep: _currentStep,
        onStepContinue: _onStepContinue,
        onStepCancel: _onStepCancel,
        controlsBuilder: (context, details) {
          return Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Row(
              children: [
                if (_currentStep > 0 && !_isDeploying)
                  TextButton(
                    onPressed: details.onStepCancel,
                    child: const Text('Atrás'),
                  ),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: _isDeploying ? null : details.onStepContinue,
                  child: Text(
                    _currentStep == 3
                        ? 'Finalizar'
                        : _currentStep == 2
                            ? _isDeploying
                                ? 'Desplegando...'
                                : 'Desplegar Sitio Web'
                            : 'Continuar',
                  ),
                ),
              ],
            ),
          );
        },
        steps: [
          // STEP 1: Choose Template
          Step(
            title: const Text('Elegir Plantilla'),
            subtitle: const Text('Selecciona el diseño de tu tienda'),
            isActive: _currentStep >= 0,
            state: _currentStep > 0 ? StepState.complete : StepState.indexed,
            content: _buildTemplateSelectionStep(theme),
          ),
          
          // STEP 2: Configure Basic Info
          Step(
            title: const Text('Configuración Básica'),
            subtitle: const Text('Nombre y dominio de tu tienda'),
            isActive: _currentStep >= 1,
            state: _currentStep > 1 ? StepState.complete : StepState.indexed,
            content: _buildConfigurationStep(theme),
          ),
          
          // STEP 3: Deploy Website
          Step(
            title: const Text('Desplegar Sitio Web'),
            subtitle: const Text('Publicar tu tienda online'),
            isActive: _currentStep >= 2,
            state: _currentStep > 2 ? StepState.complete : StepState.indexed,
            content: _buildDeploymentStep(theme),
          ),
          
          // STEP 4: Custom Domain (Optional)
          Step(
            title: const Text('Dominio Personalizado'),
            subtitle: const Text('Opcional: Configura tu propio dominio'),
            isActive: _currentStep >= 3,
            state: _currentStep > 3 ? StepState.complete : StepState.indexed,
            content: _buildCustomDomainStep(theme),
          ),
        ],
      ),
    );
  }

  Widget _buildTemplateSelectionStep(ThemeData theme) {
    final templates = [
      {
        'id': 'modern-store',
        'name': 'Tienda Moderna',
        'description': 'Diseño limpio y minimalista, ideal para todo tipo de productos',
        'preview': 'https://via.placeholder.com/300x200?text=Modern+Store',
        'features': ['Catálogo de productos', 'Carrito de compras', 'Checkout integrado'],
      },
      {
        'id': 'bike-shop',
        'name': 'Bike Shop Pro',
        'description': 'Especializado para tiendas de bicicletas con filtros avanzados',
        'preview': 'https://via.placeholder.com/300x200?text=Bike+Shop',
        'features': ['Filtros por categoría', 'Comparador de productos', 'Blog integrado'],
      },
      {
        'id': 'minimalist',
        'name': 'Minimalista',
        'description': 'Enfoque en el producto con diseño ultra limpio',
        'preview': 'https://via.placeholder.com/300x200?text=Minimalist',
        'features': ['Navegación simple', 'Carga rápida', 'Mobile-first'],
      },
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Selecciona una plantilla para comenzar',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Podrás personalizar todos los aspectos después del despliegue',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 24),
        ...templates.map((template) => _buildTemplateCard(template, theme)),
      ],
    );
  }

  Widget _buildTemplateCard(Map<String, dynamic> template, ThemeData theme) {
    final isSelected = _selectedTemplate == template['id'];
    
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: isSelected ? 4 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isSelected ? theme.colorScheme.primary : Colors.transparent,
          width: 2,
        ),
      ),
      child: InkWell(
        onTap: () => setState(() => _selectedTemplate = template['id'] as String),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Preview image
              Container(
                width: 150,
                height: 100,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  color: Colors.grey[200],
                ),
                child: Center(
                  child: Text(
                    template['name'] as String,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          template['name'] as String,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (isSelected) ...[
                          const SizedBox(width: 8),
                          Icon(
                            Icons.check_circle,
                            color: theme.colorScheme.primary,
                            size: 20,
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      template['description'] as String,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: (template['features'] as List<String>)
                          .map((feature) => Chip(
                                label: Text(
                                  feature,
                                  style: const TextStyle(fontSize: 11),
                                ),
                                visualDensity: VisualDensity.compact,
                              ))
                          .toList(),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildConfigurationStep(ThemeData theme) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Información de tu tienda',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 24),
          
          // Shop Name
          TextFormField(
            controller: _shopNameController,
            decoration: const InputDecoration(
              labelText: 'Nombre de la Tienda *',
              hintText: 'Ej: Bike Shop Santiago',
              prefixIcon: Icon(Icons.store),
              helperText: 'Este nombre aparecerá en tu sitio web',
            ),
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'El nombre es requerido';
              }
              return null;
            },
            onChanged: (value) {
              // Auto-generate subdomain from shop name
              if (_subdomainController.text.isEmpty || !_subdomainAvailable) {
                final subdomain = value
                    .toLowerCase()
                    .replaceAll(RegExp(r'[^a-z0-9-]'), '-')
                    .replaceAll(RegExp(r'-+'), '-')
                    .replaceAll(RegExp(r'^-|-$'), '');
                _subdomainController.text = subdomain;
              }
            },
          ),
          const SizedBox(height: 16),
          
          // Subdomain
          TextFormField(
            controller: _subdomainController,
            decoration: InputDecoration(
              labelText: 'Subdominio *',
              hintText: 'bike-shop-santiago',
              prefixIcon: const Icon(Icons.language),
              suffixText: '.web.app',
              helperText: 'Tu tienda estará disponible en https://{subdominio}.web.app',
              suffix: _checkingSubdomain
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : _subdomainAvailable
                      ? const Icon(Icons.check_circle, color: Colors.green, size: 20)
                      : null,
            ),
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'El subdominio es requerido';
              }
              if (!RegExp(r'^[a-z0-9-]+$').hasMatch(value)) {
                return 'Solo letras minúsculas, números y guiones';
              }
              if (!_subdomainAvailable) {
                return 'Este subdominio no está disponible';
              }
              return null;
            },
            onChanged: (value) => _checkSubdomainAvailability(value),
          ),
          const SizedBox(height: 16),
          
          // Description
          TextFormField(
            controller: _descriptionController,
            decoration: const InputDecoration(
              labelText: 'Descripción (opcional)',
              hintText: 'Breve descripción de tu tienda',
              prefixIcon: Icon(Icons.description),
              helperText: 'Aparecerá en resultados de búsqueda (SEO)',
            ),
            maxLines: 3,
          ),
          const SizedBox(height: 24),
          
          // Info card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer.withOpacity(0.3),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: theme.colorScheme.primary.withOpacity(0.3),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Tu sitio web se desplegará en Firebase Hosting de forma GRATUITA. '
                    'Incluye SSL (HTTPS) automático y CDN global.',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDeploymentStep(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '¿Listo para publicar tu tienda?',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'El proceso de despliegue toma aproximadamente 2-3 minutos',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 24),
        
        // Deployment summary card
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSummaryRow('Nombre:', _shopNameController.text, Icons.store),
                const Divider(),
                _buildSummaryRow(
                  'URL:',
                  _websiteUrl ?? 'https://${_subdomainController.text}.web.app',
                  Icons.link,
                ),
                const Divider(),
                _buildSummaryRow('Plantilla:', _getTemplateName(), Icons.palette),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        
        // Deployment status
        if (_isDeploying) ...[
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceVariant,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                Text(
                  _deploymentStatus,
                  style: theme.textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ],
        
        // Success message - SITE IS READY TO PREVIEW
        if (_websiteUrl != null && !_isDeploying) ...[
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.green.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.green),
            ),
            child: Column(
              children: [
                const Icon(Icons.check_circle, color: Colors.green, size: 48),
                const SizedBox(height: 16),
                Text(
                  '¡Sitio Web Configurado!',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Colors.green[700],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Tu sitio web está listo para ver en vista previa. Puedes personalizarlo en el editor.',
                  style: theme.textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  'Vista previa disponible en:',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.grey[600],
                  ),
                ),
                const SizedBox(height: 4),
                SelectableText(
                  '${Uri.base.origin}/tienda',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Nota: Para desplegar a Firebase (${_subdomainController.text}.web.app), un administrador debe ejecutar el script de despliegue.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.grey[600],
                    fontStyle: FontStyle.italic,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: () {
                    // TODO: Open website in new tab
                  },
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('Visitar Mi Sitio Web'),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildCustomDomainStep(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Dominio Personalizado (Opcional)',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Si tienes un dominio propio (ej: www.mibikeshop.cl), puedes configurarlo aquí',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 24),
        
        TextFormField(
          controller: _customDomainController,
          decoration: const InputDecoration(
            labelText: 'Dominio Personalizado',
            hintText: 'www.mibikeshop.cl',
            prefixIcon: Icon(Icons.public),
            helperText: 'Deja en blanco si no tienes un dominio',
          ),
        ),
        const SizedBox(height: 24),
        
        // Instructions card
        ExpansionTile(
          leading: const Icon(Icons.help_outline),
          title: const Text('¿Cómo configurar mi dominio?'),
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '1. En tu proveedor de dominios (ej: GoDaddy, Namecheap), agrega estos registros DNS:',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey[200],
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Tipo: A',
                          style: TextStyle(fontFamily: 'monospace', fontSize: 12),
                        ),
                        Text(
                          'Nombre: @',
                          style: TextStyle(fontFamily: 'monospace', fontSize: 12),
                        ),
                        Text(
                          'Valor: 151.101.1.195',
                          style: TextStyle(fontFamily: 'monospace', fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '2. La propagación DNS puede tomar hasta 48 horas',
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '3. Una vez configurado, contacta a soporte para activar el SSL',
                    style: theme.textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer.withOpacity(0.3),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(Icons.info_outline, color: theme.colorScheme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Puedes configurar el dominio personalizado más tarde desde la configuración del sitio web',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryRow(String label, String value, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Colors.grey[600]),
        const SizedBox(width: 12),
        Text(
          label,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontSize: 14),
          ),
        ),
      ],
    );
  }

  String _getTemplateName() {
    switch (_selectedTemplate) {
      case 'modern-store':
        return 'Tienda Moderna';
      case 'bike-shop':
        return 'Bike Shop Pro';
      case 'minimalist':
        return 'Minimalista';
      default:
        return 'Desconocida';
    }
  }

  Future<void> _checkSubdomainAvailability(String subdomain) async {
    if (subdomain.isEmpty) {
      setState(() => _subdomainAvailable = false);
      return;
    }

    setState(() => _checkingSubdomain = true);

    try {
      final supabase = Supabase.instance.client;
      final response = await supabase
          .from('company_settings')
          .select('id')
          .eq('website_subdomain', subdomain)
          .maybeSingle();

      setState(() {
        _subdomainAvailable = response == null;
        _checkingSubdomain = false;
      });
    } catch (e) {
      setState(() {
        _subdomainAvailable = false;
        _checkingSubdomain = false;
      });
    }
  }

  Future<void> _onStepContinue() async {
    switch (_currentStep) {
      case 0:
        // Template selected, move to configuration
        setState(() => _currentStep = 1);
        break;
        
      case 1:
        // Validate configuration
        if (_formKey.currentState!.validate()) {
          setState(() => _currentStep = 2);
        }
        break;
        
      case 2:
        // Deploy website
        await _deployWebsite();
        break;
        
      case 3:
        // Finish wizard and show preview
        if (context.mounted) {
          Navigator.of(context).pop();
          
          // Navigate to store preview to see the configured template
          context.go('/tienda');
          
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('¡Sitio configurado! Ahora puedes personalizarlo en el editor.'),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 4),
              action: SnackBarAction(
                label: 'Abrir Editor',
                textColor: Colors.white,
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const OdooStyleEditorPage(),
                    ),
                  );
                },
              ),
            ),
          );
        }
        break;
    }
  }

  void _onStepCancel() {
    if (_currentStep > 0) {
      setState(() => _currentStep--);
    }
  }

  Future<void> _deployWebsite() async {
    setState(() {
      _isDeploying = true;
      _deploymentStatus = 'Guardando configuración del sitio...';
    });

    try {
      final supabase = Supabase.instance.client;
      final tenantService = TenantService();

      // Get tenant_id from user metadata
      final tenantId = tenantService.currentTenantId;
      if (tenantId == null) {
        throw Exception('No se encontró tenant_id');
      }

      // Step 1: Save website configuration columns (UPDATE table-level columns)
      setState(() => _deploymentStatus = 'Guardando configuración básica...');
      
      // First, ensure we have at least one row for this tenant (needed for website columns)
      final existingRows = await supabase
        .from('company_settings')
        .select('id')
        .eq('tenant_id', tenantId)
        .limit(1);
      
      if (existingRows.isEmpty) {
        // Create initial row for this tenant
        await supabase.from('company_settings').insert({
          'tenant_id': tenantId,
          'key': 'website_config',
          'value': _shopNameController.text,
        });
      }
      
      // Now update website columns for this tenant (updates ALL rows for tenant)
      await supabase
        .from('company_settings')
        .update({
          'website_subdomain': _subdomainController.text,
          'website_status': 'pending',
          'website_enabled': true,
          'website_url': 'https://${_subdomainController.text}.web.app',
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('tenant_id', tenantId);

      // Step 2: Save shop name as key-value setting
      await supabase.from('company_settings').upsert({
        'tenant_id': tenantId,
        'key': 'website_shop_name',
        'value': _shopNameController.text,
        'updated_at': DateTime.now().toIso8601String(),
      });

      // Step 3: Save template selection as key-value setting
      await supabase.from('company_settings').upsert({
        'tenant_id': tenantId,
        'key': 'website_template',
        'value': _selectedTemplate,
        'updated_at': DateTime.now().toIso8601String(),
      });

      // Step 4: Save description if provided
      if (_descriptionController.text.isNotEmpty) {
        await supabase.from('company_settings').upsert({
          'tenant_id': tenantId,
          'key': 'website_description',
          'value': _descriptionController.text,
          'updated_at': DateTime.now().toIso8601String(),
        });
      }

      // ✅ NEW: Save template HTML/CSS to database for GrapesJS editor
      setState(() => _deploymentStatus = 'Guardando plantilla del sitio web...');
      await _saveTemplateToDatabase(tenantId, _selectedTemplate);

      // Request deployment - admin must run script manually
      setState(() {
        _deploymentStatus = 'Sitio web configurado exitosamente';
        _websiteUrl = 'https://${_subdomainController.text}.web.app';
        _isDeploying = false;
        _currentStep = 3;
      });

    } catch (e) {
      setState(() {
        _deploymentStatus = 'Error: $e';
        _isDeploying = false;
      });
      
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al configurar sitio: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Save template HTML/CSS to database for GrapesJS editor
  Future<void> _saveTemplateToDatabase(String tenantId, String templateId) async {
    final supabase = Supabase.instance.client;
    
    // Find the selected template
    final template = WebsiteTemplates.all.firstWhere(
      (t) => t.id == templateId,
      orElse: () => WebsiteTemplates.all.first,
    );
    
    // Delete existing home page for this tenant (fresh start)
    await supabase
      .from('website_pages')
      .delete()
      .eq('tenant_id', tenantId)
      .eq('page_name', 'home');
    
    // Save template HTML/CSS to database
    await supabase.from('website_pages').insert({
      'tenant_id': tenantId,
      'page_name': 'home',
      'html_content': template.htmlContent,
      'css_content': template.cssContent,
      'is_published': true,
      'created_at': DateTime.now().toIso8601String(),
      'updated_at': DateTime.now().toIso8601String(),
    });
  }
}
