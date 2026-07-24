-- Deployment status: DEPLOYED AND VERIFIED in production.
-- Project: xzdvtzdqjeyqxnkqprtf on 2026-07-24.
-- Exact deployed SQL SHA-256 before this status annotation:
-- e68345d79a6f625d193657a70514a1446219e42ab8e67fec4c49033603e72b65
-- Adds the replay-safe, optimistic and payment-owned correction command for
-- supplier payments. A purchase payment settles accounts payable only; the
-- purchase invoice, credit-note, refund and receipt workflows retain ownership
-- of purchase value, IVA, supplier credit and physical inventory.
--
-- Recovery: roll the client back to read-only supplier-payment details, revoke
-- the two RPC grants, and remove the correction-command guard trigger. Preserve
-- purchase_payment_edit_events and journal_supersession_evidence permanently;
-- never delete committed accounting or correction history.
begin;

do $$
begin
  if not exists (
    select 1
      from pg_constraint
     where conrelid = 'public.purchase_payments'::regclass
       and conname = 'purchase_payments_tenant_id_id_key'
  ) then
    alter table public.purchase_payments
      add constraint purchase_payments_tenant_id_id_key
      unique (tenant_id, id);
  end if;
end;
$$;

create table if not exists public.purchase_payment_edit_events (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  payment_id uuid not null,
  invoice_id uuid not null
    references public.purchase_invoices(id) on delete restrict,
  operation_key text not null,
  request_hash text not null check (request_hash ~ '^[0-9a-f]{64}$'),
  request_snapshot jsonb not null,
  reason text not null check (length(btrim(reason)) between 3 and 1000),
  financial_fields_changed boolean not null,
  legacy_journal_relinked boolean not null,
  before_snapshot jsonb not null,
  after_snapshot jsonb not null,
  trace_operation_id uuid not null,
  prior_journal_entry_id uuid not null,
  current_journal_entry_id uuid not null,
  response_snapshot jsonb not null,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default clock_timestamp(),
  unique (tenant_id, operation_key),
  foreign key (tenant_id, payment_id)
    references public.purchase_payments(tenant_id, id) on delete restrict,
  foreign key (tenant_id, trace_operation_id)
    references public.inventory_accounting_operations(tenant_id, id)
    on delete restrict
);

comment on table public.purchase_payment_edit_events is
  'Immutable tenant-scoped command receipts and before/after evidence for audited supplier-payment corrections.';
comment on column public.purchase_payment_edit_events.financial_fields_changed is
  'True when amount, payment date, or payment method changed and the accounts-payable settlement journal was superseded.';
comment on column public.purchase_payment_edit_events.legacy_journal_relinked is
  'True when one uniquely attributable invoice-number journal was preserved and replaced by the canonical payment-UUID journal.';
comment on column public.purchase_payment_edit_events.response_snapshot is
  'Exact successful RPC response used for committed-but-unacknowledged readback and replay.';

create index if not exists idx_purchase_payment_edit_events_payment
  on public.purchase_payment_edit_events(
    tenant_id, payment_id, created_at desc, id desc
  );
create index if not exists idx_purchase_payment_edit_events_trace
  on public.purchase_payment_edit_events(tenant_id, trace_operation_id);

alter table public.purchase_payment_edit_events enable row level security;

drop policy if exists purchase_payment_edit_events_select
  on public.purchase_payment_edit_events;
create policy purchase_payment_edit_events_select
  on public.purchase_payment_edit_events
  for select to authenticated
  using (tenant_id = public.user_tenant_id());

revoke all on public.purchase_payment_edit_events
  from public, anon, authenticated, service_role;
grant select on public.purchase_payment_edit_events to authenticated;

create or replace function public.guard_purchase_payment_edit_event()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  raise exception 'Purchase payment edit events are immutable'
    using errcode = '55000';
end;
$$;

drop trigger if exists trg_purchase_payment_edit_events_immutable
  on public.purchase_payment_edit_events;
create trigger trg_purchase_payment_edit_events_immutable
  before update or delete on public.purchase_payment_edit_events
  for each row execute function public.guard_purchase_payment_edit_event();

revoke all on function public.guard_purchase_payment_edit_event()
  from public, anon, authenticated, service_role;

create or replace function public.assert_purchase_payment_access(
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
    raise exception 'Purchase payment tenant is required'
      using errcode = '42501';
  end if;

  -- Trusted triggers and migrations run without an employee subject. Anonymous
  -- PostgREST traffic never receives this compatibility bypass.
  if v_actor is null then
    if coalesce(auth.role(), '') = 'anon' then
      raise exception 'Authenticated purchase payment operator is required'
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
    raise exception
      'Purchase payment does not belong to the active employee tenant'
      using errcode = '42501';
  end if;

  if v_role not in ('admin', 'manager', 'cashier', 'accountant')
     and coalesce(v_permissions->'create_invoices', 'false'::jsonb)
           is distinct from 'true'::jsonb
     and coalesce(v_permissions->'access_accounting', 'false'::jsonb)
           is distinct from 'true'::jsonb then
    raise exception
      'The active employee is not authorized to manage purchase payments'
      using errcode = '42501';
  end if;
end;
$$;

revoke all on function public.assert_purchase_payment_access(uuid)
  from public, anon, authenticated, service_role;

-- Authenticated employees must use the audited RPC for editable fields. The
-- existing trusted trigger/migration path remains available without auth.uid().
create or replace function public.guard_purchase_payment_correction_command()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    return NEW;
  end if;

  if NEW.id is distinct from OLD.id
     or NEW.tenant_id is distinct from OLD.tenant_id
     or NEW.invoice_id is distinct from OLD.invoice_id
     or NEW.idempotency_key is distinct from OLD.idempotency_key
     or NEW.deleted_at is distinct from OLD.deleted_at
     or NEW.deleted_by is distinct from OLD.deleted_by
     or NEW.created_at is distinct from OLD.created_at then
    raise exception 'Purchase payment identity is immutable'
      using errcode = 'check_violation';
  end if;

  if (
    NEW.payment_method_id is distinct from OLD.payment_method_id
    or NEW.amount is distinct from OLD.amount
    or NEW.date is distinct from OLD.date
    or NEW.reference is distinct from OLD.reference
    or NEW.notes is distinct from OLD.notes
  ) and current_setting(
    'app.purchase_payment_correction_command',
    true
  ) is distinct from 'true' then
    raise exception 'Use the audited purchase-payment correction command'
      using errcode = 'insufficient_privilege';
  end if;

  return NEW;
end;
$$;

drop trigger if exists trg_purchase_payments_01_correction_command
  on public.purchase_payments;
create trigger trg_purchase_payments_01_correction_command
  before update on public.purchase_payments
  for each row
  execute function public.guard_purchase_payment_correction_command();

revoke all on function public.guard_purchase_payment_correction_command()
  from public, anon, authenticated, service_role;

-- A correction may preserve its historical inactive method, but neither a new
-- payment nor a method change may select an inactive method. Reference
-- requirements are server-owned rather than merely form validation.
create or replace function public.validate_purchase_payment_integrity()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_invoice public.purchase_invoices%rowtype;
  v_existing_paid numeric(12,2);
  v_remaining numeric(12,2);
  v_amount numeric(12,2);
  v_requires_reference boolean;
begin
  if TG_OP = 'DELETE' then
    perform public.assert_purchase_payment_access(OLD.tenant_id);
    return OLD;
  end if;

  v_amount := public.clp_round(NEW.amount);
  if v_amount <= 0 then
    raise exception 'El monto del pago debe ser mayor a cero.';
  end if;
  NEW.amount := v_amount;
  NEW.reference := nullif(btrim(coalesce(NEW.reference, '')), '');
  NEW.notes := nullif(btrim(coalesce(NEW.notes, '')), '');

  if NEW.deleted_at is not null then
    perform public.assert_purchase_payment_access(NEW.tenant_id);
    return NEW;
  end if;

  if NEW.invoice_id is null then
    raise exception 'El pago debe pertenecer a una factura de compra.';
  end if;

  select * into v_invoice
    from public.purchase_invoices invoice
   where invoice.id = NEW.invoice_id
   for update;

  if not found then
    raise exception 'La factura de compra asociada al pago no existe.';
  end if;

  if NEW.tenant_id is null then
    NEW.tenant_id := v_invoice.tenant_id;
  end if;
  if NEW.tenant_id is distinct from v_invoice.tenant_id then
    raise exception
      'El pago no pertenece al mismo tenant que la factura de compra.';
  end if;

  perform public.assert_purchase_payment_access(NEW.tenant_id);

  select method.requires_reference
    into v_requires_reference
    from public.payment_methods method
   where method.id = NEW.payment_method_id
     and method.tenant_id = NEW.tenant_id
     and (
       method.is_active is true
       or (
         TG_OP = 'UPDATE'
         and NEW.payment_method_id is not distinct from OLD.payment_method_id
         and current_setting(
           'app.purchase_payment_correction_command',
           true
         ) = 'true'
       )
     );

  if not found then
    raise exception
      'Medio de pago no encontrado o inactivo para el tenant activo.';
  end if;
  if v_requires_reference and NEW.reference is null then
    raise exception 'Este medio de pago requiere una referencia.';
  end if;

  select public.clp_round(coalesce(sum(payment.amount), 0))
    into v_existing_paid
    from public.purchase_payments payment
   where payment.invoice_id = NEW.invoice_id
     and payment.tenant_id = NEW.tenant_id
     and payment.deleted_at is null
     and payment.id is distinct from NEW.id;

  v_remaining := public.clp_round(
    greatest(coalesce(v_invoice.total, 0) - v_existing_paid, 0)
  );
  if v_amount > v_remaining then
    raise exception
      'El pago excede el saldo pendiente de la factura de compra. Saldo pendiente: %, monto enviado: %.',
      v_remaining, v_amount;
  end if;

  return NEW;
end;
$$;

revoke all on function public.validate_purchase_payment_integrity()
  from public, anon, authenticated, service_role;

drop trigger if exists trg_purchase_payments_validate_integrity
  on public.purchase_payments;
create trigger trg_purchase_payments_validate_integrity
  before insert or update on public.purchase_payments
  for each row execute function public.validate_purchase_payment_integrity();

-- Existing purchase journals can use either the canonical payment UUID or a
-- historical invoice number. Never remove a UUID journal while silently
-- ignoring a second legacy candidate, and never invent a missing journal.
create or replace function public.delete_purchase_payment_journal_entry(
  p_payment_id uuid,
  p_invoice_id uuid,
  p_tenant_id uuid,
  p_expected_amount numeric
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_invoice_number text;
  v_id_journal_count integer;
  v_legacy_journal_count integer;
  v_matching_legacy_count integer;
begin
  if p_payment_id is null then
    return;
  end if;

  select invoice.invoice_number
    into v_invoice_number
    from public.purchase_invoices invoice
   where invoice.id = p_invoice_id
     and invoice.tenant_id = p_tenant_id;

  select count(*)::integer
    into v_id_journal_count
    from public.journal_entries entry
   where entry.tenant_id = p_tenant_id
     and entry.source_module = 'purchase_payments'
     and entry.source_reference = p_payment_id::text;

  select
    count(*)::integer,
    count(*) filter (
      where public.clp_round(entry.total_debit)
              = public.clp_round(p_expected_amount)
        and public.clp_round(entry.total_credit)
              = public.clp_round(p_expected_amount)
        and lower(entry.status) = 'posted'
    )::integer
    into v_legacy_journal_count, v_matching_legacy_count
    from public.journal_entries entry
   where entry.tenant_id = p_tenant_id
     and entry.source_module = 'purchase_payments'
     and v_invoice_number is not null
     and entry.source_reference = v_invoice_number;

  if v_id_journal_count > 1
     or (v_id_journal_count = 1 and v_legacy_journal_count > 0) then
    raise exception
      'Purchase payment % has mixed or duplicate current journals; correction stopped for accounting review',
      p_payment_id
      using errcode = 'check_violation';
  elsif v_id_journal_count = 1 then
    delete from public.journal_entries entry
     where entry.tenant_id = p_tenant_id
       and entry.source_module = 'purchase_payments'
       and entry.source_reference = p_payment_id::text;
    return;
  end if;

  if v_legacy_journal_count = 0 then
    raise exception
      'Purchase payment % has no recognized settlement journal; correction stopped for accounting review',
      p_payment_id
      using errcode = 'check_violation';
  end if;

  if v_legacy_journal_count <> 1 or v_matching_legacy_count <> 1 then
    raise exception
      'Legacy purchase payment journals for invoice % are ambiguous (journals %, matching amount %); correction stopped for accounting review',
      v_invoice_number, v_legacy_journal_count, v_matching_legacy_count
      using errcode = 'check_violation';
  end if;

  delete from public.journal_entries entry
   where entry.tenant_id = p_tenant_id
     and entry.source_module = 'purchase_payments'
     and entry.source_reference = v_invoice_number;
end;
$$;

revoke all on function public.delete_purchase_payment_journal_entry(
  uuid, uuid, uuid, numeric
) from public, anon, authenticated, service_role;

-- These legacy SECURITY DEFINER helpers are trigger internals, not client
-- commands. Leaving either overload executable through PostgREST would allow a
-- caller to create a duplicate settlement journal or delete posted accounting
-- evidence without the audited correction command.
revoke all on function public.create_purchase_payment_journal_entry(uuid)
  from public, anon, authenticated, service_role;
revoke all on function public.delete_purchase_payment_journal_entry(uuid)
  from public, anon, authenticated, service_role;

-- The CLP normalizer predates purchase credit notes and supplier refunds. Its
-- old total-minus-gross-paid assignment overwrote the canonical settlement
-- function's balance in a BEFORE UPDATE trigger. Normalize the same stored
-- settlement components without discarding credit/refund accounting.
create or replace function public.normalize_purchase_invoice_clp_amounts()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_total numeric;
  v_net numeric;
  v_gross_paid numeric;
  v_credited numeric;
  v_refunded numeric;
  v_net_paid numeric;
  v_effective_total numeric;
begin
  v_total := public.clp_round(NEW.total);
  v_gross_paid := public.clp_round(NEW.paid_amount);
  v_credited := public.clp_round(
    coalesce(NEW.credited_amount, 0)
  );
  v_refunded := public.clp_round(
    coalesce(NEW.supplier_refunded_amount, 0)
  );
  v_net_paid := greatest(v_gross_paid - v_refunded, 0);
  v_effective_total := greatest(v_total - v_credited, 0);

  NEW.total := v_total;
  NEW.paid_amount := v_gross_paid;
  NEW.credited_amount := v_credited;
  NEW.supplier_refunded_amount := v_refunded;
  NEW.supplier_credit_balance := greatest(
    v_net_paid - v_effective_total,
    0
  );
  NEW.discount_amount := public.clp_round(NEW.discount_amount);

  if NEW.tax_treatment = 'tax_included' and v_total <> 0 then
    v_net := public.clp_round(v_total / 1.19);
    NEW.net_amount := v_net;
    NEW.subtotal := v_net;
    NEW.tax := v_total - v_net;
    NEW.iva_amount := NEW.tax;
  else
    NEW.net_amount := v_total;
    NEW.subtotal := v_total;
    NEW.tax := 0;
    NEW.iva_amount := 0;
  end if;

  NEW.balance := greatest(v_effective_total - v_net_paid, 0);
  return NEW;
end;
$$;

-- Production still has an older, redundant BEFORE trigger that runs after the
-- normalizer and overwrites the canonical balance with total-minus-gross-paid.
-- Core and fresh schemas no longer install it. Remove only that trigger so
-- normalize_purchase_invoice_clp_amounts remains the single row-normalization
-- owner; leave the historical function itself inert for recovery evidence.
drop trigger if exists trg_update_purchase_invoice_balance
  on public.purchase_invoices;

-- The latest composed schema had also reintroduced the pre-credit payment
-- recalculation. Keep the compatibility entry point as a thin wrapper around
-- the canonical purchase settlement owner so both paths remain identical.
create or replace function public.recalculate_purchase_invoice_payments(
  p_invoice_id uuid
) returns void
language plpgsql
set search_path = public
as $$
begin
  perform public.recalculate_purchase_invoice_settlement(p_invoice_id);
end;
$$;

-- Canonical reference/notes-only updates leave the settlement journal intact.
-- A uniquely proven legacy journal still relinks once to the payment UUID.
create or replace function public.handle_purchase_payment_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_invoice_number text;
  v_uuid_journal_count integer := 0;
  v_legacy_journal_count integer := 0;
begin
  if TG_OP = 'INSERT' then
    perform public.create_purchase_payment_journal_entry(NEW.id);
    perform public.recalculate_purchase_invoice_payments(NEW.invoice_id);
  elsif TG_OP = 'UPDATE' then
    if NEW.tenant_id is not distinct from OLD.tenant_id
       and NEW.invoice_id is not distinct from OLD.invoice_id
       and NEW.payment_method_id is not distinct from OLD.payment_method_id
       and NEW.amount is not distinct from OLD.amount
       and NEW.date is not distinct from OLD.date
       and NEW.deleted_at is not distinct from OLD.deleted_at then
      select invoice.invoice_number
        into v_invoice_number
        from public.purchase_invoices invoice
       where invoice.id = OLD.invoice_id
         and invoice.tenant_id = OLD.tenant_id;

      select count(*)::integer
        into v_uuid_journal_count
        from public.journal_entries entry
       where entry.tenant_id = OLD.tenant_id
         and entry.source_module = 'purchase_payments'
         and entry.source_reference = OLD.id::text;

      select count(*)::integer
        into v_legacy_journal_count
        from public.journal_entries entry
       where entry.tenant_id = OLD.tenant_id
         and entry.source_module = 'purchase_payments'
         and v_invoice_number is not null
         and entry.source_reference = v_invoice_number;

      if v_uuid_journal_count = 1 and v_legacy_journal_count = 0 then
        return NEW;
      end if;
    end if;

    if NEW.invoice_id is distinct from OLD.invoice_id then
      perform public.recalculate_purchase_invoice_payments(OLD.invoice_id);
    end if;
    perform public.delete_purchase_payment_journal_entry(
      OLD.id, OLD.invoice_id, OLD.tenant_id, OLD.amount
    );
    perform public.create_purchase_payment_journal_entry(NEW.id);
    perform public.recalculate_purchase_invoice_payments(NEW.invoice_id);
  elsif TG_OP = 'DELETE' then
    perform public.delete_purchase_payment_journal_entry(
      OLD.id, OLD.invoice_id, OLD.tenant_id, OLD.amount
    );
    perform public.recalculate_purchase_invoice_payments(OLD.invoice_id);
  end if;
  return null;
end;
$$;

revoke all on function public.handle_purchase_payment_change()
  from public, anon, authenticated, service_role;

drop trigger if exists trg_purchase_payments_change
  on public.purchase_payments;
create trigger trg_purchase_payments_change
  after insert or update or delete on public.purchase_payments
  for each row execute function public.handle_purchase_payment_change();

-- The shared payment trace predates purchase credit notes and supplier cash
-- refunds. Reconcile the purchase invoice against gross payments, posted
-- credits and posted refunds instead of the obsolete total-minus-gross formula.
create or replace function public.complete_invoice_payment_trace()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_operation_text text;
  v_operation_id uuid;
  v_tenant_id uuid;
  v_payment_id uuid;
  v_invoice_id uuid;
  v_document_type text;
  v_invoice_type text;
  v_invoice_after jsonb;
  v_invoice_total numeric;
  v_invoice_paid numeric;
  v_invoice_balance numeric;
  v_invoice_status text;
  v_received_date timestamp with time zone;
  v_invoice_credited numeric := 0;
  v_invoice_refunded numeric := 0;
  v_invoice_credit_balance numeric := 0;
  v_ledger_paid numeric;
  v_ledger_credited numeric := 0;
  v_ledger_refunded numeric := 0;
  v_net_paid numeric;
  v_effective_total numeric;
  v_expected_balance numeric;
  v_expected_credit_balance numeric := 0;
  v_payment_active boolean;
  v_payment_journal_count integer;
  v_stock_movement_count integer;
  v_job_paid_mismatch integer := 0;
begin
  v_operation_text := nullif(
    current_setting('app.inventory_operation_id', true),
    ''
  );
  if v_operation_text is null then
    return case when TG_OP = 'DELETE' then OLD else NEW end;
  end if;

  v_operation_id := v_operation_text::uuid;
  v_tenant_id := case
    when TG_OP = 'DELETE' then OLD.tenant_id
    else NEW.tenant_id
  end;
  v_payment_id := case
    when TG_OP = 'DELETE' then OLD.id
    else NEW.id
  end;
  v_invoice_id := case
    when TG_OP = 'DELETE' then OLD.invoice_id
    else NEW.invoice_id
  end;
  v_payment_active := TG_OP <> 'DELETE' and NEW.deleted_at is null;

  if TG_TABLE_NAME = 'sales_payments' then
    v_document_type := 'sales_payment';
    v_invoice_type := 'sales_invoice';
    select
      public.inventory_trace_document_snapshot(to_jsonb(invoice)),
      public.clp_round(invoice.total),
      public.clp_round(invoice.paid_amount),
      public.clp_round(invoice.balance),
      invoice.status,
      null::timestamp with time zone
      into v_invoice_after, v_invoice_total, v_invoice_paid,
           v_invoice_balance, v_invoice_status, v_received_date
      from public.sales_invoices invoice
     where invoice.id = v_invoice_id
       and invoice.tenant_id = v_tenant_id;

    select public.clp_round(coalesce(sum(payment.amount), 0))
      into v_ledger_paid
      from public.sales_payments payment
     where payment.invoice_id = v_invoice_id
       and payment.tenant_id = v_tenant_id
       and payment.deleted_at is null;

    select count(*)::integer
      into v_job_paid_mismatch
      from public.mechanic_jobs job
     where job.tenant_id = v_tenant_id
       and job.invoice_id = v_invoice_id
       and job.is_paid is distinct from (
         lower(v_invoice_status) = 'paid'
       );

    v_expected_balance := greatest(v_invoice_total - v_ledger_paid, 0);
  else
    v_document_type := 'purchase_payment';
    v_invoice_type := 'purchase_invoice';
    select
      public.inventory_trace_document_snapshot(to_jsonb(invoice)),
      public.clp_round(invoice.total),
      public.clp_round(invoice.paid_amount),
      public.clp_round(invoice.balance),
      invoice.status,
      invoice.received_date,
      public.clp_round(invoice.credited_amount),
      public.clp_round(invoice.supplier_refunded_amount),
      public.clp_round(invoice.supplier_credit_balance)
      into v_invoice_after, v_invoice_total, v_invoice_paid,
           v_invoice_balance, v_invoice_status, v_received_date,
           v_invoice_credited, v_invoice_refunded,
           v_invoice_credit_balance
      from public.purchase_invoices invoice
     where invoice.id = v_invoice_id
       and invoice.tenant_id = v_tenant_id;

    select public.clp_round(coalesce(sum(payment.amount), 0))
      into v_ledger_paid
      from public.purchase_payments payment
     where payment.invoice_id = v_invoice_id
       and payment.tenant_id = v_tenant_id
       and payment.deleted_at is null;

    select public.clp_round(coalesce(sum(note.total_amount), 0))
      into v_ledger_credited
      from public.purchase_credit_notes note
     where note.purchase_invoice_id = v_invoice_id
       and note.tenant_id = v_tenant_id
       and note.status = 'posted';

    select public.clp_round(coalesce(sum(refund.amount), 0))
      into v_ledger_refunded
      from public.purchase_supplier_refunds refund
     where refund.purchase_invoice_id = v_invoice_id
       and refund.tenant_id = v_tenant_id
       and refund.status = 'posted';

    v_net_paid := greatest(v_ledger_paid - v_ledger_refunded, 0);
    v_effective_total := greatest(
      v_invoice_total - v_ledger_credited,
      0
    );
    v_expected_balance := greatest(v_effective_total - v_net_paid, 0);
    v_expected_credit_balance := greatest(
      v_net_paid - v_effective_total,
      0
    );
  end if;

  if v_invoice_after is null then
    raise exception
      'Payment trace could not reload related invoice %',
      v_invoice_id;
  end if;

  select count(*)::integer
    into v_payment_journal_count
    from public.journal_entries entry
   where entry.tenant_id = v_tenant_id
     and entry.source_module = TG_TABLE_NAME
     and entry.source_reference = v_payment_id::text;

  select count(*)::integer
    into v_stock_movement_count
    from public.stock_movements movement
   where movement.tenant_id = v_tenant_id
     and movement.operation_id = v_operation_id;

  perform public.append_inventory_accounting_checkpoint(
    v_operation_id,
    'source_snapshotted',
    'completed',
    v_invoice_type,
    v_invoice_id,
    jsonb_build_object(
      'invoice_before', (
        select operation.context->'invoice_before'
          from public.inventory_accounting_operations operation
         where operation.id = v_operation_id
      ),
      'invoice_after', v_invoice_after
    )
  );

  if v_invoice_paid <> v_ledger_paid
     or v_invoice_balance <> v_expected_balance
     or v_stock_movement_count <> 0
     or v_payment_journal_count <> (
       case when v_payment_active then 1 else 0 end
     )
     or v_job_paid_mismatch <> 0
     or (
       v_invoice_type = 'purchase_invoice'
       and (
         v_invoice_credited <> v_ledger_credited
         or v_invoice_refunded <> v_ledger_refunded
         or v_invoice_credit_balance <> v_expected_credit_balance
       )
     )
     or (
       v_invoice_type = 'purchase_invoice'
       and v_received_date is not null
       and v_invoice_status <> 'received'
     ) then
    raise exception
      'Payment invariants failed for operation % (ledger %, invoice paid %, credits %, refunds %, balance %, expected %, credit balance %, expected credit %, movements %, journals %, job mismatch %, status %)',
      v_operation_id, v_ledger_paid, v_invoice_paid,
      v_ledger_credited, v_ledger_refunded,
      v_invoice_balance, v_expected_balance,
      v_invoice_credit_balance, v_expected_credit_balance,
      v_stock_movement_count, v_payment_journal_count,
      v_job_paid_mismatch, v_invoice_status
      using errcode = 'check_violation';
  end if;

  perform public.complete_inventory_accounting_operation(
    v_operation_id,
    v_tenant_id,
    jsonb_build_object(
      'payment_id', v_payment_id,
      'payment_active', v_payment_active,
      'invoice_type', v_invoice_type,
      'invoice_id', v_invoice_id,
      'ledger_paid', v_ledger_paid,
      'ledger_credited', v_ledger_credited,
      'ledger_refunded', v_ledger_refunded,
      'invoice_balance', v_invoice_balance,
      'invoice_credit_balance', v_invoice_credit_balance,
      'invoice_status', v_invoice_status,
      'stock_movement_count', v_stock_movement_count,
      'payment_journal_count', v_payment_journal_count,
      'job_paid_mismatch', v_job_paid_mismatch
    )
  );

  perform set_config('app.inventory_operation_id', '', true);
  perform set_config('app.inventory_source_document_type', '', true);
  perform set_config('app.inventory_source_document_id', '', true);
  perform set_config('app.inventory_source_channel', '', true);
  return case when TG_OP = 'DELETE' then OLD else NEW end;
exception
  when others then
    perform set_config('app.inventory_operation_id', '', true);
    perform set_config('app.inventory_source_document_type', '', true);
    perform set_config('app.inventory_source_document_id', '', true);
    perform set_config('app.inventory_source_channel', '', true);
    raise;
end;
$$;

revoke all on function public.complete_invoice_payment_trace()
  from public, anon, authenticated, service_role;

create or replace function public.get_purchase_payment_edit_operation(
  p_operation_key text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid := auth.uid();
  v_tenant uuid;
  v_active_profile_count integer;
  v_key text := nullif(btrim(p_operation_key), '');
  v_event public.purchase_payment_edit_events%rowtype;
begin
  select count(*)::integer
    into v_active_profile_count
    from public.user_profiles profile
   where profile.user_id = v_actor
     and profile.is_active is true;

  if v_actor is null or v_active_profile_count <> 1 then
    raise exception 'Exactly one active employee tenant is required'
      using errcode = 'insufficient_privilege';
  end if;

  select profile.tenant_id
    into v_tenant
    from public.user_profiles profile
   where profile.user_id = v_actor
     and profile.is_active is true;

  perform public.assert_purchase_payment_access(v_tenant);

  if v_key is null or length(v_key) > 128 then
    raise exception
      'A valid purchase payment correction operation key is required';
  end if;

  select * into v_event
    from public.purchase_payment_edit_events event
   where event.tenant_id = v_tenant
     and event.operation_key = v_key;

  if not found then
    return null;
  end if;

  return v_event.response_snapshot
    || jsonb_build_object('replayed', true);
end;
$$;

create or replace function public.correct_purchase_payment(
  p_payment_id uuid,
  p_expected_updated_at timestamptz,
  p_operation_key text,
  p_payment_method_id uuid,
  p_amount numeric,
  p_date timestamptz,
  p_reference text,
  p_notes text,
  p_reason text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid := auth.uid();
  v_tenant uuid;
  v_role text;
  v_permissions jsonb := '{}'::jsonb;
  v_active_profile_count integer;
  v_key text := nullif(btrim(p_operation_key), '');
  v_reference text := nullif(btrim(coalesce(p_reference, '')), '');
  v_notes text := nullif(btrim(coalesce(p_notes, '')), '');
  v_reason text := nullif(btrim(coalesce(p_reason, '')), '');
  v_amount numeric := public.clp_round(p_amount);
  v_payload jsonb;
  v_payload_hash text;
  v_receipt public.purchase_payment_edit_events%rowtype;
  v_before public.purchase_payments%rowtype;
  v_saved public.purchase_payments%rowtype;
  v_invoice public.purchase_invoices%rowtype;
  v_invoice_after public.purchase_invoices%rowtype;
  v_new_method public.payment_methods%rowtype;
  v_old_method_account_id uuid;
  v_financial_changed boolean;
  v_reference_changed boolean;
  v_notes_changed boolean;
  v_existing_paid numeric;
  v_remaining numeric;
  v_uuid_journal_count integer;
  v_legacy_journal_count integer;
  v_matching_legacy_count integer;
  v_invoice_number_count integer;
  v_same_amount_payment_count integer;
  v_prior_is_legacy boolean := false;
  v_prior_journal public.journal_entries%rowtype;
  v_current_journal_count integer;
  v_current_journal public.journal_entries%rowtype;
  v_line_count integer;
  v_line_debit numeric;
  v_line_credit numeric;
  v_payable_debit_count integer;
  v_method_credit_count integer;
  v_trace_operation_count integer;
  v_trace_operation_id uuid;
  v_stock_movement_count integer;
  v_gross_paid numeric;
  v_credited numeric;
  v_refunded numeric;
  v_net_paid numeric;
  v_effective_total numeric;
  v_expected_balance numeric;
  v_expected_supplier_credit numeric;
  v_expected_status text;
  v_event_id uuid := gen_random_uuid();
  v_event_created_at timestamptz := clock_timestamp();
  v_event_snapshot jsonb;
  v_result jsonb;
begin
  select count(*)::integer
    into v_active_profile_count
    from public.user_profiles profile
   where profile.user_id = v_actor
     and profile.is_active is true;

  if v_actor is null or v_active_profile_count <> 1 then
    raise exception 'Exactly one active employee tenant is required'
      using errcode = 'insufficient_privilege';
  end if;

  select profile.tenant_id, profile.role,
         coalesce(profile.permissions, '{}'::jsonb)
    into v_tenant, v_role, v_permissions
    from public.user_profiles profile
   where profile.user_id = v_actor
     and profile.is_active is true;

  perform public.assert_purchase_payment_access(v_tenant);

  if v_key is null or length(v_key) > 128 then
    raise exception
      'A valid purchase payment correction operation key is required';
  end if;
  if p_payment_id is null or p_expected_updated_at is null then
    raise exception
      'Purchase payment id and expected updated_at are required';
  end if;
  if p_payment_method_id is null then
    raise exception 'Purchase payment method is required';
  end if;
  if p_amount is null
     or p_amount <= 0
     or p_amount is distinct from public.clp_round(p_amount) then
    raise exception 'Purchase payment amount must be positive whole CLP';
  end if;
  if p_date is null then
    raise exception 'Purchase payment date is required';
  end if;
  if v_reason is null
     or length(v_reason) < 3
     or length(v_reason) > 1000 then
    raise exception
      'A purchase payment correction reason between 3 and 1000 characters is required';
  end if;
  if length(coalesce(v_reference, '')) > 512 then
    raise exception 'Purchase payment reference allows at most 512 characters';
  end if;
  if length(coalesce(v_notes, '')) > 4000 then
    raise exception 'Purchase payment notes allow at most 4000 characters';
  end if;

  v_payload := jsonb_build_object(
    'payment_id', p_payment_id,
    'expected_updated_at', p_expected_updated_at,
    'payment_method_id', p_payment_method_id,
    'amount_clp', v_amount,
    'date', p_date,
    'reference', v_reference,
    'notes', v_notes,
    'reason', v_reason
  );
  v_payload_hash := encode(
    extensions.digest(v_payload::text, 'sha256'),
    'hex'
  );

  perform pg_advisory_xact_lock(hashtextextended(
    v_tenant::text || ':purchase-payment-correction:' || v_key,
    0
  ));

  select * into v_receipt
    from public.purchase_payment_edit_events event
   where event.tenant_id = v_tenant
     and event.operation_key = v_key;
  if found then
    if v_receipt.request_hash is distinct from v_payload_hash then
      raise exception
        'Purchase payment correction key was already used with different content'
        using errcode = 'integrity_constraint_violation';
    end if;
    return v_receipt.response_snapshot
      || jsonb_build_object('replayed', true);
  end if;

  select * into v_before
    from public.purchase_payments payment
   where payment.id = p_payment_id
     and payment.tenant_id = v_tenant
   for update;
  if not found then
    raise exception 'Purchase payment not found for the active tenant'
      using errcode = 'insufficient_privilege';
  end if;

  if v_before.updated_at is distinct from p_expected_updated_at then
    raise exception
      'Purchase payment was modified after this form was loaded'
      using errcode = 'serialization_failure';
  end if;
  if v_before.deleted_at is not null then
    raise exception 'Deleted purchase payments cannot be corrected'
      using errcode = 'check_violation';
  end if;

  select * into v_invoice
    from public.purchase_invoices invoice
   where invoice.id = v_before.invoice_id
     and invoice.tenant_id = v_tenant
   for update;
  if not found then
    raise exception
      'Purchase payment invoice is missing or belongs to another tenant'
      using errcode = 'foreign_key_violation';
  end if;
  if lower(coalesce(v_invoice.status, '')) in (
    'cancelled', 'cancelado', 'cancelada', 'anulado', 'anulada'
  ) then
    raise exception
      'Payments on cancelled purchase invoices cannot be corrected'
      using errcode = 'check_violation';
  end if;

  v_financial_changed :=
    p_payment_method_id is distinct from v_before.payment_method_id
    or v_amount is distinct from public.clp_round(v_before.amount)
    or p_date is distinct from v_before.date;
  v_reference_changed := v_reference is distinct from
    nullif(btrim(coalesce(v_before.reference, '')), '');
  v_notes_changed := v_notes is distinct from
    nullif(btrim(coalesce(v_before.notes, '')), '');

  if not v_financial_changed
     and not v_reference_changed
     and not v_notes_changed then
    raise exception 'Purchase payment correction contains no changes'
      using errcode = 'check_violation';
  end if;

  if v_financial_changed
     and v_role not in ('admin', 'manager', 'accountant')
     and coalesce(v_permissions->'access_accounting', 'false'::jsonb)
           is distinct from 'true'::jsonb then
    raise exception
      'Financial purchase payment corrections require accounting authorization'
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_new_method
    from public.payment_methods method
   where method.id = p_payment_method_id
     and method.tenant_id = v_tenant
     and (
       p_payment_method_id = v_before.payment_method_id
       or method.is_active is true
     );
  if not found then
    raise exception
      'Purchase payment method is unavailable for the current tenant'
      using errcode = 'insufficient_privilege';
  end if;
  if v_new_method.requires_reference and v_reference is null then
    raise exception 'Payment method requires a reference'
      using errcode = 'check_violation';
  end if;

  select method.account_id
    into v_old_method_account_id
    from public.payment_methods method
   where method.id = v_before.payment_method_id
     and method.tenant_id = v_tenant;
  if not found then
    raise exception
      'Historical purchase payment method requires accounting review'
      using errcode = 'check_violation';
  end if;

  select public.clp_round(coalesce(sum(payment.amount), 0))
    into v_existing_paid
    from public.purchase_payments payment
   where payment.invoice_id = v_before.invoice_id
     and payment.tenant_id = v_tenant
     and payment.deleted_at is null
     and payment.id is distinct from v_before.id;
  v_remaining := public.clp_round(
    greatest(coalesce(v_invoice.total, 0) - v_existing_paid, 0)
  );
  if v_amount > v_remaining then
    raise exception
      'Purchase payment exceeds the invoice gross remaining balance: %, amount: %',
      v_remaining, v_amount
      using errcode = 'check_violation';
  end if;

  select count(*)::integer
    into v_uuid_journal_count
    from public.journal_entries entry
   where entry.tenant_id = v_tenant
     and entry.source_module = 'purchase_payments'
     and entry.source_reference = v_before.id::text;

  select
    count(*)::integer,
    count(*) filter (
      where public.clp_round(entry.total_debit)
              = public.clp_round(v_before.amount)
        and public.clp_round(entry.total_credit)
              = public.clp_round(v_before.amount)
        and lower(entry.status) = 'posted'
    )::integer
    into v_legacy_journal_count, v_matching_legacy_count
    from public.journal_entries entry
   where entry.tenant_id = v_tenant
     and entry.source_module = 'purchase_payments'
     and entry.source_reference = v_invoice.invoice_number;

  if v_uuid_journal_count > 1
     or (v_uuid_journal_count = 1 and v_legacy_journal_count > 0) then
    raise exception
      'Purchase payment has mixed or duplicate settlement journals; correction stopped for accounting review'
      using errcode = 'check_violation';
  elsif v_uuid_journal_count = 1 then
    select * into v_prior_journal
      from public.journal_entries entry
     where entry.tenant_id = v_tenant
       and entry.source_module = 'purchase_payments'
       and entry.source_reference = v_before.id::text
     for update;
  elsif v_legacy_journal_count = 0 then
    raise exception
      'Purchase payment has no recognized settlement journal; correction stopped for accounting review'
      using errcode = 'check_violation';
  else
    select count(*)::integer
      into v_invoice_number_count
      from public.purchase_invoices invoice
     where invoice.tenant_id = v_tenant
       and invoice.invoice_number = v_invoice.invoice_number;
    select count(*)::integer
      into v_same_amount_payment_count
      from public.purchase_payments payment
     where payment.tenant_id = v_tenant
       and payment.invoice_id = v_invoice.id
       and payment.deleted_at is null
       and public.clp_round(payment.amount)
             = public.clp_round(v_before.amount);

    if v_legacy_journal_count <> 1
       or v_matching_legacy_count <> 1
       or v_invoice_number_count <> 1
       or v_same_amount_payment_count <> 1 then
      raise exception
        'Legacy purchase payment journal is ambiguous (journals %, matching %, invoice numbers %, same-amount payments %); correction stopped for accounting review',
        v_legacy_journal_count, v_matching_legacy_count,
        v_invoice_number_count, v_same_amount_payment_count
        using errcode = 'check_violation';
    end if;

    select * into v_prior_journal
      from public.journal_entries entry
     where entry.tenant_id = v_tenant
       and entry.source_module = 'purchase_payments'
       and entry.source_reference = v_invoice.invoice_number
     for update;
    v_prior_is_legacy := true;
  end if;

  if v_prior_journal.id is null
     or lower(v_prior_journal.status) <> 'posted'
     or public.clp_round(v_prior_journal.total_debit)
          is distinct from public.clp_round(v_before.amount)
     or public.clp_round(v_prior_journal.total_credit)
          is distinct from public.clp_round(v_before.amount) then
    raise exception
      'Purchase payment current journal requires accounting review before correction'
      using errcode = 'check_violation';
  end if;

  select count(*)::integer,
         public.clp_round(coalesce(sum(line.debit_amount), 0)),
         public.clp_round(coalesce(sum(line.credit_amount), 0)),
         count(*) filter (
           where line.account_code = '2101'
             and public.clp_round(line.debit_amount)
                   = public.clp_round(v_before.amount)
             and public.clp_round(line.credit_amount) = 0
         )::integer,
         count(*) filter (
           where line.account_id = v_old_method_account_id
             and public.clp_round(line.credit_amount)
                   = public.clp_round(v_before.amount)
             and public.clp_round(line.debit_amount) = 0
         )::integer
    into v_line_count, v_line_debit, v_line_credit,
         v_payable_debit_count, v_method_credit_count
    from public.journal_lines line
   where line.entry_id = v_prior_journal.id
     and line.tenant_id = v_tenant;

  if v_line_count <> 2
     or v_line_debit is distinct from public.clp_round(v_before.amount)
     or v_line_credit is distinct from public.clp_round(v_before.amount)
     or v_payable_debit_count <> 1
     or v_method_credit_count <> 1 then
    raise exception
      'Purchase payment journal lines require accounting review before correction'
      using errcode = 'check_violation';
  end if;

  perform set_config(
    'app.purchase_payment_correction_command',
    'true',
    true
  );
  perform set_config('app.inventory_idempotency_key', v_key, true);
  perform set_config(
    'app.journal_supersession_reason',
    'purchase_payment_audited_correction',
    true
  );

  update public.purchase_payments payment
     set payment_method_id = p_payment_method_id,
         amount = v_amount,
         date = p_date,
         reference = v_reference,
         notes = v_notes,
         updated_at = clock_timestamp()
   where payment.id = v_before.id
     and payment.tenant_id = v_tenant
  returning * into v_saved;

  if v_saved.tenant_id is distinct from v_before.tenant_id
     or v_saved.invoice_id is distinct from v_before.invoice_id
     or v_saved.idempotency_key is distinct from v_before.idempotency_key
     or v_saved.created_at is distinct from v_before.created_at
     or v_saved.deleted_at is distinct from v_before.deleted_at
     or v_saved.deleted_by is distinct from v_before.deleted_by then
    raise exception 'Purchase payment identity changed during correction'
      using errcode = 'check_violation';
  end if;

  select count(*)::integer
    into v_current_journal_count
    from public.journal_entries entry
   where entry.tenant_id = v_tenant
     and entry.source_module = 'purchase_payments'
     and entry.source_reference = v_saved.id::text;
  if v_current_journal_count <> 1 then
    raise exception
      'Purchase payment correction did not leave exactly one current journal'
      using errcode = 'check_violation';
  end if;

  select * into v_current_journal
    from public.journal_entries entry
   where entry.tenant_id = v_tenant
     and entry.source_module = 'purchase_payments'
     and entry.source_reference = v_saved.id::text;

  if lower(v_current_journal.status) <> 'posted'
     or public.clp_round(v_current_journal.total_debit)
          is distinct from public.clp_round(v_saved.amount)
     or public.clp_round(v_current_journal.total_credit)
          is distinct from public.clp_round(v_saved.amount) then
    raise exception
      'Purchase payment correction did not leave one balanced posted journal'
      using errcode = 'check_violation';
  end if;

  select count(*)::integer,
         public.clp_round(coalesce(sum(line.debit_amount), 0)),
         public.clp_round(coalesce(sum(line.credit_amount), 0)),
         count(*) filter (
           where line.account_code = '2101'
             and public.clp_round(line.debit_amount)
                   = public.clp_round(v_saved.amount)
             and public.clp_round(line.credit_amount) = 0
         )::integer,
         count(*) filter (
           where line.account_id = v_new_method.account_id
             and public.clp_round(line.credit_amount)
                   = public.clp_round(v_saved.amount)
             and public.clp_round(line.debit_amount) = 0
         )::integer
    into v_line_count, v_line_debit, v_line_credit,
         v_payable_debit_count, v_method_credit_count
    from public.journal_lines line
   where line.entry_id = v_current_journal.id
     and line.tenant_id = v_tenant;

  if v_line_count <> 2
     or v_line_debit is distinct from public.clp_round(v_saved.amount)
     or v_line_credit is distinct from public.clp_round(v_saved.amount)
     or v_payable_debit_count <> 1
     or v_method_credit_count <> 1 then
    raise exception
      'Purchase payment journal lines do not reconcile to accounts payable and the selected settlement account'
      using errcode = 'check_violation';
  end if;

  select count(*)::integer,
         (array_agg(operation.id order by operation.started_at, operation.id))[1]
    into v_trace_operation_count, v_trace_operation_id
    from public.inventory_accounting_operations operation
   where operation.tenant_id = v_tenant
     and operation.operation_key = format(
       'purchase_payment:%s:update:%s',
       v_saved.id,
       v_key
     )
     and operation.document_type = 'purchase_payment'
     and operation.document_id = v_saved.id
     and operation.action = 'update'
     and operation.outcome = 'completed';
  if v_trace_operation_count <> 1 then
    raise exception
      'Completed purchase payment correction trace was not recorded exactly once'
      using errcode = 'check_violation';
  end if;

  select count(*)::integer
    into v_stock_movement_count
    from public.stock_movements movement
   where movement.tenant_id = v_tenant
     and movement.operation_id = v_trace_operation_id;
  if v_stock_movement_count <> 0 then
    raise exception
      'Purchase payment correction created an inventory movement'
      using errcode = 'check_violation';
  end if;

  if v_financial_changed or v_prior_is_legacy then
    if v_current_journal.id = v_prior_journal.id then
      raise exception
        'Purchase payment correction did not supersede the required journal'
        using errcode = 'check_violation';
    end if;
    if not exists (
      select 1
        from public.journal_supersession_evidence evidence
       where evidence.tenant_id = v_tenant
         and evidence.journal_entry_id = v_prior_journal.id
         and evidence.operation_id = v_trace_operation_id
         and evidence.source_module = 'purchase_payments'
         and evidence.source_reference = case
           when v_prior_is_legacy then v_invoice.invoice_number
           else v_saved.id::text
         end
         and evidence.captured_reason
               = 'purchase_payment_audited_correction'
    ) then
      raise exception
        'Superseded purchase payment journal evidence was not preserved'
        using errcode = 'check_violation';
    end if;
  elsif v_current_journal.id is distinct from v_prior_journal.id then
    raise exception
      'Metadata-only purchase payment correction replaced its canonical journal'
      using errcode = 'check_violation';
  end if;

  if v_prior_is_legacy and exists (
    select 1
      from public.journal_entries entry
     where entry.tenant_id = v_tenant
       and entry.source_module = 'purchase_payments'
       and entry.source_reference = v_invoice.invoice_number
  ) then
    raise exception
      'Legacy purchase payment journal remained active after canonical relink'
      using errcode = 'check_violation';
  end if;

  if (v_financial_changed or v_prior_is_legacy)
     and (
       v_current_journal.operation_id is distinct from v_trace_operation_id
       or v_current_journal.source_document_type
            is distinct from 'purchase_payment'
       or v_current_journal.source_document_id is distinct from v_saved.id
     ) then
    raise exception
      'Replacement purchase payment journal is not linked to its correction trace'
      using errcode = 'check_violation';
  end if;

  select * into v_invoice_after
    from public.purchase_invoices invoice
   where invoice.id = v_saved.invoice_id
     and invoice.tenant_id = v_tenant;

  select public.clp_round(coalesce(sum(payment.amount), 0))
    into v_gross_paid
    from public.purchase_payments payment
   where payment.invoice_id = v_saved.invoice_id
     and payment.tenant_id = v_tenant
     and payment.deleted_at is null;
  select public.clp_round(coalesce(sum(note.total_amount), 0))
    into v_credited
    from public.purchase_credit_notes note
   where note.purchase_invoice_id = v_saved.invoice_id
     and note.tenant_id = v_tenant
     and note.status = 'posted';
  select public.clp_round(coalesce(sum(refund.amount), 0))
    into v_refunded
    from public.purchase_supplier_refunds refund
   where refund.purchase_invoice_id = v_saved.invoice_id
     and refund.tenant_id = v_tenant
     and refund.status = 'posted';

  v_net_paid := greatest(v_gross_paid - v_refunded, 0);
  v_effective_total := greatest(
    public.clp_round(v_invoice_after.total) - v_credited,
    0
  );
  v_expected_balance := greatest(v_effective_total - v_net_paid, 0);
  v_expected_supplier_credit := greatest(
    v_net_paid - v_effective_total,
    0
  );

  if v_invoice.status = 'received'
     or v_invoice.received_date is not null then
    v_expected_status := 'received';
  elsif v_invoice.status in ('draft', 'sent') then
    v_expected_status := v_invoice.status;
  elsif v_expected_balance = 0
     and (
       v_gross_paid > 0
       or v_credited >= public.clp_round(v_invoice.total)
     ) then
    v_expected_status := 'paid';
  elsif v_net_paid > 0 and v_expected_balance > 0 then
    v_expected_status := 'confirmed';
  else
    v_expected_status := case
      when v_invoice.status = 'paid' then 'confirmed'
      else v_invoice.status
    end;
  end if;

  if public.clp_round(v_invoice_after.paid_amount)
       is distinct from v_gross_paid
     or public.clp_round(v_invoice_after.credited_amount)
       is distinct from v_credited
     or public.clp_round(v_invoice_after.supplier_refunded_amount)
       is distinct from v_refunded
     or public.clp_round(v_invoice_after.balance)
       is distinct from v_expected_balance
     or public.clp_round(v_invoice_after.supplier_credit_balance)
       is distinct from v_expected_supplier_credit
     or v_invoice_after.status is distinct from v_expected_status then
    raise exception
      'Purchase invoice settlement does not reconcile after payment correction'
      using errcode = 'check_violation';
  end if;

  v_event_snapshot := jsonb_build_object(
    'id', v_event_id,
    'tenant_id', v_tenant,
    'payment_id', v_saved.id,
    'invoice_id', v_saved.invoice_id,
    'operation_key', v_key,
    'reason', v_reason,
    'financial_fields_changed', v_financial_changed,
    'legacy_journal_relinked', v_prior_is_legacy,
    'before_snapshot', to_jsonb(v_before),
    'after_snapshot', to_jsonb(v_saved),
    'trace_operation_id', v_trace_operation_id,
    'prior_journal_entry_id', v_prior_journal.id,
    'current_journal_entry_id', v_current_journal.id,
    'created_by', v_actor,
    'created_at', v_event_created_at
  );
  v_result := jsonb_build_object(
    'payment', to_jsonb(v_saved),
    'event', v_event_snapshot,
    'financial_fields_changed', v_financial_changed,
    'legacy_journal_relinked', v_prior_is_legacy,
    'replayed', false
  );

  insert into public.purchase_payment_edit_events (
    id, tenant_id, payment_id, invoice_id, operation_key,
    request_hash, request_snapshot, reason, financial_fields_changed,
    legacy_journal_relinked, before_snapshot, after_snapshot,
    trace_operation_id, prior_journal_entry_id, current_journal_entry_id,
    response_snapshot, created_by, created_at
  ) values (
    v_event_id, v_tenant, v_saved.id, v_saved.invoice_id, v_key,
    v_payload_hash, v_payload, v_reason, v_financial_changed,
    v_prior_is_legacy, to_jsonb(v_before), to_jsonb(v_saved),
    v_trace_operation_id, v_prior_journal.id, v_current_journal.id,
    v_result, v_actor, v_event_created_at
  );

  perform set_config(
    'app.purchase_payment_correction_command',
    '',
    true
  );
  perform set_config('app.inventory_idempotency_key', '', true);
  perform set_config('app.journal_supersession_reason', '', true);
  return v_result;
exception
  when others then
    perform set_config(
      'app.purchase_payment_correction_command',
      '',
      true
    );
    perform set_config('app.inventory_idempotency_key', '', true);
    perform set_config('app.journal_supersession_reason', '', true);
    raise;
end;
$$;

revoke all on function public.get_purchase_payment_edit_operation(text)
  from public, anon, authenticated, service_role;
revoke all on function public.correct_purchase_payment(
  uuid, timestamptz, text, uuid, numeric, timestamptz,
  text, text, text
) from public, anon, authenticated, service_role;

grant execute on function public.get_purchase_payment_edit_operation(text)
  to authenticated;
grant execute on function public.correct_purchase_payment(
  uuid, timestamptz, text, uuid, numeric, timestamptz,
  text, text, text
) to authenticated;

comment on function public.get_purchase_payment_edit_operation(text) is
  'Reads the active-tenant immutable supplier-payment correction receipt after a lost RPC acknowledgement; returns null when the key is unknown.';
comment on function public.correct_purchase_payment(
  uuid, timestamptz, text, uuid, numeric, timestamptz,
  text, text, text
) is
  'Replay-safe optimistic supplier-payment correction. Preserves payment and invoice identity, requires accounting authorization for financial changes, relinks only uniquely attributable legacy journals, reconciles credit/refund-aware invoice settlement, and proves zero inventory effects.';

commit;
