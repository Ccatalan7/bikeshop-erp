---
titulo: Cadenas y uniones
resumen: anchos por velocidad, qué cadena sirve en qué transmisión, uniones rápidas y desgaste
fuentes: [sheldon-brown, park-tool, bike-matrix]
k: [K01, K02, K03, K04, K05, K06]
claves_bici: [drivetrainSpeeds, drivetrainConfig]
claves_producto: [chain_speeds, chain_width_family, chain_outer_width_mm, chain_pitch_mm, chain_profile_family, chain_directional, quick_link_included, chain_quick_links_supplied, chain_application_declarations, chain_connector_type, chain_connector_target, chain_link_reusable, link_count, chain_ebike_rated]
revisado: 2026-10-02
---

# Cadenas y uniones

## Lo esencial

- Todas las cadenas modernas tienen **paso de ½"** (12,7 mm entre pasadores).
  Lo que cambia es el ancho [PT].
- **1/8"** (≈3,3 mm por dentro): una velocidad, BMX, piñón fijo, cambios
  internos. **3/32"**: cadenas de cambio, cada vez más angostas por fuera
  mientras más piñones atrás [PT][SB].
- La cadena se elige por la **cantidad de piñones atrás** y por la familia del
  fabricante, no por «velocidades de la bici» ([K01]).

## Ancho exterior por velocidades

| Piñones atrás | Ancho exterior aprox. |
|---|---|
| 6, 7, 8 | 7 mm (7,1–7,3) |
| 9 | 6,5–7 mm |
| 10 | 6 mm |
| 11 | 5,5 mm |
| 12 | 5,3 mm |

[PT] — números nominales; una ficha guarda qué se midió y cómo ([K03], [K37]).

## Qué se puede mezclar

- Una cadena **más angosta** suele funcionar en una transmisión con **menos**
  piñones (una de 9 en un 7-8; una de 10 en un 9). Una más ancha en una de más
  piñones roza y salta [SB].
- Que una cadena declare «compatible con Shimano, SRAM y Campagnolo» depende del
  modelo y del mercado: la KMC X8 en Europa y en EE. UU. declaran cosas distintas
  ([K02]).
- **12 velocidades no es una familia.** SRAM Flattop (AXS de ruta) es propietaria
  y no se cruza con otras de 12 [PT]; Shimano 12 con cadena SRAM 12 no es lo que
  aprueban los fabricantes [BM]; SRAM Eagle, Flattop y T-Type se distinguen
  ([K05]).
- LINKGLIDE: cadena LINKGLIDE con cassette y cambio LINKGLIDE ([K04]).

## Uniones

- La unión rápida es **otra pieza con su compatibilidad**: va por velocidad y a
  veces por marca y modelo ([K06]).
- Las cadenas Shimano de 9 o más se cierran con su **pasador especial** de un uso
  o con unión rápida [SB].
- Algunas uniones de 10 son de **un solo uso** (SRAM PowerLock); las de 7-8
  reutilizables (PowerLink) sirven en cadenas SRAM y Shimano [SB].
- Cadenas **direccionales** (Shimano de 10 en adelante): se montan con la cara
  marcada hacia afuera [Fab][Taller].

## Largo y desgaste

- Con piñón grande de 42 dientes o más (1×), el método de largo agrega eslabones
  [PT].
- Desgaste: cambiar con el medidor en 0,5 % (11-12 velocidades) o 0,75 % (hasta
  10); una cadena gastada se come el cassette y los platos [PT][Taller].

## Trampas frecuentes

- Cerrar una Shimano de 11 con un pasador de 10 o una unión de otra velocidad.
- Vender «cadena de 8» para una bici 3×8 pensando que es de 24 velocidades.
- Tratar 11/128" como universal de 9 a 11 ([K03]).

## En Vinabike

- **Bici:** `drivetrainConfig` (`3x7`, `1x10`, `singlespeed`) y `drivetrainSpeeds`.
  **Ojo:** `drivetrainSpeeds` guarda las marchas **totales** (21 en una 3×7, en
  producción 2026-10-02); los piñones de atrás, que deciden la cadena, salen de
  `drivetrainConfig`. El motor lo hace así (`_chainSpeedFromContext`: primero el
  segundo número de la configuración y sólo si no hay, `drivetrainSpeeds` cuando
  es una cantidad plausible de piñones).
- **Producto:** `chain_speeds` (opciones), `chain_width_family` (1/8, 3/32,
  11/128…), `chain_outer_width_mm`, `chain_profile_family` (Flattop, LINKGLIDE…),
  `chain_directional`, `quick_link_included` y `chain_quick_links_supplied`
  (qué unión trae: «KMC MissingLink»), `chain_application_declarations` (para qué
  sistemas la admite el fabricante), `chain_connector_*` en las uniones,
  `link_count`.
- **Motor:** `_assessChainFamilyCompatibility` y
  `_assessChainLinkFamilyCompatibility` (uniones).
- **Pendiente para la tienda:** mostrar la unión incluida desde
  `chain_quick_links_supplied` (8 cadenas publicadas la tienen).

## Fuentes

- Park Tool, «Chain Compatibility» y «Chain Length Sizing».
- Sheldon Brown, «Chains» y «6-speed … 11-speed?».
- Bike Matrix, «Anything is compatible if you use a hammer… not!».
