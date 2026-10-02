-- La ficha dice de dónde salió cada dato (dueño, 2026-10-01: «arregla el 3»,
-- sobre «no se ve de dónde salió cada dato»).
--
-- De los 4.604 hechos de productos, uno solo lo escribió una persona; el resto
-- lo leyó el lector de nombres (1.709), lo tomó del texto del proveedor
-- (1.512), lo investigó un agente (852), vino de la ficha anterior (301) o se
-- dedujo (229). La procedencia ya estaba guardada en `spec_facts.source`, pero
-- el editor mostraba todos los valores iguales, así que «116 eslabones» leído
-- del nombre y un dato investigado se veían como una certeza.
--
-- La lectura del editor agrega `value_sources`: por clave de campo, la
-- procedencia del hecho y, para una lectura del nombre, si sigue en pie (el
-- nombre y el vocabulario con que se leyó son los de ahora). Sale de los mismos
-- hechos y en la misma instantánea que `values`; una app anterior ignora la
-- clave. `confirmed` no se envía: hoy es falso en todos los hechos y no
-- distingue nada.
begin;
set local lock_timeout = '5s';
set local statement_timeout = '60s';

create or replace function public.spec_product_value_sources_internal_v1(
  p_product_id uuid, p_template_id uuid)
returns jsonb
language sql
stable
set search_path = pg_catalog, public, pg_temp
as $$
  select coalesce(jsonb_object_agg(d.key, jsonb_build_object(
           'source', f.source,
           'reading_current', case when f.source = 'name_reading' then coalesce(
               r.source_digest = encode(sha256(convert_to(
                 concat_ws(' ', p.name, p.description), 'UTF8')), 'hex')
               and r.vocabulary_digest
                   = public.spec_definition_vocabulary_digest_internal_v1(f.spec_definition_id),
               false) end)), '{}'::jsonb)
    from public.products p
    join public.spec_facts f
      on f.tenant_id = p.tenant_id and f.subject_type = 'product'
     and f.subject_id = p.id and f.subject_scope is null
    join public.spec_definitions d on d.id = f.spec_definition_id
    left join public.spec_fact_readings r on r.fact_id = f.id
   where p.id = p_product_id
     and exists (select 1 from public.spec_template_fields tf
                  where tf.template_id = p_template_id
                    and tf.spec_definition_id = f.spec_definition_id)
$$;

revoke all on function public.spec_product_value_sources_internal_v1(uuid, uuid)
  from public, anon, authenticated;
grant execute on function public.spec_product_value_sources_internal_v1(uuid, uuid)
  to service_role;

-- La propiedad del producto y del tenant la comprueba v1 antes de leer nada.
CREATE OR REPLACE FUNCTION public.get_product_spec_editor_context_v2(p_product_id uuid, p_category_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
AS $function$
#variable_conflict use_variable
declare result jsonb; template_id uuid; template jsonb; fields jsonb; unassigned jsonb;
 tenant uuid:=public.user_tenant_id();
begin
 -- This call enforces product/category tenant ownership and explicit binding.
 -- STABLE nested reads share this statement's MVCC snapshot.
 result:=public.get_product_spec_editor_context_v1(p_product_id,p_category_id);
 template_id:=(result->>'template_id')::uuid;
 if template_id is not null then
   template:=public.spec_template_editor_internal_v1(template_id,tenant);
 end if;
 select coalesce(jsonb_agg(case when d.data_type='number' then e.value||jsonb_build_object(
     'value',public.spec_json_numbers_as_text_internal_v1(e.value->'value')) else e.value end order by e.ordinality),'[]'::jsonb)
 into unassigned from jsonb_array_elements(result->'unassigned_facts') with ordinality e
 left join public.spec_definitions d on d.id::text=e.value->>'definition_id';
 return result||jsonb_build_object('read_schema_version',2,'product_id',p_product_id,'draft_category_id',p_category_id,
   'template',template,'unassigned_facts',unassigned,
   'values',public.spec_payload_display_exact_internal_v1(public.spec_template_product_payload_internal_v1(p_product_id,template_id,true)),
   'value_sources',public.spec_product_value_sources_internal_v1(p_product_id,template_id));
end $function$;

commit;
