-- Read-only compatibility gate for the workshop payment snapshot guard.
--
-- This deliberately reproduces the normalized projections from migration 070
-- without installing any function or trigger. It is safe to run before the
-- migration on production and emits aggregate counts only (no customer data).
with job_snapshots as (
  select
    job.id as job_id,
    job.tenant_id,
    job.invoice_id,
    jsonb_build_object(
      'customer_id', job.customer_id::text,
      'discount_amount', round(coalesce(job.discount_amount, 0), 2),
      'total', round(
        coalesce((
          select sum(coalesce(item.total_price, 0))
          from public.mechanic_job_items item
          where item.job_id = job.id
            and item.tenant_id = job.tenant_id
        ), 0) - coalesce(job.discount_amount, 0),
        2
      ),
      'items', coalesce((
        select jsonb_agg(line.snapshot order by line.snapshot::text)
        from (
          select jsonb_build_object(
            'product_id', coalesce(
              case
                when item.item_type = 'service'
                  then item.service_product_id::text
                when item.item_type = 'product'
                  then item.product_id::text
              end,
              ''
            ),
            'product_name', item.product_name,
            'product_sku', coalesce(item.product_sku, ''),
            'description', coalesce(item.notes, item.description, ''),
            'item_type', item.item_type,
            'quantity', item.quantity,
            'unit_price', item.unit_price,
            'line_total', coalesce(
              item.total_price,
              item.quantity * item.unit_price,
              0
            ),
            'service_configuration_data', item.service_configuration_data,
            'system_key', item.system_key,
            'component_slot_key', item.component_slot_key,
            'location_key', coalesce(item.location_key, 'none'),
            'intervention_type', item.intervention_type,
            'creates_lifecycle', coalesce(item.creates_lifecycle, false)
          ) as snapshot
          from public.mechanic_job_items item
          where item.job_id = job.id
            and item.tenant_id = job.tenant_id
        ) line
      ), '[]'::jsonb)
    ) as snapshot
  from public.mechanic_jobs job
  where job.deleted_at is null
    and job.invoice_id is not null
),
invoice_snapshots as (
  select
    invoice.id as invoice_id,
    coalesce(invoice.total, 0) - coalesce(invoice.paid_amount, 0) > 0.01
      as has_remaining_balance,
    lower(coalesce(invoice.status, '')) in ('paid', 'pagado', 'pagada')
      or coalesce(invoice.paid_amount, 0) > 0
      or exists (
        select 1
        from public.sales_payments payment
        where payment.tenant_id = invoice.tenant_id
          and payment.invoice_id = invoice.id
          and payment.deleted_at is null
          and coalesce(payment.amount, 0) > 0
      ) as has_payment_evidence,
    jsonb_build_object(
      'customer_id', invoice.customer_id::text,
      'discount_amount', round(coalesce(invoice.discount_amount, 0), 2),
      'total', round(coalesce(invoice.total, 0), 2),
      'items', coalesce((
        select jsonb_agg(line.snapshot order by line.snapshot::text)
        from (
          select jsonb_build_object(
            'product_id', coalesce(invoice_item.value->>'product_id', ''),
            'product_name', coalesce(
              nullif(invoice_item.value->>'product_name', ''),
              product.name,
              'Artículo'
            ),
            'product_sku', coalesce(
              nullif(invoice_item.value->>'product_sku', ''),
              product.sku,
              ''
            ),
            'description', coalesce(
              invoice_item.value->>'description',
              invoice_item.value->>'notes',
              ''
            ),
            'item_type', case
              when nullif(invoice_item.value->>'item_type', '') in (
                'product', 'service', 'adhoc'
              ) then invoice_item.value->>'item_type'
              when coalesce(
                nullif(
                  invoice_item.value->>'is_catalog_product',
                  ''
                )::boolean,
                true
              ) = false then 'adhoc'
              when coalesce(
                nullif(invoice_item.value->>'is_service', '')::boolean,
                false
              ) or product.product_type = 'service' then 'service'
              else 'product'
            end,
            'quantity', coalesce(
              nullif(invoice_item.value->>'quantity', '')::numeric,
              1
            ),
            'unit_price', coalesce(
              nullif(invoice_item.value->>'unit_price', '')::numeric,
              0
            ),
            'line_total', coalesce(
              nullif(invoice_item.value->>'line_total', '')::numeric,
              coalesce(
                nullif(invoice_item.value->>'quantity', '')::numeric,
                1
              ) * coalesce(
                nullif(invoice_item.value->>'unit_price', '')::numeric,
                0
              ) - coalesce(
                nullif(invoice_item.value->>'discount', '')::numeric,
                0
              )
            ),
            'service_configuration_data',
              invoice_item.value->'service_configuration_data',
            'system_key', nullif(invoice_item.value->>'system_key', ''),
            'component_slot_key',
              nullif(invoice_item.value->>'component_slot_key', ''),
            'location_key', coalesce(
              nullif(invoice_item.value->>'location_key', ''),
              'none'
            ),
            'intervention_type',
              nullif(invoice_item.value->>'intervention_type', ''),
            'creates_lifecycle', coalesce(
              nullif(
                invoice_item.value->>'creates_lifecycle',
                ''
              )::boolean,
              false
            )
          ) as snapshot
          from jsonb_array_elements(coalesce(invoice.items, '[]'::jsonb))
            invoice_item(value)
          cross join lateral (
            select case
              when coalesce(invoice_item.value->>'product_id', '') ~*
                '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
                then (invoice_item.value->>'product_id')::uuid
            /* close UUID parser */ end as product_id
          ) parsed
          left join public.products product
            on product.id = parsed.product_id
           and product.tenant_id = invoice.tenant_id
        ) line
      ), '[]'::jsonb)
    ) as snapshot
  from public.sales_invoices invoice
),
comparison as (
  select
    invoice.has_payment_evidence,
    invoice.has_remaining_balance,
    job.snapshot is distinct from invoice.snapshot as differs
  from job_snapshots job
  join invoice_snapshots invoice on invoice.invoice_id = job.invoice_id
)
select
  count(*) as linked_jobs,
  count(*) filter (where differs) as incompatible_snapshots,
  count(*) filter (
    where differs and not has_payment_evidence
  ) as open_incompatible_snapshots,
  count(*) filter (
    where differs and has_payment_evidence
  ) as historical_paid_incompatible_snapshots,
  count(*) filter (
    where differs and has_remaining_balance
  ) as payable_incompatible_snapshots
from comparison;
