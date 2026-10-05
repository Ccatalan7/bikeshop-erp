-- The public technical sheet in one pass: 265 ms → ~25 ms per product.
--
-- `get_public_product_technical_specs` reads a product's values and validates
-- them once, then shows every field that passes. Postgres inlined the two CTEs
-- that hold those results into the per-field join, so it recomputed the
-- values and the whole validation for each field: for H911 (25 fields, 11
-- shown) the validation ran 11 times, 13 ms each, and the read took ~265 ms
-- (measured 2026-10-05 with EXPLAIN ANALYZE). `materialized` makes Postgres
-- compute each of them once per product. Nothing else changes: same body,
-- same rules, same grants; the output was compared row by row against the
-- previous definition for all 1,600 published products with a template
-- before this was written, with no difference.
--
-- Every public product page pays this read: the Flutter store's sheet, the
-- HTML storefront's single page read (`get_public_product_page_v1`) and the
-- SEO generator, once per product. Phase 0 of the HTML storefront measured it
-- as the whole of the page's first byte
-- (docs/architecture/storefront-html-migration-plan.md).

CREATE OR REPLACE FUNCTION public.get_public_product_technical_specs(p_tenant_id uuid, p_product_id uuid)
 RETURNS TABLE(section_key text, section_sort_order integer, field_sort_order integer, spec_key text, spec_label text, display_value text, unit text, data_type text, spec_hint text, highlight_rank integer)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
AS $$
  with visible as (
    select p.id,p.brand,p.model,p.manufacturer_sku,p.spec_reference_id,t.id template_id,t.form_contract
    from public.products p
    join public.product_spec_bindings_internal_v1 b on b.product_id=p.id
    join public.spec_templates t on t.id=b.template_id and t.is_active and (t.tenant_id is null or t.tenant_id=p.tenant_id)
    where p.id=p_product_id and p.tenant_id=p_tenant_id and coalesce(p.is_active,true)
      and coalesce(p.is_published,false) and coalesce(p.show_on_website,false)
  ), facts as materialized (
    select p.*,public.spec_active_product_values_internal_v1(p.id,p.template_id) vals from visible p
  ), assessed as materialized (select p.*,public.spec_validate_draft_internal_v1(p.template_id,p.vals,p.spec_reference_id,p.brand,p.model,p.manufacturer_sku) issues from facts p
  ), fields as (
    select f.section_key,f.sort_order,d.id definition_id,d.key,
      coalesce(nullif(btrim(f.store_label),''),nullif(btrim(d.store_label),''),p.form_contract->'labels'->>d.key,d.label) label,
      nullif(btrim(d.store_hint),'') hint,f.store_highlight,d.store_view,
      d.unit,d.data_type,d.validation_rules,p.form_contract,p.vals,p.vals->d.key val,min(f.sort_order) over(partition by f.section_key) section_order
    from assessed p join public.spec_template_fields f on f.template_id=p.template_id
    join public.spec_definitions d on d.id=f.spec_definition_id and d.is_customer_visible
    where coalesce(p.form_contract->'roles'->>d.key,'primary') <> 'legacy'
      and public.spec_rule_known_internal_v1(p.vals->d.key)
      -- El origen de un dato no decide si se publica (dueño, 2026-10-01): una
      -- deducción se muestra como cualquier otro dato y la mano la corrige.
      and not exists(select 1 from jsonb_array_elements(p.issues) i where coalesce((i->>'blocking')::boolean,true) and i->>'field' in ('',d.key))
  ), shown as (
    select f.*,case
      when f.data_type='json' and f.validation_rules ? 'rows_schema' and f.store_view is not null then public.spec_rows_store_display_internal_v1(f.store_view,f.validation_rules->'rows_schema',public.spec_coherence_display_rows_internal_v1(f.val,public.spec_coherence_labels_internal_v1(f.key,f.form_contract,f.vals)))
      when f.data_type='json' and f.validation_rules ? 'rows_schema' then public.spec_rows_display_internal_v1(f.validation_rules->'rows_schema',public.spec_coherence_display_rows_internal_v1(f.val,public.spec_coherence_labels_internal_v1(f.key,f.form_contract,f.vals)))
      when jsonb_typeof(f.val)='array' then (select string_agg(public.spec_option_display_internal_v1(f.definition_id,e,p_tenant_id),', ' order by n) from jsonb_array_elements_text(f.val) with ordinality a(e,n))
      when jsonb_typeof(f.val)='boolean' then case when f.val='true'::jsonb then 'Sí' else 'No' end
      when f.data_type='single_select' then public.spec_option_display_internal_v1(f.definition_id,f.val#>>'{}',p_tenant_id)
      else f.val#>>'{}' end display_value
    from fields f
  )
  select s.section_key,dense_rank() over(order by s.section_order,s.section_key)::integer,
    s.sort_order,s.key,s.label,s.display_value,s.unit,s.data_type,s.hint,s.store_highlight::integer
  from shown s where nullif(btrim(s.display_value),'') is not null
  order by s.section_order,s.sort_order,s.label
$$;

revoke all on function public.get_public_product_technical_specs(uuid, uuid) from public;
grant execute on function public.get_public_product_technical_specs(uuid, uuid) to anon, authenticated, service_role;
