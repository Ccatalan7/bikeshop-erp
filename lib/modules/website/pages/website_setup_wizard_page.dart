import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:go_router/go_router.dart';
import '../../../shared/services/tenant_service.dart';
import 'odoo_style_editor_page.dart';

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
  
  // Step 1: Configuration
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
                    _currentStep == 2
                        ? 'Finalizar'
                        : _currentStep == 1
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
          // STEP 1: Configure Basic Info
          Step(
            title: const Text('Configuración Básica'),
            subtitle: const Text('Nombre y dominio de tu tienda'),
            isActive: _currentStep >= 0,
            state: _currentStep > 0 ? StepState.complete : StepState.indexed,
            content: _buildConfigurationStep(theme),
          ),
          
          // STEP 2: Deploy Website
          Step(
            title: const Text('Desplegar Sitio Web'),
            subtitle: const Text('Publicar tu tienda online'),
            isActive: _currentStep >= 1,
            state: _currentStep > 1 ? StepState.complete : StepState.indexed,
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
        // Validate configuration and move to deployment
        if (_formKey.currentState!.validate()) {
          setState(() => _currentStep = 1);
        }
        break;
        
      case 1:
        // Deploy website
        await _deployWebsite();
        break;
        
      case 2:
        // Finish wizard and show preview
        if (context.mounted) {
          Navigator.of(context).pop();
          
          // Navigate to store preview
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
      
      // Ensure we have at least one row for this tenant using upsert function
      await _upsertSetting(tenantId, 'website_config', _shopNameController.text);
      
      // Now update website columns ONLY for the website_config row
      await supabase
        .from('company_settings')
        .update({
          'website_subdomain': _subdomainController.text,
          'website_status': 'deployed', // ✅ Set as deployed immediately (no automation exists yet)
          'website_enabled': true,
          'website_url': 'https://${_subdomainController.text}.web.app',
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('tenant_id', tenantId)
        .eq('key', 'website_config'); // ✅ Only update the website_config row

      // Step 2: Save shop name as key-value setting
      await _upsertSetting(tenantId, 'website_shop_name', _shopNameController.text);

      // Step 3: Save description if provided
      if (_descriptionController.text.isNotEmpty) {
        await _upsertSetting(tenantId, 'website_description', _descriptionController.text);
      }

      // ✅ Create blank starting page for GrapesJS editor
      setState(() => _deploymentStatus = 'Creando página inicial...');
      await _saveTemplateToDatabase(tenantId, 'blank');

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
    
    // Delete existing home page for this tenant (fresh start)
    await supabase
      .from('website_pages')
      .delete()
      .eq('tenant_id', tenantId)
      .eq('page_name', 'home');
    
    // START WITH BLANK PAGE - No template loading issues
    // User builds from scratch in GrapesJS editor
    await supabase.from('website_pages').insert({
      'tenant_id': tenantId,
      'page_name': 'home',
      'html_content': '<div style="padding: 40px; text-align: center;"><h1>Start Building Your Website</h1><p>Use the blocks on the left to add content.</p></div>',
      'css_content': 'body { font-family: Arial, sans-serif; margin: 0; padding: 0; }',
      'is_published': true,
      'created_at': DateTime.now().toIso8601String(),
      'updated_at': DateTime.now().toIso8601String(),
    });
  }

  /// Helper to upsert a setting: uses PostgreSQL function to avoid 409 conflicts
  Future<void> _upsertSetting(String tenantId, String key, String value) async {
    final supabase = Supabase.instance.client;
    
    // Use PostgreSQL function with ON CONFLICT DO UPDATE
    await supabase.rpc('upsert_company_setting', params: {
      'p_tenant_id': tenantId,
      'p_key': key,
      'p_value': value,
    });
  }
}
