import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../utils/web_url.dart';

import 'package:go_router/go_router.dart';

const double workspaceMinDrawerWidth = 200.0;
const double workspaceMaxDrawerWidth = 400.0;
const double workspaceDefaultDrawerWidth = 280.0;

String workspaceRoutePath(String route) {
  return Uri.tryParse(route)?.path ?? route.split('?').first;
}

String inferWorkspaceModuleRoot(String route) {
  final path = workspaceRoutePath(route);
  const moduleRoots = [
    '/accounting',
    '/tax-reports',
    '/clientes',
    '/taller',
    '/inventory',
    '/sales',
    '/purchases',
    '/pos',
    '/hr',
    '/website',
    '/tienda',
    '/mail',
    '/chat',
    '/tools',
    '/settings',
    '/debug',
    '/dashboard',
  ];

  for (final root in moduleRoots) {
    if (path == root || path.startsWith('$root/')) {
      return root;
    }
  }

  final segments = path.split('/').where((segment) => segment.isNotEmpty);
  return segments.isEmpty ? '/dashboard' : '/${segments.first}';
}

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
    '/taller/pegas': 'Trabajos',
    '/taller/calendario': 'Calendario Taller',
    '/taller/nueva-pega': 'Nuevo Trabajo',
    '/taller/estados': 'Estados de Trabajos',
    '/taller/sujetos': 'Catálogo de Elementos',
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
    '/hr/employees': 'Trabajadores',
    '/hr/employees/new': 'Nuevo Trabajador',
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
    '/settings/users': 'Usuarios y roles',
    '/settings/payment-methods': 'Métodos de Pago',
    '/settings/bluetooth-scanner': 'Escáner Bluetooth',
    '/settings/keyboard-scanner': 'Escáner USB',
    '/settings/remote-scanner': 'Escáner Remoto',
    '/settings/backup': 'Respaldos',
    '/settings/factory-reset': 'Reseteo de Fábrica',

    // Tools
    '/tools/web': 'Portal Web',

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
    if (cleanPath.startsWith('/inventory/categories/')) {
      return 'Editar Categoría';
    }
    if (cleanPath.startsWith('/inventory/brands/')) return 'Editar Marca';
    if (cleanPath.startsWith('/sales/invoices/')) return 'Editar Factura';
    if (cleanPath.startsWith('/purchases/invoices/')) return 'Editar Compra';
    if (cleanPath.startsWith('/purchases/suppliers/')) {
      return 'Editar Proveedor';
    }
    if (cleanPath.startsWith('/accounting/accounts/')) return 'Editar Cuenta';
    if (cleanPath.startsWith('/accounting/journal-entries/')) {
      return 'Editar Asiento';
    }
    if (cleanPath.startsWith('/accounting/expenses/')) return 'Editar Gasto';
    if (cleanPath.startsWith('/hr/employees/')) return 'Editar Trabajador';
    if (cleanPath.startsWith('/taller/pega/')) return 'Editar Trabajo';
  }

  // Handle detail views /clientes/:id → "Cliente"
  if (RegExp(r'^/clientes/[^/]+$').hasMatch(cleanPath)) {
    return 'Detalle Cliente';
  }
  if (RegExp(r'^/taller/pega/[^/]+$').hasMatch(cleanPath)) {
    return 'Detalle Trabajo';
  }
  if (RegExp(r'^/sales/invoices/[^/]+$').hasMatch(cleanPath)) {
    return 'Detalle Factura';
  }
  if (RegExp(r'^/purchases/invoices/[^/]+$').hasMatch(cleanPath)) {
    return 'Detalle Compra';
  }
  if (RegExp(r'^/inventory/products/[^/]+$').hasMatch(cleanPath)) {
    return 'Detalle Producto';
  }
  if (RegExp(r'^/accounting/expenses/[^/]+$').hasMatch(cleanPath)) {
    return 'Detalle Gasto';
  }

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
  GoRouter? router; // Track actual router instance for external navigation
  bool isDrawerVisible;
  double drawerWidth;
  bool isResizingDrawer;
  bool isPinned;
  String? pinnedRouteRoot;
  final List<String> routeHistory;
  int routeHistoryIndex;
  bool isApplyingHistoryNavigation;

  Workspace({
    required this.id,
    required this.title,
    required this.initialRoute,
    this.isDrawerVisible = true,
    this.drawerWidth = workspaceDefaultDrawerWidth,
    this.isResizingDrawer = false,
    this.isPinned = false,
    this.pinnedRouteRoot,
  })  : currentRoute = initialRoute,
        navigatorKey = GlobalKey<NavigatorState>(),
        routeHistory = [initialRoute],
        routeHistoryIndex = 0,
        isApplyingHistoryNavigation = false;

  bool get canGoBack => routeHistoryIndex > 0;
  bool get canGoForward => routeHistoryIndex < routeHistory.length - 1;

  String get moduleRoot =>
      pinnedRouteRoot ?? inferWorkspaceModuleRoot(currentRoute);

  bool allowsRoute(String route) {
    if (!isPinned) return true;
    final root = pinnedRouteRoot ?? inferWorkspaceModuleRoot(currentRoute);
    final path = workspaceRoutePath(route);
    if (root == '/dashboard') return path == '/dashboard';
    return path == root || path.startsWith('$root/');
  }

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
  final List<String> _workspaceStackOrderIds = [];
  int _activeIndex = 0;
  bool _isInitialized = false;
  bool _isAIPanelOpen = false;

  List<Workspace> get workspaces => List.unmodifiable(_workspaces);
  List<Workspace> get workspaceStackOrder => List.unmodifiable(
        _workspaceStackOrderIds
            .map(workspaceById)
            .whereType<Workspace>()
            .toList(),
      );
  int get activeIndex => _activeIndex;
  Workspace? get activeWorkspace =>
      _workspaces.isEmpty ? null : _workspaces[_activeIndex];
  int get activeStackIndex {
    final activeId = activeWorkspace?.id;
    if (activeId == null) return 0;
    final index = _workspaceStackOrderIds.indexOf(activeId);
    return index == -1 ? 0 : index;
  }

  String get workspaceStackSignature => _workspaceStackOrderIds.join('|');
  bool get isInitialized => _isInitialized;
  bool get isAIPanelOpen => _isAIPanelOpen;

  Workspace? workspaceById(String id) {
    final index = _workspaces.indexWhere((workspace) => workspace.id == id);
    return index == -1 ? null : _workspaces[index];
  }

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
    _workspaceStackOrderIds.add(id);
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

  void reorderWorkspace(int oldIndex, int newIndex) {
    if (oldIndex < 0 ||
        oldIndex >= _workspaces.length ||
        newIndex < 0 ||
        oldIndex == newIndex) {
      return;
    }

    final activeId = activeWorkspace?.id;
    if (oldIndex < newIndex) {
      newIndex -= 1;
    }
    final workspace = _workspaces.removeAt(oldIndex);
    final insertIndex = _normalizeWorkspaceInsertIndex(workspace, newIndex);
    _workspaces.insert(insertIndex, workspace);

    if (activeId != null) {
      _activeIndex = _workspaces.indexWhere((w) => w.id == activeId);
      if (_activeIndex == -1) _activeIndex = 0;
    }

    notifyListeners();
  }

  void moveWorkspaceToIndex(String workspaceId, int targetIndex) {
    final oldIndex = _workspaces.indexWhere((w) => w.id == workspaceId);
    if (oldIndex == -1) return;

    final activeId = activeWorkspace?.id;
    final workspace = _workspaces.removeAt(oldIndex);
    final insertIndex = _normalizeWorkspaceInsertIndex(workspace, targetIndex);
    if (oldIndex == insertIndex) {
      _workspaces.insert(oldIndex, workspace);
      return;
    }

    _workspaces.insert(insertIndex, workspace);

    if (activeId != null) {
      _activeIndex = _workspaces.indexWhere((w) => w.id == activeId);
      if (_activeIndex == -1) _activeIndex = 0;
    }

    notifyListeners();
  }

  int _normalizeWorkspaceInsertIndex(Workspace workspace, int targetIndex) {
    final pinnedCount =
        _workspaces.where((candidate) => candidate.isPinned).length;
    final minIndex = workspace.isPinned ? 0 : pinnedCount;
    final maxIndex = workspace.isPinned ? pinnedCount : _workspaces.length;
    return targetIndex.clamp(minIndex, maxIndex).toInt();
  }

  /// Close a workspace tab
  void closeWorkspace(int index) {
    if (_workspaces.length <= 1) {
      // Don't allow closing the last workspace
      return;
    }

    if (index >= 0 && index < _workspaces.length) {
      final closedWorkspace = _workspaces.removeAt(index);
      _workspaceStackOrderIds.remove(closedWorkspace.id);

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

  void setWorkspaceDrawerVisible(String workspaceId, bool visible) {
    final workspace = workspaceById(workspaceId);
    if (workspace == null || workspace.isDrawerVisible == visible) return;
    workspace.isDrawerVisible = visible;
    notifyListeners();
  }

  void showWorkspaceDrawer(String workspaceId) =>
      setWorkspaceDrawerVisible(workspaceId, true);

  void hideWorkspaceDrawer(String workspaceId) =>
      setWorkspaceDrawerVisible(workspaceId, false);

  void startWorkspaceDrawerResize(String workspaceId) {
    final workspace = workspaceById(workspaceId);
    if (workspace == null || workspace.isResizingDrawer) return;
    workspace.isResizingDrawer = true;
    notifyListeners();
  }

  void updateWorkspaceDrawerWidth(String workspaceId, double newWidth) {
    final workspace = workspaceById(workspaceId);
    if (workspace == null) return;

    final clampedWidth =
        newWidth.clamp(workspaceMinDrawerWidth, workspaceMaxDrawerWidth);
    if (workspace.drawerWidth == clampedWidth) return;

    workspace.drawerWidth = clampedWidth.toDouble();
    notifyListeners();
  }

  void stopWorkspaceDrawerResize(String workspaceId) {
    final workspace = workspaceById(workspaceId);
    if (workspace == null || !workspace.isResizingDrawer) return;
    workspace.isResizingDrawer = false;
    notifyListeners();
  }

  void toggleWorkspacePinned(int index) {
    if (index < 0 || index >= _workspaces.length) return;

    final activeId = activeWorkspace?.id;
    final workspace = _workspaces.removeAt(index);
    workspace.isPinned = !workspace.isPinned;
    workspace.pinnedRouteRoot = workspace.isPinned
        ? inferWorkspaceModuleRoot(workspace.currentRoute)
        : null;

    final pinnedInsertIndex =
        _workspaces.where((candidate) => candidate.isPinned).length;
    final insertIndex = pinnedInsertIndex.clamp(0, _workspaces.length).toInt();
    _workspaces.insert(insertIndex, workspace);

    if (activeId != null) {
      _activeIndex = _workspaces.indexWhere((w) => w.id == activeId);
      if (_activeIndex == -1) _activeIndex = 0;
    }

    notifyListeners();
  }

  /// Navigate the currently active workspace to a new route
  /// This is essential for external UI elements (like global FABs)
  /// that exist outside the individual GoRouter subtrees.
  void navigateActiveWorkspace(String route) {
    if (_workspaces.isEmpty) return;

    final activeWorkspace = _workspaces[_activeIndex];
    if (!activeWorkspace.allowsRoute(route)) {
      openRouteInWorkspace(route);
      return;
    }

    if (activeWorkspace.router != null) {
      debugPrint(
          '🧭 [WorkspaceManager] External navigation triggered to: $route');
      activeWorkspace.router!.go(route);
    } else {
      debugPrint(
          '⚠️ [WorkspaceManager] Cannot navigate: active workspace router is null');
    }
  }

  /// Navigate from an in-app shared link while preserving a useful back
  /// milestone. If the active workspace is pinned and cannot leave its module,
  /// the destination workspace still gets a return entry back to the source.
  void navigateActiveWorkspaceFromSharedLink(String route) {
    if (_workspaces.isEmpty) return;

    final sourceWorkspace = _workspaces[_activeIndex];
    final returnRoute = sourceWorkspace.currentRoute;

    if (sourceWorkspace.allowsRoute(route)) {
      navigateActiveWorkspace(route);
      return;
    }

    openRouteInWorkspace(route, returnRoute: returnRoute);
  }

  void navigateActiveWorkspaceBack() {
    final workspace = activeWorkspace;
    if (workspace == null || !workspace.canGoBack) return;

    workspace.routeHistoryIndex -= 1;
    _navigateWorkspaceToHistoryEntry(workspace);
  }

  void navigateActiveWorkspaceForward() {
    final workspace = activeWorkspace;
    if (workspace == null || !workspace.canGoForward) return;

    workspace.routeHistoryIndex += 1;
    _navigateWorkspaceToHistoryEntry(workspace);
  }

  void _navigateWorkspaceToHistoryEntry(Workspace workspace) {
    final route = workspace.routeHistory[workspace.routeHistoryIndex];
    workspace.isApplyingHistoryNavigation = true;
    workspace.currentRoute = route;
    workspace.title = getRouteTitle(route);
    workspace.router?.go(route);
    notifyListeners();
  }

  void openRouteInWorkspace(String route, {String? returnRoute}) {
    final existingIndex = _workspaces.indexWhere(
      (workspace) =>
          workspace.currentRoute == route || workspace.initialRoute == route,
    );
    if (existingIndex != -1) {
      final workspace = _workspaces[existingIndex];
      final shouldNavigate = workspace.currentRoute != route;
      _activeIndex = existingIndex;

      _installReturnMilestone(
        workspace: workspace,
        returnRoute: returnRoute,
        targetRoute: route,
        includeTarget: !shouldNavigate,
      );

      if (shouldNavigate) {
        if (workspace.router != null) {
          workspace.router!.go(route);
        } else {
          updateWorkspaceRouteById(workspace.id, route);
          return;
        }
      }

      notifyListeners();
      return;
    }

    final workspaceId =
        addWorkspace(title: getRouteTitle(route), initialRoute: route);
    final workspace = workspaceById(workspaceId);
    if (workspace != null) {
      _installReturnMilestone(
        workspace: workspace,
        returnRoute: returnRoute,
        targetRoute: route,
        includeTarget: true,
      );
      notifyListeners();
    }
  }

  void _installReturnMilestone({
    required Workspace workspace,
    required String? returnRoute,
    required String targetRoute,
    required bool includeTarget,
  }) {
    if (returnRoute == null || returnRoute == targetRoute) return;

    if (workspace.routeHistoryIndex < workspace.routeHistory.length - 1) {
      workspace.routeHistory.removeRange(
        workspace.routeHistoryIndex + 1,
        workspace.routeHistory.length,
      );
    }

    if (includeTarget &&
        workspace.routeHistory.length == 1 &&
        workspace.routeHistory.first == targetRoute) {
      workspace.routeHistory
        ..clear()
        ..add(returnRoute)
        ..add(targetRoute);
      workspace.routeHistoryIndex = 1;
      return;
    }

    if (workspace.routeHistory.isEmpty ||
        workspace.routeHistory.last != returnRoute) {
      workspace.routeHistory.add(returnRoute);
    }

    if (includeTarget && workspace.routeHistory.last != targetRoute) {
      workspace.routeHistory.add(targetRoute);
    }

    workspace.routeHistoryIndex = workspace.routeHistory.length - 1;
  }

  /// Toggles the AI Assistant right panel visibility
  void toggleAIPanel() {
    _isAIPanelOpen = !_isAIPanelOpen;
    notifyListeners();
  }

  /// Update the active workspace's title based on current route
  /// Called when navigation changes within a workspace
  void updateActiveWorkspaceRoute(String newRoute) {
    if (_workspaces.isEmpty) return;

    updateWorkspaceRouteById(_workspaces[_activeIndex].id, newRoute);
  }

  /// Update a specific workspace's route and title
  void updateWorkspaceRoute(int index, String newRoute) {
    if (index >= 0 && index < _workspaces.length) {
      updateWorkspaceRouteById(_workspaces[index].id, newRoute);
    }
  }

  String? handleWorkspaceRouteChange(String workspaceId, String newRoute) {
    final workspace = workspaceById(workspaceId);
    if (workspace == null) return null;

    if (!workspace.allowsRoute(newRoute)) {
      final fallbackRoute = workspace.allowsRoute(workspace.currentRoute)
          ? workspace.currentRoute
          : (workspace.pinnedRouteRoot ?? workspace.initialRoute);
      openRouteInWorkspace(newRoute);
      return fallbackRoute;
    }

    updateWorkspaceRouteById(workspaceId, newRoute);
    return null;
  }

  void updateWorkspaceRouteById(String workspaceId, String newRoute) {
    final workspace = workspaceById(workspaceId);
    if (workspace == null) return;

    if (workspace.currentRoute == newRoute) {
      workspace.isApplyingHistoryNavigation = false;
      return;
    }

    workspace.currentRoute = newRoute;
    workspace.title = getRouteTitle(newRoute);

    if (workspace.isApplyingHistoryNavigation) {
      workspace.isApplyingHistoryNavigation = false;
    } else {
      if (workspace.routeHistoryIndex < workspace.routeHistory.length - 1) {
        workspace.routeHistory.removeRange(
          workspace.routeHistoryIndex + 1,
          workspace.routeHistory.length,
        );
      }
      if (workspace.routeHistory.isEmpty ||
          workspace.routeHistory.last != newRoute) {
        workspace.routeHistory.add(newRoute);
      }
      workspace.routeHistoryIndex = workspace.routeHistory.length - 1;
    }

    debugPrint(
        '📍 [WorkspaceManager] Updated workspace "${workspace.id}" to route: $newRoute → title: "${workspace.title}"');
    notifyListeners();
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
    _workspaceStackOrderIds.clear();
    _activeIndex = 0;
    addWorkspace(title: 'Dashboard', initialRoute: '/dashboard');
  }
}
