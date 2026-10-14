-- Read-back de 20260727235900: la ficha propia del trabajador existe, la llama
-- sólo un usuario con sesión y corre como su dueño con search_path fijo.

select 1 / case
  when exists (
    select 1
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public'
       and p.proname = 'get_my_employee_self_service'
       and p.prosecdef
       and p.provolatile = 's'
       and array_to_string(p.proconfig, ',') like '%search_path=%'
  )
   and has_function_privilege('authenticated', 'public.get_my_employee_self_service(date)', 'execute')
   and not has_function_privilege('anon', 'public.get_my_employee_self_service(date)', 'execute')
  then 1 else 0
end as assert_self_service_function_and_grants;
