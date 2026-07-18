import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vinabike_erp/modules/website/services/website_media_service.dart';
import 'package:vinabike_erp/modules/website/widgets/website_media_picker.dart';

class _FakeWebsiteMediaService extends WebsiteMediaService {
  _FakeWebsiteMediaService()
      : super(
          client: SupabaseClient(
            'http://localhost:54321',
            'test-anon-key',
            authOptions: const AuthClientOptions(
              autoRefreshToken: false,
            ),
          ),
        );

  @override
  Future<List<WebsiteMediaAsset>> listAssets({String query = ''}) async =>
      const [];

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
}
