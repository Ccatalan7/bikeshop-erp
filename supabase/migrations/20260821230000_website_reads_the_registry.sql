-- Fase 8, primer lector: la tienda lee el registro.
--
-- `get_public_product_technical_specs` leía `product_spec_values`, donde el
-- valor de una lista es la ETIQUETA copiada en la fila del producto. Por eso
-- renombrar «Cartucho sellado» a «Rodamiento sellado» sólo se vio en la tienda
-- después de reescribir los 48 productos.
--
-- Leyendo `spec_facts` + `spec_definition_values` la etiqueta se resuelve en la
-- consulta: renombrar cambia lo que ve el cliente sin tocar un producto.
--
-- La firma y las columnas no cambian, así que la tienda desplegada la sigue
-- llamando igual y no necesita recompilarse. Se elige este lector primero
-- porque es de sólo lectura y se verifica mirando la página.

begin;

CREATE OR REPLACE FUNCTION public.get_public_product_technical_specs(p_tenant_id uuid, p_product_id uuid)
 RETURNS TABLE(section_key text, section_sort_order integer, field_sort_order integer, spec_key text, spec_label text, display_value text, unit text, data_type text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
      -- La etiqueta sale del registro, no de una copia congelada en la fila del
      -- producto. Renombrar un valor cambia lo que ve el cliente sin reescribir
      -- un solo producto: ése es el punto del registro.
      null::text as display_value,
      f.value_text,
      f.value_number,
      f.value_boolean,
      (
        select string_agg(sv.label, ', ' order by fv2.position)
        from public.spec_fact_values fv2
        join public.spec_definition_values sv on sv.id = fv2.value_id
        where fv2.fact_id = f.id
      ) as value_option,
      null::jsonb as value_json
    from visible_product p
    join template_match tm on true
    join public.spec_template_fields stf
      on stf.template_id = tm.template_id
     and (stf.tenant_id is null or stf.tenant_id = p_tenant_id)
    join public.spec_definitions sd
      on sd.id = stf.spec_definition_id
     and (sd.tenant_id is null or sd.tenant_id = p_tenant_id)
    join public.spec_facts f
      on f.subject_type = 'product'
     and f.subject_id = p.id
     and f.tenant_id = p_tenant_id
     and f.spec_definition_id = sd.id
     and f.subject_scope is null
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
          when fv.data_type = 'multi_select' then fv.value_option
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
$function$
;

commit;
