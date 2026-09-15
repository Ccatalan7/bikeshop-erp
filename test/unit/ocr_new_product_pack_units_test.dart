import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/ai_assistant/services/ai_service.dart';
import 'package:vinabike_erp/shared/widgets/ocr_upload_widget.dart';

/// Detectar un pack probado por la investigación estructurada.
///
/// **No multiplica solo.** Multiplicar exige saber qué unidad representa la
/// fila del catálogo que se está creando, y eso no está probado: en dos
/// corridas seguidas sobre la MISMA línea la IA propuso «Rotor de Freno AVID
/// G3CS 160mm» y «Par Rotores Freno Disco Avid G3CS 160mm». Con el segundo
/// nombre, multiplicar por 2 anotaría 20 rotores. Lo que hace este detector es
/// mandar la fila a la compuerta de confirmación de unidad que ya existe.
///
/// Medido en producción el 2026-08-24 con la factura AE120826: cinco líneas de
/// rotor AVID G3CS que la publicación vende de a dos. La IA lo resuelve bien
/// —variante `G3-160-160MM`, foto con `160+160MM`, `packaging.count: 2`— pero
/// esa evidencia no llegaba a ninguna compuerta, así que la fila se creaba como
/// producto simple y el borrador anotaba **5 rotores donde llegan 10**.
AIProductIdentityInvestigation _investigation({
  required AIProductPackageKind kind,
  required int? packagingCount,
  required List<AIProductCompositionComponent> components,
}) {
  return AIProductIdentityInvestigation(
    schemaVersion: '4',
    promptVersion: 'test',
    modelId: 'test-model',
    cleanedName: 'Rotor de Freno AVID G3CS 160mm',
    object: const AIProductObjectIdentity(
      label: 'Rotor de freno de disco',
      confidence: 0.98,
    ),
    manufacturer: const AIProductManufacturerIdentity(
      value: 'AVID',
      asserted: true,
      evidence: AIProductManufacturerEvidence.identity,
    ),
    models: const <AIProductModelIdentity>[],
    specs: const <AIProductSpecificationIdentity>[],
    fitment: const <String>[],
    composition: AIProductCompositionIdentity(
      kind: kind,
      components: components,
    ),
    packaging: AIProductPackagingIdentity(
      count: packagingCount,
      unitToken: 'unidad',
      source: AIProductSpecSource.option,
    ),
    leafProposals: const <AIProductLeafProposal>[],
    evidenceUsed: const <String>['variante seleccionada: G3-160-160MM'],
    abstainReason: null,
    receipt: const AIProductIdentityReceipt(
      rowRevision: '1',
      catalogVersion: 'v1',
      treeVersion: 'v1',
      promptVersion: 'test',
      modelId: 'test-model',
      listingId: '1005008550283218',
      variantKey: 'sku:12000045667017391',
      imageIdentity: 'sha:test',
    ),
    reason: 'La variante y la imagen confirman 2 unidades.',
  );
}

AIProductCompositionComponent _component(int quantity) =>
    AIProductCompositionComponent(
      label: 'Rotor de freno de disco AVID G3CS 160mm',
      role: AIProductCompositionRole.component,
      quantity: quantity,
    );

void main() {
  group('unidades por compra de un producto que se crea nuevo', () {
    test('un pack homogéneo probado se detecta', () {
      expect(
        provenPackUnitsForNewProduct(_investigation(
          kind: AIProductPackageKind.composite,
          packagingCount: 2,
          components: <AIProductCompositionComponent>[_component(2)],
        )),
        2,
        reason: 'el rotor AVID viene de a dos: la fila tiene que pedir '
            'confirmación de unidad antes de crear',
      );
    });

    test('sin investigación no se inventa un pack', () {
      expect(provenPackUnitsForNewProduct(null), 1);
    });

    test('un producto simple no es un pack', () {
      expect(
        provenPackUnitsForNewProduct(_investigation(
          kind: AIProductPackageKind.single,
          packagingCount: 1,
          components: <AIProductCompositionComponent>[_component(1)],
        )),
        1,
      );
    });

    test('dos componentes distintos son una descomposición, no un pack', () {
      // Ese caso lo resuelve el otro camino, con una arista por identidad.
      expect(
        provenPackUnitsForNewProduct(_investigation(
          kind: AIProductPackageKind.composite,
          packagingCount: 2,
          components: <AIProductCompositionComponent>[
            _component(1),
            const AIProductCompositionComponent(
              label: 'Pinza trasera',
              role: AIProductCompositionRole.component,
              quantity: 1,
            ),
          ],
        )),
        1,
      );
    });

    test('si el modelo se contradice consigo mismo no hay pack', () {
      // Dice «pack de 2» y su composición trae 3. Cuando la evidencia no
      // cierra, la salida correcta es no tocar la cantidad.
      expect(
        provenPackUnitsForNewProduct(_investigation(
          kind: AIProductPackageKind.composite,
          packagingCount: 2,
          components: <AIProductCompositionComponent>[_component(3)],
        )),
        1,
      );
    });

    test('un accesorio incluido no convierte el producto en un pack', () {
      // La maza Novatec trae su aguja de bloqueo rápido: sigue siendo UNA maza.
      expect(
        provenPackUnitsForNewProduct(_investigation(
          kind: AIProductPackageKind.composite,
          packagingCount: 2,
          components: <AIProductCompositionComponent>[
            _component(1),
            const AIProductCompositionComponent(
              label: 'Aguja de bloqueo rápido',
              role: AIProductCompositionRole.includedAccessory,
              quantity: 1,
            ),
          ],
        )),
        1,
        reason: 'el componente principal dice 1, no 2',
      );
    });
  });
}
