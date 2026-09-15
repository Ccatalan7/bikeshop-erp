# Postizas, roldanas y guías: adjudicación de Root, sin aplicar

El candidato vigente se genera con
`scripts/inventory/compile_existing_drivetrain_service_parts_root.py`. El
compilador original de Claude permanece como propuesta histórica; ejecutarlo
solo restaura esa propuesta anterior.

Tres plantillas, 35 definiciones y 37 usos. Se conservan exactamente las diez
definiciones publicadas; 25 son nuevas. El paquete propone 14 cambios de
metadatos. Pasan 52 pruebas Dart y 49 casos SQL con avance, repetición exacta
y rollback. No hay escrituras de productos ni activación de las originales.

## Qué se acepta y qué se corrige

Se acepta separar los dos extremos de la postiza, la pieza física y su montaje,
y los modelos/interfases documentados. Una fijación compartida no identifica
la pieza, y una declaración por estándar no exige inventar un modelo o año.
La identidad de producto conserva modelo y MPN; no se duplica dentro de la ficha.

Se acepta representar cada roldana del envase con identidad, posición declarada
y cotas propias. Se corrige una inferencia de la readiness de Claude: un título
que usa un solo número de dientes no prueba que las dos roldanas sean idénticas.
Tampoco determina sus posiciones. Las declaraciones de velocidades, jaula y
modelos del par se vinculan ahora a cada ocurrencia; esos escalares sólo aplican
a una roldana individual. Un vínculo ajeno bloquea y no extiende una declaración
a las otras piezas. Las dimensiones individuales también exigen procedencia.

Se acepta distinguir recorrido de ajuste y línea de cadena con datum. Se
corrige el dueño del peso: [OneUp](https://www.oneupcomponents.com/products/bashguide-v2-iscg05)
describe el conjunto montado, mientras sus
[instrucciones](https://eu.oneupcomponents.com/blogs/bashguides-chainguides/bashguard-chainguide-install-instructions)
distinguen las placas suministradas y la instalada. Las cifras del ejemplo
quedan en configuraciones del conjunto, enlazadas por ID a la pieza montada.
La pieza suelta puede conservar su propio peso documental; no recibe el peso
del conjunto. La capacidad del SKU se transcribe con su alcance y no se calcula
como unión de rangos de piezas.

Los documentos y ejemplos públicos demuestran representación. No identifican
productos genéricos del inventario ni certifican un montaje. Las relaciones OEM
siguen necesitando su modelo/generación y una evaluación con ese alcance.

## Adopción comprobada

Captura autenticada de 33 productos: 23 postizas, siete roldanas y tres guías,
sin errores ni escrituras. Todos se evaluaron, con cero conflictos bloqueantes,
cero observaciones retiradas a legacy en esta población y ninguna activa sin
proyección. Los 33 permanecen pendientes de datos. Cero legacy observado no
significa que la conservación de los campos publicados deje de ser necesaria.

Los tres títulos que sugieren extensores continúan en revisión de asignación;
no se ejecuta ni certifica un cambio por su nombre. Sigue pendiente integrar
referencias OEM y verificar/distribuir los consumidores
del editor antes de activar. El llenado global continúa cerrado hasta completar
el saneamiento transversal.

La [revisión final de Claude](service-parts-and-row-order-delta-review-2026-09-08.md)
aceptó las cuatro adjudicaciones y no encontró defectos vigentes. Verificó
52 pruebas Dart y los agregados de adopción; el SQL lo verificó Root.
Una referencia de peso con su tabla de piezas ausente queda pendiente, no
aprobada ni contradictoria. Si la tabla está presente y el ID no pertenece a
ella, bloquea. Es el tratamiento existente de información incompleta; el
llenado debe resolver el ancla antes de presentar esa configuración como completa.

## Evidencia local

Preimagen: `2026-09-08T10:49:55.257546+00:00`. Catálogo SHA-256
`1c10d400a1bea3f26c33c67c5a81dece3cdae9c7a4f954eea74be695b0c2216f`;
casos `5084eeb7d917e294ed21caaea4c7b266a7989cc6b963410f184c543a871fbb9b`;
preimagen `09a0e6b26958535000cda8e234992b904c4371387dc47e0b702dbd8ba076e1c9`.

Logs en `.tmp/product-spec-catalog/existing-drivetrain-service-parts-root-tests.log`
y `.tmp/db/existing-drivetrain-service-parts-root-candidate/forward-replay-and-cases.log`.
La adopción está en
`.tmp/product-spec-catalog/existing-drivetrain-service-parts-adoption-20260908.json`,
sobre `existing-drivetrain-service-parts-snapshots-20260908/manifest-20260908T105000017507Z.json`.

Los casos SQL explicitan los alias existentes `field_constraint` y
`prerequisite_missing`, manteniendo dueño, gravedad y resultado; la colección
de bloqueantes usa su orden canónico. El diagnóstico de una transacción local
usa salida normal: `--format json` envuelve una consulta SELECT y no admite
un script completo con BEGIN/ROLLBACK.
