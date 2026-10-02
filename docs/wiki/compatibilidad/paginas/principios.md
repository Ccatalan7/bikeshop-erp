---
titulo: Cómo se juzga una compatibilidad
resumen: el método de un mecánico experto antes de decir «calza»; vale para todas las demás páginas
fuentes: [sheldon-brown, park-tool, bike-matrix]
k: [K07, K09, K10, K31, K32, K34, K36, K44, K51]
claves_bici: [bikeType]
claves_producto: []
revisado: 2026-10-02
---

# Cómo se juzga una compatibilidad

## Lo esencial

- Una compatibilidad es la relación entre **interfaces**, no entre productos.
  Una biela no «calza con un cuadro»: su eje calza con un pedalier, y ese
  pedalier calza con la caja del cuadro. Son dos interfaces independientes
  ([K18]).
- Cada interfaz tiene **varias dimensiones** que deben coincidir todas: un
  cassette y una maza comparten estriado, largo del núcleo y número de
  velocidades. Que coincida una no prueba nada ([K01], [K12]).
- **Identidad no es calce.** El modelo, la marca y la medida identifican un
  producto; si calza con otra pieza lo decide la interfaz. Una medida nunca es
  un modelo (contrato de identidad de producto).
- **El alcance manda.** La guía general (Sheldon Brown, Park Tool) explica qué
  comparar; la tabla del fabricante de ese modelo y revisión certifica qué
  combinaciones aprueba; una medición describe sólo el ejemplar medido. No se
  convierten una en otra ([K07], [K36], [K44]).
- **Posible no es aprobado.** Muchas cosas funcionan «a martillazos». Bike
  Matrix lo dice así: no recomiendan una combinación salvo que nueve de cada
  diez mecánicos la respalden [BM]. Vinabike igual: lo que sólo funciona con
  trucos no se ofrece como compatible ([K07], [K31]).

## Los cinco veredictos

| Veredicto | Cuándo | Ejemplo |
|---|---|---|
| **Compatible** | todas las interfaces que importan coinciden y nada lo contradice | cassette HG de 10 en núcleo HG 8-10 |
| **Compatible con condiciones** | calza con una pieza o paso adicional explícito | cassette de 7 en núcleo de 8-10: separador de 4,5 mm [SB] |
| **Incompatible** | una contradicción demostrada para ese montaje | cassette Microspline en núcleo HG |
| **Sin confirmar** | falta un dato; no hay contradicción | la bici no tiene registrado el núcleo |
| **En conflicto** | dos fuentes aplicables se contradicen | ficha del proveedor vs tabla del fabricante |

Es el contrato de fichas (§8). El motor de la app hoy lo resume en tres niveles:
*Compatible*, *Revisar* y *No compatible* (`ProductCompatibilityAssessment`).
Bike Matrix usa cuatro estados en su etiqueta: `compatible`, `warning`,
`incompatible` y `unavailable` [BM].

## Reglas que se repiten en todo el wiki

1. **Los adaptadores son direccionales.** Un adaptador post mount +20 lleva un
   rotor de 160 a 180, no al revés. Un adaptador de 6 pernos a Centerlock existe;
   de Centerlock a 6 pernos no [PT]. El veredicto dice qué adaptador y en qué
   sentido ([K09], [K47]).
2. **Una condición es parte del veredicto**, no un detalle. Un separador, unas
   lainas o un adaptador se nombran; si falta, la venta queda incompleta.
3. **Opciones independientes no se excluyen.** Que un cuadro acepte 68 y 73 mm,
   o un rotor 160 y 180, son dos verdades, no una contradicción ([K34]).
4. **Un dato dimensional necesita pieza, variante y significado.** «29 mm» no
   dice nada sin «ancho interior de llanta, variante X» ([K51]).
5. **No hay bandas universales.** No se deduce la velocidad de una cadena por su
   ancho ni el modelo de un neumático por su medida ([K03], [K32]).
6. **Lo desconocido se pregunta.** Ante la duda se mide la pieza vieja o se pide
   la bici; nunca se completa con un supuesto silencioso.

## Trampas frecuentes

- Igualar nombres comerciales: «26 pulgadas» son al menos cuatro diámetros
  distintos ([ruedas-y-neumaticos.md](ruedas-y-neumaticos.md)).
- Confiar en «misma velocidad, cualquier marca»: el 12 velocidades de Shimano y
  el de SRAM no se mezclan aunque los dos sean «12» [BM][PT].
- Tratar la cantidad de piñones como «velocidades de la bici»: 3×8 no es una
  bici de 24 compatible con cosas de 24 ([K01]).

## En Vinabike

- El veredicto que ve el mecánico sale de `BikeProductCompatibilityService`
  (`lib/modules/bikeshop/services/bike_product_compatibility_service.dart`),
  con 26 familias de piezas evaluadas. Compara la ficha de la bici
  ([modelo-vinabike.md](modelo-vinabike.md)) con la ficha técnica del producto.
- Las reglas que la base hace cumplir al guardar (opciones permitidas,
  condiciones entre campos, filas) viven en `spec_definitions`, en el
  `form_contract` de cada plantilla y en las funciones `spec_*_internal_v1`.
- Lo que falta: el motor no distingue todavía *sin confirmar* de *en conflicto*
  (los dos caen en *Revisar*), y no siempre nombra la condición (qué separador,
  qué adaptador).

## Fuentes

- Sheldon Brown, artículos citados en cada página ([fuentes/sheldon-brown.md](../fuentes/sheldon-brown.md)).
- Park Tool, Repair Help ([fuentes/park-tool.md](../fuentes/park-tool.md)).
- Bike Matrix, blog «Anything is compatible if you use a hammer… not!» y
  documentación del SDK ([fuentes/bike-matrix.md](../fuentes/bike-matrix.md)).
