import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../modules/website/models/website_catalog_presentation.dart';
import 'public_link_semantics.dart';

class CatalogCollectionNavigationItem {
  const CatalogCollectionNavigationItem({
    required this.id,
    required this.label,
    this.selected = false,
    this.onTap,
    this.href,
  });

  final String id;
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  /// Ruta pública de la colección, para exponerla como enlace a los
  /// rastreadores. Nula en Edit y en superficies que no navegan.
  final String? href;
}

/// The portada's own texts, each written on the page in the editor.
enum CatalogCollectionField { eyebrow, title, description }

/// Builds one portada text where the page shows it, in the page's style and
/// within the page's own line limit ([maxLines]), so the portada keeps the
/// same height in Edit as on the site.
typedef CatalogCollectionTextBuilder = Widget Function(
  CatalogCollectionField field, {
  required String text,
  required TextStyle style,
  required TextAlign textAlign,
  required String placeholder,
  required bool uppercase,
  int? maxLines,
});

/// What the editor adds to the portada: texts written in place. Null on the
/// public site and in Preview, where the portada is drawn as is.
class CatalogCollectionEditing {
  const CatalogCollectionEditing({
    required this.text,
    required this.showsEmpty,
    required this.fallbackTitle,
    required this.fallbackDescription,
  });

  final CatalogCollectionTextBuilder text;

  /// An optional text that is empty is offered only while its section is
  /// selected, so the page is not drawn with holes.
  final bool Function(CatalogCollectionField field) showsEmpty;

  /// The category's own name and description, shown while the portada's
  /// texts are empty.
  final String fallbackTitle;
  final String fallbackDescription;
}

/// Shared category/collection presentation used by public, Edit and Preview.
///
/// This widget owns only presentation. Category hierarchy, labels, visibility
/// and callbacks are supplied by the canonical catalog consumer.
class CatalogCollectionPresentationHeader extends StatelessWidget {
  const CatalogCollectionPresentationHeader({
    super.key,
    required this.presentation,
    required this.title,
    required this.description,
    required this.imageUrl,
    required this.breadcrumbs,
    required this.subcategories,
    required this.compact,
    this.editing,
  });

  final WebsiteCatalogPresentation presentation;
  final String title;
  final String description;
  final String imageUrl;
  final List<CatalogCollectionNavigationItem> breadcrumbs;
  final List<CatalogCollectionNavigationItem> subcategories;
  final bool compact;
  final CatalogCollectionEditing? editing;

  @override
  Widget build(BuildContext context) {
    final reducedHeroHeight = presentation.heroSize.desktopHeight * 0.5;
    final heroHeight =
        compact ? math.min(180.0, reducedHeroHeight * 0.72) : reducedHeroHeight;
    final centered =
        presentation.heroAlignment == WebsiteCatalogHeroAlignment.center;
    final textAlign = centered ? TextAlign.center : TextAlign.left;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: heroHeight,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (imageUrl.isNotEmpty)
                Image.network(
                  imageUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const ColoredBox(
                    color: Color(0xFF132638),
                  ),
                )
              else
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFF0C2234), Color(0xFF315266)],
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                    ),
                  ),
                ),
              ColoredBox(
                color: Colors.black.withValues(alpha: presentation.heroOverlay),
              ),
              Align(
                alignment: centered ? Alignment.center : Alignment.centerLeft,
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1504),
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: compact ? 22 : 56,
                        vertical: compact ? 16 : 24,
                      ),
                      child: Align(
                        alignment:
                            centered ? Alignment.center : Alignment.centerLeft,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 720),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: centered
                                ? CrossAxisAlignment.center
                                : CrossAxisAlignment.start,
                            children: [
                              if (presentation.heroEyebrow.isNotEmpty ||
                                  (editing?.showsEmpty(
                                        CatalogCollectionField.eyebrow,
                                      ) ??
                                      false)) ...[
                                _text(
                                  CatalogCollectionField.eyebrow,
                                  shown: presentation.heroEyebrow,
                                  own: presentation.heroEyebrow,
                                  placeholder: 'Etiqueta sobre el título',
                                  textAlign: textAlign,
                                  uppercase: true,
                                  style: _eyebrowStyle,
                                ),
                                const SizedBox(height: 12),
                              ],
                              _text(
                                CatalogCollectionField.title,
                                shown: title,
                                own: presentation.heroTitle,
                                placeholder: editing?.fallbackTitle ?? title,
                                textAlign: textAlign,
                                uppercase: true,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: compact ? 32 : 48,
                                  height: 0.98,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0.8,
                                ),
                              ),
                              if (description.isNotEmpty ||
                                  (editing?.showsEmpty(
                                        CatalogCollectionField.description,
                                      ) ??
                                      false)) ...[
                                const SizedBox(height: 16),
                                _text(
                                  CatalogCollectionField.description,
                                  shown: description,
                                  own: presentation.heroDescription,
                                  placeholder: editing?.fallbackDescription
                                              .trim()
                                              .isNotEmpty ==
                                          true
                                      ? editing!.fallbackDescription
                                      : 'Texto bajo el título',
                                  textAlign: textAlign,
                                  uppercase: false,
                                  maxLines: compact ? 3 : 4,
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.92),
                                    fontSize: compact ? 14 : 16,
                                    height: 1.5,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (presentation.showBreadcrumbs && breadcrumbs.isNotEmpty)
          _CatalogCollectionBreadcrumbs(
            compact: compact,
            items: breadcrumbs,
          ),
        if (presentation.showSubcategories && subcategories.isNotEmpty)
          _CatalogCollectionSubcategories(
            compact: compact,
            items: subcategories,
          ),
      ],
    );
  }

  static const TextStyle _eyebrowStyle = TextStyle(
    color: Colors.white,
    fontSize: 11,
    fontWeight: FontWeight.w800,
    letterSpacing: 1.8,
  );

  /// A portada text: as the page shows it, or — in the editor — written in
  /// place. The editor is handed what the customer sees ([shown]: the
  /// category's name while the portada has no title of its own), so the
  /// canvas never draws a placeholder where the site draws a title; writing
  /// over it gives the portada its own, and emptying it goes back to the
  /// category's. [own] is the presentation's value, for the optional label.
  Widget _text(
    CatalogCollectionField field, {
    required String shown,
    required String own,
    required String placeholder,
    required TextAlign textAlign,
    required bool uppercase,
    required TextStyle style,
    int? maxLines,
  }) {
    final editing = this.editing;
    if (editing == null) {
      return Text(
        uppercase ? shown.toUpperCase() : shown,
        textAlign: textAlign,
        maxLines: maxLines,
        overflow: maxLines == null ? null : TextOverflow.ellipsis,
        style: style,
      );
    }
    return editing.text(
      field,
      text: field == CatalogCollectionField.eyebrow ? own : shown,
      style: style,
      textAlign: textAlign,
      placeholder: placeholder,
      uppercase: uppercase,
      maxLines: maxLines,
    );
  }
}

class _CatalogCollectionBreadcrumbs extends StatelessWidget {
  const _CatalogCollectionBreadcrumbs({
    required this.compact,
    required this.items,
  });

  final bool compact;
  final List<CatalogCollectionNavigationItem> items;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          compact ? 16 : 28,
          compact ? 13 : 17,
          compact ? 16 : 28,
          compact ? 11 : 15,
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1504),
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 7,
              runSpacing: 5,
              children: [
                for (var index = 0; index < items.length; index++) ...[
                  if (index > 0)
                    Text(
                      '/',
                      style: TextStyle(
                        color: Colors.grey.shade400,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  _CatalogCollectionNavigationLink(item: items[index]),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CatalogCollectionSubcategories extends StatelessWidget {
  const _CatalogCollectionSubcategories({
    required this.compact,
    required this.items,
  });

  final bool compact;
  final List<CatalogCollectionNavigationItem> items;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 16 : 28,
          vertical: compact ? 10 : 13,
        ),
        foregroundDecoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: Colors.grey.shade200),
            bottom: BorderSide(color: Colors.grey.shade200),
          ),
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1504),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: items
                    .map(
                      (item) => Padding(
                        padding: const EdgeInsets.only(right: 22),
                        child: TextButton(
                          onPressed: item.onTap,
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.black87,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 0,
                              vertical: 8,
                            ),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: Text(
                            item.label.toUpperCase(),
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.7,
                            ),
                          ),
                        ),
                      ),
                    )
                    .toList(growable: false),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CatalogCollectionNavigationLink extends StatelessWidget {
  const _CatalogCollectionNavigationLink({required this.item});

  final CatalogCollectionNavigationItem item;

  @override
  Widget build(BuildContext context) {
    final color = item.selected ? Colors.black87 : Colors.grey.shade600;
    return PublicLinkSemantics(
      href: item.href,
      enabled: !item.selected && item.onTap != null,
      child: InkWell(
        onTap: item.selected ? null : item.onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Text(
            item.label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: item.selected ? FontWeight.w800 : FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
