-- 20261030190000: a product that is not a service and has no tax carries
-- Chile's 19 % IVA.
--
-- 15 of the 17 products created in October 2026 were saved with tax_rate
-- null, from whatever screen created them. The single online-sale rule
-- (catalog_product_web_block_v1) reads null as 'missing_tax' and hides the
-- product: 11 of them had stock and were not sold on vinabike.cl, and the ERP
-- showed them as «Exento». The 1.0.43 store run failed on one of them
-- (Camara 10Ten 24, SKU 24053): its old link answered 404.
--
-- 1,588 products carry 19 and one carries 0 on purpose. So the base decides
-- for every shop, whatever path writes the row: an unknown tax becomes 19, an
-- explicit 0 (exempt) is kept, and a service (which never reaches the cart)
-- keeps none. This ends «sin clasificar» for new products (owner, 2026-10-30):
-- it waited for a person who did not come. Checkout and the web still fail
-- closed on an unsupported rate, and trg_capture_product_tax_classification_event
-- (20260718220000) records every change, the backfill below included.

begin;

create or replace function public.products_default_tax_rate()
returns trigger
language plpgsql
set search_path = pg_catalog, public, pg_temp
as $$
begin
  if new.tax_rate is null
     and coalesce(new.product_type, 'product') <> 'service' then
    new.tax_rate := 19;
  end if;
  return new;
end;
$$;

revoke all on function public.products_default_tax_rate()
  from public, anon, authenticated, service_role;

drop trigger if exists trg_products_default_tax_rate on public.products;
create trigger trg_products_default_tax_rate
  before insert or update of tax_rate, product_type
  on public.products
  for each row
  execute function public.products_default_tax_rate();

-- The products already saved without tax, in every shop (the rule above is
-- the same for all of them), each with its audit event.
select set_config(
  'app.product_tax_classification_source',
  'migration_20261030190000_products_default_tax_rate',
  true
);
select set_config(
  'app.product_tax_classification_reason',
  'Producto sin IVA: 19 % por defecto',
  true
);

update public.products
   set tax_rate = 19
 where tax_rate is null
   and coalesce(product_type, 'product') <> 'service';

commit;
