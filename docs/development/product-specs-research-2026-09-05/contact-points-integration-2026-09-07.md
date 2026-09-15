# Diez plantillas de puntos de contacto aplicadas — 2026-09-07

Aplicadas, verificadas y registradas a las **23:49:20Z** mediante
`20260907235000_contact_point_spec_templates.sql`: 10 plantillas,
99 definiciones, 114 opciones y 133 usos nuevos; diez definiciones compartidas
con sus opciones se conservan exactamente. Son **36 plantillas nuevas activadas**
en los tres bloques, con cero nuevas asignaciones y cero productos rellenados.

Familias: pedal, pedal_peg, grip, handlebar_covering, handlebar, stem,
seatpost, seat_clamp, saddle y saddle_cover. Disponibilidad del esquema no
equivale a certificación mecánica ni a adopción por el inventario.

## Correcciones y decisiones

Los puños conservan dos ejes: medición interior con zona/condición identificada,
e interfaz nominal de manubrio declarada. Se rechazó CP-1 como fue propuesto:
ni Park Tool ni la semántica existente justifican igualar ambos diámetros.
La fixture 21,9/22,2 sólo prueba representación, no un ajuste físico aprobado.

El escalar de apriete sí tenía un defecto: ODI Lock Jaw v2.1 publica un rango
en dos unidades. La nueva tabla conserva magnitud, valor o extremos, unidad,
abrazadera/configuración, condiciones y fuente. Los rangos invertidos y los
ejes mezclados bloquean; los datos desconocidos quedan pendientes. No convierte
unidades ni inventa tolerancias o aprietes universales. El manual GP1 06/2014
se releyó para conservar ambas unidades impresas junto con la variante exacta.
Los largos por lado y la zona recta exigida siguen separados por su significado,
no por una supuesta discrepancia numérica en GP1 Standard, que se retiró.

`pedal_thread` y `dropper_actuation` ya eran legacy; uniformar sus condiciones
con `never` es limpieza declarativa, no una reparación del motor. El helper de
contenido sólo cambia el uso nuevo; la definición compartida permanece intacta.
Fuentes y alcance de las decisiones en [K41](../../architecture/bicycle-compatibility-knowledge.md).

## Evidencia de publicación

| Evidencia | SHA-256 o resultado |
|---|---|
| Catálogo contact-points | `1a10d6e52e4b50ae2da80dc2590cd0c510a639884edb8e46d0c7c81b1c0dc40a` |
| Casos | `6695414854f1f025653d99d3d2a9ba35cd4a3ab1b01578f4f64a5b3af0e0d1dc` |
| Preimagen | `5e12173a2fb34f0aa2ed69c2bcfb74f8a9fb368ad352022a94b9c142ac40ccae` |
| Paquete | `15bd2b80878ef1020fc1b408736b83d3d24a6fb14c4c47d78b31953f38cffde5` |
| Migración | `6992d0facc1856df75df556ed1f54e017b88e0eaa3e26047799260a1bad85e89` |
| Verificador | `1b892fa4b21ebb0f90f000b5c92870eeaa1c584cc310433945277fc62c6243da` |
| Revisión Claude, dictamen aplicar | `20cab962b462ecfe7b3ff5b3236f9a59ba4bd8c832b6345a0b74ae3404f37013` |
| Dart | 86 pruebas correctas |
| SQL local y producción | 75 casos correctos en cada uno |
| Publicador local | 5 regresiones correctas en rollback |

Mismo publicador parametrizado de los dos bloques anteriores: preimagen viva,
igualdad JSONB completa en columnas administradas, guardas de colisión y pin
del validador. Los dos bloques aplicados permanecen idénticos byte a byte.
La compartida histórica `pedal_thread` se reutiliza; `origin` no decide qué existe.
El verificador falló antes de publicar y pasó después. Recibo APPLIED en
`.tmp/db/migration-receipts/20260907235000.receipt` y bitácora
`.tmp/db/contact-points-publication-deploy.log`.

La comparación independiente de `contact-points-live-before.json` y
`contact-points-live-after.json` a las 23:49:46Z confirmó sin cambios los
productos, facts, categorías, ACL, políticas y motor. La migración además
preserva referencias en la misma transacción. El motor continúa en 2600,
MD5 `ac0738d5c2039412b603dc71adc41721`.

Lectura autenticada con el actor Debug existente: 10 plantillas, 133 campos,
109 definiciones, 152 opciones incluyendo las compartidas, y diez consultas
de referencias. Resultado exacto y cero escrituras a las 23:49:50Z:
`.tmp/product-spec-catalog/contact-points-authenticated-readback.json`.
No se atribuye a esta verificación una captura visual de la ficha ni una
asignación que todavía no ocurrió. El cambio local del consumidor de compras
sigue requiriendo próxima distribución; macOS177/Android65 no lo incluyen.

## Recuperación y siguiente cierre

El backup completo legacy de `20260906T222802Z-pre-fill` se conserva. Preimagen
adicional en `/Users/Claudio/Vinabike Backups/Product Specs Legacy/20260907T2350Z-contact-point-metadata`,
permisos restringidos y hashes comprobados. Sólo se pueden desactivar sin
resolver dependencias las plantillas que aún no tienen ligaduras; no sobrescribir
hechos posteriores para recuperar el estado anterior.

Quedan 32 plantillas nuevas de la propuesta congelada sin publicar, además de
los cambios propuestos sobre las 37 iniciales y el saneamiento de asignaciones,
consumidores y evidencia. La siguiente revisión con Claude cubre nueve familias
de piezas de rueda y reparación. El llenado sigue en cero y requiere cerrar el
saneamiento global y el aplicador autenticado con recibos.
