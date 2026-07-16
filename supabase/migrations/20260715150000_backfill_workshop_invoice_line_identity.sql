-- Deployment status: DEPLOYED to production project xzdvtzdqjeyqxnkqprtf
-- on 2026-07-15. Batch workshop-line-identity-20260715-v1 repaired
-- 1,023 exact one-to-one line identities and 398 legacy references; 159
-- non-exact/ambiguous lines were intentionally left unchanged for review.
-- Audited, tenant-scoped repair for legacy workshop invoice JSON lines whose
-- UUIDs predate the stable mechanic_job_items identity bridge.
begin;

create table if not exists public.workshop_line_identity_backfill_runs (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  batch_key text not null,
  status text not null default 'running'
    check (status in ('running', 'completed')),
  started_at timestamptz not null default clock_timestamp(),
  completed_at timestamptz,
  summary jsonb not null default '{}'::jsonb,
  unique (tenant_id, batch_key)
);

create table if not exists public.workshop_line_identity_backfill_rows (
  id uuid primary key default gen_random_uuid(),
  run_id uuid not null
    references public.workshop_line_identity_backfill_runs(id) on delete cascade,
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  job_id uuid references public.mechanic_jobs(id) on delete set null,
  invoice_id uuid references public.sales_invoices(id) on delete set null,
  entity_type text not null check (entity_type in ('invoice_line', 'invoice_reference')),
  line_ordinality bigint,
  changed_fields text[] not null default '{}',
  before_data jsonb not null,
  after_data jsonb not null,
  created_at timestamptz not null default clock_timestamp()
);

create index if not exists idx_workshop_line_identity_backfill_rows_run
  on public.workshop_line_identity_backfill_rows(run_id, created_at, id);

alter table public.workshop_line_identity_backfill_runs enable row level security;
alter table public.workshop_line_identity_backfill_rows enable row level security;

drop policy if exists workshop_line_identity_backfill_runs_select
  on public.workshop_line_identity_backfill_runs;
create policy workshop_line_identity_backfill_runs_select
  on public.workshop_line_identity_backfill_runs
  for select to authenticated
  using (tenant_id = public.user_tenant_id());

drop policy if exists workshop_line_identity_backfill_rows_select
  on public.workshop_line_identity_backfill_rows;
create policy workshop_line_identity_backfill_rows_select
  on public.workshop_line_identity_backfill_rows
  for select to authenticated
  using (tenant_id = public.user_tenant_id());

revoke all on public.workshop_line_identity_backfill_runs,
              public.workshop_line_identity_backfill_rows
  from public, anon, authenticated, service_role;
grant select on public.workshop_line_identity_backfill_runs,
                public.workshop_line_identity_backfill_rows
  to authenticated;

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
    candidate.item_id as candidate_item_id,
    candidate.match_count as candidate_match_count
  from resolved
  left join public.mechanic_job_items stable
    on stable.id = resolved.raw_item_id
   and stable.job_id = resolved.job_id
   and stable.tenant_id = resolved.tenant_id
  left join lateral (
    select
      (array_agg(item.id order by item.id))[1] as item_id,
      count(*) as match_count
    from public.mechanic_job_items item
    where stable.id is null
      and item.job_id = resolved.job_id
      and item.tenant_id = resolved.tenant_id
      and item.job_bike_id is not distinct from resolved.job_bike_id
      and item.item_type = resolved.item_type
      and item.product_id is not distinct from
        case when resolved.item_type = 'product' then resolved.product_id end
      and item.service_product_id is not distinct from
        case when resolved.item_type = 'service' then resolved.product_id end
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
      where stable_item_id is null and candidate_match_count = 1
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
    and candidate_match_count = 1
    and candidate_usage_count = 1 as can_backfill
from usage_counted;

grant select on public.workshop_line_identity_backfill_preview to authenticated;

create or replace function public.apply_workshop_line_identity_backfill(
  p_tenant_id uuid,
  p_batch_key text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_run public.workshop_line_identity_backfill_runs%rowtype;
  v_invoice record;
  v_new_items jsonb;
  v_summary jsonb;
  v_key text := btrim(coalesce(p_batch_key, ''));
  v_changed_lines integer := 0;
  v_changed_invoices integer := 0;
  v_changed_references integer := 0;
  v_manual_review integer := 0;
  v_row_count integer := 0;
begin
  if p_tenant_id is null or v_key = '' then
    raise exception 'Tenant and non-empty batch key are required';
  end if;
  if auth.uid() is not null then
    raise exception 'Historical workshop repair is database-admin only'
      using errcode = '42501';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(p_tenant_id::text, 0));

  select * into v_run
    from public.workshop_line_identity_backfill_runs
   where tenant_id = p_tenant_id
     and batch_key = v_key;
  if found and v_run.status = 'completed' then
    return v_run.summary || jsonb_build_object('replayed', true);
  elsif found then
    raise exception 'Backfill batch is already running';
  end if;

  insert into public.workshop_line_identity_backfill_runs(
    tenant_id, batch_key
  ) values (
    p_tenant_id, v_key
  ) returning * into v_run;

  select count(*) into v_manual_review
    from public.workshop_line_identity_backfill_preview
   where tenant_id = p_tenant_id
     and not is_stable
     and not can_backfill;

  perform set_config('app.syncing_job_to_invoice', 'true', true);

  for v_invoice in
    select invoice.*, job.id as job_id
      from public.sales_invoices invoice
      join public.mechanic_jobs job
        on job.invoice_id = invoice.id
       and job.tenant_id = invoice.tenant_id
     where invoice.tenant_id = p_tenant_id
       and (
         invoice.reference like 'Pega %'
         or exists (
           select 1
             from public.workshop_line_identity_backfill_preview preview
            where preview.invoice_id = invoice.id
              and preview.can_backfill
         )
       )
     order by invoice.id
     for update of invoice
  loop
    insert into public.workshop_line_identity_backfill_rows(
      run_id, tenant_id, job_id, invoice_id, entity_type,
      line_ordinality, changed_fields, before_data, after_data
    )
    select
      v_run.id,
      p_tenant_id,
      v_invoice.job_id,
      v_invoice.id,
      'invoice_line',
      preview.line_ordinality,
      array[
        'id', 'service_configuration_data', 'system_key',
        'component_slot_key', 'location_key', 'intervention_type',
        'creates_lifecycle'
      ],
      preview.line_data,
      preview.line_data || jsonb_strip_nulls(jsonb_build_object(
        'id', item.id::text,
        'service_configuration_data', item.service_configuration_data,
        'system_key', item.system_key,
        'component_slot_key', item.component_slot_key,
        'location_key', item.location_key,
        'intervention_type', item.intervention_type,
        'creates_lifecycle', item.creates_lifecycle
      ))
    from public.workshop_line_identity_backfill_preview preview
    join public.mechanic_job_items item on item.id = preview.candidate_item_id
    where preview.invoice_id = v_invoice.id
      and preview.can_backfill;

    get diagnostics v_row_count = row_count;
    v_changed_lines := v_changed_lines + v_row_count;

    if v_invoice.reference like 'Pega %' then
      insert into public.workshop_line_identity_backfill_rows(
        run_id, tenant_id, job_id, invoice_id, entity_type,
        changed_fields, before_data, after_data
      ) values (
        v_run.id,
        p_tenant_id,
        v_invoice.job_id,
        v_invoice.id,
        'invoice_reference',
        array['reference'],
        jsonb_build_object('reference', v_invoice.reference),
        jsonb_build_object(
          'reference', regexp_replace(v_invoice.reference, '^Pega ', 'Trabajo ')
        )
      );
      v_changed_references := v_changed_references + 1;
    end if;

    select jsonb_agg(
      case
        when preview.can_backfill then
          line.value || jsonb_strip_nulls(jsonb_build_object(
            'id', item.id::text,
            'service_configuration_data', item.service_configuration_data,
            'system_key', item.system_key,
            'component_slot_key', item.component_slot_key,
            'location_key', item.location_key,
            'intervention_type', item.intervention_type,
            'creates_lifecycle', item.creates_lifecycle
          ))
        else line.value
      end
      order by line.ordinality
    ) into v_new_items
    from jsonb_array_elements(coalesce(v_invoice.items, '[]'::jsonb))
      with ordinality as line(value, ordinality)
    left join public.workshop_line_identity_backfill_preview preview
      on preview.invoice_id = v_invoice.id
     and preview.line_ordinality = line.ordinality
    left join public.mechanic_job_items item
      on item.id = preview.candidate_item_id;

    update public.sales_invoices
       set items = coalesce(v_new_items, '[]'::jsonb),
           reference = case
             when reference like 'Pega %'
               then regexp_replace(reference, '^Pega ', 'Trabajo ')
             else reference
           end,
           updated_at = clock_timestamp()
     where id = v_invoice.id;

    v_changed_invoices := v_changed_invoices + 1;
  end loop;

  perform set_config('app.syncing_job_to_invoice', '', true);

  v_summary := jsonb_build_object(
    'tenant_id', p_tenant_id,
    'batch_key', v_key,
    'changed_invoice_lines', v_changed_lines,
    'changed_invoices', v_changed_invoices,
    'changed_references', v_changed_references,
    'manual_review_lines', v_manual_review,
    'replayed', false
  );

  update public.workshop_line_identity_backfill_runs
     set status = 'completed',
         completed_at = clock_timestamp(),
         summary = v_summary
   where id = v_run.id;

  return v_summary;
exception
  when others then
    perform set_config('app.syncing_job_to_invoice', '', true);
    raise;
end;
$$;

revoke all on function public.apply_workshop_line_identity_backfill(uuid, text)
  from public, anon, authenticated, service_role;

comment on function public.apply_workshop_line_identity_backfill(uuid, text) is
  'Admin-only atomic backfill. Stamps only one-to-one exact workshop line identities and records before/after evidence.';

commit;
