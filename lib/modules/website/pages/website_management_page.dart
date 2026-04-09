import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../shared/widgets/main_layout.dart';
import '../../../shared/widgets/branded_loading.dart';
import '../../../shared/services/tenant_service.dart';
import '../services/website_service.dart';
// Unused imports removed during cleanup

/// Main hub for website content management
class WebsiteManagementPage extends StatefulWidget {
  const WebsiteManagementPage({
    super.key,
    this.embedded = false,
  });

  final bool embedded;

  @override
  State<WebsiteManagementPage> createState() => _WebsiteManagementPageState();
}

class _WebsiteManagementPageState extends State<WebsiteManagementPage> {
  bool _isInitializing = true;

  @override
  void initState() {
    super.initState();
    debugPrint(
        '🏗️ [WebsiteManagementPage] initState called - initializing website service');
    _initialize();
  }

  Future<void> _initialize() async {
    debugPrint('🔄 [WebsiteManagementPage] _initialize started');
    final websiteService = context.read<WebsiteService>();
    await websiteService.initialize();
    debugPrint('✅ [WebsiteManagementPage] WebsiteService initialized');
    if (mounted) {
      setState(() => _isInitializing = false);
      debugPrint('✅ [WebsiteManagementPage] State updated, page ready');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_isInitializing) {
      const loading = Center(child: BrandedLoading());
      if (widget.embedded) return loading;
      return const MainLayout(child: Center(child: BrandedLoading()));
    }

    final body = SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
            // Clean Professional Header
            Row(
              children: [
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
                // Vista Previa Button - Navigate to /tienda with preview mode
                FilledButton.icon(
                  onPressed: () {
                    debugPrint(
                        '👁️ [WebsiteManagementPage] Vista Previa button clicked - navigating to /tienda?preview=true');
                    context.go('/tienda?preview=true');
                  },
                  icon: const Icon(Icons.visibility),
                  label: const Text('Vista Previa'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 16,
                    ),
                  ),
                ),
                if (!widget.embedded) ...[
                  const SizedBox(width: 12),
                  // Open in New Tab - Only for web platform
                  OutlinedButton.icon(
                    onPressed: () async {
                      debugPrint(
                          '🌐 [WebsiteManagementPage] Nueva Pestaña button clicked - launching external URL');
                      final uri = Uri.parse('${Uri.base.origin}/tienda');
                      try {
                        await launchUrl(
                          uri,
                          mode: LaunchMode.externalApplication,
                        );
                        debugPrint(
                            '✅ [WebsiteManagementPage] External URL launched successfully');
                      } catch (e) {
                        debugPrint(
                            '❌ [WebsiteManagementPage] Failed to launch external URL: $e');
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'No se pudo abrir en nueva pestaña. Usa Vista Previa.',
                              ),
                            ),
                          );
                        }
                      }
                    },
                    icon: const Icon(Icons.open_in_new),
                    label: const Text('Nueva Pestaña'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 16,
                      ),
                    ),
                  ),
                ],
              ],
            ),

            const SizedBox(height: 32),

            // 🎨 VISUAL EDITOR CARD - Clean and Professional
            Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    theme.colorScheme.primaryContainer,
                    theme.colorScheme.secondaryContainer,
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: theme.colorScheme.primary.withOpacity(0.1),
                    blurRadius: 20,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 10,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Icon(
                      Icons.palette_outlined,
                      size: 48,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 24),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Editor Visual de Sitio Web',
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.onPrimaryContainer,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Edita tu sitio web con vista previa en tiempo real. Cambia textos, colores, imágenes y ve los resultados al instante.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSecondaryContainer,
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 24),
                  FilledButton.icon(
                    onPressed: () {
                      // Navigate to /tienda and auto-enable edit mode
                      // The inline editor is now integrated into the live preview
                      context.go('/tienda?edit=true');
                    },
                    icon: const Icon(Icons.edit_rounded),
                    label: const Text('Abrir Editor'),
                    style: FilledButton.styleFrom(
                      backgroundColor: theme.colorScheme.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 32,
                        vertical: 20,
                      ),
                      textStyle: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
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
                // Pages - Main page management
                _buildManagementCard(
                  context: context,
                  title: 'Páginas',
                  subtitle: 'Crea y gestiona páginas del sitio',
                  icon: Icons.web_stories,
                  color: Colors.indigo,
                  onTap: () => context.go('/website/pages'),
                ),
                // Navigation - Menu management
                _buildManagementCard(
                  context: context,
                  title: 'Navegación',
                  subtitle: 'Configura menús y enlaces',
                  icon: Icons.menu_book,
                  color: Colors.teal,
                  onTap: () => context.go('/website/navigation'),
                ),
                // Featured Products
                _buildManagementCard(
                  context: context,
                  title: 'Productos Destacados',
                  subtitle: 'Selecciona productos para la home',
                  icon: Icons.star,
                  color: Colors.orange,
                  onTap: () => context.go('/website/featured'),
                ),
                // Content Management
                _buildManagementCard(
                  context: context,
                  title: 'Contenido',
                  subtitle: 'Textos, páginas y descripciones',
                  icon: Icons.article,
                  color: Colors.blue,
                  onTap: () => context.go('/website/content'),
                ),
                // Online Orders
                _buildManagementCard(
                  context: context,
                  title: 'Pedidos Online',
                  subtitle: 'Gestiona pedidos del sitio web',
                  icon: Icons.shopping_bag,
                  color: Colors.green,
                  onTap: () => context.go('/website/orders'),
                ),
                // Website Settings
                _buildManagementCard(
                  context: context,
                  title: 'Configuración',
                  subtitle: 'Ajustes de la tienda online',
                  icon: Icons.settings,
                  color: Colors.grey,
                  onTap: () => context.go('/website/settings'),
                ),
                // Integrations
                _buildManagementCard(
                  context: context,
                  title: 'Integraciones',
                  subtitle: 'Google Merchant, Analytics y más',
                  icon: Icons.hub,
                  color: Colors.red,
                  onTap: () => context.go('/website/integrations'),
                ),
                // SEO Settings
                _buildManagementCard(
                  context: context,
                  title: 'SEO',
                  subtitle: 'Optimización para buscadores',
                  icon: Icons.search,
                  color: Colors.green,
                  onTap: () => context.go('/website/seo'),
                ),
              ],
            ),

            const SizedBox(height: 32),

            // Quick Stats
            Consumer<WebsiteService>(
              builder: (context, service, _) {
                final activeBlocks =
                    service.blocks.where((b) => b['is_visible'] == true).length;
                final activeFeatured =
                    service.featuredProducts.where((fp) => fp.active).length;
                final pendingOrders =
                    service.orders.where((o) => o.status == 'pending').length;
                final totalOrders = service.orders.length;

                return Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(
                      color: theme.colorScheme.outlineVariant,
                      width: 1,
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Estadísticas',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 24),
                        Row(
                          children: [
                            _buildStatItem(
                              context,
                              'Bloques Activos',
                              activeBlocks.toString(),
                              Icons.view_module_outlined,
                            ),
                            const SizedBox(width: 32),
                            _buildStatItem(
                              context,
                              'Productos Destacados',
                              activeFeatured.toString(),
                              Icons.star_outline,
                            ),
                            const SizedBox(width: 32),
                            _buildStatItem(
                              context,
                              'Pedidos Pendientes',
                              pendingOrders.toString(),
                              Icons.pending_actions_outlined,
                            ),
                            const SizedBox(width: 32),
                            _buildStatItem(
                              context,
                              'Total Pedidos',
                              totalOrders.toString(),
                              Icons.receipt_long_outlined,
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
    );

    if (widget.embedded) return body;

    return MainLayout(child: body);
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
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant,
          width: 1,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 28, color: color),
              ),
              const SizedBox(height: 12),
              Text(
                title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
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
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.3),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              icon,
              color: theme.colorScheme.primary,
              size: 24,
            ),
            const SizedBox(height: 12),
            Text(
              value,
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
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

  /// Show Google Merchant Center feed URL dialog
  Future<void> _showGoogleMerchantDialog(BuildContext context) async {
    final theme = Theme.of(context);

    // Get tenant subdomain
    String? subdomain;
    String? customDomain;

    try {
      final tenantService = TenantService();
      final tenantData = await tenantService.getCurrentTenant();
      subdomain = tenantData?['subdomain'] as String?;
      customDomain = tenantData?['custom_domain'] as String?;
    } catch (e) {
      debugPrint('Error getting tenant data: $e');
    }

    if (!context.mounted) return;

    // Build the feed URL
    const supabaseUrl = 'https://xzdvtzdqjeyqxnkqprtf.supabase.co/functions/v1';
    String feedUrl;

    if (customDomain != null && customDomain.isNotEmpty) {
      feedUrl = '$supabaseUrl/google-merchant-feed?domain=$customDomain';
    } else if (subdomain != null && subdomain.isNotEmpty) {
      feedUrl = '$supabaseUrl/google-merchant-feed?tenant=$subdomain';
    } else {
      feedUrl = 'Error: No se pudo determinar el tenant';
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.feed, color: Colors.red),
            ),
            const SizedBox(width: 12),
            const Text('Google Merchant Center'),
          ],
        ),
        content: SizedBox(
          width: 500,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Feed de Productos',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Usa esta URL para configurar tu feed de productos en Google Merchant Center:',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: theme.colorScheme.outlineVariant,
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: SelectableText(
                        feedUrl,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.copy, size: 20),
                      tooltip: 'Copiar URL',
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: feedUrl));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('URL copiada al portapapeles'),
                            duration: Duration(seconds: 2),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Instrucciones:',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              _buildInstruction('1', 'Ve a Google Merchant Center'),
              _buildInstruction('2', 'Navega a Productos > Feeds'),
              _buildInstruction('3', 'Crea un nuevo feed principal'),
              _buildInstruction('4', 'Selecciona "Recuperación programada"'),
              _buildInstruction('5', 'Pega la URL de arriba'),
              _buildInstruction('6', 'Configura actualización cada 24 horas'),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline,
                        color: Colors.blue, size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Solo se incluyen productos activos, publicados, con precio > 0 y con imagen.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: Colors.blue.shade700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cerrar'),
          ),
          FilledButton.icon(
            icon: const Icon(Icons.open_in_new, size: 18),
            label: const Text('Probar Feed'),
            onPressed: () async {
              final uri = Uri.parse(feedUrl);
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildInstruction(String number, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 20,
            height: 20,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.grey.shade200,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              number,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
