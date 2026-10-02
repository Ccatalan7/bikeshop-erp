---
titulo: Cámaras y válvulas
resumen: qué cámara va en qué neumático, tipos de válvula, agujero de la llanta y largo de válvula
fuentes: [sheldon-brown, park-tool]
k: [K14, K15]
claves_bici: [valveType, frontTireBsdMm, rearTireBsdMm]
claves_producto: [tube_fit_rows, tube_width_min_mm, tube_width_max_mm, valve_type, valve_standard, valve_length_mm, rim_valve_bore_mm, valve_base_shape, valve_core_removable, tube_has_sealant]
revisado: 2026-10-02
---

# Cámaras y válvulas

## Lo esencial

- Una cámara sirve para **un diámetro (BSD) y un rango de anchos**. Elige por el
  BSD del neumático y que su ancho caiga dentro del rango de la cámara [PT].
- Por excepción, una cámara de 630 (27") sirve en un neumático 622 (700C):
  la diferencia es chica y la goma estira [PT]. No se generaliza a otros saltos.
- La válvula debe calzar con el **agujero de la llanta** y ser **más larga que
  el alto de la llanta** para poder inflar [PT].

## Tipos de válvula

| Válvula | Diámetro del vástago | Agujero de llanta | Notas |
|---|---|---|---|
| Presta (francesa, «fina») | ~6 mm | ~6,5 mm | ruta, MTB media y alta; tuerca de cierre |
| Schrader (americana, «de auto») | ~8 mm | ~8,5 mm | bicis de paseo, infantiles, BMX |
| Dunlop / Woods | cuerpo ancho, se infla como Presta | agujero de Schrader | bicis holandesas y asiáticas |

[PT][SB] — Una llanta de aluminio con agujero Presta se puede agrandar a 8,5 mm
(broca 11/32") para Schrader; al revés se usa un buje reductor [PT]. En llantas
de carbono no se taladra [Taller].

## Largo de válvula

- Llanta baja: 32–40 mm bastan. Perfil medio (30–45 mm de alto): 60 mm. Perfiles
  altos: 80 mm o extensor [PT][Taller].
- Válvula tubeless: además del largo, la **forma de la base** (redonda, cónica)
  debe calzar con el canal de la llanta para sellar [PT][Taller].

## Trampas frecuentes

- Vender la cámara por «27.5 × 2.1» sin confirmar que el rango de la cámara
  cubre el ancho real del neumático.
- Una Presta en un agujero de Schrader sin buje: la válvula se mueve, se corta
  la base y la cámara se pierde [Taller].
- Cámaras con sellante en tubeless: no son lo mismo (una cámara con líquido
  sigue siendo cámara).

## En Vinabike

- **Bici:** `valveType` (familia de válvula) y los BSD de neumático por rueda.
- **Producto:** `tube_fit_rows` (filas de BSD y anchos mínimo/máximo; la tienda
  las muestra como «26" · 1.95" a 2.125"»), `tube_width_min_mm`/`max_mm`,
  `valve_type`/`valve_standard`, `valve_length_mm`, `rim_valve_bore_mm`,
  `valve_base_shape`, `valve_core_removable`, `tube_has_sealant`.
- **Motor:** `_assessTubeFamilyCompatibility`, `_assessTubelessValveFamilyCompatibility`
  y `_assessTubelessConsumableFamilyCompatibility`.
- La tienda publica como dato deducido (`inferred`) que una cámara es de butilo
  y sin líquido cuando el nombre no dice otra cosa (229 datos, 2026-10-01).

## Fuentes

- Park Tool, «Tire, Wheel and Inner Tube Fit Standards».
- Sheldon Brown, glosario y «Tire Sizing Systems».
