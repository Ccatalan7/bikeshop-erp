-- Smart expense automation foundation:
-- - reusable expense templates/rules
-- - normalized expense links to purchase invoices
-- - transport expense account/category for delivery costs

insert into public.accounts (
  tenant_id,
  code,
  name,
  type,
  category,
  description,
  is_active
)
select
  t.id,
  '6402',
  'Gastos por Transporte',
  'expense',
  'operatingExpense',
  'Fletes, encomiendas y costos de transporte asociados a compras u operaciones',
  true
from public.tenants t
where not exists (
  select 1
  from public.accounts a
  where a.tenant_id = t.id
    and a.code = '6402'
);

insert into public.expense_categories (
  tenant_id,
  name,
  description,
  default_account_id,
  default_tax_rate
)
select
  a.tenant_id,
  'Gastos por Transporte',
  'Fletes, encomiendas y costos de transporte asociados a compras u operaciones',
  a.id,
  19
from public.accounts a
where a.code = '6402'
  and not exists (
    select 1
    from public.expense_categories ec
    where ec.tenant_id = a.tenant_id
      and lower(ec.name) = lower('Gastos por Transporte')
  );

create or replace function public.get_expense_category_name_for_account(
  p_account_code text,
  p_account_name text
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_code text := coalesce(p_account_code, '');
  v_base_code text;
  v_name text := lower(coalesce(p_account_name, ''));
begin
  v_base_code := regexp_replace(v_code, '-.*$', '');

  if v_base_code like '51%' then
    return 'Costo de Ventas';
  end if;

  if v_base_code like '610%' then
    return 'Nómina';
  end if;

  if v_base_code = '6201' then
    return 'Arriendo';
  elsif v_base_code = '6202' then
    return 'Servicios Básicos';
  elsif v_base_code = '6203' then
    return 'Telefonía e Internet';
  elsif v_base_code = '6204' then
    return 'Mantención y Reparaciones';
  elsif v_base_code = '6205' then
    return 'Suministros de Oficina';
  end if;

  if v_base_code = '6301' then
    return 'Marketing y Publicidad';
  elsif v_base_code = '6302' then
    return 'Comisiones de Venta';
  end if;

  if v_base_code = '6401' then
    return 'Gastos de Viaje';
  elsif v_base_code = '6402' then
    return 'Gastos por Transporte';
  end if;

  if v_base_code = '6501' then
    return 'Seguros';
  elsif v_base_code = '6502' then
    return 'Patentes y Contribuciones';
  end if;

  if v_base_code = '6601' then
    return 'Gastos Financieros';
  end if;

  if v_base_code = '6701' then
    return 'Depreciación';
  end if;

  if v_base_code = '6801' then
    return 'Gastos Varios';
  end if;

  if v_name like '%nómina%' or v_name like '%nomina%' or v_name like '%sueldo%' or v_name like '%salario%' then
    return 'Nómina';
  end if;
  if v_name like '%arriendo%' then
    return 'Arriendo';
  end if;
  if v_name like '%internet%' or v_name like '%telefon%' then
    return 'Telefonía e Internet';
  end if;
  if v_name like '%luz%' or v_name like '%agua%' or v_name like '%gas%' or v_name like '%servicio básico%' or v_name like '%servicios básicos%' then
    return 'Servicios Básicos';
  end if;

  if v_name like '%transporte%' or v_name like '%flete%' or v_name like '%envío%' or v_name like '%envio%' or v_name like '%encomienda%' then
    return 'Gastos por Transporte';
  end if;

  return 'Otros Gastos';
end;
$$;

create table if not exists public.expense_templates (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references public.tenants(id) on delete cascade not null,
  name text not null,
  is_active boolean not null default true,
  priority integer not null default 100,
  trigger_category_id uuid references public.expense_categories(id) on delete set null,
  trigger_supplier_id uuid references public.suppliers(id) on delete set null,
  trigger_keywords text[] not null default '{}',
  default_category_id uuid references public.expense_categories(id) on delete set null,
  default_supplier_id uuid references public.suppliers(id) on delete set null,
  default_supplier_name text,
  default_supplier_rut text,
  default_account_id uuid,
  default_payment_method_id uuid,
  default_document_type text not null default 'invoice'
    check (default_document_type in ('invoice','receipt','ticket','reimbursement','other')),
  default_amount numeric(14,2),
  default_description text,
  default_reference_prefix text,
  default_tax_rate numeric(6,3),
  recurrence_interval_months integer,
  next_due_date timestamp with time zone,
  next_review_date timestamp with time zone,
  review_reminder_days integer not null default 15,
  link_purchase_invoice boolean not null default false,
  link_kind text not null default 'general',
  notes text,
  metadata jsonb not null default '{}',
  created_by uuid references auth.users(id),
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now()
);

alter table public.expense_templates
  add column if not exists tenant_id uuid references public.tenants(id) on delete cascade,
  add column if not exists name text,
  add column if not exists is_active boolean not null default true,
  add column if not exists priority integer not null default 100,
  add column if not exists trigger_category_id uuid references public.expense_categories(id) on delete set null,
  add column if not exists trigger_supplier_id uuid references public.suppliers(id) on delete set null,
  add column if not exists trigger_keywords text[] not null default '{}',
  add column if not exists default_category_id uuid references public.expense_categories(id) on delete set null,
  add column if not exists default_supplier_id uuid references public.suppliers(id) on delete set null,
  add column if not exists default_supplier_name text,
  add column if not exists default_supplier_rut text,
  add column if not exists default_account_id uuid,
  add column if not exists default_payment_method_id uuid,
  add column if not exists default_document_type text not null default 'invoice',
  add column if not exists default_amount numeric(14,2),
  add column if not exists default_description text,
  add column if not exists default_reference_prefix text,
  add column if not exists default_tax_rate numeric(6,3),
  add column if not exists recurrence_interval_months integer,
  add column if not exists next_due_date timestamp with time zone,
  add column if not exists next_review_date timestamp with time zone,
  add column if not exists review_reminder_days integer not null default 15,
  add column if not exists link_purchase_invoice boolean not null default false,
  add column if not exists link_kind text not null default 'general',
  add column if not exists notes text,
  add column if not exists metadata jsonb not null default '{}',
  add column if not exists created_by uuid references auth.users(id),
  add column if not exists created_at timestamp with time zone not null default now(),
  add column if not exists updated_at timestamp with time zone not null default now();

do $$ begin
  alter table public.expense_templates
    drop constraint if exists expense_templates_default_account_id_fkey;
  alter table public.expense_templates
    add constraint expense_templates_default_account_id_fkey
    foreign key (tenant_id, default_account_id)
    references public.accounts(tenant_id, id)
    on delete restrict;

  alter table public.expense_templates
    drop constraint if exists expense_templates_default_payment_method_id_fkey;
  alter table public.expense_templates
    add constraint expense_templates_default_payment_method_id_fkey
    foreign key (tenant_id, default_payment_method_id)
    references public.payment_methods(tenant_id, id)
    on delete restrict;
exception
  when undefined_column then null;
  when others then raise notice 'expense_templates FK setup skipped: %', sqlerrm;
end $$;

create unique index if not exists expense_templates_tenant_name_key
  on public.expense_templates(tenant_id, lower(name));
create index if not exists idx_expense_templates_tenant
  on public.expense_templates(tenant_id);
create index if not exists idx_expense_templates_category
  on public.expense_templates(trigger_category_id);
create index if not exists idx_expense_templates_supplier
  on public.expense_templates(trigger_supplier_id);
create index if not exists idx_expense_templates_active_priority
  on public.expense_templates(tenant_id, is_active, priority);

alter table public.expense_templates enable row level security;

drop policy if exists "expense_templates_select" on public.expense_templates;
drop policy if exists "expense_templates_insert" on public.expense_templates;
drop policy if exists "expense_templates_update" on public.expense_templates;
drop policy if exists "expense_templates_delete" on public.expense_templates;

create policy "expense_templates_select" on public.expense_templates
  for select
  to authenticated
  using (tenant_id = public.user_tenant_id());

create policy "expense_templates_insert" on public.expense_templates
  for insert
  to authenticated
  with check (tenant_id = public.user_tenant_id());

create policy "expense_templates_update" on public.expense_templates
  for update
  to authenticated
  using (tenant_id = public.user_tenant_id());

create policy "expense_templates_delete" on public.expense_templates
  for delete
  to authenticated
  using (tenant_id = public.user_tenant_id());

create table if not exists public.expense_links (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references public.tenants(id) on delete cascade not null,
  expense_id uuid not null references public.expenses(id) on delete cascade,
  purchase_invoice_id uuid not null references public.purchase_invoices(id) on delete cascade,
  link_kind text not null default 'general',
  allocated_amount numeric(14,2),
  notes text,
  created_by uuid references auth.users(id),
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now()
);

alter table public.expense_links
  add column if not exists tenant_id uuid references public.tenants(id) on delete cascade,
  add column if not exists expense_id uuid references public.expenses(id) on delete cascade,
  add column if not exists purchase_invoice_id uuid references public.purchase_invoices(id) on delete cascade,
  add column if not exists link_kind text not null default 'general',
  add column if not exists allocated_amount numeric(14,2),
  add column if not exists notes text,
  add column if not exists created_by uuid references auth.users(id),
  add column if not exists created_at timestamp with time zone not null default now(),
  add column if not exists updated_at timestamp with time zone not null default now();

do $$
begin
  if not exists (
    select 1
      from pg_constraint c
     where c.conrelid = 'public.expense_links'::regclass
       and c.contype = 'u'
       and pg_get_constraintdef(c.oid) like '%(tenant_id, expense_id, purchase_invoice_id, link_kind)%'
  ) then
    alter table public.expense_links
      add constraint expense_links_tenant_expense_purchase_kind_key
      unique (tenant_id, expense_id, purchase_invoice_id, link_kind);
  end if;
end $$;

create index if not exists idx_expense_links_tenant
  on public.expense_links(tenant_id);
create index if not exists idx_expense_links_expense
  on public.expense_links(expense_id);
create index if not exists idx_expense_links_purchase_invoice
  on public.expense_links(purchase_invoice_id);

alter table public.expense_links enable row level security;

drop policy if exists "expense_links_select" on public.expense_links;
drop policy if exists "expense_links_insert" on public.expense_links;
drop policy if exists "expense_links_update" on public.expense_links;
drop policy if exists "expense_links_delete" on public.expense_links;

create policy "expense_links_select" on public.expense_links
  for select
  to authenticated
  using (tenant_id = public.user_tenant_id());

create policy "expense_links_insert" on public.expense_links
  for insert
  to authenticated
  with check (tenant_id = public.user_tenant_id());

create policy "expense_links_update" on public.expense_links
  for update
  to authenticated
  using (tenant_id = public.user_tenant_id());

create policy "expense_links_delete" on public.expense_links
  for delete
  to authenticated
  using (tenant_id = public.user_tenant_id());
