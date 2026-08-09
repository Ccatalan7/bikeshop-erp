import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:vinabike_erp/modules/website/models/website_responsive_authoring.dart';
import 'package:vinabike_erp/modules/website/providers/website_edit_mode_provider.dart';
import 'package:vinabike_erp/modules/website/widgets/text_formatting_toolbar.dart';
import 'package:vinabike_erp/modules/website/widgets/website_block_edit_section.dart';
import 'package:vinabike_erp/modules/website/widgets/website_color_picker.dart';
import 'package:vinabike_erp/modules/website/widgets/website_editor_chrome_geometry.dart';
import 'package:vinabike_erp/modules/website/widgets/website_editor_panel.dart';
import 'package:vinabike_erp/shared/themes/app_theme.dart';
import 'package:vinabike_erp/shared/themes/appearance_preset.dart';

void main() {
  testWidgets(
      'toolbar keeps font-size ticks local, cancels A on B, and commits B once',
      (tester) async {
    var owner = 'A';
    var formatting = const TextFormatting(fontSize: 16);
    final writesA = <TextFormatting>[];
    final writesB = <TextFormatting>[];
    late StateSetter rebuild;

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(useMaterial3: true),
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              rebuild = setState;
              final renderedOwner = owner;
              return TextFormattingToolbar(
                key: const ValueKey<String>('formatting-toolbar'),
                currentFormatting: formatting,
                preset: TextToolbarPreset.basic,
                showAdvancedOptions: false,
                transactionIdentity: renderedOwner,
                onFormattingChanged: (value) {
                  (renderedOwner == 'A' ? writesA : writesB).add(value);
                  setState(() => formatting = value);
                },
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.byTooltip('Tamaño de fuente'));
    await tester.pump();
    var slider = tester.widget<Slider>(find.byType(Slider));
    slider.onChangeStart!(16);
    slider.onChanged!(24);
    slider.onChanged!(32);
    slider.onChanged!(40);
    expect(writesA, isEmpty);
    expect(writesB, isEmpty);

    rebuild(() => owner = 'B');
    await tester.pump();
    expect(writesA, isEmpty);
    expect(writesB, isEmpty);

    slider = tester.widget<Slider>(find.byType(Slider));
    slider.onChangeStart!(16);
    slider.onChanged!(28);
    slider.onChanged!(36);
    slider.onChanged!(48);
    expect(writesB, isEmpty);
    slider.onChangeEnd!(48);
    await tester.pump();

    expect(writesA, isEmpty);
    expect(writesB, hasLength(1));
    expect(writesB.single.fontSize, 48);

    slider = tester.widget<Slider>(find.byType(Slider));
    slider.onChangeStart!(48);
    slider.onChanged!(64);
    final listener = tester.widget<Listener>(
      find.descendant(
        of: find.byType(WebsiteTransactionalSlider),
        matching: find.byWidgetPredicate(
          (widget) => widget is Listener && widget.onPointerCancel != null,
        ),
      ),
    );
    listener.onPointerCancel!(const PointerCancelEvent());
    expect(writesB, hasLength(1));
  });

  for (final fixture in <({
    String label,
    Map<String, dynamic> block,
    double Function(Map<String, dynamic>) fontSize,
  })>[
    (
      label: 'schema root',
      block: <String, dynamic>{
        'id': 'hero-1',
        'block_type': 'hero',
        'block_data': <String, dynamic>{
          'title': 'Portada',
          'titleFormatting': <String, dynamic>{'fontSize': 16.0},
        },
        'is_visible': true,
        'sort_order': 0,
      },
      fontSize: (data) =>
          ((data['titleFormatting'] as Map)['fontSize'] as num).toDouble(),
    ),
    (
      label: 'carousel item',
      block: <String, dynamic>{
        'id': 'carousel-1',
        'block_type': 'carousel',
        'block_data': <String, dynamic>{
          'slides': <Map<String, dynamic>>[
            <String, dynamic>{
              'id': 'slide-1',
              'title': 'Primero',
              'subtitle': 'Texto',
              'titleFormatting': <String, dynamic>{'fontSize': 16.0},
            },
          ],
        },
        'is_visible': true,
        'sort_order': 0,
      },
      fontSize: (data) => ((((data['slides'] as List).first
              as Map)['titleFormatting'] as Map)['fontSize'] as num)
          .toDouble(),
    ),
  ]) {
    testWidgets('${fixture.label} convierte un drag en un solo undo',
        (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1440, 1200);
      addTearDown(tester.view.reset);

      final provider = WebsiteEditModeProvider()
        ..enterEditMode(
          <Map<String, dynamic>>[
            Map<String, dynamic>.from(fixture.block),
          ],
          const <String, dynamic>{},
          pageId: 'page-1',
          pageSlug: 'inicio',
        )
        ..selectBlock(fixture.block['id'] as String);
      addTearDown(provider.dispose);
      provider.reportRenderedBlockViewport(
        fixture.block['id'] as String,
        WebsiteViewport.desktop,
      );
      final original = provider.blocks;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.resolve(
            preset: AppearancePresets.pacific,
            brightness: Brightness.dark,
          ),
          home: ChangeNotifierProvider<WebsiteEditModeProvider>.value(
            value: provider,
            child: WebsiteEditorChromeScope(
              editorWidth: 1440,
              canvasWidth: WebsiteEditorChromeGeometry.canvasWidthFor(1440),
              child: WebsiteEditorAuthoringViewportScope(
                requestedViewport: provider.previewViewport,
                effectiveViewport: WebsiteViewport.desktop,
                child: Scaffold(
                  body: SizedBox(
                    width: 420,
                    child: Consumer<WebsiteEditModeProvider>(
                      builder: (context, live, _) => WebsiteBlockEditSurface(
                        editProvider: live,
                        section: WebsiteBlockEditSection.content,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.byTooltip('Tamaño de fuente').first);
      await tester.pump();
      final toolbar = find.byType(TextFormattingToolbar).first;
      final slider = tester.widget<Slider>(
        find.descendant(of: toolbar, matching: find.byType(Slider)),
      );
      slider.onChangeStart!(16);
      slider.onChanged!(24);
      slider.onChanged!(36);
      slider.onChanged!(48);
      await tester.pump();

      expect(provider.blocks, original, reason: 'los ticks no persisten');
      expect(provider.canUndo, isFalse);

      final liveSlider = tester.widget<Slider>(
        find.descendant(of: toolbar, matching: find.byType(Slider)),
      );
      liveSlider.onChangeEnd!(48);
      await tester.pump();

      final data = Map<String, dynamic>.from(
        provider.blocks.single['block_data'] as Map,
      );
      expect(fixture.fontSize(data), 48);
      expect(provider.canUndo, isTrue);
      provider.undo();
      expect(provider.blocks, original);
      expect(provider.canUndo, isFalse, reason: 'un drag equivale a un undo');
    });
  }
}
