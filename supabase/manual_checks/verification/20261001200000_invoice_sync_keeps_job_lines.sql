-- Read-back of 20261001200000: the invoice-to-job sync continues the same job
-- line (by id, by content, or by product), keeps its bike or General, and
-- stays private. The body before the deploy was 586c672c1e77d65be585e15a065917d5.
-- No new triggers. Bike work (services, «Componentes» and «Servicio» items)
-- left in General of a one-bike job moved to its bike (328 lines in 122 jobs
-- measured on 2026-10-01); accessories stay in General, and a decided
-- quotation is immutable. That repair runs once, when it replaces the old
-- sync, so the count of such lines left in General is informative, not part
-- of the contract: after the fix a component in General can be a purchase
-- apart. Every bike subtotal and every invoiced job's split follow the one
-- cost rule (20261001190000), an invoiced job shows its invoice's total and
-- IVA, and an unbilled service job's total is its lines less its discount.
-- Read-only; division by zero fails it.
with actual as (
  select p.oid, p.prosrc, p.prosecdef, p.proconfig, p.proowner, p.proacl
    from pg_proc p
   where p.oid = to_regprocedure('public.sync_invoice_items_to_job_workshop_internal(uuid)')
), checks as (
  select
    count(oid) = 1 as function_exists,
    bool_and(md5(prosrc) = '2aa84b351c96dae2186f88bde92cf2c8') as exact_body,
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
    (select count(*)
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
      as bike_work_left_in_general,
    (select count(*) = 0 from (
       select jb.parts_cost, jb.labor_cost, jb.subtotal,
              coalesce(sum(i.total_price) filter (
                where public.job_line_cost_bucket(i.item_type) = 'parts'), 0) as p,
              coalesce(sum(i.total_price) filter (
                where public.job_line_cost_bucket(i.item_type) = 'labor'), 0) as l
         from public.mechanic_job_bikes jb
         join public.mechanic_jobs j on j.id = jb.job_id and j.tenant_id = jb.tenant_id
         left join public.mechanic_job_items i
           on i.job_bike_id = jb.id and i.tenant_id = jb.tenant_id
        where not (j.workflow_kind = 'quotation' and j.intake_kind = 'bike'
                   and coalesce(j.quotation_status, 'pending') <> 'pending')
        group by jb.id
     ) t where (t.parts_cost, t.labor_cost, t.subtotal) is distinct from (t.p, t.l, t.p + t.l))
      as bikes_add_up,
    (select count(*) = 0 from (
       select j.parts_cost, j.labor_cost,
              round(coalesce(sum(i.total_price) filter (
                where public.job_line_cost_bucket(i.item_type) = 'parts'), 0), 2) as p,
              round(coalesce(sum(i.total_price) filter (
                where public.job_line_cost_bucket(i.item_type) = 'labor'), 0), 2) as l
         from public.mechanic_jobs j
         left join public.mechanic_job_items i on i.job_id = j.id and i.tenant_id = j.tenant_id
        where j.invoice_id is not null
        group by j.id
     ) t where (round(t.parts_cost, 2), round(t.labor_cost, 2)) is distinct from (t.p, t.l))
      as invoiced_splits_follow_rule,
    (select count(*) = 0 from public.mechanic_jobs j
       join public.sales_invoices inv on inv.id = j.invoice_id and inv.tenant_id = j.tenant_id
      where (j.total_cost, j.final_cost, j.tax_amount, j.tax_treatment)
            is distinct from (inv.total, inv.total, inv.iva_amount, inv.tax_treatment))
      as invoiced_jobs_show_their_invoice,
    (select count(*) = 0 from (
       select j.parts_cost, j.labor_cost, j.final_cost, j.total_cost, j.tax_amount,
              j.tax_treatment, coalesce(j.discount_amount, 0) as discount,
              round(coalesce(sum(coalesce(i.total_price, i.quantity * i.unit_price, 0)) filter (
                where public.job_line_cost_bucket(i.item_type) = 'parts'), 0), 2) as p,
              round(coalesce(sum(coalesce(i.total_price, i.quantity * i.unit_price, 0)) filter (
                where public.job_line_cost_bucket(i.item_type) = 'labor'), 0), 2) as l
         from public.mechanic_jobs j
         left join public.mechanic_job_items i on i.job_id = j.id and i.tenant_id = j.tenant_id
        where j.invoice_id is null
          and j.workflow_kind is distinct from 'quotation'
        group by j.id
     ) t where (round(t.parts_cost, 2), round(t.labor_cost, 2), round(t.final_cost, 2),
                round(t.total_cost, 2), coalesce(t.tax_amount, 0), t.tax_treatment)
               is distinct from (t.p, t.l, round(t.p + t.l - least(t.discount, t.p + t.l), 2),
                                 round(t.p + t.l - least(t.discount, t.p + t.l), 2), 0, 'no_tax'))
      as unbilled_service_totals_follow_rule
  from actual
)
select checks.*,
  1 / case when function_exists and exact_body and definer_with_fixed_path
    and owner and private_function and no_forced_bike_rule and bikes_add_up
    and invoiced_splits_follow_rule and invoiced_jobs_show_their_invoice
    and unbilled_service_totals_follow_rule
    then 1 else 0 end as contract_holds
from checks;
