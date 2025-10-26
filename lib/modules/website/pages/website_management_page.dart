import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../shared/widgets/main_layout.dart';
import '../services/website_service.dart';
import '../services/website_deployment_service.dart';
import 'banners_management_page.dart';
import 'featured_products_page.dart';
import 'content_management_page.dart';
import 'website_settings_page.dart';
import 'online_orders_page.dart';
import 'odoo_style_editor_page.dart';
import 'website_setup_wizard_page.dart';
import 'grapesjs_editor_page.dart';

/// Main hub for website content management
class WebsiteManagementPage extends StatefulWidget {
  const WebsiteManagementPage({super.key});

  @override
  State<WebsiteManagementPage> createState() => _WebsiteManagementPageState();
}

class _WebsiteManagementPageState extends State<WebsiteManagementPage> {
  bool _isInitializing = true;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    final websiteService = context.read<WebsiteService>();
    final deploymentService = context.read<WebsiteDeploymentService>();
    
    await Future.wait([
      websiteService.initialize(),
      deploymentService.loadConfiguration(),
    ]);
    
    if (mounted) {
      setState(() => _isInitializing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_isInitializing) {
      return const MainLayout(
        child: Center(child: CircularProgressIndicator()),
      );
    }

    return MainLayout(
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Gestión de Sitio Web'),
          backgroundColor: theme.colorScheme.surface,
          elevation: 0,
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.language,
                      size: 40,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Gestión de Sitio Web',
                          style: theme.textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Administra el contenido de tu tienda online',
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  ElevatedButton.icon(
                    onPressed: () {
                      // Navigate to public store preview
                      context.go('/tienda');
                    },
                    icon: const Icon(Icons.visibility),
                    label: const Text('Vista Previa'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: theme.colorScheme.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 16),
                    ),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton.icon(
                    onPressed: () async {
                      // Open store in new browser tab (ONLY the store, not the whole app)
                      final uri = Uri.parse('${Uri.base.origin}/tienda');
                      if (await canLaunchUrl(uri)) {
                        await launchUrl(uri,
                            mode: LaunchMode.externalApplication);
                      } else {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content:
                                  Text('No se pudo abrir la tienda en nueva pestaña'),
                            ),
                          );
                        }
                      }
                    },
                    icon: const Icon(Icons.open_in_new),
                    label: const Text('Abrir Tienda en Nueva Pestaña'),
                  ),
                ],
              ),

              const SizedBox(height: 32),

              // 🚀 DEPLOYMENT STATUS BANNER
              Consumer<WebsiteDeploymentService>(
                builder: (context, deploymentService, _) {
                  return _buildDeploymentStatusBanner(theme, deploymentService);
                },
              ),

              const SizedBox(height: 32),

              // 🎨 VISUAL EDITOR CARD (Featured)
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      theme.colorScheme.primaryContainer,
                      theme.colorScheme.secondaryContainer,
                    ],
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: theme.colorScheme.primary.withOpacity(0.3),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.edit_note_rounded,
                        size: 48,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                '🎨 Editor Visual',
                                style: theme.textTheme.headlineSmall?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: theme.colorScheme.onPrimaryContainer,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.amber.shade600,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text(
                                  'NUEVO',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Edita tu sitio web con vista previa en tiempo real. '
                            'Cambia textos, colores, imágenes y ve los resultados al instante.',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSecondaryContainer,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 20),
                    ElevatedButton.icon(
                      onPressed: () async {
                        // Load existing home page if it exists
                        final websiteService = context.read<WebsiteService>();
                        final pageData = await websiteService.getHomePage();
                        
                        if (!context.mounted) return;
                        
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => GrapesJSEditorPage(
                              initialHtml: pageData?['html_content'] as String?,
                              initialCss: pageData?['css_content'] as String?,
                              pageId: pageData?['id'] as String?,
                            ),
                          ),
                        );
                      },
                      icon: const Icon(Icons.edit),
                      label: const Text('Abrir Editor'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: theme.colorScheme.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 32,
                          vertical: 20,
                        ),
                        textStyle: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 32),

              // Management Cards Grid
              GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: _getCrossAxisCount(context),
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                childAspectRatio: 1.5,
                children: [
                  _buildManagementCard(
                    context: context,
                    title: 'Banners',
                    subtitle: 'Imágenes destacadas del inicio',
                    icon: Icons.image,
                    color: Colors.purple,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const BannersManagementPage(),
                        ),
                      );
                    },
                  ),
                  _buildManagementCard(
                    context: context,
                    title: 'Productos Destacados',
                    subtitle: 'Selecciona productos para la home',
                    icon: Icons.star,
                    color: Colors.orange,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const FeaturedProductsPage(),
                        ),
                      );
                    },
                  ),
                  _buildManagementCard(
                    context: context,
                    title: 'Contenido',
                    subtitle: 'Textos, páginas y descripciones',
                    icon: Icons.article,
                    color: Colors.blue,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const ContentManagementPage(),
                        ),
                      );
                    },
                  ),
                  _buildManagementCard(
                    context: context,
                    title: 'Pedidos Online',
                    subtitle: 'Gestiona pedidos del sitio web',
                    icon: Icons.shopping_bag,
                    color: Colors.green,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const OnlineOrdersPage(),
                        ),
                      );
                    },
                  ),
                  _buildManagementCard(
                    context: context,
                    title: 'Configuración',
                    subtitle: 'Ajustes de la tienda online',
                    icon: Icons.settings,
                    color: Colors.grey,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const WebsiteSettingsPage(),
                        ),
                      );
                    },
                  ),
                  _buildManagementCard(
                    context: context,
                    title: 'Google Merchant',
                    subtitle: 'Feed para Google Shopping',
                    icon: Icons.feed,
                    color: Colors.red,
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Próximamente: Google Merchant Center'),
                        ),
                      );
                    },
                  ),
                ],
              ),

              const SizedBox(height: 32),

              // Quick Stats
              Consumer<WebsiteService>(
                builder: (context, service, _) {
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Estadísticas Rápidas',
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              _buildStatItem(
                                context,
                                'Banners Activos',
                                '${service.banners.where((b) => b.active).length}',
                                Icons.image,
                              ),
                              const SizedBox(width: 32),
                              _buildStatItem(
                                context,
                                'Productos Destacados',
                                '${service.featuredProducts.where((fp) => fp.active).length}',
                                Icons.star,
                              ),
                              const SizedBox(width: 32),
                              _buildStatItem(
                                context,
                                'Pedidos Pendientes',
                                '${service.orders.where((o) => o.status == 'pending').length}',
                                Icons.shopping_bag,
                              ),
                              const SizedBox(width: 32),
                              _buildStatItem(
                                context,
                                'Pedidos Totales',
                                '${service.orders.length}',
                                Icons.receipt,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDeploymentStatusBanner(
    ThemeData theme,
    WebsiteDeploymentService deploymentService,
  ) {
    // Not configured - show setup wizard call-to-action
    if (!deploymentService.isConfigured) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Colors.blue.shade50,
              Colors.purple.shade50,
            ],
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: theme.colorScheme.primary.withOpacity(0.3)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 8,
                  ),
                ],
              ),
              child: Icon(
                Icons.rocket_launch,
                size: 48,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '🚀 ¡Despliega Tu Sitio Web!',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Tu tienda online aún no está configurada. Despliégala en minutos con un dominio gratuito .web.app',
                    style: theme.textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 20),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const WebsiteSetupWizardPage(),
                  ),
                );
              },
              icon: const Icon(Icons.settings_suggest),
              label: const Text('Configurar Ahora'),
              style: ElevatedButton.styleFrom(
                backgroundColor: theme.colorScheme.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 20,
                ),
                textStyle: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      );
    }

    // Pending deployment
    if (deploymentService.isPending) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.orange.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.orange),
        ),
        child: Row(
          children: [
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                valueColor: AlwaysStoppedAnimation(Colors.orange),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Despliegue Pendiente',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.orange.shade900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Tu sitio web está configurado y listo. Mientras esperas el despliegue, puedes seguir editando tu contenido.',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            TextButton.icon(
              onPressed: () => deploymentService.loadConfiguration(),
              icon: const Icon(Icons.refresh),
              label: const Text('Actualizar'),
            ),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const OdooStyleEditorPage(),
                  ),
                );
              },
              icon: const Icon(Icons.edit),
              label: const Text('Abrir Editor'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      );
    }

    // Deployment failed
    if (deploymentService.hasFailed) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.red.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.red),
        ),
        child: Row(
          children: [
            Icon(Icons.error_outline, color: Colors.red, size: 32),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Error en el Despliegue',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.red.shade900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    deploymentService.errorMessage ?? 'Ocurrió un error desconocido',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const WebsiteSetupWizardPage(),
                  ),
                );
              },
              icon: const Icon(Icons.refresh),
              label: const Text('Reintentar'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      );
    }

    // Successfully deployed
    if (deploymentService.isDeployed) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Colors.green.shade50,
              Colors.teal.shade50,
            ],
          ),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.green),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.check_circle, color: Colors.green, size: 32),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '✅ Sitio Web Activo',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.green.shade900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  if (deploymentService.websiteUrl != null)
                    SelectableText(
                      deploymentService.websiteUrl!,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  if (deploymentService.deployedAt != null)
                    Text(
                      'Desplegado: ${_formatDate(deploymentService.deployedAt!)}',
                      style: theme.textTheme.bodySmall,
                    ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            OutlinedButton.icon(
              onPressed: () async {
                final url = deploymentService.websiteUrl;
                if (url != null) {
                  final uri = Uri.parse(url);
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  }
                }
              },
              icon: const Icon(Icons.open_in_new),
              label: const Text('Visitar'),
            ),
            const SizedBox(width: 8),
            IconButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const WebsiteSetupWizardPage(),
                  ),
                );
              },
              icon: const Icon(Icons.settings),
              tooltip: 'Configuración de Despliegue',
            ),
          ],
        ),
      );
    }

    return const SizedBox.shrink();
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
  }

  Widget _buildManagementCard({
    required BuildContext context,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 32, color: color),
              ),
              const Spacer(),
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
          ),
        ),
      ),
    );
  }

  Widget _buildStatItem(
    BuildContext context,
    String label,
    String value,
    IconData icon,
  ) {
    final theme = Theme.of(context);

    return Expanded(
      child: Row(
        children: [
          Icon(icon, color: theme.colorScheme.primary, size: 24),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.primary,
                ),
              ),
              Text(
                label,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  int _getCrossAxisCount(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (width > 1400) return 4;
    if (width > 1000) return 3;
    if (width > 600) return 2;
    return 1;
  }
}
