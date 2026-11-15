import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vinabike_erp/modules/inventory/models/brand_directory.dart';
import 'package:vinabike_erp/modules/inventory/models/brand_models.dart';
import 'package:vinabike_erp/modules/inventory/pages/brand_list_page.dart';
import 'package:vinabike_erp/modules/inventory/pages/brand_page.dart';
import 'package:vinabike_erp/modules/inventory/services/brand_directory_service.dart';
import 'package:vinabike_erp/modules/inventory/services/brand_service.dart';
import 'package:vinabike_erp/shared/services/database_service.dart';
import 'package:vinabike_erp/shared/services/tenant_service.dart';
import 'package:vinabike_erp/shared/themes/app_theme.dart';
import 'package:vinabike_erp/shared/themes/appearance_preset.dart';

/// La lista de Marcas y la página de una marca (2026-11-15) en escritorio,
/// en un ancho intermedio y en teléfono, con cifras con la forma de
/// producción: lo que se ve, lo que se busca y lo que se guarda.
void main() {
  late SupabaseClient client;

  setUpAll(() {
    client = SupabaseClient(
      'http://localhost:54321',
      'test-anon',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  Future<void> pump(
    WidgetTester tester,
    Widget page, {
    Size size = const Size(1440, 900),
    Brightness brightness = Brightness.light,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.resolve(
          preset: AppearancePresets.vinabike,
          brightness: brightness,
        ),
        home: page,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  group('lista de Marcas', () {
    testWidgets('escritorio: vistas con su conteo, lo más vendido primero',
        (tester) async {
      final source = _FakeSource();
      await pump(
        tester,
        BrandListPage(source: source, includeWorkspaceShell: false),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Con productos'), findsOneWidget);
      expect(find.text('Sin logo'), findsOneWidget);
      // Fox no tiene productos: queda fuera de la vista por defecto.
      expect(find.text('Fox'), findsNothing);
      final maxxis = tester.getTopLeft(find.text('Maxxis').first);
      final kenda = tester.getTopLeft(find.text('Kenda').first);
      expect(maxxis.dy, lessThan(kenda.dy));

      await tester.enterText(find.byType(TextField).first, 'teknobike');
      await tester.pump();
      expect(find.text('Maxxis'), findsWidgets);
      expect(find.text('Kenda'), findsNothing);
    });

    testWidgets('escritorio: tarjetas, y la vista «Todas» trae las vacías',
        (tester) async {
      await pump(
        tester,
        BrandListPage(source: _FakeSource(), includeWorkspaceShell: false),
        brightness: Brightness.dark,
      );
      await tester.tap(find.text('Tarjetas'));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.textContaining('vendidas en 12 meses'), findsWidgets);
      // La letra de las pruebas es más ancha que la de la app: las pestañas
      // se deslizan, como lo harían con conteos más largos.
      await tester.ensureVisible(find.text('Todas'));
      await tester.pump();
      await tester.tap(find.text('Todas'));
      await tester.pump();
      expect(find.text('Fox'), findsOneWidget);
    });

    for (final size in const [Size(1000, 800), Size(390, 844)]) {
      testWidgets('sin desbordes a ${size.width.toInt()} px', (tester) async {
        await pump(
          tester,
          BrandListPage(source: _FakeSource(), includeWorkspaceShell: false),
          size: size,
        );
        expect(tester.takeException(), isNull);
        expect(find.text('Maxxis'), findsWidgets);
      });
    }
  });

  group('página de una marca', () {
    testWidgets('marca compartida: se lee entera y no se edita',
        (tester) async {
      await pump(
        tester,
        BrandPage(
          brandId: 'maxxis',
          source: _FakeSource(),
          includeWorkspaceShell: false,
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Maxxis'), findsWidgets);
      expect(find.textContaining('3 productos · 5 unidades en stock'),
          findsOneWidget);
      expect(find.text('TeknoBike'), findsOneWidget);
      expect(find.text('LISTA_MAXXIS_OCT_2026.pdf'), findsOneWidget);
      expect(find.textContaining('PG-00646'), findsOneWidget);
      expect(find.textContaining('Marca del catálogo compartido'),
          findsOneWidget);
      expect(find.text('Editar'), findsNothing);
      expect(find.text('+ Agregar sitio web'), findsNothing);

      // Buscar dentro de la marca: sin tildes y por palabras.
      await tester.enterText(
          find.byKey(const ValueKey('brand-page-product-search')),
          'neumatico 29');
      await tester.pump();
      expect(find.text('Neumático Maxxis Ardent 29x2.40 EXO'), findsOneWidget);
      expect(find.text('Neumático Maxxis Rekon 27.5'), findsNothing);
      expect(find.text('Cámara Maxxis 29 Presta 48 mm'), findsNothing);
    });

    testWidgets('marca del taller: se edita en su lugar y guarda lo cambiado',
        (tester) async {
      final source = _FakeSource();
      final service = _FakeBrandService(client, source);
      await pump(
        tester,
        BrandPage(
          brandId: 'propia',
          source: source,
          brandService: service,
          includeWorkspaceShell: false,
        ),
      );
      await tester.tap(find.text('+ Agregar país'));
      await tester.pump();
      await tester.pump();
      await tester.enterText(
          find.byKey(const ValueKey('brand-edit-country')), 'Taiwán');
      await tester.pump();
      expect(find.text('1 cambio sin guardar'), findsOneWidget);
      expect(find.text('Nuevo'), findsOneWidget);

      await tester.tap(find.text('Guardar datos'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(service.saved.single.country, 'Taiwán');
      expect(service.saved.single.website, isNull);
      expect(service.saved.single.name, 'Propia Directorio');
      // Guardado: la página vuelve a leer y sale de la edición.
      expect(find.byKey(const ValueKey('brand-edit-country')), findsNothing);
      expect(find.text('Taiwán'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('teléfono: ocho productos y el resto a pedido',
        (tester) async {
      await pump(
        tester,
        BrandPage(
          brandId: 'propia',
          source: _FakeSource(),
          includeWorkspaceShell: false,
        ),
        size: const Size(390, 844),
        brightness: Brightness.dark,
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Ver 4 productos más'), findsOneWidget);
    });

    testWidgets('una marca que no existe lo dice', (tester) async {
      await pump(
        tester,
        BrandPage(
          brandId: 'ninguna',
          source: _FakeSource(),
          includeWorkspaceShell: false,
        ),
      );
      expect(find.text('Esta marca no existe o ya no está en el catálogo.'),
          findsOneWidget);
    });
  });
}

class _FakeSource implements BrandDirectorySource {
  _FakeSource() {
    pages['maxxis'] = _maxxisPage();
    pages['propia'] = _ownPage(country: null);
  }

  final Map<String, BrandPageData> pages = {};

  @override
  Future<List<BrandDirectoryEntry>> directory() async => [
        BrandDirectoryEntry(
          id: 'maxxis',
          name: 'Maxxis',
          shared: true,
          products: 30,
          inStock: 13,
          units: 13,
          stockCost: 47630,
          onWeb: 20,
          sold12m: 39,
          lastSale: DateTime.now(),
          supplier: const BrandDirectorySupplier(
              id: 'teknobike', name: 'TeknoBike', official: true),
          supplierCount: 2,
        ),
        const BrandDirectoryEntry(
          id: 'kenda',
          name: 'Kenda',
          shared: true,
          products: 12,
          inStock: 4,
          units: 9,
          stockCost: 30100,
          sold12m: 22,
          supplier: BrandDirectorySupplier(id: 'rbx', name: 'RBX'),
          supplierCount: 5,
        ),
        const BrandDirectoryEntry(id: 'fox', name: 'Fox', shared: true),
      ];

  @override
  Future<BrandPageData?> page(String brandId) async => pages[brandId];

  static BrandPageData _maxxisPage() => BrandPageData(
        brand: ProductBrand(id: 'maxxis', tenantId: '', name: 'Maxxis'),
        totals: BrandDirectoryEntry(
          id: 'maxxis',
          name: 'Maxxis',
          shared: true,
          products: 3,
          inStock: 2,
          units: 5,
          stockCost: 47630,
          sold12m: 39,
          lastSale: DateTime.now(),
        ),
        products: const [
          BrandPageProduct(
              id: 'p1',
              name: 'Neumático Maxxis Ardent 29x2.40 EXO',
              sku: 'MX-1',
              price: 34990,
              stock: 3,
              sold12m: 20),
          BrandPageProduct(
              id: 'p2',
              name: 'Cámara Maxxis 29 Presta 48 mm',
              price: 6990,
              stock: 2,
              sold12m: 19),
          BrandPageProduct(id: 'p3', name: 'Neumático Maxxis Rekon 27.5'),
        ],
        suppliers: [
          BrandPageSupplier(
            supplierId: 'teknobike',
            name: 'TeknoBike',
            official: true,
            carries: true,
            purchases: 7,
            units: 73,
            lastPurchase: DateTime(2026, 11, 9),
          ),
          const BrandPageSupplier(
              supplierId: 'ciclo', name: 'Comercial Ciclo', carries: true),
        ],
        jobsTotal: 2,
        recentJobs: [
          BrandPageJob(
            id: 'j1',
            number: 'PG-00646',
            status: 'EN_PROCESO',
            arrivalDate: DateTime(2026, 11, 12),
            customerName: 'Renato Prueba',
            bike: 'Trek Marlin 7',
            lines: 2,
            firstItem: 'Neumático Maxxis Ardent',
          ),
        ],
        filesTotal: 1,
        recentFiles: const [
          <String, dynamic>{
            'id': 'f1',
            'storage_path': 'tenant/conv/lista.pdf',
            'original_filename': 'LISTA_MAXXIS_OCT_2026.pdf',
            'extension': 'pdf',
            'declared_mime_type': 'application/pdf',
            'attached_at': '2026-11-10T12:00:00Z',
            'size_bytes': 120000,
            'conversations': <String, dynamic>{
              'title': 'TeknoBike',
              'counterparty_type': 'supplier',
              'channel': 'whatsapp',
              'whatsapp_conversation_bindings': <Object>[],
            },
          },
        ],
      );

  static BrandPageData _ownPage({required String? country}) => BrandPageData(
        brand: ProductBrand(
          id: 'propia',
          tenantId: 'tenant-1',
          name: 'Propia Directorio',
          country: country,
        ),
        totals: const BrandDirectoryEntry(
          id: 'propia',
          name: 'Propia Directorio',
          products: 12,
          inStock: 12,
          units: 12,
        ),
        products: [
          for (var index = 1; index <= 12; index++)
            BrandPageProduct(
              id: 'own-$index',
              name: 'Producto propio $index',
              stock: 1,
              price: 1000 * index,
            ),
        ],
      );
}

class _FakeBrandService extends BrandService {
  _FakeBrandService(SupabaseClient client, this.source)
      : super(
          DatabaseService(client: client, tenantService: _tenant()),
          tenantService: _tenant(),
        );

  final _FakeSource source;
  final List<ProductBrand> saved = [];

  static TenantService _tenant() => TenantService.testing(
        currentUserId: () => null,
        profileLookup: (_) async => const <Map<String, dynamic>>[],
      );

  @override
  Future<ProductBrand> updateBrand(ProductBrand brand) async {
    saved.add(brand);
    source.pages['propia'] = _FakeSource._ownPage(country: brand.country);
    return brand;
  }
}
