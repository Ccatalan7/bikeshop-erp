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
import 'shared/config/supabase_config.dart';
import 'modules/inventory/services/category_service.dart';
import 'modules/crm/services/customer_service.dart';
import 'modules/accounting/services/accounting_service.dart';
import 'modules/accounting/services/financial_reports_service.dart';
import 'modules/pos/services/pos_service.dart';
import 'modules/purchases/services/purchase_service.dart';
import 'modules/sales/services/sales_service.dart';
import 'modules/settings/services/appearance_service.dart';
import 'modules/bikeshop/services/bikeshop_service.dart';
import 'modules/hr/services/hr_service.dart';
import 'shared/routes/app_router.dart';
import 'shared/services/error_reporting_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (!SupabaseConfig.isConfigured && kDebugMode) {
    debugPrint('[Supabase] WARNING: SupabaseConfig still has placeholder values. '
        'Update lib/shared/config/supabase_config.dart or provide dart-defines.');
  }

  await Supabase.initialize(
    url: SupabaseConfig.url,
    anonKey: SupabaseConfig.anonKey,
    authOptions: const FlutterAuthClientOptions(
      autoRefreshToken: true,
    ),
  );

  // Handle deep links for OAuth callbacks on desktop
  if (!kIsWeb) {
    final appLinks = AppLinks();
    appLinks.uriLinkStream.listen((uri) {
      debugPrint('[DeepLink] Received: $uri');
      // Supabase will automatically handle the OAuth callback
    });
  }

  FlutterError.onError = (FlutterErrorDetails details) {
    ErrorReportingService.report(details.exception, details.stack);
    FlutterError.dumpErrorToConsole(details);
  };

  runZonedGuarded(() {
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
        ChangeNotifierProvider(create: (context) => InventoryService(
          db: Provider.of<DatabaseService>(context, listen: false),
        )),
        ChangeNotifierProvider(create: (context) => CategoryService(
          Provider.of<DatabaseService>(context, listen: false),
        )),
        ChangeNotifierProvider(create: (context) => CustomerService(
          Provider.of<DatabaseService>(context, listen: false),
        )),
        ChangeNotifierProvider(create: (context) => BikeshopService(
          Provider.of<DatabaseService>(context, listen: false),
        )),
        ChangeNotifierProvider(create: (context) => AccountingService(
          Provider.of<DatabaseService>(context, listen: false),
        )),
        ChangeNotifierProvider(create: (context) => FinancialReportsService(
          Provider.of<DatabaseService>(context, listen: false),
        )),
        ChangeNotifierProvider(create: (context) => PurchaseService(
          Provider.of<DatabaseService>(context, listen: false),
        )),
        ChangeNotifierProvider(create: (_) => HRService()),
        ChangeNotifierProxyProvider2<DatabaseService, AccountingService, SalesService>(
          create: (context) => SalesService(
            context.read<DatabaseService>(),
            context.read<AccountingService>(),
          ),
          update: (context, databaseService, accountingService, previous) {
            final service = previous ?? SalesService(databaseService, accountingService);
            service.updateDependencies(databaseService, accountingService);
            return service;
          },
        ),
        
        // POS service depends on Inventory, Sales, and PaymentMethod
        ChangeNotifierProxyProvider3<InventoryService, SalesService, PaymentMethodService, POSService>(
          create: (context) => POSService(
            inventoryService: context.read<InventoryService>(),
            salesService: context.read<SalesService>(),
            paymentMethodService: context.read<PaymentMethodService>(),
          ),
          update: (context, inventoryService, salesService, paymentMethodService, previous) {
            final service = previous ?? POSService(
              inventoryService: inventoryService,
              salesService: salesService,
              paymentMethodService: paymentMethodService,
            );
            service.updateDependencies(
              inventoryService: inventoryService,
              salesService: salesService,
              paymentMethodService: paymentMethodService,
            );
            return service;
          },
        ),
      ],
      child: Builder(
        builder: (context) {
          // Initialize purchase service dependency
          final accountingService = Provider.of<AccountingService>(context, listen: false);
          PurchaseService.setAccountingService(accountingService);
          
          final authService = context.read<AuthService>();

          return MaterialApp.router(
            title: 'Vinabike ERP',
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: ThemeMode.system,
            routerConfig: AppRouter.createRouter(authService),
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