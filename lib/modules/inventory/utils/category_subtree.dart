/// Una categoría y toda su descendencia, siguiendo `parent_id`.
///
/// **Elegir una categoría es elegir también sus subcategorías.** «Ruedas» no
/// tiene ni un producto propio: sus 485 productos activos viven en Neumáticos,
/// Cámaras, Llantas y el resto de sus hijas (producción, 2026-11-02). Un filtro
/// que compara el id exacto contestaba «Ruedas está vacía» sobre la sección más
/// llena del taller, y «Accesorios» mostraba 11 productos de 316. Es la misma
/// regla que ya sigue la tienda (`category_scope=subtree` por defecto): un solo
/// sentido de «categoría» en todo el sistema.
///
/// [parentById] es el árbol entero: id de cada categoría → id de su madre
/// (`null` en la raíz). Un ciclo en los datos no cuelga el recorrido.
Set<String> categorySubtreeIds(
  String rootId, {
  required Map<String, String?> parentById,
}) {
  final childrenById = <String, List<String>>{};
  parentById.forEach((id, parentId) {
    if (parentId == null || parentId.isEmpty) return;
    childrenById.putIfAbsent(parentId, () => <String>[]).add(id);
  });

  final result = <String>{rootId};
  final pending = <String>[rootId];
  while (pending.isNotEmpty) {
    final current = pending.removeLast();
    for (final child in childrenById[current] ?? const <String>[]) {
      if (result.add(child)) pending.add(child);
    }
  }
  return result;
}
