import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/android_update_service.dart';

class AndroidUpdatePrompt extends StatefulWidget {
  const AndroidUpdatePrompt({super.key});

  @override
  State<AndroidUpdatePrompt> createState() => _AndroidUpdatePromptState();
}

class _AndroidUpdatePromptState extends State<AndroidUpdatePrompt> {
  static const _pollInterval = Duration(minutes: 30);

  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<AndroidUpdateService>().checkForUpdate();
    });
    _pollTimer = Timer.periodic(_pollInterval, (_) {
      if (!mounted) return;
      context.read<AndroidUpdateService>().checkForUpdate(force: true);
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AndroidUpdateService>(
      builder: (context, service, _) {
        final release = service.availableUpdate;
        if (!service.isSupported || release == null) {
          return const SizedBox.shrink();
        }

        final theme = Theme.of(context);
        final colors = theme.colorScheme;

        return Positioned(
          left: 12,
          right: 12,
          bottom: 12,
          child: SafeArea(
            top: false,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Material(
                  elevation: 3,
                  color: colors.surface,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      border: Border.all(color: colors.outlineVariant),
                      borderRadius: BorderRadius.circular(12),
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
                              color: colors.primary,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Actualización ${release.versionName}',
                                    style: theme.textTheme.titleSmall?.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    service.errorMessage ??
                                        service.statusMessage ??
                                        release.releaseNotes ??
                                        'Hay una nueva versión de Vinabike ERP.',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: service.errorMessage == null
                                          ? colors.onSurfaceVariant
                                          : colors.error,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (!service.isDownloading)
                              IconButton(
                                tooltip: 'Ahora no',
                                visualDensity: VisualDensity.compact,
                                onPressed: service.dismissAvailableUpdate,
                                icon: const Icon(Icons.close, size: 19),
                              ),
                          ],
                        ),
                        if (service.isDownloading) ...[
                          const SizedBox(height: 12),
                          LinearProgressIndicator(
                            value: service.downloadProgress,
                            minHeight: 4,
                          ),
                        ],
                        const SizedBox(height: 12),
                        Align(
                          alignment: Alignment.centerRight,
                          child: FilledButton(
                            key: const ValueKey(
                              'android-update-primary-button',
                            ),
                            onPressed: service.isDownloading
                                ? null
                                : () => _install(context),
                            child: Text(
                              service.isDownloading
                                  ? 'Descargando…'
                                  : 'Actualizar',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _install(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await context.read<AndroidUpdateService>().installAvailableUpdate();
    } catch (_) {
      if (!context.mounted) return;
      messenger.showSnackBar(
        const SnackBar(
          content: Text('No se pudo descargar la actualización.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}
