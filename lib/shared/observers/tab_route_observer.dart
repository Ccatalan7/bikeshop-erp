import 'package:flutter/material.dart';
import '../services/tab_navigation_service.dart';

/// Route observer that automatically registers tabs when navigating
/// 
/// Maps route paths to human-readable titles
class TabRouteObserver extends NavigatorObserver {
  final TabNavigationService tabService;

  TabRouteObserver(this.tabService);

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    _registerTab(route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    // Optionally close tab when popping (disabled for now - user can close manually)
    // if (route.settings.name != null) {
    //   tabService.closeTabByRoute(route.settings.name!);
    // }
  }

  void _registerTab(Route<dynamic> route) {
    final routeName = route.settings.name;
    if (routeName == null || routeName.isEmpty) return;

    // Skip routes that shouldn't have tabs
    if (_shouldSkipRoute(routeName)) return;

    // Get human-readable title
    final title = _getRouteTitle(routeName);
    final icon = _getRouteIcon(routeName);

    // Register tab
    tabService.openTab(routeName, title, icon: icon);
  }

  /// Routes that shouldn't create tabs (auth, dialogs, etc.)
  bool _shouldSkipRoute(String route) {
    final skipPrefixes = [
      '/login',
      '/reset-password',
      '/accept-invitation',
      '/tienda', // Public store routes
    ];

    return skipPrefixes.any((prefix) => route.startsWith(prefix));
  }

  /// Map route paths to user-friendly titles
  String _getRouteTitle(String route) {
    // Route to title mapping
    const routeTitles = {
      // Dashboard
      '/dashboard': 'Inicio',

      // Inventory
      '/inventory/products': 'Productos',
      '/inventory/products/new': 'Nuevo Producto',
      '/inventory/products/import': 'Importar Productos',
      '/inventory/categories': 'Categorías',
      '/inventory/categories/new': 'Nueva Categoría',
      '/inventory/brands': 'Marcas',
      '/inventory/brands/new': 'Nueva Marca',
      '/inventory/stock-movements': 'Movimientos de Stock',

      // Sales
      '/ventas': 'Ventas',
      '/ventas/nueva': 'Nueva Factura',
      '/ventas/payment': 'Pago de Factura',

      // Purchases
      '/compras': 'Compras',
      '/compras/nueva': 'Nueva Compra',
      '/compras/proveedores': 'Proveedores',
      '/compras/proveedores/nuevo': 'Nuevo Proveedor',
      '/compras/pagos': 'Pagos de Compras',
      '/compras/smart-list': 'Lista Inteligente',

      // Customers
      '/clientes': 'Clientes',
      '/clientes/nuevo': 'Nuevo Cliente',
      '/clientes/bicicletas': 'Bicicletas',

      // Workshop
      '/taller/pegas': 'Pegas',
      '/taller/pegas/nueva': 'Nueva Pega',
      '/taller/bicicletas': 'Bicicletas Taller',
      '/taller/calendario': 'Calendario',

      // Accounting
      '/accounting/accounts': 'Plan de Cuentas',
      '/accounting/accounts/new': 'Nueva Cuenta',
      '/accounting/expenses': 'Gastos',
      '/accounting/expenses/new': 'Nuevo Gasto',
      '/accounting/journal-entries': 'Asientos',
      '/accounting/journal-entries/new': 'Nuevo Asiento',
      '/accounting/reports': 'Reportes',
      '/accounting/reports/income-statement': 'Estado de Resultados',
      '/accounting/reports/balance-sheet': 'Balance General',

      // POS
      '/pos': 'Punto de Venta',
      '/pos/cart': 'Carrito POS',
      '/pos/payment': 'Pago POS',

      // HR
      '/hr/employees': 'Empleados',
      '/hr/attendances': 'Asistencias',
      '/hr/kiosk': 'Kiosko',

      // Website
      '/website': 'Sitio Web',

      // Settings
      '/settings': 'Configuración',
      '/settings/appearance': 'Apariencia',
      '/settings/users': 'Usuarios',
      '/settings/factory-reset': 'Restablecer',
      '/settings/bluetooth-scanner': 'Escáner Bluetooth',
      '/settings/keyboard-scanner': 'Escáner USB',
      '/settings/remote-scanner': 'Escáner Remoto',
    };

    // Try exact match first
    if (routeTitles.containsKey(route)) {
      return routeTitles[route]!;
    }

    // Try to match with dynamic segments (e.g., /ventas/123 -> "Venta #123")
    if (route.startsWith('/ventas/') && route != '/ventas/nueva' && route != '/ventas/payment') {
      final id = route.split('/').last;
      return 'Venta #$id';
    }

    if (route.startsWith('/compras/') && route != '/compras/nueva' && route != '/compras/pagos') {
      final id = route.split('/').last;
      return 'Compra #$id';
    }

    if (route.startsWith('/clientes/') && route != '/clientes/nuevo') {
      return 'Cliente';
    }

    if (route.startsWith('/taller/pegas/') && route != '/taller/pegas/nueva') {
      return 'Pega';
    }

    if (route.startsWith('/inventory/products/') && route != '/inventory/products/new') {
      return 'Producto';
    }

    // Fallback: use route path
    return route.split('/').last.replaceAll('-', ' ').toUpperCase();
  }

  /// Get icon for route (optional)
  IconData? _getRouteIcon(String route) {
    const routeIcons = {
      '/dashboard': Icons.dashboard_outlined,
      '/inventory/products': Icons.inventory_outlined,
      '/ventas': Icons.receipt_long_outlined,
      '/compras': Icons.shopping_cart_outlined,
      '/clientes': Icons.people_outline,
      '/taller/pegas': Icons.build_outlined,
      '/accounting/accounts': Icons.account_tree_outlined,
      '/pos': Icons.point_of_sale,
      '/hr/employees': Icons.badge_outlined,
      '/website': Icons.web_outlined,
      '/settings': Icons.settings_outlined,
    };

    // Try exact match
    if (routeIcons.containsKey(route)) {
      return routeIcons[route];
    }

    // Try prefix match for dynamic routes
    for (final entry in routeIcons.entries) {
      if (route.startsWith(entry.key)) {
        return entry.value;
      }
    }

    return null;
  }
}
