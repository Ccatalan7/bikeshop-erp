import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/website/models/website_editor_mode_route_binding.dart';

void main() {
  test('Edit and Preview share one storefront scroll identity', () {
    final edit = websiteEditorScrollRouteKey(
      Uri.parse('/tienda/productos?q=cadena&edit=true#resultados'),
    );
    final preview = websiteEditorScrollRouteKey(
      Uri.parse('/tienda/productos?q=cadena&preview=true#resultados'),
    );
    final public = websiteEditorScrollRouteKey(
      Uri.parse('/tienda/productos?q=cadena#resultados'),
    );

    expect(edit, public);
    expect(preview, public);
  });

  test('foreign filters and repeated values remain distinct and intact', () {
    final first = websiteEditorScrollRouteKey(
      Uri.parse('/productos?marca=a&marca=b&page=2&edit=true'),
    );
    final second = websiteEditorScrollRouteKey(
      Uri.parse('/productos?marca=a&marca=b&page=3&preview=true'),
    );

    expect(first, '/productos?marca=a&marca=b&page=2');
    expect(second, '/productos?marca=a&marca=b&page=3');
    expect(first, isNot(second));
  });
}
