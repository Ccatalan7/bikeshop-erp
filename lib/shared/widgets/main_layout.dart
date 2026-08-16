import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../services/auth_service.dart';
import '../services/current_user_profile_service.dart';
import '../services/current_user_profile_navigation.dart';
import '../services/navigation_service.dart';
import '../services/query_performance_service.dart';
import '../services/right_toolbar_service.dart';
import '../services/workspace_launch_options.dart';
import '../services/workspace_manager.dart';
import '../services/window_zoom_service.dart';
import '../services/notification_service.dart';
import '../themes/workspace_chrome_theme.dart';
import '../utils/responsive_viewport.dart';
import '../../modules/settings/services/appearance_service.dart';
import '../../modules/messaging/providers/chat_provider.dart';
import '../../modules/mail/providers/mail_account_manager.dart';
import 'browser_workspace_favicon.dart';
import 'expandable_menu_item.dart';
import 'toolbar_tool_presentation.dart';
import 'current_user_profile_tile.dart';
import 'workspace_shell_scope.dart';

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
    icon: Icons.account_balance_outlined,
    title: 'Conciliación bancaria',
    route: '/accounting/bank-reconciliation',
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
    icon: Icons.design_services_outlined,
    title: 'Servicios',
    route: '/inventory/services',
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

  final isSmallScreen = ResponsiveViewport.usesCompactShell(context);
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
    '/accounting/bank-reconciliation': 'Conciliación bancaria',
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
    '/inventory/services': 'Servicios',
    '/inventory/categories': 'Categorías',
    '/sales/invoices': 'Ventas',
    '/sales/reports': 'Informes de Ventas',
    '/sales/reports/by-product': 'Ventas por Artículo',
    '/sales/reports/by-customer': 'Ventas por Cliente',
    '/purchases/suppliers': 'Compras',
    '/pos': 'POS',
    '/hr/employees': 'Trabajadores',
    '/hr/planning': 'Planificación',
    '/hr/attendances': 'Asistencias',
    '/hr/payroll': 'Nóminas',
    '/website': 'Sitio Web',
    '/website/product-visibility': 'Visibilidad de productos',
    '/website/orders': 'Órdenes / Notificaciones',
    '/tienda': 'Editor Web',
    '/tienda?edit=true': 'Editor Web',
    '/storage': 'Archivos',
    '/settings': 'Configuración',
    '/profile': 'Mi perfil',
    '/settings/business-hours': 'Horario de atención',
    '/debug': 'Debug',
  };

  return routeTitles[route] ??
      routeTitles[_routePath(route)] ??
      _routePath(route).split('/').last.capitalize();
}

String _routePath(String route) {
  return Uri.tryParse(route)?.path ?? route.split('?').first;
}

String _resolveWebsiteMenuRoute(String route) {
  if (_routePath(route) != '/website/orders') return route;
  return NotificationService().latestOnlineOrderAlertRoute ?? route;
}

Workspace? _maybeWorkspaceOf(BuildContext context) {
  try {
    return Provider.of<Workspace>(context, listen: false);
  } catch (_) {
    return null;
  }
}

extension StringExtension on String {
  String capitalize() {
    if (isEmpty) return this;
    return '${this[0].toUpperCase()}${substring(1)}';
  }
}

const List<MenuSubItem> _hrManagementMenuItems = [
  MenuSubItem(
    icon: Icons.people_outlined,
    title: 'Trabajadores',
    route: '/hr/employees',
  ),
  MenuSubItem(
    icon: Icons.calendar_month_outlined,
    title: 'Planificación',
    route: '/hr/planning',
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
];

const MenuSubItem _hrPayrollMenuItem = MenuSubItem(
  icon: Icons.attach_money_outlined,
  title: 'Nóminas',
  route: '/hr/payroll',
);

const List<MenuSubItem> _hrMenuItems = [
  ..._hrManagementMenuItems,
  _hrPayrollMenuItem,
];

const String _hrSectionKey = 'hr';

List<MenuSubItem> _visibleHrMenuItems(
  CurrentUserProfileService profileService,
) {
  final profile = profileService.profile;
  if (profileService.isLoading ||
      profileService.loadIssue != null ||
      profile == null) {
    return const [];
  }
  return [
    if (profile.canManageUsers) ..._hrManagementMenuItems,
    if (profile.canAccessAccounting) _hrPayrollMenuItem,
  ];
}

void _reorderVisibleModules(
  NavigationService navigationService,
  List<String> visibleOrder,
  int oldIndex,
  int newIndex,
) {
  if (oldIndex < 0 ||
      oldIndex >= visibleOrder.length ||
      newIndex < 0 ||
      newIndex > visibleOrder.length) {
    return;
  }

  var insertionIndex = newIndex;
  if (oldIndex < insertionIndex) insertionIndex -= 1;
  final movedKey = visibleOrder[oldIndex];
  final remaining = List<String>.from(visibleOrder)..removeAt(oldIndex);
  insertionIndex = insertionIndex.clamp(0, remaining.length);
  if (insertionIndex == oldIndex || remaining.isEmpty) return;

  final fullOrder = navigationService.moduleOrder;
  final oldFullIndex = fullOrder.indexOf(movedKey);
  if (oldFullIndex == -1) return;

  final int newFullIndex;
  if (insertionIndex < remaining.length) {
    newFullIndex = fullOrder.indexOf(remaining[insertionIndex]);
  } else {
    newFullIndex = fullOrder.indexOf(remaining.last) + 1;
  }
  if (newFullIndex < 0) return;
  navigationService.reorderModules(oldFullIndex, newFullIndex);
}

const List<MenuSubItem> _chatMenuItems = [
  MenuSubItem(
    icon: Icons.chat_bubble_outline,
    title: 'Meson de ayuda',
    route: '/chat',
  ),
];

const String _chatSectionKey = 'chat';

const List<MenuSubItem> _storageMenuItems = [
  MenuSubItem(
    icon: Icons.folder_open_outlined,
    title: 'Archivos',
    route: '/storage',
  ),
];

const String _storageSectionKey = 'storage';

const List<MenuSubItem> _websiteMenuItems = [
  MenuSubItem(
    icon: Icons.dashboard_outlined,
    title: 'Dashboard',
    route: '/website',
  ),
  MenuSubItem(
    icon: Icons.design_services_outlined,
    title: 'Editor',
    route: '/tienda?edit=true',
  ),
  MenuSubItem(
    icon: Icons.notifications_active_outlined,
    title: 'Órdenes / Notificaciones',
    route: '/website/orders',
  ),
  MenuSubItem(
    icon: Icons.visibility_outlined,
    title: 'Visibilidad productos',
    route: '/website/product-visibility',
  ),
];

const String _websiteSectionKey = 'website';

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
const String _neutralDarkSidebarVinabikeLogoAsset =
    'assets/images/vinabike_logo_dark.png';
const Map<String, String> _darkSidebarVinabikeLogoAssets = {
  'midnight': 'assets/images/vinabike_logo_dark_midnight.png',
  'aubergine': 'assets/images/vinabike_logo_dark_aubergine.png',
  'graphite_copper': 'assets/images/vinabike_logo_dark_graphite_copper.png',
  'evergreen': 'assets/images/vinabike_logo_dark_evergreen.png',
  'pacific': 'assets/images/vinabike_logo_dark_pacific.png',
};

bool _shouldUseDarkVinabikeLogo(ThemeData theme, String? logoUrl) {
  if (logoUrl == null || logoUrl.isEmpty) return false;
  if (theme.colorScheme.surface.computeLuminance() > 0.35) return false;

  final parsedUri = Uri.tryParse(logoUrl);
  final rawFileName = parsedUri != null && parsedUri.pathSegments.isNotEmpty
      ? parsedUri.pathSegments.last
      : logoUrl;
  final fileName = (() {
    try {
      return Uri.decodeComponent(rawFileName).toLowerCase();
    } catch (_) {
      return rawFileName.toLowerCase();
    }
  })();

  return fileName.contains('vinabike') || fileName.contains('viñabike');
}

Widget _buildAdaptiveCompanyLogo({
  required BuildContext context,
  required AppearanceService appearanceService,
  required Widget Function(BuildContext context) fallbackBuilder,
}) {
  final theme = Theme.of(context);
  final logoUrl = appearanceService.companyLogoUrl;

  if (_shouldUseDarkVinabikeLogo(theme, logoUrl)) {
    return Image.asset(
      _darkSidebarVinabikeLogoAssets[appearanceService.sidebarPaletteCode] ??
          _neutralDarkSidebarVinabikeLogoAsset,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
    );
  }

  if (logoUrl == null || logoUrl.isEmpty) {
    return fallbackBuilder(context);
  }

  return CachedNetworkImage(
    imageUrl: logoUrl,
    fit: BoxFit.contain,
    imageBuilder: (context, imageProvider) => Image(
      image: imageProvider,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
    ),
    placeholder: (context, url) => Center(
      child: SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: theme.colorScheme.primary,
        ),
      ),
    ),
    errorWidget: (context, url, error) => fallbackBuilder(context),
  );
}

// ─── Debug (Bug Tracking) module ─────────────────────────────────
const List<MenuSubItem> _debugMenuItems = [
  MenuSubItem(
    icon: Icons.bug_report_outlined,
    title: 'Lista de bugs',
    route: '/debug',
  ),
];

const String _debugSectionKey = 'debug';

/// One destination of the single navigation model.
///
/// The expanded sidebar, the compact icon rail and the mobile drawer all
/// consume this same resolved list: destinations, permissions, order and
/// badges are decided once, never per-surface.
@immutable
class AppDestinationModule {
  const AppDestinationModule({
    required this.key,
    required this.title,
    required this.icon,
    required this.activeIcon,
    required this.items,
    this.isSingleItem = false,
    this.enabled = true,
    this.badgeCount = 0,
    this.subItemBadgeCounts = const <String, int>{},
    this.resolveRoute,
    this.badgeTapRoute,
  });

  final String key;
  final String title;
  final IconData icon;
  final IconData activeIcon;
  final List<MenuSubItem> items;
  final bool isSingleItem;
  final bool enabled;
  final int badgeCount;
  final Map<String, int> subItemBadgeCounts;

  /// Optional late route resolution (e.g. the newest online-order alert).
  final String Function(String route)? resolveRoute;

  /// Canonical destination of the badge itself. The model owns this action:
  /// sidebar, rail and drawer all consume the same resolved route.
  final String? badgeTapRoute;

  bool matchesLocation(String location) =>
      _moduleMatchesLocation(location, items);

  /// The badge's durable action, resolved through [resolveRoute]. `null`
  /// when the module has no badge action or nothing pending.
  String? get resolvedBadgeRoute {
    final route = badgeTapRoute;
    if (route == null || badgeCount <= 0) return null;
    return resolveRoute?.call(route) ?? route;
  }
}

bool _moduleMatchesLocation(String location, List<MenuSubItem> items) {
  final locationPath = _routePath(location);
  for (final item in items) {
    if (item.isHeader) continue;
    final routePath = _routePath(item.route);
    if (locationPath == routePath || locationPath.startsWith('$routePath/')) {
      return true;
    }
  }
  return false;
}

/// Resolves the user-ordered, permission-filtered module list.
///
/// Must be called from a `build` method: it subscribes to the services that
/// own order, permissions and badge counts.
List<AppDestinationModule> resolveOrderedAppModules(BuildContext context) {
  final navigationService = context.watch<NavigationService>();
  final chatProvider = context.watch<ChatProvider>();
  final visibleHrItems = _visibleHrMenuItems(
    context.watch<CurrentUserProfileService>(),
  );

  final byKey = <String, AppDestinationModule>{
    'accounting': const AppDestinationModule(
      key: 'accounting',
      title: 'Contabilidad',
      icon: Icons.account_balance_outlined,
      activeIcon: Icons.account_balance,
      items: _accountingMenuItems,
    ),
    'tax_reports': const AppDestinationModule(
      key: 'tax_reports',
      title: 'Impuestos',
      icon: Icons.receipt_long_outlined,
      activeIcon: Icons.receipt_long,
      items: _taxReportsMenuItems,
    ),
    'chat': AppDestinationModule(
      key: 'chat',
      title: 'Mensajería',
      icon: Icons.chat_outlined,
      activeIcon: Icons.chat,
      items: _chatMenuItems,
      isSingleItem: true,
      badgeCount: chatProvider.totalUnreadCount,
    ),
    'storage': const AppDestinationModule(
      key: 'storage',
      title: 'Archivos',
      icon: Icons.folder_open_outlined,
      activeIcon: Icons.folder,
      items: _storageMenuItems,
      isSingleItem: true,
    ),
    'customers': const AppDestinationModule(
      key: 'customers',
      title: 'Clientes',
      icon: Icons.people_outline,
      activeIcon: Icons.people,
      items: _customersMenuItems,
    ),
    'workshop': const AppDestinationModule(
      key: 'workshop',
      title: 'Taller',
      icon: Icons.pedal_bike_outlined,
      activeIcon: Icons.pedal_bike,
      items: _workshopMenuItems,
    ),
    'smart_features': const AppDestinationModule(
      key: 'smart_features',
      title: 'Smart Features',
      icon: Icons.lightbulb_outlined,
      activeIcon: Icons.lightbulb,
      items: _smartFeaturesMenuItems,
    ),
    'inventory': const AppDestinationModule(
      key: 'inventory',
      title: 'Inventario',
      icon: Icons.inventory_2_outlined,
      activeIcon: Icons.inventory_2,
      items: _inventoryMenuItems,
    ),
    'sales': const AppDestinationModule(
      key: 'sales',
      title: 'Ventas',
      icon: Icons.receipt_long_outlined,
      activeIcon: Icons.receipt_long,
      items: _salesMenuItems,
    ),
    'purchases': const AppDestinationModule(
      key: 'purchases',
      title: 'Compras',
      icon: Icons.shopping_cart_outlined,
      activeIcon: Icons.shopping_cart,
      items: _purchasesMenuItems,
    ),
    'pos': const AppDestinationModule(
      key: 'pos',
      title: 'POS',
      icon: Icons.point_of_sale_outlined,
      activeIcon: Icons.point_of_sale,
      items: _posMenuItems,
    ),
    if (visibleHrItems.isNotEmpty)
      'hr': AppDestinationModule(
        key: 'hr',
        title: 'RR.HH.',
        icon: Icons.badge_outlined,
        activeIcon: Icons.badge,
        items: visibleHrItems,
      ),
    'tools': const AppDestinationModule(
      key: 'tools',
      title: 'Herramientas',
      icon: Icons.build_circle_outlined,
      activeIcon: Icons.build_circle,
      items: _toolsMenuItems,
    ),
    'debug': const AppDestinationModule(
      key: 'debug',
      title: 'Debug',
      icon: Icons.bug_report_outlined,
      activeIcon: Icons.bug_report,
      items: _debugMenuItems,
    ),
  };

  return [
    for (final moduleKey in navigationService.moduleOrder)
      if (byKey[moduleKey] case final module?) module,
  ];
}

/// Resolves the fixed destinations that close the model (Sitio Web, Correo).
///
/// Callers must rebuild on [NotificationService.onlineOrderAlertCount] and
/// [MailAccountManager.instance]; this resolver only reads current values.
List<AppDestinationModule> resolveFixedAppModules(
  BuildContext context, {
  required String currentLocation,
}) {
  final onlineOrderAlerts = NotificationService().onlineOrderAlertCount.value;
  final visibleOrderAlerts =
      currentLocation.startsWith('/website/orders') ? 0 : onlineOrderAlerts;

  return [
    AppDestinationModule(
      key: _websiteSectionKey,
      title: 'Sitio Web',
      icon: Icons.web_outlined,
      activeIcon: Icons.web,
      items: _websiteMenuItems,
      badgeCount: visibleOrderAlerts,
      subItemBadgeCounts: {'/website/orders': visibleOrderAlerts},
      resolveRoute: _resolveWebsiteMenuRoute,
      badgeTapRoute: '/website/orders',
    ),
    AppDestinationModule(
      key: 'mail',
      title: 'Correo',
      icon: Icons.email_outlined,
      activeIcon: Icons.email,
      items: const [
        MenuSubItem(icon: Icons.email, title: 'Correo', route: '/mail'),
      ],
      isSingleItem: true,
      badgeCount: MailAccountManager.instance.unreadCount,
    ),
  ];
}

/// Shows the sidebar options menu with live-updating zoom controls
void _showSidebarOptionsMenu({
  required BuildContext anchorContext,
  required BuildContext overlayContext,
  required NavigationService navigationService,
}) {
  final RenderBox button = anchorContext.findRenderObject() as RenderBox;
  final navigator = Navigator.of(overlayContext, rootNavigator: true);
  final RenderBox overlay =
      navigator.overlay!.context.findRenderObject() as RenderBox;
  final buttonPosition = button.localToGlobal(Offset.zero, ancestor: overlay);

  showDialog(
    context: overlayContext,
    useRootNavigator: true,
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
          key: const ValueKey('sidebar-options-overlay'),
          elevation: 8,
          borderRadius: BorderRadius.circular(8),
          color: theme.colorScheme.surface,
          child: Container(
            width: 308,
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
                _ThemeModeSelector(
                  mode: appearanceService.themeMode,
                  onChanged: appearanceService.setThemeMode,
                  padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
                ),
                Divider(
                    height: 1,
                    color: theme.colorScheme.outlineVariant
                        .withValues(alpha: 0.3)),
                _SidebarPalettePicker(
                  appearanceService: appearanceService,
                ),
                _OptionSwitchTile(
                  icon: Icons.chat_bubble_outline,
                  label: 'Paleta en mensajería y barra derecha',
                  value: appearanceService.messagingUsesSidebarPalette,
                  onChanged: appearanceService.setMessagingUsesSidebarPalette,
                ),
                AnimatedBuilder(
                  animation: navigationService,
                  builder: (context, _) {
                    return _OptionSwitchTile(
                      icon: Icons.view_sidebar_outlined,
                      label: 'Menú compacto por defecto',
                      value: navigationService.preferredChromeMode ==
                          NavigationChromeMode.rail,
                      onChanged: (compact) =>
                          navigationService.setPreferredChromeMode(
                        compact
                            ? NavigationChromeMode.rail
                            : NavigationChromeMode.expanded,
                      ),
                    );
                  },
                ),
                Divider(
                    height: 1,
                    color: theme.colorScheme.outlineVariant
                        .withValues(alpha: 0.3)),
                // Zoom controls
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(
                    children: [
                      Icon(Icons.zoom_in,
                          size: 18,
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.7)),
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
                    color: theme.colorScheme.outlineVariant
                        .withValues(alpha: 0.3)),
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
                size: 18,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.7)),
            const SizedBox(width: 12),
            Text(label, style: theme.textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}

class _OptionSwitchTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _OptionSwitchTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Icon(
              icon,
              size: 18,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium,
              ),
            ),
            Switch.adaptive(
              value: value,
              onChanged: onChanged,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ],
        ),
      ),
    );
  }
}

class _SidebarPalettePicker extends StatelessWidget {
  final AppearanceService appearanceService;

  const _SidebarPalettePicker({
    required this.appearanceService,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selectedCode = appearanceService.sidebarPaletteCode;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.palette_outlined,
                size: 18,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
              ),
              const SizedBox(width: 12),
              Text(
                'Paleta del panel',
                style: theme.textTheme.bodyMedium,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: AppearanceService.sidebarPalettes.map((palette) {
              return _SidebarPaletteSwatch(
                palette: palette,
                selected: palette.code == selectedCode,
                onTap: () => appearanceService.setSidebarPalette(palette.code),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

class _SidebarPaletteSwatch extends StatelessWidget {
  final SidebarPaletteOption palette;
  final bool selected;
  final VoidCallback onTap;

  const _SidebarPaletteSwatch({
    required this.palette,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          width: 134,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: selected
                ? palette.accent.withValues(alpha: 0.12)
                : theme.colorScheme.onSurface.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected
                  ? palette.accent
                  : theme.colorScheme.outlineVariant.withValues(alpha: 0.45),
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              _SidebarPalettePreview(palette: palette),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  palette.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color:
                        selected ? palette.accent : theme.colorScheme.onSurface,
                  ),
                ),
              ),
              if (selected) ...[
                const SizedBox(width: 4),
                Icon(Icons.check, size: 14, color: palette.accent),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SidebarPalettePreview extends StatelessWidget {
  final SidebarPaletteOption palette;

  const _SidebarPalettePreview({
    required this.palette,
  });

  @override
  Widget build(BuildContext context) {
    final outlineColor = Color.alphaBlend(
      palette.foreground.withValues(alpha: 0.18),
      palette.border,
    );

    return Container(
      width: 38,
      height: 30,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: outlineColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 3,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(color: palette.background),
          Align(
            alignment: Alignment.centerRight,
            child: FractionallySizedBox(
              widthFactor: 0.46,
              heightFactor: 1,
              child: ColoredBox(color: palette.backgroundAlt),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: FractionallySizedBox(
              widthFactor: 1,
              heightFactor: 0.24,
              child: ColoredBox(color: palette.accent),
            ),
          ),
          Positioned(
            left: 6,
            top: 6,
            child: Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(
                color: palette.foreground,
                shape: BoxShape.circle,
                border: Border.all(
                  color: palette.background.withValues(alpha: 0.65),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

@immutable
class MainLayoutCompactHeader {
  const MainLayoutCompactHeader({
    required this.title,
    this.contextLine,
    this.search,
    this.actions = const <Widget>[],
  });

  /// Semantic title owned by the compact shell.
  ///
  /// Feature pages provide content, never a pre-styled widget from their
  /// surface theme. This keeps light content colors from leaking onto the
  /// chromatic workspace header.
  final String title;
  final String? contextLine;
  final MainLayoutCompactSearch? search;
  final List<Widget> actions;
}

@immutable
class MainLayoutCompactSearch {
  const MainLayoutCompactSearch({
    required this.controller,
    required this.onChanged,
    this.fieldKey,
    this.hintText = 'Buscar…',
    this.autofocus = false,
    this.textInputAction = TextInputAction.search,
    this.onClear,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final Key? fieldKey;
  final String hintText;
  final bool autofocus;
  final TextInputAction textInputAction;
  final VoidCallback? onClear;
}

class MainLayout extends StatefulWidget {
  final Widget? child;
  final Widget? body;
  final String? title;
  final VoidCallback? onBackPressed;
  final MainLayoutCompactHeader? compactHeader;

  const MainLayout({
    super.key,
    this.child,
    this.body,
    this.title,
    this.onBackPressed,
    this.compactHeader,
  });

  @override
  State<MainLayout> createState() => _MainLayoutState();
}

class _MainLayoutState extends State<MainLayout> {
  final ValueNotifier<bool> _compactDrawerToolsMode = ValueNotifier(false);
  final GlobalKey _routedContentKey = GlobalKey(
    debugLabel: 'main-layout-routed-content',
  );

  Widget _buildRoutedContent() {
    return KeyedSubtree(
      key: _routedContentKey,
      child: widget.body ?? widget.child ?? const SizedBox.shrink(),
    );
  }

  @override
  void dispose() {
    _compactDrawerToolsMode.dispose();
    super.dispose();
  }

  Widget _buildCompactTitle(
    BuildContext context,
    WorkspaceChromeStyleData chrome,
  ) {
    final header = widget.compactHeader;
    final search = header?.search;
    if (search != null) {
      final textTheme = Theme.of(context).textTheme;
      final fieldBorder = OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: chrome.edge),
      );
      return SizedBox(
        height: 40,
        child: TextField(
          key: search.fieldKey,
          controller: search.controller,
          autofocus: search.autofocus,
          textInputAction: search.textInputAction,
          cursorColor: chrome.accent,
          style: textTheme.bodyMedium?.copyWith(
            color: chrome.foreground,
            fontWeight: FontWeight.w600,
          ),
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: chrome.raised,
            hintText: search.hintText,
            hintStyle: textTheme.bodyMedium?.copyWith(
              color: chrome.mutedForeground,
            ),
            prefixIcon: Icon(
              Icons.search_rounded,
              size: 19,
              color: chrome.mutedForeground,
            ),
            suffixIcon: search.controller.text.isEmpty || search.onClear == null
                ? null
                : IconButton(
                    icon: const Icon(Icons.clear_rounded, size: 18),
                    color: chrome.foreground,
                    tooltip: 'Limpiar búsqueda',
                    onPressed: search.onClear,
                  ),
            border: fieldBorder,
            enabledBorder: fieldBorder,
            focusedBorder: fieldBorder.copyWith(
              borderSide: BorderSide(color: chrome.accent, width: 1.5),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 10,
              vertical: 9,
            ),
          ),
          onChanged: search.onChanged,
        ),
      );
    }

    final contextLine = header?.contextLine?.trim();
    final title = header?.title ?? widget.title ?? 'Viñabike ERP';
    if (contextLine == null || contextLine.isEmpty) {
      return Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: chrome.foreground,
              fontWeight: FontWeight.w700,
            ),
      );
    }

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: chrome.foreground,
                fontWeight: FontWeight.w700,
              ),
        ),
        Text(
          contextLine,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: chrome.mutedForeground,
                fontFamily: 'monospace',
                fontSize: 10.5,
                fontWeight: FontWeight.w500,
              ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = ResponsiveViewport.widthOf(context);
    final showSidebar = screenWidth >= ResponsiveViewport.desktopMin;
    final workspaceTopInset = WorkspaceShellScope.topInsetOf(context);
    final workspaceChrome = WorkspaceChromeStyle.maybeOf(context);
    final navigationService = Provider.of<NavigationService>(context);
    final workspaceManager = Provider.of<WorkspaceManager>(context);
    final scopedWorkspace = _maybeWorkspaceOf(context);
    final workspaceState = scopedWorkspace == null
        ? null
        : workspaceManager.workspaceById(scopedWorkspace.id);
    final isPinnedWorkspace = workspaceState?.isPinned ?? false;
    final isDrawerVisible = !isPinnedWorkspace &&
        (workspaceState?.isDrawerVisible ?? navigationService.isDrawerVisible);
    final drawerWidth =
        workspaceState?.drawerWidth ?? navigationService.drawerWidth;
    final isResizingDrawer =
        workspaceState?.isResizingDrawer ?? navigationService.isResizing;
    // Tri-state chrome: expanded sidebar, compact icon rail, or temporarily
    // hidden. The workspace runtime override wins; new workspaces follow the
    // user preference. Pinned workspaces keep their no-chrome restriction.
    final chromeMode = workspaceState?.chromeModeOverride ??
        navigationService.preferredChromeMode;
    final isRailChrome =
        isDrawerVisible && chromeMode == NavigationChromeMode.rail;
    final navChromeWidth = !isDrawerVisible
        ? 0.0
        : isRailChrome
            ? AppNavigationRail.railWidth
            : drawerWidth;
    final routedContent = _buildRoutedContent();

    if (showSidebar) {
      // Desktop layout with collapsible sidebar
      return Scaffold(
        body: Row(
          // The shell fills the viewport height. Without this the row centres
          // its children on the cross axis, which vertically centres any route
          // whose content is shorter than the window.
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Collapsible Sidebar with smart animation
            // No animation during resize for instant tracking
            // Animation only for collapse/expand
            AnimatedContainer(
              duration: isResizingDrawer
                  ? Duration.zero
                  : const Duration(milliseconds: 250),
              curve: Curves.easeInOut,
              width: navChromeWidth,
              child: isDrawerVisible
                  ? Consumer<AppearanceService>(
                      builder: (context, appearanceService, _) {
                        final palette = appearanceService.sidebarPalette;
                        final chrome = workspaceChrome ??
                            WorkspaceChromeTheme.resolve(
                              palette: palette,
                              brightness: Theme.of(context).brightness,
                            );
                        final sidebar = isRailChrome
                            ? const AppNavigationRail()
                            : Theme(
                                data: WorkspaceChromeTheme.sidebarTheme(
                                  Theme.of(context),
                                  chrome,
                                ),
                                child: AppSidebar(
                                  overlayContext: context,
                                ),
                              );

                        return Container(
                          decoration:
                              WorkspaceChromeTheme.sidebarDecoration(chrome),
                          child: sidebar,
                        );
                      },
                    )
                  : const SizedBox.shrink(),
            ),
            // Shell divider. It is a sibling of the content rather than a
            // border on it, because a border painted on the content box stops
            // wherever that content ends and reads as a clipped half-line on
            // any route shorter than the viewport.
            if (isDrawerVisible)
              Container(
                width: 1,
                color: workspaceChrome?.edge ?? Theme.of(context).dividerColor,
              ),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(top: workspaceTopInset),
                      child: Stack(
                        children: [
                          // Main content (no app bar)
                          routedContent,
                          // Invisible resize handle on left edge (12px wide).
                          // Only the expanded sidebar is resizable; the rail
                          // has one fixed width.
                          if (isDrawerVisible && !isRailChrome)
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
                                    if (workspaceState != null) {
                                      workspaceManager
                                          .startWorkspaceDrawerResize(
                                              workspaceState.id);
                                    } else {
                                      navigationService.startResizing();
                                    }
                                  },
                                  onHorizontalDragUpdate: (details) {
                                    if (workspaceState != null) {
                                      workspaceManager
                                          .updateWorkspaceDrawerWidth(
                                        workspaceState.id,
                                        workspaceState.drawerWidth +
                                            details.delta.dx,
                                      );
                                    } else {
                                      navigationService.updateDrawerWidth(
                                        navigationService.drawerWidth +
                                            details.delta.dx,
                                      );
                                    }
                                  },
                                  onHorizontalDragEnd: (details) {
                                    if (workspaceState != null) {
                                      workspaceManager
                                          .stopWorkspaceDrawerResize(
                                              workspaceState.id);
                                    } else {
                                      navigationService.stopResizing();
                                    }
                                  },
                                  child: Container(
                                    color: Colors.transparent,
                                  ),
                                ),
                              ),
                            ),
                          // Small toggle button (bottom-left, only when drawer is hidden)
                          if (!isDrawerVisible && !isPinnedWorkspace)
                            Positioned(
                              left: 8,
                              bottom: 8,
                              child: Material(
                                elevation: 4,
                                borderRadius: BorderRadius.circular(20),
                                child: InkWell(
                                  onTap: () {
                                    if (workspaceState != null) {
                                      workspaceManager.showWorkspaceDrawer(
                                          workspaceState.id);
                                    } else {
                                      navigationService.showDrawer();
                                    }
                                  },
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
      // Compact shell (<900): MainLayout is the single owner of application
      // chrome. Feature pages contribute only title/context and their local
      // scope surface; they never mount a second Scaffold or AppBar.
      final compactChrome = workspaceChrome ??
          WorkspaceChromeTheme.resolve(
            palette: context.watch<AppearanceService>().sidebarPalette,
            brightness: Theme.of(context).brightness,
          );
      return Scaffold(
        appBar: AppBar(
          key: const ValueKey('main-layout-compact-header'),
          automaticallyImplyLeading: false,
          toolbarHeight: 56,
          leadingWidth: 56,
          titleSpacing: 0,
          leading: widget.onBackPressed != null
              ? IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: widget.onBackPressed,
                  tooltip: 'Volver',
                  color: compactChrome.foreground,
                )
              : isPinnedWorkspace
                  ? null
                  : Builder(
                      builder: (context) => IconButton(
                        key: const ValueKey('main-layout-mobile-menu'),
                        icon: const Icon(Icons.menu),
                        onPressed: () {
                          _compactDrawerToolsMode.value = false;
                          Scaffold.of(context).openDrawer();
                        },
                        tooltip: 'Abrir menú principal',
                        color: compactChrome.foreground,
                        style: IconButton.styleFrom(
                          minimumSize: const Size(48, 48),
                          side: BorderSide(color: compactChrome.edge),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ),
          title: _buildCompactTitle(context, compactChrome),
          backgroundColor: compactChrome.canvas,
          foregroundColor: compactChrome.foreground,
          // La barra de estado del sistema toma este mismo navy. Sin esto
          // Android la deja en su default claro y queda una franja blanca
          // pegada encima del header — ver `systemOverlayStyle` en
          // `WorkspaceChromeStyleData`.
          systemOverlayStyle: compactChrome.systemOverlayStyle,
          surfaceTintColor: Colors.transparent,
          shadowColor: Colors.transparent,
          elevation: 0,
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(1.0),
            child: Container(
              color: compactChrome.edge,
              height: 1.0,
            ),
          ),
          iconTheme: IconThemeData(
            color: compactChrome.foreground,
          ),
          actions: [
            ...?widget.compactHeader?.actions,
            _CompactShellActions(
              chrome: compactChrome,
              drawerToolsMode: _compactDrawerToolsMode,
            ),
          ],
        ),
        drawer: isPinnedWorkspace
            ? null
            : AppDrawer(
                toolsModeController: _compactDrawerToolsMode,
              ),
        drawerScrimColor:
            Theme.of(context).colorScheme.scrim.withValues(alpha: 0.36),
        body: routedContent,
      );
    }
  }
}

class _ThemeModeSelector extends StatelessWidget {
  const _ThemeModeSelector({
    required this.mode,
    required this.onChanged,
    required this.padding,
  });

  final ThemeMode mode;
  final ValueChanged<ThemeMode> onChanged;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: 'Tema de la aplicación',
      child: Padding(
        padding: padding,
        child: SizedBox(
          width: double.infinity,
          child: SegmentedButton<ThemeMode>(
            key: const ValueKey('theme-mode-selector'),
            segments: const <ButtonSegment<ThemeMode>>[
              ButtonSegment<ThemeMode>(
                value: ThemeMode.system,
                icon: Icon(Icons.brightness_auto_outlined, size: 17),
                label: Text(
                  'Sistema',
                  key: ValueKey('theme-mode-system'),
                ),
                tooltip: 'Seguir apariencia del sistema',
              ),
              ButtonSegment<ThemeMode>(
                value: ThemeMode.light,
                icon: Icon(Icons.light_mode_outlined, size: 17),
                label: Text(
                  'Claro',
                  key: ValueKey('theme-mode-light'),
                ),
                tooltip: 'Usar siempre modo claro',
              ),
              ButtonSegment<ThemeMode>(
                value: ThemeMode.dark,
                icon: Icon(Icons.dark_mode_outlined, size: 17),
                label: Text(
                  'Oscuro',
                  key: ValueKey('theme-mode-dark'),
                ),
                tooltip: 'Usar siempre modo oscuro',
              ),
            ],
            selected: <ThemeMode>{mode},
            showSelectedIcon: false,
            onSelectionChanged: (selection) {
              if (selection.isEmpty) return;
              onChanged(selection.single);
            },
          ),
        ),
      ),
    );
  }
}

class _CompactShellActions extends StatelessWidget {
  const _CompactShellActions({
    required this.chrome,
    required this.drawerToolsMode,
  });

  final WorkspaceChromeStyleData chrome;
  final ValueNotifier<bool> drawerToolsMode;

  Future<void> _showWorkspaceTasks(BuildContext context) async {
    final manager = context.read<WorkspaceManager>();
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        return ListenableBuilder(
          listenable: manager,
          builder: (context, _) {
            final workspaces = manager.workspaces;
            final activeId = manager.activeWorkspace?.id;
            return ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.7,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 4, 18, 10),
                    child: Text(
                      'Tareas abiertas',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                  ),
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      padding: const EdgeInsets.only(bottom: 16),
                      itemCount: workspaces.length,
                      itemBuilder: (context, index) {
                        final workspace = workspaces[index];
                        final selected = workspace.id == activeId;
                        return ListTile(
                          key: ValueKey('compact-workspace-${workspace.id}'),
                          minTileHeight: 56,
                          selected: selected,
                          leading: Icon(
                            selected
                                ? Icons.check_circle_rounded
                                : Icons.radio_button_unchecked_rounded,
                          ),
                          title: Text(
                            workspace.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle:
                              workspace.currentRoute == workspace.initialRoute
                                  ? null
                                  : Text(
                                      getRouteTitle(workspace.currentRoute),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                          trailing: workspaces.length <= 1
                              ? null
                              : IconButton(
                                  onPressed: () async {
                                    final closed =
                                        await manager.requestCloseWorkspaceById(
                                            workspace.id);
                                    if (closed &&
                                        sheetContext.mounted &&
                                        manager.workspaces.length <= 1) {
                                      Navigator.pop(sheetContext);
                                    }
                                  },
                                  icon:
                                      const Icon(Icons.close_rounded, size: 20),
                                  tooltip: 'Cerrar ${workspace.title}',
                                ),
                          onTap: () {
                            manager.switchToWorkspaceById(workspace.id);
                            Navigator.pop(sheetContext);
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _showActivity(BuildContext context) async {
    final toolbar = context.read<RightToolbarService>();
    final notificationCount =
        NotificationService().unreadNotificationsCount.value;
    final messageCount = context.read<ChatProvider>().totalUnreadCount;
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) {
        Widget row({
          required ToolbarTool tool,
          required String title,
          required String subtitle,
          required IconData icon,
          required int count,
        }) {
          return ListTile(
            key: ValueKey('compact-activity-${tool.name}'),
            minTileHeight: 58,
            leading: Icon(icon),
            title: Text(title),
            subtitle: Text(subtitle),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (count > 0) _CompactCountBadge(count: count),
                const SizedBox(width: 6),
                const Icon(Icons.chevron_right_rounded),
              ],
            ),
            onTap: () {
              Navigator.pop(sheetContext);
              toolbar.openTool(tool);
            },
          );
        }

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 4, 18, 10),
              child: Text(
                'Actividad',
                style: Theme.of(sheetContext)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
            row(
              tool: ToolbarTool.notifications,
              title: 'Notificaciones',
              subtitle: notificationCount == 0
                  ? 'No hay novedades pendientes'
                  : '$notificationCount sin revisar',
              icon: Icons.notifications_outlined,
              count: notificationCount,
            ),
            row(
              tool: ToolbarTool.messages,
              title: 'Mensajería',
              subtitle: messageCount == 0
                  ? 'No hay conversaciones pendientes'
                  : '$messageCount sin leer',
              icon: Icons.chat_bubble_outline,
              count: messageCount,
            ),
            ListTile(
              key: const ValueKey('compact-activity-open-tools'),
              minTileHeight: 58,
              leading: const Icon(Icons.grid_view_rounded),
              title: const Text('Todas las herramientas'),
              subtitle: const Text('Archivos, gastos, tareas y utilidades'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () {
                Navigator.pop(sheetContext);
                drawerToolsMode.value = true;
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!context.mounted) return;
                  Scaffold.maybeOf(context)?.openDrawer();
                });
              },
            ),
            const SizedBox(height: 12),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final manager = context.watch<WorkspaceManager>();
    final chatCount = context.watch<ChatProvider>().totalUnreadCount;
    return ValueListenableBuilder<int>(
      valueListenable: NotificationService().unreadNotificationsCount,
      builder: (context, notificationCount, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (manager.workspaces.length >= 2)
              _CompactHeaderAction(
                key: const ValueKey('main-layout-mobile-workspaces'),
                chrome: chrome,
                icon: Icons.layers_outlined,
                count: manager.workspaces.length,
                tooltip: 'Tareas abiertas',
                onPressed: () => _showWorkspaceTasks(context),
              ),
            _CompactHeaderAction(
              key: const ValueKey('main-layout-mobile-activity'),
              chrome: chrome,
              icon: Icons.notifications_none_rounded,
              count: chatCount + notificationCount,
              tooltip: 'Actividad',
              onPressed: () => _showActivity(context),
            ),
            const SizedBox(width: 4),
          ],
        );
      },
    );
  }
}

class _CompactHeaderAction extends StatelessWidget {
  const _CompactHeaderAction({
    required this.chrome,
    required this.icon,
    required this.count,
    required this.tooltip,
    required this.onPressed,
    super.key,
  });

  final WorkspaceChromeStyleData chrome;
  final IconData icon;
  final int count;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 48,
      height: 48,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: IconButton(
              tooltip: tooltip,
              onPressed: onPressed,
              color: chrome.foreground,
              icon: Icon(icon, size: 21),
            ),
          ),
          if (count > 0)
            Positioned(
              right: 3,
              top: 3,
              child: IgnorePointer(
                child: _CompactCountBadge(
                  count: count,
                  background: chrome.attention,
                  foreground: chrome.onAttention,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _CompactCountBadge extends StatelessWidget {
  const _CompactCountBadge({
    required this.count,
    this.background,
    this.foreground,
  });

  final int count;
  final Color? background;
  final Color? foreground;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      constraints: const BoxConstraints(minWidth: 18, minHeight: 16),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: background ?? theme.colorScheme.primary,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        count > 99 ? '99+' : '$count',
        style: theme.textTheme.labelSmall?.copyWith(
          color: foreground ?? theme.colorScheme.onPrimary,
          fontWeight: FontWeight.w800,
          fontSize: 9.5,
        ),
      ),
    );
  }
}

Future<void> _handleLogout(BuildContext context) async {
  final authService = context.read<AuthService>();
  final router = GoRouter.of(context);
  final messenger = ScaffoldMessenger.maybeOf(context);

  try {
    await authService.signOut();
    router.go('/login');
  } catch (error) {
    messenger?.showSnackBar(
      SnackBar(content: Text('No se pudo cerrar sesión: $error')),
    );
  }
}

class AppSidebar extends StatefulWidget {
  const AppSidebar({
    required this.overlayContext,
    super.key,
  });

  /// Context above the chromatic sidebar [Theme].
  ///
  /// Flutter captures every [InheritedTheme] between an overlay trigger and
  /// the target navigator. Sidebar dialogs therefore open from this root
  /// content context while anchor geometry still comes from the real button.
  final BuildContext overlayContext;

  @override
  State<AppSidebar> createState() => _AppSidebarState();
}

class _AppSidebarState extends State<AppSidebar> {
  // Local state for last location to detect changes
  String? _lastLocation;

  /// Renders one destination of the shared model as an expanded-sidebar item.
  Widget _buildModuleWidget(
    AppDestinationModule module,
    String currentLocation,
    String? expandedSection,
    NavigationService navService,
  ) {
    return ExpandableMenuItem(
      key: ValueKey(module.key),
      icon: module.icon,
      activeIcon: module.activeIcon,
      title: module.title,
      currentLocation: currentLocation,
      subItems: module.items,
      isExpanded: expandedSection == module.key,
      isSingleItem: module.isSingleItem,
      enabled: module.enabled,
      badgeCount: module.badgeCount,
      subItemBadgeCounts: module.subItemBadgeCounts,
      onExpansionChanged: (expand) =>
          _handleExpansionChange(module.key, expand, navService),
      onBadgeTap: module.resolvedBadgeRoute == null
          ? null
          : () => context.go(module.resolvedBadgeRoute!),
      onNavigate: module.resolveRoute == null
          ? null
          : (route) => context.go(module.resolveRoute!(route)),
    );
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
        final currentRoute = routerState.uri.toString();
        final currentPath = routerState.uri.path;
        if (currentRoute != _lastLocation) {
          _lastLocation = currentRoute;

          // Update workspace tab title based on current route
          final workspaceManager = context.read<WorkspaceManager>();
          final scopedWorkspace = _maybeWorkspaceOf(context);
          if (scopedWorkspace != null) {
            final fallbackRoute = workspaceManager.handleWorkspaceRouteChange(
              scopedWorkspace.id,
              currentRoute,
            );
            if (fallbackRoute != null && fallbackRoute != currentRoute) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;
                router.go(fallbackRoute);
              });
            }
          } else {
            workspaceManager.updateActiveWorkspaceRoute(currentRoute);
          }

          final matchingSection = _resolveSectionForPath(currentPath);
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
    if (_matchesLocation(location, _taxReportsMenuItems)) {
      return _taxReportsSectionKey;
    }
    if (_matchesLocation(location, _chatMenuItems)) {
      return _chatSectionKey;
    }
    if (_matchesLocation(location, _toolsMenuItems)) {
      return _toolsSectionKey;
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
    if (_matchesLocation(location, _storageMenuItems)) {
      return _storageSectionKey;
    }
    if (_matchesLocation(location, _websiteMenuItems)) {
      return _websiteSectionKey;
    }
    return null;
  }

  bool _matchesLocation(String location, List<MenuSubItem> items) {
    final locationPath = _routePath(location);
    for (final item in items) {
      final routePath = _routePath(item.route);
      if (locationPath == routePath || locationPath.startsWith('$routePath/')) {
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
      color: Colors.transparent,
      child: Column(
        children: [
          // Company Header
          Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 11),
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
                        SizedBox(
                          width: 86,
                          height: 25,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: _buildAdaptiveCompanyLogo(
                              context: context,
                              appearanceService: appearanceService,
                              fallbackBuilder: (context) => _buildDefaultHeader(
                                context,
                                theme,
                                appearanceService,
                              ),
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
                final orderedModules = resolveOrderedAppModules(context);
                final isReorderMode = navigationService.isReorderMode;

                if (isReorderMode) {
                  // Reorder mode: Show ReorderableListView
                  return ReorderableListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    buildDefaultDragHandles: false,
                    itemCount: orderedModules.length +
                        2, // +2 for dashboard and divider
                    onReorder: (oldIndex, newIndex) {
                      // Adjust for dashboard item (index 0) and divider (index 1)
                      if (oldIndex < 2 || newIndex < 2) return;
                      _reorderVisibleModules(
                        navigationService,
                        [for (final module in orderedModules) module.key],
                        oldIndex - 2,
                        newIndex - 2,
                      );
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
                      final module = orderedModules[moduleIndex];
                      return ReorderableDragStartListener(
                        key: ValueKey(module.key),
                        index: index,
                        child: Container(
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surface,
                            border: Border.all(
                              color: theme.colorScheme.primary
                                  .withValues(alpha: 0.3),
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
                                  module,
                                  currentLocation,
                                  navigationService.expandedSection,
                                  navigationService,
                                ),
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
                  padding: const EdgeInsets.symmetric(vertical: 5),
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
                    ...orderedModules.map((module) => _buildModuleWidget(
                        module,
                        currentLocation,
                        navigationService.expandedSection,
                        navigationService)),

                    const SizedBox(height: 8),
                    _buildSectionDivider(context),

                    // Fixed destinations shared with rail and drawer.
                    AnimatedBuilder(
                      animation: Listenable.merge([
                        NotificationService().onlineOrderAlertCount,
                        MailAccountManager.instance,
                      ]),
                      builder: (context, _) {
                        return Column(
                          children: [
                            for (final module in resolveFixedAppModules(
                              context,
                              currentLocation: currentLocation,
                            ))
                              _buildModuleWidget(
                                module,
                                currentLocation,
                                navigationService.expandedSection,
                                navigationService,
                              ),
                          ],
                        );
                      },
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
                CurrentUserProfileTile(
                  selected: currentLocation == '/profile',
                  compact: true,
                  onTap: () => CurrentUserProfileNavigation.open(context),
                ),

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
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () => _handleLogout(context),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 9, vertical: 7),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.logout_outlined,
                              size: 16,
                              color: theme.colorScheme.onSurface
                                  .withValues(alpha: 0.7),
                            ),
                            const SizedBox(width: 9),
                            Expanded(
                              child: Text(
                                'Cerrar Sesión',
                                style: theme.textTheme.bodySmall?.copyWith(
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
                      padding: const EdgeInsets.fromLTRB(6, 4, 6, 6),
                      child: Row(
                        children: [
                          // 3-dot menu button
                          IconButton(
                            icon: Icon(
                              Icons.more_horiz,
                              size: 18,
                              color: theme.colorScheme.onSurface
                                  .withValues(alpha: 0.6),
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
                                anchorContext: context,
                                overlayContext: widget.overlayContext,
                                navigationService: navigationService,
                              );
                            },
                          ),
                          const Spacer(),
                          // Compact-to-rail button (middle chrome state)
                          IconButton(
                            icon: const Icon(
                              Icons.keyboard_double_arrow_left,
                              size: 18,
                            ),
                            iconSize: 18,
                            padding: const EdgeInsets.all(8),
                            constraints: const BoxConstraints(
                              minWidth: 32,
                              minHeight: 32,
                            ),
                            tooltip: 'Compactar menú',
                            onPressed: () {
                              final scopedWorkspace =
                                  _maybeWorkspaceOf(context);
                              if (scopedWorkspace != null) {
                                context
                                    .read<WorkspaceManager>()
                                    .setWorkspaceChromeMode(
                                      scopedWorkspace.id,
                                      NavigationChromeMode.rail,
                                    );
                              } else {
                                navigationService.setPreferredChromeMode(
                                  NavigationChromeMode.rail,
                                );
                              }
                            },
                            style: IconButton.styleFrom(
                              backgroundColor: theme.colorScheme.surface,
                              foregroundColor: theme.colorScheme.onSurface
                                  .withValues(alpha: 0.6),
                            ),
                          ),
                          const SizedBox(width: 4),
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
                              final scopedWorkspace =
                                  _maybeWorkspaceOf(context);
                              if (scopedWorkspace != null) {
                                context
                                    .read<WorkspaceManager>()
                                    .hideWorkspaceDrawer(scopedWorkspace.id);
                              } else {
                                navigationService.hideDrawer();
                              }
                            },
                            style: IconButton.styleFrom(
                              backgroundColor: theme.colorScheme.surface,
                              foregroundColor: theme.colorScheme.onSurface
                                  .withValues(alpha: 0.6),
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
    int badgeCount = 0,
  }) {
    final isSelected = currentLocation.startsWith(route);
    final theme = Theme.of(context);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          mouseCursor:
              enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
          borderRadius: BorderRadius.circular(6),
          hoverColor: theme.colorScheme.primary.withValues(alpha: 0.08),
          focusColor: theme.colorScheme.primary.withValues(alpha: 0.12),
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
            constraints: const BoxConstraints(minHeight: 30),
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              color: isSelected
                  ? theme.primaryColor.withValues(alpha: 0.13)
                  : Colors.transparent,
              border: isSelected
                  ? Border(
                      left: BorderSide(
                        color: theme.colorScheme.primary,
                        width: 2,
                      ),
                    )
                  : null,
            ),
            child: Row(
              children: [
                Icon(
                  isSelected ? activeIcon : icon,
                  size: 16,
                  color: enabled
                      ? (isSelected
                          ? theme.primaryColor
                          : theme.colorScheme.onSurface.withValues(alpha: 0.7))
                      : theme.disabledColor,
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.bodySmall?.copyWith(
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
                if (badgeCount > 0)
                  Container(
                    margin: const EdgeInsets.only(left: 8),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      badgeCount > 99 ? '99+' : '$badgeCount',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onPrimary,
                        fontWeight: FontWeight.bold,
                        fontSize: 10,
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
                height: 1,
              ),
            ),
            Text(
              'ERP Sistema',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                height: 1,
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

/// Compact icon rail: the middle state of the tri-state desktop chrome.
///
/// It consumes exactly the same destination model as the expanded sidebar and
/// the mobile drawer ([resolveOrderedAppModules] / [resolveFixedAppModules]).
/// Multi-destination modules open an anchored flyout; every trigger keeps a
/// tooltip, a semantic label and an explicit selected state.
class AppNavigationRail extends StatelessWidget {
  const AppNavigationRail({super.key});

  static const double railWidth = WorkspaceShellScope.navigationRailWidth;

  @override
  Widget build(BuildContext context) {
    final chrome = WorkspaceChromeStyle.maybeOf(context) ??
        WorkspaceChromeStyleData.vinabike;
    String currentLocation = '';
    try {
      if (GoRouter.maybeOf(context) != null) {
        currentLocation = GoRouterState.of(context).uri.path;
      }
    } catch (_) {
      currentLocation = '';
    }

    final orderedModules = resolveOrderedAppModules(context);
    final profile = context.watch<CurrentUserProfileService>().profile;
    final initials = () {
      final name = profile?.displayName.trim() ?? '';
      if (name.isEmpty) return 'V';
      final parts =
          name.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
      if (parts.length == 1) return parts.first[0].toUpperCase();
      return (parts.first[0] + parts[1][0]).toUpperCase();
    }();

    return AnimatedBuilder(
      animation: Listenable.merge([
        NotificationService().onlineOrderAlertCount,
        MailAccountManager.instance,
      ]),
      builder: (context, _) {
        final fixedModules = resolveFixedAppModules(
          context,
          currentLocation: currentLocation,
        );

        return Container(
          width: railWidth,
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: <Color>[chrome.canvas, chrome.raised],
            ),
          ),
          child: Column(
            children: [
              Tooltip(
                message: 'Inicio',
                child: Semantics(
                  button: true,
                  label: 'Inicio',
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => context.go('/dashboard'),
                      mouseCursor: SystemMouseCursors.click,
                      borderRadius: BorderRadius.circular(9),
                      hoverColor: chrome.foreground.withValues(alpha: 0.10),
                      focusColor: chrome.foreground.withValues(alpha: 0.14),
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: chrome.accent,
                          borderRadius: BorderRadius.circular(9),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          'V',
                          style:
                              Theme.of(context).textTheme.titleSmall?.copyWith(
                                    color: chrome.onAccent,
                                    fontWeight: FontWeight.w800,
                                  ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 9),
              Container(width: 24, height: 1, color: chrome.edge),
              const SizedBox(height: 9),
              Expanded(
                child: ListView(
                  padding: EdgeInsets.zero,
                  children: [
                    for (final module in [...orderedModules, ...fixedModules])
                      _RailModuleDestination(
                        key: ValueKey('rail-${module.key}'),
                        module: module,
                        currentLocation: currentLocation,
                      ),
                  ],
                ),
              ),
              Container(width: 24, height: 1, color: chrome.edge),
              const SizedBox(height: 8),
              _RailDestination(
                title: 'Configuración',
                icon: Icons.settings_outlined,
                activeIcon: Icons.settings,
                selected: currentLocation.startsWith('/settings'),
                onTap: () => context.go('/settings'),
              ),
              _RailDestination(
                title: 'Cerrar sesión',
                icon: Icons.logout_outlined,
                activeIcon: Icons.logout_outlined,
                selected: false,
                onTap: () => _handleLogout(context),
              ),
              _RailDestination(
                title: 'Expandir menú',
                icon: Icons.keyboard_double_arrow_right,
                activeIcon: Icons.keyboard_double_arrow_right,
                selected: false,
                onTap: () => _expandChrome(context),
              ),
              _RailDestination(
                title: 'Ocultar menú',
                icon: Icons.chevron_left,
                activeIcon: Icons.chevron_left,
                selected: false,
                onTap: () => _hideChrome(context),
              ),
              const SizedBox(height: 6),
              Tooltip(
                message: 'Mi perfil',
                child: Semantics(
                  button: true,
                  label: 'Mi perfil',
                  child: Material(
                    color: Colors.transparent,
                    shape: const CircleBorder(),
                    child: InkWell(
                      onTap: () => CurrentUserProfileNavigation.open(context),
                      mouseCursor: SystemMouseCursors.click,
                      customBorder: const CircleBorder(),
                      hoverColor: chrome.foreground.withValues(alpha: 0.10),
                      focusColor: chrome.foreground.withValues(alpha: 0.14),
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: chrome.raised,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: chrome.accent.withValues(alpha: 0.25),
                          ),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          initials,
                          style:
                              Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: chrome.accent,
                                    fontWeight: FontWeight.w700,
                                  ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _expandChrome(BuildContext context) {
    final scopedWorkspace = _maybeWorkspaceOf(context);
    if (scopedWorkspace != null) {
      context.read<WorkspaceManager>().setWorkspaceChromeMode(
            scopedWorkspace.id,
            NavigationChromeMode.expanded,
          );
    } else {
      context
          .read<NavigationService>()
          .setPreferredChromeMode(NavigationChromeMode.expanded);
    }
  }

  void _hideChrome(BuildContext context) {
    final scopedWorkspace = _maybeWorkspaceOf(context);
    if (scopedWorkspace != null) {
      context.read<WorkspaceManager>().hideWorkspaceDrawer(scopedWorkspace.id);
    } else {
      context.read<NavigationService>().hideDrawer();
    }
  }
}

/// One rail module trigger. Single-destination modules navigate directly;
/// multi-destination modules open their children in an anchored flyout.
class _RailModuleDestination extends StatefulWidget {
  const _RailModuleDestination({
    super.key,
    required this.module,
    required this.currentLocation,
  });

  final AppDestinationModule module;
  final String currentLocation;

  @override
  State<_RailModuleDestination> createState() => _RailModuleDestinationState();
}

class _RailModuleDestinationState extends State<_RailModuleDestination> {
  final MenuController _menuController = MenuController();

  void _navigate(String route) {
    final resolved = widget.module.resolveRoute?.call(route) ?? route;
    context.go(resolved);
  }

  @override
  Widget build(BuildContext context) {
    final module = widget.module;
    final selected = module.matchesLocation(widget.currentLocation);
    final navigableItems =
        module.items.where((item) => !item.isHeader).toList(growable: false);
    final isDirect = module.isSingleItem || navigableItems.length == 1;

    if (isDirect) {
      return _RailDestination(
        title: module.title,
        icon: module.icon,
        activeIcon: module.activeIcon,
        selected: selected,
        enabled: module.enabled,
        badgeCount: module.badgeCount,
        onTap: navigableItems.isEmpty
            ? null
            : () => _navigate(navigableItems.first.route),
      );
    }

    final theme = Theme.of(context);
    return MenuAnchor(
      controller: _menuController,
      consumeOutsideTap: true,
      style: const MenuStyle(
        minimumSize: WidgetStatePropertyAll(Size(230, 0)),
      ),
      menuChildren: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
          child: Text(
            module.title,
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        // The badge's durable action, shared with sidebar and drawer through
        // the destination model.
        if (module.resolvedBadgeRoute != null)
          MenuItemButton(
            leadingIcon:
                const Icon(Icons.notifications_active_outlined, size: 18),
            onPressed: () => context.go(module.resolvedBadgeRoute!),
            child: Text(
              'Ver ${module.badgeCount} '
              '${module.badgeCount == 1 ? 'pendiente' : 'pendientes'}',
            ),
          ),
        for (final item in module.items)
          if (item.isHeader)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
              child: Text(
                item.title,
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            )
          else
            MenuItemButton(
              leadingIcon: Icon(item.icon, size: 18),
              trailingIcon: (module.subItemBadgeCounts[item.route] ?? 0) > 0
                  ? _RailBadge(
                      count: module.subItemBadgeCounts[item.route]!,
                    )
                  : null,
              onPressed: () => _navigate(item.route),
              child: Text(item.title),
            ),
      ],
      builder: (context, controller, _) {
        return _RailDestination(
          title: module.title,
          icon: module.icon,
          activeIcon: module.activeIcon,
          selected: selected,
          enabled: module.enabled,
          badgeCount: module.badgeCount,
          expanded: controller.isOpen,
          onTap: () {
            if (controller.isOpen) {
              controller.close();
            } else {
              controller.open();
            }
          },
        );
      },
    );
  }
}

class _RailDestination extends StatelessWidget {
  const _RailDestination({
    required this.title,
    required this.icon,
    required this.activeIcon,
    required this.selected,
    required this.onTap,
    this.enabled = true,
    this.badgeCount = 0,
    this.expanded,
  });

  final String title;
  final IconData icon;
  final IconData activeIcon;
  final bool selected;
  final VoidCallback? onTap;
  final bool enabled;
  final int badgeCount;

  /// Whether this trigger's flyout is open (null when it has none).
  final bool? expanded;

  @override
  Widget build(BuildContext context) {
    final chrome = WorkspaceChromeStyle.maybeOf(context) ??
        WorkspaceChromeStyleData.vinabike;
    final iconColor = !enabled
        ? chrome.mutedForeground.withValues(alpha: 0.45)
        : selected
            ? chrome.accent
            : chrome.mutedForeground;

    return Tooltip(
      message: title,
      waitDuration: const Duration(milliseconds: 350),
      child: Semantics(
        button: true,
        selected: selected,
        expanded: expanded,
        label: title + (badgeCount > 0 ? ', $badgeCount pendientes' : ''),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: enabled ? onTap : null,
            canRequestFocus: enabled && onTap != null,
            mouseCursor:
                enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
            hoverColor: chrome.foreground.withValues(alpha: 0.08),
            focusColor: chrome.foreground.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: AppNavigationRail.railWidth,
              height: 40,
              child: Center(
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: selected ? chrome.raised : Colors.transparent,
                        borderRadius: BorderRadius.circular(7),
                        border: Border.all(
                          color: selected ? chrome.accent : chrome.edge,
                        ),
                        boxShadow: selected
                            ? <BoxShadow>[
                                BoxShadow(
                                  color: chrome.accent.withValues(alpha: 0.10),
                                  spreadRadius: 3,
                                  blurRadius: 0,
                                ),
                              ]
                            : null,
                      ),
                      alignment: Alignment.center,
                      child: Icon(selected ? activeIcon : icon,
                          size: 17, color: iconColor),
                    ),
                    if (badgeCount > 0)
                      Positioned(
                        top: -3,
                        right: -3,
                        child: Container(
                          width: 9,
                          height: 9,
                          decoration: BoxDecoration(
                            color: chrome.attention,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: chrome.canvas,
                              width: 1.5,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RailBadge extends StatelessWidget {
  const _RailBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      constraints: const BoxConstraints(minWidth: 16, minHeight: 14),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: theme.colorScheme.primary,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        count > 99 ? '99+' : '$count',
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onPrimary,
          fontWeight: FontWeight.w800,
          fontSize: 9.5,
        ),
      ),
    );
  }
}

/// Pliega una cadena para comparar en el buscador del drawer: minúsculas y sin
/// tildes.
///
/// **Causa del defecto:** el filtro comparaba con `toLowerCase()` a secas y en
/// un teléfono nadie teclea la tilde. `Nomina` no encontraba `Nóminas` y el
/// drawer contestaba «No encontramos módulos o páginas», es decir, afirmaba que
/// el módulo no existe. Se pliegan **los dos lados** de la comparación, así que
/// `Nomina`, `nómina` y `NÓMINA` llegan al mismo resultado.
///
/// Vive acá, junto a la navegación compartida, y no en un util de negocio: la
/// tabla es la misma que ya usan los buscadores del ERP
/// (`normalizeBikeFinderSearch`, catálogo público), pero el drawer no puede
/// depender de un módulo para saber buscar.
String _foldForNavigationSearch(String value) {
  return value
      .toLowerCase()
      .replaceAll('á', 'a')
      .replaceAll('é', 'e')
      .replaceAll('í', 'i')
      .replaceAll('ó', 'o')
      .replaceAll('ú', 'u')
      .replaceAll('ü', 'u')
      .replaceAll('ñ', 'n');
}

class AppDrawer extends StatefulWidget {
  const AppDrawer({
    super.key,
    this.toolsModeController,
  });

  final ValueNotifier<bool>? toolsModeController;

  @override
  State<AppDrawer> createState() => _AppDrawerState();
}

enum _AppDrawerMode { navigation, tools }

class _AppDrawerState extends State<AppDrawer> {
  String? _expandedSection;
  _AppDrawerMode _mode = _AppDrawerMode.navigation;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _mode = widget.toolsModeController?.value == true
        ? _AppDrawerMode.tools
        : _AppDrawerMode.navigation;
    widget.toolsModeController?.addListener(_syncExternalMode);
  }

  @override
  void didUpdateWidget(covariant AppDrawer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.toolsModeController == widget.toolsModeController) return;
    oldWidget.toolsModeController?.removeListener(_syncExternalMode);
    widget.toolsModeController?.addListener(_syncExternalMode);
    _syncExternalMode();
  }

  @override
  void dispose() {
    widget.toolsModeController?.removeListener(_syncExternalMode);
    _searchController.dispose();
    super.dispose();
  }

  void _syncExternalMode() {
    final nextMode = widget.toolsModeController?.value == true
        ? _AppDrawerMode.tools
        : _AppDrawerMode.navigation;
    if (!mounted || nextMode == _mode) return;
    setState(() => _mode = nextMode);
  }

  void _selectMode(_AppDrawerMode mode) {
    final controller = widget.toolsModeController;
    final usesTools = mode == _AppDrawerMode.tools;
    if (controller != null && controller.value != usesTools) {
      controller.value = usesTools;
      return;
    }
    if (_mode != mode) setState(() => _mode = mode);
  }

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
    // Phone and tablet use one routed surface instead of desktop workspaces.
    // If small screen, use standard navigation instead of workspace tabs
    final isSmallScreen = ResponsiveViewport.usesCompactShell(context);

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
  void _showReorderSheet(BuildContext overlayContext) {
    final navigationService = overlayContext.read<NavigationService>();
    final canSeeHr = _visibleHrMenuItems(
      overlayContext.read<CurrentUserProfileService>(),
    ).isNotEmpty;

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
      context: overlayContext,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Theme.of(overlayContext).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            // Get a mutable copy of the order
            final moduleOrder = navigationService.moduleOrder
                .where((moduleKey) => moduleKey != 'hr' || canSeeHr)
                .toList(growable: false);

            return DraggableScrollableSheet(
              key: const ValueKey('mobile-reorder-sheet'),
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
                          _reorderVisibleModules(
                            navigationService,
                            moduleOrder,
                            oldIndex,
                            newIndex,
                          );
                          setSheetState(() {
                            // NavigationService updates synchronously. Rebuild
                            // this sheet from its authoritative order.
                          });
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

  Widget _buildCompactDrawerHeader(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      key: const ValueKey('mobile-drawer-identity'),
      padding: const EdgeInsets.fromLTRB(4, 4, 6, 4),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: theme.colorScheme.outlineVariant,
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: CurrentUserProfileTile(
              compact: true,
              onTap: () {
                Navigator.pop(context);
                CurrentUserProfileNavigation.open(context);
              },
            ),
          ),
          IconButton(
            key: const ValueKey('mobile-drawer-close'),
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close_rounded),
            tooltip: 'Cerrar menú',
            style: IconButton.styleFrom(
              minimumSize: const Size(48, 48),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDrawerModeSwitch(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      key: const ValueKey('mobile-drawer-mode-switch'),
      height: 56,
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 6),
      // The border also consumes layout space. Three vertical pixels keep the
      // visual control at 56 while preserving a real 48px target per mode.
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          Expanded(
            child: _buildDrawerModeButton(
              context,
              mode: _AppDrawerMode.navigation,
              label: 'Navegación',
            ),
          ),
          Expanded(
            child: _buildDrawerModeButton(
              context,
              mode: _AppDrawerMode.tools,
              label: 'Herramientas',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDrawerModeButton(
    BuildContext context, {
    required _AppDrawerMode mode,
    required String label,
  }) {
    final theme = Theme.of(context);
    final selected = _mode == mode;
    return Semantics(
      button: true,
      selected: selected,
      label: 'Modo $label',
      child: InkWell(
        key: ValueKey('mobile-drawer-mode-${mode.name}'),
        onTap: () => _selectMode(mode),
        borderRadius: BorderRadius.circular(6),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected
                ? theme.colorScheme.primaryContainer
                : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            label,
            style: theme.textTheme.labelLarge?.copyWith(
              color: selected
                  ? theme.colorScheme.onPrimaryContainer
                  : theme.colorScheme.onSurfaceVariant,
              fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCompactNavigationSearch(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 2, 12, 8),
      child: SizedBox(
        height: 48,
        child: TextField(
          key: const ValueKey('mobile-drawer-search'),
          controller: _searchController,
          textInputAction: TextInputAction.search,
          style: theme.textTheme.bodyMedium,
          decoration: InputDecoration(
            hintText: 'Buscar módulo o página',
            prefixIcon: const Icon(Icons.search_rounded, size: 20),
            suffixIcon: _searchQuery.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Limpiar búsqueda',
                    onPressed: () {
                      _searchController.clear();
                      setState(() => _searchQuery = '');
                    },
                    icon: const Icon(Icons.close_rounded, size: 18),
                  ),
            contentPadding: const EdgeInsets.symmetric(vertical: 12),
          ),
          onChanged: (value) => setState(() => _searchQuery = value.trim()),
        ),
      ),
    );
  }

  /// Resultados del buscador del drawer.
  ///
  /// **La tinta va atada al chrome, explícitamente.** Estos `ListTile` no
  /// declaraban color y salían pintados con el `onSurface` del tema **claro**
  /// (`#10243A`) sobre el navy del drawer: medido en la app, 1,03:1 de
  /// contraste — invisible. Los iconos sí se veían, y por eso parecía que el
  /// buscador no encontraba nada cuando en realidad sí filtraba.
  ///
  /// Heredar del `Theme` no alcanzó: el drawer ya está envuelto en
  /// `WorkspaceChromeTheme.sidebarTheme` y aun así la tinta llegaba del tema de
  /// la app. Mientras esa fuga no se explique, lo que va sobre el navy se dice
  /// en el sitio donde se pinta, que es lo que ya hacen la cabecera y las
  /// pestañas del propio drawer.
  Widget _buildCompactSearchResults(
    BuildContext context, {
    required List<AppDestinationModule> modules,
    required List<AppDestinationModule> fixedModules,
    required WorkspaceChromeStyleData chrome,
  }) {
    final normalizedQuery = _foldForNavigationSearch(_searchQuery);
    final results =
        <({String label, String module, String route, IconData icon})>[
      (
        label: 'Inicio',
        module: 'Inicio',
        route: '/dashboard',
        icon: Icons.dashboard_outlined,
      ),
      for (final module in [...modules, ...fixedModules])
        for (final item in module.items)
          if (!item.isHeader)
            (
              label: item.title,
              module: module.title,
              route: module.resolveRoute?.call(item.route) ?? item.route,
              icon: item.icon,
            ),
    ].where((result) {
      return _foldForNavigationSearch(result.label).contains(normalizedQuery) ||
          _foldForNavigationSearch(result.module).contains(normalizedQuery);
    }).toList(growable: false);

    if (results.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'No encontramos módulos o páginas para “$_searchQuery”.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: chrome.mutedForeground,
                ),
          ),
        ),
      );
    }

    return ListView.builder(
      key: const ValueKey('mobile-drawer-search-results'),
      padding: const EdgeInsets.only(bottom: 12),
      itemCount: results.length,
      itemBuilder: (context, index) {
        final result = results[index];
        return ListTile(
          minTileHeight: 52,
          iconColor: chrome.mutedForeground,
          textColor: chrome.foreground,
          leading: Icon(result.icon, size: 20, color: chrome.mutedForeground),
          title: Text(
            result.label,
            style: TextStyle(color: chrome.foreground),
          ),
          subtitle: Text(
            '${result.module} › ${result.label}',
            style: TextStyle(color: chrome.mutedForeground),
          ),
          trailing: Icon(
            Icons.chevron_right_rounded,
            size: 20,
            color: chrome.mutedForeground,
          ),
          onTap: () {
            Navigator.pop(context);
            _handleMobileNavigation(context, result.route, result.label);
          },
        );
      },
    );
  }

  Widget _buildCompactWorkspaceAccess(
    BuildContext context, {
    required WorkspaceChromeStyleData chrome,
  }) {
    return Consumer<WorkspaceManager>(
      builder: (context, manager, _) {
        final workspaces = manager.workspaces;
        final activeId = manager.activeWorkspace?.id;
        // Elegir entre espacios sólo tiene sentido cuando hay más de uno; la
        // acción de abrir uno nuevo vive aparte, siempre visible.
        if (workspaces.length <= 1) return const SizedBox.shrink();

        final browserStack = manager.unpinnedBrowserWorkspaces;
        final groupsBrowsers = browserStack.length > 1;
        final browserStackIds = groupsBrowsers
            ? browserStack.map((workspace) => workspace.id).toSet()
            : const <String>{};
        final workspaceChildren = <Widget>[];
        var insertedBrowserStack = false;
        for (final workspace in workspaces) {
          if (browserStackIds.contains(workspace.id)) {
            if (!insertedBrowserStack) {
              workspaceChildren.add(
                ExpansionTile(
                  key: const ValueKey('mobile-browser-workspace-group'),
                  minTileHeight: 48,
                  initiallyExpanded: browserStack.any(
                    (browser) => browser.id == activeId,
                  ),
                  leading: const Icon(Icons.tab_rounded, size: 20),
                  title: Text(
                    'Pestañas web · ${browserStack.length}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  children: [
                    for (final browser in browserStack)
                      _buildCompactWorkspaceTile(
                        context,
                        manager: manager,
                        workspace: browser,
                        activeId: activeId,
                        chrome: chrome,
                      ),
                  ],
                ),
              );
              insertedBrowserStack = true;
            }
            continue;
          }
          workspaceChildren.add(
            _buildCompactWorkspaceTile(
              context,
              manager: manager,
              workspace: workspace,
              activeId: activeId,
              chrome: chrome,
            ),
          );
        }

        return ExpansionTile(
          key: const ValueKey('mobile-workspace-selector'),
          minTileHeight: 48,
          leading: const Icon(Icons.layers_outlined, size: 20),
          title: Text(
            'Espacios de trabajo · ${workspaces.length}',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          children: workspaceChildren,
        );
      },
    );
  }

  Widget _buildCompactWorkspaceTile(
    BuildContext context, {
    required WorkspaceManager manager,
    required Workspace workspace,
    required String? activeId,
    required WorkspaceChromeStyleData chrome,
  }) {
    final theme = Theme.of(context);
    final selected = workspace.id == activeId;
    return ListTile(
      key: ValueKey('mobile-workspace-${workspace.id}'),
      minTileHeight: 48,
      selected: selected,
      // Congelar también la selección contra el chrome: el ListTile heredaba
      // el primaryContainer claro de la app.
      selectedColor: theme.colorScheme.onPrimaryContainer,
      selectedTileColor: theme.colorScheme.primaryContainer,
      iconColor: chrome.mutedForeground,
      textColor: chrome.foreground,
      leading: workspace.isBrowserWorkspace
          ? BrowserWorkspaceFavicon(
              key: ValueKey('mobile-workspace-favicon-${workspace.id}'),
              faviconUrl: workspace.browserFaviconUrl,
              size: 20,
              fallbackColor: chrome.mutedForeground,
            )
          : null,
      title: Text(
        workspace.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      onTap: () {
        manager.switchToWorkspaceById(workspace.id);
        Navigator.pop(context);
      },
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (workspace.isBrowserWorkspace)
            IconButton(
              key: ValueKey('mobile-workspace-pin-${workspace.id}'),
              onPressed: () {
                final index = manager.workspaces.indexWhere(
                  (candidate) => candidate.id == workspace.id,
                );
                if (index >= 0) manager.toggleWorkspacePinned(index);
              },
              icon: Icon(
                workspace.isPinned
                    ? Icons.push_pin_rounded
                    : Icons.push_pin_outlined,
                size: 18,
              ),
              tooltip: workspace.isPinned
                  ? 'Desfijar ${workspace.title}'
                  : 'Fijar ${workspace.title}',
            ),
          IconButton(
            key: ValueKey('mobile-workspace-close-${workspace.id}'),
            onPressed: () async {
              await manager.requestCloseWorkspaceById(workspace.id);
            },
            icon: const Icon(Icons.close_rounded, size: 18),
            tooltip: 'Cerrar ${workspace.title}',
          ),
        ],
      ),
    );
  }

  /// Abre un espacio de trabajo nuevo desde el shell compacto.
  ///
  /// Es el equivalente del «+» de la barra de pestañas de escritorio. Va
  /// siempre visible y fuera del selector: crear no es elegir entre los ya
  /// abiertos, y hasta el 2026-08-06 el compacto simplemente no tenía forma de
  /// abrir un segundo espacio.
  Widget _buildCompactNewWorkspaceAction(
    BuildContext context, {
    required WorkspaceChromeStyleData chrome,
  }) {
    return Consumer<WorkspaceManager>(
      builder: (context, manager, _) {
        final atLimit =
            manager.workspaces.length >= WorkspaceManager.maxWorkspaces;
        return ListTile(
          key: const ValueKey('mobile-workspace-new'),
          minTileHeight: 48,
          enabled: !atLimit,
          iconColor: chrome.mutedForeground,
          textColor: chrome.foreground,
          leading: const Icon(Icons.add_rounded, size: 20),
          title: Text(
            atLimit
                ? 'Máximo de espacios abiertos'
                : 'Nuevo espacio de trabajo',
            style: TextStyle(
              color: atLimit ? chrome.mutedForeground : chrome.foreground,
            ),
          ),
          onTap: atLimit
              ? null
              : () => _openCompactWorkspaceLauncher(context, manager),
        );
      },
    );
  }

  /// Elige el destino del espacio nuevo en una hoja inferior.
  ///
  /// O-05 de la guía de componentes: en compacto el catálogo se ofrece en una
  /// hoja, no en el popover anclado que usa el «+» de escritorio. El catálogo
  /// es el mismo (`workspaceLaunchOptions`), sólo cambia la presentación.
  Future<void> _openCompactWorkspaceLauncher(
    BuildContext context,
    WorkspaceManager manager,
  ) async {
    final navigator = Navigator.of(context);
    final chosen = await showModalBottomSheet<WorkspaceLaunchOption>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Text(
                'Abrir en un espacio nuevo',
                style: Theme.of(sheetContext).textTheme.titleMedium,
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final option in workspaceLaunchOptions)
                    ListTile(
                      key: ValueKey('mobile-workspace-launch-${option.route}'),
                      minTileHeight: 48,
                      leading: Icon(option.icon),
                      title: Text(option.title),
                      onTap: () =>
                          Navigator.of(sheetContext).pop<WorkspaceLaunchOption>(
                        option,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    if (chosen == null) return;
    manager.addWorkspace(title: chosen.title, initialRoute: chosen.route);
    // Cerrar el drawer deja a la vista el espacio recién abierto.
    if (navigator.canPop()) navigator.pop();
  }

  Widget _buildCompactToolsMode(
    BuildContext context, {
    required BuildContext overlayContext,
    required WorkspaceChromeStyleData chrome,
  }) {
    final toolbarService = context.watch<RightToolbarService>();
    final chatProvider = context.watch<ChatProvider>();
    final profileService = context.watch<CurrentUserProfileService?>();
    final canManageHr = profileService != null &&
        !profileService.isLoading &&
        profileService.loadIssue == null &&
        profileService.profile?.canManageUsers == true;
    final visibleTools = resolveVisibleToolbarTools(
      canManageHr: canManageHr,
      performanceEnabled: QueryPerformanceService.isEnabled,
      performancePinned: toolbarService.isGaugePinned,
    );

    return ValueListenableBuilder<int>(
      valueListenable: NotificationService().unreadNotificationsCount,
      builder: (context, notificationCount, _) {
        final widgets = <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
            child: Text(
              'Abre una herramienta en todo el espacio disponible. Al volver, '
              'tu módulo queda exactamente donde estaba.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    height: 1.35,
                  ),
            ),
          ),
        ];
        for (final group in ToolbarToolGroup.values) {
          final groupedTools = visibleTools
              .where((tool) => tool.toolbarPresentation.group == group)
              .toList(growable: false);
          if (groupedTools.isEmpty) continue;
          widgets.add(
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 5),
              child: Text(
                group.label.toUpperCase(),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.55,
                    ),
              ),
            ),
          );
          for (final tool in groupedTools) {
            widgets.add(
              _buildCompactToolRow(
                context,
                tool: tool,
                toolbarService: toolbarService,
                badgeCount: _compactToolBadgeCount(
                  tool,
                  chatProvider,
                  notificationCount,
                ),
              ),
            );
          }
        }
        widgets.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 5),
            child: Text(
              'APARIENCIA',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.55,
                  ),
            ),
          ),
        );
        widgets.add(
          Consumer<AppearanceService>(
            builder: (context, appearance, _) => _ThemeModeSelector(
              mode: appearance.themeMode,
              onChanged: appearance.setThemeMode,
              padding: const EdgeInsets.fromLTRB(16, 2, 16, 10),
            ),
          ),
        );
        widgets.add(
          ListTile(
            minTileHeight: 52,
            // La fila va sobre el navy; la HOJA que abre, no (ver abajo).
            iconColor: chrome.mutedForeground,
            textColor: chrome.foreground,
            leading: Icon(
              Icons.swap_vert_rounded,
              color: chrome.mutedForeground,
            ),
            title: Text(
              'Reordenar módulos',
              style: TextStyle(color: chrome.foreground),
            ),
            trailing: Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: chrome.mutedForeground,
            ),
            // Open from the app context above the drawer's chromatic Theme.
            // Otherwise showModalBottomSheet captures the shell ColorScheme and
            // paints a navy application overlay.
            onTap: () => _showReorderSheet(overlayContext),
          ),
        );
        widgets.add(const SizedBox(height: 16));
        return Column(
          key: const ValueKey('mobile-drawer-tools-mode'),
          mainAxisSize: MainAxisSize.min,
          children: widgets,
        );
      },
    );
  }

  int _compactToolBadgeCount(
    ToolbarTool tool,
    ChatProvider chatProvider,
    int notificationCount,
  ) {
    if (tool == ToolbarTool.notifications) return notificationCount;
    if (tool != ToolbarTool.messages && tool != ToolbarTool.supplierMessages) {
      return 0;
    }
    final supplier = tool == ToolbarTool.supplierMessages;
    return chatProvider.conversations.fold<int>(0, (sum, conversation) {
      if (conversation.isSupplierConversation != supplier) return sum;
      if (conversation.type == 'support' && conversation.status == 'pending') {
        return sum +
            (conversation.unreadCount > 0 ? conversation.unreadCount : 1);
      }
      return sum + conversation.unreadCount;
    });
  }

  Widget _buildCompactToolRow(
    BuildContext context, {
    required ToolbarTool tool,
    required RightToolbarService toolbarService,
    required int badgeCount,
  }) {
    final theme = Theme.of(context);
    final presentation = tool.toolbarPresentation;
    final selected = toolbarService.activeTool == tool;
    final badgeLabel = badgeCount > 99 ? '99+' : '$badgeCount';

    return Semantics(
      button: true,
      selected: selected,
      label:
          '${presentation.title}${badgeCount > 0 ? ', $badgeCount pendientes' : ''}',
      child: ListTile(
        key: ValueKey('mobile-toolbar-tool-${tool.name}'),
        minLeadingWidth: 32,
        minVerticalPadding: 4,
        selected: selected,
        selectedTileColor: theme.colorScheme.primaryContainer,
        leading: Icon(
          presentation.icon,
          size: 21,
          color: selected
              ? theme.colorScheme.onPrimaryContainer
              : theme.colorScheme.onSurfaceVariant,
        ),
        title: Text(
          presentation.title,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: selected ? theme.colorScheme.onPrimaryContainer : null,
            fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (badgeCount > 0)
              Container(
                constraints: const BoxConstraints(
                  minWidth: 24,
                  minHeight: 22,
                ),
                padding: const EdgeInsets.symmetric(horizontal: 7),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: theme.colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  badgeLabel,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onErrorContainer,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            const SizedBox(width: 6),
            Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ],
        ),
        onTap: () {
          final route = presentation.route;
          if (route != null) {
            Navigator.pop(context);
            _handleMobileNavigation(context, route, presentation.title);
            return;
          }
          toolbarService.openTool(tool);
          Navigator.pop(context);
        },
      ),
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
    final modules = resolveOrderedAppModules(context);
    final fixedModules = resolveFixedAppModules(
      context,
      currentLocation: currentLocation,
    );
    _expandedSection ??= [...modules, ...fixedModules]
        .where((module) => module.matchesLocation(currentLocation))
        .map((module) => module.key)
        .firstOrNull;

    final appTheme = Theme.of(context);
    final appearance = context.watch<AppearanceService>();
    final chrome = WorkspaceChromeStyle.maybeOf(context) ??
        WorkspaceChromeTheme.resolveFromTheme(
          appTheme,
          fallback: WorkspaceChromeTheme.resolve(
            palette: appearance.sidebarPalette,
            brightness: appTheme.brightness,
          ),
        );
    final width =
        (MediaQuery.sizeOf(context).width - 62).clamp(280.0, 348.0).toDouble();

    return Theme(
      data: WorkspaceChromeTheme.sidebarTheme(appTheme, chrome),
      child: Builder(
        builder: (drawerContext) {
          Widget destination(AppDestinationModule module) {
            return ExpandableMenuItem(
              key: ValueKey('drawer-${module.key}'),
              icon: module.icon,
              activeIcon: module.activeIcon,
              title: module.title,
              subItems: module.items,
              currentLocation: currentLocation,
              isSingleItem: module.isSingleItem,
              enabled: module.enabled,
              compactTouch: true,
              badgeCount: module.badgeCount,
              subItemBadgeCounts: module.subItemBadgeCounts,
              isExpanded: _expandedSection == module.key,
              onExpansionChanged: (expand) =>
                  _handleExpansionChange(module.key, expand),
              onBadgeTap: module.resolvedBadgeRoute == null
                  ? null
                  : () {
                      final route = module.resolvedBadgeRoute!;
                      Navigator.pop(drawerContext);
                      _handleMobileNavigation(
                        drawerContext,
                        route,
                        module.title,
                      );
                    },
              onNavigate: (route) {
                final resolved = module.resolveRoute?.call(route) ?? route;
                Navigator.pop(drawerContext);
                _handleMobileNavigation(
                  drawerContext,
                  resolved,
                  module.title,
                );
              },
              onCurrentTap: () => Navigator.pop(drawerContext),
            );
          }

          Widget navigationList() {
            if (_searchQuery.isNotEmpty) {
              return _buildCompactSearchResults(
                drawerContext,
                modules: modules,
                fixedModules: fixedModules,
                chrome: chrome,
              );
            }
            return ListView(
              key: const ValueKey('mobile-drawer-navigation-mode'),
              padding: const EdgeInsets.only(bottom: 12),
              children: [
                _buildCompactWorkspaceAccess(drawerContext, chrome: chrome),
                _buildCompactNewWorkspaceAction(drawerContext, chrome: chrome),
                ExpandableMenuItem(
                  key: const ValueKey('drawer-dashboard'),
                  icon: Icons.dashboard_outlined,
                  activeIcon: Icons.dashboard,
                  title: 'Inicio',
                  subItems: const [
                    MenuSubItem(
                      icon: Icons.dashboard,
                      title: 'Inicio',
                      route: '/dashboard',
                    ),
                  ],
                  currentLocation: currentLocation,
                  isSingleItem: true,
                  compactTouch: true,
                  onNavigate: (route) {
                    Navigator.pop(drawerContext);
                    _handleMobileNavigation(
                      drawerContext,
                      route,
                      'Inicio',
                    );
                  },
                  onCurrentTap: () => Navigator.pop(drawerContext),
                ),
                for (final module in modules) destination(module),
                if (fixedModules.isNotEmpty)
                  Divider(color: chrome.edge, height: 12),
                for (final module in fixedModules) destination(module),
              ],
            );
          }

          return Drawer(
            key: const ValueKey('main-layout-mobile-drawer'),
            width: width,
            elevation: 0,
            backgroundColor: chrome.canvas,
            surfaceTintColor: Colors.transparent,
            shape: const RoundedRectangleBorder(),
            child: SafeArea(
              child: Column(
                children: [
                  _buildCompactDrawerHeader(drawerContext),
                  _buildDrawerModeSwitch(drawerContext),
                  if (_mode == _AppDrawerMode.navigation)
                    _buildCompactNavigationSearch(drawerContext),
                  Expanded(
                    child: _mode == _AppDrawerMode.navigation
                        ? navigationList()
                        : SingleChildScrollView(
                            child: _buildCompactToolsMode(
                              drawerContext,
                              overlayContext: context,
                              chrome: chrome,
                            ),
                          ),
                  ),
                  Container(
                    key: const ValueKey('mobile-drawer-footer'),
                    decoration: BoxDecoration(
                      border: Border(top: BorderSide(color: chrome.edge)),
                    ),
                    child: Column(
                      children: [
                        // Mismo defecto medido que en los resultados del
                        // buscador: sin color explícito salían a 1,03:1 sobre
                        // el navy.
                        ListTile(
                          minTileHeight: 52,
                          iconColor: chrome.mutedForeground,
                          textColor: chrome.foreground,
                          leading: Icon(
                            Icons.settings_outlined,
                            color: chrome.mutedForeground,
                          ),
                          title: Text(
                            'Configuración',
                            style: TextStyle(color: chrome.foreground),
                          ),
                          trailing: Icon(
                            Icons.chevron_right_rounded,
                            size: 20,
                            color: chrome.mutedForeground,
                          ),
                          onTap: () {
                            Navigator.pop(drawerContext);
                            _handleMobileNavigation(
                              drawerContext,
                              '/settings',
                              'Configuración',
                            );
                          },
                        ),
                        ListTile(
                          minTileHeight: 52,
                          iconColor: chrome.mutedForeground,
                          textColor: chrome.foreground,
                          leading: Icon(
                            Icons.logout_outlined,
                            color: chrome.mutedForeground,
                          ),
                          title: Text(
                            'Cerrar sesión',
                            style: TextStyle(color: chrome.foreground),
                          ),
                          onTap: () => _handleLogout(drawerContext),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
