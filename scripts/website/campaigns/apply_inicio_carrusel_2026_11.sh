#!/usr/bin/env bash
# The home carousel of November 2026: seven layered slides (Lo Vásquez, kids'
# bikes, workshop services, Maxxis, RockShox forks, the XS-1270 cassette,
# accessories) in place of the three it had. Editor-native data: every text,
# button, product photo and accent is a Canvas layer the inspector reopens.
# See inicio_carrusel_2026_11.md.
#
#   apply     replaces the block's data when production still holds the
#             reviewed «before» (or says it is already applied)
#   rollback  puts the «before» back when production still holds the «after»
#   validate  reads what production has

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
PAGE_ID="99b789da-9b2b-44f3-b8d5-5c7bbaf7d5c4"
BLOCK_ID="0d155450-981e-4afd-8c74-c5bff74837b8"
BEFORE_MD5="4f0dcb3963580f6b5d0ca03d7703273b"
AFTER_MD5="358fbc0f65f6311b46c89e091b443e31"
BEFORE_JSON="$ROOT/scripts/website/campaigns/inicio_carrusel_2026_11.before.json"
AFTER_JSON="$ROOT/scripts/website/campaigns/inicio_carrusel_2026_11.after.json"
ASSETS_DIR="$ROOT/assets/images/campaigns/inicio-2026-11"
STORAGE_BUCKET="vinabike-assets"
STORAGE_PREFIX="website-images/inicio-2026-11-"
PUBLIC_PREFIX="https://${EXPECTED_PROJECT_REF}.supabase.co/storage/v1/object/public/${STORAGE_BUCKET}/"

for command in jq md5; do
  command -v "$command" >/dev/null 2>&1 || {
    printf 'Missing required command: %s\n' "$command" >&2
    exit 69
  }
done
[[ -f "$BEFORE_JSON" && -f "$AFTER_JSON" && -d "$ASSETS_DIR" ]] || {
  printf 'The reviewed carousel or its images are missing.\n' >&2
  exit 66
}
linked_ref="$(tr -d '[:space:]' < "$ROOT/supabase/.temp/project-ref")"
[[ "$linked_ref" == "$EXPECTED_PROJECT_REF" ]] || {
  printf 'Refusing: linked Supabase project is %s, expected %s.\n' "$linked_ref" "$EXPECTED_PROJECT_REF" >&2
  exit 65
}

scalar() {
  "$ROOT/scripts/db/query.sh" production --format csv --sql "$1" | tail -n 1 | tr -d '[:space:]"'
}

current_md5() {
  scalar "select md5(block_data::text) from website_blocks
           where id = '${BLOCK_ID}'::uuid and tenant_id = '${TENANT_ID}'::uuid
             and page_id = '${PAGE_ID}'::uuid and block_type = 'carousel'"
}

validate() {
  "$ROOT/scripts/db/query.sh" production --format table --sql \
    "select md5(b.block_data::text) as block_md5,
            jsonb_array_length(b.block_data->'slides') as slides,
            b.block_data->>'indicatorStyle' as indicators,
            b.block_data->>'accessibleTitle' as page_title,
            (select string_agg(s->>'title', ' · ' order by n)
               from jsonb_array_elements(b.block_data->'slides') with ordinality as t(s, n)) as titles,
            (select count(*) from jsonb_array_elements(b.block_data->'slides') s,
                    jsonb_array_elements(coalesce(s->'elements', '[]'::jsonb)) e) as layers,
            (select count(*) from storage.objects o
              where o.bucket_id = '${STORAGE_BUCKET}' and o.name like '${STORAGE_PREFIX}%') as stored_images
       from website_blocks b
      where b.id = '${BLOCK_ID}'::uuid and b.tenant_id = '${TENANT_ID}'::uuid
        and b.page_id = '${PAGE_ID}'::uuid and b.block_type = 'carousel'"
}

if [[ "$MODE" == "validate" ]]; then
  validate
  exit 0
fi

live="$(current_md5)"
if [[ "$MODE" == "apply" ]]; then
  from="$BEFORE_MD5"; to="$AFTER_MD5"; payload_file="$AFTER_JSON"
else
  from="$AFTER_MD5"; to="$BEFORE_MD5"; payload_file="$BEFORE_JSON"
fi
if [[ "$live" == "$to" ]]; then
  printf 'The carousel already holds the reviewed state for «%s».\n' "$MODE"
  validate
  exit 0
fi
[[ "$live" == "$from" ]] || {
  printf 'Refusing %s: the live block is %s, neither the reviewed before nor after.\n' "$MODE" "$live" >&2
  exit 65
}

if [[ "$MODE" == "apply" ]]; then
  # Every image a slide names is one of the reviewed files, and each of those
  # is in the media picker's bucket with the same bytes.
  while IFS= read -r url; do
    file="${url#"${PUBLIC_PREFIX}${STORAGE_PREFIX}"}"
    [[ "$file" != "$url" && -f "$ASSETS_DIR/$file" ]] || {
      printf 'Refusing apply: a slide names an image outside the reviewed set: %s\n' "$url" >&2
      exit 65
    }
  done < <(jq -r --arg p "$PUBLIC_PREFIX" '.. | strings | select(startswith($p))' "$AFTER_JSON" | sort -u)

  values=""
  for asset in "$ASSETS_DIR"/*.webp; do
    name="$(basename "$asset")"
    [[ "$name" =~ ^[a-z0-9.-]+$ ]] || { printf 'Unexpected image name: %s\n' "$name" >&2; exit 65; }
    values+="('${STORAGE_PREFIX}${name}','$(md5 -q "$asset")'),"
  done
  different="$(scalar "with reviewed(name, md5) as (values ${values%,})
                       select count(*) from reviewed r
                         left join storage.objects o
                           on o.bucket_id = '${STORAGE_BUCKET}' and o.name = r.name
                        where o.id is null
                           or trim(both '\"' from o.metadata->>'eTag') <> r.md5")"
  [[ "$different" == "0" ]] || {
    printf 'Refusing apply: %s reviewed images are missing from storage or differ.\n' "$different" >&2
    exit 65
  }
fi

payload="$(jq -c . "$payload_file")"
[[ "$payload" != *'$carousel$'* ]] || { printf 'Payload collides with the quoting tag.\n' >&2; exit 65; }
mkdir -p "$ROOT/.tmp"
sql_file="$(mktemp "$ROOT/.tmp/inicio-carrusel.XXXXXX")"
trap 'rm -f "$sql_file"' EXIT
cat > "$sql_file" <<SQL
begin;
set local lock_timeout = '3s';
set local statement_timeout = '30s';

do \$patch\$
declare
  v_current jsonb;
  v_next jsonb := \$carousel\$${payload}\$carousel\$::jsonb;
  v_rows integer;
begin
  select block_data into strict v_current
    from website_blocks
   where id = '${BLOCK_ID}'::uuid and tenant_id = '${TENANT_ID}'::uuid
     and page_id = '${PAGE_ID}'::uuid and block_type = 'carousel'
     for update;
  if md5(v_current::text) <> '${from}' then
    raise exception 'The carousel changed after the preflight: expected %, found %',
      '${from}', md5(v_current::text);
  end if;
  if md5(v_next::text) <> '${to}' then
    raise exception 'The payload is not the reviewed one: %', md5(v_next::text);
  end if;
  if jsonb_typeof(v_next->'slides') <> 'array' or jsonb_array_length(v_next->'slides') = 0 then
    raise exception 'A carousel needs its slides';
  end if;
  update website_blocks
     set block_data = v_next, updated_at = clock_timestamp()
   where id = '${BLOCK_ID}'::uuid and tenant_id = '${TENANT_ID}'::uuid
     and page_id = '${PAGE_ID}'::uuid and block_type = 'carousel';
  get diagnostics v_rows = row_count;
  if v_rows <> 1 then
    raise exception 'Expected one block, updated %', v_rows;
  end if;
end
\$patch\$;

select 1 / case when (select md5(block_data::text) from website_blocks
   where id = '${BLOCK_ID}'::uuid and tenant_id = '${TENANT_ID}'::uuid) = '${to}' then 1 else 0 end as read_back_ok;
commit;
SQL

VINABIKE_DB_WRITE_CONFIRM=production \
  "$ROOT/scripts/db/query.sh" production --file "$sql_file" --write --format table
validate
