-- Read-back de 20260927050000_bike_technical_fact_job_completion.
-- Antes de desplegar tiene que fallar contra producción. Se corre junto con
-- los read-back de 20260927030000 y 20260927040000, que siguen valiendo.

-- Lo instalado entra sólo con el trabajo terminado, sólo con `set`, y el
-- recibo acepta esa fuente.
select 1 / (case when
  pg_get_functiondef('public.patch_bike_technical_facts_v1(text,uuid,uuid,text,jsonb)'::regprocedure)
    like '%Installed parts change the bicycle only when the job is finished%'
  and pg_get_functiondef('public.patch_bike_technical_facts_v1(text,uuid,uuid,text,jsonb)'::regprocedure)
    like '%A finished job only sets installed bicycle facts%'
  and pg_get_functiondef('public.patch_bike_technical_facts_v1(text,uuid,uuid,text,jsonb)'::regprocedure)
    like '%j.status in (''FINALIZADO'', ''ENTREGADO'')%'
  and (select pg_get_constraintdef(oid) from pg_constraint
        where conrelid = 'public.bike_technical_fact_patches'::regclass
          and conname = 'bike_technical_fact_patches_source_check')
    like '%job_completion%'
then 1 else 0 end) as instalado_al_terminar;
