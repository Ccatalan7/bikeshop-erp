import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:vinabike_public_core/modules/website/models/website_block_type.dart';
import 'package:vinabike_public_core/modules/website/models/website_section_content.dart';
import 'package:vinabike_public_core/modules/website/theme/website_section_palette.dart';
import 'package:vinabike_public_core/public_store/models/public_policy_content.dart';

import 'website_block_content_presenters.dart';
import 'website_section_frame.dart';

/// Shared visitor content for a Website Builder FAQ block: the eyebrow, the
/// title, the note and the invitation to write (the store's WhatsApp and
/// e-mail) on one side, the questions on the other under the heavy rule;
/// one column under 1024. Each question opens to its answer with the plus
/// turning into a cross; the first one starts open. The HTML storefront
/// draws the same (`FaqSectionView`).
///
/// Editor presenters replace only persisted text leaves; collection controls
/// remain in the inspector and never alter visitor geometry.
class WebsiteFaqBlockContent extends StatelessWidget {
  const WebsiteFaqBlockContent({
    super.key,
    required this.data,
    required this.primaryColor,
    required this.accentColor,
    this.siteContact = const PublicWebsiteContactFacts(),
    this.headingFont,
    this.bodyFont,
    this.presenters,
    this.onNavigate,
    this.padding,
    this.paintSurface = true,
  });

  static const rootKey = ValueKey<String>('website-faq-root');
  static const sideKey = ValueKey<String>('website-faq-side');
  static const contactKey = ValueKey<String>('website-faq-contact');
  static const collectionKey = ValueKey<String>('website-faq-collection');

  static ValueKey<String> itemKey(int index) =>
      ValueKey<String>('website-faq-item-$index');

  static ValueKey<String> questionKey(int index) =>
      ValueKey<String>('website-faq-item-$index-question');

  static ValueKey<String> answerKey(int index) =>
      ValueKey<String>('website-faq-item-$index-answer');

  final Map<String, dynamic> data;
  final Color primaryColor;
  final Color accentColor;

  /// The store's contact (Configuración → Contacto) for the invitation.
  final PublicWebsiteContactFacts siteContact;
  final String? headingFont;
  final String? bodyFont;
  final WebsiteBlockContentPresenters? presenters;
  final void Function(String route)? onNavigate;

  /// The padding the operator set; `null` keeps the design's.
  final EdgeInsetsGeometry? padding;
  final bool paintSurface;

  @override
  Widget build(BuildContext context) {
    final items = websiteSectionItems(data, 'items');
    return KeyedSubtree(
      key: rootKey,
      child: WebsiteSectionBand(
        tone: WebsiteSectionTone.of(WebsiteBlockType.faq, data),
        primaryColor: primaryColor,
        accentColor: accentColor,
        headingFont: headingFont,
        bodyFont: bodyFont,
        padding: padding,
        paintSurface: paintSurface,
        builder: (context, scope) {
          final side = _side(context, scope);
          final list = items.isEmpty
              ? null
              : Container(
                  key: collectionKey,
                  decoration: BoxDecoration(
                    border: Border(
                      top: BorderSide(color: scope.colors.strongRule, width: 2),
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final (position, (index, item)) in items.indexed)
                        _FaqItem(
                          key: itemKey(index),
                          item: item,
                          index: index,
                          initiallyOpen: position == 0,
                          scope: scope,
                          presenters: presenters,
                        ),
                    ],
                  ),
                );
          if (scope.isDesktop) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: 360, child: side),
                const SizedBox(width: 72),
                Expanded(child: list ?? const SizedBox.shrink()),
              ],
            );
          }
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              side,
              if (list != null) ...[const SizedBox(height: 24), list],
            ],
          );
        },
      ),
    );
  }

  Widget _side(BuildContext context, WebsiteSectionScope scope) {
    final eyebrow = websiteSectionText(data, const ['eyebrow']);
    final title = websiteSectionText(data, const ['title']);
    final subtitle = websiteSectionText(data, const ['subtitle']);
    final noteSize = scope.isPhone ? 16.0 : 17.0;
    final noteStyle = scope.body(
      noteSize,
      height: 1.55,
      color: scope.colors.muted,
    );
    final contact = data['showContact'] == false ? null : _contact(scope);
    return Column(
      key: sideKey,
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (eyebrow.trim().isNotEmpty) ...[
          WebsiteSectionEyebrow(
            scope: scope,
            text: eyebrow,
            id: 'faq.eyebrow',
            presenters: presenters,
          ),
          SizedBox(height: scope.isPhone ? 12 : 14),
        ],
        if (title.trim().isNotEmpty)
          websiteSectionSlot(
            context,
            presenters,
            WebsiteInlineTextSlot(
              id: 'faq.title',
              value: title,
              valueKeys: const <String>['title'],
              baseStyle: scope.heading(scope.metrics.titleSize),
              formatting: websiteSectionFormatting(data['titleFormatting']),
              formattingKeys: const <String>['titleFormatting'],
              placeholder: 'Título',
              displayTransform: (value) => value.trim().toUpperCase(),
            ),
          ),
        if (subtitle.trim().isNotEmpty) ...[
          const SizedBox(height: 22),
          websiteSectionSlot(
            context,
            presenters,
            WebsiteInlineTextSlot(
              id: 'faq.subtitle',
              value: subtitle,
              valueKeys: const <String>['subtitle'],
              baseStyle: noteStyle,
              formatting: websiteSectionFormatting(
                data['subtitleFormatting'],
              ),
              formattingKeys: const <String>['subtitleFormatting'],
              placeholder: 'Subtítulo',
              displayTransform: (value) => value.trim(),
            ),
          ),
        ],
        if (contact != null) ...[const SizedBox(height: 22), contact],
      ],
    );
  }

  /// «¿Otra duda? Escríbenos al … o a ….» with the store's WhatsApp (or
  /// phone) and e-mail; nothing when it has neither.
  Widget? _contact(WebsiteSectionScope scope) {
    final phone = siteContact.whatsapp.trim().isNotEmpty
        ? siteContact.whatsapp.trim()
        : siteContact.phone.trim();
    final phoneHref = siteContact.whatsappHref.isNotEmpty
        ? siteContact.whatsappHref
        : 'tel:${phone.replaceAll(RegExp(r'[^\d+]'), '')}';
    final email = siteContact.email.trim();
    if (phone.isEmpty && email.isEmpty) return null;
    return _ContactLine(
      key: contactKey,
      phone: phone,
      phoneHref: phoneHref,
      email: email,
      style: scope.body(
        scope.isPhone ? 16 : 17,
        height: 1.55,
        color: scope.colors.muted,
      ),
      linkStyle: TextStyle(
        fontWeight: FontWeight.w600,
        color: scope.colors.mark,
        decoration: TextDecoration.underline,
        decorationColor: scope.colors.mark,
      ),
      onNavigate: presenters == null ? onNavigate : null,
    );
  }
}

class _ContactLine extends StatefulWidget {
  const _ContactLine({
    super.key,
    required this.phone,
    required this.phoneHref,
    required this.email,
    required this.style,
    required this.linkStyle,
    required this.onNavigate,
  });

  final String phone;
  final String phoneHref;
  final String email;
  final TextStyle style;
  final TextStyle linkStyle;
  final void Function(String route)? onNavigate;

  @override
  State<_ContactLine> createState() => _ContactLineState();
}

class _ContactLineState extends State<_ContactLine> {
  final _phone = TapGestureRecognizer();
  final _email = TapGestureRecognizer();

  @override
  void dispose() {
    _phone.dispose();
    _email.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final navigate = widget.onNavigate;
    _phone.onTap = navigate == null ? null : () => navigate(widget.phoneHref);
    _email.onTap =
        navigate == null ? null : () => navigate('mailto:${widget.email}');
    return Text.rich(
      TextSpan(
        style: widget.style,
        children: [
          const TextSpan(text: '¿Otra duda? Escríbenos '),
          if (widget.phone.isNotEmpty) ...[
            const TextSpan(text: 'al '),
            TextSpan(
              text: widget.phone,
              style: widget.linkStyle,
              recognizer: _phone,
            ),
          ],
          if (widget.phone.isNotEmpty && widget.email.isNotEmpty)
            const TextSpan(text: ' o '),
          if (widget.email.isNotEmpty) ...[
            const TextSpan(text: 'a '),
            TextSpan(
              text: widget.email,
              style: widget.linkStyle,
              recognizer: _email,
            ),
          ],
          const TextSpan(text: '.'),
        ],
      ),
    );
  }
}

class _FaqItem extends StatefulWidget {
  const _FaqItem({
    super.key,
    required this.item,
    required this.index,
    required this.initiallyOpen,
    required this.scope,
    required this.presenters,
  });

  final Map<String, dynamic> item;
  final int index;
  final bool initiallyOpen;
  final WebsiteSectionScope scope;
  final WebsiteBlockContentPresenters? presenters;

  @override
  State<_FaqItem> createState() => _FaqItemState();
}

class _FaqItemState extends State<_FaqItem> {
  late bool _open = widget.initiallyOpen;

  @override
  Widget build(BuildContext context) {
    final scope = widget.scope;
    final phone = scope.isPhone;
    final index = widget.index;
    final item = widget.item;
    final target = websiteSectionTarget(
      item,
      index: index,
      collectionKeys: const ['items'],
    );
    final question = websiteSectionText(item, const ['question']);
    final answer = websiteSectionText(item, const ['answer']);
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final duration =
        reduceMotion ? Duration.zero : const Duration(milliseconds: 200);
    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: scope.colors.rule)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            button: true,
            expanded: _open,
            child: InkWell(
              onTap: () => setState(() => _open = !_open),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: phone ? 64 : 76),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: websiteSectionSlot(
                          context,
                          widget.presenters,
                          WebsiteInlineTextSlot(
                            id: 'faq.item.$index.question',
                            value: question,
                            valueKeys: const <String>['question'],
                            baseStyle: scope.body(
                              phone ? 17 : 20,
                              height: 1.35,
                              weight: FontWeight.w600,
                            ),
                            formatting: websiteSectionFormatting(
                              item['questionFormatting'],
                            ),
                            formattingKeys: const <String>[
                              'questionFormatting',
                            ],
                            placeholder: 'Pregunta',
                            repeaterTarget: target,
                          ),
                          key: WebsiteFaqBlockContent.questionKey(index),
                        ),
                      ),
                      SizedBox(width: phone ? 16 : 24),
                      AnimatedRotation(
                        turns: _open ? 0.125 : 0,
                        duration: duration,
                        child: Icon(
                          Icons.add,
                          size: phone ? 20 : 22,
                          color: scope.colors.mark,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          AnimatedSize(
            duration: duration,
            alignment: Alignment.topCenter,
            child: _open
                ? Padding(
                    padding: EdgeInsets.fromLTRB(
                      0,
                      0,
                      phone ? 28 : 56,
                      phone ? 20 : 26,
                    ),
                    child: websiteSectionSlot(
                      context,
                      widget.presenters,
                      WebsiteInlineTextSlot(
                        id: 'faq.item.$index.answer',
                        value: answer,
                        valueKeys: const <String>['answer'],
                        baseStyle: scope.body(
                          phone ? 16 : 17,
                          height: 1.55,
                          color: scope.colors.soft,
                        ),
                        formatting: websiteSectionFormatting(
                          item['answerFormatting'],
                        ),
                        formattingKeys: const <String>['answerFormatting'],
                        placeholder: 'Respuesta',
                        repeaterTarget: target,
                      ),
                      key: WebsiteFaqBlockContent.answerKey(index),
                    ),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}
