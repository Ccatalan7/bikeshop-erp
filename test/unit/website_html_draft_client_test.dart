import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vinabike_erp/modules/website/models/website_page_models.dart';
import 'package:vinabike_erp/modules/website/services/website_html_draft_client.dart';

void main() {
  test('the draft names the page and keeps the blocks in their order', () {
    final body = jsonDecode(
      websiteHtmlDraftBody(
        path: '/pagina/nosotros',
        pageId: 'p1',
        pageSlug: 'Nosotros',
        blocks: [
          {
            'id': 'b2',
            'type': 'hero',
            'data': {'title': 'Hola'},
            'isVisible': false,
          },
          {
            'block_type': 'text',
            'block_data': {'text': 'Sin id todavía'},
          },
        ],
        settings: {'store_name': 'Viñabike'},
      ),
    ) as Map<String, dynamic>;
    expect(body['path'], '/pagina/nosotros');
    expect(body['page'], {'slug': 'nosotros'});
    expect(body['settings'], {'store_name': 'Viñabike'});
    expect(body['blocks'], [
      {
        'id': 'b2',
        'block_type': 'hero',
        'block_data': {'title': 'Hola'},
        'is_visible': false,
        'order_index': 0,
      },
      {
        'id': 'draft-1',
        'block_type': 'text',
        'block_data': {'text': 'Sin id todavía'},
        'is_visible': true,
        'order_index': 1,
      },
    ]);
    Object? page(String? pageId, String? pageSlug) => (jsonDecode(
          websiteHtmlDraftBody(
            path: '/',
            pageId: pageId,
            pageSlug: pageSlug,
            blocks: const [],
            settings: const {},
          ),
        ) as Map)['page'];
    expect(page(null, null), {'home': true});
    // A slug the server would refuse names no page: the path is still drawn.
    expect(page('p1', '@catalog/categories'), isNull);
  });

  test('the store as the editor mounts it, as its public pages', () {
    String? path(String location) => websiteHtmlDraftPath(Uri.parse(location));
    expect(path('/tienda'), '/');
    expect(path('/tienda/'), '/');
    expect(path('/tienda/productos'), '/productos');
    // The editor's own flags are not the page's.
    expect(
      path('/tienda/productos/categoria/componentes?edit=true&marca=b1'),
      '/productos/categoria/componentes?marca=b1',
    );
    expect(path('/tienda?preview=true'), '/');
    expect(
      path('/tienda/productos/categoria/horquillas?marca=b1&orden=precio'),
      '/productos/categoria/horquillas?marca=b1&orden=precio',
    );
    expect(path('/tienda/servicios'), '/servicios');
    expect(path('/tienda/productos/horquilla-auron/H911'),
        '/productos/horquilla-auron/H911');
    expect(path('/tienda/pagina/nosotros-2'), '/pagina/nosotros-2');
    expect(path('/nosotros'), '/nosotros');
    expect(path('/envios'), '/envios');
    expect(path('/tienda/contacto'), '/contacto');
    // Pages that stay on the canvas.
    for (final location in [
      '/tienda/carrito',
      '/tienda/checkout',
      '/tienda/pedido/123',
      '/tienda/cuenta',
      '/tienda/cuenta/pedidos',
      '/website',
    ]) {
      expect(path(location), isNull, reason: location);
    }
  });

  test('a drafted menu travels as rows, each in its drafted place', () {
    final now = DateTime.utc(2026, 10, 7);
    WebsiteNavigation nav(String id, int order,
            [List<WebsiteNavigation> children = const []]) =>
        WebsiteNavigation(
          id: id,
          tenantId: 'tenant',
          menuLocation: MenuLocation.footer,
          label: id,
          linkType: NavLinkType.external,
          linkValue: 'https://example.invalid/$id',
          orderIndex: order,
          children: children,
          createdAt: now,
          updatedAt: now,
        );
    // Drafted order, not the saved `orderIndex`.
    final rows = websiteHtmlDraftNavigationRows([
      nav('b', 7, [nav('b2', 9), nav('b1', 0)]),
      nav('a', 0),
    ]);
    expect(
      [
        for (final row in rows)
          (row['id'], row['parent_id'], row['order_index'])
      ],
      [('b', null, 0), ('b2', 'b', 0), ('b1', 'b', 1), ('a', null, 1)],
    );
    expect(rows.first['menu_location'], 'footer');
  });

  test('only the draft wanted now lands: A shown, B scheduled, back to A', () {
    final queue = WebsiteHtmlDraftQueue();
    expect(queue.want('A'), WebsiteHtmlDraftNeed.ask);
    final a = queue.send();
    expect(queue.want('A'), WebsiteHtmlDraftNeed.waiting);
    expect(queue.wanted(a), isTrue);
    queue.shown('A');

    expect(queue.want('B'), WebsiteHtmlDraftNeed.ask);
    final b = queue.send();
    // Back to the page on screen before B's answer: B must not land.
    expect(queue.want('A'), WebsiteHtmlDraftNeed.onScreen);
    expect(queue.wanted(b), isFalse);

    // B again is a new request; an answer that failed may be asked again.
    expect(queue.want('B'), WebsiteHtmlDraftNeed.ask);
    queue.failed();
    expect(queue.want('B'), WebsiteHtmlDraftNeed.ask);
  });

  test('the editor asks only a safe, configured server', () {
    expect(
      websiteHtmlDraftServer('https://vinabike.cl').toString(),
      'https://vinabike.cl',
    );
    expect(
      websiteHtmlDraftServer('https://vinabike.cl/').toString(),
      'https://vinabike.cl',
    );
    expect(
      websiteHtmlDraftServer('http://localhost:8080').toString(),
      'http://localhost:8080',
    );
    for (final unsafe in [
      'http://vinabike.cl',
      'https://vinabike.cl:8443',
      'https://vinabike.cl/tienda',
      'https://user@vinabike.cl',
      'ftp://localhost',
      '',
      'vinabike.cl',
    ]) {
      expect(websiteHtmlDraftServer(unsafe), isNull, reason: unsafe);
    }
    // The build's own default.
    expect(websiteHtmlDraftServer().toString(), 'https://vinabike.cl');
  });

  test('asks the store with the session and reads its answer', () async {
    late http.Request sent;
    var answer = <String, Object?>{'html': '<!DOCTYPE html><p>ok</p>'};
    var status = 200;
    final client = WebsiteHtmlDraftClient(
      client: MockClient((request) async {
        sent = request;
        return http.Response(jsonEncode(answer), status);
      }),
    );
    final drawn = await client.draw(
      storeOrigin: Uri.parse('https://vinabike.cl/algo?x=1'),
      accessToken: 'token-de-prueba',
      body: '{}',
    );
    expect(sent.url.toString(), 'https://vinabike.cl/_html/editor/borrador');
    expect(sent.headers['authorization'], 'Bearer token-de-prueba');
    expect(drawn.html, '<!DOCTYPE html><p>ok</p>');
    expect(drawn.message, isNull);

    for (final (state, expected) in [
      ('expired', WebsiteHtmlDraftState.expired),
      ('forbidden', WebsiteHtmlDraftState.forbidden),
      ('unavailable', WebsiteHtmlDraftState.unavailable),
    ]) {
      answer = {'state': state};
      status = 403;
      final refused = await client.draw(
        storeOrigin: Uri.parse('https://vinabike.cl'),
        accessToken: 't',
        body: '{}',
      );
      expect(refused.state, expected);
      expect(refused.message, isNotEmpty);
    }

    final down = WebsiteHtmlDraftClient(
      client: MockClient((_) async => throw http.ClientException('sin red')),
    );
    expect(
      (await down.draw(
        storeOrigin: Uri.parse('https://vinabike.cl'),
        accessToken: 't',
        body: '{}',
      ))
          .state,
      WebsiteHtmlDraftState.unavailable,
    );
  });
}
