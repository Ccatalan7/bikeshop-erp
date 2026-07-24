#!/bin/bash

set -euo pipefail

REPO='Ccatalan7/bikeshop-erp'
WORKFLOW='macos-release.yml'
MESSAGE=''
NO_WAIT='NO'
REQUIRE_CONFIRMATION='NO'

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
  local job_name
  local annotations_json

  if jobs_json="$(
    gh api --method GET \
      "repos/${REPO}/actions/runs/${run_id}/jobs" \
      -f per_page=100
  )"; then
    while IFS=$'\t' read -r job_id job_name; do
      printf 'Failed job: %s\n' "$job_name"
      jq -r --argjson job_id "$job_id" '
        .jobs[]
        | select(.id == $job_id)
        | .steps[]?
        | select(.conclusion == "failure")
        | "  Failed step: \(.name)"
      ' <<< "$jobs_json"

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
        | [.id, .name]
        | @tsv
      ' <<< "$jobs_json"
    )
  else
    echo 'Could not load job/annotation diagnostics; trying the failed log.' >&2
  fi

  printf '\nFailed step log:\n'
  if ! gh run view "$run_id" --repo "$REPO" --log-failed \
    | tail -n 300 \
    | awk '
        {
          if (length($0) > 1000) {
            print substr($0, 1, 1000) " ... [line truncated]"
          } else {
            print
          }
        }
      '; then
    echo 'Could not load the failed step log; use the workflow URL above.' >&2
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

require_command git
require_command gh
require_command jq

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

branch="$(git branch --show-current)"
if [[ -z "$branch" ]]; then
  echo 'Could not determine the current branch.' >&2
  exit 1
fi

assert_production_release_branch "$branch"

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
step "Pushing $branch at $head_sha"
git push origin "$branch"

runs_json="$(get_workflow_runs)"
active_run="$(
  jq -c \
    --arg sha "$head_sha" \
    '
      [
        .workflow_runs[]?
        | select(.head_sha == $sha)
        | select((.display_title // "") | startswith("macOS publish"))
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
  gh workflow run "$WORKFLOW" \
    --repo "$REPO" \
    --ref "$branch" \
    -f publish_release=true

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
        --argjson before_ids "$before_run_ids" \
        '
          [
            .workflow_runs[]?
            | select(.head_sha == $sha)
            | select((.display_title // "") | startswith("macOS publish"))
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
  show_workflow_failure_diagnostics "$run_id"
  echo "macOS publication did not complete: $run_url" >&2
  echo "Source commit $head_sha remains pushed; fix the reported failure and run the task again." >&2
  exit 1
fi

verify_published_release "$head_sha" "$run_id"
