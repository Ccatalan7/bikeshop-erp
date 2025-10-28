import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../shared/widgets/main_layout.dart';
import '../services/website_service.dart';
import 'featured_products_page.dart';
import 'content_management_page.dart';
import 'website_settings_page.dart';
import 'online_orders_page.dart';
import 'odoo_style_editor_page.dart';

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
    await websiteService.initialize();
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
      child: SingleChildScrollView(
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
                  // Single Preview Button - Navigate to /tienda
                  FilledButton.icon(
                    onPressed: () {
                      context.go('/tienda');
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
                  const SizedBox(width: 12),
                  // Open in New Tab - Only for web platform
                  OutlinedButton.icon(
                    onPressed: () async {
                      final uri = Uri.parse('${Uri.base.origin}/tienda');
                      try {
                        await launchUrl(
                          uri,
                          mode: LaunchMode.externalApplication,
                        );
                      } catch (e) {
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
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const OdooStyleEditorPage(),
                          ),
                        );
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
                  // Banners module removed - use Editor instead (hero/carousel blocks)
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
                  final activeBlocks = service.blocks.where((b) => b['is_visible'] == true).length;
                  final activeFeatured = service.featuredProducts.where((fp) => fp.active).length;
                  final pendingOrders = service.orders.where((o) => o.status == 'pending').length;
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
        ),
      );
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
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 32, color: color),
              ),
              Column(
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
          color: theme.colorScheme.surfaceVariant.withOpacity(0.3),
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
}
