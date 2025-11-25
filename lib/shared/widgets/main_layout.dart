import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../services/auth_service.dart';
import '../services/navigation_service.dart';
import '../services/workspace_manager.dart';
import '../../modules/settings/services/appearance_service.dart';
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
    '/taller/wheel-builder': 'Wheel Builder',
    '/taller/wheel-hubs': 'Hubs',
    '/taller/wheel-rims': 'Rims',
    '/taller/wheel-spokes': 'Spokes',
    '/inventory/products': 'Productos',
    '/inventory/categories': 'Categorías',
    '/sales/invoices': 'Ventas',
    '/purchases/suppliers': 'Compras',
    '/pos': 'POS',
    '/hr/employees': 'Trabajadores',
    '/website': 'Sitio Web',
    '/settings': 'Configuración',
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

// Tools (WebView embedded websites)
const List<MenuSubItem> _toolsMenuItems = [
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

class MainLayout extends StatelessWidget {
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
            // Main Content Area with left border
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
                    child: body ?? child,
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
                              navigationService.drawerWidth + details.delta.dx,
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
                              color: Theme.of(context).colorScheme.surface,
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
      );
    } else {
      // Mobile layout with drawer
      return Scaffold(
        appBar: AppBar(
          leading: onBackPressed != null
              ? IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: onBackPressed,
                )
              : null,
          title: Text(title ?? 'Vinabike ERP'),
          backgroundColor: Theme.of(context).colorScheme.inversePrimary,
          actions: [
            IconButton(
              icon: const Icon(Icons.notifications),
              onPressed: () {
                // TODO: Implement notifications
              },
            ),
            IconButton(
              icon: const Icon(Icons.settings),
              onPressed: () {
                context.push('/settings');
              },
            ),
            IconButton(
              icon: const Icon(Icons.logout),
              onPressed: () => _handleLogout(context),
            ),
          ],
        ),
        drawer: const AppDrawer(),
        body: body ?? child,
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
  String? _expandedSection;
  String? _lastLocation;

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
          final matchingSection = _resolveSectionForPath(currentLocation);
          if (matchingSection != _expandedSection && mounted) {
            setState(() {
              _expandedSection = matchingSection;
            });
          }
        }
      } catch (e) {
        // Silently ignore - not a fatal error when using Navigator.push
        debugPrint('⚠️ AppSidebar: Could not access GoRouterState: $e');
      }
    });
  }

  void _handleExpansionChange(String sectionKey, bool expand) {
    if (expand) {
      if (_expandedSection == sectionKey) {
        return;
      }
      setState(() {
        _expandedSection = sectionKey;
      });
    } else if (_expandedSection == sectionKey) {
      setState(() {
        _expandedSection = null;
      });
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
            child: ListView(
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

                ExpandableMenuItem(
                  icon: Icons.account_balance_outlined,
                  activeIcon: Icons.account_balance,
                  title: 'Contabilidad',
                  currentLocation: currentLocation,
                  subItems: _accountingMenuItems,
                  isExpanded: _expandedSection == _accountingSectionKey,
                  onExpansionChanged: (expand) =>
                      _handleExpansionChange(_accountingSectionKey, expand),
                ),

                ExpandableMenuItem(
                  icon: Icons.receipt_long_outlined,
                  activeIcon: Icons.receipt_long,
                  title: 'Impuestos',
                  currentLocation: currentLocation,
                  subItems: _taxReportsMenuItems,
                  isExpanded: _expandedSection == _taxReportsSectionKey,
                  onExpansionChanged: (expand) =>
                      _handleExpansionChange(_taxReportsSectionKey, expand),
                ),

                ExpandableMenuItem(
                  icon: Icons.people_outline,
                  activeIcon: Icons.people,
                  title: 'Clientes',
                  currentLocation: currentLocation,
                  subItems: _customersMenuItems,
                  isExpanded: _expandedSection == _customersSectionKey,
                  onExpansionChanged: (expand) =>
                      _handleExpansionChange(_customersSectionKey, expand),
                ),

                ExpandableMenuItem(
                  icon: Icons.pedal_bike_outlined,
                  activeIcon: Icons.pedal_bike,
                  title: 'Taller',
                  currentLocation: currentLocation,
                  subItems: _workshopMenuItems,
                  isExpanded: _expandedSection == _workshopSectionKey,
                  onExpansionChanged: (expand) =>
                      _handleExpansionChange(_workshopSectionKey, expand),
                ),

                ExpandableMenuItem(
                  icon: Icons.lightbulb_outlined,
                  activeIcon: Icons.lightbulb,
                  title: 'Smart Features',
                  currentLocation: currentLocation,
                  subItems: _smartFeaturesMenuItems,
                  isExpanded: _expandedSection == _smartFeaturesSectionKey,
                  onExpansionChanged: (expand) =>
                      _handleExpansionChange(_smartFeaturesSectionKey, expand),
                ),

                ExpandableMenuItem(
                  icon: Icons.inventory_2_outlined,
                  activeIcon: Icons.inventory_2,
                  title: 'Inventario',
                  currentLocation: currentLocation,
                  subItems: _inventoryMenuItems,
                  isExpanded: _expandedSection == _inventorySectionKey,
                  onExpansionChanged: (expand) =>
                      _handleExpansionChange(_inventorySectionKey, expand),
                ),

                ExpandableMenuItem(
                  icon: Icons.receipt_long_outlined,
                  activeIcon: Icons.receipt_long,
                  title: 'Ventas',
                  currentLocation: currentLocation,
                  subItems: _salesMenuItems,
                  isExpanded: _expandedSection == _salesSectionKey,
                  onExpansionChanged: (expand) =>
                      _handleExpansionChange(_salesSectionKey, expand),
                ),

                ExpandableMenuItem(
                  icon: Icons.shopping_cart_outlined,
                  activeIcon: Icons.shopping_cart,
                  title: 'Compras',
                  currentLocation: currentLocation,
                  subItems: _purchasesMenuItems,
                  isExpanded: _expandedSection == _purchasesSectionKey,
                  onExpansionChanged: (expand) =>
                      _handleExpansionChange(_purchasesSectionKey, expand),
                ),

                ExpandableMenuItem(
                  icon: Icons.point_of_sale_outlined,
                  activeIcon: Icons.point_of_sale,
                  title: 'POS',
                  currentLocation: currentLocation,
                  subItems: _posMenuItems,
                  isExpanded: _expandedSection == _posSectionKey,
                  onExpansionChanged: (expand) =>
                      _handleExpansionChange(_posSectionKey, expand),
                ),

                ExpandableMenuItem(
                  icon: Icons.badge_outlined,
                  activeIcon: Icons.badge,
                  title: 'RR.HH.',
                  currentLocation: currentLocation,
                  subItems: _hrMenuItems,
                  isExpanded: _expandedSection == _hrSectionKey,
                  onExpansionChanged: (expand) =>
                      _handleExpansionChange(_hrSectionKey, expand),
                ),

                const SizedBox(height: 8),
                _buildSectionDivider(context),
                const SizedBox(height: 8),

                // Tools (WebView Modules)
                ExpandableMenuItem(
                  icon: Icons.build_circle_outlined,
                  activeIcon: Icons.build_circle,
                  title: 'Herramientas',
                  currentLocation: currentLocation,
                  subItems: _toolsMenuItems,
                  isExpanded: _expandedSection == _toolsSectionKey,
                  onExpansionChanged: (expand) =>
                      _handleExpansionChange(_toolsSectionKey, expand),
                ),

                const SizedBox(height: 8),
                _buildSectionDivider(context),

                // Website Module
                _buildSidebarItem(
                  context,
                  icon: Icons.language_outlined,
                  activeIcon: Icons.language,
                  title: 'Sitio Web',
                  route: '/website',
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
                                  theme.colorScheme.onSurface.withOpacity(0.7),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Cerrar Sesión',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.colorScheme.onSurface
                                      .withOpacity(0.7),
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
                Container(
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 8, top: 8, bottom: 8),
                  child: IconButton(
                    icon: const Icon(Icons.chevron_left, size: 18),
                    iconSize: 18,
                    padding: const EdgeInsets.all(8),
                    constraints: const BoxConstraints(
                      minWidth: 32,
                      minHeight: 32,
                    ),
                    tooltip: 'Ocultar menú',
                    onPressed: () {
                      final navigationService =
                          context.read<NavigationService>();
                      navigationService.hideDrawer();
                    },
                    style: IconButton.styleFrom(
                      backgroundColor: theme.colorScheme.surface,
                      foregroundColor:
                          theme.colorScheme.onSurface.withOpacity(0.6),
                    ),
                  ),
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
      color: Theme.of(context).dividerColor.withOpacity(0.5),
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
                    // Dashboard, Website, and Settings navigate directly within current workspace
                    // All other modules can open in new workspace tabs if needed
                    if (route == '/dashboard' ||
                        route == '/website' ||
                        route == '/settings') {
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
                  ? theme.primaryColor.withOpacity(0.1)
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
                          : theme.colorScheme.onSurface.withOpacity(0.7))
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
                color: theme.colorScheme.onSurface.withOpacity(0.7),
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

class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    // Safely get current location
    String currentLocation = '';
    try {
      currentLocation = GoRouterState.of(context).uri.path;
    } catch (e) {
      // Not in GoRouter context
      currentLocation = '';
    }

    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          DrawerHeader(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Theme.of(context).primaryColor,
                  Theme.of(context).primaryColor.withOpacity(0.8),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Consumer<AppearanceService>(
              builder: (context, appearanceService, _) {
                return InkWell(
                  onTap: () {
                    // Navigate to dashboard when header is clicked
                    Navigator.pop(context); // Close drawer first
                    _openInWorkspace(context, '/dashboard', 'Dashboard');
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
                                  color: theme.colorScheme.onPrimary,
                                ),
                              );
                            },
                            errorWidget: (context, url, error) =>
                                _buildDefaultDrawerHeader(
                                    context, appearanceService),
                          ),
                        )
                      : _buildDefaultDrawerHeader(context, appearanceService),
                );
              },
            ),
          ),

          // Dashboard
          _buildDrawerItem(
            context,
            icon: Icons.dashboard,
            title: 'Dashboard',
            route: '/dashboard',
            currentLocation: currentLocation,
          ),

          const Divider(),

          // Core Modules
          _buildSectionHeader(context, 'MÓDULOS PRINCIPALES'),

          _buildDrawerExpandableItem(
            context,
            icon: Icons.account_balance,
            title: 'Contabilidad',
            subItems: _accountingMenuItems,
            currentLocation: currentLocation,
          ),

          _buildDrawerExpandableItem(
            context,
            icon: Icons.people,
            title: 'Clientes',
            subItems: _customersMenuItems,
            currentLocation: currentLocation,
          ),

          _buildDrawerExpandableItem(
            context,
            icon: Icons.pedal_bike,
            title: 'Taller',
            subItems: _workshopMenuItems,
            currentLocation: currentLocation,
          ),

          _buildDrawerExpandableItem(
            context,
            icon: Icons.lightbulb,
            title: 'Smart Features',
            subItems: _smartFeaturesMenuItems,
            currentLocation: currentLocation,
          ),

          _buildDrawerExpandableItem(
            context,
            icon: Icons.inventory,
            title: 'Inventario',
            subItems: _inventoryMenuItems,
            currentLocation: currentLocation,
          ),

          _buildDrawerExpandableItem(
            context,
            icon: Icons.point_of_sale,
            title: 'Ventas',
            subItems: _salesMenuItems,
            currentLocation: currentLocation,
          ),

          _buildDrawerExpandableItem(
            context,
            icon: Icons.shopping_cart,
            title: 'Compras',
            subItems: _purchasesMenuItems,
            currentLocation: currentLocation,
          ),

          _buildDrawerExpandableItem(
            context,
            icon: Icons.store,
            title: 'POS',
            subItems: _posMenuItems,
            currentLocation: currentLocation,
          ),

          _buildDrawerExpandableItem(
            context,
            icon: Icons.badge,
            title: 'RR.HH.',
            subItems: _hrMenuItems,
            currentLocation: currentLocation,
          ),

          const Divider(),

          // Tools (WebView Modules)
          _buildSectionHeader(context, 'HERRAMIENTAS'),

          _buildDrawerExpandableItem(
            context,
            icon: Icons.build_circle,
            title: 'Herramientas Web',
            subItems: _toolsMenuItems,
            currentLocation: currentLocation,
          ),

          const Divider(),

          // Secondary Modules
          _buildSectionHeader(context, 'OTROS MÓDULOS'),

          _buildDrawerItem(
            context,
            icon: Icons.build,
            title: 'Mantención',
            route: '/maintenance',
            currentLocation: currentLocation,
            enabled: false,
          ),

          _buildDrawerItem(
            context,
            icon: Icons.analytics,
            title: 'Análisis',
            route: '/analytics',
            currentLocation: currentLocation,
            enabled: false,
          ),

          const Divider(),

          // Settings
          _buildDrawerItem(
            context,
            icon: Icons.settings,
            title: 'Configuración',
            route: '/settings',
            currentLocation: currentLocation,
            enabled: false,
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
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

  Widget _buildDrawerExpandableItem(
    BuildContext context, {
    required IconData icon,
    required String title,
    required List<MenuSubItem> subItems,
    required String currentLocation,
  }) {
    final theme = Theme.of(context);
    final isExpanded = subItems.any(
      (item) => currentLocation.startsWith(item.route),
    );

    return Theme(
      data: theme.copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        leading: Icon(
          icon,
          color: theme.colorScheme.primary,
        ),
        title: Text(
          title,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        tilePadding: const EdgeInsets.symmetric(horizontal: 16),
        collapsedIconColor: theme.colorScheme.onSurface.withOpacity(0.6),
        iconColor: theme.colorScheme.primary,
        initiallyExpanded: isExpanded,
        children: subItems
            .map(
              (item) => _buildDrawerSubItem(
                context,
                item: item,
                currentLocation: currentLocation,
              ),
            )
            .toList(),
      ),
    );
  }

  Widget _buildDrawerSubItem(
    BuildContext context, {
    required MenuSubItem item,
    required String currentLocation,
  }) {
    final theme = Theme.of(context);
    final isSelected = currentLocation.startsWith(item.route);

    return ListTile(
      contentPadding: const EdgeInsets.only(left: 56, right: 16),
      leading: Icon(
        item.icon,
        size: 18,
        color: isSelected
            ? theme.colorScheme.primary
            : theme.colorScheme.onSurface.withOpacity(0.6),
      ),
      title: Text(
        item.title,
        style: theme.textTheme.bodySmall?.copyWith(
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
          color: isSelected
              ? theme.colorScheme.primary
              : theme.colorScheme.onSurface,
        ),
      ),
      selected: isSelected,
      selectedTileColor: theme.colorScheme.primary.withOpacity(0.08),
      onTap: () {
        if (!isSelected) {
          _openInWorkspace(context, item.route, item.title);
        }
        Navigator.pop(context);
      },
    );
  }

  Widget _buildDrawerItem(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String route,
    required String currentLocation,
    bool enabled = true,
  }) {
    final isSelected = currentLocation.startsWith(route);

    return ListTile(
      leading: Icon(
        icon,
        color: enabled
            ? (isSelected ? Theme.of(context).colorScheme.primary : null)
            : Theme.of(context).disabledColor,
      ),
      title: Text(
        title,
        style: TextStyle(
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          color: enabled
              ? (isSelected ? Theme.of(context).colorScheme.primary : null)
              : Theme.of(context).disabledColor,
        ),
      ),
      selected: isSelected,
      selectedTileColor: Theme.of(context).colorScheme.primary.withOpacity(0.1),
      onTap: enabled
          ? () {
              if (!isSelected) {
                // Dashboard always navigates directly (not in workspace tab)
                if (route == '/dashboard') {
                  context.go(route);
                } else {
                  _openInWorkspace(context, route, title);
                }
              }
              Navigator.pop(context);
            }
          : null,
    );
  }

  Widget _buildDefaultDrawerHeader(
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
            color: theme.colorScheme.onPrimary,
            size: 48,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Vinabike ERP',
          style: TextStyle(
            color: theme.colorScheme.onPrimary,
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          'Sistema Integral de Gestión',
          style: TextStyle(
            color: theme.colorScheme.onPrimary.withOpacity(0.7),
            fontSize: 14,
          ),
        ),
      ],
    );
  }
}
