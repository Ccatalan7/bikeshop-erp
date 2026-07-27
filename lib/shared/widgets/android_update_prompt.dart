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
          child: Semantics(
            container: true,
            label: 'Actualización de Android disponible',
            child: Material(
              key: const ValueKey('android-update-ready-prompt'),
              elevation: 3,
              color: colors.surface,
              shape: RoundedRectangleBorder(
                side: BorderSide(color: colors.outlineVariant),
                borderRadius: BorderRadius.circular(12),
              ),
              clipBehavior: Clip.antiAlias,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 8,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final textScale =
                            MediaQuery.textScalerOf(context).scale(16) / 16;
                        final stackActions = textScale > 1.3;
                        final title = release.releaseNotes == null
                            ? _UpdateTitle(
                                versionName: release.versionName,
                                detail: service.errorMessage ??
                                    service.statusMessage,
                                detailColor: service.errorMessage == null
                                    ? colors.onSurfaceVariant
                                    : colors.error,
                              )
                            : TextButton(
                                key: const ValueKey(
                                  'android-update-whats-new-button',
                                ),
                                style: TextButton.styleFrom(
                                  minimumSize: const Size.fromHeight(48),
                                  padding: EdgeInsets.zero,
                                  alignment: Alignment.centerLeft,
                                ),
                                onPressed: () => showDesktopReleaseNotesDialog(
                                  context,
                                  release.releaseNotes!,
                                ),
                                child: _UpdateTitle(
                                  versionName: release.versionName,
                                  detail: service.errorMessage ??
                                      service.statusMessage,
                                  detailColor: service.errorMessage == null
                                      ? colors.onSurfaceVariant
                                      : colors.error,
                                  showWhatsNew: true,
                                ),
                              );
                        final installButton = FilledButton(
                          key: const ValueKey(
                            'android-update-primary-button',
                          ),
                          style: FilledButton.styleFrom(
                            minimumSize: const Size(0, 48),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                            ),
                          ),
                          onPressed: service.isDownloading
                              ? null
                              : () => _install(context),
                          child: Text(
                            service.isDownloading
                                ? 'Descargando…'
                                : service.errorMessage == null
                                    ? 'Instalar'
                                    : 'Reintentar',
                          ),
                        );
                        final dismissButton = service.isDownloading
                            ? null
                            : IconButton(
                                key: const ValueKey(
                                  'android-update-dismiss-button',
                                ),
                                tooltip: 'Ahora no',
                                constraints: const BoxConstraints.tightFor(
                                  width: 48,
                                  height: 48,
                                ),
                                onPressed: service.dismissAvailableUpdate,
                                icon: const Icon(Icons.close, size: 19),
                              );

                        if (stackActions) {
                          return Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
                                children: [
                                  Expanded(child: title),
                                  if (dismissButton != null) dismissButton,
                                ],
                              ),
                              const SizedBox(height: 4),
                              Align(
                                alignment: Alignment.centerRight,
                                child: installButton,
                              ),
                            ],
                          );
                        }

                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(child: title),
                            const SizedBox(width: 8),
                            installButton,
                            if (dismissButton != null) dismissButton,
                          ],
                        );
                      },
                    ),
                    if (service.isDownloading) ...[
                      const SizedBox(height: 8),
                      LinearProgressIndicator(
                        value: service.downloadProgress,
                        minHeight: 4,
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

  Future<void> _install(BuildContext context) async {
    try {
      await context.read<AndroidUpdateService>().installAvailableUpdate();
    } catch (_) {
      // The service keeps the actionable failure in the same update prompt.
      // Avoid placing a second bottom SnackBar over that prompt.
    }
  }
}

class _UpdateTitle extends StatelessWidget {
  final String versionName;
  final String? detail;
  final Color detailColor;
  final bool showWhatsNew;

  const _UpdateTitle({
    required this.versionName,
    required this.detail,
    required this.detailColor,
    this.showWhatsNew = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Versión $versionName',
              style: theme.textTheme.titleSmall?.copyWith(
                color: colors.onSurface,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (detail != null) ...[
              const SizedBox(height: 2),
              Semantics(
                liveRegion: true,
                child: Text(
                  detail!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: detailColor,
                  ),
                ),
              ),
            ],
            if (showWhatsNew)
              Text(
                'Novedades',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: colors.primary,
                ),
              ),
          ],
        ),
      ),
    );
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
