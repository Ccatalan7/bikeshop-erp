import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'public_store/providers/cart_provider.dart';
import 'public_store/providers/public_store_tenant_provider.dart';
import 'public_store/routes/public_store_router.dart';
import 'public_store/services/address_autocomplete_service.dart';
import 'public_store/services/public_store_scroll_state.dart';
import 'public_store/services/customer_account_service.dart';
import 'public_store/services/public_inventory_service.dart';
import 'public_store/theme/public_store_theme.dart';
import 'public_store/widgets/public_store_bootstrap.dart';
import 'shared/config/supabase_config.dart';
import 'shared/services/error_reporting_service.dart';
import 'shared/services/tenant_detection_service.dart';
import 'shared/utils/web_url.dart';
import 'shared/widgets/app_selection_scope.dart';
import 'modules/website/providers/website_edit_mode_provider.dart';
import 'modules/website/services/mercadopago_service.dart';
import 'modules/website/services/website_service.dart';
import 'modules/messaging/providers/chat_provider.dart';

// Custom scroll behavior to prevent browser navigation gestures on trackpad
class AppScrollBehavior extends MaterialScrollBehavior {
  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.stylus,
        PointerDeviceKind.trackpad,
      };
}

String? _initialBrowserUrl;

bool get _shouldResetLocalStoreDebugState {
  const reset = bool.fromEnvironment('PUBLIC_STORE_DEBUG_RESET_LOCAL_STATE');
  if (!reset) return false;

  if (!kIsWeb) {
    return true;
  }

  final host = Uri.base.host.toLowerCase().split(':').first;
  return host == 'localhost' || host == '127.0.0.1';
}

Future<void> _resetLocalStoreDebugStateIfNeeded(
  SharedPreferences prefs,
) async {
  if (!_shouldResetLocalStoreDebugState) return;

  const tenantId = String.fromEnvironment('PUBLIC_STORE_TENANT_ID');
  const cachePrefixes = [
    'website_settings_',
    'website_blocks_',
    'website_navigation_',
    'website_public_store_last_refresh_',
  ];

  final keysToRemove = <String>{};
  if (tenantId.isNotEmpty) {
    for (final prefix in cachePrefixes) {
      keysToRemove.add('$prefix$tenantId');
    }
  } else {
    for (final key in prefs.getKeys()) {
      if (cachePrefixes.any(key.startsWith)) {
        keysToRemove.add(key);
      }
    }
  }

  for (final key in keysToRemove) {
    await prefs.remove(key);
  }

  final auth = Supabase.instance.client.auth;
  final hadSession = auth.currentSession != null;
  if (hadSession) {
    await auth.signOut();
  }

  debugPrint(
    '🧪 [StoreMain] Reset public store debug state: '
    'removed ${keysToRemove.length} cache keys, signedOut=$hadSession',
  );
}

Future<void> main() async {
  if (kIsWeb) {
    _initialBrowserUrl = getInitialBrowserUrl();
    debugPrint('🚀 [StoreMain] Captured initial URL: $_initialBrowserUrl');
  }

  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    // Initialize SharedPreferences BEFORE the app starts
    // This allows us to access cache synchronously in the first frame
    final prefs = await SharedPreferences.getInstance();
    WebsiteService.setSharedPreferences(prefs);

    // Clean URLs (no hash #) for web
    usePathUrlStrategy();

    if (!SupabaseConfig.isConfigured && kDebugMode) {
      debugPrint(
        '[Supabase] WARNING: SupabaseConfig still has placeholder values. '
        'Update lib/shared/config/supabase_config.dart or provide dart-defines.',
      );
    }

    await Supabase.initialize(
      url: SupabaseConfig.url,
      anonKey: SupabaseConfig.anonKey,
      authOptions: const FlutterAuthClientOptions(
        autoRefreshToken: true,
      ),
    );

    await _resetLocalStoreDebugStateIfNeeded(prefs);

    FlutterError.onError = (FlutterErrorDetails details) {
      // Suppress Flutter Web-specific "disposed EngineFlutterView" errors
      final errorString = details.exceptionAsString();
      if (kIsWeb) {
        if (errorString.contains('disposed') &&
            errorString.contains('EngineFlutterView')) {
          return;
        }
        if (errorString.contains('BindingError') ||
            errorString.contains('ColorSpace') ||
            errorString.contains('Picture') ||
            errorString.contains('Typeface') ||
            errorString.contains('Shader')) {
          return;
        }
      }

      ErrorReportingService.report(details.exception, details.stack);
      FlutterError.dumpErrorToConsole(details);
    };

    runApp(const PublicStoreApp());

    // NOTE: HTML splash screen is now hidden by PublicStoreBootstrap
    // AFTER data is loaded, for a seamless transition without spinner flash
  }, (error, stack) {
    final errorString = error.toString();

    // Suppress Flutter Web-specific errors that don't affect functionality
    if (kIsWeb) {
      // EngineFlutterView disposed errors
      if (errorString.contains('disposed') &&
          errorString.contains('EngineFlutterView')) {
        return;
      }
      // CanvasKit BindingError (WebGL/ColorSpace/Picture issues)
      if (errorString.contains('BindingError') ||
          errorString.contains('ColorSpace') ||
          errorString.contains('Picture') ||
          errorString.contains('Typeface') ||
          errorString.contains('Shader')) {
        return;
      }
    }

    ErrorReportingService.report(error, stack);
    if (kDebugMode) {
      debugPrint('❌ [StoreMain] Unhandled error: $error');
      debugPrint('❌ [StoreMain] Stack: $stack');
    }
  });
}

class PublicStoreApp extends StatelessWidget {
  const PublicStoreApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider(create: (_) => TenantDetectionService()),
        Provider(create: (_) => PublicStoreScrollState()),
        ChangeNotifierProvider(
          create: (context) => PublicStoreTenantProvider(
            context.read<TenantDetectionService>(),
          ),
        ),
        ChangeNotifierProvider(create: (_) => WebsiteService()),
        ChangeNotifierProvider(create: (_) => WebsiteEditModeProvider()),
        ChangeNotifierProvider(create: (_) => PublicInventoryService()),
        ChangeNotifierProvider(create: (_) => CartProvider()),
        ChangeNotifierProvider(create: (_) => ChatProvider()),
        ChangeNotifierProvider(create: (_) => AddressAutocompleteService()),
        ChangeNotifierProxyProvider<PublicStoreTenantProvider,
            MercadoPagoService>(
          create: (_) => MercadoPagoService(),
          update: (context, tenantProvider, service) {
            service ??= MercadoPagoService();
            final tenantId = tenantProvider.tenantId;
            if (tenantId != null && tenantId.isNotEmpty) {
              service.setTenantId(tenantId);
            }
            return service;
          },
        ),
        ChangeNotifierProxyProvider<PublicStoreTenantProvider,
            CustomerAccountService>(
          create: (_) => CustomerAccountService(),
          update: (context, tenantProvider, service) {
            service ??= CustomerAccountService();
            service.setTenantId(tenantProvider.tenantId);
            return service;
          },
        ),
      ],
      child: MaterialApp.router(
        debugShowCheckedModeBanner: false,
        title: 'Tienda',
        theme: PublicStoreTheme.theme,
        scrollBehavior: AppScrollBehavior(),
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [
          Locale('es'),
          Locale('en'),
        ],
        routerConfig: PublicStoreRouter.createRouter(),
        builder: (context, child) {
          // Single place to do tenant detection + initial data preload.
          return AppSelectionScope(
            child: PublicStoreBootstrap(
              child: child ?? const SizedBox.shrink(),
            ),
          );
        },
      ),
    );
  }
}
