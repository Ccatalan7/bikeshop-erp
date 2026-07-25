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
