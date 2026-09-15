# Luces, alimentación y sensores: integración de representación

2026-09-07. La propuesta de Claude quedó congelada en
`light-power-sensor-sanitation-2026-09-07.json` (`0f3685983e76efc3aa605ad63ecba70051e5c3b4ef8ccc0dd03047391b7cae47`).
La adjudicación independiente (`04883ccc4b57283195beff02393bd072a71e87981009170683d2b0f7fd788a80`)
aceptó ocho parches y corrigió diecisiete. Root normalizó los 25 y añadió el
vínculo de perfiles eléctricos a puertos; decisiones, preimágenes y tres
reemplazos de fixtures quedan en `light-power-sensor-root-decisions-2026-09-07.json`.

El compilador `scripts/inventory/compile_product_spec_mechanical_addenda.py`
reproduce A/B → frenos → esta adjudicación sin modificar los artefactos base.
La salida integrada tiene 105 plantillas, 681 definiciones, 48 campos de filas
y 1.186 usos. SHA del catálogo:
`f3178bd3c860c421d2365961fe3ff057581d2d038bb999bc59f5f0f959937072`;
84 fixtures: `3aea8e7a6a7c3d7d91bd24a8135ce91c36674699acfa5c9f283d408dd980cf42`.
La prueba SQL local validó los 105 contratos y 84 fixtures, activó todos los
guards diferidos, comprobó preservación de hechos/identidad y terminó en
rollback (`.tmp/db/spec-mechanical-addenda-trial.log`). La regresión Dart de
catálogo y contratos pasa 241 pruebas; frenos conserva otras 82 pruebas.

## Decisiones que cambian el resultado

- Cada luz posee sus datos físicos y modos mediante IDs de miembro, tanto
  sola como en juego. Se retiran siete escalares de uso activo conservando su
  historia. Totales OEM declarados de modos, puertos y lúmenes no se calculan
  contando las filas parciales conocidas.
- Los dos valores documentales de Group Ride de ViZ300 permanecen como
  observaciones competidoras fuera de los hechos canónicos. Ni una fecha de
  consulta ni dos documentos crean otra luz, revisión física o modo simultáneo.
  USB genérico es compatible con la precisión Micro-USB del manual. El
  [manual Cateye](https://www.cateye.com/intl/support/manual/data/doc/TL-LD810_820_HP_ENG_v1.pdf)
  sustenta batería y declaración IPX4 bajo JIS C0920 sin sustituir esa norma.
- Una fila de sensores expresa el alcance de la declaración. Tipo y
  transporte no identifican por sí solos el sensor ni permiten fusionar modelos.
  Se conservan generación, perfil, condiciones y transporte desconocido. El
  [manual Edge 540](https://www8.garmin.com/manuals/webhelp/GUID-17DE938E-466A-4746-BDBF-7A6FC1B3A32C/EN-US/GUID-09801A97-361B-4675-AD3A-6ACE25854DB3.html)
  no certifica cualquier modelo que comparta función inalámbrica.
- Protocolo global declarado, salida por puerto y reparto simultáneo tienen
  alcances diferentes. El ejemplo A2667 no inventa perfiles V/A ni atribuye a
  cada puerto todos los protocolos del dispositivo. No se calcula potencia
  total sumando máximos individuales.
- La unidad literal de almacenamiento se conserva. Bajo los
  [prefijos SI de BIPM](https://www.bipm.org/en/measurement-units/si-prefixes),
  1 TB equivale a 1000 GB; 1024 GB no es la misma cantidad. Capacidad utilizable
  y capacidad de etiqueta son observaciones distintas.

## Límites pendientes

Esta integración representa datos y sus pendientes; no autoriza compatibilidad
de un producto del inventario. Persisten coherencia fila-escalar, completitud
de conjuntos, conflictos de declaraciones sobre el mismo alcance, facetas de
consumidores y aprobación por contraparte. `row_conditions` se implementa y
revisa por separado en 2200, todavía local al escribir este checkpoint.
No se publicaron las 105 plantillas ni referencias nuevas; asignaciones y
llenado de productos permanecen en cero.
