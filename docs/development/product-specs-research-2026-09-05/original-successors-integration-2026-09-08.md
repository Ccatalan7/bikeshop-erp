# Integración de los 37 sucesores originales

Actualizado el **14 de septiembre de 2026** tras integrar H1–H5 entregados por
Claude en el mensaje 192 de «Diagnóstico fichas técnicas Viñabike».

Las 37 propuestas adjudicadas se ensamblaron en un único catálogo: 376
definiciones y 593 usos. La auditoría no encontró conflictos de identidad,
tipo, unidad, dominio, etiqueta o reglas entre definiciones compartidas.
`compile_original_spec_successors.py` exige las entradas por hash, rechaza
familias/casos/identidades duplicados y conserva cada pendiente con su origen.

**599 pruebas Dart pasaron:** 37 plantillas y 562 casos. Las 40 pendencias
documentadas no se cuentan como casos aprobados. Esto verifica la integración
de representación, no compatibilidad mecánica de datos aún sin investigar.

Catálogo `e0cccea8cdea5835e47301d11060bc735454334a9bdf6e0666b9bb5b5d87b28d`;
casos `3d8f9a4dd6c79af3ebeeacb730506d72479a057a3ef13b29bc06e6e9175e5af8`.
Manifiesto de entradas: `original-successors-shared-definition-audit-2026-09-08.json`.
Salida privada: `.tmp/product-spec-catalog/original-successors-integrated-tests-20260914.log`.

Preimagen leída directamente de producción a `2026-09-14T19:13:09.639478Z`,
152 definiciones existentes; hash
`e3f3432e49057020067adb1611992a2065d3ce313a49a1a50c06250e23ce3f35`.
Paquete integrado: 224 definiciones nuevas y 317 cambios de metadatos.
Las definiciones, plantillas y campos publicados coinciden exactamente con la
preimagen previa del 8 de septiembre. Las asignaciones sí cambiaron: ahora hay
868 productos efectivos en estas familias; no se reutiliza el conteo viejo.

**562 casos SQL pasaron**, con avance, repetición exacta y rollback, preservando
observaciones/identidad y verificando metadatos completos. El ensayo local
incluye el cuerpo de orden estricto ya publicado; no instala cambios duraderos
en local. Evidencia:
`.tmp/db/original-successors-integrated-candidate-20260914/forward-replay-and-cases.log`.

Corrección del registro anterior: el ensayo del 8 de septiembre terminó con
547 casos SQL aprobados tras resolver nueve alias de transporte de piñonería;
el documento había quedado describiendo el primer fallo. Los alias conservan
campo, gravedad y estado pendiente. El nuevo ensayo prueba además los cambios
H1–H5; no reutiliza aquel resultado como prueba de este catálogo.

**Nada de este catálogo se ha activado.** Claude devolvió la propiedad del
compilador de bielas y sus salidas; Root integró y verificó el delta. El
compilador se detiene si cambia una entrada. Siguen pendientes el perfil
tipado por miembro de kit, las referencias OEM/identidades, consumidores,
validación y distribución del cliente, saneamiento de asignaciones y llenado.

### Adopción renovada sobre los productos actuales

Se capturaron **868 productos** por la RPC autenticada, con cero errores y cero
escrituras. El lector exacto y validador compartido del editor evaluaron el
catálogo integrado: cero productos bloqueantes, cero observaciones activas
fuera de proyección, **1.056 observaciones legacy conservadas** y 863 productos
con datos pendientes. Las asignaciones ya existentes son el alcance del ensayo;
no resuelve productos sin ficha ni certifica que cada asignación sea correcta.

Resumen público por familia:
`original-successors-adoption-summary-2026-09-14.json`.
Evidencia privada:
`.tmp/product-spec-catalog/original-successors-snapshots-20260914/manifest-20260914T192211737152Z.json`
y `.tmp/product-spec-catalog/original-successors-adoption-20260914.json`.
Cada captura tiene su propia instantánea consistente; no equivale a una
transacción global ni reemplaza las comprobaciones de deriva antes de publicar.

Continuidad Claude (14 de septiembre): el acceso se recuperó desde la ventana
normal con Cmd+,; se verificaron Code, este chat/repositorio, Opus 5 Fast y
Dynamic workflows desactivado. La etiqueta de esfuerzo sigue mostrando
Ultracode con workflows apagados. El mensaje 194 entregó la revisión F2 en
`member-profile-architecture-review-2026-09-14.md`; el 195 pide una revisión
acotada de archivo de perfiles, límites de contenido y consumidor. Claude sólo
posee ese documento. Root conserva modelos/SQL/consumidores y documentación
global. El nuevo trabajo y sus límites quedan en
`member-profiles-integration-2026-09-14.md`.
