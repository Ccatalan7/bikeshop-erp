-- Read-back de `20260903103000_supplier_contacts`.
-- Cada bloque divide por cero si lo que afirma no está: corrido ANTES de la
-- migración tiene que fallar; después, pasar.

-- 1. La tabla existe con RLS, authenticated la lee y no la escribe.
select 1 / (
  case when count(*) = 1 then 1 else 0 end
) as la_tabla_existe_con_rls
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public'
  and c.relname = 'supplier_contacts'
  and c.relrowsecurity;

select 1 / (
  case when has_table_privilege('authenticated', 'public.supplier_contacts', 'SELECT')
        and not has_table_privilege('authenticated', 'public.supplier_contacts', 'INSERT')
        and not has_table_privilege('authenticated', 'public.supplier_contacts', 'UPDATE')
        and not has_table_privilege('authenticated', 'public.supplier_contacts', 'DELETE')
    then 1 else 0 end
) as authenticated_lee_y_no_escribe;

-- 2. Un solo principal por proveedor y un número por proveedor, por índice.
select 1 / (
  case when count(*) = 2 then 1 else 0 end
) as los_dos_indices_unicos
from pg_indexes
where schemaname = 'public'
  and tablename = 'supplier_contacts'
  and indexname in (
    'supplier_contacts_one_primary_per_supplier',
    'supplier_contacts_phone_per_supplier'
  );

-- 3. Los tres comandos existen, son security definer y sólo authenticated y
--    service_role los ejecutan.
select 1 / (
  case when count(*) = 3 then 1 else 0 end
) as los_comandos_existen
from pg_proc p
where p.oid in (
  to_regprocedure('public.save_supplier_contact(uuid,uuid,uuid,timestamptz,uuid,jsonb)'),
  to_regprocedure('public.set_supplier_contact_status(uuid,uuid,uuid,timestamptz,uuid,boolean)'),
  to_regprocedure('public.update_supplier_sales_rep(uuid,uuid,timestamptz,uuid,jsonb)')
)
  and p.prosecdef;

select 1 / (
  case when count(*) = 0 then 1 else 0 end
) as anon_y_public_no_los_ejecutan
from information_schema.role_routine_grants
where routine_schema = 'public'
  and routine_name in ('save_supplier_contact', 'set_supplier_contact_status')
  and grantee in ('anon', 'PUBLIC');

-- 4. El vendedor de la ficha escribe a través de los contactos.
select 1 / (
  case when count(*) = 1 then 1 else 0 end
) as el_vendedor_escribe_por_contactos
from pg_proc p
where p.oid = to_regprocedure(
  'public.update_supplier_sales_rep(uuid,uuid,timestamptz,uuid,jsonb)'
)
  and pg_get_functiondef(p.oid) like '%insert into public.supplier_contacts%'
  and pg_get_functiondef(p.oid) not like '%set sales_rep_name = v_name%';

-- 5. Los tres triggers de vínculo y el de proyección están puestos.
select 1 / (
  case when count(*) = 4 then 1 else 0 end
) as los_triggers_estan
from pg_trigger
where tgname in (
  'trg_supplier_contacts_project_primary',
  'trg_whatsapp_bindings_link_supplier_contact',
  'trg_conversations_relink_supplier_contact',
  'trg_supplier_contacts_link_bindings'
)
  and not tgisinternal;

-- 6. Invariante de negocio: la ficha de cada proveedor dice lo mismo que su
--    contacto principal, y ningún proveedor con vendedor quedó sin principal.
select 1 / (
  case when count(*) = 0 then 1 else 0 end
) as ficha_y_principal_coinciden
from public.suppliers supplier
left join public.supplier_contacts contact
  on contact.supplier_id = supplier.id
 and contact.is_primary
 and contact.is_active
where supplier.sales_rep_name is distinct from contact.name
   or supplier.sales_rep_phone is distinct from contact.phone
   or supplier.sales_rep_email is distinct from contact.email;

-- 7. Todo hilo de proveedor cuyo número es de un contacto está atado a él.
select 1 / (
  case when count(*) = 0 then 1 else 0 end
) as hilos_de_proveedor_atados
from public.whatsapp_conversation_bindings binding
where binding.supplier_contact_id is null
  and binding.external_phone_number is not null
  and exists (
    select 1
    from public.supplier_contacts contact
    where contact.supplier_id = public.conversation_supplier_id(binding.conversation_id)
      and contact.phone_digits is not null
      and public.phone_digits_match(contact.phone_digits, binding.external_phone_number)
  );
