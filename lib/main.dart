import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:app_links/app_links.dart';

import 'shared/themes/app_theme.dart';
import 'shared/services/auth_service.dart';
import 'shared/services/database_service.dart';
import 'shared/services/inventory_service.dart';
import 'shared/services/payment_method_service.dart';
import 'shared/services/navigation_service.dart';
import 'shared/services/tenant_service.dart';
import 'shared/services/user_management_service.dart';
import 'shared/config/supabase_config.dart';
import 'modules/inventory/services/category_service.dart';
import 'modules/inventory/services/inventory_service.dart' as module_inventory;
import 'modules/inventory/services/brand_service.dart';
import 'modules/crm/services/customer_service.dart';
import 'modules/accounting/services/accounting_service.dart';
import 'modules/accounting/services/financial_reports_service.dart';
import 'modules/accounting/services/expense_service.dart';
import 'modules/pos/services/pos_service.dart';
import 'modules/purchases/services/purchase_service.dart';
import 'modules/sales/services/sales_service.dart';
import 'modules/settings/services/appearance_service.dart';
import 'modules/bikeshop/services/bikeshop_service.dart';
import 'modules/hr/services/hr_service.dart';
import 'modules/website/services/website_service.dart';
import 'modules/website/services/mercadopago_service.dart';
import 'public_store/providers/cart_provider.dart';
import 'public_store/providers/public_store_tenant_provider.dart';
import 'public_store/services/customer_account_service.dart';
import 'public_store/services/address_autocomplete_service.dart';
import 'public_store/services/public_inventory_service.dart';
import 'shared/routes/app_router.dart';
import 'shared/services/error_reporting_service.dart';
import 'shared/services/tenant_detection_service.dart';

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
        ChangeNotifierProvider(create: (_) => NavigationService()),

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
        ChangeNotifierProvider(
            create: (context) => HRService(
                  Provider.of<TenantService>(context, listen: false),
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

          final authService = context.read<AuthService>();
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

          return MaterialApp.router(
            title: 'Vinabike',
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: ThemeMode.light, // Force light mode for public store
            routerConfig: AppRouter.createRouter(
              authService,
              forcePublicStoreHost: isPublicStoreHost,
              initialLocationOverride: isPublicStoreHost ? '/tienda' : null,
            ),
            debugShowCheckedModeBanner: false,
            // Add localization support
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: const [
              Locale('es', ''), // Spanish (default for Chile)
              Locale('en', ''), // English
            ],
            locale: const Locale('es', ''), // Default locale
            builder: (context, child) {
              // Global error overlay disabled - errors will show in debug console
              return child ?? const SizedBox.shrink();
            },
          );
        },
      ),
    );
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
