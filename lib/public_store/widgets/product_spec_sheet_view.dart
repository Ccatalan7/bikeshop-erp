import 'package:flutter/material.dart';

import '../models/public_product_spec_sheet.dart';
import '../theme/public_store_surface_theme.dart';

/// What decides the purchase, next to the price: one object with up to four
/// cells (value first, then what it is), and a way down to the full sheet.
class ProductSpecHighlights extends StatelessWidget {
  const ProductSpecHighlights({
    super.key,
    required this.items,
    this.onSeeAll,
  });

  final List<PublicSpecItem> items;
  final VoidCallback? onSeeAll;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    final theme = PublicStoreSurfaceTheme.of(context);
    return Column(
      key: const ValueKey('product-spec-highlights'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(builder: (context, constraints) {
          // Two columns whenever a value has room to breathe; an odd last
          // cell takes the whole row instead of sitting alone half-empty.
          final columns = constraints.maxWidth >= 300 ? 2 : 1;
          final rows = <List<PublicSpecItem>>[];
          for (var i = 0; i < items.length; i += columns) {
            rows.add(items.sublist(i, (i + columns).clamp(0, items.length)));
          }
          return DecoratedBox(
            decoration: BoxDecoration(
              color: theme.softSurface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: theme.commerceLine),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Column(
                children: [
                  for (var r = 0; r < rows.length; r++)
                    DecoratedBox(
                      decoration: BoxDecoration(
                        border: r == 0
                            ? null
                            : Border(
                                top: BorderSide(color: theme.commerceLine)),
                      ),
                      child: IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (var c = 0; c < rows[r].length; c++) ...[
                              if (c > 0)
                                VerticalDivider(
                                  width: 1,
                                  thickness: 1,
                                  color: theme.commerceLine,
                                ),
                              Expanded(child: _cell(theme, rows[r][c])),
                            ],
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        }),
        if (onSeeAll != null) ...[
          const SizedBox(height: 6),
          TextButton.icon(
            key: const ValueKey('product-spec-see-all'),
            onPressed: onSeeAll,
            style: TextButton.styleFrom(
              foregroundColor: theme.commerceAccent,
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
              minimumSize: const Size(0, 44),
              tapTargetSize: MaterialTapTargetSize.padded,
            ),
            icon: const Icon(Icons.south_rounded, size: 16),
            label: const Text(
              'Ver ficha técnica completa',
              style: TextStyle(
                fontFamily: null,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _cell(PublicStoreSurfaceTheme theme, PublicSpecItem item) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            item.value,
            style: theme.text.titleMedium?.copyWith(
              fontSize: 16.5,
              fontWeight: FontWeight.w700,
              color: theme.commerceTextPrimary,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            item.label,
            style: theme.text.bodySmall?.copyWith(
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
              color: theme.commerceTextSecondary,
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }
}

/// The full sheet: every published datum in groups a shop would use, the
/// origin of the data said once, and a person to ask.
class ProductSpecSheetView extends StatelessWidget {
  const ProductSpecSheetView({
    super.key,
    required this.sheet,
    required this.isLoading,
    required this.isMobile,
    this.description = '',
    this.onAsk,
    this.askLabel,
  });

  final PublicProductSpecSheet sheet;
  final bool isLoading;
  final bool isMobile;
  final String description;

  /// Opens a conversation with the shop about this product; null when the
  /// store has no channel configured.
  final VoidCallback? onAsk;
  final String? askLabel;

  @override
  Widget build(BuildContext context) {
    final theme = PublicStoreSurfaceTheme.of(context);
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (description.trim().isNotEmpty) ...[
          _title(theme, 'Descripción'),
          const SizedBox(height: 10),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Text(
              description.trim(),
              key: const ValueKey('product_description_text'),
              style: theme.text.bodyMedium?.copyWith(
                fontSize: 15,
                color: theme.commerceTextPrimary,
                height: 1.7,
              ),
            ),
          ),
          const SizedBox(height: 32),
        ],
        if (isLoading && sheet.isEmpty)
          SizedBox(
            key: const ValueKey('product_technical_specs_loading'),
            height: 72,
            child: Align(
              alignment: Alignment.centerLeft,
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: theme.commerceAccent,
                ),
              ),
            ),
          )
        else ...[
          if (!sheet.hasTechnicalData)
            Padding(
              padding: const EdgeInsets.only(bottom: 24),
              child: Text(
                'Aún no publicamos la ficha técnica de este producto.',
                key: const ValueKey('product_technical_specs_empty'),
                style: theme.text.bodyMedium?.copyWith(
                  fontSize: 15,
                  color: theme.commerceTextSecondary,
                  height: 1.6,
                ),
              ),
            ),
          for (var i = 0; i < sheet.groups.length; i++) ...[
            if (i > 0) const SizedBox(height: 28),
            _group(theme, sheet.groups[i]),
          ],
          if (sheet.hasTechnicalData) ...[
            const SizedBox(height: 16),
            Text(
              'Datos informados por el fabricante y el proveedor.',
              key: const ValueKey('product-spec-origin'),
              style: theme.text.bodySmall?.copyWith(
                fontSize: 12.5,
                color: theme.commerceTextMuted,
              ),
            ),
          ],
        ],
      ],
    );

    final help = _help(theme);
    return KeyedSubtree(
      key: const ValueKey('product_technical_specs_tab'),
      child: isMobile
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [content, const SizedBox(height: 32), help],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 820),
                      child: content,
                    ),
                  ),
                ),
                const SizedBox(width: 56),
                SizedBox(width: 340, child: help),
              ],
            ),
    );
  }

  Widget _title(PublicStoreSurfaceTheme theme, String title) => Text(
        title.toUpperCase(),
        style: theme.text.labelSmall?.copyWith(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          color: theme.commerceAccent,
          letterSpacing: 1.0,
        ),
      );

  Widget _group(PublicStoreSurfaceTheme theme, PublicSpecGroup group) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _title(theme, group.title),
        const SizedBox(height: 8),
        for (final item in group.items) _row(theme, item),
      ],
    );
  }

  Widget _row(PublicStoreSurfaceTheme theme, PublicSpecItem item) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: theme.commerceLine)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 5,
                child: Padding(
                  padding: const EdgeInsets.only(right: 16, top: 1),
                  child: Text(
                    item.label,
                    style: theme.text.bodyMedium?.copyWith(
                      fontSize: 14,
                      color: theme.commerceTextSecondary,
                      height: 1.4,
                    ),
                  ),
                ),
              ),
              Expanded(
                flex: 7,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.value,
                      style: theme.text.bodyMedium?.copyWith(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: theme.commerceTextPrimary,
                        height: 1.4,
                      ),
                    ),
                    if (item.detail != null)
                      Text(
                        item.detail!,
                        style: theme.text.bodySmall?.copyWith(
                          fontSize: 12.5,
                          color: theme.commerceTextMuted,
                          height: 1.4,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          if (item.hint != null) ...[
            const SizedBox(height: 4),
            Text(
              item.hint!,
              style: theme.text.bodySmall?.copyWith(
                fontSize: 12.5,
                color: theme.commerceTextMuted,
                height: 1.45,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _help(PublicStoreSurfaceTheme theme) {
    return Container(
      key: const ValueKey('product-spec-help'),
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: theme.softSurface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.commerceLine),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.pedal_bike_outlined,
              size: 26, color: theme.commerceAccent),
          const SizedBox(height: 12),
          Text(
            '¿Le sirve a tu bicicleta?',
            style: theme.text.titleMedium?.copyWith(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: theme.commerceTextPrimary,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            sheet.hasTechnicalData
                ? 'Cuéntanos qué bicicleta tienes y te ayudamos a elegir '
                    'la medida correcta antes de comprar.'
                : 'Escríbenos y te ayudamos con lo que necesites saber de '
                    'este producto antes de comprar.',
            style: theme.text.bodyMedium?.copyWith(
              fontSize: 14,
              color: theme.commerceTextSecondary,
              height: 1.55,
            ),
          ),
          if (onAsk != null) ...[
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 46,
              child: OutlinedButton.icon(
                key: const ValueKey('product-spec-ask'),
                onPressed: onAsk,
                style: OutlinedButton.styleFrom(
                  foregroundColor: theme.commerceAccent,
                  side: BorderSide(color: theme.commerceAccent),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(5),
                  ),
                ),
                icon: const Icon(Icons.chat_bubble_outline_rounded, size: 17),
                label: Text(
                  askLabel ?? 'Escríbenos',
                  style: const TextStyle(
                    fontFamily: null,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
