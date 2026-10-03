---
titulo: Dirección y tubo de dirección (SHIS)
resumen: diámetros de tubo de horquilla, cónico, códigos SHIS arriba y abajo, roscada o sin rosca
fuentes: [sheldon-brown, park-tool]
k: [K19, K38]
claves_bici: [steererFit, headsetUpperShis, headsetLowerShis]
claves_producto: [headset_upper_shis, headset_lower_shis, headset_standard, headset_upper_bearing_configuration, headset_lower_bearing_configuration, steerer_type, steerer_fit, steerer_threaded, stem_steerer_clamp_diameter_mm]
revisado: 2026-10-02
---

# Dirección y tubo de dirección (SHIS)

## Lo esencial

- Una dirección calza cuando coinciden **tres medidas**: el alojamiento del
  cuadro (arriba y abajo por separado), el diámetro del tubo de la horquilla y el
  asiento de la pista de corona [SB][PT][K19].
- El código **SHIS** las escribe: tipo + diámetro del alojamiento / diámetro del
  tubo. Ejemplo: `ZS44/28.6 | ZS56/40`. Dos direcciones con el mismo SHIS arriba y
  abajo son intercambiables [PT].
- Tipos: **EC** (taza externa, por fuera del tubo), **ZS** (taza prensada que
  queda a ras, «semi integrada»), **IS** (rodamiento apoyado directo en el cuadro,
  «integrada») [PT].

## Tubos de horquilla

| Tubo | Diámetro | Asiento de pista de corona |
|---|---|---|
| 1" ISO | 25,4 mm | 26,4 mm |
| 1" JIS | 25,4 mm | 27,0 mm |
| 1⅛" | 28,6 mm | 30,0 mm |
| 1¼" | 31,8 mm | 33,0 mm |
| 1,5" | 38,1 mm | 39,8 mm |
| Cónico | 1⅛" arriba, 1,5" abajo (también 1¼" abajo) | el de abajo |

[SB][PT] — En SHIS el tubo se escribe por la medida que toca el rodamiento:
28.6, 30 o 40 abajo para la corona [PT][Taller].

## Códigos SHIS que más se ven

| Código | Qué es |
|---|---|
| EC34/28.6 | 1⅛" de tazas externas clásica |
| ZS44/28.6 | 1⅛" semi integrada (arriba en cuadros cónicos) |
| ZS56/40 | abajo de un cuadro cónico semi integrado |
| IS41/28.6 | integrada 1⅛" con rodamiento de 45° |
| IS42/28.6 | integrada 1⅛" (estilo Campagnolo Hiddenset) |
| IS52/40 | abajo de un cuadro cónico integrado |
| EC49/40 | abajo cónico de tazas externas (1,5") |

[PT][Taller] — En IS, además del diámetro, cuenta el **ángulo del rodamiento**
(36° o 45°); un rodamiento puede ser MAX y de contacto angular a la vez ([K38]).

## Roscada o sin rosca

- Dirección **roscada**: el tubo tiene rosca (1" a 24 TPI en ISO y JIS) y la
  potencia es de **cuello (quill)** de 22,2 mm (1") [SB][Taller].
- **Sin rosca (threadless)**: la potencia aprieta el tubo por fuera; la potencia
  debe tener la misma abrazadera que el tubo (28,6 mm para 1⅛") [PT].

## Trampas frecuentes

- Pedir «dirección 1⅛» sin saber si el cuadro es EC, ZS o IS.
- Un cuadro cónico con una horquilla recta 1⅛ necesita la taza de abajo
  reductora correcta (por ejemplo ZS56/28.6), no la cónica.
- JIS e ISO de 1": la pista de corona es distinta (27,0 vs 26,4).

## En Vinabike

- **Producto:** `headset_upper_shis`, `headset_lower_shis`, `headset_standard`,
  `headset_upper/lower_bearing_configuration`; en horquillas `steerer_type`,
  `steerer_fit` (la tienda muestra «1 1/8" (28.6 mm)»), `steerer_threaded`; en
  potencias `stem_steerer_clamp_diameter_mm`.
- **Bici (20261002170000):** `steererFit` (códigos `straight_1`,
  `straight_1_1_8`, `straight_1_1_4`, `straight_1_5`, `tapered_1_1_8_1_5`) y
  `headsetUpperShis` / `headsetLowerShis` (el código SHIS tal cual). Una
  horquilla instalada cambia `steererFit` al terminar el trabajo (fila
  `steerer_fit` sin rueda de `bike_fact_spec_links`, con mapa de códigos). Los
  SHIS se eligen en la hoja: ninguna dirección del inventario dice el suyo
  (2026-10-02).
- **Motor:** `_assessHeadsetFamilyCompatibility` y
  `_assessBearingFamilyCompatibility`; la horquilla y la potencia contra el
  tubo de la ficha, en `assessCockpitCompatibility`
  (`lib/modules/bikeshop/services/cockpit_compatibility.dart`): una horquilla
  cónica no entra en una dirección recta de 1⅛″; una recta en un cuadro cónico
  va con la taza de abajo reductora; la potencia aprieta el tubo por arriba (un
  cónico es 1⅛″ ahí) y con laina baja una medida, nunca sube.

## Fuentes

- Park Tool, «Headset Standards» y «Standardized Headset Identification System».
- Sheldon Brown, crib sheet «Headsets».
