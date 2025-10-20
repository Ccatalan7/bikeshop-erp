import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../shared/widgets/main_layout.dart';
import '../services/website_service.dart';
import 'banners_management_page.dart';
import 'featured_products_page.dart';
import 'content_management_page.dart';
import 'website_settings_page.dart';
import 'online_orders_page.dart';

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
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                    ),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton.icon(
                    onPressed: () async {
                      // Open in new browser tab (for web)
                      final uri = Uri.parse('${Uri.base.origin}/tienda');
                      if (await canLaunchUrl(uri)) {
                        await launchUrl(uri, mode: LaunchMode.externalApplication);
                      } else {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Usa Vista Previa para ver la tienda'),
                            ),
                          );
                        }
                      }
                    },
                    icon: const Icon(Icons.open_in_new),
                    label: const Text('Abrir en Nueva Pestaña'),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton.icon(
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Usa Vista Previa para ver el sitio en acción'),
                        ),
                      );
                    },
                    icon: const Icon(Icons.preview),
                    label: const Text('Vista Previa'),
                  ),
                ],
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
