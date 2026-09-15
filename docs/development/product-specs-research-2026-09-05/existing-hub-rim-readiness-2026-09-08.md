# Candidato correctivo `hub` + `rim` — 2026-09-08

**Adjudicación posterior:** este informe conserva la propuesta independiente
inicial. El [candidato actual de Root](existing-hub-rim-root-decisions-2026-09-08.md)
corrige la propiedad de todas las interfaces del juego, la rosca de eje pasante,
la representación de otros ejes, el perfil tubular y las cotas/límites OEM.
Claude aceptó que excluir información por falta de consumidor era un criterio
equivocado. Los conteos y exclusiones del informe que sigue son históricos;
no se utilizan para declarar completo el candidato actual.

Sucesor local, **no aplicado**, para las dos plantillas de rueda. Sin escrituras
de producción, sin migración, sin asignación, sin llenado automático y sin
operación de UI viva. Este documento contiene sólo metadatos, agregados y
ejemplos OEM públicos.

## 1. Entradas fijadas

| entrada | sha256 |
|---|---|
| `all-family-port-cardinality-integrated-2026-09-07.json` | `16459826…fadf15` |
| `all-family-port-cardinality-cases-integrated-2026-09-07.json` | `329ad3e5…3716d7` |
| `existing-hub-rim-preimage-2026-09-08.json` | `d9ac1275…24dfe` |

La preimagen es fresca (captura del 2026-09-08) y trae 27 definiciones
publicadas, las dos plantillas y sus 20 vínculos de campo. Vínculos explícitos
de producto: 0 en ambas familias; vínculos efectivos: **48 mazas y 41 llantas**.

Salida: 2 plantillas, 41 definiciones, 44 usos de campo, 30 casos ejecutables y
6 casos pendientes.

## 2. El bloqueador real: la base congelada altera dos definiciones publicadas

Comparando la preimagen fresca contra la base congelada, **cada definición
publicada coincide byte a byte salvo dos**, y las dos son de vocabulario
compartido:

| clave | publicado hoy | lo que propone la base congelada | compartida con |
|---|---|---|---|
| `wheel_position` | `Delantera · Trasera · Universal` | agrega `Par` | `hub_axle`, `hub_small_part`, `wheel_retention`, `wheel` |
| `rotor_mount_type` | `6 pernos · Centerlock` | agrega `Desconocido / sin confirmar` | `rotor`, `wheel` |

El publicador rechaza exactamente eso: compara `id`, `key`, `label`,
`data_type`, `unit`, `allowed_values` y `validation_rules` de cada definición
reutilizada y aborta con `Shared definition must remain unchanged: <key>`
(`scripts/inventory/compile_existing_spec_publication.py:99-103`). Con la base
tal cual, el paquete de `hub` **no se puede publicar**.

Y el daño no es sólo de publicación. La compuerta del receptor de transmisión
está escrita como `wheel_position = Trasera`, así que el token `Par` que la
base agrega deja el envase de dos mazas **prohibido** de declarar su propio
receptor. Reproducido contra la base congelada, sin modificarla:

| sonda sobre la base congelada | resultado |
|---|---|
| `wheel_position='Par'` + `rear_drive_interface` | **bloquea** (`field_applicability:rear_drive_interface`) |
| `wheel_position='Par'` + un único `hub_old_mm` | pasa sin observación |

Es decir: la base prohíbe el dato correcto y acepta en silencio el incorrecto,
porque un envase de dos mazas no tiene un solo ancho entre punteras.

**Corrección aplicada aquí.** Ninguna definición publicada se toca:

- `rotor_mount_type` vuelve a su vocabulario publicado. El token añadido era
  además **inerte**: el motor lee `Desconocido / sin confirmar` como celda
  ausente (`spec_rule_evaluator.dart:5-13`), de modo que elegirlo daba el mismo
  resultado que no elegir nada. Lo que sí faltaba —poder decir que una maza
  *no* tiene anclaje de disco— se resuelve con un booleano nuevo.
- `wheel_position` se **retira a legacy dentro de la plantilla `hub`** y se
  clona en un sucesor de alcance propio, `hub_package_position`, con la cuarta
  opción que el negocio necesita. La definición global queda intacta y las
  otras cuatro familias que la comparten no se enteran.

## 3. Correcciones en `hub`

| id | corrección | por qué |
|---|---|---|
| H-1 | `hub_package_position` (sucesor con retiro legacy de `wheel_position`), requerido siempre | **8 de las 48** mazas se venden como envase de dos mazas |
| H-2 | `hub_package_pieces`: tabla de piezas del envase, permitida y exigida sólo para el juego; `hub_old_mm` y `spoke_hole_count` quedan permitidos sólo para una maza suelta | un juego tiene dos anchos y dos perforaciones, no uno de cada |
| H-3 | `rear_drive_interface` permitido y exigido para `Trasera` **o** juego | la mitad trasera de un juego sí tiene receptor |
| H-4 | `hub_spoke_head_interface` (J-Bend · Straight Pull · Otro anclaje OEM) | el anclaje de rayos tenía cotas de brida pero ningún campo que dijera **qué cabeza de rayo admite** |
| H-5 | `hub_rotor_mount_present` (booleano) como compuerta de `rotor_mount_type` | declarar la ausencia prohíbe el dato; ausencia de declaración lo deja pendiente |
| H-6 | `hub_flange_to_flange_mm` + datum explícito en los rótulos de las distancias al centro | ver abajo |

**H-6, el datum de las cotas de brida.** El ejemplo OEM público del hub
Novatec D042SB-HG publica: OLD 135 mm, PCD 58 mm, *flange to flange* 58,4 mm,
*lock nut to left flange* (A) 31,5 mm y *right flange to lock nut* (B) 45,1 mm.
La base pide `center_to_flange_left_mm` y `center_to_flange_right_mm`, que se
miden desde el **centro de la rueda**, no desde la contratuerca. Transcribir A
y B sin convertir da una ficha silenciosamente falsa: A + B = 76,6 ≠ 58,4. La
conversión correcta es 135/2 − 31,5 = **36,0** y 135/2 − 45,1 = **22,4**, cuya
suma sí devuelve 58,4. El motor compara pares ordenados, nunca sumas, así que
no hay forma de detectarlo; por eso el candidato (a) nombra el datum en el
rótulo de ambos campos y (b) agrega la cota que **no** depende del datum, que
es la que el OEM publica tal cual. El pendiente queda declarado en §6.

El anclaje de rayo de la maza (H-4) es la contraparte de lo que ya tiene la
familia `spoke`. Sheldon lo fundamenta del lado físico: el codo debe quedar
ajustado contra la brida, y el agujero de la brida tiene que dejar pasar la
rosca. El vocabulario deliberadamente **no** incluye un token de «desconocido»:
el motor lo trataría como celda vacía, de modo que agregarlo no distinguiría
nada y sólo sumaría una opción muerta.

## 4. Correcciones en `rim`

| id | corrección | fuente |
|---|---|---|
| R-1 | rótulo del diámetro de asiento del talón: es el número que decide el calce, y los rótulos en pulgadas no se convierten solos | Sheldon, *Tire Sizing Systems* |
| R-2 | rótulo del ancho interior: es el **primer número ISO** de la llanta, no el exterior ni el del neumático montado | Sheldon |
| R-3 | `rim_spoke_hole_diameter_mm` | Weinmann publica el agujero de niple por modelo: 12G = 5,0 mm, 13G = 4,7 mm, 14G = 4,5 mm |
| R-4 | `rim_brake_wear_indicator` (texto), permitido sólo si hay pista de freno | Weinmann publica línea de seguridad, línea indicadora y puntos, y dice que son para llantas de freno de aro, no de disco |
| R-5 | `tire_width_range_mm`: la fila acepta **documento o envase** como fuente, junto a la URL tipada que se conserva | adjudicación de Root del 2026-09-08 |

**Por qué el diámetro y no el rótulo.** Sheldon es explícito: si el diámetro de
asiento coincide, el neumático entra; si no coincide, no entra. Y el rótulo en
pulgadas no lo determina: 26 nombra al menos 559, 571, 590, 597 y 599; 24
nombra 507, 520, 534, 540 y 547; 20 nombra 406, 451, 419, 428 y 438. En sentido
inverso, 622 se rotula 700C, 29 pulgadas y 28 pulgadas —el propio fabricante
Weinmann lo dice así— y 584 se rotula 650B y «27 five». En la población: **13
de 41** llantas usan alguno de los tres rótulos de 622 y **12 de 41** usan un
rótulo ambiguo de 20, 24 o 26 pulgadas. Ninguno de los dos grupos se puede
convertir sin leer el producto; por eso el rótulo viejo queda legacy y el
pendiente correspondiente está en §6, no como caso verde.

R-5 sigue la adjudicación de Root de conservar la URL tipada y agregar el
documento o envase: la columna `source_url` se mantiene con tipo `url` y deja
de ser obligatoria, y la fila exige en su lugar una columna de evidencia que
acepta la identificación del envase — que es lo que la definición publicada
`spec_evidence_source` ya admite en su propia descripción.

## 5. Lo que verifiqué y dejé como está

No cambié nada de esto: lo comprobé antes de descartarlo.

1. **El vocabulario de ejes ya cubre el eje macizo con tuercas** (3/8", 5/16",
   M10) además de cierre rápido y eje pasante. No hacía falta tocarlo.
2. **El receptor de transmisión ya cubre lo que no es cassette**: rueda libre
   roscada 1.37" × 24 tpi, rueda libre roscada M30 de BMX, piñón fijo roscado
   con contratuerca izquierda y contrapedal. **4 de las 48** mazas son de esos
   tipos y el dominio las representa. Dos casos verdes lo fijan.
3. **La compuerta del descentrado de llanta es correcta**: sólo se declara si
   la llanta se declaró asimétrica. Weinmann confirma que el descentrado es una
   propiedad de modelo.
4. **El tipo de válvula ya está retirado en la llanta y es lo correcto**: la
   llanta tiene un **agujero** con un diámetro; el tipo de válvula pertenece a
   la cámara o a la válvula tubeless.
5. **`brake_track` es el eje de freno del lado de la llanta y basta.** Sheldon
   pone el resto donde corresponde: con freno de aro es el **cuadro y la
   zapata** los que fijan qué radio de llanta sirve, y con freno de buje caben
   varios tamaños. Eso no es un hecho de la llanta.
6. **La geometría de brida de la base coincide con cómo publica el OEM**: PCD
   por lado, distancias de brida y diámetro del agujero de rayo. El único
   problema es el datum (H-6), no el conjunto de campos.
7. **Centrado, tensión y alineación no entran.** Sheldon las describe como
   pasos y resultados del armado de la rueda; no son nominales de una maza ni
   de una llanta. Queda como pendiente declarado, no como campo.

## 6. Casos pendientes honestos

Ninguno se declara verde ni se resuelve con una regla inventada.

| id | resultado exigido |
|---|---|
| `hub_convertible_end_caps_need_a_configuration_table` | `unknown_without_configuration_table` |
| `hub_locknut_referenced_flange_figures_are_not_converted` | `unknown_without_arithmetic_coherence` |
| `rim_etrto_text_contradicting_the_bead_seat_diameter` | `unknown_without_parsed_declaration` |
| `legacy_inch_size_cannot_be_converted_to_a_diameter` | `identity_pending` |
| `hub_bmx_solid_axle_diameters_are_outside_the_published_domain` | `identity_pending` |
| `hub_and_rim_wheelbuild_requires_model_scoped_evidence` | `unknown_without_model_scoped_evidence` |

Sobre el penúltimo: **2 de las 48** mazas declaran ejes macizos de 13 y 14 mm,
que el vocabulario publicado no alcanza —se detiene en 3/8"—. Clonar una
segunda definición compartida por dos filas no está justificado; queda
declarado como identidad pendiente hasta que alguien lea los dos productos.

## 7. Pruebas

Arnés parametrizado, con este catálogo y estos casos:

```bash
.fvm/flutter_sdk/bin/flutter test test/unit/product_spec_integrated_catalog_test.dart \
  --dart-define=SPEC_CATALOG_INPUT=$PWD/docs/development/product-specs-research-2026-09-05/existing-hub-rim-catalog-2026-09-08.json \
  --dart-define=SPEC_CATALOG_CASES=$PWD/docs/development/product-specs-research-2026-09-05/existing-hub-rim-cases-2026-09-08.json
```

Resultado: **32 verdes** (2 de metadatos + 30 casos).

**Mutación: 15 mutantes, 15 muertos.** Cada compuerta y cada llave nueva es
observable por al menos un caso: la compuerta del juego, las dos compuertas de
maza suelta, la compuerta y la llave de la tabla de piezas, la evidencia por
fila, la compuerta del rotor, el prerrequisito del anclaje de rayo, la
compuerta del eje pasante, la exigencia de la posición, la compuerta del
indicador de desgaste, el prerrequisito del agujero de niple, la evidencia del
rango de ancho, el orden del rango y la compuerta del descentrado.

Además, dos sondas ejecutadas **contra la base congelada sin modificarla**
reproducen el defecto de §2.

## 8. Límites reales de esta entrega

- **No recibí captura de observaciones de producto para `hub` ni `rim`**, así
  que este documento no reporta adopción: no sé cuántas fichas tienen hoy una
  lectura de `wheel_position` que el retiro a legacy dejaría inerte. Medirlo es
  requisito antes de publicar, igual que se hizo en bloques anteriores.
- La relación maza–llanta–rayo–niple no se implementa aquí. El evaluador de
  relaciones ya existe con su paridad SQL; lo que falta son modelos y
  condiciones documentados, no otro motor.
- El indicador de desgaste se modela como **texto** con la designación literal
  del fabricante, no como una lista de tokens: el vocabulario que pude leer es
  de un fabricante y convertirlo en dominio cerrado sería inventar una regla
  por marca.
- Profundidad de perfil, tipo de unión de la llanta, peso por modelo y tensión
  máxima son datos que algún OEM publica, pero hoy **ningún consumidor del ERP
  decide con ellos**. No los agregué; quedan nombrados aquí para que no se
  abran por su cuenta.

## 9. Fuentes abiertas de primera mano

- Sheldon Brown / John Allen, *Wheelbuilding* —
  `https://www.sheldonbrown.com/wheelbuild.html`
- Sheldon Brown / John Allen, *Tire Sizing Systems* —
  `https://www.sheldonbrown.com/tire-sizing.html`
- Park Tool, *Spoke Wrench Selection* —
  `https://www.parktool.com/en-us/blog/repair-help/spoke-wrench-tool-selection`
- Weinmann, *Technical features of Weinmann rims* —
  `https://www.weinmanntek.com/technology/6/6`
- Ejemplo OEM por modelo, maza Novatec D042SB-HG (ficha pública de
  distribuidor) — `https://www.messingschlager.com/en/products/disc-brake-hubs_t50/novatec-d042sb-rear-disc-brake-hub_a326221-S`
