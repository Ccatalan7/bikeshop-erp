#!/usr/bin/env bash

# Shared, read-only validation for the private handoff created by
# prepare_erp_update.sh. This file is sourced by the platform publishers.

ERP_UPDATE_STATE_MAX_AGE_SECONDS=21600

erp_update_default_state_file() {
  local git_dir
  git_dir="$(cd "$(git rev-parse --absolute-git-dir)" && pwd -P)"
  printf '%s/vinabike-erp-publish-state.json\n' "$git_dir"
}

erp_update_resolve_state_file() {
  local requested="${1:-auto}"
  local git_dir
  local resolved
  local resolved_name
  local resolved_parent

  git_dir="$(cd "$(git rev-parse --absolute-git-dir)" && pwd -P)"
  if [[ -z "$requested" || "$requested" == 'auto' ]]; then
    resolved="$(erp_update_default_state_file)"
  elif [[ "$requested" == /* ]]; then
    resolved="$requested"
  else
    resolved="$(git rev-parse --show-toplevel)/$requested"
  fi

  resolved_name="${resolved##*/}"
  resolved_parent="${resolved%/*}"
  if [[ -z "$resolved_name" ]] ||
    ! resolved_parent="$(cd "$resolved_parent" 2>/dev/null && pwd -P)"; then
    echo 'Could not resolve the ERP update state-file directory.' >&2
    return 1
  fi
  resolved="$resolved_parent/$resolved_name"

  case "$resolved" in
    "$git_dir"/*)
      printf '%s\n' "$resolved"
      ;;
    *)
      echo 'The ERP update state file must stay inside the current Git directory.' >&2
      return 1
      ;;
  esac
}

erp_update_load_state() {
  local requested_path="$1"
  local required_target="$2"
  local state_json
  local now_epoch
  local state_age
  local candidate_file=''
  local candidate_hash=''

  cleanup_candidate_file() {
    if [[ -n "$candidate_file" && -f "$candidate_file" ]]; then
      rm -f -- "$candidate_file"
    fi
  }

  ERP_UPDATE_STATE_FILE="$(erp_update_resolve_state_file "$requested_path")"
  if [[ ! -f "$ERP_UPDATE_STATE_FILE" || -L "$ERP_UPDATE_STATE_FILE" ]]; then
    echo "Prepared ERP update state is unavailable: $ERP_UPDATE_STATE_FILE" >&2
    return 1
  fi

  state_json="$(cat -- "$ERP_UPDATE_STATE_FILE")"
  if ! jq -e \
    --arg target "$required_target" \
    '
      .schema_version == 2
      and (.targets | type == "array")
      and (.targets | index($target) != null)
      and (.repository_root | type == "string" and length > 0)
      and .remote == "origin"
      and (.branch | type == "string" and length > 0)
      and (.head_sha | type == "string" and test("^[0-9a-f]{40}$"))
      and (.created_epoch | type == "number")
      and (.release_notes | type == "object")
      and (
        .release_notes.from_commit
        | type == "string" and test("^[0-9a-f]{40}$")
      )
      and (.release_notes.candidate_b64 | type == "string")
      and (.release_notes.candidate_sha256 | type == "string")
    ' >/dev/null <<< "$state_json"; then
    echo 'Prepared ERP update state is malformed or does not authorize this platform.' >&2
    return 1
  fi

  ERP_UPDATE_STATE_REPOSITORY_ROOT="$(
    jq -r '.repository_root' <<< "$state_json"
  )"
  ERP_UPDATE_STATE_REMOTE="$(jq -r '.remote' <<< "$state_json")"
  ERP_UPDATE_STATE_BRANCH="$(jq -r '.branch' <<< "$state_json")"
  ERP_UPDATE_STATE_HEAD_SHA="$(jq -r '.head_sha' <<< "$state_json")"
  ERP_UPDATE_STATE_CREATED_EPOCH="$(
    jq -r '.created_epoch | floor' <<< "$state_json"
  )"
  ERP_UPDATE_STATE_RELEASE_NOTES_FROM_COMMIT="$(
    jq -r '.release_notes.from_commit' <<< "$state_json"
  )"
  ERP_UPDATE_STATE_RELEASE_NOTES_CANDIDATE_B64="$(
    jq -r '.release_notes.candidate_b64' <<< "$state_json"
  )"
  ERP_UPDATE_STATE_RELEASE_NOTES_CANDIDATE_SHA256="$(
    jq -r '.release_notes.candidate_sha256' <<< "$state_json"
  )"

  now_epoch="$(date +%s)"
  state_age=$((now_epoch - ERP_UPDATE_STATE_CREATED_EPOCH))
  if (( state_age < 0 || state_age > ERP_UPDATE_STATE_MAX_AGE_SECONDS )); then
    echo 'Prepared ERP update state is stale; run the top-level publish task again.' >&2
    return 1
  fi

  if [[ -z "$ERP_UPDATE_STATE_RELEASE_NOTES_CANDIDATE_B64" ]]; then
    if [[ -n "$ERP_UPDATE_STATE_RELEASE_NOTES_CANDIDATE_SHA256" ]]; then
      echo 'Prepared ERP update state has an invalid empty release-note binding.' >&2
      return 1
    fi
    return 0
  fi

  if [[
    ${#ERP_UPDATE_STATE_RELEASE_NOTES_CANDIDATE_B64} -gt 16384 ||
    ! "$ERP_UPDATE_STATE_RELEASE_NOTES_CANDIDATE_B64" =~ ^[A-Za-z0-9+/]*={0,2}$ ||
    ! "$ERP_UPDATE_STATE_RELEASE_NOTES_CANDIDATE_SHA256" =~ ^[0-9a-f]{64}$
  ]]; then
    echo 'Prepared ERP update state has invalid release-note metadata.' >&2
    return 1
  fi

  candidate_file="$(mktemp "${TMPDIR:-/tmp}/vinabike-release-note-state.XXXXXX")"
  chmod 600 "$candidate_file"
  if base64 --help 2>&1 | grep -q -- '--decode'; then
    if ! printf '%s' "$ERP_UPDATE_STATE_RELEASE_NOTES_CANDIDATE_B64" |
      base64 --decode > "$candidate_file"; then
      cleanup_candidate_file
      echo 'Prepared ERP update release-note candidate is not valid base64.' >&2
      return 1
    fi
  elif ! printf '%s' "$ERP_UPDATE_STATE_RELEASE_NOTES_CANDIDATE_B64" |
    base64 -D > "$candidate_file"; then
    cleanup_candidate_file
    echo 'Prepared ERP update release-note candidate is not valid base64.' >&2
    return 1
  fi

  if [[
    ! -s "$candidate_file" ||
    "$(wc -c < "$candidate_file" | tr -d '[:space:]')" -gt 12288
  ]]; then
    cleanup_candidate_file
    echo 'Prepared ERP update release-note candidate is outside its size boundary.' >&2
    return 1
  fi
  candidate_hash="$(shasum -a 256 "$candidate_file" | awk '{print $1}')"
  if [[ "$candidate_hash" != "$ERP_UPDATE_STATE_RELEASE_NOTES_CANDIDATE_SHA256" ]]; then
    cleanup_candidate_file
    echo 'Prepared ERP update release-note candidate failed its SHA256 binding.' >&2
    return 1
  fi
  if ! jq -e \
    --arg from "$ERP_UPDATE_STATE_RELEASE_NOTES_FROM_COMMIT" \
    --arg to "$ERP_UPDATE_STATE_HEAD_SHA" \
    '
      .schema_version == 1
      and .from_commit == $from
      and .to_commit == $to
      and (.evidence_catalog_sha256 | test("^[0-9a-f]{64}$"))
      and (.candidate | type == "object")
    ' "$candidate_file" >/dev/null; then
    cleanup_candidate_file
    echo 'Prepared ERP update release-note candidate targets a different range.' >&2
    return 1
  fi
  cleanup_candidate_file
}

erp_update_assert_prepared_source() {
  local actual_root
  local actual_branch
  local actual_head
  local remote_head

  actual_root="$(git rev-parse --show-toplevel)"
  actual_branch="$(git branch --show-current)"
  actual_head="$(git rev-parse HEAD)"

  if [[ "$actual_root" != "$ERP_UPDATE_STATE_REPOSITORY_ROOT" ]]; then
    echo 'Prepared ERP update state belongs to a different repository checkout.' >&2
    return 1
  fi
  if [[ -z "$actual_branch" || "$actual_branch" != "$ERP_UPDATE_STATE_BRANCH" ]]; then
    echo 'The current branch does not match the prepared ERP update.' >&2
    return 1
  fi
  if [[ "$actual_head" != "$ERP_UPDATE_STATE_HEAD_SHA" ]]; then
    echo 'The current commit does not match the prepared ERP update.' >&2
    return 1
  fi
  if [[ -n "$(git status --porcelain)" ]]; then
    echo 'The worktree changed after the shared ERP update commit was prepared.' >&2
    return 1
  fi
  if ! git merge-base --is-ancestor \
    "$ERP_UPDATE_STATE_RELEASE_NOTES_FROM_COMMIT" \
    "$ERP_UPDATE_STATE_HEAD_SHA"; then
    echo 'The prepared release-note base is not an ancestor of the release commit.' >&2
    return 1
  fi

  remote_head="$(
    git ls-remote \
      --heads \
      "$ERP_UPDATE_STATE_REMOTE" \
      "refs/heads/$ERP_UPDATE_STATE_BRANCH" \
      | awk 'NR == 1 { print $1 }'
  )"
  if [[ ! "$remote_head" =~ ^[0-9a-f]{40}$ ]]; then
    echo 'Could not resolve the live remote branch for the prepared ERP update.' >&2
    return 1
  fi
  if [[ "$remote_head" != "$ERP_UPDATE_STATE_HEAD_SHA" ]]; then
    echo 'The live remote branch no longer matches the prepared ERP update.' >&2
    return 1
  fi
}
