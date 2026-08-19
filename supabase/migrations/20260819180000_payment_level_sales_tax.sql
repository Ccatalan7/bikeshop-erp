-- Sales tax follows the tender, not the document.
--
-- Since 20260715160000 the invoice owned one tax classification and the first
-- payment fixed it: a later payment with a different treatment was rejected
-- with 55000, and every payment row mirrored the document. That contradicts
-- how this shop actually sells — a card payment is documented and carries
-- 19% IVA, a cash payment is not documented and carries none — so an invoice
-- settled with both tenders could not be classified at all. 17 invoices in
-- production already mix cash and card.
--
-- Nothing downstream had to move: create_sales_payment_journal_entry has
-- posted IVA débito from each payment's own tax_treatment since
-- 20260107_payment_level_iva, and generate_f29_from_accounting reads those
-- entries. Only the two July guards forced uniformity, plus the correction
-- command that compared a payment against its document.
--
-- What changes here:
--   1. validate_sales_payment_integrity keeps the payment's own treatment
--      (falling back to the invoice's when the caller sends none) and derives
--      net/IVA from it.
--   2. register_sales_payment_with_invoice_tax drops the 55000 lock, and only
--      the first payment sets sales_invoices.tax_treatment. That column now
--      means «the document's default», not «the IVA already recognised».
--   3. correct_sales_payment validates a payment against its own treatment,
--      so a card payment on a mixed invoice stays correctable.
--
-- guard_sales_invoice_tax_ownership is unchanged: the document's own column
-- still moves only through the payment command.

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

  -- Tax follows the tender, not the document. A card sale is documented and
  -- taxed; cash is not. An invoice settled with both therefore carries both,
  -- and this row is where that is decided: create_sales_payment_journal_entry
  -- already posts IVA débito (2105) from this payment's own classification,
  -- and the F29 is generated from those entries.
  NEW.tax_treatment := coalesce(
    nullif(btrim(coalesce(NEW.tax_treatment, '')), ''),
    v_invoice.tax_treatment
  );
  if NEW.tax_treatment not in ('no_tax', 'tax_included') then
    raise exception 'Tratamiento tributario inválido en el pago.';
  end if;
  if NEW.tax_treatment = 'tax_included' then
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
       and (
         coalesce(method.is_active, true)
         or (
           TG_OP = 'UPDATE'
           and NEW.payment_method_id is not distinct from OLD.payment_method_id
           and current_setting(
             'app.sales_payment_correction_command',
             true
           ) = 'true'
         )
       )
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
  -- The document keeps the classification its first payment gave it: that is
  -- the default the next payment starts from, and what an unpaid balance is
  -- worth. It is no longer the authority over IVA already recognised, which
  -- lives on each payment row.
  update public.sales_invoices
     set tax_treatment = case
           when v_existing_paid > 0 then tax_treatment
           else p_tax_treatment
         end,
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
) is 'Atomic authorized payment command: classifies tax per tender, posts the document, settles cash, and records an immutable full-payload retry receipt.';

-- The audited correction command only exists where its own July migration
-- was deployed. Production never received it, so replacing it there would fail
-- on a table that does not exist. Where it IS installed, it must compare a
-- payment against its own classification, or a card payment on a mixed
-- invoice becomes uncorrectable.
do $migration$
begin
  if to_regclass('public.sales_payment_edit_events') is null then
    raise notice
      'audited sales-payment corrections are not installed here; skipping';
    return;
  end if;

  execute $body$
create or replace function public.correct_sales_payment(
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
  v_receipt public.sales_payment_edit_events%rowtype;
  v_before public.sales_payments%rowtype;
  v_saved public.sales_payments%rowtype;
  v_invoice public.sales_invoices%rowtype;
  v_source text;
  v_source_managed boolean;
  v_financial_changed boolean;
  v_reference_changed boolean;
  v_notes_changed boolean;
  v_prior_journal_count integer;
  v_prior_journal_id uuid;
  v_prior_journal_balanced boolean;
  v_current_journal_count integer;
  v_current_journal_id uuid;
  v_current_journal_balanced boolean;
  v_line_debit numeric;
  v_line_credit numeric;
  v_method_debit_count integer;
  v_receivable_credit_count integer;
  v_trace_operation_id uuid;
  v_stock_movement_count integer;
  v_expected_net numeric;
  v_expected_iva numeric;
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

  perform public.assert_sales_payment_access(v_tenant);

  if v_key is null or length(v_key) > 128 then
    raise exception 'A valid payment correction operation key is required';
  end if;
  if p_payment_id is null or p_expected_updated_at is null then
    raise exception 'Payment id and expected updated_at are required';
  end if;
  if p_payment_method_id is null then
    raise exception 'Payment method is required';
  end if;
  if p_amount is null or v_amount <= 0 then
    raise exception 'Payment amount must be greater than zero';
  end if;
  if p_date is null then
    raise exception 'Payment date is required';
  end if;
  if v_reason is null or length(v_reason) < 3 or length(v_reason) > 1000 then
    raise exception 'A correction reason between 3 and 1000 characters is required';
  end if;
  if length(coalesce(v_reference, '')) > 512 then
    raise exception 'Payment reference allows at most 512 characters';
  end if;
  if length(coalesce(v_notes, '')) > 4000 then
    raise exception 'Payment notes allow at most 4000 characters';
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
    v_tenant::text || ':sales-payment-correction:' || v_key,
    0
  ));

  select * into v_receipt
    from public.sales_payment_edit_events event
   where event.tenant_id = v_tenant
     and event.operation_key = v_key;
  if found then
    if v_receipt.request_hash is distinct from v_payload_hash then
      raise exception 'Payment correction key was already used with different content'
        using errcode = 'integrity_constraint_violation';
    end if;
    return v_receipt.response_snapshot || jsonb_build_object('replayed', true);
  end if;

  select * into v_before
    from public.sales_payments payment
   where payment.id = p_payment_id
     and payment.tenant_id = v_tenant
   for update;
  if not found then
    raise exception 'Payment not found for the active tenant'
      using errcode = 'insufficient_privilege';
  end if;

  if v_before.updated_at is distinct from p_expected_updated_at then
    raise exception 'Payment was modified after this form was loaded'
      using errcode = 'serialization_failure';
  end if;
  if v_before.deleted_at is not null then
    raise exception 'Deleted payments cannot be corrected'
      using errcode = 'check_violation';
  end if;

  select * into v_invoice
    from public.sales_invoices invoice
   where invoice.id = v_before.invoice_id
     and invoice.tenant_id = v_tenant
   for update;
  if not found then
    raise exception 'Payment invoice is missing or belongs to another tenant'
      using errcode = 'foreign_key_violation';
  end if;
  if lower(coalesce(v_invoice.status, '')) in (
    'cancelled', 'cancelado', 'cancelada', 'anulado', 'anulada'
  ) then
    raise exception 'Payments on cancelled invoices cannot be corrected'
      using errcode = 'check_violation';
  end if;
  if v_before.tax_treatment not in ('no_tax', 'tax_included') then
    raise exception 'Payment tax classification requires accounting review before correction'
      using errcode = 'check_violation';
  end if;

  v_source := coalesce(nullif(btrim(v_invoice.source), ''), 'manual_sale');
  v_source_managed := v_source in ('pos', 'ecommerce', 'quick_sale')
    or exists (
      select 1
        from public.online_orders orders
       where orders.tenant_id = v_tenant
         and (
           orders.manual_payment_id = v_before.id
           or orders.sales_invoice_id = v_before.invoice_id
         )
    )
    or lower(coalesce(v_before.idempotency_key, ''))
         ~ '^(mercadopago|online_order|provider)[_:]';

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
    raise exception 'Payment correction contains no changes'
      using errcode = 'check_violation';
  end if;

  if v_source_managed
     and (v_financial_changed or v_reference_changed) then
    raise exception 'Source-managed payments allow notes-only corrections; use the source correction workflow for financial or reference changes'
      using errcode = 'check_violation';
  end if;

  if v_financial_changed
     and v_role not in ('admin', 'manager', 'accountant')
     and coalesce(v_permissions->'access_accounting', 'false'::jsonb)
           is distinct from 'true'::jsonb then
    raise exception 'Financial payment corrections require accounting authorization'
      using errcode = 'insufficient_privilege';
  end if;

  if not exists (
    select 1
      from public.payment_methods method
     where method.id = p_payment_method_id
       and method.tenant_id = v_tenant
       and (
         p_payment_method_id = v_before.payment_method_id
         or method.is_active is true
       )
  ) then
    raise exception 'Payment method is unavailable for the current tenant'
      using errcode = 'insufficient_privilege';
  end if;

  select count(*)::integer,
         (array_agg(entry.id order by entry.created_at, entry.id))[1],
         coalesce(bool_and(
           public.clp_round(entry.total_debit)
             = public.clp_round(v_before.amount)
           and public.clp_round(entry.total_credit)
             = public.clp_round(v_before.amount)
           and lower(entry.status) = 'posted'
         ), false)
    into v_prior_journal_count, v_prior_journal_id,
         v_prior_journal_balanced
    from public.journal_entries entry
   where entry.tenant_id = v_tenant
     and entry.source_module = 'sales_payments'
     and entry.source_reference = v_before.id::text;

  if v_prior_journal_count <> 1 or not v_prior_journal_balanced then
    raise exception 'Payment current journal requires accounting review before correction'
      using errcode = 'check_violation';
  end if;

  perform set_config('app.sales_payment_correction_command', 'true', true);
  perform set_config('app.inventory_idempotency_key', v_key, true);
  perform set_config(
    'app.journal_supersession_reason',
    'sales_payment_audited_correction',
    true
  );

  update public.sales_payments payment
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
     or v_saved.deleted_by is distinct from v_before.deleted_by
     or v_saved.invoice_reference is distinct from coalesce(
       v_before.invoice_reference,
       v_invoice.invoice_number
     )
     or v_saved.tax_treatment is distinct from v_before.tax_treatment then
    raise exception 'Payment identity changed during correction'
      using errcode = 'check_violation';
  end if;

  if v_before.tax_treatment = 'tax_included' then
    v_expected_net := public.clp_round(v_saved.amount / 1.19);
    v_expected_iva := public.clp_round(v_saved.amount) - v_expected_net;
  else
    v_expected_net := public.clp_round(v_saved.amount);
    v_expected_iva := 0;
  end if;
  if public.clp_round(v_saved.net_amount) is distinct from v_expected_net
     or public.clp_round(v_saved.iva_amount) is distinct from v_expected_iva then
    raise exception 'Payment tax mirrors do not reconcile after correction'
      using errcode = 'check_violation';
  end if;

  select count(*)::integer,
         (array_agg(entry.id order by entry.created_at, entry.id))[1],
         coalesce(bool_and(
           public.clp_round(entry.total_debit)
             = public.clp_round(v_saved.amount)
           and public.clp_round(entry.total_credit)
             = public.clp_round(v_saved.amount)
           and lower(entry.status) = 'posted'
         ), false)
    into v_current_journal_count, v_current_journal_id,
         v_current_journal_balanced
    from public.journal_entries entry
   where entry.tenant_id = v_tenant
     and entry.source_module = 'sales_payments'
     and entry.source_reference = v_saved.id::text;

  if v_current_journal_count <> 1 or not v_current_journal_balanced then
    raise exception 'Payment correction did not leave exactly one balanced current journal'
      using errcode = 'check_violation';
  end if;

  select public.clp_round(coalesce(sum(line.debit_amount), 0)),
         public.clp_round(coalesce(sum(line.credit_amount), 0)),
         count(*) filter (
           where line.account_id = method.account_id
             and public.clp_round(line.debit_amount)
                   = public.clp_round(v_saved.amount)
             and public.clp_round(line.credit_amount) = 0
         )::integer,
         count(*) filter (
           where line.account_code = '1130'
             and public.clp_round(line.credit_amount)
                   = public.clp_round(v_saved.amount)
             and public.clp_round(line.debit_amount) = 0
         )::integer
    into v_line_debit, v_line_credit, v_method_debit_count,
         v_receivable_credit_count
    from public.journal_lines line
    cross join public.payment_methods method
   where line.entry_id = v_current_journal_id
     and line.tenant_id = v_tenant
     and method.id = v_saved.payment_method_id
     and method.tenant_id = v_tenant;

  if v_line_debit is distinct from public.clp_round(v_saved.amount)
     or v_line_credit is distinct from public.clp_round(v_saved.amount)
     or v_method_debit_count <> 1
     or v_receivable_credit_count <> 1 then
    raise exception 'Payment journal lines do not reconcile to cash and accounts receivable'
      using errcode = 'check_violation';
  end if;

  select operation.id into v_trace_operation_id
    from public.inventory_accounting_operations operation
   where operation.tenant_id = v_tenant
     and operation.operation_key = format(
       'sales_payment:%s:update:%s',
       v_saved.id,
       v_key
     )
     and operation.document_type = 'sales_payment'
     and operation.document_id = v_saved.id
     and operation.action = 'update'
     and operation.outcome = 'completed';
  if not found then
    raise exception 'Completed payment correction trace was not recorded'
      using errcode = 'check_violation';
  end if;

  select count(*)::integer into v_stock_movement_count
    from public.stock_movements movement
   where movement.tenant_id = v_tenant
     and movement.operation_id = v_trace_operation_id;
  if v_stock_movement_count <> 0 then
    raise exception 'Payment correction created an inventory movement'
      using errcode = 'check_violation';
  end if;

  if v_financial_changed then
    if v_current_journal_id = v_prior_journal_id then
      raise exception 'Financial payment correction did not supersede its journal'
        using errcode = 'check_violation';
    end if;
    if not exists (
      select 1
        from public.journal_supersession_evidence evidence
       where evidence.tenant_id = v_tenant
         and evidence.journal_entry_id = v_prior_journal_id
         and evidence.operation_id = v_trace_operation_id
         and evidence.source_module = 'sales_payments'
         and evidence.source_reference = v_saved.id::text
         and evidence.captured_reason = 'sales_payment_audited_correction'
    ) then
      raise exception 'Superseded payment journal evidence was not preserved'
        using errcode = 'check_violation';
    end if;
  elsif v_current_journal_id is distinct from v_prior_journal_id then
    raise exception 'Metadata-only payment correction replaced its journal'
      using errcode = 'check_violation';
  end if;

  v_event_snapshot := jsonb_build_object(
    'id', v_event_id,
    'tenant_id', v_tenant,
    'payment_id', v_saved.id,
    'invoice_id', v_saved.invoice_id,
    'operation_key', v_key,
    'reason', v_reason,
    'source', v_source,
    'source_managed', v_source_managed,
    'financial_fields_changed', v_financial_changed,
    'trace_operation_id', v_trace_operation_id,
    'prior_journal_entry_id', v_prior_journal_id,
    'current_journal_entry_id', v_current_journal_id,
    'created_by', v_actor,
    'created_at', v_event_created_at
  );
  v_result := jsonb_build_object(
    'payment', to_jsonb(v_saved),
    'event', v_event_snapshot,
    'replayed', false
  );

  insert into public.sales_payment_edit_events (
    id, tenant_id, payment_id, invoice_id, operation_key,
    request_hash, request_snapshot, reason, source, source_managed,
    financial_fields_changed, before_snapshot, after_snapshot,
    trace_operation_id, prior_journal_entry_id, current_journal_entry_id,
    response_snapshot, created_by, created_at
  ) values (
    v_event_id, v_tenant, v_saved.id, v_saved.invoice_id, v_key,
    v_payload_hash, v_payload, v_reason, v_source, v_source_managed,
    v_financial_changed, to_jsonb(v_before), to_jsonb(v_saved),
    v_trace_operation_id, v_prior_journal_id, v_current_journal_id,
    v_result, v_actor, v_event_created_at
  );

  perform set_config('app.sales_payment_correction_command', '', true);
  perform set_config('app.inventory_idempotency_key', '', true);
  perform set_config('app.journal_supersession_reason', '', true);
  return v_result;
exception
  when others then
    perform set_config('app.sales_payment_correction_command', '', true);
    perform set_config('app.inventory_idempotency_key', '', true);
    perform set_config('app.journal_supersession_reason', '', true);
    raise;
end;
$$;
  $body$;

  execute $body$
    revoke all on function public.correct_sales_payment(
      uuid, timestamptz, text, uuid, numeric, timestamptz,
      text, text, text
    ) from public, anon, authenticated, service_role
  $body$;
  execute $body$
    grant execute on function public.correct_sales_payment(
      uuid, timestamptz, text, uuid, numeric, timestamptz,
      text, text, text
    ) to authenticated
  $body$;
end;
$migration$;

-- The workshop backfill repairs arithmetic, not classification.
--
-- It used to treat «payment.tax_treatment <> invoice.tax_treatment» as drift
-- and rewrite the payment to mirror the document. Under per-tender tax that
-- would flatten every mixed invoice on the next run and reclassify IVA that
-- create_sales_payment_journal_entry already posted, so the comparison now
-- happens against the payment's own classification.

drop view if exists public.workshop_financial_backfill_preview;
create view public.workshop_financial_backfill_preview
with (security_invoker = true)
as
select
  job.tenant_id,
  job.id as job_id,
  job.job_number,
  invoice.id as invoice_id,
  invoice.invoice_number,
  invoice.status as invoice_status,
  invoice.total as invoice_total,
  invoice.tax_treatment as invoice_tax_treatment,
  invoice.net_amount as invoice_net_amount,
  invoice.iva_amount as invoice_iva_amount,
  payment_stats.active_payment_count,
  payment_stats.active_payment_sum,
  payment_stats.tax_mismatch_count as payment_tax_mismatch_count,
  invoice_journal.journal_count as invoice_journal_count,
  invoice_journal.ar_debit,
  invoice_journal.sales_credit,
  invoice_journal.total_debit,
  invoice_journal.total_credit,
  job_journal.journal_count as job_journal_count,
  job.tax_treatment is distinct from invoice.tax_treatment
    or public.clp_round(job.tax_amount)
         is distinct from public.clp_round(invoice.iva_amount)
    or public.clp_round(job.total_cost)
         is distinct from public.clp_round(invoice.total)
    or job.is_paid is distinct from (
      lower(invoice.status) in ('paid', 'pagado', 'pagada')
    ) as job_financial_mirror_mismatch,
  lower(invoice.status) in ('paid', 'pagado', 'pagada')
    and public.clp_round(invoice.total) > 0
    and payment_stats.active_payment_sum = public.clp_round(invoice.total)
    and job_journal.journal_count = 0
    and invoice_journal.journal_count <= 1
    and (
      invoice_journal.journal_count = 0
      or invoice_journal.ar_debit <> public.clp_round(invoice.total)
      or invoice_journal.sales_credit <> public.clp_round(invoice.total)
      or invoice_journal.total_debit <> invoice_journal.total_credit
    ) as journal_repair_eligible,
  lower(invoice.status) in ('paid', 'pagado', 'pagada')
    and (
      invoice_journal.journal_count = 0
      or invoice_journal.ar_debit <> public.clp_round(invoice.total)
      or invoice_journal.sales_credit <> public.clp_round(invoice.total)
      or invoice_journal.total_debit <> invoice_journal.total_credit
    )
    and not (
      public.clp_round(invoice.total) > 0
      and payment_stats.active_payment_sum = public.clp_round(invoice.total)
      and job_journal.journal_count = 0
      and invoice_journal.journal_count <= 1
    ) as journal_requires_manual_review
from public.mechanic_jobs job
join public.sales_invoices invoice
  on invoice.id = job.invoice_id
 and invoice.tenant_id = job.tenant_id
left join lateral (
  select
    count(*)::integer as active_payment_count,
    public.clp_round(coalesce(sum(payment.amount), 0)) as active_payment_sum,
    -- Drift is a payment whose net/IVA contradict ITS OWN classification.
    -- A card payment taxed on an invoice whose first payment was cash is not
    -- drift: it is how a mixed-tender sale is settled here.
    count(*) filter (
      where payment.tax_treatment not in ('no_tax', 'tax_included')
         or public.clp_round(payment.net_amount) is distinct from case
           when payment.tax_treatment = 'tax_included'
             then public.clp_round(payment.amount / 1.19)
           else public.clp_round(payment.amount)
         end
         or public.clp_round(payment.iva_amount) is distinct from case
           when payment.tax_treatment = 'tax_included'
             then public.clp_round(payment.amount)
                    - public.clp_round(payment.amount / 1.19)
           else 0
         end
    )::integer as tax_mismatch_count
  from public.sales_payments payment
  where payment.invoice_id = invoice.id
    and payment.tenant_id = invoice.tenant_id
    and payment.deleted_at is null
) payment_stats on true
left join lateral (
  select
    count(distinct entry.id)::integer as journal_count,
    public.clp_round(coalesce(sum(line.debit_amount)
      filter (where line.account_code = '1130'), 0)) as ar_debit,
    public.clp_round(coalesce(sum(line.credit_amount)
      filter (where line.account_code in ('4100', '4101', '2150', '2110')), 0))
      as sales_credit,
    public.clp_round(coalesce(sum(line.debit_amount), 0)) as total_debit,
    public.clp_round(coalesce(sum(line.credit_amount), 0)) as total_credit
  from public.journal_entries entry
  left join public.journal_lines line
    on line.entry_id = entry.id
   and line.tenant_id = entry.tenant_id
  where entry.tenant_id = invoice.tenant_id
    and entry.source_module = 'sales_invoices'
    and entry.source_reference in (invoice.id::text, invoice.invoice_number)
) invoice_journal on true
left join lateral (
  select count(*)::integer as journal_count
  from public.journal_entries entry
  where entry.tenant_id = job.tenant_id
    and entry.source_module = 'mechanic_jobs'
    and entry.source_reference in (job.id::text, job.job_number)
) job_journal on true;

grant select on public.workshop_financial_backfill_preview to authenticated;

create or replace function public.apply_workshop_financial_backfill(
  p_tenant_id uuid,
  p_batch_key text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_run public.workshop_financial_backfill_runs%rowtype;
  v_key text := btrim(coalesce(p_batch_key, ''));
  v_job record;
  v_payment record;
  v_invoice public.sales_invoices%rowtype;
  v_preview record;
  v_before jsonb;
  v_after jsonb;
  v_payment_journal_before jsonb;
  v_payment_journal_after jsonb;
  v_summary jsonb;
  v_changed_jobs integer := 0;
  v_changed_payments integer := 0;
  v_repaired_journals integer := 0;
  v_manual_review integer := 0;
  v_stock_fingerprint_before text;
  v_stock_fingerprint_after text;
  v_payment_financial_fingerprint_before text;
  v_payment_financial_fingerprint_after text;
  v_invoice_fingerprint_before text;
  v_invoice_fingerprint_after text;
begin
  if p_tenant_id is null or not exists (
    select 1 from public.tenants where id = p_tenant_id
  ) then
    raise exception 'A valid tenant is required for workshop financial backfill.';
  end if;
  if v_key = '' or length(v_key) > 128 then
    raise exception 'Backfill batch key is required and must be at most 128 characters.';
  end if;
  if auth.uid() is not null then
    raise exception 'Historical workshop financial repair is database-admin only'
      using errcode = '42501';
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended(p_tenant_id::text || ':workshop-financial:' || v_key, 0)
  );

  select * into v_run
  from public.workshop_financial_backfill_runs
  where tenant_id = p_tenant_id and batch_key = v_key;

  if found and v_run.status = 'completed' then
    return v_run.summary || jsonb_build_object('replayed', true);
  elsif found then
    raise exception 'Backfill batch is already running.';
  end if;

  insert into public.workshop_financial_backfill_runs(tenant_id, batch_key)
  values (p_tenant_id, v_key)
  returning * into v_run;

  select md5(coalesce(string_agg(
    jsonb_build_object(
      'id', movement.id,
      'product_id', movement.product_id,
      'quantity', movement.quantity,
      'reference', movement.reference,
      'date', movement.date,
      'stock_before', movement.stock_before,
      'stock_after', movement.stock_after
    )::text,
    '|' order by movement.id
  ), ''))
  into v_stock_fingerprint_before
  from public.stock_movements movement
  where movement.tenant_id = p_tenant_id;

  select md5(coalesce(string_agg(
    jsonb_build_object(
      'id', payment.id,
      'invoice_id', payment.invoice_id,
      'method', payment.payment_method_id,
      'amount', payment.amount,
      'date', payment.date,
      'deleted_at', payment.deleted_at
    )::text,
    '|' order by payment.id
  ), ''))
  into v_payment_financial_fingerprint_before
  from public.sales_payments payment
  where payment.tenant_id = p_tenant_id;

  select md5(coalesce(string_agg(
    jsonb_build_object(
      'id', invoice.id,
      'status', invoice.status,
      'tax_treatment', invoice.tax_treatment,
      'subtotal', invoice.subtotal,
      'net_amount', invoice.net_amount,
      'iva_amount', invoice.iva_amount,
      'total', invoice.total,
      'paid_amount', invoice.paid_amount,
      'balance', invoice.balance,
      'items', invoice.items
    )::text,
    '|' order by invoice.id
  ), ''))
  into v_invoice_fingerprint_before
  from public.sales_invoices invoice
  where invoice.tenant_id = p_tenant_id;

  for v_job in
    select
      job.id as job_id,
      job.invoice_id,
      to_jsonb(job) as before_data,
      invoice.tax_treatment,
      invoice.iva_amount,
      invoice.total,
      lower(invoice.status) in ('paid', 'pagado', 'pagada') as is_paid
    from public.mechanic_jobs job
    join public.sales_invoices invoice
      on invoice.id = job.invoice_id
     and invoice.tenant_id = job.tenant_id
    where job.tenant_id = p_tenant_id
      and (
        job.tax_treatment is distinct from invoice.tax_treatment
        or public.clp_round(job.tax_amount)
             is distinct from public.clp_round(invoice.iva_amount)
        or public.clp_round(job.total_cost)
             is distinct from public.clp_round(invoice.total)
        or job.is_paid is distinct from (
          lower(invoice.status) in ('paid', 'pagado', 'pagada')
        )
      )
  loop
    perform set_config('app.syncing_invoice_to_job', 'true', true);
    update public.mechanic_jobs
    set tax_treatment = v_job.tax_treatment,
        tax_amount = v_job.iva_amount,
        total_cost = v_job.total,
        is_invoiced = true,
        is_paid = v_job.is_paid,
        updated_at = clock_timestamp()
    where id = v_job.job_id and tenant_id = p_tenant_id;
    perform set_config('app.syncing_invoice_to_job', '', true);

    insert into public.workshop_financial_backfill_rows(
      run_id, tenant_id, job_id, invoice_id, entity_type,
      changed_fields, before_data, after_data
    )
    select
      v_run.id, p_tenant_id, v_job.job_id, v_job.invoice_id, 'mechanic_job',
      array['tax_treatment', 'tax_amount', 'total_cost', 'is_invoiced', 'is_paid'],
      v_job.before_data, to_jsonb(job)
    from public.mechanic_jobs job where job.id = v_job.job_id;
    v_changed_jobs := v_changed_jobs + 1;
  end loop;

  for v_payment in
    select
      payment.id as payment_id,
      payment.invoice_id,
      job.id as job_id,
      to_jsonb(payment) as before_data,
      -- Repair the arithmetic, never the classification: rewriting a payment's
      -- tax treatment would reclassify IVA that its journal entry already
      -- posted, and would erase a deliberate mixed-tender settlement.
      payment.tax_treatment,
      case when payment.tax_treatment = 'tax_included'
        then public.clp_round(payment.amount / 1.19)
        else public.clp_round(payment.amount)
      end as expected_net,
      case when payment.tax_treatment = 'tax_included'
        then public.clp_round(payment.amount)
               - public.clp_round(payment.amount / 1.19)
        else 0
      end as expected_iva
    from public.sales_payments payment
    join public.sales_invoices invoice
      on invoice.id = payment.invoice_id
     and invoice.tenant_id = payment.tenant_id
    join public.mechanic_jobs job
      on job.invoice_id = invoice.id
     and job.tenant_id = invoice.tenant_id
    where payment.tenant_id = p_tenant_id
      and payment.deleted_at is null
      and (
        payment.tax_treatment not in ('no_tax', 'tax_included')
        or public.clp_round(payment.net_amount) is distinct from case
          when payment.tax_treatment = 'tax_included'
            then public.clp_round(payment.amount / 1.19)
          else public.clp_round(payment.amount)
        end
        or public.clp_round(payment.iva_amount) is distinct from case
          when payment.tax_treatment = 'tax_included'
            then public.clp_round(payment.amount)
                   - public.clp_round(payment.amount / 1.19)
          else 0
        end
      )
  loop
    select coalesce(jsonb_agg(to_jsonb(entry) order by entry.id), '[]'::jsonb)
    into v_payment_journal_before
    from public.journal_entries entry
    where entry.tenant_id = p_tenant_id
      and entry.source_module = 'sales_payments'
      and entry.source_reference = v_payment.payment_id::text;

    update public.sales_payments
    set tax_treatment = v_payment.tax_treatment,
        net_amount = v_payment.expected_net,
        iva_amount = v_payment.expected_iva
    where id = v_payment.payment_id and tenant_id = p_tenant_id;

    select coalesce(jsonb_agg(to_jsonb(entry) order by entry.id), '[]'::jsonb)
    into v_payment_journal_after
    from public.journal_entries entry
    where entry.tenant_id = p_tenant_id
      and entry.source_module = 'sales_payments'
      and entry.source_reference = v_payment.payment_id::text;

    if v_payment_journal_after is distinct from v_payment_journal_before then
      raise exception 'Payment journal changed during metadata-only repair for %.',
        v_payment.payment_id;
    end if;

    insert into public.workshop_financial_backfill_rows(
      run_id, tenant_id, job_id, invoice_id, payment_id, entity_type,
      changed_fields, before_data, after_data
    )
    select
      v_run.id, p_tenant_id, v_payment.job_id, v_payment.invoice_id,
      v_payment.payment_id, 'sales_payment',
      array['tax_treatment', 'net_amount', 'iva_amount'],
      v_payment.before_data, to_jsonb(payment)
    from public.sales_payments payment where payment.id = v_payment.payment_id;
    v_changed_payments := v_changed_payments + 1;
  end loop;

  for v_preview in
    select *
    from public.workshop_financial_backfill_preview preview
    where preview.tenant_id = p_tenant_id
      and preview.journal_repair_eligible
    order by preview.invoice_number
  loop
    select coalesce(jsonb_agg(
      jsonb_build_object(
        'entry', to_jsonb(entry),
        'lines', coalesce((
          select jsonb_agg(to_jsonb(line) order by line.id)
          from public.journal_lines line
          where line.entry_id = entry.id and line.tenant_id = entry.tenant_id
        ), '[]'::jsonb)
      ) order by entry.id
    ), '[]'::jsonb)
    into v_before
    from public.journal_entries entry
    where entry.tenant_id = p_tenant_id
      and entry.source_module = 'sales_invoices'
      and entry.source_reference in (
        v_preview.invoice_id::text,
        v_preview.invoice_number
      );

    delete from public.journal_entries entry
    where entry.tenant_id = p_tenant_id
      and entry.source_module = 'sales_invoices'
      and entry.source_reference in (
        v_preview.invoice_id::text,
        v_preview.invoice_number
      );

    select * into v_invoice
    from public.sales_invoices
    where id = v_preview.invoice_id and tenant_id = p_tenant_id;
    perform public.create_sales_invoice_journal_entry(v_invoice);

    select coalesce(jsonb_agg(
      jsonb_build_object(
        'entry', to_jsonb(entry),
        'lines', coalesce((
          select jsonb_agg(to_jsonb(line) order by line.id)
          from public.journal_lines line
          where line.entry_id = entry.id and line.tenant_id = entry.tenant_id
        ), '[]'::jsonb)
      ) order by entry.id
    ), '[]'::jsonb)
    into v_after
    from public.journal_entries entry
    where entry.tenant_id = p_tenant_id
      and entry.source_module = 'sales_invoices'
      and entry.source_reference in (
        v_preview.invoice_id::text,
        v_preview.invoice_number
      );

    if jsonb_array_length(v_after) <> 1 then
      raise exception 'Invoice journal repair did not produce exactly one entry for %.',
        v_preview.invoice_number;
    end if;

    insert into public.workshop_financial_backfill_rows(
      run_id, tenant_id, job_id, invoice_id, entity_type,
      changed_fields, before_data, after_data
    ) values (
      v_run.id, p_tenant_id, v_preview.job_id, v_preview.invoice_id,
      'sales_invoice_journal', array['journal_entry', 'journal_lines'],
      v_before, v_after
    );
    v_repaired_journals := v_repaired_journals + 1;
  end loop;

  for v_preview in
    select *
    from public.workshop_financial_backfill_preview preview
    where preview.tenant_id = p_tenant_id
      and preview.journal_requires_manual_review
    order by preview.invoice_number
  loop
    v_before := jsonb_build_object(
      'invoice_number', v_preview.invoice_number,
      'invoice_status', v_preview.invoice_status,
      'invoice_total', v_preview.invoice_total,
      'active_payment_count', v_preview.active_payment_count,
      'active_payment_sum', v_preview.active_payment_sum,
      'invoice_journal_count', v_preview.invoice_journal_count,
      'job_journal_count', v_preview.job_journal_count,
      'ar_debit', v_preview.ar_debit,
      'sales_credit', v_preview.sales_credit,
      'reason', 'legacy_unresolved'
    );
    insert into public.workshop_financial_backfill_rows(
      run_id, tenant_id, job_id, invoice_id, entity_type,
      changed_fields, before_data, after_data
    ) values (
      v_run.id, p_tenant_id, v_preview.job_id, v_preview.invoice_id,
      'legacy_unresolved', '{}', v_before, v_before
    );
    v_manual_review := v_manual_review + 1;
  end loop;

  select md5(coalesce(string_agg(
    jsonb_build_object(
      'id', movement.id,
      'product_id', movement.product_id,
      'quantity', movement.quantity,
      'reference', movement.reference,
      'date', movement.date,
      'stock_before', movement.stock_before,
      'stock_after', movement.stock_after
    )::text,
    '|' order by movement.id
  ), ''))
  into v_stock_fingerprint_after
  from public.stock_movements movement
  where movement.tenant_id = p_tenant_id;

  select md5(coalesce(string_agg(
    jsonb_build_object(
      'id', payment.id,
      'invoice_id', payment.invoice_id,
      'method', payment.payment_method_id,
      'amount', payment.amount,
      'date', payment.date,
      'deleted_at', payment.deleted_at
    )::text,
    '|' order by payment.id
  ), ''))
  into v_payment_financial_fingerprint_after
  from public.sales_payments payment
  where payment.tenant_id = p_tenant_id;

  select md5(coalesce(string_agg(
    jsonb_build_object(
      'id', invoice.id,
      'status', invoice.status,
      'tax_treatment', invoice.tax_treatment,
      'subtotal', invoice.subtotal,
      'net_amount', invoice.net_amount,
      'iva_amount', invoice.iva_amount,
      'total', invoice.total,
      'paid_amount', invoice.paid_amount,
      'balance', invoice.balance,
      'items', invoice.items
    )::text,
    '|' order by invoice.id
  ), ''))
  into v_invoice_fingerprint_after
  from public.sales_invoices invoice
  where invoice.tenant_id = p_tenant_id;

  if v_stock_fingerprint_after is distinct from v_stock_fingerprint_before then
    raise exception 'Workshop financial backfill changed stock evidence.';
  end if;
  if v_payment_financial_fingerprint_after
       is distinct from v_payment_financial_fingerprint_before then
    raise exception 'Workshop financial backfill changed cash settlement.';
  end if;
  if v_invoice_fingerprint_after is distinct from v_invoice_fingerprint_before then
    raise exception 'Workshop financial backfill changed invoice financial truth.';
  end if;

  v_summary := jsonb_build_object(
    'run_id', v_run.id,
    'tenant_id', p_tenant_id,
    'batch_key', v_key,
    'changed_jobs', v_changed_jobs,
    'changed_payments', v_changed_payments,
    'repaired_invoice_journals', v_repaired_journals,
    'legacy_unresolved', v_manual_review,
    'stock_unchanged', true,
    'cash_settlement_unchanged', true,
    'invoice_truth_unchanged', true,
    'replayed', false
  );

  update public.workshop_financial_backfill_runs
  set status = 'completed',
      completed_at = clock_timestamp(),
      summary = v_summary
  where id = v_run.id;

  return v_summary;
exception
  when others then
    perform set_config('app.syncing_invoice_to_job', '', true);
    raise;
end;
$$;
