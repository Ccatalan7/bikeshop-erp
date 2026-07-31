import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/website_service.dart';

import '../../../public_store/providers/public_store_tenant_provider.dart';
import '../../../public_store/services/public_category_publication.dart';
import '../../../public_store/services/public_inventory_service.dart';
import '../../../shared/models/public_product_visibility_policy.dart';
import '../../../shared/services/tenant_service.dart';
import '../../../shared/services/inventory_service.dart';
import '../../../shared/models/product.dart';
import '../../../shared/widgets/hover_scale.dart';
import '../../../shared/widgets/safe_layout_builder.dart';
import '../models/website_font_registry.dart';
import '../models/website_block_type.dart';
import '../models/website_action.dart';
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
    headingFont = WebsiteFontRegistry.resolveOptionalHeadingFont(headingFont);
    bodyFont = WebsiteFontRegistry.resolveOptionalBodyFont(bodyFont);

    switch (type) {
      case WebsiteBlockType.hero:
        return WebsiteHeroBlockContent(
          data: data,
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
        return _buildCarousel(
          context: context,
          data: data,
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
        return _buildText(
          context: context,
          data: data,
          headingFont: headingFont,
          bodyFont: bodyFont,
          headingSize: headingSize,
          bodySize: bodySize,
          inlinePresenter: contentPresenters?.text,
        );
      case WebsiteBlockType.button:
        return _buildButton(
          context: context,
          data: data,
          primaryColor: primaryColor,
          accentColor: accentColor,
          bodyFont: bodyFont,
          bodySize: bodySize,
          onNavigate: onNavigate,
          isNavigationEligible: isNavigationEligible,
          actionPresenter: contentPresenters?.action,
        );
      case WebsiteBlockType.divider:
        return _buildDivider(
          context: context,
          data: data,
        );
      case WebsiteBlockType.products:
        return _buildProducts(
          context: context,
          data: data,
          primaryColor: primaryColor,
          accentColor: accentColor,
          featuredProducts: featuredProducts,
          featuredProductsReady: featuredProductsReady,
          previewMode: previewMode,
          bodyFont: bodyFont,
          onNavigate: onNavigate,
          isNavigationEligible: isNavigationEligible,
          tenantId: tenantId,
        );
      case WebsiteBlockType.services:
        return _withResponsiveContentPadding(
          context: context,
          data: data,
          defaultVertical: 56,
          builder: (padding) => WebsiteServicesBlockContent(
            data: data,
            primaryColor: primaryColor,
            headingFont: headingFont,
            bodyFont: bodyFont,
            presenters: contentPresenters,
            backgroundColor: _parseColor(data['style']?['backgroundColor']),
            padding: padding,
          ),
        );
      case WebsiteBlockType.about:
        return WebsiteAboutBlockContent(
          data: data,
          headingFont: headingFont,
          bodyFont: bodyFont,
          presenters: contentPresenters,
          padding: _parsePadding(
            data,
            defaultVertical: 64,
            screenWidth: MediaQuery.sizeOf(context).width,
          ),
        );
      case WebsiteBlockType.cta:
        return WebsiteCtaBlockContent(
          data: data,
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
          context: context,
          data: data,
          builder: (padding) => WebsiteFeaturesBlockContent(
            data: data,
            primaryColor: primaryColor,
            headingFont: headingFont,
            bodyFont: bodyFont,
            presenters: contentPresenters,
            backgroundColor: _parseColor(data['style']?['backgroundColor']),
            padding: padding,
          ),
        );
      case WebsiteBlockType.testimonials:
        return _withResponsiveContentPadding(
          context: context,
          data: data,
          builder: (padding) => WebsiteTestimonialsBlockContent(
            data: data,
            primaryColor: primaryColor,
            headingFont: headingFont,
            bodyFont: bodyFont,
            presenters: contentPresenters,
            padding: padding,
          ),
        );
      case WebsiteBlockType.pricing:
        return _withResponsiveContentPadding(
          context: context,
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
            padding: padding,
          ),
        );
      case WebsiteBlockType.gallery:
        return _withResponsiveContentPadding(
          context: context,
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
          padding: _parsePadding(
            data,
            screenWidth: MediaQuery.sizeOf(context).width,
            defaultVertical: 64,
            defaultHorizontal: 24,
          ),
        );
      case WebsiteBlockType.faq:
        return _withResponsiveContentPadding(
          context: context,
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
          context: context,
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
          context: context,
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
          primaryColor: primaryColor,
          accentColor: accentColor,
          headingFont: headingFont,
          bodyFont: bodyFont,
          previewMode: previewMode,
          onNavigate: onNavigate,
        );
      case WebsiteBlockType.videoBanner:
        return _buildVideoBanner(
          context: context,
          data: data,
          primaryColor: primaryColor,
          accentColor: accentColor,
          headingFont: headingFont,
          bodyFont: bodyFont,
          previewMode: previewMode,
          onNavigate: onNavigate,
          isNavigationEligible: isNavigationEligible,
        );
      case WebsiteBlockType.partnersBanner:
        return _buildPartnersBanner(
          context: context,
          data: data,
          primaryColor: primaryColor,
          headingFont: headingFont,
          bodyFont: bodyFont,
        );
      case WebsiteBlockType.brandLogos:
        return _buildBrandLogos(
          context: context,
          data: data,
          primaryColor: primaryColor,
          headingFont: headingFont,
          bodyFont: bodyFont,
          previewMode: previewMode,
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
          primaryColor: primaryColor,
          accentColor: accentColor,
          headingFont: headingFont,
          bodyFont: bodyFont,
          previewMode: previewMode,
        );
    }
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

  static Color? _parseColor(dynamic value) {
    if (value == null) return null;
    final hex = value.toString();
    if (hex.isEmpty) return null;
    final buffer = StringBuffer();
    if (hex.length == 6 || hex.length == 7) buffer.write('ff');
    buffer.write(hex.replaceFirst('#', ''));
    try {
      return Color(int.parse(buffer.toString(), radix: 16));
    } catch (_) {
      return null;
    }
  }

  /// Parse rgba color string to Color
  static Color? _parseRgbaColor(String? rgba) {
    if (rgba == null || rgba.isEmpty) return null;
    try {
      // Handle hex colors
      if (rgba.startsWith('#')) return _parseColor(rgba);

      // Handle rgba(r,g,b,a) format
      final match = RegExp(r'rgba?\((\d+),\s*(\d+),\s*(\d+)(?:,\s*([\d.]+))?\)')
          .firstMatch(rgba);
      if (match != null) {
        final r = int.parse(match.group(1)!);
        final g = int.parse(match.group(2)!);
        final b = int.parse(match.group(3)!);
        final a = match.group(4) != null ? double.parse(match.group(4)!) : 1.0;
        return Color.fromRGBO(r, g, b, a);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Get gradient start alignment from direction string
  static Alignment _getGradientBegin(String direction) {
    switch (direction) {
      case 'to-top':
        return Alignment.bottomCenter;
      case 'to-top-right':
        return Alignment.bottomLeft;
      case 'to-right':
        return Alignment.centerLeft;
      case 'to-bottom-right':
        return Alignment.topLeft;
      case 'to-bottom':
        return Alignment.topCenter;
      case 'to-bottom-left':
        return Alignment.topRight;
      case 'to-left':
        return Alignment.centerRight;
      case 'to-top-left':
        return Alignment.bottomRight;
      default:
        return Alignment.topCenter;
    }
  }

  /// Get gradient end alignment from direction string
  static Alignment _getGradientEnd(String direction) {
    switch (direction) {
      case 'to-top':
        return Alignment.topCenter;
      case 'to-top-right':
        return Alignment.topRight;
      case 'to-right':
        return Alignment.centerRight;
      case 'to-bottom-right':
        return Alignment.bottomRight;
      case 'to-bottom':
        return Alignment.bottomCenter;
      case 'to-bottom-left':
        return Alignment.bottomLeft;
      case 'to-left':
        return Alignment.centerLeft;
      case 'to-top-left':
        return Alignment.topLeft;
      default:
        return Alignment.bottomCenter;
    }
  }

  static EdgeInsets _parsePadding(
    Map<String, dynamic> data, {
    double defaultVertical = 64,
    double defaultHorizontal = 24,
    double? screenWidth,
    double mobileHorizontal = 16,
    double mobileBreakpoint = 600,
  }) {
    final resolvedDefaultHorizontal =
        (screenWidth != null && screenWidth < mobileBreakpoint)
            ? mobileHorizontal
            : defaultHorizontal;

    final style = data['style'] as Map<String, dynamic>?;
    if (style == null) {
      return EdgeInsets.symmetric(
        vertical: defaultVertical,
        horizontal: resolvedDefaultHorizontal,
      );
    }

    final top = (style['paddingTop'] as num?)?.toDouble() ?? defaultVertical;
    final bottom =
        (style['paddingBottom'] as num?)?.toDouble() ?? defaultVertical;
    final left =
        (style['paddingLeft'] as num?)?.toDouble() ?? resolvedDefaultHorizontal;
    final right = (style['paddingRight'] as num?)?.toDouble() ??
        resolvedDefaultHorizontal;

    return EdgeInsets.only(
      top: top,
      right: right,
      bottom: bottom,
      left: left,
    );
  }

  static Widget _withResponsiveContentPadding({
    required BuildContext context,
    required Map<String, dynamic> data,
    required Widget Function(EdgeInsets padding) builder,
    double defaultVertical = 64,
    double defaultHorizontal = 24,
  }) {
    return ConstraintLayoutBuilder(
      builder: (context, constraints) {
        final frameWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        return builder(
          _parsePadding(
            data,
            defaultVertical: defaultVertical,
            defaultHorizontal: defaultHorizontal,
            screenWidth: frameWidth,
          ),
        );
      },
    );
  }

  static BoxDecoration _resolveBackgroundDecoration({
    required Map<String, dynamic> data,
    required Color defaultColor,
    String? imageUrl,
    Alignment? imageAlignmentParam,
    bool skipImage = false,
  }) {
    final style = Map<String, dynamic>.from(data['style'] ?? {});
    final hasImage = imageUrl != null && imageUrl.isNotEmpty;
    final backgroundType = style['backgroundType']?.toString() ?? 'solid';

    // Parse border
    final hasBorder = (style['borderWidth'] as num?)?.toDouble() != null &&
        (style['borderWidth'] as num).toDouble() > 0;
    final borderWidth = (style['borderWidth'] as num?)?.toDouble() ?? 0.0;
    final borderColor =
        _parseColor(style['borderColor']?.toString()) ?? Colors.grey;
    final borderStyle = style['borderStyle']?.toString() ?? 'solid';

    // Parse shadow
    final hasShadow = style['shadowEnabled'] == true;
    final shadowOffsetX = (style['shadowOffsetX'] as num?)?.toDouble() ?? 0.0;
    final shadowOffsetY = (style['shadowOffsetY'] as num?)?.toDouble() ?? 4.0;
    final shadowBlur = (style['shadowBlur'] as num?)?.toDouble() ?? 12.0;
    final shadowSpread = (style['shadowSpread'] as num?)?.toDouble() ?? 0.0;
    final shadowColor =
        _parseRgbaColor(style['shadowColor']?.toString()) ?? Colors.black26;

    final imageAlignment = imageAlignmentParam ?? _resolveFocalAlignment(data);

    // Parse border radius (note: typically handled by ClipRRect parent, but we can set it here too)
    final borderRadius = (style['borderRadius'] as num?)?.toDouble() ?? 0.0;

    // Image background takes precedence for the image property,
    // but we might still want a color/gradient behind it (visible while loading or if transparent)
    DecorationImage? image;
    if (hasImage && !skipImage) {
      image = DecorationImage(
        image: NetworkImage(imageUrl),
        fit: BoxFit.cover,
        alignment: imageAlignment,
        // on top of everything. Applying a color filter forces rasterization.
        // We use a slightly off-white (FEFEFE) to prevent the engine from
        // optimizing it away as a no-op identity filter.
        colorFilter: kIsWeb
            ? const ColorFilter.mode(Color(0xFFFEFEFE), BlendMode.modulate)
            : null,
      );
    }

    // Default background color (legacy fallback)
    final bgColor = _parseColor(style['backgroundColor']) ?? defaultColor;

    // Construct Border
    BoxBorder? border;
    if (hasBorder) {
      border = Border.all(
        color: borderColor,
        width: borderWidth,
        style: borderStyle == 'dotted' || borderStyle == 'dashed'
            ? BorderStyle
                .none // Flutter Border doesn't support dotted easily without custom painter, fallback to solid or none?
            // Actually BorderStyle.solid is likely what we want unless completely hidden
            : BorderStyle.solid,
      );
    }

    // Construct Shadow
    List<BoxShadow>? boxShadow;
    if (hasShadow) {
      boxShadow = [
        BoxShadow(
          offset: Offset(shadowOffsetX, shadowOffsetY),
          blurRadius: shadowBlur,
          spreadRadius: shadowSpread,
          color: shadowColor,
        ),
      ];
    }

    if (backgroundType == 'gradient') {
      final gradientColor1 =
          _parseColor(style['gradientColor1']?.toString()) ?? Colors.white;
      final gradientColor2 = _parseColor(style['gradientColor2']?.toString()) ??
          Colors.grey.shade100;
      final gradientDirection =
          style['gradientDirection']?.toString() ?? 'to-bottom';

      return BoxDecoration(
        color: bgColor, // Fallback color
        image: image,
        gradient: !hasImage
            ? LinearGradient(
                begin: _getGradientBegin(gradientDirection),
                end: _getGradientEnd(gradientDirection),
                colors: [gradientColor1, gradientColor2],
              )
            : null,
        border: border,
        borderRadius:
            borderRadius > 0 ? BorderRadius.circular(borderRadius) : null,
        boxShadow: boxShadow,
      );
    }

    // Solid color (or default legacy gradient if no image and no specific style)
    // If style is explicitly 'solid', we use bgColor.
    // Legacy behavior: if no style defined, we created a subtle gradient.
    // We preserve legacy behavior only if style is strictly empty or explicitly asks for it?
    // For now, let's trust the style data.

    // If hasImage is false, and no specific gradient is requested, legacy code did a subtle gradient.
    // We can keep that as a fallback if style is missing.
    final hasStyle = data['style'] != null;

    if (!hasImage && !hasStyle) {
      return BoxDecoration(
        color: bgColor,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            bgColor,
            Color.lerp(bgColor, Colors.black, 0.2)!,
          ],
        ),
        border: border,
        borderRadius:
            borderRadius > 0 ? BorderRadius.circular(borderRadius) : null,
        boxShadow: boxShadow,
      );
    }

    return BoxDecoration(
      color: bgColor,
      image: image,
      border: border,
      borderRadius:
          borderRadius > 0 ? BorderRadius.circular(borderRadius) : null,
      boxShadow: boxShadow,
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

  static Alignment _resolveFocalAlignment(
    Map<String, dynamic> data, {
    double? screenWidth,
  }) {
    final useMobile = screenWidth != null && screenWidth < 600;
    final xKey = useMobile ? 'mobileFocalPointX' : 'focalPointX';
    final yKey = useMobile ? 'mobileFocalPointY' : 'focalPointY';
    final fallbackX = (data['focalPointX'] as num?)?.toDouble();
    final fallbackY = (data['focalPointY'] as num?)?.toDouble();
    final focalX = (data[xKey] as num?)?.toDouble() ?? fallbackX ?? 0.5;
    final focalY = (data[yKey] as num?)?.toDouble() ?? fallbackY ?? 0.5;

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
    required Color primaryColor,
    required Color accentColor,
    List<Product>? featuredProducts,
    bool featuredProductsReady = true,
    bool previewMode = false,
    String? bodyFont,
    void Function(String route)? onNavigate,
    bool Function(String href)? isNavigationEligible,
    String? tenantId,
  }) {
    // Delegate to stateful widget that can fetch its own products
    return _ProductsBlockWidget(
      data: data,
      primaryColor: primaryColor,
      accentColor: accentColor,
      featuredProducts: featuredProducts,
      featuredProductsReady: featuredProductsReady,
      previewMode: previewMode,
      bodyFont: bodyFont,
      onNavigate: onNavigate,
      isNavigationEligible: isNavigationEligible,
      tenantId: tenantId,
    );
  }

  static Widget _buildVideoBanner({
    required BuildContext context,
    required Map<String, dynamic> data,
    required Color primaryColor,
    required Color accentColor,
    String? headingFont,
    String? bodyFont,
    bool previewMode = false,
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
      onNavigate: onNavigate,
      hasPlayableVideo: hasPlayableVideo,
      focalAlignment: _resolveFocalAlignment(
        data,
        screenWidth: MediaQuery.of(context).size.width,
      ),
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
        final containerPadding = _parsePadding(
          data,
          screenWidth: constraints.maxWidth,
          defaultVertical: 64,
          defaultHorizontal: 24,
        );

        return Container(
          width: double.infinity,
          height: hasFixedHeight ? constraints.maxHeight : null,
          decoration: BoxDecoration(
            color: const Color(0xFF1a1a1a),
            image: hasImage
                ? DecorationImage(
                    image: NetworkImage(imageUrl),
                    fit: BoxFit.cover,
                    alignment: _resolveFocalAlignment(
                      data,
                      screenWidth: constraints.maxWidth,
                    ),
                    colorFilter: const ColorFilter.mode(
                      Colors.black54,
                      BlendMode.darken,
                    ),
                  )
                : null,
          ),
          padding: hasFixedHeight ? null : containerPadding,
          child: Center(
            child: Padding(
              padding: hasFixedHeight
                  ? EdgeInsets.only(
                      left: containerPadding.left,
                      right: containerPadding.right,
                    )
                  : EdgeInsets.zero,
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
                          textAlign:
                              titleFormatting.textAlign == TextAlign.start
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
    required Color primaryColor,
    String? headingFont,
    String? bodyFont,
    bool previewMode = false,
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
        final containerPadding = _parsePadding(
          data,
          screenWidth: constraints.maxWidth,
          defaultVertical: 48,
          defaultHorizontal: 16,
          mobileHorizontal: 16,
        );

        return Container(
          width: double.infinity,
          height: hasFixedHeight ? constraints.maxHeight : null,
          color: Colors.white,
          padding: hasFixedHeight
              ? EdgeInsets.only(
                  left: containerPadding.left,
                  right: containerPadding.right,
                )
              : containerPadding,
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
                  padding: hasFixedHeight
                      ? EdgeInsets.zero
                      : EdgeInsets.only(
                          left: containerPadding.left,
                          right: containerPadding.right,
                        ),
                  child: _BrandLogosCarousel(
                    brands: brands,
                    bodyFont: bodyFont,
                    logoHeight: logoHeight,
                    gap: gap,
                    previewMode: previewMode,
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
  final bool previewMode;
  final void Function(String route)? onNavigate;
  final bool Function(String href)? isNavigationEligible;

  const _BrandLogosCarousel({
    required this.brands,
    this.bodyFont,
    this.logoHeight = 90,
    this.gap = 40,
    required this.previewMode,
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
                            previewMode: widget.previewMode,
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
  final bool previewMode;
  final void Function(String route)? onNavigate;
  final bool Function(String href)? isNavigationEligible;

  const _BrandLogoItem({
    required this.brand,
    this.bodyFont,
    this.width = 140,
    this.height = 90,
    required this.previewMode,
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
          onTap: previewMode ? null : () => onNavigate?.call(link),
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
  final Color primaryColor;
  final Color accentColor;
  final String? headingFont;
  final String? bodyFont;
  final bool previewMode;
  final void Function(String route)? onNavigate;

  const _AutoCategoryGrid({
    required this.data,
    required this.primaryColor,
    required this.accentColor,
    this.headingFont,
    this.bodyFont,
    required this.previewMode,
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
    final title = (widget.data['title'] ?? '').toString().trim();
    final subtitle = (widget.data['subtitle'] ?? '').toString().trim();

    // Publication comes only from Catálogo web. Manual block data may style or
    // order cards, but an empty authoritative result must remain empty.
    final categories = _categories ?? const <Map<String, dynamic>>[];

    // Show placeholder while loading
    if (_isLoading) {
      return Container(
        width: double.infinity,
        color: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 48),
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
          color: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
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
      color: Colors.white,
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                title,
                style: theme.textTheme.displaySmall?.copyWith(
                  fontFamily: widget.headingFont,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
            ),
            if (subtitle.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8, left: 24, right: 24),
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
            previewMode: widget.previewMode,
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
  final bool previewMode;
  final void Function(String route)? onNavigate;

  const _CategoryGridLayout({
    required this.categories,
    required this.primaryColor,
    required this.accentColor,
    this.bodyFont,
    required this.previewMode,
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
              previewMode: previewMode,
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
                            previewMode: previewMode,
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
                                  previewMode: previewMode,
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
                      previewMode: previewMode,
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
                      previewMode: previewMode,
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
  final bool previewMode;
  final void Function(String route)? onNavigate;

  const _CategoryCard({
    required this.data,
    required this.height,
    required this.primaryColor,
    required this.accentColor,
    this.bodyFont,
    required this.previewMode,
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
                alignment: WebsiteBlockRenderer._resolveFocalAlignment(
                  data,
                  screenWidth: MediaQuery.of(context).size.width,
                ),
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
              onTap: previewMode ? null : () => onNavigate?.call(href),
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

  static ValueKey<String> slideKey(int index) =>
      ValueKey<String>('website-carousel-slide-$index');

  static ValueKey<String> indicatorKey(int index) =>
      ValueKey<String>('website-carousel-indicator-$index');

  final Map<String, dynamic> data;
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
                        onPressed: !widget.previewMode &&
                                widget.presenters == null &&
                                action.href.trim().isNotEmpty &&
                                widget.onNavigate != null
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
      final compositionData = <String, dynamic>{
        'backgroundColor': '#00000000',
        'showGrid': widget.editBinding != null,
        'snap': true,
        'designWidth': (slide['designWidth'] as num?)?.toDouble() ?? 1200.0,
        'mobileDesignWidth':
            (slide['mobileDesignWidth'] as num?)?.toDouble() ?? 390.0,
        'constrainElementsToSafeArea':
            slide['constrainElementsToSafeArea'] != false,
        'blockHeight': (slide['designHeight'] as num?)?.toDouble() ?? 750.0,
        'elements': compositionElements,
      };
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
            onNavigate: widget.previewMode ? null : widget.onNavigate,
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

    // No video or web not supported - use image/gradient background
    // Use the block's style data for gradients (fall back to slide's image if present)
    final slideWithStyle = Map<String, dynamic>.from(slide);
    // If the slide doesn't have its own style, use the block's style
    if (slide['style'] == null && widget.data['style'] != null) {
      slideWithStyle['style'] = widget.data['style'];
    }

    // Resolve Mobile Background Alignment for Carousel Slide
    // Priority: focal point values > legacy preset alignment > center default
    Alignment? slideBgAlignment;
    final isMobile = maxWidth < 600;

    if (isMobile) {
      final focalX = (slide['mobileFocalPointX'] as num?)?.toDouble();
      final focalY = (slide['mobileFocalPointY'] as num?)?.toDouble();

      if (focalX != null && focalY != null) {
        // Convert from 0-1 range to -1 to 1 range for Alignment
        slideBgAlignment = Alignment(
          (focalX * 2) - 1,
          (focalY * 2) - 1,
        );
      } else if (slide['mobileBgAlignment'] != null) {
        // Legacy fallback
        switch (slide['mobileBgAlignment'].toString()) {
          case 'left':
          case 'centerLeft':
            slideBgAlignment = Alignment.centerLeft;
            break;
          case 'right':
          case 'centerRight':
            slideBgAlignment = Alignment.centerRight;
            break;
          case 'top':
          case 'topCenter':
            slideBgAlignment = Alignment.topCenter;
            break;
          case 'bottom':
          case 'bottomCenter':
            slideBgAlignment = Alignment.bottomCenter;
            break;
          case 'center':
          default:
            slideBgAlignment = Alignment.center;
        }
      }
    }

    final decoration = WebsiteBlockRenderer._resolveBackgroundDecoration(
      data: slideWithStyle,
      defaultColor: const Color(0xFF1a1a1a),
      imageUrl: hasImage ? imageUrl.toString() : null,
      imageAlignmentParam: slideBgAlignment,
    );
    final mediaPresenter = widget.presenters?.media;
    if (mediaPresenter != null) {
      final fallbackDecoration =
          WebsiteBlockRenderer._resolveBackgroundDecoration(
        data: slideWithStyle,
        defaultColor: const Color(0xFF1a1a1a),
        imageUrl: null,
        imageAlignmentParam: slideBgAlignment,
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
              alignment: slideBgAlignment ?? Alignment.center,
              fallback: DecoratedBox(decoration: fallbackDecoration),
              semanticLabel:
                  (slide['imageAltText'] ?? slide['altText'])?.toString(),
              repeaterTarget: repeaterTarget,
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
        decoration: const BoxDecoration(
          color: Colors.black45,
          shape: BoxShape.circle,
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
                    color: Colors.white,
                  ),
                )
              : Icon(icon, color: Colors.white, size: 28),
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
  final Color primaryColor;
  final Color accentColor;
  final List<Product>? featuredProducts;
  final bool featuredProductsReady;
  final bool previewMode;
  final String? bodyFont;
  final void Function(String route)? onNavigate;
  final bool Function(String href)? isNavigationEligible;
  final String? tenantId;

  const _ProductsBlockWidget({
    required this.data,
    required this.primaryColor,
    required this.accentColor,
    this.featuredProducts,
    this.featuredProductsReady = true,
    this.previewMode = false,
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
    final ownerChanged =
        oldWidget.data['productSource'] != widget.data['productSource'] ||
            oldWidget.data['selectedProducts']?.toString() !=
                widget.data['selectedProducts']?.toString() ||
            oldWidget.data['categoryId'] != widget.data['categoryId'] ||
            oldWidget.data['maxProducts'] != widget.data['maxProducts'] ||
            oldWidget.tenantId != widget.tenantId ||
            oldWidget.previewMode != widget.previewMode;
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
    if (!mounted || widget.previewMode || _usesParentFeaturedProducts) return;
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

  String get _productSource =>
      widget.data['productSource']?.toString() ?? 'featured';
  bool get _usesParentFeaturedProducts =>
      !widget.previewMode &&
      _productSource == 'featured' &&
      widget.featuredProducts != null;

  List<String> get _selectedProductIds {
    final raw = widget.data['selectedProducts'];
    if (raw is List) return raw.map((e) => e.toString()).toList();
    return [];
  }

  String? get _categoryId => widget.data['categoryId']?.toString();
  int get _maxProducts => (widget.data['maxProducts'] as num?)?.toInt() ?? 8;

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
      if (!widget.previewMode &&
          _productSource == 'featured' &&
          widget.featuredProducts != null &&
          !widget.featuredProductsReady) {
        return;
      }

      final supabase = Supabase.instance.client;
      List<Product> products = [];

      if (!widget.previewMode) {
        products = await _loadPublicProductsFromPolicy();
        _applyLoadedProducts(products, loadToken: loadToken);
        return;
      }

      // We have tenantId - fetch based on source
      switch (_productSource) {
        case 'manual':
          // Fetch specific products by ID
          if (_selectedProductIds.isNotEmpty) {
            dynamic query = supabase
                .from('products')
                .select(Product.storefrontPreviewSelect)
                .eq('tenant_id', tenantId)
                .inFilter('id', _selectedProductIds)
                .eq('is_active', true);
            if (!widget.previewMode) {
              query =
                  query.eq('is_published', true).eq('show_on_website', true);
            }
            final response = await query;

            products = _parseProducts(response);

            // Sort by the order in selectedProductIds
            final idOrder = {
              for (int i = 0; i < _selectedProductIds.length; i++)
                _selectedProductIds[i]: i
            };
            products.sort((a, b) =>
                (idOrder[a.id] ?? 999).compareTo(idOrder[b.id] ?? 999));
          }
          break;

        case 'category':
          // Fetch products from a specific category
          if (_categoryId != null && _categoryId!.isNotEmpty) {
            dynamic query = supabase
                .from('products')
                .select(Product.storefrontPreviewSelect)
                .eq('tenant_id', tenantId)
                .eq('category_id', _categoryId!)
                .eq('is_active', true)
                .eq('show_on_website', true);
            if (!widget.previewMode) {
              query = query.eq('is_published', true);
            }
            final response = await query.order('name').limit(_maxProducts);

            products = _parseProducts(response);
          }
          break;

        case 'newest':
          // Fetch newest products
          dynamic newestQuery = supabase
              .from('products')
              .select(Product.storefrontPreviewSelect)
              .eq('tenant_id', tenantId)
              .eq('is_active', true)
              .eq('show_on_website', true);
          if (!widget.previewMode) {
            newestQuery = newestQuery.eq('is_published', true);
          }
          final response = await newestQuery
              .order('created_at', ascending: false)
              .limit(_maxProducts);

          products = _parseProducts(response);
          break;

        case 'featured':
        default:
          // Use the passed featured products or fetch from featured_products table
          if (widget.featuredProducts != null &&
              widget.featuredProducts!.isNotEmpty) {
            products = widget.featuredProducts!
                .where((p) {
                  if (!p.isActive) return false;
                  if (!widget.previewMode && !p.isPublished) return false;
                  return true;
                })
                .take(_maxProducts)
                .toList();
          } else {
            // Fallback: fetch products marked as show_on_website
            dynamic fallbackQuery = supabase
                .from('products')
                .select(Product.storefrontPreviewSelect)
                .eq('tenant_id', tenantId)
                .eq('is_active', true)
                .eq('show_on_website', true);
            if (!widget.previewMode) {
              fallbackQuery = fallbackQuery.eq('is_published', true);
            }
            final response =
                await fallbackQuery.order('name').limit(_maxProducts);

            products = _parseProducts(response);
          }
          break;
      }

      products = await _hydratePreviewAvailability(products);
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

  Future<List<Product>> _hydratePreviewAvailability(
    List<Product> products,
  ) async {
    if (products.isEmpty) return products;
    try {
      final hydrated = await context.read<InventoryService>().getProductsByIds(
            products.map((product) => product.id),
            forceRefresh: true,
          );
      final byId = {for (final product in hydrated) product.id: product};
      return products
          .map((product) => byId[product.id] ?? product)
          .toList(growable: false);
    } catch (error) {
      debugPrint('[ProductsBlock] Set availability unavailable: $error');
      return products;
    }
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
        final page = await inventoryService.getProductPageForTenant(
          tenantId: tenantId,
          policy: policy,
          onlyInStock: true,
          sortBy: 'name',
          limit: _maxProducts,
        );
        return page.products;
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

  List<Product> _parseProducts(dynamic response) {
    if (response is! List) return [];

    return response
        .map((row) {
          try {
            final map = Map<String, dynamic>.from(row as Map);
            return Product(
              id: map['id']?.toString() ?? '',
              name: map['name']?.toString() ?? 'Producto',
              sku: map['sku']?.toString() ?? '',
              price: (map['price'] as num?)?.toDouble() ?? 0,
              cost: (map['cost'] as num?)?.toDouble() ?? 0,
              stockQuantity: (map['inventory_qty'] as num?)?.toInt() ??
                  (map['stock_quantity'] as num?)?.toInt() ??
                  0,
              imageUrl: map['image_url']?.toString(),
              imageUrls: (map['image_urls'] as List?)?.cast<String>() ?? [],
              description: map['description']?.toString() ?? '',
              category: ProductCategory.other,
              categoryId: map['category_id']?.toString(),
              categoryName: map['category_name']?.toString(),
              brand: map['brand']?.toString() ?? '',
              model: map['model']?.toString() ?? '',
              specifications: _parseSpecifications(map['specifications']),
              tags: (map['tags'] as List?)?.cast<String>() ?? [],
              unit: ProductUnit.unit,
              weight: (map['weight'] as num?)?.toDouble() ?? 0,
              trackStock: map['track_stock'] as bool? ?? true,
              isActive: map['is_active'] as bool? ?? true,
              isPublished: map['is_published'] as bool? ??
                  map['show_on_website'] as bool? ??
                  true,
              isSet: map['is_set'] as bool? ?? false,
              setType: SetType.values.cast<SetType?>().firstWhere(
                    (type) => type?.name == map['set_type']?.toString(),
                    orElse: () => null,
                  ),
              parentSetId: map['parent_set_id']?.toString(),
              componentLabel: map['component_label']?.toString(),
              componentPosition: (map['component_position'] as num?)?.toInt(),
              productType: ProductType.values.firstWhere(
                (type) => type.name == map['product_type']?.toString(),
                orElse: () => ProductType.product,
              ),
              createdAt:
                  DateTime.tryParse(map['created_at']?.toString() ?? '') ??
                      DateTime.now(),
              updatedAt:
                  DateTime.tryParse(map['updated_at']?.toString() ?? '') ??
                      DateTime.now(),
            );
          } catch (e) {
            debugPrint('[ProductsBlock] Error parsing product: $e');
            return null;
          }
        })
        .whereType<Product>()
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final rawTitle =
        (widget.data['title'] ?? 'Productos Destacados').toString().trim();
    final title = rawTitle.isEmpty ? 'DESTACADOS' : rawTitle.toUpperCase();
    final showViewAll = widget.data['showViewAll'] ?? true;
    final viewAllAction = WebsiteBlockRenderer.visibleNavigationAction(
      WebsiteActionValue.resolvePrimary(
        widget.data,
        labelKeys: const ['viewAllText'],
        hrefKeys: const ['viewAllLink'],
        defaultLabel: 'Ver todos los productos',
        defaultHref: '/productos',
        defaultVariant: WebsiteActionVariant.outline,
        enabled: showViewAll == true,
      ),
      isNavigationEligible: widget.isNavigationEligible,
    );
    final layout = widget.data['layout']?.toString() ?? 'grid';

    int itemsPerRow = 3;
    final rawItemsPerRow = widget.data['itemsPerRow'];
    if (rawItemsPerRow is int) {
      itemsPerRow = rawItemsPerRow;
    } else if (rawItemsPerRow is num) {
      itemsPerRow = rawItemsPerRow.toInt();
    } else if (rawItemsPerRow is String) {
      final parsed = int.tryParse(rawItemsPerRow);
      if (parsed != null) {
        itemsPerRow = parsed;
      }
    }

    // Responsive override
    final screenWidth = MediaQuery.of(context).size.width;
    final padding = WebsiteBlockRenderer._parsePadding(
      widget.data,
      defaultVertical: 48,
      screenWidth: screenWidth,
    );
    final emptyPadding = WebsiteBlockRenderer._parsePadding(
      widget.data,
      defaultVertical: 24,
      screenWidth: screenWidth,
    );
    final bgColor = WebsiteBlockRenderer._parseColor(
          widget.data['style']?['backgroundColor']?.toString(),
        ) ??
        Colors.white;
    if (screenWidth < 450) {
      itemsPerRow = 1;
    } else if (screenWidth < 900) {
      itemsPerRow = 2;
    } else {
      itemsPerRow = itemsPerRow.clamp(2, 4);
    }

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
              const SizedBox(height: 32),
              // Responsive override for mobile
              screenWidth < 700
                  ? _MobileProductAutoCarousel(
                      products: displayProducts,
                      bodyFont: widget.bodyFont,
                      previewMode: widget.previewMode,
                      onNavigate: widget.onNavigate,
                    )
                  : layout == 'carousel'
                      ? SizedBox(
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
                                  name: product.name,
                                  price: product.price,
                                  imageUrl: product.imageUrl,
                                  bodyFont: widget.bodyFont,
                                  previewMode: widget.previewMode,
                                  onNavigate: widget.onNavigate,
                                ),
                              );
                            },
                          ),
                        )
                      : GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
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
                              name: product.name,
                              price: product.price,
                              imageUrl: product.imageUrl,
                              bodyFont: widget.bodyFont,
                              previewMode: widget.previewMode,
                              onNavigate: widget.onNavigate,
                            );
                          },
                        ),
              if (viewAllAction != null) ...[
                const SizedBox(height: 40),
                Center(
                  child: WebsiteActionButton(
                    action: viewAllAction,
                    onPressed: widget.previewMode
                        ? () {}
                        : () {
                            if (widget.onNavigate != null) {
                              widget.onNavigate!(viewAllAction.href);
                            }
                          },
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

  Map<String, String> _parseSpecifications(dynamic raw) {
    if (raw == null) return {};
    if (raw is Map) {
      return raw
          .map((key, value) => MapEntry(key.toString(), value.toString()));
    }
    return {};
  }
}

// ============================================================================
// VIDEO BANNER WIDGET - Stateful widget for video playback
// ============================================================================
class _VideoBannerWidget extends StatefulWidget {
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
  final void Function(String route)? onNavigate;
  final bool hasPlayableVideo;
  final Alignment focalAlignment;

  const _VideoBannerWidget({
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
            color: const Color(0xFF1a1a1a),
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
                    padding: const EdgeInsets.all(24),
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
                            onPressed: widget.previewMode
                                ? null
                                : () => widget.onNavigate?.call(widget.ctaLink),
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
  final bool previewMode;
  final Function(String)? onNavigate;

  const _MobileProductAutoCarousel({
    required this.products,
    this.bodyFont,
    this.previewMode = false,
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
                  name: product.name,
                  price: product.price,
                  imageUrl: product.imageUrl,
                  bodyFont: widget.bodyFont,
                  previewMode: widget.previewMode,
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
