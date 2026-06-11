-- Add WhatsApp catalog product publishing fields.
-- Deployment status: DEPLOYED to production xzdvtzdqjeyqxnkqprtf on 2026-06-10
-- Deployment verification: information_schema.columns shows is_whatsapp_catalog, whatsapp_catalog_title, whatsapp_catalog_description, and whatsapp_catalog_price on public.products.

alter table public.products
  add column if not exists is_whatsapp_catalog boolean not null default false,
  add column if not exists whatsapp_catalog_title text,
  add column if not exists whatsapp_catalog_description text,
  add column if not exists whatsapp_catalog_price numeric(12,2);

create index if not exists idx_products_whatsapp_catalog
  on public.products(tenant_id, updated_at desc)
  where is_whatsapp_catalog = true;