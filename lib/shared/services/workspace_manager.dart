import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../utils/web_url.dart';

/// Maps route paths to human-readable titles for workspace tabs
String getRouteTitle(String path) {
  // Remove query parameters and clean the path
  final cleanPath = path.split('?').first;

  // Route to title mappings
  final Map<String, String> routeTitles = {
    // Dashboard
    '/dashboard': 'Dashboard',

    // Accounting
    '/accounting/accounts': 'Plan de Cuentas',
    '/accounting/accounts/new': 'Nueva Cuenta',
    '/accounting/journal-entries': 'Asientos Contables',
    '/accounting/journal-entries/new': 'Nuevo Asiento',
    '/accounting/reports': 'Reportes Financieros',
    '/accounting/reports/income-statement': 'Estado de Resultados',
    '/accounting/reports/balance-sheet': 'Balance General',
    '/accounting/expenses': 'Gastos',
    '/accounting/expenses/new': 'Nuevo Gasto',

    // Tax Reports
    '/tax-reports/f29': 'Formulario F29',

    // CRM / Clientes
    '/clientes': 'Clientes',
    '/clientes/nuevo': 'Nuevo Cliente',
    '/clientes/bicicletas': 'Directorio de Bicicletas',

    // Bikeshop / Taller
    '/taller': 'Taller',
    '/taller/pegas': 'Pegas',
    '/taller/calendario': 'Calendario Taller',
    '/taller/nueva-pega': 'Nueva Pega',
    '/taller/estados': 'Estados de Pegas',
    '/taller/marcas-bicicletas': 'Marcas de Bicicletas',
    '/taller/enciclopedia': 'Enciclopedia de Bicicletas',
    '/taller/logbook': 'Logbook Cliente',

    // Wheel Building
    '/wheel-building/hubs': 'Mazas',
    '/wheel-building/rims': 'Aros',
    '/wheel-building/spokes': 'Rayos',
    '/wheel-building/wizard': 'Constructor de Ruedas',
    '/wheel-building/spoke-calculator': 'Calculadora de Rayos',

    // Inventory
    '/inventory/products': 'Productos',
    '/inventory/products/new': 'Nuevo Producto',
    '/inventory/products/import': 'Importar Productos',
    '/inventory/categories': 'Categorías',
    '/inventory/categories/new': 'Nueva Categoría',
    '/inventory/brands': 'Marcas',
    '/inventory/brands/new': 'Nueva Marca',
    '/inventory/stock-movements': 'Movimientos de Stock',
    '/inventory/stock-adjustments': 'Ajustes de Stock',

    // Sales
    '/sales/invoices': 'Facturas de Venta',
    '/sales/invoices/new': 'Nueva Factura',
    '/sales/payments': 'Pagos Recibidos',
    '/sales/payments/new': 'Nuevo Pago',

    // Purchases
    '/purchases/invoices': 'Facturas de Compra',
    '/purchases/invoices/new': 'Nueva Compra',
    '/purchases/suppliers': 'Proveedores',
    '/purchases/suppliers/new': 'Nuevo Proveedor',
    '/purchases/payments': 'Pagos a Proveedores',
    '/purchases/smart-list': 'Lista Inteligente',

    // POS
    '/pos': 'Punto de Venta',
    '/pos/cart': 'Carrito POS',
    '/pos/payment': 'Pago POS',
    '/pos/receipt': 'Recibo POS',

    // HR
    '/hr/employees': 'Empleados',
    '/hr/employees/new': 'Nuevo Empleado',
    '/hr/attendance': 'Asistencia',
    '/hr/kiosk': 'Modo Kiosko',
    '/hr/medical-leaves': 'Licencias Médicas',

    // Website
    '/website': 'Sitio Web',
    '/website/pages': 'Gestión de Páginas',
    '/website/navigation': 'Navegación',

    // Mail
    '/mail': 'Correo',

    // Settings
    '/settings': 'Configuración',
    '/settings/appearance': 'Apariencia',
    '/settings/users': 'Usuarios',
    '/settings/payment-methods': 'Métodos de Pago',
    '/settings/bluetooth-scanner': 'Escáner Bluetooth',
    '/settings/keyboard-scanner': 'Escáner USB',
    '/settings/remote-scanner': 'Escáner Remoto',
    '/settings/backup': 'Respaldos',
    '/settings/factory-reset': 'Reseteo de Fábrica',

    // WebView modules
    '/webview/feria-del-disco': 'Feria del Disco',
    '/webview/google-maps': 'Google Maps',
    '/webview/custom': 'WebView',
  };

  // First check for exact match
  if (routeTitles.containsKey(cleanPath)) {
    return routeTitles[cleanPath]!;
  }

  // Check for pattern matches (routes with parameters like :id)
  // Handle /clientes/:id/editar → "Editar Cliente"
  if (cleanPath.contains('/editar') || cleanPath.contains('/edit')) {
    if (cleanPath.startsWith('/clientes/')) return 'Editar Cliente';
    if (cleanPath.startsWith('/inventory/products/')) return 'Editar Producto';
    if (cleanPath.startsWith('/inventory/categories/'))
      return 'Editar Categoría';
    if (cleanPath.startsWith('/inventory/brands/')) return 'Editar Marca';
    if (cleanPath.startsWith('/sales/invoices/')) return 'Editar Factura';
    if (cleanPath.startsWith('/purchases/invoices/')) return 'Editar Compra';
    if (cleanPath.startsWith('/purchases/suppliers/'))
      return 'Editar Proveedor';
    if (cleanPath.startsWith('/accounting/accounts/')) return 'Editar Cuenta';
    if (cleanPath.startsWith('/accounting/journal-entries/'))
      return 'Editar Asiento';
    if (cleanPath.startsWith('/accounting/expenses/')) return 'Editar Gasto';
    if (cleanPath.startsWith('/hr/employees/')) return 'Editar Empleado';
    if (cleanPath.startsWith('/taller/pega/')) return 'Editar Pega';
  }

  // Handle detail views /clientes/:id → "Cliente"
  if (RegExp(r'^/clientes/[^/]+$').hasMatch(cleanPath))
    return 'Detalle Cliente';
  if (RegExp(r'^/taller/pega/[^/]+$').hasMatch(cleanPath))
    return 'Detalle Pega';
  if (RegExp(r'^/sales/invoices/[^/]+$').hasMatch(cleanPath))
    return 'Detalle Factura';
  if (RegExp(r'^/purchases/invoices/[^/]+$').hasMatch(cleanPath))
    return 'Detalle Compra';
  if (RegExp(r'^/inventory/products/[^/]+$').hasMatch(cleanPath))
    return 'Detalle Producto';
  if (RegExp(r'^/accounting/expenses/[^/]+$').hasMatch(cleanPath))
    return 'Detalle Gasto';

  // Fallback: Extract last segment and capitalize
  final segments = cleanPath.split('/').where((s) => s.isNotEmpty).toList();
  if (segments.isNotEmpty) {
    final last = segments.last;
    // Skip UUIDs
    if (RegExp(r'^[0-9a-f-]{36}$').hasMatch(last) && segments.length > 1) {
      return segments[segments.length - 2].replaceAll('-', ' ').toUpperCase();
    }
    return last
        .replaceAll('-', ' ')
        .split(' ')
        .map((w) => w.isNotEmpty ? '${w[0].toUpperCase()}${w.substring(1)}' : w)
        .join(' ');
  }

  return 'Sin título';
}

/// Represents a single workspace tab
class Workspace {
  final String id;
  String title; // Made mutable for dynamic updates
  final String initialRoute;
  String currentRoute; // Track current route for title updates
  final GlobalKey<NavigatorState> navigatorKey;

  Workspace({
    required this.id,
    required this.title,
    required this.initialRoute,
  })  : currentRoute = initialRoute,
        navigatorKey = GlobalKey<NavigatorState>();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Workspace && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}

/// Manages multiple independent workspace tabs
/// Each workspace has its own GoRouter instance and navigation state
class WorkspaceManager extends ChangeNotifier {
  static const int maxWorkspaces = 10;

  final List<Workspace> _workspaces = [];
  int _activeIndex = 0;
  bool _isInitialized = false;

  List<Workspace> get workspaces => List.unmodifiable(_workspaces);
  int get activeIndex => _activeIndex;
  Workspace? get activeWorkspace =>
      _workspaces.isEmpty ? null : _workspaces[_activeIndex];
  bool get isInitialized => _isInitialized;

  WorkspaceManager() {
    debugPrint(
        '🏗️ [WorkspaceManager] Constructor called, checking initial URL');

    // Check if we should open a specific route based on browser URL
    String initialRoute = '/dashboard';
    String initialTitle = 'Dashboard';

    if (kIsWeb) {
      final browserUrl = getInitialBrowserUrl();
      if (browserUrl != null) {
        final uri = Uri.parse(browserUrl);
        final path = uri.path;

        // Check for ERP routes (not public store routes)
        if (path.startsWith('/mail') ||
            path.startsWith('/dashboard') ||
            path.startsWith('/accounting') ||
            path.startsWith('/inventory') ||
            path.startsWith('/sales') ||
            path.startsWith('/purchases') ||
            path.startsWith('/taller') ||
            path.startsWith('/clientes') ||
            path.startsWith('/hr') ||
            path.startsWith('/pos') ||
            path.startsWith('/settings') ||
            path.startsWith('/website') ||
            path.startsWith('/chat')) {
          // Use the path (without query params for the initial route title,
          // but WITH query params for actual navigation)
          initialRoute = uri.toString().replaceFirst(uri.origin, '');
          initialTitle = getRouteTitle(path);
          debugPrint(
              '🔗 [WorkspaceManager] Using URL from browser: $initialRoute');
        }
      }
    }

    addWorkspace(title: initialTitle, initialRoute: initialRoute);
    _isInitialized = true;
    debugPrint(
        '✅ [WorkspaceManager] Initialized with ${_workspaces.length} workspace(s)');
    // Force a notification after initialization to ensure UI rebuilds
    Future.microtask(() {
      debugPrint(
          '🔔 [WorkspaceManager] Calling notifyListeners() after microtask');
      notifyListeners();
    });
  }

  /// Add a new workspace tab
  String addWorkspace({
    required String title,
    required String initialRoute,
  }) {
    debugPrint(
        '➕ [WorkspaceManager] addWorkspace: title=$title, route=$initialRoute');

    if (_workspaces.length >= maxWorkspaces) {
      throw Exception('Maximum number of workspaces ($maxWorkspaces) reached');
    }

    final id = DateTime.now().millisecondsSinceEpoch.toString();
    final workspace = Workspace(
      id: id,
      title: title,
      initialRoute: initialRoute,
    );

    _workspaces.add(workspace);
    _activeIndex = _workspaces.length - 1;
    debugPrint(
        '✅ [WorkspaceManager] Workspace added. Total: ${_workspaces.length}, Active: $_activeIndex');
    notifyListeners();

    return id;
  }

  /// Switch to a specific workspace by index
  void switchToWorkspace(int index) {
    if (index >= 0 && index < _workspaces.length) {
      _activeIndex = index;
      notifyListeners();
    }
  }

  /// Switch to a specific workspace by ID
  void switchToWorkspaceById(String id) {
    final index = _workspaces.indexWhere((w) => w.id == id);
    if (index != -1) {
      switchToWorkspace(index);
    }
  }

  /// Close a workspace tab
  void closeWorkspace(int index) {
    if (_workspaces.length <= 1) {
      // Don't allow closing the last workspace
      return;
    }

    if (index >= 0 && index < _workspaces.length) {
      _workspaces.removeAt(index);

      // Adjust active index if needed
      if (_activeIndex >= _workspaces.length) {
        _activeIndex = _workspaces.length - 1;
      } else if (_activeIndex > index) {
        _activeIndex--;
      }

      notifyListeners();
    }
  }

  /// Close a workspace by ID
  void closeWorkspaceById(String id) {
    final index = _workspaces.indexWhere((w) => w.id == id);
    if (index != -1) {
      closeWorkspace(index);
    }
  }

  /// Update workspace title
  void updateWorkspaceTitle(int index, String newTitle) {
    if (index >= 0 && index < _workspaces.length) {
      _workspaces[index].title = newTitle;
      notifyListeners();
    }
  }

  /// Update the active workspace's title based on current route
  /// Called when navigation changes within a workspace
  void updateActiveWorkspaceRoute(String newRoute) {
    if (_workspaces.isEmpty) return;

    final workspace = _workspaces[_activeIndex];
    if (workspace.currentRoute == newRoute) return;

    workspace.currentRoute = newRoute;
    workspace.title = getRouteTitle(newRoute);
    debugPrint(
        '📍 [WorkspaceManager] Updated workspace "${workspace.id}" to route: $newRoute → title: "${workspace.title}"');
    notifyListeners();
  }

  /// Update a specific workspace's route and title
  void updateWorkspaceRoute(int index, String newRoute) {
    if (index >= 0 && index < _workspaces.length) {
      final workspace = _workspaces[index];
      if (workspace.currentRoute == newRoute) return;

      workspace.currentRoute = newRoute;
      workspace.title = getRouteTitle(newRoute);
      notifyListeners();
    }
  }

  /// Check if a workspace with the given route already exists
  /// If it does, switch to it instead of creating a new one
  bool switchToExistingWorkspaceWithRoute(String route) {
    debugPrint(
        '🔍 [WorkspaceManager] Looking for existing workspace with route: $route');
    final index = _workspaces.indexWhere((w) => w.initialRoute == route);
    if (index != -1) {
      debugPrint(
          '✅ [WorkspaceManager] Found existing workspace at index $index, switching...');
      switchToWorkspace(index);
      return true;
    }
    debugPrint('❌ [WorkspaceManager] No existing workspace found for $route');
    return false;
  }

  /// Clear all workspaces and reset to initial state
  void reset() {
    _workspaces.clear();
    _activeIndex = 0;
    addWorkspace(title: 'Dashboard', initialRoute: '/dashboard');
  }
}
