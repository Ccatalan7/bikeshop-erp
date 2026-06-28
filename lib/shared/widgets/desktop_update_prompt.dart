import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/desktop_update_service.dart';

class DesktopUpdatePrompt extends StatefulWidget {
  const DesktopUpdatePrompt({super.key});

  @override
  State<DesktopUpdatePrompt> createState() => _DesktopUpdatePromptState();
}

class _DesktopUpdatePromptState extends State<DesktopUpdatePrompt> {
  static const _pollInterval = Duration(minutes: 1);

  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<DesktopUpdateService>().checkForUpdate();
    });

    _pollTimer = Timer.periodic(_pollInterval, (_) {
      if (!mounted) return;

      final service = context.read<DesktopUpdateService>();
      if (!service.isSupported || service.isUpdating) return;

      service.checkForUpdate(
        force: true,
        revealDismissed: false,
      );
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<DesktopUpdateService>(
      builder: (context, service, _) {
        if (!service.isSupported) {
          return const SizedBox.shrink();
        }

        if (service.hasDismissedReadyUpdate) {
          return _buildCollapsedUpdateButton(context, service);
        }

        final update = service.availableUpdate;
        if (update == null) {
          return const SizedBox.shrink();
        }

        final theme = Theme.of(context);
        final colorScheme = theme.colorScheme;
        final hasPrepareError = service.errorMessage != null &&
            !service.isPreparing &&
            !service.isUpdateReady &&
            !service.isUpdating;

        if (!service.isUpdating && !service.isUpdateReady && !hasPrepareError) {
          return const SizedBox.shrink();
        }

        final String title;
        final String? body;
        final IconData icon;
        final Color iconColor;
        final bool showProgress;

        if (service.isUpdating) {
          title = 'Reiniciando para actualizar';
          body = null;
          icon = Icons.restart_alt_rounded;
          iconColor = colorScheme.primary;
          showProgress = true;
        } else if (hasPrepareError) {
          title = 'No se pudo preparar la actualizacion';
          body = service.errorMessage ?? 'Intentalo nuevamente en un momento.';
          icon = Icons.error_outline_rounded;
          iconColor = colorScheme.error;
          showProgress = false;
        } else {
          title = 'Actualizacion lista';
          body = 'Reinicia cuando puedas.';
          icon = Icons.system_update_alt_rounded;
          iconColor = colorScheme.primary;
          showProgress = false;
        }

        return Positioned(
          top: 56,
          right: 72,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 330),
            child: Material(
              color: colorScheme.surface,
              elevation: 2,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.all(10),
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
                          size: 20,
                          color: iconColor,
                        ),
                        const SizedBox(width: 10),
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
                              if (body != null) ...[
                                const SizedBox(height: 2),
                                Text(
                                  body,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        if (!service.isUpdating) ...[
                          const SizedBox(width: 8),
                          IconButton(
                            tooltip: 'Cerrar',
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(Icons.close, size: 18),
                            onPressed: service.dismissAvailableUpdate,
                          ),
                        ],
                      ],
                    ),
                    if (showProgress) ...[
                      const SizedBox(height: 8),
                      const LinearProgressIndicator(minHeight: 3),
                    ],
                    if (!service.isUpdating) ...[
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          FilledButton.icon(
                            style: FilledButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                            ),
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

  Widget _buildCollapsedUpdateButton(
    BuildContext context,
    DesktopUpdateService service,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Positioned(
      top: 56,
      right: 72,
      child: Tooltip(
        message: 'Actualizacion lista',
        child: Material(
          color: colorScheme.surface,
          elevation: 1,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: service.revealAvailableUpdate,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 8,
              ),
              decoration: BoxDecoration(
                border: Border.all(color: colorScheme.outlineVariant),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.system_update_alt_rounded,
                    size: 18,
                    color: colorScheme.primary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Actualizar',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
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
