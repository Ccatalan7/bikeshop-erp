import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../pages/cart_page.dart';
import '../pages/checkout_page.dart';
import '../pages/contact_page.dart';
import '../pages/customer_addresses_page.dart';
import '../pages/customer_auth_page.dart';
import '../pages/customer_bikes_page.dart';
import '../pages/customer_chat_detail_page.dart';
import '../pages/customer_chat_hub_page.dart';
import '../pages/customer_chat_list_page.dart';
import '../pages/customer_dashboard_page.dart';
import '../pages/customer_orders_page.dart';
import '../pages/customer_profile_page.dart';
import '../pages/customer_service_history_page.dart';
import '../pages/dynamic_website_page.dart';
import '../pages/order_confirmation_page.dart';
import '../pages/product_catalog_page.dart';
import '../pages/product_detail_page.dart';
import '../pages/public_home_page.dart';
import '../pages/static_policy_page.dart';
import '../widgets/public_store_layout.dart';

// ============================================================================
// SHELL NAVIGATOR - Keeps pages alive in IndexedStack
// ============================================================================

/// Navigator key for tracking shell state
final GlobalKey<NavigatorState> _rootNavigatorKey = GlobalKey<NavigatorState>();

// Branch navigator keys - keep each branch navigator stable/alive.
final GlobalKey<NavigatorState> _homeBranchNavigatorKey =
  GlobalKey<NavigatorState>(debugLabel: 'publicStoreHomeBranch');
final GlobalKey<NavigatorState> _productsBranchNavigatorKey =
  GlobalKey<NavigatorState>(debugLabel: 'publicStoreProductsBranch');
final GlobalKey<NavigatorState> _contactBranchNavigatorKey =
  GlobalKey<NavigatorState>(debugLabel: 'publicStoreContactBranch');
final GlobalKey<NavigatorState> _cartBranchNavigatorKey =
  GlobalKey<NavigatorState>(debugLabel: 'publicStoreCartBranch');
final GlobalKey<NavigatorState> _accountBranchNavigatorKey =
  GlobalKey<NavigatorState>(debugLabel: 'publicStoreAccountBranch');

/// Shell pages enum for IndexedStack navigation
enum ShellPage { home, products, contact, cart, account }

/// Custom shell that wraps pages in PublicStoreLayout and keeps them alive
class _PublicStoreShell extends StatefulWidget {
  final StatefulNavigationShell navigationShell;

  const _PublicStoreShell({required this.navigationShell});

  @override
  State<_PublicStoreShell> createState() => _PublicStoreShellState();
}

class _PublicStoreShellState extends State<_PublicStoreShell> {
  @override
  Widget build(BuildContext context) {
    debugPrint(
        '🐚 [PublicStoreShell] build() - currentIndex: ${widget.navigationShell.currentIndex}');

    return PublicStoreLayout(
      enablePageViewScrolling: true,
      useExternalEditorPanel: true,
      // The shell's child contains the IndexedStack with all branch pages
      child: widget.navigationShell,
    );
  }
}

// ============================================================================
// HELPER WRAPPER - For non-shell pages that need the layout
// ============================================================================

/// Helper wrapper for public store pages that are NOT in the shell
class PublicStoreWrapper extends StatelessWidget {
  final Widget child;
  final bool enablePageViewScrolling;
  final bool useExternalEditorPanel;

  const PublicStoreWrapper({
    super.key,
    required this.child,
    this.enablePageViewScrolling = true,
    this.useExternalEditorPanel = true,
  });

  @override
  Widget build(BuildContext context) {
    return PublicStoreLayout(
      enablePageViewScrolling: enablePageViewScrolling,
      useExternalEditorPanel: useExternalEditorPanel,
      child: child,
    );
  }
}

// ============================================================================
// PAGE BUILDER HELPERS
// ============================================================================

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

/// Shell pages must stay alive across navigation and query param changes
/// (e.g. `?edit=true`, `?preview=true`).
///
/// Using `state.pageKey` for these pages causes go_router to dispose/recreate
/// the page whenever the location changes (including query parameters).
Page<dynamic> _buildShellPage(
  String key,
  Widget child,
) {
  return NoTransitionPage<void>(
    key: ValueKey<String>(key),
    child: child,
  );
}

// ============================================================================
// ROUTER CONFIGURATION
// ============================================================================

class PublicStoreRouter {
  static GoRouter createRouter() {
    return GoRouter(
      navigatorKey: _rootNavigatorKey,
      debugLogDiagnostics: false,
      initialLocation: null,
      routes: [
        // ====================================================================
        // CANONICALIZATION REDIRECTS
        //
        // IMPORTANT: We keep exactly ONE route per shell page inside the
        // StatefulShellRoute branches.
        //
        // If we register both '/productos' and '/tienda/productos' as separate
        // GoRoutes that build the same widget, go_router will generate different
        // pageKeys per match and will dispose/recreate the page on navigation.
        // These redirects ensure legacy '/tienda/*' URLs map to the canonical
        // clean URLs, keeping shell pages alive in the IndexedStack.
        // ====================================================================
        GoRoute(
          path: '/tienda',
          redirect: (context, state) {
            final uri = Uri(path: '/', queryParameters: state.uri.queryParameters);
            return uri.toString();
          },
        ),
        GoRoute(
          path: '/tienda/productos',
          redirect: (context, state) {
            final uri = Uri(
              path: '/productos',
              queryParameters: state.uri.queryParameters,
            );
            return uri.toString();
          },
        ),
        GoRoute(
          path: '/tienda/contacto',
          redirect: (context, state) {
            final uri = Uri(
              path: '/contacto',
              queryParameters: state.uri.queryParameters,
            );
            return uri.toString();
          },
        ),
        GoRoute(
          path: '/tienda/carrito',
          redirect: (context, state) {
            final uri = Uri(
              path: '/carrito',
              queryParameters: state.uri.queryParameters,
            );
            return uri.toString();
          },
        ),
        GoRoute(
          path: '/tienda/cuenta',
          redirect: (context, state) {
            final uri = Uri(
              path: '/cuenta',
              queryParameters: state.uri.queryParameters,
            );
            return uri.toString();
          },
        ),

        // ====================================================================
        // STATEFUL SHELL - Main pages kept alive in IndexedStack
        // ====================================================================
        StatefulShellRoute.indexedStack(
          builder: (context, state, navigationShell) {
            return _PublicStoreShell(navigationShell: navigationShell);
          },
          branches: [
            // Branch 0: HOME (/)
            StatefulShellBranch(
              navigatorKey: _homeBranchNavigatorKey,
              routes: [
                GoRoute(
                  path: '/',
                  pageBuilder: (context, state) => _buildShellPage(
                    'public_store_shell_home',
                    const PublicHomePage(),
                  ),
                ),

                // Policy/info pages kept within the shell so navigating to them
                // doesn't dispose the IndexedStack pages.
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

            // Branch 1: PRODUCTS (/productos)
            StatefulShellBranch(
              navigatorKey: _productsBranchNavigatorKey,
              routes: [
                GoRoute(
                  path: '/productos',
                  pageBuilder: (context, state) => _buildShellPage(
                    'public_store_shell_products',
                    const ProductCatalogPage(),
                  ),
                ),
              ],
            ),

            // Branch 2: CONTACT (/contacto)
            StatefulShellBranch(
              navigatorKey: _contactBranchNavigatorKey,
              routes: [
                GoRoute(
                  path: '/contacto',
                  pageBuilder: (context, state) => _buildShellPage(
                    'public_store_shell_contact',
                    const ContactPage(),
                  ),
                ),
              ],
            ),

            // Branch 3: CART (/carrito)
            StatefulShellBranch(
              navigatorKey: _cartBranchNavigatorKey,
              routes: [
                GoRoute(
                  path: '/carrito',
                  pageBuilder: (context, state) => _buildShellPage(
                    'public_store_shell_cart',
                    const CartPage(),
                  ),
                ),
              ],
            ),

            // Branch 4: ACCOUNT (/cuenta)
            StatefulShellBranch(
              navigatorKey: _accountBranchNavigatorKey,
              routes: [
                GoRoute(
                  path: '/cuenta',
                  pageBuilder: (context, state) => _buildShellPage(
                    'public_store_shell_account',
                    const CustomerDashboardPage(),
                  ),
                ),
              ],
            ),
          ],
        ),

        // ====================================================================
        // DETAIL PAGES - Outside shell (push on top)
        // ====================================================================

        // Product detail
        GoRoute(
          path: '/producto/:id',
          parentNavigatorKey: _rootNavigatorKey,
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
          path: '/checkout',
          parentNavigatorKey: _rootNavigatorKey,
          pageBuilder: (context, state) => _buildPageWithNoTransition(
            context,
            state,
            const PublicStoreWrapper(child: CheckoutPage()),
          ),
        ),

        // Order confirmation
        GoRoute(
          path: '/pedido/:id',
          parentNavigatorKey: _rootNavigatorKey,
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

        // ====================================================================
        // CUSTOMER ACCOUNT SUB-PAGES - Outside shell
        // ====================================================================
        GoRoute(
          path: '/cuenta/login',
          parentNavigatorKey: _rootNavigatorKey,
          pageBuilder: (context, state) => _buildPageWithNoTransition(
            context,
            state,
            const PublicStoreWrapper(child: CustomerAuthPage()),
          ),
        ),
        GoRoute(
          path: '/cuenta/perfil',
          parentNavigatorKey: _rootNavigatorKey,
          pageBuilder: (context, state) => _buildPageWithNoTransition(
            context,
            state,
            const PublicStoreWrapper(child: CustomerProfilePage()),
          ),
        ),
        GoRoute(
          path: '/cuenta/direcciones',
          parentNavigatorKey: _rootNavigatorKey,
          pageBuilder: (context, state) => _buildPageWithNoTransition(
            context,
            state,
            const PublicStoreWrapper(child: CustomerAddressesPage()),
          ),
        ),
        GoRoute(
          path: '/cuenta/pedidos',
          parentNavigatorKey: _rootNavigatorKey,
          pageBuilder: (context, state) => _buildPageWithNoTransition(
            context,
            state,
            const PublicStoreWrapper(child: CustomerOrdersPage()),
          ),
        ),
        GoRoute(
          path: '/cuenta/bicicletas',
          parentNavigatorKey: _rootNavigatorKey,
          pageBuilder: (context, state) => _buildPageWithNoTransition(
            context,
            state,
            const PublicStoreWrapper(child: CustomerBikesPage()),
          ),
        ),
        GoRoute(
          path: '/cuenta/servicios',
          parentNavigatorKey: _rootNavigatorKey,
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
          parentNavigatorKey: _rootNavigatorKey,
          pageBuilder: (context, state) => _buildPageWithNoTransition(
            context,
            state,
            const PublicStoreWrapper(child: CustomerChatListPage()),
          ),
        ),
        GoRoute(
          path: '/cuenta/mensajes/:id',
          parentNavigatorKey: _rootNavigatorKey,
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
        GoRoute(
          path: '/cuenta/chats',
          parentNavigatorKey: _rootNavigatorKey,
          pageBuilder: (context, state) => _buildPageWithNoTransition(
            context,
            state,
            const PublicStoreWrapper(child: CustomerChatHubPage()),
          ),
        ),
        GoRoute(
          path: '/cuenta/chats/:id',
          parentNavigatorKey: _rootNavigatorKey,
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

        // ====================================================================
        // DYNAMIC PAGES
        // ====================================================================
        GoRoute(
          path: '/pagina/:slug',
          parentNavigatorKey: _rootNavigatorKey,
          pageBuilder: (context, state) {
            final slug = state.pathParameters['slug'] ?? 'home';
            return _buildPageWithNoTransition(
              context,
              state,
              PublicStoreWrapper(child: DynamicWebsitePage(slug: slug)),
            );
          },
        ),

        // Legacy Google Merchant URLs
        GoRoute(
          path: '/shop/:slug',
          parentNavigatorKey: _rootNavigatorKey,
          pageBuilder: (context, state) {
            final slug = state.pathParameters['slug'] ?? '';
            String productId = slug;
            final skuMatch = RegExp(r'^[sS]?(\d+)').firstMatch(slug);
            if (skuMatch != null) {
              final sku = skuMatch.group(0)!.toUpperCase();
              productId = 'sku:$sku';
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

        // ====================================================================
        // LEGACY /tienda/* ROUTES (redirects for non-shell pages only)
        // NOTE: shell page redirects are handled above.
        // ====================================================================
        GoRoute(
          path: '/tienda/producto/:id',
          redirect: (context, state) =>
              '/producto/${state.pathParameters['id']}',
        ),
        GoRoute(
          path: '/tienda/checkout',
          redirect: (context, state) => '/checkout',
        ),
        GoRoute(
          path: '/tienda/pedido/:id',
          redirect: (context, state) {
            final status = state.uri.queryParameters['status'];
            final id = state.pathParameters['id'];
            return status != null
                ? '/pedido/$id?status=$status'
                : '/pedido/$id';
          },
        ),

        // Customer account legacy redirects (sub-pages only, /tienda/cuenta is in shell)
        GoRoute(
          path: '/tienda/cuenta/login',
          redirect: (context, state) => '/cuenta/login',
        ),
        GoRoute(
          path: '/tienda/cuenta/perfil',
          redirect: (context, state) => '/cuenta/perfil',
        ),
        GoRoute(
          path: '/tienda/cuenta/direcciones',
          redirect: (context, state) => '/cuenta/direcciones',
        ),
        GoRoute(
          path: '/tienda/cuenta/pedidos',
          redirect: (context, state) => '/cuenta/pedidos',
        ),
        GoRoute(
          path: '/tienda/cuenta/bicicletas',
          redirect: (context, state) => '/cuenta/bicicletas',
        ),
        GoRoute(
          path: '/tienda/cuenta/servicios',
          redirect: (context, state) {
            final bikeId = state.uri.queryParameters['bike_id'];
            return bikeId != null
                ? '/cuenta/servicios?bike_id=$bikeId'
                : '/cuenta/servicios';
          },
        ),
        GoRoute(
          path: '/tienda/cuenta/mensajes',
          redirect: (context, state) => '/cuenta/mensajes',
        ),
        GoRoute(
          path: '/tienda/cuenta/mensajes/:id',
          redirect: (context, state) =>
              '/cuenta/mensajes/${state.pathParameters['id']}',
        ),
        GoRoute(
          path: '/tienda/cuenta/chats',
          redirect: (context, state) => '/cuenta/chats',
        ),
        GoRoute(
          path: '/tienda/cuenta/chats/:id',
          redirect: (context, state) =>
              '/cuenta/chats/${state.pathParameters['id']}',
        ),

        // Policy pages legacy redirects
        GoRoute(
          path: '/tienda/nosotros',
          redirect: (context, state) => '/nosotros',
        ),
        GoRoute(
          path: '/tienda/terminos',
          redirect: (context, state) => '/terminos',
        ),
        GoRoute(
          path: '/tienda/privacidad',
          redirect: (context, state) => '/privacidad',
        ),
        GoRoute(
          path: '/tienda/devoluciones',
          redirect: (context, state) => '/devoluciones',
        ),
        GoRoute(
          path: '/tienda/envios',
          redirect: (context, state) => '/envios',
        ),
        GoRoute(
          path: '/tienda/pagina/:slug',
          redirect: (context, state) {
            final slug = state.pathParameters['slug'];
            final uri = Uri(
              path: '/pagina/$slug',
              queryParameters: state.uri.queryParameters,
            );
            return uri.toString();
          },
        ),
      ],
    );
  }
}
