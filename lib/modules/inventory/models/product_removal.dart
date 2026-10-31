/// What «Eliminar» did to a product (`delete_or_archive_product_v1`).
///
/// A product with no history is deleted. One with sales, purchases, stock
/// movements, jobs or its IVA record is archived instead: it stays inactive,
/// hidden unless the list includes inactive ones, and keeps that history. The
/// base refuses to delete it (`guard_product_delete_history`), because the
/// cascade would take its stock movements and leave its job, purchase and bike
/// lines without a product.
class ProductRemoval {
  const ProductRemoval({required this.archived, this.reasons = const []});

  factory ProductRemoval.fromRpc(Object? response) {
    if (response is! Map) {
      throw const FormatException('Respuesta inválida al eliminar el producto');
    }
    final outcome = response['outcome'];
    if (outcome != 'deleted' && outcome != 'archived') {
      throw FormatException('Resultado desconocido al eliminar: $outcome');
    }
    final reasons = response['reasons'];
    return ProductRemoval(
      archived: outcome == 'archived',
      reasons: reasons is List
          ? reasons
              .whereType<String>()
              .map((reason) => reason.trim())
              .where((reason) => reason.isNotEmpty)
              .toList(growable: false)
          : const [],
    );
  }

  /// Said before confirming, wherever «Eliminar» is offered.
  static String confirmation(String name) =>
      'Si «$name» no tiene historia, se borra para siempre. Si tiene ventas, '
      'compras, movimientos de stock o trabajos, queda inactivo y esa '
      'historia se conserva.';

  final bool archived;

  /// The base's own words: «ventas», «movimientos de stock», «registro de IVA»…
  final List<String> reasons;

  /// The result for the operator, e.g. «No se borró «Cadena KMC X9» porque
  /// tiene ventas y movimientos de stock: quedó inactivo y esa historia se
  /// conserva.»
  String message({required String name, required bool isService}) {
    if (!archived) {
      return isService ? 'Servicio eliminado' : 'Producto eliminado';
    }
    final why = reasons.isEmpty ? 'historia' : _joined(reasons);
    return 'No se borró «$name» porque tiene $why: quedó inactivo y esa '
        'historia se conserva.';
  }

  static String _joined(List<String> reasons) {
    if (reasons.length == 1) return reasons.single;
    final head = reasons.sublist(0, reasons.length - 1).join(', ');
    return '$head y ${reasons.last}';
  }
}
