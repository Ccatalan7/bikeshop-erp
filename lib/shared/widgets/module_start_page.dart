import 'package:flutter/material.dart';

import '../themes/vinabike_theme_roles.dart';

/// The start page of a module: the entry to its workspaces.
///
/// The owner's definition (2026-10-14): a module's start page presents its
/// workspaces for orderly navigation, with almost no metrics. One continuous
/// page — a full-bleed band on the workspace chrome with the module's state
/// and at most four figures, then the workspaces in columns split by
/// hairlines. No floating cards, no slogan, no decoration; colour names a
/// group (the theme's identity tones) and never paints a figure. Sitio web
/// and Configuración are built from these pieces; a third start page reuses
/// them instead of drawing its own.

/// The page's horizontal gutter: the band, the title and the rows share it.
double moduleStartGutter(bool phone) => phone ? 16 : 40;

const _tabular = [FontFeature.tabularFigures()];

enum ModuleStartCaptionTone { muted, positive, attention }

enum ModuleStartValueKind { number, text }

/// One figure of the band. It opens the page that owns it.
@immutable
class ModuleStartFigure {
  const ModuleStartFigure({
    required this.key,
    required this.label,
    required this.shortLabel,
    required this.value,
    required this.caption,
    required this.onTap,
    this.captionTone = ModuleStartCaptionTone.muted,
    this.kind = ModuleStartValueKind.number,
  });

  final Key key;
  final String label;

  /// The label under the value on a phone, where four sit in one row.
  final String shortLabel;

  /// Null while it loads; shown as «—».
  final String? value;
  final String? caption;
  final ModuleStartCaptionTone captionTone;
  final ModuleStartValueKind kind;
  final VoidCallback onTap;
}

/// The band on the workspace chrome, edge to edge: [lead] (who or what is in
/// front of the operator), [actions], and the figures below on one row.
class ModuleStartBand extends StatelessWidget {
  const ModuleStartBand({
    super.key,
    required this.phone,
    required this.lead,
    required this.actions,
    required this.figures,
    this.phoneFigures,
  });

  final bool phone;
  final Widget lead;
  final List<Widget> actions;
  final List<ModuleStartFigure> figures;

  /// The figures a phone shows when they differ from [figures].
  final List<ModuleStartFigure>? phoneFigures;

  /// The band's main action: light on the chrome.
  static ButtonStyle primaryStyle(BuildContext context, {required bool phone}) {
    final shell = VinabikeThemeRoles.of(context).shell;
    return FilledButton.styleFrom(
      backgroundColor: shell.foreground,
      foregroundColor: shell.canvas,
      minimumSize: const Size(44, 44),
      padding: EdgeInsets.symmetric(horizontal: phone ? 14 : 18),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      textStyle: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700),
    );
  }

  /// A secondary action on the chrome: outlined by the chrome's edge.
  static ButtonStyle outlineStyle(BuildContext context) {
    final shell = VinabikeThemeRoles.of(context).shell;
    return OutlinedButton.styleFrom(
      foregroundColor: shell.foreground,
      side: BorderSide(color: shell.edge),
      minimumSize: const Size(44, 44),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
    );
  }

  @override
  Widget build(BuildContext context) {
    final shell = VinabikeThemeRoles.of(context).shell;
    final gutter = moduleStartGutter(phone);
    final cells = phone ? (phoneFigures ?? figures) : figures;
    return ColoredBox(
      color: shell.canvas,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: gutter,
              vertical: phone ? 9 : 18,
            ),
            child: Row(
              children: [
                Expanded(child: lead),
                SizedBox(width: phone ? 12 : 24),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: actions,
                ),
              ],
            ),
          ),
          if (cells.isNotEmpty)
            DecoratedBox(
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: shell.edge)),
              ),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final perRow =
                      phone || constraints.maxWidth >= 1100 ? cells.length : 2;
                  final rows = <Widget>[];
                  for (var start = 0; start < cells.length; start += perRow) {
                    final end = (start + perRow).clamp(0, cells.length);
                    rows.add(
                      IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (var i = start; i < end; i++)
                              Expanded(
                                child: _FigureFrame(
                                  first: i == start,
                                  topEdge: start > 0,
                                  leading: i == start ? gutter : null,
                                  phone: phone,
                                  figure: cells[i],
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  }
                  return Column(children: rows);
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _FigureFrame extends StatelessWidget {
  const _FigureFrame({
    required this.first,
    required this.topEdge,
    required this.leading,
    required this.phone,
    required this.figure,
  });

  final bool first;
  final bool topEdge;
  final double? leading;
  final bool phone;
  final ModuleStartFigure figure;

  @override
  Widget build(BuildContext context) {
    final shell = VinabikeThemeRoles.of(context).shell;
    final shown = figure.value ?? '—';
    final toneColor = switch (figure.captionTone) {
      ModuleStartCaptionTone.muted => null,
      ModuleStartCaptionTone.positive => shell.positive,
      ModuleStartCaptionTone.attention => shell.dirty,
    };
    final text = figure.kind == ModuleStartValueKind.text;
    final Widget body;
    if (phone) {
      body = Padding(
        padding: EdgeInsets.fromLTRB(first ? (leading ?? 12) : 12, 7, 8, 9),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              shown,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: toneColor ?? shell.foreground,
                fontSize: text ? 15.5 : 18,
                fontWeight: FontWeight.w600,
                fontFeatures: _tabular,
              ),
            ),
            Text(
              figure.shortLabel,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: shell.mutedForeground,
                fontSize: 11,
                height: 1.25,
              ),
            ),
          ],
        ),
      );
    } else {
      final value = Text(
        shown,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: shell.foreground,
          fontSize: text ? 22 : 30,
          fontWeight: FontWeight.w600,
          letterSpacing: text ? -0.3 : -0.6,
          fontFeatures: _tabular,
        ),
      );
      final caption = Text(
        figure.caption ?? 'cargando',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: toneColor ?? shell.mutedForeground,
          fontSize: 13,
          fontWeight: toneColor == null ? FontWeight.w400 : FontWeight.w600,
        ),
      );
      body = Padding(
        padding: EdgeInsets.fromLTRB(leading ?? 28, 18, 20, 22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              figure.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: shell.mutedForeground, fontSize: 12.5),
            ),
            const SizedBox(height: 4),
            if (text) ...[
              value,
              const SizedBox(height: 2),
              caption,
            ] else
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  value,
                  const SizedBox(width: 10),
                  Expanded(child: caption),
                ],
              ),
          ],
        ),
      );
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          left: first ? BorderSide.none : BorderSide(color: shell.edge),
          top: topEdge ? BorderSide(color: shell.edge) : BorderSide.none,
        ),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          key: figure.key,
          onTap: figure.onTap,
          hoverColor: shell.raised,
          child: Semantics(
            button: true,
            label: '${figure.label}: $shown'
                '${figure.caption == null ? '' : ', ${figure.caption}'}',
            excludeSemantics: true,
            child: body,
          ),
        ),
      ),
    );
  }
}

/// Identity of a group: the theme's identity tones, or the danger and
/// neutral semantic tones for a system group and a footnote group.
enum ModuleStartTone { a, b, c, d, danger, neutral }

@immutable
class ModuleStartEntry {
  const ModuleStartEntry({
    required this.key,
    required this.title,
    required this.description,
    required this.icon,
    required this.onTap,
    this.destructive = false,
    this.compactAttention,
  });

  final Key key;
  final String title;
  final String description;
  final IconData icon;
  final VoidCallback onTap;

  /// An action that removes data: its title takes the danger tone.
  final bool destructive;

  /// What needs attention, said in place of the description on a phone,
  /// where the band has no room to say it.
  final String? compactAttention;
}

@immutable
class ModuleStartGroup {
  const ModuleStartGroup({
    required this.title,
    required this.tone,
    required this.entries,
    this.description,
    this.icon,
  });

  final String title;

  /// Without one the group is a small label over its rows («Plataforma»).
  final String? description;
  final IconData? icon;
  final ModuleStartTone tone;
  final List<ModuleStartEntry> entries;
}

/// The workspaces under the band: [groups] in reading order (how a phone
/// stacks them), and [wideColumns] — group indexes per column — for the
/// three hairline-split columns from 1100 px. Each group stands alone in its
/// column when [wideColumns] is null.
class ModuleStartWorkspaces extends StatelessWidget {
  const ModuleStartWorkspaces({
    super.key,
    required this.phone,
    required this.groups,
    this.wideColumns,
    this.title,
  });

  final bool phone;
  final List<ModuleStartGroup> groups;
  final List<List<int>>? wideColumns;
  final String? title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final line = theme.colorScheme.outlineVariant;
    // Rows carry 12 px of their own so the hover tint has room; the block
    // starts 12 px early and the icons line up with the band's text.
    final inset = phone ? 0.0 : 12.0;
    final gutter = moduleStartGutter(phone) - inset;
    final columns = wideColumns ??
        [
          for (var i = 0; i < groups.length; i++) [i],
        ];
    return Padding(
      padding: EdgeInsets.fromLTRB(gutter, phone ? 18 : 34, gutter, 48),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null) ...[
            Padding(
              padding: EdgeInsets.only(left: inset),
              child: Semantics(
                header: true,
                child: Text(
                  title!,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontSize: phone ? 17 : 20,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                  ),
                ),
              ),
            ),
            SizedBox(height: phone ? 8 : 24),
          ],
          LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth >= 1100) {
                return IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var c = 0; c < columns.length; c++)
                        Expanded(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              border: Border(
                                left: c == 0
                                    ? BorderSide.none
                                    : BorderSide(color: line),
                              ),
                            ),
                            child: Padding(
                              padding: EdgeInsets.only(
                                left: c == 0 ? 0 : 20,
                                right: c == columns.length - 1 ? 0 : 20,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  for (var g = 0; g < columns[c].length; g++)
                                    Padding(
                                      padding: EdgeInsets.only(
                                        top: g == 0 ? 0 : 34,
                                      ),
                                      child: _GroupBlock(
                                        group: groups[columns[c][g]],
                                        compact: false,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < groups.length; i++)
                    DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border(
                          top: i == 0
                              ? BorderSide.none
                              : BorderSide(color: line),
                        ),
                      ),
                      child: Padding(
                        padding: EdgeInsets.only(
                          top: i == 0 ? (title == null ? 0 : 10) : 22,
                          bottom: 14,
                        ),
                        child: _GroupBlock(group: groups[i], compact: phone),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _GroupBlock extends StatelessWidget {
  const _GroupBlock({required this.group, required this.compact});

  final ModuleStartGroup group;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final roles = VinabikeThemeRoles.of(context);
    final (tone, onTone, soft) = switch (group.tone) {
      ModuleStartTone.a => (roles.avatarA, roles.onAvatarA, roles.avatarSoftA),
      ModuleStartTone.b => (roles.avatarB, roles.onAvatarB, roles.avatarSoftB),
      ModuleStartTone.c => (roles.avatarC, roles.onAvatarC, roles.avatarSoftC),
      ModuleStartTone.d => (roles.avatarD, roles.onAvatarD, roles.avatarSoftD),
      ModuleStartTone.danger => (
          roles.danger.accent,
          roles.danger.onAccent,
          roles.danger.container,
        ),
      ModuleStartTone.neutral => (
          roles.neutral.accent,
          roles.neutral.onAccent,
          roles.neutral.container,
        ),
    };
    final square = compact ? 38.0 : 42.0;
    final side = compact ? 0.0 : 12.0;
    final icon = group.icon;
    final Widget header;
    if (icon == null) {
      header = Padding(
        padding: EdgeInsets.fromLTRB(side, 0, side, 4),
        child: Semantics(
          header: true,
          child: Text(
            group.title.toUpperCase(),
            style: TextStyle(
              color: theme.colorScheme.onSurfaceVariant,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.7,
            ),
          ),
        ),
      );
    } else {
      header = Padding(
        padding: EdgeInsets.fromLTRB(side, 0, side, 12),
        child: Row(
          children: [
            Container(
              width: square,
              height: square,
              decoration: BoxDecoration(
                color: tone,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, size: compact ? 19 : 21, color: onTone),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Semantics(
                    header: true,
                    child: Text(
                      group.title,
                      style: TextStyle(
                        color: theme.colorScheme.onSurface,
                        fontSize: compact ? 15.5 : 16.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ),
                  if (group.description != null)
                    Text(
                      group.description!,
                      style: TextStyle(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontSize: compact ? 12.5 : 13,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        header,
        for (var i = 0; i < group.entries.length; i++) ...[
          if (i > 0)
            Padding(
              padding: EdgeInsets.symmetric(horizontal: side),
              child: Divider(height: 1, thickness: 1, color: roles.hairline),
            ),
          _EntryRow(
            entry: group.entries[i],
            tone: tone,
            soft: soft,
            compact: compact,
          ),
        ],
      ],
    );
  }
}

class _EntryRow extends StatelessWidget {
  const _EntryRow({
    required this.entry,
    required this.tone,
    required this.soft,
    required this.compact,
  });

  final ModuleStartEntry entry;
  final Color tone;
  final Color soft;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final roles = VinabikeThemeRoles.of(context);
    final attention = compact ? entry.compactAttention : null;
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        key: entry.key,
        onTap: entry.onTap,
        borderRadius: BorderRadius.circular(12),
        hoverColor: soft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 0 : 12,
              vertical: compact ? 8 : 12,
            ),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: soft,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(entry.icon, size: 18, color: tone),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.title,
                        style: TextStyle(
                          color: entry.destructive
                              ? roles.danger.accent
                              : theme.colorScheme.onSurface,
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        attention ?? entry.description,
                        maxLines: compact ? 2 : 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: attention == null
                              ? theme.colorScheme.onSurfaceVariant
                              : roles.warning.accent,
                          fontSize: compact ? 12 : 12.5,
                          fontWeight: attention == null
                              ? FontWeight.w400
                              : FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 20,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
