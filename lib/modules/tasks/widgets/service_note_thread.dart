import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../shared/themes/vinabike_theme_roles.dart';
import '../../../shared/widgets/vb_button.dart';
import '../../../shared/widgets/vb_overlay_surfaces.dart';
import '../../../shared/widgets/vb_segmented.dart' show VbDensity;
import '../../../shared/widgets/vb_status_badge.dart';
import '../models/smart_task_service_note.dart';

/// Notas por servicio de una tarea (dueño, 2026-09-27): el mismo bloque en
/// el detalle del ERP y en el portal del trabajador.
///
/// Bajo cada servicio se ve la nota vigente —quién y cuándo, si se corrigió y
/// cuántas tiene el hilo— y sus acciones: **Continuar** agrega una nota nueva
/// (la anterior queda en la historia), **Corregir** y **Retirar** son sólo de
/// quien la escribió, e **Historial** abre la línea de tiempo del servicio.

final DateFormat _shortStamp = DateFormat('dd/MM HH:mm');
final DateFormat _fullStamp = DateFormat('dd/MM/yyyy HH:mm');

class ServiceNoteBlock extends StatelessWidget {
  const ServiceNoteBlock({
    super.key,
    required this.jobItemId,
    required this.keyPrefix,
    required this.note,
    required this.onHistory,
    this.onWrite,
    this.onEdit,
    this.onWithdraw,
    this.density,
  });

  final String jobItemId;

  /// Prefijo de las llaves de prueba (`task-service-note` en el ERP,
  /// `worker-task-service-note` en el portal).
  final String keyPrefix;
  final ServiceNote? note;

  /// Agregar la primera o continuar. Null: quien mira no escribe aquí.
  final void Function(BuildContext anchorContext)? onWrite;

  /// Corregir / retirar la propia. Se ofrecen sólo si [ServiceNote.mine].
  final void Function(BuildContext anchorContext, ServiceNote note)? onEdit;
  final void Function(ServiceNote note)? onWithdraw;
  final void Function(BuildContext anchorContext) onHistory;
  final VbDensity? density;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final note = this.note;
    final muted = theme.colorScheme.onSurfaceVariant;

    Widget action(String suffix, String label, VoidCallback onPressed) =>
        VbButton(
          key: ValueKey('$keyPrefix-$suffix-$jobItemId'),
          label: label,
          variant: VbButtonVariant.text,
          density: density,
          onPressed: onPressed,
        );

    final actions = <Widget>[
      if (onWrite != null)
        Builder(
          builder: (anchor) => action(
            note == null ? 'add' : 'continue',
            note == null ? 'Agregar nota' : 'Continuar',
            () => onWrite!(anchor),
          ),
        ),
      if (note != null && note.mine && onEdit != null)
        Builder(
          builder: (anchor) =>
              action('edit', 'Corregir', () => onEdit!(anchor, note)),
        ),
      if (note != null && note.mine && onWithdraw != null)
        action('withdraw', 'Retirar', () => onWithdraw!(note)),
      Builder(
        builder: (anchor) =>
            action('history', 'Historial', () => onHistory(anchor)),
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (note != null) ...[
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child:
                    Icon(Icons.sticky_note_2_outlined, size: 13, color: muted),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      note.body,
                      key: ValueKey('$keyPrefix-body-$jobItemId'),
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.onSurface),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [
                        note.authorName ?? 'Alguien',
                        _shortStamp.format(note.createdAt.toLocal()),
                        if (note.isEdited) 'corregida',
                        if (note.count > 1) '${note.count} notas',
                      ].join(' · '),
                      style: theme.textTheme.labelSmall?.copyWith(color: muted),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
        Wrap(spacing: 2, runSpacing: 0, children: actions),
      ],
    );
  }
}

/// Lo que se le pide a quien escribe, según el modo.
enum ServiceNoteMode { first, continuing, correcting }

/// Pide el texto de una nota de servicio en el host dual (popover en
/// escritorio, hoja en compacto). Null si se canceló.
Future<String?> promptServiceNote({
  required BuildContext anchorContext,
  required String serviceName,
  required ServiceNoteMode mode,
  String? initialText,
}) {
  return showVbReasonPrompt(
    anchorContext: anchorContext,
    title: switch (mode) {
      ServiceNoteMode.first => 'Nota para «$serviceName»',
      ServiceNoteMode.continuing => 'Continuar la nota de «$serviceName»',
      ServiceNoteMode.correcting => 'Corregir tu nota',
    },
    hint: switch (mode) {
      ServiceNoteMode.first =>
        'Lo que hay que saber de este servicio (ej: la cadena ya viene cambiada)',
      ServiceNoteMode.continuing =>
        'Lo que sigue; la nota anterior queda en el historial',
      ServiceNoteMode.correcting => 'Lo que debía decir',
    },
    confirmLabel: switch (mode) {
      ServiceNoteMode.first => 'Guardar nota',
      ServiceNoteMode.continuing => 'Continuar nota',
      ServiceNoteMode.correcting => 'Guardar',
    },
    initialText: initialText,
  );
}

/// Abre la línea de tiempo de un servicio: encargo, cada nota escrita,
/// continuada, corregida (con lo que decía) o retirada, hecho / pendiente y
/// lo que cambió el taller. Lo más reciente arriba; la vigente, marcada.
Future<void> showServiceNoteTimeline({
  required BuildContext anchorContext,
  required String serviceName,
  required Future<List<ServiceTimelineEntry>> Function() load,
}) {
  return showVbSurface<void>(
    anchorContext: anchorContext,
    title: 'Historial de «$serviceName»',
    maxWidth: 480,
    builder: (_) => _ServiceTimelineBody(load: load),
  );
}

class _ServiceTimelineBody extends StatefulWidget {
  const _ServiceTimelineBody({required this.load});

  final Future<List<ServiceTimelineEntry>> Function() load;

  @override
  State<_ServiceTimelineBody> createState() => _ServiceTimelineBodyState();
}

class _ServiceTimelineBodyState extends State<_ServiceTimelineBody> {
  late Future<List<ServiceTimelineEntry>> _entries = widget.load();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
      child: FutureBuilder<List<ServiceTimelineEntry>>(
        future: _entries,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Row(
              children: [
                Expanded(
                  child: Text('No se pudo leer el historial.',
                      style: theme.textTheme.bodySmall),
                ),
                VbButton(
                  label: 'Reintentar',
                  variant: VbButtonVariant.text,
                  onPressed: () => setState(() => _entries = widget.load()),
                ),
              ],
            );
          }
          if (!snapshot.hasData) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            );
          }
          final entries = snapshot.data!;
          if (entries.isEmpty) {
            return Text('Sin historia registrada todavía.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant));
          }
          return Column(
            key: const ValueKey('service-timeline'),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < entries.length; i++)
                _TimelineRow(
                  entry: entries[i],
                  isLast: i == entries.length - 1,
                ),
            ],
          );
        },
      ),
    );
  }
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({required this.entry, required this.isLast});

  final ServiceTimelineEntry entry;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final roles = VinabikeThemeRoles.maybeOf(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final who = entry.actorName ?? 'Alguien';
    final (IconData icon, Color color, String what) = switch (entry.kind) {
      ServiceTimelineKind.assigned => (
          Icons.assignment_ind_outlined,
          muted,
          '$who encargó el servicio'
        ),
      ServiceTimelineKind.noteWritten => (
          Icons.sticky_note_2_outlined,
          theme.colorScheme.primary,
          '$who escribió una nota'
        ),
      ServiceTimelineKind.noteContinued => (
          Icons.sticky_note_2_outlined,
          theme.colorScheme.primary,
          '$who continuó la nota'
        ),
      ServiceTimelineKind.noteEdited => (
          Icons.edit_outlined,
          theme.colorScheme.primary,
          '$who corrigió su nota'
        ),
      ServiceTimelineKind.noteWithdrawn => (
          Icons.remove_circle_outline,
          muted,
          '$who retiró su nota'
        ),
      ServiceTimelineKind.done => (
          Icons.check_circle,
          roles?.success.accent ?? theme.colorScheme.primary,
          '$who lo marcó hecho'
        ),
      ServiceTimelineKind.reopened => (
          Icons.replay,
          muted,
          '$who lo volvió a pendiente'
        ),
      ServiceTimelineKind.serviceChanged => (
          Icons.sync_problem,
          theme.colorScheme.tertiary,
          'El taller cambió este servicio en el trabajo'
        ),
      ServiceTimelineKind.serviceRemoved => (
          Icons.link_off,
          roles?.danger.accent ?? theme.colorScheme.error,
          'El taller sacó este servicio del trabajo'
        ),
      ServiceTimelineKind.unknown => (Icons.circle_outlined, muted, who),
    };
    final crossedOut = theme.textTheme.bodySmall?.copyWith(
      color: muted,
      decoration: TextDecoration.lineThrough,
    );

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // El hilo: un punto por hecho, unidos por una línea.
          SizedBox(
            width: 20,
            child: Column(
              children: [
                Icon(icon, size: 16, color: color),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 1,
                      margin: const EdgeInsets.symmetric(vertical: 2),
                      color: theme.colorScheme.outlineVariant,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 6,
                    runSpacing: 2,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(what,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(fontWeight: FontWeight.w600)),
                      if (entry.isCurrent)
                        const VbStatusBadge(
                          label: 'Vigente',
                          tone: VbStatusTone.info,
                          dense: true,
                        ),
                    ],
                  ),
                  Text(
                    [
                      _fullStamp.format(entry.occurredAt.toLocal()),
                      if (entry.fromPortal == true) 'desde su portal',
                      if (entry.atCreate) 'con el encargo',
                    ].join(' · '),
                    style: theme.textTheme.labelSmall?.copyWith(color: muted),
                  ),
                  if (entry.note != null) ...[
                    const SizedBox(height: 4),
                    Text(entry.note!, style: theme.textTheme.bodySmall),
                  ],
                  if (entry.previousNote != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      entry.kind == ServiceTimelineKind.noteEdited
                          ? 'Decía: ${entry.previousNote}'
                          : entry.previousNote!,
                      style: crossedOut,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
