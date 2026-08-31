import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/shared/services/supplier_need_portal_search.dart';
import 'package:vinabike_erp/shared/services/supplier_taxonomy_selection.dart';

/// Dónde buscar una pieza, sin una lista de palabras por familia.
///
/// El punteo por vocabulario exige que alguien escriba, para cada familia, las
/// palabras que la nombran y las que la desmienten. Una familia nueva no se
/// puede buscar hasta que eso exista. Acá el proveedor ya publicó su índice de
/// categorías y el modelo sólo elige de esa lista.
///
/// Lo que se prueba no es que el modelo acierte —eso lo decide el modelo— sino
/// que **no pueda inventar un nodo** y que quedarse sin buscar nunca sea el
/// resultado.

/// Rótulos reales del catálogo de RBX.
const _rbx = <SupplierPortalTaxonomyNode>[
  SupplierPortalTaxonomyNode(
    id: '171',
    label: 'CAMARAS RUTA',
    parentLabel: 'NEUMATICOS Y CAMARAS',
  ),
  SupplierPortalTaxonomyNode(
    id: '172',
    label: 'CAMARAS MTB',
    parentLabel: 'NEUMATICOS Y CAMARAS',
  ),
  SupplierPortalTaxonomyNode(
    id: '56',
    label: 'MOTOR (MOVIMIENTO CENTRAL)',
    parentLabel: 'TRANSMISION Y PARTES',
  ),
  SupplierPortalTaxonomyNode(
    id: '57',
    label: 'BIELAS Y PLATOS',
    parentLabel: 'TRANSMISION Y PARTES',
  ),
  SupplierPortalTaxonomyNode(
    id: '112',
    label: 'NEUMATICOS RUTA',
    parentLabel: 'NEUMATICOS Y CAMARAS',
  ),
];

final _taxonomia = SupplierPortalCatalogTaxonomy.fromNodes(_rbx);

/// El punteo por vocabulario, que es a lo que se cae si el modelo falla.
final _fallback = <SupplierPortalTaxonomyNode>[_rbx[0]];

Object? _respuesta(List<String> ids) => <String, Object?>{
      'nodes': <Object?>[
        for (final id in ids) <String, Object?>{'id': id, 'why': 'prueba'},
      ],
    };

void main() {
  group('la instrucción lleva el índice del proveedor', () {
    test('los rótulos y el padre van tal cual, y la pieza también', () {
      final prompt = buildSupplierTaxonomyPrompt(
        requestedObject: 'Motor de centro sellado con eje cuadrado',
        nodes: _rbx,
        limit: 3,
      );

      expect(prompt, contains('MOTOR (MOVIMIENTO CENTRAL)'));
      expect(prompt, contains('TRANSMISION Y PARTES'));
      expect(prompt, contains('Motor de centro sellado con eje cuadrado'));
      // El tope viaja: recorrer el catálogo entero no es una respuesta.
      expect(prompt, contains('máximo 3'));
    });
  });

  group('la compuerta: sólo existen los nodos que mandamos', () {
    test('un nodo inventado se descarta', () {
      final rechazos = <String>[];
      final elegidos = verifySupplierTaxonomySelection(
        nodes: _rbx,
        response: _respuesta(<String>['56', '9999']),
        limit: 3,
        onRejected: rechazos.addAll,
      );

      expect(elegidos.map((node) => node.id), <String>['56']);
      expect(rechazos.single, contains('nodo inexistente'));
    });

    test('se respeta el orden del modelo y el tope', () {
      final elegidos = verifySupplierTaxonomySelection(
        nodes: _rbx,
        response: _respuesta(<String>['56', '57', '171']),
        limit: 2,
      );
      expect(elegidos.map((node) => node.id), <String>['56', '57']);
    });

    test('un id repetido cuenta una vez', () {
      final elegidos = verifySupplierTaxonomySelection(
        nodes: _rbx,
        response: _respuesta(<String>['56', '56']),
        limit: 3,
      );
      expect(elegidos, hasLength(1));
    });

    test('un nodo de OTRA pieza se veta con lo que ya sabemos', () {
      // Pasó de verdad el 2026-08-30: pidiendo cámaras, el modelo eligió
      // `NEUMATICOS RUTA` y la corrida gastó cuatro páginas del presupuesto
      // enumerando neumáticos. Los términos negativos de la familia ya
      // existen; acá sólo desmienten, no eligen.
      final rechazos = <String>[];
      final elegidos = verifySupplierTaxonomySelection(
        nodes: _rbx,
        response: _respuesta(<String>['112', '171']),
        limit: 3,
        excludedTerms: const <String>['neumatico'],
        onRejected: rechazos.addAll,
      );

      expect(elegidos.map((node) => node.label), <String>['CAMARAS RUTA']);
      expect(rechazos.single, contains('nombra otra pieza'));
    });

    test('el veto exige la palabra entera, no un pedazo', () {
      // `camara` no puede vetar `CAMARAS RUTA` por aparecer dentro de otra
      // palabra: el veto que se pasa de listo deja al operador sin buscar.
      final elegidos = verifySupplierTaxonomySelection(
        nodes: _rbx,
        response: _respuesta(<String>['171']),
        limit: 3,
        excludedTerms: const <String>['rut'],
      );
      expect(elegidos, hasLength(1));
    });

    test('una respuesta ilegible no elige nada', () {
      expect(
        verifySupplierTaxonomySelection(
          nodes: _rbx,
          response: 'el modelo se puso a conversar',
          limit: 3,
        ),
        isEmpty,
      );
    });
  });

  group('quedarse sin buscar nunca es el resultado', () {
    Future<List<SupplierPortalTaxonomyNode>> elegir({
      SupplierSpecExtractorStub? extractor,
    }) =>
        chooseSupplierTaxonomyNodes(
          taxonomy: _taxonomia,
          requestedObject: 'Motor de centro sellado con eje cuadrado',
          fallback: _fallback,
          limit: 3,
          extractor: extractor?.call,
        );

    test('el modelo elige el nodo que ninguna lista nombraba', () async {
      // `MOTOR (MOVIMIENTO CENTRAL)` es el rótulo de RBX para un pedalier.
      // Sin vocabulario escrito para esa familia, el punteo no lo encuentra.
      final elegidos = await elegir(
        extractor: SupplierSpecExtractorStub(
          (_) async => _respuesta(<String>['56']),
        ),
      );
      expect(elegidos.single.label, 'MOTOR (MOVIMIENTO CENTRAL)');
    });

    test('sin modelo se usa el punteo de siempre', () async {
      expect(await elegir(), _fallback);
    });

    test('si el modelo se cae, se usa el punteo de siempre', () async {
      final elegidos = await elegir(
        extractor: SupplierSpecExtractorStub(
          (_) async => throw StateError('cuota agotada'),
        ),
      );
      expect(elegidos, _fallback);
    });

    test('si no elige nada, se usa el punteo de siempre', () async {
      // Una lista vacía puede ser correcta —el proveedor no tiene la pieza—
      // pero no se puede distinguir de un modelo que no entendió. Se busca.
      final elegidos = await elegir(
        extractor: SupplierSpecExtractorStub(
          (_) async => _respuesta(const <String>[]),
        ),
      );
      expect(elegidos, _fallback);
    });
  });
}

/// Un extractor de mentira, para probar el circuito sin red.
class SupplierSpecExtractorStub {
  const SupplierSpecExtractorStub(this.call);
  final Future<Object?> Function(String prompt) call;
}
