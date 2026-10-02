---
titulo: Cómo guarda y juzga Vinabike la compatibilidad
resumen: el mapa entre el oficio y el sistema — ficha de la bici, ficha técnica del producto, motor, reglas en la base y el Master Schema
fuentes: [bike-matrix]
k: [K36, K51]
claves_bici: [bikeType, wheelSize, brakeType, rimBrakeFamily, suspensionLayout, frontHubSpacingMm, rearHubSpacingMm, freehubType, drivetrainSpeeds, drivetrainConfig, frontSpokeHoles, rearSpokeHoles, valveType, bottomBracketFamily, bbShellWidthMm, bbShellDiameterMm, spindleInterface, frontAxleInterface, rearAxleInterface, frontBrakeFluidType, rearBrakeFluidType, frontRotorSizeMm, rearRotorSizeMm]
claves_producto: [bead_seat_diameter_mm, hub_old_mm, axle_type, spoke_hole_count, freehub_type, cassette_spline_standard, chain_speeds, shift_actuation_family, bb_shell_standard, crank_axle_interface_declarations, brake_type, rotor_diameter_mm, fluid_type, valve_type]
revisado: 2026-10-02
---

# Cómo guarda y juzga Vinabike la compatibilidad

Esta es la página «maestra»: une el oficio (las demás páginas) con dónde vive
cada cosa en el sistema. Cuando el Master Schema y esta página no coincidan,
manda el código y la base viva; se corrige la que esté atrasada.

## Dónde vive la verdad

| Pieza | Dónde | Qué guarda |
|---|---|---|
| **Ficha de la bici** | `bikes` + `bike_profiles.technical_profile` | el estado real de esa bici (kernel V1 y detalle); cambia cuando un trabajo cambia partes |
| **Catálogo de bicis** | `bike_catalog` | la ficha de fábrica por modelo; punto de partida |
| **Ficha técnica del producto** | `spec_facts` sobre `spec_definitions` (902 definiciones globales) y `spec_templates` por familia | cada dato del producto con su origen (`mechanic`, `supplier_text`, `research`, `inferred`…) |
| **Reglas que la base hace cumplir** | `form_contract` de cada plantilla, `field_applicability`, `row_conditions`, funciones `spec_*_internal_v1` | qué opciones valen, qué campo aplica cuando otro tiene cierto valor, filas válidas |
| **El motor del taller** | `BikeProductCompatibilityService` (`lib/modules/bikeshop/services/`) | compara bici y producto en 26 familias; devuelve *Compatible*, *Revisar* o *No compatible* con detalle |
| **Evidencia** | registro K01–K52 (`docs/architecture/bicycle-compatibility-knowledge.md`) | afirmaciones de un modelo concreto con su fuente |
| **Método y conceptos** | este wiki | el oficio y el mapa |

## El kernel de la bici y su pareja en el producto

| Concepto | Ficha de la bici | Ficha del producto | Página |
|---|---|---|---|
| Tipo de bici | `bikeType` | — | [principios](principios.md) |
| Diámetro de rueda | `wheelSize`, `front/rearWheelBsdMm`, `front/rearRimBsdMm`, `front/rearTireBsdMm` | `bead_seat_diameter_mm`, `rim_etrto`, `tire_etrto`, `tube_fit_rows` | [ruedas](ruedas-y-neumaticos.md) |
| Válvula | `valveType` | `valve_type`, `rim_valve_bore_mm`, `valve_length_mm` | [cámaras](camaras-y-valvulas.md) |
| Espaciado de maza | `frontHubSpacingMm`, `rearHubSpacingMm` | `hub_old_mm`, `front_hub_old_mm`, `rear_hub_old_mm` | [mazas](mazas-ejes-y-espaciado.md) |
| Eje | `frontAxleInterface`, `rearAxleInterface` | `axle_type`, `hub_axle_diameter_mm` | [mazas](mazas-ejes-y-espaciado.md) |
| Rayos | `frontSpokeHoles`, `rearSpokeHoles` | `spoke_hole_count` | [mazas](mazas-ejes-y-espaciado.md) |
| Núcleo | `freehubType` | `freehub_type`, `cassette_spline_standard`, `rear_drive_interface`, `freehub_bodies_accepted` | [núcleos](nucleos-y-cassettes.md) |
| Velocidades y configuración | `drivetrainConfig` (piñones de atrás = segundo número), `drivetrainSpeeds` (marchas totales) | `chain_speeds`, `sprocket_count`, `*_application_configurations` | [cadenas](cadenas.md), [cambios](cambios-y-mandos.md) |
| Familia de tiro | (se deriva de las piezas) | `shift_actuation_family`, `rear_derailleur_actuation_ratio_declaration` | [cambios](cambios-y-mandos.md) |
| Pedalier | `bottomBracketFamily`, `bbShellWidthMm`, `bbShellDiameterMm`, `spindleInterface` | `bb_shell_standard`, `bb_accepted_spindles`, `crank_axle_interface_declarations` | [pedalier](pedalier.md), [bielas](bielas-y-platos.md) |
| Freno | `brakeType`, `rimBrakeFamily` | `brake_type`, `caliper_mount`, `lever_cable_pull` | [disco](frenos-de-disco.md), [llanta](frenos-de-llanta.md) |
| Rotor | `frontRotorSizeMm`, `rearRotorSizeMm` | `rotor_diameter_mm`, `max_rotor_mm`, `rotor_adapter_fitments` | [disco](frenos-de-disco.md) |
| Líquido de freno | `frontBrakeFluidType`, `rearBrakeFluidType` | `fluid_type`, `brake_fluid_declarations` | [hidráulicos](frenos-hidraulicos.md) |
| Suspensión | `suspensionLayout` | `fork_kind`, `eye_to_eye_mm`, `stroke_mm` | [suspensión](suspension.md) |

La bici y el producto comparten **conceptos y posiciones, no nombres de campo**:
`spoke_hole_count` de una llanta trasera corresponde a `rearSpokeHoles` (visión
del dueño, 2026-09-27, «matriz de compatibilidad unificada»).

## Huecos conocidos (2026-10-02)

- La bici no guarda: patilla del cuadro, dirección (SHIS), diámetro de tija,
  manubrio, neumático más ancho que admite el cuadro, rotor máximo del cuadro.
- El motor no tiene familia para horquillas ni amortiguadores.
- *Revisar* mezcla «con condiciones», «sin confirmar» y «en conflicto»; el
  contrato tiene los cinco veredictos.
- La tienda no puede todavía decir «calza con tu bici» usando la ficha real del
  cliente, aunque el taller la tenga ([bike-matrix-vs-vinabike.md](bike-matrix-vs-vinabike.md)).
- Tablas de fabricante sin vista de tienda: `freehub_bodies_accepted`,
  `bottom_bracket_required`, `bb_installation_claims`, `bb_shell_ports`,
  `chain_quick_links_supplied`, conectores hidráulicos y adaptadores de freno.

## Antes de cambiar el motor o una ficha

El Master Schema exige (sección «Mandatory External Technical Research
Protocol»): mirar Sheldon Brown y Park Tool, los datos vivos de producción y el
esquema actual. Este wiki es el primer paso de esa investigación; lo nuevo que se
aprenda se escribe aquí antes de cerrar la tarea.

## Fuentes

- `BIKE_WORKSHOP_MASTER_SCHEMA.md` («V1 mandatory base compatibility kernel»,
  «Mandatory External Technical Research Protocol», «La ficha es el estado real de
  la bici»).
- `docs/architecture/product-technical-specifications-contract.md` (§7–§8).
- `lib/modules/bikeshop/services/bike_product_compatibility_service.dart` y
  `lib/shared/models/product_compatibility.dart`.
- Lectura de `spec_definitions` en producción, 2026-10-02.
