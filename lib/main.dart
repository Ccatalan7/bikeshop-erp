import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';

import 'shared/themes/app_theme.dart';
import 'shared/services/auth_service.dart';
import 'shared/services/database_service.dart';
import 'shared/services/inventory_service.dart';
import 'modules/inventory/services/category_service.dart';
import 'modules/crm/services/customer_service.dart';
import 'modules/accounting/services/accounting_service.dart';
import 'modules/pos/services/pos_service.dart';
import 'modules/purchases/services/purchase_service.dart';
import 'modules/sales/services/sales_service.dart';
import 'shared/routes/app_router.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize Firebase
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  
  runApp(const VinabikeApp());
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
        ChangeNotifierProvider(create: (context) => AccountingService(
          Provider.of<DatabaseService>(context, listen: false),
        )),
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
        
        // POS service depends on Inventory and Accounting
        ChangeNotifierProxyProvider2<InventoryService, AccountingService, POSService>(
          create: (context) => POSService(
            inventoryService: context.read<InventoryService>(),
            accountingService: context.read<AccountingService>(),
          ),
          update: (context, inventoryService, accountingService, previous) =>
              previous ?? POSService(
                inventoryService: inventoryService,
                accountingService: accountingService,
              ),
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
          );
        },
      ),
    );
  }
}