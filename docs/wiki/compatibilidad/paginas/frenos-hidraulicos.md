---
titulo: Frenos hidráulicos, líquidos y conexiones
resumen: DOT o mineral, cada freno es su sistema, mangueras, olivas e insertos, kits de purga
fuentes: [park-tool]
k: [K26, K35, K46]
claves_bici: [frontBrakeFluidType, rearBrakeFluidType]
claves_producto: [fluid_type, brake_fluid_declarations, brake_fluid_standard_claims, brake_model_fluid_approvals, hose_fitting_type, hose_inner_diameter_mm, hose_outer_diameter_mm, hose_system_code, brake_fitting_oem_code, brake_fitting_insert_length_mm, brake_hydraulic_connections, brake_bleed_ports]
revisado: 2026-10-02
---

# Frenos hidráulicos, líquidos y conexiones

## Lo esencial

- Hay dos familias de líquido y **nunca se mezclan**, ni en el freno ni en las
  herramientas de purga: el cruce daña los sellos y el freno puede fallar [PT].
- **DOT** (base glicol): SRAM (salvo DB8), Formula, Hayes, Hope [PT].
- **Aceite mineral**: Shimano, Magura, TRP, Tektro, Trick Stuff, SRAM DB8,
  Campagnolo, Promax, Clarks [PT].
- **Cada freno es su propio sistema.** Adelante y atrás pueden tener líquidos
  distintos si son de marcas distintas; la ficha guarda el líquido por freno
  (corrección del dueño, 2026-09-27) ([K26]).
- El líquido **no** define el accionamiento ni la superficie de frenado ([K35]).

## Mangueras y conexiones

- La manguera es del **sistema de ese fabricante**: diámetro exterior e interior,
  y la conexión en cada extremo (oliva + inserto, banjo, conexión rápida) ([K46]).
- Al cortar una manguera se usan **oliva e inserto nuevos** del modelo correcto;
  el código del inserto depende del diámetro interior de la manguera [Fab][Taller].
- La identidad física (diámetros, rosca, largo del inserto) va antes que la lista
  de modelos donde sirve ([K46]).

## Purga

- Kit de purga **por líquido**: Park BKD (DOT) y BKM (mineral) [PT].
- Cada fabricante tiene su procedimiento y sus puertos; la ficha guarda qué
  puertos tiene el cáliper y la manilla.

## Trampas frecuentes

- Rellenar un Shimano con DOT «porque es líquido de freno».
- Usar la misma jeringa para DOT y mineral.
- Vender un kit de insertos por «marca» sin el diámetro de la manguera.

## En Vinabike

- **Bici:** `frontBrakeFluidType` y `rearBrakeFluidType` con los códigos del
  registro `fluid_type` (migración 20260928040000).
- **Producto:** `fluid_type`, `brake_fluid_declarations`,
  `brake_fluid_standard_claims`, `brake_model_fluid_approvals` (líquidos y
  modelos de freno), `hose_fitting_type`, `hose_inner_diameter_mm`,
  `hose_outer_diameter_mm`, `hose_system_code`, `brake_fitting_oem_code`,
  `brake_fitting_insert_length_mm`, `brake_hydraulic_connections`,
  `brake_bleed_ports`.
- **Motor:** `_assessHydraulicDiscFamilyCompatibility` compara el líquido de
  cada freno de la bici con el del producto (bloque F.2).
- **Residuo conocido (2026-10-02):** 10 conectores hidráulicos y 2 líquidos de
  freno publicados no muestran datos en la tienda; su información está en tablas
  sin vista de tienda.

## Fuentes

- Park Tool, fichas BKD-1.2 y BKM-1.2, «Brake Bleeding for SRAM Hydraulic
  Brakes» y «How to Bleed Shimano Flat Bar Hydraulic Brakes».
