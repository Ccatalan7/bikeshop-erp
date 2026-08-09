import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:vinabike_erp/modules/website/models/website_block_definition.dart';
import 'package:vinabike_erp/modules/website/models/website_block_surface_style.dart';
import 'package:vinabike_erp/modules/website/models/website_responsive_authoring.dart';
import 'package:vinabike_erp/modules/website/providers/website_edit_mode_provider.dart';
import 'package:vinabike_erp/modules/website/widgets/responsive_field_shell.dart';
import 'package:vinabike_erp/modules/website/widgets/website_block_edit_section.dart';
import 'package:vinabike_erp/modules/website/widgets/website_editor_chrome_geometry.dart';
import 'package:vinabike_erp/modules/website/widgets/website_editor_host_theme.dart';
import 'package:vinabike_erp/modules/website/widgets/website_editor_panel.dart';
import 'package:vinabike_erp/shared/themes/app_theme.dart';
import 'package:vinabike_erp/shared/themes/appearance_preset.dart';

void main() {
  const blockId = 'surface-block';

  WebsiteEditModeProvider providerFor(
    Map<String, dynamic> data, {
    DevicePreviewMode preview = DevicePreviewMode.mobile,
  }) {
    final provider = WebsiteEditModeProvider()
      ..enterEditMode(
        <Map<String, dynamic>>[
          <String, dynamic>{
            'id': blockId,
            'block_type': 'hero',
            'block_data': data,
            'is_visible': true,
            'sort_order': 0,
          },
        ],
        const <String, dynamic>{},
        pageId: 'page-style',
        pageSlug: '/style',
      )
      ..selectBlock(blockId)
      ..setDevicePreviewMode(preview);
    final viewport = switch (preview) {
      DevicePreviewMode.desktop => WebsiteViewport.desktop,
      DevicePreviewMode.tablet => WebsiteViewport.tablet,
      DevicePreviewMode.mobile => WebsiteViewport.mobile,
    };
    provider.reportRenderedBlockViewport(blockId, viewport);
    addTearDown(provider.dispose);
    return provider;
  }

  Map<String, dynamic> dataOf(WebsiteEditModeProvider provider) =>
      Map<String, dynamic>.from(provider.blocks.single['block_data'] as Map);

  Widget host(
    WebsiteEditModeProvider provider, {
    required double width,
    Brightness brightness = Brightness.light,
  }) {
    final viewport = width < 600
        ? WebsiteViewport.mobile
        : width < 900
            ? WebsiteViewport.tablet
            : WebsiteViewport.desktop;
    return MaterialApp(
      theme: AppTheme.resolve(
        preset: AppearancePresets.pacific,
        brightness: brightness,
      ),
      home: Builder(
        builder: (hostContext) => ChangeNotifierProvider.value(
          value: provider,
          child: WebsiteEditorChromeScope(
            editorWidth: width,
            canvasWidth: width,
            child: WebsiteEditorAuthoringViewportScope(
              requestedViewport: viewport,
              effectiveViewport: viewport,
              child: Theme(
                data: WebsiteEditorInspectorTheme.resolveFrom(hostContext),
                child: Consumer<WebsiteEditModeProvider>(
                  builder: (context, live, _) => Scaffold(
                    body: WebsiteBlockEditSurface(
                      editProvider: live,
                      section: WebsiteBlockEditSection.style,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> pumpStyle(
    WidgetTester tester,
    WebsiteEditModeProvider provider, {
    required double width,
  }) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = Size(width, 2600);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(host(provider, width: width));
    await tester.pumpAndSettle();
  }

  testWidgets('390 and 834 use graphite owner and 48pt Style targets',
      (tester) async {
    for (final (width, preview) in <(double, DevicePreviewMode)>[
      (390, DevicePreviewMode.mobile),
      (834, DevicePreviewMode.tablet),
    ]) {
      final provider = providerFor(
        <String, dynamic>{
          'title': 'Superficie',
          'style': <String, dynamic>{
            'backgroundType': 'gradient',
            'borderWidth': 1,
            'borderStyle': 'solid',
            'shadowEnabled': true,
            'shadowOffsetX': 0,
            'shadowOffsetY': 1,
            'shadowBlur': 2,
            'shadowSpread': 0,
            'shadowColor': 'rgba(12,37,55,0.06)',
          },
        },
        preview: preview,
      );
      await pumpStyle(tester, provider, width: width);

      final targetKeys = <Key>[
        const ValueKey<String>('surface-background-type'),
        const ValueKey<String>('surface-padding-vertical'),
        const ValueKey<String>('surface-padding-horizontal'),
        const ValueKey<String>('surface-border-preset'),
        const ValueKey<String>('surface-shadow-preset'),
        const ValueKey<String>('surface-gradient-to-top'),
      ];
      for (final key in targetKeys) {
        final target = find.byKey(key);
        expect(target, findsOneWidget, reason: '$width $key');
        expect(
          tester.getSize(target).height,
          greaterThanOrEqualTo(48),
          reason: '$width $key uses the touch-density owner',
        );
      }

      final element = tester.element(
        find.byKey(const ValueKey<String>('surface-padding-vertical')),
      );
      expect(Theme.of(element).brightness, Brightness.dark);
      expect(
        Theme.of(element).colorScheme.surface,
        WebsiteEditorInspectorTheme.canvas,
      );
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('padding axis writes both stored sides in exactly one undo',
      (tester) async {
    final provider = providerFor(<String, dynamic>{
      'title': 'Superficie',
      'style': <String, dynamic>{'futureStyleOwner': 'preserved'},
    });
    for (final field in <WebsiteBlockFieldSchema>[
      WebsiteBlockSurfaceFields.paddingTop,
      WebsiteBlockSurfaceFields.paddingBottom,
    ]) {
      provider.setFieldWriteScope(
        blockId: blockId,
        propertyKey: field.key,
        policy: field.responsivePolicy,
        scope: WebsiteWriteScope.viewport,
        viewport: WebsiteViewport.mobile,
      );
    }
    await pumpStyle(tester, provider, width: 390);

    final vertical = find.byKey(
      const ValueKey<String>('surface-padding-vertical'),
    );
    expect(vertical, findsOneWidget);
    final before = dataOf(provider);
    await tester.tap(
      find.descendant(of: vertical, matching: find.text('48')),
    );
    await tester.pumpAndSettle();
    final changed = dataOf(provider);
    final mobile = (changed['responsive'] as Map)['mobile'] as Map;
    expect(mobile['surfacePaddingTop'], 48);
    expect(mobile['surfacePaddingBottom'], 48);
    expect((changed['style'] as Map)['futureStyleOwner'], 'preserved');
    expect(provider.canUndo, isTrue);

    provider.undo();
    await tester.pumpAndSettle();
    expect(dataOf(provider), before);
    expect(provider.canUndo, isFalse,
        reason: 'one axis selection is one history entry');
  });

  testWidgets(
      'legacy padding stays byte-stable until explicit scale adjustment',
      (tester) async {
    final provider = providerFor(<String, dynamic>{
      'title': 'Superficie heredada',
      'style': <String, dynamic>{
        'paddingTop': 55,
        'paddingBottom': 23,
        'paddingLeft': 12,
        'paddingRight': 29,
        'futureStyleOwner': 'preserved',
      },
    });
    final before = dataOf(provider);
    await pumpStyle(tester, provider, width: 390);

    expect(dataOf(provider), before);
    expect(provider.hasUnsavedChanges, isFalse);
    expect(provider.canUndo, isFalse);
    expect(find.text('Personalizado heredado'), findsNWidgets(2));
    expect(
      find.byKey(const ValueKey<String>('surface-padding-vertical')),
      findsNothing,
      reason: 'an unknown value must not make S-04 select a false preset',
    );
    expect(
      find.byKey(const ValueKey<String>('surface-padding-horizontal')),
      findsNothing,
    );

    await tester.tap(
      find.byKey(
        const ValueKey<String>('surface-padding-vertical-adjust'),
      ),
    );
    await tester.pumpAndSettle();

    final changed = dataOf(provider);
    final style = changed['style'] as Map;
    expect(style['paddingTop'], 32);
    expect(style['paddingBottom'], 32);
    expect(style['paddingLeft'], 12);
    expect(style['paddingRight'], 29);
    expect(style['futureStyleOwner'], 'preserved');
    expect(provider.canUndo, isTrue);

    provider.undo();
    await tester.pumpAndSettle();
    expect(dataOf(provider), before);
    expect(provider.canUndo, isFalse);
  });

  testWidgets('padding axis customize and reset own both responsive sides',
      (tester) async {
    final provider = providerFor(<String, dynamic>{
      'title': 'Superficie',
      'style': <String, dynamic>{
        'paddingTop': 32,
        'paddingBottom': 32,
      },
    });
    await pumpStyle(tester, provider, width: 390);

    final verticalField = find.byKey(
      const ValueKey<String>('surface-padding-vertical-field'),
    );
    await tester.tap(
      find.descendant(
        of: verticalField,
        matching: find.byKey(ResponsiveFieldShell.customizeActionKey),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: verticalField,
        matching: find.text('64'),
      ),
    );
    await tester.pumpAndSettle();

    var mobile = (dataOf(provider)['responsive'] as Map)['mobile'] as Map;
    expect(mobile['surfacePaddingTop'], 64);
    expect(mobile['surfacePaddingBottom'], 64);

    await tester.tap(
      find.descendant(
        of: verticalField,
        matching: find.byKey(ResponsiveFieldShell.resetActionKey),
      ),
    );
    await tester.pumpAndSettle();
    final responsiveAfterReset = dataOf(provider)['responsive'] as Map?;
    final mobileAfterReset = responsiveAfterReset?['mobile'] as Map?;
    expect(
      mobileAfterReset?.containsKey('surfacePaddingTop') ?? false,
      isFalse,
    );
    expect(
      mobileAfterReset?.containsKey('surfacePaddingBottom') ?? false,
      isFalse,
    );
    expect(provider.canUndo, isTrue);

    provider.undo();
    await tester.pumpAndSettle();
    mobile = (dataOf(provider)['responsive'] as Map)['mobile'] as Map;
    expect(mobile['surfacePaddingTop'], 64);
    expect(mobile['surfacePaddingBottom'], 64);
  });

  testWidgets('padding axis cannot split its two sides across write scopes',
      (tester) async {
    final provider = providerFor(<String, dynamic>{
      'title': 'Superficie',
      'style': <String, dynamic>{
        'paddingTop': 32,
        'paddingBottom': 32,
      },
    });
    provider.setFieldWriteScope(
      blockId: blockId,
      propertyKey: WebsiteBlockSurfaceFields.paddingTop.key,
      policy: WebsiteBlockSurfaceFields.paddingTop.responsivePolicy,
      scope: WebsiteWriteScope.viewport,
      viewport: WebsiteViewport.mobile,
    );
    await pumpStyle(tester, provider, width: 390);

    final vertical = find.byKey(
      const ValueKey<String>('surface-padding-vertical'),
    );
    await tester.tap(
      find.descendant(of: vertical, matching: find.text('48')),
    );
    await tester.pumpAndSettle();

    final data = dataOf(provider);
    final style = data['style'] as Map;
    final mobile = (data['responsive'] as Map)['mobile'] as Map;
    expect(style['paddingTop'], 32);
    expect(style['paddingBottom'], 32);
    expect(mobile['surfacePaddingTop'], 48);
    expect(mobile['surfacePaddingBottom'], 48);
    expect(provider.canUndo, isTrue);

    provider.undo();
    await tester.pumpAndSettle();
    expect(dataOf(provider)['responsive'], isNull);
    expect(provider.canUndo, isFalse);
  });

  testWidgets('Style color drafts in dialog and commits once on Apply',
      (tester) async {
    final provider = providerFor(<String, dynamic>{
      'title': 'Superficie',
      'style': <String, dynamic>{'backgroundColor': '#FF112233'},
    });
    await pumpStyle(tester, provider, width: 390);
    final before = dataOf(provider);

    expect(
      find.byKey(const ValueKey<String>('website_color_opacity_Color')),
      findsNothing,
      reason: 'Style does not expose the per-tick opacity shortcut',
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('website_color_picker_Color')),
    );
    await tester.pumpAndSettle();

    final dialogOpacity = find.byKey(
      const ValueKey<String>('website_color_picker_dialog_opacity'),
    );
    expect(dialogOpacity, findsOneWidget);
    final opacitySlider = tester.widget<Slider>(dialogOpacity);
    opacitySlider.onChanged!(0.75);
    await tester.pump();
    tester.widget<Slider>(dialogOpacity).onChanged!(0.5);
    await tester.pump();
    expect(dataOf(provider), before);
    expect(provider.canUndo, isFalse);

    await tester.tap(
      find.byKey(const ValueKey<String>('website_color_picker_apply')),
    );
    await tester.pumpAndSettle();
    expect(dataOf(provider), isNot(before));
    expect(provider.canUndo, isTrue);

    provider.undo();
    await tester.pumpAndSettle();
    expect(dataOf(provider), before);
    expect(provider.canUndo, isFalse);
  });

  testWidgets(
      'Style color Apply keeps the document lease captured before the dialog',
      (tester) async {
    final provider = providerFor(<String, dynamic>{
      'title': 'Documento A',
      'style': <String, dynamic>{'backgroundColor': '#FF112233'},
    });
    await pumpStyle(tester, provider, width: 390);

    await tester.tap(
      find.byKey(const ValueKey<String>('website_color_picker_Color')),
    );
    await tester.pumpAndSettle();
    final opacity = find.byKey(
      const ValueKey<String>('website_color_picker_dialog_opacity'),
    );
    tester.widget<Slider>(opacity).onChanged!(0.25);
    await tester.pump();

    const documentB = <Map<String, dynamic>>[
      <String, dynamic>{
        'id': blockId,
        'block_type': 'hero',
        'block_data': <String, dynamic>{
          'title': 'Documento B',
          'style': <String, dynamic>{'backgroundColor': '#FFABCDEF'},
        },
        'is_visible': true,
        'sort_order': 0,
      },
    ];
    provider
      ..enterEditMode(
        documentB,
        const <String, dynamic>{},
        pageId: 'page-style-b',
        pageSlug: '/style-b',
      )
      ..selectBlock(blockId)
      ..reportRenderedBlockViewport(blockId, WebsiteViewport.mobile);
    await tester.pump();

    await tester.tap(
      find.byKey(const ValueKey<String>('website_color_picker_apply')),
    );
    await tester.pumpAndSettle();

    expect(dataOf(provider)['title'], 'Documento B');
    expect(
      (dataOf(provider)['style'] as Map)['backgroundColor'],
      '#FFABCDEF',
    );
    expect(provider.hasUnsavedChanges, isFalse);
    expect(provider.canUndo, isFalse);
    expect(tester.takeException(), isNull);
  });

  test('Style chrome has no local palette or unsupported border choices', () {
    final source = File(
      'lib/modules/website/widgets/editor_panel/style_controls.dart',
    ).readAsStringSync();

    expect(source, isNot(contains('const Color(')));
    expect(source, isNot(contains('Colors.white')));
    expect(source, isNot(contains('0xFF00A09D')));
    expect(source, isNot(contains('GestureDetector')));
    expect(source, isNot(contains("'dashed'")));
    expect(source, isNot(contains("'dotted'")));
    expect(source, isNot(contains('updateBlockData(')));
    expect(source, isNot(contains('_SurfaceSlider')));
    expect(source, isNot(contains('_PaddingLinkControl')));
    expect(source, contains('VbSegmented'));
    expect(source, contains('verticalPaddingChoices'));
    expect(source, contains('horizontalPaddingChoices'));
  });
}
