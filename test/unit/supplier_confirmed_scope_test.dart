import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/purchases/models/intelligent_purchasing_models.dart';

/// **«Confirmado» tiene que ser confirmado DE ESTO.**
///
/// La celda decía «12 de 12» en la fila de RBX y el dueño no pudo relacionar el
/// 12 con nada de la pantalla. Eran dos defectos:
///
///   1. El número no tenía referente: la fila habla de «2 de 9 líneas · 2
///      facturas · 1 producto» y ningún 12 aparecía por ningún lado.
///   2. Contestaba otra pregunta: el barrido de reposición del proveedor
///      —cámaras de 16", 20", 24", 26" y una biela— sobre una necesidad de
///      cámaras 29.
SupplierConfirmedAvailability _confirmed({
  required int checked,
  required int available,
  int outOfStock = 0,
  int notFound = 0,
  int inconclusive = 0,
  int sweptProducts = 0,
  int sweptAvailable = 0,
}) {
  return SupplierConfirmedAvailability(
    checked: checked,
    available: available,
    outOfStock: outOfStock,
    notFound: notFound,
    inconclusive: inconclusive,
    lastCheckedAt: DateTime.now().subtract(const Duration(hours: 5)),
    sharpestDriftPercent: null,
    sharpestDriftName: null,
    sweptProducts: sweptProducts,
    sweptAvailable: sweptAvailable,
  );
}

void main() {
  group('la celda contesta la pregunta de la fila', () {
    test('un solo producto se contesta con sí, no con «1 de 1»', () {
      expect(_confirmed(checked: 1, available: 1).rowLabel, 'Sí');
    });

    test('y el «no» distingue por qué', () {
      // «No apareció» y «no lo vende» son cosas distintas: el producto suele
      // estar sólo agotado y el filtro del portal lo esconde.
      expect(
        _confirmed(checked: 1, available: 0, outOfStock: 1).rowLabel,
        'Sin stock',
      );
      expect(
        _confirmed(checked: 1, available: 0, notFound: 1).rowLabel,
        'No estaba',
      );
      expect(
        _confirmed(checked: 1, available: 0, inconclusive: 1).rowLabel,
        'Sin concluir',
      );
    });

    test('con varios, la fracción sí compara entre proveedores', () {
      expect(_confirmed(checked: 3, available: 2).rowLabel, '2 de 3');
    });

    test('sin nada consultado de esta línea, la celda queda vacía', () {
      expect(_confirmed(checked: 0, available: 0).rowLabel, isNull);
    });

    test('consultado de OTRA cosa no es «sin consultar»', () {
      // Decirle «sin consultar» empujaría a repetir un chequeo que no contesta
      // esta pregunta. El barrido existe y se nombra aparte.
      final soloBarrido = _confirmed(
        checked: 0,
        available: 0,
        sweptProducts: 12,
        sweptAvailable: 12,
      );

      expect(soloBarrido.sweptButNotThis, isTrue);
      expect(soloBarrido.rowLabel, isNull);
      expect(soloBarrido.isEmpty, isTrue);
    });

    test('el barrido no infla el recuento de la fila', () {
      final ambos = _confirmed(
        checked: 1,
        available: 1,
        sweptProducts: 12,
        sweptAvailable: 12,
      );

      expect(ambos.rowLabel, 'Sí');
      expect(ambos.checked, 1, reason: 'la fila cuenta lo de esta línea');
      expect(ambos.sweptProducts, 12, reason: 'el barrido sigue disponible');
      expect(ambos.sweptButNotThis, isFalse);
    });
  });
}
