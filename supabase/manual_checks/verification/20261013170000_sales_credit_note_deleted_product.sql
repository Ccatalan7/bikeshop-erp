-- Read-back de 20261013170000: la nota de crédito enlaza el producto sólo si
-- todavía existe, y el comando sigue siendo sólo de usuarios autenticados.

select 1 / case
  when pg_get_functiondef(
         'public.create_sales_credit_note(uuid,jsonb,timestamptz,text,text,text)'::regprocedure
       ) like '%product.id=work.product_id and product.tenant_id=v_tenant%'
   and has_function_privilege('authenticated', 'public.create_sales_credit_note(uuid,jsonb,timestamptz,text,text,text)', 'execute')
   and not has_function_privilege('anon', 'public.create_sales_credit_note(uuid,jsonb,timestamptz,text,text,text)', 'execute')
  then 1 else 0 end as sales_credit_note_deleted_product_ready;
