import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/bikeshop_models.dart';

/// Compact, shared table representation of the canonical lifecycle metrics.
/// It intentionally has no fallback to mutable legacy timestamps.
class CompactJobTimeMetrics extends StatelessWidget {
  const CompactJobTimeMetrics({super.key, required this.job});

  final MechanicJob job;

  @override
  Widget build(BuildContext context) {
    final metrics = job.timeMetrics;
    if (metrics == null) {
      return const Tooltip(
        message:
            'No fue posible leer la fuente canónica de tiempos. Actualiza para volver a intentar.',
        child: Center(
          child:
              Icon(Icons.sync_problem_outlined, size: 17, color: Colors.grey),
        ),
      );
    }

    final stages = _coreStages(job, metrics);
    return Semantics(
      label: stages.map((stage) => stage.tooltip).join('. '),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var index = 0; index < stages.length; index++) ...[
            _CompactStage(stage: stages[index]),
            if (index < stages.length - 1)
              Expanded(
                child: Container(
                  height: 1.5,
                  color: stages[index + 1].color.withValues(alpha: 0.28),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

/// One coherent timeline for the job detail surface. Missing or reconstructed
/// evidence remains visible instead of being converted into fabricated KPIs.
class JobTimeMetricsPanel extends StatelessWidget {
  const JobTimeMetricsPanel({super.key, required this.job});

  final MechanicJob job;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final metrics = job.timeMetrics;
    if (metrics == null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color:
              theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(Icons.sync_problem_outlined,
                color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'La fuente canónica de tiempos no está disponible. Actualiza para volver a intentar.',
              ),
            ),
          ],
        ),
      );
    }

    final stages = <_TimeStage>[
      if (job.requiresApproval || metrics.approvalDecisionAt != null)
        _approvalStage(job, metrics),
      ..._coreStages(job, metrics),
    ];
    final warnings = metrics.qualityFlags
        .map(_qualityFlagLabel)
        .whereType<String>()
        .toList(growable: false);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            theme.colorScheme.primary.withValues(alpha: 0.055),
            theme.colorScheme.surface,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final narrow = constraints.maxWidth < 620;
              if (narrow) {
                return Wrap(
                  spacing: 18,
                  runSpacing: 18,
                  children: stages
                      .map((stage) => SizedBox(
                            width: constraints.maxWidth < 360
                                ? constraints.maxWidth
                                : (constraints.maxWidth - 18) / 2,
                            child: _DetailedStage(stage: stage),
                          ))
                      .toList(growable: false),
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var index = 0; index < stages.length; index++) ...[
                    Expanded(child: _DetailedStage(stage: stages[index])),
                    if (index < stages.length - 1)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Icon(
                          Icons.arrow_forward_rounded,
                          size: 16,
                          color: theme.colorScheme.outlineVariant,
                        ),
                      ),
                  ],
                ],
              );
            },
          ),
          if (job.actualLaborHours != null ||
              metrics.hasReconstructedEvidence ||
              warnings.isNotEmpty) ...[
            const SizedBox(height: 16),
            Divider(
              height: 1,
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.55),
            ),
            const SizedBox(height: 11),
          ],
          if (job.actualLaborHours != null)
            _EvidenceLine(
              icon: Icons.engineering_outlined,
              color: const Color(0xFF5E35B1),
              text:
                  '${_formatHours(job.actualLaborHours!)} de trabajo mecánico imputado',
            ),
          if (metrics.hasReconstructedEvidence)
            const _EvidenceLine(
              icon: Icons.history_rounded,
              color: Color(0xFF546E7A),
              text:
                  'Algunos hitos fueron reconstruidos desde eventos históricos; no se reescribió la ficha.',
            ),
          for (final warning in warnings)
            _EvidenceLine(
              icon: Icons.error_outline_rounded,
              color: const Color(0xFFE65100),
              text: warning,
            ),
        ],
      ),
    );
  }
}

class _CompactStage extends StatelessWidget {
  const _CompactStage({required this.stage});

  final _TimeStage stage;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: stage.tooltip,
      waitDuration: const Duration(milliseconds: 250),
      child: Container(
        width: 22,
        height: 22,
        decoration: BoxDecoration(
          color: stage.color.withValues(alpha: 0.12),
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: Icon(stage.icon, size: 13, color: stage.color),
      ),
    );
  }
}

class _DetailedStage extends StatelessWidget {
  const _DetailedStage({required this.stage});

  final _TimeStage stage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      label: stage.tooltip,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: stage.color.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Icon(stage.icon, size: 16, color: stage.color),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  stage.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  stage.value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: stage.color,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  stage.detail,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
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

class _EvidenceLine extends StatelessWidget {
  const _EvidenceLine({
    required this.icon,
    required this.color,
    required this.text,
  });

  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 7),
          Expanded(
            child: Text(text, style: Theme.of(context).textTheme.bodySmall),
          ),
        ],
      ),
    );
  }
}

class _TimeStage {
  const _TimeStage({
    required this.label,
    required this.value,
    required this.detail,
    required this.tooltip,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final String detail;
  final String tooltip;
  final IconData icon;
  final Color color;
}

List<_TimeStage> _coreStages(
  MechanicJob job,
  MechanicJobTimeMetrics metrics,
) {
  final now = DateTime.now();
  final terminal = metrics.currentIsCompleted || metrics.currentIsDelivered;
  final waitOrigin = metrics.approvalDecision == 'approved' &&
          metrics.approvalDecisionAt != null
      ? metrics.approvalDecisionAt!
      : job.arrivalDate;
  final waitEnd = metrics.startedAt ?? (terminal ? null : now);
  final waitDuration = waitEnd?.difference(waitOrigin);
  final executionEnd = metrics.completedAt ??
      (metrics.startedAt != null && !metrics.currentIsCompleted ? now : null);
  final executionDuration = metrics.startedAt == null
      ? null
      : executionEnd?.difference(metrics.startedAt!);
  final cycleEnd =
      metrics.firstDeliveredAt ?? (metrics.currentIsDelivered ? null : now);
  final cycleDuration = cycleEnd?.difference(job.arrivalDate);

  final waitLive = metrics.startedAt == null && !terminal;
  final executionLive = metrics.startedAt != null &&
      metrics.completedAt == null &&
      !metrics.currentIsCompleted;
  final cycleLive =
      metrics.firstDeliveredAt == null && !metrics.currentIsDelivered;

  return [
    _TimeStage(
      label: 'Espera a taller',
      value: _safeDuration(waitDuration),
      detail: waitLive
          ? 'en curso · tiempo calendario'
          : metrics.startedAt == null
              ? 'sin registro de inicio'
              : 'hasta el inicio · calendario',
      tooltip: waitLive
          ? 'Espera a taller: ${_safeDuration(waitDuration)} (en curso)\n'
              '${metrics.approvalDecision == 'approved' ? 'Aprobación' : 'Recepción'} → inicio de trabajo\n'
              'Inicio aún no registrado'
          : 'Espera a taller: ${_safeDuration(waitDuration)}\n'
              '${metrics.approvalDecision == 'approved' ? 'Aprobación' : 'Recepción'} → inicio de trabajo\n'
              '${_sourceDescription(metrics.startSource)}',
      icon: waitLive ? Icons.hourglass_top_rounded : Icons.play_arrow_rounded,
      color: metrics.startedAt != null
          ? const Color(0xFF1976D2)
          : terminal
              ? const Color(0xFFE65100)
              : const Color(0xFFF9A825),
    ),
    _TimeStage(
      label: 'Ejecución',
      value: _safeDuration(executionDuration),
      detail: executionLive
          ? 'en curso · tiempo calendario'
          : metrics.completedAt == null
              ? 'sin registro de término'
              : 'inicio a término · calendario',
      tooltip: executionLive
          ? 'Ejecución: ${_safeDuration(executionDuration)} (en curso)\n'
              'Inicio → término · incluye pausas y esperas de repuestos'
          : 'Ejecución: ${_safeDuration(executionDuration)}\n'
              'Inicio → término · incluye pausas y esperas de repuestos\n'
              '${_sourceDescription(metrics.completionSource)}',
      icon: executionLive ? Icons.build_rounded : Icons.task_alt_rounded,
      color: metrics.completedAt != null
          ? const Color(0xFF2E7D32)
          : executionLive
              ? const Color(0xFF5E35B1)
              : terminal
                  ? const Color(0xFFE65100)
                  : const Color(0xFF90A4AE),
    ),
    _TimeStage(
      label: metrics.reopenedAfterDelivery ? 'Primera entrega' : 'Ciclo total',
      value: _safeDuration(cycleDuration),
      detail: metrics.reopenedAfterDelivery
          ? 'reabierto después · calendario'
          : cycleLive
              ? 'en curso · tiempo calendario'
              : metrics.firstDeliveredAt == null
                  ? 'sin registro de entrega'
                  : 'recepción a 1ª entrega · calendario',
      tooltip: cycleLive
          ? '${metrics.reopenedAfterDelivery ? 'Primera entrega' : 'Ciclo total'}: ${_safeDuration(cycleDuration)} (en curso)\n'
              'Recepción → primera entrega\n'
              'Entrega aún no registrada'
          : '${metrics.reopenedAfterDelivery ? 'Primera entrega' : 'Ciclo total'}: ${_safeDuration(cycleDuration)}\n'
              'Recepción → primera entrega\n'
              '${_sourceDescription(metrics.deliverySource)}',
      icon: metrics.reopenedAfterDelivery
          ? Icons.replay_rounded
          : metrics.firstDeliveredAt != null
              ? Icons.flag_rounded
              : Icons.timelapse_rounded,
      color: metrics.firstDeliveredAt != null
          ? const Color(0xFF00897B)
          : metrics.currentIsDelivered
              ? const Color(0xFFE65100)
              : const Color(0xFF607D8B),
    ),
  ];
}

_TimeStage _approvalStage(
  MechanicJob job,
  MechanicJobTimeMetrics metrics,
) {
  final duration = metrics.approvalDecisionAt?.difference(job.arrivalDate);
  final rejected = metrics.approvalDecision == 'rejected';
  final missing = metrics.approvalDecisionAt == null;
  final color = missing
      ? const Color(0xFFE65100)
      : rejected
          ? const Color(0xFFC62828)
          : const Color(0xFF00897B);
  return _TimeStage(
    label: 'Decisión cliente',
    value: _safeDuration(duration),
    detail: missing
        ? 'sin decisión comprobable'
        : rejected
            ? 'presupuesto rechazado'
            : 'presupuesto aprobado',
    tooltip:
        'Decisión del cliente: ${_safeDuration(duration)}. Recepción → decisión. ${_sourceDescription(metrics.approvalSource)}',
    icon: missing
        ? Icons.help_outline_rounded
        : rejected
            ? Icons.close_rounded
            : Icons.done_rounded,
    color: color,
  );
}

String _safeDuration(Duration? duration) {
  if (duration == null || duration.isNegative) return 'Sin dato';
  if (duration.inDays > 0) {
    return '${duration.inDays} d ${duration.inHours.remainder(24)} h';
  }
  if (duration.inHours > 0) {
    return '${duration.inHours} h ${duration.inMinutes.remainder(60)} min';
  }
  return '${duration.inMinutes} min';
}

String _sourceDescription(String? source) {
  return switch (source) {
    'recorded_timestamp' => 'Hito registrado con hora exacta',
    'mode_event' => 'Decisión registrada con hora exacta',
    'status_transition' => 'Transición registrada con hora exacta',
    'legacy_timeline' => 'Estimación según historial de estados',
    'legacy_current_state' => 'Estimación según último estado conocido',
    // Desde el 05-08-2026 cada cambio de estado queda registrado con su hora
    // exacta; las pegas anteriores no tienen ese dato y no se inventa.
    null => 'Hito sin registro',
    _ => 'Evento ${source.replaceAll('_', ' ')}',
  };
}

String? _qualityFlagLabel(String flag) {
  return switch (flag) {
    'approval_missing_when_required' =>
      'Este trabajo requería aprobación, pero no existe una decisión fechada.',
    'start_missing_when_terminal' =>
      'El trabajo terminó sin un inicio de taller comprobable.',
    'completion_missing_when_delivered' =>
      'La bicicleta fue entregada sin un término de taller comprobable.',
    'delivery_event_missing_when_delivered' =>
      'El estado dice entregado, pero no existe un evento de entrega confiable.',
    'delivery_before_arrival' =>
      'Existe una entrega histórica anterior a la recepción; fue descartada.',
    'deadline_before_arrival' =>
      'El plazo de entrega quedó registrado antes de la recepción.',
    'recorded_start_before_arrival' =>
      'El inicio guardado precede a la recepción y fue descartado.',
    'recorded_completion_before_start' =>
      'El término guardado precede al inicio y fue descartado.',
    _ => null,
  };
}

String _formatHours(double hours) {
  final formatter = NumberFormat('#,##0.##', 'es_CL');
  return '${formatter.format(hours)} h';
}
