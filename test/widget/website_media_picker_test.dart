import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vinabike_erp/modules/website/services/website_media_service.dart';
import 'package:vinabike_erp/modules/website/services/website_service.dart';
import 'package:vinabike_erp/modules/website/widgets/website_media_picker.dart';

const _legacyAsset = WebsiteMediaAsset(
  name: 'website_1770066134089_scaled_mechanic.avif',
  path: 'website-images/website_1770066134089_scaled_mechanic.avif',
  publicUrl: 'https://cdn.example.com/website-images/mechanic.avif',
);
const _optimizedAsset = WebsiteMediaAsset(
  name: 'mechanic.webp',
  path: 'website/media/tenant/mechanic.webp',
  publicUrl: 'https://cdn.example.com/website/media/mechanic.webp',
  metadata: {'website_variant': 'web'},
);

class _FakeWebsiteMediaService extends WebsiteMediaService {
  _FakeWebsiteMediaService({
    this.library = const [],
    this.unreadableLegacy = false,
    this.pending,
  }) : super(
          client: SupabaseClient(
            'http://localhost:54321',
            'test-anon-key',
            authOptions: const AuthClientOptions(
              autoRefreshToken: false,
            ),
          ),
        );

  final List<WebsiteMediaAsset> library;
  final bool unreadableLegacy;
  final Completer<WebsiteMediaAsset>? pending;
  final optimized = <String>[];

  @override
  Future<List<WebsiteMediaAsset>> listAssets({String query = ''}) async =>
      library;

  @override
  Future<WebsiteMediaAsset> optimizeLibraryAsset(
    WebsiteMediaAsset asset, {
    String? tenantId,
    WebsiteEditorWriteGuard? writeGuard,
    Iterable<WebsiteMediaAsset> library = const <WebsiteMediaAsset>[],
  }) async {
    optimized.add(asset.path);
    if (pending != null) return pending!.future;
    if (unreadableLegacy) {
      throw const FormatException('No se pudo leer la imagen.');
    }
    return _optimizedAsset;
  }

  @override
  Future<List<WebsiteProductMediaItem>> listProductMedia() async => const [
        WebsiteProductMediaItem(
          id: 'product-1',
          name: 'Cámara Maxxis 29',
          sku: 'MAX-29',
          brand: 'Maxxis',
          categoryName: 'Cámaras',
          inventoryQty: 7,
          isPublished: true,
          imageUrls: [
            'https://cdn.example.com/maxxis-main.png',
            'https://cdn.example.com/maxxis-side.png',
          ],
        ),
        WebsiteProductMediaItem(
          id: 'product-2',
          name: 'Producto sin foto',
          sku: 'NO-PHOTO',
          imageUrls: [],
        ),
      ];
}

void main() {
  testWidgets('product tab selects an image and can link its product',
      (tester) async {
    WebsiteMediaAsset? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () async {
                result = await showWebsiteMediaPicker(
                  context: context,
                  mediaService: _FakeWebsiteMediaService(),
                  allowProductLink: true,
                );
              },
              child: const Text('Abrir picker'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Abrir picker'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Productos'));
    await tester.pumpAndSettle();

    expect(find.text('Cámara Maxxis 29'), findsOneWidget);
    expect(find.text('Producto sin foto'), findsOneWidget);
    expect(find.text('2 imágenes'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('website_product_media_product-1')),
    );
    await tester.pump();

    expect(find.text('Usar sólo imagen'), findsOneWidget);
    expect(find.text('Vincular producto'), findsOneWidget);
    expect(find.text('Imágenes del producto'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('website_product_media_link')),
    );
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.publicUrl, 'https://cdn.example.com/maxxis-main.png');
    expect(result!.productId, 'product-1');
    expect(result!.linksProduct, isTrue);
  });

  testWidgets('upload explains the automatic web optimization', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () => showWebsiteMediaPicker(
                context: context,
                mediaService: _FakeWebsiteMediaService(),
              ),
              child: const Text('Abrir picker'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Abrir picker'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Subir'));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'El editor ajusta el tamaño y publica WebP automáticamente.',
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        'JPG, PNG o WebP. Transparencia y calidad visual se conservan.',
      ),
      findsOneWidget,
    );
  });

  test('sólo una imagen antigua de la biblioteca se vuelve a optimizar', () {
    final service = _FakeWebsiteMediaService();
    expect(service.needsWebOptimization(_legacyAsset), isTrue);
    expect(service.needsWebOptimization(_optimizedAsset), isFalse);
    expect(
      service.needsWebOptimization(const WebsiteMediaAsset(
        name: 'banner.jpg',
        path: 'website/blocks/optimized/banner.jpg',
        publicUrl: 'https://cdn.example.com/banner.jpg',
      )),
      isFalse,
    );
    expect(
      service.needsWebOptimization(const WebsiteMediaAsset(
        name: 'Imagen externa',
        path: 'https://example.com/foto.png',
        publicUrl: 'https://example.com/foto.png',
      )),
      isFalse,
    );
  });

  Future<WebsiteMediaAsset?> pickLegacy(
    WidgetTester tester,
    _FakeWebsiteMediaService service, {
    WebsiteMediaAsset legacy = _legacyAsset,
    bool settle = true,
  }) async {
    WebsiteMediaAsset? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () async {
                result = await showWebsiteMediaPicker(
                  context: context,
                  mediaService: service,
                );
              },
              child: const Text('Abrir picker'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Abrir picker'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(ValueKey('website_media_${legacy.path}')),
    );
    // La tarjeta también escucha doble toque: el toque simple se confirma
    // cuando vence la espera del doble.
    await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 50));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Usar imagen'));
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
    }
    return result;
  }

  testWidgets('usar una imagen antigua entrega su versión optimizada',
      (tester) async {
    final service = _FakeWebsiteMediaService(library: const [_legacyAsset]);
    final result = await pickLegacy(tester, service);
    expect(service.optimized, [_legacyAsset.path]);
    expect(result?.publicUrl, _optimizedAsset.publicUrl);
  });

  testWidgets('si el formato no se puede leer, se usa la imagen como antes',
      (tester) async {
    final service = _FakeWebsiteMediaService(
      library: const [_legacyAsset],
      unreadableLegacy: true,
    );
    final result = await pickLegacy(tester, service);
    expect(service.optimized, [_legacyAsset.path]);
    expect(result?.publicUrl, _legacyAsset.publicUrl);
  });

  test('una WebP antigua pesada también se optimiza; una liviana no', () {
    final service = _FakeWebsiteMediaService();
    WebsiteMediaAsset webp(int size) => WebsiteMediaAsset(
          name: 'bici.webp',
          path: 'website-images/bici.webp',
          publicUrl: 'https://cdn.example.com/bici.webp',
          metadata: {'size': size},
        );
    expect(service.needsWebOptimization(webp(1024 * 1024)), isTrue);
    expect(service.needsWebOptimization(webp(120 * 1024)), isFalse);
  });

  test('el nombre base calza con el de website-optimize-image', () {
    expect(
      WebsiteMediaService.webVariantStem(
          'website_1770066134089_scaled_mechanic.avif'),
      'website_1770066134089_scaled_mechanic',
    );
    expect(WebsiteMediaService.webVariantStem('Cámara Ñandú 29.png'),
        'camara-nandu-29');
  });

  test('una imagen antigua ya optimizada no se vuelve a subir', () async {
    final service = WebsiteMediaService(
      client: SupabaseClient(
        'http://localhost:54321',
        'test-anon-key',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      ),
    );
    const variant = WebsiteMediaAsset(
      name: 'website_1770066134089_scaled_mechanic-'
          '0f8c2d9e-1b2a-4c3d-9e8f-123456789abc-web.webp',
      path: 'website/media/tenant/website_1770066134089_scaled_mechanic-'
          '0f8c2d9e-1b2a-4c3d-9e8f-123456789abc-web.webp',
      publicUrl: 'https://cdn.example.com/website/media/mechanic-web.webp',
    );
    final result = await service.optimizeLibraryAsset(
      _legacyAsset,
      library: const [_legacyAsset, variant],
    );
    expect(result.publicUrl, variant.publicUrl);
  });

  testWidgets('una imagen legible que no se puede preparar avisa y no se usa',
      (tester) async {
    const legacyPng = WebsiteMediaAsset(
      name: 'banner-enorme.png',
      path: 'website-images/banner-enorme.png',
      publicUrl: 'https://cdn.example.com/banner-enorme.png',
    );
    final service = _FakeWebsiteMediaService(
      library: const [legacyPng],
      unreadableLegacy: true,
    );
    final result = await pickLegacy(tester, service, legacy: legacyPng);
    expect(service.optimized, [legacyPng.path]);
    expect(result, isNull);
    expect(find.text('Usar imagen'), findsOneWidget);
  });

  testWidgets('mientras optimiza, el diálogo no se cierra ni cambia de pestaña',
      (tester) async {
    final pending = Completer<WebsiteMediaAsset>();
    final service = _FakeWebsiteMediaService(
      library: const [_legacyAsset],
      pending: pending,
    );
    await pickLegacy(tester, service, settle: false);
    await tester.pump();
    expect(find.text('Optimizando…'), findsOneWidget);
    final cancel = tester.widget<TextButton>(
      find.widgetWithText(TextButton, 'Cancelar'),
    );
    expect(cancel.onPressed, isNull);
    final tabs = tester.widget<SegmentedButton<WebsiteMediaPickerTab>>(
      find.byType(SegmentedButton<WebsiteMediaPickerTab>),
    );
    expect(tabs.onSelectionChanged, isNull);
    pending.complete(_optimizedAsset);
    await tester.pumpAndSettle();
    expect(find.text('Optimizando…'), findsNothing);
  });
}
