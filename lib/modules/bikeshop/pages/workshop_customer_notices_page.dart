import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../shared/themes/vinabike_theme_roles.dart';
import '../../../shared/widgets/branded_loading.dart';
import '../../../shared/widgets/main_layout.dart';
import '../../../shared/widgets/vb_button.dart';
import '../../../shared/widgets/vb_notice.dart';
import '../services/workshop_customer_notice_service.dart';

/// Taller › Avisos y garantía (20261105130000): lo que el taller le avisa al
/// cliente —bici recibida, presupuesto listo, lista para retirar, entregada—
/// por correo y por WhatsApp, cómo van las plantillas en Meta, lo último que
/// salió, y la garantía que va en cada comprobante de entrega.
class WorkshopCustomerNoticesPage extends StatelessWidget {
  const WorkshopCustomerNoticesPage({super.key, this.service});

  /// Costura de pruebas; en la app es el servicio real.
  final WorkshopCustomerNoticeService? service;

  @override
  Widget build(BuildContext context) {
    return MainLayout(
      title: 'Avisos y garantía',
      child: WorkshopCustomerNoticesView(service: service),
    );
  }
}

class WorkshopCustomerNoticesView extends StatefulWidget {
  const WorkshopCustomerNoticesView({super.key, this.service});

  final WorkshopCustomerNoticeService? service;

  @override
  State<WorkshopCustomerNoticesView> createState() =>
      _WorkshopCustomerNoticesViewState();
}

class _WorkshopCustomerNoticesViewState
    extends State<WorkshopCustomerNoticesView> {
  late final WorkshopCustomerNoticeService _service =
      widget.service ?? WorkshopCustomerNoticeService();

  WorkshopNoticeOverview? _overview;
  List<WorkshopNoticeRecord> _recent = const [];
  Object? _loadError;
  Object? _recentError;
  bool _savingChannel = false;
  bool _creatingTemplates = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool refreshTemplates = true}) async {
    setState(() => _loadError = null);
    unawaited(_loadRecent());
    try {
      final overview = await _service.load(refreshTemplates: refreshTemplates);
      if (mounted) setState(() => _overview = overview);
    } catch (error) {
      if (mounted) setState(() => _loadError = error);
    }
  }

  Future<void> _loadRecent() async {
    try {
      final recent = await _service.recent();
      if (mounted) {
        setState(() {
          _recent = recent;
          _recentError = null;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _recentError = error);
    }
  }

  Future<void> _setChannel(WorkshopNoticeChannel channel, bool on) async {
    setState(() => _savingChannel = true);
    try {
      final overview = await _service.update(
        emailEnabled: channel == WorkshopNoticeChannel.email ? on : null,
        whatsappEnabled: channel == WorkshopNoticeChannel.whatsapp ? on : null,
      );
      if (!mounted) return;
      setState(() => _overview = _keepTemplates(overview));
    } catch (error) {
      _toast(WorkshopCustomerNoticeService.describeError(error));
    } finally {
      if (mounted) setState(() => _savingChannel = false);
    }
  }

  Future<bool> _saveWarranty(int days, int months) async {
    try {
      final overview = await _service.update(
        serviceWarrantyDays: days,
        partsWarrantyMonths: months,
      );
      if (!mounted) return true;
      setState(() => _overview = _keepTemplates(overview));
      _toast('Garantía guardada. Rige desde la próxima entrega.');
      return true;
    } catch (error) {
      _toast(WorkshopCustomerNoticeService.describeError(error));
      return false;
    }
  }

  Future<void> _createTemplates() async {
    final missing = _overview?.missingTemplates ?? const [];
    if (missing.isEmpty) return;
    setState(() => _creatingTemplates = true);
    try {
      final created = await _service.createTemplates(missing);
      _toast(created == 1
          ? 'Plantilla enviada a revisión de Meta.'
          : '$created plantillas enviadas a revisión de Meta.');
      await _load();
    } catch (error) {
      _toast(WorkshopCustomerNoticeService.describeError(error));
    } finally {
      if (mounted) setState(() => _creatingTemplates = false);
    }
  }

  /// Guardar no vuelve a preguntar a Meta: conserva lo que ya se sabía de
  /// las plantillas.
  WorkshopNoticeOverview _keepTemplates(WorkshopNoticeOverview fresh) {
    final previous = _overview;
    if (previous == null) return fresh;
    return WorkshopNoticeOverview(
      startedAt: fresh.startedAt,
      canEdit: fresh.canEdit,
      emailSwitch: fresh.emailSwitch,
      whatsappSwitch: fresh.whatsappSwitch,
      emailReady: fresh.emailReady,
      whatsappReady: fresh.whatsappReady,
      tallies: fresh.tallies,
      lastSentAt: fresh.lastSentAt,
      templates: fresh.templates,
      templateCheckFailed: previous.templateCheckFailed,
      serviceWarrantyDays: fresh.serviceWarrantyDays,
      partsWarrantyMonths: fresh.partsWarrantyMonths,
    );
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final overview = _overview;
    if (overview == null) {
      if (_loadError != null) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: VbNotice(
                title: 'No se pudieron leer los avisos',
                body: WorkshopCustomerNoticeService.describeError(_loadError!),
                tone: VbNoticeTone.danger,
                action: VbButton(
                  label: 'Reintentar',
                  variant: VbButtonVariant.secondary,
                  onPressed: _load,
                ),
              ),
            ),
          ),
        );
      }
      return const Center(child: BrandedLoading());
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 1100;
        final gutter = constraints.maxWidth >= 700 ? 24.0 : 16.0;
        final channels = _ChannelsCard(
          overview: overview,
          saving: _savingChannel,
          onChanged: overview.canEdit ? _setChannel : null,
        );
        final moments = _MomentsSection(
          overview: overview,
          wide: constraints.maxWidth >= 760,
          creating: _creatingTemplates,
          onCreateTemplates:
              overview.canEdit && overview.missingTemplates.isNotEmpty
                  ? _createTemplates
                  : null,
        );
        final warranty = _WarrantyCard(
          key: ValueKey(
              'warranty-${overview.serviceWarrantyDays}-${overview.partsWarrantyMonths}'),
          days: overview.serviceWarrantyDays,
          months: overview.partsWarrantyMonths,
          canEdit: overview.canEdit,
          onSave: _saveWarranty,
        );
        final recent = _RecentCard(
          records: _recent,
          error: _recentError,
          onRetry: _loadRecent,
        );

        return RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: EdgeInsets.fromLTRB(gutter, 20, gutter, 32),
            children: [
              _Header(overview: overview),
              const SizedBox(height: 20),
              if (wide) ...[
                // Sin alto forzado: un ListTile mide su alto intrínseco
                // menos de lo que ocupa y la tarjeta se desbordaría.
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(width: 340, child: channels),
                    const SizedBox(width: 16),
                    Expanded(child: moments),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(width: 340, child: warranty),
                    const SizedBox(width: 16),
                    Expanded(child: recent),
                  ],
                ),
              ] else ...[
                channels,
                const SizedBox(height: 16),
                moments,
                const SizedBox(height: 16),
                warranty,
                const SizedBox(height: 16),
                recent,
              ],
            ],
          ),
        );
      },
    );
  }
}

/// El tono de identidad de cada momento: el mismo en el ícono de su tarjeta
/// y en la lista de lo último.
({Color tint, Color soft}) _kindTone(
    VinabikeThemeRoles roles, WorkshopNoticeKind kind) {
  return switch (kind) {
    WorkshopNoticeKind.received => (
        tint: roles.avatarA,
        soft: roles.avatarSoftA
      ),
    WorkshopNoticeKind.quoteReady => (
        tint: roles.avatarB,
        soft: roles.avatarSoftB
      ),
    WorkshopNoticeKind.ready => (tint: roles.avatarC, soft: roles.avatarSoftC),
    WorkshopNoticeKind.delivered => (
        tint: roles.avatarD,
        soft: roles.avatarSoftD
      ),
  };
}

IconData _kindIcon(WorkshopNoticeKind kind) => switch (kind) {
      WorkshopNoticeKind.received => Icons.move_to_inbox_outlined,
      WorkshopNoticeKind.quoteReady => Icons.request_quote_outlined,
      WorkshopNoticeKind.ready => Icons.task_alt_outlined,
      WorkshopNoticeKind.delivered => Icons.verified_outlined,
    };

class _Panel extends StatelessWidget {
  const _Panel({required this.child, this.padding = const EdgeInsets.all(20)});

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final roles = VinabikeThemeRoles.of(context);
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: roles.hairline),
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title, {this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.overview});

  final WorkshopNoticeOverview overview;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final roles = VinabikeThemeRoles.of(context);
    final lastSent = overview.lastSentAt;
    final summary = [
      if (!overview.emailOn && !overview.whatsappOn)
        'Los avisos están apagados.'
      else
        'El taller le avisa al cliente en cada paso, por '
            '${[
          if (overview.emailOn) 'correo',
          if (overview.whatsappOn) 'WhatsApp',
        ].join(' y ')}.',
      if (lastSent != null)
        'Último aviso: ${DateFormat("d 'de' MMMM, HH:mm", 'es_CL').format(lastSent)}.',
    ].join(' ');
    return Wrap(
      spacing: 24,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.end,
      alignment: WrapAlignment.spaceBetween,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Avisos al cliente',
                style: theme.textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              Text(
                summary,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: roles.faintForeground),
              ),
            ],
          ),
        ),
        Semantics(
          label: '${overview.sentTotal} avisos enviados en 30 días',
          excludeSemantics: true,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                '${overview.sentTotal}',
                style: theme.textTheme.displaySmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(width: 10),
              Text(
                'enviados\nen 30 días',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: roles.faintForeground, height: 1.25),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ChannelsCard extends StatelessWidget {
  const _ChannelsCard({
    required this.overview,
    required this.saving,
    required this.onChanged,
  });

  final WorkshopNoticeOverview overview;
  final bool saving;
  final void Function(WorkshopNoticeChannel channel, bool on)? onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final roles = VinabikeThemeRoles.of(context);
    Widget channel({
      required WorkshopNoticeChannel channel,
      required IconData icon,
      required bool value,
      required bool ready,
      required String onText,
      required String notReadyText,
    }) {
      final subtitle = !ready
          ? notReadyText
          : value
              ? onText
              : 'Apagado: no sale ningún aviso por aquí.';
      return SwitchListTile.adaptive(
        key: ValueKey('workshop-notices-${channel.code}-switch'),
        contentPadding: EdgeInsets.zero,
        value: value && ready,
        onChanged: onChanged == null || saving || !ready
            ? null
            : (on) => onChanged!(channel, on),
        secondary: Icon(icon, color: roles.faintForeground),
        title: Text(
          channel.label,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(subtitle),
      );
    }

    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionTitle('Canales'),
          const SizedBox(height: 8),
          channel(
            channel: WorkshopNoticeChannel.email,
            icon: Icons.mail_outline,
            value: overview.emailSwitch,
            ready: overview.emailReady,
            onText: 'A quien dejó su correo, con el remitente de la tienda.',
            notReadyText: 'Falta el remitente de correo de la tienda.',
          ),
          channel(
            channel: WorkshopNoticeChannel.whatsapp,
            icon: Icons.chat_outlined,
            value: overview.whatsappSwitch,
            ready: overview.whatsappReady,
            onText: 'Por el número del taller, de 9:00 a 21:00.',
            notReadyText: 'Conecta un número en Configuración › WhatsApp.',
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.person_outline,
                  size: 18, color: roles.faintForeground),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'El cliente con cuenta elige en su perfil si los recibe por '
                  'correo, por WhatsApp o por los dos.',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: roles.faintForeground),
                ),
              ),
            ],
          ),
          if (!overview.canEdit) ...[
            const SizedBox(height: 10),
            Text(
              'Sólo administración enciende o apaga los avisos.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: roles.faintForeground),
            ),
          ],
        ],
      ),
    );
  }
}

class _MomentsSection extends StatelessWidget {
  const _MomentsSection({
    required this.overview,
    required this.wide,
    required this.creating,
    required this.onCreateTemplates,
  });

  final WorkshopNoticeOverview overview;
  final bool wide;
  final bool creating;
  final VoidCallback? onCreateTemplates;

  @override
  Widget build(BuildContext context) {
    final tiles = [
      for (final kind in WorkshopNoticeKind.values)
        _MomentTile(kind: kind, overview: overview, stretched: wide),
    ];
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SectionTitle(
            'Los cuatro avisos',
            trailing: onCreateTemplates == null
                ? null
                : VbButton(
                    key: const Key('workshop-notices-create-templates'),
                    label: creating
                        ? 'Enviando a Meta…'
                        : 'Crear plantillas en Meta',
                    icon: Icons.add_comment_outlined,
                    variant: VbButtonVariant.secondary,
                    busy: creating,
                    onPressed: creating ? null : onCreateTemplates,
                  ),
          ),
          const SizedBox(height: 16),
          if (wide)
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < tiles.length; i++) ...[
                    if (i > 0) const SizedBox(width: 12),
                    Expanded(child: tiles[i]),
                  ],
                ],
              ),
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < tiles.length; i++) ...[
                  if (i > 0) const SizedBox(height: 12),
                  tiles[i],
                ],
              ],
            ),
        ],
      ),
    );
  }
}

class _MomentTile extends StatelessWidget {
  const _MomentTile({
    required this.kind,
    required this.overview,
    required this.stretched,
  });

  final WorkshopNoticeKind kind;
  final WorkshopNoticeOverview overview;

  /// En la fila de cuatro, las tarjetas tienen el mismo alto y las cifras van
  /// al pie, en línea aunque un título ocupe dos líneas. En una columna, cada
  /// una mide lo suyo.
  final bool stretched;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final roles = VinabikeThemeRoles.of(context);
    final tone = _kindTone(roles, kind);
    final email = overview.tally(kind, WorkshopNoticeChannel.email);
    final whatsapp = overview.tally(kind, WorkshopNoticeChannel.whatsapp);
    final skipped = <String, int>{};
    for (final tally in [email, whatsapp]) {
      tally.skipped.forEach((reason, count) {
        final label = WorkshopCustomerNoticeService.reasonLabel(reason);
        skipped[label] = (skipped[label] ?? 0) + count;
      });
    }
    final skippedLine = (skipped.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value)))
        .take(2)
        .map((entry) => '${entry.value} ${entry.key.toLowerCase()}')
        .join(' · ');

    final (statusLabel, statusTone) = switch (overview.templateState(kind)) {
      WorkshopNoticeTemplateState.approved => (
          'Plantilla aprobada',
          roles.success
        ),
      WorkshopNoticeTemplateState.fallback => (
          'En revisión · sale con la anterior',
          roles.info,
        ),
      WorkshopNoticeTemplateState.pending => (
          'En revisión de Meta · espera',
          roles.warning,
        ),
      WorkshopNoticeTemplateState.rejected => (
          'Rechazada por Meta',
          roles.danger
        ),
      WorkshopNoticeTemplateState.missing => (
          'Falta crearla en Meta',
          roles.warning
        ),
      WorkshopNoticeTemplateState.unknown => (
          'No se pudo consultar a Meta',
          roles.neutral
        ),
    };

    Widget figure(int value, String label) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$value',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            Text(
              label,
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: roles.faintForeground),
            ),
          ],
        );

    return Semantics(
      container: true,
      label: '${kind.title}. ${email.sent} correos y ${whatsapp.sent} '
          'WhatsApp en 30 días. $statusLabel.',
      child: DecoratedBox(
        key: ValueKey('workshop-notice-moment-${kind.code}'),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: roles.hairline),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: ExcludeSemantics(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: tone.soft,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(_kindIcon(kind), size: 20, color: tone.tint),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        kind.title,
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  kind.when,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: roles.faintForeground),
                ),
                const SizedBox(height: 14),
                if (stretched) const Spacer(),
                Row(
                  children: [
                    figure(email.sent, 'correos'),
                    const SizedBox(width: 20),
                    figure(whatsapp.sent, 'WhatsApp'),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: statusTone.accent,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        statusLabel,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
                if (skippedLine.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Omitidos: $skippedLine',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: roles.faintForeground),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _WarrantyCard extends StatefulWidget {
  const _WarrantyCard({
    super.key,
    required this.days,
    required this.months,
    required this.canEdit,
    required this.onSave,
  });

  final int days;
  final int months;
  final bool canEdit;
  final Future<bool> Function(int days, int months) onSave;

  @override
  State<_WarrantyCard> createState() => _WarrantyCardState();
}

class _WarrantyCardState extends State<_WarrantyCard> {
  late final _days = TextEditingController(text: '${widget.days}');
  late final _months = TextEditingController(text: '${widget.months}');
  String? _daysError;
  String? _monthsError;
  bool _saving = false;

  @override
  void dispose() {
    _days.dispose();
    _months.dispose();
    super.dispose();
  }

  int? get _dayValue => int.tryParse(_days.text.trim());
  int? get _monthValue => int.tryParse(_months.text.trim());

  bool get _changed => _dayValue != widget.days || _monthValue != widget.months;

  Future<void> _save() async {
    const days = WorkshopCustomerNoticeService.serviceDaysRange;
    const months = WorkshopCustomerNoticeService.partsMonthsRange;
    final d = _dayValue;
    final m = _monthValue;
    setState(() {
      _daysError = d == null || d < days.min || d > days.max
          ? 'Entre ${days.min} y ${days.max} días.'
          : null;
      _monthsError = m == null || m < months.min || m > months.max
          ? 'Entre ${months.min} y ${months.max} meses.'
          : null;
    });
    if (_daysError != null || _monthsError != null) return;
    setState(() => _saving = true);
    await widget.onSave(d!, m!);
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final roles = VinabikeThemeRoles.of(context);
    final enabled = widget.canEdit && !_saving;
    Widget field({
      required Key key,
      required TextEditingController controller,
      required String label,
      required String suffix,
      required String? error,
    }) {
      return TextField(
        key: key,
        controller: controller,
        enabled: enabled,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        onChanged: (_) => setState(() {
          _daysError = null;
          _monthsError = null;
        }),
        decoration: InputDecoration(
          labelText: label,
          suffixText: suffix,
          errorText: error,
          border: const OutlineInputBorder(),
        ),
      );
    }

    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _SectionTitle('Garantía del taller'),
          const SizedBox(height: 6),
          Text(
            'Va en el comprobante de cada entrega. Cambiarla no toca los '
            'comprobantes ya emitidos.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: roles.faintForeground),
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: field(
                  key: const Key('workshop-warranty-days'),
                  controller: _days,
                  label: 'Servicio',
                  suffix: 'días',
                  error: _daysError,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: field(
                  key: const Key('workshop-warranty-months'),
                  controller: _months,
                  label: 'Repuestos',
                  suffix: 'meses',
                  error: _monthsError,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Sin perjuicio de la garantía legal de los productos '
            '(Ley 19.496).',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: roles.faintForeground),
          ),
          if (widget.canEdit) ...[
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: VbButton(
                key: const Key('workshop-warranty-save'),
                label: 'Guardar garantía',
                busy: _saving,
                onPressed: enabled && _changed ? _save : null,
              ),
            ),
          ] else ...[
            const SizedBox(height: 10),
            Text(
              'Sólo administración la cambia.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: roles.faintForeground),
            ),
          ],
        ],
      ),
    );
  }
}

class _RecentCard extends StatelessWidget {
  const _RecentCard({
    required this.records,
    required this.error,
    required this.onRetry,
  });

  final List<WorkshopNoticeRecord> records;
  final Object? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final roles = VinabikeThemeRoles.of(context);
    final time = DateFormat("d MMM, HH:mm", 'es_CL');
    return _Panel(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _SectionTitle('Lo último'),
          const SizedBox(height: 8),
          if (error != null && records.isEmpty)
            Row(
              children: [
                Expanded(
                  child: Text(
                    'No se pudo leer la lista.',
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ),
                TextButton(onPressed: onRetry, child: const Text('Reintentar')),
              ],
            )
          else if (records.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(
                'Todavía no sale ningún aviso. El primero sale con el próximo '
                'trabajo que se cree.',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: roles.faintForeground),
              ),
            )
          else
            for (final record in records)
              _RecentRow(record: record, time: time),
        ],
      ),
    );
  }
}

class _RecentRow extends StatelessWidget {
  const _RecentRow({required this.record, required this.time});

  final WorkshopNoticeRecord record;
  final DateFormat time;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final roles = VinabikeThemeRoles.of(context);
    final tone = _kindTone(roles, record.kind);
    final (stateLabel, stateTone) = switch (record.state) {
      'sent' => (
          'Enviado ${time.format(record.sentAt ?? record.createdAt)}',
          roles.success,
        ),
      'pending' || 'sending' => ('Por salir', roles.info),
      'failed' => (
          WorkshopCustomerNoticeService.reasonLabel(record.reason),
          roles.danger,
        ),
      _ => (
          WorkshopCustomerNoticeService.reasonLabel(record.reason),
          roles.neutral,
        ),
    };
    final who = [
      if (record.jobNumber != null) record.jobNumber!,
      if (record.customerName != null) record.customerName!,
    ].join(' · ');
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => context.push('/taller/pegas/${record.jobId}'),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 52),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: tone.soft,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(_kindIcon(record.kind), size: 18, color: tone.tint),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      who.isEmpty ? record.kind.title : who,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    Text(
                      '${record.kind.title} · ${record.channel.label}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: roles.faintForeground),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: stateTone.accent,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    stateLabel,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
