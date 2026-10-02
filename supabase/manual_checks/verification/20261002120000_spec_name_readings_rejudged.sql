-- Read-back of 20261002120000: no root name reading stays mute while the
-- current judge accepts its quote. The ones that remain mute are the ones the
-- judge rejects (24 booleans on 2026-10-01), informational here.
-- Read-only; division by zero fails it.
with stale as (
  select f.spec_definition_id, r.quote, d.data_type,
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
), judged as (
  select public.spec_reading_rejection_internal_v1(spec_definition_id, value, quote) as rejection
    from stale where value is not null
)
select count(*) filter (where rejection is null) as mute_but_accepted,
       count(*) filter (where rejection is not null) as mute_and_rejected,
       1 / case when count(*) filter (where rejection is null) = 0 then 1 else 0 end
         as name_readings_rejudged_ok
  from judged;
