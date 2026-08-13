# AI Assistant Gateway Rollout

The server-owned AI assistant remains disabled in Flutter until every gate in this document has been
read back. Local source and provider tests are not evidence that production can execute an ERP tool.

## Closed runtime boundary

- Flutter sends one user message, an opaque thread/request UUID and at most 20 already-authorized
  workshop row UUIDs. It never sends tenant, role, permissions, model ID, provider, tools or
  transcript history.
- The Edge Function resolves the caller again and performs every advertised ERP read with the caller
  JWT plus the public publishable key.
- Each advertised read/context RPC also enforces a database-side 4.5 second `statement_timeout`;
  aborting the HTTP request is not a substitute for cancelling work inside PostgreSQL.
- Run admission/replay uses the caller JWT; the database derives `auth.uid()`, tenant and authority
  fingerprint and enforces the hard quotas. The caller never supplies those authority fields.
- Post-admission ledger mutations retain the original caller JWT. Edge adds a server-only HMAC
  attestation to one of four fixed `v2` RPCs in the exposed `assistant_runtime` schema. The envelope
  binds the exact operation, caller, tenant, authority fingerprint, run, lease, fence, canonical
  body byte length, key id, audience, UUIDv4 nonce and a 60-second `iat`/`exp` window. PostgreSQL
  re-derives the caller authority, verifies the Vault-backed key, consumes the nonce under the first
  transaction lock and returns only an exact cached response for a byte-identical replay. A changed
  body/binding/MAC with the same nonce is denied. That exact-response receipt expires after at most
  15 minutes; later recovery uses the caller-bound `clientRequestId` run replay, not a long-lived
  mutation attestation. There is no custom runtime JWT, database role, `service_role` path or direct
  table DML grant.
- Authenticated callers can resolve only the four three-text-argument `v2` wrappers. Internal
  verifier, canonicalizer, legacy typed mutators, key metadata, nonce receipts and
  `vault.decrypted_secrets` remain closed. Run admission still occurs only through the caller-bound
  public RPC, and purge remains owner/scheduler-only.
- Provider continuations, thinking/signatures and raw tool payloads remain request-local. The ledger
  stores canonical visible messages, terminal cards, usage/cost and HMAC receipts only.
- Provider usage is normalized according to each provider's billing semantics before it reaches
  pricing or quota checks. In particular, Gemini `toolUsePromptTokenCount` is input and
  `thoughtsTokenCount` is billable output; omitting either makes a valid thinking-model response
  look internally inconsistent and must fail a regression test. Any future positive total-token
  residual is conservatively accounted as output rather than silently dropped.
- The model may return text and propose calls. Code owns authorization, execution order,
  destinations and cards.
- A known, authorized tool call with malformed arguments is never executed. It receives a bounded
  `rejected` receipt and one model-visible schema correction result so the model can repair its own
  call in the next round. Unknown tools, unauthorized tools, invalid call identities and exhausted
  budgets still fail closed. This is structural self-correction, not phrase routing.
- Canonically attested JSON cannot contain JavaScript `undefined`. Server-built cards therefore omit
  absent optional keys before signing/persistence; tests compare their explicit object shape with
  the JSON round-trip so a card can never succeed in memory and then fail only at the durable
  completion RPC.
- General operational planning is grounded by the closed `get_business_snapshot` tool and filtered
  workshop/task reads. The snapshot contains machine-semantic scalar facts and per-source status,
  never authored advice; the model remains responsible for prioritization and explanation.

## Deployment inputs

The Edge deployment requires these secrets or server variables; values never belong in Git, shell
history, logs or this document:

- `SUPABASE_URL`
- hosted `SUPABASE_PUBLISHABLE_KEYS` (platform-provided JSON map) and, optionally,
  `AI_AGENT_SUPABASE_PUBLISHABLE_KEY_NAME`
- `AI_AGENT_RUNTIME_ATTESTATION_KID`
- `AI_AGENT_RUNTIME_ATTESTATION_KEY_HEX` (exactly 32 random bytes as lowercase hex)
- `AI_AGENT_RUNTIME_ATTESTATION_AUDIENCE`
- `AI_AGENT_AUDIT_HMAC_KEY`
- `AI_AGENT_MODEL_PRICING_JSON`
- `AI_AGENT_FAST_PROVIDER`, `AI_AGENT_DEEP_PROVIDER`, `AI_AGENT_VISION_PROVIDER`
- the selected provider key, model allowlist and per-role model variables for Gemini, OpenAI and/or
  Anthropic
- optional bounded `AI_AGENT_TIMEOUT_MS`, `AI_AGENT_MAX_OUTPUT_TOKENS`, `AI_AGENT_MAX_REQUEST_BYTES`
  and exact CORS origins
- public research uses the existing `GEMINI_API_KEY` through stateless Gemini Interactions, with
  optional `AI_AGENT_GEMINI_RESEARCH_MODEL`, bounded `AI_AGENT_GEMINI_RESEARCH_TIMEOUT_MS` and
  required `AI_AGENT_GEMINI_SEARCH_MICROUSD_PER_QUERY` (currently `14000`). The server requires an
  actual `google_search_call`/matching result and treats URL Context only as optional enrichment, so
  an enrichment failure cannot erase valid search evidence. Browser Use client scaffolding remains
  dormant: a key alone cannot activate it until the provider supplies a hard read-only action policy
  and an attestable visited-URL/action trace. Configured token/search pricing meters success,
  failure, cancellation and conservatively reserved retries on the originating tool receipt.

Generate the runtime attestation key once as 32 cryptographically random bytes. Store the lowercase
hex value in the Edge secret `AI_AGENT_RUNTIME_ATTESTATION_KEY_HEX` and, through the guarded
migration provisioning operation, in Supabase Vault. The database stores only Vault UUID, key id,
audience and bounded activation metadata. Never print or read back the key value; verify only that
Edge reports the secret name and that the database metadata points to exactly one active,
non-expired Vault entry. The key id and audience must match both stores. Never reuse
`AI_AGENT_AUDIT_HMAC_KEY`, a provider key, Supabase JWT signing material or any client-visible key.

Hosted Supabase Edge Functions receive publishable API keys through the platform-provided
`SUPABASE_PUBLISHABLE_KEYS` JSON map. Do not create `SUPABASE_PUBLISHABLE_KEY` as a hosted custom
secret: `SUPABASE_*` is a reserved namespace. The gateway selects `default` unless
`AI_AGENT_SUPABASE_PUBLISHABLE_KEY_NAME` names another safe entry and fails before traffic if the
map, name or selected `sb_publishable_*` value is invalid. Singular `SUPABASE_PUBLISHABLE_KEY` is
only a local-development fallback for `localhost`, `127.0.0.1` or `::1`; an invalid supplied map
never falls back.

The pricing JSON is a closed object keyed by each exact routed model. Each entry contains integer
`inputMicrousdPerMillionTokens` and `outputMicrousdPerMillionTokens`. A routed model without an
exact entry fails before the provider call.

## Ordered activation

1. Run repository DB preflight. Validate every AI-assistant pgTAP contract and the canonical
   bootstrap gate.
2. Prepare one production-derived compatibility session for
   `20260811170000_ai_assistant_runtime_ledger.sql` followed by
   `20260811171000_ai_assistant_read_tools.sql`, `20260811172000_ai_assistant_business_snapshot.sql`
   and `20260811173000_ai_assistant_filtered_operational_reads.sql`,
   `20260811174000_ai_assistant_general_operational_reads.sql` and
   `20260811175000_ai_assistant_task_actions.sql`, followed by
   `20260812030000_ai_assistant_public_research_usage_ledger.sql`; run all focused contracts there.
3. Inspect production authority functions, source views, RLS, grants and current migration history
   read-only. Stop on drift.
4. Apply the reviewed forward migrations one at a time through the guarded DB wrapper. Read back
   every table, FORCE RLS flag, function definition, grant, attestation metadata/nonce constraints,
   quota/lease constraint and retention schedule before registering each migration. The runtime
   catalog audit must return only the four reviewed `v2` wrappers to `authenticated`:

   ```bash
   scripts/db/query.sh production --sql "
   select namespace.nspname as schema_name,
          routine.proname as function_name,
          pg_get_function_identity_arguments(routine.oid) as arguments,
          routine.prosecdef as security_definer,
          has_function_privilege('anon', routine.oid, 'EXECUTE') as anon_baseline
   from pg_proc routine
   join pg_namespace namespace on namespace.oid = routine.pronamespace
   where namespace.nspname = 'assistant_runtime'
     and has_function_privilege('authenticated', routine.oid, 'EXECUTE')
   order by namespace.nspname, routine.proname,
            pg_get_function_identity_arguments(routine.oid)"
   ```

   Stop unless the result is exactly the four three-text-argument `v2` RPCs. Also prove
   `authenticated`, `anon` and `service_role` cannot read Vault, attestation metadata/nonces, ledger
   tables or execute any internal/v1 mutator. Source-level `REVOKE` text is not an effective-ACL
   read-back.
5. Expose `assistant_runtime` in the hosted Data API/PostgREST configuration and read it back.
   `supabase/config.toml` configures local development only; a hosted request must prove the schema
   is exposed and its cache reloaded.
6. Provision matching Edge/Vault runtime attestation key material plus the provider/pricing/audit
   secrets. Verify only names, key id, audience, active dates and the single Vault UUID
   reference—never secret values. A golden signed synthetic mutation must then prove Unicode
   canonicalization, caller binding, wrong-MAC/wrong-tenant denial and exact cached nonce replay.
7. Deploy `ai-agent-gateway` with platform JWT verification enabled.
8. Using synthetic authenticated users, smoke every advertised tool across the role matrix and two
   tenants. Prove caller-JWT headers, cross-tenant denial, verified-empty versus unavailable, card
   decoding, idempotent replay, concurrency quota, cancel and lease expiry. Include keyword-free
   filtered questions (overdue urgent work, today's unassigned tasks and my tasks) and verify that
   every navigable row card carries only its server-validated tenant-bound entity reference. If
   public research is enabled, prove the model-visible schema is exact `{}` and the worker task
   derives only from the current operator message, never history, ERP rows, tool output, tenant, JWT
   or model-authored domain/URL/locale. Verify DLP, the 70-second total egress ceiling with at most
   two independently bounded transport attempts, forced search call/result pairing, both documented
   `query`/`queries` response variants, optional URL
   enrichment, HTTPS-only sources, abort behavior and durable external usage/cost for success,
   failure and cancellation. Before production traffic, capture `EXPLAIN (ANALYZE, BUFFERS)` for
   every advertised read/context RPC query shape at representative tenant cardinalities. Their
   normalized substring matching can scan tenant rows even when source tables have tenant and
   identity indexes; the output `LIMIT` does not bound scanned input. Stop activation if any plan
   approaches the 4.5 second DB timeout, and add evidence-driven indexes or a bounded search read
   model rather than guessing a functional index in the rollout migration.
9. Prove factual parity for the today/tomorrow operational briefing. Preserve per-source
   empty/partial/unavailable semantics, but evaluate correctness and usefulness rather than exact
   wording: the model owns the response and no authored phrase router may replace its reasoning. The
   product flag remains off even if every RPC returns successfully until this evaluation passes.
10. Run the 50-case fixed evaluation against each intended provider and record tool correctness,
    unsupported refusals, latency, usage and cost. A provider route is enabled only after its own
    result passes.
11. Run the canonical macOS Debug session in light/dark mode. Verify thread continuity, reset on
    logout/tenant/permission change, cancellation of a pending turn, all seven card destinations and
    no autonavigation.
12. Build a new client session with `AI_AGENT_GATEWAY_ENABLED=true` and the public key supplied to
    Flutter as the `SUPABASE_PUBLISHABLE_KEY` Dart define. Never flip the engine inside an existing
    conversation; this client define is separate from the hosted Edge environment described above.

## Rollback and recovery

- Product rollback is `AI_AGENT_GATEWAY_ENABLED=false` in a new build/session. Do not replay a
  failed gateway turn through the legacy engine.
- Server rollback stops new function traffic/provider routing; additive ledger tables remain for
  audit/retention. Do not drop or truncate them as a routine rollback.
- A lost worker is fenced until lease expiry. A reclaimed nonterminal run is closed as
  `run_recovery_required`; it never resumes provider continuation or repeats a possibly incurred
  provider/tool step. The operator may then start a new run. An unconfirmed terminal commit returns
  `run_finalization_pending`, and the client reconciles only by replaying the same
  `clientRequestId`.
- If `pg_cron` is unavailable or the schedule was not installed, activation is blocked until a
  separately owned purge runner is verified. TTL columns alone do not delete data.
