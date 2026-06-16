-- Enrich ERP notification sources with manager-actionable detail.
-- Adds a shared actor-name resolver and richer `data` payloads for
-- workshop-job and sales-payment notifications.
--
-- Deployment status: DEPLOYED to production xzdvtzdqjeyqxnkqprtf on 2026-06-13
-- Deployment verification: pg_proc shows erp_actor_display_name(uuid,uuid),
--   create_mechanic_job_erp_notification, create_sales_payment_erp_notification;
--   pg_trigger shows trg_mechanic_job_erp_notification on mechanic_jobs and
--   trg_sales_payment_erp_notification on sales_payments.

-- ============================================================
-- Shared helper: resolve a human-readable actor name from a user id.
-- Prefers the linked employee (trabajador) name, then auth metadata,
-- then email. SECURITY DEFINER so triggers can read auth.users.
-- ============================================================
create or replace function public.erp_actor_display_name(
  p_user_id uuid,
  p_tenant_id uuid
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_name text;
begin
  if p_user_id is null then
    return null;
  end if;

  -- Prefer the linked employee (trabajador) full name.
  select nullif(trim(coalesce(e.first_name, '') || ' ' || coalesce(e.last_name, '')), '')
    into v_name
  from public.user_profiles up
  join public.employees e on e.id = up.employee_id
  where up.user_id = p_user_id
    and up.tenant_id = p_tenant_id
  limit 1;

  if v_name is not null then
    return v_name;
  end if;

  -- Fallback to auth user metadata or email.
  select nullif(
           coalesce(
             u.raw_user_meta_data->>'full_name',
             u.raw_user_meta_data->>'name',
             u.email
           ), '')
    into v_name
  from auth.users u
  where u.id = p_user_id
  limit 1;

  return v_name;
end;
$$;

grant execute on function public.erp_actor_display_name(uuid, uuid) to authenticated;

-- ============================================================
-- Notification source: new workshop job (trabajo) — enriched
-- ============================================================
create or replace function public.create_mechanic_job_erp_notification()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_customer_name text;
  v_bike_label text;
  v_client_request text;
  v_body text;
begin
  -- Skip soft-deleted rows
  if NEW.deleted_at is not null then
    return NEW;
  end if;

  select name into v_customer_name
  from public.customers
  where id = NEW.customer_id;

  select nullif(trim(
           coalesce(b.brand, '') || ' ' || coalesce(b.model, '')
           || case
                when nullif(trim(coalesce(b.color, '')), '') is not null
                  then ' · ' || b.color
                else ''
              end
         ), '')
    into v_bike_label
  from public.bikes b
  where b.id = NEW.bike_id;

  v_client_request := nullif(left(coalesce(NEW.client_request, ''), 300), '');

  v_body := coalesce(nullif(NEW.job_number, ''), 'Trabajo')
    || ' · '
    || coalesce(nullif(v_customer_name, ''), 'Cliente');

  insert into public.erp_notifications (
    tenant_id,
    type,
    title,
    body,
    route,
    entity_type,
    entity_id,
    severity,
    data
  ) values (
    NEW.tenant_id,
    'mechanic_job_created',
    'Nuevo trabajo',
    v_body,
    '/taller/pegas?job=' || NEW.id::text,
    'mechanic_job',
    NEW.id,
    'info',
    jsonb_build_object(
      'job_id', NEW.id,
      'job_number', NEW.job_number,
      'customer_id', NEW.customer_id,
      'customer_name', v_customer_name,
      'bike_id', NEW.bike_id,
      'bike_label', v_bike_label,
      'client_request', v_client_request,
      'priority', NEW.priority,
      'status', NEW.status
    )
  ) on conflict (tenant_id, type, entity_type, entity_id) do nothing;

  return NEW;
end;
$$;

drop trigger if exists trg_mechanic_job_erp_notification on mechanic_jobs;
create trigger trg_mechanic_job_erp_notification
  after insert on mechanic_jobs
  for each row execute function public.create_mechanic_job_erp_notification();

-- ============================================================
-- Notification source: new sales payment received — enriched
-- ============================================================
create or replace function public.create_sales_payment_erp_notification()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_body text;
  v_payment_method text;
  v_customer_name text;
  v_recorded_by text;
begin
  -- Skip soft-deleted rows
  if NEW.deleted_at is not null then
    return NEW;
  end if;

  select name into v_payment_method
  from public.payment_methods
  where tenant_id = NEW.tenant_id
    and id = NEW.payment_method_id;

  select customer_name into v_customer_name
  from public.sales_invoices
  where id = NEW.invoice_id;

  v_recorded_by := public.erp_actor_display_name(auth.uid(), NEW.tenant_id);

  v_body := coalesce(nullif(NEW.invoice_reference, ''), 'Pago');

  if coalesce(NEW.amount, 0) > 0 then
    v_body := v_body || ' · $' || trim(to_char(NEW.amount, 'FM999G999G999G990'));
  end if;

  insert into public.erp_notifications (
    tenant_id,
    type,
    title,
    body,
    route,
    entity_type,
    entity_id,
    severity,
    data
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
    )
  ) on conflict (tenant_id, type, entity_type, entity_id) do nothing;

  return NEW;
end;
$$;

drop trigger if exists trg_sales_payment_erp_notification on sales_payments;
create trigger trg_sales_payment_erp_notification
  after insert on sales_payments
  for each row execute function public.create_sales_payment_erp_notification();
