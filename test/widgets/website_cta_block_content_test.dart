import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/website/models/website_action.dart';
import 'package:vinabike_erp/modules/website/models/website_block_surface_style.dart';
import 'package:vinabike_erp/modules/website/models/website_block_type.dart';
import 'package:vinabike_erp/modules/website/models/website_responsive_authoring.dart';
import 'package:vinabike_erp/modules/website/models/website_responsive_projection.dart';
import 'package:vinabike_erp/modules/website/widgets/website_action_button.dart';
import 'package:vinabike_erp/modules/website/widgets/website_block_content_presenters.dart';
import 'package:vinabike_erp/modules/website/widgets/website_cta_block_content.dart';

Widget _host({
  required Map<String, dynamic> data,
  bool previewMode = false,
  void Function(String route)? onNavigate,
  bool Function(String href)? isNavigationEligible,
  WebsiteBlockContentPresenters? presenters,
}) {
  return MaterialApp(
    theme: ThemeData(useMaterial3: true),
    home: Builder(
      builder: (context) => Scaffold(
        body: WebsiteCtaBlockContent(
          data: data,
          surfaceStyle: WebsiteBlockSurfaceStyle.forLogicalWidth(
            data: data,
            logicalWidth: MediaQuery.sizeOf(context).width,
          ),
          primaryColor: const Color(0xFF123456),
          accentColor: const Color(0xFF00A09D),
          previewMode: previewMode,
          headingFont: 'Inter',
          bodyFont: 'Inter',
          onNavigate: onNavigate,
          isNavigationEligible: isNavigationEligible,
          presenters: presenters,
        ),
      ),
    ),
  );
}

Future<void> _setViewport(
  WidgetTester tester, {
  required double width,
  double height = 900,
}) async {
  tester.view
    ..devicePixelRatio = 1
    ..physicalSize = Size(width, height);
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('WebsiteCtaBlockContent', () {
    testWidgets(
      'keeps the canonical CTA geometry at 1440, 834 and 390 widths',
      (tester) async {
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        for (final testCase in <({double width, double horizontal})>[
          (width: 1440, horizontal: 24),
          (width: 834, horizontal: 24),
          (width: 390, horizontal: 16),
        ]) {
          await _setViewport(
            tester,
            width: testCase.width,
          );
          await tester.pumpWidget(
            _host(
              data: const <String, dynamic>{
                'title': 'Pedalea hoy',
                'subtitle':
                    'Una campaña suficientemente larga para validar el ajuste.',
                'buttonText': 'Ver bicicletas',
                'buttonLink': '/productos',
              },
            ),
          );
          await tester.pump();

          final padding = tester.widget<Padding>(
            find.byKey(WebsiteCtaBlockContent.paddingKey),
          );
          expect(
            padding.padding,
            EdgeInsets.symmetric(
              horizontal: testCase.horizontal,
              vertical: 56,
            ),
          );

          final frame = tester.widget<ConstrainedBox>(
            find.byKey(WebsiteCtaBlockContent.contentFrameKey),
          );
          expect(frame.constraints.maxWidth, 800);
          expect(
            tester.getSize(find.byKey(WebsiteCtaBlockContent.rootKey)).width,
            testCase.width,
          );

          final title = tester.widget<Text>(
            find.descendant(
              of: find.byKey(WebsiteCtaBlockContent.titleKey),
              matching: find.text('PEDALEA HOY'),
            ),
          );
          expect(title.style?.fontSize, 24);
          expect(title.style?.fontWeight, FontWeight.w700);
          expect(title.style?.letterSpacing, 1);
          expect(title.textAlign, TextAlign.center);
          expect(tester.takeException(), isNull);
        }
      },
    );

    testWidgets(
      'uses intrinsic auto height and exact height only when it is persisted',
      (tester) async {
        await _setViewport(tester, width: 834);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        const content = <String, dynamic>{
          'title': 'Agenda tu mantención',
          'subtitle': 'Estamos listos para ayudarte.',
          'buttonText': 'Agendar',
          'buttonLink': '/contacto',
        };
        await tester.pumpWidget(_host(data: content));
        final autoHeight =
            tester.getSize(find.byKey(WebsiteCtaBlockContent.rootKey)).height;
        expect(autoHeight, greaterThan(112));
        expect(autoHeight, isNot(420));

        await tester.pumpWidget(
          _host(
            data: const <String, dynamic>{
              ...content,
              'blockHeight': 320.0,
            },
          ),
        );
        expect(
          tester.getSize(find.byKey(WebsiteCtaBlockContent.rootKey)).height,
          320,
        );
        final exactPadding = tester.widget<Padding>(
          find.byKey(WebsiteCtaBlockContent.paddingKey),
        );
        expect(
          exactPadding.padding,
          const EdgeInsets.symmetric(horizontal: 24),
        );

        await tester.pumpWidget(
          _host(
            data: const <String, dynamic>{
              ...content,
              'blockHeight': 0,
            },
          ),
        );
        expect(
          tester.getSize(find.byKey(WebsiteCtaBlockContent.rootKey)).height,
          autoHeight,
        );
      },
    );

    testWidgets(
      'shares background color, overlay and desktop/mobile focal projection',
      (tester) async {
        WebsiteInlineMediaSlot? mediaSlot;
        final presenters = WebsiteBlockContentPresenters(
          media: (context, slot) {
            mediaSlot = slot;
            return const ColoredBox(color: Color(0xFF445566));
          },
        );
        const source = <String, dynamic>{
          'title': 'Campaña',
          'backgroundImage': 'https://example.invalid/campaign.jpg',
          'backgroundImageAltText': 'Ciclista en la montaña',
          'focalPointX': 0.2,
          'focalPointY': 0.3,
          'mobileFocalPointX': 0.1,
          'mobileFocalPointY': 0.1,
          'mobileBgAlignment': 'left',
          'responsive': <String, dynamic>{
            'version': 2,
            'mobile': <String, dynamic>{
              'focalPointX': 0.8,
              'focalPointY': 0.9,
            },
          },
          'overlayColor': '#112233',
          'overlayOpacity': 0.4,
          'style': <String, dynamic>{'backgroundColor': '#ABCDEF'},
        };
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await _setViewport(tester, width: 834);
        await tester.pumpWidget(
          _host(
            data: WebsiteResponsiveBlockProjection.project(
              type: WebsiteBlockType.cta,
              data: source,
              viewport: WebsiteViewport.tablet,
            ),
            presenters: presenters,
          ),
        );
        expect(mediaSlot?.url, source['backgroundImage']);
        expect(mediaSlot?.fit, BoxFit.cover);
        expect(mediaSlot?.alignment, const Alignment(-0.6, -0.4));
        expect(mediaSlot?.semanticLabel, 'Ciclista en la montaña');
        expect(
          tester
              .widget<ColoredBox>(
                find.byKey(WebsiteCtaBlockContent.overlayKey),
              )
              .color,
          const Color(0xFF112233).withValues(alpha: 0.4),
        );

        await _setViewport(tester, width: 390);
        await tester.pumpWidget(
          _host(
            data: WebsiteResponsiveBlockProjection.project(
              type: WebsiteBlockType.cta,
              data: source,
              viewport: WebsiteViewport.mobile,
            ),
            presenters: presenters,
          ),
        );
        expect(mediaSlot?.alignment.x, closeTo(0.6, 0.000001));
        expect(mediaSlot?.alignment.y, closeTo(0.8, 0.000001));

        await tester.pumpWidget(
          _host(
            data: const <String, dynamic>{
              'title': 'Campaña sin imagen',
              'style': <String, dynamic>{
                'backgroundColor': '#ABCDEF',
              },
            },
          ),
        );
        final background = tester.widget<DecoratedBox>(
          find.byKey(WebsiteCtaBlockContent.backgroundKey),
        );
        final decoration = background.decoration as BoxDecoration;
        expect(
          decoration.color,
          Colors.transparent,
          reason: 'the shared WebsiteBlockSurface paints authored color once',
        );
        expect(decoration.image, isNull);
        expect(find.byKey(WebsiteCtaBlockContent.overlayKey), findsNothing);
      },
    );

    testWidgets(
      'keeps a labeled action without href visible but inert and omits '
      'empty labels',
      (tester) async {
        await tester.pumpWidget(
          _host(
            data: const <String, dynamic>{
              'title': 'Conversemos',
              'buttonText': 'Hablar',
              'buttonLink': '',
              'actionVariant': 'outline',
            },
            onNavigate: (_) => fail('An empty action must never navigate.'),
          ),
        );

        expect(find.byType(WebsiteActionButton), findsOneWidget);
        final inertButton = tester.widget<OutlinedButton>(
          find.byType(OutlinedButton),
        );
        expect(inertButton.onPressed, isNull);
        expect(find.text('HABLAR'), findsOneWidget);

        await tester.pumpWidget(
          _host(
            data: const <String, dynamic>{
              'title': 'Conversemos',
              'buttonText': '',
              'buttonLink': '/contacto',
            },
          ),
        );
        expect(find.byType(WebsiteActionButton), findsNothing);
        expect(find.byType(ElevatedButton), findsNothing);
        expect(find.byType(OutlinedButton), findsNothing);
        expect(find.byType(TextButton), findsNothing);
        expect(find.text('CONTÁCTANOS'), findsNothing);

        await tester.pumpWidget(
          _host(
            data: const <String, dynamic>{
              'title': 'Conversemos',
            },
          ),
        );
        expect(find.byType(WebsiteActionButton), findsNothing);
      },
    );

    testWidgets(
      'preserves the action variant; Preview and Public navigate as a '
      'visitor while Edit (presenters) stays inert',
      (tester) async {
        WidgetController.hitTestWarningShouldBeFatal = true;
        addTearDown(() => WidgetController.hitTestWarningShouldBeFatal = false);
        final routes = <String>[];
        const data = <String, dynamic>{
          'title': 'Explora',
          'buttonText': 'Abrir catálogo',
          'buttonLink': '/productos?origen=cta',
          'actionVariant': 'text',
        };

        await tester.pumpWidget(
          _host(
            data: data,
            onNavigate: routes.add,
          ),
        );
        expect(find.byType(TextButton), findsOneWidget);
        await tester.tap(find.byKey(WebsiteCtaBlockContent.actionKey));
        expect(routes, <String>['/productos?origen=cta']);

        // Preview keeps VISITOR navigation semantics: same tap, same route.
        await tester.pumpWidget(
          _host(
            data: data,
            previewMode: true,
            onNavigate: routes.add,
          ),
        );
        await tester.tap(find.byKey(WebsiteCtaBlockContent.actionKey));
        expect(
          routes,
          <String>['/productos?origen=cta', '/productos?origen=cta'],
          reason: 'Preview navigates exactly like Public',
        );

        // Edit is identified by its injected presenters and stays inert.
        await tester.pumpWidget(
          _host(
            data: data,
            onNavigate: routes.add,
            presenters: WebsiteBlockContentPresenters(
              action: (context, slot) => slot.child,
            ),
          ),
        );
        await tester.tap(find.byKey(WebsiteCtaBlockContent.actionKey));
        expect(
          routes,
          <String>['/productos?origen=cta', '/productos?origen=cta'],
          reason: 'Edit (presenters) never navigates',
        );

        await tester.pumpWidget(
          _host(
            data: data,
            onNavigate: routes.add,
            isNavigationEligible: (_) => false,
          ),
        );
        expect(find.byKey(WebsiteCtaBlockContent.actionKey), findsNothing);
      },
    );

    testWidgets(
      'exposes typed title, subtitle, action and media slots to Edit chrome',
      (tester) async {
        final textSlots = <WebsiteInlineTextSlot>[];
        WebsiteInlineActionSlot? actionSlot;
        WebsiteInlineMediaSlot? mediaSlot;
        var navigations = 0;
        final presenters = WebsiteBlockContentPresenters(
          text: (context, slot) {
            textSlots.add(slot);
            return Text(
              slot.displayTransform?.call(slot.value) ?? slot.value,
              style: slot.formatting.applyTo(slot.baseStyle),
              textAlign: slot.textAlign,
            );
          },
          action: (context, slot) {
            actionSlot = slot;
            return slot.child;
          },
          media: (context, slot) {
            mediaSlot = slot;
            return const ColoredBox(color: Color(0xFF334455));
          },
        );

        await tester.pumpWidget(
          _host(
            data: const <String, dynamic>{
              'title': 'Edita sin navegar',
              'subtitle': '',
              'buttonText': 'Configurar',
              'buttonLink': '/destino',
              'actionVariant': 'filled',
              'backgroundImage': 'https://example.invalid/edit.jpg',
            },
            presenters: presenters,
            onNavigate: (_) => navigations += 1,
          ),
        );

        expect(textSlots.map((slot) => slot.id), <String>[
          'cta.title',
          'cta.subtitle',
        ]);
        expect(textSlots.first.valueKeys, <String>['title']);
        expect(
          textSlots.last.valueKeys,
          <String>['subtitle', 'description'],
        );
        expect(textSlots.last.placeholder, isNotEmpty);
        expect(actionSlot?.id, 'cta.action');
        expect(
          actionSlot?.labelKeys,
          <String>['buttonText', 'ctaText'],
        );
        expect(
          actionSlot?.hrefKeys,
          <String>['buttonLink', 'ctaLink'],
        );
        expect(actionSlot?.action.variant, WebsiteActionVariant.filled);
        expect(mediaSlot?.id, 'cta.background');
        expect(
          mediaSlot?.valueKeys,
          <String>['backgroundImage', 'imageUrl'],
        );

        await tester.tap(find.byKey(WebsiteCtaBlockContent.actionKey));
        expect(navigations, 0);
      },
    );
  });
}
