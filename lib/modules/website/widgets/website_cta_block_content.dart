import 'package:flutter/material.dart';
import 'package:vinabike_public_core/modules/website/models/website_section_content.dart';
import 'package:vinabike_public_core/modules/website/theme/website_section_palette.dart';
import 'package:vinabike_public_core/public_store/models/public_policy_content.dart';

import '../models/website_action.dart';
import '../models/website_block_surface_style.dart';
import 'text_formatting_toolbar.dart';
import 'website_block_content_presenters.dart';
import 'website_section_frame.dart';

typedef WebsiteCtaImageProviderBuilder = WebsiteSectionImageProviderBuilder;

/// Pure shared content tree for the Website Builder CTA block, the close of a
/// page: the title in capitals and the text over the photo (with its veil,
/// the brand's deepest tone unless the block chose a color) or over the dark
/// tone, the two buttons (an empty main one opens the store's WhatsApp, an
/// empty second one its map: `websiteCtaActions`) and, beside them, how to
/// reach the store from Configuración → Contacto. The HTML storefront draws
/// the same (`CtaSectionView`).
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
    this.siteContact = const PublicWebsiteContactFacts(),
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

  /// The store's contact (Configuración → Contacto): the WhatsApp an empty
  /// main button opens, the map of the second one and the contacts beside.
  final PublicWebsiteContactFacts siteContact;
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
  static const titleKey = ValueKey<String>('website-cta-title');
  static const subtitleKey = ValueKey<String>('website-cta-subtitle');
  static const actionKey = ValueKey<String>('website-cta-action');
  static const secondaryActionKey =
      ValueKey<String>('website-cta-secondary-action');
  static const contactsKey = ValueKey<String>('website-cta-contacts');

  @override
  Widget build(BuildContext context) {
    final tones = websiteSectionTones(
      context,
      primary: primaryColor,
      accent: accentColor,
    );
    final colors = WebsiteSectionColors.of(
      context,
      tone: WebsiteSectionTone.dark,
      primary: primaryColor,
      accent: accentColor,
    );
    final image = websiteSectionText(data, const [
      'backgroundImage',
      'imageUrl',
    ]).trim();
    final blockHeight = _positive(data['blockHeight']);
    final opacity = (_finite(data['overlayOpacity']) ?? 0.8).clamp(0.0, 1.0);
    final veil =
        _parseColor(data['overlayColor']) ?? websiteSectionColor(tones.deeper);
    final backdrop = websiteSectionColor(tones.deep);
    final fallback = ColoredBox(key: backgroundKey, color: backdrop);
    final background = websiteSectionMedia(
      context,
      presenters: presenters,
      id: 'cta.background',
      url: image,
      valueKeys: const <String>['backgroundImage', 'imageUrl'],
      fallback: fallback,
      semanticLabel: websiteSectionText(data, const [
        'backgroundImageAltText',
        'imageAltText',
      ]).trim(),
      alignment: websiteSectionFocal(data),
      imageProviderBuilder: imageProviderBuilder,
    );
    return SizedBox(
      key: rootKey,
      width: double.infinity,
      height: blockHeight,
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          Positioned.fill(child: ColoredBox(color: backdrop)),
          Positioned.fill(child: background),
          if (image.isNotEmpty && opacity > 0)
            Positioned.fill(
              child: IgnorePointer(
                child: ColoredBox(
                  key: overlayKey,
                  color: veil.withValues(alpha: opacity),
                ),
              ),
            ),
          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.hasBoundedWidth
                  ? constraints.maxWidth
                  : MediaQuery.sizeOf(context).width;
              final band = WebsiteSectionWidth.of(width);
              final design = switch (band) {
                WebsiteSectionWidth.desktop =>
                  const EdgeInsets.symmetric(vertical: 120, horizontal: 32),
                WebsiteSectionWidth.tablet =>
                  const EdgeInsets.symmetric(vertical: 96, horizontal: 32),
                WebsiteSectionWidth.phone =>
                  const EdgeInsets.fromLTRB(20, 72, 20, 64),
              };
              var padding = surfaceStyle.hasAuthoredPadding
                  ? surfaceStyle.paddingWithFallback(design)
                  : design;
              if (blockHeight != null && !surfaceStyle.hasAuthoredPadding) {
                padding = EdgeInsets.symmetric(horizontal: padding.left);
              }
              return Padding(
                key: paddingKey,
                padding: padding,
                child: Align(
                  alignment: blockHeight == null
                      ? Alignment.topCenter
                      : Alignment.center,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1136),
                    child: _content(context, band, colors),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _content(
    BuildContext context,
    WebsiteSectionWidth band,
    WebsiteSectionColors colors,
  ) {
    final phone = band == WebsiteSectionWidth.phone;
    final desktop = band == WebsiteSectionWidth.desktop;
    final title = websiteSectionText(data, const ['title']);
    final subtitle = websiteSectionText(data, const [
      'subtitle',
      'description',
    ]);
    final actions = websiteCtaActions(
      data,
      whatsappHref: siteContact.whatsappHref,
      mapsUrl: siteContact.mapsUrl,
    );
    // The main button is the accent unless the operator chose an outline
    // (or text) look for it in the editor.
    final primaryVariant = WebsiteActionVariant.fromStorage(
      data['actionVariant']?.toString(),
      fallback: WebsiteActionVariant.filled,
    );
    bool visible(WebsiteSectionAction? action) =>
        action != null &&
        (presenters != null ||
            (isNavigationEligible?.call(action.href) ?? true));
    final buttons = <Widget>[
      if (visible(actions.primary))
        KeyedSubtree(
          key: actionKey,
          child: _button(
            context,
            actions.primary!,
            colors,
            id: 'cta.action',
            fields: WebsiteButtonFields.cta,
            variant: primaryVariant,
            kind: primaryVariant == WebsiteActionVariant.filled
                ? WebsiteSectionButtonKind.accent
                : WebsiteSectionButtonKind.ghost,
            expand: phone,
            destinationHelp: 'Vacío, abre el WhatsApp de la tienda.',
          ),
        ),
      if (visible(actions.secondary))
        KeyedSubtree(
          key: secondaryActionKey,
          child: _button(
            context,
            actions.secondary!,
            colors,
            id: 'cta.secondary',
            fields: WebsiteButtonFields.ctaSecondary,
            variant: WebsiteActionVariant.outline,
            kind: WebsiteSectionButtonKind.ghost,
            expand: phone,
            destinationHelp: 'Vacío, abre el mapa del negocio.',
          ),
        ),
    ];
    final main = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        websiteSectionSlot(
          context,
          presenters,
          WebsiteInlineTextSlot(
            id: 'cta.title',
            value: title,
            valueKeys: const <String>['title'],
            baseStyle: TextStyle(
              fontFamily: headingFont,
              fontSize: switch (band) {
                WebsiteSectionWidth.desktop => 72,
                WebsiteSectionWidth.tablet => 56,
                WebsiteSectionWidth.phone => 46,
              },
              height: 1,
              fontWeight: FontWeight.w500,
              color: Colors.white,
            ),
            formatting: _formatting(data['titleFormatting']),
            formattingKeys: const <String>['titleFormatting'],
            placeholder: 'Llamado a la acción',
            displayTransform: (value) =>
                (value.trim().isEmpty ? '¿Necesitas ayuda?' : value.trim())
                    .toUpperCase(),
          ),
          key: titleKey,
        ),
        if (subtitle.trim().isNotEmpty) ...[
          SizedBox(height: phone ? 18 : 24),
          Align(
            alignment: Alignment.centerLeft,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: websiteSectionSlot(
                context,
                presenters,
                WebsiteInlineTextSlot(
                  id: 'cta.subtitle',
                  value: subtitle,
                  valueKeys: const <String>['subtitle', 'description'],
                  baseStyle: TextStyle(
                    fontFamily: bodyFont,
                    fontSize: phone ? 17 : 19,
                    height: 1.5,
                    color: Colors.white.withValues(alpha: 0.8),
                  ),
                  formatting: _formatting(
                    data['subtitleFormatting'] ?? data['descriptionFormatting'],
                  ),
                  formattingKeys: const <String>[
                    'subtitleFormatting',
                    'descriptionFormatting',
                  ],
                  placeholder: 'Descripción',
                  displayTransform: (value) => value.trim(),
                ),
                key: subtitleKey,
              ),
            ),
          ),
        ],
        if (buttons.isNotEmpty) ...[
          SizedBox(height: phone ? 28 : 36),
          if (phone)
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (position, button) in buttons.indexed) ...[
                  if (position > 0) const SizedBox(height: 12),
                  button,
                ],
              ],
            )
          else
            Wrap(spacing: 14, runSpacing: 14, children: buttons),
        ],
      ],
    );
    final contacts = data['showContact'] == false
        ? const <(String, String)>[]
        : [
            if (siteContact.whatsapp.trim().isNotEmpty)
              ('WhatsApp', siteContact.whatsapp.trim())
            else if (siteContact.phone.trim().isNotEmpty)
              ('Teléfono', siteContact.phone.trim()),
            if (siteContact.email.trim().isNotEmpty)
              ('Correo', siteContact.email.trim()),
            if (siteContact.address.trim().isNotEmpty)
              ('Dirección', siteContact.address.trim()),
          ];
    if (contacts.isEmpty) return main;
    final rule = BorderSide(color: Colors.white.withValues(alpha: 0.24));
    if (phone) {
      final lines = [
        contacts
            .where((entry) => entry.$1 != 'Dirección')
            .map((entry) => entry.$2)
            .join(' · '),
        ...contacts
            .where((entry) => entry.$1 == 'Dirección')
            .map((entry) => entry.$2),
      ].where((line) => line.isNotEmpty);
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          main,
          const SizedBox(height: 28),
          Container(
            key: contactsKey,
            padding: const EdgeInsets.only(top: 20),
            decoration: BoxDecoration(border: Border(top: rule)),
            child: Text(
              lines.join('\n'),
              style: TextStyle(
                fontFamily: bodyFont,
                fontSize: 15,
                height: 1.6,
                color: Colors.white.withValues(alpha: 0.8),
              ),
            ),
          ),
        ],
      );
    }
    Widget entry((String, String) contact) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              contact.$1.toUpperCase(),
              style: TextStyle(
                fontFamily: bodyFont,
                fontSize: 12,
                height: 1.4,
                fontWeight: FontWeight.w600,
                letterSpacing: 12 * 0.16,
                color: Colors.white.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              contact.$2,
              style: TextStyle(
                fontFamily: bodyFont,
                fontSize: 18,
                height: 1.4,
                color: Colors.white,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        );
    final list = Container(
      key: contactsKey,
      padding: const EdgeInsets.only(top: 24),
      decoration: BoxDecoration(border: Border(top: rule)),
      child: desktop
          ? Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (position, contact) in contacts.indexed) ...[
                  if (position > 0) const SizedBox(height: 18),
                  entry(contact),
                ],
              ],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final (position, contact) in contacts.indexed) ...[
                  if (position > 0) const SizedBox(width: 24),
                  Expanded(child: entry(contact)),
                ],
                for (var rest = contacts.length; rest < 3; rest++) ...[
                  const SizedBox(width: 24),
                  const Expanded(child: SizedBox.shrink()),
                ],
              ],
            ),
    );
    if (desktop) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(child: main),
          const SizedBox(width: 48),
          SizedBox(width: 340, child: list),
        ],
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [main, const SizedBox(height: 40), list],
    );
  }

  Widget _button(
    BuildContext context,
    WebsiteSectionAction action,
    WebsiteSectionColors colors, {
    required String id,
    required WebsiteButtonFields fields,
    required WebsiteActionVariant variant,
    required WebsiteSectionButtonKind kind,
    required bool expand,
    String? destinationHelp,
  }) {
    return websiteSectionAction(
      context,
      presenters: presenters,
      id: id,
      action: WebsiteActionValue(
        label: action.label,
        href: action.href,
        variant: variant,
      ),
      fields: fields,
      kind: kind,
      colors: colors,
      onNavigate: onNavigate,
      bodyFont: bodyFont,
      icon: action.whatsapp ? Icons.chat_bubble_outline_rounded : null,
      minHeight: 52,
      horizontalPadding: 26,
      expand: expand,
      storedHref: websiteSectionText(data, fields.href),
      destinationHelp: destinationHelp,
    );
  }

  static TextFormatting _formatting(Object? raw) =>
      websiteSectionFormatting(raw);

  static double? _finite(Object? raw) {
    final value = switch (raw) {
      num number => number.toDouble(),
      String text => double.tryParse(text.trim()),
      _ => null,
    };
    return value != null && value.isFinite ? value : null;
  }

  static double? _positive(Object? raw) {
    final value = _finite(raw);
    return value != null && value > 0 ? value : null;
  }

  /// `#RRGGBB` or `#AARRGGBB`; anything else (empty included) is the
  /// brand's deepest tone.
  static Color? _parseColor(Object? raw) {
    var hex = (raw?.toString() ?? '').trim().replaceFirst('#', '');
    if (hex.length == 6) hex = 'FF$hex';
    if (hex.length != 8) return null;
    final value = int.tryParse(hex, radix: 16);
    return value == null ? null : Color(value);
  }
}
