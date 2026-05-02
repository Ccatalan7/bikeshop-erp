-- Durable ERP notifications for online orders.
-- These rows power app-shell badges/overlays across refreshes and devices.

create table if not exists public.erp_notifications (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references public.tenants(id) on delete cascade not null,
  type text not null,
  title text not null,
  body text,
  route text,
  entity_type text,
  entity_id uuid,
  severity text not null default 'info'
    check (severity in ('info', 'success', 'warning', 'critical')),
  data jsonb not null default '{}'::jsonb,
  read_at timestamp with time zone,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now(),
  unique(tenant_id, type, entity_type, entity_id)
);

create index if not exists idx_erp_notifications_tenant_unread
  on public.erp_notifications(tenant_id, type, created_at desc)
  where read_at is null;
create index if not exists idx_erp_notifications_entity
  on public.erp_notifications(tenant_id, entity_type, entity_id);

alter table public.erp_notifications enable row level security;

drop policy if exists "erp_notifications_select" on public.erp_notifications;
create policy "erp_notifications_select" on public.erp_notifications
  for select using (tenant_id = public.user_tenant_id());

drop policy if exists "erp_notifications_update" on public.erp_notifications;
create policy "erp_notifications_update" on public.erp_notifications
  for update using (tenant_id = public.user_tenant_id())
  with check (tenant_id = public.user_tenant_id());

grant select, update on public.erp_notifications to authenticated;

drop trigger if exists trg_erp_notifications_updated_at on public.erp_notifications;
create trigger trg_erp_notifications_updated_at
  before update on public.erp_notifications
  for each row execute procedure public.set_updated_at();

do $$
begin
  if exists (
    select 1
    from pg_publication
    where pubname = 'supabase_realtime'
  ) and not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'erp_notifications'
  ) then
    alter publication supabase_realtime add table public.erp_notifications;
  end if;
end $$;

create or replace function public.create_online_order_erp_notification()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_body text;
begin
  v_body := coalesce(nullif(NEW.order_number, ''), 'Pedido web')
    || ' · '
    || coalesce(nullif(NEW.customer_name, ''), 'Cliente');

  if coalesce(NEW.total, 0) > 0 then
    v_body := v_body || ' · $' || trim(to_char(NEW.total, 'FM999G999G999G990'));
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
    'online_order_created',
    'Nueva venta online',
    v_body,
    '/website/orders?order=' || NEW.id::text,
    'online_order',
    NEW.id,
    'success',
    jsonb_build_object(
      'order_id', NEW.id,
      'order_number', NEW.order_number,
      'customer_name', NEW.customer_name,
      'total', NEW.total,
      'payment_status', NEW.payment_status,
      'delivery_type', NEW.delivery_type
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

drop trigger if exists trg_online_order_erp_notification on public.online_orders;
create trigger trg_online_order_erp_notification
  after insert on public.online_orders
  for each row execute function public.create_online_order_erp_notification();
