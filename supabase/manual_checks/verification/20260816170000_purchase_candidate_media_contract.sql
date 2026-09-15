-- Read-only executable verification for
-- 20260816170000_purchase_candidate_media_contract.sql.
-- Every assertion deliberately raises division_by_zero when the installed
-- production definition, ACL or additive view shape differs. It is consumed by
-- scripts/db/deploy_migration.sh before that version can be stamped APPLIED.

select 1 / ((
  (
    select jsonb_agg(
      jsonb_build_array(column_name, ordinal_position, udt_name)
      order by ordinal_position
    )
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'purchase_candidate_metrics_v1'
      and column_name in ('image_url_optimized', 'image_url', 'image_urls')
  ) = jsonb_build_array(
    jsonb_build_array('image_url_optimized', 38, 'text'),
    jsonb_build_array('image_url', 39, 'text'),
    jsonb_build_array('image_urls', 40, '_text')
  )
)::integer) as additive_media_columns_verified;

select 1 / ((exists (
  select 1
  from pg_class relation
  join pg_namespace namespace on namespace.oid = relation.relnamespace
  where namespace.nspname = 'public'
    and relation.relname = 'purchase_candidate_metrics_v1'
    and relation.relkind = 'v'
    and 'security_invoker=true' = any(coalesce(relation.reloptions, array[]::text[]))
))::integer) as security_invoker_verified;

select 1 / ((
  has_table_privilege(
    'authenticated', 'public.purchase_candidate_metrics_v1', 'SELECT'
  )
  and not has_table_privilege(
    'anon', 'public.purchase_candidate_metrics_v1', 'SELECT'
  )
  and not has_table_privilege(
    'service_role', 'public.purchase_candidate_metrics_v1', 'SELECT'
  )
)::integer) as candidate_view_acl_verified;

with installed as (
  select pg_get_functiondef(
    'public.rank_purchase_candidates_v1(text,uuid,uuid,text,integer)'::regprocedure
  ) as definition
)
select 1 / ((
  position('''imageUrlOptimized''' in definition) > 0
  and position('''imageUrl''' in definition) > 0
  and position('''imageUrls''' in definition) > 0
  and position('image_url_optimized' in definition) > 0
  and position('to_jsonb(image_urls)' in definition) > 0
)::integer) as ranking_media_payload_verified
from installed;

select 1 / ((
  has_function_privilege(
    'authenticated',
    'public.rank_purchase_candidates_v1(text,uuid,uuid,text,integer)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'anon',
    'public.rank_purchase_candidates_v1(text,uuid,uuid,text,integer)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'service_role',
    'public.rank_purchase_candidates_v1(text,uuid,uuid,text,integer)',
    'EXECUTE'
  )
)::integer) as ranking_acl_verified;

with installed as (
  select pg_get_functiondef(
    'public.get_supply_need_inventory_snapshot_v1(uuid)'::regprocedure
  ) as definition
)
select 1 / ((
  position('''image_url_optimized''' in definition) > 0
  and position('''image_url''' in definition) > 0
  and position('''image_urls''' in definition) > 0
  and position('component.image_url_optimized' in definition) > 0
  and position('to_jsonb(coalesce(component.image_urls' in definition) > 0
)::integer) as inventory_snapshot_media_payload_verified
from installed;

select 1 / ((
  has_function_privilege(
    'authenticated',
    'public.get_supply_need_inventory_snapshot_v1(uuid)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'anon',
    'public.get_supply_need_inventory_snapshot_v1(uuid)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'service_role',
    'public.get_supply_need_inventory_snapshot_v1(uuid)',
    'EXECUTE'
  )
)::integer) as inventory_snapshot_acl_verified;
