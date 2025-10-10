import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
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
];

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
    title: 'Registrar pago',
    route: '/payments/new',
  ),
];

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
];

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
                            // TODO: Navigate to settings
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.logout_outlined),
                          onPressed: () {
                            // TODO: Implement logout
                          },
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
                // TODO: Navigate to settings
              },
            ),
            IconButton(
              icon: const Icon(Icons.logout),
              onPressed: () {
                // TODO: Implement logout
              },
            ),
          ],
        ),
        drawer: const AppDrawer(),
        body: body ?? child,
      );
    }
  }
}

class AppSidebar extends StatelessWidget {
  const AppSidebar({super.key});

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
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: theme.primaryColor,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Icon(
                    Icons.pedal_bike,
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
              ],
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
                ),

                ExpandableMenuItem(
                  icon: Icons.people_outline,
                  activeIcon: Icons.people,
                  title: 'Clientes',
                  currentLocation: currentLocation,
                  subItems: _crmMenuItems,
                ),

                ExpandableMenuItem(
                  icon: Icons.inventory_2_outlined,
                  activeIcon: Icons.inventory_2,
                  title: 'Inventario',
                  currentLocation: currentLocation,
                  subItems: _inventoryMenuItems,
                ),

                ExpandableMenuItem(
                  icon: Icons.receipt_long_outlined,
                  activeIcon: Icons.receipt_long,
                  title: 'Ventas',
                  currentLocation: currentLocation,
                  subItems: _salesMenuItems,
                ),

                ExpandableMenuItem(
                  icon: Icons.shopping_cart_outlined,
                  activeIcon: Icons.shopping_cart,
                  title: 'Compras',
                  currentLocation: currentLocation,
                  subItems: _purchasesMenuItems,
                ),

                ExpandableMenuItem(
                  icon: Icons.point_of_sale_outlined,
                  activeIcon: Icons.point_of_sale,
                  title: 'POS',
                  currentLocation: currentLocation,
                  subItems: _posMenuItems,
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
              enabled: false,
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
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.pedal_bike,
                  color: Colors.white,
                  size: 48,
                ),
                SizedBox(height: 8),
                Text(
                  'Vinabike ERP',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  'Sistema Integral de Gestión',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                  ),
                ),
              ],
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
}