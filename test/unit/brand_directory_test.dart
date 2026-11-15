import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/inventory/models/brand_data_draft.dart';
import 'package:vinabike_erp/modules/inventory/models/brand_directory.dart';
import 'package:vinabike_erp/modules/inventory/models/brand_models.dart';

/// La lista de Marcas y la página de una marca (2026-11-15): vistas, orden,
/// búsqueda por marca o proveedor, cómo se dicen las cifras, y la edición en su
/// lugar de los datos de la marca.
void main() {
  BrandDirectoryEntry entry(
    String name, {
    int products = 0,
    int inStock = 0,
    num sold = 0,
    String? logo,
    String? supplier,
    DateTime? lastSale,
  }) =>
      BrandDirectoryEntry(
        id: name.toLowerCase(),
        name: name,
        logoUrl: logo,
        products: products,
        inStock: inStock,
        sold12m: sold,
        lastSale: lastSale,
        supplier: supplier == null
            ? null
            : BrandDirectorySupplier(id: supplier.toLowerCase(), name: supplier),
        supplierCount: supplier == null ? 0 : 1,
      );

  final rows = <BrandDirectoryEntry>[
    entry('Maxxis',
        products: 30,
        inStock: 13,
        sold: 39,
        logo: 'https://example.invalid/m.png',
        supplier: 'TeknoBike',
        lastSale: DateTime(2026, 11, 14)),
    entry('Kenda', products: 12, inStock: 4, sold: 39, supplier: 'RBX'),
    entry('Shimano', products: 40, sold: 80, supplier: 'Andes Industrial'),
    entry('Fox'),
    entry('Ztto', products: 2, inStock: 2, sold: 1),
  ];

  group('vistas', () {
    test('«Con productos» deja fuera las marcas vacías', () {
      final names = brandDirectoryRows(rows,
              view: BrandListView.withProducts,
              sort: BrandSort.name,
              descending: false)
          .map((row) => row.name);
      expect(names, ['Kenda', 'Maxxis', 'Shimano', 'Ztto']);
    });

    test('«Con stock» y «Sin logo» cuentan lo que dicen', () {
      expect(
        rows.where(BrandListView.inStock.includes).map((row) => row.name),
        ['Maxxis', 'Kenda', 'Ztto'],
      );
      expect(
        rows.where(BrandListView.noLogo.includes).map((row) => row.name),
        ['Kenda', 'Shimano', 'Fox', 'Ztto'],
      );
      expect(rows.where(BrandListView.all.includes), hasLength(5));
    });
  });

  group('orden', () {
    test('un empate se rompe por nombre', () {
      final names = brandDirectoryRows(rows,
              view: BrandListView.all, sort: BrandSort.sold, descending: true)
          .map((row) => row.name)
          .toList();
      expect(names.take(3), ['Shimano', 'Kenda', 'Maxxis']);
    });

    test('sin proveedor y sin venta van al final en los dos sentidos', () {
      for (final descending in [false, true]) {
        final bySupplier = brandDirectoryRows(rows,
                view: BrandListView.all,
                sort: BrandSort.supplier,
                descending: descending)
            .map((row) => row.name)
            .toList();
        expect(bySupplier.sublist(3), ['Fox', 'Ztto']);
        final byLastSale = brandDirectoryRows(rows,
                view: BrandListView.all,
                sort: BrandSort.lastSale,
                descending: descending)
            .map((row) => row.name)
            .toList();
        expect(byLastSale.first, 'Maxxis');
      }
    });

    test('una cifra se lee de más a menos; un nombre, de la A a la Z', () {
      expect(BrandSort.sold.descendingFirst, isTrue);
      expect(BrandSort.name.descendingFirst, isFalse);
      expect(BrandSort.supplier.descendingFirst, isFalse);
      expect(BrandSort.sold.phrase(descending: true), 'de más a menos vendidas');
    });
  });

  test('se busca por la marca o por quien la trae', () {
    expect(searchBrandDirectory(rows, 'maxx').map((row) => row.name),
        ['Maxxis']);
    expect(searchBrandDirectory(rows, 'teknobike').map((row) => row.name),
        ['Maxxis']);
    expect(searchBrandDirectory(rows, '  '), same(rows));
  });

  test('las cifras se dicen como en el taller', () {
    final today = DateTime(2026, 11, 15, 10);
    expect(brandDayLabel(DateTime(2026, 11, 15, 8), today: today), 'hoy');
    expect(brandDayLabel(DateTime(2026, 11, 14, 22), today: today), 'ayer');
    expect(brandDayLabel(DateTime(2026, 11, 10), today: today), '10 nov');
    expect(brandDayLabel(DateTime(2025, 9, 16), today: today), '16 sep 2025');
    expect(brandCount(1001085), '1.001.085');
    expect(brandCount(-3), '-3');
    expect(brandMoney(47630), r'$47.630');
    expect(brandPlural(1, 'producto'), '1 producto');
    expect(brandPlural(30, 'producto'), '30 productos');
  });

  test('la página se lee de una sola respuesta', () {
    final data = BrandPageData.fromJson(<String, dynamic>{
      'brand': <String, dynamic>{
        'id': 'b1',
        'tenant_id': null,
        'name': 'Maxxis',
        'is_active': true,
        'shared': true,
        'created_at': '2026-01-01T00:00:00Z',
        'updated_at': '2026-01-01T00:00:00Z',
      },
      'totals': <String, dynamic>{
        'products': 2,
        'in_stock': 1,
        'units': 3,
        'stock_cost': 3000,
        'sold_12m': 6,
        'last_sale': '2026-11-13T12:00:00Z',
      },
      'products': [
        <String, dynamic>{
          'id': 'p1',
          'name': 'Neumático',
          'stock_quantity': 3,
          'price': 25990,
          'sold_12m': 6,
        },
        <String, dynamic>{'id': 'p2', 'name': 'Cámara', 'stock_quantity': 0},
      ],
      'suppliers': [
        <String, dynamic>{
          'supplier_id': 's1',
          'name': 'TeknoBike',
          'official': true,
          'carries': true,
          'purchases': 7,
          'units': 73,
        },
      ],
      'jobs': <String, dynamic>{
        'total': 15,
        'recent': [
          <String, dynamic>{
            'id': 'j1',
            'job_number': 'PG-00646',
            'status': 'EN_PROCESO',
            'lines': 2,
            'first_item': 'Neumático',
          },
        ],
      },
      'files': <String, dynamic>{'total': 0, 'recent': <Object>[]},
    });
    expect(data.shared, isTrue);
    expect(data.brand.name, 'Maxxis');
    expect(data.totals.units, 3);
    expect(data.products.map((product) => product.hasStock), [true, false]);
    expect(data.suppliers.single.official, isTrue);
    expect(data.jobsTotal, 15);
    expect(data.recentJobs.single.statusLabel, 'En proceso');
    expect(data.filesTotal, 0);
  });

  group('datos de la marca, editados en su lugar', () {
    final original = ProductBrand(
      id: 'b3',
      tenantId: 't1',
      name: 'Propia',
      website: 'https://propia.example',
      isActive: true,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );

    test('cuenta los cambios y los deshace uno por uno', () {
      final draft = BrandDataDraft(original);
      expect(draft.changeCount, 0);
      draft.setText(BrandDataField.country, 'Taiwán');
      draft.setActive(false);
      expect(draft.changed, {BrandDataField.country, BrandDataField.active});
      expect(draft.before(BrandDataField.active), 'Activa');
      draft.revert(BrandDataField.active);
      expect(draft.changeCount, 1);
      draft.setText(BrandDataField.country, '  ');
      expect(draft.changeCount, 0, reason: 'espacios no son un cambio');
    });

    test('no guarda un nombre vacío ni un sitio sin dirección completa', () {
      final draft = BrandDataDraft(original)
        ..setText(BrandDataField.name, 'P')
        ..setText(BrandDataField.website, 'propia');
      expect(draft.problems.keys,
          {BrandDataField.name, BrandDataField.website});
      draft
        ..setText(BrandDataField.name, 'Propia Bikes')
        ..setText(BrandDataField.website, 'https://propia.example/es');
      expect(draft.problems, isEmpty);
    });

    test('guarda vacío lo vacío y conserva el logo', () {
      final withLogo = original.copyWith(logoUrl: 'https://example.invalid/l.png');
      final saved = (BrandDataDraft(withLogo)
            ..setText(BrandDataField.website, '')
            ..setText(BrandDataField.description, ' Neumáticos '))
          .toBrand();
      expect(saved.website, isNull);
      expect(saved.description, 'Neumáticos');
      expect(saved.logoUrl, 'https://example.invalid/l.png');
      expect(saved.id, 'b3');
    });
  });
}
