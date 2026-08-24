#!/usr/bin/env bash

set -euo pipefail
umask 077

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
MESSAGE=''
STATE_FILE_REQUEST='auto'
CANONICAL_RELEASE_BRANCH="${VINABIKE_ERP_RELEASE_BRANCH:-smartpegas1.0}"
CHECK_RELEASE_BRANCH_ONLY='NO'
state_temp_file=''
release_notes_from_commit=''
release_notes_candidate_b64=''
release_notes_candidate_sha256=''

# shellcheck source=scripts/releases/erp_update_state.sh
source "$SCRIPT_DIR/erp_update_state.sh"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --message)
      MESSAGE="${2:?--message requires a value}"
      shift
      ;;
    --state-file)
      STATE_FILE_REQUEST="${2:?--state-file requires a value}"
      shift
      ;;
    --check-release-branch)
      CHECK_RELEASE_BRANCH_ONLY='YES'
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 64
      ;;
  esac
  shift
done

step() {
  printf '\n[erp-update] %s\n' "$1"
}

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Required command '$1' was not found." >&2
    exit 127
  fi
}

ensure_safe_production_branch() {
  local current_branch="$1"
  local boundary_output

  if boundary_output="$(
    bash scripts/publish_macos_update.sh --check-release-branch 2>&1
  )"; then
    printf '%s\n' "$boundary_output"
    branch="$current_branch"
    return
  fi

  if [[ "$current_branch" == "$CANONICAL_RELEASE_BRANCH" ]]; then
    printf '%s\n' "$boundary_output" >&2
    exit 1
  fi

  step "Checking a safe handoff from $current_branch to $CANONICAL_RELEASE_BRANCH"
  if ! git fetch --quiet --no-tags origin \
    "refs/heads/${CANONICAL_RELEASE_BRANCH}:refs/remotes/origin/${CANONICAL_RELEASE_BRANCH}"; then
    printf '%s\n' "$boundary_output" >&2
    echo "Could not read origin/$CANONICAL_RELEASE_BRANCH." >&2
    exit 1
  fi

  local current_head
  local canonical_remote_head
  current_head="$(git rev-parse HEAD)"
  canonical_remote_head="$(
    git rev-parse "refs/remotes/origin/${CANONICAL_RELEASE_BRANCH}"
  )"
  if [[ "$current_head" != "$canonical_remote_head" ]]; then
    printf '%s\n' "$boundary_output" >&2
    echo "Automatic branch handoff was not attempted because $current_branch" >&2
    echo "does not point to the exact live origin/$CANONICAL_RELEASE_BRANCH commit." >&2
    echo 'Review or integrate that history first; the publisher will not merge it.' >&2
    exit 1
  fi

  if git show-ref --verify --quiet "refs/heads/${CANONICAL_RELEASE_BRANCH}"; then
    local canonical_local_head
    canonical_local_head="$(git rev-parse "refs/heads/${CANONICAL_RELEASE_BRANCH}")"
    if [[ "$canonical_local_head" != "$canonical_remote_head" ]]; then
      if ! git merge-base --is-ancestor \
        "$canonical_local_head" "$canonical_remote_head"; then
        echo "Local $CANONICAL_RELEASE_BRANCH contains history not present on origin." >&2
        echo 'The publisher will not move or discard that branch automatically.' >&2
        exit 1
      fi
      git branch -f "$CANONICAL_RELEASE_BRANCH" "$canonical_remote_head"
    fi
  else
    git branch --track \
      "$CANONICAL_RELEASE_BRANCH" "origin/$CANONICAL_RELEASE_BRANCH"
  fi

  step "Switching safely to $CANONICAL_RELEASE_BRANCH at the same source commit"
  git switch "$CANONICAL_RELEASE_BRANCH"
  branch="$CANONICAL_RELEASE_BRANCH"
  bash scripts/publish_macos_update.sh --check-release-branch
}

cleanup_state_temp_file() {
  if [[ -n "$state_temp_file" && -f "$state_temp_file" ]]; then
    rm -f -- "$state_temp_file"
  fi
}

cleanup() {
  cleanup_state_temp_file
}

prepare_shared_release_notes() {
  local head_commit="$1"
  local desktop_release_notes_from_commit

  release_notes_candidate_b64=''
  release_notes_candidate_sha256=''
  desktop_release_notes_from_commit="$(
    GH_REPO='Ccatalan7/bikeshop-erp' \
      bash scripts/releases/resolve_previous_release_commit.sh \
        macos-v \
        macos-release-manifest.json \
        "$head_commit"
  )"
  release_notes_from_commit="$(
    node scripts/releases/resolve_paired_release_notes_base.mjs \
      --branch "$branch" \
      --head-commit "$head_commit" \
      --desktop-commit "$desktop_release_notes_from_commit"
  )"
  if [[
    ! "$release_notes_from_commit" =~ ^[0-9a-f]{40}$ ||
    "$release_notes_from_commit" == "$head_commit"
  ]]; then
    echo 'Could not resolve a safe release-note range.' >&2
    exit 1
  fi
  echo 'Gemini Flash will generate the shared release notes inside protected CI.'
}

for required in awk bash chmod date git gh jq mktemp mv node; do
  require_command "$required"
done

cd "$PROJECT_ROOT"
trap cleanup EXIT

branch="$(git branch --show-current)"
if [[ -z "$branch" ]]; then
  echo 'Could not determine the current branch.' >&2
  exit 1
fi

step 'Checking the macOS Production branch boundary'
ensure_safe_production_branch "$branch"

if [[ "$CHECK_RELEASE_BRANCH_ONLY" == 'YES' ]]; then
  echo 'Shared ERP release branch preflight passed.'
  exit 0
fi

step "Checking live source history for $branch"
git fetch --quiet --no-tags origin "refs/heads/${branch}:refs/remotes/origin/${branch}"
remote_before="$(git rev-parse "refs/remotes/origin/${branch}")"
if ! git merge-base --is-ancestor "$remote_before" HEAD; then
  if git merge-base --is-ancestor HEAD "$remote_before"; then
    step "Fast-forwarding $branch to the live origin before publication"
    if ! git merge --ff-only "$remote_before"; then
      echo 'The live branch could not be applied without disturbing local work.' >&2
      echo 'Resolve the reported files, then run the combined task again.' >&2
      exit 1
    fi
  else
    echo "Local $branch and origin/$branch have diverged." >&2
    echo 'The shared publisher will not overwrite or bypass either history.' >&2
    exit 1
  fi
fi

step 'Refreshing the pinned Flutter dependency lock before the shared commit'
if [[ -x .fvm/flutter_sdk/bin/flutter ]]; then
  .fvm/flutter_sdk/bin/flutter pub get
elif command -v fvm >/dev/null 2>&1; then
  fvm flutter pub get
else
  echo 'The pinned Flutter toolchain is unavailable.' >&2
  exit 127
fi

step 'Staging all reviewed Source Control changes once'
git add -A
staged_files="$(git diff --cached --name-only)"

if [[ -n "$staged_files" ]]; then
  if [[ -z "$MESSAGE" ]]; then
    MESSAGE="chore: publish ERP update $(date '+%Y-%m-%d %H:%M')"
  fi
  printf 'Commit message: %s\nFiles to commit and publish:\n%s\n' \
    "$MESSAGE" \
    "$staged_files"
  step 'Creating the shared ERP update commit'
  git commit -m "$MESSAGE"
else
  echo 'No uncommitted Source Control changes found.'
  echo 'Both publishers will use the current branch HEAD.'
fi

if [[ -n "$(git status --porcelain)" ]]; then
  echo 'The worktree changed while the shared ERP update commit was being prepared.' >&2
  exit 1
fi

head_sha="$(git rev-parse HEAD)"
prepare_shared_release_notes "$head_sha"

if [[ -n "$(git status --porcelain)" || "$(git rev-parse HEAD)" != "$head_sha" ]]; then
  echo 'The source changed while shared release notes were being prepared.' >&2
  echo 'Review the new changes, then run the combined task again.' >&2
  exit 1
fi

step "Pushing the shared source commit $head_sha"
git push origin "$branch"

remote_after="$(
  git ls-remote --heads origin "refs/heads/${branch}" |
    awk 'NR == 1 { print $1 }'
)"
if [[ "$remote_after" != "$head_sha" ]]; then
  echo 'The live remote branch does not identify the shared ERP update commit.' >&2
  exit 1
fi

created_epoch="$(date +%s)"

state_file="$(erp_update_resolve_state_file "$STATE_FILE_REQUEST")"
state_temp_file="$(mktemp "${state_file}.tmp.XXXXXX")"
chmod 600 "$state_temp_file"
jq -n \
  --arg repository_root "$PROJECT_ROOT" \
  --arg branch "$branch" \
  --arg head_sha "$head_sha" \
  --argjson created_epoch "$created_epoch" \
  --arg release_notes_from_commit "$release_notes_from_commit" \
  --arg release_notes_candidate_b64 "$release_notes_candidate_b64" \
  --arg release_notes_candidate_sha256 "$release_notes_candidate_sha256" \
  '{
    schema_version: 2,
    targets: ["macos", "android"],
    repository_root: $repository_root,
    remote: "origin",
    branch: $branch,
    head_sha: $head_sha,
    created_epoch: $created_epoch,
    release_notes: {
      from_commit: $release_notes_from_commit,
      candidate_b64: $release_notes_candidate_b64,
      candidate_sha256: $release_notes_candidate_sha256
    }
  }' > "$state_temp_file"
mv -f -- "$state_temp_file" "$state_file"
state_temp_file=''

printf '\nPrepared one shared ERP update commit:\n'
printf '  Source: %s\n' "$head_sha"
printf '  Notes base: %s\n' "$release_notes_from_commit"
echo 'VS Code can now start the macOS and Android publishers in parallel.'
