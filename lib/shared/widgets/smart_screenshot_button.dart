import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/right_toolbar_service.dart';
import '../services/smart_screenshot_service.dart';
import '../services/workspace_manager.dart';
import 'vb_shell_icon_button.dart';
import 'workspace_shell_scope.dart';

class SmartScreenshotButton extends StatelessWidget {
  const SmartScreenshotButton({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final chrome = WorkspaceChromeStyle.maybeOf(context);

    // `A-02` sobre shell, mismo dueño que el resto del grupo.
    if (chrome != null) {
      return VbShellIconButton(
        buttonKey: const ValueKey<String>('workspace-smart-screenshot'),
        icon: Icons.screenshot_monitor_outlined,
        tooltip: 'Capturas',
        onPressed: () => _showScreenshotDialog(context),
      );
    }
    return IconButton(
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      tooltip: 'Capturas',
      onPressed: () => _showScreenshotDialog(context),
      icon: Icon(
        Icons.screenshot_monitor_outlined,
        size: 20,
        color: theme.colorScheme.onSurface.withValues(alpha: 0.76),
      ),
    );
  }

  Future<void> _showScreenshotDialog(BuildContext context) async {
    final service = context.read<SmartScreenshotService>();
    final workspace = context.read<WorkspaceManager>().activeWorkspace;
    final canCaptureBrowser = service.hasBrowserContext(workspace);

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => _SmartScreenshotDialog(
        canCaptureBrowser: canCaptureBrowser,
        onSelected: (mode) {
          Navigator.of(dialogContext).pop();
          WidgetsBinding.instance.addPostFrameCallback((_) {
            Future<void>.delayed(const Duration(milliseconds: 180), () {
              if (!context.mounted) return;
              unawaited(_captureScreenshot(context, mode));
            });
          });
        },
      ),
    );
  }

  Future<void> _captureScreenshot(
    BuildContext context,
    SmartScreenshotMode mode,
  ) async {
    final service = context.read<SmartScreenshotService>();
    final workspace = context.read<WorkspaceManager>().activeWorkspace;
    final toolbarService = context.read<RightToolbarService>();
    final messenger = ScaffoldMessenger.of(context);
    final errorColor = Theme.of(context).colorScheme.error;

    try {
      final String fileName;
      switch (mode) {
        case SmartScreenshotMode.visibleApp:
          final file = await service.captureVisibleApp(workspace: workspace);
          fileName = file.fileName;
          break;
        case SmartScreenshotMode.selectedArea:
          final file = await service.captureSelectedArea(
            context: context,
            workspace: workspace,
          );
          fileName = file.fileName;
          break;
        case SmartScreenshotMode.browserPage:
          final file = await service.captureBrowserPage(workspace: workspace);
          fileName = file.fileName;
          break;
      }

      if (!context.mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('Captura guardada: $fileName'),
          action: SnackBarAction(
            label: 'Ver',
            onPressed: () => toolbarService.openTool(ToolbarTool.storage),
          ),
        ),
      );
    } on SmartScreenshotCancelledException {
      // User cancelled the area selection.
    } catch (error) {
      if (!context.mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('No se pudo guardar la captura: $error'),
          backgroundColor: errorColor,
        ),
      );
    }
  }
}

class _SmartScreenshotDialog extends StatelessWidget {
  const _SmartScreenshotDialog({
    required this.canCaptureBrowser,
    required this.onSelected,
  });

  final bool canCaptureBrowser;
  final ValueChanged<SmartScreenshotMode> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: colorScheme.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.screenshot_monitor_outlined,
                      size: 19,
                      color: colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Captura inteligente',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Cerrar',
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.close, size: 18),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _ScreenshotModeTile(
                icon: Icons.desktop_windows_outlined,
                title: 'Pantalla visible',
                subtitle: 'Guarda la vista actual del ERP.',
                onTap: () => onSelected(SmartScreenshotMode.visibleApp),
              ),
              _ScreenshotModeTile(
                icon: Icons.crop_free_outlined,
                title: 'Area seleccionada',
                subtitle: 'Arrastra una zona dentro de la app.',
                onTap: () => onSelected(SmartScreenshotMode.selectedArea),
              ),
              _ScreenshotModeTile(
                icon: Icons.public_outlined,
                title: 'Pagina del navegador',
                subtitle: canCaptureBrowser
                    ? 'Captura el portal web activo.'
                    : 'Disponible en espacios de navegador.',
                enabled: canCaptureBrowser,
                onTap: () => onSelected(SmartScreenshotMode.browserPage),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScreenshotModeTile extends StatelessWidget {
  const _ScreenshotModeTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.enabled = true,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final foreground = enabled
        ? colorScheme.onSurface
        : colorScheme.onSurface.withValues(alpha: 0.42);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: enabled
            ? colorScheme.surfaceContainerHighest.withValues(alpha: 0.28)
            : colorScheme.surfaceContainerHighest.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            child: Row(
              children: [
                Icon(icon, size: 20, color: foreground),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: foreground,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant.withValues(
                            alpha: enabled ? 1 : 0.56,
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
      ),
    );
  }
}
