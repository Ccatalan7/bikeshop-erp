#!/bin/bash

set -euo pipefail

readonly REPO_SLUG='Ccatalan7/bikeshop-erp'
readonly RELEASE_SIGNER='vinabike-release'
readonly RELEASE_NAMESPACE='vinabike-macos-release'
readonly RELEASE_PUBLIC_KEY='ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILPejGbw9io5kXqLVhYI5a+TFA8Py792DXF/nUfSDRw8'
readonly EXPECTED_BUNDLE_ID='com.vinabike.vinabikeErp'
readonly EXPECTED_APP_NAME='Vinabike ERP.app'
readonly UPDATE_LABEL='com.vinabike.erp.updater'
readonly DEFAULT_MANIFEST_URL="https://github.com/${REPO_SLUG}/releases/download/macos-latest/macos-release-manifest.json"
readonly DEFAULT_SIGNATURE_URL="${DEFAULT_MANIFEST_URL}.sig"

MODE='install'
QUIET='NO'
TEST_MODE="${VINABIKE_TEST_MODE:-NO}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --service)
      MODE='service'
      QUIET='YES'
      ;;
    --prepare)
      MODE='prepare'
      ;;
    --apply-prepared)
      MODE='apply'
      ;;
    --quiet)
      QUIET='YES'
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 64
      ;;
  esac
  shift
done

if [[ "$TEST_MODE" == 'YES' ]]; then
  USER_HOME="${VINABIKE_USER_HOME:?VINABIKE_USER_HOME is required in test mode}"
else
  USER_HOME="${HOME:?HOME is required}"
fi

readonly USER_HOME
readonly APP_PARENT="${VINABIKE_INSTALL_ROOT:-${USER_HOME}/Applications}"
readonly APP_PATH="${APP_PARENT}/${EXPECTED_APP_NAME}"
readonly SUPPORT_ROOT="${VINABIKE_SUPPORT_ROOT:-${USER_HOME}/Library/Application Support/VinabikeERP}"
readonly UPDATER_ROOT="${SUPPORT_ROOT}/updater"
readonly INSTALLED_SCRIPT="${UPDATER_ROOT}/install_vinabike_erp_macos.sh"
readonly PREPARED_ROOT="${SUPPORT_ROOT}/prepared"
readonly ROLLBACK_ROOT="${SUPPORT_ROOT}/rollback"
readonly LOG_PATH="${SUPPORT_ROOT}/updater.log"
readonly LAUNCH_AGENT_LOG_PATH="${SUPPORT_ROOT}/launch-agent.log"
readonly COORDINATION_ROOT="${VINABIKE_COORDINATION_ROOT:-${USER_HOME}/Library/Containers/${EXPECTED_BUNDLE_ID}/Data/Library/Application Support/${EXPECTED_BUNDLE_ID}/updates}"
readonly PREPARE_REQUEST="${COORDINATION_ROOT}/prepare-request.json"
readonly APPLY_REQUEST="${COORDINATION_ROOT}/apply-request.json"
readonly PREPARED_STATE="${COORDINATION_ROOT}/prepared-release.json"
readonly CURRENT_STATE="${COORDINATION_ROOT}/current-release.json"
readonly ERROR_STATE="${COORDINATION_ROOT}/update-error.json"
readonly LAUNCH_AGENTS_ROOT="${VINABIKE_LAUNCH_AGENTS_ROOT:-${USER_HOME}/Library/LaunchAgents}"
readonly LAUNCH_AGENT_PATH="${LAUNCH_AGENTS_ROOT}/${UPDATE_LABEL}.plist"
readonly MANIFEST_URL="${VINABIKE_MANIFEST_URL:-${DEFAULT_MANIFEST_URL}}"
readonly SIGNATURE_URL="${VINABIKE_SIGNATURE_URL:-${DEFAULT_SIGNATURE_URL}}"

WORK_ROOT=''
LOCK_HELD='NO'
APPLY_ATTEMPTED='NO'
TAG_NAME='unknown'
ARCHIVE_NAME=''
ARCHIVE_URL=''
ARCHIVE_SHA256=''
INSTALLER_URL=''
INSTALLER_SHA256=''
BUNDLE_VERSION=''
SHORT_VERSION=''
COMMIT_SHA=''
MANIFEST_PATH=''
SIGNATURE_PATH=''

log() {
  local message="$1"
  mkdir -p "$SUPPORT_ROOT"
  printf '[%s] %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$message" >> "$LOG_PATH"
  if [[ "$QUIET" != 'YES' ]]; then
    printf '%s\n' "$message"
  fi
}

rotate_log_if_large() {
  local file="$1"
  [[ -f "$file" ]] || return 0

  local size
  size="$(/usr/bin/stat -f '%z' "$file" 2>/dev/null || printf '0')"
  if [[ "$size" =~ ^[0-9]+$ ]] && [[ "$size" -gt 5242880 ]]; then
    mv -f "$file" "${file}.previous"
  fi
}

json_value() {
  local file="$1"
  local key="$2"
  /usr/bin/plutil -extract "$key" raw -o - "$file"
}

write_release_state() {
  local file="$1"
  local tag="$2"
  local temporary="${file}.tmp.$$"
  mkdir -p "$(dirname "$file")"
  printf '{"tag_name":"%s","updated_at":"%s"}\n' \
    "$tag" "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" > "$temporary"
  mv -f "$temporary" "$file"
}

write_error_state() {
  local message="$1"
  local temporary="${ERROR_STATE}.tmp.$$"
  mkdir -p "$COORDINATION_ROOT"
  printf '{"tag_name":"%s","message":"%s","updated_at":"%s"}\n' \
    "$TAG_NAME" "$message" "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" > "$temporary"
  mv -f "$temporary" "$ERROR_STATE"
}

safe_remove_tree() {
  local target="$1"
  if [[ -z "$target" || "$target" == '/' ]]; then
    log "Refusing to remove unsafe path: $target"
    return 1
  fi
  case "$target" in
    "$WORK_ROOT"|"$WORK_ROOT"/*|"$PREPARED_ROOT"/*|"$ROLLBACK_ROOT"/*|"$APP_PATH")
      rm -rf -- "$target"
      ;;
    *)
      log "Refusing to remove unexpected path: $target"
      return 1
      ;;
  esac
}

cleanup() {
  local exit_code=$?

  if [[ "$LOCK_HELD" == 'YES' ]]; then
    rmdir "${SUPPORT_ROOT}/update.lock" 2>/dev/null || true
  fi

  if [[ -n "$WORK_ROOT" && -d "$WORK_ROOT" ]]; then
    safe_remove_tree "$WORK_ROOT" 2>/dev/null || true
  fi

  if [[ $exit_code -ne 0 && ! -f "$ERROR_STATE" ]]; then
    write_error_state 'No se pudo completar la actualización de macOS.' 2>/dev/null || true
  fi

  if [[ $exit_code -ne 0 ]]; then
    rm -f "$PREPARE_REQUEST" "$APPLY_REQUEST"
    if [[ "$APPLY_ATTEMPTED" == 'YES' && -d "$APP_PATH" ]] && \
       [[ "${VINABIKE_SKIP_LAUNCH:-NO}" != 'YES' ]]; then
      /usr/bin/open "$APP_PATH" >/dev/null 2>&1 || true
    fi
  fi
}
trap cleanup EXIT

acquire_lock() {
  mkdir -p "$SUPPORT_ROOT"
  if ! mkdir "${SUPPORT_ROOT}/update.lock" 2>/dev/null; then
    log 'Another Vinabike ERP update process is already active.'
    exit 0
  fi
  LOCK_HELD='YES'
}

make_work_root() {
  if [[ -n "$WORK_ROOT" ]]; then
    return
  fi
  WORK_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/vinabike-update.XXXXXX")"
}

download() {
  local url="$1"
  local destination="$2"
  /usr/bin/curl --fail --location --silent --show-error \
    --retry 4 --retry-all-errors --connect-timeout 20 \
    --output "$destination" "$url"
}

validate_https_release_url() {
  local url="$1"
  if [[ "$TEST_MODE" == 'YES' && "$url" == file://* ]]; then
    return
  fi
  case "$url" in
    "https://github.com/${REPO_SLUG}/releases/download/"*) ;;
    *)
      log "Rejected unexpected release URL: $url"
      return 1
      ;;
  esac
}

fetch_and_verify_manifest() {
  make_work_root
  MANIFEST_PATH="${WORK_ROOT}/macos-release-manifest.json"
  SIGNATURE_PATH="${MANIFEST_PATH}.sig"
  local allowed_signers="${WORK_ROOT}/allowed_signers"

  download "$MANIFEST_URL" "$MANIFEST_PATH"
  download "$SIGNATURE_URL" "$SIGNATURE_PATH"
  printf '%s %s\n' "$RELEASE_SIGNER" "$RELEASE_PUBLIC_KEY" > "$allowed_signers"

  if ! /usr/bin/ssh-keygen -Y verify \
    -f "$allowed_signers" \
    -I "$RELEASE_SIGNER" \
    -n "$RELEASE_NAMESPACE" \
    -s "$SIGNATURE_PATH" < "$MANIFEST_PATH" >> "$LOG_PATH" 2>&1; then
    log 'The macOS release manifest signature is invalid.'
    return 1
  fi

  TAG_NAME="$(json_value "$MANIFEST_PATH" tag_name)"
  ARCHIVE_NAME="$(json_value "$MANIFEST_PATH" archive_name)"
  ARCHIVE_URL="$(json_value "$MANIFEST_PATH" archive_url)"
  ARCHIVE_SHA256="$(json_value "$MANIFEST_PATH" archive_sha256)"
  INSTALLER_URL="$(json_value "$MANIFEST_PATH" installer_url)"
  INSTALLER_SHA256="$(json_value "$MANIFEST_PATH" installer_sha256)"
  BUNDLE_VERSION="$(json_value "$MANIFEST_PATH" bundle_version)"
  SHORT_VERSION="$(json_value "$MANIFEST_PATH" short_version)"
  COMMIT_SHA="$(json_value "$MANIFEST_PATH" commit)"

  [[ "$TAG_NAME" =~ ^macos-v[0-9A-Za-z._-]+$ ]]
  [[ "$ARCHIVE_NAME" =~ ^vinabike_erp_macos_[0-9A-Za-z._-]+\.zip$ ]]
  [[ "$ARCHIVE_SHA256" =~ ^[0-9a-fA-F]{64}$ ]]
  [[ "$INSTALLER_SHA256" =~ ^[0-9a-fA-F]{64}$ ]]
  [[ "$BUNDLE_VERSION" =~ ^[0-9]+$ ]]
  [[ "$SHORT_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+([._+-][0-9A-Za-z.-]+)?$ ]]
  [[ "$COMMIT_SHA" =~ ^[0-9a-f]{40}$ ]]
  [[ "$(json_value "$MANIFEST_PATH" bundle_id)" == "$EXPECTED_BUNDLE_ID" ]]
  [[ "$(json_value "$MANIFEST_PATH" app_name)" == "$EXPECTED_APP_NAME" ]]
  validate_https_release_url "$ARCHIVE_URL"
  validate_https_release_url "$INSTALLER_URL"

  log "Verified signed release manifest for $TAG_NAME."
}

verify_sha256() {
  local file="$1"
  local expected="$2"
  local actual
  actual="$(/usr/bin/shasum -a 256 "$file" | /usr/bin/awk '{print $1}')"
  if [[ "$actual" != "$expected" ]]; then
    log "SHA-256 mismatch for $(basename "$file")."
    return 1
  fi
}

refresh_installed_updater() {
  local downloaded_installer="${WORK_ROOT}/install_vinabike_erp_macos.sh"
  download "$INSTALLER_URL" "$downloaded_installer"
  verify_sha256 "$downloaded_installer" "$INSTALLER_SHA256"
  mkdir -p "$UPDATER_ROOT"
  chmod 700 "$downloaded_installer"
  mv -f "$downloaded_installer" "$INSTALLED_SCRIPT"
  log 'Verified and refreshed the per-user updater.'
}

verify_app_bundle() {
  local candidate="$1"
  local info_plist="${candidate}/Contents/Info.plist"
  [[ -d "$candidate" && -f "$info_plist" ]]
  [[ "$(json_value "$info_plist" CFBundleIdentifier)" == "$EXPECTED_BUNDLE_ID" ]]
  [[ "$(json_value "$info_plist" CFBundleVersion)" == "$BUNDLE_VERSION" ]]
  [[ "$(json_value "$info_plist" CFBundleShortVersionString)" == "$SHORT_VERSION" ]]
  /usr/bin/codesign --verify --deep --strict "$candidate"
}

reject_downgrade() {
  if [[ ! -d "$APP_PATH" ]]; then
    return
  fi

  local installed_info="${APP_PATH}/Contents/Info.plist"
  local installed_build
  installed_build="$(json_value "$installed_info" CFBundleVersion 2>/dev/null || true)"
  if [[ "$installed_build" =~ ^[0-9]+$ ]] && \
     [[ "$BUNDLE_VERSION" -lt "$installed_build" ]]; then
    log "Rejected build $BUNDLE_VERSION because installed build $installed_build is newer."
    return 1
  fi
}

prune_stale_prepared_releases() {
  local keep_dir="$1"
  local candidate
  for candidate in "$PREPARED_ROOT"/*; do
    if [[ -d "$candidate" && "$candidate" != "$keep_dir" ]]; then
      safe_remove_tree "$candidate"
    fi
  done
}

prepare_latest_release() {
  rm -f "$ERROR_STATE"
  fetch_and_verify_manifest
  reject_downgrade

  local requested_tag=''
  if [[ -f "$PREPARE_REQUEST" ]]; then
    requested_tag="$(json_value "$PREPARE_REQUEST" tag_name 2>/dev/null || true)"
  fi
  if [[ -n "$requested_tag" && "$requested_tag" != "$TAG_NAME" ]]; then
    log "Requested $requested_tag but the signed current release is $TAG_NAME."
  fi

  local prepared_app="${PREPARED_ROOT}/${TAG_NAME}/${EXPECTED_APP_NAME}"
  if [[ -d "$prepared_app" && -f "$PREPARED_STATE" ]] && \
     [[ "$(json_value "$PREPARED_STATE" tag_name 2>/dev/null || true)" == "$TAG_NAME" ]]; then
    verify_app_bundle "$prepared_app"
    rm -f "$ERROR_STATE" "$PREPARE_REQUEST"
    log "Release $TAG_NAME is already prepared."
    return
  fi

  local archive_path="${WORK_ROOT}/${ARCHIVE_NAME}"
  local extract_root="${WORK_ROOT}/extracted"
  download "$ARCHIVE_URL" "$archive_path"
  verify_sha256 "$archive_path" "$ARCHIVE_SHA256"
  mkdir -p "$extract_root"
  /usr/bin/ditto -x -k "$archive_path" "$extract_root"

  local extracted_app="${extract_root}/${EXPECTED_APP_NAME}"
  verify_app_bundle "$extracted_app"

  local prepared_dir="${PREPARED_ROOT}/${TAG_NAME}"
  if [[ -d "$prepared_dir" ]]; then
    safe_remove_tree "$prepared_dir"
  fi
  mkdir -p "$prepared_dir"
  /usr/bin/ditto "$extracted_app" "$prepared_app"
  verify_app_bundle "$prepared_app"

  # The operator explicitly opted into this internal distribution channel.
  # Gatekeeper remains enabled globally; quarantine is removed only from the
  # archive whose release manifest signature, SHA-256 and bundle were verified.
  /usr/bin/xattr -dr com.apple.quarantine "$prepared_app" 2>/dev/null || true

  refresh_installed_updater
  write_release_state "$PREPARED_STATE" "$TAG_NAME"
  write_release_state "${SUPPORT_ROOT}/prepared-release.json" "$TAG_NAME"
  prune_stale_prepared_releases "$prepared_dir"
  rm -f "$ERROR_STATE" "$PREPARE_REQUEST"
  log "Prepared Vinabike ERP $TAG_NAME."
}

wait_for_process_exit() {
  local process_id="$1"
  if [[ ! "$process_id" =~ ^[0-9]+$ || "$process_id" -eq 0 ]]; then
    return
  fi

  local attempt=0
  while /bin/kill -0 "$process_id" 2>/dev/null && [[ $attempt -lt 90 ]]; do
    /bin/sleep 1
    attempt=$((attempt + 1))
  done

  if /bin/kill -0 "$process_id" 2>/dev/null; then
    log "The running app did not exit within 90 seconds."
    return 1
  fi
}

app_is_running() {
  /usr/bin/pgrep -f "${APP_PATH}/Contents/MacOS/vinabike_erp" >/dev/null 2>&1
}

launch_installed_app() {
  /usr/bin/open "$APP_PATH"
  local attempt=0
  while [[ $attempt -lt 20 ]]; do
    /bin/sleep 1
    if app_is_running; then
      return 0
    fi
    attempt=$((attempt + 1))
  done
  return 1
}

apply_prepared_release() {
  local requested_tag=''
  local process_id='0'
  if [[ -f "$APPLY_REQUEST" ]]; then
    requested_tag="$(json_value "$APPLY_REQUEST" tag_name 2>/dev/null || true)"
    process_id="$(json_value "$APPLY_REQUEST" process_id 2>/dev/null || printf '0')"
  elif [[ -f "$PREPARED_STATE" ]]; then
    requested_tag="$(json_value "$PREPARED_STATE" tag_name)"
  fi

  if [[ -z "$requested_tag" ]]; then
    log 'No prepared macOS release was requested for installation.'
    return
  fi

  APPLY_ATTEMPTED='YES'
  rm -f "$ERROR_STATE"
  fetch_and_verify_manifest
  reject_downgrade
  if [[ "$requested_tag" != "$TAG_NAME" ]]; then
    log "Prepared request $requested_tag no longer matches signed release $TAG_NAME."
    return 1
  fi

  local prepared_app="${PREPARED_ROOT}/${TAG_NAME}/${EXPECTED_APP_NAME}"
  verify_app_bundle "$prepared_app"
  wait_for_process_exit "$process_id"

  mkdir -p "$APP_PARENT" "$ROLLBACK_ROOT"
  local rollback_app="${ROLLBACK_ROOT}/Vinabike ERP.previous.app"
  if [[ -d "$rollback_app" ]]; then
    safe_remove_tree "$rollback_app"
  fi
  if [[ -d "$APP_PATH" ]]; then
    mv "$APP_PATH" "$rollback_app"
  fi

  if ! mv "$prepared_app" "$APP_PATH"; then
    if [[ -d "$rollback_app" && ! -d "$APP_PATH" ]]; then
      mv "$rollback_app" "$APP_PATH"
    fi
    log 'Could not place the prepared application in the install location.'
    return 1
  fi

  if ! verify_app_bundle "$APP_PATH"; then
    safe_remove_tree "$APP_PATH"
    if [[ -d "$rollback_app" ]]; then
      mv "$rollback_app" "$APP_PATH"
    fi
    log 'Installed bundle verification failed; restored the previous version.'
    return 1
  fi

  rm -f "$APPLY_REQUEST" "$PREPARED_STATE" "${SUPPORT_ROOT}/prepared-release.json" "$ERROR_STATE"

  if [[ "${VINABIKE_SKIP_LAUNCH:-NO}" != 'YES' ]]; then
    if ! launch_installed_app; then
      safe_remove_tree "$APP_PATH"
      if [[ -d "$rollback_app" ]]; then
        mv "$rollback_app" "$APP_PATH"
        /usr/bin/open "$APP_PATH" || true
      fi
      write_error_state 'La versión nueva no abrió y se restauró la anterior.'
      log 'The new app did not remain running; restored the previous version.'
      return 1
    fi
  fi

  write_release_state "$CURRENT_STATE" "$TAG_NAME"
  write_release_state "${SUPPORT_ROOT}/current-release.json" "$TAG_NAME"
  prune_stale_prepared_releases ''

  log "Installed and launched Vinabike ERP $TAG_NAME."
}

install_launch_agent() {
  if [[ "$TEST_MODE" == 'YES' || "${VINABIKE_SKIP_LAUNCH_AGENT:-NO}" == 'YES' ]]; then
    return
  fi

  mkdir -p "$LAUNCH_AGENTS_ROOT" "$COORDINATION_ROOT" "$UPDATER_ROOT"
  cat > "$LAUNCH_AGENT_PATH" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>${UPDATE_LABEL}</string>
  <key>ProgramArguments</key>
  <array>
    <string>${INSTALLED_SCRIPT}</string>
    <string>--service</string>
  </array>
  <key>WatchPaths</key>
  <array>
    <string>${PREPARE_REQUEST}</string>
    <string>${APPLY_REQUEST}</string>
  </array>
  <key>ProcessType</key>
  <string>Background</string>
  <key>ThrottleInterval</key>
  <integer>10</integer>
  <key>StandardOutPath</key>
  <string>${LAUNCH_AGENT_LOG_PATH}</string>
  <key>StandardErrorPath</key>
  <string>${LAUNCH_AGENT_LOG_PATH}</string>
</dict>
</plist>
EOF
  /usr/bin/plutil -lint "$LAUNCH_AGENT_PATH" >/dev/null
  /bin/launchctl bootout "gui/$(id -u)" "$LAUNCH_AGENT_PATH" >/dev/null 2>&1 || true
  /bin/launchctl bootstrap "gui/$(id -u)" "$LAUNCH_AGENT_PATH"
  log 'Installed the per-user background update agent.'
}

run_service() {
  if [[ -f "$PREPARE_REQUEST" ]]; then
    prepare_latest_release
  fi
  if [[ -f "$APPLY_REQUEST" ]]; then
    apply_prepared_release
  fi
}

main() {
  mkdir -p "$SUPPORT_ROOT"
  acquire_lock
  rotate_log_if_large "$LOG_PATH"
  rotate_log_if_large "$LAUNCH_AGENT_LOG_PATH"
  mkdir -p "$COORDINATION_ROOT" "$PREPARED_ROOT" "$ROLLBACK_ROOT"

  case "$MODE" in
    install)
      if [[ "$QUIET" != 'YES' ]]; then
        printf '%s\n' \
          'Vinabike ERP se instalará para este usuario y usará el canal interno de actualizaciones.' \
          'Gatekeeper no se desactiva. Solo se elimina la cuarentena del paquete después de verificar firma, hash, bundle ID y versión.'
      fi
      prepare_latest_release
      install_launch_agent
      apply_prepared_release
      ;;
    prepare)
      prepare_latest_release
      ;;
    apply)
      apply_prepared_release
      ;;
    service)
      run_service
      ;;
  esac
}

main
