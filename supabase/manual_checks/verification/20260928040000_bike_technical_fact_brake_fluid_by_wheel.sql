-- Read-back de 20260928040000_bike_technical_fact_brake_fluid_by_wheel.
-- Antes de desplegar tiene que fallar contra producción. Se corre junto con
-- los read-back de 20260928020000, 20260928010000 y 20260927040000, que
-- siguen valiendo; el de 20260928030000 queda reemplazado por éste (su
-- `brakeFluidType` ya no se acepta).

-- El fluido es de cada freno: dos claves con el vocabulario del registro, y
-- la clave de bici completa ya no se acepta.
select 1 / (case when
  pg_get_functiondef('public.patch_bike_technical_facts_v1(text,uuid,uuid,text,jsonb)'::regprocedure)
    like '%when ''frontBrakeFluidType'' then v_text in (''aceite_mineral'', ''dot_4'', ''dot_5_1'')%'
  and pg_get_functiondef('public.patch_bike_technical_facts_v1(text,uuid,uuid,text,jsonb)'::regprocedure)
    like '%when ''rearBrakeFluidType'' then v_text in (''aceite_mineral'', ''dot_4'', ''dot_5_1'')%'
  and pg_get_functiondef('public.patch_bike_technical_facts_v1(text,uuid,uuid,text,jsonb)'::regprocedure)
    not like '%''brakeFluidType''%'
  and pg_get_functiondef('public.patch_bike_technical_facts_v1(text,uuid,uuid,text,jsonb)'::regprocedure)
    like '%or v_text = ''catalog_de6e897b1c6ced32e6762f3ceaebffd6''%'
  and pg_get_functiondef('public.patch_bike_technical_facts_v1(text,uuid,uuid,text,jsonb)'::regprocedure)
    like '%The job line did not install %'
then 1 else 0 end) as fluido_por_freno;

-- El vocabulario del comando sigue siendo exactamente el del registro.
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

-- Ninguna ficha quedó con la clave de bici completa.
select 1 / (case when not exists (
  select 1 from public.bike_profiles
   where technical_profile->'values' ? 'brakeFluidType'
) then 1 else 0 end) as sin_fluido_de_bici_completa;

-- Mismos permisos: sólo el empleado autenticado ejecuta el comando.
select 1 / (case when
  has_function_privilege('authenticated',
    'public.patch_bike_technical_facts_v1(text,uuid,uuid,text,jsonb)', 'EXECUTE')
  and not has_function_privilege('anon',
    'public.patch_bike_technical_facts_v1(text,uuid,uuid,text,jsonb)', 'EXECUTE')
  and not has_function_privilege('service_role',
    'public.patch_bike_technical_facts_v1(text,uuid,uuid,text,jsonb)', 'EXECUTE')
then 1 else 0 end) as permisos_sin_cambio;
