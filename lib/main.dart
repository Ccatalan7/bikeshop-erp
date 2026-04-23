import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'shared/services/notification_service.dart';

import 'shared/themes/app_theme.dart';
import 'shared/services/auth_service.dart';
import 'shared/services/database_service.dart';
import 'shared/services/inventory_service.dart';
import 'shared/services/payment_method_service.dart';
import 'shared/services/navigation_service.dart';
import 'shared/services/tenant_service.dart';
import 'shared/services/user_management_service.dart';
import 'shared/services/workspace_manager.dart';
import 'shared/config/supabase_config.dart';
import 'shared/widgets/workspace_tab_bar.dart';
import 'shared/utils/web_url.dart';
import 'modules/ai_assistant/widgets/ai_chat_bubble.dart';
import 'modules/inventory/services/category_service.dart';
import 'modules/inventory/services/inventory_service.dart' as module_inventory;
import 'modules/inventory/services/brand_service.dart';
import 'modules/inventory/services/stock_movements_service.dart';
import 'modules/crm/services/customer_service.dart';
import 'modules/accounting/services/accounting_service.dart';
import 'modules/accounting/services/financial_reports_service.dart';
import 'modules/accounting/services/expense_service.dart';
import 'modules/tax_reports/services/f29_service.dart';
import 'modules/pos/services/pos_service.dart';
import 'modules/purchases/services/purchase_service.dart';
import 'modules/purchases/services/smart_purchase_list_service.dart';
import 'modules/sales/services/sales_service.dart';
import 'modules/settings/services/appearance_service.dart';
import 'modules/bikeshop/services/bikeshop_service.dart';
import 'modules/bikeshop/services/wheel_building_service.dart';
import 'modules/bikeshop/services/smart_task_service.dart';
import 'modules/tasks/services/task_service.dart';
import 'modules/bikeshop/services/job_status_service.dart';
import 'modules/hr/services/hr_service.dart';
import 'modules/hr/services/payroll_voucher_service.dart';
import 'modules/website/services/website_service.dart';
import 'shared/services/niimbot_printer_service.dart';
import 'modules/website/services/mercadopago_service.dart';
import 'modules/website/services/google_business_service.dart';
import 'modules/website/providers/website_edit_mode_provider.dart';
import 'shared/services/job_role_service.dart';
import 'public_store/providers/cart_provider.dart';
import 'public_store/providers/public_store_tenant_provider.dart';
import 'modules/messaging/providers/chat_provider.dart';
import 'modules/messaging/services/messaging_service.dart';
import 'public_store/services/customer_account_service.dart';
import 'public_store/services/address_autocomplete_service.dart';
import 'public_store/services/public_inventory_service.dart';
import 'shared/routes/app_router.dart';
import 'shared/services/data_preload_service.dart';
import 'shared/services/error_reporting_service.dart';
import 'shared/services/tenant_detection_service.dart';
import 'shared/services/backup_service.dart';
import 'modules/spreadsheets/services/spreadsheet_service.dart';
import 'shared/services/window_zoom_service.dart';
import 'shared/services/right_toolbar_service.dart';
import 'shared/widgets/window_zoom_scope.dart';
import 'shared/widgets/branded_loading.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'shared/services/remote_scanner_service.dart';
import 'shared/services/barcode_scanner_service.dart';
import 'shared/widgets/scanner_bridge_scope.dart';
import 'shared/widgets/right_toolbar.dart';
import 'shared/widgets/query_performance_gauge.dart';
import 'public_router_app.dart';
import 'shared/services/deep_link_handler.dart';

// Custom scroll behavior to prevent browser navigation gestures on trackpad
class AppScrollBehavior extends MaterialScrollBehavior {
  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.stylus,
        PointerDeviceKind.trackpad,
      };
}

// CRITICAL: Capture the initial URL BEFORE usePathUrlStrategy() modifies it!
// This is needed for MercadoPago redirects and direct URL navigation to work.
String? _initialBrowserUrl;

// Performance timing for initialization
final _initTimings = <String, int>{};
late final Stopwatch _globalStopwatch;
bool _tenantDetectionStarted = false; // Prevent duplicate triggers

void _logTiming(String phase, [String? detail]) {
  final elapsed = _globalStopwatch.elapsedMilliseconds;
  _initTimings[phase] = elapsed;
  // Performance logging disabled for production
  // debugPrint('⏱️ [PERF] $phase: ${elapsed}ms${detail != null ? ' ($detail)' : ''}');
}

/// Hide the HTML loading screen after Flutter has loaded
void _hideLoadingScreen() {
  if (!kIsWeb) return;

  // Use web platform URL strategy to call JavaScript
  try {
    // This works by leveraging the url_strategy package's web implementation
    // which already has access to the DOM
    hideHtmlLoadingScreen();
    // debugPrint('✨ [Main] Loading screen hidden');
  } catch (e) {
    debugPrint('⚠️ [Main] Could not hide loading screen: $e');
  }
}

/// Initialize the deep link handler for mail OAuth callbacks
Future<DeepLinkHandler> _initializeDeepLinkHandler() async {
  final handler = DeepLinkHandler.instance;
  await handler.initialize();
  return handler;
}

Future<void> main() async {
  _globalStopwatch = Stopwatch()..start();

  // Capture browser URL IMMEDIATELY, before anything else
  if (kIsWeb) {
    _initialBrowserUrl = getInitialBrowserUrl();
    // Capture OAuth codes if present to prevent router from cleaning them
    captureZohoOAuthCode();
    captureGmailOAuthCode();
    // debugPrint('🚀 [Main] Captured initial URL: $_initialBrowserUrl');
  }
  _logTiming('URL_CAPTURED');

  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    _logTiming('FLUTTER_BINDING');

    // Use clean URLs (no hash #) for web
    usePathUrlStrategy();
    _logTiming('URL_STRATEGY');

    final isPublicStoreHost = _detectPublicStoreHost();

    if (!SupabaseConfig.isConfigured && kDebugMode) {
      debugPrint(
          '[Supabase] WARNING: SupabaseConfig still has placeholder values. '
          'Update lib/shared/config/supabase_config.dart or provide dart-defines.');
    }

    if (!isPublicStoreHost) {
      // Skip Firebase on Safari/iOS web - they don't support FCM properly
      // and cause the app to hang during initialization
      final skipFirebase = kIsWeb && shouldSkipFirebase();
      if (skipFirebase) {
        debugPrint(
            '⚠️ [Main] Safari/iOS detected - skipping Firebase initialization');
        _logTiming('FIREBASE_INIT_SKIPPED', 'safari_ios');
      } else {
        try {
          await Firebase.initializeApp(
            options: DefaultFirebaseOptions.currentPlatform,
          );
          _logTiming('FIREBASE_INIT');
        } catch (e) {
          debugPrint('⚠️ Firebase Config missing for this platform: $e');
          _logTiming('FIREBASE_INIT_SKIPPED');
        }
      }
    } else {
      _logTiming('FIREBASE_INIT_SKIPPED', 'public_store_host');
    }

    await Supabase.initialize(
      url: SupabaseConfig.url,
      anonKey: SupabaseConfig.anonKey,
      authOptions: const FlutterAuthClientOptions(
        autoRefreshToken: true,
      ),
    );
    _logTiming('SUPABASE_INIT');

    // Handle deep links for OAuth callbacks on desktop and mobile
    // Initialize Notifications (FCM for Mobile/Web, Local for Desktop)
    // Skip on public store: visitors don't need ERP notifications, and web plugins can crash startup.
    // NOTE: Don't await - let init run in background to avoid blocking app startup
    if (!isPublicStoreHost) {
      NotificationService().init(); // No await - non-blocking
      _logTiming('NOTIFICATIONS_INIT_STARTED');
    } else {
      _logTiming('NOTIFICATIONS_INIT_SKIPPED', 'public_store_host');
    }

    // Handle deep links for OAuth callbacks on desktop and mobile
    // Use our custom DeepLinkHandler for mail OAuth callbacks (vinabike:// scheme)
    if (!kIsWeb) {
      // Import and initialize the deep link handler for mail OAuth
      final deepLinkHandler = await _initializeDeepLinkHandler();
      debugPrint('🔗 [Main] DeepLinkHandler initialized: $deepLinkHandler');
    }

    FlutterError.onError = (FlutterErrorDetails details) {
      // Suppress Flutter Web-specific "disposed EngineFlutterView" errors
      // These occur during hot reload and navigation and don't affect functionality
      final errorString = details.exceptionAsString();
      if (kIsWeb &&
          errorString.contains('disposed') &&
          errorString.contains('EngineFlutterView')) {
        if (kDebugMode) {
          debugPrint(
              '⚠️ [Flutter Web] Suppressed disposed view error (hot reload artifact)');
        }
        return; // Don't report or dump these errors
      }

      ErrorReportingService.report(details.exception, details.stack);
      FlutterError.dumpErrorToConsole(details);
    };

    // Global error boundary - show user-friendly error UI instead of red screen
    // This prevents widget crashes from looking catastrophic to users
    ErrorWidget.builder = (FlutterErrorDetails details) {
      return Material(
        child: Container(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.warning_amber_rounded,
                  size: 48, color: Colors.orange),
              const SizedBox(height: 16),
              const Text(
                'Algo salió mal',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                kDebugMode
                    ? details.exceptionAsString()
                    : 'Por favor, intenta de nuevo.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.grey),
              ),
            ],
          ),
        ),
      );
    };

    runApp(const VinabikeApp());
    _logTiming('RUN_APP');

    // Hide the HTML loading screen after Flutter starts
    if (kIsWeb) {
      // Safety timeout: Ensure loading screen is hidden after 4 seconds max
      // This acts as a fallback if the data loading completion trigger fails
      Future.delayed(const Duration(seconds: 4), () {
        _hideLoadingScreen();
      });
    }
  }, (error, stack) {
    // Suppress Flutter Web-specific errors in zone guard as well
    final errorString = error.toString();
    if (kIsWeb &&
        errorString.contains('disposed') &&
        errorString.contains('EngineFlutterView')) {
      if (kDebugMode) {
        debugPrint('⚠️ [Flutter Web] Suppressed disposed view error (zone)');
      }
      return; // Don't report these errors
    }

    // Also suppress LegacyJavaScriptObject errors (http package compatibility issue)
    if (kIsWeb && errorString.contains('LegacyJavaScriptObject')) {
      if (kDebugMode) {
        debugPrint('⚠️ [Flutter Web] Suppressed LegacyJavaScriptObject error');
      }
      return;
    }

    ErrorReportingService.report(error, stack);
    debugPrint('Uncaught error: $error\n$stack');
  });
}

class VinabikeApp extends StatelessWidget {
  const VinabikeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        // Core services
        ChangeNotifierProvider(create: (_) => AuthService()),
        ChangeNotifierProvider(create: (_) => DatabaseService()),
        ChangeNotifierProvider(create: (_) {
          final tenantService = TenantService();
          tenantService.initialize();
          return tenantService;
        }),
        ChangeNotifierProvider(create: (_) => PaymentMethodService()),
        ChangeNotifierProvider(create: (_) => AppearanceService()),
        ChangeNotifierProvider(create: (_) => WindowZoomService()),
        ChangeNotifierProvider(create: (_) => RightToolbarService()),
        ChangeNotifierProvider(create: (_) {
          final navigationService = NavigationService();
          navigationService.initialize();
          return navigationService;
        }),
        ChangeNotifierProvider(create: (_) => WorkspaceManager()),

        // Messaging service (global for chat sidebar in all modules)
        Provider(create: (_) => MessagingService()),

        // Business services
        // Shared inventory service (used by POS)
        ChangeNotifierProvider(
            create: (context) => InventoryService(
                  db: Provider.of<DatabaseService>(context, listen: false),
                )),
        // Module inventory service (used by ProductListPage)
        ChangeNotifierProvider(
            create: (context) => module_inventory.InventoryService(
                  Provider.of<DatabaseService>(context, listen: false),
                  Provider.of<TenantService>(context, listen: false),
                )),
        ChangeNotifierProvider(
            create: (context) => CategoryService(
                  Provider.of<DatabaseService>(context, listen: false),
                  Provider.of<TenantService>(context, listen: false),
                )),
        ChangeNotifierProvider(
            create: (context) => BrandService(
                  Provider.of<DatabaseService>(context, listen: false),
                )),
        ChangeNotifierProvider(create: (_) => StockMovementsService()),
        ChangeNotifierProvider(create: (_) => NiimbotPrinterService()),
        ChangeNotifierProvider(
            create: (context) => CustomerService(
                  Provider.of<DatabaseService>(context, listen: false),
                  Provider.of<TenantService>(context, listen: false),
                )),
        ChangeNotifierProvider(
            create: (context) => BikeshopService(
                  Provider.of<DatabaseService>(context, listen: false),
                )),
        ChangeNotifierProvider(
            create: (context) => JobStatusService(
                  Provider.of<DatabaseService>(context, listen: false),
                )),
        ChangeNotifierProvider(create: (context) => WheelBuildingService()),
        ChangeNotifierProvider(
            create: (context) => SmartTaskService(
                  Provider.of<DatabaseService>(context, listen: false),
                )),
        ChangeNotifierProvider(
            create: (context) => AccountingService(
                  Provider.of<DatabaseService>(context, listen: false),
                )),
        ChangeNotifierProvider(
            create: (context) => FinancialReportsService(
                  Provider.of<DatabaseService>(context, listen: false),
                )),
        ChangeNotifierProvider(
            create: (context) => ExpenseService(
                  Provider.of<DatabaseService>(context, listen: false),
                )),
        ChangeNotifierProvider(create: (_) => F29Service()),
        ChangeNotifierProvider(
            create: (context) => PurchaseService(
                  Provider.of<DatabaseService>(context, listen: false),
                  Provider.of<TenantService>(context, listen: false),
                )),
        ChangeNotifierProvider.value(
            value:
                SmartPurchaseListService()), // Singleton - persists across app
        ChangeNotifierProvider(
            create: (context) => HRService(
                  Provider.of<TenantService>(context, listen: false),
                )),
        ChangeNotifierProvider(
            create: (context) => TaskService(
                  Supabase.instance.client,
                  Provider.of<TenantService>(context, listen: false),
                )),
        ChangeNotifierProvider(
            create: (context) => PayrollVoucherService(
                  Provider.of<DatabaseService>(context, listen: false),
                )),
        ChangeNotifierProvider(
            create: (context) => JobRoleService(
                  Provider.of<DatabaseService>(context, listen: false),
                )),
        Provider(
            create: (context) => UserManagementService(
                  Provider.of<TenantService>(context, listen: false),
                )),
        ChangeNotifierProvider(create: (_) => WebsiteService()),
        ChangeNotifierProvider(create: (_) => WebsiteEditModeProvider()),
        ChangeNotifierProvider(create: (_) => GoogleBusinessService()),
        // MercadoPago: Don't auto-initialize - checkout will init with proper tenant_id
        ChangeNotifierProvider(create: (_) => MercadoPagoService()),
        ChangeNotifierProvider(create: (_) => BackupService()),
        ChangeNotifierProvider(create: (_) => SpreadsheetService()),

        // User Management
        Provider(
          create: (context) =>
              UserManagementService(context.read<TenantService>()),
        ),

        // Public store services
        ChangeNotifierProvider(create: (_) => CartProvider()),
        ChangeNotifierProxyProvider<UserManagementService, ChatProvider>(
          create: (context) =>
              ChatProvider(context.read<UserManagementService>()),
          update: (context, userService, previous) =>
              previous ?? ChatProvider(userService),
        ),
        ChangeNotifierProvider(create: (_) => AddressAutocompleteService()),
        ChangeNotifierProvider(create: (_) => CustomerAccountService()),

        // Tenant detection for public store (subdomain-based routing)
        Provider(create: (_) => TenantDetectionService()),
        ChangeNotifierProvider(
          create: (context) => PublicStoreTenantProvider(
            context.read<TenantDetectionService>(),
          ),
        ),

        // Public inventory service (for anonymous users browsing the store)
        ChangeNotifierProvider(create: (_) => PublicInventoryService()),

        ChangeNotifierProxyProvider3<DatabaseService, AccountingService,
            TenantService, SalesService>(
          create: (context) => SalesService(
            context.read<DatabaseService>(),
            context.read<AccountingService>(),
            context.read<TenantService>(),
          ),
          update: (context, databaseService, accountingService, tenantService,
              previous) {
            final service = previous ??
                SalesService(databaseService, accountingService, tenantService);
            service.updateDependencies(databaseService, accountingService);
            return service;
          },
        ),

        // POS service depends on Inventory, Sales, PaymentMethod, and Tenant
        ChangeNotifierProxyProvider4<InventoryService, SalesService,
            PaymentMethodService, TenantService, POSService>(
          create: (context) => POSService(
            inventoryService: context.read<InventoryService>(),
            salesService: context.read<SalesService>(),
            paymentMethodService: context.read<PaymentMethodService>(),
            tenantService: context.read<TenantService>(),
          ),
          update: (context, inventoryService, salesService,
              paymentMethodService, tenantService, previous) {
            final service = previous ??
                POSService(
                  inventoryService: inventoryService,
                  salesService: salesService,
                  paymentMethodService: paymentMethodService,
                  tenantService: tenantService,
                );
            service.updateDependencies(
              inventoryService: inventoryService,
              salesService: salesService,
              paymentMethodService: paymentMethodService,
              tenantService: tenantService,
            );
            return service;
          },
        ),

        // Data preload service - preloads critical data after authentication
        ChangeNotifierProvider(create: (_) => DataPreloadService()),

        // Scanner Services
        ChangeNotifierProvider(create: (_) => BarcodeScannerService()),
        Provider(create: (_) => RemoteScannerService()),
      ],
      child: Builder(
        builder: (context) {
          // Initialize purchase service dependency
          final accountingService =
              Provider.of<AccountingService>(context, listen: false);
          PurchaseService.setAccountingService(accountingService);

          final isPublicStoreHost = _detectPublicStoreHost();

          // CRITICAL: Use context.watch() to rebuild when auth state changes
          final authService = context.watch<AuthService>();
          final appearanceService = context.watch<AppearanceService>();

          // PUBLIC STORE: Wait for tenant detection, then render app
          if (isPublicStoreHost) {
            final tenantProvider = context.watch<PublicStoreTenantProvider>();

            // Start tenant detection + data loading (ONLY ONCE)
            if (!tenantProvider.hasTenant &&
                !tenantProvider.isLoading &&
                !tenantProvider.hasError &&
                !_tenantDetectionStarted) {
              _tenantDetectionStarted = true; // Prevent duplicate triggers
              WidgetsBinding.instance.addPostFrameCallback((_) async {
                if (!context.mounted) return;
                _logTiming('TENANT_DETECT_START');
                await tenantProvider.detectTenant();
                if (!context.mounted) return;
                _logTiming('TENANT_DETECTED', tenantProvider.tenantId);

                // Load data in background - UNIFIED single query
                if (tenantProvider.tenantId != null) {
                  final tid = tenantProvider.tenantId!;
                  final ws = context.read<WebsiteService>();

                  _logTiming('DATA_LOAD_START');
                  await ws.loadPublicStoreDataUnified(tid);
                  _logTiming('ALL_DATA_LOADED');
                  if (kIsWeb) {
                    _hideLoadingScreen(); // Hide splash screen when data is ready
                  }
                }
              });
            }

            // Show loading while tenant is being detected
            if (tenantProvider.isLoading ||
                (!tenantProvider.hasTenant && !tenantProvider.hasError)) {
              return const MaterialApp(
                debugShowCheckedModeBanner: false,
                home: Scaffold(
                  backgroundColor: Colors.white,
                  body: Center(child: CircularProgressIndicator()),
                ),
              );
            }

            // Tenant detection failed
            if (tenantProvider.hasError) {
              if (kIsWeb) {
                _hideLoadingScreen(); // Fail safe: hide if error occurs
              }
              return MaterialApp(
                debugShowCheckedModeBanner: false,
                home: Scaffold(
                  backgroundColor: Colors.white,
                  body: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.store, size: 64, color: Colors.grey),
                        const SizedBox(height: 16),
                        Text(tenantProvider.error ?? 'Tienda no encontrada'),
                        const SizedBox(height: 24),
                        ElevatedButton(
                          onPressed: () => tenantProvider.retry(),
                          child: const Text('Reintentar'),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }

            // Tenant is ready - proceed to app (data loads in background)
          }

          // Initialize data preload service (preloads critical data after auth)
          // SKIP on public store AND for non-staff users - they don't need ERP data
          final dataPreloadService = context.read<DataPreloadService>();
          final shouldPreload = !isPublicStoreHost &&
              !dataPreloadService.hasPreloaded &&
              authService.isAuthenticated &&
              authService.isStaffProfileLoaded &&
              authService.isStaff; // Only preload for actual staff

          if (shouldPreload) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              dataPreloadService.initialize(
                bikeshopService: context.read<BikeshopService>(),
                categoryService: context.read<CategoryService>(),
                brandService: context.read<BrandService>(),
                purchaseService: context.read<PurchaseService>(),
                hrService: context.read<HRService>(),
                taskService: context.read<TaskService>(),
                isPublicStore: isPublicStoreHost, // Disable on public store
              );
            });
          }

          // NOTE: Removed reloadSettings call from here - it caused infinite loops
          // for customers (hasLoadedWithTenant is always false for them).
          // AppearanceService already listens to auth changes and reloads automatically.

          // Show loading screen while:
          // 1. Auth is initializing, OR
          // 2. User is authenticated but staff profile check hasn't completed yet
          // This prevents the flicker where customers briefly see Workspace before redirect
          final isWaitingForStaffCheck =
              authService.isAuthenticated && !authService.isStaffProfileLoaded;

          if ((authService.isInitializing || isWaitingForStaffCheck) &&
              !isPublicStoreHost) {
            return MaterialApp(
              title: 'Vinabike',
              theme: AppTheme.lightTheme,
              darkTheme: AppTheme.darkTheme,
              themeMode: appearanceService.themeMode,
              home: const Scaffold(
                body: BrandedLoadingOverlay(message: 'Cargando...'),
              ),
            );
          }

          // Public store or not authenticated = single router
          // Also force non-staff users (customers) to use this router to show Access Denied
          // This prevents building the Workspace System for unauthorized users
          if (isPublicStoreHost ||
              !authService.isAuthenticated ||
              (authService.isStaffProfileLoaded && !authService.isStaff)) {
            // Use the URL captured at startup (before usePathUrlStrategy modified it)
            // This is critical for MercadoPago redirects and direct URL navigation
            final initialLocationOverride = () {
              if (kIsWeb && _initialBrowserUrl != null) {
                final uri = Uri.parse(_initialBrowserUrl!);
                debugPrint(
                    '🔍 [Main] Using captured initial URL: $_initialBrowserUrl');
                return uri
                    .toString(); // Just pass the full URL string (or path+query)
              }
              return null;
            }();

            return VinabikePublicRouterApp(
              key: const ValueKey('PublicRouter'),
              authService: authService,
              appearanceService: appearanceService,
              isPublicStoreHost: isPublicStoreHost,
              initialUrl: initialLocationOverride,
            );
          }

          // Authenticated = workspace system with OUTER Material context
          debugPrint('✅ [Main] User is AUTHENTICATED - using WORKSPACE SYSTEM');

          return MaterialApp(
            title: 'Vinabike',
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: appearanceService.themeMode,
            scrollBehavior: AppScrollBehavior(),
            debugShowCheckedModeBanner: false,
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: const [
              Locale('es', ''),
              Locale('en', ''),
            ],
            locale: const Locale('es', ''),
            builder: (context, child) => WindowZoomScope(
              child: ScannerBridgeScope(
                child: child ?? const SizedBox.shrink(),
              ),
            ),
            home: Selector<WorkspaceManager, bool>(
              selector: (_, wm) => wm.workspaces.isEmpty,
              builder: (context, isEmpty, _) {
                // Check if workspaces are initialized
                if (isEmpty) {
                  debugPrint(
                      '⚠️ [Main] WorkspaceManager has no workspaces yet, showing loading...');
                  return const Scaffold(
                    body: BrandedLoadingOverlay(
                        message: 'Cargando espacios de trabajo...'),
                  );
                }

                // Scaffold and tab bar are stable - only IndexedStack rebuilds with workspace changes
                return Scaffold(
                  body: Stack(
                    children: [
                      SafeArea(
                        bottom:
                            false, // Only add top padding for iOS status bar
                        child: Column(
                          children: [
                            // Tab bar has its own internal Consumer, stable during rebuilds
                            const WorkspaceTabBar(),
                            // Only this part needs to rebuild on workspace changes
                            Expanded(
                              child: Selector<WorkspaceManager,
                                  (int, List<String>, bool)>(
                                selector: (_, wm) => (
                                  wm.activeIndex,
                                  wm.workspaces.map((w) => w.id).toList(),
                                  wm.isAIPanelOpen,
                                ),
                                builder: (context, data, _) {
                                  final workspaceManager =
                                      context.read<WorkspaceManager>();

                                  // Use a Row so the workspace pane stays at
                                  // index 0 regardless of AI panel state. This
                                  // prevents the IndexedStack (and its child
                                  // Routers) from being destroyed and recreated
                                  // every time the AI panel is toggled.
                                  return Row(
                                    children: [
                                      Expanded(
                                        // SelectionArea works here (no Overlay
                                        // wrapper needed) because we are already
                                        // inside the outer MaterialApp Navigator's
                                        // own Overlay.
                                        child: SelectionArea(
                                          child: IndexedStack(
                                            index: data.$1,
                                            sizing: StackFit.expand,
                                            children: workspaceManager
                                                .workspaces
                                                .map((workspace) {
                                              return _WorkspaceRouterView(
                                                key: ValueKey(workspace.id),
                                                workspace: workspace,
                                                authService: authService,
                                              );
                                            }).toList(),
                                          ),
                                        ),
                                      ),
                                      // Right panel – only mounted when open, but
                                      // its addition/removal never shifts the
                                      // workspace pane above.
                                      if (data.$3)
                                        SelectionArea(
                                          child: Container(
                                            width: 400,
                                            decoration: BoxDecoration(
                                              color: Theme.of(context)
                                                  .scaffoldBackgroundColor,
                                              border: Border(
                                                left: BorderSide(
                                                    color: Theme.of(context)
                                                        .dividerColor),
                                              ),
                                            ),
                                            child: const AIChatPanel(jobs: []),
                                          ),
                                        ),
                                    ],
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                      const QueryPerformanceGauge(),
                    ],
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class _WorkspaceRouterView extends StatefulWidget {
  final Workspace workspace;
  final AuthService authService;

  const _WorkspaceRouterView({
    required super.key,
    required this.workspace,
    required this.authService,
  });

  @override
  State<_WorkspaceRouterView> createState() => _WorkspaceRouterViewState();
}

class _WorkspaceRouterViewState extends State<_WorkspaceRouterView>
    with AutomaticKeepAliveClientMixin {
  late GoRouter _router;
  StreamSubscription<String>? _notificationTapSubscription;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();

    debugPrint(
        '🎯 [WorkspaceRouterView] Creating router for workspace: ${widget.workspace.title} with route: ${widget.workspace.initialRoute}');

    // Create the router with an explicit initial location for this workspace.
    // This avoids post-frame .go() calls that can cause extra navigation cycles.
    _router = AppRouter.createRouter(
      widget.authService,
      initialLocationOverride: widget.workspace.currentRoute,
    );

    // Save the router reference to the workspace object so external UI
    // (like global floating buttons) can trigger navigation on the active tab
    widget.workspace.router = _router;

    // Listen for notification taps to navigate to specific chats
    // Only handle if this is the active workspace
    _notificationTapSubscription =
        NotificationService().onNotificationTap.listen((route) {
      final workspaceManager =
          Provider.of<WorkspaceManager>(context, listen: false);
      final myIndex = workspaceManager.workspaces.indexOf(widget.workspace);

      // Only navigate if this workspace is the active one
      if (myIndex == workspaceManager.activeIndex) {
        debugPrint(
            '🔔 [WorkspaceRouterView] Notification tap → navigating to: $route');
        try {
          _router.go(route);
        } catch (e) {
          debugPrint(
              '❌ [WorkspaceRouterView] Notification navigation error: $e');
        }
      }
    });
  }

  @override
  void dispose() {
    _notificationTapSubscription?.cancel();
    _router.dispose();
    super.dispose();
  }

  final _toolbarKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    super.build(context);

    try {
      return Row(
        children: [
          Expanded(child: Router.withConfig(config: _router)),
          RightToolbar(key: _toolbarKey),
        ],
      );
    } catch (e) {
      debugPrint('🔴 [WorkspaceRouterView] Router build error: $e');
      return Material(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error, color: Colors.red, size: 48),
              const SizedBox(height: 16),
              Text('Navigation Error: $e'),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () {
                  // Try to recreate router
                  setState(() {
                    _router = AppRouter.createRouter(widget.authService);
                  });
                },
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }
  }
}

bool _detectPublicStoreHost() {
  // Development: Check for FORCE_SUBDOMAIN environment variable
  const forceSubdomain = String.fromEnvironment('FORCE_SUBDOMAIN');
  if (forceSubdomain.isNotEmpty) {
    debugPrint(
        '🧪 [Main] FORCE_SUBDOMAIN=$forceSubdomain → treating as public store host');
    return true;
  }

  if (!kIsWeb) {
    return false;
  }

  final host = Uri.base.host.toLowerCase();
  return host == 'vinabike-store.web.app' ||
      host == 'vinabike-store.firebaseapp.com' ||
      host == 'vinabike.cl' ||
      host == 'www.vinabike.cl';
}
