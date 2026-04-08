-- Fix manual stock adjustments to use a single database transaction.
-- This prevents duplicate movement history by updating products once,
-- inserting exactly one stock_adjustments row, and letting the existing
-- stock_adjustments -> stock_movements sync trigger create the movement row.

alter table public.stock_adjustments drop constraint if exists stock_adjustments_adjustment_type_check;

alter table public.stock_adjustments add constraint stock_adjustments_adjustment_type_check
  check (adjustment_type in ('manual', 'correction', 'initial', 'damage', 'loss', 'found', 'import', 'purchase'));

create or replace function public.apply_manual_stock_adjustment(
  p_product_id uuid,
  p_quantity integer,
  p_type text,
  p_reason text default 'Ajuste Manual'
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_product public.products%rowtype;
  v_delta integer;
  v_stock_before integer;
  v_stock_after integer;
  v_reason text;
  v_created_at timestamp with time zone := now();
  v_adjustment_id uuid;
  v_movement_id uuid;
begin
  if p_type not in ('IN', 'OUT') then
    raise exception 'Invalid stock adjustment type: %', p_type
      using errcode = 'check_violation';
  end if;

  if p_quantity <= 0 then
    raise exception 'Stock adjustment quantity must be positive: %', p_quantity
      using errcode = 'check_violation';
  end if;

  select *
    into v_product
    from public.products
   where id = p_product_id
     and tenant_id = public.user_tenant_id()
   for update;

  if not found then
    raise exception 'Product % not found for current tenant', p_product_id
      using errcode = 'foreign_key_violation';
  end if;

  if coalesce(v_product.product_type, 'product') = 'service'
     or coalesce(v_product.track_stock, true) = false then
    raise exception 'Product % does not track stock', coalesce(v_product.name, p_product_id::text)
      using errcode = 'check_violation';
  end if;

  v_delta := case when p_type = 'IN' then p_quantity else -p_quantity end;
  v_stock_before := greatest(coalesce(v_product.inventory_qty, 0), coalesce(v_product.stock_quantity, 0));
  v_stock_after := v_stock_before + v_delta;
  v_reason := coalesce(nullif(trim(p_reason), ''), 'Ajuste Manual');

  perform set_config('app.skip_stock_adjustment_trigger', 'true', true);

  update public.products
     set inventory_qty = v_stock_after,
         stock_quantity = v_stock_after,
         updated_at = v_created_at
   where id = v_product.id
     and tenant_id = v_product.tenant_id;

  insert into public.stock_adjustments (
    tenant_id,
    product_id,
    adjustment_type,
    quantity,
    stock_before,
    stock_after,
    reason,
    reference,
    created_by,
    created_at
  ) values (
    v_product.tenant_id,
    v_product.id,
    'manual',
    v_delta,
    v_stock_before,
    v_stock_after,
    v_reason,
    null,
    auth.uid(),
    v_created_at
  )
  returning id into v_adjustment_id;

  perform set_config('app.skip_stock_adjustment_trigger', '', true);

  select sm.id
    into v_movement_id
    from public.stock_movements sm
   where sm.tenant_id = v_product.tenant_id
     and sm.product_id = v_product.id
     and sm.created_at = v_created_at
     and sm.movement_type = 'manual'
   order by sm.id desc
   limit 1;

  return jsonb_build_object(
    'adjustment_id', v_adjustment_id,
    'movement_id', v_movement_id,
    'product_id', v_product.id,
    'product_name', v_product.name,
    'product_sku', v_product.sku,
    'type', p_type,
    'quantity', v_delta,
    'stock_before', v_stock_before,
    'stock_after', v_stock_after,
    'reason', v_reason,
    'created_at', v_created_at
  );
exception
  when others then
    perform set_config('app.skip_stock_adjustment_trigger', '', true);
    raise;
end;
$$;

grant execute on function public.apply_manual_stock_adjustment(uuid, integer, text, text) to authenticated;