import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/desktop_update_service.dart';

class DesktopUpdatePrompt extends StatefulWidget {
  const DesktopUpdatePrompt({super.key});

  @override
  State<DesktopUpdatePrompt> createState() => _DesktopUpdatePromptState();
}

class _DesktopUpdatePromptState extends State<DesktopUpdatePrompt> {
  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<DesktopUpdateService>().checkForUpdate();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<DesktopUpdateService>(
      builder: (context, service, _) {
        final update = service.availableUpdate;
        if (!service.isSupported || update == null) {
          return const SizedBox.shrink();
        }

        final theme = Theme.of(context);
        final colorScheme = theme.colorScheme;

        return Positioned(
          top: 56,
          right: 72,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: Material(
              color: colorScheme.surface,
              elevation: 3,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  border: Border.all(color: colorScheme.outlineVariant),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.system_update_alt_rounded,
                          size: 22,
                          color: colorScheme.primary,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Actualizacion disponible',
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Hay una nueva version de Vinabike ERP lista para instalar.',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          tooltip: 'Cerrar',
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: service.isUpdating
                              ? null
                              : service.dismissAvailableUpdate,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: service.isUpdating
                              ? null
                              : service.dismissAvailableUpdate,
                          child: const Text('Mas tarde'),
                        ),
                        const SizedBox(width: 8),
                        FilledButton.icon(
                          onPressed: service.isUpdating
                              ? null
                              : () => _startUpdate(context),
                          icon: service.isUpdating
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.restart_alt_rounded, size: 18),
                          label: Text(
                            service.isUpdating ? 'Actualizando' : 'Actualizar',
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _startUpdate(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);

    try {
      await context.read<DesktopUpdateService>().startUpdate();
    } catch (_) {
      if (!context.mounted) return;
      messenger.showSnackBar(
        const SnackBar(
          content: Text('No se pudo iniciar la actualizacion.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}
