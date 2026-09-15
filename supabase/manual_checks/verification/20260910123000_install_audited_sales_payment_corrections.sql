-- Pure SELECT read-back for 20260910123000_install_audited_sales_payment_corrections.
-- Every statement divides by zero when the expected live state is absent.

-- 1. Every object the client calls or the guard relies on exists.
select 1/(case when
     to_regclass('public.sales_payment_edit_events') is not null
 and to_regprocedure('public.guard_sales_payment_edit_event()') is not null
 and to_regprocedure('public.guard_sales_payment_correction_command()') is not null
 and to_regprocedure('public.get_sales_payment_edit_operation(text)') is not null
 and to_regprocedure('public.correct_sales_payment(uuid,timestamptz,text,uuid,numeric,timestamptz,text,text,text)') is not null
 and to_regprocedure('public.validate_sales_payment_integrity()') is not null
 then 1 else 0 end) as audited_correction_objects_present;

-- 2. The three triggers: the new guard (BEFORE UPDATE, first among the 01+
--    row triggers), the immutability trigger on the event table, and the
--    pre-existing integrity trigger that must not have been disturbed.
select 1/(case when count(*) = 3 then 1 else 0 end) as correction_triggers_present
from pg_trigger t
where not t.tgisinternal
  and t.tgenabled <> 'D'
  and (
    (t.tgrelid = 'public.sales_payments'::regclass
     and t.tgname = 'trg_sales_payments_01_correction_command'
     and t.tgfoid = 'public.guard_sales_payment_correction_command()'::regprocedure
     and pg_get_triggerdef(t.oid) like 'CREATE TRIGGER trg_sales_payments_01_correction_command BEFORE UPDATE ON public.sales_payments FOR EACH ROW %')
    or
    (t.tgrelid = 'public.sales_payment_edit_events'::regclass
     and t.tgname = 'trg_sales_payment_edit_events_immutable'
     and t.tgfoid = 'public.guard_sales_payment_edit_event()'::regprocedure
     and pg_get_triggerdef(t.oid) like 'CREATE TRIGGER trg_sales_payment_edit_events_immutable BEFORE DELETE OR UPDATE ON public.sales_payment_edit_events FOR EACH ROW %')
    or
    (t.tgrelid = 'public.sales_payments'::regclass
     and t.tgname = 'trg_sales_payments_validate_integrity'
     and t.tgfoid = 'public.validate_sales_payment_integrity()'::regprocedure)
  );

-- 3. Bodies: correct_sales_payment carries the 2026-08-19 per-tender rule and
--    not the July invoice-pinned one; validate_sales_payment_integrity still
--    carries both the correction-command hook and the tender-tax rule.
select 1/(case when
     pg_get_functiondef('public.correct_sales_payment(uuid,timestamptz,text,uuid,numeric,timestamptz,text,text,text)'::regprocedure)
       like '%v_saved.tax_treatment is distinct from v_before.tax_treatment%'
 and pg_get_functiondef('public.correct_sales_payment(uuid,timestamptz,text,uuid,numeric,timestamptz,text,text,text)'::regprocedure)
       not like '%v_saved.tax_treatment is distinct from v_invoice.tax_treatment%'
 and pg_get_functiondef('public.correct_sales_payment(uuid,timestamptz,text,uuid,numeric,timestamptz,text,text,text)'::regprocedure)
       like '%insert into public.sales_payment_edit_events%'
 and pg_get_functiondef('public.get_sales_payment_edit_operation(text)'::regprocedure)
       like '%response_snapshot || jsonb_build_object(''replayed'', true)%'
 and pg_get_functiondef('public.validate_sales_payment_integrity()'::regprocedure)
       like '%Tax follows the tender%'
 and pg_get_functiondef('public.validate_sales_payment_integrity()'::regprocedure)
       like '%app.sales_payment_correction_command%'
 then 1 else 0 end) as function_bodies_are_the_august_ones;

-- 4. The four new functions run as security definer pinned to public.
select 1/(case when count(*) = 4 then 1 else 0 end) as definer_functions_pinned
from pg_proc p
where p.oid in (
  'public.guard_sales_payment_edit_event()'::regprocedure,
  'public.guard_sales_payment_correction_command()'::regprocedure,
  'public.get_sales_payment_edit_operation(text)'::regprocedure,
  'public.correct_sales_payment(uuid,timestamptz,text,uuid,numeric,timestamptz,text,text,text)'::regprocedure
)
  and p.prosecdef
  and p.proconfig @> array['search_path=public'];

-- 5. ACLs: only authenticated may execute the two RPCs; nobody executes the
--    guards directly.
select 1/(case when
     has_function_privilege('authenticated', 'public.correct_sales_payment(uuid,timestamptz,text,uuid,numeric,timestamptz,text,text,text)', 'execute')
 and has_function_privilege('authenticated', 'public.get_sales_payment_edit_operation(text)', 'execute')
 and not has_function_privilege('anon', 'public.correct_sales_payment(uuid,timestamptz,text,uuid,numeric,timestamptz,text,text,text)', 'execute')
 and not has_function_privilege('anon', 'public.get_sales_payment_edit_operation(text)', 'execute')
 and not has_function_privilege('authenticated', 'public.guard_sales_payment_correction_command()', 'execute')
 and not has_function_privilege('authenticated', 'public.guard_sales_payment_edit_event()', 'execute')
 and not has_function_privilege('anon', 'public.guard_sales_payment_correction_command()', 'execute')
 then 1 else 0 end) as rpc_acls_are_authenticated_only;

-- 6. Event table: RLS on, one tenant-scoped SELECT policy, select-only grant.
select 1/(case when
     (select c.relrowsecurity from pg_class c where c.oid = 'public.sales_payment_edit_events'::regclass)
 and exists (
       select 1 from pg_policies pol
        where pol.schemaname = 'public'
          and pol.tablename = 'sales_payment_edit_events'
          and pol.policyname = 'sales_payment_edit_events_select'
          and pol.cmd = 'SELECT'
          and pol.roles = '{authenticated}'::name[]
          and pol.qual like '%user_tenant_id()%')
 and (select count(*) from pg_policies pol
       where pol.schemaname = 'public' and pol.tablename = 'sales_payment_edit_events') = 1
 and has_table_privilege('authenticated', 'public.sales_payment_edit_events', 'SELECT')
 and not has_table_privilege('authenticated', 'public.sales_payment_edit_events', 'INSERT')
 and not has_table_privilege('authenticated', 'public.sales_payment_edit_events', 'UPDATE')
 and not has_table_privilege('authenticated', 'public.sales_payment_edit_events', 'DELETE')
 and not has_table_privilege('anon', 'public.sales_payment_edit_events', 'SELECT')
 then 1 else 0 end) as event_table_rls_and_grants;

-- 7. Event table shape: two indexes, the (tenant_id, operation_key) replay
--    key, and the five foreign keys that tie a receipt to its tenant, invoice,
--    payment, trace operation and actor.
select 1/(case when
     (select count(*) from pg_indexes i
       where i.schemaname = 'public' and i.tablename = 'sales_payment_edit_events'
         and i.indexname in ('idx_sales_payment_edit_events_payment', 'idx_sales_payment_edit_events_trace')) = 2
 and (select count(*) from pg_constraint k
       where k.conrelid = 'public.sales_payment_edit_events'::regclass and k.contype = 'u') = 1
 and (select count(*) from pg_constraint k
       where k.conrelid = 'public.sales_payment_edit_events'::regclass and k.contype = 'f') = 5
 and (select count(*) from pg_constraint k
       where k.conrelid = 'public.sales_payment_edit_events'::regclass and k.contype = 'c') >= 2
 then 1 else 0 end) as event_table_shape;

-- 8. Nothing was written: the receipt table starts empty in production.
select count(*) as sales_payment_edit_events_rows
from public.sales_payment_edit_events;
