-- Una nota escrita no habilita ni bloquea otros datos (20261002090000).
--
-- «Fuente del dato» era prerrequisito de casi todos los campos en 57 fichas, y
-- en otras ocho un texto libre sobre cómo se midió bloqueaba la medida misma:
-- el editor deshabilitaba las velocidades de una cadena o el ERD de un aro
-- hasta escribir una nota. Un texto libre no se puede comprobar; cada hecho
-- guarda su procedencia en `spec_facts.source`. Esta prueba fija la regla
-- también para las fichas que publiquen catálogos futuros.
begin;

select no_plan();

select is(
  (select count(*)::integer
     from public.spec_templates t
    cross join lateral jsonb_each(
            case when jsonb_typeof(t.form_contract->'prerequisites') = 'object'
                 then t.form_contract->'prerequisites' else '{}'::jsonb end) entry
    cross join lateral jsonb_array_elements_text(
            case when jsonb_typeof(entry.value) = 'array'
                 then entry.value else '[]'::jsonb end) dep(value)
    where dep.value = any(public.spec_template_note_keys_internal_v1(t.id))),
  0,
  'ninguna ficha espera una nota escrita para habilitar otro campo');

-- Los compiladores de catálogos ponían la fuente delante de casi cada campo:
-- volver a publicarla se rechaza con el nombre del campo.
set constraints all immediate;
select throws_like(
  $$update public.spec_templates
       set form_contract = jsonb_set(form_contract, '{prerequisites,chain_speeds}',
                                     '["spec_evidence_source"]'::jsonb)
     where key = 'chain' and tenant_id is null and is_active$$,
  '%es un texto libre: no puede habilitar ni bloquear otro campo de la ficha.',
  'una ficha que vuelve a poner la fuente como prerrequisito se rechaza');

-- Lo mismo para cualquier campo de texto libre de la ficha, no sólo la fuente.
select throws_like(
  $$update public.spec_templates
       set form_contract = jsonb_set(form_contract, '{prerequisites,tire_width_mm}',
                                     '["tire_etrto"]'::jsonb)
     where key = 'tire' and tenant_id is null and is_active$$,
  '«%» es un texto libre:%',
  'un texto libre de la ficha tampoco puede ser prerrequisito');

-- La fuente es opcional en todas las fichas, y volver a exigirla se rechaza.
select is(
  (select count(*)::integer from public.spec_templates
    where form_contract->'roles' ? 'spec_evidence_source'
      and form_contract->'required_when'->'spec_evidence_source'->>'kind' <> 'never'),
  0,
  'ninguna ficha exige la fuente del dato');
select throws_like(
  $$update public.spec_templates
       set form_contract = jsonb_set(form_contract, '{required_when}',
             coalesce(form_contract->'required_when', '{}'::jsonb)
             || '{"spec_evidence_source": {"kind": "always"}}'::jsonb)
     where key = 'chain' and tenant_id is null and is_active$$,
  'La fuente del dato es una nota opcional: no puede ser obligatoria.',
  'volver a exigir la fuente se rechaza');

-- Un prerrequisito tipado sigue aceptándose: la guardia mira sólo las notas.
select lives_ok(
  $$update public.spec_templates
       set form_contract = form_contract
     where jsonb_typeof(form_contract->'prerequisites') = 'object'
       and form_contract->'prerequisites' <> '{}'::jsonb$$,
  'las fichas con prerrequisitos tipados se siguen guardando');

select * from finish();
rollback;
