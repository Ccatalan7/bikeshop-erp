-- Deployment status: DEPLOYED to staging bczzjhjrpmtpgwdvlbut and production
-- xzdvtzdqjeyqxnkqprtf on 2026-07-13. Production business counts were exact
-- before/after; staging proved 10 -> -1 and reversal -1 -> 10 with exact traces.
-- Restores Viñabike's established staff-sales policy: a tracked item may be
-- sold below zero, while the normal invoice movement, accounting operation,
-- checkpoints, and reversal path remain mandatory and auditable.
begin;

create or replace function public.validate_sales_invoice_stock_before_posting()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_non_posted constant text[] := array[
    'draft','borrador','sent','enviado','enviada','issued','emitido','emitida',
    'cancelled','cancelado','cancelada','anulado','anulada'
  ];
  v_old_posted boolean := false;
  v_new_posted boolean;
  v_requirement record;
  v_product public.products%rowtype;
begin
  v_new_posted := not (lower(coalesce(new.status, 'draft')) = any(v_non_posted));
  if tg_op = 'UPDATE' then
    v_old_posted := not (lower(coalesce(old.status, 'draft')) = any(v_non_posted));
  end if;

  if not v_new_posted then
    return new;
  end if;

  if tg_op = 'UPDATE'
     and v_old_posted
     and v_new_posted
     and public.invoice_inventory_signature(old.items)
         = public.invoice_inventory_signature(new.items) then
    return new;
  end if;

  if exists (
    select 1
      from jsonb_array_elements(coalesce(new.items, '[]'::jsonb)) item(value)
     where nullif(item.value->>'product_id', '') is not null
       and not exists (
         select 1
           from public.products product
          where product.id = nullif(item.value->>'product_id', '')::uuid
            and product.tenant_id = new.tenant_id
       )
  ) then
    raise exception 'Sales invoice contains a product outside the current tenant';
  end if;

  if exists (
    select 1
      from jsonb_array_elements(coalesce(new.items, '[]'::jsonb)) item(value)
      join public.products product
        on product.id = nullif(item.value->>'product_id', '')::uuid
       and product.tenant_id = new.tenant_id
     where not coalesce(product.is_service, false)
       and coalesce(product.track_stock, true)
       and coalesce(nullif(item.value->>'purchase_treatment', ''), 'inventory')
           <> 'workshop_consumable'
       and coalesce(nullif(item.value->>'quantity', '')::numeric, 0)
           <> trunc(coalesce(nullif(item.value->>'quantity', '')::numeric, 0))
  ) then
    raise exception 'Tracked sales invoice quantities must be whole units';
  end if;

  -- Lock every product whose posted requirement increases and preserve all
  -- tenant/existence/dual-balance checks. Insufficient stock is intentionally
  -- not rejected: the posting trigger records the exact negative balance.
  for v_requirement in
    with new_requirements as (
      select *
        from public.sales_invoice_stock_requirements(new.tenant_id, new.items)
    ), old_requirements as (
      select *
        from public.sales_invoice_stock_requirements(
          new.tenant_id,
          case when v_old_posted then old.items else '[]'::jsonb end
        )
    ), deltas as (
      select coalesce(new_req.product_id, old_req.product_id) product_id,
             coalesce(new_req.quantity, 0) - coalesce(old_req.quantity, 0) quantity
        from new_requirements new_req
        full join old_requirements old_req using (product_id)
    )
    select * from deltas where quantity > 0 order by product_id
  loop
    select *
      into v_product
      from public.products
     where id = v_requirement.product_id
       and tenant_id = new.tenant_id
     for update;

    if not found then
      raise exception 'Sales invoice stock product not found for current tenant';
    end if;
    if coalesce(v_product.inventory_qty, 0)
       <> coalesce(v_product.stock_quantity, 0) then
      raise exception
        'Product stock columns disagree; sales posting blocked for %',
        v_product.name;
    end if;
  end loop;

  return new;
end;
$$;

comment on function public.validate_sales_invoice_stock_before_posting() is
  'Validates tenant ownership, whole tracked units, and synchronized balances; staff invoice posting may create auditable negative stock.';

commit;
