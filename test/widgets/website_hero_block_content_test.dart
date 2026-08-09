import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/website/models/website_action.dart';
import 'package:vinabike_erp/modules/website/models/website_block_surface_style.dart';
import 'package:vinabike_erp/modules/website/widgets/website_action_button.dart';
import 'package:vinabike_erp/modules/website/widgets/website_block_content_presenters.dart';
import 'package:vinabike_erp/modules/website/widgets/website_hero_block_content.dart';

Widget _host({
  required double width,
  required double viewportHeight,
  required Map<String, dynamic> data,
  bool previewMode = false,
  void Function(String route)? onNavigate,
  bool Function(String href)? isNavigationEligible,
  WebsiteBlockContentPresenters? presenters,
}) {
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(size: Size(width, viewportHeight)),
      child: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: width,
            child: WebsiteHeroBlockContent(
              data: data,
              surfaceStyle: WebsiteBlockSurfaceStyle.forLogicalWidth(
                data: data,
                logicalWidth: width,
              ),
              primaryColor: const Color(0xFF143D59),
              accentColor: const Color(0xFFF4B41A),
              previewMode: previewMode,
              onNavigate: onNavigate,
              isNavigationEligible: isNavigationEligible,
              presenters: presenters,
            ),
          ),
        ),
      ),
    ),
  );
}

Future<void> _pumpHero(
  WidgetTester tester, {
  required double width,
  required double viewportHeight,
  required Map<String, dynamic> data,
  bool previewMode = false,
  void Function(String route)? onNavigate,
  bool Function(String href)? isNavigationEligible,
  WebsiteBlockContentPresenters? presenters,
}) async {
  await tester.binding.setSurfaceSize(Size(width, viewportHeight));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    _host(
      width: width,
      viewportHeight: viewportHeight,
      data: data,
      previewMode: previewMode,
      onNavigate: onNavigate,
      isNavigationEligible: isNavigationEligible,
      presenters: presenters,
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('keeps canonical desktop/mobile geometry and content alignment',
      (tester) async {
    await _pumpHero(
      tester,
      width: 1200,
      viewportHeight: 900,
      data: const <String, dynamic>{
        'title': 'Taller Viñabike',
        'subtitle': 'Servicio técnico especializado',
        'alignment': 'left',
      },
    );

    expect(
      tester.getSize(
        find.byKey(WebsiteHeroBlockContent.rootKey),
      ),
      const Size(1200, 520),
    );
    expect(
      tester
          .widget<Align>(
            find.byKey(WebsiteHeroBlockContent.contentKey),
          )
          .alignment,
      Alignment.centerLeft,
    );
    expect(find.text('TALLER VIÑABIKE'), findsOneWidget);
    expect(find.text('Servicio técnico especializado'), findsOneWidget);

    await _pumpHero(
      tester,
      width: 390,
      viewportHeight: 1000,
      data: const <String, dynamic>{
        'title': 'Taller Viñabike',
        'alignment': 'right',
      },
    );

    expect(
      tester.getSize(
        find.byKey(WebsiteHeroBlockContent.rootKey),
      ),
      const Size(390, 420),
    );
    expect(
      tester
          .widget<Align>(
            find.byKey(WebsiteHeroBlockContent.contentKey),
          )
          .alignment,
      Alignment.centerRight,
    );

    await _pumpHero(
      tester,
      width: 390,
      viewportHeight: 1000,
      data: const <String, dynamic>{
        'title': 'Pantalla completa',
        'isFullScreen': true,
      },
    );
    expect(
      tester
          .getSize(
            find.byKey(WebsiteHeroBlockContent.rootKey),
          )
          .height,
      800,
    );
  });

  testWidgets(
      'consumes canonical focal projection despite conflicting legacy aliases',
      (tester) async {
    WebsiteInlineMediaSlot? capturedMedia;
    await _pumpHero(
      tester,
      width: 390,
      viewportHeight: 900,
      data: const <String, dynamic>{
        'title': 'Campaña',
        'backgroundImage': 'https://cdn.example.test/hero.webp',
        'imageAltText': 'Bicicleta de montaña en el taller',
        'focalPointX': 0.25,
        'focalPointY': 0.75,
        'mobileFocalPointX': 0.9,
        'mobileFocalPointY': 0.1,
        'mobileBgAlignment': 'right',
        'showOverlay': true,
        'overlayOpacity': 0.4,
        'overlayColor': '#112233',
      },
      presenters: WebsiteBlockContentPresenters(
        media: (context, slot) {
          capturedMedia = slot;
          return const ColoredBox(color: Color(0xFF1A1A1A));
        },
      ),
    );

    expect(capturedMedia, isNotNull);
    expect(
      capturedMedia!.url,
      'https://cdn.example.test/hero.webp',
    );
    expect(
      capturedMedia!.valueKeys,
      const <String>['imageUrl', 'backgroundImage'],
    );
    expect(capturedMedia!.alignment, const Alignment(-0.5, 0.5));
    expect(
      capturedMedia!.semanticLabel,
      'Bicicleta de montaña en el taller',
    );
    final backgroundSemantics = tester.widget<Semantics>(
      find.byKey(WebsiteHeroBlockContent.backgroundKey),
    );
    expect(
      backgroundSemantics.properties.label,
      'Bicicleta de montaña en el taller',
    );
    expect(backgroundSemantics.properties.image, isTrue);
    expect(
      find.byKey(WebsiteHeroBlockContent.overlayKey),
      findsOneWidget,
    );

    await _pumpHero(
      tester,
      width: 390,
      viewportHeight: 900,
      data: const <String, dynamic>{
        'title': 'Sin overlay',
        'showOverlay': false,
      },
    );
    expect(
      find.byKey(WebsiteHeroBlockContent.overlayKey),
      findsNothing,
    );
  });

  testWidgets('keeps authored CTA only and never invents a destination',
      (tester) async {
    await _pumpHero(
      tester,
      width: 900,
      viewportHeight: 800,
      data: const <String, dynamic>{'title': 'Sin acción'},
    );
    expect(find.byType(WebsiteActionButton), findsNothing);
    expect(find.textContaining('/productos'), findsNothing);

    var navigatedRoute = '';
    await _pumpHero(
      tester,
      width: 900,
      viewportHeight: 800,
      data: const <String, dynamic>{
        'title': 'Acción configurada',
        'ctaText': 'Comprar',
        'ctaLink': '/pagina/campana',
        'actionVariant': 'outline',
      },
      onNavigate: (route) => navigatedRoute = route,
      isNavigationEligible: (_) => true,
    );
    final publicButton = tester.widget<WebsiteActionButton>(
      find.byType(WebsiteActionButton),
    );
    expect(publicButton.action.label, 'Comprar');
    expect(publicButton.action.href, '/pagina/campana');
    expect(publicButton.action.variant, WebsiteActionVariant.outline);
    await tester.tap(find.text('COMPRAR'));
    expect(navigatedRoute, '/pagina/campana');

    await _pumpHero(
      tester,
      width: 900,
      viewportHeight: 800,
      data: const <String, dynamic>{
        'title': 'Destino oculto',
        'buttonText': 'No publicar',
        'buttonLink': '/pagina/oculta',
      },
      isNavigationEligible: (_) => false,
    );
    expect(find.byType(WebsiteActionButton), findsNothing);

    WebsiteInlineActionSlot? capturedAction;
    await _pumpHero(
      tester,
      width: 900,
      viewportHeight: 800,
      data: const <String, dynamic>{
        'title': 'Destino reparable',
        'ctaText': 'Configurar',
        'ctaLink': '',
      },
      isNavigationEligible: (_) => false,
      presenters: WebsiteBlockContentPresenters(
        action: (context, slot) {
          capturedAction = slot;
          return slot.child;
        },
      ),
    );
    expect(capturedAction, isNotNull);
    expect(capturedAction!.action.label, 'Configurar');
    expect(capturedAction!.action.href, isEmpty);
    expect(
      capturedAction!.labelKeys,
      const <String>['ctaText', 'buttonText', 'label'],
    );
    expect(
      capturedAction!.hrefKeys,
      const <String>['ctaLink', 'buttonLink', 'link'],
    );
    expect(find.byType(WebsiteActionButton), findsOneWidget);
  });

  testWidgets('keeps formatted text and presenter bindings on the shared tree',
      (tester) async {
    final slots = <String, WebsiteInlineTextSlot>{};
    await _pumpHero(
      tester,
      width: 1000,
      viewportHeight: 800,
      data: const <String, dynamic>{
        'title': 'Formato persistido',
        'subtitle': 'Subtítulo persistido',
        'alignment': 'left',
        'titleFormatting': <String, dynamic>{
          'fontSize': 31,
          'textAlign': 'right',
          'italic': true,
        },
        'subtitleFormatting': <String, dynamic>{
          'textAlign': 'center',
        },
      },
      presenters: WebsiteBlockContentPresenters(
        text: (context, slot) {
          slots[slot.id] = slot;
          return Text(
            slot.displayTransform?.call(slot.value) ?? slot.value,
            style: slot.formatting.applyTo(slot.baseStyle),
            textAlign: slot.resolvedTextAlign,
          );
        },
      ),
    );

    expect(slots.keys, containsAll(<String>['hero.title', 'hero.subtitle']));
    expect(slots['hero.title']!.valueKeys, const <String>['title']);
    expect(
      slots['hero.title']!.formattingKeys,
      const <String>['titleFormatting'],
    );
    expect(slots['hero.title']!.baseStyle.fontSize, 31);
    expect(slots['hero.title']!.resolvedTextAlign, TextAlign.right);
    expect(
      slots['hero.subtitle']!.formattingKeys,
      const <String>['subtitleFormatting'],
    );
    expect(slots['hero.subtitle']!.resolvedTextAlign, TextAlign.center);
    expect(find.text('FORMATO PERSISTIDO'), findsOneWidget);
  });
}
