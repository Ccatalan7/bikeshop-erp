import 'package:flutter/material.dart';

import 'seo_center_scope_rail.dart';
import 'seo_readiness_badge.dart';

/// Content width below which a row stacks instead of laying out in one line.
///
/// Measured from the tile's own constraints, not from the window, so an
/// embedded or split composition behaves like the width it actually received.
const double kSeoRowStackWidth = 600;

/// A labelled read-only fact shown in the detail body.
@immutable
class SeoCenterFact {
  const SeoCenterFact({
    required this.label,
    required this.value,
    this.tone,
  });

  final String label;
  final String value;

  /// Optional emphasis. Use [SeoBadgeTone.attention] only for a fact that
  /// contradicts the owner's apparent intent.
  final SeoBadgeTone? tone;
}

/// A non-destructive jump to the canonical owner of a value.
///
/// The SEO center never edits; it routes. The opened surface owns its own
/// return contract.
@immutable
class SeoCenterHandoff {
  const SeoCenterHandoff({
    required this.label,
    required this.route,
    this.icon = Icons.open_in_new_rounded,
    this.helper,
  });

  final String label;

  /// Absolute application route pushed with `context.push`.
  final String route;

  final IconData icon;

  /// One line naming the owner, e.g. "Catálogo web > Categorías".
  final String? helper;
}

/// One row of a scope.
///
/// The three planes are optional because some rows describe a metadata value
/// (site title, site description) rather than an addressable public surface.
@immutable
class SeoCenterEntityRow {
  const SeoCenterEntityRow({
    required this.id,
    required this.title,
    this.subtitle,
    this.source,
    this.appEligibility,
    this.buildInclusion,
    this.googleIndex,
    this.facts = const [],
    this.handoff,
    this.needsAttention = false,
  });

  final String id;
  final String title;

  /// Route, SKU or slug. Shown under the title in a muted weight.
  final String? subtitle;

  /// Where the effective metadata comes from: `Propio`, `Heredado`,
  /// `Generado`. Absence of an override is never rendered as "falta".
  final SeoBadgeState? source;

  final SeoBadgeState? appEligibility;
  final SeoBadgeState? buildInclusion;
  final SeoBadgeState? googleIndex;

  final List<SeoCenterFact> facts;
  final SeoCenterHandoff? handoff;

  /// Drives the scope counter and the "Solo con atención" filter.
  final bool needsAttention;

  bool get hasPlanes =>
      appEligibility != null && buildInclusion != null && googleIndex != null;

  bool matches(String query) {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) return true;
    return title.toLowerCase().contains(normalized) ||
        (subtitle ?? '').toLowerCase().contains(normalized);
  }
}

/// Scope-level header shown above the rows.
@immutable
class SeoCenterOverview {
  const SeoCenterOverview({
    required this.title,
    this.subtitle,
    this.facts = const [],
    this.appEligibility,
    this.buildInclusion,
    this.googleIndex,
    this.handoff,
  });

  final String title;
  final String? subtitle;
  final List<SeoCenterFact> facts;
  final SeoBadgeState? appEligibility;
  final SeoBadgeState? buildInclusion;
  final SeoBadgeState? googleIndex;
  final SeoCenterHandoff? handoff;

  bool get hasPlanes =>
      appEligibility != null && buildInclusion != null && googleIndex != null;
}

/// A neutral counter shown in the scope summary.
///
/// Wording is the caller's responsibility. A deliberate owner decision — such
/// as 128 hidden collections — must read as scope, never as a deficit, and
/// must never be expressed as a percentage or progress bar.
@immutable
class SeoCenterSummaryCount {
  const SeoCenterSummaryCount({
    required this.label,
    required this.value,
    this.tone = SeoBadgeTone.neutral,
  });

  final String label;
  final String value;
  final SeoBadgeTone tone;
}

/// Everything the SEO center knows about one scope.
@immutable
class SeoCenterGroup {
  const SeoCenterGroup({
    required this.scope,
    required this.summary,
    this.counts = const [],
    this.overview,
    this.rows = const [],
    this.partialError,
    this.emptyTitle = 'Sin elementos',
    this.emptyDescription = 'Este ámbito no tiene elementos que mostrar.',
  });

  final SeoCenterScope scope;

  /// One sentence describing the current scope neutrally.
  final String summary;

  final List<SeoCenterSummaryCount> counts;
  final SeoCenterOverview? overview;
  final List<SeoCenterEntityRow> rows;

  /// A degraded but non-fatal read. Rendered as a visible notice; the rest of
  /// the scope still renders with honest `unknown` states.
  final String? partialError;

  final String emptyTitle;
  final String emptyDescription;

  int get attentionCount => rows.where((row) => row.needsAttention).length;
}

/// Master list for one scope.
///
/// Search text, the attention filter, the selected row and the scroll
/// controller all belong to the host page, per the navigation-preservation
/// contract. This widget only renders and reports intent.
class SeoCenterList extends StatelessWidget {
  const SeoCenterList({
    super.key,
    required this.group,
    required this.query,
    required this.searchController,
    required this.onQueryChanged,
    required this.onlyAttention,
    required this.onOnlyAttentionChanged,
    required this.onRowSelected,
    required this.onHandoff,
    this.selectedRowId,
    this.scrollController,
    this.leading,
  });

  final SeoCenterGroup group;
  final String query;

  /// Owned by the host page so the query survives scope and detail round
  /// trips.
  final TextEditingController searchController;

  final ValueChanged<String> onQueryChanged;
  final bool onlyAttention;
  final ValueChanged<bool> onOnlyAttentionChanged;
  final ValueChanged<SeoCenterEntityRow> onRowSelected;
  final ValueChanged<SeoCenterHandoff> onHandoff;
  final String? selectedRowId;
  final ScrollController? scrollController;

  /// Optional scope-owned block placed between the overview and the filters.
  ///
  /// Used by the site scope for its Google operations. It scrolls with the
  /// list at every width, so a compact viewport never has to choose between
  /// the actions and the rows.
  final Widget? leading;

  List<SeoCenterEntityRow> get visibleRows => group.rows
      .where((row) => !onlyAttention || row.needsAttention)
      .where((row) => row.matches(query))
      .toList(growable: false);

  @override
  Widget build(BuildContext context) {
    final rows = visibleRows;
    final showFilters = group.rows.length > 6;

    return CustomScrollView(
      controller: scrollController,
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(0, 0, 0, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _ScopeSummary(group: group),
                if (group.partialError != null) ...[
                  const SizedBox(height: 12),
                  _PartialErrorNotice(message: group.partialError!),
                ],
                if (group.overview != null) ...[
                  const SizedBox(height: 16),
                  SeoCenterOverviewPanel(
                    overview: group.overview!,
                    onHandoff: onHandoff,
                  ),
                ],
                if (leading != null) ...[
                  const SizedBox(height: 16),
                  leading!,
                ],
                if (showFilters) ...[
                  const SizedBox(height: 16),
                  _ListFilters(
                    searchController: searchController,
                    onQueryChanged: onQueryChanged,
                    onlyAttention: onlyAttention,
                    onOnlyAttentionChanged: onOnlyAttentionChanged,
                    attentionCount: group.attentionCount,
                  ),
                ],
              ],
            ),
          ),
        ),
        if (rows.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: _ListEmptyState(
              group: group,
              filtered: query.trim().isNotEmpty || onlyAttention,
            ),
          )
        else
          SliverList.builder(
            itemCount: rows.length,
            itemBuilder: (context, index) {
              final row = rows[index];
              return SeoCenterRowTile(
                row: row,
                isSelected: row.id == selectedRowId,
                isFirst: index == 0,
                onTap: () => onRowSelected(row),
              );
            },
          ),
      ],
    );
  }
}

class _ScopeSummary extends StatelessWidget {
  const _ScopeSummary({required this.group});

  final SeoCenterGroup group;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          group.scope.label,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        SeoCollapsibleText(
          text: group.summary,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            height: 1.35,
          ),
        ),
        if (group.counts.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final count in group.counts)
                SeoReadinessBadge(
                  state: SeoBadgeState(
                    label: '${count.value} ${count.label}',
                    tone: count.tone,
                  ),
                  compact: true,
                ),
            ],
          ),
        ],
      ],
    );
  }
}

/// Explanatory copy that clamps itself on compact widths.
///
/// A list header must not push every record out of the first screen on a
/// phone. Nothing is removed: the full text is one tap away, and above
/// [kSeoRowStackWidth] it is never clamped at all.
class SeoCollapsibleText extends StatefulWidget {
  const SeoCollapsibleText({
    super.key,
    required this.text,
    this.style,
    this.collapsedMaxLines = 2,
  });

  final String text;
  final TextStyle? style;
  final int collapsedMaxLines;

  @override
  State<SeoCollapsibleText> createState() => _SeoCollapsibleTextState();
}

class _SeoCollapsibleTextState extends State<SeoCollapsibleText> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final clamps = constraints.maxWidth < kSeoRowStackWidth && !_expanded;
        final painter = TextPainter(
          text: TextSpan(text: widget.text, style: widget.style),
          maxLines: widget.collapsedMaxLines,
          textDirection: Directionality.of(context),
        )..layout(maxWidth: constraints.maxWidth);
        final overflows = painter.didExceedMaxLines;
        painter.dispose();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.text,
              style: widget.style,
              maxLines: clamps ? widget.collapsedMaxLines : null,
              overflow: clamps ? TextOverflow.ellipsis : TextOverflow.clip,
            ),
            if (overflows && constraints.maxWidth < kSeoRowStackWidth)
              Semantics(
                button: true,
                expanded: _expanded,
                excludeSemantics: true,
                label: _expanded ? 'Ver menos' : 'Ver más',
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => setState(() => _expanded = !_expanded),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 44),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          _expanded ? 'Ver menos' : 'Ver más',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _PartialErrorNotice extends StatelessWidget {
  const _PartialErrorNotice({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: theme.colorScheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline_rounded,
            size: 19,
            color: theme.colorScheme.onTertiaryContainer,
          ),
          const SizedBox(width: 11),
          Expanded(
            child: SeoCollapsibleText(
              text: message,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onTertiaryContainer,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ListFilters extends StatelessWidget {
  const _ListFilters({
    required this.searchController,
    required this.onQueryChanged,
    required this.onlyAttention,
    required this.onOnlyAttentionChanged,
    required this.attentionCount,
  });

  final TextEditingController searchController;
  final ValueChanged<String> onQueryChanged;
  final bool onlyAttention;
  final ValueChanged<bool> onOnlyAttentionChanged;
  final int attentionCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final search = TextField(
      controller: searchController,
      onChanged: onQueryChanged,
      decoration: const InputDecoration(
        isDense: true,
        prefixIcon: Icon(Icons.search_rounded, size: 19),
        hintText: 'Buscar por nombre o ruta',
      ),
    );

    final filter = FilterChip(
      selected: onlyAttention,
      onSelected: attentionCount == 0 ? null : onOnlyAttentionChanged,
      showCheckmark: false,
      avatar: Icon(
        Icons.warning_amber_rounded,
        size: 17,
        color: onlyAttention
            ? theme.colorScheme.onTertiaryContainer
            : theme.colorScheme.onSurfaceVariant,
      ),
      label: Text('Solo con atención ($attentionCount)'),
      selectedColor: theme.colorScheme.tertiaryContainer,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < kSeoRowStackWidth) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              search,
              const SizedBox(height: 10),
              filter,
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: search),
            const SizedBox(width: 12),
            filter,
          ],
        );
      },
    );
  }
}

class _ListEmptyState extends StatelessWidget {
  const _ListEmptyState({required this.group, required this.filtered});

  final SeoCenterGroup group;
  final bool filtered;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                filtered ? Icons.filter_alt_off_outlined : group.scope.icon,
                size: 34,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 12),
              Text(
                filtered ? 'Sin coincidencias' : group.emptyTitle,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                filtered
                    ? 'Ajusta la búsqueda o quita el filtro de atención.'
                    : group.emptyDescription,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One list row.
///
/// The tile measures its own constraints: above [kSeoRowStackWidth] identity
/// and badges share a line; below it the badges wrap under the identity. There
/// is no horizontal scroll at any width.
class SeoCenterRowTile extends StatelessWidget {
  const SeoCenterRowTile({
    super.key,
    required this.row,
    required this.onTap,
    this.isSelected = false,
    this.isFirst = false,
  });

  final SeoCenterEntityRow row;
  final VoidCallback onTap;
  final bool isSelected;
  final bool isFirst;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final identity = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          row.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        if (row.subtitle != null && row.subtitle!.isNotEmpty) ...[
          const SizedBox(height: 3),
          Text(
            row.subtitle!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        if (row.source != null) ...[
          const SizedBox(height: 7),
          Align(
            alignment: Alignment.centerLeft,
            child: SeoReadinessBadge(state: row.source!, compact: true),
          ),
        ],
      ],
    );

    final badges = row.hasPlanes
        ? SeoReadinessBadgeGroup(
            appEligibility: row.appEligibility!,
            buildInclusion: row.buildInclusion!,
            googleIndex: row.googleIndex!,
            compact: true,
          )
        : const SizedBox.shrink();

    return Semantics(
      selected: isSelected,
      button: true,
      child: Material(
        color: isSelected
            ? theme.colorScheme.primaryContainer
            : Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: theme.colorScheme.outlineVariant),
                bottom: isFirst
                    ? BorderSide.none
                    : BorderSide(color: theme.colorScheme.outlineVariant),
              ),
            ),
            constraints: const BoxConstraints(minHeight: 56),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth < kSeoRowStackWidth) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      identity,
                      if (row.hasPlanes) ...[
                        const SizedBox(height: 10),
                        badges,
                      ],
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(flex: 5, child: identity),
                    const SizedBox(width: 14),
                    Expanded(
                      flex: 6,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: badges,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 20,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// Scope-level header panel (used by the `Sitio` scope and any scope that
/// carries an aggregate state).
class SeoCenterOverviewPanel extends StatelessWidget {
  const SeoCenterOverviewPanel({
    super.key,
    required this.overview,
    required this.onHandoff,
  });

  final SeoCenterOverview overview;
  final ValueChanged<SeoCenterHandoff> onHandoff;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            overview.title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          if (overview.subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              overview.subtitle!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.35,
              ),
            ),
          ],
          if (overview.hasPlanes) ...[
            const SizedBox(height: 12),
            SeoReadinessBadgeGroup(
              appEligibility: overview.appEligibility!,
              buildInclusion: overview.buildInclusion!,
              googleIndex: overview.googleIndex!,
            ),
          ],
          if (overview.facts.isNotEmpty) ...[
            const SizedBox(height: 14),
            SeoCenterFactList(facts: overview.facts),
          ],
          if (overview.handoff != null) ...[
            const SizedBox(height: 14),
            Align(
              alignment: Alignment.centerLeft,
              child: SeoCenterHandoffButton(
                handoff: overview.handoff!,
                onHandoff: onHandoff,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Read-only label/value pairs.
class SeoCenterFactList extends StatelessWidget {
  const SeoCenterFactList({super.key, required this.facts});

  final List<SeoCenterFact> facts;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var index = 0; index < facts.length; index++) ...[
          if (index > 0)
            Divider(height: 17, color: theme.colorScheme.outlineVariant),
          LayoutBuilder(
            builder: (context, constraints) {
              final fact = facts[index];
              final label = Text(
                fact.label,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              );
              final value = fact.tone == null
                  ? Text(
                      fact.value,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        height: 1.3,
                      ),
                    )
                  : Align(
                      alignment: Alignment.centerLeft,
                      child: SeoReadinessBadge(
                        state: SeoBadgeState(
                          label: fact.value,
                          tone: fact.tone!,
                        ),
                        compact: true,
                      ),
                    );

              if (constraints.maxWidth < 420) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [label, const SizedBox(height: 4), value],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(width: 168, child: label),
                  const SizedBox(width: 12),
                  Expanded(child: value),
                ],
              );
            },
          ),
        ],
      ],
    );
  }
}

/// Primary non-destructive action of a row or overview.
class SeoCenterHandoffButton extends StatelessWidget {
  const SeoCenterHandoffButton({
    super.key,
    required this.handoff,
    required this.onHandoff,
  });

  final SeoCenterHandoff handoff;
  final ValueChanged<SeoCenterHandoff> onHandoff;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        OutlinedButton.icon(
          onPressed: () => onHandoff(handoff),
          icon: Icon(handoff.icon, size: 18),
          label: Text(handoff.label),
        ),
        if (handoff.helper != null) ...[
          const SizedBox(height: 6),
          Text(
            handoff.helper!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

/// Detail body for one row.
///
/// On desktop this renders in the right pane. On tablet and phone it replaces
/// the list body and shows [onBack], per the in-page navigation contract.
class SeoCenterDetail extends StatelessWidget {
  const SeoCenterDetail({
    super.key,
    required this.row,
    required this.onHandoff,
    this.onBack,
    this.scrollController,
  });

  final SeoCenterEntityRow row;
  final ValueChanged<SeoCenterHandoff> onHandoff;
  final VoidCallback? onBack;
  final ScrollController? scrollController;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      controller: scrollController,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (onBack != null) ...[
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: onBack,
                icon: const Icon(Icons.arrow_back_rounded, size: 18),
                label: const Text('Volver a la lista'),
              ),
            ),
            const SizedBox(height: 10),
          ],
          Text(
            row.title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          if (row.subtitle != null && row.subtitle!.isNotEmpty) ...[
            const SizedBox(height: 4),
            SelectableText(
              row.subtitle!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          if (row.source != null) ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: SeoReadinessBadge(state: row.source!),
            ),
          ],
          if (row.hasPlanes) ...[
            const SizedBox(height: 20),
            Divider(height: 1, color: theme.colorScheme.outlineVariant),
            const SizedBox(height: 18),
            SeoReadinessBadgeGroup(
              appEligibility: row.appEligibility!,
              buildInclusion: row.buildInclusion!,
              googleIndex: row.googleIndex!,
              showPlaneCaptions: true,
            ),
          ],
          if (row.facts.isNotEmpty) ...[
            const SizedBox(height: 20),
            Divider(height: 1, color: theme.colorScheme.outlineVariant),
            const SizedBox(height: 18),
            Text(
              'Detalle',
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            SeoCenterFactList(facts: row.facts),
          ],
          if (row.handoff != null) ...[
            const SizedBox(height: 22),
            SeoCenterHandoffButton(
              handoff: row.handoff!,
              onHandoff: onHandoff,
            ),
          ],
        ],
      ),
    );
  }
}

/// Placeholder shown in the desktop detail pane before a row is selected.
class SeoCenterDetailPlaceholder extends StatelessWidget {
  const SeoCenterDetailPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 300),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.travel_explore_outlined,
                size: 32,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 12),
              Text(
                'Selecciona un elemento',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                'Verás su elegibilidad, la evidencia del último build y lo que '
                'Google haya informado.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
