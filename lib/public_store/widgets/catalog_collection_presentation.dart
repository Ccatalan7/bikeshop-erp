import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../modules/website/models/website_catalog_presentation.dart';

class CatalogCollectionNavigationItem {
  const CatalogCollectionNavigationItem({
    required this.id,
    required this.label,
    this.selected = false,
    this.onTap,
  });

  final String id;
  final String label;
  final bool selected;
  final VoidCallback? onTap;
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
  });

  final WebsiteCatalogPresentation presentation;
  final String title;
  final String description;
  final String imageUrl;
  final List<CatalogCollectionNavigationItem> breadcrumbs;
  final List<CatalogCollectionNavigationItem> subcategories;
  final bool compact;

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
                              if (presentation.heroEyebrow.isNotEmpty) ...[
                                Text(
                                  presentation.heroEyebrow.toUpperCase(),
                                  textAlign: textAlign,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 1.8,
                                  ),
                                ),
                                const SizedBox(height: 12),
                              ],
                              Text(
                                title.toUpperCase(),
                                textAlign: textAlign,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: compact ? 32 : 48,
                                  height: 0.98,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0.8,
                                ),
                              ),
                              if (description.isNotEmpty) ...[
                                const SizedBox(height: 16),
                                Text(
                                  description,
                                  textAlign: textAlign,
                                  maxLines: compact ? 3 : 4,
                                  overflow: TextOverflow.ellipsis,
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
    return InkWell(
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
    );
  }
}
