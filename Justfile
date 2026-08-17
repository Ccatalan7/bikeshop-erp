set dotenv-load := false
set positional-arguments := true

default:
    @just --list

bootstrap:
    #!/usr/bin/env bash
    set -euo pipefail
    case "$(uname -s)" in
      Darwin) exec bash scripts/bootstrap/bootstrap_macos.sh ;;
      *) echo "On Windows run: pwsh -File scripts/bootstrap/bootstrap_windows.ps1" >&2; exit 64 ;;
    esac

doctor:
    #!/usr/bin/env bash
    exec bash scripts/dev/doctor.sh

verify-fast:
    #!/usr/bin/env bash
    exec bash scripts/dev/verify.sh fast

verify:
    #!/usr/bin/env bash
    exec bash scripts/dev/verify.sh full

db-preflight:
    #!/usr/bin/env bash
    exec bash scripts/db/preflight.sh

db-help:
    #!/usr/bin/env bash
    bash scripts/db/query.sh --help || true

db-start:
    #!/usr/bin/env bash
    exec bash scripts/db/ensure_local.sh

db-status:
    #!/usr/bin/env bash
    exec bash scripts/db/status.sh

db-test *tests:
    #!/usr/bin/env bash
    exec bash scripts/db/test.sh {{tests}}

db-gate:
    #!/usr/bin/env bash
    exec bash scripts/reset_local_supabase.sh

db-query environment query:
    #!/usr/bin/env bash
    exec bash scripts/db/query.sh "{{environment}}" --sql "{{query}}"

db-query-file environment file:
    #!/usr/bin/env bash
    exec bash scripts/db/query.sh "{{environment}}" --file "{{file}}"

db-migration-status *migrations:
    #!/usr/bin/env bash
    exec bash scripts/db/migration_status.sh {{migrations}}

db-trace environment kind id:
    #!/usr/bin/env bash
    exec bash scripts/db/trace.sh "{{environment}}" "{{kind}}" "{{id}}"

db-fingerprint environment="local":
    #!/usr/bin/env bash
    exec bash scripts/db/query.sh "{{environment}}" --file supabase/manual_checks/diagnostics/schema_fingerprint.sql

db-drift left="local" right="production":
    #!/usr/bin/env bash
    exec bash scripts/db/drift.sh "{{left}}" "{{right}}"

db-staging-schema-gate:
    #!/usr/bin/env bash
    echo "Staging schema gate is suspended: staging is not production-authoritative." >&2
    exit 64

db-smoke environment="local":
    #!/usr/bin/env bash
    exec bash scripts/db/smoke.sh "{{environment}}"

db-health environment="local":
    #!/usr/bin/env bash
    exec bash scripts/db/health.sh "{{environment}}"

e2e:
    #!/usr/bin/env bash
    echo "Staging E2E is suspended: staging is not production-authoritative." >&2
    exit 64

preview-erp *args:
    #!/usr/bin/env bash
    exec bash scripts/dev/web_preview.sh {{args}} --erp

preview-store *args:
    #!/usr/bin/env bash
    exec bash scripts/dev/web_preview.sh {{args}} --store --release

preview-store-debug *args:
    #!/usr/bin/env bash
    exec bash scripts/dev/web_preview.sh {{args}} --store

preview-stop:
    #!/usr/bin/env bash
    exec bash scripts/dev/web_preview.sh stop --all

build-erp:
    #!/usr/bin/env bash
    exec scripts/dev/flutter.sh build web --release --no-wasm-dry-run -t lib/main.dart -o build/web_erp

build-store:
    #!/usr/bin/env bash
    exec scripts/dev/flutter.sh build web --release --pwa-strategy=none -t lib/main_store.dart -o build/web_store

build-all: build-erp build-store

clean-generated:
    #!/usr/bin/env bash
    exec bash scripts/dev/clean_generated.sh
