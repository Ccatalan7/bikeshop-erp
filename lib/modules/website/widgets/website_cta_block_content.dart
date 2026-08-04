import 'package:flutter/material.dart';

import '../models/website_action.dart';
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
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isMobile = screenWidth < 600;
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
    final focalAlignment = _resolveFocalAlignment(
      data,
      useMobile: isMobile,
    );
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
      decoration: _resolveBackgroundDecoration(
        data: data,
        defaultColor: primaryColor,
        imageUrl: hasBackgroundImage ? backgroundImage : null,
        imageAlignment: focalAlignment,
        imageProviderBuilder: imageProviderBuilder,
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
            padding: EdgeInsets.symmetric(
              horizontal: isMobile ? 16 : 24,
              vertical: blockHeight == null ? 56 : 0,
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

  static BoxDecoration _resolveBackgroundDecoration({
    required Map<String, dynamic> data,
    required Color defaultColor,
    required String? imageUrl,
    required Alignment imageAlignment,
    required WebsiteCtaImageProviderBuilder? imageProviderBuilder,
  }) {
    final style = _stringMap(data['style']);
    final backgroundColor = _parseColor(
          style['backgroundColor'] ?? data['backgroundColor'],
        ) ??
        defaultColor;
    final hasImage = imageUrl != null && imageUrl.isNotEmpty;
    final imageProvider = hasImage
        ? imageProviderBuilder?.call(imageUrl) ?? NetworkImage(imageUrl)
        : null;
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
    final useGradient = backgroundType == 'gradient' && !hasImage;
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
              begin: _gradientBegin(
                style['gradientDirection']?.toString(),
              ),
              end: _gradientEnd(
                style['gradientDirection']?.toString(),
              ),
              colors: <Color>[
                _parseColor(style['gradientColor1']) ?? Colors.white,
                _parseColor(style['gradientColor2']) ?? Colors.grey.shade100,
              ],
            )
          : !hasImage && !hasStyle
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
    final desktopX = _finiteDouble(data['focalPointX']) ?? 0.5;
    final desktopY = _finiteDouble(data['focalPointY']) ?? 0.5;
    final x = useMobile
        ? _finiteDouble(data['mobileFocalPointX']) ?? desktopX
        : desktopX;
    final y = useMobile
        ? _finiteDouble(data['mobileFocalPointY']) ?? desktopY
        : desktopY;
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

  static Map<String, dynamic> _stringMap(Object? raw) {
    if (raw is! Map) return <String, dynamic>{};
    return raw.map<String, dynamic>(
      (key, value) => MapEntry<String, dynamic>(key.toString(), value),
    );
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

  static Color? _parseRgbaColor(Object? raw) {
    final value = raw?.toString().trim();
    if (value == null || value.isEmpty) return null;
    if (value.startsWith('#')) return _parseColor(value);
    final match = RegExp(
      r'rgba?\((\d+),\s*(\d+),\s*(\d+)(?:,\s*([\d.]+))?\)',
    ).firstMatch(value);
    if (match == null) return null;
    try {
      return Color.fromRGBO(
        int.parse(match.group(1)!),
        int.parse(match.group(2)!),
        int.parse(match.group(3)!),
        double.tryParse(match.group(4) ?? '') ?? 1,
      );
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

  static Alignment _gradientBegin(String? direction) {
    return switch (direction?.trim().toLowerCase()) {
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

  static Alignment _gradientEnd(String? direction) {
    return switch (direction?.trim().toLowerCase()) {
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
}
