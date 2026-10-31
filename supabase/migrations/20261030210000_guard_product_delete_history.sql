-- Borrar un producto no se lleva su historia (2026-10-30).
--
-- «Eliminar» en el inventario borraba la fila de products, y lo que dependía
-- de ella corría una de tres suertes:
-- * se borraba en cascada: stock_movements y stock_adjustments (el kardex);
-- * quedaba sin producto (SET NULL): las líneas de trabajos
--   (mechanic_job_items, también el servicio), de compras
--   (purchase_invoice_lines), de pedidos web (online_order_items) y la
--   historia de las bicis (bike_interventions, bike_component_lifecycles,
--   bike_observations);
-- * o la llave impedía el borrado y la app mostraba el error crudo: el
--   registro de IVA (product_tax_classification_events, 20260718220000) lo
--   tenían 1.607 de los 1.699 productos de Viñabike el 2026-10-30.
-- Las ventas guardan sus líneas en sales_invoices.items (JSON, sin llave): un
-- producto vendido se podía borrar y la factura quedaba apuntando a nada.
--
-- La regla va en la base, como la de los clientes (20261003220000):
-- * product_history_reasons_internal dice qué historia tiene un producto, con
--   las palabras que lee el operador.
-- * guard_product_delete_history, BEFORE DELETE, rechaza borrar un producto
--   con historia: product_has_history, SQLSTATE 23503 (el de las llaves que ya
--   lo impedían), y el detalle dice qué tiene. SECURITY DEFINER para que RLS
--   no esconda filas que la cascada sí ve. En las tablas con llave se busca
--   por product_id sin tenant_id, porque la cascada tampoco mira la empresa;
--   en el JSON de las facturas, dentro de la empresa del producto.
-- * Un borrado que llega en cascada desde otra tabla (borrar una empresa)
--   trae pg_trigger_depth() > 1 y pasa.
-- * delete_or_archive_product_v1 es lo que llama la app: borra un producto
--   sin historia y archiva el que la tiene (is_active = false, el «inactivo»
--   que la lista esconde salvo con «Incluir inactivos»). Devuelve cuál de las
--   dos hizo y por qué. Si otra llave lo retiene (una tabla que la lista no
--   nombra, como las fichas investigadas: 0 en Viñabike el 2026-10-30), el
--   error dice cuál y también lo archiva.
-- * En la base sólo la restauración heredada (restore_backup_legacy_rows_internal,
--   que la app ya no llama; usa restore_backup_merge) borra productos: borra
--   antes ventas, compras, trabajos, pedidos web, bicis y movimientos, y el
--   registro de IVA ya la detenía.

begin;

create or replace function public.product_history_reasons_internal(
  p_product_id uuid,
  p_tenant_id uuid
)
returns text[]
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select array_remove(array[
    case when exists (select 1 from public.stock_movements where product_id = p_product_id)
           or exists (select 1 from public.stock_adjustments where product_id = p_product_id)
           or exists (select 1 from public.inventory_adjustments where product_id = p_product_id)
           or exists (select 1 from public.product_import_stock_commands where product_id = p_product_id)
      then 'movimientos de stock' end,
    case when exists (
           select 1
             from public.sales_invoices
            where tenant_id = p_tenant_id
              and items @> jsonb_build_array(
                    jsonb_build_object('product_id', p_product_id::text)))
           or exists (select 1 from public.sales_order_items where product_id = p_product_id)
           or exists (select 1 from public.order_items where product_id = p_product_id)
           or exists (select 1 from public.sales_credit_note_lines where product_id = p_product_id)
           or exists (select 1 from public.sales_return_lines where product_id = p_product_id)
      then 'ventas' end,
    case when exists (select 1 from public.purchase_invoice_lines where product_id = p_product_id)
           or exists (
             select 1
               from public.purchase_invoices
              where tenant_id = p_tenant_id
                and items @> jsonb_build_array(
                      jsonb_build_object('product_id', p_product_id::text)))
           or exists (select 1 from public.purchase_order_items where product_id = p_product_id)
           or exists (select 1 from public.purchase_receipt_lines where product_id = p_product_id)
           or exists (select 1 from public.purchase_credit_note_lines where product_id = p_product_id)
           or exists (select 1 from public.purchase_supplier_return_lines where product_id = p_product_id)
           or exists (select 1 from public.purchase_plan_lines where product_id = p_product_id)
           or exists (select 1 from public.supply_needs where product_id = p_product_id)
      then 'compras' end,
    case when exists (
           select 1
             from public.mechanic_job_items
            where product_id = p_product_id
               or service_product_id = p_product_id)
           or exists (select 1 from public.work_order_items where product_id = p_product_id)
           or exists (select 1 from public.workshop_inventory_commitments where product_id = p_product_id)
      then 'trabajos' end,
    case when exists (select 1 from public.online_order_items where product_id = p_product_id)
           or exists (select 1 from public.online_order_inventory_reservations where product_id = p_product_id)
      then 'pedidos web' end,
    case when exists (
           select 1
             from public.bike_interventions
            where product_id = p_product_id
               or service_product_id = p_product_id)
           or exists (
             select 1
               from public.bike_component_lifecycles
              where product_id = p_product_id
                 or service_product_id = p_product_id)
           or exists (
             select 1
               from public.bike_observations
              where product_id = p_product_id
                 or service_product_id = p_product_id)
           or exists (
             select 1
               from public.wheel_builds
              where left_spoke_product_id = p_product_id
                 or right_spoke_product_id = p_product_id)
      then 'historia de bicis' end,
    case when exists (
           select 1
             from public.product_tax_classification_events
            where tenant_id = p_tenant_id
              and product_id = p_product_id)
      then 'registro de IVA' end
  ], null);
$$;

comment on function public.product_history_reasons_internal(uuid, uuid) is
  'Qué historia tiene un producto (movimientos de stock, ventas, compras, trabajos, pedidos web, historia de bicis, registro de IVA): la lee guard_product_delete_history y delete_or_archive_product_v1. Vacío = se puede borrar.';

revoke all on function public.product_history_reasons_internal(uuid, uuid)
  from public, anon, authenticated, service_role;

create or replace function public.guard_product_delete_history()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_found text[];
begin
  -- Borrar una empresa borra sus productos en cascada: eso no se detiene.
  if pg_trigger_depth() > 1 then
    return old;
  end if;

  v_found := public.product_history_reasons_internal(old.id, old.tenant_id);

  if cardinality(v_found) > 0 then
    raise exception 'product_has_history'
      using errcode = '23503',
            detail = format('El producto tiene %s.', array_to_string(v_found, ', ')),
            hint = 'Un producto con historia no se elimina: se archiva (queda inactivo) '
                   'y su historia se conserva.';
  end if;

  return old;
end;
$$;

comment on function public.guard_product_delete_history() is
  'Rechaza borrar un producto con historia (product_has_history, 23503): la cascada se llevaría su kardex y dejaría sin producto sus trabajos, compras, pedidos web y bicis. Deja pasar el borrado en cascada desde otra tabla (pg_trigger_depth() > 1).';

revoke all on function public.guard_product_delete_history()
  from public, anon, authenticated, service_role;

drop trigger if exists trg_guard_product_delete_history on public.products;
create trigger trg_guard_product_delete_history
  before delete on public.products
  for each row execute function public.guard_product_delete_history();

create or replace function public.delete_or_archive_product_v1(
  p_tenant_id uuid,
  p_product_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_reasons text[];
  v_table text;
begin
  if p_tenant_id is null or p_product_id is null then
    raise exception 'product_reference_required' using errcode = '22023';
  end if;

  if p_tenant_id is distinct from public.user_tenant_id() then
    raise exception 'Product not found or not accessible' using errcode = '42501';
  end if;

  -- The row lock makes a new child row wait (its key asks FOR KEY SHARE), so
  -- the history read below is the one the delete sees.
  perform 1
    from public.products
   where tenant_id = p_tenant_id
     and id = p_product_id
     for update;
  if not found then
    raise exception 'Product not found or not accessible' using errcode = 'P0002';
  end if;

  v_reasons := public.product_history_reasons_internal(p_product_id, p_tenant_id);

  if cardinality(v_reasons) = 0 then
    begin
      delete from public.products
       where tenant_id = p_tenant_id
         and id = p_product_id;
      return jsonb_build_object('outcome', 'deleted', 'reasons', '[]'::jsonb);
    exception
      when foreign_key_violation then
        -- Another key keeps it: a table the list does not name (the error
        -- names it), or a sale written since the read.
        get stacked diagnostics v_table = table_name;
        v_reasons := coalesce(
          nullif(public.product_history_reasons_internal(p_product_id, p_tenant_id), '{}'::text[]),
          array[case
            when v_table like 'sales\_%' or v_table = 'order_items' then 'ventas'
            when v_table like 'purchase\_%' or v_table like 'supply\_%'
              or v_table like 'supplier\_%' then 'compras'
            when v_table like 'workshop\_%' or v_table like 'work\_order%' then 'trabajos'
            when v_table like 'online\_order%' then 'pedidos web'
            when v_table like 'product\_spec\_%' then 'ficha técnica'
            when v_table like 'product\_import%' then 'movimientos de stock'
            else 'otros registros'
          end]
        );
    end;
  end if;

  update public.products
     set is_active = false,
         updated_at = now()
   where tenant_id = p_tenant_id
     and id = p_product_id;

  return jsonb_build_object('outcome', 'archived', 'reasons', to_jsonb(v_reasons));
end;
$$;

comment on function public.delete_or_archive_product_v1(uuid, uuid) is
  'Eliminar un producto desde la app: lo borra si no tiene historia y si la tiene lo archiva (is_active = false). Devuelve {outcome: deleted|archived, reasons: [...]} con las palabras de product_history_reasons_internal.';

revoke all on function public.delete_or_archive_product_v1(uuid, uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.delete_or_archive_product_v1(uuid, uuid)
  to authenticated;

commit;
