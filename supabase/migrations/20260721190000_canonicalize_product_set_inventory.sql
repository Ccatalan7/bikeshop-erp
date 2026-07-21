-- Deployment status: NOT DEPLOYED
-- Canonical product-set aggregate and inventory repair.
--
-- `product_set_components` is the only authoritative composition. The legacy
-- `products.parent_set_id` columns remain a read-compatible mirror, but all
-- writes go through save_product_set_aggregate so a parent, its component
-- products and their links commit (or roll back) together.
--
-- Recovery: roll back the client to the previous product form. Keep the
-- additive RPCs, constraints and trace evidence in place. Do not delete the
-- canonical links or repair movements: they preserve the physical history
-- that the old implementation omitted.

begin;

set local lock_timeout = '2s';
set local statement_timeout = '60s';

create unique index if not exists uq_product_set_components_component
  on public.product_set_components(component_product_id);

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.products'::regclass
      and conname = 'products_tenant_parent_set_fkey'
  ) then
    alter table public.products
      add constraint products_tenant_parent_set_fkey
      foreign key (tenant_id, parent_set_id)
      references public.products(tenant_id, id)
      on delete set null (parent_set_id);
  end if;

  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.product_set_components'::regclass
      and conname = 'product_set_components_positive_quantity_check'
  ) then
    alter table public.product_set_components
      add constraint product_set_components_positive_quantity_check
      check (quantity_in_set > 0);
  end if;

  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.product_set_components'::regclass
      and conname = 'product_set_components_positive_position_check'
  ) then
    alter table public.product_set_components
      add constraint product_set_components_positive_position_check
      check (component_position > 0);
  end if;

  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.product_set_components'::regclass
      and conname = 'product_set_components_distinct_products_check'
  ) then
    alter table public.product_set_components
      add constraint product_set_components_distinct_products_check
      check (set_product_id <> component_product_id);
  end if;

  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.product_set_components'::regclass
      and conname = 'product_set_components_cost_ratio_check'
  ) then
    alter table public.product_set_components
      add constraint product_set_components_cost_ratio_check
      check (cost_ratio is null or cost_ratio between 0 and 1);
  end if;

  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.product_set_components'::regclass
      and conname = 'product_set_components_price_ratio_check'
  ) then
    alter table public.product_set_components
      add constraint product_set_components_price_ratio_check
      check (price_ratio is null or price_ratio between 0 and 1);
  end if;

  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.product_set_components'::regclass
      and conname = 'product_set_components_tenant_set_fkey'
  ) then
    alter table public.product_set_components
      add constraint product_set_components_tenant_set_fkey
      foreign key (tenant_id, set_product_id)
      references public.products(tenant_id, id) on delete cascade;
  end if;

  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.product_set_components'::regclass
      and conname = 'product_set_components_tenant_component_fkey'
  ) then
    alter table public.product_set_components
      add constraint product_set_components_tenant_component_fkey
      foreign key (tenant_id, component_product_id)
      references public.products(tenant_id, id) on delete cascade;
  end if;
end $$;

create or replace function public.product_set_has_document_history(
  p_tenant_id uuid,
  p_set_product_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.purchase_invoices invoice
    cross join lateral jsonb_array_elements(coalesce(invoice.items, '[]'::jsonb)) item
    join public.products set_product
      on set_product.id = p_set_product_id
     and set_product.tenant_id = p_tenant_id
    where invoice.tenant_id = p_tenant_id
      and (
        nullif(item->>'product_id', '')::uuid = p_set_product_id
        or (
          nullif(item->>'product_id', '') is null
          and nullif(item->>'product_sku', '') = set_product.sku
        )
      )
  ) or exists (
    select 1
    from public.sales_invoices invoice
    cross join lateral jsonb_array_elements(coalesce(invoice.items, '[]'::jsonb)) item
    join public.products set_product
      on set_product.id = p_set_product_id
     and set_product.tenant_id = p_tenant_id
    where invoice.tenant_id = p_tenant_id
      and (
        nullif(item->>'product_id', '')::uuid = p_set_product_id
        or (
          nullif(item->>'product_id', '') is null
          and nullif(item->>'product_sku', '') = set_product.sku
        )
      )
  ) or exists (
    select 1
    from public.purchase_receipt_lines line
    where line.tenant_id = p_tenant_id
      and line.product_id = p_set_product_id
  ) or exists (
    select 1
    from public.online_order_items item
    where item.tenant_id = p_tenant_id
      and item.product_id = p_set_product_id
  ) or exists (
    select 1
    from public.stock_movements movement
    where movement.tenant_id = p_tenant_id
      and (
        movement.product_id = p_set_product_id
        or (
          movement.product_id in (
            select component.component_product_id
            from public.product_set_components component
            where component.tenant_id = p_tenant_id
              and component.set_product_id = p_set_product_id
          )
          and movement.movement_type in (
            'sales_invoice_component',
            'purchase_invoice_component',
            'purchase_receipt_component',
            'online_order_set_component',
            'sales_return_component'
          )
        )
      )
  );
$$;

revoke all on function public.product_set_has_document_history(uuid, uuid)
  from public, anon, authenticated;

create or replace function public.validate_product_set_component_row()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_set public.products%rowtype;
  v_component public.products%rowtype;
begin
  select * into v_set
  from public.products
  where id = new.set_product_id
    and tenant_id = new.tenant_id;

  if not found or not coalesce(v_set.is_set, false) then
    raise exception 'Set parent is missing, cross-tenant, or not marked as a set'
      using errcode = '23514';
  end if;

  select * into v_component
  from public.products
  where id = new.component_product_id
    and tenant_id = new.tenant_id;

  if not found then
    raise exception 'Set component is missing or belongs to another tenant'
      using errcode = '23514';
  end if;
  if coalesce(v_component.is_set, false)
     or coalesce(v_component.product_type, 'product') = 'service'
     or not coalesce(v_component.track_stock, true) then
    raise exception 'Set components must be stock-tracked ordinary products'
      using errcode = '23514';
  end if;
  if v_component.parent_set_id is distinct from new.set_product_id then
    raise exception 'Component parent_set_id must mirror the canonical set link'
      using errcode = '23514';
  end if;

  return new;
end;
$$;

revoke all on function public.validate_product_set_component_row()
  from public, anon, authenticated;

drop trigger if exists trg_validate_product_set_component_row
  on public.product_set_components;
create trigger trg_validate_product_set_component_row
  before insert or update on public.product_set_components
  for each row execute function public.validate_product_set_component_row();

create or replace function public.guard_canonical_product_set_component_write()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if coalesce(current_setting('app.product_set_composition_writer', true), '')
       not in ('aggregate_rpc', 'migration') then
    raise exception 'Product set composition must be changed through save_product_set_aggregate'
      using errcode = '42501';
  end if;
  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$$;

revoke all on function public.guard_canonical_product_set_component_write()
  from public, anon, authenticated;

drop trigger if exists trg_00_guard_canonical_product_set_component_write
  on public.product_set_components;
create trigger trg_00_guard_canonical_product_set_component_write
  before insert or update or delete on public.product_set_components
  for each row execute function public.guard_canonical_product_set_component_write();

-- The old trigger copied calculated availability into physical stock columns.
-- Availability is now always calculated by get_full_sets_count / the view.
drop trigger if exists trg_sync_set_inventory_from_component on public.products;

create or replace function public.get_full_sets_count(p_set_product_id uuid)
returns integer
language sql
stable
set search_path = public
as $$
  select greatest(
    coalesce(min(floor(
      coalesce(product.stock_quantity, product.inventory_qty, 0)::numeric
      / component.quantity_in_set
    ))::integer, 0),
    0
  )
  from public.product_set_components component
  join public.products product
    on product.id = component.component_product_id
   and product.tenant_id = component.tenant_id
  where component.set_product_id = p_set_product_id;
$$;

-- The legacy view used owner privileges and therefore bypassed the products
-- RLS policy. Its p.* expansion was frozen when the historical view was first
-- created, so recreating it would silently change its column contract. Harden
-- execution and ACLs in place while preserving the exact deployed definition.
alter view public.products_with_sets set (security_invoker = true);

revoke all on public.products_with_sets
  from public, anon, authenticated, service_role;
grant select on public.products_with_sets to authenticated, service_role;

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'codex_test_runner') then
    grant select on public.products_with_sets to codex_test_runner;
  end if;
end;
$$;

create or replace function public.get_product_set_composition(
  p_set_product_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_tenant_id uuid := public.user_tenant_id();
  v_parent public.products%rowtype;
begin
  if auth.uid() is null or v_tenant_id is null then
    raise exception 'Authenticated tenant context is required'
      using errcode = '42501';
  end if;

  select * into v_parent
  from public.products product
  where product.id = p_set_product_id
    and product.tenant_id = v_tenant_id
    and coalesce(product.is_set, false);

  if not found then
    raise exception 'Product set not found for current tenant'
      using errcode = '42501';
  end if;

  return jsonb_build_object(
    'set_product_id', v_parent.id,
    'full_sets_available', public.get_full_sets_count(v_parent.id),
    'components', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', product.id,
        'sku', product.sku,
        'name', product.name,
        'label', component.component_label,
        'position', component.component_position,
        'quantity_in_set', component.quantity_in_set,
        'price', product.price,
        'cost', product.cost,
        'cost_ratio', component.cost_ratio,
        'price_ratio', component.price_ratio,
        'stock_quantity', coalesce(product.stock_quantity, product.inventory_qty, 0)
      ) order by component.component_position)
      from public.product_set_components component
      join public.products product
        on product.id = component.component_product_id
       and product.tenant_id = component.tenant_id
      where component.tenant_id = v_tenant_id
        and component.set_product_id = v_parent.id
    ), '[]'::jsonb)
  );
end;
$$;

revoke all on function public.get_product_set_composition(uuid)
  from public, anon;
grant execute on function public.get_product_set_composition(uuid)
  to authenticated;

create or replace function public.preview_product_stock_impact(
  p_product_id uuid,
  p_quantity integer default 1
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_tenant_id uuid := public.user_tenant_id();
  v_product public.products%rowtype;
  v_components jsonb;
  v_available integer;
begin
  if auth.uid() is null or v_tenant_id is null then
    raise exception 'Authenticated tenant context is required'
      using errcode = '42501';
  end if;
  if p_quantity is null or p_quantity <= 0 then
    raise exception 'Requested quantity must be a positive whole number'
      using errcode = '22023';
  end if;

  select * into v_product
  from public.products product
  where product.id = p_product_id
    and product.tenant_id = v_tenant_id;

  if not found then
    raise exception 'Product not found for current tenant'
      using errcode = '42501';
  end if;

  if coalesce(v_product.is_set, false) then
    if not exists (
      select 1 from public.product_set_components component
      where component.tenant_id = v_tenant_id
        and component.set_product_id = v_product.id
    ) then
      raise exception 'Set product has no canonical components'
        using errcode = '23514';
    end if;

    v_available := public.get_full_sets_count(v_product.id);
    select jsonb_agg(jsonb_build_object(
      'product_id', component_product.id,
      'sku', component_product.sku,
      'name', component_product.name,
      'quantity_in_set', component.quantity_in_set,
      'required_quantity', p_quantity * component.quantity_in_set,
      'stock_quantity', coalesce(component_product.stock_quantity, component_product.inventory_qty, 0),
      'projected_stock', coalesce(component_product.stock_quantity, component_product.inventory_qty, 0)
        - p_quantity * component.quantity_in_set
    ) order by component.component_position)
    into v_components
    from public.product_set_components component
    join public.products component_product
      on component_product.id = component.component_product_id
     and component_product.tenant_id = component.tenant_id
    where component.tenant_id = v_tenant_id
      and component.set_product_id = v_product.id;
  else
    v_available := coalesce(v_product.stock_quantity, v_product.inventory_qty, 0);
    v_components := jsonb_build_array(jsonb_build_object(
      'product_id', v_product.id,
      'sku', v_product.sku,
      'name', v_product.name,
      'quantity_in_set', 1,
      'required_quantity', p_quantity,
      'stock_quantity', v_available,
      'projected_stock', v_available - p_quantity
    ));
  end if;

  return jsonb_build_object(
    'product_id', v_product.id,
    'is_set', coalesce(v_product.is_set, false),
    'tracks_inventory', (
      coalesce(v_product.product_type, 'product') <> 'service'
      and coalesce(v_product.track_stock, true)
      and coalesce(v_product.purchase_treatment, 'inventory') = 'inventory'
    ),
    'requested_quantity', p_quantity,
    'available_quantity', v_available,
    'components', coalesce(v_components, '[]'::jsonb)
  );
end;
$$;

revoke all on function public.preview_product_stock_impact(uuid, integer)
  from public, anon;
grant execute on function public.preview_product_stock_impact(uuid, integer)
  to authenticated;

-- Modern availability projection independent of the frozen historical
-- products_with_sets p.* column contract. Physical products and sets both
-- include active online reservations; malformed set maps fail closed instead
-- of presenting zero or stale availability as a valid result.
create or replace function public.get_product_available_quantities(
  p_tenant_id uuid,
  p_product_ids uuid[]
)
returns table(product_id uuid, available_quantity integer)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_set public.products%rowtype;
begin
  if p_tenant_id is null then
    raise exception 'Tenant is required' using errcode = '22023';
  end if;
  if coalesce(auth.role(), '') <> 'service_role'
     and (
       auth.uid() is null
       or public.user_tenant_id() is distinct from p_tenant_id
     ) then
    raise exception 'Tenant availability access denied' using errcode = '42501';
  end if;
  if p_product_ids is null
     or coalesce(cardinality(p_product_ids), 0) = 0
     or cardinality(p_product_ids) > 500 then
    raise exception 'Product id batch must contain between 1 and 500 ids'
      using errcode = '22023';
  end if;

  for v_set in
    select product.*
    from public.products product
    where product.tenant_id = p_tenant_id
      and product.id = any(p_product_ids)
      and coalesce(product.is_set, false)
    order by product.id
  loop
    if coalesce(v_set.inventory_qty, 0) <> 0
       or coalesce(v_set.stock_quantity, 0) <> 0 then
      raise exception 'Set product % has forbidden physical stock', v_set.sku
        using errcode = '23514';
    end if;
    if not exists (
      select 1
      from public.product_set_components component
      where component.tenant_id = p_tenant_id
        and component.set_product_id = v_set.id
    ) then
      raise exception 'Set product % has no canonical components', v_set.sku
        using errcode = '23514';
    end if;
    if exists (
      select 1
      from public.product_set_components component
      left join public.products child
        on child.id = component.component_product_id
       and child.tenant_id = component.tenant_id
      where component.tenant_id = p_tenant_id
        and component.set_product_id = v_set.id
        and (
          child.id is null
          or child.parent_set_id is distinct from v_set.id
          or coalesce(child.is_set, false)
          or coalesce(child.product_type, 'product') = 'service'
          or not coalesce(child.track_stock, true)
          or component.quantity_in_set <= 0
        )
    ) then
      raise exception 'Set product % has an invalid canonical component map',
        v_set.sku using errcode = '23514';
    end if;
    if exists (
      select 1
      from public.product_set_components component
      join public.products child
        on child.id = component.component_product_id
       and child.tenant_id = component.tenant_id
      where component.tenant_id = p_tenant_id
        and component.set_product_id = v_set.id
        and child.inventory_qty is distinct from child.stock_quantity
    ) then
      raise exception 'Set product % has inconsistent component stock columns',
        v_set.sku using errcode = '23514';
    end if;
  end loop;

  return query
  select product.id,
         public.online_product_available_quantity(
           product.tenant_id,
           product.id
         )::integer
  from public.products product
  where product.tenant_id = p_tenant_id
    and product.id = any(p_product_ids)
  order by product.id;
end;
$$;

comment on function public.get_product_available_quantities(uuid, uuid[]) is
  'Tenant-authorized reservation-aware availability for one or many products. Set headers are validated and resolved exclusively through canonical physical components.';

revoke all on function public.get_product_available_quantities(uuid, uuid[])
  from public, anon, authenticated, service_role;
grant execute on function public.get_product_available_quantities(uuid, uuid[])
  to authenticated, service_role;

create or replace function public.save_product_set_aggregate(
  p_parent jsonb,
  p_components jsonb,
  p_operation_key text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_tenant_id uuid := public.user_tenant_id();
  v_actor_id uuid := auth.uid();
  v_parent_id uuid;
  v_parent public.products%rowtype;
  v_existing_parent public.products%rowtype;
  v_existing_operation public.inventory_accounting_operations%rowtype;
  v_component_request jsonb;
  v_component public.products%rowtype;
  v_component_id uuid;
  v_desired_component_ids uuid[] := array[]::uuid[];
  v_normalized_components jsonb := '[]'::jsonb;
  v_requested_position integer;
  v_requested_quantity integer;
  v_cost_ratio numeric;
  v_price_ratio numeric;
  v_had_history boolean := false;
  v_map_changed boolean := false;
  v_before_snapshot jsonb;
  v_result jsonb;
  v_operation_id uuid;
  v_request_fingerprint text;
  v_previous_writer text := current_setting('app.product_set_composition_writer', true);
  v_array text[];
begin
  if v_actor_id is null or v_tenant_id is null then
    raise exception 'Authenticated tenant context is required'
      using errcode = '42501';
  end if;
  if p_parent is null or jsonb_typeof(p_parent) <> 'object' then
    raise exception 'Parent product payload must be a JSON object'
      using errcode = '22023';
  end if;
  if p_components is null
     or jsonb_typeof(p_components) <> 'array'
     or jsonb_array_length(p_components) = 0 then
    raise exception 'A product set requires at least one component'
      using errcode = '22023';
  end if;
  if nullif(btrim(p_operation_key), '') is null
     or length(btrim(p_operation_key)) > 180 then
    raise exception 'A bounded operation key is required'
      using errcode = '22023';
  end if;
  if nullif(btrim(p_parent->>'name'), '') is null
     or nullif(btrim(p_parent->>'sku'), '') is null then
    raise exception 'Set name and SKU are required'
      using errcode = '22023';
  end if;
  if p_parent ? 'tenant_id'
     and nullif(p_parent->>'tenant_id', '')::uuid is distinct from v_tenant_id then
    raise exception 'Parent product belongs to another tenant'
      using errcode = '42501';
  end if;
  if coalesce(nullif(p_parent->>'inventory_qty', '')::integer, 0) <> 0
     or coalesce(nullif(p_parent->>'stock_quantity', '')::integer, 0) <> 0 then
    raise exception 'Set parent physical stock must be zero'
      using errcode = '23514';
  end if;
  if p_parent ? 'product_type' and coalesce(p_parent->>'product_type', 'product') <> 'product'
     or p_parent ? 'purchase_treatment' and coalesce(p_parent->>'purchase_treatment', 'inventory') <> 'inventory'
     or p_parent ? 'track_stock' and not coalesce((p_parent->>'track_stock')::boolean, true)
     or p_parent ? 'is_set' and not coalesce((p_parent->>'is_set')::boolean, true)
     or nullif(p_parent->>'parent_set_id', '') is not null then
    raise exception 'A set parent must be an inventory-tracked product without a parent'
      using errcode = '23514';
  end if;

  v_request_fingerprint := md5(jsonb_build_object(
    'parent', p_parent - array['expected_updated_at'],
    'components', p_components
  )::text);

  select * into v_existing_operation
  from public.inventory_accounting_operations operation
  where operation.tenant_id = v_tenant_id
    and operation.operation_key = 'product_set:' || btrim(p_operation_key);

  if found then
    if v_existing_operation.document_type <> 'product_set'
       or v_existing_operation.context->>'request_fingerprint' is distinct from v_request_fingerprint then
      raise exception 'Operation key was already used for a different product-set request'
        using errcode = '23505';
    end if;
    return coalesce(v_existing_operation.after_snapshot, '{}'::jsonb)
      || jsonb_build_object('operation_id', v_existing_operation.id, 'replayed', true);
  end if;

  perform set_config('app.product_set_composition_writer', 'aggregate_rpc', true);

  v_parent_id := coalesce(nullif(p_parent->>'id', '')::uuid, gen_random_uuid());
  select * into v_existing_parent
  from public.products product
  where product.id = v_parent_id
    and product.tenant_id = v_tenant_id
  for update;

  if found then
    if nullif(p_parent->>'expected_updated_at', '') is null then
      raise exception 'expected_updated_at is required when editing a product set'
        using errcode = '22023';
    end if;
    if v_existing_parent.updated_at is distinct from (p_parent->>'expected_updated_at')::timestamptz then
      raise exception 'Product set changed since it was opened; reload before saving'
        using errcode = '40001';
    end if;
    if not coalesce(v_existing_parent.is_set, false) then
      raise exception 'Existing product is not a set'
        using errcode = '23514';
    end if;
    if coalesce(v_existing_parent.inventory_qty, 0) <> 0
       or coalesce(v_existing_parent.stock_quantity, 0) <> 0 then
      raise exception 'Existing set parent has physical stock and must be normalized first'
        using errcode = '23514';
    end if;
    v_before_snapshot := jsonb_build_object(
      'parent', to_jsonb(v_existing_parent),
      'composition', coalesce((
        select jsonb_agg(to_jsonb(component) order by component.component_position)
        from public.product_set_components component
        where component.tenant_id = v_tenant_id
          and component.set_product_id = v_parent_id
      ), '[]'::jsonb)
    );
  else
    if p_parent ? 'expected_updated_at' then
      raise exception 'Product set no longer exists'
        using errcode = '40001';
    end if;
    if exists (select 1 from public.products product where product.id = v_parent_id) then
      raise exception 'Product id belongs to another tenant'
        using errcode = '42501';
    end if;
    insert into public.products (
      id, tenant_id, name, sku, price, cost, inventory_qty, stock_quantity,
      purchase_treatment, product_type, is_service, track_stock, is_set,
      parent_set_id, set_type
    ) values (
      v_parent_id, v_tenant_id, btrim(p_parent->>'name'), btrim(p_parent->>'sku'),
      coalesce(nullif(p_parent->>'price', '')::numeric, 0),
      coalesce(nullif(p_parent->>'cost', '')::numeric, 0),
      0, 0, 'inventory', 'product', false, true, true, null,
      nullif(p_parent->>'set_type', '')
    );
    v_before_snapshot := null;
  end if;

  -- Apply the allowlisted parent patch. Server-owned identity, stock and set
  -- relationship fields never come from the client payload.
  update public.products product set
    name = btrim(p_parent->>'name'),
    sku = btrim(p_parent->>'sku'),
    barcode = case when p_parent ? 'barcode' then nullif(p_parent->>'barcode', '') else product.barcode end,
    price = case when p_parent ? 'price' then coalesce(nullif(p_parent->>'price', '')::numeric, 0) else product.price end,
    cost = case when p_parent ? 'cost' then coalesce(nullif(p_parent->>'cost', '')::numeric, 0) else product.cost end,
    min_stock_level = case when p_parent ? 'min_stock_level' then coalesce(nullif(p_parent->>'min_stock_level', '')::integer, 0) else product.min_stock_level end,
    max_stock_level = case when p_parent ? 'max_stock_level' then coalesce(nullif(p_parent->>'max_stock_level', '')::integer, 0) else product.max_stock_level end,
    image_url = case when p_parent ? 'image_url' then nullif(p_parent->>'image_url', '') else product.image_url end,
    image_url_optimized = case when p_parent ? 'image_url_optimized' then nullif(p_parent->>'image_url_optimized', '') else product.image_url_optimized end,
    image_fingerprint = case
      when not (p_parent ? 'image_fingerprint') then product.image_fingerprint
      when p_parent->'image_fingerprint' = 'null'::jsonb then null
      when jsonb_typeof(p_parent->'image_fingerprint') = 'object' then p_parent->'image_fingerprint'
      else product.image_fingerprint
    end,
    image_urls = case when jsonb_typeof(p_parent->'image_urls') = 'array' then array(select jsonb_array_elements_text(p_parent->'image_urls')) else product.image_urls end,
    description = case when p_parent ? 'description' then nullif(p_parent->>'description', '') else product.description end,
    category = case when p_parent ? 'category' then coalesce(nullif(p_parent->>'category', ''), 'other') else product.category end,
    category_id = case when p_parent ? 'category_id' then nullif(p_parent->>'category_id', '')::uuid else product.category_id end,
    category_name = case when p_parent ? 'category_name' then nullif(p_parent->>'category_name', '') else product.category_name end,
    brand_id = case when p_parent ? 'brand_id' then nullif(p_parent->>'brand_id', '')::uuid else product.brand_id end,
    brand = case when p_parent ? 'brand' then nullif(p_parent->>'brand', '') else product.brand end,
    model = case when p_parent ? 'model' then nullif(p_parent->>'model', '') else product.model end,
    specifications = case when jsonb_typeof(p_parent->'specifications') = 'object' then p_parent->'specifications' else product.specifications end,
    supplier_id = case when p_parent ? 'supplier_id' then nullif(p_parent->>'supplier_id', '')::uuid else product.supplier_id end,
    supplier_name = case when p_parent ? 'supplier_name' then nullif(p_parent->>'supplier_name', '') else product.supplier_name end,
    supplier_reference = case when p_parent ? 'supplier_reference' then nullif(p_parent->>'supplier_reference', '') else product.supplier_reference end,
    supplier_code = case when p_parent ? 'supplier_code' then nullif(p_parent->>'supplier_code', '') else product.supplier_code end,
    manufacturer = case when p_parent ? 'manufacturer' then nullif(p_parent->>'manufacturer', '') else product.manufacturer end,
    manufacturer_sku = case when p_parent ? 'manufacturer_sku' then nullif(p_parent->>'manufacturer_sku', '') else product.manufacturer_sku end,
    gtin = case when p_parent ? 'gtin' then nullif(p_parent->>'gtin', '') else product.gtin end,
    hs_code = case when p_parent ? 'hs_code' then nullif(p_parent->>'hs_code', '') else product.hs_code end,
    country_of_origin = case when p_parent ? 'country_of_origin' then nullif(p_parent->>'country_of_origin', '') else product.country_of_origin end,
    color = case when p_parent ? 'color' then nullif(p_parent->>'color', '') else product.color end,
    size = case when p_parent ? 'size' then nullif(p_parent->>'size', '') else product.size end,
    material = case when p_parent ? 'material' then nullif(p_parent->>'material', '') else product.material end,
    dimensions = case when jsonb_typeof(p_parent->'dimensions') = 'object' then p_parent->'dimensions' else product.dimensions end,
    warranty_months = case when p_parent ? 'warranty_months' then coalesce(nullif(p_parent->>'warranty_months', '')::integer, 0) else product.warranty_months end,
    lifecycle_status = case when p_parent ? 'lifecycle_status' then coalesce(nullif(p_parent->>'lifecycle_status', ''), 'active') else product.lifecycle_status end,
    serialized = case when p_parent ? 'serialized' then coalesce((p_parent->>'serialized')::boolean, false) else product.serialized end,
    lot_tracking = case when p_parent ? 'lot_tracking' then coalesce((p_parent->>'lot_tracking')::boolean, false) else product.lot_tracking end,
    expiration_tracking = case when p_parent ? 'expiration_tracking' then coalesce((p_parent->>'expiration_tracking')::boolean, false) else product.expiration_tracking end,
    expiry_days = case when p_parent ? 'expiry_days' then nullif(p_parent->>'expiry_days', '')::integer else product.expiry_days end,
    lead_time_days = case when p_parent ? 'lead_time_days' then coalesce(nullif(p_parent->>'lead_time_days', '')::integer, 0) else product.lead_time_days end,
    reorder_quantity = case when p_parent ? 'reorder_quantity' then coalesce(nullif(p_parent->>'reorder_quantity', '')::integer, 0) else product.reorder_quantity end,
    warehouse_location = case when p_parent ? 'warehouse_location' then nullif(p_parent->>'warehouse_location', '') else product.warehouse_location end,
    price_currency = case when p_parent ? 'price_currency' then coalesce(nullif(upper(p_parent->>'price_currency'), ''), 'CLP') else product.price_currency end,
    cost_currency = case when p_parent ? 'cost_currency' then coalesce(nullif(upper(p_parent->>'cost_currency'), ''), 'CLP') else product.cost_currency end,
    tax_rate = case when p_parent ? 'tax_rate' then nullif(p_parent->>'tax_rate', '')::numeric else product.tax_rate end,
    tags = case when jsonb_typeof(p_parent->'tags') = 'array' then array(select jsonb_array_elements_text(p_parent->'tags')) else product.tags end,
    unit = case when p_parent ? 'unit' then coalesce(nullif(p_parent->>'unit', ''), 'unit') else product.unit end,
    weight = case when p_parent ? 'weight' then coalesce(nullif(p_parent->>'weight', '')::numeric, 0) else product.weight end,
    is_active = case when p_parent ? 'is_active' then coalesce((p_parent->>'is_active')::boolean, true) else product.is_active end,
    is_published = case when p_parent ? 'is_published' then coalesce((p_parent->>'is_published')::boolean, true) else product.is_published end,
    is_google_merchant = case when p_parent ? 'is_google_merchant' then coalesce((p_parent->>'is_google_merchant')::boolean, false) else product.is_google_merchant end,
    is_whatsapp_catalog = case when p_parent ? 'is_whatsapp_catalog' then coalesce((p_parent->>'is_whatsapp_catalog')::boolean, false) else product.is_whatsapp_catalog end,
    whatsapp_catalog_title = case when p_parent ? 'whatsapp_catalog_title' then nullif(p_parent->>'whatsapp_catalog_title', '') else product.whatsapp_catalog_title end,
    whatsapp_catalog_description = case when p_parent ? 'whatsapp_catalog_description' then nullif(p_parent->>'whatsapp_catalog_description', '') else product.whatsapp_catalog_description end,
    whatsapp_catalog_price = case when p_parent ? 'whatsapp_catalog_price' then nullif(p_parent->>'whatsapp_catalog_price', '')::numeric else product.whatsapp_catalog_price end,
    show_on_website = case when p_parent ? 'show_on_website' then coalesce((p_parent->>'show_on_website')::boolean, true) else product.show_on_website end,
    website_description = case when p_parent ? 'website_description' then nullif(p_parent->>'website_description', '') else product.website_description end,
    website_name = case when p_parent ? 'website_name' then nullif(p_parent->>'website_name', '') else product.website_name end,
    website_price = case when p_parent ? 'website_price' then nullif(p_parent->>'website_price', '')::numeric else product.website_price end,
    website_image_url = case when p_parent ? 'website_image_url' then nullif(p_parent->>'website_image_url', '') else product.website_image_url end,
    website_image_url_optimized = case when p_parent ? 'website_image_url_optimized' then nullif(p_parent->>'website_image_url_optimized', '') else product.website_image_url_optimized end,
    website_image_urls = case when jsonb_typeof(p_parent->'website_image_urls') = 'array' then array(select jsonb_array_elements_text(p_parent->'website_image_urls')) else product.website_image_urls end,
    website_seo_title = case when p_parent ? 'website_seo_title' then nullif(p_parent->>'website_seo_title', '') else product.website_seo_title end,
    website_seo_description = case when p_parent ? 'website_seo_description' then nullif(p_parent->>'website_seo_description', '') else product.website_seo_description end,
    website_search_terms = case when jsonb_typeof(p_parent->'website_search_terms') = 'array' then array(select jsonb_array_elements_text(p_parent->'website_search_terms')) else product.website_search_terms end,
    website_merchant_title = case when p_parent ? 'website_merchant_title' then nullif(p_parent->>'website_merchant_title', '') else product.website_merchant_title end,
    website_merchant_description = case when p_parent ? 'website_merchant_description' then nullif(p_parent->>'website_merchant_description', '') else product.website_merchant_description end,
    website_merchant_brand = case when p_parent ? 'website_merchant_brand' then nullif(p_parent->>'website_merchant_brand', '') else product.website_merchant_brand end,
    website_merchant_gtin = case when p_parent ? 'website_merchant_gtin' then nullif(p_parent->>'website_merchant_gtin', '') else product.website_merchant_gtin end,
    website_merchant_mpn = case when p_parent ? 'website_merchant_mpn' then nullif(p_parent->>'website_merchant_mpn', '') else product.website_merchant_mpn end,
    website_google_product_category = case when p_parent ? 'website_google_product_category' then nullif(p_parent->>'website_google_product_category', '') else product.website_google_product_category end,
    set_type = case when p_parent ? 'set_type' then nullif(p_parent->>'set_type', '') else product.set_type end,
    inventory_qty = 0,
    stock_quantity = 0,
    purchase_treatment = 'inventory',
    product_type = 'product',
    is_service = false,
    track_stock = true,
    is_set = true,
    parent_set_id = null,
    updated_at = clock_timestamp()
  where product.id = v_parent_id
    and product.tenant_id = v_tenant_id
  returning * into v_parent;

  v_had_history := public.product_set_has_document_history(v_tenant_id, v_parent_id);

  -- Reject duplicate positions/SKUs before touching any component row.
  if exists (
    select 1
    from jsonb_array_elements(p_components) request
    group by nullif(request->>'position', '')::integer
    having count(*) > 1
  ) or exists (
    select 1
    from jsonb_array_elements(p_components) request
    group by lower(btrim(request->>'sku'))
    having count(*) > 1
  ) then
    raise exception 'Component positions and SKUs must be unique inside a set'
      using errcode = '23505';
  end if;

  for v_component_request in
    select value from jsonb_array_elements(p_components)
  loop
    if jsonb_typeof(v_component_request) <> 'object'
       or nullif(btrim(v_component_request->>'sku'), '') is null
       or nullif(btrim(v_component_request->>'name'), '') is null
       or nullif(btrim(v_component_request->>'label'), '') is null then
      raise exception 'Every set component requires SKU, name and label'
        using errcode = '22023';
    end if;

    v_requested_position := nullif(v_component_request->>'position', '')::integer;
    v_requested_quantity := coalesce(
      nullif(v_component_request->>'quantity_in_set', '')::integer, 1
    );
    if v_requested_position is null or v_requested_position <= 0
       or v_requested_quantity <= 0 then
      raise exception 'Component position and quantity_in_set must be positive integers'
        using errcode = '22023';
    end if;
    v_cost_ratio := nullif(v_component_request->>'cost_ratio', '')::numeric;
    v_price_ratio := nullif(v_component_request->>'price_ratio', '')::numeric;
    if v_cost_ratio is not null and (v_cost_ratio < 0 or v_cost_ratio > 1)
       or v_price_ratio is not null and (v_price_ratio < 0 or v_price_ratio > 1) then
      raise exception 'Component ratios must be between 0 and 1'
        using errcode = '22023';
    end if;

    v_component_id := nullif(v_component_request->>'id', '')::uuid;
    v_component := null;
    if v_component_id is not null then
      select * into v_component
      from public.products product
      where product.id = v_component_id
        and product.tenant_id = v_tenant_id
      for update;
      if not found then
        raise exception 'Component product not found for current tenant'
          using errcode = '42501';
      end if;
    else
      select * into v_component
      from public.products product
      where product.sku = btrim(v_component_request->>'sku')
        and product.tenant_id = v_tenant_id
      for update;
      if found then
        v_component_id := v_component.id;
      else
        v_component_id := gen_random_uuid();
      end if;
    end if;

    if v_component.id is not null then
      if coalesce(v_component.is_set, false)
         or v_component.id = v_parent_id
         or v_component.parent_set_id is distinct from v_parent_id then
        raise exception 'Existing component is not owned by this set'
          using errcode = '23514';
      end if;
      if v_component.sku is distinct from btrim(v_component_request->>'sku')
         and exists (
           select 1 from public.stock_movements movement
           where movement.tenant_id = v_tenant_id
             and movement.product_id = v_component.id
         ) then
        raise exception 'Component SKU cannot change after inventory history exists'
          using errcode = '23514';
      end if;

      update public.products product set
        sku = btrim(v_component_request->>'sku'),
        name = btrim(v_component_request->>'name'),
        price = coalesce(nullif(v_component_request->>'price', '')::numeric, product.price),
        cost = coalesce(nullif(v_component_request->>'cost', '')::numeric, product.cost),
        tax_rate = v_parent.tax_rate,
        component_label = btrim(v_component_request->>'label'),
        component_position = v_requested_position,
        parent_set_id = v_parent_id,
        is_set = false,
        product_type = 'product',
        is_service = false,
        purchase_treatment = 'inventory',
        track_stock = true,
        is_published = false,
        show_on_website = false,
        updated_at = clock_timestamp()
      where product.id = v_component_id
        and product.tenant_id = v_tenant_id
      returning * into v_component;
    else
      insert into public.products (
        id, tenant_id, name, sku, description, category, category_id,
        category_name, brand_id, brand, supplier_id, supplier_name, price,
        cost, tax_rate, inventory_qty, stock_quantity, min_stock_level,
        max_stock_level, image_url, image_url_optimized, image_urls,
        is_active, is_published, show_on_website, product_type, is_service,
        purchase_treatment, track_stock, is_set, parent_set_id,
        component_label, component_position
      ) values (
        v_component_id, v_tenant_id, btrim(v_component_request->>'name'),
        btrim(v_component_request->>'sku'),
        format('%s del set %s', btrim(v_component_request->>'label'), v_parent.name),
        v_parent.category, v_parent.category_id, v_parent.category_name,
        v_parent.brand_id, v_parent.brand, v_parent.supplier_id,
        v_parent.supplier_name,
        coalesce(nullif(v_component_request->>'price', '')::numeric, 0),
        coalesce(nullif(v_component_request->>'cost', '')::numeric, 0),
        v_parent.tax_rate, 0, 0, v_parent.min_stock_level,
        v_parent.max_stock_level, v_parent.image_url, v_parent.image_url_optimized,
        v_parent.image_urls, v_parent.is_active, false, false, 'product', false,
        'inventory', true, false, v_parent_id,
        btrim(v_component_request->>'label'), v_requested_position
      ) returning * into v_component;
    end if;

    v_desired_component_ids := array_append(v_desired_component_ids, v_component_id);
    v_normalized_components := v_normalized_components || jsonb_build_array(
      jsonb_build_object(
        'id', v_component_id,
        'sku', v_component.sku,
        'name', v_component.name,
        'label', btrim(v_component_request->>'label'),
        'position', v_requested_position,
        'quantity_in_set', v_requested_quantity,
        'price', v_component.price,
        'cost', v_component.cost,
        'cost_ratio', v_cost_ratio,
        'price_ratio', v_price_ratio
      )
    );
  end loop;

  select
    (select count(*)
     from public.product_set_components component
     where component.tenant_id = v_tenant_id
       and component.set_product_id = v_parent_id)
      <> jsonb_array_length(v_normalized_components)
    or exists (
      select 1
      from jsonb_array_elements(v_normalized_components) request
      left join public.product_set_components component
        on component.tenant_id = v_tenant_id
       and component.set_product_id = v_parent_id
       and component.component_product_id = (request->>'id')::uuid
      where component.component_product_id is null
         or component.quantity_in_set is distinct from
              (request->>'quantity_in_set')::integer
    )
    or exists (
      select 1
      from public.product_set_components component
      where component.tenant_id = v_tenant_id
        and component.set_product_id = v_parent_id
        and not exists (
          select 1
          from jsonb_array_elements(v_normalized_components) request
          where (request->>'id')::uuid = component.component_product_id
        )
    )
  into v_map_changed;

  if v_had_history and v_map_changed then
    raise exception 'Set composition or quantities cannot change after document history exists'
      using errcode = '23514';
  end if;

  if exists (
    select 1
    from public.product_set_components component
    join public.products product
      on product.id = component.component_product_id
     and product.tenant_id = component.tenant_id
    where component.tenant_id = v_tenant_id
      and component.set_product_id = v_parent_id
      and not (component.component_product_id = any(v_desired_component_ids))
      and (
        coalesce(product.inventory_qty, 0) <> 0
        or coalesce(product.stock_quantity, 0) <> 0
      )
  ) then
    raise exception 'A component with physical stock cannot be removed from its set'
      using errcode = '23514';
  end if;

  -- Move current positions out of the requested range, then atomically replace
  -- the exact canonical map. The outer transaction hides the temporary state.
  update public.product_set_components component
  set component_position = component.component_position + 1000000
  where component.tenant_id = v_tenant_id
    and component.set_product_id = v_parent_id;

  delete from public.product_set_components component
  where component.tenant_id = v_tenant_id
    and component.set_product_id = v_parent_id
    and not (component.component_product_id = any(v_desired_component_ids));

  update public.products product
  set parent_set_id = null,
      component_label = null,
      component_position = null,
      is_active = false,
      updated_at = clock_timestamp()
  where product.tenant_id = v_tenant_id
    and product.parent_set_id = v_parent_id
    and not (product.id = any(v_desired_component_ids));

  for v_component_request in
    select value from jsonb_array_elements(v_normalized_components)
  loop
    insert into public.product_set_components (
      tenant_id, set_product_id, component_product_id, component_label,
      component_position, quantity_in_set, cost_ratio, price_ratio
    ) values (
      v_tenant_id, v_parent_id, (v_component_request->>'id')::uuid,
      v_component_request->>'label', (v_component_request->>'position')::integer,
      (v_component_request->>'quantity_in_set')::integer,
      nullif(v_component_request->>'cost_ratio', '')::numeric,
      nullif(v_component_request->>'price_ratio', '')::numeric
    ) on conflict (set_product_id, component_product_id) do update set
      component_label = excluded.component_label,
      component_position = excluded.component_position,
      quantity_in_set = excluded.quantity_in_set,
      cost_ratio = excluded.cost_ratio,
      price_ratio = excluded.price_ratio,
      updated_at = clock_timestamp();
  end loop;

  insert into public.inventory_accounting_operations (
    tenant_id, operation_key, source_channel, action, document_type,
    document_id, actor_id, executor, before_snapshot, context
  ) values (
    v_tenant_id, 'product_set:' || btrim(p_operation_key),
    'inventory_product_form',
    case when v_existing_parent.id is null then 'create_product_set' else 'update_product_set' end,
    'product_set', v_parent_id, v_actor_id, 'save_product_set_aggregate',
    v_before_snapshot,
    jsonb_build_object(
      'request_fingerprint', v_request_fingerprint,
      'composition_changed', v_map_changed,
      'had_document_history', v_had_history
    )
  ) returning id into v_operation_id;

  perform public.append_inventory_accounting_checkpoint(
    v_operation_id, 'accepted', 'completed', 'product_set', v_parent_id,
    jsonb_build_object('operation_key', btrim(p_operation_key))
  );
  perform public.append_inventory_accounting_checkpoint(
    v_operation_id, 'source_snapshotted', 'completed', 'product_set', v_parent_id,
    jsonb_build_object('before', v_before_snapshot)
  );

  select * into v_parent
  from public.products product
  where product.id = v_parent_id and product.tenant_id = v_tenant_id;

  v_result := jsonb_build_object(
    'operation_id', v_operation_id,
    'replayed', false,
    'parent', to_jsonb(v_parent),
    'full_sets_available', public.get_full_sets_count(v_parent_id),
    'components', (public.get_product_set_composition(v_parent_id)->'components')
  );

  update public.inventory_accounting_operations
  set after_snapshot = v_result
  where id = v_operation_id and tenant_id = v_tenant_id;

  perform public.append_inventory_accounting_checkpoint(
    v_operation_id, 'invariants_verified', 'completed', 'product_set', v_parent_id,
    jsonb_build_object(
      'parent_physical_stock', 0,
      'canonical_component_count', jsonb_array_length(v_normalized_components),
      'legacy_mirror_count', (
        select count(*) from public.products product
        where product.tenant_id = v_tenant_id
          and product.parent_set_id = v_parent_id
      )
    )
  );
  update public.inventory_accounting_operations
  set outcome = 'completed', completed_at = clock_timestamp()
  where id = v_operation_id and tenant_id = v_tenant_id;
  perform public.append_inventory_accounting_checkpoint(
    v_operation_id, 'completed', 'completed', 'product_set', v_parent_id,
    jsonb_build_object('component_count', jsonb_array_length(v_normalized_components))
  );

  perform set_config(
    'app.product_set_composition_writer', coalesce(v_previous_writer, ''), true
  );
  return v_result;
end;
$$;

revoke all on function public.save_product_set_aggregate(jsonb, jsonb, text)
  from public, anon;
grant execute on function public.save_product_set_aggregate(jsonb, jsonb, text)
  to authenticated;

-- A set is the procurement unit; its private components are the physical
-- stock units. Keep smart purchasing on the parent using calculated set
-- availability and never create duplicate recommendations for private parts.
create or replace function public.refresh_product_set_purchase_list(
  p_tenant_id uuid,
  p_set_product_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_set public.products%rowtype;
  v_current_stock integer;
  v_supplier_id uuid;
  v_supplier_name text;
  v_rotation numeric(10,4);
  v_days_since_purchase integer;
  v_suggested integer;
  v_priority numeric(5,2);
begin
  select * into v_set
  from public.products product
  where product.id = p_set_product_id
    and product.tenant_id = p_tenant_id
    and coalesce(product.is_set, false);
  if not found then return; end if;

  v_current_stock := public.get_full_sets_count(v_set.id);

  -- Remove only machine-created legacy component recommendations. Explicitly
  -- ordered/received history and manually curated rows remain untouched.
  delete from public.smart_purchase_list list
  using public.products component
  where component.tenant_id = p_tenant_id
    and component.parent_set_id = v_set.id
    and list.tenant_id = component.tenant_id
    and list.product_id = component.id
    and list.status = 'pending'
    and coalesce(list.notes, '') like 'Auto-added:%';

  if v_current_stock > coalesce(v_set.min_stock_level, 0) then
    delete from public.smart_purchase_list list
    where list.tenant_id = p_tenant_id
      and list.product_id = v_set.id
      and list.status = 'pending'
      and coalesce(list.notes, '') like 'Auto-added:%';
    return;
  end if;

  select supplier.id, supplier.name
  into v_supplier_id, v_supplier_name
  from public.suppliers supplier
  where supplier.tenant_id = p_tenant_id
    and supplier.is_active
  order by (supplier.id = v_set.supplier_id) desc, supplier.created_at
  limit 1;

  select count(*)::numeric / 30.0 into v_rotation
  from public.sales_invoices invoice
  cross join lateral jsonb_array_elements(coalesce(invoice.items, '[]'::jsonb)) item
  where invoice.tenant_id = p_tenant_id
    and invoice.date >= clock_timestamp() - interval '30 days'
    and nullif(item->>'product_id', '')::uuid = v_set.id;
  v_rotation := coalesce(v_rotation, 0);

  select extract(day from clock_timestamp() - max(invoice.date))::integer
  into v_days_since_purchase
  from public.purchase_invoices invoice
  cross join lateral jsonb_array_elements(coalesce(invoice.items, '[]'::jsonb)) item
  where invoice.tenant_id = p_tenant_id
    and nullif(item->>'product_id', '')::uuid = v_set.id;
  v_days_since_purchase := coalesce(v_days_since_purchase, 999);
  v_suggested := greatest(
    coalesce(v_set.max_stock_level, 0) - v_current_stock,
    ceil(greatest(v_rotation, 0.1) * 30)::integer,
    1
  );
  v_priority := least(100, greatest(0,
    (v_rotation * 10 * 0.6)
    + (case
        when v_current_stock = 0 then 100
        when coalesce(v_set.min_stock_level, 0) = 0 then 50
        else (1 - (v_current_stock::numeric / v_set.min_stock_level)) * 100
      end * 0.3)
    + least(v_days_since_purchase, 100) * 0.1
  ));

  update public.smart_purchase_list list
  set product_name = v_set.name,
      product_sku = v_set.sku,
      supplier_id = coalesce(v_set.supplier_id, v_supplier_id),
      supplier_name = coalesce(v_set.supplier_name, v_supplier_name),
      suggested_quantity = v_suggested,
      priority = v_priority,
      rotation_kpi = v_rotation,
      days_since_last_purchase = v_days_since_purchase,
      current_stock = v_current_stock,
      min_stock_level = coalesce(v_set.min_stock_level, 0),
      avg_daily_consumption = greatest(v_rotation, 0.1),
      lead_time_days = greatest(coalesce(v_set.lead_time_days, 0), 7),
      estimated_stockout_date = clock_timestamp()
        + (v_current_stock / greatest(v_rotation, 0.1) || ' days')::interval,
      notes = 'Auto-added: disponibilidad calculada desde componentes del set',
      updated_at = clock_timestamp()
  where list.tenant_id = p_tenant_id
    and list.product_id = v_set.id
    and list.status in ('pending', 'ordered');

  if found then return; end if;

  insert into public.smart_purchase_list (
    tenant_id, product_id, product_name, product_sku, supplier_id,
    supplier_name, suggested_quantity, status, priority, rotation_kpi,
    days_since_last_purchase, current_stock, min_stock_level,
    avg_daily_consumption, lead_time_days, estimated_stockout_date, notes,
    added_date
  ) values (
    p_tenant_id, v_set.id, v_set.name, v_set.sku,
    coalesce(v_set.supplier_id, v_supplier_id),
    coalesce(v_set.supplier_name, v_supplier_name),
    v_suggested, 'pending', v_priority, v_rotation, v_days_since_purchase,
    v_current_stock, coalesce(v_set.min_stock_level, 0),
    greatest(v_rotation, 0.1), greatest(coalesce(v_set.lead_time_days, 0), 7),
    clock_timestamp() + (v_current_stock / greatest(v_rotation, 0.1) || ' days')::interval,
    'Auto-added: disponibilidad calculada desde componentes del set',
    clock_timestamp()
  );
end;
$$;

revoke all on function public.refresh_product_set_purchase_list(uuid, uuid)
  from public, anon, authenticated;

drop trigger if exists trg_auto_add_low_stock on public.products;
create trigger trg_auto_add_low_stock
  after insert or update of stock_quantity, inventory_qty on public.products
  for each row
  when (
    not coalesce(new.is_set, false)
    and new.parent_set_id is null
  )
  execute function public.auto_add_low_stock_to_purchase_list();

create or replace function public.refresh_parent_set_after_component_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_set_id uuid;
  v_tenant_id uuid;
  v_component_id uuid;
begin
  if tg_op = 'DELETE' then
    v_tenant_id := old.tenant_id;
    v_component_id := old.id;
  else
    v_tenant_id := new.tenant_id;
    v_component_id := new.id;
  end if;
  for v_set_id in
    select component.set_product_id
    from public.product_set_components component
    where component.tenant_id = v_tenant_id
      and component.component_product_id = v_component_id
  loop
    perform public.refresh_product_set_purchase_list(v_tenant_id, v_set_id);
  end loop;
  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$$;

revoke all on function public.refresh_parent_set_after_component_change()
  from public, anon, authenticated;

drop trigger if exists trg_refresh_parent_set_purchase_list on public.products;
create trigger trg_refresh_parent_set_purchase_list
  after update of stock_quantity, inventory_qty on public.products
  for each row execute function public.refresh_parent_set_after_component_change();

create or replace function public.refresh_purchase_list_after_set_map_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'DELETE' then
    perform public.refresh_product_set_purchase_list(old.tenant_id, old.set_product_id);
    return old;
  end if;
  perform public.refresh_product_set_purchase_list(new.tenant_id, new.set_product_id);
  return new;
end;
$$;

revoke all on function public.refresh_purchase_list_after_set_map_change()
  from public, anon, authenticated;

drop trigger if exists trg_refresh_purchase_list_after_set_map_change
  on public.product_set_components;
create trigger trg_refresh_purchase_list_after_set_map_change
  after insert or update or delete on public.product_set_components
  for each row execute function public.refresh_purchase_list_after_set_map_change();

-- Install the refresh triggers only after the cutover below. Component stock
-- is moved in batches during that cutover and must not expose intermediate
-- purchase recommendations even inside migration-side trigger work.
drop trigger if exists trg_refresh_parent_set_purchase_list on public.products;
drop trigger if exists trg_refresh_purchase_list_after_set_map_change
  on public.product_set_components;

-- --------------------------------------------------------------------------
-- One-time legacy graph cutover.
-- --------------------------------------------------------------------------
-- Production preflight (2026-07-21) found six complete two-child graphs whose
-- only relationship was products.parent_set_id. Their set-header quantity is
-- physical quantity that was never exploded, so move it to every component
-- and append exact IN/OUT reclassification movements. No movement or document
-- evidence is deleted or rewritten.
do $$
declare
  v_tenant_id constant uuid := '5443b130-cc28-45af-a420-cd500b288890';
  v_graph_count integer;
  v_graph_hash text;
  v_registry_count integer;
  v_active_reservations integer;
begin
  -- On an idempotent bootstrap/replay the migration operations already prove
  -- the cutover. On the first production application, require the exact
  -- read-only fingerprint captured immediately before authoring this file.
  if exists (
    select 1 from public.inventory_accounting_operations operation
    where operation.tenant_id = v_tenant_id
      and operation.operation_key like 'migration:20260721190000:set:%'
  ) then
    return;
  end if;
  if not exists (
    select 1 from public.products product
    where product.tenant_id = v_tenant_id and product.sku = 'AE0368'
  ) then
    return;
  end if;

  with graph as (
    select
      product.id, product.tenant_id, product.sku, product.is_set,
      product.parent_set_id, product.component_label,
      product.component_position, product.inventory_qty,
      product.stock_quantity, product.cost, product.price
    from public.products product
    where product.tenant_id = v_tenant_id
      and (coalesce(product.is_set, false) or product.parent_set_id is not null)
  )
  select count(*)::integer,
         md5(string_agg(concat_ws('|',
           id::text, coalesce(sku, ''), coalesce(is_set, false)::text,
           coalesce(parent_set_id::text, ''), coalesce(component_label, ''),
           coalesce(component_position::text, ''),
           coalesce(inventory_qty::text, ''),
           coalesce(stock_quantity::text, ''), coalesce(cost::text, ''),
           coalesce(price::text, '')
         ), E'\n' order by id))
  into v_graph_count, v_graph_hash
  from graph;

  select count(*)::integer into v_registry_count
  from public.product_set_components component
  where component.tenant_id = v_tenant_id;

  select count(*)::integer into v_active_reservations
  from public.online_order_inventory_reservations reservation
  join public.online_order_items item
    on item.id = reservation.order_item_id
   and item.tenant_id = reservation.tenant_id
  where reservation.tenant_id = v_tenant_id
    and reservation.state in ('active', 'consuming')
    and (reservation.state = 'consuming' or reservation.expires_at > clock_timestamp())
    and item.product_id in (
      select product.id from public.products product
      where product.tenant_id = v_tenant_id
        and (coalesce(product.is_set, false) or product.parent_set_id is not null)
    );

  if v_graph_count <> 19
     or v_graph_hash <> 'b96d134f369c4bac0b89f7becbb02be0'
     or v_registry_count <> 0
     or v_active_reservations <> 0 then
    raise exception
      'Product-set cutover fingerprint changed (rows %, hash %, registry %, reservations %)',
      v_graph_count, v_graph_hash, v_registry_count, v_active_reservations;
  end if;

  -- Authorize only the immediately following tenant-scoped data cutover. This
  -- transaction-local marker remains unset on canonical bootstraps, replays,
  -- or any database where the exact production fingerprint is absent.
  perform set_config(
    'app.product_set_cutover_authorization',
    'b96d134f369c4bac0b89f7becbb02be0',
    true
  );
end $$;

do $$
declare
  v_tenant_id constant uuid := '5443b130-cc28-45af-a420-cd500b288890';
  v_target_skus constant text[] := array[
    '10283', '19102', '2000000178066', '4710944234304', 'AE0368', 'S59867'
  ];
  v_set public.products%rowtype;
  v_child public.products%rowtype;
  v_parent_quantity integer;
  v_child_quantity integer;
  v_operation_id uuid;
  v_operation_key text;
  v_before jsonb;
  v_after jsonb;
begin
  if coalesce(
    current_setting('app.product_set_cutover_authorization', true), ''
  ) <> 'b96d134f369c4bac0b89f7becbb02be0' then
    return;
  end if;

  perform set_config('app.product_set_composition_writer', 'migration', true);
  perform set_config('app.skip_stock_adjustment_trigger', 'true', true);
  perform set_config('app.skip_sync_set_inventory', 'true', true);

  if exists (
    select 1
    from public.products set_product
    where set_product.tenant_id = v_tenant_id
      and set_product.sku = any(v_target_skus)
      and coalesce(set_product.is_set, false)
      and exists (
        select 1 from public.products child
        where child.parent_set_id = set_product.id
      )
      and (
        coalesce(set_product.inventory_qty, 0)
          <> coalesce(set_product.stock_quantity, 0)
        or coalesce(set_product.inventory_qty, 0) < 0
      )
  ) then
    raise exception 'Legacy set cutover refused: a set header has ambiguous stock columns';
  end if;

  if exists (
    select 1
    from public.products child
    join public.products set_product
      on set_product.id = child.parent_set_id
     and set_product.tenant_id = child.tenant_id
    where set_product.tenant_id = v_tenant_id
      and set_product.sku = any(v_target_skus)
      and coalesce(set_product.is_set, false)
      and (
        child.tenant_id <> set_product.tenant_id
        or coalesce(child.is_set, false)
        or coalesce(child.product_type, 'product') = 'service'
        or not coalesce(child.track_stock, true)
        or coalesce(child.inventory_qty, 0)
             <> coalesce(child.stock_quantity, 0)
      )
  ) then
    raise exception 'Legacy set cutover refused: a component graph is invalid or ambiguous';
  end if;

  if exists (
    select 1
    from public.products child
    join public.products set_product
      on set_product.id = child.parent_set_id
     and set_product.tenant_id = child.tenant_id
    where set_product.tenant_id = v_tenant_id
      and set_product.sku = any(v_target_skus)
      and coalesce(set_product.is_set, false)
    group by child.parent_set_id, child.component_position
    having child.component_position is null or count(*) > 1
  ) then
    raise exception 'Legacy set cutover refused: component positions are missing or duplicated';
  end if;

  for v_set in
    select set_product.*
    from public.products set_product
    where set_product.tenant_id = v_tenant_id
      and set_product.sku = any(v_target_skus)
      and coalesce(set_product.is_set, false)
      and exists (
        select 1 from public.products child
        where child.parent_set_id = set_product.id
          and child.tenant_id = set_product.tenant_id
      )
    order by set_product.tenant_id, set_product.id
    for update
  loop
    v_operation_key := 'migration:20260721190000:set:' || v_set.id::text;
    select operation.id into v_operation_id
    from public.inventory_accounting_operations operation
    where operation.tenant_id = v_set.tenant_id
      and operation.operation_key = v_operation_key;

    if v_operation_id is not null then
      continue;
    end if;

    v_parent_quantity := coalesce(v_set.inventory_qty, 0);
    v_before := jsonb_build_object(
      'parent', jsonb_build_object(
        'id', v_set.id,
        'sku', v_set.sku,
        'stock', v_parent_quantity,
        'unit_cost', coalesce(v_set.cost, 0)
      ),
      'legacy_components', coalesce((
        select jsonb_agg(jsonb_build_object(
          'id', child.id,
          'sku', child.sku,
          'stock', coalesce(child.inventory_qty, 0),
          'unit_cost', coalesce(child.cost, 0),
          'position', child.component_position
        ) order by child.component_position)
        from public.products child
        where child.tenant_id = v_set.tenant_id
          and child.parent_set_id = v_set.id
      ), '[]'::jsonb)
    );

    insert into public.inventory_accounting_operations (
      tenant_id, operation_key, source_channel, action, document_type,
      document_id, actor_id, executor, before_snapshot, context
    ) values (
      v_set.tenant_id, v_operation_key, 'schema_migration',
      'canonicalize_product_set_inventory', 'product_set', v_set.id,
      null, '20260721190000_canonicalize_product_set_inventory', v_before,
      jsonb_build_object(
        'legacy_relation', 'products.parent_set_id',
        'canonical_relation', 'product_set_components',
        'parent_quantity_transferred', v_parent_quantity,
        'accounting_effect', 'none_inventory_reclassification'
      )
    ) returning id into v_operation_id;

    perform public.append_inventory_accounting_checkpoint(
      v_operation_id, 'accepted', 'completed', 'product_set', v_set.id,
      jsonb_build_object('migration', '20260721190000')
    );
    perform public.append_inventory_accounting_checkpoint(
      v_operation_id, 'source_snapshotted', 'completed', 'product_set', v_set.id,
      v_before
    );

    insert into public.product_set_components (
      tenant_id, set_product_id, component_product_id, component_label,
      component_position, quantity_in_set, cost_ratio, price_ratio
    )
    select
      child.tenant_id, v_set.id, child.id,
      coalesce(nullif(child.component_label, ''), child.name),
      child.component_position, 1,
      case when coalesce(v_set.cost, 0) > 0
        then least(greatest(coalesce(child.cost, 0) / v_set.cost, 0), 1)
      end,
      case when coalesce(v_set.price, 0) > 0
        then least(greatest(coalesce(child.price, 0) / v_set.price, 0), 1)
      end
    from public.products child
    where child.tenant_id = v_set.tenant_id
      and child.parent_set_id = v_set.id
    order by child.component_position
    on conflict (set_product_id, component_product_id) do nothing;

    if v_parent_quantity > 0 then
      for v_child in
        select child.*
        from public.product_set_components component
        join public.products child
          on child.id = component.component_product_id
         and child.tenant_id = component.tenant_id
        where component.tenant_id = v_set.tenant_id
          and component.set_product_id = v_set.id
        order by child.id
        for update of child
      loop
        v_child_quantity := coalesce(v_child.inventory_qty, 0) + v_parent_quantity;
        update public.products
        set inventory_qty = v_child_quantity,
            stock_quantity = v_child_quantity,
            updated_at = clock_timestamp()
        where id = v_child.id and tenant_id = v_set.tenant_id;

        insert into public.stock_movements (
          tenant_id, product_id, type, movement_type, quantity, reference,
          notes, date, created_at, updated_at, operation_id,
          source_document_type, source_document_id, created_by,
          stock_before, stock_after
        ) values (
          v_set.tenant_id, v_child.id, 'IN',
          'product_set_parent_stock_transfer_in', v_parent_quantity,
          'product_set_cutover:' || v_set.id::text,
          format('Transferencia física desde cabecera legacy %s', v_set.sku),
          clock_timestamp(), clock_timestamp(), clock_timestamp(), v_operation_id,
          'product_set', v_set.id, null,
          coalesce(v_child.inventory_qty, 0), v_child_quantity
        );
      end loop;

      update public.products
      set inventory_qty = 0, stock_quantity = 0, updated_at = clock_timestamp()
      where id = v_set.id and tenant_id = v_set.tenant_id;

      insert into public.stock_movements (
        tenant_id, product_id, type, movement_type, quantity, reference,
        notes, date, created_at, updated_at, operation_id,
        source_document_type, source_document_id, created_by,
        stock_before, stock_after
      ) values (
        v_set.tenant_id, v_set.id, 'OUT',
        'product_set_parent_stock_transfer_out', -v_parent_quantity,
        'product_set_cutover:' || v_set.id::text,
        'Cabecera de set convertida a proyección virtual',
        clock_timestamp(), clock_timestamp(), clock_timestamp(), v_operation_id,
        'product_set', v_set.id, null, v_parent_quantity, 0
      );
    end if;

    v_after := jsonb_build_object(
      'parent', jsonb_build_object('id', v_set.id, 'sku', v_set.sku, 'stock', 0),
      'components', coalesce((
        select jsonb_agg(jsonb_build_object(
          'id', child.id,
          'sku', child.sku,
          'stock', coalesce(child.inventory_qty, 0),
          'quantity_in_set', component.quantity_in_set
        ) order by component.component_position)
        from public.product_set_components component
        join public.products child
          on child.id = component.component_product_id
         and child.tenant_id = component.tenant_id
        where component.tenant_id = v_set.tenant_id
          and component.set_product_id = v_set.id
      ), '[]'::jsonb)
    );

    update public.inventory_accounting_operations
    set after_snapshot = v_after
    where id = v_operation_id and tenant_id = v_set.tenant_id;

    perform public.append_inventory_accounting_checkpoint(
      v_operation_id, 'inventory_applied', 'completed', 'product_set', v_set.id,
      jsonb_build_object('parent_quantity_transferred', v_parent_quantity)
    );
    perform public.complete_inventory_accounting_operation(
      v_operation_id, v_set.tenant_id,
      jsonb_build_object('canonical_component_count', jsonb_array_length(v_after->'components'))
    );
  end loop;
end $$;

create or replace function public.enforce_product_set_product_row()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_writer text := coalesce(
    current_setting('app.product_set_composition_writer', true), ''
  );
  v_parent public.products%rowtype;
begin
  if coalesce(new.is_set, false) then
    if coalesce(new.inventory_qty, 0) <> 0
       or coalesce(new.stock_quantity, 0) <> 0 then
      raise exception 'Set parent physical stock must remain zero; use calculated availability'
        using errcode = '23514';
    end if;
    if new.parent_set_id is not null
       or coalesce(new.product_type, 'product') = 'service'
       or not coalesce(new.track_stock, true)
       or coalesce(new.purchase_treatment, 'inventory') <> 'inventory' then
      raise exception 'Set parent must be a stock-tracked inventory product without a parent'
        using errcode = '23514';
    end if;
  end if;

  if new.parent_set_id is not null then
    if coalesce(new.is_set, false)
       or coalesce(new.product_type, 'product') = 'service'
       or not coalesce(new.track_stock, true) then
      raise exception 'Set component must be a stock-tracked ordinary product'
        using errcode = '23514';
    end if;
    select * into v_parent
    from public.products parent
    where parent.id = new.parent_set_id
      and parent.tenant_id = new.tenant_id;
    if not found or not coalesce(v_parent.is_set, false) then
      raise exception 'Component parent set is missing, cross-tenant, or invalid'
        using errcode = '23514';
    end if;
  end if;

  if tg_op = 'INSERT' then
    if (coalesce(new.is_set, false) or new.parent_set_id is not null)
       and v_writer not in ('aggregate_rpc', 'migration') then
      raise exception 'Product sets must be created through save_product_set_aggregate'
        using errcode = '42501';
    end if;
  else
    if (
      old.is_set is distinct from new.is_set
      or old.parent_set_id is distinct from new.parent_set_id
      or old.component_label is distinct from new.component_label
      or old.component_position is distinct from new.component_position
    ) and v_writer not in ('aggregate_rpc', 'migration') then
      raise exception 'Product set relationships must be changed through save_product_set_aggregate'
        using errcode = '42501';
    end if;

    if coalesce(old.is_set, false)
       and not coalesce(new.is_set, false)
       and exists (
         select 1 from public.product_set_components component
         where component.tenant_id = old.tenant_id
           and component.set_product_id = old.id
       ) then
      raise exception 'A composed set cannot be converted to an ordinary product'
        using errcode = '23514';
    end if;

    if old.parent_set_id is not null
       and new.parent_set_id is distinct from old.parent_set_id
       and exists (
         select 1 from public.stock_movements movement
         where movement.tenant_id = old.tenant_id
           and movement.product_id = old.id
       )
       and v_writer <> 'migration' then
      raise exception 'A component with inventory history cannot change parent set'
        using errcode = '23514';
    end if;
  end if;

  return new;
end;
$$;

revoke all on function public.enforce_product_set_product_row()
  from public, anon, authenticated;

drop trigger if exists trg_00_enforce_product_set_product_row on public.products;
create trigger trg_00_enforce_product_set_product_row
  before insert or update of
    tenant_id, is_set, parent_set_id, component_label, component_position,
    inventory_qty, stock_quantity, product_type, track_stock, purchase_treatment
  on public.products
  for each row execute function public.enforce_product_set_product_row();

create or replace function public.assert_valid_product_set_maps(
  p_tenant_id uuid,
  p_items jsonb
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_item jsonb;
  v_product public.products%rowtype;
begin
  for v_item in select value from jsonb_array_elements(coalesce(p_items, '[]'::jsonb))
  loop
    v_product := null;
    if nullif(v_item->>'product_id', '') is not null then
      select * into v_product
      from public.products product
      where product.id = nullif(v_item->>'product_id', '')::uuid
        and product.tenant_id = p_tenant_id;
    elsif nullif(v_item->>'product_sku', '') is not null then
      select * into v_product
      from public.products product
      where product.sku = v_item->>'product_sku'
        and product.tenant_id = p_tenant_id
      limit 1;
    end if;

    if v_product.id is not null and coalesce(v_product.is_set, false) then
      if coalesce(v_product.inventory_qty, 0) <> 0
         or coalesce(v_product.stock_quantity, 0) <> 0 then
        raise exception 'Set parent % has forbidden physical stock', v_product.sku
          using errcode = '23514';
      end if;
      if not exists (
        select 1
        from public.product_set_components component
        where component.tenant_id = p_tenant_id
          and component.set_product_id = v_product.id
      ) then
        raise exception 'Set product % has no canonical components', v_product.sku
          using errcode = '23514';
      end if;
      if exists (
        select 1
        from public.product_set_components component
        left join public.products child
          on child.id = component.component_product_id
         and child.tenant_id = component.tenant_id
        where component.tenant_id = p_tenant_id
          and component.set_product_id = v_product.id
          and (
            child.id is null
            or child.parent_set_id is distinct from v_product.id
            or coalesce(child.is_set, false)
            or not coalesce(child.track_stock, true)
            or component.quantity_in_set <= 0
          )
      ) then
        raise exception 'Set product % has an invalid canonical component map', v_product.sku
          using errcode = '23514';
      end if;
    end if;
  end loop;
end;
$$;

revoke all on function public.assert_valid_product_set_maps(uuid, jsonb)
  from public, anon, authenticated;

-- Keep the authoritative 20260718300010 checkout kernel byte-for-byte except
-- for its two set-awareness fragments. Re-declaring the 440-line function here
-- would risk regressing later shipping, tax, idempotency and event behavior.
-- Refuse the migration if the installed source is not the expected kernel.
do $checkout_set_availability_patch$
declare
  v_definition text;
  v_old_projection constant text := $old_projection$      product.track_stock,
      product.inventory_qty,$old_projection$;
  v_new_projection constant text := $new_projection$      product.track_stock,
      product.is_set,
      product.inventory_qty,$new_projection$;
  v_old_validation constant text := $old_validation$    if not (
      coalesce(v_product.is_service, false)
      or v_product.product_type = 'service'
    )
       and coalesce(v_product.track_stock, true) then
      if v_product.stock_quantity is not null
         and v_product.inventory_qty is not null
         and v_product.stock_quantity <> v_product.inventory_qty then
        raise exception 'Product stock columns disagree; checkout blocked for %',
          v_product.name;
      end if;
      if coalesce(v_product.stock_quantity, v_product.inventory_qty, 0)
         < v_quantity then
        raise exception 'Insufficient stock for product %', v_product.name;
      end if;
    end if;$old_validation$;
  v_new_validation constant text := $new_validation$    if not (
      coalesce(v_product.is_service, false)
      or v_product.product_type = 'service'
    )
       and coalesce(v_product.track_stock, true) then
      if coalesce(v_product.is_set, false) then
        -- Canonical set headers are virtual. Validate their component map and
        -- availability after active reservations; the item-insert trigger then
        -- locks and reserves every physical component atomically.
        perform public.assert_valid_product_set_maps(
          v_tenant_id,
          jsonb_build_array(jsonb_build_object(
            'product_id', v_product.id,
            'quantity', v_quantity
          ))
        );
        if public.online_product_available_quantity(
          v_tenant_id,
          v_product.id
        ) < v_quantity then
          raise exception 'Insufficient stock for product %', v_product.name;
        end if;
      else
        if v_product.stock_quantity is not null
           and v_product.inventory_qty is not null
           and v_product.stock_quantity <> v_product.inventory_qty then
          raise exception 'Product stock columns disagree; checkout blocked for %',
            v_product.name;
        end if;
        if coalesce(v_product.stock_quantity, v_product.inventory_qty, 0)
           < v_quantity then
          raise exception 'Insufficient stock for product %', v_product.name;
        end if;
      end if;
    end if;$new_validation$;
begin
  select pg_get_functiondef(
    'public.create_public_online_order_unkeyed(jsonb,jsonb)'::regprocedure
  ) into v_definition;

  if position('-- Canonical set headers are virtual.' in v_definition) > 0 then
    return;
  end if;

  if (length(v_definition) - length(replace(
        v_definition, v_old_projection, ''
      ))) <> length(v_old_projection)
     or (length(v_definition) - length(replace(
        v_definition, v_old_validation, ''
      ))) <> length(v_old_validation) then
    raise exception
      'Checkout set-availability patch refused: authoritative kernel changed';
  end if;

  v_definition := replace(
    v_definition,
    v_old_projection,
    v_new_projection
  );
  v_definition := replace(
    v_definition,
    v_old_validation,
    v_new_validation
  );
  execute v_definition;
end;
$checkout_set_availability_patch$;

comment on function public.create_public_online_order_unkeyed(jsonb, jsonb) is
  'Private authoritative checkout implementation. Re-reads product price/tax/stock, derives set availability from canonical components, verifies the shipping quote and persists immutable tax/accounting snapshots atomically.';

revoke all on function public.create_public_online_order_unkeyed(jsonb, jsonb)
  from public, anon, authenticated, service_role;

-- The reservation-aware public catalog wrapper must receive every otherwise
-- eligible row before applying stock policy with derived availability. The
-- private legacy ranking kernel still read the tenant's stock policy and
-- filtered virtual set headers on raw stock=0, despite the wrapper passing
-- p_only_in_stock=false. Disable only that private prefilter; search/ranking,
-- category/image visibility and pagination remain the installed live body.
do $catalog_set_availability_patch$
declare
  v_definition text;
  v_old_policy constant text := $old_policy$      case lower(coalesce(
        nullif(trim(coalesce((
          select ws.value
          from public.website_settings ws
          where ws.tenant_id = p_tenant_id
            and ws.key = 'product_visibility_stock_policy'
          limit 1
        ), '')), ''),
        case when p_only_in_stock then 'available_only' else 'all' end
      ))
        when 'all' then 'all'
        when 'both' then 'all'
        when 'out_of_stock_only' then 'out_of_stock_only'
        when 'out_of_stock' then 'out_of_stock_only'
        when 'sin_stock' then 'out_of_stock_only'
        else 'available_only'
      end as stock_policy,$old_policy$;
  v_new_policy constant text := $new_policy$      -- The outer reservation-aware wrapper is the sole stock-policy owner.
      'all'::text as stock_policy,$new_policy$;
begin
  select pg_get_functiondef(
    'public.get_public_products_without_inventory_reservations(uuid,uuid[],uuid[],text,text,text,boolean,text,integer,integer)'::regprocedure
  ) into v_definition;

  if position(
    '-- The outer reservation-aware wrapper is the sole stock-policy owner.'
    in v_definition
  ) > 0 then
    return;
  end if;

  if (length(v_definition) - length(replace(
        v_definition, v_old_policy, ''
      ))) <> length(v_old_policy) then
    raise exception
      'Public catalog set-availability patch refused: ranking kernel changed';
  end if;

  execute replace(v_definition, v_old_policy, v_new_policy);
end;
$catalog_set_availability_patch$;

comment on function public.get_public_products_without_inventory_reservations(
  uuid, uuid[], uuid[], text, text, text, boolean, text, integer, integer
) is
  'Private public-catalog search/ranking base. Stock policy is intentionally deferred to the reservation-aware public wrapper.';

revoke all on function public.get_public_products_without_inventory_reservations(
  uuid, uuid[], uuid[], text, text, text, boolean, text, integer, integer
) from public, anon, authenticated, service_role;

-- Wrap the exact live inventory kernels instead of copying an older body.
-- This preserves all later online-order trace behavior while making the
-- historical zero-component loop fail closed.
do $$
begin
  if to_regprocedure(
    'public.consume_sales_invoice_inventory_pre_set_guard(public.sales_invoices)'
  ) is null then
    alter function public.consume_sales_invoice_inventory(public.sales_invoices)
      rename to consume_sales_invoice_inventory_pre_set_guard;
  end if;
  if to_regprocedure(
    'public.consume_purchase_invoice_inventory_pre_set_guard(public.purchase_invoices)'
  ) is null then
    alter function public.consume_purchase_invoice_inventory(public.purchase_invoices)
      rename to consume_purchase_invoice_inventory_pre_set_guard;
  end if;
  if to_regprocedure(
    'public.sales_invoice_stock_requirements_pre_set_guard(uuid,jsonb)'
  ) is null then
    alter function public.sales_invoice_stock_requirements(uuid, jsonb)
      rename to sales_invoice_stock_requirements_pre_set_guard;
  end if;
end $$;

create or replace function public.consume_sales_invoice_inventory(
  p_invoice public.sales_invoices
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.assert_valid_product_set_maps(p_invoice.tenant_id, p_invoice.items);
  perform public.consume_sales_invoice_inventory_pre_set_guard(p_invoice);
end;
$$;

create or replace function public.consume_purchase_invoice_inventory(
  p_invoice public.purchase_invoices
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.assert_valid_product_set_maps(p_invoice.tenant_id, p_invoice.items);
  perform public.consume_purchase_invoice_inventory_pre_set_guard(p_invoice);
end;
$$;

create or replace function public.sales_invoice_stock_requirements(
  p_tenant_id uuid,
  p_items jsonb
)
returns table(product_id uuid, quantity integer)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  perform public.assert_valid_product_set_maps(p_tenant_id, p_items);
  return query
  select requirement.product_id, requirement.quantity
  from public.sales_invoice_stock_requirements_pre_set_guard(p_tenant_id, p_items)
    requirement;
end;
$$;

revoke all on function public.consume_sales_invoice_inventory(public.sales_invoices)
  from public, anon, authenticated, service_role;
revoke all on function public.consume_purchase_invoice_inventory(public.purchase_invoices)
  from public, anon, authenticated, service_role;
revoke all on function public.sales_invoice_stock_requirements(uuid, jsonb)
  from public, anon, authenticated;

-- Retained implementations are owner-only, matching the legacy RPC hardening
-- boundary; only the guarded wrappers are called by database kernels.
revoke all on function public.consume_sales_invoice_inventory_pre_set_guard(public.sales_invoices)
  from public, anon, authenticated, service_role;
revoke all on function public.consume_purchase_invoice_inventory_pre_set_guard(public.purchase_invoices)
  from public, anon, authenticated, service_role;
revoke all on function public.sales_invoice_stock_requirements_pre_set_guard(uuid, jsonb)
  from public, anon, authenticated, service_role;

drop policy if exists "product_set_components_insert"
  on public.product_set_components;
drop policy if exists "product_set_components_update"
  on public.product_set_components;
drop policy if exists "product_set_components_delete"
  on public.product_set_components;
revoke all on public.product_set_components
  from public, anon, authenticated, service_role;
grant select on public.product_set_components to authenticated, service_role;

create or replace view public.product_set_integrity_issues
with (security_invoker = true)
as
select
  product.tenant_id,
  product.id as product_id,
  product.sku,
  'set_parent_physical_stock'::text as issue_code,
  jsonb_build_object(
    'inventory_qty', product.inventory_qty,
    'stock_quantity', product.stock_quantity
  ) as evidence
from public.products product
where coalesce(product.is_set, false)
  and (
    coalesce(product.inventory_qty, 0) <> 0
    or coalesce(product.stock_quantity, 0) <> 0
  )
union all
select
  product.tenant_id,
  product.id,
  product.sku,
  'set_without_canonical_components',
  '{}'::jsonb
from public.products product
where coalesce(product.is_set, false)
  and not exists (
    select 1 from public.product_set_components component
    where component.tenant_id = product.tenant_id
      and component.set_product_id = product.id
  )
union all
select
  child.tenant_id,
  child.id,
  child.sku,
  'legacy_parent_without_canonical_link',
  jsonb_build_object('parent_set_id', child.parent_set_id)
from public.products child
where child.parent_set_id is not null
  and not exists (
    select 1 from public.product_set_components component
    where component.tenant_id = child.tenant_id
      and component.component_product_id = child.id
      and component.set_product_id = child.parent_set_id
  )
union all
select
  component.tenant_id,
  component.component_product_id,
  child.sku,
  'canonical_legacy_mirror_mismatch',
  jsonb_build_object(
    'canonical_parent_id', component.set_product_id,
    'legacy_parent_id', child.parent_set_id
  )
from public.product_set_components component
join public.products child
  on child.id = component.component_product_id
 and child.tenant_id = component.tenant_id
where child.parent_set_id is distinct from component.set_product_id;

revoke all on public.product_set_integrity_issues from public, anon;
grant select on public.product_set_integrity_issues to authenticated;

comment on view public.product_set_integrity_issues is
  'Tenant-RLS projection of canonical product-set mapping and virtual-parent stock violations.';

-- S60994 is the single production orphan discovered by the read-only
-- fingerprint: stock 1, no child graph and no document history. It is an
-- ordinary stocked product incorrectly flagged as a set. Demote it only while
-- that exact fingerprint remains true; otherwise fail rather than guess.
do $$
declare
  v_product public.products%rowtype;
  v_operation_id uuid;
  v_document_references integer;
  v_movement_count integer;
  v_movement_net numeric;
begin
  select orphan.* into v_product
  from public.products orphan
  join public.products ae
    on ae.tenant_id = orphan.tenant_id and ae.sku = 'AE0368'
  where orphan.sku = 'S60994'
    and orphan.tenant_id = '5443b130-cc28-45af-a420-cd500b288890'::uuid
  for update;

  if not found then return; end if;
  if not coalesce(v_product.is_set, false) then return; end if;

  select count(*) into v_document_references
  from (
    select invoice.id
    from public.purchase_invoices invoice
    cross join lateral jsonb_array_elements(coalesce(invoice.items, '[]'::jsonb)) item
    where invoice.tenant_id = v_product.tenant_id
      and nullif(item->>'product_id', '')::uuid = v_product.id
    union all
    select invoice.id
    from public.sales_invoices invoice
    cross join lateral jsonb_array_elements(coalesce(invoice.items, '[]'::jsonb)) item
    where invoice.tenant_id = v_product.tenant_id
      and nullif(item->>'product_id', '')::uuid = v_product.id
    union all
    select item.id from public.online_order_items item
    where item.tenant_id = v_product.tenant_id and item.product_id = v_product.id
    union all
    select line.id from public.purchase_receipt_lines line
    where line.tenant_id = v_product.tenant_id and line.product_id = v_product.id
  ) reference;

  select count(*), coalesce(sum(case
    when movement.type in ('IN', 'TRANSFER_IN') then abs(movement.quantity)
    when movement.type in ('OUT', 'TRANSFER_OUT') then -abs(movement.quantity)
    else movement.quantity
  end), 0)
  into v_movement_count, v_movement_net
  from public.stock_movements movement
  where movement.tenant_id = v_product.tenant_id
    and movement.product_id = v_product.id;

  if coalesce(v_product.inventory_qty, 0) <> 1
     or coalesce(v_product.stock_quantity, 0) <> 1
     or exists (select 1 from public.products child where child.parent_set_id = v_product.id)
     or exists (select 1 from public.product_set_components component where component.set_product_id = v_product.id)
     or v_document_references <> 0
     or v_movement_count <> 1
     or v_movement_net <> 1 then
    raise exception 'S60994 orphan-set repair refused because its production fingerprint changed';
  end if;

  insert into public.inventory_accounting_operations (
    tenant_id, operation_key, source_channel, action, document_type,
    document_id, actor_id, executor, before_snapshot, after_snapshot, context,
    outcome, completed_at
  ) values (
    v_product.tenant_id, 'migration:20260721190000:demote:S60994',
    'schema_migration', 'demote_empty_product_set', 'product_set', v_product.id,
    null, '20260721190000_canonicalize_product_set_inventory',
    jsonb_build_object('is_set', true, 'stock', 1, 'movement_count', 1),
    jsonb_build_object('is_set', false, 'stock', 1, 'movement_count', 1),
    jsonb_build_object('reason', 'no_components_no_document_history'),
    'completed', clock_timestamp()
  ) on conflict (tenant_id, operation_key) do nothing
  returning id into v_operation_id;

  if v_operation_id is null then return; end if;

  perform set_config('app.product_set_composition_writer', 'migration', true);
  update public.products
  set is_set = false, set_type = null, updated_at = clock_timestamp()
  where id = v_product.id and tenant_id = v_product.tenant_id;

  perform public.append_inventory_accounting_checkpoint(
    v_operation_id, 'source_snapshotted', 'completed', 'product', v_product.id,
    jsonb_build_object('is_set', true, 'stock', 1)
  );
  perform public.append_inventory_accounting_checkpoint(
    v_operation_id, 'invariants_verified', 'completed', 'product', v_product.id,
    jsonb_build_object('is_set', false, 'stock_preserved', 1)
  );
  perform public.append_inventory_accounting_checkpoint(
    v_operation_id, 'completed', 'completed', 'product', v_product.id,
    jsonb_build_object('classification', 'ordinary_stocked_product')
  );
end $$;

-- AE0368: strict, one-case repair for the purchase receipt omitted by the old
-- zero-row component loop. The purchase journal already debited inventory, so
-- this appends physical IN evidence only; it deliberately creates no journal.
do $$
declare
  v_parent public.products%rowtype;
  v_front public.products%rowtype;
  v_rear public.products%rowtype;
  v_purchase public.purchase_invoices%rowtype;
  v_sale public.sales_invoices%rowtype;
  v_purchase_match_count integer;
  v_sale_match_count integer;
  v_purchase_movement_count integer;
  v_front_net numeric;
  v_rear_net numeric;
  v_journal_match_count integer;
  v_operation_id uuid;
  v_child public.products%rowtype;
begin
  select * into v_parent
  from public.products
  where tenant_id = '5443b130-cc28-45af-a420-cd500b288890'::uuid
    and sku = 'AE0368'
  for update;
  if not found then return; end if;

  if exists (
    select 1 from public.inventory_accounting_operations operation
    where operation.tenant_id = v_parent.tenant_id
      and operation.operation_key = 'repair:AE0368:AE150626:missing-set-receipt:v1'
  ) then return; end if;

  select * into v_front from public.products
  where tenant_id = v_parent.tenant_id and sku = 'AE0368-DELAN' for update;
  if not found then
    raise exception 'AE0368 repair refused: front component is missing';
  end if;
  select * into v_rear from public.products
  where tenant_id = v_parent.tenant_id and sku = 'AE0368-TRASE' for update;
  if not found then
    raise exception 'AE0368 repair refused: rear component is missing';
  end if;

  select * into v_purchase
  from public.purchase_invoices invoice
  where invoice.id = 'f5159c1f-cc86-4447-b090-2d5399be5518'::uuid
    and invoice.tenant_id = v_parent.tenant_id
  for update;
  if not found then
    raise exception 'AE0368 repair refused: purchase invoice is missing';
  end if;

  select * into v_sale
  from public.sales_invoices invoice
  where invoice.id = '4850ccfa-b5e8-4315-98db-42c9df98b0a3'::uuid
    and invoice.tenant_id = v_parent.tenant_id
  for update;
  if not found then
    raise exception 'AE0368 repair refused: sales invoice is missing';
  end if;

  select count(distinct invoice.id)
  into v_purchase_match_count
  from public.purchase_invoices invoice
  cross join lateral jsonb_array_elements(coalesce(invoice.items, '[]'::jsonb)) item
  where invoice.id = 'f5159c1f-cc86-4447-b090-2d5399be5518'::uuid
    and invoice.tenant_id = v_parent.tenant_id
    and invoice.invoice_number = 'AE150626'
    and nullif(item->>'product_id', '')::uuid = v_parent.id
    and coalesce(nullif(item->>'quantity', '')::numeric, 0) = 1
    and coalesce(nullif(item->>'unit_cost', '')::numeric, 0) = 22520
    and coalesce(nullif(item->>'purchase_treatment', ''), 'inventory') = 'inventory';

  select count(distinct invoice.id) into v_sale_match_count
  from public.sales_invoices invoice
  where invoice.id = '4850ccfa-b5e8-4315-98db-42c9df98b0a3'::uuid
    and invoice.tenant_id = v_parent.tenant_id
    and invoice.invoice_number = 'FV-00715'
    and exists (
      select 1 from jsonb_array_elements(coalesce(invoice.items, '[]'::jsonb)) item
      where nullif(item->>'product_id', '')::uuid = v_front.id
        and coalesce(nullif(item->>'quantity', '')::numeric, 0) = 1
    )
    and exists (
      select 1 from jsonb_array_elements(coalesce(invoice.items, '[]'::jsonb)) item
      where nullif(item->>'product_id', '')::uuid = v_rear.id
        and coalesce(nullif(item->>'quantity', '')::numeric, 0) = 1
    );

  select count(*) into v_purchase_movement_count
  from public.stock_movements movement
  where movement.tenant_id = v_parent.tenant_id
    and movement.reference = 'purchase_invoice:' || v_purchase.id::text
    and movement.product_id in (v_parent.id, v_front.id, v_rear.id);

  select coalesce(sum(case
    when movement.type in ('IN', 'TRANSFER_IN') then abs(movement.quantity)
    when movement.type in ('OUT', 'TRANSFER_OUT') then -abs(movement.quantity)
    else movement.quantity
  end), 0) into v_front_net
  from public.stock_movements movement
  where movement.tenant_id = v_parent.tenant_id and movement.product_id = v_front.id;

  select coalesce(sum(case
    when movement.type in ('IN', 'TRANSFER_IN') then abs(movement.quantity)
    when movement.type in ('OUT', 'TRANSFER_OUT') then -abs(movement.quantity)
    else movement.quantity
  end), 0) into v_rear_net
  from public.stock_movements movement
  where movement.tenant_id = v_parent.tenant_id and movement.product_id = v_rear.id;

  select count(*) into v_journal_match_count
  from (
    select entry.id
    from public.journal_entries entry
    join public.journal_lines line
      on line.entry_id = entry.id and line.tenant_id = entry.tenant_id
    where entry.tenant_id = v_parent.tenant_id
      and entry.entry_number = 'AC-01826'
    group by entry.id
    having round(sum(line.debit_amount), 2) = 79933
       and round(sum(line.credit_amount), 2) = 79933
       and count(*) filter (
         where line.account_code = '1105' and line.debit_amount = 79933
       ) = 1
  ) balanced_purchase_journal;

  if not coalesce(v_parent.is_set, false)
     or coalesce(v_parent.inventory_qty, 0) <> 0
     or coalesce(v_parent.stock_quantity, 0) <> 0
     or v_front.parent_set_id is distinct from v_parent.id
     or v_rear.parent_set_id is distinct from v_parent.id
     or coalesce(v_front.inventory_qty, 0) <> -1
     or coalesce(v_front.stock_quantity, 0) <> -1
     or coalesce(v_rear.inventory_qty, 0) <> -1
     or coalesce(v_rear.stock_quantity, 0) <> -1
     or v_front_net <> -1 or v_rear_net <> -1
     or v_purchase.status <> 'received'
     or v_sale.status <> 'paid'
     or v_purchase_match_count <> 1
     or v_sale_match_count <> 1
     or v_purchase_movement_count <> 0
     or v_journal_match_count <> 1
     or (select count(*) from public.product_set_components component
         where component.tenant_id = v_parent.tenant_id
           and component.set_product_id = v_parent.id
           and component.component_product_id in (v_front.id, v_rear.id)
           and component.quantity_in_set = 1) <> 2
     or (select count(*) from public.product_set_components component
         where component.tenant_id = v_parent.tenant_id
           and component.set_product_id = v_parent.id) <> 2 then
    raise exception 'AE0368 repair refused because its production fingerprint changed';
  end if;

  insert into public.inventory_accounting_operations (
    tenant_id, operation_key, source_channel, action, document_type,
    document_id, actor_id, executor, before_snapshot, context
  ) values (
    v_parent.tenant_id, 'repair:AE0368:AE150626:missing-set-receipt:v1',
    'schema_migration', 'repair_missing_purchase_set_receipt',
    'purchase_invoice', v_purchase.id, null,
    '20260721190000_canonicalize_product_set_inventory',
    jsonb_build_object(
      'parent_stock', 0,
      'front_stock', -1,
      'rear_stock', -1,
      'purchase_movement_count', 0,
      'purchase_journal', 'AC-01826'
    ),
    jsonb_build_object(
      'set_product_id', v_parent.id,
      'set_sku', v_parent.sku,
      'purchase_invoice_id', v_purchase.id,
      'purchase_invoice_number', v_purchase.invoice_number,
      'accounting_effect', 'none_purchase_journal_already_posted',
      'repair_reason', 'legacy_empty_component_loop'
    )
  ) returning id into v_operation_id;

  perform public.append_inventory_accounting_checkpoint(
    v_operation_id, 'accepted', 'completed', 'purchase_invoice', v_purchase.id,
    jsonb_build_object('fingerprint', 'AE0368/AE150626/FV-00715/AC-01826')
  );
  perform public.append_inventory_accounting_checkpoint(
    v_operation_id, 'source_snapshotted', 'completed', 'purchase_invoice', v_purchase.id,
    jsonb_build_object('front_stock', -1, 'rear_stock', -1)
  );
  perform public.append_inventory_accounting_checkpoint(
    v_operation_id, 'inventory_planned', 'completed', 'product_set', v_parent.id,
    jsonb_build_object('front_delta', 1, 'rear_delta', 1, 'journal_delta', 0)
  );

  perform set_config('app.skip_stock_adjustment_trigger', 'true', true);
  for v_child in
    select product.* from public.products product
    where product.id in (v_front.id, v_rear.id)
      and product.tenant_id = v_parent.tenant_id
    order by product.id
    for update
  loop
    update public.products
    set inventory_qty = 0, stock_quantity = 0, updated_at = clock_timestamp()
    where id = v_child.id and tenant_id = v_parent.tenant_id;

    insert into public.stock_movements (
      tenant_id, product_id, type, movement_type, quantity, reference, notes,
      date, created_at, updated_at, operation_id, source_document_type,
      source_document_id, created_by, stock_before, stock_after
    ) values (
      v_parent.tenant_id, v_child.id, 'IN',
      'purchase_invoice_set_component_repair', 1,
      'purchase_invoice:' || v_purchase.id::text,
      format('Entrada omitida del set %s en factura %s', v_parent.sku, v_purchase.invoice_number),
      coalesce(v_purchase.date, clock_timestamp()), clock_timestamp(), clock_timestamp(),
      v_operation_id, 'purchase_invoice', v_purchase.id, null, -1, 0
    );
  end loop;

  update public.inventory_accounting_operations
  set after_snapshot = jsonb_build_object(
    'parent_stock', 0, 'front_stock', 0, 'rear_stock', 0,
    'movement_count', 2, 'journal_count', 0
  )
  where id = v_operation_id and tenant_id = v_parent.tenant_id;

  perform public.append_inventory_accounting_checkpoint(
    v_operation_id, 'inventory_applied', 'completed', 'product_set', v_parent.id,
    jsonb_build_object('front_stock', 0, 'rear_stock', 0)
  );
  perform public.complete_inventory_accounting_operation(
    v_operation_id, v_parent.tenant_id,
    jsonb_build_object('repaired_components', 2, 'journal_unchanged', true)
  );
end $$;

-- A set's externally published availability changes when any physical
-- component changes. Queue the parent directly; never materialize or touch the
-- virtual header stock and never create an inventory movement for this sync.
create or replace function public.request_parent_set_whatsapp_catalog_sync(
  p_tenant_id uuid,
  p_set_product_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_product public.products%rowtype;
  v_service_role_key text;
begin
  select product.* into v_product
  from public.products product
  where product.id = p_set_product_id
    and product.tenant_id = p_tenant_id
    and coalesce(product.is_set, false)
    and coalesce(product.is_whatsapp_catalog, false)
  for update;

  if not found then return; end if;

  update public.products product
  set whatsapp_catalog_sync_status = 'pending',
      whatsapp_catalog_sync_error = null,
      whatsapp_catalog_sync_requested_at = clock_timestamp()
  where product.id = v_product.id
    and product.tenant_id = v_product.tenant_id;

  begin
    execute $vault$
      select decrypted_secret
      from vault.decrypted_secrets
      where name = 'whatsapp_catalog_sync_service_role_key'
      order by created_at desc
      limit 1
    $vault$ into v_service_role_key;
  exception when others then
    v_service_role_key := null;
  end;

  if nullif(v_service_role_key, '') is null then
    update public.products product
    set whatsapp_catalog_sync_status = 'failed',
        whatsapp_catalog_sync_error =
          'Missing Vault secret whatsapp_catalog_sync_service_role_key'
    where product.id = v_product.id
      and product.tenant_id = v_product.tenant_id;
    return;
  end if;

  perform net.http_post(
    url := 'https://xzdvtzdqjeyqxnkqprtf.supabase.co/functions/v1/whatsapp-catalog-sync',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || v_service_role_key,
      'apikey', v_service_role_key
    ),
    body := jsonb_build_object('productId', v_product.id::text),
    timeout_milliseconds := 15000
  );
exception when others then
  -- Catalog transport must never roll back physical inventory. Preserve the
  -- failure on the parent so the existing retry/review flow remains visible.
  begin
    update public.products product
    set whatsapp_catalog_sync_status = 'failed',
        whatsapp_catalog_sync_error = sqlerrm
    where product.id = p_set_product_id
      and product.tenant_id = p_tenant_id;
  exception when others then
    null;
  end;
end;
$$;

revoke all on function public.request_parent_set_whatsapp_catalog_sync(uuid, uuid)
  from public, anon, authenticated, service_role;

create or replace function public.refresh_parent_set_whatsapp_after_component_stock()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_parent_id uuid;
begin
  if old.inventory_qty is not distinct from new.inventory_qty
     and old.stock_quantity is not distinct from new.stock_quantity then
    return new;
  end if;

  for v_parent_id in
    select parent.id
    from public.product_set_components component
    join public.products parent
      on parent.id = component.set_product_id
     and parent.tenant_id = component.tenant_id
    where component.tenant_id = new.tenant_id
      and component.component_product_id = new.id
      and coalesce(parent.is_set, false)
      and coalesce(parent.is_whatsapp_catalog, false)
  loop
    begin
      perform public.request_parent_set_whatsapp_catalog_sync(
        new.tenant_id,
        v_parent_id
      );
    exception when others then
      -- External catalog availability is eventual; stock is authoritative.
      null;
    end;
  end loop;

  return new;
end;
$$;

revoke all on function public.refresh_parent_set_whatsapp_after_component_stock()
  from public, anon, authenticated, service_role;

drop trigger if exists trg_refresh_parent_set_whatsapp_after_component_stock
  on public.products;
create trigger trg_refresh_parent_set_whatsapp_after_component_stock
  after update of inventory_qty, stock_quantity on public.products
  for each row execute function
    public.refresh_parent_set_whatsapp_after_component_stock();

create trigger trg_refresh_parent_set_purchase_list
  after update of stock_quantity, inventory_qty on public.products
  for each row execute function public.refresh_parent_set_after_component_change();

create trigger trg_refresh_purchase_list_after_set_map_change
  after insert or update or delete on public.product_set_components
  for each row execute function public.refresh_purchase_list_after_set_map_change();

do $$
declare
  v_tenant_id constant uuid := '5443b130-cc28-45af-a420-cd500b288890';
  v_target_skus constant text[] := array[
    '10283', '19102', '2000000178066', '4710944234304', 'AE0368', 'S59867'
  ];
  v_set record;
begin
  if coalesce(
    current_setting('app.product_set_cutover_authorization', true), ''
  ) <> 'b96d134f369c4bac0b89f7becbb02be0' then
    return;
  end if;

  for v_set in
    select product.tenant_id, product.id
    from public.products product
    where product.tenant_id = v_tenant_id
      and product.sku = any(v_target_skus)
      and coalesce(product.is_set, false)
      and exists (
        select 1 from public.product_set_components component
        where component.tenant_id = product.tenant_id
          and component.set_product_id = product.id
      )
    order by product.tenant_id, product.id
  loop
    perform public.refresh_product_set_purchase_list(v_set.tenant_id, v_set.id);
    perform public.request_parent_set_whatsapp_catalog_sync(
      v_set.tenant_id,
      v_set.id
    );
  end loop;

  if exists (
    select 1
    from public.smart_purchase_list list
    join public.products component
      on component.id = list.product_id and component.tenant_id = list.tenant_id
    join public.products set_product
      on set_product.id = component.parent_set_id
     and set_product.tenant_id = component.tenant_id
    where set_product.tenant_id = v_tenant_id
      and set_product.sku = any(v_target_skus)
      and component.parent_set_id is not null
      and list.status = 'pending'
      and coalesce(list.notes, '') like 'Auto-added:%'
  ) then
    raise exception 'Product-set cutover left duplicate automatic component purchase recommendations';
  end if;

  if exists (
    select 1
    from public.smart_purchase_list list
    join public.products set_product
      on set_product.id = list.product_id and set_product.tenant_id = list.tenant_id
    where set_product.tenant_id = v_tenant_id
      and set_product.sku = any(v_target_skus)
      and coalesce(set_product.is_set, false)
      and list.status in ('pending', 'ordered')
      and list.current_stock <> public.get_full_sets_count(set_product.id)
  ) then
    raise exception 'Product-set purchase recommendation availability is stale after cutover';
  end if;
end $$;

commit;
