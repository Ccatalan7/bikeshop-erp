import 'package:flutter/material.dart';

import '../themes/vinabike_theme_roles.dart';

/// One destination of a [VbSubTabs] set.
@immutable
class VbSubTab<T> {
  const VbSubTab({required this.value, required this.label});

  final T value;
  final String label;
}

/// `T-04 VbSubTabs` — the universal owner for navigating between sets.
///
/// Design source: project `a0fa3196-6315-4b96-bde7-7cc801e7a74e`,
/// `GUÍA GENERAL Viñabike - Componentes` `T-04`, published through
/// `Website Builder Responsive Authoring` `handoff-t10/spec.json`
/// `subtabs_anatomy`:
///
/// > alto 32 (40 comfortable), subrayado accent 2 px sobre el hairline,
/// > label 12/600, sin fondos por tab, sin cápsulas, sin íconos
///
/// Every measurement below is that sentence. Nothing here is a module value:
/// the horizontal room a label needs is expressed as `F-04` spacing, not as a
/// gutter this widget invented.
///
/// **Why it is universal.** Two feature-local copies existed — the Website
/// Builder pane's tab bar and the `O-05` sheet's section tabs — with different
/// heights, different colours and different overflow behaviour (one had none).
/// `T-04` is one component; two implementations of it is how a pane and a
/// sheet start disagreeing about what "the same three sections" look like.
///
/// **Overflow is `O-01`, not compression.** A label is either readable at its
/// published size or it is in the drawer. Nothing shrinks, nothing scrolls
/// horizontally, and the active destination is always inline — navigation that
/// hides where you are is not navigation.
class VbSubTabs<T> extends StatelessWidget {
  const VbSubTabs({
    super.key,
    required this.tabs,
    required this.value,
    required this.onChanged,
    this.density = VbSubTabsDensity.compact,
    this.overflowTooltip = 'Más secciones',
  });

  final List<VbSubTab<T>> tabs;
  final T value;
  final ValueChanged<T> onChanged;
  final VbSubTabsDensity density;
  final String overflowTooltip;

  /// `T-04` · `alto 32`.
  static const double compactHeight = 32;

  /// `T-04` · `(40 comfortable)`.
  static const double comfortableHeight = 40;

  /// `T-04` · `subrayado accent 2 px`.
  static const double underline = 2;

  /// `T-04` · `label 12/600`.
  static const double labelSize = 12;
  static const FontWeight labelWeight = FontWeight.w600;

  /// `F-04` · the published spacing step used each side of a label. Not a
  /// gutter chosen here: it is the scale's `10`.
  static const double labelPadding = 10;

  /// `A-02` on a bar of this height — the overflow trigger's own box.
  static const double overflowWidth = 36;

  /// `F-06` · below 900 the density is touch and every target is 48.
  static const double touchTarget = 48;

  @visibleForTesting
  static const Key overflowKey = Key('vb-sub-tabs-overflow');

  @visibleForTesting
  static Key tabKey(Object? value) => Key('vb-sub-tab-$value');

  /// What the tab PAINTS. `T-04`'s own two heights.
  double get _paintedHeight => switch (density) {
        VbSubTabsDensity.compact => compactHeight,
        VbSubTabsDensity.comfortable => comfortableHeight,
      };

  /// What the tab can be HIT at.
  ///
  /// `T-04` publishes 40 as its comfortable height and `F-06` requires 48 for
  /// a touch target, and both are published — so the reconciliation is the one
  /// Design already published for chips in t11 11a (`chip: 36, chip_hit: 48`):
  /// paint the component's size, expand the touch area invisibly around it.
  /// The comfortable density is the touch one, so it takes the touch target;
  /// the compact density is a pointer surface and keeps its own height.
  double get _hitHeight => switch (density) {
        VbSubTabsDensity.compact => compactHeight,
        VbSubTabsDensity.comfortable => touchTarget,
      };

  /// Width one tab needs to render its label whole at the published size.
  static double measureTab(String label, TextScaler textScaler) {
    final painter = TextPainter(
      text: TextSpan(
        text: label,
        style: const TextStyle(
          fontSize: labelSize,
          fontWeight: labelWeight,
        ),
      ),
      textDirection: TextDirection.ltr,
      textScaler: textScaler,
    )..layout();
    return painter.width + labelPadding * 2;
  }

  /// How many of [tabs] fit inline, and which go to the drawer.
  ///
  /// Pure so a guard can assert the composition at any width without pumping
  /// the surface that hosts it.
  @visibleForTesting
  static ({List<T> inline, List<T> overflow}) split<T>({
    required List<VbSubTab<T>> tabs,
    required T value,
    required double maxWidth,
    TextScaler textScaler = TextScaler.noScaling,
  }) {
    final widths = <T, double>{
      for (final tab in tabs) tab.value: measureTab(tab.label, textScaler),
    };
    final total = widths.values.fold<double>(0, (sum, w) => sum + w);
    if (total <= maxWidth) {
      return (inline: [for (final tab in tabs) tab.value], overflow: <T>[]);
    }

    final budget = maxWidth - overflowWidth;
    final inline = <T>[];
    var used = 0.0;
    for (final tab in tabs) {
      final width = widths[tab.value]!;
      if (used + width <= budget) {
        inline.add(tab.value);
        used += width;
      }
    }
    if (!inline.contains(value) && tabs.any((t) => t.value == value)) {
      while (inline.isNotEmpty && used + widths[value]! > budget) {
        used -= widths[inline.removeLast()]!;
      }
      inline.add(value);
    }
    return (
      inline: inline,
      overflow: [
        for (final tab in tabs)
          if (!inline.contains(tab.value)) tab.value,
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final roles = VinabikeThemeRoles.maybeOf(context);
    final accent = roles?.info.accent ?? theme.colorScheme.primary;
    final activeColor = theme.colorScheme.onSurface;
    final idleColor = theme.colorScheme.onSurfaceVariant;
    final edge = theme.dividerColor;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        final layout = split<T>(
          tabs: tabs,
          value: value,
          maxWidth: width,
          textScaler: MediaQuery.textScalerOf(context),
        );
        final byValue = {for (final tab in tabs) tab.value: tab};

        return SizedBox(
          height: _hitHeight,
          child: Row(
            children: [
              for (final id in layout.inline)
                _VbSubTab<T>(
                  tab: byValue[id]!,
                  isActive: id == value,
                  paintedHeight: _paintedHeight,
                  hitHeight: _hitHeight,
                  accent: accent,
                  activeColor: activeColor,
                  idleColor: idleColor,
                  edge: edge,
                  onTap: () => onChanged(id),
                ),
              if (layout.overflow.isNotEmpty)
                _VbSubTabsOverflow<T>(
                  tabs: [for (final id in layout.overflow) byValue[id]!],
                  height: _hitHeight,
                  color: idleColor,
                  edge: edge,
                  tooltip: overflowTooltip,
                  onSelected: onChanged,
                ),
            ],
          ),
        );
      },
    );
  }
}

/// `F-06` · the two densities `T-04` publishes.
enum VbSubTabsDensity { compact, comfortable }

class _VbSubTab<T> extends StatelessWidget {
  const _VbSubTab({
    required this.tab,
    required this.isActive,
    required this.paintedHeight,
    required this.hitHeight,
    required this.accent,
    required this.activeColor,
    required this.idleColor,
    required this.edge,
    required this.onTap,
  });

  final VbSubTab<T> tab;
  final bool isActive;
  final double paintedHeight;
  final double hitHeight;
  final Color accent;
  final Color activeColor;
  final Color idleColor;
  final Color edge;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: isActive,
      label: tab.label,
      child: InkWell(
        key: VbSubTabs.tabKey(tab.value),
        onTap: onTap,
        child: Container(
          // The hit area is the outer box; the published row is painted at the
          // bottom of it so the underline still lands on the content boundary.
          height: hitHeight,
          alignment: Alignment.bottomCenter,
          child: Container(
            height: paintedHeight,
            padding: const EdgeInsets.symmetric(
              horizontal: VbSubTabs.labelPadding,
            ),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              // `T-04` · the underline sits ON the hairline and only the active
              // tab paints it. No per-tab background, no capsule.
              border: Border(
                bottom: BorderSide(
                  color: isActive ? accent : edge,
                  width: isActive ? VbSubTabs.underline : 1,
                ),
              ),
            ),
            child: Text(
              tab.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: isActive ? activeColor : idleColor,
                fontSize: VbSubTabs.labelSize,
                fontWeight: VbSubTabs.labelWeight,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// `O-01 VbMenu` · the destinations the bar could not show whole.
class _VbSubTabsOverflow<T> extends StatelessWidget {
  const _VbSubTabsOverflow({
    required this.tabs,
    required this.height,
    required this.color,
    required this.edge,
    required this.tooltip,
    required this.onSelected,
  });

  final List<VbSubTab<T>> tabs;
  final double height;
  final Color color;
  final Color edge;
  final String tooltip;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: VbSubTabs.overflowWidth,
      height: height,
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: edge)),
      ),
      child: PopupMenuButton<T>(
        key: VbSubTabs.overflowKey,
        tooltip: tooltip,
        padding: EdgeInsets.zero,
        onSelected: onSelected,
        itemBuilder: (context) => [
          for (final tab in tabs)
            PopupMenuItem<T>(value: tab.value, child: Text(tab.label)),
        ],
        child: Icon(
          Icons.more_horiz,
          size: 16,
          color: color,
          semanticLabel: tooltip,
        ),
      ),
    );
  }
}
