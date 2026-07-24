import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/desktop_release_notes.dart';
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
          return const SizedBox.shrink();
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
                      Wrap(
                        alignment: WrapAlignment.end,
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          if (service.isUpdateReady &&
                              update.releaseNotes != null) ...[
                            TextButton(
                              key: const ValueKey(
                                'desktop-update-whats-new-button',
                              ),
                              style: TextButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 8,
                                ),
                              ),
                              onPressed: () => showDesktopReleaseNotesDialog(
                                context,
                                update.releaseNotes!,
                              ),
                              child: const Text('Novedades'),
                            ),
                          ],
                          FilledButton.icon(
                            key: const ValueKey(
                              'desktop-update-primary-button',
                            ),
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

Future<void> showDesktopReleaseNotesDialog(
  BuildContext context,
  DesktopReleaseNotes notes,
) {
  return showDialog<void>(
    context: context,
    builder: (_) => DesktopReleaseNotesDialog(notes: notes),
  );
}

class DesktopReleaseNotesDialog extends StatefulWidget {
  final DesktopReleaseNotes notes;

  const DesktopReleaseNotesDialog({
    super.key,
    required this.notes,
  });

  @override
  State<DesktopReleaseNotesDialog> createState() =>
      _DesktopReleaseNotesDialogState();
}

class _DesktopReleaseNotesDialogState extends State<DesktopReleaseNotesDialog> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final availableHeight = MediaQuery.sizeOf(context).height;

    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        key: const ValueKey('desktop-release-notes-dialog'),
        constraints: BoxConstraints(
          maxWidth: 520,
          maxHeight: availableHeight * 0.78,
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.notes.title,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                widget.notes.summary,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              Divider(height: 1, color: colorScheme.outlineVariant),
              const SizedBox(height: 12),
              Flexible(
                child: Scrollbar(
                  controller: _scrollController,
                  thumbVisibility: true,
                  child: SingleChildScrollView(
                    controller: _scrollController,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (var index = 0;
                            index < widget.notes.modules.length;
                            index++) ...[
                          if (index > 0) const SizedBox(height: 16),
                          _ReleaseNotesModuleSection(
                            module: widget.notes.modules[index],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cerrar'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReleaseNotesModuleSection extends StatelessWidget {
  final DesktopReleaseNotesModule module;

  const _ReleaseNotesModuleSection({
    required this.module,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      key: ValueKey('desktop-release-notes-module-${module.id}'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          module.label,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        for (final item in module.items)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '•',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    item,
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
