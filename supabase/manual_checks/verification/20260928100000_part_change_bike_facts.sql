-- Read-back de 20260928100000_part_change_bike_facts. Antes de desplegar
-- tiene que fallar contra producción (no existe la relación).

-- La relación única: el rotor por rueda, con lo que pide de la bici; la app
-- la lee y no la escribe.
select 1 / (case when
  (select count(*) from public.bike_fact_spec_links
    where spec_key = 'rotor_diameter_mm_value') = 2
  and exists (select 1 from public.bike_fact_spec_links
               where spec_key = 'rotor_diameter_mm_value' and position = 'front'
                 and bike_fact_key = 'frontRotorSizeMm'
                 and requires_fact_key = 'brakeType'
                 and requires_fact_values = array['mechanical_disc', 'hydraulic_disc'])
  and exists (select 1 from public.bike_fact_spec_links
               where spec_key = 'rotor_diameter_mm_value' and position = 'rear'
                 and bike_fact_key = 'rearRotorSizeMm'
                 and requires_fact_key = 'brakeType'
                 and requires_fact_values = array['mechanical_disc', 'hydraulic_disc'])
  and has_table_privilege('authenticated', 'public.bike_fact_spec_links', 'SELECT')
  and not has_table_privilege('authenticated', 'public.bike_fact_spec_links', 'INSERT')
  and not has_table_privilege('anon', 'public.bike_fact_spec_links', 'SELECT')
then 1 else 0 end) as relacion_unica;

-- El lector de la ficha del producto es el de la app y da lo que dice el
-- inventario real: 180 para el RT56 de 180, nada para unas pastillas.
select 1 / (case when
  not has_function_privilege('authenticated',
    'public.product_bike_fact_spec_value_internal(uuid,uuid,text)', 'EXECUTE')
  and not has_function_privilege('authenticated',
    'public.job_line_part_change_internal(uuid,uuid)', 'EXECUTE')
  and (select public.product_bike_fact_spec_value_internal(
                p.tenant_id, p.id, 'rotor_diameter_mm_value')
         from public.products p
        where p.name = 'Disco freno Shimano Deore RT56 180MM'
        order by p.created_at
        limit 1) = '180'::jsonb
  and (select count(*)
         from public.products p
        where p.category_name = 'Pastillas'
          and public.product_bike_fact_spec_value_internal(
                p.tenant_id, p.id, 'rotor_diameter_mm_value') is not null) = 0
  -- Otro taller no lee el producto.
  and (select public.product_bike_fact_spec_value_internal(
                (select t.id from public.tenants t where t.id <> p.tenant_id
                  order by t.id limit 1),
                p.id, 'rotor_diameter_mm_value')
         from public.products p
        where p.name = 'Disco freno Shimano Deore RT56 180MM'
        order by p.created_at
        limit 1) is null
  -- En todo producto con un concepto enlazado, el lector da lo mismo que el
  -- espejo `product_spec_values` (16 de 16 rotores el 2026-09-28).
  and (select count(*)
         from public.product_spec_values v
         join public.spec_definitions d on d.id = v.spec_definition_id
         join public.bike_fact_spec_links l
           on l.spec_key = d.key and l.position = 'front'
         join public.products p
           on p.id = v.product_id and p.tenant_id = v.tenant_id
        where v.value_number is not null
          and (public.product_bike_fact_spec_value_internal(
                 p.tenant_id, p.id, l.spec_key) #>> '{}')::numeric
              is distinct from v.value_number) = 0
then 1 else 0 end) as lector_del_producto;

-- Las reglas compartidas del aplicador y el parche son internas.
select 1 / (case when
  not has_function_privilege('authenticated',
    'public.job_line_bike_internal(uuid,uuid)', 'EXECUTE')
  and not has_function_privilege('authenticated',
    'public.bike_fact_part_misfit_internal(text,jsonb,jsonb)', 'EXECUTE')
  and not has_function_privilege('service_role',
    'public.job_line_bike_internal(uuid,uuid)', 'EXECUTE')
  and (select min_value = 100 and max_value = 260
         from public.bike_fact_spec_links
        where bike_fact_key = 'rearRotorSizeMm')
then 1 else 0 end) as reglas_compartidas;

-- El parche acepta el rotor sólo con la línea que lo respalda; la regla que
-- aplica al terminar comprueba la ficha real; el disparador cuenta el
-- repuesto.
select 1 / (case when
  pg_get_functiondef('public.patch_bike_technical_facts_v1(text,uuid,uuid,text,jsonb)'::regprocedure)
    like '%Un repuesto instala las claves de la relación%'
  and pg_get_functiondef('public.patch_bike_technical_facts_v1(text,uuid,uuid,text,jsonb)'::regprocedure)
    like '%) is not true then%The job line did not install%'
  and pg_get_functiondef('public.patch_bike_technical_facts_v1(text,uuid,uuid,text,jsonb)'::regprocedure)
    like '%bike_fact_part_misfit_internal%'
  and pg_get_functiondef('public.patch_bike_technical_facts_v1(text,uuid,uuid,text,jsonb)'::regprocedure)
    like '%job_line_bike_internal%'
  and pg_get_functiondef('public.patch_bike_technical_facts_v1(text,uuid,uuid,text,jsonb)'::regprocedure)
    like '%later corrections are kept%'
  and pg_get_functiondef('public.apply_job_installed_bike_facts_internal(uuid,uuid,boolean)'::regprocedure)
    like '%''incompatible''%'
  and pg_get_functiondef('public.apply_job_installed_bike_facts_internal(uuid,uuid,boolean)'::regprocedure)
    like '%job_line_part_change_internal%'
  and public.installed_bike_fact_label('rearRotorSizeMm', '180'::jsonb) = '180 mm en el rotor trasero'
  and public.installed_bike_fact_label('frontSpokeHoles', '28'::jsonb) = '28H en la rueda delantera'
  and exists (select 1 from pg_trigger
               where tgrelid = 'public.mechanic_job_items'::regclass
                 and tgname = 'trg_mechanic_job_items_installed_bike_facts_update'
                 and not tgisinternal and tgenabled = 'O'
                 and pg_get_triggerdef(oid) like '%product_id IS DISTINCT FROM%'
                 and pg_get_triggerdef(oid) like '%job_id IS DISTINCT FROM%')
then 1 else 0 end) as rotor_por_la_puerta;
