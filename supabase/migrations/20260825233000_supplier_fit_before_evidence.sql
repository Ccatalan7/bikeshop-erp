-- El paso Proveedores compara primero el calce y después la procedencia.
--
-- Un producto exacto de catálogo puede conservar proveedor y costo aunque la
-- migración desde Zoho no haya traído su factura. Ese costo es utilizable como
-- referencia, pero nunca se convierte en costo pagado o aterrizado. Esta
-- migración lo transporta y lo congela en el snapshot del plan sin sumarlo al
-- subtotal histórico.

begin;

set local lock_timeout = '750ms';
set local statement_timeout = '30s';

-- v2 sigue disponible para clientes instalados. v3 agrega sólo claves por
-- producto; no cambia ninguna conclusión de stock ni de evidencia comercial.
create or replace function public.get_supply_need_stock_resolution_v3(
  p_need_id uuid,
  p_limit integer default 12,
  p_offset integer default 0
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, extensions, pg_temp
set statement_timeout = '9000ms'
as $$
declare
  v_tenant_id uuid := public.user_tenant_id();
  v_base jsonb;
  v_items jsonb;
begin
  if v_tenant_id is null then
    raise exception 'No tenant context' using errcode = '42501';
  end if;

  v_base := public.get_supply_need_stock_resolution_v2(
    p_need_id, p_limit, p_offset
  );

  select coalesce(jsonb_agg(
      item.value || jsonb_strip_nulls(jsonb_build_object(
        'catalogCostNet', case
          when product.cost > 0 then product.cost
          else null
        end,
        'catalogCostCurrency', case when product.cost > 0 then
          coalesce(nullif(upper(product.cost_currency), ''), 'CLP')
        else null end,
        'catalogProductUpdatedAt', product.updated_at,
        'supplierCode', case
          when product.supplier_id = evidence_supplier.supplier_id
            then coalesce(
              nullif(btrim(product.supplier_code), ''),
              evidence_supplier.supplier_code
            )
          else evidence_supplier.supplier_code
        end,
        'automaticAvailabilityEnabled', exists (
          select 1
          from public.supplier_portal_probes probe
          where probe.tenant_id = v_tenant_id
            and probe.supplier_id = evidence_supplier.supplier_id
            and probe.is_enabled is true
            and probe.search_url_template like '%{code}%'
        )
      ))
      order by item.ordinality
    ), '[]'::jsonb)
  into v_items
  from jsonb_array_elements(coalesce(v_base -> 'items', '[]'::jsonb))
    with ordinality item(value, ordinality)
  join public.products product
    on product.tenant_id = v_tenant_id
   and product.id = (item.value ->> 'productId')::uuid
  left join lateral (
    select
      nullif(item.value ->> 'supplierId', '')::uuid as supplier_id,
      (
        select nullif(btrim(check_row.supplier_code), '')
        from public.supplier_availability_checks check_row
        where check_row.tenant_id = v_tenant_id
          and check_row.product_id = product.id
          and check_row.supplier_id =
            nullif(item.value ->> 'supplierId', '')::uuid
          and nullif(btrim(check_row.supplier_code), '') is not null
        order by check_row.checked_at desc, check_row.id desc
        limit 1
      ) as supplier_code
  ) evidence_supplier on true;

  return jsonb_set(v_base, '{items}', v_items, true);
end;
$$;

revoke all on function public.get_supply_need_stock_resolution_v3(
  uuid, integer, integer
) from public, anon, authenticated, service_role;
grant execute on function public.get_supply_need_stock_resolution_v3(
  uuid, integer, integer
) to authenticated;

-- El snapshot conserva la referencia mutable que existía al tomar la
-- decisión. landed_unit_cost_net permanece nulo: una ficha no es una factura.
create or replace function public.purchase_plan_line_catalog_reference_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, extensions, pg_temp
as $$
declare
  v_product public.products%rowtype;
begin
  if new.candidate_id is not null
     or new.product_id is null
     or new.evidence_state not in (
       'fresh_supplier_check', 'catalog_assignment', 'no_erp_history'
     ) then
    return new;
  end if;

  select product.* into v_product
  from public.products product
  where product.tenant_id = new.tenant_id
    and product.id = new.product_id;

  if found then
    new.evidence_snapshot := coalesce(new.evidence_snapshot, '{}'::jsonb)
      || jsonb_strip_nulls(jsonb_build_object(
        'catalog_cost_net', case
          when v_product.cost > 0 then v_product.cost
          else null
        end,
        'catalog_cost_currency', case when v_product.cost > 0 then
          coalesce(nullif(upper(v_product.cost_currency), ''), 'CLP')
        else null end,
        'catalog_product_updated_at', v_product.updated_at,
        'supplier_code', nullif(btrim(v_product.supplier_code), '')
      ));
  end if;
  return new;
end;
$$;

revoke all on function public.purchase_plan_line_catalog_reference_v1()
  from public, anon, authenticated, service_role;

drop trigger if exists trg_purchase_plan_line_catalog_reference
  on public.purchase_plan_lines;
create trigger trg_purchase_plan_line_catalog_reference
  before insert or update of candidate_id, product_id, evidence_state,
    evidence_snapshot
  on public.purchase_plan_lines
  for each row execute function
    public.purchase_plan_line_catalog_reference_v1();

-- Planes borrador creados por la entrega anterior reciben la misma referencia
-- congelada. No se toca ninguna línea con candidato/factura real.
update public.purchase_plan_lines line
set evidence_snapshot = coalesce(line.evidence_snapshot, '{}'::jsonb)
  || jsonb_strip_nulls(jsonb_build_object(
    'catalog_cost_net', case
      when product.cost > 0 then product.cost
      else null
    end,
    'catalog_cost_currency', case when product.cost > 0 then
      coalesce(nullif(upper(product.cost_currency), ''), 'CLP')
    else null end,
    'catalog_product_updated_at', product.updated_at,
    'supplier_code', nullif(btrim(product.supplier_code), '')
  )),
  updated_at = clock_timestamp()
from public.products product
where line.tenant_id = product.tenant_id
  and line.product_id = product.id
  and line.candidate_id is null
  and line.evidence_state in (
    'fresh_supplier_check', 'catalog_assignment', 'no_erp_history'
  )
  and (
    product.cost > 0
    or nullif(btrim(product.supplier_code), '') is not null
  )
  and (
    line.evidence_snapshot ->> 'catalog_cost_net' is distinct from
      case when product.cost > 0 then product.cost::text else null end
    or line.evidence_snapshot ->> 'catalog_cost_currency' is distinct from
      case when product.cost > 0 then
        coalesce(nullif(upper(product.cost_currency), ''), 'CLP')
      else null end
    or line.evidence_snapshot ->> 'catalog_product_updated_at' is distinct from
      product.updated_at::text
    or line.evidence_snapshot ->> 'supplier_code' is distinct from
      nullif(btrim(product.supplier_code), '')
  );

comment on function public.get_supply_need_stock_resolution_v3(
  uuid, integer, integer
) is
  'Stock-first resolution plus labelled catalog cost and exact-product portal capability; catalog cost is not purchase evidence.';

comment on function public.purchase_plan_line_catalog_reference_v1() is
  'Freezes catalog cost metadata in no-history plan snapshots without populating landed cost or historical economics.';

commit;
