-- Purpose:
--   Represent a product sale / installment-collection wrapper in the familiar
--   workshop table without pretending that a bicycle or loose component was
--   received. The linked sales invoice remains the exclusive owner of stock,
--   revenue, tax, receivable and payments.
--
-- Canonical mode:
--   workflow_kind = 'sale'
--   intake_kind   = 'none'
--   job_type      = 'service' (legacy compatibility facade)
--
-- Safety and recovery:
--   This migration contains no business-row backfill. It is additive and
--   idempotent. Older clients continue to see job_type = service. If the new
--   client is rolled back, leave the new values, immutable events and guards in
--   place. A separately reviewed migration owns any exact historical repair.

begin;

set local lock_timeout = '750ms';
set local statement_timeout = '30s';

-- ---------------------------------------------------------------------------
-- 1. Legacy-facade normalization for the new orthogonal pair
-- ---------------------------------------------------------------------------

create or replace function public.normalize_mechanic_job_mode_axes()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_axes_changed boolean := false;
  v_job_type_changed boolean := false;
begin
  if tg_op = 'UPDATE' then
    v_axes_changed := new.workflow_kind is distinct from old.workflow_kind
      or new.intake_kind is distinct from old.intake_kind;
    v_job_type_changed := new.job_type is distinct from old.job_type;
  end if;

  if tg_op = 'INSERT' then
    if new.job_type in ('quotation', 'warranty', 'item_service') then
      new.workflow_kind := case new.job_type
        when 'quotation' then 'quotation'
        when 'warranty' then 'warranty'
        else 'service'
      end;
      if new.job_type = 'item_service' then
        new.intake_kind := 'component';
      elsif new.intake_kind is null or new.intake_kind = 'unspecified' then
        new.intake_kind := case
          when new.subject_id is not null then 'component'
          when new.bike_id is not null then 'bike'
          else 'unspecified'
        end;
      end if;
    else
      new.workflow_kind := coalesce(new.workflow_kind, 'service');
      new.intake_kind := case
        when new.intake_kind is null or new.intake_kind = 'unspecified' then case
          when new.subject_id is not null then 'component'
          when new.bike_id is not null then 'bike'
          else 'unspecified'
        end
        else new.intake_kind
      end;
      new.job_type := case
        when new.workflow_kind = 'quotation' then 'quotation'
        when new.workflow_kind = 'warranty' then 'warranty'
        when new.workflow_kind = 'sale' then 'service'
        when new.intake_kind = 'component' then 'item_service'
        else 'service'
      end;
    end if;
  elsif v_axes_changed then
    new.job_type := case
      when new.workflow_kind = 'quotation' then 'quotation'
      when new.workflow_kind = 'warranty' then 'warranty'
      when new.workflow_kind = 'sale' then 'service'
      when new.intake_kind = 'component' then 'item_service'
      else 'service'
    end;
  elsif v_job_type_changed then
    new.workflow_kind := case new.job_type
      when 'quotation' then 'quotation'
      when 'warranty' then 'warranty'
      else 'service'
    end;
    new.intake_kind := case
      when new.job_type = 'item_service' then 'component'
      when new.subject_id is not null then 'component'
      when new.bike_id is not null then 'bike'
      else new.intake_kind
    end;
  elsif old.bike_id is null
     and new.bike_id is not null
     and new.workflow_kind in ('service', 'warranty')
     and new.intake_kind = 'unspecified' then
    new.intake_kind := 'bike';
    new.job_type := case
      when new.workflow_kind = 'warranty' then 'warranty'
      else 'service'
    end;
    new.mode_needs_review := false;
    new.mode_review_reason := null;
  end if;

  if new.workflow_kind = 'sale' and new.intake_kind = 'none' then
    new.job_type := 'service';
    new.mode_needs_review := false;
    new.mode_review_reason := null;
  elsif new.workflow_kind in ('service', 'warranty')
     and new.intake_kind = 'unspecified' then
    new.mode_needs_review := true;
    new.mode_review_reason := coalesce(
      nullif(btrim(new.mode_review_reason), ''),
      'system: falta confirmar bicicleta o componente recibido'
    );
  elsif new.intake_kind = 'component'
     and new.subject_id is null
     and nullif(btrim(coalesce(new.subject_notes, '')), '') is null then
    new.mode_needs_review := true;
    new.mode_review_reason := coalesce(
      nullif(btrim(new.mode_review_reason), ''),
      'system: falta identificar el componente recibido'
    );
  elsif new.mode_needs_review
     and coalesce(new.mode_review_reason, '') like 'system:%' then
    new.mode_needs_review := false;
    new.mode_review_reason := null;
  end if;

  if new.workflow_kind = 'quotation' then
    new.quotation_status := coalesce(new.quotation_status, 'pending');
    new.requires_approval := true;
  end if;

  return new;
end;
$$;

revoke all on function public.normalize_mechanic_job_mode_axes()
  from public, anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 2. Physical-anchor guards for a no-intake sale
-- ---------------------------------------------------------------------------

create or replace function public.guard_mechanic_job_sale_physical_anchor()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_workflow_kind text;
  v_intake_kind text;
begin
  if tg_table_name = 'mechanic_jobs' then
    if new.workflow_kind = 'sale' or new.intake_kind = 'none' then
      if new.workflow_kind is distinct from 'sale'
         or new.intake_kind is distinct from 'none' then
        raise exception 'La venta debe usar recepción sin objeto.'
          using errcode = '23514';
      end if;
      if new.job_type is distinct from 'service' then
        raise exception 'La venta debe conservar el tipo compatible service.'
          using errcode = '23514';
      end if;
      if new.bike_id is not null or new.subject_id is not null then
        raise exception 'Una venta sin recepción no puede asociar bicicleta ni componente.'
          using errcode = '23514';
      end if;
      if exists (
        select 1
        from public.mechanic_job_bikes job_bike
        where job_bike.tenant_id = new.tenant_id
          and job_bike.job_id = new.id
      ) then
        raise exception 'Una venta sin recepción no puede conservar bicicletas del trabajo.'
          using errcode = '23514';
      end if;
    end if;
    return new;
  end if;

  select job.workflow_kind, job.intake_kind
    into v_workflow_kind, v_intake_kind
  from public.mechanic_jobs job
  where job.id = new.job_id
    and job.tenant_id = new.tenant_id;

  if found and (v_workflow_kind = 'sale' or v_intake_kind = 'none') then
    raise exception 'Una venta sin recepción no admite bicicletas del trabajo.'
      using errcode = '23514';
  end if;

  return new;
end;
$$;

revoke all on function public.guard_mechanic_job_sale_physical_anchor()
  from public, anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 3. Paid commercial guard: one exact metadata-only classification exception
-- ---------------------------------------------------------------------------

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

  if current_setting(
       'app.mechanic_job_sale_classification_rpc', true
     ) = 'true'
     and old.job_type = 'service'
     and old.workflow_kind = 'service'
     and old.intake_kind = 'unspecified'
     and old.mode_needs_review
     and old.bike_id is null
     and old.subject_id is null
     and new.job_type = 'service'
     and new.workflow_kind = 'sale'
     and new.intake_kind = 'none'
     and not new.mode_needs_review
     and new.mode_review_reason is null
     and new.bike_id is null
     and new.subject_id is null
     and row(
       old.tenant_id, old.customer_id, old.service_package_id,
       old.subject_notes, old.discount_amount, old.invoice_id
     ) is not distinct from row(
       new.tenant_id, new.customer_id, new.service_package_id,
       new.subject_notes, new.discount_amount, new.invoice_id
     )
     and not exists (
       select 1
       from public.mechanic_job_bikes job_bike
       where job_bike.tenant_id = old.tenant_id
         and job_bike.job_id = old.id
     ) then
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

revoke all on function public.guard_paid_workshop_job_commercial_update()
  from public, anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 4. Audited/idempotent manual classification as product sale
-- ---------------------------------------------------------------------------

create or replace function public.classify_mechanic_job_as_sale(
  p_job_id uuid,
  p_reason text default null,
  p_operation_key uuid default gen_random_uuid()
)
returns jsonb
language plpgsql
security definer
set search_path = public
set lock_timeout = '750ms'
as $$
declare
  v_preflight_tenant_id uuid;
  v_preflight_invoice_id uuid;
  v_job public.mechanic_jobs%rowtype;
  v_updated public.mechanic_jobs%rowtype;
  v_invoice public.sales_invoices%rowtype;
  v_event public.mechanic_job_mode_events%rowtype;
  v_reason text := coalesce(
    nullif(btrim(coalesce(p_reason, '')), ''),
    'Venta de producto sin bicicleta ni componente recibido.'
  );
  v_operation_key text := coalesce(p_operation_key, gen_random_uuid())::text;
  v_request jsonb := jsonb_build_object(
    'classification', 'sale',
    'intake_kind', 'none',
    'reason', nullif(btrim(coalesce(p_reason, '')), '')
  );
  v_product_line_count integer := 0;
begin
  if p_job_id is null then
    raise exception 'Trabajo no encontrado.';
  end if;

  select job.tenant_id, job.invoice_id
    into v_preflight_tenant_id, v_preflight_invoice_id
  from public.mechanic_jobs job
  where job.id = p_job_id
    and job.deleted_at is null;
  if not found then
    raise exception 'Trabajo no encontrado.';
  end if;
  perform public.assert_workshop_rpc_tenant(v_preflight_tenant_id);

  -- Match the global payment/sync lock order: invoice first, then job.
  if v_preflight_invoice_id is not null then
    select invoice.* into v_invoice
    from public.sales_invoices invoice
    where invoice.id = v_preflight_invoice_id
      and invoice.tenant_id = v_preflight_tenant_id
    for update;
    if not found then
      raise exception 'La factura vinculada al trabajo no existe en el mismo negocio.'
        using errcode = '23514';
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
    raise exception 'El vínculo financiero del trabajo cambió; vuelve a intentarlo.'
      using errcode = '40001';
  end if;
  if v_invoice.id is not null
     and v_invoice.customer_id is distinct from v_job.customer_id then
    raise exception 'La factura vinculada no pertenece al cliente del trabajo.'
      using errcode = '23514';
  end if;

  select event.* into v_event
  from public.mechanic_job_mode_events event
  where event.tenant_id = v_job.tenant_id
    and event.operation_key = v_operation_key;
  if found then
    if v_event.job_id is distinct from v_job.id
       or v_event.event_type <> 'classified'
       or v_event.metadata->'request' is distinct from v_request
       or v_event.to_workflow_kind is distinct from 'sale'
       or v_event.to_intake_kind is distinct from 'none' then
      raise exception 'La clave de operación ya pertenece a otra clasificación de trabajo.'
        using errcode = '23505';
    end if;
    return jsonb_build_object(
      'job_id', v_event.job_id,
      'job_type', v_event.to_job_type,
      'workflow_kind', v_event.to_workflow_kind,
      'intake_kind', v_event.to_intake_kind,
      'event_id', v_event.id,
      'invoice_id', v_event.invoice_id,
      'replayed', true
    );
  end if;

  if v_job.job_type <> 'service'
     or v_job.workflow_kind <> 'service'
     or v_job.intake_kind <> 'unspecified'
     or not v_job.mode_needs_review then
    raise exception 'Solo un servicio pendiente de clasificación puede confirmarse como venta.'
      using errcode = '23514';
  end if;
  if v_job.bike_id is not null
     or v_job.subject_id is not null
     or exists (
       select 1
       from public.mechanic_job_bikes job_bike
       where job_bike.tenant_id = v_job.tenant_id
         and job_bike.job_id = v_job.id
     ) then
    raise exception 'El trabajo tiene una bicicleta o componente recibido y no puede clasificarse como venta.'
      using errcode = '23514';
  end if;
  if v_job.service_package_id is not null then
    raise exception 'Una venta de producto no puede conservar un paquete de servicio.'
      using errcode = '23514';
  end if;

  -- Lock existing lines while the job lock prevents new FK children. A sale
  -- needs at least one catalog product and cannot contain labor/service lines.
  perform item.id
  from public.mechanic_job_items item
  where item.tenant_id = v_job.tenant_id
    and item.job_id = v_job.id
  order by item.id
  for update;

  select count(*)::integer
    into v_product_line_count
  from public.mechanic_job_items item
  where item.tenant_id = v_job.tenant_id
    and item.job_id = v_job.id
    and item.item_type = 'product'
    and item.product_id is not null;

  if v_product_line_count = 0 then
    raise exception 'La venta necesita al menos un producto de catálogo.'
      using errcode = '23514';
  end if;
  if exists (
    select 1
    from public.mechanic_job_items item
    where item.tenant_id = v_job.tenant_id
      and item.job_id = v_job.id
      and item.item_type = 'service'
  ) then
    raise exception 'Una venta sin recepción no puede contener líneas de servicio de taller.'
      using errcode = '23514';
  end if;

  perform set_config('app.mechanic_job_mode_rpc', 'true', true);
  perform set_config(
    'app.mechanic_job_sale_classification_rpc', 'true', true
  );

  update public.mechanic_jobs job
  set job_type = 'service',
      workflow_kind = 'sale',
      intake_kind = 'none',
      mode_needs_review = false,
      mode_review_reason = null,
      updated_at = clock_timestamp()
  where job.id = v_job.id
    and job.tenant_id = v_job.tenant_id
  returning job.* into v_updated;

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
    invoice_id,
    reason,
    actor_id,
    operation_key,
    metadata
  ) values (
    v_updated.tenant_id,
    v_updated.id,
    'classified',
    v_job.job_type,
    v_updated.job_type,
    v_job.workflow_kind,
    v_updated.workflow_kind,
    v_job.intake_kind,
    v_updated.intake_kind,
    v_job.quotation_status,
    v_updated.quotation_status,
    v_updated.invoice_id,
    v_reason,
    auth.uid(),
    v_operation_key,
    jsonb_build_object(
      'request', v_request,
      'classification_source', 'manual-sale-confirmation-v1',
      'previous_review_reason', v_job.mode_review_reason,
      'product_line_count', v_product_line_count,
      'financial_effects_created', false
    )
  ) returning * into v_event;

  perform set_config('app.mechanic_job_sale_classification_rpc', '', true);
  perform set_config('app.mechanic_job_mode_rpc', '', true);

  return jsonb_build_object(
    'job_id', v_updated.id,
    'job_type', v_updated.job_type,
    'workflow_kind', v_updated.workflow_kind,
    'intake_kind', v_updated.intake_kind,
    'event_id', v_event.id,
    'invoice_id', v_updated.invoice_id,
    'replayed', false
  );
exception
  when others then
    perform set_config('app.mechanic_job_sale_classification_rpc', '', true);
    perform set_config('app.mechanic_job_mode_rpc', '', true);
    raise;
end;
$$;

revoke all on function public.classify_mechanic_job_as_sale(
  uuid, text, uuid
) from public, anon, authenticated, service_role;
grant execute on function public.classify_mechanic_job_as_sale(
  uuid, text, uuid
) to authenticated;

comment on function public.classify_mechanic_job_as_sale(
  uuid, text, uuid
) is
  'Audited idempotent command that confirms a review-flagged product-only workshop row as a sale with no physical intake and no financial rewrite.';

-- ---------------------------------------------------------------------------
-- 5. Explicit invoice entrypoint contract for sale / none
-- ---------------------------------------------------------------------------

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
  v_invoice public.sales_invoices%rowtype;
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
    select invoice.* into v_invoice
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

  if v_job.workflow_kind = 'sale' or v_job.intake_kind = 'none' then
    if v_job.workflow_kind <> 'sale'
       or v_job.intake_kind <> 'none'
       or v_job.job_type <> 'service'
       or v_job.mode_needs_review
       or v_job.bike_id is not null
       or v_job.subject_id is not null
       or v_job.service_package_id is not null
       or exists (
         select 1
         from public.mechanic_job_bikes job_bike
         where job_bike.tenant_id = v_job.tenant_id
           and job_bike.job_id = v_job.id
       ) then
      raise exception 'La venta debe estar clasificada sin bicicleta, componente ni paquete de servicio.'
        using errcode = '23514';
    end if;
    perform item.id
    from public.mechanic_job_items item
    where item.tenant_id = v_job.tenant_id
      and item.job_id = v_job.id
    order by item.id
    for share;
    if not exists (
      select 1
      from public.mechanic_job_items item
      where item.tenant_id = v_job.tenant_id
        and item.job_id = v_job.id
        and item.item_type = 'product'
        and item.product_id is not null
    ) then
      raise exception 'La venta necesita al menos un producto de catálogo.'
        using errcode = '23514';
    end if;
    if exists (
      select 1
      from public.mechanic_job_items item
      where item.tenant_id = v_job.tenant_id
        and item.job_id = v_job.id
        and item.item_type = 'service'
    ) then
      raise exception 'Una venta sin recepción no puede contener líneas de servicio de taller.'
        using errcode = '23514';
    end if;
  end if;

  -- Existing historical links may still be synchronized if their legacy
  -- intake classification awaits review. Sale rows have already passed their
  -- explicit no-intake and product-line contract above.
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
  'Canonical guarded invoice command for workshop services, warranties and product-only sale/none wrappers; the invoice remains the exclusive financial owner.';

-- ---------------------------------------------------------------------------
-- 6. Delivery remains operational, but a sale does not open service warranty
-- ---------------------------------------------------------------------------

create or replace function public.capture_mechanic_job_delivery_event()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_old_delivered boolean := false;
  v_new_delivered boolean;
  v_has_delivery boolean;
  v_starts_warranty boolean;
  v_occurred_at timestamptz := clock_timestamp();
begin
  if tg_op = 'UPDATE' then
    v_old_delivered := public.mechanic_job_resolves_delivery(
      old.status,
      old.status_id
    );
  end if;

  v_new_delivered := public.mechanic_job_resolves_delivery(
    new.status,
    new.status_id
  );

  if v_old_delivered or not v_new_delivered then
    return new;
  end if;

  select exists (
    select 1
    from public.mechanic_job_delivery_events event
    where event.tenant_id = new.tenant_id
      and event.job_id = new.id
      and event.event_kind in ('delivered', 'redelivered')
  ) into v_has_delivery;

  v_starts_warranty := not v_has_delivery
    and new.workflow_kind <> 'sale';

  insert into public.mechanic_job_delivery_events (
    tenant_id,
    job_id,
    event_kind,
    occurred_at,
    actor_id,
    starts_warranty_window,
    warranty_days_snapshot,
    warranty_started_at,
    warranty_expires_at,
    source,
    operation_key,
    metadata
  ) values (
    new.tenant_id,
    new.id,
    case when v_has_delivery then 'redelivered' else 'delivered' end,
    v_occurred_at,
    auth.uid(),
    v_starts_warranty,
    case when v_starts_warranty then 14 else null end,
    case when v_starts_warranty then v_occurred_at else null end,
    case when v_starts_warranty
      then v_occurred_at + interval '14 days'
      else null
    end,
    'status_transition',
    format(
      'delivery:auto:%s:%s:%s',
      new.id,
      txid_current(),
      gen_random_uuid()
    ),
    jsonb_build_object(
      'legacy_status', new.status,
      'custom_status_id', new.status_id,
      'warranty_reset', v_starts_warranty,
      'workflow_kind', new.workflow_kind,
      'sale_collection', new.workflow_kind = 'sale'
    )
  );

  return new;
end;
$$;

revoke all on function public.capture_mechanic_job_delivery_event()
  from public, anon, authenticated, service_role;

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
) warranty on true
where job.workflow_kind <> 'sale';

grant select on public.mechanic_job_service_warranty_view to authenticated;

comment on view public.mechanic_job_service_warranty_view is
  'Current delivery and service-warranty projection; product-sale collection wrappers are excluded even if legacy delivery evidence exists.';

-- Keep the mature warranty bodies behind private aliases and put the explicit
-- sale exclusion at their public entrypoints. The rename is guarded so both a
-- migration replay and an idempotent core_schema reapplication are safe.
do $$
begin
  if to_regprocedure(
    'public.extend_mechanic_job_service_warranty_mode_ledger(uuid,timestamp with time zone,text,text)'
  ) is null then
    if to_regprocedure(
      'public.extend_mechanic_job_service_warranty(uuid,timestamp with time zone,text,text)'
    ) is null then
      raise exception 'Missing service-warranty extension command required by sale-mode migration';
    end if;
    alter function public.extend_mechanic_job_service_warranty(
      uuid, timestamptz, text, text
    ) rename to extend_mechanic_job_service_warranty_mode_ledger;
  end if;
end;
$$;

revoke all on function public.extend_mechanic_job_service_warranty_mode_ledger(
  uuid, timestamptz, text, text
) from public, anon, authenticated, service_role;

create or replace function public.extend_mechanic_job_service_warranty(
  p_job_id uuid,
  p_new_expires_at timestamptz,
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
begin
  select job.* into v_job
  from public.mechanic_jobs job
  where job.id = p_job_id;
  if not found then
    raise exception 'Trabajo no encontrado';
  end if;
  perform public.assert_workshop_rpc_tenant(v_job.tenant_id);

  if v_job.workflow_kind = 'sale' or v_job.intake_kind = 'none' then
    raise exception 'Una venta de producto no tiene garantía de servicio técnico.'
      using errcode = '23514';
  end if;

  return public.extend_mechanic_job_service_warranty_mode_ledger(
    p_job_id,
    p_new_expires_at,
    p_reason,
    p_operation_key
  );
end;
$$;

revoke all on function public.extend_mechanic_job_service_warranty(
  uuid, timestamptz, text, text
) from public, anon, authenticated, service_role;
grant execute on function public.extend_mechanic_job_service_warranty(
  uuid, timestamptz, text, text
) to authenticated;

do $$
begin
  if to_regprocedure(
    'public.register_mechanic_job_warranty_claim_mode_070(uuid,uuid,text)'
  ) is null then
    if to_regprocedure(
      'public.register_mechanic_job_warranty_claim(uuid,uuid,text)'
    ) is null then
      raise exception 'Missing warranty registration command required by sale-mode migration';
    end if;
    alter function public.register_mechanic_job_warranty_claim(
      uuid, uuid, text
    ) rename to register_mechanic_job_warranty_claim_mode_070;
  end if;
end;
$$;

revoke all on function public.register_mechanic_job_warranty_claim_mode_070(
  uuid, uuid, text
) from public, anon, authenticated, service_role;

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
  v_tenant_id uuid;
  v_source_workflow_kind text;
  v_source_intake_kind text;
begin
  select job.tenant_id into v_tenant_id
  from public.mechanic_jobs job
  where job.id = p_warranty_job_id;
  if not found then
    raise exception 'Trabajo de garantía no encontrado';
  end if;
  perform public.assert_workshop_rpc_tenant(v_tenant_id);

  select job.workflow_kind, job.intake_kind
    into v_source_workflow_kind, v_source_intake_kind
  from public.mechanic_jobs job
  where job.id = p_source_job_id
    and job.tenant_id = v_tenant_id;
  if not found then
    raise exception 'Trabajo original no encontrado';
  end if;

  if v_source_workflow_kind = 'sale' or v_source_intake_kind = 'none' then
    raise exception 'Una venta de producto no puede originar una garantía de servicio técnico.'
      using errcode = '23514';
  end if;

  return public.register_mechanic_job_warranty_claim_mode_070(
    p_warranty_job_id,
    p_source_job_id,
    p_operation_key
  );
end;
$$;

revoke all on function public.register_mechanic_job_warranty_claim(
  uuid, uuid, text
) from public, anon, authenticated, service_role;
grant execute on function public.register_mechanic_job_warranty_claim(
  uuid, uuid, text
) to authenticated;

comment on function public.extend_mechanic_job_service_warranty(
  uuid, timestamptz, text, text
) is
  'Extends a service-warranty window and explicitly rejects product-sale collection wrappers.';
comment on function public.register_mechanic_job_warranty_claim(
  uuid, uuid, text
) is
  'Registers a canonical bicycle/component service warranty and explicitly rejects product-sale collection sources.';

-- ---------------------------------------------------------------------------
-- 7. Short bounded DDL window for checks and trigger wiring
-- ---------------------------------------------------------------------------

lock table
  public.mechanic_jobs,
  public.mechanic_job_bikes
  in access exclusive mode nowait;

alter table public.mechanic_jobs
  drop constraint if exists mechanic_jobs_workflow_kind_check;
alter table public.mechanic_jobs
  add constraint mechanic_jobs_workflow_kind_check
  check (workflow_kind in ('service', 'quotation', 'warranty', 'sale'))
  not valid;

alter table public.mechanic_jobs
  drop constraint if exists mechanic_jobs_intake_kind_check;
alter table public.mechanic_jobs
  add constraint mechanic_jobs_intake_kind_check
  check (intake_kind in ('bike', 'component', 'unspecified', 'none'))
  not valid;

alter table public.mechanic_jobs
  drop constraint if exists mechanic_jobs_sale_intake_pair_check;
alter table public.mechanic_jobs
  add constraint mechanic_jobs_sale_intake_pair_check
  check (
    (workflow_kind = 'sale' and intake_kind = 'none')
    or (workflow_kind <> 'sale' and intake_kind <> 'none')
  ) not valid;

alter table public.mechanic_jobs
  drop constraint if exists mechanic_jobs_sale_no_physical_anchor_check;
alter table public.mechanic_jobs
  add constraint mechanic_jobs_sale_no_physical_anchor_check
  check (
    workflow_kind <> 'sale'
    or (
      job_type = 'service'
      and bike_id is null
      and subject_id is null
      and not mode_needs_review
      and mode_review_reason is null
    )
  ) not valid;

alter table public.mechanic_jobs
  validate constraint mechanic_jobs_workflow_kind_check;
alter table public.mechanic_jobs
  validate constraint mechanic_jobs_intake_kind_check;
alter table public.mechanic_jobs
  validate constraint mechanic_jobs_sale_intake_pair_check;
alter table public.mechanic_jobs
  validate constraint mechanic_jobs_sale_no_physical_anchor_check;

drop trigger if exists trg_mechanic_jobs_guard_sale_anchor
  on public.mechanic_jobs;
create trigger trg_mechanic_jobs_guard_sale_anchor
  before insert or update of
    job_type,
    workflow_kind,
    intake_kind,
    bike_id,
    subject_id,
    mode_needs_review,
    mode_review_reason
  on public.mechanic_jobs
  for each row execute function public.guard_mechanic_job_sale_physical_anchor();

drop trigger if exists trg_mechanic_job_bikes_guard_sale_anchor
  on public.mechanic_job_bikes;
create trigger trg_mechanic_job_bikes_guard_sale_anchor
  before insert or update of tenant_id, job_id, bike_id
  on public.mechanic_job_bikes
  for each row execute function public.guard_mechanic_job_sale_physical_anchor();

-- Migration 070 created this trigger against the previous function OID. Rewire
-- it explicitly so an idempotent core_schema replay cannot retain stale logic.
drop trigger if exists trg_mechanic_jobs_guard_paid_commercial_snapshot
  on public.mechanic_jobs;
create trigger trg_mechanic_jobs_guard_paid_commercial_snapshot
  before update of customer_id, bike_id, service_package_id, job_type,
    workflow_kind, intake_kind, mode_needs_review, mode_review_reason,
    subject_id, subject_notes, discount_amount
  on public.mechanic_jobs
  for each row execute function public.guard_paid_workshop_job_commercial_update();

notify pgrst, 'reload schema';

commit;
