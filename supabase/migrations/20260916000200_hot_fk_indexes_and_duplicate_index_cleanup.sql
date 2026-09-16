-- 20260916000200: cover the foreign keys of the hot ERP tables with indexes and
-- remove the 11 duplicate-index groups the Supabase performance advisor
-- reported on 2026-09-15.
--
-- Forward behaviour
--   * 32 plain btree indexes, one per uncovered foreign key on
--     bug_reports, conversations, customer_addresses, employees,
--     erp_notifications, mechanic_jobs, message_reactions, messages,
--     sales_invoices, smart_task_job_items, smart_task_user_state and
--     smart_tasks. Every one of these tables has fewer than 1 000 live rows on
--     2026-09-15, so the builds are instant; the indexes exist so that a
--     delete or key update on the referenced side never scans the child
--     table under lock once the tables grow.
--   * Duplicate groups: the index without scans is dropped and the one the
--     planner already uses stays. products_tenant_id_id_key and
--     suppliers_tenant_id_id_key are UNIQUE constraints whose twin
--     (uq_products_tenant_id_id / uq_suppliers_tenant_id_id, bare unique
--     indexes) carries every referencing foreign key (17 and 19), so the
--     constraint without dependents is the one dropped; uq_purchase_invoices_tenant_id_id is a bare unique index whose
--     twin constraint purchase_invoices_tenant_id_id_key carries the three
--     foreign keys. Uniqueness on (tenant_id, id) stays enforced everywhere.
-- Recovery
--   Idempotent (if exists / if not exists). Recreating a dropped duplicate is
--   a plain CREATE INDEX from the definitions kept with the block evidence.
-- Locks
--   CREATE INDEX (non-concurrent) takes SHARE on each table for milliseconds;
--   DROP INDEX / DROP CONSTRAINT take ACCESS EXCLUSIVE briefly. lock_timeout
--   5s rolls the whole file back instead of queueing behind traffic.
begin;
set local lock_timeout = '5s';
set local statement_timeout = '120s';
set local search_path = public, pg_temp;

-- Indexes (one round trip)
do $block$
begin
  execute $ddl$ create index if not exists "idx_bug_reports_reported_by_fk" on public."bug_reports" using btree ("reported_by") $ddl$;
  execute $ddl$ create index if not exists "idx_conversations_accepted_by_fk" on public."conversations" using btree ("accepted_by") $ddl$;
  execute $ddl$ create index if not exists "idx_conversations_created_by_fk" on public."conversations" using btree ("created_by") $ddl$;
  execute $ddl$ create index if not exists "idx_conversations_resolved_by_fk" on public."conversations" using btree ("resolved_by") $ddl$;
  execute $ddl$ create index if not exists "idx_customer_addresses_tenant_id_fk" on public."customer_addresses" using btree ("tenant_id") $ddl$;
  execute $ddl$ create index if not exists "idx_employees_preferred_payment_method_id_fk" on public."employees" using btree ("preferred_payment_method_id") $ddl$;
  execute $ddl$ create index if not exists "idx_erp_notifications_recipient_user_id_fk" on public."erp_notifications" using btree ("recipient_user_id") $ddl$;
  execute $ddl$ create index if not exists "idx_mechanic_jobs_tenant_id_archive_operation_id_fk" on public."mechanic_jobs" using btree ("tenant_id", "archive_operation_id") $ddl$;
  execute $ddl$ create index if not exists "idx_mechanic_jobs_created_by_fk" on public."mechanic_jobs" using btree ("created_by") $ddl$;
  execute $ddl$ create index if not exists "idx_mechanic_jobs_deleted_by_fk" on public."mechanic_jobs" using btree ("deleted_by") $ddl$;
  execute $ddl$ create index if not exists "idx_mechanic_jobs_service_package_id_fk" on public."mechanic_jobs" using btree ("service_package_id") $ddl$;
  execute $ddl$ create index if not exists "idx_mechanic_jobs_tenant_id_status_id_fk" on public."mechanic_jobs" using btree ("tenant_id", "status_id") $ddl$;
  execute $ddl$ create index if not exists "idx_message_reactions_reactor_user_id_fk" on public."message_reactions" using btree ("reactor_user_id") $ddl$;
  execute $ddl$ create index if not exists "idx_messages_sender_id_fk" on public."messages" using btree ("sender_id") $ddl$;
  execute $ddl$ create index if not exists "idx_messages_tenant_id_fk" on public."messages" using btree ("tenant_id") $ddl$;
  execute $ddl$ create index if not exists "idx_messages_thread_root_message_id_fk" on public."messages" using btree ("thread_root_message_id") $ddl$;
  execute $ddl$ create index if not exists "idx_sales_invoices_created_by_fk" on public."sales_invoices" using btree ("created_by") $ddl$;
  execute $ddl$ create index if not exists "idx_sales_invoices_tenant_id_void_operation_id_fk" on public."sales_invoices" using btree ("tenant_id", "void_operation_id") $ddl$;
  execute $ddl$ create index if not exists "idx_sales_invoices_voided_by_fk" on public."sales_invoices" using btree ("voided_by") $ddl$;
  execute $ddl$ create index if not exists "idx_smart_task_job_items_linked_by_fk" on public."smart_task_job_items" using btree ("linked_by") $ddl$;
  execute $ddl$ create index if not exists "idx_smart_task_user_state_tenant_id_fk" on public."smart_task_user_state" using btree ("tenant_id") $ddl$;
  execute $ddl$ create index if not exists "idx_smart_task_user_state_user_id_fk" on public."smart_task_user_state" using btree ("user_id") $ddl$;
  execute $ddl$ create index if not exists "idx_smart_tasks_acknowledged_by_fk" on public."smart_tasks" using btree ("acknowledged_by") $ddl$;
  execute $ddl$ create index if not exists "idx_smart_tasks_assigned_by_fk" on public."smart_tasks" using btree ("assigned_by") $ddl$;
  execute $ddl$ create index if not exists "idx_smart_tasks_blocked_by_fk" on public."smart_tasks" using btree ("blocked_by") $ddl$;
  execute $ddl$ create index if not exists "idx_smart_tasks_cancelled_by_fk" on public."smart_tasks" using btree ("cancelled_by") $ddl$;
  execute $ddl$ create index if not exists "idx_smart_tasks_completed_by_fk" on public."smart_tasks" using btree ("completed_by") $ddl$;
  execute $ddl$ create index if not exists "idx_smart_tasks_created_by_fk" on public."smart_tasks" using btree ("created_by") $ddl$;
  execute $ddl$ create index if not exists "idx_smart_tasks_linked_customer_id_fk" on public."smart_tasks" using btree ("linked_customer_id") $ddl$;
  execute $ddl$ create index if not exists "idx_smart_tasks_linked_purchase_invoice_id_fk" on public."smart_tasks" using btree ("linked_purchase_invoice_id") $ddl$;
  execute $ddl$ create index if not exists "idx_smart_tasks_linked_sales_invoice_id_fk" on public."smart_tasks" using btree ("linked_sales_invoice_id") $ddl$;
  execute $ddl$ create index if not exists "idx_smart_tasks_linked_supplier_id_fk" on public."smart_tasks" using btree ("linked_supplier_id") $ddl$;
  execute $ddl$ alter table public."products" drop constraint if exists "products_tenant_id_id_key" $ddl$;
  execute $ddl$ alter table public."suppliers" drop constraint if exists "suppliers_tenant_id_id_key" $ddl$;
  execute $ddl$ drop index if exists public."idx_bike_profiles_bike" $ddl$;
  execute $ddl$ drop index if exists public."idx_conv_contexts_lookup" $ddl$;
  execute $ddl$ drop index if exists public."idx_conversation_contexts_context" $ddl$;
  execute $ddl$ drop index if exists public."idx_conv_contexts_conversation" $ddl$;
  execute $ddl$ drop index if exists public."idx_contracts_tenant" $ddl$;
  execute $ddl$ drop index if exists public."idx_journal_lines_journal_entry" $ddl$;
  execute $ddl$ drop index if exists public."idx_pvl_employee" $ddl$;
  execute $ddl$ drop index if exists public."idx_pvl_voucher" $ddl$;
  execute $ddl$ drop index if exists public."idx_invitations_tenant" $ddl$;
  execute $ddl$ drop index if exists public."uq_purchase_invoices_tenant_id_id" $ddl$;
end
$block$;
commit;
