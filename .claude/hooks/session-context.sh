#!/usr/bin/env bash
set -euo pipefail

# Consume the hook payload even though this hook needs no event fields.
cat >/dev/null

project_dir="${CLAUDE_PROJECT_DIR:-$(pwd)}"
if ! git -C "$project_dir" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  exit 0
fi

branch="$(git -C "$project_dir" branch --show-current 2>/dev/null || true)"
head="$(git -C "$project_dir" rev-parse --short HEAD 2>/dev/null || true)"
changed_count="$(
  git -C "$project_dir" status --porcelain=v1 2>/dev/null |
    awk 'END { print NR + 0 }'
)"

printf '%s\n' \
  "Shared checkout context: branch=${branch:-detached}, HEAD=${head:-unknown}, pre-existing changed paths=$changed_count." \
  "Preserve every unrelated change; never reset or clean the shared tree." \
  "Claude preflight: Code mode + bikeshop-erp + Fable 5 preferred (Opus 5 allowed) + Effort: Ultracode. Verify the visible labels and intended chat immediately before Send; Extra is not accepted." \
  "UI redesign: Codex and the operator own product workflow, information architecture and layout by default; GUÍA GENERAL supplies visual grammar. Only when the owner explicitly requests Claude/Design input, contribute an independent proposal or review, inspect the relevant concept in ERP Bikeshop UI Mockups and name it in the handoff; never treat a module canvas as required or authoritative." \
  "Use .fvm/flutter_sdk/bin/dart and .fvm/flutter_sdk/bin/flutter for Dart/Flutter commands." \
  "Before shared work closes, follow docs/development/CODEX_CLAUDE_COLLABORATION.md and run the cross-review skill."
