import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../widgets/main_layout.dart';
import '../screens/dashboard_screen.dart';
import '../screens/login_screen.dart';
import '../services/auth_service.dart';
import '../../modules/accounting/pages/account_list_page.dart';
import '../../modules/accounting/pages/account_form_page.dart';
import '../../modules/accounting/pages/journal_entry_list_page.dart';
import '../../modules/accounting/pages/journal_entry_form_page.dart';
import '../../modules/accounting/pages/financial_reports_hub_page.dart';
import '../../modules/accounting/pages/income_statement_page.dart';
import '../../modules/accounting/pages/balance_sheet_page.dart';
import '../../modules/crm/pages/customer_list_page.dart';
import '../../modules/crm/pages/customer_form_page.dart';
import '../../modules/crm/pages/customer_bike_directory_page.dart';
import '../../modules/bikeshop/pages/client_logbook_page.dart';
import '../../modules/bikeshop/pages/pegas_table_page.dart';
import '../../modules/bikeshop/pages/mechanic_job_form_page.dart';
import '../../modules/inventory/pages/product_list_page.dart';
import '../../modules/inventory/pages/product_form_page.dart';
import '../../modules/inventory/pages/category_list_page.dart';
import '../../modules/inventory/pages/category_form_page.dart';
import '../../modules/inventory/pages/stock_movement_list_page.dart';
import '../../modules/sales/pages/invoice_list_page.dart';
import '../../modules/sales/pages/invoice_form_page.dart';
import '../../modules/sales/pages/invoice_payment_page.dart';
import '../../modules/sales/pages/invoice_detail_page.dart';
import '../../modules/sales/pages/payment_form_page.dart';
import '../../modules/purchases/pages/supplier_list_page.dart';
import '../../modules/purchases/pages/supplier_form_page.dart';
import '../../modules/purchases/pages/purchase_invoice_list_page.dart';
import '../../modules/purchases/pages/purchase_invoice_form_page.dart';
import '../../modules/purchases/pages/purchase_invoice_detail_page.dart';
import '../../modules/purchases/pages/purchase_payments_list_page.dart';
import '../../modules/pos/pages/pos_dashboard_page.dart';
import '../../modules/pos/pages/pos_cart_page.dart';
import '../../modules/pos/pages/pos_payment_page.dart';
import '../../modules/pos/pages/pos_receipt_page.dart';
import '../../modules/pos/models/pos_transaction.dart';
import '../../modules/settings/pages/settings_page.dart';
import '../../modules/settings/pages/factory_reset_page.dart';
import '../../modules/settings/pages/appearance_settings_page.dart';
import '../../modules/hr/pages/employee_list_page.dart';
import '../../modules/hr/pages/attendances_page.dart';
import '../../modules/hr/pages/kiosk_mode_page.dart';
import '../../modules/website/pages/website_management_page.dart';

// Public Store Pages
import '../../public_store/pages/public_home_page.dart';
import '../../public_store/pages/product_catalog_page.dart';
import '../../public_store/pages/product_detail_page.dart';
import '../../public_store/pages/cart_page.dart';
import '../../public_store/pages/checkout_page.dart';
import '../../public_store/pages/order_confirmation_page.dart';
import '../../public_store/pages/contact_page.dart';
import '../../public_store/widgets/public_store_layout.dart';

// Helper wrapper for public store pages
class PublicStoreWrapper extends StatelessWidget {
  final Widget child;

  const PublicStoreWrapper({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return PublicStoreLayout(child: child);
  }
}

// Helper function to create pages without transitions
Page<dynamic> _buildPageWithNoTransition(
  BuildContext context,
  GoRouterState state,
  Widget child,
) {
  return NoTransitionPage<void>(
    key: state.pageKey,
    child: child,
  );
}

class AppRouter {
  static GoRouter createRouter(
    AuthService authService, {
    String? initialLocationOverride,
    bool forcePublicStoreHost = false,
  }) {
    // Public store routes (customer-facing, no auth required)
    final publicRoutes = [
      '/tienda',
      '/tienda/productos',
      '/tienda/producto',
      '/tienda/carrito',
      '/tienda/checkout',
      '/tienda/pedido',
      '/tienda/contacto',
    ];

    final effectiveInitialLocation = initialLocationOverride ??
        (forcePublicStoreHost ? '/tienda' : '/login');

    final router = GoRouter(
      initialLocation: effectiveInitialLocation,
      refreshListenable: authService,
      redirect: (context, state) {
        if (authService.isInitializing) {
          return null;
        }

        final isPublicRoute = publicRoutes.any(
          (route) => state.uri.path.startsWith(route),
        );

        if (forcePublicStoreHost) {
          // Force public storefront hosts to stay within /tienda routes.
          if (!isPublicRoute) {
            return '/tienda';
          }
          return null;
        }

        final isLoggedIn = authService.isAuthenticated;
        final loggingIn = state.matchedLocation == '/login';

        // Allow access to public store routes without authentication
        if (isPublicRoute) {
          return null;
        }

        // Admin/ERP routes require authentication
        if (!isLoggedIn && !loggingIn) {
          return '/login';
        }

        // Redirect logged-in users from login to dashboard
        if (isLoggedIn && loggingIn) {
          return '/dashboard';
        }

        return null;
      },
      routes: [
        // ========================================
        // PUBLIC STORE ROUTES (Customer-facing, No Auth Required)
        // Accessible at /tienda/* for customers
        // ========================================

        // Public Store Home
        GoRoute(
          path: '/tienda',
          pageBuilder: (context, state) => _buildPageWithNoTransition(
            context,
            state,
            const PublicStoreWrapper(child: PublicHomePage()),
          ),
        ),

        // Product Catalog
        GoRoute(
          path: '/tienda/productos',
          pageBuilder: (context, state) => _buildPageWithNoTransition(
            context,
            state,
            const PublicStoreWrapper(child: ProductCatalogPage()),
          ),
        ),

        // Product Detail
        GoRoute(
          path: '/tienda/producto/:id',
          pageBuilder: (context, state) {
            final productId = state.pathParameters['id']!;
            return _buildPageWithNoTransition(
              context,
              state,
              PublicStoreWrapper(
                  child: ProductDetailPage(productId: productId)),
            );
          },
        ),

        // Shopping Cart
        GoRoute(
          path: '/tienda/carrito',
          pageBuilder: (context, state) => _buildPageWithNoTransition(
            context,
            state,
            const PublicStoreWrapper(child: CartPage()),
          ),
        ),

        // Checkout
        GoRoute(
          path: '/tienda/checkout',
          pageBuilder: (context, state) => _buildPageWithNoTransition(
            context,
            state,
            const PublicStoreWrapper(child: CheckoutPage()),
          ),
        ),

        // Order Confirmation
        GoRoute(
          path: '/tienda/pedido/:id',
          pageBuilder: (context, state) {
            final orderId = state.pathParameters['id']!;
            return _buildPageWithNoTransition(
              context,
              state,
              PublicStoreWrapper(
                  child: OrderConfirmationPage(orderId: orderId)),
            );
          },
        ),

        // Contact Page
        GoRoute(
          path: '/tienda/contacto',
          pageBuilder: (context, state) => _buildPageWithNoTransition(
            context,
            state,
            const PublicStoreWrapper(child: ContactPage()),
          ),
        ),

        // ========================================
        // ADMIN/ERP ROUTES (Auth Required)
        // ========================================

        // Authentication
        GoRoute(
          path: '/login',
          pageBuilder: (context, state) => _buildPageWithNoTransition(
            context,
            state,
            const LoginScreen(),
          ),
        ),

        // Dashboard
        GoRoute(
          path: '/dashboard',
          pageBuilder: (context, state) => _buildPageWithNoTransition(
            context,
            state,
            const DashboardScreen(),
          ),
        ),

        // Accounting Module
        GoRoute(
          path: '/accounting/accounts',
          pageBuilder: (context, state) => _buildPageWithNoTransition(
            context,
            state,
            const AccountListPage(),
          ),
        ),
        GoRoute(
          path: '/accounting/accounts/new',
          pageBuilder: (context, state) => _buildPageWithNoTransition(
            context,
            state,
            const AccountFormPage(),
          ),
        ),
        GoRoute(
          path: '/accounting/accounts/:id/edit',
          pageBuilder: (context, state) {
            final id = state.pathParameters['id']!;
            return _buildPageWithNoTransition(
              context,
              state,
              AccountFormPage(accountId: id),
            );
          },
        ),
        GoRoute(
          path: '/accounting/journal-entries',
          pageBuilder: (context, state) => _buildPageWithNoTransition(
            context,
            state,
            const JournalEntryListPage(),
          ),
        ),
        GoRoute(
          path: '/accounting/journal-entries/new',
          pageBuilder: (context, state) => _buildPageWithNoTransition(
            context,
            state,
            const JournalEntryFormPage(),
          ),
        ),
        GoRoute(
          path: '/accounting/journal-entries/:id/edit',
          pageBuilder: (context, state) {
            final entryId = state.pathParameters['id']!;
            return _buildPageWithNoTransition(
              context,
              state,
              JournalEntryFormPage(entryId: entryId),
            );
          },
        ),

        // Financial Reports
        GoRoute(
          path: '/accounting/reports',
          pageBuilder: (context, state) => _buildPageWithNoTransition(
            context,
            state,
            const FinancialReportsHubPage(),
          ),
        ),
        GoRoute(
          path: '/accounting/reports/income-statement',
          pageBuilder: (context, state) => _buildPageWithNoTransition(
            context,
            state,
            const IncomeStatementPage(),
          ),
        ),
        GoRoute(
          path: '/accounting/reports/balance-sheet',
          pageBuilder: (context, state) => _buildPageWithNoTransition(
            context,
            state,
            const BalanceSheetPage(),
          ),
        ),

        // Clientes Hub
        GoRoute(
          path: '/clientes',
          pageBuilder: (context, state) => _buildPageWithNoTransition(
            context,
            state,
            const CustomerListPage(),
          ),
        ),
        GoRoute(
          path: '/clientes/nuevo',
          pageBuilder: (context, state) => _buildPageWithNoTransition(
            context,
            state,
            const CustomerFormPage(),
          ),
        ),
        GoRoute(
          path: '/clientes/:id/editar',
          pageBuilder: (context, state) {
            final id = state.pathParameters['id']!;
            return _buildPageWithNoTransition(
              context,
              state,
              CustomerFormPage(customerId: id),
            );
          },
        ),
        GoRoute(
          path: '/clientes/:id',
          pageBuilder: (context, state) {
            final id = state.pathParameters['id']!;
            final initialTab = state.uri.queryParameters['tab'];
            return _buildPageWithNoTransition(
              context,
              state,
              ClientLogbookPage(
                customerId: id,
                initialTab: initialTab,
              ),
            );
          },
        ),
        GoRoute(
          path: '/clientes/bicicletas',
          pageBuilder: (context, state) => _buildPageWithNoTransition(
            context,
            state,
            const CustomerBikeDirectoryPage(),
          ),
        ),

        // Taller Module
        GoRoute(
          path: '/taller/pegas',
          pageBuilder: (context, state) => _buildPageWithNoTransition(
            context,
            state,
            const PegasTablePage(),
          ),
        ),
        GoRoute(
          path: '/taller/pegas/nueva',
          pageBuilder: (context, state) {
            final customerId = state.uri.queryParameters['customer_id'];
            return _buildPageWithNoTransition(
              context,
              state,
              MechanicJobFormPage(customerId: customerId),
            );
          },
        ),
        GoRoute(
          path: '/taller/pegas/:id',
          pageBuilder: (context, state) {
            final jobId = state.pathParameters['id']!;
            return _buildPageWithNoTransition(
              context,
              state,
              MechanicJobFormPage(jobId: jobId),
            );
          },
        ),

        // Inventory Module
        GoRoute(
          path: '/inventory/products',
          pageBuilder: (context, state) {
            final categoryId = state.uri.queryParameters['category'];
            final supplierId = state.uri.queryParameters['supplier'];
            return _buildPageWithNoTransition(
              context,
              state,
              ProductListPage(
                initialCategoryId: categoryId,
                initialSupplierId: supplierId,
              ),
            );
          },
        ),
        GoRoute(
          path: '/inventory/products/new',
          pageBuilder: (context, state) => _buildPageWithNoTransition(
            context,
            state,
            const ProductFormPage(),
          ),
        ),
        GoRoute(
          path: '/inventory/products/:id/edit',
          pageBuilder: (context, state) {
            final id = state.pathParameters['id']!;
            return _buildPageWithNoTransition(
              context,
              state,
              ProductFormPage(productId: id),
            );
          },
        ),
        GoRoute(
          path: '/inventory/categories',
          pageBuilder: (context, state) => _buildPageWithNoTransition(
            context,
            state,
            const CategoryListPage(),
          ),
        ),
        GoRoute(
          path: '/inventory/categories/new',
          pageBuilder: (context, state) => _buildPageWithNoTransition(
            context,
            state,
            const CategoryFormPage(),
          ),
        ),
        GoRoute(
          path: '/inventory/categories/:id/edit',
          pageBuilder: (context, state) {
            final id = state.pathParameters['id']!;
            return _buildPageWithNoTransition(
              context,
              state,
              CategoryFormPage(categoryId: id),
            );
          },
        ),
        GoRoute(
          path: '/inventory/movements',
          pageBuilder: (context, state) => _buildPageWithNoTransition(
            context,
            state,
            const StockMovementListPage(),
          ),
        ),

        // Sales Module
        GoRoute(
          path: '/sales/invoices',
          pageBuilder: (context, state) => _buildPageWithNoTransition(
            context,
            state,
            const InvoiceListPage(),
          ),
        ),
        GoRoute(
          path: '/sales/invoices/new',
          pageBuilder: (context, state) {
            final jobId = state.uri.queryParameters['job_id'];
            final customerId = state.uri.queryParameters['customer_id'];
            return _buildPageWithNoTransition(
              context,
              state,
              InvoiceFormPage(
                preselectedJobId: jobId,
                preselectedCustomerId: customerId,
              ),
            );
          },
        ),
        GoRoute(
          path: '/sales/invoices/:id',
          pageBuilder: (context, state) {
            final id = state.pathParameters['id']!;
            final extra = state.extra;
            final openPayment = extra is Map && extra['openPayment'] == true;
            return _buildPageWithNoTransition(
              context,
              state,
              InvoiceDetailPage(invoiceId: id, openPaymentOnLoad: openPayment),
            );
          },
        ),
        GoRoute(
          path: '/sales/invoices/:id/payment',
          pageBuilder: (context, state) {
            final id = state.pathParameters['id']!;
            return _buildPageWithNoTransition(
              context,
              state,
              InvoicePaymentPage(invoiceId: id),
            );
          },
        ),
        GoRoute(
          path: '/sales/invoices/:id/edit',
          pageBuilder: (context, state) {
            final id = state.pathParameters['id']!;
            return _buildPageWithNoTransition(
              context,
              state,
              InvoiceFormPage(invoiceId: id),
            );
          },
        ),
        GoRoute(
          path: '/sales/payments',
          pageBuilder: (context, state) => _buildPageWithNoTransition(
            context,
            state,
            const PaymentsPage(),
          ),
        ),

        // Purchases Module
        GoRoute(
          path: '/purchases/suppliers',
          pageBuilder: (context, state) => _buildPageWithNoTransition(
            context,
            state,
            const SupplierListPage(),
          ),
        ),
        GoRoute(
          path: '/purchases/suppliers/new',
          pageBuilder: (context, state) => _buildPageWithNoTransition(
            context,
            state,
            const SupplierFormPage(),
          ),
        ),
        GoRoute(
          path: '/purchases/suppliers/:id/edit',
          pageBuilder: (context, state) {
            final id = state.pathParameters['id']!;
            return _buildPageWithNoTransition(
              context,
              state,
              SupplierFormPage(supplierId: id),
            );
          },
        ),
        GoRoute(
          path: '/purchases',
          pageBuilder: (context, state) => _buildPageWithNoTransition(
            context,
            state,
            const PurchaseInvoiceListPage(),
          ),
        ),
        GoRoute(
          path: '/purchases/new',
          pageBuilder: (context, state) {
            final prepaymentParam = state.uri.queryParameters['prepayment'];
            final isPrepayment = prepaymentParam == 'true';
            print(
                '🔍 DEBUG: prepayment param = "$prepaymentParam", isPrepayment = $isPrepayment');
            return _buildPageWithNoTransition(
              context,
              state,
              PurchaseInvoiceFormPage(isPrepayment: isPrepayment),
            );
          },
        ),
        GoRoute(
          path: '/purchases/:id/detail',
          pageBuilder: (context, state) {
            final id = state.pathParameters['id']!;
            return _buildPageWithNoTransition(
              context,
              state,
              PurchaseInvoiceDetailPage(invoiceId: id),
            );
          },
        ),
        GoRoute(
          path: '/purchases/:id/edit',
          pageBuilder: (context, state) {
            final id = state.pathParameters['id']!;
            return _buildPageWithNoTransition(
              context,
              state,
              PurchaseInvoiceFormPage(invoiceId: id),
            );
          },
        ),
        GoRoute(
          path: '/purchases/payments',
          pageBuilder: (context, state) => _buildPageWithNoTransition(
            context,
            state,
            const MainLayout(
              child: PurchasePaymentsListPage(),
            ),
          ),
        ),

        // POS Module
        GoRoute(
          path: '/pos',
          pageBuilder: (context, state) => _buildPageWithNoTransition(
            context,
            state,
            const MainLayout(
              child: POSDashboardPage(),
            ),
          ),
        ),
        GoRoute(
          path: '/pos/cart',
          pageBuilder: (context, state) => _buildPageWithNoTransition(
            context,
            state,
            const MainLayout(
              child: POSCartPage(),
            ),
          ),
        ),
        GoRoute(
          path: '/pos/payment',
          pageBuilder: (context, state) => _buildPageWithNoTransition(
            context,
            state,
            const MainLayout(
              child: POSPaymentPage(),
            ),
          ),
        ),
        GoRoute(
          path: '/pos/receipt',
          pageBuilder: (context, state) {
            final transaction = state.extra as POSTransaction;
            return _buildPageWithNoTransition(
              context,
              state,
              MainLayout(
                child: POSReceiptPage(transaction: transaction),
              ),
            );
          },
        ),

        // Settings routes
        GoRoute(
          path: '/settings',
          pageBuilder: (context, state) => _buildPageWithNoTransition(
            context,
            state,
            const MainLayout(
              child: SettingsPage(),
            ),
          ),
        ),
        GoRoute(
          path: '/settings/factory-reset',
          pageBuilder: (context, state) => _buildPageWithNoTransition(
            context,
            state,
            const MainLayout(
              child: FactoryResetPage(),
            ),
          ),
        ),
        GoRoute(
          path: '/settings/appearance',
          pageBuilder: (context, state) => _buildPageWithNoTransition(
            context,
            state,
            const MainLayout(
              child: AppearanceSettingsPage(),
            ),
          ),
        ),

        // HR routes
        GoRoute(
          path: '/hr/employees',
          pageBuilder: (context, state) => _buildPageWithNoTransition(
            context,
            state,
            const EmployeeListPage(),
          ),
        ),
        GoRoute(
          path: '/hr/attendances',
          pageBuilder: (context, state) => _buildPageWithNoTransition(
            context,
            state,
            const AttendancesPage(),
          ),
        ),
        GoRoute(
          path: '/hr/kiosk',
          pageBuilder: (context, state) => _buildPageWithNoTransition(
            context,
            state,
            const KioskModePage(), // Full screen, no MainLayout
          ),
        ),

        // Website Module
        GoRoute(
          path: '/website',
          pageBuilder: (context, state) => _buildPageWithNoTransition(
            context,
            state,
            const WebsiteManagementPage(),
          ),
        ),
      ],
    );

    return router;
  }
}
