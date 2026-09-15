# Contacto y familias restantes — adjudicación e integración local

**Continuación:** esta etapa histórica quedó verificada dentro de la integración
posterior de [valores por fila](row-values-integration-2026-09-07.md). CPC-G01
ya tiene motor 2400 aplicado y regresiones de contradicción; la etapa local
actual agrega [contenido de conjuntos](package-contents-integration-2026-09-07.md).
Los estados de trial pendiente de abajo describen el checkpoint original.

La base integrada contiene **105 plantillas, 706 definiciones (578 nuevas),
57 estructuras de filas, 1.212 usos y 240 casos de representación**. Las
**349 comprobaciones Dart** pasan. El trial SQL está preparado; espera la
base local ocupada por la prueba del forward 2400. No se ha publicado el
catálogo ampliado ni escrito, reasignado o rellenado un producto.

## Pedales, puños, sillines y tijas

Se aceptan los 14 parches del
[dictamen CPC](cockpit-pedal-contact-addendum-review-2026-09-07.md), tras
contrastar de nuevo las fuentes Ergon, Sheldon, SDG y RockShox. Cuatro
definiciones nuevas y 40 casos conservan los mínimos por lado en puños,
identifican anclajes propietarios y separan mandos compatibles de incluidos.
El único caso previo corregido es GP1 Rohloff/Nexus, con preimagen completa.

`compile_product_spec_contact_addendum.py` vuelve a validar todas las
preimágenes contra WSS, aunque el revisor trabajó sobre c122. La base fuente
y el paquete quedan congelados. El checkpoint intermedio es
`all-family-contact-integrated-2026-09-07.json`, SHA
`d7f8510ca112da4430f485720243ddde899daa097f39fb00aec49fe35027b7ca`.
Los motivos individuales están en `contact-root-decisions-2026-09-07.json`.

El [manual GP1 06/2014](https://www.ergonbike.com/infocenter/downloads/manual_gp1.pdf)
describe espacio recto distinto para largo/corto; el espacio disponible se
observa en el manubrio instalado. Las
[cotas Reverb AXS](https://www.sram.com/globalassets/document-hierarchy/frame-fit-specifications/rockshox/gen0000000006250-rev-a-reverb-axs-seatpost-specifications.pdf)
no reemplazan las observaciones de cuadro y ciclista. El
[anclaje SDG I-Beam](https://sdgcomponents.com/products/micro-alloy-i-beam)
necesita sistema y contraparte específicos. Nada de ello se infiere de marca,
nombre genérico o medidas que coincidan.

CPC-G01 (incluido/false) está en implementación de motor 2400; CPC-G02 (dos
anchos para el mismo datum), G03 (ajuste externo y aritmético de tija) y G04
(identidad y consumidor) continúan abiertos. La integración de campos no los
declara resueltos.

## Adjudicación del paquete ND de Claude

El paquete original `remaining-non-drivetrain-addendum-review-2026-09-07.json`
permanece en `fd78724798b4c83773e599d33e6705d51fb5298526743470f5a223f5f586d0e1`.
Root genera 23 parches explícitos: **rechaza los siete unique_by** y acepta
o corrige los restantes, incluidas ampliaciones propias. Hay tres definiciones
nuevas y 33 casos adicionales. El contraejemplo no es una licencia para aceptar
afirmaciones contradictorias: mientras falte identificar su alcance, los
conflictos documentales permanecen pendientes y no autorizan compatibilidad.

Una columna requerida no demuestra identidad física. Las siete claves
propuestas borraban al menos uno de estos ejes:

| Filas | Alcance que perdería la restricción |
|---|---|
| Capacidades de herramienta | Miembro, interfaz concreta, medida, adaptador y modelo objetivo |
| Nivel de seguridad | Programa de clasificación, componente concreto, edición |
| Montura de accesorio | Pieza de adaptación, configuración y revisión de esta montura |
| Miembro de bolso | Estado cerrado/expandido y referencia de medida |
| Cartucho CO2 | Modelo/rosca/condiciones de la contraparte |
| Lente | Pieza, revisión, tinte y condiciones de medición |
| Información nutricional | Nutriente concreto cuando dice Otro; cantidad y preparación de la porción |

Contraejemplos primarios verificados:

- [ABUS GRANIT XPlus 540](https://www.abus.com/usa/Products/Bicycle-locks/U-Locks-Bike/GRANIT-XPlus-540)
  publica Sold Secure Pedal Cycle Diamond y Powered Cycle Gold. Se añadió el
  programa como dato explícito y se pide cuando el emisor es Sold Secure.
- [Topeak TT9635B](https://www.topeak.com/us/en/product/122-mtx-trunkbag-dxp)
  describe un compartimento superior expandible. Dos alturas del mismo
  miembro en estados diferentes no son un duplicado mecánico.
- [Fidlock, plantilla bottle 800 + bike base](https://www.fidlock.com/consumer/media/g0/b2/35/1677141440/fidlock_twist_1to1scale_bottledimensions_bottle800bikebase_220210.pdf)
  publica dimensiones del conjunto. El diámetro compartido con portabidón
  queda rotulado y condicionado como **acople con aro**, mientras las
  dimensiones físicas tienen configuración y referencia propias.
- [Topeak AirBooster G2](https://www.topeak.com/us/en/product/1202-AIRBOOSTER%20G2)
  publica el fondo de escala del manómetro. El campo de presión sin alcance
  queda legacy sólo en pump. La estructura nueva diferencia bombeo, presión
  de trabajo, escala y estimación CO2; esta última pide neumático, gas,
  cantidad de neumáticos y condiciones. La
  [tabla CO2 de Topeak](https://www.topeak.com/storage/app/media/product/bags/top-tube-bags/gravel-gear-bag/tubi-11_power-lever-x_airbooster_2021-03.pdf)
  no se convierte en una presión garantizada de cualquier neumático.
- [Park Tool, roscas](https://www.parktool.com/en-us/blog/repair-help/basic-thread-concepts)
  documenta diámetros métricos con TPI. El nuevo selector expresa el paso y
  no decide la unidad del diámetro. La selección de paso/mm o TPI pide su
  valor; sin selección hay pendiente, nunca aprobación mecánica por ausencia
  de un error bloqueante.

Se retiró la opción de **otra variante del soporte** de su tabla de montajes:
la ficha representa esta variante física. En cascos se separan uso, construcción
y público; Integral y Niño no compiten con Enduro. No se infiere una norma ni
método de fabricación desde esas palabras.

## Pruebas, trazabilidad y límites

`normalize_remaining_nd_review.py` conserva cada rechazo/corrección y su
preimagen. `compile_product_spec_remaining_nd_addendum.py` verifica fuentes,
la adjudicación, casos y tres cambios sobre fixtures anteriores mediante el
hash de su preimagen completa. El integrador conserva los IDs/tipos/unidades
existentes y todos los gates en falso.

| Artefacto | SHA-256 |
|---|---|
| Catálogo all-family-remaining-nd-integrated-2026-09-07.json | `f1826a9a782a200754b21ba6c5420af0f9c39b89482503cab77f96779fc739b1` |
| Casos all-family-remaining-nd-cases-integrated-2026-09-07.json | `14b6905563349eda7581cf651819f3b07e9c8de72de313c7250c1424de46f4ac` |
| Propuesta remaining-nd-normalized-patches-2026-09-07.json | `96f65c22acd5167216978e0b856944f89c2229f29acf48a2f0fb41fb3bcb5d97` |

El paquete original de Claude había comprobado preimágenes, **no ejecutado
sus fixtures en el motor**. Contenía tokens fuera de dominio y números de fila
con transporte incorrecto: Cartucho incluido, Etiqueta y Carbohidratos no eran
los tokens reales de sus respectivas columnas. Se corrigieron explícitamente
y los ejemplos sintéticos no se presentaron como observaciones de inventario.
En la integración root también se corrigieron U-lock y códigos de diagnóstico
en las expectativas, después de inspeccionar la respuesta del motor. No se
relajó ninguna regla para aprobar esos casos.

Log Dart: `.tmp/product-spec-catalog/all-family-remaining-nd-dart.log`.
Trial pendiente: `.tmp/product-spec-catalog/all-family-remaining-nd-trial.sql`.
La revisión independiente de estas correcciones está solicitada en el mismo
chat Claude Code/Opus 5/Ultracode. No hay aprobación de familias completas.
