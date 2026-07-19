import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../shared/widgets/asset_pdf_preview_dialog.dart';
import '../services/website_service.dart';
import '../widgets/website_admin_ui.dart';

/// Operational hub for the public website and online store.
class WebsiteManagementPage extends StatefulWidget {
  const WebsiteManagementPage({super.key, this.embedded = false});

  final bool embedded;

  @override
  State<WebsiteManagementPage> createState() => _WebsiteManagementPageState();
}

class _WebsiteManagementPageState extends State<WebsiteManagementPage> {
  bool _isHydratingMetrics = true;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      final service = context.read<WebsiteService>();
      await service.initialize();
      await service.initializeOrders();
    } catch (error) {
      debugPrint('No se pudieron hidratar las métricas del sitio web: $error');
    } finally {
      if (mounted) setState(() => _isHydratingMetrics = false);
    }
  }

  Future<void> _openStore() async {
    final uri = Uri.parse('${Uri.base.origin}/tienda');
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo abrir una ventana externa.'),
        ),
      );
    }
  }

  Future<void> _openManual() {
    return showAssetPdfPreviewDialog(
      context,
      assetPath: 'assets/manuals/manual_sitio_web_ventas_online.pdf',
      title: 'Manual de sitio web y ventas online',
      description: 'Publicación, pedidos, pagos, documentos y excepciones.',
      fileName: 'manual_sitio_web_ventas_online.pdf',
    );
  }

  @override
  Widget build(BuildContext context) {
    return WebsiteAdminShell(
      embedded: widget.embedded,
      showBack: false,
      title: 'Sitio web',
      description: 'Controla lo que publicas y cómo compran tus clientes.',
      actions: [
        IconButton.outlined(
          onPressed: _openManual,
          tooltip: 'Manual de sitio web y ventas',
          icon: const Icon(Icons.help_outline_rounded, size: 19),
        ),
        OutlinedButton.icon(
          onPressed: () => context.go('/tienda?preview=true'),
          icon: const Icon(Icons.visibility_outlined, size: 18),
          label: const Text('Vista previa'),
        ),
        IconButton.outlined(
          onPressed: _openStore,
          tooltip: 'Abrir sitio en otra ventana',
          icon: const Icon(Icons.open_in_new_rounded, size: 19),
        ),
      ],
      child: WebsiteAdminBody(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _EditorSpotlight(
              onOpen: () => context.go('/tienda?edit=true'),
            ),
            const SizedBox(height: 18),
            Consumer<WebsiteService>(
              builder: (context, service, _) {
                final activeBlocks = service.blocks
                    .where((block) => block['is_visible'] == true)
                    .length;
                final activeFeatured = service.featuredProducts
                    .where((product) => product.active)
                    .length;
                final pendingOrders = service.orders
                    .where((order) => order.status == 'pending')
                    .length;
                return WebsiteAdminMetricStrip(
                  metrics: [
                    WebsiteAdminMetric(
                      label: 'Secciones visibles',
                      value: _isHydratingMetrics ? '—' : '$activeBlocks',
                      icon: Icons.layers_outlined,
                      detail: _isHydratingMetrics ? 'cargando' : 'en el sitio',
                      accent: const Color(0xFF1976D2),
                    ),
                    WebsiteAdminMetric(
                      label: 'Productos destacados',
                      value: _isHydratingMetrics ? '—' : '$activeFeatured',
                      icon: Icons.star_outline_rounded,
                      detail: _isHydratingMetrics ? 'cargando' : 'de 8',
                      accent: const Color(0xFF7C4DFF),
                    ),
                    WebsiteAdminMetric(
                      label: 'Pedidos por revisar',
                      value: _isHydratingMetrics ? '—' : '$pendingOrders',
                      icon: Icons.pending_actions_outlined,
                      detail: _isHydratingMetrics ? 'cargando' : 'pendientes',
                      accent: const Color(0xFFF28C28),
                    ),
                    WebsiteAdminMetric(
                      label: 'Pedidos históricos',
                      value: _isHydratingMetrics
                          ? '—'
                          : '${service.orders.length}',
                      icon: Icons.receipt_long_outlined,
                      detail: _isHydratingMetrics ? 'cargando' : 'total',
                      accent: const Color(0xFF19A974),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 28),
            Text(
              'Espacios de trabajo',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              'Contenido, comercio y crecimiento en un solo lugar.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 14),
            LayoutBuilder(
              builder: (context, constraints) {
                final columns = constraints.maxWidth >= 1120
                    ? 3
                    : constraints.maxWidth >= 720
                        ? 2
                        : 1;
                const gap = 14.0;
                final width =
                    (constraints.maxWidth - gap * (columns - 1)) / columns;
                return Wrap(
                  spacing: gap,
                  runSpacing: gap,
                  children: [
                    SizedBox(
                      width: width,
                      child: const _ManagementGroup(
                        title: 'Contenido y estructura',
                        description: 'Lo que el cliente ve y cómo se mueve.',
                        icon: Icons.dashboard_customize_outlined,
                        accent: Color(0xFF1976D2),
                        items: [
                          _ManagementItem(
                            title: 'Páginas',
                            description: 'Crea y ordena las páginas del sitio',
                            icon: Icons.web_stories_outlined,
                            route: '/website/pages',
                          ),
                          _ManagementItem(
                            title: 'Navegación',
                            description: 'Menús del encabezado y pie',
                            icon: Icons.menu_open_rounded,
                            route: '/website/navigation',
                          ),
                          _ManagementItem(
                            title: 'Destinos y enlaces',
                            description: 'Comprueba rutas, botones y campañas',
                            icon: Icons.account_tree_outlined,
                            route: '/website/destinations',
                          ),
                        ],
                      ),
                    ),
                    SizedBox(
                      width: width,
                      child: const _ManagementGroup(
                        title: 'Catálogo y ventas',
                        description: 'Qué publicas y qué requiere atención.',
                        icon: Icons.storefront_outlined,
                        accent: Color(0xFF0F9D87),
                        items: [
                          _ManagementItem(
                            title: 'Catálogo web',
                            description:
                                'Visibilidad de productos y categorías',
                            icon: Icons.storefront_outlined,
                            route: '/website/product-visibility',
                          ),
                          _ManagementItem(
                            title: 'Productos destacados',
                            description: 'La selección principal de la portada',
                            icon: Icons.star_outline_rounded,
                            route: '/website/featured',
                          ),
                          _ManagementItem(
                            title: 'Pedidos online',
                            description: 'Revisa estados, pagos y entregas',
                            icon: Icons.shopping_bag_outlined,
                            route: '/website/orders',
                          ),
                        ],
                      ),
                    ),
                    SizedBox(
                      width: width,
                      child: const _ManagementGroup(
                        title: 'Configuración y alcance',
                        description: 'Datos, conexiones y posicionamiento.',
                        icon: Icons.auto_graph_outlined,
                        accent: Color(0xFF7C4DFF),
                        items: [
                          _ManagementItem(
                            title: 'Configuración',
                            description: 'Datos públicos y reglas de compra',
                            icon: Icons.tune_rounded,
                            route: '/website/settings',
                          ),
                          _ManagementItem(
                            title: 'Integraciones',
                            description: 'Google, medición y canales externos',
                            icon: Icons.hub_outlined,
                            route: '/website/integrations',
                          ),
                          _ManagementItem(
                            title: 'SEO',
                            description: 'Cómo aparece tu tienda en buscadores',
                            icon: Icons.search_rounded,
                            route: '/website/seo',
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _EditorSpotlight extends StatelessWidget {
  const _EditorSpotlight({required this.onOpen});

  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const deepBlue = Color(0xFF0A3C66);
    const brightBlue = Color(0xFF1976D2);
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [deepBlue, brightBlue],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
          boxShadow: [
            BoxShadow(
              color: Color(0x331976D2),
              blurRadius: 28,
              offset: Offset(0, 12),
            ),
          ],
        ),
        child: Stack(
          children: [
            Positioned(
              right: -45,
              top: -85,
              child: Container(
                width: 220,
                height: 220,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.07),
                ),
              ),
            ),
            Positioned(
              right: 125,
              bottom: -75,
              child: Container(
                width: 160,
                height: 160,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.045),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 25, 28, 25),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final copy = Row(
                    children: [
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.18),
                          ),
                        ),
                        child: const Icon(
                          Icons.language_rounded,
                          color: Colors.white,
                          size: 27,
                        ),
                      ),
                      const SizedBox(width: 18),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 7,
                                  height: 7,
                                  decoration: const BoxDecoration(
                                    color: Color(0xFF59E0A9),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 7),
                                Text(
                                  'CANAL WEB',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: Colors.white.withValues(alpha: 0.78),
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.8,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 7),
                            Text(
                              'Tu vitrina digital, lista para vender',
                              style: theme.textTheme.headlineSmall?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.5,
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              'Actualiza contenido y catálogo sobre una vista real del sitio.',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: Colors.white.withValues(alpha: 0.8),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                  final button = FilledButton.icon(
                    onPressed: onOpen,
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: deepBlue,
                      minimumSize: const Size(0, 44),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: const Text('Abrir editor visual'),
                  );
                  if (constraints.maxWidth < 700) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        copy,
                        const SizedBox(height: 20),
                        Align(alignment: Alignment.centerLeft, child: button),
                      ],
                    );
                  }
                  return Row(
                    children: [
                      Expanded(child: copy),
                      const SizedBox(width: 28),
                      button,
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ManagementItem {
  const _ManagementItem({
    required this.title,
    required this.description,
    required this.icon,
    required this.route,
  });

  final String title;
  final String description;
  final IconData icon;
  final String route;
}

class _ManagementGroup extends StatelessWidget {
  const _ManagementGroup({
    required this.title,
    required this.description,
    required this.icon,
    required this.accent,
    required this.items,
  });

  final String title;
  final String description;
  final IconData icon;
  final Color accent;
  final List<_ManagementItem> items;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return WebsiteAdminSurface(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(18, 17, 18, 15),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.065),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(9),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.13),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Icon(icon, size: 20, color: accent),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.15,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        description,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: theme.colorScheme.outlineVariant),
          for (var index = 0; index < items.length; index++) ...[
            _ManagementRow(item: items[index], accent: accent),
            if (index < items.length - 1)
              Divider(
                height: 1,
                indent: 54,
                color: theme.colorScheme.outlineVariant,
              ),
          ],
        ],
      ),
    );
  }
}

class _ManagementRow extends StatelessWidget {
  const _ManagementRow({required this.item, required this.accent});

  final _ManagementItem item;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: () => context.go(item.route),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 14),
        child: Row(
          children: [
            Icon(
              item.icon,
              size: 21,
              color: accent,
            ),
            const SizedBox(width: 15),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    item.description,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}
