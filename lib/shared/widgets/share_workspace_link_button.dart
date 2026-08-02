import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../services/route_share_service.dart';
import '../services/workspace_manager.dart';
import 'vb_shell_icon_button.dart';
import 'workspace_shell_scope.dart';

class ShareWorkspaceLinkButton extends StatelessWidget {
  const ShareWorkspaceLinkButton({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final chrome = WorkspaceChromeStyle.maybeOf(context);

    // Dentro del shell manda `A-02` sobre shell, y su dueño es
    // `VbShellIconButton`: 32 / r7 / glifo 16 para TODAS las acciones del
    // grupo. Antes esta traía 28 y glifo 18, y mezclada con las demás dejaba
    // el chrome con tres alturas distintas.
    if (chrome != null) {
      return VbShellIconButton(
        buttonKey: const ValueKey<String>('workspace-share-link'),
        icon: Icons.ios_share_outlined,
        tooltip: 'Copiar enlace de página',
        onPressed: () => _copyCurrentLink(context),
      );
    }
    // Fuera del shell este botón tiene otros hosts: se deja como estaba.
    return IconButton(
      tooltip: 'Copiar enlace de página',
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      icon: Icon(
        Icons.ios_share_outlined,
        size: 18,
        color: theme.colorScheme.onSurface,
      ),
      onPressed: () => _copyCurrentLink(context),
    );
  }

  Future<void> _copyCurrentLink(BuildContext context) async {
    final link = _buildCurrentLink(context);
    if (link == null) {
      _showSnack(context, 'Esta página todavía no se puede compartir.');
      return;
    }

    await Clipboard.setData(ClipboardData(text: link.shareText));
    if (context.mounted) {
      _showSnack(context, 'Enlace copiado para compartir.');
    }
  }

  SharedRouteLink? _buildCurrentLink(BuildContext context) {
    final workspace = context.read<WorkspaceManager>().activeWorkspace;
    if (workspace == null) return null;

    return RouteShareService.buildForRoute(
      route: workspace.shareRoute,
      title: workspace.title,
    );
  }

  void _showSnack(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}
