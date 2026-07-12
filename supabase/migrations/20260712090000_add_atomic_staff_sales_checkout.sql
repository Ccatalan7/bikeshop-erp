-- Deployment status: DEPLOYED 2026-07-11. Additive and compatible with older clients.
-- New POS/Quick Sale clients use one transaction; legacy clients remain observable.
begin;

alter table public.sales_invoices
 add column if not exists checkout_idempotency_key text,
 add column if not exists checkout_payload_hash text,
 add column if not exists checkout_completed_at timestamptz;
create unique index if not exists uq_sales_invoice_checkout_key
 on public.sales_invoices(tenant_id,checkout_idempotency_key)
 where checkout_idempotency_key is not null;

create or replace function public.create_atomic_sales_checkout(
 p_source text,
 p_checkout_key text,
 p_customer_id uuid,
 p_customer_name text,
 p_customer_rut text,
 p_reference text,
 p_tax_treatment text,
 p_items jsonb,
 p_payments jsonb,
 p_sale_date timestamptz default now()
) returns jsonb language plpgsql security definer set search_path=public as $$
declare
 v_tenant uuid:=public.user_tenant_id();v_actor uuid:=auth.uid();v_source text:=lower(btrim(coalesce(p_source,'')));v_key text:=btrim(coalesce(p_checkout_key,''));
 v_hash text;v_existing public.sales_invoices%rowtype;v_invoice_id uuid:=gen_random_uuid();v_invoice_number text;v_items jsonb;v_total numeric;v_net numeric;v_tax numeric;
 v_payment_total numeric;v_payment record;v_operation uuid;v_customer_tenant uuid;
begin
 if v_actor is null or v_tenant is null then raise exception 'Authenticated employee tenant is required';end if;
 if v_source not in('pos','quick_sale')then raise exception 'Atomic checkout source must be pos or quick_sale';end if;
 if v_key=''or length(v_key)>128 then raise exception 'Checkout idempotency key is required and must be at most 128 characters';end if;
 if p_sale_date is null then raise exception 'Checkout date is required';end if;
 if p_tax_treatment not in('no_tax','tax_included')then raise exception 'Invalid checkout tax treatment';end if;
 if jsonb_typeof(p_items)<>'array'or jsonb_array_length(p_items)=0 then raise exception 'Checkout requires at least one item';end if;
 if jsonb_typeof(p_payments)<>'array'or jsonb_array_length(p_payments)=0 then raise exception 'Checkout requires at least one payment';end if;
 if p_customer_id is not null then
  select tenant_id into v_customer_tenant from public.customers where id=p_customer_id;
  if not found or v_customer_tenant<>v_tenant then raise exception 'Checkout customer not found for current tenant';end if;
 end if;
 v_hash:=md5(jsonb_build_object(
  'source',v_source,'customer_id',p_customer_id,'customer_name',btrim(coalesce(p_customer_name,'')),'customer_rut',btrim(coalesce(p_customer_rut,'')),
  'reference',btrim(coalesce(p_reference,'')),'tax_treatment',p_tax_treatment,'items',p_items,'payments',p_payments
 )::text);
 perform pg_advisory_xact_lock(hashtextextended(v_tenant::text||':'||v_source||':'||v_key,0));
 select * into v_existing from public.sales_invoices where tenant_id=v_tenant and checkout_idempotency_key=v_source||':'||v_key;
 if found then
  if v_existing.checkout_payload_hash is distinct from v_hash then raise exception 'Checkout key was already used with different sale content' using errcode='integrity_constraint_violation';end if;
  return jsonb_build_object('invoice_id',v_existing.id,'invoice_number',v_existing.invoice_number,'status',v_existing.status,'replayed',true);
 end if;

 create temporary table if not exists pg_temp.atomic_checkout_items(
  ord integer,product_id uuid,quantity numeric,unit_price numeric,discount numeric,primary key(product_id)
 )on commit drop;truncate pg_temp.atomic_checkout_items;
 insert into pg_temp.atomic_checkout_items(ord,product_id,quantity,unit_price,discount)
 select item.ordinality::integer,nullif(item.value->>'product_id','')::uuid,
  coalesce(nullif(item.value->>'quantity','')::numeric,0),
  coalesce(nullif(item.value->>'unit_price','')::numeric,0),coalesce(nullif(item.value->>'discount','')::numeric,0)
 from jsonb_array_elements(p_items)with ordinality item(value,ordinality);
 if exists(select 1 from pg_temp.atomic_checkout_items where product_id is null or quantity<=0 or unit_price<0 or discount<0 or quantity<>trunc(quantity) or unit_price<>public.clp_round(unit_price)or discount<>public.clp_round(discount)or discount>=quantity*unit_price)then
  raise exception 'Checkout items require a product, positive whole units, and valid whole-CLP prices';
 end if;
 if (select count(*)from pg_temp.atomic_checkout_items)<>jsonb_array_length(p_items)then raise exception 'Checkout cannot contain duplicate product lines';end if;
 if exists(select 1 from pg_temp.atomic_checkout_items request left join public.products product on product.id=request.product_id and product.tenant_id=v_tenant where product.id is null)then raise exception 'Checkout product not found for current tenant';end if;
 select jsonb_agg(jsonb_build_object(
  'line_id',gen_random_uuid(),'product_id',product.id,'product_name',product.name,'product_sku',product.sku,
  'quantity',request.quantity::integer,'unit_price',request.unit_price,'price',request.unit_price,'discount',request.discount,
  'line_total',request.quantity*request.unit_price-request.discount,'cost',coalesce(product.cost,0),
  'purchase_treatment',coalesce(product.purchase_treatment,'inventory'),'is_service',coalesce(product.is_service,false),'is_catalog_product',true
 )order by request.ord),public.clp_round(sum(request.quantity*request.unit_price-request.discount))
 into v_items,v_total
 from pg_temp.atomic_checkout_items request join public.products product on product.id=request.product_id and product.tenant_id=v_tenant;
 if v_total<=0 then raise exception 'Checkout total must be positive';end if;
 v_net:=case when p_tax_treatment='tax_included'then public.clp_round(v_total/1.19)else v_total end;v_tax:=v_total-v_net;

 create temporary table if not exists pg_temp.atomic_checkout_payments(ord integer,payment_method_id uuid,amount numeric,reference text,primary key(ord))on commit drop;truncate pg_temp.atomic_checkout_payments;
 insert into pg_temp.atomic_checkout_payments(ord,payment_method_id,amount,reference)
 select payment.ordinality::integer,nullif(payment.value->>'payment_method_id','')::uuid,coalesce(nullif(payment.value->>'amount','')::numeric,0),nullif(btrim(payment.value->>'reference'),'')
 from jsonb_array_elements(p_payments)with ordinality payment(value,ordinality);
 if exists(select 1 from pg_temp.atomic_checkout_payments where payment_method_id is null or amount<=0 or amount<>public.clp_round(amount))then raise exception 'Checkout payments must be positive whole CLP';end if;
 if exists(select 1 from pg_temp.atomic_checkout_payments payment left join public.payment_methods method on method.id=payment.payment_method_id and method.tenant_id=v_tenant and method.is_active where method.id is null)then raise exception 'Checkout payment method not found or inactive';end if;
 select public.clp_round(sum(amount))into v_payment_total from pg_temp.atomic_checkout_payments;
 if v_payment_total<>v_total then raise exception 'Checkout payment total must equal invoice total';end if;

 v_invoice_number:=public.get_next_document_number(v_tenant,'sales_invoice','FV');
 perform set_config('app.inventory_idempotency_key','staff_checkout:'||v_source||':'||v_key,true);
 insert into public.sales_invoices(
  id,tenant_id,invoice_number,customer_id,customer_name,customer_rut,date,due_date,reference,status,subtotal,net_amount,iva_amount,total,paid_amount,balance,tax_treatment,items,source,checkout_idempotency_key,checkout_payload_hash,created_by
 )values(
  v_invoice_id,v_tenant,v_invoice_number,p_customer_id,coalesce(nullif(btrim(p_customer_name),''),'Cliente Mostrador'),nullif(btrim(p_customer_rut),''),p_sale_date,p_sale_date,nullif(btrim(p_reference),''),'confirmed',v_total,v_net,v_tax,v_total,0,v_total,p_tax_treatment,v_items,v_source,v_source||':'||v_key,v_hash,v_actor
 );
 for v_payment in select * from pg_temp.atomic_checkout_payments order by ord loop
  insert into public.sales_payments(tenant_id,invoice_id,invoice_reference,payment_method_id,idempotency_key,amount,date,reference,tax_treatment,net_amount,iva_amount)
  values(v_tenant,v_invoice_id,v_invoice_number,v_payment.payment_method_id,format('staff_checkout:%s:%s:%s',v_source,v_key,v_payment.ord),v_payment.amount,p_sale_date,v_payment.reference,'no_tax',v_payment.amount,0);
 end loop;
 update public.sales_invoices set checkout_completed_at=clock_timestamp()where id=v_invoice_id;
 select id into v_operation from public.inventory_accounting_operations
 where tenant_id=v_tenant and document_type='sales_invoice'and document_id=v_invoice_id and source_channel=v_source
 order by created_at desc limit 1;
 if v_operation is not null then
  perform public.append_inventory_accounting_checkpoint(v_operation,'invariants_verified','completed','sales_invoice',v_invoice_id,jsonb_build_object('atomic_checkout',true,'source',v_source,'payment_total',v_payment_total,'invoice_total',v_total,'payment_count',jsonb_array_length(p_payments)));
 end if;
 return jsonb_build_object('invoice_id',v_invoice_id,'invoice_number',v_invoice_number,'status',(select status from public.sales_invoices where id=v_invoice_id),'replayed',false);
end;$$;

revoke all on function public.create_atomic_sales_checkout(text,text,uuid,text,text,text,text,jsonb,jsonb,timestamptz)from public,anon;
grant execute on function public.create_atomic_sales_checkout(text,text,uuid,text,text,text,text,jsonb,jsonb,timestamptz)to authenticated;
commit;
