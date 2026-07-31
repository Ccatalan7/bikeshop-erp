import 'package:flutter/material.dart';

import '../../../shared/utils/responsive_viewport.dart';

/// Responsive composition boundary for the stock-movement workspace.
///
/// Business state and commands stay with [StockMovementsPage]. This widget only
/// decides whether the canonical list/detail children are presented as a
/// desktop split or as a compact in-page workspace.
class StockMovementsResponsiveFrame extends StatelessWidget {
  const StockMovementsResponsiveFrame({
    super.key,
    required this.isRecentMode,
    required this.hasSelectedProduct,
    required this.recentScopeLabel,
    required this.desktopHeader,
    required this.recentBody,
    required this.productList,
    required this.productDetail,
    required this.onSelectRecentMode,
    required this.onSelectProductMode,
    required this.onBackToProducts,
    required this.desktopProductListWidth,
    required this.onDesktopPanelResize,
  });

  final bool isRecentMode;
  final bool hasSelectedProduct;
  final String recentScopeLabel;
  final Widget desktopHeader;
  final Widget recentBody;
  final Widget productList;
  final Widget productDetail;
  final VoidCallback onSelectRecentMode;
  final VoidCallback onSelectProductMode;
  final VoidCallback onBackToProducts;
  final double desktopProductListWidth;
  final ValueChanged<double> onDesktopPanelResize;

  @override
  Widget build(BuildContext context) {
    final isCompact = ResponsiveViewport.usesCompactShell(context);

    return Column(
      children: [
        if (isCompact)
          _CompactStockMovementsHeader(
            isRecentMode: isRecentMode,
            hasSelectedProduct: hasSelectedProduct,
            recentScopeLabel: recentScopeLabel,
            onSelectRecentMode: onSelectRecentMode,
            onSelectProductMode: onSelectProductMode,
          )
        else
          desktopHeader,
        Expanded(
          child: isRecentMode
              ? recentBody
              : isCompact
                  ? _CompactProductWorkspace(
                      hasSelectedProduct: hasSelectedProduct,
                      productList: productList,
                      productDetail: productDetail,
                      onBackToProducts: onBackToProducts,
                    )
                  : _DesktopProductWorkspace(
                      productListWidth: desktopProductListWidth,
                      productList: productList,
                      productDetail: productDetail,
                      onPanelResize: onDesktopPanelResize,
                    ),
        ),
      ],
    );
  }
}

class _CompactStockMovementsHeader extends StatelessWidget {
  const _CompactStockMovementsHeader({
    required this.isRecentMode,
    required this.hasSelectedProduct,
    required this.recentScopeLabel,
    required this.onSelectRecentMode,
    required this.onSelectProductMode,
  });

  final bool isRecentMode;
  final bool hasSelectedProduct;
  final String recentScopeLabel;
  final VoidCallback onSelectRecentMode;
  final VoidCallback onSelectProductMode;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subtitle = isRecentMode
        ? recentScopeLabel
        : hasSelectedProduct
            ? 'Historial del producto'
            : 'Selecciona un producto';

    return Material(
      key: const ValueKey('stock-movements-compact-header'),
      color: theme.colorScheme.surface,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.45),
            ),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Movimientos de stock',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              height: 48,
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: _CompactModeButton(
                      key: const ValueKey('stock-movements-mode-recent'),
                      label: 'Últimos',
                      icon: Icons.history,
                      selected: isRecentMode,
                      onTap: onSelectRecentMode,
                    ),
                  ),
                  Expanded(
                    child: _CompactModeButton(
                      key: const ValueKey('stock-movements-mode-product'),
                      label: 'Por producto',
                      icon: Icons.inventory_2_outlined,
                      selected: !isRecentMode,
                      onTap: onSelectProductMode,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CompactModeButton extends StatelessWidget {
  const _CompactModeButton({
    super.key,
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final foreground = selected
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurfaceVariant;

    return Semantics(
      button: true,
      selected: selected,
      label: 'Vista $label',
      onTap: onTap,
      excludeSemantics: true,
      child: Material(
        color: selected
            ? theme.colorScheme.primaryContainer.withValues(alpha: 0.58)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(9),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(9),
          child: SizedBox.expand(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 18, color: foreground),
                const SizedBox(width: 7),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: foreground,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
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

class _CompactProductWorkspace extends StatelessWidget {
  const _CompactProductWorkspace({
    required this.hasSelectedProduct,
    required this.productList,
    required this.productDetail,
    required this.onBackToProducts,
  });

  final bool hasSelectedProduct;
  final Widget productList;
  final Widget productDetail;
  final VoidCallback onBackToProducts;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return IndexedStack(
      index: hasSelectedProduct ? 1 : 0,
      children: [
        KeyedSubtree(
          key: const ValueKey('stock-movements-compact-product-list'),
          child: productList,
        ),
        Column(
          key: const ValueKey('stock-movements-compact-product-detail'),
          children: [
            Semantics(
              button: true,
              label: 'Volver a productos',
              onTap: onBackToProducts,
              excludeSemantics: true,
              child: Material(
                color: theme.colorScheme.surfaceContainerLowest,
                child: InkWell(
                  key: const ValueKey('stock-movements-compact-back'),
                  onTap: onBackToProducts,
                  child: SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Row(
                        children: [
                          Icon(
                            Icons.arrow_back,
                            size: 20,
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(width: 10),
                          Text(
                            'Volver a productos',
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: theme.colorScheme.primary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Expanded(child: productDetail),
          ],
        ),
      ],
    );
  }
}

class _DesktopProductWorkspace extends StatelessWidget {
  const _DesktopProductWorkspace({
    required this.productListWidth,
    required this.productList,
    required this.productDetail,
    required this.onPanelResize,
  });

  final double productListWidth;
  final Widget productList;
  final Widget productDetail;
  final ValueChanged<double> onPanelResize;

  @override
  Widget build(BuildContext context) {
    return Row(
      key: const ValueKey('stock-movements-desktop-split'),
      children: [
        SizedBox(width: productListWidth, child: productList),
        MouseRegion(
          cursor: SystemMouseCursors.resizeColumn,
          child: GestureDetector(
            onHorizontalDragUpdate: (details) =>
                onPanelResize(details.delta.dx),
            child: Container(
              width: 8,
              color: Colors.transparent,
              alignment: Alignment.center,
              child: Container(
                width: 1,
                color: Theme.of(context).dividerColor,
              ),
            ),
          ),
        ),
        Expanded(child: productDetail),
      ],
    );
  }
}

/// Compact reference destination used by movement cards.
///
/// A null [onTap] keeps the reference readable without announcing a fake
/// action. Navigable references expose one named, 48px-high touch target.
class StockMovementCompactReferenceAction extends StatelessWidget {
  const StockMovementCompactReferenceAction({
    super.key,
    required this.label,
    this.onTap,
  });

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final child = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: onTap == null
                      ? theme.colorScheme.onSurfaceVariant
                      : theme.colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (onTap != null) ...[
              const SizedBox(width: 4),
              Icon(
                Icons.chevron_right,
                size: 18,
                color: theme.colorScheme.primary,
              ),
            ],
          ],
        ),
      ),
    );

    final action = onTap;
    if (action == null) {
      return child;
    }

    return Semantics(
      button: true,
      label: 'Abrir $label',
      onTap: action,
      excludeSemantics: true,
      child: InkWell(
        onTap: action,
        borderRadius: BorderRadius.circular(6),
        child: child,
      ),
    );
  }
}
