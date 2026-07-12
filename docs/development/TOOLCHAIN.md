# Vinabike ERP Toolchain

`toolchain.json` is the machine-readable source of truth. `.fvmrc`, `.node-version`, `.python-version`, the root `package.json`, and the Cloudflare Worker lockfile implement those pins.

## Command surface

Use the same commands on every machine:

```text
just bootstrap         install missing workstation dependencies
just doctor            report blockers with exact fixes
just verify-fast       secrets plus configuration/shell checks
just verify            analyzer and all Flutter tests
just db-test [name]    reuse local Supabase and run selected/all pgTAP
just db-gate           rebuild canonical schema and run every pgTAP test
just e2e               browser regression suite
just build-all         ERP and storefront web releases
just clean-generated   preview safe generated-file cleanup
```

Daily database commands reuse the local schema and support targeted pgTAP selectors; `just db-gate` is the deliberate full rebuild. See `SUPABASE_WORKFLOW.md`.

On Windows, bootstrap and doctor are PowerShell scripts because `just` is not available until bootstrap completes:

```powershell
pwsh -File scripts/bootstrap/bootstrap_windows.ps1
pwsh -File scripts/dev/doctor.ps1
```

## Pinning rules

- Flutter is selected through FVM; do not depend on a random global Flutter.
- Node and npm are selected through Volta; use `npm ci`.
- Java 17 is the supported Android baseline.
- Python service environments are recreated with `uv sync`; never commit `venv` or `.venv`.
- Supabase, Firebase and Playwright run from the root lockfile in CI. The standalone Supabase binary remains available for local Docker workflows.
- Wrangler is isolated and pinned in `cloudflare-worker/package.json`.

Tool upgrades follow `UPGRADE_POLICY.md`; a bootstrap run must not broadly upgrade an already working machine.
