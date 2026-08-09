import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/website/widgets/website_color_picker.dart';

void main() {
  test('parses and serializes the editor ARGB compatibility format', () {
    final color = parseWebsiteEditorColor('#8808100D');

    expect((websiteEditorColorOpacity(color) * 100).round(), 53);
    expect(serializeWebsiteEditorColor(color), '#8808100D');
    expect(serializeWebsiteEditorColor(color, includeAlpha: false), '#08100D');
  });

  testWidgets(
    'shows a visual color and explicit opacity before exposing the code',
    (tester) async {
      var value = '#8808100D';

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(useMaterial3: true),
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => SizedBox(
                width: 320,
                child: WebsiteColorPickerField(
                  label: 'Color de relleno',
                  value: value,
                  transactionIdentity: const ('test', 'fill-color'),
                  onChanged: (next) => setState(() => value = next),
                ),
              ),
            ),
          ),
        ),
      );

      expect(find.text('Opacidad 53%'), findsOneWidget);
      expect(
        find.byKey(
          const ValueKey('website_color_opacity_Color de relleno'),
        ),
        findsOneWidget,
        reason: 'the default keeps the established inline opacity shortcut',
      );
      expect(find.text('Código avanzado'), findsNothing);

      await tester.tap(
        find.byKey(
          const ValueKey('website_color_picker_Color de relleno'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('PALETA DEL SITIO'), findsOneWidget);
      expect(find.text('Código avanzado'), findsOneWidget);
      expect(find.text('Aplicar'), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey('website_color_swatch_#F0642F')),
      );
      await tester.tap(
        find.byKey(const ValueKey('website_color_picker_apply')),
      );
      await tester.pumpAndSettle();

      expect(value, '#88F0642F');
      expect(find.text('Opacidad 53%'), findsOneWidget);
    },
  );

  testWidgets(
    'transactional slider keeps ticks local, commits once, and cancels A on B',
    (tester) async {
      var owner = 'A';
      final writesA = <double>[];
      final writesB = <double>[];
      final cancels = <String>[];
      late StateSetter rebuild;

      await tester.pumpWidget(
        MaterialApp(
          home: Material(
            child: StatefulBuilder(
              builder: (context, setState) {
                rebuild = setState;
                final renderedOwner = owner;
                return WebsiteTransactionalSlider(
                  key: const ValueKey('transaction-slider'),
                  value: 0.5,
                  min: 0,
                  max: 1,
                  transactionIdentity: renderedOwner,
                  onCancel: () => cancels.add(renderedOwner),
                  onCommit: renderedOwner == 'A' ? writesA.add : writesB.add,
                );
              },
            ),
          ),
        ),
      );

      var slider = tester.widget<Slider>(find.byType(Slider));
      slider.onChangeStart!(0.5);
      slider.onChanged!(0.6);
      slider.onChanged!(0.7);
      slider.onChanged!(0.8);
      expect(writesA, isEmpty);
      expect(writesB, isEmpty);

      rebuild(() => owner = 'B');
      await tester.pump();
      expect(cancels, <String>['A']);
      expect(writesA, isEmpty);
      expect(writesB, isEmpty);

      slider = tester.widget<Slider>(find.byType(Slider));
      slider.onChangeStart!(0.5);
      slider.onChanged!(0.55);
      slider.onChanged!(0.65);
      slider.onChanged!(0.75);
      expect(writesB, isEmpty);
      slider.onChangeEnd!(0.75);
      expect(writesA, isEmpty);
      expect(writesB, <double>[0.75]);

      slider = tester.widget<Slider>(find.byType(Slider));
      slider.onChangeStart!(0.5);
      slider.onChanged!(0.9);
      final listener = tester.widget<Listener>(
        find.descendant(
          of: find.byKey(const ValueKey('transaction-slider')),
          matching: find.byWidgetPredicate(
            (widget) => widget is Listener && widget.onPointerCancel != null,
          ),
        ),
      );
      listener.onPointerCancel!(const PointerCancelEvent());
      expect(writesB, <double>[0.75]);
      expect(cancels, <String>['A', 'B']);
    },
  );

  testWidgets(
    'inline opacity persists once on end and never on pointer cancel',
    (tester) async {
      var value = '#FF08100D';
      final writes = <String>[];
      late StateSetter rebuild;

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(useMaterial3: true),
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                rebuild = setState;
                return WebsiteColorPickerField(
                  label: 'Opacidad transaccional',
                  value: value,
                  transactionIdentity: const ('test', 'opacity'),
                  onChanged: (next) {
                    writes.add(next);
                    rebuild(() => value = next);
                  },
                );
              },
            ),
          ),
        ),
      );

      final owner = find.byKey(
        const ValueKey('website_color_opacity_Opacidad transaccional'),
      );
      var slider = tester.widget<Slider>(
        find.descendant(of: owner, matching: find.byType(Slider)),
      );
      slider.onChangeStart!(1);
      slider.onChanged!(0.9);
      slider.onChanged!(0.8);
      slider.onChanged!(0.7);
      expect(writes, isEmpty);
      slider.onChangeEnd!(0.7);
      expect(writes, hasLength(1));

      await tester.pump();
      slider = tester.widget<Slider>(
        find.descendant(of: owner, matching: find.byType(Slider)),
      );
      slider.onChangeStart!(0.7);
      slider.onChanged!(0.4);
      final listener = tester.widget<Listener>(
        find.descendant(
          of: owner,
          matching: find.byWidgetPredicate(
            (widget) => widget is Listener && widget.onPointerCancel != null,
          ),
        ),
      );
      listener.onPointerCancel!(const PointerCancelEvent());
      expect(writes, hasLength(1));
    },
  );
}
