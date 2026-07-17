import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/web_url.dart';

import 'package:go_router/go_router.dart';

const double workspaceMinDrawerWidth = 200.0;
const double workspaceMaxDrawerWidth = 400.0;
const double workspaceDefaultDrawerWidth = 280.0;

const _browserWorkspaceSessionPrefsKey =
    'vinabike_browser_workspace_session_v1';
const _browserWorkspaceSessionVersion = 1;
const _browserWorkspacePersistDelay = Duration(milliseconds: 250);

const _initialWorkspaceRouteRoots = <String>[
  '/mail',
  '/storage',
  '/dashboard',
  '/accounting',
  '/inventory',
  '/sales',
  '/purchases',
  '/taller',
  '/clientes',
  '/hr',
  '/pos',
  '/tools',
  '/settings',
  '/website',
  '/chat',
];

/// Returns the ERP route represented by a browser URL, including its query
/// string, or `null` when the URL is not a workspace route.
///
/// Keeping this independent from the live browser location lets startup pass
/// the URL captured before the unauthenticated router redirects through login.
String? resolveInitialWorkspaceRoute(String? browserUrl) {
  if (browserUrl == null || browserUrl.trim().isEmpty) return null;

  final uri = Uri.tryParse(browserUrl);
  if (uri == null) return null;

  final path = uri.path;
  final isWorkspaceRoute = _initialWorkspaceRouteRoots.any(
    (root) => path == root || path.startsWith('$root/'),
  );
  if (!isWorkspaceRoute) return null;

  if (uri.hasScheme && uri.hasAuthority) {
    return uri.toString().replaceFirst(uri.origin, '');
  }
  return uri.toString();
}

String workspaceRoutePath(String route) {
  return Uri.tryParse(route)?.path ?? route.split('?').first;
}

String buildBrowserWorkspaceRoute({
  required String url,
  String? title,
}) {
  final cleanTitle = title?.trim();
  return Uri(
    path: '/tools/web',
    queryParameters: {
      'url': url,
      if (cleanTitle != null && cleanTitle.isNotEmpty) 'name': cleanTitle,
    },
  ).toString();
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
    '/storage',
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
  final uri = Uri.tryParse(path);
  final cleanPath = uri?.path ?? path.split('?').first;

  if (cleanPath == '/tools/web') {
    final webName = uri?.queryParameters['name']?.trim();
    if (webName != null && webName.isNotEmpty) return webName;

    final webUrl = uri?.queryParameters['url']?.trim();
    if (webUrl != null && webUrl.isNotEmpty) {
      final parsedWebUrl = Uri.tryParse(webUrl);
      if (parsedWebUrl?.host.isNotEmpty == true) {
        return parsedWebUrl!.host;
      }
    }

    return 'Navegador web';
  }

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
    '/hr/planning': 'Planificación',
    '/hr/attendance': 'Asistencia',
    '/hr/attendances': 'Asistencias',
    '/hr/kiosk': 'Modo Kiosko',
    '/hr/medical-leaves': 'Licencias Médicas',

    // Website
    '/website': 'Sitio Web',
    '/website/pages': 'Gestión de Páginas',
    '/website/navigation': 'Navegación',

    // Mail
    '/mail': 'Correo',

    // Storage
    '/storage': 'Archivos',

    // Settings
    '/settings': 'Configuración',
    '/settings/appearance': 'Apariencia',
    '/settings/business-hours': 'Horario de Atención',
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
  String? browserUrl;
  String? browserTitle;
  bool isHydrated;

  Workspace({
    required this.id,
    required this.title,
    required this.initialRoute,
    this.isDrawerVisible = true,
    this.drawerWidth = workspaceDefaultDrawerWidth,
    this.isResizingDrawer = false,
    this.isPinned = false,
    this.pinnedRouteRoot,
    this.browserUrl,
    this.browserTitle,
    this.isHydrated = true,
  })  : currentRoute = initialRoute,
        navigatorKey = GlobalKey<NavigatorState>(),
        routeHistory = [initialRoute],
        routeHistoryIndex = 0,
        isApplyingHistoryNavigation = false;

  bool get canGoBack => routeHistoryIndex > 0;
  bool get canGoForward => routeHistoryIndex < routeHistory.length - 1;

  String get moduleRoot =>
      pinnedRouteRoot ?? inferWorkspaceModuleRoot(currentRoute);

  bool get isBrowserWorkspace =>
      workspaceRoutePath(currentRoute) == '/tools/web' ||
      workspaceRoutePath(initialRoute) == '/tools/web';

  String get shareRoute {
    final url = browserUrl;
    if (!isBrowserWorkspace || url == null || url.isEmpty) {
      return currentRoute;
    }
    return buildBrowserWorkspaceRoute(
      url: url,
      title: browserTitle ?? title,
    );
  }

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
  String _sessionIdentity;
  Timer? _browserSessionPersistTimer;
  Future<void> _browserSessionPersistTail = Future.value();
  Future<void> _sessionIdentityChangeTail = Future.value();
  late Future<void> _browserSessionReady;
  bool _isRestoringBrowserSession = true;
  int _sessionGeneration = 0;
  int _workspaceIdSequence = 0;

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
  Future<void> get browserSessionReady => _browserSessionReady;

  Workspace? workspaceById(String id) {
    final index = _workspaces.indexWhere((workspace) => workspace.id == id);
    return index == -1 ? null : _workspaces[index];
  }

  WorkspaceManager({
    String? initialBrowserUrl,
    String? sessionIdentity,
  }) : _sessionIdentity = _normalizeSessionIdentity(sessionIdentity) {
    debugPrint(
        '🏗️ [WorkspaceManager] Constructor called, checking initial URL');

    // Check if we should open a specific route based on browser URL
    String initialRoute = '/dashboard';
    String initialTitle = 'Dashboard';

    if (kIsWeb) {
      final resolvedRoute = resolveInitialWorkspaceRoute(
        initialBrowserUrl ?? getInitialBrowserUrl(),
      );
      if (resolvedRoute != null) {
        initialRoute = resolvedRoute;
        initialTitle = getRouteTitle(resolvedRoute);
        debugPrint(
            '🔗 [WorkspaceManager] Using URL from browser: $initialRoute');
      }
    }

    _addWorkspaceInternal(
      title: initialTitle,
      initialRoute: initialRoute,
      activate: true,
    );
    _isInitialized = true;
    debugPrint(
        '✅ [WorkspaceManager] Initialized with ${_workspaces.length} workspace(s)');
    _browserSessionReady = _restoreBrowserSession(_sessionGeneration);
  }

  static String _normalizeSessionIdentity(String? value) {
    final normalized = value?.trim() ?? '';
    return normalized.isEmpty ? 'anonymous' : normalized;
  }

  String get _browserSessionStorageKey =>
      '$_browserWorkspaceSessionPrefsKey::$_sessionIdentity';

  String _newWorkspaceId() {
    _workspaceIdSequence += 1;
    return '${DateTime.now().microsecondsSinceEpoch}-$_workspaceIdSequence';
  }

  Workspace _addWorkspaceInternal({
    required String title,
    required String initialRoute,
    required bool activate,
    bool isPinned = false,
    bool isHydrated = true,
  }) {
    final routeUri = Uri.tryParse(initialRoute);
    final isBrowserRoute = routeUri?.path == '/tools/web';
    final routeUrl = isBrowserRoute ? routeUri?.queryParameters['url'] : null;
    final routeTitle =
        isBrowserRoute ? routeUri?.queryParameters['name']?.trim() : null;

    final workspace = Workspace(
      id: _newWorkspaceId(),
      title: title,
      initialRoute: initialRoute,
      isPinned: isPinned,
      pinnedRouteRoot: isPinned ? inferWorkspaceModuleRoot(initialRoute) : null,
      browserUrl: routeUrl,
      browserTitle: routeTitle?.isNotEmpty == true ? routeTitle : title,
      isHydrated: isHydrated,
    );

    _workspaces.add(workspace);
    _workspaceStackOrderIds.add(workspace.id);
    if (activate) {
      _activeIndex = _workspaces.length - 1;
      workspace.isHydrated = true;
    }
    return workspace;
  }

  Future<void> _restoreBrowserSession(int generation) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (generation != _sessionGeneration) return;

      final encoded = prefs.getString(_browserSessionStorageKey);
      if (encoded == null || encoded.isEmpty) return;

      final decoded = jsonDecode(encoded);
      if (decoded is! Map<String, dynamic> ||
          decoded['version'] != _browserWorkspaceSessionVersion) {
        return;
      }

      final storedTabs = decoded['tabs'];
      if (storedTabs is! List) return;

      final previouslyActiveId = activeWorkspace?.id;
      final hadInitialBrowserWorkspace = _workspaces.any(
        (workspace) => workspace.isBrowserWorkspace,
      );
      final canRestoreBrowserFocus = !hadInitialBrowserWorkspace &&
          activeWorkspace?.initialRoute == '/dashboard' &&
          activeWorkspace?.currentRoute == '/dashboard';
      final existingUrls = _workspaces
          .where((workspace) => workspace.isBrowserWorkspace)
          .map(_browserUrlForWorkspace)
          .whereType<String>()
          .toSet();
      final restored = <Workspace>[];

      for (final value in storedTabs) {
        if (_workspaces.length >= maxWorkspaces) break;
        if (value is! Map) continue;

        final url = value['url']?.toString().trim() ?? '';
        final uri = Uri.tryParse(url);
        if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
          continue;
        }
        if (existingUrls.remove(uri.toString())) continue;

        final storedTitle = value['title']?.toString().trim() ?? '';
        final title = storedTitle.isNotEmpty
            ? storedTitle
            : (uri.host.isNotEmpty ? uri.host : 'Navegador web');
        final workspace = _addWorkspaceInternal(
          title: title,
          initialRoute: buildBrowserWorkspaceRoute(
            url: uri.toString(),
            title: title,
          ),
          activate: false,
          isPinned: value['isPinned'] == true,
          isHydrated: false,
        );
        restored.add(workspace);
      }

      if (restored.isNotEmpty) {
        final pinned = _workspaces
            .where((workspace) => workspace.isPinned)
            .toList(growable: false);
        final regular = _workspaces
            .where((workspace) => !workspace.isPinned)
            .toList(growable: false);
        _workspaces
          ..clear()
          ..addAll(pinned)
          ..addAll(regular);
      }

      if (canRestoreBrowserFocus &&
          decoded['activeWasBrowser'] == true &&
          restored.isNotEmpty) {
        final storedIndex = decoded['activeBrowserIndex'];
        final browserIndex = storedIndex is int
            ? storedIndex.clamp(0, restored.length - 1)
            : restored.length - 1;
        final activeWorkspace = restored[browserIndex];
        _activeIndex = _workspaces.indexOf(activeWorkspace);
        activeWorkspace.isHydrated = true;
      } else if (previouslyActiveId != null) {
        final restoredActiveIndex = _workspaces.indexWhere(
          (workspace) => workspace.id == previouslyActiveId,
        );
        if (restoredActiveIndex >= 0) {
          _activeIndex = restoredActiveIndex;
        }
      }
    } catch (error) {
      if (kDebugMode) {
        debugPrint('🌐 Browser workspace session restore skipped: $error');
      }
    } finally {
      if (generation == _sessionGeneration) {
        _isRestoringBrowserSession = false;
        super.notifyListeners();
      }
    }
  }

  String? _browserUrlForWorkspace(Workspace workspace) {
    final direct = workspace.browserUrl?.trim();
    if (direct != null && direct.isNotEmpty) return direct;

    final route = Uri.tryParse(workspace.currentRoute);
    final routeUrl = route?.path == '/tools/web'
        ? route?.queryParameters['url']?.trim()
        : null;
    return routeUrl?.isNotEmpty == true ? routeUrl : null;
  }

  String _browserSessionPayload() {
    final browserWorkspaces = _workspaces
        .where((workspace) => workspace.isBrowserWorkspace)
        .where((workspace) {
      final url = _browserUrlForWorkspace(workspace);
      final uri = url == null ? null : Uri.tryParse(url);
      return uri != null && (uri.scheme == 'http' || uri.scheme == 'https');
    }).toList(growable: false);
    final active = activeWorkspace;
    final activeBrowserIndex = active == null
        ? -1
        : browserWorkspaces
            .indexWhere((workspace) => workspace.id == active.id);

    return jsonEncode({
      'version': _browserWorkspaceSessionVersion,
      'activeWasBrowser': activeBrowserIndex >= 0,
      'activeBrowserIndex': activeBrowserIndex,
      'tabs': [
        for (final workspace in browserWorkspaces)
          {
            'url': _browserUrlForWorkspace(workspace),
            'title': workspace.browserTitle ?? workspace.title,
            'isPinned': workspace.isPinned,
          },
      ],
    });
  }

  void _scheduleBrowserSessionPersist() {
    if (_isRestoringBrowserSession || !_isInitialized) return;
    _browserSessionPersistTimer?.cancel();
    _browserSessionPersistTimer = Timer(
      _browserWorkspacePersistDelay,
      () => unawaited(flushBrowserSession()),
    );
  }

  Future<void> flushBrowserSession() {
    _browserSessionPersistTimer?.cancel();
    _browserSessionPersistTimer = null;

    final storageKey = _browserSessionStorageKey;
    final payload = _browserSessionPayload();
    final hasBrowserWorkspaces =
        _workspaces.any((workspace) => workspace.isBrowserWorkspace);

    _browserSessionPersistTail = _browserSessionPersistTail.then((_) async {
      try {
        final prefs = await SharedPreferences.getInstance();
        if (hasBrowserWorkspaces) {
          await prefs.setString(storageKey, payload);
        } else {
          await prefs.remove(storageKey);
        }
      } catch (error) {
        if (kDebugMode) {
          debugPrint('🌐 Browser workspace session save skipped: $error');
        }
      }
    });
    return _browserSessionPersistTail;
  }

  Future<void> setSessionIdentity(String? value) {
    final nextIdentity = _normalizeSessionIdentity(value);
    final transition = _sessionIdentityChangeTail.then(
      (_) => _applySessionIdentity(nextIdentity),
    );
    _sessionIdentityChangeTail = transition;
    return transition;
  }

  Future<void> _applySessionIdentity(String nextIdentity) async {
    if (nextIdentity == _sessionIdentity) {
      await _browserSessionReady;
      return;
    }

    await _browserSessionReady;
    await flushBrowserSession();

    _sessionGeneration += 1;
    _sessionIdentity = nextIdentity;
    _isRestoringBrowserSession = true;
    _workspaces.clear();
    _workspaceStackOrderIds.clear();
    _activeIndex = 0;
    _addWorkspaceInternal(
      title: 'Dashboard',
      initialRoute: '/dashboard',
      activate: true,
    );
    super.notifyListeners();

    _browserSessionReady = _restoreBrowserSession(_sessionGeneration);
    await _browserSessionReady;
  }

  @override
  void notifyListeners() {
    _scheduleBrowserSessionPersist();
    super.notifyListeners();
  }

  @override
  void dispose() {
    _browserSessionPersistTimer?.cancel();
    unawaited(flushBrowserSession());
    super.dispose();
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

    final workspace = _addWorkspaceInternal(
      title: title,
      initialRoute: initialRoute,
      activate: true,
    );
    debugPrint(
        '✅ [WorkspaceManager] Workspace added. Total: ${_workspaces.length}, Active: $_activeIndex');
    notifyListeners();

    return workspace.id;
  }

  /// Opens a web page in a fresh ERP browser tab. Returns the new workspace
  /// id, or `null` when the tab limit has been reached or the URL is invalid.
  String? openBrowserWorkspace(
    String url, {
    String? title,
  }) {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
      return null;
    }
    if (_workspaces.length >= maxWorkspaces) return null;

    final cleanTitle = title?.trim();
    final resolvedTitle = cleanTitle?.isNotEmpty == true
        ? cleanTitle!
        : (uri.host.isNotEmpty ? uri.host : 'Navegador web');
    return addWorkspace(
      title: resolvedTitle,
      initialRoute: buildBrowserWorkspaceRoute(
        url: uri.toString(),
        title: resolvedTitle,
      ),
    );
  }

  /// Records the actual page loaded inside a browser workspace without
  /// replacing its GoRouter route (which would destroy the live WebView).
  void updateBrowserWorkspaceState(
    String workspaceId, {
    required String url,
    String? title,
  }) {
    final workspace = workspaceById(workspaceId);
    if (workspace == null || !workspace.isBrowserWorkspace) return;

    final uri = Uri.tryParse(url.trim());
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) return;

    final cleanTitle = title?.trim();
    final nextTitle = cleanTitle?.isNotEmpty == true
        ? cleanTitle!
        : (uri.host.isNotEmpty ? uri.host : workspace.title);
    final boundedTitle = nextTitle.length <= 140
        ? nextTitle
        : '${nextTitle.substring(0, 137)}...';

    final changed = workspace.browserUrl != uri.toString() ||
        workspace.browserTitle != boundedTitle ||
        workspace.title != boundedTitle;
    if (!changed) return;

    workspace.browserUrl = uri.toString();
    workspace.browserTitle = boundedTitle;
    workspace.title = boundedTitle;
    notifyListeners();
  }

  /// Switch to a specific workspace by index
  void switchToWorkspace(int index) {
    if (index >= 0 && index < _workspaces.length) {
      _activeIndex = index;
      _workspaces[index].isHydrated = true;
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
