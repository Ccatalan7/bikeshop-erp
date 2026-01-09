import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

// ignore: avoid_web_libraries_in_flutter
import 'dart:html'
    if (dart.library.io) '../../modules/website/services/google_business_service_stub.dart'
    as html;

import '../providers/cart_provider.dart';
import '../providers/public_store_tenant_provider.dart';
import '../services/public_store_scroll_state.dart';
import '../theme/public_store_theme.dart';
import 'floating_whatsapp_button.dart';
import 'customer_account_menu.dart';
import '../../modules/website/services/website_service.dart';
import '../../modules/website/providers/website_edit_mode_provider.dart';
import '../../modules/website/theme/website_theme_builder.dart';
import '../../modules/website/widgets/deferred_website_editor_panel.dart';
import '../../modules/website/models/website_page_models.dart';
import '../../shared/routes/erp_routes_barrel.dart' deferred as erp;
import '../../shared/services/tenant_service.dart';
import '../../shared/utils/file_download_web.dart'
    if (dart.library.io) '../../shared/utils/file_download_stub.dart';
import '../../shared/utils/seo_helper.dart';
import '../services/customer_account_service.dart';
import '../../shared/utils/web_url.dart' show setLocationHash;
import 'customer_chat_widget.dart';

class PublicStoreLayout extends StatefulWidget {
  final Widget child;
  final bool showEditorButton;
  final bool enablePageViewScrolling;

  /// When true, the editor panel is rendered externally (by PersistentEditorShell)
  /// so this layout should not render it.
  final bool useExternalEditorPanel;

  const PublicStoreLayout({
    super.key,
    required this.child,
    this.showEditorButton = true,
    this.enablePageViewScrolling = true,
    this.useExternalEditorPanel = true,
  });

  @override
  State<PublicStoreLayout> createState() => _PublicStoreLayoutState();
}

class _PublicStoreLayoutState extends State<PublicStoreLayout> {
  static const double _externalEditorPanelWidth = 380;
  static const String _actionSitePages = 'site_pages';
  static const String _actionSiteNavigation = 'site_navigation';
  static const String _actionSiteContent = 'site_content';
  static const String _actionSiteSettings = 'site_settings';
  static const String _actionSiteOpenWebsiteHub = 'site_hub';

  static const String _actionEcomProducts = 'ecom_products';
  static const String _actionEcomCategories = 'ecom_categories';
  static const String _actionEcomFeatured = 'ecom_featured';
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

  Future<void>? _erpLibraryFuture;

  Future<void> _ensureErpLibraryLoaded() {
    return _erpLibraryFuture ??= erp.loadLibrary();
  }

  // Screenshot capture state
  bool _isCapturingScreenshot = false;

  @override
  void initState() {
    super.initState();
    // Settings are loaded in main.dart after tenant detection
    // No need to load here - just watch the service

    // Check if we're returning from Google OAuth and need to restore edit mode
    if (kIsWeb) {
      _checkGoogleOAuthReturn();
    }
  }

  /// Check localStorage for Google OAuth return flag and restore edit mode
  void _checkGoogleOAuthReturn() {
    try {
      final flag = html.window.localStorage['google_oauth_return_to_editor'];
      if (flag == 'true') {
        debugPrint(
            '🔄 [PublicStoreLayout] Detected OAuth return - restoring edit mode');
        // Clear the flag
        html.window.localStorage.remove('google_oauth_return_to_editor');

        // Schedule edit mode activation after the widget tree is built
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            final editProvider = context.read<WebsiteEditModeProvider>();
            if (!editProvider.isEditMode) {
              editProvider.switchToEditMode();
              debugPrint(
                  '✅ [PublicStoreLayout] Edit mode restored after OAuth');
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
    final qp = currentUri.queryParameters;
    // IMPORTANT:
    // - URL params are only used to ENTER editor context (first time).
    // - Once the provider is already in editor context, ignore URL flags.
    //   Otherwise stale params (common with persistent shell pages) can cause
    //   preview/edit to "bounce" back and forth.
    final allowUrlForce = !editProvider.isInEditorContext;
    final forceEditMode = allowUrlForce && qp['edit'] == 'true';
    final forcePreviewMode = allowUrlForce && qp['preview'] == 'true';

    final isEditMode = editProvider.isEditMode || forceEditMode;
    final isPreviewMode = editProvider.isPreviewMode || forcePreviewMode;

    final devicePreviewMode = editProvider.devicePreviewMode;
    final isInEditorContext =
        editProvider.isInEditorContext || forceEditMode || forcePreviewMode;

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
    if (kIsWeb && editProvider.isInEditorContext) {
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
        WidgetsBinding.instance.addPostFrameCallback((_) {
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

    final websiteTheme = WebsiteThemeBuilder.build(
      base: Theme.of(context),
      primaryColor: primaryColor,
      accentColor: accentColor,
      backgroundColor: backgroundColor,
      headingFont: headingFont,
      bodyFont: bodyFont,
      headingSize: headingSize,
      bodySize: bodySize,
    );

    // Header settings (DJI-style customization)
    final headerStyle = websiteService.getSetting('header_style', 'solid');
    final headerColorMode =
        websiteService.getSetting('header_color_mode', 'light');
    final showTopBannerRaw =
        websiteService.getSetting('header_show_top_banner', 'false');
    final showTopBanner = showTopBannerRaw == 'true';
    final headerShadow =
        websiteService.getSetting('header_shadow', 'true') == 'true';
    final headerBgColor = _resolveColor(
      websiteService.getSetting('header_bg_color', ''),
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
      );
    }

    // Build the main page content based on header style
    Widget pageContent;

    // Check if we're on the homepage (route is exactly '/tienda' or '/')
    final currentRoute = GoRouterState.of(context).uri.path;
    final isHomePage = currentRoute == '/tienda' ||
        currentRoute == '/' ||
        currentRoute == '/tienda/';

    if (headerStyle == 'transparent' &&
        isHomePage &&
        widget.enablePageViewScrolling) {
      // TRANSPARENT: Header floats over hero ONLY ON HOMEPAGE
      pageContent = ScrollConfiguration(
        behavior: isEditMode
            ? const _NoDragScrollBehavior()
            : const MaterialScrollBehavior(),
        child: SingleChildScrollView(
          clipBehavior: _isCapturingScreenshot ? Clip.none : Clip.hardEdge,
          physics: _isCapturingScreenshot
              ? const NeverScrollableScrollPhysics()
              : null,
          child: RepaintBoundary(
            key: editProvider.screenshotKey,
            child: Stack(
              children: [
                // Content starts from top (behind header)
                Column(
                  children: [
                    widget.child,
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
      pageContent = Column(
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
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    widget.child,
                    footerWidget,
                  ],
                ),
              ),
            ),
          ),
        ],
      );
    } else if (headerStyle == 'sticky' && widget.enablePageViewScrolling) {
      // STICKY: Header stays fixed at top while scrolling
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
        showTopBanner: showTopBanner,
        headerShadow: headerShadow,
        headerBgColor: headerBgColor,
        navItems: navItems,
        isEditMode: isEditMode,
        footer: footerWidget,
      );
    } else {
      // SOLID: Normal layout, header at top, content scrolls below
      pageContent = Column(
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
                    child: SingleChildScrollView(
                      child: Column(
                        children: [
                          widget.child,
                          footerWidget,
                        ],
                      ),
                    ),
                  )
                : Column(
                    children: [
                      Expanded(child: widget.child),
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
              devicePreviewMode == DevicePreviewMode.desktop;

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
        mainBody = Expanded(
          child: Stack(
            children: [
              Positioned.fill(child: editorViewport),
              if (_isConfigHubOpen)
                Positioned.fill(
                  child: overlayLayer,
                ),
            ],
          ),
        );
      } else {
        // Legacy: render editor panel inline. Ensure overlay only covers the viewport
        // (left) and never sits behind the right editor panel.
        mainBody = Expanded(
          child: Row(
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
              DeferredWebsiteEditorPanel(
                onSave: () async {
                  await _saveChanges(context, editProvider, websiteService);
                  if (context.mounted) {
                    editProvider.switchToPreviewMode();
                  }
                },
                onDiscard: () {
                  editProvider.switchToPreviewMode();
                },
              ),
            ],
          ),
        );
      }

      return Theme(
        data: websiteTheme,
        child: Scaffold(
          backgroundColor: backgroundColor,
          body: Column(
            children: [
              // Keep the same "command center" top bar visible while editing.
              _buildPreviewTopBar(
                  context, editProvider, websiteService, storeName),
              mainBody,
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
          backgroundColor: backgroundColor,
          body: Column(
            children: [
              // Preview top bar (Live Editor)
              _buildPreviewTopBar(
                  context, editProvider, websiteService, storeName),
              // Page content
              Expanded(
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
            ],
          ),
        ),
      );
    }

    // Build the main content (normal view mode)
    final mainContent = SelectionArea(
      child: Scaffold(
        backgroundColor: backgroundColor,
        body: Stack(
          children: [
            pageContent,
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
            // Show "Edit Site" button ONLY on ERP domain (not on public store domain)
            // This is for admin previewing the store from ERP, not for customers
            if (isLoggedIn &&
                widget.showEditorButton &&
                !_isPublicStoreDomain())
              Positioned(
                bottom: 24,
                right: hasWhatsApp ? 104 : 24,
                child: Builder(
                  builder: (context) {
                    final editProvider =
                        context.watch<WebsiteEditModeProvider>();
                    final isInEditorContext = editProvider.isInEditorContext;
                    final websiteService = context.read<WebsiteService>();

                    // Don't show the floating button if we're already in editor context
                    if (isInEditorContext) return const SizedBox.shrink();

                    return FloatingActionButton.extended(
                      heroTag: 'edit_site_fab',
                      onPressed: () {
                        debugPrint(
                            '🎨 [Layout] Edit button pressed. Entering preview mode');
                        // Enter preview mode first (shows top bar with Editar button)
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
      ),
    );

    return Theme(
      data: websiteTheme,
      child: mainContent,
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
          // Navigation items
          _buildPreviewNavMenu(
            context: context,
            editProvider: editProvider,
            websiteService: websiteService,
            label: 'Sitio',
            isActive: true,
            actions: const [
              _PreviewNavAction(
                id: _actionSitePages,
                label: 'Páginas (administrar)',
                icon: Icons.description_outlined,
              ),
              _PreviewNavAction(
                id: _actionSiteNavigation,
                label: 'Navegación / Menú',
                icon: Icons.menu,
              ),
              _PreviewNavAction(
                id: _actionSiteContent,
                label: 'Contenido (banners / textos)',
                icon: Icons.collections_outlined,
              ),
              _PreviewNavAction(
                id: _actionSiteSettings,
                label: 'Ajustes del sitio (tema / header / footer)',
                icon: Icons.tune,
              ),
              _PreviewNavAction(
                id: _actionSiteOpenWebsiteHub,
                label: 'Centro del Sitio Web',
                icon: Icons.dashboard_outlined,
              ),
            ],
          ),
          _buildPreviewNavMenu(
            context: context,
            editProvider: editProvider,
            websiteService: websiteService,
            label: 'Tienda',
            isActive: false,
            actions: const [
              _PreviewNavAction(
                id: _actionEcomProducts,
                label: 'Productos (publicar en web)',
                icon: Icons.inventory_2_outlined,
              ),
              _PreviewNavAction(
                id: _actionEcomCategories,
                label: 'Categorías',
                icon: Icons.category_outlined,
              ),
              _PreviewNavAction(
                id: _actionEcomFeatured,
                label: 'Productos destacados (home)',
                icon: Icons.star_outline,
              ),
              _PreviewNavAction(
                id: _actionEcomOrders,
                label: 'Pedidos online',
                icon: Icons.shopping_bag_outlined,
              ),
            ],
          ),
          _buildPreviewNavMenu(
            context: context,
            editProvider: editProvider,
            websiteService: websiteService,
            label: 'Google',
            isActive: false,
            actions: const [
              _PreviewNavAction(
                id: _actionConfigWebsiteSettings,
                label: 'SEO (Merchant / Search)',
                icon: Icons.manage_search_outlined,
              ),
              _PreviewNavAction(
                id: _actionConfigIntegrations,
                label: 'Integraciones (Google Merchant)',
                icon: Icons.extension_outlined,
              ),
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
              _PreviewNavAction.divider(),
              _PreviewNavAction(
                id: _actionReportsAnalytics,
                label: 'Analytics (Google)',
                icon: Icons.analytics_outlined,
              ),
            ],
          ),
          _buildPreviewNavMenu(
            context: context,
            editProvider: editProvider,
            websiteService: websiteService,
            label: 'Configuración',
            isActive: false,
            actions: const [
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
                activeColor: Colors.green,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ],
          ),
          const SizedBox(width: 16),

          // Mobile preview button
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
                    : editProvider.devicePreviewMode == DevicePreviewMode.tablet
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
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(4)),
            ),
            child: Text(
              isEditMode ? 'Vista previa' : 'Editar',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
          ),
          const SizedBox(width: 8),

          // Close/exit button - go back to Website Management
          IconButton(
            onPressed: () {
              editProvider.exitEditMode();
              context.go('/website');
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
            leading: Icon(a.icon),
            title: Text(a.label!),
          ),
        ),
      );
    }

    return PopupMenuButton<String>(
      tooltip: label,
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
    String title;
    if (editProvider.currentPageSlug == null ||
        editProvider.currentPageSlug!.isEmpty) {
      title = 'Página: Inicio';
    } else {
      title = 'Página: /pagina/${editProvider.currentPageSlug}';
    }

    return PopupMenuButton<String>(
      tooltip: 'Acciones de página',
      onSelected: (action) => _handleTopBarAction(
        context: context,
        editProvider: editProvider,
        websiteService: websiteService,
        actionId: action,
      ),
      itemBuilder: (context) => const [
        PopupMenuItem(
          value: _actionPageCopyLink,
          child: ListTile(
            dense: true,
            leading: Icon(Icons.copy),
            title: Text('Copiar enlace'),
          ),
        ),
        PopupMenuItem(
          value: _actionPageOpenNewTab,
          child: ListTile(
            dense: true,
            leading: Icon(Icons.open_in_new),
            title: Text('Abrir en nueva pestaña'),
          ),
        ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            Icon(Icons.article_outlined,
                size: 18, color: Colors.white.withValues(alpha: 0.8)),
            const SizedBox(width: 6),
            Text(
              title,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.8),
                fontSize: 13,
              ),
            ),
            const SizedBox(width: 2),
            Icon(Icons.arrow_drop_down,
                size: 18, color: Colors.white.withValues(alpha: 0.8)),
          ],
        ),
      ),
    );
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
      case _actionSiteContent:
        if (editProvider.isInEditorContext) {
          _openConfigHub(_EditorConfigHubTab.siteContent);
          return;
        }
        goAdmin('/website/content');
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
      case _actionEcomProducts:
        if (editProvider.isInEditorContext) {
          _openConfigHub(_EditorConfigHubTab.ecomProducts);
          return;
        }
        goAdmin('/inventory/products');
        return;
      case _actionEcomCategories:
        if (editProvider.isInEditorContext) {
          _openConfigHub(_EditorConfigHubTab.ecomCategories);
          return;
        }
        goAdmin('/inventory/categories');
        return;
      case _actionEcomFeatured:
        if (editProvider.isInEditorContext) {
          _openConfigHub(_EditorConfigHubTab.ecomFeatured);
          return;
        }
        goAdmin('/website/featured');
        return;
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
      return _isPublicStoreDomain() ? '/' : '/tienda';
    }
    if (_isPublicStoreDomain()) {
      return '/pagina/$slug';
    }
    // ERP/legacy host where public store is mounted under /tienda
    return '/tienda/pagina/$slug';
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
                    SnackBar(content: Text('Error guardando dominio: $e')),
                  );
                }
              }
            },
            icon: const Icon(Icons.save_outlined),
            label: const Text('Guardar'),
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
      return LayoutBuilder(builder: (context, constraints) {
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
                  color: Colors.black.withOpacity(0.1),
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

    final screenSize = MediaQuery.sizeOf(context);
    final targetWidth = mode == DevicePreviewMode.tablet ? 820.0 : 390.0;

    // If we are simulating mobile on desktop, we want to constrain width but keep height full?
    // Or fixed height?
    final targetHeight = screenSize.height;

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
          height: targetHeight,
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
              size: Size(targetWidth, screenSize.height),
            ),
            child: child,
          ),
        ),
      ),
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
                    value: template,
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
    context.go('/tienda/pagina/${created.slug}?edit=true');
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
    if (!_isPublicStoreDomain()) return legacyRoute;
    final uri = Uri.tryParse(legacyRoute);
    if (uri == null) return legacyRoute;

    var path = uri.path;
    if (path == '/tienda' || path == '/tienda/') {
      path = '/';
    } else if (path.startsWith('/tienda/')) {
      path = path.substring('/tienda'.length);
      if (path.isEmpty) path = '/';
    }

    return uri.replace(path: path).toString();
  }

  /// Save changes to the database
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
        pendingPageSeo: editProvider.pendingPageSeo,
        pendingFooterSectionOrder: editProvider.pendingFooterSectionOrder,
        pendingFooterLinkOrder: editProvider.pendingFooterLinkOrder,
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
    String headerColorMode = 'light',
    bool showTopBanner = true,
    bool headerShadow = true,
    Color headerBgColor = Colors.white,
    List<WebsiteNavigation> navItems = const [],
    bool isOverlay = false, // For transparent mode when scrolled up
  }) {
    final cart = context.watch<CartProvider>();

    return LayoutBuilder(builder: (context, constraints) {
      // Determine colors based on mode
      final isDarkMode = headerColorMode == 'dark' || isOverlay;
      final textColor = isDarkMode ? Colors.white : Colors.black87;
      final iconColor = isDarkMode ? Colors.white : primaryColor;
      final bgColor = isOverlay ? Colors.transparent : headerBgColor;

      final screenWidth = constraints.maxWidth;
      final useMobileGradient = screenWidth < 900 && isOverlay;

      final headerContent = Material(
        elevation: headerShadow && !isOverlay ? 2 : 0,
        color: bgColor,
        child: Container(
          decoration: useMobileGradient
              ? BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.55),
                      Colors.black.withValues(alpha: 0.15),
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
                  color: isDarkMode
                      ? Colors.black.withValues(alpha: 0.3)
                      : primaryColor,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                  child: Row(
                    children: [
                      const Icon(Icons.local_shipping_outlined,
                          color: Colors.white, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          topBannerText,
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w500,
                                  ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (screenWidth >= 900) ...[
                        if (contactPhone.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(left: 16),
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
                            padding: const EdgeInsets.only(left: 16),
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  child: Row(
                    children: [
                      // Logo - uses URL if set, otherwise falls back to asset, then text
                      // Logo - Force use of local asset for consistency and to fix "white block" issue
                      // (Database logo_url might be opaque, causing white tint to fill the box)
                      InkWell(
                        onTap: () {
                          final path = _routeForPublicStore('/tienda');
                          final isEditMode = context
                              .read<WebsiteEditModeProvider>()
                              .isEditMode;
                          final target = isEditMode ? '$path?edit=true' : path;
                          context.go(target);
                        },
                        child: _buildLogo(
                          context: context,
                          logoUrl: logoUrl,
                          storeName: storeName,
                          textColor: textColor,
                          isDarkMode: isDarkMode,
                          height: 48,
                        ),
                      ),
                      const SizedBox(width: 24),
                      // Only show nav links on desktop, use Spacer on mobile
                      if (screenWidth >= 900)
                        Expanded(
                          child: Row(
                            children: navItems.isEmpty
                                ? [
                                    _buildNavLink(
                                      context,
                                      'Inicio',
                                      _routeForPublicStore('/tienda'),
                                      textColor,
                                    ),
                                    const SizedBox(width: 24),
                                    _buildNavLink(
                                      context,
                                      'Productos',
                                      _routeForPublicStore('/tienda/productos'),
                                      textColor,
                                    ),
                                  ]
                                : [
                                    ...navItems
                                        .where((n) => n.showOnDesktop)
                                        .map((nav) {
                                      final children = nav.children
                                          .where((c) => c.isVisible)
                                          .where((c) => c.showOnDesktop)
                                          .toList()
                                        ..sort((a, b) => a.orderIndex
                                            .compareTo(b.orderIndex));

                                      if (children.isNotEmpty) {
                                        return Padding(
                                          padding:
                                              const EdgeInsets.only(right: 24),
                                          child: _buildNavDropdown(
                                            context: context,
                                            parent: nav,
                                            children: children,
                                          ),
                                        );
                                      }

                                      return Padding(
                                        padding:
                                            const EdgeInsets.only(right: 24),
                                        child: _buildNavItemLink(
                                          context,
                                          nav,
                                          textColor,
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
                            icon: const Icon(Icons.search),
                            color: iconColor,
                            onPressed: () => context
                                .go(_routeForPublicStore('/tienda/productos')),
                            tooltip: 'Buscar',
                          ),
                          const SizedBox(width: 8),
                          Stack(
                            clipBehavior: Clip.none,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.shopping_cart_outlined),
                                color: iconColor,
                                onPressed: () => context.go(
                                  _routeForPublicStore('/tienda/carrito'),
                                ),
                                tooltip: 'Carrito',
                              ),
                              if (cart.itemCount > 0)
                                Positioned(
                                  right: 0,
                                  top: 0,
                                  child: IgnorePointer(
                                    child: Container(
                                      padding: const EdgeInsets.all(4),
                                      decoration: BoxDecoration(
                                        color: accentColor,
                                        shape: BoxShape.circle,
                                      ),
                                      constraints: const BoxConstraints(
                                        minWidth: 18,
                                        minHeight: 18,
                                      ),
                                      child: Text(
                                        '${cart.itemCount}',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          if (screenWidth >= 900) ...[
                            const SizedBox(width: 16),
                            CustomerAccountMenu(textColor: textColor),
                          ] else ...[
                            const SizedBox(width: 8),
                            IconButton(
                              icon: const Icon(Icons.menu),
                              color: iconColor,
                              onPressed: () =>
                                  _showMobileMenu(context, navItems),
                              tooltip: 'Menú',
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
      );

      // Wrap with edit mode indicator if in edit mode
      if (isEditMode) {
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            // Select header for editing in the "Editar" tab
            final editProvider = context.read<WebsiteEditModeProvider>();
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
                        color: Colors.blue.withOpacity(0.5),
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
                            Icon(Icons.edit, color: Colors.white, size: 14),
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
    required Widget footer,
  }) {
    // Sticky uses the scaffold that keeps header fixed at top
    return _StickyHeaderScaffold(
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
      buildHeader: _buildHeader,
      child: widget.child,
      footer: footer,
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
    required Color primaryColor,
    required Color accentColor,
    required String logoUrl,
    bool isEditMode = false,
    bool isPreviewMode = false, // Added for preview visibility
  }) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    final dividerColor = Colors.white24;
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
          Divider(color: dividerColor),

          const SizedBox(height: 32),

          const SizedBox(height: 32),

          // Social Icons
          Text(
            'SÍGUENOS',
            style: textTheme.titleSmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              if (facebookUrl != null || isEditMode || isPreviewMode) ...[
                _buildSocialIconMobile(
                  Icons.facebook,
                  facebookUrl,
                  isEditMode, // Only edit in edit mode
                  settingKey: 'facebook',
                  label: 'Facebook',
                ),
                const SizedBox(width: 16),
              ],
              if (instagramUrl != null || isEditMode || isPreviewMode) ...[
                _buildSocialIconMobile(
                  Icons.camera_alt,
                  instagramUrl,
                  isEditMode, // Only edit in edit mode
                  settingKey: 'instagram',
                  label: 'Instagram',
                ),
                const SizedBox(width: 16),
              ],
              if (twitterUrl != null || isEditMode || isPreviewMode) ...[
                _buildSocialIconMobile(
                  Icons.alternate_email,
                  twitterUrl,
                  isEditMode, // Only edit in edit mode
                  settingKey: 'twitter',
                  label: 'Twitter/X',
                ),
                const SizedBox(width: 16),
              ],
              if (youtubeUrl != null || isEditMode || isPreviewMode) ...[
                _buildSocialIconMobile(
                  Icons.play_circle_fill,
                  youtubeUrl,
                  isEditMode, // Only edit in edit mode
                  settingKey: 'youtube',
                  label: 'YouTube',
                ),
              ],
            ],
          ),

          const SizedBox(height: 24),
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

  Widget _buildFooterLinkMobile(
      BuildContext context, String text, String route) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: InkWell(
          onTap: () {
            _navigateToHref(context, route);
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
            width: 40,
            height: 40,
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
            child: Icon(
              icon,
              color: hasUrl ? Colors.white : Colors.white38,
              size: 20,
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
    final websiteService = context.read<WebsiteService>();
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
                decoration: InputDecoration(
                  labelText: 'Usuario o URL de $label',
                  hintText: _getHintForSetting(settingKey),
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
            onPressed: () async {
              final value = controller.text.trim();
              try {
                await websiteService.saveSetting(settingKey, value);
                if (dialogContext.mounted) {
                  Navigator.pop(dialogContext, true);
                }
              } catch (e) {
                if (dialogContext.mounted) {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    SnackBar(
                      content: Text('Error al guardar: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            icon: const Icon(Icons.save),
            label: const Text('Guardar'),
          ),
        ],
      ),
    );

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
    required Color primaryColor,
    required Color accentColor,
    required String logoUrl, // Added parameter
    bool isEditMode = false,
  }) {
    return LayoutBuilder(builder: (context, constraints) {
      final websiteService = context.watch<WebsiteService>();
      final editProvider = context.watch<WebsiteEditModeProvider>();
      var footerNavItems =
          List<WebsiteNavigation>.from(websiteService.footerNavigation);

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
      final twitterUrl = _buildSocialUrl(twitterHandle, 'https://twitter.com/');
      final youtubeUrl = _buildSocialUrl(youtubeHandle, 'https://youtube.com/');

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
                              if (contactEmail.isNotEmpty)
                                IconButton(
                                  icon: const Icon(Icons.mail_outline,
                                      color: Colors.white70),
                                  onPressed: () => _launchUri(Uri(
                                      scheme: 'mailto', path: contactEmail)),
                                  tooltip: 'Email',
                                ),
                              if (contactPhone.isNotEmpty)
                                IconButton(
                                  icon: const Icon(Icons.phone_outlined,
                                      color: Colors.white70),
                                  onPressed: () => _launchUri(
                                      Uri(scheme: 'tel', path: contactPhone)),
                                  tooltip: 'Teléfono',
                                ),
                              if (facebookUrl != null)
                                IconButton(
                                  icon: const Icon(Icons.facebook_outlined,
                                      color: Colors.white70),
                                  onPressed: () =>
                                      _launchUri(Uri.parse(facebookUrl)),
                                  tooltip: 'Facebook',
                                ),
                              if (instagramUrl != null)
                                IconButton(
                                  icon: const Icon(Icons.camera_alt_outlined,
                                      color: Colors.white70),
                                  onPressed: () =>
                                      _launchUri(Uri.parse(instagramUrl)),
                                  tooltip: 'Instagram',
                                ),
                              if (twitterUrl != null)
                                IconButton(
                                  icon: const Icon(Icons.alternate_email,
                                      color: Colors.white70),
                                  onPressed: () =>
                                      _launchUri(Uri.parse(twitterUrl)),
                                  tooltip: 'Twitter',
                                ),
                              if (youtubeUrl != null)
                                IconButton(
                                  icon: const Icon(Icons.play_circle_outline,
                                      color: Colors.white70),
                                  onPressed: () =>
                                      _launchUri(Uri.parse(youtubeUrl)),
                                  tooltip: 'YouTube',
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
                const SizedBox(height: 48),
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
                        color: Colors.green.withOpacity(0.5),
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
              _buildFooterLink(context, 'Inicio', '/tienda', primaryColor),
              _buildFooterLink(
                  context, 'Productos', '/tienda/productos', primaryColor),
              _buildFooterLink(
                  context, 'Servicios', '/tienda/servicios', primaryColor),
              _buildFooterLink(
                  context, 'Contacto', '/tienda/contacto', primaryColor),
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
              _buildFooterLink(
                  context, 'Sobre Nosotros', '/nosotros', primaryColor),
              _buildFooterLink(
                  context, 'Términos y Condiciones', '/terminos', primaryColor),
              _buildFooterLink(context, 'Política de Privacidad', '/privacidad',
                  primaryColor),
              _buildFooterLink(context, 'Política de Devoluciones',
                  '/devoluciones', primaryColor),
              _buildFooterLink(context, 'Envíos', '/envios', primaryColor),
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
                _buildFooterNavLinkDesktop(context, child),
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
              _buildFooterNavLinkDesktop(context, nav),
          ],
        ),
      ),
    ];
  }

  Widget _buildFooterNavLinkDesktop(
    BuildContext context,
    WebsiteNavigation nav,
  ) {
    final href = _routeForPublicStore(nav.href ?? '/');
    final isActive = GoRouterState.of(context).matchedLocation == href;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () {
          _navigateToHref(context, href, openInNewTab: nav.openInNewTab);
        },
        child: Text(
          nav.label,
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
  }) {
    final theme = Theme.of(context);
    final dividerColor = Colors.white24;

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
                  context, 'Inicio', _routeForPublicStore('/tienda')),
              _buildFooterLinkMobile(context, 'Productos',
                  _routeForPublicStore('/tienda/productos')),
              _buildFooterLinkMobile(context, 'Servicios',
                  _routeForPublicStore('/tienda/servicios')),
              _buildFooterLinkMobile(context, 'Contacto',
                  _routeForPublicStore('/tienda/contacto')),
            ],
          ),
        ),
        Divider(color: dividerColor),
        Theme(
          data: theme.copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            title: Text('INFORMACIÓN', style: titleStyle),
            iconColor: Colors.white,
            collapsedIconColor: Colors.white,
            childrenPadding: const EdgeInsets.only(left: 16, bottom: 16),
            children: [
              _buildFooterLinkMobile(context, 'Sobre Nosotros', '/nosotros'),
              _buildFooterLinkMobile(
                  context, 'Términos y Condiciones', '/terminos'),
              _buildFooterLinkMobile(
                  context, 'Política de Devolución', '/devoluciones'),
            ],
          ),
        ),
        Divider(color: dividerColor),
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
                  _buildFooterLinkMobile(
                    context,
                    child.label,
                    _routeForPublicStore(child.href ?? '/'),
                  ),
              ],
            ),
          ),
        );
        sections.add(Divider(color: dividerColor));
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
              _buildFooterLinkMobile(
                context,
                nav.label,
                _routeForPublicStore(nav.href ?? '/'),
              ),
          ],
        ),
      ),
      Divider(color: dividerColor),
    ];
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
    // 1. Try Network URL if available
    if (logoUrl.isNotEmpty) {
      return Container(
        height: height,
        alignment: alignment,
        child: Image.network(
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
      );
    }

    // 2. Fallback to Local Asset (if no URL)
    return Container(
      height: height,
      alignment: alignment,
      child: Image.asset(
        'assets/images/vinabike_logo.png',
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) {
          // 3. Fallback to Text
          return _buildTextLogo(context, storeName, textColor);
        },
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
    Color primaryColor,
  ) {
    final isActive = GoRouterState.of(context).matchedLocation == path;

    return InkWell(
      onTap: () {
        _navigateToHref(context, path);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
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
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                color: isActive ? primaryColor : PublicStoreTheme.textPrimary,
              ),
        ),
      ),
    );
  }

  Future<void> _navigateToHref(
    BuildContext context,
    String href, {
    bool openInNewTab = false,
  }) async {
    final normalized = href.trim();
    if (normalized.isEmpty) return;

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

    // Internal navigation
    final isEditMode = context.read<WebsiteEditModeProvider>().isEditMode;
    final hasQuery = normalized.contains('?');
    final target = isEditMode
        ? (hasQuery ? '$normalized&edit=true' : '$normalized?edit=true')
        : normalized;

    context.go(target);
  }

  Widget _buildNavItemLink(
    BuildContext context,
    WebsiteNavigation nav,
    Color primaryColor,
  ) {
    final href = _routeForPublicStore(nav.href ?? '/');
    final isActive = GoRouterState.of(context).matchedLocation == href;

    return InkWell(
      onTap: () {
        _navigateToHref(context, href, openInNewTab: nav.openInNewTab);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
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
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                color: isActive ? primaryColor : PublicStoreTheme.textPrimary,
              ),
        ),
      ),
    );
  }

  Widget _buildNavDropdown({
    required BuildContext context,
    required WebsiteNavigation parent,
    required List<WebsiteNavigation> children,
  }) {
    return PopupMenuButton<WebsiteNavigation>(
      offset: const Offset(0, 40),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      elevation: 8,
      color: Colors.white,
      onSelected: (WebsiteNavigation nav) {
        final href = _routeForPublicStore(nav.href ?? '/');
        _navigateToHref(context, href, openInNewTab: nav.openInNewTab);
      },
      itemBuilder: (BuildContext popupContext) {
        return <PopupMenuEntry<WebsiteNavigation>>[
          for (int i = 0; i < children.length; i++) ...[
            if (i > 0) const PopupMenuDivider(height: 1),
            PopupMenuItem<WebsiteNavigation>(
              value: children[i],
              child: Text(children[i].label),
            ),
          ],
        ];
      },
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            parent.label,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.normal,
                  color: PublicStoreTheme.textPrimary,
                ),
          ),
          const SizedBox(width: 4),
          Icon(Icons.keyboard_arrow_down,
              size: 18, color: PublicStoreTheme.textPrimary),
        ],
      ),
    );
  }

  void _showMobileMenu(BuildContext context, List<WebsiteNavigation> navItems) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        // Access provider here inside the builder to ensure we have context
        final accountService = context.watch<CustomerAccountService>();
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
                    context,
                    icon: Icons.person_rounded,
                    label: 'Mi Cuenta',
                    onTap: () {
                      Navigator.pop(context);
                      context.go(_routeForPublicStore('/tienda/cuenta'));
                    },
                  ),
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                    child: Divider(color: Colors.white.withValues(alpha: 0.2)),
                  ),
                ] else ...[
                  _buildMobileMenuItem(
                    context,
                    icon: Icons.login_rounded,
                    label: 'Iniciar Sesión',
                    color: PublicStoreTheme.primaryBlue,
                    onTap: () {
                      Navigator.pop(context);
                      context.go(_routeForPublicStore('/tienda/cuenta/login'));
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
                    context,
                    icon: Icons.home_rounded,
                    label: 'Inicio',
                    onTap: () {
                      Navigator.pop(context);
                      context.go(_routeForPublicStore('/tienda'));
                    },
                  ),
                  _buildMobileMenuItem(
                    context,
                    icon: Icons.shopping_bag_rounded,
                    label: 'Productos',
                    onTap: () {
                      Navigator.pop(context);
                      context.go(_routeForPublicStore('/tienda/productos'));
                    },
                  ),
                  _buildMobileMenuItem(
                    context,
                    icon: Icons.mail_rounded,
                    label: 'Contacto',
                    onTap: () {
                      Navigator.pop(context);
                      context.go(_routeForPublicStore('/tienda/contacto'));
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
                        context,
                        icon: Icons.arrow_forward_ios_rounded,
                        label: nav.label,
                        onTap: () {
                          Navigator.pop(context);
                          final href = _routeForPublicStore(nav.href ?? '/');
                          _navigateToHref(
                            context,
                            href,
                            openInNewTab: nav.openInNewTab,
                          );
                        },
                      ),
                    ];

                    for (final child in children) {
                      items.add(
                        _buildMobileMenuItem(
                          context,
                          icon: Icons.subdirectory_arrow_right_rounded,
                          label: child.label,
                          onTap: () {
                            Navigator.pop(context);
                            final href =
                                _routeForPublicStore(child.href ?? '/');
                            _navigateToHref(
                              context,
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
                    context,
                    icon: Icons.logout_rounded,
                    label: 'Cerrar Sesión',
                    color: Colors.redAccent,
                    onTap: () async {
                      Navigator.pop(context);
                      await accountService.signOut();
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Sesión cerrada correctamente'),
                            backgroundColor: Colors.green,
                          ),
                        );
                        context.go('/');
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
                  color: color ?? Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
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
    setState(() {
      _configHubTab = tab;
      _isConfigHubOpen = true;
    });
  }

  void _closeConfigHub() {
    setState(() => _isConfigHubOpen = false);
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
            case _EditorConfigHubTab.siteContent:
              return erp.ContentManagementPage(embedded: true);
            case _EditorConfigHubTab.siteSettings:
              return erp.WebsiteSettingsPage(embedded: true);

            // E-commerce
            case _EditorConfigHubTab.ecomProducts:
              return erp.ProductListPage(embedded: true);
            case _EditorConfigHubTab.ecomCategories:
              return erp.HierarchicalCategoryPage(embedded: true);
            case _EditorConfigHubTab.ecomFeatured:
              return erp.FeaturedProductsPage(embedded: true);
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
                IconButton(
                  tooltip: 'Cerrar',
                  icon: const Icon(Icons.close),
                  onPressed: _closeConfigHub,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _configHubTab.title,
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis,
                  ),
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

enum _EditorConfigHubTab {
  // Site
  siteHub,
  sitePages,
  siteNavigation,
  siteContent,
  siteSettings,

  // E-commerce
  ecomProducts,
  ecomCategories,
  ecomFeatured,
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
      case _EditorConfigHubTab.siteContent:
        return 'Contenido';
      case _EditorConfigHubTab.siteSettings:
        return 'Ajustes del sitio';
      case _EditorConfigHubTab.ecomProducts:
        return 'Productos (publicar en web)';
      case _EditorConfigHubTab.ecomCategories:
        return 'Categorías';
      case _EditorConfigHubTab.ecomFeatured:
        return 'Productos destacados (home)';
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

Widget _buildFooterLink(
  BuildContext context,
  String label,
  String path,
  Color primaryColor,
) {
  final isActive = GoRouterState.of(context).matchedLocation == path;
  final editProvider = context.read<WebsiteEditModeProvider>();
  final isEditMode = editProvider.isEditMode;

  return Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: InkWell(
      onTap: () {
        // Preserve edit mode query param when navigating
        final targetPath = isEditMode ? '$path?edit=true' : path;
        context.go(targetPath);
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
    required this.buildHeader,
    required this.child,
    required this.footer,
  });

  @override
  State<_StickyHeaderScaffold> createState() => _StickyHeaderScaffoldState();
}

class _StickyHeaderScaffoldState extends State<_StickyHeaderScaffold> {
  final ScrollController _scrollController = ScrollController();
  double _scrollOffset = 0;
  String? _routeKey;
  bool _restoredForRoute = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

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
      _restoreScrollForRoute();
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
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

  @override
  Widget build(BuildContext context) {
    // Calculate header opacity based on scroll (0 = transparent, 1 = solid)
    // Transition happens over the first 100 pixels of scroll
    final double headerOpacity = (_scrollOffset / 100).clamp(0.0, 1.0);
    final bool isScrolled = _scrollOffset > 50;

    // When scrolled, switch to light mode (dark text on white bg)
    final String effectiveColorMode =
        isScrolled ? 'light' : widget.headerColorMode;
    final Color effectiveBgColor = isScrolled
        ? widget.headerBgColor
        : widget.headerBgColor.withValues(alpha: headerOpacity);

    return Stack(
      children: [
        // Main scrollable content
        // Main scrollable content
        ScrollConfiguration(
          behavior: widget.isEditMode
              ? const _NoDragScrollBehavior()
              : const MaterialScrollBehavior(),
          child: SingleChildScrollView(
            controller: _scrollController,
            child: Column(
              children: [
                // Add padding at top for the header space (only if not in edit mode)
                if (!widget.isEditMode) const SizedBox(height: 0),
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
            showTopBanner: widget.showTopBanner && !isScrolled,
            headerShadow: widget.headerShadow && isScrolled,
            headerBgColor: effectiveBgColor,
            navItems: widget.navItems,
            isOverlay: !isScrolled, // Only overlay when not scrolled
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
