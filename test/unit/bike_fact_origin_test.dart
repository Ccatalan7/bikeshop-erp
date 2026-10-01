// La ficha decía «Fuente: catalog» o «Fuente: job_completion». Un dato
// trazable dice de dónde vino en palabras del taller (C1/C4, 2026-09-30).
import 'package:flutter_test/flutter_test.dart';

import 'package:vinabike_erp/modules/bikeshop/models/bike_fact_origin.dart';

void main() {
  test('a catalog fact names the model that seeded it', () {
    final model =
        bikeCatalogModelLabel(brand: 'Trek', model: 'Marlin 7', year: 2024);
    expect(model, 'Trek Marlin 7 2024');
    expect(bikeFactOriginLabel('catalog', catalogModel: model),
        'Del modelo Trek Marlin 7 2024');
    expect(bikeFactOriginLabel('catalog'), 'Del modelo en el catálogo');
  });

  test('every source the system writes reads as workshop words', () {
    expect(bikeFactOriginLabel('bike_type'), 'Sugerido por el tipo de bici');
    expect(bikeFactOriginLabel('mechanic'), 'Anotado en el taller',
        reason: 'noting a value is not confirming it');
    expect(bikeFactOriginLabel('job_completion'),
        'Instalado en un trabajo terminado');
    expect(bikeFactOriginLabel('intake'), 'Anotado al recibir la bici');
    expect(bikeFactOriginLabel('manual'), 'Anotado a mano');
  });

  test('the caption says when nobody confirmed the value', () {
    expect(
        bikeFactOriginCaption('catalog',
            confirmed: false, catalogModel: 'Trek Marlin 7 2024'),
        'Del modelo Trek Marlin 7 2024 · sin confirmar');
    expect(bikeFactOriginCaption('mechanic', confirmed: true),
        'Anotado en el taller');
    expect(
        bikeFactOriginCaption('job_diagnosis_sync', confirmed: false), isNull);
  });

  test('an unknown or empty code shows nothing instead of jargon', () {
    expect(bikeFactOriginLabel('job_diagnosis_sync'), isNull);
    expect(bikeFactOriginLabel(''), isNull);
    expect(bikeFactOriginLabel(null), isNull);
    expect(bikeCatalogModelLabel(brand: ' ', model: null), isNull);
  });
}
