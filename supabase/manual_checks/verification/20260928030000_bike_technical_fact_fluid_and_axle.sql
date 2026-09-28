-- Read-back de 20260928030000_bike_technical_fact_fluid_and_axle.
-- Antes de desplegar tiene que fallar contra producción. Se corre junto con
-- los read-back de 20260927030000, 20260927040000, 20260927050000,
-- 20260928002200, 20260928010000 y 20260928020000, que siguen valiendo.

-- El comando acepta el fluido y el eje de cada rueda, y sigue probando lo
-- instalado por su línea.
select 1 / (case when
  pg_get_functiondef('public.patch_bike_technical_facts_v1(text,uuid,uuid,text,jsonb)'::regprocedure)
    like '%''brakeFluidType'', ''frontAxleInterface'', ''rearAxleInterface''%'
  and pg_get_functiondef('public.patch_bike_technical_facts_v1(text,uuid,uuid,text,jsonb)'::regprocedure)
    like '%when ''brakeFluidType'' then v_text in (''aceite_mineral'', ''dot_4'', ''dot_5_1'')%'
  and pg_get_functiondef('public.patch_bike_technical_facts_v1(text,uuid,uuid,text,jsonb)'::regprocedure)
    like '%or v_text = ''catalog_de6e897b1c6ced32e6762f3ceaebffd6''%'
  and pg_get_functiondef('public.patch_bike_technical_facts_v1(text,uuid,uuid,text,jsonb)'::regprocedure)
    like '%The job line did not install %'
then 1 else 0 end) as fluido_y_eje_en_el_comando;

-- El vocabulario del comando es exactamente el del registro: cada código
-- activo y global, sin «Desconocido / sin confirmar», está en el comando, y
-- el registro no tiene más que los que el comando nombra (3 fluidos, 8 ejes).
select 1 / (case when
  (select count(*)
     from public.spec_definition_values v
     join public.spec_definitions d on d.id = v.spec_definition_id
    where d.tenant_id is null and v.tenant_id is null and v.is_active
      and d.key = 'fluid_type') = 3
  and (select count(*)
     from public.spec_definition_values v
     join public.spec_definitions d on d.id = v.spec_definition_id
    where d.tenant_id is null and v.tenant_id is null and v.is_active
      and d.key = 'axle_type'
      and v.code <> 'catalog_de6e897b1c6ced32e6762f3ceaebffd6') = 8
  and not exists (
    select 1
      from public.spec_definition_values v
      join public.spec_definitions d on d.id = v.spec_definition_id
     where d.tenant_id is null and v.tenant_id is null and v.is_active
       and d.key in ('fluid_type', 'axle_type')
       and v.code <> 'catalog_de6e897b1c6ced32e6762f3ceaebffd6'
       and pg_get_functiondef('public.patch_bike_technical_facts_v1(text,uuid,uuid,text,jsonb)'::regprocedure)
           not like '%''' || v.code || '''%')
then 1 else 0 end) as vocabulario_del_registro;

-- La matriz: el eje de la bici completa y del cuadro usan los mismos códigos
-- que el de horquilla, maza y rueda, así que la ficha de la bici y la del
-- inventario hablan de lo mismo.
select 1 / (case when not exists (
  select v.code
    from public.spec_definition_values v
    join public.spec_definitions d on d.id = v.spec_definition_id
   where d.tenant_id is null and v.tenant_id is null and v.is_active
     and d.key in ('front_axle_type', 'rear_axle_type')
  except
  select v.code
    from public.spec_definition_values v
    join public.spec_definitions d on d.id = v.spec_definition_id
   where d.tenant_id is null and v.tenant_id is null and v.is_active
     and d.key = 'axle_type'
) then 1 else 0 end) as ejes_de_bici_y_pieza_iguales;

-- Mismos permisos: sólo el empleado autenticado ejecuta el comando.
select 1 / (case when
  has_function_privilege('authenticated',
    'public.patch_bike_technical_facts_v1(text,uuid,uuid,text,jsonb)', 'EXECUTE')
  and not has_function_privilege('anon',
    'public.patch_bike_technical_facts_v1(text,uuid,uuid,text,jsonb)', 'EXECUTE')
  and not has_function_privilege('service_role',
    'public.patch_bike_technical_facts_v1(text,uuid,uuid,text,jsonb)', 'EXECUTE')
then 1 else 0 end) as permisos_sin_cambio;
