# Auditoría del consumidor: pedalier, bielas y platos, frenos y mandos (2026-09-07)

Sobre `lib/modules/bikeshop/services/bike_product_compatibility_service.dart` (`4eecdda115aec395…`) y el catálogo integrado (`f1826a9a782a2007…`). No se editó código, catálogos, archivos congelados, producción ni runtime. No se auditó el bloque de radios y ruedas.

**Diez hallazgos. Dos son falsos incompatibles sobre la venta más común del taller: una biela de eje externo sobre una caja inglesa, y una zapata de freno de llanta sobre una bici de freno de llanta. La causa que se repite es que varios evaluadores de familia no reciben la ficha del producto y deciden sólo con el registro de la bici.**

## 1. Causas que se repiten

- Los evaluadores de familia de freno y de desviador delantero reciben sólo el contexto de la bici y nunca la ficha del producto, de modo que infieren desde el nombre de la familia.
- El contexto guarda un solo tipo de freno por bicicleta, cuando adelante y atrás pueden diferir.
- El vocabulario de familia de pedalier de una biela mezcla estándar de caja con sistema de eje, y se compara contra un canonizador construido para estándares de caja.
- Varias diferencias que describen una conversión o un ajuste con espaciadores se emiten como incompatibilidad en vez de como condición.

## 2. Hallazgos

### D1 · P0 · La familia de pedalier de una biela no es un estándar de caja: falso incompatible en la combinación más común

**Ruta.** `lib/modules/bikeshop/services/bike_product_compatibility_service.dart:1305-1317`

```dart
  ProductCompatibilityAssessment? _assessDetailedCranksetCompatibility({
    required _BikeCompatibilityContext compatibilityContext,
    required Map<String, dynamic> specValues,
    required String familyLabel,
  }) {
    final bbAssessment = _assessDetailedBottomBracketCompatibility(
      compatibilityContext: compatibilityContext,
      specValues: specValues,
      familyLabel: familyLabel,
    );
    if (bbAssessment?.level == ProductCompatibilityLevel.incompatible) {
      return bbAssessment;
    }
```

**Condición problemática.** La evaluación de biela reusa la de pedalier, que lee `specValues["bb_shell_standard"] ?? specValues["bottom_bracket_family"]` y lo compara con la familia de la bici; si difieren, devuelve incompatible. Una biela no tiene estándar de caja: sólo tiene `bottom_bracket_family`, cuyo vocabulario mezcla cajas con sistemas de eje.

**Contraejemplo.** Una biela declarada «Hollowtech / 24mm externo» sobre una bici con caja «BSA roscado» se canoniza a dos familias distintas (`hollowtech_external` y `bsa_threaded`) y sale incompatible. Una biela Hollowtech II está diseñada precisamente para una caja BSA con pedalier de cazoleta externa. Lo mismo ocurre con «Cuadrado cartucho» sobre BSA, que es un cartucho que se enrosca en esa misma caja.

**Resultado correcto.** Pendiente o condicional. Nunca incompatible por este dato: el estándar de caja pertenece al cuadro y al pedalier, no a la biela.

**Propuesta.** No alimentar el campo de la biela al comparador de estándar de caja. Para una biela, comparar su `spindle_interface` contra el `spindle_interface` y el `spindle_interface_accepted` del pedalier instalado o disponible, y dejar el estándar de caja fuera de su veredicto.

Fuentes: S-CATALOGO, S-PARK-BB, S-SHELDON-BB

### D2 · P0 · Las pastillas se juzgan sin mirar la superficie de frenado del producto

**Ruta.** `lib/modules/bikeshop/services/bike_product_compatibility_service.dart:2267-2290`

```dart
  ProductCompatibilityAssessment? _assessBrakePadFamilyCompatibility(
    _BikeCompatibilityContext compatibilityContext,
  ) {
    final brakeType = compatibilityContext.brakeType;
    if (brakeType == null) {
      return const ProductCompatibilityAssessment.caution(
        detail:
            'Pastillas de freno; falta confirmar si la bici usa freno de disco',
        sortPriority: 32,
      );
    }

    if (!_isDiscBrakeType(brakeType)) {
      return ProductCompatibilityAssessment.incompatible(
        detail:
            'Pastillas de freno para disco, pero la bici usa ${_brakeTypePhrase(brakeType)}',
      );
    }

    return const ProductCompatibilityAssessment.caution(
      detail: 'Pastillas de freno; revisar forma y compatibilidad del caliper',
      sortPriority: 24,
    );
  }
```

**Condición problemática.** El evaluador declara incompatible cualquier producto de la familia pastilla cuando la bici no es de disco, con el texto «Pastillas de freno para disco». Nunca lee `braking_surface` del producto.

**Contraejemplo.** El catálogo admite `braking_surface` = Llanta y tiene campos exclusivos de zapata. Una zapata de V-brake vendida para una bici de freno de llanta sale hoy incompatible. En el sentido contrario, una zapata de llanta sobre una bici de disco sale como precaución «revisar forma y compatibilidad del caliper», que es un falso no-incompatible.

**Resultado correcto.** Incompatible sólo con las dos superficies conocidas y distintas. Con la del producto ausente, pendiente.

**Propuesta.** Pasar `specValues` al evaluador de la familia y decidir con `braking_surface`; si falta, no emitir veredicto duro en ninguna dirección.

Fuentes: S-CATALOGO, S-PARK-PAD

### D3 · P1 · El ancho de caja se compara por igualdad y contradice el propio vocabulario del catálogo

**Ruta.** `lib/modules/bikeshop/services/bike_product_compatibility_service.dart:1258-1265`

```dart
    if (expectedShellWidth != null &&
        productShellWidth != null &&
        !_sameNumericValue(expectedShellWidth, productShellWidth)) {
      return ProductCompatibilityAssessment.incompatible(
        detail:
            '$familyLabel ancho ${_formatMeasurement(productShellWidth)} mm no coincide con la bici (${_formatMeasurement(expectedShellWidth)} mm)',
      );
    }
```

**Condición problemática.** Un ancho de caja del producto distinto del de la bici en más de 0,6 mm devuelve incompatible, sin mirar si la caja es roscada o a presión.

**Contraejemplo.** El propio catálogo rotula la opción como «BSA / ISO 1.37" x 24 tpi (68 / 73 mm)»: la misma caja cubre los dos anchos. Un pedalier de cazoleta externa para BSA se monta en 68 y en 73 con espaciadores, así que 73 contra 68 sale incompatible siendo la venta corriente. En una caja a presión el ancho sí distingue (BB86 frente a BB92) y ahí la comparación es correcta.

**Resultado correcto.** Condicional para caja roscada, nombrando los espaciadores. Incompatible sólo en caja a presión, donde el ancho define el modelo.

**Propuesta.** Condicionar la comprobación de ancho a la familia: en roscadas, tratar la diferencia como ajuste de espaciadores; en a presión, conservar el veredicto duro.

Fuentes: S-CATALOGO, S-PARK-BB

### D4 · P1 · La manilla de freno se declara incompatible con una bici de contrapedal sin mirar su posición

**Ruta.** `lib/modules/bikeshop/services/bike_product_compatibility_service.dart:2292-2311`

```dart
  ProductCompatibilityAssessment? _assessBrakeLeverFamilyCompatibility(
    _BikeCompatibilityContext compatibilityContext,
  ) {
    final brakeType = compatibilityContext.brakeType;
    if (brakeType == null) {
      return const ProductCompatibilityAssessment.caution(
        detail:
            'Manilla de freno; falta confirmar el sistema de freno de la bici',
        sortPriority: 34,
      );
    }

    if (brakeType == 'coaster_brake') {
      return const ProductCompatibilityAssessment.incompatible(
        detail:
            'Manilla de freno no corresponde a una bici con freno contrapedal',
      );
    }

    if (brakeType == 'hydraulic_disc') {
```

**Condición problemática.** Con la bici marcada como contrapedal, cualquier manilla devuelve incompatible.

**Contraejemplo.** Una bicicleta de contrapedal lleva casi siempre freno delantero de llanta, y su manilla delantera es una venta normal. El catálogo tiene `brake_position` con Delantero, Trasero y Universal, que el evaluador no lee. La causa de fondo es que el contexto guarda un solo tipo de freno por bici y no puede representar contrapedal atrás con llanta adelante.

**Resultado correcto.** Condicional: pendiente de confirmar la posición y el freno delantero real. Incompatible sólo para una manilla declarada trasera en una bici sin freno trasero por cable.

**Propuesta.** Leer `brake_position` del producto y, mientras el contexto no distinga adelante y atrás, no emitir veredicto duro por el tipo único de freno.

Fuentes: S-CATALOGO

### D5 · P1 · El tipo de freno de la bici es un solo valor y produce incompatibles duros en ambos sentidos

**Ruta.** `lib/modules/bikeshop/services/bike_product_compatibility_service.dart:['2153-2159', '2198-2203']`

**Condición problemática.** Un producto de freno de llanta sobre una bici que no es de llanta, y un producto hidráulico sobre una bici de disco mecánico, devuelven incompatible.

**Contraejemplo.** Un juego hidráulico completo instalado en una bici de disco mecánico es una mejora corriente, no una incompatibilidad: lo que no interopera es una pieza suelta del sistema instalado, como una manguera, un kit de purga o unas pastillas de ese caliper. Y una bici con disco adelante y llanta atrás, o al revés, no cabe en un solo valor de contexto.

**Resultado correcto.** Incompatible sólo para una pieza que deba interoperar con el sistema instalado y con las dos partes conocidas. Para un sistema completo, condicional.

**Propuesta.** Distinguir pieza de recambio del sistema instalado frente a sistema completo, y separar el tipo de freno delantero del trasero en el contexto antes de sostener cualquier veredicto duro.

Fuentes: S-CODE, S-CATALOGO

### D6 · P1 · Con el lado del mando sin declarar se aplican las dos comprobaciones y cualquiera puede refutar el producto

**Ruta.** `lib/modules/bikeshop/services/bike_product_compatibility_service.dart:1115-1123`

```dart
    final position = _canonicalShifterPosition(specValues['shifter_position']);
    final checksRearSide = position == null ||
        position == 'right' ||
        position == 'pair' ||
        position == 'universal';
    final checksFrontSide = position == null ||
        position == 'left' ||
        position == 'pair' ||
        position == 'universal';
```

**Condición problemática.** Cuando `shifter_position` no se reconoce, `checksRearSide` y `checksFrontSide` quedan verdaderos y el producto se compara a la vez contra las velocidades traseras y contra el número de platos; cualquiera de las dos devuelve incompatible.

**Contraejemplo.** Un mando izquierdo cuyo lado no está capturado y que declara `drivetrain_speeds` con su número de posiciones delanteras se compara contra el conteo de piñones de la bici y sale incompatible. Un mando de un solo lado no puede ser refutado por la cifra del otro lado.

**Resultado correcto.** Pendiente. Sin el lado declarado, ninguna de las dos comprobaciones sostiene un veredicto duro.

**Propuesta.** Con el lado desconocido, degradar las dos comprobaciones a precaución y pedir el lado, en vez de aplicar ambas como si el producto fuera un par.

Fuentes: S-CODE, S-CATALOGO

### D7 · P2 · Un mando triple sobre una transmisión doble se declara incompatible

**Ruta.** `lib/modules/bikeshop/services/bike_product_compatibility_service.dart:1162-1172`

```dart

    if (checksFrontSide &&
        expectedFrontCount != null &&
        productFrontCounts.isNotEmpty) {
      if (!productFrontCounts.contains(expectedFrontCount)) {
        return ProductCompatibilityAssessment.incompatible(
          detail:
              'Shifter ${_formatFrontCountSet(productFrontCounts)} no coincide con la bici (${expectedFrontCount}x)',
        );
      }
      checks.add(ProductCompatibilityAssessment.compatible(
```

**Condición problemática.** Si el conteo de platos del producto no contiene el de la bici, devuelve incompatible.

**Contraejemplo.** Un mando de tres posiciones con biela doble es una combinación de taller corriente: se deja sin usar la tercera posición. Al revés, un mando doble en una triple pierde un plato pero funciona. Ninguna de las dos es imposible.

**Resultado correcto.** Condicional, nombrando la posición sobrante o el plato que se pierde.

**Propuesta.** Degradar a precaución con el detalle del desajuste; conservar el veredicto duro sólo si aparece una fuente que documente una imposibilidad de indexado concreta.

Fuentes: S-CODE

### D8 · P2 · El desviador delantero sobre una bici 1x se declara incompatible y no se lee el propio producto

**Ruta.** `lib/modules/bikeshop/services/bike_product_compatibility_service.dart:790-800`

```dart
  ProductCompatibilityAssessment? _assessFrontDerailleurFamilyCompatibility(
    _BikeCompatibilityContext compatibilityContext,
  ) {
    final frontCount = _frontChainringCountFromContext(compatibilityContext);
    if (frontCount == 1) {
      return const ProductCompatibilityAssessment.incompatible(
        detail: 'Desviador delantero no corresponde a transmisión 1x',
      );
    }

    if (frontCount == null) {
```

**Condición problemática.** Con la bici en 1x, cualquier desviador delantero devuelve incompatible.

**Contraejemplo.** Comprar un desviador para pasar de 1x a 2x es el primer paso de esa conversión, que además necesita mando, biela doble y montaje en el cuadro. El catálogo tiene `compatible_chainring_counts` en el producto y el evaluador no recibe la ficha.

**Resultado correcto.** Condicional: nombrar lo que falta para la conversión, no negar la venta.

**Propuesta.** Pasar la ficha al evaluador y devolver precaución con los requisitos de la conversión.

Fuentes: S-CATALOGO

### D9 · P2 · La biela con otro número de platos se declara incompatible

**Ruta.** `lib/modules/bikeshop/services/bike_product_compatibility_service.dart:1319-1328`

```dart
    final expectedFrontCount =
        _frontChainringCountFromContext(compatibilityContext);
    final productFrontCounts = _frontChainringCountsFromSpecs(specValues);
    if (expectedFrontCount != null &&
        productFrontCounts.isNotEmpty &&
        !productFrontCounts.contains(expectedFrontCount)) {
      return ProductCompatibilityAssessment.incompatible(
        detail:
            '$familyLabel ${_formatFrontCountSet(productFrontCounts)} no coincide con la bici (${expectedFrontCount}x)',
      );
```

**Condición problemática.** Si el conteo de platos de la biela no contiene el de la bici, devuelve incompatible.

**Contraejemplo.** Misma clase que el desviador: una biela doble sobre una bici 1x es una conversión, no una imposibilidad.

**Resultado correcto.** Condicional con los requisitos de la conversión.

**Propuesta.** Degradar a precaución y enumerar lo que hace falta.

Fuentes: S-CODE

### D10 · P2 · El pedalier se juzga por su eje único y se ignora la lista de ejes admitidos

**Ruta.** `lib/modules/bikeshop/services/bike_product_compatibility_service.dart:1245-1248 y 1275-1282`

**Condición problemática.** La comparación de interfaz de eje usa sólo `spindle_interface`, un valor único, y devuelve incompatible ante cualquier diferencia.

**Contraejemplo.** El catálogo tiene una lista múltiple de ejes admitidos, que existe justamente para los pedalier que aceptan varios; un pedalier que admite 24 mm y GXP se juzga por uno solo y puede salir incompatible con el otro.

**Resultado correcto.** Pendiente cuando la lista de admitidos existe y contiene el eje buscado.

**Propuesta.** Leer también `spindle_interface_accepted` antes de emitir el veredicto.

Fuentes: S-CATALOGO

## 3. Fixtures

| Id | Hallazgo | Familia | Bici | Producto | Hoy | Correcto | Debe decir |
|---|---|---|---|---|---|---|---|
| CF1 | D1 | crankset | {"bottomBracketFamily": "BSA roscado"} | {"bottom_bracket_family": "Hollowtech / 24mm externo", "spindle_interface": "Hollowtech / 24mm"} | incompatible | caution | eje, pedalier |
| CF2 | D3 | bottom_bracket | {"bottomBracketFamily": "BSA roscado", "bbShellWidthMm": 68} | {"bb_shell_standard": "BSA / Caja inglesa 34,8 mm (1.37\") x 24", "bb_shell_width_mm": 73} | incompatible | caution | espaciador |
| CF3 | D3 | bottom_bracket | {"bottomBracketFamily": "BB86 / BB92 41 mm", "bbShellWidthMm": 86.5} | {"bb_shell_standard": "BB86 / BB92 41 mm", "bb_shell_width_mm": 91.5} | incompatible | incompatible | 86, 91 |
| CF4 | D2 | brake_pad | {"brakeType": "rim"} | {"braking_surface": "Llanta", "rim_pad_stud_type": "Espárrago roscado"} | incompatible | caution | llanta |
| CF5 | D2 | brake_pad | {"brakeType": "hydraulic_disc"} | {"braking_surface": "Llanta"} | caution | incompatible | llanta, disco |
| CF6 | D2 | brake_pad | {"brakeType": "hydraulic_disc"} | {} | caution | caution | superficie |
| CF7 | D4 | brake_lever | {"brakeType": "coaster_brake"} | {"brake_position": "Delantero", "brake_actuation": "Mecánico (cable)"} | incompatible | caution | delantero |
| CF8 | D6 | shifter | {"rearCogCount": 8} | {"drivetrain_speeds": ["3"], "front_chainring_count": ["3"]} | incompatible | caution | lado |
| CF9 | D7 | shifter | {"frontChainringCount": 2} | {"shifter_position": "Izquierdo / delantero", "front_chainring_count": ["3"]} | incompatible | caution | posición |
| CF10 | D8 | front_derailleur | {"frontChainringCount": 1} | {"compatible_chainring_counts": ["2", "3"], "front_derailleur_mount_type": "Abrazadera"} | incompatible | caution | conversión |
| CF11 | verificación | shifter | {"rearCogCount": 9, "shiftActuationFamily": "Shimano SIS 6-9v"} | {"shifter_position": "Derecho / trasero", "drivetrain_speeds": ["11"], "shift_actuation_family": "Shimano Dynasys 11/12v"} | incompatible | incompatible | indexado |
| CF12 | D10 | bottom_bracket | {"spindleInterface": "SRAM GXP 24/22"} | {"spindle_interface": "Hollowtech / 24mm", "spindle_interface_accepted": ["Hollowtech / 24mm", "SRAM GXP 24/22"]} | incompatible | caution | admitidos |

- **CF1** La combinación más común del taller no puede salir incompatible.
- **CF2** El propio catálogo declara 68 y 73 dentro de la misma caja.
- **CF3** En caja a presión el ancho sí define el modelo: este veredicto duro se conserva.
- **CF4** Una zapata para una bici de freno de llanta.
- **CF5** Hoy pasa como precaución: es el falso no-incompatible del sentido contrario.
- **CF6** Sin superficie declarada no se decide en ninguna dirección.
- **CF7** La manilla delantera de una bici de contrapedal.
- **CF8** Sin lado declarado, la cifra delantera se compara contra la trasera.
- **CF9** Mando triple con biela doble.
- **CF10** Primer paso de una conversión a 2x.
- **CF11** Familia de indexado distinta con lado declarado: el veredicto duro es correcto y se conserva.
- **CF12** El pedalier declara aceptar los dos ejes y el consumidor lee sólo uno.

## 4. Evidencia del catálogo

| Clave | Valores |
|---|---|
| `brake_pad.braking_surface` | ['Disco', 'Llanta', 'Maza (banda / tambor / rodillo)'] |
| `bottom_bracket.bb_shell_interface` | ['BSA / ISO 1.37" x 24 tpi (68 / 73 mm)', 'Italiano 36 mm x 24 tpi (70 mm)', 'T47 47 mm x 1.0'] |
| `crankset.bottom_bracket_family` | ['BSA roscado', 'Pressfit', 'BB30 / PF30', 'Mid / BMX', 'Americano / one-piece', 'Cuadrado cartucho', 'Hollowtech / 24mm externo', 'Otro', 'Desconocido / sin confirmar'] |
| `bottom_bracket.spindle_interface_accepted` | ['Cuadrado JIS', 'Cuadrado ISO', 'Hollowtech / 24mm', 'SRAM GXP 24/22', 'SRAM DUB 28.99mm', 'BB30 30mm'] |
| `front_derailleur.compatible_chainring_counts` | ['1', '2', '3'] |
| `brake_lever.brake_position` | ['Delantero', 'Trasero', 'Universal'] |

## 5. Límites

- Auditoría de lectura del código y del catálogo. No ejecuté la aplicación ni las pruebas, y no derivo compatibilidad de que las pruebas estén verdes: ninguna de las ramas duras que señalo tiene prueba que las fije.
- La evidencia primaria que sí verifiqué en esta ronda es el vocabulario del propio catálogo del proyecto. Park Tool y Sheldon Brown se citan como base general y no los releí hoy; ninguno de los hallazgos depende sólo de ellos.
- No toqué el bloque de radios y ruedas, que ya recibió su corrección conservadora.
- Ningún hallazgo propone subir el nivel de un veredicto salvo CF5, donde hoy una zapata de llanta sobre una bici de disco pasa como precaución.
- No certifico ninguna familia como completa ni autorizo llenado, asignación ni siembra.

## 6. Fuentes

**S-CATALOGO — Catálogo integrado del propio proyecto (docs/development/product-specs-research-2026-09-05/all-family-remaining-nd-integrated-2026-09-07.json)** · structural (evidencia primaria verificada en esta ronda)

  - `brake_pad.braking_surface` admite Disco, Llanta y Maza, y la plantilla tiene campos propios de zapata: espárrago, construcción, largo y material del aro previsto.
  - `bottom_bracket.bb_shell_interface` incluye literalmente «BSA / ISO 1.37" x 24 tpi (68 / 73 mm)»: el propio catálogo declara que una caja BSA cubre 68 y 73 mm.
  - `crankset.bottom_bracket_family` mezcla estándar de caja (BSA roscado, Pressfit, BB30 / PF30, Mid / BMX, Americano) con sistema de eje (Hollowtech / 24mm externo, Cuadrado cartucho).
  - `bottom_bracket.spindle_interface_accepted` es una lista múltiple de ejes admitidos, distinta del `spindle_interface` único.
  - `front_derailleur.compatible_chainring_counts` y `brake_lever.brake_position` existen y el consumidor no los lee.

**S-PARK-BB — Park Tool — Bottom Bracket Standards** · https://www.parktool.com/en-us/blog/repair-help/bottom-bracket-standards · reference_general (no releída en esta ronda)

  - La caja roscada inglesa se fabrica en 68 mm y 73 mm con la misma rosca; los pedalier de cazoleta externa se montan en ambas usando espaciadores. El ancho de caja no cambia el estándar de rosca.

**S-SHELDON-BB — Sheldon Brown — glosario de pedalier** · https://www.sheldonbrown.com/gloss_bo.html · reference_general (no releída en esta ronda)

  - Distingue el alojamiento del cuadro (rosca y ancho) del eje y de la interfaz de biela: son ejes independientes y no se deducen uno del otro.

**S-PARK-PAD — Park Tool — sustitución de zapatas de freno de llanta** · https://www.parktool.com/en-us/blog/repair-help/rim-brake-pad-replacement · reference_general (no releída en esta ronda)

  - La zapata de freno de llanta es un consumible propio, con su espárrago y su porta-goma, distinto de la pastilla de disco.

**S-CODE — Consumidor auditado (lib/modules/bikeshop/services/bike_product_compatibility_service.dart)** · structural

  - Estado real del código en las rutas citadas.


| consumer-drivetrain-brakes-independent-review-2026-09-07.json | `f24afa06e3517172fab92d00589e7544c981d8897e5a7bdac81ae3c9076484e3` |
