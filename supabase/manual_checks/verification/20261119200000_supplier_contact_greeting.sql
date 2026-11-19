-- Read-back de 20261119200000_supplier_contact_greeting.
-- Sólo `select` planos: la lectura remota corre el archivo en una sola
-- transacción de sólo lectura, y cada uno revienta si falta la definición o
-- si el invariante no se cumple. No se imprime ningún nombre de contacto.

-- 1. Las dos columnas, con el primer nombre por defecto.
select 1 / (count(*) = 2)::int as columnas_del_saludo
  from information_schema.columns c
 where c.table_schema = 'public'
   and c.table_name = 'supplier_contacts'
   and (
     (c.column_name = 'greeting_style'
      and c.is_nullable = 'NO'
      and c.column_default like '''first_name''%')
     or (c.column_name = 'greeting_custom_name' and c.is_nullable = 'YES')
   );

-- 2. Las tres reglas de la tabla, validadas.
select 1 / (count(*) = 3)::int as reglas_del_saludo
  from pg_catalog.pg_constraint con
 where con.conrelid = 'public.supplier_contacts'::regclass
   and con.convalidated
   and con.conname in (
     'supplier_contacts_greeting_style_known',
     'supplier_contacts_greeting_custom_name_shape',
     'supplier_contacts_greeting_custom_matches_style'
   );

-- 3. Cada contacto que ya existía quedó con un saludo válido; el personalizado
--    sólo con su texto.
select 1 / (
  count(*) > 0
  and count(*) filter (
    where greeting_style in ('first_name', 'two_names', 'custom')
      and (greeting_style = 'custom') = (greeting_custom_name is not null)
  ) = count(*)
)::int as contactos_con_saludo
  from public.supplier_contacts;

-- 4. El comando que guarda acepta y conserva el saludo, y el contacto que
--    devuelve lo trae.
select 1 / (count(*) = 1)::int as guardar_con_saludo
  from pg_catalog.pg_proc p
 where p.oid = to_regprocedure(
         'public.save_supplier_contact(uuid,uuid,uuid,timestamptz,uuid,jsonb)'
       )
   and p.prosecdef
   and array_to_string(p.proconfig, ',') like '%search_path=pg_catalog, public, pg_temp%'
   and pg_get_functiondef(p.oid) like '%''greeting_custom_name''%'
   and pg_get_functiondef(p.oid) like '%v_existing.greeting_style%';

select 1 / (count(*) = 1)::int as contacto_trae_saludo
  from pg_catalog.pg_proc p
 where p.oid = to_regprocedure('public.supplier_contact_json(public.supplier_contacts)')
   and pg_get_functiondef(p.oid) like '%''greeting_style'', p_contact.greeting_style%';

-- 5. Sigue siendo sólo para una sesión del ERP.
select 1 / (
  has_function_privilege(
    'authenticated',
    'public.save_supplier_contact(uuid,uuid,uuid,timestamptz,uuid,jsonb)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'anon',
    'public.save_supplier_contact(uuid,uuid,uuid,timestamptz,uuid,jsonb)',
    'EXECUTE'
  )
)::int as solo_con_sesion;
