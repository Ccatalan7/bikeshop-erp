#!/usr/bin/env bash

set -euo pipefail
umask 077

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
MESSAGE=''
STATE_FILE_REQUEST='auto'
state_temp_file=''
release_notes_temp_dir=''
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

cleanup_state_temp_file() {
  if [[ -n "$state_temp_file" && -f "$state_temp_file" ]]; then
    rm -f -- "$state_temp_file"
  fi
}

cleanup_release_notes_temp_dir() {
  if [[ -z "$release_notes_temp_dir" ]]; then
    return
  fi
  case "$release_notes_temp_dir" in
    "${TMPDIR:-/tmp}"/vinabike-shared-release-notes.*)
      rm -rf -- "$release_notes_temp_dir"
      ;;
  esac
}

cleanup() {
  cleanup_state_temp_file
  cleanup_release_notes_temp_dir
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

prepare_shared_release_notes() {
  local head_commit="$1"
  local codex_binary
  local git_binary
  local candidate_file
  local compact_candidate_file
  local private_log

  release_notes_candidate_b64=''
  release_notes_candidate_sha256=''
  release_notes_from_commit="$(
    GH_REPO='Ccatalan7/bikeshop-erp' \
      bash scripts/releases/resolve_previous_release_commit.sh \
        macos-v \
        macos-release-manifest.json \
        "$head_commit"
  )"
  if [[
    ! "$release_notes_from_commit" =~ ^[0-9a-f]{40}$ ||
    "$release_notes_from_commit" == "$head_commit"
  ]]; then
    echo 'Could not resolve a safe release-note range.' >&2
    exit 1
  fi

  if [[ -f "$(erp_update_resolve_state_file "$STATE_FILE_REQUEST")" ]] &&
    erp_update_load_state "$STATE_FILE_REQUEST" macos 2>/dev/null &&
    [[
      "$ERP_UPDATE_STATE_HEAD_SHA" == "$head_commit" &&
      "$ERP_UPDATE_STATE_RELEASE_NOTES_FROM_COMMIT" == \
        "$release_notes_from_commit" &&
      -n "$ERP_UPDATE_STATE_RELEASE_NOTES_CANDIDATE_B64"
    ]]; then
    release_notes_candidate_b64="$ERP_UPDATE_STATE_RELEASE_NOTES_CANDIDATE_B64"
    release_notes_candidate_sha256="$ERP_UPDATE_STATE_RELEASE_NOTES_CANDIDATE_SHA256"
    echo 'Reusing the exact Codex candidate already bound to this commit.'
    return
  fi

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
  git_binary="$(command -v git)"

  release_notes_temp_dir="$(
    mktemp -d "${TMPDIR:-/tmp}/vinabike-shared-release-notes.XXXXXX"
  )"
  chmod 700 "$release_notes_temp_dir"
  candidate_file="$release_notes_temp_dir/candidate-envelope.json"
  compact_candidate_file="$release_notes_temp_dir/candidate-envelope.compact.json"
  private_log="$release_notes_temp_dir/private.log"
  : > "$private_log"
  chmod 600 "$private_log"

  step 'Checking the committed release range before local Codex notes'
  if ! gitleaks git \
    --log-opts="${release_notes_from_commit}..${head_commit}" \
    --config .gitleaks.toml \
    --gitleaks-ignore-path .gitleaksignore \
    --redact=100 \
    --no-banner \
    --no-color \
    --timeout 120 \
    "$PROJECT_ROOT" \
    >"$private_log" 2>&1; then
    echo 'Local Codex notes skipped: the committed range did not pass the private secret scan.'
    return
  fi

  step 'Preparing one shared user-friendly note with local Codex'
  if ! env \
    -u OPENAI_API_KEY \
    -u OPENAI_RELEASE_NOTES_ENDPOINT \
    -u OPENAI_RELEASE_NOTES_MODEL \
    -u GEMINI_RELEASE_API_KEY \
    -u GH_TOKEN \
    node scripts/releases/generate_codex_release_notes.mjs \
      --from-commit "$release_notes_from_commit" \
      --to-commit "$head_commit" \
      --output "$candidate_file" \
      --codex-bin "$codex_binary" \
      --git-bin "$git_binary" \
      >"$private_log" 2>&1; then
    echo 'Local Codex notes unavailable; protected CI will use Gemini or deterministic notes.'
    return
  fi

  if ! jq -ce \
    --arg from "$release_notes_from_commit" \
    --arg to "$head_commit" \
    '
      select(
        .schema_version == 1
        and .from_commit == $from
        and .to_commit == $to
        and (.evidence_catalog_sha256 | test("^[0-9a-f]{64}$"))
        and (.candidate | type == "object")
      )
    ' \
    "$candidate_file" > "$compact_candidate_file"; then
    echo 'Local Codex notes unavailable; protected CI will use Gemini or deterministic notes.'
    return
  fi

  release_notes_candidate_b64="$(
    base64 < "$compact_candidate_file" | tr -d '\r\n'
  )"
  release_notes_candidate_sha256="$(
    shasum -a 256 "$compact_candidate_file" | awk '{print $1}'
  )"
  if [[
    ${#release_notes_candidate_b64} -gt 16384 ||
    ! "$release_notes_candidate_b64" =~ ^[A-Za-z0-9+/]*={0,2}$ ||
    ! "$release_notes_candidate_sha256" =~ ^[0-9a-f]{64}$
  ]]; then
    release_notes_candidate_b64=''
    release_notes_candidate_sha256=''
    echo 'Local Codex notes unavailable; protected CI will use Gemini or deterministic notes.'
    return
  fi
  echo 'One bounded Codex candidate is ready for both platform publishers.'
}

for required in \
  awk base64 bash chmod date env git gh head jq mktemp mv rm sed shasum tr; do
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
bash scripts/publish_macos_update.sh --check-release-branch

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
