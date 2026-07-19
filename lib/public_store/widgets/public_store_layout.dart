import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

// ignore: avoid_web_libraries_in_flutter
import 'package:web/web.dart'
    if (dart.library.io) '../../modules/website/services/google_business_service_stub.dart'
    as web;

import '../providers/cart_provider.dart';
import '../providers/public_store_tenant_provider.dart';
import '../services/public_store_scroll_state.dart';
import '../theme/public_store_theme.dart';
import '../theme/public_header_contrast.dart';
import 'floating_whatsapp_button.dart';
import 'customer_account_menu.dart';
import '../../modules/website/services/website_service.dart';
import '../../modules/website/providers/website_edit_mode_provider.dart';
import '../../modules/website/widgets/website_link_value_editor.dart';
import '../../modules/website/widgets/website_workspace_scope.dart';
import '../../modules/website/theme/website_theme_builder.dart';
import '../../modules/website/widgets/deferred_website_editor_panel.dart';
import '../../modules/website/models/website_page_models.dart';
import '../../modules/website/models/website_destination.dart';
import '../../shared/routes/erp_routes_barrel.dart' deferred as erp
    show
        AnalyticsDashboardPage,
        FeaturedProductsPage,
        HierarchicalCategoryPage,
        IntegrationsPage,
        NavigationManagementPage,
        OnlineOrdersPage,
        PageManagementPage,
        PaymentMethodsSettingsPage,
        ProductWebsiteVisibilityPage,
        WebsiteCatalogSection,
        SeoSettingsPage,
        WebsiteDestinationManagementPage,
        WebsiteManagementPage,
        WebsiteSettingsPage;
import '../../shared/services/tenant_service.dart';
import '../../shared/utils/file_download_web.dart'
    if (dart.library.io) '../../shared/utils/file_download_stub.dart';
import '../../shared/utils/seo_helper.dart';
import '../services/customer_account_service.dart';
import '../../shared/utils/web_url.dart' show setLocationHash;
import 'customer_chat_widget.dart';
import 'search_overlay.dart';
import '../../shared/widgets/safe_layout_builder.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'mega_menu.dart';

/// Runtime routing mode for the public store shell.
///
/// The same store UI is embedded in two different apps:
/// - Standalone public store (`main_store.dart`)
/// - ERP/admin app preview/editor (`main.dart`)
///
/// Route normalization must behave differently between those modes,
/// especially on native platforms where we cannot infer it from the host.
class PublicStoreRuntimeConfig {
  static bool isErpMounted = false;
}

class PublicStoreLayout extends StatefulWidget {
  final Widget child;
  final bool showEditorButton;
  final bool enablePageViewScrolling;
  final String? routePath;

  /// When true, the editor panel is rendered externally (by PersistentEditorShell)
  /// so this layout should not render it.
  final bool useExternalEditorPanel;

  const PublicStoreLayout({
    super.key,
    required this.child,
    this.showEditorButton = true,
    this.enablePageViewScrolling = true,
    this.useExternalEditorPanel = true,
    this.routePath,
  });

  /// Centralized navigation entry-point for public store UI elements.
  ///
  /// Prefer this over calling `context.go(...)` directly from pages/blocks so
  /// transitions + route normalization behave consistently.
  static Future<void> navigateToHref(
    BuildContext context,
    String href, {
    bool openInNewTab = false,
  }) async {
    final state = context.findAncestorStateOfType<_PublicStoreLayoutState>();
    if (state != null) {
      await state._navigateToHref(context, href, openInNewTab: openInNewTab);
      return;
    }

    // Fallback (should be rare): best-effort navigation without normalization.
    final normalized = href.trim();
    if (normalized.isEmpty) return;

    if (normalized.startsWith('http://') || normalized.startsWith('https://')) {
      final uri = Uri.tryParse(normalized);
      if (uri != null) {
        await launchUrl(
          uri,
          mode: LaunchMode.platformDefault,
          webOnlyWindowName: openInNewTab ? '_blank' : '_self',
        );
      }
      return;
    }

    if (normalized.startsWith('#')) {
      if (kIsWeb) {
        setLocationHash(normalized);
      }
      return;
    }

    // Fallback: treat non-external links as top-level navigation.
    // Using go() avoids stacking routes on web (which can lead to blank frames
    // when a layout exception occurs in an offstage route).
    context.go(normalized);
  }

  @override
  State<PublicStoreLayout> createState() => _PublicStoreLayoutState();
}

class _PublicStoreLayoutState extends State<PublicStoreLayout> {
  static const double _externalEditorPanelWidth = 380;
  static const String _actionPageEditorWorkspace = 'workspace_page_editor';
  static const String _actionEcomCatalog = 'ecom_catalog';
  static const String _actionSitePages = 'site_pages';
  static const String _actionSiteNavigation = 'site_navigation';
  static const String _actionSiteDestinations = 'site_destinations';
  static const String _actionSiteSettings = 'site_settings';
  static const String _actionSiteOpenWebsiteHub = 'site_hub';

  static const String _actionEcomOrders = 'ecom_orders';
  static const String _actionEcomGoogle = 'ecom_google';

  static const String _actionReportsAnalytics = 'reports_analytics';
  static const String _actionReportsOrders = 'reports_orders';

  static const String _actionGoogleOpenMerchantFeed = 'google_open_feed';
  static const String _actionGoogleCopyMerchantFeed = 'google_copy_feed';

  static const String _actionConfigDomain = 'config_domain';
  static const String _actionConfigPaymentMethods = 'config_payment_methods';
  static const String _actionConfigIntegrations = 'config_integrations';
  static const String _actionConfigWebsiteSettings = 'config_website_settings';

  static const String _actionStoreCopyUrl = 'store_copy_url';
  static const String _actionStoreOpenPublic = 'store_open_public';
  static const String _actionStoreOpenWebsite = 'store_open_website';

  static const String _actionPageCopyLink = 'page_copy_link';
  static const String _actionPageOpenNewTab = 'page_open_new_tab';

  bool _isConfigHubOpen = false;
  _EditorConfigHubTab _configHubTab = _EditorConfigHubTab.siteHub;
  _EditorCatalogTab _catalogTab = _EditorCatalogTab.products;
  _EditorCategoryTab _categoryTab = _EditorCategoryTab.publication;

  Future<void>? _erpLibraryFuture;

  Future<void> _ensureErpLibraryLoaded() {
    return _erpLibraryFuture ??= erp.loadLibrary();
  }

  // Screenshot capture state
  bool _isCapturingScreenshot = false;

  // Guard to prevent scheduling multiple navigations in the same frame
  bool _pendingModeNavigation = false;
  bool _pendingProviderModeSync = false;
  bool _isErpMountedStore() => PublicStoreRuntimeConfig.isErpMounted;

  // ------------------------------------------------------------------------
  // On-canvas inline editing: Footer navigation
  // ------------------------------------------------------------------------
  String? _activeInlineFooterNavId;
  final TextEditingController _inlineFooterNavLabelController =
      TextEditingController();
  final FocusNode _inlineFooterNavLabelFocusNode = FocusNode();

  // ------------------------------------------------------------------------
  // Debug: URL + router state (web)
  // ------------------------------------------------------------------------
  bool get _storeUrlLogsEnabled =>
      kDebugMode || const bool.fromEnvironment('STORE_PERF_LOGS');

  String? _lastLoggedUrlSignature;
  // Payment methods now hardcoded - icons hosted in Supabase Storage

  @override
  void initState() {
    super.initState();
    // Settings are loaded in main.dart after tenant detection
    // No need to load here - just watch the service

    // Check if we're returning from Google OAuth and need to restore edit mode
    if (kIsWeb) {
      _checkGoogleOAuthReturn();
    }
    // Payment method icons are now hardcoded - no need to fetch from MercadoPago API
  }

  @override
  void dispose() {
    _inlineFooterNavLabelController.dispose();
    _inlineFooterNavLabelFocusNode.dispose();
    super.dispose();
  }

  String _currentPublicStorePath(BuildContext context) {
    final explicitRoutePath = widget.routePath;
    if (explicitRoutePath != null && explicitRoutePath.isNotEmpty) {
      return explicitRoutePath;
    }

    final routeName = ModalRoute.of(context)?.settings.name;
    if (routeName != null && routeName.isNotEmpty) {
      final parsed = Uri.tryParse(routeName);
      if (parsed != null && parsed.path.isNotEmpty) {
        return parsed.path;
      }
      if (routeName.startsWith('/')) {
        return routeName;
      }
    }

    try {
      final path = GoRouterState.of(context).uri.path;
      if (path.isNotEmpty) {
        return path;
      }
    } catch (_) {
      // Fall through to a safe default.
    }

    return '/';
  }

  bool _isHomePagePath(String path) {
    switch (path) {
      case '/':
      case '/tienda':
      case '/tienda/':
      case '/home':
      case '/inicio':
      case '/tienda/home':
      case '/tienda/inicio':
        return true;
      default:
        return false;
    }
  }

  bool _usesInlineHeaderLayout(String path) {
    return path == '/carrito' ||
        path == '/checkout' ||
        path == '/cuenta' ||
        path.startsWith('/cuenta/') ||
        path == '/tienda/carrito' ||
        path == '/tienda/checkout' ||
        path == '/tienda/cuenta' ||
        path.startsWith('/tienda/cuenta/') ||
        path.startsWith('/pedido/') ||
        path.startsWith('/tienda/pedido/');
  }

  void _beginInlineFooterNavEdit(
    WebsiteEditModeProvider editProvider,
    WebsiteNavigation nav,
  ) {
    setState(() {
      _activeInlineFooterNavId = nav.id;
      _inlineFooterNavLabelController.text =
          editProvider.getEffectiveFooterNavItem(nav).label;
    });
    editProvider.selectBlock('footer');
    editProvider.selectFooterNavItem(nav.id);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _inlineFooterNavLabelFocusNode.requestFocus();
      _inlineFooterNavLabelController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _inlineFooterNavLabelController.text.length,
      );
    });
  }

  Future<void> _showInlineFooterNavDestinationDialog(
    BuildContext context,
    WebsiteEditModeProvider editProvider,
    WebsiteNavigation nav,
  ) async {
    final effective = editProvider.getEffectiveFooterNavItem(nav);

    final initialHref = (effective.linkValue ?? '').trim();

    final pickedHref = await WebsiteLinkValueEditor.pickLink(
      context: context,
      initialValue: initialHref,
      allowInternal: true,
      allowExternal: true,
      allowAnchor: true,
      darkStyle: true,
    );

    if (!context.mounted) return;

    if (pickedHref == null) return;
    final href = pickedHref.trim();
    if (href.isEmpty) return;

    final inferredType = WebsiteDestination.navigationTypeForHref(href);

    var openInNewTab = effective.openInNewTab;
    if (inferredType == NavLinkType.external) {
      final applied = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: const Text('Opciones del enlace'),
            content: SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('Abrir en nueva pestaña'),
              value: openInNewTab,
              onChanged: (v) => setDialogState(() => openInNewTab = v),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Aplicar'),
              ),
            ],
          ),
        ),
      );

      if (applied != true) {
        // Keep the destination change, but preserve the current openInNewTab.
        openInNewTab = effective.openInNewTab;
      }
    } else {
      openInNewTab = false;
    }

    editProvider.updateFooterNavDestination(
      nav.id,
      linkType: inferredType,
      linkValue: href,
      openInNewTab: openInNewTab,
    );
  }

  /// Check localStorage for Google OAuth return flag and restore edit mode
  void _checkGoogleOAuthReturn() {
    try {
      final flag =
          web.window.localStorage.getItem('google_oauth_return_to_editor');
      final openIntegrations =
          web.window.localStorage.getItem('google_oauth_open_integrations');
      if (flag == 'true') {
        debugPrint(
            '🔄 [PublicStoreLayout] Detected OAuth return - restoring edit mode');
        // Clear the flag
        web.window.localStorage.removeItem('google_oauth_return_to_editor');

        // Clear one-shot "open integrations" request (if present).
        if (openIntegrations == 'true') {
          web.window.localStorage.removeItem('google_oauth_open_integrations');
        }

        // Schedule edit mode activation after the widget tree is built
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            final editProvider = context.read<WebsiteEditModeProvider>();
            if (!editProvider.isEditMode) {
              editProvider.switchToEditMode();
              debugPrint(
                  '✅ [PublicStoreLayout] Edit mode restored after OAuth');
            }

            if (openIntegrations == 'true') {
              _openConfigHub(_EditorConfigHubTab.integrations);
            }
          }
        });
      }
    } catch (e) {
      debugPrint('⚠️ [PublicStoreLayout] Error checking OAuth return: $e');
    }
  }

  /// Capture the full page as a screenshot
  Future<void> _captureFullPageScreenshot(
    BuildContext context,
    WebsiteEditModeProvider editProvider,
  ) async {
    // Show loading state
    setState(() => _isCapturingScreenshot = true);

    try {
      // Wait for the layout to rebuild without scroll constraints
      await Future.delayed(const Duration(milliseconds: 100));
      // Wait for another frame to ensure painting is complete
      await WidgetsBinding.instance.endOfFrame;
      await Future.delayed(const Duration(milliseconds: 50));

      final boundary = editProvider.screenshotKey.currentContext
          ?.findRenderObject() as RenderRepaintBoundary?;

      if (boundary == null) {
        throw Exception('No se encontró el área de captura (RepaintBoundary)');
      }

      // Capture image at 2x resolution for crisp output
      final image = await boundary.toImage(pixelRatio: 2.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      final pngBytes = byteData!.buffer.asUint8List();

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName = 'website-preview-$timestamp.png';

      await downloadFile(
        bytes: pngBytes,
        fileName: fileName,
        mimeType: 'image/png',
      );

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Captura descargada: $fileName'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      debugPrint('Screenshot error: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al capturar: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      // Restore normal scroll view
      if (mounted) {
        setState(() => _isCapturingScreenshot = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final supabase = Supabase.instance.client;
    final isLoggedIn = supabase.auth.currentUser != null;

    // Watch providers to rebuild when data changes
    context.watch<PublicStoreTenantProvider>();
    final websiteService = context.watch<WebsiteService>();
    final editProvider = context.watch<WebsiteEditModeProvider>();

    // Check if in edit/preview mode. Also respect URL query params so the UI
    // can enter editor context before provider updates.
    final routerState = GoRouterState.of(context);
    final currentUri = routerState.uri;

    // Log when the router thinks we're on a new location, and what the browser
    // address bar says. This helps diagnose cases where the URL gets rewritten
    // to the origin (path stripped) by an unexpected history.replaceState().
    if (kIsWeb && _storeUrlLogsEnabled) {
      try {
        final browserHref = web.window.location.href;
        final signature =
            '${Uri.base.toString()}|$browserHref|${routerState.uri}|${routerState.matchedLocation}';
        if (_lastLoggedUrlSignature != signature) {
          _lastLoggedUrlSignature = signature;
          debugPrint(
            '🌐 [StoreURL] base=${Uri.base} href=$browserHref '
            'routerUri=${routerState.uri} matched=${routerState.matchedLocation}',
          );
        }
      } catch (e) {
        // Ignore on non-web platforms
      }
    }
    final qp = currentUri.queryParameters;
    // IMPORTANT:
    // - URL params are only used to ENTER editor context (first time).
    // - Once the provider is already in editor context, ignore URL flags.
    //   Otherwise stale params (common with persistent shell pages) can cause
    //   preview/edit to "bounce" back and forth.
    final requestedEditMode = qp['edit'] == 'true';
    final requestedPreviewMode = qp['preview'] == 'true';

    if (editProvider.isInEditorContext && !_pendingProviderModeSync) {
      final shouldSwitchToEdit = requestedEditMode && !editProvider.isEditMode;
      final shouldSwitchToPreview = requestedPreviewMode &&
          !editProvider.isPreviewMode &&
          !requestedEditMode;

      if (shouldSwitchToEdit || shouldSwitchToPreview) {
        _pendingProviderModeSync = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _pendingProviderModeSync = false;
          if (!mounted) return;
          if (shouldSwitchToEdit) {
            editProvider.switchToEditMode();
          } else if (shouldSwitchToPreview) {
            editProvider.switchToPreviewMode();
          }
        });
      }
    }

    final allowUrlForce = !editProvider.isInEditorContext;
    final forceEditMode = allowUrlForce && requestedEditMode;
    final forcePreviewMode = allowUrlForce && requestedPreviewMode;

    final isEditMode = editProvider.isEditMode || forceEditMode;
    final isPreviewMode = editProvider.isPreviewMode || forcePreviewMode;

    final devicePreviewMode = editProvider.devicePreviewMode;
    final isInEditorContext =
        editProvider.isInEditorContext || forceEditMode || forcePreviewMode;

    // ======================================================================
    // PAGE CONTENT TRANSITION (WEB)
    // ======================================================================
    // go_router page transitions can be visually imperceptible here because the
    // header/layout is nearly identical between routes (only body changes).
    // This AnimatedSwitcher makes route changes obvious while keeping header
    // stable. It is disabled for editor/preview modes.
    final mq = MediaQuery.maybeOf(context);
    final reduceMotion =
        (mq?.disableAnimations ?? false) || (mq?.accessibleNavigation ?? false);
    final isSmallScreen = (mq?.size.shortestSide ?? 9999) < 600;

    Widget animateBody(Widget child, {bool expand = false}) {
      // Disable the content switcher on small screens (mobile). On mobile web
      // the animation is often dropped/janky and can feel worse than instant.
      // Also disable on web entirely due to blank screen issues during transitions
      // where the FadeTransition opacity gets stuck at 0 until a resize forces
      // a repaint. This is a known Flutter web rendering issue.
      if (reduceMotion ||
          isSmallScreen ||
          isInEditorContext ||
          isEditMode ||
          isPreviewMode ||
          kIsWeb) {
        return expand ? SizedBox.expand(child: child) : child;
      }

      final uri = GoRouterState.of(context).uri.toString();
      final keyedChild = KeyedSubtree(
        key: ValueKey<String>('store_body_$uri'),
        child: expand ? SizedBox.expand(child: child) : child,
      );

      return AnimatedSwitcher(
        // Intentionally long and obvious for UX verification.
        duration: isSmallScreen
            ? const Duration(milliseconds: 700)
            : const Duration(milliseconds: 460),
        reverseDuration: isSmallScreen
            ? const Duration(milliseconds: 650)
            : const Duration(milliseconds: 420),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        layoutBuilder: (currentChild, previousChildren) {
          // Keep the top of pages aligned so the movement reads clearly.
          // Use StackFit.passthrough to ensure children get proper constraints.
          // This fixes blank screen issues on web where the Stack would have
          // zero height during transitions.
          return Stack(
            fit: StackFit.passthrough,
            alignment: Alignment.topCenter,
            children: <Widget>[
              ...previousChildren,
              if (currentChild != null) currentChild,
            ],
          );
        },
        transitionBuilder: (child, animation) {
          // More obvious on mobile: fade + slide + slight scale.
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          );

          final beginDy = isSmallScreen ? 0.06 : 0.035;
          final beginScale = isSmallScreen ? 0.97 : 0.985;

          return FadeTransition(
            opacity: curved,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: Offset(0, beginDy),
                end: Offset.zero,
              ).animate(curved),
              child: ScaleTransition(
                scale:
                    Tween<double>(begin: beginScale, end: 1.0).animate(curved),
                child: child,
              ),
            ),
          );
        },
        child: keyedChild,
      );
    }

    // Don't block rendering - just use defaults until settings load
    // This makes the site feel faster

    final storeName = websiteService.getSetting('store_name', 'VINABIKE');
    final storeDescription = websiteService.getSetting(
      'store_description',
      'Todo lo que necesitas para tu bicicleta en Viña del Mar',
    );
    final logoUrl = websiteService.getSetting('logo_url', '');
    final topBannerText = websiteService
        .getSetting('top_banner_text', 'Envíos a todo Chile')
        .trim();

    // Footer info - use provider for live preview when in editor context
    final contactEmail = (isInEditorContext
            ? editProvider.getEffectiveFooterSetting(
                'contact_email',
                websiteService.getSetting('contact_email', ''),
              )
            : websiteService.getSetting('contact_email', ''))
        .trim();
    final contactPhone = (isInEditorContext
            ? editProvider.getEffectiveFooterSetting(
                'contact_phone',
                websiteService.getSetting('contact_phone', ''),
              )
            : websiteService.getSetting('contact_phone', ''))
        .trim();
    final contactAddress = (isInEditorContext
            ? editProvider.getEffectiveFooterSetting(
                'contact_address',
                websiteService.getSetting('contact_address', ''),
              )
            : websiteService.getSetting('contact_address', ''))
        .trim();

    final facebookHandle = isInEditorContext
        ? editProvider.getEffectiveFooterSetting(
            'facebook',
            websiteService.getSetting(
                'facebook', websiteService.getSetting('facebook_handle', '')),
          )
        : websiteService.getSetting(
            'facebook', websiteService.getSetting('facebook_handle', ''));
    final instagramHandle = isInEditorContext
        ? editProvider.getEffectiveFooterSetting(
            'instagram',
            websiteService.getSetting(
                'instagram', websiteService.getSetting('instagram_handle', '')),
          )
        : websiteService.getSetting(
            'instagram', websiteService.getSetting('instagram_handle', ''));
    final twitterHandle = isInEditorContext
        ? editProvider.getEffectiveFooterSetting(
            'twitter',
            websiteService.getSetting(
                'twitter', websiteService.getSetting('twitter_handle', '')),
          )
        : websiteService.getSetting(
            'twitter', websiteService.getSetting('twitter_handle', ''));
    final youtubeHandle = isInEditorContext
        ? editProvider.getEffectiveFooterSetting(
            'youtube',
            websiteService.getSetting(
                'youtube',
                websiteService.getSetting(
                    'youtube_handle', '@vinabikechannel')),
          )
        : websiteService.getSetting('youtube',
            websiteService.getSetting('youtube_handle', '@vinabikechannel'));

    final whatsappRaw = isInEditorContext
        ? editProvider.getEffectiveFooterSetting(
            'whatsapp',
            websiteService.getSetting('whatsapp', ''),
          )
        : websiteService.getSetting('whatsapp', '');
    final whatsappNumber = _sanitizePhone(whatsappRaw);
    final hasWhatsApp = whatsappNumber.isNotEmpty;

    // Site publish flag (stored in website_settings)
    final sitePublished =
        websiteService.getSetting('site_published', 'true') == 'true';

    // While in editor context, keep the URL mode flag consistent with provider
    // state. This prevents stale query params (common with shell routes) from
    // lingering like ?preview=true while actually in edit mode.
    // NOTE: We guard against scheduling multiple navigations within the same
    // frame (common when provider notifies and triggers rebuild) to avoid
    // triggering "already marked needs layout" assertions.
    if (kIsWeb &&
        editProvider.isInEditorContext &&
        !_pendingModeNavigation &&
        !_pendingProviderModeSync) {
      final desiredModeKey = editProvider.isEditMode
          ? 'edit'
          : (editProvider.isPreviewMode ? 'preview' : null);

      final nextQp = Map<String, String>.from(currentUri.queryParameters);
      nextQp.remove('edit');
      nextQp.remove('preview');
      if (desiredModeKey != null) nextQp[desiredModeKey] = 'true';

      final currentQp = currentUri.queryParameters;
      final qpMatches = nextQp.length == currentQp.length &&
          nextQp.entries.every((e) => currentQp[e.key] == e.value);

      if (!qpMatches) {
        _pendingModeNavigation = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _pendingModeNavigation = false;
          if (!context.mounted) return;
          final nextUri = currentUri.replace(
            queryParameters: nextQp.isEmpty ? null : nextQp,
          );
          context.go(_routeForPublicStore(nextUri.toString()));
        });
      }
    }

    // Theme colors - use provider for live preview when in editor context
    final primaryColor = _resolveColor(
      isInEditorContext
          ? editProvider.getEffectiveThemeSetting('theme_primary_color',
              websiteService.getSetting('theme_primary_color', ''))
          : websiteService.getSetting('theme_primary_color', ''),
      PublicStoreTheme.primaryBlue,
    );
    final accentColor = _resolveColor(
      isInEditorContext
          ? editProvider.getEffectiveThemeSetting('theme_accent_color',
              websiteService.getSetting('theme_accent_color', ''))
          : websiteService.getSetting('theme_accent_color', ''),
      PublicStoreTheme.accentGreen,
    );
    final backgroundColor = _resolveColor(
      isInEditorContext
          ? editProvider.getEffectiveThemeSetting(
              'theme_background_color',
              websiteService.getSetting('theme_background_color', ''),
            )
          : websiteService.getSetting('theme_background_color', ''),
      Colors.white,
    );

    // Global typography (fonts + base sizes)
    final headingFont = isInEditorContext
        ? editProvider.getEffectiveThemeSetting(
            'theme_heading_font',
            websiteService.getSetting('theme_heading_font', ''),
          )
        : websiteService.getSetting('theme_heading_font', '');
    final bodyFont = isInEditorContext
        ? editProvider.getEffectiveThemeSetting(
            'theme_body_font',
            websiteService.getSetting('theme_body_font', ''),
          )
        : websiteService.getSetting('theme_body_font', '');

    final headingSize = double.tryParse(
      isInEditorContext
          ? editProvider.getEffectiveThemeSetting(
              'theme_heading_size',
              websiteService.getSetting('theme_heading_size', ''),
            )
          : websiteService.getSetting('theme_heading_size', ''),
    );
    final bodySize = double.tryParse(
      isInEditorContext
          ? editProvider.getEffectiveThemeSetting(
              'theme_body_size',
              websiteService.getSetting('theme_body_size', ''),
            )
          : websiteService.getSetting('theme_body_size', ''),
    );
    String getThemeSetting(String key, String fallback) {
      return isInEditorContext
          ? editProvider.getEffectiveThemeSetting(
              key,
              websiteService.getSetting(key, fallback),
            )
          : websiteService.getSetting(key, fallback);
    }

    final websiteTheme = WebsiteThemeBuilder.build(
      base: Theme.of(context),
      primaryColor: primaryColor,
      accentColor: accentColor,
      backgroundColor: backgroundColor,
      headingFont: headingFont,
      bodyFont: bodyFont,
      headingSize: headingSize,
      bodySize: bodySize,
      buttonStyle: getThemeSetting('button_style', 'rounded'),
      buttonSize: getThemeSetting('button_size', 'medium'),
    );

    // Header settings (DJI-style customization)
    // Header settings (DJI-style customization)
    // In edit mode, prefer pending settings for real-time preview
    String getHeaderSetting(String key, String def) {
      if (isInEditorContext) {
        return editProvider.pendingHeaderSettings[key] ??
            websiteService.getSetting(key, def);
      }
      return websiteService.getSetting(key, def);
    }

    final headerStyle = getHeaderSetting('header_style', 'solid');
    final headerColorMode = getHeaderSetting('header_color_mode', 'auto');
    final showTopBannerRaw =
        getHeaderSetting('header_show_top_banner', 'false');
    final showTopBanner = showTopBannerRaw == 'true';
    final headerShadow = getHeaderSetting('header_shadow', 'true') == 'true';
    final headerBgColor = _resolveColor(
      getHeaderSetting('header_bg_color', ''),
      Colors.white,
    );

    // Navigation (single source of truth): website_navigation table.
    // Public store loads it via WebsiteService.loadNavigationForTenant().
    final navItems =
        websiteService.headerNavigation.where((n) => n.isVisible).toList();

    // If the site is unpublished, show a holding page to visitors.
    // Allow bypass when entering via ?preview=true or ?edit=true, even before provider updates.
    final bypassUnpublished =
        isInEditorContext || qp['preview'] == 'true' || qp['edit'] == 'true';
    if (!sitePublished && !bypassUnpublished) {
      return Theme(
        data: websiteTheme,
        child: _buildUnpublishedSiteScaffold(context, storeName),
      );
    }

    // Build footer (reused in all layouts)
    final footerWidget = _buildFooter(
      context: context,
      storeName: storeName,
      storeDescription: storeDescription,
      contactEmail: contactEmail,
      contactPhone: contactPhone,
      contactAddress: contactAddress,
      facebookHandle: facebookHandle,
      instagramHandle: instagramHandle,
      twitterHandle: twitterHandle,
      youtubeHandle: youtubeHandle,
      whatsappHandle: whatsappRaw,
      primaryColor: primaryColor,
      accentColor: accentColor,
      isEditMode: isEditMode,
      logoUrl: logoUrl, // Pass logoUrl
    );

    // Build header widget builder for special layouts
    Widget buildHeaderWidget(
        {bool isOverlay = false,
        Color? overrideBgColor,
        String? overrideColorMode,
        bool? overrideShowBanner,
        bool? overrideShadow}) {
      return _buildHeader(
        context: context,
        storeName: storeName,
        storeDescription: storeDescription,
        logoUrl: logoUrl,
        topBannerText: topBannerText,
        contactPhone: contactPhone,
        contactEmail: contactEmail,
        primaryColor: primaryColor,
        accentColor: accentColor,
        isEditMode: isEditMode,
        headerStyle: headerStyle,
        headerColorMode: overrideColorMode ?? headerColorMode,
        showTopBanner: overrideShowBanner ?? showTopBanner,
        headerShadow: overrideShadow ?? headerShadow,
        headerBgColor: overrideBgColor ?? headerBgColor,
        navItems: navItems,
        isOverlay: isOverlay,
        // If we are in Preview Mode (Editor), the header is shifted down by the 48px Top Bar
        // We pass this offset to the Mega Menu so it can snap correctly.
        topOffset: (isPreviewMode || isEditMode) ? 48.0 : 0.0,
      );
    }

    // Build the main page content based on header style
    Widget pageContent;

    // Use the page route name first because the raw GoRouter state inside this
    // shared shell can resolve to the outer location and misclassify inner
    // pages like /checkout or /pedido/:id as the homepage.
    final currentRoute = _currentPublicStorePath(context);
    final isHomePage = _isHomePagePath(currentRoute);
    final allowsOverlayHeader = isHomePage;
    final usesInlineHeaderLayout =
        widget.enablePageViewScrolling && _usesInlineHeaderLayout(currentRoute);

    // Mode-aware key ensures complete widget recreation on mode change to
    // avoid element reactivation crashes during layout.
    final scrollViewMode =
        isEditMode ? 'edit' : (isPreviewMode ? 'preview' : 'normal');

    if (headerStyle == 'transparent' &&
        allowsOverlayHeader &&
        widget.enablePageViewScrolling) {
      // TRANSPARENT: Header floats over hero ONLY ON HOMEPAGE
      pageContent = ScrollConfiguration(
        behavior: isEditMode
            ? const _NoDragScrollBehavior()
            : const MaterialScrollBehavior(),
        child: _PublicStoreScrollView(
          key: ValueKey('scroll_transparent_home_$scrollViewMode'),
          // On Web, clip layers can end up painting above later Stack children
          // (like the header) due to DOM stacking context quirks.
          clipBehavior:
              (_isCapturingScreenshot || kIsWeb) ? Clip.none : Clip.hardEdge,
          physics: _isCapturingScreenshot
              ? const NeverScrollableScrollPhysics()
              : null,
          child: RepaintBoundary(
            key: editProvider.screenshotKey,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // Content starts from top (behind header)
                Column(
                  children: [
                    animateBody(widget.child),
                    footerWidget,
                  ],
                ),
                // Header floats on top (positioned at top, scrolls with content)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: buildHeaderWidget(
                    isOverlay: true,
                    overrideBgColor: Colors.transparent,
                    overrideColorMode:
                        headerColorMode, // Use configured color mode (dark = white text)
                    overrideShadow: false,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    } else if (headerStyle == 'transparent' &&
        !isHomePage &&
        widget.enablePageViewScrolling) {
      // TRANSPARENT style but NOT homepage: Use solid header instead
      pageContent = usesInlineHeaderLayout
          ? ScrollConfiguration(
              behavior: isEditMode
                  ? const _NoDragScrollBehavior()
                  : const MaterialScrollBehavior(),
              child: _PublicStoreScrollView(
                key: ValueKey('scroll_transparent_inline_$scrollViewMode'),
                child: Column(
                  children: [
                    buildHeaderWidget(
                      isOverlay: false,
                      overrideBgColor: headerBgColor,
                      overrideColorMode: headerColorMode,
                      overrideShowBanner: false,
                      overrideShadow: headerShadow,
                    ),
                    animateBody(widget.child),
                    footerWidget,
                  ],
                ),
              ),
            )
          : Column(
              children: [
                // Header - static at top with solid background
                buildHeaderWidget(
                  isOverlay: false,
                  overrideBgColor: headerBgColor,
                  overrideColorMode: headerColorMode,
                  overrideShadow: headerShadow,
                ),
                // Main content area - scrollable
                Expanded(
                  child: ScrollConfiguration(
                    behavior: isEditMode
                        ? const _NoDragScrollBehavior()
                        : const MaterialScrollBehavior(),
                    child: _PublicStoreScrollView(
                      key: ValueKey(
                          'scroll_transparent_notHome_$scrollViewMode'),
                      child: Column(
                        children: [
                          animateBody(widget.child),
                          footerWidget,
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            );
    } else if (headerStyle == 'sticky' &&
        (widget.enablePageViewScrolling || isPreviewMode || isEditMode)) {
      // STICKY: Homepage may overlay the hero; inner routes reserve header
      // height so the fixed header stays visible without covering content.
      final stickyAllowsOverlay = allowsOverlayHeader;
      pageContent = _buildStickyHeaderLayout(
        context: context,
        storeName: storeName,
        storeDescription: storeDescription,
        logoUrl: logoUrl,
        topBannerText: topBannerText,
        contactPhone: contactPhone,
        contactEmail: contactEmail,
        primaryColor: primaryColor,
        accentColor: accentColor,
        headerColorMode: headerColorMode,
        showTopBanner: stickyAllowsOverlay ? showTopBanner : false,
        headerShadow: headerShadow,
        headerBgColor: headerBgColor,
        navItems: navItems,
        isEditMode: isEditMode,
        child: animateBody(widget.child),
        footer: footerWidget,
        allowOverlayAtTop: stickyAllowsOverlay,
        scrollViewMode: scrollViewMode,
      );
    } else {
      // SOLID: Normal layout, header at top, content scrolls below
      pageContent = usesInlineHeaderLayout
          ? ScrollConfiguration(
              behavior: isEditMode
                  ? const _NoDragScrollBehavior()
                  : const MaterialScrollBehavior(),
              child: _PublicStoreScrollView(
                key: ValueKey('scroll_solid_inline_$scrollViewMode'),
                child: Column(
                  children: [
                    buildHeaderWidget(overrideShowBanner: false),
                    animateBody(widget.child),
                    footerWidget,
                  ],
                ),
              ),
            )
          : Column(
              children: [
                // Header - static at top
                buildHeaderWidget(),
                // Main content area - scrollable or fixed
                Expanded(
                  child: widget.enablePageViewScrolling
                      ? ScrollConfiguration(
                          behavior: isEditMode
                              ? const _NoDragScrollBehavior()
                              : const MaterialScrollBehavior(),
                          child: _PublicStoreScrollView(
                            key: ValueKey('scroll_solid_$scrollViewMode'),
                            child: Column(
                              children: [
                                animateBody(widget.child),
                                footerWidget,
                              ],
                            ),
                          ),
                        )
                      : Column(
                          children: [
                            Expanded(
                                child: animateBody(widget.child, expand: true)),
                            // In fixed mode, footer is not shown or is part of child.
                            // Let's hide footer for fixed layout to gain max space.
                          ],
                        ),
                ),
              ],
            );
    }

    // ========================================================================
    // SEO BACKGROUND UPDATE
    // ========================================================================
    // Automatically update browser title and meta tags based on current page
    if (kIsWeb && !isEditMode) {
      final currentPath = GoRouterState.of(context).uri.path;

      // Product pages manage their own SEO once the product loads.
      if (currentPath.startsWith('/producto/') ||
          currentPath.startsWith('/productos/') ||
          currentPath.startsWith('/shop/')) {
        // Skip the generic page SEO updater to avoid overwriting product SEO.
      } else {
        String normalizedSlug = GoRouterState.of(context).uri.path;
        if (normalizedSlug.startsWith('/tienda/')) {
          normalizedSlug = normalizedSlug.substring(8);
        } else if (normalizedSlug.startsWith('/tienda')) {
          normalizedSlug = 'home';
        }
        if (normalizedSlug.startsWith('/')) {
          normalizedSlug = normalizedSlug.substring(1);
        }
        if (normalizedSlug.isEmpty) normalizedSlug = 'home';

        // Handle legacy route specific cases
        if (GoRouterState.of(context).uri.path == '/') normalizedSlug = 'home';

        WebsitePage? currentPage;
        try {
          // Try to find matching page
          if (websiteService.pages.isNotEmpty) {
            currentPage = websiteService.pages.firstWhere(
              (p) =>
                  p.slug == normalizedSlug ||
                  (p.isHome && normalizedSlug == 'home'),
              orElse: () => websiteService.pages.firstWhere((p) => p.isHome,
                  orElse: () => websiteService.pages.first),
            );
          }
        } catch (_) {
          // Page not found or list empty
        }

        String seoTitle = storeName;
        String? seoDesc = storeDescription;
        String? seoImage = logoUrl;

        if (currentPage != null) {
          // Only use page-specific SEO if we matched the correct page
          bool isCorrectPage = currentPage.slug == normalizedSlug ||
              (currentPage.isHome && normalizedSlug == 'home');

          if (isCorrectPage) {
            if (currentPage.metaTitle?.isNotEmpty == true) {
              seoTitle = currentPage.metaTitle!;
            } else if (currentPage.title.isNotEmpty) {
              seoTitle = '${currentPage.title} | $storeName';
            }

            if (currentPage.metaDescription?.isNotEmpty == true) {
              seoDesc = currentPage.metaDescription;
            }

            if (currentPage.ogImageUrl?.isNotEmpty == true) {
              seoImage = currentPage.ogImageUrl;
            }
          }
        }

        // Defer SEO update to avoid build-phase conflicts
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            SeoHelper.updateSeo(
              title: seoTitle,
              description: seoDesc,
              imageUrl: seoImage,
            );
          }
        });
      }
    }

    // When the editor panel is rendered externally (PersistentEditorShell),
    // reserve horizontal space so the website (including header) is never
    // hidden behind the panel. Keep the top command bar full-width.
    // NOTE: Only apply this padding in DESKTOP preview mode. In mobile/tablet
    // preview, the content is already inside a constrained frame.
    if (isEditMode &&
        widget.useExternalEditorPanel &&
        devicePreviewMode == DevicePreviewMode.desktop) {
      pageContent = Padding(
        padding: const EdgeInsets.only(right: _externalEditorPanelWidth),
        child: pageContent,
      );
    }

    // In full edit mode, use Row layout with side panel
    if (isEditMode) {
      final editorViewport = _buildEditorViewport(
          context, pageContent, devicePreviewMode,
          isEditMode: true);

      final shouldReserveRightSpaceForExternalPanel =
          widget.useExternalEditorPanel &&
              devicePreviewMode == DevicePreviewMode.desktop &&
              !_isConfigHubOpen;

      Widget overlayLayer = _buildConfigHubOverlay();
      if (shouldReserveRightSpaceForExternalPanel) {
        overlayLayer = Padding(
          padding: const EdgeInsets.only(right: _externalEditorPanelWidth),
          child: overlayLayer,
        );
      }

      final Widget mainBody;
      if (widget.useExternalEditorPanel) {
        // Editor panel is rendered externally by PersistentEditorShell.
        // Overlay can cover the full viewport, but must avoid the reserved panel width.
        mainBody = Stack(
          children: [
            Positioned.fill(child: editorViewport),
            if (_isConfigHubOpen)
              Positioned.fill(
                child: overlayLayer,
              ),
          ],
        );
      } else {
        // Legacy: render editor panel inline. Ensure overlay only covers the viewport
        // (left) and never sits behind the right editor panel.
        mainBody = Row(
          children: [
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(child: editorViewport),
                  if (_isConfigHubOpen)
                    Positioned.fill(
                      child: overlayLayer,
                    ),
                ],
              ),
            ),
            if (!_isConfigHubOpen)
              DeferredWebsiteEditorPanel(
                onSave: () async {
                  await _saveChanges(context, editProvider, websiteService);
                  if (context.mounted) {
                    editProvider.switchToPreviewMode();
                  }
                },
                onRestoreComplete: () => _reloadEditorAfterBackupRestore(
                  context,
                  editProvider,
                  websiteService,
                ),
                onDiscard: () {
                  editProvider.discardPendingChanges();
                  editProvider.switchToPreviewMode();
                },
              ),
          ],
        );
      }

      return Theme(
        data: websiteTheme,
        child: Scaffold(
          key: const ValueKey('scaffold_edit_mode'),
          backgroundColor: backgroundColor,
          body: Stack(
            children: [
              // Main Body (underneath, with padding for top bar)
              Positioned.fill(
                top: 48,
                child: mainBody,
              ),
              // Top Bar (on top)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: 48,
                child: _buildPreviewTopBar(
                    context, editProvider, websiteService, storeName),
              ),
            ],
          ),
        ),
      );
    }

    // In preview mode, show top bar with "Editar" button
    if (isPreviewMode) {
      final editorViewport = _buildEditorViewport(
          context, pageContent, devicePreviewMode,
          isEditMode: false);
      return Theme(
        data: websiteTheme,
        child: Scaffold(
          key: const ValueKey('scaffold_preview_mode'),
          backgroundColor: backgroundColor,
          body: Stack(
            children: [
              // Page content (underneath, with padding)
              Positioned.fill(
                top: 48,
                child: Stack(
                  children: [
                    Positioned.fill(child: editorViewport),
                    if (_isConfigHubOpen)
                      Positioned.fill(
                        child: _buildConfigHubOverlay(),
                      ),
                  ],
                ),
              ),
              // Top Bar (on top)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: 48,
                child: _buildPreviewTopBar(
                    context, editProvider, websiteService, storeName),
              ),
            ],
          ),
        ),
      );
    }

    // Build the main content (normal view mode)
    final mainContent = Scaffold(
      key: const ValueKey('scaffold_normal_mode'),
      backgroundColor: backgroundColor,
      body: Stack(
        children: [
          Positioned.fill(child: pageContent),
          // Internal Chat System (replaces WhatsApp for richer interaction)
          const CustomerChatWidget(),
          if (hasWhatsApp &&
              1 ==
                  0) // Disable WhatsApp button in favor of new chat (or make it configurable)
            Positioned(
              bottom: 24,
              right: 24,
              child: FloatingWhatsAppButton(
                phoneNumber: whatsappNumber,
                message:
                    'Hola! Me gustaría consultar sobre ${storeName.isNotEmpty ? storeName : 'sus productos'}.',
                backgroundColor: accentColor,
              ),
            ),
          // Show the legacy "Edit Site" FAB only when the store is mounted
          // inside the ERP shell. Standalone store debug on localhost should
          // behave like the public storefront and never expose this old entry.
          if (isLoggedIn && widget.showEditorButton && _isErpMountedStore())
            Positioned(
              bottom: 24,
              right: hasWhatsApp ? 104 : 24,
              child: Builder(
                builder: (context) {
                  final editProvider = context.watch<WebsiteEditModeProvider>();
                  final isInEditorContext = editProvider.isInEditorContext;
                  final websiteService = context.read<WebsiteService>();

                  if (isInEditorContext) return const SizedBox.shrink();

                  return FloatingActionButton.extended(
                    heroTag: 'edit_site_fab',
                    onPressed: () {
                      debugPrint(
                          '🎨 [Layout] Edit button pressed. Entering preview mode');
                      final blocks = List<Map<String, dynamic>>.from(
                          websiteService.blocks);
                      final settings =
                          Map<String, dynamic>.from(websiteService.settings);
                      debugPrint(
                          '🎨 [Layout] Entering preview mode with ${blocks.length} blocks');
                      editProvider.enterPreviewMode(blocks, settings);
                    },
                    backgroundColor: accentColor,
                    icon: const Icon(Icons.edit, color: Colors.white),
                    label: const Text(
                      'Editar Sitio',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    tooltip: 'Editar sitio web',
                  );
                },
              ),
            ),
        ],
      ),
    );

    return WebsiteWorkspaceScope(
      onOpen: _openWorkspacePanel,
      child: Theme(
        data: websiteTheme,
        child: mainContent,
      ),
    );
  }

  /// Build the preview top bar (Odoo-style) with "Editar" button
  Widget _buildPreviewTopBar(
    BuildContext context,
    WebsiteEditModeProvider editProvider,
    WebsiteService websiteService,
    String storeName,
  ) {
    final isEditMode = editProvider.isEditMode;
    final sitePublished =
        websiteService.getSetting('site_published', 'true') == 'true';
    return Container(
      height: 48,
      color: const Color(0xFF1E1E1E),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          // Logo/brand
          Row(
            children: [
              Icon(Icons.language,
                  color: Colors.white.withValues(alpha: 0.8), size: 20),
              const SizedBox(width: 8),
              Text(
                'Sitio web',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.8),
                  fontWeight: FontWeight.w500,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          const SizedBox(width: 24),
          // Task-oriented workspace navigation. Management screens replace the
          // canvas instead of competing with the block inspector.
          _buildPreviewWorkspaceButton(
            context: context,
            editProvider: editProvider,
            websiteService: websiteService,
            label: 'Editar página',
            icon: Icons.edit_outlined,
            actionId: _actionPageEditorWorkspace,
            isActive:
                editProvider.workspaceMode == WebsiteWorkspaceMode.pageEditor,
          ),
          _buildPreviewWorkspaceButton(
            context: context,
            editProvider: editProvider,
            websiteService: websiteService,
            label: 'Catálogo web',
            icon: Icons.storefront_outlined,
            actionId: _actionEcomCatalog,
            isActive:
                editProvider.workspaceMode == WebsiteWorkspaceMode.catalog,
          ),
          _buildPreviewNavMenu(
            context: context,
            editProvider: editProvider,
            websiteService: websiteService,
            label: 'Estructura',
            isActive:
                editProvider.workspaceMode == WebsiteWorkspaceMode.structure,
            actions: const [
              _PreviewNavAction(
                id: _actionSitePages,
                label: 'Páginas',
                icon: Icons.description_outlined,
              ),
              _PreviewNavAction(
                id: _actionSiteNavigation,
                label: 'Navegación y menús',
                icon: Icons.menu,
              ),
              _PreviewNavAction(
                id: _actionSiteDestinations,
                label: 'Destinos y enlaces',
                icon: Icons.account_tree_outlined,
              ),
            ],
          ),
          _buildPreviewNavMenu(
            context: context,
            editProvider: editProvider,
            websiteService: websiteService,
            label: 'Ajustes',
            isActive:
                editProvider.workspaceMode == WebsiteWorkspaceMode.settings,
            actions: const [
              _PreviewNavAction(
                id: _actionSiteSettings,
                label: 'Sitio, tema y contacto',
                icon: Icons.tune,
              ),
              _PreviewNavAction(
                id: _actionConfigWebsiteSettings,
                label: 'SEO',
                icon: Icons.manage_search_outlined,
              ),
              _PreviewNavAction(
                id: _actionConfigIntegrations,
                label: 'Integraciones',
                icon: Icons.extension_outlined,
              ),
              _PreviewNavAction(
                id: _actionConfigDomain,
                label: 'Dominio y URL',
                icon: Icons.link_outlined,
              ),
              _PreviewNavAction(
                id: _actionConfigPaymentMethods,
                label: 'Métodos de pago',
                icon: Icons.payments_outlined,
              ),
            ],
          ),
          _buildPreviewNavMenu(
            context: context,
            editProvider: editProvider,
            websiteService: websiteService,
            label: 'Más',
            isActive:
                editProvider.workspaceMode == WebsiteWorkspaceMode.operations,
            actions: const [
              _PreviewNavAction(
                id: _actionEcomOrders,
                label: 'Pedidos online',
                icon: Icons.shopping_bag_outlined,
              ),
              _PreviewNavAction(
                id: _actionReportsAnalytics,
                label: 'Analytics',
                icon: Icons.analytics_outlined,
              ),
              _PreviewNavAction(
                id: _actionSiteOpenWebsiteHub,
                label: 'Centro del Sitio Web',
                icon: Icons.dashboard_outlined,
              ),
              _PreviewNavAction.divider(),
              _PreviewNavAction(
                id: _actionGoogleOpenMerchantFeed,
                label: 'Abrir feed de productos',
                icon: Icons.feed_outlined,
              ),
              _PreviewNavAction(
                id: _actionGoogleCopyMerchantFeed,
                label: 'Copiar feed de productos',
                icon: Icons.copy,
              ),
            ],
          ),

          // Current page actions (copy link, open)
          _buildCurrentPageMenu(
            context: context,
            editProvider: editProvider,
            websiteService: websiteService,
          ),

          const Spacer(),

          // Store name dropdown
          _buildStoreMenu(
            context: context,
            editProvider: editProvider,
            websiteService: websiteService,
            storeName: storeName,
          ),
          const SizedBox(width: 16),

          // Published toggle
          Row(
            children: [
              Text(
                'Publicado',
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.8), fontSize: 13),
              ),
              const SizedBox(width: 8),
              Switch(
                value: sitePublished,
                onChanged: (v) async {
                  final next = v ? 'true' : 'false';
                  await websiteService.saveSetting('site_published', next);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          v ? 'Sitio publicado' : 'Sitio despublicado',
                        ),
                      ),
                    );
                  }
                },
                activeThumbColor: Colors.green,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ],
          ),
          const SizedBox(width: 16),

          if (editProvider.isPageEditorWorkspace) ...[
            // Device preview belongs to page composition, not management.
            PopupMenuButton<DevicePreviewMode>(
              tooltip: 'Vista (dispositivo)',
              initialValue: editProvider.devicePreviewMode,
              onSelected: (mode) => editProvider.setDevicePreviewMode(mode),
              itemBuilder: (context) => const [
                PopupMenuItem(
                  value: DevicePreviewMode.desktop,
                  child: ListTile(
                    dense: true,
                    leading: Icon(Icons.desktop_windows_outlined),
                    title: Text('Desktop'),
                  ),
                ),
                PopupMenuItem(
                  value: DevicePreviewMode.tablet,
                  child: ListTile(
                    dense: true,
                    leading: Icon(Icons.tablet_mac_outlined),
                    title: Text('Tablet'),
                  ),
                ),
                PopupMenuItem(
                  value: DevicePreviewMode.mobile,
                  child: ListTile(
                    dense: true,
                    leading: Icon(Icons.phone_android_outlined),
                    title: Text('Móvil'),
                  ),
                ),
              ],
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Icon(
                  editProvider.devicePreviewMode == DevicePreviewMode.desktop
                      ? Icons.desktop_windows
                      : editProvider.devicePreviewMode ==
                              DevicePreviewMode.tablet
                          ? Icons.tablet_mac
                          : Icons.phone_android,
                  color: Colors.white70,
                  size: 20,
                ),
              ),
            ),
            const SizedBox(width: 4),

            // Screenshot button
            IconButton(
              onPressed: _isCapturingScreenshot
                  ? null
                  : () => _captureFullPageScreenshot(context, editProvider),
              icon: _isCapturingScreenshot
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white70,
                      ),
                    )
                  : const Icon(Icons.camera_alt_outlined,
                      color: Colors.white70, size: 20),
              tooltip: 'Capturar página',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            ),
            const SizedBox(width: 8),

            // New page button
            TextButton(
              onPressed: () => _showQuickCreatePageDialog(context),
              style: TextButton.styleFrom(
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              child: const Text('Nuevo', style: TextStyle(fontSize: 13)),
            ),
            const SizedBox(width: 8),

            // Main mode button (Preview -> Edit, Edit -> Preview)
            ElevatedButton(
              onPressed: () {
                // IMPORTANT: Mode is controlled by BOTH provider state and URL query params.
                // If we only flip provider state while the URL still has ?edit=true,
                // the page will immediately force edit mode again (bounce).
                final state = GoRouterState.of(context);
                final currentUri = state.uri;

                final qp = Map<String, String>.from(currentUri.queryParameters);
                qp.remove('edit');
                qp.remove('preview');

                if (isEditMode) {
                  // Go to preview mode (remove edit=true)
                  qp['preview'] = 'true';
                  editProvider.switchToPreviewMode();
                } else {
                  // Go to edit mode (remove preview=true)
                  qp['edit'] = 'true';
                  editProvider.switchToEditMode();
                }

                final nextUri = Uri(
                  path: currentUri.path,
                  queryParameters: qp.isEmpty ? null : qp,
                );
                context.go(_routeForPublicStore(nextUri.toString()));
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red.shade600,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(4)),
              ),
              child: Text(
                isEditMode ? 'Vista previa' : 'Editar',
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
            ),
            const SizedBox(width: 8),
          ],

          // Close/exit button - go back to Website Management
          IconButton(
            onPressed: () {
              editProvider.exitEditMode();
              context.go(
                _isErpMountedStore()
                    ? '/website'
                    : _routeForPublicStore('/tienda'),
              );
            },
            icon: const Icon(Icons.close, color: Colors.white70, size: 20),
            tooltip: 'Volver a Gestión de Sitio Web',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          ),
        ],
      ),
    );
  }

  Widget _buildStoreMenu({
    required BuildContext context,
    required WebsiteEditModeProvider editProvider,
    required WebsiteService websiteService,
    required String storeName,
  }) {
    final label = storeName.isNotEmpty ? storeName : 'Mi Tienda';
    return PopupMenuButton<String>(
      tooltip: 'Acciones de tienda',
      onSelected: (action) => _handleTopBarAction(
        context: context,
        editProvider: editProvider,
        websiteService: websiteService,
        actionId: action,
      ),
      itemBuilder: (context) => const [
        PopupMenuItem(
          value: _actionStoreOpenPublic,
          child: ListTile(
            dense: true,
            leading: Icon(Icons.open_in_new),
            title: Text('Abrir tienda pública'),
          ),
        ),
        PopupMenuItem(
          value: _actionStoreCopyUrl,
          child: ListTile(
            dense: true,
            leading: Icon(Icons.copy),
            title: Text('Copiar URL'),
          ),
        ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.white24),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.arrow_drop_down, color: Colors.white, size: 18),
          ],
        ),
      ),
    );
  }

  Widget _buildPreviewWorkspaceButton({
    required BuildContext context,
    required WebsiteEditModeProvider editProvider,
    required WebsiteService websiteService,
    required String label,
    required IconData icon,
    required String actionId,
    required bool isActive,
  }) {
    return Tooltip(
      message: label,
      child: InkWell(
        borderRadius: BorderRadius.circular(4),
        onTap: () => _handleTopBarAction(
          context: context,
          editProvider: editProvider,
          websiteService: websiteService,
          actionId: actionId,
        ),
        child: Container(
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: isActive ? Colors.white.withValues(alpha: 0.1) : null,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 16,
                color: isActive
                    ? Colors.white
                    : Colors.white.withValues(alpha: 0.6),
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: isActive
                      ? Colors.white
                      : Colors.white.withValues(alpha: 0.6),
                  fontSize: 13,
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPreviewNavMenu({
    required BuildContext context,
    required WebsiteEditModeProvider editProvider,
    required WebsiteService websiteService,
    required String label,
    required bool isActive,
    required List<_PreviewNavAction> actions,
  }) {
    final entries = <PopupMenuEntry<String>>[];
    for (final a in actions) {
      if (a.isDivider) {
        entries.add(const PopupMenuDivider());
        continue;
      }
      entries.add(
        PopupMenuItem<String>(
          value: a.id!,
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(a.icon,
                color: Colors.white.withValues(alpha: 0.9), size: 20),
            title: Text(
              a.label!,
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.9), fontSize: 13),
            ),
          ),
        ),
      );
    }

    return PopupMenuButton<String>(
      tooltip: label,
      offset: const Offset(0, 38),
      color: const Color(0xFF252525),
      surfaceTintColor: Colors.transparent,
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      onSelected: (action) => _handleTopBarAction(
        context: context,
        editProvider: editProvider,
        websiteService: websiteService,
        actionId: action,
      ),
      itemBuilder: (context) => entries,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            Text(
              label,
              style: TextStyle(
                color: isActive
                    ? Colors.white
                    : Colors.white.withValues(alpha: 0.6),
                fontSize: 13,
                fontWeight: isActive ? FontWeight.w500 : FontWeight.normal,
              ),
            ),
            const SizedBox(width: 2),
            Icon(
              Icons.arrow_drop_down,
              size: 18,
              color:
                  isActive ? Colors.white : Colors.white.withValues(alpha: 0.6),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCurrentPageMenu({
    required BuildContext context,
    required WebsiteEditModeProvider editProvider,
    required WebsiteService websiteService,
  }) {
    final title = _currentPageTitle(context, editProvider);

    return InkWell(
      onTap: () => _showPageNavigator(
        context: context,
        editProvider: editProvider,
        websiteService: websiteService,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            Icon(
              Icons.article_outlined,
              size: 18,
              color: Colors.white.withValues(alpha: 0.8),
            ),
            const SizedBox(width: 6),
            Text(
              title,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.8),
                fontSize: 13,
              ),
            ),
            const SizedBox(width: 2),
            Icon(
              Icons.arrow_drop_down,
              size: 18,
              color: Colors.white.withValues(alpha: 0.8),
            ),
          ],
        ),
      ),
    );
  }

  String _currentPageTitle(
    BuildContext context,
    WebsiteEditModeProvider editProvider,
  ) {
    final slug = _getCurrentSlugFromRoute(context, editProvider);
    if (slug.isEmpty) return 'Página: Inicio';
    return 'Página: ${_displayPathForSlug(slug)}';
  }

  /// Detect the current page slug from the actual URL, falling back to
  /// editProvider.currentPageSlug for CMS pages.
  String _getCurrentSlugFromRoute(
    BuildContext context,
    WebsiteEditModeProvider editProvider,
  ) {
    try {
      final uri = GoRouterState.of(context).uri;
      final path = uri.path;

      // Remove /tienda prefix if present (ERP host)
      var cleanPath = path;
      if (cleanPath.startsWith('/tienda')) {
        cleanPath = cleanPath.substring('/tienda'.length);
      }
      if (cleanPath.isEmpty || cleanPath == '/') {
        return ''; // Home page
      }

      // Ensure it starts with /
      if (!cleanPath.startsWith('/')) cleanPath = '/$cleanPath';

      // Known canonical routes
      const canonicalRoutes = <String, String>{
        '/productos': 'productos',
        '/contacto': 'contacto',
        '/carrito': 'carrito',
        '/checkout': 'checkout',
        '/cuenta': 'cuenta',
      };
      if (canonicalRoutes.containsKey(cleanPath)) {
        return canonicalRoutes[cleanPath]!;
      }

      // Policy pages at root level
      const policySlugs = {
        'nosotros',
        'terminos',
        'privacidad',
        'devoluciones',
        'envios'
      };
      final rootSlug = cleanPath.substring(1); // Remove leading /
      if (policySlugs.contains(rootSlug)) {
        return rootSlug;
      }

      // /pagina/<slug> pattern
      if (cleanPath.startsWith('/pagina/')) {
        return cleanPath.substring('/pagina/'.length);
      }

      // If it's a simple slug (e.g. /servicios), use it
      if (!rootSlug.contains('/')) {
        return rootSlug;
      }

      // Fallback to provider
      return (editProvider.currentPageSlug ?? '').trim();
    } catch (_) {
      return (editProvider.currentPageSlug ?? '').trim();
    }
  }

  Future<void> _showPageNavigator({
    required BuildContext context,
    required WebsiteEditModeProvider editProvider,
    required WebsiteService websiteService,
  }) async {
    final navContext = context;

    // Ensure pages are available (public store can run unauthenticated).
    final tenantProvider = navContext.read<PublicStoreTenantProvider>();
    final tenantId = tenantProvider.tenantId;
    if (websiteService.pages.isEmpty && tenantId != null) {
      await websiteService.loadPagesForTenant(tenantId);
    }

    if (!navContext.mounted) return;

    final canNavigate = await _confirmNavigateAwayIfUnsaved(
      navContext,
      editProvider,
    );
    if (!canNavigate) return;
    if (!navContext.mounted) return;

    final initialSlug = _getCurrentSlugFromRoute(navContext, editProvider);
    final pages = List<WebsitePage>.from(websiteService.pages);

    // Build targets (include a few canonical routes even if pages table is
    // missing them).
    final targets = _buildPageNavigatorTargets(pages);

    final selected = await showDialog<_PageNavTarget>(
      context: navContext,
      builder: (dialogContext) {
        final size = MediaQuery.sizeOf(dialogContext);
        final isCompact = size.width < 720;

        return Dialog(
          backgroundColor: const Color(0xFF1E1E1E), // Match editor theme
          insetPadding: EdgeInsets.symmetric(
            horizontal: isCompact ? 8 : 24,
            vertical: isCompact ? 16 : 24,
          ),
          clipBehavior: Clip.antiAlias,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 760,
              maxHeight: isCompact ? size.height - 32 : 680,
              minHeight: 420,
            ),
            child: _PageNavigatorDialog(
              initialSlug: initialSlug,
              targets: targets,
              onCopyLink: () => _copyCurrentPageUrl(
                dialogContext,
                editProvider,
                websiteService,
              ),
              onOpenNewTab: () => _openCurrentPageUrl(
                dialogContext,
                editProvider,
                websiteService,
              ),
            ),
          ),
        );
      },
    );

    if (selected == null) return;
    if (!navContext.mounted) return;

    // The page navigator already provides normalized hrefs. Use direct
    // navigation instead of _navigateToHref to avoid UUID resolution loops.
    final href = selected.href;

    // Append edit=true since we're in editor context.
    final hasQuery = href.contains('?');
    final target = hasQuery ? '$href&edit=true' : '$href?edit=true';

    // Use go() to replace current route (avoids stacking editor pages).
    navContext.go(target);
  }

  Future<bool> _confirmNavigateAwayIfUnsaved(
    BuildContext context,
    WebsiteEditModeProvider editProvider,
  ) async {
    if (!editProvider.isEditMode) return true;
    if (!editProvider.hasUnsavedChanges) return true;

    final res = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Cambiar de página'),
          content: const Text(
            'Tienes cambios sin guardar. Si cambias de página ahora, podrías perderlos.\n\n¿Quieres continuar?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Continuar'),
            ),
          ],
        );
      },
    );
    return res ?? false;
  }

  List<_PageNavTarget> _buildPageNavigatorTargets(List<WebsitePage> pages) {
    // Some routes are not always present as CMS rows but are still useful to
    // navigate while in edit mode.
    const canonical = <_PageNavTarget>[
      _PageNavTarget(
        key: 'home',
        title: 'Inicio',
        href: '/tienda',
        kind: _PageNavKind.core,
      ),
      _PageNavTarget(
        key: 'productos',
        title: 'Productos',
        href: '/tienda/productos',
        kind: _PageNavKind.core,
      ),
      _PageNavTarget(
        key: 'servicios',
        title: 'Servicios',
        href: '/tienda/servicios',
        kind: _PageNavKind.core,
      ),
      _PageNavTarget(
        key: 'contacto',
        title: 'Contacto',
        href: '/tienda/contacto',
        kind: _PageNavKind.core,
      ),
      _PageNavTarget(
        key: 'carrito',
        title: 'Carrito',
        href: '/tienda/carrito',
        kind: _PageNavKind.system,
      ),
      _PageNavTarget(
        key: 'checkout',
        title: 'Checkout',
        href: '/tienda/checkout',
        kind: _PageNavKind.system,
      ),
      _PageNavTarget(
        key: 'cuenta',
        title: 'Cuenta',
        href: '/tienda/cuenta',
        kind: _PageNavKind.system,
      ),
    ];

    const policySlugs = <String>{
      'nosotros',
      'terminos',
      'privacidad',
      'devoluciones',
      'envios',
    };

    final byKey = <String, _PageNavTarget>{
      for (final t in canonical) t.key: t,
    };

    for (final p in pages) {
      final slug = p.slug.trim();
      if (slug.isEmpty) continue;

      final isPolicy = policySlugs.contains(slug);
      final isHome = p.isHome || slug == 'inicio' || slug == 'home';

      final kind = isHome
          ? _PageNavKind.core
          : isPolicy
              ? _PageNavKind.legal
              : p.isSystem
                  ? _PageNavKind.system
                  : (p.isPublished
                      ? _PageNavKind.published
                      : _PageNavKind.draft);

      final legacyHref = isHome
          ? '/tienda'
          : isPolicy
              ? '/$slug'
              : _isDirectSlug(slug)
                  ? '/tienda/$slug'
                  : '/tienda/pagina/$slug';

      final key = isHome ? 'home' : slug;
      byKey[key] = _PageNavTarget(
        key: key,
        title: p.title.isNotEmpty ? p.title : slug,
        href: legacyHref,
        kind: kind,
        subtitle: _displayPathForSlug(isHome ? '' : slug),
        isPublished: p.isPublished,
      );
    }

    final targets = byKey.values.toList();
    targets.sort((a, b) {
      final kindCmp = a.kind.index.compareTo(b.kind.index);
      if (kindCmp != 0) return kindCmp;
      return a.title.toLowerCase().compareTo(b.title.toLowerCase());
    });

    // Normalize hrefs to current host conventions.
    return targets
        .map(
          (t) => t.copyWith(href: _routeForPublicStore(t.href)),
        )
        .toList();
  }

  bool _isDirectSlug(String slug) {
    // Slugs that map to clean top-level routes (not /pagina/*).
    const direct = <String>{
      'productos',
      'servicios',
      'contacto',
      'carrito',
      'checkout',
      'cuenta',
    };
    return direct.contains(slug);
  }

  String _displayPathForSlug(String slug) {
    if (slug.isEmpty) return '/';
    if (_isDirectSlug(slug)) return '/$slug';
    const policySlugs = <String>{
      'nosotros',
      'terminos',
      'privacidad',
      'devoluciones',
      'envios',
    };
    if (policySlugs.contains(slug)) return '/$slug';
    return '/pagina/$slug';
  }

  Future<void> _handleTopBarAction({
    required BuildContext context,
    required WebsiteEditModeProvider editProvider,
    required WebsiteService websiteService,
    required String actionId,
  }) async {
    // For actions that go back into ERP pages, ensure we exit editor mode cleanly.
    void goAdmin(String path) {
      editProvider.exitEditMode();
      context.go(path);
    }

    switch (actionId) {
      case _actionPageEditorWorkspace:
        _closeConfigHub();
        return;
      case _actionEcomCatalog:
        if (editProvider.isInEditorContext) {
          _openConfigHub(_EditorConfigHubTab.ecomCatalog);
          return;
        }
        goAdmin('/website/product-visibility');
        return;

      // Site
      case _actionSitePages:
        if (editProvider.isInEditorContext) {
          _openConfigHub(_EditorConfigHubTab.sitePages);
          return;
        }
        goAdmin('/website/pages');
        return;
      case _actionSiteNavigation:
        if (editProvider.isInEditorContext) {
          _openConfigHub(_EditorConfigHubTab.siteNavigation);
          return;
        }
        goAdmin('/website/navigation');
        return;
      case _actionSiteDestinations:
        if (editProvider.isInEditorContext) {
          _openConfigHub(_EditorConfigHubTab.siteDestinations);
          return;
        }
        goAdmin('/website/destinations');
        return;
      case _actionSiteSettings:
        if (editProvider.isInEditorContext) {
          _openConfigHub(_EditorConfigHubTab.siteSettings);
          return;
        }
        goAdmin('/website/settings');
        return;
      case _actionSiteOpenWebsiteHub:
        if (editProvider.isInEditorContext) {
          _openConfigHub(_EditorConfigHubTab.siteHub);
          return;
        }
        goAdmin('/website');
        return;

      // E-commerce
      case _actionEcomOrders:
        if (editProvider.isInEditorContext) {
          _openConfigHub(_EditorConfigHubTab.ecomOrders);
          return;
        }
        goAdmin('/website/orders');
        return;
      case _actionEcomGoogle:
        if (editProvider.isInEditorContext) {
          _openConfigHub(_EditorConfigHubTab.integrations);
          return;
        }
        goAdmin('/website/integrations');
        return;

      // Reports
      case _actionReportsAnalytics:
        if (editProvider.isInEditorContext) {
          _openConfigHub(_EditorConfigHubTab.reportsAnalytics);
          return;
        }
        goAdmin('/tools/analytics');
        return;
      case _actionReportsOrders:
        if (editProvider.isInEditorContext) {
          _openConfigHub(_EditorConfigHubTab.ecomOrders);
          return;
        }
        goAdmin('/website/orders');
        return;

      // Google quick actions
      case _actionGoogleOpenMerchantFeed:
        final url = _resolveGoogleMerchantFeedUrl(websiteService);
        if (url == null) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('No se pudo determinar la URL del feed'),
              ),
            );
          }
          return;
        }
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
        return;
      case _actionGoogleCopyMerchantFeed:
        final url = _resolveGoogleMerchantFeedUrl(websiteService);
        if (url == null) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('No se pudo determinar la URL del feed'),
              ),
            );
          }
          return;
        }
        await _copyToClipboard(url);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Feed copiado al portapapeles')),
          );
        }
        return;

      // Config
      case _actionConfigWebsiteSettings:
        if (editProvider.isInEditorContext) {
          _openConfigHub(_EditorConfigHubTab.seo);
          return;
        }
        goAdmin('/website/seo');
        return;
      case _actionConfigIntegrations:
        if (editProvider.isInEditorContext) {
          _openConfigHub(_EditorConfigHubTab.integrations);
          return;
        }
        goAdmin('/website/integrations');
        return;
      case _actionConfigPaymentMethods:
        if (editProvider.isInEditorContext) {
          _openConfigHub(_EditorConfigHubTab.paymentMethods);
          return;
        }
        goAdmin('/settings/payment-methods');
        return;
      case _actionConfigDomain:
        if (editProvider.isInEditorContext) {
          _openConfigHub(_EditorConfigHubTab.domain);
          return;
        }
        await _showDomainAndUrlDialog(context);
        return;

      // Page actions
      case _actionPageCopyLink:
        await _copyCurrentPageUrl(context, editProvider, websiteService);
        return;
      case _actionPageOpenNewTab:
        await _openCurrentPageUrl(context, editProvider, websiteService);
        return;

      // Store actions
      case _actionStoreOpenWebsite:
        goAdmin('/website');
        return;
      case _actionStoreCopyUrl:
        await _copyPublicStoreUrl(context, websiteService);
        return;
      case _actionStoreOpenPublic:
        await _openPublicStoreUrl(context, websiteService);
        return;
    }
  }

  Future<void> _openPublicStoreUrl(
    BuildContext context,
    WebsiteService websiteService,
  ) async {
    final url = _resolvePublicStoreUrl(websiteService);
    if (url == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo determinar la URL pública')),
        );
      }
      return;
    }
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  String _currentPagePathForLink(WebsiteEditModeProvider editProvider) {
    final slug = (editProvider.currentPageSlug ?? '').trim();
    if (slug.isEmpty) {
      return _routeForPublicStore('/tienda');
    }

    // Policy pages are always clean URLs in both hosts.
    const policySlugs = {
      'nosotros',
      'terminos',
      'privacidad',
      'devoluciones',
      'envios',
    };
    if (policySlugs.contains(slug)) {
      return '/$slug';
    }

    // All other CMS pages should use the standard website page route.
    return _routeForPublicStore('/tienda/pagina/$slug');
  }

  String? _buildUrlWithPath({
    required WebsiteService websiteService,
    required String path,
  }) {
    final base = _resolvePublicStoreUrl(websiteService);
    if (base == null) return null;
    final baseUri = Uri.tryParse(base);
    if (baseUri == null) return null;

    // Ensure path is appended cleanly (avoid double slashes).
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    final next = baseUri.replace(
      path: normalizedPath,
      query: '',
      fragment: '',
    );
    return next.toString();
  }

  Future<void> _openCurrentPageUrl(
    BuildContext context,
    WebsiteEditModeProvider editProvider,
    WebsiteService websiteService,
  ) async {
    final path = _currentPagePathForLink(editProvider);
    final url = _buildUrlWithPath(websiteService: websiteService, path: path);
    if (url == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo determinar el enlace')),
        );
      }
      return;
    }
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  Future<void> _copyCurrentPageUrl(
    BuildContext context,
    WebsiteEditModeProvider editProvider,
    WebsiteService websiteService,
  ) async {
    final path = _currentPagePathForLink(editProvider);
    final url = _buildUrlWithPath(websiteService: websiteService, path: path);
    if (url == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo determinar el enlace')),
        );
      }
      return;
    }
    await Clipboard.setData(ClipboardData(text: url));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enlace copiado al portapapeles')),
      );
    }
  }

  Future<void> _copyPublicStoreUrl(
    BuildContext context,
    WebsiteService websiteService,
  ) async {
    final url = _resolvePublicStoreUrl(websiteService);
    if (url == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo determinar la URL pública')),
        );
      }
      return;
    }
    await Clipboard.setData(ClipboardData(text: url));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('URL copiada al portapapeles')),
      );
    }
  }

  Future<void> _copyToClipboard(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
  }

  String? _resolvePublicStoreUrl(WebsiteService websiteService) {
    final explicit = websiteService.getSetting('store_url', '').trim();
    if (explicit.isNotEmpty) return explicit;

    if (!kIsWeb) return null;

    // When running in ERP/admin host, we can't reliably derive the public domain here.
    // But on the public store host, Uri.base already is the public store.
    final host = Uri.base.host;
    if (host.isEmpty) return null;
    return '${Uri.base.scheme}://$host';
  }

  String? _resolveGoogleMerchantFeedUrl(WebsiteService websiteService) {
    const supabaseFunctionsBaseUrl =
        'https://xzdvtzdqjeyqxnkqprtf.supabase.co/functions/v1';

    final tenantProvider = context.read<PublicStoreTenantProvider>();
    final subdomain = (tenantProvider.subdomain ?? '').trim();

    // Prefer custom domain if we can resolve it (works for vinabike.cl).
    final publicUrl = _resolvePublicStoreUrl(websiteService);
    final host = publicUrl == null ? '' : (Uri.tryParse(publicUrl)?.host ?? '');

    if (host.isNotEmpty) {
      return '$supabaseFunctionsBaseUrl/google-merchant-feed?domain=$host';
    }
    if (subdomain.isNotEmpty) {
      return '$supabaseFunctionsBaseUrl/google-merchant-feed?tenant=$subdomain';
    }
    return null;
  }

  Future<void> _showDomainAndUrlDialog(BuildContext context) async {
    final tenantId = await _resolveTenantIdForSave(context);

    if (tenantId == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo identificar el tenant')),
        );
      }
      return;
    }

    final supabase = Supabase.instance.client;
    final tenant = await supabase
        .from('tenants')
        .select('subdomain, custom_domain')
        .eq('id', tenantId)
        .maybeSingle();

    if (!context.mounted) return;

    final subdomain = (tenant?['subdomain'] as String?)?.trim() ?? '';
    final currentCustomDomain = (tenant?['custom_domain'] as String?)?.trim();

    final controller = TextEditingController(text: currentCustomDomain ?? '');
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Dominio y URL'),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Subdominio actual: ${subdomain.isEmpty ? "—" : "$subdomain.bikeshop-erp.app"}',
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                decoration: const InputDecoration(
                  labelText: 'Dominio personalizado (opcional)',
                  hintText: 'www.tutienda.cl',
                  prefixIcon: Icon(Icons.link_outlined),
                  helperText:
                      'Si lo dejas vacío, tu tienda seguirá usando el subdominio.',
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'DNS (resumen):\n- CNAME: www -> tu-subdominio.bikeshop-erp.app\n- O A/ALIAS según tu proveedor',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton.icon(
            onPressed: () async {
              final next = controller.text.trim();
              try {
                await supabase.from('tenants').update({
                  'custom_domain': next.isEmpty ? null : next,
                }).eq('id', tenantId);
                if (dialogContext.mounted) {
                  Navigator.pop(dialogContext, true);
                }
              } catch (e) {
                if (dialogContext.mounted) {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    SnackBar(content: Text('Error actualizando dominio: $e')),
                  );
                }
              }
            },
            icon: const Icon(Icons.language_outlined),
            label: const Text('Aplicar dominio'),
          ),
        ],
      ),
    );

    controller.dispose();

    if (saved == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Dominio actualizado')),
      );
    }
  }

  Widget _buildUnpublishedSiteScaffold(BuildContext context, String storeName) {
    final label = storeName.isNotEmpty ? storeName : 'Mi Tienda';
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.visibility_off_outlined,
                    size: 56, color: Colors.grey),
                const SizedBox(height: 12),
                Text(
                  '$label no está publicado',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Este sitio está en construcción. Vuelve pronto.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.black54),
                ),
                const SizedBox(height: 16),
                Builder(
                  builder: (context) {
                    final isLoggedIn =
                        Supabase.instance.client.auth.currentUser != null;
                    if (!isLoggedIn) return const SizedBox.shrink();
                    return FilledButton.icon(
                      onPressed: () => context
                          .go(_routeForPublicStore('/tienda?preview=true')),
                      icon: const Icon(Icons.edit_outlined),
                      label: const Text('Entrar al editor'),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEditorViewport(
      BuildContext context, Widget child, DevicePreviewMode mode,
      {bool isEditMode = false}) {
    // Desktop mode is the default "no constraint" viewport.
    if (mode == DevicePreviewMode.desktop) return child;

    // Checks if we are in an "App Mode" page (like Chat) that handles its own scrolling.
    if (!widget.enablePageViewScrolling) {
      final targetWidth = mode == DevicePreviewMode.tablet ? 820.0 : 390.0;
      final modeKey = isEditMode ? 'edit' : 'preview';
      return MediaQueryLayoutBuilder(
          key: ValueKey('viewport_layout_app_${mode.name}_$modeKey'),
          builder: (context, constraints) {
            // Provide a STRICT height constraint equal to the available space (or a fixed device height).
            // Using available space (constraints.maxHeight) prevents overflow/unbounded errors.
            return Center(
              child: Container(
                width: targetWidth,
                height: constraints.maxHeight,
                decoration: BoxDecoration(
                  color: Colors.white, // Standard frame background
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
                      blurRadius: 20,
                      spreadRadius: 2,
                    )
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                child: MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                    size: Size(targetWidth, constraints.maxHeight),
                  ),
                  child: child,
                ),
              ),
            );
          });
    }

    // If we are in an app-like page that handles its own scrolling (like Chat),
    // and we are simply resizing the viewport for mobile preview, we should
    // ensure we don't apply restrictive height constraints if possible,
    // OR we rely on the fact that the inner content is now unbounded.
    // However, the real issue is likely the Clip.antiAlias and fixed height container.

    // If this is an app page (non-scrollable), we should probably return it as-is
    // but just constrained by width if we want to simulate mobile.
    // BUT the user asked to NOT break edit mode.
    // So we must ensure the container provides a valid height constraint (not infinite, but not zero).
    // The current implementation uses targetHeight = screenSize.height which IS definite.
    // The issue might be MediaQuery data overlap.

    // Let's ensure the MediaQuery doesn't mess up the constraints for the inner Expanded.
    // Actually, getting "RenderBox not laid out" usually means an Expanded is inside a parent with unbounded height (Scrollable)
    // OR an Expanded is inside a parent with 0 height.

    // If widget.enablePageViewScrolling is false, the passed 'child' (pageContent)
    // is a Column with Expanded(child: widget.child).
    // The _buildEditorViewport wraps this in a Container(height: screenSize.height).
    // This *should* work (Fixed Height > Column > Expanded).

    // Wait, let's look at the 'child' being passed.
    // pageContent is created in line 438: Column([Expanded(child: widget.child)]).
    // If that is put inside _buildEditorViewport -> Container(height: screenHeight), it should be fine.

    // Re-reading the error: "RenderBox was not laid out".
    // This often happens if the Column is inside a SingleChildScrollView.
    // But we fixed that logic in lines 423-445.

    // Is it possible 'pageContent' is NOT what we think it is?
    // In build(), 'pageContent' varies by 'headerStyle'.
    // If headerStyle is transparent... which it might be on some pages?
    // Chat page probably uses 'solid' (default).

    // Let's modify this method to pass the 'enablePageViewScrolling' check effectively.
    // If the user wants to "put the edit mode back", we just need to ensure it renders.
    // The safest fix for the "App Mode" inside Editor is to allow it to fill the container.

    // Actually, looking at the previous file content, I don't see 'enablePageViewScrolling' being checked here.
    // I will add a check: if (!widget.enablePageViewScrolling) return child; ?
    // No, user said "don't force it". They want edit mode.

    // If the error persists in edit mode, it might be the MediaQuery.size override?
    // Let's try to pass the constraints properly.

    final targetWidth = mode == DevicePreviewMode.tablet ? 820.0 : 390.0;
    final modeKey = isEditMode ? 'edit' : 'preview';

    return MediaQueryLayoutBuilder(
      key: ValueKey('viewport_layout_scroll_${mode.name}_$modeKey'),
      builder: (context, constraints) {
        final screenSize = MediaQuery.sizeOf(context);
        final availableHeight = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : screenSize.height;

        // Calculate offset for external editor panel (it overlays on the right)
        // We need to shift the preview left by half the panel width to appear visually centered
        // Only apply offset in edit mode when the panel is actually visible
        final panelOffset = (isEditMode && widget.useExternalEditorPanel)
            ? _externalEditorPanelWidth / 2
            : 0.0;

        return Container(
          color: const Color(0xFFF3F3F3),
          // Use Padding to shift content left to account for overlaid panel
          padding: EdgeInsets.only(right: panelOffset * 2),
          child: Center(
            child: Container(
              width: targetWidth,
              height: availableHeight,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x33000000),
                    blurRadius: 18,
                    offset: Offset(0, 6),
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  size: Size(targetWidth, availableHeight),
                ),
                child: child,
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _showQuickCreatePageDialog(BuildContext context) async {
    final titleController = TextEditingController();
    final slugController = TextEditingController();
    var autoSlug = true;
    PageTemplate template = PageTemplate.defaultTemplate;

    String generateSlug(String title) {
      return title
          .toLowerCase()
          .replaceAll(RegExp(r'[áàäâ]'), 'a')
          .replaceAll(RegExp(r'[éèëê]'), 'e')
          .replaceAll(RegExp(r'[íìïî]'), 'i')
          .replaceAll(RegExp(r'[óòöô]'), 'o')
          .replaceAll(RegExp(r'[úùüû]'), 'u')
          .replaceAll('ñ', 'n')
          .replaceAll(RegExp(r'[^a-z0-9\s-]'), '')
          .replaceAll(RegExp(r'\s+'), '-')
          .replaceAll(RegExp(r'-+'), '-')
          .replaceAll(RegExp(r'^-|-$'), '');
    }

    titleController.addListener(() {
      if (autoSlug) {
        slugController.text = generateSlug(titleController.text);
      }
    });

    final created = await showDialog<WebsitePage>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setState) => AlertDialog(
            title: const Text('Nueva página'),
            content: SizedBox(
              width: 520,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: titleController,
                    decoration: const InputDecoration(
                      labelText: 'Título',
                      prefixIcon: Icon(Icons.title),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: slugController,
                    decoration: InputDecoration(
                      labelText: 'Slug (URL)',
                      prefixText: '/pagina/',
                      prefixIcon: const Icon(Icons.link),
                      helperText: autoSlug
                          ? 'Auto-generado desde el título'
                          : 'Puedes editarlo manualmente',
                    ),
                    onChanged: (_) => setState(() => autoSlug = false),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<PageTemplate>(
                    initialValue: template,
                    decoration: const InputDecoration(
                      labelText: 'Plantilla',
                      prefixIcon: Icon(Icons.layers_outlined),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: PageTemplate.defaultTemplate,
                        child: Text('Estándar (bloques)'),
                      ),
                      DropdownMenuItem(
                        value: PageTemplate.landing,
                        child: Text('Landing'),
                      ),
                      DropdownMenuItem(
                        value: PageTemplate.blog,
                        child: Text('Blog'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) setState(() => template = value);
                    },
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancelar'),
              ),
              FilledButton.icon(
                onPressed: () async {
                  final title = titleController.text.trim();
                  final slug = slugController.text.trim();
                  if (title.isEmpty || slug.isEmpty) return;

                  try {
                    final websiteService = context.read<WebsiteService>();
                    final page = WebsitePage(
                      id: '',
                      tenantId: '',
                      slug: slug,
                      title: title,
                      template: template,
                      isPublished: true,
                      createdAt: DateTime.now(),
                      updatedAt: DateTime.now(),
                    );
                    final created = await websiteService.createPage(page);
                    if (dialogContext.mounted) {
                      Navigator.pop(dialogContext, created);
                    }
                  } catch (e) {
                    if (dialogContext.mounted) {
                      ScaffoldMessenger.of(dialogContext).showSnackBar(
                        SnackBar(content: Text('Error creando página: $e')),
                      );
                    }
                  }
                },
                icon: const Icon(Icons.add),
                label: const Text('Crear y editar'),
              ),
            ],
          ),
        );
      },
    );

    titleController.dispose();
    slugController.dispose();

    if (created == null || !context.mounted) return;

    // Jump directly into edit mode on the new page.
    context
        .go(_routeForPublicStore('/tienda/pagina/${created.slug}?edit=true'));
  }

  /// Check if we're on the public store domain (customer-facing)
  bool _isPublicStoreDomain() {
    if (!kIsWeb) return false;
    final host = Uri.base.host.toLowerCase();
    return host == 'vinabike-store.web.app' ||
        host == 'vinabike-store.firebaseapp.com' ||
        host == 'vinabike.cl' ||
        host == 'www.vinabike.cl';
  }

  /// Converts legacy in-app routes under `/tienda` to clean public-store routes.
  ///
  /// Example: `/tienda` -> `/`, `/tienda/productos` -> `/productos`.
  /// Preserves query parameters (e.g. `/tienda?edit=true` -> `/?edit=true`).
  String _routeForPublicStore(String legacyRoute) {
    var uri = Uri.tryParse(legacyRoute);
    if (uri == null) return legacyRoute;

    var path = uri.path;

    // Normalize relative paths like 'productos' to '/productos'.
    // This avoids odd browser URL behavior on web and keeps routing consistent.
    if (uri.scheme.isEmpty && path.isNotEmpty && !path.startsWith('/')) {
      path = '/$path';
    }

    // When running the public store entrypoint on localhost, we still want the
    // clean store routes (/, /productos, /contacto, ...) instead of /tienda/*.
    // We can infer this safely from the current browser path:
    // - Store-only app: Uri.base.path does NOT start with /tienda
    // - ERP-mounted store: Uri.base.path starts with /tienda
    final host = Uri.base.host.toLowerCase().split(':').first;
    final isLocalHost = host == 'localhost' || host == '127.0.0.1';
    final isErpMountedStore = _isErpMountedStore();
    final isStoreOnlyLocal = kIsWeb &&
        isLocalHost &&
        !isErpMountedStore &&
        !Uri.base.path.startsWith('/tienda');

    // Mobile/desktop native apps are always running the public store entrypoint
    // (there is no ERP-mounted `/tienda/*` router on those platforms).
    // Therefore we must always produce clean public-store routes.
    final isStandaloneStoreRuntime = _isPublicStoreDomain() ||
        isStoreOnlyLocal ||
        (!kIsWeb && !isErpMountedStore);

    if (isStandaloneStoreRuntime) {
      // Convert legacy in-app routes under `/tienda` to clean public-store routes.
      if (path == '/tienda' || path == '/tienda/') {
        path = '/';
      } else if (path.startsWith('/tienda/')) {
        path = path.substring('/tienda'.length);
        if (path.isEmpty) path = '/';
      }
      return uri.replace(path: path).toString();
    }

    // ERP/legacy host: keep policy pages as clean URLs (they are part of the shell).
    const policyPaths = {
      '/nosotros',
      '/terminos',
      '/privacidad',
      '/devoluciones',
      '/envios',
    };
    if (policyPaths.contains(path)) {
      return uri.toString();
    }

    // Preserve explicit legacy routes.
    if (path == '/tienda' || path.startsWith('/tienda/')) {
      return uri.toString();
    }

    // Never navigate to ERP root.
    if (path.isEmpty || path == '/') {
      path = '/tienda';
      return uri.replace(path: path).toString();
    }

    // Map common clean store routes into the ERP-mounted `/tienda/*` space.
    if (path == '/productos') path = '/tienda/productos';
    if (path == '/servicios') path = '/tienda/servicios';
    if (path == '/carrito') path = '/tienda/carrito';
    if (path == '/checkout') path = '/tienda/checkout';
    if (path == '/contacto') path = '/tienda/contacto';

    // Detail and scoped sections.
    if (path.startsWith('/producto/')) path = '/tienda$path';
    if (path.startsWith('/pedido/')) path = '/tienda$path';
    if (path == '/cuenta' || path.startsWith('/cuenta/')) path = '/tienda$path';
    if (path.startsWith('/pagina/')) path = '/tienda$path';

    return uri.replace(path: path).toString();
  }

  /// Save changes to the database
  Future<void> _reloadEditorAfterBackupRestore(
    BuildContext context,
    WebsiteEditModeProvider editProvider,
    WebsiteService websiteService,
  ) async {
    final tenantId = await _resolveTenantIdForSave(context);
    if (tenantId == null) {
      throw Exception('No se pudo identificar el tenant');
    }

    await websiteService.loadPublicStoreDataUnified(
      tenantId,
      forceRefresh: true,
    );

    final pageId = editProvider.currentPageId;
    final freshBlocks = pageId == null
        ? websiteService.blocks
        : await websiteService.loadBlocksForPage(pageId, tenantId: tenantId);

    editProvider.enterEditMode(
      freshBlocks,
      websiteService.settings,
      pageId: pageId,
      pageSlug: editProvider.currentPageSlug,
    );
  }

  Future<void> _saveChanges(
    BuildContext context,
    WebsiteEditModeProvider editProvider,
    WebsiteService websiteService,
  ) async {
    try {
      final tenantId = await _resolveTenantIdForSave(context);

      if (tenantId == null) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Error: No se pudo identificar el tenant')),
          );
        }
        return;
      }

      // Show saving indicator
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Guardando cambios...')),
        );
      }

      final result = await websiteService.saveEditorChanges(
        tenantId: tenantId,
        editorBlocks: editProvider.blocks,
        pendingSiteSettings: editProvider.pendingSiteSettings,
        pendingHeaderSettings: editProvider.pendingHeaderSettings,
        pendingFooterSettings: editProvider.pendingFooterSettings,
        pendingThemeSettings: editProvider.pendingThemeSettings,
        pendingFooterNavLabels: editProvider.pendingFooterNavLabels,
        pendingFooterNavLinkTypes: editProvider.pendingFooterNavLinkTypes,
        pendingFooterNavLinkValues: editProvider.pendingFooterNavLinkValues,
        pendingFooterNavOpenInNewTab: editProvider.pendingFooterNavOpenInNewTab,
        pendingFooterNavItems: editProvider.pendingFooterNavItems,
        pendingFooterNavCreates: editProvider.pendingFooterNavCreates,
        pendingFooterNavDeletes: editProvider.pendingFooterNavDeletes,
        pendingPageSeo: editProvider.pendingPageSeo,
        pendingFooterSectionOrder: editProvider.pendingFooterSectionOrder,
        pendingFooterLinkOrder: editProvider.pendingFooterLinkOrder,
        pendingCategoryVisibility: editProvider.pendingCategoryVisibility,
        pageId: editProvider.currentPageId,
        pageSlug: editProvider.currentPageSlug,
      );

      // Keep provider context in sync for subsequent saves
      if (result.pageId != null || (result.pageSlug?.isNotEmpty ?? false)) {
        editProvider.updateCurrentPageContext(
          pageId: result.pageId,
          pageSlug: result.pageSlug,
        );
      }

      editProvider.updateBlocksAfterSave(result.freshBlocks);
      editProvider.markAsSaved();
      editProvider.clearSiteSettingsChanges();
      editProvider.clearHeaderChanged();
      editProvider.clearFooterChanges();
      editProvider.clearThemeChanges();
      editProvider.clearSeoChanges();
      editProvider.clearCategoryChanges();

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Cambios guardados'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      debugPrint('❌ [SaveChanges] Error: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al guardar: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<String?> _resolveTenantIdForSave(BuildContext context) async {
    // 1) Public store host (anonymous tenant detection) via provider
    try {
      final tenantProvider = context.read<PublicStoreTenantProvider>();
      final tenantId = tenantProvider.tenantId;
      if (tenantId != null && tenantId.isNotEmpty) {
        return tenantId;
      }
    } catch (_) {
      // Provider not available in this tree (ERP host) - fall back below.
    }

    // 2) Authenticated ERP host via TenantService
    try {
      final tenantService = context.read<TenantService>();
      final tenantId = await tenantService.getTenantId();
      if (tenantId != null && tenantId.isNotEmpty) {
        return tenantId;
      }
    } catch (_) {
      // TenantService not provided - fall back to direct instantiation
    }

    final fallbackService = TenantService();
    final tenantId = await fallbackService.getTenantId();
    if (tenantId != null && tenantId.isNotEmpty) {
      return tenantId;
    }

    return null;
  }

  Widget _buildHeader({
    required BuildContext context,
    required String storeName,
    required String storeDescription,
    required String logoUrl,
    required String topBannerText,
    required String contactPhone,
    required String contactEmail,
    required Color primaryColor,
    required Color accentColor,
    bool isEditMode = false,
    String headerStyle = 'solid',
    String headerColorMode = 'auto',
    bool showTopBanner = true,
    bool headerShadow = true,
    Color headerBgColor = Colors.white,
    List<WebsiteNavigation> navItems = const [],
    bool isOverlay = false, // For transparent mode when scrolled up
    double topOffset = 0.0, // Explicit top offset for Mega Menu alignment
  }) {
    final cart = context.watch<CartProvider>();
    final modeKey = isEditMode ? 'edit' : 'normal';

    return MediaQueryLayoutBuilder(
        key: ValueKey(
            'header_layout_${isOverlay ? 'overlay' : 'solid'}_$modeKey'),
        builder: (context, constraints) {
          return AnimatedBuilder(
            animation: MegaMenuController.instance,
            builder: (context, child) {
              final isMenuOpen = MegaMenuController.instance.isAnyMenuOpen;

              final contrastMode =
                  PublicHeaderContrastModeX.parse(headerColorMode);
              final usesLightForeground = isMenuOpen ||
                  contrastMode.usesLightForeground(
                    isOverlay: isOverlay,
                    backgroundColor: headerBgColor,
                  );

              // If menu is open, we force everything to Look like the Mega Menu Panel (Black)
              final effectiveBgColor = isMenuOpen
                  ? const Color(0xFF000000)
                  : (isOverlay ? Colors.transparent : headerBgColor);

              final textColor =
                  usesLightForeground ? Colors.white : Colors.black87;
              final iconColor = usesLightForeground
                  ? Colors.white
                  : PublicStoreTheme.logoBlue;

              // Remove shadow when menu is open to prevent "seam" line
              final effectiveElevation =
                  (isMenuOpen || isOverlay) ? 0.0 : (headerShadow ? 2.0 : 0.0);

              final screenWidth = constraints.maxWidth;
              final isDesktopHeader = screenWidth >= 900;
              final useAdaptiveOverlayScrim = isOverlay &&
                  contrastMode == PublicHeaderContrastMode.automatic;
              final headerHorizontalPadding = isDesktopHeader ? 24.0 : 16.0;
              final headerVerticalPadding = isDesktopHeader ? 8.0 : 10.0;
              final headerLogoHeight = isDesktopHeader ? 38.0 : 40.0;
              final headerIconSize = isDesktopHeader ? 22.0 : 23.0;
              final headerIconBox = isDesktopHeader ? 40.0 : 42.0;

              // Wrap with MegaMenuHeaderWrapper to enable dark background (#111111) when menu is open
              // Also wrap with Transform.translate to force a new stacking context on Web
              // to prevent it from falling behind other layers (like the Carousel).
              final headerContent = Transform.translate(
                offset: Offset.zero,
                child: MegaMenuHeaderWrapper(
                  fixedTop: topOffset,
                  child: AnimatedPhysicalModel(
                    duration: const Duration(
                        milliseconds:
                            300), // Slightly slower to match menu fade/rendering
                    curve: Curves
                        .easeInOut, // Smoother transition than easeOut which effectively snaps to black too fast
                    shape: BoxShape.rectangle,
                    elevation: effectiveElevation,
                    color: effectiveBgColor,
                    shadowColor: Colors.black,
                    child: Container(
                      decoration: useAdaptiveOverlayScrim
                          ? BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Colors.black.withValues(alpha: 0.52),
                                  Colors.black.withValues(alpha: 0.24),
                                ],
                              ),
                            )
                          : null,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (showTopBanner && topBannerText.isNotEmpty)
                            Container(
                              width: double.infinity,
                              color: usesLightForeground
                                  ? Colors.black.withValues(alpha: 0.3)
                                  : primaryColor,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 24, vertical: 6),
                              child: Row(
                                children: [
                                  const Icon(Icons.local_shipping_outlined,
                                      color: Colors.white, size: 16),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      topBannerText,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w500,
                                          ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  if (screenWidth >= 900) ...[
                                    if (contactPhone.isNotEmpty)
                                      Padding(
                                        padding:
                                            const EdgeInsets.only(left: 16),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(Icons.phone_outlined,
                                                color: Colors.white, size: 16),
                                            const SizedBox(width: 8),
                                            Text(
                                              contactPhone,
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .bodySmall
                                                  ?.copyWith(
                                                    color: Colors.white,
                                                    fontWeight: FontWeight.w500,
                                                  ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    if (contactEmail.isNotEmpty)
                                      Padding(
                                        padding:
                                            const EdgeInsets.only(left: 16),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(Icons.mail_outline,
                                                color: Colors.white, size: 16),
                                            const SizedBox(width: 8),
                                            Text(
                                              contactEmail,
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .bodySmall
                                                  ?.copyWith(
                                                    color: Colors.white,
                                                    fontWeight: FontWeight.w500,
                                                  ),
                                            ),
                                          ],
                                        ),
                                      ),
                                  ],
                                ],
                              ),
                            ),

                          // Main header with logo
                          Center(
                            child: Container(
                              constraints: const BoxConstraints(maxWidth: 1200),
                              padding: EdgeInsets.symmetric(
                                  horizontal: headerHorizontalPadding,
                                  vertical: headerVerticalPadding),
                              child: Row(
                                children: [
                                  // Logo - uses URL if set, otherwise falls back to asset, then text
                                  // Logo - Force use of local asset for consistency and to fix "white block" issue
                                  // (Database logo_url might be opaque, causing white tint to fill the box)
                                  InkWell(
                                    onTap: isEditMode
                                        ? null
                                        : () {
                                            final path =
                                                _routeForPublicStore('/tienda');
                                            _navigateToHref(
                                              context,
                                              path,
                                              forceHomeRefresh: true,
                                            );
                                          },
                                    child: _buildLogo(
                                      context: context,
                                      logoUrl: logoUrl,
                                      storeName: storeName,
                                      textColor: textColor,
                                      isDarkMode: usesLightForeground,
                                      height: headerLogoHeight,
                                    ),
                                  ),
                                  SizedBox(width: isDesktopHeader ? 22 : 16),
                                  // Only show nav links on desktop, use Spacer on mobile
                                  if (screenWidth >= 900)
                                    Expanded(
                                      child: Row(
                                        children: navItems.isEmpty
                                            ? [
                                                _buildNavLink(
                                                  context,
                                                  'Inicio',
                                                  _routeForPublicStore(
                                                      '/tienda'),
                                                  textColor,
                                                  isEditMode: isEditMode,
                                                ),
                                                const SizedBox(width: 32),
                                                _buildNavLink(
                                                  context,
                                                  'Productos',
                                                  _routeForPublicStore(
                                                      '/productos'),
                                                  textColor,
                                                  isEditMode: isEditMode,
                                                ),
                                                const SizedBox(width: 32),
                                                _buildNavLink(
                                                  context,
                                                  'Servicios',
                                                  _routeForPublicStore(
                                                      '/servicios'),
                                                  textColor,
                                                  isEditMode: isEditMode,
                                                ),
                                              ]
                                            : [
                                                ...navItems
                                                    .where(
                                                        (n) => n.showOnDesktop)
                                                    .map((nav) {
                                                  final children = nav.children
                                                      .where((c) => c.isVisible)
                                                      .where((c) =>
                                                          c.showOnDesktop)
                                                      .toList()
                                                    ..sort((a, b) =>
                                                        a.orderIndex.compareTo(
                                                            b.orderIndex));

                                                  if (children.isNotEmpty) {
                                                    // ALWAYS use Mega Menu for desktop nav items with children
                                                    // (Per user requirement for "Fox Racing" style)
                                                    return Padding(
                                                      padding:
                                                          const EdgeInsets.only(
                                                              right: 24),
                                                      child: MegaMenuButton(
                                                        key: ValueKey(
                                                            'mega_${nav.id}_${nav.label}'),
                                                        parent: nav,
                                                        children: children,
                                                        isEditMode: isEditMode,
                                                        textColor: textColor,
                                                        onNavigate: (href,
                                                                newTab) =>
                                                            _navigateToHref(
                                                                context, href,
                                                                openInNewTab:
                                                                    newTab),
                                                      ),
                                                    );
                                                  }

                                                  return Padding(
                                                    padding:
                                                        const EdgeInsets.only(
                                                            right: 24),
                                                    child: _buildNavItemLink(
                                                      context,
                                                      nav,
                                                      textColor,
                                                      isEditMode: isEditMode,
                                                    ),
                                                  );
                                                }),
                                              ],
                                      ),
                                    )
                                  else
                                    const Spacer(),
                                  Row(
                                    children: [
                                      IconButton(
                                        icon: Icon(Icons.search,
                                            size: headerIconSize),
                                        color: iconColor,
                                        onPressed: () =>
                                            SearchOverlay.show(context),
                                        tooltip: 'Buscar',
                                        constraints: BoxConstraints.tightFor(
                                          width: headerIconBox,
                                          height: headerIconBox,
                                        ),
                                        padding: EdgeInsets.zero,
                                      ),
                                      SizedBox(width: isDesktopHeader ? 2 : 4),
                                      Stack(
                                        clipBehavior: Clip.none,
                                        children: [
                                          IconButton(
                                            icon: Icon(
                                              Icons.shopping_cart_outlined,
                                              size: headerIconSize,
                                            ),
                                            color: iconColor,
                                            onPressed: () => _navigateToHref(
                                              context,
                                              _routeForPublicStore(
                                                  '/tienda/carrito'),
                                            ),
                                            tooltip: 'Carrito',
                                            constraints:
                                                BoxConstraints.tightFor(
                                              width: headerIconBox,
                                              height: headerIconBox,
                                            ),
                                            padding: EdgeInsets.zero,
                                          ),
                                          if (cart.itemCount > 0)
                                            Positioned(
                                              right: 0,
                                              top: 0,
                                              child: IgnorePointer(
                                                child: Container(
                                                  padding:
                                                      const EdgeInsets.all(4),
                                                  decoration: BoxDecoration(
                                                    color: accentColor,
                                                    shape: BoxShape.circle,
                                                  ),
                                                  constraints:
                                                      const BoxConstraints(
                                                    minWidth: 18,
                                                    minHeight: 18,
                                                  ),
                                                  child: Text(
                                                    '${cart.itemCount}',
                                                    style: const TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 10,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                    ),
                                                    textAlign: TextAlign.center,
                                                  ),
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                      if (screenWidth >= 900) ...[
                                        const SizedBox(width: 10),
                                        CustomerAccountMenu(
                                            textColor: textColor),
                                      ] else ...[
                                        const SizedBox(width: 4),
                                        IconButton(
                                          icon: Icon(Icons.menu,
                                              size: headerIconSize),
                                          color: iconColor,
                                          onPressed: () => _showMobileMenu(
                                              context, navItems),
                                          tooltip: 'Menú',
                                          constraints: BoxConstraints.tightFor(
                                            width: headerIconBox,
                                            height: headerIconBox,
                                          ),
                                          padding: EdgeInsets.zero,
                                        ),
                                      ]
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );

              // Wrap with edit mode indicator if in edit mode
              if (isEditMode) {
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    // Select header for editing in the "Editar" tab
                    final editProvider =
                        context.read<WebsiteEditModeProvider>();
                    editProvider.selectBlock('header');
                  },
                  child: Stack(
                    children: [
                      headerContent,
                      Positioned.fill(
                        child: IgnorePointer(
                          child: Container(
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: Colors.blue.withValues(alpha: 0.5),
                                width: 2,
                              ),
                            ),
                            child: Align(
                              alignment: Alignment.topLeft,
                              child: Container(
                                margin: const EdgeInsets.all(4),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.blue,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.edit,
                                        color: Colors.white, size: 14),
                                    SizedBox(width: 4),
                                    Text(
                                      'Header',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }

              return headerContent;
            },
          );
        });
  }

  /// Builds a layout where the header stays fixed at the top while scrolling
  /// Header starts with configured style and stays visible
  Widget _buildStickyHeaderLayout({
    required BuildContext context,
    required String storeName,
    required String storeDescription,
    required String logoUrl,
    required String topBannerText,
    required String contactPhone,
    required String contactEmail,
    required Color primaryColor,
    required Color accentColor,
    required String headerColorMode,
    required bool showTopBanner,
    required bool headerShadow,
    required Color headerBgColor,
    required List<WebsiteNavigation> navItems,
    required bool isEditMode,
    required Widget child,
    required Widget footer,
    bool allowOverlayAtTop = true,
    String scrollViewMode = 'normal',
  }) {
    // Sticky uses the scaffold that keeps header fixed at top
    // Mode-aware key ensures complete widget recreation on mode change to
    // avoid element reactivation crashes during layout.
    return _StickyHeaderScaffold(
      key: ValueKey('sticky_scaffold_$scrollViewMode'),
      storeName: storeName,
      storeDescription: storeDescription,
      logoUrl: logoUrl,
      topBannerText: topBannerText,
      contactPhone: contactPhone,
      contactEmail: contactEmail,
      primaryColor: primaryColor,
      accentColor: accentColor,
      headerColorMode: headerColorMode,
      showTopBanner: showTopBanner,
      headerShadow: headerShadow,
      headerBgColor: headerBgColor,
      navItems: navItems,
      isEditMode: isEditMode,
      allowOverlayAtTop: allowOverlayAtTop,
      buildHeader: _buildHeader,
      footer: footer,
      child: child,
    );
  }

  Widget _buildMobileFooter({
    required BuildContext context,
    required List<WebsiteNavigation> footerNavItems,
    required String storeName,
    required String storeDescription,
    required String contactEmail,
    required String contactPhone,
    required String contactAddress,
    required String? facebookUrl,
    required String? instagramUrl,
    required String? twitterUrl,
    required String? youtubeUrl,
    required String? whatsappUrl,
    required Color primaryColor,
    required Color accentColor,
    required String logoUrl,
    bool isEditMode = false,
    bool isPreviewMode = false, // Added for preview visibility
  }) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    const dividerColor = Colors.white24;
    // final iconColor = primaryColor; // Unused now, switching to white

    return Container(
      color: PublicStoreTheme.textPrimary,
      padding:
          const EdgeInsets.fromLTRB(16, 32, 16, 24), // Reduced bottom padding
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Store Logo
          Center(
            child: SizedBox(
              height: 50,
              child: logoUrl.isNotEmpty
                  ? Stack(
                      children: [
                        // Outline layers (simulated stroke)
                        for (final offset in const [
                          Offset(-1, -1),
                          Offset(1, -1),
                          Offset(-1, 1),
                          Offset(1, 1),
                        ])
                          Transform.translate(
                            offset: offset,
                            child: Image.network(
                              logoUrl,
                              fit: BoxFit.contain,
                              color: Colors.white,
                              colorBlendMode: BlendMode.srcIn,
                            ),
                          ),
                        // Main Image
                        Image.network(
                          logoUrl,
                          fit: BoxFit.contain,
                          filterQuality: FilterQuality.high,
                          errorBuilder: (context, error, stackTrace) => Text(
                            storeName,
                            style: textTheme.headlineSmall?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    )
                  : Image.asset(
                      'assets/images/vinabike_logo.png',
                      fit: BoxFit.contain,
                      filterQuality: FilterQuality.high,
                      errorBuilder: (context, error, stackTrace) => Text(
                        storeName.isNotEmpty ? storeName : 'VINABIKE',
                        style: textTheme.headlineSmall?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 32),

          ..._buildMobileFooterNavigationSections(
            context: context,
            footerNavItems: footerNavItems,
            titleStyle: textTheme.titleSmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.0,
            ),
            isEditMode: isEditMode,
          ),

          // Collapsible: Contact
          Theme(
            data: theme.copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              title: Text(
                'CONTACTO',
                style: textTheme.titleSmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.0,
                ),
              ),
              iconColor: Colors.white,
              collapsedIconColor: Colors.white,
              childrenPadding: const EdgeInsets.only(left: 16, bottom: 16),
              children: [
                if (contactAddress.isNotEmpty)
                  _buildFooterContactItem(context, Icons.location_on_outlined,
                      contactAddress, null),
                if (contactPhone.isNotEmpty)
                  _buildFooterContactItem(
                      context,
                      Icons.phone_outlined,
                      contactPhone,
                      () => _launchUri(Uri(scheme: 'tel', path: contactPhone))),
                if (contactEmail.isNotEmpty)
                  _buildFooterContactItem(
                      context,
                      Icons.email_outlined,
                      contactEmail,
                      () => _launchUri(
                          Uri(scheme: 'mailto', path: contactEmail))),
              ],
            ),
          ),
          const Divider(color: dividerColor),

          const SizedBox(height: 32),

          if (facebookUrl != null ||
              instagramUrl != null ||
              twitterUrl != null ||
              youtubeUrl != null ||
              whatsappUrl != null ||
              isEditMode) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                '¡SÍGUENOS!',
                style: textTheme.titleSmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.0,
                ),
                textAlign: TextAlign.left,
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Wrap(
                alignment: WrapAlignment.start,
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (facebookUrl != null || isEditMode)
                    _buildSocialIconMobile(
                      FontAwesomeIcons.facebook,
                      facebookUrl,
                      isEditMode,
                      settingKey: 'facebook',
                      label: 'Facebook',
                    ),
                  if (instagramUrl != null || isEditMode)
                    _buildSocialIconMobile(
                      FontAwesomeIcons.instagram,
                      instagramUrl,
                      isEditMode,
                      settingKey: 'instagram',
                      label: 'Instagram',
                    ),
                  if (twitterUrl != null || isEditMode)
                    _buildSocialIconMobile(
                      FontAwesomeIcons.xTwitter,
                      twitterUrl,
                      isEditMode,
                      settingKey: 'twitter',
                      label: 'Twitter/X',
                    ),
                  if (youtubeUrl != null || isEditMode)
                    _buildSocialIconMobile(
                      FontAwesomeIcons.youtube,
                      youtubeUrl,
                      isEditMode,
                      settingKey: 'youtube',
                      label: 'YouTube',
                    ),
                  if (whatsappUrl != null || isEditMode)
                    _buildSocialIconMobile(
                      FontAwesomeIcons.whatsapp,
                      whatsappUrl,
                      isEditMode,
                      settingKey: 'whatsapp',
                      label: 'WhatsApp',
                    ),
                ],
              ),
            ),
            const SizedBox(height: 32),
          ],

          // Copyright
          Center(
            child: Text(
              '© ${DateTime.now().year} ${storeName.isNotEmpty ? storeName : 'Vinabike'}. Todos los derechos reservados.',
              style: textTheme.bodySmall?.copyWith(color: Colors.white54),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 24), // Reduced bottom space
        ],
      ),
    );
  }

  Widget _buildDesktopSocialIcon(
    BuildContext context,
    IconData icon,
    String? url,
    bool isEditMode,
    String settingKey,
    String label, {
    bool isContact = false, // Special handling for contact items
  }) {
    if ((url == null || url.trim().isEmpty) && !isEditMode) {
      return const SizedBox.shrink();
    }

    // Determine icon color
    final hasValue = url != null && url.trim().isNotEmpty;
    final iconColor =
        hasValue ? Colors.white70 : Colors.white70.withValues(alpha: 0.35);

    // Determine tooltip
    final tooltip =
        isEditMode ? (hasValue ? 'Editar $label' : 'Agregar $label') : label;

    // Determine tap action
    VoidCallback? onTap;
    if (isEditMode) {
      onTap = () {
        if (isContact) {
          _showFooterContactEditDialog(context, settingKey, label, url ?? '');
        } else {
          _showSocialMediaEditDialog(context, settingKey, label, url);
        }
      };
    } else if (hasValue) {
      onTap = () {
        if (isContact) {
          if (settingKey == 'contact_email') {
            _launchUri(Uri(scheme: 'mailto', path: url));
          } else if (settingKey == 'contact_phone') {
            _launchUri(Uri(scheme: 'tel', path: url));
          }
        } else {
          _launchUri(Uri.parse(url));
        }
      };
    }

    return IconButton(
      icon: FaIcon(icon, color: iconColor, size: 22),
      onPressed: onTap,
      tooltip: tooltip,
    );
  }

  Widget _buildFooterLinkMobile(
    BuildContext context,
    String text,
    String route, {
    bool forceHomeRefresh = false,
    required bool isEditMode,
  }) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: InkWell(
          onTap: isEditMode
              ? null
              : () {
                  _navigateToHref(
                    context,
                    route,
                    forceHomeRefresh: forceHomeRefresh,
                  );
                },
          child: Text(
            text,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.white70,
                ),
          ),
        ),
      ),
    );
  }

  Widget _buildFooterContactItem(
      BuildContext context, IconData icon, String text, VoidCallback? onTap) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Colors.white70, size: 18),
          const SizedBox(width: 12),
          Expanded(
            child: InkWell(
              onTap: onTap,
              child: Text(
                text,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.white70,
                    ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showFooterContactEditDialog(
    BuildContext context,
    String settingKey,
    String label,
    String currentValue,
  ) async {
    final editProvider = context.read<WebsiteEditModeProvider>();
    final controller = TextEditingController(text: currentValue);

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Editar $label'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                style: const TextStyle(
                    color: Colors.black87), // Ensure visible text
                decoration: InputDecoration(
                  labelText: label,
                  hintText: _getHintForFooterContactSetting(settingKey),
                  fillColor: Colors.white,
                  filled: true,
                  prefixIcon: Icon(
                    settingKey == 'contact_phone'
                        ? Icons.phone_outlined
                        : Icons.mail_outline,
                  ),
                  helperText: settingKey == 'contact_phone'
                      ? 'Ej: +56 9 9835 7797'
                      : 'Ej: contacto@vinabike.cl',
                ),
                keyboardType: settingKey == 'contact_phone'
                    ? TextInputType.phone
                    : TextInputType.emailAddress,
                autofocus: true,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton.icon(
            onPressed: () {
              final value = controller.text.trim();
              editProvider.updateFooterSetting(settingKey, value);
              if (dialogContext.mounted) {
                Navigator.pop(dialogContext, true);
              }
            },
            icon: const Icon(Icons.check),
            label: const Text('Aplicar'),
          ),
        ],
      ),
    );

    controller.dispose();

    if (saved == true && mounted) {
      setState(() {});
    }
  }

  String _getHintForFooterContactSetting(String key) {
    switch (key) {
      case 'contact_email':
        return 'contacto@vinabike.cl';
      case 'contact_phone':
        return '+56 9 9835 7797';
      case 'contact_address':
        return 'Álvarez 32, Local 17, Viña del Mar';
      case 'whatsapp':
        return '+56 9 9835 7797';
      default:
        return '';
    }
  }

  Widget _buildSocialIconMobile(
    IconData icon,
    String? url,
    bool isEditMode, {
    required String settingKey,
    required String label,
  }) {
    if (url == null && !isEditMode) {
      return const SizedBox.shrink();
    }

    final hasUrl = url != null && url.isNotEmpty;

    return InkWell(
      onTap: () async {
        if (isEditMode) {
          // Show edit dialog
          await _showSocialMediaEditDialog(context, settingKey, label, url);
        } else if (hasUrl) {
          _launchUri(Uri.parse(url));
        }
      },
      child: Stack(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: hasUrl
                  ? Colors.white.withValues(alpha: 0.1)
                  : Colors.white.withValues(alpha: 0.05),
              border: isEditMode && !hasUrl
                  ? Border.all(
                      color: Colors.white38,
                      width: 1,
                      strokeAlign: BorderSide.strokeAlignInside)
                  : null,
            ),
            child: Center(
              child: FaIcon(
                icon,
                color: hasUrl ? Colors.white : Colors.white38,
                size: 22,
              ),
            ),
          ),
          if (isEditMode)
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  color: hasUrl ? Colors.green : Colors.orange,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  hasUrl ? Icons.check : Icons.edit,
                  color: Colors.white,
                  size: 10,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _showSocialMediaEditDialog(
    BuildContext context,
    String settingKey,
    String label,
    String? currentValue,
  ) async {
    final editProvider = context.read<WebsiteEditModeProvider>();
    final controller = TextEditingController(text: currentValue ?? '');

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Editar $label'),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                style: const TextStyle(
                    color: Colors.black87), // Ensure visible text
                decoration: InputDecoration(
                  labelText: 'Usuario o URL de $label',
                  hintText: _getHintForSetting(settingKey),
                  fillColor: Colors.white,
                  filled: true,
                  prefixIcon: const Icon(Icons.link_outlined),
                  helperText: 'Puedes ingresar el @usuario o la URL completa',
                ),
                autofocus: true,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton.icon(
            onPressed: () {
              final value = controller.text.trim();
              editProvider.updateFooterSetting(settingKey, value);
              if (dialogContext.mounted) {
                Navigator.pop(dialogContext, true);
              }
            },
            icon: const Icon(Icons.check),
            label: const Text('Aplicar'),
          ),
        ],
      ),
    );

    controller.dispose();

    if (saved == true && mounted) {
      setState(() {}); // Refresh to show updated value
    }
  }

  String _getHintForSetting(String key) {
    switch (key) {
      case 'facebook':
        return '@vinabike o https://facebook.com/vinabike';
      case 'instagram':
        return '@vinabike o https://instagram.com/vinabike';
      case 'twitter':
        return '@vinabike o https://twitter.com/vinabike';
      case 'youtube':
        return '@vinabikechannel o https://youtube.com/@vinabike';
      default:
        return '';
    }
  }

  Widget _buildFooter({
    required BuildContext context,
    required String storeName,
    required String storeDescription,
    required String contactEmail,
    required String contactPhone,
    required String contactAddress,
    required String facebookHandle,
    required String instagramHandle,
    required String twitterHandle,
    required String youtubeHandle,
    required String whatsappHandle,
    required Color primaryColor,
    required Color accentColor,
    required String logoUrl, // Added parameter
    bool isEditMode = false,
  }) {
    final modeKey = isEditMode ? 'edit' : 'normal';
    return MediaQueryLayoutBuilder(
        key: ValueKey('footer_layout_$modeKey'),
        builder: (context, constraints) {
          final websiteService = context.watch<WebsiteService>();
          final editProvider = context.watch<WebsiteEditModeProvider>();
          var footerNavItems = editProvider.getEffectiveFooterNavigation(
            websiteService.footerNavigation,
          );

          // Apply pending section order from provider for live preview
          final pendingSectionOrder = editProvider.pendingFooterSectionOrder;
          if (pendingSectionOrder != null && pendingSectionOrder.isNotEmpty) {
            final orderMap = <String, int>{};
            for (var i = 0; i < pendingSectionOrder.length; i++) {
              orderMap[pendingSectionOrder[i]] = i;
            }
            footerNavItems.sort((a, b) {
              final aIdx = orderMap[a.id] ?? a.orderIndex;
              final bIdx = orderMap[b.id] ?? b.orderIndex;
              return aIdx.compareTo(bIdx);
            });
          }

          // Apply pending link order for each section - create new section objects
          final pendingLinkOrder = editProvider.pendingFooterLinkOrder;
          if (pendingLinkOrder.isNotEmpty) {
            footerNavItems = footerNavItems.map((section) {
              final linkOrder = pendingLinkOrder[section.id];
              if (linkOrder != null && linkOrder.isNotEmpty) {
                final orderMap = <String, int>{};
                for (var i = 0; i < linkOrder.length; i++) {
                  orderMap[linkOrder[i]] = i;
                }
                final sortedChildren =
                    List<WebsiteNavigation>.from(section.children)
                      ..sort((a, b) {
                        final aHas = orderMap.containsKey(a.id);
                        final bHas = orderMap.containsKey(b.id);
                        if (aHas && bHas) {
                          return orderMap[a.id]!.compareTo(orderMap[b.id]!);
                        }
                        if (aHas) return -1;
                        if (bHas) return 1;
                        return a.orderIndex.compareTo(b.orderIndex);
                      });

                return section.copyWith(children: sortedChildren);
              }
              return section;
            }).toList();
          }

          final screenWidth = MediaQuery.of(context).size.width;
          final isMobile = screenWidth < 800;

          final facebookUrl =
              _buildSocialUrl(facebookHandle, 'https://facebook.com/');
          final instagramUrl =
              _buildSocialUrl(instagramHandle, 'https://instagram.com/');
          final twitterUrl =
              _buildSocialUrl(twitterHandle, 'https://twitter.com/');
          final youtubeUrl =
              _buildSocialUrl(youtubeHandle, 'https://youtube.com/');
          final whatsappUrl = whatsappHandle.isNotEmpty
              ? 'https://wa.me/${_sanitizePhone(whatsappHandle)}?text=${Uri.encodeComponent("Hola $storeName, vengo desde el sitio web")}'
              : null;

          if (isMobile) {
            return _buildMobileFooter(
              context: context,
              footerNavItems: footerNavItems,
              storeName: storeName,
              storeDescription: storeDescription,
              contactEmail: contactEmail,
              contactPhone: contactPhone,
              contactAddress: contactAddress,
              facebookUrl: facebookUrl,
              instagramUrl: instagramUrl,
              twitterUrl: twitterUrl,
              youtubeUrl: youtubeUrl,
              whatsappUrl: whatsappUrl,
              primaryColor: primaryColor,
              accentColor: accentColor,
              logoUrl: logoUrl,
              isEditMode: isEditMode,
              isPreviewMode:
                  isMobile, // Always true when this branch runs, so icons show
            );
          }

          final footerContent = Container(
            width: double.infinity,
            color: PublicStoreTheme.textPrimary,
            padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 24),
            child: Center(
              child: Container(
                constraints: const BoxConstraints(maxWidth: 1200),
                child: Column(
                  children: [
                    Wrap(
                      spacing: 32,
                      runSpacing: 24,
                      crossAxisAlignment: WrapCrossAlignment.start,
                      children: [
                        SizedBox(
                          width: 250,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildLogo(
                                context: context,
                                logoUrl: logoUrl,
                                storeName: storeName,
                                textColor: Colors.white,
                                isDarkMode: true,
                                height: 60,
                                alignment: Alignment.centerLeft,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                storeDescription.isNotEmpty
                                    ? storeDescription
                                    : 'Todo lo que necesitas para tu bicicleta en Viña del Mar',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(
                                      color: Colors.white70,
                                    ),
                              ),
                              const SizedBox(height: 24),
                              Wrap(
                                spacing: 8,
                                children: [
                                  // Facebook
                                  if (facebookUrl != null || isEditMode)
                                    _buildDesktopSocialIcon(
                                      context,
                                      FontAwesomeIcons.facebook,
                                      facebookUrl,
                                      isEditMode,
                                      'facebook',
                                      'Facebook',
                                    ),
                                  // Instagram
                                  if (instagramUrl != null || isEditMode)
                                    _buildDesktopSocialIcon(
                                      context,
                                      FontAwesomeIcons.instagram,
                                      instagramUrl,
                                      isEditMode,
                                      'instagram',
                                      'Instagram',
                                    ),
                                  // Twitter
                                  if (twitterUrl != null || isEditMode)
                                    _buildDesktopSocialIcon(
                                      context,
                                      FontAwesomeIcons.xTwitter,
                                      twitterUrl,
                                      isEditMode,
                                      'twitter',
                                      'Twitter',
                                    ),
                                  // YouTube
                                  if (youtubeUrl != null || isEditMode)
                                    _buildDesktopSocialIcon(
                                      context,
                                      FontAwesomeIcons.youtube,
                                      youtubeUrl,
                                      isEditMode,
                                      'youtube',
                                      'YouTube',
                                    ),
                                  // WhatsApp
                                  if (whatsappUrl != null || isEditMode)
                                    _buildDesktopSocialIcon(
                                      context,
                                      FontAwesomeIcons.whatsapp,
                                      whatsappUrl,
                                      isEditMode,
                                      'whatsapp',
                                      'WhatsApp',
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        ..._buildFooterNavigationColumnsDesktop(
                          context: context,
                          footerNavItems: footerNavItems,
                          primaryColor: primaryColor,
                          isEditMode: isEditMode,
                        ),
                        SizedBox(
                          width: 200,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Contacto',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                    ),
                              ),
                              const SizedBox(height: 16),
                              if (contactAddress.isNotEmpty) ...[
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Icon(Icons.location_on_outlined,
                                        color: Colors.white70, size: 20),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        contactAddress,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                              color: Colors.white70,
                                            ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                              ],
                              if (contactPhone.isNotEmpty) ...[
                                Row(
                                  children: [
                                    const Icon(Icons.phone_outlined,
                                        color: Colors.white70, size: 20),
                                    const SizedBox(width: 8),
                                    Text(
                                      contactPhone,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: Colors.white70,
                                          ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                              ],
                              if (contactEmail.isNotEmpty)
                                Row(
                                  children: [
                                    const Icon(Icons.email_outlined,
                                        color: Colors.white70, size: 20),
                                    const SizedBox(width: 8),
                                    Text(
                                      contactEmail,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: Colors.white70,
                                          ),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    // Payment badges - using our own hosted icons from Supabase Storage
                    const SizedBox(height: 32),
                    Column(
                      children: [
                        Text(
                          'Medios de Pago',
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: Colors.white60,
                                    fontSize: 11,
                                    letterSpacing: 0.5,
                                  ),
                        ),
                        const SizedBox(height: 16),
                        const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _PaymentBadge(
                              name: 'MercadoPago',
                              imageUrl:
                                  'https://xzdvtzdqjeyqxnkqprtf.supabase.co/storage/v1/object/public/vinabike-assets/payment-icons/mercadopago.svg',
                              isSvg: true,
                            ),
                            SizedBox(width: 12),
                            _PaymentBadge(
                              name: 'Visa',
                              imageUrl:
                                  'https://xzdvtzdqjeyqxnkqprtf.supabase.co/storage/v1/object/public/vinabike-assets/payment-icons/visa.svg',
                              isSvg: true,
                            ),
                            SizedBox(width: 12),
                            _PaymentBadge(
                              name: 'Mastercard',
                              imageUrl:
                                  'https://xzdvtzdqjeyqxnkqprtf.supabase.co/storage/v1/object/public/vinabike-assets/payment-icons/mastercard.svg',
                              isSvg: true,
                            ),
                            SizedBox(width: 12),
                            _PaymentBadge(
                              name: 'Redcompra',
                              imageUrl:
                                  'https://xzdvtzdqjeyqxnkqprtf.supabase.co/storage/v1/object/public/vinabike-assets/payment-icons/redcompra.png',
                              isSvg: false,
                            ),
                          ],
                        ),
                      ],
                    ),
                    const Divider(color: Colors.white24),
                    const SizedBox(height: 24),
                    Text(
                      '© ${DateTime.now().year} ${storeName.isNotEmpty ? storeName : 'Vinabike'}. Todos los derechos reservados.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Colors.white70,
                          ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          );

          // Wrap with edit mode indicator if in edit mode
          if (isEditMode) {
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                // Select footer for editing in the "Editar" tab
                final editProvider = context.read<WebsiteEditModeProvider>();
                editProvider.selectBlock('footer');
              },
              child: Stack(
                children: [
                  footerContent,
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: Colors.green.withValues(alpha: 0.5),
                            width: 2,
                          ),
                        ),
                        child: Align(
                          alignment: Alignment.topLeft,
                          child: Container(
                            margin: const EdgeInsets.all(4),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.green,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.edit, color: Colors.white, size: 14),
                                SizedBox(width: 4),
                                Text(
                                  'Footer',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          }

          return footerContent;
        });
  }

  List<Widget> _buildFooterNavigationColumnsDesktop({
    required BuildContext context,
    required List<WebsiteNavigation> footerNavItems,
    required Color primaryColor,
    required bool isEditMode,
  }) {
    final desktopItems = footerNavItems
        .where((n) => n.isVisible)
        .where((n) => n.showOnDesktop)
        .toList();

    if (desktopItems.isEmpty) {
      return [
        SizedBox(
          width: 180,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Enlaces',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 16),
              _buildFooterLinkDesktop(
                context,
                'Inicio',
                _routeForPublicStore('/tienda'),
                primaryColor,
                isEditMode: isEditMode,
              ),
              _buildFooterLinkDesktop(
                context,
                'Productos',
                '/productos',
                primaryColor,
                isEditMode: isEditMode,
              ),
              _buildFooterLinkDesktop(
                context,
                'Servicios',
                _routeForPublicStore('/servicios'),
                primaryColor,
                isEditMode: isEditMode,
              ),
              _buildFooterLinkDesktop(
                context,
                'Contacto',
                _routeForPublicStore('/tienda/contacto'),
                primaryColor,
                isEditMode: isEditMode,
              ),
            ],
          ),
        ),
        SizedBox(
          width: 200,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Información',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 16),
              _buildFooterLinkDesktop(
                context,
                'Sobre Nosotros',
                '/nosotros',
                primaryColor,
                isEditMode: isEditMode,
              ),
              _buildFooterLinkDesktop(
                context,
                'Términos y Condiciones',
                '/terminos',
                primaryColor,
                isEditMode: isEditMode,
              ),
              _buildFooterLinkDesktop(
                context,
                'Política de Privacidad',
                '/privacidad',
                primaryColor,
                isEditMode: isEditMode,
              ),
              _buildFooterLinkDesktop(
                context,
                'Política de Devoluciones',
                '/devoluciones',
                primaryColor,
                isEditMode: isEditMode,
              ),
              _buildFooterLinkDesktop(
                context,
                'Envíos',
                '/envios',
                primaryColor,
                isEditMode: isEditMode,
              ),
            ],
          ),
        ),
      ];
    }

    final sectionParents = desktopItems
        .where(
          (p) => p.children
              .where((c) => c.isVisible)
              .where((c) => c.showOnDesktop)
              .isNotEmpty,
        )
        .toList();

    if (sectionParents.isNotEmpty) {
      return sectionParents.map((parent) {
        final children = parent.children
            .where((c) => c.isVisible)
            .where((c) => c.showOnDesktop)
            .toList();

        return SizedBox(
          width: 200,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                parent.label,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 16),
              for (final child in children)
                _buildFooterNavLinkDesktop(context, child,
                    isEditMode: isEditMode),
            ],
          ),
        );
      }).toList();
    }

    // Flat list
    return [
      SizedBox(
        width: 200,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Enlaces',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 16),
            for (final nav in desktopItems)
              _buildFooterNavLinkDesktop(context, nav, isEditMode: isEditMode),
          ],
        ),
      ),
    ];
  }

  Widget _buildFooterNavLinkDesktop(
    BuildContext context,
    WebsiteNavigation nav, {
    required bool isEditMode,
  }) {
    final editProvider = context.watch<WebsiteEditModeProvider>();
    final effective = editProvider.getEffectiveFooterNavItem(nav);

    final href = _routeForPublicStore(effective.href ?? '/');
    final isActive = GoRouterState.of(context).matchedLocation == href;
    final isInlineEditing = isEditMode && _activeInlineFooterNavId == nav.id;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: isInlineEditing
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.16),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 32,
                      child: TextField(
                        controller: _inlineFooterNavLabelController,
                        focusNode: _inlineFooterNavLabelFocusNode,
                        onChanged: (value) =>
                            editProvider.updateFooterNavLabel(nav.id, value),
                        cursorColor: Colors.white,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Colors.white,
                              fontWeight:
                                  isActive ? FontWeight.bold : FontWeight.w500,
                            ),
                        decoration: InputDecoration(
                          isDense: true,
                          filled: true,
                          fillColor: Colors.white.withValues(alpha: 0.10),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(6),
                            borderSide: BorderSide(
                              color: Colors.white.withValues(alpha: 0.22),
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(6),
                            borderSide: BorderSide(
                              color: Colors.white.withValues(alpha: 0.18),
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(6),
                            borderSide: BorderSide(
                              color: Colors.white.withValues(alpha: 0.42),
                              width: 1.2,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Editar destino',
                    onPressed: () => _showInlineFooterNavDestinationDialog(
                      context,
                      editProvider,
                      effective,
                    ),
                    icon: const Icon(Icons.link, size: 18, color: Colors.white),
                  ),
                  IconButton(
                    tooltip: 'Terminar',
                    onPressed: () {
                      setState(() => _activeInlineFooterNavId = null);
                      editProvider.selectFooterNavItem(null);
                    },
                    icon:
                        const Icon(Icons.check, size: 18, color: Colors.white),
                  ),
                ],
              ),
            )
          : MouseRegion(
              cursor: isEditMode ? SystemMouseCursors.click : MouseCursor.defer,
              child: InkWell(
                onTap: isEditMode
                    ? () => _beginInlineFooterNavEdit(editProvider, effective)
                    : () {
                        _navigateToHref(
                          context,
                          href,
                          openInNewTab: effective.openInNewTab,
                        );
                      },
                child: Text(
                  effective.label,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.white70,
                        fontWeight:
                            isActive ? FontWeight.bold : FontWeight.normal,
                      ),
                ),
              ),
            ),
    );
  }

  Widget _buildFooterLinkDesktop(
    BuildContext context,
    String label,
    String path,
    Color primaryColor, {
    bool forceHomeRefresh = false,
    required bool isEditMode,
  }) {
    final isActive = GoRouterState.of(context).matchedLocation == path;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: isEditMode
            ? null
            : () {
                _navigateToHref(
                  context,
                  path,
                  forceHomeRefresh: forceHomeRefresh,
                );
              },
        child: Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Colors.white70,
                fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
              ),
        ),
      ),
    );
  }

  List<Widget> _buildMobileFooterNavigationSections({
    required BuildContext context,
    required List<WebsiteNavigation> footerNavItems,
    required TextStyle? titleStyle,
    required bool isEditMode,
  }) {
    final theme = Theme.of(context);
    const dividerColor = Colors.white24;

    final mobileItems = footerNavItems
        .where((n) => n.isVisible)
        .where((n) => n.showOnMobile)
        .toList();

    if (mobileItems.isEmpty) {
      // Keep the previous UX when navigation isn't configured.
      return [
        Theme(
          data: theme.copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            title: Text('ENLACES RÁPIDOS', style: titleStyle),
            iconColor: Colors.white,
            collapsedIconColor: Colors.white,
            childrenPadding: const EdgeInsets.only(left: 16, bottom: 16),
            children: [
              _buildFooterLinkMobile(
                  context, 'Inicio', _routeForPublicStore('/tienda'),
                  isEditMode: isEditMode),
              _buildFooterLinkMobile(
                  context, 'Productos', _routeForPublicStore('/productos'),
                  isEditMode: isEditMode),
              _buildFooterLinkMobile(
                context,
                'Servicios',
                _routeForPublicStore('/servicios'),
                isEditMode: isEditMode,
              ),
              _buildFooterLinkMobile(
                  context, 'Contacto', _routeForPublicStore('/tienda/contacto'),
                  isEditMode: isEditMode),
            ],
          ),
        ),
        const Divider(color: dividerColor),
        Theme(
          data: theme.copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            title: Text('INFORMACIÓN', style: titleStyle),
            iconColor: Colors.white,
            collapsedIconColor: Colors.white,
            childrenPadding: const EdgeInsets.only(left: 16, bottom: 16),
            children: [
              _buildFooterLinkMobile(context, 'Sobre Nosotros', '/nosotros',
                  isEditMode: isEditMode),
              _buildFooterLinkMobile(
                  context, 'Términos y Condiciones', '/terminos',
                  isEditMode: isEditMode),
              _buildFooterLinkMobile(
                  context, 'Política de Devolución', '/devoluciones',
                  isEditMode: isEditMode),
            ],
          ),
        ),
        const Divider(color: dividerColor),
      ];
    }

    final sectionParents = mobileItems
        .where(
          (p) => p.children
              .where((c) => c.isVisible)
              .where((c) => c.showOnMobile)
              .isNotEmpty,
        )
        .toList();

    if (sectionParents.isNotEmpty) {
      final sections = <Widget>[];
      for (final parent in sectionParents) {
        final children = parent.children
            .where((c) => c.isVisible)
            .where((c) => c.showOnMobile)
            .toList();

        sections.add(
          Theme(
            data: theme.copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              title: Text(parent.label.toUpperCase(), style: titleStyle),
              iconColor: Colors.white,
              collapsedIconColor: Colors.white,
              childrenPadding: const EdgeInsets.only(left: 16, bottom: 16),
              children: [
                for (final child in children)
                  _buildFooterNavLinkMobile(
                    context,
                    child,
                    isEditMode: isEditMode,
                  ),
              ],
            ),
          ),
        );
        sections.add(const Divider(color: dividerColor));
      }

      return sections;
    }

    return [
      Theme(
        data: theme.copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          title: Text('ENLACES', style: titleStyle),
          iconColor: Colors.white,
          collapsedIconColor: Colors.white,
          childrenPadding: const EdgeInsets.only(left: 16, bottom: 16),
          children: [
            for (final nav in mobileItems)
              _buildFooterNavLinkMobile(
                context,
                nav,
                isEditMode: isEditMode,
              ),
          ],
        ),
      ),
      const Divider(color: dividerColor),
    ];
  }

  Widget _buildFooterNavLinkMobile(
    BuildContext context,
    WebsiteNavigation nav, {
    required bool isEditMode,
  }) {
    final editProvider = context.watch<WebsiteEditModeProvider>();
    final effective = editProvider.getEffectiveFooterNavItem(nav);

    final href = _routeForPublicStore(effective.href ?? '/');
    final isInlineEditing = isEditMode && _activeInlineFooterNavId == nav.id;

    if (!isEditMode) {
      return _buildFooterLinkMobile(
        context,
        effective.label,
        href,
        isEditMode: false,
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: isInlineEditing
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.16),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _inlineFooterNavLabelController,
                      focusNode: _inlineFooterNavLabelFocusNode,
                      onChanged: (value) =>
                          editProvider.updateFooterNavLabel(nav.id, value),
                      cursorColor: Colors.white,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: Colors.white),
                      decoration: InputDecoration(
                        isDense: true,
                        filled: true,
                        fillColor: Colors.white.withValues(alpha: 0.10),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                          borderSide: BorderSide(
                            color: Colors.white.withValues(alpha: 0.22),
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                          borderSide: BorderSide(
                            color: Colors.white.withValues(alpha: 0.18),
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                          borderSide: BorderSide(
                            color: Colors.white.withValues(alpha: 0.42),
                            width: 1.2,
                          ),
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Destino',
                    onPressed: () => _showInlineFooterNavDestinationDialog(
                      context,
                      editProvider,
                      effective,
                    ),
                    icon: const Icon(Icons.link, size: 18, color: Colors.white),
                  ),
                  IconButton(
                    tooltip: 'OK',
                    onPressed: () {
                      setState(() => _activeInlineFooterNavId = null);
                      editProvider.selectFooterNavItem(null);
                    },
                    icon:
                        const Icon(Icons.check, size: 18, color: Colors.white),
                  ),
                ],
              ),
            )
          : InkWell(
              onTap: () => _beginInlineFooterNavEdit(editProvider, effective),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    const Icon(Icons.edit, size: 14, color: Colors.white70),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        effective.label,
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: Colors.white70),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildLogo({
    required BuildContext context,
    required String logoUrl,
    required String storeName,
    required Color textColor,
    required bool isDarkMode,
    double height = 48,
    Alignment alignment = Alignment.center,
  }) {
    Widget applyContrast(Widget child) {
      if (!isDarkMode) return child;
      return ColorFiltered(
        colorFilter: ColorFilter.mode(textColor, BlendMode.srcIn),
        child: child,
      );
    }

    // 1. Try Network URL if available
    if (logoUrl.isNotEmpty) {
      return Container(
        height: height,
        alignment: alignment,
        child: applyContrast(
          Image.network(
            logoUrl,
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) {
              // 2. Fallback to Local Asset
              return Image.asset(
                'assets/images/vinabike_logo.png',
                fit: BoxFit.contain,
                height: height,
                errorBuilder: (context, error, stackTrace) {
                  // 3. Fallback to Text
                  return _buildTextLogo(context, storeName, textColor);
                },
              );
            },
          ),
        ),
      );
    }

    // 2. Fallback to Local Asset (if no URL)
    return Container(
      height: height,
      alignment: alignment,
      child: applyContrast(
        Image.asset(
          'assets/images/vinabike_logo.png',
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) {
            // 3. Fallback to Text
            return _buildTextLogo(context, storeName, textColor);
          },
        ),
      ),
    );
  }

  Widget _buildTextLogo(
      BuildContext context, String storeName, Color primaryColor) {
    return Text(
      storeName.isNotEmpty ? storeName.toUpperCase() : 'MI TIENDA',
      style: Theme.of(context).textTheme.headlineMedium?.copyWith(
            color: primaryColor,
            fontWeight: FontWeight.bold,
            letterSpacing: 1,
          ),
    );
  }

  Widget _buildNavLink(
    BuildContext context,
    String label,
    String path,
    Color primaryColor, {
    bool forceHomeRefresh = false,
    bool isEditMode = false,
  }) {
    final isActive = GoRouterState.of(context).matchedLocation == path;

    return InkWell(
      onTap: isEditMode
          ? null
          : () {
              _navigateToHref(
                context,
                path,
                forceHomeRefresh: forceHomeRefresh,
              );
            },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 5),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: isActive ? primaryColor : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontFamily: null,
                fontSize: 14,
                letterSpacing: 0.1,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                color: isActive
                    ? primaryColor
                    : (primaryColor == Colors.white
                        ? Colors.white
                        : PublicStoreTheme.textPrimary),
              ),
        ),
      ),
    );
  }

  Future<void> _navigateToHref(
    BuildContext context,
    String href, {
    bool openInNewTab = false,
    bool forceHomeRefresh = false,
  }) async {
    final normalized = href.trim();
    if (normalized.isEmpty) return;

    // IMPORTANT: Ensure any open mega menu is closed before navigating.
    // This resets the header background color (which turns black when menu is open).
    MegaMenuController.instance.closeMenu();

    // Sometimes website blocks/navigation store a bare UUID as a link target.
    // This can be either a product id OR a website_pages.id. Normalize to a
    // real route so we don't hit go_router 404s.
    final uuidRe = RegExp(
      r'^[0-9a-fA-F]{8}-'
      r'[0-9a-fA-F]{4}-'
      r'[0-9a-fA-F]{4}-'
      r'[0-9a-fA-F]{4}-'
      r'[0-9a-fA-F]{12}$',
    );
    String internalHref = normalized;
    String? uuid;
    if (uuidRe.hasMatch(internalHref)) {
      uuid = internalHref;
    } else if (internalHref.startsWith('/') &&
        uuidRe.hasMatch(internalHref.substring(1))) {
      uuid = internalHref.substring(1);
    }

    if (uuid != null) {
      // 1) Prefer resolving UUID as a website page id.
      final websiteService = context.read<WebsiteService>();
      final tenantProvider = context.read<PublicStoreTenantProvider>();
      final tenantId = tenantProvider.tenantId;

      // Pages might not be loaded in some boot paths (we always have settings,
      // but pages are loaded lazily). Load them on demand for UUID links.
      if (websiteService.pages.isEmpty && tenantId != null) {
        await websiteService.loadPagesForTenant(tenantId);
      }

      final page = websiteService.pages.cast<WebsitePage?>().firstWhere(
            (p) => p?.id == uuid,
            orElse: () => null,
          );

      // If not found in memory, try a direct lookup (covers stale caches).
      final resolvedPage = page ?? await websiteService.getPageById(uuid);
      if (!context.mounted) return;

      final slug = (resolvedPage != null &&
              (tenantId == null || resolvedPage.tenantId == tenantId))
          ? resolvedPage.slug
          : null;
      if (slug != null && slug.trim().isNotEmpty) {
        final s = slug.trim();

        // Map common system slugs to canonical routes.
        const directSlugs = <String>{
          'productos',
          'contacto',
          'nosotros',
          'terminos',
          'privacidad',
          'devoluciones',
          'envios',
          'carrito',
          'checkout',
          'cuenta',
        };

        if (s == 'inicio' || s == 'home') {
          internalHref = '/';
        } else if (directSlugs.contains(s)) {
          internalHref = '/$s';
        } else {
          internalHref = '/pagina/$s';
        }
      } else {
        // 2) Fallback: treat UUID as a product id.
        internalHref = '/productos/$uuid';
      }
    }

    // External URLs
    if (normalized.startsWith('http://') || normalized.startsWith('https://')) {
      final uri = Uri.tryParse(normalized);
      if (uri != null) {
        await launchUrl(
          uri,
          mode: LaunchMode.platformDefault,
          webOnlyWindowName: openInNewTab ? '_blank' : '_self',
        );
      }
      return;
    }

    // Anchor links (best-effort on web)
    if (normalized.startsWith('#')) {
      if (kIsWeb) {
        setLocationHash(normalized);
      }
      return;
    }

    // Normalize internal relative paths like 'productos' to '/productos'.
    // Some CMS/DB-stored links omit the leading '/', which can lead to
    // inconsistent URL updates on web.
    final parsedInternal = Uri.tryParse(internalHref);
    if (parsedInternal != null &&
        parsedInternal.scheme.isEmpty &&
        internalHref.isNotEmpty &&
        !internalHref.startsWith('/') &&
        !internalHref.startsWith('?')) {
      internalHref = '/$internalHref';
    }

    // Normalize common "home" aliases so they behave like a real home
    // navigation (including scroll-to-top behavior).
    final internalPath =
        (Uri.tryParse(internalHref)?.path ?? internalHref).trim().toLowerCase();
    if (internalPath == '/inicio' || internalPath == '/home') {
      internalHref = '/';
    } else if (internalPath == '/tienda/inicio' ||
        internalPath == '/tienda/home') {
      internalHref = '/tienda';
    }

    // Re-normalize the internal route against the current runtime.
    // This is critical in preview/editor contexts where callers may pass a
    // clean store route (`/`) while the ERP-mounted shell actually needs
    // `/tienda`, or vice versa.
    internalHref = _routeForPublicStore(internalHref);

    // Internal navigation
    final editProvider = context.read<WebsiteEditModeProvider>();
    final currentUri = GoRouterState.of(context).uri;
    final isEditMode =
        editProvider.isEditMode || currentUri.queryParameters['edit'] == 'true';
    final isPreviewMode = !isEditMode &&
        (editProvider.isPreviewMode ||
            currentUri.queryParameters['preview'] == 'true');

    final targetUri = Uri.tryParse(internalHref);
    var target = internalHref;
    if (targetUri != null && targetUri.scheme.isEmpty) {
      final nextQuery = Map<String, String>.from(targetUri.queryParameters);
      nextQuery.remove('edit');
      nextQuery.remove('preview');

      if (isEditMode) {
        nextQuery['edit'] = 'true';
      } else if (isPreviewMode) {
        nextQuery['preview'] = 'true';
      }

      target = targetUri
          .replace(queryParameters: nextQuery.isEmpty ? null : nextQuery)
          .toString();
    }

    // Avoid redundant navigation.
    final current = GoRouterState.of(context).uri.toString();

    // Prefer go() for top-level navigation (header/footer) on web to avoid
    // stacking routes (Navigator keeps prior routes offstage, which can
    // exacerbate "RenderBox was not laid out" failures and lead to blank
    // frames). Keep push() for detail routes like product pages.
    final targetPath = Uri.tryParse(target)?.path ?? target;
    final isHomeTarget = targetPath == '/' ||
        targetPath == '/tienda' ||
        targetPath == '/tienda/';
    final shouldReplace = _shouldReplaceForPublicStoreNav(targetPath);

    // Web-only: if the user explicitly asked for a "home refresh" (logo/Inicio)
    // behave like a traditional website and force a full page reload.
    // This avoids cases where soft-refresh signals are imperceptible due to
    // caching or when the route doesn't change (already on home).
    if (kIsWeb && forceHomeRefresh && isHomeTarget && !isEditMode) {
      try {
        final currentPath = Uri.parse(web.window.location.href).path;
        final desiredPath = targetPath.isEmpty ? '/' : targetPath;

        if (currentPath == desiredPath) {
          web.window.location.reload();
        } else {
          // Navigate + reload in one step.
          web.window.location.assign(target);
        }
        return;
      } catch (e) {
        // Fallback for non-web platforms - just navigate normally
      }
    }

    // If we're already on the target route, still honor explicit "home"
    // navigations (logo / Inicio) by scrolling to top.
    if (current == target) {
      if (shouldReplace) {
        context.read<PublicStoreScrollState>().requestScrollToTop(target);
        context
            .read<PublicStoreScrollState>()
            .requestScrollToTopForPath(targetPath);
      }

      if (isHomeTarget) {
        context.read<PublicStoreScrollState>().requestScrollToTopForPath('/');
        context
            .read<PublicStoreScrollState>()
            .requestScrollToTopForPath('/tienda');
      }

      if (forceHomeRefresh && isHomeTarget) {
        context.read<PublicStoreScrollState>().requestHomeRefresh();
      }
      return;
    }

    if (shouldReplace) {
      // Explicit "home" navigations (logo / Inicio) should land at the top,
      // even if we pop-to-root (which would otherwise preserve scroll).
      context.read<PublicStoreScrollState>().requestScrollToTop(target);
      context
          .read<PublicStoreScrollState>()
          .requestScrollToTopForPath(targetPath);

      if (isHomeTarget) {
        context.read<PublicStoreScrollState>().requestScrollToTopForPath('/');
        context
            .read<PublicStoreScrollState>()
            .requestScrollToTopForPath('/tienda');
      }

      if (forceHomeRefresh) {
        context.read<PublicStoreScrollState>().requestHomeRefresh();
      }

      // For home navigation, always use go() directly instead of the pop loop.
      // The pop-to-root approach was causing blank screen issues on production
      // because the context becomes invalid after multiple pops, and the
      // postFrameCallback couldn't reliably navigate to the target.
      // Using go() directly is more reliable and handles the browser history
      // correctly on web.
      context.go(target);
    } else {
      context.push(target);
    }
  }

  bool _shouldReplaceForPublicStoreNav(String path) {
    final p = path.trim().toLowerCase();
    if (p.isEmpty) return true;

    // Normalize legacy ERP-mounted store routes.
    var normalized = p;
    if (normalized == '/tienda') return true;
    if (normalized == '/tienda/') return true;
    if (normalized.startsWith('/tienda/')) {
      normalized = normalized.substring('/tienda'.length);
      if (normalized.isEmpty) normalized = '/';
    }

    // Home
    if (normalized == '/') return true;

    // Product list is top-level; product detail should remain push().
    if (normalized == '/productos') return true;
    if (normalized == '/servicios') return true;
    if (normalized.startsWith('/productos/')) return false;

    // Top-level pages
    const topLevelExact = <String>{
      '/contacto',
      '/carrito',
      '/checkout',
      '/cuenta',
      '/cuenta/login',
      '/nosotros',
      '/terminos',
      '/privacidad',
      '/devoluciones',
      '/envios',
    };
    if (topLevelExact.contains(normalized)) return true;

    // Custom pages
    if (normalized.startsWith('/pagina/')) return true;

    return false;
  }

  Widget _buildNavItemLink(
    BuildContext context,
    WebsiteNavigation nav,
    Color primaryColor, {
    bool isEditMode = false,
  }) {
    final href = _routeForPublicStore(nav.href ?? '/');
    final isActive = GoRouterState.of(context).matchedLocation == href;

    return InkWell(
      onTap: isEditMode
          ? null
          : () {
              _navigateToHref(context, href, openInNewTab: nav.openInNewTab);
            },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 5),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: isActive ? primaryColor : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Text(
          nav.label,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontSize: 14,
                letterSpacing: 0.1,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                color: isActive
                    ? primaryColor
                    : (primaryColor == Colors.white
                        ? Colors.white
                        : PublicStoreTheme.textPrimary),
              ),
        ),
      ),
    );
  }

  void _showMobileMenu(BuildContext context, List<WebsiteNavigation> navItems) {
    // IMPORTANT: The bottom-sheet builder gets its own BuildContext. After
    // `Navigator.pop(sheetContext)`, that context can be disposed; using it for
    // navigation can make taps appear to do nothing (especially on mobile).
    final navContext = context;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) {
        // Access provider here inside the builder to ensure we have context.
        final accountService = sheetContext.watch<CustomerAccountService>();
        final isAuthenticated = accountService.isAuthenticated;

        return Container(
          decoration: const BoxDecoration(
            color: Color(0xFF1a1a1a),
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Handle bar
                Container(
                  margin: const EdgeInsets.only(top: 12),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 24),
                // Account Section (Top)
                if (isAuthenticated) ...[
                  _buildMobileMenuItem(
                    sheetContext,
                    icon: Icons.person_rounded,
                    label: 'Mi Cuenta',
                    onTap: () {
                      Navigator.pop(sheetContext);
                      _navigateToHref(
                        navContext,
                        _routeForPublicStore('/tienda/cuenta'),
                      );
                    },
                  ),
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                    child: Divider(color: Colors.white.withValues(alpha: 0.2)),
                  ),
                ] else ...[
                  _buildMobileMenuItem(
                    sheetContext,
                    icon: Icons.login_rounded,
                    label: 'Iniciar Sesión',
                    color: PublicStoreTheme.primaryBlue,
                    onTap: () {
                      Navigator.pop(sheetContext);
                      _navigateToHref(
                        navContext,
                        _routeForPublicStore('/tienda/cuenta/login'),
                      );
                    },
                  ),
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                    child: Divider(color: Colors.white.withValues(alpha: 0.2)),
                  ),
                ],

                // Navigation items
                if (navItems.isEmpty) ...[
                  _buildMobileMenuItem(
                    sheetContext,
                    icon: Icons.home_rounded,
                    label: 'Inicio',
                    onTap: () {
                      Navigator.pop(sheetContext);
                      _navigateToHref(
                        navContext,
                        _routeForPublicStore('/tienda'),
                      );
                    },
                  ),
                  _buildMobileMenuItem(
                    sheetContext,
                    icon: Icons.shopping_bag_rounded,
                    label: 'Productos',
                    onTap: () {
                      Navigator.pop(sheetContext);
                      _navigateToHref(
                        navContext,
                        _routeForPublicStore('/productos'),
                      );
                    },
                  ),
                  _buildMobileMenuItem(
                    sheetContext,
                    icon: Icons.mail_rounded,
                    label: 'Contacto',
                    onTap: () {
                      Navigator.pop(sheetContext);
                      _navigateToHref(
                        navContext,
                        _routeForPublicStore('/tienda/contacto'),
                      );
                    },
                  ),
                ] else ...[
                  ...navItems
                      .where((n) => n.isVisible)
                      .where((n) => n.showOnMobile)
                      .expand((nav) {
                    final children = nav.children
                        .where((c) => c.isVisible)
                        .where((c) => c.showOnMobile)
                        .toList()
                      ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));

                    final items = <Widget>[
                      _buildMobileMenuItem(
                        sheetContext,
                        icon: Icons.arrow_forward_ios_rounded,
                        label: nav.label,
                        onTap: () {
                          Navigator.pop(sheetContext);
                          final href = _routeForPublicStore(nav.href ?? '/');
                          _navigateToHref(
                            navContext,
                            href,
                            openInNewTab: nav.openInNewTab,
                          );
                        },
                      ),
                    ];

                    for (final child in children) {
                      items.add(
                        _buildMobileMenuItem(
                          sheetContext,
                          icon: Icons.subdirectory_arrow_right_rounded,
                          label: child.label,
                          onTap: () {
                            Navigator.pop(sheetContext);
                            final href =
                                _routeForPublicStore(child.href ?? '/');
                            _navigateToHref(
                              navContext,
                              href,
                              openInNewTab: child.openInNewTab,
                            );
                          },
                        ),
                      );
                    }

                    return items;
                  }),
                ],

                // Logout at bottom (only if authenticated)
                if (isAuthenticated) ...[
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                    child: Divider(color: Colors.white.withValues(alpha: 0.2)),
                  ),
                  _buildMobileMenuItem(
                    sheetContext,
                    icon: Icons.logout_rounded,
                    label: 'Cerrar Sesión',
                    color: Colors.redAccent,
                    onTap: () async {
                      Navigator.pop(sheetContext);
                      await accountService.signOut();
                      if (navContext.mounted) {
                        ScaffoldMessenger.of(navContext).showSnackBar(
                          const SnackBar(
                            content: Text('Sesión cerrada correctamente'),
                            backgroundColor: Colors.green,
                          ),
                        );
                        navContext.go('/');
                      }
                    },
                  ),
                ],
                const SizedBox(height: 24),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildMobileMenuItem(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color? color,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        splashColor: Colors.white12,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Row(
            children: [
              Icon(icon, color: color ?? Colors.white70, size: 22),
              const SizedBox(width: 16),
              Text(
                label,
                style: TextStyle(
                  fontFamily: null,
                  color: color ?? Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.2,
                ),
              ),
              const Spacer(),
              const Icon(Icons.chevron_right_rounded,
                  color: Colors.white38, size: 20),
            ],
          ),
        ),
      ),
    );
  }

  void _openConfigHub(_EditorConfigHubTab tab) {
    context
        .read<WebsiteEditModeProvider>()
        .openWorkspace(_workspaceModeForConfigTab(tab));
    setState(() {
      _configHubTab = tab;
      _isConfigHubOpen = true;
    });
  }

  void _openWorkspacePanel(WebsiteWorkspacePanel panel) {
    switch (panel) {
      case WebsiteWorkspacePanel.pages:
        _openConfigHub(_EditorConfigHubTab.sitePages);
        return;
      case WebsiteWorkspacePanel.navigation:
        _openConfigHub(_EditorConfigHubTab.siteNavigation);
        return;
      case WebsiteWorkspacePanel.destinations:
        _openConfigHub(_EditorConfigHubTab.siteDestinations);
        return;
      case WebsiteWorkspacePanel.catalogProducts:
        setState(() => _catalogTab = _EditorCatalogTab.products);
        _openConfigHub(_EditorConfigHubTab.ecomCatalog);
        return;
      case WebsiteWorkspacePanel.catalogCategories:
        setState(() {
          _catalogTab = _EditorCatalogTab.categories;
          _categoryTab = _EditorCategoryTab.publication;
        });
        _openConfigHub(_EditorConfigHubTab.ecomCatalog);
        return;
    }
  }

  void _closeConfigHub() {
    context.read<WebsiteEditModeProvider>().returnToPageEditor();
    if (_isConfigHubOpen) {
      setState(() => _isConfigHubOpen = false);
    }
  }

  WebsiteWorkspaceMode _workspaceModeForConfigTab(_EditorConfigHubTab tab) {
    switch (tab) {
      case _EditorConfigHubTab.ecomCatalog:
        return WebsiteWorkspaceMode.catalog;
      case _EditorConfigHubTab.sitePages:
      case _EditorConfigHubTab.siteNavigation:
      case _EditorConfigHubTab.siteDestinations:
        return WebsiteWorkspaceMode.structure;
      case _EditorConfigHubTab.siteSettings:
      case _EditorConfigHubTab.seo:
      case _EditorConfigHubTab.integrations:
      case _EditorConfigHubTab.paymentMethods:
      case _EditorConfigHubTab.domain:
        return WebsiteWorkspaceMode.settings;
      case _EditorConfigHubTab.siteHub:
      case _EditorConfigHubTab.ecomOrders:
      case _EditorConfigHubTab.reportsAnalytics:
        return WebsiteWorkspaceMode.operations;
    }
  }

  Widget _buildConfigHubOverlay() {
    final theme = Theme.of(context);

    Widget buildBody() {
      if (_configHubTab == _EditorConfigHubTab.domain) {
        return _buildDomainAndUrlPanel();
      }

      return FutureBuilder(
        future: _ensureErpLibraryLoaded(),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(
              child: SizedBox(
                width: 40,
                height: 40,
                child: CircularProgressIndicator(),
              ),
            );
          }

          switch (_configHubTab) {
            // Site
            case _EditorConfigHubTab.siteHub:
              return erp.WebsiteManagementPage(embedded: true);
            case _EditorConfigHubTab.sitePages:
              return erp.PageManagementPage(embedded: true);
            case _EditorConfigHubTab.siteNavigation:
              return erp.NavigationManagementPage(embedded: true);
            case _EditorConfigHubTab.siteDestinations:
              return erp.WebsiteDestinationManagementPage(
                embedded: true,
                onOpenPages: () =>
                    _openConfigHub(_EditorConfigHubTab.sitePages),
                onOpenNavigation: () =>
                    _openConfigHub(_EditorConfigHubTab.siteNavigation),
                onOpenCatalogProducts: () {
                  setState(() => _catalogTab = _EditorCatalogTab.products);
                  _openConfigHub(_EditorConfigHubTab.ecomCatalog);
                },
                onOpenCatalogCategories: () {
                  setState(() {
                    _catalogTab = _EditorCatalogTab.categories;
                    _categoryTab = _EditorCategoryTab.publication;
                  });
                  _openConfigHub(_EditorConfigHubTab.ecomCatalog);
                },
              );
            case _EditorConfigHubTab.siteSettings:
              return erp.WebsiteSettingsPage(embedded: true);

            // E-commerce
            case _EditorConfigHubTab.ecomCatalog:
              return _buildCatalogWorkspace(theme);
            case _EditorConfigHubTab.ecomOrders:
              return erp.OnlineOrdersPage(embedded: true);

            // Reports
            case _EditorConfigHubTab.reportsAnalytics:
              return erp.AnalyticsDashboardPage(
                dashboardUrl: 'https://analytics.google.com',
                embedded: true,
              );

            // Config
            case _EditorConfigHubTab.seo:
              return erp.SeoSettingsPage(embedded: true);
            case _EditorConfigHubTab.integrations:
              return erp.IntegrationsPage(embedded: true);
            case _EditorConfigHubTab.paymentMethods:
              return erp.PaymentMethodsSettingsPage(embedded: true);
            case _EditorConfigHubTab.domain:
              // Handled above.
              return const SizedBox.shrink();
          }
        },
      );
    }

    return Material(
      color: theme.colorScheme.surface,
      child: Column(
        children: [
          Container(
            height: 52,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: theme.dividerColor),
              ),
            ),
            child: Row(
              children: [
                TextButton.icon(
                  icon: const Icon(Icons.arrow_back, size: 18),
                  label: const Text('Volver al editor'),
                  onPressed: _closeConfigHub,
                ),
                const SizedBox(width: 12),
                SizedBox(
                  height: 24,
                  child: VerticalDivider(color: theme.dividerColor),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _configHubTab.title,
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Builder(
                  builder: (context) {
                    final editProvider =
                        context.watch<WebsiteEditModeProvider>();
                    if (!editProvider.hasUnsavedChanges) {
                      return const SizedBox.shrink();
                    }
                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.tertiaryContainer,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'Borrador de página preservado',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onTertiaryContainer,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          Expanded(
            child: buildBody(),
          ),
        ],
      ),
    );
  }

  Widget _buildCatalogWorkspace(ThemeData theme) {
    final selectedSection = _catalogTab == _EditorCatalogTab.categories
        ? erp.WebsiteCatalogSection.categories
        : erp.WebsiteCatalogSection.products;

    Widget body;
    if (_catalogTab == _EditorCatalogTab.featured) {
      body = erp.FeaturedProductsPage(embedded: true);
    } else if (_catalogTab == _EditorCatalogTab.categories &&
        _categoryTab == _EditorCategoryTab.structure) {
      body = erp.HierarchicalCategoryPage(embedded: true);
    } else {
      body = erp.ProductWebsiteVisibilityPage(
        embedded: true,
        section: selectedSection,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            border: Border(
              bottom: BorderSide(color: theme.colorScheme.outlineVariant),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Catálogo web',
                          style: theme.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Publica productos, categorías y la colección destacada desde un solo lugar.',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  SegmentedButton<_EditorCatalogTab>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(
                        value: _EditorCatalogTab.products,
                        icon: Icon(Icons.inventory_2_outlined, size: 17),
                        label: Text('Productos'),
                      ),
                      ButtonSegment(
                        value: _EditorCatalogTab.categories,
                        icon: Icon(Icons.category_outlined, size: 17),
                        label: Text('Categorías'),
                      ),
                      ButtonSegment(
                        value: _EditorCatalogTab.featured,
                        icon: Icon(Icons.star_outline, size: 17),
                        label: Text('Destacados'),
                      ),
                    ],
                    selected: {_catalogTab},
                    onSelectionChanged: (selection) {
                      setState(() => _catalogTab = selection.first);
                    },
                    style: const ButtonStyle(
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ],
              ),
              if (_catalogTab == _EditorCatalogTab.categories) ...[
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerRight,
                  child: SegmentedButton<_EditorCategoryTab>(
                    showSelectedIcon: false,
                    style: const ButtonStyle(
                      visualDensity: VisualDensity.compact,
                    ),
                    segments: const [
                      ButtonSegment(
                        value: _EditorCategoryTab.publication,
                        label: Text('Publicación web'),
                      ),
                      ButtonSegment(
                        value: _EditorCategoryTab.structure,
                        label: Text('Estructura y nombres'),
                      ),
                    ],
                    selected: {_categoryTab},
                    onSelectionChanged: (selection) {
                      setState(() => _categoryTab = selection.first);
                    },
                  ),
                ),
              ],
            ],
          ),
        ),
        Expanded(child: body),
      ],
    );
  }

  Widget _buildDomainAndUrlPanel() {
    // Reuse the same data shown in the dialog, but as an inline panel.
    final websiteService = context.read<WebsiteService>();
    final url = _resolvePublicStoreUrl(websiteService);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Dominio y URL',
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Administra tu URL pública. (La configuración de dominio se gestiona en Firebase Hosting / DNS).',
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: SelectableText(
                          url ?? 'No se pudo determinar la URL pública',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                      const SizedBox(width: 12),
                      OutlinedButton.icon(
                        onPressed: url == null
                            ? null
                            : () async {
                                await launchUrl(
                                  Uri.parse(url),
                                  mode: LaunchMode.externalApplication,
                                );
                              },
                        icon: const Icon(Icons.open_in_new),
                        label: const Text('Abrir'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: url == null
                        ? null
                        : () async {
                            await _copyToClipboard(url);
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('URL copiada'),
                                ),
                              );
                            }
                          },
                    icon: const Icon(Icons.copy),
                    label: const Text('Copiar URL'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

enum _EditorCatalogTab { products, categories, featured }

enum _EditorCategoryTab { publication, structure }

enum _EditorConfigHubTab {
  // Site
  siteHub,
  sitePages,
  siteNavigation,
  siteDestinations,
  siteSettings,

  // E-commerce
  ecomCatalog,
  ecomOrders,

  // Reports
  reportsAnalytics,

  // Config
  domain,
  seo,
  integrations,
  paymentMethods,
}

extension on _EditorConfigHubTab {
  String get title {
    switch (this) {
      case _EditorConfigHubTab.siteHub:
        return 'Sitio web';
      case _EditorConfigHubTab.sitePages:
        return 'Páginas';
      case _EditorConfigHubTab.siteNavigation:
        return 'Navegación';
      case _EditorConfigHubTab.siteDestinations:
        return 'Destinos y enlaces';
      case _EditorConfigHubTab.siteSettings:
        return 'Ajustes del sitio';
      case _EditorConfigHubTab.ecomCatalog:
        return 'Catálogo web';
      case _EditorConfigHubTab.ecomOrders:
        return 'Pedidos online';
      case _EditorConfigHubTab.reportsAnalytics:
        return 'Analytics (Google)';
      case _EditorConfigHubTab.domain:
        return 'Dominio y URL';
      case _EditorConfigHubTab.seo:
        return 'Ajustes del sitio (SEO / contacto)';
      case _EditorConfigHubTab.integrations:
        return 'Integraciones (Google Merchant)';
      case _EditorConfigHubTab.paymentMethods:
        return 'Métodos de pago';
    }
  }
}

Future<void> _launchUri(Uri uri) async {
  if (await canLaunchUrl(uri)) {
    await launchUrl(uri, mode: LaunchMode.platformDefault);
  }
}

String? _buildSocialUrl(String handle, String baseUrl) {
  final trimmed = handle.trim();
  if (trimmed.isEmpty) {
    return null;
  }
  if (trimmed.startsWith('http')) {
    return trimmed;
  }
  return '$baseUrl${trimmed.replaceAll('@', '')}';
}

String _sanitizePhone(String input) {
  final digits = input.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.isEmpty) {
    return '';
  }
  if (digits.startsWith('56')) {
    return digits;
  }
  if (digits.length == 9 && digits.startsWith('9')) {
    return '56$digits';
  }
  if (digits.length == 8) {
    return '56$digits';
  }
  return digits;
}

Color _resolveColor(String raw, Color fallback) {
  final value = raw.trim();
  if (value.isEmpty) return fallback;

  Color? parsed;
  int? intValue;

  String cleaned = value.toLowerCase();
  if (cleaned.startsWith('color(')) {
    final inside = cleaned.replaceAll(RegExp(r'color\(|\)'), '');
    intValue = int.tryParse(inside);
  }

  intValue ??= int.tryParse(cleaned);
  if (intValue == null && cleaned.startsWith('0x')) {
    intValue = int.tryParse(cleaned);
  }
  if (intValue == null) {
    cleaned = cleaned.replaceAll('#', '');
    intValue = int.tryParse(cleaned, radix: 16);
    if (intValue != null && cleaned.length <= 6) {
      intValue = 0xFF000000 | intValue;
    }
  }

  if (intValue != null) {
    parsed = Color(intValue);
  }

  return parsed ?? fallback;
}

class _PreviewNavAction {
  final String? id;
  final String? label;
  final IconData? icon;
  final bool isDivider;

  const _PreviewNavAction({
    required this.id,
    required this.label,
    required this.icon,
  }) : isDivider = false;

  const _PreviewNavAction.divider()
      : id = null,
        label = null,
        icon = null,
        isDivider = true;
}

enum _PageNavKind {
  core,
  published,
  draft,
  legal,
  system,
}

class _PageNavTarget {
  final String key;
  final String title;
  final String href;
  final _PageNavKind kind;
  final String? subtitle;
  final bool? isPublished;

  const _PageNavTarget({
    required this.key,
    required this.title,
    required this.href,
    required this.kind,
    this.subtitle,
    this.isPublished,
  });

  _PageNavTarget copyWith({
    String? key,
    String? title,
    String? href,
    _PageNavKind? kind,
    String? subtitle,
    bool? isPublished,
  }) {
    return _PageNavTarget(
      key: key ?? this.key,
      title: title ?? this.title,
      href: href ?? this.href,
      kind: kind ?? this.kind,
      subtitle: subtitle ?? this.subtitle,
      isPublished: isPublished ?? this.isPublished,
    );
  }
}

class _PageNavigatorDialog extends StatefulWidget {
  const _PageNavigatorDialog({
    required this.initialSlug,
    required this.targets,
    required this.onCopyLink,
    required this.onOpenNewTab,
  });

  final String initialSlug;
  final List<_PageNavTarget> targets;
  final Future<void> Function() onCopyLink;
  final Future<void> Function() onOpenNewTab;

  @override
  State<_PageNavigatorDialog> createState() => _PageNavigatorDialogState();
}

class _PageNavigatorDialogState extends State<_PageNavigatorDialog> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      final next = _searchController.text.trim().toLowerCase();
      if (next == _query) return;
      setState(() => _query = next);
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Only used for logic not for UI colors anymore as we hardcode dark theme
    // final theme = Theme.of(context);

    // Filter items based on search query
    // The items are already sorted by the caller (Core -> Published -> Draft -> Legal -> System) + Alphabetical
    final filtered = _query.isEmpty
        ? widget.targets
        : widget.targets.where((t) {
            final hay = '${t.title} ${t.subtitle ?? ''}'.toLowerCase();
            return hay.contains(_query);
          }).toList();

    bool isCurrent(_PageNavTarget t) {
      final currentSlug = widget.initialSlug;
      if (currentSlug.isEmpty) return t.key == 'home';
      return t.key == currentSlug;
    }

    // Dark theme for the editor dialog
    return Theme(
      data: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF1E1E1E),
        dividerColor: Colors.white.withValues(alpha: 0.1),
        textTheme: const TextTheme(
          titleMedium: TextStyle(
              color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
          bodyMedium: TextStyle(color: Colors.white70),
        ),
        iconTheme: const IconThemeData(color: Colors.white70),
      ),
      child: Scaffold(
        backgroundColor: const Color(0xFF1E1E1E),
        appBar: AppBar(
          backgroundColor: const Color(0xFF1E1E1E),
          elevation: 0,
          leading: IconButton(
            tooltip: 'Cerrar',
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close),
          ),
          title: const Text('Ir a página'),
          centerTitle: true,
          shape: Border(
            bottom: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
          ),
          actions: [
            IconButton(
              tooltip: 'Copiar enlace',
              onPressed: widget.onCopyLink,
              icon: const Icon(Icons.copy, size: 20),
            ),
            IconButton(
              tooltip: 'Abrir en nueva pestaña',
              onPressed: widget.onOpenNewTab,
              icon: const Icon(Icons.open_in_new, size: 20),
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                controller: _searchController,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search, color: Colors.white54),
                  hintText: 'Buscar páginas (título o ruta)',
                  hintStyle: const TextStyle(color: Colors.white38),
                  isDense: true,
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.1),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
              ),
            ),
            Expanded(
              child: filtered.isEmpty
                  ? Center(
                      child: Text(
                        'No hay resultados',
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.5)),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.only(bottom: 20),
                      // Simply use the filtered list which is already sorted
                      itemCount: filtered.length,
                      itemBuilder: (context, index) {
                        final t = filtered[index];
                        final current = isCurrent(t);

                        return InkWell(
                          onTap: () => Navigator.of(context).pop(t),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 20, vertical: 12),
                            decoration: BoxDecoration(
                              border: Border(
                                bottom: BorderSide(
                                  color: Colors.white.withValues(alpha: 0.05),
                                ),
                              ),
                              color: current
                                  ? const Color(0xFF00A09D)
                                      .withValues(alpha: 0.15)
                                  : Colors.transparent,
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  current
                                      ? Icons.check_circle
                                      : Icons.circle_outlined,
                                  size: 18,
                                  color: current
                                      ? const Color(0xFF00A09D)
                                      : Colors.white38,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        t.title,
                                        style: TextStyle(
                                          color: current
                                              ? const Color(0xFF00A09D)
                                              : Colors.white,
                                          fontWeight: current
                                              ? FontWeight.w600
                                              : FontWeight.normal,
                                        ),
                                      ),
                                      if (t.subtitle != null)
                                        Padding(
                                          padding:
                                              const EdgeInsets.only(top: 2),
                                          child: Text(
                                            t.subtitle!,
                                            style: TextStyle(
                                              color: current
                                                  ? const Color(0xFF00A09D)
                                                      .withValues(alpha: 0.7)
                                                  : Colors.white38,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                if (t.isPublished != null)
                                  Tooltip(
                                    message: t.isPublished!
                                        ? 'Publicada'
                                        : 'Borrador (oculta)',
                                    child: Icon(
                                      t.isPublished!
                                          ? Icons.public
                                          : Icons.lock_outline,
                                      size: 16,
                                      color: t.isPublished!
                                          ? Colors.greenAccent
                                              .withValues(alpha: 0.7)
                                          : Colors.orangeAccent
                                              .withValues(alpha: 0.7),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Scroll container for the non-sticky layouts.
///
/// The sticky header scaffold already manages its own ScrollController.
/// For solid/transparent layouts, we still want:
/// - restore scroll position when navigating back
/// - force scroll-to-top when user clicks "Inicio" / home
class _PublicStoreScrollView extends StatefulWidget {
  const _PublicStoreScrollView({
    super.key,
    required this.child,
    this.physics,
    this.clipBehavior = Clip.hardEdge,
  });

  final Widget child;
  final ScrollPhysics? physics;
  final Clip clipBehavior;

  @override
  State<_PublicStoreScrollView> createState() => _PublicStoreScrollViewState();
}

class _PublicStoreScrollViewState extends State<_PublicStoreScrollView> {
  final ScrollController _scrollController = ScrollController();
  String? _routeKey;
  bool _restoredForRoute = false;
  PublicStoreScrollState? _scrollState;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final nextScrollState = context.read<PublicStoreScrollState>();
    if (!identical(_scrollState, nextScrollState)) {
      _scrollState?.scrollToTopSignal.removeListener(_onScrollToTopSignal);
      _scrollState = nextScrollState;
      _scrollState?.scrollToTopSignal.addListener(_onScrollToTopSignal);
    }

    final uri = GoRouterState.of(context).uri;
    final nextKey = uri.toString();
    if (_routeKey != nextKey) {
      _routeKey = nextKey;
      _restoredForRoute = false;
    }

    if (_restoredForRoute) return;
    _restoredForRoute = true;

    final key = _routeKey;
    final path = GoRouterState.of(context).uri.path;
    final scrollState = _scrollState ?? context.read<PublicStoreScrollState>();

    final shouldScrollToTop =
        (key != null && scrollState.consumeScrollToTopRequest(key)) ||
            scrollState.consumeScrollToTopRequestForPath(path);

    if (key != null && shouldScrollToTop) {
      scrollState.clear(key);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (!_scrollController.hasClients) return;
        if (_scrollController.offset <= 0) return;
        _scrollController.jumpTo(0);
      });
    } else {
      _restoreScrollForRoute();
    }
  }

  void _onScrollToTopSignal() {
    if (!mounted) return;
    final key = _routeKey;
    if (key == null) return;

    final scrollState = _scrollState;
    if (scrollState == null) return;

    final path = GoRouterState.of(context).uri.path;
    final shouldScrollToTop = scrollState.consumeScrollToTopRequest(key) ||
        scrollState.consumeScrollToTopRequestForPath(path);
    if (!shouldScrollToTop) return;

    scrollState.clear(key);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!_scrollController.hasClients) return;
      if (_scrollController.offset <= 0) return;
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    });
  }

  void _restoreScrollForRoute() {
    final key = _routeKey;
    if (key == null) return;

    final offset = context.read<PublicStoreScrollState>().getOffset(key);
    if (offset <= 0) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!_scrollController.hasClients) return;
      final max = _scrollController.position.maxScrollExtent;
      final clamped = offset.clamp(0.0, max);
      if ((_scrollController.offset - clamped).abs() < 1.0) return;
      _scrollController.jumpTo(clamped);
    });
  }

  void _onScroll() {
    final key = _routeKey;
    if (key == null) return;
    context
        .read<PublicStoreScrollState>()
        .setOffset(key, _scrollController.offset);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _scrollState?.scrollToTopSignal.removeListener(_onScrollToTopSignal);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      controller: _scrollController,
      // Flutter Web can occasionally fail to repaint after route changes when
      // a scroll viewport is clipped. Disabling clipping is a pragmatic fix
      // for the "blank until resize" symptom.
      clipBehavior: kIsWeb ? Clip.none : widget.clipBehavior,
      physics: widget.physics,
      child: widget.child,
    );
  }
}

/// A stateful widget that manages the sticky header that stays fixed at top while scrolling
class _StickyHeaderScaffold extends StatefulWidget {
  final String storeName;
  final String storeDescription;
  final String logoUrl;
  final String topBannerText;
  final String contactPhone;
  final String contactEmail;
  final Color primaryColor;
  final Color accentColor;
  final String headerColorMode;
  final bool showTopBanner;
  final bool headerShadow;
  final Color headerBgColor;
  final List<WebsiteNavigation> navItems;
  final bool isEditMode;
  final bool allowOverlayAtTop;
  final Widget Function({
    required BuildContext context,
    required String storeName,
    required String storeDescription,
    required String logoUrl,
    required String topBannerText,
    required String contactPhone,
    required String contactEmail,
    required Color primaryColor,
    required Color accentColor,
    bool isEditMode,
    String headerStyle,
    String headerColorMode,
    bool showTopBanner,
    bool headerShadow,
    Color headerBgColor,
    required List<WebsiteNavigation> navItems,
    bool isOverlay,
  }) buildHeader;
  final Widget child;
  final Widget footer;

  const _StickyHeaderScaffold({
    super.key,
    required this.storeName,
    required this.storeDescription,
    required this.logoUrl,
    required this.topBannerText,
    required this.contactPhone,
    required this.contactEmail,
    required this.primaryColor,
    required this.accentColor,
    required this.headerColorMode,
    required this.showTopBanner,
    required this.headerShadow,
    required this.headerBgColor,
    required this.navItems,
    required this.isEditMode,
    required this.allowOverlayAtTop,
    required this.buildHeader,
    required this.child,
    required this.footer,
  });

  @override
  State<_StickyHeaderScaffold> createState() => _StickyHeaderScaffoldState();
}

class _StickyHeaderScaffoldState extends State<_StickyHeaderScaffold> {
  static const double _fallbackReservedHeaderHeight = 66;

  final ScrollController _scrollController = ScrollController();
  final GlobalKey _headerKey = GlobalKey();
  double _scrollOffset = 0;
  double _reservedHeaderHeight = _fallbackReservedHeaderHeight;
  String? _routeKey;
  bool _restoredForRoute = false;
  PublicStoreScrollState? _scrollState;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // Attach once to the shared scroll state to support "scroll to top" even
    // when the route doesn't change (e.g., clicking the logo while already on
    // home).
    final nextScrollState = context.read<PublicStoreScrollState>();
    if (!identical(_scrollState, nextScrollState)) {
      _scrollState?.scrollToTopSignal.removeListener(_onScrollToTopSignal);
      _scrollState = nextScrollState;
      _scrollState?.scrollToTopSignal.addListener(_onScrollToTopSignal);
    }

    // Key scroll offset by current route location so going "back" restores where
    // the user was (most important for long lists like /productos).
    final uri = GoRouterState.of(context).uri;
    final nextKey = uri.toString();
    if (_routeKey != nextKey) {
      _routeKey = nextKey;
      _restoredForRoute = false;
    }

    if (!_restoredForRoute) {
      _restoredForRoute = true;
      final key = _routeKey;
      final path = GoRouterState.of(context).uri.path;
      final scrollState =
          _scrollState ?? context.read<PublicStoreScrollState>();
      final shouldScrollToTop =
          (key != null && scrollState.consumeScrollToTopRequest(key)) ||
              scrollState.consumeScrollToTopRequestForPath(path);

      if (key != null && shouldScrollToTop) {
        // Explicit home navigation: land at top, don't restore.
        scrollState.clear(key);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          if (!_scrollController.hasClients) return;
          if (_scrollController.offset <= 0) return;
          _scrollController.jumpTo(0);
        });
      } else {
        _restoreScrollForRoute();
      }
    }
  }

  void _onScrollToTopSignal() {
    if (!mounted) return;
    final key = _routeKey;
    if (key == null) return;

    final scrollState = _scrollState;
    if (scrollState == null) return;

    final path = GoRouterState.of(context).uri.path;
    final shouldScrollToTop = scrollState.consumeScrollToTopRequest(key) ||
        scrollState.consumeScrollToTopRequestForPath(path);
    if (!shouldScrollToTop) return;

    scrollState.clear(key);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!_scrollController.hasClients) return;
      if (_scrollController.offset <= 0) return;
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _scrollState?.scrollToTopSignal.removeListener(_onScrollToTopSignal);
    super.dispose();
  }

  void _onScroll() {
    setState(() {
      _scrollOffset = _scrollController.offset;
    });

    final key = _routeKey;
    if (key == null) return;
    context
        .read<PublicStoreScrollState>()
        .setOffset(key, _scrollController.offset);
  }

  void _restoreScrollForRoute() {
    final key = _routeKey;
    if (key == null) return;

    final targetOffset = context.read<PublicStoreScrollState>().getOffset(key);
    if (targetOffset <= 0) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!_scrollController.hasClients) return;

      final max = _scrollController.position.maxScrollExtent;
      final clamped = targetOffset.clamp(0.0, max);
      if ((_scrollController.offset - clamped).abs() < 1.0) return;
      _scrollController.jumpTo(clamped);
    });
  }

  void _scheduleHeaderMeasurement() {
    if (widget.allowOverlayAtTop) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      final headerContext = _headerKey.currentContext;
      if (headerContext == null) return;

      final renderBox = headerContext.findRenderObject() as RenderBox?;
      if (renderBox == null || !renderBox.hasSize) return;

      final measuredHeight = renderBox.size.height;
      if ((measuredHeight - _reservedHeaderHeight).abs() < 0.5) return;

      setState(() {
        _reservedHeaderHeight = measuredHeight;
      });
    });
  }

  @override
  void didUpdateWidget(covariant _StickyHeaderScaffold oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.allowOverlayAtTop != widget.allowOverlayAtTop ||
        oldWidget.showTopBanner != widget.showTopBanner) {
      _scheduleHeaderMeasurement();
    }
  }

  @override
  Widget build(BuildContext context) {
    _scheduleHeaderMeasurement();

    // Calculate header opacity based on scroll (0 = transparent, 1 = solid)
    // Transition happens over the first 100 pixels of scroll
    final bool allowOverlayAtTop = widget.allowOverlayAtTop;
    final double headerOpacity =
        allowOverlayAtTop ? (_scrollOffset / 100).clamp(0.0, 1.0) : 1.0;
    final bool isScrolled = allowOverlayAtTop && _scrollOffset > 50;

    // When scrolled, switch to light mode (dark text on white bg)
    final String effectiveColorMode =
        allowOverlayAtTop && isScrolled ? 'light' : widget.headerColorMode;
    final Color effectiveBgColor = allowOverlayAtTop
        ? (isScrolled
            ? widget.headerBgColor
            : widget.headerBgColor.withValues(alpha: headerOpacity))
        : widget.headerBgColor;

    return Stack(
      // On Flutter Web (HTML renderer especially), clipping can create DOM
      // stacking contexts that end up painting *above* later Stack children.
      // We keep this Stack unclipped so the sticky header reliably stays on top.
      clipBehavior: Clip.none,
      children: [
        // Main scrollable content
        // Main scrollable content
        ScrollConfiguration(
          behavior: widget.isEditMode
              ? const _NoDragScrollBehavior()
              : const MaterialScrollBehavior(),
          child: SingleChildScrollView(
            controller: _scrollController,
            // Avoid clip-induced z-order issues on Web where the scroll viewport
            // can end up above the sticky header.
            clipBehavior: kIsWeb ? Clip.none : Clip.hardEdge,
            child: Column(
              children: [
                if (!allowOverlayAtTop) SizedBox(height: _reservedHeaderHeight),
                widget.child,
                widget.footer,
              ],
            ),
          ),
        ),
        // Floating header
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: KeyedSubtree(
            key: _headerKey,
            child: widget.buildHeader(
              context: context,
              storeName: widget.storeName,
              storeDescription: widget.storeDescription,
              logoUrl: widget.logoUrl,
              topBannerText: widget.topBannerText,
              contactPhone: widget.contactPhone,
              contactEmail: widget.contactEmail,
              primaryColor: widget.primaryColor,
              accentColor: widget.accentColor,
              isEditMode: widget.isEditMode,
              headerStyle: 'transparent',
              headerColorMode: effectiveColorMode,
              showTopBanner: allowOverlayAtTop
                  ? widget.showTopBanner && !isScrolled
                  : widget.showTopBanner,
              headerShadow: allowOverlayAtTop
                  ? widget.headerShadow && isScrolled
                  : widget.headerShadow,
              headerBgColor: effectiveBgColor,
              navItems: widget.navItems,
              isOverlay: allowOverlayAtTop && !isScrolled,
            ),
          ),
        ),
      ],
    );
  }
}

class _NoDragScrollBehavior extends MaterialScrollBehavior {
  const _NoDragScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.stylus,
        PointerDeviceKind.invertedStylus,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.unknown,
      };
}

/// Payment badge widget for footer - displays payment method icons
class _PaymentBadge extends StatelessWidget {
  final String name;
  final String imageUrl;
  final bool isSvg;

  const _PaymentBadge({
    required this.name,
    required this.imageUrl,
    this.isSvg = false,
  });

  @override
  Widget build(BuildContext context) {
    // MercadoPago and Redcompra logos render naturally smaller due to aspect ratio,
    // so we give them size boosts to visually match the other logos.
    double height = 40;
    double maxWidth = 100;

    if (name == 'MercadoPago') {
      height = 60;
      maxWidth = 150;
    } else if (name == 'Redcompra') {
      height = 48;
      maxWidth = 120;
    }

    return Tooltip(
      message: name,
      child: Container(
        height: height,
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: isSvg
            ? SvgPicture.network(
                imageUrl,
                fit: BoxFit.contain,
                placeholderBuilder: (_) => const SizedBox.shrink(),
              )
            : Image.network(
                imageUrl,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) {
                  return const SizedBox.shrink();
                },
              ),
      ),
    );
  }
}
