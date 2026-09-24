import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vinabike_erp/modules/website/services/website_media_service.dart';
import 'package:vinabike_erp/modules/website/services/website_service.dart';
import 'package:vinabike_erp/modules/website/widgets/website_media_picker.dart';

const _legacyAsset = WebsiteMediaAsset(
  name: 'website_1770066134089_scaled_mechanic.png',
  path: 'website-images/website_1770066134089_scaled_mechanic.png',
  publicUrl: 'https://cdn.example.com/website-images/mechanic.png',
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
  }) async {
    optimized.add(asset.path);
    if (pending != null) return pending!.future;
    if (unreadableLegacy) {
      throw const FormatException('La imagen supera 15 MB.');
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

/// Usa el `optimizeLibraryAsset` real con la búsqueda de variantes inyectada:
/// si encuentra la suya, no baja ni sube nada.
class _VariantLookupService extends WebsiteMediaService {
  _VariantLookupService(this.variants)
      : super(
          client: SupabaseClient(
            'http://localhost:54321',
            'test-anon-key',
            authOptions: const AuthClientOptions(autoRefreshToken: false),
          ),
        );

  final List<WebsiteMediaAsset> variants;
  final searched = <String>[];

  @override
  Future<List<WebsiteMediaAsset>> listWebVariants(
    String stem,
    String tenantId,
  ) async {
    searched.add('$tenantId/$stem');
    return variants;
  }
}

WebsiteMediaAsset _webVariantOf(WebsiteMediaAsset legacy) {
  final name = '${WebsiteMediaService.legacyVariantStem(legacy)}'
      '-0f8c2d9e-1b2a-4c3d-9e8f-123456789abc-web.webp';
  return WebsiteMediaAsset(
    name: name,
    path: 'website/media/tenant/$name',
    publicUrl: 'https://cdn.example.com/website/media/tenant/$name',
  );
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
    expect(
      service.needsWebOptimization(const WebsiteMediaAsset(
        name: 'sin-tamano.webp',
        path: 'website-images/sin-tamano.webp',
        publicUrl: 'https://cdn.example.com/sin-tamano.webp',
      )),
      isTrue,
    );
  });

  test('el nombre de la versión web distingue la imagen por su ruta', () {
    const png = WebsiteMediaAsset(
      name: 'logo.png',
      path: 'website-images/logo.png',
      publicUrl: 'https://cdn.example.com/logo.png',
    );
    const jpg = WebsiteMediaAsset(
      name: 'logo.jpg',
      path: 'website-images/logo.jpg',
      publicUrl: 'https://cdn.example.com/logo.jpg',
    );
    const otherFolder = WebsiteMediaAsset(
      name: 'logo.png',
      path: 'website/blocks/logo.png',
      publicUrl: 'https://cdn.example.com/blocks/logo.png',
    );
    final stem = WebsiteMediaService.legacyVariantStem(png);
    expect(stem, matches(RegExp(r'^logo-src[0-9a-f]{8}$')));
    expect(WebsiteMediaService.legacyVariantStem(png), stem);
    expect(WebsiteMediaService.legacyVariantStem(jpg), isNot(stem));
    expect(WebsiteMediaService.legacyVariantStem(otherFolder), isNot(stem));

    final service = _VariantLookupService(const []);
    expect(service.existingWebVariant(png, [_webVariantOf(jpg)]), isNull);
    expect(
      service.existingWebVariant(
          png, [_webVariantOf(jpg), _webVariantOf(png)])?.path,
      _webVariantOf(png).path,
    );
  });

  test('el nombre sale en ASCII y cabe en el nombre base de la función', () {
    final stem = WebsiteMediaService.legacyVariantStem(WebsiteMediaAsset(
      name: 'Ångström Cámara Ñandú ${'x' * 90}.PNG',
      path: 'website-images/angstrom.PNG',
      publicUrl: 'https://cdn.example.com/angstrom.PNG',
    ));
    // `safeFileStem` de website-optimize-image deja intacto un nombre
    // [a-z0-9_-] sin guiones dobles ni en los bordes y de hasta 72.
    expect(stem, matches(RegExp(r'^[a-z0-9_]+(-[a-z0-9_]+)*$')));
    expect(stem.length, lessThanOrEqualTo(72));
    expect(stem, startsWith('angstrom-camara-nandu-'));
  });

  test('una imagen antigua ya optimizada no se vuelve a subir', () async {
    final service = _VariantLookupService([_webVariantOf(_legacyAsset)]);
    final result = await service.optimizeLibraryAsset(
      _legacyAsset,
      tenantId: 'tenant',
    );
    expect(result.publicUrl, _webVariantOf(_legacyAsset).publicUrl);
    expect(service.searched, [
      'tenant/${WebsiteMediaService.legacyVariantStem(_legacyAsset)}',
    ]);
  });

  testWidgets('una imagen antigua que no se puede preparar avisa y no se usa',
      (tester) async {
    final service = _FakeWebsiteMediaService(
      library: const [_legacyAsset],
      unreadableLegacy: true,
    );
    final result = await pickLegacy(tester, service);
    expect(service.optimized, [_legacyAsset.path]);
    expect(result, isNull);
    expect(find.text('La imagen supera 15 MB.'), findsOneWidget);
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
    expect(find.textContaining('Se optimiza al usarla'), findsOneWidget);
    final cancel = tester.widget<TextButton>(
      find.widgetWithText(TextButton, 'Cancelar'),
    );
    expect(cancel.onPressed, isNull);
    final tabs = tester.widget<SegmentedButton<WebsiteMediaPickerTab>>(
      find.byType(SegmentedButton<WebsiteMediaPickerTab>),
    );
    expect(tabs.onSelectionChanged, isNull);
    final search = tester.widget<TextField>(
      find.widgetWithText(TextField, 'Buscar en la biblioteca'),
    );
    expect(search.enabled, isFalse);
    pending.complete(_optimizedAsset);
    await tester.pumpAndSettle();
    expect(find.text('Optimizando…'), findsNothing);
  });
}
