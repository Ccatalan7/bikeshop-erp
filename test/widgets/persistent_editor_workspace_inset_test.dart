import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:vinabike_erp/modules/website/providers/website_edit_mode_provider.dart';
import 'package:vinabike_erp/public_store/widgets/persistent_editor_shell.dart';
import 'package:vinabike_erp/shared/widgets/workspace_shell_scope.dart';

void main() {
  testWidgets(
    'ERP website editor starts below the global workspace bar',
    (tester) async {
      const contentKey = ValueKey('website-editor-test-content');

      await tester.pumpWidget(
        ChangeNotifierProvider(
          create: (_) => WebsiteEditModeProvider(),
          child: const MaterialApp(
            home: Scaffold(
              body: WorkspaceShellScope(
                topInset: WorkspaceShellScope.workspaceBarHeight,
                child: PersistentEditorShell(
                  child: ColoredBox(
                    key: contentKey,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      expect(
        tester.getTopLeft(find.byKey(contentKey)).dy,
        WorkspaceShellScope.workspaceBarHeight,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'standalone website editor does not invent workspace spacing',
    (tester) async {
      const contentKey = ValueKey('standalone-editor-test-content');

      await tester.pumpWidget(
        ChangeNotifierProvider(
          create: (_) => WebsiteEditModeProvider(),
          child: const MaterialApp(
            home: Scaffold(
              body: PersistentEditorShell(
                child: ColoredBox(
                  key: contentKey,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ),
      );

      expect(tester.getTopLeft(find.byKey(contentKey)).dy, 0);
      expect(tester.takeException(), isNull);
    },
  );
}
