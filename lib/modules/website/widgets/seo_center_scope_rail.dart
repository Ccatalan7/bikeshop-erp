import 'package:flutter/material.dart';

/// The four ownership scopes of the SEO center.
///
/// Each scope maps to exactly one canonical owner elsewhere in the product.
/// The SEO center reads them and routes to them; it never becomes a second
/// writer for any of them.
enum SeoCenterScope { site, pages, products, collections }

extension SeoCenterScopeCopy on SeoCenterScope {
  String get label => switch (this) {
        SeoCenterScope.site => 'Sitio',
        SeoCenterScope.pages => 'Páginas',
        SeoCenterScope.products => 'Productos',
        SeoCenterScope.collections => 'Colecciones',
      };

  String get description => switch (this) {
        SeoCenterScope.site =>
          'Identidad, metadatos base y datos estructurados',
        SeoCenterScope.pages => 'Portada, páginas de confianza y páginas CMS',
        SeoCenterScope.products => 'Fichas públicas del catálogo',
        SeoCenterScope.collections => 'Categorías con página pública propia',
      };

  IconData get icon => switch (this) {
        SeoCenterScope.site => Icons.public_outlined,
        SeoCenterScope.pages => Icons.web_stories_outlined,
        SeoCenterScope.products => Icons.inventory_2_outlined,
        SeoCenterScope.collections => Icons.category_outlined,
      };
}

/// Rail orientation. The page picks it from real layout constraints, not from
/// the operating system.
enum SeoCenterScopeRailLayout { vertical, horizontal }

/// Selector for the four SEO scopes.
///
/// * `vertical` is the desktop rail (>=900 px content width).
/// * `horizontal` is the tablet and phone selector; it wraps instead of
///   scrolling sideways, so no composition ever depends on horizontal panning.
class SeoCenterScopeRail extends StatelessWidget {
  const SeoCenterScopeRail({
    super.key,
    required this.selected,
    required this.onSelected,
    this.layout = SeoCenterScopeRailLayout.vertical,
    this.counters = const {},
    this.attention = const {},
    this.width = 216,
  });

  final SeoCenterScope selected;
  final ValueChanged<SeoCenterScope> onSelected;
  final SeoCenterScopeRailLayout layout;

  /// Short trailing text per scope, e.g. `5 · 128`. Purely informational.
  final Map<SeoCenterScope, String> counters;

  /// Scopes that contain at least one row needing attention.
  final Map<SeoCenterScope, bool> attention;

  final double width;

  @override
  Widget build(BuildContext context) {
    if (layout == SeoCenterScopeRailLayout.horizontal) {
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final scope in SeoCenterScope.values)
            _ScopeChip(
              scope: scope,
              isSelected: scope == selected,
              counter: counters[scope],
              needsAttention: attention[scope] ?? false,
              onTap: () => onSelected(scope),
            ),
        ],
      );
    }

    final theme = Theme.of(context);
    return SizedBox(
      width: width,
      child: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        padding: const EdgeInsets.all(8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final scope in SeoCenterScope.values) ...[
              _ScopeRailItem(
                scope: scope,
                isSelected: scope == selected,
                counter: counters[scope],
                needsAttention: attention[scope] ?? false,
                onTap: () => onSelected(scope),
              ),
              if (scope != SeoCenterScope.values.last)
                const SizedBox(height: 4),
            ],
          ],
        ),
      ),
    );
  }
}

class _ScopeRailItem extends StatelessWidget {
  const _ScopeRailItem({
    required this.scope,
    required this.isSelected,
    required this.counter,
    required this.needsAttention,
    required this.onTap,
  });

  final SeoCenterScope scope;
  final bool isSelected;
  final String? counter;
  final bool needsAttention;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final foreground = isSelected
        ? theme.colorScheme.onPrimaryContainer
        : theme.colorScheme.onSurface;

    return Semantics(
      selected: isSelected,
      button: true,
      child: Material(
        color: isSelected
            ? theme.colorScheme.primaryContainer
            : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            child: Row(
              children: [
                Icon(scope.icon, size: 19, color: foreground),
                const SizedBox(width: 11),
                Expanded(
                  child: Text(
                    scope.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight:
                          isSelected ? FontWeight.w700 : FontWeight.w600,
                      color: foreground,
                    ),
                  ),
                ),
                if (needsAttention) ...[
                  const SizedBox(width: 6),
                  const _AttentionDot(),
                ],
                if (counter != null && counter!.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Text(
                    counter!,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: isSelected
                          ? foreground
                          : theme.colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ScopeChip extends StatelessWidget {
  const _ScopeChip({
    required this.scope,
    required this.isSelected,
    required this.counter,
    required this.needsAttention,
    required this.onTap,
  });

  final SeoCenterScope scope;
  final bool isSelected;
  final String? counter;
  final bool needsAttention;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final foreground = isSelected
        ? theme.colorScheme.onPrimaryContainer
        : theme.colorScheme.onSurface;

    return Semantics(
      selected: isSelected,
      button: true,
      child: Material(
        color: isSelected
            ? theme.colorScheme.primaryContainer
            : theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            constraints: const BoxConstraints(minHeight: 44),
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isSelected
                    ? theme.colorScheme.primaryContainer
                    : theme.colorScheme.outlineVariant,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(scope.icon, size: 17, color: foreground),
                const SizedBox(width: 8),
                Text(
                  scope.label,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                    color: foreground,
                  ),
                ),
                if (needsAttention) ...[
                  const SizedBox(width: 6),
                  const _AttentionDot(),
                ],
                if (counter != null && counter!.isNotEmpty) ...[
                  const SizedBox(width: 7),
                  Text(
                    counter!,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: isSelected
                          ? foreground
                          : theme.colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AttentionDot extends StatelessWidget {
  const _AttentionDot();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      label: 'Requiere atención',
      child: Container(
        width: 7,
        height: 7,
        decoration: BoxDecoration(
          color: theme.colorScheme.tertiary,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}
