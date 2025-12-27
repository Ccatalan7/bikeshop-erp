import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';

import '../widgets/main_layout.dart';
import '../screens/dashboard_screen.dart';
import '../screens/login_screen.dart';
import '../screens/reset_password_screen.dart';
import '../../modules/auth/pages/accept_invitation_page.dart';
import '../services/auth_service.dart';
import '../../modules/accounting/pages/account_list_page.dart';
import '../../modules/accounting/pages/account_form_page.dart';
import '../../modules/accounting/pages/journal_entry_list_page.dart';
import '../../modules/accounting/pages/journal_entry_form_page.dart';
import '../../modules/accounting/pages/financial_reports_hub_page.dart';
import '../../modules/accounting/pages/income_statement_page.dart';
import '../../modules/accounting/pages/balance_sheet_page.dart';
import '../../modules/accounting/pages/expense_list_page.dart';
import '../../modules/accounting/pages/expense_detail_page.dart';
import '../../modules/accounting/pages/expense_form_page.dart';
import '../../modules/tax_reports/pages/f29_dashboard_page.dart';
import '../../modules/crm/pages/customer_list_page.dart';
import '../../modules/crm/pages/customer_form_page.dart';
import '../../modules/crm/pages/customer_bike_directory_page.dart';
import '../../modules/bikeshop/pages/client_logbook_page.dart';
import '../../modules/bikeshop/pages/pegas_table_page.dart';
import '../../modules/bikeshop/pages/job_statuses_page.dart';
import '../../modules/bikeshop/pages/mechanic_job_form_page.dart';
import '../../modules/bikeshop/pages/workshop_calendar_page.dart';
import '../../modules/bikeshop/pages/bike_brands_page.dart';
import '../../modules/bikeshop/pages/wheel_hubs_page.dart';
import '../../modules/bikeshop/pages/wheel_rims_page.dart';
import '../../modules/bikeshop/pages/wheel_spokes_page.dart';
import '../../modules/bikeshop/pages/wheel_builder_wizard_page.dart';
import '../../modules/bikeshop/pages/spoke_length_calculator_page.dart';
import '../../modules/bikeshop/pages/bike_encyclopedia_page.dart';
import '../../modules/inventory/pages/product_list_page.dart';
import '../../modules/inventory/pages/product_form_page.dart';
import '../../modules/inventory/pages/product_import_page.dart';
import '../../modules/inventory/pages/hierarchical_category_page.dart';
import '../../modules/inventory/pages/category_form_page.dart';
import '../../modules/inventory/pages/brand_list_page.dart';
import '../../modules/inventory/pages/brand_form_page.dart';
import '../../modules/inventory/pages/stock_movement_list_page.dart';
import '../../modules/inventory/pages/stock_movements_page.dart';
import '../../modules/sales/pages/invoice_list_page.dart';
import '../../modules/sales/pages/invoice_form_page.dart';
import '../../modules/sales/pages/invoice_payment_page.dart';
import '../../modules/sales/pages/payment_form_page.dart';
import '../../modules/sales/pages/sales_reports_page.dart';
import '../../modules/sales/pages/reports/sales_by_product_page.dart';
import '../../modules/sales/pages/reports/sales_by_product_detail_page.dart';
import '../../modules/sales/pages/reports/sales_by_customer_page.dart';
import '../../modules/purchases/pages/supplier_list_page.dart';
import '../../modules/purchases/pages/supplier_form_page.dart';
import '../../modules/purchases/pages/purchase_invoice_list_page.dart';
import '../../modules/purchases/pages/purchase_invoice_form_page.dart';
import '../../modules/purchases/pages/purchase_payment_form_page.dart';
import '../../modules/purchases/pages/purchase_payments_list_page.dart';
import '../../modules/purchases/pages/smart_purchase_list_page.dart';
import '../../modules/pos/pages/pos_dashboard_page.dart';
import '../../modules/pos/pages/pos_cart_page.dart';
import '../../modules/pos/pages/pos_payment_page.dart';
import '../../modules/pos/pages/pos_receipt_page.dart';
import '../../modules/pos/models/pos_transaction.dart';
import '../../modules/settings/pages/settings_page.dart';
import '../../modules/settings/pages/factory_reset_page_new.dart';
import '../../modules/settings/pages/backup_management_page.dart';
import '../../modules/settings/pages/appearance_settings_page.dart';
import '../../modules/settings/pages/user_management_page.dart';
import '../../modules/settings/pages/payment_methods_settings_page.dart';
import '../../modules/settings/pages/bluetooth_scanner_page.dart';
import '../../modules/settings/pages/keyboard_scanner_page.dart';
import '../../modules/settings/pages/remote_scanner_page.dart';
import '../../modules/settings/pages/notification_settings_page.dart';
import '../../modules/hr/pages/employee_list_page.dart';
import '../../modules/hr/pages/attendances_page.dart';
import '../../modules/hr/pages/kiosk_mode_page.dart';
import '../../modules/hr/pages/medical_leaves_page.dart';
import '../../modules/website/pages/website_management_page.dart';
import '../../modules/website/pages/page_management_page.dart';
import '../../modules/website/pages/navigation_management_page.dart';
import '../../modules/website/pages/integrations_page.dart';
import '../../modules/website/pages/featured_products_page.dart';
import '../../modules/website/pages/content_management_page.dart';
import '../../modules/website/pages/online_orders_page.dart';
import '../../modules/website/pages/website_settings_page.dart';
import '../../modules/website/pages/seo_settings_page.dart';
import '../widgets/workspace_demo_page.dart';

// WebView Modules (embedded websites)
import '../../modules/webview_modules/webview_modules.dart';

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
import '../../modules/messaging/pages/employee_chat_page.dart';
import '../../public_store/widgets/public_store_layout.dart';

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
    return PublicStoreLayout(
      enablePageViewScrolling: enablePageViewScrolling,
      child: child,
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
  @override
  Widget build(BuildContext context) {
    final disablePageViewScrolling =
        widget.currentPath.startsWith('/tienda/cuenta/mensajes/') ||
            widget.currentPath.startsWith('/tienda/cuenta/chats/');

    return PublicStoreLayout(
      enablePageViewScrolling: !disablePageViewScrolling,
      child: widget.navigationShell,
    );
  }
}

class AppRouter {
  static GoRouter createRouter(
    AuthService authService, {
    String? initialLocationOverride,
    bool forcePublicStoreHost = false,
  }) {
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
        debugPrint(
            '🧭 [Router] redirect called - path: ${state.uri.path}, matchedLocation: ${state.matchedLocation}');
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
        final inferredOrderId = (externalReference?.isNotEmpty ?? false)
            ? externalReference
            : (orderIdFromQuery?.isNotEmpty ?? false)
                ? orderIdFromQuery
                : null;

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
            '/productos',
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

            if (p == '/productos') legacyPath = '/tienda/productos';
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
        final resettingPassword = state.matchedLocation == '/reset-password';
        final acceptingInvitation =
            state.matchedLocation == '/accept-invitation';

        // Allow access to password reset and invitation acceptance without authentication
        if (resettingPassword || acceptingInvitation) {
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

        // Product Detail (clean URL)
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

        // Product Detail
        GoRoute(
          path: '/tienda/producto/:id',
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
          path: '/login',
          pageBuilder: (context, state) => _buildPageWithNoTransition(
            context,
            state,
            const LoginScreen(),
          ),
        ),

        // Password Reset
        GoRoute(
          path: '/reset-password',
          pageBuilder: (context, state) => _buildPageWithNoTransition(
            context,
            state,
            const ResetPasswordScreen(),
          ),
        ),

        // Accept Invitation
        GoRoute(
          path: '/accept-invitation',
          pageBuilder: (context, state) {
            final token = state.uri.queryParameters['token'] ?? '';
            return _buildPageWithNoTransition(
              context,
              state,
              AcceptInvitationPage(token: token),
            );
          },
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

        // Workspace Demo (for testing workspace tab system)
        GoRoute(
          path: '/workspace-demo',
          pageBuilder: (context, state) => _buildPageWithNoTransition(
            context,
            state,
            const WorkspaceDemoPage(),
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
          path: '/accounting/expenses',
          pageBuilder: (context, state) => _buildPageWithNoTransition(
            context,
            state,
            const ExpenseListPage(),
          ),
        ),
        GoRoute(
          path: '/accounting/expenses/new',
          pageBuilder: (context, state) => _buildPageWithNoTransition(
            context,
            state,
            const ExpenseFormPage(),
          ),
        ),
        GoRoute(
          path: '/accounting/expenses/:id',
          pageBuilder: (context, state) {
            final id = state.pathParameters['id']!;
            return _buildPageWithNoTransition(
              context,
              state,
              ExpenseDetailPage(expenseId: id),
            );
          },
        ),
        GoRoute(
          path: '/accounting/expenses/:id/edit',
          pageBuilder: (context, state) {
            final id = state.pathParameters['id']!;
            return _buildPageWithNoTransition(
              context,
              state,
              ExpenseFormPage(expenseId: id),
            );
          },
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

        // Tax Reports (F29)
        GoRoute(
          path: '/tax-reports/f29',
          pageBuilder: (context, state) => _buildPageWithNoTransition(
            context,
            state,
            const F29DashboardPage(),
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
          path: '/taller/estados',
          pageBuilder: (context, state) => _buildPageWithNoTransition(
            context,
            state,
            const JobStatusesPage(),
          ),
        ),
        GoRoute(
          path: '/taller/pegas/nueva',
          pageBuilder: (context, state) {
            return _buildPageWithNoTransition(
              context,
              state,
              const MechanicJobFormPage(),
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
        GoRoute(
          path: '/taller/bicicletas',
          pageBuilder: (context, state) => _buildPageWithNoTransition(
            context,
            state,
            const CustomerBikeDirectoryPage(),
          ),
        ),
        GoRoute(
          path: '/taller/calendario',
          pageBuilder: (context, state) => _buildPageWithNoTransition(
            context,
            state,
            const WorkshopCalendarPage(),
          ),
        ),
        GoRoute(
          path: '/taller/marcas-modelos',
          pageBuilder: (context, state) => _buildPageWithNoTransition(
            context,
            state,
            const BikeBrandsPage(),
          ),
        ),

        // Bike Encyclopedia
        GoRoute(
          path: '/taller/bike-encyclopedia',
          pageBuilder: (context, state) => _buildPageWithNoTransition(
            context,
            state,
            const BikeEncyclopediaPage(),
          ),
        ),

        // Wheel Building System
        GoRoute(
          path: '/taller/wheel-builder',
          pageBuilder: (context, state) => _buildPageWithNoTransition(
            context,
            state,
            const WheelBuilderWizardPage(),
          ),
        ),
        GoRoute(
          path: '/taller/spoke-calculator',
          pageBuilder: (context, state) => _buildPageWithNoTransition(
            context,
            state,
            const SpokeLengthCalculatorPage(),
          ),
        ),
        GoRoute(
          path: '/taller/wheel-hubs',
          pageBuilder: (context, state) => _buildPageWithNoTransition(
            context,
            state,
            const WheelHubsPage(),
          ),
        ),
        GoRoute(
          path: '/taller/wheel-rims',
          pageBuilder: (context, state) => _buildPageWithNoTransition(
            context,
            state,
            const WheelRimsPage(),
          ),
        ),
        GoRoute(
          path: '/taller/wheel-spokes',
          pageBuilder: (context, state) => _buildPageWithNoTransition(
            context,
            state,
            const WheelSpokesPage(),
          ),
        ),

        // Inventory Module
        GoRoute(
          path: '/inventory/products',
          pageBuilder: (context, state) {
            final categoryId = state.uri.queryParameters['category'];
            final supplierId = state.uri.queryParameters['supplier'];
            final refreshToken = state.uri.queryParameters['refresh'];
            return _buildPageWithNoTransition(
              context,
              state,
              ProductListPage(
                initialCategoryId: categoryId,
                initialSupplierId: supplierId,
                refreshToken: refreshToken,
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
          path: '/inventory/products/import',
          pageBuilder: (context, state) => _buildPageWithNoTransition(
            context,
            state,
            const ProductImportPage(),
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
            const HierarchicalCategoryPage(),
          ),
        ),
        GoRoute(
          path: '/inventory/categories/new',
          pageBuilder: (context, state) {
            final parentId = state.uri.queryParameters['parent'];
            return _buildPageWithNoTransition(
              context,
              state,
              CategoryFormPage(parentCategoryId: parentId),
            );
          },
        ),
        GoRoute(
          path: '/inventory/categories/:id',
          pageBuilder: (context, state) {
            final id = state.pathParameters['id']!;
            // Check if this is an edit route by looking at the full path
            if (state.uri.path.endsWith('/edit')) {
              return _buildPageWithNoTransition(
                context,
                state,
                CategoryFormPage(categoryId: id),
              );
            }
            // Otherwise it's a category view
            return _buildPageWithNoTransition(
              context,
              state,
              HierarchicalCategoryPage(categoryId: id),
            );
          },
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
          path: '/inventory/brands',
          pageBuilder: (context, state) => _buildPageWithNoTransition(
            context,
            state,
            const BrandListPage(),
          ),
        ),
        GoRoute(
          path: '/inventory/movements',
          pageBuilder: (context, state) => _buildPageWithNoTransition(
            context,
            state,
            const StockMovementsPage(),
          ),
        ),
        GoRoute(
          path: '/inventory/brands/new',
          pageBuilder: (context, state) => _buildPageWithNoTransition(
            context,
            state,
            const BrandFormPage(),
          ),
        ),
        GoRoute(
          path: '/inventory/brands/:id/edit',
          pageBuilder: (context, state) {
            final id = state.pathParameters['id']!;
            return _buildPageWithNoTransition(
              context,
              state,
              BrandFormPage(brandId: id),
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
            final referrer = state.uri.queryParameters['referrer'];
            final jobId = state.uri.queryParameters['jobId'];
            return _buildPageWithNoTransition(
              context,
              state,
              InvoiceFormPage(
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
            final referrer = state.uri.queryParameters['referrer'];
            final jobId = state.uri.queryParameters['jobId'];
            return _buildPageWithNoTransition(
              context,
              state,
              InvoiceFormPage(
                invoiceId: id,
                referrer: referrer,
                referrerJobId: jobId,
              ),
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

        // Sales Reports
        GoRoute(
          path: '/sales/reports',
          pageBuilder: (context, state) => _buildPageWithNoTransition(
            context,
            state,
            const SalesReportsPage(),
          ),
        ),
        GoRoute(
          path: '/sales/reports/by-product',
          pageBuilder: (context, state) => _buildPageWithNoTransition(
            context,
            state,
            const SalesByProductPage(),
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

            return _buildPageWithNoTransition(
              context,
              state,
              SalesByProductDetailPage(
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
          pageBuilder: (context, state) => _buildPageWithNoTransition(
            context,
            state,
            const SalesByCustomerPage(),
          ),
        ),

        // Messaging Module
        GoRoute(
          path: '/chat',
          pageBuilder: (context, state) => _buildPageWithNoTransition(
            context,
            state,
            const MainLayout(child: EmployeeChatPage()),
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
        // Specific routes MUST come before dynamic :id route
        GoRoute(
          path: '/purchases/new',
          pageBuilder: (context, state) {
            final prepaymentParam = state.uri.queryParameters['prepayment'];
            final isPrepayment = prepaymentParam == 'true';
            debugPrint(
                '🔍 DEBUG: prepayment param = "$prepaymentParam", isPrepayment = $isPrepayment');
            return _buildPageWithNoTransition(
              context,
              state,
              PurchaseInvoiceFormPage(isPrepayment: isPrepayment),
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
        GoRoute(
          path: '/purchases/smart-list',
          pageBuilder: (context, state) => _buildPageWithNoTransition(
            context,
            state,
            const SmartPurchaseListPage(),
          ),
        ),
        // Dynamic route for viewing/editing invoices
        GoRoute(
          path: '/purchases/:id',
          pageBuilder: (context, state) {
            final id = state.pathParameters['id']!;
            // Single page for create, edit, and workflow (like sales invoice)
            return _buildPageWithNoTransition(
              context,
              state,
              PurchaseInvoiceFormPage(invoiceId: id),
            );
          },
        ),
        GoRoute(
          path: '/purchases/:id/detail',
          pageBuilder: (context, state) {
            final id = state.pathParameters['id']!;
            // DEPRECATED: Detail page is no longer used, redirects to form page
            return _buildPageWithNoTransition(
              context,
              state,
              PurchaseInvoiceFormPage(invoiceId: id),
            );
          },
        ),
        GoRoute(
          path: '/purchases/:id/edit',
          pageBuilder: (context, state) {
            final id = state.pathParameters['id']!;
            // DEPRECATED: Edit route is no longer used, redirects to form page
            return _buildPageWithNoTransition(
              context,
              state,
              PurchaseInvoiceFormPage(invoiceId: id),
            );
          },
        ),
        GoRoute(
          path: '/purchases/invoices/:id/payment',
          pageBuilder: (context, state) {
            final id = state.pathParameters['id']!;
            return _buildPageWithNoTransition(
              context,
              state,
              PurchasePaymentFormPage(invoiceId: id),
            );
          },
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
              child: FactoryResetPageNew(),
            ),
          ),
        ),
        GoRoute(
          path: '/settings/backup',
          pageBuilder: (context, state) => _buildPageWithNoTransition(
            context,
            state,
            const BackupManagementPage(),
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
        GoRoute(
          path: '/settings/users',
          pageBuilder: (context, state) => _buildPageWithNoTransition(
            context,
            state,
            const MainLayout(
              child: UserManagementPage(),
            ),
          ),
        ),
        GoRoute(
          path: '/settings/payment-methods',
          pageBuilder: (context, state) => _buildPageWithNoTransition(
            context,
            state,
            const MainLayout(
              child: PaymentMethodsSettingsPage(),
            ),
          ),
        ),
        GoRoute(
          path: '/settings/bluetooth-scanner',
          pageBuilder: (context, state) => _buildPageWithNoTransition(
            context,
            state,
            const BluetoothScannerPage(),
          ),
        ),
        GoRoute(
          path: '/settings/keyboard-scanner',
          pageBuilder: (context, state) => _buildPageWithNoTransition(
            context,
            state,
            const KeyboardScannerPage(),
          ),
        ),
        GoRoute(
          path: '/settings/remote-scanner',
          pageBuilder: (context, state) => _buildPageWithNoTransition(
            context,
            state,
            const RemoteScannerPage(),
          ),
        ),
        GoRoute(
          path: '/settings/notifications',
          pageBuilder: (context, state) => _buildPageWithNoTransition(
            context,
            state,
            const NotificationSettingsPage(),
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
        GoRoute(
          path: '/hr/medical-leaves',
          pageBuilder: (context, state) => _buildPageWithNoTransition(
            context,
            state,
            const MedicalLeavesPage(),
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

        // Website Module
        GoRoute(
          path: '/website',
          pageBuilder: (context, state) => _buildPageWithNoTransition(
            context,
            state,
            const WebsiteManagementPage(),
          ),
          routes: [
            // Page Management (Dec 2025)
            GoRoute(
              path: 'pages',
              pageBuilder: (context, state) => _buildPageWithNoTransition(
                context,
                state,
                const PageManagementPage(),
              ),
            ),
            // Navigation Management (Dec 2025)
            GoRoute(
              path: 'navigation',
              pageBuilder: (context, state) => _buildPageWithNoTransition(
                context,
                state,
                const NavigationManagementPage(),
              ),
            ),
            // Integrations (Dec 2025)
            GoRoute(
              path: 'integrations',
              pageBuilder: (context, state) => _buildPageWithNoTransition(
                context,
                state,
                const IntegrationsPage(),
              ),
            ),
            // SEO Settings (Dec 2025)
            GoRoute(
              path: 'seo',
              pageBuilder: (context, state) => _buildPageWithNoTransition(
                context,
                state,
                const SeoSettingsPage(),
              ),
            ),
            // Featured Products
            GoRoute(
              path: 'featured',
              pageBuilder: (context, state) => _buildPageWithNoTransition(
                context,
                state,
                const FeaturedProductsPage(),
              ),
            ),
            // Content Management
            GoRoute(
              path: 'content',
              pageBuilder: (context, state) => _buildPageWithNoTransition(
                context,
                state,
                const ContentManagementPage(),
              ),
            ),
            // Online Orders
            GoRoute(
              path: 'orders',
              pageBuilder: (context, state) => _buildPageWithNoTransition(
                context,
                state,
                const OnlineOrdersPage(),
              ),
            ),
            // Website Settings
            GoRoute(
              path: 'settings',
              pageBuilder: (context, state) => _buildPageWithNoTransition(
                context,
                state,
                const WebsiteSettingsPage(),
              ),
            ),
          ],
        ),

        // ========================================
        // TOOLS MODULE (WebView Embedded Websites)
        // ========================================

        // WhatsApp Web
        GoRoute(
          path: '/tools/whatsapp-web',
          pageBuilder: (context, state) => _buildPageWithNoTransition(
            context,
            state,
            const WhatsAppWebModulePage(),
          ),
        ),

        // Google Sheets
        GoRoute(
          path: '/tools/sheets',
          pageBuilder: (context, state) {
            final url = state.uri.queryParameters['url'];
            return _buildPageWithNoTransition(
              context,
              state,
              GoogleSheetsModulePage(sheetUrl: url),
            );
          },
        ),

        // Notion Workspace
        GoRoute(
          path: '/tools/notion',
          pageBuilder: (context, state) {
            final url = state.uri.queryParameters['url'];
            return _buildPageWithNoTransition(
              context,
              state,
              NotionModulePage(workspaceUrl: url),
            );
          },
        ),

        // Analytics Dashboard
        GoRoute(
          path: '/tools/analytics',
          pageBuilder: (context, state) {
            final url = state.uri.queryParameters['url'] ??
                'https://analytics.google.com';
            return _buildPageWithNoTransition(
              context,
              state,
              AnalyticsDashboardPage(dashboardUrl: url),
            );
          },
        ),

        // Generic Web Tool
        GoRoute(
          path: '/tools/web',
          pageBuilder: (context, state) {
            final url =
                state.uri.queryParameters['url'] ?? 'https://www.google.com';
            final name = state.uri.queryParameters['name'] ?? 'Web Tool';
            return _buildPageWithNoTransition(
              context,
              state,
              GenericWebToolPage(url: url, name: name),
            );
          },
        ),
      ],
    );

    return router;
  }
}
