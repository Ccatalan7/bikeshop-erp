import 'dart:convert';

import 'package:jaspr/server.dart';
import 'package:test/test.dart';
import 'package:vinabike_storefront_html/storefront_html.dart';

const _tenant = '5443b130-cc28-45af-a420-cd500b288890';
const _parent = 'c0000000-0000-4000-8000-000000000001';
const _child = 'c0000000-0000-4000-8000-000000000002';
const _hidden = 'c0000000-0000-4000-8000-000000000003';
const _draftPage = 'd0000000-0000-4000-8000-000000000009';

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

class _FakeReads implements PublicReads {
  _FakeReads({this.page, this.fail = false, this.shell});

  final Map<String, dynamic>? page;
  final bool fail;
  final Map<String, dynamic>? shell;
  final requested = <String>[];

  @override
  Future<ProductPageReads> productPage(String sku) async {
    requested.add(sku);
    if (fail) throw PublicReadException('down');
    return (shell: shell ?? _shell(), page: page);
  }
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
}) => Future.value(
  storefrontHandler(config: config, reads: reads)(
    Request(method, Uri.parse('http://localhost$path')),
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
  '/productos/x/H911',
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
      expect(response.headers['cache-control'], 'no-store');
      expect(response.headers['x-robots-tag'], 'noindex');
      expect(response.headers['server-timing'], contains('data;dur='));
      expect(reads.requested, ['H911']);
      expect(html, startsWith('<!DOCTYPE html>'));
      expect(html, contains('<html lang="es-CL">'));
      expect(html, isNot(contains('<base')));
      expect(html, contains('<h1>Horquilla Suntour 29 Auron 35</h1>'));
      expect(html, contains(r'$550.000'));
      expect(html, contains('Recorrido'));
      expect(html, contains('<meta name="robots" content="noindex"/>'));
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

  test('the page also answers without the hidden prefix', () async {
    final response = await _get(_FakeReads(page: _page()), '/productos/x/H911');
    expect(response.statusCode, 200);
  });

  test(
    'catalog text is escaped in the page and in the structured data',
    () async {
      final hostile = '<script>alert("x")</script> & "comillas"';
      final response = await _get(
        _FakeReads(
          page: _page(product: _product(name: hostile)),
        ),
        '/productos/x/H911',
      );
      final html = await response.readAsString();
      expect(html, isNot(contains('<script>alert')));
      expect(html, contains('&lt;script&gt;alert'));
      final jsonLd = RegExp(
        r'<script type="application/ld\+json">(.*?)</script>',
        dotAll: true,
      ).firstMatch(html)!.group(1)!;
      expect(jsonLd, isNot(contains('<')));
      expect(jsonLd, contains(r'\u0026'));
    },
  );

  test(
    'breadcrumbs link public categories and menus resolve like the store',
    () async {
      final response = await _get(
        _FakeReads(page: _page()),
        '/productos/x/H911',
      );
      final html = await response.readAsString();
      final crumbs = RegExp(
        r'<nav class="crumbs wrap".*?</nav>',
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

  test('an unknown SKU or path is a 404, a failed read a 502', () async {
    expect((await _get(_FakeReads(), '/productos/x/NOPE')).statusCode, 404);
    expect(
      (await _get(_FakeReads(page: _page()), '/contacto')).statusCode,
      404,
    );
    final failed = await _get(_FakeReads(fail: true), '/productos/x/H911');
    expect(failed.statusCode, 502);
    expect(failed.headers['cache-control'], 'no-store');
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
    expect(
      html,
      contains('<div class="nav-no-mobile"><p class="foot-title">Grupo</p>'),
    );
    expect(
      html,
      contains('<div class="nav-no-desktop"><p class="foot-title">Enlaces</p>'),
    );
    expect(html, contains('<a href="/contacto">Suelto</a>'));
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
}
