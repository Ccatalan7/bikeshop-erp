import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vinabike_erp/shared/services/public_catalog_client.dart';

/// La tienda lee `products` como anónimo aunque haya un cliente con sesión.
///
/// La base sólo le da a `anon` las columnas públicas de `products`, y a un
/// usuario con sesión sólo los productos de su empresa. Si una lectura de la
/// tienda viaja con la sesión de un cliente, ese cliente deja de ver el
/// catálogo.
void main() {
  tearDown(PublicCatalogClient.reset);

  test('el cliente del catálogo sale con la clave pública, sin sesión',
      () async {
    final requests = <http.Request>[];
    PublicCatalogClient.configure(
      url: 'https://catalogo.example.invalid',
      anonKey: 'clave-publica-de-prueba',
      httpClient: MockClient((request) async {
        requests.add(request);
        return http.Response('[]', 200,
            headers: {'content-type': 'application/json'}, request: request);
      }),
    );

    await PublicCatalogClient.instance
        .from('products')
        .select('id,name')
        .eq('tenant_id', 'tienda');

    expect(requests, hasLength(1));
    expect(requests.single.headers['Authorization'],
        'Bearer clave-publica-de-prueba');
    expect(requests.single.headers['apikey'], 'clave-publica-de-prueba');
    expect(() => PublicCatalogClient.instance.auth, throwsA(anything),
        reason: 'sin autenticación propia no puede tomar ninguna sesión');
  });

  test('la tienda no lee products con la sesión del cliente', () {
    final offenders = <String>[];
    final files = [
      ...Directory('lib/public_store')
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart')),
      File('lib/modules/website/widgets/canvas_block.dart'),
    ];

    for (final file in files) {
      final lines = file.readAsLinesSync();
      for (var index = 0; index < lines.length; index++) {
        if (!lines[index].contains(".from('products')")) continue;
        final from = index - 8 < 0 ? 0 : index - 8;
        final window = lines.sublist(from, index + 1).join('\n');
        if (window.contains('PublicCatalogClient.instance')) continue;
        offenders.add('${file.path}:${index + 1}');
      }
    }

    expect(offenders, isEmpty,
        reason: 'lee products con PublicCatalogClient.instance');
  });
}
