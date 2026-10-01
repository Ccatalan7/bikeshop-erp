-- Read-back of 20261001200000: the invoice-to-job sync continues the same job
-- line (by id, by content, or by product), keeps its bike or General, and
-- stays private. The body before the deploy was 586c672c1e77d65be585e15a065917d5.
-- No new triggers. Bike work (services, «Componentes» and «Servicio» items)
-- left in General of a one-bike job moved to its bike (328 lines in 122 jobs
-- measured on 2026-10-01); accessories stay in General, and a decided
-- quotation is immutable. Read-only; division by zero fails it.
with actual as (
  select p.oid, p.prosrc, p.prosecdef, p.proconfig, p.proowner, p.proacl
    from pg_proc p
   where p.oid = to_regprocedure('public.sync_invoice_items_to_job_workshop_internal(uuid)')
), checks as (
  select
    count(oid) = 1 as function_exists,
    bool_and(md5(prosrc) = 'a89d958f9abf7750fd8f86e65e8bdc70') as exact_body,
    bool_and(prosecdef and proconfig @> array['search_path=public']) as definer_with_fixed_path,
    bool_and(proowner = 'postgres'::regrole) as owner,
    bool_and(not exists (select 1 from aclexplode(coalesce(actual.proacl, acldefault('f', actual.proowner))) a
      where a.privilege_type = 'EXECUTE'
        and (a.grantee = 0 or a.grantee in ('anon'::regrole, 'authenticated'::regrole, 'service_role'::regrole))))
      as private_function,
    (select count(*) = 0 from pg_trigger t
      where not t.tgisinternal
        and t.tgname in ('trg_mechanic_job_items_only_bike',
                         'trg_mechanic_job_bikes_adopt_general_lines'))
      as no_forced_bike_rule,
    (select count(*) = 0
       from public.mechanic_job_items i
       join public.mechanic_jobs j on j.id = i.job_id and j.tenant_id = i.tenant_id
      where i.job_bike_id is null
        and not (j.workflow_kind = 'quotation' and coalesce(j.quotation_status, 'pending') <> 'pending')
        and (select count(*) from public.mechanic_job_bikes jb
              where jb.job_id = i.job_id and jb.tenant_id = i.tenant_id) = 1
        and (i.item_type = 'service' or exists (
              select 1 from public.products p
                join public.product_categories c on c.id = p.category_id and c.tenant_id = p.tenant_id
               where p.id = coalesce(i.product_id, i.service_product_id) and p.tenant_id = i.tenant_id
                 and split_part(c.full_path, ' / ', 1) in ('Componentes', 'Servicio'))))
      as no_bike_work_left_in_general
  from actual
)
select checks.*,
  1 / case when function_exists and exact_body and definer_with_fixed_path
    and owner and private_function and no_forced_bike_rule
    and no_bike_work_left_in_general
    then 1 else 0 end as contract_holds
from checks;
