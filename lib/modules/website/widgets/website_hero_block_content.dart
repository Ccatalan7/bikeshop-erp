import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/website_action.dart';
import '../models/website_block_surface_style.dart';
import '../models/website_block_type.dart';
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
    required this.surfaceStyle,
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
  final WebsiteBlockSurfaceStyle surfaceStyle;

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
        final backgroundAlignment = _resolveFocalAlignment(data);
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
            padding: surfaceStyle.paddingWithFallback(
              WebsiteBlockSurfaceDefaults.paddingFor(
                blockType: WebsiteBlockType.hero,
                viewport: surfaceStyle.viewport,
                data: data,
              ),
            ),
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
          final imageProvider = hasImage && !skipImage
              ? imageProviderBuilder?.call(imageUrl) ?? NetworkImage(imageUrl)
              : null;
          final fallback = DecoratedBox(
            decoration: surfaceStyle.contentBackgroundDecoration(
              fallbackColor: const Color(0xFF1A1A1A),
              imageProvider: imageProvider,
              imageAlignment: backgroundAlignment,
              preserveLegacyFallbackGradient: !hasImage,
              onImageError: _ignoreBackgroundImageError,
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

  static Alignment _resolveFocalAlignment(Map<String, dynamic> data) {
    final focalX = (_finiteDouble(data['focalPointX']) ?? 0.5).clamp(0.0, 1.0);
    final focalY = (_finiteDouble(data['focalPointY']) ?? 0.5).clamp(0.0, 1.0);
    return Alignment(focalX * 2 - 1, focalY * 2 - 1);
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
