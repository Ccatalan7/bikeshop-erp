-- Add distinct company WhatsApp channels and normalized Chilean bank accounts.
-- Deployment status: DEPLOYED on 2026-06-03 to linked Supabase project xzdvtzdqjeyqxnkqprtf.
-- Deployment verification: whatsapp_api_phone_columns=1; company_bank_accounts_tables=1; bank_account_columns=10; company_phones=+56 9 9835 7797 / +56 9 9835 7797 / +56 9 4188 4520; website_api_phone=+56 9 4188 4520.

alter table public.companies
  add column if not exists whatsapp_api_phone text;

create table if not exists public.company_bank_accounts (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references public.tenants(id) on delete cascade not null,
  company_id uuid references public.companies(id) on delete cascade not null,
  label text not null default 'Cuenta principal',
  bank_name text not null,
  account_type text not null default 'Cuenta corriente',
  account_number text not null,
  account_holder_name text not null,
  account_holder_rut text not null,
  contact_email text,
  currency text not null default 'CLP',
  is_default boolean not null default false,
  is_active boolean not null default true,
  notes text,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now()
);

alter table public.company_bank_accounts
  add column if not exists label text not null default 'Cuenta principal',
  add column if not exists bank_name text,
  add column if not exists account_type text not null default 'Cuenta corriente',
  add column if not exists account_number text,
  add column if not exists account_holder_name text,
  add column if not exists account_holder_rut text,
  add column if not exists contact_email text,
  add column if not exists currency text not null default 'CLP',
  add column if not exists is_default boolean not null default false,
  add column if not exists is_active boolean not null default true,
  add column if not exists notes text,
  add column if not exists updated_at timestamp with time zone not null default now();

create index if not exists idx_company_bank_accounts_tenant
  on public.company_bank_accounts(tenant_id);

create index if not exists idx_company_bank_accounts_company
  on public.company_bank_accounts(company_id);

create index if not exists idx_company_bank_accounts_default
  on public.company_bank_accounts(tenant_id, company_id, is_default);

comment on column public.companies.whatsapp_phone is
  'Physical SIM / WhatsApp Business app number used by the shop.';
comment on column public.companies.whatsapp_api_phone is
  'WhatsApp Cloud API / Meta data center number used by internal messaging.';
comment on table public.company_bank_accounts is
  'Tenant-scoped company bank accounts for Chilean transfer instructions and payment routing.';

do $$ begin
  alter table public.company_bank_accounts enable row level security;
  drop policy if exists company_bank_accounts_tenant_isolation
    on public.company_bank_accounts;
  create policy company_bank_accounts_tenant_isolation
    on public.company_bank_accounts
    for all
    using (tenant_id = public.user_tenant_id())
    with check (tenant_id = public.user_tenant_id());
exception when others then null; end $$;

update public.companies
set
  phone = '+56 9 9835 7797',
  whatsapp_phone = '+56 9 9835 7797',
  whatsapp_api_phone = '+56 9 4188 4520',
  updated_at = now()
where tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
  and (
    regexp_replace(coalesce(tax_id, ''), '[^0-9Kk]', '', 'g') = '775419997'
    or regexp_replace(coalesce(rut, ''), '[^0-9Kk]', '', 'g') = '775419997'
    or is_default = true
  );

insert into public.website_settings (tenant_id, key, value, description)
values
  (
    '5443b130-cc28-45af-a420-cd500b288890',
    'contact_phone',
    '+56 9 9835 7797',
    'Telefono publico sincronizado desde datos de empresa'
  ),
  (
    '5443b130-cc28-45af-a420-cd500b288890',
    'seo_phone',
    '+56 9 9835 7797',
    'Telefono SEO sincronizado desde datos de empresa'
  ),
  (
    '5443b130-cc28-45af-a420-cd500b288890',
    'business_phone',
    '+56 9 9835 7797',
    'Telefono comercial sincronizado desde datos de empresa'
  ),
  (
    '5443b130-cc28-45af-a420-cd500b288890',
    'whatsapp',
    '+56 9 9835 7797',
    'WhatsApp tienda/SIM sincronizado desde datos de empresa'
  ),
  (
    '5443b130-cc28-45af-a420-cd500b288890',
    'whatsapp_phone',
    '+56 9 9835 7797',
    'WhatsApp tienda/SIM sincronizado desde datos de empresa'
  ),
  (
    '5443b130-cc28-45af-a420-cd500b288890',
    'whatsapp_business_phone',
    '+56 9 9835 7797',
    'WhatsApp Business con SIM fisica'
  ),
  (
    '5443b130-cc28-45af-a420-cd500b288890',
    'whatsapp_sim_phone',
    '+56 9 9835 7797',
    'WhatsApp Business con SIM fisica'
  ),
  (
    '5443b130-cc28-45af-a420-cd500b288890',
    'whatsapp_api_phone',
    '+56 9 4188 4520',
    'WhatsApp Cloud API / Meta'
  ),
  (
    '5443b130-cc28-45af-a420-cd500b288890',
    'whatsapp_meta_api_phone',
    '+56 9 4188 4520',
    'WhatsApp Cloud API / Meta'
  ),
  (
    '5443b130-cc28-45af-a420-cd500b288890',
    'messaging_whatsapp_phone',
    '+56 9 4188 4520',
    'Numero usado por mensajeria interna hacia WhatsApp'
  )
on conflict (tenant_id, key) do update
set
  value = excluded.value,
  description = excluded.description,
  updated_at = now();
