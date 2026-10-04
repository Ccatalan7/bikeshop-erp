-- Read-back of 20261003220000: deleting a customer with activity is refused
-- in the database. The BEFORE DELETE row trigger exists on customers and is
-- enabled; its function is security definer with a fixed search_path, lets a
-- cascade from another table through (pg_trigger_depth() > 1), checks the six
-- tables the customer foreign keys cascade to or orphan, raises
-- customer_has_activity with SQLSTATE 23503, and nobody can call it directly.
-- The customer_id foreign keys it relies on are still the ones it was written
-- for (mechanic_jobs.assigned_to also points at customers; it is not one).
-- Read-only; division by zero fails it.
select 1/(case when
 exists (select 1 from pg_trigger t
          where t.tgrelid = 'public.customers'::regclass
            and t.tgname = 'trg_guard_customer_delete_activity'
            and not t.tgisinternal and t.tgenabled = 'O'
            and t.tgfoid = 'public.guard_customer_delete_activity()'::regprocedure
            and pg_get_triggerdef(t.oid) like '%BEFORE DELETE ON public.customers FOR EACH ROW%')
 and (select p.prosecdef and p.proconfig @> array['search_path=public, pg_temp']
        from pg_proc p where p.oid = 'public.guard_customer_delete_activity()'::regprocedure)
 and (select bool_and(position(fragment in pg_get_functiondef(
                'public.guard_customer_delete_activity()'::regprocedure)) > 0)
        from unnest(array[
          'pg_trigger_depth() > 1',
          'public.bikes where customer_id = old.id',
          'public.mechanic_jobs where customer_id = old.id',
          'public.vehicles where customer_id = old.id',
          'public.sales_invoices where customer_id = old.id',
          'public.orders where customer_id = old.id',
          'public.online_orders where customer_id = old.id',
          'customer_has_activity',
          'errcode = ''23503''']) fragment)
 and not has_function_privilege('anon', 'public.guard_customer_delete_activity()', 'EXECUTE')
 and not has_function_privilege('authenticated', 'public.guard_customer_delete_activity()', 'EXECUTE')
 and (select count(*) from pg_constraint c
       join pg_attribute a on a.attrelid = c.conrelid and a.attnum = c.conkey[1]
       where c.contype = 'f' and c.confrelid = 'public.customers'::regclass
         and a.attname = 'customer_id' and c.confdeltype in ('c', 'n')
         and c.conrelid in ('public.bikes'::regclass, 'public.mechanic_jobs'::regclass,
                            'public.vehicles'::regclass, 'public.sales_invoices'::regclass,
                            'public.orders'::regclass, 'public.online_orders'::regclass)) = 6
 and (select count(*) from pg_constraint c
       join pg_attribute a on a.attrelid = c.conrelid and a.attnum = c.conkey[1]
       where c.contype = 'f' and c.confrelid = 'public.customers'::regclass
         and a.attname = 'customer_id' and c.confdeltype = 'a'
         and c.conrelid in ('public.sales_orders'::regclass, 'public.work_orders'::regclass)) = 2
then 1 else 0 end) as guard_customer_delete_activity_verified;
