-- First-class company profile fields for legal identity, tax activity,
-- public contact data, and cross-module business identity reuse.
-- Deployment status: DEPLOYED on 2026-06-03 to linked Supabase project xzdvtzdqjeyqxnkqprtf.
-- Deployment verification: company_profile_columns=13; vinabike_company_rows=1; business_name=Viñabike; business_legal_name=NEWEN SpA.

alter table public.companies
  add column if not exists legal_name text,
  add column if not exists rut text,
  add column if not exists tax_id text,
  add column if not exists fantasy_name text,
  add column if not exists business_activity text,
  add column if not exists comuna text,
  add column if not exists region text,
  add column if not exists postal_code text,
  add column if not exists country text default 'Chile',
  add column if not exists phone text,
  add column if not exists whatsapp_phone text,
  add column if not exists support_phone text,
  add column if not exists email text,
  add column if not exists billing_email text,
  add column if not exists public_email text,
  add column if not exists website_url text,
  add column if not exists is_default boolean default false,
  add column if not exists updated_at timestamp with time zone not null default now(),
  add column if not exists metadata jsonb not null default '{}'::jsonb;

update public.companies
set metadata = '{}'::jsonb
where metadata is null;

alter table public.companies
  alter column metadata set default '{}'::jsonb,
  alter column metadata set not null;

update public.companies
set tax_id = coalesce(nullif(tax_id, ''), nullif(rut, ''))
where tax_id is null or tax_id = '';

comment on column public.companies.name is
  'Internal/display company name used in the ERP.';
comment on column public.companies.legal_name is
  'Legal name or razon social used for tax documents.';
comment on column public.companies.fantasy_name is
  'Commercial/fantasy name used publicly and operationally.';
comment on column public.companies.tax_id is
  'Tax identifier, RUT in Chile.';
comment on column public.companies.rut is
  'Legacy RUT mirror kept for older modules while tax_id becomes canonical.';
comment on column public.companies.business_activity is
  'Tax activity or giro for accounting and document handling.';
comment on column public.companies.website_url is
  'Primary public website URL.';
comment on column public.companies.metadata is
  'Reserved structured company metadata for sync/integration flags.';

create index if not exists idx_companies_default
  on public.companies(tenant_id, is_default);

create index if not exists idx_companies_identity_search
  on public.companies using gin (
    to_tsvector(
      'spanish',
      coalesce(name, '') || ' ' ||
      coalesce(legal_name, '') || ' ' ||
      coalesce(fantasy_name, '') || ' ' ||
      coalesce(tax_id, '') || ' ' ||
      coalesce(business_activity, '')
    )
  );

insert into public.companies (
  tenant_id,
  name,
  legal_name,
  fantasy_name,
  tax_id,
  business_activity,
  country,
  email,
  public_email,
  billing_email,
  is_default,
  metadata
)
select
  t.id,
  'Viñabike',
  'NEWEN SpA',
  'Viñabike',
  '77.541.999-7',
  'Venta al por menor de bicicletas y sus repuestos en comercios especializados',
  'Chile',
  coalesce(nullif(t.owner_email, ''), 'vinabikechile@gmail.com'),
  coalesce(nullif(t.owner_email, ''), 'vinabikechile@gmail.com'),
  coalesce(nullif(t.owner_email, ''), 'vinabikechile@gmail.com'),
  true,
  jsonb_build_object('seeded_from', '20260603143000_add_company_profile_fields')
from public.tenants t
where t.id = '5443b130-cc28-45af-a420-cd500b288890'
  and not exists (
    select 1
    from public.companies c
    where c.tenant_id = t.id
      and (
        regexp_replace(coalesce(c.tax_id, ''), '[^0-9Kk]', '', 'g') = '775419997'
        or regexp_replace(coalesce(c.rut, ''), '[^0-9Kk]', '', 'g') = '775419997'
      )
  );

update public.companies
set
  name = 'Viñabike',
  legal_name = 'NEWEN SpA',
  fantasy_name = 'Viñabike',
  tax_id = '77.541.999-7',
  rut = '77.541.999-7',
  business_activity = 'Venta al por menor de bicicletas y sus repuestos en comercios especializados',
  country = 'Chile',
  email = coalesce(nullif(email, ''), 'vinabikechile@gmail.com'),
  public_email = coalesce(nullif(public_email, ''), 'vinabikechile@gmail.com'),
  billing_email = coalesce(nullif(billing_email, ''), 'vinabikechile@gmail.com'),
  is_default = true,
  metadata = coalesce(metadata, '{}'::jsonb) ||
    jsonb_build_object('seeded_from', '20260603143000_add_company_profile_fields'),
  updated_at = now()
where tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
  and (
    regexp_replace(coalesce(tax_id, ''), '[^0-9Kk]', '', 'g') = '775419997'
    or regexp_replace(coalesce(rut, ''), '[^0-9Kk]', '', 'g') = '775419997'
  );

update public.companies
set is_default = false
where tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
  and tax_id is distinct from '77.541.999-7'
  and is_default = true;

update public.tenants
set
  shop_name = 'Viñabike',
  owner_email = coalesce(nullif(owner_email, ''), 'vinabikechile@gmail.com'),
  updated_at = now()
where id = '5443b130-cc28-45af-a420-cd500b288890';

insert into public.website_settings (tenant_id, key, value, description)
values
  (
    '5443b130-cc28-45af-a420-cd500b288890',
    'site_title',
    'Viñabike',
    'Titulo publico sincronizado desde datos de empresa'
  ),
  (
    '5443b130-cc28-45af-a420-cd500b288890',
    'store_name',
    'Viñabike',
    'Nombre publico sincronizado desde datos de empresa'
  ),
  (
    '5443b130-cc28-45af-a420-cd500b288890',
    'business_name',
    'Viñabike',
    'Nombre comercial sincronizado desde datos de empresa'
  ),
  (
    '5443b130-cc28-45af-a420-cd500b288890',
    'business_legal_name',
    'NEWEN SpA',
    'Razon social sincronizada desde datos de empresa'
  ),
  (
    '5443b130-cc28-45af-a420-cd500b288890',
    'business_fantasy_name',
    'Viñabike',
    'Nombre de fantasia sincronizado desde datos de empresa'
  ),
  (
    '5443b130-cc28-45af-a420-cd500b288890',
    'business_tax_id',
    '77.541.999-7',
    'RUT sincronizado desde datos de empresa'
  ),
  (
    '5443b130-cc28-45af-a420-cd500b288890',
    'business_activity',
    'Venta al por menor de bicicletas y sus repuestos en comercios especializados',
    'Giro sincronizado desde datos de empresa'
  ),
  (
    '5443b130-cc28-45af-a420-cd500b288890',
    'contact_email',
    'vinabikechile@gmail.com',
    'Email publico sincronizado desde datos de empresa'
  ),
  (
    '5443b130-cc28-45af-a420-cd500b288890',
    'seo_email',
    'vinabikechile@gmail.com',
    'Email SEO sincronizado desde datos de empresa'
  )
on conflict (tenant_id, key) do update
set
  value = excluded.value,
  description = excluded.description,
  updated_at = now();
