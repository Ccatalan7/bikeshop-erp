-- Executable production read-back for 20260817140000.
-- Every statement fails at SQL level if the installed definition or the
-- payment/notification state contradicts the cancellation contract.

select 1 / (case when exists (
  select 1
  from pg_trigger trigger_row
  where trigger_row.tgrelid = 'public.sales_payments'::regclass
    and trigger_row.tgname = 'trg_sales_payment_erp_notification'
    and not trigger_row.tgisinternal
    and pg_get_triggerdef(trigger_row.oid)
      like '%AFTER INSERT OR DELETE OR UPDATE OF date, deleted_at ON public.sales_payments%'
) then 1 else 0 end) as reversal_trigger_installed;

select 1 / (case when
  not has_function_privilege(
    'anon',
    'public.create_sales_payment_erp_notification()',
    'EXECUTE'
  )
  and not has_function_privilege(
    'authenticated',
    'public.create_sales_payment_erp_notification()',
    'EXECUTE'
  )
  and not has_function_privilege(
    'service_role',
    'public.create_sales_payment_erp_notification()',
    'EXECUTE'
  )
then 1 else 0 end) as reversal_trigger_acl_private;

select 1 / (case when not exists (
  select 1
  from public.erp_notifications notification
  where notification.type = 'sales_payment_received'
    and notification.entity_type = 'sales_payment'
    and not exists (
      select 1
      from public.sales_payments payment
      where payment.tenant_id = notification.tenant_id
        and payment.id = notification.entity_id
        and payment.deleted_at is null
    )
) then 1 else 0 end) as no_orphan_received_payment_activity;

select 1 / (case when not exists (
  select 1
  from public.erp_notifications notification
  where notification.type = 'sales_payment_voided'
    and (
      notification.title <> 'Pago anulado'
      or notification.severity <> 'warning'
      or notification.data @> '{"is_voided": true}'::jsonb is not true
    )
) then 1 else 0 end) as voided_activity_is_explicit;

select 1 / (case when not exists (
  select 1
  from public.erp_notifications notification
  join public.sales_payments payment
    on payment.tenant_id = notification.tenant_id
   and payment.id = notification.entity_id
   and payment.deleted_at is null
  where notification.type = 'sales_payment_voided'
) then 1 else 0 end) as no_active_payment_is_labelled_voided;

-- The user's reproduced case: two discarded $82,000 registrations remain as
-- history, while the active $82,000 + $12,000 collections are the only money
-- facts available to both the briefing metric and the dashboard cash counter.
select 1 / (case when (
  select count(*)
  from public.erp_notifications notification
  where notification.type = 'sales_payment_voided'
    and notification.data->>'invoice_reference' = 'FV-00955'
    and (notification.data->>'amount')::numeric = 82000
) = 2 then 1 else 0 end) as fv00955_two_voided_attempts_preserved;

select 1 / (case when (
  select coalesce(sum(payment.amount), 0)
  from public.sales_payments payment
  join public.sales_invoices invoice
    on invoice.tenant_id = payment.tenant_id
   and invoice.id = payment.invoice_id
  where invoice.invoice_number = 'FV-00955'
    and payment.deleted_at is null
) = 94000 then 1 else 0 end) as fv00955_active_payment_total_is_94000;

select 1 / (case when (
  select coalesce(sum((notification.data->>'amount')::numeric), 0)
  from public.erp_notifications notification
  where notification.type = 'sales_payment_received'
    and notification.data->>'invoice_reference' = 'FV-00955'
) = 94000 then 1 else 0 end) as fv00955_briefing_payment_total_is_94000;
