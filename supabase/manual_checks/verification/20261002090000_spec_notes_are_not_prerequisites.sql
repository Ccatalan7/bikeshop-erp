-- Read-back of 20261002090000: no written note gates another field. Before
-- the deploy, «Fuente del dato» (`spec_evidence_source`) gated fields in 57 of
-- the 107 active templates, and a free-text measuring note gated its own
-- measurement in eight more, and six templates required the source
-- (2026-10-01). The typed prerequisites (a brake
-- presentation, a connector type, a thread) stay: 30 edges in 11 templates
-- that day, informational here. A commit-time trigger on templates and their fields
-- rejects a template that publishes a note as a prerequisite again. No stored
-- value changes. Read-only; division by zero fails it.
with edges as (
  select t.id, dep.value as parent,
         dep.value = any(public.spec_template_note_keys_internal_v1(t.id)) as is_note
    from public.spec_templates t
   cross join lateral jsonb_each(
           case when jsonb_typeof(t.form_contract->'prerequisites') = 'object'
                then t.form_contract->'prerequisites' else '{}'::jsonb end) entry
   cross join lateral jsonb_array_elements_text(
           case when jsonb_typeof(entry.value) = 'array'
                then entry.value else '[]'::jsonb end) dep(value)
), checks as (
  select
    (select count(*) = 0 from edges where is_note) as no_note_gates_a_field,
    (select count(*) from edges) as remaining_prerequisite_edges,
    (select count(*) = 0 from public.spec_templates
      where is_active
        and jsonb_typeof(form_contract->'prerequisites') is distinct from 'object')
      as every_contract_keeps_its_prerequisites_map,
    (select count(*) = 0 from public.spec_templates
      where form_contract->'roles' ? 'spec_evidence_source'
        and form_contract->'required_when'->'spec_evidence_source'->>'kind' <> 'never')
      as the_source_is_optional,
    (select count(*) = 2 from pg_trigger
      where tgname = 'spec_template_note_prerequisite_guard'
        and tgrelid in ('public.spec_templates'::regclass,
                        'public.spec_template_fields'::regclass)
        and tgenabled = 'O' and tgdeferrable and tginitdeferred)
      as future_templates_are_guarded
)
select checks.*,
  1 / case when no_note_gates_a_field and every_contract_keeps_its_prerequisites_map
                and the_source_is_optional and future_templates_are_guarded
    then 1 else 0 end as contract_holds
from checks;
