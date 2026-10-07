import 'package:flutter/material.dart';

import '../services/deferred_load_failure.dart';
import '../themes/vinabike_theme_roles.dart';
import '../utils/browser_url.dart';
import 'vb_button.dart';

/// What the ERP on the web shows where a part of it did not load
/// ([DeferredLoadFailure]): what happened, in the operator's words, and the
/// one thing that fixes it, a reload. In place of «Algo salió mal», which is
/// what a page left behind by a deploy showed until 2026-10-07.
///
/// It lands wherever the failure lands (a whole screen, the editor's panel,
/// one block), so it fits a narrow column, and it renders even under a
/// theme without the ERP's roles: an error surface cannot fail in turn.
class DeferredLoadNotice extends StatelessWidget {
  const DeferredLoadNotice({super.key, required this.failure})
      : compact = false;

  /// One line, for a part that repeats (each block of the editor's canvas):
  /// a page of blocks says it once per block without filling the screen.
  const DeferredLoadNotice.compact({super.key, required this.failure})
      : compact = true;

  final DeferredLoadFailure failure;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final roles = VinabikeThemeRoles.maybeOf(context);
    final tone = roles?.info;
    final icon = failure == DeferredLoadFailure.newBuild
        ? Icons.system_update_alt_rounded
        : Icons.cloud_off_rounded;
    const reload = 'Recargar';
    if (compact) {
      return Material(
        type: MaterialType.transparency,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Icon(icon, size: 18, color: tone?.accent ?? scheme.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  failure == DeferredLoadFailure.newBuild
                      ? 'Hay una versión nueva del ERP'
                      : 'Esta parte del ERP no se cargó',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurface,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              if (roles != null)
                const VbButton(
                  label: reload,
                  variant: VbButtonVariant.text,
                  onPressed: reloadBrowserPage,
                )
              else
                const TextButton(
                  onPressed: reloadBrowserPage,
                  child: Text(reload),
                ),
            ],
          ),
        ),
      );
    }
    final (title, body) = switch (failure) {
      DeferredLoadFailure.newBuild => (
          'Hay una versión nueva del ERP',
          'Se publicó mientras esta pestaña estaba abierta. Recarga la '
              'página para seguir en la nueva.',
        ),
      DeferredLoadFailure.unavailable => (
          'Esta parte del ERP no se cargó',
          'Puede que se haya publicado una versión nueva o que se cortara '
              'la conexión. Recarga la página para seguir.',
        ),
    };
    return Material(
      type: MaterialType.transparency,
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: tone?.container ?? scheme.primaryContainer,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    icon,
                    size: 22,
                    color: tone?.accent ?? scheme.primary,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurface,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  body,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Si tienes algo sin guardar en otra pestaña del ERP, '
                  'guárdalo antes.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: roles?.faintForeground ?? scheme.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 18),
                if (roles != null)
                  const VbButton(
                    label: reload,
                    icon: Icons.refresh_rounded,
                    onPressed: reloadBrowserPage,
                  )
                else
                  FilledButton.icon(
                    onPressed: reloadBrowserPage,
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: const Text(reload),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
