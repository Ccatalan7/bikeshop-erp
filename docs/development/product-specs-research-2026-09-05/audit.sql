-- Read-only evidence. Run only through scripts/db/query.sh production --file.
-- Template metadata is global; category coverage below is scoped to vinabike.
select t.key, t.technical_family, t.is_active,
       count(f.id) as fields,
       count(f.id) filter (where f.visibility_rules <> '[]'::jsonb) as visibility_rules,
       count(f.id) filter (where f.option_rules <> '[]'::jsonb) as option_rules
from public.spec_templates t
left join public.spec_template_fields f on f.template_id = t.id
group by t.id, t.key, t.technical_family, t.is_active
order by t.technical_family, t.key;

select count(*) as active_categories,
       count(*) filter (where not exists (
         select 1 from public.product_categories ch
         where ch.parent_id = c.id and ch.is_active
       )) as active_leaves,
       count(*) filter (where not exists (
         select 1 from public.product_categories ch
         where ch.parent_id = c.id and ch.is_active
       ) and not exists (
         select 1 from public.category_tech_mappings m
         join public.spec_templates t on t.id = m.template_id and t.is_active
         where m.category_id = c.id and m.status = 'active'
       )) as leaves_without_active_template
from public.product_categories c
join public.tenants tn on tn.id = c.tenant_id
where tn.subdomain = 'vinabike' and c.is_active;

with recursive tree as (
  select c.id, c.name, c.parent_id, c.tenant_id, c.name::text as path
  from public.product_categories c
  join public.tenants tn on tn.id = c.tenant_id
  where tn.subdomain = 'vinabike' and c.is_active and c.parent_id is null
  union all
  select c.id, c.name, c.parent_id, c.tenant_id, tree.path || ' / ' || c.name
  from public.product_categories c join tree on c.parent_id = tree.id
  where c.is_active
)
select tree.path,
       (select string_agg(distinct t.key, ', ' order by t.key)
        from public.category_tech_mappings m
        join public.spec_templates t on t.id = m.template_id and t.is_active
        where m.category_id = tree.id and m.status = 'active') as templates,
       (select count(*) from public.products p
        where p.category_id = tree.id and p.tenant_id = tree.tenant_id
          and p.is_active and p.product_type <> 'service') as active_product_rows
from tree
where not exists (
  select 1 from public.product_categories ch
  where ch.parent_id = tree.id and ch.is_active
)
order by tree.path;

select c.relname, t.tgname, p.proname
from pg_trigger t
join pg_class c on c.oid = t.tgrelid
join pg_proc p on p.oid = t.tgfoid
where c.relnamespace = 'public'::regnamespace
  and c.relname in ('spec_facts','spec_fact_values','product_spec_values')
  and not t.tgisinternal
order by c.relname, t.tgname;

select p.proname, pg_get_functiondef(p.oid) as definition
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and p.proname in (
  'save_product_spec_facts_v1',
  'validate_product_spec_value_exact_drivetrain_fields',
  'spec_fact_value_shape_internal_v1',
  'mirror_facts_into_product_specs_internal_v1'
)
order by p.proname;
