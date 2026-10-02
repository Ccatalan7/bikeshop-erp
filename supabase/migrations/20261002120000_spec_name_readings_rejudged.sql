-- Las lecturas del nombre que siguen en pie vuelven a contar (2026-10-01).
--
-- Cada lectura del nombre guarda la huella del vocabulario con que el servidor
-- juzgó la cita (`vocabulary_digest`: rótulo, descripción, opciones y términos
-- de lectura del campo). Si ese vocabulario cambia, la lectura deja de contar
-- hasta que se vuelve a juzgar: «renombrar la etiqueta elegida, cambiar el
-- nombre del campo o agregar un valor hermano más específico» son formas de
-- que la misma cita deje de decir lo que decía (20260906160000).
--
-- Nadie la volvía a juzgar. Las pasadas de vocabulario del 2026-09-16→19
-- (etiquetas de tienda, español de taller, términos de lectura) dejaron 292 de
-- las 1.709 lecturas mudas: 80 cantidades de hoyos de maza, 21 anchos entre
-- tuercas, las 20 de «Tipo de transmisión»… El editor y el taller las mostraban
-- igual, pero la búsqueda técnica del asistente de inventario las ignoraba:
-- «¿tienes cadenas de 6 velocidades?» no encontraba productos que lo dicen en
-- el nombre.
--
-- Aquí se vuelve a juzgar cada lectura muda con el vocabulario actual y el
-- mismo juez del servidor (`spec_reading_rejection_internal_v1`), con la cita
-- y el valor guardados. La que el juez acepta recibe la huella actual (268 el
-- 2026-10-01); la que no, sigue muda, que es lo correcto: 24 booleanos cuya
-- cita no dice el campo («Trasera» no dice «tiene montaje para piñón»). La
-- huella del nombre del producto (`source_digest`) no se toca: si el nombre
-- cambió, la lectura sigue sin contar. Sólo lecturas de la ficha principal; las
-- de componentes tienen su propio dueño y revisión.
begin;
set local lock_timeout = '5s';
set local statement_timeout = '180s';

-- Vuelve a juzgar las lecturas mudas por vocabulario y devuelve cuántas
-- volvieron a contar. Una pasada de vocabulario futura lo llama al final.
create or replace function public.spec_rejudge_name_readings_internal_v1()
returns integer
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare v_count integer;
begin
  with stale as (
    select r.fact_id,
           f.spec_definition_id,
           r.quote,
           case d.data_type
             when 'single_select' then (
               select to_jsonb(v.label)
                 from public.spec_fact_values fv
                 join public.spec_definition_values v on v.id = fv.value_id
                where fv.fact_id = f.id
                order by fv.position
                limit 1)
             when 'boolean' then to_jsonb(f.value_boolean)
             when 'number' then to_jsonb(f.value_number)
           end as value
      from public.spec_fact_readings r
      join public.spec_facts f
        on f.id = r.fact_id and f.source = 'name_reading' and f.subject_scope is null
      join public.spec_definitions d on d.id = f.spec_definition_id
     where r.vocabulary_digest
           <> public.spec_definition_vocabulary_digest_internal_v1(f.spec_definition_id)
  )
  update public.spec_fact_readings r
     set vocabulary_digest = public.spec_definition_vocabulary_digest_internal_v1(s.spec_definition_id)
    from stale s
   where r.fact_id = s.fact_id
     and s.value is not null
     and public.spec_reading_rejection_internal_v1(s.spec_definition_id, s.value, s.quote) is null;
  get diagnostics v_count = row_count;
  return v_count;
end $$;

revoke all on function public.spec_rejudge_name_readings_internal_v1()
  from public, anon, authenticated;
grant execute on function public.spec_rejudge_name_readings_internal_v1()
  to service_role;

do $$ begin
  raise notice 'Lecturas del nombre que vuelven a contar: %',
    public.spec_rejudge_name_readings_internal_v1();
end $$;

commit;
