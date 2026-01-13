-- Enforce: services never track stock
-- Source of truth: supabase/sql/core_schema.sql
-- - Backfill + trigger: lines 1856-1904
-- - search_products RPC: lines 1920-2007
-- - track_product_stock_changes: lines 2312-2364

begin;

-- Backfill existing rows (all tenants)
update products
   set is_service = true,
       track_stock = false,
       inventory_qty = 0,
       stock_quantity = 0,
       min_stock_level = 0,
       max_stock_level = 0
 where product_type = 'service'
   and (
     is_service is distinct from true
     or track_stock is distinct from false
     or coalesce(inventory_qty, 0) <> 0
     or coalesce(stock_quantity, 0) <> 0
     or coalesce(min_stock_level, 0) <> 0
     or coalesce(max_stock_level, 0) <> 0
   );

-- Keep service flags consistent even if callers forget.
create or replace function public.sync_product_service_flags()
returns trigger
language plpgsql
as $$
begin
  if NEW.product_type is null then
    NEW.product_type := 'product';
  end if;

  NEW.is_service := (NEW.product_type = 'service');

  if NEW.is_service then
    NEW.track_stock := false;
    NEW.inventory_qty := 0;
    NEW.stock_quantity := 0;
    NEW.min_stock_level := 0;
    NEW.max_stock_level := 0;
  end if;

  return NEW;
end;
$$;

drop trigger if exists trg_sync_product_service_flags on products;
create trigger trg_sync_product_service_flags
  before insert or update of product_type, is_service, track_stock, inventory_qty, stock_quantity, min_stock_level, max_stock_level
  on products
  for each row
  execute function public.sync_product_service_flags();

-- PUBLIC STORE SEARCH (RPC): include services and non-stock-tracked items.
create or replace function public.search_products(
  p_search_term text,
  p_tenant_id uuid,
  p_limit int default 10
)
returns setof public.products
language sql
security invoker
set search_path = public
as $$
  with q as (
    select
      unaccent(lower(coalesce(p_search_term, ''))) as term,
      array_remove(
        regexp_split_to_array(
          regexp_replace(unaccent(lower(coalesce(p_search_term, ''))), '[^a-z0-9]+', ' ', 'g'),
          '\\s+'
        ),
        ''
      ) as tokens
  )
  select p.*
  from public.products p
  cross join q
  where
    q.term <> ''
    and p.tenant_id = p_tenant_id
    and p.is_active = true
    and (
      p.product_type = 'service'
      or coalesce(p.track_stock, true) = false
      or coalesce(p.inventory_qty, 0) > 0
      or coalesce(p.stock_quantity, 0) > 0
    )

    -- AND semantics across tokens, OR semantics across fields
    and (
      select bool_and(
        case
          -- Numeric-only tokens (e.g. "26") often represent sizes.
          -- Avoid matching them inside long identifier fields like SKU/barcodes,
          -- which can create false positives.
          when t ~ '^[0-9]+$' then
            (
              unaccent(lower(coalesce(p.name, ''))) like '%' || t || '%'
              or unaccent(lower(coalesce(p.description, ''))) like '%' || t || '%'
              or unaccent(lower(coalesce(p.brand, ''))) like '%' || t || '%'
              or unaccent(lower(coalesce(p.model, ''))) like '%' || t || '%'
              or unaccent(lower(coalesce(p.manufacturer, ''))) like '%' || t || '%'
              or unaccent(lower(coalesce(p.category_name, ''))) like '%' || t || '%'
              or unaccent(lower(coalesce(p.sku, ''))) ~ ('(^|[^0-9])' || t || '([^0-9]|$)')
              or unaccent(lower(coalesce(p.manufacturer_sku, ''))) ~ ('(^|[^0-9])' || t || '([^0-9]|$)')
            )
          else
            (
              unaccent(lower(coalesce(p.name, ''))) like '%' || t || '%'
              or unaccent(lower(coalesce(p.sku, ''))) like '%' || t || '%'
              or unaccent(lower(coalesce(p.description, ''))) like '%' || t || '%'
              or unaccent(lower(coalesce(p.brand, ''))) like '%' || t || '%'
              or unaccent(lower(coalesce(p.model, ''))) like '%' || t || '%'
              or unaccent(lower(coalesce(p.manufacturer, ''))) like '%' || t || '%'
              or unaccent(lower(coalesce(p.manufacturer_sku, ''))) like '%' || t || '%'
              or unaccent(lower(coalesce(p.barcode, ''))) like '%' || t || '%'
              or unaccent(lower(coalesce(p.gtin, ''))) like '%' || t || '%'
              or unaccent(lower(coalesce(p.category_name, ''))) like '%' || t || '%'
            )
        end
      )
      from unnest(q.tokens) as t
    )

  order by
    -- Prefer direct substring hits in the most relevant fields
    case when unaccent(lower(coalesce(p.sku, ''))) = q.term then 5 else 0 end desc,
    case when unaccent(lower(coalesce(p.name, ''))) like '%' || q.term || '%' then 4 else 0 end desc,
    case when unaccent(lower(coalesce(p.sku, ''))) like '%' || q.term || '%' then 3 else 0 end desc,
    case when unaccent(lower(coalesce(p.brand, ''))) like '%' || q.term || '%' then 2 else 0 end desc,

    -- Then trigram similarity
    greatest(
      similarity(unaccent(lower(coalesce(p.name, ''))), q.term),
      similarity(unaccent(lower(coalesce(p.sku, ''))), q.term),
      similarity(unaccent(lower(coalesce(p.description, ''))), q.term)
    ) desc,

    -- Stable ordering
    p.name asc

  limit greatest(p_limit, 0);
$$;

grant execute on function public.search_products(text, uuid, int) to anon;
grant execute on function public.search_products(text, uuid, int) to authenticated;

-- Track manual stock changes on products table (skip services/non-stock items)
create or replace function track_product_stock_changes()
returns trigger as $$
declare
  v_adjustment_type text;
  v_reason text;
  v_reference text;
begin
  -- Services and non-stock-tracked items should not generate stock adjustments.
  if coalesce(NEW.product_type, 'product') = 'service'
     or coalesce(NEW.track_stock, true) = false then
    return NEW;
  end if;

  -- CRITICAL: Only track MANUAL changes, not automatic ones from invoice triggers
  -- Skip if this update is triggered by invoice consumption functions
  if current_setting('app.skip_stock_adjustment_trigger', true) = 'true' then
    return NEW;
  end if;

  -- Only track if stock_quantity actually changed
  if (TG_OP = 'UPDATE' and OLD.stock_quantity <> NEW.stock_quantity) then
    -- Determine adjustment type based on context
    if current_setting('app.stock_adjustment_context', true) = 'import' then
      v_adjustment_type := 'import';
      v_reason := coalesce(
        current_setting('app.import_reason', true),
        'Stock updated via import'
      );
      v_reference := current_setting('app.import_reference', true); -- Import filename or batch ID
    else
      v_adjustment_type := 'manual';
      v_reason := 'Manual adjustment via product form';
      v_reference := null;
    end if;

    insert into stock_adjustments (
      tenant_id,
      product_id,
      adjustment_type,
      quantity,
      stock_before,
      stock_after,
      reason,
      reference,
      created_by
    ) values (
      NEW.tenant_id,
      NEW.id,
      v_adjustment_type,
      NEW.stock_quantity - OLD.stock_quantity,
      OLD.stock_quantity,
      NEW.stock_quantity,
      v_reason,
      v_reference,
      auth.uid()
    );
  elsif (TG_OP = 'INSERT' and NEW.stock_quantity > 0) then
    -- Track initial stock when product is created with stock
    -- Check if this is part of an import
    if current_setting('app.stock_adjustment_context', true) = 'import' then
      v_adjustment_type := 'import';
      v_reason := coalesce(
        current_setting('app.import_reason', true),
        'Initial stock via import'
      );
      v_reference := current_setting('app.import_reference', true);
    else
      v_adjustment_type := 'initial';
      v_reason := 'Initial stock on product creation';
      v_reference := null;
    end if;

    insert into stock_adjustments (
      tenant_id,
      product_id,
      adjustment_type,
      quantity,
      stock_before,
      stock_after,
      reason,
      reference,
      created_by
    ) values (
      NEW.tenant_id,
      NEW.id,
      v_adjustment_type,
      NEW.stock_quantity,
      0,
      NEW.stock_quantity,
      v_reason,
      v_reference,
      auth.uid()
    );
  end if;

  return NEW;
end;
$$ language plpgsql security definer;

drop trigger if exists trg_track_product_stock_changes on products;
create trigger trg_track_product_stock_changes
  after insert or update of stock_quantity
  on products
  for each row
  execute function track_product_stock_changes();

commit;
