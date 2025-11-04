import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../services/tab_navigation_service.dart';

/// Horizontal tab bar for multi-tab navigation
/// 
/// Features:
/// - Horizontal scrollable tabs
/// - Active tab highlighting
/// - Close buttons (X) on each tab
/// - Click to switch tabs
/// - Hover effects
/// - Compact design (TradingView style)
class AppTabBar extends StatelessWidget {
  const AppTabBar({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<TabNavigationService>(
      builder: (context, tabService, _) {
        // Get current route to determine active tab
        String? currentRoute;
        try {
          final routerState = GoRouterState.of(context);
          currentRoute = routerState.uri.path;
        } catch (e) {
          // GoRouterState not available
        }

        return Container(
          height: 40,
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            border: Border(
              bottom: BorderSide(
                color: Theme.of(context).dividerColor,
                width: 1,
              ),
            ),
          ),
          child: Row(
            children: [
              // Scrollable tabs area
              if (tabService.hasTabs)
                Expanded(
                  child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: tabService.tabCount,
                  itemBuilder: (context, index) {
                    final tab = tabService.tabs[index];
                    // Tab is active if its route matches current route
                    final isActive = currentRoute != null && tab.route == currentRoute;
                    
                    return _TabItem(
                      tab: tab,
                      isActive: isActive,
                      onTap: () {
                        // Navigate to the tab's route
                        context.go(tab.route);
                      },
                      onClose: () => tabService.closeTab(index),
                    );
                  },
                ),
              )
              else
                const Spacer(),
              
              // "+ New Tab" button - opens menu with all modules
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: PopupMenuButton<Map<String, dynamic>>(
                  icon: const Icon(Icons.add_circle_outline, size: 18),
                  tooltip: 'Abrir pestaña',
                  padding: const EdgeInsets.all(8),
                  onSelected: (moduleData) {
                    tabService.openTabWithoutNavigation(
                      moduleData['route'] as String,
                      moduleData['title'] as String,
                      icon: moduleData['icon'] as IconData?,
                    );
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Pestaña "${moduleData['title']}" abierta'),
                        duration: const Duration(seconds: 1),
                      ),
                    );
                  },
                  itemBuilder: (context) => [
                    // Main modules
                    _buildMenuItem('Tablero', '/dashboard', Icons.dashboard),
                    _buildMenuItem('Productos', '/inventory/products', Icons.inventory),
                    _buildMenuItem('Ventas', '/sales/invoices', Icons.receipt_long),
                    _buildMenuItem('Compras', '/purchases', Icons.shopping_cart),
                    _buildMenuItem('Clientes', '/customers/list', Icons.people),
                    _buildMenuItem('Proveedores', '/suppliers/list', Icons.business),
                    _buildMenuItem('Pegas', '/taller/pegas', Icons.build),
                    _buildMenuItem('Empleados', '/hr/employees', Icons.badge),
                    _buildMenuItem('Plan de Cuentas', '/accounting/accounts', Icons.account_balance),
                    _buildMenuItem('Reportes', '/accounting/reports', Icons.analytics),
                    const PopupMenuDivider(),
                    _buildMenuItem('Configuración', '/settings', Icons.settings),
                  ],
                ),
              ),
              
              // Tab counter and close-all button
              if (tabService.tabCount > 1) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    '${tabService.tabCount}/${TabNavigationService.maxTabs}',
                    style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(context).hintColor,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_fullscreen, size: 16),
                  tooltip: 'Cerrar todas las pestañas',
                  padding: const EdgeInsets.all(8),
                  constraints: const BoxConstraints(),
                  onPressed: () => _showCloseAllDialog(context, tabService),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  PopupMenuItem<Map<String, dynamic>> _buildMenuItem(
    String title,
    String route,
    IconData icon,
  ) {
    return PopupMenuItem<Map<String, dynamic>>(
      value: {'title': title, 'route': route, 'icon': icon},
      child: Row(
        children: [
          Icon(icon, size: 18),
          const SizedBox(width: 12),
          Text(title),
        ],
      ),
    );
  }

  void _showCloseAllDialog(BuildContext context, TabNavigationService tabService) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cerrar todas las pestañas'),
        content: Text('¿Cerrar las ${tabService.tabCount} pestañas abiertas?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              tabService.closeAllTabs();
              Navigator.pop(context);
            },
            child: const Text('Cerrar todas'),
          ),
        ],
      ),
    );
  }
}

/// Individual tab item
class _TabItem extends StatefulWidget {
  final TabData tab;
  final bool isActive;
  final VoidCallback onTap;
  final VoidCallback onClose;

  const _TabItem({
    required this.tab,
    required this.isActive,
    required this.onTap,
    required this.onClose,
  });

  @override
  State<_TabItem> createState() => _TabItemState();
}

class _TabItemState extends State<_TabItem> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // Colors based on state
    final backgroundColor = widget.isActive
        ? (isDark ? Colors.grey[850] : Colors.white)
        : _isHovered
            ? (isDark ? Colors.grey[800] : Colors.grey[100])
            : Colors.transparent;

    final textColor = widget.isActive
        ? theme.colorScheme.primary
        : theme.textTheme.bodyMedium?.color;

    final borderColor = widget.isActive
        ? theme.colorScheme.primary
        : Colors.transparent;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          constraints: const BoxConstraints(
            minWidth: 120,
            maxWidth: 200,
          ),
          decoration: BoxDecoration(
            color: backgroundColor,
            border: Border(
              bottom: BorderSide(
                color: borderColor,
                width: 2,
              ),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Tab icon (if provided)
                if (widget.tab.icon != null) ...[
                  Icon(
                    widget.tab.icon,
                    size: 14,
                    color: textColor,
                  ),
                  const SizedBox(width: 6),
                ],

                // Tab title
                Expanded(
                  child: Text(
                    widget.tab.title,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: widget.isActive ? FontWeight.w600 : FontWeight.w400,
                      color: textColor,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),

                const SizedBox(width: 8),

                // Close button
                InkWell(
                  onTap: widget.onClose,
                  borderRadius: BorderRadius.circular(4),
                  child: Padding(
                    padding: const EdgeInsets.all(2),
                    child: Icon(
                      Icons.close,
                      size: 14,
                      color: _isHovered 
                          ? theme.colorScheme.error 
                          : theme.hintColor,
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
