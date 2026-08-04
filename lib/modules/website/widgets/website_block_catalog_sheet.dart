import 'package:flutter/material.dart';

import '../../../shared/themes/vinabike_theme_roles.dart';
import '../models/website_block_catalog.dart';
import '../models/website_block_type.dart';

/// What the catalog sheet resolves to. Null means the operator cancelled.
@immutable
class WebsiteBlockCatalogSelection {
  const WebsiteBlockCatalogSelection({
    required this.type,
    required this.atIndex,
  });

  final WebsiteBlockType type;

  /// The canonical `atIndex` for `onAddBlock(type, atIndex:)`.
  final int atIndex;
}

/// `O-05 VbBottomSheet` geometry for the catalog, read from Design.
///
/// Design source: project `a0fa3196-6315-4b96-bde7-7cc801e7a74e`,
/// `Website Builder Responsive Authoring` t11 frame **11a** +
/// `handoff-t11/spec.json` geometry for 390:
/// `sheet_max_pct 60, search_field 48, chip 36, chip_hit 48, row 56,
/// handle 34x4, radius_top 14, insert_affordance 48`.
abstract final class WebsiteBlockCatalogSheetGeometry {
  static const double topRadius = 14;
  static const double handleWidth = 34;
  static const double handleHeight = 4;
  static const double titleSize = 14;

  /// `I-04 VbSearchField` at touch density.
  static const double searchFieldHeight = 48;

  /// `E-02 VbFilterChip`: painted 36, hit area 48.
  static const double chipHeight = 36;
  static const double chipHitHeight = 48;

  /// `F-04` · `trazo hairline1`. The chip draws its outline around the label,
  /// so the label is the pill minus that hairline top and bottom.
  static const double hairline = 1;

  /// What the chip's label must measure for the pill to paint [chipHeight].
  static const double chipLabelHeight = chipHeight - 2 * hairline;

  /// t11a · a catalog row is icon + name + one line, so it is taller than the
  /// 48 minimum. 56 is Design's number, not a rounding of the minimum.
  static const double rowHeight = 56;

  /// `O-05` · "Máx. 60% de alto; con más, es una página".
  static const double maxHeightFraction = 0.60;

  static double maxHeightFor(double availableHeight) =>
      availableHeight * maxHeightFraction;
}

/// Opens the shared block catalog and resolves to the chosen family plus the
/// exact index it must land on.
///
/// Contract, from t11 frame **11b** `preservation_contract`:
///
/// * cancelling resolves to null and performs **no** write, **no** history step
///   and **no** selection change — the caller does nothing at all;
/// * the sheet never writes: it returns a choice, and the caller invokes the
///   one canonical `onAddBlock`;
/// * it creates no provider of its own and reads no editor state.
Future<WebsiteBlockCatalogSelection?> showWebsiteBlockCatalogSheet({
  required BuildContext context,
  required Iterable<String> presentBlockTypes,
  WebsiteBlockInsertionAnchor? anchor,
  int fallbackIndex = 0,
}) {
  return showModalBottomSheet<WebsiteBlockCatalogSelection>(
    context: context,
    // The page stays visible above the sheet: the operator has to see the gap
    // they are inserting into.
    barrierColor: Colors.transparent,
    backgroundColor: Colors.transparent,
    elevation: 0,
    isScrollControlled: true,
    useSafeArea: false,
    builder: (sheetContext) => WebsiteBlockCatalogSheet(
      presentBlockTypes: presentBlockTypes.toList(growable: false),
      anchor: anchor,
      fallbackIndex: fallbackIndex,
    ),
  );
}

/// The `+ Agregar aquí` affordance that lives in a gap between blocks.
///
/// Design source: t11 frame **11a** — 48 tall, centred, `accentSoft` band with
/// an `accentBorder` hairline top and bottom, a 22 accent dot with a `+`, and
/// the label that names it. The rule the frame states: *"La entrada nace en la
/// posición: el + vive en el hueco, no en una barra global."*
///
/// It performs no write. It opens the shared catalog and, only if the operator
/// chose something, calls the one canonical `onAddBlock` exactly once.
class WebsiteInsertBlockAffordance extends StatelessWidget {
  const WebsiteInsertBlockAffordance({
    super.key,
    required this.anchor,
    required this.presentBlockTypes,
    required this.onAddBlock,
    this.fallbackIndex = 0,
  });

  /// Null only on an empty page.
  final WebsiteBlockInsertionAnchor? anchor;
  final List<String> presentBlockTypes;
  final int fallbackIndex;

  /// The canonical page-level command. This widget never touches a provider.
  final void Function(String blockType, {int? atIndex}) onAddBlock;

  /// t11a · `insert_affordance: 48`.
  static const double height = 48;

  @visibleForTesting
  static const Key affordanceKey = Key('website-insert-block-affordance');

  /// Distinguishes the affordances of a page in tests and in semantics.
  static Key keyForIndex(int index) =>
      Key('website-insert-block-affordance-$index');

  String get _semanticLabel {
    final target = anchor;
    if (target == null) return 'Agregar el primer bloque de la página';
    return 'Agregar bloque ${target.initialSide.label.toLowerCase()} '
        '${target.anchorTitle}';
  }

  Future<void> _open(BuildContext context) async {
    final selection = await showWebsiteBlockCatalogSheet(
      context: context,
      presentBlockTypes: presentBlockTypes,
      anchor: anchor,
      fallbackIndex: fallbackIndex,
    );
    // Cancelling is a true no-op: no write, no history, nothing to restore.
    if (selection == null) return;
    onAddBlock(selection.type.name, atIndex: selection.atIndex);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final roles = VinabikeThemeRoles.maybeOf(context);
    final accent = roles?.info.accent ?? theme.colorScheme.primary;
    final band = roles?.info.container ?? theme.colorScheme.primaryContainer;
    final border = roles?.info.border ?? theme.colorScheme.outlineVariant;
    final onAccent = roles?.info.onAccent ?? theme.colorScheme.onPrimary;

    return Semantics(
      button: true,
      label: _semanticLabel,
      child: InkWell(
        key: anchor == null
            ? WebsiteInsertBlockAffordance.affordanceKey
            : keyForIndex(anchor!.indexFor(anchor!.initialSide)),
        onTap: () => _open(context),
        child: Container(
          height: height,
          width: double.infinity,
          decoration: BoxDecoration(
            color: band,
            border: Border(
              top: BorderSide(color: border),
              bottom: BorderSide(color: border),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 22,
                height: 22,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Icon(Icons.add, size: 14, color: onAccent),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  'Agregar aquí',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: accent,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
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

/// The sheet body. Public so a widget test can mount it without a route.
class WebsiteBlockCatalogSheet extends StatefulWidget {
  const WebsiteBlockCatalogSheet({
    super.key,
    required this.presentBlockTypes,
    this.anchor,
    this.fallbackIndex = 0,
  });

  final List<String> presentBlockTypes;

  /// Null on an empty page: there is no block to be before or after, so the
  /// position control does not exist and [fallbackIndex] is used.
  final WebsiteBlockInsertionAnchor? anchor;
  final int fallbackIndex;

  @visibleForTesting
  static const Key sheetKey = Key('website-block-catalog-sheet');

  @visibleForTesting
  static const Key cancelKey = Key('website-block-catalog-cancel');

  @visibleForTesting
  static const Key searchKey = Key('website-block-catalog-search');

  @visibleForTesting
  static const Key positionKey = Key('website-block-catalog-position');

  @visibleForTesting
  static const Key emptyKey = Key('website-block-catalog-empty');

  @visibleForTesting
  static Key rowKeyFor(WebsiteBlockType type) =>
      Key('website-block-catalog-row-${type.name}');

  @visibleForTesting
  static Key chipKeyFor(String category) =>
      Key('website-block-catalog-chip-$category');

  @override
  State<WebsiteBlockCatalogSheet> createState() =>
      _WebsiteBlockCatalogSheetState();
}

class _WebsiteBlockCatalogSheetState extends State<WebsiteBlockCatalogSheet> {
  late WebsiteBlockInsertSide _side =
      widget.anchor?.initialSide ?? WebsiteBlockInsertSide.after;
  String _query = '';
  String _category = WebsiteBlockCatalog.allCategory;

  int get _atIndex => widget.anchor?.indexFor(_side) ?? widget.fallbackIndex;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final roles = VinabikeThemeRoles.maybeOf(context);
    final media = MediaQuery.of(context);

    // The keyboard is part of the geometry: the search field is the first
    // thing a phone operator touches, so the sheet is measured against the
    // height the keyboard leaves and is pushed above it.
    final keyboardInset = media.viewInsets.bottom;
    final available = media.size.height - keyboardInset;
    final maxHeight = WebsiteBlockCatalogSheetGeometry.maxHeightFor(
      available <= 0 ? media.size.height : available,
    );

    final categories = WebsiteBlockCatalog.categories(
      presentBlockTypes: widget.presentBlockTypes,
    );
    final entries = WebsiteBlockCatalog.filtered(
      presentBlockTypes: widget.presentBlockTypes,
      query: _query,
      category: _category,
    );

    return Padding(
      padding: EdgeInsets.only(bottom: keyboardInset),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Material(
          key: WebsiteBlockCatalogSheet.sheetKey,
          color: theme.colorScheme.surface,
          shadowColor: roles?.shadow ?? theme.shadowColor,
          elevation: 12,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(
              WebsiteBlockCatalogSheetGeometry.topRadius,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const _Handle(),
                _TitleRow(onCancel: () => Navigator.of(context).pop()),
                if (widget.anchor != null)
                  _PositionRow(
                    anchor: widget.anchor!,
                    side: _side,
                    onChanged: (value) => setState(() => _side = value),
                  ),
                _SearchRow(
                  onChanged: (value) => setState(() => _query = value),
                ),
                WebsiteBlockCategoryChips(
                  categories: categories,
                  selected: _category,
                  onSelected: (value) => setState(() => _category = value),
                ),
                Divider(height: 1, color: theme.dividerColor),
                Flexible(
                  child: entries.isEmpty
                      ? const _EmptyResults()
                      : ListView.separated(
                          shrinkWrap: true,
                          padding: EdgeInsets.zero,
                          itemCount: entries.length,
                          separatorBuilder: (_, __) =>
                              Divider(height: 1, color: theme.dividerColor),
                          itemBuilder: (context, index) => _CatalogRow(
                            entry: entries[index],
                            onSelected: () => Navigator.of(context).pop(
                              WebsiteBlockCatalogSelection(
                                type: entries[index].type,
                                atIndex: _atIndex,
                              ),
                            ),
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

class _Handle extends StatelessWidget {
  const _Handle();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 6),
      child: Center(
        child: Container(
          width: WebsiteBlockCatalogSheetGeometry.handleWidth,
          height: WebsiteBlockCatalogSheetGeometry.handleHeight,
          decoration: BoxDecoration(
            color: Theme.of(context).dividerColor,
            borderRadius: BorderRadius.circular(999),
          ),
        ),
      ),
    );
  }
}

class _TitleRow extends StatelessWidget {
  const _TitleRow({required this.onCancel});

  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 8, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Agregar bloque',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall?.copyWith(
                    fontSize: WebsiteBlockCatalogSheetGeometry.titleSize,
                    fontWeight: FontWeight.w600,
                  ) ??
                  const TextStyle(
                    fontSize: WebsiteBlockCatalogSheetGeometry.titleSize,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
          TextButton(
            key: WebsiteBlockCatalogSheet.cancelKey,
            onPressed: onCancel,
            child: const Text('Cancelar'),
          ),
        ],
      ),
    );
  }
}

/// t11a · `Posición` against one named block. Two options, both real: each
/// resolves to a different index, so the control is never decorative.
class _PositionRow extends StatelessWidget {
  const _PositionRow({
    required this.anchor,
    required this.side,
    required this.onChanged,
  });

  final WebsiteBlockInsertionAnchor anchor;
  final WebsiteBlockInsertSide side;
  final ValueChanged<WebsiteBlockInsertSide> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
      child: Row(
        key: WebsiteBlockCatalogSheet.positionKey,
        children: [
          Text(
            'Posición',
            style: theme.textTheme.labelMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: SegmentedButton<WebsiteBlockInsertSide>(
              showSelectedIcon: false,
              segments: [
                for (final value in WebsiteBlockInsertSide.values)
                  ButtonSegment<WebsiteBlockInsertSide>(
                    value: value,
                    label: Text(value.label, maxLines: 1),
                  ),
              ],
              selected: <WebsiteBlockInsertSide>{side},
              onSelectionChanged: (selection) => onChanged(selection.first),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              anchor.anchorTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelMedium,
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchRow extends StatelessWidget {
  const _SearchRow({required this.onChanged});

  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
      child: SizedBox(
        height: WebsiteBlockCatalogSheetGeometry.searchFieldHeight,
        child: TextField(
          key: WebsiteBlockCatalogSheet.searchKey,
          onChanged: onChanged,
          textInputAction: TextInputAction.search,
          decoration: const InputDecoration(
            isDense: true,
            prefixIcon: Icon(Icons.search, size: 18),
            hintText: 'Buscar bloque',
            border: OutlineInputBorder(),
          ),
        ),
      ),
    );
  }
}

/// `E-02 VbFilterChip` · painted 36, hit area 48.
///
/// The two numbers belong to different things and must not be produced by the
/// same box. The chip **paints** 36 because its label owns that height and its
/// own padding is zero; it is **touchable** across 48 because
/// `MaterialTapTargetSize.padded` makes `RawChip` wrap itself in a hit
/// redirector of at least `kMinInteractiveDimension` and route every tap in
/// that area to the chip.
///
/// An outer `SizedBox(height: 36)` used to sit between the two: it clamped the
/// redirector to the painted height, so the surrounding 48 was empty space and
/// the real target was 36 — below the touch minimum and against t11a. Padding a
/// control from the outside never grows its target; only the control can.
///
/// There is exactly ONE interactive owner: the `ChoiceChip`. No second detector
/// wraps it, so a tap can be handled once and only once, and the semantics node
/// with the selected state is the chip's own.
@visibleForTesting
class WebsiteBlockCategoryChips extends StatelessWidget {
  const WebsiteBlockCategoryChips({
    super.key,
    required this.categories,
    required this.selected,
    required this.onSelected,
  });

  final List<String> categories;
  final String selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: WebsiteBlockCatalogSheetGeometry.chipHitHeight,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        itemCount: categories.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (context, index) {
          final category = categories[index];
          return ChoiceChip(
            key: WebsiteBlockCatalogSheet.chipKeyFor(category),
            // The painted band lives INSIDE the chip, so no ancestor box can
            // shrink the chip's own tap redirector. The chip lays its outline
            // out around the label, so the label carries the pill height minus
            // that hairline on each edge and the painted pill lands on `F-04`'s
            // 36 exactly.
            label: SizedBox(
              height: WebsiteBlockCatalogSheetGeometry.chipLabelHeight,
              child: Center(
                child: Text(
                  category,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            labelPadding: const EdgeInsets.symmetric(horizontal: 12),
            padding: EdgeInsets.zero,
            selected: category == selected,
            onSelected: (_) => onSelected(category),
            materialTapTargetSize: MaterialTapTargetSize.padded,
          );
        },
      ),
    );
  }
}

class _CatalogRow extends StatelessWidget {
  const _CatalogRow({required this.entry, required this.onSelected});

  final WebsiteBlockCatalogEntry entry;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final roles = VinabikeThemeRoles.maybeOf(context);
    final enabled = entry.isInsertable;
    final foreground = enabled
        ? theme.colorScheme.onSurface
        : (roles?.disabledForeground ??
            theme.colorScheme.onSurface.withValues(alpha: 0.38));
    // A disabled family says why in the line that would have described it.
    final secondary = enabled
        ? entry.description
        : (entry.unavailableReason ?? entry.description);

    return Semantics(
      button: true,
      enabled: enabled,
      label: enabled ? entry.title : '${entry.title}. $secondary',
      child: InkWell(
        key: WebsiteBlockCatalogSheet.rowKeyFor(entry.type),
        onTap: enabled ? onSelected : null,
        child: Opacity(
          opacity: enabled ? 1 : 0.55,
          child: Container(
            constraints: const BoxConstraints(
              minHeight: WebsiteBlockCatalogSheetGeometry.rowHeight,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            child: Row(
              children: [
                Icon(entry.icon, size: 18, color: foreground),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: foreground,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Text(
                        secondary,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontSize: 11,
                        ),
                      ),
                    ],
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

class _EmptyResults extends StatelessWidget {
  const _EmptyResults();

  @override
  Widget build(BuildContext context) {
    return Padding(
      key: WebsiteBlockCatalogSheet.emptyKey,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
      child: Text(
        'Ningún bloque coincide con esa búsqueda.',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodyMedium,
      ),
    );
  }
}
