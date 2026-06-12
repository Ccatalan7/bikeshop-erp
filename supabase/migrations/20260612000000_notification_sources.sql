-- Deployment status: DEPLOYED to production xzdvtzdqjeyqxnkqprtf on 2026-06-12
-- Deployment verification: pg_proc confirms create_mechanic_job_erp_notification,
--   create_sales_payment_erp_notification, create_whatsapp_catalog_erp_notification;
--   pg_trigger confirms trg_*_erp_notification attached to mechanic_jobs,
--   sales_payments, and products respectively.
-- Notification sources for the ERP notifications center.
-- Adds AFTER INSERT/UPDATE triggers that write into the existing generic
-- erp_notifications backbone for: new workshop jobs, new sales payments,
-- and WhatsApp catalog products that become customer-visible.
-- Mirrors functions/triggers in supabase/sql/core_schema.sql (idempotent).

-- ============================================================
-- Notification source: new workshop job (trabajo)
-- ============================================================
create or replace function public.create_mechanic_job_erp_notification()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_customer_name text;
  v_body text;
begin
  if NEW.deleted_at is not null then
    return NEW;
  end if;

  select name into v_customer_name
  from public.customers
  where id = NEW.customer_id;

  v_body := coalesce(nullif(NEW.job_number, ''), 'Trabajo')
    || ' · '
    || coalesce(nullif(v_customer_name, ''), 'Cliente');

  insert into public.erp_notifications (
    tenant_id, type, title, body, route,
    entity_type, entity_id, severity, data
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
-- Notification source: new sales payment received
-- ============================================================
create or replace function public.create_sales_payment_erp_notification()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_body text;
begin
  if NEW.deleted_at is not null then
    return NEW;
  end if;

  v_body := coalesce(nullif(NEW.invoice_reference, ''), 'Pago');

  if coalesce(NEW.amount, 0) > 0 then
    v_body := v_body || ' · $' || trim(to_char(NEW.amount, 'FM999G999G999G990'));
  end if;

  insert into public.erp_notifications (
    tenant_id, type, title, body, route,
    entity_type, entity_id, severity, data
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
      'amount', NEW.amount
    )
  ) on conflict (tenant_id, type, entity_type, entity_id) do nothing;

  return NEW;
end;
$$;

drop trigger if exists trg_sales_payment_erp_notification on sales_payments;
create trigger trg_sales_payment_erp_notification
  after insert on sales_payments
  for each row execute function public.create_sales_payment_erp_notification();

-- ============================================================
-- Notification source: WhatsApp catalog product approved (customer-visible)
-- ============================================================
create or replace function public.create_whatsapp_catalog_erp_notification()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_name text;
  v_body text;
begin
  if NEW.whatsapp_catalog_sync_status is distinct from 'customer_visible' then
    return NEW;
  end if;

  if OLD.whatsapp_catalog_sync_status is not distinct from 'customer_visible' then
    return NEW;
  end if;

  v_name := coalesce(
    nullif(NEW.whatsapp_catalog_title, ''),
    nullif(NEW.name, ''),
    'Producto'
  );

  v_body := v_name || ' ya es visible en el catálogo de WhatsApp';

  insert into public.erp_notifications (
    tenant_id, type, title, body, route,
    entity_type, entity_id, severity, data
  ) values (
    NEW.tenant_id,
    'whatsapp_catalog_approved',
    'Producto aprobado en WhatsApp',
    v_body,
    '/inventory/products?product=' || NEW.id::text,
    'product',
    NEW.id,
    'success',
    jsonb_build_object(
      'product_id', NEW.id,
      'product_name', v_name,
      'sku', NEW.sku
    )
  ) on conflict (tenant_id, type, entity_type, entity_id) do update
    set title = excluded.title,
        body = excluded.body,
        route = excluded.route,
        severity = excluded.severity,
        data = excluded.data,
        read_at = null,
        updated_at = now();

  return NEW;
end;
$$;

drop trigger if exists trg_whatsapp_catalog_erp_notification on products;
create trigger trg_whatsapp_catalog_erp_notification
  after update of whatsapp_catalog_sync_status on products
  for each row execute function public.create_whatsapp_catalog_erp_notification();
