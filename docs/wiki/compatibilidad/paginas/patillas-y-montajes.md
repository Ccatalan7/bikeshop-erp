---
titulo: Patillas de cambio y montajes del cambio
resumen: patilla propia de cada cuadro, UDH, direct mount y extensores
fuentes: [park-tool]
k: [K05, K13]
claves_bici: []
claves_producto: [hanger_interface, hanger_frame_interface, hanger_derailleur_interface, hanger_model_code, rear_derailleur_mount_type, rear_derailleur_hanger_interface, hanger_extender_claims, hanger_extender_limit_claims]
revisado: 2026-10-02
---

# Patillas de cambio y montajes del cambio

## Lo esencial

- La patilla (hanger) une el **cuadro** con el **cambio**: son dos interfaces.
  Del lado del cuadro, cada modelo tiene su forma, sus pernos y su posición; del
  lado del cambio casi todas tienen la rosca estándar (10 × 1 mm) [Taller][K13].
- Por eso una patilla se vende **por cuadro** (marca, modelo, año y a veces
  talla), con el código del fabricante o del fabricante de patillas.
- **UDH** (Universal Derailleur Hanger de SRAM) es una patilla común a muchos
  cuadros; además es la única base para SRAM Transmission (T-Type), que se
  apoya en el eje y no usa patilla ([K05]).
- **Direct mount** (Shimano): el cambio se monta sin el eslabón B; el cuadro o
  la patilla deben ser direct mount [Fab][Taller].
- Antes de cambiar un cambio o mover piñones, se **alinea la patilla** con la
  herramienta [PT].

## Extensores

Un extensor de patilla alarga el brazo para piñones grandes; cada fabricante
declara hasta qué piñón sirve. Es una condición del veredicto, no una solución
general [Fab][K09].

## Trampas frecuentes

- Vender una patilla «parecida» por foto: dos patillas casi iguales pueden tener
  distinta altura de rosca y dejar el cambio fuera de línea.
- Instalar un cambio T-Type en un cuadro sin UDH.

## En Vinabike

- **Producto:** `hanger_frame_interface` (lado del cuadro), `hanger_derailleur_interface`
  (lado del cambio), `hanger_model_code`, `hanger_interface`;
  `rear_derailleur_mount_type` y `rear_derailleur_hanger_interface` en el
  cambio; `hanger_extender_claims` y `hanger_extender_limit_claims` en los
  extensores.
- **Bici:** la ficha de la bici todavía no guarda la patilla de su cuadro; hoy
  se resuelve con la identidad de la bici (marca, modelo, año). Es un hueco
  conocido para la matriz unificada.

## Fuentes

- Park Tool, «Rear Derailleur Hanger Alignment».
