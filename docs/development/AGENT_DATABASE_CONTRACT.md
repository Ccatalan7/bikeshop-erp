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

| Autonomous | Requires the owner's explicit go-ahead in the task |
|---|---|
| Guarded reads on `local` and `production` | Any `--write` (the write guard exists to make this deliberate) |
| `just db-test`, `just db-gate`, pgTAP | Migration-history registration (`migration repair`) |
| `db-trace`, `db-fingerprint`, `db-drift`, `db-health`, `db-smoke` | Mutating probes on production, even in `BEGIN`/`ROLLBACK` |
| `production_validation.sh prepare/reuse/test` | `production_validation.sh refresh` (forced redump) |
| Control-plane reads: `projects list`, `secrets list`, `backups list` | Secret removal, function deletion, Edge Function deploy |
| Reading a hosted PII column by explicit name | `--allow-pii` (star projection over a sensitive table) |
| Anything on `staging` | Staging is dormant; only the owner reactivates it |

### Production completion is part of database ownership

Standing owner authorization recorded on 2026-07-29: when an implementation
task creates or changes a production-bound forward migration/query, deploying
that exact reviewed change through the guarded production workflow, verifying
it live, and registering its migration version are part of completing the same
task. A second routine confirmation is not required unless the task explicitly
says `local-only`, `draft`, or `no production writes`.

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
redump). An authorized write is always prefixed with
`VINABIKE_DB_WRITE_CONFIRM=…`, which matches no pre-approved pattern and
therefore always surfaces for confirmation. Keep that property when editing the
allowlist: pre-approve read verbs, never the write confirmation.

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

Every invocation appends one line to `.tmp/db/journal.jsonl`: timestamp,
environment, read/write mode, SQL SHA-256, format, caps, duration, and exit
status. No SQL text, no values, no credentials. The file is git-ignored evidence,
not a deliverable.

## Schema changes

Two artifacts, always, in the same task:

1. a unique idempotent forward migration in `supabase/migrations/`; and
2. the same final objects/logic mirrored in idempotent
   `supabase/sql/core_schema.sql`.

`core_schema.sql` is the bootstrap mirror. It is never proof of the live
deployed schema, and it is never applied wholesale to production. The full
deployment, read-back, and registration contract is in `STAGING_SUPABASE.md`
("Production change contract"); the commands are in `SUPABASE_WORKFLOW.md`
("Authorized production writes").

## Credentials

Check presence, never print values, connection strings, or credential-bearing
commands. Sources and per-consumer scope are in `SUPABASE_WORKFLOW.md`
("Credentials and what each one does"). A publishable/anon key is public client
identity and does not bypass RLS; a secret key is privileged and is never an
ordinary test identity.
