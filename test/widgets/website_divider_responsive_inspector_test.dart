import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:vinabike_erp/modules/website/models/website_responsive_authoring.dart';
import 'package:vinabike_erp/modules/website/models/website_responsive_field_state.dart';
import 'package:vinabike_erp/modules/website/providers/website_edit_mode_provider.dart';
import 'package:vinabike_erp/modules/website/widgets/responsive_field_shell.dart';
import 'package:vinabike_erp/modules/website/widgets/website_block_edit_section.dart';
import 'package:vinabike_erp/modules/website/widgets/website_color_picker.dart';
import 'package:vinabike_erp/modules/website/widgets/website_editor_chrome_geometry.dart';
import 'package:vinabike_erp/modules/website/widgets/website_editor_panel.dart';
import 'package:vinabike_erp/shared/themes/app_theme.dart';
import 'package:vinabike_erp/shared/themes/appearance_preset.dart';

/// Divider through the real generic inspector.
///
/// Design source: project `a0fa3196-6315-4b96-bde7-7cc801e7a74e`,
/// `Website Builder Responsive Authoring` t10 frames 10a/10b/10c. The batch
/// adds no control and no visual value: the three properties reach the already
/// approved `ResponsiveFieldShell` through the schema path.
void main() {
  Map<String, dynamic> dividerData() => <String, dynamic>{
        'thickness': 1,
        'widthPct': 1.0,
        'color': '#E5E7EB',
      };

  WebsiteEditModeProvider providerFor({
    DevicePreviewMode viewport = DevicePreviewMode.mobile,
  }) {
    return WebsiteEditModeProvider()
      ..enterEditMode(
        <Map<String, dynamic>>[
          {
            'id': 'block-1',
            'block_type': 'divider',
            'block_data': dividerData(),
            'is_visible': true,
            'sort_order': 0,
          },
        ],
        const <String, dynamic>{},
      )
      ..selectBlock('block-1')
      ..setDevicePreviewMode(viewport)
      ..reportRenderedBlockViewport(
        'block-1',
        switch (viewport) {
          DevicePreviewMode.desktop => WebsiteViewport.desktop,
          DevicePreviewMode.tablet => WebsiteViewport.tablet,
          DevicePreviewMode.mobile => WebsiteViewport.mobile,
        },
      );
  }

  Map<String, dynamic> dataOf(WebsiteEditModeProvider provider) =>
      Map<String, dynamic>.from(provider.blocks.single['block_data'] as Map);

  void useViewport(
    WidgetTester tester, {
    required double width,
    double height = 1400,
  }) {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = Size(width, height);
    addTearDown(tester.view.reset);
  }

  Widget host({
    required WebsiteEditModeProvider provider,
    required double editorWidth,
    Brightness brightness = Brightness.light,
  }) {
    return MaterialApp(
      theme: AppTheme.resolve(
        preset: AppearancePresets.pacific,
        brightness: brightness,
      ),
      home: ChangeNotifierProvider<WebsiteEditModeProvider>.value(
        value: provider,
        child: WebsiteEditorChromeScope(
          editorWidth: editorWidth,
          canvasWidth: WebsiteEditorChromeGeometry.canvasWidthFor(editorWidth),
          child: Consumer<WebsiteEditModeProvider>(
            builder: (context, watched, _) => Scaffold(
              body: WebsiteBlockEditSurface(
                editProvider: watched,
                section: WebsiteBlockEditSection.content,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Finder shellFor(String key) => find.byWidgetPredicate(
        (widget) =>
            widget is ResponsiveFieldShell && widget.state.schema.key == key,
      );

  WebsiteResponsiveFieldState<dynamic> stateOf(
    WidgetTester tester,
    String key,
  ) =>
      (tester.widget(shellFor(key)) as ResponsiveFieldShell).state;

  Future<void> settle(WidgetTester tester) async {
    for (var attempt = 0; attempt < 8; attempt++) {
      await tester.pump(const Duration(milliseconds: 40));
    }
  }

  Future<void> disclose(WidgetTester tester) async {
    final header = find.text('Apariencia');
    if (header.evaluate().isEmpty) return;
    if (shellFor('thickness').evaluate().isNotEmpty) return;
    await tester.tap(header.first, warnIfMissed: false);
    await settle(tester);
  }

  Future<void> tapShellAction(
    WidgetTester tester,
    String key,
    Key actionKey,
  ) async {
    final action = find.descendant(
      of: shellFor(key),
      matching: find.byKey(actionKey),
    );
    expect(action, findsOneWidget, reason: '$key / $actionKey');
    await tester.ensureVisible(action);
    await settle(tester);
    await tester.tap(action);
    await settle(tester);
  }

  Future<void> pumpDivider(
    WidgetTester tester, {
    required double width,
    required DevicePreviewMode viewport,
    Brightness brightness = Brightness.light,
  }) async {
    useViewport(tester, width: width);
    final provider = providerFor(viewport: viewport);
    await tester.pumpWidget(
      host(
        provider: provider,
        editorWidth: width,
        brightness: brightness,
      ),
    );
    await settle(tester);
    await disclose(tester);
  }

  const keys = <String>['thickness', 'widthPct', 'color'];

  group('2 · el inspector real del separador', () {
    testWidgets('390 en Móvil: los tres dicen Heredado y ofrecen personalizar',
        (tester) async {
      await pumpDivider(
        tester,
        width: 390,
        viewport: DevicePreviewMode.mobile,
      );

      for (final key in keys) {
        expect(shellFor(key), findsOneWidget, reason: key);
        expect(
          stateOf(tester, key).status,
          WebsiteResponsiveFieldStatus.inherited,
          reason: key,
        );
        expect(
          stateOf(tester, key).effectiveWriteScope,
          WebsiteWriteScope.shared,
          reason: 'sin personalizar todavía, el próximo cambio es común',
        );
        expect(
          find.descendant(
            of: shellFor(key),
            matching: find.byKey(ResponsiveFieldShell.customizeActionKey),
          ),
          findsOneWidget,
          reason: key,
        );
      }
    });

    testWidgets('834 en Tablet: mismo estado, y la acción nombra Tablet',
        (tester) async {
      await pumpDivider(
        tester,
        width: 834,
        viewport: DevicePreviewMode.tablet,
      );

      for (final key in keys) {
        expect(
          stateOf(tester, key).status,
          WebsiteResponsiveFieldStatus.inherited,
          reason: key,
        );
        expect(
          stateOf(tester, key).context.previewViewport,
          WebsiteViewport.tablet,
          reason: key,
        );
      }
      expect(find.text('Personalizar para Tablet'), findsNWidgets(keys.length));
    });

    testWidgets('1440 en Escritorio: Común y sin personalizar', (tester) async {
      await pumpDivider(
        tester,
        width: 1440,
        viewport: DevicePreviewMode.desktop,
      );

      for (final key in keys) {
        expect(
          stateOf(tester, key).status,
          WebsiteResponsiveFieldStatus.common,
          reason: key,
        );
        expect(
          stateOf(tester, key).effectiveWriteScope,
          WebsiteWriteScope.shared,
          reason: key,
        );
        expect(
          find.descendant(
            of: shellFor(key),
            matching: find.byKey(ResponsiveFieldShell.customizeActionKey),
          ),
          findsNothing,
          reason: key,
        );
      }
    });
  });

  group('3 · customize + write + reset por los controles reales', () {
    /// Writes through the control the inspector actually mounted for [key].
    void writeThrough(WidgetTester tester, String key, Object value) {
      switch (key) {
        case 'color':
          tester
              .widget<WebsiteColorPickerField>(
                find.descendant(
                  of: shellFor(key),
                  matching: find.byType(WebsiteColorPickerField),
                ),
              )
              .onChanged(value as String);
        default:
          final slider = tester.widget<Slider>(
            find.descendant(
              of: shellFor(key),
              matching: find.byType(Slider),
            ),
          );
          final next = (value as num).toDouble();
          slider.onChangeStart!(slider.value);
          slider.onChanged!(next);
          slider.onChangeEnd!(next);
      }
    }

    for (final (viewport, bucket, width)
        in const <(DevicePreviewMode, String, double)>[
      (DevicePreviewMode.mobile, 'mobile', 390),
      (DevicePreviewMode.tablet, 'tablet', 834),
    ]) {
      testWidgets(
          '$bucket: cada override aterriza en responsive.$bucket y '
          'vuelve al común', (tester) async {
        await pumpDivider(tester, width: width, viewport: viewport);
        final provider = tester
            .widget<WebsiteBlockEditSurface>(
              find.byType(WebsiteBlockEditSurface),
            )
            .editProvider;
        final original = dataOf(provider);
        expect(provider.hasUnsavedChanges, isFalse);

        const written = <String, Object>{
          'thickness': 6,
          'widthPct': 0.5,
          'color': '#123456',
        };

        for (final key in keys) {
          await tapShellAction(
            tester,
            key,
            ResponsiveFieldShell.customizeActionKey,
          );
          writeThrough(tester, key, written[key]!);
          await settle(tester);
        }

        final overrides =
            (dataOf(provider)['responsive'] as Map)[bucket] as Map;
        expect(overrides['thickness'], 6);
        expect(overrides['widthPct'], 0.5);
        expect(overrides['color'], '#123456');

        // El común queda intacto…
        expect(dataOf(provider)['thickness'], 1);
        expect(dataOf(provider)['widthPct'], 1.0);
        expect(dataOf(provider)['color'], '#E5E7EB');
        // …y el otro viewport no recibió nada: no hay cascada.
        final otherBucket = bucket == 'mobile' ? 'tablet' : 'mobile';
        expect(
          (dataOf(provider)['responsive'] as Map).containsKey(otherBucket),
          isFalse,
        );

        for (final key in keys) {
          expect(
            stateOf(tester, key).status,
            WebsiteResponsiveFieldStatus.overridden,
            reason: key,
          );
          await tapShellAction(
            tester,
            key,
            ResponsiveFieldShell.resetActionKey,
          );
        }

        expect(dataOf(provider), original);
        expect(provider.hasUnsavedChanges, isFalse);
        expect(dataOf(provider).containsKey('responsive'), isFalse);
      });
    }
  });

  group('5 · anchos, brillos y ausencia de duplicados', () {
    for (final (width, viewport) in const <(double, DevicePreviewMode)>[
      (390, DevicePreviewMode.mobile),
      (834, DevicePreviewMode.tablet),
      (1440, DevicePreviewMode.desktop),
    ]) {
      for (final brightness in Brightness.values) {
        testWidgets(
            '$width · $brightness sin overflow y una etiqueta por '
            'campo', (tester) async {
          await pumpDivider(
            tester,
            width: width,
            viewport: viewport,
            brightness: brightness,
          );

          for (final key in keys) {
            expect(shellFor(key), findsOneWidget, reason: key);
          }
          expect(find.text('Grosor'), findsOneWidget);
          expect(find.text('Ancho (%)'), findsOneWidget);
          expect(find.text('Color'), findsOneWidget);
          expect(tester.takeException(), isNull);
        });
      }
    }

    testWidgets('en host compacto la acción del shell cumple 48',
        (tester) async {
      await pumpDivider(
        tester,
        width: 390,
        viewport: DevicePreviewMode.mobile,
      );

      for (final key in keys) {
        final action = find.descendant(
          of: shellFor(key),
          matching: find.byKey(ResponsiveFieldShell.customizeActionKey),
        );
        await tester.ensureVisible(action);
        await settle(tester);
        expect(
          tester.getSize(action).height,
          greaterThanOrEqualTo(48),
          reason: key,
        );
      }
    });
  });
}
