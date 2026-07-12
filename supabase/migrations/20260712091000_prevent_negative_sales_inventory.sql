-- Deployment status: DEPLOYED 2026-07-11. Prevents all posted sales channels from overselling.
begin;

create or replace function public.sales_invoice_stock_requirements(p_tenant_id uuid,p_items jsonb)
returns table(product_id uuid,quantity integer)
language sql stable security definer set search_path=public as $$
with requested as(
 select
  coalesce(direct.id,sku_product.id)product_id,
  coalesce(nullif(item.value->>'quantity','')::numeric,0)quantity,
  coalesce(nullif(item.value->>'purchase_treatment',''),'inventory')purchase_treatment
 from jsonb_array_elements(coalesce(p_items,'[]'::jsonb))item(value)
 left join public.products direct on direct.id=nullif(item.value->>'product_id','')::uuid and direct.tenant_id=p_tenant_id
 left join public.products sku_product on direct.id is null and sku_product.tenant_id=p_tenant_id and sku_product.sku=nullif(item.value->>'product_sku','')
),targets as(
 select product.id product_id,requested.quantity::integer quantity
 from requested join public.products product on product.id=requested.product_id and product.tenant_id=p_tenant_id
 where requested.quantity>0 and requested.quantity=trunc(requested.quantity)and requested.purchase_treatment<>'workshop_consumable'
  and not coalesce(product.is_service,false)and coalesce(product.track_stock,true)and not coalesce(product.is_set,false)
 union all
 select component.component_product_id,requested.quantity::integer*component.quantity_in_set
 from requested join public.products product on product.id=requested.product_id and product.tenant_id=p_tenant_id
 join public.product_set_components component on component.tenant_id=p_tenant_id and component.set_product_id=product.id
 where requested.quantity>0 and requested.quantity=trunc(requested.quantity)and requested.purchase_treatment<>'workshop_consumable'
  and not coalesce(product.is_service,false)and coalesce(product.track_stock,true)and coalesce(product.is_set,false)
)
select targets.product_id,sum(targets.quantity)::integer from targets group by targets.product_id;
$$;

create or replace function public.validate_sales_invoice_stock_before_posting()
returns trigger language plpgsql security definer set search_path=public as $$
declare
 v_non_posted constant text[]:=array['draft','borrador','sent','enviado','enviada','issued','emitido','emitida','cancelled','cancelado','cancelada','anulado','anulada'];
 v_old_posted boolean:=false;v_new_posted boolean;v_requirement record;v_product public.products%rowtype;
begin
 v_new_posted:=not(lower(coalesce(new.status,'draft'))=any(v_non_posted));
 if tg_op='UPDATE'then v_old_posted:=not(lower(coalesce(old.status,'draft'))=any(v_non_posted));end if;
 if not v_new_posted then return new;end if;
 -- Payment/status recalculation on an already-posted unchanged snapshot has no
 -- inventory delta. It must remain compatible with legacy line metadata.
 if tg_op='UPDATE'and v_old_posted and v_new_posted
  and public.invoice_inventory_signature(old.items)=public.invoice_inventory_signature(new.items)then return new;end if;
 if exists(
  select 1 from jsonb_array_elements(coalesce(new.items,'[]'::jsonb))item(value)
  where nullif(item.value->>'product_id','')is not null
   and not exists(select 1 from public.products product where product.id=nullif(item.value->>'product_id','')::uuid and product.tenant_id=new.tenant_id)
 )then raise exception 'Sales invoice contains a product outside the current tenant';end if;
 if exists(
  select 1 from jsonb_array_elements(coalesce(new.items,'[]'::jsonb))item(value)
  join public.products product on product.id=nullif(item.value->>'product_id','')::uuid and product.tenant_id=new.tenant_id
  where not coalesce(product.is_service,false)and coalesce(product.track_stock,true)
   and coalesce(nullif(item.value->>'purchase_treatment',''),'inventory')<>'workshop_consumable'
   and coalesce(nullif(item.value->>'quantity','')::numeric,0)<>trunc(coalesce(nullif(item.value->>'quantity','')::numeric,0))
 )then raise exception 'Tracked sales invoice quantities must be whole units';end if;
 for v_requirement in
  with new_requirements as(select * from public.sales_invoice_stock_requirements(new.tenant_id,new.items)),
  old_requirements as(select * from public.sales_invoice_stock_requirements(new.tenant_id,case when v_old_posted then old.items else'[]'::jsonb end)),
  deltas as(
   select coalesce(new_req.product_id,old_req.product_id)product_id,coalesce(new_req.quantity,0)-coalesce(old_req.quantity,0)quantity
   from new_requirements new_req full join old_requirements old_req using(product_id)
  )select * from deltas where quantity>0 order by product_id
 loop
  select * into v_product from public.products where id=v_requirement.product_id and tenant_id=new.tenant_id for update;
  if not found then raise exception 'Sales invoice stock product not found for current tenant';end if;
  if coalesce(v_product.inventory_qty,0)<>coalesce(v_product.stock_quantity,0)then raise exception 'Product stock columns disagree; sales posting blocked for %',v_product.name;end if;
  if coalesce(v_product.inventory_qty,0)<v_requirement.quantity then
   raise exception 'Insufficient stock for product %: available %, required additional %',v_product.name,coalesce(v_product.inventory_qty,0),v_requirement.quantity;
  end if;
 end loop;
 return new;
end;$$;

drop trigger if exists trg_validate_sales_invoice_stock_before_posting on public.sales_invoices;
create trigger trg_validate_sales_invoice_stock_before_posting
before insert or update on public.sales_invoices
for each row execute function public.validate_sales_invoice_stock_before_posting();
commit;
