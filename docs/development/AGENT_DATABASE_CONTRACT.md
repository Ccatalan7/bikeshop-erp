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

`functions delete` cuenta como cambio destructivo del plano de control: el
wrapper lo rechaza salvo que `VINABIKE_SUPABASE_DESTRUCTIVE_CONFIRM` sea el
project ref revisado (verificado 2026-09-03 al borrar una función de prueba
propia). Un deploy no lo necesita.

**Medir una función en producción sin dejar rastro (2026-09-03):** un archivo
`begin; set local track_functions = 'all'; …; select * from
pg_stat_xact_user_functions order by total_time desc; rollback;` corrido con
`scripts/db/query.sh production --write --file` (el rechazo de `begin`/`end`
aplica a las lecturas remotas, no a `--write`) devuelve el tiempo de cada
función y trigger anidado con datos reales y no commitea nada; `explain
(analyze)` sobre el insert reparte el costo por trigger. `\timing` incluye
~200 ms de viaje por sentencia. Así se vio que el insert de `messages` cuesta
2 ms y el upkeep del binding 150–350 ms.

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

Una lectura de producción que necesita SQL dinámico (contar filas en tablas
que se leen del catálogo, por ejemplo) tampoco necesita DO: `query_to_xml`
ejecuta el texto y `xpath` saca el número, en un `select` plano
(`(xpath('/row/count/text()', query_to_xml(format('select count(*) …'), false,
true, '')))[1]::text::bigint`). Así se midió el 2026-09-29 qué borraría
restaurar un respaldo en producción, con `--max-rows 0`.

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

## Un campo nuevo en una RPC del asistente rompe su herramienta

**2026-08-24 — costo real: la herramienta de «a quién le compramos X» murió el
día entero, y el operador leía un error transitorio que era permanente.**

El Edge Function valida cada sobre con `hasExactKeys`: la fila que devuelve la
RPC tiene que traer **exactamente** los campos declarados en la lista `fields`
de `supabase/functions/_shared/ai_agent/tool_executor.ts`. Una clave de más **no
se ignora** — bota cada fila, descarta el sobre completo y sale como
`tool_source_unavailable`.

`20260824530000_cost_with_or_without_freight.sql` agregó
`averageBaseUnitCostNet` a `purchase_supplier_concentration_internal_v1`, el
motor detrás de `assistant_rank_purchase_suppliers_v1`, y la lista del ejecutor
no se tocó. Read-back: **7 de 7 llamadas correctas el 23-08, 6 de 6 caídas el
24-08**, con la base respondiendo `status: success`. El modelo reintentaba hasta
cuatro veces, quemaba medio presupuesto de herramientas y el turno moría en
`agent_budget_exhausted`; en pantalla eso es «No pude procesar esa solicitud
ahora. Intenta de nuevo en unos segundos», y reintentar no iba a funcionar
nunca.

La regla, porque es un despliegue en dos piezas y la base va primero:

- Una migración que **agrega, renombra o quita** un campo de una RPC
  `assistant_*` actualiza `fields` en la **misma tarea**. No es opcional ni
  aditivo: el validador es exacto en los dos sentidos.
- El read-back es diferencial, y se lee de la fuente, no del código:

  ```sql
  select jsonb_object_keys(
    (public.assistant_rank_purchase_suppliers_v1('camaras 29', null, null, 5))
      ->'items'->0);
  ```

  Comparado contra la lista `fields`, sobra o falta exactamente la clave
  culpable.
- Diagnóstico previo obligatorio: **llama la RPC directamente** fijando el JWT
  en sólo lectura (ver `scripts/db/query.sh production --file` con
  `set_config('request.jwt.claims', …)`). Si devuelve `status: success`, el
  defecto vive **después** de la base y perseguir al modelo es tiempo perdido.

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

## Pendiente: `complete_run_v2` rechaza a veces la respuesta final (2026-08-23)

4 corridas en toda la historia mueren con
`assistant_unavailable_complete_run_v2_rpc_invalid_response`: el turno hizo todo
—buscó, armó tarjetas, redactó— y el RPC de cierre lo rechaza. El operador lee
«no pude procesar esa solicitud», después de pagarse el turno completo.

Descartado con evidencia, para que la próxima vuelta no lo repita:

- **No son las tarjetas.** `assistant_cards_valid_v1` acepta el conjunto exacto
  que produce esa respuesta (probado con 1 a 5 tarjetas, con y sin opciones).
- **No es el largo del texto.** El runtime corta en 16 KB y el RPC admite 64 KB.
- **No es el tope de tarjetas.** Ambos lados cortan en 6.
- **No es un `$` ni un símbolo raro** en el contenido.

Queda por descartar: el cuerpo de atestación de `assistant_complete_run_v2`
—valida claves exactas— y la verificación HMAC/replay cuando dos respuestas
idénticas se cierran seguidas. Es intermitente (2 de 3 con la MISMA pregunta
repetida), lo que apunta justo ahí.

Para diagnosticarlo hace falta el mensaje real del RPC, que hoy se aplana a
`rpc_invalid_response`: ver «Una función agrupada se prueba EJECUTÁNDOLA» para
llamar el RPC con identidad en sólo lectura.

**Mientras tanto, ya no cuesta la respuesta.** `completeWithoutLosingTheAnswer`
reintenta el cierre una vez sin tarjetas: el texto ES la respuesta y las
tarjetas son atajos para abrir pantallas. Un segundo rechazo sí es terminal,
porque entonces el problema está en el contenido. Si al revisar los recibos
aparece una corrida cerrada con cero tarjetas y texto largo, ahí está la prueba
de que el conjunto de tarjetas era la causa — y con eso se cierra el
diagnóstico.

## Una función agrupada se prueba EJECUTÁNDOLA, no leyéndola (2026-08-23)

`assistant_inspect_inventory_schema_v3` quedó con una subconsulta que
referenciaba `definition.id` mientras el `GROUP BY` sólo agrupaba por
`definition.key`. Postgres **acepta el `CREATE FUNCTION`** —el cuerpo de una
`plpgsql` no se planifica hasta ejecutarse— y falla recién con el primer dato
que llega a esa rama:

```text
ERROR:  subquery uses ungrouped column "definition.id" from outer query
```

Resultado: 28 llamadas fallidas contra 5 exitosas en un día, reportadas como
`tool_source_unavailable`, en la herramienta que resuelve la categoría antes de
buscar. Nadie lo vio porque la migración se aplicó verde.

**Un read-back que sólo comprueba que la función existe no prueba nada.** Para
cualquier función con `GROUP BY`, ventanas o subconsultas correlacionadas, el
`--verify` tiene que ejecutar esa misma forma contra datos reales del tenant.

Cómo llamar a una RPC del asistente para diagnosticar, en sólo lectura:

```sql
select set_config('request.jwt.claims',
  json_build_object('sub','<uuid del usuario>','role','authenticated')::text, true);
select set_config('role','authenticated', true);
select public.assistant_<lo_que_sea>_v1('...', null);
```

Eso devuelve el error real en un segundo, en vez de tres rondas de hipótesis.

### El tope del ejecutor y el de la consulta son el mismo tope

La misma función limitaba el catálogo a 40 filas y **después** agregaba tres
campos operativos fijos: 43 ítems contra un `maxItems` de 40, así que el sobre
se rechazaba entero. Fallaba justo en las consultas amplias —«freno», «rueda»,
«piñón»—, que son las comunes. Si una función agrega filas fuera de su `limit`,
el reparto se calcula completo: 37 + 3, no 40 + 3.

## Agregar un parámetro con default NO reemplaza la función: la duplica (2026-08-22)

`create or replace function f(a, b, c, d default null)` sobre una `f(a, b, c)`
existente **no reemplaza nada**. Postgres identifica una función por su lista de
argumentos, así que quedan las dos, y desde ese instante toda llamada de tres
argumentos falla con:

```text
ERROR:  function public.f(uuid, jsonb, boolean) is not unique
HINT:  Could not choose a best candidate function.
```

No es un error de sintaxis ni aparece al aplicar la migración: aparece cuando
alguien llama. El día que pasó, la migración se aplicó y se verificó verde —el
read-back llamaba con cuatro argumentos—, y las 38 herramientas del asistente
que llamaban con tres murieron calladas. En la app se leía «La fuente autorizada
respondió como no disponible», que es honesto sobre el síntoma y no dice nada de
la causa; el diagnóstico salió de `assistant_tool_receipts`, no del mensaje.

Al cambiar la firma de una función existente, en la MISMA migración:

- `drop function if exists` la firma anterior, con sus tipos explícitos; o
- mantén el mismo número de argumentos.

Y el read-back tiene que ejercitar la firma **vieja**, no sólo la nueva: si el
llamador real pasa tres argumentos, el `--verify` que sólo prueba cuatro no
cubre nada. Ver también «Un read-back que no falla antes de aplicar no prueba
nada».

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

**2026-09-27 — una migración desplegada queda congelada byte a byte.** El
receipt guarda el SHA-256 de la migración y de cada `--verify`. Cambiar después
aunque sea el comentario `-- Deployment status` de la primera línea deja el
archivo distinto del que se aplicó, y el receipt ya no lo prueba: pasó con
`20260927030000` y lo detectó la revisión de Codex. El estado vive en
`schema_migrations` y en el receipt; una migración nueva no lleva comentario de
estado, y la de un archivo desplegado no se corrige.

**2026-09-10 — una migración que otra migración «salta» sigue pendiente, y el
cliente ya la llama.** `20260723023000_add_audited_sales_payment_corrections`
nunca se estampó; `20260819180000` redefinía `correct_sales_payment` dentro de
un `do` que, si faltaba la tabla de eventos, hacía `raise notice … skipping` y
seguía. Se desplegó verde y el módulo de pagos de venta llevó siete semanas
respondiendo `PGRST202` a cada corrección hasta que un operador lo reportó por
WhatsApp. Tres reglas que salen de ahí:

- Un `skip` guardado dentro de una migración **no** cierra la pendiente que
  esquiva; hay que dejarla registrada como bloqueo o resolverla en la misma
  ronda. `migration_status.sh` sobre el archivo viejo la sigue diciendo
  `NOT_APPLIED`; se corre para cada RPC que el cliente llama antes de dar por
  desplegada una superficie.
- El archivo viejo **no se despliega tal cual** cuando una migración posterior
  ya estampada redefine algo que él también toca: el de julio redefinía
  `validate_sales_payment_integrity()` con el cuerpo de julio y habría
  retrocedido el IVA por medio de pago del 19-08. Se escribe un forward nuevo
  con los cuerpos finales, se afirma en un `do` previo que lo que no se toca ya
  está en su versión final, y el archivo viejo queda marcado `SUPERSEDED` en su
  cabecera (no está aplicado, así que editar el comentario no rompe historia).
- Local no representa a producción en ninguna de las dos direcciones: tenía
  los objetos de julio (por `core_schema.sql`) y no tenía los cuerpos de
  agosto. Antes de un pgTAP que dependa de la función, reaplicar en local el
  stack pendiente real (`query.sh local --write --file` del 0819) y comprobar
  con `pg_get_functiondef` que el cuerpo es el de producción.

El read-back tuvo su propia trampa: `pg_get_triggerdef` imprime los eventos en
orden canónico (`BEFORE DELETE OR UPDATE`), no en el orden del `create
trigger`. Un `like` con el orden del archivo divide por cero en local aunque
el trigger exista.

## Antes de un recorrido local, comparar su camino con producción (2026-09-30)

Un recorrido por la app contra la base local prueba lo que corre **en local**.
El 2026-09-30, antes del C1/C4 del taller, `just db-drift local production` y
una comparación de `md5(pg_get_functiondef)` sobre cada función del camino
del recorrido encontraron dos cosas que ninguna prueba había visto:

- **Faltaba el motor de fichas entero**, aunque sus consumidores estaban: los
  pgTAP de cambio de partes reemplazan el lector y pasaban. Instalación y lista
  exacta: `docs/development/product-specs-research-2026-09-05/local-engine-restore-2026-09-16.md`.
- **El cierre de un trabajo no era el de producción.** El
  `handle_mechanic_job_change` de `core_schema.sql` descuenta stock y crea el
  asiento al pasar a EN_CURSO/FINALIZADO; el de producción calcula esas
  banderas y nunca las ejecuta. El cuerpo no tenía dueño en el repositorio
  al detectar la diferencia. `20260930152000_capture_workshop_job_lifecycle.sql`
  lo captura ahora sin cambiar el comportamiento, APPLIED a 15:34:04 UTC;
  el readback compara definición normalizada, ACL y dos triggers. Otros dos cuerpos del mismo
  camino estaban atrasados (`normalize_mechanic_job_lifecycle_timestamps`, de
  `20260805210000`, y `create_mechanic_job_erp_notification` con su trigger, de
  `20260817170000`). Local se alinea con
  `supabase/tests/fixtures/job_lifecycle_production_local_seed.sql`, copia
  verificada por md5 de producción. El forward captura exactamente el cuerpo
  ya ejercido en ese seed; una corrección local por sí sola no lo reconstruye.

La regla: para cada comando y disparador que el recorrido ejerce, cuerpo local
= cuerpo de producción por md5, o la diferencia queda explicada antes de
compilar. Los comandos del taller (`save_bike_aggregate`,
`create_mechanic_job_v1`, `save_mechanic_job_lines_v1`,
`transition_mechanic_job_status`, `smart_task_create_v1` y toda la puerta de
cambio de partes) ya eran idénticos; sólo el cierre heredado difería.

**2026-10-01, otra diferencia del mismo tipo:** el
`sync_job_items_to_invoice_statement` local era el back-sync de antes del
2026-03-19 (activo); en producción es un no-op. Una prueba de líneas del
taller en local reescribía la factura y en producción no. Se alineó local
reaplicando `20260319_disable_job_items_invoice_backsync.sql`.

## Un pgTAP rojo en local no es tuyo hasta compararlo sin tu cambio (2026-10-01)

Con la primera versión de `20261001200000` aplicada, 20 archivos del taller
salieron rojos. Sin la
migración (deshecha sólo en local con un script inverso), los mismos 18
fallaban en las mismas pruebas: fixtures que ya no cumplen una FK
(`mechanic_jobs_created_by_fkey`), `update_workshop_supply_need_v1` ausente en
local, un `job_subjects` duplicado. Los dos de verdad nuevos eran los que
describían la regla vieja. El método: correr los mismos archivos sin el
cambio y comparar número de prueba por número de prueba. Ojo con resumir el
log con `grep -v "Failed: 0"`: un archivo que muere antes de su plan sale con
`Tests: 0 Failed: 0` y queda fuera del filtro; se leen todas las líneas
`Wstat`.

**Ampliado el 2026-10-01, con la suite completa.** Lo que `just db-test`
imprime al fallar son las últimas 120 líneas: con 261 archivos, el resumen
queda cortado y una comparación hecha sobre esa cola pierde archivos (la
primera, con `20261001190000`–`200000`, dio un «archivo nuevo en rojo» que no
lo era). El log entero queda en `.tmp/db/pgtap-<fecha>-<hora>.log`; se compara
ése. Cuando el cambio es el cuerpo de funciones, «sin el cambio» se arma sin
escribir a mano un inverso: se leen los cuerpos de producción con
`pg_get_functiondef` por `query.sh production --format json`, se aplican en
local en una transacción, se corre la suite, y se reaplican las migraciones
(por eso tienen que ser idempotentes: un `create function` sin `or replace`
lo impide). Ese día, 110 de los 261 archivos estaban rojos en local por la
deriva conocida, idénticos prueba por prueba con y sin el cambio. Y
`query.sh <entorno> --file` exige que el archivo termine en `;`: sin él, el
`rollback` que agrega para la lectura sale como `syntax error at or near
"rollback"`.

## Una reparación por heurística corre una vez, cuando reemplaza al escritor roto (2026-10-01)

`20261001200000` pasa a su bici las líneas de General que parecen de la bici
(servicios, «Componentes», «Servicio»). Eso vale para lo que dejó la
sincronización vieja; después del arreglo, un componente en General puede ser
una compra aparte, y la regla de «migración idempotente» hacía que volver a
correrla lo moviera (revisión de Codex). La marca es el cuerpo exacto del
escritor roto: antes del paso que lo reemplaza, una tabla temporal `on commit
drop` guarda si `md5(prosrc)` es el de producción antes del cambio, y la
reparación sólo corre si lo es. Un recálculo puro (subtotales, espejos de la
factura) sí se repite sin marca. Y el read-back no puede exigir «ninguna
línea queda así»: eso es lo que hizo la migración, no una regla del sistema;
va como columna informativa.

Para probar una reparación sobre un estado viejo, ese estado se siembra con
`set local session_replication_role = replica`. Con los disparadores vivos,
vincular la factura al trabajo corre la factura → el trabajo, que reescribe
líneas y espejos, y una factura `paid` sin pago vuelve a `confirmed`: el
fixture deja de parecerse a producción (costó dos corridas). Se agrega un
control: sin la marca de la sincronización, la guardia de lo pagado sigue
rechazando el mismo cambio.

## Un disparador nuevo en una tabla del respaldo del taller se registra en la recuperación (2026-10-01)

`workshop_restore_effects_review_internal` rechaza la recuperación
(`unreviewed_effect`) si una tabla del respaldo tiene un disparador de INSERT
que no está en `workshop_restore_trigger_review_internal`. Un disparador nuevo
—también uno de UPDATE que incluya INSERT— se crea con exactamente
`when (not public.workshop_restore_effect_suppressed('public.<tabla>'::regclass, '<nombre>'::name))`
(sin otras condiciones: la revisión compara el texto que imprime
`pg_get_triggerdef`) y se agrega al registro renombrando la función y
uniéndola, como `20260930181000`. Con eso la recuperación lo apaga y devuelve
las filas tal como se respaldaron. El read-back de cada migración fija los
totales (30/12 en `181000`). Se probó con una primera versión de
`20261001200000` que agregaba dos disparadores; el dueño la corrigió y esa
versión no se desplegó.

## Borrar un cliente borra sus bicis y sus trabajos (2026-10-03)

`DELETE FROM customers` no se detiene ante la actividad del cliente: las
llaves foráneas **borran en cascada** `bikes`, `mechanic_jobs`, `vehicles`,
`customer_addresses` y la fidelización, y **dejan en NULL** el cliente de
`sales_invoices`, `orders`, `online_orders`, `smart_tasks` y
`whatsapp_conversation_bindings`. La lista de clientes antigua ofrecía
«Eliminar» en cada fila con una confirmación, así que un clic podía llevarse
las bicis y los trabajos de un cliente y dejar sus facturas sin dueño. Desde
este día la app sólo ofrece eliminar en la página del cliente y sólo si no
tiene bicis, trabajos ni facturas.

**Desde `20261003220000` la base lo impide** (`trg_guard_customer_delete_activity`,
BEFORE DELETE): borrar un cliente con bicis, trabajos —también uno con
`deleted_at`—, vehículos, facturas o pedidos falla con `customer_has_activity`
(SQLSTATE 23503, PostgREST 409; el detalle dice qué tiene), venga de la app,
de SQL o de otra función. Revisar primero y borrar después, en dos consultas,
**no** bastaba: la primera versión de la app lo hacía así y Codex mostró la
ventana; se reprodujo en local con dos sesiones (una bici confirmada 50 ms
antes del borrado se fue en la cascada) y con la guardia el borrado espera a la
bici, la ve y se niega. Funciona porque Postgres bloquea la fila antes de un
BEFORE DELETE y la llave de la fila hija pide `FOR KEY SHARE` sobre ella. El
borrado en cascada desde otra tabla (`tenants`) pasa por
`pg_trigger_depth() > 1`. `sales_orders` y `work_orders` no tienen acción y su
propia llave ya devuelve 23503. En local `sales_orders` sí borra en cascada y
`work_orders` no existe: el `--verify` de la llave sólo se cumple en producción.

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

## La CLI sin sesión no deja registrar la versión: el registro va por el wrapper (2026-10-06)

`deploy_migration.sh` aplicó y verificó `20261006090000` en producción y falló
al registrar: `migration repair` respondió `FGA Authentication Error.
Unauthorized`, y lo mismo `projects list` y el conector MCP de Supabase.
La página de estado de Supabase estaba en verde: es la autorización de la
cuenta (el token de la CLI y el del conector), no una caída. El
`just db-preflight` lo dice antes: «CLI authentication missing or invalid».

La migración ya estaba en producción y verificada. Registrar esa versión exacta
es autónomo, y es una fila: `version`, `name` (el nombre del archivo sin la
versión) y `statements`. La CLI guarda en `statements` cada sentencia
separada por los `;` de nivel superior, con sus comentarios delante y sin el
`;`. Se escribe esa misma fila con `query.sh production --write` (las
sentencias entre comillas de dólar propias) y se confirma con
`migration_status.sh` → `APPLIED`. Esto **no** sirve para registrar una versión
que no se aplicó y verificó: eso sigue siendo una reparación que decide el
dueño.

Lo que la CLI sin sesión sí deja fuera es el plano de control (desplegar
funciones Edge, secretos): eso necesita volver a iniciar sesión en la cuenta.

## Insertar una tienda cambia el sujeto de la petición (2026-10-06)

En un sembrado o un pgTAP, `insert into public.tenants` deja el id de la
tienda en `request.jwt.claim.sub`. Si después se inserta un producto con
`tax_rate`, el disparador de la clasificación de IVA registra a `auth.uid()`
como autor y la llave a `auth.users` falla con el id de la tienda. Los
`set_config` del autor van **después** de crear la tienda. Una tienda nueva
nace además con ajustes por defecto (`site_title`…): los de la prueba van con
`on conflict (tenant_id, key) do update`.

## Cloud sessions: the wrapper cannot reach production, the Supabase MCP can

**2026-09-15, decisión del dueño.** A Claude Code session running in the
cloud (claude.ai/code) has no keychain, no `SUPABASE_DB_PASSWORD`, no Supabase
CLI, and its network policy blocks TCP 5432/6543 to
`aws-1-sa-east-1.pooler.supabase.com` (`pg_isready` gets no response). The
wrapper is therefore unusable there, and a CPU alert stayed undiagnosed for a
round because the agent reported "no credentials" instead of using an
integration. The owner's instruction: «dime cuál es la mejor integración de
Claude con Supabase y configurémosla, no seas limitado».

The accepted path for cloud sessions is the official Supabase MCP connector,
scoped to the production project and read-only:

```
https://mcp.supabase.com/mcp?project_ref=xzdvtzdqjeyqxnkqprtf&read_only=true
```

added in claude.ai → Settings → Connectors → *Add custom connector*, then
authorised with the owner's Supabase login. The owner connected it on
2026-09-15 and the session found it **writable** (`create temp table`
succeeded), so `read_only` is not something to rely on blindly: probe it, and
behave as read-only unless the task is an implementation/fix with the owner's
go-ahead. The connector does not carry the wrapper's journal, row cap, or
sensitive-column guard: name the columns you need, never star-project a table
listed in `scripts/db/sensitive_tables.txt`, add `limit` to every
row-returning query, and keep results out of committed files. Governed
migrations still go through the wrapper from a machine that holds the
credential; a live emergency fix applied through the connector (2026-09-15:
one `create or replace function` that stopped a 900-request/s retry storm) is
recorded as a migration file in the same task and read back live, exactly as
a wrapper write would be.

**Governance gap found the same day.** A cloud session clones the default
branch, `main`, which on 2026-09-15 was 94 commits and five weeks behind the
working branch `smartpegas1.0`; and the working branch itself was eight days
behind the Mac checkout: the function burning the instance had been pushed
(`20260829160000_supply_need_refinement_modes.sql`, on `smartpegas1.0`), but
the twenty migrations deployed to production between 2026-09-08 and
2026-09-15 existed only on the Mac until the owner's local session committed
them that afternoon. Two rules follow. A cloud session fetches
`origin/smartpegas1.0` (until `main` is the working line, see
`docs/runbooks/MAIN_BRANCH_CUTOVER.md`) before claiming that anything is
absent from the repository. And a deploy through the guarded wrapper is not
finished until its migration file is pushed: production must never be ahead
of `origin`.

**El Mac también pierde el pooler, y vuelve solo (2026-10-08).** En una ronda
de mensajería `query.sh production` se quedó colgado sin error durante cerca de
una hora: el pooler de `sa-east-1` no contestaba desde la red del Mac, con la
credencial y la CLI en orden. No es un problema de sesión: las lecturas
siguieron por el conector MCP (con las reglas de arriba) y la migración esperó.
Al volver la red, el `--verify` falló antes de aplicar como debía y el despliegue
salió entero por `deploy_migration.sh`. Una escritura no se adelanta por el
conector por esta causa: se espera y se reintenta el wrapper. Y en zsh de este
Mac no existe `timeout`; un `timeout 60 query.sh …` no corre nada y no imprime
nada, que se lee igual que el cuelgue.

## Credentials

**Formato de resultados (2026-09-15).** `query.sh --format json` envuelve la
consulta completa en una subconsulta. Un archivo local con `BEGIN`, fixtures y
`ROLLBACK` debe usar el formato table predeterminado, no JSON; no es un fallo
del candidato. Evita también llamar `result` a una columna de salida JSON:
coincide con el alias del wrapper y PostgreSQL puede serializar esa columna
directamente en lugar de la fila. Usa un nombre explícito como `readback` y
comprueba la forma devuelta antes de consumirla. Estos dos supuestos causaron
un ensayo local fallido y una preparación detenida; ninguna escritura llegó a
producción por esos intentos.

Check presence, never print values, connection strings, or credential-bearing
commands. Sources and per-consumer scope are in `SUPABASE_WORKFLOW.md`
("Credentials and what each one does"). A publishable/anon key is public client
identity and does not bypass RLS; a secret key is privileged and is never an
ordinary test identity.

## Tres trampas de una migración de catálogo grande (2026-09-16)

Salieron del bloque 1 de carga residual (487 políticas reescritas, 44
cambios de índices), y cada una costó una pasada:

- **Postgres deparsea `(select f())` como `( SELECT f() AS f)`**, en
  mayúsculas y con alias. Un read-back que busque «llamada sin envolver» con
  `~ '(?<!select )…'` cuenta como sin envolver todo lo que acaba de envolver;
  en local dio 426 «pendientes» tras una migración correcta. Se compara con
  `~*` (o con `lower()`), y el generador que envuelve también ignora
  mayúsculas para no envolver dos veces.
- **Cada sentencia por el pooler cuesta ~200 ms de viaje.** 550 `ALTER
  POLICY` sueltos dentro de una transacción son ~110 s con ACCESS EXCLUSIVE
  sobre ~290 tablas. Se agrupa cada sección en un `do $block$ … end $block$`
  con `execute $ddl$ … $ddl$` por sentencia: un viaje por sección, la
  transacción dura segundos y `lock_timeout = '5s'` sigue cubriendo la
  espera. El archivo sigue siendo legible sentencia por sentencia.
- **Un índice único sin constraint no tiene «constraint propio».** Al contar
  `pg_constraint.conindid = <índice>` para afirmar cuántas FKs cuelgan de un
  índice, un `uq_*` creado con `create unique index` cuenta sólo FKs (17),
  mientras que su gemelo `*_key` creado con `unique (…)` cuenta 1 propio más
  las FKs. Restarle «uno» a todos por igual hizo fallar el read-back después
  de aplicar; el deploy quedó aplicado sin stamp y se cerró en una segunda
  pasada idempotente. Leer `contype` antes de escribir el número.

## Una función nueva nace con `service_role`, y un pgTAP ordenado compara con ICU (2026-09-16)

Supabase declara `alter default privileges in schema public grant all on functions to
anon, authenticated, service_role`. Cada función que una migración crea nace con esos tres
grants **explícitos**; `revoke all … from public` no toca ninguno. La fachada
`get_public_product_facets_v2` pasó la revisión de lectura y falló el pgTAP de fachadas
públicas (`service_role` seguía con EXECUTE): costó una corrida y una reaplicación local.

- Toda migración que cree una función escribe primero
  `revoke all on function … from public, anon, authenticated, service_role;` y después el
  `grant execute … to …` que corresponde (patrón de `20260722200000_add_public_catalog_facets.sql`).
  Un núcleo privado llamado desde una fachada `security definer` no lleva grant alguno.
- En pgTAP, un `order by` sobre texto usa la collation ICU de la base: la puntuación se ignora
  en el primer nivel y `spec:x_len` sale antes que `spec:x:`. Cuando el orden de un
  `results_eq` importa, `order by columna collate "C"` en ambos lados; la expectativa entonces
  vale en local, en CI y en producción.

**Un pgTAP no borra de `storage.objects` sin la marca de la API (2026-09-29).** El
disparador `storage.protect_delete` rechaza un `delete` directo («Direct deletion from
storage tables is not allowed»), también como `postgres`, y la prueba se corta ahí sin
plan. La API de Storage borra con `select set_config('storage.allow_delete_query', 'true',
true);` dentro de la transacción; la prueba hace lo mismo. Estaba sólo en un comentario de
`workshop_command_outbox.sql` y costó una corrida en `managed_image_urls_exist.sql`.

**Con las tablas pasa lo mismo, y los privilegios son siete (2026-09-29).** Una tabla nueva
nace con todos para `anon` y `authenticated`. `revoke select, insert, update, delete` deja
TRUNCATE, REFERENCES y TRIGGER, y el RLS no cubre TRUNCATE. Así nació
`mechanic_job_creations` (recibos del alta). Su read-back miraba sólo los cuatro de siempre y
pasó; lo encontró la revisión de Codex. Una tabla que la API no toca lleva
`revoke all on … from public, anon, authenticated`. Su verificación recorre los siete con
`has_table_privilege` (patrón en
`supabase/manual_checks/verification/20260929010000_create_mechanic_job.sql`).

## Un trigger diferido se prueba nombrándolo, nunca con `set constraints all` (2026-09-26)

Un pgTAP corre en una transacción que nunca hace commit, así que un `constraint trigger …
deferrable initially deferred` no dispara solo: hay que forzarlo con `set constraints`.
`set constraints all immediate` fuerza **todos** los diferidos pendientes de la base, también
los de identidad de otros módulos. La sincronía de cuentas de `smart_tasks` lo usó y
`link_erp_user_to_employee` cayó con `employee_erp_link_inconsistent` a mitad de la fixture,
un falso rojo que costó una ronda de diagnóstico.

- Se nombran sólo los triggers bajo prueba, y se devuelven a diferidos enseguida:
  `set constraints trg_a, trg_b immediate; set constraints trg_a, trg_b deferred;`, dentro
  de un ayudante `pg_temp` que simula el commit (patrón `pg_temp.commit_sync()` de
  `supabase/tests/smart_task_employee_assignee.sql`).
- La verificación `--verify` de un trigger así afirma `tgdeferrable`/`tginitdeferred` y
  `tgenabled in ('O','A')`: un trigger en modo `R` (réplica) existe, pero no dispara en
  una sesión normal.

## Antes de llevar un efecto de la app a un comando, mira los triggers de la tabla (2026-09-28)

Lo que la app hacía «después de la respuesta» se pierde cuando otro confirma el comando (la
bandeja tras un reinicio, la consulta del recibo), y la corrección natural es meterlo en el
comando. Antes de escribirlo, lista los triggers de cada tabla que el comando escribe
(`select tgname, pg_get_triggerdef(oid) from pg_trigger where tgrelid = '<tabla>'::regclass
and not tgisinternal`): puede que la base ya lo haga. `trg_auto_parse_item_description`
(AFTER INSERT en `mechanic_job_items`) creaba las tareas de cada línea del catálogo desde su
descripción, y la app las volvía a crear con otra regla: 32 nombres repetidos en 8 líneas de
producción. La primera corrección del comando de líneas agregó una tercera copia; su pgTAP
pasaba porque la línea de prueba no tenía `product_id` y el trigger no la tocaba. El dueño es
el trigger; se quitan las copias y la prueba usa una fila que sí lo dispara.

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

## Una vista `_metrics_` puede tener una fila por producto, no por par (2026-08-23)

`purchase_candidate_metrics_v1` parece el sustrato natural para «a quién le
compramos esto»: trae `supplier_id`, `supplier_name`, `purchase_count`,
`purchased_units` y costo aterrizado. **Tiene una fila por producto**, no una
por producto×proveedor —medido: 267 filas, 267 productos distintos, 12
proveedores—, así que agregar por proveedor ahí le atribuye TODA la historia de
un producto a su último proveedor.

El hecho es la línea: `purchase_line_landed_cost_observations_v1`, que además
prorratea el flete (`landed_unit_cost_net`). Comparar por precio unitario base
premia al importador barato contra el distribuidor local por una diferencia que
el flete se come.

Antes de agregar por una dimensión, comprueba la granularidad real con
`count(*)` contra `count(distinct <dimensión>)`. El nombre de la vista no la
declara.

### Un forward que agrega una clave ajena tiene que poder volver a correr

Una `foreign key` compuesta cuelga del índice único al que apunta, así que un
`drop constraint if exists` sobre ese índice falla mientras la clave ajena
exista. Si el forward crea las dos, retira **primero** la clave ajena y después
el índice; si no, el archivo se aplica una vez y falla en el segundo intento
—que es exactamente lo que pasa al probarlo en local antes de desplegarlo—.
Costó dos vueltas el 2026-08-31.

## Producción tiene un arreglo a mano que el repositorio no tiene (2026-09-02)

`public.auto_update_purchase_list_on_invoice_status()` difiere entre producción
y lo que generan las migraciones: producción envuelve el `product_id` con
`nullif(…, '')::uuid` dentro de un `begin … exception` y las migraciones
siguen con el cast directo. La batería local completa (`just db-gate`, 173
archivos) muere por eso en `supplier_relationship_foundation.sql`, prueba 38
(`invalid input syntax for type uuid: ""`), **antes** de llegar a cualquier
bloque que se agregue al final de ese archivo. Un bloque nuevo ahí no se
ejecuta y su verde es mentira.

Mientras el arreglo no vuelva al repositorio como migración, un comando nuevo
se prueba en **su propio archivo pgTAP** con sus propias fixtures y
`request.jwt.claims` en `service_role` (ver
`supabase/tests/supplier_sales_rep_command.sql`), y se corre solo con
`just db-test <archivo>`. Ojo: `db-gate` reconstruye local desde las
migraciones pero no siempre deja aplicada la última recién escrita (dijo
«historical fixture hash unchanged» y la función no existía); comprobar con
`to_regprocedure` y, si falta, aplicarla en local con `query.sh local --write
--file`.

Quien tome el arreglo del trigger: escribir la migración con la versión de
producción (`pg_get_functiondef` en `production` es la fuente), no la copia
local.

## Un comando que escribe la tabla directo puede estar muerto desde que nació (2026-09-17)

**Costo real: una función del ERP que nunca funcionó y nadie había reportado.**

`Agregar imagen…` en la ficha del proveedor fallaba siempre con
`PostgrestException(message: permission denied for table suppliers, code:
42501)`. La causa no era RLS —una política que niega contesta *«new row
violates row-level security policy»*— sino la **ausencia de grants**: el rol
`authenticated` no tiene ningún privilegio sobre `public.suppliers`, ni
`UPDATE` ni `SELECT`. Todo lo que el cliente hace con proveedores va por RPC
`security definer`; ese comando era el único del módulo que intentaba
`.from('suppliers').update(...)`, y por eso era el único roto.

Lo que queda:

- **Antes de escribir una tabla desde el cliente, mirá los grants, no las
  políticas.** `select grantee, privilege_type from
  information_schema.role_table_grants where table_name = '<tabla>'`. Si
  `authenticated` no aparece, esa tabla no se toca desde la app: tiene una RPC,
  o hay que escribirla.
- **El vecindario manda.** Si los comandos hermanos del mismo gateway van por
  RPC y uno va por tabla, ese uno está mal, aunque compile y aunque nadie se
  haya quejado. Los 42501 sólo aparecen cuando alguien usa la función.
- **Una RPC nueva nace con el grant por defecto de `public`.** Se retira y se
  entrega explícito (`revoke all … from public; grant execute … to
  authenticated, service_role`), y el read-back lo comprueba con
  `has_function_privilege` para los dos roles —el que debe y el que no—.

El read-back también afirma lo que **no** cambió: que `authenticated` sigue sin
poder escribir la tabla directo. Una migración que abre la puerta que intentaba
forzar el cliente arregla el síntoma y pierde el aislamiento.

## `create or replace view` borra las `reloptions` (2026-09-17)

**Costo real: una vista quedó sin `security_invoker` en producción, entre el
apply y el read-back.**

Agregar una columna a `supplier_profile_read_model` con `create or replace view
… as select …` aplicó bien la columna **y dejó `reloptions` vacío**: la vista
pasó de `security_invoker=true` a ejecutarse con los permisos de su dueño, que
es exactamente lo contrario de lo que esa vista necesita. No hay aviso; hay que
volver a declararlo:

```sql
create or replace view public.<vista>
with (security_invoker = true) as
  select …;
```

Dos cosas que sí funcionaron y conviene repetir:

- **El read-back lo atrapó.** La aserción afirmaba lo que no debía cambiar —que
  la vista sigue siendo invoker y que `authenticated` la sigue leyendo—, no sólo
  que la columna nueva existiera. Un read-back que sólo comprueba lo agregado
  habría dejado el agujero abierto y sellado la migración.
- **`create or replace` sólo agrega columnas al final.** La columna nueva va
  después de la última; reordenar o insertar en medio exige `drop view`, que se
  lleva los grants y las dependencias.

## Un relleno masivo desde fuera se mira antes de escribirlo (2026-09-17)

Rellenar `suppliers.image_url` con el icono que publica cada sitio dejó 27 filas
nuevas en producción. Lo que evitó los peores errores no fue el código: fue
**montar las 27 imágenes en una hoja de contacto y mirarlas** antes del
`update` —aunque mirarlas **no bastó**; ver la corrección de abajo—. Tres cosas
que sólo se ven mirando, y que ninguna validación de tamaño o de tipo habría
detenido:

- **El favicon puede ser el de la plataforma, no el de la marca.** `cge.cl`
  servía la W de WordPress en 80×80: un PNG válido, del dominio correcto, y
  completamente equivocado como logo de CGE.
- **`qlmanage` convierte un SVG roto en un PNG perfectamente válido.** El de
  AliExpress no parseaba, y Quick Look rindió *el mensaje de error* en 512×512.
  Pasó el filtro de dimensiones y de formato; se cayó al verlo.
- **Un logotipo claro sobre fondo transparente desaparece.** Se compone sobre el
  fondo que lo deja ver —la luminancia media de lo opaco decide blanco u
  oscuro—, no sobre el que uno supuso.

Dos notas de herramienta para la próxima:

- **`supabase storage cp` sube al bucket**, con `--experimental`, y resuelve el
  proyecto **desde el directorio de trabajo**: corriéndolo fuera del repo
  contesta `LegacyProjectNotLinkedError` aunque el enlace exista. Es el camino
  para subir un archivo sin service-role key, y deja el objeto donde la app ya
  los pone (`vinabike-assets/suppliers/<tenant>/<supplier>/`).
- **Después del `update`, comprobar que cada URL guardada responde una imagen.**
  Una fila con una URL muerta se ve igual que una fila sin imagen hasta que
  alguien abre la pantalla. Un `HEAD` por fila cuesta segundos.

### Corrección (2026-09-17, misma tarde): el favicon no es el logo de la marca

La pasada de arriba **no quedó correcta**. El dueño la rechazó al verla en el
directorio: de las 28 imágenes, 12 eran favicons de 32 a 64 px que se
desarmaban al agrandarlos, la de Andes Industrial eran barras blancas
ilegibles, y la de **Pullman Cargo era la «S» de Svelte** —el favicon por
defecto del framework del sitio—, que pasó la hoja de contacto. Hubo que
rehacer 14 y buscar desde cero las demás.

**Causa:** la hoja mostraba *un* candidato por proveedor, sin nada al lado con
qué compararlo. «¿Es esta la marca de Pullman?» no se contesta mirando una
imagen sola; se contesta al ponerla junto al logo del encabezado del sitio y al
avatar de su página, donde la ajena salta a la vista. La hoja de revisión se
arma **por proveedor, con todos los candidatos en una fila**.

Dónde está el mejor candidato, en el orden en que rindió (91 proveedores, 53
con imagen al cerrar; los 38 restantes son personas o comercios sin ninguna
imagen propia publicada):

1. **El avatar de su página de Facebook.** Es el cuadrado que la marca misma
   eligió para verse chica, casi siempre a 720 px:
   `https://graph.facebook.com/<página>/picture?type=large&width=720&height=720`,
   sin token, para páginas públicas. La `<página>` se saca de los enlaces a
   `facebook.com/…` del propio sitio, no se adivina. Un nombre de página que no
   existe responde **HTTP 400**; una página sin foto responde **200 con la
   silueta gris genérica** en 720×720 —una imagen válida que hay que descartar
   comparándola con la silueta conocida—.
2. **Lo que el sitio declara:** el `<img>` del encabezado cuyo `src`, `alt` o
   `class` dice *logo*, el `og:image`, los íconos del `manifest` y el
   `apple-touch-icon`. El favicon va al final.
3. **Wikimedia Commons** para las marcas nacionales grandes cuyo sitio bloquea
   bots (Copec, Esval, SII tienen su SVG oficial): la API de búsqueda en el
   espacio `6` y `imageinfo` con `iiurlwidth`, siempre con `User-Agent`.
4. **Instagram**, para el comercio que sólo existe ahí: su API contesta 401 sin
   sesión; el navegador integrado sí muestra la foto de perfil, a 150 px, con
   una URL firmada del CDN que se descarga sin cookies. **Nunca se inicia
   sesión.**
5. **Una marca corta que sólo se publica como favicon de 32 px** (la A de
   Atletis, la B de Blue Express) se recorta del logotipo grande, por
   **componente conexo** y no por caja fija: en una tipografía itálica las
   letras se montan y una caja arrastra la vecina.

Y al reemplazar, la fila cambia sólo si su imagen sigue siendo la leída antes
de subir (`where image_url = '<leída>'`, o `is null`): si el dueño cambió una a
mano entretanto, el relleno no se la pisa.

Nota de herramienta: **Pillow está en `/usr/bin/python3`** (10.4), no en el
Python de Homebrew; y **`qlmanage -t -s 1600 hoja.html`** rinde a PNG una hoja
de revisión HTML con imágenes locales, que el navegador integrado sólo muestra
como instantánea estática, sin captura posible.

## Unificar proveedores duplicados sin perder nada (2026-09-18)

Tres pares de fichas duplicadas —«garozzo»/«Bicicletas Garozzo»,
«Transvayve»/«Transportes Vayve», «Pernos y Gomas»/«Comercial Gomas y
Pernos»— se unificaron con la instrucción del dueño «que no se pierda nada».
Lo que hace falta saber para repetirlo:

- **Primero se mide lo que cuelga de cada ficha, en todas partes.** Hay 49
  claves foráneas hacia `suppliers` (algunas `on delete restrict`, otras
  `cascade`: borrar arrastraría roles, contactos y credenciales) y además
  referencias **sin** clave foránea: `conversations.context_id`,
  `conversation_contexts.context_id`, `app_files.context_id`,
  `erp_notifications.entity_id` y la identidad en `external_parties` (mismo id
  que el proveedor) con sus `external_party_identifiers`. La consulta de conteo
  se arma de las dos listas y se corre **antes y después**: tiene que dar lo
  mismo fila por fila.
- **Se desactiva, no se borra.** La ficha retirada queda `is_active = false`
  con una nota que nombra a la que la absorbe; la sobreviviente guarda su
  nombre como alias y su ID de Zoho en la nota. El trigger
  `prepare_supplier_external_party` refleja `is_active` en `external_parties`
  solo, así que un `update` directo de `suppliers` deja las dos tablas
  coherentes. Si la retirada tuviera movimientos, se re-apuntan antes; estas no
  tenían ninguno, y los datos bancarios y la plantilla OCR estaban vacíos en
  las seis.
- **No usar `save_supplier_relationship_profile` para un cambio parcial.** Es
  un comando de ficha completa: los campos del perfil sólo cambian si vienen en
  el JSON, pero roles, capacidades y etiquetas **se reemplazan enteros** con los
  arreglos que se le pasen —un arreglo vacío los borra—.
- **Ensayo con `rollback` y aserciones al final.** El archivo termina con un
  `select 1 / (case when <estado final esperado> then 1 else 0 end)` por
  bloque: si una fila no quedó como se esperaba, la división por cero aborta la
  transacción entera. Cada `update` va guardado por el `updated_at` leído, para
  no pisar una edición hecha entretanto.
- **El buscador global también tiene que saberlo.** No leía `aliases` ni
  marcaba inactivos; tras unificar, «transvayve» sólo encontraba la ficha
  retirada. Ver la fila del buscador en `canonical-ui-surfaces.md`.

## Un asiento se prueba en los dos sentidos (2026-09-19)

`post_journal` de la conciliación bancaria escribía sus dos líneas eligiendo
el monto por dirección dos veces, y para la plata que **sale** dejaba la
cuenta al Haber y el banco al Debe. Nació el 2026-08-14 con un pgTAP que sólo
clasificaba un **abono**; el primer «Aplicar» real (13 cargos, $31.443) dejó el
banco $62.886 por encima de la cartola hasta que la migración
`20260919100000` corrigió el kernel y los asientos. Toda función que escribe
un asiento contra el banco se prueba con un movimiento de entrada **y** uno de
salida, afirmando la cuenta y el lado (`account_code, debit, credit`), no sólo
que cuadre: un asiento al revés también cuadra. Y después de la primera
escritura real se lee de vuelta el lado de la línea del banco contra el
sentido del movimiento.

## Dos trampas de PL/pgSQL y pgTAP que costaron una corrida (2026-09-19)

- **Un `record` sin asignar revienta aunque su rama no corra.**
  `case when v_journal_id is null then '{}' else jsonb_build_object('id',
  v_account.id) end` falla con `record "v_account" is not assigned yet` cuando
  el bloque que llena `v_account` no se ejecutó: PL/pgSQL resuelve los campos
  del record al preparar la expresión. El jsonb se arma dentro del `if` que
  asignó el record. Lo detectó `bank_reconciliation_pays_payroll.sql`, no la
  prueba nueva: por eso se corren todas las pruebas de la función que se tocó.
- **Una escritura y una lectura `stable` en la misma sentencia no se ven.**
  `select ok((guardar_borrador(...))->>'revision' = '3' and (select ... from
  listar(...)))` lee la lista con la foto de antes de guardar. Se escribe en
  una sentencia y se afirma en la siguiente.
- **Una guardia nueva en un kernel se prueba con todos sus llamadores.** El
  tope de $1.000 para vínculos `manual` (`20260919110000`) pasó las nueve
  pruebas `bank_*` y rompió las liquidaciones de tarjeta: el adaptador de
  terminales llama al mismo kernel y envía sus estimaciones como `manual`.
  Su prueba (`payment_terminal_settlement_accounting.sql`) no tiene el
  prefijo. Lo encontró la revisión de Codex; estuvo una hora en producción.
  Antes de desplegar se corren **todas** las pruebas que nombran la función:
  `grep -l <función> supabase/tests/*.sql`.

## Una alternativa que puede dar nulo abre un `if not (…)` (2026-09-28)

`if not (regla_vieja or f(x) @> y) then raise` deja pasar **todo** lo que
debía rechazar cuando `f` devuelve nulo: `false or null` es `null`,
`not null` es `null` y un `if null` no entra. Pasó al agregarle al parche de
la ficha (`20260928100000`) la prueba de un repuesto como segunda
alternativa: con las líneas del Enrayado, `job_line_part_change_internal`
es nulo y el parche aceptó «32H» de una línea que armó 28H. Lo atraparon las
pruebas viejas (`bike_technical_fact_patch.sql` 48–52), no la nueva. Toda
alternativa que pueda dar nulo dentro de una guardia negada va con
`coalesce(…, false)`, y al tocar una guardia se corren las pruebas de sus
casos anteriores, no sólo las del caso que se agrega.

## Un parche por bloque DO con marcador no se reaplica en local (2026-09-28)

Las migraciones que cambian `patch_bike_technical_facts_v1` lo hacen con un
bloque DO que lee `pg_get_functiondef`, reemplaza anclas y sale sin tocar
nada si ya encuentra su marcador: así se puede volver a correr en producción.
En local, la misma protección esconde la iteración. Al cambiar la firma de
`bike_fact_part_conflict_internal` (`20260928110000`) y reaplicar la
migración, la función del parche siguió llamando a la firma vieja: el
marcador ya estaba, el bloque no hizo nada, y la suite del rotor falló con
`function … does not exist` como `rejected`. Costó una corrida en entender
que no era la regla. Si cambias el **texto que inserta** un bloque así en
una migración ya aplicada en local, arregla la función local con un script
aparte en el scratchpad (el mismo `replace` sobre `pg_get_functiondef`) y no
agregues a la migración `drop` ni reparaciones de una firma que producción
nunca tuvo. Las anclas que busca no cambian, así que la corrida real sobre la
versión anterior sigue valiendo.

## Una variable de sesión no es una señal de confianza (2026-09-29)

Para que el comando de guardado corriera la puerta del trabajo terminado una
sola vez al final, el borrador de `20260928140000` hacía que el disparador de
las líneas esperara mientras `current_setting('vinabike.job_line_gate_job')`
dijera ese trabajo. La revisión de Codex lo encontró: cualquier escritor con
`UPDATE` y SQL transaccional hace `set local` de esa variable, cambia una línea
incompatible y confirma sin puerta. `set_config` no tiene dueño ni permiso.
Cuando un disparador tiene que creerle a un comando, la señal va en una tabla
privada (RLS sin políticas y `revoke all` a `anon`, `authenticated` y
`service_role`) con la fila por `txid_current()` que abre y borra el mismo
comando `security definer`; el disparador sólo le cree a esa fila. Y una
columna `not null` sobre lo que se anota en ella hace ruido donde la variable
callaba: `set_config(nombre, null)` vaciaba la lista sin error (un mutante lo
demostró con la tabla). Pruébalo fijando la variable vieja a mano y
esperando el rechazo de siempre.

## Un adaptador que normaliza el payload rompe la idempotencia del kernel (2026-09-19)

`apply_bank_reconciliation_actions_v2` traduce lo que le llega antes de
llamar al kernel, y el kernel guarda el hash de **lo que recibió**. Cuando el
adaptador empezó a marcar sus liquidaciones (`20260919160000`), el payload
normalizado cambió: repetir una operación aplicada antes de ese despliegue
—exactamente para lo que existen las claves de operación, cuando el cliente
perdió la respuesta— devolvía `bank_reconciliation_idempotency_conflict`, sin
nada que el operador pudiera hacer.

Regla: **la idempotencia se juzga sobre lo que mandó el llamador**, no sobre
lo que la capa de traducción produjo. El adaptador guarda su propio
`source_payload_hash`, toma el mismo bloqueo que el kernel, y si la operación
ya existe con esa acción y ese hash devuelve el recibo guardado sin llamar al
kernel (`20260919170000`). Un payload distinto bajo la misma clave se sigue
rechazando. Cualquier cambio en la normalización de un adaptador con
idempotencia se prueba **entre versiones**: aplicar, reescribir el
`payload_hash` guardado como lo dejaba la versión anterior, y reintentar.

## Una carrera de dos conexiones se prueba con dos conexiones (2026-09-19)

pgTAP corre en una sola sesión, así que una guardia de concurrencia no se
puede afirmar ahí: el `verify` sólo comprueba que el texto del bloqueo esté.
`scripts/db/payroll_lock_probe.sh` es el patrón —como
`atomicity_rollback_probe.sh`—: dos invocaciones de `scripts/db/query.sh
local --file`, una que toma el bloqueo canónico y duerme dentro de su
transacción, otra que arranca un segundo después, y afirmaciones sobre el
**error exacto** y sobre el read-back. Sus SQL viven en
`supabase/manual_checks/probes/` y la sonda limpia su propia fixture al
terminar.

Lo que probó: con el bloqueo de Nómina tomado antes de leer el saldo, la
conciliación espera, ve la semana que cambió y rechaza con
`bank_reconciliation_payroll_line_changed`. Sin él pasa su propia validación
y sólo la versión optimista del comando canónico la detiene
(`payroll_payment_version_conflict`), ya dentro de Nómina. **No hay pago
doble en ninguno de los dos casos**; lo que se pierde sin el bloqueo es la
protección propia de la revisión, y por eso la sonda afirma el error exacto y
no «que falle».

**Esperar no es volver a leer (2026-09-27).** `patch_bike_technical_facts_v1`
leía el estado FINALIZADO del trabajo sin bloqueo y después escribía lo
instalado. En la sonda (`scripts/db/bike_fact_completion_lock_probe.sh`) la
escritura **sí esperó** a la cancelación: el `insert` de su recibo y de su
evento chequea la llave foránea a `mechanic_jobs`, y ese chequeo toma
`for key share`, que choca con el `for update` de la transición. Cuando la
cancelación confirmó, el chequeo pasó (la fila seguía ahí) y la función siguió
con la decisión que ya había tomado: trabajo CANCELADO, ficha en 28H y un
recibo. Una espera que aparece en los tiempos no prueba nada; lo que protege
es leer la condición bajo el bloqueo (`select … where status in (…) for
share`), que en READ COMMITTED se reevalúa sobre la versión confirmada. Desde
20260928010000 la escritura ve el trabajo cancelado y se rechaza.

Dos detalles de la sonda que costaron una corrida: `query.sh` tarda varios
segundos en arrancar, así que con `pg_sleep(4)` la segunda conexión llegó
después del commit y «pasó» sin competir (la sesión que retiene duerme 15 s);
y el hook de Bash rechaza un comando cuyo texto trae SQL («Raw SQL and
Supabase database commands bypass…»), también en un heredoc que sólo escribe
un archivo. El SQL de una sonda se escribe como archivo en
`supabase/manual_checks/probes/` y el script sólo nombra rutas. Basta la
palabra del cliente de Postgres en cualquier parte del texto, incluso como
patrón de un `grep` sobre un log (C2, 2026-09-30): se busca por otra palabra.

**Una sonda que pasa por un comando hereda su `lock_timeout` (2026-09-28).**
`transition_mechanic_job_status`, `sync_job_installed_bike_facts_v1` y
`save_mechanic_job_lines_v1` llevan `SET lock_timeout TO '750ms'`
(20260928060000/080000): la segunda conexión **no espera** los 15 s de la
primera, corta con 55P03 y el aplicador lo devuelve como `rejected`, sin
escribir. La sonda de dos trabajos que terminan con la misma bici
(`scripts/db/part_change_rear_cogs_race_probe.sh`) afirma ese rechazo, que la
primera seguía reteniendo cuando la segunda terminó, y el **reintento**
después del commit, en vez de medir cuánto esperó (la primera versión exigía
«esperó más de 5 s» y falló por eso). El aviso de reintento tampoco entra
mientras la bici está tomada: escribir en la historia de la bici chequea su
llave foránea, y ese aviso es de mejor esfuerzo por diseño.

**La limpieza de una sonda no se deshace entera (2026-09-28).** Si la sonda
reemplaza una función (el lector del motor de fichas, que la base local no
trae), devolverla va en su propia transacción, **antes** de borrar la
fixture: la primera limpieza de esa sonda falló en una llave foránea
(`mechanic_job_status_transition_events`) y su rollback se llevó también la
restauración, dejando el lector falso en la base local hasta la siguiente
corrida. Una fixture que pasó por comandos deja filas en tablas que el seed
no conoce (eventos de transición, compromisos de inventario, lista de
compras, más lo que siembra un taller nuevo); la limpieza borra por
`tenant_id` en todas las tablas de `public` que lo tienen, con
`session_replication_role = replica` sólo en esa transacción, y termina
leyendo que no quedó nada y que la función real volvió.

## Una reversa se fecha el día del movimiento que anula (2026-09-19)

`reverse_payroll_settlement_v1` escribía el contra-pago con
`statement_timestamp()`, y el asiento hereda esa fecha. Anular un pago del
27 de agosto dejaba agosto con $30.000 de sueldo que nunca se pagaron y
septiembre con un «Gasto · Salario · -$30.000»: los dos meses mal por el
mismo monto, y en el panorama del dueño un sueldo negativo. Lo vio él, no
una prueba.

La regla: **un contra-movimiento no es plata moviéndose el día en que se
descubre el error, sino la retirada de un movimiento**, así que lleva la
fecha del original (`payment_date` del pago, `applied_at` de la asignación).
`created_at` y la razón quedan como pista de auditoría de cuándo y por qué
se corrigió. `20260919180000` lo corrige en la función y repara en su lugar
lo ya escrito.

Dos cosas que cuestan una corrida si no se saben:

- **Las filas de plata de Nómina están protegidas contra edición**
  (`payroll_money_receipt_movement_is_immutable`, por
  `payroll_money_operation_movements`). Una reparación versionada apaga la
  guardia acotada —`trg_aaa_payroll_expense_payment_balance`,
  `trg_guard_payroll_workspace_expense_payment`,
  `trg_aaa_payroll_advance_allocation_evidence`—, corrige, la vuelve a
  encender y revalida antes de terminar.
- **Cambiarle la fecha a un asiento le cambia el número.** `AC-02788` pasó a
  ser `AC-02875` al moverlo a agosto; el vínculo con su original
  (`reversal_of_id`, `source_document_id`) es lo que se sigue, nunca el
  número.

## Un gasto sin contraparte se lee como dato faltante (2026-09-19)

109 de los 195 gastos del taller son sueldos, y un sueldo no tiene proveedor:
quien recibe la plata es el trabajador. El ERP lo sabía —lo escribía en las
notas y en la línea del gasto— pero dejaba vacío `supplier_name`, que es el
único campo que leen la lista de gastos, la ficha, el panorama y la
notificación. El dueño abrió el Resumen diario y vio «GTO-00196 · Proveedor
no informado · $10.000» una y otra vez.

`supplier_name` es en este ERP **el nombre libre de la contraparte** cuando no
hay ficha de proveedor —así lo escribe la conciliación bancaria para Google,
Meta o el arriendo—, así que ahí va el trabajador
(`ensure_payroll_line_expense`) o el beneficiario del concepto adicional
(`apply_payroll_payment_workspace_v1`, cuyo beneficiario vive en
`payroll_payment_workspace_legs.beneficiary_employee_id`, no en la
disposición: un concepto «adicional» no cuelga de una línea de la semana).
`supplier_id` sigue nulo, así que las guardias de procedencia que miran
`supplier_id` no cambian: [[guard-procedencia-gasto-sin-proveedor]] sigue
valiendo, un gasto sin proveedor es legítimo.

Lo que queda sin contraparte después del relleno son gastos que el dueño
escribió a mano sin decir a quién: no se inventa. **Decisión del dueño
(2026-09-19): los seis que quedan se dejan así** —cuatro «Gastos Varios», uno
de «Costo de Ventas» y un sueldo de diciembre de 2025 cargado a la cuenta
madre `6101`, que es de todos—. No son deuda técnica ni un relleno pendiente:
son gastos cuya contraparte no consta, y el ERP lo dice en vez de inventarla.
Ninguna guardia los marca: el verificador de `20260919230000` sólo exige
nombre cuando la línea carga la cuenta de salario de un trabajador.

## Una suite que no corre completa esconde tres cosas distintas (2026-09-19)

`payroll_statement_reconciliation.sql` llevaba semanas cortándose. Al
repararla aparecieron tres causas que no se parecen:

- **Una trampa de la semilla.** Borrar los métodos de pago del bootstrap
  falla por `payment_terminal_terms_method_fk`; hay que sacar antes términos
  y perfiles de terminal bajo `session_replication_role = replica`. Estaba en
  tres suites más (`payroll_dated_partial_payments_and_advances`,
  `payroll_included_concept_reclassification`, `payroll_payment_workspace`).
- **Una regla derogada.** Varias aserciones fechaban el pago **dentro** de la
  semana; desde `20260812021000` un movimiento anterior al cierre operativo es
  un anticipo, con cartola o sin ella. Eso no se arregla moviendo la fecha y
  ya: la aserción que decía «acepta fechas dentro de la semana» pasó a decir
  «va del cierre operativo al cierre + 5», que es la regla viva.
- **Una regresión real.** La prueba 67 de
  `hr_payroll_authorization_hardening.sql` fallaba porque
  `20260827210000`, al reescribir la identidad, perdió la mitad de la
  comprobación de bloqueo: cualquier `banned_until`, aunque hubiera vencido,
  cerraba el Portal del Trabajador para siempre (`20260919210000`).

**Antes de tocar una fixture, preguntar cuál de las tres es.** Y una prueba
que lleva tiempo roja no es ruido: ésta escondía un bloqueo permanente.

**Cerrado el mismo día, y con una lección de método.** Dije que «otras seis
funciones» trataban cualquier `banned_until` como bloqueo vigente, contando
las que devolvía `grep banned_until is null`. Cuatro ya tenían la condición
completa: `banned_until is null` **es la primera mitad** de «is null or <=
statement_timestamp()», así que buscar esa frase las señala en falso. Lo
encontró Codex revisando, después de que mi reemplazo automático corrompiera
`get_erp_employee_directory` —alias distinto, `directory_auth_user`— y el
`create or replace` no fallara: SQL válido, función rota.

Dos reglas de esto: **una condición se cuenta leyendo su contexto, no
greppeando media frase**, y **una función regenerada desde
`pg_get_functiondef` se prueba ejecutándola**, no sólo aplicándola. Las dos
puertas que sí estaban estrictas —`guard_worker_portal_identity` y
`switch_erp_user_to_worker`— quedaron corregidas en `20260919220000`, con
`supabase/tests/expired_ban_is_not_a_ban.sql` (7 aserciones) encima. Ese
trigger, además, sólo vigila `tenant_id, employee_id, auth_user_id,
is_active`: una prueba que cambia otra columna no lo despierta y pasa sin
probar nada.

Lo que esto **no** resuelve, y conviene decirlo: un bloqueo temporal no es una
suspensión. Si a alguien se le quita el acceso de verdad, va en los estados
(`user_profiles.is_active`, `employees.status`, la cuenta de portal), no en
una fecha que vence sola.

## Un cliente publicado que llama una RPC sin desplegar deja la tienda sin vender (2026-09-23)

La tienda publicada llamaba `get_public_checkout_capabilities` para decidir qué
medios de pago mostrar. Esa función venía en
`20260728220000_harden_public_checkout_capabilities`, cuya primera línea decía
`-- NOT DEPLOYED.` y que nunca se desplegó. PostgREST respondía 404 y el
checkout decía «No pudimos verificar los medios de pago disponibles»: **nadie
pudo pagar en la web** y el último pedido web fue del 19 de julio. Nadie lo
vio en dos meses, porque el error sólo aparecía en el paso de pago y la
tienda no mide eventos.

- Un archivo `NOT DEPLOYED` que el cliente ya llama no es un borrador: es una
  caída de producción. Antes de publicar un cliente, cada RPC que agrega se
  pasa por `migration_status.sh` (o `to_regprocedure` en producción) y tiene
  que estar `APPLIED`.
- Tampoco se despliega el archivo viejo tal cual: se compara cada función que
  reescribe contra `pg_get_functiondef` de producción y contra las
  migraciones posteriores. Ésta sólo agregaba, pero la revisión de Codex
  encontró que la foto de la tienda caía al correo del dueño; se desplegó como
  `20260923200000` y el archivo de julio quedó `SUPERSEDED`.
- `migration_status.sh` sobre las 721 migraciones desplegables da 118
  `NOT_APPLIED`. Muchas son antiguas y se aplicaron por otra vía sin stamp, así
  que **ese número no es una lista de objetos faltantes**: para cada una hay
  que preguntar por el objeto en producción. Las tres del 28 de julio que tocan
  la web sí faltaban (checkout, menú del sitio y publicación).

## Permisos por columna cuando el RLS abre la fila a anónimo (2026-09-23)

El RLS decide **qué filas** se ven, nunca **qué columnas**. `products` tenía
`public_products_select` para `anon` y el grant de tabla por defecto, así que
cualquiera leía `cost` y `supplier_name` de 1.599 productos con la clave
pública. Lo que funcionó (`20260923180000`):

- `revoke all on table ... from anon` también retira los grants por columna
  (INSERT/UPDATE en 97 columnas); se comprobó en local con `has_column_privilege`.
- `grant select (lista) ... to anon` con **la unión de las listas que pide la
  tienda más las columnas por las que filtra u ordena**. La lista sale del
  código y se contrasta con los registros de la API (`edge_logs`, parámetro
  `select` por rol): un filtro sobre una columna sin grant falla igual que un
  `select`.
- Las RPC SECURITY DEFINER, la clave de servicio y los embebidos que no pasan
  por `anon` no cambian. Las funciones SECURITY INVOKER que anónimo puede
  ejecutar sí: `search_products` devolvía `p.*` y era otra puerta al costo
  (`20260923201000`).
- **`authenticated` no se arregla así**, porque el staff usa el mismo rol y
  necesita el costo. La rama «publicado» de `products_select` dejaba a
  cualquier cuenta de cliente (registro abierto con correo o Google) leerlo
  todo. Se cerró quitando esa rama (`20260923190000`) y haciendo que la
  tienda lea el catálogo con un cliente anónimo aunque haya sesión
  (`PublicCatalogClient`).
- Read-back real: como anónimo por REST (`select=cost` → 42501) y, en
  producción y sólo lectura, con `set local role authenticated` y los claims
  de una cuenta de cliente existente (0 filas) y de un usuario del staff (sus
  productos, con costo).

## La base local se reconstruye a mitad de ronda (2026-09-23)

`ensure_local.sh` rearma el esquema local desde `core_schema.sql` cuando
cambia el hash de sus entradas, y la base local es compartida entre sesiones y
worktrees. A mitad de una tanda de pruebas se reconstruyó y borró las
migraciones candidatas que había aplicado: una prueba que había pasado volvió
a fallar, y otra dio un «antes» sobre una versión que no era la de producción.

Antes de confiar en un resultado local de «antes y después», se compara
`md5(prosrc)` de cada función involucrada contra producción. Si difieren, se
carga en local el cuerpo exacto de producción (`pg_get_functiondef`), se corre
la prueba —tiene que fallar— y recién entonces se aplica la migración.

## Lo que no se lee sin sesión se prueba por REST, relación por relación (2026-09-24)

Contar filas como `anon` en las 177 relaciones con grant de SELECT
(`set local role anon` + `query_to_xml(format('select count(*) ... %I'))`,
porque un read-back alojado no admite `do $$`) encontró las dos puertas que el
RLS no cubre, y ambas se confirmaron con la clave pública por REST antes de
cerrarlas (`20260924020000`):

- **Una vista materializada no tiene RLS.** `product_gama_bands_mv` llevaba el
  costo neto promedio de compra por marca y categoría, con grant a `anon` y a
  `authenticated`: 107 filas para cualquiera, y los costos de todos los
  tenants para cualquier sesión. Una vista `security_invoker` encima no
  protege nada si lee la materializada. Sus consumidores eran SECURITY
  DEFINER, así que el grant sobraba. El linter de Supabase la marca como
  `materialized_view_in_api`.
- **pgTAP instalado en `public` queda en la API.** 1.074 funciones y dos
  vistas: `GET /rest/v1/tap_funky` lista cada función del esquema con su
  `is_definer`, y `POST /rest/v1/rpc/lives_ok` (cuerpo `text/plain`) ejecuta
  el SQL que recibe. Sus objetos son de `supabase_admin`: un `revoke` de
  `postgres` termina sin error y sin quitar nada. Lo que funcionó fue
  `drop extension pgtap; create extension pgtap with schema extensions` (es
  una extensión privilegiada de supautils; `postgres` puede hacerlo), y las
  pruebas lo siguen resolviendo sin prefijo porque `extensions` está en el
  search_path de `postgres` en producción y en local. `anon` y
  `authenticated` necesitan USAGE en ese esquema para las pruebas que cambian
  de rol: la base de `production_validation.sh` lo creaba sin grants y
  `products_anon_public_columns` falló con `function lives_ok(unknown,
  unknown) does not exist` hasta que se replicó el grant de Supabase. Esa
  base instala pgTAP en `extensions`, igual que producción: instalado en
  `public` escondería una prueba que dependa de ese esquema.
- **Una función SECURITY DEFINER que anónimo puede ejecutar no es un
  hallazgo por sí sola.** De las 29 que marca el linter, las de la tienda son
  la fachada pública, las que devuelven `trigger` no las expone PostgREST y
  las del asistente exigen `assistant_require_capability_internal_v1` adentro.
  Se lee el cuerpo antes de revocar.

## Una fixture fecha con el mismo reloj que la función que prueba (2026-09-24)

`purchase_candidate_metrics_v1` mide la antigüedad de la última compra con
`tenant_business_date(tenant)` (hora de Chile), y el fixture de
`supply_need_external_candidates.sql` fechaba las compras con
`current_date - 30` (UTC). Entre las 21:00 y las 24:00 de Chile las dos
fechas difieren en un día, la antigüedad sale 29 y los puntajes exactos
fallan. Fallaba tres horas al día y pasaba el resto: la misma prueba falló a
las 01:47 UTC y pasó a las 04:30 sin tocar nada. Una fixture de fechas usa la
función que usa el código (`tenant_business_date(...) - n`), no
`current_date` ni `now()`. Ante una prueba que pasa y falla sin cambios, la
primera pregunta es a qué hora corrió.

En el mismo repaso, dos pruebas que parecían regresiones eran reglas vigentes
de producción: el peso de la gama se había movido al núcleo de puntaje, y un
valor de ficha sólo es evidencia si el campo está activo en la plantilla del
producto (`spec_product_field_is_active_internal_v1`). Antes de «arreglar»
producción para que pase una prueba, se busca dónde vive hoy la regla.

## Una columna que no existe no falla: se muestra vacía (2026-09-25)

Las páginas que leen una fila de Supabase como `Map<String, dynamic>` no
avisan cuando piden una columna que no existe: `row['description']` devuelve
`null`, la página no pinta nada y ninguna prueba falla. En el portal de
clientes pasó dos veces desde que se escribió: «Taller» leía
`mechanic_jobs.description` (no existe; lo que el cliente pidió está en
`client_request`, lleno en 409 de 505 trabajos) y «Soporte» leía
`conversations.last_message` (no existe; el último mensaje viene en las filas
`messages` que trae la misma consulta). El cliente nunca vio qué había pedido
ni el último mensaje. Antes de atar un campo nuevo a una pantalla se leen las
columnas reales (`information_schema.columns` por `scripts/db/query.sh`) y
cuántas filas lo traen lleno; lo segundo decide si vale la pena mostrarlo.

## Contar productos de una categoría como los ve el cliente (2026-09-25)

`get_public_products_faceted_v2(tenant, array[<categoría>], …)` filtra por
`category_id` exacto: con una categoría padre («Ruedas», «Transmisión»)
devuelve cero filas, porque los productos cuelgan de las hojas. La página de
catálogo expande el subárbol en el cliente (`_getCategoryAndDescendantIds`),
así que para contar lo que un cliente ve en una categoría se pasa el arreglo
del subárbol completo (CTE recursiva sobre `product_categories.parent_id`).
Y se cuenta con esa función, no con `is_active and show_on_website and
is_published`: esa condición daba 128 cámaras y la tienda muestra 22. Así se
eligió la grilla de la portada del 2026-09-25 (Ruedas 152, Transmisión 63,
Accesorios 61, Frenos 61, Cambios 58, Dirección 33 visibles). Una categoría
sólo es destino público con `show_on_website`; el 2026-09-25 había 7 de 137.

## Un vocabulario del registro dentro de una RPC se prueba en local y se iguala en producción (2026-09-27)

La base local no trae el registro de especificaciones que usan las fichas:
el 2026-09-27 no tenía `spec_definition_values` ni las definiciones
`axle_type` y `fluid_type`, así que una RPC que validara contra el registro
en tiempo de ejecución no se podía probar con pgTAP. En
`20260928030000_bike_technical_fact_fluid_and_axle.sql` los códigos van
escritos en la función, como los demás vocabularios del comando, y el
read-back comprueba en producción las dos direcciones: cada código activo y
global del registro, sin «Desconocido / sin confirmar», está en el cuerpo, y
el registro tiene exactamente tantos como el cuerpo nombra. Si alguien agrega
un eje al registro, el siguiente read-back falla y el comando lo rechaza con
«unknown value» hasta su migración: el desfase se ve, no se come.
«Desconocido / sin confirmar» del registro es un código `catalog_…`, no el
texto `unknown`: la guardia que rechaza confirmar lo desconocido tiene que
nombrar ese código aparte.

## Un conflicto con `40001` no llega al cliente: PostgREST lo reintenta sin fin (2026-09-28)

PostgREST 14 —el de producción, 14.5— trata un `40001`
(`serialization_failure`) lanzado por una función como transitorio y
reejecuta la transacción él mismo, sin tope. El cliente recibe un **504** del
gateway, no el conflicto, y la base sigue ejecutándola. La historia completa y
la corrección del diagnóstico del 15-09 están en
`docs/development/SUPABASE_WORKFLOW.md` («Corrección 2026-09-28»).

- **Regla:** un conflicto de negocio (versión vieja, recibo superado, fila
  que ya no existe) se lanza con `PT409` (HTTP 409, `code` = `PT409`) o clase
  23, con `detail`. `40001` sólo si repetir la misma transacción puede
  resultar distinto.
- **Si un bucle está vivo:** en `pg_stat_activity` se ven conexiones de
  `PostgREST 14.x` alternando `active` e `idle in transaction (aborted)` sobre
  la misma sentencia, con `query_start` renovado cada pocos milisegundos
  (`pg_stat_statements` no lo muestra: sólo cuenta lo que termina bien).
  Primero se corta la fuente (la app o la bandeja que reenvía); después
  `pg_terminate_backend(pid)` de esas conexiones, con
  `VINABIKE_DB_WRITE_CONFIRM=production` y el `pid` y la sentencia en el
  mismo `where`. `pg_cancel_backend` no basta: PostgREST empieza otra vuelta.
- **Cuáles quedan:**

  ```sql
  select n.nspname || '.' || p.proname
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'private') and p.prokind = 'f'
     and (pg_get_functiondef(p.oid) ilike '%serialization_failure%'
          or pg_get_functiondef(p.oid) ilike '%''40001''%');
  ```

  79 el 2026-09-28, antes de `20260928052000` (que saca las dos de la ficha).
- **Costo:** una prueba del ítem 3 con la bici fixture abrió tres bucles en
  producción durante ~20 minutos hasta que se terminaron a mano; ninguno
  escribió (el conflicto aborta cada vuelta).

## Lo que borra y reinserta se mide contra todas las llaves, no contra su lista (2026-09-29)

`restore_backup` borra y reinserta, por taller, las 38 tablas que guarda el
respaldo; el esquema creció alrededor. Leído del catálogo en producción: 173
llaves foráneas desde tablas que el respaldo no guarda bloquean ese borrado,
70 borrarían en cascada (fichas técnicas, historia de las bicis, tareas,
líneas de facturas de compra…) y 48 dejarían vínculos en null. La restauración
fallaba en todos los talleres por `payment_terminal_terms`, que cada taller
trae al crearse, y **ese fallo era lo único que protegía el resto**: arreglar
el síntoma (apagar la llave, o sembrar las terminales en el respaldo) habría
dejado pasar las cascadas. Casi se cierra así el corte de adjuntos faltantes:
el pgTAP falló en la llave de las terminales, no en lo que se probaba.

Antes de reparar o reemplazar una función que borra y reinserta un conjunto de
tablas, lista las llaves foráneas **hacia** ese conjunto **desde fuera** de él
(`pg_constraint`, `confdeltype`) y cuenta las filas por taller: `c` pierde
datos, `n`/`d` los desconecta, el resto bloquea. `restore_backup_uncovered_dependents`
lo hace en vivo y es la guardia de `restore_backup`; el read-back de
`20260929030000` compara su lista de tablas con los `delete from` de la
función, para que no se separen.

Codex encontró el caso peor en la revisión: la restauración borra las 38
tablas pero reinserta sólo las que el respaldo trae, y al único respaldo
completado del taller principal (2025-12-09) le faltan las 7 de la
mensajería. Restaurarlo vaciaba los mensajes y daba éxito. Ojo al medirlo:
`create_backup` guarda una tabla vacía como `null`, así que «falta» es **la
clave ausente** (`not (data ? tabla)`), no `jsonb_typeof(...) <> 'array'`. Con
la segunda condición conté 18 faltantes y el pgTAP negó todos sus propios
respaldos recién hechos.

Dos datos del taller de prueba que cuestan una corrida si no se saben: un
taller nuevo nace con `payment_terminal_terms` (2), `payment_terminal_profiles`
(1) y `expense_categories` (1), y cada trabajo insertado crea su
`mechanic_job_status_transitions`; y reinsertar un medio de pago con tarjeta
vuelve a sembrar sus terminales (`zz_seed_terminal_from_legacy_card`), así que
una segunda restauración en la misma prueba las encuentra de nuevo. El
medio de pago y la terminal se apuntan entre sí: soltar la terminal exige
poner `terminal_profile_id` en null antes, o la reinserción del medio de pago
falla en `payment_methods_terminal_profile_fk`.

## Un cambio de catálogo se ensaya contra producción, no sólo en local (2026-10-01)

La base local sólo tiene 99 definiciones globales y ninguna tabla con filas
(`rows_schema`): una migración que edita definiciones del catálogo pasa en
local con `UPDATE 0` y no prueba nada de lo que hará en producción. La
`20261002150000` apartaba `spec_rows_definition_guard`, quitaba la
obligación de las columnas de fuente en 88 tablas y volvía a encender el
guardia; en local, verde. Ensayada en producción falló con `cannot ALTER
TABLE "spec_definitions" because it has pending trigger events`: el `update`
dispara disparadores diferidos (revisión de contrato, guardias de reglas) y
Postgres no deja tocar los disparadores de la tabla con eventos pendientes.
Arreglo: `set constraints all immediate;` antes del `enable trigger`, como ya
hacía `20260919253000`.

Cómo se ensaya sin desplegar: `scripts/inventory/fill_expert_values.py
--mode dry --prelude <cuerpo-de-la-migración>` corre, en cada transacción
que termina en `rollback`, el cuerpo de la migración (sin `begin`/`commit`)
y después las llamadas reales como el actor. Sirve para cualquier migración
que el llenado necesite y que producción todavía no tiene. Ojo: un `alter
table` del cuerpo bloquea las escrituras (no las lecturas) de esa tabla
mientras dura cada tanda; tandas cortas.

## Cuatro trampas de un pgTAP y un read-back de cambios de partes (2026-10-02)

Costaron tres corridas de `just db-test part_change_cockpit` y una revisión de
Codex antes del despliegue de `20261002170000`.

- **Insertar el tenant pone `request.jwt.claim.sub` con su id.** Un
  `created_by` posterior falla por la llave foránea a `auth.users`. Se reponen
  los claims del empleado de prueba después de insertar el tenant, como hace
  `part_change_rim.sql`.
- **En `like`, la barra invertida es el escape.** `like '%(\.[0-9]+)?$%'` sobre
  `pg_get_functiondef` nunca coincide aunque el texto esté. Un read-back que
  busca un fragmento literal usa `position(... in ...) > 0`.
- **Una línea `incompatible` o `stale_change` bloquea terminar el trabajo**
  (`job_completion_blocked`) y revierte todo lo que ese cierre escribía, eventos
  incluidos. Un caso que espera el bloqueo va en un trabajo propio; si comparte
  trabajo con casos que escriben, se lleva sus aserciones.
- **Una pasada sobre el historial no pasa por la puerta.** No puede marcar
  líneas viejas (la factura pagada las protege), así que escribe la ficha
  directo; entonces tiene que repetir lo que la puerta revisa —rango y
  vocabulario de cada dato—, o escribe lo que la puerta habría rechazado. Lo
  encontró Codex leyendo la migración, no el pgTAP: el read-back final lo
  habría detectado sólo después de escribir.


## Antes de guardar un resultado, quitar el trabajo que sobra (2026-10-07)

Las lecturas del catálogo público pasaban el tope de 3 s de `anon` con unas
doce visitas a la vez. El primer arreglo fue guardar lo que se recalculaba en
cada visita (texto de búsqueda y valores técnicos de cada producto) en tablas
mantenidas por disparadores en la misma transacción del cambio. **Se
descartó entero** después de dos revisiones de Codex que encontraron nueve
defectos, siete de concurrencia: candados consultivos que se suben de
compartido a exclusivo, órdenes de candado invertidos entre la fila del
producto, la cola y el candado consultivo, una reconciliación nocturna que
escribía texto viejo sobre el nuevo, un cambio compartido que no ve el hecho
aún sin confirmar de otra transacción, y `TRUNCATE`, que salta todos los
disparadores. Costó unas tres horas. Una tabla derivada mantenida por
disparadores es un diseño de concurrencia, no una optimización: se paga en
cada escritura y en cada camino que escribe.

Lo que sí funcionó fue **hacer que la lectura haga menos y devuelva lo
mismo** (`20261007020000`): ligar plantillas en un solo `join` en vez de una
vista por producto, leer el contrato de cada plantilla una vez, calcular los
valores técnicos sólo de los productos de las categorías pedidas y no
normalizar texto cuando no hay búsqueda. Filtros 391 → ~120 ms en la raíz y
399 → ~65 ms en una categoría; listado ~130 → ~25 ms. Sin tablas, disparadores
ni candados nuevos. Primero se quita el trabajo que sobra; guardar resultados
viene después, si todavía hace falta.

**Cómo se prueba que devuelve lo mismo, en producción y sin escribir:**

- Se copia la definición viva (`pg_get_functiondef`) antes de tocarla y se
  compara su `md5(prosrc)` con la de producción justo antes del despliegue.
- El cuerpo anterior va **en línea** en la consulta: el read-back corre en
  `begin read only` y ahí no se puede crear una función, ni temporal. Los
  casos van en un `values` y el cuerpo, una sola vez, en un `cross join
  lateral` o en una subconsulta escalar por caso. Se compara
  `md5(string_agg(fila::text, '|' order by rn))` con `row_number() over ()`
  (mismo orden) y `except all` en los dos sentidos (mismas filas, mismas
  repeticiones).
- Al poner en línea un cuerpo: los `p_x` se reemplazan por la columna del
  caso, pero **no** los de una llamada con nombre (`p_x := p_x` conserva el
  nombre a la izquierda); el caso necesita un alias que el cuerpo no use (el
  de los filtros ya tenía su propio `k`, y `k.p_tenant_id` «no se puede
  referenciar desde esta parte de la consulta»); `= any((select ids from …))`
  compara con un arreglo de arreglos y falla, se escribe `in (select
  unnest(…))`.
- En pgTAP, el cuerpo anterior sí va como función `pg_temp` y la prueba compara
  sobre un fixture que cubre cada camino (plantilla propia que gana a la de la
  categoría, plantilla propia inactiva sin caer a la categoría, ligazón
  pendiente, rol retirado, etiqueta del contrato…).

**Trampas de Postgres que salieron del intento descartado** y siguen
valiendo:

- `after update of <columnas>` no ve lo que escribe un BEFORE: el disparador
  se dispara sólo si la columna está en la lista del `UPDATE`
  (`trg_sync_product_denormalized_fields` llena `category_name`). Se usa
  `when (old.x is distinct from new.x …)`, que compara la fila final.
- Una llave foránea desde una tabla nueva a una tabla del respaldo
  (`products`, entre otras) hace que `restore_backup_uncovered_dependents`
  rechace toda restauración.
- Una tabla de transición sirve a un solo evento: `referencing` no se acepta
  en un disparador `insert or update`.
- `TRUNCATE` no dispara los disparadores de fila ni de sentencia de
  `insert/update/delete`.

**La otra mitad no era la base.** Con las lecturas ya baratas, doce páginas
a la vez seguían dando algún 503: el servidor HTML mandaba unas ochenta
consultas juntas a la instancia actual (pequeña, de CPU compartida: 60
conexiones, 256 MB de `shared_buffers`) y cada una tardaba diez veces más. El servidor ahora deja pasar cuatro a la vez
(`DatabaseGate`, `services/storefront_html/lib/src/database_gate.dart`) y las
demás esperan su turno en el servidor, donde esperar no cuesta nada.

## Una regla por fila sin subconsultas, y medida antes y después (2026-10-10)

La regla única de venta online (`catalog_product_web_block_v1`) se aplica a
cada fila de las lecturas públicas. La primera versión preguntaba por la
categoría con un `exists (...)` y **el listado público pasó de ~50 a ~110 ms**:
una función `language sql` sólo se incrusta en la consulta que la llama si no
tiene `security definer`, ni `set`, ni **subconsultas**; con una, Postgres la
llama fila por fila. Se movió esa pregunta a su propia función
(`catalog_category_visible_v1`) y volvió a ~51 ms (`20261010020000`, su
read-back afirma que el cuerpo no tiene `exists`).

- Antes de tocar una función que usan las lecturas públicas, guardar el
  `EXPLAIN (ANALYZE)` de la lectura en producción; repetirlo después.
- Un permiso por columna nuevo para `anon` (aquí `website_price_mode`) va en
  la misma migración que la función `security invoker` que lo lee, y el
  read-back afirma ambas cosas (`20261010030000`).
