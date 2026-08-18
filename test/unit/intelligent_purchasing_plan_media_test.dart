import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vinabike_erp/modules/purchases/services/intelligent_purchasing_service.dart';

/// El enlace completo que hace que el plan muestre la foto del producto:
/// `fetchPlan` → una sola consulta a `products` con la terna de imagen →
/// `PurchasePlanLine.media`.
///
/// **Por qué conductual y no un grep de fuente.** Las tres piezas se pueden
/// romper por separado sin que ninguna deje de existir: alguien recorta la
/// proyección «para pedir menos», o cambia `withProduct` y deja de pasar el
/// media, o mete la consulta dentro del `map` y la vuelve una por fila. Un
/// contrato de texto sólo detecta la primera. Acá se conduce el servicio real
/// contra un transporte falso, así que lo que se afirma es lo que el servicio
/// **pide** y lo que **devuelve**, no cómo está escrito.
///
/// No toca producción: `MockClient` responde en memoria y no abre socket.
const _planId = '91000000-0000-4000-8000-000000000101';
const _productA = '91000000-0000-4000-8000-000000000201';
const _productB = '91000000-0000-4000-8000-000000000202';

http.Response _json(Object? body, http.BaseRequest request) => http.Response(
      jsonEncode(body),
      200,
      headers: {'content-type': 'application/json'},
      request: request,
    );

/// Construye el servicio sobre un transporte falso y registra cada petición.
({IntelligentPurchasingService service, List<Uri> requests}) _service({
  required List<Map<String, dynamic>> lines,
  required List<Map<String, dynamic>> products,
}) {
  final requests = <Uri>[];
  final client = SupabaseClient(
    'https://example.supabase.co',
    'test-anon-key',
    authOptions: const AuthClientOptions(autoRefreshToken: false),
    httpClient: MockClient((request) async {
      requests.add(request.url);
      final path = request.url.path;
      if (path.endsWith('/purchase_plans')) {
        return _json({
          'id': _planId,
          'title': 'Plan de compra',
          'state': 'draft',
          'objective_profile': 'balanced',
          'version': 1,
        }, request);
      }
      if (path.endsWith('/purchase_plan_lines')) return _json(lines, request);
      if (path.endsWith('/products')) return _json(products, request);
      if (path.endsWith('/purchase_plan_supplier_groups_v1')) {
        return _json(const <Object?>[], request);
      }
      throw StateError('Petición inesperada: ${request.url}');
    }),
  );
  addTearDown(client.dispose);
  return (
    service: IntelligentPurchasingService(client: client),
    requests: requests
  );
}

Map<String, dynamic> _line(String id, String productId) => {
      'id': id,
      'plan_id': _planId,
      'source_need_id': 'need-$id',
      'candidate_id': 'candidate-$id',
      'product_id': productId,
      'supplier_name': 'Andes Industrial',
      'quantity': 2,
      'unit': 'unit',
      'currency_code': 'CLP',
      'landed_unit_cost_net': 8725,
      'projected_gross_margin_ratio': 0.41,
      'supplier_availability': 'unverified',
      'state': 'active',
    };

Uri _productsRequest(List<Uri> requests) =>
    requests.firstWhere((uri) => uri.path.endsWith('/products'));

void main() {
  test('la consulta de ficha proyecta el nombre y la terna de imagen',
      () async {
    final harness = _service(
      lines: [_line('line-1', _productA)],
      products: [
        {
          'id': _productA,
          'name': 'Neumático 27,5 Maxxis',
          'image_url_optimized': 'https://cdn/opt.webp',
          'image_url': 'https://cdn/raw.jpg',
          'image_urls': ['https://cdn/extra.jpg'],
        },
      ],
    );

    await harness.service.fetchPlan(_planId);

    final select = _productsRequest(harness.requests).queryParameters['select'];
    // Las cinco columnas, nombradas una por una: si alguien recorta la
    // proyección, el plan vuelve a quedarse sin foto y esto lo dice acá, no
    // tres pantallas más allá.
    expect(select, isNotNull);
    for (final column in const [
      'id',
      'name',
      'image_url_optimized',
      'image_url',
      'image_urls',
    ]) {
      expect(select, contains(column), reason: 'falta la columna $column');
    }
  });

  test('la foto de la ficha llega a la línea en su orden de resolución',
      () async {
    final harness = _service(
      lines: [_line('line-1', _productA)],
      products: [
        {
          'id': _productA,
          'name': 'Neumático 27,5 Maxxis',
          'image_url_optimized': ' https://cdn/opt.webp ',
          'image_url': 'https://cdn/raw.jpg',
          'image_urls': ['https://cdn/raw.jpg', '', 'https://cdn/extra.jpg'],
        },
      ],
    );

    final plan = await harness.service.fetchPlan(_planId);
    final line = plan!.lines.single;

    expect(line.productName, 'Neumático 27,5 Maxxis');
    expect(line.media.hasImage, isTrue);
    // Optimizada primero, cruda después, galería al final y sin repetir: el
    // mismo contrato que `ProductMedia` ya defiende, verificado extremo a
    // extremo en vez de sobre un mapa construido a mano.
    expect(line.media.resolutionChain, const [
      'https://cdn/opt.webp',
      'https://cdn/raw.jpg',
      'https://cdn/extra.jpg',
    ]);
  });

  test('una ficha sin imagen deja la línea con media vacía, no con basura',
      () async {
    final harness = _service(
      lines: [_line('line-1', _productA)],
      products: [
        {'id': _productA, 'name': 'Cámara 27,5'},
      ],
    );

    final plan = await harness.service.fetchPlan(_planId);
    final line = plan!.lines.single;

    expect(line.productName, 'Cámara 27,5');
    expect(line.media.hasImage, isFalse);
    expect(line.media.primaryUrl, isNull);
  });

  test('todas las líneas se resuelven con una sola consulta de ficha',
      () async {
    final harness = _service(
      lines: [_line('line-1', _productA), _line('line-2', _productB)],
      products: [
        {
          'id': _productA,
          'name': 'Neumático',
          'image_url_optimized': 'https://cdn/a.webp',
        },
        {'id': _productB, 'name': 'Cámara', 'image_url': 'https://cdn/b.jpg'},
      ],
    );

    final plan = await harness.service.fetchPlan(_planId);

    expect(
      plan!.lines.map((line) => line.media.primaryUrl),
      ['https://cdn/a.webp', 'https://cdn/b.jpg'],
    );
    // Una consulta para las dos líneas. Enriquecer dentro del `map` haría N+1
    // viajes contra producción sin que ninguna prueba de UI se enterara.
    expect(
      harness.requests.where((uri) => uri.path.endsWith('/products')).length,
      1,
    );
  });

  test('sin producto en la ficha la línea sobrevive sin nombre inventado',
      () async {
    final harness = _service(
      lines: [_line('line-1', _productA)],
      products: const [],
    );

    final plan = await harness.service.fetchPlan(_planId);
    final line = plan!.lines.single;

    expect(line.productName, isNull);
    expect(line.media.hasImage, isFalse);
  });
}
