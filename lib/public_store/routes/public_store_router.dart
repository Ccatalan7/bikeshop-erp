import 'package:flutter/foundation.dart';
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
import '../pages/android_app_download_page.dart';
import '../pages/dynamic_website_page.dart';
import '../pages/order_confirmation_page.dart';
import '../pages/product_catalog_page.dart';
import '../pages/product_detail_page.dart';
import '../pages/public_home_page.dart';
import '../pages/static_policy_page.dart';
import '../widgets/public_store_layout.dart';

// Match the tenant detection perf logging pattern.
// Enable in debug, or in release via:
// flutter build web --release --dart-define=STORE_PERF_LOGS=true
bool get _storeNavLogsEnabled =>
    kDebugMode || const bool.fromEnvironment('STORE_PERF_LOGS');

final Set<String> _loggedTransitionFirstFrame = <String>{};

final Expando<bool> _transitionListenerAttached = Expando<bool>();

Widget _mobilePremiumTransition({
  required Animation<double> animation,
  required Animation<double> secondaryAnimation,
  required Widget child,
}) {
  // Goal: "zig-zag" motion (push: right->left, pop: left->right).
  // (animation goes 0->1 on push, 1->0 on pop.)
  final curved = CurvedAnimation(
    parent: animation,
    curve: Curves.easeInOutCubic,
    reverseCurve: Curves.easeInOutCubic,
  );

  // Opposite-direction slide for pop to get the zig-zag effect.
  final isPopping = animation.status == AnimationStatus.reverse;
  final slideTween = isPopping
      ? Tween<Offset>(begin: const Offset(-1.0, 0), end: Offset.zero)
      : Tween<Offset>(begin: const Offset(1.0, 0), end: Offset.zero);
  final slide = slideTween.animate(curved);

  // Keep fade extremely subtle; rely mostly on motion.
  final slightFade = Tween<double>(begin: 0.98, end: 1.0).animate(curved);

  // Add a subtle edge shadow.
  final withShadow = DecoratedBox(
    decoration: const BoxDecoration(
      boxShadow: <BoxShadow>[
        BoxShadow(
          color: Color(0x26000000),
          blurRadius: 18,
          spreadRadius: 1,
          offset: Offset(-8, 0),
        ),
      ],
    ),
    child: child,
  );

  return ClipRect(
    child: FadeTransition(
      opacity: slightFade,
      child: SlideTransition(
        position: slide,
        child: withShadow,
      ),
    ),
  );
}

Widget _desktopTransition({
  required Animation<double> animation,
  required Widget child,
  required bool isSmallScreen,
}) {
  final curved = CurvedAnimation(
    parent: animation,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeInCubic,
  );

  final beginDy = isSmallScreen
      ? (_storeNavLogsEnabled ? 0.10 : 0.08)
      : (_storeNavLogsEnabled ? 0.06 : 0.04);
  final beginScale = isSmallScreen
      ? (_storeNavLogsEnabled ? 0.965 : 0.975)
      : (_storeNavLogsEnabled ? 0.975 : 0.985);
  final scale = Tween<double>(begin: beginScale, end: 1.0).animate(curved);

  return FadeTransition(
    opacity: curved,
    child: SlideTransition(
      position: Tween<Offset>(
        begin: Offset(0, beginDy),
        end: Offset.zero,
      ).animate(curved),
      child: ScaleTransition(
        scale: scale,
        child: child,
      ),
    ),
  );
}

void _attachTransitionDebugOnce(
  Animation<double> animation, {
  required Uri uri,
  required String kind,
}) {
  if (!_storeNavLogsEnabled) return;
  if (_transitionListenerAttached[animation] == true) return;
  _transitionListenerAttached[animation] = true;

  double lastLogged = -1;

  void logValue(String tag) {
    final v = animation.value;
    // Avoid spam; only log when value meaningfully changes.
    if ((v - lastLogged).abs() < 0.08 && tag == 'tick') return;
    lastLogged = v;
    debugPrint(
      '🎞️ [PublicStoreRouter] $kind $tag uri=$uri '
      'value=${v.toStringAsFixed(3)} status=${animation.status}',
    );
  }

  animation.addStatusListener((status) {
    debugPrint('🎞️ [PublicStoreRouter] $kind status uri=$uri status=$status');
  });

  animation.addListener(() => logValue('tick'));

  // Log immediately upon attachment.
  logValue('attach');
}

class _PublicStoreNavObserver extends NavigatorObserver {
  void _log(String verb, Route<dynamic>? route, Route<dynamic>? previousRoute) {
    if (!_storeNavLogsEnabled) return;
    final name = route?.settings.name;
    final prev = previousRoute?.settings.name;
    debugPrint('🧭 [PublicStoreNav] $verb name=$name (from=$prev)');
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _log('push', route, previousRoute);

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) =>
      _log('replace', newRoute, oldRoute);

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _log('pop', previousRoute, route);
}

// ============================================================================
// PAGE BUILDER HELPER
// ============================================================================

String _storefrontMode(GoRouterState state) {
  final uri = state.uri;
  final isEdit = uri.queryParameters['edit'] == 'true';
  final isPreview = uri.queryParameters['preview'] == 'true';
  return isEdit ? 'edit' : (isPreview ? 'preview' : 'normal');
}

/// Keeps the routed [Page] identity owned by go_router.
///
/// A previous implementation cached one process-wide [UniqueKey]. During a
/// category -> catalog-root replacement, go_router can build the outgoing and
/// incoming pages in the same Navigator update. Both pages then received that
/// cached key and tripped Navigator's duplicated-page-key assertion.
@visibleForTesting
LocalKey publicStoreRoutePageKey(GoRouterState state) => state.pageKey;

/// Recreates only the storefront layout when Edit/Preview mode changes.
///
/// This key is intentionally separate from the Navigator [Page] key. Its
/// parent page scopes it, so two routes can coexist safely while a replacement
/// is being reconciled.
@visibleForTesting
LocalKey publicStoreModeContentKey(GoRouterState state) {
  return ValueKey<(LocalKey, String, String)>(
    (
      state.pageKey,
      state.matchedLocation,
      _storefrontMode(state),
    ),
  );
}

Page<dynamic> _buildPage(
  BuildContext context,
  GoRouterState state,
  Widget child,
) {
  final mediaQuery = MediaQuery.maybeOf(context);
  final disableAnimations = mediaQuery?.disableAnimations ?? false;
  final accessibleNavigation = mediaQuery?.accessibleNavigation ?? false;
  final reduceMotion = disableAnimations || accessibleNavigation;

  // Mobile tends to hide subtle transitions (small screens + often lower FPS).
  // Make it a bit more noticeable without being intrusive on desktop.
  final isSmallScreen = (mediaQuery?.size.shortestSide ?? 9999) < 600;

  if (_storeNavLogsEnabled) {
    debugPrint(
      '➡️ [PublicStoreRouter] build uri=${state.uri} matched=${state.matchedLocation} reduceMotion=$reduceMotion',
    );
    if (reduceMotion) {
      debugPrint(
        '🟡 [PublicStoreRouter] Transitions disabled (reduce motion): '
        'disableAnimations=$disableAnimations accessibleNavigation=$accessibleNavigation',
      );
    }
  }

  final pageKey = publicStoreRoutePageKey(state);

  // Recreate the layout on mode changes without changing or sharing the
  // Navigator Page identity.
  final pageChild = KeyedSubtree(
    key: publicStoreModeContentKey(state),
    child: PublicStoreLayout(
      routePath: state.uri.path,
      enablePageViewScrolling: true,
      child: child,
    ),
  );

  // Respect user reduce-motion settings.
  // Also disable transitions on web due to Flutter web rendering bug where
  // FadeTransition/ScaleTransition can get "stuck" at invisible state
  // until a window resize forces a repaint.
  if (reduceMotion || kIsWeb) {
    return NoTransitionPage<void>(
      key: pageKey,
      name: state.uri.toString(),
      child: pageChild,
    );
  }

  return CustomTransitionPage<void>(
    key: pageKey,
    name: state.uri.toString(),
    child: pageChild,
    // Mobile: a more obvious, native-feeling slide+fade.
    transitionDuration: isSmallScreen
        ? const Duration(milliseconds: 420)
        : const Duration(milliseconds: 300),
    reverseTransitionDuration: isSmallScreen
        ? const Duration(milliseconds: 380)
        : const Duration(milliseconds: 260),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      _attachTransitionDebugOnce(
        animation,
        uri: state.uri,
        kind: 'transition',
      );
      if (_storeNavLogsEnabled) {
        final id = '${state.pageKey}_${state.uri}';
        if (_loggedTransitionFirstFrame.add(id)) {
          debugPrint(
            '🎞️ [PublicStoreRouter] transition builder uri=${state.uri} '
            'value=${animation.value.toStringAsFixed(3)} status=${animation.status}',
          );
        }
      }
      if (isSmallScreen) {
        return _mobilePremiumTransition(
          animation: animation,
          secondaryAnimation: secondaryAnimation,
          child: child,
        );
      }

      return _desktopTransition(
        animation: animation,
        child: child,
        isSmallScreen: isSmallScreen,
      );
    },
  );
}

Page<dynamic> _buildPageNoScroll(
  BuildContext context,
  GoRouterState state,
  Widget child,
) {
  final mediaQuery = MediaQuery.maybeOf(context);
  final disableAnimations = mediaQuery?.disableAnimations ?? false;
  final accessibleNavigation = mediaQuery?.accessibleNavigation ?? false;
  final reduceMotion = disableAnimations || accessibleNavigation;

  final isSmallScreen = (mediaQuery?.size.shortestSide ?? 9999) < 600;

  if (_storeNavLogsEnabled) {
    debugPrint(
      '➡️ [PublicStoreRouter] build(noScroll) uri=${state.uri} matched=${state.matchedLocation} reduceMotion=$reduceMotion',
    );
    if (reduceMotion) {
      debugPrint(
        '🟡 [PublicStoreRouter] Transitions disabled (reduce motion, noScroll): '
        'disableAnimations=$disableAnimations accessibleNavigation=$accessibleNavigation',
      );
    }
  }

  final pageKey = publicStoreRoutePageKey(state);

  // Recreate the layout on mode changes without changing or sharing the
  // Navigator Page identity.
  final pageChild = KeyedSubtree(
    key: publicStoreModeContentKey(state),
    child: PublicStoreLayout(
      routePath: state.uri.path,
      enablePageViewScrolling: false,
      child: child,
    ),
  );

  // Respect user reduce-motion settings.
  // Also disable transitions on web due to Flutter web rendering bug where
  // FadeTransition/ScaleTransition can get "stuck" at invisible state.
  if (reduceMotion || kIsWeb) {
    return NoTransitionPage<void>(
      key: pageKey,
      name: state.uri.toString(),
      child: pageChild,
    );
  }

  return CustomTransitionPage<void>(
    key: pageKey,
    name: state.uri.toString(),
    child: pageChild,
    transitionDuration: isSmallScreen
        ? const Duration(milliseconds: 420)
        : const Duration(milliseconds: 300),
    reverseTransitionDuration: isSmallScreen
        ? const Duration(milliseconds: 380)
        : const Duration(milliseconds: 260),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      _attachTransitionDebugOnce(
        animation,
        uri: state.uri,
        kind: 'transition(noScroll)',
      );

      if (_storeNavLogsEnabled) {
        final id = '${state.pageKey}_${state.uri}_noScroll';
        if (_loggedTransitionFirstFrame.add(id)) {
          debugPrint(
            '🎞️ [PublicStoreRouter] transition builder(noScroll) uri=${state.uri} '
            'value=${animation.value.toStringAsFixed(3)} status=${animation.status}',
          );
        }
      }

      if (isSmallScreen) {
        return _mobilePremiumTransition(
          animation: animation,
          secondaryAnimation: secondaryAnimation,
          child: child,
        );
      }

      return _desktopTransition(
        animation: animation,
        child: child,
        isSmallScreen: isSmallScreen,
      );
    },
  );
}

// ============================================================================
// ROUTER CONFIGURATION
// ============================================================================

class PublicStoreRouter {
  static GoRouter createRouter() {
    PublicStoreRuntimeConfig.isErpMounted = false;

    // IMPORTANT (Web): We use imperative navigation (`push`/`pop`) to guarantee
    // consistent forward/back behavior + transitions.
    // By default, go_router may NOT reflect imperative navigation in the URL,
    // which makes the address bar stay at the origin (e.g. https://vinabike.cl/)
    // even while the app is on /productos.
    // This opt-in makes the URL track `push()` routes as expected.
    GoRouter.optionURLReflectsImperativeAPIs = true;

    return GoRouter(
      debugLogDiagnostics: false,
      initialLocation: null,
      observers: [
        if (_storeNavLogsEnabled) _PublicStoreNavObserver(),
      ],
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

        // Services catalog
        GoRoute(
          path: '/servicios',
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

        // Account dashboard
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

        // Product category landing pages (SEO-friendly filtered catalog)
        GoRoute(
          path: '/productos/categoria/:category',
          pageBuilder: (context, state) => _buildPage(
            context,
            state,
            const ProductCatalogPage(),
          ),
        ),

        // Service category landing pages (SEO-friendly filtered catalog)
        GoRoute(
          path: '/servicios/categoria/:category',
          pageBuilder: (context, state) => _buildPage(
            context,
            state,
            const ProductCatalogPage(),
          ),
        ),

        // Product detail (canonical: /productos/:slug/:sku)
        GoRoute(
          path: '/productos/:slug/:sku',
          pageBuilder: (context, state) {
            final sku = state.pathParameters['sku']!;
            return _buildPage(
              context,
              state,
              ProductDetailPage(productId: 'sku:$sku'),
            );
          },
        ),

        // Previous canonical product detail. ProductDetailPage upgrades the URL.
        GoRoute(
          path: '/productos/:id',
          pageBuilder: (context, state) {
            final productId = state.pathParameters['id']!;
            return _buildPage(
              context,
              state,
              ProductDetailPage(productId: productId),
            );
          },
        ),

        // Legacy product detail (redirect to canonical)
        GoRoute(
          path: '/producto/:id',
          redirect: (context, state) =>
              '/productos/${state.pathParameters['id']}',
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
          path: '/cuenta/descargas/android',
          pageBuilder: (context, state) => _buildPage(
            context,
            state,
            const AndroidAppDownloadPage(),
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
          redirect: (context, state) {
            final qp = state.uri.queryParameters;
            return Uri(
              path: '/productos',
              queryParameters: qp.isEmpty ? null : qp,
            ).toString();
          },
        ),
        GoRoute(
          path: '/tienda/servicios',
          redirect: (context, state) {
            final qp = state.uri.queryParameters;
            return Uri(
              path: '/servicios',
              queryParameters: qp.isEmpty ? null : qp,
            ).toString();
          },
        ),
        GoRoute(
          path: '/tienda/producto/:id',
          redirect: (context, state) =>
              '/productos/${state.pathParameters['id']}',
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
          path: '/tienda/cuenta/descargas/android',
          redirect: (context, state) => '/cuenta/descargas/android',
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
