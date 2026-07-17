import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../services/route_share_service.dart';
import '../services/workspace_manager.dart';

class ShareWorkspaceLinkButton extends StatelessWidget {
  const ShareWorkspaceLinkButton({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return IconButton(
      tooltip: 'Copiar enlace de página',
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
