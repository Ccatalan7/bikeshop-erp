-- Read-back de 20261115063000_part_change_single_wheel_line.
-- Sólo `select` planos (corre en lectura remota): cada uno revienta si falta
-- la definición o si el invariante no se cumple.

-- 1. La rueda única de un repuesto existe y es interna.
select 1 / (
  to_regprocedure('public.part_line_single_wheel_internal(uuid,uuid)') is not null
  and not has_function_privilege('authenticated',
    'public.part_line_single_wheel_internal(uuid,uuid)', 'EXECUTE')
)::int as rueda_unica_interna;

-- 2. En Viñabike ninguna línea con marca y sin rueda, de un repuesto que va
--    en una sola rueda, queda sin verificar (antes había una abierta: el
--    cassette de un trabajo de dos bicis que no se podía entregar).
select 1 / (count(*) = 0)::int as lineas_sin_rueda_verificadas
  from public.mechanic_job_items i
 where i.tenant_id = (select t.id from public.tenants t where t.subdomain = 'vinabike')
   and i.service_configuration_data ? 'part_change'
   and coalesce(i.location_key, 'none') not in ('front', 'rear')
   and public.part_line_single_wheel_internal(i.tenant_id, i.product_id) is not null
   and exists (
     select 1
       from jsonb_array_elements(public.job_line_part_change_marks_internal(
              i.service_configuration_data->'part_change')) m
      where public.job_line_part_change_internal(i.tenant_id, i.id, m->>'key') is null);

-- 3. Y esa línea ahora respalda su driver atrás.
select 1 / (count(*) >= 1)::int as cassette_sin_rueda_respalda_driver
  from public.mechanic_job_items i
 where i.tenant_id = (select t.id from public.tenants t where t.subdomain = 'vinabike')
   and i.service_configuration_data ? 'part_change'
   and coalesce(i.location_key, 'none') not in ('front', 'rear')
   and public.part_line_single_wheel_internal(i.tenant_id, i.product_id) = 'rear'
   and public.job_line_part_change_internal(i.tenant_id, i.id, 'freehubType')->>'position' = 'rear';
