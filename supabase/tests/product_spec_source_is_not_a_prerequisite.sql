-- «Fuente del dato» no habilita ni bloquea otros datos (20261002090000).
--
-- Era prerrequisito de casi todos los campos en 57 fichas: el editor
-- deshabilitaba las velocidades, el ancho o los eslabones de una cadena hasta
-- llenar una nota privada que se pide al final, y los valores leídos del
-- nombre quedaban congelados. Cada hecho guarda su procedencia en
-- `spec_facts.source`; la nota es un respaldo opcional. Esta prueba fija la
-- regla también para las fichas que publiquen catálogos futuros.
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
    where dep.value = 'spec_evidence_source'),
  0,
  'ninguna ficha espera la fuente del dato para habilitar otro campo');

-- Los compiladores de catálogos ponían la arista delante de casi cada campo:
-- volver a publicarla se rechaza con el motivo.
select throws_ok(
  $$update public.spec_templates
       set form_contract = jsonb_set(form_contract, '{prerequisites,spec_probe_field}',
                                     '["spec_evidence_source"]'::jsonb)
     where id = (select id from public.spec_templates
                  where jsonb_typeof(form_contract->'prerequisites') = 'object'
                  order by key limit 1)$$,
  '23514',
  'La fuente del dato es una nota privada: no puede habilitar ni bloquear otro campo de la ficha.',
  'una ficha que vuelve a poner la fuente como prerrequisito se rechaza');

-- Un prerrequisito real sigue aceptándose: la guardia mira sólo la nota.
select lives_ok(
  $$update public.spec_templates
       set form_contract = form_contract
     where id = (select id from public.spec_templates
                  where jsonb_typeof(form_contract->'prerequisites') = 'object'
                    and form_contract->'prerequisites' <> '{}'::jsonb
                  order by key limit 1)$$,
  'una ficha con prerrequisitos reales se sigue guardando');

select * from finish();
rollback;
