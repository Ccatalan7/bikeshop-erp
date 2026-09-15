# Nueve familias de piezas de rueda aplicadas — 2026-09-07

Migración `20260908001000` APPLIED y verificada a las **2026-09-08T00:43:49Z**
(7 de septiembre en Los Ángeles). Publica 9 plantillas, 42 definiciones,
49 opciones y 74 usos; conserva exactamente siete definiciones compartidas.
Son **45 plantillas nuevas activadas en cuatro bloques**, con cero productos
rellenados y cero nuevas asignaciones. Quedan 23 nuevas, las correcciones de
las 37 iniciales y el saneamiento transversal previo al llenado.

Familias: hub_axle, hub_small_part, wheel_retention, spoke_nipple,
tubeless_tape, tubeless_repair, valve_small_part, tire_liner y tube_repair.

## Cambios comprobados

Interfaces y retenciones separan componente, configuración, posición, longitud
útil y su referencia de medición, asiento y rosca. Diámetro y paso conservan
unidades independientes: un eje de 10 mm × 26 TPI cabe sin conversión.
Las cabecillas distinguen rosca del radio e interfaz de herramienta. Las
bandas antipinchazo conservan cada combinación nominal o BSD con su ancho,
sin productos cartesianos ni equivalencias inventadas. Los reparadores
declaran superficie/material/modelo y condiciones; válvulas y mechas mantienen
sus miembros e interfaces por fila. Los escalares que duplicaban esas
declaraciones se retiran como legacy, conservando sus observaciones.

La revisión inicial de rosca acoplaba las dos unidades y fue corregida antes
de publicar. El dictamen final de Claude comprobó el contraejemplo de Park,
los seis hashes y las nueve condiciones de fila. No se amplió una definición
ya aplicada ni se convirtió una medida habitual en regla universal.

Límites: Mr. Tuffy no aportó una tabla primaria legible en esta revisión;
sus fixtures son sintéticas. Las instrucciones de cinta siguen siendo texto,
no una función de holgura. Los vocabularios de desconocido de otras plantillas
y la rosca cerrada de horquilla requieren sus propios sucesores.

## Evidencia y recuperación

| Artefacto | SHA-256 |
|---|---|
| Catálogo | `1f38ce44b48c9d58154a5342ddc014642af15f3401718e467643b6bb0608b501` |
| Casos | `5463a15b9385df3c2db8815b3fb1337fe4995961afec695edbf763fe5fe23852` |
| Preimagen | `8f0d8c6ed1a1f296d2623a579c75f3afbfd1822a84ace80d99f5786bd8c49837` |
| Paquete | `78ace24d3cbedc73faa743a62357c75323cc37e6d1ecbf29d46bf20dd628311e` |
| Migración | `a401264cd180ce57b268435193e3fae7dcd29cd56afcce460c6863e9003fe990` |
| Verificador | `2abaf25120303cd83a834357c147bb4971e3db5e1f96e8e05708c163966f2108` |
| Revisión Claude | `35d954c5a6a7c66f1cf36042ee44250ffc97fc9b07d5221f28aaa74da4969be9` |

44 pruebas Dart y cinco regresiones del publicador en rollback correctas;
35 casos sobre el catálogo real pasan en local y producción. El verificador
falló antes y pasó después. Recibo:
`.tmp/db/migration-receipts/20260908001000.receipt`.

Lectura autenticada a las **00:44:46Z**: 9 plantillas, 74 campos,
49 definiciones, 86 opciones incluyendo compartidas y nueve consultas de
referencias. Archivo: `.tmp/product-spec-catalog/wheel-small-parts-authenticated-readback.json`.
No es una captura visual ni una asignación de productos.

La comparación independiente de `wheel-small-parts-live-before.json` y
`wheel-small-parts-live-after.json` sólo cambió fecha y versión de migración:
productos, facts, categorías, ACL, políticas y motor permanecen iguales.
El publicador preserva también referencias en la misma transacción.

Preimagen adicional verificada en
`/Users/Claudio/Vinabike Backups/Product Specs Legacy/20260908T0010Z-wheel-small-part-metadata`;
el backup completo legacy `20260906T222802Z-pre-fill` sigue disponible.
La recuperación sólo puede desactivar directamente plantillas sin ligaduras;
no sobrescribir hechos posteriores. El consumidor local de compras todavía
requiere próxima distribución. macOS177/Android65 no incluyen ese parche.

Siguiente cierre: revisión independiente e integración de suspensión/dirección
y piezas pequeñas de transmisión; Claude prepara cables y mandos mecánicos.
