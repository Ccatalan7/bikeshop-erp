-- Lo que no se ofrece sin stock no se pide más allá del stock (dueño,
-- 2026-11-03; la regla es 20261103070000). Se despliega junto con la tienda
-- que ya dice qué se cotiza: la de la 1.0.45 ofrecía «Cotízalo a pedido» en
-- todo agotado y el cliente recién se enteraría al enviar.

begin;

set local lock_timeout = '750ms';
set local statement_timeout = '30s';

-- ---------------------------------------------------------------------------
-- La solicitud no acepta, más allá del stock, lo que no se ofrece
-- ---------------------------------------------------------------------------

-- Igual que en 20261102041700, más la regla: en el sitio, lo que falta de un
-- producto que no se ofrece sin stock se rechaza con el mismo código que un
-- producto que el sitio ya no muestra (la página de la cotización publicada
-- en la 1.0.45 ya lo explica y vuelve a leer la lista). El equipo, en el ERP,
-- cotiza lo que quiera.
create or replace function public.customer_quote_insert_lines_internal(
  p_quote_id uuid,
  p_items jsonb,
  p_web_rule boolean
)
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_quote public.customer_quotes%rowtype;
  v_policy jsonb;
  v_item record;
  v_product public.products%rowtype;
  v_terms public.product_on_order_terms%rowtype;
  v_line_no smallint := 0;
  v_kind text;
  v_available integer;
begin
  select * into v_quote from public.customer_quotes where id = p_quote_id;
  if p_items is null or jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then
    raise exception 'quote_items_required' using errcode = '22023';
  end if;
  v_policy := public.catalog_web_policy_v1(v_quote.tenant_id);

  for v_item in
    select (e ->> 'product_id')::uuid as product_id,
           sum(greatest(1, least(99, coalesce((e ->> 'quantity')::integer, 1))))::integer as quantity,
           min(ord) as first_ord
      from jsonb_array_elements(p_items) with ordinality as x(e, ord)
     group by 1
     order by 3
  loop
    if v_line_no >= 50 then
      raise exception 'quote_too_many_items' using errcode = '22023';
    end if;
    select * into v_product from public.products p
     where p.id = v_item.product_id and p.tenant_id = v_quote.tenant_id;
    if not found
       or coalesce(v_product.product_type, 'product') = 'service'
       or (p_web_rule and public.catalog_product_web_block_v1(v_product, v_policy) is not null) then
      raise exception 'quote_product_not_available' using errcode = '22023',
        detail = coalesce(v_item.product_id::text, '');
    end if;
    select * into v_terms from public.product_on_order_terms t
     where t.product_id = v_product.id and t.is_active;
    v_available := coalesce(public.customer_quote_available_stock_internal(v_quote.tenant_id, v_product.id), 0);
    if p_web_rule
       and v_available < least(v_item.quantity, 99)
       and public.customer_quote_sold_out_mode_internal(
             v_quote.tenant_id, v_product.id, v_product.brand_id) = 'none' then
      raise exception 'quote_product_not_available' using errcode = '22023',
        detail = v_product.id::text,
        hint = 'not_offered_sold_out';
    end if;
    v_kind := case
      when v_available >= least(v_item.quantity, 99) then 'in_stock'
      when v_terms.product_id is not null then 'on_order'
      else 'to_confirm'
    end;
    v_line_no := v_line_no + 1;
    insert into public.customer_quote_lines (
      tenant_id, quote_id, line_no, product_id, product_sku, product_name, quantity,
      stock_at_request, kind_at_request, unit_price_reference
    ) values (
      v_quote.tenant_id, p_quote_id, v_line_no, v_product.id, v_product.sku,
      coalesce(nullif(btrim(v_product.website_name), ''), v_product.name),
      least(v_item.quantity, 99), v_available, v_kind,
      public.customer_quote_public_price_internal(v_product)
    );
  end loop;
  return v_line_no;
end;
$$;

revoke all on function public.customer_quote_insert_lines_internal(uuid, jsonb, boolean)
  from public, anon, authenticated, service_role;

commit;
