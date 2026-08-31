import 'dart:async';
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
import 'notifications_panel.dart';
import 'quick_messages_panel.dart';
import 'quick_supplier_messages_panel.dart';
import '../services/workspace_manager.dart';
import '../services/window_zoom_service.dart';
import '../services/notification_service.dart';
import '../themes/workspace_chrome_theme.dart';
import '../utils/responsive_viewport.dart';
import '../../modules/settings/services/appearance_service.dart';
import '../../modules/messaging/providers/chat_provider.dart';
import '../../modules/mail/providers/mail_account_manager.dart';
import 'expandable_menu_item.dart';
import '../services/workspace_launch_options.dart';
import 'browser_workspace_favicon.dart';
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
    icon: Icons.auto_awesome_outlined,
    title: 'Asistente de compras',
    route: '/purchases/assistant',
  ),
  MenuSubItem(
    icon: Icons.storefront_outlined,
    title: 'Proveedores',
    route: '/purchases/suppliers',
  ),
  MenuSubItem(
    icon: Icons.receipt_outlined,
    title: 'Documentos de compra',
    route: '/purchases',
  ),
  MenuSubItem(
    icon: Icons.note_add_outlined,
    title: 'Nuevo documento',
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
  // El panel se dibujaba contra el tema RAÍZ de la app, así que salía blanco
  // siempre — y es justamente el panel donde se elige la paleta: no se podía
  // previsualizar lo que se estaba eligiendo. El botón vive dentro del subárbol
  // con `WorkspaceChromeTheme.sidebarTheme`, así que su tema ES el de la barra;
  // se captura aquí y se reinyecta en el overlay.
  final chromeTheme = Theme.of(anchorContext);
  // El panel se dibuja en el overlay RAÍZ, fuera del subárbol del espacio de
  // trabajo, así que ahí `Provider.of<Workspace>` no encuentra nada. Dentro de
  // un espacio manda su propio modo de chrome, no la preferencia global: sin
  // capturarlo aquí, cambiar de Completo a Riel no hacía nada.
  final scopedWorkspace = _maybeWorkspaceOf(anchorContext);
  final workspaceManager = anchorContext.read<WorkspaceManager>();
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
            child: Theme(
              data: chromeTheme,
              child: _SidebarOptionsPanel(
                navigationService: navigationService,
                scopedWorkspace: scopedWorkspace,
                workspaceManager: workspaceManager,
                onClose: () => Navigator.of(dialogContext).pop(),
              ),
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

  /// Espacio de trabajo activo, capturado en el ancla: aquí dentro ya no está
  /// en el árbol.
  final Workspace? scopedWorkspace;
  final WorkspaceManager workspaceManager;

  const _SidebarOptionsPanel({
    required this.navigationService,
    required this.scopedWorkspace,
    required this.workspaceManager,
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
            // 344 y no 308: con tres rótulos —Completo/Riel/Oculto— el ancho
            // anterior partía «Completo» en dos líneas. Un SegmentedButton
            // reserva ~32px de padding por segmento y eso no se puede bajar.
            width: 344,
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
                // Los tres estados del menú, rotulados. Antes eran dos íconos
                // de chevron en el pie que sólo se distinguían por la cantidad
                // de flechas: « compactaba y ‹ ocultaba. Eso no se aprende.
                _SidebarChromeModeSelector(
                  navigationService: navigationService,
                  scopedWorkspace: scopedWorkspace,
                  workspaceManager: workspaceManager,
                  onClose: onClose,
                ),
                Divider(
                    height: 1,
                    color: theme.colorScheme.outlineVariant
                        .withValues(alpha: 0.3)),
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

/// Los tres estados de la barra lateral, con su nombre.
///
/// Reemplaza a los dos chevrons del pie. `expanded` y `rail` son el mismo
/// ajuste del servicio; «oculto» es visibilidad, otra cosa distinta — por eso
/// antes eran dos botones. Aquí se presentan como lo que son para el operador:
/// tres tamaños del mismo menú.
class _SidebarChromeModeSelector extends StatelessWidget {
  const _SidebarChromeModeSelector({
    required this.navigationService,
    required this.scopedWorkspace,
    required this.workspaceManager,
    required this.onClose,
  });

  final NavigationService navigationService;
  final Workspace? scopedWorkspace;
  final WorkspaceManager workspaceManager;
  final VoidCallback onClose;

  /// Dentro de un espacio de trabajo manda su modo; fuera, la preferencia
  /// global. Es la misma regla que usa el botón del pie.
  void _applyMode(NavigationChromeMode mode) {
    final workspace = scopedWorkspace;
    if (workspace != null) {
      workspaceManager.setWorkspaceChromeMode(workspace.id, mode);
    } else {
      navigationService.setPreferredChromeMode(mode);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hidden = !navigationService.isDrawerVisible;
    // Misma resolución que usa el shell: dentro de un espacio manda su
    // override, y sólo si no hay se cae a la preferencia global. Leer sólo la
    // global marcaba «Completo» con el riel puesto.
    final effectiveMode = scopedWorkspace?.chromeModeOverride ??
        navigationService.preferredChromeMode;
    final selected = hidden
        ? 'hidden'
        : effectiveMode == NavigationChromeMode.rail
            ? 'rail'
            : 'expanded';

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 2, bottom: 6),
            child: Row(
              children: [
                Icon(
                  Icons.view_sidebar_outlined,
                  size: 17,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                ),
                const SizedBox(width: 8),
                Text('Menú lateral', style: theme.textTheme.bodyMedium),
              ],
            ),
          ),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<String>(
              key: const ValueKey('sidebar-chrome-mode-selector'),
              // Sin iconos a propósito: con icono un SegmentedButton no se
              // estrecha y tres rótulos no caben en el panel de 308px.
              segments: const <ButtonSegment<String>>[
                ButtonSegment<String>(
                  value: 'expanded',
                  label: Text('Completo'),
                  tooltip: 'Menú con nombres',
                ),
                ButtonSegment<String>(
                  value: 'rail',
                  label: Text('Riel'),
                  tooltip: 'Sólo iconos',
                ),
                ButtonSegment<String>(
                  value: 'hidden',
                  label: Text('Oculto'),
                  tooltip: 'Sin menú lateral',
                ),
              ],
              selected: <String>{selected},
              showSelectedIcon: false,
              onSelectionChanged: (selection) {
                if (selection.isEmpty) return;
                switch (selection.single) {
                  case 'expanded':
                    _applyMode(NavigationChromeMode.expanded);
                    navigationService.showDrawer();
                  case 'rail':
                    _applyMode(NavigationChromeMode.rail);
                    navigationService.showDrawer();
                  case 'hidden':
                    navigationService.hideDrawer();
                    // Se cierra: el panel cuelga de un menú que acaba de
                    // desaparecer, y dejarlo abierto lo deja huérfano.
                    onClose();
                }
              },
            ),
          ),
        ],
      ),
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
                        // El riel también va envuelto en el tema del chrome.
                        // Sin esto sus desplegables salían blancos sobre la
                        // paleta: `MenuAnchor` conserva la ascendencia del
                        // árbol, así que hereda el tema del ancla — y el ancla
                        // vivía fuera del tema de la barra.
                        final sidebar = isRailChrome
                            ? Theme(
                                data: WorkspaceChromeTheme.sidebarTheme(
                                  Theme.of(context),
                                  chrome,
                                ),
                                child: const AppNavigationRail(),
                              )
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
            ),
          ],
        ),
        drawer: isPinnedWorkspace ? null : AppDrawer(),
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
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Con icono, un SegmentedButton NO se estrecha: ni la densidad
            // compacta ni un padding menor le bajan el ancho, y lo único que
            // funciona es quitar el icono. En el pie del drawer «Sistema» se
            // partía en dos líneas por eso.
            final showIcons = constraints.maxWidth >= 330;
            return SizedBox(
              width: double.infinity,
              child: SegmentedButton<ThemeMode>(
                key: const ValueKey('theme-mode-selector'),
                segments: <ButtonSegment<ThemeMode>>[
                  ButtonSegment<ThemeMode>(
                    value: ThemeMode.system,
                    icon: showIcons
                        ? const Icon(Icons.brightness_auto_outlined, size: 17)
                        : null,
                    label: const Text(
                      'Sistema',
                      key: ValueKey('theme-mode-system'),
                    ),
                    tooltip: 'Seguir apariencia del sistema',
                  ),
                  ButtonSegment<ThemeMode>(
                    value: ThemeMode.light,
                    icon: showIcons
                        ? const Icon(Icons.light_mode_outlined, size: 17)
                        : null,
                    label: const Text(
                      'Claro',
                      key: ValueKey('theme-mode-light'),
                    ),
                    tooltip: 'Usar siempre modo claro',
                  ),
                  ButtonSegment<ThemeMode>(
                    value: ThemeMode.dark,
                    icon: showIcons
                        ? const Icon(Icons.dark_mode_outlined, size: 17)
                        : null,
                    label: const Text(
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
            );
          },
        ),
      ),
    );
  }
}

class _CompactShellActions extends StatelessWidget {
  const _CompactShellActions({
    required this.chrome,
  });

  final WorkspaceChromeStyleData chrome;

  Future<void> _showNotifications(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      isScrollControlled: true,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.88,
      ),
      builder: (sheetContext) => const _CompactSheetFrame(
        title: 'Notificaciones',
        child: NotificationsToolbarPanel(),
      ),
    );
  }

  Future<void> _showMessages(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      isScrollControlled: true,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.88,
      ),
      builder: (sheetContext) => const _CompactMessagesSheet(),
    );
  }

  Future<void> _showWorkspacesAndTools(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      isScrollControlled: true,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.88,
      ),
      builder: (sheetContext) => const _CompactWorkspaceToolsSheet(),
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
            // Tres entradas separadas y cada una dice lo que abre: la campana
            // es sólo avisos, el globo es sólo mensajes, y la cuadrícula junta
            // lo que no es bandeja —tareas abiertas y herramientas—.
            _CompactHeaderAction(
              key: const ValueKey('main-layout-mobile-notifications'),
              chrome: chrome,
              icon: Icons.notifications_none_rounded,
              count: notificationCount,
              tooltip: 'Notificaciones',
              onPressed: () => _showNotifications(context),
            ),
            _CompactHeaderAction(
              key: const ValueKey('main-layout-mobile-messages'),
              chrome: chrome,
              icon: Icons.chat_bubble_outline_rounded,
              count: chatCount,
              tooltip: 'Mensajes',
              onPressed: () => _showMessages(context),
            ),
            _CompactHeaderAction(
              key: const ValueKey('main-layout-mobile-workspaces'),
              chrome: chrome,
              icon: Icons.grid_view_rounded,
              count: manager.workspaces.length >= 2
                  ? manager.workspaces.length
                  : 0,
              tooltip: 'Tareas y herramientas',
              onPressed: () => _showWorkspacesAndTools(context),
            ),
            const SizedBox(width: 4),
          ],
        );
      },
    );
  }
}

/// Marco común de las hojas compactas: título arriba y contenido debajo.
class _CompactSheetFrame extends StatelessWidget {
  const _CompactSheetFrame({
    required this.title,
    required this.child,
    this.showHeader = true,
  });

  final String title;
  final Widget child;

  /// La cabecera se ESCONDE, no se desmonta el marco. Devolver un árbol de
  /// otra forma cuando hay chat abierto hacía que Flutter recreara el panel, y
  /// el `initState` nuevo corría antes de que el `dispose` viejo guardara la
  /// sesión: el chat se abría y se cerraba solo en el mismo instante.
  final bool showHeader;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // `Visibility` y no `if`: quitar el hijo cambia el ÍNDICE de lo que
        // viene después, y Flutter, sin llaves, recrea esos elementos. El
        // panel de abajo se remontaba —y con él, el chat abierto se cerraba
        // solo. `Visibility` conserva la posición en la lista.
        Visibility(
          visible: showHeader,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 8, 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
          ),
        ),
        Expanded(child: child),
      ],
    );
  }
}

/// Las dos bandejas de conversación del taller.
enum _MessagesTab { suppliers, customers }

/// La hoja de Mensajes en compacto.
///
/// Proveedores y clientes son dos bandejas distintas con dueños distintos, y
/// cada una lleva su propio contador de no leídos: mezclarlas en un solo número
/// escondía cuál de las dos estaba esperando respuesta.
class _CompactMessagesSheet extends StatefulWidget {
  const _CompactMessagesSheet();

  @override
  State<_CompactMessagesSheet> createState() => _CompactMessagesSheetState();
}

class _CompactMessagesSheetState extends State<_CompactMessagesSheet> {
  /// La pestaña sobrevive al cierre: quien sigue una conversación con un
  /// proveedor vuelve a ella, no a la bandeja de clientes.
  static _MessagesTab _lastTab = _MessagesTab.suppliers;

  late _MessagesTab _tab;

  /// Con un chat abierto la hoja cede TODA su cabecera: el título y las
  /// pestañas no aportan ahí y en un teléfono le quitaban al mensaje casi un
  /// tercio de la pantalla.
  ///
  /// Es un `ValueNotifier` y NO un `setState` a propósito: reconstruir la hoja
  /// entera reconstruye el subárbol del panel, y dos intentos de esta función
  /// murieron por eso — el panel se remontaba y el chat recién abierto se
  /// cerraba solo. Con el notifier sólo la cabecera escucha; el panel ni se
  /// entera.
  final ValueNotifier<bool> _conversationOpen = ValueNotifier(false);

  @override
  void initState() {
    super.initState();
    _tab = _lastTab;
  }

  @override
  void dispose() {
    _conversationOpen.dispose();
    super.dispose();
  }

  void _handleConversationVisibility(bool visible) {
    if (!mounted) return;
    _conversationOpen.value = visible;
  }

  int _supplierCount(ChatProvider chat) => chat.conversations.fold(0, (sum, c) {
        if (!c.isSupplierConversation) return sum;
        if (c.type == 'support' && c.status == 'pending') {
          return sum + (c.unreadCount > 0 ? c.unreadCount : 1);
        }
        return sum + c.unreadCount;
      });

  int _customerCount(ChatProvider chat) => chat.conversations.fold(0, (sum, c) {
        if (c.isSupplierConversation) return sum;
        if (c.type == 'support' && c.status == 'pending') {
          return sum + (c.unreadCount > 0 ? c.unreadCount : 1);
        }
        return sum + c.unreadCount;
      });

  @override
  Widget build(BuildContext context) {
    final chat = context.watch<ChatProvider>();
    final counts = <_MessagesTab, int>{
      _MessagesTab.suppliers: _supplierCount(chat),
      _MessagesTab.customers: _customerCount(chat),
    };

    final inbox = Column(
      children: [
        ValueListenableBuilder<bool>(
          valueListenable: _conversationOpen,
          builder: (context, open, child) =>
              Visibility(visible: !open, child: child!),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: _CompactTabBar<_MessagesTab>(
              selected: _tab,
              values: _MessagesTab.values,
              counts: counts,
              keyPrefix: 'compact-messages-tab',
              labelOf: (tab) => switch (tab) {
                _MessagesTab.suppliers => 'Proveedores',
                _MessagesTab.customers => 'Clientes',
              },
              iconOf: (tab) => switch (tab) {
                _MessagesTab.suppliers => Icons.local_shipping_outlined,
                _MessagesTab.customers => Icons.person_outline_rounded,
              },
              nameOf: (tab) => tab.name,
              onChanged: (tab) => setState(() {
                _tab = tab;
                _lastTab = tab;
              }),
            ),
          ),
        ),
        Expanded(
          child: switch (_tab) {
            _MessagesTab.suppliers => QuickSupplierMessagesPanel(
                showTitle: false,
                onConversationVisibilityChanged: _handleConversationVisibility,
              ),
            _MessagesTab.customers => QuickMessagesPanel(
                showTitle: false,
                onConversationVisibilityChanged: _handleConversationVisibility,
              ),
          },
        ),
      ],
    );

    // Mismo árbol siempre; con chat abierto la cabecera sólo se esconde, y el
    // título escucha el notifier sin reconstruir la hoja.
    return ValueListenableBuilder<bool>(
      valueListenable: _conversationOpen,
      builder: (context, open, child) => _CompactSheetFrame(
        title: 'Mensajes',
        showHeader: !open,
        child: child!,
      ),
      child: inbox,
    );
  }
}

/// Lo que no es bandeja: herramientas y tareas abiertas.
enum _WorkspaceToolsTab { tools, workspaces }

/// La hoja de Tareas y herramientas en compacto.
///
/// Abre en **Herramientas** y las muestra aquí mismo. La versión anterior sólo
/// ofrecía una fila «Todas las herramientas» que mandaba al drawer, lo que era
/// un salto de más para lo que se usa a diario —y encima estaba rota: cerraba
/// la hoja y recién entonces buscaba el `Scaffold` con un contexto ya muerto,
/// así que no abría nada.
class _CompactWorkspaceToolsSheet extends StatefulWidget {
  const _CompactWorkspaceToolsSheet();

  @override
  State<_CompactWorkspaceToolsSheet> createState() =>
      _CompactWorkspaceToolsSheetState();
}

class _CompactWorkspaceToolsSheetState
    extends State<_CompactWorkspaceToolsSheet> {
  _WorkspaceToolsTab _tab = _WorkspaceToolsTab.tools;

  int _badgeFor(
    ToolbarTool tool,
    ChatProvider chat,
    int notificationCount,
  ) {
    switch (tool) {
      case ToolbarTool.notifications:
        return notificationCount;
      case ToolbarTool.messages:
        return chat.conversations.fold(0, (sum, c) {
          if (c.isSupplierConversation) return sum;
          if (c.type == 'support' && c.status == 'pending') {
            return sum + (c.unreadCount > 0 ? c.unreadCount : 1);
          }
          return sum + c.unreadCount;
        });
      case ToolbarTool.supplierMessages:
        return chat.conversations.fold(0, (sum, c) {
          if (!c.isSupplierConversation) return sum;
          if (c.type == 'support' && c.status == 'pending') {
            return sum + (c.unreadCount > 0 ? c.unreadCount : 1);
          }
          return sum + c.unreadCount;
        });
      default:
        return 0;
    }
  }

  /// El router y el servicio se toman ANTES de cerrar: después del `pop` el
  /// contexto de la hoja está muerto y cualquier lookup contra él falla en
  /// silencio, que es exactamente por qué la fila anterior no abría nada.
  void _openTool(ToolbarTool tool) {
    final presentation = tool.toolbarPresentation;
    final route = presentation.route;
    final router = GoRouter.of(context);
    final toolbarService = context.read<RightToolbarService>();

    Navigator.pop(context);
    if (route != null) {
      router.push(route);
      return;
    }
    toolbarService.openTool(tool);
  }

  Widget _buildTools(BuildContext context) {
    final toolbarService = context.watch<RightToolbarService>();
    final chat = context.watch<ChatProvider>();
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
        final rows = <Widget>[];
        for (final group in ToolbarToolGroup.values) {
          final grouped = visibleTools
              .where((tool) => tool.toolbarPresentation.group == group)
              .toList(growable: false);
          if (grouped.isEmpty) continue;
          rows.add(
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
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
          for (final tool in grouped) {
            final presentation = tool.toolbarPresentation;
            final badge = _badgeFor(tool, chat, notificationCount);
            rows.add(
              ListTile(
                key: ValueKey('compact-tools-${tool.name}'),
                minTileHeight: 52,
                // La herramienta abierta se ve marcada: en el drawer anterior
                // se veía, y sin eso no se sabe a cuál se está volviendo.
                selected: toolbarService.activeTool == tool,
                selectedTileColor:
                    Theme.of(context).colorScheme.primaryContainer,
                leading: Icon(presentation.icon),
                title: Text(presentation.title),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (badge > 0) _CompactCountBadge(count: badge),
                    const SizedBox(width: 6),
                    const Icon(Icons.chevron_right_rounded, size: 20),
                  ],
                ),
                onTap: () => _openTool(tool),
              ),
            );
          }
        }
        return ListView(
          padding: const EdgeInsets.only(bottom: 16),
          children: rows,
        );
      },
    );
  }

  /// Las tareas abiertas, con todo lo que traían en el drawer: favicon del
  /// navegador, fijar/desfijar, cerrar, y las pestañas web agrupadas cuando hay
  /// más de una sin fijar. Al sacar los espacios del drawer esto se había
  /// perdido; es una diferencia real, no adorno.
  Widget _buildWorkspaces(BuildContext context) {
    final manager = context.watch<WorkspaceManager>();
    final workspaces = manager.workspaces;
    final activeId = manager.activeWorkspace?.id;

    if (workspaces.isEmpty) {
      return const Center(child: Text('No hay tareas abiertas'));
    }

    final browserStack = manager.unpinnedBrowserWorkspaces;
    final groupsBrowsers = browserStack.length > 1;
    final browserStackIds = groupsBrowsers
        ? browserStack.map((workspace) => workspace.id).toSet()
        : const <String>{};

    final children = <Widget>[];
    var insertedBrowserStack = false;
    for (final workspace in workspaces) {
      if (browserStackIds.contains(workspace.id)) {
        if (!insertedBrowserStack) {
          children.add(
            ExpansionTile(
              key: const ValueKey('mobile-browser-workspace-group'),
              minTileHeight: 48,
              initiallyExpanded:
                  browserStack.any((browser) => browser.id == activeId),
              leading: const Icon(Icons.tab_rounded, size: 20),
              title: Text(
                'Pestañas web · ${browserStack.length}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              children: [
                for (final browser in browserStack)
                  _buildWorkspaceTile(context, manager, browser, activeId),
              ],
            ),
          );
          insertedBrowserStack = true;
        }
        continue;
      }
      children.add(
        _buildWorkspaceTile(context, manager, workspace, activeId),
      );
    }

    return ListView(
      key: const ValueKey('mobile-workspace-selector'),
      padding: const EdgeInsets.only(bottom: 16),
      children: [
        _buildNewWorkspaceAction(context, manager),
        const Divider(height: 1),
        ...children,
      ],
    );
  }

  /// Abrir un espacio nuevo. Existe desde el 2026-08-06 porque hasta entonces
  /// el shell compacto sólo podía moverse entre los espacios ya abiertos y no
  /// podía crear el segundo. Se movió aquí con el resto del manejo de tareas;
  /// perderlo dejaría al teléfono otra vez sin poder abrir uno.
  Widget _buildNewWorkspaceAction(
    BuildContext context,
    WorkspaceManager manager,
  ) {
    final atLimit = manager.workspaces.length >= WorkspaceManager.maxWorkspaces;
    return ListTile(
      key: const ValueKey('mobile-workspace-new'),
      minTileHeight: 48,
      enabled: !atLimit,
      leading: const Icon(Icons.add_rounded, size: 20),
      // El tope se dice, no se descubre al fallar.
      title: Text(
        atLimit ? 'Máximo de espacios abiertos' : 'Nuevo espacio de trabajo',
      ),
      onTap: atLimit ? null : () => _openWorkspaceLauncher(context, manager),
    );
  }

  /// Elige el destino del espacio nuevo en una hoja inferior.
  ///
  /// O-05 de la guía de componentes: en compacto el catálogo se ofrece en una
  /// hoja, no en el popover anclado que usa el «+» de escritorio.
  Future<void> _openWorkspaceLauncher(
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
    // Cerrar la hoja deja a la vista el espacio recién abierto.
    if (navigator.canPop()) navigator.pop();
  }

  Widget _buildWorkspaceTile(
    BuildContext context,
    WorkspaceManager manager,
    Workspace workspace,
    String? activeId,
  ) {
    final theme = Theme.of(context);
    final selected = workspace.id == activeId;
    return ListTile(
      key: ValueKey('mobile-workspace-${workspace.id}'),
      minTileHeight: 48,
      selected: selected,
      selectedColor: theme.colorScheme.onPrimaryContainer,
      selectedTileColor: theme.colorScheme.primaryContainer,
      leading: workspace.isBrowserWorkspace
          ? BrowserWorkspaceFavicon(
              key: ValueKey('mobile-workspace-favicon-${workspace.id}'),
              faviconUrl: workspace.browserFaviconUrl,
              size: 20,
              fallbackColor: theme.colorScheme.onSurfaceVariant,
            )
          : Icon(
              selected
                  ? Icons.check_circle_rounded
                  : Icons.radio_button_unchecked_rounded,
            ),
      title: Text(
        workspace.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: workspace.currentRoute == workspace.initialRoute
          ? null
          : Text(
              getRouteTitle(workspace.currentRoute),
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
          // Con una sola tarea no se ofrece cerrarla: dejaría el espacio vacío.
          if (manager.workspaces.length > 1)
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

  @override
  Widget build(BuildContext context) {
    final workspaceCount = context.watch<WorkspaceManager>().workspaces.length;

    return _CompactSheetFrame(
      title: 'Tareas y herramientas',
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: _CompactTabBar<_WorkspaceToolsTab>(
              selected: _tab,
              values: _WorkspaceToolsTab.values,
              counts: {
                _WorkspaceToolsTab.tools: 0,
                _WorkspaceToolsTab.workspaces: workspaceCount,
              },
              keyPrefix: 'compact-workspace-tools-tab',
              labelOf: (tab) => switch (tab) {
                _WorkspaceToolsTab.tools => 'Herramientas',
                _WorkspaceToolsTab.workspaces => 'Tareas',
              },
              iconOf: (tab) => switch (tab) {
                _WorkspaceToolsTab.tools => Icons.grid_view_rounded,
                _WorkspaceToolsTab.workspaces => Icons.layers_outlined,
              },
              nameOf: (tab) => tab.name,
              onChanged: (tab) => setState(() => _tab = tab),
            ),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: switch (_tab) {
              _WorkspaceToolsTab.tools => _buildTools(context),
              _WorkspaceToolsTab.workspaces => _buildWorkspaces(context),
            },
          ),
        ],
      ),
    );
  }
}

/// Pestañas compactas con contador propio.
///
/// Se dibujan a mano y no con `SegmentedButton`: ése no se estrecha con icono
/// —ni densidad compacta ni padding reducen su ancho— y desborda en un teléfono
/// angosto.
class _CompactTabBar<T> extends StatelessWidget {
  const _CompactTabBar({
    required this.selected,
    required this.values,
    required this.counts,
    required this.labelOf,
    required this.iconOf,
    required this.nameOf,
    required this.keyPrefix,
    required this.onChanged,
  });

  final T selected;
  final List<T> values;
  final Map<T, int> counts;
  final String Function(T) labelOf;
  final IconData Function(T) iconOf;
  final String Function(T) nameOf;
  final String keyPrefix;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          for (final value in values)
            Expanded(
              child: _CompactTab(
                tabKey: ValueKey('$keyPrefix-${nameOf(value)}'),
                label: labelOf(value),
                icon: iconOf(value),
                count: counts[value] ?? 0,
                isSelected: value == selected,
                onTap: () => onChanged(value),
              ),
            ),
        ],
      ),
    );
  }
}

class _CompactTab extends StatelessWidget {
  const _CompactTab({
    required this.tabKey,
    required this.label,
    required this.icon,
    required this.count,
    required this.isSelected,
    required this.onTap,
  });

  final Key tabKey;
  final String label;
  final IconData icon;
  final int count;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final foreground = isSelected
        ? theme.colorScheme.onSurface
        : theme.colorScheme.onSurfaceVariant;

    return Semantics(
      button: true,
      selected: isSelected,
      label: count > 0 ? '$label, $count sin leer' : label,
      excludeSemantics: true,
      child: InkWell(
        key: tabKey,
        borderRadius: BorderRadius.circular(9),
        onTap: onTap,
        child: Container(
          // 48px reales: en compacto no hay escala 0.8 que los encoja.
          height: 48,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isSelected ? theme.colorScheme.surface : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 3,
                      offset: const Offset(0, 1),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            // Explícito: sin esto el contador se estiraba a lo alto de la
            // pestaña y se leía como una barra, no como un número.
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: foreground),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: foreground,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ),
              if (count > 0) ...[
                const SizedBox(width: 5),
                SizedBox(
                  height: 16,
                  child: _CompactCountBadge(count: count),
                ),
              ],
            ],
          ),
        ),
      ),
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
            // El tooltip sólo aparece al pasar el cursor o mantener pulsado, y
            // en un teléfono eso no existe: sin rótulo semántico estos tres
            // íconos eran mudos para un lector de pantalla. El contador entra
            // en el mismo rótulo para que se oiga «Mensajes, 3 sin leer».
            child: Semantics(
              button: true,
              label: count > 0 ? '$tooltip, $count sin leer' : tooltip,
              excludeSemantics: true,
              child: IconButton(
                tooltip: tooltip,
                onPressed: onPressed,
                color: chrome.foreground,
                icon: Icon(icon, size: 21),
              ),
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

                // El pie lleva dos cosas y las dos dicen su nombre: la
                // apariencia, y el gesto diario de compactar. Antes eran tres
                // íconos mudos —«...», « y ‹— donde el segundo y el tercero
                // sólo se distinguían por la cantidad de flechas.
                Consumer<NavigationService>(
                  builder: (context, navigationService, _) {
                    final isRail = navigationService.preferredChromeMode ==
                        NavigationChromeMode.rail;
                    return Container(
                      padding: const EdgeInsets.fromLTRB(6, 4, 6, 6),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextButton.icon(
                              key: const ValueKey('sidebar-appearance-entry'),
                              onPressed: () {
                                _showSidebarOptionsMenu(
                                  anchorContext: context,
                                  overlayContext: widget.overlayContext,
                                  navigationService: navigationService,
                                );
                              },
                              icon:
                                  const Icon(Icons.palette_outlined, size: 17),
                              label: const Text(
                                'Apariencia',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              style: TextButton.styleFrom(
                                alignment: Alignment.centerLeft,
                                foregroundColor: theme.colorScheme.onSurface
                                    .withValues(alpha: 0.75),
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 8),
                                minimumSize: const Size(0, 36),
                              ),
                            ),
                          ),
                          // Un solo botón para el gesto de todos los días.
                          // «Oculto» vive en Apariencia: es raro, y una vez
                          // oculto este botón ya no existe, así que su vuelta
                          // es por otro camino de todos modos.
                          IconButton(
                            key: const ValueKey('sidebar-compact-toggle'),
                            icon: Icon(
                              isRail
                                  ? Icons.view_sidebar_rounded
                                  : Icons.view_sidebar_outlined,
                              size: 18,
                            ),
                            iconSize: 18,
                            padding: const EdgeInsets.all(8),
                            constraints: const BoxConstraints(
                              minWidth: 36,
                              minHeight: 36,
                            ),
                            tooltip:
                                isRail ? 'Expandir menú' : 'Compactar menú',
                            onPressed: () {
                              final nextMode = isRail
                                  ? NavigationChromeMode.expanded
                                  : NavigationChromeMode.rail;
                              final scopedWorkspace =
                                  _maybeWorkspaceOf(context);
                              if (scopedWorkspace != null) {
                                context
                                    .read<WorkspaceManager>()
                                    .setWorkspaceChromeMode(
                                      scopedWorkspace.id,
                                      nextMode,
                                    );
                              } else {
                                navigationService
                                    .setPreferredChromeMode(nextMode);
                              }
                            },
                            style: IconButton.styleFrom(
                              foregroundColor: theme.colorScheme.onSurface
                                  .withValues(alpha: 0.7),
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
              // Apariencia también desde el riel: si no, para llegar a los
              // tres estados del menú había que expandir primero.
              _RailDestination(
                title: 'Apariencia',
                icon: Icons.palette_outlined,
                activeIcon: Icons.palette,
                selected: false,
                hasSubmenu: true,
                onTap: () => _showSidebarOptionsMenu(
                  anchorContext: context,
                  overlayContext: context,
                  navigationService: context.read<NavigationService>(),
                ),
              ),
              // Un solo control, igual que en la barra expandida. «Ocultar»
              // vive en Apariencia: es raro, y dos flechas que se distinguen
              // por su cantidad no se aprenden.
              _RailDestination(
                title: 'Expandir menú',
                icon: Icons.view_sidebar_rounded,
                activeIcon: Icons.view_sidebar_rounded,
                selected: false,
                onTap: () => _expandChrome(context),
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

  /// El desplegable se abre al posar el cursor, como el de Zoho. El cierre va
  /// con un respiro: al pasar del icono al panel el puntero deja el disparador
  /// por unos milisegundos, y sin esa gracia el menú se cerraría justo cuando
  /// el usuario va a usarlo.
  Timer? _closeTimer;

  void _openOnHover() {
    _closeTimer?.cancel();
    if (!_menuController.isOpen) _menuController.open();
  }

  void _scheduleClose() {
    _closeTimer?.cancel();
    _closeTimer = Timer(const Duration(milliseconds: 450), () {
      if (mounted && _menuController.isOpen) _menuController.close();
    });
  }

  @override
  void dispose() {
    _closeTimer?.cancel();
    super.dispose();
  }

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
      // Al COSTADO del icono, fuera del riel. Por defecto `MenuAnchor` abre
      // hacia abajo, y ahí el panel se monta encima de los módulos siguientes:
      // el riel queda inutilizable justo mientras se está mirando el submenú.
      style: const MenuStyle(
        alignment: AlignmentDirectional.topEnd,
        minimumSize: WidgetStatePropertyAll(Size(230, 0)),
      ),
      // Sin hueco: 6px entre el icono y el panel son zona muerta donde el
      // cursor no está en ninguno de los dos, y ahí arranca el cierre.
      alignmentOffset: Offset.zero,
      menuChildren: [
        // Envuelve TODO el panel: entrar en él cancela el cierre programado.
        // Antes esto envolvía un `SizedBox.shrink()` —tamaño cero—, así que no
        // recibía el cursor nunca y el menú se cerraba igual estuvieras encima
        // o no. Era imposible llegar a un submódulo.
        MouseRegion(
          onEnter: (_) => _closeTimer?.cancel(),
          onExit: (_) => _scheduleClose(),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
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
                    trailingIcon:
                        (module.subItemBadgeCounts[item.route] ?? 0) > 0
                            ? _RailBadge(
                                count: module.subItemBadgeCounts[item.route]!,
                              )
                            : null,
                    onPressed: () => _navigate(item.route),
                    child: Text(item.title),
                  ),
            ],
          ),
        ),
      ],
      builder: (context, controller, _) {
        return MouseRegion(
          onEnter: (_) => _openOnHover(),
          onExit: (_) => _scheduleClose(),
          child: _RailDestination(
            title: module.title,
            icon: module.icon,
            activeIcon: module.activeIcon,
            selected: selected,
            enabled: module.enabled,
            badgeCount: module.badgeCount,
            expanded: controller.isOpen,
            hasSubmenu: true,
            onTap: () {
              // El clic sigue sirviendo: en pantalla táctil no hay hover.
              if (controller.isOpen) {
                controller.close();
              } else {
                controller.open();
              }
            },
          ),
        );
      },
    );
  }
}

/// Una entrada del riel, al estilo del de Zoho Books: icono con su rótulo
/// debajo, y el seleccionado como un bloque relleno.
///
/// El riel anterior era de iconos mudos: para saber qué era cada uno había que
/// posar el cursor y esperar el tooltip, uno por uno. Un rótulo de 10px cuesta
/// 20px de ancho y elimina esa adivinanza.
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
    this.hasSubmenu = false,
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

  /// Marca la esquina cuando el módulo tiene submódulos, para que se sepa que
  /// hay algo más antes de posar el cursor.
  final bool hasSubmenu;

  @override
  Widget build(BuildContext context) {
    final chrome = WorkspaceChromeStyle.maybeOf(context) ??
        WorkspaceChromeStyleData.vinabike;
    final foreground = !enabled
        ? chrome.mutedForeground.withValues(alpha: 0.45)
        : selected
            ? chrome.onAccent
            : chrome.mutedForeground;

    // El tooltip sólo tiene sentido donde NO hay desplegable: el rótulo se corta
    // a dos líneas y ahí conserva el nombre entero. En un módulo con submenú el
    // panel ya lo encabeza con su nombre, así que el tooltip repetía la palabra
    // y encima flotaba por encima del propio panel.
    final body = Semantics(
      button: true,
      selected: selected,
      expanded: expanded,
      label: title + (badgeCount > 0 ? ', $badgeCount pendientes' : ''),
      excludeSemantics: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: enabled ? onTap : null,
          canRequestFocus: enabled && onTap != null,
          mouseCursor:
              enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
          hoverColor: chrome.foreground.withValues(alpha: 0.08),
          focusColor: chrome.foreground.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
          child: SizedBox(
            width: AppNavigationRail.railWidth,
            height: 58,
            child: Center(
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 64,
                    height: 52,
                    decoration: BoxDecoration(
                      color: selected ? chrome.accent : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    alignment: Alignment.center,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(selected ? activeIcon : icon,
                            size: 19, color: foreground),
                        const SizedBox(height: 3),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 3),
                          child: Text(
                            title,
                            maxLines: 2,
                            textAlign: TextAlign.center,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 9.5,
                              height: 1.1,
                              letterSpacing: 0,
                              color: foreground,
                              fontWeight:
                                  selected ? FontWeight.w700 : FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (hasSubmenu)
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: CustomPaint(
                        size: const Size(6, 6),
                        painter: _RailSubmenuCorner(
                          color: selected
                              ? chrome.onAccent.withValues(alpha: 0.75)
                              : chrome.mutedForeground.withValues(alpha: 0.65),
                        ),
                      ),
                    ),
                  if (badgeCount > 0)
                    Positioned(
                      top: -1,
                      right: 2,
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
    );

    if (hasSubmenu) return body;
    return Tooltip(
      message: title,
      waitDuration: const Duration(milliseconds: 500),
      child: body,
    );
  }
}

/// El triangulito de la esquina que marca «esto tiene submódulos».
class _RailSubmenuCorner extends CustomPainter {
  const _RailSubmenuCorner({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(size.width, 0)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _RailSubmenuCorner oldDelegate) =>
      oldDelegate.color != color;
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
  });

  @override
  State<AppDrawer> createState() => _AppDrawerState();
}

// 2026-08-20 · el drawer es sólo navegación. El enum de modos y el
// controlador externo que lo ponía en «Herramientas» quedaron sin uso al mover
// las herramientas a la hoja del encabezado.
class _AppDrawerState extends State<AppDrawer> {
  String? _expandedSection;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
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
  /// Tema y paleta en compacto.
  ///
  /// El teléfono sólo tenía claro/oscuro: la paleta no se podía elegir en
  /// ningún lado. Los estados del menú lateral y el zoom NO están, y es
  /// correcto — no hay barra que compactar, y la guía móvil fija la escala en
  /// 1.0 bajo 900px, así que el zoom es preferencia de escritorio.
  void _showCompactAppearanceSheet(BuildContext hostContext) {
    Navigator.pop(hostContext);
    showModalBottomSheet<void>(
      context: hostContext,
      useSafeArea: true,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => Consumer<AppearanceService>(
        builder: (context, appearance, _) => SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 4, 18, 6),
                child: Text(
                  'Apariencia',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              _ThemeModeSelector(
                mode: appearance.themeMode,
                onChanged: appearance.setThemeMode,
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              ),
              _SidebarPalettePicker(appearanceService: appearance),
              _OptionSwitchTile(
                icon: Icons.chat_bubble_outline,
                label: 'Paleta en mensajería',
                value: appearance.messagingUsesSidebarPalette,
                onChanged: appearance.setMessagingUsesSidebarPalette,
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

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
                  // 2026-08-20 · decisión del dueño: el drawer es sólo
                  // navegación. Herramientas y tareas abiertas viven en la hoja
                  // del encabezado, y tenerlas también aquí eran dos caminos al
                  // mismo sitio.
                  _buildCompactNavigationSearch(drawerContext),
                  Expanded(child: navigationList()),
                  Container(
                    key: const ValueKey('mobile-drawer-footer'),
                    decoration: BoxDecoration(
                      border: Border(top: BorderSide(color: chrome.edge)),
                    ),
                    child: Column(
                      children: [
                        // El tema y el orden de los módulos venían del modo
                        // Herramientas, que se retiró del drawer. Reordenar
                        // módulos configura la propia navegación, así que su
                        // sitio es aquí; el tema acompaña a Configuración, que
                        // ya vivía en este pie. Ninguno de los dos se perdió.
                        // Una entrada con nombre, igual que en escritorio, en
                        // vez del selector suelto: el teléfono no tenía dónde
                        // elegir la paleta, sólo el modo claro/oscuro.
                        ListTile(
                          key: const ValueKey('mobile-drawer-appearance'),
                          minTileHeight: 52,
                          iconColor: chrome.mutedForeground,
                          textColor: chrome.foreground,
                          leading: Icon(
                            Icons.palette_outlined,
                            color: chrome.mutedForeground,
                          ),
                          title: Text(
                            'Apariencia',
                            style: TextStyle(color: chrome.foreground),
                          ),
                          trailing: Icon(
                            Icons.chevron_right_rounded,
                            size: 20,
                            color: chrome.mutedForeground,
                          ),
                          onTap: () => _showCompactAppearanceSheet(context),
                        ),
                        ListTile(
                          minTileHeight: 52,
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
                          // Desde el contexto de la app, por encima del Theme
                          // cromático del drawer: si no, la hoja captura el
                          // ColorScheme del shell y sale pintada de navy.
                          onTap: () => _showReorderSheet(context),
                        ),
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
