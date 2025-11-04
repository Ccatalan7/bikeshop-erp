import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../services/tab_navigation_service.dart';

/// Helper function to register current page as a tab
/// 
/// Call this in your page's build method or initState:
/// ```dart
/// @override
/// Widget build(BuildContext context) {
///   registerCurrentTab(context, title: 'My Page', icon: Icons.my_icon);
///   return Scaffold(...);
/// }
/// ```
void registerCurrentTab(
  BuildContext context, {
  String? title,
  IconData? icon,
  bool enabled = true,
}) {
  if (!enabled) return;

  // Use post-frame callback to avoid modifying state during build
  WidgetsBinding.instance.addPostFrameCallback((_) {
    try {
      final routerState = GoRouterState.of(context);
      final route = routerState.uri.path;

      // Skip routes that shouldn't have tabs
      if (_shouldSkipRoute(route)) return;

      final tabService = context.read<TabNavigationService>();
      final tabTitle = title ?? _getRouteTitle(route);

      tabService.openTab(route, tabTitle, icon: icon);
    } catch (e) {
      debugPrint('⚠️ [Tab Registration] Failed: $e');
    }
  });
}

bool _shouldSkipRoute(String route) {
  final skipPrefixes = [
    '/login',
    '/reset-password',
    '/accept-invitation',
    '/tienda', // Public store routes
  ];

  return skipPrefixes.any((prefix) => route.startsWith(prefix));
}

String _getRouteTitle(String route) {
  // Route to title mapping
  const routeTitles = {
    '/dashboard': 'Inicio',
    '/inventory/products': 'Productos',
    '/inventory/products/new': 'Nuevo Producto',
    '/inventory/products/import': 'Importar Productos',
    '/inventory/categories': 'Categorías',
    '/inventory/brands': 'Marcas',
    '/inventory/stock-movements': 'Movimientos',
    '/ventas': 'Ventas',
    '/ventas/nueva': 'Nueva Factura',
    '/compras': 'Compras',
    '/compras/nueva': 'Nueva Compra',
    '/compras/proveedores': 'Proveedores',
    '/compras/pagos': 'Pagos Compras',
    '/compras/smart-list': 'Lista Inteligente',
    '/clientes': 'Clientes',
    '/clientes/nuevo': 'Nuevo Cliente',
    '/taller/pegas': 'Pegas',
    '/taller/pegas/nueva': 'Nueva Pega',
    '/taller/calendario': 'Calendario',
    '/accounting/accounts': 'Cuentas',
    '/accounting/journal-entries': 'Asientos',
    '/accounting/expenses': 'Gastos',
    '/accounting/reports': 'Reportes',
    '/accounting/reports/income-statement': 'Estado Resultados',
    '/accounting/reports/balance-sheet': 'Balance',
    '/pos': 'POS',
    '/hr/employees': 'Empleados',
    '/hr/attendances': 'Asistencias',
    '/website': 'Sitio Web',
    '/settings': 'Configuración',
  };

  // Try exact match
  if (routeTitles.containsKey(route)) {
    return routeTitles[route]!;
  }

  // Fallback: use last path segment
  final segments = route.split('/').where((s) => s.isNotEmpty).toList();
  if (segments.isEmpty) return 'Inicio';

  final lastSegment = segments.last;
  // Try to make it readable
  return lastSegment
      .replaceAll('-', ' ')
      .split(' ')
      .map((word) => word.isEmpty
          ? ''
          : word[0].toUpperCase() + word.substring(1))
      .join(' ');
}

/// DEPRECATED: Use registerCurrentTab() function instead
/// 
/// Old widget-based approach that caused issues with auto-registration
@Deprecated('Use registerCurrentTab() function in your build method instead')
class AutoTab extends StatefulWidget {
  final Widget child;
  final String? title;
  final IconData? icon;
  final bool enabled;

  const AutoTab({
    super.key,
    required this.child,
    this.title,
    this.icon,
    this.enabled = true,
  });

  @override
  State<AutoTab> createState() => _AutoTabState();
}

class _AutoTabState extends State<AutoTab> {
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    if (!widget.enabled) return;

    // Register tab after build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      try {
        final routerState = GoRouterState.of(context);
        final route = routerState.uri.path;

        // Skip routes that shouldn't have tabs
        if (_shouldSkipRoute(route)) return;

        final tabService = context.read<TabNavigationService>();
        final title = widget.title ?? _getRouteTitle(route);

        tabService.openTab(route, title, icon: widget.icon);
      } catch (e) {
        debugPrint('⚠️ [AutoTab] Failed to register tab: $e');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
