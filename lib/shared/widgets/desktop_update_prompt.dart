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
        final isCheckingOnly = service.isChecking && update == null;
        if (!service.isSupported || (update == null && !isCheckingOnly)) {
          return const SizedBox.shrink();
        }

        final theme = Theme.of(context);
        final colorScheme = theme.colorScheme;
        final hasPrepareError = update != null &&
            service.errorMessage != null &&
            !service.isPreparing &&
            !service.isUpdateReady &&
            !service.isUpdating;

        final String title;
        final String body;
        final IconData icon;
        final Color iconColor;
        final bool showProgress;
        final bool showActions;

        if (isCheckingOnly) {
          title = 'Buscando actualizaciones';
          body = 'Revisando si hay una nueva version disponible.';
          icon = Icons.system_update_alt_rounded;
          iconColor = colorScheme.primary;
          showProgress = true;
          showActions = false;
        } else if (service.isUpdating) {
          title = 'Reiniciando para actualizar';
          body = 'Cerrando Vinabike ERP y aplicando la nueva version.';
          icon = Icons.restart_alt_rounded;
          iconColor = colorScheme.primary;
          showProgress = true;
          showActions = true;
        } else if (hasPrepareError) {
          title = 'No se pudo preparar la actualizacion';
          body = service.errorMessage ?? 'Intentalo nuevamente en un momento.';
          icon = Icons.error_outline_rounded;
          iconColor = colorScheme.error;
          showProgress = false;
          showActions = true;
        } else if (service.isPreparing || !service.isUpdateReady) {
          title = 'Descargando actualizacion';
          body =
              'La nueva version se esta descargando. Puedes seguir trabajando.';
          icon = Icons.downloading_rounded;
          iconColor = colorScheme.primary;
          showProgress = true;
          showActions = true;
        } else {
          title = 'Actualizacion lista';
          body =
              'La nueva version ya esta descargada. Reinicia para aplicarla.';
          icon = Icons.system_update_alt_rounded;
          iconColor = colorScheme.primary;
          showProgress = false;
          showActions = true;
        }

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
                          icon,
                          size: 22,
                          color: iconColor,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title,
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                body,
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
                          onPressed: service.isUpdating || isCheckingOnly
                              ? null
                              : service.dismissAvailableUpdate,
                        ),
                      ],
                    ),
                    if (showProgress) ...[
                      const SizedBox(height: 12),
                      const LinearProgressIndicator(minHeight: 3),
                    ],
                    if (showActions) ...[
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: service.isUpdating
                                ? null
                                : service.dismissAvailableUpdate,
                            child:
                                Text(hasPrepareError ? 'Cerrar' : 'Mas tarde'),
                          ),
                          const SizedBox(width: 8),
                          FilledButton.icon(
                            onPressed: _primaryActionFor(context, service),
                            icon: _primaryIconFor(service, hasPrepareError),
                            label: Text(_primaryLabelFor(
                              service,
                              hasPrepareError,
                            )),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  VoidCallback? _primaryActionFor(
    BuildContext context,
    DesktopUpdateService service,
  ) {
    if (service.isUpdating || service.isPreparing) return null;
    if (service.errorMessage != null && !service.isUpdateReady) {
      return () => service.checkForUpdate(force: true);
    }
    if (!service.isUpdateReady) return null;
    return () => _startUpdate(context);
  }

  Widget _primaryIconFor(
    DesktopUpdateService service,
    bool hasPrepareError,
  ) {
    if (service.isUpdating || service.isPreparing) {
      return const SizedBox(
        width: 16,
        height: 16,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    if (hasPrepareError) {
      return const Icon(Icons.refresh_rounded, size: 18);
    }
    return const Icon(Icons.restart_alt_rounded, size: 18);
  }

  String _primaryLabelFor(
    DesktopUpdateService service,
    bool hasPrepareError,
  ) {
    if (service.isUpdating) return 'Reiniciando';
    if (hasPrepareError) return 'Reintentar';
    if (service.isPreparing || !service.isUpdateReady) return 'Descargando';
    return 'Reiniciar';
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
