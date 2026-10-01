-- Read-back of 20261002090000: «Fuente del dato» (`spec_evidence_source`) is
-- no longer a prerequisite of any field in any template. Before the deploy it
-- gated fields in 57 of the 107 active templates (2026-10-01). The other
-- prerequisites (a measurement and its reference, a part and its
-- presentation) stay: 45 edges in 20 templates on that day. A trigger rejects
-- any template that publishes the edge again. No stored value changes.
-- Read-only; division by zero fails it.
with edges as (
  select t.id, dep.value as parent
    from public.spec_templates t
   cross join lateral jsonb_each(
           case when jsonb_typeof(t.form_contract->'prerequisites') = 'object'
                then t.form_contract->'prerequisites' else '{}'::jsonb end) entry
   cross join lateral jsonb_array_elements_text(
           case when jsonb_typeof(entry.value) = 'array'
                then entry.value else '[]'::jsonb end) dep(value)
   where t.is_active
), checks as (
  select
    (select count(*) = 0 from edges where parent = 'spec_evidence_source')
      as source_gates_nothing,
    (select count(*) from edges) as remaining_prerequisite_edges,
    (select count(*) = 0 from public.spec_templates
      where is_active
        and jsonb_typeof(form_contract->'prerequisites') is distinct from 'object')
      as every_contract_keeps_its_prerequisites_map,
    exists (select 1 from pg_trigger
             where tgrelid = 'public.spec_templates'::regclass
               and tgname = 'spec_template_source_not_prerequisite_guard'
               and tgenabled = 'O')
      as future_templates_are_guarded
)
select checks.*,
  1 / case when source_gates_nothing and every_contract_keeps_its_prerequisites_map
                and future_templates_are_guarded
    then 1 else 0 end as contract_holds
from checks;
