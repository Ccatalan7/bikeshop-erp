-- Deployment status: DEPLOYED to production project xzdvtzdqjeyqxnkqprtf
-- on 2026-07-15. Batch workshop-line-identity-20260715-v2 stamped 13 more
-- deterministic line IDs across 8 invoices; 146 historical lines remain
-- unresolved. Replay returned the original receipt without further changes.
-- Refine the historical workshop invoice-line matcher without weakening the
-- one-to-one identity requirement. Legacy service rows sometimes persisted the
-- catalog UUID in both product_id and service_product_id, and repeated lines
-- can be distinguished by their preserved description/notes.
begin;

drop view if exists public.workshop_line_identity_backfill_preview;
create view public.workshop_line_identity_backfill_preview
with (security_invoker = true)
as
with invoice_lines as (
  select
    job.tenant_id,
    job.id as job_id,
    invoice.id as invoice_id,
    invoice.invoice_number,
    invoice.status as invoice_status,
    line.ordinality as line_ordinality,
    line.value as line_data,
    case
      when coalesce(line.value->>'id', '') ~*
        '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
        then (line.value->>'id')::uuid
    end as raw_item_id,
    case
      when coalesce(line.value->>'product_id', '') ~*
        '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
        then (line.value->>'product_id')::uuid
    end as raw_product_id,
    case
      when coalesce(line.value->>'job_bike_id', '') ~*
        '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
        then (line.value->>'job_bike_id')::uuid
    end as raw_job_bike_id
  from public.mechanic_jobs job
  join public.sales_invoices invoice
    on invoice.id = job.invoice_id
   and invoice.tenant_id = job.tenant_id
  cross join lateral jsonb_array_elements(coalesce(invoice.items, '[]'::jsonb))
    with ordinality as line(value, ordinality)
), resolved as (
  select
    line.*,
    product.id as product_id,
    product.name as catalog_name,
    product.product_type,
    job_bike.id as job_bike_id,
    case
      when nullif(line.line_data->>'item_type', '') in ('product', 'service', 'adhoc')
        then line.line_data->>'item_type'
      when coalesce(nullif(line.line_data->>'is_catalog_product', '')::boolean, true) = false
        then 'adhoc'
      when coalesce(nullif(line.line_data->>'is_service', '')::boolean, false)
           or product.product_type = 'service'
        then 'service'
      else 'product'
    end as item_type
  from invoice_lines line
  left join public.products product
    on product.id = line.raw_product_id
   and product.tenant_id = line.tenant_id
  left join public.mechanic_job_bikes job_bike
    on job_bike.id = line.raw_job_bike_id
   and job_bike.job_id = line.job_id
   and job_bike.tenant_id = line.tenant_id
), classified as (
  select
    resolved.*,
    stable.id as stable_item_id,
    case
      when candidate.core_match_count = 1 then candidate.core_item_id
      when candidate.description_match_count = 1
        then candidate.description_item_id
    end as candidate_item_id,
    case
      when candidate.core_match_count = 1 then 1
      when candidate.description_match_count = 1 then 1
      else coalesce(candidate.core_match_count, 0)
    end as candidate_match_count
  from resolved
  left join public.mechanic_job_items stable
    on stable.id = resolved.raw_item_id
   and stable.job_id = resolved.job_id
   and stable.tenant_id = resolved.tenant_id
  left join lateral (
    select
      (array_agg(item.id order by item.id))[1] as core_item_id,
      count(*) as core_match_count,
      (array_agg(item.id order by item.id) filter (
        where btrim(coalesce(item.notes, item.description, ''))
          = btrim(coalesce(resolved.line_data->>'description', ''))
      ))[1] as description_item_id,
      count(*) filter (
        where btrim(coalesce(item.notes, item.description, ''))
          = btrim(coalesce(resolved.line_data->>'description', ''))
      ) as description_match_count
    from public.mechanic_job_items item
    where stable.id is null
      and item.job_id = resolved.job_id
      and item.tenant_id = resolved.tenant_id
      and item.job_bike_id is not distinct from resolved.job_bike_id
      and item.item_type = resolved.item_type
      and case
        when resolved.item_type = 'product' then
          item.product_id is not distinct from resolved.product_id
        when resolved.item_type = 'service' then
          coalesce(item.service_product_id, item.product_id)
            is not distinct from resolved.product_id
        else
          item.product_id is null and item.service_product_id is null
      end
      and item.product_name = coalesce(
        nullif(resolved.line_data->>'product_name', ''),
        resolved.catalog_name,
        'Artículo'
      )
      and item.quantity = greatest(
        coalesce(nullif(resolved.line_data->>'quantity', '')::numeric, 1),
        0.01
      )
      and item.unit_price = round(
        coalesce(nullif(resolved.line_data->>'unit_price', '')::numeric, 0),
        2
      )
      and item.total_price = round(
        coalesce(
          nullif(resolved.line_data->>'line_total', '')::numeric,
          coalesce(nullif(resolved.line_data->>'quantity', '')::numeric, 1)
            * coalesce(nullif(resolved.line_data->>'unit_price', '')::numeric, 0)
            - coalesce(nullif(resolved.line_data->>'discount', '')::numeric, 0)
        ),
        2
      )
  ) candidate on true
), usage_counted as (
  select
    classified.*,
    count(*) filter (
      where stable_item_id is null
        and candidate_item_id is not null
        and candidate_match_count = 1
    ) over (partition by invoice_id, candidate_item_id) as candidate_usage_count
  from classified
)
select
  tenant_id,
  job_id,
  invoice_id,
  invoice_number,
  invoice_status,
  line_ordinality,
  line_data,
  raw_item_id,
  stable_item_id is not null as is_stable,
  candidate_item_id,
  coalesce(candidate_match_count, 0) as candidate_match_count,
  candidate_usage_count,
  stable_item_id is null
    and candidate_item_id is not null
    and candidate_match_count = 1
    and candidate_usage_count = 1 as can_backfill
from usage_counted;

grant select on public.workshop_line_identity_backfill_preview to authenticated;

comment on view public.workshop_line_identity_backfill_preview is
  'One-to-one workshop invoice-line identity preview. Accepts legacy dual-populated service product fields and uses exact preserved descriptions only to disambiguate otherwise identical candidates.';

commit;
