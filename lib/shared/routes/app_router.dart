import 'package:go_router/go_router.dart';

import '../widgets/main_layout.dart';
import '../screens/dashboard_screen.dart';
import '../screens/login_screen.dart';
import '../services/auth_service.dart';
import '../../modules/accounting/pages/account_list_page.dart';
import '../../modules/accounting/pages/account_form_page.dart';
import '../../modules/accounting/pages/journal_entry_list_page.dart';
import '../../modules/accounting/pages/journal_entry_form_page.dart';
import '../../modules/crm/pages/customer_list_page.dart';
import '../../modules/crm/pages/customer_form_page.dart';
import '../../modules/inventory/pages/product_list_page.dart';
import '../../modules/inventory/pages/product_form_page.dart';
import '../../modules/inventory/pages/category_list_page.dart';
import '../../modules/inventory/pages/category_form_page.dart';
import '../../modules/inventory/pages/stock_movement_list_page.dart';
import '../../modules/sales/pages/invoice_list_page.dart';
import '../../modules/sales/pages/invoice_form_page.dart';
import '../../modules/sales/pages/payment_form_page.dart';
import '../../modules/purchases/pages/supplier_list_page.dart';
import '../../modules/purchases/pages/supplier_form_page.dart';
import '../../modules/purchases/pages/purchase_order_list_page.dart';
import '../../modules/purchases/pages/purchase_order_form_page.dart';
import '../../modules/pos/pages/pos_dashboard_page.dart';
import '../../modules/pos/pages/pos_cart_page.dart';
import '../../modules/pos/pages/pos_payment_page.dart';
import '../../modules/pos/pages/pos_receipt_page.dart';
import '../../modules/pos/models/pos_transaction.dart';

class AppRouter {
  static GoRouter? _router;

  static GoRouter createRouter(AuthService authService) {
    _router ??= GoRouter(
      initialLocation: '/dashboard',
      refreshListenable: authService,
      redirect: (context, state) {
        if (authService.isInitializing) {
          return null;
        }

        final isLoggedIn = authService.isAuthenticated;
        final loggingIn = state.matchedLocation == '/login';

        if (!isLoggedIn && !loggingIn) {
          return '/login';
        }

        if (isLoggedIn && loggingIn) {
          return '/dashboard';
        }

        return null;
      },
      routes: [
      // Authentication
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginScreen(),
      ),
      
      // Dashboard
      GoRoute(
        path: '/dashboard',
        builder: (context, state) => const DashboardScreen(),
      ),
      
      // Accounting Module
      GoRoute(
        path: '/accounting/accounts',
        builder: (context, state) => const AccountListPage(),
      ),
      GoRoute(
        path: '/accounting/accounts/new',
        builder: (context, state) => const AccountFormPage(),
      ),
      GoRoute(
        path: '/accounting/accounts/:id/edit',
        builder: (context, state) {
          final id = state.pathParameters['id']!;
          return AccountFormPage(accountId: id);
        },
      ),
      GoRoute(
        path: '/accounting/journal-entries',
        builder: (context, state) => const JournalEntryListPage(),
      ),
      GoRoute(
        path: '/accounting/journal-entries/new',
        builder: (context, state) => const JournalEntryFormPage(),
      ),
      GoRoute(
        path: '/accounting/journal-entries/:id/edit',
        builder: (context, state) {
          final entryId = state.pathParameters['id']!;
          return JournalEntryFormPage(entryId: entryId);
        },
      ),
      
      // CRM Module
      GoRoute(
        path: '/crm/customers',
        builder: (context, state) => const CustomerListPage(),
      ),
      GoRoute(
        path: '/crm/customers/new',
        builder: (context, state) => const CustomerFormPage(),
      ),
      GoRoute(
        path: '/crm/customers/:id/edit',
        builder: (context, state) {
          final id = state.pathParameters['id']!;
          return CustomerFormPage(customerId: id);
        },
      ),
      
      // Inventory Module
      GoRoute(
        path: '/inventory/products',
        builder: (context, state) => const ProductListPage(),
      ),
      GoRoute(
        path: '/inventory/products/new',
        builder: (context, state) => const ProductFormPage(),
      ),
      GoRoute(
        path: '/inventory/products/:id/edit',
        builder: (context, state) {
          final id = state.pathParameters['id']!;
          return ProductFormPage(productId: id);
        },
      ),
      GoRoute(
        path: '/inventory/categories',
        builder: (context, state) => const CategoryListPage(),
      ),
      GoRoute(
        path: '/inventory/categories/new',
        builder: (context, state) => const CategoryFormPage(),
      ),
      GoRoute(
        path: '/inventory/categories/:id/edit',
        builder: (context, state) {
          final id = state.pathParameters['id']!;
          return CategoryFormPage(categoryId: id);
        },
      ),
      GoRoute(
        path: '/inventory/movements',
        builder: (context, state) => const StockMovementListPage(),
      ),
      
      // Sales Module
      GoRoute(
        path: '/sales/invoices',
        builder: (context, state) => const InvoiceListPage(),
      ),
      GoRoute(
        path: '/sales/invoices/new',
        builder: (context, state) => const InvoiceFormPage(),
      ),
      GoRoute(
        path: '/sales/invoices/:id/edit',
        builder: (context, state) {
          final id = state.pathParameters['id']!;
          return InvoiceFormPage(invoiceId: id);
        },
      ),
      GoRoute(
        path: '/payments/new',
        builder: (context, state) {
          final paymentId = state.uri.queryParameters['payment_id'];
          return PaymentFormPage(
            paymentId: paymentId != null ? int.parse(paymentId) : null,
          );
        },
      ),
      
      // Purchases Module
      GoRoute(
        path: '/purchases/suppliers',
        builder: (context, state) => const SupplierListPage(),
      ),
      GoRoute(
        path: '/purchases/suppliers/new',
        builder: (context, state) => const SupplierFormPage(),
      ),
      GoRoute(
        path: '/purchases/suppliers/:id/edit',
        builder: (context, state) {
          final id = state.pathParameters['id']!;
          return SupplierFormPage(supplierId: id);
        },
      ),
      GoRoute(
        path: '/purchases',
        builder: (context, state) => const PurchaseOrderListPage(),
      ),
      GoRoute(
        path: '/purchases/new',
        builder: (context, state) => const PurchaseOrderFormPage(),
      ),
      GoRoute(
        path: '/purchases/:id/edit',
        builder: (context, state) {
          final id = state.pathParameters['id']!;
          return PurchaseOrderFormPage(orderId: id);
        },
      ),
      
      // POS Module
      GoRoute(
        path: '/pos',
        builder: (context, state) => const MainLayout(
          child: POSDashboardPage(),
        ),
      ),
      GoRoute(
        path: '/pos/cart',
        builder: (context, state) => const MainLayout(
          child: POSCartPage(),
        ),
      ),
      GoRoute(
        path: '/pos/payment',
        builder: (context, state) => const MainLayout(
          child: POSPaymentPage(),
        ),
      ),
      GoRoute(
        path: '/pos/receipt',
        builder: (context, state) {
          final transaction = state.extra as POSTransaction;
          return MainLayout(
            child: POSReceiptPage(transaction: transaction),
          );
        },
      ),
      ],
    );

    return _router!;
  }
}
