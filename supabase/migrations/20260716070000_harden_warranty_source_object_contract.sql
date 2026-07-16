-- Deployment status: DEPLOYED AND VERIFIED IN PRODUCTION 2026-07-16.
--
-- Purpose:
--   Make a warranty inherit the canonical physical intake of its original
--   delivered job. Component provenance must never become bicycle custody,
--   and a stale form object must never be accepted through NULL/coalesce
--   behavior. Claim/source locks are deterministic and bounded, bicycle claims
--   own exactly one canonical mechanic_job_bikes row, and registration/decision
--   operation keys are exact receipts. A different key for an already-linked
--   registration returns an explicit invariant-already-satisfied receipt rather
--   than appending a duplicate event. The shared job-to-invoice sync and the
--   existing-invoice retry command also adopt the invoice -> job lock order
--   used by payments. Payment validates the shared commercial snapshot before
--   settlement; after financial history begins, both job and invoice
--   commercial projections remain exact no-ops. This migration performs no
--   data rewrite or financial posting merely by being installed.

begin;

set local lock_timeout = '750ms';
set local statement_timeout = '30s';

-- Append the canonical classification fields without changing the position or
-- type of any existing view column, preserving older select consumers.
create or replace view public.mechanic_job_service_warranty_view
with (security_invoker = true)
as
select
  job.tenant_id,
  job.id as job_id,
  job.job_number,
  job.customer_id,
  job.bike_id,
  job.subject_id,
  job.job_type,
  delivery.first_delivered_at,
  delivery.last_delivered_at,
  delivery.delivery_count,
  delivery.has_ambiguous_legacy_history,
  warranty.id as warranty_event_id,
  warranty.warranty_started_at,
  warranty.warranty_expires_at,
  warranty.warranty_days_snapshot,
  case
    when warranty.warranty_expires_at is null then 'not_started'
    when warranty.warranty_expires_at >= clock_timestamp() then 'active'
    else 'expired'
  end as warranty_state,
  case
    when warranty.warranty_expires_at is null then null
    else greatest(
      ceil(extract(epoch from (
        warranty.warranty_expires_at - clock_timestamp()
      )) / 86400.0),
      0
    )::integer
  end as warranty_days_remaining,
  job.intake_kind,
  job.mode_needs_review,
  job.subject_notes
from public.mechanic_jobs job
left join lateral (
  select
    min(event.occurred_at) as first_delivered_at,
    max(event.occurred_at) as last_delivered_at,
    count(*)::integer as delivery_count,
    bool_or(coalesce((event.metadata->>'legacy_ambiguous')::boolean, false))
      as has_ambiguous_legacy_history
  from public.mechanic_job_delivery_events event
  where event.tenant_id = job.tenant_id
    and event.job_id = job.id
    and event.event_kind in ('delivered', 'redelivered')
) delivery on true
left join lateral (
  select event.*
  from public.mechanic_job_delivery_events event
  where event.tenant_id = job.tenant_id
    and event.job_id = job.id
    and event.starts_warranty_window
  order by event.occurred_at desc, event.recorded_at desc, event.id desc
  limit 1
) warranty on true;

grant select on public.mechanic_job_service_warranty_view to authenticated;

create or replace function public.register_mechanic_job_warranty_claim(
  p_warranty_job_id uuid,
  p_source_job_id uuid,
  p_operation_key text
)
returns jsonb
language plpgsql
security definer
set search_path = public
set lock_timeout = '750ms'
as $$
declare
  v_warranty_job public.mechanic_jobs%rowtype;
  v_source_job public.mechanic_jobs%rowtype;
  v_existing public.mechanic_job_warranty_claim_events%rowtype;
  v_delivery public.mechanic_job_delivery_events%rowtype;
  v_event public.mechanic_job_warranty_claim_events%rowtype;
  v_eligibility text;
  v_operation_id uuid;
  v_operation_key text := btrim(coalesce(p_operation_key, ''));
  v_source_subject_notes text;
  v_warranty_subject_notes text;
  v_tenant_id uuid;
  v_has_existing_registration boolean := false;
  v_job_bike_id uuid;
begin
  if p_warranty_job_id is null or p_source_job_id is null then
    raise exception 'La garantía debe vincularse al trabajo original';
  end if;
  if p_warranty_job_id = p_source_job_id then
    raise exception 'El trabajo de garantía no puede ser su propio origen';
  end if;
  if v_operation_key = '' then
    raise exception 'La garantía requiere una clave de operación';
  end if;

  -- Resolve and authorize the tenant before taking row locks. The two jobs are
  -- then locked in UUID order so source reclassification/delivery cannot race
  -- the frozen claim object and concurrent cross-claim calls cannot deadlock by
  -- acquiring the same pair in opposite order. The function-level lock timeout
  -- makes active shop work win after 750ms instead of waiting indefinitely.
  select tenant_id into v_tenant_id
  from public.mechanic_jobs
  where id = p_warranty_job_id;
  if not found then raise exception 'Trabajo de garantía no encontrado'; end if;
  perform public.assert_workshop_rpc_tenant(v_tenant_id);

  perform job.id
  from public.mechanic_jobs job
  where job.tenant_id = v_tenant_id
    and job.id in (p_warranty_job_id, p_source_job_id)
  order by job.id
  for update;

  select * into v_warranty_job
  from public.mechanic_jobs
  where id = p_warranty_job_id
    and tenant_id = v_tenant_id;
  if not found then raise exception 'Trabajo de garantía no encontrado'; end if;

  select * into v_source_job
  from public.mechanic_jobs
  where id = p_source_job_id
    and tenant_id = v_tenant_id;
  if not found then raise exception 'Trabajo original no encontrado'; end if;

  if v_warranty_job.customer_id is distinct from v_source_job.customer_id then
    raise exception 'La garantía y el trabajo original deben pertenecer al mismo cliente';
  end if;

  -- A replay key is a durable receipt, not a wildcard. Reject a collision that
  -- belongs to another claim, source, or event type.
  select * into v_event
  from public.mechanic_job_warranty_claim_events
  where tenant_id = v_warranty_job.tenant_id
    and operation_key = v_operation_key;
  if found then
    if v_event.warranty_job_id is distinct from v_warranty_job.id
       or v_event.source_job_id is distinct from v_source_job.id
       or v_event.event_type <> 'registration' then
      raise exception 'La clave de operación ya pertenece a otra acción de garantía'
        using errcode = '23505';
    end if;
    return to_jsonb(v_event) || jsonb_build_object('replay', true);
  end if;

  select * into v_existing
  from public.mechanic_job_warranty_claim_events
  where tenant_id = v_warranty_job.tenant_id
    and warranty_job_id = v_warranty_job.id
    and event_type = 'registration'
  order by occurred_at desc, id desc
  limit 1;

  v_has_existing_registration := found
    and v_existing.source_job_id is not null;
  if v_has_existing_registration then
    if v_existing.source_job_id is distinct from v_source_job.id then
      raise exception 'La garantía ya está vinculada a otro trabajo original';
    end if;
  end if;

  if coalesce(v_source_job.mode_needs_review, false)
     or v_source_job.intake_kind not in ('bike', 'component') then
    raise exception 'Clasifica primero el trabajo original como bicicleta o componente';
  end if;

  v_source_subject_notes := nullif(btrim(coalesce(v_source_job.subject_notes, '')), '');
  v_warranty_subject_notes := nullif(btrim(coalesce(v_warranty_job.subject_notes, '')), '');

  if v_source_job.intake_kind = 'bike' then
    if v_source_job.bike_id is null then
      raise exception 'El trabajo original no tiene una bicicleta canónica';
    end if;
    if v_warranty_job.bike_id is not null
       and v_warranty_job.bike_id is distinct from v_source_job.bike_id then
      raise exception 'La bicicleta de garantía no coincide con el trabajo original';
    end if;
    if v_warranty_job.subject_id is not null then
      raise exception 'Una garantía de bicicleta no puede conservar un componente recibido';
    end if;
    if exists (
      select 1
      from public.mechanic_job_bikes job_bike
      where job_bike.tenant_id = v_warranty_job.tenant_id
        and job_bike.job_id = v_warranty_job.id
        and job_bike.bike_id is distinct from v_source_job.bike_id
    ) then
      raise exception 'La ficha de garantía contiene una bicicleta distinta al trabajo original';
    end if;

    if v_has_existing_registration then
      if v_warranty_job.bike_id is distinct from v_source_job.bike_id
         or (
           select count(*)
           from public.mechanic_job_bikes job_bike
           where job_bike.tenant_id = v_warranty_job.tenant_id
             and job_bike.job_id = v_warranty_job.id
             and job_bike.bike_id = v_source_job.bike_id
         ) <> 1 then
        raise exception 'La garantía registrada no conserva su bicicleta canónica';
      end if;
    else
      insert into public.mechanic_job_bikes (
        tenant_id,
        job_id,
        bike_id,
        order_index,
        work_requested,
        is_warranty_work
      ) values (
        v_warranty_job.tenant_id,
        v_warranty_job.id,
        v_source_job.bike_id,
        0,
        v_warranty_job.client_request,
        true
      )
      on conflict (job_id, bike_id) do update
        set is_warranty_work = true,
            updated_at = clock_timestamp()
      returning id into v_job_bike_id;
    end if;
  else
    if v_source_job.subject_id is null and v_source_subject_notes is null then
      raise exception 'El trabajo original no identifica el componente recibido';
    end if;
    if v_warranty_job.bike_id is not null or exists (
      select 1
      from public.mechanic_job_bikes job_bike
      where job_bike.tenant_id = v_warranty_job.tenant_id
        and job_bike.job_id = v_warranty_job.id
    ) then
      raise exception 'Una garantía de componente no puede recibir una bicicleta completa';
    end if;
    if v_warranty_job.subject_id is distinct from v_source_job.subject_id then
      raise exception 'El componente de garantía no coincide con el trabajo original';
    end if;
    if v_source_job.subject_id is null
       and v_warranty_subject_notes is distinct from v_source_subject_notes then
      raise exception 'La descripción del componente no coincide con el trabajo original';
    end if;
  end if;

  -- A new operation key for an already-linked claim is not another immutable
  -- registration event. Return a deterministic reconstructed receipt whose
  -- request key is explicit and whose canonical event key remains available.
  -- This lets a client recognize "invariant already satisfied" without
  -- inventing a second registration or replaying financial behavior.
  if v_has_existing_registration then
    return to_jsonb(v_existing) || jsonb_build_object(
      'operation_key', v_operation_key,
      'canonical_operation_key', v_existing.operation_key,
      'request_operation_key', v_operation_key,
      'invariant_already_satisfied', true,
      'replay', true
    );
  end if;

  select * into v_delivery
  from public.mechanic_job_delivery_events
  where tenant_id = v_source_job.tenant_id
    and job_id = v_source_job.id
    and starts_warranty_window
  order by occurred_at desc, recorded_at desc, id desc
  limit 1;

  v_eligibility := case
    when v_delivery.id is null then 'unknown'
    when v_delivery.warranty_expires_at >= clock_timestamp() then 'within_window'
    else 'outside_window'
  end;

  insert into public.mechanic_job_warranty_claim_events (
    tenant_id,
    warranty_job_id,
    source_job_id,
    source_delivery_event_id,
    event_type,
    eligibility,
    warranty_expires_at_snapshot,
    outcome,
    actor_id,
    operation_key,
    metadata
  ) values (
    v_warranty_job.tenant_id,
    v_warranty_job.id,
    v_source_job.id,
    v_delivery.id,
    'registration',
    v_eligibility,
    v_delivery.warranty_expires_at,
    'pending',
    auth.uid(),
    v_operation_key,
    jsonb_build_object(
      'source_job_type', v_source_job.job_type,
      'source_intake_kind', v_source_job.intake_kind,
      'source_bike_id', v_source_job.bike_id,
      'source_subject_id', v_source_job.subject_id,
      'source_subject_notes', v_source_subject_notes
    )
  ) returning * into v_event;

  perform set_config('app.warranty_claim_rpc', 'true', true);
  perform set_config('app.mechanic_job_mode_rpc', 'true', true);
  update public.mechanic_jobs
  set job_type = 'warranty',
      workflow_kind = 'warranty',
      intake_kind = v_source_job.intake_kind,
      is_warranty_job = true,
      warranty_outcome = 'pending',
      bike_id = case
        when v_source_job.intake_kind = 'bike' then v_source_job.bike_id
        else null
      end,
      subject_id = case
        when v_source_job.intake_kind = 'component' then v_source_job.subject_id
        else null
      end,
      subject_notes = case
        when v_source_job.intake_kind = 'component' then v_source_subject_notes
        else null
      end,
      mode_needs_review = false,
      mode_review_reason = null,
      updated_at = clock_timestamp()
  where id = v_warranty_job.id;
  perform set_config('app.mechanic_job_mode_rpc', '', true);
  perform set_config('app.warranty_claim_rpc', '', true);

  v_operation_id := public.record_service_warranty_trace(
    v_warranty_job.tenant_id,
    v_warranty_job.id,
    v_operation_key,
    'warranty_claim_registered',
    jsonb_build_object(
      'outcome', v_warranty_job.warranty_outcome,
      'intake_kind', v_warranty_job.intake_kind,
      'bike_id', v_warranty_job.bike_id,
      'subject_id', v_warranty_job.subject_id
    ),
    jsonb_build_object(
      'outcome', 'pending',
      'source_job_id', v_source_job.id,
      'eligibility', v_eligibility,
      'intake_kind', v_source_job.intake_kind,
      'bike_id', case
        when v_source_job.intake_kind = 'bike' then v_source_job.bike_id
        else null
      end,
      'subject_id', case
        when v_source_job.intake_kind = 'component' then v_source_job.subject_id
        else null
      end
    ),
    jsonb_build_object('claim_event_id', v_event.id)
  );

  return to_jsonb(v_event) || jsonb_build_object(
    'operation_id', v_operation_id,
    'replay', false
  );
exception
  when others then
    perform set_config('app.mechanic_job_mode_rpc', '', true);
    perform set_config('app.warranty_claim_rpc', '', true);
    raise;
end;
$$;

revoke all on function public.register_mechanic_job_warranty_claim(
  uuid, uuid, text
) from public, anon, authenticated, service_role;
grant execute on function public.register_mechanic_job_warranty_claim(
  uuid, uuid, text
) to authenticated;

comment on function public.register_mechanic_job_warranty_claim(
  uuid, uuid, text
) is
  'Registers a replay-safe warranty claim and replaces its physical object with the canonical bike/component intake of the original delivered job. A new key for an already-satisfied registration returns invariant_already_satisfied plus request_operation_key and canonical_operation_key without appending a duplicate event.';

-- Invoice linkage and settlement mirrors are database-owned. Older clients may
-- send a stale full-row payload after a preceding request linked the invoice;
-- normalize that stale null/false mirror instead of unlinking finance or
-- returning a misleading whole-save failure. Reassignment to a different
-- invoice is still rejected as an invariant violation.
create or replace function public.guard_mechanic_job_invoice_link_identity()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if old.invoice_id is null
     or current_setting('app.syncing_invoice_status_to_job', true) = 'true' then
    return new;
  end if;

  if new.invoice_id is not null
     and new.invoice_id is distinct from old.invoice_id then
    raise exception 'Un trabajo facturado no puede reasignarse a otra factura.'
      using errcode = '55000';
  end if;

  new.invoice_id := old.invoice_id;
  new.is_invoiced := true;
  new.is_paid := old.is_paid;
  return new;
end;
$$;

drop trigger if exists trg_mechanic_jobs_guard_invoice_link_identity
  on public.mechanic_jobs;
create trigger trg_mechanic_jobs_guard_invoice_link_identity
  before update of invoice_id, is_invoiced, is_paid on public.mechanic_jobs
  for each row execute function public.guard_mechanic_job_invoice_link_identity();

revoke all on function public.guard_mechanic_job_invoice_link_identity()
  from public, anon, authenticated, service_role;

create or replace function public.sync_invoice_status_to_job(p_invoice_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_invoice public.sales_invoices%rowtype;
  v_job_id uuid;
begin
  if p_invoice_id is null then return; end if;
  select invoice.* into v_invoice
  from public.sales_invoices invoice
  where invoice.id = p_invoice_id;
  if not found then return; end if;
  perform public.assert_workshop_rpc_tenant(v_invoice.tenant_id);

  select job.id into v_job_id
  from public.mechanic_jobs job
  where job.invoice_id = p_invoice_id
    and job.tenant_id = v_invoice.tenant_id;
  if v_job_id is null then return; end if;

  perform set_config('app.syncing_invoice_status_to_job', 'true', true);
  update public.mechanic_jobs
  set is_invoiced = true,
      is_paid = lower(v_invoice.status) in ('paid', 'pagado', 'pagada'),
      tax_treatment = v_invoice.tax_treatment,
      tax_amount = v_invoice.iva_amount,
      total_cost = v_invoice.total,
      updated_at = clock_timestamp()
  where id = v_job_id;
  perform set_config('app.syncing_invoice_status_to_job', '', true);
exception
  when others then
    perform set_config('app.syncing_invoice_status_to_job', '', true);
    raise;
end;
$$;

revoke all on function public.sync_invoice_status_to_job(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.sync_invoice_status_to_job(uuid)
  to authenticated;

comment on function public.sync_invoice_status_to_job(uuid) is
  'Synchronizes invoice-owned paid/tax/total mirrors to a linked workshop job under an explicit internal identity-guard context.';

-- A payment must never settle a stale workshop projection. Compare only the
-- shared commercial contract: payment-owned tax/cost fields and legacy line
-- identifiers are intentionally excluded, while every job-owned price,
-- quantity, description, catalog target and technical service configuration
-- is normalized deterministically. Sorting makes legacy invoices without
-- stable line IDs comparable without rewriting them during deployment.
create or replace function public.workshop_job_commercial_snapshot(
  p_job_id uuid
)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
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
              when item.item_type = 'service' then item.service_product_id::text
              when item.item_type = 'product' then item.product_id::text
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
  )
  from public.mechanic_jobs job
  where job.id = p_job_id;
$$;

create or replace function public.workshop_invoice_commercial_snapshot(
  p_invoice_id uuid
)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
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
              nullif(invoice_item.value->>'is_catalog_product', '')::boolean,
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
            nullif(invoice_item.value->>'creates_lifecycle', '')::boolean,
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
          end as product_id
        ) parsed
        left join public.products product
          on product.id = parsed.product_id
         and product.tenant_id = invoice.tenant_id
      ) line
    ), '[]'::jsonb)
  )
  from public.sales_invoices invoice
  where invoice.id = p_invoice_id;
$$;

revoke all on function public.workshop_job_commercial_snapshot(uuid)
  from public, anon, authenticated, service_role;
revoke all on function public.workshop_invoice_commercial_snapshot(uuid)
  from public, anon, authenticated, service_role;

create or replace function public.assert_workshop_payment_snapshot_current(
  p_invoice_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
set lock_timeout = '750ms'
as $$
declare
  v_invoice public.sales_invoices%rowtype;
  v_job_id uuid;
  v_link_count integer := 0;
  v_candidate record;
  v_job_snapshot jsonb;
  v_invoice_snapshot jsonb;
begin
  if p_invoice_id is null then return; end if;

  select invoice.* into v_invoice
  from public.sales_invoices invoice
  where invoice.id = p_invoice_id
  for update;
  if not found then return; end if;

  perform public.assert_sales_payment_access(v_invoice.tenant_id);

  -- Payment paths already own the invoice lock. Lock every linked job next so
  -- a concurrent child-row guard either commits first (and is detected here)
  -- or waits until the payment exists and is rejected there.
  for v_candidate in
    select job.id
    from public.mechanic_jobs job
    where job.invoice_id = v_invoice.id
      and job.tenant_id = v_invoice.tenant_id
      and job.deleted_at is null
    order by job.id
    for update
  loop
    v_link_count := v_link_count + 1;
    v_job_id := v_candidate.id;
  end loop;

  if v_link_count = 0 then return; end if;
  if v_link_count <> 1 then
    raise exception 'La factura está vinculada a más de un trabajo; no se registró el pago.'
      using errcode = '23514';
  end if;

  v_job_snapshot := public.workshop_job_commercial_snapshot(v_job_id);
  v_invoice_snapshot :=
    public.workshop_invoice_commercial_snapshot(v_invoice.id);

  if v_job_snapshot is distinct from v_invoice_snapshot then
    raise exception 'El trabajo cambió mientras se preparaba el pago. Guarda o recarga el trabajo y vuelve a cobrar; no se registró ningún pago.'
      using errcode = '40001';
  end if;
end;
$$;

revoke all on function public.assert_workshop_payment_snapshot_current(uuid)
  from public, anon, authenticated, service_role;

-- The atomic tax/payment command updates invoice status immediately before it
-- inserts the payment. Validate before that update can project an older invoice
-- back into the job. Legacy/direct payment inserts receive the same assertion.
create or replace function public.guard_workshop_payment_snapshot()
returns trigger
language plpgsql
security definer
set search_path = public
set lock_timeout = '750ms'
as $$
begin
  if tg_table_name = 'sales_invoices' then
    if current_setting('app.payment_tax_command', true) = 'true' then
      perform public.assert_workshop_payment_snapshot_current(new.id);
    end if;
    return new;
  end if;

  if tg_op = 'DELETE' then return old; end if;
  if new.deleted_at is null then
    perform public.assert_workshop_payment_snapshot_current(new.invoice_id);
  end if;
  return new;
end;
$$;

drop trigger if exists trg_sales_invoice_00_workshop_payment_snapshot_guard
  on public.sales_invoices;
create trigger trg_sales_invoice_00_workshop_payment_snapshot_guard
  before update of status, tax_treatment on public.sales_invoices
  for each row execute function public.guard_workshop_payment_snapshot();

drop trigger if exists trg_sales_payments_00_workshop_snapshot_guard
  on public.sales_payments;
create trigger trg_sales_payments_00_workshop_snapshot_guard
  before insert or update on public.sales_payments
  for each row execute function public.guard_workshop_payment_snapshot();

revoke all on function public.guard_workshop_payment_snapshot()
  from public, anon, authenticated, service_role;

-- Commercial child mutations serialize on the job row. They never acquire the
-- invoice lock, which avoids reversing the invoice -> job order used by payment
-- posting. Once a payment commits, external item/physical-bike mutations fail
-- atomically; invoice-owned reconciliation is explicitly exempt.
create or replace function public.guard_paid_workshop_child_mutation()
returns trigger
language plpgsql
security definer
set search_path = public
set lock_timeout = '750ms'
as $$
declare
  v_changed boolean := true;
  v_job public.mechanic_jobs%rowtype;
  v_candidate record;
  v_old_job_id uuid;
  v_new_job_id uuid;
begin
  if current_setting('app.syncing_invoice_to_job', true) = 'true' then
    if tg_op = 'DELETE' then return old; end if;
    return new;
  end if;

  if tg_op = 'UPDATE' then
    if tg_table_name = 'mechanic_job_items' then
      v_changed := (to_jsonb(old) - 'updated_at' - 'created_at')
        is distinct from
        (to_jsonb(new) - 'updated_at' - 'created_at');
    else
      v_changed := row(
        old.tenant_id, old.job_id, old.bike_id,
        old.parts_cost, old.labor_cost, old.subtotal
      ) is distinct from row(
        new.tenant_id, new.job_id, new.bike_id,
        new.parts_cost, new.labor_cost, new.subtotal
      );
    end if;
    if not v_changed then return new; end if;
  end if;

  if tg_op <> 'INSERT' then v_old_job_id := old.job_id; end if;
  if tg_op <> 'DELETE' then v_new_job_id := new.job_id; end if;

  for v_candidate in
    select distinct candidate.job_id
    from unnest(array[
      v_old_job_id,
      v_new_job_id
    ]::uuid[]) candidate(job_id)
    where candidate.job_id is not null
    order by candidate.job_id
  loop
    select job.* into v_job
    from public.mechanic_jobs job
    where job.id = v_candidate.job_id
    for update;
    if not found or v_job.invoice_id is null then continue; end if;

    if exists (
      select 1
      from public.sales_invoices invoice
      where invoice.id = v_job.invoice_id
        and invoice.tenant_id = v_job.tenant_id
        and (
          lower(invoice.status) in ('paid', 'pagado', 'pagada')
          or coalesce(invoice.paid_amount, 0) > 0
          or exists (
            select 1
            from public.sales_payments payment
            where payment.invoice_id = invoice.id
              and payment.tenant_id = invoice.tenant_id
              and payment.deleted_at is null
              and coalesce(payment.amount, 0) > 0
          )
        )
    ) then
      raise exception 'La factura del trabajo ya tiene pagos. Productos, precios y bicicleta recibida quedan protegidos; el diagnóstico sí puede seguir editándose.'
        using errcode = '55000';
    end if;
  end loop;

  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$$;

drop trigger if exists trg_mechanic_job_items_guard_paid_snapshot
  on public.mechanic_job_items;
create trigger trg_mechanic_job_items_guard_paid_snapshot
  before insert or update or delete on public.mechanic_job_items
  for each row execute function public.guard_paid_workshop_child_mutation();

drop trigger if exists trg_mechanic_job_bikes_guard_paid_snapshot
  on public.mechanic_job_bikes;
create trigger trg_mechanic_job_bikes_guard_paid_snapshot
  before insert or update or delete on public.mechanic_job_bikes
  for each row execute function public.guard_paid_workshop_child_mutation();

revoke all on function public.guard_paid_workshop_child_mutation()
  from public, anon, authenticated, service_role;

create or replace function public.guard_paid_workshop_job_commercial_update()
returns trigger
language plpgsql
security definer
set search_path = public
set lock_timeout = '750ms'
as $$
begin
  if current_setting('app.syncing_invoice_to_job', true) = 'true'
     or old.invoice_id is null then
    return new;
  end if;

  if row(
    old.customer_id, old.bike_id, old.service_package_id,
    old.job_type, old.workflow_kind, old.intake_kind,
    old.mode_needs_review, old.mode_review_reason,
    old.subject_id, old.subject_notes, old.discount_amount
  ) is not distinct from row(
    new.customer_id, new.bike_id, new.service_package_id,
    new.job_type, new.workflow_kind, new.intake_kind,
    new.mode_needs_review, new.mode_review_reason,
    new.subject_id, new.subject_notes, new.discount_amount
  ) then
    return new;
  end if;

  if exists (
    select 1
    from public.sales_invoices invoice
    where invoice.id = old.invoice_id
      and invoice.tenant_id = old.tenant_id
      and (
        lower(invoice.status) in ('paid', 'pagado', 'pagada')
        or coalesce(invoice.paid_amount, 0) > 0
        or exists (
          select 1
          from public.sales_payments payment
          where payment.invoice_id = invoice.id
            and payment.tenant_id = invoice.tenant_id
            and payment.deleted_at is null
            and coalesce(payment.amount, 0) > 0
        )
      )
  ) then
    raise exception 'La factura del trabajo ya tiene pagos. Cliente, modalidad, objeto recibido y descuento quedan protegidos.'
      using errcode = '55000';
  end if;

  return new;
end;
$$;

drop trigger if exists trg_mechanic_jobs_guard_paid_commercial_snapshot
  on public.mechanic_jobs;
create trigger trg_mechanic_jobs_guard_paid_commercial_snapshot
  before update of customer_id, bike_id, service_package_id, job_type,
    workflow_kind, intake_kind, mode_needs_review, mode_review_reason,
    subject_id, subject_notes, discount_amount
  on public.mechanic_jobs
  for each row execute function public.guard_paid_workshop_job_commercial_update();

revoke all on function public.guard_paid_workshop_job_commercial_update()
  from public, anon, authenticated, service_role;

-- The lifecycle trigger is intentionally defined on UPDATE OF status/status_id
-- for compatibility with older clients, but PostgreSQL fires that trigger when
-- a column is merely present in SET even if its value did not change. Exit
-- before touching the invoice when both lifecycle values are identical so a
-- diagnosis-only save cannot re-confirm/repost a completed covered warranty.
create or replace function public.sync_covered_warranty_invoice_lifecycle()
returns trigger
language plpgsql
security definer
set search_path = public
set lock_timeout = '750ms'
as $$
declare
  v_old_complete boolean := false;
  v_new_complete boolean;
  v_invoice_id uuid;
  v_tenant_id uuid;
  v_invoice public.sales_invoices%rowtype;
  v_operation_text text;
  v_operation_id uuid;
begin
  if tg_op = 'UPDATE'
     and old.status is not distinct from new.status
     and old.status_id is not distinct from new.status_id then
    return new;
  end if;

  -- Existing invoice identity belongs to the stored row, not to an older
  -- client's full-row mirror. Use OLD first on UPDATE so trigger ordering can
  -- never make a stale invoice_id = null skip posting/reversal or its payment
  -- guard. A status change that links its first invoice still uses NEW.
  if tg_op = 'UPDATE' then
    v_invoice_id := coalesce(old.invoice_id, new.invoice_id);
    v_tenant_id := old.tenant_id;
  else
    v_invoice_id := new.invoice_id;
    v_tenant_id := new.tenant_id;
  end if;

  if new.job_type <> 'warranty'
     or new.warranty_outcome <> 'covered'
     or v_invoice_id is null then
    return new;
  end if;

  if tg_op = 'UPDATE' then
    -- The row-level trigger already owns the job row. Take the invoice lock
    -- with a bounded wait, then fail the whole status statement before any
    -- posting/reversal when settlement evidence exists. Normal paid services
    -- never enter this covered-warranty-only branch.
    select invoice.* into v_invoice
    from public.sales_invoices invoice
    where invoice.id = v_invoice_id
      and invoice.tenant_id = v_tenant_id
    for update;

    if v_invoice.id is not null and (
      lower(v_invoice.status) in ('paid', 'pagado', 'pagada')
      or coalesce(v_invoice.paid_amount, 0) > 0
      or exists (
        select 1
        from public.sales_payments payment
        where payment.invoice_id = v_invoice.id
          and payment.tenant_id = v_invoice.tenant_id
          and payment.deleted_at is null
          and coalesce(payment.amount, 0) > 0
      )
    ) then
      raise exception 'La garantía cubierta tiene evidencia de pago. Su estado y efectos contables no pueden cambiar sin una corrección financiera auditada.'
        using errcode = '55000';
    end if;
  end if;

  if tg_op = 'UPDATE' then
    v_old_complete := public.mechanic_job_resolves_completion(
      old.status,
      old.status_id
    );
  end if;
  v_new_complete := public.mechanic_job_resolves_completion(
    new.status,
    new.status_id
  );

  if v_new_complete then
    update public.sales_invoices invoice
    set status = 'confirmed', updated_at = clock_timestamp()
    where invoice.id = v_invoice_id
      and invoice.tenant_id = v_tenant_id
      and lower(invoice.status) in (
        'draft','borrador','sent','enviado','enviada','issued','emitido','emitida'
      )
    returning invoice.* into v_invoice;

    if v_invoice.id is not null then
      perform public.consume_sales_invoice_inventory(v_invoice);
      perform public.create_service_warranty_cost_journal(v_invoice);

      v_operation_text := nullif(
        current_setting('app.inventory_operation_id', true),
        ''
      );
      if v_operation_text ~* '^[0-9a-f-]{36}$' then
        v_operation_id := v_operation_text::uuid;
        if exists (
          select 1
          from public.inventory_accounting_operations operation
          where operation.id = v_operation_id
            and operation.tenant_id = v_tenant_id
            and operation.document_type = 'sales_invoice'
            and operation.document_id = v_invoice.id
            and operation.outcome = 'started'
        ) then
          perform public.complete_inventory_accounting_operation(
            v_operation_id,
            v_tenant_id,
            jsonb_build_object(
              'trigger_operation', lower(tg_op),
              'service_warranty_lifecycle', 'posted'
            )
          );
        end if;
        perform set_config('app.inventory_operation_id', '', true);
        perform set_config('app.inventory_source_document_type', '', true);
        perform set_config('app.inventory_source_document_id', '', true);
        perform set_config('app.inventory_source_channel', '', true);
      end if;
    end if;
  elsif v_old_complete then
    select * into v_invoice
    from public.sales_invoices invoice
    where invoice.id = v_invoice_id
      and invoice.tenant_id = v_tenant_id
      and lower(invoice.status) not in (
        'draft','borrador','sent','enviado','enviada','issued','emitido','emitida',
        'cancelled','cancelado','cancelada','anulado','anulada'
      )
    for update;

    if v_invoice.id is not null then
      update public.sales_invoices
      set status = case when upper(coalesce(new.status, '')) = 'CANCELADO'
        then 'cancelled' else 'draft' end,
        updated_at = clock_timestamp()
      where id = v_invoice.id;

      perform public.restore_sales_invoice_inventory(v_invoice);
      delete from public.journal_entries
      where tenant_id = v_invoice.tenant_id
        and source_module = 'sales_invoices'
        and source_reference = v_invoice.invoice_number;

      v_operation_text := nullif(
        current_setting('app.inventory_operation_id', true),
        ''
      );
      if v_operation_text ~* '^[0-9a-f-]{36}$' then
        v_operation_id := v_operation_text::uuid;
        if exists (
          select 1
          from public.inventory_accounting_operations operation
          where operation.id = v_operation_id
            and operation.tenant_id = v_tenant_id
            and operation.document_type = 'sales_invoice'
            and operation.document_id = v_invoice.id
            and operation.outcome = 'started'
        ) then
          perform public.complete_inventory_accounting_operation(
            v_operation_id,
            v_tenant_id,
            jsonb_build_object(
              'trigger_operation', lower(tg_op),
              'service_warranty_lifecycle', 'reversed'
            )
          );
        end if;
        perform set_config('app.inventory_operation_id', '', true);
        perform set_config('app.inventory_source_document_type', '', true);
        perform set_config('app.inventory_source_document_id', '', true);
        perform set_config('app.inventory_source_channel', '', true);
      end if;
    end if;
  end if;

  return new;
end;
$$;

revoke all on function public.sync_covered_warranty_invoice_lifecycle()
  from public, anon, authenticated, service_role;

comment on function public.sync_covered_warranty_invoice_lifecycle() is
  'Posts or reverses covered-warranty invoice effects only when status/status_id actually changes; diagnosis-only updates are exact financial no-ops.';

-- Payment posting locks the invoice and then updates its linked job. Keep the
-- direct workshop sync command on that same global order so normal form saves
-- cannot deadlock with a payment that arrives at the same time.
create or replace function public.sync_job_to_invoice(p_job_id uuid)
returns void
language plpgsql
security definer
set search_path = public
set lock_timeout = '750ms'
as $$
declare
  v_preflight_tenant_id uuid;
  v_preflight_invoice_id uuid;
  v_job public.mechanic_jobs%rowtype;
  v_invoice public.sales_invoices%rowtype;
  v_items jsonb := '[]'::jsonb;
  v_item record;
  v_existing jsonb;
  v_parts numeric(12,2) := 0;
  v_labor numeric(12,2) := 0;
  v_gross numeric(12,2) := 0;
  v_discount numeric(12,2) := 0;
  v_total numeric(12,2) := 0;
  v_has_financial_history boolean := false;
begin
  if p_job_id is null then return; end if;
  if current_setting('app.syncing_invoice_to_job', true) = 'true' then return; end if;

  select job.tenant_id, job.invoice_id
    into v_preflight_tenant_id, v_preflight_invoice_id
  from public.mechanic_jobs job
  where job.id = p_job_id;
  if not found or v_preflight_invoice_id is null then return; end if;
  perform public.assert_workshop_rpc_tenant(v_preflight_tenant_id);

  select invoice.* into v_invoice
  from public.sales_invoices invoice
  where invoice.id = v_preflight_invoice_id
    and invoice.tenant_id = v_preflight_tenant_id
  for update;
  if not found then
    raise exception 'La factura vinculada al trabajo no existe en el mismo tenant.';
  end if;

  select job.* into v_job
  from public.mechanic_jobs job
  where job.id = p_job_id
  for update;
  if not found then
    raise exception 'El trabajo vinculado a la factura ya no existe.'
      using errcode = '40001';
  end if;
  if v_job.tenant_id is distinct from v_preflight_tenant_id
     or v_job.invoice_id is distinct from v_preflight_invoice_id then
    raise exception 'El vínculo financiero del trabajo cambió durante la sincronización; vuelve a intentarlo'
      using errcode = '40001';
  end if;

  select
    lower(v_invoice.status) in ('paid', 'pagado', 'pagada')
    or coalesce(v_invoice.paid_amount, 0) > 0
    or exists (
      select 1
      from public.sales_payments payment
      where payment.tenant_id = v_invoice.tenant_id
        and payment.invoice_id = v_invoice.id
        and payment.deleted_at is null
        and coalesce(payment.amount, 0) > 0
    )
  into v_has_financial_history;
  if v_has_financial_history then
    -- Never use an ordinary form save as a retroactive cleanup for historical
    -- paid rows. Production contains legitimate legacy differences, including
    -- richer workshop-only technical metadata. Payment-time guards prevent
    -- new drift; once financial history exists this command is an exact
    -- commercial no-op on both sides.
    return;
  end if;

  for v_item in
    select item.*,
           coalesce(nullif(concat_ws(' ', bike.brand, bike.model), ''), 'Bicicleta') as bike_name,
           product.cost as catalog_cost
      from public.mechanic_job_items item
      left join public.mechanic_job_bikes job_bike on job_bike.id = item.job_bike_id
      left join public.bikes bike on bike.id = job_bike.bike_id
      left join public.products product
        on product.id = coalesce(item.product_id, item.service_product_id)
       and product.tenant_id = item.tenant_id
     where item.job_id = p_job_id
       and item.tenant_id = v_job.tenant_id
     order by item.created_at, item.id
  loop
    select element.value into v_existing
      from jsonb_array_elements(coalesce(v_invoice.items, '[]'::jsonb)) element(value)
     where element.value->>'id' = v_item.id::text
     limit 1;

    v_items := v_items || jsonb_build_object(
      'id', v_item.id,
      'product_id', case
        when v_item.item_type = 'service' then coalesce(v_item.service_product_id::text, '')
        when v_item.item_type = 'product' then coalesce(v_item.product_id::text, '')
        else ''
      end,
      'product_name', v_item.product_name,
      'product_sku', coalesce(v_item.product_sku, ''),
      'description', coalesce(v_item.notes, v_item.description, ''),
      'item_type', v_item.item_type,
      'is_service', v_item.item_type = 'service',
      'is_catalog_product',
        v_item.item_type <> 'adhoc'
        and coalesce(v_item.product_id, v_item.service_product_id) is not null,
      'quantity', v_item.quantity,
      'unit_price', v_item.unit_price,
      'discount', coalesce(nullif(v_existing->>'discount', '')::numeric, 0),
      'line_total', coalesce(v_item.total_price, v_item.quantity * v_item.unit_price, 0),
      'cost', coalesce(nullif(v_existing->>'cost', '')::numeric, v_item.catalog_cost, 0),
      'purchase_treatment', coalesce(v_existing->>'purchase_treatment', 'inventory'),
      'job_bike_id', v_item.job_bike_id,
      'bike_name', case when v_item.job_bike_id is null then null else v_item.bike_name end,
      'service_configuration_data', v_item.service_configuration_data,
      'system_key', v_item.system_key,
      'component_slot_key', v_item.component_slot_key,
      'location_key', v_item.location_key,
      'intervention_type', v_item.intervention_type,
      'creates_lifecycle', v_item.creates_lifecycle
    );

    if v_item.item_type = 'product' then
      v_parts := v_parts + coalesce(v_item.total_price, 0);
    else
      v_labor := v_labor + coalesce(v_item.total_price, 0);
    end if;
  end loop;

  v_gross := round(v_parts + v_labor, 2);
  v_discount := round(coalesce(v_job.discount_amount, 0), 2);
  if v_discount < 0 or v_discount > v_gross then
    raise exception 'El descuento del trabajo debe estar entre cero y el subtotal (%).', v_gross;
  end if;
  v_total := v_gross - v_discount;

  -- Prevent the invoice UPDATE trigger from projecting the same payload back
  -- into child rows while this invoice -> job lock order is held. Besides
  -- avoiding redundant work, this is what keeps a concurrent child-row guard
  -- from forming an invoice/job/item wait cycle.
  perform set_config('app.syncing_job_to_invoice', 'true', true);
  update public.sales_invoices
     set items = v_items,
         subtotal = v_total,
         total = v_total,
         discount_amount = v_discount,
         updated_at = clock_timestamp()
   where id = v_invoice.id;

  perform public.recalculate_sales_invoice_payments(v_invoice.id);
  perform set_config('app.syncing_job_to_invoice', '', true);
exception
  when others then
    perform set_config('app.syncing_invoice_to_job', '', true);
    perform set_config('app.syncing_job_to_invoice', '', true);
    raise;
end;
$$;

revoke all on function public.sync_job_to_invoice(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.sync_job_to_invoice(uuid)
  to authenticated;

comment on function public.sync_job_to_invoice(uuid) is
  'Workshop-to-invoice sync preserving stable line IDs and technical metadata while locking invoice before job; invoices with financial history make the commercial projection an exact no-op.';

-- The guarded public invoice command must take the same order before entering
-- the private mature builder's existing-invoice retry branch. New invoices do
-- not yet have a competing invoice row, so the job lock remains sufficient for
-- their first atomic construction/link.
create or replace function public.create_billable_invoice_from_mechanic_job(
  p_job_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = public
set lock_timeout = '750ms'
as $$
declare
  v_preflight_tenant_id uuid;
  v_preflight_invoice_id uuid;
  v_job public.mechanic_jobs%rowtype;
  v_invoice_id uuid;
begin
  select job.tenant_id, job.invoice_id
    into v_preflight_tenant_id, v_preflight_invoice_id
  from public.mechanic_jobs job
  where job.id = p_job_id
    and job.deleted_at is null;
  if not found then
    raise exception 'Trabajo no encontrado.';
  end if;
  perform public.assert_workshop_rpc_tenant(v_preflight_tenant_id);

  if v_preflight_invoice_id is not null then
    select invoice.id into v_invoice_id
    from public.sales_invoices invoice
    where invoice.id = v_preflight_invoice_id
      and invoice.tenant_id = v_preflight_tenant_id
    for update;
    if not found then
      raise exception 'La factura vinculada al trabajo no existe en el mismo tenant.';
    end if;
  end if;

  select job.* into v_job
  from public.mechanic_jobs job
  where job.id = p_job_id
    and job.deleted_at is null
  for update;
  if not found then
    raise exception 'Trabajo no encontrado.';
  end if;
  if v_job.tenant_id is distinct from v_preflight_tenant_id
     or v_job.invoice_id is distinct from v_preflight_invoice_id then
    raise exception 'El vínculo financiero del trabajo cambió durante la facturación; vuelve a intentarlo'
      using errcode = '40001';
  end if;

  if v_job.workflow_kind = 'quotation' or v_job.job_type = 'quotation' then
    raise exception 'Una cotización no genera factura; primero debe aprobarse y convertirse.'
      using errcode = '23514';
  end if;

  -- Existing historical links may still be synchronized if their legacy
  -- intake classification awaits review. The invoice and job are already held
  -- in canonical order before the private builder reaches its retry branch.
  if v_job.invoice_id is not null then
    return public.create_invoice_from_mechanic_job_internal(v_job.id);
  end if;

  if v_job.mode_needs_review then
    raise exception 'Confirma si se recibió una bicicleta o solo un componente antes de facturar.'
      using errcode = '23514';
  end if;

  if v_job.workflow_kind in ('service', 'warranty')
     and v_job.intake_kind = 'bike'
     and v_job.bike_id is null
     and not exists (
       select 1 from public.mechanic_job_bikes job_bike
       where job_bike.tenant_id = v_job.tenant_id
         and job_bike.job_id = v_job.id
     ) then
    raise exception 'El servicio de bicicleta necesita una bicicleta asociada.'
      using errcode = '23514';
  end if;

  if v_job.workflow_kind in ('service', 'warranty')
     and v_job.intake_kind = 'component'
     and v_job.subject_id is null
     and nullif(btrim(coalesce(v_job.subject_notes, '')), '') is null then
    raise exception 'El servicio de componente necesita identificar el componente recibido.'
      using errcode = '23514';
  end if;

  if v_job.workflow_kind in ('service', 'warranty')
     and v_job.intake_kind = 'unspecified' then
    raise exception 'Confirma si se recibió una bicicleta o solo un componente antes de facturar.'
      using errcode = '23514';
  end if;

  if v_job.workflow_kind = 'warranty'
     and coalesce(v_job.warranty_outcome, 'pending') = 'pending' then
    raise exception 'La garantía debe resolverse antes de generar su documento interno o factura.'
      using errcode = '23514';
  end if;

  v_invoice_id := public.create_invoice_from_mechanic_job_internal(v_job.id);

  if v_invoice_id is not null
     and v_job.workflow_kind = 'warranty'
     and v_job.warranty_outcome = 'covered' then
    perform public.sync_job_to_invoice(v_job.id);
  end if;

  return v_invoice_id;
end;
$$;

revoke all on function public.create_billable_invoice_from_mechanic_job(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.create_billable_invoice_from_mechanic_job(uuid)
  to authenticated;

comment on function public.create_billable_invoice_from_mechanic_job(uuid) is
  'Canonical guarded invoice command for billable workshop modes; existing links lock invoice before job, while new invoices are built and linked atomically.';

-- Keep the existing invoice-owned warranty lifecycle byte-for-byte in spirit,
-- but make its operation key a strict receipt. A decision key may replay only
-- the same warranty job, event type, normalized outcome and normalized reason.
create or replace function public.decide_mechanic_job_warranty_claim(
  p_warranty_job_id uuid,
  p_outcome text,
  p_reason text,
  p_operation_key text
)
returns jsonb
language plpgsql
security definer
set search_path = public
set lock_timeout = '750ms'
as $$
declare
  v_job public.mechanic_jobs%rowtype;
  v_registration public.mechanic_job_warranty_claim_events%rowtype;
  v_event public.mechanic_job_warranty_claim_events%rowtype;
  v_preflight_tenant_id uuid;
  v_preflight_invoice_id uuid;
  v_invoice_id uuid;
  v_invoice public.sales_invoices%rowtype;
  v_operation_id uuid;
  v_has_financial_history boolean := false;
  v_outcome text := btrim(coalesce(p_outcome, ''));
  v_reason text := nullif(btrim(coalesce(p_reason, '')), '');
  v_operation_key text := btrim(coalesce(p_operation_key, ''));
begin
  if v_outcome not in ('pending', 'covered', 'not_covered') then
    raise exception 'Resultado de garantía inválido';
  end if;
  if v_operation_key = '' then
    raise exception 'La decisión de garantía requiere una clave de operación';
  end if;

  -- Resolve the current financial owner without taking a row lock, authorize
  -- the tenant, then follow the same invoice -> job lock order as the payment
  -- command and invoice triggers. This avoids the inverse job -> invoice edge
  -- that could deadlock against a payment posting. Revalidate the preflight
  -- relationship after both locks so a concurrent link/unlink never makes the
  -- decision operate on a different invoice than the one serialized here.
  select job.tenant_id, job.invoice_id
    into v_preflight_tenant_id, v_preflight_invoice_id
  from public.mechanic_jobs job
  where job.id = p_warranty_job_id;
  if not found then raise exception 'Trabajo de garantía no encontrado'; end if;
  perform public.assert_workshop_rpc_tenant(v_preflight_tenant_id);

  if v_preflight_invoice_id is not null then
    select invoice.* into v_invoice
    from public.sales_invoices invoice
    where invoice.id = v_preflight_invoice_id
      and invoice.tenant_id = v_preflight_tenant_id
    for update;
    if not found then
      raise exception 'La factura vinculada a la garantía no existe';
    end if;
    v_invoice_id := v_invoice.id;
  end if;

  select job.* into v_job
  from public.mechanic_jobs job
  where job.id = p_warranty_job_id
  for update;
  if not found then raise exception 'Trabajo de garantía no encontrado'; end if;
  if v_job.tenant_id is distinct from v_preflight_tenant_id
     or v_job.invoice_id is distinct from v_preflight_invoice_id then
    raise exception 'El vínculo financiero del trabajo cambió durante la decisión; vuelve a intentarlo'
      using errcode = '40001';
  end if;

  select * into v_event
  from public.mechanic_job_warranty_claim_events
  where tenant_id = v_job.tenant_id
    and operation_key = v_operation_key;
  if found then
    if v_event.warranty_job_id is distinct from v_job.id
       or v_event.event_type <> 'decision'
       or v_event.outcome <> v_outcome
       or nullif(btrim(coalesce(v_event.reason, '')), '')
            is distinct from v_reason then
      raise exception 'La clave de operación ya pertenece a otra decisión de garantía'
        using errcode = '23505';
    end if;
    return to_jsonb(v_event) || jsonb_build_object('replay', true);
  end if;

  select * into v_registration
  from public.mechanic_job_warranty_claim_events
  where tenant_id = v_job.tenant_id
    and warranty_job_id = v_job.id
    and event_type = 'registration'
  order by occurred_at desc, id desc
  limit 1;
  if not found then
    raise exception 'Primero vincula la garantía con el trabajo original';
  end if;

  -- The invoice lock above serializes this check with payment registration, so
  -- a payment cannot commit between this guard and the covered invoice sync.
  -- Whichever transaction wins makes the other re-evaluate authoritative
  -- invoice/payment state after the lock is released.
  if v_invoice.id is not null then
    select
      lower(coalesce(v_invoice.status, '')) in ('paid', 'pagado', 'pagada')
      or coalesce(v_invoice.paid_amount, 0) > 0
      or exists (
      select 1
      from public.sales_payments payment
      where payment.tenant_id = v_job.tenant_id
        and payment.invoice_id = v_job.invoice_id
        and payment.deleted_at is null
        and coalesce(payment.amount, 0) > 0
      )
    into v_has_financial_history;
  end if;

  if v_outcome = 'covered'
     and v_registration.eligibility <> 'within_window'
     and v_reason is null then
    raise exception 'Aceptar una garantía fuera de plazo o sin fecha requiere justificación';
  end if;
  if v_outcome = 'not_covered' and v_reason is null then
    raise exception 'Rechazar una garantía requiere una justificación';
  end if;
  if v_outcome = 'covered'
     and v_job.warranty_outcome is distinct from 'covered'
     and v_has_financial_history then
    raise exception 'No se puede marcar como cubierta una garantía con pagos vigentes; primero revierte o reembolsa el pago desde la factura';
  end if;
  if v_job.warranty_outcome = 'covered'
     and v_outcome <> 'covered'
     and v_has_financial_history then
    raise exception 'No se puede retirar la cobertura de una garantía con historial financiero; primero corrige el documento desde la factura';
  end if;

  insert into public.mechanic_job_warranty_claim_events (
    tenant_id,
    warranty_job_id,
    source_job_id,
    source_delivery_event_id,
    event_type,
    eligibility,
    warranty_expires_at_snapshot,
    outcome,
    reason,
    actor_id,
    operation_key,
    metadata
  ) values (
    v_job.tenant_id,
    v_job.id,
    v_registration.source_job_id,
    v_registration.source_delivery_event_id,
    'decision',
    v_registration.eligibility,
    v_registration.warranty_expires_at_snapshot,
    v_outcome,
    v_reason,
    auth.uid(),
    v_operation_key,
    jsonb_build_object('previous_outcome', v_job.warranty_outcome)
  ) returning * into v_event;

  -- Reversing a previously covered decision first returns the internal invoice
  -- to a non-posted state. The canonical invoice trigger restores inventory and
  -- removes the warranty-cost journal before billable prices are rebuilt.
  if v_job.warranty_outcome = 'covered'
     and v_outcome <> 'covered'
     and v_job.invoice_id is not null then
    update public.sales_invoices
    set status = 'draft', updated_at = clock_timestamp()
    where id = v_job.invoice_id
      and tenant_id = v_job.tenant_id
      and lower(status) not in (
        'draft','borrador','sent','enviado','enviada','issued','emitido','emitida',
        'cancelled','cancelado','cancelada','anulado','anulada'
      );
  end if;

  perform set_config('app.warranty_claim_rpc', 'true', true);
  update public.mechanic_jobs
  set warranty_outcome = v_outcome,
      is_warranty_job = true,
      updated_at = clock_timestamp()
  where id = v_job.id;
  perform set_config('app.warranty_claim_rpc', '', true);

  select invoice_id into v_invoice_id
  from public.mechanic_jobs
  where id = v_job.id;

  if v_invoice_id is null then
    v_invoice_id := public.create_invoice_from_mechanic_job(v_job.id);
    if v_invoice_id is not null then
      perform public.sync_job_to_invoice(v_job.id);
    end if;
  else
    -- The same RPC handles both sides safely: before settlement it projects
    -- job edits to the invoice; after financial history begins it leaves both
    -- commercial projections, payment, stock and journal rows exact.
    perform public.sync_job_to_invoice(v_job.id);
  end if;

  if v_outcome = 'covered'
     and public.mechanic_job_resolves_completion(v_job.status, v_job.status_id)
     and v_invoice_id is not null then
    update public.sales_invoices
    set status = 'confirmed', updated_at = clock_timestamp()
    where id = v_invoice_id
      and tenant_id = v_job.tenant_id
      and lower(status) in (
        'draft','borrador','sent','enviado','enviada','issued','emitido','emitida'
      );
  end if;

  v_operation_id := public.record_service_warranty_trace(
    v_job.tenant_id,
    v_job.id,
    v_operation_key,
    'warranty_claim_decided',
    jsonb_build_object('outcome', v_job.warranty_outcome),
    jsonb_build_object(
      'outcome', v_outcome,
      'eligibility', v_registration.eligibility,
      'reason', v_reason,
      'invoice_id', v_invoice_id
    ),
    jsonb_build_object('claim_event_id', v_event.id)
  );

  return to_jsonb(v_event) || jsonb_build_object(
    'invoice_id', v_invoice_id,
    'operation_id', v_operation_id,
    'replay', false
  );
exception
  when others then
    perform set_config('app.warranty_claim_rpc', '', true);
    raise;
end;
$$;

revoke all on function public.decide_mechanic_job_warranty_claim(
  uuid, text, text, text
) from public, anon, authenticated, service_role;
grant execute on function public.decide_mechanic_job_warranty_claim(
  uuid, text, text, text
) to authenticated;

comment on function public.decide_mechanic_job_warranty_claim(
  uuid, text, text, text
) is
  'Records the invoice-owned warranty decision atomically; an operation key replays only the exact job, decision outcome and normalized reason.';

notify pgrst, 'reload schema';

commit;
