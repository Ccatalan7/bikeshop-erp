# Publicación del orden estricto

Forward preparado: `20260908185800_product_spec_strict_row_order.sql`.
La revisión de las dos funciones y sus correcciones G1/G2 ya está cerrada en
`service-parts-and-row-order-delta-review-2026-09-08.md`. El generador de
publicación no cambia ese código: añade preimagen exacta, conservación y lectura
posterior. La activación de metadatos v2 y la distribución del editor son
entregas separadas; este forward no activa una ficha ni rellena productos.

## Precondición y conservación

Preimagen productiva nueva: 93 esquemas de filas, cero v2. Los cuerpos siguen
siendo `e4147389be641a0c61e0f625c676e39b` y
`79623b3e97219d95b035aa0705be7757`. Las definiciones completas se conservan en
`strict-row-order-publication-preimage-2026-09-08.json`; los cuerpos esperados
están en `strict-row-order-publication-expected-2026-09-08.json`.

El forward exige los dos cuerpos antiguos o los dos posteriores (reintento),
con igual propietario, ACL, volatilidad, search_path y modo invocador. Un
estado mezclado o desconocido revierte. Las funciones siguen siendo privadas
para postgres/service_role; no se agregan permisos.

Una transacción repeatable read toma SHARE sobre las definiciones para impedir
que cambien esquemas durante su validación. Lock timeout 5 s y statement timeout
30 s. Compara huellas de definiciones, plantillas, usos, hechos, referencias y
vínculos técnicos de productos antes/después. Un bloqueo o un esquema inválido
revierte el forward completo. No modifica esos datos ni migra sobres de filas.

## Prueba y recuperación

Avance y repetición exacta locales terminaron en rollback, con las verificaciones
de cuerpos, ACL, conservación y normalización v2. El verificador productivo
falló antes del despliegue en su aserción de cuerpos, como corresponde.
Las 49 pruebas SQL de comportamiento y las 79 Dart constan en la readiness;
las funciones publicables son las mismas, no otra implementación.

Recuperación: las dos definiciones anteriores están juntas en la preimagen
legible. Si fuera necesario revertir, preparar un forward nuevo con esas dos
definiciones y ACL conservadas, **sólo si no se activaron esquemas v2**. Si ya
hay v2, retirar primero su activación mediante un plan de conservación de
metadatos/datos revisado; no instalar un parser v1 sobre datos v2. No se ejecuta
esa recuperación de forma automática ni se reescribe historia aplicada.

Aplicado, verificado y registrado a **2026-09-08T19:01:53Z**. Lectura real:
93 esquemas existentes validados, normalización v2 correcta, cuerpos/ACL/modo
exactos; conservación de catálogo, hechos, referencias y vínculos pasó.
Migración SHA-256 `335701286b1938971fe59373d4cd67b57cb842de7c6762911b11b0a28c449a62`;
verificador `2c2f04b777ebd0c9424475d174a0abaa5adbf892b305c39d7e2c33abb7bbeef1`.
Recibo `.tmp/db/migration-receipts/20260908185800.receipt`;
log `.tmp/db/strict-order-publication-deploy.log`.
Los cuerpos posteriores son `c21cb764086b89a50c5580ad72c0c970` y
`a7e629a22356148871253ad48ef25b3f`. Ninguna plantilla v2 fue activada.
