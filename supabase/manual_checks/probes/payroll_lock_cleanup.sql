-- Takes the payroll-race fixture out of the synthetic LOCAL stack, in
-- dependency order. Run on its own or from payroll_lock_seed.sql; it
-- touches nothing outside its own tenant.
begin;

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);
set local session_replication_role = replica;

delete from public.bank_reconciliation_allocations
 where tenant_id = 'e9000000-0000-4000-8000-000000000001';
delete from public.bank_reconciliation_row_decisions
 where tenant_id = 'e9000000-0000-4000-8000-000000000001';
delete from public.bank_reconciliation_operations
 where tenant_id = 'e9000000-0000-4000-8000-000000000001';
delete from public.bank_statement_rows
 where tenant_id = 'e9000000-0000-4000-8000-000000000001';
delete from public.bank_statement_imports
 where tenant_id = 'e9000000-0000-4000-8000-000000000001';
delete from public.payroll_money_operation_movements
 where tenant_id = 'e9000000-0000-4000-8000-000000000001';
delete from public.payroll_money_command_contexts
 where tenant_id = 'e9000000-0000-4000-8000-000000000001';
delete from public.payroll_money_operations
 where tenant_id = 'e9000000-0000-4000-8000-000000000001';
delete from public.payroll_voucher_confirmation_batch_operations
 where tenant_id = 'e9000000-0000-4000-8000-000000000001';
delete from public.payroll_voucher_draft_operations
 where tenant_id = 'e9000000-0000-4000-8000-000000000001';
delete from public.expense_payments
 where tenant_id = 'e9000000-0000-4000-8000-000000000001';
delete from public.expenses
 where tenant_id = 'e9000000-0000-4000-8000-000000000001';
delete from public.journal_lines
 where tenant_id = 'e9000000-0000-4000-8000-000000000001';
delete from public.journal_entries
 where tenant_id = 'e9000000-0000-4000-8000-000000000001';
delete from public.payroll_voucher_lines
 where tenant_id = 'e9000000-0000-4000-8000-000000000001';
delete from public.payroll_vouchers
 where tenant_id = 'e9000000-0000-4000-8000-000000000001';
delete from public.employees
 where tenant_id = 'e9000000-0000-4000-8000-000000000001';
delete from public.payment_terminal_terms
 where tenant_id = 'e9000000-0000-4000-8000-000000000001';
delete from public.payment_terminal_profiles
 where tenant_id = 'e9000000-0000-4000-8000-000000000001';
delete from public.payment_methods
 where tenant_id = 'e9000000-0000-4000-8000-000000000001';
delete from public.accounts
 where tenant_id = 'e9000000-0000-4000-8000-000000000001';
delete from public.user_profiles
 where tenant_id = 'e9000000-0000-4000-8000-000000000001';
delete from auth.users
 where id = 'e9000000-0000-4000-8000-000000000002';
delete from public.tenants
 where id = 'e9000000-0000-4000-8000-000000000001';

commit;
