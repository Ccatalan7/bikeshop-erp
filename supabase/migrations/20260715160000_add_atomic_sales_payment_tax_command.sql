-- Deployment status: DEPLOYED to production project xzdvtzdqjeyqxnkqprtf
-- on 2026-07-15. Atomic tax/payment canary FV-00884 paid CLP 3,000,
-- replayed idempotently, posted balanced invoice/payment journals and created
-- zero stock movements. Deployed SQL SHA-256 before annotation:
-- a3813411a648a4c429b0e81edfad117a8e95f421211078cbb5bfb75668a39dc6
-- Payment-terminal ownership for manual/workshop invoice tax without enabling
-- the broad historical repair drafted in 20260715120000.
begin;

create table if not exists public.sales_payment_command_receipts (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  idempotency_key text not null,
  payload_hash text not null check (payload_hash ~ '^[0-9a-f]{64}$'),
  payload_snapshot jsonb not null,
  response_snapshot jsonb not null,
  invoice_id uuid not null,
  payment_id uuid not null,
  created_by uuid references auth.users(id) on delete set null,
  completed_at timestamptz not null default clock_timestamp(),
  unique (tenant_id, idempotency_key)
);

comment on table public.sales_payment_command_receipts is
  'Immutable retry and forensic receipts for the atomic invoice-tax plus cash-settlement command.';
comment on column public.sales_payment_command_receipts.payload_hash is
  'Server-computed SHA-256 fingerprint of every normalized command input.';

create index if not exists idx_sales_payment_command_receipts_invoice
  on public.sales_payment_command_receipts(
    tenant_id, invoice_id, completed_at desc
  );

alter table public.sales_payment_command_receipts enable row level security;

drop policy if exists sales_payment_command_receipts_select
  on public.sales_payment_command_receipts;
create policy sales_payment_command_receipts_select
  on public.sales_payment_command_receipts
  for select to authenticated
  using (tenant_id = public.user_tenant_id());

revoke all on public.sales_payment_command_receipts
  from public, anon, authenticated, service_role;
grant select on public.sales_payment_command_receipts to authenticated;

create or replace function public.guard_sales_payment_command_receipt()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  raise exception 'Payment command receipts are immutable'
    using errcode = '55000';
end;
$$;

drop trigger if exists trg_sales_payment_command_receipts_immutable
  on public.sales_payment_command_receipts;
create trigger trg_sales_payment_command_receipts_immutable
  before update or delete on public.sales_payment_command_receipts
  for each row execute function public.guard_sales_payment_command_receipt();

revoke all on function public.guard_sales_payment_command_receipt()
  from public, anon, authenticated, service_role;

create or replace function public.assert_sales_payment_access(
  p_tenant_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid := auth.uid();
  v_role text;
  v_permissions jsonb := '{}'::jsonb;
  v_active_profile_count integer := 0;
begin
  if p_tenant_id is null then
    raise exception 'Payment tenant is required' using errcode = '42501';
  end if;

  -- Database triggers and migrations may run without an employee JWT. Anon
  -- PostgREST requests never receive this bypass.
  if v_actor is null then
    if coalesce(auth.role(), '') = 'anon' then
      raise exception 'Authenticated payment operator is required'
        using errcode = '42501';
    end if;
    return;
  end if;

  select count(*)::integer
    into v_active_profile_count
    from public.user_profiles profile
   where profile.user_id = v_actor
     and profile.is_active is true;

  if v_active_profile_count <> 1 then
    raise exception 'Exactly one active employee tenant is required'
      using errcode = '42501';
  end if;

  select profile.role, coalesce(profile.permissions, '{}'::jsonb)
    into v_role, v_permissions
    from public.user_profiles profile
   where profile.user_id = v_actor
     and profile.tenant_id = p_tenant_id
     and profile.is_active is true;

  if not found then
    raise exception 'Payment entity does not belong to the active employee tenant'
      using errcode = '42501';
  end if;

  if v_role not in ('admin', 'manager', 'cashier', 'accountant')
     and coalesce(v_permissions->'access_pos', 'false'::jsonb)
           is distinct from 'true'::jsonb
     and coalesce(v_permissions->'create_invoices', 'false'::jsonb)
           is distinct from 'true'::jsonb
     and coalesce(v_permissions->'access_accounting', 'false'::jsonb)
           is distinct from 'true'::jsonb then
    raise exception 'The active employee is not authorized to register payments'
      using errcode = '42501';
  end if;
end;
$$;

revoke all on function public.assert_sales_payment_access(uuid)
  from public, anon, authenticated, service_role;

create or replace function public.guard_sales_invoice_tax_ownership()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_payment_managed boolean;
begin
  -- POS, ecommerce and quick-sale checkouts are already atomic payment
  -- terminals. Manual and workshop invoices must classify tax only through
  -- register_sales_payment_with_invoice_tax().
  v_payment_managed := coalesce(NEW.source, OLD.source, '')
    not in ('pos', 'ecommerce', 'quick_sale');

  if v_payment_managed
     and NEW.tax_treatment is distinct from OLD.tax_treatment
     and auth.uid() is not null
     and current_setting('app.payment_tax_command', true)
           is distinct from 'true' then
    raise exception 'El IVA de la factura se controla únicamente desde el panel de pago.'
      using errcode = '42501';
  end if;
  return NEW;
end;
$$;

drop trigger if exists trg_sales_invoice_tax_ownership
  on public.sales_invoices;
create trigger trg_sales_invoice_tax_ownership
  before update of tax_treatment on public.sales_invoices
  for each row execute function public.guard_sales_invoice_tax_ownership();

revoke all on function public.guard_sales_invoice_tax_ownership()
  from public, anon, authenticated, service_role;

create or replace function public.validate_sales_payment_integrity()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_invoice public.sales_invoices%rowtype;
  v_existing_paid numeric(12,2);
  v_remaining numeric(12,2);
  v_amount numeric(12,2);
  v_net numeric(12,2);
begin
  if TG_OP = 'DELETE' then
    perform public.assert_sales_payment_access(OLD.tenant_id);
    return OLD;
  end if;

  if NEW.invoice_id is null then
    raise exception 'El pago debe pertenecer a una factura de venta.';
  end if;

  select * into v_invoice
    from public.sales_invoices
   where id = NEW.invoice_id
   for update;

  if not found then
    raise exception 'La factura de venta asociada al pago no existe.';
  end if;

  if NEW.tenant_id is null then
    NEW.tenant_id := v_invoice.tenant_id;
  end if;
  if NEW.tenant_id is distinct from v_invoice.tenant_id then
    raise exception 'El pago no pertenece al mismo tenant que la factura de venta.';
  end if;

  perform public.assert_sales_payment_access(NEW.tenant_id);

  v_amount := public.clp_round(NEW.amount);
  if v_amount <= 0 then
    raise exception 'El monto del pago debe ser mayor a cero.';
  end if;
  NEW.amount := v_amount;
  NEW.invoice_reference := coalesce(
    nullif(btrim(coalesce(NEW.invoice_reference, '')), ''),
    v_invoice.invoice_number
  );

  -- The payment is cash settlement only. Tax and revenue stay invoice-owned;
  -- this row mirrors the whole-document classification for reporting.
  NEW.tax_treatment := v_invoice.tax_treatment;
  if v_invoice.tax_treatment = 'tax_included' then
    v_net := public.clp_round(v_amount / 1.19);
    NEW.net_amount := v_net;
    NEW.iva_amount := v_amount - v_net;
  else
    NEW.net_amount := v_amount;
    NEW.iva_amount := 0;
  end if;

  if NEW.deleted_at is not null then
    return NEW;
  end if;

  if NEW.payment_method_id is null or not exists (
    select 1
      from public.payment_methods method
     where method.id = NEW.payment_method_id
       and method.tenant_id = NEW.tenant_id
       and coalesce(method.is_active, true)
  ) then
    raise exception 'Medio de pago no encontrado o inactivo para el tenant activo.';
  end if;

  select public.clp_round(coalesce(sum(payment.amount), 0))
    into v_existing_paid
    from public.sales_payments payment
   where payment.invoice_id = NEW.invoice_id
     and payment.tenant_id = NEW.tenant_id
     and payment.deleted_at is null
     and payment.id is distinct from NEW.id;

  v_remaining := public.clp_round(
    greatest(coalesce(v_invoice.total, 0) - v_existing_paid, 0)
  );
  if v_amount > v_remaining then
    raise exception 'El pago excede el saldo pendiente de la factura de venta. Saldo pendiente: %, monto enviado: %.',
      v_remaining, v_amount;
  end if;

  return NEW;
end;
$$;

drop trigger if exists trg_sales_payments_validate_integrity
  on public.sales_payments;
create trigger trg_sales_payments_validate_integrity
  before insert or update or delete on public.sales_payments
  for each row execute function public.validate_sales_payment_integrity();

revoke all on function public.validate_sales_payment_integrity()
  from public, anon, authenticated, service_role;

create or replace function public.register_sales_payment_with_invoice_tax(
  p_invoice_id uuid,
  p_payment_method_id uuid,
  p_idempotency_key text,
  p_amount numeric,
  p_date timestamptz,
  p_reference text,
  p_notes text,
  p_tax_treatment text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid := auth.uid();
  v_tenant uuid;
  v_invoice public.sales_invoices%rowtype;
  v_existing public.sales_payments%rowtype;
  v_payment public.sales_payments%rowtype;
  v_receipt public.sales_payment_command_receipts%rowtype;
  v_key text := btrim(coalesce(p_idempotency_key, ''));
  v_reference text := nullif(btrim(coalesce(p_reference, '')), '');
  v_notes text := nullif(btrim(coalesce(p_notes, '')), '');
  v_amount numeric := public.clp_round(p_amount);
  v_existing_paid numeric := 0;
  v_status text;
  v_payload jsonb;
  v_payload_hash text;
  v_response jsonb;
begin
  if v_actor is null then
    raise exception 'Authenticated payment operator is required'
      using errcode = '42501';
  end if;

  select profile.tenant_id
    into v_tenant
    from public.user_profiles profile
   where profile.user_id = v_actor
     and profile.is_active is true;
  perform public.assert_sales_payment_access(v_tenant);

  if p_tax_treatment not in ('no_tax', 'tax_included') then
    raise exception 'Tratamiento tributario inválido.';
  end if;
  if v_key = '' or length(v_key) > 128 then
    raise exception 'La clave idempotente del pago es obligatoria y admite hasta 128 caracteres.';
  end if;
  if v_amount <= 0 then
    raise exception 'El monto del pago debe ser mayor a cero.';
  end if;
  if p_date is null then
    raise exception 'La fecha del pago es obligatoria.';
  end if;
  if length(coalesce(v_reference, '')) > 512 then
    raise exception 'La referencia del pago admite hasta 512 caracteres.';
  end if;
  if length(coalesce(v_notes, '')) > 4000 then
    raise exception 'Las notas del pago admiten hasta 4000 caracteres.';
  end if;

  v_payload := jsonb_build_object(
    'invoice_id', p_invoice_id,
    'payment_method_id', p_payment_method_id,
    'amount_clp', v_amount,
    'date_epoch', extract(epoch from p_date),
    'reference', v_reference,
    'notes', v_notes,
    'tax_treatment', p_tax_treatment
  );
  v_payload_hash := encode(
    extensions.digest(v_payload::text, 'sha256'),
    'hex'
  );

  perform pg_advisory_xact_lock(
    hashtextextended(v_tenant::text || ':sales-payment:' || v_key, 0)
  );

  select * into v_receipt
    from public.sales_payment_command_receipts receipt
   where receipt.tenant_id = v_tenant
     and receipt.idempotency_key = v_key;
  if found then
    if v_receipt.payload_hash is distinct from v_payload_hash then
      raise exception 'La clave idempotente ya fue usada con otro contenido de pago.'
        using errcode = '23000';
    end if;
    return v_receipt.response_snapshot || jsonb_build_object('replayed', true);
  end if;

  select * into v_existing
    from public.sales_payments payment
   where payment.tenant_id = v_tenant
     and payment.idempotency_key = v_key;
  if found then
    if v_existing.invoice_id is distinct from p_invoice_id
       or v_existing.payment_method_id is distinct from p_payment_method_id
       or public.clp_round(v_existing.amount) is distinct from v_amount
       or v_existing.date is distinct from p_date
       or nullif(btrim(coalesce(v_existing.reference, '')), '')
            is distinct from v_reference
       or nullif(btrim(coalesce(v_existing.notes, '')), '')
            is distinct from v_notes
       or v_existing.tax_treatment is distinct from p_tax_treatment then
      raise exception 'La clave idempotente ya fue usada con otro contenido de pago.'
        using errcode = '23000';
    end if;

    v_response := jsonb_build_object(
      'payment', to_jsonb(v_existing),
      'invoice_id', v_existing.invoice_id,
      'replayed', false
    );
    insert into public.sales_payment_command_receipts(
      tenant_id, idempotency_key, payload_hash, payload_snapshot,
      response_snapshot, invoice_id, payment_id, created_by
    ) values (
      v_tenant, v_key, v_payload_hash, v_payload,
      v_response, v_existing.invoice_id, v_existing.id, v_actor
    );
    return v_response || jsonb_build_object('replayed', true);
  end if;

  select * into v_invoice
    from public.sales_invoices invoice
   where invoice.id = p_invoice_id
     and invoice.tenant_id = v_tenant
   for update;
  if not found then
    raise exception 'Factura no encontrada para el tenant activo.'
      using errcode = '42501';
  end if;

  if lower(v_invoice.status) in (
    'cancelled', 'cancelado', 'cancelada', 'anulado', 'anulada'
  ) then
    raise exception 'No se puede pagar una factura anulada.';
  end if;

  if not exists (
    select 1
      from public.payment_methods method
     where method.id = p_payment_method_id
       and method.tenant_id = v_tenant
       and coalesce(method.is_active, true)
  ) then
    raise exception 'Medio de pago no encontrado o inactivo para el tenant activo.';
  end if;

  select public.clp_round(coalesce(sum(payment.amount), 0))
    into v_existing_paid
    from public.sales_payments payment
   where payment.invoice_id = v_invoice.id
     and payment.tenant_id = v_tenant
     and payment.deleted_at is null;

  if v_existing_paid > 0
     and v_invoice.tax_treatment is distinct from p_tax_treatment then
    raise exception 'El tratamiento tributario quedó fijado con el primer pago. Use un flujo de corrección auditado para cambiarlo.'
      using errcode = '55000';
  end if;

  if v_amount > public.clp_round(
    greatest(v_invoice.total - v_existing_paid, 0)
  ) then
    raise exception 'El pago excede el saldo pendiente de la factura de venta.';
  end if;

  v_status := case
    when lower(v_invoice.status) in (
      'draft', 'borrador', 'sent', 'enviado', 'enviada',
      'issued', 'emitido', 'emitida'
    ) then 'confirmed'
    else v_invoice.status
  end;

  perform set_config('app.inventory_idempotency_key', v_key, true);
  perform set_config('app.payment_tax_command', 'true', true);
  update public.sales_invoices
     set tax_treatment = p_tax_treatment,
         status = v_status,
         updated_at = clock_timestamp()
   where id = v_invoice.id;
  perform set_config('app.payment_tax_command', '', true);

  insert into public.sales_payments (
    tenant_id, invoice_id, invoice_reference, payment_method_id,
    idempotency_key, amount, date, reference, notes, tax_treatment
  ) values (
    v_tenant, v_invoice.id, v_invoice.invoice_number, p_payment_method_id,
    v_key, v_amount, p_date, v_reference, v_notes, p_tax_treatment
  ) returning * into v_payment;

  v_response := jsonb_build_object(
    'payment', to_jsonb(v_payment),
    'invoice_id', v_invoice.id,
    'replayed', false
  );
  insert into public.sales_payment_command_receipts(
    tenant_id, idempotency_key, payload_hash, payload_snapshot,
    response_snapshot, invoice_id, payment_id, created_by
  ) values (
    v_tenant, v_key, v_payload_hash, v_payload,
    v_response, v_invoice.id, v_payment.id, v_actor
  );

  perform set_config('app.inventory_idempotency_key', '', true);
  return v_response;
exception
  when others then
    perform set_config('app.payment_tax_command', '', true);
    perform set_config('app.inventory_idempotency_key', '', true);
    raise;
end;
$$;

revoke all on function public.register_sales_payment_with_invoice_tax(
  uuid, uuid, text, numeric, timestamptz, text, text, text
) from public, anon, authenticated, service_role;
grant execute on function public.register_sales_payment_with_invoice_tax(
  uuid, uuid, text, numeric, timestamptz, text, text, text
) to authenticated;

comment on function public.register_sales_payment_with_invoice_tax(
  uuid, uuid, text, numeric, timestamptz, text, text, text
) is 'Atomic authorized payment command: fixes whole-invoice tax once, posts the document, settles cash, and records an immutable full-payload retry receipt.';

-- The broad repair drafted in 20260715120000 is intentionally unavailable.
-- Historical corrections must be split into reviewed, evidence-backed batches.
drop function if exists public.apply_workshop_invoice_backfill(uuid, text);

commit;
