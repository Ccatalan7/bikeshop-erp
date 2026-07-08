-- Optimize stock movements navigation and product-picker loading.
-- Safe to re-run; indexes are read-path only and do not change data.

create index if not exists idx_products_tenant_name
  on public.products(tenant_id, name);

create index if not exists idx_stock_movements_tenant_recent
  on public.stock_movements(tenant_id, date desc, created_at desc, id desc);

create index if not exists idx_stock_movements_tenant_product_recent
  on public.stock_movements(tenant_id, product_id, date desc, created_at desc, id desc);

create index if not exists idx_stock_adjustments_tenant_product_match
  on public.stock_adjustments(tenant_id, product_id, created_at, adjustment_type, quantity);
