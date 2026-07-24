#!/bin/bash

set -euo pipefail

export VOLTA_HOME="${VOLTA_HOME:-$HOME/.volta}"
export PATH="$VOLTA_HOME/bin:$PATH"

REPO='Ccatalan7/bikeshop-erp'
WORKFLOW='macos-release.yml'
MESSAGE=''
NO_WAIT='NO'
REQUIRE_CONFIRMATION='NO'
PREFLIGHT_ONLY='NO'

while [[ $# -gt 0 ]]; do
  case "$1" in
    --message)
      MESSAGE="${2:?--message requires a value}"
      shift
      ;;
    --no-wait)
      NO_WAIT='YES'
      ;;
    --require-confirmation)
      REQUIRE_CONFIRMATION='YES'
      ;;
    --preflight-only)
      PREFLIGHT_ONLY='YES'
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 64
      ;;
  esac
  shift
done

step() {
  printf '\n[macos-update] %s\n' "$1"
}

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Required command '$1' was not found." >&2
    exit 1
  fi
}

require_command git
require_command gh
require_command jq
require_command volta
require_command node
require_command npm

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

node_version="$(jq -r .node toolchain.json)"
npm_version="$(jq -r .npm toolchain.json)"
actual_node_version="$(node --version | sed 's/^v//')"
actual_npm_version="$(npm --version)"
if [[ "$actual_node_version" != "$node_version" ||
      "$actual_npm_version" != "$npm_version" ]]; then
  echo "Pinned Node/npm toolchain is unavailable." >&2
  echo "Expected Node $node_version and npm $npm_version; found Node $actual_node_version and npm $actual_npm_version." >&2
  echo "Run the macOS bootstrap, then retry the publish task." >&2
  exit 1
fi

flutter_bin="$(command -v flutter || true)"
if [[ -z "$flutter_bin" && -x "$repo_root/.fvm/flutter_sdk/bin/flutter" ]]; then
  flutter_bin="$repo_root/.fvm/flutter_sdk/bin/flutter"
fi
if [[ -z "$flutter_bin" ]]; then
  echo "Required command 'flutter' was not found in PATH or .fvm/flutter_sdk." >&2
  exit 1
fi

branch="$(git branch --show-current)"
if [[ -z "$branch" ]]; then
  echo 'Could not determine the current branch.' >&2
  exit 1
fi

step "Checking Production permission for branch: $branch"
policies="$(gh api "repos/${REPO}/environments/Production/deployment-branch-policies" --paginate)"
if ! jq -e --arg branch "$branch" \
  '.branch_policies[]? | select(.type == "branch" and .name == $branch)' \
  >/dev/null <<< "$policies"; then
  echo "Branch '$branch' is not authorized by the Production environment." >&2
  exit 1
fi

step 'Staging current Source Control changes'
git add -A
staged_files="$(git diff --cached --name-only)"
snapshot_tree="$(git write-tree)"
if [[ -n "$staged_files" ]]; then
  if [[ -z "$MESSAGE" ]]; then
    MESSAGE="chore: publish macOS update $(date '+%Y-%m-%d %H:%M')"
  fi
  printf 'Commit message: %s\nFiles to publish:\n%s\n' "$MESSAGE" "$staged_files"
else
  echo 'No uncommitted Source Control changes found; publishing current HEAD.'
fi

if [[ "$REQUIRE_CONFIRMATION" == 'YES' ]]; then
  read -r -p "Type YES to publish a macOS update from '$branch': " confirmation
  if [[ "$confirmation" != 'YES' ]]; then
    echo 'Cancelled.'
    exit 1
  fi
fi

snapshot_root="$(mktemp -d "${TMPDIR:-/tmp}/vinabike-macos-preflight.XXXXXX")"
cleanup_snapshot() {
  if [[ -n "${snapshot_root:-}" && -d "$snapshot_root" ]]; then
    rm -rf -- "$snapshot_root"
  fi
}
trap cleanup_snapshot EXIT

step "Exporting immutable staged snapshot $snapshot_tree"
git archive "$snapshot_tree" | tar -x -C "$snapshot_root"

step 'Running the local release integrity preflight on the staged snapshot'
(
  cd "$snapshot_root"
  spreadsheet_bundle_js='web/spreadsheet_engine/univer.bundle.js'
  spreadsheet_bundle_css='web/spreadsheet_engine/univer.bundle.css'
  bundle_js_hash_before="$(git hash-object "$spreadsheet_bundle_js")"
  bundle_css_hash_before="$(git hash-object "$spreadsheet_bundle_css")"
  npm ci
  npm run build:spreadsheet-engine
  if [[ "$(git hash-object "$spreadsheet_bundle_js")" != "$bundle_js_hash_before" ||
        "$(git hash-object "$spreadsheet_bundle_css")" != "$bundle_css_hash_before" ]]; then
    echo 'Pinned spreadsheet build changed the committed release assets.' >&2
    echo "Regenerate them with Node $node_version and npm $npm_version, include them in Source Control, and retry." >&2
    exit 1
  fi
  "$flutter_bin" pub get
  "$flutter_bin" analyze --no-fatal-infos --no-fatal-warnings lib test
  bash scripts/run_flutter_test_gate.sh "$flutter_bin"
  "$flutter_bin" build web --release --no-wasm-dry-run \
    --dart-define=STORE_PERF_LOGS=true \
    -t lib/main.dart \
    -o build/web_erp
)

current_index_tree="$(git write-tree)"
if [[ "$current_index_tree" != "$snapshot_tree" ]]; then
  echo 'The staged snapshot changed while the release preflight was running.' >&2
  echo 'Nothing was committed, pushed, or published. Finish the staging operation and run the task again:' >&2
  git diff --cached --name-status >&2
  exit 1
fi

cleanup_snapshot
trap - EXIT

if [[ "$PREFLIGHT_ONLY" == 'YES' ]]; then
  step 'Local macOS release preflight passed'
  echo 'Nothing was committed, pushed, or published.'
  exit 0
fi

if [[ -n "$staged_files" ]]; then
  step 'Committing staged changes'
  git commit -m "$MESSAGE"
fi

head_sha="$(git rev-parse HEAD)"
step "Pushing $branch at $head_sha"
git push origin "$branch"

triggered_at="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
step 'Triggering guarded macOS publication workflow'
gh workflow run "$WORKFLOW" \
  --repo "$REPO" \
  --ref "$branch" \
  -f publish_release=true

run_id=''
run_url=''
for _ in $(seq 1 30); do
  runs="$(gh run list \
    --repo "$REPO" \
    --workflow "$WORKFLOW" \
    --branch "$branch" \
    --event workflow_dispatch \
    --limit 20 \
    --json databaseId,headSha,createdAt,url,status)"
  run_id="$(jq -r \
    --arg sha "$head_sha" \
    --arg started "$triggered_at" \
    '[.[] | select(.headSha == $sha and .createdAt >= $started)] | first | .databaseId // empty' \
    <<< "$runs")"
  run_url="$(jq -r \
    --arg sha "$head_sha" \
    --arg started "$triggered_at" \
    '[.[] | select(.headSha == $sha and .createdAt >= $started)] | first | .url // empty' \
    <<< "$runs")"
  if [[ -n "$run_id" ]]; then
    break
  fi
  sleep 2
done

if [[ -z "$run_id" ]]; then
  echo 'The workflow was dispatched, but its run could not be resolved.' >&2
  exit 1
fi

printf 'Workflow: %s\n' "$run_url"
if [[ "$NO_WAIT" == 'YES' ]]; then
  exit 0
fi

step 'Waiting for build, verification, and publication'
gh run watch "$run_id" --repo "$REPO" --exit-status

step 'Verifying published macOS release evidence'
release_json="$(gh release list \
  --repo "$REPO" \
  --limit 30 \
  --json tagName,createdAt \
  | jq -c '[.[] | select(.tagName | startswith("macos-v"))] | first')"
release_tag="$(jq -r '.tagName // empty' <<< "$release_json")"
if [[ -z "$release_tag" ]]; then
  echo 'No published macOS release was found.' >&2
  exit 1
fi

asset_names="$(gh release view "$release_tag" --repo "$REPO" --json assets --jq '.assets[].name')"
for required_asset in \
  macos-release-manifest.json \
  macos-release-manifest.json.sig \
  install_vinabike_erp_macos.sh; do
  if ! grep -Fxq "$required_asset" <<< "$asset_names"; then
    echo "Published release is missing $required_asset." >&2
    exit 1
  fi
done
if ! grep -Eq '^vinabike_erp_macos_.*\.zip$' <<< "$asset_names"; then
  echo 'Published release is missing the macOS application archive.' >&2
  exit 1
fi

printf 'Published macOS update %s from commit %s.\n' "$release_tag" "$head_sha"
