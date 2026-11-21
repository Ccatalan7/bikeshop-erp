-- Read-back de 20261121200000_customer_greeting.
-- Sólo `select` planos: la lectura remota corre el archivo en una sola
-- transacción de sólo lectura, y cada uno revienta si falta la definición o
-- si el invariante no se cumple. No se imprime ningún nombre de cliente.

-- 1. Las dos columnas, con el primer nombre por defecto.
select 1 / (count(*) = 2)::int as columnas_del_saludo
  from information_schema.columns c
 where c.table_schema = 'public'
   and c.table_name = 'customers'
   and (
     (c.column_name = 'greeting_style'
      and c.is_nullable = 'NO'
      and c.column_default like '''first_name''%')
     or (c.column_name = 'greeting_custom_name' and c.is_nullable = 'YES')
   );

-- 2. Las tres reglas de la tabla, validadas.
select 1 / (count(*) = 3)::int as reglas_del_saludo
  from pg_catalog.pg_constraint con
 where con.conrelid = 'public.customers'::regclass
   and con.convalidated
   and con.conname in (
     'customers_greeting_style_known',
     'customers_greeting_custom_name_shape',
     'customers_greeting_custom_matches_style'
   );

-- 3. Cada cliente quedó con un saludo válido, y los nombres compuestos que
--    los avisos ya saludaban enteros quedaron con dos nombres.
select 1 / (
  count(*) > 0
  and count(*) filter (
    where greeting_style in ('first_name', 'two_names', 'second_name', 'full_name', 'custom')
      and (greeting_style = 'custom') = (greeting_custom_name is not null)
  ) = count(*)
  and count(*) filter (where greeting_style = 'two_names') > 0
)::int as clientes_con_saludo
  from public.customers;

-- 4. La regla, con los casos de la app.
select 1 / (
  public.contact_greeting_name_internal('MARÍA JOSÉ LARA', 'two_names', null) = 'María José'
  and public.contact_greeting_name_internal('Inés de los Ángeles Mora', 'second_name', null) = 'Ángeles'
  and public.contact_greeting_name_internal('ana de la fuente', 'full_name', null) = 'Ana de la Fuente'
  and public.contact_greeting_name_internal('Pedro Soto', 'custom', ' Don   Pedro ') = 'Don Pedro'
  and public.contact_greeting_name_internal('Pedro Soto', 'custom', '') = 'Pedro'
  and public.contact_greeting_name_internal(' ', 'first_name', null) is null
)::int as regla_del_saludo;

-- 5. «Mi cuenta»: el comando es de la cuenta, nunca de un visitante, y la
--    guardia de la ficha deja cambiar el saludo.
select 1 / (count(*) = 1)::int as comando_de_la_cuenta
  from pg_catalog.pg_proc p
 where p.oid = to_regprocedure('public.set_my_customer_greeting_v1(uuid,text,text)')
   and p.prosecdef
   and has_function_privilege('authenticated', p.oid, 'execute')
   and not has_function_privilege('anon', p.oid, 'execute');

select 1 / (count(*) = 1)::int as guardia_deja_el_saludo
  from pg_catalog.pg_proc p
 where p.oid = to_regprocedure('public.guard_customer_identity_update()')
   and pg_get_functiondef(p.oid) like '%''greeting_custom_name''%'
   and pg_get_functiondef(p.oid) like '%Customer self-service may update profile fields only%';

select 1 / (count(*) = 1)::int as columna_calculada
  from pg_catalog.pg_proc p
 where p.oid = to_regprocedure('public.greeting_name(public.customers)')
   and has_function_privilege('authenticated', p.oid, 'execute');

-- 6. Lo que sale del servidor saluda con lo elegido.
select 1 / (
  pg_get_functiondef('public.workshop_notice_dispatch_whatsapp_internal'::regproc)
    like '%customer_greeting_internal(v_customer)%greeting_name_source%'
  and pg_get_functiondef('public.process_whatsapp_review_requests_v1'::regproc)
    like '%customer_greeting_style%greeting_name_source%'
  and pg_get_functiondef('public.workshop_notice_email_payload_internal'::regproc)
    like '%customerGreeting%'
  and pg_get_functiondef('public.customer_quote_email_payload_internal'::regproc)
    like '%customerGreeting%'
  and pg_get_functiondef('public.transactional_email_render_payload'::regproc)
    like '%customer_greeting_for_internal%'
)::int as mensajes_con_saludo;

select 1 / (count(*) = 0)::int as nadie_saluda_con_la_primera_palabra
  from pg_catalog.pg_proc p
  join pg_catalog.pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public'
   and p.prokind = 'f'
   and p.proname <> 'customer_first_name_internal'
   and p.prosrc like '%customer_first_name_internal%';
