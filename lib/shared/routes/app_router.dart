import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../widgets/main_layout.dart';
import '../pages/auth_callback_page.dart';
import '../pages/app_link_landing_page.dart';
import '../../modules/mail/pages/mail_inbox_page.dart' as mail;
import '../../modules/storage/pages/storage_page.dart' as storage;
import '../../public_store/widgets/persistent_editor_shell.dart';
import '../services/auth_service.dart';
// ERP / Admin Modules (Deferred to reduce initial bundle size)
import 'erp_routes_barrel.dart' deferred as erp
    show
        AcceptInvitationPage,
        AccountFormPage,
        AccountListPage,
        AnalyticsDashboardPage,
        AppearanceSettingsPage,
        AttendancesPage,
        BackupManagementPage,
        BalanceSheetPage,
        BikeBrandsPage,
        BikeEncyclopediaPage,
        BluetoothScannerPage,
        BugListPage,
        BusinessHoursSettingsPage,
        BrandFormPage,
        BrandListPage,
        CategoryFormPage,
        ClientLogbookPage,
        CompanySettingsPage,
        CustomerBikeDirectoryPage,
        CustomerFormPage,
        CustomerListPage,
        DashboardScreen,
        EmployeeChatPage,
        EmployeeDetailPage,
        EmployeeListPage,
        ExpenseCategoriesPage,
        ExpenseDetailPage,
        ExpenseFormPage,
        ExpenseListPage,
        F29DashboardPage,
        FactoryResetPageNew,
        FeaturedProductsPage,
        FinancialReportsHubPage,
        GenericWebToolPage,
        GoogleSheetsModulePage,
        HierarchicalCategoryPage,
        IncomeStatementPage,
        IntegrationsPage,
        InvoiceFormPage,
        InvoiceListPage,
        InvoicePaymentPage,
        JobStatusesPage,
        JobSubjectsPage,
        JournalEntryFormPage,
        JournalEntryListPage,
        KeyboardScannerPage,
        KioskModePage,
        LabelPrinterPage,
        LoginScreen,
        MechanicJobFormPage,
        MedicalLeavesPage,
        NavigationManagementPage,
        NiimbotSettingsPage,
        NotificationSettingsPage,
        NotionModulePage,
        OnlineOrdersPage,
        POSCartPage,
        POSDashboardPage,
        POSPaymentPage,
        POSReceiptPage,
        PageManagementPage,
        PaymentMethodsSettingsPage,
        MetaSettingsPage,
        WhatsAppSettingsPage,
        PaymentDetailPage,
        PaymentEditPage,
        PaymentsPage,
        PegasTablePage,
        ProductFormPage,
        ProductType,
        InventoryCatalogScope,
        ProductWebsiteVisibilityPage,
        WebsiteCatalogSection,
        ProductImportPage,
        ProductListPage,
        ServiceListPage,
        PurchaseInvoiceFormPage,
        PurchaseInvoiceListPage,
        PurchasePaymentDetailPage,
        PurchasePaymentEditPage,
        PurchasePaymentFormPage,
        PurchasePaymentsListPage,
        PurchaseReceiptDetailPage,
        RemoteScannerPage,
        ResetPasswordScreen,
        SalesByCustomerPage,
        SalesByProductDetailPage,
        SalesByProductPage,
        SalesReportsPage,
        SeoSettingsPage,
        SettingsPage,
        ShiftPlanningPage,
        SmartPurchaseListPage,
        SpokeLengthCalculatorPage,
        SpreadsheetDashboardPage,
        SpreadsheetEditorExitGuard,
        SpreadsheetEditorPage,
        StockMovementsPage,
        SupplierFormPage,
        SupplierListPage,
        UserManagementPage,
        WebsiteManagementPage,
        WebsiteDestinationManagementPage,
        WebsiteSettingsPage,
        WhatsAppWebModulePage,
        WheelBuilderWizardPage,
        WheelHubsPage,
        WheelRimsPage,
        WheelSpokesPage,
        WorkerHomePage,
        WorkerLoginPage,
        WorkshopCalendarPage,
        WorkspaceDemoPage;

// WebView Modules (Deferred via barrel)
// import '../../modules/webview_modules/webview_modules.dart'; // Already in barrel

// Public Store Pages
import '../../public_store/pages/public_home_page.dart';
import '../../public_store/pages/product_catalog_page.dart';
import '../../public_store/pages/product_detail_page.dart';
import '../../public_store/pages/cart_page.dart';
import '../../public_store/pages/checkout_page.dart';
import '../../public_store/pages/order_confirmation_page.dart';
import '../../public_store/pages/contact_page.dart';
import '../../public_store/pages/customer_auth_page.dart';

import '../../public_store/pages/customer_profile_page.dart';
import '../../public_store/pages/customer_addresses_page.dart';
import '../../public_store/pages/customer_orders_page.dart';
import '../../public_store/pages/customer_bikes_page.dart';
import '../../public_store/pages/customer_service_history_page.dart';
import '../../public_store/pages/dynamic_website_page.dart';
import '../../public_store/pages/static_policy_page.dart';
import '../../public_store/pages/customer_chat_list_page.dart';
import '../../public_store/pages/customer_chat_hub_page.dart';
import '../../public_store/pages/customer_chat_detail_page.dart';
import '../../public_store/pages/customer_dashboard_page.dart';
import '../../public_store/widgets/public_store_layout.dart';
import '../../public_store/utils/product_url.dart';
import '../../public_store/utils/public_store_tenant_resolver.dart';
import '../../public_store/services/public_store_scroll_state.dart';
import '../../modules/website/services/website_service.dart';
import '../utils/mercadopago_reference.dart';

class _EnsurePublicStoreScrollState extends StatelessWidget {
  final Widget child;

  const _EnsurePublicStoreScrollState({required this.child});

  @override
  Widget build(BuildContext context) {
    PublicStoreScrollState? existing;
    try {
      existing = context.read<PublicStoreScrollState>();
    } on ProviderNotFoundException {
      existing = null;
    }

    if (existing != null) return child;

    // In the store build (`main_store.dart`) this is already provided globally.
    // In the ERP build, store routes are mounted under the ERP router, so we
    // ensure the provider exists to avoid runtime crashes.
    return Provider(
      create: (_) => PublicStoreScrollState(),
      child: child,
    );
  }
}

// Helper wrapper for public store pages
class PublicStoreWrapper extends StatelessWidget {
  final Widget child;
  final bool enablePageViewScrolling;

  const PublicStoreWrapper({
    super.key,
    required this.child,
    this.enablePageViewScrolling = true,
  });

  @override
  Widget build(BuildContext context) {
    return _EnsurePublicStoreScrollState(
      child: PublicStoreLayout(
        enablePageViewScrolling: enablePageViewScrolling,
        child: child,
      ),
    );
  }
}

// Helper function to create pages without transitions
Page<dynamic> _buildPageWithNoTransition(
  BuildContext context,
  GoRouterState state,
  Widget child,
) {
  // Use state.pageKey to allow Flutter to preserve state when the route stack is updated
  // This ensures that back navigation restores the previous widget state instead of rebuilding it
  return NoTransitionPage<void>(
    key: state.pageKey,
    child: child,
  );
}

/// Shell pages must stay alive across navigation and query param changes
/// (e.g. `?edit=true`, `?preview=true`).
Page<dynamic> _buildShellPage(
  String key,
  Widget child,
) {
  return NoTransitionPage<void>(
    key: ValueKey<String>(key),
    child: child,
  );
}

class _PublicStoreShell extends StatefulWidget {
  final StatefulNavigationShell navigationShell;
  final String currentPath;

  const _PublicStoreShell({
    required this.navigationShell,
    required this.currentPath,
  });

  @override
  State<_PublicStoreShell> createState() => _PublicStoreShellState();
}

class _PublicStoreShellState extends State<_PublicStoreShell> {
  bool _storeDataLoadStarted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _ensureStoreDataLoaded();
    });
  }

  @override
  void didUpdateWidget(covariant _PublicStoreShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_storeDataLoadStarted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _ensureStoreDataLoaded();
      });
    }
  }

  Future<String?> _resolveStoreTenantId() async {
    return resolvePublicStoreTenantId(
      context,
      allowAuthenticatedFallback: true,
    );
  }

  Future<void> _ensureStoreDataLoaded() async {
    if (_storeDataLoadStarted) return;
    _storeDataLoadStarted = true;

    final tenantId = await _resolveStoreTenantId();
    if (!mounted) return;
    if (tenantId == null || tenantId.isEmpty) {
      _storeDataLoadStarted = false;
      return;
    }

    final websiteService = context.read<WebsiteService>();
    websiteService.preloadPublicStoreFromSynchronousCache(tenantId);
    await websiteService.loadPublicStoreDataUnified(
      tenantId,
      forceRefresh: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final disablePageViewScrolling =
        widget.currentPath.startsWith('/tienda/cuenta/mensajes/') ||
            widget.currentPath.startsWith('/tienda/cuenta/chats/');

    return PersistentEditorShell(
      child: _EnsurePublicStoreScrollState(
        child: PublicStoreLayout(
          enablePageViewScrolling: !disablePageViewScrolling,
          child: widget.navigationShell,
        ),
      ),
    );
  }
}

class AppRouter {
  static GoRouter createRouter(
    AuthService authService, {
    String? initialLocationOverride,
    bool forcePublicStoreHost = false,
  }) {
    PublicStoreRuntimeConfig.isErpMounted = !forcePublicStoreHost;

    // For public store on web: DON'T override initialLocation
    // Let GoRouter read from the browser URL (important for MercadoPago redirects)
    // For ERP: Start at /login if not overridden
    final String? effectiveInitialLocation;
    if (initialLocationOverride != null) {
      effectiveInitialLocation = initialLocationOverride;
    } else if (forcePublicStoreHost && kIsWeb) {
      // On web public store: let browser URL determine initial route
      effectiveInitialLocation = null;
    } else if (forcePublicStoreHost) {
      // On non-web public store: default to home
      effectiveInitialLocation = '/';
    } else {
      // ERP: default to login
      effectiveInitialLocation = '/login';
    }

    debugPrint(
        '🧭 [Router] Creating router with initialLocation: $effectiveInitialLocation, forcePublicStoreHost: $forcePublicStoreHost, kIsWeb: $kIsWeb');

    final router = GoRouter(
      initialLocation: effectiveInitialLocation,
      debugLogDiagnostics: false,
      // Only use refreshListenable on ERP (admin) routes
      // On public store, auth changes shouldn't cause route refreshes
      // This prevents the bug where authService.notifyListeners() causes unwanted navigation to /
      refreshListenable: forcePublicStoreHost ? null : authService,
      redirect: (context, state) {
        // Debug: redirect called
        if (authService.isInitializing) {
          return null;
        }

        // --------------------------------------------------------------------
        // MercadoPago return safety net
        // --------------------------------------------------------------------
        // In some cases MercadoPago may return to the site root (/) with query
        // parameters like external_reference/payment_id instead of our expected
        // /pedido/:id route. If we can infer the order id, redirect to the
        // order confirmation page so users don't end up on the homepage.
        // NOTE: Some hosting/browser flows may put params into the URL fragment
        // (e.g. https://site/#/?external_reference=...&collection_status=approved)
        // so we fall back to parsing fragment query parameters when needed.
        final Map<String, String> qp = () {
          final direct = state.uri.queryParameters;
          if (direct.isNotEmpty) return direct;

          final fragment = state.uri.fragment;
          if (fragment.isEmpty) return const <String, String>{};

          final qIndex = fragment.indexOf('?');
          if (qIndex < 0 || qIndex == fragment.length - 1) {
            return const <String, String>{};
          }

          final queryString = fragment.substring(qIndex + 1);
          try {
            return Uri.splitQueryString(queryString);
          } catch (_) {
            return const <String, String>{};
          }
        }();
        final externalReference =
            qp['external_reference'] ?? qp['externalReference'];
        final orderIdFromQuery =
            qp['pedido'] ?? qp['order'] ?? qp['order_id'] ?? qp['orderId'];
        final inferredOrderId =
            mercadoPagoOrderIdFromExternalReference(externalReference) ??
                mercadoPagoOrderIdFromExternalReference(orderIdFromQuery);

        String normalizePaymentStatus() {
          final explicit = qp['status'];
          if (explicit != null && explicit.isNotEmpty) return explicit;

          final collectionStatus =
              (qp['collection_status'] ?? qp['collectionStatus'] ?? '')
                  .toLowerCase();
          switch (collectionStatus) {
            case 'approved':
              return 'success';
            case 'pending':
            case 'in_process':
              return 'pending';
            case 'rejected':
            case 'cancelled':
              return 'failure';
          }

          final genericStatus =
              (qp['payment_status'] ?? qp['paymentStatus'] ?? '').toLowerCase();
          switch (genericStatus) {
            case 'approved':
              return 'success';
            case 'pending':
            case 'in_process':
              return 'pending';
            case 'rejected':
            case 'cancelled':
              return 'failure';
          }

          return '';
        }

        final path = state.uri.path;
        final isAlreadyOnOrder =
            path.startsWith('/pedido/') || path.startsWith('/tienda/pedido/');
        final isHomeLike =
            path == '/' || path == '/tienda' || path == '/tienda/';
        if (!isAlreadyOnOrder && isHomeLike && inferredOrderId != null) {
          final normalizedStatus = normalizePaymentStatus();
          final nextQp = Map<String, String>.from(qp);
          if (normalizedStatus.isNotEmpty) {
            nextQp['status'] = normalizedStatus;
          }

          // Prefer clean URLs on the public store.
          final destinationPath = normalizedStatus == 'failure'
              ? '/checkout'
              : '/pedido/$inferredOrderId';

          final destination = Uri(
            path: destinationPath,
            queryParameters: nextQp.isEmpty ? null : nextQp,
          ).toString();
          debugPrint(
              '🎯 [Router] MercadoPago return detected on home. Redirecting to: $destination');
          return destination;
        }

        // Treat any customer-facing path as public (clean + legacy, with slug support)
        bool isPublicPath(String path) {
          if (path == '/' || path.isEmpty) return true;

          // Common public prefixes (clean + legacy)
          const publicPrefixes = [
            '/auth/callback',
            '/app/open',
            '/productos',
            '/servicios',
            '/producto',
            '/carrito',
            '/checkout',
            '/pedido',
            '/contacto',
            '/cuenta',
            '/pagina',
            '/tienda',
            '/shop', // Legacy Google Merchant URLs
            // Policy pages (clean URLs)
            '/nosotros',
            '/terminos',
            '/privacidad',
            '/devoluciones',
            '/envios',
          ];

          for (final prefix in publicPrefixes) {
            if (path == prefix || path.startsWith('$prefix/')) {
              return true;
            }
          }
          return false;
        }

        final isPublicRoute = isPublicPath(path);

        // --------------------------------------------------------------------
        // ERP PREVIEW MODE: Prefer legacy /tienda/* URLs
        // --------------------------------------------------------------------
        // In the ERP app (localhost/ERP domain), the public store is mounted
        // under /tienda to keep it isolated from '/' (dashboard/login) and to
        // support module-scoped keep-alive.
        // If any clean public route is hit (e.g. header links loaded from DB),
        // redirect to the /tienda/* equivalent.
        if (!forcePublicStoreHost) {
          final p = state.uri.path;
          const policyPaths = {
            '/nosotros',
            '/terminos',
            '/privacidad',
            '/devoluciones',
            '/envios',
          };

          // Keep policy pages as clean URLs (they are part of the shell).
          if (!policyPaths.contains(p)) {
            String? legacyPath;

            if (p == '/productos' ||
                p.startsWith('/productos/') ||
                p == '/servicios' ||
                p.startsWith('/servicios/')) {
              legacyPath = Uri.parse(
                normalizePublicCatalogRouteForRuntime(
                  p,
                  isErpMounted: true,
                ),
              ).path;
            }
            if (p == '/carrito') legacyPath = '/tienda/carrito';
            if (p == '/checkout') legacyPath = '/tienda/checkout';
            if (p == '/contacto') legacyPath = '/tienda/contacto';

            if (p == '/cuenta' || p.startsWith('/cuenta/')) {
              legacyPath = '/tienda$p';
            }
            if (p.startsWith('/producto/') || p.startsWith('/pedido/')) {
              legacyPath = '/tienda$p';
            }
            if (p.startsWith('/pagina/')) {
              legacyPath = '/tienda$p';
            }

            // Don't rewrite /shop/* Google Merchant legacy URLs.
            if (p.startsWith('/shop/')) {
              legacyPath = null;
            }

            if (legacyPath != null && legacyPath != p) {
              final qp2 = state.uri.queryParameters;
              final destination = Uri(
                path: legacyPath,
                queryParameters: qp2.isEmpty ? null : qp2,
              ).toString();
              debugPrint(
                  '🧭 [Router] ERP public-store rewrite: $p -> $destination');
              return destination;
            }
          }
        }

        // Public store host (vinabike-store.web.app): ONLY allow public routes
        // Customer auth on store is for orders/addresses, NOT for ERP access
        if (forcePublicStoreHost) {
          // FIX: Redirect legacy ERP paths (/tienda/*) to clean paths
          // This catches defaults like '/tienda/productos' and rewrites to '/productos'
          if (path.startsWith('/tienda/')) {
            final newPath = path.replaceFirst('/tienda', '');
            final qp = state.uri.queryParameters;
            final destination = Uri(
              path: newPath,
              queryParameters: qp.isEmpty ? null : qp,
            ).toString();
            debugPrint(
                '🔄 [Router] Redirecting legacy path: $path -> $destination');
            return destination;
          }

          // If somehow a non-public path sneaks in, send to home (should be rare)
          if (!isPublicRoute) {
            return '/';
          }
          return null;
        }

        // --------------------------------------------------------------------
        // ERP DOMAIN PROTECTION: Redirect root '/' to login/dashboard
        // --------------------------------------------------------------------
        // The ERP domain should NEVER show the public store home page at root.
        // It must always redirect to the application interface.
        if (state.uri.path == '/') {
          return authService.isAuthenticated ? '/dashboard' : '/login';
        }

        final isLoggedIn = authService.isAuthenticated;

        // Allow access to public store routes without authentication
        if (isPublicRoute) {
          return null;
        }

        final loggingIn = state.matchedLocation == '/login';
        final workerLoggingIn = state.matchedLocation == '/worker/login';
        final workerRoute = state.uri.path == '/worker' ||
            state.uri.path.startsWith('/worker/');
        final resettingPassword = state.matchedLocation == '/reset-password';
        final acceptingInvitation =
            state.matchedLocation == '/accept-invitation';

        // Allow access to password reset and invitation acceptance without authentication
        if (resettingPassword || acceptingInvitation) {
          return null;
        }

        if (workerLoggingIn) {
          if (isLoggedIn &&
              authService.isAccessProfileLoaded &&
              authService.isWorker) {
            return '/worker';
          }
          return null;
        }

        if (workerRoute) {
          if (!isLoggedIn) {
            return '/worker/login';
          }
          if (authService.isAccessProfileLoaded && !authService.isWorker) {
            return '/worker/login?error=access_denied';
          }
          return null;
        }

        // Admin/ERP routes require authentication
        if (!isLoggedIn && !loggingIn) {
          return '/login';
        }

        // ============================================================================
        // STAFF-ONLY GUARD: Block non-staff users from ERP routes
        // ============================================================================
        // If user is logged in but NOT a staff member (no user_profiles entry),
        // they cannot access ERP routes. Redirect them to login with error.
        // IMPORTANT: Only block AFTER staff profile check completes to avoid loops.
        if (isLoggedIn &&
            authService.isStaffProfileLoaded &&
            !authService.isStaff &&
            !loggingIn) {
          debugPrint(
              '🚫 [Router] Non-staff user blocked from ERP route: ${state.uri.path}');
          return '/login?error=access_denied';
        }

        // Redirect logged-in STAFF users from login to dashboard
        // Only redirect after staff profile is confirmed loaded
        if (isLoggedIn &&
            authService.isStaffProfileLoaded &&
            authService.isStaff &&
            loggingIn) {
          return '/dashboard';
        }

        return null;
      },
      routes: [
        // ========================================
        // AUTH CALLBACK ROUTE (Public)
        // Prevents router redirects from stripping OAuth query params.
        // ========================================
        GoRoute(
          path: '/auth/callback',
          builder: (context, state) => const AuthCallbackPage(),
        ),

        GoRoute(
          path: '/app/open',
          pageBuilder: (context, state) => _buildPageWithNoTransition(
            context,
            state,
            AppLinkLandingPage(uri: state.uri),
          ),
        ),

        // ========================================
        // PUBLIC STORE ROUTES (Clean URLs)
        // Each route wraps its page with PublicStoreWrapper
        // ========================================

        // Public Store Home (clean URL)
        GoRoute(
          path: '/',
          pageBuilder: (context, state) => _buildPageWithNoTransition(
            context,
            state,
            const PublicStoreWrapper(child: PublicHomePage()),
          ),
        ),

        // Product Catalog (clean URL)
        GoRoute(
          path: '/productos',
          pageBuilder: (context, state) => _buildPageWithNoTransition(
            context,
            state,
            const PublicStoreWrapper(child: ProductCatalogPage()),
          ),
        ),

        GoRoute(
          path: '/productos/categoria/:category',
          pageBuilder: (context, state) => _buildPageWithNoTransition(
            context,
            state,
            const PublicStoreWrapper(child: ProductCatalogPage()),
          ),
        ),

        GoRoute(
          path: '/servicios',
          pageBuilder: (context, state) => _buildPageWithNoTransition(
            context,
            state,
            const PublicStoreWrapper(child: ProductCatalogPage()),
          ),
        ),

        GoRoute(
          path: '/servicios/categoria/:category',
          pageBuilder: (context, state) => _buildPageWithNoTransition(
            context,
            state,
            const PublicStoreWrapper(child: ProductCatalogPage()),
          ),
        ),

        // Canonical product detail. The ERP redirect above mounts this same
        // route under /tienda while the standalone store keeps the clean URL.
        GoRoute(
          path: '/productos/:slug/:sku',
          pageBuilder: (context, state) {
            final sku = state.pathParameters['sku']!;
            return _buildPageWithNoTransition(
              context,
              state,
              PublicStoreWrapper(
                child: ProductDetailPage(productId: 'sku:$sku'),
              ),
            );
          },
        ),

        // UUID/legacy product detail. ProductDetailPage upgrades it to the
        // canonical readable route after resolving the product.
        GoRoute(
          path: '/productos/:id',
          pageBuilder: (context, state) {
            final productId = state.pathParameters['id']!;
            return _buildPageWithNoTransition(
              context,
              state,
              PublicStoreWrapper(
                child: ProductDetailPage(productId: productId),
              ),
            );
          },
        ),

        // Legacy product detail (clean URL)
        GoRoute(
          path: '/producto/:id',
          pageBuilder: (context, state) {
            final productId = state.pathParameters['id']!;
            return _buildPageWithNoTransition(
              context,
              state,
              PublicStoreWrapper(
                child: ProductDetailPage(productId: productId),
              ),
            );
          },
        ),

        // Legacy /shop/:slug route for Google Merchant indexed URLs
        GoRoute(
          path: '/shop/:slug',
          pageBuilder: (context, state) {
            final slug = state.pathParameters['slug'] ?? '';
            debugPrint('🔗 [Router] Legacy /shop/ URL detected: $slug');

            String productId = slug;
            final skuMatch = RegExp(r'^[sS]?(\d+)').firstMatch(slug);
            if (skuMatch != null) {
              final sku = skuMatch.group(0)!.toUpperCase();
              productId = 'sku:$sku';
              debugPrint(
                  '🔗 [Router] Extracted SKU: $sku -> productId: $productId');
            } else {
              debugPrint('🔗 [Router] Could not extract SKU from slug: $slug');
            }

            return _buildPageWithNoTransition(
              context,
              state,
              PublicStoreWrapper(
                child: ProductDetailPage(productId: productId),
              ),
            );
          },
        ),

        // Shopping Cart (clean URL)
        GoRoute(
          path: '/carrito',
          pageBuilder: (context, state) => _buildPageWithNoTransition(
            context,
            state,
            const PublicStoreWrapper(child: CartPage()),
          ),
        ),

        // Checkout (clean URL)
        GoRoute(
          path: '/checkout',
          pageBuilder: (context, state) => _buildPageWithNoTransition(
            context,
            state,
            const PublicStoreWrapper(child: CheckoutPage()),
          ),
        ),

        // Order Confirmation (clean URL)
        GoRoute(
          path: '/pedido/:id',
          pageBuilder: (context, state) {
            final orderId = state.pathParameters['id']!;
            final status = state.uri.queryParameters['status'];
            return _buildPageWithNoTransition(
              context,
              state,
              PublicStoreWrapper(
                child: OrderConfirmationPage(
                  orderId: orderId,
                  paymentStatus: status,
                ),
              ),
            );
          },
        ),

        // Contact Page (clean URL)
        GoRoute(
          path: '/contacto',
          pageBuilder: (context, state) => _buildPageWithNoTransition(
            context,
            state,
            const PublicStoreWrapper(child: ContactPage()),
          ),
        ),

        // ========================================
        // PUBLIC STORE SHELL (ERP ONLY)
        // Keeps the public store module alive (no rebuild/dispose) while
        // navigating between core store pages + policy pages.
        // The real deployed store uses PublicStoreRouter (main_store.dart),
        // so this is specifically for ERP preview/edit flows.
        // ========================================
        if (!forcePublicStoreHost)
          StatefulShellRoute.indexedStack(
            builder: (context, state, navigationShell) {
              return _PublicStoreShell(
                navigationShell: navigationShell,
                currentPath: state.uri.path,
              );
            },
            branches: [
              // Core store navigation (ERP uses legacy /tienda/*)
              StatefulShellBranch(
                routes: [
                  GoRoute(
                    path: '/tienda',
                    pageBuilder: (context, state) => _buildShellPage(
                      'public_store_shell_tienda_home',
                      const PublicHomePage(),
                    ),
                  ),
                ],
              ),
              StatefulShellBranch(
                routes: [
                  GoRoute(
                    path: '/tienda/productos',
                    pageBuilder: (context, state) => _buildShellPage(
                      'public_store_shell_tienda_productos',
                      const ProductCatalogPage(),
                    ),
                    routes: [
                      GoRoute(
                        path: 'categoria/:category',
                        pageBuilder: (context, state) => _buildShellPage(
                          'public_store_shell_tienda_category_${state.pathParameters['category']}',
                          const ProductCatalogPage(),
                        ),
                      ),
                      GoRoute(
                        path: ':slug/:sku',
                        pageBuilder: (context, state) {
                          final sku = state.pathParameters['sku']!;
                          return _buildShellPage(
                            'public_store_shell_tienda_product_$sku',
                            ProductDetailPage(productId: 'sku:$sku'),
                          );
                        },
                      ),
                      GoRoute(
                        path: ':id',
                        pageBuilder: (context, state) {
                          final productId = state.pathParameters['id']!;
                          return _buildShellPage(
                            'public_store_shell_tienda_product_$productId',
                            ProductDetailPage(productId: productId),
                          );
                        },
                      ),
                    ],
                  ),
                ],
              ),
              StatefulShellBranch(
                routes: [
                  GoRoute(
                    path: '/tienda/servicios',
                    pageBuilder: (context, state) => _buildShellPage(
                      'public_store_shell_tienda_servicios',
                      const ProductCatalogPage(),
                    ),
                    routes: [
                      GoRoute(
                        path: 'categoria/:category',
                        pageBuilder: (context, state) => _buildShellPage(
                          'public_store_shell_tienda_service_category_${state.pathParameters['category']}',
                          const ProductCatalogPage(),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              StatefulShellBranch(
                routes: [
                  GoRoute(
                    path: '/tienda/carrito',
                    pageBuilder: (context, state) => _buildShellPage(
                      'public_store_shell_tienda_carrito',
                      const CartPage(),
                    ),
                  ),
                ],
              ),
              StatefulShellBranch(
                routes: [
                  GoRoute(
                    path: '/tienda/contacto',
                    pageBuilder: (context, state) => _buildShellPage(
                      'public_store_shell_tienda_contacto',
                      const ContactPage(),
                    ),
                  ),
                ],
              ),

              // Customer account (ERP legacy paths)
              StatefulShellBranch(
                routes: [
                  GoRoute(
                    path: '/tienda/cuenta',
                    pageBuilder: (context, state) => _buildShellPage(
                      'public_store_shell_tienda_cuenta',
                      const CustomerDashboardPage(),
                    ),
                    routes: [
                      GoRoute(
                        path: 'login',
                        pageBuilder: (context, state) => _buildShellPage(
                          'public_store_shell_tienda_cuenta_login',
                          const CustomerAuthPage(),
                        ),
                      ),
                      GoRoute(
                        path: 'perfil',
                        pageBuilder: (context, state) => _buildShellPage(
                          'public_store_shell_tienda_cuenta_perfil',
                          const CustomerProfilePage(),
                        ),
                      ),
                      GoRoute(
                        path: 'direcciones',
                        pageBuilder: (context, state) => _buildShellPage(
                          'public_store_shell_tienda_cuenta_direcciones',
                          const CustomerAddressesPage(),
                        ),
                      ),
                      GoRoute(
                        path: 'pedidos',
                        pageBuilder: (context, state) => _buildShellPage(
                          'public_store_shell_tienda_cuenta_pedidos',
                          const CustomerOrdersPage(),
                        ),
                      ),
                      GoRoute(
                        path: 'bicicletas',
                        pageBuilder: (context, state) => _buildShellPage(
                          'public_store_shell_tienda_cuenta_bicicletas',
                          const CustomerBikesPage(),
                        ),
                      ),
                      GoRoute(
                        path: 'servicios',
                        pageBuilder: (context, state) {
                          final bikeId = state.uri.queryParameters['bike_id'];
                          return _buildShellPage(
                            'public_store_shell_tienda_cuenta_servicios',
                            CustomerServiceHistoryPage(bikeId: bikeId),
                          );
                        },
                      ),

                      // Messaging (legacy account paths)
                      GoRoute(
                        path: 'mensajes',
                        pageBuilder: (context, state) => _buildShellPage(
                          'public_store_shell_tienda_cuenta_mensajes',
                          const CustomerChatListPage(),
                        ),
                      ),
                      GoRoute(
                        path: 'mensajes/:id',
                        pageBuilder: (context, state) {
                          final conversationId = state.pathParameters['id']!;
                          return _buildShellPage(
                            'public_store_shell_tienda_cuenta_mensajes_detail',
                            CustomerChatDetailPage(
                              conversationId: conversationId,
                            ),
                          );
                        },
                      ),

                      // New unified chat hub
                      GoRoute(
                        path: 'chats',
                        pageBuilder: (context, state) => _buildShellPage(
                          'public_store_shell_tienda_cuenta_chats',
                          const CustomerChatHubPage(),
                        ),
                      ),
                      GoRoute(
                        path: 'chats/:id',
                        pageBuilder: (context, state) {
                          final conversationId = state.pathParameters['id']!;
                          return _buildShellPage(
                            'public_store_shell_tienda_cuenta_chats_detail',
                            CustomerChatHubPage(
                              initialConversationId: conversationId,
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ],
              ),

              // Policy pages (clean URLs)
              StatefulShellBranch(
                routes: [
                  GoRoute(
                    path: '/nosotros',
                    pageBuilder: (context, state) => _buildShellPage(
                      'public_store_shell_policy_nosotros',
                      const StaticPolicyPage(
                        slug: 'nosotros',
                        fallbackTitle: 'Sobre Nosotros',
                      ),
                    ),
                  ),
                ],
              ),
              StatefulShellBranch(
                routes: [
                  GoRoute(
                    path: '/terminos',
                    pageBuilder: (context, state) => _buildShellPage(
                      'public_store_shell_policy_terminos',
                      const StaticPolicyPage(
                        slug: 'terminos',
                        fallbackTitle: 'Términos y Condiciones',
                      ),
                    ),
                  ),
                ],
              ),
              StatefulShellBranch(
                routes: [
                  GoRoute(
                    path: '/privacidad',
                    pageBuilder: (context, state) => _buildShellPage(
                      'public_store_shell_policy_privacidad',
                      const StaticPolicyPage(
                        slug: 'privacidad',
                        fallbackTitle: 'Política de Privacidad',
                      ),
                    ),
                  ),
                ],
              ),
              StatefulShellBranch(
                routes: [
                  GoRoute(
                    path: '/devoluciones',
                    pageBuilder: (context, state) => _buildShellPage(
                      'public_store_shell_policy_devoluciones',
                      const StaticPolicyPage(
                        slug: 'devoluciones',
                        fallbackTitle: 'Política de Devoluciones',
                      ),
                    ),
                  ),
                ],
              ),
              StatefulShellBranch(
                routes: [
                  GoRoute(
                    path: '/envios',
                    pageBuilder: (context, state) => _buildShellPage(
                      'public_store_shell_policy_envios',
                      const StaticPolicyPage(
                        slug: 'envios',
                        fallbackTitle: 'Información de Envíos',
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),

        // Public store host fallback: keep simple, plain policy routes.
        if (forcePublicStoreHost) ...[
          GoRoute(
            path: '/nosotros',
            pageBuilder: (context, state) => _buildPageWithNoTransition(
              context,
              state,
              const PublicStoreWrapper(
                child: StaticPolicyPage(
                  slug: 'nosotros',
                  fallbackTitle: 'Sobre Nosotros',
                ),
              ),
            ),
          ),
          GoRoute(
            path: '/terminos',
            pageBuilder: (context, state) => _buildPageWithNoTransition(
              context,
              state,
              const PublicStoreWrapper(
                child: StaticPolicyPage(
                  slug: 'terminos',
                  fallbackTitle: 'Términos y Condiciones',
                ),
              ),
            ),
          ),
          GoRoute(
            path: '/privacidad',
            pageBuilder: (context, state) => _buildPageWithNoTransition(
              context,
              state,
              const PublicStoreWrapper(
                child: StaticPolicyPage(
                  slug: 'privacidad',
                  fallbackTitle: 'Política de Privacidad',
                ),
              ),
            ),
          ),
          GoRoute(
            path: '/devoluciones',
            pageBuilder: (context, state) => _buildPageWithNoTransition(
              context,
              state,
              const PublicStoreWrapper(
                child: StaticPolicyPage(
                  slug: 'devoluciones',
                  fallbackTitle: 'Política de Devoluciones',
                ),
              ),
            ),
          ),
          GoRoute(
            path: '/envios',
            pageBuilder: (context, state) => _buildPageWithNoTransition(
              context,
              state,
              const PublicStoreWrapper(
                child: StaticPolicyPage(
                  slug: 'envios',
                  fallbackTitle: 'Información de Envíos',
                ),
              ),
            ),
          ),
        ],

        // ========================================
        // CUSTOMER ACCOUNT ROUTES
        // ========================================
        GoRoute(
          path: '/cuenta/login',
          pageBuilder: (context, state) => _buildPageWithNoTransition(
            context,
            state,
            const PublicStoreWrapper(child: CustomerAuthPage()),
          ),
        ),
        GoRoute(
          path: '/cuenta',
          pageBuilder: (context, state) => _buildPageWithNoTransition(
            context,
            state,
            const PublicStoreWrapper(child: CustomerDashboardPage()),
          ),
        ),
        GoRoute(
          path: '/cuenta/perfil',
          pageBuilder: (context, state) => _buildPageWithNoTransition(
            context,
            state,
            const PublicStoreWrapper(child: CustomerProfilePage()),
          ),
        ),
        GoRoute(
          path: '/cuenta/direcciones',
          pageBuilder: (context, state) => _buildPageWithNoTransition(
            context,
            state,
            const PublicStoreWrapper(child: CustomerAddressesPage()),
          ),
        ),
        GoRoute(
          path: '/cuenta/pedidos',
          pageBuilder: (context, state) => _buildPageWithNoTransition(
            context,
            state,
            const PublicStoreWrapper(child: CustomerOrdersPage()),
          ),
        ),
        GoRoute(
          path: '/cuenta/bicicletas',
          pageBuilder: (context, state) => _buildPageWithNoTransition(
            context,
            state,
            const PublicStoreWrapper(child: CustomerBikesPage()),
          ),
        ),
        GoRoute(
          path: '/cuenta/servicios',
          pageBuilder: (context, state) {
            final bikeId = state.uri.queryParameters['bike_id'];
            return _buildPageWithNoTransition(
              context,
              state,
              PublicStoreWrapper(
                child: CustomerServiceHistoryPage(bikeId: bikeId),
              ),
            );
          },
        ),

        // Chat / Support
        GoRoute(
          path: '/cuenta/mensajes',
          pageBuilder: (context, state) => _buildPageWithNoTransition(
            context,
            state,
            const PublicStoreWrapper(child: CustomerChatListPage()),
          ),
        ),
        GoRoute(
          path: '/cuenta/mensajes/:id',
          pageBuilder: (context, state) {
            final conversationId = state.pathParameters['id']!;
            return _buildPageWithNoTransition(
              context,
              state,
              PublicStoreWrapper(
                enablePageViewScrolling: false,
                child: CustomerChatDetailPage(conversationId: conversationId),
              ),
            );
          },
        ),

        // Chat / Support (New) - Unified Hub
        GoRoute(
          path: '/cuenta/chats',
          pageBuilder: (context, state) => _buildPageWithNoTransition(
            context,
            state,
            const PublicStoreWrapper(child: CustomerChatHubPage()),
          ),
        ),
        GoRoute(
          path: '/cuenta/chats/:id',
          pageBuilder: (context, state) {
            final conversationId = state.pathParameters['id']!;
            return _buildPageWithNoTransition(
              context,
              state,
              PublicStoreWrapper(
                enablePageViewScrolling: false,
                child:
                    CustomerChatHubPage(initialConversationId: conversationId),
              ),
            );
          },
        ),

        // Dynamic Pages (Clean URL)
        GoRoute(
          path: '/pagina/:slug',
          pageBuilder: (context, state) {
            final slug = state.pathParameters['slug'] ?? 'home';
            return _buildPageWithNoTransition(
              context,
              state,
              PublicStoreWrapper(child: DynamicWebsitePage(slug: slug)),
            );
          },
        ),

        // ========================================
        // LEGACY /tienda/* ROUTES
        // NOTE: Core /tienda pages are handled by the ERP-only shell above.
        // Keep only legacy detail/checkout/order routes here.
        // ========================================

        // Legacy mounted product detail.
        GoRoute(
          path: '/tienda/producto/:id',
          redirect: (context, state) {
            final query = state.uri.queryParameters;
            return Uri(
              path: '/tienda/productos/${state.pathParameters['id']!}',
              queryParameters: query.isEmpty ? null : query,
            ).toString();
          },
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
            final status = state.uri.queryParameters['status'];
            debugPrint('🎯 [Router] ORDER CONFIRMATION ROUTE MATCHED!');
            debugPrint('🎯 [Router] orderId: $orderId');
            debugPrint('🎯 [Router] status: $status');
            debugPrint('🎯 [Router] full URI: ${state.uri}');
            return _buildPageWithNoTransition(
              context,
              state,
              PublicStoreWrapper(
                child: OrderConfirmationPage(
                  orderId: orderId,
                  paymentStatus: status,
                ),
              ),
            );
          },
        ),

        // Dynamic Pages (Legacy)
        GoRoute(
          path: '/tienda/pagina/:slug',
          pageBuilder: (context, state) {
            final slug = state.pathParameters['slug'] ?? '';
            return _buildPageWithNoTransition(
              context,
              state,
              PublicStoreWrapper(child: DynamicWebsitePage(slug: slug)),
            );
          },
        ),

        // ========================================
        // ADMIN/ERP ROUTES (Auth Required)
        // ========================================

        // Authentication
        GoRoute(
          path: '/worker/login',
          pageBuilder: (context, state) => _buildDeferredPageWithNoTransition(
            context,
            state,
            erp.loadLibrary(),
            () => erp.WorkerLoginPage(),
          ),
        ),

        GoRoute(
          path: '/worker',
          pageBuilder: (context, state) => _buildDeferredPageWithNoTransition(
            context,
            state,
            erp.loadLibrary(),
            () => erp.WorkerHomePage(),
          ),
        ),

        GoRoute(
          path: '/login',
          pageBuilder: (context, state) => _buildDeferredPageWithNoTransition(
            context,
            state,
            erp.loadLibrary(),
            () => erp.LoginScreen(),
          ),
        ),

        // Password Reset
        GoRoute(
          path: '/reset-password',
          pageBuilder: (context, state) => _buildDeferredPageWithNoTransition(
            context,
            state,
            erp.loadLibrary(),
            () => erp.ResetPasswordScreen(),
          ),
        ),

        // Accept Invitation
        GoRoute(
          path: '/accept-invitation',
          pageBuilder: (context, state) {
            final token = state.uri.queryParameters['token'] ?? '';
            return _buildDeferredPageWithNoTransition(
              context,
              state,
              erp.loadLibrary(),
              () => erp.AcceptInvitationPage(token: token),
            );
          },
        ),

        // Dashboard
        GoRoute(
          path: '/dashboard',
          pageBuilder: (context, state) => _buildDeferredPageWithNoTransition(
            context,
            state,
            erp.loadLibrary(),
            () => erp.DashboardScreen(),
          ),
        ),

        // Workspace Demo (for testing workspace tab system)
        GoRoute(
          path: '/workspace-demo',
          pageBuilder: (context, state) => _buildDeferredPageWithNoTransition(
            context,
            state,
            erp.loadLibrary(),
            () => erp.WorkspaceDemoPage(),
          ),
        ),

        // Accounting Module
        GoRoute(
          path: '/accounting/accounts',
          pageBuilder: (context, state) => _buildDeferredPageWithNoTransition(
            context,
            state,
            erp.loadLibrary(),
            () => erp.AccountListPage(),
          ),
        ),
        GoRoute(
          path: '/accounting/expenses',
          pageBuilder: (context, state) => _buildDeferredPageWithNoTransition(
            context,
            state,
            erp.loadLibrary(),
            () => erp.ExpenseListPage(),
          ),
        ),
        GoRoute(
          path: '/accounting/expense-categories',
          pageBuilder: (context, state) => _buildDeferredPageWithNoTransition(
            context,
            state,
            erp.loadLibrary(),
            () => erp.ExpenseCategoriesPage(),
          ),
        ),
        GoRoute(
          path: '/accounting/expenses/new',
          pageBuilder: (context, state) => _buildDeferredPageWithNoTransition(
            context,
            state,
            erp.loadLibrary(),
            () => erp.ExpenseFormPage(),
          ),
        ),
        GoRoute(
          path: '/accounting/expenses/:id',
          pageBuilder: (context, state) {
            final id = state.pathParameters['id']!;
            return _buildDeferredPageWithNoTransition(
              context,
              state,
              erp.loadLibrary(),
              () => erp.ExpenseDetailPage(expenseId: id),
            );
          },
        ),
        GoRoute(
          path: '/accounting/expenses/:id/edit',
          pageBuilder: (context, state) {
            final id = state.pathParameters['id']!;
            return _buildDeferredPageWithNoTransition(
              context,
              state,
              erp.loadLibrary(),
              () => erp.ExpenseFormPage(expenseId: id),
            );
          },
        ),
        GoRoute(
          path: '/accounting/accounts/new',
          pageBuilder: (context, state) => _buildDeferredPageWithNoTransition(
            context,
            state,
            erp.loadLibrary(),
            () => erp.AccountFormPage(),
          ),
        ),
        GoRoute(
          path: '/accounting/accounts/:id/edit',
          pageBuilder: (context, state) {
            final id = state.pathParameters['id']!;
            return _buildDeferredPageWithNoTransition(
              context,
              state,
              erp.loadLibrary(),
              () => erp.AccountFormPage(accountId: id),
            );
          },
        ),
        GoRoute(
          path: '/accounting/journal-entries',
          pageBuilder: (context, state) => _buildDeferredPageWithNoTransition(
            context,
            state,
            erp.loadLibrary(),
            () => erp.JournalEntryListPage(),
          ),
        ),
        GoRoute(
          path: '/accounting/journal-entries/new',
          pageBuilder: (context, state) => _buildDeferredPageWithNoTransition(
            context,
            state,
            erp.loadLibrary(),
            () => erp.JournalEntryFormPage(),
          ),
        ),
        GoRoute(
          path: '/accounting/journal-entries/:id/edit',
          pageBuilder: (context, state) {
            final entryId = state.pathParameters['id']!;
            return _buildDeferredPageWithNoTransition(
              context,
              state,
              erp.loadLibrary(),
              () => erp.JournalEntryFormPage(entryId: entryId),
            );
          },
        ),

        // Financial Reports
        GoRoute(
          path: '/accounting/reports',
          pageBuilder: (context, state) => _buildDeferredPageWithNoTransition(
            context,
            state,
            erp.loadLibrary(),
            () => erp.FinancialReportsHubPage(),
          ),
        ),
        GoRoute(
          path: '/accounting/reports/income-statement',
          pageBuilder: (context, state) => _buildDeferredPageWithNoTransition(
            context,
            state,
            erp.loadLibrary(),
            () => erp.IncomeStatementPage(),
          ),
        ),
        GoRoute(
          path: '/accounting/reports/balance-sheet',
          pageBuilder: (context, state) => _buildDeferredPageWithNoTransition(
            context,
            state,
            erp.loadLibrary(),
            () => erp.BalanceSheetPage(),
          ),
        ),

        // Tax Reports (F29)
        GoRoute(
          path: '/tax-reports/f29',
          pageBuilder: (context, state) => _buildDeferredPageWithNoTransition(
            context,
            state,
            erp.loadLibrary(),
            () => erp.F29DashboardPage(),
          ),
        ),

        // Clientes Hub
        GoRoute(
          path: '/clientes',
          pageBuilder: (context, state) => _buildDeferredPageWithNoTransition(
            context,
            state,
            erp.loadLibrary(),
            () => erp.CustomerListPage(),
          ),
        ),
        GoRoute(
          path: '/clientes/nuevo',
          pageBuilder: (context, state) => _buildDeferredPageWithNoTransition(
            context,
            state,
            erp.loadLibrary(),
            () => erp.CustomerFormPage(),
          ),
        ),
        GoRoute(
          path: '/clientes/:id/editar',
          pageBuilder: (context, state) {
            final id = state.pathParameters['id']!;
            return _buildDeferredPageWithNoTransition(
              context,
              state,
              erp.loadLibrary(),
              () => erp.CustomerFormPage(customerId: id),
            );
          },
        ),
        GoRoute(
          path: '/clientes/:id',
          pageBuilder: (context, state) {
            final id = state.pathParameters['id']!;
            final initialTab = state.uri.queryParameters['tab'];
            final initialBikeId = state.uri.queryParameters['bike_id'];
            return _buildDeferredPageWithNoTransition(
              context,
              state,
              erp.loadLibrary(),
              () => erp.ClientLogbookPage(
                customerId: id,
                initialTab: initialTab,
                initialBikeId: initialBikeId,
              ),
            );
          },
        ),

        // Taller Module
        GoRoute(
          path: '/taller/pegas',
          pageBuilder: (context, state) => _buildDeferredPageWithNoTransition(
            context,
            state,
            erp.loadLibrary(),
            () => erp.PegasTablePage(),
          ),
        ),
        GoRoute(
          path: '/taller/estados',
          pageBuilder: (context, state) => _buildDeferredPageWithNoTransition(
            context,
            state,
            erp.loadLibrary(),
            () => erp.JobStatusesPage(),
          ),
        ),
        GoRoute(
          path: '/taller/sujetos',
          pageBuilder: (context, state) => _buildDeferredPageWithNoTransition(
            context,
            state,
            erp.loadLibrary(),
            () => erp.JobSubjectsPage(),
          ),
        ),
        GoRoute(
          path: '/taller/pegas/nueva',
          pageBuilder: (context, state) {
            return _buildDeferredPageWithNoTransition(
              context,
              state,
              erp.loadLibrary(),
              () => erp.MechanicJobFormPage(
                customerId: state.uri.queryParameters['customer_id'],
                initialBikeId: state.uri.queryParameters['bike_id'],
                initialJobType: state.uri.queryParameters['type'],
              ),
            );
          },
        ),
        GoRoute(
          path: '/taller/pegas/:id',
          pageBuilder: (context, state) {
            final jobId = state.pathParameters['id']!;
            return _buildDeferredPageWithNoTransition(
              context,
              state,
              erp.loadLibrary(),
              () => erp.MechanicJobFormPage(
                jobId: jobId,
                initialTab: state.uri.queryParameters['tab'],
              ),
            );
          },
        ),
        GoRoute(
          path: '/taller/bicicletas',
          pageBuilder: (context, state) => _buildDeferredPageWithNoTransition(
            context,
            state,
            erp.loadLibrary(),
            () => erp.CustomerBikeDirectoryPage(),
          ),
        ),
        GoRoute(
          path: '/taller/calendario',
          pageBuilder: (context, state) => _buildDeferredPageWithNoTransition(
            context,
            state,
            erp.loadLibrary(),
            () => erp.WorkshopCalendarPage(),
          ),
        ),
        GoRoute(
          path: '/taller/marcas-modelos',
          pageBuilder: (context, state) => _buildDeferredPageWithNoTransition(
            context,
            state,
            erp.loadLibrary(),
            () => erp.BikeBrandsPage(),
          ),
        ),

        // Bike Encyclopedia
        GoRoute(
          path: '/taller/bike-encyclopedia',
          pageBuilder: (context, state) => _buildDeferredPageWithNoTransition(
            context,
            state,
            erp.loadLibrary(),
            () => erp.BikeEncyclopediaPage(),
          ),
        ),

        // Wheel Building System
        GoRoute(
          path: '/taller/wheel-builder',
          pageBuilder: (context, state) => _buildDeferredPageWithNoTransition(
            context,
            state,
            erp.loadLibrary(),
            () => erp.WheelBuilderWizardPage(),
          ),
        ),
        GoRoute(
          path: '/taller/spoke-calculator',
          pageBuilder: (context, state) => _buildDeferredPageWithNoTransition(
            context,
            state,
            erp.loadLibrary(),
            () => erp.SpokeLengthCalculatorPage(),
          ),
        ),
        GoRoute(
          path: '/taller/wheel-hubs',
          pageBuilder: (context, state) => _buildDeferredPageWithNoTransition(
            context,
            state,
            erp.loadLibrary(),
            () => erp.WheelHubsPage(),
          ),
        ),
        GoRoute(
          path: '/taller/wheel-rims',
          pageBuilder: (context, state) => _buildDeferredPageWithNoTransition(
            context,
            state,
            erp.loadLibrary(),
            () => erp.WheelRimsPage(),
          ),
        ),
        GoRoute(
          path: '/taller/wheel-spokes',
          pageBuilder: (context, state) => _buildDeferredPageWithNoTransition(
            context,
            state,
            erp.loadLibrary(),
            () => erp.WheelSpokesPage(),
          ),
        ),

        // Inventory Module
        GoRoute(
          path: '/inventory/products',
          pageBuilder: (context, state) {
            final categoryId = state.uri.queryParameters['category'];
            final supplierId = state.uri.queryParameters['supplier'];
            final refreshToken = state.uri.queryParameters['refresh'];
            return _buildDeferredPageWithNoTransition(
              context,
              state,
              erp.loadLibrary(),
              () => erp.ProductListPage(
                initialCategoryId: categoryId,
                initialSupplierId: supplierId,
                refreshToken: refreshToken,
                catalogScope: erp.InventoryCatalogScope.products,
              ),
            );
          },
          routes: [
            GoRoute(
              path: 'new',
              pageBuilder: (context, state) =>
                  _buildDeferredPageWithNoTransition(
                context,
                state,
                erp.loadLibrary(),
                () => erp.ProductFormPage(lockProductType: true),
              ),
            ),
            GoRoute(
              path: 'import',
              pageBuilder: (context, state) =>
                  _buildDeferredPageWithNoTransition(
                context,
                state,
                erp.loadLibrary(),
                () => erp.ProductImportPage(),
              ),
            ),
            GoRoute(
              path: ':id/edit',
              pageBuilder: (context, state) {
                final id = state.pathParameters['id']!;
                return _buildDeferredPageWithNoTransition(
                  context,
                  state,
                  erp.loadLibrary(),
                  () => erp.ProductFormPage(
                    productId: id,
                    lockProductType: true,
                  ),
                );
              },
            ),
          ],
        ),
        GoRoute(
          path: '/inventory/services',
          pageBuilder: (context, state) {
            final categoryId = state.uri.queryParameters['category'];
            final refreshToken = state.uri.queryParameters['refresh'];
            return _buildDeferredPageWithNoTransition(
              context,
              state,
              erp.loadLibrary(),
              () => erp.ServiceListPage(
                initialCategoryId: categoryId,
                refreshToken: refreshToken,
              ),
            );
          },
          routes: [
            GoRoute(
              path: 'new',
              pageBuilder: (context, state) =>
                  _buildDeferredPageWithNoTransition(
                context,
                state,
                erp.loadLibrary(),
                () => erp.ProductFormPage(
                  initialProductType: erp.ProductType.service,
                  lockProductType: true,
                ),
              ),
            ),
            GoRoute(
              path: ':id/edit',
              pageBuilder: (context, state) {
                final id = state.pathParameters['id']!;
                return _buildDeferredPageWithNoTransition(
                  context,
                  state,
                  erp.loadLibrary(),
                  () => erp.ProductFormPage(
                    productId: id,
                    initialProductType: erp.ProductType.service,
                    lockProductType: true,
                  ),
                );
              },
            ),
          ],
        ),
        GoRoute(
          path: '/inventory/categories',
          pageBuilder: (context, state) => _buildDeferredPageWithNoTransition(
            context,
            state,
            erp.loadLibrary(),
            () => erp.HierarchicalCategoryPage(),
          ),
          routes: [
            GoRoute(
              path: 'new',
              pageBuilder: (context, state) {
                final parentId = state.uri.queryParameters['parent'];
                return _buildDeferredPageWithNoTransition(
                  context,
                  state,
                  erp.loadLibrary(),
                  () => erp.CategoryFormPage(parentCategoryId: parentId),
                );
              },
            ),
            GoRoute(
              path: ':id',
              pageBuilder: (context, state) {
                final id = state.pathParameters['id']!;
                return _buildDeferredPageWithNoTransition(
                  context,
                  state,
                  erp.loadLibrary(),
                  () => erp.HierarchicalCategoryPage(categoryId: id),
                );
              },
              routes: [
                GoRoute(
                  path: 'edit',
                  pageBuilder: (context, state) {
                    final id = state.pathParameters['id']!;
                    return _buildDeferredPageWithNoTransition(
                      context,
                      state,
                      erp.loadLibrary(),
                      () => erp.CategoryFormPage(categoryId: id),
                    );
                  },
                ),
              ],
            ),
          ],
        ),
        GoRoute(
          path: '/inventory/brands',
          pageBuilder: (context, state) => _buildDeferredPageWithNoTransition(
            context,
            state,
            erp.loadLibrary(),
            () => erp.BrandListPage(),
          ),
          routes: [
            GoRoute(
              path: 'new',
              pageBuilder: (context, state) =>
                  _buildDeferredPageWithNoTransition(
                context,
                state,
                erp.loadLibrary(),
                () => erp.BrandFormPage(),
              ),
            ),
            GoRoute(
              path: ':id/edit',
              pageBuilder: (context, state) {
                final id = state.pathParameters['id']!;
                return _buildDeferredPageWithNoTransition(
                  context,
                  state,
                  erp.loadLibrary(),
                  () => erp.BrandFormPage(brandId: id),
                );
              },
            ),
          ],
        ),
        GoRoute(
          path: '/inventory/movements',
          pageBuilder: (context, state) => _buildDeferredPageWithNoTransition(
            context,
            state,
            erp.loadLibrary(),
            () => erp.StockMovementsPage(),
          ),
        ),

        // Sales Module
        GoRoute(
          path: '/sales/invoices',
          pageBuilder: (context, state) {
            final initialInvoiceId =
                state.uri.queryParameters['selectedInvoiceId'] ??
                    state.uri.queryParameters['invoiceId'];
            final initialInvoiceNumber =
                state.uri.queryParameters['selectedInvoiceNumber'] ??
                    state.uri.queryParameters['invoiceNumber'];
            final forceSplitView =
                state.uri.queryParameters['view'] == 'split' ||
                    state.uri.queryParameters['preview'] == '1';
            final invoiceSelectionKey =
                initialInvoiceId ?? initialInvoiceNumber;
            return _buildDeferredPageWithNoTransition(
              context,
              state,
              erp.loadLibrary(),
              () => erp.InvoiceListPage(
                initialInvoiceId: initialInvoiceId,
                initialInvoiceNumber: initialInvoiceNumber,
                forceSplitView: forceSplitView,
              ),
              pageKeyOverride: invoiceSelectionKey == null
                  ? null
                  : ValueKey(
                      'sales-invoices:$invoiceSelectionKey:${forceSplitView ? 'split' : 'list'}',
                    ),
            );
          },
        ),
        GoRoute(
          path: '/sales/invoices/new',
          pageBuilder: (context, state) {
            final jobId = state.uri.queryParameters['job_id'];
            final customerId = state.uri.queryParameters['customer_id'];
            return _buildDeferredPageWithNoTransition(
              context,
              state,
              erp.loadLibrary(),
              () => erp.InvoiceFormPage(
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
            final referrer = state.uri.queryParameters['referrer'];
            final jobId = state.uri.queryParameters['jobId'];
            return _buildDeferredPageWithNoTransition(
              context,
              state,
              erp.loadLibrary(),
              () => erp.InvoiceFormPage(
                invoiceId: id,
                referrer: referrer,
                referrerJobId: jobId,
              ),
            );
          },
        ),
        GoRoute(
          path: '/sales/invoices/:id/payment',
          pageBuilder: (context, state) {
            final id = state.pathParameters['id']!;
            return _buildDeferredPageWithNoTransition(
              context,
              state,
              erp.loadLibrary(),
              () => erp.InvoicePaymentPage(invoiceId: id),
            );
          },
        ),
        GoRoute(
          path: '/sales/invoices/:id/edit',
          pageBuilder: (context, state) {
            final id = state.pathParameters['id']!;
            final referrer = state.uri.queryParameters['referrer'];
            final jobId = state.uri.queryParameters['jobId'];
            return _buildDeferredPageWithNoTransition(
              context,
              state,
              erp.loadLibrary(),
              () => erp.InvoiceFormPage(
                invoiceId: id,
                referrer: referrer,
                referrerJobId: jobId,
              ),
            );
          },
        ),
        GoRoute(
          path: '/sales/payments',
          pageBuilder: (context, state) {
            final paymentId = state.uri.queryParameters['paymentId'];
            return _buildDeferredPageWithNoTransition(
              context,
              state,
              erp.loadLibrary(),
              () => erp.PaymentsPage(
                highlightPaymentId: paymentId,
                initialOpenRequestId: state.uri.queryParameters['openRequest'],
              ),
            );
          },
        ),
        GoRoute(
          path: '/sales/payments/:id/edit',
          pageBuilder: (context, state) {
            final id = state.pathParameters['id']!;
            return _buildDeferredPageWithNoTransition(
              context,
              state,
              erp.loadLibrary(),
              () => erp.PaymentEditPage(paymentId: id),
            );
          },
        ),
        GoRoute(
          path: '/sales/payments/:id',
          pageBuilder: (context, state) {
            final id = state.pathParameters['id']!;
            return _buildDeferredPageWithNoTransition(
              context,
              state,
              erp.loadLibrary(),
              () => erp.PaymentDetailPage(paymentId: id),
            );
          },
        ),

        // Sales Reports
        GoRoute(
          path: '/sales/reports',
          pageBuilder: (context, state) => _buildDeferredPageWithNoTransition(
            context,
            state,
            erp.loadLibrary(),
            () => erp.SalesReportsPage(),
          ),
        ),
        GoRoute(
          path: '/sales/reports/by-product',
          pageBuilder: (context, state) => _buildDeferredPageWithNoTransition(
            context,
            state,
            erp.loadLibrary(),
            () => erp.SalesByProductPage(),
          ),
        ),
        GoRoute(
          path: '/sales/reports/by-product/:id',
          pageBuilder: (context, state) {
            final id = state.pathParameters['id']!;
            final name = state.uri.queryParameters['name'];
            final startStr = state.uri.queryParameters['start'];
            final endStr = state.uri.queryParameters['end'];

            DateTime? start = startStr != null && startStr.isNotEmpty
                ? DateTime.tryParse(startStr)
                : null;
            DateTime? end = endStr != null && endStr.isNotEmpty
                ? DateTime.tryParse(endStr)
                : null;

            return _buildDeferredPageWithNoTransition(
              context,
              state,
              erp.loadLibrary(),
              () => erp.SalesByProductDetailPage(
                productId: id,
                productName: name,
                startDate: start,
                endDate: end,
              ),
            );
          },
        ),
        GoRoute(
          path: '/sales/reports/by-customer',
          pageBuilder: (context, state) => _buildDeferredPageWithNoTransition(
            context,
            state,
            erp.loadLibrary(),
            () => erp.SalesByCustomerPage(),
          ),
        ),

        // Messaging Module
        GoRoute(
          path: '/chat',
          pageBuilder: (context, state) {
            final conversationId = state.uri.queryParameters['conversation'];
            return _buildDeferredPageWithNoTransition(
              context,
              state,
              erp.loadLibrary(),
              () => MainLayout(
                child: erp.EmployeeChatPage(
                  initialConversationId: conversationId,
                ),
              ),
            );
          },
        ),

        // Purchases Module
        GoRoute(
          path: '/purchases/suppliers',
          pageBuilder: (context, state) => _buildDeferredPageWithNoTransition(
            context,
            state,
            erp.loadLibrary(),
            () => erp.SupplierListPage(),
          ),
        ),
        GoRoute(
          path: '/purchases/suppliers/new',
          pageBuilder: (context, state) => _buildDeferredPageWithNoTransition(
            context,
            state,
            erp.loadLibrary(),
            () => erp.SupplierFormPage(),
          ),
        ),
        GoRoute(
          path: '/purchases/suppliers/:id/edit',
          pageBuilder: (context, state) {
            final id = state.pathParameters['id']!;
            return _buildDeferredPageWithNoTransition(
              context,
              state,
              erp.loadLibrary(),
              () => erp.SupplierFormPage(supplierId: id),
            );
          },
        ),
        GoRoute(
          path: '/purchases',
          pageBuilder: (context, state) => _buildDeferredPageWithNoTransition(
            context,
            state,
            erp.loadLibrary(),
            () => erp.PurchaseInvoiceListPage(),
          ),
        ),
        // Specific routes MUST come before dynamic :id route
        GoRoute(
          path: '/purchases/new',
          pageBuilder: (context, state) {
            final prepaymentParam = state.uri.queryParameters['prepayment'];
            final isPrepayment = prepaymentParam == 'true';
            debugPrint(
                '🔍 DEBUG: prepayment param = "$prepaymentParam", isPrepayment = $isPrepayment');
            return _buildDeferredPageWithNoTransition(
              context,
              state,
              erp.loadLibrary(),
              () => erp.PurchaseInvoiceFormPage(isPrepayment: isPrepayment),
            );
          },
        ),
        GoRoute(
          path: '/purchases/payments',
          pageBuilder: (context, state) {
            final paymentId = state.uri.queryParameters['paymentId'];
            return _buildDeferredPageWithNoTransition(
              context,
              state,
              erp.loadLibrary(),
              () => MainLayout(
                child: erp.PurchasePaymentsListPage(
                  highlightPaymentId: paymentId,
                ),
              ),
            );
          },
        ),
        GoRoute(
          path: '/purchases/payments/:id/edit',
          pageBuilder: (context, state) {
            final id = state.pathParameters['id']!;
            return _buildDeferredPageWithNoTransition(
              context,
              state,
              erp.loadLibrary(),
              () => erp.PurchasePaymentEditPage(paymentId: id),
            );
          },
        ),
        GoRoute(
          path: '/purchases/payments/:id',
          pageBuilder: (context, state) {
            final id = state.pathParameters['id']!;
            return _buildDeferredPageWithNoTransition(
              context,
              state,
              erp.loadLibrary(),
              () => erp.PurchasePaymentDetailPage(paymentId: id),
            );
          },
        ),
        GoRoute(
          path: '/purchases/smart-list',
          pageBuilder: (context, state) => _buildDeferredPageWithNoTransition(
            context,
            state,
            erp.loadLibrary(),
            () => erp.SmartPurchaseListPage(),
          ),
        ),
        GoRoute(
          path: '/purchases/receipts/:receiptId',
          pageBuilder: (context, state) {
            final receiptId = state.pathParameters['receiptId']!;
            return _buildDeferredPageWithNoTransition(
              context,
              state,
              erp.loadLibrary(),
              () => erp.PurchaseReceiptDetailPage(receiptId: receiptId),
            );
          },
        ),
        // Dynamic route for viewing/editing invoices
        GoRoute(
          path: '/purchases/:id',
          pageBuilder: (context, state) {
            final id = state.pathParameters['id']!;
            final referrer = state.uri.queryParameters['referrer'];
            // Single page for create, edit, and workflow (like sales invoice)
            return _buildDeferredPageWithNoTransition(
              context,
              state,
              erp.loadLibrary(),
              () => erp.PurchaseInvoiceFormPage(
                invoiceId: id,
                referrer: referrer,
              ),
            );
          },
        ),
        GoRoute(
          path: '/purchases/:id/detail',
          pageBuilder: (context, state) {
            final id = state.pathParameters['id']!;
            // DEPRECATED: Detail page is no longer used, redirects to form page
            return _buildDeferredPageWithNoTransition(
              context,
              state,
              erp.loadLibrary(),
              () => erp.PurchaseInvoiceFormPage(invoiceId: id),
            );
          },
        ),
        GoRoute(
          path: '/purchases/:id/edit',
          pageBuilder: (context, state) {
            final id = state.pathParameters['id']!;
            // DEPRECATED: Edit route is no longer used, redirects to form page
            return _buildDeferredPageWithNoTransition(
              context,
              state,
              erp.loadLibrary(),
              () => erp.PurchaseInvoiceFormPage(invoiceId: id),
            );
          },
        ),
        GoRoute(
          path: '/purchases/invoices/:id/payment',
          pageBuilder: (context, state) {
            final id = state.pathParameters['id']!;
            return _buildDeferredPageWithNoTransition(
              context,
              state,
              erp.loadLibrary(),
              () => erp.PurchasePaymentFormPage(invoiceId: id),
            );
          },
        ),

        // POS Module
        GoRoute(
          path: '/pos',
          pageBuilder: (context, state) => _buildDeferredPageWithNoTransition(
            context,
            state,
            erp.loadLibrary(),
            () => MainLayout(
              child: erp.POSDashboardPage(),
            ),
          ),
        ),
        GoRoute(
          path: '/pos/cart',
          pageBuilder: (context, state) => _buildDeferredPageWithNoTransition(
            context,
            state,
            erp.loadLibrary(),
            () => MainLayout(
              child: erp.POSCartPage(),
            ),
          ),
        ),
        GoRoute(
          path: '/pos/payment',
          pageBuilder: (context, state) => _buildDeferredPageWithNoTransition(
            context,
            state,
            erp.loadLibrary(),
            () => MainLayout(
              child: erp.POSPaymentPage(),
            ),
          ),
        ),
        GoRoute(
          path: '/pos/receipt',
          pageBuilder: (context, state) {
            // Note: POSTransaction type requires direct import, not deferred
            final transaction = state.extra;
            return _buildDeferredPageWithNoTransition(
              context,
              state,
              erp.loadLibrary(),
              () => MainLayout(
                child: erp.POSReceiptPage(transaction: transaction),
              ),
            );
          },
        ),

        // Settings routes
        GoRoute(
          path: '/settings',
          pageBuilder: (context, state) => _buildDeferredPageWithNoTransition(
            context,
            state,
            erp.loadLibrary(),
            () => MainLayout(
              child: erp.SettingsPage(),
            ),
          ),
        ),
        GoRoute(
          path: '/settings/factory-reset',
          pageBuilder: (context, state) => _buildDeferredPageWithNoTransition(
            context,
            state,
            erp.loadLibrary(),
            () => MainLayout(
              child: erp.FactoryResetPageNew(),
            ),
          ),
        ),
        GoRoute(
          path: '/settings/backup',
          pageBuilder: (context, state) => _buildDeferredPageWithNoTransition(
            context,
            state,
            erp.loadLibrary(),
            () => erp.BackupManagementPage(),
          ),
        ),
        GoRoute(
          path: '/settings/appearance',
          pageBuilder: (context, state) => _buildDeferredPageWithNoTransition(
            context,
            state,
            erp.loadLibrary(),
            () => MainLayout(
              child: erp.AppearanceSettingsPage(),
            ),
          ),
        ),
        GoRoute(
          path: '/settings/company',
          pageBuilder: (context, state) => _buildDeferredPageWithNoTransition(
            context,
            state,
            erp.loadLibrary(),
            () => MainLayout(
              child: erp.CompanySettingsPage(),
            ),
          ),
        ),
        GoRoute(
          path: '/settings/business-hours',
          pageBuilder: (context, state) => _buildDeferredPageWithNoTransition(
            context,
            state,
            erp.loadLibrary(),
            () => MainLayout(
              child: erp.BusinessHoursSettingsPage(),
            ),
          ),
        ),
        GoRoute(
          path: '/settings/users',
          pageBuilder: (context, state) => _buildDeferredPageWithNoTransition(
            context,
            state,
            erp.loadLibrary(),
            () => MainLayout(
              child: erp.UserManagementPage(),
            ),
          ),
        ),
        GoRoute(
          path: '/settings/whatsapp',
          pageBuilder: (context, state) => _buildDeferredPageWithNoTransition(
            context,
            state,
            erp.loadLibrary(),
            () => MainLayout(
              child: erp.WhatsAppSettingsPage(),
            ),
          ),
        ),
        GoRoute(
          path: '/settings/meta',
          pageBuilder: (context, state) => _buildDeferredPageWithNoTransition(
            context,
            state,
            erp.loadLibrary(),
            // Deferred page classes cannot be constructed with const.
            // ignore: prefer_const_constructors
            () => MainLayout(
              child: erp.MetaSettingsPage(),
            ),
          ),
        ),
        GoRoute(
          path: '/settings/payment-methods',
          pageBuilder: (context, state) => _buildDeferredPageWithNoTransition(
            context,
            state,
            erp.loadLibrary(),
            () => MainLayout(
              child: erp.PaymentMethodsSettingsPage(),
            ),
          ),
        ),
        GoRoute(
          path: '/settings/bluetooth-scanner',
          pageBuilder: (context, state) => _buildDeferredPageWithNoTransition(
            context,
            state,
            erp.loadLibrary(),
            () => erp.BluetoothScannerPage(),
          ),
        ),
        GoRoute(
          path: '/settings/keyboard-scanner',
          pageBuilder: (context, state) => _buildDeferredPageWithNoTransition(
            context,
            state,
            erp.loadLibrary(),
            () => erp.KeyboardScannerPage(),
          ),
        ),
        GoRoute(
          path: '/settings/remote-scanner',
          pageBuilder: (context, state) => _buildDeferredPageWithNoTransition(
            context,
            state,
            erp.loadLibrary(),
            () => MainLayout(
              child: erp.RemoteScannerPage(),
            ),
          ),
        ),
        GoRoute(
          path: '/settings/label-printer',
          pageBuilder: (context, state) => _buildDeferredPageWithNoTransition(
            context,
            state,
            erp.loadLibrary(),
            () => erp.NiimbotSettingsPage(),
          ),
        ),
        GoRoute(
          path: '/label-printer',
          pageBuilder: (context, state) => _buildDeferredPageWithNoTransition(
            context,
            state,
            erp.loadLibrary(),
            () => erp.LabelPrinterPage(),
          ),
        ),
        GoRoute(
          path: '/settings/notifications',
          pageBuilder: (context, state) => _buildDeferredPageWithNoTransition(
            context,
            state,
            erp.loadLibrary(),
            () => MainLayout(
              child: erp.NotificationSettingsPage(),
            ),
          ),
        ),

        // HR routes
        GoRoute(
          path: '/hr/employees',
          pageBuilder: (context, state) => _buildDeferredPageWithNoTransition(
            context,
            state,
            erp.loadLibrary(),
            () => erp.EmployeeListPage(),
          ),
        ),
        GoRoute(
          path: '/hr/employees/:id',
          pageBuilder: (context, state) => _buildDeferredPageWithNoTransition(
            context,
            state,
            erp.loadLibrary(),
            () =>
                erp.EmployeeDetailPage(employeeId: state.pathParameters['id']!),
          ),
        ),
        GoRoute(
          path: '/hr/planning',
          pageBuilder: (context, state) => _buildDeferredPageWithNoTransition(
            context,
            state,
            erp.loadLibrary(),
            () => erp.ShiftPlanningPage(),
          ),
        ),
        GoRoute(
          path: '/hr/attendances',
          pageBuilder: (context, state) => _buildDeferredPageWithNoTransition(
            context,
            state,
            erp.loadLibrary(),
            () => erp.AttendancesPage(
              initialView: state.uri.queryParameters['view'],
              initialDate:
                  DateTime.tryParse(state.uri.queryParameters['date'] ?? ''),
              initialEmployeeId: state.uri.queryParameters['employeeId'],
              initialAttendanceId: state.uri.queryParameters['attendanceId'],
              initialOpenRequestId: state.uri.queryParameters['openRequest'],
            ),
          ),
        ),
        GoRoute(
          path: '/hr/kiosk',
          pageBuilder: (context, state) => _buildDeferredPageWithNoTransition(
            context,
            state,
            erp.loadLibrary(),
            () => MainLayout(
              child: erp.KioskModePage(embedded: true),
            ),
          ),
        ),
        GoRoute(
          path: '/hr/medical-leaves',
          pageBuilder: (context, state) => _buildDeferredPageWithNoTransition(
            context,
            state,
            erp.loadLibrary(),
            () => erp.MedicalLeavesPage(),
          ),
        ),
        GoRoute(
          path: '/hr/contracts',
          pageBuilder: (context, state) => _buildPageWithNoTransition(
            context,
            state,
            const MainLayout(
              title: 'Contratos',
              child: Center(child: Text('Próximamente')),
            ),
          ),
        ),
        GoRoute(
          path: '/hr/payroll',
          pageBuilder: (context, state) => _buildPageWithNoTransition(
            context,
            state,
            const MainLayout(
              title: 'Liquidaciones',
              child: Center(child: Text('Próximamente')),
            ),
          ),
        ),

        // Debug Module (Bug Tracking)
        GoRoute(
          path: '/debug',
          pageBuilder: (context, state) => _buildDeferredPageWithNoTransition(
            context,
            state,
            erp.loadLibrary(),
            () => erp.BugListPage(),
          ),
        ),

        // Website Module
        GoRoute(
          path: '/website',
          pageBuilder: (context, state) => _buildDeferredPageWithNoTransition(
            context,
            state,
            erp.loadLibrary(),
            () => erp.WebsiteManagementPage(),
          ),
          routes: [
            // Page Management (Dec 2025)
            GoRoute(
              path: 'pages',
              pageBuilder: (context, state) =>
                  _buildDeferredPageWithNoTransition(
                context,
                state,
                erp.loadLibrary(),
                () => erp.PageManagementPage(),
              ),
            ),
            // Navigation Management (Dec 2025)
            GoRoute(
              path: 'navigation',
              pageBuilder: (context, state) =>
                  _buildDeferredPageWithNoTransition(
                context,
                state,
                erp.loadLibrary(),
                () => erp.NavigationManagementPage(),
              ),
            ),
            // Canonical CTA/navigation integrity view
            GoRoute(
              path: 'destinations',
              pageBuilder: (context, state) =>
                  _buildDeferredPageWithNoTransition(
                context,
                state,
                erp.loadLibrary(),
                () => erp.WebsiteDestinationManagementPage(),
              ),
            ),
            // Integrations (Dec 2025)
            GoRoute(
              path: 'integrations',
              pageBuilder: (context, state) =>
                  _buildDeferredPageWithNoTransition(
                context,
                state,
                erp.loadLibrary(),
                () => erp.IntegrationsPage(),
              ),
            ),
            // SEO Settings (Dec 2025)
            GoRoute(
              path: 'seo',
              pageBuilder: (context, state) =>
                  _buildDeferredPageWithNoTransition(
                context,
                state,
                erp.loadLibrary(),
                () => erp.SeoSettingsPage(),
              ),
            ),
            // Featured Products
            GoRoute(
              path: 'featured',
              pageBuilder: (context, state) =>
                  _buildDeferredPageWithNoTransition(
                context,
                state,
                erp.loadLibrary(),
                () => erp.FeaturedProductsPage(),
              ),
            ),
            // Product website visibility
            GoRoute(
              path: 'product-visibility',
              pageBuilder: (context, state) =>
                  _buildDeferredPageWithNoTransition(
                context,
                state,
                erp.loadLibrary(),
                () => erp.ProductWebsiteVisibilityPage(
                  section: state.uri.queryParameters['section'] == 'categories'
                      ? erp.WebsiteCatalogSection.categories
                      : erp.WebsiteCatalogSection.products,
                ),
              ),
            ),
            // Legacy content records are not consumed by the storefront.
            // Keep old bookmarks working, but land on the canonical view.
            GoRoute(
              path: 'content',
              redirect: (context, state) => '/website/destinations',
            ),
            // Online Orders
            GoRoute(
              path: 'orders',
              pageBuilder: (context, state) {
                final initialOrderId = state.uri.queryParameters['order'];
                return _buildDeferredPageWithNoTransition(
                  context,
                  state,
                  erp.loadLibrary(),
                  () => erp.OnlineOrdersPage(
                    initialOrderId: initialOrderId,
                    initialOpenRequestId:
                        state.uri.queryParameters['openRequest'],
                  ),
                );
              },
            ),
            // Website Settings
            GoRoute(
              path: 'settings',
              pageBuilder: (context, state) =>
                  _buildDeferredPageWithNoTransition(
                context,
                state,
                erp.loadLibrary(),
                () => erp.WebsiteSettingsPage(),
              ),
            ),
          ],
        ),

        // Mail Module (Zoho Mail Integration)
        GoRoute(
          path: '/mail',
          pageBuilder: (context, state) => CustomTransitionPage<void>(
            key: state.pageKey,
            child: mail.MailInboxPage(
              initialProviderId: state.uri.queryParameters['providerId'],
              initialMessageId: state.uri.queryParameters['messageId'],
              initialOpenRequestId: state.uri.queryParameters['openRequest'],
            ),
            transitionsBuilder:
                (context, animation, secondaryAnimation, child) => child,
          ),
        ),

        // Internal File Storage
        GoRoute(
          path: '/storage',
          pageBuilder: (context, state) => CustomTransitionPage<void>(
            key: state.pageKey,
            child: storage.StoragePage(
              initialFileId: state.uri.queryParameters['file'],
              initialOpenRequestId: state.uri.queryParameters['openRequest'],
            ),
            transitionsBuilder:
                (context, animation, secondaryAnimation, child) => child,
          ),
        ),

        // ========================================
        // TOOLS MODULE (WebView Embedded Websites)
        // ========================================

        // WhatsApp Web
        GoRoute(
          path: '/tools/whatsapp-web',
          pageBuilder: (context, state) => _buildDeferredPageWithNoTransition(
            context,
            state,
            erp.loadLibrary(),
            () => erp.WhatsAppWebModulePage(),
          ),
        ),

        // ── Native Spreadsheets ──
        GoRoute(
          path: '/tools/spreadsheets',
          pageBuilder: (context, state) => _buildDeferredPageWithNoTransition(
            context,
            state,
            erp.loadLibrary(),
            () => erp.SpreadsheetDashboardPage(),
          ),
        ),
        GoRoute(
          path: '/tools/spreadsheets/:id',
          onExit: (context, state) async {
            await erp.loadLibrary();
            return erp.SpreadsheetEditorExitGuard.canExit(
              state.pathParameters['id'] ?? '',
            );
          },
          pageBuilder: (context, state) {
            final id = state.pathParameters['id'] ?? '';
            return _buildDeferredPageWithNoTransition(
              context,
              state,
              erp.loadLibrary(),
              () => erp.SpreadsheetEditorPage(spreadsheetId: id),
            );
          },
        ),

        // Google Sheets
        GoRoute(
          path: '/tools/sheets',
          pageBuilder: (context, state) {
            final url = state.uri.queryParameters['url'];
            return _buildDeferredPageWithNoTransition(
              context,
              state,
              erp.loadLibrary(),
              () => erp.GoogleSheetsModulePage(sheetUrl: url),
            );
          },
        ),

        // Notion Workspace
        GoRoute(
          path: '/tools/notion',
          pageBuilder: (context, state) {
            final url = state.uri.queryParameters['url'];
            return _buildDeferredPageWithNoTransition(
              context,
              state,
              erp.loadLibrary(),
              () => erp.NotionModulePage(workspaceUrl: url),
            );
          },
        ),

        // Analytics Dashboard
        GoRoute(
          path: '/tools/analytics',
          pageBuilder: (context, state) {
            final url = state.uri.queryParameters['url'] ??
                'https://analytics.google.com';
            return _buildDeferredPageWithNoTransition(
              context,
              state,
              erp.loadLibrary(),
              () => erp.AnalyticsDashboardPage(dashboardUrl: url),
            );
          },
        ),

        // Generic Web Tool
        GoRoute(
          path: '/tools/web',
          pageBuilder: (context, state) {
            final url =
                state.uri.queryParameters['url'] ?? 'https://www.google.com';
            final name = state.uri.queryParameters['name'] ?? 'Navegador web';
            return _buildDeferredPageWithNoTransition(
              context,
              state,
              erp.loadLibrary(),
              () => erp.GenericWebToolPage(url: url, name: name),
            );
          },
        ),
      ],
    );

    return router;
  }

  // Helper for deferred routes (Code Splitting)
  // Shows MainLayout with loading indicator while the library chunk loads
  // This preserves the sidebar during navigation
  static Page<void> _buildDeferredPageWithNoTransition(
    BuildContext context,
    GoRouterState state,
    Future<dynamic> libraryFuture,
    Widget Function() widgetBuilder, {
    LocalKey? pageKeyOverride,
  }) {
    return CustomTransitionPage<void>(
      key: pageKeyOverride ?? state.pageKey,
      child: FutureBuilder(
        future: libraryFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.done) {
            return widgetBuilder();
          }
          // Use MainLayout as skeleton to preserve sidebar during load
          return const MainLayout(
            title: '...',
            body: Center(
              child: SizedBox(
                width: 40,
                height: 40,
                child: CircularProgressIndicator(),
              ),
            ),
          );
        },
      ),
      transitionsBuilder: (context, animation, secondaryAnimation, child) =>
          child,
    );
  }
}
