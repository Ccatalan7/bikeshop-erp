---
titulo: Herramientas por interfaz de servicio
resumen: qué herramienta pide cada anillo, taza, rueda libre y sistema; se elige por la interfaz, no por la marca
fuentes: [park-tool]
k: [K30, K33]
claves_bici: []
claves_producto: [tool_capabilities, tool_interface, chain_tool_speeds, remover_tool_standard]
revisado: 2026-10-02
---

# Herramientas por interfaz de servicio

## Lo esencial

- La herramienta se elige por la **interfaz de servicio** (cuántas muescas o
  estrías, qué diámetro), no por la marca de la pieza ([K30], [K33]).
- Park Tool lo hace así: contar las muescas o estrías de la taza o el anillo y
  medir el diámetro con un pie de metro [PT].

## Anillos de cassette y Centerlock

| Interfaz | Herramienta típica |
|---|---|
| 12 estrías ~23,4 mm (Shimano, SRAM, Sun Race, Chris King, DT) | FR-5.2 |
| Piñón chico de cassette SRAM XD | FR-5.2 |
| 12 estrías ~22,8 mm (Campagnolo) | FR-11 |
| Anillo Centerlock de estrías internas (eje QR) | FR-5.2 |
| Anillo Centerlock de muescas externas (eje pasante) | BBT-9, BBT-69.4 o similar |

[PT]

## Ruedas libres

| Marca | Interfaz |
|---|---|
| Shimano, Sun Race, Sachs | 12 estrías ~23 mm |
| Falcon | 12 estrías ~23 mm, **otra herramienta** (no usar la de Shimano) |
| Suntour | 2 o 4 dientes |
| Atom, Regina, Schwinn | 20 estrías ~21,6 mm |
| BMX y una velocidad | 4 dientes ~40 mm |

[PT]

## Pedalier

- Roscado: por cantidad de muescas y diámetro exterior (por ejemplo 16 muescas,
  44 mm para BSA Hollowtech II) [PT].
- Press-fit: extractor y prensa por diámetro de caja (PF41, PF42, PF46) [PT].

## Frenos

- Rotores de 6 pernos: Torx T25 [PT].
- Purga: kit DOT o mineral, nunca el mismo ([frenos-hidraulicos.md](frenos-hidraulicos.md)) [PT].
- Facing de montajes: Park DT-5.2 sirve para IS, post mount y flat mount [PT].

## Cadena

- Tronchacadenas por velocidad: los de 11-12 manejan pasadores más finos;
  pinzas para uniones rápidas [Taller][Fab].

## En Vinabike

- **Producto:** `tool_capabilities` (filas «sirve para»; la tienda las muestra),
  `tool_interface`, `chain_tool_speeds`, `remover_tool_standard`.
- **Pendiente:** el residuo de cazoletas de pedalier sin datos en la tienda (8
  productos, 2026-10-02) se resuelve con su interfaz de herramienta.

## Fuentes

- Park Tool, «Determining Cassette / Freewheel Type», «Disc Brake Rotor Removal &
  Installation», «Bottom Bracket Identification» y fichas de herramientas.
