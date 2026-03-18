import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';

import 'shared/routes/app_router.dart';
import 'shared/services/auth_service.dart';
import 'modules/settings/services/appearance_service.dart';
import 'shared/themes/app_theme.dart';
import 'main.dart'; // For AppScrollBehavior
import 'shared/widgets/window_zoom_scope.dart';
import 'shared/widgets/scanner_bridge_scope.dart';
import 'shared/widgets/app_selection_scope.dart';

class VinabikePublicRouterApp extends StatefulWidget {
  final AuthService authService;
  final AppearanceService appearanceService;
  final bool isPublicStoreHost;
  final String? initialUrl;

  const VinabikePublicRouterApp({
    super.key,
    required this.authService,
    required this.appearanceService,
    required this.isPublicStoreHost,
    this.initialUrl,
  });

  @override
  State<VinabikePublicRouterApp> createState() =>
      _VinabikePublicRouterAppState();
}

class _VinabikePublicRouterAppState extends State<VinabikePublicRouterApp> {
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    _router = AppRouter.createRouter(
      widget.authService,
      forcePublicStoreHost: widget.isPublicStoreHost,
      initialLocationOverride: widget.initialUrl,
    );
  }

  @override
  void dispose() {
    // router disposal is handled by GoRouter internal logic usually,
    // but if we created it, we should verify.
    // AppRouter.createRouter returns a GoRouter.
    // GoRouter disposes its listeners.
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Vinabike',
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: widget.appearanceService.themeMode,
      scrollBehavior: AppScrollBehavior(),
      routerConfig: _router,
      debugShowCheckedModeBanner: false,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('es', ''),
        Locale('en', ''),
      ],
      locale: const Locale('es', ''),
      builder: (context, child) => AppSelectionScope(
        child: WindowZoomScope(
          child: ScannerBridgeScope(
            child: child ?? const SizedBox.shrink(),
          ),
        ),
      ),
    );
  }
}
