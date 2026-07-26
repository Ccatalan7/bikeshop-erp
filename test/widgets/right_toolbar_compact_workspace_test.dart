import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:vinabike_erp/shared/services/right_toolbar_service.dart';
import 'package:vinabike_erp/shared/widgets/calculator_panel.dart';
import 'package:vinabike_erp/shared/widgets/right_toolbar.dart';
import 'package:vinabike_erp/shared/widgets/toolbar_tool_presentation.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'http://127.0.0.1:54321',
      anonKey: 'test-anon-key',
    );
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('shared presentation catalog covers every toolbar tool', () {
    expect(
      toolbarToolPresentationCatalog.keys.toSet(),
      ToolbarTool.values.toSet(),
    );

    final newJob = ToolbarTool.newJob.toolbarPresentation;
    expect(newJob.opensPanel, isFalse);
    expect(newJob.route, '/taller/pegas/nueva');

    for (final tool in ToolbarTool.values.where(
      (tool) => tool != ToolbarTool.newJob,
    )) {
      expect(
        tool.toolbarPresentation.opensPanel,
        isTrue,
        reason: '${tool.name} must keep using its canonical panel.',
      );
    }
  });

  testWidgets(
    'compact toolbar is zero-sized while inactive and closes through Back',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(384, 824));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final service = RightToolbarService();
      await tester.pumpWidget(
        ChangeNotifierProvider<RightToolbarService>.value(
          value: service,
          child: const MaterialApp(
            home: Scaffold(
              body: RightToolbar.compactWorkspace(),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(tester.getSize(find.byType(RightToolbar)), Size.zero);
      expect(find.byKey(const ValueKey('right-toolbar-compact-back')),
          findsNothing);

      service.openTool(ToolbarTool.calculator);
      await tester.pump();

      expect(find.text('Calculadora'), findsOneWidget);
      expect(find.byType(CalculatorPanel), findsOneWidget);

      final back = find.byKey(const ValueKey('right-toolbar-compact-back'));
      expect(back, findsOneWidget);
      final backSize = tester.getSize(back);
      expect(backSize.width, greaterThanOrEqualTo(48));
      expect(backSize.height, greaterThanOrEqualTo(48));

      await tester.tap(back);
      await tester.pump();

      expect(service.activeTool, isNull);
      expect(tester.getSize(find.byType(RightToolbar)), Size.zero);
      expect(find.byType(CalculatorPanel), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('system Back closes the compact tool before the host route',
      (tester) async {
    final service = RightToolbarService()..openTool(ToolbarTool.calculator);

    await tester.pumpWidget(
      ChangeNotifierProvider<RightToolbarService>.value(
        value: service,
        child: const MaterialApp(
          home: Scaffold(
            body: RightToolbar.compactWorkspace(),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(CalculatorPanel), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pump();

    expect(service.activeTool, isNull);
    expect(find.byType(CalculatorPanel), findsNothing);
    expect(find.byType(Scaffold), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
