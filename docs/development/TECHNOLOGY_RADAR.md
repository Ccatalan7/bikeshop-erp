# Technology Radar

Last reviewed: 2026-07-12

| Ring | Capability | Decision | Evidence / next review |
|---|---|---|---|
| Adopt | FVM + Flutter 3.38.5 | Reproducible Flutter SDK on Mac/Windows | Proven by Mac doctor; review monthly |
| Adopt | Volta + Node 24 LTS | Reproducible Node/npm and supported Firebase CLI runtime | Proven by Mac doctor; review monthly |
| Adopt | uv + Python 3.12 | Lock and recreate invoice-parser service | Import smoke passed; review monthly |
| Adopt | just | One cross-platform project command surface | Recipes and doctor proven on Mac; Windows proof pending |
| Adopt | Gitleaks | Reject newly committed credentials | Local and GitHub checks active; review quarterly |
| Adopt | actions/checkout v7 | Use the supported Node 24 GitHub Action runtime | Official v7.0.0 release reviewed; all workflows upgraded after CI deprecation warning |
| Trial | Playwright | Browser workflow regression on Firebase preview/staging | Pinned; critical E2E suite pending |
| Trial | New Supabase publishable/secret keys | Replace legacy JWT keys without breaking Edge Functions | Staging migration pending |
| Hold | Direct production deployment helpers | Bypass governed promotion and rollback evidence | Replace before further use |
| Retire | Tracked venv/cache/screenshot archives | Generated or personal state, not source | Removed from Git tracking in cleanup batch 1 |

Entries move rings only with representative test evidence under `UPGRADE_POLICY.md`.

`.github/workflows/technology-radar.yml` runs weekly and updates one living GitHub issue from official Node/npm registries. It proposes reviews only; it cannot change dependencies or deploy production.
