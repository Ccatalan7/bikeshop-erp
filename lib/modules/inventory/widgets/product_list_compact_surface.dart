import 'package:flutter/material.dart';

/// Primary command row for the compact inventory surface.
///
/// Secondary catalog commands intentionally stay behind [onMore] so the first
/// reading keeps the catalog identity and the main create action.
class CompactInventoryCommandHeader extends StatelessWidget {
  const CompactInventoryCommandHeader({
    super.key,
    required this.title,
    required this.countLabel,
    required this.onNew,
    this.onMore,
  });

  final String title;
  final String countLabel;
  final VoidCallback onNew;
  final VoidCallback? onMore;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                countLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        if (onMore != null) ...[
          SizedBox(
            height: 48,
            child: OutlinedButton.icon(
              key: const ValueKey('inventory-compact-more-actions'),
              onPressed: onMore,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(48, 48),
                padding: const EdgeInsets.symmetric(horizontal: 12),
              ),
              icon: const Icon(Icons.more_horiz_rounded, size: 20),
              label: const Text('Más'),
            ),
          ),
          const SizedBox(width: 8),
        ],
        SizedBox(
          height: 48,
          child: FilledButton.icon(
            key: const ValueKey('inventory-compact-new'),
            onPressed: onNew,
            style: FilledButton.styleFrom(
              minimumSize: const Size(48, 48),
              padding: const EdgeInsets.symmetric(horizontal: 12),
            ),
            icon: const Icon(Icons.add_rounded, size: 20),
            label: const Text('Nuevo'),
          ),
        ),
      ],
    );
  }
}

/// Search and filter command row used by the compact inventory list.
///
/// The page owns the query and filter state; this widget only recomposes those
/// same controls into one 48px touch row.
class CompactInventorySearchToolbar extends StatelessWidget {
  const CompactInventorySearchToolbar({
    super.key,
    required this.controller,
    required this.hintText,
    required this.hasActiveFilters,
    required this.onChanged,
    required this.onClear,
    required this.onOpenFilters,
  });

  final TextEditingController controller;
  final String hintText;
  final bool hasActiveFilters;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;
  final VoidCallback onOpenFilters;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      children: [
        Expanded(
          child: SizedBox(
            key: const ValueKey('inventory-compact-search'),
            height: 48,
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              textAlignVertical: TextAlignVertical.center,
              decoration: InputDecoration(
                hintText: hintText,
                prefixIcon: const Icon(Icons.search_rounded, size: 20),
                prefixIconConstraints:
                    const BoxConstraints(minWidth: 48, minHeight: 48),
                suffixIcon: controller.text.isNotEmpty
                    ? IconButton(
                        key: const ValueKey('inventory-compact-clear-search'),
                        tooltip: 'Limpiar búsqueda',
                        onPressed: onClear,
                        constraints: const BoxConstraints.tightFor(
                            width: 48, height: 48),
                        icon: const Icon(Icons.close_rounded, size: 20),
                      )
                    : null,
                suffixIconConstraints:
                    const BoxConstraints(minWidth: 48, minHeight: 48),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                filled: true,
                fillColor: theme.colorScheme.surfaceContainerHighest
                    .withValues(alpha: 0.34),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(
                    color: theme.colorScheme.outlineVariant,
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(
                    color: theme.colorScheme.outlineVariant,
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Semantics(
          label: hasActiveFilters ? 'Filtros activos' : 'Abrir filtros',
          button: true,
          child: SizedBox.square(
            key: const ValueKey('inventory-compact-filters'),
            dimension: 48,
            child: IconButton(
              tooltip: hasActiveFilters ? 'Filtros activos' : 'Filtros',
              onPressed: onOpenFilters,
              style: IconButton.styleFrom(
                backgroundColor: hasActiveFilters
                    ? theme.colorScheme.primaryContainer
                    : theme.colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.34),
                foregroundColor: hasActiveFilters
                    ? theme.colorScheme.onPrimaryContainer
                    : theme.colorScheme.onSurfaceVariant,
                side: BorderSide(
                  color: hasActiveFilters
                      ? theme.colorScheme.primary.withValues(alpha: 0.55)
                      : theme.colorScheme.outlineVariant,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              icon: Icon(
                hasActiveFilters
                    ? Icons.filter_alt_rounded
                    : Icons.tune_rounded,
                size: 20,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// A phone/tablet product row with no desktop column widths.
///
/// Identity and actions form the first line. Stock, price, and cost use the
/// complete available width below it, so long names and increased text scale
/// reflow without squeezing the monetary values out of the viewport.
class CompactInventoryProductRow extends StatelessWidget {
  const CompactInventoryProductRow({
    super.key,
    required this.name,
    required this.sku,
    required this.stockLabel,
    required this.stockColor,
    required this.priceLabel,
    required this.costLabel,
    required this.leading,
    required this.onOpen,
    required this.onActionSelected,
    this.secondaryLabel,
    this.isSet = false,
    this.isActive = true,
  });

  final String name;
  final String sku;
  final String stockLabel;
  final Color stockColor;
  final String priceLabel;
  final String costLabel;
  final Widget leading;
  final VoidCallback onOpen;
  final ValueChanged<String> onActionSelected;
  final String? secondaryLabel;
  final bool isSet;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final metadata = [
      if (sku.trim().isNotEmpty) 'SKU $sku',
      if (secondaryLabel?.trim().isNotEmpty ?? false) secondaryLabel!.trim(),
    ].join(' · ');

    return Semantics(
      container: true,
      label: [
        name,
        if (sku.trim().isNotEmpty) 'SKU $sku',
        'Stock $stockLabel',
        'Precio $priceLabel',
        'Costo $costLabel',
      ].join('. '),
      child: Material(
        color: theme.colorScheme.surface,
        child: InkWell(
          key: const ValueKey('inventory-compact-row-open'),
          onTap: onOpen,
          child: Container(
            constraints: const BoxConstraints(minHeight: 104),
            padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color:
                      theme.colorScheme.outlineVariant.withValues(alpha: 0.52),
                ),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    SizedBox.square(
                      key: const ValueKey('inventory-compact-thumbnail'),
                      dimension: 48,
                      child: leading,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (isSet) ...[
                                Container(
                                  margin: const EdgeInsets.only(
                                    right: 6,
                                    top: 2,
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 5,
                                    vertical: 1,
                                  ),
                                  decoration: BoxDecoration(
                                    color: theme.colorScheme.tertiaryContainer,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    'SET',
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color:
                                          theme.colorScheme.onTertiaryContainer,
                                      fontSize: 9,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                              Expanded(
                                child: Text(
                                  name,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                    color: isActive
                                        ? theme.colorScheme.onSurface
                                        : theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (metadata.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                metadata,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    Semantics(
                      label: 'Abrir ficha de $name',
                      button: true,
                      child: SizedBox.square(
                        key: const ValueKey('inventory-compact-edit'),
                        dimension: 48,
                        child: IconButton(
                          tooltip: 'Abrir ficha',
                          onPressed: onOpen,
                          icon: const Icon(Icons.edit_outlined, size: 20),
                        ),
                      ),
                    ),
                    Semantics(
                      label: 'Más acciones para $name',
                      button: true,
                      child: SizedBox.square(
                        key: const ValueKey('inventory-compact-more'),
                        dimension: 48,
                        child: PopupMenuButton<String>(
                          tooltip: 'Más acciones',
                          padding: EdgeInsets.zero,
                          icon: const Icon(Icons.more_vert_rounded, size: 20),
                          onSelected: onActionSelected,
                          itemBuilder: (context) => [
                            const PopupMenuItem<String>(
                              value: 'edit',
                              child: Row(
                                children: [
                                  Icon(Icons.open_in_new_rounded, size: 18),
                                  SizedBox(width: 10),
                                  Text('Abrir ficha'),
                                ],
                              ),
                            ),
                            PopupMenuItem<String>(
                              value: 'delete',
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.delete_outline_rounded,
                                    size: 18,
                                    color: theme.colorScheme.error,
                                  ),
                                  const SizedBox(width: 10),
                                  Text(
                                    'Eliminar',
                                    style: TextStyle(
                                      color: theme.colorScheme.error,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _CompactInventoryMetric(
                        label: 'Stock',
                        value: stockLabel,
                        valueColor: stockColor,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _CompactInventoryMetric(
                        label: 'Precio',
                        value: priceLabel,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _CompactInventoryMetric(
                        label: 'Costo',
                        value: costLabel,
                        valueColor: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
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

class _CompactInventoryMetric extends StatelessWidget {
  const _CompactInventoryMetric({
    required this.label,
    required this.value,
    this.valueColor,
  });

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          maxLines: 1,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        Text(
          value,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall?.copyWith(
            color: valueColor ?? theme.colorScheme.onSurface,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
