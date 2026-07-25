#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
SUPABASE_CLI_WRAPPER="$ROOT/scripts/supabase_cli.sh"
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
CATEGORY_ID="f8f5bf86-0ec9-47e7-9c8c-d05a28ba36a4"
CAMPAIGN_KEY="camaras-2026-07"
BEFORE_MD5="40f5aa625389acf74860ada289c7f507"
AFTER_MD5="5cfd4bd7d19e918a28cba3bc5ffce06c"

BEFORE_JSON="$ROOT/scripts/website/campaigns/camaras_trail_editorial_2026_07.v2.json"
AFTER_JSON="$ROOT/scripts/website/campaigns/camaras_trail_editorial_2026_07.after.json"
ASSET="$ROOT/assets/images/campaigns/camaras-trail-editorial-2026-07.png"
ASSET_SHA256="7e11a126110a0655080e1e05aebbab05fa65d3f72a578d1ba40378a4ac89a337"
ASSET_MD5="23c779074232a3d17fee766bc143bb2a"
STORAGE_BUCKET="vinabike-assets"
STORAGE_OBJECT="website-images/camaras-trail-editorial-2026-07.png"
PUBLIC_URL="https://${EXPECTED_PROJECT_REF}.supabase.co/storage/v1/object/public/${STORAGE_BUCKET}/${STORAGE_OBJECT}"

MAXXIS_ASSET="$ROOT/assets/images/campaigns/products/maxxis-welter-weight-29-cutout.png"
MAXXIS_SHA256="f7669020d911761b53631eddf0a6101996575be89bc5752ada52afa2084021e0"
MAXXIS_MD5="48e3a42ffabe0bc3266dd140cc6a1acb"
MAXXIS_STORAGE_OBJECT="website-images/camaras-maxxis-welter-weight-29-cutout.png"
MAXXIS_PUBLIC_URL="https://${EXPECTED_PROJECT_REF}.supabase.co/storage/v1/object/public/${STORAGE_BUCKET}/${MAXXIS_STORAGE_OBJECT}"
MAXXIS_OPTIMIZED_ASSET="$ROOT/assets/images/campaigns/products/maxxis-welter-weight-29-cutout-optimized.webp"
MAXXIS_OPTIMIZED_SHA256="39a670ad8a6653bffd9e14812dd8353305355c75d2fc746bbbbb88f0ba127b77"
MAXXIS_OPTIMIZED_MD5="5ef3e83704a3ec4b7ed8e0548884276c"
MAXXIS_OPTIMIZED_STORAGE_OBJECT="website/media/camaras-maxxis-welter-weight-29-cutout-optimized.webp"
MAXXIS_OPTIMIZED_PUBLIC_URL="https://${EXPECTED_PROJECT_REF}.supabase.co/storage/v1/object/public/${STORAGE_BUCKET}/${MAXXIS_OPTIMIZED_STORAGE_OBJECT}"

RIDEXC_ASSET="$ROOT/assets/images/campaigns/products/ridexc-butyl-29-cutout.png"
RIDEXC_SHA256="bb62c42d58cdd02207050f17147fd9d783fb38d081c8eef3f65ad717e26ef245"
RIDEXC_MD5="b9dd4d60cdcbee5bc20fdd25f66a83f7"
RIDEXC_STORAGE_OBJECT="website-images/camaras-ridexc-butyl-29-cutout.png"
RIDEXC_PUBLIC_URL="https://${EXPECTED_PROJECT_REF}.supabase.co/storage/v1/object/public/${STORAGE_BUCKET}/${RIDEXC_STORAGE_OBJECT}"
RIDEXC_OPTIMIZED_ASSET="$ROOT/assets/images/campaigns/products/ridexc-butyl-29-cutout-optimized.webp"
RIDEXC_OPTIMIZED_SHA256="f2ac69e5bd638c06cf71739970edd8ef41f81a61992f4537ef286886dcfd10b2"
RIDEXC_OPTIMIZED_MD5="2bd6d67243256229aee1ef2d27dbde4f"
RIDEXC_OPTIMIZED_STORAGE_OBJECT="website/media/camaras-ridexc-butyl-29-cutout-optimized.webp"
RIDEXC_OPTIMIZED_PUBLIC_URL="https://${EXPECTED_PROJECT_REF}.supabase.co/storage/v1/object/public/${STORAGE_BUCKET}/${RIDEXC_OPTIMIZED_STORAGE_OBJECT}"

TENTEN_ASSET="$ROOT/assets/images/campaigns/products/10ten-butyl-26-cutout.png"
TENTEN_SHA256="7f9b251e255c96ab31b22c7b03078d9067d6ad41af5d8ea2fb2ced6bfd3b2693"
TENTEN_MD5="4dc6b05c160e6bb89b97c2d18bf57c16"
TENTEN_STORAGE_OBJECT="website-images/camaras-10ten-butyl-26-cutout.png"
TENTEN_PUBLIC_URL="https://${EXPECTED_PROJECT_REF}.supabase.co/storage/v1/object/public/${STORAGE_BUCKET}/${TENTEN_STORAGE_OBJECT}"
TENTEN_OPTIMIZED_ASSET="$ROOT/assets/images/campaigns/products/10ten-butyl-26-cutout-optimized.webp"
TENTEN_OPTIMIZED_SHA256="70fbb1030043a2d41a6a73bc0810f48aac1efebb1d477df45e024a7cffdf67e4"
TENTEN_OPTIMIZED_MD5="63f8e4a47f0451d23ca561726d6d9f1b"
TENTEN_OPTIMIZED_STORAGE_OBJECT="website/media/camaras-10ten-butyl-26-cutout-optimized.webp"
TENTEN_OPTIMIZED_PUBLIC_URL="https://${EXPECTED_PROJECT_REF}.supabase.co/storage/v1/object/public/${STORAGE_BUCKET}/${TENTEN_OPTIMIZED_STORAGE_OBJECT}"

for command in jq supabase shasum md5; do
  command -v "$command" >/dev/null 2>&1 || {
    printf 'Missing required command: %s\n' "$command" >&2
    exit 69
  }
done

[[ -f "$BEFORE_JSON" && -f "$AFTER_JSON" && -f "$ASSET" &&
   -f "$MAXXIS_ASSET" && -f "$RIDEXC_ASSET" && -f "$TENTEN_ASSET" &&
   -f "$MAXXIS_OPTIMIZED_ASSET" && -f "$RIDEXC_OPTIMIZED_ASSET" &&
   -f "$TENTEN_OPTIMIZED_ASSET" ]] || {
  printf 'Campaign fixture or media asset is missing.\n' >&2
  exit 66
}

[[ "$(jq -r '.imageUrl // empty' "$AFTER_JSON")" == "$PUBLIC_URL" ]] || {
  printf 'Refusing: reviewed slide background does not match the managed media object.\n' >&2
  exit 65
}

for expected_url in "$MAXXIS_OPTIMIZED_PUBLIC_URL" "$RIDEXC_OPTIMIZED_PUBLIC_URL" "$TENTEN_OPTIMIZED_PUBLIC_URL"; do
  [[ "$(jq --arg url "$expected_url" '[.elements[] | select(.type == "image" and .imageUrl == $url)] | length' "$AFTER_JSON")" == "2" ]] || {
    printf 'Refusing: each reviewed cutout must own one desktop and one mobile layer: %s\n' "$expected_url" >&2
    exit 65
  }
done

linked_ref="$(tr -d '[:space:]' < "$ROOT/supabase/.temp/project-ref")"
[[ "$linked_ref" == "$EXPECTED_PROJECT_REF" ]] || {
  printf 'Refusing: linked Supabase project is %s, expected %s.\n' \
    "$linked_ref" "$EXPECTED_PROJECT_REF" >&2
  exit 65
}

actual_sha256="$(shasum -a 256 "$ASSET" | awk '{print $1}')"
actual_md5="$(md5 -q "$ASSET")"
[[ "$actual_sha256" == "$ASSET_SHA256" && "$actual_md5" == "$ASSET_MD5" ]] || {
  printf 'Refusing: campaign asset checksum changed.\n' >&2
  exit 65
}

verify_asset_checksum() {
  local asset="$1"
  local expected_sha256="$2"
  local expected_md5="$3"
  [[ "$(shasum -a 256 "$asset" | awk '{print $1}')" == "$expected_sha256" &&
     "$(md5 -q "$asset")" == "$expected_md5" ]] || {
    printf 'Refusing: campaign cutout checksum changed: %s\n' "$asset" >&2
    exit 65
  }
}

verify_asset_checksum "$MAXXIS_ASSET" "$MAXXIS_SHA256" "$MAXXIS_MD5"
verify_asset_checksum "$RIDEXC_ASSET" "$RIDEXC_SHA256" "$RIDEXC_MD5"
verify_asset_checksum "$TENTEN_ASSET" "$TENTEN_SHA256" "$TENTEN_MD5"
verify_asset_checksum "$MAXXIS_OPTIMIZED_ASSET" "$MAXXIS_OPTIMIZED_SHA256" "$MAXXIS_OPTIMIZED_MD5"
verify_asset_checksum "$RIDEXC_OPTIMIZED_ASSET" "$RIDEXC_OPTIMIZED_SHA256" "$RIDEXC_OPTIMIZED_MD5"
verify_asset_checksum "$TENTEN_OPTIMIZED_ASSET" "$TENTEN_OPTIMIZED_SHA256" "$TENTEN_OPTIMIZED_MD5"

current_slide_md5() {
  "$ROOT/scripts/db/query.sh" production --format csv --sql \
    "select md5((block_data->'slides'->2)::text) as slide_md5
       from website_blocks
      where id = '${BLOCK_ID}'::uuid
        and tenant_id = '${TENANT_ID}'::uuid
        and page_id = '${PAGE_ID}'::uuid
        and block_type = 'carousel'" | tail -n 1 | tr -d '[:space:]'
}

storage_etag() {
  local storage_object="$1"
  "$ROOT/scripts/db/query.sh" production --format csv --sql \
    "select trim(both '\"' from metadata->>'eTag') as etag
       from storage.objects
      where bucket_id = '${STORAGE_BUCKET}'
        and name = '${storage_object}'" | tail -n 1 | tr -d '[:space:]'
}

ensure_storage_asset() {
  local asset="$1"
  local storage_object="$2"
  local expected_md5="$3"
  local content_type="${4:-image/png}"
  local existing_etag
  existing_etag="$(storage_etag "$storage_object")"
  if [[ -z "$existing_etag" || "$existing_etag" == "etag" ]]; then
    VINABIKE_SUPABASE_STORAGE_WRITE_CONFIRM="$EXPECTED_PROJECT_REF" \
      "$SUPABASE_CLI_WRAPPER" --experimental storage cp --linked \
      --content-type "$content_type" \
      --cache-control 'public,max-age=31536000,immutable' \
      "$asset" "ss:///${STORAGE_BUCKET}/${storage_object}"
    existing_etag="$(storage_etag "$storage_object")"
  fi
  [[ "$existing_etag" == "$expected_md5" ]] || {
    printf 'Refusing: storage object %s eTag %s does not match reviewed asset %s.\n' \
      "$storage_object" "$existing_etag" "$expected_md5" >&2
    exit 65
  }
}

validate() {
  "$ROOT/scripts/db/query.sh" production --format table --sql \
    "select
       b.id,
       p.slug as page_slug,
       b.is_visible,
       md5((b.block_data->'slides'->2)::text) as slide_md5,
       b.block_data->'slides'->2->>'campaignKey' as campaign_key,
       b.block_data->'slides'->2->>'title' as title,
       b.block_data->'slides'->2->>'imageUrl' as background_url,
       b.block_data->'slides'->2->'actions'->0->>'to' as destination,
       jsonb_array_length(b.block_data->'slides'->2->'elements') as element_count,
       (
         select count(*)
         from jsonb_array_elements(b.block_data->'slides'->2->'elements') e
         where nullif(e->>'productId', '') is not null
       ) as product_binding_count
     from website_blocks b
     join website_pages p on p.id = b.page_id
     where b.id = '${BLOCK_ID}'::uuid
       and b.tenant_id = '${TENANT_ID}'::uuid
       and b.page_id = '${PAGE_ID}'::uuid
       and b.block_type = 'carousel';

     select
       bucket_id,
       name,
       trim(both '\"' from metadata->>'eTag') as etag,
       metadata->>'size' as bytes,
       updated_at
     from storage.objects
     where bucket_id = '${STORAGE_BUCKET}'
       and name in (
         '${STORAGE_OBJECT}',
         '${MAXXIS_STORAGE_OBJECT}',
         '${RIDEXC_STORAGE_OBJECT}',
         '${TENTEN_STORAGE_OBJECT}',
         '${MAXXIS_OPTIMIZED_STORAGE_OBJECT}',
         '${RIDEXC_OPTIMIZED_STORAGE_OBJECT}',
         '${TENTEN_OPTIMIZED_STORAGE_OBJECT}'
       )
     order by name;

     select
       id,
       name,
       show_on_website,
       is_active,
       (
         select count(*)
         from products p
         where p.tenant_id = c.tenant_id
           and p.category_id = c.id
           and coalesce(p.is_active, true)
           and coalesce(p.is_published, false)
           and coalesce(p.show_on_website, false)
       ) as eligible_products
     from product_categories c
     where c.tenant_id = '${TENANT_ID}'::uuid
       and c.id = '${CATEGORY_ID}'::uuid"
}

if [[ "$MODE" == "validate" ]]; then
  validate
  exit 0
fi

current_md5="$(current_slide_md5)"

if [[ "$MODE" == "apply" ]]; then
  if [[ "$current_md5" == "$AFTER_MD5" ]]; then
    printf 'Campaign slide already matches the reviewed after state.\n'
    validate
    exit 0
  fi
  [[ "$current_md5" == "$BEFORE_MD5" ]] || {
    printf 'Refusing apply: live slide hash %s is neither reviewed before nor after state.\n' \
      "$current_md5" >&2
    exit 65
  }

  ensure_storage_asset "$ASSET" "$STORAGE_OBJECT" "$ASSET_MD5"
  ensure_storage_asset "$MAXXIS_ASSET" "$MAXXIS_STORAGE_OBJECT" "$MAXXIS_MD5"
  ensure_storage_asset "$RIDEXC_ASSET" "$RIDEXC_STORAGE_OBJECT" "$RIDEXC_MD5"
  ensure_storage_asset "$TENTEN_ASSET" "$TENTEN_STORAGE_OBJECT" "$TENTEN_MD5"
  ensure_storage_asset "$MAXXIS_OPTIMIZED_ASSET" "$MAXXIS_OPTIMIZED_STORAGE_OBJECT" "$MAXXIS_OPTIMIZED_MD5" image/webp
  ensure_storage_asset "$RIDEXC_OPTIMIZED_ASSET" "$RIDEXC_OPTIMIZED_STORAGE_OBJECT" "$RIDEXC_OPTIMIZED_MD5" image/webp
  ensure_storage_asset "$TENTEN_OPTIMIZED_ASSET" "$TENTEN_OPTIMIZED_STORAGE_OBJECT" "$TENTEN_OPTIMIZED_MD5" image/webp

  payload="$(jq -c . "$AFTER_JSON")"
  expected_from="$BEFORE_MD5"
  expected_to="$AFTER_MD5"
else
  if [[ "$current_md5" == "$BEFORE_MD5" ]]; then
    printf 'Campaign slide already matches the reviewed before state.\n'
    validate
    exit 0
  fi
  [[ "$current_md5" == "$AFTER_MD5" ]] || {
    printf 'Refusing rollback: live slide hash %s is neither reviewed after nor before state.\n' \
      "$current_md5" >&2
    exit 65
  }
  payload="$(jq -c . "$BEFORE_JSON")"
  expected_from="$AFTER_MD5"
  expected_to="$BEFORE_MD5"
fi

read -r -d '' sql <<SQL || true
begin;
set local lock_timeout = '3s';
set local statement_timeout = '30s';

do \$patch\$
declare
  v_current jsonb;
  v_next jsonb := \$slide\$${payload}\$slide\$::jsonb;
  v_rows integer;
  v_product_bindings integer;
begin
  select block_data->'slides'->2
    into strict v_current
    from website_blocks
   where id = '${BLOCK_ID}'::uuid
     and tenant_id = '${TENANT_ID}'::uuid
     and page_id = '${PAGE_ID}'::uuid
     and block_type = 'carousel'
   for update;

  if md5(v_current::text) <> '${expected_from}' then
    raise exception 'Campaign slide changed after preflight: expected %, found %',
      '${expected_from}', md5(v_current::text);
  end if;
  if v_next->>'campaignKey' <> '${CAMPAIGN_KEY}' then
    raise exception 'Unexpected campaign key: %', v_next->>'campaignKey';
  end if;
  if v_next->'actions'->0->>'to' <>
      '/productos?category=${CATEGORY_ID}' then
    raise exception 'Unexpected campaign destination: %',
      v_next->'actions'->0->>'to';
  end if;
  if v_next->>'useComposition' <> 'true'
      or jsonb_typeof(v_next->'elements') <> 'array' then
    raise exception 'Campaign must remain an editor-native layered composition';
  end if;

  select count(*) into v_product_bindings
    from jsonb_array_elements(v_next->'elements') e
   where e->>'productId' in (
     '967a79d7-0e08-4cec-b4f5-920510fc080e',
     'a1833eee-c61e-49bb-9b97-4439d2c6f0db',
     'fe2d8c63-da9c-4bf1-b65a-0d5125dbf5ea'
   );
  if v_product_bindings <> 6 then
    raise exception 'Expected six responsive product bindings, found %',
      v_product_bindings;
  end if;

  update website_blocks
     set block_data = jsonb_set(block_data, '{slides,2}', v_next, false),
         updated_at = clock_timestamp()
   where id = '${BLOCK_ID}'::uuid
     and tenant_id = '${TENANT_ID}'::uuid
     and page_id = '${PAGE_ID}'::uuid
     and block_type = 'carousel';

  get diagnostics v_rows = row_count;
  if v_rows <> 1 then
    raise exception 'Expected one campaign block update, wrote % rows', v_rows;
  end if;

  select block_data->'slides'->2
    into strict v_current
    from website_blocks
   where id = '${BLOCK_ID}'::uuid;
  if md5(v_current::text) <> '${expected_to}' then
    raise exception 'Post-write hash mismatch: expected %, found %',
      '${expected_to}', md5(v_current::text);
  end if;
end
\$patch\$;

commit;
SQL

VINABIKE_DB_WRITE_CONFIRM=production \
  "$ROOT/scripts/db/query.sh" production --write --sql "$sql"

validate
