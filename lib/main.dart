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
import 'modules/pos/services/pos_service.dart';
import 'modules/purchases/services/purchase_service.dart';
import 'modules/purchases/services/smart_purchase_list_service.dart';
import 'modules/sales/services/sales_service.dart';
import 'modules/settings/services/appearance_service.dart';
import 'modules/bikeshop/services/bikeshop_service.dart';
import 'modules/hr/services/hr_service.dart';
import 'modules/website/services/website_service.dart';
import 'modules/website/services/mercadopago_service.dart';
import 'shared/services/job_role_service.dart';
import 'public_store/providers/cart_provider.dart';
import 'public_store/providers/public_store_tenant_provider.dart';
import 'public_store/services/customer_account_service.dart';
import 'public_store/services/address_autocomplete_service.dart';
import 'public_store/services/public_inventory_service.dart';
import 'shared/routes/app_router.dart';
import 'shared/services/error_reporting_service.dart';
import 'shared/services/tenant_detection_service.dart';

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
      ErrorReportingService.report(details.exception, details.stack);
      FlutterError.dumpErrorToConsole(details);
    };

    runApp(const VinabikeApp());
  }, (error, stack) {
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
        ChangeNotifierProvider(create: (_) {
          final service = AppearanceService();
          // Auto-refresh logo on app start to get latest version
          Future.delayed(const Duration(seconds: 2), () {
            service.refreshLogo();
          });
          return service;
        }),
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
        ChangeNotifierProvider(create: (_) => MercadoPagoService()..initialize()),
        
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
      ],
      child: Builder(
        builder: (context) {
          // Initialize purchase service dependency
          final accountingService =
              Provider.of<AccountingService>(context, listen: false);
          PurchaseService.setAccountingService(accountingService);

          final isPublicStoreHost = _detectPublicStoreHost();

          // Detect tenant for public store (subdomain-based routing)
          if (isPublicStoreHost) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              final tenantProvider = context.read<PublicStoreTenantProvider>();
              if (!tenantProvider.hasTenant && !tenantProvider.isLoading) {
                debugPrint('[Main] Triggering tenant detection for public store...');
                tenantProvider.detectTenant();
              }
            });
          }

          // CRITICAL: Use context.watch() to rebuild when auth state changes
          final authService = context.watch<AuthService>();
          
          debugPrint('🔐 [Main] Auth check: isAuthenticated=${authService.isAuthenticated}, isInitializing=${authService.isInitializing}');
          debugPrint('📍 [Main] isPublicStoreHost=$isPublicStoreHost');

          // Show loading screen while auth is initializing
          if (authService.isInitializing) {
            debugPrint('⏳ [Main] Auth still initializing, showing loading screen...');
            return MaterialApp(
              home: const Scaffold(
                body: Center(
                  child: CircularProgressIndicator(),
                ),
              ),
            );
          }

          // Public store or not authenticated = single router
          if (isPublicStoreHost || !authService.isAuthenticated) {
            debugPrint('⚠️ [Main] Using SINGLE ROUTER (no workspace system)');
            debugPrint('   Reason: ${isPublicStoreHost ? "Public store host" : "Not authenticated"}');
            
            return MaterialApp.router(
              title: 'Vinabike',
              theme: AppTheme.lightTheme,
              darkTheme: AppTheme.darkTheme,
              themeMode: ThemeMode.light,
              scrollBehavior: AppScrollBehavior(),
              routerConfig: AppRouter.createRouter(
                authService,
                forcePublicStoreHost: isPublicStoreHost,
                initialLocationOverride: isPublicStoreHost ? '/tienda' : null,
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
            );
          }

          // Authenticated = workspace system with OUTER Material context
          debugPrint('✅ [Main] User is AUTHENTICATED - using WORKSPACE SYSTEM');
          
          return MaterialApp(
            title: 'Vinabike',
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: ThemeMode.light,
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
            home: Consumer<WorkspaceManager>(
              builder: (context, workspaceManager, _) {
                // Ensure workspaces are initialized before rendering
                if (workspaceManager.workspaces.isEmpty) {
                  debugPrint('⚠️ [Main] WorkspaceManager has no workspaces yet, showing loading...');
                  return const Scaffold(
                    body: Center(
                      child: CircularProgressIndicator(),
                    ),
                  );
                }
                
                return Scaffold(
                  body: Column(
                    children: [
                      Container(
                        color: Colors.white,
                        child: const WorkspaceTabBar(),
                      ),
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
  if (!kIsWeb) {
    return false;
  }

  final host = Uri.base.host.toLowerCase();
  return host == 'vinabike-store.web.app' ||
      host == 'vinabike-store.firebaseapp.com' ||
      host == 'vinabike.cl' ||
      host == 'www.vinabike.cl';
}
