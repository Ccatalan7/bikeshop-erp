-- Read-back de 20260928070000_job_line_installed_bike_facts. Antes de
-- desplegar tiene que fallar contra producción (no existen los disparadores).

-- Agregar una línea o cambiarle la configuración, la ubicación o la bici en
-- un trabajo terminado aplica lo instalado; la función del disparador no se
-- llama desde afuera.
select 1 / (case when
  exists (select 1 from pg_trigger
           where tgrelid = 'public.mechanic_job_items'::regclass
             and tgname = 'trg_mechanic_job_items_installed_bike_facts_insert'
             and not tgisinternal and tgenabled = 'O')
  and exists (select 1 from pg_trigger
               where tgrelid = 'public.mechanic_job_items'::regclass
                 and tgname = 'trg_mechanic_job_items_installed_bike_facts_update'
                 and not tgisinternal and tgenabled = 'O'
                 and pg_get_triggerdef(oid) like '%service_configuration_data IS DISTINCT FROM%')
  and not has_function_privilege('authenticated',
    'public.apply_installed_bike_facts_on_job_line_change()', 'EXECUTE')
  and pg_get_functiondef('public.apply_installed_bike_facts_on_job_line_change()'::regprocedure)
    like '%for no key update%'
then 1 else 0 end) as linea_terminada_instala;

-- Borrar una línea terminada también pasa por la regla (deja el aviso en la
-- historia de la bici), y el disparador falla en vez de callarse cuando lo
-- que instala la línea no entra a la ficha.
select 1 / (case when
  exists (select 1 from pg_trigger
           where tgrelid = 'public.mechanic_job_items'::regclass
             and tgname = 'trg_mechanic_job_items_installed_bike_facts_delete'
             and not tgisinternal and tgenabled = 'O')
  and pg_get_functiondef('public.apply_installed_bike_facts_on_job_line_change()'::regprocedure)
    like '%errcode = ''23514''%'
  and to_regprocedure('public.record_installed_bike_fact_notice(uuid,uuid,uuid,text,text,text,text,jsonb,boolean)') is not null
  and not has_function_privilege('authenticated',
    'public.record_installed_bike_fact_notice(uuid,uuid,uuid,text,text,text,text,jsonb,boolean)', 'EXECUTE')
then 1 else 0 end) as borrar_avisa_y_editar_no_se_calla;
