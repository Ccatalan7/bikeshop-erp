import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:vinabike_public_core/modules/website/models/website_hero_content.dart';

import '../models/website_action.dart';
import '../models/website_block_surface_style.dart';
import '../models/website_block_type.dart';
import '../../../shared/utils/chilean_utils.dart';
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
    this.card,
    this.onCardTap,
    this.rating,
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

  /// The split hero's card ([websiteHeroCardReference]), read from the
  /// catalog by the renderer, and what tapping it does; `null` draws none.
  final WebsiteHeroCard? card;
  final VoidCallback? onCardTap;

  /// The site's Google score for the split hero ([websiteHeroRating]).
  final ({double rating, int? total})? rating;

  static const splitKey = ValueKey<String>('website-hero-split');
  static const splitCardKey = ValueKey<String>('website-hero-split-card');
  static const secondaryActionKey =
      ValueKey<String>('website-hero-secondary-action');

  @override
  Widget build(BuildContext context) {
    if (websiteHeroLayout(data) == WebsiteHeroLayout.split) {
      return _SplitHero(content: this);
    }
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
                  WebsiteInlineActionSlot.button(
                    WebsiteButtonFields.hero,
                    id: 'hero.action',
                    action: visibleAction,
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

  static WebsiteActionValue? _resolveAction(Map<String, dynamic> data) =>
      resolveWebsiteHeroAction(data);

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

/// The hero's «Partida» layout, as the HTML storefront's `_SplitHero`
/// draws it: the eyebrow, title, subtitle, two buttons and the Google score
/// on a panel of the site's primary color, five parts to the photo's seven,
/// the photo with the card of a catalog product; under 900 px the photo
/// first, the panel under it and no card.
class _SplitHero extends StatelessWidget {
  const _SplitHero({required this.content});

  final WebsiteHeroBlockContent content;

  static const _ink = Color(0xFF17211B);
  static const _star = Color(0xFFF5B33A);

  /// White or the store's dark ink, whichever reads better on [background]
  /// (`WebsiteRgba.readableOn`, the HTML's `--w-onprim`).
  static Color _readableOn(Color background) {
    double contrast(Color a, Color b) {
      final la = a.computeLuminance();
      final lb = b.computeLuminance();
      return (max(la, lb) + 0.05) / (min(la, lb) + 0.05);
    }

    return contrast(Colors.white, background) >= contrast(_ink, background)
        ? Colors.white
        : _ink;
  }

  @override
  Widget build(BuildContext context) {
    final data = content.data;
    final presenters = content.presenters;
    final primary = content.primaryColor;
    final onPrimary = _readableOn(primary);
    final soft = Color.lerp(primary, onPrimary, 0.84)!;
    final faint = Color.lerp(primary, onPrimary, 0.68)!;
    final eyebrow = (data['eyebrow'] ?? '').toString().trim();
    final rawTitle = (data['title'] ?? '').toString();
    final subtitle = (data['subtitle'] ?? '').toString().trim();
    final imageUrl = WebsiteHeroBlockContent._firstNonNullString(
      data,
      const <String>['imageUrl', 'backgroundImage'],
    )?.trim();
    final hasImage = imageUrl != null && imageUrl.isNotEmpty;
    final imageAltText = WebsiteHeroBlockContent._firstNonNullString(
          data,
          const <String>['imageAltText', 'backgroundImageAltText', 'altText'],
        )?.trim() ??
        '';
    final alignment = WebsiteHeroBlockContent._resolveFocalAlignment(data);
    final imageLeft = websiteHeroImageOnLeft(data);
    final configuredHeight =
        WebsiteHeroBlockContent._positiveFiniteDouble(data['blockHeight']);
    final primaryAction = WebsiteHeroBlockContent._visibleAction(
      resolveWebsiteHeroAction(data),
      presenters: presenters,
      isNavigationEligible: content.isNavigationEligible,
    );
    final secondaryAction = WebsiteHeroBlockContent._visibleAction(
      resolveWebsiteHeroSecondaryAction(data),
      presenters: presenters,
      isNavigationEligible: content.isNavigationEligible,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        final stacked = width < 900;
        final titleSize = stacked
            ? (width * 0.09).clamp(34.0, 44.0)
            : (width * 0.044).clamp(40.0, 64.0);

        Widget text({
          required String id,
          required String value,
          required List<String> keys,
          required TextStyle style,
          required String placeholder,
          List<String> formattingKeys = const <String>[],
          String Function(String value)? transform,
        }) {
          final slot = WebsiteInlineTextSlot(
            id: id,
            value: value,
            valueKeys: keys,
            baseStyle: style,
            formatting: formattingKeys.isEmpty
                ? const TextFormatting()
                : WebsiteHeroBlockContent._formatting(
                    data[formattingKeys.first]),
            formattingKeys: formattingKeys,
            textAlign: TextAlign.left,
            placeholder: placeholder,
            displayTransform: transform,
          );
          return presenters?.text?.call(context, slot) ??
              Text(
                transform?.call(value) ?? value,
                style: slot.baseStyle,
                textAlign: slot.resolvedTextAlign,
              );
        }

        final titleStyle = WebsiteHeroBlockContent._formatting(
          data['titleFormatting'],
        ).applyTo(
          WebsiteHeroBlockContent._applyFont(
            TextStyle(
              fontSize: titleSize,
              height: 1.04,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.005 * titleSize,
              color: onPrimary,
            ),
            content.headingFont,
          ),
        );
        final subtitleStyle = WebsiteHeroBlockContent._formatting(
          data['subtitleFormatting'],
        ).applyTo(
          WebsiteHeroBlockContent._applyFont(
            TextStyle(
              fontSize: stacked ? 16 : 19,
              height: 1.5,
              color: soft,
            ),
            content.bodyFont,
          ),
        );

        Widget button(
          WebsiteActionValue action, {
          required bool solid,
          required Key key,
        }) {
          final href = action.href.trim();
          final VoidCallback? onPressed = href.isEmpty
              ? null
              : presenters != null
                  ? () {}
                  : content.onNavigate != null
                      ? () => content.onNavigate!(action.href)
                      : content.previewMode
                          ? () {}
                          : null;
          final label = Text(
            action.label,
            style: WebsiteHeroBlockContent._applyFont(
              TextStyle(
                fontSize: 16,
                fontWeight: solid ? FontWeight.w700 : FontWeight.w600,
              ),
              content.bodyFont,
            ),
          );
          const size = Size(64, 52);
          const padding = EdgeInsets.symmetric(horizontal: 26);
          final Widget control = solid
              ? FilledButton(
                  onPressed: onPressed,
                  style: FilledButton.styleFrom(
                    backgroundColor: onPrimary,
                    foregroundColor: primary,
                    minimumSize: size,
                    padding: padding,
                  ),
                  child: label,
                )
              : OutlinedButton(
                  onPressed: onPressed,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: onPrimary,
                    minimumSize: size,
                    padding: padding,
                    side: BorderSide(
                      color: onPrimary.withValues(alpha: 0.55),
                      width: 1.5,
                    ),
                  ),
                  child: label,
                );
          final actionPresenter = presenters?.action;
          final presented = !solid || actionPresenter == null
              ? control
              : actionPresenter(
                  context,
                  WebsiteInlineActionSlot.button(
                    WebsiteButtonFields.hero,
                    id: 'hero.action',
                    action: action,
                    child: control,
                  ),
                );
          return KeyedSubtree(key: key, child: presented);
        }

        final ratingValue = content.rating;
        final copy = Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            if (eyebrow.isNotEmpty || presenters != null) ...<Widget>[
              text(
                id: 'hero.eyebrow',
                value: eyebrow,
                keys: const <String>['eyebrow'],
                placeholder: 'Antetítulo',
                transform: (value) => value.toUpperCase(),
                style: WebsiteHeroBlockContent._applyFont(
                  TextStyle(
                    fontSize: stacked ? 12 : 13,
                    height: 1.4,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.8,
                    color: faint,
                  ),
                  content.bodyFont,
                ),
              ),
              SizedBox(height: stacked ? 16 : 22),
            ],
            KeyedSubtree(
              key: WebsiteHeroBlockContent.titleKey,
              child: text(
                id: 'hero.title',
                value: rawTitle,
                keys: const <String>['title'],
                formattingKeys: const <String>['titleFormatting'],
                placeholder: 'Título principal',
                transform: (value) =>
                    value.trim().isEmpty ? 'Título' : value.trim(),
                style: titleStyle,
              ),
            ),
            if (subtitle.isNotEmpty || presenters != null) ...<Widget>[
              SizedBox(height: stacked ? 16 : 22),
              KeyedSubtree(
                key: WebsiteHeroBlockContent.subtitleKey,
                child: text(
                  id: 'hero.subtitle',
                  value: subtitle,
                  keys: const <String>['subtitle'],
                  formattingKeys: const <String>['subtitleFormatting'],
                  placeholder: 'Subtítulo descriptivo',
                  style: subtitleStyle,
                ),
              ),
            ],
            if (primaryAction != null || secondaryAction != null) ...<Widget>[
              SizedBox(height: stacked ? 20 : 28),
              if (stacked)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    if (primaryAction != null)
                      button(
                        primaryAction,
                        solid: true,
                        key: WebsiteHeroBlockContent.actionKey,
                      ),
                    if (primaryAction != null && secondaryAction != null)
                      const SizedBox(height: 12),
                    if (secondaryAction != null)
                      button(
                        secondaryAction,
                        solid: false,
                        key: WebsiteHeroBlockContent.secondaryActionKey,
                      ),
                  ],
                )
              else
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: <Widget>[
                    if (primaryAction != null)
                      button(
                        primaryAction,
                        solid: true,
                        key: WebsiteHeroBlockContent.actionKey,
                      ),
                    if (secondaryAction != null)
                      button(
                        secondaryAction,
                        solid: false,
                        key: WebsiteHeroBlockContent.secondaryActionKey,
                      ),
                  ],
                ),
            ],
            if (ratingValue != null) ...<Widget>[
              SizedBox(height: stacked ? 16 : 26),
              _Rating(
                rating: ratingValue.rating,
                total: ratingValue.total,
                color: soft,
                strong: onPrimary,
                font: content.bodyFont,
              ),
            ],
          ],
        );

        final panel = ColoredBox(
          color: primary,
          child: Padding(
            padding: stacked
                ? const EdgeInsets.fromLTRB(20, 28, 20, 32)
                : imageLeft
                    ? const EdgeInsets.fromLTRB(56, 72, 32, 72)
                    : const EdgeInsets.fromLTRB(32, 72, 56, 72),
            child: Align(
              alignment: stacked || imageLeft
                  ? Alignment.centerLeft
                  : Alignment.centerRight,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: stacked ? double.infinity : 560,
                ),
                child: copy,
              ),
            ),
          ),
        );

        final fallback = ColoredBox(
          color: Color.lerp(primary, Colors.black, 0.22)!,
        );
        Widget photo = hasImage
            ? Image(
                image: content.imageProviderBuilder?.call(imageUrl) ??
                    NetworkImage(imageUrl),
                fit: BoxFit.cover,
                alignment: alignment,
                errorBuilder: (_, __, ___) => fallback,
              )
            : fallback;
        final mediaPresenter = presenters?.media;
        if (mediaPresenter != null) {
          photo = mediaPresenter(
            context,
            WebsiteInlineMediaSlot(
              id: 'hero.background',
              url: hasImage ? imageUrl : null,
              valueKeys: const <String>['imageUrl', 'backgroundImage'],
              fit: BoxFit.cover,
              alignment: alignment,
              fallback: fallback,
              semanticLabel: imageAltText.isEmpty ? null : imageAltText,
              editAffordance: WebsiteInlineMediaEditAffordance.inspectorOnly,
            ),
          );
        }
        final card = content.card;
        final media = Stack(
          fit: StackFit.expand,
          children: <Widget>[
            // Positioned, so the photo's own size never sets the hero's
            // height: the panel's words do (IntrinsicHeight below).
            Positioned.fill(
              child: Semantics(
                key: WebsiteHeroBlockContent.backgroundKey,
                image: hasImage,
                label: imageAltText.isEmpty ? null : imageAltText,
                child: photo,
              ),
            ),
            if (card != null && !stacked)
              Positioned(
                left: imageLeft ? null : 32,
                right: imageLeft ? 32 : null,
                bottom: 32,
                child: _HeroCard(
                  key: WebsiteHeroBlockContent.splitCardKey,
                  card: card,
                  onTap: presenters != null ? null : content.onCardTap,
                  font: content.bodyFont,
                ),
              ),
          ],
        );

        if (stacked) {
          return Column(
            key: WebsiteHeroBlockContent.splitKey,
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              SizedBox(height: min(width * 2 / 3, 420), child: media),
              panel,
            ],
          );
        }
        final panelSlot = Expanded(flex: 5, child: panel);
        final mediaSlot = Expanded(flex: 7, child: media);
        return ConstrainedBox(
          key: WebsiteHeroBlockContent.splitKey,
          constraints: BoxConstraints(minHeight: configuredHeight ?? 580),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: imageLeft
                  ? <Widget>[mediaSlot, panelSlot]
                  : <Widget>[panelSlot, mediaSlot],
            ),
          ),
        );
      },
    );
  }
}

/// The site's Google score: five stars, the score and the reviews.
class _Rating extends StatelessWidget {
  const _Rating({
    required this.rating,
    required this.total,
    required this.color,
    required this.strong,
    this.font,
  });

  final double rating;
  final int? total;
  final Color color;
  final Color strong;
  final String? font;

  @override
  Widget build(BuildContext context) {
    final score = websiteHeroRatingScore(rating);
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 10,
      runSpacing: 6,
      children: <Widget>[
        Semantics(
          label: '$score de 5 estrellas',
          child: ExcludeSemantics(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                for (var index = 1; index <= 5; index++)
                  Icon(
                    rating >= index - 0.25
                        ? Icons.star
                        : rating >= index - 0.75
                            ? Icons.star_half
                            : Icons.star_border,
                    size: 18,
                    color: _SplitHero._star,
                  ),
              ],
            ),
          ),
        ),
        Text.rich(
          TextSpan(
            children: <InlineSpan>[
              TextSpan(
                text: score,
                style: TextStyle(color: strong, fontWeight: FontWeight.w700),
              ),
              TextSpan(text: ' ${websiteHeroRatingSource(total)}'),
            ],
          ),
          style: WebsiteHeroBlockContent._applyFont(
            TextStyle(fontSize: 15, height: 1.4, color: color),
            font,
          ),
        ),
      ],
    );
  }
}

/// The card of a product or service over the split hero's photo.
class _HeroCard extends StatelessWidget {
  const _HeroCard({
    super.key,
    required this.card,
    required this.onTap,
    this.font,
  });

  final WebsiteHeroCard card;
  final VoidCallback? onTap;
  final String? font;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    TextStyle style(double size, FontWeight weight, Color color) =>
        WebsiteHeroBlockContent._applyFont(
          TextStyle(
            fontSize: size,
            height: 1.35,
            fontWeight: weight,
            color: color,
          ),
          font,
        );
    return SizedBox(
      width: 320,
      child: Material(
        color: scheme.surface,
        elevation: 12,
        shadowColor: const Color(0x66061628),
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 20, 22, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(
                  card.eyebrow.toUpperCase(),
                  style: style(12, FontWeight.w700, scheme.onSurfaceVariant)
                      .copyWith(letterSpacing: 1.2),
                ),
                const SizedBox(height: 6),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        card.name,
                        style: style(18, FontWeight.w700, scheme.onSurface),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      ChileanUtils.formatCurrency(card.price),
                      style:
                          style(18, FontWeight.w700, scheme.onSurface).copyWith(
                        fontFeatures: const <FontFeature>[
                          FontFeature.tabularFigures(),
                        ],
                      ),
                    ),
                  ],
                ),
                if (card.text.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 6),
                  Text(
                    card.text,
                    style: style(14, FontWeight.w400, scheme.onSurfaceVariant),
                  ),
                ],
                const SizedBox(height: 10),
                Row(
                  children: <Widget>[
                    Text(
                      card.linkLabel,
                      style: style(14, FontWeight.w700, scheme.primary),
                    ),
                    const SizedBox(width: 4),
                    Icon(Icons.arrow_forward, size: 16, color: scheme.primary),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
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
