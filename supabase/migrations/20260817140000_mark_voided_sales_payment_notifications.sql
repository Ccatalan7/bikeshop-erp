-- Preserve payment reversals in the operational briefing without presenting
-- them as active collections.
--
-- A sales payment is currently removed through the audited DELETE path. The
-- durable `sales_payment_received` row used to survive unchanged, so one
-- reversed payment still looked like money received and inflated the briefing
-- payment metric. The notification now changes state in place to
-- `sales_payment_voided`; its immutable recording timestamp and read state stay
-- intact, while its route moves to the surviving invoice.

begin;

set local lock_timeout = '5s';
set local statement_timeout = '30s';

create or replace function public.create_sales_payment_erp_notification()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_body text;
  v_customer_name text;
  v_invoice_route text;
  v_is_restore boolean := false;
  v_is_void boolean := false;
  v_payment public.sales_payments%rowtype;
  v_payment_method text;
  v_recorded_by text;
  v_voided_at timestamp with time zone;
  v_voided_by text;
begin
  if TG_OP = 'DELETE' then
    v_payment := OLD;

    -- A later physical purge of an already soft-deleted row must not replace
    -- the original cancellation timestamp or actor.
    if OLD.deleted_at is not null then
      return OLD;
    end if;
    v_is_void := true;
  else
    v_payment := NEW;
  end if;

  if TG_OP = 'UPDATE' then
    v_is_void := OLD.deleted_at is null and NEW.deleted_at is not null;
    v_is_restore := OLD.deleted_at is not null and NEW.deleted_at is null;
  end if;

  v_invoice_route := '/sales/invoices/' || v_payment.invoice_id::text;

  if v_is_void then
    v_voided_at := coalesce(v_payment.deleted_at, clock_timestamp());
    v_voided_by := public.erp_actor_display_name(
      coalesce(v_payment.deleted_by, auth.uid()),
      v_payment.tenant_id
    );

    -- Reuse the immutable notification identity. Realtime consumers therefore
    -- replace the received row instead of rendering another apparent payment.
    update public.erp_notifications as existing
       set type = 'sales_payment_voided',
           title = 'Pago anulado',
           route = v_invoice_route,
           severity = 'warning',
           data = existing.data || jsonb_strip_nulls(
             jsonb_build_object(
               'is_voided', true,
               'voided_at', v_voided_at,
               'voided_by_name', v_voided_by
             )
           )
     where existing.tenant_id = v_payment.tenant_id
       and existing.type = 'sales_payment_received'
       and existing.entity_type = 'sales_payment'
       and existing.entity_id = v_payment.id;

    if found then
      if TG_OP = 'DELETE' then
        return OLD;
      end if;
      return NEW;
    end if;

    -- Compatibility fallback for a payment created before notification
    -- persistence was available. The cancellation still gets one truthful row.
    select method.name
      into v_payment_method
      from public.payment_methods method
     where method.tenant_id = v_payment.tenant_id
       and method.id = v_payment.payment_method_id;

    select invoice.customer_name
      into v_customer_name
      from public.sales_invoices invoice
     where invoice.tenant_id = v_payment.tenant_id
       and invoice.id = v_payment.invoice_id;

    v_body := coalesce(nullif(v_payment.invoice_reference, ''), 'Pago');
    if coalesce(v_payment.amount, 0) > 0 then
      v_body := v_body
        || ' · $'
        || trim(to_char(v_payment.amount, 'FM999G999G999G990'));
    end if;

    insert into public.erp_notifications as existing (
      tenant_id,
      type,
      title,
      body,
      route,
      entity_type,
      entity_id,
      severity,
      data,
      occurred_at
    ) values (
      v_payment.tenant_id,
      'sales_payment_voided',
      'Pago anulado',
      v_body,
      v_invoice_route,
      'sales_payment',
      v_payment.id,
      'warning',
      jsonb_strip_nulls(jsonb_build_object(
        'payment_id', v_payment.id,
        'invoice_id', v_payment.invoice_id,
        'invoice_reference', v_payment.invoice_reference,
        'amount', v_payment.amount,
        'payment_method', v_payment_method,
        'customer_name', v_customer_name,
        'recorded_at', v_payment.created_at,
        'payment_date', v_payment.date,
        'reference', v_payment.reference,
        'is_voided', true,
        'voided_at', v_voided_at,
        'voided_by_name', v_voided_by
      )),
      v_payment.date
    ) on conflict (tenant_id, type, entity_type, entity_id) do update
      set title = excluded.title,
          body = excluded.body,
          route = excluded.route,
          severity = excluded.severity,
          data = existing.data || excluded.data,
          occurred_at = excluded.occurred_at;

    if TG_OP = 'DELETE' then
      return OLD;
    end if;
    return NEW;
  end if;

  -- Inserts that already arrive soft-deleted are imports, not new receipts.
  if NEW.deleted_at is not null then
    return NEW;
  end if;

  if TG_OP = 'UPDATE'
     and not v_is_restore
     and NEW.date is not distinct from OLD.date then
    return NEW;
  end if;

  select method.name
    into v_payment_method
    from public.payment_methods method
   where method.tenant_id = NEW.tenant_id
     and method.id = NEW.payment_method_id;

  select invoice.customer_name
    into v_customer_name
    from public.sales_invoices invoice
   where invoice.tenant_id = NEW.tenant_id
     and invoice.id = NEW.invoice_id;

  v_recorded_by := public.erp_actor_display_name(auth.uid(), NEW.tenant_id);
  v_body := coalesce(nullif(NEW.invoice_reference, ''), 'Pago');
  if coalesce(NEW.amount, 0) > 0 then
    v_body := v_body
      || ' · $'
      || trim(to_char(NEW.amount, 'FM999G999G999G990'));
  end if;

  if v_is_restore then
    update public.erp_notifications as existing
       set type = 'sales_payment_received',
           title = 'Nuevo pago recibido',
           body = v_body,
           route = '/sales/payments',
           severity = 'success',
           data = (
             existing.data
               - 'is_voided'
               - 'voided_at'
               - 'voided_by_name'
           ) || jsonb_build_object('payment_date', NEW.date),
           occurred_at = NEW.date
     where existing.tenant_id = NEW.tenant_id
       and existing.type = 'sales_payment_voided'
       and existing.entity_type = 'sales_payment'
       and existing.entity_id = NEW.id;

    if found then
      return NEW;
    end if;
  end if;

  insert into public.erp_notifications as existing (
    tenant_id,
    type,
    title,
    body,
    route,
    entity_type,
    entity_id,
    severity,
    data,
    occurred_at
  ) values (
    NEW.tenant_id,
    'sales_payment_received',
    'Nuevo pago recibido',
    v_body,
    '/sales/payments',
    'sales_payment',
    NEW.id,
    'success',
    jsonb_build_object(
      'payment_id', NEW.id,
      'invoice_id', NEW.invoice_id,
      'invoice_reference', NEW.invoice_reference,
      'amount', NEW.amount,
      'payment_method', v_payment_method,
      'customer_name', v_customer_name,
      'recorded_by_name', v_recorded_by,
      'recorded_at', NEW.created_at,
      'payment_date', NEW.date,
      'reference', NEW.reference
    ),
    NEW.date
  ) on conflict (tenant_id, type, entity_type, entity_id) do update
    set occurred_at = excluded.occurred_at,
        data = existing.data
          || jsonb_build_object('payment_date', NEW.date);

  return NEW;
end;
$$;

revoke all on function public.create_sales_payment_erp_notification()
  from public, anon, authenticated, service_role;

drop trigger if exists trg_sales_payment_erp_notification
  on public.sales_payments;
create trigger trg_sales_payment_erp_notification
  after insert or delete or update of date, deleted_at
  on public.sales_payments
  for each row execute function public.create_sales_payment_erp_notification();

comment on function public.create_sales_payment_erp_notification() is
  'Creates received-payment activity and converts it in place to a non-financial sales_payment_voided event when the payment is reversed.';

-- Repair every surviving received-payment notification whose source payment
-- is no longer active. Where the append-only payment trace exists, carry its
-- exact cancellation time and tenant-safe actor name; older evidence remains
-- explicitly voided without inventing either field.
with orphaned as (
  select
    notification.id,
    notification.tenant_id,
    coalesce(
      payment.deleted_at,
      deletion.completed_at,
      deletion.created_at
    ) as voided_at,
    coalesce(payment.deleted_by, deletion.actor_id) as voided_by
  from public.erp_notifications notification
  left join public.sales_payments payment
    on payment.tenant_id = notification.tenant_id
   and payment.id = notification.entity_id
  left join lateral (
    select
      operation.actor_id,
      operation.completed_at,
      operation.created_at
    from public.inventory_accounting_operations operation
    where operation.tenant_id = notification.tenant_id
      and operation.document_type = 'sales_payment'
      and operation.document_id = notification.entity_id
      and operation.action = 'delete'
    order by operation.created_at desc
    limit 1
  ) deletion on true
  where notification.type = 'sales_payment_received'
    and notification.entity_type = 'sales_payment'
    and not exists (
      select 1
      from public.sales_payments active_payment
      where active_payment.tenant_id = notification.tenant_id
        and active_payment.id = notification.entity_id
        and active_payment.deleted_at is null
    )
), resolved as (
  select
    orphaned.*,
    public.erp_actor_display_name(
      orphaned.voided_by,
      orphaned.tenant_id
    ) as voided_by_name
  from orphaned
)
update public.erp_notifications as notification
   set type = 'sales_payment_voided',
       title = 'Pago anulado',
       route = case
         when nullif(notification.data->>'invoice_id', '') is null
           then '/sales/invoices'
         else '/sales/invoices/' || (notification.data->>'invoice_id')
       end,
       severity = 'warning',
       data = notification.data || jsonb_strip_nulls(
         jsonb_build_object(
           'is_voided', true,
           'voided_at', resolved.voided_at,
           'voided_by_name', resolved.voided_by_name
         )
       )
  from resolved
 where notification.id = resolved.id;

commit;
