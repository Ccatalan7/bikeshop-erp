#!/usr/bin/env bash
# Recorridos con sesión contra el stack local (PLANS.md, 2026-09-30):
# lib/main.dart real contra Auth, PostgREST y Storage locales, en el AVD
# Android arm64 Medium_Phone_API_36.1 (por defecto; un driver de
# adb/uiautomator los recorre por identidad semántica) o, con --surface web, en
# Chrome de escritorio a 1440 px (la app de `web_preview.sh --local` y una
# prueba de Playwright). Cuentas, fixture, readback y retirada son los mismos.
#
#   scripts/e2e/run_android_local_journey.sh --journey task-form|workshop|backup|c3-photo [--build-only]
#                                            [--surface android|web]
#                                            [--reuse-apk] [--start-services]
#                                            [--hold | --release]
#
#   --surface  android (por defecto) o web; web tiene los recorridos
#              workshop (e2e/workshop_local.spec.ts) y backup
#              (e2e/backup_local.spec.ts). El escritorio nativo de macOS no se
#              usa: su sesión debug es del dueño y no se duplica.
#   --reuse-apk  reusa el APK sellado (android) o el bundle local (web).
#   --hold     si el driver falla, deja la app con su sesión y el taller
#              sintético tal como quedaron, para explorar desde donde se
#              detuvo: en Android con android_ui.py; en web la página queda
#              abierta y lee órdenes de .tmp/e2e/web-<recorrido>-<fecha>-hold/
#              (cmd.js → out.txt; `exit` la cierra).
#   --release  retira lo que dejó un --hold: app, archivos, reverse, preview
#              y fixture.
#
#   task-form  C1: el TaskFormDialog adjunta, abre y retira archivos (aceptado
#              el 2026-09-30; run_task_form_android_local.sh es su atajo).
#   workshop   C1/C4: el recorrido completo del taller, con los siete criterios
#              del Master y los dos defectos corregidos del C1 nativo
#              (workshop_journey_local_fixture.sql, android_workshop_journey.py).
#   backup     C2: recuperar desde Configuración → Respaldos un trabajo perdido
#              con su bici y su tarea (backup_journey_local_fixture.sql; sólo
#              --surface web: el diálogo es el mismo widget en el teléfono y su
#              ancho de 390 px se captura en el mismo recorrido).
#   c3-photo   C3: la foto heredada de un trabajo se ve en el teléfono desde su
#              copia privada (android_c3_private_photo_journey.py). Usa la
#              fixture C3 ya preparada y retenida por su dueño, que se nombra
#              con C3_FIXTURE_JSON (archivo privado 0600): no crea cuentas, no
#              prepara ni retira nada de la base; su readback sólo lee que la
#              fixture siga igual.
#
# 1. APK: `flutter build apk --debug --target-platform android-arm64` de
#    lib/main.dart con los defines públicos del stack local en un JSON privado
#    (0600, fuera del log y de argv, borrado al compilar). Queda sellado con la
#    URL local y la huella de la llave; nunca se instala un APK sin ese sello.
#    La app usa http://127.0.0.1:54321 igual que en el Mac: `adb reverse` lleva
#    ese puerto del emulador al del Mac, sin cambiar el bootstrap a 10.0.2.2.
# 2. Preparativos administrativos (llave de servicio, nunca en la app): dos
#    cuentas sintéticas por la API de Auth y la fixture del recorrido.
# 3. Emulador: se arranca sin ventana si no hay uno; se instala el APK tras
#    desinstalar la app (datos limpios del emulador de pruebas, no de un
#    teléfono del dueño) y se copian a Download las fotos del recorrido.
# 4. Recorrido: el driver entra por el login y deja frames claro/oscuro y el
#    árbol semántico de cada estado en .tmp/e2e/android-<recorrido>-<fecha>/.
# 5. Readback de la fixture, retirada, y el emulador como estaba: app
#    desinstalada, archivos y reverse fuera, apagado si lo arrancó este script.
#
# El log guarda pasos y evidencia; ni llaves ni contraseñas.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

SDK="${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}"
ADB="$SDK/platform-tools/adb"
EMULATOR="$SDK/emulator/emulator"
AVD="${ANDROID_E2E_AVD:-${TASK_FORM_ANDROID_AVD:-Medium_Phone_API_36.1}}"
PACKAGE="com.vinabike.erp"
FLUTTER="$ROOT/.fvm/flutter_sdk/bin/flutter"
APK_DIR="$ROOT/build/android_local_e2e"
APK="$APK_DIR/app-local-debug.apk"
STAMP="$APK_DIR/.vinabike-local-profile"
EMPLOYEE_NAME="Tomás Rivas"
COWORKER_NAME="Javiera Soto"
PROJECT="bikeshop-erp"
REQUIRED_CONTAINERS=(supabase_db supabase_auth supabase_rest supabase_storage supabase_kong)
EXCLUDED_SERVICES="realtime,imgproxy,mailpit,postgres-meta,studio,edge-runtime,logflare,vector,supavisor"

usage() {
  echo "Uso: $0 --journey task-form|workshop|backup|c3-photo [--surface android|web] [--build-only] [--reuse-apk] [--start-services] [--hold|--release]" >&2
  exit 64
}
journey=""
build_only=false
reuse_apk=false
start_services=false
hold=false
release=false
surface=android
while [[ $# -gt 0 ]]; do
  case "$1" in
    --journey) journey="${2:-}"; shift ;;
    --surface) surface="${2:-}"; shift ;;
    --build-only) build_only=true ;;
    --reuse-apk) reuse_apk=true ;;
    --start-services) start_services=true ;;
    --hold) hold=true ;;
    --release) release=true ;;
    *) usage ;;
  esac
  shift
done

# Lo que cambia de un recorrido a otro. El resto del lanzador es común.
case "$journey" in
  task-form)
    TITLE="C1 nativo Android"
    RUN_NAME="android-task-form"
    FIXTURE="scripts/e2e/task_form_local_fixture.sql"
    FIXTURE_MODE_VAR="TASK_FORM_E2E_FIXTURE_MODE"
    TENANT="e2898000-0000-4000-8000-000000000021"
    EMAIL="task-ui-e2e@vinabike.invalid"
    COWORKER_EMAIL="task-ui-e2e-otra@vinabike.invalid"
    DRIVER="scripts/e2e/android_task_form_journey.py"
    DEVICE_FILES=(pastilla-trasera.png rotor-delantero.png)
    PREFLIGHT=false
    ;;
  workshop)
    TITLE="C1/C4 nativo Android"
    RUN_NAME="android-workshop"
    FIXTURE="scripts/e2e/workshop_journey_local_fixture.sql"
    FIXTURE_MODE_VAR="WORKSHOP_E2E_FIXTURE_MODE"
    TENANT="e2898000-0000-4000-8000-000000000031"
    EMAIL="taller-ui-e2e@vinabike.invalid"
    COWORKER_EMAIL="taller-ui-e2e-otra@vinabike.invalid"
    DRIVER="scripts/e2e/android_workshop_journey.py"
    DEVICE_FILES=(rueda-trasera.png)
    PREFLIGHT=true
    ;;
  backup)
    TITLE="C2 escritorio (Chrome)"
    RUN_NAME="web-backup"
    FIXTURE="scripts/e2e/backup_journey_local_fixture.sql"
    FIXTURE_MODE_VAR="BACKUP_E2E_FIXTURE_MODE"
    TENANT="e2898000-0000-4000-8000-000000000041"
    EMAIL="respaldo-ui-e2e@vinabike.invalid"
    COWORKER_EMAIL="respaldo-ui-e2e-otra@vinabike.invalid"
    DRIVER=""
    DEVICE_FILES=(none)
    PREFLIGHT=false
    ;;
  c3-photo)
    TITLE="C3 nativo Android"
    RUN_NAME="android-c3-photo"
    # La fixture es de su dueño y queda como está: sin fixture propia.
    FIXTURE=""
    FIXTURE_MODE_VAR=""
    TENANT=""
    EMAIL=""
    COWORKER_EMAIL=""
    DRIVER="scripts/e2e/android_c3_private_photo_journey.py"
    DEVICE_FILES=(none)
    PREFLIGHT=false
    C3_FIXTURE_JSON="${C3_FIXTURE_JSON:-}"
    [[ -f "$C3_FIXTURE_JSON" ]] || { echo "Falta C3_FIXTURE_JSON: la fixture C3 retenida" >&2; exit 64; }
    ;;
  *) usage ;;
esac
case "$surface" in
  android) [[ "$journey" != backup ]] || usage ;;
  web)
    [[ "$journey" != c3-photo ]] || usage
    case "$journey" in
      workshop)
        TITLE="C1/C4 escritorio (Chrome)"
        RUN_NAME="web-workshop"
        SPEC="e2e/workshop_local.spec.ts"
        ;;
      backup) SPEC="e2e/backup_local.spec.ts" ;;
      *) usage ;;
    esac
    BASE_URL="http://localhost:${ERP_LOCAL_WEB_PORT:-54334}"
    ;;
  *) usage ;;
esac

# El entorno propio de cada driver: nombres y datos, nunca llaves.
driver_env() {
  case "$journey" in
    task-form)
      printf '%s\n' \
        "TASK_FORM_E2E_EMAIL=$EMAIL" \
        "TASK_FORM_E2E_PASSWORD=$PASSWORD" \
        "TASK_FORM_E2E_TASK_TITLE=Cambiar pastillas traseras (Trek Marlin 7)" \
        "TASK_FORM_E2E_ASSIGNEE=$COWORKER_NAME"
      ;;
    workshop)
      printf '%s\n' \
        "WORKSHOP_E2E_EMAIL=$EMAIL" \
        "WORKSHOP_E2E_PASSWORD=$PASSWORD" \
        "WORKSHOP_E2E_CUSTOMER=Camila Rojas" \
        "WORKSHOP_E2E_BRAND=Trek" \
        "WORKSHOP_E2E_MODEL=Marlin 7 Gen 3" \
        "WORKSHOP_E2E_COWORKER=$COWORKER_NAME"
      ;;
    backup)
      printf '%s\n' \
        "BACKUP_E2E_EMAIL=$EMAIL" \
        "BACKUP_E2E_PASSWORD=$PASSWORD" \
        "BACKUP_E2E_NAME=Antes de perder el trabajo" \
        "BACKUP_E2E_JOB_ID=e2898000-0000-4000-8000-000000000450"
      ;;
    c3-photo)
      # La cuenta del taller de la fixture C3 y su contraseña de un uso, del
      # archivo privado: van al entorno del driver, nunca al log ni a argv.
      python3 - "$C3_FIXTURE_JSON" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
staff = [a for a in data["accounts"] if a["email"].startswith("c3-staff-")]
if len(staff) != 1 or not data.get("password") or not data.get("ids", {}).get("job"):
    sys.exit("la fixture C3 no trae una cuenta del taller, su contraseña y el trabajo")
print(f"C3_E2E_EMAIL={staff[0]['email']}")
print(f"C3_E2E_PASSWORD={data['password']}")
print(f"C3_E2E_JOB_ID={data['ids']['job']}")
PY
      ;;
  esac
}

# C3: la fixture de su dueño sigue igual (sólo lectura): el recibo de copia,
# la copia privada con su tamaño y el vínculo del trabajo; el original público
# se informa (su 404 es de la fixture, no de este recorrido). 1/0 al final.
c3_readback() {
  local job private_path source_path
  job="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["ids"]["job"])' "$C3_FIXTURE_JSON")"
  private_path="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["private_path"])' "$C3_FIXTURE_JSON")"
  source_path="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["source_path"])' "$C3_FIXTURE_JSON")"
  [[ "$job" =~ ^[0-9a-f-]{36}$ && "$private_path" =~ ^[0-9a-zA-Z/._-]+$ && "$source_path" =~ ^[0-9a-zA-Z/._-]+$ ]] ||
    { log "ERROR: la fixture C3 trae identidades inesperadas"; return 1; }
  bash scripts/db/query.sh local --format table --sql "
    with copy as (
      select * from public.workshop_legacy_asset_copies
       where job_id = '$job' and storage_path = '$private_path'
    ), facts as (
      select (select count(*) from copy) as recibo,
        (select count(*) from storage.objects o join copy on o.name = copy.storage_path
          where o.bucket_id = 'workshop-legacy-private'
            and (o.metadata->>'size')::bigint = copy.private_size_bytes) as copia_privada,
        (select count(*) from public.mechanic_jobs j join copy on j.id = copy.job_id
          where copy.source_reference = any(coalesce(j.image_urls, '{}'::text[]))) as vinculo_del_trabajo,
        (select count(*) from storage.objects o
          where o.bucket_id = 'vinabike-assets' and o.name = '$source_path') as original_publico
    )
    select facts.*,
      1 / (case when recibo = 1 and copia_privada = 1 and vinculo_del_trabajo = 1
                then 1 else 0 end) as c3_fixture_intacta
    from facts"
}

mkdir -p .tmp/e2e
RUN_STAMP="$(date +%Y%m%d-%H%M%S)"
LOG=".tmp/e2e/$RUN_NAME-$RUN_STAMP.log"
FRAMES=".tmp/e2e/$RUN_NAME-$RUN_STAMP"
log() { printf '%s %s\n' "$(date -u +%H:%M:%SZ)" "$*" | tee -a "$LOG"; }
redact() { grep -viE 'key|secret|jwt|password|contraseña|token|bearer' || true; }

private_dir="$(mktemp -d "${TMPDIR:-/tmp}/$RUN_NAME.XXXXXX")"
chmod 700 "$private_dir"
needs_retire=false
serial=""
started_emulator=false
device_prepared=false
preview_started=false

die() {
  log "ERROR: $*"
  exit 1
}

# ── Defines públicos del stack local, en privado ────────────────────────────
# `status -o env` también trae la llave de servicio y la clave de la base: sólo
# se escribe en el directorio 0700 y se borra al leerla.
read_local_stack() {
  scripts/supabase_cli.sh status -o env >"$private_dir/status.env" 2>/dev/null ||
    die "El stack local no responde (supabase status)"
  if ! LOCAL_STACK="$(python3 - "$private_dir" <<'PY'
import base64, hashlib, json, os, re, sys

directory = sys.argv[1]
status_path = os.path.join(directory, 'status.env')
values = {}
try:
    with open(status_path) as status:
        for line in status:
            match = re.match(r'^([A-Z_]+)="?([^"\n]*)"?\s*$', line)
            if match:
                values[match.group(1)] = match.group(2)
finally:
    os.remove(status_path)

def fail(message):
    print('local stack: ' + message, file=sys.stderr)
    sys.exit(1)

def is_public(key):
    if not key or re.search(r'[\s"\\]', key):
        return False
    if key.startswith('sb_publishable_'):
        return True
    if key.startswith('sb_'):
        return False
    parts = key.split('.')
    if len(parts) != 3:
        return False
    try:
        claims = json.loads(base64.urlsafe_b64decode(parts[1] + '=' * (-len(parts[1]) % 4)))
    except Exception:
        return False
    return isinstance(claims, dict) and claims.get('role') == 'anon'

url = values.get('API_URL', '').rstrip('/')
if not re.fullmatch(r'http://(127\.0\.0\.1|localhost):[0-9]{2,5}', url):
    fail('refusing a missing or non-local API URL')
anon = values.get('ANON_KEY') or values.get('PUBLISHABLE_KEY', '')
publishable = values.get('PUBLISHABLE_KEY', '')
service = values.get('SERVICE_ROLE_KEY') or values.get('SECRET_KEY', '')
if not is_public(anon) or (publishable and not is_public(publishable)):
    fail('refusing a missing or non-public anon key')
if not service:
    fail('missing the local administration key')
defines = {'SUPABASE_URL': url, 'SUPABASE_ANON_KEY': anon}
if publishable:
    defines['SUPABASE_PUBLISHABLE_KEY'] = publishable
for name, content in (('defines.json', json.dumps(defines)),
                      ('admin.headers', f'apikey: {service}\nAuthorization: Bearer {service}\n')):
    descriptor = os.open(os.path.join(directory, name), os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(descriptor, 'w') as handle:
        handle.write(content)
fingerprint = hashlib.sha256('\n'.join([url, anon, publishable]).encode()).hexdigest()[:16]
print(f'api_url={url}')
print(f'keys_sha256_16={fingerprint}')
PY
)"; then
    die "La configuración local no es válida"
  fi
  API_URL="$(sed -n 's/^api_url=//p' <<<"$LOCAL_STACK")"
}

build_apk() {
  log "APK: flutter build apk --debug --target-platform android-arm64 (lib/main.dart, defines privados)"
  if ! "$FLUTTER" build apk --debug --target-platform android-arm64 -t lib/main.dart \
      "--dart-define-from-file=$private_dir/defines.json" >"$private_dir/build.out" 2>&1; then
    rm -f "$private_dir/defines.json"
    redact <"$private_dir/build.out" | tail -40 | tee -a "$LOG"
    die "La compilación Android falló"
  fi
  rm -f "$private_dir/defines.json"
  redact <"$private_dir/build.out" | grep -E "Built|Running Gradle" | tail -3 | tee -a "$LOG"
  local built="$ROOT/build/app/outputs/flutter-apk/app-debug.apk"
  [[ -f "$built" ]] || die "La compilación no dejó el APK"
  # El APK es un zip: la URL local tiene que estar compilada en libapp.so o en
  # el kernel del debug; si no, la app hablaría con producción.
  python3 - "$built" "$API_URL" <<'PY' || die "El APK no lleva la URL local; se descarta"
import sys, zipfile
apk, url = sys.argv[1], sys.argv[2].encode()
with zipfile.ZipFile(apk) as archive:
    for name in archive.namelist():
        if name.endswith(('kernel_blob.bin', 'libapp.so')) and url in archive.read(name):
            sys.exit(0)
sys.exit(1)
PY
  mkdir -p "$APK_DIR"
  cp "$built" "$APK.next"
  printf '%s\n' "$LOCAL_STACK" >"$STAMP.next"
  mv -f "$APK.next" "$APK"
  mv -f "$STAMP.next" "$STAMP"
  log "APK: sellado para $API_URL en ${APK#"$ROOT"/}"
}

# ── Retirada ────────────────────────────────────────────────────────────────
fixture() {
  env "$FIXTURE_MODE_VAR=$1" bash scripts/db/query.sh local --format table --file "$FIXTURE"
}

retire_objects() {
  local listing names status
  listing="$(fixture objects 2>&1)" || { log "ERROR: la fixture no listó los bytes"; return 1; }
  names="$(sed -n "s/^ *\\($TENANT\\/[^ ]*\\) *\$/\\1/p" <<<"$listing")"
  [[ -n "$names" ]] || { log "Storage: sin bytes sintéticos que retirar"; return 0; }
  python3 -c 'import json,sys; print(json.dumps({"prefixes": sys.stdin.read().split()}))' \
    <<<"$names" >"$private_dir/delete.json"
  status="$(curl -sS -o "$private_dir/delete.out" -w '%{http_code}' -X DELETE \
    -H @"$private_dir/admin.headers" -H 'Content-Type: application/json' \
    --data @"$private_dir/delete.json" "$API_URL/storage/v1/object/task-attachments")"
  [[ "$status" == 200 ]] || { log "ERROR: Storage no retiró los bytes (HTTP $status)"; return 1; }
  log "Storage: retirados $(wc -l <<<"$names" | tr -d ' ') objeto(s) sintético(s) por la API"
}

retire_all() {
  if [[ -z "$FIXTURE" ]]; then
    log "Fixture: la de C3 es de su dueño; no se prepara ni se retira aquí"
    return 0
  fi
  retire_objects || return 1
  fixture teardown >>"$LOG" 2>&1 || { log "ERROR: la retirada de la fixture falló"; return 1; }
  log "Retirada: taller, vínculos y cuentas sintéticas fuera"
}

restore_device() {
  [[ -n "$serial" ]] || return 0
  if [[ "$device_prepared" == true ]]; then
    "$ADB" -s "$serial" shell cmd uimode night no >/dev/null 2>&1 || true
    "$ADB" -s "$serial" uninstall "$PACKAGE" >/dev/null 2>&1 || true
    for file in "${DEVICE_FILES[@]}"; do
      "$ADB" -s "$serial" shell rm -f "/sdcard/Download/$file" >/dev/null 2>&1 || true
    done
    "$ADB" -s "$serial" reverse --remove tcp:54321 >/dev/null 2>&1 || true
    log "Emulador: app, archivos y reverse retirados"
  fi
  if [[ "$started_emulator" == true ]]; then
    "$ADB" -s "$serial" emu kill >/dev/null 2>&1 || true
    log "Emulador: apagado (lo arrancó este recorrido)"
  fi
}

stop_preview() {
  [[ "$preview_started" == true ]] || return 0
  preview_started=false
  scripts/dev/web_preview.sh stop --local >>"$LOG" 2>&1 ||
    { log "AVISO: el preview local no se detuvo limpio"; return 1; }
  log "App: preview local detenido"
}

# Lo que dejó una página retenida: órdenes, respuestas y la marca de lista.
clear_hold_dirs() {
  local dir
  for dir in .tmp/e2e/"$RUN_NAME"-*-hold; do
    [[ -d "$dir" ]] || continue
    find "$dir" -type f -exec rm -f {} + 2>/dev/null || true
    rmdir "$dir" 2>/dev/null || true
  done
}

on_exit() {
  local status=$?
  restore_device || status=1
  stop_preview || status=1
  if [[ "$needs_retire" == true ]]; then
    needs_retire=false
    retire_all || status=1
  fi
  find "$private_dir" -type f -exec rm -f {} + 2>/dev/null || true
  rmdir "$private_dir" 2>/dev/null || true
  exit "$status"
}
trap on_exit EXIT

# 0. Herramientas.
log "$TITLE: inicio (log $LOG)"
if [[ "$surface" == android ]]; then
  [[ -x "$ADB" && -x "$EMULATOR" ]] || die "Falta adb o el emulador en $SDK"
  "$EMULATOR" -list-avds | grep -qx "$AVD" || die "No existe el AVD $AVD"
fi

# 1. APK sellado para el stack local.
read_local_stack
log "API local: $API_URL (llaves leídas, no registradas)"
if [[ "$release" == true ]]; then
  if [[ "$surface" == web ]]; then
    preview_started=true
    stop_preview
    clear_hold_dirs
  else
    serial="$("$ADB" devices | awk '/^emulator-[0-9]+\tdevice$/ {print $1; exit}')"
    device_prepared=true
    restore_device
    serial=""
  fi
  retire_all || die "La retirada del recorrido retenido falló"
  log "$TITLE: liberado lo retenido (app, archivos, reverse y fixture)"
  exit 0
fi
if [[ "$surface" == web ]]; then
  # El bundle lo compila y sella su dueño (web_preview.sh), con sus defines.
  rm -f "$private_dir/defines.json"
  if [[ "$reuse_apk" == true ]]; then
    log "App: bundle local reutilizado (web_preview.sh sólo sirve uno de este stack)"
  else
    log "App: web_preview.sh build --local (lib/main.dart, defines privados)"
    scripts/dev/web_preview.sh build --local >"$private_dir/build.out" 2>&1 || {
      redact <"$private_dir/build.out" | tail -30 | tee -a "$LOG"
      die "La compilación local de la app falló"
    }
    redact <"$private_dir/build.out" | tail -3 | tee -a "$LOG"
  fi
elif [[ "$reuse_apk" == true && -f "$APK" && "$(cat "$STAMP" 2>/dev/null)" == "$LOCAL_STACK" ]]; then
  log "APK: reutilizado; su sello es de este stack"
  rm -f "$private_dir/defines.json"
else
  build_apk
fi
[[ "$surface" == web || "$(cat "$STAMP" 2>/dev/null)" == "$LOCAL_STACK" ]] ||
  die "El APK no está sellado para este stack"
if [[ "$build_only" == true ]]; then
  log "$TITLE: APK listo (--build-only); no se tocó la base ni el emulador"
  exit 0
fi

# 2. Servicios y preparativos administrativos.
services_running() {
  local running name
  running="$(docker ps --format '{{.Names}}')"
  for name in "${REQUIRED_CONTAINERS[@]}"; do
    grep -qx "${name}_${PROJECT}" <<<"$running" || return 1
  done
}
if ! services_running; then
  [[ "$start_services" == true ]] || die "Faltan servicios locales; correr con --start-services"
  scripts/supabase_cli.sh stop >"$private_dir/stop.out" 2>&1 || die "supabase stop falló"
  scripts/supabase_cli.sh start -x "$EXCLUDED_SERVICES" >"$private_dir/start.out" 2>&1 ||
    die "supabase start falló"
  services_running || die "Tras el arranque siguen faltando servicios"
fi
bash scripts/db/ensure_local.sh >>"$LOG" 2>&1 || die "ensure_local.sh falló"
if [[ "$PREFLIGHT" == true ]]; then
  # Sólo lectura: lo que el recorrido necesita existe en esta base.
  fixture preflight >"$private_dir/preflight.out" 2>&1 ||
    { tee -a "$LOG" <"$private_dir/preflight.out"; die "Falta algo del recorrido en la base local"; }
  tee -a "$LOG" <"$private_dir/preflight.out" >/dev/null
  log "Preflight: la base local tiene lo que el recorrido usa"
fi

log "Preparación: restos de otra corrida"
retire_all || die "No se pudieron retirar restos de otra corrida"
needs_retire=true
PASSWORD="ui-$(openssl rand -hex 16)"
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
if [[ -n "$FIXTURE" ]]; then
  create_account "$EMAIL" "$EMPLOYEE_NAME" "$PASSWORD"
  create_account "$COWORKER_EMAIL" "$COWORKER_NAME" "ui-$(openssl rand -hex 16)"
  fixture setup >>"$LOG" 2>&1 || die "La fixture no preparó el taller"
  log "Fixture: taller sintético y sus datos listos"
else
  c3_readback >"$private_dir/c3-before.out" 2>&1 ||
    { tee -a "$LOG" <"$private_dir/c3-before.out"; die "La fixture C3 no está como la dejó su dueño"; }
  log "Fixture: la C3 de su dueño está intacta antes del recorrido"
fi

if [[ "$surface" == web ]]; then
  # 3-4 (web). La app servida por su dueño y el recorrido en Chrome.
  preview_started=true
  scripts/dev/web_preview.sh start --local >"$private_dir/start-preview.out" 2>&1 || {
    redact <"$private_dir/start-preview.out" | tail -20 | tee -a "$LOG"
    die "El preview local no arrancó"
  }
  redact <"$private_dir/start-preview.out" | tail -3 | tee -a "$LOG"
  hold_dir=""
  if [[ "$hold" == true ]]; then
    clear_hold_dirs
    hold_dir=".tmp/e2e/$RUN_NAME-$RUN_STAMP-hold"
    mkdir -m 700 "$hold_dir"
  fi
  log "Recorrido: $SPEC (frames en $FRAMES)"
  journey_status=0
  journey_env=()
  while IFS= read -r line; do journey_env+=("$line"); done < <(driver_env)
  env -u SERVICE_ROLE_KEY \
    WORKSHOP_E2E_ENABLED=1 \
    E2E_BASE_URL="$BASE_URL" \
    WORKSHOP_E2E_FRAMES_DIR="$ROOT/$FRAMES" \
    WORKSHOP_E2E_HOLD_DIR="${hold_dir:+$ROOT/$hold_dir}" \
    "${journey_env[@]}" \
    npx playwright test "$SPEC" --reporter=line --output="$private_dir/playwright" \
    >"$private_dir/journey.out" 2>&1 || journey_status=$?
  journey_env=()
  unset PASSWORD
  redact <"$private_dir/journey.out" | grep -vE '^\s*$' | tail -60 | tee -a "$LOG"
  if [[ "$journey_status" != 0 && "$hold" == true ]]; then
    needs_retire=false
    preview_started=false
    log "Retenido (--hold): el taller sintético y el preview local quedan arriba;"
    log "  retirar con: $0 --journey $journey --surface web --release"
    exit 1
  fi
  clear_hold_dirs
  readback_status=0
  if [[ "$journey_status" == 0 ]]; then
    fixture readback >"$private_dir/readback.out" 2>&1 || readback_status=$?
    tee -a "$LOG" <"$private_dir/readback.out"
  fi
  stop_preview || true
  needs_retire=false
  retire_all || die "La retirada final falló"
  log "Frames: $(find "$FRAMES" -name '*.png' 2>/dev/null | wc -l | tr -d ' ') en $FRAMES"
  [[ "$journey_status" == 0 ]] || die "El recorrido falló (playwright salió con $journey_status)"
  [[ "$readback_status" == 0 ]] || die "El readback de la base no confirmó el recorrido"
  log "$TITLE: recorrido completo y readback confirmado"
  exit 0
fi

# 3. Emulador.
serial="$("$ADB" devices | awk '/^emulator-[0-9]+\tdevice$/ {print $1; exit}')"
if [[ -z "$serial" ]]; then
  log "Emulador: arrancando $AVD sin ventana"
  nohup "$EMULATOR" -avd "$AVD" -no-window -no-audio -no-boot-anim -no-snapshot-save \
    >"$private_dir/emulator.out" 2>&1 &
  started_emulator=true
  for _ in $(seq 1 90); do
    serial="$("$ADB" devices | awk '/^emulator-[0-9]+\tdevice$/ {print $1; exit}')"
    [[ -n "$serial" ]] && break
    sleep 2
  done
  [[ -n "$serial" ]] || die "El emulador no apareció en adb"
fi
for _ in $(seq 1 120); do
  [[ "$("$ADB" -s "$serial" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" == 1 ]] && break
  sleep 2
done
[[ "$("$ADB" -s "$serial" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" == 1 ]] ||
  die "El emulador no terminó de arrancar"
# Sin pantalla encendida y desbloqueada, uiautomator devuelve «null root node».
"$ADB" -s "$serial" shell input keyevent 224 >/dev/null 2>&1 || true
"$ADB" -s "$serial" shell wm dismiss-keyguard >/dev/null 2>&1 || true
log "Emulador: $serial listo ($("$ADB" -s "$serial" shell getprop ro.build.version.release | tr -d '\r'), $("$ADB" -s "$serial" shell getprop ro.product.cpu.abi | tr -d '\r'))"

device_prepared=true
"$ADB" -s "$serial" reverse tcp:54321 tcp:54321 >/dev/null
"$ADB" -s "$serial" uninstall "$PACKAGE" >/dev/null 2>&1 || true
"$ADB" -s "$serial" shell pm trim-caches 2G >/dev/null 2>&1 || true
"$ADB" -s "$serial" install -r "$APK" >"$private_dir/install.out" 2>&1 ||
  { tail -5 "$private_dir/install.out" | tee -a "$LOG"; die "No se instaló el APK"; }
log "Emulador: APK local instalado; 127.0.0.1:54321 del emulador lleva al Mac (adb reverse)"

# 4. Recorrido por identidad semántica.
log "Recorrido: $DRIVER (frames en $FRAMES)"
journey_status=0
journey_env=()
while IFS= read -r line; do journey_env+=("$line"); done < <(driver_env)
env -u SERVICE_ROLE_KEY \
  ANDROID_E2E_SERIAL="$serial" \
  ANDROID_E2E_ADB="$ADB" \
  ANDROID_E2E_PACKAGE="$PACKAGE" \
  ANDROID_E2E_FRAMES_DIR="$ROOT/$FRAMES" \
  "${journey_env[@]}" \
  python3 -B "$DRIVER" >"$private_dir/journey.out" 2>&1 || journey_status=$?
journey_env=()
unset PASSWORD
redact <"$private_dir/journey.out" | tail -60 | tee -a "$LOG"

if [[ "$journey_status" != 0 && "$hold" == true ]]; then
  needs_retire=false
  device_prepared=false
  started_emulator=false
  log "Retenido (--hold): la app, su sesión y el taller sintético quedan en $serial;"
  log "  retirar con: $0 --journey $journey --release"
  exit 1
fi

# 5. Readback y retirada.
readback_status=0
if [[ "$journey_status" == 0 ]]; then
  if [[ -n "$FIXTURE" ]]; then
    fixture readback >"$private_dir/readback.out" 2>&1 || readback_status=$?
  else
    c3_readback >"$private_dir/readback.out" 2>&1 || readback_status=$?
  fi
  tee -a "$LOG" <"$private_dir/readback.out"
fi
restore_device
serial=""
needs_retire=false
retire_all || die "La retirada final falló"
log "Frames: $(find "$FRAMES" -name '*.png' 2>/dev/null | wc -l | tr -d ' ') en $FRAMES"
[[ "$journey_status" == 0 ]] || die "El recorrido falló (driver salió con $journey_status)"
[[ "$readback_status" == 0 ]] || die "El readback de la base no confirmó el recorrido"
log "$TITLE: recorrido completo y readback confirmado"
