import 'package:flutter/material.dart';

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
      child: AppFilesPanel(
        compact: false,
        initialFileId: initialFileId,
        initialOpenRequestId: initialOpenRequestId,
      ),
    );
  }
}
