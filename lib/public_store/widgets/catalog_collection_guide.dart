import 'package:flutter/material.dart';
import 'package:vinabike_public_core/modules/website/models/website_catalog_presentation.dart';

import 'public_link_semantics.dart';

/// One of a category's pages for a measure or a brand, as a link beside the
/// others; the HTML storefront draws the same row (`_LandingLinks`).
class CatalogLandingLinkItem {
  const CatalogLandingLinkItem({
    required this.label,
    required this.href,
    this.current = false,
    this.onTap,
  });

  final String label;
  final String href;
  final bool current;

  /// Null on the canvas, where a tap chooses the section.
  final VoidCallback? onTap;
}

/// «Por aro: Aro 26 · Aro 27.5 · Aro 29 / 700c» under a category's portada.
class CatalogLandingLinks extends StatelessWidget {
  const CatalogLandingLinks({
    super.key,
    required this.label,
    required this.items,
    required this.compact,
  });

  final String label;
  final List<CatalogLandingLinkItem> items;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Material(
      color: Colors.white,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 16 : 28,
          vertical: compact ? 8 : 10,
        ),
        foregroundDecoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1504),
            child: Row(
              children: [
                if (label.isNotEmpty) ...[
                  Text(
                    label.toUpperCase(),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.7,
                      color: Colors.grey.shade700,
                    ),
                  ),
                  SizedBox(width: compact ? 10 : 14),
                ],
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (final item in items)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: PublicLinkSemantics(
                              href: item.href,
                              enabled: !item.current && item.onTap != null,
                              child: _Chip(item: item, primary: primary),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.item, required this.primary});

  final CatalogLandingLinkItem item;
  final Color primary;

  @override
  Widget build(BuildContext context) {
    final current = item.current;
    return Material(
      color: current ? primary : Colors.white,
      shape: StadiumBorder(
        side: BorderSide(color: current ? primary : Colors.grey.shade300),
      ),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: current ? null : item.onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 40),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Center(
              widthFactor: 1,
              child: Text(
                item.label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: current ? Colors.white : const Color(0xFF1E293B),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A category's guide under its products: its title and text, then its
/// questions, each opening to its answer, as the HTML storefront draws it
/// (`_Guide`).
class CatalogCollectionGuideView extends StatelessWidget {
  const CatalogCollectionGuideView({
    super.key,
    required this.guide,
    required this.compact,
    this.onOpenLink,
  });

  final WebsiteCatalogGuide guide;
  final bool compact;

  /// Follows the guide's link; null on the canvas, where a tap chooses the
  /// section.
  final ValueChanged<String>? onOpenLink;

  static const _ink = Color(0xFF1E293B);
  static const _text = Color(0xFF475569);

  @override
  Widget build(BuildContext context) {
    final title = guide.title.trim();
    final questions = guide.shownQuestions;
    final text = <Widget>[
      if (title.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: 18),
          child: Text(
            title,
            style: TextStyle(
              fontSize: compact ? 24 : 30,
              height: 1.15,
              fontWeight: FontWeight.w800,
              color: _ink,
            ),
          ),
        ),
      for (final paragraph in guide.paragraphs)
        Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Text(
            paragraph,
            style: const TextStyle(fontSize: 16, height: 1.65, color: _text),
          ),
        ),
      if (guide.shownLink case final link?)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: PublicLinkSemantics(
            href: link.href,
            enabled: onOpenLink != null,
            child: InkWell(
              onTap: onOpenLink == null ? null : () => onOpenLink!(link.href),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 40),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        link.label,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 18,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
    ];
    final faq = questions.isEmpty
        ? null
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'PREGUNTAS FRECUENTES',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                  color: _ink,
                ),
              ),
              const SizedBox(height: 6),
              for (final question in questions) _Question(question),
            ],
          );
    final hasText = text.isNotEmpty;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFFF4F6F9),
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
      ),
      padding: EdgeInsets.fromLTRB(
        compact ? 16 : 28,
        compact ? 36 : 56,
        compact ? 16 : 28,
        compact ? 44 : 64,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1504),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final columns =
                  hasText && faq != null && constraints.maxWidth >= 980;
              if (columns) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 11,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: text,
                      ),
                    ),
                    const SizedBox(width: 64),
                    Expanded(flex: 10, child: faq),
                  ],
                );
              }
              return ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 820),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ...text,
                    if (hasText && faq != null) const SizedBox(height: 22),
                    if (faq != null) faq,
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _Question extends StatefulWidget {
  const _Question(this.question);

  final WebsiteCatalogQuestion question;

  @override
  State<_Question> createState() => _QuestionState();
}

class _QuestionState extends State<_Question> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return DecoratedBox(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            button: true,
            expanded: _open,
            child: InkWell(
              onTap: () => setState(() => _open = !_open),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 56),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          widget.question.question,
                          style: const TextStyle(
                            fontSize: 16,
                            height: 1.4,
                            fontWeight: FontWeight.w600,
                            color: CatalogCollectionGuideView._ink,
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      AnimatedRotation(
                        turns: _open ? 0.125 : 0,
                        duration: const Duration(milliseconds: 200),
                        child: Icon(Icons.add, size: 20, color: primary),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (_open)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text(
                widget.question.answer,
                style: const TextStyle(
                  fontSize: 15,
                  height: 1.6,
                  color: CatalogCollectionGuideView._text,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
