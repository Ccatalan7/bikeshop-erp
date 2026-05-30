import 'package:flutter/material.dart';

import '../../../shared/widgets/main_layout.dart';
import '../widgets/app_files_panel.dart';

class StoragePage extends StatelessWidget {
  const StoragePage({super.key});

  @override
  Widget build(BuildContext context) {
    return const MainLayout(
      child: AppFilesPanel(compact: false),
    );
  }
}
