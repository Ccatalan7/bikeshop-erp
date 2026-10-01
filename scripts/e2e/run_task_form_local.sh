#!/usr/bin/env bash
# C1 por la app (PLANS.md, 2026-09-30): subir, abrir y retirar adjuntos desde
# el TaskFormDialog real de lib/main.dart, con Auth, PostgREST y Storage
# locales. El recorrido lo hace Chrome (Playwright) como el empleado sintético.
#
#   scripts/e2e/run_task_form_local.sh [--start-services] [--reuse-bundle]
#
# 1. Servicios: DB, Auth, PostgREST, Storage y Kong del stack local (con
#    --start-services los arranca como run_task_attachments_local.sh).
# 2. Preparativos administrativos (llave de servicio, nunca en la app ni en el
#    recorrido): retira restos de otra corrida, crea por la API de Auth al
#    mecánico que entra (contraseña de un solo uso) y a la compañera a quien
#    se asigna, y aplica la fixture (taller y perfiles mechanic).
# 3. App: `web_preview.sh build --local` compila lib/main.dart contra el stack
#    local (--reuse-bundle se lo salta si el bundle ya es de este stack) y
#    `start --local` la sirve en http://localhost:54334.
# 4. Recorrido: e2e/task_form_local.spec.ts entra por el login, crea la tarea
#    asignada a la compañera con dos fotos, guarda con Storage detenido y
#    reintenta, sale sin adjuntar tras otro fallo, abre el adjunto, quita uno
#    normal y otro con Storage detenido, y vuelve a entrar para que la app
#    retome la limpieza. Frames en .tmp/e2e/task-form-<fecha>/.
# 5. Readback y retirada: la fixture comprueba lo que quedó; los bytes que
#    sobren se retiran por la API de Storage y el resto por la fixture. Al
#    salir, pase lo que pase: Storage arriba, preview local detenido y retirada.
#
# El log en .tmp/e2e/ guarda sólo pasos y evidencia: ni llaves ni contraseñas.
# Es el cliente web; no acredita por sí solo el cliente nativo.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

FIXTURE="scripts/e2e/task_form_local_fixture.sql"
SPEC="e2e/task_form_local.spec.ts"
EMAIL="task-ui-e2e@vinabike.invalid"
EMPLOYEE_NAME="Tomás Rivas"
COWORKER_EMAIL="task-ui-e2e-otra@vinabike.invalid"
COWORKER_NAME="Javiera Soto"
TASK_TITLE="Cambiar pastillas traseras (Trek Marlin 7)"
PROJECT="bikeshop-erp"
STORAGE_CONTAINER="supabase_storage_${PROJECT}"
REQUIRED_CONTAINERS=(supabase_db supabase_auth supabase_rest supabase_storage supabase_kong)
EXCLUDED_SERVICES="realtime,imgproxy,mailpit,postgres-meta,studio,edge-runtime,logflare,vector,supavisor"
BASE_URL="http://localhost:${ERP_LOCAL_WEB_PORT:-54334}"

start_services=false
reuse_bundle=false
for arg in "$@"; do
  case "$arg" in
    --start-services) start_services=true ;;
    --reuse-bundle) reuse_bundle=true ;;
    *)
      echo "Uso: $0 [--start-services] [--reuse-bundle]" >&2
      exit 64
      ;;
  esac
done

mkdir -p .tmp/e2e
STAMP="$(date +%Y%m%d-%H%M%S)"
LOG=".tmp/e2e/task-form-$STAMP.log"
FRAMES=".tmp/e2e/task-form-$STAMP"
log() { printf '%s %s\n' "$(date -u +%H:%M:%SZ)" "$*" | tee -a "$LOG"; }
redact() { grep -viE 'key|secret|jwt|password|contraseña|token|bearer' || true; }

# Llaves locales, contraseña y cuerpos HTTP: sólo aquí, 0700, y fuera al salir.
private_dir="$(mktemp -d "${TMPDIR:-/tmp}/task-form-e2e.XXXXXX")"
chmod 700 "$private_dir"
needs_retire=false
preview_started=false

fixture() {
  TASK_FORM_E2E_FIXTURE_MODE="$1" bash scripts/db/query.sh local --format table --file "$FIXTURE"
}

storage_running() {
  docker ps --format '{{.Names}}' | grep -qx "$STORAGE_CONTAINER"
}

# El recorrido detiene Storage a propósito; nadie sale con Storage abajo.
ensure_storage_up() {
  storage_running && return 0
  log "Storage: el contenedor quedó detenido; se arranca otra vez"
  docker start "$STORAGE_CONTAINER" >/dev/null 2>&1 || {
    log "ERROR: no se pudo arrancar $STORAGE_CONTAINER"
    return 1
  }
  local tries=0 status
  while ((tries < 45)); do
    status="$(curl -s -o /dev/null -w '%{http_code}' --max-time 3 "$API_URL/storage/v1/status" || true)"
    if [[ "$status" =~ ^[1-4][0-9][0-9]$ ]]; then
      log "Storage: arriba (HTTP $status)"
      return 0
    fi
    tries=$((tries + 1))
    sleep 2
  done
  log "ERROR: Storage no respondió tras arrancarlo"
  return 1
}

# Bytes del taller sintético que queden: por la API de Storage, como admin.
retire_objects() {
  local listing names status
  if ! listing="$(fixture objects 2>&1)"; then
    log "ERROR: la fixture no listó los bytes sintéticos"
    return 1
  fi
  names="$(sed -n 's/^ *\(e2898000-0000-4000-8000-000000000021\/[^ ]*\) *$/\1/p' <<<"$listing")"
  if [[ -z "$names" ]]; then
    log "Storage: sin bytes sintéticos que retirar"
    return 0
  fi
  python3 -c 'import json,sys; print(json.dumps({"prefixes": sys.stdin.read().split()}))' \
    <<<"$names" >"$private_dir/delete.json"
  status="$(curl -sS -o "$private_dir/delete.out" -w '%{http_code}' -X DELETE \
    -H @"$private_dir/admin.headers" -H 'Content-Type: application/json' \
    --data @"$private_dir/delete.json" "$API_URL/storage/v1/object/task-attachments")"
  if [[ "$status" != 200 ]]; then
    log "ERROR: Storage no retiró los bytes sintéticos (HTTP $status)"
    return 1
  fi
  log "Storage: retirados $(wc -l <<<"$names" | tr -d ' ') objeto(s) sintético(s) por la API"
}

retire_all() {
  retire_objects || return 1
  if ! fixture teardown >>"$LOG" 2>&1; then
    log "ERROR: la retirada de la fixture falló"
    return 1
  fi
  log "Retirada: taller, vínculos y usuario sintéticos fuera"
}

on_exit() {
  local status=$?
  if [[ -n "${API_URL:-}" ]]; then
    ensure_storage_up || status=1
  fi
  if [[ "$preview_started" == true ]]; then
    preview_started=false
    scripts/dev/web_preview.sh stop --local >>"$LOG" 2>&1 || status=1
    log "Preview local detenido"
  fi
  if [[ "$needs_retire" == true ]]; then
    needs_retire=false
    retire_all || status=1
  fi
  find "$private_dir" -type f -exec rm -f {} + 2>/dev/null || true
  rmdir "$private_dir" 2>/dev/null || true
  exit "$status"
}
trap on_exit EXIT

die() {
  log "ERROR: $*"
  exit 1
}

services_running() {
  local running name
  running="$(docker ps --format '{{.Names}}')"
  for name in "${REQUIRED_CONTAINERS[@]}"; do
    grep -qx "${name}_${PROJECT}" <<<"$running" || return 1
  done
}

# 1. Servicios.
log "C1 UI adjuntos de tareas: inicio (log $LOG)"
if services_running; then
  log "Servicios: DB, Auth, PostgREST, Storage y Kong ya están arriba"
elif [[ "$start_services" == true ]]; then
  log "Servicios: stop del stack local (conserva volúmenes) y start sin $EXCLUDED_SERVICES"
  # Ambos comandos pueden imprimir llaves locales: su salida no va al log.
  if ! scripts/supabase_cli.sh stop >"$private_dir/stop.out" 2>&1; then
    redact <"$private_dir/stop.out" | tail -20 | tee -a "$LOG"
    die "supabase stop falló"
  fi
  if ! scripts/supabase_cli.sh start -x "$EXCLUDED_SERVICES" >"$private_dir/start.out" 2>&1; then
    redact <"$private_dir/start.out" | tail -30 | tee -a "$LOG"
    die "supabase start falló"
  fi
  services_running || die "Tras el arranque siguen faltando servicios"
  log "Servicios: arriba"
else
  die "Faltan Auth/PostgREST/Storage/Kong locales; correr con --start-services"
fi

bash scripts/db/ensure_local.sh >>"$LOG" 2>&1 || die "ensure_local.sh falló"

# Credenciales locales del stack, sin registrarlas.
scripts/supabase_cli.sh status -o env >"$private_dir/status.env" 2>/dev/null ||
  die "supabase status falló"
read_status() {
  sed -n "s/^$1=\"\{0,1\}\([^\"]*\)\"\{0,1\}\$/\1/p" "$private_dir/status.env" | head -1
}
API_URL="$(read_status API_URL)"
SERVICE_ROLE_KEY="$(read_status SERVICE_ROLE_KEY)"
[[ -n "$SERVICE_ROLE_KEY" ]] || SERVICE_ROLE_KEY="$(read_status SECRET_KEY)"
rm -f "$private_dir/status.env"
[[ "$API_URL" =~ ^http://(127\.0\.0\.1|localhost):[0-9]{2,5}$ ]] || {
  API_URL=""
  die "La API no es local"
}
[[ -n "$SERVICE_ROLE_KEY" ]] || die "No se leyó la llave local de administración"
printf 'apikey: %s\nAuthorization: Bearer %s\n' "$SERVICE_ROLE_KEY" "$SERVICE_ROLE_KEY" \
  >"$private_dir/admin.headers"
unset SERVICE_ROLE_KEY
log "API local: $API_URL (llave de administración leída, no registrada)"
ensure_storage_up || die "Storage local no responde"

# Inspección previa: qué previews hay antes de tocar el perfil local.
for port in 54330 54331 "${ERP_LOCAL_WEB_PORT:-54334}"; do
  holder="$(lsof -nP -t -iTCP:"$port" -sTCP:LISTEN 2>/dev/null | head -1 || true)"
  log "Preview :$port antes: ${holder:+pid $holder}${holder:-libre}"
done

# 2. Preparativos administrativos.
log "Preparación: restos de otra corrida"
retire_all || die "No se pudieron retirar restos de otra corrida"

needs_retire=true
PASSWORD="ui-$(openssl rand -hex 16)"
# Cuentas de personal ERP con nombre, como las deja una invitación: el
# directorio de asignación sólo lista `erp_staff`/`erp_owner`. La compañera
# nunca entra; su contraseña es otra y se descarta aquí.
create_account() {
  local email="$1" name="$2" password="$3" status
  E2E_EMAIL="$email" E2E_NAME="$name" E2E_PASSWORD="$password" python3 -c \
    'import json,os; print(json.dumps({"email": os.environ["E2E_EMAIL"], "password": os.environ["E2E_PASSWORD"], "email_confirm": True, "user_metadata": {"display_name": os.environ["E2E_NAME"]}, "app_metadata": {"account_type": "erp_staff"}}))' \
    >"$private_dir/user.json"
  status="$(curl -sS -o "$private_dir/user.out" -w '%{http_code}' -X POST \
    -H @"$private_dir/admin.headers" -H 'Content-Type: application/json' \
    --data @"$private_dir/user.json" "$API_URL/auth/v1/admin/users")"
  rm -f "$private_dir/user.json" "$private_dir/user.out"
  [[ "$status" == 200 || "$status" == 201 ]] || die "Auth no creó $email (HTTP $status)"
  log "Auth: cuenta sintética $email ($name) creada por la API de administración"
}
create_account "$EMAIL" "$EMPLOYEE_NAME" "$PASSWORD"
create_account "$COWORKER_EMAIL" "$COWORKER_NAME" "ui-$(openssl rand -hex 16)"

fixture setup >>"$LOG" 2>&1 || die "La fixture no preparó el taller"
log "Fixture: taller sintético y perfiles mechanic listos"

# 3. La app completa contra el stack local, por el dueño del preview.
if [[ "$reuse_bundle" == false ]]; then
  log "App: web_preview.sh build --local (lib/main.dart, defines privados)"
  scripts/dev/web_preview.sh build --local >"$private_dir/build.out" 2>&1 || {
    redact <"$private_dir/build.out" | tail -30 | tee -a "$LOG"
    die "La compilación local de la app falló"
  }
  redact <"$private_dir/build.out" | tail -3 | tee -a "$LOG"
fi
preview_started=true
scripts/dev/web_preview.sh start --local >"$private_dir/start-preview.out" 2>&1 || {
  redact <"$private_dir/start-preview.out" | tail -20 | tee -a "$LOG"
  die "El preview local no arrancó"
}
redact <"$private_dir/start-preview.out" | tail -3 | tee -a "$LOG"

# 4. Recorrido en Chrome, como el empleado. Sin llave de administración.
log "Recorrido: $SPEC (frames en $FRAMES)"
journey_status=0
env -u SERVICE_ROLE_KEY \
  TASK_FORM_E2E_ENABLED=1 \
  E2E_BASE_URL="$BASE_URL" \
  TASK_FORM_E2E_API_URL="$API_URL" \
  TASK_FORM_E2E_EMAIL="$EMAIL" \
  TASK_FORM_E2E_PASSWORD="$PASSWORD" \
  TASK_FORM_E2E_TASK_TITLE="$TASK_TITLE" \
  TASK_FORM_E2E_ASSIGNEE="$COWORKER_NAME" \
  TASK_FORM_E2E_STORAGE_CONTAINER="$STORAGE_CONTAINER" \
  TASK_FORM_E2E_FRAMES_DIR="$ROOT/$FRAMES" \
  npx playwright test "$SPEC" --reporter=line --output="$private_dir/playwright" \
  >"$private_dir/journey.out" 2>&1 || journey_status=$?
unset PASSWORD
redact <"$private_dir/journey.out" | grep -vE '^\s*$' | tail -60 | tee -a "$LOG"
ensure_storage_up || die "Storage no volvió después del recorrido"

# 5. Readback (sólo si el recorrido terminó) y retirada.
readback_status=0
if [[ "$journey_status" == 0 ]]; then
  fixture readback >"$private_dir/readback.out" 2>&1 || readback_status=$?
  tee -a "$LOG" <"$private_dir/readback.out"
fi
preview_started=false
scripts/dev/web_preview.sh stop --local >>"$LOG" 2>&1 || log "AVISO: el preview local no se detuvo limpio"
needs_retire=false
retire_all || die "La retirada final falló"

log "Frames: $(find "$FRAMES" -name '*.png' 2>/dev/null | wc -l | tr -d ' ') en $FRAMES"
[[ "$journey_status" == 0 ]] || die "El recorrido falló (playwright salió con $journey_status)"
[[ "$readback_status" == 0 ]] || die "El readback de la base no confirmó el recorrido"
log "C1 UI adjuntos: recorrido completo en la app y readback confirmado"
