import 'package:flutter/material.dart';
import 'package:vinabike_public_core/modules/website/theme/website_section_palette.dart';
import 'package:vinabike_public_core/modules/website/theme/website_theme_roles.dart';

import '../../../public_store/widgets/public_link_semantics.dart';
import '../models/website_action.dart';
import 'text_formatting_toolbar.dart';
import 'website_block_content_presenters.dart';

/// What the section blocks (stats, services, plans, testimonials, gallery,
/// team, questions, the brands strip and the call to action) share in
/// Flutter since the sections design (2026-10-07), as the HTML storefront
/// draws them (`website_section_blocks_view.dart`): the band on its tone
/// (`WebsiteSectionPalette`), the sizes by the block's own width
/// (`WebsiteSectionMetrics`), the header (eyebrow, title, note) and the
/// buttons.

Color websiteSectionColor(WebsiteRgba color) =>
    Color.from(alpha: color.a, red: color.r, green: color.g, blue: color.b);

WebsiteRgba websiteSectionRgba(Color color) =>
    WebsiteRgba(color.a, color.r, color.g, color.b);

/// A section palette as Flutter colors.
class WebsiteSectionColors {
  WebsiteSectionColors._(this.palette, {Color? surface})
      : surface = surface ?? websiteSectionColor(palette.surface),
        ink = websiteSectionColor(palette.ink),
        muted = websiteSectionColor(palette.muted),
        soft = websiteSectionColor(
          WebsiteRgba.lerp(palette.ink, palette.surface, 0.15),
        ),
        rule = websiteSectionColor(palette.rule),
        strongRule = websiteSectionColor(palette.strongRule),
        eyebrow = websiteSectionColor(palette.eyebrow),
        mark = websiteSectionColor(palette.mark),
        tint = websiteSectionColor(palette.tint),
        card = websiteSectionColor(palette.card),
        cardRule = websiteSectionColor(palette.cardRule),
        accent = websiteSectionColor(palette.accent),
        onAccent = websiteSectionColor(palette.onAccent);

  /// [tone]'s colors for the site theme in [context] (its background and
  /// text) with the block's [primary] and [accent].
  factory WebsiteSectionColors.of(
    BuildContext context, {
    required WebsiteSectionTone tone,
    required Color primary,
    required Color accent,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return WebsiteSectionColors._(
      WebsiteSectionPalette.resolve(
        tone: tone,
        primary: websiteSectionRgba(primary),
        accent: websiteSectionRgba(accent),
        background: websiteSectionRgba(scheme.surface),
        onSurface: websiteSectionRgba(scheme.onSurface),
      ),
    );
  }

  final WebsiteSectionPalette palette;
  final Color surface;

  /// The same colors on a surface lifted from a dark section: a featured
  /// part inside a section that is already dark.
  WebsiteSectionColors get lifted =>
      WebsiteSectionColors._(palette, surface: card);
  final Color ink;
  final Color muted;

  /// Between [ink] and [muted]: an answer's words.
  final Color soft;
  final Color rule;
  final Color strongRule;
  final Color eyebrow;
  final Color mark;
  final Color tint;
  final Color card;
  final Color cardRule;
  final Color accent;
  final Color onAccent;
}

/// The tones derived from the theme's colors in [context], for the parts of
/// a section that keep their own tone whatever the section's (the brands
/// strip, the call to action, the gallery's captions).
WebsiteSectionTones websiteSectionTones(
  BuildContext context, {
  required Color primary,
  required Color accent,
}) =>
    WebsiteSectionTones.derive(
      primary: websiteSectionRgba(primary),
      accent: websiteSectionRgba(accent),
      background: websiteSectionRgba(Theme.of(context).colorScheme.surface),
    );

/// One section as it is being drawn: its width's sizes, its colors (and the
/// dark ones for a featured part) and the theme's fonts.
class WebsiteSectionScope {
  const WebsiteSectionScope({
    required this.metrics,
    required this.colors,
    required this.inverse,
    required this.contentWidth,
    this.headingFont,
    this.bodyFont,
  });

  final WebsiteSectionMetrics metrics;
  final WebsiteSectionColors colors;

  /// A part drawn on the dark tone inside the section (the featured plan,
  /// the gallery's address): the dark palette, or a lifted one on a dark
  /// section.
  final WebsiteSectionColors inverse;

  /// The width of the section's centered column.
  final double contentWidth;
  final String? headingFont;
  final String? bodyFont;

  bool get isPhone => metrics.isPhone;
  bool get isDesktop => metrics.isDesktop;

  /// A text in the heading font: the design's weight 500 (Oswald draws it at
  /// its regular instance, as the HTML).
  TextStyle heading(double size, {double height = 1.05, Color? color}) =>
      TextStyle(
        fontFamily: headingFont,
        fontSize: size,
        height: height,
        fontWeight: FontWeight.w500,
        color: color ?? colors.ink,
        fontFeatures: const [FontFeature.tabularFigures()],
      );

  /// A text in the body font.
  TextStyle body(
    double size, {
    double height = 1.5,
    FontWeight weight = FontWeight.w400,
    Color? color,
    double? letterSpacing,
  }) =>
      TextStyle(
        fontFamily: bodyFont,
        fontSize: size,
        height: height,
        fontWeight: weight,
        color: color ?? colors.ink,
        letterSpacing: letterSpacing,
      );

  /// Small capitals: an eyebrow, a tag, a label (tracking in em).
  TextStyle caps(
    double size, {
    double tracking = 0.18,
    FontWeight weight = FontWeight.w600,
    Color? color,
  }) =>
      body(
        size,
        height: 1.2,
        weight: weight,
        color: color ?? colors.eyebrow,
        letterSpacing: size * tracking,
      );
}

/// The band a section is drawn in: its tone's background to the edges, the
/// design's padding for the block's width (or the one the operator set) and
/// the centered column [builder] fills.
class WebsiteSectionBand extends StatelessWidget {
  const WebsiteSectionBand({
    super.key,
    required this.tone,
    required this.primaryColor,
    required this.accentColor,
    required this.builder,
    this.headingFont,
    this.bodyFont,
    this.padding,
    this.paintSurface = true,
    this.paddingFor,
    this.maxContentWidth = WebsiteSectionMetrics.contentMaxWidth,
  });

  final WebsiteSectionTone tone;
  final Color primaryColor;
  final Color accentColor;
  final String? headingFont;
  final String? bodyFont;

  /// The padding the operator set; `null` keeps the design's.
  final EdgeInsetsGeometry? padding;

  /// Whether the band paints its tone (not when the operator set a
  /// background of their own).
  final bool paintSurface;

  /// The design's padding at a width, when the section's differs from the
  /// common one (the stats band).
  final EdgeInsets Function(WebsiteSectionMetrics metrics)? paddingFor;
  final double maxContentWidth;
  final Widget Function(BuildContext context, WebsiteSectionScope scope)
      builder;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        final metrics = WebsiteSectionMetrics.of(WebsiteSectionWidth.of(width));
        final colors = WebsiteSectionColors.of(
          context,
          tone: tone,
          primary: primaryColor,
          accent: accentColor,
        );
        final inverse = tone == WebsiteSectionTone.dark
            ? colors.lifted
            : WebsiteSectionColors.of(
                context,
                tone: WebsiteSectionTone.dark,
                primary: primaryColor,
                accent: accentColor,
              );
        final resolved = padding?.resolve(Directionality.of(context)) ??
            paddingFor?.call(metrics) ??
            EdgeInsets.symmetric(
              vertical: metrics.paddingBlock,
              horizontal: metrics.paddingInline,
            );
        final contentWidth =
            (width - resolved.horizontal).clamp(0.0, maxContentWidth);
        final scope = WebsiteSectionScope(
          metrics: metrics,
          colors: colors,
          inverse: inverse,
          contentWidth: contentWidth,
          headingFont: headingFont,
          bodyFont: bodyFont,
        );
        return ColoredBox(
          color: paintSurface ? colors.surface : Colors.transparent,
          child: Padding(
            padding: resolved,
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxContentWidth),
                child: DefaultTextStyle.merge(
                  style: TextStyle(color: colors.ink, fontFamily: bodyFont),
                  child: builder(context, scope),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// A text of a section: the editor's inline slot in Edit, the stored text
/// (through the slot's display transform) otherwise.
Widget websiteSectionSlot(
  BuildContext context,
  WebsiteBlockContentPresenters? presenters,
  WebsiteInlineTextSlot slot, {
  Key? key,
}) {
  final presented = presenters?.text?.call(context, slot);
  final child = presented ??
      Text(
        slot.displayTransform?.call(slot.value) ?? slot.value,
        style: slot.formatting.applyTo(slot.baseStyle),
        textAlign: slot.resolvedTextAlign,
        maxLines: slot.maxLines,
      );
  return key == null ? child : KeyedSubtree(key: key, child: child);
}

/// A block's formatting of one text (`titleFormatting`…).
TextFormatting websiteSectionFormatting(Object? raw) {
  if (raw is! Map) return const TextFormatting();
  return TextFormatting.fromJson(Map<String, dynamic>.from(raw));
}

/// The target of an item of a block's list, for the editor's inline slots.
WebsiteInlineRepeaterTarget websiteSectionTarget(
  Map<String, dynamic> item, {
  required int index,
  required List<String> collectionKeys,
}) {
  final persistedId = item['id'];
  final hasPersistedId =
      persistedId != null && persistedId.toString().trim().isNotEmpty;
  return WebsiteInlineRepeaterTarget(
    collectionKeys: collectionKeys,
    itemIndex: index,
    identityKey: hasPersistedId ? 'id' : null,
    identityValue: hasPersistedId ? persistedId : null,
  );
}

String _upper(String value) => value.toUpperCase();

/// A section's header: the eyebrow, the title in capitals and, beside it
/// (under it on a phone), the note; [ruled] closes it with the heavy line.
/// Nothing when all three are empty.
class WebsiteSectionHeader extends StatelessWidget {
  const WebsiteSectionHeader({
    super.key,
    required this.scope,
    required this.data,
    required this.idPrefix,
    this.presenters,
    this.titleSize,
    this.titleHeight = 1.05,
    this.titleMaxWidth = 760,
    this.noteKey = 'subtitle',
    this.noteAliases = const <String>[],
    this.showNote = true,
    this.ruled = false,
    this.eyebrowGap = 14,
  });

  static ValueKey<String> eyebrowKey(String prefix) =>
      ValueKey<String>('website-$prefix-eyebrow');
  static ValueKey<String> titleKey(String prefix) =>
      ValueKey<String>('website-$prefix-title');
  static ValueKey<String> noteWidgetKey(String prefix) =>
      ValueKey<String>('website-$prefix-note');

  final WebsiteSectionScope scope;
  final Map<String, dynamic> data;
  final String idPrefix;
  final WebsiteBlockContentPresenters? presenters;
  final double? titleSize;
  final double titleHeight;
  final double titleMaxWidth;
  final String noteKey;
  final List<String> noteAliases;
  final bool showNote;
  final bool ruled;
  final double eyebrowGap;

  bool get isEmpty =>
      _text('eyebrow').trim().isEmpty &&
      _text('title').trim().isEmpty &&
      (!showNote || _note.trim().isEmpty);

  String _text(String key) => data[key]?.toString() ?? '';

  String get _note {
    for (final key in [noteKey, ...noteAliases]) {
      if (data.containsKey(key)) return data[key]?.toString() ?? '';
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    if (isEmpty) return const SizedBox.shrink();
    final metrics = scope.metrics;
    final colors = scope.colors;
    final eyebrow = _text('eyebrow').trim();
    final title = _text('title');
    final note = showNote ? _note.trim() : '';
    final titleBlock = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (eyebrow.isNotEmpty) ...[
          WebsiteSectionEyebrow(
            scope: scope,
            text: _text('eyebrow'),
            id: '$idPrefix.eyebrow',
            presenters: presenters,
            key: eyebrowKey(idPrefix),
          ),
          SizedBox(height: metrics.isPhone ? 12 : eyebrowGap),
        ],
        if (title.trim().isNotEmpty)
          websiteSectionSlot(
            context,
            presenters,
            WebsiteInlineTextSlot(
              id: '$idPrefix.title',
              value: title,
              valueKeys: const <String>['title'],
              baseStyle: scope.heading(
                titleSize ?? metrics.titleSize,
                height: titleHeight,
              ),
              formatting: websiteSectionFormatting(data['titleFormatting']),
              formattingKeys: const <String>['titleFormatting'],
              placeholder: 'Título',
              displayTransform: (value) => _upper(value.trim()),
            ),
            key: titleKey(idPrefix),
          ),
      ],
    );
    final noteWidget = note.isEmpty
        ? null
        : websiteSectionSlot(
            context,
            presenters,
            WebsiteInlineTextSlot(
              id: '$idPrefix.$noteKey',
              value: _note,
              valueKeys: [noteKey, ...noteAliases],
              baseStyle: scope.body(metrics.noteSize, color: colors.muted),
              formatting:
                  websiteSectionFormatting(data['${noteKey}Formatting']),
              formattingKeys: ['${noteKey}Formatting'],
              placeholder: 'Nota',
              displayTransform: (value) => value.trim(),
            ),
            key: noteWidgetKey(idPrefix),
          );
    final Widget header = metrics.isPhone
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              titleBlock,
              if (noteWidget != null) ...[
                const SizedBox(height: 14),
                noteWidget,
              ],
            ],
          )
        : Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.end,
            spacing: 32,
            runSpacing: 24,
            children: [
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: titleMaxWidth),
                child: titleBlock,
              ),
              if (noteWidget != null)
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 400),
                  child: noteWidget,
                ),
            ],
          );
    if (!ruled) {
      return SizedBox(width: double.infinity, child: header);
    }
    return Container(
      width: double.infinity,
      padding: EdgeInsets.only(bottom: metrics.isPhone ? 22 : 36),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: colors.strongRule, width: 2),
        ),
      ),
      child: header,
    );
  }
}

/// The small capitals above a section's title.
class WebsiteSectionEyebrow extends StatelessWidget {
  const WebsiteSectionEyebrow({
    super.key,
    required this.scope,
    required this.text,
    required this.id,
    this.presenters,
  });

  final WebsiteSectionScope scope;
  final String text;
  final String id;
  final WebsiteBlockContentPresenters? presenters;

  @override
  Widget build(BuildContext context) {
    return websiteSectionSlot(
      context,
      presenters,
      WebsiteInlineTextSlot(
        id: id,
        value: text,
        valueKeys: const <String>['eyebrow'],
        baseStyle: scope.caps(scope.metrics.eyebrowSize).copyWith(height: 1),
        placeholder: 'Antetítulo',
        displayTransform: (value) => _upper(value.trim()),
      ),
    );
  }
}

/// How a section's button looks: drawn in the ink, filled with the accent,
/// or outlined in white over a photo.
enum WebsiteSectionButtonKind { line, accent, ghost }

/// A section's button: a link a visitor follows, inert in Edit (where the
/// editor's action presenter wraps it), in the design's shape.
class WebsiteSectionButton extends StatelessWidget {
  const WebsiteSectionButton({
    super.key,
    required this.label,
    required this.href,
    required this.kind,
    required this.colors,
    required this.onPressed,
    this.bodyFont,
    this.icon,
    this.minHeight = 48,
    this.horizontalPadding = 24,
    this.expand = false,
  });

  final String label;
  final String href;
  final WebsiteSectionButtonKind kind;
  final WebsiteSectionColors colors;
  final VoidCallback? onPressed;
  final String? bodyFont;
  final IconData? icon;
  final double minHeight;
  final double horizontalPadding;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final (background, foreground, border) = switch (kind) {
      WebsiteSectionButtonKind.line => (
          Colors.transparent,
          colors.ink,
          BorderSide(color: colors.ink, width: 1.5),
        ),
      WebsiteSectionButtonKind.accent => (
          colors.accent,
          colors.onAccent,
          BorderSide.none,
        ),
      WebsiteSectionButtonKind.ghost => (
          Colors.transparent,
          Colors.white,
          BorderSide(color: Colors.white.withValues(alpha: 0.8), width: 1.5),
        ),
    };
    final style = TextStyle(
      fontFamily: bodyFont,
      fontSize: 15,
      height: 1.2,
      fontWeight: kind == WebsiteSectionButtonKind.accent
          ? FontWeight.w700
          : FontWeight.w600,
      letterSpacing: 15 * 0.06,
      color: foreground,
    );
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(6),
      side: border,
    );
    final content = Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 20, color: foreground),
          const SizedBox(width: 10),
        ],
        Flexible(
          child: Text(
            label.toUpperCase(),
            style: style,
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
    final button = Material(
      color: background,
      shape: shape,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        hoverColor: kind == WebsiteSectionButtonKind.accent
            ? Colors.black.withValues(alpha: 0.12)
            : foreground.withValues(alpha: 0.08),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: minHeight),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: horizontalPadding,
              vertical: 10,
            ),
            child: Center(widthFactor: expand ? null : 1, child: content),
          ),
        ),
      ),
    );
    final linked = Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: PublicLinkSemantics(
        href: href,
        enabled: onPressed != null,
        child: button,
      ),
    );
    return expand ? SizedBox(width: double.infinity, child: linked) : linked;
  }
}

/// A section's button through the editor's action presenter in Edit (its
/// label and destination edited where they are), inert there; a visitor's
/// link in Preview and the store.
Widget websiteSectionAction(
  BuildContext context, {
  required WebsiteBlockContentPresenters? presenters,
  required String id,
  required WebsiteActionValue action,
  required List<String> labelKeys,
  required List<String> hrefKeys,
  required WebsiteSectionButtonKind kind,
  required WebsiteSectionColors colors,
  required void Function(String route)? onNavigate,
  List<String> variantKeys = const <String>[],
  WebsiteInlineRepeaterTarget? repeaterTarget,
  String? bodyFont,
  IconData? icon,
  double minHeight = 48,
  double horizontalPadding = 24,
  bool expand = false,
  String? storedHref,
  bool mirrorsPrimary = true,
  String? destinationHelp,
}) {
  final href = action.href.trim();
  final button = WebsiteSectionButton(
    label: action.label,
    href: href,
    kind: kind,
    colors: colors,
    bodyFont: bodyFont,
    icon: icon,
    minHeight: minHeight,
    horizontalPadding: horizontalPadding,
    expand: expand,
    // Edit owns the pointer: a valid button stays enabled-looking through a
    // no-op, as the standalone button.
    onPressed: href.isEmpty
        ? null
        : presenters != null
            ? () {}
            : onNavigate == null
                ? null
                : () => onNavigate(href),
  );
  final presenter = presenters?.action;
  if (presenter == null) return button;
  return presenter(
    context,
    WebsiteInlineActionSlot(
      id: id,
      // Edit changes what is stored: an empty destination stays empty (the
      // button follows the store's WhatsApp or map) when only the label is
      // written.
      action: storedHref == null ? action : action.copyWith(href: storedHref),
      labelKeys: labelKeys,
      hrefKeys: hrefKeys,
      variantKeys: variantKeys,
      actionsKey: mirrorsPrimary ? 'actions' : null,
      destinationHelp: destinationHelp,
      child: button,
      repeaterTarget: repeaterTarget,
    ),
  );
}

/// Loads a photo; widget tests pass one that needs no network.
typedef WebsiteSectionImageProviderBuilder = ImageProvider<Object> Function(
  String url,
);

/// A photo of a section through the editor's media presenter in Edit
/// (replaced where it is), the stored image otherwise, [fallback] without
/// one or when it fails.
Widget websiteSectionMedia(
  BuildContext context, {
  required WebsiteBlockContentPresenters? presenters,
  required String id,
  required String url,
  required List<String> valueKeys,
  required Widget fallback,
  required String semanticLabel,
  Alignment alignment = Alignment.center,
  BorderRadius? borderRadius,
  bool oval = false,
  WebsiteInlineRepeaterTarget? repeaterTarget,
  WebsiteSectionImageProviderBuilder? imageProviderBuilder,
  Key? imageKey,
}) {
  final slot = WebsiteInlineMediaSlot(
    id: id,
    url: url.isEmpty ? null : url,
    valueKeys: valueKeys,
    fit: BoxFit.cover,
    alignment: alignment,
    fallback: fallback,
    borderRadius: oval ? BorderRadius.circular(999) : borderRadius,
    semanticLabel: semanticLabel,
    repeaterTarget: repeaterTarget,
  );
  final presenter = presenters?.media;
  if (presenter != null) return presenter(context, slot);
  if (url.isEmpty) return fallback;
  final image = Image(
    key: imageKey,
    image: imageProviderBuilder?.call(url) ?? NetworkImage(url),
    width: double.infinity,
    height: double.infinity,
    fit: BoxFit.cover,
    alignment: alignment,
    excludeFromSemantics: true,
    errorBuilder: (_, __, ___) => fallback,
  );
  return Semantics(
    container: true,
    image: true,
    label: semanticLabel,
    child: ExcludeSemantics(
      child: oval
          ? ClipOval(child: image)
          : ClipRRect(
              borderRadius: borderRadius ?? BorderRadius.zero,
              child: image,
            ),
    ),
  );
}

/// A photo's framing from the editor's focal point (`focalPointX/Y`, 0–1).
Alignment websiteSectionFocal(Map<String, dynamic> data) {
  double read(Object? raw) {
    final value = raw is num ? raw.toDouble() : double.tryParse('$raw');
    return value != null && value.isFinite ? value.clamp(0.0, 1.0) : 0.5;
  }

  return Alignment(
    read(data['focalPointX']) * 2 - 1,
    read(data['focalPointY']) * 2 - 1,
  );
}
