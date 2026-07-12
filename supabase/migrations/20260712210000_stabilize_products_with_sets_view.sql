begin;

-- products_with_sets uses p.*. Recreate it after every products ALTER block so
-- a fresh database and an upgraded database expose the same final columns.
drop view if exists public.products_with_sets;

create view public.products_with_sets as
select
  p.*,
  case when p.is_set then
    (select json_agg(
      json_build_object(
        'id', psc.id,
        'component_product_id', psc.component_product_id,
        'component_label', psc.component_label,
        'component_position', psc.component_position,
        'component_name', cp.name,
        'component_sku', cp.sku,
        'stock_quantity', coalesce(cp.stock_quantity, cp.inventory_qty, 0),
        'quantity_in_set', psc.quantity_in_set,
        'cost_ratio', psc.cost_ratio,
        'price_ratio', psc.price_ratio
      ) order by psc.component_position
    )
    from public.product_set_components psc
    join public.products cp on cp.id = psc.component_product_id
    where psc.set_product_id = p.id)
  end as set_components,
  case when p.is_set then public.get_full_sets_count(p.id) end as full_sets_available,
  case when p.is_set then public.is_set_partial(p.id) end as is_partial,
  case when p.parent_set_id is not null then
    (select json_build_object(
      'id', parent_product.id,
      'name', parent_product.name,
      'sku', parent_product.sku
    ) from public.products parent_product where parent_product.id = p.parent_set_id)
  end as parent_set_info
from public.products p;

grant all on public.products_with_sets to anon, authenticated, service_role;

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'codex_test_runner') then
    grant select on public.products_with_sets to codex_test_runner;
  end if;
end;
$$;

commit;
