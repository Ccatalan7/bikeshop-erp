import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/bikeshop/pages/mechanic_job_form_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpSurface(
    WidgetTester tester, {
    required Size size,
    required Widget child,
    double textScale = 1.3,
    double keyboardInset = 0,
  }) async {
    tester.view
      ..physicalSize = size
      ..devicePixelRatio = 1
      ..viewInsets = FakeViewPadding(bottom: keyboardInset);
    addTearDown(() {
      tester.view
        ..resetPhysicalSize()
        ..resetDevicePixelRatio()
        ..resetViewInsets();
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: true),
        home: MediaQuery(
          data: MediaQueryData(
            size: size,
            textScaler: TextScaler.linear(textScale),
            viewInsets: EdgeInsets.only(bottom: keyboardInset),
          ),
          child: Scaffold(
            body: SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(8),
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  test('responsive policy keeps phone/tablet compact and desktop at 900', () {
    const cases = <(double, bool)>[
      (384, true),
      (599, true),
      (600, true),
      (899, true),
      (900, false),
      (1440, false),
    ];

    for (final (width, expectedCompact) in cases) {
      expect(
        MechanicJobResponsivePolicy.usesCompactComposition(width),
        expectedCompact,
        reason: 'Unexpected workbench class at $width px.',
      );
    }
  });

  for (final width in <double>[384, 599, 600, 899]) {
    testWidgets(
      'compact workbench keeps complete labels and 48px targets at $width',
      (tester) async {
        var selectedIndex = 0;
        await pumpSurface(
          tester,
          size: Size(width, 824),
          child: StatefulBuilder(
            builder: (context, setState) {
              return MechanicJobCompactWorkbenchNavigation(
                selectedIndex: selectedIndex,
                showDiagnosis: true,
                productsLabel: 'Ítems',
                onSelected: (value) {
                  setState(() => selectedIndex = value);
                },
              );
            },
          ),
        );

        expect(find.text('General'), findsOneWidget);
        expect(find.text('Diagnóstico'), findsOneWidget);
        expect(find.text('Ítems'), findsOneWidget);
        expect(find.textContaining('Productos y Servicios'), findsNothing);

        for (final index in <int>[0, 1, 2]) {
          final target = find.byKey(
            ValueKey('mechanic-job-workbench-tab-$index'),
          );
          expect(target, findsOneWidget);
          expect(tester.getSize(target).height, greaterThanOrEqualTo(48));
        }

        await tester.tap(
          find.byKey(const ValueKey('mechanic-job-workbench-tab-1')),
        );
        await tester.pump();
        expect(selectedIndex, 1);
        expect(find.bySemanticsLabel('Diagnóstico'), findsOneWidget);

        await tester.tap(
          find.byKey(const ValueKey('mechanic-job-workbench-tab-2')),
        );
        await tester.pump();
        expect(selectedIndex, 2);
        expect(
          find.bySemanticsLabel('Productos y servicios'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'compact diagnosis choice menu exposes one system and semantic options',
    (tester) async {
      var selectedId = 'cockpit';
      Widget buildMenu() {
        return StatefulBuilder(
          builder: (context, setState) {
            return MechanicJobCompactChoiceMenu(
              controlLabel: 'Sistema',
              selectedId: selectedId,
              choices: const [
                MechanicJobCompactChoice(
                  id: 'cockpit',
                  label: 'Cockpit / dirección',
                  icon: Icons.tune,
                  statusLabel: 'Pendiente',
                  statusColor: Colors.blueGrey,
                ),
                MechanicJobCompactChoice(
                  id: 'brakes',
                  label: 'Frenos',
                  icon: Icons.radio_button_checked,
                  statusLabel: 'Atención',
                  statusColor: Colors.orange,
                ),
                MechanicJobCompactChoice(
                  id: 'drivetrain',
                  label: 'Transmisión',
                  icon: Icons.settings,
                  statusLabel: 'Correcto',
                  statusColor: Colors.green,
                ),
              ],
              onSelected: (value) {
                setState(() => selectedId = value);
              },
            );
          },
        );
      }

      await pumpSurface(
        tester,
        size: const Size(384, 824),
        child: buildMenu(),
      );

      final control = find.byKey(
        const ValueKey('mechanic-job-compact-sistema-menu'),
      );
      expect(control, findsOneWidget);
      expect(tester.getSize(control).height, greaterThanOrEqualTo(48));
      expect(
        find.bySemanticsLabel(
          'Sistema. Cockpit / dirección. Estado Pendiente. Cambiar',
        ),
        findsOneWidget,
      );

      await tester.tap(control);
      await tester.pumpAndSettle();
      final brakes = find.byKey(
        const ValueKey('mechanic-job-choice-brakes'),
      );
      expect(brakes, findsOneWidget);
      expect(tester.getSize(brakes).height, greaterThanOrEqualTo(48));

      await tester.tap(brakes);
      await tester.pumpAndSettle();
      expect(selectedId, 'brakes');
      expect(find.text('Frenos'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'discard confirmation remains usable with text scale and keyboard inset',
    (tester) async {
      bool? result;
      await pumpSurface(
        tester,
        size: const Size(384, 824),
        keyboardInset: 300,
        child: Builder(
          builder: (context) {
            return FilledButton(
              onPressed: () async {
                result = await showDialog<bool>(
                  context: context,
                  builder: (_) => const MechanicJobDiscardDialog(),
                );
              },
              child: const Text('Abrir confirmación'),
            );
          },
        ),
      );

      await tester.tap(find.text('Abrir confirmación'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('mechanic-job-inline-discard-dialog')),
        findsOneWidget,
      );
      final keepEditing = find.byKey(
        const ValueKey('mechanic-job-inline-discard-cancel'),
      );
      final discard = find.byKey(
        const ValueKey('mechanic-job-inline-discard-confirm'),
      );
      expect(tester.getSize(keepEditing).height, greaterThanOrEqualTo(48));
      expect(tester.getSize(discard).height, greaterThanOrEqualTo(48));

      await tester.tap(keepEditing);
      await tester.pumpAndSettle();
      expect(result, isFalse);

      await tester.tap(find.text('Abrir confirmación'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('mechanic-job-inline-discard-confirm')),
      );
      await tester.pumpAndSettle();
      expect(result, isTrue);
      expect(tester.takeException(), isNull);
    },
  );
}
