import 'dart:convert';
import 'dart:io';

import 'package:jaspr/server.dart';
import 'package:test/test.dart';
import 'package:vinabike_public_core/public_store/utils/product_url.dart';
import 'package:vinabike_public_core/shared/models/product.dart';
import 'package:vinabike_storefront_html/storefront_html.dart';

const _tenant = '5443b130-cc28-45af-a420-cd500b288890';
const _parent = 'c0000000-0000-4000-8000-000000000001';
const _child = 'c0000000-0000-4000-8000-000000000002';
const _hidden = 'c0000000-0000-4000-8000-000000000003';
const _draftPage = 'd0000000-0000-4000-8000-000000000009';
const _brandA = 'b0000000-0000-4000-8000-00000000000a';
const _brandB = 'b0000000-0000-4000-8000-00000000000b';

Map<String, dynamic> _shell() => {
  'settings': {
    'store_name': 'Viñabike',
    'theme_primary_color': '4279385960',
    'contact_address': 'Alvarez 32, Viña del Mar',
    'business_hours_json': jsonEncode([
      {'day': 'MONDAY', 'opens': '10:30', 'closes': '19:00'},
    ]),
  },
  'navigation': [
    {
      'id': 'n1',
      'menu_location': 'header',
      'label': 'Horquillas',
      'link_type': 'category',
      'link_value': _child,
      'order_index': 1,
    },
    {
      'id': 'n2',
      'menu_location': 'header',
      'label': 'Página borrador',
      'link_type': 'page',
      'link_value': _draftPage,
      'order_index': 2,
    },
    {
      'id': 'n3',
      'menu_location': 'header',
      'label': 'Contacto',
      'link_type': 'page',
      'link_value': 'p1',
      'order_index': 3,
    },
  ],
  'pages': [
    {'id': 'p1', 'slug': 'contacto', 'is_home': false, 'title': 'Contacto'},
  ],
  'categories': [
    {
      'id': _parent,
      'name': 'Componentes',
      'parent_id': null,
      'full_path': 'Componentes',
      'show_on_website': true,
    },
    {
      'id': _child,
      'name': 'Horquillas',
      'parent_id': _parent,
      'full_path': 'Componentes > Horquillas',
      'show_on_website': true,
    },
    {
      'id': _hidden,
      'name': 'Interna',
      'parent_id': null,
      'full_path': 'Interna',
      'show_on_website': false,
    },
  ],
  'shipping_tiers': [
    {
      'shipping_gross': 6990,
      'estimated_min_business_days': 3,
      'estimated_max_business_days': 12,
    },
  ],
};

Map<String, dynamic> _product({
  String name = 'Horquilla Suntour 29 Auron 35',
  String sku = 'H911',
}) => {
  'id': '6f1d2a3e-0000-4000-8000-000000000911',
  'tenant_id': _tenant,
  'name': name,
  'sku': sku,
  'price': 550000,
  'stock_quantity': 2,
  'inventory_qty': 2,
  'track_stock': true,
  'is_active': true,
  'is_published': true,
  'show_on_website': true,
  'image_urls': ['https://example.invalid/h911.jpg'],
  'category_id': _child,
  'brand_id': 'b1',
  'model': 'AURON35 Boost EQ',
};

Map<String, dynamic> _page({Map<String, dynamic>? product}) => {
  'product': product ?? _product(),
  'brand_rows': [
    {'id': 'b1', 'name': 'Suntour', 'tenant_id': null, 'is_active': true},
  ],
  'specs': [
    {
      'section_key': 'medidas',
      'section_sort_order': 1,
      'field_sort_order': 1,
      'spec_key': 'travel_mm',
      'spec_label': 'Recorrido',
      'display_value': '160',
      'unit': 'mm',
      'data_type': 'number',
    },
  ],
  'related': [
    {
      ..._product(name: 'Horquilla vecina', sku: 'H912'),
      'id': '6f1d2a3e-0000-4000-8000-000000000912',
    },
  ],
};

/// The product's canonical path, which the page answers without a redirect.
String _canonical([Map<String, dynamic>? product]) =>
    publicProductPath(Product.fromJson(product ?? _product()));

class _FakeReads implements PublicReads {
  _FakeReads({
    this.page,
    this.fail = false,
    Map<String, dynamic>? shell,
    this.products = const [],
    this.brandRows = const [],
    this.thumbnails = const [],
    this.facets = const [],
    this.aliases = const {},
    this.byId = const {},
  }) : shellJson = shell;

  final Map<String, dynamic>? page;
  final bool fail;
  final Map<String, dynamic>? shellJson;
  final List<Object?> products;
  final List<Object?> brandRows;
  final List<Object?> thumbnails;
  final List<Object?> facets;
  final Map<String, String> aliases;
  final Map<String, Map<String, dynamic>> byId;
  final requested = <String>[];
  final catalogRequests = <CatalogRequest>[];

  @override
  Future<ShellReads> shell() async {
    if (fail) throw PublicReadException('down');
    return (shell: shellJson ?? _shell(), payments: null);
  }

  @override
  Future<ProductPageReads> productPage({String? sku, String? productId}) async {
    requested.add(sku ?? 'id:$productId');
    if (fail) throw PublicReadException('down');
    return (shell: shellJson ?? _shell(), payments: null, page: page);
  }

  @override
  Future<CatalogReads> catalog(CatalogRequest request) async {
    catalogRequests.add(request);
    if (fail) throw PublicReadException('down');
    return (
      products: products,
      brandRows: brandRows,
      thumbnails: thumbnails,
      facets: facets,
      optionLabels: const <Object?>[],
    );
  }

  @override
  Future<Map<String, dynamic>?> productById(String id) async => byId[id];

  @override
  Future<String?> productIdForAlias(String path) async => aliases[path];
}

const _config = StorefrontConfig(
  supabaseUrl: 'https://example.invalid',
  publishableKey: 'test',
);

Future<Response> _get(
  PublicReads reads,
  String path, {
  String method = 'GET',
  StorefrontConfig config = _config,
  Map<String, String> headers = const {},
}) => Future.value(
  storefrontHandler(config: config, reads: reads)(
    Request(method, Uri.parse('http://localhost$path'), headers: headers),
  ),
);

Map<String, dynamic> _nav(
  String id,
  String label, {
  String location = 'header',
  String? parent,
  String type = 'page',
  String value = 'p1',
  bool desktop = true,
  bool mobile = true,
}) => {
  'id': id,
  'menu_location': location,
  'label': label,
  'link_type': type,
  'link_value': value,
  'parent_id': parent,
  'order_index': 1,
  'show_on_desktop': desktop,
  'show_on_mobile': mobile,
};

Future<String> _html({
  Map<String, dynamic>? shell,
  Map<String, dynamic>? page,
  StorefrontConfig config = _config,
}) async => (await _get(
  _FakeReads(page: page ?? _page(), shell: shell),
  _canonical(),
  config: config,
)).readAsString();
void main() {
  setUpAll(Jaspr.initializeApp);

  test(
    'a product page is whole HTML, fresh on every visit and noindex',
    () async {
      final reads = _FakeReads(page: _page());
      final response = await _get(
        reads,
        '/_html/productos/horquilla-suntour-29-auron-35/H911',
      );
      final html = await response.readAsString();

      expect(response.statusCode, 200);
      expect(response.headers['cache-control'], 'private, no-cache');
      expect(response.headers['x-robots-tag'], 'noindex');
      expect(response.headers['server-timing'], contains('data;dur='));
      expect(reads.requested, ['H911']);
      expect(html, startsWith('<!DOCTYPE html>'));
      expect(html, contains('<html lang="es-CL">'));
      expect(html, isNot(contains('<base')));
      expect(html, contains('<h1>Horquilla Suntour 29 Auron 35</h1>'));
      expect(html, contains(r'$550.000'));
      expect(html, contains('Recorrido'));
      expect(html, contains('<meta name="robots" content="noindex,follow"/>'));
      expect(
        html,
        contains(
          'href="https://vinabike.cl/productos/horquilla-suntour-29-auron-35/H911" '
          'rel="canonical"',
        ),
      );
      expect(html, contains('"@type":"Product"'));
      expect(html, contains('"@type":"BreadcrumbList"'));
      expect(html, contains('href="/productos/horquilla-vecina/H912"'));
    },
  );

  test(
    'the public path is indexable; a filter or the hidden copy is not',
    () async {
      final public = await _get(
        _FakeReads(page: _page()),
        '/productos/horquilla-suntour-29-auron-35/H911',
      );
      expect(public.statusCode, 200);
      expect(public.headers['x-robots-tag'], isNull);
      expect(
        await public.readAsString(),
        contains('<meta name="robots" content="index,follow"/>'),
      );
      final tracked = await _get(
        _FakeReads(page: _page()),
        '/productos/horquilla-suntour-29-auron-35/H911?utm_source=ig',
      );
      expect(tracked.headers['x-robots-tag'], isNull);
      final sorted = await _get(
        _FakeReads(page: _page()),
        '/productos/horquilla-suntour-29-auron-35/H911?sort=price_asc',
      );
      expect(sorted.headers['x-robots-tag'], 'noindex');
    },
  );

  test(
    'catalog text is escaped in the page and in the structured data',
    () async {
      final hostile = '<script>alert("x")</script> & "comillas"';
      final response = await _get(
        _FakeReads(
          page: _page(product: _product(name: hostile)),
        ),
        _canonical(_product(name: hostile)),
      );
      final html = await response.readAsString();
      expect(html, isNot(contains('<script>alert')));
      expect(html, contains('&lt;script&gt;alert'));
      final jsonLd = RegExp(
        r'<script type="application/ld\+json">(.*?)</script>',
        dotAll: true,
      ).allMatches(html).map((match) => match.group(1)!).join();
      expect(jsonLd, isNot(contains('<')));
      expect(jsonLd, contains(r'\u0026'));
    },
  );

  test(
    'breadcrumbs link public categories and menus resolve like the store',
    () async {
      final response = await _get(_FakeReads(page: _page()), _canonical());
      final html = await response.readAsString();
      final crumbs = RegExp(
        r'<nav class="crumbs".*?</nav>',
        dotAll: true,
      ).firstMatch(html)!.group(0)!;
      expect(crumbs, contains('href="/productos/categoria/componentes"'));
      expect(crumbs, contains('href="/productos/categoria/horquillas"'));
      // The category menu becomes its clean path, the published page its route,
      // and a link to an unpublished page is not drawn.
      expect(
        html,
        contains('<a href="/productos/categoria/horquillas">Horquillas</a>'),
      );
      expect(html, contains('<a href="/contacto">Contacto</a>'));
      expect(html, isNot(contains('Página borrador')));
    },
  );

  test('pages are gzipped for a client that asks', () async {
    final response = await _get(
      _FakeReads(page: _page()),
      _canonical(),
      headers: {'accept-encoding': 'gzip, deflate, br'},
    );
    expect(response.headers['content-encoding'], 'gzip');
    expect(response.headers['vary'], 'accept-encoding');
    final bytes = await response.read().expand((chunk) => chunk).toList();
    expect(utf8.decode(gzip.decode(bytes)), contains('<!DOCTYPE html>'));
    final plain = await _get(_FakeReads(page: _page()), _canonical());
    expect(plain.headers['content-encoding'], isNull);
  });

  test('an unknown SKU or path is a 404, a failed read a 503', () async {
    expect((await _get(_FakeReads(), '/productos/x/NOPE')).statusCode, 404);
    expect(
      (await _get(_FakeReads(page: _page()), '/contacto')).statusCode,
      404,
    );
    final failed = await _get(_FakeReads(fail: true), '/productos/x/H911');
    expect(failed.statusCode, 503);
    expect(failed.headers['cache-control'], 'private, no-cache');
    expect(
      (await _get(
        _FakeReads(page: _page()),
        '/productos/x/H911',
        method: 'POST',
      )).statusCode,
      405,
    );
  });

  test('canonical and JSON-LD follow the editor\'s store_url', () async {
    final html = await _html(
      shell: {
        ..._shell(),
        'settings': {
          ..._shell()['settings'],
          'store_url': 'https://tienda.example/',
        },
      },
    );
    expect(html, contains('href="https://tienda.example/productos/'));
    expect(
      html,
      contains('"item":"https://tienda.example/productos/categoria/'),
    );
  });

  test(
    'related cards use the canonical brand and their website fields',
    () async {
      final page = _page();
      page['related'] = [
        {
          ...(page['related'] as List).first as Map<String, dynamic>,
          'brand_id': 'b1',
          'brand': 'nombre viejo',
          'website_name': 'Nombre del sitio de la vecina',
        },
      ];
      final html = await _html(page: page);
      expect(html, contains('Nombre del sitio de la vecina'));
    },
  );

  test('menus keep each item\'s phone and desktop visibility', () async {
    final html = await _html(
      shell: {
        ..._shell(),
        'navigation': [
          _nav('a', 'Sólo escritorio', mobile: false),
          _nav('b', 'Sólo teléfono', desktop: false),
          _nav('c', 'En ninguno', desktop: false, mobile: false),
        ],
      },
    );
    expect(
      html,
      contains(
        '<li class="nav-no-mobile"><a href="/contacto">Sólo escritorio</a>',
      ),
    );
    expect(
      html,
      contains(
        '<li class="nav-no-desktop"><a href="/contacto">Sólo teléfono</a>',
      ),
    );
    expect(html, isNot(contains('En ninguno')));
  });

  test(
    'the footer draws groups with links, or one «Enlaces» list without groups',
    () async {
      final grouped = await _html(
        shell: {
          ..._shell(),
          'navigation': [
            _nav('g', 'Información', location: 'footer', value: ''),
            _nav('g1', 'Contacto', location: 'footer', parent: 'g'),
            _nav('solo', 'Suelto', location: 'footer'),
          ],
        },
      );
      expect(grouped, contains('<p class="foot-title">Información</p>'));
      expect(grouped, isNot(contains('Suelto')));

      final flat = await _html(
        shell: {
          ..._shell(),
          'navigation': [_nav('solo', 'Suelto', location: 'footer')],
        },
      );
      expect(flat, contains('<p class="foot-title">Enlaces</p>'));
      expect(flat, contains('<a href="/contacto">Suelto</a>'));
    },
  );

  test(
    'another store without a logo shows its name, never Viñabike\'s logo',
    () async {
      final html = await _html(
        config: const StorefrontConfig(
          supabaseUrl: 'https://example.invalid',
          publishableKey: 'test',
          tenantId: '00000000-0000-4000-8000-000000000000',
        ),
      );
      expect(html, isNot(contains('vinabike_logo')));
      expect(html, contains('<span class="logo-name">Viñabike</span>'));
    },
  );

  test('each audience gets its own footer, as Flutter decides it', () async {
    final html = await _html(
      shell: {
        ..._shell(),
        'navigation': [
          _nav('g', 'Grupo', location: 'footer', value: '', mobile: false),
          _nav('g1', 'Contacto', location: 'footer', parent: 'g'),
          _nav('solo', 'Suelto', location: 'footer', desktop: false),
        ],
      },
    );
    // Flutter's two footers: columns from 800 px up, collapsible sections
    // below, each with its own audience.
    final wide = html.substring(
      html.indexOf('<div class="foot-wide">'),
      html.indexOf('<div class="foot-narrow">'),
    );
    final narrow = html.substring(html.indexOf('<div class="foot-narrow">'));
    expect(wide, contains('<p class="foot-title">Grupo</p>'));
    expect(wide, isNot(contains('Suelto')));
    expect(narrow, contains('<span>ENLACES</span>'));
    expect(narrow, contains('<a href="/contacto">Suelto</a>'));
    expect(narrow, isNot(contains('GRUPO')));
  });

  test(
    'a footer item without a destination passes its published children up',
    () async {
      final html = await _html(
        shell: {
          ..._shell(),
          'navigation': [
            _nav('g', 'Información', location: 'footer', value: ''),
            // Links to a page that is not published: structural only.
            _nav(
              'mid',
              'Carpeta',
              location: 'footer',
              parent: 'g',
              value: 'd0000000-0000-4000-8000-000000000009',
            ),
            _nav('leaf', 'Contacto', location: 'footer', parent: 'mid'),
          ],
        },
      );
      expect(html, contains('<p class="foot-title">Información</p>'));
      expect(html, contains('<a href="/contacto">Contacto</a>'));
      expect(html, isNot(contains('Carpeta')));
    },
  );

  group('catalog', () {
    const id911 = '6f1d2a3e-0000-4000-8000-000000000911';
    List<Object?> rows({int total = 2}) => [
      {..._product(), 'total_count': total},
      {
        ..._product(name: 'Horquilla vecina', sku: 'H912'),
        'id': '6f1d2a3e-0000-4000-8000-000000000912',
        'total_count': total,
      },
    ];
    const facets = <Object?>[
      {
        'facet_key': 'brand',
        'value_id': 'b1',
        'value_label': 'Suntour',
        'item_count': 2,
      },
      {'facet_key': 'price', 'range_min': 100000, 'range_max': 550000},
      {'facet_key': 'summary', 'item_count': 9},
      {'facet_key': 'category', 'value_id': _child, 'item_count': 2},
      {'facet_key': 'category', 'value_id': _hidden, 'item_count': 5},
    ];
    _FakeReads reads({int total = 2, Map<String, dynamic>? shell}) =>
        _FakeReads(
          products: rows(total: total),
          facets: facets,
          shell: shell,
        );

    test('/productos lists the catalog with its filters, indexable', () async {
      final fake = reads();
      final response = await _get(fake, '/productos');
      final html = await response.readAsString();
      expect(response.statusCode, 200);
      expect(response.headers['x-robots-tag'], isNull);
      expect(html, contains('<meta name="robots" content="index,follow"/>'));
      expect(
        html,
        contains('href="https://vinabike.cl/productos" rel="canonical"'),
      );
      expect(
        html,
        contains('<h1 class="trail">PRODUCTOS</h1>'),
      );
      expect(html, contains('Mostrando 1 - 2 de 2 productos'));
      expect(html, contains('href="/productos/horquilla-vecina/H912"'));
      // The tree starts at the published roots and counts their branch; an
      // unpublished category is not offered.
      expect(html, contains('href="/productos/categoria/componentes"'));
      expect(html, isNot(contains('Interna')));
      expect(html, contains('<h2>Categorías</h2>'));
      // «Todas» is the facet summary, which also counts what has no
      // published category.
      expect(html, contains('<span>Todas (9)</span>'));
      expect(html, contains('"@type":"CollectionPage"'));
      expect(html, contains('"@type":"ItemList"'));
      expect(fake.catalogRequests.single.categoryIds, isNull);
      expect(fake.catalogRequests.single.limit, 20);
    });

    test('cards use the commercial title and the canonical brand', () async {
      final fake = _FakeReads(
        products: [
          {
            ..._product(),
            'website_name': 'Nombre web',
            'website_merchant_title': 'Nombre comercial',
            'brand': 'nombre viejo',
            'total_count': 1,
          },
        ],
        brandRows: const [
          {'id': 'b1', 'name': 'Suntour', 'tenant_id': null, 'is_active': true},
        ],
        facets: facets,
      );
      final html = await (await _get(fake, '/productos')).readAsString();
      final card = RegExp(
        r'<li class="card[^"]*">.*?</li>',
        dotAll: true,
      ).firstMatch(html)!.group(0)!;
      expect(card, contains('Nombre comercial'));
      expect(card, contains('<span class="maker">Suntour</span>'));
      expect(card, isNot(contains('nombre viejo')));
    });

    test(
      'a category reads its whole branch, with its hero and trail',
      () async {
        final fake = reads();
        final response = await _get(fake, '/productos/categoria/componentes');
        final html = await response.readAsString();
        expect(response.statusCode, 200);
        expect(
          fake.catalogRequests.single.categoryIds,
          unorderedEquals([_parent, _child]),
        );
        expect(html, contains('<h1>Componentes</h1>'));
        expect(html, contains('<nav class="subcats"'));
        expect(html, contains('<h2>Subcategorías</h2>'));
        expect(
          html,
          contains(
            '<nav class="trail" aria-label="Ruta"><a href="/productos">',
          ),
        );
        expect(
          html,
          contains(
            'href="https://vinabike.cl/productos/categoria/componentes" '
            'rel="canonical"',
          ),
        );
      },
    );

    test(
      'a name shared with a hidden category opens the published one',
      () async {
        final shell = _shell();
        shell['categories'] = [
          ...shell['categories'] as List,
          {
            'id': 'c0000000-0000-4000-8000-000000000004',
            'name': 'Horquillas',
            'parent_id': _hidden,
            'full_path': 'Interna > Horquillas',
            'show_on_website': false,
          },
        ];
        final fake = reads(shell: shell);
        final response = await _get(fake, '/productos/categoria/horquillas');
        expect(response.statusCode, 200);
        expect(fake.catalogRequests.single.categoryIds, [_child]);
      },
    );

    test('an unknown or unpublished category is a 404', () async {
      for (final path in [
        '/productos/categoria/interna',
        '/productos/categoria/no-existe',
      ]) {
        final response = await _get(reads(), path);
        expect(response.statusCode, 404, reason: path);
        expect(response.headers['x-robots-tag'], 'noindex');
        expect(
          await response.readAsString(),
          contains('Esta colección no está disponible'),
        );
      }
    });

    test('a GET form\'s repeated and empty fields become one filter', () async {
      final fake = reads();
      final response = await _get(
        fake,
        '/productos?brand=$_brandA&brand=$_brandB&min_price=&max_price=90000'
        '&spec.valve_standard=Presta&spec.valve_standard=Schrader&q=',
      );
      expect(response.statusCode, 200);
      expect(response.headers['x-robots-tag'], 'noindex');
      final request = fake.catalogRequests.single;
      expect(request.brandIds, unorderedEquals([_brandA, _brandB]));
      expect(request.minPrice, isNull);
      expect(request.maxPrice, 90000);
      expect(request.specFilters, {
        'valve_standard': ['Presta', 'Schrader'],
      });
    });

    test('invalid filters are said, not silently widened', () async {
      final response = await _get(reads(), '/productos?min_price=abc');
      expect(response.statusCode, 200);
      expect(response.headers['x-robots-tag'], 'noindex');
      expect(
        await response.readAsString(),
        contains('La URL contiene filtros de catálogo inválidos.'),
      );
    });

    test('pages link to each other and say which one they are', () async {
      final first = await (await _get(
        reads(total: 45),
        '/productos',
      )).readAsString();
      expect(first, contains('href="/productos?page=2"'));
      expect(first, contains('rel="next"'));
      final second = await _get(reads(total: 45), '/productos?page=2');
      final html = await second.readAsString();
      expect(second.headers['x-robots-tag'], 'noindex');
      expect(html, contains('· página 2</title>'));
      expect(html, contains('Mostrando 21 - 40 de 45 productos'));
    });

    test('the old ?category= opens the category\'s own path', () async {
      final response = await _get(
        reads(),
        '/productos?category=$_child&sort=price_asc',
      );
      expect(response.statusCode, 301);
      expect(
        response.headers['location'],
        '/productos/categoria/horquillas?sort=price_asc',
      );
    });

    test(
      'an old ?category= Flutter cannot resolve becomes its search',
      () async {
        final fake = reads();
        final response = await _get(
          fake,
          '/productos?category=texto-inexistente&cat=$_child',
        );
        // `category` wins over `cat` even when it does not resolve.
        expect(response.statusCode, 200);
        expect(fake.catalogRequests.single.searchQuery, 'texto-inexistente');
        expect(fake.catalogRequests.single.categoryIds, isNull);
      },
    );

    test('a page past the end shows the last one, counted right', () async {
      final response = await _get(
        reads(total: 25),
        '/productos?page=999&page_size=20',
      );
      final html = await response.readAsString();
      expect(html, contains('Mostrando 21 - 25 de 25 productos'));
      expect(html, contains('<span class="num" aria-current="page">2</span>'));
      expect(html, contains('· página 2</title>'));
    });

    test('gzip only for a client that does not refuse it', () async {
      final refused = await _get(
        reads(),
        '/productos',
        headers: {'accept-encoding': 'gzip;q=0, identity'},
      );
      expect(refused.headers['content-encoding'], isNull);
      final weighted = await _get(
        reads(),
        '/productos',
        headers: {'accept-encoding': 'br;q=1.0, gzip;q=0.8'},
      );
      expect(weighted.headers['content-encoding'], 'gzip');
    });

    test('product URLs that are not canonical redirect permanently', () async {
      final slug = await _get(
        _FakeReads(page: _page()),
        '/productos/x/H911?utm_source=ig',
      );
      expect(slug.statusCode, 301);
      expect(slug.headers['location'], '${_canonical()}?utm_source=ig');

      final hidden = await _get(
        _FakeReads(page: _page()),
        '/_html/productos/x/H911',
      );
      expect(hidden.headers['location'], '/_html${_canonical()}');

      final alias = await _get(
        _FakeReads(
          aliases: {'/productos/viejo/OLD1': id911},
          byId: {id911: _product()},
        ),
        '/productos/viejo/OLD1',
      );
      expect(alias.statusCode, 301);
      expect(alias.headers['location'], _canonical());

      for (final path in ['/producto/$id911', '/productos/$id911']) {
        final legacy = await _get(_FakeReads(byId: {id911: _product()}), path);
        expect(legacy.statusCode, 301, reason: path);
        expect(legacy.headers['location'], _canonical(), reason: path);
      }
      expect((await _get(_FakeReads(), '/producto/$id911')).statusCode, 404);
    });

    test(
      'measurement: only public pages, and the browser checks the mark',
      () async {
        final shell = {
          ..._shell(),
          'settings': {..._shell()['settings'], 'seo_ga_id': 'G-TEST123'},
        };
        Future<String> html(
          String path, {
          Map<String, String>? headers,
        }) async => (await _get(
          reads(shell: shell),
          path,
          headers: headers ?? const {},
        )).readAsString();
        // Firebase Hosting strips the `vb_sin_medir` cookie on the way here,
        // so the page's own script reads the mark before loading anything.
        final public = await html('/productos');
        expect(public, contains('G-TEST123'));
        expect(public, contains("var markName = 'vb_sin_medir';"));
        expect(
          public,
          contains('if (readMark()) { writeMark(true); return; }'),
        );
        expect(await html('/_html/productos'), isNot(contains('G-TEST123')));
      },
    );

    test('an unpublished site shows the holding page', () async {
      final response = await _get(
        reads(
          shell: {
            ..._shell(),
            'settings': {..._shell()['settings'], 'site_published': 'false'},
          },
        ),
        '/productos',
      );
      expect(response.headers['x-robots-tag'], 'noindex');
      expect(await response.readAsString(), contains('no está publicado'));
    });
  });

  test('every response names the source the server was built from', () async {
    Future<Response> inner(Request request) async => Response.notFound('');
    final request = Request('GET', Uri.parse('http://localhost/productos'));

    final stamped = await storefrontSourceHeader(
      'core-aaaaaaaaaaaa.server-bbbbbbbbbbbb',
    )(inner)(request);
    expect(
      stamped.headers['x-storefront-source'],
      'core-aaaaaaaaaaaa.server-bbbbbbbbbbbb',
    );
    final plain = await storefrontSourceHeader(null)(inner)(request);
    expect(plain.headers.containsKey('x-storefront-source'), isFalse);

    final config = StorefrontConfig.fromEnvironment({
      'SUPABASE_PUBLISHABLE_KEY': 'sb_publishable_x',
      'STOREFRONT_SOURCE': ' core-a.server-b ',
    });
    expect(config.source, 'core-a.server-b');
    expect(
      StorefrontConfig.fromEnvironment({
        'SUPABASE_PUBLISHABLE_KEY': 'sb_publishable_x',
      }).source,
      isNull,
    );
  });

  test('a product without a SKU is drawn at its UUID route', () async {
    const id = '6f1d2a3e-0000-4000-8000-000000000912';
    final product = {..._product(), 'id': id, 'sku': null};
    final fake = _FakeReads(
      page: _page(product: product),
      byId: {id: product},
    );
    final response = await _get(fake, '/productos/$id');
    expect(response.statusCode, 200);
    expect(fake.requested, ['id:$id']);
    final html = await response.readAsString();
    expect(
      html,
      contains('href="https://vinabike.cl/productos/$id" rel="canonical"'),
    );

    final singular = await _get(
      _FakeReads(byId: {id: product}),
      '/producto/$id',
    );
    expect(singular.statusCode, 301);
    expect(singular.headers['location'], '/productos/$id');
  });

  group('card photos', () {
    const photo = 'https://example.invalid/h911.jpg';
    final facets = [
      {'facet_key': 'summary', 'item_count': 1},
    ];
    Future<String> page({List<Object?> thumbnails = const []}) async {
      final fake = _FakeReads(
        products: [
          {..._product(), 'total_count': 1},
        ],
        thumbnails: thumbnails,
        facets: facets,
      );
      return (await _get(fake, '/productos')).readAsString();
    }

    test('offer the smaller copies and preload the same candidates', () async {
      final html = await page(
        thumbnails: [
          {
            'source_url': photo,
            'source_width': 1200,
            'source_height': 900,
            'variants': [
              {
                'width': 800,
                'height': 600,
                'url': 'https://example.invalid/t-800.jpg',
              },
              {
                'width': 400,
                'height': 300,
                'url': 'https://example.invalid/t-400.jpg',
              },
            ],
          },
        ],
      );
      final card = RegExp(
        r'<li class="card[^"]*">.*?</li>',
        dotAll: true,
      ).firstMatch(html)!.group(0)!;
      const srcset =
          'https://example.invalid/t-400.jpg 400w, '
          'https://example.invalid/t-800.jpg 800w, $photo 1200w';
      expect(card, contains('src="https://example.invalid/t-400.jpg"'));
      expect(card, contains('srcset="$srcset"'));
      expect(
        card,
        contains(
          'sizes="(max-width: 599px) calc(50vw - 49px), '
          '(max-width: 699px) calc(33vw - 49px), '
          '(max-width: 899px) calc(50vw - 199px), '
          '(max-width: 1191px) calc(33vw - 149px), '
          '(max-width: 1559px) calc(25vw - 128px), 257px"',
        ),
      );
      final preload = RegExp(
        r'<link[^>]*rel="preload"[^>]*as="image"[^>]*>',
      ).firstMatch(html)!.group(0)!;
      expect(preload, contains('imagesrcset="$srcset"'));
      expect(preload, contains('imagesizes='));
    });

    test('without copies a card keeps the photo', () async {
      final html = await page();
      final card = RegExp(
        r'<li class="card[^"]*">.*?</li>',
        dotAll: true,
      ).firstMatch(html)!.group(0)!;
      expect(card, contains('src="$photo"'));
      expect(card, isNot(contains('srcset')));
    });
  });
}
