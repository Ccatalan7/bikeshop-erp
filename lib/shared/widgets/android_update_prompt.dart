import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/android_update_service.dart';
import 'desktop_update_prompt.dart' show showDesktopReleaseNotesDialog;

class AndroidUpdatePrompt extends StatefulWidget {
  const AndroidUpdatePrompt({super.key});

  @override
  State<AndroidUpdatePrompt> createState() => _AndroidUpdatePromptState();
}

class _AndroidUpdatePromptState extends State<AndroidUpdatePrompt>
    with WidgetsBindingObserver {
  static const _pollInterval = Duration(minutes: 5);

  Timer? _pollTimer;
  bool _isForeground = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _isForeground = WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_isForeground) {
        _startPolling();
        unawaited(
          context.read<AndroidUpdateService>().checkForUpdate(force: true),
        );
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _isForeground = state == AppLifecycleState.resumed;
    if (!_isForeground) {
      _pollTimer?.cancel();
      _pollTimer = null;
      return;
    }

    _startPolling();
    if (mounted) {
      unawaited(
        context.read<AndroidUpdateService>().checkForUpdate(force: true),
      );
    }
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(_pollInterval, (_) {
      if (!mounted || !_isForeground) return;
      unawaited(
        context.read<AndroidUpdateService>().checkForUpdate(force: true),
      );
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pollTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AndroidUpdateService>(
      builder: (context, service, _) {
        final release = service.availableUpdate;
        final showCheckError = release == null &&
            service.errorMessage != null &&
            service.consecutiveCheckFailures > 0;
        if (!service.isSupported || (release == null && !showCheckError)) {
          return const SizedBox.shrink();
        }

        final theme = Theme.of(context);
        final colors = theme.colorScheme;

        if (release == null) {
          return _UpdatePromptPosition(
            child: Material(
              key: const ValueKey('android-update-check-error'),
              elevation: 3,
              color: colors.surface,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  border: Border.all(color: colors.error),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(Icons.sync_problem_rounded, color: colors.error),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'No pudimos comprobar si hay una actualización.',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      key: const ValueKey('android-update-retry-button'),
                      style: TextButton.styleFrom(
                        minimumSize: const Size(0, 48),
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                      ),
                      onPressed: service.isChecking
                          ? null
                          : () => unawaited(
                                service.checkForUpdate(force: true),
                              ),
                      child: const Text('Reintentar'),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        return _UpdatePromptPosition(
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
                                  release.releaseNotes?.summary ??
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
                  Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      if (release.releaseNotes != null)
                        TextButton(
                          key: const ValueKey(
                            'android-update-whats-new-button',
                          ),
                          style: TextButton.styleFrom(
                            minimumSize: const Size(0, 48),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                            ),
                          ),
                          onPressed: () => showDesktopReleaseNotesDialog(
                            context,
                            release.releaseNotes!,
                          ),
                          child: const Text('Novedades'),
                        ),
                      FilledButton(
                        key: const ValueKey(
                          'android-update-primary-button',
                        ),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 48),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                          ),
                        ),
                        onPressed: service.isDownloading
                            ? null
                            : () => _install(context),
                        child: Text(
                          service.isDownloading ? 'Descargando…' : 'Actualizar',
                        ),
                      ),
                    ],
                  ),
                ],
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

class _UpdatePromptPosition extends StatelessWidget {
  final Widget child;

  const _UpdatePromptPosition({required this.child});

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 12,
      right: 12,
      bottom: 12,
      child: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: child,
          ),
        ),
      ),
    );
  }
}
