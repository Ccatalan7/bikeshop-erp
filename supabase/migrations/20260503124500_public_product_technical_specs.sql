create or replace function public.get_public_product_technical_specs(
  p_tenant_id uuid,
  p_product_id uuid
)
returns table (
  section_key text,
  section_sort_order integer,
  field_sort_order integer,
  spec_key text,
  spec_label text,
  display_value text,
  unit text,
  data_type text
)
language sql
stable
security definer
set search_path = public
as $$
  with visible_product as (
    select p.id, p.category_id
    from public.products p
    where p.tenant_id = p_tenant_id
      and p.id = p_product_id
      and coalesce(p.is_active, true) = true
      and coalesce(p.is_published, false) = true
      and coalesce(p.show_on_website, false) = true
    limit 1
  ),
  template_match as (
    select ctm.template_id
    from visible_product p
    join public.category_tech_mappings ctm
      on ctm.category_id = p.category_id
     and ctm.tenant_id = p_tenant_id
    where ctm.template_id is not null
    order by ctm.created_at desc
    limit 1
  ),
  raw_field_values as (
    select
      stf.section_key,
      min(stf.sort_order) over (partition by stf.section_key)::integer as section_min_sort_order,
      stf.sort_order::integer as field_sort_order,
      sd.key as spec_key,
      sd.label as spec_label,
      sd.unit,
      sd.data_type,
      psv.display_value,
      psv.value_text,
      psv.value_number,
      psv.value_boolean,
      psv.value_option,
      psv.value_json
    from visible_product p
    join template_match tm on true
    join public.spec_template_fields stf
      on stf.template_id = tm.template_id
     and (stf.tenant_id is null or stf.tenant_id = p_tenant_id)
    join public.spec_definitions sd
      on sd.id = stf.spec_definition_id
     and (sd.tenant_id is null or sd.tenant_id = p_tenant_id)
    join public.product_spec_values psv
      on psv.product_id = p.id
     and psv.tenant_id = p_tenant_id
     and psv.spec_definition_id = sd.id
  ),
  field_values as (
    select
      r.*,
      dense_rank() over (order by r.section_min_sort_order, r.section_key)::integer as section_sort_order
    from raw_field_values r
  )
  select
    fv.section_key,
    fv.section_sort_order,
    fv.field_sort_order,
    fv.spec_key,
    fv.spec_label,
    nullif(
      coalesce(
        nullif(btrim(fv.display_value), ''),
        case
          when fv.data_type = 'boolean' then case when fv.value_boolean then 'Sí' else 'No' end
          when fv.data_type = 'number' then fv.value_number::text
          when fv.data_type = 'single_select' then fv.value_option
          when fv.data_type = 'multi_select' and jsonb_typeof(fv.value_json) = 'array' then (
            select string_agg(value, ', ' order by ordinality)
            from jsonb_array_elements_text(fv.value_json) with ordinality as option_value(value, ordinality)
          )
          when fv.value_json is not null then fv.value_json::text
          else fv.value_text
        end
      ),
      ''
    ) as display_value,
    fv.unit,
    fv.data_type
  from field_values fv
  where nullif(
    coalesce(
      nullif(btrim(fv.display_value), ''),
      fv.value_text,
      fv.value_option,
      fv.value_number::text,
      fv.value_boolean::text,
      fv.value_json::text
    ),
    ''
  ) is not null
  order by fv.section_sort_order, fv.field_sort_order, fv.spec_label;
$$;

grant execute on function public.get_public_product_technical_specs(uuid, uuid) to anon, authenticated;