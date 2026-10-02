---
titulo: Suspensión (horquillas y amortiguadores)
resumen: horquilla por tubo, eje, rueda, recorrido y freno; amortiguador por largo entre ojos, carrera y montaje; repuestos por modelo y año
fuentes: [park-tool]
k: [K28, K29]
claves_bici: [suspensionLayout, bikeType]
claves_producto: [fork_kind, fork_travel_mm, travel_mm, axle_to_crown_mm, fork_offset_mm, fork_crown_layout, fork_tire_clearance_configurations, steerer_type, steerer_fit, axle_type, eye_to_eye_mm, stroke_mm, rear_shock_size, shock_mount_kind, shock_end_configurations, shock_size_declarations]
revisado: 2026-10-02
---

# Suspensión (horquillas y amortiguadores)

## Lo esencial

- **Horquilla** ↔ bici: tubo de dirección ([direccion.md](direccion.md)), eje y
  ancho ([mazas-ejes-y-espaciado.md](mazas-ejes-y-espaciado.md)), diámetro de
  rueda y neumático más ancho ([ruedas-y-neumaticos.md](ruedas-y-neumaticos.md)),
  montaje de freno y rotor máximo ([frenos-de-disco.md](frenos-de-disco.md)) y
  recorrido/alto (*axle-to-crown*) que acepta la geometría del cuadro [Taller].
- **Amortiguador** ↔ cuadro: **largo entre ojos × carrera** (210 × 50, 230 × 60;
  o en pulgadas 7,875 × 2,0), tipo de montaje (ojo estándar o *trunnion*) y
  bujes/pernos de cada ojo con su ancho [Taller][Fab].
- **Recorrido de rueda ≠ carrera del amortiguador**: la relación de palanca del
  cuadro los conecta ([K29]).
- **Repuestos de servicio** (sellos, retenes, cartuchos) van por **modelo, año y
  revisión**, no por «horquilla de 32 mm» ([K28]).

## Trampas frecuentes

- Poner más recorrido del que el cuadro aprueba: cambia la geometría y la
  garantía [Fab].
- Comprar un amortiguador «210 × 50» sin mirar si el cuadro es trunnion.
- Kit de sellos por diámetro de barra solamente.

## En Vinabike

- **Bici:** `suspensionLayout` (rígida, hardtail, doble) decide si existen los
  campos de horquilla y amortiguador; `bikeType` (una BMX o fixie no muestra
  suspensión).
- **Producto:** horquillas `fork_kind`, `fork_travel_mm`/`travel_mm`,
  `axle_to_crown_mm`, `fork_offset_mm`, `fork_crown_layout`,
  `fork_tire_clearance_configurations` (la tienda muestra «29" / 700c ·
  neumático hasta 2.3" (58 mm)»), `steerer_type`, `steerer_fit`, `axle_type`;
  amortiguadores `eye_to_eye_mm`, `stroke_mm`, `rear_shock_size`,
  `shock_mount_kind`, `shock_end_configurations`, `shock_size_declarations`.
- **Motor:** no hay familia de horquilla ni amortiguador entre las 26 que juzga
  hoy; es un hueco.

## Fuentes

- Criterio de taller; Park Tool para el eje de horquilla (TS-TA) y los
  procedimientos de servicio.
