-- Verifier: fails (division by zero) until the specificity tiebreak is live and the presentation vocabulary is split.
select 1/(case
  when pg_get_functiondef('public.spec_reading_rejection_internal_v1(uuid,jsonb,text)'::regprocedure) like '%spec_terms_best_length_internal_v1%'
   and (select public.spec_terms_best_length_internal_v1('juego de frenos hidraulicos', (select array['juego','juego de frenos'] from pg_class limit 1))) = 15
   and (select public.spec_terms_best_length_internal_v1('herradura par negra', (select array['juego de frenos'] from pg_class limit 1))) = 0
   and exists (select 1 from public.spec_definition_values v join public.spec_definitions d on d.id = v.spec_definition_id
               where d.tenant_id is null and d.key = 'brake_presentation' and v.label = 'Par de mecanismos' and 'juego' = any(v.reading_terms))
   and not exists (select 1 from public.spec_definition_values v join public.spec_definitions d on d.id = v.spec_definition_id
               where d.tenant_id is null and d.key = 'brake_presentation' and v.label = 'Par delantero y trasero' and 'juego' = any(v.reading_terms))
  then 1 else 0 end) as ok;
