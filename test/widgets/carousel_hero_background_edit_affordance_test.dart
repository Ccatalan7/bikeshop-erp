import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:vinabike_erp/modules/website/models/website_responsive_authoring.dart';
import 'package:vinabike_erp/modules/website/providers/website_edit_mode_provider.dart';
import 'package:vinabike_erp/modules/website/widgets/editable_block_renderer.dart';
import 'package:vinabike_erp/modules/website/widgets/inline_editable_image.dart';
import 'package:vinabike_erp/modules/website/widgets/website_action_button.dart';
import 'package:vinabike_erp/modules/website/widgets/website_block_content_presenters.dart';
import 'package:vinabike_erp/modules/website/widgets/website_block_renderer.dart';
import 'package:vinabike_erp/modules/website/widgets/website_inline_action_editor.dart';

/// Behavioural guard for the interactive-background edit affordance,
/// exercised through the PRODUCTION wiring — not a substitute presenter.
///
/// The regression it pins: in Edit mode the carousel-hero and hero slide
/// backgrounds mounted the full-surface hover picker of
/// [InlineEditableImage] ("Cambiar imagen"), which appeared on mere hover
/// and captured the banner, making the real CTA, arrows, dots and block
/// selection unusable. Backgrounds under interactive content use the
/// [WebsiteInlineMediaEditAffordance.inspectorOnly] policy: the background
/// renders passively with NO picker UI of any kind — the canonical
/// "Cambiar imagen" control lives in the block/slide inspector, asserted in
/// the panel's owning suite
/// (`website_builder_workspace_architecture_test.dart`).
///
/// Every editor-path test here mounts the real
/// `EditableBlockRenderer.build → content presenters → InlineEditableImage`
/// chain, so deleting the productive `editAffordance: slot.editAffordance`
/// forwarding (or a slot's `inspectorOnly` declaration) fails these tests.
/// Simple standalone images keep the classic hover picker.
void main() {
  // Hit-test misses are FATAL for this suite: a tap that does not really
  // reach its target must fail the test, never degrade to a warning. The
  // flag is global, so it is restored after every test.
  setUp(() => WidgetController.hitTestWarningShouldBeFatal = true);
  tearDown(() => WidgetController.hitTestWarningShouldBeFatal = false);

  WebsiteEditModeProvider editProviderFor(
    String blockId,
    String blockType,
    Map<String, dynamic> data,
  ) {
    final provider = WebsiteEditModeProvider()
      ..enterEditMode(
        <Map<String, dynamic>>[
          <String, dynamic>{
            'id': blockId,
            'block_type': blockType,
            'block_data': data,
            'order_index': 0,
          },
        ],
        const <String, dynamic>{},
      );
    return provider;
  }

  Widget hostEditable({
    required WebsiteEditModeProvider provider,
    required String blockId,
    required String blockType,
    required Map<String, dynamic> data,
  }) {
    return MaterialApp(
      home: MediaQuery(
        // Reduced motion keeps slide transitions instantaneous so hit and
        // visibility assertions see exactly one slide at a time.
        data: const MediaQueryData(
          size: Size(1200, 900),
          disableAnimations: true,
        ),
        child: Scaffold(
          body: ChangeNotifierProvider<WebsiteEditModeProvider>.value(
            value: provider,
            child: SizedBox(
              height: 520,
              width: double.infinity,
              child: Builder(
                builder: (context) => EditableBlockRenderer.build(
                  context: context,
                  blockId: blockId,
                  blockType: blockType,
                  data: data,
                  effectiveViewport:
                      WebsiteResponsiveDataCodec.viewportForDocumentWidth(
                    data,
                    1200,
                  ),
                  primaryColor: const Color(0xFF123456),
                  accentColor: const Color(0xFF00A09D),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  const carouselData = <String, dynamic>{
    'autoPlay': false,
    'showArrows': true,
    'showIndicators': true,
    'slides': <Map<String, dynamic>>[
      <String, dynamic>{
        'title': 'Primero',
        'ctaText': 'Ver cámaras',
        'ctaLink': '/productos',
      },
      <String, dynamic>{'title': 'Segundo'},
    ],
  };

  const heroData = <String, dynamic>{
    'title': 'Hero título',
    'subtitle': 'Hero subtítulo',
    'ctaText': 'Ver catálogo',
    'ctaLink': '/productos',
    'imageUrl': null,
    'showOverlay': false,
  };

  Future<TestGesture> hoverAt(WidgetTester tester, Offset position) async {
    final gesture = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
    );
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await tester.pump();
    await gesture.moveTo(position);
    await tester.pump();
    return gesture;
  }

  testWidgets(
      'CAROUSEL through the real editor path: the production wiring delivers '
      'inspectorOnly and the canvas has NO "Cambiar imagen" before or after '
      'hover', (tester) async {
    final provider = editProviderFor('carousel-1', 'carousel', carouselData);
    addTearDown(provider.dispose);
    await tester.pumpWidget(
      hostEditable(
        provider: provider,
        blockId: 'carousel-1',
        blockType: 'carousel',
        data: carouselData,
      ),
    );

    // The REAL presenter chain built the background editor with the slot's
    // policy. If the productive forwarding is removed, this fails first.
    final background = tester.widget<InlineEditableImage>(
      find.byType(InlineEditableImage),
    );
    expect(
      background.editAffordance,
      WebsiteInlineMediaEditAffordance.inspectorOnly,
      reason: 'EditableBlockRenderer must forward slot.editAffordance',
    );

    expect(find.text('Cambiar imagen'), findsNothing);
    expect(find.byKey(InlineEditableImage.hoverOverlayKey), findsNothing);

    final slideCenter = tester.getCenter(
      find.byKey(WebsiteCarouselBlockContent.slideKey(0)),
    );
    await hoverAt(tester, slideCenter);

    expect(find.text('Cambiar imagen'), findsNothing);
    expect(find.byKey(InlineEditableImage.hoverOverlayKey), findsNothing);

    // Tapping the slide background opens nothing and keeps working as BLOCK
    // SELECTION through the real wrapper.
    await tester.tapAt(slideCenter + const Offset(0, 120));
    await tester.pump();
    expect(find.byType(Dialog), findsNothing);
    expect(provider.selectedBlockId, 'carousel-1',
        reason: 'background click selects the block, never opens a picker');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'CAROUSEL through the real editor path: CTA, arrows and dots stay '
      'hittable and functional', (tester) async {
    final provider = editProviderFor('carousel-1', 'carousel', carouselData);
    addTearDown(provider.dispose);
    await tester.pumpWidget(
      hostEditable(
        provider: provider,
        blockId: 'carousel-1',
        blockType: 'carousel',
        data: carouselData,
      ),
    );

    // CTA: in Edit the productive interactive target is the inline action
    // editor's own opaque GestureDetector (the visitor button below it is
    // deliberately IgnorePointer). Tap the REAL target — a fatal hit-test
    // warning fails this test if any capturing layer sat above it — and
    // prove _handleTap's observable effect: the first tap selects the
    // inline editor (selection badge) WITHOUT opening the editor card or
    // any picker.
    expect(find.byType(WebsiteActionButton), findsOneWidget);
    expect(find.byIcon(Icons.edit_outlined), findsNothing);
    await tester.tap(find.byType(WebsiteInlineActionEditor));
    await tester.pump();
    expect(find.byIcon(Icons.edit_outlined), findsOneWidget,
        reason: '_handleTap selected the inline action editor');
    expect(find.text('Editar acción'), findsNothing,
        reason: 'first tap selects; it must not open the editor card');
    expect(find.byType(Dialog), findsNothing);
    expect(tester.takeException(), isNull);

    // Arrows: navigation still works with the edit background mounted.
    await tester.tap(
      find.byKey(WebsiteCarouselBlockContent.nextButtonKey),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('SEGUNDO'), findsOneWidget);

    // Dots: direct slide selection still works.
    await tester.tap(
      find.byKey(WebsiteCarouselBlockContent.indicatorKey(0)),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('PRIMERO'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'HERO through the real editor path: passive background, no '
      '"Cambiar imagen" before or after hover, CTA hittable', (tester) async {
    final provider = editProviderFor('hero-1', 'hero', heroData);
    addTearDown(provider.dispose);
    await tester.pumpWidget(
      hostEditable(
        provider: provider,
        blockId: 'hero-1',
        blockType: 'hero',
        data: heroData,
      ),
    );

    final background = tester.widget<InlineEditableImage>(
      find.byType(InlineEditableImage),
    );
    expect(
      background.editAffordance,
      WebsiteInlineMediaEditAffordance.inspectorOnly,
      reason: 'the hero background slot declares inspectorOnly and the real '
          'presenter chain must deliver it',
    );

    expect(find.text('Cambiar imagen'), findsNothing);
    expect(find.byKey(InlineEditableImage.hoverOverlayKey), findsNothing);

    final heroCenter = tester.getCenter(find.byType(InlineEditableImage));
    await hoverAt(tester, heroCenter);

    expect(find.text('Cambiar imagen'), findsNothing);
    expect(find.byKey(InlineEditableImage.hoverOverlayKey), findsNothing);

    // The hero CTA keeps its own full hit surface over the passive
    // background: tap the REAL productive target (the inline action
    // editor's opaque GestureDetector; the visitor button below is
    // IgnorePointer by design) under fatal hit-test warnings, and prove
    // _handleTap's observable selection effect.
    expect(find.byType(WebsiteActionButton), findsOneWidget);
    expect(find.byIcon(Icons.edit_outlined), findsNothing);
    await tester.tap(find.byType(WebsiteInlineActionEditor));
    await tester.pump();
    expect(find.byIcon(Icons.edit_outlined), findsOneWidget,
        reason: '_handleTap selected the inline action editor');
    expect(find.text('Editar acción'), findsNothing,
        reason: 'first tap selects; it must not open the editor card');
    expect(find.byType(Dialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'simple images keep the classic hover picker (the policy is opt-in)',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 400,
              height: 300,
              child: InlineEditableImage(
                isEditMode: true,
                placeholder: Container(color: const Color(0xFFEEEEEE)),
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.byKey(InlineEditableImage.hoverOverlayKey), findsNothing);
    expect(find.text('Cambiar imagen'), findsNothing);

    await hoverAt(
      tester,
      tester.getCenter(find.byType(InlineEditableImage)),
    );

    expect(find.byKey(InlineEditableImage.hoverOverlayKey), findsOneWidget);
    expect(find.text('Cambiar imagen'), findsOneWidget);
  });
}
