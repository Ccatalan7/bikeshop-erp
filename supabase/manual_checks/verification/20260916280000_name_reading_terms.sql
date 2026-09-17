-- Verifier: fails (division by zero) until the reading-terms columns exist and the rejection helper honours them.
-- The probe reads a definition through a subquery so nothing is folded at plan time; it asks for the reading-terms
-- column by name in a subquery guarded by information_schema so the whole statement still parses before the migration.
select 1/(case
  when (select count(*) from information_schema.columns
        where table_schema='public' and table_name='spec_definition_values' and column_name='reading_terms') = 1
   and (select count(*) from information_schema.columns
        where table_schema='public' and table_name='spec_definitions' and column_name in ('reading_terms','reading_terms_false')) = 2
   and pg_get_functiondef('public.spec_reading_rejection_internal_v1(uuid,jsonb,text)'::regprocedure) like '%spec_terms_hit_internal_v1%'
   and pg_get_functiondef('public.spec_definition_vocabulary_digest_internal_v1(uuid)'::regprocedure) like '%reading_terms_false%'
   and (select public.spec_terms_hit_internal_v1('maza ztto 100mm 32h qr morado', (select array['qr','bloqueo'] from pg_class limit 1)))
   and (select public.spec_boolean_from_terms_internal_v1('eje macizo trasero', (select array['macizo'] from pg_class limit 1))) is true
   and (select public.spec_boolean_from_terms_internal_v1('eje sin bloqueo', (select array['bloqueo'] from pg_class limit 1))) is false
  then 1 else 0 end) as ok;
