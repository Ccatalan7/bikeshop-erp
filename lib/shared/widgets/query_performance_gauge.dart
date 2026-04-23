import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/query_performance_service.dart';
import '../services/right_toolbar_service.dart';

class QueryPerformanceGauge extends StatefulWidget {
  const QueryPerformanceGauge({super.key});

  @override
  State<QueryPerformanceGauge> createState() => _QueryPerformanceGaugeState();
}

class _QueryPerformanceGaugeState extends State<QueryPerformanceGauge> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    if (!QueryPerformanceService.isEnabled) {
      return const SizedBox.shrink();
    }

    final toolbarService = context.watch<RightToolbarService>();
    if (toolbarService.isGaugePinned) {
      return const SizedBox.shrink();
    }

    final service = QueryPerformanceService.instance;
    final theme = Theme.of(context);

    return AnimatedBuilder(
      animation: service,
      builder: (context, _) {
        final topTables = service.topTablesByBytes.take(3).toList();
        final lastEvent = service.lastEvent;

        return SafeArea(
          child: Align(
            alignment: Alignment.bottomRight,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Material(
                color: Colors.transparent,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: _isExpanded ? 320 : 210,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface.withValues(alpha: 0.96),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: theme.colorScheme.outlineVariant,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.08),
                        blurRadius: 16,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.speed_outlined,
                            size: 18,
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'DB Gauge',
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.push_pin_outlined, size: 18),
                            tooltip: 'Anclar a la barra derecha',
                            onPressed: () {
                              context
                                  .read<RightToolbarService>()
                                  .pinGaugeToToolbar();
                            },
                            visualDensity: VisualDensity.compact,
                          ),
                          IconButton(
                            icon: Icon(
                              _isExpanded
                                  ? Icons.unfold_less
                                  : Icons.unfold_more,
                              size: 18,
                            ),
                            tooltip: _isExpanded ? 'Contraer' : 'Expandir',
                            onPressed: () {
                              setState(() => _isExpanded = !_isExpanded);
                            },
                            visualDensity: VisualDensity.compact,
                          ),
                          IconButton(
                            icon: const Icon(Icons.restart_alt, size: 18),
                            tooltip: 'Reiniciar métricas',
                            onPressed: service.reset,
                            visualDensity: VisualDensity.compact,
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Sesion: ${service.formatBytes(service.totalEstimatedBytes)} · ${service.totalDurationMs} ms · ${service.readCount} lecturas',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: _GaugeStat(
                              label: 'Ultima',
                              value: lastEvent == null
                                  ? '--'
                                  : service
                                      .formatBytes(lastEvent.estimatedBytes),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _GaugeStat(
                              label: 'Tiempo',
                              value: lastEvent == null
                                  ? '--'
                                  : '${lastEvent.durationMs} ms',
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _GaugeStat(
                              label: 'Promedio',
                              value: '${service.averageDurationMs.round()} ms',
                            ),
                          ),
                        ],
                      ),
                      if (_isExpanded) ...[
                        const SizedBox(height: 12),
                        if (lastEvent != null)
                          Text(
                            'Ultima consulta: ${lastEvent.label} · ${lastEvent.rowCount} filas · ${lastEvent.operation}',
                            style: theme.textTheme.bodySmall,
                          ),
                        if (topTables.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          Text(
                            'Top tablas por MB',
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 6),
                          ...topTables.map(
                            (entry) => Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      entry.label,
                                      style: theme.textTheme.bodySmall,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    service.formatBytes(entry.estimatedBytes),
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    '${entry.averageDurationMs.round()} ms',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class QueryPerformanceToolbarPanel extends StatelessWidget {
  const QueryPerformanceToolbarPanel({super.key});

  @override
  Widget build(BuildContext context) {
    if (!QueryPerformanceService.isEnabled) {
      return const SizedBox.shrink();
    }

    final service = QueryPerformanceService.instance;
    final theme = Theme.of(context);

    return AnimatedBuilder(
      animation: service,
      builder: (context, _) {
        final topTables = service.topTablesByBytes.take(8).toList();
        final events = service.recentEvents.take(8).toList();
        final lastEvent = service.lastEvent;

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Sesión actual',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _GaugeStat(
                      label: 'Total',
                      value: service.formatBytes(service.totalEstimatedBytes),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _GaugeStat(
                      label: 'Lecturas',
                      value: '${service.readCount}',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _GaugeStat(
                      label: 'Tiempo',
                      value: '${service.totalDurationMs} ms',
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _GaugeStat(
                      label: 'Promedio',
                      value: '${service.averageDurationMs.round()} ms',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              FilledButton.tonalIcon(
                onPressed: service.reset,
                icon: const Icon(Icons.restart_alt),
                label: const Text('Reiniciar métricas'),
              ),
              if (lastEvent != null) ...[
                const SizedBox(height: 18),
                Text(
                  'Última consulta',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                _MetricCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        lastEvent.label,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${lastEvent.rowCount} filas · ${service.formatBytes(lastEvent.estimatedBytes)} · ${lastEvent.durationMs} ms · ${lastEvent.operation}',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
              if (topTables.isNotEmpty) ...[
                const SizedBox(height: 18),
                Text(
                  'Top tablas por MB',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                ...topTables.map(
                  (entry) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _MetricCard(
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              entry.label,
                              style: theme.textTheme.bodySmall,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            service.formatBytes(entry.estimatedBytes),
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${entry.averageDurationMs.round()} ms',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
              if (events.isNotEmpty) ...[
                const SizedBox(height: 18),
                Text(
                  'Lecturas recientes',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                ...events.map(
                  (event) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _MetricCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            event.label,
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${event.rowCount} filas · ${service.formatBytes(event.estimatedBytes)} · ${event.durationMs} ms',
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color:
            theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(10),
      ),
      child: child,
    );
  }
}

class _GaugeStat extends StatelessWidget {
  const _GaugeStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
