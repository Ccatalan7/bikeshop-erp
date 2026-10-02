---
titulo: Frenos de disco, rotores y adaptadores
resumen: montajes IS, post mount y flat mount, tamaño de rotor y adaptadores, 6 pernos o Centerlock, grosor y pastillas
fuentes: [park-tool]
k: [K09, K24, K25, K47]
claves_bici: [brakeType, frontRotorSizeMm, rearRotorSizeMm]
claves_producto: [caliper_mount, caliper_mount_interface, brake_mount_front, brake_mount_rear, rotor_diameter_mm, rotor_mount_type, rotor_thickness_mm, rotor_nominal_thickness_mm, rotor_adapter_fitments, rotor_from_mm, rotor_to_mm, brake_adapter_fitments, hub_brake_attachment_interfaces, max_rotor_mm, max_rotor_rear_mm, brake_pad_retainer_model]
revisado: 2026-10-02
---

# Frenos de disco, rotores y adaptadores

## Lo esencial

Un freno de disco calza cuando cada una de estas parejas coincide ([K24]):

1. **Cáliper ↔ montaje del cuadro/horquilla** (IS, post mount, flat mount), con
   el adaptador que corresponda.
2. **Rotor ↔ maza**: 6 pernos o Centerlock.
3. **Rotor ↔ cáliper**: diámetro (lo fija el montaje + adaptador) y grosor.
4. **Pastilla ↔ cáliper**: forma y retén de ese cáliper ([K25]).
5. **Manilla ↔ cáliper**: hidráulico del mismo sistema
   ([frenos-hidraulicos.md](frenos-hidraulicos.md)) o mecánico con el tiro
   correcto ([frenos-de-llanta.md](frenos-de-llanta.md)).

## Montajes del cáliper

| Montaje | Cómo se reconoce | Notas |
|---|---|---|
| **IS** (International Standard) | dos agujeros sin rosca con pernos transversales | antiguo; los cálipers actuales (post mount) necesitan adaptador IS→PM |
| **Post mount** (PM) | dos postes roscados; pernos en el sentido del cáliper | MTB actual; cada horquilla o cuadro declara su rotor nativo (PM160, PM180…) |
| **Flat mount** (FM) | cáliper plano, pernos desde abajo | ruta y gravel; rotor nativo 140 o 160 |

[PT][Taller]

## Tamaño de rotor y adaptadores

- Tamaños comunes: **140, 160, 180, 203** mm (y 220 en descenso y e-bike) [PT].
- Un **adaptador** sube el rotor desde el tamaño nativo del montaje: PM160 + 20
  = 180; +43 = 203. Es **direccional**: dice de qué montaje a qué cáliper y de
  qué rotor a qué rotor ([K09], [K47]).
- El fabricante del cuadro u horquilla fija el **rotor máximo**; un adaptador no
  autoriza pasarlo [Fab][Taller].

## Rotor y maza

| Unión | Detalle |
|---|---|
| 6 pernos | círculo de 44 mm, pernos T25 a 4–6 Nm [PT] |
| Centerlock | estriado con anillo; el anillo de estrías internas (herramienta de cassette) va con eje QR; el de muescas externas (herramienta de pedalier) con eje pasante [PT] |

Un rotor de 6 pernos se monta en una maza Centerlock **con adaptador**; un rotor
Centerlock **no** se monta en una maza de 6 pernos [PT].

## Grosor y compuesto

- Cada sistema declara el **grosor** del rotor nuevo y el mínimo de desgaste
  (por ejemplo 1,8 mm nuevo en Shimano, 2,0 mm en algunos SRAM); un rotor más
  grueso puede no entrar en el cáliper [Fab][Taller].
- Hay rotores **sólo para pastilla orgánica (resina)**: una metálica los gasta
  rápido [Fab].

## Trampas frecuentes

- Vender un adaptador «+20» sin saber si el montaje es PM160 o PM180.
- Un cáliper post mount en un cuadro IS sin el adaptador IS→PM.
- Rotor de otro grosor: roza o la pastilla no alcanza.

## En Vinabike

- **Bici:** `brakeType` (disco mecánico o hidráulico) y `frontRotorSizeMm`,
  `rearRotorSizeMm` con valores estándar (el kernel V1 prohíbe texto libre y
  esconde el rotor si el freno no es de disco).
- **Producto:** en cálipers `caliper_mount`/`caliper_mount_interface`; en cuadros
  y horquillas `brake_mount_front`/`brake_mount_rear`, `max_rotor_mm`,
  `max_rotor_rear_mm`; en rotores `rotor_diameter_mm`, `rotor_mount_type`,
  `rotor_thickness_mm`, `rotor_nominal_thickness_mm`; en adaptadores
  `rotor_adapter_fitments`, `rotor_from_mm`, `rotor_to_mm`,
  `brake_adapter_fitments`; en mazas `hub_brake_attachment_interfaces`; en
  pastillas `brake_pad_retainer_model`.
- **Motor:** `_assessRotorFamilyCompatibility`, `_assessDiscBrakeFamilyCompatibility`,
  `_assessHydraulicDiscFamilyCompatibility`,
  `_assessMechanicalDiscFamilyCompatibility` y
  `_assessBrakePadFamilyCompatibility`.
- **Residuo conocido (2026-10-02):** 4 adaptadores de freno publicados no
  muestran datos en la tienda: su información está en tablas que aún no tienen
  vista de tienda.

## Fuentes

- Park Tool, «Disc Brake Rotor Removal & Installation», «Mechanical Disc Brake
  Alignment» y la ficha DT-5.2 (IS, post mount y flat mount).
