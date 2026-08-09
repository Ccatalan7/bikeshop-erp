import 'package:flutter/material.dart';

import '../models/website_action.dart';
import '../models/website_block_surface_style.dart';
import '../models/website_block_type.dart';
import 'text_formatting_toolbar.dart';
import 'website_action_button.dart';
import 'website_block_content_presenters.dart';

typedef WebsiteCtaImageProviderBuilder = ImageProvider<Object> Function(
  String url,
);

/// Pure shared content tree for the Website Builder CTA block.
///
/// Public and Preview render this widget directly. Edit injects presentation
/// hooks through [presenters], keeping editor state and commands outside the
/// shared storefront renderer.
class WebsiteCtaBlockContent extends StatelessWidget {
  const WebsiteCtaBlockContent({
    super.key,
    required this.data,
    required this.surfaceStyle,
    required this.primaryColor,
    required this.accentColor,
    this.previewMode = false,
    this.headingFont,
    this.bodyFont,
    this.onNavigate,
    this.isNavigationEligible,
    this.presenters,
    this.imageProviderBuilder,
  });

  final Map<String, dynamic> data;
  final WebsiteBlockSurfaceStyle surfaceStyle;
  final Color primaryColor;
  final Color accentColor;
  final bool previewMode;
  final String? headingFont;
  final String? bodyFont;
  final void Function(String route)? onNavigate;
  final bool Function(String href)? isNavigationEligible;
  final WebsiteBlockContentPresenters? presenters;

  /// Allows focused widget tests to avoid loading remote media.
  final WebsiteCtaImageProviderBuilder? imageProviderBuilder;

  static const rootKey = ValueKey<String>('website-cta-root');
  static const backgroundKey = ValueKey<String>('website-cta-background-media');
  static const overlayKey = ValueKey<String>('website-cta-overlay');
  static const paddingKey = ValueKey<String>('website-cta-content-padding');
  static const contentFrameKey = ValueKey<String>('website-cta-content-frame');
  static const titleKey = ValueKey<String>('website-cta-title');
  static const subtitleKey = ValueKey<String>('website-cta-subtitle');
  static const actionKey = ValueKey<String>('website-cta-action');

  @override
  Widget build(BuildContext context) {
    final title = _firstString(data, const <String>['title']);
    final subtitle = _firstString(
      data,
      const <String>['subtitle', 'description'],
    );
    final action = _resolveAction(data);
    final presenters = this.presenters;
    final visibleAction = _visibleAction(
      action,
      presenters: presenters,
      isNavigationEligible: isNavigationEligible,
    );
    final backgroundImage = _firstString(
      data,
      const <String>['backgroundImage', 'imageUrl'],
    ).trim();
    final hasBackgroundImage = backgroundImage.isNotEmpty;
    final focalAlignment = _resolveFocalAlignment(data);
    final blockHeight = _positiveFiniteDouble(data['blockHeight']);
    final titleFormatting = _resolveFormatting(data['titleFormatting']);
    final subtitleFormatting = _resolveFormatting(
      data['subtitleFormatting'] ?? data['descriptionFormatting'],
    );
    final titleStyle = titleFormatting.applyTo(
      TextStyle(
        fontFamily: _nonEmpty(headingFont),
        fontSize: 24,
        fontWeight: FontWeight.w700,
        color: Colors.white,
        letterSpacing: 1,
      ),
    );
    final subtitleStyle = subtitleFormatting.applyTo(
      (Theme.of(context).textTheme.bodyLarge ?? const TextStyle(fontSize: 16))
          .copyWith(
        fontFamily: _nonEmpty(bodyFont),
        color: Colors.white70,
      ),
    );
    final resolvedTitle =
        title.trim().isEmpty ? '¿Necesitas ayuda?' : title.trim();

    final titleSlot = WebsiteInlineTextSlot(
      id: 'cta.title',
      value: title,
      valueKeys: const <String>['title'],
      baseStyle: const TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.w700,
        color: Colors.white,
        letterSpacing: 1,
      ).copyWith(fontFamily: _nonEmpty(headingFont)),
      formatting: titleFormatting,
      formattingKeys: const <String>['titleFormatting'],
      textAlign: TextAlign.center,
      placeholder: 'Llamado a la acción',
      displayTransform: (value) {
        final displayValue =
            value.trim().isEmpty ? '¿Necesitas ayuda?' : value.trim();
        return displayValue.toUpperCase();
      },
    );
    final subtitleSlot = WebsiteInlineTextSlot(
      id: 'cta.subtitle',
      value: subtitle,
      valueKeys: const <String>['subtitle', 'description'],
      baseStyle: (Theme.of(context).textTheme.bodyLarge ??
              const TextStyle(fontSize: 16))
          .copyWith(
        fontFamily: _nonEmpty(bodyFont),
        color: Colors.white70,
      ),
      formatting: subtitleFormatting,
      formattingKeys: const <String>[
        'subtitleFormatting',
        'descriptionFormatting',
      ],
      textAlign: TextAlign.center,
      placeholder: 'Descripción del llamado a la acción',
    );

    final titleContent = presenters?.text?.call(context, titleSlot) ??
        Text(
          resolvedTitle.toUpperCase(),
          style: titleStyle,
          textAlign: _centerWhenUnspecified(titleFormatting.textAlign),
        );
    final subtitleContent = presenters?.text?.call(context, subtitleSlot) ??
        Text(
          subtitle,
          style: subtitleStyle,
          textAlign: _centerWhenUnspecified(subtitleFormatting.textAlign),
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
        textStyle: const TextStyle(letterSpacing: 1),
        style: const ButtonStyle(
          minimumSize: WidgetStatePropertyAll<Size>(Size(0, 48)),
        ),
      );
      final actionPresenter = presenters?.action;
      actionContent = actionPresenter == null
          ? button
          : actionPresenter(
              context,
              WebsiteInlineActionSlot(
                id: 'cta.action',
                action: visibleAction,
                labelKeys: const <String>['buttonText', 'ctaText'],
                hrefKeys: const <String>['buttonLink', 'ctaLink'],
                variantKeys: const <String>['actionVariant'],
                child: button,
              ),
            );
    }

    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        KeyedSubtree(
          key: titleKey,
          child: titleContent,
        ),
        if (subtitle.isNotEmpty || presenters?.text != null) ...<Widget>[
          const SizedBox(height: 12),
          KeyedSubtree(
            key: subtitleKey,
            child: subtitleContent,
          ),
        ],
        if (actionContent != null) ...<Widget>[
          const SizedBox(height: 24),
          KeyedSubtree(
            key: actionKey,
            child: actionContent,
          ),
        ],
      ],
    );

    final backgroundFallback = DecoratedBox(
      key: backgroundKey,
      decoration: surfaceStyle.contentBackgroundDecoration(
        fallbackColor: primaryColor,
        imageProvider: hasBackgroundImage
            ? imageProviderBuilder?.call(backgroundImage) ??
                NetworkImage(backgroundImage)
            : null,
        imageAlignment: focalAlignment,
        preserveLegacyFallbackGradient: !hasBackgroundImage,
        onImageError: _ignoreBackgroundImageError,
      ),
    );
    final mediaPresenter = presenters?.media;
    final background = mediaPresenter == null
        ? backgroundFallback
        : mediaPresenter(
            context,
            WebsiteInlineMediaSlot(
              id: 'cta.background',
              url: hasBackgroundImage ? backgroundImage : null,
              valueKeys: const <String>['backgroundImage', 'imageUrl'],
              fit: BoxFit.cover,
              alignment: focalAlignment,
              fallback: backgroundFallback,
              semanticLabel: _firstString(
                data,
                const <String>[
                  'backgroundImageAltText',
                  'imageAltText',
                ],
              ).trim(),
            ),
          );
    final overlayColor =
        _parseColor(data['overlayColor']) ?? const Color(0xFF000000);
    final overlayOpacity =
        (_finiteDouble(data['overlayOpacity']) ?? 0.5).clamp(0.0, 1.0);

    return SizedBox(
      key: rootKey,
      width: double.infinity,
      height: blockHeight,
      child: Stack(
        fit: StackFit.passthrough,
        clipBehavior: Clip.none,
        children: <Widget>[
          Positioned.fill(child: background),
          if (hasBackgroundImage && overlayOpacity > 0)
            Positioned.fill(
              child: ColoredBox(
                key: overlayKey,
                color: overlayColor.withValues(alpha: overlayOpacity),
              ),
            ),
          Padding(
            key: paddingKey,
            padding: surfaceStyle.paddingWithFallback(
              WebsiteBlockSurfaceDefaults.paddingFor(
                blockType: WebsiteBlockType.cta,
                viewport: surfaceStyle.viewport,
                data: data,
              ),
            ),
            child: Center(
              child: ConstrainedBox(
                key: contentFrameKey,
                constraints: const BoxConstraints(maxWidth: 800),
                child: content,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static WebsiteActionValue? _resolveAction(Map<String, dynamic> data) {
    final labelField = _firstPresentString(
      data,
      const <String>['buttonText', 'ctaText', 'label'],
    );
    final hrefField = _firstPresentString(
      data,
      const <String>['buttonLink', 'ctaLink', 'link'],
    );
    final resolved = WebsiteActionValue.resolvePrimary(
      data,
      labelKeys: const <String>['buttonText', 'ctaText', 'label'],
      hrefKeys: const <String>['buttonLink', 'ctaLink', 'link'],
      variantKeys: const <String>['actionVariant'],
      defaultLabel: '',
      defaultHref: '',
      defaultVariant: WebsiteActionVariant.outline,
    );

    final label = labelField.present
        ? labelField.value.trim()
        : resolved?.label.trim() ?? '';
    if (label.isEmpty) return null;

    final href = hrefField.present
        ? hrefField.value.trim()
        : resolved?.href.trim() ?? '';
    final hasExplicitVariant = data.containsKey('actionVariant');
    final variant = hasExplicitVariant
        ? WebsiteActionVariant.fromStorage(
            data['actionVariant']?.toString(),
            fallback: WebsiteActionVariant.outline,
          )
        : resolved?.variant ?? WebsiteActionVariant.outline;
    return WebsiteActionValue(
      label: label,
      href: href,
      variant: variant,
    );
  }

  static WebsiteActionValue? _visibleAction(
    WebsiteActionValue? action, {
    required WebsiteBlockContentPresenters? presenters,
    required bool Function(String href)? isNavigationEligible,
  }) {
    if (action == null) return null;
    final href = action.href.trim();
    if (presenters != null || href.isEmpty || isNavigationEligible == null) {
      return action;
    }
    return isNavigationEligible(href) ? action : null;
  }

  static Alignment _resolveFocalAlignment(Map<String, dynamic> data) {
    final x = _finiteDouble(data['focalPointX']) ?? 0.5;
    final y = _finiteDouble(data['focalPointY']) ?? 0.5;
    return Alignment(
      (x.clamp(0.0, 1.0) * 2) - 1,
      (y.clamp(0.0, 1.0) * 2) - 1,
    );
  }

  static TextFormatting _resolveFormatting(Object? raw) {
    final map = raw is Map ? Map<String, dynamic>.from(raw) : null;
    return TextFormatting.fromJson(map);
  }

  static TextAlign _centerWhenUnspecified(TextAlign alignment) {
    return alignment == TextAlign.start ? TextAlign.center : alignment;
  }

  static String? _nonEmpty(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  static String _firstString(
    Map<String, dynamic> data,
    List<String> keys,
  ) {
    for (final key in keys) {
      if (data.containsKey(key)) return data[key]?.toString() ?? '';
    }
    return '';
  }

  static ({bool present, String value}) _firstPresentString(
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

  static double? _finiteDouble(Object? raw) {
    final value = switch (raw) {
      num number => number.toDouble(),
      String text => double.tryParse(text.trim()),
      _ => null,
    };
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
      var hex = value.replaceFirst('#', '');
      if (hex.length == 6) hex = 'FF$hex';
      if (hex.length != 8) return null;
      return Color(int.parse(hex, radix: 16));
    } catch (_) {
      return null;
    }
  }

  static void _ignoreBackgroundImageError(
    Object exception,
    StackTrace? stackTrace,
  ) {
    // The configured color remains the visible, deterministic fallback.
  }
}
