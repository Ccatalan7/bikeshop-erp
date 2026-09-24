# Security Contract

- Never place credentials in source, documentation, screenshots, logs, launch configurations or chat.
- Private Supabase values belong in macOS Keychain, Windows Credential Manager,
  or a protected one-command/CI environment—never `.env`. Other local-only
  credentials may use an owner-only ignored `.env` only when their consuming
  tool has not yet moved to an operating-system store.
- CI values belong in the matching protected GitHub Environment.
- Run `just verify-fast` before commit; GitHub runs a complete-history-aware commit-range secret gate.
- Production database/service credentials are never used by browser E2E or fixtures.
- Rotate a suspected credential first, verify its consumers, then sanitize HEAD/history.
- Do not print secret values while diagnosing authentication.

The incident baseline and remaining historical-remediation work are recorded in `SECURITY_REMEDIATION_2026-07-12.md`. Moderate dependency advisories without a safe upstream fix are recorded and reviewed; high or critical advisories fail the gate.

## Public catalog response boundary

**2026-09-23 finding:** published `public.products` rows exposed `cost` and
`supplier_name` through both the anonymous table grant and the authenticated
customer path. Public catalog functions also declare a `cost` result column,
but their live projection returned `0::numeric` in the initial read-back.

**2026-09-24 production read-back:** migrations `20260923180000`,
`20260923190000`, and `20260924020000` are applied. `anon` can select the
storefront columns but cannot select `cost` or `supplier_name`.
`authenticated` retains those column grants for staff, while the live
`products_select` policy restricts reads to
`tenant_id = user_tenant_id()`; the published-products policy applies only to
`anon`. This closes the grant and RLS paths identified above by inspection of
the effective permissions and policies. The public-function guard migration is
also recorded as applied. A real non-staff customer token was not exercised in
this read-back, so that end-to-end check remains distinct from the permission
and policy verification.

Audit public catalog exposure as one boundary: table grants, RLS, function
execution grants, and every public function's returned columns. A later change
to a public function's internal projection could expose its declared `cost`
column even though the present projection supplies zero.
