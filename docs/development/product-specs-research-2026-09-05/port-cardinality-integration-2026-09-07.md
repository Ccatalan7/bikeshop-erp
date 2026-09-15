# Puertos y aplicabilidad — integración 2026-09-07

El forward `20260907026000` está aplicado y verificado en producción desde
`2026-09-07T18:58:08Z`. Corrige una petición imposible de datos: elegir cable
de datos hacía inaplicable la tabla de puertos de cargador, pero la cardinalidad
seguía pidiendo investigar su total. Sólo se retira ese pendiente cuando la
aplicabilidad es explícitamente falsa; desconocido conserva su pendiente.
Observaciones inválidas conservan sus errores de forma o aplicabilidad.

## Alcance y evidencia

- Forward SHA-256 `e8d1e7cb7b2f3c85338632f6e6ac948e2e2b291ddc715d1821b3a0debe692ee7`.
- Cuerpo productivo previo MD5 `9ea12d82761d6ffd0584d460cbc998d6`;
  posterior `ac0738d5c2039412b603dc71adc41721`. Una función privada cambia.
- Verificador estricto SHA-256
  `e1ead025b1bacd6ca22d4aff986bc3aa90a6ceee75ec6d46fa45395309ff7592`:
  falló antes del deploy; después comprobó cuerpo, dueño, ACL, volatilidad y
  search_path. Ejecutó las 35 plantillas ligadas en el tenant.
- Recibo: `.tmp/db/migration-receipts/20260907026000.receipt`.
  Los dos checks de preservación pasaron antes y después: cero cambios de
  hechos, identidad técnica o asignaciones.
- Fallo reproducido: cuatro de diez aserciones SQL fallaban antes. Después
  pasan las diez, 131 con cardinalidad, y **1.265 en 23 archivos** de la suite
  completa de fichas. Log: `.tmp/db/pgtap-20260907-115242.log`.
- **515 comprobaciones Dart** y **323 casos de catálogo SQL** pasaron. El
  ensayo local termina en rollback y comprueba preservación de facts/identidad.
  Logs: `.tmp/product-spec-catalog/port-cardinality-after-dart.log` y
  `.tmp/db/spec-port-cardinality-trial-after.log`.
- Dos aplicaciones locales del forward pasaron. Análisis de los archivos
  cambiados: cero errores/warnings, dos infos preexistentes.

La nueva tabla de electrónica no existe todavía en el catálogo productivo.
Por tanto el smoke de las 35 plantillas no prueba la rama concreta del cable;
esa conducta se probó con metadatos equivalentes en SQL local y el motor Dart.
No se hicieron probes mutantes sobre producción para aparentar esa cobertura.

## Catálogo propuesto y alcance del conteo

La etapa derivada conserva 105 plantillas, 711 definiciones, 58 tablas y
1.218 usos. Su única activación adicional de cardinalidad es
`consumer_electronics.power_port_configurations` contra `ports_count`.

- `all-family-port-cardinality-integrated-2026-09-07.json`:
  `16459826fee4c589cce37243afe4e159317212ddf1d47d6d6f1d76f9b3fadf15`.
- `all-family-port-cardinality-cases-integrated-2026-09-07.json`:
  `329ad3e5543048121775fd7fc3d5c5b4acd90d7446cd3deacc999b4dce3716d7`.
- Generador: `scripts/inventory/compile_product_spec_port_cardinality.py`.
  La capacidad de conteo llega en 2500; el caso de inaplicabilidad necesita 2600.

La unicidad de `port_id` y la cardinalidad son reglas distintas: tres puertos
distintos con total uno eran únicos y aun así contradicen el total. Los perfiles
de potencia y las direcciones entrada/salida no añaden puertos físicos. La
[página oficial Anker A1289](https://www.anker.com/products/a1289) ilustra dos
USB-C y un USB-A; no es una afirmación sobre un producto del inventario.

**No se trasladó la regla a modos de luces.** Sus filas son observaciones que
pueden repetir miembro y modo con condiciones/métodos/fuentes distintos.
El [conjunto Cateye AMPP500/ViZ150](https://www.cateye.com/intl/products/headlights/HL-EL085RC_TL-LD800/)
declara cuatro modos por luz, no un total único del conjunto. Comparar esas
observaciones con un `modes_count` global produciría conflictos falsos.

## Revisión y runtime

Claude revisó código/SQL/seguridad y no encontró un defecto de comportamiento:
`cardinality-applicability-independent-review-2026-09-07.md`, SHA-256
`8b37b84bdab297f8dded9a99fe991c8e67961025977387de52a666e10fa5e001`.
Root comparó además la preimagen real: las supresiones de conflicto y total que
ese informe atribuye a 2600 **ya existían en 2500**. Sólo el filtro del pendiente
es nuevo. No se amplió el cambio ni se reescribió el forward aplicado.

La sesión `payroll`, PID 90499, recargó 139/5.383 bibliotecas en 8,577 s. Los
árboles semánticos antes/después coinciden. El frame inspeccionado
`.tmp/product-spec-catalog/port-cardinality-runtime-after.png` muestra la
pantalla de OCR abierta por otro trabajo: no demuestra el formulario de puertos
ni el antiguo borrador KMC. No se navegó ni se guardó ese flujo.

El catálogo ampliado sigue sin publicar y el llenado sigue en cero. La próxima
comprobación usa snapshots autenticados exactos de todos los productos para
ensayar las plantillas propuestas sobre observaciones reales. Un resultado sin
conflictos de población no certifica mecánica ni decide asignaciones nominales.
