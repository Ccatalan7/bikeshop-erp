import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:jaspr/server.dart';
import 'package:test/test.dart';
import 'package:vinabike_public_core/modules/website/models/website_catalog_presentation.dart';
import 'package:vinabike_public_core/modules/website/theme/website_theme_roles.dart';
import 'package:vinabike_public_core/public_store/models/customer_portal_presentation.dart';
import 'package:vinabike_public_core/public_store/models/portal_time_zone.dart';
import 'package:vinabike_public_core/public_store/utils/product_url.dart';
import 'package:vinabike_public_core/shared/utils/auth_input_validation.dart';
import 'package:vinabike_public_core/shared/models/product.dart';
import 'package:vinabike_storefront_html/storefront_html.dart';

const _tenant = '5443b130-cc28-45af-a420-cd500b288890';

/// A customer's saved address, as `customer_addresses` returns it.
const _addressRow = <String, Object?>{
  'id': 'ad000000-0000-4000-8000-000000000001',
  'customer_id': '7e570000-0000-4000-8000-0000000000ab',
  'tenant_id': _tenant,
  'label': 'Casa',
  'recipient_name': 'Ana Prueba',
  'phone': '+56 9 1234 5678',
  'street_address': 'Avenida Libertad',
  'street_number': '1234',
  'apartment': null,
  'comuna': 'Viña del Mar',
  'city': 'Viña del Mar',
  'region': 'Valparaíso',
  'postal_code': null,
  'additional_info': null,
  'is_default': true,
  'created_at': '2026-02-01T00:00:00Z',
  'updated_at': '2026-02-01T00:00:00Z',
};
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
    this.policyRows = const [],
    this.homeRow,
    this.editorPages = const {},
    this.contactRow,
    this.payments,
    this.orders = const {},
    this.portal,
    this.writeOk = true,
    this.auth = const {},
  }) : shellJson = shell;

  /// What `customerPortal` answers; null refuses the session.
  final CustomerPortalReads? portal;

  /// Whether `customerWrite` writes a row.
  final bool writeOk;

  /// What Auth answers each call (200 when absent); null throws as a
  /// connection that failed.
  final Map<CustomerAuthCall, CustomerAuthAnswer?> auth;

  /// Every write and Auth call, as sent.
  final writes = <Map<String, Object?>>[];
  final authCalls = <(CustomerAuthCall, Map<String, Object?>?)>[];

  final Map<String, dynamic>? page;
  final bool fail;
  final Map<String, dynamic>? shellJson;
  final List<Object?> products;
  final List<Object?> brandRows;
  final List<Object?> thumbnails;
  final List<Object?> facets;
  final Map<String, String> aliases;
  final Map<String, Map<String, dynamic>> byId;
  final List<Object?> policyRows;
  final Map<String, dynamic>? homeRow;

  /// The editor's published pages by slug.
  final Map<String, Map<String, dynamic>> editorPages;
  final Map<String, dynamic>? contactRow;

  /// `get_public_checkout_capabilities`, as the shell read returns it.
  final Object? payments;

  /// `get_public_online_order_by_access_token` by token.
  final Map<String, Object?> orders;
  final requested = <String>[];
  final catalogRequests = <CatalogRequest>[];

  @override
  Future<ShellReads> shell() async {
    if (fail) throw PublicReadException('down');
    return (shell: shellJson ?? _shell(), payments: payments);
  }

  @override
  Future<ProductPageReads> productPage({String? sku, String? productId}) async {
    requested.add(sku ?? 'id:$productId');
    if (fail) throw PublicReadException('down');
    return (shell: shellJson ?? _shell(), payments: null, page: page);
  }

  @override
  Future<CustomerPortalReads> customerPortal(
    String accessToken, {
    bool files = true,
  }) async {
    requested.add(files ? 'portal' : 'portal without files');
    if (fail) throw PublicReadException('down');
    final read = portal;
    if (read == null) throw const CustomerSessionRefused();
    return read;
  }

  @override
  Future<Map<String, dynamic>?> customerProfile(String accessToken) async {
    if (fail) throw PublicReadException('down');
    final read = portal;
    if (read == null) throw const CustomerSessionRefused();
    return read.profile;
  }

  @override
  Future<Map<String, dynamic>?> customerEnter(String accessToken) async {
    requested.add('enter');
    if (fail) throw PublicReadException('down');
    final read = portal;
    if (read == null) throw const CustomerSessionRefused();
    return read.profile;
  }

  @override
  Future<bool> customerWrite(
    String accessToken, {
    required String method,
    required String table,
    Map<String, String> filters = const {},
    Map<String, Object?>? body,
  }) async {
    writes.add({
      'method': method,
      'table': table,
      'filters': filters,
      'body': body,
    });
    return writeOk;
  }

  @override
  Future<CustomerAuthAnswer> customerAuth(
    String accessToken,
    CustomerAuthCall call, {
    Map<String, Object?>? body,
  }) async {
    authCalls.add((call, body));
    if (!auth.containsKey(call)) return (status: 200, code: null, message: '');
    final answer = auth[call];
    if (answer == null) throw const SocketException('down');
    return answer;
  }

  @override
  Future<String?> customerJobFile(String accessToken, String reference) async =>
      reference;

  @override
  Future<Object?> publicOrder(String accessToken) async {
    requested.add('order');
    if (fail) throw PublicReadException('down');
    return orders[accessToken];
  }

  @override
  Future<CartReads> cartProducts(List<String> productIds) async {
    if (fail) throw PublicReadException('down');
    return (
      products: [
        for (final row in products)
          if (row is Map && productIds.contains(row['id'])) row,
      ],
      brandRows: brandRows,
      thumbnails: thumbnails,
    );
  }

  @override
  Future<HomePageReads> homePage(
    List<String> Function(Map<String, dynamic> page) productIds,
  ) async {
    if (fail) throw PublicReadException('down');
    final ids = homeRow == null ? const <String>[] : productIds(homeRow!);
    return (
      shell: shellJson ?? _shell(),
      payments: null,
      page: homeRow,
      products: [
        for (final row in products)
          if (row is Map && ids.contains(row['id'])) row,
      ],
      brandRows: brandRows,
      thumbnails: thumbnails,
    );
  }

  @override
  Future<HomePageReads> websitePage(
    String slug,
    List<String> Function(Map<String, dynamic> page) productIds,
  ) async {
    requested.add('pagina:$slug');
    if (fail) throw PublicReadException('down');
    final row = editorPages[slug];
    final ids = row == null ? const <String>[] : productIds(row);
    return (
      shell: shellJson ?? _shell(),
      payments: null,
      page: row,
      products: [
        for (final product in products)
          if (product is Map && ids.contains(product['id'])) product,
      ],
      brandRows: brandRows,
      thumbnails: thumbnails,
    );
  }

  @override
  Future<PolicyPagesReads> policyPages() async {
    if (fail) throw PublicReadException('down');
    return (shell: shellJson ?? _shell(), payments: null, pages: policyRows);
  }

  @override
  Future<ContactPageReads> contactPage() async {
    if (fail) throw PublicReadException('down');
    return (shell: shellJson ?? _shell(), payments: null, page: contactRow);
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
  FlutterShell? flutterShell,
  Object? body,
}) => Future.value(
  storefrontHandler(
    config: config,
    reads: reads,
    flutterShell: flutterShell,
    orderSummaryFonts: _repositoryFonts,
  )(
    Request(
      method,
      Uri.parse('http://localhost$path'),
      headers: headers,
      body: body,
    ),
  ),
);

/// The faces Flutter bundles, from the repository.
final _repositoryFonts = OrderSummaryFonts(
  (face) async => ByteData.sublistView(
    await File('../../assets/fonts/$face.ttf').readAsBytes(),
  ),
);

/// The Flutter store's page, as Hosting would serve it.
class _FakeFlutterShell implements FlutterShell {
  final requested = <String>[];

  @override
  Future<String?> html(String storeUrl) async {
    requested.add(storeUrl);
    return '<!DOCTYPE html><html><head><title>Tienda | Viñabike</title>\n'
        '<meta name="description" content="La portada.">\n'
        '<link rel="canonical" href="https://vinabike.cl">\n'
        '<meta property="og:url" content="https://vinabike.cl">\n'
        '<meta name="robots" content="index,follow">\n'
        '</head><body><noscript><main class="storefront-nojs-fallback">'
        '<h1>Tienda</h1></main></noscript>'
        '<script src="flutter_bootstrap.js"></script></body></html>';
  }
}

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
    // The desktop menu and the phone's sheet are Flutter's two projections.
    final desktop = html.substring(
      html.indexOf('<nav class="menu"'),
      html.indexOf('</nav>', html.indexOf('<nav class="menu"')),
    );
    final sheet = html.substring(
      html.indexOf('<div class="menu-sheet"'),
      html.indexOf('</nav>', html.indexOf('<div class="menu-sheet"')),
    );
    expect(desktop, contains('Sólo escritorio'));
    expect(desktop, isNot(contains('Sólo teléfono')));
    expect(sheet, contains('Sólo teléfono'));
    expect(sheet, isNot(contains('Sólo escritorio')));
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

  group('contact', () {
    Map<String, dynamic> shell() => {
      ..._shell(),
      'settings': {
        ...(_shell()['settings'] as Map),
        'contact_email': 'hola@taller.example',
        'contact_phone': '+56 9 1111 2222',
        'whatsapp': '+56 9 1111 2222',
        // A full address saved where a handle was expected.
        'instagram': 'https://www.instagram.com/taller.norte',
        'business_hours_json':
            '{"periods":[${[for (var day = 1; day <= 5; day++) '{"open":{"day":$day,"time":"1030"},"close":{"day":$day,"time":"1900"}}'].join(',')},'
            '{"open":{"day":6,"time":"1030"},"close":{"day":6,"time":"1530"}}]}',
      },
    };

    test(
      '/contacto draws the store\'s contact page from its settings',
      () async {
        final response = await _get(
          _FakeReads(
            shell: shell(),
            contactRow: const {
              'slug': 'contacto',
              'title': 'Contacto',
              'meta_title': 'Contacto y Ubicación - Taller',
              'meta_description': 'Ubícanos en Viña del Mar.',
            },
          ),
          '/contacto',
        );
        final html = await response.readAsString();
        expect(response.statusCode, 200);
        expect(html, contains('<title>Contacto y Ubicación - Taller</title>'));
        expect(html, contains('"@type":"ContactPage"'));
        expect(html, contains('<h1>Contáctanos</h1>'));
        // The form writes to the store's mailbox, with Flutter's checks.
        expect(html, contains('data-mail="hola@taller.example"'));
        expect(html, contains('data-required="Por favor ingresa tu nombre"'));
        expect(html, contains('data-min="El mensaje debe tener al menos'));
        // Hours grouped as Flutter shows them.
        expect(html, contains('<span>Lunes a Viernes</span>'));
        expect(html, contains('<span class="ct-time">10:30 - 19:00</span>'));
        expect(html, contains('<span>Domingo</span>'));
        expect(html, contains('<span class="ct-time">Cerrado</span>'));
        expect(html, contains('https://wa.me/56911112222?text='));
        // The saved full address is the link, not instagram.com/https://…
        expect(html, contains('href="https://www.instagram.com/taller.norte"'));
        expect(html, isNot(contains('instagram.com/https')));
        expect(html, isNot(contains('Facebook')));
      },
    );

    test('an unpublished /contacto is «Contacto no disponible», 404', () async {
      final response = await _get(_FakeReads(shell: shell()), '/contacto');
      expect(response.statusCode, 404);
      final html = await response.readAsString();
      expect(html, contains('Contacto no disponible'));
      // No form and no contact cards (the footer keeps its contact column).
      expect(html, isNot(contains('<form class="ct-form"')));
      expect(html, isNot(contains('class="ct-card')));
      expect(html, contains('<meta name="robots" content="noindex'));
    });

    test('without a mailbox the form cannot send', () async {
      final settings = Map<String, dynamic>.from(shell()['settings'] as Map)
        ..remove('contact_email');
      final response = await _get(
        _FakeReads(
          shell: {...shell(), 'settings': settings},
          contactRow: const {'slug': 'contacto'},
        ),
        '/contacto',
      );
      final html = await response.readAsString();
      expect(html, contains('<button class="ct-send" type="submit" disabled'));
      expect(html, isNot(contains('action="mailto:')));
    });
  });

  test('the heading font is preloaded as its Latin subset', () async {
    final html = await _html();
    final preload = RegExp(
      r'<link[^>]*rel="preload"[^>]*as="font"[^>]*>',
    ).firstMatch(html)!.group(0)!;
    expect(preload, contains('.latin.woff2"'));
    expect(preload, contains('type="font/woff2"'));
    expect(preload, contains('crossorigin'));
    expect(html, contains('format("woff2")'));
  });

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
    'the wide footer is as wide as its widest row, as Flutter\'s Wrap',
    () async {
      final html = await _html(
        shell: {
          ..._shell(),
          'navigation': [
            _nav('a', 'Enlaces', location: 'footer', value: ''),
            _nav('a1', 'Uno', location: 'footer', parent: 'a'),
            _nav('b', 'Información', location: 'footer', value: ''),
            _nav('b1', 'Dos', location: 'footer', parent: 'b'),
          ],
        },
      );
      // Brand 250 + two columns + «Contacto», 200 each, 32 apart: 946 px in
      // one row; below that «Contacto» starts a row of its own under the
      // logo and the rows are 714 px wide, centered.
      expect(
        html,
        contains('.foot-grid{justify-content:flex-start;width:946px;'),
      );
      expect(
        html,
        contains('@container foot (width<946px){.foot-grid{width:714px}}'),
      );
      expect(
        html,
        contains('@container foot (width<714px){.foot-grid{width:482px}}'),
      );
    },
  );

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
      expect(html, contains('<h1 class="trail">PRODUCTOS</h1>'));
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

    test(
      '/servicios is the same catalog for the workshop\'s services',
      () async {
        final fake = _FakeReads(
          products: [
            {
              ..._product(name: 'Ajuste de dirección', sku: 'NNV3'),
              'product_type': 'service',
              'price': 3000,
              'total_count': 1,
            },
          ],
          facets: const [
            {'facet_key': 'summary', 'item_count': 1},
          ],
        );
        final response = await _get(fake, '/servicios');
        final html = await response.readAsString();
        expect(response.statusCode, 200);
        // The services, not the products, under the snapshot's own title.
        expect(fake.catalogRequests.single.services, isTrue);
        expect(
          html,
          contains(
            '<title>Servicios y precios del taller de bicicletas | Viñabike',
          ),
        );
        expect(
          html,
          contains('href="https://vinabike.cl/servicios" rel="canonical"'),
        );
        expect(html, contains('<h1 class="trail">SERVICIOS</h1>'));
        expect(html, contains('Mostrando 1 - 1 de 1 servicios'));
        expect(html, contains('placeholder="Buscar servicios"'));
        expect(html, contains('href="/servicios"'));
        // Each service with its price, as Google read them until today.
        expect(html, contains('"@type":"Service"'));
        expect(html, contains('"price":"3000","priceCurrency":"CLP"'));
        // /productos still asks for products.
        final products = _FakeReads(products: rows(), facets: facets);
        await _get(products, '/productos');
        expect(products.catalogRequests.single.services, isFalse);
      },
    );

    test(
      'an unknown service category answers 404 back to /servicios',
      () async {
        final response = await _get(reads(), '/servicios/categoria/no-existe');
        expect(response.statusCode, 404);
        final html = await response.readAsString();
        expect(html, contains('Ver todos los servicios'));
        expect(html, contains('href="/servicios"'));
      },
    );

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

  group('information pages', () {
    Map<String, dynamic> row(String slug, List<Map<String, dynamic>> blocks) =>
        {
          'id': 'page-$slug',
          'slug': slug,
          'title': slug == 'envios' ? 'Información de Envíos' : '',
          'meta_description': slug == 'envios'
              ? 'Tarifas y plazos de despacho.'
              : null,
          'is_published': true,
          'website_blocks': blocks,
        };
    Map<String, dynamic> block(
      String id,
      String type,
      int order,
      Map<String, dynamic> data,
    ) => {
      'id': id,
      'block_type': type,
      'order_index': order,
      'is_visible': true,
      'block_data': data,
    };
    final rows = [
      row('envios', [
        block('hero', 'hero', 0, {
          'title': 'Información de Envíos',
          'subtitle': 'Despachos a todo Chile continental',
          'blockHeight': 280,
        }),
        block('features', 'features', 1, {
          'title': 'Opciones de Despacho',
          'features': [
            {'title': 'Retiro en tienda', 'description': 'Sin costo.'},
          ],
          'visibility': {'mobile': false},
        }),
        block('contact', 'contact', 2, {
          'title': 'Visítanos',
          'showForm': false,
        }),
      ]),
      row('nosotros', [
        block('about', 'about', 0, {
          'title': 'Identidad',
          'content': 'Primera línea.\nSegunda línea.\n\nOtro párrafo.',
        }),
      ]),
      // Published but with nothing to read: not linked, and a 404.
      row('terminos', [
        block('t-hero', 'hero', 0, {'title': 'Términos'}),
      ]),
    ];

    test('a page draws its frame, its blocks and the other pages', () async {
      final response = await _get(
        _FakeReads(policyRows: rows),
        '/_html/envios',
      );
      final html = await response.readAsString();

      expect(response.statusCode, 200);
      expect(response.headers['x-robots-tag'], 'noindex');
      expect(html, contains('<h1>Información de Envíos</h1>'));
      expect(html, contains('Tarifas y plazos de despacho.'));
      // The hero's button comes from the block's defaults, as in Flutter.
      expect(html, contains('<h2 class="hero-t">INFORMACIÓN DE ENVÍOS</h2>'));
      expect(html, contains('href="/productos">VER CATÁLOGO</a>'));
      expect(html, contains('style="--gap:64px;height:280px"'));
      // A features block is read as the page's sections; hidden on phones.
      expect(html, contains('<h2>Opciones de Despacho</h2>'));
      expect(html, contains('<h3>Retiro en tienda</h3>'));
      expect(html, contains('data-block="features" data-bands="1 2 3 4 5"'));
      // The contact block without its own data shows the store's.
      expect(html, contains('Alvarez 32, Viña del Mar'));
      expect(html, isNot(contains('Completa tus datos')));
      // The navigation names the pages with something to read.
      expect(html, contains('<a aria-current="page" href="/envios">'));
      expect(html, contains('href="/nosotros"'));
      expect(html, isNot(contains('href="/terminos"><svg')));
      expect(html, contains('"@type":"WebPage"'));
      expect(html, contains('<title>Información de Envíos | Viñabike</title>'));
      expect(response.headers['x-storefront-uncovered'], isNull);
    });

    test('an open information page with a block the HTML does not draw '
        'yet is drawn by Flutter', () async {
      final response = await _get(
        _FakeReads(
          policyRows: [
            row('envios', [
              ...(rows.first['website_blocks'] as List)
                  .cast<Map<String, dynamic>>(),
              block('logos', 'brandLogos', 5, {'logos': []}),
            ]),
          ],
        ),
        '/envios',
        flutterShell: _FakeFlutterShell(),
      );
      expect(response.statusCode, 200);
      expect(response.headers['x-storefront-fallback'], 'flutter');
      expect(response.headers['x-robots-tag'], isNull);
      final html = await response.readAsString();
      expect(html, contains('flutter_bootstrap.js'));
      // The page's own head and words, not the home's.
      expect(html, contains('<title>Información de Envíos | Viñabike</title>'));
      expect(
        html,
        contains('<link rel="canonical" href="https://vinabike.cl/envios">'),
      );
      expect(
        html,
        contains(
          '<meta property="og:url" content="https://vinabike.cl/envios">',
        ),
      );
      expect(html, isNot(contains('La portada.')));
      expect(html, contains('<h1>Información de Envíos</h1>'));
      expect(html, isNot(contains('<h1>Tienda</h1>')));
      expect(html, contains('"@type":"WebPage"'));
    });

    test('a block the HTML does not draw yet is named, not guessed', () async {
      final response = await _get(
        _FakeReads(
          policyRows: [
            row('envios', [
              ...(rows.first['website_blocks'] as List)
                  .cast<Map<String, dynamic>>(),
              block('logos', 'brandLogos', 5, {'logos': []}),
            ]),
          ],
        ),
        '/_html/envios',
      );
      expect(response.statusCode, 200);
      expect(response.headers['x-storefront-uncovered'], 'brandLogos');
    });

    test('the public path is indexable and keeps single line breaks', () async {
      final response = await _get(_FakeReads(policyRows: rows), '/nosotros');
      final html = await response.readAsString();

      expect(response.statusCode, 200);
      expect(response.headers['x-robots-tag'], isNull);
      expect(html, contains('<meta name="robots" content="index,follow"/>'));
      expect(html, contains('"@type":"AboutPage"'));
      expect(html, contains('<h1>Sobre nosotros</h1>'));
      expect(html, contains('Primera línea.<br/>'));
      expect(html, contains('Otro párrafo.'));
    });

    test(
      'a page without public content is a 404 with Flutter\'s message',
      () async {
        for (final path in ['/terminos', '/privacidad']) {
          final response = await _get(_FakeReads(policyRows: rows), path);
          final html = await response.readAsString();
          expect(response.statusCode, 404, reason: path);
          expect(html, contains('no tiene contenido público disponible'));
          expect(
            html,
            contains('<meta name="robots" content="noindex,follow"/>'),
          );
        }
      },
    );
  });

  group('home', () {
    Map<String, dynamic> block(
      String id,
      String type,
      int order,
      Map<String, dynamic> data,
    ) => {
      'id': id,
      'block_type': type,
      'order_index': order,
      'is_visible': true,
      'block_data': data,
    };
    final second = {
      ..._product(name: 'Cassette Eclipse 8v', sku: 'C8'),
      'id': '6f1d2a3e-0000-4000-8000-000000000008',
    };
    Map<String, dynamic> home(List<Map<String, dynamic>> blocks) => {
      'id': 'home',
      'slug': 'inicio',
      'is_published': true,
      'website_blocks': blocks,
    };
    final blocks = [
      block('car', 'carousel', 0, {
        'blockHeight': 750,
        'animation': 'fade',
        'intervalSeconds': 8,
        'slides': [
          {
            'title': 'Taller de bicicletas',
            'subtitle': 'Repuestos y accesorios',
            'imageUrl': 'https://example.invalid/s1.webp',
            'ctaText': 'Ver catálogo',
            'ctaLink': '/productos',
          },
          {
            'title': 'Cámaras',
            'useComposition': true,
            'imageUrl': 'https://example.invalid/s2.png',
            'elements': [
              {
                'id': 'i',
                'type': 'image',
                'imageUrl': 'https://example.invalid/layer.webp',
                'x': 700,
                'y': 120,
                'w': 400,
                'h': 300,
              },
              {
                'id': 't',
                'type': 'text',
                'text': 'CÁMARAS',
                'x': 88,
                'y': 150,
                'w': 610,
                'h': 92,
                'fontSize': 72,
                'anim': 'fadeUp',
              },
              {
                'id': 'b',
                'type': 'button',
                'label': 'Ver cámaras',
                'link': '/productos',
                'style': 'filled',
                'inheritTheme': false,
                'uppercase': true,
                'x': 88,
                'y': 470,
                'w': 220,
                'h': 54,
              },
            ],
          },
        ],
      }),
      block('prod', 'products', 1, {
        'title': 'Productos destacados',
        'productSource': 'manual',
        // The second one is out of stock: the read does not return it.
        'selectedProducts': [second['id'], 'agotado', _product()['id']],
      }),
      block('cats', 'categoryGrid', 2, {
        'categories': [
          {
            'title': 'Horquillas',
            'size': 'large',
            'imageFit': 'contain',
            'imageUrl': 'https://example.invalid/fork.jpg',
            'link': '/productos?category=$_child',
          },
          {
            'title': 'Interna',
            'size': 'large',
            'imageUrl': 'https://example.invalid/x.jpg',
            'link': '/productos?category=$_hidden',
          },
        ],
      }),
      block('brands', 'brandLogos', 3, {
        'title': 'Marcas',
        'blockHeight': 510,
        'brands': [
          {'name': 'Shimano', 'imageUrl': 'https://example.invalid/s.png'},
        ],
      }),
      block('video', 'videoBanner', 4, {
        'title': 'Vive la Aventura',
        'videoUrl': 'https://youtu.be/BnJCsaH5Ybs?si=x',
        'ctaText': 'Descubrir más',
        'ctaLink': '/tienda/productos',
      }),
      block('reviews', 'googleReviews', 5, {'title': 'Reseñas'}),
    ];
    final shell = _shell()
      ..['settings'] = {
        ...(_shell()['settings'] as Map),
        'google_reviews_rating': '4.4',
        'google_reviews_total': '36',
        'google_reviews_data': jsonEncode([
          {'author_name': 'Mia', 'rating': 5, 'text': 'Excelente'},
          {'author_name': 'Juan', 'rating': 3, 'text': 'Pasable'},
        ]),
      };

    test(
      'a picked product shows the copy its smaller photos come from',
      () async {
        const original = 'https://example.invalid/c8.png';
        const optimized = 'https://example.invalid/c8_optimized.jpg';
        final response = await _get(
          _FakeReads(
            homeRow: home([blocks[1]]),
            shell: shell,
            products: [
              {
                ...second,
                'image_url': original,
                'image_url_optimized': optimized,
              },
            ],
            thumbnails: [
              {
                'source_url': optimized,
                'source_width': 1200,
                'source_height': 900,
                'variants': [
                  {
                    'width': 400,
                    'height': 300,
                    'url': 'https://example.invalid/c8-400.jpg',
                  },
                ],
              },
            ],
          ),
          '/_html/',
        );
        final html = await response.readAsString();

        expect(html, contains('src="https://example.invalid/c8-400.jpg"'));
        expect(html, contains('$optimized 1200w'));
        expect(html, isNot(contains(original)));
      },
    );

    test(
      'draws every block under the header that floats over the first',
      () async {
        final response = await _get(
          _FakeReads(
            homeRow: home(blocks),
            shell: shell,
            products: [_product(), second],
          ),
          '/_html/',
        );
        final html = await response.readAsString();

        expect(response.statusCode, 200);
        expect(response.headers['x-storefront-uncovered'], isNull);
        expect(html, contains('<header class="top over">'));
        // The first slide's photo is the largest paint: fetched first.
        expect(
          html,
          contains(
            'href="https://example.invalid/s1.webp" fetchpriority="high"',
          ),
        );
        expect(html, contains('h.classList.toggle("clear",scrollY<=50)'));
        // The carousel: the first slide's title is the page's heading, the
        // composed slide is drawn as layers, and the page script plays it.
        expect(html, contains('<h1 class="car-t"'));
        expect(html, contains('TALLER DE BICICLETAS'));
        expect(html, contains('data-interval="8000"'));
        expect(html, contains('class="cl cl-a-fadeUp cl-text al-left"'));
        expect(html, contains('>VER CÁMARAS</a>'));
        expect(html, contains('document.querySelectorAll("[data-car]")'));
        // A later slide's photos wait for their turn: only the first slide's
        // photo is fetched with the page.
        expect(html, contains('data-src="https://example.invalid/s2.png"'));
        expect(html, contains('data-src="https://example.invalid/layer.webp"'));
        expect(
          html,
          isNot(contains(RegExp(r'[^-]src="https://example.invalid/s2'))),
        );
        expect(
          html,
          isNot(contains(RegExp(r'[^-]src="https://example.invalid/layer'))),
        );
        // The picked products in the author's order, the sold-out one left out.
        final cassette = html.indexOf('CASSETTE ECLIPSE 8V');
        final fork = html.indexOf('HORQUILLA SUNTOUR 29 AURON 35');
        expect(cassette, greaterThan(0));
        expect(fork, greaterThan(cassette));
        // A category card whose category is not published is not drawn.
        expect(html, contains('>HORQUILLAS</span>'));
        expect(html, isNot(contains('>INTERNA</span>')));
        // Its `?category=<id>` link goes straight to the clean path.
        expect(html, contains('href="/productos/categoria/horquillas"'));
        expect(html, isNot(contains('?category=')));
        // The brand row keeps its 510 px as a minimum, centered.
        expect(html, contains('min-height:510px'));
        expect(
          html,
          contains('https://www.youtube.com/embed/BnJCsaH5Ybs?autoplay=1'),
        );
        expect(html, contains('href="/productos">Descubrir más</a>'));
        // The store's synced reviews, only those that reach 4 stars.
        expect(html, contains('en Google (36 reseñas)'));
        expect(html, contains('Excelente'));
        expect(html, isNot(contains('Pasable')));
      },
    );

    test('a block the HTML does not draw yet is named; on the public path '
        'Flutter draws the page', () async {
      final reads = _FakeReads(
        homeRow: home([
          ...blocks,
          block('faq', 'faq', 6, {'title': 'Preguntas'}),
        ]),
        shell: shell,
      );
      final flutter = _FakeFlutterShell();
      final hidden = await _get(reads, '/_html/', flutterShell: flutter);
      expect(hidden.statusCode, 200);
      expect(hidden.headers['x-storefront-uncovered'], 'faq');
      expect(await hidden.readAsString(), contains('TALLER DE BICICLETAS'));
      expect(flutter.requested, isEmpty);

      final public = await _get(reads, '/', flutterShell: flutter);
      expect(public.statusCode, 200);
      expect(public.headers['x-storefront-fallback'], 'flutter');
      expect(public.headers['x-storefront-uncovered'], 'faq');
      expect(await public.readAsString(), contains('flutter_bootstrap.js'));
      expect(flutter.requested, ['https://vinabike.cl']);
    });

    test('a store without a published home answers 404', () async {
      final response = await _get(_FakeReads(), '/_html/');
      expect(response.statusCode, 404);
    });
  });

  group('editor pages', () {
    Map<String, dynamic> block(
      String id,
      String type,
      int order,
      Map<String, dynamic> data,
    ) => {
      'id': id,
      'block_type': type,
      'order_index': order,
      'is_visible': true,
      'block_data': data,
    };
    Map<String, dynamic> page(
      List<Map<String, dynamic>> blocks, {
      String title = 'Arriendo de bicicletas',
      String? metaDescription,
    }) => {
      'id': 'p1',
      'slug': 'arriendo',
      'title': title,
      'meta_description': metaDescription,
      'is_published': true,
      'website_blocks': blocks,
    };
    final blocks = [
      block('h', 'text', 0, {'text': 'Arriendo por día', 'preset': 'heading'}),
      block('t', 'text', 1, {
        'text': 'Casco incluido.\nDevuelve antes de las <19:00> & listo.',
        'maxWidth': 600,
        'formatting': {
          'textAlign': 'center',
          'bold': true,
          'textColor': 0xFF1565C0,
        },
      }),
      block('b', 'button', 2, {
        'label': 'Reservar',
        'link': '/contacto',
        'style': 'outline',
      }),
      block('none', 'button', 3, {'label': 'Sin destino', 'link': ''}),
      block('d', 'divider', 4, {
        'thickness': 4,
        'widthPct': 0.5,
        'color': '#80FF0000',
      }),
      block('js', 'button', 5, {
        'label': 'Truco',
        'link': 'javascript:alert(1)',
      }),
      block('barlow', 'text', 6, {
        'text': 'Barlow',
        'preset': 'heading',
        'formatting': {'fontFamily': 'Barlow', 'fontWeight': 7},
      }),
      block('last', 'text', 7, {'text': 'Uno\n'}),
      block('mail', 'button', 8, {
        'label': 'Escríbenos',
        'link': 'mailto:taller@example.com',
      }),
    ];

    test('draws text, buttons and dividers under the fixed header, with '
        "the page's own title and description", () async {
      final reads = _FakeReads(
        editorPages: {
          'arriendo': page(blocks, metaDescription: 'Bicicletas por día.'),
        },
      );
      final response = await _get(reads, '/pagina/arriendo');
      final html = await response.readAsString();

      expect(response.statusCode, 200);
      expect(response.headers['x-storefront-uncovered'], isNull);
      expect(reads.requested, ['pagina:arriendo']);
      expect(
        html,
        contains('<title>Arriendo de bicicletas | Viñabike</title>'),
      );
      expect(html, contains('content="Bicicletas por día."'));
      expect(html, contains('href="https://vinabike.cl/pagina/arriendo"'));
      expect(html, contains('content="index,follow"'));
      // Only the home's header floats over its first block.
      expect(html, isNot(contains('<header class="top over">')));
      // The editor's default column: 800 wide; Oswald drawn at its regular
      // instance and emboldened, as Flutter draws its variable file.
      expect(
        html,
        contains(
          '<h2 class="txt heading" style="width:min(800px,100%);'
          'font-weight:400;-webkit-text-stroke:.032em currentColor">'
          'Arriendo por día</h2>',
        ),
      );
      // Another family draws the weight asked (Barlow has a file for it).
      expect(
        html,
        contains(
          'font-weight:800;font-family:&quot;Barlow&quot;,var(--head)">'
          'Barlow</h2>',
        ),
      );
      // A last line break is one more line in Flutter.
      expect(html, contains('data-break>Uno&#10;</p>'));
      // Only an absolute http(s) link leaves the store, as in Flutter: any
      // other scheme is a path inside it.
      expect(html, isNot(contains('href="javascript:')));
      expect(html, contains('href="/javascript:alert(1)">Truco</a>'));
      // An e-mail or phone link opens the visitor's app.
      expect(html, contains('href="mailto:taller@example.com">Escríbenos</a>'));
      // The text is written whole: its line break is a reference (the
      // renderer indents every line it prints), its markup escaped.
      expect(
        html,
        contains(
          '<p class="txt paragraph" style="width:min(600px,100%);'
          'text-align:center;font-weight:700;color:rgb(21 101 192)">'
          'Casco incluido.&#10;Devuelve antes de las &lt;19:00&gt; &amp; '
          'listo.</p>',
        ),
      );
      expect(
        html,
        contains(
          '<a class="w-btn b-blk outline" href="/contacto">Reservar</a>',
        ),
      );
      // A button with nowhere to go is not drawn; its place keeps the space
      // after it, as Flutter's empty block.
      expect(html, isNot(contains('Sin destino')));
      expect(RegExp(r'data-block="button"').allMatches(html), hasLength(4));
      // Flutter reads the color alpha first.
      expect(
        html,
        contains('width:50%;height:4px;background:rgb(255 0 0 / 0.502)'),
      );
    });

    test('a block the HTML does not draw yet, or one with a surface of its '
        'own, leaves the page to Flutter', () async {
      final flutter = _FakeFlutterShell();
      for (final extra in [
        block('faq', 'faq', 9, {'title': 'Preguntas'}),
        block('framed', 'text', 9, {
          'text': 'Con fondo',
          'style': {'backgroundColor': '#FFEEDD'},
        }),
        block('phone', 'divider', 9, {
          'responsive': {
            'mobile': {'surfacePaddingTop': 16},
          },
        }),
      ]) {
        final reads = _FakeReads(
          editorPages: {
            'arriendo': page([...blocks, extra]),
          },
        );
        final public = await _get(
          reads,
          '/pagina/arriendo',
          flutterShell: flutter,
        );
        expect(public.headers['x-storefront-fallback'], 'flutter');
        expect(public.headers['x-storefront-uncovered'], extra['block_type']);
        final hidden = await _get(
          reads,
          '/_html/pagina/arriendo',
          flutterShell: flutter,
        );
        expect(hidden.statusCode, 200);
        expect(await hidden.readAsString(), contains('Arriendo por día'));
      }
      // A button's scalar `style` is its variant, never a surface.
      final button = await _get(
        _FakeReads(
          editorPages: {
            'arriendo': page([blocks[2]]),
          },
        ),
        '/pagina/arriendo',
        flutterShell: flutter,
      );
      expect(button.headers['x-storefront-fallback'], isNull);
    });

    test('a page that does not exist answers 404, an upper-case slug the '
        'lower-case page Flutter reads', () async {
      final reads = _FakeReads(editorPages: {'arriendo': page(blocks)});
      final missing = await _get(reads, '/pagina/otra');
      expect(missing.statusCode, 404);

      final upper = await _get(reads, '/pagina/Arriendo?x=1');
      expect(upper.statusCode, 301);
      expect(upper.headers['location'], '/pagina/arriendo?x=1');
    });

    test(
      'a page without blocks is under construction and not indexed',
      () async {
        final response = await _get(
          _FakeReads(editorPages: {'arriendo': page(const [])}),
          '/pagina/arriendo',
        );
        final html = await response.readAsString();

        expect(response.statusCode, 200);
        expect(html, contains('Esta página está en construcción'));
        expect(html, contains('content="noindex,follow"'));
      },
    );
  });

  test('every stylesheet closes what it opens', () {
    // A stray «}» at the end of the shared stylesheet swallowed the first
    // rule of the next one (2026-10-05): the page theme never applied.
    void balanced(String name, String css) {
      var depth = 0;
      for (final char
          in css.replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '').split('')) {
        if (char == '{') depth++;
        if (char == '}') depth--;
        expect(depth, greaterThanOrEqualTo(0), reason: '$name closes early');
      }
      expect(depth, 0, reason: '$name leaves a rule open');
    }

    balanced(
      'storefrontCss',
      storefrontCss(
        primary: '#123f68',
        accent: '#ff6f00',
        headingFont: 'Oswald',
        bodyFont: 'Barlow',
      ),
    );
    balanced(
      'policyPageCss',
      policyPageCss(WebsiteThemeRoles.resolve((_) => '')),
    );
    balanced('homePageCss', homePageCss(WebsiteThemeRoles.resolve((_) => '')));
    balanced(
      'editorPageEmptyCss',
      editorPageEmptyCss(WebsiteThemeRoles.resolve((_) => '')),
    );
  });

  group('cart', () {
    const gone = '6f1d2a3e-0000-4000-8000-00000000dead';
    final fork = {
      ..._product(),
      'tax_rate': 19,
      'stock_quantity': 2,
      'inventory_qty': 2,
    };
    final cassette = {
      ..._product(name: 'Cassette Eclipse 8v', sku: 'C8'),
      'id': '6f1d2a3e-0000-4000-8000-000000000008',
      'price': 35000,
      'tax_rate': 19,
    };

    Future<Map<String, dynamic>> lines(
      String l, {
      List<Object?>? products,
    }) async {
      final response = await _get(
        _FakeReads(products: products ?? [fork, cassette]),
        '/carrito/lineas?l=${Uri.encodeQueryComponent(l)}',
      );
      expect(response.statusCode, 200);
      expect(response.headers['content-type'], startsWith('application/json'));
      expect(response.headers['cache-control'], 'no-store');
      return jsonDecode(await response.readAsString()) as Map<String, dynamic>;
    }

    test(
      'the page is the frame, never indexed; its script asks for the lines',
      () async {
        final response = await _get(_FakeReads(), '/carrito');
        final html = await response.readAsString();

        expect(response.statusCode, 200);
        expect(html, contains('<meta name="robots" content="noindex,follow"'));
        expect(
          html,
          contains('href="https://vinabike.cl/carrito" rel="canonical"'),
        );
        expect(html, contains('data-lines-url="/carrito/lineas"'));
        expect(html, contains('Tu carrito está vacío'));
        // The cart's script runs after the page script that owns the document.
        expect(
          html.indexOf('window.vinabikeCart = {'),
          lessThan(html.indexOf('var cart = window.vinabikeCart;')),
        );
      },
    );

    test(
      'a saved line is kept to the stock, a missing product leaves',
      () async {
        final data = await lines('${fork['id']}:5,$gone:1,${cassette['id']}:1');

        expect(data['lines'], [
          {'id': fork['id'], 'q': 2, 'limit': 2},
          {'id': cassette['id'], 'q': 1, 'limit': 2},
        ]);
        expect(data['gone'], [gone]);
        expect(data['adjusted'], 2);
        expect(data['units'], 3);
        expect(data['unitsText'], '3 unidades en revisión');
        expect(data['payable'], isTrue);
        final items = data['items'] as String;
        expect(items, contains('HORQUILLA SUNTOUR 29 AURON 35'));
        expect(
          items,
          contains('data-act="inc" aria-label="Agregar una unidad" disabled'),
        );
        expect(items, isNot(contains('Stock insuficiente')));
        final summary = data['summary'] as String;
        // 2 × 550.000 + 35.000, IVA included, by line.
        expect(summary, contains('<b>\$ 1.135.000</b>'));
        expect(summary, contains('IVA incluido (19%)'));
        expect(summary, contains('href="/checkout"'));
      },
    );

    test(
      'without a tax rate the cart shows the gross and blocks payment',
      () async {
        final data = await lines(
          '${cassette['id']}:1',
          products: [
            {...cassette}..remove('tax_rate'),
          ],
        );
        final summary = data['summary'] as String;

        expect(data['payable'], isFalse);
        expect(summary, contains('TOTAL PRODUCTOS'));
        expect(
          summary,
          contains('<button class="cs-pay" type="button" disabled>'),
        );
        expect(summary, isNot(contains('href="/checkout"')));
      },
    );

    test('saved lines are read as Flutter reads them', () {
      expect(parseSavedCartLines('a:2,b:x,a:5,c:0,,d:1:2,e:3'), [
        (id: 'a', quantity: 5),
        (id: 'e', quantity: 3),
      ]);
    });
  });

  group('checkout', () {
    final cassette = {
      ..._product(name: 'Cassette Eclipse 8v', sku: 'C8'),
      'id': '6f1d2a3e-0000-4000-8000-000000000008',
      'price': 35000,
      'tax_rate': 19,
    };
    const both = {
      'schemaVersion': 1,
      'methods': [
        {'code': 'mercadopago', 'available': true, 'reasonCode': 'available'},
        {'code': 'transfer', 'available': true, 'reasonCode': 'available'},
      ],
    };

    test('the form is the same for everyone, never indexed, with the store\'s '
        'payment methods and pickup point', () async {
      final response = await _get(_FakeReads(payments: both), '/checkout');
      final html = await response.readAsString();

      expect(response.statusCode, 200);
      expect(html, contains('<meta name="robots" content="noindex,follow"'));
      expect(
        html,
        contains('href="https://vinabike.cl/checkout" rel="canonical"'),
      );
      expect(html, contains('data-lines-url="/checkout/lineas"'));
      expect(html, contains('data-sb-url="https://example.invalid"'));
      expect(html, contains('data-sb-key="test"'));
      expect(
        html,
        contains(
          'data-pickup-address="Retiro en tienda: Alvarez 32, Viña del Mar"',
        ),
      );
      expect(html, contains('name="payment" value="mercadopago" checked'));
      expect(html, contains('name="payment" value="transfer"'));
      expect(html, contains('RECOMENDADO'));
      expect(html, contains('Retiro en Viñabike'));
      // Records, then the page, both after the script that owns the cart.
      final owner = html.indexOf('window.vinabikeCart = {');
      final records = html.indexOf('window.vinabikeCheckoutRecords = function');
      final page = html.indexOf('var R = window.vinabikeCheckoutRecords(');
      expect(owner, greaterThan(0));
      expect(records, greaterThan(owner));
      expect(page, greaterThan(records));
    });

    test('the hidden copy asks the hidden lines', () async {
      final response = await _get(
        _FakeReads(payments: both),
        '/_html/checkout',
      );
      expect(
        await response.readAsString(),
        contains('data-lines-url="/_html/checkout/lineas"'),
      );
    });

    test(
      'without the payment methods the form says so instead of guessing',
      () async {
        final response = await _get(_FakeReads(), '/checkout');
        final html = await response.readAsString();
        expect(
          html,
          contains('No pudimos verificar los medios de pago disponibles.'),
        );
        expect(html, isNot(contains('name="payment"')));
      },
    );

    test('the lines carry what the order states of each one', () async {
      final response = await _get(
        _FakeReads(products: [cassette]),
        '/checkout/lineas?l=${cassette['id']}:2',
      );
      expect(response.headers['cache-control'], 'no-store');
      final data =
          jsonDecode(await response.readAsString()) as Map<String, dynamic>;

      expect(data['valid'], isTrue);
      expect(data['gross'], 70000);
      expect(data['net'], 58824);
      expect(data['tax'], 11176);
      expect(data['items'], [
        {
          'product_id': cassette['id'],
          'product_name': 'Cassette Eclipse 8v',
          'product_sku': 'C8',
          'quantity': 2,
          'unit_price': 35000.0,
          'subtotal': 70000.0,
        },
      ]);
      expect(data['rows'], contains('Cantidad: 2'));
      expect(data['rows'], contains('\$ 70.000'));
    });

    test(
      'without a tax rate the order is blocked, the gross still known',
      () async {
        final response = await _get(
          _FakeReads(
            products: [
              {...cassette}..remove('tax_rate'),
            ],
          ),
          '/checkout/lineas?l=${cassette['id']}:1',
        );
        final data =
            jsonDecode(await response.readAsString()) as Map<String, dynamic>;
        expect(data['valid'], isFalse);
        expect(data['gross'], isNull);
        expect(data['knownGross'], 35000);
        expect(data['block'], isNotEmpty);
      },
    );
  });

  group('order page', () {
    const order = '0d000000-0000-4000-8000-000000000021';
    final token = 'od-test-token-${'x' * 40}';
    Map<String, Object?> envelope({String id = order}) => {
      'order': {
        'id': id,
        'number': 'WEB-26-00021',
        'status': 'confirmed',
        'paymentStatus': 'pending',
        'paymentMethod': 'transfer',
        'deliveryType': 'pickup',
        'createdAt': '2026-10-06T08:30:00.123456+00:00',
        'updatedAt': '2026-10-06T08:31:00+00:00',
        'subtotal': 74790,
        'taxAmount': 14210,
        'shippingCost': 0,
        'discountAmount': 0,
        'total': 89000,
      },
      'items': [
        {
          'name': 'Cassette Eclipse 8v',
          'sku': 'C8',
          'quantity': 1,
          'unitPrice': 89000,
          'subtotal': 89000,
          'taxRate': 19,
        },
      ],
      'storefront': {'schemaVersion': 1, 'displayName': 'Viñabike'},
    };
    Map<String, dynamic> transferShell() {
      final shell = _shell();
      (shell['settings'] as Map<String, String>).addAll(<String, String>{
        'payment_transfer_bank_name': 'Banco de Chile',
        'payment_transfer_account_type': 'Cuenta corriente',
        'payment_transfer_account_number': '81522258',
        'payment_transfer_account_holder': 'NEWEN SpA',
        'payment_transfer_rut': '77.541.999-7',
        'payment_transfer_contact_email': 'contacto@vinabike.cl',
      });
      return shell;
    }

    test('the frame is the same for everyone, never indexed, with the '
        'store\'s transfer details', () async {
      final response = await _get(
        _FakeReads(shell: transferShell()),
        '/pedido/$order',
      );
      final html = await response.readAsString();

      expect(response.statusCode, 200);
      expect(html, contains('<meta name="robots" content="noindex,follow"'));
      expect(html, contains('data-order="$order"'));
      expect(html, contains('data-pdf-url="/pedido/resumen.pdf"'));
      expect(html, contains('<dt>BANCO</dt><dd>Banco de Chile</dd>'));
      expect(html, contains('<dt>CUENTA CORRIENTE</dt><dd>81522258</dd>'));
      expect(
        html,
        contains(
          'envía el comprobante a contacto@vinabike.cl con tu número de '
          'pedido.',
        ),
      );
      expect(html, isNot(contains('Nuestro equipo te compartirá')));
      // No order, customer or token in the page the server sends.
      expect(html, isNot(contains('WEB-26-00021')));
      final owner = html.indexOf('window.vinabikeCart = {');
      final records = html.indexOf('window.vinabikeCheckoutRecords = function');
      final page = html.indexOf("root.dataset.order");
      expect(owner, greaterThan(0));
      expect(records, greaterThan(owner));
      expect(page, greaterThan(records));
    });

    test('without transfer details it says the team will send them', () async {
      final html = await (await _get(
        _FakeReads(),
        '/_html/pedido/$order',
      )).readAsString();
      expect(html, contains('Nuestro equipo te compartirá'));
      expect(html, contains('data-pdf-url="/_html/pedido/resumen.pdf"'));
    });

    test('an id that is not an order id is a page that is not there', () async {
      final response = await _get(_FakeReads(), '/pedido/a.b');
      expect(response.statusCode, 404);
    });

    test(
      'the summary PDF is drawn from the access, sent in the body',
      () async {
        final reads = _FakeReads(orders: {token: envelope()});
        final response = await _get(
          reads,
          '/pedido/resumen.pdf',
          method: 'POST',
          headers: {'content-type': 'application/json'},
          body: jsonEncode({'order_id': order, 'access_token': token}),
        );
        final bytes = await response.read().expand((chunk) => chunk).toList();

        expect(response.statusCode, 200);
        expect(response.headers['content-type'], 'application/pdf');
        expect(
          response.headers['content-disposition'],
          'attachment; filename="pedido_WEB-26-00021.pdf"',
        );
        expect(response.headers['cache-control'], 'no-store');
        expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
        expect(bytes.length, greaterThan(5000));
      },
    );

    test('the PDF needs that order\'s access and a POST', () async {
      final reads = _FakeReads(orders: {token: envelope(id: 'other')});
      Future<int> post(Object body) async => (await _get(
        reads,
        '/pedido/resumen.pdf',
        method: 'POST',
        body: jsonEncode(body),
      )).statusCode;

      expect(await post({'order_id': order, 'access_token': token}), 404);
      expect(await post({'order_id': order, 'access_token': 'short'}), 400);
      expect(await post({'order_id': 'a/b', 'access_token': token}), 400);
      expect((await _get(reads, '/pedido/resumen.pdf')).statusCode, 405);
    });
  });

  group('header', () {
    Map<String, dynamic> withMenu(List<Map<String, Object>> rows) {
      final shell = _shell();
      shell['navigation'] = [...(shell['navigation'] as List), ...rows];
      return shell;
    }

    test('the phone sheet follows Flutter\'s projection: a published '
        'category whose children are all hidden is a plain link', () async {
      final shell = withMenu([
        {
          'id': 'n4',
          'menu_location': 'header',
          'label': 'Accesorios',
          'link_type': 'category',
          'link_value': _parent,
          'order_index': 4,
        },
        {
          'id': 'n5',
          'menu_location': 'header',
          'parent_id': 'n4',
          'label': 'Interna',
          'link_type': 'category',
          'link_value': _hidden,
          'order_index': 1,
        },
      ]);
      final html = await (await _get(
        _FakeReads(shell: shell),
        '/productos',
      )).readAsString();
      final start = html.indexOf('class="menu-sheet"');
      final sheet = html.substring(start, html.indexOf('</nav>', start));
      expect(sheet, isNot(contains('Ver todo Accesorios')));
      expect(sheet, isNot(contains('>Interna<')));
      // A link row, not a group (`<summary>`) with «Ver todo».
      expect(
        RegExp(
          r'<a class="sheet-item"[^>]*href="/productos/categoria/[^"]+"[^>]*>'
          r'\s*<svg[\s\S]*?</svg>\s*<span>Accesorios</span>',
        ).hasMatch(sheet),
        isTrue,
      );
      expect(sheet, isNot(contains('<summary')));
      // Page links keep their page (Contacto), drafts stay out.
      expect(sheet, contains('>Contacto<'));
      expect(sheet, isNot(contains('Página borrador')));
    });

    Map<String, dynamic> wideMenu({String? css = 'megamenu'}) {
      final shell = withMenu([
        {
          'id': 'n4',
          'menu_location': 'header',
          'label': 'Componentes',
          'link_type': 'category',
          'link_value': _parent,
          'order_index': 4,
          'css_class': ?css,
        },
        for (final (id, parent, label, order) in [
          ('n5', 'n4', 'Suspensión', 1),
          ('n6', 'n5', 'Horquillas', 1),
          ('n8', 'n6', 'Horquillas rígidas', 1),
          ('n7', 'n4', 'Frenos', 2),
        ])
          {
            'id': id,
            'menu_location': 'header',
            'parent_id': parent,
            'label': label,
            'link_type': 'category',
            'link_value': _child,
            'order_index': order,
          },
      ]);
      (shell['settings']
          as Map)[websiteCatalogPresentationsSettingKey] = jsonEncode({
        'items': [
          {
            'category_id': _child,
            'slug': 'horquillas',
            'mega_menu_image_url': 'https://img.example/suspension.webp',
            'mega_menu_overlay': 0.5,
            'mega_menu_card_overlay': 0.2,
            'mega_menu_overview_width': 330,
            'mega_menu_content_alignment': 'center',
          },
        ],
      });
      return shell;
    }

    Future<String> desktopMenu(Map<String, dynamic> shell) async {
      final html = await (await _get(
        _FakeReads(shell: shell),
        '/productos',
      )).readAsString();
      final start = html.indexOf('<nav class="menu"');
      return html.substring(start, html.indexOf('<div class="tools">', start));
    }

    test('an item marked «megamenu» opens Flutter\'s wide panel: a tab per '
        'branch, the section\'s photo, its cards and a level per card with '
        'subcategories', () async {
      final menu = await desktopMenu(wideMenu());
      // The trigger is a button, as Flutter's; the page is «VER TODO».
      expect(
        menu,
        contains(
          '<button class="mega-btn" type="button" aria-expanded="false" '
          'aria-controls="mega-n4">Componentes</button>',
        ),
      );
      expect(
        menu,
        matches(
          RegExp(
            r'class="mega-all mega-link" href="/productos/categoria/componentes"',
          ),
        ),
      );
      // The first branch with children is open; a leaf branch is a tab too.
      expect(
        menu,
        matches(
          RegExp(
            r'<a class="mega-tab on" data-branch="n5" href="/productos/categoria/horquillas">\s*<span>SUSPENSIÓN</span>',
          ),
        ),
      );
      expect(menu, contains('<a class="mega-tab" data-branch="n7"'));
      expect(menu, contains('<section class="mega-branch" data-branch="n5">'));
      expect(
        menu,
        contains('<section class="mega-branch" data-branch="n7" hidden>'),
      );
      // «Catálogo web»: photo, veil, width and alignment of the section.
      expect(menu, contains('class="mega-ov photo" style="width:330px"'));
      expect(menu, contains('alt="Imagen de Suspensión"'));
      expect(menu, contains('src="https://img.example/suspension.webp"'));
      expect(
        menu,
        contains(
          'linear-gradient(90deg,rgb(0 0 0 / 0.5) 0%,rgb(0 0 0 / 0.17) 48%,transparent 86%)',
        ),
      );
      expect(menu, contains('justify-content:center'));
      expect(menu, contains('Explorar Suspensión'));
      // A card leads to its products; its caption opens its subcategories.
      expect(menu, contains('aria-label="Ver productos de Horquillas"'));
      expect(menu, contains('background:rgb(0 0 0 / 0.2)'));
      expect(
        menu,
        matches(
          RegExp(
            r'<button class="mega-cap" type="button" data-open="n6" aria-label="Ver las 1 subcategorías de Horquillas">\s*<span>1 SUBCATEGORÍA</span>',
          ),
        ),
      );
      expect(menu, contains('<div class="mega-level" data-level="n6" hidden>'));
      expect(menu, matches(RegExp(r'<span>Volver a Suspensión</span>')));
      expect(menu, contains('VER TODO EN HORQUILLAS'));
    });

    test('an item with children but no «megamenu» opens the compact list, '
        'and the panel\'s styles and script come only with a menu', () async {
      final menu = await desktopMenu(wideMenu(css: null));
      expect(menu, contains('<li class="has-drop" data-drop>'));
      expect(menu, contains('VER TODO COMPONENTES'));
      expect(menu, isNot(contains('mega-branch')));
      final plain = await (await _get(
        _FakeReads(),
        '/productos',
      )).readAsString();
      expect(plain, isNot(contains('.mega{')));
      expect(plain, isNot(contains('[data-mega]')));
      final withMenu = await (await _get(
        _FakeReads(shell: wideMenu()),
        '/productos',
      )).readAsString();
      expect(withMenu, contains('.mega{'));
      expect(withMenu, contains("querySelectorAll('[data-mega]')"));
    });

    test('a signed-in customer is drawn by the page script, from the '
        'session Flutter keeps', () async {
      final html = await (await _get(
        _FakeReads(),
        '/productos',
      )).readAsString();
      expect(html, contains('class="acct" data-acct hidden'));
      expect(html, contains('role="menuitem" href="/cuenta/pedidos"'));
      expect(html, contains('data-act="sign-out"'));
      expect(
        html,
        contains('class="sheet-item sheet-account" hidden href="/cuenta"'),
      );
      // The body tells the page script where the session lives.
      expect(
        html,
        contains('document.body.dataset.sbUrl="https://example.invalid"'),
      );
      expect(
        accountSessionKey('https://abcd1234.supabase.co'),
        'sb-abcd1234-auth-token',
      );
      expect(html, contains('"sb-example-auth-token"'));
    });
  });

  group('portal', () {
    setUpAll(usePortalTimeZone);
    // An invented session: the server only reads its `sub` for the filter;
    // the fake reads stand for Supabase, which checks the signature.
    String token() {
      String b64(Map<String, Object?> v) =>
          base64Url.encode(utf8.encode(jsonEncode(v))).replaceAll('=', '');
      return '${b64({'alg': 'HS256'})}.'
          '${b64({'sub': '7e570000-0000-4000-8000-0000000000aa'})}.'
          '${'x' * 43}';
    }

    const customer = '7e570000-0000-4000-8000-0000000000ab';
    const bike = 'b1000000-0000-4000-8000-000000000001';
    CustomerPortalReads portal({
      Map<String, dynamic>? profile = const {
        'id': customer,
        'tenant_id': _tenant,
        'auth_user_id': '7e570000-0000-4000-8000-0000000000aa',
        'name': 'Ana Prueba',
        'email': 'ana@example.invalid',
        'phone': '+56 9 1234 5678',
        'created_at': '2026-01-01T00:00:00Z',
      },
      List<Object?> jobs = const [],
      List<Object?> orders = const [],
      List<Object?> addresses = const [_addressRow],
    }) => (
      shell: _shell(),
      profile: profile,
      addresses: addresses,
      orders: orders,
      bikes: const [
        {
          'id': bike,
          'brand': 'Besatti',
          'model': 'Priore',
          'bike_type': 'mountain_hardtail',
          'color': 'negra',
          'wheel_size': '27.5',
          'warranty_until': '2027-03-01',
          'bike_brands': {'name': 'Besatti'},
          'bike_models': {'name': 'Priore'},
        },
      ],
      jobs: jobs,
      jobBikes: const [
        {
          'id': bike,
          'brand': 'Besatti',
          'model': 'Priore',
          'color': 'negra',
          'bike_type': 'mountain_hardtail',
          'wheel_size': '27.5',
        },
      ],
      productImages: const [],
      jobFiles: const {},
    );

    Future<Map<String, Object?>> view(
      _FakeReads reads,
      String page, {
      String query = '',
      String? auth,
    }) async {
      final response = await _get(
        reads,
        portalViewPath,
        method: 'POST',
        headers: {
          'authorization': auth ?? 'Bearer ${token()}',
          'content-type': 'application/json',
        },
        body: jsonEncode({'path': page, 'query': query}),
      );
      expect(response.headers['cache-control'], 'no-store');
      expect(response.headers['x-robots-tag'], 'noindex');
      return jsonDecode(await response.readAsString()) as Map<String, Object?>;
    }

    test(
      'the frame is the way in, with no data, no index and no store '
      'footer; a session switches it to «Preparando» before painting',
      () async {
        for (final path in [
          '/cuenta',
          '/cuenta/pedidos',
          '/cuenta/servicios',
          '/cuenta/bicicletas',
        ]) {
          final response = await _get(_FakeReads(), path);
          expect(response.statusCode, 200, reason: path);
          final html = await response.readAsString();
          expect(html, contains('data-portal-root'));
          expect(html, contains('data-view-url="/cuenta/vista"'));
          expect(html, contains('data-portal="signedOut"'));
          expect(html, contains('data-portal="loading" hidden'));
          expect(html, contains('data-portal="notCustomer" hidden'));
          expect(html, contains('Entra a tu cuenta'));
          expect(html, contains('href="/cuenta/login"'));
          expect(html, contains('noindex'));
          expect(html, isNot(contains('class="foot')));
          expect(html, contains('"sb-example-auth-token"'));
        }
        final hidden = await (await _get(
          _FakeReads(),
          '/_html/cuenta',
        )).readAsString();
        expect(hidden, contains('data-view-url="/_html/cuenta/vista"'));
      },
    );

    test('the view needs a session and a portal page', () async {
      final reads = _FakeReads(portal: portal());
      expect((await view(reads, '/cuenta', auth: ''))['state'], 'invalid');
      expect((await view(reads, '/cuenta/chats'))['state'], 'invalid');
      expect(
        (await _get(reads, portalViewPath)).statusCode,
        405,
        reason: 'a GET',
      );
    });

    test('a refused session asks for a renewal; one that is not a customer '
        'is told so', () async {
      expect((await view(_FakeReads(), '/cuenta'))['state'], 'expired');
      expect(
        (await view(
          _FakeReads(portal: portal(profile: null)),
          '/cuenta',
        ))['state'],
        'not-customer',
      );
      expect(
        (await view(_FakeReads(fail: true), '/cuenta'))['state'],
        'not-customer',
      );
    });

    test(
      'the summary greets the customer and says what waits for them',
      () async {
        final html =
            (await view(
                  _FakeReads(
                    portal: portal(
                      jobs: const [
                        {
                          'id': 'j1000000-0000-4000-8000-000000000001',
                          'bike_id': bike,
                          'job_number': 'PG-00493',
                          'status': 'ESPERANDO_APROBACION',
                          'client_request': 'Frena poco atrás',
                          'total_cost': 48500,
                          'arrival_date': '2026-08-05',
                          'created_at': '2026-08-05T15:00:00Z',
                          'image_urls': [],
                        },
                      ],
                    ),
                  ),
                  '/cuenta',
                ))['html']
                as String;
        expect(html, contains('data-portal="ready"'));
        expect(html, contains('Hola, Ana'));
        expect(html, contains('Cliente desde diciembre de 2025'));
        expect(html, contains('Para ti ahora'));
        expect(
          html,
          contains('Presupuesto de \$ 48.500 por frena poco atrás.'),
        );
        expect(html, contains('Responder al taller'));
        expect(html, contains('Tus bicicletas'));
        expect(html, contains('<dialog id="pt-sheet-'));
        expect(html, contains('Garantía hasta el 1 mar 2027'));
        // The tabs, with Resumen open, and the service band.
        expect(
          html,
          contains('class="pt-tab on" aria-current="page" href="/cuenta"'),
        );
        expect(html, contains('Habla con el taller'));
      },
    );

    test(
      'the workshop draws every bike view and opens the one asked for',
      () async {
        final html =
            (await view(
                  _FakeReads(
                    portal: portal(
                      jobs: const [
                        {
                          'id': 'j1000000-0000-4000-8000-000000000002',
                          'bike_id': bike,
                          'job_number': 'PG-00100',
                          'status': 'ENTREGADO',
                          'client_request': 'Cambio de cadena',
                          'total_cost': 12000,
                          'arrival_date': '2025-12-28',
                          'created_at': '2025-12-28T15:00:00Z',
                        },
                      ],
                    ),
                  ),
                  '/cuenta/servicios',
                  query: 'bike_id=$bike',
                ))['html']
                as String;
        expect(html, contains('class="pt-back"'));
        expect(html, contains('data-view="all" hidden'));
        expect(html, contains('data-view="$bike"'));
        expect(html, isNot(contains('data-view="$bike" hidden')));
        expect(html, contains('Historial'));
        expect(html, contains('28 dic 2025'));
      },
    );

    test('an instant becomes the store\'s date; a date stays as it is', () {
      // 02:30 UTC on the 6th is still the 5th in Santiago (UTC−3/−4).
      expect(portalDate(DateTime.parse('2026-10-06T02:30:00Z')), '5 oct 2026');
      expect(portalDate(DateTime.parse('2026-10-06')), '6 oct 2026');
    });

    test('the bike drawing is the shared strokes as SVG', () {
      final svg = customerBikeSvg(CustomerBikeSilhouette.road);
      expect(svg, startsWith('<svg viewBox="0 0 220 132"'));
      expect(svg, contains('stroke-linecap="round"'));
      expect(svg, contains('Q164 78 174 92'));
      expect(customerBikeSvg(CustomerBikeSilhouette.city), contains('A41 41'));
    });

    // ------------------------------------------------------------ 4b

    Future<Map<String, Object?>> action(
      _FakeReads reads,
      String page,
      String name, [
      Map<String, Object?> values = const {},
    ]) async {
      final response = await _get(
        reads,
        portalActionPath,
        method: 'POST',
        headers: {
          'authorization': 'Bearer ${token()}',
          'content-type': 'application/json',
        },
        body: jsonEncode({'path': page, 'action': name, 'values': values}),
      );
      expect(response.headers['cache-control'], 'no-store');
      return jsonDecode(await response.readAsString()) as Map<String, Object?>;
    }

    test('the profile and addresses frames send their forms to the server; '
        'only the addresses page loads the Places client', () async {
      for (final path in ['/cuenta/perfil', '/cuenta/direcciones']) {
        final html = await (await _get(_FakeReads(), path)).readAsString();
        expect(
          html,
          contains('data-action-url="/cuenta/accion"'),
          reason: path,
        );
        expect(html, contains('data-portal="signedOut"'), reason: path);
        expect(
          html.contains('google-places-proxy'),
          path == '/cuenta/direcciones',
          reason: path,
        );
      }
    });

    test('the profile shows the facts, the form in place and the password '
        'dialog with its three steps', () async {
      final reads = _FakeReads(portal: portal());
      final html = (await view(reads, '/cuenta/perfil'))['html'] as String;
      expect(reads.requested, contains('portal without files'));
      expect(html, contains('Perfil y seguridad'));
      expect(html, contains('Para tus boletas'));
      // RUT is empty: the row says «AGREGAR» and opens the form.
      expect(html, contains('class="pt-prow-add" aria-label="Agregar"'));
      expect(html, contains('data-form="profile"'));
      expect(html, contains('data-required="Escribe tu nombre"'));
      expect(html, contains('placeholder="12.345.678-9"'));
      expect(html, contains('value="Ana Prueba"'));
      expect(html, contains('Cambiar contraseña'));
      expect(html, contains('Verifica que eres tú'));
      expect(html, contains('Completar seguridad'));
      expect(html, contains(AuthInputValidation.strongPasswordHelper));
      expect(html, contains('Cambia la contraseña con que entras a la tienda'));
      expect(html, isNot(contains('Quedó pendiente cerrar')));
      final pendingResponse = await _get(
        reads,
        portalViewPath,
        method: 'POST',
        headers: {
          'authorization': 'Bearer ${token()}',
          'content-type': 'application/json',
        },
        body: jsonEncode({'path': '/cuenta/perfil', 'pending': true}),
      );
      final pending =
          (jsonDecode(await pendingResponse.readAsString()) as Map)['html']
              as String;
      expect(pending, contains('Quedó pendiente cerrar las demás sesiones.'));
      expect(pending, contains('Tu nueva contraseña ya está activa'));
      expect(pending, contains('data-step-to="revocation"'));
    });

    test('the addresses show each row with what its form and menu need, or '
        'the empty state', () async {
      final html =
          (await view(
                _FakeReads(portal: portal()),
                '/cuenta/direcciones',
              ))['html']
              as String;
      expect(
        html,
        contains('La principal aparece primero al pagar un pedido.'),
      );
      expect(html, contains('Agregar dirección'));
      expect(html, contains('Avenida Libertad 1234, Viña del Mar, Valparaíso'));
      expect(html, contains('Ana Prueba · +56 9 1234 5678'));
      expect(html, contains('data-delete-title="¿Eliminar «Casa»?"'));
      expect(html, contains('&quot;profile_contact&quot;:true'));
      expect(html, contains('aria-label="Opciones de Casa"'));
      expect(html, contains('Usar como principal'));
      expect(html, contains('Nueva dirección'));
      expect(html, contains('Buscar dirección en Google Maps'));
      expect(html, contains('data-required="Requerido"'));
      final empty =
          (await view(
                _FakeReads(portal: portal(addresses: const [])),
                '/cuenta/direcciones',
              ))['html']
              as String;
      expect(empty, contains('No tienes direcciones guardadas.'));
      expect(empty, contains('Agregar la primera dirección'));
      expect(empty, contains('Dónde te enviamos tus pedidos.'));
    });

    test('saving the profile checks the name, writes only the profile '
        'columns of this customer in this store and draws the page', () async {
      final reads = _FakeReads(portal: portal());
      expect(
        (await action(reads, '/cuenta/perfil', 'profile', {
          'name': '  ',
        }))['errors'],
        {'name': 'Escribe tu nombre'},
      );
      expect(reads.writes, isEmpty);
      final saved = await action(reads, '/cuenta/perfil', 'profile', {
        'name': ' Ana María ',
        'rut': '',
        'phone': '+56 9 8765 4321',
        'email': 'otra@example.invalid',
      });
      expect(saved['toast'], 'Guardamos tus datos.');
      expect(saved['html'], contains('data-portal="ready"'));
      final write = reads.writes.single;
      expect(write['method'], 'PATCH');
      expect(write['table'], 'customers');
      expect(write['filters'], {
        'id': 'eq.$customer',
        'tenant_id': 'eq.$_tenant',
      });
      final body = write['body'] as Map<String, Object?>;
      expect(body['name'], 'Ana María');
      expect(body['phone'], '+56 9 8765 4321');
      // An emptied RUT is cleared, and the e-mail is never written.
      expect(body.containsKey('rut'), isTrue);
      expect(body['rut'], isNull);
      expect(body.containsKey('email'), isFalse);
      expect(
        (await action(
          _FakeReads(portal: portal(), writeOk: false),
          '/cuenta/perfil',
          'profile',
          {'name': 'Ana'},
        ))['toast'],
        'No pudimos guardar tus datos. Inténtalo nuevamente.',
      );
    });

    test(
      'an address is checked, created for this customer and store, '
      'changed, made principal or deleted only through its own row',
      () async {
        final reads = _FakeReads(portal: portal());
        final errors =
            (await action(reads, '/cuenta/direcciones', 'address-save', {
                  'label': 'Casa',
                }))['errors']
                as Map;
        expect(errors['recipient_name'], 'Requerido');
        expect(errors['comuna'], 'Requerido');
        expect(errors.containsKey('label'), isFalse);
        final values = {
          'id': '',
          'label': 'Trabajo',
          'recipient_name': 'Ana Prueba',
          'phone': '+56 9 1234 5678',
          'street_address': 'Álvarez',
          'street_number': '32',
          'apartment': '',
          'comuna': 'Viña del Mar',
          'city': 'Viña del Mar',
          'region': 'Valparaíso',
          'postal_code': '2520000',
          'additional_info': '',
          'is_default': false,
          'profile_contact': true,
        };
        final created = await action(
          reads,
          '/cuenta/direcciones',
          'address-save',
          values,
        );
        expect(created['html'], contains('data-portal="ready"'));
        final insert = reads.writes.last;
        expect(insert['method'], 'POST');
        expect(insert['table'], 'customer_addresses');
        final row = insert['body'] as Map<String, Object?>;
        expect(row['customer_id'], customer);
        expect(row['tenant_id'], _tenant);
        expect(row['apartment'], isNull);
        expect(row['is_default'], isFalse);
        expect(row['postal_code'], '2520000');
        expect(row.containsKey('profile_contact'), isFalse);

        const id = 'ad000000-0000-4000-8000-000000000001';
        await action(reads, '/cuenta/direcciones', 'address-save', {
          ...values,
          'id': id,
        });
        expect(reads.writes.last['method'], 'PATCH');
        expect(reads.writes.last['filters'], {
          'id': 'eq.$id',
          'customer_id': 'eq.$customer',
          'tenant_id': 'eq.$_tenant',
        });
        await action(reads, '/cuenta/direcciones', 'address-default', {
          'id': id,
        });
        expect(reads.writes.last['body'], {'is_default': true});
        await action(reads, '/cuenta/direcciones', 'address-delete', {
          'id': id,
        });
        expect(reads.writes.last['method'], 'DELETE');
        expect(reads.writes.last['filters'], {
          'id': 'eq.$id',
          'customer_id': 'eq.$customer',
          'tenant_id': 'eq.$_tenant',
        });
        final count = reads.writes.length;
        expect(
          (await action(reads, '/cuenta/direcciones', 'address-delete', {
            'id': 'not-an-id',
          }))['state'],
          'invalid',
        );
        expect(reads.writes.length, count);
        expect(
          (await action(
            _FakeReads(portal: portal(), writeOk: false),
            '/cuenta/direcciones',
            'address-delete',
            {'id': id},
          ))['toast'],
          'No pudimos eliminar la dirección. Intenta de nuevo.',
        );
      },
    );

    test('the password: checked first, then Auth; a code when Auth asks for '
        'one; only the sessions are retried once it changed', () async {
      var reads = _FakeReads(portal: portal());
      expect(
        (await action(reads, '/cuenta/perfil', 'password', {
          'password': 'corta1',
          'confirm': 'corta1',
        }))['errors'],
        {'password': 'La contraseña debe tener al menos 8 caracteres'},
      );
      expect(
        (await action(reads, '/cuenta/perfil', 'password', {
          'password': 'pedal2026',
          'confirm': 'pedal2025',
        }))['errors'],
        {'confirm': 'Las contraseñas no coinciden'},
      );
      expect(reads.authCalls, isEmpty);
      expect(
        await action(reads, '/cuenta/perfil', 'password', {
          'password': 'pedal2026',
          'confirm': 'pedal2026',
        }),
        {
          'done': true,
          'toast': 'Contraseña actualizada y demás sesiones cerradas.',
        },
      );
      expect(reads.authCalls.map((c) => c.$1), [
        CustomerAuthCall.updatePassword,
        CustomerAuthCall.signOutOthers,
      ]);
      expect(reads.authCalls.first.$2, {'password': 'pedal2026'});

      // The other sessions could not be closed: never the password again.
      reads = _FakeReads(
        portal: portal(),
        auth: {CustomerAuthCall.signOutOthers: null},
      );
      expect(
        await action(reads, '/cuenta/perfil', 'password', {
          'password': 'pedal2026',
          'confirm': 'pedal2026',
        }),
        {'step': 'revocation', 'pending': true},
      );
      expect(
        (await action(reads, '/cuenta/perfil', 'revoke-others'))['error'],
        contains('Reintenta desde Seguridad'),
      );
      expect(
        reads.authCalls.where((c) => c.$1 == CustomerAuthCall.updatePassword),
        hasLength(1),
      );

      // Auth asks for a code: it is mailed, then sent with the password.
      reads = _FakeReads(
        portal: portal(),
        auth: {
          CustomerAuthCall.updatePassword: (
            status: 400,
            code: 'reauthentication_needed',
            message: 'Password update requires reauthentication',
          ),
        },
      );
      expect(
        await action(reads, '/cuenta/perfil', 'password', {
          'password': 'pedal2026',
          'confirm': 'pedal2026',
        }),
        {
          'step': 'verification',
          'notice': 'Enviamos un código de verificación a tu correo asociado.',
        },
      );
      expect(
        (await action(reads, '/cuenta/perfil', 'password', {
          'password': 'pedal2026',
          'code': '12345',
        }))['errors'],
        {'code': 'Ingresa los 6 dígitos del código.'},
      );
      reads = _FakeReads(
        portal: portal(),
        auth: {
          CustomerAuthCall.updatePassword: (
            status: 400,
            code: 'reauthentication_not_valid',
            message: 'Verification code not valid',
          ),
          CustomerAuthCall.reauthenticate: (
            status: 429,
            code: 'over_email_send_rate_limit',
            message: 'rate limit',
          ),
        },
      );
      expect(
        (await action(reads, '/cuenta/perfil', 'password', {
          'password': 'pedal2026',
          'code': '123456',
        }))['error'],
        'El código no es válido. Revísalo e inténtalo nuevamente.',
      );
      expect(reads.authCalls.last.$2, {
        'password': 'pedal2026',
        'nonce': '123456',
      });
      expect(await action(reads, '/cuenta/perfil', 'password-resend'), {
        'step': 'verification',
        'error': 'Espera un momento antes de solicitar otro código.',
      });
      expect(
        (await action(
          _FakeReads(
            portal: portal(),
            auth: {
              CustomerAuthCall.updatePassword: (
                status: 422,
                code: 'same_password',
                message: 'New password should be different',
              ),
            },
          ),
          '/cuenta/perfil',
          'password',
          {'password': 'pedal2026', 'confirm': 'pedal2026'},
        ))['error'],
        'La nueva contraseña debe ser distinta a la contraseña actual.',
      );
    });

    test('after a lost answer, Auth\'s «same password» means it changed: '
        'only the other sessions are closed', () async {
      final reads = _FakeReads(
        portal: portal(),
        auth: {
          CustomerAuthCall.updatePassword: (
            status: 422,
            code: 'same_password',
            message: 'New password should be different',
          ),
        },
      );
      expect(
        await action(reads, '/cuenta/perfil', 'password', {
          'password': 'pedal2026',
          'confirm': 'pedal2026',
          'uncertain': true,
        }),
        {
          'done': true,
          'toast': 'Contraseña actualizada y demás sesiones cerradas.',
        },
      );
      expect(reads.authCalls.last.$1, CustomerAuthCall.signOutOthers);
      // A failed call marks the outcome unknown for the next attempt.
      expect(
        await action(
          _FakeReads(
            portal: portal(),
            auth: {CustomerAuthCall.updatePassword: null},
          ),
          '/cuenta/perfil',
          'password',
          {'password': 'pedal2026', 'confirm': 'pedal2026'},
        ),
        {
          'error': 'No pudimos actualizar la contraseña. Inténtalo nuevamente.',
          'uncertain': true,
        },
      );
    });

    test('a save keeps the pending notice, and a failed read before it '
        'answers Flutter\'s words in the private envelope', () async {
      final reads = _FakeReads(portal: portal());
      final response = await _get(
        reads,
        portalActionPath,
        method: 'POST',
        headers: {
          'authorization': 'Bearer ${token()}',
          'content-type': 'application/json',
        },
        body: jsonEncode({
          'path': '/cuenta/perfil',
          'action': 'profile',
          'values': {'name': 'Ana'},
          'pending': true,
        }),
      );
      final html =
          (jsonDecode(await response.readAsString()) as Map)['html'] as String;
      expect(html, contains('Quedó pendiente cerrar las demás sesiones.'));
      final failed = await _get(
        _FakeReads(fail: true),
        portalActionPath,
        method: 'POST',
        headers: {
          'authorization': 'Bearer ${token()}',
          'content-type': 'application/json',
        },
        body: jsonEncode({
          'path': '/cuenta/direcciones',
          'action': 'address-delete',
          'values': {'id': 'ad000000-0000-4000-8000-000000000001'},
        }),
      );
      expect(failed.statusCode, 200);
      expect(failed.headers['cache-control'], 'no-store');
      expect(
        (jsonDecode(await failed.readAsString()) as Map)['toast'],
        'No pudimos eliminar la dirección. Intenta de nuevo.',
      );
      final get = await _get(reads, portalActionPath);
      expect(get.statusCode, 405);
      expect(get.headers['cache-control'], 'no-store');
      expect(get.headers['x-robots-tag'], 'noindex');
    });

    // ------------------------------------------------------------ 4c

    test('the login is the HTML page: noindex, its own head, the forms, and '
        'the script that hands a fragment link back before painting', () async {
      final response = await _get(_FakeReads(), '/cuenta/login');
      expect(response.statusCode, 200);
      expect(response.headers['x-robots-tag'], 'noindex');
      final html = await response.readAsString();
      expect(html, contains('<title>Iniciar sesión | '));
      expect(
        html,
        contains('href="https://vinabike.cl/cuenta/login" rel="canonical"'),
      );
      expect(html, contains('data-login'));
      expect(html, contains('data-action-url="/cuenta/accion"'));
      expect(html, contains('method="post"'));
      expect(html, contains('Ingresa para revisar pedidos, bicicletas'));
      expect(html, contains('Crea tu cuenta para guardar tus datos'));
      expect(html, contains('Recuperar contraseña'));
      expect(html, contains('enlace'));
      expect(html, contains('class="foot'));
      final hidden = await (await _get(
        _FakeReads(),
        '/_html/cuenta/login',
      )).readAsString();
      expect(hidden, contains('data-action-url="/_html/cuenta/accion"'));
      expect(hidden, isNot(contains('vinabikeAuthHandoff=true')));
    });

    test(
      'a link back from Auth is answered with Flutter, with the login '
      'head; the hidden copy stays HTML; no Flutter page, try again',
      () async {
        for (final query in [
          'confirmed=true&code=abc',
          'error=access_denied&error_code=otp_expired',
          'enlace=1',
          'token_hash=x&type=recovery',
        ]) {
          final flutter = _FakeFlutterShell();
          final response = await _get(
            _FakeReads(),
            '/cuenta/login?$query',
            flutterShell: flutter,
          );
          expect(response.statusCode, 200, reason: query);
          expect(response.headers['x-storefront-fallback'], 'flutter');
          expect(response.headers['x-robots-tag'], 'noindex');
          final html = await response.readAsString();
          expect(html, contains('flutter_bootstrap.js'));
          expect(html, contains('<title>Iniciar sesión | '));
          expect(html, contains('noindex'));
        }
        final plain = await _get(
          _FakeReads(),
          '/cuenta/login?confirmed=true',
          flutterShell: _FakeFlutterShell(),
        );
        expect(plain.headers['x-storefront-fallback'], isNull);
        final hidden = await _get(
          _FakeReads(),
          '/_html/cuenta/login?code=abc',
          flutterShell: _FakeFlutterShell(),
        );
        expect(hidden.headers['x-storefront-fallback'], isNull);
        expect(
          (await _get(_FakeReads(), '/cuenta/login?code=abc')).statusCode,
          503,
        );
        expect(loginIsAuthReturn(['confirmed']), isFalse);
        expect(loginIsAuthReturn(['clave']), isFalse);
        expect(loginIsAuthReturn(['code']), isTrue);
      },
    );

    Future<(int, Map<String, Object?>)> login(
      _FakeReads reads,
      Map<String, Object?> body, {
      String? auth,
    }) async {
      final response = await _get(
        reads,
        portalActionPath,
        method: 'POST',
        headers: {'authorization': ?auth, 'content-type': 'application/json'},
        body: jsonEncode(body),
      );
      expect(response.headers['cache-control'], 'no-store');
      return (
        response.statusCode,
        jsonDecode(await response.readAsString()) as Map<String, Object?>,
      );
    }

    test('check: the core\'s messages for each form, with no session and '
        'nothing read', () async {
      final reads = _FakeReads();
      expect(
        (await login(reads, {
          'action': 'check',
          'form': 'login',
          'values': {'email': '', 'password': ''},
        })).$2,
        {
          'errors': {
            'email': 'El correo es requerido',
            'password': 'Por favor ingrese su contraseña',
          },
        },
      );
      expect(
        (await login(reads, {
          'action': 'check',
          'form': 'register',
          'values': {'name': ' ', 'email': 'a@b', 'password': 'aaaaaaa1'},
        })).$2,
        {
          'errors': {'name': 'El nombre es requerido'},
        },
      );
      expect(
        (await login(reads, {
          'action': 'check',
          'form': 'reset',
          'values': {'email': 'sin-arroba'},
        })).$2,
        {
          'errors': {'email': 'Ingresa un correo válido'},
        },
      );
      expect(
        (await login(reads, {
          'action': 'check',
          'form': 'login',
          'values': {'email': 'a@b', 'password': 'Aaa1..'},
        })).$2,
        {'errors': <String, Object?>{}},
      );
      final (status, answer) = await login(reads, {
        'action': 'check',
        'form': 'otro',
      });
      expect(status, 400);
      expect(answer['state'], 'invalid');
      expect(reads.requested, isEmpty);
    });

    test('enter: the store\'s customer behind the session, the signup phone '
        'kept when the profile has none', () async {
      final reads = _FakeReads(portal: portal());
      expect(
        (await login(reads, {'action': 'enter'}, auth: 'Bearer ${token()}')).$2,
        {'state': 'entered'},
      );
      expect(reads.requested, ['enter']);
      expect(reads.writes, isEmpty);
      expect(
        (await login(_FakeReads(portal: portal(profile: null)), {
          'action': 'enter',
        }, auth: 'Bearer ${token()}')).$2,
        {'state': 'not-customer'},
      );
      expect(
        (await login(_FakeReads(), {
          'action': 'enter',
        }, auth: 'Bearer ${token()}')).$2,
        {'state': 'expired'},
      );
      expect(
        (await login(_FakeReads(fail: true), {
          'action': 'enter',
        }, auth: 'Bearer ${token()}')).$2,
        {'state': 'not-customer'},
      );
      // No session: not an action the login can send.
      expect((await login(reads, {'action': 'enter'})).$1, 400);

      String b64(Map<String, Object?> v) =>
          base64Url.encode(utf8.encode(jsonEncode(v))).replaceAll('=', '');
      final withPhone =
          '${b64({'alg': 'HS256'})}.'
          '${b64({
            'sub': '7e570000-0000-4000-8000-0000000000aa',
            'user_metadata': {'phone': ' +56 9 8765 4321 '},
          })}.'
          '${'x' * 43}';
      final noPhone = _FakeReads(
        portal: portal(
          profile: const {
            'id': customer,
            'tenant_id': _tenant,
            'auth_user_id': '7e570000-0000-4000-8000-0000000000aa',
            'name': 'Ana Prueba',
            'phone': null,
          },
        ),
      );
      expect(
        (await login(noPhone, {
          'action': 'enter',
        }, auth: 'Bearer $withPhone')).$2,
        {'state': 'entered'},
      );
      expect(noPhone.writes.single['table'], 'customers');
      expect(noPhone.writes.single['filters'], {
        'id': 'eq.$customer',
        'tenant_id': 'eq.$_tenant',
      });
      expect(
        (noPhone.writes.single['body'] as Map)['phone'],
        '+56 9 8765 4321',
      );
      // A profile with a phone keeps it.
      final kept = _FakeReads(portal: portal());
      await login(kept, {'action': 'enter'}, auth: 'Bearer $withPhone');
      expect(kept.writes, isEmpty);
    });

    test('a refused session is renewed before any write', () async {
      final reads = _FakeReads();
      expect(
        (await action(reads, '/cuenta/perfil', 'profile', {
          'name': 'Ana',
        }))['state'],
        'expired',
      );
      expect(reads.writes, isEmpty);
      expect(
        (await action(
          _FakeReads(portal: portal()),
          '/cuenta/perfil',
          'borrar',
        ))['state'],
        'invalid',
      );
    });
  });
}
