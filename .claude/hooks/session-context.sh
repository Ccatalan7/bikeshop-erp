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
  "UI design (owner, 2026-09-27): the ERP's look is open. The agent doing the work, Claude or Codex, decides values, containers, component anatomy, visual direction and composition, aiming modern, serious and with personality, never dated or AI'ish; no DesignSync, no GUÍA GENERAL authority, no /design-login wait, no per-frame gate. A Claude Design canvas proposal before a big change is welcome. Still binding: navigation return, canonical surfaces registry, accessibility, phone/tablet, light/dark via theme roles, shared controls improved in their owner, and real app screenshots as proof. Public website brand still comes from the website editor. See .github/GUI_DESIGN_PRINCIPLES.md «El diseño del ERP es abierto»." \
  "Use .fvm/flutter_sdk/bin/dart and .fvm/flutter_sdk/bin/flutter for Dart/Flutter commands." \
  "Before shared work closes, follow docs/development/CODEX_CLAUDE_COLLABORATION.md and run the cross-review skill."
