-- Read-back for 20261006090000_public_checkout_processes_signed_in_transfer:
-- the checkout processes its own order through the internal function, no API
-- role can call that function, and the ERP entry point keeps its guard.
select 1 / case
  when pg_get_functiondef(
         'public.create_public_online_order_unkeyed(jsonb, jsonb)'::regprocedure
       ) like '%perform public.process_public_checkout_order(v_order_id, v_tenant_id);%'
   and pg_get_functiondef(
         'public.create_public_online_order_unkeyed(jsonb, jsonb)'::regprocedure
       ) not like '%perform public.process_online_order(v_order_id);%'
  then 1 else 0
end as assert_checkout_uses_internal_processor;

select 1 / case
  when not has_function_privilege(
         'anon', 'public.process_public_checkout_order(uuid, uuid)', 'EXECUTE')
   and not has_function_privilege(
         'authenticated', 'public.process_public_checkout_order(uuid, uuid)', 'EXECUTE')
   and not has_function_privilege(
         'service_role', 'public.process_public_checkout_order(uuid, uuid)', 'EXECUTE')
  then 1 else 0
end as assert_internal_processor_has_no_api_role;

select 1 / case
  when pg_get_functiondef('public.process_online_order(uuid)'::regprocedure)
       like '%v_tenant_id is distinct from public.user_tenant_id()%'
  then 1 else 0
end as assert_erp_processor_keeps_staff_guard;

select 1 / case
  when not has_function_privilege(
         'anon', 'public.create_public_online_order_unkeyed(jsonb, jsonb)', 'EXECUTE')
   and not has_function_privilege(
         'authenticated', 'public.create_public_online_order_unkeyed(jsonb, jsonb)', 'EXECUTE')
  then 1 else 0
end as assert_unkeyed_checkout_stays_private;
