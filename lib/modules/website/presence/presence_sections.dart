import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../../shared/themes/vinabike_theme_roles.dart';
import '../../../shared/widgets/vb_notice.dart';
import '../../../shared/widgets/vb_status_badge.dart';
import 'presence_chart.dart';
import 'presence_controller.dart';
import 'presence_models.dart';

final _int = NumberFormat.decimalPattern('es_CL');
final _one = NumberFormat('#,##0.0', 'es_CL');
final _pct = NumberFormat('#,##0.0', 'es_CL');
final _dayShort = DateFormat('d MMM', 'es');
final _dayLong = DateFormat("EEEE d 'de' MMMM", 'es');

const _tabular = [FontFeature.tabularFigures()];

String _count(int n, String one, String many) =>
    '${_int.format(n)} ${n == 1 ? one : many}';

/// The container of every block: a quiet surface, a title line and its
/// content. Hierarchy comes from type and spacing, not from accents.
class PresenceBlock extends StatelessWidget {
  const PresenceBlock({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.trailing,
    this.padding = const EdgeInsets.fromLTRB(18, 16, 18, 18),
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 8,
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Semantics(
                      header: true,
                      child: Text(
                        title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.2,
                        ),
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ],
                ),
                if (trailing != null) trailing!,
              ],
            ),
            const SizedBox(height: 14),
            child,
          ],
        ),
      ),
    );
  }
}

/// A change against the previous period: the arrow and the color say
/// whether it is good for the shop, the text says by how much.
class PresenceDelta extends StatelessWidget {
  const PresenceDelta(
      {super.key,
      required this.text,
      required this.good,
      this.compact = false});

  /// Relative change of a count; null when there is nothing to compare with.
  factory PresenceDelta.count(int current, int previous,
      {bool compact = false}) {
    if (previous == 0) {
      return PresenceDelta(
        text: current == 0 ? 'sin cambio' : 'nuevo',
        good: current == 0 ? null : true,
        compact: compact,
      );
    }
    final change = (current - previous) / previous;
    if (change.abs() < 0.005) {
      return PresenceDelta(text: 'igual', good: null, compact: compact);
    }
    return PresenceDelta(
      text:
          '${change > 0 ? '▲' : '▼'} ${_int.format((change.abs() * 100).round())} %',
      good: change > 0,
      compact: compact,
    );
  }

  /// Places gained in the results (a lower position is better).
  factory PresenceDelta.position(double? current, double? previous,
      {bool compact = false}) {
    if (current == null || previous == null) {
      return PresenceDelta(
          text: previous == null ? 'nueva' : '—', good: null, compact: compact);
    }
    final gain = previous - current;
    if (gain.abs() < 0.05) {
      return PresenceDelta(text: 'igual', good: null, compact: compact);
    }
    return PresenceDelta(
      text:
          '${gain > 0 ? '▲' : '▼'} ${_one.format(gain.abs())}${compact ? '' : ' lugares'}',
      good: gain > 0,
      compact: compact,
    );
  }

  final String text;
  final bool? good;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final roles = VinabikeThemeRoles.of(context);
    final scheme = Theme.of(context).colorScheme;
    final color = good == null
        ? scheme.onSurfaceVariant
        : good!
            ? roles.success.accent
            : roles.danger.accent;
    return Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: (compact
              ? Theme.of(context).textTheme.labelSmall
              : Theme.of(context).textTheme.labelMedium)
          ?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
              fontFeatures: _tabular),
    );
  }
}

/// One headline figure of the period with its change and its little line.
class PresenceFigure extends StatelessWidget {
  const PresenceFigure({
    super.key,
    required this.label,
    required this.value,
    required this.delta,
    this.caption,
    this.spark = const [],
    this.sparkColor,
    this.onTap,
  });

  final String label;
  final String value;
  final Widget delta;
  final String? caption;
  final List<double?> spark;
  final Color? sparkColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final body = Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Scaled down, not cut, when two figures share a phone row.
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              label.toUpperCase(),
              maxLines: 1,
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
              ),
            ),
          ),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: -0.6,
                fontFeatures: _tabular,
              ),
            ),
          ),
          const SizedBox(height: 4),
          // The change and its caption on two lines: on a phone two figures
          // share the row and «▲ 4,0 lugares» alone fills the tile.
          delta,
          const SizedBox(height: 2),
          Text(
            caption ?? '',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 28,
            child: PresenceSparkline(
                values: spark, color: sparkColor ?? scheme.primary),
          ),
        ],
      ),
    );
    return Material(
      color: scheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: onTap == null ? body : InkWell(onTap: onTap, child: body),
    );
  }
}

enum TermSort { clicks, impressions, climbed }

/// Queries or pages of the period against the period before.
class PresenceTermsBlock extends StatefulWidget {
  const PresenceTermsBlock({
    super.key,
    required this.title,
    required this.subtitle,
    required this.terms,
    required this.pages,
    this.host,
    this.loading = false,
    this.error,
    this.onRetry,
  });

  final String title;
  final String subtitle;
  final List<PresenceTerm> terms;
  final bool pages;
  final String? host;
  final bool loading;
  final String? error;
  final VoidCallback? onRetry;

  @override
  State<PresenceTermsBlock> createState() => _PresenceTermsBlockState();
}

class _PresenceTermsBlockState extends State<PresenceTermsBlock> {
  TermSort _sort = TermSort.clicks;
  bool _all = false;

  String _label(String term) {
    if (!widget.pages) return term;
    final uri = Uri.tryParse(term);
    if (uri == null) return term;
    final path = uri.path.isEmpty ? '/' : uri.path;
    final query = uri.hasQuery ? '?${uri.query}' : '';
    // The store's own https addresses as paths; anything else (http://,
    // www., another host) whole, because that difference is the finding.
    if (uri.scheme == 'https' && uri.host == widget.host) return '$path$query';
    return '${uri.scheme}://${uri.host}$path$query';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final sorted = [...widget.terms];
    switch (_sort) {
      case TermSort.clicks:
        break;
      case TermSort.impressions:
        sorted.sort((a, b) => b.impressions.compareTo(a.impressions));
      case TermSort.climbed:
        sorted.removeWhere((t) => t.positionGain == null || t.impressions < 5);
        sorted.sort((a, b) => b.positionGain!.compareTo(a.positionGain!));
    }
    final shown = _all ? sorted : sorted.take(10).toList();
    final phone = MediaQuery.sizeOf(context).width < 600;

    return PresenceBlock(
      title: widget.title,
      subtitle: widget.subtitle,
      trailing: SegmentedButton<TermSort>(
        showSelectedIcon: false,
        style: const ButtonStyle(visualDensity: VisualDensity.compact),
        segments: const [
          ButtonSegment(value: TermSort.clicks, label: Text('Clics')),
          ButtonSegment(value: TermSort.impressions, label: Text('Vistas')),
          ButtonSegment(value: TermSort.climbed, label: Text('Subieron')),
        ],
        selected: {_sort},
        onSelectionChanged: (value) => setState(() => _sort = value.first),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.error != null && widget.terms.isEmpty)
            VbNotice(
              tone: VbNoticeTone.warning,
              title: 'No se pudo leer esta lista',
              body: widget.error,
              bodyMaxLines: 2,
              action: TextButton(
                  onPressed: widget.onRetry, child: const Text('Reintentar')),
            )
          else if (widget.loading && widget.terms.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else if (shown.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text(
                _sort == TermSort.climbed
                    ? 'Nada subió con al menos 5 vistas en el período.'
                    : 'Google no informó búsquedas en este período.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
            )
          else ...[
            if (!phone) _TermHeader(pages: widget.pages),
            for (final term in shown)
              phone
                  ? _TermTile(term: term, label: _label(term.term))
                  : _TermRow(term: term, label: _label(term.term)),
          ],
          if (sorted.length > 10)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => setState(() => _all = !_all),
                child: Text(_all ? 'Ver menos' : 'Ver las ${sorted.length}'),
              ),
            ),
        ],
      ),
    );
  }
}

class _TermHeader extends StatelessWidget {
  const _TermHeader({required this.pages});

  final bool pages;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelSmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
        );
    Widget cell(String text, double width) => SizedBox(
        width: width,
        child: Text(text, textAlign: TextAlign.right, style: style));
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Expanded(child: Text(pages ? 'PÁGINA' : 'BÚSQUEDA', style: style)),
          cell('CLICS', 56),
          cell('VISTAS', 72),
          cell('POSICIÓN', 72),
          cell('LUGARES', 84),
        ],
      ),
    );
  }
}

class _TermRow extends StatelessWidget {
  const _TermRow({required this.term, required this.label});

  final PresenceTerm term;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final number = theme.textTheme.bodyMedium?.copyWith(fontFeatures: _tabular);
    Widget cell(Widget child, double width) => SizedBox(
        width: width,
        child: Align(alignment: Alignment.centerRight, child: child));
    return Container(
      constraints: const BoxConstraints(minHeight: 38),
      decoration: BoxDecoration(
        border: Border(
            top: BorderSide(
                color: scheme.outlineVariant.withValues(alpha: 0.7))),
      ),
      child: Row(
        children: [
          Expanded(
            child: Tooltip(
              message: term.term,
              waitDuration: const Duration(milliseconds: 600),
              child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ),
          cell(
              Text(_int.format(term.clicks),
                  style: number?.copyWith(fontWeight: FontWeight.w700)),
              56),
          cell(Text(_int.format(term.impressions), style: number), 72),
          cell(
              Text(term.position == null ? '—' : _one.format(term.position),
                  style: number),
              72),
          cell(
            term.isNew
                ? const VbStatusBadge(
                    label: 'nueva', tone: VbStatusTone.info, dense: true)
                : PresenceDelta.position(term.position, term.previousPosition,
                    compact: true),
            84,
          ),
        ],
      ),
    );
  }
}

class _TermTile extends StatelessWidget {
  const _TermTile({required this.term, required this.label});

  final PresenceTerm term;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 9),
      decoration: BoxDecoration(
        border: Border(
            top: BorderSide(
                color: scheme.outlineVariant.withValues(alpha: 0.7))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium),
          const SizedBox(height: 3),
          Row(
            children: [
              Flexible(
                child: Text(
                  '${_count(term.clicks, 'clic', 'clics')} · ${_count(term.impressions, 'vista', 'vistas')} · '
                  'pos. ${term.position == null ? '—' : _one.format(term.position)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontFeatures: _tabular,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              term.isNew
                  ? const VbStatusBadge(
                      label: 'nueva', tone: VbStatusTone.info, dense: true)
                  : PresenceDelta.position(term.position, term.previousPosition,
                      compact: true),
            ],
          ),
        ],
      ),
    );
  }
}

/// How much of the sitemap Google has, by what its inspection said.
class PresenceIndexBlock extends StatelessWidget {
  const PresenceIndexBlock({
    super.key,
    required this.latest,
    required this.atStart,
    required this.history,
    required this.onOpenState,
  });

  final IndexDay? latest;
  final IndexDay? atStart;
  final List<IndexDay> history;
  final ValueChanged<String> onOpenState;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final roles = VinabikeThemeRoles.of(context);
    final latest = this.latest;
    if (latest == null) {
      return PresenceBlock(
        title: 'Páginas en Google',
        child: Text(
          'La primera foto de la indexación se guarda con la próxima recolección.',
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: scheme.onSurfaceVariant),
        ),
      );
    }

    Color stateColor(String state) {
      if (coverageIsIndexed(state)) return roles.success.accent;
      if (state.startsWith('Discovered') ||
          state.startsWith('URL is unknown')) {
        return roles.info.accent;
      }
      if (state.startsWith('Crawled') ||
          state.startsWith('Duplicate') ||
          state.startsWith('Alternate')) {
        return roles.warning.accent;
      }
      if (state == 'Page with redirect') return scheme.outline;
      return roles.danger.accent;
    }

    final states = latest.byState.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final pending = latest.sitemapUrls - latest.inspected;
    final share = latest.indexedShare;

    return PresenceBlock(
      title: 'Páginas en Google',
      subtitle: latest.sitemapLastRead == null
          ? 'Lo que dice la inspección de Google de cada dirección del sitemap'
          : 'Google leyó el sitemap el ${_dayShort.format(latest.sitemapLastRead!)}'
              '${latest.sitemapSubmitted == null ? '' : ' · declara ${_int.format(latest.sitemapSubmitted)} páginas'}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.end,
            spacing: 10,
            runSpacing: 4,
            children: [
              Text(
                _int.format(latest.indexed),
                style: theme.textTheme.displaySmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: -1,
                  fontFeatures: _tabular,
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  'indexadas de ${_int.format(latest.inspected)} revisadas'
                  '${share == null ? '' : ' (${_pct.format(share * 100)} %)'}',
                  style: theme.textTheme.bodyLarge
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              height: 12,
              child: Row(
                children: [
                  for (final entry in states)
                    Expanded(
                      flex: entry.value,
                      child: Container(
                        margin: const EdgeInsets.only(right: 1.5),
                        color: stateColor(entry.key),
                      ),
                    ),
                  if (pending > 0)
                    Expanded(
                      flex: pending,
                      child: ColoredBox(color: scheme.surfaceContainerHighest),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          for (final entry in states)
            InkWell(
              onTap: () => onOpenState(entry.key),
              borderRadius: BorderRadius.circular(6),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 2),
                child: Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                          color: stateColor(entry.key), shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 10),
                    Expanded(child: Text(coverageLabel(entry.key))),
                    Text(
                      _int.format(entry.value),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        fontFeatures: _tabular,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(Icons.chevron_right_rounded,
                        size: 18, color: scheme.onSurfaceVariant),
                  ],
                ),
              ),
            ),
          if (pending > 0) ...[
            const SizedBox(height: 8),
            Text(
              '${_int.format(pending)} de ${_int.format(latest.sitemapUrls)} direcciones aún sin revisar: '
              'Google deja revisar unas 2.000 al día y la recolección pide ~700, '
              'así que la foto completa se arma en pocos días.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
          if (atStart != null &&
              atStart!.day != latest.day &&
              atStart!.inspected > 0) ...[
            const SizedBox(height: 8),
            Text(
              'Al comienzo del período: ${_int.format(atStart!.indexed)} indexadas de '
              '${_int.format(atStart!.inspected)} revisadas.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ],
      ),
    );
  }
}

/// Visits from Analytics by channel and the store funnel.
class PresenceTrafficBlock extends StatelessWidget {
  const PresenceTrafficBlock({
    super.key,
    required this.controller,
    required this.onConnect,
  });

  final PresenceController controller;
  final VoidCallback onConnect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final roles = VinabikeThemeRoles.of(context);
    final c = controller;
    final scopeSelector = SegmentedButton<PresenceScope>(
      showSelectedIcon: false,
      style: const ButtonStyle(visualDensity: VisualDensity.compact),
      segments: [
        for (final scope in PresenceScope.values)
          ButtonSegment(value: scope, label: Text(scope.label)),
      ],
      selected: {c.scope},
      onSelectionChanged: (value) => c.setScope(value.first),
    );

    if (c.settings.ga4PropertyId == null) {
      return PresenceBlock(
        title: 'Visitas al sitio',
        subtitle: 'Google Analytics',
        child: VbNotice(
          tone: VbNoticeTone.info,
          title: 'Analytics no está conectado',
          body:
              'Indica el número de la propiedad de Google Analytics 4 para ver las visitas, '
              'los canales y el embudo de compra junto a las búsquedas.',
          action: FilledButton.tonal(
              onPressed: onConnect, child: const Text('Conectar')),
        ),
      );
    }

    if (c.trafficError != null && !c.hasTraffic) {
      return PresenceBlock(
        title: 'Visitas al sitio',
        subtitle: 'Google Analytics',
        child: VbNotice(
          tone: VbNoticeTone.warning,
          title: 'No se pudieron leer las visitas',
          body: c.trafficError,
          bodyMaxLines: 2,
          action: TextButton(
              onPressed: c.retryTraffic, child: const Text('Reintentar')),
        ),
      );
    }

    if (c.trafficLoading && !c.hasTraffic) {
      return const PresenceBlock(
        title: 'Visitas al sitio',
        subtitle: 'Google Analytics',
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
        ),
      );
    }

    if (!c.analyticsNoAccess && !c.hasTraffic) {
      return PresenceBlock(
        title: 'Visitas al sitio',
        subtitle: 'Google Analytics · propiedad ${c.settings.ga4PropertyId}',
        child: const VbNotice(
          tone: VbNoticeTone.info,
          title: 'Aún no hay visitas guardadas',
          body:
              'Llegan con la próxima recolección (todos los días a las 06:23) o al '
              'pulsar «Actualizar».',
        ),
      );
    }

    if (c.analyticsNoAccess && !c.hasTraffic) {
      final account = '${c.analyticsState?['account'] ?? ''}';
      return PresenceBlock(
        title: 'Visitas al sitio',
        subtitle: 'Google Analytics · propiedad ${c.settings.ga4PropertyId}',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const VbNotice(
              tone: VbNoticeTone.warning,
              title: 'Analytics todavía no deja leer las visitas',
              body:
                  'En Analytics › Administrar › Gestión de acceso a la propiedad, agrega esta '
                  'cuenta con el rol Lector. Las cifras llegan con la recolección siguiente.',
            ),
            if (account.isNotEmpty) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: SelectableText(
                      account,
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(fontFamily: 'monospace'),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Copiar la cuenta',
                    icon: const Icon(Icons.copy_rounded),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: account));
                      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                        const SnackBar(content: Text('Cuenta copiada')),
                      );
                    },
                  ),
                ],
              ),
            ],
          ],
        ),
      );
    }

    final channels = c.channels;
    final total = channels.fold<int>(0, (sum, ch) => sum + ch.sessions);
    final previousTotal =
        channels.fold<int>(0, (sum, ch) => sum + ch.previousSessions);
    final funnel = c.funnel;
    final top = channels.isEmpty ? 1 : channels.first.sessions;
    final range = c.trafficRange;

    return PresenceBlock(
      title: 'Visitas al sitio',
      subtitle: range == null
          ? 'Google Analytics'
          : 'Google Analytics · ${_dayShort.format(range.from)} – ${_dayShort.format(range.to)}',
      trailing: scopeSelector,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                _int.format(total),
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.8,
                  fontFeatures: _tabular,
                ),
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Text('visitas',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: scheme.onSurfaceVariant)),
              ),
              const SizedBox(width: 10),
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: PresenceDelta.count(total, previousTotal),
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (final channel in channels.take(8))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          channelLabel(channel.channel),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: channel.channel == 'Organic Search'
                                ? FontWeight.w700
                                : null,
                          ),
                        ),
                      ),
                      if (channel.engagement != null)
                        Text(
                          '${_int.format((channel.engagement! * 100).round())} % con interés  ',
                          style: theme.textTheme.labelSmall
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      Text(
                        _int.format(channel.sessions),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          fontFeatures: _tabular,
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 58,
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: PresenceDelta.count(
                              channel.sessions, channel.previousSessions,
                              compact: true),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: top == 0 ? 0 : channel.sessions / top,
                      minHeight: 5,
                      backgroundColor: scheme.surfaceContainerHighest,
                      color: channel.channel == 'Organic Search'
                          ? roles.success.accent
                          : scheme.primary.withValues(alpha: 0.55),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 16),
          Text(
            'EMBUDO DE LA TIENDA',
            style: theme.textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 8),
          for (final (event, label) in presenceFunnel)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Expanded(child: Text(label)),
                  Text(
                    _int.format(funnel[event]?.$1 ?? 0),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      fontFeatures: _tabular,
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 58,
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: PresenceDelta.count(
                          funnel[event]?.$1 ?? 0, funnel[event]?.$2 ?? 0,
                          compact: true),
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

/// What we changed on the site and what each analysis concluded.
class PresenceLogBlock extends StatefulWidget {
  const PresenceLogBlock({super.key, required this.notes});

  final List<PresenceNote> notes;

  @override
  State<PresenceLogBlock> createState() => _PresenceLogBlockState();
}

class _PresenceLogBlockState extends State<PresenceLogBlock> {
  PresenceNoteKind? _kind;
  bool _all = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final notes = [
      for (final note in widget.notes)
        if (_kind == null || note.kind == _kind) note,
    ];
    final shown = _all ? notes : notes.take(8).toList();
    return PresenceBlock(
      title: 'Bitácora',
      subtitle:
          'Cambios del sitio (registro del wiki) y análisis periódicos, en el período',
      trailing: SegmentedButton<PresenceNoteKind?>(
        showSelectedIcon: false,
        style: const ButtonStyle(visualDensity: VisualDensity.compact),
        segments: const [
          ButtonSegment(value: null, label: Text('Todo')),
          ButtonSegment(value: PresenceNoteKind.change, label: Text('Cambios')),
          ButtonSegment(
              value: PresenceNoteKind.analysis, label: Text('Análisis')),
        ],
        selected: {_kind},
        onSelectionChanged: (value) => setState(() => _kind = value.first),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (shown.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Text(
                'Nada registrado en este período.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
          for (final note in shown) PresenceNoteTile(note: note),
          if (notes.length > 8)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => setState(() => _all = !_all),
                child: Text(_all ? 'Ver menos' : 'Ver las ${notes.length}'),
              ),
            ),
        ],
      ),
    );
  }
}

class PresenceNoteTile extends StatelessWidget {
  const PresenceNoteTile({super.key, required this.note});

  final PresenceNote note;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final roles = VinabikeThemeRoles.of(context);
    final analysis = note.kind == PresenceNoteKind.analysis;
    final color = analysis ? roles.info.accent : roles.warning.accent;
    return Theme(
      data: theme.copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(left: 64, bottom: 10, right: 8),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        leading: SizedBox(
          width: 52,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                DateFormat('d MMM', 'es').format(note.day),
                style: theme.textTheme.labelMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              Text(
                DateFormat('yyyy').format(note.day),
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
        title: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 6, right: 8),
              child: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
            ),
            Expanded(
              child: Text(
                note.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(left: 16, top: 2),
          child: Text(
            analysis ? 'Análisis' : 'Cambio en el sitio',
            style: theme.textTheme.labelSmall
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ),
        children: [
          SelectableText(note.body,
              style: theme.textTheme.bodySmall?.copyWith(height: 1.5)),
        ],
      ),
    );
  }
}

/// The day's notes, opened from a mark under the chart.
Future<void> showPresenceDay(
    BuildContext context, DateTime day, List<PresenceNote> notes) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: ConstrainedBox(
        constraints:
            BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.75),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          children: [
            Text(
              toBeginningOfSentenceCase(_dayLong.format(day)),
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            for (final note in notes) PresenceNoteTile(note: note),
          ],
        ),
      ),
    ),
  );
}

/// Addresses of the sitemap in one coverage state.
Future<void> showPresenceUrls(
  BuildContext context, {
  required String state,
  required Future<List<PresenceUrl>> urls,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) {
      final theme = Theme.of(context);
      final scheme = theme.colorScheme;
      return SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.75,
          child: FutureBuilder<List<PresenceUrl>>(
            future: urls,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(
                    child: Text('No se pudo leer: ${snapshot.error}'));
              }
              final list = snapshot.data ?? const [];
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                itemCount: list.length + 1,
                separatorBuilder: (_, index) => index == 0
                    ? const SizedBox(height: 8)
                    : Divider(height: 1, color: scheme.outlineVariant),
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return Text(
                      '${coverageLabel(state)} · ${_int.format(list.length)}${list.length >= 200 ? '+' : ''}',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    );
                  }
                  final url = list[index - 1];
                  final uri = Uri.tryParse(url.url);
                  final canonical = url.googleCanonical != null &&
                          url.googleCanonical != url.url
                      ? url.googleCanonical
                      : null;
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SelectableText(uri?.path ?? url.url,
                            style: theme.textTheme.bodyMedium),
                        const SizedBox(height: 2),
                        Text(
                          [
                            url.lastCrawlAt == null
                                ? 'Google no la ha rastreado'
                                : 'Rastreada el ${_dayShort.format(url.lastCrawlAt!)}',
                            if (canonical != null)
                              'Google prefiere ${Uri.tryParse(canonical)?.path ?? canonical}',
                          ].join(' · '),
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ),
      );
    },
  );
}
