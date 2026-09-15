-- Exclude only pending inferred root observations from customer specification output.
-- No product/fact edits, no change to internal readers or other source semantics.
do $guard$
declare current_body text;
begin
 current_body:=pg_get_functiondef('public.get_public_product_technical_specs(uuid,uuid)'::regprocedure);
 if md5(current_body)='4d42285fdfc0bc9c33fce0fe6d9d40a3' then return; end if;
 if md5(current_body) is distinct from '89e21f13bb41bdac92b17e62b059df06' then
   raise exception 'Public specification reader changed after review';
 end if;
 execute $reader$CREATE OR REPLACE FUNCTION public.get_public_product_technical_specs(p_tenant_id uuid, p_product_id uuid)
 RETURNS TABLE(section_key text, section_sort_order integer, field_sort_order integer, spec_key text, spec_label text, display_value text, unit text, data_type text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
AS $function$
  with visible as (
    select p.id,p.brand,p.model,p.manufacturer_sku,p.spec_reference_id,t.id template_id,t.form_contract
    from public.products p
    join public.product_spec_bindings_internal_v1 b on b.product_id=p.id
    join public.spec_templates t on t.id=b.template_id and t.is_active and (t.tenant_id is null or t.tenant_id=p.tenant_id)
    where p.id=p_product_id and p.tenant_id=p_tenant_id and coalesce(p.is_active,true)
      and coalesce(p.is_published,false) and coalesce(p.show_on_website,false)
  ), facts as (
    select p.*,public.spec_active_product_values_internal_v1(p.id,p.template_id) vals from visible p
  ), assessed as (select p.*,public.spec_validate_draft_internal_v1(p.template_id,p.vals,p.spec_reference_id,p.brand,p.model,p.manufacturer_sku) issues from facts p
  ), fields as (
    select f.section_key,f.sort_order,d.key,coalesce(p.form_contract->'labels'->>d.key,d.label) label,
      d.unit,d.data_type,d.validation_rules,p.form_contract,p.vals,p.vals->d.key val,min(f.sort_order) over(partition by f.section_key) section_order
    from assessed p join public.spec_template_fields f on f.template_id=p.template_id
    join public.spec_definitions d on d.id=f.spec_definition_id and d.is_customer_visible
    where coalesce(p.form_contract->'roles'->>d.key,'primary') <> 'legacy'
      and public.spec_rule_known_internal_v1(p.vals->d.key)
      -- Pending inference is retained in the editor, not asserted by the storefront.
      -- Confirmation and source are distinct: other origins keep their existing policy.
      and not exists (
        select 1 from public.spec_facts observed
        where observed.tenant_id=p_tenant_id and observed.subject_type='product'
          and observed.subject_id=p.id and observed.subject_scope is null
          and observed.spec_definition_id=d.id
          and observed.source='inferred' and not coalesce(observed.confirmed,false)
      )
      and not exists(select 1 from jsonb_array_elements(p.issues) i where coalesce((i->>'blocking')::boolean,true) and i->>'field' in ('',d.key))
  )
  select f.section_key,dense_rank() over(order by f.section_order,f.section_key)::integer,
    f.sort_order,f.key,f.label,case
      when f.data_type='json' and f.validation_rules ? 'rows_schema' then public.spec_rows_display_internal_v1(f.validation_rules->'rows_schema',public.spec_coherence_display_rows_internal_v1(f.val,public.spec_coherence_labels_internal_v1(f.key,f.form_contract,f.vals)))
      when jsonb_typeof(f.val)='array' then (select string_agg(e,', ' order by n) from jsonb_array_elements_text(f.val) with ordinality a(e,n))
      when jsonb_typeof(f.val)='boolean' then case when f.val='true'::jsonb then 'Sí' else 'No' end
      else f.val#>>'{}' end,f.unit,f.data_type
  from fields f order by f.section_order,f.sort_order,f.label
$function$
$reader$;
 if md5(pg_get_functiondef('public.get_public_product_technical_specs(uuid,uuid)'::regprocedure))
    is distinct from '4d42285fdfc0bc9c33fce0fe6d9d40a3' then raise exception 'Public reader postimage differs'; end if;
end $guard$;
