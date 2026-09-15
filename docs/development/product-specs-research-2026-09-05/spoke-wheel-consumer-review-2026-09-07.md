# W11 en el consumidor real: largo de radio y conteo de agujeros (2026-09-07)

Revisión de `lib/modules/bikeshop/services/bike_product_compatibility_service.dart` (`15e9d0aa9e11f49f…`) y de `test/unit/bike_product_compatibility_service_test.dart` (`62f726ef04b20437…`). Propuesta: no se editó el consumidor, sus pruebas, el paquete WSS congelado, la base ni el runtime. Llenado y publicación siguen en cero.

**La regla de ±1 mm no está en este consumidor: el largo del radio no se usa en absoluto. Las dos reglas de conteo de agujeros sí están, y devuelven incompatible por comparar la pieza con la bicicleta en vez de con su contraparte de armado.**

## 1. Hallazgos

### C1 · P0 de premisa · La regla de ±1 mm no existe en este consumidor

**Evidencia.** `spoke_length_mm` aparece una sola vez en lib/modules/bikeshop/services/bike_product_compatibility_service.dart, dentro de la lista blanca de claves de ficha (línea 56). `_assessSpokeFamilyCompatibility` (línea 1972) no lo lee: decide sólo con los conteos de agujeros de la bici y siempre devuelve `caution`.

**Veredicto.** W11 describía el blueprint, no el consumidor desplegado. Aquí no hay nada que corregir en el largo: hay algo que falta.

**Acción.** No introducir la regla. Corregir el mensaje para que nombre el largo declarado del producto (P3) y dejar la comparación de largo donde están los datos que la permiten: el módulo de armado.

### C2 · P1 · Un conteo de agujeros distinto al de la bici devuelve incompatible

**Evidencia.** lib/modules/bikeshop/services/bike_product_compatibility_service.dart:1559-1566 (maza) y :1674-1679 (llanta) devuelven `ProductCompatibilityAssessment.incompatible` cuando el conteo del producto difiere del registrado en la bici.

**Veredicto.** Físicamente falso. El conteo tiene que casar entre aro y maza de la rueda que se arma, no entre la pieza y la bicicleta. Una maza de 32H para una bici con ruedas de 36H no es incompatible con la bici: es incompatible con reutilizar ese aro en un radiado estándar. Comprar maza y aro de 32H, o armar una rueda nueva, es trabajo corriente, y este taller arma ruedas.

**Acción.** Degradar a `caution` con un mensaje que diga la condición real (P1, P2).

### C3 · P1 · Un solo número de la bici alimenta los dos lados

**Evidencia.** lib/modules/bikeshop/services/bike_product_compatibility_service.dart:2533-2536 rellena `frontSpokeHoles` y `rearSpokeHoles` con el mismo `bike.spokeCount`, que en `lib/modules/bikeshop/models/bikeshop_models.dart:135` es un único `int?` para toda la bicicleta.

**Veredicto.** Una bici con 32H delante y 36H detrás queda registrada con un número; con la regla actual, una maza trasera correcta de 36H se declara incompatible contra un 32 que nunca fue del eje trasero.

**Acción.** Marcar el conteo como agregado sin lado y no permitir que una diferencia contra un agregado produzca un veredicto duro (P4).

### C4 · P2 · Los dos veredictos duros no tienen prueba

**Evidencia.** test/unit/bike_product_compatibility_service_test.dart sólo ejerce conteos coincidentes: `spoke_holes: 32` contra `32` en las líneas 691, 713 y 737. Ninguna prueba entra a las ramas `incompatible` de 1562 ni de 1675.

**Veredicto.** Las dos reglas más fuertes del bloque de ruedas se cambiaron y se podrían volver a cambiar sin que nada falle.

**Acción.** Las regresiones F1–F7 de este documento cubren las dos ramas, en su forma corregida.

### C5 · informativo · La tolerancia real vive en una búsqueda, no en un veredicto

**Evidencia.** `lib/modules/bikeshop/services/wheel_building_service.dart:346-348` expone `findCompatibleSpokes({required double requiredLengthMm, double toleranceMm = 2.0})`, que delega en la RPC `find_compatible_spokes`. El largo calculado sale de la ley de cosenos en las líneas 20-73 del mismo archivo, sin compensación por tensado y redondeando a 0,1 mm.

**Veredicto.** La forma es la correcta: filtrar candidatos, no aprobar un armado. El problema es de nombre y de metadato: «compatible» sugiere aprobación y el largo calculado no registra con qué método se obtuvo, que es justo lo que la fuente pide distinguir.

**Acción.** Fuera del alcance de este encargo (toca otro servicio y una RPC). Se deja anotado para root con su preimagen; no propongo cambio de firma aquí.

## 2. Cambios propuestos, con preimagen exacta

### P1 (C2) — `lib/modules/bikeshop/services/bike_product_compatibility_service.dart:1559-1566`

Preimagen:

```dart
    if (spokeHoles != null &&
        expectedSpokeHoles != null &&
        spokeHoles != expectedSpokeHoles) {
      return ProductCompatibilityAssessment.incompatible(
        detail:
            'Maza ${_wheelPositionLabel(wheelPosition)} ${spokeHoles}H no coincide con la bici (${expectedSpokeHoles}H)',
      );
    }
```

Propuesta:

```dart
    if (spokeHoles != null &&
        expectedSpokeHoles != null &&
        spokeHoles != expectedSpokeHoles) {
      // El conteo casa entre aro y maza de la rueda que se arma, no entre la
      // pieza y la bicicleta: armar con la contraparte del mismo conteo es
      // trabajo corriente. La diferencia describe el armado, no lo prohíbe.
      return ProductCompatibilityAssessment.caution(
        detail:
            'Maza ${_wheelPositionLabel(wheelPosition)} ${spokeHoles}H: la rueda registrada de la bici tiene ${expectedSpokeHoles}H. Sirve armando con un aro de ${spokeHoles}H; no reutiliza el aro actual.',
        sortPriority: 20,
      );
    }
```

**Por qué.** La igualdad de conteos es una condición del par aro-maza dentro de un radiado estándar. La fuente de Sheldon sobre armado no la enuncia como ley ni documenta excepciones, así que tampoco se convierte en prohibición: se dice qué haría falta.

**Qué no hace.** No se aprueba nada: el veredicto sigue siendo precaución y el mensaje nombra la condición pendiente.

### P2 (C2) — `lib/modules/bikeshop/services/bike_product_compatibility_service.dart:1674-1679`

Preimagen:

```dart
      if (knownSpokeSides.isNotEmpty && matchingSides.isEmpty) {
        return ProductCompatibilityAssessment.incompatible(
          detail:
              'Llanta ${productSpokeHoles}H no coincide con la bici (${knownSpokeSides.join(' / ')})',
        );
      }
```

Propuesta:

```dart
      if (knownSpokeSides.isNotEmpty && matchingSides.isEmpty) {
        // Misma razón que en la maza: el conteo empareja aro con maza, no
        // producto con bicicleta.
        return ProductCompatibilityAssessment.caution(
          detail:
              'Llanta ${productSpokeHoles}H: la bici registra ${knownSpokeSides.join(' / ')} con otro conteo. Sirve armando con una maza de ${productSpokeHoles}H; no reutiliza la maza actual.',
          sortPriority: 20,
        );
      }
```

**Por qué.** Simétrica de P1. Además, con la corrección el aro deja de bloquearse y sigue su camino normal por los avisos de asiento, ancho, presión y freno que ya emite el bloque.

**Qué no hace.** No cambia el aviso de tamaño de aro ni el de válvula, que son otros ejes.

### P3 (C1) — `lib/modules/bikeshop/services/bike_product_compatibility_service.dart:1991-1995`

Preimagen:

```dart
    return ProductCompatibilityAssessment.caution(
      detail:
          'Rayo; revisar largo, calibre y perforaciones (${knownHoleCounts.join('/')}H)',
      sortPriority: 28,
    );
```

Propuesta:

```dart
    return ProductCompatibilityAssessment.caution(
      detail:
          'Rayo; el largo no se decide con los datos de la bici: hace falta ERD del aro, diámetro y separación de bridas de la maza, patrón y niple. Perforaciones registradas: ${knownHoleCounts.join('/')}H.',
      sortPriority: 28,
    );
```

**Por qué.** El consumidor no tiene ninguno de los datos con los que se calcula un largo. Decirlo evita que el mensaje «revisar largo» se lea como que ya se revisó, y nombra exactamente qué falta.

**Qué no hace.** No compara `spoke_length_mm` con nada ni introduce tolerancia: eso pertenece a la calculadora, con su método declarado.

### P4 (C3) — `lib/modules/bikeshop/services/bike_product_compatibility_service.dart:2533-2536`

Preimagen:

```dart
      frontSpokeHoles:
          _parseIntValue(technicalValues['frontSpokeHoles']) ?? bike.spokeCount,
      rearSpokeHoles:
          _parseIntValue(technicalValues['rearSpokeHoles']) ?? bike.spokeCount,
```

Propuesta:

```dart
      frontSpokeHoles: _parseIntValue(technicalValues['frontSpokeHoles']),
      rearSpokeHoles: _parseIntValue(technicalValues['rearSpokeHoles']),
      // `bike.spokeCount` es un solo número para toda la bicicleta: no dice de
      // qué rueda es. Se conserva aparte y nunca se atribuye a un lado.
      aggregateSpokeHoles: bike.spokeCount,
```

**Por qué.** Un agregado sin lado no puede sostener una afirmación por lado. Con P1 y P2 ya no produce un veredicto duro, y con este cambio tampoco produce una coincidencia falsa: hoy un 32 agregado «coincide» con una maza trasera de 32 aunque la rueda trasera tenga 36.

**Qué no hace.** Exige un campo nuevo en `_BikeCompatibilityContext` y ajustar los puntos que hoy leen los dos campos; el agregado se usa sólo para el texto («la bici registra 32H sin distinguir rueda»), nunca para coincidir ni para descartar.

**Alcance.** Cambio de mayor alcance que P1–P3: root decide si entra en la misma corrección o después. P1–P3 son correctos por sí solos.

## 3. Fixtures de regresión

| Id | Tipo | Familia | Bici | Producto | Hoy | Esperado | Debe decir |
|---|---|---|---|---|---|---|---|
| F1 | válido (armado con contraparte) | rear_hub | {"rearSpokeHoles": 36} | {"wheel_position": "rear", "spoke_holes": 32} | incompatible | caution | 32H, 36H, armando con un aro |
| F2 | válido (armado con contraparte) | rim | {"frontSpokeHoles": 32} | {"spoke_holes": 36} | incompatible | caution | 36H, armando con una maza |
| F3 | válido (coincide) | rear_hub | {"rearSpokeHoles": 32} | {"wheel_position": "rear", "spoke_holes": 32} | caution | caution | 32H |
| F4 | desconocido | rear_hub | {} | {"wheel_position": "rear", "spoke_holes": 32} | caution | caution | perforaciones de la rueda |
| F5 | desconocido (largo) | spoke | {"frontSpokeHoles": 32} | {"spoke_length_mm": 263, "spoke_gauge": "14G"} | caution con «revisar largo» | caution | ERD, bridas, patrón |
| F6 | incompatible que debe seguir siéndolo | rear_hub | {"rearSpokeHoles": 32, "rearHubSpacingMm": 135} | {"wheel_position": "rear", "spoke_holes": 32, "hub_spacing_mm": 148} | incompatible | incompatible | 148, 135 |
| F7 | no detectable | rear_hub | {"spokeCount_aggregate": 32} | {"wheel_position": "rear", "spoke_holes": 32} | caution que afirma coincidencia por lado | caution | sin distinguir rueda |

- **F1** Caso que hoy se bloquea y es una compra normal para armar rueda.
- **F2** Simétrico de F1 por el lado del aro.
- **F3** No cambia: coincidir sigue sin aprobar el eje ni el cuerpo del núcleo.
- **F4** Sin conteo registrado, la falta se declara; no se rellena con un valor típico.
- **F5** Un radio de 263 mm del inventario real: el consumidor no puede decir nada del largo y ahora lo dice con precisión.
- **F6** La corrección no toca el ancho entre punteras: sigue siendo un veredicto duro y esta prueba lo fija. (Su propio matiz Gnot-rite es W08, fuera de este encargo.)
- **F7** Sólo con P4. Hoy un agregado de 32 se presenta como coincidencia de la rueda trasera aunque la trasera sea de 36; el dato no alcanza para afirmarlo ni para negarlo.

## 4. Qué puede y qué no puede concluir el consumidor actual

- El consumidor compara un producto contra el registro de la bicicleta, que tiene un único conteo de agujeros y ningún ERD, brida ni patrón. Con esos datos no puede concluir nada sobre el largo de un radio, ni antes ni después de esta corrección.
- Tampoco puede concluir que un conteo distinto impida algo: no sabe si el cliente reutiliza el aro, compra los dos o arma una rueda nueva. Lo máximo honesto es nombrar la condición.
- La igualdad de conteos entre aro y maza es la condición del radiado estándar; la página de armado de Sheldon no la enuncia como ley ni documenta excepciones, así que este documento no la convierte en prohibición ni afirma que existan excepciones útiles.
- La ausencia de receta de armado no es compatibilidad: ninguna de las correcciones sube el nivel de un veredicto, todas lo bajan de prohibición a condición declarada.
- La comparación de largo sí es posible en el módulo de armado, donde existen ERD, bridas, patrón y niple. Ese camino ya usa una búsqueda por tolerancia; su revisión es otro encargo (C5).

## 5. Fuentes

**S-SHELDON-BUILD — Sheldon Brown — Wheelbuilding** · https://www.sheldonbrown.com/wheelbuild.html · reference_general · lectura web 2026-09-07

  - Sobre el largo: recomienda redondear al tamaño disponible inmediatamente mayor y dice que el largo no es supercrítico, aunque es peor quedarse corto que pasarse.
  - Los límites que sí nombra son físicos y no simétricos: un radio demasiado largo estorba el destornillador, sobresale y puede pinchar la cámara; más largo todavía toca fondo en la rosca y no se puede tensar.
  - Menciona que los radios del lado derecho suelen ser 1 o 2 mm más cortos que los del izquierdo, sin fijar una tolerancia por radio.
  - NO enuncia como ley que aro y maza deban tener el mismo número de agujeros, y NO documenta excepciones a esa igualdad.

**S-SHELDON-LENGTH — Sheldon Brown / John Allen — Measurements for Spoke-Length Calculations** · https://www.sheldonbrown.com/spoke-length.html · reference_general · citada en la revisión W del 2026-09-06 (fuente S24); no releída en esta ronda

  - El margen depende del método de cálculo, de si la calculadora incorpora compensación por tensado, del niple y de la longitud de rosca. No prescribe ±1 mm ni conteos iguales.

**S-CODE — Consumidor y módulo de armado del repositorio (lib/modules/bikeshop/services/bike_product_compatibility_service.dart, wheel_building_service.dart, wheel_building_models.dart, spoke_length_calculator_page.dart)** · structural · lectura de código 2026-09-07

  - El taller sí arma ruedas: existen WheelBuild con patrón de radiado y largos calculados por lado, una calculadora por ley de cosenos y una búsqueda de radios por tolerancia.

**S-INVENTARIO — Evidencia de inventario ya registrada en esta carpeta de investigación** · inventory · documentos existentes 2026-09-07

  - El catálogo vende radios por largo en milímetros (185, 195, 257, 260, 263, 265, 270, 280 mm), varios «con niples» y rotulados «compatibles / genérico».

## 6. Compuertas

- Ninguna corrección sube el nivel de un veredicto; todas bajan de prohibición a condición declarada.
- P1–P3 son independientes y aplicables por separado; P4 exige un campo nuevo en el contexto y lo decide root.
- No se tocó DB, runtime, consumidor, pruebas ni el paquete WSS congelado.
- Llenado, asignación y publicación siguen en cero.

| spoke-wheel-consumer-review-2026-09-07.json | `9b64d43838a5363da81e8112b9ba4264f7dbef4d0db053f6744a7b729686a95b` |
