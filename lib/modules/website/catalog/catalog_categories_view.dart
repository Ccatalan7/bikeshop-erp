import 'package:flutter/material.dart';

import '../../../shared/themes/vinabike_theme_roles.dart';
import 'catalog_ui_parts.dart';
import 'catalog_web_controller.dart';
import 'catalog_web_models.dart';

/// Opens a category's own page on the editor canvas.
typedef CatalogOpenCategoryPage = void Function(
  String categoryId,
  String categoryName, {
  required bool services,
});

/// «Categorías»: which ones the store shows, with what each sells counted
/// with its subcategories (a parent no longer reads 0/0).
class CatalogCategoriesView extends StatefulWidget {
  const CatalogCategoriesView({
    super.key,
    required this.controller,
    this.onOpenCategoryPage,
  });

  final CatalogWebController controller;
  final CatalogOpenCategoryPage? onOpenCategoryPage;

  @override
  State<CatalogCategoriesView> createState() => _CatalogCategoriesViewState();
}

class _CatalogCategoriesViewState extends State<CatalogCategoriesView> {
  bool _onlyVisible = false;
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _toggle(CatalogCategoryCount category, bool visible) async {
    try {
      await widget.controller.setCategoryVisible(category.id, visible);
      if (mounted) {
        showCatalogMessage(
          context,
          visible
              ? '«${category.name}» se muestra en la tienda.'
              : '«${category.name}» ya no se muestra en la tienda.',
        );
      }
    } catch (error) {
      if (mounted) showCatalogMessage(context, catalogErrorMessage(error));
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) => LayoutBuilder(
        builder: (context, constraints) {
          final theme = Theme.of(context);
          final scheme = theme.colorScheme;
          final compact = constraints.maxWidth < 700;
          final side = compact ? 12.0 : 20.0;
          final query = _search.text.trim().toLowerCase();
          final all = widget.controller.categories;
          final rows = [
            for (final category in all)
              if ((!_onlyVisible || category.visible) &&
                  (category.selling +
                              category.soldOut +
                              category.needsAttention >
                          0 ||
                      category.visible) &&
                  (query.isEmpty ||
                      (category.fullPath ?? category.name)
                          .toLowerCase()
                          .contains(query)))
                category,
          ];
          final visible = all.where((c) => c.visible).toList();
          final outside = all
              .where((c) => !c.visible && c.parentId == null && c.selling > 0)
              .toList();
          final emptyVisible = visible.where((c) => c.selling == 0).toList();

          return ListView(
            padding: EdgeInsets.fromLTRB(side, 16, side, 32),
            children: [
              Text('Categorías',
                  style: theme.textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text(
                '${visible.length} de ${all.length} se muestran en la tienda. Los números suman sus subcategorías. '
                'Mostrar u ocultar una categoría no cambia qué productos se venden: decide qué categorías aparecen en la tienda.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
              if (outside.isNotEmpty || emptyVisible.isNotEmpty) ...[
                const SizedBox(height: 12),
                _Notes(outside: outside, emptyVisible: emptyVisible),
              ],
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: compact ? double.infinity : 320,
                    child: TextField(
                      controller: _search,
                      decoration: const InputDecoration(
                        isDense: true,
                        prefixIcon: Icon(Icons.search, size: 20),
                        hintText: 'Buscar categoría',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  FilterChip(
                    label: const Text('Sólo las que se muestran'),
                    selected: _onlyVisible,
                    onSelected: (value) => setState(() => _onlyVisible = value),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: scheme.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: scheme.outlineVariant),
                ),
                child: Column(
                  children: [
                    if (!compact) const _Header(),
                    for (final category in rows)
                      _Row(
                        category: category,
                        compact: compact,
                        busy: widget.controller.busy,
                        onToggle: (visible) => _toggle(category, visible),
                        onOpenPage: widget.onOpenCategoryPage == null ||
                                !category.visible
                            ? null
                            : () => widget.onOpenCategoryPage!(
                                  category.id,
                                  category.name,
                                  services: false,
                                ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              CatalogStorePreview(
                title: 'Así se ven las categorías en /productos',
                path: '/productos',
                note:
                    'Cada una abre su página con lo que tiene a la venta, contando sus subcategorías.',
                child: _MenuPreview(categories: visible),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Notes extends StatelessWidget {
  const _Notes({required this.outside, required this.emptyVisible});

  final List<CatalogCategoryCount> outside;
  final List<CatalogCategoryCount> emptyVisible;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final roles = VinabikeThemeRoles.of(context);
    final lines = <String>[
      if (outside.isNotEmpty)
        '${outside.fold<int>(0, (s, c) => s + c.selling)} productos a la venta están en categorías que no se muestran '
            '(${outside.map((c) => c.name).join(', ')}): se encuentran buscando, pero no navegando.',
      if (emptyVisible.isNotEmpty)
        'Se muestran sin nada a la venta: ${emptyVisible.map((c) => c.name).join(', ')}.',
    ];
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: roles.info.container,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final line in lines)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text(line,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: roles.info.onContainer)),
            ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.labelSmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.6,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
      child: Row(
        children: [
          Expanded(child: Text('CATEGORÍA', style: style)),
          SizedBox(
              width: 84,
              child:
                  Text('EN VENTA', style: style, textAlign: TextAlign.right)),
          SizedBox(
              width: 84,
              child:
                  Text('AGOTADOS', style: style, textAlign: TextAlign.right)),
          SizedBox(
              width: 92,
              child:
                  Text('FALTA ALGO', style: style, textAlign: TextAlign.right)),
          const SizedBox(width: 16),
          SizedBox(width: 190, child: Text('EN LA TIENDA', style: style)),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.category,
    required this.compact,
    required this.busy,
    required this.onToggle,
    required this.onOpenPage,
  });

  final CatalogCategoryCount category;
  final bool compact;
  final bool busy;
  final ValueChanged<bool> onToggle;
  final VoidCallback? onOpenPage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final roles = VinabikeThemeRoles.of(context);
    final numbers = theme.textTheme.bodyMedium?.copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final indent = (category.level.clamp(0, 4)) * 16.0;
    final name = Padding(
      padding: EdgeInsets.only(left: indent),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(category.name,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: category.parentId == null ? FontWeight.w600 : null,
              )),
          if (category.subcategories > 0)
            Text(
              '${category.subcategories} ${category.subcategories == 1 ? 'subcategoría' : 'subcategorías'}',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
        ],
      ),
    );
    final toggle = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Switch(
          value: category.visible,
          onChanged: busy ? null : onToggle,
        ),
        if (onOpenPage != null)
          TextButton(onPressed: onOpenPage, child: const Text('Su página')),
      ],
    );
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
      decoration:
          BoxDecoration(border: Border(top: BorderSide(color: roles.hairline))),
      child: compact
          ? Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      name,
                      Padding(
                        padding: EdgeInsets.only(left: indent, top: 2),
                        child: Text(
                          '${category.selling} en venta · ${category.soldOut} agotados'
                          '${category.needsAttention > 0 ? ' · ${category.needsAttention} falta algo' : ''}',
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ),
                    ],
                  ),
                ),
                toggle,
              ],
            )
          : Row(
              children: [
                Expanded(child: name),
                SizedBox(
                  width: 84,
                  child: Text('${category.selling}',
                      textAlign: TextAlign.right,
                      style: numbers?.copyWith(fontWeight: FontWeight.w600)),
                ),
                SizedBox(
                  width: 84,
                  child: Text('${category.soldOut}',
                      textAlign: TextAlign.right,
                      style: numbers?.copyWith(color: scheme.onSurfaceVariant)),
                ),
                SizedBox(
                  width: 92,
                  child: Text('${category.needsAttention}',
                      textAlign: TextAlign.right,
                      style: numbers?.copyWith(
                        color: category.needsAttention > 0
                            ? roles.warning.accent
                            : scheme.onSurfaceVariant,
                      )),
                ),
                const SizedBox(width: 16),
                SizedBox(width: 190, child: toggle),
              ],
            ),
    );
  }
}

class _MenuPreview extends StatelessWidget {
  const _MenuPreview({required this.categories});

  final List<CatalogCategoryCount> categories;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final roots = categories.where((c) => c.parentId == null).toList();
    final shown = (roots.isNotEmpty ? roots : categories).take(14).toList();
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final category in shown)
          Chip(
            label: Text('${category.name} (${category.selling})'),
            backgroundColor: theme.colorScheme.surfaceContainerHighest,
          ),
        if (categories.length > shown.length)
          Chip(label: Text('+${categories.length - shown.length} más')),
      ],
    );
  }
}
