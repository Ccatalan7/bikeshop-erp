-- Read-back for 20260916000200. Run it before the deploy and require a failure.
select 1 / (count(*) = 32)::integer as hot_fk_indexes_present
from pg_indexes where schemaname = 'public' and indexname in ('idx_bug_reports_reported_by_fk', 'idx_conversations_accepted_by_fk', 'idx_conversations_created_by_fk', 'idx_conversations_resolved_by_fk', 'idx_customer_addresses_tenant_id_fk', 'idx_employees_preferred_payment_method_id_fk', 'idx_erp_notifications_recipient_user_id_fk', 'idx_mechanic_jobs_tenant_id_archive_operation_id_fk', 'idx_mechanic_jobs_created_by_fk', 'idx_mechanic_jobs_deleted_by_fk', 'idx_mechanic_jobs_service_package_id_fk', 'idx_mechanic_jobs_tenant_id_status_id_fk', 'idx_message_reactions_reactor_user_id_fk', 'idx_messages_sender_id_fk', 'idx_messages_tenant_id_fk', 'idx_messages_thread_root_message_id_fk', 'idx_sales_invoices_created_by_fk', 'idx_sales_invoices_tenant_id_void_operation_id_fk', 'idx_sales_invoices_voided_by_fk', 'idx_smart_task_job_items_linked_by_fk', 'idx_smart_task_user_state_tenant_id_fk', 'idx_smart_task_user_state_user_id_fk', 'idx_smart_tasks_acknowledged_by_fk', 'idx_smart_tasks_assigned_by_fk', 'idx_smart_tasks_blocked_by_fk', 'idx_smart_tasks_cancelled_by_fk', 'idx_smart_tasks_completed_by_fk', 'idx_smart_tasks_created_by_fk', 'idx_smart_tasks_linked_customer_id_fk', 'idx_smart_tasks_linked_purchase_invoice_id_fk', 'idx_smart_tasks_linked_sales_invoice_id_fk', 'idx_smart_tasks_linked_supplier_id_fk');
select 1 / (count(*) = 0)::integer as duplicate_indexes_gone
from pg_class where relkind = 'i' and relnamespace = 'public'::regnamespace
  and relname in ('idx_bike_profiles_bike', 'idx_conv_contexts_lookup', 'idx_conversation_contexts_context', 'idx_conv_contexts_conversation', 'idx_contracts_tenant', 'idx_journal_lines_journal_entry', 'idx_pvl_employee', 'idx_pvl_voucher', 'idx_invitations_tenant', 'uq_purchase_invoices_tenant_id_id', 'products_tenant_id_id_key', 'suppliers_tenant_id_id_key');
select 1 / (count(*) = 3)::integer as tenant_id_uniqueness_still_enforced
from pg_index where indisunique and indexrelid in (
  'public.uq_products_tenant_id_id'::regclass,
  'public.uq_suppliers_tenant_id_id'::regclass,
  'public.purchase_invoices_tenant_id_id_key'::regclass);
select 1 / (count(*) = 17)::integer as product_fks_still_bound
from pg_constraint where contype = 'f' and conindid = 'public.uq_products_tenant_id_id'::regclass;
select 1 / (count(*) = 19)::integer as supplier_fks_still_bound
from pg_constraint where contype = 'f' and conindid = 'public.uq_suppliers_tenant_id_id'::regclass;
select 1 / (count(*) = 3)::integer as purchase_invoice_fks_still_bound
from pg_constraint where contype = 'f' and conindid = 'public.purchase_invoices_tenant_id_id_key'::regclass;
