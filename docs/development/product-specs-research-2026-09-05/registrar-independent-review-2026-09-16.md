# Registrador de aplicaciones: revisión independiente — 2026-09-16

La revisión del aplicador del 2026-09-07 dejó escrito que «el registrador es tan crítico como
este archivo y no puede quedar sin su propia revisión independiente», porque el RPC confía en
él para todo lo que no vuelve a comprobar. Esta revisión es de Claude como único propietario,
sólo lectura de `scripts/inventory/prepare_product_spec_registration.py`,
`prepare_product_spec_application.py` y `simulate_product_spec_research.py`, con las 58 pruebas
unitarias Python y la ida y vuelta local corridas después de los dos cambios que aplico abajo.
No hay revisor distinto disponible: queda dicho, no disimulado.

## Qué comprueba el registrador antes de emitir el SQL

1. **El paquete no puede haber cambiado.** `verify_bundle` recalcula `bundle_sha256` sobre el
   cuerpo, `command_sha256` sobre el comando y `backup_sha256` sobre la preimagen, y exige que
   `operation_id` sea el uuid5 de proyecto, tenant y sha del comando. Un paquete editado a mano,
   o llevado a otro proyecto, no registra nada.
2. **La revisión se rehace fresca, no se confía en el hash.** Vuelve a simular la propuesta
   contra el servidor con la sesión autenticada real y ejecuta `prepare` completo: esquema v2,
   evidencia archivada con sha, revisor distinto del investigador, preimagen entera y postimagen
   entera. Si el `bundle_sha256` fresco difiere del sellado, aborta con «Fresh review differs».
   Como la preimagen viva entra en el paquete, un producto que cambió después de la revisión
   hace fallar el registro antes de tocar la base.
3. **La readiness tiene que estar cerrada y ser exacta.** Exige `enabled = true`, ids
   canónicos, dos sha256 y una fecha de cierre con zona horaria; el SQL vuelve a leer la fila
   `for share` y compara `enabled`, ambos hashes y `closed_at`, con `40001` si difieren.
4. **El registro es idempotente y no reemplaza aprobaciones.** `insert … on conflict(id) do
   nothing` y después comparación de todas las columnas con `for update`; una aplicación
   revocada o distinta aborta con `23514`. La repetición exacta del mismo SQL está probada.
5. **El SQL no puede escapar de su literal.** Comillas dobladas, `standard_conforming_strings`,
   etiqueta de dólar que se muta si aparece en algún valor; el fixture de la ida y vuelta lleva
   un modelo con `' \ $registration$ $$ ; COMMIT; --` y sobrevive.
6. **Actor y proyecto.** La CLI rechaza una sesión cuyo proyecto o actor no sean los del comando
   sellado. El SQL en sí corre por la ruta guardada como `postgres`: es privilegiado por diseño
   y por eso vive fuera del cliente.

## Lo que encontré y cambié

1. **Un recibo de readiness era opaco.** El registrador aceptaba dos sha256 sin mirar a qué
   archivos correspondían; bastaba un JSON con 64 hexadecimales. Ahora la CLI exige `--audit` y
   `--review`, recalcula el sha256 de ambos archivos y aborta si no coinciden con el recibo.
   `registration_sql` no cambia (la ida y vuelta lo llama directo con una readiness sintética).
2. **Dos pendientes ya no eran ciertos.** El simulador añadía siempre
   `authenticated_spec_only_applicator_pending` y, por cada hecho de origen `research`,
   `research_provenance_writer_pending`; desde `20260916140000` el aplicador existe y la
   procedencia `research` se escribe. Quedan `global_sanitation_open` (la readiness, que sigue
   sin existir) y `canonical_name_receipt_required` para lecturas de nombre, que bloquea. Un
   paquete sellado hoy declara el pendiente real y nada más.

## Lo que sigue abierto

- ~~**Nadie puede revocar una aplicación** salvo por SQL privilegiado directo (`revoked_at`); no
  hay herramienta ni recibo de revocación.~~ **Cerrado el 2026-09-16:**
  `revoke_product_spec_research_application_v1` y su recibo
  ([research-revocation-2026-09-16.md](research-revocation-2026-09-16.md)).
- **Nadie lee los recibos salvo el actor** por RPC. Un lector de auditoría para el dueño sigue
  pendiente (registro del aplicador).
- **La readiness no existe** y su creación es una decisión: apunta por sha256 a una auditoría
  global concreta y a una revisión independiente concreta. Con esta revisión, el registrador
  ya no la acepta a ciegas.
- **Revisor distinto.** Esta revisión la hizo el mismo propietario que corrió el aplicador.

Llenado técnico persistido: 0.
