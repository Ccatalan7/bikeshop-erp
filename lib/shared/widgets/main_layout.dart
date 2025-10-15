import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../services/auth_service.dart';
import '../../modules/settings/services/appearance_service.dart';
import 'expandable_menu_item.dart';

const List<MenuSubItem> _accountingMenuItems = [
  MenuSubItem(
    icon: Icons.account_tree_outlined,
    title: 'Plan de cuentas',
    route: '/accounting/accounts',
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

const List<MenuSubItem> _crmMenuItems = [
  MenuSubItem(
    icon: Icons.people_outline,
    title: 'Clientes',
    route: '/crm/customers',
  ),
  MenuSubItem(
    icon: Icons.person_add_alt,
    title: 'Nuevo cliente',
    route: '/crm/customers/new',
  ),
];

const String _crmSectionKey = 'crm';

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

class MainLayout extends StatelessWidget {
  final Widget? child;
  final Widget? body;
  final String? title;
  
  const MainLayout({
    super.key, 
    this.child,
    this.body,
    this.title,
  });

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final showSidebar = screenWidth > 768; // Show sidebar on larger screens
    
    if (showSidebar) {
      // Desktop layout with persistent sidebar
      return Scaffold(
        body: Row(
          children: [
            // Persistent Sidebar
            Container(
              width: 280,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                border: Border(
                  right: BorderSide(
                    color: Theme.of(context).dividerColor,
                    width: 1,
                  ),
                ),
              ),
              child: const AppSidebar(),
            ),
            // Main Content Area
            Expanded(
              child: Column(
                children: [
                  // Top App Bar
                  Container(
                    height: 64,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      border: Border(
                        bottom: BorderSide(
                          color: Theme.of(context).dividerColor,
                          width: 1,
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Text(
                            title ?? 'Vinabike ERP',
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const Spacer(),
                        // Action buttons
                        IconButton(
                          icon: const Icon(Icons.notifications_outlined),
                          onPressed: () {
                            // TODO: Implement notifications
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.settings_outlined),
                          onPressed: () {
                            context.push('/settings');
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.logout_outlined),
                          onPressed: () => _handleLogout(context),
                        ),
                        const SizedBox(width: 8),
                      ],
                    ),
                  ),
                  // Page Content
                  Expanded(
                    child: Container(
                      color: Theme.of(context).colorScheme.background,
                      child: body ?? child,
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
    final currentLocation = GoRouterState.of(context).uri.path;
    if (currentLocation != _lastLocation) {
      _lastLocation = currentLocation;
      final matchingSection = _resolveSectionForPath(currentLocation);
      if (matchingSection != _expandedSection) {
        setState(() {
          _expandedSection = matchingSection;
        });
      }
    }
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
    if (_matchesLocation(location, _crmMenuItems)) {
      return _crmSectionKey;
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
    final currentLocation = GoRouterState.of(context).uri.path;
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
                    // Navigate to dashboard when header is clicked
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
                              placeholder: (context, url) => const Center(
                                child: SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                ),
                              ),
                              errorWidget: (context, url, error) => _buildDefaultHeader(context, theme, appearanceService),
                            ),
                          ),
                        )
                      else
                        // Show default header with icon and text
                        ..._buildDefaultHeaderWidgets(context, theme, appearanceService),
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
                  onExpansionChanged: (expand) => _handleExpansionChange(_accountingSectionKey, expand),
                ),

                ExpandableMenuItem(
                  icon: Icons.people_outline,
                  activeIcon: Icons.people,
                  title: 'Clientes',
                  currentLocation: currentLocation,
                  subItems: _crmMenuItems,
                  isExpanded: _expandedSection == _crmSectionKey,
                  onExpansionChanged: (expand) => _handleExpansionChange(_crmSectionKey, expand),
                ),

                ExpandableMenuItem(
                  icon: Icons.inventory_2_outlined,
                  activeIcon: Icons.inventory_2,
                  title: 'Inventario',
                  currentLocation: currentLocation,
                  subItems: _inventoryMenuItems,
                  isExpanded: _expandedSection == _inventorySectionKey,
                  onExpansionChanged: (expand) => _handleExpansionChange(_inventorySectionKey, expand),
                ),

                ExpandableMenuItem(
                  icon: Icons.receipt_long_outlined,
                  activeIcon: Icons.receipt_long,
                  title: 'Ventas',
                  currentLocation: currentLocation,
                  subItems: _salesMenuItems,
                  isExpanded: _expandedSection == _salesSectionKey,
                  onExpansionChanged: (expand) => _handleExpansionChange(_salesSectionKey, expand),
                ),

                ExpandableMenuItem(
                  icon: Icons.shopping_cart_outlined,
                  activeIcon: Icons.shopping_cart,
                  title: 'Compras',
                  currentLocation: currentLocation,
                  subItems: _purchasesMenuItems,
                  isExpanded: _expandedSection == _purchasesSectionKey,
                  onExpansionChanged: (expand) => _handleExpansionChange(_purchasesSectionKey, expand),
                ),

                ExpandableMenuItem(
                  icon: Icons.point_of_sale_outlined,
                  activeIcon: Icons.point_of_sale,
                  title: 'POS',
                  currentLocation: currentLocation,
                  subItems: _posMenuItems,
                  isExpanded: _expandedSection == _posSectionKey,
                  onExpansionChanged: (expand) => _handleExpansionChange(_posSectionKey, expand),
                ),
                
                const SizedBox(height: 8),
                _buildSectionDivider(context),
                
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
                  icon: Icons.badge_outlined,
                  activeIcon: Icons.badge,
                  title: 'RR.HH.',
                  route: '/hr',
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
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(
                  color: theme.dividerColor,
                  width: 1,
                ),
              ),
            ),
            child: _buildSidebarItem(
              context,
              icon: Icons.settings_outlined,
              activeIcon: Icons.settings,
              title: 'Configuración',
              route: '/settings',
              currentLocation: currentLocation,
              enabled: true,
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
                    context.go(route);
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
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
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
          color: Colors.white,
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
    final currentLocation = GoRouterState.of(context).uri.path;
    
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
                    context.go('/dashboard');
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: appearanceService.hasCustomLogo
                      ? Padding(
                          padding: const EdgeInsets.all(8),
                          child: CachedNetworkImage(
                            imageUrl: appearanceService.companyLogoUrl!,
                            fit: BoxFit.contain,
                            placeholder: (context, url) => const Center(
                              child: CircularProgressIndicator(
                                color: Colors.white,
                              ),
                            ),
                            errorWidget: (context, url, error) => _buildDefaultDrawerHeader(context, appearanceService),
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
            subItems: _crmMenuItems,
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
            icon: Icons.badge,
            title: 'RR.HH.',
            route: '/hr',
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
          context.go(item.route);
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
                context.go(route);
              }
              Navigator.pop(context);
            }
          : null,
    );
  }

  Widget _buildDefaultDrawerHeader(BuildContext context, AppearanceService appearanceService) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(
            appearanceService.homeIcon,
            color: Colors.white,
            size: 48,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Vinabike ERP',
          style: TextStyle(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
        const Text(
          'Sistema Integral de Gestión',
          style: TextStyle(
            color: Colors.white70,
            fontSize: 14,
          ),
        ),
      ],
    );
  }
}