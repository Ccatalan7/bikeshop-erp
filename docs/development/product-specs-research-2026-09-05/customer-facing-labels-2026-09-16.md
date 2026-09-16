# Rótulos en el idioma de las tiendas chilenas — 2026-09-16

El dueño vio en vinabike.cl «Posición de las mazas de este envase» y pidió lenguaje natural,
el que usan las tiendas y talleres conocidos en Chile. Los rótulos de las plantillas de
2026-09 se escribieron para el motor (precisos, pero de ingeniero); la tienda, el taller y el
asistente de compras los imprimen tal cual.

## Referencias usadas (cómo rotulan las tiendas)

| Tienda | Rótulos y notación observados |
|---|---|
| Bike Factory (bikefactory.cl, mazas) | filtros «Rayos: 32H / 36H», «Núcleo: HG, Micro Spline, XD», «Medida eje: 9x135, 12x148»; tees «Longitud: 60 mm», «Diámetro de fijación: 31,8 mm» |
| Viaja en Bici (viajaenbici.cl, maza Shimano FH-M3050) | «Ancho de buje: 135mm», «Anclaje disco tipo Centerlock», «32 Hoyos / Sellado por contacto» |
| Faucon Bikes (fauconbikes.cl, cámaras y tees) | «Válvula Auto Schrader», «Válvula Francesa», «Aro 29», «48mm / 60mm», «Diámetro manillar 31.8mm», «Ángulo 6°» |
| Trek Chile (trekbikeschile.com, cámara Bontrager) | «Diámetro: 27.5"», «Ancho: 2.2-2.5"», «Largo: 48 mm», «Válvula: Presta», «ETRTO», «Material: Butyl», «Peso» |
| Imperio Bikers (imperiobikers.cl, cassette y cambio) | «Velocidades: 12», «Rango: 11-50», «Núcleo: Shimano HG», «Caja larga», «Piñón máximo» |
| Rideshop / Derman (llantas) | «32 hoyos», «doble pared», «ancho interno / externo», «línea de freno / freno disco» |
| Oxford Store (candado) | «Candado tipo U-Lock», «Incluye 2 llaves», «Largo del cable» |

## Qué cambió (migración `20260916180000_customer_facing_labels.sql`)

126 rótulos de definiciones globales y 20 rótulos de opciones, aplicados y verificados en
producción (recibo `.tmp/db/migration-receipts/20260916180000.receipt`). Los hechos, los
valores guardados, las banderas y los contratos no cambian; el trigger de revisión subió la
versión de contrato de las plantillas que usan esas definiciones, como corresponde a un cambio
de rótulo. Generador y lista completa: `scripts/inventory/compile_customer_labels.py`.

Ejemplos, antes → después:

| Antes | Después |
|---|---|
| Posición de las mazas de este envase | Posición de la maza |
| Cantidad de agujeros para rayos | Hoyos para rayos |
| Distancia entre contratuercas de la maza (OLD) | Ancho de la maza (OLD) |
| Construcción del receptor de transmisión / Núcleo estriado de cassette | Núcleo (tipo de piñón) / Núcleo de cassette |
| Norma de válvula / Presta (francesa) / Schrader (americana / auto) | Tipo de válvula / Francesa (Presta) / Auto (Schrader / americana) |
| Cantidad de coronas, Cantidad de posiciones indexadas, Velocidades cadena | Velocidades |
| Largo caja cambio / SGS / larga | Largo de pata (caja) / Larga (SGS) |
| Superficie de frenado | Freno (disco o llanta) |
| Compuesto: Orgánico | Compuesto: Orgánico (resina) |
| Mecanismo de cierre / Combinación | Cierre (llave o clave) / Clave (combinación) |
| Estándar de rosca del pedal (diámetro + paso) | Rosca |
| Diámetro de sujeción del manubrio | Diámetro del manubrio (abrazadera) |
| El envase trae el pedalier / cubrecadena | Incluye motor (pedalier) / Incluye cubrecadena |
| Cambio con clutch, Cadena direccional | Con clutch (embrague), Con sentido de montaje (direccional) |

Los dos últimos también arreglan una trampa del vocabulario booleano de las lecturas de nombre:
«cambio» y «cadena» dejaban de ser términos que dan «sí» a todo cambio y a toda cadena.

Los títulos de sección de la ficha pública (`primary`, `measurement`, `contents`,
`declaration`) salían en inglés porque la página imprimía la clave interna; ahora se muestran
como «Características», «Medidas», «Qué incluye» y «Según el fabricante»
(`lib/public_store/pages/product_detail_page.dart`, se despliega con el merge).

## La segunda copia de las opciones (`20260916182000`)

Una opción vive en dos lugares: la fila de `spec_definition_values` (lo que un hecho referencia
por id y lo que la tienda muestra) y el arreglo `spec_definitions.allowed_values` (contra lo
que valida `spec_validate_product_internal_v1`). La migración de rótulos cambió sólo las filas,
y el validador marcó cada hecho con opción renombrada como «no pertenece a las opciones del
campo», un `field_constraint` que la ficha pública trata como bloqueante: esas filas
desaparecieron de la tienda hasta la sincronización (`compile_allowed_values_sync.py`, 20
reemplazos, verificada). Comprobación posterior: ningún hecho guardado queda fuera de las
opciones de su campo. Las 96 diferencias que quedan entre ambas copias son numéricas (`103` vs
`"103"`) y de vocabularios de estado de la bici, con el mismo conteo a ambos lados: no son un
desfase.

## Qué no se tocó y por qué

- Opciones que un contrato de plantilla nombra en sus reglas (`Talón de alambre`, `Talón
  plegable`, `Juego delantera + trasera`, `Delantera`/`Trasera`, `Izquierdo / delantero`,
  `Derecho / trasero`, `Plato individual`, `Juego de platos en el mismo envase`, `Tee sin rosca
  (ahead)`, `Tee de espiga (quill)`, `Adaptador quill → ahead`): renombrarlas exige migrar el
  contrato en el mismo paso. El rótulo del campo ya las contextualiza («Talón (alambre o
  plegable)», «Posición de la maza»).
- Rótulos de campos muy técnicos sin hechos (datums, designaciones de rosca de rayo, cotas OEM
  de tijas): siguen con la redacción del motor hasta que alguna familia los llene.

## Efecto en las lecturas de nombre

Las reglas de `spec_name_reading_rules.py` apuntan a los rótulos nuevos, y los rótulos nuevos
hacen legibles notaciones que antes no calzaban con ninguna palabra de la etiqueta: «Resina»
→ Orgánico (resina), «Plano» → Recto (plano), «Clave» → Clave (combinación), «T/ARRIBA» y
«T/ABAJO» → Tiro arriba / Tiro abajo, «Doble tirón» → Doble tiro. Ver fill-002c en
[fill-002-name-readings-record.md](fill-002-name-readings-record.md).
