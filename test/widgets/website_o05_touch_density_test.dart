import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:vinabike_erp/modules/website/models/website_responsive_authoring.dart';
import 'package:vinabike_erp/modules/website/providers/website_edit_mode_provider.dart';
import 'package:vinabike_erp/modules/website/widgets/website_block_edit_section.dart';
import 'package:vinabike_erp/modules/website/widgets/website_editor_chrome_geometry.dart';
import 'package:vinabike_erp/modules/website/widgets/website_editor_panel.dart';
import 'package:vinabike_erp/shared/themes/app_theme.dart';
import 'package:vinabike_erp/shared/themes/appearance_preset.dart';
import 'package:vinabike_erp/shared/widgets/vb_segmented.dart';

/// `F-06` applied to the real O-05 inspector body.
///
/// The editor host owns density. Phone and tablet require a 48 px hit target;
/// a 420 px inspector pane inside a 1440 px desktop remains pointer-dense.
void main() {
  const heightPresetKeys = <Key>[
    ValueKey<String>('website-height-preset-auto'),
    ValueKey<String>('website-height-preset-small'),
    ValueKey<String>('website-height-preset-medium'),
    ValueKey<String>('website-height-preset-large'),
    ValueKey<String>('website-height-preset-extraLarge'),
  ];
  const spacingPresetKeys = <Key>[
    ValueKey<String>('website-spacing-preset-0'),
    ValueKey<String>('website-spacing-preset-S'),
    ValueKey<String>('website-spacing-preset-M'),
    ValueKey<String>('website-spacing-preset-L'),
    ValueKey<String>('website-spacing-preset-XL'),
  ];
  const customToggleKey = ValueKey<String>('website-height-custom-toggle');
  const customInputKey = ValueKey<String>('website-height-custom-input');
  const applyKey = ValueKey<String>('website-height-apply');
  const resetKey = ValueKey<String>('website-height-reset');
  const quickActionKeys = <Key>[
    ValueKey<String>('website-block-quick-visibility'),
    ValueKey<String>('website-block-quick-duplicate'),
    ValueKey<String>('website-block-quick-delete'),
  ];

  void useViewport(
    WidgetTester tester, {
    required double width,
    double height = 1600,
  }) {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, height);
    addTearDown(tester.view.reset);
  }

  WebsiteEditModeProvider newProvider() {
    final provider = WebsiteEditModeProvider()
      ..enterEditMode(
        const <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'hero-1',
            'block_type': 'hero',
            'block_data': <String, dynamic>{
              'title': 'Portada',
              'blockHeight': 450,
              'spacingAfter': 16,
            },
            'is_visible': true,
            'sort_order': 0,
          },
        ],
        const <String, dynamic>{},
      )
      ..selectBlock('hero-1');
    addTearDown(provider.dispose);
    return provider;
  }

  Map<String, dynamic> dataOf(WebsiteEditModeProvider provider) =>
      Map<String, dynamic>.from(
        provider.blocks.single['block_data'] as Map,
      );

  Widget host({
    required WebsiteEditModeProvider provider,
    required double editorWidth,
    bool wholePanel = false,
  }) {
    return MaterialApp(
      theme: AppTheme.resolve(
        preset: AppearancePresets.pacific,
        brightness: Brightness.dark,
      ),
      home: ChangeNotifierProvider<WebsiteEditModeProvider>.value(
        value: provider,
        child: WebsiteEditorChromeScope(
          editorWidth: editorWidth,
          canvasWidth: WebsiteEditorChromeGeometry.canvasWidthFor(editorWidth),
          child: Scaffold(
            body: WebsiteEditorAuthoringViewportScope(
              requestedViewport: provider.previewViewport,
              effectiveViewport: provider.renderedBlockViewportFor('hero-1') ??
                  provider.previewViewport,
              child: wholePanel
                  ? const WebsiteEditorPanel()
                  : Consumer<WebsiteEditModeProvider>(
                      builder: (context, live, _) => WebsiteBlockEditSurface(
                        editProvider: live,
                        section: WebsiteBlockEditSection.layout,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }

  Future<WebsiteEditModeProvider> pumpInspector(
    WidgetTester tester, {
    required double width,
    bool wholePanel = false,
  }) async {
    useViewport(tester, width: width);
    final provider = newProvider();
    provider.reportRenderedBlockViewport(
      'hero-1',
      WebsiteResponsiveDataCodec.viewportForDocumentWidth(
        dataOf(provider),
        WebsiteEditorChromeGeometry.canvasWidthFor(width),
      ),
    );
    await tester.pumpWidget(
      host(
        provider: provider,
        editorWidth: width,
        wholePanel: wholePanel,
      ),
    );
    await tester.pump();
    return provider;
  }

  void expectMinimumHeight(
    WidgetTester tester,
    Iterable<Key> keys,
    double minimum,
  ) {
    for (final key in keys) {
      final finder = find.byKey(key);
      expect(finder, findsOneWidget, reason: '$key existe');
      expect(
        tester.getSize(finder).height,
        greaterThanOrEqualTo(minimum),
        reason: '$key respeta el target del host',
      );
    }
  }

  group('O-05 · phone/tablet touch', () {
    for (final width in <double>[390, 834]) {
      testWidgets('$width: presets, custom y apply cumplen F-06',
          (tester) async {
        await pumpInspector(tester, width: width);
        final touchTarget = VbDensity.touch.controlHeight;

        expectMinimumHeight(tester, heightPresetKeys, touchTarget);
        expectMinimumHeight(tester, spacingPresetKeys, touchTarget);
        expectMinimumHeight(
          tester,
          const <Key>[customToggleKey, resetKey],
          touchTarget,
        );

        await tester.tap(find.byKey(customToggleKey));
        await tester.pump();

        expectMinimumHeight(
          tester,
          const <Key>[customInputKey, applyKey],
          touchTarget,
        );
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('los targets ampliados ejecutan el comando una sola vez',
        (tester) async {
      final provider = await pumpInspector(tester, width: 390);

      await tester.tap(
        find.byKey(const ValueKey<String>('website-height-preset-small')),
      );
      await tester.pump();
      expect(dataOf(provider)['blockHeight'], 300);

      await tester.tap(
        find.byKey(const ValueKey<String>('website-spacing-preset-M')),
      );
      await tester.pump();
      expect(dataOf(provider)['spacingAfter'], 32);

      await tester.tap(find.byKey(customToggleKey));
      await tester.pump();
      final field = find.descendant(
        of: find.byKey(customInputKey),
        matching: find.byType(TextField),
      );
      await tester.enterText(field, '510');
      await tester.tap(find.byKey(applyKey));
      await tester.pump();
      expect(dataOf(provider)['blockHeight'], 510);

      await tester.tap(find.byKey(resetKey));
      await tester.pump();
      expect(dataOf(provider)['blockHeight'], isNull);
    });

    testWidgets(
        'el slider de espaciado conserva ticks locales y agrega un solo undo',
        (tester) async {
      final provider = await pumpInspector(tester, width: 390);
      final original = dataOf(provider);
      final sliderOwner = find.byKey(
        const ValueKey<String>('website-block-spacing-slider'),
      );
      var slider = tester.widget<Slider>(
        find.descendant(of: sliderOwner, matching: find.byType(Slider)),
      );

      slider.onChangeStart!(16);
      slider.onChanged!(24);
      slider.onChanged!(40);
      slider.onChanged!(56);
      await tester.pump();

      expect(dataOf(provider), original, reason: 'los ticks son sólo preview');
      expect(provider.canUndo, isFalse);

      slider = tester.widget<Slider>(
        find.descendant(of: sliderOwner, matching: find.byType(Slider)),
      );
      slider.onChangeEnd!(56);
      await tester.pump();

      expect(dataOf(provider)['spacingAfter'], 56);
      expect(provider.canUndo, isTrue);
      provider.undo();
      expect(dataOf(provider), original);
      expect(provider.canUndo, isFalse, reason: 'un drag equivale a un undo');
    });

    testWidgets('pointer-cancel del slider de espaciado no persiste',
        (tester) async {
      final provider = await pumpInspector(tester, width: 390);
      final original = dataOf(provider);
      final sliderOwner = find.byKey(
        const ValueKey<String>('website-block-spacing-slider'),
      );
      final slider = tester.widget<Slider>(
        find.descendant(of: sliderOwner, matching: find.byType(Slider)),
      );

      slider.onChangeStart!(16);
      slider.onChanged!(80);
      await tester.pump();
      final listener = tester.widget<Listener>(
        find.descendant(
          of: sliderOwner,
          matching: find.byWidgetPredicate(
            (widget) => widget is Listener && widget.onPointerCancel != null,
          ),
        ),
      );
      listener.onPointerCancel!(const PointerCancelEvent());
      await tester.pump();

      expect(dataOf(provider), original);
      expect(provider.canUndo, isFalse);
      expect(provider.hasUnsavedChanges, isFalse);
    });

    testWidgets('599/600 siguen touch y el corte exacto ocurre en 899/900',
        (tester) async {
      for (final entry in <(double, bool)>[
        (599, true),
        (600, true),
        (899, true),
        (900, false),
      ]) {
        await pumpInspector(tester, width: entry.$1);
        final height = tester
            .getSize(
              find.byKey(
                const ValueKey<String>('website-height-preset-auto'),
              ),
            )
            .height;
        if (entry.$2) {
          expect(
            height,
            greaterThanOrEqualTo(VbDensity.touch.controlHeight),
            reason: '${entry.$1} sigue siendo touch',
          );
        } else {
          expect(
            height,
            lessThan(VbDensity.touch.controlHeight),
            reason: '${entry.$1} ya es pointer',
          );
        }
      }
    });
  });

  group('pane · desktop pointer no hereda los 420 px locales', () {
    testWidgets('1440 conserva la densidad compacta existente', (tester) async {
      await pumpInspector(tester, width: 1440);

      for (final key in <Key>[
        ...heightPresetKeys,
        ...spacingPresetKeys,
        customToggleKey,
        resetKey,
      ]) {
        expect(
          tester.getSize(find.byKey(key)).height,
          lessThan(VbDensity.touch.controlHeight),
          reason: '$key no se convierte en touch por vivir en un pane angosto',
        );
      }

      await tester.tap(find.byKey(customToggleKey));
      await tester.pump();
      expect(tester.getSize(find.byKey(customInputKey)).height, 32);
      expect(tester.getSize(find.byKey(applyKey)).height, 32);
    });

    testWidgets('quick actions cambian con el host, no con el pane',
        (tester) async {
      await pumpInspector(tester, width: 1440, wholePanel: true);
      for (final key in quickActionKeys) {
        final size = tester.getSize(find.byKey(key));
        expect(size.width, lessThan(VbDensity.touch.controlHeight));
        expect(size.height, lessThan(VbDensity.touch.controlHeight));
      }

      await pumpInspector(tester, width: 834, wholePanel: true);
      for (final key in quickActionKeys) {
        final size = tester.getSize(find.byKey(key));
        expect(size.width, greaterThanOrEqualTo(VbDensity.touch.controlHeight));
        expect(
          size.height,
          greaterThanOrEqualTo(VbDensity.touch.controlHeight),
        );
      }
      expect(tester.takeException(), isNull);
    });
  });
}
