---
titulo: Pedalier (caja y eje)
resumen: cajas roscadas y press-fit, ancho de caja, ejes de biela y qué pedalier une cada combinación
fuentes: [sheldon-brown, park-tool]
k: [K18, K33, K38, K50]
claves_bici: [bottomBracketFamily, bbShellWidthMm, bbShellDiameterMm, spindleInterface]
claves_producto: [bb_shell_standard, bb_shell_interface, bb_shell_width_mm, bb_shell_diameter_mm, bb_accepted_spindles, bb_installation_claims, bb_shell_ports, bottom_bracket_family, crank_axle_interface_declarations, spindle_interface]
revisado: 2026-10-02
---

# Pedalier (caja y eje)

## Lo esencial

- El pedalier une **dos interfaces independientes**: la **caja** del cuadro
  (rosca o diámetro de prensa, y ancho) y el **eje** de la biela (diámetro y
  forma). Se elige un pedalier que calce con las dos ([K18]).
- Para saber qué hay: si las tazas tienen muescas o estrías visibles es roscado o
  «thread-together»; si no tienen nada para la herramienta es press-fit [PT].
- La rosca inglesa (BSA) tiene el lado de la cadena con **rosca izquierda**; la
  italiana tiene los dos lados con rosca derecha [SB][PT].

## Cajas roscadas

| Estándar | Rosca | Ancho de caja | Notas |
|---|---|---|---|
| Inglesa / BSA / ISO | 1,37" × 24 TPI | 68, 73 (MTB), 83 (DH), 100 (fat) | la más común; lado cadena rosca izquierda |
| T47 | M47 × 1 mm | 68, 77 (ruta), 86 (ruta), 85,5 | lado cadena rosca izquierda |
| Italiana | 36 mm × 24 TPI | 70 | los dos lados rosca derecha |
| Francesa | 35 × 1 mm | 68 | obsoleta; los dos lados derecha |
| Suiza | 35 × 1 mm | 68 | obsoleta; lado cadena izquierda |
| Raleigh | 1,37" × 26 TPI | 71–76 | no es la inglesa de 24 TPI |

[SB][PT][Taller para los anchos T47]

## Cajas press-fit (por diámetro, nombres de Park)

| Grupo | Diámetro de caja | Nombres comerciales | Ejes que admite |
|---|---|---|---|
| PF41 | 41 mm | BB86, BB89.5, BB92, BB107, BB121, BB132, Shimano Press-Fit | 24, 28,99, 30 mm, 22/24 |
| PF42 | 42 mm | BB30, BB30A, BBright Direct Fit | 24, 28,99, 30 mm |
| PF46 | 46 mm | PF30, PF30A, BB386EVO, OSBB, BBright Press Fit | 24, 28,99, 30 mm |
| 37 mm | 37 mm | BB90/BB95 (Trek), «española» (BMX) | según caja |
| 41,2 mm | Mid (BMX) | rodamiento directo | 19–22 mm |
| 51,5 mm | Americana (Ashtabula) | bielas de una pieza | adaptadores para reducir |

[PT][SB] — Los ejes que admite son con el pedalier adecuado; el press-fit por sí
solo no define el eje.

## Ejes de biela

| Eje | Diámetro | Quién |
|---|---|---|
| Cuadrado JIS | cónico | Shimano y la mayoría de bielas cuadradas |
| Cuadrado ISO | cónico, otro ángulo | Campagnolo y europeas |
| Octalink / ISIS | estriado | Shimano antiguo / varios |
| Hollowtech II | 24 mm | Shimano y muchas otras |
| GXP | 24 mm lado cadena, 22 mm el otro | SRAM antiguo |
| DUB | 28,99 mm | SRAM actual |
| BB30 / 30 mm | 30 mm | Cannondale, Race Face Cinch 30… |

[Taller][SB] — **JIS e ISO no se mezclan**: la biela entra distinto en el cono y
queda mal [Taller].

## Trampas frecuentes

- Comprar «pedalier BB92» para una biela DUB: existe, pero hay que pedir **BB92
  para DUB**, no cualquiera.
- Pedalier cuadrado: además del cono importa el **largo del eje** (110, 113, 118,
  122,5 mm…), que define la línea de cadena.
- Una caja de 73 con un pedalier de 68 sin separadores, o al revés.

## En Vinabike

- **Bici:** `bottomBracketFamily` (kernel V1); al confirmarla, `bbShellWidthMm`,
  `bbShellDiameterMm` (si es press-fit) y `spindleInterface`.
- **Producto:** `bb_shell_standard`, `bb_shell_interface`, `bb_shell_width_mm`,
  `bb_shell_diameter_mm`, `bb_accepted_spindles` (ejes que recibe),
  `bb_installation_claims` (cajas donde el fabricante lo aprueba; la tienda aún no
  las muestra), `bb_shell_ports` (rosca de cada taza);
  en la biela, `crank_axle_interface_declarations`.
- **Motor:** `_assessBottomBracketFamilyCompatibility` y
  `_assessBearingFamilyCompatibility` (rodamientos sueltos).

## Fuentes

- Park Tool, «Bottom Bracket Standards and Terminology» y «Bottom Bracket
  Identification».
- Sheldon Brown, crib sheets «Bottom Brackets, Threaded» y «Unthreaded Bottom
  Brackets».
