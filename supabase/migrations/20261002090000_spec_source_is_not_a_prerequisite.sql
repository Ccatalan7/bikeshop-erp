-- «Fuente del dato» no habilita ni bloquea otros datos de la ficha (dueño,
-- 2026-10-01: «what the fuck it's that thing of "se desbloquea cuando llenes
-- la fuente del dato"?»).
--
-- `spec_evidence_source` es una nota privada (envase, manual o URL que se
-- revisó). En 57 de las 107 fichas activas figuraba como prerrequisito de
-- casi todos sus campos —en la cadena, de las velocidades, el ancho, los
-- eslabones y el sentido de montaje—, y es un texto que el formulario muestra
-- al final. Así, el editor deshabilitaba los datos de arriba hasta llenar una
-- nota de abajo, y los valores leídos del nombre (6 velocidades, 3/32, 116
-- eslabones) quedaban congelados con «falta confirmar Fuente del dato».
--
-- La arquitectura de fichas ya dice otra cosa: valor, procedencia y estado son
-- dimensiones distintas (§4.2). Cada hecho guarda su procedencia en
-- `spec_facts.source` (lectura del nombre, proveedor, investigación,
-- importación, mecánico) y su confirmación; lo que escribe el operador queda
-- como `mechanic`. La nota sigue existiendo y sigue privada, como respaldo
-- opcional; sólo deja de ser condición de los demás datos. Los prerrequisitos
-- reales —una medida que necesita su referencia de medición, una pieza que
-- depende de su presentación— se conservan.
--
-- Sólo cambia el contrato de las fichas; ningún valor guardado. El disparador
-- de revisión sube `contract_version` de cada ficha que cambia, así que un
-- editor abierto con la versión anterior pide recargar al guardar.
--
-- La arista venía de los compiladores de catálogos de investigación
-- (`scripts/inventory/compile_*.py`, 2026-09-07→16), que la ponen delante de
-- casi cada campo. Por eso la regla queda también en la base: una ficha que
-- vuelva a publicarla se rechaza con el motivo, en vez de bloquear otra vez el
-- editor en silencio.
begin;
set local lock_timeout = '5s';
set local statement_timeout = '60s';

update public.spec_templates t
   set form_contract = jsonb_set(
         t.form_contract,
         '{prerequisites}',
         coalesce((
           select jsonb_object_agg(field.key, field.deps)
             from (
               select entry.key,
                      case when jsonb_typeof(entry.value) = 'array' then
                        (select jsonb_agg(dep.value order by dep.ordinality)
                           from jsonb_array_elements(entry.value)
                                with ordinality as dep(value, ordinality)
                          where dep.value <> to_jsonb('spec_evidence_source'::text))
                      else entry.value end as deps
                 from jsonb_each(t.form_contract->'prerequisites') entry
             ) field
            where field.deps is not null
         ), '{}'::jsonb)),
       updated_at = now()
 where jsonb_typeof(t.form_contract->'prerequisites') = 'object'
   and exists (
         select 1
           from jsonb_each(t.form_contract->'prerequisites') entry
          cross join lateral jsonb_array_elements_text(
                  case when jsonb_typeof(entry.value) = 'array'
                       then entry.value else '[]'::jsonb end) dep(value)
          where dep.value = 'spec_evidence_source');

create or replace function public.spec_template_source_not_prerequisite_guard_internal_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
begin
  if jsonb_typeof(new.form_contract->'prerequisites') = 'object' and exists (
       select 1
         from jsonb_each(new.form_contract->'prerequisites') entry
        cross join lateral jsonb_array_elements_text(
                case when jsonb_typeof(entry.value) = 'array'
                     then entry.value else '[]'::jsonb end) dep(value)
        where dep.value = 'spec_evidence_source') then
    raise exception 'La fuente del dato es una nota privada: no puede habilitar ni bloquear otro campo de la ficha.'
      using errcode = '23514';
  end if;
  return new;
end $$;

revoke all on function public.spec_template_source_not_prerequisite_guard_internal_v1()
  from public, anon, authenticated;
grant execute on function public.spec_template_source_not_prerequisite_guard_internal_v1()
  to service_role;

drop trigger if exists spec_template_source_not_prerequisite_guard on public.spec_templates;
create trigger spec_template_source_not_prerequisite_guard
  before insert or update of form_contract on public.spec_templates
  for each row execute function public.spec_template_source_not_prerequisite_guard_internal_v1();

commit;
