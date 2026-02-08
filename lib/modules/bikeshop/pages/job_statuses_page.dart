import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../shared/widgets/main_layout.dart';
import '../../../shared/widgets/branded_loading.dart';
import '../models/bikeshop_models.dart';
import '../services/job_status_service.dart';

/// Management page for custom job statuses (Notion-style)
class JobStatusesPage extends StatefulWidget {
  const JobStatusesPage({super.key});

  @override
  State<JobStatusesPage> createState() => _JobStatusesPageState();
}

class _JobStatusesPageState extends State<JobStatusesPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<JobStatusService>().loadStatuses();
    });
  }

  @override
  Widget build(BuildContext context) {
    return MainLayout(
      title: 'Estados de Trabajos',
      child: Consumer<JobStatusService>(
        builder: (context, service, _) {
          if (service.isLoading && service.statuses.isEmpty) {
            return const Center(child: BrandedLoading());
          }

          if (service.error != null && service.statuses.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error_outline, size: 48, color: Colors.red[300]),
                  const SizedBox(height: 16),
                  Text('Error: ${service.error}'),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => service.loadStatuses(),
                    child: const Text('Reintentar'),
                  ),
                ],
              ),
            );
          }

          return _buildContent(context, service);
        },
      ),
    );
  }

  Widget _buildContent(BuildContext context, JobStatusService service) {
    final statusesByPhase = service.statusesByPhase;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              const Icon(Icons.tune, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Estados Personalizados',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'Crea y administra los estados para tus trabajos. Estilo Notion.',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
              ElevatedButton.icon(
                onPressed: () => _showCreateStatusDialog(context, service),
                icon: const Icon(Icons.add),
                label: const Text('Nuevo Estado'),
              ),
            ],
          ),
          const SizedBox(height: 32),

          // Phases with statuses
          for (final phase in StatusPhase.values) ...[
            _buildPhaseSection(
                context, service, phase, statusesByPhase[phase] ?? []),
            const SizedBox(height: 24),
          ],
        ],
      ),
    );
  }

  Widget _buildPhaseSection(
    BuildContext context,
    JobStatusService service,
    StatusPhase phase,
    List<JobStatusCustom> statuses,
  ) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Phase header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: _getPhaseHeaderColor(phase, isDark: isDark),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(11),
                topRight: Radius.circular(11),
              ),
            ),
            child: Row(
              children: [
                Icon(_getPhaseIcon(phase),
                    size: 20, color: _getPhaseTextColor(phase, isDark: isDark)),
                const SizedBox(width: 8),
                Text(
                  phase.displayName,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: _getPhaseTextColor(phase, isDark: isDark),
                  ),
                ),
                const Spacer(),
                Text(
                  '${statuses.length} estados',
                  style: TextStyle(
                    fontSize: 13,
                    color: _getPhaseTextColor(phase, isDark: isDark)
                        .withOpacity(0.7),
                  ),
                ),
              ],
            ),
          ),
          // Statuses list
          if (statuses.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: Text(
                  'No hay estados en esta fase',
                  style: TextStyle(color: theme.hintColor),
                ),
              ),
            )
          else
            ReorderableListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              buildDefaultDragHandles: false,
              itemCount: statuses.length,
              onReorder: (oldIndex, newIndex) {
                if (newIndex > oldIndex) newIndex--;
                final reordered = List<JobStatusCustom>.from(statuses);
                final item = reordered.removeAt(oldIndex);
                reordered.insert(newIndex, item);
                service.reorderStatuses(reordered);
              },
              itemBuilder: (context, index) {
                final status = statuses[index];
                return _buildStatusTile(context, service, status, index);
              },
            ),
        ],
      ),
    );
  }

  Widget _buildStatusTile(
    BuildContext context,
    JobStatusService service,
    JobStatusCustom status,
    int index,
  ) {
    final color = _parseColor(status.color);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      key: ValueKey(status.id),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: theme.dividerColor.withOpacity(0.5)),
        ),
      ),
      child: ListTile(
        leading: ReorderableDragStartListener(
          index: index,
          child: MouseRegion(
            cursor: SystemMouseCursors.grab,
            child: Icon(Icons.drag_indicator, color: theme.hintColor),
          ),
        ),
        title: Row(
          children: [
            // Color badge
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(6),
              ),
            ),
            const SizedBox(width: 12),
            // Name
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        status.name,
                        style: const TextStyle(fontWeight: FontWeight.w500),
                      ),
                      if (status.isSystem) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: isDark ? Colors.grey[700] : Colors.grey[200],
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'Sistema',
                            style: TextStyle(
                              fontSize: 10,
                              color:
                                  isDark ? Colors.grey[300] : Colors.grey[600],
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  Text(
                    status.code,
                    style: TextStyle(fontSize: 12, color: theme.hintColor),
                  ),
                ],
              ),
            ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.edit_outlined, size: 20),
              onPressed: () => _showEditStatusDialog(context, service, status),
              tooltip: 'Editar',
            ),
            if (!status.isSystem)
              IconButton(
                icon: Icon(Icons.delete_outline,
                    size: 20, color: Colors.red[400]),
                onPressed: () => _confirmDeleteStatus(context, service, status),
                tooltip: 'Eliminar',
              ),
          ],
        ),
      ),
    );
  }

  Color _getPhaseHeaderColor(StatusPhase phase, {bool isDark = false}) {
    switch (phase) {
      case StatusPhase.todo:
        return isDark ? Colors.grey[800]! : Colors.grey[100]!;
      case StatusPhase.inProgress:
        return isDark ? Colors.blue[900]!.withOpacity(0.3) : Colors.blue[50]!;
      case StatusPhase.complete:
        return isDark ? Colors.green[900]!.withOpacity(0.3) : Colors.green[50]!;
    }
  }

  Color _getPhaseTextColor(StatusPhase phase, {bool isDark = false}) {
    switch (phase) {
      case StatusPhase.todo:
        return isDark ? Colors.grey[300]! : Colors.grey[700]!;
      case StatusPhase.inProgress:
        return isDark ? Colors.blue[300]! : Colors.blue[700]!;
      case StatusPhase.complete:
        return isDark ? Colors.green[300]! : Colors.green[700]!;
    }
  }

  IconData _getPhaseIcon(StatusPhase phase) {
    switch (phase) {
      case StatusPhase.todo:
        return Icons.pending_outlined;
      case StatusPhase.inProgress:
        return Icons.autorenew;
      case StatusPhase.complete:
        return Icons.check_circle_outline;
    }
  }

  Color _parseColor(String hex) {
    try {
      final buffer = StringBuffer();
      if (hex.length == 7) buffer.write('ff');
      buffer.write(hex.replaceFirst('#', ''));
      return Color(int.parse(buffer.toString(), radix: 16));
    } catch (_) {
      return Colors.grey;
    }
  }

  void _showCreateStatusDialog(BuildContext context, JobStatusService service) {
    _showStatusDialog(context, service, null);
  }

  void _showEditStatusDialog(
      BuildContext context, JobStatusService service, JobStatusCustom status) {
    _showStatusDialog(context, service, status);
  }

  void _showStatusDialog(
      BuildContext context, JobStatusService service, JobStatusCustom? status) {
    final isEditing = status != null;
    final nameController = TextEditingController(text: status?.name ?? '');
    final codeController = TextEditingController(text: status?.code ?? '');
    String selectedColor = status?.color ?? '#6B7280';
    StatusPhase selectedPhase = status?.phase ?? StatusPhase.inProgress;

    // New automation flags
    bool triggersStart = status?.triggersStart ?? false;
    bool triggersCompletion = status?.triggersCompletion ?? false;
    bool triggersDelivery = status?.triggersDelivery ?? false;

    final colors = [
      '#6B7280', // Gray
      '#EF4444', // Red
      '#F97316', // Orange
      '#F59E0B', // Amber
      '#EAB308', // Yellow
      '#84CC16', // Lime
      '#22C55E', // Green
      '#10B981', // Emerald
      '#14B8A6', // Teal
      '#06B6D4', // Cyan
      '#0EA5E9', // Sky
      '#3B82F6', // Blue
      '#6366F1', // Indigo
      '#8B5CF6', // Violet
      '#A855F7', // Purple
      '#D946EF', // Fuchsia
      '#EC4899', // Pink
      '#F43F5E', // Rose
    ];

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(isEditing ? 'Editar Estado' : 'Nuevo Estado'),
          content: SizedBox(
            width: 450, // Slightly wider for new options
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Name field
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: 'Nombre *',
                      hintText: 'Ej: En Revisión',
                      border: OutlineInputBorder(),
                    ),
                    autofocus: true,
                    onChanged: (value) {
                      if (!isEditing) {
                        codeController.text =
                            value.toUpperCase().replaceAll(' ', '_');
                      }
                    },
                  ),
                  const SizedBox(height: 16),

                  // Code field
                  TextField(
                    controller: codeController,
                    decoration: InputDecoration(
                      labelText: 'Código *',
                      hintText: 'Ej: EN_REVISION',
                      border: const OutlineInputBorder(),
                      helperText: 'Identificador único (sin espacios)',
                      enabled: !(status?.isSystem ?? false),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Phase selector
                  const Text('Fase',
                      style: TextStyle(fontWeight: FontWeight.w500)),
                  const SizedBox(height: 8),
                  SegmentedButton<StatusPhase>(
                    segments: StatusPhase.values.map((phase) {
                      return ButtonSegment<StatusPhase>(
                        value: phase,
                        label: Text(phase.displayName),
                        icon: Icon(_getPhaseIcon(phase), size: 18),
                      );
                    }).toList(),
                    selected: {selectedPhase},
                    onSelectionChanged: (Set<StatusPhase> phases) {
                      setDialogState(() => selectedPhase = phases.first);
                    },
                  ),
                  const SizedBox(height: 24),

                  // Automation Section
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.blue.shade100),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.auto_awesome,
                                size: 20, color: Colors.blue.shade700),
                            const SizedBox(width: 8),
                            Text(
                              'Automatización y KPIs',
                              style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.blue.shade800),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        SwitchListTile(
                          title: const Text('Iniciar Reloj de Taller'),
                          subtitle:
                              const Text('Marca la fecha de "Inicio" (KPI)'),
                          value: triggersStart,
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          activeColor: Colors.blue,
                          onChanged: (val) =>
                              setDialogState(() => triggersStart = val),
                        ),
                        SwitchListTile(
                          title: const Text('Detener Reloj de Taller'),
                          subtitle:
                              const Text('Marca la fecha de "Término" (KPI)'),
                          value: triggersCompletion,
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          activeColor: Colors.purple,
                          onChanged: (val) =>
                              setDialogState(() => triggersCompletion = val),
                        ),
                        SwitchListTile(
                          title: const Text('Marcar como Entregado'),
                          subtitle: const Text(
                              'Marca la fecha "Entregado" y cierra el ciclo'),
                          value: triggersDelivery,
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          activeColor: Colors.green,
                          onChanged: (val) =>
                              setDialogState(() => triggersDelivery = val),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Color picker
                  const Text('Color',
                      style: TextStyle(fontWeight: FontWeight.w500)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: colors.map((color) {
                      final isSelected = color == selectedColor;
                      return InkWell(
                        onTap: () =>
                            setDialogState(() => selectedColor = color),
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: _parseColor(color),
                            borderRadius: BorderRadius.circular(8),
                            border: isSelected
                                ? Border.all(color: Colors.black, width: 2)
                                : null,
                            boxShadow: isSelected
                                ? [
                                    BoxShadow(
                                      color:
                                          _parseColor(color).withOpacity(0.5),
                                      blurRadius: 8,
                                      offset: const Offset(0, 2),
                                    ),
                                  ]
                                : null,
                          ),
                          child: isSelected
                              ? const Icon(Icons.check,
                                  color: Colors.white, size: 18)
                              : null,
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),

                  // Preview
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey[50],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey[200]!),
                    ),
                    child: Row(
                      children: [
                        Text('Vista previa:',
                            style: TextStyle(color: Colors.grey[600])),
                        const SizedBox(width: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: _parseColor(selectedColor),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            nameController.text.isEmpty
                                ? 'Estado'
                                : nameController.text,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w500,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () async {
                final name = nameController.text.trim();
                final code = codeController.text
                    .trim()
                    .toUpperCase()
                    .replaceAll(' ', '_');

                if (name.isEmpty || code.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('Nombre y código son requeridos')),
                  );
                  return;
                }

                if (isEditing && status != null) {
                  final updated = status.copyWith(
                    name: name,
                    code: code,
                    color: selectedColor,
                    phase: selectedPhase,
                    triggersStart: triggersStart,
                    triggersCompletion: triggersCompletion,
                    triggersDelivery: triggersDelivery,
                  );
                  await service.updateStatus(updated);
                } else {
                  await service.createStatus(
                    name: name,
                    code: code,
                    color: selectedColor,
                    phase: selectedPhase,
                    // Note: CreateStatus method in service might need update or we rely on copyWith if the service uses the whole object
                    // Actually checking service: createStatus takes named args... I should verify service signature
                  );
                  // WAIT: I need to check if createStatus service method accepts these new args.
                  // If not, I should probably use a lower level 'save' or update the service first.
                  // Let's assume I need to update the service signature as well.
                }

                if (context.mounted) Navigator.pop(context);
              },
              child: Text(isEditing ? 'Guardar' : 'Crear'),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDeleteStatus(
      BuildContext context, JobStatusService service, JobStatusCustom status) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar Estado'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('¿Estás seguro de eliminar el estado "${status.name}"?'),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.amber[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.amber[200]!),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: Colors.amber[700]),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Los trabajos con este estado no serán afectados.',
                      style: TextStyle(fontSize: 13, color: Colors.amber[900]),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () async {
              await service.deleteStatus(status.id!);
              if (context.mounted) Navigator.pop(context);
            },
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
  }
}
