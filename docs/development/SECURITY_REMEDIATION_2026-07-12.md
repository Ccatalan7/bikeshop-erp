# Credential Exposure Remediation — 2026-07-12

**Status:** containment in progress; production rotations are performed provider by provider with before/after checks.

## Evidence snapshot

- Repository visibility: public.
- GitHub secret-scanning alerts at discovery: 9 open (7 Google API-key alerts, 2 legacy Supabase service-key alerts).
- Redacted Gitleaks baseline: 111 historical findings and 105 working-tree findings.
- Literal consumer inventory: 19 distinct fingerprints across 54 current occurrences. No value is recorded in this document.
- Recoverable offline baseline: owner-only Git bundle, worktree/index patches, untracked archive, manifest, and checksums under `/Users/Claudio/Dev/bikeshop-erp-secure-backups/phase0-20260712-133941`.
- After containment: zero Gitleaks findings in tracked working-tree files. The remaining local-only finding is the ignored `.env` Supabase anonymous/publishable value.
- Alert classification: the three Google keys reported only in generated Firebase web/iOS/Android client configuration were resolved as intentional public client identifiers. Six alerts remain open: four historical `GEMINI_API_KEY` exposures and two legacy Supabase service-key exposures. They remain open until provider rotation/disablement is proven.

## Completed containment

- Installed Gitleaks 8.30.1 and added redacted repository scanning configuration, exact public-client-key exceptions, a local check script, and a required GitHub workflow for new commits.
- Removed tracked token outputs, scratch diagnostics, temporary data exports, and local VS Code credentials; the local ignored launch configuration remains available on this machine.
- Removed plaintext production fallback credentials from `.github/copilot-instructions.md` and replaced them with operating-system credential-store procedures.
- Converted legacy Zoho/Odoo/Notion/Supabase import and maintenance scripts to environment-only credentials.
- Removed hardcoded shared-login credentials from seed scripts and required dedicated environment variables.
- Removed hardcoded Supabase elevated keys from maintenance/SEO scripts and the historical SQL baseline.
- Moved the Cloudflare worker's Supabase key to a worker binding. Updated Wrangler from 4.60.0 to 4.110.0: npm audit improved from 4 high vulnerabilities to 0, and the worker dry-run passes.
- Verified the existing independently managed Supabase `sb_secret_...` key with REST HTTP 200, stored it in macOS Keychain, and installed it as protected GitHub secret `SUPABASE_SECRET_KEY`.
- Stored the existing independently managed Supabase publishable key in macOS Keychain.
- Rotated the production database password through the Management API after proving there was no runtime consumer. Management API returned 200; direct PostgreSQL login and linked-CLI tenant count (10) passed afterward.
- On 2026-07-25, found that Supabase CLI telemetry traces had captured the
  then-current modern secret key in request metadata. Disabled CLI telemetry
  globally, added the tracked `scripts/supabase_cli.sh` no-telemetry boundary,
  split the shared key into independently named local-maintenance and GitHub
  storefront keys, validated both through read-only production REST requests,
  updated macOS Keychain and the protected GitHub secret, revoked the exposed
  `default` key as compromised, and permanently removed the seven affected
  local trace files. The Supabase CLI home and trace directories are now
  owner-only. No secret values are recorded here.

## Rotation matrix

| Credential family | Current state | Required completion |
|---|---|---|
| Supabase database password | Rotated and verified | Copy to other authorized machines through the approved credential manager only when direct PostgreSQL is required. |
| Supabase new secret keys | Rotated and split by consumer on 2026-07-25 | Keep local maintenance and GitHub storefront credentials independent; use guarded credential stores only, never CLI key-list output or trace logs. |
| Legacy Supabase `service_role` JWT | Compromised, still enabled | Migrate and deploy all Edge Functions to the new secret-key path on staging, verify production, then disable the legacy key. |
| Legacy Supabase `anon` JWT | Public client key, still active | Rebuild all clients with the new publishable key, verify Auth/REST/Realtime/Storage on every surface, then disable legacy keys. |
| Zoho OAuth clients/refresh tokens | Removed from source; validity unknown | Identify the active OAuth client and Supabase/DB consumers, issue replacement token, verify imports/OAuth, then revoke exposed refresh tokens. |
| Odoo API keys | Two exposed fingerprints removed from source | Identify the owning Odoo users, create least-privilege replacements, verify read/import tasks, revoke both old keys. |
| ERP shared debug login | Removed from tracked launch configuration; password unchanged | Create a dedicated limited E2E user, update local/CI test credentials, coordinate coworker sign-in, then rotate the shared password. |
| Google/Firebase client keys | Expected in generated client configuration | Verify both API and application restrictions; retain only keys needed by the corresponding web/iOS/Android app. |
| Historical Gemini/Google server key | Removed from current client source | Compare provider key inventory and usage; rotate/delete any unrestricted or formerly client-embedded key. Gemini runtime remains server-side. |
| Historical WhatsApp token | Present in historical documentation | Compare with the active Supabase secret fingerprint, stage a replacement, verify messaging/webhook operations, then revoke if matched or still valid. |

## Rotation protocol

For each pending provider:

1. Record all consumers and the current non-secret health check.
2. Create the replacement without revoking the old value.
3. Store the replacement in Keychain/credential manager and protected CI/provider secret stores.
4. Update code/configuration to the replacement variable and test locally/staging.
5. Deploy one controlled consumer group and run functional before/after checks.
6. Move remaining consumers, confirm provider usage/logs, then revoke the old value.
7. Re-run Gitleaks and provider-specific smoke tests; record evidence here.

Never rotate the legacy Supabase JWT signing secret as a shortcut. The safe route is to migrate clients to publishable keys and elevated consumers to independently managed secret keys before legacy disablement.

## Final security gate

Phase 0 is complete only when:

- every provider row above is either rotated/revoked or proven intentionally public and restricted;
- all nine GitHub alerts are resolved with evidence;
- redacted full-history Gitleaks passes after the coordinated history rewrite;
- all authorized machines use fresh clones and credential stores;
- ERP login, Firebase sites, Supabase Auth/REST/Realtime/Storage/Functions, Cloudflare worker, Zoho/Odoo import tools, messaging, inventory, and accounting smoke checks pass.

## Official references

- [Supabase API key types and new-key rotation](https://supabase.com/docs/guides/getting-started/api-keys)
- [Supabase legacy key migration guidance](https://supabase.com/docs/guides/troubleshooting/rotating-anon-service-and-jwt-secrets-1Jq6yd)
- [Supabase database password reset](https://supabase.com/docs/guides/troubleshooting/how-do-i-reset-my-supabase-database-password-oTs5sB)
- [Google API-key restrictions](https://docs.cloud.google.com/docs/authentication/api-keys)
- [Zoho OAuth token revocation](https://www.zoho.com/accounts/protocol/oauth/revoke-refresh-token.html)
- [GitHub sensitive-data remediation](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/removing-sensitive-data-from-a-repository)
