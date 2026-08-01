#!/usr/bin/env bash
set -euo pipefail

payload="$(cat)"
tool_name="$(jq -r '.tool_name // ""' <<<"$payload")"
command_text="$(jq -r '.tool_input.command // ""' <<<"$payload")"

if [[ "$tool_name" != "Bash" || -z "$command_text" ]]; then
  exit 0
fi

deny() {
  local reason="$1"
  jq -n --arg reason "$reason" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: $reason
    }
  }'
  exit 0
}

# Normalize quoting and line breaks for conservative command inspection. This
# intentionally also sees commands nested in `sh -c`/`bash -c`; the hook is the
# last safety boundary when Claude Desktop starts in bypassPermissions mode.
command_scan="$(
  printf '%s' "$command_text" |
    tr '\r\n\t' '   ' |
    sed "s/[\"']/ /g"
)"
tool_boundary='(^|[[:space:];|&()])([^[:space:];|&()]*/)?'
# Only documented Git global options may precede the top-level subcommand.
# An arbitrary "some tokens, then push" prefix confuses command arguments with
# the subcommand (for example, `git stash push` used to look like `git push`).
git_global_argument='(-[cC][[:space:]]+[^[:space:];|&()]+|-[cC][^[:space:];|&()]+|--(git-dir|work-tree|namespace|super-prefix|config-env|exec-path|attr-source)(=[^[:space:];|&()]+|[[:space:]]+[^[:space:];|&()]+)|--(bare|no-pager|paginate|no-replace-objects|no-lazy-fetch|no-optional-locks|no-advice|literal-pathspecs|glob-pathspecs|noglob-pathspecs|icase-pathspecs)|-[pP])'
git_command="${tool_boundary}git[[:space:]]+(${git_global_argument}[[:space:]]+)*"

command_matches() {
  printf '%s' "$command_scan" | grep -Eq -- "$1"
}

# The Claude Desktop local agent currently starts in bypassPermissions mode.
# PreToolUse hooks still execute in that mode, so this is the durable boundary
# for actions that require an explicit owner decision or a safer operator.
# 2026-07-31 · decisión del dueño: commit, push, PR y restore quedan en manos
# del agente. Sólo la reescritura de historia sigue siendo suya.
if command_matches "${git_command}(rebase)([[:space:]]|$)"; then
  deny "History rewrites are owner-controlled."
fi

# Deshacer una edición propia sobre archivos NOMBRADOS es recuperación, y por
# eso `restore` dejó de estar en la lista de arriba. Barrer el árbol entero no
# lo es: `git restore .` descarta el trabajo sin commitear de quien esté
# compartiendo el checkout, y `--staged`/`--source` traen contenido de otra
# revisión. Eso sigue siendo del dueño.
# El `=` cuenta como cierre del flag: `--source=HEAD~1` es la forma habitual.
if command_matches "${git_command}restore[[:space:]]+([^;|&()]*[[:space:]])?(--staged|--source|--pathspec-from-file|[.*]|:/)([[:space:]=]|$)"; then
  deny "Un restore de alcance abierto puede descartar el trabajo sin commitear de otro. Nombra las rutas: git restore -- <ruta> [<ruta>...]"
fi

# `git checkout name` is inherently ambiguous: when `name` is not a branch it
# can be a path restore, and `checkout TREE PATH` needs no `--` separator.
# Branch movement remains available through the unambiguous `git switch`.
if command_matches "${git_command}checkout([[:space:]]|$)"; then
  deny "Git checkout can restore paths and discard shared changes. Use git switch for branch changes."
fi

if command_matches "${git_command}stash([[:space:]]|$)" ||
   command_matches "${git_command}reset[[:space:]]+[^;|&()]*--hard([[:space:]]|$)" ||
   command_matches "${git_command}clean[[:space:]]+[^;|&()]*(-[^[:space:];|&()]*f[^[:space:];|&()]*|--force)([[:space:]]|$)" ||
   command_matches "${git_command}switch[[:space:]]+([^;|&()]*[[:space:]])?(-f|--force|--discard-changes|-C[^[:space:];|&()]*)([[:space:]]|$)" ||
   command_matches "${git_command}branch[[:space:]]+([^;|&()]*[[:space:]])?-D([[:space:]]|$)"; then
  deny "Destructive Git cleanup is forbidden in the shared checkout."
fi

if command_matches "${tool_boundary}rm([[:space:]]+[^[:space:];|&()]+)*[[:space:]]+(-[^[:space:];|&()]*[rR][^[:space:];|&()]*|--recursive)([[:space:]]|$)" ||
   command_matches "${tool_boundary}find[[:space:]]+[^;|&()]*[[:space:]]-delete([[:space:]]|$)" ||
   command_matches "${tool_boundary}(kill|killall|pkill)([[:space:]]|$)"; then
  deny "Recursive deletion and generic process signaling are blocked. Use the canonical preview owner or a recoverable, exact target."
fi

if command_matches "${tool_boundary}psql([[:space:]]|$)" ||
   command_matches "${tool_boundary}supabase[[:space:]]+([^;|&()]+[[:space:]]+)*(db|migration)([[:space:]]|$)"; then
  deny "Raw SQL and Supabase database commands bypass the audited repository database contract."
fi

if [[ "$command_scan" == *"production"* &&
      "$command_scan" == *"--allow-pii"* &&
      ( "$command_scan" == *"scripts/db/query.sh"* ||
        "$command_scan" == *"just db-query"* ) ]]; then
  deny "Hosted PII override is not pre-approved. Hand the exact columns and necessity back to Codex/the owner."
fi

if [[ "$command_scan" == *"production"* &&
      "$command_scan" == *"--write"* &&
      ( "$command_scan" == *"scripts/db/query.sh"* ||
        "$command_scan" == *"just db-query"* ) ]]; then
  deny "Production database writes require explicit owner authorization and must be executed through the guarded workflow by Codex."
fi

if [[ "$command_scan" == *"scripts/db/production_validation.sh refresh"* ]]; then
  deny "Refreshing the production-derived database cache is an external read with operational impact; hand it back to Codex."
fi

# 2026-08-01 · decisión del dueño: publicar la actualización del ERP es del
# agente. `scripts/publish_*` y `scripts/releases/*` salen de la lista — la
# tarea macOS+Android es UNA sola y el guard trataba sus dos mitades distinto
# (Android pasaba, macOS no), que fue lo que llevó a cancelar el run equivocado.
# Sigue siendo del dueño lo que toca infraestructura fuera del ciclo de release:
# desplegar funciones, migraciones y `scripts/deploy.sh`.
# El script se reconoce en POSICIÓN DE COMANDO, no como texto suelto. Un
# `==  *"scripts/deploy.sh"*` compara contra todo el comando, así que escribir
# la ruta dentro de un documento —un ledger, un mensaje de commit, un test que
# la lista— quedaba denegado por *mencionarla*. Pasó cinco veces en un día.
deploy_script='(^|[;|&][[:space:]]*)([^[:space:];|&()]*(bash|sh|zsh)[[:space:]]+)?[^[:space:];|&()]*scripts/deploy\.sh([[:space:]]|$)'
if command_matches "${tool_boundary}firebase[[:space:]]+([^;|&()]+[[:space:]]+)*deploy([[:space:]]|$)" ||
   command_matches "${tool_boundary}supabase[[:space:]]+([^;|&()]+[[:space:]]+)*functions[[:space:]]+deploy([[:space:]]|$)" ||
   command_matches "$deploy_script"; then
  if ! printf '%s' "$command_scan" | grep -Eq -- '(^|[;|&])[[:space:]]*(pgrep|grep|rg|ps)[[:space:]]'; then
    deny "Deployment, release, and publication are owner-controlled external mutations."
  fi
fi
