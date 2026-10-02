---
titulo: Cables y fundas
resumen: cable de cambio y de freno, cabezas, funda de cambio (sin compresión) y de freno (espiral), diámetros
fuentes: [sheldon-brown, park-tool]
k: [K27, K45]
claves_bici: []
claves_producto: [cable_diameter_mm, cable_head, cable_purpose, housing_kind, housing_construction, housing_application, housing_outer_diameter_mm, fits_cable_diameter_mm, fits_housing_diameter_mm, lever_cable_head_profiles]
revisado: 2026-10-02
---

# Cables y fundas

## Lo esencial

- El **cable de freno es más grueso** que el de cambio porque soporta más tensión
  [SB]. Habitual: ~1,5–1,6 mm freno, ~1,1–1,2 mm cambio [Taller].
- **La funda de cambio nunca va en un freno.** La funda de cambio tiene hilos
  longitudinales para no estirarse (indexado preciso), pero no aguanta la carga de
  frenar y puede reventar; la de freno es una espiral, fuerte pero se acorta un
  poco al doblarse [SB][PT][K27].
- La funda de cambio común es de **4 mm**; la de 5 mm fue común y aún se usa. La
  de freno es de **5 mm** [PT][Taller].

## Cabezas del cable

| Cabeza | Dónde |
|---|---|
| Cilindro (barril) | freno de manillas de manubrio plano |
| Hongo / pera | freno de manillas de ruta |
| Cilindro chico alineado con el cable | cambio |

[SB] — Una manilla declara qué cabeza recibe; un cable con las dos cabezas
(se corta la que no sirve) cubre ambas [Taller].

## Terminales y alcance

Cable, cabeza, funda, terminal (*ferrule*) y forro (*liner*) conservan cada uno su
ámbito: un terminal es para un diámetro de funda; un forro para un diámetro de
cable ([K45]).

## Trampas frecuentes

- Usar funda de cambio en el freno trasero «porque sobraba».
- Terminal de 4 mm en funda de 5 mm.

## En Vinabike

- **Producto:** `cable_diameter_mm`, `cable_head`, `cable_purpose` (cambio o
  freno), `housing_kind`, `housing_construction`, `housing_application`,
  `housing_outer_diameter_mm`, y en terminales `fits_cable_diameter_mm`,
  `fits_housing_diameter_mm`; en manillas `lever_cable_head_profiles`.
- **Bici:** sin campo; se deduce del freno y la transmisión.

## Fuentes

- Sheldon Brown, «Cables».
- Park Tool, «How to Size and Install Shift Cable Housing» y «Brake Housing &
  Cable Installation».
