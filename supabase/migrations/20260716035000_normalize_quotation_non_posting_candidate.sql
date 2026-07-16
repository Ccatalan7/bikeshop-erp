-- Deployment status: PENDING.
--
-- Purpose:
--   Normalize only the independently inspected PG-00468 quotation after the
--   quotation contract in 20260716030000 is installed. This data repair is
--   intentionally separate from the schema change so its writer lock lasts
--   only for the fingerprint, one-row update, evidence insert and postflight.
--
-- Safety and recovery:
--   Ordinary reads remain available. SHARE ROW EXCLUSIVE NOWAIT aborts before
--   doing anything if a workshop writer is active; it never waits behind shop
--   traffic. Zero candidates is a replay-safe success. Any candidate other
--   than the frozen production fingerprint aborts the entire transaction.
--   The repair never creates or replays invoices, payments, stock movements or
--   journals. Forward recovery must preserve its immutable evidence event.

begin;

set local lock_timeout = '750ms';
set local statement_timeout = '12s';

-- Acquire every writer lock atomically and fail immediately rather than race
-- a worker save. SELECTs remain available throughout this short transaction.
lock table
  public.mechanic_job_mode_events,
  public.mechanic_jobs,
  public.mechanic_job_items
  in share row exclusive mode nowait;

drop table if exists pg_temp.quotation_non_posting_normalization;
create temporary table quotation_non_posting_normalization
on commit drop
as
with totals as (
  select
    job.id as job_id,
    job.tenant_id,
    round(coalesce(sum(coalesce(
      item.total_price,
      item.quantity * item.unit_price,
      0
    )) filter (
      where coalesce(item.item_type, 'product') <> 'service'
    ), 0), 2) as parts_cost,
    round(coalesce(sum(coalesce(
      item.total_price,
      item.quantity * item.unit_price,
      0
    )) filter (
      where coalesce(item.item_type, 'product') = 'service'
    ), 0), 2) as labor_cost,
    count(item.id)::integer as line_count,
    md5(coalesce(
      jsonb_agg(jsonb_build_object(
        'id', item.id,
        'item_type', item.item_type,
        'product_id', item.product_id,
        'service_product_id', item.service_product_id,
        'quantity', item.quantity,
        'unit_price', item.unit_price,
        'total_price', item.total_price
      ) order by item.id) filter (where item.id is not null),
      '[]'::jsonb
    )::text) as line_contract_hash
  from public.mechanic_jobs job
  left join public.mechanic_job_items item
    on item.job_id = job.id
   and item.tenant_id = job.tenant_id
  where job.deleted_at is null
    and job.workflow_kind = 'quotation'
    and job.job_type = 'quotation'
    and job.invoice_id is null
  group by job.id, job.tenant_id
), candidates as (
  select
    job.id as job_id,
    job.tenant_id,
    job.job_number,
    jsonb_build_object(
      'quotation_status', job.quotation_status,
      'requires_approval', job.requires_approval,
      'is_invoiced', job.is_invoiced,
      'is_paid', job.is_paid,
      'parts_cost', job.parts_cost,
      'labor_cost', job.labor_cost,
      'final_cost', job.final_cost,
      'tax_amount', job.tax_amount,
      'total_cost', job.total_cost,
      'tax_treatment', job.tax_treatment
    ) as before_values,
    totals.parts_cost,
    totals.labor_cost,
    totals.line_count,
    totals.line_contract_hash,
    round(
      totals.parts_cost + totals.labor_cost
        - round(coalesce(job.discount_amount, 0), 2),
      2
    ) as expected_total
  from public.mechanic_jobs job
  join totals on totals.job_id = job.id and totals.tenant_id = job.tenant_id
  where job.quotation_status is null
     or job.requires_approval is distinct from true
     or job.is_invoiced is distinct from false
     or job.is_paid is distinct from false
     or job.parts_cost is distinct from totals.parts_cost
     or job.labor_cost is distinct from totals.labor_cost
     or job.final_cost is distinct from round(
       totals.parts_cost + totals.labor_cost
         - round(coalesce(job.discount_amount, 0), 2), 2
     )
     or job.tax_amount is distinct from 0::numeric
     or job.total_cost is distinct from round(
       totals.parts_cost + totals.labor_cost
         - round(coalesce(job.discount_amount, 0), 2), 2
     )
     or job.tax_treatment is distinct from 'no_tax'
)
select * from candidates;

do $$
begin
  if exists (
    select 1
    from quotation_non_posting_normalization candidate
    where candidate.expected_total < 0
  ) then
    raise exception 'Quotation non-posting normalization found a discount above its subtotal';
  end if;

  if exists (
    select 1
    from quotation_non_posting_normalization candidate
    where not (
      candidate.tenant_id = '5443b130-cc28-45af-a420-cd500b288890'::uuid
      and candidate.job_id = 'cb5606a2-9d91-41eb-81b9-f14db5c04347'::uuid
      and candidate.job_number = 'PG-00468'
      and candidate.before_values->>'quotation_status' is null
      and candidate.before_values->>'requires_approval' = 'false'
      and candidate.before_values->>'is_invoiced' = 'false'
      and candidate.before_values->>'is_paid' = 'false'
      and (candidate.before_values->>'parts_cost')::numeric = 74000
      and (candidate.before_values->>'labor_cost')::numeric = 16000
      and (candidate.before_values->>'final_cost')::numeric = 90000
      and (candidate.before_values->>'tax_amount')::numeric = 17100
      and (candidate.before_values->>'total_cost')::numeric = 90000
      and candidate.before_values->>'tax_treatment' = 'no_tax'
      and candidate.parts_cost = 74000
      and candidate.labor_cost = 16000
      and candidate.expected_total = 90000
      and candidate.line_count = 4
      and candidate.line_contract_hash = 'b00974ddcab33479417faa09dc569a0c'
    )
  ) then
    raise exception 'Quotation normalization candidate set changed; review the live fingerprint before applying.'
      using errcode = '23514';
  end if;
end;
$$;

select set_config('app.mechanic_job_mode_rpc', 'true', true);

update public.mechanic_jobs job
set quotation_status = coalesce(job.quotation_status, 'pending'),
    requires_approval = true,
    is_invoiced = false,
    is_paid = false,
    parts_cost = candidate.parts_cost,
    labor_cost = candidate.labor_cost,
    final_cost = candidate.expected_total,
    tax_amount = 0,
    total_cost = candidate.expected_total,
    tax_treatment = 'no_tax',
    updated_at = clock_timestamp()
from quotation_non_posting_normalization candidate
where job.id = candidate.job_id
  and job.tenant_id = candidate.tenant_id
  and job.deleted_at is null
  and job.workflow_kind = 'quotation'
  and job.job_type = 'quotation'
  and job.invoice_id is null;

select set_config('app.mechanic_job_mode_rpc', '', true);

insert into public.mechanic_job_mode_events (
  tenant_id,
  job_id,
  event_type,
  from_job_type,
  to_job_type,
  from_workflow_kind,
  to_workflow_kind,
  from_intake_kind,
  to_intake_kind,
  from_quotation_status,
  to_quotation_status,
  reason,
  actor_id,
  operation_key,
  metadata
)
select
  candidate.tenant_id,
  candidate.job_id,
  'quotation_non_posting_normalized',
  job.job_type,
  job.job_type,
  job.workflow_kind,
  job.workflow_kind,
  job.intake_kind,
  job.intake_kind,
  candidate.before_values->>'quotation_status',
  job.quotation_status,
  'Corrección no tributaria: el presupuesto no publica IVA, inventario ni contabilidad antes de convertirse.',
  null,
  'quotation-non-posting:v1:' || candidate.job_id,
  jsonb_build_object(
    'before', candidate.before_values,
    'after', jsonb_build_object(
      'quotation_status', job.quotation_status,
      'parts_cost', job.parts_cost,
      'labor_cost', job.labor_cost,
      'final_cost', job.final_cost,
      'tax_amount', job.tax_amount,
      'total_cost', job.total_cost,
      'tax_treatment', job.tax_treatment
    ),
    'invoice_id', job.invoice_id,
    'business_effects_replayed', false
  )
from quotation_non_posting_normalization candidate
join public.mechanic_jobs job
  on job.id = candidate.job_id
 and job.tenant_id = candidate.tenant_id
on conflict (tenant_id, operation_key) do nothing;

do $$
begin
  if exists (
    select 1
    from public.mechanic_jobs job
    left join lateral (
      select
        round(coalesce(sum(coalesce(
          item.total_price,
          item.quantity * item.unit_price,
          0
        )) filter (
          where coalesce(item.item_type, 'product') <> 'service'
        ), 0), 2) as parts_cost,
        round(coalesce(sum(coalesce(
          item.total_price,
          item.quantity * item.unit_price,
          0
        )) filter (
          where coalesce(item.item_type, 'product') = 'service'
        ), 0), 2) as labor_cost
      from public.mechanic_job_items item
      where item.job_id = job.id
        and item.tenant_id = job.tenant_id
    ) lines on true
    where job.deleted_at is null
      and job.workflow_kind = 'quotation'
      and (
        job.invoice_id is not null
        or job.quotation_status is null
        or job.requires_approval is distinct from true
        or job.is_invoiced is distinct from false
        or job.is_paid is distinct from false
        or job.parts_cost is distinct from lines.parts_cost
        or job.labor_cost is distinct from lines.labor_cost
        or coalesce(job.discount_amount, 0) < 0
        or coalesce(job.discount_amount, 0)
             > lines.parts_cost + lines.labor_cost
        or job.final_cost is distinct from round(
          lines.parts_cost + lines.labor_cost
            - round(coalesce(job.discount_amount, 0), 2),
          2
        )
        or job.tax_amount is distinct from 0::numeric
        or job.total_cost is distinct from round(
          lines.parts_cost + lines.labor_cost
            - round(coalesce(job.discount_amount, 0), 2),
          2
        )
        or job.tax_treatment is distinct from 'no_tax'
        or exists (
          select 1
          from public.stock_movements movement
          where movement.tenant_id = job.tenant_id
            and movement.source_document_id = job.id
        )
        or exists (
          select 1
          from public.journal_entries entry
          where entry.tenant_id = job.tenant_id
            and entry.source_document_id = job.id
        )
      )
  ) then
    raise exception 'Quotation normalization postflight failed';
  end if;

  if exists (
    select 1
    from quotation_non_posting_normalization candidate
    left join public.mechanic_job_mode_events event
      on event.tenant_id = candidate.tenant_id
     and event.job_id = candidate.job_id
     and event.operation_key = 'quotation-non-posting:v1:' || candidate.job_id
     and event.event_type = 'quotation_non_posting_normalized'
    where event.id is null
       or coalesce(
            (event.metadata->>'business_effects_replayed')::boolean,
            true
          )
  ) then
    raise exception 'Quotation normalization evidence postflight failed';
  end if;
end;
$$;

commit;
