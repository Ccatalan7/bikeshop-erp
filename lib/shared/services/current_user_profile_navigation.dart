import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../utils/responsive_viewport.dart';
import 'workspace_manager.dart';

/// Canonical entry point for the authenticated user's ERP profile.
///
/// Compact hosts keep the originating route in their navigation stack.
/// Desktop hosts reuse the dedicated profile workspace when it already exists.
abstract final class CurrentUserProfileNavigation {
  static const String route = '/profile';

  static void open(BuildContext context) {
    if (ResponsiveViewport.usesCompactShell(context)) {
      final router = GoRouter.maybeOf(context);
      if (router != null && GoRouterState.of(context).uri.path == route) {
        return;
      }
      context.push(route);
      return;
    }

    try {
      context.read<WorkspaceManager>().openRouteInWorkspace(route);
    } on ProviderNotFoundException {
      // Standalone/debug hosts may not mount the desktop workspace owner.
      // Push keeps the caller's exact return path in that bounded fallback.
      context.push(route);
    }
  }
}
