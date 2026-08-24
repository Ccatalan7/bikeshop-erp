select
  1 / (case when exists (
    select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'supply_need_category_for_phrase_internal_v1'
  ) then 1 else 0 end) as existe,
  1 / (case when not has_function_privilege('authenticated',
    'public.supply_need_category_for_phrase_internal_v1(uuid,text)', 'execute')
    then 1 else 0 end) as no_expuesto,
  -- Sin rama dominante devuelve nulo: inventar una es peor que no tenerla.
  1 / (case when (
    select prosrc from pg_proc
    where proname = 'supply_need_category_for_phrase_internal_v1'
  ) like '%>= 0.6%' then 1 else 0 end) as exige_dominancia;
