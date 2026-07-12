#!/usr/bin/env bash

set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR" || exit 1

export VOLTA_HOME="${VOLTA_HOME:-$HOME/.volta}"
export PATH="$VOLTA_HOME/bin:/opt/homebrew/opt/libpq/bin:$HOME/.local/bin:$PATH"

ERRORS=0
WARNINGS=0

pass() { printf 'PASS  %s\n' "$*"; }
warn() { printf 'WARN  %s\n' "$*"; WARNINGS=$((WARNINGS + 1)); }
fail() { printf 'FAIL  %s\n' "$*"; ERRORS=$((ERRORS + 1)); }

require_command() {
  local command_name="$1"
  local fix="$2"
  if command -v "$command_name" >/dev/null 2>&1; then
    pass "$command_name: $(command -v "$command_name")"
  else
    fail "$command_name missing — $fix"
  fi
}

require_command git "run the platform bootstrap"
require_command gh "run the platform bootstrap"
require_command fvm "run the platform bootstrap"
require_command volta "run the platform bootstrap"
require_command node "run the platform bootstrap"
require_command npm "run the platform bootstrap"
require_command uv "run the platform bootstrap"
require_command just "run the platform bootstrap"
require_command docker "run the platform bootstrap"
require_command psql "run the platform bootstrap"
require_command gitleaks "run the platform bootstrap"

if command -v fvm >/dev/null 2>&1 && fvm flutter --version --machine >/tmp/vinabike_flutter_version.json 2>/dev/null; then
  expected="$(jq -r .flutter .fvmrc)"
  actual="$(jq -r .frameworkVersion /tmp/vinabike_flutter_version.json)"
  if [[ "$actual" == "$expected" ]]; then
    pass "Flutter $actual matches .fvmrc"
  else
    fail "Flutter $actual does not match required $expected — run: fvm install $expected && fvm use $expected --force"
  fi
else
  fail "FVM Flutter SDK is not ready — run the platform bootstrap"
fi
rm -f /tmp/vinabike_flutter_version.json

if command -v node >/dev/null 2>&1; then
  expected_node="$(jq -r .node toolchain.json)"
  actual_node="$(node --version 2>/dev/null | sed 's/^v//')"
  if [[ "$actual_node" == "$expected_node" ]]; then
    pass "Node $actual_node matches toolchain.json"
  else
    fail "Node $actual_node does not match $expected_node — run: volta install node@$expected_node"
  fi
fi

if command -v docker >/dev/null 2>&1; then
  if docker info >/dev/null 2>&1; then
    pass "Docker runtime is reachable"
  else
    warn "Docker CLI exists but the runtime is stopped — start Docker Desktop or run: colima start"
  fi
fi

if gh auth status >/dev/null 2>&1; then
  pass "GitHub CLI authentication is valid"
else
  warn "GitHub CLI is not authenticated — run: gh auth login"
fi

if [[ -f .env ]]; then
  mode="$(stat -f '%Lp' .env 2>/dev/null || stat -c '%a' .env 2>/dev/null || true)"
  if [[ "$mode" == "600" ]]; then
    pass ".env permissions are owner-only"
  else
    warn ".env should be owner-only — run: chmod 600 .env"
  fi
else
  warn ".env is absent; copy .env.example only when local runtime credentials are needed"
fi

if [[ -f android/gradle/wrapper/gradle-wrapper.jar ]]; then
  pass "Root Android Gradle wrapper is present"
else
  fail "Root Android Gradle wrapper jar is missing"
fi
if [[ -f mobile_scanner_app/android/gradle/wrapper/gradle-wrapper.jar ]]; then
  pass "Scanner Android Gradle wrapper is present"
else
  fail "Scanner Android Gradle wrapper jar is missing"
fi

free_kb="$(df -Pk . | awk 'NR==2 {print $4}')"
if [[ "$free_kb" -lt 10485760 ]]; then
  warn "Less than 10 GB disk space is free"
else
  pass "Disk space is sufficient for normal development"
fi

if [[ "$ERRORS" -gt 0 ]]; then
  printf '\nDoctor failed: %d blocker(s), %d warning(s).\n' "$ERRORS" "$WARNINGS" >&2
  exit 1
fi

printf '\nDoctor passed with %d warning(s).\n' "$WARNINGS"
