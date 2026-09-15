# Actualización de las plantillas existentes: infraestructura preparada

Estado local, sin migración de producción generada o aplicada. El nuevo publicador permite actualizar contratos/usos conservando los IDs originales, definiciones compartidas, campos retirados y observaciones. El contador de revisión sube sólo por cambios reales; la repetición exacta no incrementa revisiones. Exige una preimagen completa y rechaza ediciones posteriores, campos ausentes y colisiones. No elimina campos: el retiro debe declararse. La recuperación necesita un nuevo paquete contra el estado de ese momento; no se promete restaurar una preimagen sobre cambios posteriores.

Siete pruebas de compilador y siete regresiones SQL locales verdes, todas con rollback. SQL prueba actualización/repetición exacta, cambios concurrentes de plantilla/campo/revisión/definición y edición posterior de campo/opción. Usa metadata sintética aislada con technical_family bearing, no afirma compatibilidad de una bicicleta. El primer ensayo detectó un alias PL/pgSQL ambiguo; se corrigieron las variables del bloque antes de repetir. Evidencia `.tmp/db/existing-spec-publication-tests.log` y sus siete logs por caso.

Lectura productiva guardada a2026-09-08T03:50:11.737289Z:37 plantillas,280usos,150definiciones compartidas presentes entre campos actuales y propuestos. 863 asignaciones efectivas, cero FK explícitos. La vista efectiva es la autoridad de ese conteo. [Delta](existing-37-live-shared-delta-2026-09-07.json):21 diferencias del congelado, en opciones/unidades representadas o etiquetas; no se normalizan ni se publican sobre las vivas sin adjudicación. Snapshot privado `.tmp/db/existing-37-candidate-preimage.json`, SHA-256 `0a21d85a1539c330e661e0c5c1aa2fde0bbf29ddad67a452a018ed767d08b2a6`.

Esta infraestructura no aprueba las37 propuestas. Pendientes antes de usarla: adjudicación mecánica por familia, candidato reproducible contra metadata compartida viva, auditoría de observaciones/bindings, revisión independiente, preimagen/backup recientes, pruebas del paquete exacto y readback posterior. No reabrir la frontera legacy como si faltara: el escritor v2 productivo conserva idénticos y rechaza añadir/cambiar (MD5 `4000850abcb96fe223f1df53584eadfb`, comprobado con lectura directa, no invocado por el cliente).

| Archivo | SHA-256 |
|---|---|
| `scripts/inventory/compile_existing_spec_publication.py` | `8b70b43716294f4bb5de3ee001bdbb223fb05036fdc3c8710ea3dc94d70f913d` |
| `scripts/inventory/test_existing_spec_publication.py` | `8ea50a9fbd33f2f7d64514977e2586deca83ea4e0ec4a21847cd70d94f60762e` |
| `test/scripts/test_existing_spec_publication.py` | `a39d32eabc1563838a0ab4a0730d77c11f55df03f1f2144ff66b829e676b3ca4` |

## Adjudicación de la revisión independiente

Claude reprodujo once regresiones SQL locales y nueve sondas de compilador/alcance: aprobó aritmética nativa, replay y conservación. Se aceptó su defecto de propiedades de plantilla ignoradas. El compilador ahora rechaza cambios explícitos en name,description,default_tags,is_active,tenant_id,fechas y contract_version; la omisión conserva lo existente. No se aplica una nueva etiqueta sin invalidación. Ocho pruebas unitarias (la nueva recorre ocho propiedades) y las siete regresiones SQL del publicador volvieron a pasar. Revisión en existing-template-publication-review-2026-09-07.md. Ninguna de las37 plantillas se ha actualizado aún.
