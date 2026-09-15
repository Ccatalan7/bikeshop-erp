begin;

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);

select plan(34);

select has_trigger(
  'public',
  'erp_notifications',
  'trg_erp_notifications_lifecycle_state',
  'all notification sources share one inactive payload normalizer'
);

select ok(
  not has_function_privilege(
    'authenticated',
    'public.normalize_erp_notification_lifecycle_state()',
    'EXECUTE'
  ),
  'clients cannot invoke the lifecycle payload normalizer directly'
);

select ok(
  exists (
    select 1
    from pg_trigger trigger_row
    where trigger_row.tgrelid = 'public.mechanic_jobs'::regclass
      and trigger_row.tgname = 'trg_mechanic_job_erp_notification'
      and not trigger_row.tgisinternal
      and pg_get_triggerdef(trigger_row.oid)
        like '%AFTER INSERT OR DELETE OR UPDATE OF deleted_at ON public.mechanic_jobs%'
  ),
  'job notifications observe insert, archive, restore, and physical deletion'
);

select has_trigger(
  'public',
  'expenses',
  'trg_expense_notification_lifecycle',
  'expenses have a dedicated lifecycle notification trigger'
);

select has_trigger(
  'public',
  'online_orders',
  'trg_online_order_notification_lifecycle',
  'online orders have a dedicated lifecycle notification trigger'
);

select ok(
  not has_function_privilege(
    'authenticated',
    'public.create_mechanic_job_erp_notification()',
    'EXECUTE'
  ),
  'clients cannot invoke the job notification trigger directly'
);

select ok(
  not has_function_privilege(
    'authenticated',
    'public.reconcile_expense_erp_notification_lifecycle()',
    'EXECUTE'
  ),
  'clients cannot invoke the expense lifecycle trigger directly'
);

select ok(
  not has_function_privilege(
    'authenticated',
    'public.reconcile_online_order_erp_notification_lifecycle()',
    'EXECUTE'
  ),
  'clients cannot invoke the order lifecycle trigger directly'
);

insert into public.tenants (id, shop_name)
values (
  '98650000-0000-4000-8000-000000000001',
  'Notification Counter Lifecycle Test'
);

insert into auth.users (
  id,
  aud,
  role,
  email,
  encrypted_password,
  email_confirmed_at,
  raw_app_meta_data,
  raw_user_meta_data,
  created_at,
  updated_at
) values (
  '98650000-0000-4000-8000-000000000099',
  'authenticated',
  'authenticated',
  'notification-counter-lifecycle@example.invalid',
  '',
  now(),
  '{}'::jsonb,
  jsonb_build_object('name', 'Ana Ciclo'),
  now(),
  now()
);

delete from public.user_profiles
where user_id = '98650000-0000-4000-8000-000000000099';

insert into public.user_profiles (user_id, tenant_id, role, is_active)
values (
  '98650000-0000-4000-8000-000000000099',
  '98650000-0000-4000-8000-000000000001',
  'admin',
  true
);

select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub', '98650000-0000-4000-8000-000000000099',
    'role', 'authenticated'
  )::text,
  true
);
select set_config(
  'request.jwt.claim.sub',
  '98650000-0000-4000-8000-000000000099',
  true
);

insert into public.customers (id, tenant_id, name)
values (
  '98650000-0000-4000-8000-000000000010',
  '98650000-0000-4000-8000-000000000001',
  'Cliente ciclo'
);

insert into public.bikes (
  id,
  tenant_id,
  customer_id,
  brand,
  model,
  color
) values (
  '98650000-0000-4000-8000-000000000020',
  '98650000-0000-4000-8000-000000000001',
  '98650000-0000-4000-8000-000000000010',
  'Oxford',
  'Ciclo',
  'Azul'
);

insert into public.mechanic_jobs (
  id,
  tenant_id,
  customer_id,
  bike_id,
  job_number,
  job_type,
  workflow_kind,
  intake_kind,
  client_request
) values (
  '98650000-0000-4000-8000-000000000030',
  '98650000-0000-4000-8000-000000000001',
  '98650000-0000-4000-8000-000000000010',
  '98650000-0000-4000-8000-000000000020',
  'PG-NOTIFY-LIFECYCLE-001',
  'service',
  'service',
  'bike',
  'Revisar transmisión'
);

select is(
  (
    select type
    from public.erp_notifications
    where entity_type = 'mechanic_job'
      and entity_id = '98650000-0000-4000-8000-000000000030'
  ),
  'mechanic_job_created',
  'an active job starts as new work activity'
);

select is(
  (
    select count(*)::integer
    from public.erp_notifications
    where entity_type = 'mechanic_job'
      and entity_id = '98650000-0000-4000-8000-000000000030'
  ),
  1,
  'one job starts with one notification identity'
);

update public.erp_notifications
set read_at = '2026-08-17 20:00:00+00'
where entity_type = 'mechanic_job'
  and entity_id = '98650000-0000-4000-8000-000000000030';

create temp table job_notification_baseline on commit drop as
select id, created_at, read_at
from public.erp_notifications
where entity_type = 'mechanic_job'
  and entity_id = '98650000-0000-4000-8000-000000000030';

do $$
begin
  perform public.set_mechanic_job_archived(
    '98650000-0000-4000-8000-000000000030',
    true,
    'Duplicado de prueba',
    'notification-counter-job-archive'
  );
end;
$$;

select is(
  (
    select type
    from public.erp_notifications
    where entity_type = 'mechanic_job'
      and entity_id = '98650000-0000-4000-8000-000000000030'
  ),
  'mechanic_job_archived',
  'archiving a job removes its active counter type'
);

select is(
  (
    select title
    from public.erp_notifications
    where entity_type = 'mechanic_job'
      and entity_id = '98650000-0000-4000-8000-000000000030'
  ),
  'Trabajo eliminado',
  'archived work is labelled with the canonical Eliminados language'
);

select ok(
  (
    select data @> '{"is_inactive": true, "inactive_reason": "archived"}'::jsonb
    from public.erp_notifications
    where entity_type = 'mechanic_job'
      and entity_id = '98650000-0000-4000-8000-000000000030'
  ),
  'archived work carries the shared inactive payload contract'
);

select is(
  (
    select data->>'removed_by_name'
    from public.erp_notifications
    where entity_type = 'mechanic_job'
      and entity_id = '98650000-0000-4000-8000-000000000030'
  ),
  'Ana Ciclo',
  'job removal keeps the tenant-safe actor display'
);

select ok(
  (
    select notification.id = baseline.id
       and notification.created_at = baseline.created_at
       and notification.read_at = baseline.read_at
    from public.erp_notifications notification
    join job_notification_baseline baseline on true
    where notification.entity_type = 'mechanic_job'
      and notification.entity_id = '98650000-0000-4000-8000-000000000030'
  ),
  'job lifecycle conversion preserves identity, recording time, and read state'
);

do $$
begin
  perform public.set_mechanic_job_archived(
    '98650000-0000-4000-8000-000000000030',
    false,
    'Restauración de prueba',
    'notification-counter-job-restore'
  );
end;
$$;

select is(
  (
    select type
    from public.erp_notifications
    where entity_type = 'mechanic_job'
      and entity_id = '98650000-0000-4000-8000-000000000030'
  ),
  'mechanic_job_created',
  'restoring a job returns the same activity to the active counter type'
);

select ok(
  (
    select not data ? 'is_inactive'
    from public.erp_notifications
    where entity_type = 'mechanic_job'
      and entity_id = '98650000-0000-4000-8000-000000000030'
  ),
  'restoring a job clears its inactive payload state'
);

insert into public.expenses (
  id,
  tenant_id,
  expense_number,
  supplier_name,
  document_type,
  issue_date,
  posting_status,
  payment_status,
  subtotal,
  tax_amount,
  total_amount,
  amount_paid,
  balance,
  created_by
) values (
  '98650000-0000-4000-8000-000000000040',
  '98650000-0000-4000-8000-000000000001',
  'GTO-NOTIFY-LIFECYCLE-001',
  'Proveedor ciclo',
  'invoice',
  '2026-08-17 18:00:00+00',
  'draft',
  'pending',
  10000,
  1900,
  11900,
  0,
  11900,
  '98650000-0000-4000-8000-000000000099'
);

select is(
  (
    select type
    from public.erp_notifications
    where entity_type = 'expense'
      and entity_id = '98650000-0000-4000-8000-000000000040'
  ),
  'expense_recorded',
  'an active expense starts as recorded activity'
);

update public.expenses
set posting_status = 'void'
where id = '98650000-0000-4000-8000-000000000040';

select is(
  (
    select type
    from public.erp_notifications
    where entity_type = 'expense'
      and entity_id = '98650000-0000-4000-8000-000000000040'
  ),
  'expense_voided',
  'voiding an expense removes its active financial counter type'
);

select ok(
  (
    select data @> '{"is_inactive": true, "inactive_reason": "voided"}'::jsonb
    from public.erp_notifications
    where entity_type = 'expense'
      and entity_id = '98650000-0000-4000-8000-000000000040'
  ),
  'a voided expense carries the shared inactive payload contract'
);

update public.expenses
set posting_status = 'draft'
where id = '98650000-0000-4000-8000-000000000040';

select is(
  (
    select type
    from public.erp_notifications
    where entity_type = 'expense'
      and entity_id = '98650000-0000-4000-8000-000000000040'
  ),
  'expense_recorded',
  'restoring a voided expense returns the same active activity type'
);

delete from public.expenses
where id = '98650000-0000-4000-8000-000000000040';

select is(
  (
    select count(*)::integer
    from public.expenses
    where id = '98650000-0000-4000-8000-000000000040'
  ),
  0,
  'the source expense is physically deleted'
);

select is(
  (
    select type
    from public.erp_notifications
    where entity_type = 'expense'
      and entity_id = '98650000-0000-4000-8000-000000000040'
  ),
  'expense_deleted',
  'deleting an expense leaves truthful non-financial history'
);

select is(
  (
    select count(*)::integer
    from public.erp_notifications
    where entity_type = 'expense'
      and entity_id = '98650000-0000-4000-8000-000000000040'
  ),
  1,
  'expense void/restore/delete keeps one notification identity'
);

insert into public.sales_invoices (
  id,
  tenant_id,
  invoice_number,
  customer_name,
  status,
  subtotal,
  net_amount,
  iva_amount,
  total,
  paid_amount,
  balance,
  tax_treatment,
  items
) values (
  '98650000-0000-4000-8000-000000000045',
  '98650000-0000-4000-8000-000000000001',
  'FV-NOTIFY-LIFECYCLE-001',
  'Cliente ciclo',
  'draft',
  25000,
  25000,
  0,
  25000,
  0,
  25000,
  'no_tax',
  '[]'::jsonb
);

insert into public.online_orders (
  id,
  tenant_id,
  order_number,
  customer_id,
  customer_email,
  customer_name,
  subtotal,
  total,
  status,
  payment_status,
  sales_invoice_id
) values (
  '98650000-0000-4000-8000-000000000050',
  '98650000-0000-4000-8000-000000000001',
  'WEB-NOTIFY-LIFECYCLE-001',
  '98650000-0000-4000-8000-000000000010',
  'cliente-ciclo@example.invalid',
  'Cliente ciclo',
  25000,
  25000,
  'pending',
  'pending',
  '98650000-0000-4000-8000-000000000045'
);

select is(
  (
    select type
    from public.erp_notifications
    where entity_type = 'online_order'
      and entity_id = '98650000-0000-4000-8000-000000000050'
  ),
  'online_order_created',
  'an active online order starts as new-order activity'
);

update public.erp_notifications
set read_at = '2026-08-17 20:05:00+00'
where entity_type = 'online_order'
  and entity_id = '98650000-0000-4000-8000-000000000050';

create temp table order_notification_baseline on commit drop as
select id, created_at, read_at
from public.erp_notifications
where entity_type = 'online_order'
  and entity_id = '98650000-0000-4000-8000-000000000050';

update public.online_orders
set status = 'cancelled',
    cancelled_at = '2026-08-17 20:06:00+00',
    cancelled_reason = 'Cliente desistió',
    cancelled_by = '98650000-0000-4000-8000-000000000099'
where id = '98650000-0000-4000-8000-000000000050';

select is(
  (
    select type
    from public.erp_notifications
    where entity_type = 'online_order'
      and entity_id = '98650000-0000-4000-8000-000000000050'
  ),
  'online_order_cancelled',
  'cancelling an order removes its active counter type'
);

select ok(
  (
    select data @> '{"is_inactive": true, "inactive_reason": "cancelled"}'::jsonb
    from public.erp_notifications
    where entity_type = 'online_order'
      and entity_id = '98650000-0000-4000-8000-000000000050'
  ),
  'a cancelled order carries the shared inactive payload contract'
);

select is(
  (
    select data->>'cancelled_by_name'
    from public.erp_notifications
    where entity_type = 'online_order'
      and entity_id = '98650000-0000-4000-8000-000000000050'
  ),
  'Ana Ciclo',
  'order cancellation keeps the tenant-safe actor display'
);

select ok(
  (
    select notification.id = baseline.id
       and notification.created_at = baseline.created_at
       and notification.read_at = baseline.read_at
    from public.erp_notifications notification
    join order_notification_baseline baseline on true
    where notification.entity_type = 'online_order'
      and notification.entity_id = '98650000-0000-4000-8000-000000000050'
  ),
  'order lifecycle conversion preserves identity, recording time, and read state'
);

update public.online_orders
set status = 'pending'
where id = '98650000-0000-4000-8000-000000000050';

select is(
  (
    select type
    from public.erp_notifications
    where entity_type = 'online_order'
      and entity_id = '98650000-0000-4000-8000-000000000050'
  ),
  'online_order_created',
  'restoring an order returns the same active activity type'
);

select ok(
  (
    select not data ? 'is_inactive'
    from public.erp_notifications
    where entity_type = 'online_order'
      and entity_id = '98650000-0000-4000-8000-000000000050'
  ),
  'restoring an order clears its inactive payload state'
);

select is(
  (
    select count(*)::integer
    from (
      select entity_type, entity_id
      from public.erp_notifications
      where tenant_id = '98650000-0000-4000-8000-000000000001'
        and entity_type in ('mechanic_job', 'expense', 'online_order')
      group by entity_type, entity_id
      having count(*) <> 1
    ) duplicates
  ),
  0,
  'every tested source entity retains exactly one notification identity'
);

select is(
  (
    select count(*)::integer
    from public.erp_notifications notification
    left join public.mechanic_jobs job
      on notification.entity_type = 'mechanic_job'
     and job.tenant_id = notification.tenant_id
     and job.id = notification.entity_id
    left join public.expenses expense
      on notification.entity_type = 'expense'
     and expense.tenant_id = notification.tenant_id
     and expense.id = notification.entity_id
    left join public.online_orders order_row
      on notification.entity_type = 'online_order'
     and order_row.tenant_id = notification.tenant_id
     and order_row.id = notification.entity_id
    where notification.tenant_id = '98650000-0000-4000-8000-000000000001'
      and (
        notification.type = 'mechanic_job_created'
          and (job.id is null or job.deleted_at is not null)
        or notification.type = 'expense_recorded'
          and (expense.id is null or expense.posting_status = 'void')
        or notification.type = 'online_order_created'
          and (order_row.id is null or order_row.status = 'cancelled')
      )
  ),
  0,
  'no active counter type points at an inactive or missing source fact'
);

select ok(
  not exists (
    select 1
    from public.erp_notifications
    where tenant_id = '98650000-0000-4000-8000-000000000001'
      and type in (
        'mechanic_job_archived',
        'sales_payment_voided',
        'expense_voided',
        'expense_deleted',
        'online_order_cancelled'
      )
      and coalesce((data->>'is_inactive')::boolean, false) is false
  ),
  'every inactive lifecycle type carries the shared inactive flag'
);

select * from finish();
rollback;
