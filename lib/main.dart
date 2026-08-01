import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'firebase_options.dart';
import 'shared/services/notification_service.dart';
import 'shared/services/mail_notification_gate.dart';
import 'shared/services/chat_notification_gate.dart';
import 'shared/services/erp_notification_gate.dart';

import 'shared/themes/app_theme.dart';
import 'shared/themes/workspace_chrome_theme.dart';
import 'shared/services/auth_service.dart';
import 'shared/services/database_service.dart';
import 'shared/services/inventory_service.dart';
import 'shared/services/payment_method_service.dart';
import 'shared/services/navigation_service.dart';
import 'shared/services/tenant_service.dart';
import 'shared/models/current_user_profile.dart';
import 'shared/services/current_user_profile_service.dart';
import 'shared/services/employee_self_service_service.dart';
import 'shared/services/user_management_service.dart';
import 'shared/services/workspace_manager.dart';
import 'shared/config/supabase_config.dart';
import 'shared/widgets/workspace_tab_bar.dart';
import 'shared/widgets/workspace_shell_scope.dart';
import 'shared/utils/web_url.dart';
import 'shared/utils/notification_deep_link.dart';
import 'shared/utils/trusted_meta_notification_url.dart';
import 'modules/inventory/services/category_service.dart';
import 'modules/inventory/services/inventory_service.dart' as module_inventory;
import 'modules/inventory/services/brand_service.dart';
import 'modules/inventory/services/stock_movements_service.dart';
import 'modules/crm/services/customer_service.dart';
import 'modules/accounting/services/accounting_service.dart';
import 'modules/accounting/services/financial_projection_refresh_coordinator.dart';
import 'modules/accounting/services/financial_projection_realtime_transport.dart';
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
import 'modules/messaging/utils/conversation_channel_presentation.dart';
import 'modules/mail/providers/email_provider.dart';
import 'modules/mail/providers/mail_account_manager.dart';
import 'public_store/services/customer_account_service.dart';
import 'public_store/services/address_autocomplete_service.dart';
import 'public_store/services/checkout_exit_guard.dart';
import 'public_store/services/checkout_session_store.dart';
import 'public_store/services/public_inventory_service.dart';
import 'shared/routes/app_router.dart';
import 'shared/services/data_preload_service.dart';
import 'shared/services/error_reporting_service.dart';
import 'shared/services/tenant_detection_service.dart';
import 'shared/services/backup_service.dart';
import 'modules/spreadsheets/services/spreadsheet_service.dart';
import 'modules/ai_assistant/services/ai_assistant_context_service.dart';
import 'shared/services/window_zoom_service.dart';
import 'shared/services/right_toolbar_service.dart';
import 'shared/utils/responsive_viewport.dart';
import 'shared/services/ocr_file_handoff_service.dart';
import 'shared/services/smart_screenshot_service.dart';
import 'shared/services/desktop_update_service.dart';
import 'shared/services/android_update_service.dart';
import 'shared/widgets/window_zoom_scope.dart';
import 'shared/widgets/branded_loading.dart';
import 'shared/widgets/desktop_update_prompt.dart';
import 'shared/widgets/android_update_prompt.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'shared/services/remote_scanner_service.dart';
import 'shared/services/barcode_scanner_service.dart';
import 'shared/widgets/scanner_bridge_scope.dart';
import 'shared/widgets/right_toolbar.dart';
import 'shared/widgets/query_performance_gauge.dart';
import 'public_router_app.dart';
import 'shared/services/deep_link_handler.dart';
import 'shared/services/route_share_service.dart';
import 'dev/agent_input.dart';

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
    AuthService.captureInitialUrl(_initialBrowserUrl);
    CustomerAccountService.captureInitialUrl(_initialBrowserUrl);
    // Capture OAuth codes if present to prevent router from cleaning them
    captureZohoOAuthCode();
    captureGmailOAuthCode();
  }
  _logTiming('URL_CAPTURED');

  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    _logTiming('FLUTTER_BINDING');

    // Debug-only: lets an agent drive the app through synthetic pointer events
    // instead of moving the owner's real cursor. No-op outside debug.
    registerAgentInputExtensions();

    // **La barra de estado la pinta la app, no el sistema.**
    //
    // Desde Android 15 (API 35) el modo edge-to-edge es obligatorio y
    // `Window.setStatusBarColor` —que es lo que hay debajo de
    // `SystemUiOverlayStyle.statusBarColor`— quedó **ignorado**. Por eso el
    // arreglo del 31/07 no cambió nada en el teléfono: le pedía al sistema un
    // color que el sistema ya no acepta, y encima de la franja transparente se
    // veía el `windowBackground` del tema Android, que en claro es blanco.
    //
    // Con edge-to-edge la app puede dibujarse DEBAJO de la barra. El inset
    // superior debe seguir disponible hasta el `AppBar` del shell para que
    // éste extienda su canvas semántico hasta y=0; consumirlo antes con un
    // `SafeArea` vuelve a dejar visible el fondo claro del host. El color
    // sigue viajando en el overlay style para Android antiguos y el brillo de
    // los iconos sigue siendo dinámico. Esta configuración es Android-only:
    // iOS y macOS conservan su dueño nativo del system chrome.
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }

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
      } else if (!_supportsFirebaseInitialization()) {
        debugPrint(
            'ℹ️ [Main] Firebase initialization skipped on ${defaultTargetPlatform.name}');
        _logTiming('FIREBASE_INIT_SKIPPED', defaultTargetPlatform.name);
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
      if (ErrorReportingService.shouldSuppress(errorString)) {
        return; // Don't report or dump known framework/layout noise
      }
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
    if (ErrorReportingService.shouldSuppress(errorString)) {
      return; // Don't report known framework/layout noise
    }
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
        ChangeNotifierProxyProvider2<AuthService, TenantService,
            CurrentUserProfileService>(
          create: (_) => CurrentUserProfileService(),
          update: (_, authService, tenantService, currentUserProfile) {
            final service = currentUserProfile ?? CurrentUserProfileService();
            final user = authService.currentUser;
            unawaited(
              service.synchronize(
                identity:
                    user == null ? null : CurrentUserIdentity.fromUser(user),
                resolveTenantId: tenantService.getTenantId,
              ),
            );
            return service;
          },
        ),
        ChangeNotifierProxyProvider<CurrentUserProfileService,
            EmployeeSelfServiceService>(
          lazy: true,
          create: (_) => EmployeeSelfServiceService(),
          update: (_, currentUserProfile, selfService) {
            final service = selfService ?? EmployeeSelfServiceService();
            unawaited(
              service.synchronize(profile: currentUserProfile.profile),
            );
            return service;
          },
        ),
        ProxyProvider<TenantService, FinancialProjectionRefreshCoordinator>(
          create: (_) => FinancialProjectionRefreshCoordinator(
            realtimeTransport: SupabaseFinancialProjectionRealtimeTransport(
              Supabase.instance.client,
            ),
          ),
          update: (_, tenantService, coordinator) {
            final value = coordinator ??
                FinancialProjectionRefreshCoordinator(
                  realtimeTransport:
                      SupabaseFinancialProjectionRealtimeTransport(
                    Supabase.instance.client,
                  ),
                );
            unawaited(value.synchronizeTenantFrom(tenantService));
            return value;
          },
          dispose: (_, coordinator) => coordinator.dispose(),
        ),
        ChangeNotifierProvider(create: (_) => PaymentMethodService()),
        ChangeNotifierProxyProvider2<AuthService, TenantService,
            AppearanceService>(
          create: (_) => AppearanceService(),
          update: (_, authService, tenantService, appearanceService) {
            final service = appearanceService ?? AppearanceService();
            unawaited(
              service.synchronize(
                userId: authService.currentUser?.id,
                resolveTenantId: tenantService.getTenantId,
              ),
            );
            return service;
          },
        ),
        ChangeNotifierProvider(create: (_) => WindowZoomService()),
        ChangeNotifierProvider(create: (_) => RightToolbarService()),
        ChangeNotifierProvider(create: (_) => AIAssistantContextService()),
        ChangeNotifierProvider(create: (_) => OcrFileHandoffService()),
        ChangeNotifierProvider(create: (_) => SmartScreenshotService()),
        ChangeNotifierProvider(create: (_) => DesktopUpdateService()),
        ChangeNotifierProvider(create: (_) => AndroidUpdateService()),
        ChangeNotifierProvider(create: (_) {
          final navigationService = NavigationService();
          navigationService.initialize();
          return navigationService;
        }),
        ChangeNotifierProxyProvider<AuthService, WorkspaceManager>(
          create: (_) => WorkspaceManager(
            initialBrowserUrl: _initialBrowserUrl,
            sessionIdentity: Supabase.instance.client.auth.currentUser?.id,
          ),
          update: (_, authService, workspaceManager) {
            final manager = workspaceManager ??
                WorkspaceManager(
                  initialBrowserUrl: _initialBrowserUrl,
                  sessionIdentity: authService.currentUser?.id,
                );
            unawaited(
              manager.setSessionIdentity(authService.currentUser?.id),
            );
            return manager;
          },
        ),

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
                  financialProjectionRefresh:
                      context.read<FinancialProjectionRefreshCoordinator>(),
                )),
        ChangeNotifierProvider(
            create: (context) => FinancialReportsService(
                  Provider.of<DatabaseService>(context, listen: false),
                )),
        ChangeNotifierProvider(
            create: (context) => ExpenseService(
                  Provider.of<DatabaseService>(context, listen: false),
                  financialProjectionRefresh:
                      context.read<FinancialProjectionRefreshCoordinator>(),
                )),
        ChangeNotifierProvider(create: (_) => F29Service()),
        ChangeNotifierProvider(
            create: (context) => PurchaseService(
                  Provider.of<DatabaseService>(context, listen: false),
                  Provider.of<TenantService>(context, listen: false),
                  financialProjectionRefresh:
                      context.read<FinancialProjectionRefreshCoordinator>(),
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
                  financialProjectionRefresh:
                      context.read<FinancialProjectionRefreshCoordinator>(),
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
        ChangeNotifierProvider(create: (_) => CheckoutExitGuard()),
        Provider(create: (_) => CheckoutSessionStore.platform()),
        ChangeNotifierProxyProvider2<UserManagementService, TenantService,
            ChatProvider>(
          create: (context) => ChatProvider(
            context.read<UserManagementService>(),
            context.read<TenantService>(),
          ),
          update: (context, userService, tenantService, previous) {
            final provider =
                previous ?? ChatProvider(userService, tenantService);
            unawaited(provider.synchronizeSessionScope());
            return provider;
          },
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

        ChangeNotifierProxyProvider4<DatabaseService, AccountingService,
            TenantService, FinancialProjectionRefreshCoordinator, SalesService>(
          create: (context) => SalesService(
            context.read<DatabaseService>(),
            context.read<AccountingService>(),
            context.read<TenantService>(),
            financialProjectionRefresh:
                context.read<FinancialProjectionRefreshCoordinator>(),
          ),
          update: (
            context,
            databaseService,
            accountingService,
            tenantService,
            financialProjectionRefresh,
            previous,
          ) {
            final service = previous ??
                SalesService(
                  databaseService,
                  accountingService,
                  tenantService,
                  financialProjectionRefresh: financialProjectionRefresh,
                );
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
          final currentUserProfileService =
              context.watch<CurrentUserProfileService>();
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
          final preloadAuthorityTenantId =
              currentUserProfileService.profile?.tenantId;
          final shouldPreload = !isPublicStoreHost &&
              authService.isAuthenticated &&
              !authService.isWorkerPortalAuthUser &&
              !authService.isWorker &&
              authService.isStaffProfileLoaded &&
              authService.isStaff &&
              !currentUserProfileService.isLoading &&
              currentUserProfileService.loadIssue == null &&
              preloadAuthorityTenantId != null &&
              (!dataPreloadService.hasPreloaded ||
                  dataPreloadService.authorityTenantId !=
                      preloadAuthorityTenantId);

          if (shouldPreload) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              dataPreloadService.initialize(
                bikeshopService: context.read<BikeshopService>(),
                categoryService: context.read<CategoryService>(),
                brandService: context.read<BrandService>(),
                purchaseService: context.read<PurchaseService>(),
                authorityTenantId: preloadAuthorityTenantId,
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
              authService.isWorkerPortalAuthUser ||
              authService.isWorker ||
              (authService.isStaffProfileLoaded && !authService.isStaff)) {
            // Use the URL captured at startup (before usePathUrlStrategy modified it)
            // This is critical for MercadoPago redirects and direct URL navigation
            final initialLocationOverride = () {
              const debugInitialRoute =
                  String.fromEnvironment('DEBUG_INITIAL_ROUTE');
              if (debugInitialRoute.isNotEmpty) {
                debugPrint(
                  '🔍 [Main] Using debug initial route: $debugInitialRoute',
                );
                return debugInitialRoute;
              }
              if (kIsWeb && _initialBrowserUrl != null) {
                final uri = Uri.parse(_initialBrowserUrl!);
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
            // Canonical authenticated ERP theme owner. Public store and
            // unauthenticated router hosts retain their separate theme
            // boundaries.
            theme: AppTheme.resolve(
              preset: appearanceService.appearancePreset,
              brightness: Brightness.light,
            ),
            darkTheme: AppTheme.resolve(
              preset: appearanceService.appearancePreset,
              brightness: Brightness.dark,
            ),
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
                child: RepaintBoundary(
                  key:
                      context.read<SmartScreenshotService>().captureBoundaryKey,
                  child: child ?? const SizedBox.shrink(),
                ),
              ),
            ),
            home: _WorkspaceDeepLinkBridge(
              child: Selector<WorkspaceManager, bool>(
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

                  return Scaffold(
                    body: Stack(
                      children: [
                        // Do not consume the top system inset here. The
                        // compact MainLayout AppBar is the single owner that
                        // both paints behind the status bar and positions its
                        // toolbar below it. An outer SafeArea would erase the
                        // descendant MediaQuery.padding.top and expose this
                        // Scaffold's light canvas above the navy header.
                        _WorkspaceShell(
                          key: const ValueKey(
                            'authenticated-workspace-shell',
                          ),
                          authService: authService,
                        ),
                        const QueryPerformanceGauge(),
                        const DesktopUpdatePrompt(),
                        const AndroidUpdatePrompt(),
                      ],
                    ),
                  );
                },
              ),
            ),
          );
        },
      ),
    );
  }
}

bool _supportsFirebaseInitialization() {
  if (kIsWeb) return true;

  switch (defaultTargetPlatform) {
    case TargetPlatform.android:
    case TargetPlatform.iOS:
    case TargetPlatform.windows:
      return true;
    case TargetPlatform.macOS:
    case TargetPlatform.linux:
    case TargetPlatform.fuchsia:
      return false;
  }
}

class _WorkspaceDeepLinkBridge extends StatefulWidget {
  final Widget child;

  const _WorkspaceDeepLinkBridge({required this.child});

  @override
  State<_WorkspaceDeepLinkBridge> createState() =>
      _WorkspaceDeepLinkBridgeState();
}

class _WorkspaceDeepLinkBridgeState extends State<_WorkspaceDeepLinkBridge>
    with WidgetsBindingObserver {
  StreamSubscription<String>? _routeSubscription;
  StreamSubscription<RemoteMessage>? _workspacePushSubscription;
  StreamSubscription<Email>? _newEmailSubscription;
  StreamSubscription<AuthState>? _authStateSubscription;
  OverlayEntry? _workspaceAlertOverlay;
  Timer? _workspaceAlertTimer;
  Timer? _erpNotificationsRefreshTimer;
  RealtimeChannel? _erpNotificationsChannel;
  late final WorkspaceManager _workspaceManager;
  bool _isWorkspaceForeground = true;
  bool _erpNotificationsRefreshInFlight = false;
  int _notificationLifecycleEpoch = 0;
  String? _notificationUserId;

  @override
  void initState() {
    super.initState();
    _workspaceManager = context.read<WorkspaceManager>();
    WidgetsBinding.instance.addObserver(this);

    final notificationService = NotificationService();
    notificationService.setForegroundPresentationPolicy(
      this,
      _shouldPresentForegroundMessage,
    );
    _workspacePushSubscription =
        notificationService.messageStream.listen(_handleWorkspacePush);
    _newEmailSubscription =
        MailAccountManager.instance.newEmailStream.listen(_handleNewEmail);
    _authStateSubscription = Supabase.instance.client.auth.onAuthStateChange
        .listen(_handleNotificationAuthState);
    _restartNotificationLifecycle(
      Supabase.instance.client.auth.currentUser?.id,
    );

    if (kIsWeb) return;

    final handler = DeepLinkHandler.instance;
    _routeSubscription = handler.routeLinks.listen(_openSharedRoute);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final pendingRoute = handler.takePendingRoute();
      if (pendingRoute != null) {
        _openSharedRoute(pendingRoute);
      }
    });
  }

  @override
  void dispose() {
    _notificationLifecycleEpoch++;
    _notificationUserId = null;
    _erpNotificationsRefreshInFlight = false;
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_workspaceManager.flushBrowserSession());
    _routeSubscription?.cancel();
    _workspacePushSubscription?.cancel();
    _newEmailSubscription?.cancel();
    _authStateSubscription?.cancel();
    _workspaceAlertTimer?.cancel();
    _workspaceAlertOverlay?.remove();
    _erpNotificationsRefreshTimer?.cancel();
    _erpNotificationsChannel?.unsubscribe();
    _erpNotificationsChannel = null;
    ChatNotificationGate.shared.clearScope();
    MailNotificationGate.shared.clearScope();
    ErpNotificationGate.shared.clearScope();
    NotificationService().clearNotificationScope();
    unawaited(MailAccountManager.instance.reset());
    NotificationService().clearForegroundPresentationPolicy(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _isWorkspaceForeground = true;
      context.read<ChatProvider>().setApplicationForeground(true);
      context
          .read<FinancialProjectionRefreshCoordinator>()
          .setApplicationActive(true);
      unawaited(MailAccountManager.instance.backgroundRefresh());
    }
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden) {
      _isWorkspaceForeground = false;
      context.read<ChatProvider>().setApplicationForeground(false);
      context
          .read<FinancialProjectionRefreshCoordinator>()
          .setApplicationActive(false);
      unawaited(_workspaceManager.flushBrowserSession());
    }
  }

  bool _shouldPresentForegroundMessage(RemoteMessage message) {
    if (!_isWorkspaceForeground) return true;

    final data = message.data;
    final isMailNotification = data['type'] == 'mail' ||
        data['notification_type'] == 'mail' ||
        data['route'] == '/mail';
    if (isMailNotification) return true;
    if (data['type']?.toString() == 'system') return false;

    final route = data['route']?.toString();
    final routeUri = route == null ? null : Uri.tryParse(route);
    final conversationId = (data['conversation_id'] ??
            data['chat_id'] ??
            routeUri?.queryParameters['conversation'])
        ?.toString()
        .trim();
    if (conversationId == null || conversationId.isEmpty) return true;

    return !context.read<ChatProvider>().isConversationVisible(conversationId);
  }

  void _handleNotificationAuthState(AuthState state) {
    final userId = state.session?.user.id;
    if (userId == _notificationUserId && userId != null) return;
    _restartNotificationLifecycle(userId);
  }

  void _restartNotificationLifecycle(String? userId) {
    final epoch = ++_notificationLifecycleEpoch;
    _notificationUserId = userId;
    _erpNotificationsRefreshInFlight = false;
    _erpNotificationsRefreshTimer?.cancel();
    _erpNotificationsRefreshTimer = null;
    final oldChannel = _erpNotificationsChannel;
    _erpNotificationsChannel = null;
    if (oldChannel != null) unawaited(oldChannel.unsubscribe());

    ChatNotificationGate.shared.clearScope();
    MailNotificationGate.shared.clearScope();
    ErpNotificationGate.shared.clearScope();
    NotificationService().clearNotificationScope();

    if (userId == null) {
      unawaited(MailAccountManager.instance.reset());
      return;
    }
    unawaited(_initializeNotificationLifecycle(userId, epoch));
  }

  Future<void> _initializeNotificationLifecycle(
    String userId,
    int epoch,
  ) async {
    try {
      await MailAccountManager.instance.prepareSession(userId);
      if (!_isCurrentNotificationLifecycle(userId, epoch)) return;

      final tenantId = await TenantService().getTenantId();
      if (!_isCurrentNotificationLifecycle(userId, epoch) ||
          tenantId == null ||
          tenantId.isEmpty) {
        return;
      }

      ChatNotificationGate.shared.activateScope(
        userId: userId,
        tenantId: tenantId,
      );
      MailNotificationGate.shared.activateScope(
        userId: userId,
        tenantId: tenantId,
      );
      ErpNotificationGate.shared.activateScope(
        userId: userId,
        tenantId: tenantId,
      );
      NotificationService().activateNotificationScope(
        userId: userId,
        tenantId: tenantId,
      );

      await MailAccountManager.instance.initialize();
      if (!_isCurrentNotificationLifecycle(userId, epoch)) return;

      await _refreshErpNotifications(
        userId: userId,
        tenantId: tenantId,
        epoch: epoch,
        seedBaseline: true,
      );
      if (!_isCurrentNotificationLifecycle(userId, epoch)) return;

      _erpNotificationsRefreshTimer = Timer.periodic(
        const Duration(seconds: 20),
        (_) => unawaited(
          _refreshErpNotifications(
            userId: userId,
            tenantId: tenantId,
            epoch: epoch,
          ),
        ),
      );
      await _subscribeErpNotifications(
        userId: userId,
        tenantId: tenantId,
        epoch: epoch,
      );
    } catch (error) {
      debugPrint(
        '🔔 [WorkspaceShell] Notification lifecycle initialization failed: $error',
      );
    }
  }

  bool _isCurrentNotificationLifecycle(String userId, int epoch) {
    return mounted &&
        epoch == _notificationLifecycleEpoch &&
        _notificationUserId == userId &&
        Supabase.instance.client.auth.currentUser?.id == userId;
  }

  Future<void> _subscribeErpNotifications({
    required String userId,
    required String tenantId,
    required int epoch,
  }) async {
    if (!_isCurrentNotificationLifecycle(userId, epoch)) return;

    final previousChannel = _erpNotificationsChannel;
    _erpNotificationsChannel = null;
    if (previousChannel != null) await previousChannel.unsubscribe();
    if (!_isCurrentNotificationLifecycle(userId, epoch)) return;

    late final RealtimeChannel channel;
    channel = Supabase.instance.client
        .channel('workspace-erp-notifications-$userId-$tenantId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'erp_notifications',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'tenant_id',
            value: tenantId,
          ),
          callback: (payload) => _handleErpNotificationRecord(
            payload.newRecord,
            userId: userId,
            tenantId: tenantId,
            epoch: epoch,
            allowPresentation: true,
          ),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'erp_notifications',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'tenant_id',
            value: tenantId,
          ),
          callback: (payload) => _handleErpNotificationRecord(
            payload.newRecord,
            userId: userId,
            tenantId: tenantId,
            epoch: epoch,
            allowPresentation: false,
          ),
        )
        .subscribe((status, error) {
      if (!_isCurrentNotificationLifecycle(userId, epoch)) return;
      if (status == RealtimeSubscribeStatus.subscribed) {
        unawaited(
          _refreshErpNotifications(
            userId: userId,
            tenantId: tenantId,
            epoch: epoch,
          ),
        );
      } else if (status == RealtimeSubscribeStatus.channelError ||
          status == RealtimeSubscribeStatus.timedOut) {
        debugPrint(
          '🔔 [WorkspaceShell] ERP notifications realtime issue: $error',
        );
      }
    });

    if (!_isCurrentNotificationLifecycle(userId, epoch)) {
      await channel.unsubscribe();
      return;
    }
    _erpNotificationsChannel = channel;
  }

  Future<void> _refreshErpNotifications({
    required String userId,
    required String tenantId,
    required int epoch,
    bool seedBaseline = false,
  }) async {
    if (!_isCurrentNotificationLifecycle(userId, epoch) ||
        _erpNotificationsRefreshInFlight) {
      return;
    }

    _erpNotificationsRefreshInFlight = true;
    try {
      final notificationService = NotificationService();
      final onlineOrderRows =
          await notificationService.loadOnlineOrderAlerts(tenantId);
      if (!_isCurrentNotificationLifecycle(userId, epoch)) return;
      final rows = await notificationService.loadNotifications(tenantId);
      if (!_isCurrentNotificationLifecycle(userId, epoch)) return;

      final ids = [...onlineOrderRows, ...rows]
          .map((row) => row['id']?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .map((id) => 'erp:$id');
      if (seedBaseline) {
        ErpNotificationGate.shared.rememberBaseline(ids);
        return;
      }

      Map<String, dynamic>? newestUnseen;
      for (final row in rows.reversed) {
        if (row['read_at'] != null) continue;
        final id = row['id']?.toString() ?? '';
        if (ErpNotificationGate.shared.claimPresentation('erp:$id')) {
          newestUnseen = row;
        }
      }
      if (newestUnseen != null) {
        _presentErpNotification(newestUnseen);
      }
    } catch (error) {
      debugPrint(
          '🔔 [WorkspaceShell] ERP notifications refresh failed: $error');
    } finally {
      if (epoch == _notificationLifecycleEpoch) {
        _erpNotificationsRefreshInFlight = false;
      }
    }
  }

  void _handleErpNotificationRecord(
    Map<String, dynamic> record, {
    required String userId,
    required String tenantId,
    required int epoch,
    required bool allowPresentation,
  }) {
    if (!_isCurrentNotificationLifecycle(userId, epoch) ||
        record['tenant_id']?.toString() != tenantId) {
      return;
    }

    final notificationService = NotificationService();
    notificationService.recordNotification(record);
    final type = record['type']?.toString();
    final id = record['id']?.toString() ?? '';
    if (type == 'online_order_created') {
      notificationService.recordOnlineOrderAlert(id, notification: record);
    }
    if (!allowPresentation || record['read_at'] != null) return;
    if (!ErpNotificationGate.shared.claimPresentation('erp:$id')) return;
    _presentErpNotification(record);
  }

  void _presentErpNotification(Map<String, dynamic> record) {
    final type = record['type']?.toString();
    final id = record['id']?.toString() ?? '';
    final isMail = type == 'mail' ||
        record['notification_type']?.toString() == 'mail' ||
        record['route']?.toString() == '/mail';
    if (isMail && !MailNotificationGate.shared.claimPresentation('erp:$id')) {
      return;
    }

    _showWorkspaceAlert(
      title: record['title']?.toString() ?? 'Nueva notificación',
      body: record['body']?.toString() ?? '',
      icon: _iconForErpNotification(type),
      route: resolveErpNotificationRoute(record),
      category:
          isMail ? NotificationCategory.email : NotificationCategory.general,
      suppressRoutePrefix: type == 'online_order_created'
          ? '/website/orders'
          : isMail
              ? '/mail'
              : null,
      showSystemNotification: !_isWorkspaceForeground && !kIsWeb,
      notificationId: 'erp:$id'.hashCode,
    );
  }

  IconData _iconForErpNotification(String? type) {
    if (type?.startsWith('meta_instagram_') == true) {
      return ConversationChannelPresentation.iconForChannel('instagram');
    }
    if (type?.startsWith('meta_facebook_') == true) {
      return ConversationChannelPresentation.iconForChannel(
        'facebook_messenger',
      );
    }
    switch (type) {
      case 'mechanic_job_created':
        return Icons.build_outlined;
      case 'sales_payment_received':
        return Icons.payments_outlined;
      case 'expense_recorded':
        return Icons.receipt_long_outlined;
      case 'online_order_created':
        return Icons.shopping_cart_checkout_outlined;
      case 'whatsapp_catalog_approved':
        return Icons.verified_outlined;
      case 'mail':
        return Icons.email_outlined;
      default:
        return Icons.notifications_outlined;
    }
  }

  void _handleWorkspacePush(RemoteMessage message) {
    final data = message.data;
    final isMailNotification = data['type'] == 'mail' ||
        data['notification_type'] == 'mail' ||
        data['route'] == '/mail';
    if (isMailNotification) {
      _handleMailPush(message);
      return;
    }

    _handleChatPush(message);
  }

  void _handleChatPush(RemoteMessage message) {
    if (!mounted) return;
    final data = message.data;
    if (data['type']?.toString() == 'system') return;

    final route = data['route']?.toString();
    final routeUri = route == null ? null : Uri.tryParse(route);
    final conversationId = (data['conversation_id'] ??
            data['chat_id'] ??
            routeUri?.queryParameters['conversation'])
        ?.toString()
        .trim();
    if (conversationId == null || conversationId.isEmpty) return;

    final notificationService = NotificationService();
    if (!notificationService
        .notificationsEnabledFor(NotificationCategory.message)) {
      return;
    }

    final createdAt = data['created_at']?.toString().trim() ?? '';
    final content =
        (data['content'] ?? data['body'] ?? message.notification?.body)
                ?.toString()
                .trim() ??
            '';
    final stableId = (data['id'] ?? data['message_id'] ?? message.messageId)
        ?.toString()
        .trim();
    final eventKey = stableId?.isNotEmpty == true
        ? 'message:$stableId'
        : 'message:$conversationId:$createdAt:$content';
    if (!ChatNotificationGate.shared.claimPresentation(eventKey)) return;

    final chatProvider = context.read<ChatProvider>();
    if (_isWorkspaceForeground &&
        chatProvider.isConversationVisible(conversationId)) {
      return;
    }

    var title = message.notification?.title?.trim();
    var channel =
        (data['channel'] ?? data['external_provider'] ?? data['provider'])
            ?.toString()
            .trim()
            .toLowerCase();
    var chatIcon = ConversationChannelPresentation.iconForChannel(channel);
    for (final conversation in chatProvider.conversations) {
      if (conversation.id == conversationId) {
        title = chatProvider.getChatTitle(conversation);
        channel = conversation.channel;
        chatIcon = ConversationChannelPresentation.icon(conversation);
        break;
      }
    }
    if (title == null || title.isEmpty || title == 'New Message') {
      final isMetaChannel =
          channel == 'instagram' || channel == 'facebook_messenger';
      title = isMetaChannel
          ? 'Nuevo mensaje de ${ConversationChannelPresentation.shortLabelForChannel(channel)}'
          : 'Nuevo mensaje';
    }

    final chatRoute = Uri(
      path: '/chat',
      queryParameters: {'conversation': conversationId},
    ).toString();
    _showWorkspaceAlert(
      title: title,
      body: content.isEmpty ? 'Nuevo mensaje recibido' : content,
      icon: chatIcon,
      route: chatRoute,
      category: NotificationCategory.message,
      showSystemNotification: !kIsWeb,
      notificationId: eventKey.hashCode,
    );
  }

  void _handleMailPush(RemoteMessage message) {
    if (!mounted) return;
    final data = message.data;
    final isMailNotification = data['type'] == 'mail' ||
        data['notification_type'] == 'mail' ||
        data['route'] == '/mail';
    if (!isMailNotification) return;

    final notificationService = NotificationService();
    if (!notificationService
        .notificationsEnabledFor(NotificationCategory.email)) {
      return;
    }

    final stableEventId = message.messageId?.trim().isNotEmpty == true
        ? message.messageId!.trim()
        : (data['history_id'] ?? data['message_id'] ?? data['notification_id'])
            ?.toString()
            .trim();
    final provider = data['provider']?.toString().trim() ?? 'mail';
    if (stableEventId != null &&
        stableEventId.isNotEmpty &&
        !MailNotificationGate.shared.claimPresentation(
          'push:$provider:$stableEventId',
        )) {
      return;
    }

    // Gmail history pushes are wake-up signals, not proof that a new inbox
    // message exists. The provider refresh is the authority and will emit a
    // concrete provider/message ID only when it discovers a real new email.
    unawaited(
      MailAccountManager.instance.refreshInbox(background: true),
    );
  }

  void _handleNewEmail(Email email) {
    if (!mounted ||
        !MailNotificationGate.shared.claimPresentation(
          'inbox:${email.providerId}:${email.id}',
        )) {
      return;
    }

    final sender =
        email.senderName.trim().isEmpty ? email.senderEmail : email.senderName;
    final subject =
        email.subject.trim().isEmpty ? '(sin asunto)' : email.subject.trim();
    final body = sender.trim().isEmpty ? subject : '$sender - $subject';

    _showWorkspaceAlert(
      title: 'Nuevo correo',
      body: body,
      icon: Icons.email_outlined,
      route: buildMailMessageRoute(
        providerId: email.providerId,
        messageId: email.id,
      ),
      category: NotificationCategory.email,
      suppressRoutePrefix: '/mail',
      showSystemNotification: _usesDesktopLocalMailNotifications,
      notificationId: '${email.providerId}:${email.id}'.hashCode,
    );
  }

  bool get _usesDesktopLocalMailNotifications {
    if (kIsWeb) return false;
    return defaultTargetPlatform != TargetPlatform.android &&
        defaultTargetPlatform != TargetPlatform.iOS;
  }

  void _showWorkspaceAlert({
    required String title,
    required String body,
    required IconData icon,
    required String route,
    required NotificationCategory category,
    String? suppressRoutePrefix,
    bool showSystemNotification = false,
    int? notificationId,
  }) {
    final notificationService = NotificationService();
    final activeRoute = workspaceRoutePath(
      _workspaceManager.activeWorkspace?.currentRoute ?? '',
    );
    if (!notificationService.notificationsEnabledFor(category) ||
        (_isWorkspaceForeground &&
            suppressRoutePrefix != null &&
            activeRoute.startsWith(suppressRoutePrefix))) {
      return;
    }

    _workspaceAlertTimer?.cancel();
    _workspaceAlertOverlay?.remove();

    final overlay = Overlay.maybeOf(context);
    if (overlay == null) return;

    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (overlayContext) => Positioned(
        top: 10,
        left: 16,
        right: 16,
        child: Material(
          color: Colors.transparent,
          child: Center(
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: -100, end: 0),
              duration: const Duration(milliseconds: 400),
              curve: Curves.easeOutQuart,
              builder: (context, offset, child) => Transform.translate(
                offset: Offset(0, offset),
                child: Opacity(
                  opacity: (1 - (offset / -100)).clamp(0.0, 1.0),
                  child: child,
                ),
              ),
              child: Container(
                constraints: const BoxConstraints(maxWidth: 400),
                decoration: BoxDecoration(
                  color: Theme.of(overlayContext).colorScheme.inverseSurface,
                  borderRadius: BorderRadius.circular(30),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.2),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: InkWell(
                  onTap: () {
                    entry.remove();
                    if (identical(_workspaceAlertOverlay, entry)) {
                      _workspaceAlertOverlay = null;
                    }

                    final trustedExternalUri =
                        trustedMetaNotificationUrl(route);
                    if (trustedExternalUri != null) {
                      unawaited(
                        launchUrl(
                          trustedExternalUri,
                          mode: LaunchMode.externalApplication,
                        ).then<void>(
                          (opened) {
                            if (!opened) {
                              debugPrint(
                                '🔔 [WorkspaceShell] Could not open trusted Meta URL',
                              );
                            }
                          },
                          onError: (Object error, StackTrace stackTrace) {
                            debugPrint(
                              '🔔 [WorkspaceShell] Could not open trusted Meta URL: $error',
                            );
                          },
                        ),
                      );
                    } else {
                      _workspaceManager.navigateActiveWorkspace(route);
                    }
                  },
                  borderRadius: BorderRadius.circular(30),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          icon,
                          size: 18,
                          color: Theme.of(overlayContext)
                              .colorScheme
                              .onInverseSurface,
                        ),
                        const SizedBox(width: 12),
                        Flexible(
                          child: Text(
                            '$title: $body',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Theme.of(overlayContext)
                                  .colorScheme
                                  .onInverseSurface,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
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
        ),
      ),
    );

    overlay.insert(entry);
    _workspaceAlertOverlay = entry;
    _workspaceAlertTimer = Timer(const Duration(seconds: 4), () {
      if (!identical(_workspaceAlertOverlay, entry)) return;
      entry.remove();
      _workspaceAlertOverlay = null;
    });

    if (showSystemNotification) {
      notificationService.playNotificationSound(
        category: category,
      );
      notificationService.showLocalNotification(
        title,
        body,
        notificationId: notificationId,
        category: category,
      );
    }
  }

  void _openSharedRoute(String route) {
    if (!mounted) return;

    final normalizedRoute = RouteShareService.normalizeRoute(route);
    if (normalizedRoute == null) {
      debugPrint('🔗 [DeepLink] Ignored unsupported shared route: $route');
      return;
    }

    final workspaceManager = context.read<WorkspaceManager>();
    debugPrint('🔗 [DeepLink] Opening shared route: $normalizedRoute');
    workspaceManager.navigateActiveWorkspaceFromSharedLink(normalizedRoute);
    DeepLinkHandler.instance.takePendingRoute();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _WorkspaceShell extends StatefulWidget {
  const _WorkspaceShell({super.key, required this.authService});

  final AuthService authService;

  @override
  State<_WorkspaceShell> createState() => _WorkspaceShellState();
}

class _WorkspaceShellState extends State<_WorkspaceShell> {
  final _toolbarKey = GlobalKey();
  final _workspaceStackKey = GlobalKey(
    debugLabel: 'authenticated-workspace-stack',
  );

  Widget _buildWorkspaceStack({required double topInset}) {
    return WorkspaceShellScope(
      topInset: topInset,
      child: Selector<WorkspaceManager, (int, String)>(
        key: _workspaceStackKey,
        selector: (_, workspaceManager) => (
          workspaceManager.activeStackIndex,
          workspaceManager.workspaceStackSignature,
        ),
        builder: (context, data, _) {
          final workspaceManager = context.read<WorkspaceManager>();
          return IndexedStack(
            index: data.$1,
            sizing: StackFit.expand,
            children: workspaceManager.workspaceStackOrder.map((workspace) {
              if (!workspace.isHydrated) {
                return SizedBox.shrink(
                  key: ValueKey('dormant-${workspace.id}'),
                );
              }
              return _WorkspaceRouterView(
                key: ValueKey(workspace.id),
                workspace: workspace,
                authService: widget.authService,
              );
            }).toList(),
          );
        },
      ),
    );
  }

  double _activeNavigationWidth(
    NavigationService navigationService,
    WorkspaceManager workspaceManager,
  ) {
    final workspace = workspaceManager.activeWorkspace;
    if (workspace != null &&
        !workspaceRouteUsesAppNavigation(workspace.currentRoute)) {
      return 0;
    }
    final isPinned = workspace?.isPinned ?? false;
    final isVisible = !isPinned &&
        (workspace?.isDrawerVisible ?? navigationService.isDrawerVisible);
    if (!isVisible) return 0;

    final mode =
        workspace?.chromeModeOverride ?? navigationService.preferredChromeMode;
    return mode == NavigationChromeMode.rail
        ? WorkspaceShellScope.navigationRailWidth
        : (workspace?.drawerWidth ?? navigationService.drawerWidth);
  }

  @override
  Widget build(BuildContext context) {
    final appearanceService = context.watch<AppearanceService>();
    final activeTool = context.watch<RightToolbarService>().activeTool;
    final navigationService = context.watch<NavigationService>();
    final workspaceManager = context.watch<WorkspaceManager>();
    final theme = Theme.of(context);
    final chrome = WorkspaceChromeTheme.resolveFromTheme(
      theme,
      fallback: WorkspaceChromeTheme.resolve(
        palette: appearanceService.sidebarPalette,
        brightness: theme.brightness,
      ),
    );

    return WorkspaceChromeStyle(
      data: chrome,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = ResponsiveViewport.usesCompactShell(context);

          if (compact) {
            final toolbar = RightToolbar.compactWorkspace(key: _toolbarKey);
            final hasCompactTool =
                activeTool != null && activeTool != ToolbarTool.newJob;
            return WorkspaceSystemInsetBoundary(
              compact: true,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _buildWorkspaceStack(topInset: 0),
                  Positioned.fill(
                    child: Offstage(
                      offstage: !hasCompactTool,
                      child: toolbar,
                    ),
                  ),
                ],
              ),
            );
          }

          const topInset = WorkspaceShellScope.workspaceBarHeight;
          final navigationWidth = _activeNavigationWidth(
            navigationService,
            workspaceManager,
          );
          final isResizing =
              workspaceManager.activeWorkspace?.isResizingDrawer ??
                  navigationService.isResizing;
          final toolbar = Padding(
            padding: const EdgeInsets.only(top: topInset),
            child: RightToolbar(key: _toolbarKey),
          );
          final workspaceStack = _buildWorkspaceStack(topInset: topInset);

          late final Widget workspaceAndTools;
          if (!appearanceService.rightToolbarOverContent) {
            workspaceAndTools = Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: workspaceStack),
                toolbar,
              ],
            );
          } else {
            workspaceAndTools = Stack(
              children: [
                Positioned.fill(
                  child: Padding(
                    padding: const EdgeInsets.only(
                      right: RightToolbar.collapsedWidth,
                    ),
                    child: workspaceStack,
                  ),
                ),
                Positioned(
                  top: 0,
                  right: 0,
                  bottom: 0,
                  child: toolbar,
                ),
              ],
            );
          }

          return WorkspaceSystemInsetBoundary(
            compact: false,
            child: Stack(
              fit: StackFit.expand,
              children: [
                workspaceAndTools,
                AnimatedPositioned(
                  key: const ValueKey('workspace-tab-bar-placement'),
                  duration: isResizing
                      ? Duration.zero
                      : const Duration(milliseconds: 200),
                  curve: Curves.easeOutCubic,
                  left: navigationWidth,
                  top: 0,
                  right: 0,
                  height: topInset,
                  child: const WorkspaceTabBar(),
                ),
              ],
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
  String? _lastRouterLocation;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();

    // Create the router with an explicit initial location for this workspace.
    // This avoids post-frame .go() calls that can cause extra navigation cycles.
    _router = AppRouter.createRouter(
      widget.authService,
      initialLocationOverride: widget.workspace.currentRoute,
    );

    // Save the router reference to the workspace object so external UI
    // (like global floating buttons) can trigger navigation on the active tab
    widget.workspace.router = _router;
    _lastRouterLocation = _currentRouterLocation();
    _router.routerDelegate.addListener(_handleRouterLocationChanged);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<WorkspaceManager>().handleWorkspaceRouteChange(
            widget.workspace.id,
            _currentRouterLocation(),
          );
    });

    // Listen for notification taps to navigate to specific chats
    // Only handle if this is the active workspace
    _notificationTapSubscription =
        NotificationService().onNotificationTap.listen((route) {
      if (!mounted) return;
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
    _router.routerDelegate.removeListener(_handleRouterLocationChanged);
    _router.dispose();
    super.dispose();
  }

  Widget _buildWorkspaceRouter() {
    return Provider<Workspace>.value(
      value: widget.workspace,
      child: Router.withConfig(config: _router),
    );
  }

  String _currentRouterLocation() {
    return _router.routerDelegate.currentConfiguration.uri.toString();
  }

  void _handleRouterLocationChanged() {
    if (!mounted) return;

    final route = _currentRouterLocation();
    if (route == _lastRouterLocation) return;
    _lastRouterLocation = route;

    final workspaceManager = context.read<WorkspaceManager>();
    final fallbackRoute =
        workspaceManager.handleWorkspaceRouteChange(widget.workspace.id, route);

    if (fallbackRoute != null && fallbackRoute != route) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_currentRouterLocation() != fallbackRoute) {
          _router.go(fallbackRoute);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    try {
      return _buildWorkspaceRouter();
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
                    _router.routerDelegate
                        .removeListener(_handleRouterLocationChanged);
                    _router.dispose();
                    _router = AppRouter.createRouter(
                      widget.authService,
                      initialLocationOverride: widget.workspace.currentRoute,
                    );
                    widget.workspace.router = _router;
                    _lastRouterLocation = _currentRouterLocation();
                    _router.routerDelegate
                        .addListener(_handleRouterLocationChanged);
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
