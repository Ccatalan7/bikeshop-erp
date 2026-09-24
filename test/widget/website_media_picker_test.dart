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
    _FakeWebsiteMediaService service,
  ) async {
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
      find.byKey(ValueKey('website_media_${_legacyAsset.path}')),
    );
    // La tarjeta también escucha doble toque: el toque simple se confirma
    // cuando vence la espera del doble.
    await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 50));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Usar imagen'));
    await tester.pumpAndSettle();
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
}
