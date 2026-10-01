-- Read-back of 20261001200000: a job line belongs to the job's only bike.
-- Exact bodies, private grants, both triggers hooked for recovery, the review
-- registry extended by exactly two hooks, and no line left in General in a
-- one-bike job except in decided quotations (immutable).
-- Read-only; division by zero fails any missing contract.
with expected(signature, body_md5) as (values
    ('public.assign_job_line_to_only_bike()', '8b6a7912eb4960ce4fec20a9258fa4c2'),
    ('public.adopt_general_job_lines_for_only_bike()', '60672362236eba0d6db6436a97a34839'),
    ('public.workshop_restore_trigger_review_internal()', 'cf265beca2d298546eb695ad5db362fd'),
    ('public.workshop_restore_trigger_review_without_only_bike_internal()', 'c806c0d30088defac24f5780b67126c9'),
    ('public.sync_invoice_items_to_job_workshop_internal(uuid)', 'a89d958f9abf7750fd8f86e65e8bdc70')
), actual as (
  select e.*, p.oid, p.prosrc, p.proowner, p.proacl
    from expected e left join pg_proc p on p.oid = to_regprocedure(e.signature)
), triggers as (
  select t.tgname, t.tgenabled, pg_get_triggerdef(t.oid) as def, c.relname
    from pg_trigger t join pg_class c on c.oid = t.tgrelid
   where not t.tgisinternal
     and (c.relname, t.tgname::text) in (
       ('mechanic_job_items', 'trg_mechanic_job_items_only_bike'),
       ('mechanic_job_bikes', 'trg_mechanic_job_bikes_adopt_general_lines'))
), checks as (
  select
    count(*) = 5 and count(oid) = 5 as functions_exist,
    bool_and(md5(prosrc) = body_md5) as exact_function_bodies,
    bool_and(proowner = 'postgres'::regrole) as owners,
    bool_and(not exists (select 1 from aclexplode(coalesce(actual.proacl, acldefault('f', actual.proowner))) a
      where a.privilege_type = 'EXECUTE'
        and (a.grantee = 0 or a.grantee in ('anon'::regrole, 'authenticated'::regrole, 'service_role'::regrole))))
      as private_functions,
    (select count(*) = 2 and bool_and(tgenabled = 'O')
        and bool_and(position(public.workshop_restore_hook_when_internal(relname, tgname) in def) > 0)
       from triggers) as hooked_triggers,
    (select bool_or(relname = 'mechanic_job_items'
                    and def like '%BEFORE INSERT OR UPDATE ON public.mechanic_job_items FOR EACH ROW%')
        and bool_or(relname = 'mechanic_job_bikes'
                    and def like '%AFTER INSERT OR DELETE ON public.mechanic_job_bikes FOR EACH ROW%')
       from triggers) as trigger_events,
    (select count(*) = 32 from public.workshop_restore_trigger_review_internal() where review = 'hook')
      and (select count(*) = 12 from public.workshop_restore_trigger_review_internal() where review = 'keep')
      as closed_trigger_review,
    public.workshop_restore_effects_review_internal('public.mechanic_job_items'::regclass) is null
      and public.workshop_restore_effects_review_internal('public.mechanic_job_bikes'::regclass) is null
      as recovery_reviews_both_tables,
    (select count(*) = 0 from public.workshop_restore_invocations)
      and (select count(*) = 0 from public.workshop_restore_effect_packets) as no_open_packets,
    (select count(*) = 0
       from public.mechanic_job_items i
       join public.mechanic_jobs j on j.id = i.job_id and j.tenant_id = i.tenant_id
      where i.job_bike_id is null
        and not (j.workflow_kind = 'quotation' and coalesce(j.quotation_status, 'pending') <> 'pending')
        and (select count(*) from public.mechanic_job_bikes jb
              where jb.job_id = i.job_id and jb.tenant_id = i.tenant_id) = 1)
      as no_general_line_in_one_bike_jobs
  from actual
)
select checks.*,
  1 / case when functions_exist and exact_function_bodies and owners and private_functions
    and hooked_triggers and trigger_events and closed_trigger_review
    and recovery_reviews_both_tables and no_open_packets and no_general_line_in_one_bike_jobs
    then 1 else 0 end as contract_holds
from checks;
