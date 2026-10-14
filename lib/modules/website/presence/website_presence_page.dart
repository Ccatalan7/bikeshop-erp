import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../shared/themes/vinabike_theme_roles.dart';
import '../../../shared/widgets/vb_notice.dart';
import '../widgets/website_admin_ui.dart';
import 'presence_chart.dart';
import 'presence_controller.dart';
import 'presence_models.dart';
import 'presence_sections.dart';

final _int = NumberFormat.decimalPattern('es_CL');
final _one = NumberFormat('#,##0.0', 'es_CL');
final _dayShort = DateFormat('d MMM', 'es');

/// «Presencia en internet» (`/website/presence`): what Google says of the
/// store day by day — searches, positions, indexation and visits — next to
/// what we changed, so every change can be judged by its effect.
///
/// The figures come from `web-presence-collect` (Search Console and
/// Analytics through Viñabike's service account, daily at 06:23 and an
/// indexation batch every two hours); the page only reads them.
class WebsitePresencePage extends StatefulWidget {
  const WebsitePresencePage(
      {super.key, this.controller, this.embedded = false});

  /// For tests; the page builds its own otherwise.
  final PresenceController? controller;

  /// Without the ERP layout around it (tests and embedded hosts).
  final bool embedded;

  @override
  State<WebsitePresencePage> createState() => _WebsitePresencePageState();
}

class _WebsitePresencePageState extends State<WebsitePresencePage> {
  late final PresenceController _controller =
      widget.controller ?? PresenceController();

  @override
  void initState() {
    super.initState();
    _controller.load();
  }

  @override
  void dispose() {
    if (widget.controller == null) _controller.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => _ConnectionsDialog(controller: _controller),
    );
    if (saved == true && mounted) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(
            content: Text(
                'Guardado. Las visitas llegan con la próxima recolección.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        final phone = MediaQuery.sizeOf(context).width < 600;
        return WebsiteAdminShell(
          embedded: widget.embedded,
          title: 'Presencia en internet',
          description:
              'Cómo te encuentra Google y qué pasa después, con lo que cambiamos marcado',
          // One header line on a phone too: the period and a «⋯» with
          // refresh and connections (three buttons wrapped to two rows).
          actions: [
            PopupMenuButton<PresencePeriod>(
              tooltip: 'Período',
              initialValue: _controller.period,
              onSelected: _controller.setPeriod,
              itemBuilder: (context) => [
                for (final period in PresencePeriod.values)
                  PopupMenuItem(
                      value: period, child: Text('Últimos ${period.label}')),
              ],
              child: Container(
                constraints: const BoxConstraints(minHeight: 40),
                padding: EdgeInsets.only(left: phone ? 10 : 12, right: 4),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border:
                      Border.all(color: Theme.of(context).colorScheme.outline),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!phone) ...[
                      const Icon(Icons.date_range_rounded, size: 18),
                      const SizedBox(width: 6),
                    ],
                    Text(
                      phone
                          ? _controller.period.label
                          : 'Últimos ${_controller.period.label}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const Icon(Icons.arrow_drop_down_rounded),
                  ],
                ),
              ),
            ),
            if (phone)
              _controller.refreshing
                  ? const SizedBox.square(
                      dimension: 40,
                      child: Center(
                        child: SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    )
                  : PopupMenuButton<String>(
                      tooltip: 'Más acciones',
                      enabled: _controller.tenantId != null,
                      icon: const Icon(Icons.more_vert_rounded),
                      onSelected: (value) => value == 'refresh'
                          ? _controller.refresh()
                          : _connect(),
                      itemBuilder: (context) => const [
                        PopupMenuItem(
                          value: 'refresh',
                          child: ListTile(
                            leading: Icon(Icons.refresh_rounded),
                            title: Text('Actualizar ahora'),
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                        PopupMenuItem(
                          value: 'connect',
                          child: ListTile(
                            leading: Icon(Icons.link_rounded),
                            title: Text('Conexiones con Google'),
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                      ],
                    )
            else ...[
              IconButton(
                tooltip: 'Conexiones con Google',
                onPressed: _controller.tenantId == null ? null : _connect,
                icon: const Icon(Icons.link_rounded),
              ),
              FilledButton.icon(
                onPressed:
                    _controller.refreshing || _controller.tenantId == null
                        ? null
                        : _controller.refresh,
                icon: _controller.refreshing
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.refresh_rounded, size: 18),
                label: Text(
                    _controller.refreshing ? 'Actualizando' : 'Actualizar'),
              ),
            ],
          ],
          child: _PresenceBody(controller: _controller, onConnect: _connect),
        );
      },
    );
  }
}

class _PresenceBody extends StatelessWidget {
  const _PresenceBody({required this.controller, required this.onConnect});

  final PresenceController controller;
  final VoidCallback onConnect;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    if (c.loading && !c.hasData) {
      return const Center(child: CircularProgressIndicator());
    }
    if (c.error != null && !c.hasData) {
      return Padding(
        padding: const EdgeInsets.all(20),
        child: VbNotice(
          tone: VbNoticeTone.danger,
          title: 'No se pudieron leer las cifras',
          body: c.error,
          action:
              TextButton(onPressed: c.load, child: const Text('Reintentar')),
        ),
      );
    }
    if (!c.hasData) {
      return const WebsiteAdminEmptyState(
        icon: Icons.travel_explore_rounded,
        title: 'Aún no hay cifras de Google',
        description:
            'La recolección corre todos los días a las 06:23. Pulsa «Actualizar» '
            'para traerlas ahora (Search Console guarda hasta 16 meses).',
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final phone = width < 600;
        final wide = width >= 1100;
        final gap = phone ? 12.0 : 16.0;
        final sections = <Widget>[
          _StatusLine(controller: c),
          _Figures(
              controller: c,
              width: width - (phone ? 24 : 48),
              gap: gap,
              onConnect: onConnect),
          _TrendBlock(controller: c),
          _pair(
            wide,
            gap,
            PresenceTermsBlock(
              title: 'Lo que la gente busca',
              subtitle: 'Búsquedas en Google donde apareció la tienda',
              terms: c.queries,
              pages: false,
              loading: c.termsLoading,
              error: c.termsError,
              onRetry: c.retryTerms,
            ),
            PresenceTermsBlock(
              title: 'Páginas que aparecen',
              subtitle: 'Direcciones de la tienda en los resultados',
              terms: c.pages,
              pages: true,
              loading: c.termsLoading,
              error: c.termsError,
              onRetry: c.retryTerms,
              host: c.storeHost,
            ),
          ),
          _pair(
            wide,
            gap,
            PresenceIndexBlock(
              latest: c.latestIndex,
              atStart: c.indexAtStart,
              history: c.indexDays,
              onOpenState: (state) => showPresenceUrls(
                context,
                state: state,
                urls: c.urlsInState(state),
              ),
            ),
            PresenceTrafficBlock(controller: c, onConnect: onConnect),
          ),
          PresenceLogBlock(notes: c.periodNotes),
        ];
        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
              phone ? 12 : 24, phone ? 12 : 18, phone ? 12 : 24, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < sections.length; i++) ...[
                if (i > 0) SizedBox(height: gap),
                sections[i],
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _pair(bool wide, double gap, Widget left, Widget right) {
    if (!wide) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [left, SizedBox(height: gap), right],
      );
    }
    // Side by side from the top: IntrinsicHeight cannot measure a
    // SegmentedButton (its dry layout reads constraints it does not have).
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: left),
        SizedBox(width: gap),
        Expanded(child: right),
      ],
    );
  }
}

/// When the figures are from and whether the last collection went well.
class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.controller});

  final PresenceController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final roles = VinabikeThemeRoles.of(context);
    final c = controller;
    final run = c.lastFinished;
    final range = c.currentRange;
    final ok = run?.status == PresenceRunStatus.ok;
    final color = run == null
        ? scheme.outline
        : ok
            ? roles.success.accent
            : run.status == PresenceRunStatus.partial
                ? roles.warning.accent
                : roles.danger.accent;
    final ago = run?.finishedAt == null ? null : _ago(run!.finishedAt!);
    final parts = [
      if (range != null)
        'Búsquedas del ${_dayShort.format(range.from)} al ${_dayShort.format(range.to)}, '
            'contra los ${c.period.label} anteriores',
      if (ago != null) 'revisado $ago',
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Tooltip(
              message: run == null
                  ? 'Sin recolecciones'
                  : run.errors.isEmpty
                      ? 'Última recolección sin problemas'
                      : run.errors.join('\n'),
              child: Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                parts.join(' · '),
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
          ],
        ),
        if (c.refreshMessage != null) ...[
          const SizedBox(height: 6),
          Text(
            c.refreshMessage!,
            style: theme.textTheme.bodySmall
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
        ],
      ],
    );
  }

  static String _ago(DateTime time) {
    final minutes = DateTime.now().difference(time).inMinutes;
    if (minutes < 2) return 'recién';
    if (minutes < 60) return 'hace $minutes min';
    final hours = minutes ~/ 60;
    if (hours < 24) return 'hace $hours h';
    return 'el ${_dayShort.format(time)}';
  }
}

class _Figures extends StatelessWidget {
  const _Figures({
    required this.controller,
    required this.width,
    required this.gap,
    required this.onConnect,
  });

  final PresenceController controller;
  final double width;
  final double gap;
  final VoidCallback onConnect;

  @override
  Widget build(BuildContext context) {
    final roles = VinabikeThemeRoles.of(context);
    final scheme = Theme.of(context).colorScheme;
    final c = controller;
    final now = c.current;
    final before = c.previous;
    final days = c.currentDays;
    final index = c.latestIndex;
    final start = c.indexAtStart;
    final organic = c.organic;

    final figures = <Widget>[
      PresenceFigure(
        label: 'Clics desde Google',
        value: _int.format(now.clicks),
        delta: PresenceDelta.count(now.clicks, before.clicks),
        spark: [for (final d in days) d.clicks.toDouble()],
        onTap: () => c.setMetric(PresenceMetric.clicks),
      ),
      PresenceFigure(
        label: 'Vistas en Google',
        value: _int.format(now.impressions),
        delta: PresenceDelta.count(now.impressions, before.impressions),
        spark: [for (final d in days) d.impressions.toDouble()],
        onTap: () => c.setMetric(PresenceMetric.impressions),
      ),
      PresenceFigure(
        label: 'Posición media',
        value: now.position == null ? '—' : _one.format(now.position),
        delta: PresenceDelta.position(now.position, before.position),
        spark: [for (final d in days) d.position == null ? null : -d.position!],
        sparkColor: scheme.tertiary,
        onTap: () => c.setMetric(PresenceMetric.position),
      ),
      PresenceFigure(
        label: 'Clics por vista',
        value: now.ctr == null ? '—' : '${_one.format(now.ctr! * 100)} %',
        delta: now.ctr == null || before.ctr == null
            ? const PresenceDelta(text: '—', good: null)
            : PresenceDelta(
                text: '${now.ctr! >= before.ctr! ? '▲' : '▼'} '
                    '${_one.format(((now.ctr! - before.ctr!) * 100).abs())} pts',
                good: (now.ctr! - before.ctr!).abs() < 0.0005
                    ? null
                    : now.ctr! > before.ctr!,
              ),
        spark: [
          for (final d in days)
            d.impressions == 0 ? null : d.clicks / d.impressions
        ],
        sparkColor: scheme.secondary,
      ),
      PresenceFigure(
        label: 'Páginas en Google',
        value: index == null ? '—' : _int.format(index.indexed),
        caption: index == null
            ? null
            : 'de ${_int.format(index.inspected)} revisadas',
        delta: index != null && start != null && start.day != index.day
            ? PresenceDelta.count(index.indexed, start.indexed)
            : const PresenceDelta(text: 'desde hoy', good: null),
        spark: [for (final d in c.indexDays) d.indexed.toDouble()],
        sparkColor: roles.success.accent,
      ),
      if (organic != null)
        PresenceFigure(
          label: 'Visitas desde Google',
          value: _int.format(organic.sessions),
          delta:
              PresenceDelta.count(organic.sessions, organic.previousSessions),
          caption: organic.engagement == null
              ? null
              : '${_int.format((organic.engagement! * 100).round())} % con interés',
          spark: [for (final p in c.seriesFor(PresenceMetric.visits)) p.$2],
          sparkColor: roles.success.accent,
          onTap: () => c.setMetric(PresenceMetric.visits),
        )
      else
        PresenceFigure(
          label: 'Visitas desde Google',
          value: '—',
          delta: PresenceDelta(
            text: c.settings.ga4PropertyId == null
                ? 'conectar Analytics'
                : c.analyticsNoAccess
                    ? 'falta acceso'
                    : 'sin datos aún',
            good: null,
          ),
          onTap: onConnect,
        ),
    ];

    final columns = width >= 1300
        ? 6
        : width >= 900
            ? 3
            : 2;
    final tile = (width - gap * (columns - 1)) / columns;
    return Wrap(
      spacing: gap,
      runSpacing: gap,
      children: [
        for (final figure in figures) SizedBox(width: tile, child: figure)
      ],
    );
  }
}

class _TrendBlock extends StatelessWidget {
  const _TrendBlock({required this.controller});

  final PresenceController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final roles = VinabikeThemeRoles.of(context);
    final phone = MediaQuery.sizeOf(context).width < 600;
    final notes = c.periodNotes;
    return PresenceBlock(
      title: 'Día a día',
      subtitle: c.period.days > 45 ? 'Línea gruesa: promedio de 7 días' : null,
      trailing: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final metric in PresenceMetric.values)
            if (metric != PresenceMetric.visits || c.hasTraffic)
              ChoiceChip(
                label: Text(metric.label),
                selected: c.metric == metric,
                onSelected: (_) => c.setMetric(metric),
                visualDensity: VisualDensity.compact,
              ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PresenceTrendChart(
            metric: c.metric,
            series: c.series,
            notes: notes,
            height: phone ? 200 : 280,
            onOpenDay: (day) => showPresenceDay(
              context,
              day,
              [
                for (final n in notes)
                  if (n.day == day) n
              ],
            ),
          ),
          if (notes.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 16,
              runSpacing: 4,
              children: [
                _Legend(
                    color: roles.warning.accent, label: 'Cambio en el sitio'),
                _Legend(color: roles.info.accent, label: 'Análisis'),
                Text(
                  'Toca una marca para ver qué se hizo ese día',
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text(label, style: Theme.of(context).textTheme.labelSmall),
        ],
      );
}

class _ConnectionsDialog extends StatefulWidget {
  const _ConnectionsDialog({required this.controller});

  final PresenceController controller;

  @override
  State<_ConnectionsDialog> createState() => _ConnectionsDialogState();
}

class _ConnectionsDialogState extends State<_ConnectionsDialog> {
  late final TextEditingController _property = TextEditingController(
      text: widget.controller.settings.ga4PropertyId ?? '');
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _property.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final digits = _property.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isNotEmpty && (digits.length < 6 || digits.length > 12)) {
      setState(() =>
          _error = 'El número de la propiedad tiene entre 6 y 12 dígitos.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.controller
          .saveAnalyticsProperty(digits.isEmpty ? null : digits);
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      setState(() {
        _saving = false;
        _error = 'No se pudo guardar: $error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final settings = widget.controller.settings;
    return AlertDialog(
      title: const Text('Conexiones con Google'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Search Console',
                style: theme.textTheme.labelLarge
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(
              settings.gscSite ??
                  'La propiedad de dominio de la tienda (sc-domain:…), leída con la cuenta de servicio de Viñabike.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 18),
            Text('Google Analytics 4',
                style: theme.textTheme.labelLarge
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            TextField(
              controller: _property,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Número de la propiedad',
                helperText:
                    'Analytics › Administrar › Detalles de la propiedad (no el «G-…»)',
                errorText: _error,
              ),
              onSubmitted: (_) => _save(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? 'Guardando…' : 'Guardar'),
        ),
      ],
    );
  }
}
