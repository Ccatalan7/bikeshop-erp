#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO='Ccatalan7/bikeshop-erp'
WORKFLOW='macos-release.yml'
MESSAGE=''
NO_WAIT='NO'
REQUIRE_CONFIRMATION='NO'
CHECK_RELEASE_BRANCH_ONLY='NO'
PREPARED_STATE_REQUEST=''
RELEASE_NOTES_CANDIDATE_B64=''
RELEASE_NOTES_CANDIDATE_SHA256=''
RELEASE_NOTES_FROM_COMMIT=''
INTEGRITY_RUN_ID=''
INTEGRITY_RUN_ATTEMPT=''
release_notes_temp_dir=''

# shellcheck source=scripts/releases/erp_update_state.sh
source "$SCRIPT_DIR/releases/erp_update_state.sh"

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
    --check-release-branch)
      CHECK_RELEASE_BRANCH_ONLY='YES'
      ;;
    --prepared-state)
      PREPARED_STATE_REQUEST="${2:?--prepared-state requires a value}"
      shift
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

format_elapsed() {
  local elapsed="$1"
  printf '%02d:%02d' "$((elapsed / 60))" "$((elapsed % 60))"
}

assert_production_release_branch() {
  local branch="$1"
  local environment_json
  local protected_branches_only
  local custom_branch_policies

  step "Checking Production release permission for branch: $branch"
  environment_json="$(gh api "repos/${REPO}/environments/Production")"
  protected_branches_only="$(
    jq -r '.deployment_branch_policy.protected_branches // false' \
      <<< "$environment_json"
  )"
  custom_branch_policies="$(
    jq -r '.deployment_branch_policy.custom_branch_policies // false' \
      <<< "$environment_json"
  )"

  if [[ "$protected_branches_only" == 'true' ]]; then
    local encoded_branch
    encoded_branch="$(jq -rn --arg value "$branch" '$value | @uri')"
    if [[ "$(gh api "repos/${REPO}/branches/${encoded_branch}" --jq '.protected')" != 'true' ]]; then
      echo "Branch '$branch' is not authorized by the Production environment." >&2
      exit 1
    fi
    echo 'Branch is protected and authorized for Production.'
    return
  fi

  if [[ "$custom_branch_policies" == 'true' ]]; then
    local policies_json
    local policy_type
    local policy_pattern
    policies_json="$(
      gh api --method GET \
        "repos/${REPO}/environments/Production/deployment-branch-policies" \
        -f per_page=100
    )"

    while IFS=$'\t' read -r policy_type policy_pattern; do
      # GitHub Production branch policies intentionally use glob patterns.
      # shellcheck disable=SC2053
      if [[ "$policy_type" == 'branch' && "$branch" == $policy_pattern ]]; then
        echo "Branch is authorized by Production policy '$policy_pattern'."
        return
      fi
    done < <(
      jq -r '.branch_policies[]? | [.type, .name] | @tsv' \
        <<< "$policies_json"
    )

    echo "Branch '$branch' is not authorized by the Production environment." >&2
    exit 1
  fi

  echo 'Production has no deployment branch restriction.'
}

get_workflow_runs() {
  local api_output

  if api_output="$(
    gh api --method GET \
      "repos/${REPO}/actions/workflows/${WORKFLOW}/runs" \
      -f branch="$branch" \
      -f event=workflow_dispatch \
      -f per_page=30 \
      2>/dev/null
  )"; then
    printf '%s\n' "$api_output"
    return
  fi

  echo 'Direct workflow run API failed; falling back to gh run list.' >&2
  gh run list \
    --repo "$REPO" \
    --workflow "$WORKFLOW" \
    --branch "$branch" \
    --event workflow_dispatch \
    --limit 30 \
    --json databaseId,headSha,status,conclusion,url,createdAt,displayTitle \
    | jq '{
        workflow_runs: [
          .[] | {
            id: .databaseId,
            head_sha: .headSha,
            status: .status,
            conclusion: .conclusion,
            html_url: .url,
            created_at: .createdAt,
            display_title: .displayTitle
          }
        ]
      }'
}

show_workflow_failure_diagnostics() {
  local run_id="$1"
  local jobs_json
  local job_id
  local annotations_json
  local failed_jobs_summary=''
  local failed_log=''
  local flutter_gate_summary=''

  if jobs_json="$(
    gh api --method GET \
      "repos/${REPO}/actions/runs/${run_id}/jobs" \
      -f per_page=100
  )"; then
    failed_jobs_summary="$(
      jq -r '
        .jobs[]
        | select(.conclusion == "failure")
        | "Failed job: \(.name)\n"
          + (
              [.steps[]? | select(.conclusion == "failure") | "  Failed step: \(.name)"]
              | if length == 0
                then ["  Failed step: unavailable from GitHub jobs API"]
                else .
                end
              | join("\n")
            )
      ' <<< "$jobs_json"
    )"
    while IFS= read -r job_id; do
      if annotations_json="$(
        gh api --method GET \
          "repos/${REPO}/check-runs/${job_id}/annotations" \
          -f per_page=100 \
          2>/dev/null
      )"; then
        jq -r '.[]? | select(.message != null) | "  \(.message)"' \
          <<< "$annotations_json"
      fi
    done < <(
      jq -r '
        .jobs[]
        | select(.conclusion == "failure")
        | .id
      ' <<< "$jobs_json"
    )
  else
    echo 'Could not load job/annotation diagnostics; trying the failed log.' >&2
  fi

  printf '\nFailed step log:\n'
  if failed_log="$(gh run view "$run_id" --repo "$REPO" --log-failed)"; then
    tail -n 300 <<< "$failed_log" \
      | awk '
        {
          if (length($0) > 1000) {
            print substr($0, 1, 1000) " ... [line truncated]"
          } else {
            print
          }
        }
      '
    flutter_gate_summary="$(
      awk -F '\t' '
        {
          line = (NF >= 3 ? $3 : $0)
          sub(/^[0-9-]+T[0-9:.]+Z[[:space:]]*/, "", line)
          if (line ~ /^\[flutter-test-gate\] Flutter tests failed\./) {
            capture = 1
          }
          if (capture) {
            print line
          }
          if (line ~ /^\[flutter-test-gate\] Nothing was published\./) {
            exit
          }
        }
      ' <<< "$failed_log"
    )"
  else
    echo 'Could not load the failed step log; use the workflow URL above.' >&2
  fi

  printf '\nFailure summary:\n'
  if [[ -n "$failed_jobs_summary" ]]; then
    printf '%s\n' "$failed_jobs_summary"
  else
    printf 'Failed job: unavailable from GitHub jobs API\n'
    printf '  Failed step: unavailable from GitHub jobs API\n'
  fi
  if [[ -n "$flutter_gate_summary" ]]; then
    printf '%s\n' "$flutter_gate_summary"
  else
    echo '[macos-update] Nothing was published. Fix the failed step above and run the task again.'
  fi
}

download_release_asset() {
  local release_json="$1"
  local asset_name="$2"
  local asset_id

  asset_id="$(
    jq -r --arg name "$asset_name" \
      '.assets[]? | select(.name == $name) | .id' \
      <<< "$release_json" \
      | head -1
  )"
  if [[ -z "$asset_id" ]]; then
    echo "Published release is missing $asset_name." >&2
    return 1
  fi

  gh api \
    -H 'Accept: application/octet-stream' \
    "repos/${REPO}/releases/assets/${asset_id}"
}

find_published_release_run_id_for_commit() {
  local head_sha="$1"
  local stable_release_json
  local stable_manifest

  if ! stable_release_json="$(
    gh api "repos/${REPO}/releases/tags/macos-latest" 2>/dev/null
  )"; then
    return 1
  fi
  if ! stable_manifest="$(
    download_release_asset \
      "$stable_release_json" \
      'macos-release-manifest.json' \
      2>/dev/null
  )"; then
    return 1
  fi

  jq -er \
    --arg sha "$head_sha" \
    '
      select(.commit == $sha)
      | (.run_id | tostring)
      | select(test("^[0-9]+$"))
    ' <<< "$stable_manifest"
}

verify_published_release() {
  local head_sha="$1"
  local run_id="$2"
  local stable_release_json
  local stable_asset_names
  local stable_manifest
  local release_tag
  local archive_name
  local release_json
  local asset_names

  step 'Verifying the exact published macOS release'
  stable_release_json="$(gh api "repos/${REPO}/releases/tags/macos-latest")"
  stable_asset_names="$(jq -r '.assets[]?.name' <<< "$stable_release_json")"
  for required_stable_asset in \
    macos-release-manifest.json \
    macos-release-manifest.json.sig \
    install_vinabike_erp_macos.sh; do
    if ! grep -Fxq "$required_stable_asset" <<< "$stable_asset_names"; then
      echo "macos-latest is missing $required_stable_asset." >&2
      exit 1
    fi
  done

  stable_manifest="$(
    download_release_asset \
      "$stable_release_json" \
      'macos-release-manifest.json'
  )"

  if ! jq -e \
    --arg sha "$head_sha" \
    --arg run_id "$run_id" \
    '
      .commit == $sha
      and (.run_id | tostring) == $run_id
      and (.tag_name | startswith("macos-v"))
      and (.archive_name | test("^vinabike_erp_macos_.*[.]zip$"))
    ' >/dev/null <<< "$stable_manifest"; then
    echo 'macos-latest does not identify the completed workflow and source commit.' >&2
    exit 1
  fi

  release_tag="$(jq -r '.tag_name' <<< "$stable_manifest")"
  archive_name="$(jq -r '.archive_name' <<< "$stable_manifest")"
  release_json="$(gh api "repos/${REPO}/releases/tags/${release_tag}")"

  if [[ "$(jq -r '.target_commitish' <<< "$release_json")" != "$head_sha" ]]; then
    echo "Release '$release_tag' does not target commit $head_sha." >&2
    exit 1
  fi

  asset_names="$(jq -r '.assets[]?.name' <<< "$release_json")"
  for required_asset in \
    "$archive_name" \
    "${archive_name}.sha256" \
    macos-release-manifest.json \
    macos-release-manifest.json.sig \
    install_vinabike_erp_macos.sh; do
    if ! grep -Fxq "$required_asset" <<< "$asset_names"; then
      echo "Published release is missing $required_asset." >&2
      exit 1
    fi
  done

  local versioned_manifest
  versioned_manifest="$(
    download_release_asset \
      "$release_json" \
      'macos-release-manifest.json'
  )"
  if ! jq -e \
    --arg sha "$head_sha" \
    --arg run_id "$run_id" \
    --arg tag "$release_tag" \
    --arg archive "$archive_name" \
    '
      .commit == $sha
      and (.run_id | tostring) == $run_id
      and .tag_name == $tag
      and .archive_name == $archive
    ' >/dev/null <<< "$versioned_manifest"; then
    echo "Release '$release_tag' contains stale or mismatched metadata." >&2
    exit 1
  fi

  printf 'Published macOS update %s from commit %s.\n' \
    "$release_tag" \
    "$head_sha"
}

cleanup_release_notes_temp_dir() {
  if [[ -z "$release_notes_temp_dir" ]]; then
    return
  fi
  case "$release_notes_temp_dir" in
    "${TMPDIR:-/tmp}"/vinabike-codex-release-notes.*)
      rm -rf -- "$release_notes_temp_dir"
      ;;
  esac
}

find_codex_binary() {
  if command -v codex >/dev/null 2>&1; then
    command -v codex
    return
  fi
  local bundled_codex='/Applications/ChatGPT.app/Contents/Resources/codex'
  if [[ -x "$bundled_codex" ]]; then
    printf '%s\n' "$bundled_codex"
    return
  fi
  return 1
}

prepare_local_codex_release_notes() {
  local head_commit="$1"
  local codex_binary
  local base_commit
  local candidate_file
  local private_log
  local candidate_json

  RELEASE_NOTES_CANDIDATE_B64=''
  RELEASE_NOTES_CANDIDATE_SHA256=''
  RELEASE_NOTES_FROM_COMMIT=''
  if ! command -v node >/dev/null 2>&1; then
    echo 'Local Codex notes skipped: Node is unavailable; protected CI will use its fallback chain.'
    return
  fi
  if ! command -v gitleaks >/dev/null 2>&1; then
    echo 'Local Codex notes skipped: gitleaks is unavailable; protected CI will use its fallback chain.'
    return
  fi
  if ! codex_binary="$(find_codex_binary)"; then
    echo 'Local Codex notes skipped: Codex is unavailable; protected CI will use its fallback chain.'
    return
  fi
  if ! base_commit="$(
    GH_REPO="$REPO" \
      bash scripts/releases/resolve_previous_release_commit.sh \
        macos-v \
        macos-release-manifest.json \
        "$head_commit" \
        2>/dev/null
  )"; then
    echo 'Local Codex notes skipped: the previous release could not be resolved.'
    return
  fi
  if [[ ! "$base_commit" =~ ^[0-9a-f]{40}$ || "$base_commit" == "$head_commit" ]]; then
    echo 'Local Codex notes skipped: the release range is unavailable.'
    return
  fi
  RELEASE_NOTES_FROM_COMMIT="$base_commit"

  release_notes_temp_dir="$(
    mktemp -d "${TMPDIR:-/tmp}/vinabike-codex-release-notes.XXXXXX"
  )"
  chmod 700 "$release_notes_temp_dir"
  candidate_file="$release_notes_temp_dir/candidate-envelope.json"
  private_log="$release_notes_temp_dir/private.log"
  : > "$private_log"
  chmod 600 "$private_log"

  step 'Checking the committed release range before local Codex notes'
  if ! gitleaks git \
    --log-opts="${base_commit}..${head_commit}" \
    --config .gitleaks.toml \
    --gitleaks-ignore-path .gitleaksignore \
    --redact=100 \
    --no-banner \
    --no-color \
    --timeout 120 \
    "$repo_root" \
    >"$private_log" 2>&1; then
    echo 'Local Codex notes skipped: the committed range did not pass the private secret scan.'
    return
  fi

  step 'Preparing user-friendly notes with local Codex'
  if ! env \
    -u OPENAI_API_KEY \
    -u OPENAI_RELEASE_NOTES_ENDPOINT \
    -u OPENAI_RELEASE_NOTES_MODEL \
    -u GEMINI_RELEASE_API_KEY \
    -u GH_TOKEN \
    node scripts/releases/generate_codex_release_notes.mjs \
      --from-commit "$base_commit" \
      --to-commit "$head_commit" \
      --output "$candidate_file" \
      --codex-bin "$codex_binary" \
      --git-bin "$(command -v git)" \
      >"$private_log" 2>&1; then
    echo 'Local Codex notes unavailable; protected CI will use Gemini or deterministic notes.'
    return
  fi

  if ! candidate_json="$(jq -c . "$candidate_file" 2>/dev/null)"; then
    echo 'Local Codex notes unavailable; protected CI will use Gemini or deterministic notes.'
    return
  fi
  RELEASE_NOTES_CANDIDATE_B64="$(
    printf '%s' "$candidate_json" | base64 | tr -d '\r\n'
  )"
  RELEASE_NOTES_CANDIDATE_SHA256="$(
    printf '%s' "$candidate_json" | shasum -a 256 | awk '{print $1}'
  )"
  if [[
    ${#RELEASE_NOTES_CANDIDATE_B64} -gt 16384 ||
    ! "$RELEASE_NOTES_CANDIDATE_B64" =~ ^[A-Za-z0-9+/]*={0,2}$ ||
    ! "$RELEASE_NOTES_CANDIDATE_SHA256" =~ ^[0-9a-f]{64}$
  ]]; then
    RELEASE_NOTES_CANDIDATE_B64=''
    RELEASE_NOTES_CANDIDATE_SHA256=''
    echo 'Local Codex notes unavailable; protected CI will use Gemini or deterministic notes.'
    return
  fi
  echo 'Local Codex prepared a bounded candidate; protected CI will validate it again.'
}

require_command awk
require_command git
require_command gh
require_command jq
for required in \
  base64 bash chmod date env grep head mktemp rm shasum sleep tail tr wc; do
  require_command "$required"
done

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"
trap cleanup_release_notes_temp_dir EXIT

branch="$(git branch --show-current)"
if [[ -z "$branch" ]]; then
  echo 'Could not determine the current branch.' >&2
  exit 1
fi

assert_production_release_branch "$branch"

if [[ "$CHECK_RELEASE_BRANCH_ONLY" == 'YES' ]]; then
  echo 'macOS release branch preflight passed.'
  exit 0
fi

if [[ -n "$PREPARED_STATE_REQUEST" ]]; then
  erp_update_load_state "$PREPARED_STATE_REQUEST" macos
  erp_update_assert_prepared_source
  head_sha="$ERP_UPDATE_STATE_HEAD_SHA"
  RELEASE_NOTES_FROM_COMMIT="$ERP_UPDATE_STATE_RELEASE_NOTES_FROM_COMMIT"
  RELEASE_NOTES_CANDIDATE_B64="$ERP_UPDATE_STATE_RELEASE_NOTES_CANDIDATE_B64"
  RELEASE_NOTES_CANDIDATE_SHA256="$ERP_UPDATE_STATE_RELEASE_NOTES_CANDIDATE_SHA256"
  INTEGRITY_RUN_ID="$ERP_UPDATE_STATE_INTEGRITY_RUN_ID"
  INTEGRITY_RUN_ATTEMPT="$ERP_UPDATE_STATE_INTEGRITY_RUN_ATTEMPT"
  step "Using shared ERP update commit $head_sha"

  if published_run_id="$(
    find_published_release_run_id_for_commit "$head_sha"
  )"; then
    step 'This macOS commit is already published'
    verify_published_release "$head_sha" "$published_run_id"
    exit 0
  fi

else
  step 'Staging all Source Control changes'
  git add -A
  staged_files="$(git diff --cached --name-only)"

  if [[ -n "$staged_files" ]]; then
    if [[ -z "$MESSAGE" ]]; then
      MESSAGE="chore: publish macOS update $(date '+%Y-%m-%d %H:%M')"
    fi
    printf 'Commit message: %s\nFiles to commit and publish:\n%s\n' \
      "$MESSAGE" \
      "$staged_files"
  else
    echo 'No uncommitted Source Control changes found.'
    echo 'Publishing the current branch HEAD instead.'
  fi

  if [[ "$REQUIRE_CONFIRMATION" == 'YES' ]]; then
    read -r -p "Type YES to publish a macOS update from '$branch': " confirmation
    if [[ "$confirmation" != 'YES' ]]; then
      echo 'Cancelled.'
      exit 1
    fi
  fi

  if [[ -n "$staged_files" ]]; then
    step 'Committing staged changes'
    git commit -m "$MESSAGE"
  else
    step 'Skipping commit'
  fi

  head_sha="$(git rev-parse HEAD)"
  prepare_local_codex_release_notes "$head_sha"

  step "Pushing $branch at $head_sha"
  git push origin "$branch"
fi

notes_title_identity="${RELEASE_NOTES_CANDIDATE_SHA256:-fallback}"
notes_base_identity="${RELEASE_NOTES_FROM_COMMIT:-auto}"
integrity_title_identity="${INTEGRITY_RUN_ID:-self}"
expected_run_title="macOS publish · ${head_sha} · notes ${notes_title_identity} · from ${notes_base_identity} · integrity ${integrity_title_identity}"
runs_json="$(get_workflow_runs)"
active_run="$(
  jq -c \
    --arg sha "$head_sha" \
    --arg expected_title "$expected_run_title" \
    '
      [
        .workflow_runs[]?
        | select(.head_sha == $sha)
        | select((.display_title // "") == $expected_title)
        | select(.status != "completed")
      ]
      | sort_by(.created_at)
      | last
      // empty
    ' <<< "$runs_json"
)"
timer_start="$SECONDS"

if [[ -n "$active_run" ]]; then
  step 'Existing macOS release build found for current commit'
  run_json="$active_run"
else
  before_run_ids="$(
    jq -c '[.workflow_runs[]?.id]' <<< "$runs_json"
  )"

  step 'Triggering guarded macOS publication workflow'
  jq -n \
    --arg expected_commit "$head_sha" \
    --arg release_notes_from_commit "$RELEASE_NOTES_FROM_COMMIT" \
    --arg release_notes_candidate_b64 "$RELEASE_NOTES_CANDIDATE_B64" \
    --arg release_notes_candidate_sha256 "$RELEASE_NOTES_CANDIDATE_SHA256" \
    --arg integrity_run_id "$INTEGRITY_RUN_ID" \
    --arg integrity_run_attempt "$INTEGRITY_RUN_ATTEMPT" \
    '{
      release_target: "macos",
      publish_release: "true",
      expected_commit: $expected_commit,
      release_notes_from_commit: $release_notes_from_commit,
      release_notes_candidate_b64: $release_notes_candidate_b64,
      release_notes_candidate_sha256: $release_notes_candidate_sha256,
      integrity_run_id: $integrity_run_id,
      integrity_run_attempt: $integrity_run_attempt
    }' \
    | gh workflow run "$WORKFLOW" \
        --repo "$REPO" \
        --ref "$branch" \
        --json

  lookup_deadline="$((SECONDS + 300))"
  run_json=''
  step 'Finding GitHub Actions macOS release run'
  while [[ -z "$run_json" && "$SECONDS" -lt "$lookup_deadline" ]]; do
    printf 'Elapsed: %s | Phase: finding GitHub run\n' \
      "$(format_elapsed "$((SECONDS - timer_start))")"
    runs_json="$(get_workflow_runs)"
    run_json="$(
      jq -c \
        --arg sha "$head_sha" \
        --arg expected_title "$expected_run_title" \
        --argjson before_ids "$before_run_ids" \
        '
          [
            .workflow_runs[]?
            | select(.head_sha == $sha)
            | select((.display_title // "") == $expected_title)
            | select(.id as $id | ($before_ids | index($id)) == null)
          ]
          | sort_by(.created_at)
          | last
          // empty
        ' <<< "$runs_json"
    )"
    if [[ -z "$run_json" ]]; then
      sleep 10
    fi
  done
fi

if [[ -z "$run_json" ]]; then
  echo 'GitHub accepted the workflow dispatch, but the run was not visible within five minutes.' >&2
  echo "Check Actions for workflow '$WORKFLOW' on branch '$branch' at commit $head_sha." >&2
  exit 1
fi

run_id="$(jq -r '.id' <<< "$run_json")"
run_url="$(jq -r '.html_url' <<< "$run_json")"
printf 'Workflow run: %s\n' "$run_url"

if [[ "$NO_WAIT" == 'YES' ]]; then
  echo 'Not waiting for completion because --no-wait was passed.'
  exit 0
fi

step 'Waiting for macOS release build and publication'
while true; do
  view_json="$(
    gh run view "$run_id" \
      --repo "$REPO" \
      --json status,conclusion,url
  )"
  status="$(jq -r '.status' <<< "$view_json")"
  conclusion="$(jq -r '.conclusion // ""' <<< "$view_json")"
  printf 'Elapsed: %s | Phase: building macOS release | Status: %s | Conclusion: %s\n' \
    "$(format_elapsed "$((SECONDS - timer_start))")" \
    "$status" \
    "${conclusion:-pending}"
  if [[ "$status" == 'completed' ]]; then
    break
  fi
  sleep 30
done

if [[ "$conclusion" != 'success' ]]; then
  echo "macOS publication did not complete: $run_url" >&2
  echo "Source commit $head_sha remains pushed; fix the reported failure and run the task again." >&2
  show_workflow_failure_diagnostics "$run_id"
  exit 1
fi

verify_published_release "$head_sha" "$run_id"
