# Catorce plantillas de movilidad aplicadas — 2026-09-07

Aplicadas, verificadas y registradas a las **23:24:21Z** mediante
`20260907233000_mobility_accessory_spec_templates.sql`: 14 plantillas,
113 definiciones, 224 opciones y 163 usos de campo nuevos. Nueve definiciones
globales se reutilizan sin cambios. Sumadas a las 12 publicadas a las 22:34Z,
son **26 plantillas nuevas activadas**, sin nuevas asignaciones ni llenado.

Familias: workshop_tool, light, cycle_computer, consumer_electronics,
accessory_mount, rack_basket, fender, kickstand, bike_bag, rider_bag,
training_wheel, bike_protection, eyewear y pump. Los esquemas están disponibles;
todavía no se han vinculado automáticamente a productos ni categorías.

## Correcciones integradas

- Cuatro familias sustituyen los selectores nominales mínimo/máximo por
  declaraciones de rueda con alcance: designación literal, rango nominal en
  pulgadas o BSD. Los extremos invertidos y los ejes mezclados bloquean;
  un extremo desconocido queda pendiente. No hay conversión automática ni
  aprobación de montaje por la sola coincidencia de la medida.
- Las bombas híbridas pueden declarar CO₂ sin perder su formato manual.
  La capacidad adicional sólo se pregunta en formatos que no la declaran ya.
  La ausencia del dato queda pendiente; una negación explícita contradice
  una declaración de cartuchos compatibles.
- Una riñonera puede incluir depósito. Su capacidad se separa del formato del
  bolso y exige confirmar la inclusión. El volumen principal conserva dos
  ejes independientes: carga/hidratación y producto completo/unidad del conjunto.
- Las presiones de herramientas conservan magnitud, unidad y configuración.
  El escalar antiguo queda retirado, igual que el de bombas. El legado ya era
  excluido del guardado de hechos: DL-5 fue retirado por el revisor, no se
  presenta como un fallo del motor reparado en esta entrega.
- El helper de contenido se extiende a los usos nuevos de light, fender y
  training_wheel; la definición compartida `kit_members` permanece intacta.

Fuentes y decisiones de dominio: [K40](../../architecture/bicycle-compatibility-knowledge.md).
Se contrastaron Sheldon Brown, Park Tool INF-2, Topeak HYBRIDROCKET HP y
CamelBak M.U.L.E. 5 Waist Pack. La capacidad total/carga de esta última no se
dedujo de su nombre: esa parte de la tabla OEM no llegó en la lectura disponible.
Los casos son de representación, no atribuciones a SKU del inventario.

## Publicación y evidencia

El compilador del bloque usa la **preimagen viva** para determinar qué existe;
`origin=new` en una propuesta histórica no significa que todavía pueda insertarse.
Se extrajo `metadata_records` para reutilizar el publicador anterior. Paquete,
migración y verificador de las primeras 12 siguen idénticos byte a byte.
No se editó ninguna migración aplicada.

| Evidencia | SHA-256 o resultado |
|---|---|
| Catálogo `mobility-accessories-catalog-2026-09-07.json` | `cd477af08f8c39225d8abef182f3ce326145b0be7d1cfe043d579132838e8a44` |
| Casos `mobility-accessories-cases-2026-09-07.json` | `1ca9ec14aa994014d89ae30a85b86beaa22c5471359197b3ef41288d4e933559` |
| Paquete de publicación | `56af15d0cb8b83f6ec59c62ce71b4095ae500831d617478a88cf87d8266e6a6a` |
| Preimagen compartida | `2c1bc85e8174aaee2a3b510a2ef04ca7ca96529d81d772c821bf4785c6e99945` |
| Migración | `3412bcba5b0298dba58f3b41cb3d3dc397ed2bb0fddb1f81b273e23f47b5289d` |
| Verificador | `fb619208d15ba7ad125758a3daac9259269968f5f400cd48bd787de951e1dbdb` |
| Revisión Claude final | `5fd2fe9a305cdd240e9fd201abedae94522c387ed1f5428c2a2d64a70718299d` |
| Dart del catálogo | 148 pruebas correctas |
| SQL local y servidor | 131 casos correctos en cada uno |
| Publicador local | 5 regresiones, todas en rollback |

El verificador falló antes de publicar con error SQL y pasó después. La
igualdad JSONB incluye todas las columnas administradas y la preimagen completa
de las nueve compartidas con sus opciones. No actualiza ni amplía vocabularios
compartidos. La migración conserva fingerprints de productos, facts,
referencias y mapeos dentro de la misma transacción.

Recibo `.tmp/db/migration-receipts/20260907233000.receipt`; bitácora
`.tmp/db/mobility-publication-deploy.log`. La comparación independiente
`.tmp/db/mobility-live-before.json` / `mobility-live-after.json` a las 23:25Z
confirmó productos, facts, mapeos, validador, ACL y políticas sin diferencias.
La historia está **APPLIED**. El motor sigue en 2600, MD5
`ac0738d5c2039412b603dc71adc41721`.

El lector `verify_product_spec_metadata_publication.py` reutilizó el actor
real de la sesión Debug y su transporte restringido a lecturas. Comprobó
14 plantillas, 163 campos, 122 definiciones, 260 opciones incluyendo las
compartidas y las referencias de las 14 familias. Cero escrituras.
Evidencia `.tmp/product-spec-catalog/mobility-authenticated-readback.json`.

## Corrección de compras y límite de distribución

`supplyNeedCriterionFieldsOf` es el dueño compartido por el vocabulario del
buscador y `SupplyNeedRefinementEditor`. Excluye campos legacy, campos de
aplicabilidad constante falsa y tipos no soportados por los predicados
escalares, incluidas las tablas por componente. Conserva los requisitos
desconocidos. Un criterio guardado que el editor ya no expresa se arrastra
intacto cuando cambia otro; no se borra como consecuencia del filtro.

**65 pruebas correctas** del consumidor y editores ancho/compacto; analyzer
limpio. Regresión nueva de exclusión y conservación en
`test/widget/supply_need_hidden_criterion_test.dart`.
Esto está implementado en el checkout y requiere la siguiente distribución;
**no se atribuye al macOS177/Android65 ya publicado**. No hubo nueva captura
visual ni navegación de la app sobre estas familias aún sin asignar. La sesión
`payroll`, PID90499, quedó preservada. La revisión dinámica de criterios y la
proyección estructurada para búsquedas siguen con su propio alcance; este
filtro no convierte filas en predicados escalares.

## Recuperación y continuación

Backup legacy completo conservado en
`/Users/Claudio/Vinabike Backups/Product Specs Legacy/20260906T222802Z-pre-fill`.
Preimagen adicional de esta publicación:
`/Users/Claudio/Vinabike Backups/Product Specs Legacy/20260907T2330Z-mobility-accessory-metadata`,
con permisos restringidos y hashes comprobados. Es backup de metadatos, no
otra copia completa del inventario. Sólo se desactivan plantillas sin ligaduras;
si ya se usaron, la guarda exige resolver dependencias y preservar hechos
posteriores. No regenerar IDs ni códigos para cambiar etiquetas.

El saneamiento global, adjudicaciones de identidad/asignación, consumidores y
aplicador autenticado con recibos siguen pendientes antes del llenado.
La base de Viñabike sigue siendo 1.664 registros; el registro adicional de
otra tienda no pertenece a esta investigación. La siguiente revisión acotada
con Claude cubre pedal, pedal_peg, grip, handlebar_covering, handlebar, stem,
seatpost, seat_clamp, saddle y saddle_cover.
