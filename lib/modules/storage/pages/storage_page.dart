import 'package:flutter/material.dart';

import '../../../shared/utils/responsive_viewport.dart';
import '../../../shared/widgets/main_layout.dart';
import '../widgets/app_files_panel.dart';

class StoragePage extends StatelessWidget {
  const StoragePage({
    super.key,
    this.initialFileId,
    this.initialOpenRequestId,
  });

  final String? initialFileId;
  final String? initialOpenRequestId;

  @override
  Widget build(BuildContext context) {
    return MainLayout(
      child: StorageResponsiveSurface(
        initialFileId: initialFileId,
        initialOpenRequestId: initialOpenRequestId,
      ),
    );
  }
}

/// Responsive route content shared by the real Storage route and widget tests.
///
/// Phone and tablet use the compact library composition while desktop keeps
/// the operational two-pane folder and file workspace.
class StorageResponsiveSurface extends StatelessWidget {
  const StorageResponsiveSurface({
    super.key,
    this.initialFileId,
    this.initialOpenRequestId,
    this.filesLoader,
  });

  final String? initialFileId;
  final String? initialOpenRequestId;
  final AppFilesLoader? filesLoader;

  @override
  Widget build(BuildContext context) {
    final compact = ResponsiveViewport.usesCompactShell(context);
    return AppFilesPanel(
      key:
          ValueKey(compact ? 'storage-panel-compact' : 'storage-panel-desktop'),
      compact: compact,
      initialFileId: initialFileId,
      initialOpenRequestId: initialOpenRequestId,
      filesLoader: filesLoader,
    );
  }
}
