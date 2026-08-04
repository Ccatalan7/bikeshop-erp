import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/shared/services/right_toolbar_service.dart';
import 'package:vinabike_erp/shared/themes/app_theme.dart';
import 'package:vinabike_erp/shared/themes/appearance_preset.dart';
import 'package:vinabike_erp/shared/widgets/right_toolbar.dart';
import 'package:vinabike_erp/shared/widgets/toolbar_tool_presentation.dart';

/// Exercises the production button both rails render.
///
/// The full `RightToolbar` pulls in Supabase-backed providers, but the defect
/// was never in the rail's plumbing: it was that a tool button carried its
/// name only as a `Tooltip`, which screen readers announce as a hint. The
/// assistant — reachable from nowhere else in the app — had no accessible
/// name, and the first fix reached only the collapsed rail while the mini-rail
/// an operator uses with a panel open kept the defect. Both loops now build
/// this widget, so the regression is on production code.
void main() {
  Widget host(Widget child, {Brightness brightness = Brightness.light}) {
    return MaterialApp(
      theme: AppTheme.resolve(
        preset: AppearancePresets.all.first,
        brightness: brightness,
      ),
      home: Scaffold(body: child),
    );
  }

  Widget button(
    ToolbarTool tool, {
    required bool selected,
    VoidCallback? onTap,
  }) {
    return RightToolbarToolButton(
      tool: tool,
      selected: selected,
      waitDuration: const Duration(milliseconds: 400),
      onTap: onTap ?? () {},
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(8)),
      icon: const Icon(Icons.auto_awesome),
    );
  }

  testWidgets('a rail tool exposes its name, not just a tooltip hint',
      (tester) async {
    await tester.pumpWidget(
      host(button(ToolbarTool.aiAssistant, selected: false)),
    );

    expect(find.bySemanticsLabel('Asistente IA, herramienta'), findsOneWidget);
  });

  testWidgets('the tooltip does not duplicate the accessible name',
      (tester) async {
    await tester.pumpWidget(host(button(ToolbarTool.tasks, selected: false)));

    final node =
        tester.getSemantics(find.bySemanticsLabel('Tareas, herramienta'));
    expect(
      node.tooltip,
      isEmpty,
      reason: 'tooltip and label would be announced twice',
    );
  });

  testWidgets('the selected state is announced, not only painted',
      (tester) async {
    await tester.pumpWidget(
      host(button(ToolbarTool.aiAssistant, selected: true)),
    );

    final node =
        tester.getSemantics(find.bySemanticsLabel('Asistente IA, herramienta'));
    expect(node.hasFlag(SemanticsFlag.isSelected), isTrue);
    expect(node.hasFlag(SemanticsFlag.isButton), isTrue);
  });

  testWidgets('an unselected tool does not claim to be selected',
      (tester) async {
    await tester.pumpWidget(
      host(button(ToolbarTool.aiAssistant, selected: false)),
    );

    final node =
        tester.getSemantics(find.bySemanticsLabel('Asistente IA, herramienta'));
    expect(node.hasFlag(SemanticsFlag.isSelected), isFalse);
  });

  testWidgets('the button is tappable through its semantics', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      host(button(ToolbarTool.aiAssistant,
          selected: false, onTap: () => taps++)),
    );

    await tester.tap(find.bySemanticsLabel('Asistente IA, herramienta'));
    await tester.pump();

    expect(taps, 1);
  });

  testWidgets('every tool the rail can render has a name', (tester) async {
    for (final tool in ToolbarTool.values) {
      await tester.pumpWidget(host(button(tool, selected: false)));
      expect(
        find.bySemanticsLabel('${tool.toolbarPresentation.title}, herramienta'),
        findsOneWidget,
        reason: '$tool has no accessible name',
      );
    }
  });

  testWidgets('the name survives dark mode', (tester) async {
    await tester.pumpWidget(
      host(
        button(ToolbarTool.aiAssistant, selected: false),
        brightness: Brightness.dark,
      ),
    );

    expect(find.bySemanticsLabel('Asistente IA, herramienta'), findsOneWidget);
  });
}
