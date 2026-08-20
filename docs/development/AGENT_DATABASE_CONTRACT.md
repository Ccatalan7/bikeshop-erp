# Agent Database Contract

Single entry point for every agent (Claude Code, Codex, Copilot, Antigravity)
doing Supabase/database work in this repository. Read this before the first
database command of a task.

This file routes. It does not duplicate policy.

| Question | Authoritative document |
|---|---|
| What may I use, what is safe, what needs a human? | `docs/runbooks/STAGING_SUPABASE.md` |
| Which exact command do I run? | `docs/development/SUPABASE_WORKFLOW.md` |
| Backup and recovery | `docs/runbooks/DATABASE_BACKUP_AND_RESTORE.md` |
| Key migration and rotation | `docs/development/SECURITY_REMEDIATION_2026-07-12.md` |

If those two first documents ever disagree, `STAGING_SUPABASE.md` wins and the
disagreement is a bug to fix in the same task.

## The one rule that resolves most confusion

**All SQL goes through `scripts/db/query.sh`. The Supabase CLI never runs SQL.**

The CLI is control-plane/metadata only — projects, secrets, Edge Functions,
backups, and post-verification migration-history registration — and is invoked
through `scripts/supabase_cli.sh`, never as the bare binary.

These are not agent SQL paths, in any environment, for any reason: any
`supabase db …` subcommand, ad hoc hosted `psql`, and the hosted SQL Editor.
They bypass the read-only transaction,
statement timeout, project-identity check, row cap, sensitive-column guard, and
audit journal that the wrapper supplies.

## Start of a database task

```bash
just db-preflight
```

Prints linked project identity, CLI authentication, credential presence
(`credential-ready` / `missing` / `inaccessible`, never values), and local stack
status. Run it once per task, not per command.

## Autonomy boundary

Agents run everything in the left column themselves, without asking. Do not
hand the user a query, a test, or a migration the repository can execute.

> **Decisión del dueño, 2026-08-05 — corrige la fila de escrituras.** «Los
> agentes deben correr los querys siempre, sin pedir confirmación.» Las
> escrituras guiadas (`--write` con `VINABIKE_DB_WRITE_CONFIRM`) pasan a la
> columna autónoma; el marcador de deliberación y el journal se mantienen. El
> costo de la regla anterior fue real: un admin recién invitado quedó fuera
> por metadatos corruptos, el arreglo era un `UPDATE` de una fila, y la regla
> lo devolvía a un Codex sin cupo. La denegación mecánica vivía en
> `.claude/hooks/guard-dangerous-bash.sh` (antiguo bloque «Production database
> writes»). Ese bloqueo general ya no existe: el hook conserva la denegación de
> bypasses/raw paths, mientras el write guardado in-scope se ejecuta por el
> wrapper canónico.

| Autonomous | Requires the owner's explicit go-ahead in the task |
|---|---|
| Guarded reads on `local` and `production` | A write during an analysis-only, diagnosis-only, draft, local-only, or ambiguous-target task |
| The smallest reviewed `--write` required by an implementation/fix/ship request, with exact read-back | Destructive deletion/repair, broad corrective backfill, credential rotation, or an unrelated pending migration |
| `just db-test`, `just db-gate`, pgTAP | Mutating probes on production, even in `BEGIN`/`ROLLBACK` |
| Registration of the exact deployed migration after successful live read-back | Arbitrary migration-history repair or registration without a verified matching deployment |
| `db-trace`, `db-fingerprint`, `db-drift`, `db-health`, `db-smoke` | Secret removal or function deletion |
| Control-plane reads and deployment of an in-scope reviewed Edge Function | `--allow-pii` (star projection over a sensitive table) |
| Reading a hosted PII column by explicit name | Anything on `staging`; staging is dormant until the owner reactivates it |

**Decisión del dueño, 2026-08-17 — las copias de esquema dejan de ser gate.**
No ejecutar `production_validation.sh` ni presentar un restore `schema-only`
como evidencia de compatibilidad. Una copia omite filas de catálogo sembradas,
estado de vistas materializadas, historia efectiva y comportamiento administrado
por el proveedor; los falsos verdes y falsos rojos cuestan más que lo que
detectan. La división válida es: pgTAP con rollback en local para la lógica,
lecturas guardadas directamente sobre producción para su estado actual y,
cuando el cambio está autorizado, deploy mínimo más read-back ejecutable en la
base real. Si una propiedad del SQL nuevo no puede observarse antes de
desplegarlo, queda declarada como gate pendiente; no se sustituye por un clon.

### Production completion is part of database ownership

Standing owner authorization recorded on 2026-07-29: when an implementation
task creates or changes a production-bound forward migration/query, deploying
that exact reviewed change through the guarded production workflow, verifying
it live, and registering its migration version are part of completing the same
task. A second routine confirmation is not required unless the task explicitly
says `local-only`, `draft`, or `no production writes`.

**2026-08-09 clarification:** those scope labels are not sticky across later
owner instructions. If the owner subsequently asks to implement, fix, finish,
ship, or deploy the same result, the newest instruction controls and the normal
non-destructive production completion above resumes. Do not preserve an older
read-only handoff as a permanent blocker, and do not call a backend-dependent
client surface complete while its production objects are absent.

Never call database work complete while its production SQL is merely local,
and never hide a pending deployment in the final notes. If credentials, drift,
or a safety gate prevents deployment, report that immediately as a blocking
condition and keep the task incomplete.

This standing authorization does not cover unrelated pending migrations,
destructive data removal, broad data correction/backfill, secret changes,
staging reactivation, or any expansion beyond the task's reviewed target.
Those operations retain their explicit authorization requirements.

Human handoff is valid only for the cases listed in `STAGING_SUPABASE.md`
("Agent ownership and valid handoffs"): missing provider access, billing/MFA/legal
UI, ambiguous target or authorization, destructive scope expansion, or a failed
gate needing a business decision. Convenience is not a valid handoff.

In Claude Code this boundary is also mechanical: `.claude/settings.json` — the
committed, machine-shared file, not the git-ignored `settings.local.json` —
pre-approves the guarded read and test commands so they never interrupt the
user, and denies the bypass paths (`supabase db …`, ad hoc `psql`, forced
redump and `production_validation.sh`). An in-scope write is always prefixed with
`VINABIKE_DB_WRITE_CONFIRM=…`; this is a deliberate, task-bound execution
marker, not a request for another owner confirmation. Never remove the marker
or pre-approve a bypass path merely to avoid a routing boundary.

**Decisión del dueño, 2026-08-19 — producción se pre-aprueba.** «Asegúrate de
que correr querys por agentes de IA sea muy fácil y no tengan ningún problema.»
Hasta ese día el allowlist sólo cubría `query.sh local`, así que cada consulta a
producción levantaba un prompt aunque este documento ya prometiera que las
lecturas no interrumpen, y un test exigía justamente que producción **no**
estuviera pre-aprobada. Las tres cosas se alinearon: las lecturas alojadas y la
forma canónica de la escritura guiada —con el prefijo del marcador, que ninguna
otra regla cubría— están en el allowlist, y el test las verifica.

**Antes de decir «estoy bloqueado», inténtalo.** El bloque que denegaba
escrituras a producción no existe desde el 2026-08-05, y durante dos semanas los
agentes lo citaron sin comprobarlo y devolvieron trabajo al dueño por nada.
Además, hasta el 2026-08-19 las reglas de PII y de `production_validation.sh`
comparaban subcadenas contra el comando entero: *mencionarlas* en un documento,
un mensaje de commit o un `grep` se denegaba sin que hubiera consulta alguna.
Hoy se reconocen en posición de comando. Lo que sigue denegado es corto y está
en la tabla de arriba; comprobarlo cuesta un comando.

## Un read-back alojado se escribe en SQL plano, nunca con `do $$ … $$`

**2026-08-19.** El guard de transacciones de `query.sh` busca `end` después de
un `;`, y el `end;` que cierra un bloque plpgsql calza. Resultado: cualquier
archivo con `do $$ … end; $$` se rechaza con «Remote read-only SQL files cannot
manage transactions», aunque corra perfecto en `local`, donde la lectura no es
read-only y el guard no aplica. Un read-back escrito con DO parece verde en
local y no se puede correr contra producción jamás.

Las afirmaciones van en SQL plano. Para que muerdan a nivel SQL —que es lo que
`deploy_migration.sh` exige antes de sellar la migración— se dividen por cero
cuando el invariante falta:

```sql
select 1 / (case when <invariante> then 1 else 0 end) as afirma_lo_que_sea;
```

Precede la afirmación con un `select` de diagnóstico que imprima el estado
real: el error dirá sólo «division by zero», y esa fila es lo que le explica al
operador qué faltó. Ejemplo completo en
`supabase/manual_checks/verify_whatsapp_message_reactions.sql`.

Un probe con lógica plpgsql sí es válido, pero es de `local` y se corre con
`query.sh local --file` (ver `scripts/db/probes/`).

## Antes de afirmar que un dato falta, comprueba que no falle tu lectura

Reads are autonomous precisely so this is cheap. Use it.

**Lo que pasó el 2026-07-30.** El respaldo de pago de Nóminas mostró
`Haber · no quedó registrada`. Se leía `expense_payments.payment_account_id`,
que efectivamente está nulo en los 78 pagos de sueldo. Pero el asiento contable
real vive en `journal_entries` + `journal_lines` y **está completo y cuadrado
en los 78**. La app declaró rota una contabilidad sana.

La regla:

- Un campo vacío significa **que ese campo está vacío**, no que el hecho no
  exista. Antes de decírselo al dueño, busca dónde vive el hecho de verdad.
- Un campo denormalizado (`*_id`, `*_label` copiados a una tabla vecina) es una
  conveniencia de lectura, **no la fuente**. La fuente suele ser la tabla que
  registra el evento.
- Una consulta que carga las mismas filas por dos caminos distintos puede traer
  columnas distintas: si un dato aparece en una pantalla y no en otra, sospecha
  de la consulta antes que de los datos. (Pasó el mismo día: las líneas de
  nómina se leen por dos rutas y sólo una traía el join de la cuenta.)
- Cuando un valor no se puede resolver, la salida correcta es decir que no se
  pudo — nunca un valor plausible, y nunca la mitad de un hecho que debe
  cuadrar.

Una consulta de verificación cuesta segundos:

```bash
scripts/db/query.sh production --sql "select … "
```

Afirmar sin ella puede costar la confianza del dueño en sus propios datos, que
es mucho más caro que la consulta.

## Un encabezado liquidado no es el ledger de caja

**2026-08-15 — el detalle de Panorama financiero fechaba un anticipo cuando se
aplicó a Nóminas.** La serie agregada ya sumaba `expense_payments.payment_date`
y `employee_advances.paid_at`, pero su drill-down reconstruía todo desde
`expenses.paid_at`. Ese campo resume cuándo quedó liquidado el gasto: puede ser
la última cuota o la aplicación posterior de un anticipo y no identifica el
momento en que salió el dinero.

En base caja, el detalle y su agregado deben compartir los mismos dueños: cada
`purchase_payments.date`, `expense_payments.payment_date` y
`employee_advances.paid_at` es un movimiento; `expenses.paid_at` se admite sólo
como fallback explícito para registros heredados sin ninguno de esos ledgers.
Una prueba mínima incluye un gasto dividido en dos fechas y un anticipo pagado
antes de su aplicación, y exige tanto las fechas como el total del período.

## Un `text` con `CHECK` es un enum disfrazado: lee `pg_constraint`

**El dominio de una columna no está en `information_schema.columns`.** Esa vista
dice el *tipo de almacenamiento*, no los valores admitidos. Una columna
declarada `text` puede tener un `CHECK` que la reduce a tres literales, y ese
`CHECK` no aparece por ningún lado en la vista de columnas.

**Lo que pasó el 2026-08-01.** Se leyó `employees.bank_account_type` en
`information_schema.columns`, salió `text`, y de ahí se concluyó —y se escribió
en el código y en el handoff— que era **texto libre**. Design dibujaba un select
para ese campo y se le llevó la contraria «porque el esquema no tiene catálogo».
Era falso: `employees_bank_account_type_check` admite exactamente
`Cuenta Corriente`, `Cuenta Vista` y `Cuenta de Ahorro`. El editor de fichas
llevaba además una cuarta etiqueta inválida —`Cuenta Ahorro`— que la base
rechazaba al guardar. Costó una ronda entera de diagnóstico y una corrección de
Design que no correspondía.

La regla:

- Antes de declarar el dominio de una columna —y **siempre** antes de escribir
  un desplegable, una validación o un enum de cliente contra ella— consulta sus
  constraints, no sólo su tipo.
- El dominio se **cita**, no se transcribe: un `enum` de Dart que repite la
  lista a mano vuelve a divergir en el primer cambio. Que la lista tenga un
  único dueño que la tome del constraint.
- **2026-08-15 — una migración aditiva conserva todo el dominio vivo.** Una
  migración posterior de Nóminas agregó `audited_reversal` reemplazando un
  CHECK compartido, pero borró `advance_audit_attach`. Como consecuencia,
  `register_employee_advance_v3` revertía cada anticipo estructurado al llegar
  al paso de adjuntar su auditoría. Antes de reemplazar un CHECK compartido,
  haz inventario de todos sus escritores actuales y migra a la unión de valores
  existentes y nuevos; prueba además un escritor anterior después de aplicar
  la migración nueva. Nunca redefinas el dominio sólo desde los literales del
  feature que estás agregando.
- Vale igual para `NOT NULL`, `DEFAULT`, `UNIQUE` y las FK: lo que la base
  acepta lo definen sus constraints, y la vista de columnas sólo cuenta una
  parte.

```bash
scripts/db/query.sh production --sql "
  select conname, pg_get_constraintdef(oid)
  from pg_constraint
  where conrelid = 'public.employees'::regclass"
```

## `core_schema.sql` es una guía histórica incompleta, no una autoridad

2026-08-05. Al planear un aviso en `Usuarios y roles` había que saber si el
cliente podía leer `user_invitations`. `core_schema.sql:488-497` describe dos
políticas de `select` —una para `authenticated` filtrada por tenant y otra
**para `anon` con `using (status = 'pending')` y sin filtro de tenant**. Leída
sola, esa segunda línea parece una fuga: cualquier anónimo enumerando correos,
roles y tenants ajenos.

En producción no existe ninguna de las dos. La tabla tiene RLS activo y **cero
políticas**: sólo la alcanzan las Edge Functions con service role.

La causa es que ese archivo acumula `create policy` históricos que después se
reemplazaron o se dejaron de aplicar, y nada garantiza su reconciliación. Vale
como contexto de búsqueda, no como estado, baseline reproducible ni fuente de
verdad. Dos consecuencias prácticas: no se reporta una vulnerabilidad leyéndolo,
y **no se diseña una consulta de cliente confiando en que la política existe** —
el widget habría compilado, pasado sus pruebas con datos falsos y devuelto cero
filas para siempre en la app real.

```bash
scripts/db/query.sh production --sql "
  select c.relrowsecurity, p.polname, p.polcmd::text
  from pg_class c left join pg_policy p on p.polrelid = c.oid
  where c.oid = 'public.user_invitations'::regclass"
```

## Guarded read defaults you should know

Hosted reads run in `BEGIN READ ONLY` with a 30-second statement timeout and are
rolled back. Two additional defaults apply to hosted reads only:

- **Row cap.** Single-statement `SELECT`/`WITH` queries are capped at 200 rows.
  Raise it with `--max-rows N`, disable it with `--max-rows 0`. The cap is
  announced on stderr so a truncated result is never mistaken for a complete one.
- **Sensitive-column guard.** A star projection (`select *`) over a table listed
  in `scripts/db/sensitive_tables.txt` is rejected. Name the columns you need.
  `--allow-pii` overrides it and is recorded in the journal; use it only when
  the task genuinely requires the full row.

Neither default applies to `local`, which holds only synthetic data.

**2026-08-16 — el guard de proyección es exclusivamente de lectura.** El
wrapper llegó a ejecutar esa comprobación antes de distinguir `--write`, por
lo que una migración revisada que definía una vista con `select alias.*` fue
rechazada como si fuera a volcar una tabla sensible al transcript. Una
escritura alojada sigue requiriendo identidad, confirmación y journal, pero no
usa `--allow-pii`: el guard de divulgación se evalúa sólo para lecturas, tal
como indica el contrato. La regresión mínima exige que una lectura con estrella
siga fallando antes de `psql` y que una escritura con esa sintaxis alcance el
camino guardado normal.

Every invocation appends one line to `.tmp/db/journal.jsonl`: timestamp,
environment, read/write mode, SQL SHA-256, format, caps, duration, and exit
status. No SQL text, no values, no credentials. The file is git-ignored evidence,
not a deliverable.

## Una verificación que no ejecuta no verifica nada (2026-08-17)

Un read-back que sólo hace `like` sobre `pg_get_functiondef` **pasa en verde
con una función rota**. PostgreSQL acepta un `create function` cuya consulta no
resuelve hasta ejecutarla: `purchase_priority_feed_v1` se desplegó y se selló
llamando a `need.product_name`, columna que no existe, y el único síntoma fue
que un panel no aparecía en la app.

Todo read-back de una función **la ejecuta**, con un tenant real, y exige la
forma de la respuesta. Comprobar la definición sirve para fijar invariantes de
forma —que el contrato de imágenes siga publicado, que la ACL sea la correcta—,
nunca como única prueba de que la función sirve.

Dos trampas del camino guardado, ambas costaron un intento:

- **No admite bloques que manejen transacción.** Un `do $$ … $$` es rechazado
  con «Remote read-only SQL files cannot manage transactions». La ejecución va
  como consulta normal, y el contexto de tenant se fija en una **sentencia
  aparte**: dentro de un CTE el planificador puede evaluar la función antes de
  que `set_config` haya corrido.
- **Corre con un rol privilegiado, sin RLS.** Una aserción que escanea una
  vista entera toca todos los tenants, y cualquier función que exija membresía
  —como `tenant_business_date`— lanza. La aserción no es falsa: es
  **inevaluable** ahí. Se acota al tenant del contexto o se comprueba a través
  de una función que ya lleva su propio ámbito.

## Optimizar sin `EXPLAIN` es adivinar, y adivinar en producción cuesta más que el defecto (2026-08-17)

`rank_purchase_candidates_v1` por texto libre tardaba 32 s contra su propio
`statement_timeout` de 4,5 s. Se atacó tres veces por corazonada:

1. `tenant_business_date` se evalúa por fila porque recibe una columna. Sacarla
   a un CTE **no bajó el tiempo**, y como la función exige membresía activa,
   evaluarla para todos los tenants hizo que lecturas amplias empezaran a
   lanzar 42501.
2. Acotarla derivándola del agregado obligó a materializar todo antes de
   filtrar y **rompió el camino por producto exacto**, que era el único que la
   aplicación usa y el único que funcionaba.
3. Hubo que revertir a la definición conocida-buena.

Un defecto que no afectaba al usuario estuvo a un paso de convertirse en uno
que sí. **Antes de tocar una definición compartida por rendimiento: `EXPLAIN`
primero.** El plan de este caso mostró de inmediato lo que tres intentos no
vieron — un costo estimado de 686 contra 32 s reales, estimaciones de filas
rotas, y un CTE inlineado dentro de un Nested Loop.

Y al medir, medir lo que se ejecuta: `count(*)` deja al planificador saltarse
columnas caras y da un número tranquilizador que no tiene nada que ver con la
consulta real.

La base local con datos de fixture **no reproduce** un problema de volumen:
1,5 ms contra 32 s. Una hipótesis de rendimiento que sólo se puede validar en
producción se documenta y se espera; no se despliega para ver qué pasa.

**Cómo terminó, para que la lección no quede colgando.** El `EXPLAIN` señaló la
causa real —`tenant_business_date` escaneaba `pg_timezone_names`, 1.194 filas
sin índice, en cada llamada— y el arreglo fue dejar que `at time zone` valide la
zona y capturar `invalid_parameter_value`:
`20260817130000_tenant_business_date_cheap_validation.sql`, ~67 ms → ~6 ms por
llamada. Está APPLIED y su read-back de producción pasa completo. La lección de
arriba sigue vigente; el defecto que la produjo, no.

## Un read-back que no falla antes de aplicar no prueba nada (2026-08-19)

`deploy_migration.sh` corre las verificaciones **después** de aplicar, así que
un read-back mal escrito pasa igual y firma un despliegue que nadie comprobó.
La forma barata de saber que muerde es correrlo **contra producción antes**: si
no revienta ahí, no está mirando lo que cree.

Al desplegar `20260819100000` esa comprobación encontró un read-back roto: la
firma se comparaba con `pg_get_function_identity_arguments`, que devuelve
`p_plan_id uuid, p_expected_plan_version bigint, …` —con los **nombres**— y no
`uuid, bigint, …`. Pasaba en producción por la razón equivocada y habría pasado
también sin la función. Se compara con `to_regprocedure('…(uuid,bigint,…)')`,
que resuelve la firma real o devuelve `NULL`.

> **La regla:** antes de `deploy_migration.sh`, correr cada `--verify` contra
> producción con `query.sh` y **exigir que falle**. Después, que pase. Las dos
> mitades, o el read-back es decorado.

**Y una que no hay que hacer:** el cache de esquema de PostgREST no se refresca
a mano. Producción tiene `pgrst_ddl_watch` y `pgrst_drop_watch` activos, así
que una RPC nueva queda expuesta al terminar el DDL. Compruébalo con
`pg_event_trigger` si dudas; no agregues un `NOTIFY pgrst` a la migración.

## Schema changes

One required deployable artifact: a uniquely versioned, idempotent forward
migration in `supabase/migrations/`. That standalone file owns the change.

`supabase/sql/core_schema.sql` is an optional, incomplete historical/local
reference. Mirroring a final definition there can improve search context, but
it is not required for deployment, is not a reproducible baseline, and must
never be used to decide whether a production object exists. Never delay or
reinterpret a migration because the historical guide differs.

`just db-gate` rebuilds the disposable local `public` schema from that
historical file; it does **not** replay pending standalone migrations. Running
it after applying local candidate migrations removes those definitions from the
test database. Use it only as the explicitly named legacy-fixture check, never
as a production-compatibility gate, and reapply the exact pending forward stack
before any focused contract that depends on it.

The authoritative deployment stamp is the exact version row in
`supabase_migrations.schema_migrations`, read from production after deployment.
A comment in the SQL file, a Git commit, a successful `psql` exit or a local
receipt is not that stamp. The full deployment, executable read-back, and
registration contract is in `STAGING_SUPABASE.md` ("Production change
contract"); the commands are in `SUPABASE_WORKFLOW.md` ("Authorized production
writes").

**2026-08-17 — se eliminó la separación que producía estados ambiguos.** El
repositorio todavía llamaba “canónico” a `core_schema.sql` en varios documentos
y permitía aplicar un forward file con `query.sh` para después recordar, en un
paso manual separado, verificarlo y reparar history. Eso dejó una migración del
asistente de compras correctamente probada pero sin respuesta única sobre si
estaba desplegada. Ahora `query.sh` rechaza tanto `core_schema.sql` en hosted
como una migración invocada directamente; `deploy_migration.sh` es el único
coordinador de apply → assertions → stamp → read-back, y
`migration_status.sh` consulta la autoridad remota. El receipt local ayuda a la
auditoría, pero no sustituye el stamp.

## JSONB backup redaction preserves structure and derived metadata

**2026-08-09 — supplier historical-backup gate.** Removing sensitive keys
from a JSONB snapshot is a structural rewrite, not just a security predicate.
When the payload contains arrays, expand them `WITH ORDINALITY` and aggregate
with an explicit `ORDER BY`; otherwise PostgreSQL does not guarantee that the
restored business rows retain their original order. In the same atomic update,
recalculate every payload-derived field such as `backup_size_bytes`, and make
the command result report the persisted post-redaction value rather than the
pre-redaction estimate.

The minimum regression is one sequence: dry-run identifies the exact manifest
without mutation; apply removes only the intended keys while preserving row,
array order and unrelated JSON; read-back reports zero candidates and correct
derived metadata; a second apply is a no-op with byte-identical payload and
metadata. A production gate must additionally scan the complete JSON tree
read-only, because checking only the canonical array can turn an unexpected
legacy shape into a false zero.

## Credentials

Check presence, never print values, connection strings, or credential-bearing
commands. Sources and per-consumer scope are in `SUPABASE_WORKFLOW.md`
("Credentials and what each one does"). A publishable/anon key is public client
identity and does not bypass RLS; a secret key is privileged and is never an
ordinary test identity.

## El archivo `--verify` no admite bloques ni constantes plegables (2026-08-19)

Un read-back de `deploy_migration.sh` corre por la ruta de **lectura remota**, y
ahí hay dos trampas que cuestan un intento de despliegue cada una:

- **Nada de `do $$ begin ... end $$`.** El guard de transacciones busca `begin`
  después de `;` y el bloque PL/pgSQL lo dispara: *«Remote read-only SQL files
  cannot manage transactions»*. Se escribe con `select` planos.
- **La rama que el `CASE` no toma igual se evalúa.** El planificador pliega
  constantes: `else (1 / 0)::text` revienta aunque la condición sea verdadera, y
  `'public.fn(args)'::regprocedure` revienta cuando la función no existe aunque
  ese `when` nunca se alcance. El divisor va como agregado sobre un conjunto
  vacío —`(select (1 / count(*))::text from pg_class where relname = '__x__')`—
  y la existencia de una función se resuelve con `to_regprocedure(...)::oid`,
  que devuelve NULL en vez de fallar.

Ejemplo completo: `.tmp/db/payment-level-sales-tax-readback.sql`.

**Y producción no tiene todas las migraciones del árbol.** `20260723023000`
(correcciones auditadas de pago) nunca se desplegó, así que
`sales_payment_edit_events` y `correct_sales_payment` no existen allá y una
migración que las asuma falla a medio aplicar. Antes de reemplazar una función,
compruébalo con `to_regclass`/`to_regprocedure` contra producción y haz esa
sección condicional.
