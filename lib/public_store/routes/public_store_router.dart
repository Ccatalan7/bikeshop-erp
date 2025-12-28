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
// PAGE BUILDER HELPER
// ============================================================================

Page<dynamic> _buildPage(
  BuildContext context,
  GoRouterState state,
  Widget child,
) {
  return NoTransitionPage<void>(
    key: state.pageKey,
    child: PublicStoreLayout(
      enablePageViewScrolling: true,
      child: child,
    ),
  );
}

Page<dynamic> _buildPageNoScroll(
  BuildContext context,
  GoRouterState state,
  Widget child,
) {
  return NoTransitionPage<void>(
    key: state.pageKey,
    child: PublicStoreLayout(
      enablePageViewScrolling: false,
      child: child,
    ),
  );
}

// ============================================================================
// ROUTER CONFIGURATION
// ============================================================================

class PublicStoreRouter {
  static GoRouter createRouter() {
    return GoRouter(
      debugLogDiagnostics: false,
      initialLocation: null,
      routes: [
        // ====================================================================
        // MAIN PAGES
        // ====================================================================

        // Home
        GoRoute(
          path: '/',
          pageBuilder: (context, state) => _buildPage(
            context,
            state,
            const PublicHomePage(),
          ),
        ),

        // Products
        GoRoute(
          path: '/productos',
          pageBuilder: (context, state) => _buildPage(
            context,
            state,
            const ProductCatalogPage(),
          ),
        ),

        // Contact
        GoRoute(
          path: '/contacto',
          pageBuilder: (context, state) => _buildPage(
            context,
            state,
            const ContactPage(),
          ),
        ),

        // Cart
        GoRoute(
          path: '/carrito',
          pageBuilder: (context, state) => _buildPage(
            context,
            state,
            const CartPage(),
          ),
        ),

        // Account Dashboard
        GoRoute(
          path: '/cuenta',
          pageBuilder: (context, state) => _buildPage(
            context,
            state,
            const CustomerDashboardPage(),
          ),
        ),

        // ====================================================================
        // POLICY PAGES
        // ====================================================================
        GoRoute(
          path: '/nosotros',
          pageBuilder: (context, state) => _buildPage(
            context,
            state,
            const StaticPolicyPage(
              slug: 'nosotros',
              fallbackTitle: 'Sobre Nosotros',
            ),
          ),
        ),
        GoRoute(
          path: '/terminos',
          pageBuilder: (context, state) => _buildPage(
            context,
            state,
            const StaticPolicyPage(
              slug: 'terminos',
              fallbackTitle: 'Términos y Condiciones',
            ),
          ),
        ),
        GoRoute(
          path: '/privacidad',
          pageBuilder: (context, state) => _buildPage(
            context,
            state,
            const StaticPolicyPage(
              slug: 'privacidad',
              fallbackTitle: 'Política de Privacidad',
            ),
          ),
        ),
        GoRoute(
          path: '/devoluciones',
          pageBuilder: (context, state) => _buildPage(
            context,
            state,
            const StaticPolicyPage(
              slug: 'devoluciones',
              fallbackTitle: 'Política de Devoluciones',
            ),
          ),
        ),
        GoRoute(
          path: '/envios',
          pageBuilder: (context, state) => _buildPage(
            context,
            state,
            const StaticPolicyPage(
              slug: 'envios',
              fallbackTitle: 'Información de Envíos',
            ),
          ),
        ),

        // ====================================================================
        // DETAIL PAGES
        // ====================================================================

        // Product detail
        GoRoute(
          path: '/producto/:id',
          pageBuilder: (context, state) {
            final productId = state.pathParameters['id']!;
            return _buildPage(
              context,
              state,
              ProductDetailPage(productId: productId),
            );
          },
        ),

        // Checkout
        GoRoute(
          path: '/checkout',
          pageBuilder: (context, state) => _buildPage(
            context,
            state,
            const CheckoutPage(),
          ),
        ),

        // Order confirmation
        GoRoute(
          path: '/pedido/:id',
          pageBuilder: (context, state) {
            final orderId = state.pathParameters['id']!;
            final status = state.uri.queryParameters['status'];
            return _buildPage(
              context,
              state,
              OrderConfirmationPage(
                orderId: orderId,
                paymentStatus: status,
              ),
            );
          },
        ),

        // ====================================================================
        // CUSTOMER ACCOUNT SUB-PAGES
        // ====================================================================
        GoRoute(
          path: '/cuenta/login',
          pageBuilder: (context, state) => _buildPage(
            context,
            state,
            const CustomerAuthPage(),
          ),
        ),
        GoRoute(
          path: '/cuenta/perfil',
          pageBuilder: (context, state) => _buildPage(
            context,
            state,
            const CustomerProfilePage(),
          ),
        ),
        GoRoute(
          path: '/cuenta/direcciones',
          pageBuilder: (context, state) => _buildPage(
            context,
            state,
            const CustomerAddressesPage(),
          ),
        ),
        GoRoute(
          path: '/cuenta/pedidos',
          pageBuilder: (context, state) => _buildPage(
            context,
            state,
            const CustomerOrdersPage(),
          ),
        ),
        GoRoute(
          path: '/cuenta/bicicletas',
          pageBuilder: (context, state) => _buildPage(
            context,
            state,
            const CustomerBikesPage(),
          ),
        ),
        GoRoute(
          path: '/cuenta/servicios',
          pageBuilder: (context, state) {
            final bikeId = state.uri.queryParameters['bike_id'];
            return _buildPage(
              context,
              state,
              CustomerServiceHistoryPage(bikeId: bikeId),
            );
          },
        ),

        // Chat / Support
        GoRoute(
          path: '/cuenta/mensajes',
          pageBuilder: (context, state) => _buildPage(
            context,
            state,
            const CustomerChatListPage(),
          ),
        ),
        GoRoute(
          path: '/cuenta/mensajes/:id',
          pageBuilder: (context, state) {
            final conversationId = state.pathParameters['id']!;
            return _buildPageNoScroll(
              context,
              state,
              CustomerChatDetailPage(conversationId: conversationId),
            );
          },
        ),
        GoRoute(
          path: '/cuenta/chats',
          pageBuilder: (context, state) => _buildPage(
            context,
            state,
            const CustomerChatHubPage(),
          ),
        ),
        GoRoute(
          path: '/cuenta/chats/:id',
          pageBuilder: (context, state) {
            final conversationId = state.pathParameters['id']!;
            return _buildPageNoScroll(
              context,
              state,
              CustomerChatHubPage(initialConversationId: conversationId),
            );
          },
        ),

        // ====================================================================
        // DYNAMIC PAGES
        // ====================================================================
        GoRoute(
          path: '/pagina/:slug',
          pageBuilder: (context, state) {
            final slug = state.pathParameters['slug'] ?? 'home';
            return _buildPage(
              context,
              state,
              DynamicWebsitePage(slug: slug),
            );
          },
        ),

        // Legacy Google Merchant URLs
        GoRoute(
          path: '/shop/:slug',
          pageBuilder: (context, state) {
            final slug = state.pathParameters['slug'] ?? '';
            String productId = slug;
            final skuMatch = RegExp(r'^[sS]?(\d+)').firstMatch(slug);
            if (skuMatch != null) {
              final sku = skuMatch.group(0)!.toUpperCase();
              productId = 'sku:$sku';
            }
            return _buildPage(
              context,
              state,
              ProductDetailPage(productId: productId),
            );
          },
        ),

        // ====================================================================
        // LEGACY /tienda/* REDIRECTS
        // ====================================================================
        GoRoute(
          path: '/tienda',
          redirect: (context, state) => '/',
        ),
        GoRoute(
          path: '/tienda/productos',
          redirect: (context, state) => '/productos',
        ),
        GoRoute(
          path: '/tienda/producto/:id',
          redirect: (context, state) =>
              '/producto/${state.pathParameters['id']}',
        ),
        GoRoute(
          path: '/tienda/carrito',
          redirect: (context, state) => '/carrito',
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
        GoRoute(
          path: '/tienda/contacto',
          redirect: (context, state) => '/contacto',
        ),

        // Customer account legacy redirects
        GoRoute(
          path: '/tienda/cuenta',
          redirect: (context, state) => '/cuenta',
        ),
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
          redirect: (context, state) =>
              '/pagina/${state.pathParameters['slug']}',
        ),
      ],
    );
  }
}
