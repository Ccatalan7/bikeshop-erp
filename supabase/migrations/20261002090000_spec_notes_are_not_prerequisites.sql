-- Una nota escrita no habilita ni bloquea otros datos de la ficha (dueño,
-- 2026-10-01: «what the fuck it's that thing of "se desbloquea cuando llenes
-- la fuente del dato"?»).
--
-- `spec_evidence_source` («Fuente del dato») es una nota privada: el envase,
-- manual o URL que se revisó. En 57 de las 107 fichas activas figuraba como
-- prerrequisito de casi todos sus campos —en la cadena, de las velocidades, el
-- ancho, los eslabones y el sentido de montaje—, y es un texto que el
-- formulario muestra al final. Así, el editor deshabilitaba los datos de arriba
-- hasta llenar una nota de abajo, y los valores leídos del nombre (6
-- velocidades, 3/32, 116 eslabones) quedaban congelados.
--
-- La auditoría de las 107 fichas encontró la misma forma en otras ocho: un
-- texto libre que describe cómo se midió («Cómo se midió el diámetro efectivo
-- del aro», «Dónde se mide el diámetro del eje», «Documento OEM de cotas»)
-- bloqueaba la medida misma. Un texto libre no se puede comprobar: como
-- condición sólo obliga a escribir algo para seguir. La regla es una: un campo
-- de texto libre no es prerrequisito de otro campo. Y la fuente, que en seis
-- fichas (maza, aro, rayo, juego de dirección, adaptador de poste y conjunto
-- de piezas) era obligatoria, pasa a ser lo que es: opcional.
--
-- La arquitectura de fichas ya separa valor, procedencia y estado (§4.2): cada
-- hecho guarda su procedencia en `spec_facts.source`. Las notas siguen
-- existiendo, privadas y opcionales, al lado del dato que explican. Los
-- prerrequisitos reales —una decisión tipada como la presentación de un freno,
-- el tipo de conector o la rosca de un perno— se conservan.
--
-- Sólo cambia el contrato de las fichas; ningún valor guardado. El disparador
-- de revisión sube `contract_version` de cada ficha que cambia, así que un
-- editor abierto con la versión anterior pide recargar al guardar.
--
-- Las aristas venían de los compiladores de catálogos de investigación
-- (`scripts/inventory/compile_*.py`, 2026-09-07→16). Por eso la regla queda
-- también en la base: una ficha que vuelva a publicar un texto libre como
-- prerrequisito, o la fuente como obligatoria, se rechaza con el nombre del
-- campo al confirmar la transacción, en vez de bloquear otra vez el editor en
-- silencio. El validador común de esos compiladores
-- (`validate_contract`) rechaza lo mismo antes de generar el SQL.
begin;
set local lock_timeout = '5s';
set local statement_timeout = '60s';

create or replace function public.spec_template_note_keys_internal_v1(p_template_id uuid)
returns text[]
language sql
stable
set search_path = pg_catalog, public, pg_temp
as $$
  select array['spec_evidence_source'] || coalesce(array_agg(d.key), '{}'::text[])
    from public.spec_template_fields f
    join public.spec_definitions d on d.id = f.spec_definition_id
   where f.template_id = p_template_id
     and d.data_type = 'text'
$$;

revoke all on function public.spec_template_note_keys_internal_v1(uuid)
  from public, anon, authenticated;
grant execute on function public.spec_template_note_keys_internal_v1(uuid)
  to service_role;

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
                          where not (dep.value #>> '{}') = any(
                                  public.spec_template_note_keys_internal_v1(t.id)))
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
          where dep.value = any(public.spec_template_note_keys_internal_v1(t.id)));

update public.spec_templates t
   set form_contract = jsonb_set(t.form_contract, '{required_when,spec_evidence_source}',
                                 '{"kind": "never"}'::jsonb),
       updated_at = now()
 where t.form_contract->'roles' ? 'spec_evidence_source'
   and t.form_contract->'required_when'->'spec_evidence_source'->>'kind' <> 'never';

create or replace function public.spec_template_note_prerequisite_guard_internal_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_template_id uuid;
  v_label text;
begin
  -- Each table names the template differently; a CASE would resolve both.
  if tg_table_name = 'spec_templates' then
    v_template_id := new.id;
  else
    v_template_id := new.template_id;
  end if;
  select coalesce(t.form_contract->'labels'->>dep.value,
                  (select d.label
                     from public.spec_template_fields f
                     join public.spec_definitions d on d.id = f.spec_definition_id
                    where f.template_id = t.id and d.key = dep.value
                    limit 1),
                  dep.value)
    into v_label
    from public.spec_templates t
   cross join lateral jsonb_each(
           case when jsonb_typeof(t.form_contract->'prerequisites') = 'object'
                then t.form_contract->'prerequisites' else '{}'::jsonb end) entry
   cross join lateral jsonb_array_elements_text(
           case when jsonb_typeof(entry.value) = 'array'
                then entry.value else '[]'::jsonb end) dep(value)
   where t.id = v_template_id
     and dep.value = any(public.spec_template_note_keys_internal_v1(t.id))
   limit 1;
  if v_label is not null then
    raise exception '«%» es un texto libre: no puede habilitar ni bloquear otro campo de la ficha.', v_label
      using errcode = '23514';
  end if;
  if exists (select 1 from public.spec_templates t
              where t.id = v_template_id
                and t.form_contract->'roles' ? 'spec_evidence_source'
                and t.form_contract->'required_when'->'spec_evidence_source'->>'kind' <> 'never') then
    raise exception 'La fuente del dato es una nota opcional: no puede ser obligatoria.'
      using errcode = '23514';
  end if;
  return null;
end $$;

revoke all on function public.spec_template_note_prerequisite_guard_internal_v1()
  from public, anon, authenticated;
grant execute on function public.spec_template_note_prerequisite_guard_internal_v1()
  to service_role;

-- Al confirmar: una ficha nueva publica primero el contrato y después sus
-- campos, así que sólo entonces se sabe qué prerrequisito es un texto.
drop trigger if exists spec_template_note_prerequisite_guard on public.spec_templates;
create constraint trigger spec_template_note_prerequisite_guard
  after insert or update on public.spec_templates
  deferrable initially deferred
  for each row execute function public.spec_template_note_prerequisite_guard_internal_v1();

drop trigger if exists spec_template_note_prerequisite_guard on public.spec_template_fields;
create constraint trigger spec_template_note_prerequisite_guard
  after insert or update on public.spec_template_fields
  deferrable initially deferred
  for each row execute function public.spec_template_note_prerequisite_guard_internal_v1();

commit;
