import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'dart:async';

import '../services/auth_service.dart';
import '../services/navigation_service.dart';
import '../services/workspace_manager.dart';
import '../services/window_zoom_service.dart';
import '../services/notification_service.dart';
import '../../modules/settings/services/appearance_service.dart';
import '../../modules/messaging/providers/chat_provider.dart';
import 'expandable_menu_item.dart';

const List<MenuSubItem> _accountingMenuItems = [
  MenuSubItem(
    icon: Icons.account_tree_outlined,
    title: 'Plan de cuentas',
    route: '/accounting/accounts',
  ),
  MenuSubItem(
    icon: Icons.receipt_long_outlined,
    title: 'Gastos',
    route: '/accounting/expenses',
  ),
  MenuSubItem(
    icon: Icons.library_books_outlined,
    title: 'Asientos contables',
    route: '/accounting/journal-entries',
  ),
  MenuSubItem(
    icon: Icons.add_circle_outline,
    title: 'Nuevo asiento',
    route: '/accounting/journal-entries/new',
  ),
  MenuSubItem(
    icon: Icons.assessment_outlined,
    title: 'Reportes Financieros',
    route: '/accounting/reports',
  ),
  MenuSubItem(
    icon: Icons.trending_up,
    title: 'Estado de Resultados',
    route: '/accounting/reports/income-statement',
  ),
  MenuSubItem(
    icon: Icons.account_balance,
    title: 'Balance General',
    route: '/accounting/reports/balance-sheet',
  ),
];

const String _accountingSectionKey = 'accounting';

const List<MenuSubItem> _taxReportsMenuItems = [
  MenuSubItem(
    icon: Icons.description_outlined,
    title: 'Declaraciones F29',
    route: '/tax-reports/f29',
  ),
];

const String _taxReportsSectionKey = 'tax_reports';

const List<MenuSubItem> _customersMenuItems = [
  MenuSubItem(
    icon: Icons.people_outline,
    title: 'Lista de clientes',
    route: '/clientes',
  ),
  MenuSubItem(
    icon: Icons.person_add_alt,
    title: 'Nuevo cliente',
    route: '/clientes/nuevo',
  ),
];

const String _customersSectionKey = 'customers';

const List<MenuSubItem> _workshopMenuItems = [
  MenuSubItem(
    icon: Icons.build_outlined,
    title: 'Trabajos',
    route: '/taller/pegas',
  ),
  MenuSubItem(
    icon: Icons.add_circle_outline,
    title: 'Nuevo trabajo',
    route: '/taller/pegas/nueva',
  ),
  MenuSubItem(
    icon: Icons.pedal_bike,
    title: 'Bicicletas registradas',
    route: '/taller/bicicletas',
  ),
  MenuSubItem(
    icon: Icons.branding_watermark_outlined,
    title: 'Marcas y modelos',
    route: '/taller/marcas-modelos',
  ),
  MenuSubItem(
    icon: Icons.calendar_today_outlined,
    title: 'Calendario',
    route: '/taller/calendario',
  ),
  MenuSubItem(
    icon: Icons.tune_outlined,
    title: 'Estados personalizados',
    route: '/taller/estados',
  ),
  MenuSubItem(
    icon: Icons.category_outlined,
    title: 'Catálogo de elementos',
    route: '/taller/sujetos',
  ),
];

const String _workshopSectionKey = 'workshop';

const List<MenuSubItem> _smartFeaturesMenuItems = [
  MenuSubItem(
    icon: Icons.settings_outlined,
    title: '🔧 Wheel Builder',
    route: '/taller/wheel-builder',
  ),
  MenuSubItem(
    icon: Icons.calculate_outlined,
    title: '📐 Spoke Calculator',
    route: '/taller/spoke-calculator',
  ),
  MenuSubItem(
    icon: Icons.menu_book,
    title: '📚 Bike Encyclopedia',
    route: '/taller/bike-encyclopedia',
  ),
  MenuSubItem(
    icon: Icons.hub_outlined,
    title: 'Hubs',
    route: '/taller/wheel-hubs',
  ),
  MenuSubItem(
    icon: Icons.album_outlined,
    title: 'Rims',
    route: '/taller/wheel-rims',
  ),
  MenuSubItem(
    icon: Icons.linear_scale_outlined,
    title: 'Spokes',
    route: '/taller/wheel-spokes',
  ),
];

const String _smartFeaturesSectionKey = 'smart_features';

const List<MenuSubItem> _inventoryMenuItems = [
  MenuSubItem(
    icon: Icons.shopping_bag_outlined,
    title: 'Productos',
    route: '/inventory/products',
  ),
  MenuSubItem(
    icon: Icons.category_outlined,
    title: 'Categorías',
    route: '/inventory/categories',
  ),
  MenuSubItem(
    icon: Icons.workspace_premium_outlined,
    title: 'Marcas',
    route: '/inventory/brands',
  ),
  MenuSubItem(
    icon: Icons.swap_horiz_outlined,
    title: 'Movimientos',
    route: '/inventory/movements',
  ),
];

const String _inventorySectionKey = 'inventory';

const List<MenuSubItem> _salesMenuItems = [
  MenuSubItem(
    icon: Icons.receipt_long_outlined,
    title: 'Facturas de venta',
    route: '/sales/invoices',
  ),
  MenuSubItem(
    icon: Icons.add_circle_outline,
    title: 'Nueva factura',
    route: '/sales/invoices/new',
  ),
  MenuSubItem(
    icon: Icons.payments_outlined,
    title: 'Pagos',
    route: '/sales/payments',
  ),
  MenuSubItem(
    icon: Icons.bar_chart_outlined,
    title: 'Informes',
    route: '/sales/reports',
  ),
];

const String _salesSectionKey = 'sales';

const List<MenuSubItem> _purchasesMenuItems = [
  MenuSubItem(
    icon: Icons.list_alt,
    title: 'Lista Inteligente',
    route: '/purchases/smart-list',
  ),
  MenuSubItem(
    icon: Icons.storefront_outlined,
    title: 'Proveedores',
    route: '/purchases/suppliers',
  ),
  MenuSubItem(
    icon: Icons.receipt_outlined,
    title: 'Facturas de compra',
    route: '/purchases',
  ),
  MenuSubItem(
    icon: Icons.note_add_outlined,
    title: 'Nueva factura',
    route: '/purchases/new',
  ),
  MenuSubItem(
    icon: Icons.payments_outlined,
    title: 'Pagos',
    route: '/purchases/payments',
  ),
];

const String _purchasesSectionKey = 'purchases';

const List<MenuSubItem> _posMenuItems = [
  MenuSubItem(
    icon: Icons.point_of_sale,
    title: 'Panel POS',
    route: '/pos',
  ),
  MenuSubItem(
    icon: Icons.shopping_cart_checkout_outlined,
    title: 'Carrito',
    route: '/pos/cart',
  ),
  MenuSubItem(
    icon: Icons.attach_money_outlined,
    title: 'Cobrar',
    route: '/pos/payment',
  ),
];

const String _posSectionKey = 'pos';

/// Helper function to open a route in a new workspace tab
/// If workspace system is not available (e.g., not authenticated), falls back to regular navigation
void _openInWorkspace(BuildContext context, String route, String title) {
  debugPrint(
      '🚀 [MainLayout] _openInWorkspace called: route=$route, title=$title');

  // Check for mobile/tablet screen width (< 800px)
  // If small screen, use standard navigation instead of workspace tabs
  final isSmallScreen = MediaQuery.of(context).size.width < 800;
  if (isSmallScreen) {
    debugPrint(
        '📱 [MainLayout] Small screen detected, using standard navigation.');
    context.push(route);
    return;
  }

  try {
    final workspaceManager = context.read<WorkspaceManager>();
    debugPrint(
        '✅ [MainLayout] WorkspaceManager found, current workspaces: ${workspaceManager.workspaces.length}');

    // Try to switch to existing workspace with this route first
    final existingFound =
        workspaceManager.switchToExistingWorkspaceWithRoute(route);
    if (!existingFound) {
      debugPrint('📝 [MainLayout] Creating new workspace for $route');
      // If not found, create new workspace
      workspaceManager.addWorkspace(
        title: title,
        initialRoute: route,
      );
      debugPrint(
          '✅ [MainLayout] New workspace created, total: ${workspaceManager.workspaces.length}');
    } else {
      debugPrint('🔄 [MainLayout] Switched to existing workspace for $route');
    }
  } catch (e) {
    debugPrint(
        '❌ [MainLayout] WorkspaceManager error: $e, falling back to context.go()');
    // WorkspaceManager not available, fall back to regular navigation
    context.go(route);
  }
}

/// Helper to get a friendly title from a route
String _getTitleFromRoute(String route) {
  final routeTitles = {
    '/dashboard': 'Dashboard',
    '/accounting/accounts': 'Contabilidad',
    '/accounting/expenses': 'Gastos',
    '/accounting/journal-entries': 'Asientos',
    '/tax-reports/f29': 'Declaraciones F29',
    '/clientes': 'Clientes',
    '/taller/pegas': 'Trabajos',
    '/taller/bicicletas': 'Bicicletas',
    '/taller/marcas-modelos': 'Marcas y Modelos',
    '/taller/estados': 'Estados personalizados',
    '/taller/sujetos': 'Catálogo de elementos',
    '/taller/wheel-builder': 'Wheel Builder',
    '/taller/wheel-hubs': 'Hubs',
    '/taller/wheel-rims': 'Rims',
    '/taller/wheel-spokes': 'Spokes',
    '/inventory/products': 'Productos',
    '/inventory/categories': 'Categorías',
    '/sales/invoices': 'Ventas',
    '/sales/reports': 'Informes de Ventas',
    '/sales/reports/by-product': 'Ventas por Artículo',
    '/sales/reports/by-customer': 'Ventas por Cliente',
    '/purchases/suppliers': 'Compras',
    '/pos': 'POS',
    '/hr/employees': 'Trabajadores',
    '/website': 'Sitio Web',
    '/settings': 'Configuración',
    '/debug': 'Debug',
  };

  return routeTitles[route] ?? route.split('/').last.capitalize();
}

extension StringExtension on String {
  String capitalize() {
    if (isEmpty) return this;
    return '${this[0].toUpperCase()}${substring(1)}';
  }
}

const List<MenuSubItem> _hrMenuItems = [
  MenuSubItem(
    icon: Icons.people_outlined,
    title: 'Trabajadores',
    route: '/hr/employees',
  ),
  MenuSubItem(
    icon: Icons.access_time_outlined,
    title: 'Asistencias',
    route: '/hr/attendances',
  ),
  MenuSubItem(
    icon: Icons.touch_app_outlined,
    title: 'Modo Kiosko',
    route: '/hr/kiosk',
  ),
  MenuSubItem(
    icon: Icons.local_hospital_outlined,
    title: 'Licencias Médicas',
    route: '/hr/medical-leaves',
  ),
  MenuSubItem(
    icon: Icons.description_outlined,
    title: 'Contratos',
    route: '/hr/contracts',
  ),
  MenuSubItem(
    icon: Icons.attach_money_outlined,
    title: 'Liquidaciones',
    route: '/hr/payroll',
  ),
];

const String _hrSectionKey = 'hr';

const List<MenuSubItem> _chatMenuItems = [
  MenuSubItem(
    icon: Icons.chat_bubble_outline,
    title: 'Meson de ayuda',
    route: '/chat',
  ),
];

const String _chatSectionKey = 'chat';

// Tools (WebView embedded websites)
const List<MenuSubItem> _toolsMenuItems = [
  MenuSubItem(
    icon: Icons.table_chart,
    title: '📊 Planillas',
    route: '/tools/spreadsheets',
  ),
  MenuSubItem(
    icon: Icons.message,
    title: 'WhatsApp Web',
    route: '/tools/whatsapp-web',
  ),
  MenuSubItem(
    icon: Icons.table_chart,
    title: 'Google Sheets',
    route: '/tools/sheets',
  ),
  MenuSubItem(
    icon: Icons.note,
    title: 'Notion',
    route: '/tools/notion',
  ),
  MenuSubItem(
    icon: Icons.analytics,
    title: 'Analytics',
    route: '/tools/analytics',
  ),
];

const String _toolsSectionKey = 'tools';

// ─── Debug (Bug Tracking) module ─────────────────────────────────
const List<MenuSubItem> _debugMenuItems = [
  MenuSubItem(
    icon: Icons.bug_report_outlined,
    title: 'Lista de bugs',
    route: '/debug',
  ),
];

const String _debugSectionKey = 'debug';

/// Shows the sidebar options menu with live-updating zoom controls
void _showSidebarOptionsMenu(
    BuildContext context, NavigationService navigationService) {
  final RenderBox button = context.findRenderObject() as RenderBox;
  final RenderBox overlay =
      Navigator.of(context).overlay!.context.findRenderObject() as RenderBox;
  final buttonPosition = button.localToGlobal(Offset.zero, ancestor: overlay);

  showDialog(
    context: context,
    barrierColor: Colors.transparent,
    builder: (dialogContext) {
      return Stack(
        children: [
          // Invisible barrier to close on tap outside
          Positioned.fill(
            child: GestureDetector(
              onTap: () => Navigator.of(dialogContext).pop(),
              child: Container(color: Colors.transparent),
            ),
          ),
          // Menu positioned above the button
          Positioned(
            left: buttonPosition.dx,
            bottom: overlay.size.height - buttonPosition.dy + 8,
            child: _SidebarOptionsPanel(
              navigationService: navigationService,
              onClose: () => Navigator.of(dialogContext).pop(),
            ),
          ),
        ],
      );
    },
  );
}

/// Stateful widget for the options panel to enable live updates
class _SidebarOptionsPanel extends StatelessWidget {
  final NavigationService navigationService;
  final VoidCallback onClose;

  const _SidebarOptionsPanel({
    required this.navigationService,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Consumer2<WindowZoomService, AppearanceService>(
      builder: (context, zoomService, appearanceService, _) {
        final zoomPercent = (zoomService.scale * 100).round();

        return Material(
          elevation: 8,
          borderRadius: BorderRadius.circular(8),
          color: theme.colorScheme.surface,
          child: Container(
            width: 220,
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Dark mode toggle
                _OptionTile(
                  icon: appearanceService.themeMode == ThemeMode.dark
                      ? Icons.light_mode
                      : Icons.dark_mode,
                  label: appearanceService.themeMode == ThemeMode.dark
                      ? 'Modo claro'
                      : 'Modo oscuro',
                  onTap: () {
                    final newMode =
                        appearanceService.themeMode == ThemeMode.dark
                            ? ThemeMode.light
                            : ThemeMode.dark;
                    appearanceService.setThemeMode(newMode);
                  },
                ),
                // Zoom controls
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(
                    children: [
                      Icon(Icons.zoom_in,
                          size: 18,
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.7)),
                      const SizedBox(width: 12),
                      Text('Zoom', style: theme.textTheme.bodyMedium),
                      const Spacer(),
                      // Zoom out button
                      IconButton(
                        icon: const Icon(Icons.remove, size: 16),
                        padding: EdgeInsets.zero,
                        constraints:
                            const BoxConstraints(minWidth: 28, minHeight: 28),
                        onPressed: zoomService.scale > 0.5
                            ? () => zoomService.zoomOut()
                            : null,
                      ),
                      // Live zoom percentage
                      Container(
                        width: 42,
                        alignment: Alignment.center,
                        child: Text(
                          '$zoomPercent%',
                          style: theme.textTheme.bodySmall
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                      ),
                      // Zoom in button
                      IconButton(
                        icon: const Icon(Icons.add, size: 16),
                        padding: EdgeInsets.zero,
                        constraints:
                            const BoxConstraints(minWidth: 28, minHeight: 28),
                        onPressed: zoomService.scale < 3.0
                            ? () => zoomService.zoomIn()
                            : null,
                      ),
                    ],
                  ),
                ),
                Divider(
                    height: 1,
                    color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3)),
                // Reorder modules
                _OptionTile(
                  icon: navigationService.isReorderMode
                      ? Icons.check
                      : Icons.swap_vert,
                  label: navigationService.isReorderMode
                      ? 'Guardar orden'
                      : 'Reordenar módulos',
                  onTap: () {
                    navigationService.toggleReorderMode();
                    onClose();
                  },
                ),
                // Reset order (only in reorder mode)
                if (navigationService.isReorderMode)
                  _OptionTile(
                    icon: Icons.restart_alt,
                    label: 'Restaurar orden',
                    onTap: () {
                      navigationService.resetModuleOrder();
                      onClose();
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _OptionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _OptionTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Icon(icon,
                size: 18, color: theme.colorScheme.onSurface.withValues(alpha: 0.7)),
            const SizedBox(width: 12),
            Text(label, style: theme.textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}

class MainLayout extends StatefulWidget {
  final Widget? child;
  final Widget? body;
  final String? title;
  final VoidCallback? onBackPressed;

  const MainLayout({
    super.key,
    this.child,
    this.body,
    this.title,
    this.onBackPressed,
  });

  @override
  State<MainLayout> createState() => _MainLayoutState();
}

class _MainLayoutState extends State<MainLayout> {
  OverlayEntry? _currentNotificationOverlay;
  Timer? _notificationTimer;

  @override
  void initState() {
    super.initState();
    // Listen for incoming messages to show in-app notification
    NotificationService().messageStream.listen((message) {
      if (!mounted) return;

      // FORCE ChatProvider refresh to ensure badge updates immediately
      // This covers cases where ChatProvider's internal listener might have missed it
      context.read<ChatProvider>().loadConversations();

      final notification = message.notification;
      final title = notification?.title ?? 'Nuevo Mensaje';
      final body = notification?.body ?? '';

      _showTopNotification(title, body);
    });
  }

  void _showTopNotification(String title, String body) {
    _notificationTimer?.cancel();
    _currentNotificationOverlay?.remove();

    final overlay = OverlayEntry(
      builder: (context) => Positioned(
        top: 10, // Very close to the top edge
        left: 16,
        right: 16,
        child: Material(
          color: Colors.transparent,
          child: Center(
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: -100, end: 0), // Start further up
              duration: const Duration(milliseconds: 400),
              curve: Curves.easeOutQuart, // Smoother curve
              builder: (context, value, child) {
                return Transform.translate(
                  offset: Offset(0, value),
                  child: Opacity(
                    // Fade in as it slides down (simple mapping)
                    opacity: (1 - (value / -100)).clamp(0.0, 1.0),
                    child: child,
                  ),
                );
              },
              child: Container(
                constraints: const BoxConstraints(maxWidth: 400),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.inverseSurface,
                  borderRadius: BorderRadius.circular(30),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.2),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: InkWell(
                  onTap: () {
                    context.go('/chat');
                    _currentNotificationOverlay?.remove();
                    _currentNotificationOverlay = null;
                  },
                  borderRadius: BorderRadius.circular(30),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.chat_bubble_outline,
                            size: 18,
                            color:
                                Theme.of(context).colorScheme.onInverseSurface),
                        const SizedBox(width: 12),
                        Flexible(
                          child: Text(
                            '$title: $body',
                            style: TextStyle(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onInverseSurface,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    Overlay.of(context).insert(overlay);
    _currentNotificationOverlay = overlay;

    _notificationTimer = Timer(const Duration(seconds: 4), () {
      _currentNotificationOverlay?.remove();
      _currentNotificationOverlay = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final showSidebar = screenWidth > 768; // Show sidebar on larger screens
    final navigationService = Provider.of<NavigationService>(context);

    if (showSidebar) {
      // Desktop layout with collapsible sidebar
      return Scaffold(
        body: Row(
          children: [
            // Collapsible Sidebar with smart animation
            // No animation during resize for instant tracking
            // Animation only for collapse/expand
            AnimatedContainer(
              duration: navigationService.isResizing
                  ? Duration.zero
                  : const Duration(milliseconds: 250),
              curve: Curves.easeInOut,
              width: navigationService.isDrawerVisible
                  ? navigationService.drawerWidth
                  : 0,
              child: navigationService.isDrawerVisible
                  ? Container(
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface,
                      ),
                      child: const AppSidebar(),
                    )
                  : const SizedBox.shrink(),
            ),
            Expanded(
              child: Row(
                children: [
                  Expanded(
                    child: Stack(
                      children: [
                        // Main content with border (no app bar)
                        Container(
                          decoration: navigationService.isDrawerVisible
                              ? BoxDecoration(
                                  border: Border(
                                    left: BorderSide(
                                      color: Theme.of(context).dividerColor,
                                      width: 1,
                                    ),
                                  ),
                                )
                              : null,
                          child: widget.body ?? widget.child,
                        ),
                        // Invisible resize handle on left edge (12px wide)
                        if (navigationService.isDrawerVisible)
                          Positioned(
                            left: 0,
                            top: 0,
                            bottom: 0,
                            width: 12,
                            child: MouseRegion(
                              cursor: SystemMouseCursors.resizeColumn,
                              child: GestureDetector(
                                behavior: HitTestBehavior.translucent,
                                onHorizontalDragStart: (details) {
                                  navigationService.startResizing();
                                },
                                onHorizontalDragUpdate: (details) {
                                  navigationService.updateDrawerWidth(
                                    navigationService.drawerWidth +
                                        details.delta.dx,
                                  );
                                },
                                onHorizontalDragEnd: (details) {
                                  navigationService.stopResizing();
                                },
                                child: Container(
                                  color: Colors.transparent,
                                ),
                              ),
                            ),
                          ),
                        // Small toggle button (bottom-left, only when drawer is hidden)
                        if (!navigationService.isDrawerVisible)
                          Positioned(
                            left: 8,
                            bottom: 8,
                            child: Material(
                              elevation: 4,
                              borderRadius: BorderRadius.circular(20),
                              child: InkWell(
                                onTap: () => navigationService.showDrawer(),
                                borderRadius: BorderRadius.circular(20),
                                child: Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color:
                                        Theme.of(context).colorScheme.surface,
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: const Icon(Icons.menu, size: 20),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // Right-side toolbar is rendered by _WorkspaceRouterView (above the router)
            // so it persists across navigation without flickering.
          ],
        ),
      );
    } else {
      // Mobile layout with drawer
      return Scaffold(
        appBar: AppBar(
          leading: widget.onBackPressed != null
              ? IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: widget.onBackPressed,
                  color: Theme.of(context).colorScheme.onSurface,
                )
              : Builder(
                  builder: (context) => IconButton(
                    icon: const Icon(Icons.menu),
                    onPressed: () => Scaffold.of(context).openDrawer(),
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
          title: Text(
            widget.title ?? 'Vinabike ERP',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface,
              fontWeight: FontWeight.bold,
            ),
          ),
          backgroundColor: Theme.of(context).colorScheme.surface,
          elevation: 0,
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(1.0),
            child: Container(
              color: Theme.of(context).dividerColor,
              height: 1.0,
            ),
          ),
          iconTheme: IconThemeData(
            color: Theme.of(context).colorScheme.onSurface,
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.notifications_outlined),
              onPressed: () {
                // TODO: Implement notifications
              },
              color: Theme.of(context).colorScheme.onSurface,
            ),
            IconButton(
              icon: const Icon(Icons.settings_outlined),
              onPressed: () {
                context.push('/settings');
              },
              color: Theme.of(context).colorScheme.onSurface,
            ),
            IconButton(
              icon: const Icon(Icons.logout_outlined),
              onPressed: () => _handleLogout(context),
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ],
        ),
        drawer: const AppDrawer(),
        body: widget.body ?? widget.child,
      );
    }
  }
}

Future<void> _handleLogout(BuildContext context) async {
  final authService = context.read<AuthService>();
  final router = GoRouter.of(context);

  try {
    await authService.signOut();
    router.go('/login');
  } catch (error) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.showSnackBar(
      SnackBar(content: Text('No se pudo cerrar sesión: $error')),
    );
  }
}

class AppSidebar extends StatefulWidget {
  const AppSidebar({super.key});

  @override
  State<AppSidebar> createState() => _AppSidebarState();
}

class _AppSidebarState extends State<AppSidebar> {
  // Local state for last location to detect changes
  String? _lastLocation;

  // Module configuration for reordering
  Widget _buildModuleWidget(String moduleKey, String currentLocation,
      String? expandedSection, NavigationService navService) {
    switch (moduleKey) {
      case 'accounting':
        return ExpandableMenuItem(
          key: ValueKey(moduleKey),
          icon: Icons.account_balance_outlined,
          activeIcon: Icons.account_balance,
          title: 'Contabilidad',
          currentLocation: currentLocation,
          subItems: _accountingMenuItems,
          isExpanded: expandedSection == _accountingSectionKey,
          onExpansionChanged: (expand) =>
              _handleExpansionChange(_accountingSectionKey, expand, navService),
        );
      case 'tax_reports':
        return ExpandableMenuItem(
          key: ValueKey(moduleKey),
          icon: Icons.receipt_long_outlined,
          activeIcon: Icons.receipt_long,
          title: 'Impuestos',
          currentLocation: currentLocation,
          subItems: _taxReportsMenuItems,
          isExpanded: expandedSection == _taxReportsSectionKey,
          onExpansionChanged: (expand) =>
              _handleExpansionChange(_taxReportsSectionKey, expand, navService),
        );
      case 'chat':
        return Consumer<ChatProvider>(
          builder: (context, chatProvider, _) {
            return ExpandableMenuItem(
              key: ValueKey(moduleKey),
              icon: Icons.chat_outlined,
              activeIcon: Icons.chat,
              title: 'Mensajería',
              currentLocation: currentLocation,
              subItems: _chatMenuItems,
              isExpanded: expandedSection == _chatSectionKey,
              onExpansionChanged: (expand) =>
                  _handleExpansionChange(_chatSectionKey, expand, navService),
              isSingleItem: true,
              badgeCount: chatProvider.totalUnreadCount,
            );
          },
        );
      case 'customers':
        return ExpandableMenuItem(
          key: ValueKey(moduleKey),
          icon: Icons.people_outline,
          activeIcon: Icons.people,
          title: 'Clientes',
          currentLocation: currentLocation,
          subItems: _customersMenuItems,
          isExpanded: expandedSection == _customersSectionKey,
          onExpansionChanged: (expand) =>
              _handleExpansionChange(_customersSectionKey, expand, navService),
        );
      case 'workshop':
        return ExpandableMenuItem(
          key: ValueKey(moduleKey),
          icon: Icons.pedal_bike_outlined,
          activeIcon: Icons.pedal_bike,
          title: 'Taller',
          currentLocation: currentLocation,
          subItems: _workshopMenuItems,
          isExpanded: expandedSection == _workshopSectionKey,
          onExpansionChanged: (expand) =>
              _handleExpansionChange(_workshopSectionKey, expand, navService),
        );
      case 'smart_features':
        return ExpandableMenuItem(
          key: ValueKey(moduleKey),
          icon: Icons.lightbulb_outlined,
          activeIcon: Icons.lightbulb,
          title: 'Smart Features',
          currentLocation: currentLocation,
          subItems: _smartFeaturesMenuItems,
          isExpanded: expandedSection == _smartFeaturesSectionKey,
          onExpansionChanged: (expand) => _handleExpansionChange(
              _smartFeaturesSectionKey, expand, navService),
        );
      case 'inventory':
        return ExpandableMenuItem(
          key: ValueKey(moduleKey),
          icon: Icons.inventory_2_outlined,
          activeIcon: Icons.inventory_2,
          title: 'Inventario',
          currentLocation: currentLocation,
          subItems: _inventoryMenuItems,
          isExpanded: expandedSection == _inventorySectionKey,
          onExpansionChanged: (expand) =>
              _handleExpansionChange(_inventorySectionKey, expand, navService),
        );
      case 'sales':
        return ExpandableMenuItem(
          key: ValueKey(moduleKey),
          icon: Icons.receipt_long_outlined,
          activeIcon: Icons.receipt_long,
          title: 'Ventas',
          currentLocation: currentLocation,
          subItems: _salesMenuItems,
          isExpanded: expandedSection == _salesSectionKey,
          onExpansionChanged: (expand) =>
              _handleExpansionChange(_salesSectionKey, expand, navService),
        );
      case 'purchases':
        return ExpandableMenuItem(
          key: ValueKey(moduleKey),
          icon: Icons.shopping_cart_outlined,
          activeIcon: Icons.shopping_cart,
          title: 'Compras',
          currentLocation: currentLocation,
          subItems: _purchasesMenuItems,
          isExpanded: expandedSection == _purchasesSectionKey,
          onExpansionChanged: (expand) =>
              _handleExpansionChange(_purchasesSectionKey, expand, navService),
        );
      case 'pos':
        return ExpandableMenuItem(
          key: ValueKey(moduleKey),
          icon: Icons.point_of_sale_outlined,
          activeIcon: Icons.point_of_sale,
          title: 'POS',
          currentLocation: currentLocation,
          subItems: _posMenuItems,
          isExpanded: expandedSection == _posSectionKey,
          onExpansionChanged: (expand) =>
              _handleExpansionChange(_posSectionKey, expand, navService),
        );
      case 'hr':
        return ExpandableMenuItem(
          key: ValueKey(moduleKey),
          icon: Icons.badge_outlined,
          activeIcon: Icons.badge,
          title: 'RR.HH.',
          currentLocation: currentLocation,
          subItems: _hrMenuItems,
          isExpanded: expandedSection == _hrSectionKey,
          onExpansionChanged: (expand) =>
              _handleExpansionChange(_hrSectionKey, expand, navService),
        );
      case 'tools':
        return ExpandableMenuItem(
          key: ValueKey(moduleKey),
          icon: Icons.build_circle_outlined,
          activeIcon: Icons.build_circle,
          title: 'Herramientas',
          currentLocation: currentLocation,
          subItems: _toolsMenuItems,
          isExpanded: expandedSection == _toolsSectionKey,
          onExpansionChanged: (expand) =>
              _handleExpansionChange(_toolsSectionKey, expand, navService),
        );
      case 'debug':
        return ExpandableMenuItem(
          key: ValueKey(moduleKey),
          icon: Icons.bug_report_outlined,
          activeIcon: Icons.bug_report,
          title: 'Debug',
          currentLocation: currentLocation,
          subItems: _debugMenuItems,
          isExpanded: expandedSection == _debugSectionKey,
          onExpansionChanged: (expand) =>
              _handleExpansionChange(_debugSectionKey, expand, navService),
        );
      default:
        return const SizedBox.shrink();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // Defer GoRouter access to avoid blocking Navigator.push navigation
    // This is critical - accessing GoRouter synchronously blocks the UI thread
    Future.microtask(() {
      if (!mounted) return;

      try {
        // Check if GoRouter is available first
        final router = GoRouter.maybeOf(context);
        if (router == null) {
          debugPrint('⚠️ AppSidebar: GoRouter not available (Navigator.push?)');
          return;
        }

        final routerState = GoRouterState.of(context);
        final currentLocation = routerState.uri.path;
        if (currentLocation != _lastLocation) {
          _lastLocation = currentLocation;

          // Update workspace tab title based on current route
          final workspaceManager = context.read<WorkspaceManager>();
          workspaceManager.updateActiveWorkspaceRoute(currentLocation);

          final matchingSection = _resolveSectionForPath(currentLocation);
          final navService = context.read<NavigationService>();

          if (matchingSection != navService.expandedSection && mounted) {
            navService.setExpandedSection(matchingSection);
          }
        }
      } catch (e) {
        // Silently ignore - not a fatal error when using Navigator.push
        debugPrint('⚠️ AppSidebar: Could not access GoRouterState: $e');
      }
    });
  }

  void _handleExpansionChange(
      String sectionKey, bool expand, NavigationService navService) {
    if (expand) {
      navService.setExpandedSection(sectionKey);
    } else if (navService.expandedSection == sectionKey) {
      navService.setExpandedSection(null);
    }
  }

  String? _resolveSectionForPath(String location) {
    if (_matchesLocation(location, _accountingMenuItems)) {
      return _accountingSectionKey;
    }
    if (_matchesLocation(location, _customersMenuItems)) {
      return _customersSectionKey;
    }
    if (_matchesLocation(location, _workshopMenuItems)) {
      return _workshopSectionKey;
    }
    if (_matchesLocation(location, _smartFeaturesMenuItems)) {
      return _smartFeaturesSectionKey;
    }
    if (_matchesLocation(location, _inventoryMenuItems)) {
      return _inventorySectionKey;
    }
    if (_matchesLocation(location, _salesMenuItems)) {
      return _salesSectionKey;
    }
    if (_matchesLocation(location, _purchasesMenuItems)) {
      return _purchasesSectionKey;
    }
    if (_matchesLocation(location, _posMenuItems)) {
      return _posSectionKey;
    }
    if (_matchesLocation(location, _hrMenuItems)) {
      return _hrSectionKey;
    }
    if (_matchesLocation(location, _debugMenuItems)) {
      return _debugSectionKey;
    }
    return null;
  }

  bool _matchesLocation(String location, List<MenuSubItem> items) {
    for (final item in items) {
      if (location == item.route || location.startsWith('${item.route}/')) {
        return true;
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    // Safely get current location, fallback to empty string if not in GoRouter context
    String currentLocation = '';
    try {
      final routerState = GoRouter.maybeOf(context);
      if (routerState != null) {
        currentLocation = GoRouterState.of(context).uri.path;
      }
    } catch (e) {
      // Not in GoRouter context (e.g., opened via Navigator.push)
      currentLocation = '';
    }
    final theme = Theme.of(context);

    return Container(
      color: theme.colorScheme.surface,
      child: Column(
        children: [
          // Company Header
          Container(
            height: 64,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: theme.dividerColor,
                  width: 1,
                ),
              ),
            ),
            child: Consumer<AppearanceService>(
              builder: (context, appearanceService, _) {
                return InkWell(
                  onTap: () {
                    // Navigate directly to dashboard (not workspace tab)
                    context.go('/dashboard');
                  },
                  borderRadius: BorderRadius.circular(6),
                  child: Row(
                    children: [
                      if (appearanceService.hasCustomLogo)
                        // Show custom logo
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: CachedNetworkImage(
                              imageUrl: appearanceService.companyLogoUrl!,
                              fit: BoxFit.contain,
                              imageBuilder: (context, imageProvider) => Image(
                                image: imageProvider,
                                fit: BoxFit.contain,
                                filterQuality: FilterQuality.high,
                              ),
                              placeholder: (context, url) => const Center(
                                child: SizedBox(
                                  width: 20,
                                  height: 20,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                ),
                              ),
                              errorWidget: (context, url, error) =>
                                  _buildDefaultHeader(
                                      context, theme, appearanceService),
                            ),
                          ),
                        )
                      else
                        // Show default header with icon and text
                        ..._buildDefaultHeaderWidgets(
                            context, theme, appearanceService),
                    ],
                  ),
                );
              },
            ),
          ),

          // Navigation Menu
          Expanded(
            child: Consumer<NavigationService>(
              builder: (context, navigationService, _) {
                final moduleOrder = navigationService.moduleOrder;
                final isReorderMode = navigationService.isReorderMode;

                if (isReorderMode) {
                  // Reorder mode: Show ReorderableListView
                  return ReorderableListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    buildDefaultDragHandles: false,
                    itemCount:
                        moduleOrder.length + 2, // +2 for dashboard and divider
                    onReorder: (oldIndex, newIndex) {
                      // Adjust for dashboard item (index 0) and divider (index 1)
                      if (oldIndex < 2 || newIndex < 2) return;
                      navigationService.reorderModules(
                          oldIndex - 2, newIndex - 2);
                    },
                    itemBuilder: (context, index) {
                      if (index == 0) {
                        // Dashboard (non-reorderable)
                        return Container(
                          key: const ValueKey('dashboard'),
                          child: Column(
                            children: [
                              _buildSidebarItem(
                                context,
                                icon: Icons.dashboard_outlined,
                                activeIcon: Icons.dashboard,
                                title: 'Inicio',
                                route: '/dashboard',
                                currentLocation: currentLocation,
                              ),
                              const SizedBox(height: 8),
                            ],
                          ),
                        );
                      }
                      if (index == 1) {
                        // Divider (non-reorderable)
                        return Container(
                          key: const ValueKey('divider'),
                          child: _buildSectionDivider(context),
                        );
                      }
                      // Module items
                      final moduleIndex = index - 2;
                      final moduleKey = moduleOrder[moduleIndex];
                      return ReorderableDragStartListener(
                        key: ValueKey(moduleKey),
                        index: index,
                        child: Container(
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surface,
                            border: Border.all(
                              color: theme.colorScheme.primary.withValues(alpha: 0.3),
                              width: 1,
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          margin: const EdgeInsets.symmetric(
                              horizontal: 4, vertical: 2),
                          child: Row(
                            children: [
                              Padding(
                                padding: const EdgeInsets.all(8.0),
                                child: Icon(
                                  Icons.drag_indicator,
                                  size: 18,
                                  color: theme.colorScheme.primary
                                      .withValues(alpha: 0.6),
                                ),
                              ),
                              Expanded(
                                child: _buildModuleWidget(
                                    moduleKey,
                                    currentLocation,
                                    navigationService.expandedSection,
                                    navigationService),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                }

                // Normal mode: Regular ListView
                return ListView(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  children: [
                    // Dashboard
                    _buildSidebarItem(
                      context,
                      icon: Icons.dashboard_outlined,
                      activeIcon: Icons.dashboard,
                      title: 'Inicio',
                      route: '/dashboard',
                      currentLocation: currentLocation,
                    ),

                    const SizedBox(height: 8),

                    // Core Modules Section
                    _buildSectionDivider(context),

                    // Render modules in custom order
                    ...moduleOrder.map((moduleKey) => _buildModuleWidget(
                        moduleKey,
                        currentLocation,
                        navigationService.expandedSection,
                        navigationService)),

                    const SizedBox(height: 8),
                    _buildSectionDivider(context),

                    // Website Module
                    _buildSidebarItem(
                      context,
                      icon: Icons.web_outlined,
                      activeIcon: Icons.web,
                      title: 'Sitio Web',
                      route: '/website',
                      currentLocation: currentLocation,
                      enabled: true,
                    ),

                    // Correo (Zoho Mail)
                    _buildSidebarItem(
                      context,
                      icon: Icons.email_outlined,
                      activeIcon: Icons.email,
                      title: 'Correo',
                      route: '/mail',
                      currentLocation: currentLocation,
                      enabled: true,
                    ),

                    // Additional Modules (Disabled for now)
                    _buildSidebarItem(
                      context,
                      icon: Icons.build_outlined,
                      activeIcon: Icons.build,
                      title: 'Mantención',
                      route: '/maintenance',
                      currentLocation: currentLocation,
                      enabled: false,
                    ),

                    _buildSidebarItem(
                      context,
                      icon: Icons.analytics_outlined,
                      activeIcon: Icons.analytics,
                      title: 'Análisis',
                      route: '/analytics',
                      currentLocation: currentLocation,
                      enabled: false,
                    ),
                  ],
                );
              },
            ),
          ),

          // Bottom section
          Container(
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(
                  color: theme.dividerColor,
                  width: 1,
                ),
              ),
            ),
            child: Column(
              children: [
                // Settings
                _buildSidebarItem(
                  context,
                  icon: Icons.settings_outlined,
                  activeIcon: Icons.settings,
                  title: 'Configuración',
                  route: '/settings',
                  currentLocation: currentLocation,
                  enabled: true,
                ),

                // Logout
                Container(
                  margin:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () => _handleLogout(context),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.logout_outlined,
                              size: 20,
                              color:
                                  theme.colorScheme.onSurface.withValues(alpha: 0.7),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Cerrar Sesión',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.colorScheme.onSurface
                                      .withValues(alpha: 0.7),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

                // Hide navigation button (bottom-right, small like Zoho)
                Consumer<NavigationService>(
                  builder: (context, navigationService, _) {
                    return Container(
                      padding: const EdgeInsets.only(
                          left: 8, right: 8, top: 8, bottom: 8),
                      child: Row(
                        children: [
                          // 3-dot menu button
                          IconButton(
                            icon: Icon(
                              Icons.more_horiz,
                              size: 18,
                              color:
                                  theme.colorScheme.onSurface.withValues(alpha: 0.6),
                            ),
                            iconSize: 18,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                              minWidth: 32,
                              minHeight: 32,
                            ),
                            tooltip: 'Opciones',
                            onPressed: () {
                              _showSidebarOptionsMenu(
                                  context, navigationService);
                            },
                          ),
                          const Spacer(),
                          // Hide navigation button
                          IconButton(
                            icon: const Icon(Icons.chevron_left, size: 18),
                            iconSize: 18,
                            padding: const EdgeInsets.all(8),
                            constraints: const BoxConstraints(
                              minWidth: 32,
                              minHeight: 32,
                            ),
                            tooltip: 'Ocultar menú',
                            onPressed: () {
                              navigationService.hideDrawer();
                            },
                            style: IconButton.styleFrom(
                              backgroundColor: theme.colorScheme.surface,
                              foregroundColor:
                                  theme.colorScheme.onSurface.withValues(alpha: 0.6),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionDivider(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      height: 1,
      color: Theme.of(context).dividerColor.withValues(alpha: 0.5),
    );
  }

  Widget _buildSidebarItem(
    BuildContext context, {
    required IconData icon,
    required IconData activeIcon,
    required String title,
    required String route,
    required String currentLocation,
    bool enabled = true,
  }) {
    final isSelected = currentLocation.startsWith(route);
    final theme = Theme.of(context);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: enabled
              ? () {
                  if (!isSelected) {
                    // Dashboard, Website, Settings, and Mail navigate directly within current workspace
                    // All other modules can open in new workspace tabs if needed
                    if (route == '/dashboard' ||
                        route == '/website' ||
                        route == '/settings' ||
                        route == '/mail') {
                      debugPrint(
                          '🔀 [MainLayout] Navigating to $route in current workspace');
                      context.go(route);
                    } else {
                      _openInWorkspace(
                          context, route, _getTitleFromRoute(route));
                    }
                  }
                }
              : null,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              color: isSelected
                  ? theme.primaryColor.withValues(alpha: 0.1)
                  : Colors.transparent,
            ),
            child: Row(
              children: [
                Icon(
                  isSelected ? activeIcon : icon,
                  size: 20,
                  color: enabled
                      ? (isSelected
                          ? theme.primaryColor
                          : theme.colorScheme.onSurface.withValues(alpha: 0.7))
                      : theme.disabledColor,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight:
                          isSelected ? FontWeight.w600 : FontWeight.normal,
                      color: enabled
                          ? (isSelected
                              ? theme.primaryColor
                              : theme.colorScheme.onSurface)
                          : theme.disabledColor,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Helper method to build default header widgets
  List<Widget> _buildDefaultHeaderWidgets(
    BuildContext context,
    ThemeData theme,
    AppearanceService appearanceService,
  ) {
    return [
      Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: theme.primaryColor,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Icon(
          appearanceService.homeIcon,
          color: theme.colorScheme.onPrimary,
          size: 18,
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'Vinabike',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              'ERP Sistema',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
      ),
    ];
  }

  // Helper method to build default header as a single widget
  Widget _buildDefaultHeader(
    BuildContext context,
    ThemeData theme,
    AppearanceService appearanceService,
  ) {
    return Row(
      children: _buildDefaultHeaderWidgets(context, theme, appearanceService),
    );
  }
}

class AppDrawer extends StatefulWidget {
  const AppDrawer({super.key});

  @override
  State<AppDrawer> createState() => _AppDrawerState();
}

class _AppDrawerState extends State<AppDrawer> {
  String? _expandedSection;

  void _handleExpansionChange(String sectionKey, bool isExpanded) {
    setState(() {
      if (isExpanded) {
        _expandedSection = sectionKey;
      } else if (_expandedSection == sectionKey) {
        _expandedSection = null;
      }
    });
  }

  void _handleMobileNavigation(
      BuildContext context, String route, String title) {
    // Check for mobile/tablet screen width (< 800px)
    // If small screen, use standard navigation instead of workspace tabs
    final isSmallScreen = MediaQuery.of(context).size.width < 800;

    if (isSmallScreen) {
      context.push(route);
    } else {
      // Logic from _openInWorkspace but safe to call
      try {
        final workspaceManager = context.read<WorkspaceManager>();
        final existingFound =
            workspaceManager.switchToExistingWorkspaceWithRoute(route);
        if (!existingFound) {
          workspaceManager.addWorkspace(
            title: title,
            initialRoute: route,
          );
        }
      } catch (e) {
        context.go(route);
      }
    }
  }

  /// Shows a bottom sheet with reorderable module list
  void _showReorderSheet(BuildContext context) {
    final navigationService = context.read<NavigationService>();

    // Module key to display name and icon mapping
    const moduleInfo = <String, (String, IconData)>{
      'accounting': ('Contabilidad', Icons.account_balance),
      'tax_reports': ('Impuestos', Icons.receipt_long),
      'customers': ('Clientes', Icons.people),
      'chat': ('Mensajería', Icons.chat_bubble),
      'workshop': ('Taller', Icons.build),
      'smart_features': ('Smart Features', Icons.auto_awesome),
      'inventory': ('Inventario', Icons.inventory_2),
      'sales': ('Ventas', Icons.point_of_sale),
      'purchases': ('Compras', Icons.shopping_cart),
      'pos': ('POS', Icons.storefront),
      'hr': ('RR.HH.', Icons.badge),
      'tools': ('Herramientas', Icons.build_circle),
    };

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            // Get a mutable copy of the order
            final moduleOrder =
                List<String>.from(navigationService.moduleOrder);

            return DraggableScrollableSheet(
              initialChildSize: 0.7,
              minChildSize: 0.5,
              maxChildSize: 0.9,
              expand: false,
              builder: (context, scrollController) {
                return Column(
                  children: [
                    // Header
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(
                            color: Theme.of(context).colorScheme.outlineVariant,
                          ),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.swap_vert),
                          const SizedBox(width: 12),
                          Text(
                            'Reordenar Módulos',
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                          const Spacer(),
                          TextButton(
                            onPressed: () {
                              navigationService.resetModuleOrder();
                              Navigator.pop(context);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Orden restaurado'),
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                            },
                            child: const Text('Restaurar'),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () => Navigator.pop(context),
                          ),
                        ],
                      ),
                    ),
                    // Instruction
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        'Mantén presionado y arrastra para reordenar',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                      ),
                    ),
                    // Reorderable List
                    Expanded(
                      child: ReorderableListView.builder(
                        itemCount: moduleOrder.length,
                        onReorder: (oldIndex, newIndex) {
                          setSheetState(() {
                            if (oldIndex < newIndex) newIndex -= 1;
                            final item = moduleOrder.removeAt(oldIndex);
                            moduleOrder.insert(newIndex, item);
                          });
                          // Persist the change
                          navigationService.reorderModules(oldIndex, newIndex);
                        },
                        itemBuilder: (context, index) {
                          final key = moduleOrder[index];
                          final info = moduleInfo[key];
                          final title = info?.$1 ?? key;
                          final icon = info?.$2 ?? Icons.extension;

                          return ListTile(
                            key: ValueKey(key),
                            leading: Icon(icon),
                            title: Text(title),
                            trailing: ReorderableDragStartListener(
                              index: index,
                              child: const Icon(Icons.drag_handle),
                            ),
                          );
                        },
                      ),
                    ),
                    // Done button
                    SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            onPressed: () {
                              Navigator.pop(context);
                              Navigator.pop(context); // Close drawer too
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Orden guardado'),
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                            },
                            child: const Text('Listo'),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // Safely get current location
    String currentLocation = '';
    try {
      currentLocation = GoRouterState.of(context).uri.path;
    } catch (e) {
      currentLocation = '';
    }

    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          DrawerHeader(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              border: Border(
                bottom: BorderSide(
                  color: Theme.of(context).dividerColor,
                  width: 1,
                ),
              ),
            ),
            child: Consumer<AppearanceService>(
              builder: (context, appearanceService, _) {
                return InkWell(
                  onTap: () {
                    // Navigate to dashboard when header is clicked
                    Navigator.pop(context); // Close drawer first
                    _handleMobileNavigation(context, '/dashboard', 'Dashboard');
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: appearanceService.hasCustomLogo
                      ? Padding(
                          padding: const EdgeInsets.all(8),
                          child: CachedNetworkImage(
                            imageUrl: appearanceService.companyLogoUrl!,
                            fit: BoxFit.contain,
                            imageBuilder: (context, imageProvider) => Image(
                              image: imageProvider,
                              fit: BoxFit.contain,
                              filterQuality: FilterQuality.high,
                            ),
                            placeholder: (context, url) {
                              final theme = Theme.of(context);
                              return Center(
                                child: CircularProgressIndicator(
                                  color: theme.colorScheme.primary,
                                ),
                              );
                            },
                            errorWidget: (context, url, error) =>
                                _Helper.buildDefaultDrawerHeader(
                                    context, appearanceService),
                          ),
                        )
                      : _Helper.buildDefaultDrawerHeader(
                          context, appearanceService),
                );
              },
            ),
          ),

          // Dashboard
          ExpandableMenuItem(
            icon: Icons.dashboard_outlined,
            activeIcon: Icons.dashboard,
            title: 'Dashboard',
            subItems: const [
              MenuSubItem(
                  icon: Icons.dashboard,
                  title: 'Dashboard',
                  route: '/dashboard')
            ],
            currentLocation: currentLocation,
            isSingleItem: true,
            onNavigate: (route) {
              Navigator.pop(context);
              _handleMobileNavigation(context, route, 'Dashboard');
            },
          ),

          const Divider(),

          // Core Modules
          _Helper.buildSectionHeader(context, 'MÓDULOS PRINCIPALES'),

          // Mensajería (Chat)
          Consumer<ChatProvider>(
            builder: (context, chatProvider, child) {
              return ExpandableMenuItem(
                icon: Icons.chat_bubble_outline,
                activeIcon: Icons.chat_bubble,
                title: 'Mensajería',
                subItems: const [
                  MenuSubItem(
                      icon: Icons.chat, title: 'Mensajería', route: '/chat')
                ],
                currentLocation: currentLocation,
                isSingleItem: true,
                badgeCount: chatProvider.totalUnreadCount,
                onNavigate: (route) {
                  Navigator.pop(context);
                  _handleMobileNavigation(context, route, 'Mensajería');
                },
              );
            },
          ),

          ExpandableMenuItem(
            icon: Icons.account_balance_outlined,
            activeIcon: Icons.account_balance,
            title: 'Contabilidad',
            subItems: _accountingMenuItems,
            currentLocation: currentLocation,
            isExpanded: _expandedSection == 'accounting',
            onExpansionChanged: (expand) =>
                _handleExpansionChange('accounting', expand),
            onNavigate: (route) {
              Navigator.pop(context);
              _handleMobileNavigation(context, route, 'Contabilidad');
            },
          ),

          ExpandableMenuItem(
            icon: Icons.people_outline,
            activeIcon: Icons.people,
            title: 'Clientes',
            subItems: _customersMenuItems,
            currentLocation: currentLocation,
            isExpanded: _expandedSection == 'customers',
            onExpansionChanged: (expand) =>
                _handleExpansionChange('customers', expand),
            onNavigate: (route) {
              Navigator.pop(context);
              _handleMobileNavigation(context, route, 'Clientes');
            },
          ),

          ExpandableMenuItem(
            icon: Icons.pedal_bike_outlined,
            activeIcon: Icons.pedal_bike,
            title: 'Taller',
            subItems: _workshopMenuItems,
            currentLocation: currentLocation,
            isExpanded: _expandedSection == 'workshop',
            onExpansionChanged: (expand) =>
                _handleExpansionChange('workshop', expand),
            onNavigate: (route) {
              Navigator.pop(context);
              _handleMobileNavigation(context, route, 'Taller');
            },
          ),

          ExpandableMenuItem(
            icon: Icons.lightbulb_outlined,
            activeIcon: Icons.lightbulb,
            title: 'Smart Features',
            subItems: _smartFeaturesMenuItems,
            currentLocation: currentLocation,
            isExpanded: _expandedSection == 'smart_features',
            onExpansionChanged: (expand) =>
                _handleExpansionChange('smart_features', expand),
            onNavigate: (route) {
              Navigator.pop(context);
              _handleMobileNavigation(context, route, 'Smart Features');
            },
          ),

          ExpandableMenuItem(
            icon: Icons.inventory_2_outlined,
            activeIcon: Icons.inventory_2,
            title: 'Inventario',
            subItems: _inventoryMenuItems,
            currentLocation: currentLocation,
            isExpanded: _expandedSection == 'inventory',
            onExpansionChanged: (expand) =>
                _handleExpansionChange('inventory', expand),
            onNavigate: (route) {
              Navigator.pop(context);
              _handleMobileNavigation(context, route, 'Inventario');
            },
          ),

          ExpandableMenuItem(
            icon: Icons.receipt_long_outlined,
            activeIcon: Icons.receipt_long,
            title: 'Ventas',
            subItems: _salesMenuItems,
            currentLocation: currentLocation,
            isExpanded: _expandedSection == 'sales',
            onExpansionChanged: (expand) =>
                _handleExpansionChange('sales', expand),
            onNavigate: (route) {
              Navigator.pop(context);
              _handleMobileNavigation(context, route, 'Ventas');
            },
          ),

          ExpandableMenuItem(
            icon: Icons.shopping_cart_outlined,
            activeIcon: Icons.shopping_cart,
            title: 'Compras',
            subItems: _purchasesMenuItems,
            currentLocation: currentLocation,
            isExpanded: _expandedSection == 'purchases',
            onExpansionChanged: (expand) =>
                _handleExpansionChange('purchases', expand),
            onNavigate: (route) {
              Navigator.pop(context);
              _handleMobileNavigation(context, route, 'Compras');
            },
          ),

          ExpandableMenuItem(
            icon: Icons.point_of_sale_outlined,
            activeIcon: Icons.point_of_sale,
            title: 'POS',
            subItems: _posMenuItems,
            currentLocation: currentLocation,
            isExpanded: _expandedSection == 'pos',
            onExpansionChanged: (expand) =>
                _handleExpansionChange('pos', expand),
            onNavigate: (route) {
              Navigator.pop(context);
              _handleMobileNavigation(context, route, 'POS');
            },
          ),

          ExpandableMenuItem(
            icon: Icons.people_outline,
            activeIcon: Icons.people,
            title: 'RR.HH.',
            subItems: _hrMenuItems,
            currentLocation: currentLocation,
            isExpanded: _expandedSection == 'hr',
            onExpansionChanged: (expand) =>
                _handleExpansionChange('hr', expand),
            onNavigate: (route) {
              Navigator.pop(context);
              _handleMobileNavigation(context, route, 'RR.HH.');
            },
          ),

          const Divider(),

          // Tools (WebView Modules)
          _Helper.buildSectionHeader(context, 'HERRAMIENTAS'),

          ExpandableMenuItem(
            icon: Icons.build_circle_outlined,
            activeIcon: Icons.build_circle,
            title: 'Herramientas Web',
            subItems: _toolsMenuItems,
            currentLocation: currentLocation,
            isExpanded: _expandedSection == 'tools',
            onExpansionChanged: (expand) =>
                _handleExpansionChange('tools', expand),
            onNavigate: (route) {
              Navigator.pop(context);
              _handleMobileNavigation(context, route, 'Herramientas');
            },
          ),

          const Divider(),

          // Secondary Modules
          _Helper.buildSectionHeader(context, 'OTROS MÓDULOS'),

          ExpandableMenuItem(
            icon: Icons.build_outlined,
            activeIcon: Icons.build,
            title: 'Mantención',
            subItems: const [
              MenuSubItem(
                  icon: Icons.build, title: 'Mantención', route: '/maintenance')
            ],
            currentLocation: currentLocation,
            isSingleItem: true,
            enabled: false,
            onNavigate: (_) {},
          ),

          ExpandableMenuItem(
            icon: Icons.analytics_outlined,
            activeIcon: Icons.analytics,
            title: 'Análisis',
            subItems: const [
              MenuSubItem(
                  icon: Icons.analytics, title: 'Análisis', route: '/analytics')
            ],
            currentLocation: currentLocation,
            isSingleItem: true,
            enabled: false,
            onNavigate: (_) {},
          ),

          // Sitio Web module - ADDED for mobile access
          ExpandableMenuItem(
            icon: Icons.web_outlined,
            activeIcon: Icons.web,
            title: 'Sitio Web',
            subItems: const [
              MenuSubItem(
                  icon: Icons.web, title: 'Sitio Web', route: '/website')
            ],
            currentLocation: currentLocation,
            isSingleItem: true,
            enabled: true,
            onNavigate: (route) {
              Navigator.pop(context);
              _handleMobileNavigation(context, route, 'Sitio Web');
            },
          ),

          // Correo (Mail) module - ADDED for mobile access
          ExpandableMenuItem(
            icon: Icons.email_outlined,
            activeIcon: Icons.email,
            title: 'Correo',
            subItems: const [
              MenuSubItem(icon: Icons.email, title: 'Correo', route: '/mail')
            ],
            currentLocation: currentLocation,
            isSingleItem: true,
            enabled: true,
            onNavigate: (route) {
              Navigator.pop(context);
              _handleMobileNavigation(context, route, 'Correo');
            },
          ),

          const Divider(),

          // Mobile Options Panel (Dark Mode, Zoom, Reorder)
          _Helper.buildSectionHeader(context, 'OPCIONES'),

          // Dark Mode Toggle
          Consumer<AppearanceService>(
            builder: (context, appearanceService, _) {
              final isDark = appearanceService.themeMode == ThemeMode.dark;
              return ListTile(
                leading: Icon(isDark ? Icons.light_mode : Icons.dark_mode),
                title: Text(isDark ? 'Modo claro' : 'Modo oscuro'),
                trailing: Switch(
                  value: isDark,
                  onChanged: (value) {
                    appearanceService
                        .setThemeMode(value ? ThemeMode.dark : ThemeMode.light);
                  },
                ),
                onTap: () {
                  final newMode = isDark ? ThemeMode.light : ThemeMode.dark;
                  appearanceService.setThemeMode(newMode);
                },
              );
            },
          ),

          // Zoom Controls - Now works on all platforms!
          Consumer<WindowZoomService>(
            builder: (context, zoomService, _) {
              final zoomPercent = (zoomService.scale * 100).round();
              return ListTile(
                leading: const Icon(Icons.zoom_in),
                title: const Text('Zoom'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.remove, size: 18),
                      onPressed: zoomService.scale > 0.5
                          ? () => zoomService.zoomOut()
                          : null,
                    ),
                    SizedBox(
                      width: 40,
                      child: Text(
                        '$zoomPercent%',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.add, size: 18),
                      onPressed: zoomService.scale < 3.0
                          ? () => zoomService.zoomIn()
                          : null,
                    ),
                  ],
                ),
              );
            },
          ),

          // Reorder Modules - Opens bottom sheet with drag-to-reorder
          ListTile(
            leading: const Icon(Icons.swap_vert),
            title: const Text('Reordenar módulos'),
            onTap: () => _showReorderSheet(context),
          ),

          const Divider(),

          // Settings
          ExpandableMenuItem(
            icon: Icons.settings_outlined,
            activeIcon: Icons.settings,
            title: 'Configuración',
            subItems: const [
              MenuSubItem(
                  icon: Icons.settings,
                  title: 'Configuración',
                  route: '/settings')
            ],
            currentLocation: currentLocation,
            isSingleItem: true,
            enabled: true, // Enabled!
            onNavigate: (route) {
              Navigator.pop(context);
              _handleMobileNavigation(context, route, 'Configuración');
            },
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _Helper {
  static Widget buildSectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.primary,
            ),
      ),
    );
  }

  static Widget buildDefaultDrawerHeader(
      BuildContext context, AppearanceService appearanceService) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(
            appearanceService.homeIcon,
            color: theme.colorScheme.primary,
            size: 48,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Vinabike ERP',
          style: TextStyle(
            color: theme.colorScheme.onSurface,
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          'Sistema Integral de Gestión',
          style: TextStyle(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
            fontSize: 14,
          ),
        ),
      ],
    );
  }
}
