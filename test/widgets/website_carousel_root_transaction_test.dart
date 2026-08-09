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

void main() {
  WebsiteEditModeProvider providerFor(Map<String, dynamic> data) {
    final provider = WebsiteEditModeProvider()
      ..enterEditMode(
        <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'carousel-block',
            'block_type': 'carousel',
            'block_data': data,
            'is_visible': true,
            'sort_order': 0,
          },
        ],
        const <String, dynamic>{},
        pageId: 'page-1',
        pageSlug: 'inicio',
      )
      ..selectBlock('carousel-block')
      ..setDevicePreviewMode(DevicePreviewMode.mobile)
      ..reportRenderedBlockViewport(
        'carousel-block',
        WebsiteViewport.mobile,
      );
    addTearDown(provider.dispose);
    return provider;
  }

  Map<String, dynamic> dataOf(WebsiteEditModeProvider provider) =>
      Map<String, dynamic>.from(provider.blocks.single['block_data'] as Map);

  Map<String, dynamic> carouselData({
    bool autoPlay = true,
    int transitionDuration = 600,
  }) =>
      <String, dynamic>{
        'autoPlay': autoPlay,
        'intervalSeconds': 5,
        'transitionDuration': transitionDuration,
        'animation': 'slide',
        'showIndicators': true,
        'showArrows': true,
        'slides': <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'slide-a',
            'title': 'Primero',
            'subtitle': 'Descripción',
            'showOverlay': true,
            'overlayOpacity': 0.55,
          },
        ],
      };

  Widget host(WebsiteEditModeProvider provider, {double width = 390}) {
    return MaterialApp(
      theme: AppTheme.resolve(
        preset: AppearancePresets.pacific,
        brightness: Brightness.dark,
      ),
      home: ChangeNotifierProvider<WebsiteEditModeProvider>.value(
        value: provider,
        child: WebsiteEditorChromeScope(
          editorWidth: width,
          canvasWidth: WebsiteEditorChromeGeometry.canvasWidthFor(width),
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

  Future<void> settle(WidgetTester tester) async {
    for (var attempt = 0; attempt < 10; attempt++) {
      await tester.pump(const Duration(milliseconds: 40));
    }
  }

  Future<void> openBehavior(WidgetTester tester) async {
    final title = find.text('Comportamiento del carrusel');
    expect(title, findsOneWidget);
    await tester.ensureVisible(title);
    await tester.tap(title);
    await settle(tester);
  }

  void usePhoneSurface(WidgetTester tester) {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 1600);
    addTearDown(tester.view.reset);
  }

  testWidgets('root toggle is one-shot before rebuild and one undo',
      (tester) async {
    usePhoneSurface(tester);
    final provider = providerFor(carouselData());
    await tester.pumpWidget(host(provider));
    await settle(tester);
    await openBehavior(tester);

    final autoPlay = tester.widget<Switch>(find.byType(Switch).first);
    expect(autoPlay.value, isTrue);
    autoPlay.onChanged!(false);
    autoPlay.onChanged!(true);
    await settle(tester);

    expect(dataOf(provider)['autoPlay'], isFalse);
    provider.undo();
    expect(dataOf(provider)['autoPlay'], isTrue);
    expect(provider.canUndo, isFalse,
        reason: 'the second callback from the same control was rejected');
    expect(tester.takeException(), isNull);
  });

  testWidgets('root animation dropdown is exact and rejects a second callback',
      (tester) async {
    usePhoneSurface(tester);
    final provider = providerFor(carouselData());
    await tester.pumpWidget(host(provider));
    await settle(tester);
    await openBehavior(tester);

    final anchor = find.text('Deslizar').first;
    await tester.ensureVisible(anchor);
    await tester.tap(anchor);
    await settle(tester);

    final fade = tester.widget<MenuItemButton>(
      find.widgetWithText(MenuItemButton, 'Desvanecer'),
    );
    final zoom = tester.widget<MenuItemButton>(
      find.widgetWithText(MenuItemButton, 'Zoom'),
    );
    fade.onPressed!();
    zoom.onPressed!();
    await settle(tester);

    expect(dataOf(provider)['animation'], 'fade');
    provider.undo();
    expect(dataOf(provider)['animation'], 'slide');
    expect(provider.canUndo, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('duration ticks stay local then commit both aliases in one undo',
      (tester) async {
    usePhoneSurface(tester);
    final provider = providerFor(carouselData(transitionDuration: 600));
    await tester.pumpWidget(host(provider));
    await settle(tester);
    await openBehavior(tester);

    final durationFinder = find.byWidgetPredicate(
      (widget) => widget is Slider && widget.min == 200 && widget.max == 2000,
    );
    expect(durationFinder, findsOneWidget);
    final duration = tester.widget<Slider>(durationFinder);
    duration.onChangeStart!(600);
    duration.onChanged!(700);
    duration.onChanged!(800);
    duration.onChanged!(900);
    await tester.pump();

    expect(dataOf(provider).containsKey('animationDurationMs'), isFalse);
    expect(dataOf(provider)['transitionDuration'], 600);
    expect(provider.canUndo, isFalse,
        reason: 'slider ticks are a widget-local draft');

    duration.onChangeEnd!(900);
    await settle(tester);

    expect(dataOf(provider)['animationDurationMs'], 900);
    expect(dataOf(provider)['transitionDuration'], 900);
    provider.undo();
    final restored = dataOf(provider);
    expect(restored.containsKey('animationDurationMs'), isFalse);
    expect(restored['transitionDuration'], 600);
    expect(provider.canUndo, isFalse,
        reason: 'canonical duration and companion share one transaction');
    expect(tester.takeException(), isNull);
  });
}
