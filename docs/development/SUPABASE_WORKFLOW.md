# Supabase Daily Workflow

Use this guide for commands. The authority for environment use, release
evidence, and production safety is
`docs/runbooks/STAGING_SUPABASE.md`.

## Current environment map

- Production: `xzdvtzdqjeyqxnkqprtf`; authoritative and repository-linked.
- Staging: `bczzjhjrpmtpgwdvlbut`; policy-dormant and non-authoritative.
- Local: persistent disposable Supabase stack for the fast development loop.

Supabase may report dormant staging as `ACTIVE_HEALTHY`. That is provider
health, not permission to use it. Do not run staging queries, gates, fixtures,
or browser journeys unless the owner explicitly reactivates it. The guarded
launchers enforce this with the per-command
`VINABIKE_STAGING_REACTIVATION_CONFIRM=bczzjhjrpmtpgwdvlbut` confirmation,
which must not be persisted in `.env` or shell startup files.

## Tool boundary

| Need | Canonical path |
|---|---|
| Where an agent starts | `docs/development/AGENT_DATABASE_CONTRACT.md`, then `just db-preflight` |
| What the wrapper accepts and enforces | `bash scripts/db/query.sh --help` / `just db-help` |
| Local or hosted SQL read | `scripts/db/query.sh` or the corresponding `just` recipe |
| Authorized hosted SQL write | `scripts/db/query.sh ... --write` with the exact write confirmation |
| Local pgTAP | `scripts/db/test.sh` / `just db-test` |
| Canonical bootstrap gate | `just db-gate` |
| Production compatibility | Guarded direct read-only queries, then authorized deploy plus live read-back |
| Trace, fingerprint, drift, health, CPU profile | Guarded recipes under `scripts/db/` and `just db-cpu` |
| Project status, secrets, functions, backups | `scripts/supabase_cli.sh` with explicit project ref |
| Verified migration-history registration | `scripts/supabase_cli.sh migration repair --linked` after exact read-back |
| Authenticated REST/RLS behavior | Publishable key and a synthetic authenticated user; privileged secret key only when the test explicitly requires admin behavior |
| Production schema capture | Deprecated; do not use as compatibility evidence |

Do not use raw `supabase db query`, `supabase db push`, ad hoc remote `psql`, or
the Supabase SQL Editor as an agent SQL path. The database wrapper supplies the
read-only transaction, timeout, credential loading, and production identity
guards that those paths do not. On Bash/macOS/Linux, do not invoke the Supabase
binary directly for control-plane work either; use `scripts/supabase_cli.sh`.

## Session preflight

Run once at the start of a database task, not before every command:

```bash
just db-preflight
```

That single recipe runs the CLI version check, the linked-ref assertion, the
hosted control-plane project list, and `scripts/db/status.sh`. The individual
commands remain available when a step needs to be inspected on its own:

```bash
cd /Users/Claudio/Dev/bikeshop-erp

scripts/supabase_cli.sh --version
cat supabase/.temp/project-ref
scripts/supabase_cli.sh projects list --output json
bash scripts/db/status.sh
```

Expected linked production ref:

```text
xzdvtzdqjeyqxnkqprtf
```

The project-list result is a control-plane status check. `supabase status`
describes only the local Docker stack; a stopped local stack does not mean
hosted Supabase is down. `scripts/db/status.sh` also reports linked identity,
CLI authentication, API-key metadata, and each credential as
`credential-ready`, `missing`, or `inaccessible` without printing a value.

`scripts/supabase_cli.sh` forces Supabase telemetry, `DO_NOT_TRACK`, and
OpenTelemetry exporters off. This prevents trace/telemetry files from retaining
request metadata and avoids telemetry-file races and sandbox/Windows `EPERM`
failures. It also requires explicit approved project refs, rejects hosted
database shortcuts and project/storage deletion, and requires an exact
per-command confirmation for function deletion or secret removal. Run
control-plane commands sequentially.

From a PowerShell host with the repository's Git Bash available, keep the same
wrapper boundary:

```powershell
bash scripts/supabase_cli.sh projects list --output json
```

## Credentials and what each one does

No private Supabase credential is hardcoded in the repository.

| Credential | Purpose | Approved source |
|---|---|---|
| Supabase CLI access token | Management/control-plane commands | Provider login store; macOS Keychain service `Supabase CLI`, account `supabase` |
| Production database password | Guarded PostgreSQL reads, schema export, and authorized writes | macOS Keychain service `Vinabike ERP Supabase database password`, account `postgres`; CI `SUPABASE_DB_PASSWORD` |
| Local-maintenance secret key | Explicit privileged local maintenance/REST consumers | macOS Keychain service `Vinabike ERP Supabase secret key`, account `supabase`; not shared with GitHub |
| GitHub storefront SEO secret key | Storefront SEO sync and snapshot generation in the protected GitHub workflow only | Protected repository secret `SUPABASE_SECRET_KEY`; not copied to local Keychain |

**The CI copy of the database password goes stale silently (2026-08-10 and
2026-09-15).** `Deploy to Firebase Hosting on merge` builds, deploys and
verifies `release.json` on production, and then its last step, `Verify
read-only production ERP invariants` (`scripts/db/health.sh production`),
fails with `password authentication failed for user "postgres"` at the
Supabase pooler. That message means the `SUPABASE_DB_PASSWORD` secret of the
GitHub `Production` environment no longer matches the database password (the
pooler reports the user without its `.<project-ref>` suffix, so the username
is not the problem). The run is red although production is already serving
the new commit, and it stayed unnoticed for five weeks because `main`
received no push in between. Fix: refresh that one secret from the Keychain
entry above and re-run the failed job; never reset the database password for
this, which would break the Mac wrapper and every other consumer.
Done on 2026-09-15 22:36 UTC with
`security find-generic-password -w -s '<service>' -a postgres | gh secret set
SUPABASE_DB_PASSWORD --env Production` (the value never touches the
terminal); the next deploy run (`35030810641`, `dc1e609`) passed that step on
its first attempt because environment secrets are read when the job starts,
not when the run is queued. Prove the Keychain copy first with
`bash scripts/db/health.sh production`, which uses the same credential path.
| Publishable key | Public client initialization and RLS-governed requests | macOS Keychain service `Vinabike ERP Supabase publishable key`, account `supabase`; approved client/CI configuration |
| Staging ref/password | Dormant environment tooling | Keychain services `Vinabike ERP Supabase staging project ref` and `Vinabike ERP Supabase staging database password`; protected environment variables |
| Staging publishable key/E2E login | Dormant browser fixtures, only after owner reactivation | Keychain services `Vinabike ERP Supabase staging publishable key` and `Vinabike ERP staging E2E password`; protected `SUPABASE_STAGING_PUBLISHABLE_KEY` / `E2E_PASSWORD` |

The database password is not an API key. The CLI token is not a database login.
The publishable/anon key is public but does not bypass RLS. The secret key is
privileged.

The exposed modern key named `default` was revoked on 2026-07-25. Production
now has two separately validated modern secret keys: local maintenance and
GitHub storefront SEO. Keep them consumer-scoped and in their separate stores;
never recover a secret from CLI key-list output or copy one consumer's key into
the other consumer.

The legacy `service_role` JWT is compromised and still enabled only for
unmigrated consumers. Never add it to a new consumer. The legacy `anon` JWT is
public client configuration and remains active for unmigrated client builds; it
is not a privileged credential. Do not disable or rotate legacy keys in an
ordinary task; follow
`docs/development/SECURITY_REMEDIATION_2026-07-12.md` and migrate every consumer
first.

Check only whether credentials are present. Never print their values, full
connection strings, or credential-bearing commands.

## Fast local loop

```bash
just db-status
just db-start
just db-test payment_integrity_guards
just db-test stock_ledger_continuity sales_credit_note_kernel
just db-query local "select count(*) from stock_movements"
```

`db-start` reuses the running local stack when the recorded historical-fixture
hash is unchanged. It rebuilds only when the fixture inputs changed, required
sentinel objects are missing, no verified hash exists, or `--reset` was
requested.

`db-test` calls `ensure_local.sh`, then runs only the selected pgTAP files.
Every ordinary pgTAP rerun reuses the already prepared local database. It does
not copy production and does not rebuild from scratch unless the local fixture
inputs actually changed.

**Trampa del seed de tenant en fixtures pgTAP (2026-08-26).** El seed de
inicialización que corre al insertar una fila en `tenants` deja
`request.jwt.claim.sub` apuntando **al id del tenant** y no lo restaura. Desde
ese punto `auth.uid()` devuelve el tenant, y cualquier trigger que capture
actor (`set_mechanic_job_created_by`, guards de identidad) escribe ese uuid
como si fuera un usuario: el síntoma es un
`mechanic_jobs_created_by_fkey violation` en un INSERT de fixture que parecía
correcto, y costó una ronda completa encontrarlo. Regla: **después de insertar
tenants y antes de cualquier otra fila**, limpia el contexto:

```sql
select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);
```

Varias suites antiguas (`mechanic_job_archive`,
`ai_assistant_filtered_operational_reads`, entre otras) no lo hacen y hoy
abortan en local por esta causa, no por el cambio que estés probando: verifica
la preexistencia con teardown/reaplicación antes de atribuirte la falla.

Run the full legacy-fixture gate only when `core_schema.sql` or an included
fixture input changed, or at a deliberate checkpoint:

```bash
just db-gate
```

This gate drops and rebuilds the disposable local `public` schema, applies the
incomplete historical fixture, and runs all pgTAP files. It proves only that
the fixture remains internally usable—not completeness or compatibility with
production.

## Guarded SQL reads

```bash
bash scripts/db/query.sh local \
  --sql "select count(*) from stock_movements" \
  --format table

bash scripts/db/query.sh production \
  --sql "select now() as checked_at, current_database() as database_name" \
  --format table

bash scripts/db/query.sh production \
  --file supabase/manual_checks/diagnostics/example.sql \
  --format table
```

Formats are `table`, `csv`, and `json`. Hosted reads run in a read-only
transaction with a 30-second timeout. The wrapper rejects transaction escape
statements. Batch related read-only evidence into one query/file where that
reduces repeated connections and remains reviewable.

Two further defaults apply to hosted reads, and to hosted reads only. The local
stack holds synthetic data and is unrestricted; a write is already gated by
explicit confirmation and task authorization.

**Row cap.** A single-statement `SELECT`/`WITH` hosted read returns at most 200
rows. The cap is announced on stderr, so a truncated result is never mistaken
for a complete one. Multi-statement input and `--file` are not capped.

```bash
bash scripts/db/query.sh production --max-rows 2000 \
  --sql "select id, status from operations where created_at >= now() - interval '7 days'"

bash scripts/db/query.sh production --max-rows 0 \
  --sql "select count(*) over () from stock_movements"
```

**Sensitive-column guard.** A star projection (`select *`, `select t.*`) that
reads `from`/`join` a table listed in `scripts/db/sensitive_tables.txt` is
rejected. Name the columns the task needs. `count(*)`, aggregates, and explicit
column lists are unaffected, including on those tables.

```bash
# rejected: dumps every personal column of every matched customer
bash scripts/db/query.sh production --sql "select * from customers limit 50"

# correct
bash scripts/db/query.sh production \
  --sql "select id, tenant_id, is_active from customers limit 50"
```

`--allow-pii` overrides the guard when the task genuinely needs the whole row.
It is recorded in the journal. Keep the result out of committed files and
reports. Extend `sensitive_tables.txt` whenever a table starts storing personal
data; the guard limits accidental disclosure and is not an access-control
boundary, which remains RLS and grants.

**Audit journal.** Every invocation appends one line to `.tmp/db/journal.jsonl`
with timestamp, environment, read/write mode, SQL SHA-256, source, format, caps,
duration, and exit status. It never contains SQL text, result values, or
credentials. It is git-ignored local evidence: cite it when reconstructing what
a session did against production, and do not treat it as a deliverable.

Useful guarded diagnostics:

```bash
just db-trace production operation 00000000-0000-4000-8000-000000000000
just db-trace production product 00000000-0000-4000-8000-000000000000
just db-trace production tenant 00000000-0000-4000-8000-000000000000
just db-fingerprint production
just db-drift local production
just db-health production
just db-cpu production
```

Full manifests and verbose output stay under ignored `.tmp/db/`.

### A Supabase "high CPU usage" email is answered with measurements, not by reading code

2026-09-15. The project is small and still received the >80% CPU alert every
Saturday night for three weeks. Reading the code produced five plausible
suspects (per-minute pg_cron workers, the in-database backup, storefront and
ERP polling, RLS helpers evaluated per row, Realtime). None was the cause. The
measurement found it in minutes:

- **The cause was one client retrying a rejected RPC in a loop.** A trigger
  rejected a stale `record_supplier_need_portal_search_v1` receipt with
  errcode `40001` (serialization_failure). To every client that code means
  «retry the same transaction», so the ERP retried it ~900 times per second
  for 16 days: 1.14 billion aborted transactions, PostgREST's whole pool busy,
  `tenants` and `user_profiles` sequentially scanned 1.16 billion times by
  `user_tenant_id()` inside each attempt. Changing the errcode to `23514`
  (class 23, «rejected, do not retry») stopped it within the minute.
  `supabase/migrations/20260915190000_reject_stale_need_portal_search_definitively.sql`
  is the exact deployed body.
  Stamped as APPLIED on 2026-09-15 20:00 UTC through
  `scripts/db/deploy_migration.sh` (idempotent re-apply, read-back file
  `supabase/manual_checks/verification/20260915190000_reject_stale_need_portal_search_definitively.sql`,
  then `migration repair`); the MCP deploy alone leaves no stamp. The same
  day the ERP client stopped treating any class 22/23 or `P0001` answer from
  `record_supplier_need_portal_search_v1` as transport: it surfaces
  `SupplierNeedSearchRejected`, drops the reading, reloads the need and never
  enqueues a retry chain (`lib/shared/services/supplier_availability_service.dart`,
  `intelligent_purchasing_workspace_page.dart`).
- **The debug build was not the runaway client.** The canonical macOS debug
  session (`screen -x payroll`, 12 days of `run.log`, 33 MB) contains zero
  `40001` or «recibo falló» lines, and its bounded receipt retry waits 5–120 s
  between five attempts. A hot restart was done anyway on 2026-09-15; the
  storm had already stopped with the errcode change. The ~900/s caller was a
  Flutter build on the owner's network with a bearer issued 2026-08-30: look
  at an installed Release app or another device before blaming this session.
- **A failing-request storm is invisible in `pg_stat_statements`.** It only
  records statements that complete, so §2–§4 of the profile showed Realtime
  as 66% of tracked time while the real burner was untracked. The tells are
  `pg_stat_database.xact_rollback` (§12d), the ERROR rate in `postgres_logs`,
  and PostgREST backends all `active` or `idle in transaction (aborted)` on
  the same statement (§5).
- **Identify a PostgREST caller from inside the database.** Nothing in the
  edge logs matched, so the trigger's exception message temporarily included
  `current_setting('request.headers', true)`: `x-client-info` named the
  Flutter app, `x-forwarded-for` the owner's own network, and the bearer's
  `iat` dated the runaway session to 2026-08-30. One `create or replace`,
  read the next log lines, put the original back.
- **Supabase re-sends the CPU alert weekly while the condition persists.**
  Three emails at the same hour on consecutive weekends were the same
  continuous storm, not a weekly job.
- **`40001` is an instruction, not a label.** Raise it only when re-running
  the identical transaction can succeed. A receipt stamped with a superseded
  version can never be accepted; that is class 23 or `P0001`, with `detail`
  and `hint` telling the client what to reload.

The measured secondary loads, in order, once the storm was gone: Realtime
`list_changes` (~11% of one core continuously, 21 published tables, ~19 live
subscriptions), ~300 RLS policies comparing `tenant_id = public.user_tenant_id()`
without `(select …)`, the ERP shell's 20 s / 30 s pollers, the storefront's
30 s / 60 s freshness pulses per open tab, and the per-minute pg_cron workers
with `cron.job_run_details` never purged (215k rows). They are backlog, not
the alert.

### Backlog de carga residual, 2026-09-15

Medido en producción sobre 17 días desde el 2026-08-30 05:29 UTC (reset de
`pg_stat_statements`), ya sin el bucle de reintentos `40001`. Cada bloque va
en su propia PR con migración, `--verify` y read-back, y se mide antes y
después con `just db-cpu production` y `pg_stat_statements`:

1. **Higiene de RLS e índices.** 58 políticas reevalúan `auth.uid()` /
   `current_setting()` por fila (envolverlas en `(select …)` sin cambiar
   semántica); 45 políticas permisivas duplicadas por rol/acción
   (`email_push_subscriptions` 7, `product_gama_overrides` 7,
   `customer_addresses` 4, catálogo y `website_*`); 593 FKs sin índice en
   `public` (indexar las tablas calientes: `messages`, `conversations`,
   `erp_notifications`, `smart_tasks`, `smart_task_job_items`,
   `mechanic_jobs`, `sales_invoices`, `employees`); 11 índices duplicados.
   Los 450 índices sin uso sólo se listan con tamaño y costo de escritura;
   no se borran sin decisión del dueño. Releer el advisor antes de tocar.
2. **Realtime.** `list_changes`: 2,07 M llamadas, 2 711 min de CPU, 78 ms por
   sondeo, ~85 sondeos por minuto; 20 suscripciones (`messages` 2,
   `erp_notifications` 2, `sales_invoices` 2, `sales_payments`,
   `purchase_invoices`, `purchase_payments`, `mechanic_jobs`,
   `stock_adjustments`, `mechanic_job_tasks`, `conversations`). Inventariar
   cada `postgres_changes` en `lib/`, dejar sólo lo que la pantalla abierta
   necesita y mover notificaciones y contadores a broadcast desde triggers,
   como ya hace `financial_projection`.
3. **Polling del ERP.** `smart_tasks` 118 900 llamadas a 63 ms (125 min),
   `smart_task_job_items` 116 908 a 19 ms, `smart_task_user_state` 116 881;
   `erp_notifications` en tres variantes de ~142 k llamadas (la de 17 ms
   suma 40 min): un cliente preguntando cada 20–40 s. Quitar los ciclos o
   ponerles backoff con la ventana inactiva; usar Realtime donde ya hay
   suscripción.
4. **Mensajería.** `conversation_unread_counts` 1 862 ms de media (1 661
   llamadas), listado de `messages` 2 098 ms (631) y otra de `messages`
   249 ms (4 058); `mechanic_job_service_warranty_view` 197 ms; `employees`
   77 ms × 12 334. Contador materializado o índices, objetivo < 50 ms.
5. **Housekeeping.** `invoke_transactional_email_worker`,
   `invoke_mercadopago_preference_worker` y `recover_whatsapp_outbox_v1` a
   52–58 ms por minuto cada uno; limpieza de `net._http_response` 21 ms ×
   96 804; `cron.job_run_details` 216 k filas / 42 MB sin purga;
   `net._http_response` 55 MB. Purga programada (conservar 7 días) y salida
   temprana de los tres workers cuando no hay cola.
6. **`raise … errcode '40001'` restantes** en
   `20260829160000_supply_need_refinement_modes.sql` (siete `using errcode =
   '40001'`, líneas 263–1200): revisar cada uno con la regla de arriba
   —`40001` sólo cuando repetir la misma transacción puede tener éxito— y
   reclasificar los que sean rechazos de negocio.

### Bloque 1 — higiene de RLS e índices (2026-09-16)

Migraciones `20260916000100_rls_hoist_stable_calls_and_permissive_policy_hygiene`
y `20260916000200_hot_fk_indexes_and_duplicate_index_cleanup`, cada una con su
`verify_*.sql` al lado (corridos contra producción **antes** del deploy y
exigiendo el fallo, y después exigiendo el paso). Generadas mecánicamente
desde el catálogo de producción (`pg_policies`, `pg_constraint`,
`pg_stat_user_indexes`) el 2026-09-15; la evidencia del antes vive en el PR.

**La causa que el advisor no nombra.** Sus 58 `auth_rls_initplan` cuentan
sólo `auth.<fn>()` y `current_setting()`. El costo real por fila estaba en
`user_tenant_id()`: una función SQL `STABLE SECURITY DEFINER` con una
subconsulta a `user_profiles`, que aparecía **441 veces** en 687 políticas
de 293 tablas sin `(select …)`, de modo que cada fila leída la ejecutaba de
nuevo. Junto con `auth.uid()` (66), `erp_member_tenant_id()` (26),
`current_erp_employee_id()` (18), `worker_portal_*` (9) y `current_setting`
(2), 487 políticas evaluaban por fila algo que es constante por sentencia.
Todas esas funciones son `STABLE` (`pg_proc.provolatile = 's'`), así que
`tenant_id = (select user_tenant_id())` es exactamente equivalente y se
evalúa una vez como initplan. La migración reescribe 473 políticas con
`ALTER POLICY` y crea 21 ya envueltas.

**Duplicados permisivos: 45 hallazgos, 36 resueltos, 9 dejados a propósito.**
- 16 eran duplicados puros —una política `SELECT` idéntica a una `FOR ALL`
  para los mismos roles— en `email_push_subscriptions` (7),
  `product_gama_overrides` (7), `spec_facts`, `spec_fact_values` y
  `online_shipping_rate_tiers`: se borra la `SELECT`.
- 14 eran el trío del catálogo público (`X_select` para `public` +
  `public_X_select` para `anon` + `public_X_select_authenticated`) en
  `categories`, `featured_products`, `product_brands`, `product_categories`,
  `products`, `website_banners` y `website_content`. Para `anon` la política
  de tenant nunca acertaba (`user_tenant_id()` es null sin sesión) pero se
  evaluaba fila por fila en cada lectura anónima de la tienda: `X_select`
  pasa a `authenticated` y absorbe con `OR` la variante autenticada; la de
  `anon` no cambia.
- `website_navigation` (1) y `sales_invoices` (1): la política pública pasa
  a `anon` y la autenticada absorbe la otra con `OR`; la política legada
  «Customers can view their own invoices» (`customer_id = auth.uid()`) se
  conserva dentro del `OR` porque nada demuestra que sea letra muerta.
- 4 `FOR ALL` que tapaban una `SELECT` más amplia (`business_sites`,
  `journal_entries`, `journal_lines`, `spec_definition_values`) se parten en
  `INSERT`/`UPDATE`/`DELETE`; la `SELECT` queda sola porque el cuerpo de
  `can_edit_tenant_settings` y `can_manage_tenant_accounting` exige lo mismo
  que `is_active_tenant_member` más un rol, y `tenant_id = user_tenant_id()`
  está contenido en `(tenant_id is null) or …`. Con 6 390 filas en
  `journal_lines`, eso es una llamada `SECURITY DEFINER` menos por fila.
- Se dejan tal cual las 8 parejas staff/cliente de `customer_addresses`,
  `bikes`, `mechanic_jobs`, `online_orders`, `online_order_items` y la pareja
  de `website_blocks`: `supabase/tests/auth_tenant_provisioning_hardening.sql`
  y `supabase/tests/website_editor_read_authority.sql` fijan ese conjunto de
  políticas por nombre como contrato, y fusionarlas no ahorra ninguna
  llamada (las dos ramas se evalúan igual dentro del `OR`).

**Índices.** 32 índices btree para las FKs sin cobertura de las tablas
calientes (`messages` 3, `conversations` 3, `smart_tasks` 10,
`mechanic_jobs` 5, `sales_invoices` 3, `smart_task_user_state` 2, y una en
`bug_reports`, `customer_addresses`, `employees`, `erp_notifications`,
`message_reactions`, `smart_task_job_items`). Ninguna de esas tablas pasa de
906 filas vivas hoy, así que no mueven CPU: existen para que un borrado en
`auth.users` o en la tabla referenciada no recorra la hija bajo lock cuando
crezcan, y aparecerán en la próxima lista de «índices sin uso» hasta que
haya tráfico que los use. De los 11 grupos duplicados se borra el índice sin
scans de cada par; `products_tenant_id_id_key` y `suppliers_tenant_id_id_key`
son constraints UNIQUE cuyo gemelo (`uq_*`, índices únicos sin constraint)
carga las 17 y 19 FKs respectivamente, así que cae el que no tiene
dependientes (la primera versión del read-back esperaba 16 y 18 porque contó
como «propio» un constraint que el índice `uq_*` no tiene: el deploy aplicó
el bloque, el read-back falló en esa aserción y el stamp se registró en la
segunda pasada, idempotente, con el número corregido);
`uq_purchase_invoices_tenant_id_id` es un índice único sin constraint y su
gemelo lleva las 3 FKs. Los 450 índices sin uso (19,3 MB en total; el mayor
`products.idx_products_embedding`, 9,9 MB; los de mayor costo de escritura
son los diez de `mechanic_jobs`, 1 200 escrituras en la ventana) están en
`docs/development/supabase-load-2026-09-15/unused-indexes.csv` con tamaño,
escrituras de la tabla y definición; no se borra ninguno sin decisión del
dueño.

**Ensayo y prueba semántica.** Antes del deploy se replicó el catálogo de
políticas de producción en la base local (267 de 293 tablas existen ahí) y
se corrió la migración dos veces (idempotencia). La equivalencia se prueba
con conteos visibles por rol —`set local role anon`, y `authenticated` con
`request.jwt.claims` del dueño y de un cliente de la tienda— sobre las 51
tablas afectadas, antes y después: deben ser idénticos.

**Antes / después.** Desplegado el 2026-09-16 00:05–00:15 UTC; ambas
migraciones `APPLIED`; `scripts/db/health.sh production` en verde; los
conteos visibles por rol idénticos en las 51 tablas.

| Advisor de rendimiento | antes | después |
| --- | ---: | ---: |
| `auth_rls_initplan` | 58 | 0 |
| `multiple_permissive_policies` | 45 | 9 (los dejados a propósito) |
| `unindexed_foreign_keys` | 594 | 562 (0 en las tablas calientes) |
| `duplicate_index` | 11 | 0 |
| `unused_index` | 450 | 460 (+32 nuevos sin tráfico aún, −10 duplicados sin scans, y otros que empezaron a usarse) |

`pg_stat_statements`, media por sentencia: «antes» es la media acumulada
desde el 2026-08-30 (17 días, todas las horas); «después» es la media del
intervalo 23:49–00:16 UTC posterior al deploy, con tráfico nocturno, así que
la comparación es indicativa hasta medir 24 h completas.

| Sentencia (rol) | llamadas en el intervalo | media antes | media después |
| --- | ---: | ---: | ---: |
| Realtime `list_changes` (`supabase_admin`) | 2 596 | 78,2 ms | 9,4 ms |
| `smart_tasks` (poll del ERP, `authenticated`) | 109 | 63,2 ms | 6,0 ms |
| `erp_notifications` variante de 17 ms | 162 | 17,0 ms | 2,0 ms |
| `erp_notifications` variantes de 2 ms | 162 + 162 | 1,9 / 2,1 ms | 0,6 / 0,5 ms |
| `employees` listado (`authenticated`) | 27 | 76,1 ms | 7,7 ms |
| `get_checked_in_employees()` | 27 | 27,6 ms | 2,3 ms |

Por qué `list_changes` también baja: Realtime evalúa las políticas RLS de
cada tabla suscrita por cada suscriptor en `realtime.apply_rls`, así que el
`user_tenant_id()` por fila también le costaba a él. El bloque 2 sigue siendo
necesario: 2 596 sondeos en 27 minutos son ~96 por minuto, y el objetivo del
dueño es bajar la frecuencia, no sólo el costo de cada uno.

`supabase/manual_checks/diagnostics/cpu_pressure_profile.sql` (`just db-cpu`)
measures all of it: execution time by role and by statement, calls per hour,
live activity, rollbacks, replication-slot lag, seq-scan pressure, bloat, the
backup schedule, the worker runtimes, pg_cron run history, pg_net responses
and live Realtime subscriptions. Read §12d and §5 first; then §2/§3. Trailing
sections read the `cron`, `net` and `realtime` schemas and may stop on a
permission error without invalidating the earlier ones.

## Authorized production writes

Production writes must already be in task scope and satisfy the policy
contract. A **standalone migration** means one immutable, uniquely versioned
`supabase/migrations/YYYYMMDDHHMMSS_slug.sql` file containing the complete
forward change. It never means a fragment copied from `core_schema.sql`, an ad
hoc SQL Editor paste, or an unversioned file under `supabase/sql/`.

Encode exact definition and business-invariant checks in one or more read-only
SQL files that fail at SQL level when the expected state is absent. Then use the
single apply → verify → stamp command:

```bash
VINABIKE_DB_WRITE_CONFIRM=production \
  scripts/db/deploy_migration.sh \
  --migration supabase/migrations/YYYYMMDDHHMMSS_change_name.sql \
  --verify supabase/manual_checks/verification/YYYYMMDDHHMMSS_change_name.sql
```

That wrapper refuses non-migration paths and duplicate/legacy version formats,
applies only the standalone file through `query.sh`, runs every verification
read-only, registers the exact version through the guarded CLI, reads the stamp
back, and writes a secondary ignored receipt under
`.tmp/db/migration-receipts/`. If deployment succeeds but verification fails,
the version intentionally remains unregistered until the live state is
diagnosed and this same idempotent path completes.

At any time, ask production—not a file comment—whether one or more candidates
are stamped:

```bash
scripts/db/migration_status.sh \
  supabase/migrations/YYYYMMDDHHMMSS_change_name.sql
```

`APPLIED` means the exact version exists in
`supabase_migrations.schema_migrations`; `NOT_APPLIED` means it does not. A
successful SQL exit without that row is an incomplete deployment, not a
finished migration. Migration repair remains a history-metadata operation, not
a schema deployment path.

Every schema change needs the unique standalone forward migration. Do not edit
an applied migration. `core_schema.sql` is merely an incomplete historical and
best-effort local reference; mirroring there is optional and never a deployment
gate. The migration file may describe intended verification, but its production
status comes only from remote migration history. A local pass is not a
production deployment.

Historical migrations are not a replayable baseline, so CLI migrations are
intentionally disabled in `supabase/config.toml`. Until a clean forward
migration stream is enabled, deploy the reviewed standalone file through the
guarded wrapper above. `supabase db push`, `migration up`, SQL Editor and
`core_schema.sql` are not deployment paths.

## Production compatibility: no schema-copy substitute

Do not run `scripts/db/production_validation.sh` as an implementation or
release gate. It is retained only so old evidence remains interpretable. Run
focused pgTAP against the disposable local database, then inspect the live
production target directly with bounded read-only queries through
`scripts/db/query.sh production`. Confirm migration history, exact signatures,
columns, dependencies, effective ACLs, reference catalogs, materialized state
and relevant invariants. A property introduced by an undeployed migration stays
explicitly unverified until authorized deploy plus executable live read-back;
never replace that gap with a schema-only restore.

## Supabase CLI: wrapped control plane/metadata only

Examples:

```bash
scripts/supabase_cli.sh projects list --output json
scripts/supabase_cli.sh secrets list \
  --project-ref xzdvtzdqjeyqxnkqprtf
scripts/supabase_cli.sh functions deploy FUNCTION_NAME \
  --project-ref xzdvtzdqjeyqxnkqprtf
scripts/supabase_cli.sh backups list \
  --project-ref xzdvtzdqjeyqxnkqprtf
```

Use `--no-verify-jwt` only when the reviewed function intentionally implements
its own authentication, such as a verified webhook. After a function
deployment, invoke the affected path and verify logs/behavior.

**2026-08-14 — local Edge bundler fallback.** If a reviewed function passes
`deno check` but the wrapped deploy fails before upload with
`failed to open eszip ... output.eszip`, repeat the same wrapped command with
`--use-api`. That flag moves bundling to Supabase's API and avoids the broken
local temporary eszip path; it does not relax project identity or function
authentication. Read back the resulting active version and exercise the real
endpoint before treating the deployment as complete.

For hosted outages, first compare the wrapped project-list result, project DNS,
and the Auth health endpoint. A healthy hosted project plus a failed local
status is a local Docker issue. Backup and recovery operations follow
`docs/runbooks/DATABASE_BACKUP_AND_RESTORE.md`.

## Auth, RLS, and REST checks

SQL catalog checks cannot prove an authenticated user's RLS behavior. Use a
dedicated synthetic user and tenant through the real client/REST path. A secret
key or SQL Editor session bypasses RLS and cannot be cited as proof of tenant
isolation.

Use privileged REST only when the behavior under test is explicitly an admin
consumer. Use that consumer's own approved secret (the local-maintenance key
for local agent work), load it without printing it, limit the request to the
required columns/tenant, then unset it.

**2026-08-27 — legacy writes cannot own new evidence or race a decision.**
When an additive migration must keep an older client writing a shared table,
every new actor/timestamp/version column remains server-owned: the row guard
normalizes it on `INSERT` and preserves or derives it on `UPDATE`, even when
the legacy route itself stays authorized. RLS saying who may update a row does
not stop that actor from spoofing newly added audit columns. Likewise, a
read-then-write conflict check is not a concurrency guarantee. If two commands
decide ownership of the same business identities, take deterministic
transaction-scoped locks for those identities before checking and writing.
Every participating command must acquire shared business-identity locks and
row locks in the same global order; sorting only the identities inside one
helper does not prevent a cycle if another path already holds its task row.
The minimum regression must exercise a forged legacy write against a row that
provably exists and verify the lock is reached before task-row locking on every
command path that can make the decision.

## Autonomous finish checklist

Agents complete these steps themselves when they are in scope and authorized:

- environment and linked-ref preflight;
- credential-presence checks;
- local startup and affected tests;
- guarded production inspection;
- guarded deployment and migration registration;
- exact live read-back, health checks, and application smoke; and
- cleanup of disposable databases/processes while retaining ignored evidence.

Ask for human intervention only for missing provider access, billing/MFA/legal
UI, ambiguous target or authorization, destructive scope expansion, or a
failed gate requiring a business decision. Do not hand the user routine SQL,
tests, or deployment commands to run on the agent's behalf.


**2026-09-06 — serializar wrappers que aseguran el stack local.** Dos procesos
`query.sh local`/`db-test` simultáneos pueden competir por
`.tmp/db/ensure-local.lock/owner`: se observó `No such file or directory` al
crear owner tras liberar el lock desde otro proceso. Hasta corregir el owner
del lock, ejecutar esos wrappers de forma secuencial; las pruebas Flutter y
lecturas remotas independientes pueden correr a la vez. No confundir ese fallo
de arranque con un error del SQL. Costó una consulta repetida, sin mutaciones.
