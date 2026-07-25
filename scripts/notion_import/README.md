# Notion Workshop Import Quarantine

The historical `notion_pegas_sync.py` flow is disabled. It targeted an obsolete
Supabase project, auto-created related records, and wrote customers and
mechanic jobs through separate direct requests without a reviewed atomic
aggregate contract.

Do not restore its credentials or change the project URL to make it run.

If Notion import is needed, the agent must build a tracked replacement that:

- follows `docs/development/SUPABASE_WORKFLOW.md`;
- validates the exact production or loopback target before loading a secret;
- previews and validates every mapped record before mutation;
- writes through a tenant-scoped, idempotent workshop aggregate RPC;
- preserves bike, customer, inventory, accounting, and audit evidence; and
- proves replay, partial-failure, tenant-isolation, and read-back behavior in
  focused tests.

Agents perform the routine implementation and validation. Human intervention
is limited to unavailable Notion access or an irreversible mapping/business
decision.
