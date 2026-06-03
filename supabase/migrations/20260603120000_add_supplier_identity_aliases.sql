-- Supplier identity fields for matching legal issuers, trade names, owners,
-- and OCR aliases against the same operational supplier.
-- Deployment status: DEPLOYED on 2026-06-03 to linked Supabase project xzdvtzdqjeyqxnkqprtf.
-- Deployment verification: supplier_identity_columns=4; supplier_identity_indexes=idx_suppliers_aliases, idx_suppliers_identity_search; starken_kaudat_backfill_rows=1.

alter table public.suppliers
  add column if not exists legal_name text,
  add column if not exists trade_name text,
  add column if not exists owner_name text,
  add column if not exists aliases text[] not null default '{}'::text[];

update public.suppliers
set aliases = '{}'::text[]
where aliases is null;

alter table public.suppliers
  alter column aliases set default '{}'::text[],
  alter column aliases set not null;

comment on column public.suppliers.legal_name is
  'Legal issuer or razón social shown on supplier tax documents.';
comment on column public.suppliers.trade_name is
  'Commercial brand or public-facing supplier name.';
comment on column public.suppliers.owner_name is
  'Owner, parent, or controlling company when it differs from the shop-facing supplier.';
comment on column public.suppliers.aliases is
  'Additional OCR/search names that should resolve to this supplier.';

update public.suppliers s
set
  legal_name = coalesce(nullif(s.legal_name, ''), 'Kaudat SpA'),
  owner_name = coalesce(nullif(s.owner_name, ''), 'Kaudat SpA'),
  trade_name = coalesce(nullif(s.trade_name, ''), 'Starken'),
  rut = coalesce(nullif(s.rut, ''), '76.211.240-K'),
  default_tax_treatment = 'tax_included',
  aliases = (
    select array_agg(alias order by alias)
    from (
      select distinct trim(alias) as alias
      from unnest(
        coalesce(s.aliases, '{}'::text[]) ||
        array['Starken', 'Kaudat', 'Kaudat SpA', 'KAUDAT SPA']
      ) as alias
      where trim(alias) <> ''
    ) deduped_aliases
  ),
  updated_at = now()
where lower(s.name) like '%starken%'
   or lower(s.name) like '%kaudat%';

create index if not exists idx_suppliers_aliases
  on public.suppliers using gin (aliases);

create index if not exists idx_suppliers_identity_search
  on public.suppliers using gin (
    to_tsvector(
      'spanish',
      coalesce(name, '') || ' ' ||
      coalesce(legal_name, '') || ' ' ||
      coalesce(trade_name, '') || ' ' ||
      coalesce(owner_name, '')
    )
  );
