-- Falla si vuelve a haber dos firmas del sobre, o si la que queda no atiende
-- una llamada de tres argumentos.
select 1 / (case when
  (select count(*) from pg_proc p
     join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public'
     and p.proname = 'assistant_tool_envelope_internal_v1') = 1
  and (
    public.assistant_tool_envelope_internal_v1(
      '5443b130-cc28-45af-a420-cd500b288890'::uuid, '[]'::jsonb, false
    ) ->> 'totalMatches'
  )::int = 0
  and (
    public.assistant_tool_envelope_internal_v1(
      '5443b130-cc28-45af-a420-cd500b288890'::uuid, '[{"a":1}]'::jsonb, true, 99
    ) ->> 'totalMatches'
  )::int = 99
then 1 else 0 end) as una_sola_firma;
