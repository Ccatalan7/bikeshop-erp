#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "$ROOT"

MODE="${1:-}"
case "$MODE" in
  apply|rollback|validate) ;;
  *)
    printf 'Usage: %s <apply|rollback|validate>\n' "$0" >&2
    exit 64
    ;;
esac

EXPECTED_PROJECT_REF="xzdvtzdqjeyqxnkqprtf"
TENANT_ID="5443b130-cc28-45af-a420-cd500b288890"
SETTING_KEY="header_color_mode"
BEFORE_VALUE="light"
AFTER_VALUE="auto"

linked_ref="$(tr -d '[:space:]' < "$ROOT/supabase/.temp/project-ref")"
[[ "$linked_ref" == "$EXPECTED_PROJECT_REF" ]] || {
  printf 'Refusing: linked Supabase project is %s, expected %s.\n' \
    "$linked_ref" "$EXPECTED_PROJECT_REF" >&2
  exit 65
}

validate() {
  "$ROOT/scripts/db/query.sh" production --format table --sql \
    "select tenant_id, key, value, updated_at
       from website_settings
      where tenant_id = '${TENANT_ID}'::uuid
        and key = '${SETTING_KEY}';"
}

if [[ "$MODE" == "validate" ]]; then
  validate
  exit 0
fi

if [[ "$MODE" == "apply" ]]; then
  expected_from="$BEFORE_VALUE"
  expected_to="$AFTER_VALUE"
else
  expected_from="$AFTER_VALUE"
  expected_to="$BEFORE_VALUE"
fi

current_value="$(
  "$ROOT/scripts/db/query.sh" production --format csv --sql \
    "select value
       from website_settings
      where tenant_id = '${TENANT_ID}'::uuid
        and key = '${SETTING_KEY}'" |
    tail -n 1 | tr -d '[:space:]'
)"

if [[ "$current_value" == "$expected_to" ]]; then
  printf 'Header contrast already matches %s.\n' "$expected_to"
  validate
  exit 0
fi

[[ "$current_value" == "$expected_from" ]] || {
  printf 'Refusing %s: expected %s, found %s.\n' \
    "$MODE" "$expected_from" "$current_value" >&2
  exit 65
}

read -r -d '' sql <<SQL || true
begin;
set local lock_timeout = '3s';
set local statement_timeout = '30s';

update website_settings
   set value = '${expected_to}',
       updated_at = clock_timestamp()
 where tenant_id = '${TENANT_ID}'::uuid
   and key = '${SETTING_KEY}'
   and value = '${expected_from}';

do \$verify\$
declare
  v_value text;
begin
  select value into strict v_value
    from website_settings
   where tenant_id = '${TENANT_ID}'::uuid
     and key = '${SETTING_KEY}';
  if v_value <> '${expected_to}' then
    raise exception 'Header contrast update failed: expected %, found %',
      '${expected_to}', v_value;
  end if;
end
\$verify\$;

commit;
SQL

VINABIKE_DB_WRITE_CONFIRM=production \
  "$ROOT/scripts/db/query.sh" production --write --sql "$sql"

validate
