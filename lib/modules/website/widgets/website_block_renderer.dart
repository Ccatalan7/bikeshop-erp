import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:provider/provider.dart';
import '../services/website_service.dart';

import '../../../public_store/providers/public_store_tenant_provider.dart';
import '../../../public_store/services/public_category_publication.dart';
import '../../../public_store/services/public_inventory_service.dart';
import '../../../shared/models/public_product_visibility_policy.dart';
import '../../../shared/services/tenant_service.dart';
import '../../../shared/models/product.dart';
import '../../../shared/widgets/hover_scale.dart';
import '../../../shared/widgets/safe_layout_builder.dart';
import '../models/website_font_registry.dart';
import '../models/website_block_registry.dart';
import '../models/website_block_surface_style.dart';
import '../models/website_block_type.dart';
import '../models/website_action.dart';
import '../models/website_canvas_responsive_document.dart';
import '../models/website_responsive_authoring.dart';
import 'website_action_button.dart';
import 'deferred_canvas_block.dart';
import 'premium_product_card.dart';
import 'text_formatting_toolbar.dart';
import 'google_reviews_carousel.dart';
import 'website_about_block_content.dart';
import 'website_carousel_media.dart';
import 'website_carousel_edit_binding.dart';
import 'website_canvas_editor_binding.dart';
import 'website_block_content_presenters.dart';
import 'website_block_surface.dart';
import 'website_contact_block_content.dart';
import 'website_cta_block_content.dart';
import 'website_faq_block_content.dart';
import 'website_features_block_content.dart';
import 'website_gallery_block_content.dart';
import 'website_hero_block_content.dart';
import 'website_pricing_block_content.dart';
import 'website_services_block_content.dart';
import 'website_stats_block_content.dart';
import 'website_team_block_content.dart';
import 'website_testimonials_block_content.dart';
import 'website_text_block_content.dart';

// Conditional import for web platform
import 'video_banner_stub.dart' if (dart.library.html) 'video_banner_web.dart'
    as video_platform;

/// Renders website blocks using the same widgets as the public store so the
/// editor preview can stay in sync with the live site.
class WebsiteBlockRenderer {
  const WebsiteBlockRenderer._();

  /// Apply font family via CSS font-family instead of GoogleFonts package
  /// (GoogleFonts adds ~6.5MB to bundle with all font metadata)
  static TextStyle _applyThemeFont(TextStyle base, String? fontFamily) {
    final family = fontFamily?.trim();
    if (family == null || family.isEmpty) return base;
    // Apply font family directly - browser loads via CSS @font-face or system fonts
    return base.copyWith(fontFamily: family);
  }

  static WebsiteActionValue? _resolvePrimaryNavigateAction(
    Map<String, dynamic> data, {
    required String fallbackLabel,
    required String fallbackTo,
    bool enabled = true,
    WebsiteActionVariant defaultVariant = WebsiteActionVariant.outline,
  }) {
    return WebsiteActionValue.resolvePrimary(
      data,
      labelKeys: const ['ctaText', 'buttonText', 'label'],
      hrefKeys: const ['ctaLink', 'buttonLink', 'link'],
      defaultLabel: fallbackLabel,
      defaultHref: fallbackTo,
      defaultVariant: defaultVariant,
      enabled: enabled,
    );
  }

  /// Single visibility filter for configurable block actions.
  ///
  /// Phase-2 contract (reconciliación Codex, 2026-07-28): the host injects its
  /// navigation-eligibility boundary through `isNavigationEligible`; this
  /// renderer never resolves category publication itself and must not import
  /// storefront navigation owners. An action whose configured destination is
  /// not eligible is ABSENT from public and public-preview composition — never
  /// rendered disabled — because a dead call-to-action invites a retry that
  /// cannot succeed. An empty href keeps its block's existing fallback
  /// semantics, and an ineligible href is never rewritten to a substitute
  /// destination.
  @visibleForTesting
  static WebsiteActionValue? visibleNavigationAction(
    WebsiteActionValue? action, {
    required bool Function(String href)? isNavigationEligible,
  }) {
    if (action == null) return null;
    final href = action.href.trim();
    if (href.isEmpty) return action;
    if (isNavigationEligible == null) return action;
    return isNavigationEligible(href) ? action : null;
  }

  static Widget build({
    required BuildContext context,
    required String blockType,
    required Map<String, dynamic> data,
    required WebsiteViewport effectiveViewport,
    required Color primaryColor,
    required Color accentColor,
    List<Product>? featuredProducts,
    bool featuredProductsReady = true,
    bool previewMode = false,
    String? headingFont,
    String? bodyFont,
    double? headingSize,
    double? bodySize,
    void Function(String route)? onNavigate,
    bool Function(String href)? isNavigationEligible,
    WebsiteBlockContentPresenters? contentPresenters,
    WebsiteCarouselEditBinding? carouselEditBinding,
    WebsiteCanvasEditorBinding? canvasEditBinding,
    String? tenantId,
  }) {
    final type = parseWebsiteBlockType(blockType);
    // ONE visitor-interaction boundary for the private consumers below that
    // never see presenters: Edit (injected contentPresenters) is inert;
    // Preview and Public keep visitor navigation. `previewMode` keeps ONLY
    // data/draft/hints/autoplay/publication semantics.
    final visitorInteractionsEnabled = contentPresenters == null;
    headingFont = WebsiteFontRegistry.resolveOptionalHeadingFont(headingFont);
    bodyFont = WebsiteFontRegistry.resolveOptionalBodyFont(bodyFont);

    Widget buildContent(WebsiteBlockSurfaceStyle surfaceStyle) {
      switch (type) {
        case WebsiteBlockType.hero:
          return WebsiteHeroBlockContent(
            data: data,
            surfaceStyle: surfaceStyle,
            primaryColor: primaryColor,
            accentColor: accentColor,
            previewMode: previewMode,
            headingFont: headingFont,
            bodyFont: bodyFont,
            headingSize: headingSize,
            bodySize: bodySize,
            onNavigate: onNavigate,
            isNavigationEligible: isNavigationEligible,
            presenters: contentPresenters,
          );
        case WebsiteBlockType.carousel:
          return _applySurfacePadding(
            surfaceStyle,
            _buildCarousel(
              context: context,
              data: data,
              surfaceStyle: surfaceStyle,
              primaryColor: primaryColor,
              accentColor: accentColor,
              previewMode: previewMode,
              headingFont: headingFont,
              bodyFont: bodyFont,
              headingSize: headingSize,
              bodySize: bodySize,
              onNavigate: onNavigate,
              isNavigationEligible: isNavigationEligible,
              tenantId: tenantId,
              presenters: contentPresenters,
              editBinding: carouselEditBinding,
            ),
            blockType: WebsiteBlockType.carousel,
            data: data,
          );
        case WebsiteBlockType.canvas:
          return _buildCanvas(
            context: context,
            data: data,
            accentColor: accentColor,
            onNavigate: onNavigate,
            isNavigationEligible: isNavigationEligible,
            tenantId: tenantId,
            headingFont: headingFont,
            bodyFont: bodyFont,
            editBinding: canvasEditBinding,
          );
        case WebsiteBlockType.text:
          return _applySurfacePadding(
            surfaceStyle,
            _buildText(
              context: context,
              data: data,
              headingFont: headingFont,
              bodyFont: bodyFont,
              headingSize: headingSize,
              bodySize: bodySize,
              inlinePresenter: contentPresenters?.text,
            ),
            blockType: WebsiteBlockType.text,
            data: data,
          );
        case WebsiteBlockType.button:
          return _applySurfacePadding(
            surfaceStyle,
            _buildButton(
              context: context,
              data: data,
              primaryColor: primaryColor,
              accentColor: accentColor,
              bodyFont: bodyFont,
              bodySize: bodySize,
              onNavigate: onNavigate,
              isNavigationEligible: isNavigationEligible,
              actionPresenter: contentPresenters?.action,
            ),
            blockType: WebsiteBlockType.button,
            data: data,
          );
        case WebsiteBlockType.divider:
          return _applySurfacePadding(
            surfaceStyle,
            _buildDivider(
              context: context,
              data: data,
            ),
            blockType: WebsiteBlockType.divider,
            data: data,
          );
        case WebsiteBlockType.products:
          return _buildProducts(
            context: context,
            data: data,
            surfaceStyle: surfaceStyle,
            primaryColor: primaryColor,
            accentColor: accentColor,
            featuredProducts: featuredProducts,
            featuredProductsReady: featuredProductsReady,
            previewMode: previewMode,
            visitorInteractionsEnabled: visitorInteractionsEnabled,
            bodyFont: bodyFont,
            onNavigate: onNavigate,
            isNavigationEligible: isNavigationEligible,
            tenantId: tenantId,
          );
        case WebsiteBlockType.services:
          return _withResponsiveContentPadding(
            surfaceStyle: surfaceStyle,
            blockType: WebsiteBlockType.services,
            data: data,
            builder: (padding) => WebsiteServicesBlockContent(
              data: data,
              primaryColor: primaryColor,
              headingFont: headingFont,
              bodyFont: bodyFont,
              presenters: contentPresenters,
              backgroundColor: surfaceStyle.hasAuthoredBackground
                  ? Colors.transparent
                  : null,
              padding: padding,
            ),
          );
        case WebsiteBlockType.about:
          return WebsiteAboutBlockContent(
            data: data,
            headingFont: headingFont,
            bodyFont: bodyFont,
            presenters: contentPresenters,
            padding: _surfacePadding(
              surfaceStyle,
              blockType: WebsiteBlockType.about,
              data: data,
            ),
          );
        case WebsiteBlockType.cta:
          return WebsiteCtaBlockContent(
            data: data,
            surfaceStyle: surfaceStyle,
            primaryColor: primaryColor,
            accentColor: accentColor,
            previewMode: previewMode,
            headingFont: headingFont,
            bodyFont: bodyFont,
            onNavigate: onNavigate,
            isNavigationEligible: isNavigationEligible,
            presenters: contentPresenters,
          );
        case WebsiteBlockType.features:
          return _withResponsiveContentPadding(
            surfaceStyle: surfaceStyle,
            blockType: WebsiteBlockType.features,
            data: data,
            builder: (padding) => WebsiteFeaturesBlockContent(
              data: data,
              primaryColor: primaryColor,
              headingFont: headingFont,
              bodyFont: bodyFont,
              presenters: contentPresenters,
              backgroundColor: surfaceStyle.hasAuthoredBackground
                  ? Colors.transparent
                  : null,
              padding: padding,
            ),
          );
        case WebsiteBlockType.testimonials:
          return _withResponsiveContentPadding(
            surfaceStyle: surfaceStyle,
            blockType: WebsiteBlockType.testimonials,
            data: data,
            builder: (padding) => WebsiteTestimonialsBlockContent(
              data: data,
              primaryColor: primaryColor,
              headingFont: headingFont,
              bodyFont: bodyFont,
              presenters: contentPresenters,
              backgroundColor: surfaceStyle.hasAuthoredBackground
                  ? Colors.transparent
                  : null,
              padding: padding,
            ),
          );
        case WebsiteBlockType.pricing:
          return _withResponsiveContentPadding(
            surfaceStyle: surfaceStyle,
            blockType: WebsiteBlockType.pricing,
            data: data,
            builder: (padding) => WebsitePricingBlockContent(
              data: data,
              primaryColor: primaryColor,
              accentColor: accentColor,
              headingFont: headingFont,
              bodyFont: bodyFont,
              previewMode: previewMode,
              onNavigate: onNavigate,
              isNavigationEligible: isNavigationEligible,
              presenters: contentPresenters,
              backgroundColor: surfaceStyle.hasAuthoredBackground
                  ? Colors.transparent
                  : null,
              padding: padding,
            ),
          );
        case WebsiteBlockType.gallery:
          return _withResponsiveContentPadding(
            surfaceStyle: surfaceStyle,
            blockType: WebsiteBlockType.gallery,
            data: data,
            builder: (padding) => WebsiteGalleryBlockContent(
              data: data,
              headingFont: headingFont,
              bodyFont: bodyFont,
              presenters: contentPresenters,
              padding: padding,
            ),
          );
        case WebsiteBlockType.contact:
          return WebsiteContactBlockContent(
            data: data,
            primaryColor: primaryColor,
            accentColor: accentColor,
            headingFont: headingFont,
            bodyFont: bodyFont,
            previewMode: previewMode,
            onNavigate: onNavigate,
            isNavigationEligible: isNavigationEligible,
            presenters: contentPresenters,
            padding: _surfacePadding(
              surfaceStyle,
              blockType: WebsiteBlockType.contact,
              data: data,
            ),
          );
        case WebsiteBlockType.faq:
          return _withResponsiveContentPadding(
            surfaceStyle: surfaceStyle,
            blockType: WebsiteBlockType.faq,
            data: data,
            builder: (padding) => WebsiteFaqBlockContent(
              data: data,
              primaryColor: primaryColor,
              headingFont: headingFont,
              bodyFont: bodyFont,
              presenters: contentPresenters,
              padding: padding,
            ),
          );
        case WebsiteBlockType.stats:
          return _withResponsiveContentPadding(
            surfaceStyle: surfaceStyle,
            blockType: WebsiteBlockType.stats,
            data: data,
            builder: (padding) => WebsiteStatsBlockContent(
              data: data,
              primaryColor: primaryColor,
              accentColor: accentColor,
              headingFont: headingFont,
              bodyFont: bodyFont,
              presenters: contentPresenters,
              padding: padding,
            ),
          );
        case WebsiteBlockType.team:
          return _withResponsiveContentPadding(
            surfaceStyle: surfaceStyle,
            blockType: WebsiteBlockType.team,
            data: data,
            builder: (padding) => WebsiteTeamBlockContent(
              data: data,
              accentColor: accentColor,
              headingFont: headingFont,
              bodyFont: bodyFont,
              previewMode: previewMode,
              onNavigate: onNavigate,
              isNavigationEligible: isNavigationEligible,
              presenters: contentPresenters,
              padding: padding,
            ),
          );
        case WebsiteBlockType.footer:
          return const SizedBox(height: 64);
        case WebsiteBlockType.categoryGrid:
          return _AutoCategoryGrid(
            data: data,
            surfaceStyle: surfaceStyle,
            primaryColor: primaryColor,
            accentColor: accentColor,
            headingFont: headingFont,
            bodyFont: bodyFont,
            previewMode: previewMode,
            visitorInteractionsEnabled: visitorInteractionsEnabled,
            onNavigate: onNavigate,
          );
        case WebsiteBlockType.videoBanner:
          return _buildVideoBanner(
            context: context,
            data: data,
            surfaceStyle: surfaceStyle,
            primaryColor: primaryColor,
            accentColor: accentColor,
            headingFont: headingFont,
            bodyFont: bodyFont,
            previewMode: previewMode,
            visitorInteractionsEnabled: visitorInteractionsEnabled,
            onNavigate: onNavigate,
            isNavigationEligible: isNavigationEligible,
          );
        case WebsiteBlockType.partnersBanner:
          return _buildPartnersBanner(
            context: context,
            data: data,
            surfaceStyle: surfaceStyle,
            primaryColor: primaryColor,
            headingFont: headingFont,
            bodyFont: bodyFont,
          );
        case WebsiteBlockType.brandLogos:
          return _buildBrandLogos(
            context: context,
            data: data,
            surfaceStyle: surfaceStyle,
            primaryColor: primaryColor,
            headingFont: headingFont,
            bodyFont: bodyFont,
            previewMode: previewMode,
            visitorInteractionsEnabled: visitorInteractionsEnabled,
            onNavigate: onNavigate,
            isNavigationEligible: isNavigationEligible,
          );
        case WebsiteBlockType.googleReviews:
          // Inject synced Google review truth when the block has no custom reviews.
          var effectiveData = data;
          try {
            // Access service safely (without listen to avoid redundant rebuilds here, parent handles it)
            final service = Provider.of<WebsiteService>(context, listen: false);
            final jsonStr = service.getSetting('google_reviews_data');
            final syncedRating = service.getSetting('google_reviews_rating');
            final syncedTotal = service.getSetting('google_reviews_total');

            if ((data['reviews'] as List?)?.isEmpty ?? true) {
              if (jsonStr.isNotEmpty) {
                final list = jsonDecode(jsonStr) as List;
                final reviews =
                    list.map((e) => Map<String, dynamic>.from(e)).toList();

                // Create new map to avoid mutating original
                effectiveData = Map<String, dynamic>.from(data);
                effectiveData['reviews'] = reviews;
              }
            }

            if (syncedRating.isNotEmpty || syncedTotal.isNotEmpty) {
              effectiveData = Map<String, dynamic>.from(effectiveData);
              if (syncedRating.isNotEmpty && effectiveData['rating'] == null) {
                effectiveData['rating'] = syncedRating;
              }
              if (syncedTotal.isNotEmpty &&
                  effectiveData['totalReviews'] == null) {
                effectiveData['totalReviews'] = syncedTotal;
              }
            }
          } catch (e) {
            debugPrint('Error injecting reviews: $e');
          }

          return GoogleReviewsCarousel(
            data: effectiveData,
            padding: _surfacePadding(
              surfaceStyle,
              blockType: WebsiteBlockType.googleReviews,
              data: data,
            ),
            backgroundColorOverride:
                surfaceStyle.hasAuthoredBackground ? Colors.transparent : null,
            primaryColor: primaryColor,
            accentColor: accentColor,
            headingFont: headingFont,
            bodyFont: bodyFont,
            previewMode: previewMode,
          );
      }
    }

    return WebsiteBlockSurface(
      data: data,
      viewport: effectiveViewport,
      paintDecoration:
          type != WebsiteBlockType.canvas && type != WebsiteBlockType.footer,
      clipContent: type != WebsiteBlockType.videoBanner,
      builder: (context, surfaceStyle) => buildContent(surfaceStyle),
    );
  }

  static Widget _buildCanvas({
    required BuildContext context,
    required Map<String, dynamic> data,
    required Color accentColor,
    void Function(String route)? onNavigate,
    bool Function(String href)? isNavigationEligible,
    String? tenantId,
    String? headingFont,
    String? bodyFont,
    WebsiteCanvasEditorBinding? editBinding,
  }) {
    return DeferredCanvasBlock(
      data: data,
      accentColor: accentColor,
      onNavigate: onNavigate,
      isNavigationEligible: isNavigationEligible,
      tenantId: tenantId,
      headingFont: headingFont,
      bodyFont: bodyFont,
      editorBinding: editBinding,
    );
  }

  static Widget _buildText({
    required BuildContext context,
    required Map<String, dynamic> data,
    String? headingFont,
    String? bodyFont,
    double? headingSize,
    double? bodySize,
    WebsiteInlineTextPresenter? inlinePresenter,
  }) {
    return WebsiteTextBlockContent(
      presentation: WebsiteTextBlockPresentation.resolve(
        context: context,
        data: data,
        headingFont: headingFont,
        bodyFont: bodyFont,
        headingSize: headingSize,
        bodySize: bodySize,
      ),
      inlinePresenter: inlinePresenter,
    );
  }

  static Widget _buildButton({
    required BuildContext context,
    required Map<String, dynamic> data,
    required Color primaryColor,
    required Color accentColor,
    void Function(String route)? onNavigate,
    String? bodyFont,
    double? bodySize,
    bool Function(String href)? isNavigationEligible,
    WebsiteInlineActionPresenter? actionPresenter,
  }) {
    final resolvedAction = WebsiteActionValue.resolvePrimary(
      data,
      labelKeys: const ['label', 'text'],
      hrefKeys: const ['link'],
      variantKeys: const ['style'],
      defaultLabel: 'Botón',
      defaultVariant: WebsiteActionVariant.fromStorage(
        data['style']?.toString(),
      ),
    );
    final action = resolvedAction ??
        WebsiteActionValue(
          label: (data['label'] ?? 'Botón').toString(),
          href: (data['link'] ?? '').toString(),
          variant: WebsiteActionVariant.fromStorage(data['style']?.toString()),
        );
    // The button IS this block's content: an ineligible destination leaves
    // nothing honest to render, so the whole block is absent.
    if (resolvedAction == null && actionPresenter == null) {
      return const SizedBox.shrink();
    }
    final visibleAction = visibleNavigationAction(
      action,
      isNavigationEligible: isNavigationEligible,
    );
    if (visibleAction == null && actionPresenter == null) {
      return const SizedBox.shrink();
    }

    final renderedAction = visibleAction ?? action;
    final link = renderedAction.href;
    final style = renderedAction.variant.storageValue;

    final textStyle = TextStyle(
      fontFamily: bodyFont,
      fontSize: bodySize ?? 16,
      fontWeight: FontWeight.w600,
    );

    VoidCallback? onPressed;
    if (actionPresenter != null) {
      // Editor chrome owns the pointer boundary, so the visitor destination
      // remains visible without being activated from Edit.
      onPressed = () {};
    } else if (link.isNotEmpty && onNavigate != null) {
      onPressed = () => onNavigate(link);
    }

    final button = WebsiteActionButton(
      action: renderedAction,
      onPressed: onPressed,
      backgroundColor: accentColor,
      foregroundColor: style == 'filled' ? Colors.white : accentColor,
      outlineColor: accentColor,
      textStyle: textStyle,
    );
    final content = actionPresenter?.call(
          context,
          WebsiteInlineActionSlot(
            id: 'standalone-button',
            action: renderedAction,
            labelKeys: const ['label', 'text'],
            hrefKeys: const ['link'],
            variantKeys: const ['style'],
            child: button,
          ),
        ) ??
        button;

    final bool isEnabled = onPressed != null && actionPresenter == null;

    return HoverScale(
      enabled: isEnabled,
      hoverScale: 1.03,
      pressedScale: 0.98,
      child: content,
    );
  }

  static Widget _buildDivider({
    required BuildContext context,
    required Map<String, dynamic> data,
  }) {
    final thickness = (data['thickness'] as num?)?.toDouble() ?? 1.0;
    final widthPct = (data['widthPct'] as num?)?.toDouble() ?? 1.0;
    final colorRaw = (data['color'] ?? '#E0E0E0').toString();
    final color = _parseHexColor(colorRaw) ?? Colors.grey.shade300;

    return Center(
      child: FractionallySizedBox(
        widthFactor: widthPct.clamp(0.1, 1.0),
        child: Divider(
          thickness: thickness.clamp(1, 12),
          height: thickness.clamp(1, 12),
          color: color,
        ),
      ),
    );
  }

  static Color? _parseHexColor(String raw) {
    try {
      var hex = raw.trim().replaceAll('#', '');
      if (hex.isEmpty) return null;
      if (hex.length == 6) hex = 'FF$hex';
      if (hex.length != 8) return null;
      return Color(int.parse(hex, radix: 16));
    } catch (_) {
      return null;
    }
  }

  static EdgeInsets _surfacePadding(
    WebsiteBlockSurfaceStyle surfaceStyle, {
    required WebsiteBlockType blockType,
    required Map<String, dynamic> data,
    EdgeInsets? fallback,
  }) {
    return surfaceStyle.paddingWithFallback(
      fallback ??
          WebsiteBlockSurfaceDefaults.paddingFor(
            blockType: blockType,
            viewport: surfaceStyle.viewport,
            data: data,
          ),
    );
  }

  static Widget _applySurfacePadding(
    WebsiteBlockSurfaceStyle surfaceStyle,
    Widget child, {
    required WebsiteBlockType blockType,
    required Map<String, dynamic> data,
  }) {
    if (!surfaceStyle.hasAuthoredPadding) return child;
    return Padding(
      padding: _surfacePadding(
        surfaceStyle,
        blockType: blockType,
        data: data,
      ),
      child: child,
    );
  }

  static Widget _withResponsiveContentPadding({
    required WebsiteBlockSurfaceStyle surfaceStyle,
    required WebsiteBlockType blockType,
    required Map<String, dynamic> data,
    required Widget Function(EdgeInsets padding) builder,
  }) {
    return builder(
      _surfacePadding(
        surfaceStyle,
        blockType: blockType,
        data: data,
      ),
    );
  }

  static BoxDecoration _resolveBackgroundDecoration({
    required Map<String, dynamic> data,
    required Color defaultColor,
    String? imageUrl,
    Alignment? imageAlignmentParam,
    bool skipImage = false,
  }) {
    final hasConfiguredImage = imageUrl != null && imageUrl.isNotEmpty;
    final style = WebsiteBlockSurfaceStyle.resolve(
      data: data,
      viewport: WebsiteViewport.desktop,
    );
    return style.decorationWithMedia(
      fallbackColor: defaultColor,
      imageProvider:
          hasConfiguredImage && !skipImage ? NetworkImage(imageUrl) : null,
      imageAlignment: imageAlignmentParam ?? _resolveFocalAlignment(data),
      imageColorFilter: kIsWeb && hasConfiguredImage && !skipImage
          ? const ColorFilter.mode(Color(0xFFFEFEFE), BlendMode.modulate)
          : null,
      preserveLegacyFallbackGradient: !hasConfiguredImage,
    );
  }

  /// Shared background contract used by the public renderer and editor preview.
  static BoxDecoration resolveBackgroundDecoration({
    required Map<String, dynamic> data,
    required Color defaultColor,
    String? imageUrl,
    Alignment? imageAlignment,
    bool skipImage = false,
  }) {
    return _resolveBackgroundDecoration(
      data: data,
      defaultColor: defaultColor,
      imageUrl: imageUrl,
      imageAlignmentParam: imageAlignment,
      skipImage: skipImage,
    );
  }

  static Alignment _resolveFocalAlignment(Map<String, dynamic> data) {
    final focalX = (data['focalPointX'] as num?)?.toDouble() ?? 0.5;
    final focalY = (data['focalPointY'] as num?)?.toDouble() ?? 0.5;

    return Alignment(
      (focalX.clamp(0.0, 1.0) * 2) - 1,
      (focalY.clamp(0.0, 1.0) * 2) - 1,
    );
  }

  static TextFormatting _resolveTextFormatting(
    Map<String, dynamic> data,
    String key, {
    String? fallbackKey,
  }) {
    final raw = data[key] ?? (fallbackKey == null ? null : data[fallbackKey]);
    return TextFormatting.fromJson(
      raw is Map ? Map<String, dynamic>.from(raw) : null,
    );
  }

  static Widget _buildCarousel({
    required BuildContext context,
    required Map<String, dynamic> data,
    required WebsiteBlockSurfaceStyle surfaceStyle,
    required Color primaryColor,
    required Color accentColor,
    bool previewMode = false,
    String? headingFont,
    String? bodyFont,
    double? headingSize,
    double? bodySize,
    void Function(String route)? onNavigate,
    bool Function(String href)? isNavigationEligible,
    String? tenantId,
    WebsiteBlockContentPresenters? presenters,
    WebsiteCarouselEditBinding? editBinding,
  }) {
    // Use block ID as stable key to prevent rebuilds on every page mount
    // Falls back to a constant key if no ID is available
    final blockId = data['id']?.toString() ?? 'carousel_default';

    return WebsiteCarouselBlockContent(
      key: ValueKey('carousel_$blockId'),
      data: data,
      surfaceStyle: surfaceStyle,
      primaryColor: primaryColor,
      accentColor: accentColor,
      previewMode: previewMode,
      headingFont: headingFont,
      bodyFont: bodyFont,
      headingSize: headingSize,
      bodySize: bodySize,
      onNavigate: onNavigate,
      isNavigationEligible: isNavigationEligible,
      tenantId: tenantId,
      presenters: presenters,
      editBinding: editBinding,
    );
  }

  static Widget _buildProducts({
    required BuildContext context,
    required Map<String, dynamic> data,
    required WebsiteBlockSurfaceStyle surfaceStyle,
    required Color primaryColor,
    required Color accentColor,
    List<Product>? featuredProducts,
    bool featuredProductsReady = true,
    bool previewMode = false,
    bool visitorInteractionsEnabled = true,
    String? bodyFont,
    void Function(String route)? onNavigate,
    bool Function(String href)? isNavigationEligible,
    String? tenantId,
  }) {
    // Delegate to stateful widget that can fetch its own products
    return _ProductsBlockWidget(
      data: data,
      surfaceStyle: surfaceStyle,
      primaryColor: primaryColor,
      accentColor: accentColor,
      featuredProducts: featuredProducts,
      featuredProductsReady: featuredProductsReady,
      previewMode: previewMode,
      visitorInteractionsEnabled: visitorInteractionsEnabled,
      bodyFont: bodyFont,
      onNavigate: onNavigate,
      isNavigationEligible: isNavigationEligible,
      tenantId: tenantId,
    );
  }

  static Widget _buildVideoBanner({
    required BuildContext context,
    required Map<String, dynamic> data,
    required WebsiteBlockSurfaceStyle surfaceStyle,
    required Color primaryColor,
    required Color accentColor,
    String? headingFont,
    String? bodyFont,
    bool previewMode = false,
    bool visitorInteractionsEnabled = true,
    void Function(String route)? onNavigate,
    bool Function(String href)? isNavigationEligible,
  }) {
    final title = (data['title'] ?? '').toString().trim();
    final subtitle = (data['subtitle'] ?? '').toString().trim();
    final imageUrl = data['imageUrl']?.toString();
    final videoUrl = data['videoUrl']?.toString();
    final videoFileUrl = data['videoFileUrl']?.toString(); // Direct video file
    final legacyCtaText = (data['ctaText'] ?? 'Ver más').toString().trim();
    final legacyCtaLink = (data['ctaLink'] ?? '/productos').toString().trim();
    final showCta = data['showCta'] != false;

    final primaryAction = _resolvePrimaryNavigateAction(
      data,
      fallbackLabel: legacyCtaText,
      fallbackTo: legacyCtaLink,
      enabled: showCta,
    );

    double overlayOpacity = 0.5;
    final rawOpacity = data['overlayOpacity'];
    if (rawOpacity is num) {
      overlayOpacity = rawOpacity.toDouble().clamp(0.0, 1.0);
    }

    final hasImage = imageUrl != null && imageUrl.isNotEmpty;
    final hasVideoUrl = videoUrl != null && videoUrl.isNotEmpty;
    final hasVideoFile = videoFileUrl != null && videoFileUrl.isNotEmpty;

    // Check if it's a YouTube URL
    String? youtubeVideoId;
    if (hasVideoUrl) {
      youtubeVideoId = _extractYouTubeVideoId(videoUrl);
    }

    // Determine what background to show
    final hasPlayableVideo = youtubeVideoId != null || hasVideoFile;

    return _VideoBannerWidget(
      surfaceStyle: surfaceStyle,
      title: title,
      subtitle: subtitle,
      imageUrl: hasImage ? imageUrl : null,
      youtubeVideoId: youtubeVideoId,
      videoFileUrl: hasVideoFile ? videoFileUrl : null,
      ctaText: primaryAction?.label ?? legacyCtaText,
      ctaLink: primaryAction?.href ?? legacyCtaLink,
      actionVariant: primaryAction?.variant ?? WebsiteActionVariant.outline,
      // Absence, not disabling: an ineligible destination suppresses the CTA
      // slot entirely while the configured values stay untouched.
      showCta: visibleNavigationAction(
            primaryAction,
            isNavigationEligible: isNavigationEligible,
          ) !=
          null,
      overlayOpacity: overlayOpacity,
      accentColor: accentColor,
      headingFont: headingFont,
      bodyFont: bodyFont,
      previewMode: previewMode,
      visitorInteractionsEnabled: visitorInteractionsEnabled,
      onNavigate: onNavigate,
      hasPlayableVideo: hasPlayableVideo,
      focalAlignment: _resolveFocalAlignment(data),
    );
  }

  /// Extract YouTube video ID from various URL formats
  static String? _extractYouTubeVideoId(String url) {
    // Handle various YouTube URL formats:
    // - https://www.youtube.com/watch?v=VIDEO_ID
    // - https://youtu.be/VIDEO_ID
    // - https://www.youtube.com/embed/VIDEO_ID
    // - https://www.youtube.com/v/VIDEO_ID

    final uri = Uri.tryParse(url);
    if (uri == null) return null;

    // youtube.com/watch?v=VIDEO_ID
    if (uri.host.contains('youtube.com')) {
      final videoId = uri.queryParameters['v'];
      if (videoId != null && videoId.isNotEmpty) return videoId;

      // youtube.com/embed/VIDEO_ID or youtube.com/v/VIDEO_ID
      final pathSegments = uri.pathSegments;
      if (pathSegments.isNotEmpty) {
        final embedIndex = pathSegments.indexOf('embed');
        final vIndex = pathSegments.indexOf('v');
        if (embedIndex != -1 && embedIndex + 1 < pathSegments.length) {
          return pathSegments[embedIndex + 1];
        }
        if (vIndex != -1 && vIndex + 1 < pathSegments.length) {
          return pathSegments[vIndex + 1];
        }
      }
    }

    // youtu.be/VIDEO_ID
    if (uri.host.contains('youtu.be')) {
      final pathSegments = uri.pathSegments;
      if (pathSegments.isNotEmpty) {
        return pathSegments.first;
      }
    }

    return null;
  }

  // ============================================================================
  // PARTNERS BANNER BLOCK
  // Dark background with centered text/list (partners, locations, etc.)
  // ============================================================================
  static Widget _buildPartnersBanner({
    required BuildContext context,
    required Map<String, dynamic> data,
    required WebsiteBlockSurfaceStyle surfaceStyle,
    required Color primaryColor,
    String? headingFont,
    String? bodyFont,
  }) {
    final theme = Theme.of(context);
    final title = (data['title'] ?? '').toString().trim();
    final titleFormatting = _resolveTextFormatting(data, 'titleFormatting');
    final imageUrl = data['imageUrl']?.toString();

    // Parse items (list of text lines)
    List<String> items = [];
    final rawItems = data['items'];
    if (rawItems is List) {
      items = rawItems
          .map((item) => item is Map
              ? (item['label'] ?? item['text'] ?? '').toString()
              : item.toString())
          .where((item) => item.trim().isNotEmpty)
          .toList();
    }

    if (items.isEmpty) {
      items = [
        'Santiago, Chile',
        'Viña del Mar, Chile',
        'Concepción, Chile',
      ];
    }

    final hasImage = imageUrl != null && imageUrl.isNotEmpty;

    // Use LayoutBuilder to fill available height and center content
    return ConstraintLayoutBuilder(
      builder: (context, constraints) {
        final hasFixedHeight = constraints.maxHeight.isFinite;
        final containerPadding = _surfacePadding(
          surfaceStyle,
          blockType: WebsiteBlockType.partnersBanner,
          data: data,
        );
        final fixedPadding = EdgeInsets.only(
          top: surfaceStyle
                  .isPaddingAuthored(WebsiteBlockSurfaceFields.paddingTop)
              ? containerPadding.top
              : 0,
          right: containerPadding.right,
          bottom: surfaceStyle
                  .isPaddingAuthored(WebsiteBlockSurfaceFields.paddingBottom)
              ? containerPadding.bottom
              : 0,
          left: containerPadding.left,
        );

        return Container(
          width: double.infinity,
          height: hasFixedHeight ? constraints.maxHeight : null,
          decoration: BoxDecoration(
            color: surfaceStyle.hasAuthoredBackground
                ? Colors.transparent
                : const Color(0xFF1a1a1a),
            image: hasImage
                ? DecorationImage(
                    image: NetworkImage(imageUrl),
                    fit: BoxFit.cover,
                    alignment: _resolveFocalAlignment(data),
                    colorFilter: const ColorFilter.mode(
                      Colors.black54,
                      BlendMode.darken,
                    ),
                  )
                : null,
          ),
          padding: hasFixedHeight ? fixedPadding : containerPadding,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 800),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (title.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 24),
                      child: Text(
                        title.toUpperCase(),
                        style: titleFormatting.applyTo(
                          theme.textTheme.labelLarge?.copyWith(
                                fontFamily: bodyFont,
                                color: Colors.white60,
                                letterSpacing: 3,
                              ) ??
                              const TextStyle(),
                        ),
                        textAlign: titleFormatting.textAlign == TextAlign.start
                            ? TextAlign.center
                            : titleFormatting.textAlign,
                      ),
                    ),
                  ...items.map((item) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Text(
                          item.toUpperCase(),
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontFamily: headingFont,
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.5,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      )),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // ============================================================================
  // BRAND LOGOS BLOCK
  // Clean white background with brand logos in a scrollable row
  // Like Commencal's "ACCESSORY BRANDS" section
  // ============================================================================
  static Widget _buildBrandLogos({
    required BuildContext context,
    required Map<String, dynamic> data,
    required WebsiteBlockSurfaceStyle surfaceStyle,
    required Color primaryColor,
    String? headingFont,
    String? bodyFont,
    bool previewMode = false,
    bool visitorInteractionsEnabled = true,
    void Function(String route)? onNavigate,
    bool Function(String href)? isNavigationEligible,
  }) {
    final title = (data['title'] ?? 'MARCAS').toString().trim();
    final titleFormatting = _resolveTextFormatting(data, 'titleFormatting');

    // Logo height only - width will be calculated to fill available space
    final logoSizeStr = (data['logoSize'] ?? 'medium').toString();
    double logoHeight;
    switch (logoSizeStr) {
      case 'small':
        logoHeight = 50;
        break;
      case 'large':
        logoHeight = 100;
        break;
      case 'xlarge':
        logoHeight = 130;
        break;
      case 'medium':
      default:
        logoHeight = 80;
        break;
    }

    // Parse brand logos list
    List<Map<String, dynamic>> brands = [];
    final rawBrands = data['brands'];
    if (rawBrands is List) {
      brands = rawBrands
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    if (brands.isEmpty && data['logos'] is List) {
      brands = (data['logos'] as List)
          .map((url) => {'name': '', 'imageUrl': url.toString()})
          .toList();
    }

    // If no brands configured, show placeholder
    if (brands.isEmpty) {
      brands = [
        {'name': 'Marca 1', 'imageUrl': ''},
        {'name': 'Marca 2', 'imageUrl': ''},
        {'name': 'Marca 3', 'imageUrl': ''},
        {'name': 'Marca 4', 'imageUrl': ''},
      ];
    }

    // Gap between logos
    const double gap = 80;

    // Use LayoutBuilder to fill available height and center content
    return ConstraintLayoutBuilder(
      builder: (context, constraints) {
        final hasFixedHeight = constraints.maxHeight.isFinite;
        final containerPadding = _surfacePadding(
          surfaceStyle,
          blockType: WebsiteBlockType.brandLogos,
          data: data,
        );
        final fixedPadding = EdgeInsets.only(
          top: surfaceStyle
                  .isPaddingAuthored(WebsiteBlockSurfaceFields.paddingTop)
              ? containerPadding.top
              : 0,
          right: containerPadding.right,
          bottom: surfaceStyle
                  .isPaddingAuthored(WebsiteBlockSurfaceFields.paddingBottom)
              ? containerPadding.bottom
              : 0,
          left: containerPadding.left,
        );
        final carouselInset = EdgeInsets.only(
          left: surfaceStyle
                  .isPaddingAuthored(WebsiteBlockSurfaceFields.paddingLeft)
              ? 0
              : containerPadding.left,
          right: surfaceStyle
                  .isPaddingAuthored(WebsiteBlockSurfaceFields.paddingRight)
              ? 0
              : containerPadding.right,
        );

        return Container(
          width: double.infinity,
          height: hasFixedHeight ? constraints.maxHeight : null,
          color: surfaceStyle.hasAuthoredBackground
              ? Colors.transparent
              : Colors.white,
          padding: hasFixedHeight ? fixedPadding : containerPadding,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Title with accent underline
                Text(
                  title.toUpperCase(),
                  style: titleFormatting.applyTo(TextStyle(
                    fontFamily: headingFont,
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 2,
                    color: Colors.black87,
                  )),
                  textAlign: titleFormatting.textAlign,
                ),
                Padding(
                  padding: hasFixedHeight ? EdgeInsets.zero : carouselInset,
                  child: _BrandLogosCarousel(
                    brands: brands,
                    bodyFont: bodyFont,
                    logoHeight: logoHeight,
                    gap: gap,
                    visitorInteractionsEnabled: visitorInteractionsEnabled,
                    onNavigate: onNavigate,
                    isNavigationEligible: isNavigationEligible,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ============================================================================
// BRAND LOGOS CAROUSEL WIDGET
// Horizontal scrolling row of brand logos with pagination dots
// ============================================================================
class _BrandLogosCarousel extends StatefulWidget {
  final List<Map<String, dynamic>> brands;
  final String? bodyFont;
  final double logoHeight;
  final double gap;
  final bool visitorInteractionsEnabled;
  final void Function(String route)? onNavigate;
  final bool Function(String href)? isNavigationEligible;

  const _BrandLogosCarousel({
    required this.brands,
    this.bodyFont,
    this.logoHeight = 90,
    this.gap = 40,
    this.visitorInteractionsEnabled = true,
    this.onNavigate,
    this.isNavigationEligible,
  });

  @override
  State<_BrandLogosCarousel> createState() => _BrandLogosCarouselState();
}

class _BrandLogosCarouselState extends State<_BrandLogosCarousel> {
  final PageController _pageController = PageController(viewportFraction: 1);
  int _currentPage = 0;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.brands.isEmpty) return const SizedBox.shrink();

    final brandCount = widget.brands.length;

    // Use LayoutBuilder to get ACTUAL available width
    return ConstraintLayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth;

        // Items per page = total brands (show all on one page, like reference site)
        // Only paginate if we truly can't fit them all
        const minLogoWidth = 100.0; // Minimum width per logo
        final maxItemsPerPage =
            ((availableWidth) / (minLogoWidth + widget.gap)).floor();

        // Show as many as we can fit, up to all brands
        final itemsPerPage = maxItemsPerPage.clamp(1, brandCount);
        final totalPages = (brandCount / itemsPerPage).ceil();

        return Column(
          children: [
            SizedBox(
              height: widget.logoHeight,
              child: PageView.builder(
                controller: _pageController,
                itemCount: totalPages,
                onPageChanged: (i) => setState(() => _currentPage = i),
                itemBuilder: (_, page) {
                  final start = page * itemsPerPage;
                  final end = (start + itemsPerPage).clamp(0, brandCount);
                  final items = widget.brands.sublist(start, end);

                  // Use Expanded to fill all available width evenly
                  return Row(
                    children: [
                      for (int i = 0; i < items.length; i++) ...[
                        Expanded(
                          child: _BrandLogoItem(
                            brand: items[i],
                            bodyFont: widget.bodyFont,
                            width: double.infinity,
                            height: widget.logoHeight,
                            visitorInteractionsEnabled:
                                widget.visitorInteractionsEnabled,
                            onNavigate: widget.onNavigate,
                            isNavigationEligible: widget.isNavigationEligible,
                          ),
                        ),
                        if (i < items.length - 1) SizedBox(width: widget.gap),
                      ],
                    ],
                  );
                },
              ),
            ),
            if (totalPages > 1) ...[
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(totalPages, (i) {
                  final active = i == _currentPage;
                  return GestureDetector(
                    onTap: () {
                      _pageController.animateToPage(
                        i,
                        duration: const Duration(milliseconds: 250),
                        curve: Curves.easeOut,
                      );
                      setState(() => _currentPage = i);
                    },
                    child: Container(
                      width: active ? 20 : 10,
                      height: 10,
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      decoration: BoxDecoration(
                        color: active
                            ? const Color(0xFF00A09D)
                            : Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(5),
                      ),
                    ),
                  );
                }),
              ),
            ],
          ],
        );
      },
    );
  }
}

// ============================================================================
// BRAND LOGO ITEM
// Single brand logo with optional name
// ============================================================================
class _BrandLogoItem extends StatelessWidget {
  final Map<String, dynamic> brand;
  final String? bodyFont;
  final double width;
  final double height;
  final bool visitorInteractionsEnabled;
  final void Function(String route)? onNavigate;
  final bool Function(String href)? isNavigationEligible;

  const _BrandLogoItem({
    required this.brand,
    this.bodyFont,
    this.width = 140,
    this.height = 90,
    this.visitorInteractionsEnabled = true,
    this.onNavigate,
    this.isNavigationEligible,
  });

  @override
  Widget build(BuildContext context) {
    final name = brand['name']?.toString() ?? '';
    final imageUrl = brand['imageUrl']?.toString() ?? '';
    final link = brand['link']?.toString() ?? '';

    Widget content = Container(
      constraints: BoxConstraints(maxWidth: width, minWidth: 40),
      height: height,
      child: imageUrl.isNotEmpty
          ? Image.network(
              imageUrl,
              fit: BoxFit.contain,
              semanticLabel: (brand['altText'] ?? brand['name'])?.toString(),
              errorBuilder: (context, error, stackTrace) {
                return _buildPlaceholder(name);
              },
            )
          : _buildPlaceholder(name),
    );

    final canNavigate = link.isNotEmpty &&
        (isNavigationEligible == null || isNavigationEligible!(link));
    if (canNavigate) {
      content = MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          // Visitor navigation works in Preview and Public; only Edit
          // (visitorInteractionsEnabled=false) is inert.
          onTap:
              visitorInteractionsEnabled ? () => onNavigate?.call(link) : null,
          child: content,
        ),
      );
    }

    return content;
  }

  Widget _buildPlaceholder(String name) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Center(
        child: Text(
          name.isNotEmpty ? name : 'Logo',
          style: TextStyle(
            fontFamily: bodyFont,
            fontSize: width > 150 ? 14 : 12,
            color: Colors.grey.shade500,
            fontWeight: FontWeight.w500,
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

// ============================================================================
// AUTO CATEGORY GRID - Fetches categories with show_on_website=true
// ============================================================================
class _AutoCategoryGrid extends StatefulWidget {
  final Map<String, dynamic> data;
  final WebsiteBlockSurfaceStyle surfaceStyle;
  final Color primaryColor;
  final Color accentColor;
  final String? headingFont;
  final String? bodyFont;
  final bool previewMode;
  final bool visitorInteractionsEnabled;
  final void Function(String route)? onNavigate;

  const _AutoCategoryGrid({
    required this.data,
    required this.surfaceStyle,
    required this.primaryColor,
    required this.accentColor,
    this.headingFont,
    this.bodyFont,
    required this.previewMode,
    this.visitorInteractionsEnabled = true,
    this.onNavigate,
  });

  @override
  State<_AutoCategoryGrid> createState() => _AutoCategoryGridState();
}

class _AutoCategoryGridState extends State<_AutoCategoryGrid> {
  List<Map<String, dynamic>>? _categories;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadCategories();
  }

  Future<void> _loadCategories() async {
    try {
      // Get tenant from provider
      final tenantProvider = context.read<PublicStoreTenantProvider>();
      String? tenantId = tenantProvider.tenantId;

      // Fallback for editor context
      if (tenantId == null) {
        try {
          final tenantService = context.read<TenantService>();
          tenantId = tenantService.currentTenantId;
        } catch (_) {}
      }

      if (tenantId == null) {
        setState(() {
          _categories = [];
          _isLoading = false;
        });
        return;
      }

      final inventory = context.read<PublicInventoryService>();
      final categories =
          await inventory.getCategoriesForTenant(tenantId: tenantId);
      if (!mounted) return;
      final websiteService = context.read<WebsiteService>();
      final publication = PublicCategoryPublication.resolve(
        categories: [
          for (final category in categories)
            if (category.id != null)
              PublicCategoryDescriptor(
                id: category.id!,
                name: category.name,
                fullPath: category.fullPath,
                showOnWebsite: category.showOnWebsite,
              ),
        ],
        navigation: websiteService.navigation,
        presentationRegistry: websiteService.catalogPresentationRegistry,
      );

      // Manual cards own presentation and order, never publication. Category
      // destinations still respect Catálogo web, while generic catalog
      // searches and other authored destinations remain eligible.
      final rawCategories = widget.data['categories'];
      final manualCategories = rawCategories is List
          ? rawCategories
              .whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .toList()
          : const <Map<String, dynamic>>[];
      final hasManualPresentation = manualCategories.any(
        (category) =>
            (category['imageUrl']?.toString().trim() ?? '').isNotEmpty,
      );
      final publishedManualCategories = manualCategories.where((category) {
        final href = _CategoryCard.resolveHref(category);
        return publication.allowsHref(href);
      }).toList(growable: false);

      final publishedCategories = categories
          .where(
            (category) =>
                category.id != null && publication.isPublished(category.id),
          )
          .toList()
        ..sort((a, b) {
          final byOrder = a.sortOrder.compareTo(b.sortOrder);
          return byOrder != 0 ? byOrder : a.name.compareTo(b.name);
        });

      final autoCategories = publishedCategories.asMap().entries.map((entry) {
        final category = entry.value;
        final index = entry.key;
        return {
          'title': category.name,
          'subtitle': category.description ?? '',
          'imageUrl': category.imageUrl ?? '',
          'ctaText': 'Ver productos',
          'ctaLink': '/productos?category=${category.id}',
          'size': index < 2 ? 'large' : 'medium',
        };
      }).toList();

      setState(() {
        _categories =
            hasManualPresentation ? publishedManualCategories : autoCategories;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error loading website categories: $e');
      if (mounted) {
        setState(() {
          _categories = [];
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final transparentBackground = widget.surfaceStyle.hasAuthoredBackground;
    final headerPadding = EdgeInsets.only(
      left: widget.surfaceStyle
              .isPaddingAuthored(WebsiteBlockSurfaceFields.paddingLeft)
          ? 0
          : 24,
      right: widget.surfaceStyle
              .isPaddingAuthored(WebsiteBlockSurfaceFields.paddingRight)
          ? 0
          : 24,
    );
    final title = (widget.data['title'] ?? '').toString().trim();
    final subtitle = (widget.data['subtitle'] ?? '').toString().trim();
    // The inspector has always saved `titleFormatting` for this family; this
    // grid was the one consumer that dropped it, so bold/size/colour/alignment
    // survived a save and never reached the storefront. Same owner and same
    // resolution as every other block here — no second writer, no new key.
    final titleFormatting = WebsiteBlockRenderer._resolveTextFormatting(
      widget.data,
      'titleFormatting',
    );

    // Publication comes only from Catálogo web. Manual block data may style or
    // order cards, but an empty authoritative result must remain empty.
    final categories = _categories ?? const <Map<String, dynamic>>[];

    // Show placeholder while loading
    if (_isLoading) {
      return Container(
        width: double.infinity,
        color: transparentBackground ? Colors.transparent : Colors.white,
        padding: widget.surfaceStyle.paddingWithFallback(
          WebsiteBlockSurfaceDefaults.paddingFor(
            blockType: WebsiteBlockType.categoryGrid,
            viewport: widget.surfaceStyle.viewport,
            data: widget.data,
          ),
        ),
        child: const Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    // If still empty, show nothing (or a subtle message in preview mode)
    if (categories.isEmpty) {
      if (widget.previewMode) {
        return Container(
          width: double.infinity,
          color: transparentBackground ? Colors.transparent : Colors.white,
          padding: widget.surfaceStyle.paddingWithFallback(
            const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
          ),
          child: Center(
            child: Text(
              'Activa categorías en Catálogo web > Categorías para mostrarlas aquí',
              style: TextStyle(color: Colors.grey.shade500),
            ),
          ),
        );
      }
      return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      color: transparentBackground ? Colors.transparent : Colors.white,
      padding: widget.surfaceStyle.paddingWithFallback(
        WebsiteBlockSurfaceDefaults.paddingFor(
          blockType: WebsiteBlockType.categoryGrid,
          viewport: widget.surfaceStyle.viewport,
          data: widget.data,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title.isNotEmpty) ...[
            Padding(
              padding: headerPadding,
              child: Text(
                title,
                style: titleFormatting.applyTo(
                  theme.textTheme.displaySmall?.copyWith(
                        fontFamily: widget.headingFont,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ) ??
                      const TextStyle(),
                ),
                // `start` means "not set" across the product, so the block's
                // own default wins until the author chooses an alignment.
                textAlign: titleFormatting.textAlign == TextAlign.start
                    ? TextAlign.start
                    : titleFormatting.textAlign,
              ),
            ),
            if (subtitle.isNotEmpty)
              Padding(
                padding: headerPadding.copyWith(
                  top: 8,
                ),
                child: Text(
                  subtitle,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontFamily: widget.bodyFont,
                    color: Colors.black54,
                  ),
                ),
              ),
            const SizedBox(height: 32),
          ],
          _CategoryGridLayout(
            categories: categories,
            primaryColor: widget.primaryColor,
            accentColor: widget.accentColor,
            bodyFont: widget.bodyFont,
            visitorInteractionsEnabled: widget.visitorInteractionsEnabled,
            onNavigate: widget.onNavigate,
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// CATEGORY GRID LAYOUT WIDGET
// Responsive grid that handles different card sizes
// ============================================================================
class _CategoryGridLayout extends StatelessWidget {
  final List<Map<String, dynamic>> categories;
  final Color primaryColor;
  final Color accentColor;
  final String? bodyFont;
  final bool visitorInteractionsEnabled;
  final void Function(String route)? onNavigate;

  const _CategoryGridLayout({
    required this.categories,
    required this.primaryColor,
    required this.accentColor,
    this.bodyFont,
    required this.visitorInteractionsEnabled,
    this.onNavigate,
  });

  @override
  Widget build(BuildContext context) {
    // Separate large and regular cards
    final largeCards = categories.where((c) => c['size'] == 'large').toList();
    final otherCards = categories.where((c) => c['size'] != 'large').toList();

    // Gap between cards (Commencal uses ~4px gaps)
    const double cardGap = 4.0;
    final screenWidth = MediaQuery.of(context).size.width;

    final isMobile = screenWidth < 600;

    if (isMobile) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Large cards: Stacked vertically
          for (final card in largeCards) ...[
            _CategoryCard(
              data: card,
              height: 300, // Slightly shorter than desktop large
              primaryColor: primaryColor,
              accentColor: accentColor,
              bodyFont: bodyFont,
              visitorInteractionsEnabled: visitorInteractionsEnabled,
              onNavigate: onNavigate,
            ),
            const SizedBox(height: cardGap),
          ],

          if (largeCards.isNotEmpty && otherCards.isNotEmpty)
            const SizedBox(height: cardGap),

          // Other cards: 2 columns using Row for every pair
          if (otherCards.isNotEmpty)
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (int i = 0; i < otherCards.length; i += 2) ...[
                  if (i > 0) const SizedBox(height: cardGap),
                  SizedBox(
                    height: 220,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: _CategoryCard(
                            data: otherCards[i],
                            height: 220,
                            primaryColor: primaryColor,
                            accentColor: accentColor,
                            bodyFont: bodyFont,
                            visitorInteractionsEnabled:
                                visitorInteractionsEnabled,
                            onNavigate: onNavigate,
                          ),
                        ),
                        const SizedBox(width: cardGap),
                        Expanded(
                          child: i + 1 < otherCards.length
                              ? _CategoryCard(
                                  data: otherCards[i + 1],
                                  height: 220,
                                  primaryColor: primaryColor,
                                  accentColor: accentColor,
                                  bodyFont: bodyFont,
                                  visitorInteractionsEnabled:
                                      visitorInteractionsEnabled,
                                  onNavigate: onNavigate,
                                )
                              : const SizedBox.shrink(),
                        ),
                      ],
                    ),
                  ),
                ]
              ],
            )
        ],
      );
    }

    return Column(
      children: [
        // Large cards row (2 per row, taller) - edge to edge
        if (largeCards.isNotEmpty)
          SizedBox(
            height: 380,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (int i = 0; i < largeCards.take(2).length; i++) ...[
                  if (i > 0) const SizedBox(width: cardGap),
                  Expanded(
                    child: _CategoryCard(
                      data: largeCards[i],
                      height: 380,
                      primaryColor: primaryColor,
                      accentColor: accentColor,
                      bodyFont: bodyFont,
                      visitorInteractionsEnabled: visitorInteractionsEnabled,
                      onNavigate: onNavigate,
                    ),
                  ),
                ],
              ],
            ),
          ),
        // Smaller cards row (4 per row, shorter) - edge to edge
        if (otherCards.isNotEmpty) ...[
          const SizedBox(height: cardGap),
          SizedBox(
            height: 220,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (int i = 0; i < otherCards.take(4).length; i++) ...[
                  if (i > 0) const SizedBox(width: cardGap),
                  Expanded(
                    child: _CategoryCard(
                      data: otherCards[i],
                      height: 220,
                      primaryColor: primaryColor,
                      accentColor: accentColor,
                      bodyFont: bodyFont,
                      visitorInteractionsEnabled: visitorInteractionsEnabled,
                      onNavigate: onNavigate,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}

// ============================================================================
// CATEGORY CARD WIDGET
// Individual category card with image, title, and CTA button
// ============================================================================
class _CategoryCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final double height;
  final Color primaryColor;
  final Color accentColor;
  final String? bodyFont;
  final bool visitorInteractionsEnabled;
  final void Function(String route)? onNavigate;

  const _CategoryCard({
    required this.data,
    required this.height,
    required this.primaryColor,
    required this.accentColor,
    this.bodyFont,
    required this.visitorInteractionsEnabled,
    this.onNavigate,
  });

  @override
  Widget build(BuildContext context) {
    final title = (data['title'] ?? 'Categoría').toString();
    final subtitle = (data['subtitle'] ?? '').toString();
    final ctaText = (data['ctaText'] ?? 'Ver colección').toString();
    // Backward/forward compat: some editors/definitions use `link`, others use `ctaLink`.
    // If both exist but disagree (common in legacy data), prefer the non-generic one.
    final href = resolveHref(data);
    final imageUrl = data['imageUrl']?.toString();
    final hasImage = imageUrl != null && imageUrl.isNotEmpty;

    return Container(
      height: height,
      decoration: BoxDecoration(
        color: const Color(0xFF2a2a2a),
        image: hasImage
            ? DecorationImage(
                image: NetworkImage(imageUrl),
                fit: BoxFit.cover,
                alignment: WebsiteBlockRenderer._resolveFocalAlignment(data),
                colorFilter: const ColorFilter.mode(
                  Colors.black38,
                  BlendMode.darken,
                ),
              )
            : null,
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Placeholder gradient for cards without images
          if (!hasImage)
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFF3a3a3a),
                    Color(0xFF1a1a1a),
                  ],
                ),
              ),
            ),
          // Material + InkWell for interaction and hover effect
          Material(
            color: Colors.transparent,
            child: InkWell(
              // Visitor navigation works in Preview and Public; only Edit
              // (visitorInteractionsEnabled=false) is inert.
              onTap: visitorInteractionsEnabled
                  ? () => onNavigate?.call(href)
                  : null,
              hoverColor: Colors.black.withValues(alpha: 0.2),
              splashColor: Colors.white.withValues(alpha: 0.1),
              highlightColor: Colors.white.withValues(alpha: 0.05),
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      title.toUpperCase(),
                      style: TextStyle(
                        fontFamily: bodyFont,
                        color: Colors.white,
                        fontSize: height > 300 ? 28 : 20,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1,
                        shadows: [
                          Shadow(
                            color: Colors.black.withValues(alpha: 0.5),
                            blurRadius: 8,
                          ),
                        ],
                      ),
                    ),
                    if (subtitle.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          subtitle,
                          style: TextStyle(
                            fontFamily: bodyFont,
                            color: Colors.white70,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    const SizedBox(height: 16),
                    // Commencal-style black button with white text
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black,
                        border: Border.all(
                            color: Colors.white.withValues(alpha: 0.3)),
                      ),
                      child: Text(
                        ctaText.toUpperCase(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String resolveHref(Map<String, dynamic> data) {
    final ctaLink = (data['ctaLink'] ?? '').toString().trim();
    final link = (data['link'] ?? '').toString().trim();
    return _resolveCategoryHref(ctaLink: ctaLink, link: link);
  }

  static String _resolveCategoryHref({
    required String ctaLink,
    required String link,
  }) {
    const fallback = '/productos';
    final hasCta = ctaLink.isNotEmpty;
    final hasLink = link.isNotEmpty;

    if (!hasCta && !hasLink) return fallback;
    if (!hasCta) return link;
    if (!hasLink) return ctaLink;

    if (ctaLink == link) return link;

    bool isGenericCatalog(String href) {
      return href == '/productos' || href == '/tienda/productos';
    }

    final ctaIsGeneric = isGenericCatalog(ctaLink);
    final linkIsGeneric = isGenericCatalog(link);

    if (linkIsGeneric && !ctaIsGeneric) return ctaLink;
    if (ctaIsGeneric && !linkIsGeneric) return link;

    // If both are “specific” but conflicting, prefer `link` (newer schema key).
    return link;
  }
}

enum _CarouselAnimation { slide, fade, zoom }

class WebsiteCarouselBlockContent extends StatefulWidget {
  const WebsiteCarouselBlockContent({
    super.key,
    required this.data,
    required this.surfaceStyle,
    required this.primaryColor,
    required this.accentColor,
    required this.previewMode,
    this.headingFont,
    this.bodyFont,
    this.headingSize,
    this.bodySize,
    this.onNavigate,
    this.isNavigationEligible,
    this.tenantId,
    this.presenters,
    this.editBinding,
  });

  static const rootKey = ValueKey<String>('website-carousel-content-root');
  static const previousButtonKey =
      ValueKey<String>('website-carousel-previous');
  static const nextButtonKey = ValueKey<String>('website-carousel-next');

  /// ONE owner for the visitor arrow-navigation affordance over arbitrary
  /// photography, identical in Edit/Preview/Public: the scrim disc separates
  /// the control on light media while the hairline boundary ring separates
  /// it on dark media (a background-colored scrim alone vanishes there).
  /// The values reuse this component's own overlay grammar — the dots
  /// already pair [Colors.white] with white at 40% alpha — so no new
  /// visual token is introduced.
  static const arrowSurfaceColor = Colors.black45;
  static const arrowForegroundColor = Colors.white;
  static final arrowBoundaryColor = Colors.white.withValues(alpha: 0.4);

  static ValueKey<String> slideKey(int index) =>
      ValueKey<String>('website-carousel-slide-$index');

  static ValueKey<String> indicatorKey(int index) =>
      ValueKey<String>('website-carousel-indicator-$index');

  final Map<String, dynamic> data;
  final WebsiteBlockSurfaceStyle surfaceStyle;
  final Color primaryColor;
  final Color accentColor;
  final bool previewMode;
  final String? headingFont;
  final String? bodyFont;
  final double? headingSize;
  final double? bodySize;
  final void Function(String route)? onNavigate;
  final bool Function(String href)? isNavigationEligible;
  final String? tenantId;
  final WebsiteBlockContentPresenters? presenters;
  final WebsiteCarouselEditBinding? editBinding;

  @override
  State<WebsiteCarouselBlockContent> createState() =>
      _WebsiteCarouselBlockContentState();
}

class _WebsiteCarouselBlockContentState
    extends State<WebsiteCarouselBlockContent> {
  late List<Map<String, dynamic>> _slides;
  int _currentIndex = 0;
  late bool _autoPlay;
  late bool _showIndicators;
  late bool _showArrows;
  late Duration _interval;
  late Duration _transitionDuration;
  late _CarouselAnimation _animation;
  Timer? _timer;
  final Map<String, Future<void>> _imageWarmups = <String, Future<void>>{};
  final Map<int, Future<void>> _slideWarmups = <int, Future<void>>{};
  int _mediaPreloadGeneration = 0;
  int _slideIntentGeneration = 0;
  int? _pendingSlideIndex;
  late String _configurationSignature;
  bool _initialMediaPreloadScheduled = false;
  bool _dependenciesReady = false;

  @override
  void initState() {
    super.initState();
    _configurationSignature = jsonEncode(widget.data);
    _refreshConfiguration(resetIndex: true);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _dependenciesReady = true;
    _restartTimer();
    if (_initialMediaPreloadScheduled) return;
    _initialMediaPreloadScheduled = true;
    _scheduleMediaPreload();
  }

  @override
  void didUpdateWidget(covariant WebsiteCarouselBlockContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextSignature = jsonEncode(widget.data);
    if (nextSignature != _configurationSignature) {
      _configurationSignature = nextSignature;
      _slideIntentGeneration++;
      _slideWarmups.clear();
      _pendingSlideIndex = null;
    }
    setState(_refreshConfiguration);
    _scheduleMediaPreload();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _mediaPreloadGeneration++;
    _slideIntentGeneration++;
    super.dispose();
  }

  void _scheduleMediaPreload() {
    final generation = ++_mediaPreloadGeneration;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || generation != _mediaPreloadGeneration) return;
      unawaited(_preloadSlideMedia(generation));
    });
  }

  Future<void> _preloadSlideMedia(int generation) async {
    if (_slides.isEmpty) return;

    final preloadOrder = websiteCarouselPreloadOrder(
      slideCount: _slides.length,
      currentIndex: _currentIndex,
    );

    // Keep the critical request queue small: warm the visible slide and the
    // next autoplay slide only. Each subsequent transition schedules the same
    // look-ahead, preserving seamless playback without downloading every
    // campaign image during first paint.
    for (final slideIndex in preloadOrder) {
      if (!mounted || generation != _mediaPreloadGeneration) return;
      await _ensureSlideReady(slideIndex);
    }
  }

  Future<void> _ensureSlideReady(int slideIndex) {
    if (!mounted || slideIndex < 0 || slideIndex >= _slides.length) {
      return Future<void>.value();
    }

    return _slideWarmups.putIfAbsent(slideIndex, () async {
      final futures = <Future<void>>[];
      if (websiteCarouselSlideUsesComposition(_slides[slideIndex])) {
        futures.add(
          preloadDeferredCanvasLibrary().onError((_, __) {
            // The deferred renderer owns its visible error state. Remove this
            // slide future after the wait so a later interaction can retry.
            _slideWarmups.remove(slideIndex);
          }),
        );
      }

      final urls =
          collectWebsiteCarouselSlideImageUrls(_slides[slideIndex]).toSet();
      futures.addAll(
        urls.map(
          (url) => _imageWarmups.putIfAbsent(
            url,
            () => precacheImage(
              NetworkImage(url),
              context,
              onError: (_, __) {
                // Rendering keeps the existing per-image error UI. A failed
                // speculative request must never break carousel playback.
                _imageWarmups.remove(url);
              },
            ),
          ),
        ),
      );

      if (futures.isNotEmpty) {
        await Future.wait<void>(futures);
      }
    });
  }

  void _warmSlide(int slideIndex) {
    unawaited(_ensureSlideReady(slideIndex));
  }

  void _refreshConfiguration({bool resetIndex = false}) {
    _slides = _parseSlides(widget.data);
    final editorIndex = widget.editBinding?.selectedSlideIndex;
    if (_slides.isEmpty) {
      _currentIndex = 0;
    } else if (editorIndex != null) {
      _currentIndex = editorIndex.clamp(0, _slides.length - 1).toInt();
    } else if (resetIndex || _currentIndex >= _slides.length) {
      _currentIndex = 0;
    }

    _autoPlay =
        !widget.previewMode && (widget.data['autoPlay'] ?? true) == true;
    _showIndicators = (widget.data['showIndicators'] ?? true) == true;
    _showArrows = (widget.data['showArrows'] ?? true) == true;
    _interval =
        Duration(seconds: _parseInterval(widget.data['intervalSeconds']));
    _transitionDuration = _parseAnimationDuration(widget.data);
    _animation = _parseAnimation(widget.data['animation']);

    if (_pendingSlideIndex == null) {
      _restartTimer();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_slides.isEmpty) {
      return const SizedBox.shrink();
    }

    // Use LayoutBuilder to fill available height, default to 520 if unconstrained
    return ConstraintLayoutBuilder(
      builder: (context, constraints) {
        final height =
            constraints.maxHeight.isFinite ? constraints.maxHeight : 520.0;
        final transitionDuration =
            _motionDisabled ? Duration.zero : _transitionDuration;
        return SizedBox(
          key: WebsiteCarouselBlockContent.rootKey,
          height: height,
          width: double.infinity,
          child: Stack(
            fit: StackFit.expand,
            children: [
              AnimatedSwitcher(
                duration: transitionDuration,
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                transitionBuilder: _buildTransition,
                child: _buildSlide(context, _slides[_currentIndex],
                    _currentIndex, constraints.maxWidth),
              ),
              if (_showIndicators && _slides.length > 1)
                Positioned(
                  bottom: 32,
                  left: 0,
                  right: 0,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(_slides.length, (index) {
                      final isActive = index == _currentIndex;
                      final isPending = index == _pendingSlideIndex;
                      return GestureDetector(
                        key: WebsiteCarouselBlockContent.indicatorKey(index),
                        onTapDown: (_) => _warmSlide(index),
                        onTap: () => _goToSlide(index),
                        child: SizedBox(
                          width: 22,
                          height: 22,
                          child: Center(
                            child: isPending
                                ? const SizedBox(
                                    width: 12,
                                    height: 12,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : AnimatedContainer(
                                    duration: const Duration(milliseconds: 250),
                                    width: 12,
                                    height: 12,
                                    decoration: BoxDecoration(
                                      color: isActive
                                          ? Colors.white
                                          : Colors.white.withValues(alpha: 0.4),
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                          ),
                        ),
                      );
                    }),
                  ),
                ),
              if (_showArrows && _slides.length > 1) ...[
                Positioned(
                  left: 24,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: Builder(builder: (context) {
                      final target =
                          (_currentIndex - 1 + _slides.length) % _slides.length;
                      return _buildArrowButton(
                        key: WebsiteCarouselBlockContent.previousButtonKey,
                        icon: Icons.chevron_left,
                        isPending: _pendingSlideIndex == target,
                        onWarmUp: () => _warmSlide(target),
                        onTap: _previousSlide,
                      );
                    }),
                  ),
                ),
                Positioned(
                  right: 24,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: Builder(builder: (context) {
                      final target = (_currentIndex + 1) % _slides.length;
                      return _buildArrowButton(
                        key: WebsiteCarouselBlockContent.nextButtonKey,
                        icon: Icons.chevron_right,
                        isPending: _pendingSlideIndex == target,
                        onWarmUp: () => _warmSlide(target),
                        onTap: _nextSlide,
                      );
                    }),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildSlide(
    BuildContext context,
    Map<String, dynamic> slide,
    int index,
    double maxWidth,
  ) {
    final theme = Theme.of(context);
    final title = (slide['title'] ?? '').toString().trim();
    final subtitle = (slide['subtitle'] ?? '').toString().trim();
    final authoredAction = _resolveSlideAction(slide);
    final action = widget.presenters != null
        ? authoredAction
        : authoredAction == null || authoredAction.href.trim().isEmpty
            ? null
            : WebsiteBlockRenderer.visibleNavigationAction(
                authoredAction,
                isNavigationEligible: widget.isNavigationEligible,
              );
    final repeaterTarget = WebsiteInlineRepeaterTarget(
      collectionKeys: const <String>['slides'],
      itemIndex: index,
    );
    final imageUrl = slide['imageUrl'];
    final videoUrl = slide['videoUrl']?.toString() ?? '';
    final videoFileUrl = slide['videoFileUrl']?.toString() ?? '';
    final showOverlay = (slide['showOverlay'] ?? true) == true;
    final compositionElements = slide['elements'] is List
        ? (slide['elements'] as List)
            .whereType<Map>()
            .map((element) => Map<String, dynamic>.from(element))
            .toList(growable: false)
        : const <Map<String, dynamic>>[];
    final usesComposition =
        slide['useComposition'] == true || compositionElements.isNotEmpty;

    double overlayOpacity = 0.55;
    final rawOverlay = slide['overlayOpacity'];
    if (rawOverlay is num) {
      overlayOpacity = rawOverlay.toDouble();
    } else if (rawOverlay is String) {
      overlayOpacity = double.tryParse(rawOverlay) ?? 0.55;
    }
    overlayOpacity = overlayOpacity.clamp(0.0, 1.0);

    final hasImage = imageUrl != null && imageUrl.toString().isNotEmpty;

    // Check for video - prefer file upload over YouTube
    final hasVideoFile = videoFileUrl.isNotEmpty;
    final youtubeId = videoUrl.isNotEmpty
        ? WebsiteBlockRenderer._extractYouTubeVideoId(videoUrl)
        : null;
    final hasYoutubeVideo = youtubeId != null;
    final hasVideo = hasVideoFile || hasYoutubeVideo;

    // Get formatting data if saved
    final titleFormatting = TextFormatting.fromJson(
        slide['titleFormatting'] as Map<String, dynamic>?);
    final subtitleFormatting = TextFormatting.fromJson(
        slide['subtitleFormatting'] as Map<String, dynamic>?);

    final headingStyle = titleFormatting.applyTo(
      WebsiteBlockRenderer._applyThemeFont(
        (theme.textTheme.displayLarge ?? const TextStyle()).copyWith(
          fontSize: widget.headingSize,
          color: Colors.white,
        ),
        widget.headingFont,
      ).copyWith(
        letterSpacing: 3,
        fontWeight: FontWeight.w900,
      ),
    );

    final subtitleStyle = subtitleFormatting.applyTo(
      WebsiteBlockRenderer._applyThemeFont(
        (theme.textTheme.headlineSmall ?? const TextStyle()).copyWith(
          fontSize: widget.bodySize != null ? widget.bodySize! * 1.2 : null,
          color: Colors.white70,
        ),
        widget.bodyFont,
      ),
    );

    final ctaTextStyle = WebsiteBlockRenderer._applyThemeFont(
      const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        letterSpacing: 1.5,
      ),
      widget.bodyFont,
    );

    // Content widget. Layered slides reuse the universal Canvas element
    // contract, so text, images, shapes, and CTA buttons remain editor-owned.
    Widget contentWidget = Container(
      decoration: showOverlay
          ? BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: overlayOpacity * 0.4),
                  Colors.black.withValues(alpha: overlayOpacity * 0.7),
                ],
              ),
            )
          : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (title.isNotEmpty || widget.presenters?.text != null)
                  widget.presenters?.text?.call(
                        context,
                        WebsiteInlineTextSlot(
                          id: 'carousel.slide.$index.title',
                          value: title,
                          valueKeys: const <String>['title'],
                          baseStyle: headingStyle,
                          formatting: titleFormatting,
                          formattingKeys: const <String>['titleFormatting'],
                          textAlign: TextAlign.center,
                          placeholder: 'Título del banner',
                          displayTransform: (value) =>
                              value.trim().toUpperCase(),
                          repeaterTarget: repeaterTarget,
                        ),
                      ) ??
                      Text(
                        title.toUpperCase(),
                        style: headingStyle,
                        textAlign: titleFormatting.textAlign == TextAlign.start
                            ? TextAlign.center
                            : titleFormatting.textAlign,
                      ),
                if (subtitle.isNotEmpty || widget.presenters?.text != null) ...[
                  const SizedBox(height: 20),
                  widget.presenters?.text?.call(
                        context,
                        WebsiteInlineTextSlot(
                          id: 'carousel.slide.$index.subtitle',
                          value: subtitle,
                          valueKeys: const <String>['subtitle'],
                          baseStyle: subtitleStyle,
                          formatting: subtitleFormatting,
                          formattingKeys: const <String>[
                            'subtitleFormatting',
                          ],
                          textAlign: TextAlign.center,
                          placeholder: 'Subtítulo descriptivo',
                          repeaterTarget: repeaterTarget,
                        ),
                      ) ??
                      Text(
                        subtitle,
                        style: subtitleStyle,
                        textAlign:
                            subtitleFormatting.textAlign == TextAlign.start
                                ? TextAlign.center
                                : subtitleFormatting.textAlign,
                      ),
                ],
                if (action != null && action.label.isNotEmpty) ...[
                  const SizedBox(height: 40),
                  Builder(
                    builder: (context) {
                      final button = WebsiteActionButton(
                        action: action,
                        // Preview keeps VISITOR navigation; only Edit is
                        // inert. Mirrors the standalone-button contract:
                        // editor chrome owns the pointer boundary, so a
                        // VALID destination stays enabled-looking in Edit
                        // through a no-op — Material must never repaint the
                        // authored foreground as disabled. Empty hrefs stay
                        // truly disabled.
                        onPressed: action.href.trim().isEmpty
                            ? null
                            : widget.presenters != null
                                ? () {}
                                : widget.onNavigate != null
                                    ? () => widget.onNavigate!(action.href)
                                    : null,
                        backgroundColor: widget.accentColor,
                        foregroundColor: Colors.white,
                        outlineColor: Colors.white,
                        uppercase: true,
                        textStyle: ctaTextStyle,
                      );
                      return widget.presenters?.action?.call(
                            context,
                            WebsiteInlineActionSlot(
                              id: 'carousel.slide.$index.action',
                              action: action,
                              labelKeys: const <String>[
                                'ctaText',
                                'buttonText',
                              ],
                              hrefKeys: const <String>[
                                'ctaLink',
                                'buttonLink',
                              ],
                              variantKeys: const <String>['actionVariant'],
                              child: button,
                              repeaterTarget: repeaterTarget,
                            ),
                          ) ??
                          button;
                    },
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );

    if (usesComposition) {
      final compositionData =
          WebsiteCanvasResponsiveDocument.carouselAuthoringDocument(
        slide: slide,
        showGrid: widget.editBinding != null,
      );
      contentWidget = Stack(
        fit: StackFit.expand,
        children: [
          if (showOverlay)
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: overlayOpacity * 0.4),
                    Colors.black.withValues(alpha: overlayOpacity * 0.7),
                  ],
                ),
              ),
            ),
          DeferredCanvasBlock(
            data: compositionData,
            accentColor: widget.accentColor,
            // Preview keeps VISITOR navigation; only Edit is inert, and
            // Edit is identified by its injected presenters.
            onNavigate: widget.presenters == null ? widget.onNavigate : null,
            isNavigationEligible: widget.isNavigationEligible,
            tenantId: widget.tenantId,
            headingFont: widget.headingFont,
            bodyFont: widget.bodyFont,
            fillAvailableHeight: true,
            clipContentToBounds: true,
            editorBinding: widget.editBinding?.canvasBindingForSlide(index),
          ),
        ],
      );
    }

    // If we have video, use Stack with video background
    if (hasVideo && video_platform.VideoBannerPlatform.isSupported) {
      return ConstraintLayoutBuilder(
        builder: (context, constraints) {
          return Container(
            key: WebsiteCarouselBlockContent.slideKey(index),
            color: const Color(0xFF1a1a1a),
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Video background
                video_platform.VideoBannerPlatform.buildVideoBackground(
                  youtubeVideoId: hasVideoFile ? null : youtubeId,
                  videoFileUrl: hasVideoFile ? videoFileUrl : null,
                  width: constraints.maxWidth,
                  height: constraints.maxHeight,
                ),
                // Content on top of video
                contentWidget,
              ],
            ),
          );
        },
      );
    }

    // No video or web not supported: the slide owns only its own authored
    // media/style. The block surface is already painted outside this carousel;
    // inheriting it here was the second application that hid/doubled it.
    final slideStyle = WebsiteBlockSurfaceStyle.resolve(
      data: slide,
      viewport: widget.surfaceStyle.viewport,
    );

    final slideBgAlignment = WebsiteBlockRenderer._resolveFocalAlignment(slide);

    final letsBlockBackgroundThrough =
        widget.surfaceStyle.hasAuthoredBackground &&
            !slideStyle.hasAuthoredBackground;
    final fallbackColor = letsBlockBackgroundThrough
        ? Colors.transparent
        : const Color(0xFF1a1a1a);
    final decoration = slideStyle.decorationWithMedia(
      fallbackColor: fallbackColor,
      imageProvider: hasImage ? NetworkImage(imageUrl.toString()) : null,
      imageAlignment: slideBgAlignment,
      imageColorFilter: kIsWeb
          ? const ColorFilter.mode(Color(0xFFFEFEFE), BlendMode.modulate)
          : null,
      preserveLegacyFallbackGradient: !letsBlockBackgroundThrough,
    );
    final mediaPresenter = widget.presenters?.media;
    if (mediaPresenter != null) {
      final fallbackDecoration = slideStyle.decorationWithMedia(
        fallbackColor: fallbackColor,
        imageAlignment: slideBgAlignment,
        preserveLegacyFallbackGradient: !letsBlockBackgroundThrough,
      );
      return Stack(
        key: WebsiteCarouselBlockContent.slideKey(index),
        fit: StackFit.expand,
        children: <Widget>[
          mediaPresenter(
            context,
            WebsiteInlineMediaSlot(
              id: 'carousel.slide.$index.background',
              url: hasImage ? imageUrl.toString() : null,
              valueKeys: const <String>['imageUrl'],
              fit: BoxFit.cover,
              alignment: slideBgAlignment,
              fallback: DecoratedBox(decoration: fallbackDecoration),
              semanticLabel:
                  (slide['imageAltText'] ?? slide['altText'])?.toString(),
              repeaterTarget: repeaterTarget,
              // The slide background sits under the CTA, arrows, dots and
              // nested selection: it renders passively, and its canonical
              // editing control is the slide inspector's
              // `Imagen y encuadre` picker.
              editAffordance: WebsiteInlineMediaEditAffordance.inspectorOnly,
            ),
          ),
          contentWidget,
        ],
      );
    }

    return Container(
      key: WebsiteCarouselBlockContent.slideKey(index),
      decoration: decoration,
      child: contentWidget,
    );
  }

  WebsiteActionValue? _resolveSlideAction(Map<String, dynamic> slide) {
    ({bool present, String value}) firstPresent(List<String> keys) {
      for (final key in keys) {
        if (slide.containsKey(key)) {
          return (
            present: true,
            value: slide[key]?.toString().trim() ?? '',
          );
        }
      }
      return (present: false, value: '');
    }

    final labelField = firstPresent(const <String>['ctaText', 'buttonText']);
    final hrefField = firstPresent(const <String>['ctaLink', 'buttonLink']);
    final resolved = WebsiteActionValue.resolvePrimary(
      slide,
      labelKeys: const <String>['ctaText', 'buttonText'],
      hrefKeys: const <String>['ctaLink', 'buttonLink'],
      variantKeys: const <String>['actionVariant'],
      defaultLabel: '',
      defaultHref: '',
      defaultVariant: WebsiteActionVariant.outline,
    );
    final label =
        (labelField.present ? labelField.value : resolved?.label ?? '').trim();
    if (label.isEmpty) return null;
    final href =
        (hrefField.present ? hrefField.value : resolved?.href ?? '').trim();
    final variant = slide.containsKey('actionVariant')
        ? WebsiteActionVariant.fromStorage(
            slide['actionVariant']?.toString(),
            fallback: WebsiteActionVariant.outline,
          )
        : resolved?.variant ?? WebsiteActionVariant.outline;
    return WebsiteActionValue(
      label: label,
      href: href,
      variant: variant,
    );
  }

  Widget _buildTransition(Widget child, Animation<double> animation) {
    switch (_animation) {
      case _CarouselAnimation.fade:
        return FadeTransition(opacity: animation, child: child);
      case _CarouselAnimation.zoom:
        final scaleAnimation =
            Tween<double>(begin: 0.95, end: 1).animate(animation);
        return ScaleTransition(scale: scaleAnimation, child: child);
      case _CarouselAnimation.slide:
        final offsetAnimation = Tween<Offset>(
          begin: const Offset(0.15, 0),
          end: Offset.zero,
        ).animate(animation);
        return ClipRect(
          child: SlideTransition(
            position: offsetAnimation,
            child: child,
          ),
        );
    }
  }

  Widget _buildArrowButton({
    required Key key,
    required IconData icon,
    required bool isPending,
    required VoidCallback onTap,
    required VoidCallback onWarmUp,
  }) {
    return InkWell(
      key: key,
      onTap: onTap,
      onTapDown: (_) => onWarmUp(),
      onHover: (isHovering) {
        if (isHovering) onWarmUp();
      },
      customBorder: const CircleBorder(),
      child: Container(
        decoration: BoxDecoration(
          color: WebsiteCarouselBlockContent.arrowSurfaceColor,
          shape: BoxShape.circle,
          // Boundary independent of the photo underneath: keeps the disc
          // visible when the media is as dark as the scrim itself.
          border: Border.all(
            color: WebsiteCarouselBlockContent.arrowBoundaryColor,
          ),
        ),
        padding: const EdgeInsets.all(8),
        child: SizedBox(
          width: 28,
          height: 28,
          child: isPending
              ? const Padding(
                  padding: EdgeInsets.all(5),
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: WebsiteCarouselBlockContent.arrowForegroundColor,
                  ),
                )
              : Icon(
                  icon,
                  color: WebsiteCarouselBlockContent.arrowForegroundColor,
                  size: 28,
                ),
        ),
      ),
    );
  }

  void _nextSlide() {
    if (!mounted || _slides.length <= 1) return;
    unawaited(_requestSlide((_currentIndex + 1) % _slides.length));
  }

  void _previousSlide() {
    if (!mounted || _slides.length <= 1) return;
    unawaited(
      _requestSlide(
        (_currentIndex - 1 + _slides.length) % _slides.length,
      ),
    );
  }

  void _goToSlide(int index) {
    if (!mounted || index < 0 || index >= _slides.length) return;
    unawaited(_requestSlide(index));
  }

  Future<void> _requestSlide(int index) async {
    if (!mounted || index < 0 || index >= _slides.length) return;
    if (index == _currentIndex) {
      _restartTimer();
      return;
    }

    _timer?.cancel();
    final editBinding = widget.editBinding;
    if (editBinding != null) {
      setState(() {
        _currentIndex = index;
        _pendingSlideIndex = null;
      });
      editBinding.onSlideSelected(index);
      _scheduleMediaPreload();
      return;
    }

    final intent = ++_slideIntentGeneration;
    setState(() {
      _pendingSlideIndex = index;
    });

    try {
      await _ensureSlideReady(index);
    } catch (_) {
      // The slide renderer retains its normal media/deferred-library error UI.
      // A speculative warm-up failure must not make navigation impossible.
    }

    if (!mounted || intent != _slideIntentGeneration) return;
    setState(() {
      _currentIndex = index;
      _pendingSlideIndex = null;
    });
    _scheduleMediaPreload();
    _restartTimer();
  }

  void _restartTimer() {
    _timer?.cancel();
    if (!_autoPlay ||
        (_dependenciesReady && _motionDisabled) ||
        _slides.length <= 1) {
      return;
    }
    _timer = Timer.periodic(_interval, (_) => _nextSlide());
  }

  List<Map<String, dynamic>> _parseSlides(Map<String, dynamic> data) {
    final rawSlides = data['slides'];
    if (rawSlides is List) {
      return rawSlides
          .whereType<Map>()
          .map((slide) => Map<String, dynamic>.from(slide))
          .toList();
    }
    return [];
  }

  bool get _motionDisabled {
    final mediaQuery = MediaQuery.maybeOf(context);
    return mediaQuery?.disableAnimations == true ||
        mediaQuery?.accessibleNavigation == true;
  }

  int _parseInterval(dynamic value) {
    if (value is num) {
      return max(1, value.toInt());
    }
    if (value is String) {
      final parsed = int.tryParse(value);
      if (parsed != null) {
        return max(1, parsed);
      }
    }
    return 5;
  }

  Duration _parseAnimationDuration(Map<String, dynamic> data) {
    final raw = data['animationDurationMs'] ?? data['transitionDuration'];
    if (raw is num) {
      return Duration(milliseconds: max(1, raw.toInt()));
    }
    if (raw is String) {
      final parsed = int.tryParse(raw);
      if (parsed != null) {
        return Duration(milliseconds: max(1, parsed));
      }
    }
    return const Duration(milliseconds: 600);
  }

  _CarouselAnimation _parseAnimation(dynamic value) {
    final raw = value?.toString().toLowerCase();
    switch (raw) {
      case 'fade':
        return _CarouselAnimation.fade;
      case 'zoom':
        return _CarouselAnimation.zoom;
      default:
        return _CarouselAnimation.slide;
    }
  }
}

// ============================================================================
// PREMIUM PRODUCT CARD - Commencal-style clean, minimal design
// ============================================================================
// (moved) Premium product card extracted to `premium_product_card.dart` for reuse (e.g. Canvas).

/// Stateful Products block widget that fetches products based on block settings
class _ProductsBlockWidget extends StatefulWidget {
  final Map<String, dynamic> data;
  final WebsiteBlockSurfaceStyle surfaceStyle;
  final Color primaryColor;
  final Color accentColor;
  final List<Product>? featuredProducts;
  final bool featuredProductsReady;
  final bool previewMode;
  final bool visitorInteractionsEnabled;
  final String? bodyFont;
  final void Function(String route)? onNavigate;
  final bool Function(String href)? isNavigationEligible;
  final String? tenantId;

  const _ProductsBlockWidget({
    required this.data,
    required this.surfaceStyle,
    required this.primaryColor,
    required this.accentColor,
    this.featuredProducts,
    this.featuredProductsReady = true,
    this.previewMode = false,
    this.visitorInteractionsEnabled = true,
    this.bodyFont,
    this.onNavigate,
    this.isNavigationEligible,
    this.tenantId,
  });

  @override
  State<_ProductsBlockWidget> createState() => _ProductsBlockWidgetState();
}

class _ProductsBlockWidgetState extends State<_ProductsBlockWidget> {
  List<Product> _products = [];
  bool _isLoading = true;
  int _loadToken = 0;
  PublicInventoryService? _observedInventoryService;
  bool _inventoryRevalidationPending = false;
  bool _inventoryRevalidationScheduled = false;
  bool _inventoryTickerActive = true;
  bool _productLoadActive = false;

  @override
  void initState() {
    super.initState();
    _loadProducts();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    PublicInventoryService? nextInventoryService;
    try {
      nextInventoryService = context.read<PublicInventoryService>();
    } catch (_) {
      // ERP-hosted previews may not provide the public inventory service.
    }
    if (_observedInventoryService != nextInventoryService) {
      _observedInventoryService
          ?.removeListener(_handlePublicInventoryInvalidated);
      _observedInventoryService = nextInventoryService;
      nextInventoryService?.addListener(_handlePublicInventoryInvalidated);
    }

    _inventoryTickerActive = TickerMode.of(context);
    if (_inventoryTickerActive && _inventoryRevalidationPending) {
      _scheduleInventoryRevalidation();
    }
  }

  @override
  void didUpdateWidget(_ProductsBlockWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldContract = WebsiteProductsBlockContract.fromData(oldWidget.data);
    final nextContract = _contract;
    final ownerChanged = oldContract.productSource !=
            nextContract.productSource ||
        oldContract.selectionFingerprint != nextContract.selectionFingerprint ||
        oldContract.categoryId != nextContract.categoryId ||
        oldContract.maxProducts != nextContract.maxProducts ||
        oldWidget.tenantId != widget.tenantId;
    final featuredInputChanged =
        oldWidget.featuredProductsReady != widget.featuredProductsReady ||
            !_samePublicProductSnapshots(
              oldWidget.featuredProducts,
              widget.featuredProducts,
            );

    if (ownerChanged || featuredInputChanged) {
      _loadProducts(
        preserveVisible: !ownerChanged && _products.isNotEmpty,
      );
    }
  }

  void _handlePublicInventoryInvalidated() {
    if (!mounted || _usesParentFeaturedProducts) return;
    _inventoryRevalidationPending = true;
    _scheduleInventoryRevalidation();
  }

  void _scheduleInventoryRevalidation() {
    if (!mounted ||
        !_inventoryTickerActive ||
        _inventoryRevalidationScheduled ||
        !_inventoryRevalidationPending) {
      return;
    }
    _inventoryRevalidationScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _inventoryRevalidationScheduled = false;
      if (!mounted || !_inventoryTickerActive) return;
      if (!_inventoryRevalidationPending) return;
      if (_usesParentFeaturedProducts) {
        _inventoryRevalidationPending = false;
        return;
      }
      if (_productLoadActive) return;

      _inventoryRevalidationPending = false;
      unawaited(_loadProducts(preserveVisible: true));
    });
  }

  WebsiteProductsBlockContract get _contract =>
      WebsiteProductsBlockContract.fromData(widget.data);

  String get _productSource => _contract.productSource;
  bool get _usesParentFeaturedProducts =>
      _productSource == 'featured' && widget.featuredProducts != null;

  List<String> get _selectedProductIds => _contract.productIds;
  String? get _categoryId => _contract.categoryId;
  int get _maxProducts => _contract.maxProducts;

  Future<void> _loadProducts({bool preserveVisible = false}) async {
    if (!mounted) return;
    final loadToken = ++_loadToken;
    _productLoadActive = true;

    if (!preserveVisible) {
      if (_products.isNotEmpty || !_isLoading) {
        setState(() {
          _products = [];
          _isLoading = true;
        });
      }
    } else if (_products.isEmpty && !_isLoading) {
      setState(() => _isLoading = true);
    }

    try {
      final tenantId = widget.tenantId;

      // If no tenantId yet, stay in loading state and wait for didUpdateWidget.
      if (tenantId == null || tenantId.isEmpty) return;
      if (_productSource == 'featured' &&
          widget.featuredProducts != null &&
          !widget.featuredProductsReady) {
        return;
      }

      // Edit, Preview and Public consume the same catalog truth. Author-only
      // repair information belongs in the inspector, never in the canvas.
      final products = await _loadPublicProductsFromPolicy();
      _applyLoadedProducts(products, loadToken: loadToken);
    } catch (e) {
      debugPrint('[ProductsBlock] Error: $e');
      if (mounted && loadToken == _loadToken) {
        setState(() {
          _isLoading = false;
        });
      }
    } finally {
      if (loadToken == _loadToken) {
        _productLoadActive = false;
        if (mounted &&
            _inventoryTickerActive &&
            _inventoryRevalidationPending) {
          _scheduleInventoryRevalidation();
        }
      }
    }
  }

  void _applyLoadedProducts(
    List<Product> products, {
    required int loadToken,
  }) {
    if (!mounted || loadToken != _loadToken) return;
    final nextProducts = products.take(_maxProducts).toList(growable: false);
    if (_isLoading || !_samePublicProductSnapshots(_products, nextProducts)) {
      setState(() {
        _products = nextProducts;
        _isLoading = false;
      });
    }
  }

  bool _samePublicProductSnapshots(
    List<Product>? current,
    List<Product>? next,
  ) {
    if (identical(current, next)) return true;
    if (current == null || next == null || current.length != next.length) {
      return false;
    }
    return _publicProductFingerprint(current) ==
        _publicProductFingerprint(next);
  }

  String _publicProductFingerprint(List<Product> products) {
    return jsonEncode([
      for (final product in products)
        <String, dynamic>{
          ...product.toJson(),
          'available_stock_quantity': product.availableStockQuantity,
          'full_sets_available': product.fullSetsAvailable,
          'is_partial': product.isPartial,
        },
    ]);
  }

  @override
  void dispose() {
    _loadToken++;
    _observedInventoryService
        ?.removeListener(_handlePublicInventoryInvalidated);
    super.dispose();
  }

  Future<List<Product>> _loadPublicProductsFromPolicy() async {
    final tenantId = widget.tenantId;
    if (tenantId == null || tenantId.isEmpty) return const [];

    PublicInventoryService inventoryService;
    try {
      inventoryService = context.read<PublicInventoryService>();
    } catch (_) {
      inventoryService = PublicInventoryService();
    }

    final policy = _readVisibilityPolicy();

    switch (_productSource) {
      case 'manual':
        if (_selectedProductIds.isEmpty) return const [];
        final page = await inventoryService.getProductPageForTenant(
          tenantId: tenantId,
          productIds: _selectedProductIds,
          policy: policy,
          onlyInStock: true,
          limit: _selectedProductIds.length,
        );
        final idOrder = {
          for (int i = 0; i < _selectedProductIds.length; i++)
            _selectedProductIds[i]: i,
        };
        return page.products
          ..sort(
              (a, b) => (idOrder[a.id] ?? 999).compareTo(idOrder[b.id] ?? 999));

      case 'category':
        if (_categoryId == null || _categoryId!.isEmpty) return const [];
        final page = await inventoryService.getProductPageForTenant(
          tenantId: tenantId,
          categoryIds: [_categoryId!],
          policy: policy,
          onlyInStock: true,
          sortBy: 'name',
          limit: _maxProducts,
        );
        return page.products;

      case 'newest':
        final page = await inventoryService.getProductPageForTenant(
          tenantId: tenantId,
          policy: policy,
          onlyInStock: true,
          sortBy: 'newest',
          limit: _maxProducts,
        );
        return page.products;

      case 'featured':
      default:
        if (widget.featuredProducts != null && widget.featuredProductsReady) {
          return widget.featuredProducts!
              .where(
                (product) => policy == null || policy.allowsProduct(product),
              )
              .take(_maxProducts)
              .toList();
        }
        return inventoryService.getFeaturedProductsForTenant(
          tenantId: tenantId,
          policy: policy,
          limit: _maxProducts,
        );
    }
  }

  PublicProductVisibilityPolicy? _readVisibilityPolicy() {
    try {
      final service = context.read<WebsiteService>();
      if (!PublicProductVisibilityPolicy.hasAnySetting(service.settings)) {
        return null;
      }
      return PublicProductVisibilityPolicy.fromSettings(service.settings);
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final contract = _contract;
    final rawTitle = contract.title.trim();
    final title = rawTitle.isEmpty ? 'DESTACADOS' : rawTitle.toUpperCase();
    final subtitle = contract.subtitle.trim();
    final showViewAll = contract.showViewAll;
    final viewAllAction = WebsiteBlockRenderer.visibleNavigationAction(
      WebsiteActionValue.resolvePrimary(
        widget.data,
        labelKeys: const ['viewAllText'],
        hrefKeys: const ['viewAllLink'],
        defaultLabel: 'Ver todos los productos',
        defaultHref: '/productos',
        defaultVariant: WebsiteActionVariant.outline,
        enabled: showViewAll,
      ),
      isNavigationEligible: widget.isNavigationEligible,
    );
    final layout = contract.layout;
    var itemsPerRow = contract.itemsPerRow;

    final viewport = widget.surfaceStyle.viewport;
    final padding = WebsiteBlockRenderer._surfacePadding(
      widget.surfaceStyle,
      blockType: WebsiteBlockType.products,
      data: widget.data,
    );
    final emptyPadding = WebsiteBlockRenderer._surfacePadding(
      widget.surfaceStyle,
      blockType: WebsiteBlockType.products,
      data: widget.data,
      fallback: EdgeInsets.symmetric(
        vertical: 24,
        horizontal:
            widget.surfaceStyle.viewport == WebsiteViewport.mobile ? 16 : 24,
      ),
    );
    final bgColor = widget.surfaceStyle.hasAuthoredBackground
        ? Colors.transparent
        : Colors.white;
    // Grid density is automatic below desktop, while the selected layout is
    // honoured at every width. `itemsPerRow` therefore remains an honest
    // shared desktop base rather than a fake phone/tablet override.
    itemsPerRow = switch (viewport) {
      WebsiteViewport.mobile => 1,
      WebsiteViewport.tablet => 2,
      WebsiteViewport.desktop => itemsPerRow.clamp(2, 4),
    };

    // Show placeholders only during loading
    // Show empty message if no products after loading
    final bool showEmptyState = !_isLoading && _products.isEmpty;
    final displayProducts = _isLoading
        ? _buildSampleProducts(itemsPerRow) // Just 1 row of placeholders
        : _products;

    // If no products after loading, show compact empty state
    if (showEmptyState) {
      return Container(
        color: bgColor,
        width: double.infinity,
        padding: emptyPadding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Section header
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 4,
                  height: 24,
                  color: Colors.black,
                  margin: const EdgeInsets.only(right: 12),
                ),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                    color: Colors.black,
                  ),
                ),
              ],
            ),
            if (subtitle.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                subtitle,
                style: TextStyle(
                  fontFamily: widget.bodyFont,
                  fontSize: 14,
                  color: Colors.black54,
                ),
                textAlign: TextAlign.center,
              ),
            ],
            const SizedBox(height: 24),
            Icon(Icons.inventory_2_outlined, size: 48, color: Colors.grey[400]),
            const SizedBox(height: 12),
            Text(
              'No hay productos disponibles',
              style: TextStyle(fontSize: 16, color: Colors.grey[600]),
            ),
          ],
        ),
      );
    }

    return Container(
      color: bgColor,
      width: double.infinity,
      padding: padding,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1200),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Commencal-style section header with vertical bar
              Row(
                children: [
                  Container(
                    width: 4,
                    height: 28,
                    color: Colors.black,
                    margin: const EdgeInsets.only(right: 12),
                  ),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                        color: Colors.black,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
                  if (_isLoading) ...[
                    const SizedBox(width: 12),
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ],
                ],
              ),
              if (subtitle.isNotEmpty) ...[
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.only(left: 16),
                  child: Text(
                    subtitle,
                    style: TextStyle(
                      fontFamily: widget.bodyFont,
                      fontSize: 14,
                      color: Colors.black54,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 32),
              // Layout is a real rendered property at phone, tablet and
              // desktop widths. Only the carousel implementation adapts to
              // touch-sized pages below the canonical 600 boundary.
              layout == 'carousel'
                  ? viewport == WebsiteViewport.mobile
                      ? _MobileProductAutoCarousel(
                          products: displayProducts,
                          bodyFont: widget.bodyFont,
                          showPrice: contract.showPrice,
                          showSku: contract.showSku,
                          showBrand: contract.showBrand,
                          interactionsEnabled:
                              widget.visitorInteractionsEnabled,
                          onNavigate: widget.onNavigate,
                        )
                      : SizedBox(
                          height: 480,
                          child: ListView.builder(
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.only(bottom: 20),
                            itemCount: displayProducts.length,
                            itemBuilder: (context, index) {
                              final product = displayProducts[index];
                              double cardWidth;
                              if (itemsPerRow <= 2) {
                                cardWidth = 350;
                              } else if (itemsPerRow == 3) {
                                cardWidth = 300;
                              } else {
                                cardWidth = 260;
                              }

                              return Container(
                                width: cardWidth,
                                margin: const EdgeInsets.only(right: 20),
                                child: PremiumProductCard(
                                  productId: product.id,
                                  productSku: product.sku,
                                  productBrand: product.brand,
                                  name: product.name,
                                  price: product.price,
                                  imageUrl: product.imageUrl,
                                  bodyFont: widget.bodyFont,
                                  showPrice: contract.showPrice,
                                  showSku: contract.showSku,
                                  showBrand: contract.showBrand,
                                  interactionsEnabled:
                                      widget.visitorInteractionsEnabled,
                                  onNavigate: widget.onNavigate,
                                ),
                              );
                            },
                          ),
                        )
                  : GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: itemsPerRow,
                        childAspectRatio: 0.75,
                        crossAxisSpacing: 20,
                        mainAxisSpacing: 20,
                      ),
                      itemCount: displayProducts.length,
                      itemBuilder: (context, index) {
                        final product = displayProducts[index];
                        return PremiumProductCard(
                          productId: product.id,
                          productSku: product.sku,
                          productBrand: product.brand,
                          name: product.name,
                          price: product.price,
                          imageUrl: product.imageUrl,
                          bodyFont: widget.bodyFont,
                          showPrice: contract.showPrice,
                          showSku: contract.showSku,
                          showBrand: contract.showBrand,
                          interactionsEnabled:
                              widget.visitorInteractionsEnabled,
                          onNavigate: widget.onNavigate,
                        );
                      },
                    ),
              if (viewAllAction != null) ...[
                const SizedBox(height: 40),
                Center(
                  child: WebsiteActionButton(
                    action: viewAllAction,
                    // Visitor navigation works in Preview and Public; Edit
                    // keeps its enabled-looking inert affordance.
                    onPressed: widget.visitorInteractionsEnabled
                        ? () {
                            if (widget.onNavigate != null) {
                              widget.onNavigate!(viewAllAction.href);
                            }
                          }
                        : () {},
                    backgroundColor: widget.accentColor,
                    foregroundColor: Colors.black,
                    outlineColor: Colors.black,
                    uppercase: true,
                    textStyle: const TextStyle(letterSpacing: 1),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  List<Product> _buildSampleProducts(int count) {
    return List.generate(count, (index) {
      final now = DateTime.now();
      return Product(
        id: 'preview-product-$index',
        name: '',
        sku: 'PREVIEW-${index + 1}',
        price: 0,
        cost: 0,
        stockQuantity: 0,
        imageUrl: null,
        imageUrls: const [],
        description: '',
        category: ProductCategory.other,
        categoryId: null,
        categoryName: null,
        brand: '',
        model: '',
        specifications: const {},
        tags: const [],
        unit: ProductUnit.unit,
        weight: 0,
        trackStock: true,
        isActive: true,
        productType: ProductType.product,
        createdAt: now,
        updatedAt: now,
      );
    });
  }
}

// ============================================================================
// VIDEO BANNER WIDGET - Stateful widget for video playback
// ============================================================================
class _VideoBannerWidget extends StatefulWidget {
  final WebsiteBlockSurfaceStyle surfaceStyle;
  final String title;
  final String subtitle;
  final String? imageUrl;
  final String? youtubeVideoId;
  final String? videoFileUrl;
  final String ctaText;
  final String ctaLink;
  final WebsiteActionVariant actionVariant;
  final bool showCta;
  final double overlayOpacity;
  final Color accentColor;
  final String? headingFont;
  final String? bodyFont;
  final bool previewMode;
  final bool visitorInteractionsEnabled;
  final void Function(String route)? onNavigate;
  final bool hasPlayableVideo;
  final Alignment focalAlignment;

  const _VideoBannerWidget({
    required this.surfaceStyle,
    required this.title,
    required this.subtitle,
    this.imageUrl,
    this.youtubeVideoId,
    this.videoFileUrl,
    required this.ctaText,
    required this.ctaLink,
    required this.actionVariant,
    required this.showCta,
    required this.overlayOpacity,
    required this.accentColor,
    this.headingFont,
    this.bodyFont,
    required this.previewMode,
    this.visitorInteractionsEnabled = true,
    this.onNavigate,
    required this.hasPlayableVideo,
    required this.focalAlignment,
  });

  @override
  State<_VideoBannerWidget> createState() => _VideoBannerWidgetState();
}

class _VideoBannerWidgetState extends State<_VideoBannerWidget> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasImage = widget.imageUrl != null && widget.imageUrl!.isNotEmpty;
    final screenWidth = MediaQuery.of(context).size.width;

    // Check if we can play video (web platform only)
    final canPlayVideo = kIsWeb &&
        widget.hasPlayableVideo &&
        video_platform.VideoBannerPlatform.isSupported;

    // Use LayoutBuilder to fill available height, default to 500 if unconstrained
    return ConstraintLayoutBuilder(
      builder: (context, constraints) {
        final height =
            constraints.maxHeight.isFinite ? constraints.maxHeight : 500.0;
        return Container(
          width: double.infinity,
          height: height,
          decoration: BoxDecoration(
            color: widget.surfaceStyle.hasAuthoredBackground
                ? Colors.transparent
                : const Color(0xFF1a1a1a),
            image: (hasImage && !canPlayVideo)
                ? DecorationImage(
                    image: NetworkImage(widget.imageUrl!),
                    fit: BoxFit.cover,
                    alignment: widget.focalAlignment,
                    // Force rasterization on Web with identity modulate
                    colorFilter: kIsWeb
                        ? const ColorFilter.mode(
                            Color(0xFFFEFEFE), BlendMode.modulate)
                        : null,
                  )
                : null,
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Video background (web only)
              if (canPlayVideo)
                Positioned.fill(
                  child: KeyedSubtree(
                    key: ValueKey<String>(
                      'video_bg:${widget.youtubeVideoId ?? widget.videoFileUrl ?? ''}',
                    ),
                    child:
                        video_platform.VideoBannerPlatform.buildVideoBackground(
                      youtubeVideoId: widget.youtubeVideoId,
                      videoFileUrl: widget.videoFileUrl,
                      width: screenWidth,
                      height: height,
                    ),
                  ),
                ),

              // Overlay gradient
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black
                          .withValues(alpha: widget.overlayOpacity * 0.3),
                      Colors.black.withValues(alpha: widget.overlayOpacity),
                    ],
                  ),
                ),
              ),

              // Content
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 800),
                  child: Padding(
                    padding: widget.surfaceStyle.paddingWithFallback(
                      WebsiteBlockSurfaceDefaults.paddingFor(
                        blockType: WebsiteBlockType.videoBanner,
                        viewport: widget.surfaceStyle.viewport,
                        data: const <String, dynamic>{},
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (widget.title.isNotEmpty)
                          Text(
                            widget.title,
                            style: theme.textTheme.displayMedium?.copyWith(
                              fontFamily: widget.headingFont,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                              letterSpacing: 2,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        if (widget.subtitle.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 16),
                            child: Text(
                              widget.subtitle,
                              style: theme.textTheme.titleLarge?.copyWith(
                                fontFamily: widget.bodyFont,
                                color: Colors.white70,
                                fontStyle: FontStyle.italic,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        if (widget.showCta && widget.ctaText.isNotEmpty) ...[
                          const SizedBox(height: 32),
                          WebsiteActionButton(
                            action: WebsiteActionValue(
                              label: widget.ctaText,
                              href: widget.ctaLink,
                              variant: widget.actionVariant,
                            ),
                            // Visitor navigation works in Preview and
                            // Public; only Edit is inert.
                            onPressed: widget.visitorInteractionsEnabled
                                ? () => widget.onNavigate?.call(widget.ctaLink)
                                : null,
                            backgroundColor: widget.accentColor,
                            foregroundColor: Colors.white,
                            outlineColor: Colors.white,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),

              // Play button overlay for non-web platforms when video is configured
              if (!kIsWeb && widget.hasPlayableVideo)
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.play_arrow_rounded,
                      size: 48,
                      color: Colors.white,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _MobileProductAutoCarousel extends StatefulWidget {
  final List<Product> products;
  final String? bodyFont;
  final bool showPrice;
  final bool showSku;
  final bool showBrand;
  final bool interactionsEnabled;
  final Function(String)? onNavigate;

  const _MobileProductAutoCarousel({
    required this.products,
    this.bodyFont,
    required this.showPrice,
    required this.showSku,
    required this.showBrand,
    this.interactionsEnabled = true,
    this.onNavigate,
  });

  @override
  State<_MobileProductAutoCarousel> createState() =>
      _MobileProductAutoCarouselState();
}

class _MobileProductAutoCarouselState
    extends State<_MobileProductAutoCarousel> {
  late final PageController _pageController;
  Timer? _timer;
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(viewportFraction: 1.0);
    _startTimer();
  }

  void _startTimer() {
    _timer?.cancel();
    if (widget.products.length <= 1) return;

    _timer = Timer.periodic(const Duration(seconds: 3), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      int next = _currentPage + 1;
      if (next >= widget.products.length) {
        next = 0;
        _pageController.animateToPage(
          0,
          duration: const Duration(milliseconds: 800),
          curve: Curves.fastOutSlowIn,
        );
        _currentPage = 0;
      } else {
        _pageController.animateToPage(
          next,
          duration: const Duration(milliseconds: 800),
          curve: Curves.fastOutSlowIn,
        );
        _currentPage = next;
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          height: 520,
          child: PageView.builder(
            controller: _pageController,
            itemCount: widget.products.length,
            onPageChanged: (index) {
              setState(() => _currentPage = index);
            },
            itemBuilder: (context, index) {
              final product = widget.products[index];
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8.0),
                child: PremiumProductCard(
                  productId: product.id,
                  productSku: product.sku,
                  productBrand: product.brand,
                  name: product.name,
                  price: product.price,
                  imageUrl: product.imageUrl,
                  bodyFont: widget.bodyFont,
                  showPrice: widget.showPrice,
                  showSku: widget.showSku,
                  showBrand: widget.showBrand,
                  interactionsEnabled: widget.interactionsEnabled,
                  onNavigate: widget.onNavigate,
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 16),
        if (widget.products.length > 1)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(widget.products.length, (index) {
              final isActive = index == _currentPage;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                margin: const EdgeInsets.symmetric(horizontal: 4),
                height: 8,
                width: isActive ? 24 : 8,
                decoration: BoxDecoration(
                  color: isActive ? Colors.black : Colors.grey[300],
                  borderRadius: BorderRadius.circular(4),
                ),
              );
            }),
          ),
      ],
    );
  }
}
