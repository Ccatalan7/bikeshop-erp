-- A single, read-only PostgreSQL statement gives every subquery the same
-- MVCC snapshot. Run only through scripts/db/query.sh production --file.
-- This is a product-specification recovery bundle, not a full ERP dump.
-- Format 2 adds the component profile headers and their event history in the
-- same snapshot as the scoped facts they own. It requires the member-profile
-- framework to be published; before that the statement fails closed and the
-- earlier format 1 copies stay readable with the same tool.
with tenant as (
  select id, subdomain from public.tenants where subdomain = 'vinabike'
), products as (
  select p.id,p.tenant_id,p.name,p.sku,p.brand_id,p.brand,p.model,
    p.manufacturer,p.manufacturer_sku,p.barcode,p.gtin,p.category_id,
    p.category,p.category_name,p.description,p.specifications,p.tags,
    p.unit,p.weight,p.color,p.size,p.material,p.dimensions,
    p.product_type,p.is_service,p.is_active,p.is_set,p.set_type,
    p.parent_set_id,p.component_label,p.component_position,
    p.supplier_id,p.supplier_name,p.supplier_code,p.supplier_reference,
    p.image_url,p.image_urls,p.additional_images,
    p.created_at,p.updated_at,p.spec_revision,p.spec_reference_id,
    (to_jsonb(p)->>'spec_template_id')::uuid spec_template_id
  from public.products p join tenant t on t.id=p.tenant_id
), facts as (
  -- Every scope of the product: root observations (null scope) and the
  -- component observations owned by a profile (member:<profile id>).
  select f.* from public.spec_facts f join products p
    on p.id=f.subject_id and p.tenant_id=f.tenant_id
  where f.subject_type='product'
), member_profiles as (
  select m.* from public.product_spec_member_profiles m join products p
    on p.id=m.product_id and p.tenant_id=m.tenant_id
), member_events as (
  select e.* from public.product_spec_member_profile_events e
  join member_profiles m on m.id=e.profile_id and m.tenant_id=e.tenant_id
), definitions as (
  select d.* from public.spec_definitions d
  where d.tenant_id is null or d.tenant_id in (select id from tenant)
), definition_values as (
  select v.* from public.spec_definition_values v
  join definitions d on d.id=v.spec_definition_id
), templates as (
  select t.* from public.spec_templates t
  where t.tenant_id is null or t.tenant_id in (select id from tenant)
), fields as (
  select f.* from public.spec_template_fields f
  join templates t on t.id=f.template_id
), scope_tables as (
  select unnest(array['spec_definitions','spec_definition_values','spec_templates',
    'spec_template_fields','category_tech_mappings','spec_facts','spec_fact_values',
    'spec_fact_readings','product_spec_values','product_spec_references',
    'product_spec_save_receipts','product_set_components','products',
    'product_categories','product_spec_member_profiles',
    'product_spec_member_profile_events']) name
)
select jsonb_build_object(
  'format_version',2,'scope','vinabike_product_specs_pre_fill',
  'captured_at',clock_timestamp(),'transaction_snapshot',txid_current_snapshot()::text,
  'tenant',(select to_jsonb(t) from tenant t),
  'tables',jsonb_build_object(
    'products',(select coalesce(jsonb_agg(to_jsonb(p) order by p.id),'[]') from products p),
    'product_categories',(select coalesce(jsonb_agg(to_jsonb(c) order by c.id),'[]')
      from public.product_categories c join tenant t on t.id=c.tenant_id),
    'category_tech_mappings',(select coalesce(jsonb_agg(to_jsonb(m) order by m.id),'[]')
      from public.category_tech_mappings m join tenant t on t.id=m.tenant_id),
    'spec_definitions',(select coalesce(jsonb_agg(to_jsonb(d) order by d.id),'[]') from definitions d),
    'spec_definition_values',(select coalesce(jsonb_agg(to_jsonb(v) order by v.id),'[]') from definition_values v),
    'spec_templates',(select coalesce(jsonb_agg(to_jsonb(t) order by t.id),'[]') from templates t),
    'spec_template_fields',(select coalesce(jsonb_agg(to_jsonb(f) order by f.id),'[]') from fields f),
    'spec_facts',(select coalesce(jsonb_agg(to_jsonb(f) order by f.id),'[]') from facts f),
    'spec_fact_values',(select coalesce(jsonb_agg(to_jsonb(v) order by v.fact_id,v.position,v.value_id),'[]')
      from public.spec_fact_values v join facts f on f.id=v.fact_id),
    'spec_fact_readings',(select coalesce(jsonb_agg(to_jsonb(r) order by r.fact_id),'[]')
      from public.spec_fact_readings r join facts f on f.id=r.fact_id and f.tenant_id=r.tenant_id),
    'product_spec_values',(select coalesce(jsonb_agg(to_jsonb(v) order by v.id),'[]')
      from public.product_spec_values v join products p on p.id=v.product_id and p.tenant_id=v.tenant_id),
    'product_set_components',(select coalesce(jsonb_agg(to_jsonb(c) order by c.id),'[]')
      from public.product_set_components c join tenant t on t.id=c.tenant_id),
    'product_spec_references',(select coalesce(jsonb_agg(to_jsonb(r) order by r.id),'[]')
      from public.product_spec_references r),
    'product_spec_save_receipts',(select coalesce(jsonb_agg(to_jsonb(r) order by r.operation_key),'[]')
      from public.product_spec_save_receipts r join tenant t on t.id=r.tenant_id),
    -- Generated columns (scope, active_template_guard) travel with the row so
    -- the identity and archived state are verifiable without recomputing them.
    'product_spec_member_profiles',(select coalesce(jsonb_agg(to_jsonb(m) order by m.id),'[]')
      from member_profiles m),
    'product_spec_member_profile_events',(select coalesce(jsonb_agg(to_jsonb(e) order by e.occurred_at,e.id),'[]')
      from member_events e)
  ),
  'catalog',jsonb_build_object(
    'columns',(select jsonb_agg(to_jsonb(c) order by c.table_name,c.ordinal_position)
      from information_schema.columns c where c.table_schema='public'
      and c.table_name in (select name from scope_tables)),
    'constraints',(select jsonb_agg(jsonb_build_object('table',c.conrelid::regclass::text,
      'name',c.conname,'definition',pg_get_constraintdef(c.oid)) order by c.oid)
      from pg_constraint c where c.conrelid in
      (select ('public.'||name)::regclass from scope_tables)),
    'triggers',(select jsonb_agg(jsonb_build_object('table',t.tgrelid::regclass::text,
      'name',t.tgname,'definition',pg_get_triggerdef(t.oid),'enabled',t.tgenabled) order by t.oid)
      from pg_trigger t where not t.tgisinternal and t.tgrelid in
      (select ('public.'||name)::regclass from scope_tables)),
    'functions',(select jsonb_agg(jsonb_build_object('signature',p.oid::regprocedure::text,
      'definition',pg_get_functiondef(p.oid),'acl',p.proacl) order by p.oid)
      from pg_proc p where p.pronamespace='public'::regnamespace and p.prokind='f'
      and (p.proname like '%spec%' or p.proname in ('save_product_with_specs_v1',
        'save_product_set_aggregate','get_product_set_aggregate_v1'))),
    'policies',(select jsonb_agg(to_jsonb(p) order by p.tablename,p.policyname)
      from pg_policies p where p.schemaname='public' and p.tablename in (select name from scope_tables)),
    'indexes',(select jsonb_agg(to_jsonb(i) order by i.tablename,i.indexname)
      from pg_indexes i where i.schemaname='public' and i.tablename in (select name from scope_tables)),
    'grants',(select jsonb_agg(to_jsonb(g) order by g.table_name,g.grantee,g.privilege_type)
      from information_schema.role_table_grants g where g.table_schema='public'
      and g.table_name in (select name from scope_tables)),
    'migration_versions',(select jsonb_agg(version order by version)
      from supabase_migrations.schema_migrations)
  ),
  'operational_fingerprint',jsonb_build_object(
    'purpose','comparison_only_never_restore_commercial_or_stock_fields',
    'products', (select count(*) from products),
    'physical_products',(select count(*) from products where product_type is distinct from 'service'),
    'member_profiles',(select count(*) from member_profiles),
    'commercial_stock_md5',(select md5(string_agg(jsonb_build_array(p.id,p.price,p.cost,
      p.stock_quantity,p.inventory_qty,p.track_stock,p.tax_type,p.tax_rate)::text,'' order by p.id))
      from public.products p join tenant t on t.id=p.tenant_id)
  )
) as snapshot;
