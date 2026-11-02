import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/inventory/utils/category_subtree.dart';

/// El árbol replica producción (2026-11-02): «Ruedas» no tiene productos
/// propios y «Mazas» baja dos niveles más, hasta Conos.
void main() {
  const tree = <String, String?>{
    'componentes': null,
    'ruedas': 'componentes',
    'neumaticos': 'ruedas',
    'mazas': 'ruedas',
    'ejes': 'mazas',
    'conos': 'ejes',
    'frenos': 'componentes',
    'servicio': null,
    'servicio-ruedas': 'servicio',
  };

  test('una categoría sin hijas es sólo ella', () {
    expect(
      categorySubtreeIds('neumaticos', parentById: tree),
      <String>{'neumaticos'},
    );
  });

  test('una madre trae a toda su descendencia, a cualquier profundidad', () {
    expect(
      categorySubtreeIds('ruedas', parentById: tree),
      <String>{'ruedas', 'neumaticos', 'mazas', 'ejes', 'conos'},
    );
  });

  test('el mismo nombre en otra rama no se mezcla', () {
    expect(
      categorySubtreeIds('servicio', parentById: tree),
      <String>{'servicio', 'servicio-ruedas'},
    );
  });

  test('un id que el árbol no conoce se filtra por sí mismo', () {
    // La lista puede tener el filtro antes de que lleguen las categorías.
    expect(
      categorySubtreeIds('ruedas', parentById: const <String, String?>{}),
      <String>{'ruedas'},
    );
  });

  test('un ciclo en los datos no cuelga el recorrido', () {
    expect(
      categorySubtreeIds(
        'a',
        parentById: const <String, String?>{'a': 'b', 'b': 'a'},
      ),
      <String>{'a', 'b'},
    );
  });
}
