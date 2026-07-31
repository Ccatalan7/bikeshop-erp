import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/stock_movement.dart';
import '../services/stock_movements_service.dart';

/// The stock ledger: a chronological statement of what happened to stock.
///
/// It reads top to bottom like a bank statement — day breaks give the eye a
/// rhythm, every figure stacks in the same column, and one row can be opened to
/// ask why. That is the whole organising idea, and the layout decisions below
/// follow from it:
///
///  * There are no product thumbnails. A ledger identifies a line by name, SKU
///    and document, and a 40px picture per row halved the number of facts
///    visible in one screen without helping anyone find anything.
///  * There is no manual column resizing. Seven invisible drag handles between
///    headers are maintenance, not an affordance; the columns are sized from
///    their content and the optional ones drop at known widths instead.
///  * Only `Fecha` and `Cambio` sort. Ordering by running balance is
///    meaningless — the balance is a consequence of chronology — and ordering
///    by product or reference is what the facets are for.
///  * Sorting by `Cambio` visibly changes the reading mode: day headers
///    dissolve and the balance drops in weight, because a running balance
///    re-sorted by magnitude no longer describes a sequence.
class StockLedger extends StatelessWidget {
  const StockLedger({
    required this.movements,
    required this.chronological,
    required this.sortKey,
    required this.ascending,
    required this.onSort,
    required this.onOpen,
    this.storeTimezone = stockMovementsDefaultStoreTimezone,
    this.showProduct = true,
    this.selectedId,
    this.scrollController,
    super.key,
  });

  /// Below this the row recomposes into two stacked lines. Registered as an
  /// internal exception in `docs/architecture/canonical-ui-surfaces.md`.
  static const stackedMaxWidth = 720.0;

  static const rowExtent = 44.0;
  static const _stackedRowExtent = 64.0;

  final List<StockMovement> movements;
  final bool chronological;
  final MovementSortKey sortKey;
  final bool ascending;
  final void Function(MovementSortKey key) onSort;
  final void Function(StockMovement movement) onOpen;
  final String storeTimezone;
  final bool showProduct;
  final String? selectedId;
  final ScrollController? scrollController;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked = constraints.maxWidth < stackedMaxWidth;
        // Never dropped: it is the row's evidence.
        const showReference = true;
        final showSku = constraints.maxWidth >= 1120;
        final storeToday = stockMovementStoreTime(
          DateTime.now().toUtc(),
          storeTimezone: storeTimezone,
        );
        final rows = _groupRows(storeToday);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!stacked)
              _LedgerHeaderBar(
                showProduct: showProduct,
                showReference: showReference,
                showSku: showSku,
                sortKey: sortKey,
                ascending: ascending,
                onSort: onSort,
              ),
            if (stacked)
              _CompactLedgerSortBar(
                sortKey: sortKey,
                ascending: ascending,
                onSort: onSort,
              ),
            Expanded(
              child: CustomScrollView(
                controller: scrollController,
                key: const PageStorageKey('stock-movements-ledger'),
                slivers: [
                  // Each day is its own sliver group so its header pins only while
                  // that day is on screen and is then pushed out by the next one.
                  // Several independently pinned headers in one scroll view produce
                  // invalid geometry (layoutExtent exceeding paintExtent) as soon as
                  // the second one is pushed, and the whole viewport stops painting.
                  for (final section in rows)
                    SliverMainAxisGroup(
                      slivers: [
                        if (section.header != null)
                          SliverPersistentHeader(
                            pinned: true,
                            delegate: _DayHeaderDelegate(section.header!),
                          ),
                        SliverFixedExtentList(
                          itemExtent: stacked ? _stackedRowExtent : rowExtent,
                          delegate: SliverChildBuilderDelegate(
                            (context, index) {
                              final movement = section.rows[index];
                              return _LedgerRow(
                                movement: movement,
                                stacked: stacked,
                                showProduct: showProduct,
                                showReference: showReference,
                                showSku: showSku,
                                chronological: chronological,
                                selected: movement.id == selectedId,
                                storeTimezone: storeTimezone,
                                onOpen: () => onOpen(movement),
                              );
                            },
                            childCount: section.rows.length,
                          ),
                        ),
                      ],
                    ),
                  const SliverToBoxAdapter(child: SizedBox(height: 24)),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  /// Day sections, but only while the ledger is a statement.
  ///
  /// Under a ranked order consecutive rows are unrelated in time, so a day
  /// header would group rows that have nothing to do with each other.
  List<_LedgerSection> _groupRows(DateTime storeToday) {
    if (!chronological) {
      return [_LedgerSection(header: null, rows: movements)];
    }

    final sections = <_LedgerSection>[];
    DateTime? currentDay;
    var buffer = <StockMovement>[];

    for (final movement in movements) {
      final date = stockMovementStoreTime(
        movement.createdAt,
        storeTimezone: storeTimezone,
      );
      final day = DateTime(date.year, date.month, date.day);
      if (currentDay == null || day != currentDay) {
        if (buffer.isNotEmpty) {
          sections.add(
            _LedgerSection(
              header: _DaySummary(currentDay!, buffer, storeToday),
              rows: buffer,
            ),
          );
        }
        currentDay = day;
        buffer = <StockMovement>[];
      }
      buffer.add(movement);
    }
    if (buffer.isNotEmpty && currentDay != null) {
      sections.add(
        _LedgerSection(
          header: _DaySummary(currentDay, buffer, storeToday),
          rows: buffer,
        ),
      );
    }
    return sections;
  }
}

class _CompactLedgerSortBar extends StatelessWidget {
  const _CompactLedgerSortBar({
    required this.sortKey,
    required this.ascending,
    required this.onSort,
  });

  final MovementSortKey sortKey;
  final bool ascending;
  final void Function(MovementSortKey key) onSort;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final field = sortKey == MovementSortKey.date ? 'Fecha' : 'Cambio';
    final direction = ascending ? 'ascendente' : 'descendente';

    return Container(
      constraints: const BoxConstraints(minHeight: 48),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(bottom: BorderSide(color: colors.outlineVariant)),
      ),
      alignment: Alignment.centerRight,
      child: PopupMenuButton<MovementSortKey>(
        tooltip: 'Cambiar orden de movimientos',
        onSelected: onSort,
        itemBuilder: (context) => const [
          PopupMenuItem(
            value: MovementSortKey.date,
            height: 48,
            child: Text('Ordenar por fecha'),
          ),
          PopupMenuItem(
            value: MovementSortKey.change,
            height: 48,
            child: Text('Ordenar por cambio'),
          ),
        ],
        child: Semantics(
          button: true,
          label: 'Orden actual: $field, $direction',
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.sort, size: 18),
                const SizedBox(width: 8),
                Text(
                  'Orden: $field',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  ascending ? Icons.arrow_upward : Icons.arrow_downward,
                  size: 15,
                  color: colors.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LedgerSection {
  const _LedgerSection({required this.header, required this.rows});
  final _DaySummary? header;
  final List<StockMovement> rows;
}

class _DaySummary {
  _DaySummary(this.day, List<StockMovement> rows, this.today)
      : net = rows.fold(0, (total, row) => total + row.summaryQuantity);

  final DateTime day;
  final DateTime today;
  final int net;

  // Written out rather than taken from DateFormat with an 'es' locale: that
  // locale is not initialised in this app, so asking for it throws while the
  // header is building and the whole ledger renders empty.
  static const _weekdays = ['lun', 'mar', 'mié', 'jue', 'vie', 'sáb', 'dom'];
  static const _months = [
    'enero',
    'febrero',
    'marzo',
    'abril',
    'mayo',
    'junio',
    'julio',
    'agosto',
    'septiembre',
    'octubre',
    'noviembre',
    'diciembre',
  ];

  String get label {
    final justToday = DateTime(today.year, today.month, today.day);
    final difference = justToday.difference(day).inDays;
    if (difference == 0) return 'Hoy';
    if (difference == 1) return 'Ayer';
    final weekday = _weekdays[(day.weekday - 1) % 7];
    final month = _months[day.month - 1];
    final year = day.year == today.year ? '' : ' ${day.year}';
    return '$weekday ${day.day} de $month$year';
  }
}

class _DayHeaderDelegate extends SliverPersistentHeaderDelegate {
  const _DayHeaderDelegate(this.summary);

  final _DaySummary summary;

  @override
  double get minExtent => 30;
  @override
  double get maxExtent => 30;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlaps) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final net = summary.net;
    return Container(
      color: colors.surfaceContainerLow,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      alignment: Alignment.centerLeft,
      child: Row(
        children: [
          Expanded(
            child: Text(
              summary.label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: colors.onSurfaceVariant,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3,
              ),
            ),
          ),
          Text(
            net >= 0 ? '+$net' : '$net',
            style: theme.textTheme.labelSmall?.copyWith(
              color: colors.onSurfaceVariant,
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _DayHeaderDelegate old) =>
      old.summary.day != summary.day || old.summary.net != summary.net;
}

class _LedgerHeaderBar extends StatelessWidget {
  const _LedgerHeaderBar({
    required this.showProduct,
    required this.showReference,
    required this.showSku,
    required this.sortKey,
    required this.ascending,
    required this.onSort,
  });

  final bool showProduct;
  final bool showReference;
  final bool showSku;
  final MovementSortKey sortKey;
  final bool ascending;
  final void Function(MovementSortKey key) onSort;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Container(
      height: 36,
      padding: const EdgeInsets.only(left: 16, right: 16),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(bottom: BorderSide(color: colors.outlineVariant)),
      ),
      child: Row(
        children: [
          const SizedBox(width: 4),
          _SortableHeader(
            label: 'Hora',
            width: 56,
            active: sortKey == MovementSortKey.date,
            ascending: ascending,
            onTap: () => onSort(MovementSortKey.date),
          ),
          if (showProduct)
            const Expanded(flex: 5, child: _HeaderLabel('Producto')),
          const Expanded(flex: 4, child: _HeaderLabel('Movimiento')),
          if (showReference)
            const Expanded(flex: 3, child: _HeaderLabel('Referencia')),
          _SortableHeader(
            label: 'Cambio',
            width: 96,
            alignEnd: true,
            active: sortKey == MovementSortKey.change,
            ascending: ascending,
            onTap: () => onSort(MovementSortKey.change),
          ),
          const SizedBox(
            width: 118,
            child: _HeaderLabel('Saldo', alignEnd: true),
          ),
          const SizedBox(width: 36),
        ],
      ),
    );
  }
}

class _HeaderLabel extends StatelessWidget {
  const _HeaderLabel(this.text, {this.alignEnd = false});

  final String text;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      text.toUpperCase(),
      textAlign: alignEnd ? TextAlign.right : TextAlign.left,
      style: theme.textTheme.labelSmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.4,
        fontSize: 11,
      ),
    );
  }
}

/// A column header that carries its own sort affordance.
///
/// The label is the hit target — a separate icon button beside it would be a
/// second thing to aim at for one intent.
class _SortableHeader extends StatefulWidget {
  const _SortableHeader({
    required this.label,
    required this.width,
    required this.active,
    required this.ascending,
    required this.onTap,
    this.alignEnd = false,
  });

  final String label;
  final double width;
  final bool active;
  final bool ascending;
  final VoidCallback onTap;
  final bool alignEnd;

  @override
  State<_SortableHeader> createState() => _SortableHeaderState();
}

class _SortableHeaderState extends State<_SortableHeader> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    // The inactive arrow appears on hover so the column advertises that it can
    // be sorted without printing an arrow on every header forever.
    final showArrow = widget.active || _hovered;

    return SizedBox(
      width: widget.width,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          behavior: HitTestBehavior.opaque,
          child: Row(
            mainAxisAlignment: widget.alignEnd
                ? MainAxisAlignment.end
                : MainAxisAlignment.start,
            children: [
              Flexible(
                  child: _HeaderLabel(widget.label, alignEnd: widget.alignEnd)),
              const SizedBox(width: 3),
              AnimatedOpacity(
                duration: const Duration(milliseconds: 120),
                opacity: showArrow ? (widget.active ? 1 : 0.4) : 0,
                child: AnimatedRotation(
                  duration: const Duration(milliseconds: 180),
                  turns: widget.ascending ? 0.5 : 0,
                  child: Icon(
                    Icons.arrow_downward,
                    size: 13,
                    color: widget.active
                        ? colors.primary
                        : colors.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LedgerRow extends StatefulWidget {
  const _LedgerRow({
    required this.movement,
    required this.stacked,
    required this.showProduct,
    required this.showReference,
    required this.showSku,
    required this.chronological,
    required this.selected,
    required this.storeTimezone,
    required this.onOpen,
  });

  final StockMovement movement;
  final bool stacked;
  final bool showProduct;
  final bool showReference;
  final bool showSku;
  final bool chronological;
  final bool selected;
  final String storeTimezone;
  final VoidCallback onOpen;

  @override
  State<_LedgerRow> createState() => _LedgerRowState();
}

class _LedgerRowState extends State<_LedgerRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final movement = widget.movement;
    final change = movement.summaryQuantity;

    final background = widget.selected
        ? colors.secondaryContainer
        : _hovered
            ? colors.surfaceContainerLow
            : Colors.transparent;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onOpen,
        behavior: HitTestBehavior.opaque,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: background,
            border: Border(bottom: BorderSide(color: colors.outlineVariant)),
          ),
          child: Row(
            children: [
              // Integrity is a state, not an event: a quiet rule in the gutter
              // rather than a coloured badge shouting on every affected row.
              SizedBox(
                width: 4,
                child: movement.hasIntegrityWarning
                    ? Center(
                        child: Container(
                          width: 3,
                          height: 20,
                          decoration: BoxDecoration(
                            color: colors.tertiary,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      )
                    : null,
              ),
              Expanded(
                child: widget.stacked
                    ? _buildStacked(theme, movement, change)
                    : _buildTabular(theme, movement, change),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTabular(ThemeData theme, StockMovement movement, int change) {
    final colors = theme.colorScheme;
    final storeCreatedAt = stockMovementStoreTime(
      movement.createdAt,
      storeTimezone: widget.storeTimezone,
    );
    return Padding(
      padding: const EdgeInsets.only(left: 12, right: 16),
      child: Row(
        children: [
          SizedBox(
            width: 56,
            child: Text(
              DateFormat('HH:mm').format(storeCreatedAt),
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          if (widget.showProduct)
            Expanded(
              flex: 5,
              child: _ProductCell(movement: movement, showSku: widget.showSku),
            ),
          Expanded(
            flex: 4,
            child: _MovementCell(movement: movement),
          ),
          if (widget.showReference)
            Expanded(
              flex: 3,
              child: _ReferenceCell(movement: movement),
            ),
          SizedBox(width: 96, child: _ChangeText(change: change)),
          SizedBox(
            width: 118,
            child: _BalanceText(
              movement: movement,
              chronological: widget.chronological,
            ),
          ),
          SizedBox(
            width: 36,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 120),
              opacity: _hovered ? 1 : 0,
              child: Icon(
                Icons.chevron_right,
                size: 18,
                color: colors.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Compact: two lines, and a fixed trailing gutter.
  ///
  /// The gutter is the point — every delta and every balance stacks down the
  /// list at the same x, so the column can still be read vertically on a phone.
  Widget _buildStacked(ThemeData theme, StockMovement movement, int change) {
    final colors = theme.colorScheme;
    final storeCreatedAt = stockMovementStoreTime(
      movement.createdAt,
      storeTimezone: widget.storeTimezone,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  widget.showProduct
                      ? movement.productName
                      : movement.sourceDisplay,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${DateFormat('HH:mm').format(storeCreatedAt)}'
                  ' · ${movement.referenceDisplay}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 88,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _ChangeText(change: change, emphasized: true),
                const SizedBox(height: 1),
                Text(
                  '${movement.stockBefore} → ${movement.stockAfter}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colors.onSurfaceVariant,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Type, origin and — when the row has one — the reason its evidence is
/// partial, all in the space one column already had.
///
/// The origin alone ("Taller") loses that it was a sale; the type alone
/// ("Venta") loses where it happened. They are printed together only when they
/// actually differ, so no row ever reads "Venta · Venta". The integrity reason
/// returns as words: a mark in the gutter says something is worth checking, it
/// never says what.
class _MovementCell extends StatelessWidget {
  const _MovementCell({required this.movement});

  final StockMovement movement;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final type = movement.movementTypeDisplay.trim();
    final origin = movement.sourceDisplay.trim();
    // Containment, not equality: "Recepción · Recepción de compra" repeats its
    // first word just as loudly as "Venta · Venta" did.
    final lowerType = type.toLowerCase();
    final lowerOrigin = origin.toLowerCase();
    final overlapping =
        lowerOrigin.contains(lowerType) || lowerType.contains(lowerOrigin);
    final label = overlapping
        ? (origin.length >= type.length ? origin : type)
        : '$type · $origin';
    final reason = movement.hasIntegrityWarning
        ? _integrityReason(movement.integrityStatus)
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall?.copyWith(
            color: colors.onSurface,
            fontWeight: FontWeight.w600,
          ),
        ),
        if (reason != null)
          Text(
            reason,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              color: colors.tertiary,
              fontWeight: FontWeight.w600,
            ),
          ),
      ],
    );
  }

  static String _integrityReason(String status) {
    return switch (status) {
      'legacy_duplicate_footprint' => 'Huella duplicada',
      'legacy_purchase_reversal_collision' => 'Colisión de reversión',
      'legacy_ambiguous_adjustment_match' => 'Ajuste ambiguo',
      'ledger_source_balance_mismatch' => 'Saldo de origen no encadenado',
      'arithmetic_mismatch' => 'Aritmética inconsistente',
      _ => 'Evidencia parcial',
    };
  }
}

class _ProductCell extends StatelessWidget {
  const _ProductCell({required this.movement, required this.showSku});

  final StockMovement movement;
  final bool showSku;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final sku = movement.productSku;
    return Row(
      children: [
        Flexible(
          child: Text(
            movement.productName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        if (showSku && sku != null && sku.isNotEmpty) ...[
          const SizedBox(width: 8),
          Text(
            sku,
            style: theme.textTheme.labelSmall?.copyWith(
              color: colors.onSurfaceVariant,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ],
    );
  }
}

/// The document that justifies the movement.
///
/// This is the row's evidence, so it is the last column a narrow window may
/// drop, never the first. The arrow appears only where there is somewhere to
/// go, and the whole number is the tap target.
class _ReferenceCell extends StatelessWidget {
  const _ReferenceCell({required this.movement});

  final StockMovement movement;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final navigable = movement.hasNavigableReference;

    return Align(
      alignment: Alignment.centerLeft,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              movement.referenceDisplay,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: navigable ? colors.primary : colors.onSurfaceVariant,
                fontWeight: FontWeight.w600,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          if (navigable) ...[
            const SizedBox(width: 5),
            Icon(Icons.north_east, size: 12, color: colors.primary),
          ],
        ],
      ),
    );
  }
}

class _ChangeText extends StatelessWidget {
  const _ChangeText({required this.change, this.emphasized = false});

  final int change;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Text(
      change >= 0 ? '+$change' : '$change',
      textAlign: TextAlign.right,
      style: (emphasized
              ? theme.textTheme.titleMedium
              : theme.textTheme.bodyMedium)
          ?.copyWith(
        color: change >= 0 ? colors.tertiary : colors.error,
        fontWeight: FontWeight.w700,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
  }
}

class _BalanceText extends StatelessWidget {
  const _BalanceText({required this.movement, required this.chronological});

  final StockMovement movement;
  final bool chronological;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    // Under a ranked order the balance is still true for its own row but no
    // longer describes a sequence, so it steps back rather than pretending to
    // be a running total.
    final reconstructed = movement.balanceProvenance != 'persisted_movement';
    // The transition, not just its result. A ledger line answers "what did this
    // leave behind"; printing only the closing balance makes the reader
    // reconstruct the opening one from the row above, which stops working the
    // moment the list is filtered or ranked.
    return Text.rich(
      textAlign: TextAlign.right,
      TextSpan(
        style: theme.textTheme.bodyMedium?.copyWith(
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
        children: [
          TextSpan(
            text: '${movement.stockBefore}',
            style: TextStyle(color: colors.onSurfaceVariant),
          ),
          TextSpan(
            text: ' → ',
            style: TextStyle(color: colors.outline),
          ),
          TextSpan(
            text: '${movement.stockAfter}',
            style: TextStyle(
              color: chronological ? colors.onSurface : colors.onSurfaceVariant,
              fontWeight: chronological ? FontWeight.w700 : FontWeight.w500,
              decoration: reconstructed ? TextDecoration.underline : null,
              decorationStyle: TextDecorationStyle.dotted,
              decorationColor: colors.outline,
            ),
          ),
        ],
      ),
    );
  }
}
