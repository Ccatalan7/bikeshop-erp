import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vinabike_erp/modules/website/services/website_html_draft_client.dart';

void main() {
  test('the draft names the page and keeps the blocks in their order', () {
    final body = jsonDecode(
      websiteHtmlDraftBody(
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
    expect(
      (jsonDecode(
        websiteHtmlDraftBody(
          pageId: null,
          pageSlug: null,
          blocks: const [],
          settings: const {},
        ),
      ) as Map)['page'],
      {'home': true},
    );
  });

  test('the home and the pages the editor creates; not the templates', () {
    expect(
      websiteHtmlDraftSupports(
          pageId: null, pageSlug: null, catalogCanvas: false),
      isTrue,
    );
    expect(
      websiteHtmlDraftSupports(
        pageId: 'p1',
        pageSlug: 'nosotros',
        catalogCanvas: false,
      ),
      isTrue,
    );
    expect(
      websiteHtmlDraftSupports(
        pageId: 'p1',
        pageSlug: '@catalog/categories',
        catalogCanvas: false,
      ),
      isFalse,
    );
    expect(
      websiteHtmlDraftSupports(
          pageId: null, pageSlug: null, catalogCanvas: true),
      isFalse,
    );
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
