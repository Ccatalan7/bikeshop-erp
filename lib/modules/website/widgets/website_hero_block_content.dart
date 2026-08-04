import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/website_action.dart';
import 'text_formatting_toolbar.dart';
import 'website_action_button.dart';
import 'website_block_content_presenters.dart';

typedef WebsiteHeroImageProviderBuilder = ImageProvider<Object> Function(
  String url,
);

/// Shared visitor content for the Website Builder Hero block.
///
/// Preview and Public render this tree directly. Edit may inject typed
/// [presenters] around its text, cover-media and action leaves without owning
/// a second layout.
class WebsiteHeroBlockContent extends StatelessWidget {
  const WebsiteHeroBlockContent({
    super.key,
    required this.data,
    required this.primaryColor,
    required this.accentColor,
    this.previewMode = false,
    this.headingFont,
    this.bodyFont,
    this.headingSize,
    this.bodySize,
    this.onNavigate,
    this.isNavigationEligible,
    this.presenters,
    this.imageProviderBuilder,
  });

  static const rootKey = ValueKey<String>('website-hero-content-root');
  static const backgroundKey =
      ValueKey<String>('website-hero-background-media');
  static const overlayKey = ValueKey<String>('website-hero-overlay');
  static const contentKey = ValueKey<String>('website-hero-content');
  static const titleKey = ValueKey<String>('website-hero-title');
  static const subtitleKey = ValueKey<String>('website-hero-subtitle');
  static const actionKey = ValueKey<String>('website-hero-action');

  final Map<String, dynamic> data;

  /// Kept in the campaign-content API alongside [accentColor]. The established
  /// Hero surface itself uses a neutral dark fallback when no media/style is
  /// configured.
  final Color primaryColor;
  final Color accentColor;
  final bool previewMode;
  final String? headingFont;
  final String? bodyFont;
  final double? headingSize;
  final double? bodySize;
  final void Function(String route)? onNavigate;
  final bool Function(String href)? isNavigationEligible;
  final WebsiteBlockContentPresenters? presenters;
  final WebsiteHeroImageProviderBuilder? imageProviderBuilder;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rawTitle = (data['title'] ?? 'Bienvenido').toString();
    final title = rawTitle.trim().isEmpty ? 'Título' : rawTitle.trim();
    final subtitle = (data['subtitle'] ?? '').toString().trim();
    final action = _resolveAction(data);
    final visibleAction = _visibleAction(
      action,
      presenters: presenters,
      isNavigationEligible: isNavigationEligible,
    );
    final imageUrl = _firstNonNullString(
      data,
      const <String>['imageUrl', 'backgroundImage'],
    )?.trim();
    final hasImage = imageUrl != null && imageUrl.isNotEmpty;
    final imageAltText = _firstNonNullString(
          data,
          const <String>[
            'imageAltText',
            'backgroundImageAltText',
            'altText',
          ],
        )?.trim() ??
        '';
    final showOverlay = data['showOverlay'] != false;
    final overlayOpacity =
        (_finiteDouble(data['overlayOpacity']) ?? 0.5).clamp(0.0, 1.0);
    final overlayColor =
        _parseColor(data['overlayColor']) ?? const Color(0xFF000000);
    final isFullScreen = data['isFullScreen'] == true;
    final alignment = data['alignment']?.toString().trim().toLowerCase();
    final titleFormatting = _formatting(data['titleFormatting']);
    final subtitleFormatting = _formatting(data['subtitleFormatting']);

    final resolvedHeading = titleFormatting.applyTo(
      _applyFont(
        (theme.textTheme.displayLarge ?? const TextStyle()).copyWith(
          fontSize: headingSize,
          color: Colors.white,
        ),
        headingFont,
      ),
    );
    final resolvedSubtitle = subtitleFormatting.applyTo(
      _applyFont(
        (theme.textTheme.headlineSmall ?? const TextStyle()).copyWith(
          fontSize: bodySize == null ? null : bodySize! * 1.2,
          color: Colors.white70,
        ),
        bodyFont,
      ),
    );

    final (
      crossAxisAlignment,
      fallbackTextAlign,
      geometryAlignment,
    ) = switch (alignment) {
      'left' => (
          CrossAxisAlignment.start,
          TextAlign.left,
          Alignment.centerLeft,
        ),
      'right' => (
          CrossAxisAlignment.end,
          TextAlign.right,
          Alignment.centerRight,
        ),
      _ => (
          CrossAxisAlignment.center,
          TextAlign.center,
          Alignment.center,
        ),
    };

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        final isMobile = availableWidth < 600;
        final backgroundAlignment = _resolveFocalAlignment(
          data,
          useMobile: isMobile,
        );
        final viewportHeight = MediaQuery.sizeOf(context).height;
        final configuredHeight = _positiveFiniteDouble(data['blockHeight']);
        final height = configuredHeight ??
            (isFullScreen
                ? isMobile && viewportHeight > 900
                    ? 800.0
                    : viewportHeight
                : isMobile
                    ? 420.0
                    : 520.0);

        final titleSlot = WebsiteInlineTextSlot(
          id: 'hero.title',
          value: rawTitle,
          valueKeys: const <String>['title'],
          baseStyle: resolvedHeading.copyWith(
            letterSpacing: 3,
            fontWeight: FontWeight.w900,
            fontSize: isMobile ? (headingSize ?? 32) * 0.8 : headingSize,
          ),
          formatting: titleFormatting,
          formattingKeys: const <String>['titleFormatting'],
          textAlign: fallbackTextAlign,
          placeholder: 'Título principal',
          displayTransform: (value) {
            final normalized = value.trim().isEmpty ? 'Título' : value.trim();
            return normalized.toUpperCase();
          },
        );
        final subtitleSlot = WebsiteInlineTextSlot(
          id: 'hero.subtitle',
          value: subtitle,
          valueKeys: const <String>['subtitle'],
          baseStyle: resolvedSubtitle.copyWith(
            fontSize: isMobile ? (bodySize ?? 16) : bodySize,
          ),
          formatting: subtitleFormatting,
          formattingKeys: const <String>['subtitleFormatting'],
          textAlign: fallbackTextAlign,
          placeholder: 'Subtítulo descriptivo',
        );

        final titleContent = presenters?.text?.call(context, titleSlot) ??
            Text(
              title.toUpperCase(),
              style: titleSlot.baseStyle,
              textAlign: titleSlot.resolvedTextAlign,
            );
        final subtitleContent = presenters?.text?.call(context, subtitleSlot) ??
            Text(
              subtitle,
              style: subtitleSlot.baseStyle,
              textAlign: subtitleSlot.resolvedTextAlign,
            );

        Widget? actionContent;
        if (visibleAction != null) {
          // Preview keeps VISITOR interaction semantics: navigation is inert
          // only in Edit, and Edit is identified by its injected presenters —
          // never by `previewMode`, which owns preview DATA semantics.
          final actionHref = visibleAction.href.trim();
          final button = WebsiteActionButton(
            action: visibleAction,
            // Mirrors the standalone-button contract: editor chrome owns the
            // pointer boundary, so a VALID destination stays enabled-looking
            // in Edit through a no-op — Material must never repaint the
            // authored foreground as disabled. Visitors navigate when a
            // handler exists; the legacy preview no-op survives only for a
            // missing handler. Empty hrefs stay truly disabled.
            onPressed: actionHref.isEmpty
                ? null
                : presenters != null
                    ? () {}
                    : onNavigate != null
                        ? () => onNavigate!(visibleAction.href)
                        : previewMode
                            ? () {}
                            : null,
            backgroundColor: accentColor,
            foregroundColor: Colors.white,
            outlineColor: Colors.white,
            uppercase: true,
            textStyle: const TextStyle(letterSpacing: 1.5),
          );
          final actionPresenter = presenters?.action;
          actionContent = actionPresenter == null
              ? button
              : actionPresenter(
                  context,
                  WebsiteInlineActionSlot(
                    id: 'hero.action',
                    action: visibleAction,
                    labelKeys: const <String>[
                      'ctaText',
                      'buttonText',
                      'label',
                    ],
                    hrefKeys: const <String>[
                      'ctaLink',
                      'buttonLink',
                      'link',
                    ],
                    variantKeys: const <String>['actionVariant'],
                    child: button,
                  ),
                );
        }

        final content = Align(
          key: contentKey,
          alignment: geometryAlignment,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: crossAxisAlignment,
              children: <Widget>[
                KeyedSubtree(key: titleKey, child: titleContent),
                if (subtitle.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 20),
                  KeyedSubtree(key: subtitleKey, child: subtitleContent),
                ],
                if (actionContent != null) ...<Widget>[
                  const SizedBox(height: 40),
                  KeyedSubtree(key: actionKey, child: actionContent),
                ],
              ],
            ),
          ),
        );

        Widget buildBackground({required bool skipImage}) {
          final fallback = DecoratedBox(
            decoration: _resolveBackgroundDecoration(
              data: data,
              imageUrl: hasImage && !skipImage ? imageUrl : null,
              imageAlignment: backgroundAlignment,
              imageProviderBuilder: imageProviderBuilder,
              imageConfigured: hasImage,
            ),
          );
          final mediaPresenter = presenters?.media;
          final background = mediaPresenter == null || skipImage
              ? fallback
              : mediaPresenter(
                  context,
                  WebsiteInlineMediaSlot(
                    id: 'hero.background',
                    url: hasImage ? imageUrl : null,
                    valueKeys: const <String>[
                      'imageUrl',
                      'backgroundImage',
                    ],
                    fit: BoxFit.cover,
                    alignment: backgroundAlignment,
                    fallback: fallback,
                    semanticLabel: imageAltText.isEmpty ? null : imageAltText,
                    // Same interactive-background class as a carousel slide:
                    // the hero CTA and copy live above this media. Its
                    // canonical editing control is the hero inspector's
                    // schema image field (`imageUrl`, WebsiteBlockFieldType
                    // .image in the registry).
                    editAffordance:
                        WebsiteInlineMediaEditAffordance.inspectorOnly,
                  ),
                );
          return Semantics(
            key: backgroundKey,
            image: hasImage,
            label: imageAltText.isEmpty ? null : imageAltText,
            child: background,
          );
        }

        Widget buildHero({required bool skipImage}) {
          return SizedBox(
            key: rootKey,
            height: height,
            width: double.infinity,
            child: Stack(
              fit: StackFit.expand,
              children: <Widget>[
                buildBackground(skipImage: skipImage),
                if (showOverlay && overlayOpacity > 0)
                  IgnorePointer(
                    child: DecoratedBox(
                      key: overlayKey,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: <Color>[
                            overlayColor.withValues(
                              alpha: overlayOpacity * 0.5,
                            ),
                            overlayColor.withValues(
                              alpha: overlayOpacity * 0.8,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                content,
              ],
            ),
          );
        }

        final deferImage = presenters == null &&
            !kIsWeb &&
            defaultTargetPlatform == TargetPlatform.android &&
            hasImage;
        if (!deferImage) return buildHero(skipImage: false);
        return _DeferredHeroImage(
          builder: (showImage) => buildHero(skipImage: !showImage),
        );
      },
    );
  }

  static WebsiteActionValue? _resolveAction(Map<String, dynamic> data) {
    final labelField = _firstPresentField(
      data,
      const <String>['ctaText', 'buttonText', 'label'],
    );
    final hrefField = _firstPresentField(
      data,
      const <String>['ctaLink', 'buttonLink', 'link'],
    );
    final resolved = WebsiteActionValue.resolvePrimary(
      data,
      labelKeys: const <String>['ctaText', 'buttonText', 'label'],
      hrefKeys: const <String>['ctaLink', 'buttonLink', 'link'],
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
    final variant = data.containsKey('actionVariant')
        ? WebsiteActionVariant.fromStorage(
            data['actionVariant']?.toString(),
            fallback: WebsiteActionVariant.outline,
          )
        : resolved?.variant ?? WebsiteActionVariant.outline;
    return WebsiteActionValue(label: label, href: href, variant: variant);
  }

  static WebsiteActionValue? _visibleAction(
    WebsiteActionValue? action, {
    required WebsiteBlockContentPresenters? presenters,
    required bool Function(String href)? isNavigationEligible,
  }) {
    if (action == null) return null;
    final href = action.href.trim();
    if (presenters != null) {
      return action;
    }
    if (href.isEmpty) return null;
    if (isNavigationEligible == null) return action;
    return isNavigationEligible(href) ? action : null;
  }

  static BoxDecoration _resolveBackgroundDecoration({
    required Map<String, dynamic> data,
    required String? imageUrl,
    required Alignment imageAlignment,
    required WebsiteHeroImageProviderBuilder? imageProviderBuilder,
    required bool imageConfigured,
  }) {
    final style = _stringMap(data['style']);
    final backgroundColor =
        _parseColor(style['backgroundColor']) ?? const Color(0xFF1A1A1A);
    final imageProvider = imageUrl == null || imageUrl.isEmpty
        ? null
        : imageProviderBuilder?.call(imageUrl) ?? NetworkImage(imageUrl);
    final borderWidth = _positiveFiniteDouble(style['borderWidth']) ?? 0;
    final borderColor =
        _parseColor(style['borderColor']) ?? Colors.grey.shade500;
    final borderRadius = _positiveFiniteDouble(style['borderRadius']) ?? 0;
    final shadowEnabled = style['shadowEnabled'] == true;
    final shadowColor = _parseRgbaColor(style['shadowColor']) ?? Colors.black26;
    final shadowOffsetX = _finiteDouble(style['shadowOffsetX']) ?? 0;
    final shadowOffsetY = _finiteDouble(style['shadowOffsetY']) ?? 4;
    final shadowBlur = _positiveFiniteDouble(style['shadowBlur']) ?? 12;
    final shadowSpread = _finiteDouble(style['shadowSpread']) ?? 0;
    final backgroundType =
        style['backgroundType']?.toString().trim().toLowerCase();
    final useGradient = backgroundType == 'gradient' && !imageConfigured;
    final hasStyle = data['style'] is Map;

    return BoxDecoration(
      color: backgroundColor,
      image: imageProvider == null
          ? null
          : DecorationImage(
              image: imageProvider,
              fit: BoxFit.cover,
              alignment: imageAlignment,
              onError: _ignoreBackgroundImageError,
            ),
      gradient: useGradient
          ? LinearGradient(
              begin: _gradientBegin(style['gradientDirection']?.toString()),
              end: _gradientEnd(style['gradientDirection']?.toString()),
              colors: <Color>[
                _parseColor(style['gradientColor1']) ?? Colors.white,
                _parseColor(style['gradientColor2']) ?? Colors.grey.shade100,
              ],
            )
          : !imageConfigured && !hasStyle
              ? LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: <Color>[
                    backgroundColor,
                    Color.lerp(backgroundColor, Colors.black, 0.2)!,
                  ],
                )
              : null,
      border: borderWidth > 0
          ? Border.all(
              color: borderColor,
              width: borderWidth,
              style: style['borderStyle'] == 'dotted' ||
                      style['borderStyle'] == 'dashed'
                  ? BorderStyle.none
                  : BorderStyle.solid,
            )
          : null,
      borderRadius:
          borderRadius > 0 ? BorderRadius.circular(borderRadius) : null,
      boxShadow: shadowEnabled
          ? <BoxShadow>[
              BoxShadow(
                offset: Offset(shadowOffsetX, shadowOffsetY),
                blurRadius: shadowBlur,
                spreadRadius: shadowSpread,
                color: shadowColor,
              ),
            ]
          : null,
    );
  }

  static Alignment _resolveFocalAlignment(
    Map<String, dynamic> data, {
    required bool useMobile,
  }) {
    final desktopX =
        (_finiteDouble(data['focalPointX']) ?? 0.5).clamp(0.0, 1.0);
    final desktopY =
        (_finiteDouble(data['focalPointY']) ?? 0.5).clamp(0.0, 1.0);
    if (useMobile) {
      final mobileX = _finiteDouble(data['mobileFocalPointX']);
      final mobileY = _finiteDouble(data['mobileFocalPointY']);
      if (mobileX != null && mobileY != null) {
        return Alignment(
          mobileX.clamp(0.0, 1.0) * 2 - 1,
          mobileY.clamp(0.0, 1.0) * 2 - 1,
        );
      }
      final legacy = _legacyMobileAlignment(data['mobileBgAlignment']);
      if (legacy != null) return legacy;
    }
    return Alignment(desktopX * 2 - 1, desktopY * 2 - 1);
  }

  static Alignment? _legacyMobileAlignment(Object? raw) {
    return switch (raw?.toString()) {
      'left' || 'centerLeft' => Alignment.centerLeft,
      'right' || 'centerRight' => Alignment.centerRight,
      'top' || 'topCenter' => Alignment.topCenter,
      'bottom' || 'bottomCenter' => Alignment.bottomCenter,
      'center' => Alignment.center,
      _ => null,
    };
  }

  static TextStyle _applyFont(TextStyle base, String? fontFamily) {
    final family = fontFamily?.trim();
    return family == null || family.isEmpty
        ? base
        : base.copyWith(fontFamily: family);
  }

  static TextFormatting _formatting(Object? raw) {
    return raw is Map
        ? TextFormatting.fromJson(Map<String, dynamic>.from(raw))
        : const TextFormatting();
  }

  static ({bool present, String value}) _firstPresentField(
    Map<String, dynamic> data,
    List<String> keys,
  ) {
    for (final key in keys) {
      if (data.containsKey(key)) {
        return (present: true, value: data[key]?.toString() ?? '');
      }
    }
    return (present: false, value: '');
  }

  static String? _firstNonNullString(
    Map<String, dynamic> data,
    List<String> keys,
  ) {
    for (final key in keys) {
      final value = data[key];
      if (value != null) return value.toString();
    }
    return null;
  }

  static Map<String, dynamic> _stringMap(Object? raw) {
    return raw is Map
        ? Map<String, dynamic>.from(raw)
        : const <String, dynamic>{};
  }

  static double? _finiteDouble(Object? raw) {
    final value = raw is num ? raw.toDouble() : double.tryParse('$raw');
    return value != null && value.isFinite ? value : null;
  }

  static double? _positiveFiniteDouble(Object? raw) {
    final value = _finiteDouble(raw);
    return value != null && value > 0 ? value : null;
  }

  static Color? _parseColor(Object? raw) {
    final value = raw?.toString().trim();
    if (value == null || value.isEmpty) return null;
    try {
      final normalized = value.replaceFirst('#', '');
      if (normalized.length == 6) {
        return Color(int.parse('FF$normalized', radix: 16));
      }
      if (normalized.length == 8) {
        return Color(int.parse(normalized, radix: 16));
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  static Color? _parseRgbaColor(Object? raw) {
    final value = raw?.toString().trim();
    if (value == null || value.isEmpty) return null;
    if (value.startsWith('#')) return _parseColor(value);
    final match = RegExp(r'rgba?\((\d+),\s*(\d+),\s*(\d+)(?:,\s*([\d.]+))?\)')
        .firstMatch(value);
    if (match == null) return null;
    return Color.fromRGBO(
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
      double.tryParse(match.group(4) ?? '') ?? 1,
    );
  }

  static Alignment _gradientBegin(String? raw) {
    return switch (raw) {
      'to-top' => Alignment.bottomCenter,
      'to-top-right' => Alignment.bottomLeft,
      'to-right' => Alignment.centerLeft,
      'to-bottom-right' => Alignment.topLeft,
      'to-bottom' => Alignment.topCenter,
      'to-bottom-left' => Alignment.topRight,
      'to-left' => Alignment.centerRight,
      'to-top-left' => Alignment.bottomRight,
      _ => Alignment.topCenter,
    };
  }

  static Alignment _gradientEnd(String? raw) {
    return switch (raw) {
      'to-top' => Alignment.topCenter,
      'to-top-right' => Alignment.topRight,
      'to-right' => Alignment.centerRight,
      'to-bottom-right' => Alignment.bottomRight,
      'to-bottom' => Alignment.bottomCenter,
      'to-bottom-left' => Alignment.bottomLeft,
      'to-left' => Alignment.centerLeft,
      'to-top-left' => Alignment.topLeft,
      _ => Alignment.bottomCenter,
    };
  }

  static void _ignoreBackgroundImageError(
    Object error,
    StackTrace? stackTrace,
  ) {}
}

class _DeferredHeroImage extends StatefulWidget {
  const _DeferredHeroImage({required this.builder});

  final Widget Function(bool showImage) builder;

  @override
  State<_DeferredHeroImage> createState() => _DeferredHeroImageState();
}

class _DeferredHeroImageState extends State<_DeferredHeroImage> {
  bool _showImage = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _showImage = true);
    });
  }

  @override
  Widget build(BuildContext context) => widget.builder(_showImage);
}
