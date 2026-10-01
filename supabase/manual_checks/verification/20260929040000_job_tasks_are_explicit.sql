-- Read-back de 20260929040000_job_tasks_are_explicit. Antes de desplegar
-- tiene que fallar contra producción (el disparador del parser sigue ahí).

select 1 / (case when
  not exists (
    select 1 from pg_trigger
     where tgrelid = 'public.mechanic_job_items'::regclass
       and tgname = 'trg_auto_parse_item_description')
  and to_regprocedure('public.auto_parse_item_description()') is null
  and not exists (
    select 1 from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace and n.nspname = 'public'
     where p.proname = 'parse_description_to_tasks')
then 1 else 0 end) as sin_parser_de_descripciones;

select 1 / (case when
  exists (
    select 1 from pg_trigger
     where tgrelid = 'public.mechanic_job_tasks'::regclass
       and tgname = 'trg_mechanic_job_task_is_explicit'
       and tgenabled = 'O'
       and tgfoid = 'public.mechanic_job_task_is_explicit()'::regprocedure)
  and pg_get_functiondef('public.mechanic_job_task_is_explicit()'::regprocedure)
    like '%job_task_from_description%'
  and not has_function_privilege('authenticated',
    'public.mechanic_job_task_is_explicit()', 'EXECUTE')
then 1 else 0 end) as tareas_sólo_de_personas;

select 1 / (case when
  exists (
    select 1 from pg_trigger
     where tgrelid = 'public.mechanic_job_tasks'::regclass
       and tgname = 'trg_mechanic_job_task_same_tenant'
       and tgenabled = 'O'
       and tgfoid = 'public.mechanic_job_task_same_tenant()'::regprocedure)
  and pg_get_functiondef('public.mechanic_job_task_same_tenant()'::regprocedure)
    like '%job_task_other_tenant%'
  and not has_function_privilege('authenticated',
    'public.mechanic_job_task_same_tenant()', 'EXECUTE')
then 1 else 0 end) as tareas_del_mismo_taller;
