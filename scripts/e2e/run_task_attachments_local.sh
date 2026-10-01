#!/usr/bin/env bash
# C1 (PLANS.md, 2026-09-30): subir, abrir y retirar un adjunto privado de
# tarea con Auth, PostgREST y Storage locales reales y el TaskService de la app.
#
#   scripts/e2e/run_task_attachments_local.sh [--start-services]
#
# 1. Servicios: DB, Auth, PostgREST, Storage y Kong del stack local. Con
#    --start-services, si faltan, se detiene el stack (los volúmenes quedan, y
#    con ellos la DB preparada) y se arranca sin los servicios que este
#    recorrido no usa. Ese arranque baja las imágenes que falten.
# 2. Preparativos administrativos (llave de servicio, nunca en el recorrido):
#    retira restos de otra corrida, crea los dos empleados por la API de Auth
#    y aplica la fixture (talleres A/B y perfiles mechanic).
# 3. Recorrido autenticado: test/integration/task_attachments_local_test.dart
#    con la llave anónima y la contraseña de cada empleado.
# 4. Readback y retirada: la fixture comprueba lo que quedó; los bytes que
#    sobren se retiran por la API de Storage y el resto por la fixture. La
#    retirada también corre si algo falla después de crear los empleados.
#
# El log en .tmp/e2e/ guarda sólo pasos y evidencia: ni llaves ni contraseñas.
# No sustituye el recorrido en la app ni en el teléfono.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

FIXTURE="scripts/e2e/task_attachments_local_fixture.sql"
TEST_FILE="test/integration/task_attachments_local_test.dart"
TENANT_A="e2898000-0000-4000-8000-000000000001"
EMAIL_A="task-e2e-a@vinabike.invalid"
EMAIL_B="task-e2e-b@vinabike.invalid"
PROJECT="bikeshop-erp"
REQUIRED_CONTAINERS=(supabase_db supabase_auth supabase_rest supabase_storage supabase_kong)
EXCLUDED_SERVICES="realtime,imgproxy,mailpit,postgres-meta,studio,edge-runtime,logflare,vector,supavisor"

start_services=false
case "${1:-}" in
  --start-services) start_services=true ;;
  "") ;;
  *)
    echo "Uso: $0 [--start-services]" >&2
    exit 64
    ;;
esac

mkdir -p .tmp/e2e
LOG=".tmp/e2e/task-attachments-$(date +%Y%m%d-%H%M%S).log"
log() { printf '%s %s\n' "$(date -u +%H:%M:%SZ)" "$*" | tee -a "$LOG"; }

# Llaves locales, contraseña y cuerpos HTTP: sólo aquí, 0700, y fuera al salir.
private_dir="$(mktemp -d "${TMPDIR:-/tmp}/task-e2e.XXXXXX")"
chmod 700 "$private_dir"
needs_retire=false

fixture() {
  TASK_E2E_FIXTURE_MODE="$1" bash scripts/db/query.sh local --format "${2:-table}" --file "$FIXTURE"
}

# Bytes de los talleres sintéticos que queden: por la API de Storage, como admin.
retire_objects() {
  local listing names status
  # Formato tabla: el modo CSV del wrapper no admite los comandos de psql de
  # la fixture (\set, \getenv) y fallaba en silencio.
  if ! listing="$(fixture objects 2>&1)"; then
    log "ERROR: la fixture no listó los bytes sintéticos"
    return 1
  fi
  names="$(sed -n 's/^ *\(e2898000-0000-4000-8000-00000000000[12]\/[^ ]*\) *$/\1/p' <<<"$listing")"
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
  log "Retirada: talleres, vínculos y usuarios sintéticos fuera"
}

on_exit() {
  local status=$?
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
log "C1 adjuntos privados de tareas: inicio (log $LOG)"
if services_running; then
  log "Servicios: DB, Auth, PostgREST, Storage y Kong ya están arriba"
elif [[ "$start_services" == true ]]; then
  log "Servicios: stop del stack local (conserva volúmenes) y start sin $EXCLUDED_SERVICES"
  # Ambos comandos pueden imprimir llaves locales: su salida no va al log.
  if ! scripts/supabase_cli.sh stop >"$private_dir/stop.out" 2>&1; then
    grep -viE 'key|secret|jwt|password|token' "$private_dir/stop.out" | tail -20 | tee -a "$LOG" || true
    die "supabase stop falló"
  fi
  if ! scripts/supabase_cli.sh start -x "$EXCLUDED_SERVICES" >"$private_dir/start.out" 2>&1; then
    grep -viE 'key|secret|jwt|password|token' "$private_dir/start.out" | tail -30 | tee -a "$LOG" || true
    die "supabase start falló"
  fi
  services_running || die "Tras el arranque siguen faltando servicios"
  log "Servicios: arriba"
else
  die "Faltan Auth/PostgREST/Storage/Kong locales; correr con --start-services"
fi

# La DB preparada debe seguir igual (misma fixture histórica).
bash scripts/db/ensure_local.sh >>"$LOG" 2>&1 || die "ensure_local.sh falló"

# Credenciales locales del stack, sin registrarlas.
scripts/supabase_cli.sh status -o env >"$private_dir/status.env" 2>/dev/null ||
  die "supabase status falló"
read_status() {
  sed -n "s/^$1=\"\{0,1\}\([^\"]*\)\"\{0,1\}\$/\1/p" "$private_dir/status.env" | head -1
}
API_URL="$(read_status API_URL)"
ANON_KEY="$(read_status ANON_KEY)"
[[ -n "$ANON_KEY" ]] || ANON_KEY="$(read_status PUBLISHABLE_KEY)"
SERVICE_ROLE_KEY="$(read_status SERVICE_ROLE_KEY)"
[[ -n "$SERVICE_ROLE_KEY" ]] || SERVICE_ROLE_KEY="$(read_status SECRET_KEY)"
case "$API_URL" in
  http://127.0.0.1:* | http://localhost:*) ;;
  *) die "La API no es local" ;;
esac
[[ -n "$ANON_KEY" && -n "$SERVICE_ROLE_KEY" ]] || die "No se leyeron las llaves locales"
printf 'apikey: %s\nAuthorization: Bearer %s\n' "$SERVICE_ROLE_KEY" "$SERVICE_ROLE_KEY" \
  >"$private_dir/admin.headers"
rm -f "$private_dir/status.env"
log "API local: $API_URL (llaves leídas, no registradas)"

# 2. Preparativos administrativos.
log "Preparación: restos de otra corrida"
retire_all || die "No se pudieron retirar restos de otra corrida"

needs_retire=true
PASSWORD="e2e-$(openssl rand -hex 16)"
for email in "$EMAIL_A" "$EMAIL_B"; do
  E2E_EMAIL="$email" E2E_PASSWORD="$PASSWORD" python3 -c \
    'import json,os; print(json.dumps({"email": os.environ["E2E_EMAIL"], "password": os.environ["E2E_PASSWORD"], "email_confirm": True}))' \
    >"$private_dir/user.json"
  status="$(curl -sS -o "$private_dir/user.out" -w '%{http_code}' -X POST \
    -H @"$private_dir/admin.headers" -H 'Content-Type: application/json' \
    --data @"$private_dir/user.json" "$API_URL/auth/v1/admin/users")"
  rm -f "$private_dir/user.json"
  [[ "$status" == 200 || "$status" == 201 ]] || die "Auth no creó $email (HTTP $status)"
  log "Auth: empleado sintético $email creado por la API de administración"
done

fixture setup >>"$LOG" 2>&1 || die "La fixture no preparó los talleres"
log "Fixture: talleres A/B y perfiles mechanic listos"

# 3. Recorrido autenticado: sin llave de servicio en su entorno.
RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)-$$"
log "Recorrido: $TEST_FILE"
journey_status=0
env -u SERVICE_ROLE_KEY \
  TASK_E2E_ENABLED=1 \
  TASK_E2E_API_URL="$API_URL" \
  TASK_E2E_ANON_KEY="$ANON_KEY" \
  TASK_E2E_EMAIL_A="$EMAIL_A" \
  TASK_E2E_EMAIL_B="$EMAIL_B" \
  TASK_E2E_PASSWORD="$PASSWORD" \
  TASK_E2E_TENANT_A="$TENANT_A" \
  TASK_E2E_RUN_ID="$RUN_ID" \
  .fvm/flutter_sdk/bin/flutter test "$TEST_FILE" --reporter expanded \
  >"$private_dir/journey.out" 2>&1 || journey_status=$?
grep -viE 'key|secret|jwt|password|token' "$private_dir/journey.out" |
  grep -E 'C1 evidencia|[0-9]{2}:[0-9]{2} \+[0-9]+|Expected|Actual|Exception|Error|All tests passed|Some tests failed' |
  tail -40 | tee -a "$LOG" || true

# 4. Readback (sólo si el recorrido terminó) y retirada.
readback_status=0
if [[ "$journey_status" == 0 ]]; then
  fixture readback >"$private_dir/readback.out" 2>&1 || readback_status=$?
  tee -a "$LOG" <"$private_dir/readback.out"
fi
needs_retire=false
retire_all || die "La retirada final falló"

[[ "$journey_status" == 0 ]] || die "El recorrido falló (flutter test salió con $journey_status)"
[[ "$readback_status" == 0 ]] || die "El readback de la base no confirmó el recorrido"
log "C1 adjuntos privados: recorrido completo y readback confirmado"
