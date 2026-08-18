#!/bin/bash
# Owner of the canonical macOS debug session for agent-driven verification.
#
#   native_session.sh start     # launch `flutter run -d macos` inside screen
#   native_session.sh status    # session + app + VM service state
#   native_session.sh reload    # hot reload  (r)  ~2-5 s
#   native_session.sh restart   # hot restart (R)  ~3-5 s
#   native_session.sh log [n]   # tail the run log
#   native_session.sh errors    # only compile/exception lines
#   native_session.sh doctor    # WHY it is not responding (wedged compiler…)
#   native_session.sh stop      # end the session it owns
#
# Read docs/development/AGENT_MACOS_APP_CONTROL.md before using this.
#
# Hard rules encoded here (they cost real time when broken):
#   - Only ONE Flutter session may be alive. `start` refuses if one exists.
#   - `flutter run` must keep a TTY. Piping it to `tee` silently disables the
#     single-key commands, so logging goes through screen's own logfile.
#   - Keystrokes need an explicit window: `screen -S <s> -p 0 -X stuff`.
#     Without `-p 0` the key is swallowed and the reload never happens.
#   - This script never pattern-kills Flutter/Dart. `stop` captures the exact
#     descendant tree of ITS screen before closing it, asks `flutter run` to
#     quit gracefully with `q`, and only then terminates that captured tree —
#     leaf first — verifying nothing survives. Closing screen alone leaves
#     login/flutter/frontend orphaned on init (observed twice on 2026-08-01).
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT" || exit 1

SESSION="${NATIVE_SESSION_NAME:-payroll}"
RUN_DIR="$REPO_ROOT/.tmp/native-session"
LOG="${NATIVE_SESSION_LOG:-$RUN_DIR/run.log}"
SCREENRC="$RUN_DIR/screenrc"
FLUTTER="$REPO_ROOT/.fvm/flutter_sdk/bin/flutter"
TARGET="${NATIVE_SESSION_TARGET:-lib/main.dart}"
DEBUG_APP_GLOB="build/macos/Build/Products/Debug/vinabike_erp.app/Contents/MacOS/vinabike_erp"

# Closed compile-time rollout inputs. The canonical development session runs the
# same modern AI gateway as release builds by default; legacy is available only
# as an explicit rollback with `NATIVE_SESSION_AI_AGENT_GATEWAY_ENABLED=false`.
# Both values are emitted as dart-defines so the selected runtime is visible in
# the process arguments instead of being inferred from an absent flag. The
# owner must preserve argument boundaries and never eval caller-controlled text.
# The modern Supabase key is public, but it is still kept out of this script and
# its logs.
FLUTTER_ROLLOUT_ARGS=()
AI_AGENT_GATEWAY_MODE="${NATIVE_SESSION_AI_AGENT_GATEWAY_ENABLED:-true}"
case "$AI_AGENT_GATEWAY_MODE" in
  true) FLUTTER_ROLLOUT_ARGS+=(--dart-define=AI_AGENT_GATEWAY_ENABLED=true) ;;
  false) FLUTTER_ROLLOUT_ARGS+=(--dart-define=AI_AGENT_GATEWAY_ENABLED=false) ;;
  '') echo "NATIVE_SESSION_AI_AGENT_GATEWAY_ENABLED no puede estar vacío" >&2; exit 64 ;;
  *) echo "NATIVE_SESSION_AI_AGENT_GATEWAY_ENABLED debe ser true o false" >&2; exit 64 ;;
esac

# The public client key is process configuration, not repository state. Prefer
# an explicit per-launch value, otherwise use the approved Keychain entry. A
# gateway launch without it used to compile successfully and fail only after
# the operator sent a message, which made a broken session look healthy.
NATIVE_PUBLISHABLE_KEY="${NATIVE_SESSION_SUPABASE_PUBLISHABLE_KEY:-}"
if [ -z "$NATIVE_PUBLISHABLE_KEY" ] && [ "$AI_AGENT_GATEWAY_MODE" = true ] \
   && command -v security >/dev/null 2>&1; then
  NATIVE_PUBLISHABLE_KEY="$(security find-generic-password \
    -s 'Vinabike ERP Supabase publishable key' \
    -a supabase -w 2>/dev/null || true)"
fi
if [ -n "$NATIVE_PUBLISHABLE_KEY" ]; then
  case "$NATIVE_PUBLISHABLE_KEY" in
    sb_publishable_*)
      FLUTTER_ROLLOUT_ARGS+=(
        "--dart-define=SUPABASE_PUBLISHABLE_KEY=$NATIVE_PUBLISHABLE_KEY"
      )
      ;;
    *) echo "NATIVE_SESSION_SUPABASE_PUBLISHABLE_KEY no es una publishable key válida" >&2; exit 64 ;;
  esac
elif [ "$AI_AGENT_GATEWAY_MODE" = true ]; then
  echo "El gateway IA requiere la publishable key en Keychain o NATIVE_SESSION_SUPABASE_PUBLISHABLE_KEY." >&2
  exit 64
fi

app_pid() { pgrep -f "$DEBUG_APP_GLOB" | head -1; }
# `screen -ls` exits 1 even when sessions exist, so under `set -o pipefail` a
# direct `screen -ls | grep -q` pipeline always reports "no session" — which
# silently disabled reload/restart/stop AND let `start` open a second session.
# Capture the listing first so only grep decides the status.
session_alive() {
  local listing
  listing="$(screen -ls 2>/dev/null | tr -d "\r")"
  printf '%s\n' "$listing" | grep -q "\.${SESSION}[[:space:]]"
}

vm_uri() {
  grep -a "Dart VM Service on macOS is available at:" "$LOG" 2>/dev/null |
    tail -1 | sed 's/.*at: //' | tr -d ' \r\n'
}

# `grep -c` prints the count but exits 1 when it is zero, so the old
# `grep -ac … || echo 0` emitted TWO lines ("0\n0") and every numeric test
# died with "integer expression expected". Let grep print, ignore its status.
marker_count() { # marker_count <pattern>
  local n
  n="$(grep -ac "$1" "$LOG" 2>/dev/null || true)"
  printf '%s' "${n:-0}"
}

send_key() {
  session_alive || { echo "no hay sesión '$SESSION'; usa start" >&2; return 1; }
  screen -S "$SESSION" -p 0 -X stuff "$1"
}

wait_for() { # wait_for <regex> <seconds>
  local pattern="$1" limit="$2" start
  start=$(date +%s)
  until grep -aq "$pattern" "$LOG" 2>/dev/null; do
    [ $(( $(date +%s) - start )) -ge "$limit" ] && return 1
    sleep 1
  done
  return 0
}

case "${1:-}" in
  start)
    if session_alive; then
      echo "ya existe la sesión '$SESSION'. Usa reload/restart, o stop primero." >&2
      exit 1
    fi
    other="$(app_pid)"
    if [ -n "$other" ]; then
      echo "hay una app debug viva (pid $other) sin sesión screen." >&2
      echo "ciérrala desde su ventana (o desde VS Code) antes de continuar." >&2
      exit 1
    fi
    mkdir -p "$RUN_DIR"
    : > "$LOG"
    # screen 4.x (el de macOS) no acepta -Logfile: el destino se declara aquí.
    printf 'logfile %s\nlogfile flush 1\ndeflog on\n' "$LOG" > "$SCREENRC"
    if [ "${#FLUTTER_ROLLOUT_ARGS[@]}" -gt 0 ]; then
      screen -c "$SCREENRC" -dmS "$SESSION" "$FLUTTER" run -d macos -t "$TARGET" \
        "${FLUTTER_ROLLOUT_ARGS[@]}"
    else
      # Bash 3.2 treats an empty-array expansion as an unbound variable under
      # `set -u`, so keep the no-rollout launch path argument-free.
      screen -c "$SCREENRC" -dmS "$SESSION" "$FLUTTER" run -d macos -t "$TARGET"
    fi
    echo "compilando… (primer arranque ~1-2 min, luego los reload son de segundos)"
    if wait_for "Flutter run key commands" 900; then
      echo "app arriba · pid $(app_pid) · VM $(vm_uri)"
    else
      echo "no llegó a arrancar; revisa: $0 errors" >&2
      exit 1
    fi
    ;;

  status)
    if session_alive; then
      echo "screen: activa (sesión=$SESSION)"
      echo "attach: screen -x $SESSION  # sirve aunque ya figure Attached"
      echo "control: $0 reload | $0 restart"
    else
      echo "screen: no existe (sesión esperada=$SESSION)"
    fi
    pid="$(app_pid)"
    [ -n "$pid" ] && echo "app:    pid $pid" || echo "app:    no corre"
    uri="$(vm_uri)"
    [ -n "$uri" ] && echo "vm:     $uri" || echo "vm:     sin URI en el log"
    ;;

  reload|restart)
    key='r'; label='Reloaded'
    [ "$1" = "restart" ] && { key='R'; label='Restarted application in'; }
    before=$(marker_count "$label")
    send_key "$key" || exit 1
    start=$(date +%s)
    while [ "$(marker_count "$label")" -le "$before" ]; do
      if [ $(( $(date +%s) - start )) -ge 90 ]; then
        # "sin respuesta" no dice nada: la causa hay que nombrarla. Las tres
        # que existen se distinguen sin ambigüedad desde acá.
        echo "el reload no confirmó en 90 s. Causa:" >&2
        "$0" doctor >&2
        exit 1
      fi
      sleep 1
    done
    grep -a "$label" "$LOG" | tail -1
    ;;

  # Por qué no responde la sesión. Existe porque el 2026-07-31 un compilador
  # trabado se leyó como "el dueño tiene tomada la sesión" y se perdió una
  # ronda entera mirando el síntoma equivocado.
  doctor)
    session_alive || { echo "  · no hay sesión '$SESSION'. Usa: $0 start"; exit 0; }
    pid="$(app_pid)"
    [ -n "$pid" ] || echo "  · la app no corre aunque el screen existe: $0 stop && $0 start"

    # 1. ¿El log sigue vivo? screen escribe cada segundo mientras haya salida.
    if [ -f "$LOG" ]; then
      age=$(( $(date +%s) - $(stat -f %m "$LOG") ))
      if [ "$age" -gt 60 ]; then
        echo "  · el log lleva ${age}s sin crecer (última línea: $(tail -c 200 "$LOG" | tr -d '\r' | tail -1))"
      fi
    fi

    # 2. ¿Hay un reload colgado? Se reconoce por el log: la última línea quedó
    #    en el spinner y nunca llegó su "Reloaded".
    #
    #    Este diagnóstico es de SÓLO LECTURA a propósito. La primera versión
    #    pedía un `reloadSources` al VM service para "comprobar", y eso disparaba
    #    un segundo reload encima del que ya corría: los dos morían con
    #    "Error while starting Kernel isolate task" y el doctor reportaba
    #    trabado un compilador que él mismo acababa de trabar. **Nunca
    #    diagnostiques con una llamada que muta.**
    last="$(tail -c 400 "$LOG" 2>/dev/null | tr -d '\r' | tail -1)"
    case "$last" in
      *"Performing hot reload"*|*"Performing hot restart"*)
        echo "  · hay un reload EN CURSO o colgado (el log terminó en el spinner)."
        echo "    NO mandes otro: dos reloads simultáneos se matan entre sí."
        echo "    Espera, y si no avanza en ~2 min: $0 stop && $0 start" ;;
    esac

    uri="$(vm_uri)"
    if [ -n "$uri" ]; then
      # Sólo lectura: confirma que la app respira, sin tocar el compilador.
      if python3 - "$uri" <<'PY' >/dev/null 2>&1
import json, sys, urllib.request
uri = sys.argv[1].strip().rstrip('/')
with urllib.request.urlopen(f"{uri}/getVM", timeout=15) as response:
    json.load(response)['result']['isolates'][0]['id']
PY
      then
        echo "  · el VM service responde (la app está viva)"
      else
        echo "  · el VM service no responde: $0 stop && $0 start"
      fi
    fi

    # 3. ¿Hay alguien mirando? Informativo: NO impide recargar, y confundirlo
    #    con la causa fue justamente el error del 31/07.
    if screen -ls 2>/dev/null | tr -d '\r' | grep -q "\.${SESSION}[[:space:]].*Attached"; then
      echo "  · hay un 'screen -x $SESSION' abierto (informativo: no bloquea el reload)"
    fi
    ;;

  log)   tail -n "${2:-40}" "$LOG" ;;
  errors)
    grep -aiE "Compiler message|^lib/.*(Error|error:)|EXCEPTION|Unhandled|overflowed" \
      "$LOG" 2>/dev/null | tail -n "${2:-20}"
    ;;

  stop)
    session_alive || { echo "no hay sesión '$SESSION'"; exit 0; }

    # 2026-08-01 · `stop` era sólo `screen -X quit`. Eso mata screen y deja
    # `login → flutter → frontend` colgando de init: dos árboles huérfanos
    # quemando CPU, y el `start` siguiente negándose por "app debug viva sin
    # sesión screen". El árbol se captura ANTES de cerrar screen, porque en
    # cuanto screen muere ya no hay forma de saber cuáles descendientes eran
    # suyos sin adivinar por patrón — que es justo lo que este script no hace.
    screen_pid="$(screen -ls 2>/dev/null | awk -v s="$SESSION" '
      $1 ~ ("\\." s "$") { split($1, a, "."); print a[1]; exit }')"

    # FALLA CERRADO. Si no se puede resolver la screen o su árbol, lo que NO se
    # puede hacer es cerrar screen igual y declarar «sin descendientes»: eso es
    # exactamente cómo se produjeron los huérfanos. Se aborta y se dice.
    if [ -z "$screen_pid" ]; then
      echo "no se pudo resolver el pid de la screen '$SESSION'." >&2
      echo "NO se cierra nada: cerrarla a ciegas dejaría su árbol huérfano." >&2
      exit 1
    fi

    owned_tree=""
    collect_tree() {
      local p="$1" c
      owned_tree="$owned_tree $p"
      for c in $(pgrep -P "$p" 2>/dev/null); do collect_tree "$c"; done
    }
    # TODOS los hijos directos, no el primero: `screen` puede tener más de una
    # ventana, y quedarse con `head -1` deja las demás fuera de la limpieza.
    for root in $(pgrep -P "$screen_pid" 2>/dev/null); do collect_tree "$root"; done

    if [ -z "${owned_tree// /}" ]; then
      echo "la screen '$SESSION' (pid $screen_pid) no declara descendientes." >&2
      echo "NO se cierra: sin árbol capturado no hay forma de limpiar." >&2
      exit 1
    fi

    # 1 · Salida grácil: `q` es como `flutter run` termina por sí mismo, y así
    #     cierra la app y libera el VM service en orden.
    screen -S "$SESSION" -p 0 -X stuff 'q' 2>/dev/null || true
    for _ in $(seq 1 20); do session_alive || break; sleep 1; done

    # 2 · Si no salió sola, se cierra screen y se termina SÓLO lo capturado
    #     arriba, hoja primero. Nunca por patrón, nunca a un pid ajeno.
    session_alive && { screen -S "$SESSION" -X quit 2>/dev/null || true; }
    for p in $(echo "$owned_tree" | tr ' ' '\n' | tail -r); do
      [ -n "$p" ] && kill -0 "$p" 2>/dev/null && kill "$p" 2>/dev/null || true
    done
    for _ in $(seq 1 10); do
      still=""
      for p in $owned_tree; do kill -0 "$p" 2>/dev/null && still="$still $p"; done
      [ -z "${still// /}" ] && break
      sleep 1
    done
    for p in $owned_tree; do
      kill -0 "$p" 2>/dev/null && kill -9 "$p" 2>/dev/null || true
    done

    # 3 · Se comprueba que no quede descendiente, y si queda **se dice**: un
    #     stop que miente es lo que produjo los huérfanos anteriores.
    leftovers=""
    for p in $owned_tree; do kill -0 "$p" 2>/dev/null && leftovers="$leftovers $p"; done
    if [ -n "${leftovers// /}" ]; then
      echo "sesión '$SESSION' cerrada, PERO quedaron vivos:$leftovers" >&2
      exit 1
    fi
    echo "sesión '$SESSION' cerrada, sin descendientes vivos"
    ;;

  *)
    sed -n '2,20p' "$0"
    exit 1
    ;;
esac
