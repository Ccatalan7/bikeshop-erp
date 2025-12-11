import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:app_links/app_links.dart';
import 'package:go_router/go_router.dart';

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
import 'modules/bikeshop/services/job_status_service.dart';
import 'modules/hr/services/hr_service.dart';
import 'modules/website/services/website_service.dart';
import 'modules/website/services/mercadopago_service.dart';
import 'modules/website/providers/website_edit_mode_provider.dart';
import 'shared/services/job_role_service.dart';
import 'public_store/providers/cart_provider.dart';
import 'public_store/providers/public_store_tenant_provider.dart';
import 'public_store/services/customer_account_service.dart';
import 'public_store/services/address_autocomplete_service.dart';
import 'public_store/services/public_inventory_service.dart';
import 'shared/routes/app_router.dart';
import 'shared/services/data_preload_service.dart';
import 'shared/services/error_reporting_service.dart';
import 'shared/services/tenant_detection_service.dart';
import 'shared/services/backup_service.dart';
import 'shared/services/window_zoom_service.dart';
import 'shared/widgets/window_zoom_scope.dart';
import 'shared/widgets/branded_loading.dart';
import 'package:flutter_web_plugins/url_strategy.dart';

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

Future<void> main() async {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    
    // Use clean URLs (no hash #) for web
    usePathUrlStrategy();

    if (!SupabaseConfig.isConfigured && kDebugMode) {
      debugPrint(
          '[Supabase] WARNING: SupabaseConfig still has placeholder values. '
          'Update lib/shared/config/supabase_config.dart or provide dart-defines.');
    }

    await Supabase.initialize(
      url: SupabaseConfig.url,
      anonKey: SupabaseConfig.anonKey,
      authOptions: const FlutterAuthClientOptions(
        autoRefreshToken: true,
      ),
    );

    // Handle deep links for OAuth callbacks on desktop and mobile
    if (!kIsWeb) {
      final appLinks = AppLinks();
      appLinks.uriLinkStream.listen((uri) {
        if (kDebugMode) {
          print('[DeepLink] Received: $uri');
        }
        // Supabase automatically handles OAuth callbacks
        // The auth state listener will trigger navigation
      });
      
      // Handle initial link (app opened from a link)
      appLinks.getInitialLink().then((uri) {
        if (uri != null && kDebugMode) {
          print('[DeepLink] Initial link: $uri');
        }
      });
    }

    FlutterError.onError = (FlutterErrorDetails details) {
      // Suppress Flutter Web-specific "disposed EngineFlutterView" errors
      // These occur during hot reload and navigation and don't affect functionality
      final errorString = details.exceptionAsString();
      if (kIsWeb && errorString.contains('disposed') && errorString.contains('EngineFlutterView')) {
        if (kDebugMode) {
          debugPrint('⚠️ [Flutter Web] Suppressed disposed view error (hot reload artifact)');
        }
        return; // Don't report or dump these errors
      }
      
      ErrorReportingService.report(details.exception, details.stack);
      FlutterError.dumpErrorToConsole(details);
    };

    runApp(const VinabikeApp());
  }, (error, stack) {
    // Suppress Flutter Web-specific errors in zone guard as well
    final errorString = error.toString();
    if (kIsWeb && errorString.contains('disposed') && errorString.contains('EngineFlutterView')) {
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
        ChangeNotifierProvider(create: (_) {
          final navigationService = NavigationService();
          navigationService.initialize();
          return navigationService;
        }),
        ChangeNotifierProvider(create: (_) => WorkspaceManager()),

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
        ChangeNotifierProvider(create: (context) => SmartTaskService(
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
        ChangeNotifierProvider.value(value: SmartPurchaseListService()), // Singleton - persists across app
        ChangeNotifierProvider(
            create: (context) => HRService(
                  Provider.of<TenantService>(context, listen: false),
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
        // MercadoPago: Don't auto-initialize - checkout will init with proper tenant_id
        ChangeNotifierProvider(create: (_) => MercadoPagoService()),
        ChangeNotifierProvider(create: (_) => BackupService()),
        
        // Public store services
        ChangeNotifierProvider(create: (_) => CartProvider()),
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
          update: (context, databaseService, accountingService, tenantService, previous) {
            final service =
                previous ?? SalesService(databaseService, accountingService, tenantService);
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
          
          // PUBLIC STORE: Simple one-time initialization
          // DON'T watch WebsiteService - it causes infinite rebuilds
          if (isPublicStoreHost) {
            final tenantProvider = context.watch<PublicStoreTenantProvider>();
            final websiteService = context.watch<WebsiteService>();
            
            // If tenant not detected yet, start detection
            if (!tenantProvider.hasTenant && !tenantProvider.isLoading) {
              WidgetsBinding.instance.addPostFrameCallback((_) async {
                await tenantProvider.detectTenant();
                if (tenantProvider.tenantId != null) {
                  final tid = tenantProvider.tenantId!;
                  final ws = context.read<WebsiteService>();
                  final publicInventoryService = context.read<PublicInventoryService>();
                  
                  // Load all data in parallel (ONE TIME)
                  await Future.wait([
                    ws.loadSettingsForTenant(tid),
                    ws.loadBlocksForTenant(tid),
                    publicInventoryService.getProductsForTenant(tenantId: tid),
                    publicInventoryService.getCategoriesForTenant(tenantId: tid),
                  ]);
                }
              });
            }
            
            // Show loading while tenant is being detected OR data is loading
            final isDataReady = websiteService.hasLoadedForTenant;
            if (tenantProvider.isLoading || (tenantProvider.hasTenant && !isDataReady)) {
              return const MaterialApp(
                debugShowCheckedModeBanner: false,
                home: Scaffold(
                  backgroundColor: Colors.white,
                  body: Center(child: CircularProgressIndicator()),
                ),
              );
            }
            
            // Tenant detection failed
            if (!tenantProvider.hasTenant) {
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
          // SKIP on public store - visitors don't need ERP data
          final dataPreloadService = context.read<DataPreloadService>();
          if (!isPublicStoreHost && !dataPreloadService.hasPreloaded && authService.isAuthenticated) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              dataPreloadService.initialize(
                bikeshopService: context.read<BikeshopService>(),
                customerService: context.read<CustomerService>(),
                inventoryService: context.read<module_inventory.InventoryService>(),
                categoryService: context.read<CategoryService>(),
                brandService: context.read<BrandService>(),
                salesService: context.read<SalesService>(),
                purchaseService: context.read<PurchaseService>(),
                hrService: context.read<HRService>(),
                isPublicStore: isPublicStoreHost, // Disable on public store
              );
            });
          }
          
          // Reload appearance settings after authentication completes
          // Use hasLoadedWithTenant to ensure we reload if initial load had no tenant
          if (authService.isAuthenticated && !appearanceService.hasLoadedWithTenant) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              appearanceService.reloadSettings();
            });
          }

          // Show loading screen while auth is initializing
          // BUT skip for public store hosts - they don't need auth
          if (authService.isInitializing && !isPublicStoreHost) {
            return MaterialApp(
              title: 'Viñabike ERP',
              theme: AppTheme.lightTheme,
              darkTheme: AppTheme.darkTheme,
              themeMode: appearanceService.themeMode,
              home: const Scaffold(
                body: BrandedLoadingOverlay(message: 'Cargando...'),
              ),
            );
          }

          // Public store or not authenticated = single router
          if (isPublicStoreHost || !authService.isAuthenticated) {
            
            return MaterialApp.router(
              title: 'Viñabike ERP',
              theme: AppTheme.lightTheme,
              darkTheme: AppTheme.darkTheme,
              themeMode: appearanceService.themeMode,
              scrollBehavior: AppScrollBehavior(),
              routerConfig: AppRouter.createRouter(
                authService,
                forcePublicStoreHost: isPublicStoreHost,
                initialLocationOverride: isPublicStoreHost ? '/' : null,
              ),
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
              builder: (context, child) =>
                  WindowZoomScope(child: child ?? const SizedBox.shrink()),
            );
          }

          // Authenticated = workspace system with OUTER Material context
          debugPrint('✅ [Main] User is AUTHENTICATED - using WORKSPACE SYSTEM');
          
          return MaterialApp(
            title: 'Viñabike ERP',
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
            builder: (context, child) =>
                WindowZoomScope(child: child ?? const SizedBox.shrink()),
            home: Consumer<WorkspaceManager>(
              builder: (context, workspaceManager, _) {
                // Ensure workspaces are initialized before rendering
                if (workspaceManager.workspaces.isEmpty) {
                  debugPrint('⚠️ [Main] WorkspaceManager has no workspaces yet, showing loading...');
                  return const Scaffold(
                    body: BrandedLoadingOverlay(message: 'Cargando espacios de trabajo...'),
                  );
                }
                
                return Scaffold(
                  body: Column(
                    children: [
                      // Workspace tab bar uses theme
                      const WorkspaceTabBar(),
                      Expanded(
                        child: IndexedStack(
                          index: workspaceManager.activeIndex,
                          sizing: StackFit.expand,
                          children: workspaceManager.workspaces.map((workspace) {
                            return _WorkspaceRouterView(
                              key: ValueKey(workspace.id),
                              workspace: workspace,
                              authService: authService,
                            );
                          }).toList(),
                        ),
                      ),
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
  late final GoRouter _router;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    
    debugPrint('🎯 [WorkspaceRouterView] Creating router for workspace: ${widget.workspace.title} with route: ${widget.workspace.initialRoute}');
    
    // Create router WITHOUT initialLocation to avoid navigation conflicts
    // The MainLayout will handle navigation to the correct route
    _router = AppRouter.createRouter(widget.authService);
    
    // Navigate to the workspace's initial route after the router is created
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        debugPrint('🚀 [WorkspaceRouterView] Navigating to: ${widget.workspace.initialRoute}');
        _router.go(widget.workspace.initialRoute);
      } catch (e) {
        debugPrint('❌ [WorkspaceRouterView] Navigation error: $e');
      }
    });
  }

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    
    try {
      return Router.withConfig(config: _router);
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
    debugPrint('🧪 [Main] FORCE_SUBDOMAIN=$forceSubdomain → treating as public store host');
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
