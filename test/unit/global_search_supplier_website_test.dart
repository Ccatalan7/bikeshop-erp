import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/shared/services/global_search/global_search_engine.dart';
import 'package:vinabike_erp/shared/services/global_search/global_search_entry.dart';
import 'package:vinabike_erp/shared/services/global_search/global_search_index.dart';
import 'package:vinabike_erp/shared/services/global_search/global_search_query.dart';

/// El sitio de un proveedor es una de las cosas que se quieren de él.
///
/// Las filas replican producción (2026-09-17): 40 de 92 proveedores tienen
/// sitio, y TeknoBike lo guarda sin esquema, como lo escribió alguien.
void main() {
  Map<String, dynamic> row({
    String? name = 'TeknoBike',
    String? website = 'teknobike.cl',
  }) =>
      <String, dynamic>{
        'id': 's1',
        'name': name,
        'website': website,
        'image_url': 'https://cdn.test/tekno.png',
        'updated_at': '2026-09-17T12:00:00Z',
      };

  test('«teknobike» ofrece abrir su sitio', () {
    final outcome = rankGlobalSearch(
      query: GlobalSearchQuery.parse('teknobike'),
      entries: <GlobalSearchEntry>[globalSearchSupplierWebsiteEntry(row())!],
    );
    final entry = outcome.flattened.single.entry;
    expect(entry.id, 'supplier_website:s1');
    expect(entry.title, 'Sitio web de TeknoBike');
    expect(entry.subtitle, 'teknobike.cl');
    expect(outcome.groups.single.kind.groupTitle, 'Sitios web');
  });

  test('una dirección sin esquema se completa para poder abrirse', () {
    expect(globalSearchSupplierWebsiteEntry(row())!.browserUrl,
        'https://teknobike.cl');
  });

  test('lo que ya trae esquema se respeta', () {
    final entry = globalSearchSupplierWebsiteEntry(
      row(website: 'http://www.derman.cl/catalogo'),
    )!;
    expect(entry.browserUrl, 'http://www.derman.cl/catalogo');
    // El dominio se lee sin `www.`, que es como se teclea.
    expect(entry.subtitle, 'derman.cl');
  });

  test('el dominio también encuentra la fila', () {
    final outcome = rankGlobalSearch(
      query: GlobalSearchQuery.parse('teknobike.cl'),
      entries: <GlobalSearchEntry>[globalSearchSupplierWebsiteEntry(row())!],
    );
    expect(outcome.flattened, isNotEmpty);
  });

  test('un proveedor sin sitio no ofrece abrir nada', () {
    expect(globalSearchSupplierWebsiteEntry(row(website: null)), isNull);
  });

  test('lo que no se puede abrir no se ofrece', () {
    // Un texto suelto, un correo o un esquema que el navegador no acepta.
    for (final value in <String>['pregunta a Diego', 'mailto:x@y.cl', 'ftp://x.cl']) {
      expect(
        globalSearchSupplierWebsiteEntry(row(website: value)),
        isNull,
        reason: 'con «$value»',
      );
    }
  });

  test('abre el navegador, no navega el ERP', () {
    final entry = globalSearchSupplierWebsiteEntry(row())!;
    expect(entry.browserUrl, isNotNull);
    expect(entry.toolbarTool, isNull);
    expect(entry.conversationId, isNull);
  });
}
