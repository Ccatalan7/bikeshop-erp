---
titulo: Mazas, ejes y espaciado
resumen: ancho entre tuercas (OLD), tipos de eje, Boost, rayos y lo que una maza debe calzar con el cuadro y la llanta
fuentes: [sheldon-brown, park-tool]
k: [K17, K42]
claves_bici: [frontHubSpacingMm, rearHubSpacingMm, frontAxleInterface, rearAxleInterface, frontSpokeHoles, rearSpokeHoles, frontHubSpokeHoles, rearHubSpokeHoles]
claves_producto: [hub_old_mm, front_hub_old_mm, rear_hub_old_mm, axle_type, front_axle_type, rear_axle_type, hub_axle_diameter_mm, hub_axle_length_datum, spoke_hole_count, hub_flange_to_flange_mm, hub_brake_attachment_interfaces, freehub_type, dropout_hub_acceptance_configurations]
revisado: 2026-10-02
---

# Mazas, ejes y espaciado

## Lo esencial

Una maza calza en una bici cuando coinciden **cuatro cosas a la vez**:

1. **Ancho entre tuercas (OLD)** = espacio entre punteras del cuadro/horquilla.
2. **Tipo y diámetro de eje**: eje con tuerca, cierre rápido (QR) o eje pasante
   de 12, 15 o 20 mm.
3. **Cantidad de rayos** = agujeros de la llanta (28, 32, 36…).
4. **Frenado y transmisión**: montaje de disco (6 pernos o Centerlock) o maza
   sin disco; y el núcleo o rosca para piñones atrás
   ([nucleos-y-cassettes.md](nucleos-y-cassettes.md)).

## Espaciado trasero (OLD)

| OLD (mm) | Dónde se usa |
|---|---|
| 110 | pista antigua, contrapedal, una velocidad |
| 114 | mazas de cambios internos 3-4 (antiguas) |
| 120 | 5 velocidades, pista moderna, una velocidad |
| 126 | ruta 6-7 velocidades |
| 130 | ruta 8-11 con freno de llanta; MTB 7 antigua usaba 130 |
| 135 | MTB 7-11 con QR; ruta con disco y QR |
| 142 | eje pasante 12 mm (MTB y ruta/gravel con disco) |
| 148 | Boost, eje pasante 12 mm |
| 150 / 157 | descenso (DH); 157 «Super Boost» |
| 170–197 | fatbike |

[SB]

## Espaciado delantero (OLD)

| OLD (mm) | Dónde se usa |
|---|---|
| 74 | Brompton |
| 100 | estándar: QR 9 mm, ejes pasantes 12 o 15 mm |
| 110 | Boost (15 × 110) y descenso (20 × 110) |
| 135 / 150 | fatbike |

[SB] — los plegables usan medidas propias (70, 74, 79 mm).

## Ejes

| Eje | Delantero | Trasero |
|---|---|---|
| Eje con tuerca | 3/8" o M9 | 3/8" o M10 |
| Cierre rápido (QR) | 9 mm, 100 mm | 10 mm, 130 / 135 mm |
| Eje pasante | 12 × 100 (ruta/gravel), 15 × 100, 15 × 110 Boost, 20 × 110 | 12 × 142, 12 × 148 Boost, 12 × 157 |

[SB][PT][Taller] — Un eje QR mide unos 11 mm más que el OLD (5,5 mm por lado)
[SB]. Un eje pasante de una medida no entra en una puntera de otra; existen kits
de conversión de la **maza** (tapas) cuando el fabricante los ofrece, no
adaptadores del cuadro [Fab][Taller].

## Rayos y llanta

- La maza y la llanta deben tener **la misma cantidad de agujeros** (28H con 28H)
  ([K17]). La memoria del dueño lo resume: una llanta de 28H necesita una maza de
  28H.
- El largo de rayo sale del ERD de la llanta, las dimensiones de la maza
  (diámetro de pestaña, distancia al centro) y el cruce; no es una propiedad del
  rayo ni de la llanta solos [PT][K17].

## Boost y la línea de cadena

Boost corre las pestañas de la maza 3 mm hacia afuera por lado (delantera
100 → 110, trasera 142 → 148) para una rueda más rígida; atrás también corre la
línea de cadena unos 3 mm, por eso los platos «Boost» tienen otro desplazamiento
([bielas-y-platos.md](bielas-y-platos.md)) [SB][Taller].

## Trampas frecuentes

- Ensanchar a la fuerza un cuadro de acero de 126 a 130 («cold setting») es un
  trabajo de taller con su riesgo; en aluminio y carbono no se hace [SB][Taller].
- Confundir 12 × 142 con 12 × 148 porque los dos son «12 mm».
- Ofrecer una maza Centerlock para un rotor de 6 pernos sin el adaptador (o al
  revés, que no existe) [PT].

## En Vinabike

- **Bici:** `frontHubSpacingMm`, `rearHubSpacingMm` (kernel V1),
  `frontAxleInterface` / `rearAxleInterface` (códigos del registro `axle_type`,
  por ejemplo eje pasante 15 mm; la tienda muestra la etiqueta), y los rayos
  por rueda (`frontSpokeHoles`, `rearSpokeHoles`, con variantes `Hub` y `Build`
  para la maza instalada y la que se arma).
- **Producto:** `hub_old_mm` y por rueda (`front_hub_old_mm`, `rear_hub_old_mm`),
  `axle_type`, `hub_axle_diameter_mm`, `spoke_hole_count`,
  `hub_brake_attachment_interfaces`, `freehub_type` y
  `dropout_hub_acceptance_configurations` (qué mazas admite una puntera).
- **Motor:** `_assessHubFamilyCompatibility`, `_assessRimFamilyCompatibility` y
  `_assessSpokeFamilyCompatibility`; desde el bloque F.2 (2026-09-27) compara el
  eje de la maza con el de la bici.
- Master Schema: «V1 mandatory base compatibility kernel» (espaciados y rayos) y
  la nota del dueño «La ficha es el estado real de la bici» (cambiar una llanta de
  32H por una de 28H cambia la ficha).

## Fuentes

- Sheldon Brown, «Spacing» (crib sheet) y «Frame spacing».
- Park Tool, «Determining Spoke Length for Wheel Building» y «Hub Overhaul».
