import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vinabike_erp/modules/website/models/website_action.dart';
import 'package:vinabike_erp/modules/website/models/website_editor_capability.dart';
import 'package:vinabike_erp/modules/website/models/website_page_models.dart';
import 'package:vinabike_erp/modules/website/models/website_responsive_authoring.dart';
import 'package:vinabike_erp/modules/website/services/website_save_coordinator.dart';
import 'package:vinabike_erp/modules/website/models/website_page_composition.dart';
import 'package:vinabike_erp/modules/website/providers/website_edit_mode_provider.dart';
import 'package:vinabike_erp/modules/website/widgets/deferred_editable_block_renderer.dart';
import 'package:vinabike_erp/modules/website/widgets/inline_editable_image.dart';
import 'package:vinabike_erp/modules/website/widgets/inline_editable_text_v2.dart';
import 'package:vinabike_erp/modules/website/widgets/text_formatting_toolbar.dart';
import 'package:vinabike_erp/modules/website/widgets/website_action_button.dart';
import 'package:vinabike_erp/modules/website/widgets/website_block_renderer.dart';
import 'package:vinabike_erp/modules/website/widgets/website_block_surface.dart';
import 'package:vinabike_erp/modules/website/widgets/website_contact_block_content.dart';
import 'package:vinabike_erp/modules/website/widgets/website_cta_block_content.dart';
import 'package:vinabike_erp/modules/website/widgets/website_faq_block_content.dart';
import 'package:vinabike_erp/modules/website/widgets/website_features_block_content.dart';
import 'package:vinabike_erp/modules/website/widgets/website_gallery_block_content.dart';
import 'package:vinabike_erp/modules/website/widgets/website_hero_block_content.dart';
import 'package:vinabike_erp/modules/website/widgets/website_inline_action_editor.dart';
import 'package:vinabike_erp/modules/website/widgets/website_pricing_block_content.dart';
import 'package:vinabike_erp/modules/website/widgets/website_services_block_content.dart';
import 'package:vinabike_erp/modules/website/widgets/website_stats_block_content.dart';
import 'package:vinabike_erp/modules/website/widgets/website_team_block_content.dart';
import 'package:vinabike_erp/modules/website/widgets/website_testimonials_block_content.dart';
import 'package:vinabike_erp/public_store/widgets/page_composition.dart';

Map<String, dynamic> _block({
  required String id,
  required String type,
  required int order,
  required Map<String, dynamic> data,
}) {
  return <String, dynamic>{
    'id': id,
    'block_type': type,
    'order_index': order,
    'is_visible': true,
    'block_data': data,
  };
}

String _breakpoint(double width) {
  return WebsiteViewport.fromLogicalWidth(width).wireName;
}

Widget _host({
  required List<Map<String, dynamic>> blocks,
  required WebsitePageCompositionMode mode,
  required double logicalWidth,
  WebsiteEditModeProvider? provider,
}) {
  WebsitePageComposition project(List<Map<String, dynamic>> source) =>
      WebsitePageComposition.project(
        blocks: source,
        mode: mode,
        breakpoint: _breakpoint(logicalWidth),
        logicalWidth: logicalWidth,
      );

  Widget page(WebsitePageComposition composition) => Scaffold(
        body: SingleChildScrollView(
          child: PageComposition(
            composition: composition,
            primaryColor: const Color(0xFF143D59),
            accentColor: const Color(0xFFF4B41A),
            textColor: Colors.black,
            containerPadding: 24,
            onAddBlock: (type, {atIndex}) {},
            onSpacingChanged: (blockId, spacing) {},
            onNavigate: (_) {},
            isNavigationEligible: (_) => true,
          ),
        ),
      );

  final app = MaterialApp(
    home: provider == null
        ? page(project(blocks))
        : Consumer<WebsiteEditModeProvider>(
            builder: (context, live, _) => page(project(live.blocks)),
          ),
  );
  if (provider == null) return app;
  return ChangeNotifierProvider<WebsiteEditModeProvider>.value(
    value: provider,
    child: app,
  );
}

Future<void> _pumpComposition(
  WidgetTester tester, {
  required List<Map<String, dynamic>> blocks,
  required WebsitePageCompositionMode mode,
  WebsiteEditModeProvider? provider,
}) async {
  if (mode == WebsitePageCompositionMode.edit) {
    await tester.runAsync(DeferredEditableBlockRenderer.preload);
  }
  final width = tester.view.physicalSize.width / tester.view.devicePixelRatio;
  await tester.pumpWidget(
    _host(
      blocks: blocks,
      mode: mode,
      logicalWidth: width,
      provider: provider,
    ),
  );
  for (var attempt = 0; attempt < 10; attempt++) {
    await tester.pump(const Duration(milliseconds: 10));
    if (find.byType(CircularProgressIndicator).evaluate().isEmpty) break;
  }
}

Map<String, dynamic> _dataFor(
  WebsiteEditModeProvider provider,
  String blockId,
) {
  final block = provider.blocks.firstWhere((item) => item['id'] == blockId);
  return Map<String, dynamic>.from(block['block_data'] as Map);
}

Map<String, dynamic> _rowFor(List<Map<String, dynamic>> rows, String id) =>
    rows.firstWhere((row) => row['id'] == id);

/// STATEFUL fake persistence for the save round-trip: `replacePageBlocks`
/// persists a DEEP COPY of the rows per page (stamping the server-owned
/// columns) and returns another deep copy as the canonical response, and
/// `readPage` hands out yet another deep copy like a fresh origin read. No
/// in-memory object can travel Edit -> persisted -> reload, so the tests
/// prove real Edit -> Guardar/recargar -> Preview/Public convergence.
WebsiteEditorCapabilitySnapshot _cap(
  String identity,
  String tenant, {
  int epoch = 0,
}) =>
    WebsiteEditorCapabilitySnapshot(
      identity: identity,
      activeTenantId: tenant,
      storefrontTenantId: tenant,
      hasAuthority: true,
      authorityEpoch: epoch,
    );

class _StatefulFakeSaveGateway implements WebsiteSaveGateway {
  int authorityRejections = 0;

  @override
  void Function()? writeGuard;

  @override
  void recordEditorAuthorityRejection(String tenantId) {
    authorityRejections++;
  }

  _StatefulFakeSaveGateway({this.serviceCapability});

  @override
  int identityEpoch = 0;

  /// The SERVICE-side typed capability truth for the target tenant.
  WebsiteEditorCapabilitySnapshot? serviceCapability;

  @override
  WebsiteEditorCapabilitySnapshot? currentCapability(String tenantId) =>
      serviceCapability;

  final Map<String, List<Map<String, dynamic>>> _pages = {};
  int replaceCalls = 0;
  int readCalls = 0;
  int resolveCalls = 0;
  int settingsCalls = 0;

  /// When set, saveSettings blocks on it so a test can switch identity
  /// DURING the first gated operation.
  Completer<void>? settingsGate;

  /// When set, saveSettings throws it AFTER the gate (models a server-side
  /// rejection of the mutation).
  Object? settingsError;

  Completer<void>? resolveGate;
  Object? resolveError;
  Completer<void>? navigationGetGate;
  Object? navigationGetError;
  Completer<void>? seoGate;
  Object? seoError;

  static List<Map<String, dynamic>> _deepCopy(
    List<Map<String, dynamic>> blocks,
  ) =>
      (jsonDecode(jsonEncode(blocks)) as List)
          .map((row) => Map<String, dynamic>.from(row as Map))
          .toList(growable: false);

  List<Map<String, dynamic>> readPage(String pageId) {
    readCalls++;
    return _deepCopy(_pages[pageId] ?? const []);
  }

  @override
  bool isTenantProjectionActive(String tenantId) => true;

  @override
  Future<void> saveSettings(
    String tenantId,
    Map<String, String> settings,
  ) async {
    settingsCalls++;
    final gate = settingsGate;
    if (gate != null) await gate.future;
    final error = settingsError;
    if (error != null) throw error;
  }

  @override
  Future<void> savePageSeo({
    required String tenantId,
    required String routeKey,
    required Map<String, String> values,
  }) async {
    final gate = seoGate;
    if (gate != null) await gate.future;
    final error = seoError;
    if (error != null) throw error;
  }

  @override
  Future<WebsiteEditorPageTarget> resolvePage({
    required String tenantId,
    required String? pageId,
    required String? pageSlug,
  }) async {
    resolveCalls++;
    final gate = resolveGate;
    if (gate != null) await gate.future;
    final error = resolveError;
    if (error != null) throw error;
    return WebsiteEditorPageTarget(
      storagePageId: pageId!,
      editorPageId: pageId,
      pageSlug: pageSlug,
    );
  }

  @override
  Future<List<Map<String, dynamic>>> replacePageBlocks({
    required String tenantId,
    required String pageId,
    required List<Map<String, dynamic>> blocks,
  }) async {
    replaceCalls++;
    final persisted = _deepCopy(blocks)
        .map((row) => <String, dynamic>{
              ...row,
              'tenant_id': tenantId,
              'page_id': pageId,
            })
        .toList(growable: false);
    _pages[pageId] = persisted;
    return _deepCopy(persisted);
  }

  @override
  Future<WebsiteNavigation?> getNavigation({
    required String tenantId,
    required String navigationId,
  }) async {
    final gate = navigationGetGate;
    if (gate != null) await gate.future;
    final error = navigationGetError;
    if (error != null) throw error;
    return null;
  }

  @override
  Future<void> updateNavigation({
    required String tenantId,
    required WebsiteNavigation navigation,
  }) async {}

  @override
  Future<void> deleteNavigation({
    required String tenantId,
    required String navigationId,
  }) async {}

  @override
  Future<void> upsertNavigationCreate({
    required String tenantId,
    required String persistedId,
    required WebsiteNavigation navigation,
  }) async {}

  @override
  Future<void> reorderNavigation({
    required String tenantId,
    required List<String> orderedIds,
  }) async {}
}

void main() {
  testWidgets(
    'converged families keep shared root geometry in Edit and Preview',
    (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final cases = <({
        String type,
        Map<String, dynamic> data,
        Key rootKey,
      })>[
        (
          type: 'hero',
          data: const <String, dynamic>{
            'title': 'Campaña',
            'subtitle': 'Contenido compartido',
            'ctaText': 'Conocer',
            'ctaLink': '/campana',
          },
          rootKey: WebsiteHeroBlockContent.rootKey,
        ),
        (
          type: 'carousel',
          data: const <String, dynamic>{
            'slides': <Map<String, dynamic>>[
              <String, dynamic>{
                'title': 'Primera campaña',
                'subtitle': 'Contenido compartido',
                'ctaText': 'Conocer',
                'ctaLink': '/campana',
              },
              <String, dynamic>{
                'title': 'Segunda campaña',
                'subtitle': 'Otro contenido',
              },
            ],
            'autoPlay': false,
          },
          rootKey: WebsiteCarouselBlockContent.rootKey,
        ),
        (
          type: 'about',
          data: const <String, dynamic>{
            'title': 'Nuestra historia',
            'content':
                'Un taller cercano con experiencia real sobre bicicletas.',
            'imageUrl': 'https://invalid.local/about.jpg',
            'imagePosition': 'left',
          },
          rootKey: const ValueKey<String>('website-about-content-root'),
        ),
        (
          type: 'cta',
          data: const <String, dynamic>{
            'title': 'Agenda tu mantención',
            'subtitle': 'Reserva una hora con el taller.',
            'buttonText': 'Agendar',
            'buttonLink': '/contacto',
            'actionVariant': 'outline',
          },
          rootKey: WebsiteCtaBlockContent.rootKey,
        ),
        (
          type: 'contact',
          data: const <String, dynamic>{
            'title': 'Contáctanos',
            'subtitle': 'Respondemos tus dudas.',
            'phone': '+56 9 1111 2222',
            'email': 'hola@example.com',
            'address': 'Viña del Mar',
            'showForm': true,
            'showMap': true,
            'mapUrl': '/mapa',
          },
          rootKey: WebsiteContactBlockContent.frameKey,
        ),
        (
          type: 'features',
          data: const <String, dynamic>{
            'title': 'Ventajas',
            'features': <Map<String, dynamic>>[
              <String, dynamic>{
                'title': 'Diagnóstico',
                'description': 'Antes de intervenir.',
              },
            ],
          },
          rootKey: WebsiteFeaturesBlockContent.rootKey,
        ),
        (
          type: 'services',
          data: const <String, dynamic>{
            'title': 'Servicios',
            'services': <Map<String, dynamic>>[
              <String, dynamic>{
                'title': 'Mantención',
                'description': 'Servicio programado.',
              },
            ],
          },
          rootKey: WebsiteServicesBlockContent.rootKey,
        ),
        (
          type: 'faq',
          data: const <String, dynamic>{
            'title': 'Preguntas',
            'items': <Map<String, dynamic>>[
              <String, dynamic>{
                'question': '¿Cuánto demora?',
                'answer': 'Depende del diagnóstico.',
              },
            ],
          },
          rootKey: WebsiteFaqBlockContent.rootKey,
        ),
        (
          type: 'testimonials',
          data: const <String, dynamic>{
            'title': 'Testimonios',
            'testimonials': <Map<String, dynamic>>[
              <String, dynamic>{
                'name': 'Carolina',
                'comment': 'Excelente servicio.',
                'rating': 5,
              },
            ],
          },
          rootKey: WebsiteTestimonialsBlockContent.rootKey,
        ),
        (
          type: 'pricing',
          data: const <String, dynamic>{
            'title': 'Planes',
            'plans': <Map<String, dynamic>>[
              <String, dynamic>{
                'name': 'Mantención',
                'price': '29.990',
                'features': <String>['Frenos'],
                'ctaText': 'Reservar',
                'ctaLink': '/reservar',
              },
            ],
          },
          rootKey: WebsitePricingBlockContent.rootKey,
        ),
        (
          type: 'stats',
          data: const <String, dynamic>{
            'title': 'Resultados',
            'metrics': <Map<String, dynamic>>[
              <String, dynamic>{
                'value': '1200',
                'suffix': '+',
                'label': 'Bicicletas',
              },
            ],
          },
          rootKey: WebsiteStatsBlockContent.rootKey,
        ),
        (
          type: 'team',
          data: const <String, dynamic>{
            'title': 'Equipo',
            'members': <Map<String, dynamic>>[
              <String, dynamic>{
                'name': 'Andrea',
                'role': 'Mecánica',
                'avatarUrl': '',
              },
            ],
          },
          rootKey: WebsiteTeamBlockContent.rootKey,
        ),
        (
          type: 'gallery',
          data: const <String, dynamic>{
            'title': 'Galería',
            'images': <Map<String, dynamic>>[
              <String, dynamic>{
                'imageUrl': '',
                'caption': 'Taller',
              },
            ],
          },
          rootKey: WebsiteGalleryBlockContent.rootKey,
        ),
      ];

      for (final width in <double>[1440, 834, 390]) {
        await tester.binding.setSurfaceSize(Size(width, 1600));
        for (final testCase in cases) {
          final blocks = <Map<String, dynamic>>[
            _block(
              id: testCase.type,
              type: testCase.type,
              order: 0,
              data: testCase.data,
            ),
          ];
          final provider = WebsiteEditModeProvider()
            ..enterEditMode(
              blocks,
              const <String, dynamic>{},
              pageId: 'page-${testCase.type}',
              pageSlug: testCase.type,
            );

          await _pumpComposition(
            tester,
            blocks: provider.blocks,
            mode: WebsitePageCompositionMode.edit,
            provider: provider,
          );
          final editRect = tester.getRect(find.byKey(testCase.rootKey));
          Size? editActionSize;
          String? pricingGeometryDetail;
          if (testCase.type == 'pricing') {
            final action = find.byKey(WebsitePricingBlockContent.actionKey(0));
            expect(action, findsOneWidget);
            editActionSize = tester.getSize(action);
            final name = find.byKey(
              const ValueKey<String>(
                'website-inline-text-pricing-pricing.plan.0.name',
              ),
            );
            final price = find.byKey(
              const ValueKey<String>(
                'website-inline-text-pricing-pricing.plan.0.price',
              ),
            );
            pricingGeometryDetail = 'edit name=${tester.getRect(name)} '
                'price=${tester.getRect(price)} '
                'action=${tester.getRect(action)}';
          }

          await _pumpComposition(
            tester,
            blocks: provider.blocks,
            mode: WebsitePageCompositionMode.preview,
          );
          final previewRect = tester.getRect(find.byKey(testCase.rootKey));
          Size? previewActionSize;
          if (testCase.type == 'pricing') {
            final action = find.byKey(WebsitePricingBlockContent.actionKey(0));
            expect(action, findsOneWidget);
            previewActionSize = tester.getSize(action);
            pricingGeometryDetail = '$pricingGeometryDetail; preview '
                'name=${tester.getRect(find.text('Mantención'))} '
                'price=${tester.getRect(find.text('CLP 29.990'))} '
                'action=${tester.getRect(action)}';
          }

          expect(
            editRect.size.width,
            closeTo(previewRect.size.width, 0.01),
            reason: '${testCase.type} width at $width',
          );
          expect(
            editRect.size.height,
            closeTo(previewRect.size.height, 0.01),
            reason: '${testCase.type} height at $width; '
                'action edit=$editActionSize preview=$previewActionSize; '
                '$pricingGeometryDetail',
          );
          provider.dispose();
        }
      }
    },
  );

  testWidgets(
    'shared presenters round-trip Edit through saved reload to Preview/Public',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 1800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final initialBlocks = <Map<String, dynamic>>[
        _block(
          id: 'about',
          type: 'about',
          order: 0,
          data: const <String, dynamic>{
            'title': 'Historia original',
            'content': 'Contenido original',
            'description': 'Contenido original',
            'imageUrl': '',
            'image': '',
          },
        ),
        _block(
          id: 'cta',
          type: 'cta',
          order: 1,
          data: const <String, dynamic>{
            'title': 'Acción original',
            'subtitle': 'Subtítulo original',
            'description': 'Subtítulo original',
            'buttonText': 'Ir',
            'ctaText': 'Ir',
            'buttonLink': '/original',
            'ctaLink': '/original',
            'actionVariant': 'filled',
            'actions': <Map<String, dynamic>>[
              <String, dynamic>{
                'type': 'navigate',
                'label': 'Ir',
                'to': '/original',
                'variant': 'filled',
              },
            ],
          },
        ),
        _block(
          id: 'contact',
          type: 'contact',
          order: 2,
          data: const <String, dynamic>{
            'title': 'Contacto original',
            'subtitle': 'Subtítulo de contacto',
            'showForm': false,
            'showMap': false,
          },
        ),
      ];
      final provider = WebsiteEditModeProvider()
        ..adoptEditorEntryLease(
          0,
          const WebsiteEditorCapabilitySnapshot(
            identity: 'save-user',
            activeTenantId: 'tenant-round-trip',
            storefrontTenantId: 'tenant-round-trip',
            hasAuthority: true,
          ),
        )
        ..enterEditMode(
          initialBlocks,
          const <String, dynamic>{},
          pageId: 'page-round-trip',
          pageSlug: 'round-trip',
        );
      // Destroyed explicitly mid-test (never reused after the save).

      await _pumpComposition(
        tester,
        blocks: provider.blocks,
        mode: WebsitePageCompositionMode.edit,
        provider: provider,
      );

      // Production selects the block on pointer-down before its inline
      // presenter handles the edit. The exact mutation lease deliberately
      // rejects a callback captured without that owner selection.
      provider.selectBlock('about');
      await tester.pump();
      tester
          .widget<InlineEditableTextV2>(
            find.byKey(
              const ValueKey<String>(
                'website-inline-text-about-about-content',
              ),
            ),
          )
          .onTextChanged!
          .call('Historia guardada');
      await tester.pump();
      tester
          .widget<InlineEditableImage>(
            find.byKey(
              const ValueKey<String>(
                'website-inline-media-about-about-image',
              ),
            ),
          )
          .onChanged!
          .call('https://invalid.local/saved-about.jpg');
      await tester.pump();

      provider.selectBlock('cta');
      await tester.pump();
      tester
          .widget<InlineEditableTextV2>(
            find.byKey(
              const ValueKey<String>('website-inline-text-cta-cta.subtitle'),
            ),
          )
          .onTextChanged!
          .call('Subtítulo guardado');
      await tester.pump();
      tester
          .widget<WebsiteInlineActionEditor>(
            find.byKey(
              const ValueKey<String>('website-inline-action-cta-cta.action'),
            ),
          )
          .onChanged
          .call(
            const WebsiteActionValue(
              label: 'Reservar',
              href: '/reservar',
              variant: WebsiteActionVariant.outline,
            ),
          );
      await tester.pump();

      provider.selectBlock('contact');
      await tester.pump();
      tester
          .widget<InlineEditableTextV2>(
            find.byKey(
              const ValueKey<String>(
                'website-inline-text-contact-contact-title',
              ),
            ),
          )
          .onTextChanged!
          .call('Contacto guardado');
      await tester.pump();

      final aboutData = _dataFor(provider, 'about');
      expect(aboutData['content'], 'Historia guardada');
      expect(aboutData['description'], 'Historia guardada');
      expect(
        aboutData['imageUrl'],
        'https://invalid.local/saved-about.jpg',
      );
      expect(aboutData['image'], aboutData['imageUrl']);

      final ctaData = _dataFor(provider, 'cta');
      expect(ctaData['subtitle'], 'Subtítulo guardado');
      expect(ctaData['description'], 'Subtítulo guardado');
      expect(ctaData['buttonText'], 'Reservar');
      expect(ctaData['ctaText'], 'Reservar');
      expect(ctaData['buttonLink'], '/reservar');
      expect(ctaData['ctaLink'], '/reservar');
      expect(ctaData['actionVariant'], 'outline');
      final savedAction = Map<String, dynamic>.from(
        (ctaData['actions'] as List).first as Map,
      );
      expect(savedAction['label'], 'Reservar');
      expect(savedAction['to'], '/reservar');
      expect(savedAction['variant'], 'outline');

      expect(_dataFor(provider, 'contact')['title'], 'Contacto guardado');

      // REAL round-trip: the save coordinator persists through a STATEFUL
      // deep-copy gateway and applies the CANONICAL response rows.
      final gateway = _StatefulFakeSaveGateway(
        serviceCapability: _cap('save-user', 'tenant-round-trip'),
      );
      final coordinator = WebsiteSaveCoordinator(gateway);
      final attemptedBlocks = provider.blocks;
      final saveResult = await coordinator.save(
        tenantId: 'tenant-round-trip',
        document: provider,
      );
      expect(gateway.replaceCalls, 1);
      expect(saveResult.appliedToActiveDocument, isTrue);
      expect(provider.hasUnsavedChanges, isFalse);

      // The reload is a NEW deep copy read into a NEW provider: no object is
      // shared with the editing session.
      final reloadedRows = gateway.readPage('page-round-trip');
      expect(identical(reloadedRows, attemptedBlocks), isFalse);
      expect(
        identical(
          _rowFor(reloadedRows, 'about')['block_data'],
          _rowFor(attemptedBlocks, 'about')['block_data'],
        ),
        isFalse,
        reason: 'Persisted rows must be deep copies, never shared maps.',
      );
      expect(
        identical(
          _rowFor(reloadedRows, 'about')['block_data'],
          _rowFor(provider.blocks, 'about')['block_data'],
        ),
        isFalse,
        reason: 'The reload must not alias the acknowledged document either.',
      );

      final reloaded = WebsiteEditModeProvider()
        ..enterPreviewMode(
          reloadedRows,
          const <String, dynamic>{},
          pageId: 'page-round-trip',
          pageSlug: 'round-trip',
        );
      addTearDown(reloaded.dispose);
      expect(_dataFor(reloaded, 'about')['content'], 'Historia guardada');
      expect(
        _dataFor(reloaded, 'about')['imageUrl'],
        'https://invalid.local/saved-about.jpg',
      );
      expect(
        _dataFor(reloaded, 'about')['image'],
        _dataFor(reloaded, 'about')['imageUrl'],
      );
      final reloadedCta = _dataFor(reloaded, 'cta');
      expect(reloadedCta['buttonText'], 'Reservar');
      expect(reloadedCta['ctaText'], 'Reservar');
      expect(reloadedCta['buttonLink'], '/reservar');
      expect(reloadedCta['ctaLink'], '/reservar');
      expect(reloadedCta['actionVariant'], 'outline');

      // The editing session is DESTROYED before Preview/Public render: they
      // may only see persisted rows.
      provider.dispose();
      await _pumpComposition(
        tester,
        blocks: reloaded.blocks,
        mode: WebsitePageCompositionMode.preview,
      );
      expect(find.text('Historia guardada'), findsOneWidget);
      expect(find.text('Subtítulo guardado'), findsOneWidget);
      expect(find.text('Contacto guardado'), findsOneWidget);
      final previewCtaButton = tester.widget<WebsiteActionButton>(
        find.descendant(
          of: find.byKey(WebsiteCtaBlockContent.rootKey),
          matching: find.byType(WebsiteActionButton),
        ),
      );
      expect(previewCtaButton.action.label, 'Reservar');
      expect(previewCtaButton.action.href, '/reservar');
      expect(previewCtaButton.action.variant, WebsiteActionVariant.outline);
      final previewCtaRect =
          tester.getRect(find.byKey(WebsiteCtaBlockContent.rootKey));

      // Public renders from ANOTHER independent origin read: a distinct
      // list AND distinct nested maps (readCalls alone cannot prove it).
      final publicRows = gateway.readPage('page-round-trip');
      expect(gateway.readCalls, 2);
      expect(identical(publicRows, reloadedRows), isFalse);
      expect(
        identical(
          _rowFor(publicRows, 'about')['block_data'],
          _rowFor(reloaded.blocks, 'about')['block_data'],
        ),
        isFalse,
        reason: 'Each origin read must be its own deep copy.',
      );
      expect(_rowFor(publicRows, 'about')['tenant_id'], 'tenant-round-trip');
      expect(_rowFor(publicRows, 'about')['page_id'], 'page-round-trip');
      await _pumpComposition(
        tester,
        blocks: publicRows,
        mode: WebsitePageCompositionMode.public,
      );
      expect(find.text('Historia guardada'), findsOneWidget);
      expect(find.text('Subtítulo guardado'), findsOneWidget);
      expect(find.text('Contacto guardado'), findsOneWidget);
      final publicCtaRect =
          tester.getRect(find.byKey(WebsiteCtaBlockContent.rootKey));
      expect(publicCtaRect, previewCtaRect,
          reason: 'Preview and Public must agree on the saved CTA geometry.');
    },
  );

  testWidgets(
    'Style survives save, fresh reload, Preview and Public without changing '
    'a Button scalar style',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final initialBlocks = <Map<String, dynamic>>[
        _block(
          id: 'styled-button',
          type: 'button',
          order: 0,
          data: const <String, dynamic>{
            'label': 'Abrir catálogo',
            'link': '/productos',
            'style': 'outline',
            'surfaceStyle': <String, dynamic>{
              'backgroundColor': '#FF112233',
              'paddingTop': 40,
              'paddingRight': 30,
              'paddingBottom': 20,
              'paddingLeft': 10,
              'futureSurfaceOwner': <String, dynamic>{'kept': true},
            },
            'responsive': <String, dynamic>{
              'version': 2,
              'mobile': <String, dynamic>{
                'surfacePaddingTop': 8,
                'surfacePaddingLeft': 6,
                'futureMobileOwner': 'kept',
              },
              'tablet': <String, dynamic>{
                'surfacePaddingRight': 18,
                'futureTabletOwner': 'kept',
              },
            },
          },
        ),
      ];
      final provider = WebsiteEditModeProvider()
        ..adoptEditorEntryLease(
          0,
          const WebsiteEditorCapabilitySnapshot(
            identity: 'style-save-user',
            activeTenantId: 'tenant-style-round-trip',
            storefrontTenantId: 'tenant-style-round-trip',
            hasAuthority: true,
          ),
        )
        ..enterEditMode(
          initialBlocks,
          const <String, dynamic>{},
          pageId: 'page-style-round-trip',
          pageSlug: 'style-round-trip',
        );

      await _pumpComposition(
        tester,
        blocks: provider.blocks,
        mode: WebsitePageCompositionMode.edit,
        provider: provider,
      );
      provider.selectBlock('styled-button');
      await tester.pump();
      final lease = provider.captureInlineMutationLease(
        WebsiteInlineManipulationTarget(
          blockId: 'styled-button',
          owner: const WebsiteInlineBlockOwner(),
          viewport: WebsiteViewport.mobile,
          properties: <WebsiteInlineManipulationProperty>[
            WebsiteInlineManipulationProperty(
              canonicalKey: 'surfaceStyle',
              policy: WebsiteResponsivePropertyPolicy.sharedOnly,
            ),
          ],
        ),
      );
      expect(lease, isNotNull);
      final sourceData = Map<String, dynamic>.from(
        lease!.sourceBlock['block_data'] as Map,
      );
      final sourceSurface = Map<String, dynamic>.from(
        sourceData['surfaceStyle'] as Map,
      );
      expect(
        provider.commitInlineMutation(
          lease,
          <String, Object?>{
            'surfaceStyle': <String, dynamic>{
              ...sourceSurface,
              'borderRadius': 12,
            },
          },
        ),
        WebsiteInlineMutationResult.committed,
      );
      await tester.pump();

      final gateway = _StatefulFakeSaveGateway(
        serviceCapability: _cap(
          'style-save-user',
          'tenant-style-round-trip',
        ),
      );
      final result = await WebsiteSaveCoordinator(gateway).save(
        tenantId: 'tenant-style-round-trip',
        document: provider,
      );
      expect(result.appliedToActiveDocument, isTrue);
      expect(gateway.replaceCalls, 1);

      final reloadedRows = gateway.readPage('page-style-round-trip');
      final persistedData = Map<String, dynamic>.from(
        reloadedRows.single['block_data'] as Map,
      );
      expect(persistedData['style'], 'outline');
      final persistedSurface = persistedData['surfaceStyle'] as Map;
      expect(persistedSurface['borderRadius'], 12);
      expect(
        (persistedSurface['futureSurfaceOwner'] as Map)['kept'],
        isTrue,
      );
      final persistedResponsive = persistedData['responsive'] as Map;
      expect(
        (persistedResponsive['mobile'] as Map)['futureMobileOwner'],
        'kept',
      );
      expect(
        (persistedResponsive['tablet'] as Map)['futureTabletOwner'],
        'kept',
      );

      final reloaded = WebsiteEditModeProvider()
        ..enterPreviewMode(
          reloadedRows,
          const <String, dynamic>{},
          pageId: 'page-style-round-trip',
          pageSlug: 'style-round-trip',
        );
      addTearDown(reloaded.dispose);
      provider.dispose();

      for (final (width, expectedPadding) in const <(double, EdgeInsets)>[
        (390, EdgeInsets.fromLTRB(6, 8, 30, 20)),
        (834, EdgeInsets.fromLTRB(10, 40, 18, 20)),
      ]) {
        await tester.binding.setSurfaceSize(Size(width, 1200));
        for (final mode in <WebsitePageCompositionMode>[
          WebsitePageCompositionMode.preview,
          WebsitePageCompositionMode.public,
        ]) {
          final rows = mode == WebsitePageCompositionMode.preview
              ? reloaded.blocks
              : gateway.readPage('page-style-round-trip');
          await _pumpComposition(
            tester,
            blocks: rows,
            mode: mode,
          );
          final surface = tester.widget<Container>(
            find.byKey(WebsiteBlockSurface.fallbackKey),
          );
          final decoration = surface.decoration! as BoxDecoration;
          expect(decoration.color, const Color(0xFF112233));
          expect(decoration.borderRadius, BorderRadius.circular(12));
          expect(
            find.descendant(
              of: find.byKey(WebsiteBlockSurface.fallbackKey),
              matching: find.byWidgetPredicate(
                (widget) =>
                    widget is Padding && widget.padding == expectedPadding,
              ),
            ),
            findsOneWidget,
            reason: '$mode @ $width consumes the saved viewport padding',
          );
          expect(find.text('Abrir catálogo'), findsOneWidget);
          expect(tester.takeException(), isNull);
        }
      }
    },
  );

  testWidgets(
    'nested collections round-trip Edit through saved reload to Preview/Public',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 4000));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final initialBlocks = <Map<String, dynamic>>[
        _block(
          id: 'features',
          type: 'features',
          order: 0,
          data: const <String, dynamic>{
            'title': 'Ventajas',
            'features': <Map<String, dynamic>>[
              <String, dynamic>{
                'id': 'feature-1',
                'title': 'Diagnóstico',
                'description': 'Antes de intervenir.',
              },
            ],
          },
        ),
        _block(
          id: 'services',
          type: 'services',
          order: 1,
          data: const <String, dynamic>{
            'title': 'Servicios',
            'services': <Map<String, dynamic>>[
              <String, dynamic>{
                'id': 'service-1',
                'title': 'Mantención',
                'description': 'Programada.',
              },
            ],
          },
        ),
        _block(
          id: 'faq',
          type: 'faq',
          order: 2,
          data: const <String, dynamic>{
            'title': 'Preguntas',
            'items': <Map<String, dynamic>>[
              <String, dynamic>{
                'id': 'faq-1',
                'question': '¿Cuánto demora?',
                'answer': 'Respuesta original.',
              },
            ],
          },
        ),
        _block(
          id: 'testimonials',
          type: 'testimonials',
          order: 3,
          data: const <String, dynamic>{
            'title': 'Testimonios',
            'testimonials': <Map<String, dynamic>>[
              <String, dynamic>{
                'id': 'testimonial-1',
                'name': 'Carolina',
                'comment': 'Comentario original.',
                'rating': 5,
              },
            ],
          },
        ),
        _block(
          id: 'pricing',
          type: 'pricing',
          order: 4,
          data: const <String, dynamic>{
            'title': 'Planes',
            'plans': <Map<String, dynamic>>[
              <String, dynamic>{
                'id': 'plan-1',
                'name': 'Plan original',
                'price': '29.990',
                'features': <String>['Frenos'],
                'ctaText': 'Reservar',
                'ctaLink': '/reservar',
              },
            ],
          },
        ),
        _block(
          id: 'stats',
          type: 'stats',
          order: 5,
          data: const <String, dynamic>{
            'title': 'Resultados',
            'metrics': <Map<String, dynamic>>[
              <String, dynamic>{
                'id': 'metric-1',
                'value': '1200',
                'suffix': '+',
                'label': 'Bicicletas',
              },
            ],
          },
        ),
        _block(
          id: 'team',
          type: 'team',
          order: 6,
          data: const <String, dynamic>{
            'title': 'Equipo',
            'members': <Map<String, dynamic>>[
              <String, dynamic>{
                'id': 'member-1',
                'name': 'Andrea',
                'role': 'Mecánica',
                'avatarUrl': '',
              },
            ],
          },
        ),
        _block(
          id: 'gallery',
          type: 'gallery',
          order: 7,
          data: const <String, dynamic>{
            'title': 'Galería',
            'images': <Map<String, dynamic>>[
              <String, dynamic>{
                'id': 'image-1',
                'imageUrl': '',
                'caption': 'Taller original',
              },
            ],
          },
        ),
      ];
      final provider = WebsiteEditModeProvider()
        ..adoptEditorEntryLease(
          0,
          const WebsiteEditorCapabilitySnapshot(
            identity: 'save-user',
            activeTenantId: 'tenant-nested-round-trip',
            storefrontTenantId: 'tenant-nested-round-trip',
            hasAuthority: true,
          ),
        )
        ..enterEditMode(
          initialBlocks,
          const <String, dynamic>{},
          pageId: 'page-nested-round-trip',
          pageSlug: 'nested-round-trip',
        );
      // Destroyed explicitly mid-test (never reused after the save).

      await _pumpComposition(
        tester,
        blocks: provider.blocks,
        mode: WebsitePageCompositionMode.edit,
        provider: provider,
      );

      InlineEditableTextV2 inlineText(String blockId, String slotId) {
        return tester.widget<InlineEditableTextV2>(
          find.byKey(
            ValueKey<String>('website-inline-text-$blockId-$slotId'),
            skipOffstage: false,
          ),
        );
      }

      Future<void> selectInlineOwner(String blockId) async {
        provider.selectBlock(blockId);
        await tester.pump();
      }

      await selectInlineOwner('features');
      inlineText('features', 'features.item.0.title')
          .onTextChanged!
          .call('Diagnóstico guardado');
      await tester.pump();
      inlineText('features', 'features.item.0.title')
          .onFormattingChanged!
          .call(const TextFormatting(textAlign: TextAlign.right));
      await tester.pump();
      await selectInlineOwner('services');
      inlineText('services', 'services.item.0.description')
          .onTextChanged!
          .call('Servicio guardado');
      await tester.pump();
      await selectInlineOwner('faq');
      inlineText('faq', 'faq.item.0.question')
          .onTextChanged!
          .call('Pregunta guardada');
      await tester.pump();
      await selectInlineOwner('testimonials');
      inlineText('testimonials', 'testimonials.item.0.comment')
          .onTextChanged!
          .call('Testimonio guardado');
      await tester.pump();
      await selectInlineOwner('pricing');
      inlineText('pricing', 'pricing.plan.0.name')
          .onTextChanged!
          .call('Plan guardado');
      await tester.pump();
      tester
          .widget<WebsiteInlineActionEditor>(
            find.byKey(
              const ValueKey<String>(
                'website-inline-action-pricing-pricing.plan.0.action',
              ),
            ),
          )
          .onChanged
          .call(
            const WebsiteActionValue(
              label: 'Comprar',
              href: '/comprar',
              variant: WebsiteActionVariant.outline,
            ),
          );
      await tester.pump();
      await selectInlineOwner('stats');
      inlineText('stats', 'stats.metric.0.value').onTextChanged!.call('1500');
      await tester.pump();
      await selectInlineOwner('team');
      inlineText('team', 'team.member.0.name')
          .onTextChanged!
          .call('Andrea guardada');
      await tester.pump();
      tester
          .widget<InlineEditableImage>(
            find.byKey(
              const ValueKey<String>(
                'website-inline-media-team-team.member.0.avatar',
              ),
            ),
          )
          .onChanged!
          .call('https://invalid.local/team.jpg');
      await tester.pump();
      await selectInlineOwner('gallery');
      inlineText('gallery', 'gallery.image.0.caption')
          .onTextChanged!
          .call('Taller guardado');
      await tester.pump();
      tester
          .widget<InlineEditableImage>(
            find.byKey(
              const ValueKey<String>(
                'website-inline-media-gallery-gallery.image.0.media',
              ),
            ),
          )
          .onChanged!
          .call('https://invalid.local/gallery.jpg');
      await tester.pump();

      Map<String, dynamic> firstItem(String blockId, String collectionKey) {
        return Map<String, dynamic>.from(
          (_dataFor(provider, blockId)[collectionKey] as List).first as Map,
        );
      }

      expect(
        firstItem('features', 'features')['title'],
        'Diagnóstico guardado',
      );
      expect(
        firstItem('features', 'features')['titleFormatting'],
        <String, dynamic>{'textAlign': 'right'},
      );
      expect(
        firstItem('services', 'services')['description'],
        'Servicio guardado',
      );
      expect(firstItem('faq', 'items')['question'], 'Pregunta guardada');
      expect(
        firstItem('testimonials', 'testimonials')['comment'],
        'Testimonio guardado',
      );
      expect(firstItem('pricing', 'plans')['name'], 'Plan guardado');
      expect(firstItem('pricing', 'plans')['ctaText'], 'Comprar');
      expect(firstItem('pricing', 'plans')['ctaLink'], '/comprar');
      expect(firstItem('stats', 'metrics')['value'], '1500');
      expect(firstItem('team', 'members')['name'], 'Andrea guardada');
      expect(
        firstItem('team', 'members')['avatarUrl'],
        'https://invalid.local/team.jpg',
      );
      expect(
        firstItem('gallery', 'images')['caption'],
        'Taller guardado',
      );
      expect(
        firstItem('gallery', 'images')['imageUrl'],
        'https://invalid.local/gallery.jpg',
      );

      // REAL round-trip through the save coordinator + stateful deep-copy
      // gateway; the editing session is destroyed before Preview renders.
      final gateway = _StatefulFakeSaveGateway(
        serviceCapability: _cap('save-user', 'tenant-nested-round-trip'),
      );
      final coordinator = WebsiteSaveCoordinator(gateway);
      final attemptedBlocks = provider.blocks;
      final saveResult = await coordinator.save(
        tenantId: 'tenant-nested-round-trip',
        document: provider,
      );
      expect(gateway.replaceCalls, 1);
      expect(saveResult.appliedToActiveDocument, isTrue);
      expect(provider.hasUnsavedChanges, isFalse);

      final reloadedRows = gateway.readPage('page-nested-round-trip');
      expect(identical(reloadedRows, attemptedBlocks), isFalse);
      expect(
        identical(
          _rowFor(reloadedRows, 'features')['block_data'],
          _rowFor(attemptedBlocks, 'features')['block_data'],
        ),
        isFalse,
        reason: 'Persisted rows must be deep copies, never shared maps.',
      );

      final reloaded = WebsiteEditModeProvider()
        ..enterPreviewMode(
          reloadedRows,
          const <String, dynamic>{},
          pageId: 'page-nested-round-trip',
          pageSlug: 'nested-round-trip',
        );
      addTearDown(reloaded.dispose);

      // The editing session is DESTROYED before Preview/Public render.
      provider.dispose();
      await _pumpComposition(
        tester,
        blocks: reloaded.blocks,
        mode: WebsitePageCompositionMode.preview,
      );
      for (final savedText in <String>[
        'Diagnóstico guardado',
        'Servicio guardado',
        'Pregunta guardada',
        'Testimonio guardado',
        'Plan guardado',
        '1500',
        'Andrea guardada',
        'Taller guardado',
      ]) {
        expect(find.text(savedText), findsOneWidget, reason: savedText);
      }
      expect(
        tester.widget<Text>(find.text('Diagnóstico guardado')).textAlign,
        TextAlign.right,
      );
      final previewPricingAction = tester.widget<WebsiteActionButton>(
        find.descendant(
          of: find.byKey(WebsitePricingBlockContent.rootKey),
          matching: find.byType(WebsiteActionButton),
        ),
      );
      expect(previewPricingAction.action.label, 'Comprar');
      expect(previewPricingAction.action.href, '/comprar');

      final previewPricingRect =
          tester.getRect(find.byKey(WebsitePricingBlockContent.rootKey));

      // Public renders from ANOTHER independent origin read: a distinct
      // list AND distinct nested maps (readCalls alone cannot prove it).
      final publicRows = gateway.readPage('page-nested-round-trip');
      expect(gateway.readCalls, 2);
      expect(identical(publicRows, reloadedRows), isFalse);
      expect(
        identical(
          _rowFor(publicRows, 'features')['block_data'],
          _rowFor(reloaded.blocks, 'features')['block_data'],
        ),
        isFalse,
        reason: 'Each origin read must be its own deep copy.',
      );
      expect(
        _rowFor(publicRows, 'features')['tenant_id'],
        'tenant-nested-round-trip',
      );
      expect(
        _rowFor(publicRows, 'features')['page_id'],
        'page-nested-round-trip',
      );
      await _pumpComposition(
        tester,
        blocks: publicRows,
        mode: WebsitePageCompositionMode.public,
      );
      expect(find.text('Diagnóstico guardado'), findsOneWidget);
      expect(find.text('Taller guardado'), findsOneWidget);
      expect(find.text('Comprar'), findsOneWidget);
      expect(
        tester.widget<Text>(find.text('Diagnóstico guardado')).textAlign,
        TextAlign.right,
        reason: 'Persisted formatting must survive the reload into Public.',
      );
      expect(
        tester.getRect(find.byKey(WebsitePricingBlockContent.rootKey)),
        previewPricingRect,
        reason: 'Preview and Public must agree on saved pricing geometry.',
      );
    },
  );

  testWidgets(
    'the REAL routed flow saves: granted lease -> URL command -> '
    'activatePageDocument -> edit -> coordinator.save',
    (tester) async {
      final provider = WebsiteEditModeProvider();
      addTearDown(provider.dispose);
      provider.adoptEditorEntryLease(
        0,
        const WebsiteEditorCapabilitySnapshot(
          identity: 'user-a',
          activeTenantId: 'tenant-a',
          storefrontTenantId: 'tenant-a',
          hasAuthority: true,
        ),
      );
      // URL entry command opens the session WITHOUT a document; the routed
      // Dynamic/Policy consumer then binds through activatePageDocument —
      // never through openEditorDocument.
      provider.applyRouteModeCommand(WebsiteEditorMode.edit);
      expect(provider.mode, WebsiteEditorMode.edit);
      provider.activatePageDocument(
        const [
          {
            'id': 'block-1',
            'block_type': 'about',
            'block_data': {'title': 'Original'},
            'order_index': 0,
            'is_visible': true,
          },
        ],
        const <String, dynamic>{},
        pageId: 'page-a',
        pageSlug: 'page-a',
      );
      await tester.pump();
      provider.updateBlockData('block-1', 'title', 'Draft routed');

      final gateway = _StatefulFakeSaveGateway(
        serviceCapability: _cap('user-a', 'tenant-a'),
      );
      final coordinator = WebsiteSaveCoordinator(gateway);
      final result = await coordinator.save(
        tenantId: 'tenant-a',
        document: provider,
      );
      expect(result.appliedToActiveDocument, isTrue);
      expect(gateway.replaceCalls, 1);
      expect(provider.hasUnsavedChanges, isFalse);
      expect(
        gateway.readPage('page-a').single['block_data']['title'],
        'Draft routed',
      );
    },
  );

  testWidgets(
    'a save against a tenant that does not match the authorizing lease is '
    'rejected before ANY gateway call',
    (tester) async {
      final provider = WebsiteEditModeProvider()
        ..adoptEditorEntryLease(
          0,
          const WebsiteEditorCapabilitySnapshot(
            identity: 'save-user',
            activeTenantId: 'tenant-a',
            storefrontTenantId: 'tenant-a',
            hasAuthority: true,
          ),
        )
        ..enterEditMode(
          const [
            {
              'id': 'block-1',
              'block_type': 'about',
              'block_data': {'title': 'Original'},
              'order_index': 0,
              'is_visible': true,
            },
          ],
          const <String, dynamic>{},
          pageId: 'page-a',
          pageSlug: 'page-a',
        )
        ..updateBlockData('block-1', 'title', 'Draft A');
      addTearDown(provider.dispose);

      final gateway = _StatefulFakeSaveGateway(
        serviceCapability: _cap('user-a', 'tenant-a'),
      );
      final coordinator = WebsiteSaveCoordinator(gateway);
      await expectLater(
        coordinator.save(tenantId: 'tenant-b', document: provider),
        throwsA(isA<WebsiteEditorAuthorityException>()),
      );
      expect(gateway.resolveCalls, 0);
      expect(gateway.replaceCalls, 0);
      expect(gateway.settingsCalls, 0);
    },
  );

  testWidgets(
    'an identity switch A -> B before save produces ZERO gateway calls and '
    'no draft of A ever travels into B',
    (tester) async {
      final provider = WebsiteEditModeProvider()
        ..adoptEditorEntryLease(
          0,
          const WebsiteEditorCapabilitySnapshot(
            identity: 'user-a',
            activeTenantId: 'tenant-a',
            storefrontTenantId: 'tenant-a',
            hasAuthority: true,
          ),
        )
        ..enterEditMode(
          const [
            {
              'id': 'block-1',
              'block_type': 'about',
              'block_data': {'title': 'Original'},
              'order_index': 0,
              'is_visible': true,
            },
          ],
          const <String, dynamic>{},
          pageId: 'page-a',
          pageSlug: 'page-a',
        )
        ..updateBlockData('block-1', 'title', 'Draft A');
      addTearDown(provider.dispose);
      expect(provider.hasUnsavedChanges, isTrue);

      // Identity change: revocation discards A's buckets, then B adopts.
      provider.revokeEditorEntryLease();
      provider.adoptEditorEntryLease(
        provider.editorEntryLeaseGeneration,
        const WebsiteEditorCapabilitySnapshot(
          identity: 'user-b',
          activeTenantId: 'tenant-b',
          storefrontTenantId: 'tenant-b',
          hasAuthority: true,
        ),
      );
      expect(provider.blocks, isEmpty,
          reason: 'A\'s draft was discarded by the revocation.');

      final gateway = _StatefulFakeSaveGateway(
        serviceCapability: _cap('user-b', 'tenant-b'),
      );
      final coordinator = WebsiteSaveCoordinator(gateway);
      // B's own fresh session is legitimate, but NOTHING of A survives the
      // takeover: the save has zero sections, zero gateway writes, and no
      // draft of A can travel into B.
      final result = await coordinator.save(
        tenantId: 'tenant-b',
        document: provider,
      );
      expect(result.completedSections, isEmpty);
      expect(gateway.resolveCalls, 0);
      expect(gateway.replaceCalls, 0);
      expect(gateway.settingsCalls, 0);
      expect(provider.blocks, isEmpty);

      // Aiming at A's tenant with B's lease is REJECTED before any call.
      await expectLater(
        coordinator.save(tenantId: 'tenant-a', document: provider),
        throwsA(isA<WebsiteEditorAuthorityException>()),
      );
      expect(gateway.resolveCalls, 0);
      expect(gateway.replaceCalls, 0);
      expect(gateway.settingsCalls, 0);
    },
  );

  testWidgets(
    'a granted session on a DOCUMENTLESS route saves sitewide drafts '
    '(session owner), while an ownerless page draft is rejected',
    (tester) async {
      // (a) Documentless route: header/footer/sitewide edits save through
      // the SESSION owner stamped at the granted entry.
      final sessionOnly = WebsiteEditModeProvider();
      addTearDown(sessionOnly.dispose);
      sessionOnly.adoptEditorEntryLease(
        0,
        const WebsiteEditorCapabilitySnapshot(
          identity: 'user-a',
          activeTenantId: 'tenant-a',
          storefrontTenantId: 'tenant-a',
          hasAuthority: true,
        ),
      );
      sessionOnly.applyRouteModeCommand(WebsiteEditorMode.edit);
      sessionOnly.updateSiteSetting('store_name', 'Nueva tienda');

      final gateway = _StatefulFakeSaveGateway(
        serviceCapability: _cap('user-a', 'tenant-a'),
      );
      final coordinator = WebsiteSaveCoordinator(gateway);
      final result = await coordinator.save(
        tenantId: 'tenant-a',
        document: sessionOnly,
      );
      expect(result.completedSections, {WebsiteSaveSection.siteSettings});
      expect(gateway.settingsCalls, 1);
      expect(gateway.resolveCalls, 0);
      expect(gateway.replaceCalls, 0);
      expect(gateway.writeGuard, isNull,
          reason: 'The per-command guard is uninstalled in finally.');

      // (b) A page draft whose document was opened WITHOUT a lease has no
      // document owner: rejected with zero gateway calls.
      final ownerless = WebsiteEditModeProvider();
      addTearDown(ownerless.dispose);
      ownerless.enterEditMode(
        const [
          {
            'id': 'block-1',
            'block_type': 'about',
            'block_data': {'title': 'Original'},
            'order_index': 0,
            'is_visible': true,
          },
        ],
        const <String, dynamic>{},
        pageId: 'page-a',
        pageSlug: 'page-a',
      );
      ownerless.adoptEditorEntryLease(
        ownerless.editorEntryLeaseGeneration,
        const WebsiteEditorCapabilitySnapshot(
          identity: 'user-a',
          activeTenantId: 'tenant-a',
          storefrontTenantId: 'tenant-a',
          hasAuthority: true,
        ),
      );
      ownerless.updateBlockData('block-1', 'title', 'Ownerless draft');

      final gateway2 = _StatefulFakeSaveGateway(
        serviceCapability: _cap('user-a', 'tenant-a'),
      );
      final coordinator2 = WebsiteSaveCoordinator(gateway2);
      await expectLater(
        coordinator2.save(tenantId: 'tenant-a', document: ownerless),
        throwsA(isA<WebsiteEditorAuthorityException>()),
      );
      expect(gateway2.resolveCalls, 0);
      expect(gateway2.replaceCalls, 0);
      expect(gateway2.settingsCalls, 0);
    },
  );

  testWidgets(
    'an identity switch DURING the first gated operation aborts every later '
    'write: draft A never reaches the gateway under B',
    (tester) async {
      final provider = WebsiteEditModeProvider();
      addTearDown(provider.dispose);
      provider.adoptEditorEntryLease(
        0,
        const WebsiteEditorCapabilitySnapshot(
          identity: 'user-a',
          activeTenantId: 'tenant-a',
          storefrontTenantId: 'tenant-a',
          hasAuthority: true,
        ),
      );
      provider.applyRouteModeCommand(WebsiteEditorMode.edit);
      provider.activatePageDocument(
        const [
          {
            'id': 'block-1',
            'block_type': 'about',
            'block_data': {'title': 'Original'},
            'order_index': 0,
            'is_visible': true,
          },
        ],
        const <String, dynamic>{},
        pageId: 'page-a',
        pageSlug: 'page-a',
      );
      await tester.pump();
      provider.updateBlockData('block-1', 'title', 'Draft A');
      provider.updateSiteSetting('store_name', 'Tienda A');

      final gateway = _StatefulFakeSaveGateway(
        serviceCapability: _cap('user-a', 'tenant-a'),
      )..settingsGate = Completer<void>();
      final coordinator = WebsiteSaveCoordinator(gateway);
      final pending = coordinator.save(
        tenantId: 'tenant-a',
        document: provider,
      );
      await tester.pump();
      expect(gateway.resolveCalls, 1, reason: 'page target resolved');
      expect(gateway.settingsCalls, 1, reason: 'first op is in flight');

      // A -> B on the SAME tenant while the first op is gated: both the
      // provider AND the service truth move to B.
      gateway.serviceCapability = _cap('user-b', 'tenant-a');
      provider.revokeEditorEntryLease();
      provider.adoptEditorEntryLease(
        provider.editorEntryLeaseGeneration,
        const WebsiteEditorCapabilitySnapshot(
          identity: 'user-b',
          activeTenantId: 'tenant-a',
          storefrontTenantId: 'tenant-a',
          hasAuthority: true,
        ),
      );
      gateway.settingsGate!.complete();

      // The OLD command ends as a typed superseded write — never as
      // authority loss for the new session.
      await expectLater(
        pending,
        throwsA(isA<WebsiteEditorWriteSupersededException>()),
      );
      expect(gateway.authorityRejections, 0);
      expect(gateway.replaceCalls, 0,
          reason: 'Draft A must NEVER be written under B.');
      expect(gateway.settingsCalls, 1,
          reason: 'No further mutable operation ran after the switch.');
      expect(gateway.writeGuard, isNull,
          reason: 'The per-command guard is uninstalled in finally.');
    },
  );

  testWidgets(
    'a provider still holding lease A while the SERVICE is already B on the '
    'same tenant writes nothing: zero gateway calls',
    (tester) async {
      final provider = WebsiteEditModeProvider();
      addTearDown(provider.dispose);
      provider.adoptEditorEntryLease(
        0,
        const WebsiteEditorCapabilitySnapshot(
          identity: 'user-a',
          activeTenantId: 'tenant-a',
          storefrontTenantId: 'tenant-a',
          hasAuthority: true,
        ),
      );
      provider.applyRouteModeCommand(WebsiteEditorMode.edit);
      provider.activatePageDocument(
        const [
          {
            'id': 'block-1',
            'block_type': 'about',
            'block_data': {'title': 'Original'},
            'order_index': 0,
            'is_visible': true,
          },
        ],
        const <String, dynamic>{},
        pageId: 'page-a',
        pageSlug: 'page-a',
      );
      await tester.pump();
      provider.updateBlockData('block-1', 'title', 'Draft A');

      // The auth event reached the service but the provider has not rebuilt
      // yet: the SERVICE truth is B on the SAME tenant.
      final gateway = _StatefulFakeSaveGateway(
        serviceCapability: _cap('user-b', 'tenant-a'),
      );
      final coordinator = WebsiteSaveCoordinator(gateway);
      await expectLater(
        coordinator.save(tenantId: 'tenant-a', document: provider),
        throwsA(isA<WebsiteEditorAuthorityException>()),
      );
      expect(gateway.resolveCalls, 0);
      expect(gateway.replaceCalls, 0);
      expect(gateway.settingsCalls, 0);
    },
  );

  testWidgets(
    'closeEditor under a live granted lease keeps the session attributable: '
    'reopen and sitewide save still work without a new grant',
    (tester) async {
      final provider = WebsiteEditModeProvider();
      addTearDown(provider.dispose);
      provider.adoptEditorEntryLease(
        0,
        const WebsiteEditorCapabilitySnapshot(
          identity: 'user-a',
          activeTenantId: 'tenant-a',
          storefrontTenantId: 'tenant-a',
          hasAuthority: true,
        ),
      );
      provider.applyRouteModeCommand(WebsiteEditorMode.edit);
      provider.closeEditor();
      await tester.pump();
      expect(provider.mode, WebsiteEditorMode.public);

      // Reopen under the SAME live lease and edit sitewide settings.
      provider.applyRouteModeCommand(WebsiteEditorMode.edit);
      expect(provider.mode, WebsiteEditorMode.edit);
      provider.updateSiteSetting('store_name', 'Reabierta');

      final gateway = _StatefulFakeSaveGateway(
        serviceCapability: _cap('user-a', 'tenant-a'),
      );
      final coordinator = WebsiteSaveCoordinator(gateway);
      final result = await coordinator.save(
        tenantId: 'tenant-a',
        document: provider,
      );
      expect(result.completedSections, {WebsiteSaveSection.siteSettings});
      expect(gateway.settingsCalls, 1);
    },
  );

  testWidgets(
    'an A -> B -> A auth churn (same fingerprint, NEW epoch) revokes the '
    'session and writes nothing',
    (tester) async {
      final provider = WebsiteEditModeProvider();
      addTearDown(provider.dispose);
      provider.adoptEditorEntryLease(0, _cap('user-a', 'tenant-a'));
      provider.applyRouteModeCommand(WebsiteEditorMode.edit);
      provider.activatePageDocument(
        const [
          {
            'id': 'block-1',
            'block_type': 'about',
            'block_data': {'title': 'Original'},
            'order_index': 0,
            'is_visible': true,
          },
        ],
        const <String, dynamic>{},
        pageId: 'page-a',
        pageSlug: 'page-a',
      );
      await tester.pump();
      provider.updateBlockData('block-1', 'title', 'Draft A');
      expect(provider.hasUnsavedChanges, isTrue);

      // Two coalesced auth events (A -> B -> A) before any pump/build: the
      // SERVICE truth reproduces A's fingerprint but at a NEW epoch.
      final gateway = _StatefulFakeSaveGateway(
        serviceCapability: _cap('user-a', 'tenant-a', epoch: 2),
      )..identityEpoch = 2;
      final coordinator = WebsiteSaveCoordinator(gateway);
      await expectLater(
        coordinator.save(tenantId: 'tenant-a', document: provider),
        throwsA(isA<WebsiteEditorAuthorityException>()),
      );
      expect(gateway.resolveCalls, 0);
      expect(gateway.replaceCalls, 0);
      expect(gateway.settingsCalls, 0);

      // Re-adopting the same fingerprint at the NEW epoch is a takeover:
      // the stale session and drafts are cleared before adoption.
      provider.adoptEditorEntryLease(
        provider.editorEntryLeaseGeneration,
        _cap('user-a', 'tenant-a', epoch: 2),
      );
      expect(provider.mode, WebsiteEditorMode.public);
      expect(provider.blocks, isEmpty);
      expect(provider.hasUnsavedChanges, isFalse);
    },
  );

  testWidgets(
    'a CURRENT 42501 during a documentless save latches the durable denial, '
    'revokes the provider once and throws typed authority loss',
    (tester) async {
      final provider = WebsiteEditModeProvider();
      addTearDown(provider.dispose);
      provider.adoptEditorEntryLease(0, _cap('user-a', 'tenant-a'));
      provider.applyRouteModeCommand(WebsiteEditorMode.edit);
      provider.updateSiteSetting('store_name', 'Rechazada');

      final gateway = _StatefulFakeSaveGateway(
        serviceCapability: _cap('user-a', 'tenant-a'),
      )..settingsError = const PostgrestException(
          message: 'denied',
          code: '42501',
        );
      final coordinator = WebsiteSaveCoordinator(gateway);
      final revisionBefore = provider.editorEntryLeaseIdentityRevision;
      await expectLater(
        coordinator.save(tenantId: 'tenant-a', document: provider),
        throwsA(isA<WebsiteEditorAuthorityException>()),
      );
      expect(gateway.authorityRejections, 1,
          reason: 'The WRITE path latches the same durable denial.');
      expect(provider.editorEntryLease, isNull,
          reason: 'The provider is revoked exactly once.');
      expect(
        provider.editorEntryLeaseIdentityRevision - revisionBefore,
        1,
        reason: 'EXACTLY one revocation (identity revision delta).',
      );
      expect(provider.mode, WebsiteEditorMode.public);
    },
  );

  testWidgets(
    'a LATE 42501 after an identity switch during save is a typed '
    'SUPERSEDED write: no latch, no revoke, new session untouched',
    (tester) async {
      final provider = WebsiteEditModeProvider();
      addTearDown(provider.dispose);
      provider.adoptEditorEntryLease(0, _cap('user-a', 'tenant-a'));
      provider.applyRouteModeCommand(WebsiteEditorMode.edit);
      provider.updateSiteSetting('store_name', 'Tienda A');

      final gateway = _StatefulFakeSaveGateway(
        serviceCapability: _cap('user-a', 'tenant-a'),
      )
        ..settingsGate = Completer<void>()
        ..settingsError = const PostgrestException(
          message: 'denied',
          code: '42501',
        );
      final coordinator = WebsiteSaveCoordinator(gateway);
      final pending = coordinator.save(
        tenantId: 'tenant-a',
        document: provider,
      );
      await tester.pump();
      expect(gateway.settingsCalls, 1);

      // A -> B during the gated op: provider AND service truth move to B.
      gateway.identityEpoch = 1;
      gateway.serviceCapability = _cap('user-b', 'tenant-a', epoch: 1);
      provider.revokeEditorEntryLease();
      provider.adoptEditorEntryLease(
        provider.editorEntryLeaseGeneration,
        _cap('user-b', 'tenant-a', epoch: 1),
      );
      provider.applyRouteModeCommand(WebsiteEditorMode.edit);
      provider.updateSiteSetting('store_name', 'Tienda B');
      gateway.settingsGate!.complete();

      await expectLater(
        pending,
        throwsA(isA<WebsiteEditorWriteSupersededException>()),
      );
      expect(gateway.authorityRejections, 0,
          reason: 'A\'s late rejection can never latch a denial for B.');
      expect(provider.editorEntryLeaseGranted, isTrue,
          reason: 'B\'s session is untouched.');
      expect(provider.pendingSiteSettings, {'store_name': 'Tienda B'},
          reason: 'B\'s draft is untouched.');
    },
  );

  testWidgets(
    'an epoch-only change during the LAST operation yields '
    'appliedToActiveDocument=false and no acknowledgement',
    (tester) async {
      final provider = WebsiteEditModeProvider();
      addTearDown(provider.dispose);
      provider.adoptEditorEntryLease(0, _cap('user-a', 'tenant-a'));
      provider.applyRouteModeCommand(WebsiteEditorMode.edit);
      provider.updateSiteSetting('store_name', 'Casi guardada');

      final gateway = _StatefulFakeSaveGateway(
        serviceCapability: _cap('user-a', 'tenant-a'),
      )..settingsGate = Completer<void>();
      final coordinator = WebsiteSaveCoordinator(gateway);
      final pending = coordinator.save(
        tenantId: 'tenant-a',
        document: provider,
      );
      await tester.pump();
      expect(gateway.settingsCalls, 1);

      // Only the epoch moves (coalesced auth churn) while the last op is in
      // flight: the write itself completed, but nothing may be acknowledged
      // or reported as applied.
      gateway.identityEpoch = 1;
      gateway.settingsGate!.complete();

      final result = await pending;
      expect(result.appliedToActiveDocument, isFalse);
      expect(provider.pendingSiteSettings, {'store_name': 'Casi guardada'},
          reason: 'No acknowledgement without current authority.');
    },
  );

  testWidgets(
    'a LATE non-auth failure (network/5xx) inside resolvePage, '
    'getNavigation or the SEO write after an identity switch is a typed '
    'SUPERSEDED outcome: zero acks, zero touches on B, guard uninstalled',
    (tester) async {
      Future<void> runCase({
        required void Function(WebsiteEditModeProvider provider) draft,
        required void Function(_StatefulFakeSaveGateway gateway) arm,
        required Completer<void> Function(_StatefulFakeSaveGateway gateway)
            gateOf,
      }) async {
        final provider = WebsiteEditModeProvider();
        addTearDown(provider.dispose);
        provider.adoptEditorEntryLease(0, _cap('user-a', 'tenant-a'));
        provider.applyRouteModeCommand(WebsiteEditorMode.edit);
        draft(provider);

        final gateway = _StatefulFakeSaveGateway(
          serviceCapability: _cap('user-a', 'tenant-a'),
        );
        arm(gateway);
        final coordinator = WebsiteSaveCoordinator(gateway);
        final pending = coordinator.save(
          tenantId: 'tenant-a',
          document: provider,
        );
        await tester.pump();

        // A -> B (same tenant) while the op is gated; then the op FAILS
        // with a non-auth error.
        gateway.identityEpoch = 1;
        gateway.serviceCapability = _cap('user-b', 'tenant-a', epoch: 1);
        provider.revokeEditorEntryLease();
        provider.adoptEditorEntryLease(
          provider.editorEntryLeaseGeneration,
          _cap('user-b', 'tenant-a', epoch: 1),
        );
        provider.applyRouteModeCommand(WebsiteEditorMode.edit);
        provider.updateSiteSetting('store_name', 'Tienda B');
        gateOf(gateway).complete();

        await expectLater(
          pending,
          throwsA(isA<WebsiteEditorWriteSupersededException>()),
        );
        expect(gateway.authorityRejections, 0);
        expect(gateway.writeGuard, isNull,
            reason: 'The per-command guard is uninstalled in finally.');
        expect(provider.editorEntryLeaseGranted, isTrue,
            reason: 'B\'s session is untouched.');
        expect(provider.pendingSiteSettings, {'store_name': 'Tienda B'},
            reason: 'B\'s draft is untouched (no acknowledgement).');
      }

      // resolvePage (page-draft read) fails late with a network error.
      await runCase(
        draft: (provider) {
          provider.activatePageDocument(
            const [
              {
                'id': 'block-1',
                'block_type': 'about',
                'block_data': {'title': 'Original'},
                'order_index': 0,
                'is_visible': true,
              },
            ],
            const <String, dynamic>{},
            pageId: 'page-a',
            pageSlug: 'page-a',
          );
          provider.updateBlockData('block-1', 'title', 'Draft A');
        },
        arm: (gateway) => gateway
          ..resolveGate = Completer<void>()
          ..resolveError = http.ClientException('network down'),
        gateOf: (gateway) => gateway.resolveGate!,
      );

      // The SEO write fails late with a 5xx.
      await runCase(
        draft: (provider) => provider.updatePageSeo(
          routeKey: '/page-a',
          metaTitle: 'SEO',
          metaDescription: 'desc',
        ),
        arm: (gateway) => gateway
          ..seoGate = Completer<void>()
          ..seoError = const PostgrestException(message: 'boom', code: '500'),
        gateOf: (gateway) => gateway.seoGate!,
      );

      // The navigation idempotency read fails late with a network error.
      await runCase(
        draft: (provider) => provider.createFooterNavDraft(
          WebsiteNavigation(
            id: 'draft_22222222-2222-4222-8222-222222222222',
            tenantId: 'tenant-a',
            menuLocation: MenuLocation.footer,
            label: 'Nueva',
            linkType: NavLinkType.external,
            linkValue: '/n',
            createdAt: DateTime.utc(2026, 7, 30),
            updatedAt: DateTime.utc(2026, 7, 30),
          ),
        ),
        arm: (gateway) => gateway
          ..navigationGetGate = Completer<void>()
          ..navigationGetError = http.ClientException('network down'),
        gateOf: (gateway) => gateway.navigationGetGate!,
      );
    },
  );
}
