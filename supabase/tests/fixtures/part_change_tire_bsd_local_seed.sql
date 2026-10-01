-- Local-only missing catalogue rows for the tire part change (C1/C4,
-- 2026-09-30). Not a production restore.
--
-- The local base is rebuilt from supabase/sql/core_schema.sql, whose global
-- `tire` template predates the tire publication
-- (20260916030000_tire_tube_successors.sql). That publication can never apply
-- here: it requires production's template ids (local `tire` was seeded with a
-- different uuid) and the validator it was reviewed against. Without
-- `bead_seat_diameter_mm` a tire has no BSD, so `product_bike_fact_spec_internal`
-- and the job form see nothing to check and the part-change guard is never
-- exercised with the real engine.
--
-- This seeds exactly production's definition row (same id, read on
-- 2026-09-30) and adds it as a field of the local global `tire` template with
-- production's field id and placement. The engine's own triggers validate the
-- insert. No products, prices, facts or tenant data are copied.
--
-- Apply after the spec engine replay (see
-- docs/development/product-specs-research-2026-09-05/local-engine-restore-2026-09-16.md):
--   scripts/db/query.sh local --write --file supabase/tests/fixtures/part_change_tire_bsd_local_seed.sql
\set ON_ERROR_STOP on
begin;

select 1 / (case when not exists (select 1 from vault.secrets) then 1 else 0 end)
  as solo_base_local;

insert into public.spec_definitions (
  id, tenant_id, key, label, description, data_type, unit, allowed_values,
  validation_rules, is_filterable, is_required_by_default,
  is_compatibility_relevant, is_customer_visible, is_mechanic_visible,
  group_name, sort_order
)
select 'ee4e8a1b-f363-5bff-a22a-4101533ab113', null, 'bead_seat_diameter_mm',
       'Aro (diámetro ISO)', null, 'number', 'mm', '[]'::jsonb,
       '{"integer": true, "positive": true}'::jsonb, true, false, false, true,
       true, null, 0
where not exists (select 1 from public.spec_definitions
                   where tenant_id is null and key = 'bead_seat_diameter_mm');

insert into public.spec_template_fields (
  id, tenant_id, template_id, spec_definition_id, is_required, section_key,
  sort_order, default_value_json, visibility_rules, helper_text, option_rules,
  constraint_rules
)
select '46d89f9f-f38c-5bf8-9c76-cc9ee3156c12', null, t.id,
       'ee4e8a1b-f363-5bff-a22a-4101533ab113', false, 'measurement', 10, null,
       '[]'::jsonb, null, '[]'::jsonb, '[]'::jsonb
  from public.spec_templates t
 where t.tenant_id is null and t.key = 'tire' and t.is_active
   and not exists (select 1 from public.spec_template_fields f
                    where f.template_id = t.id
                      and f.spec_definition_id = 'ee4e8a1b-f363-5bff-a22a-4101533ab113');

select 1 / (case when exists (
    select 1 from public.spec_template_fields f
      join public.spec_templates t on t.id = f.template_id
     where t.tenant_id is null and t.key = 'tire'
       and f.spec_definition_id = 'ee4e8a1b-f363-5bff-a22a-4101533ab113')
  then 1 else 0 end) as neumatico_con_bsd;

commit;
