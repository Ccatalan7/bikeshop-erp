import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/website_service.dart';

// import '../../../public_store/theme/public_store_theme.dart'; // Unused
import '../../../shared/models/product.dart';
import '../../../shared/widgets/hover_scale.dart';
import '../models/website_block_type.dart';
import 'deferred_canvas_block.dart';
import 'premium_product_card.dart';
import 'text_formatting_toolbar.dart';
import 'google_reviews_carousel.dart';

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

  static ({String label, String to})? _resolvePrimaryNavigateAction(
    Map<String, dynamic> data, {
    required String fallbackLabel,
    required String fallbackTo,
    bool enabled = true,
  }) {
    if (!enabled) return null;

    final actionsRaw = data['actions'];
    if (actionsRaw is List) {
      for (final item in actionsRaw) {
        if (item is! Map) continue;
        final map = Map<String, dynamic>.from(item);
        final type = (map['type'] ?? '').toString().trim().toLowerCase();
        // Treat empty type as navigate for forward-compat.
        if (type.isNotEmpty && type != 'navigate') continue;

        final to = (map['to'] ?? map['href'] ?? '').toString().trim();
        if (to.isEmpty) continue;
        final label =
            (map['label'] ?? map['text'] ?? fallbackLabel).toString().trim();
        return (
          label: label.isNotEmpty
              ? label
              : (fallbackLabel.isNotEmpty ? fallbackLabel : 'Ver más'),
          to: to,
        );
      }
    }

    final to = fallbackTo.trim();
    if (to.isEmpty) return null;

    final label = fallbackLabel.trim();
    return (
      label: label.isNotEmpty ? label : 'Ver más',
      to: to,
    );
  }

  static Widget build({
    required BuildContext context,
    required String blockType,
    required Map<String, dynamic> data,
    required Color primaryColor,
    required Color accentColor,
    List<Product>? featuredProducts,
    bool previewMode = false,
    String? headingFont,
    String? bodyFont,
    double? headingSize,
    double? bodySize,
    void Function(String route)? onNavigate,
    String? tenantId,
  }) {
    final type = parseWebsiteBlockType(blockType);

    switch (type) {
      case WebsiteBlockType.hero:
        return _buildHero(
          context: context,
          data: data,
          accentColor: accentColor,
          primaryColor: primaryColor,
          previewMode: previewMode,
          headingFont: headingFont,
          bodyFont: bodyFont,
          headingSize: headingSize,
          bodySize: bodySize,
          onNavigate: onNavigate,
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
        );
      case WebsiteBlockType.canvas:
        return _buildCanvas(
          context: context,
          data: data,
          accentColor: accentColor,
          onNavigate: onNavigate,
          tenantId: tenantId,
          bodyFont: bodyFont,
        );
      case WebsiteBlockType.text:
        return _buildText(
          context: context,
          data: data,
          headingFont: headingFont,
          bodyFont: bodyFont,
          headingSize: headingSize,
          bodySize: bodySize,
          previewMode: previewMode,
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
          previewMode: previewMode,
          bodyFont: bodyFont,
          onNavigate: onNavigate,
          tenantId: tenantId,
        );
      case WebsiteBlockType.services:
        return _buildServices(
          context: context,
          data: data,
          primaryColor: primaryColor,
          previewMode: previewMode,
          headingFont: headingFont,
          bodyFont: bodyFont,
        );
      case WebsiteBlockType.about:
        return _buildAbout(
          context: context,
          data: data,
          headingFont: headingFont,
          bodyFont: bodyFont,
        );
      case WebsiteBlockType.cta:
        return _buildCta(
          context: context,
          data: data,
          primaryColor: primaryColor,
          accentColor: accentColor,
          previewMode: previewMode,
          headingFont: headingFont,
          bodyFont: bodyFont,
          onNavigate: onNavigate,
        );
      case WebsiteBlockType.features:
        return _buildFeatures(
          context: context,
          data: data,
          primaryColor: primaryColor,
          headingFont: headingFont,
          bodyFont: bodyFont,
        );
      case WebsiteBlockType.testimonials:
        return _buildTestimonials(
          context: context,
          data: data,
          primaryColor: primaryColor,
          headingFont: headingFont,
          bodyFont: bodyFont,
          previewMode: previewMode,
        );
      case WebsiteBlockType.pricing:
        return _buildPricing(
          context: context,
          data: data,
          primaryColor: primaryColor,
          accentColor: accentColor,
          headingFont: headingFont,
          bodyFont: bodyFont,
          previewMode: previewMode,
          onNavigate: onNavigate,
        );
      case WebsiteBlockType.gallery:
        return _buildGallery(
          context: context,
          data: data,
          primaryColor: primaryColor,
          previewMode: previewMode,
          headingFont: headingFont,
          bodyFont: bodyFont,
        );
      case WebsiteBlockType.contact:
        return _buildContact(
          context: context,
          data: data,
          primaryColor: primaryColor,
          accentColor: accentColor,
          headingFont: headingFont,
          bodyFont: bodyFont,
          previewMode: previewMode,
          onNavigate: onNavigate,
        );
      case WebsiteBlockType.faq:
        return _buildFaq(
          context: context,
          data: data,
          primaryColor: primaryColor,
          headingFont: headingFont,
          bodyFont: bodyFont,
        );
      case WebsiteBlockType.stats:
        return _buildStats(
          context: context,
          data: data,
          primaryColor: primaryColor,
          accentColor: accentColor,
          headingFont: headingFont,
          bodyFont: bodyFont,
        );
      case WebsiteBlockType.team:
        return _buildTeam(
          context: context,
          data: data,
          primaryColor: primaryColor,
          accentColor: accentColor,
          headingFont: headingFont,
          bodyFont: bodyFont,
          previewMode: previewMode,
        );
      case WebsiteBlockType.footer:
        return const SizedBox(height: 64);
      case WebsiteBlockType.categoryGrid:
        return _buildCategoryGrid(
          context: context,
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
        );
      case WebsiteBlockType.googleReviews:
        // Inject synced reviews if block doesn't have custom ones
        var effectiveData = data;
        if ((data['reviews'] as List?)?.isEmpty ?? true) {
          try {
            // Access service safely (without listen to avoid redundant rebuilds here, parent handles it)
            final service = Provider.of<WebsiteService>(context, listen: false);
            final jsonStr = service.getSetting('google_reviews_data');
            if (jsonStr.isNotEmpty) {
              final list = jsonDecode(jsonStr) as List;
              final reviews =
                  list.map((e) => Map<String, dynamic>.from(e)).toList();

              // Create new map to avoid mutating original
              effectiveData = Map<String, dynamic>.from(data);
              effectiveData['reviews'] = reviews;
            }
          } catch (e) {
            debugPrint('Error injecting reviews: $e');
          }
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
    String? tenantId,
    String? bodyFont,
  }) {
    return DeferredCanvasBlock(
      data: data,
      accentColor: accentColor,
      onNavigate: onNavigate,
      tenantId: tenantId,
      bodyFont: bodyFont,
    );
  }

  static Widget _buildText({
    required BuildContext context,
    required Map<String, dynamic> data,
    required bool previewMode,
    String? headingFont,
    String? bodyFont,
    double? headingSize,
    double? bodySize,
  }) {
    final text = (data['text'] ?? '').toString();
    final preset = (data['preset'] ?? 'paragraph').toString();
    final maxWidth = (data['maxWidth'] as num?)?.toDouble();
    final formatting =
        TextFormatting.fromJson(data['formatting'] as Map<String, dynamic>?);

    TextStyle base;
    switch (preset) {
      case 'heading':
        base = Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  fontFamily: headingFont,
                  fontSize: headingSize,
                ) ??
            TextStyle(
              fontSize: headingSize ?? 36,
              fontWeight: FontWeight.w700,
              fontFamily: headingFont,
            );
        break;
      case 'subheading':
        base = Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                  fontFamily: headingFont,
                ) ??
            TextStyle(
              fontSize: (bodySize ?? 16) * 1.25,
              fontWeight: FontWeight.w600,
              fontFamily: headingFont,
            );
        break;
      case 'caption':
        base = Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontFamily: bodyFont,
                  fontSize: (bodySize ?? 16) * 0.9,
                ) ??
            TextStyle(
              fontSize: (bodySize ?? 16) * 0.9,
              fontFamily: bodyFont,
            );
        break;
      default:
        base = Theme.of(context).textTheme.bodyLarge?.copyWith(
                  fontFamily: bodyFont,
                  fontSize: bodySize,
                ) ??
            TextStyle(
              fontSize: bodySize ?? 16,
              fontFamily: bodyFont,
            );
    }

    final effectiveStyle = formatting.applyTo(base);
    final align = formatting.textAlign;

    Widget content = Text(
      text.isEmpty && previewMode ? 'Texto' : text,
      style: effectiveStyle,
      textAlign: align,
    );

    if (maxWidth != null) {
      content = Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth.clamp(200, 1600)),
          child: content,
        ),
      );
    }

    return content;
  }

  static Widget _buildButton({
    required BuildContext context,
    required Map<String, dynamic> data,
    required Color primaryColor,
    required Color accentColor,
    void Function(String route)? onNavigate,
    String? bodyFont,
    double? bodySize,
  }) {
    final label = (data['label'] ?? 'Botón').toString();
    final link = (data['link'] ?? '').toString().trim();
    final style = (data['style'] ?? 'filled').toString();

    final textStyle = TextStyle(
      fontFamily: bodyFont,
      fontSize: bodySize ?? 16,
      fontWeight: FontWeight.w600,
    );

    VoidCallback? onPressed;
    if (link.isNotEmpty && onNavigate != null) {
      onPressed = () => onNavigate(link);
    }

    late final Widget button;

    switch (style) {
      case 'outline':
        button = OutlinedButton(
          onPressed: onPressed,
          style: OutlinedButton.styleFrom(
            foregroundColor: accentColor,
            side: BorderSide(color: accentColor),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          ),
          child: Text(label, style: textStyle),
        );
        break;
      case 'text':
        button = TextButton(
          onPressed: onPressed,
          style: TextButton.styleFrom(
            foregroundColor: accentColor,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
          child: Text(label, style: textStyle),
        );
        break;
      default:
        button = ElevatedButton(
          onPressed: onPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: accentColor,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          ),
          child: Text(label, style: textStyle.copyWith(color: Colors.white)),
        );
        break;
    }

    final bool isEnabled = onPressed != null;

    return HoverScale(
      enabled: isEnabled,
      hoverScale: 1.03,
      pressedScale: 0.98,
      child: button,
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

    final imageAlignment =
        imageAlignmentParam ?? Alignment.center; // Use parameter if provided

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

  static Widget _buildHero({
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
  }) {
    final theme = Theme.of(context);

    final title = (data['title'] ?? 'Bienvenido').toString().trim();
    final subtitle = (data['subtitle'] ?? '').toString().trim();
    final legacyCtaText =
        (data['ctaText'] ?? data['buttonText'] ?? 'Ver más').toString().trim();
    final legacyCtaLink =
        (data['ctaLink'] ?? data['buttonLink'] ?? '/productos')
            .toString()
            .trim();
    final primaryAction = _resolvePrimaryNavigateAction(
      data,
      fallbackLabel: legacyCtaText,
      fallbackTo: legacyCtaLink,
    );
    final imageUrl = data['imageUrl'] ?? data['backgroundImage'];
    final showOverlay = (data['showOverlay'] ?? true) == true;
    final overlayOpacity =
        ((data['overlayOpacity'] ?? 0.5) as num).clamp(0.0, 1.0).toDouble();

    // Use style background if no image
    final defaultBgColor = const Color(0xFF1a1a1a);

    // New Props for Alignment and Full Screen
    final isFullScreen = data['isFullScreen'] == true;
    final alignment =
        data['alignment']?.toString() ?? 'center'; // center, left, right

    final resolvedHeading = _applyThemeFont(
      (theme.textTheme.displayLarge ?? const TextStyle()).copyWith(
        fontSize: headingSize,
        color: Colors.white,
      ),
      headingFont,
    );

    final resolvedSubtitle = _applyThemeFont(
      (theme.textTheme.headlineSmall ?? const TextStyle()).copyWith(
        fontSize: bodySize != null ? bodySize * 1.2 : null,
        color: Colors.white70,
      ),
      bodyFont,
    );

    // Resolve alignment logic
    CrossAxisAlignment crossAlign;
    TextAlign textAlign;
    Alignment geometryAlign;

    switch (alignment) {
      case 'left':
        crossAlign = CrossAxisAlignment.start;
        textAlign = TextAlign.left;
        geometryAlign = Alignment.centerLeft;
        break;
      case 'right':
        crossAlign = CrossAxisAlignment.end;
        textAlign = TextAlign.right;
        geometryAlign = Alignment.centerRight;
        break;
      default:
        crossAlign = CrossAxisAlignment.center;
        textAlign = TextAlign.center;
        geometryAlign = Alignment.center;
    }

    return LayoutBuilder(builder: (context, constraints) {
      final screenWidth = constraints.maxWidth;
      // Use 600 as mobile breakpoint (standard)
      final isMobile = screenWidth < 600;

      // Resolve Mobile Background Alignment
      // Priority: focal point values > legacy preset alignment > center default
      Alignment? bgAlignment;
      if (isMobile) {
        final focalX = (data['mobileFocalPointX'] as num?)?.toDouble();
        final focalY = (data['mobileFocalPointY'] as num?)?.toDouble();

        if (focalX != null && focalY != null) {
          // Convert from 0-1 range to -1 to 1 range for Alignment
          bgAlignment = Alignment(
            (focalX * 2) - 1, // 0→-1, 0.5→0, 1→1
            (focalY * 2) - 1,
          );
        } else if (data['mobileBgAlignment'] != null) {
          // Legacy fallback: preset alignment strings
          switch (data['mobileBgAlignment']) {
            case 'left':
            case 'centerLeft':
              bgAlignment = Alignment.centerLeft;
              break;
            case 'right':
            case 'centerRight':
              bgAlignment = Alignment.centerRight;
              break;
            case 'top':
            case 'topCenter':
              bgAlignment = Alignment.topCenter;
              break;
            case 'bottom':
            case 'bottomCenter':
              bgAlignment = Alignment.bottomCenter;
              break;
            case 'center':
            default:
              bgAlignment = Alignment.center;
          }
        }
      }

      final decoration = _resolveBackgroundDecoration(
        data: data,
        defaultColor: defaultBgColor,
        imageUrl: imageUrl?.toString(),
        imageAlignmentParam: bgAlignment,
      );

      final shouldDeferHeroImage =
          !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

      // Determine height
      // For full screen, we want to respect the device height, but in the editor preview (which might be desktop height),
      // we should cap it to a reasonable mobile height to avoid a "slit" look.
      final mediaQueryHeight = MediaQuery.of(context).size.height;
      double height;
      if (isFullScreen) {
        if (isMobile && mediaQueryHeight > 900) {
          // Cap mobile fullscreen height in editor/large screens
          height = 800;
        } else {
          height = mediaQueryHeight;
        }
      } else {
        height = isMobile ? 420 : 520;
      }

      final heroInner = Container(
        decoration: showOverlay
            ? BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withOpacity(overlayOpacity * 0.5),
                    Colors.black.withOpacity(overlayOpacity * 0.8),
                  ],
                ),
              )
            : null,
        child: Align(
          alignment: geometryAlign,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: crossAlign,
              children: [
                Text(
                  (title.isEmpty ? 'Título' : title).toUpperCase(),
                  style: resolvedHeading.copyWith(
                    letterSpacing: 3,
                    fontWeight: FontWeight.w900,
                    fontSize:
                        isMobile ? (headingSize ?? 32) * 0.8 : headingSize,
                  ),
                  textAlign: textAlign,
                ),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  Text(
                    subtitle,
                    style: resolvedSubtitle.copyWith(
                      fontSize: isMobile ? (bodySize ?? 16) : bodySize,
                    ),
                    textAlign: textAlign,
                  ),
                ],
                const SizedBox(height: 40),
                OutlinedButton(
                  onPressed: previewMode
                      ? () {}
                      : () {
                          final route =
                              (primaryAction?.to ?? '/productos').trim();
                          if (onNavigate != null) {
                            onNavigate(route);
                          }
                        },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white, width: 1),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 40, vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(0),
                    ),
                  ),
                  child: Text(
                    ((primaryAction?.label ?? legacyCtaText).trim().isEmpty
                            ? 'CHECK IT OUT'
                            : (primaryAction?.label ?? legacyCtaText))
                        .toUpperCase(),
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      if (!shouldDeferHeroImage || imageUrl == null) {
        return Container(
          height: height,
          width: double.infinity,
          decoration: decoration,
          child: heroInner,
        );
      }

      // Android first-frame optimization: build the hero WITHOUT the background image
      // for the first frame, then rebuild with the image.
      return _DeferredFirstFrame(
        builder: (showHeavy) {
          final deferredDecoration = _resolveBackgroundDecoration(
            data: data,
            defaultColor: defaultBgColor,
            imageUrl: imageUrl?.toString(),
            imageAlignmentParam: bgAlignment,
            skipImage: !showHeavy,
          );

          return Container(
            height: height,
            width: double.infinity,
            decoration: deferredDecoration,
            child: heroInner,
          );
        },
      );
    });
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
  }) {
    // Use block ID as stable key to prevent rebuilds on every page mount
    // Falls back to a constant key if no ID is available
    final blockId = data['id']?.toString() ?? 'carousel_default';

    return _CarouselBanner(
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
    );
  }

  static Widget _buildProducts({
    required BuildContext context,
    required Map<String, dynamic> data,
    required Color primaryColor,
    required Color accentColor,
    List<Product>? featuredProducts,
    bool previewMode = false,
    String? bodyFont,
    void Function(String route)? onNavigate,
    String? tenantId,
  }) {
    // Delegate to stateful widget that can fetch its own products
    return _ProductsBlockWidget(
      data: data,
      primaryColor: primaryColor,
      accentColor: accentColor,
      featuredProducts: featuredProducts,
      previewMode: previewMode,
      bodyFont: bodyFont,
      onNavigate: onNavigate,
      tenantId: tenantId,
    );
  }

  static Widget _buildServices({
    required BuildContext context,
    required Map<String, dynamic> data,
    required Color primaryColor,
    bool previewMode = false,
    String? headingFont,
    String? bodyFont,
  }) {
    final rawTitle = (data['title'] ?? 'Nuestros Servicios').toString().trim();
    final title =
        rawTitle.isEmpty ? 'NUESTROS SERVICIOS' : rawTitle.toUpperCase();
    final rawServices = data['services'];

    List<Map<String, dynamic>> services = [];
    if (rawServices is List) {
      services = rawServices
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
    }

    if (services.isEmpty) {
      services = [
        {
          'title': 'Servicio Técnico',
          'description': 'Mantención y reparación profesional',
          'icon': 'build',
        },
        {
          'title': 'Envíos a Todo Chile',
          'description': 'Despacho rápido y seguro',
          'icon': 'local_shipping',
        },
        {
          'title': 'Productos Originales',
          'description': 'Garantía de autenticidad',
          'icon': 'verified',
        },
      ];
    }

    // Use LayoutBuilder to fill available height and center content
    return LayoutBuilder(
      builder: (context, constraints) {
        final hasFixedHeight = constraints.maxHeight.isFinite;
        final bgColor = _parseColor(data['style']?['backgroundColor']) ??
            const Color(0xFFFAFAFA);
        final isMobile = constraints.maxWidth < 600;

        final padding = hasFixedHeight
            ? EdgeInsets.only(
                left: (data['style']?['paddingLeft'] as num?)?.toDouble() ??
                    (isMobile ? 16 : 24),
                right: (data['style']?['paddingRight'] as num?)?.toDouble() ??
                    (isMobile ? 16 : 24),
              )
            : _parsePadding(
                data,
                defaultVertical: 56,
                screenWidth: constraints.maxWidth,
              );

        return Container(
          color: bgColor,
          width: double.infinity,
          height: hasFixedHeight ? constraints.maxHeight : null,
          padding: padding,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1000),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 2,
                      color: Colors.black87,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 40),
                  if (isMobile)
                    Column(
                      children: services.take(3).map((service) {
                        final index = services.indexOf(service);
                        final iconName = service['icon']?.toString();
                        final serviceTitle =
                            (service['title'] ?? 'Servicio').toString();
                        final description =
                            (service['description'] ?? '').toString().trim();

                        return Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 24),
                          decoration: BoxDecoration(
                            border: Border(
                              bottom: index < services.take(3).length - 1
                                  ? BorderSide(
                                      color: Colors.grey.shade300, width: 1)
                                  : BorderSide.none,
                            ),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                _getIconFromString(iconName),
                                size: 32,
                                color: primaryColor,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                serviceTitle,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.black87,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              if (description.isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Text(
                                  description,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Colors.grey.shade600,
                                    height: 1.4,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ],
                          ),
                        );
                      }).toList(),
                    )
                  else
                    Row(
                      children: services.take(3).map((service) {
                        final iconName = service['icon']?.toString();
                        final serviceTitle =
                            (service['title'] ?? 'Servicio').toString();
                        final description =
                            (service['description'] ?? '').toString().trim();

                        return Expanded(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 20, vertical: 24),
                            decoration: BoxDecoration(
                              border: Border(
                                left: services.indexOf(service) > 0
                                    ? BorderSide(
                                        color: Colors.grey.shade300, width: 1)
                                    : BorderSide.none,
                              ),
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  _getIconFromString(iconName),
                                  size: 32,
                                  color: primaryColor,
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  serviceTitle,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.black87,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                                if (description.isNotEmpty) ...[
                                  const SizedBox(height: 6),
                                  Text(
                                    description,
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: Colors.grey.shade600,
                                      height: 1.4,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  static Widget _buildAbout({
    required BuildContext context,
    required Map<String, dynamic> data,
    String? headingFont,
    String? bodyFont,
  }) {
    final theme = Theme.of(context);
    final title = (data['title'] ?? 'Sobre Nosotros').toString().trim();
    final content = (data['content'] ?? '').toString().trim();

    if (content.isEmpty) {
      return const SizedBox.shrink();
    }

    final screenWidth = MediaQuery.of(context).size.width;
    final padding = _parsePadding(
      data,
      defaultVertical: 64,
      screenWidth: screenWidth,
    );

    return Container(
      padding: padding,
      child: Column(
        children: [
          Text(
            title.isEmpty ? 'Sobre Nosotros' : title,
            style: theme.textTheme.displaySmall?.copyWith(
              fontFamily: headingFont,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          Text(
            content,
            style: theme.textTheme.bodyLarge?.copyWith(
              fontFamily: bodyFont,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  static Widget _buildCta({
    required BuildContext context,
    required Map<String, dynamic> data,
    required Color primaryColor,
    required Color accentColor,
    bool previewMode = false,
    String? headingFont,
    String? bodyFont,
    void Function(String route)? onNavigate,
  }) {
    final title = (data['title'] ?? 'Visita nuestra tienda').toString().trim();
    final subtitle =
        (data['subtitle'] ?? data['description'] ?? '').toString().trim();
    final legacyButtonText =
        (data['buttonText'] ?? data['ctaText'] ?? 'Ver productos')
            .toString()
            .trim();
    final legacyButtonLink =
        (data['buttonLink'] ?? data['ctaLink'] ?? '/tienda/contacto')
            .toString()
            .trim();

    final primaryAction = _resolvePrimaryNavigateAction(
      data,
      fallbackLabel: legacyButtonText,
      fallbackTo: legacyButtonLink,
    );

    final backgroundImage =
        (data['backgroundImage'] ?? data['imageUrl'])?.toString().trim();
    final hasBackground =
        backgroundImage != null && backgroundImage.trim().isNotEmpty;

    final overlayColor =
        _parseColor(data['overlayColor']?.toString()) ?? Colors.black;
    final overlayOpacity =
        ((data['overlayOpacity'] ?? 0.5) as num).toDouble().clamp(0.0, 1.0);

    final blockHeight = (data['blockHeight'] as num?)?.toDouble();

    final decoration = _resolveBackgroundDecoration(
      data: data,
      defaultColor: primaryColor,
      imageUrl: backgroundImage,
    );

    final titleStyle = const TextStyle(
      fontSize: 24,
      fontWeight: FontWeight.w700,
      color: Colors.white,
      letterSpacing: 1,
    ).copyWith(
      fontFamily: headingFont?.isNotEmpty == true ? headingFont : null,
    );

    final subtitleStyle =
        (Theme.of(context).textTheme.bodyLarge ?? const TextStyle(fontSize: 16))
            .copyWith(
      fontFamily: bodyFont?.isNotEmpty == true ? bodyFont : null,
      color: Colors.white70,
    );

    return Container(
      height: blockHeight,
      width: double.infinity,
      decoration: decoration,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (hasBackground && overlayOpacity > 0)
            Container(
              color: overlayColor.withValues(alpha: overlayOpacity),
            ),
          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: 24,
              vertical: blockHeight == null ? 56 : 0,
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    (title.isEmpty ? '¿Necesitas ayuda?' : title).toUpperCase(),
                    style: titleStyle,
                    textAlign: TextAlign.center,
                  ),
                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      subtitle,
                      style: subtitleStyle,
                      textAlign: TextAlign.center,
                    ),
                  ],
                  const SizedBox(height: 24),
                  OutlinedButton(
                    onPressed: previewMode
                        ? () {}
                        : () {
                            final route =
                                primaryAction?.to ?? '/tienda/contacto';
                            if (onNavigate != null) {
                              onNavigate(route);
                            }
                          },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white, width: 1),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 32,
                        vertical: 14,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(0),
                      ),
                    ),
                    child: Text(
                      ((primaryAction?.label ?? legacyButtonText).isEmpty
                              ? 'Contáctanos'
                              : (primaryAction?.label ?? legacyButtonText))
                          .toUpperCase(),
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  static Widget _buildFeatures({
    required BuildContext context,
    required Map<String, dynamic> data,
    required Color primaryColor,
    String? headingFont,
    String? bodyFont,
  }) {
    final theme = Theme.of(context);
    final title = (data['title'] ?? '¿Por qué elegirnos?').toString();
    final featuresRaw = data['features'];
    final features = (featuresRaw is List)
        ? featuresRaw
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList()
        : <Map<String, dynamic>>[];

    final layout = data['layout']?.toString() ?? 'grid'; // grid or list
    final bgColor = _parseColor(
        data['style']?['backgroundColor']); // Default transparent/theme
    final screenWidth = MediaQuery.of(context).size.width;
    final padding = _parsePadding(
      data,
      defaultVertical: 64,
      screenWidth: screenWidth,
    );

    return Container(
      padding: padding,
      color: bgColor,
      child: Column(
        children: [
          Text(
            title.isEmpty ? 'Características' : title,
            style: theme.textTheme.displaySmall?.copyWith(
              fontFamily: headingFont,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 48),
          if (features.isEmpty)
            _buildDefaultFeatures(context, primaryColor, headingFont, bodyFont)
          else if (layout == 'list')
            Column(
              children: features.map((item) {
                final rawIcon = item['icon']?.toString();
                final icon = _getIconFromString(rawIcon);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 32),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: primaryColor.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(icon, size: 28, color: primaryColor),
                      ),
                      const SizedBox(width: 20),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item['title']?.toString() ?? 'Título',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                fontFamily: headingFont,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              item['description']?.toString() ?? 'Descripción',
                              style: TextStyle(
                                fontSize: 15,
                                color: Colors.grey.shade600,
                                height: 1.5,
                                fontFamily: bodyFont,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            )
          else
            Wrap(
              spacing: 24,
              runSpacing: 24,
              alignment: WrapAlignment.center,
              children: features.map((item) {
                final rawIcon = item['icon']?.toString();
                final icon = _getIconFromString(rawIcon);
                return _buildFeatureCard(
                  context,
                  icon: icon,
                  title: item['title']?.toString() ?? 'Título',
                  description: item['description']?.toString() ?? 'Descripción',
                  primaryColor: primaryColor,
                  headingFont: headingFont,
                  bodyFont: bodyFont,
                );
              }).toList(),
            ),
        ],
      ),
    );
  }

  static Widget _buildDefaultFeatures(BuildContext context, Color primaryColor,
      String? headingFont, String? bodyFont) {
    return Wrap(
      spacing: 24,
      runSpacing: 24,
      alignment: WrapAlignment.center,
      children: [
        _buildFeatureCard(
          context,
          icon: Icons.verified,
          title: 'Servicio certificado',
          description: 'Técnicos con amplia experiencia en bicicletas.',
          primaryColor: primaryColor,
          headingFont: headingFont,
          bodyFont: bodyFont,
        ),
        _buildFeatureCard(
          context,
          icon: Icons.pedal_bike,
          title: 'Variedad de productos',
          description: 'Catálogo actualizado con las mejores marcas.',
          primaryColor: primaryColor,
          headingFont: headingFont,
          bodyFont: bodyFont,
        ),
        _buildFeatureCard(
          context,
          icon: Icons.support_agent,
          title: 'Acompañamiento experto',
          description: 'Te ayudamos a elegir la bicicleta perfecta.',
          primaryColor: primaryColor,
          headingFont: headingFont,
          bodyFont: bodyFont,
        ),
      ],
    );
  }

  static Widget _buildTestimonials({
    required BuildContext context,
    required Map<String, dynamic> data,
    required Color primaryColor,
    String? headingFont,
    String? bodyFont,
    bool previewMode = false,
  }) {
    final theme = Theme.of(context);
    final rawTitle = (data['title'] ?? 'Testimonios').toString().trim();
    final title = rawTitle.isEmpty ? 'Testimonios' : rawTitle;
    final rawTestimonials = data['testimonials'];

    var testimonials = <Map<String, dynamic>>[];
    if (rawTestimonials is List) {
      testimonials = rawTestimonials
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
    }

    if (testimonials.isEmpty && previewMode) {
      testimonials = [
        {
          'name': 'Carolina M.',
          'role': 'Ciclista urbana',
          'comment':
              '“Me ayudaron a dejar mi bicicleta como nueva y fueron súper rápidos.”',
          'rating': 5,
        },
        {
          'name': 'Luis P.',
          'role': 'Mountain biker',
          'comment':
              '“Excelente servicio y atención. Siempre tienen repuestos de calidad.”',
          'rating': 5,
        },
        {
          'name': 'Paula G.',
          'role': 'Cicloturista',
          'comment':
              '“El equipo es muy dedicado y se nota la pasión por el ciclismo.”',
          'rating': 4,
        },
      ];
    }

    if (testimonials.isEmpty) {
      return const SizedBox.shrink();
    }

    final screenWidth = MediaQuery.of(context).size.width;
    final isCompact = screenWidth < 380;
    final padding = _parsePadding(
      data,
      defaultVertical: 64,
      screenWidth: screenWidth,
    );

    return Container(
      padding: padding,
      color: theme.colorScheme.surfaceVariant.withOpacity(0.25),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                title,
                style: theme.textTheme.displaySmall?.copyWith(
                  fontFamily: headingFont,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 40),
              Wrap(
                spacing: 24,
                runSpacing: 24,
                alignment: WrapAlignment.center,
                children: testimonials
                    .map(
                      (item) => SizedBox(
                        width: isCompact ? double.infinity : 320,
                        child: _buildTestimonialCard(
                          context: context,
                          testimonial: item,
                          primaryColor: primaryColor,
                          bodyFont: bodyFont,
                        ),
                      ),
                    )
                    .toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Widget _buildPricing({
    required BuildContext context,
    required Map<String, dynamic> data,
    required Color primaryColor,
    required Color accentColor,
    String? headingFont,
    String? bodyFont,
    bool previewMode = false,
    void Function(String route)? onNavigate,
  }) {
    final theme = Theme.of(context);
    final rawTitle = (data['title'] ?? 'Planes y Precios').toString().trim();
    final title = rawTitle.isEmpty ? 'Planes y Precios' : rawTitle;
    final subtitle = (data['subtitle'] ?? '').toString().trim();
    final rawPlans = data['plans'];

    var plans = <Map<String, dynamic>>[];
    if (rawPlans is List) {
      plans = rawPlans
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
    }

    if (plans.isEmpty && previewMode) {
      plans = [
        {
          'name': 'Mantención Básica',
          'price': '29.990',
          'features': [
            'Revisión de frenos',
            'Ajuste de cambios',
            'Limpieza básica',
          ],
          'ctaText': 'Reservar',
          'ctaLink': '/productos',
        },
        {
          'name': 'Full Service',
          'price': '59.990',
          'features': [
            'Incluye plan básico',
            'Lubricación completa',
            'Ajuste integral',
          ],
          'ctaText': 'Agendar',
          'ctaLink': '/productos',
          'highlighted': true,
        },
        {
          'name': 'Elite Racing',
          'price': '89.990',
          'features': [
            'Servicio avanzado de suspensión',
            'Lavado premium',
            'Entrega prioritaria',
          ],
          'ctaText': 'Contactar',
          'ctaLink': '/productos',
        },
      ];
    }

    if (plans.isEmpty) {
      return const SizedBox.shrink();
    }

    final screenWidth = MediaQuery.of(context).size.width;
    final isCompact = screenWidth < 380;

    return Container(
      padding: _parsePadding(
        data,
        screenWidth: screenWidth,
        defaultVertical: 64,
        defaultHorizontal: 24,
      ),
      color: theme.colorScheme.surfaceVariant.withOpacity(0.15),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                title,
                style: theme.textTheme.displaySmall?.copyWith(
                  fontFamily: headingFont,
                ),
                textAlign: TextAlign.center,
              ),
              if (subtitle.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  subtitle,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontFamily: bodyFont,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
              const SizedBox(height: 40),
              Wrap(
                spacing: 24,
                runSpacing: 24,
                alignment: WrapAlignment.center,
                children: plans
                    .map(
                      (plan) => SizedBox(
                        width: isCompact ? double.infinity : 320,
                        child: _buildPricingPlanCard(
                          context: context,
                          plan: plan,
                          primaryColor: primaryColor,
                          accentColor: accentColor,
                          bodyFont: bodyFont,
                          previewMode: previewMode,
                          onNavigate: onNavigate,
                        ),
                      ),
                    )
                    .toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Widget _buildTestimonialCard({
    required BuildContext context,
    required Map<String, dynamic> testimonial,
    required Color primaryColor,
    String? bodyFont,
  }) {
    final theme = Theme.of(context);
    final name = (testimonial['name'] ?? 'Cliente').toString().trim();
    final role = (testimonial['role'] ?? '').toString().trim();
    final comment = (testimonial['comment'] ?? '').toString().trim();
    final ratingRaw = testimonial['rating'];

    int rating = 5;
    if (ratingRaw is num) {
      rating = ratingRaw.clamp(1, 5).round();
    } else if (ratingRaw is String) {
      final parsed = int.tryParse(ratingRaw);
      if (parsed != null) {
        rating = parsed.clamp(1, 5);
      }
    }

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.format_quote,
              color: primaryColor,
              size: 32,
            ),
            const SizedBox(height: 16),
            Text(
              comment.isEmpty
                  ? 'Agrega testimonios reales desde el editor.'
                  : comment,
              style: theme.textTheme.bodyLarge?.copyWith(
                fontFamily: bodyFont,
                fontStyle: FontStyle.italic,
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                ...List.generate(5, (index) {
                  final filled = index < rating;
                  return Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Icon(
                      filled ? Icons.star : Icons.star_border,
                      color: filled
                          ? primaryColor
                          : theme.colorScheme.onSurfaceVariant,
                      size: 18,
                    ),
                  );
                }),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              name.isEmpty ? 'Cliente' : name,
              style: theme.textTheme.titleMedium?.copyWith(
                fontFamily: bodyFont,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (role.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                role,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontFamily: bodyFont,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static Widget _buildPricingPlanCard({
    required BuildContext context,
    required Map<String, dynamic> plan,
    required Color primaryColor,
    required Color accentColor,
    String? bodyFont,
    bool previewMode = false,
    void Function(String route)? onNavigate,
  }) {
    final theme = Theme.of(context);
    final name = (plan['name'] ?? 'Plan').toString().trim();
    final priceRaw = (plan['price'] ?? '0').toString().trim();
    final featuresRaw = plan['features'];
    final ctaText = (plan['ctaText'] ?? 'Seleccionar').toString().trim();
    final ctaLink = (plan['ctaLink'] ?? '').toString().trim();
    final isHighlighted =
        plan['highlighted'] == true || plan['isFeatured'] == true;

    final features = <String>[];
    if (featuresRaw is List) {
      features
        ..clear()
        ..addAll(featuresRaw
            .where((item) => item != null)
            .map((item) => item.toString())
            .where((item) => item.isNotEmpty));
    }

    final hasCurrency = RegExp(r'[A-Za-z\$]').hasMatch(priceRaw);
    final priceLabel = priceRaw.isEmpty
        ? 'CLP 0'
        : hasCurrency
            ? priceRaw
            : 'CLP $priceRaw';

    final cardColor = isHighlighted
        ? accentColor.withOpacity(0.12)
        : theme.colorScheme.surface;
    final borderColor = isHighlighted ? accentColor : theme.dividerColor;

    return Card(
      color: cardColor,
      elevation: isHighlighted ? 4 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: borderColor, width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (isHighlighted) ...[
              Align(
                alignment: Alignment.centerRight,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: accentColor,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    'Más popular',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
            Text(
              name.isEmpty ? 'Plan' : name,
              style: theme.textTheme.titleLarge?.copyWith(
                fontFamily: bodyFont,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              priceLabel,
              style: theme.textTheme.headlineMedium?.copyWith(
                fontFamily: bodyFont,
                color: primaryColor,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 24),
            if (features.isEmpty)
              Text(
                'Agrega beneficios desde el editor.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontFamily: bodyFont,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              )
            else
              ...features.map(
                (feature) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.check_circle, color: primaryColor, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          feature,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontFamily: bodyFont,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: previewMode || ctaLink.isEmpty
                  ? null
                  : () => onNavigate?.call(ctaLink),
              style: ElevatedButton.styleFrom(
                backgroundColor: isHighlighted ? accentColor : primaryColor,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(48),
              ),
              child: Text(ctaText.isEmpty ? 'Seleccionar' : ctaText),
            ),
          ],
        ),
      ),
    );
  }

  static Widget _buildGallery({
    required BuildContext context,
    required Map<String, dynamic> data,
    required Color primaryColor,
    bool previewMode = false,
    String? headingFont,
    String? bodyFont,
  }) {
    final theme = Theme.of(context);
    final title = (data['title'] ?? 'Galería').toString().trim();
    final layout = (data['layout'] ?? 'grid').toString();
    final rawImages = data['images'];

    var images = <Map<String, dynamic>>[];
    if (rawImages is List) {
      images = rawImages
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
    }

    if (images.isEmpty) {
      images = [
        {
          'imageUrl':
              'https://images.unsplash.com/photo-1500530855697-b586d89ba3ee?auto=format&fit=crop&w=900&q=60',
          'caption': 'Agrega fotos reales desde el editor.',
        },
        {
          'imageUrl':
              'https://images.unsplash.com/photo-1517841905240-472988babdf9?auto=format&fit=crop&w=900&q=60',
          'caption': 'Esta es una imagen de ejemplo.',
        },
        {
          'imageUrl':
              'https://images.unsplash.com/photo-1489515217757-5fd1be406fef?auto=format&fit=crop&w=900&q=60',
          'caption': 'Sustituye las imágenes para personalizar tu galería.',
        },
      ];
    }

    final useMasonry = layout == 'masonry';
    final screenWidth = MediaQuery.of(context).size.width;

    return Container(
      padding: _parsePadding(
        data,
        screenWidth: screenWidth,
        defaultVertical: 64,
        defaultHorizontal: 24,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                title.isEmpty ? 'Galería' : title,
                style: theme.textTheme.displaySmall?.copyWith(
                  fontFamily: headingFont,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 36),
              LayoutBuilder(
                builder: (context, constraints) {
                  final columns = constraints.maxWidth >= 900
                      ? 3
                      : constraints.maxWidth >= 600
                          ? 2
                          : 1;
                  final itemWidth =
                      (constraints.maxWidth - (16 * (columns - 1))) / columns;

                  return Wrap(
                    spacing: 16,
                    runSpacing: 16,
                    children: images.asMap().entries.map((entry) {
                      final index = entry.key;
                      final image = entry.value;
                      final imageUrl =
                          (image['imageUrl'] ?? '').toString().trim();
                      final caption =
                          (image['caption'] ?? '').toString().trim();
                      final aspectRatio = useMasonry
                          ? (index % 3 == 0
                              ? 1.2
                              : index % 3 == 1
                                  ? 0.8
                                  : 1.0)
                          : 1.0;

                      return SizedBox(
                        width: itemWidth,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            AspectRatio(
                              aspectRatio: aspectRatio,
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(20),
                                child: Container(
                                  color: theme.colorScheme.surfaceVariant,
                                  child: imageUrl.isEmpty
                                      ? Center(
                                          child: Icon(
                                            Icons.image_outlined,
                                            color: theme
                                                .colorScheme.onSurfaceVariant,
                                          ),
                                        )
                                      : Image.network(
                                          imageUrl,
                                          fit: BoxFit.cover,
                                          errorBuilder:
                                              (context, error, stackTrace) {
                                            return Center(
                                              child: Icon(
                                                Icons.broken_image,
                                                color: theme.colorScheme.error,
                                              ),
                                            );
                                          },
                                        ),
                                ),
                              ),
                            ),
                            if (caption.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Text(
                                caption,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontFamily: bodyFont,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ],
                        ),
                      );
                    }).toList(),
                  );
                },
              ),
              if (!previewMode)
                Padding(
                  padding: const EdgeInsets.only(top: 24),
                  child: Text(
                    'Optimiza tus imágenes antes de subirlas para mejorar el rendimiento.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  static Widget _buildFaq({
    required BuildContext context,
    required Map<String, dynamic> data,
    required Color primaryColor,
    String? headingFont,
    String? bodyFont,
  }) {
    final theme = Theme.of(context);
    final title = (data['title'] ?? 'Preguntas frecuentes').toString().trim();
    final subtitle = (data['subtitle'] ?? '').toString().trim();
    final rawItems = data['items'];

    var items = <Map<String, dynamic>>[];
    if (rawItems is List) {
      items = rawItems
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
    }

    if (items.isEmpty) {
      items = [
        {
          'question': '¿Cómo agendo una mantención?',
          'answer':
              'Puedes agendar directamente desde el botón “Reservar” del sitio o escribirnos por WhatsApp.',
        },
        {
          'question': '¿Trabajan con bicicletas eléctricas?',
          'answer':
              'Sí, contamos con técnicos certificados y repuestos para e-bikes.',
        },
      ];
    }

    final screenWidth = MediaQuery.of(context).size.width;

    return Container(
      padding: _parsePadding(
        data,
        screenWidth: screenWidth,
        defaultVertical: 64,
        defaultHorizontal: 24,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                title.isEmpty ? 'Preguntas frecuentes' : title,
                style: theme.textTheme.displaySmall?.copyWith(
                  fontFamily: headingFont,
                ),
                textAlign: TextAlign.center,
              ),
              if (subtitle.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  subtitle,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontFamily: bodyFont,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
              const SizedBox(height: 32),
              ...items.map(
                (item) => Card(
                  margin: const EdgeInsets.only(bottom: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Theme(
                    data: theme.copyWith(
                      dividerColor: Colors.transparent,
                    ),
                    child: ExpansionTile(
                      iconColor: primaryColor,
                      collapsedIconColor: primaryColor,
                      title: Text(
                        (item['question'] ?? 'Pregunta').toString(),
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontFamily: headingFont,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      childrenPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      children: [
                        Text(
                          (item['answer'] ?? 'Agrega una respuesta clara.')
                              .toString(),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontFamily: bodyFont,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Widget _buildStats({
    required BuildContext context,
    required Map<String, dynamic> data,
    required Color primaryColor,
    required Color accentColor,
    String? headingFont,
    String? bodyFont,
  }) {
    final theme = Theme.of(context);
    final title = (data['title'] ?? 'Resultados').toString().trim();
    final rawMetrics = data['metrics'];

    var metrics = <Map<String, dynamic>>[];
    if (rawMetrics is List) {
      metrics = rawMetrics
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
    }

    if (metrics.isEmpty) {
      metrics = [
        {
          'label': 'Bicis reparadas',
          'value': '1200',
          'suffix': '+',
        },
        {
          'label': 'Clientes felices',
          'value': '980',
          'suffix': '+',
        },
        {
          'label': 'Años de experiencia',
          'value': '10',
        },
      ];
    }

    final screenWidth = MediaQuery.of(context).size.width;

    return Container(
      padding: _parsePadding(
        data,
        screenWidth: screenWidth,
        defaultVertical: 64,
        defaultHorizontal: 24,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1000),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                title.isEmpty ? 'Indicadores' : title,
                style: theme.textTheme.displaySmall?.copyWith(
                  fontFamily: headingFont,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 40),
              Wrap(
                spacing: 24,
                runSpacing: 24,
                alignment: WrapAlignment.center,
                children: metrics.map((metric) {
                  final label = (metric['label'] ?? 'Indicador').toString();
                  final value = (metric['value'] ?? '0').toString();
                  final suffix = (metric['suffix'] ?? '').toString();
                  return Container(
                    width: 220,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 32),
                    decoration: BoxDecoration(
                      color: accentColor.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: primaryColor.withOpacity(0.2)),
                    ),
                    child: Column(
                      children: [
                        Text(
                          '$value$suffix',
                          style: theme.textTheme.displaySmall?.copyWith(
                            fontFamily: headingFont,
                            color: primaryColor,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          label,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            fontFamily: bodyFont,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Widget _buildContact({
    required BuildContext context,
    required Map<String, dynamic> data,
    required Color primaryColor,
    required Color accentColor,
    String? headingFont,
    String? bodyFont,
    bool previewMode = false,
    void Function(String route)? onNavigate,
  }) {
    final theme = Theme.of(context);
    final title = (data['title'] ?? 'Contáctanos').toString().trim();
    final subtitle = (data['subtitle'] ?? '').toString().trim();
    final phone = (data['phone'] ?? '').toString().trim();
    final email = (data['email'] ?? '').toString().trim();
    final address = (data['address'] ?? '').toString().trim();
    final mapUrl = (data['mapUrl'] ?? '').toString().trim();
    final showForm = data['showForm'] != false;
    final showMap = data['showMap'] == true;

    final contactItems = <Widget>[];
    if (phone.isNotEmpty) {
      contactItems.add(
        _buildContactDetail(
          icon: Icons.phone,
          label: 'Teléfono',
          value: phone,
          theme: theme,
          bodyFont: bodyFont,
        ),
      );
    }
    if (email.isNotEmpty) {
      contactItems.add(
        _buildContactDetail(
          icon: Icons.email_outlined,
          label: 'Correo',
          value: email,
          theme: theme,
          bodyFont: bodyFont,
        ),
      );
    }
    if (address.isNotEmpty) {
      contactItems.add(
        _buildContactDetail(
          icon: Icons.location_on_outlined,
          label: 'Dirección',
          value: address,
          theme: theme,
          bodyFont: bodyFont,
        ),
      );
    }

    final screenWidth = MediaQuery.of(context).size.width;
    final isCompact = screenWidth < 400;

    return Container(
      padding: _parsePadding(
        data,
        screenWidth: screenWidth,
        defaultVertical: 64,
        defaultHorizontal: 24,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                title.isEmpty ? 'Contáctanos' : title,
                style: theme.textTheme.displaySmall?.copyWith(
                  fontFamily: headingFont,
                ),
                textAlign: TextAlign.center,
              ),
              if (subtitle.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  subtitle,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontFamily: bodyFont,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
              const SizedBox(height: 36),
              Wrap(
                spacing: 24,
                runSpacing: 24,
                alignment: WrapAlignment.center,
                children: [
                  SizedBox(
                    width: isCompact ? double.infinity : 320,
                    child: Card(
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Información de contacto',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontFamily: headingFont,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 16),
                            if (contactItems.isEmpty)
                              Text(
                                'Completa tus datos de contacto desde el editor.',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              )
                            else
                              ...contactItems,
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (showForm)
                    SizedBox(
                      width: isCompact ? double.infinity : 360,
                      child: Card(
                        elevation: 2,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                'Envíanos un mensaje',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontFamily: headingFont,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 16),
                              _buildDisabledTextField(theme, 'Nombre'),
                              const SizedBox(height: 12),
                              _buildDisabledTextField(
                                  theme, 'Correo electrónico'),
                              const SizedBox(height: 12),
                              _buildDisabledTextField(theme, 'Mensaje',
                                  maxLines: 4),
                              const SizedBox(height: 20),
                              ElevatedButton(
                                onPressed: previewMode ? () {} : null,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: primaryColor,
                                  foregroundColor: Colors.white,
                                ),
                                child: const Text('Enviar consulta'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  if (showMap)
                    SizedBox(
                      width: isCompact ? double.infinity : 360,
                      child: Card(
                        elevation: 2,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                'Cómo llegar',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontFamily: headingFont,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 16),
                              Container(
                                height: 200,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(16),
                                  color: theme.colorScheme.surfaceVariant,
                                ),
                                child: Center(
                                  child: Icon(
                                    Icons.map_outlined,
                                    size: 64,
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                              if (mapUrl.isNotEmpty) ...[
                                const SizedBox(height: 16),
                                TextButton.icon(
                                  onPressed: previewMode
                                      ? () {}
                                      : (mapUrl.startsWith('/')
                                          ? () => onNavigate?.call(mapUrl)
                                          : null),
                                  icon: const Icon(Icons.arrow_outward),
                                  label: const Text('Abrir mapa'),
                                  style: TextButton.styleFrom(
                                    foregroundColor: accentColor,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Widget _buildContactDetail({
    required IconData icon,
    required String label,
    required String value,
    required ThemeData theme,
    String? bodyFont,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: theme.colorScheme.primary, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontFamily: bodyFont,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontFamily: bodyFont,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static Widget _buildDisabledTextField(ThemeData theme, String label,
      {int maxLines = 1}) {
    return TextField(
      enabled: false,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      maxLines: maxLines,
    );
  }

  static Widget _buildTeam({
    required BuildContext context,
    required Map<String, dynamic> data,
    required Color primaryColor,
    required Color accentColor,
    String? headingFont,
    String? bodyFont,
    bool previewMode = false,
  }) {
    final theme = Theme.of(context);
    final title = (data['title'] ?? 'Nuestro equipo').toString().trim();
    final description = (data['description'] ?? '').toString().trim();
    final rawMembers = data['members'];

    var members = <Map<String, dynamic>>[];
    if (rawMembers is List) {
      members = rawMembers
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
    }

    if (members.isEmpty) {
      members = [
        {
          'name': 'Nombre del integrante',
          'role': 'Cargo',
          'bio': 'Usa el editor para agregar información de tu equipo.',
          'avatarUrl': '',
        },
        {
          'name': 'Integrante 2',
          'role': 'Cargo',
          'bio':
              'Cada integrante puede incluir redes sociales y una breve bio.',
          'avatarUrl': '',
        },
      ];
    }

    final screenWidth = MediaQuery.of(context).size.width;
    final isCompact = screenWidth < 350;

    return Container(
      padding: _parsePadding(
        data,
        screenWidth: screenWidth,
        defaultVertical: 64,
        defaultHorizontal: 24,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                title.isEmpty ? 'Nuestro equipo' : title,
                style: theme.textTheme.displaySmall?.copyWith(
                  fontFamily: headingFont,
                ),
                textAlign: TextAlign.center,
              ),
              if (description.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  description,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontFamily: bodyFont,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
              const SizedBox(height: 40),
              Wrap(
                spacing: 24,
                runSpacing: 24,
                alignment: WrapAlignment.center,
                children: members.map((member) {
                  final name = (member['name'] ?? 'Integrante').toString();
                  final role = (member['role'] ?? '').toString();
                  final bio = (member['bio'] ?? '').toString();
                  final avatarUrl =
                      (member['avatarUrl'] ?? '').toString().trim();
                  final instagram =
                      (member['instagram'] ?? '').toString().trim();
                  final linkedin = (member['linkedin'] ?? '').toString().trim();

                  return SizedBox(
                    width: isCompact ? double.infinity : 300,
                    child: Card(
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            CircleAvatar(
                              radius: 48,
                              backgroundColor: accentColor.withOpacity(0.12),
                              backgroundImage: avatarUrl.isNotEmpty
                                  ? NetworkImage(avatarUrl)
                                  : null,
                              child: avatarUrl.isEmpty
                                  ? Icon(
                                      Icons.person,
                                      size: 48,
                                      color: accentColor,
                                    )
                                  : null,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              name,
                              style: theme.textTheme.titleLarge?.copyWith(
                                fontFamily: headingFont,
                                fontWeight: FontWeight.bold,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            if (role.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Text(
                                role,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontFamily: bodyFont,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                            if (bio.isNotEmpty) ...[
                              const SizedBox(height: 12),
                              Text(
                                bio,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontFamily: bodyFont,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                            if (instagram.isNotEmpty || linkedin.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 16),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (instagram.isNotEmpty)
                                      IconButton(
                                        tooltip: 'Instagram',
                                        onPressed: () {},
                                        icon: const Icon(
                                            Icons.camera_alt_outlined),
                                        color: accentColor,
                                      ),
                                    if (linkedin.isNotEmpty)
                                      IconButton(
                                        tooltip: 'LinkedIn',
                                        onPressed: () {},
                                        icon: const Icon(Icons.work_outline),
                                        color: accentColor,
                                      ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Widget _buildFeatureCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String description,
    required Color primaryColor,
    String? headingFont,
    String? bodyFont,
  }) {
    return SizedBox(
      width: 320,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Icon(icon, size: 48, color: primaryColor),
              const SizedBox(height: 16),
              Text(
                title,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontFamily: headingFont,
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                description,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontFamily: bodyFont,
                    ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  static IconData _getIconFromString(String? iconName) {
    switch (iconName) {
      case 'directions_bike':
        return Icons.directions_bike;
      case 'build':
        return Icons.build;
      case 'shopping_bag':
        return Icons.shopping_bag;
      case 'verified':
        return Icons.verified;
      case 'pedal_bike':
        return Icons.pedal_bike;
      case 'support_agent':
        return Icons.support_agent;
      case 'favorite':
        return Icons.favorite;
      case 'star':
        return Icons.star;
      case 'links':
        return Icons.link;
      case 'instagram':
        return Icons.camera_alt_outlined;
      case 'strava':
        return Icons.timeline;
      case 'facebook':
        return Icons.thumb_up_alt_outlined;
      case 'phone':
        return Icons.phone;
      case 'mail':
        return Icons.mail_outline;
      case 'location':
        return Icons.location_on_outlined;
      default:
        return Icons.star;
    }
  }

  // ============================================================================
  // CATEGORY GRID BLOCK
  // Modern grid of category cards with images (like Commencal's MTB/Road/Kids)
  // ============================================================================
  static Widget _buildCategoryGrid({
    required BuildContext context,
    required Map<String, dynamic> data,
    required Color primaryColor,
    required Color accentColor,
    String? headingFont,
    String? bodyFont,
    bool previewMode = false,
    void Function(String route)? onNavigate,
  }) {
    final theme = Theme.of(context);
    final title = (data['title'] ?? '').toString().trim();
    final subtitle = (data['subtitle'] ?? '').toString().trim();

    // Parse categories
    List<Map<String, dynamic>> categories = [];
    final rawCategories = data['categories'];
    if (rawCategories is List) {
      categories = rawCategories
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
    }

    // Default sample categories if empty
    if (categories.isEmpty) {
      categories = [
        {
          'title': 'Mountain Bike',
          'subtitle': 'Conquista cualquier terreno',
          'imageUrl': null,
          'ctaText': 'Ver colección',
          'ctaLink': '/productos',
          'size': 'large', // large, medium, small
        },
        {
          'title': 'Ruta',
          'subtitle': 'Velocidad y rendimiento',
          'imageUrl': null,
          'ctaText': 'Ver colección',
          'ctaLink': '/productos',
          'size': 'large',
        },
        {
          'title': 'Urbano',
          'subtitle': 'Movilidad en la ciudad',
          'imageUrl': null,
          'ctaText': 'Ver gama',
          'ctaLink': '/productos',
          'size': 'medium',
        },
        {
          'title': 'Accesorios',
          'subtitle': 'Todo lo que necesitas',
          'imageUrl': null,
          'ctaText': 'Explorar',
          'ctaLink': '/productos',
          'size': 'medium',
        },
      ];
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
                  fontFamily: headingFont,
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
                    fontFamily: bodyFont,
                    color: Colors.black54,
                  ),
                ),
              ),
            const SizedBox(height: 32),
          ],
          _CategoryGridLayout(
            categories: categories,
            primaryColor: primaryColor,
            accentColor: accentColor,
            bodyFont: bodyFont,
            previewMode: previewMode,
            onNavigate: onNavigate,
          ),
        ],
      ),
    );
  }

  // ============================================================================
  // VIDEO BANNER BLOCK
  // Full-width image/video banner with overlay text
  // ============================================================================
  static Widget _buildVideoBanner({
    required BuildContext context,
    required Map<String, dynamic> data,
    required Color primaryColor,
    required Color accentColor,
    String? headingFont,
    String? bodyFont,
    bool previewMode = false,
    void Function(String route)? onNavigate,
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
    if (rawOpacity is num)
      overlayOpacity = rawOpacity.toDouble().clamp(0.0, 1.0);

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
      ctaLink: primaryAction?.to ?? legacyCtaLink,
      showCta: primaryAction != null,
      overlayOpacity: overlayOpacity,
      accentColor: accentColor,
      headingFont: headingFont,
      bodyFont: bodyFont,
      previewMode: previewMode,
      onNavigate: onNavigate,
      hasPlayableVideo: hasPlayableVideo,
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
    final imageUrl = data['imageUrl']?.toString();

    // Parse items (list of text lines)
    List<String> items = [];
    final rawItems = data['items'];
    if (rawItems is List) {
      items = rawItems.map((e) => e.toString()).toList();
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
    return LayoutBuilder(
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
                    colorFilter: ColorFilter.mode(
                      Colors.black.withOpacity(0.7),
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
                          style: theme.textTheme.labelLarge?.copyWith(
                            fontFamily: bodyFont,
                            color: Colors.white60,
                            letterSpacing: 3,
                          ),
                          textAlign: TextAlign.center,
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
  }) {
    final title = (data['title'] ?? 'MARCAS').toString().trim();

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
    return LayoutBuilder(
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
                  style: TextStyle(
                    fontFamily: headingFont,
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 2,
                    color: Colors.black87,
                  ),
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

class _DeferredFirstFrame extends StatefulWidget {
  const _DeferredFirstFrame({required this.builder});

  final Widget Function(bool showHeavy) builder;

  @override
  State<_DeferredFirstFrame> createState() => _DeferredFirstFrameState();
}

class _DeferredFirstFrameState extends State<_DeferredFirstFrame> {
  bool _showHeavy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _showHeavy = true);
    });
  }

  @override
  Widget build(BuildContext context) => widget.builder(_showHeavy);
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

  const _BrandLogosCarousel({
    required this.brands,
    this.bodyFont,
    this.logoHeight = 90,
    this.gap = 40,
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth;

        // Items per page = total brands (show all on one page, like reference site)
        // Only paginate if we truly can't fit them all
        final minLogoWidth = 100.0; // Minimum width per logo
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

  const _BrandLogoItem({
    required this.brand,
    this.bodyFont,
    this.width = 140,
    this.height = 90,
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
              errorBuilder: (context, error, stackTrace) {
                return _buildPlaceholder(name);
              },
            )
          : _buildPlaceholder(name),
    );

    if (link.isNotEmpty) {
      content = MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () {
            // Could open link in browser
          },
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
    final ctaLink = (data['ctaLink'] ?? '').toString().trim();
    final link = (data['link'] ?? '').toString().trim();
    final href = _resolveCategoryHref(ctaLink: ctaLink, link: link);
    final imageUrl = data['imageUrl']?.toString();
    final hasImage = imageUrl != null && imageUrl.isNotEmpty;

    return RepaintBoundary(
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: const Color(0xFF2a2a2a),
          image: hasImage
              ? DecorationImage(
                  image: NetworkImage(imageUrl),
                  fit: BoxFit.cover,
                  colorFilter: ColorFilter.mode(
                    Colors.black.withOpacity(0.35),
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
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      const Color(0xFF3a3a3a),
                      const Color(0xFF1a1a1a),
                    ],
                  ),
                ),
              ),
            // Material + InkWell for interaction and hover effect
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: previewMode ? null : () => onNavigate?.call(href),
                hoverColor: Colors.black.withOpacity(0.2),
                splashColor: Colors.white.withOpacity(0.1),
                highlightColor: Colors.white.withOpacity(0.05),
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
                              color: Colors.black.withOpacity(0.5),
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
                          border:
                              Border.all(color: Colors.white.withOpacity(0.3)),
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
      ),
    );
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

class _CarouselBanner extends StatefulWidget {
  const _CarouselBanner({
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
  });

  final Map<String, dynamic> data;
  final Color primaryColor;
  final Color accentColor;
  final bool previewMode;
  final String? headingFont;
  final String? bodyFont;
  final double? headingSize;
  final double? bodySize;
  final void Function(String route)? onNavigate;

  @override
  State<_CarouselBanner> createState() => _CarouselBannerState();
}

class _CarouselBannerState extends State<_CarouselBanner> {
  late List<Map<String, dynamic>> _slides;
  int _currentIndex = 0;
  late bool _autoPlay;
  late bool _showIndicators;
  late bool _showArrows;
  late Duration _interval;
  late _CarouselAnimation _animation;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _refreshConfiguration(resetIndex: true);
  }

  @override
  void didUpdateWidget(covariant _CarouselBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    setState(_refreshConfiguration);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _refreshConfiguration({bool resetIndex = false}) {
    _slides = _parseSlides(widget.data);
    if (_slides.isEmpty) {
      _slides = _defaultSlides();
    }

    if (resetIndex || _currentIndex >= _slides.length) {
      _currentIndex = 0;
    }

    _autoPlay = (widget.data['autoPlay'] ?? true) == true;
    _showIndicators = (widget.data['showIndicators'] ?? true) == true;
    _showArrows = (widget.data['showArrows'] ?? true) == true;
    _interval =
        Duration(seconds: _parseInterval(widget.data['intervalSeconds']));
    _animation = _parseAnimation(widget.data['animation']);

    _restartTimer();
  }

  @override
  Widget build(BuildContext context) {
    if (_slides.isEmpty) {
      return const SizedBox.shrink();
    }

    // Use LayoutBuilder to fill available height, default to 520 if unconstrained
    return LayoutBuilder(
      builder: (context, constraints) {
        final height =
            constraints.maxHeight.isFinite ? constraints.maxHeight : 520.0;
        return SizedBox(
          height: height,
          width: double.infinity,
          child: Stack(
            fit: StackFit.expand,
            children: [
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 600),
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
                      return GestureDetector(
                        onTap: () => _goToSlide(index),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 250),
                          margin: const EdgeInsets.symmetric(horizontal: 5),
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: isActive
                                ? Colors.white
                                : Colors.white.withOpacity(0.4),
                            shape: BoxShape.circle,
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
                    child: _buildArrowButton(
                      icon: Icons.chevron_left,
                      onTap: _previousSlide,
                    ),
                  ),
                ),
                Positioned(
                  right: 24,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: _buildArrowButton(
                      icon: Icons.chevron_right,
                      onTap: _nextSlide,
                    ),
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
    final title = (slide['title'] ?? 'Título').toString().trim();
    final subtitle = (slide['subtitle'] ?? '').toString().trim();
    final ctaText = (slide['ctaText'] ?? 'Ver más').toString().trim();
    final ctaLink = (slide['ctaLink'] ?? '/productos').toString().trim();
    final imageUrl = slide['imageUrl'];
    final videoUrl = slide['videoUrl']?.toString() ?? '';
    final videoFileUrl = slide['videoFileUrl']?.toString() ?? '';
    final showOverlay = (slide['showOverlay'] ?? true) == true;

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

    final headingStyle = WebsiteBlockRenderer._applyThemeFont(
      (theme.textTheme.displayLarge ?? const TextStyle()).copyWith(
        fontSize: widget.headingSize,
        color: Colors.white,
      ),
      widget.headingFont,
    );

    final subtitleStyle = WebsiteBlockRenderer._applyThemeFont(
      (theme.textTheme.headlineSmall ?? const TextStyle()).copyWith(
        fontSize: widget.bodySize != null ? widget.bodySize! * 1.2 : null,
        color: Colors.white70,
      ),
      widget.bodyFont,
    );

    final ctaTextStyle = WebsiteBlockRenderer._applyThemeFont(
      const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        letterSpacing: 1.5,
      ),
      widget.bodyFont,
    );

    // Content widget (text, buttons, overlay)
    Widget contentWidget = Container(
      decoration: showOverlay
          ? BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withOpacity(overlayOpacity * 0.4),
                  Colors.black.withOpacity(overlayOpacity * 0.7),
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
                Text(
                  (title.isEmpty ? 'Título' : title).toUpperCase(),
                  style: headingStyle.copyWith(
                    letterSpacing: 3,
                    fontWeight: FontWeight.w900,
                  ),
                  textAlign: TextAlign.center,
                ),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  Text(
                    subtitle,
                    style: subtitleStyle,
                    textAlign: TextAlign.center,
                  ),
                ],
                const SizedBox(height: 40),
                if (ctaText.isNotEmpty)
                  OutlinedButton(
                    onPressed: widget.previewMode
                        ? () {}
                        : () {
                            final route =
                                ctaLink.isNotEmpty ? ctaLink : '/productos';
                            if (widget.onNavigate != null) {
                              widget.onNavigate!(route);
                            }
                          },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white, width: 1),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 40,
                        vertical: 16,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(0),
                      ),
                    ),
                    child: Text(
                      ctaText.toUpperCase(),
                      style: ctaTextStyle,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );

    // If we have video, use Stack with video background
    if (hasVideo && video_platform.VideoBannerPlatform.isSupported) {
      return LayoutBuilder(
        builder: (context, constraints) {
          return Container(
            key: ValueKey<int>(index),
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

    return Container(
      key: ValueKey<int>(index),
      decoration: decoration,
      child: contentWidget,
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

  Widget _buildArrowButton(
      {required IconData icon, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.black45,
          shape: BoxShape.circle,
        ),
        padding: const EdgeInsets.all(8),
        child: Icon(icon, color: Colors.white, size: 28),
      ),
    );
  }

  void _nextSlide() {
    if (!mounted || _slides.length <= 1) return;
    setState(() {
      _currentIndex = (_currentIndex + 1) % _slides.length;
    });
  }

  void _previousSlide() {
    if (!mounted || _slides.length <= 1) return;
    setState(() {
      _currentIndex = (_currentIndex - 1 + _slides.length) % _slides.length;
    });
    _restartTimer();
  }

  void _goToSlide(int index) {
    if (!mounted || index < 0 || index >= _slides.length) return;
    setState(() {
      _currentIndex = index;
    });
    _restartTimer();
  }

  void _restartTimer() {
    _timer?.cancel();
    if (!_autoPlay || _slides.length <= 1) {
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

  List<Map<String, dynamic>> _defaultSlides() {
    return [
      {
        'title': 'Descubre la tienda',
        'subtitle': 'Todo lo que necesitas para tu bicicleta en un solo lugar',
        'ctaText': 'Ver catálogo',
        'ctaLink': '/productos',
        'imageUrl': null,
        'showOverlay': true,
        'overlayOpacity': 0.55,
      },
      {
        'title': 'Servicio técnico certificado',
        'subtitle': 'Agenda tu mantención sin salir de casa',
        'ctaText': 'Agendar ahora',
        'ctaLink': '/tienda/servicios',
        'imageUrl': null,
        'showOverlay': true,
        'overlayOpacity': 0.55,
      },
    ];
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
  final bool previewMode;
  final String? bodyFont;
  final void Function(String route)? onNavigate;
  final String? tenantId;

  const _ProductsBlockWidget({
    required this.data,
    required this.primaryColor,
    required this.accentColor,
    this.featuredProducts,
    this.previewMode = false,
    this.bodyFont,
    this.onNavigate,
    this.tenantId,
  });

  @override
  State<_ProductsBlockWidget> createState() => _ProductsBlockWidgetState();
}

class _ProductsBlockWidgetState extends State<_ProductsBlockWidget> {
  List<Product> _products = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadProducts();
  }

  @override
  void didUpdateWidget(_ProductsBlockWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Reload if source, selected products, OR tenantId changed
    final shouldReload =
        oldWidget.data['productSource'] != widget.data['productSource'] ||
            oldWidget.data['selectedProducts']?.toString() !=
                widget.data['selectedProducts']?.toString() ||
            oldWidget.data['categoryId'] != widget.data['categoryId'] ||
            oldWidget.data['maxProducts'] != widget.data['maxProducts'] ||
            oldWidget.tenantId != widget.tenantId;

    if (shouldReload) {
      _loadProducts();
    }
  }

  String get _productSource =>
      widget.data['productSource']?.toString() ?? 'featured';

  List<String> get _selectedProductIds {
    final raw = widget.data['selectedProducts'];
    if (raw is List) return raw.map((e) => e.toString()).toList();
    return [];
  }

  String? get _categoryId => widget.data['categoryId']?.toString();
  int get _maxProducts => (widget.data['maxProducts'] as num?)?.toInt() ?? 8;

  Future<void> _loadProducts() async {
    if (!mounted) return;

    final tenantId = widget.tenantId;

    // If no tenantId yet, stay in loading state and wait for didUpdateWidget
    if (tenantId == null || tenantId.isEmpty) {
      // Keep _isLoading = true to show loading placeholders
      // Don't set error state - tenant detection may still be in progress
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final supabase = Supabase.instance.client;
      List<Product> products = [];

      // We have tenantId - fetch based on source
      switch (_productSource) {
        case 'manual':
          // Fetch specific products by ID
          if (_selectedProductIds.isNotEmpty) {
            final response = await supabase
                .from('products')
                .select()
                .eq('tenant_id', tenantId)
                .inFilter('id', _selectedProductIds)
                .eq('is_active', true);

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
            final response = await supabase
                .from('products')
                .select()
                .eq('tenant_id', tenantId)
                .eq('category_id', _categoryId!)
                .eq('is_active', true)
                .eq('show_on_website', true)
                .order('name')
                .limit(_maxProducts);

            products = _parseProducts(response);
          }
          break;

        case 'newest':
          // Fetch newest products
          final response = await supabase
              .from('products')
              .select()
              .eq('tenant_id', tenantId)
              .eq('is_active', true)
              .eq('show_on_website', true)
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
                .where((p) => p.isActive)
                .take(_maxProducts)
                .toList();
          } else {
            // Fallback: fetch products marked as show_on_website
            final response = await supabase
                .from('products')
                .select()
                .eq('tenant_id', tenantId)
                .eq('is_active', true)
                .eq('show_on_website', true)
                .order('name')
                .limit(_maxProducts);

            products = _parseProducts(response);
          }
          break;
      }

      // Filter out out-of-stock products unless in preview mode (admin editing)
      if (!widget.previewMode) {
        products = products.where((p) => p.stockQuantity > 0).toList();
      }

      if (mounted) {
        setState(() {
          _products = products.take(_maxProducts).toList();
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('[ProductsBlock] Error: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
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
              productType: ProductType.product,
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
                              name: product.name,
                              price: product.price,
                              imageUrl: product.imageUrl,
                              bodyFont: widget.bodyFont,
                              previewMode: widget.previewMode,
                              onNavigate: widget.onNavigate,
                            );
                          },
                        ),
              if (showViewAll) ...[
                const SizedBox(height: 40),
                Center(
                  child: OutlinedButton(
                    onPressed: widget.previewMode
                        ? () {}
                        : () {
                            if (widget.onNavigate != null) {
                              widget.onNavigate!('/productos');
                            }
                          },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.black,
                      side: const BorderSide(color: Colors.black, width: 1),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 32, vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(0),
                      ),
                    ),
                    child: const Text(
                      'VER TODOS LOS PRODUCTOS',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1,
                      ),
                    ),
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
  final bool showCta;
  final double overlayOpacity;
  final Color accentColor;
  final String? headingFont;
  final String? bodyFont;
  final bool previewMode;
  final void Function(String route)? onNavigate;
  final bool hasPlayableVideo;

  const _VideoBannerWidget({
    required this.title,
    required this.subtitle,
    this.imageUrl,
    this.youtubeVideoId,
    this.videoFileUrl,
    required this.ctaText,
    required this.ctaLink,
    required this.showCta,
    required this.overlayOpacity,
    required this.accentColor,
    this.headingFont,
    this.bodyFont,
    required this.previewMode,
    this.onNavigate,
    required this.hasPlayableVideo,
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
    return LayoutBuilder(
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
                      Colors.black.withOpacity(widget.overlayOpacity * 0.3),
                      Colors.black.withOpacity(widget.overlayOpacity),
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
                          ElevatedButton(
                            onPressed: widget.previewMode
                                ? null
                                : () => widget.onNavigate?.call(widget.ctaLink),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: widget.accentColor,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 32,
                                vertical: 16,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                            child: Text(widget.ctaText),
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
                      color: Colors.white.withOpacity(0.2),
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
    Key? key,
    required this.products,
    this.bodyFont,
    this.previewMode = false,
    this.onNavigate,
  }) : super(key: key);

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
