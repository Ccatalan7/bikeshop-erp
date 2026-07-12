set dotenv-load := true
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

db-test:
    #!/usr/bin/env bash
    exec bash scripts/reset_local_supabase.sh

e2e:
    #!/usr/bin/env bash
    exec npm run e2e

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
