-- 20260916000100: hoist every per-row STABLE session call in public RLS policies into
-- an initplan, and remove the permissive-policy duplication the Supabase
-- performance advisor reported on 2026-09-15 (58 auth_rls_initplan,
-- 45 multiple_permissive_policies).
--
-- Forward behaviour
--   * ALTER POLICY rewrites USING / WITH CHECK so that auth.uid(),
--     user_tenant_id(), erp_member_tenant_id(), current_erp_employee_id(),
--     worker_portal_tenant_id(), worker_portal_employee_id() and
--     current_setting(...) are evaluated once per statement as
--     (select fn()) instead of once per row. All of them are STABLE
--     (pg_proc.provolatile = 's' read on 2026-09-15), so the value is the
--     same for every row of a statement and the rewrite is exact.
--   * Pure duplicates (a SELECT policy identical to a FOR ALL policy for the
--     same roles) are dropped; a public/authenticated SELECT pair with the
--     same audience is merged with OR into one policy; four FOR ALL policies
--     that shadowed a broader SELECT are split into INSERT/UPDATE/DELETE.
--     Every merged expression is the literal OR of the previous expressions
--     as deparsed by pg_policies; nothing is simplified.
--   * Nine advisor findings are left in place on purpose: the customer-own
--     policies of customer_addresses, bikes, mechanic_jobs, online_orders and
--     online_order_items and the public/private pair of website_blocks are
--     pinned by pgTAP contracts (see the block record in
--     docs/development/SUPABASE_WORKFLOW.md).
-- Recovery
--   Re-running this file is idempotent (drop-if-exists + create, and ALTER
--   POLICY with the same expressions). The previous expressions are the
--   deparsed catalog of 2026-09-15 kept with the block evidence; restoring
--   one means a new reviewed forward file, never an edit of this one.
-- Locks
--   CREATE/ALTER/DROP POLICY take ACCESS EXCLUSIVE on their table for the
--   rest of the transaction; ~290 tables are touched, all small. lock_timeout
--   5s makes the whole file roll back instead of queueing behind traffic.
begin;
set local lock_timeout = '5s';
set local statement_timeout = '120s';
set local search_path = public, pg_temp;

-- 1. Permissive-policy hygiene (one round trip)
do $block$
begin
  execute $ddl$ drop policy if exists "users_view_own_push_subscriptions" on public."email_push_subscriptions" $ddl$;
  execute $ddl$ drop policy if exists "product_gama_overrides_tenant_read" on public."product_gama_overrides" $ddl$;
  execute $ddl$ drop policy if exists "spec_facts_select" on public."spec_facts" $ddl$;
  execute $ddl$ drop policy if exists "spec_fact_values_select" on public."spec_fact_values" $ddl$;
  execute $ddl$ drop policy if exists "online_shipping_rate_tiers_staff_read" on public."online_shipping_rate_tiers" $ddl$;
  execute $ddl$ drop policy if exists "categories_select" on public."categories" $ddl$;
  execute $ddl$ drop policy if exists "public_categories_select_authenticated" on public."categories" $ddl$;
  execute $ddl$ drop policy if exists "featured_products_select" on public."featured_products" $ddl$;
  execute $ddl$ drop policy if exists "public_featured_products_select_authenticated" on public."featured_products" $ddl$;
  execute $ddl$ drop policy if exists "product_brands_select" on public."product_brands" $ddl$;
  execute $ddl$ drop policy if exists "public_product_brands_select_authenticated" on public."product_brands" $ddl$;
  execute $ddl$ drop policy if exists "product_categories_select" on public."product_categories" $ddl$;
  execute $ddl$ drop policy if exists "public_product_categories_select_authenticated" on public."product_categories" $ddl$;
  execute $ddl$ drop policy if exists "products_select" on public."products" $ddl$;
  execute $ddl$ drop policy if exists "public_products_select_authenticated" on public."products" $ddl$;
  execute $ddl$ drop policy if exists "website_banners_select" on public."website_banners" $ddl$;
  execute $ddl$ drop policy if exists "public_website_banners_select_authenticated" on public."website_banners" $ddl$;
  execute $ddl$ drop policy if exists "website_content_select" on public."website_content" $ddl$;
  execute $ddl$ drop policy if exists "public_website_content_select_authenticated" on public."website_content" $ddl$;
  execute $ddl$ drop policy if exists "website_navigation_select" on public."website_navigation" $ddl$;
  execute $ddl$ drop policy if exists "Customers can view their own invoices" on public."sales_invoices" $ddl$;
  execute $ddl$ drop policy if exists "sales_invoices_select" on public."sales_invoices" $ddl$;
  execute $ddl$ drop policy if exists "business_sites_write" on public."business_sites" $ddl$;
  execute $ddl$ drop policy if exists "journal_entries_write_accounting" on public."journal_entries" $ddl$;
  execute $ddl$ drop policy if exists "journal_lines_write_accounting" on public."journal_lines" $ddl$;
  execute $ddl$ drop policy if exists "spec_definition_values_write" on public."spec_definition_values" $ddl$;
  execute $ddl$ drop policy if exists "categories_select" on public."categories" $ddl$;
  execute $ddl$ drop policy if exists "featured_products_select" on public."featured_products" $ddl$;
  execute $ddl$ drop policy if exists "product_brands_select" on public."product_brands" $ddl$;
  execute $ddl$ drop policy if exists "product_categories_select" on public."product_categories" $ddl$;
  execute $ddl$ drop policy if exists "products_select" on public."products" $ddl$;
  execute $ddl$ drop policy if exists "website_banners_select" on public."website_banners" $ddl$;
  execute $ddl$ drop policy if exists "website_content_select" on public."website_content" $ddl$;
  execute $ddl$ drop policy if exists "website_navigation_select" on public."website_navigation" $ddl$;
  execute $ddl$ drop policy if exists "sales_invoices_select" on public."sales_invoices" $ddl$;
  execute $ddl$ drop policy if exists "business_sites_insert" on public."business_sites" $ddl$;
  execute $ddl$ drop policy if exists "business_sites_update" on public."business_sites" $ddl$;
  execute $ddl$ drop policy if exists "business_sites_delete" on public."business_sites" $ddl$;
  execute $ddl$ drop policy if exists "journal_entries_insert_accounting" on public."journal_entries" $ddl$;
  execute $ddl$ drop policy if exists "journal_entries_update_accounting" on public."journal_entries" $ddl$;
  execute $ddl$ drop policy if exists "journal_entries_delete_accounting" on public."journal_entries" $ddl$;
  execute $ddl$ drop policy if exists "journal_lines_insert_accounting" on public."journal_lines" $ddl$;
  execute $ddl$ drop policy if exists "journal_lines_update_accounting" on public."journal_lines" $ddl$;
  execute $ddl$ drop policy if exists "journal_lines_delete_accounting" on public."journal_lines" $ddl$;
  execute $ddl$ drop policy if exists "spec_definition_values_insert" on public."spec_definition_values" $ddl$;
  execute $ddl$ drop policy if exists "spec_definition_values_update" on public."spec_definition_values" $ddl$;
  execute $ddl$ drop policy if exists "spec_definition_values_delete" on public."spec_definition_values" $ddl$;
  execute $ddl$ create policy "categories_select" on public."categories"
    as permissive for select to authenticated
    using (((tenant_id = (select user_tenant_id()))) OR (true)) $ddl$;
  execute $ddl$ create policy "featured_products_select" on public."featured_products"
    as permissive for select to authenticated
    using (((tenant_id = (select user_tenant_id()))) OR ((active = true))) $ddl$;
  execute $ddl$ create policy "product_brands_select" on public."product_brands"
    as permissive for select to authenticated
    using (((tenant_id = (select user_tenant_id()))) OR ((is_active = true))) $ddl$;
  execute $ddl$ create policy "product_categories_select" on public."product_categories"
    as permissive for select to authenticated
    using (((tenant_id = (select user_tenant_id()))) OR ((is_active = true))) $ddl$;
  execute $ddl$ create policy "products_select" on public."products"
    as permissive for select to authenticated
    using (((tenant_id = (select user_tenant_id()))) OR (((is_active = true) AND (COALESCE(is_published, false) = true) AND (COALESCE(show_on_website, false) = true)))) $ddl$;
  execute $ddl$ create policy "website_banners_select" on public."website_banners"
    as permissive for select to authenticated
    using (((tenant_id = (select user_tenant_id()))) OR ((active = true))) $ddl$;
  execute $ddl$ create policy "website_content_select" on public."website_content"
    as permissive for select to authenticated
    using (((tenant_id = (select user_tenant_id()))) OR ((tenant_id IS NOT NULL))) $ddl$;
  execute $ddl$ create policy "website_navigation_select" on public."website_navigation"
    as permissive for select to authenticated
    using (((tenant_id = (select user_tenant_id()))) OR ((is_visible = true))) $ddl$;
  execute $ddl$ create policy "sales_invoices_select" on public."sales_invoices"
    as permissive for select to authenticated
    using (((tenant_id = (select user_tenant_id()))) OR ((customer_id = (select auth.uid())))) $ddl$;
  execute $ddl$ create policy "business_sites_insert" on public."business_sites"
    as permissive for insert to authenticated
    with check (can_edit_tenant_settings(tenant_id)) $ddl$;
  execute $ddl$ create policy "business_sites_update" on public."business_sites"
    as permissive for update to authenticated
    using (can_edit_tenant_settings(tenant_id))
    with check (can_edit_tenant_settings(tenant_id)) $ddl$;
  execute $ddl$ create policy "business_sites_delete" on public."business_sites"
    as permissive for delete to authenticated
    using (can_edit_tenant_settings(tenant_id)) $ddl$;
  execute $ddl$ create policy "journal_entries_insert_accounting" on public."journal_entries"
    as permissive for insert to authenticated
    with check (can_manage_tenant_accounting(tenant_id)) $ddl$;
  execute $ddl$ create policy "journal_entries_update_accounting" on public."journal_entries"
    as permissive for update to authenticated
    using (can_manage_tenant_accounting(tenant_id))
    with check (can_manage_tenant_accounting(tenant_id)) $ddl$;
  execute $ddl$ create policy "journal_entries_delete_accounting" on public."journal_entries"
    as permissive for delete to authenticated
    using (can_manage_tenant_accounting(tenant_id)) $ddl$;
  execute $ddl$ create policy "journal_lines_insert_accounting" on public."journal_lines"
    as permissive for insert to authenticated
    with check ((can_manage_tenant_accounting(tenant_id) AND (EXISTS ( SELECT 1
   FROM journal_entries entry
  WHERE ((entry.id = journal_lines.entry_id) AND (entry.tenant_id = journal_lines.tenant_id)))))) $ddl$;
  execute $ddl$ create policy "journal_lines_update_accounting" on public."journal_lines"
    as permissive for update to authenticated
    using (can_manage_tenant_accounting(tenant_id))
    with check ((can_manage_tenant_accounting(tenant_id) AND (EXISTS ( SELECT 1
   FROM journal_entries entry
  WHERE ((entry.id = journal_lines.entry_id) AND (entry.tenant_id = journal_lines.tenant_id)))))) $ddl$;
  execute $ddl$ create policy "journal_lines_delete_accounting" on public."journal_lines"
    as permissive for delete to authenticated
    using (can_manage_tenant_accounting(tenant_id)) $ddl$;
  execute $ddl$ create policy "spec_definition_values_insert" on public."spec_definition_values"
    as permissive for insert to authenticated
    with check ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ create policy "spec_definition_values_update" on public."spec_definition_values"
    as permissive for update to authenticated
    using ((tenant_id = (select user_tenant_id())))
    with check ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ create policy "spec_definition_values_delete" on public."spec_definition_values"
    as permissive for delete to authenticated
    using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "website_navigation_select_public" on public."website_navigation" to anon $ddl$;
end
$block$;
-- 2. Hoist per-row STABLE calls into initplans (one round trip)
do $block$
begin
  execute $ddl$ alter policy "accounting_source_identity_rows_select" on public."accounting_source_identity_backfill_rows" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "accounting_source_identity_runs_select" on public."accounting_source_identity_backfill_runs" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "accounts_delete" on public."accounts" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "accounts_insert" on public."accounts" with check ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "accounts_select" on public."accounts" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "accounts_update" on public."accounts" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "aliexpress_sku_reservation_receipts_select" on public."aliexpress_sku_reservation_receipts" using (((tenant_id = (select user_tenant_id())) AND (EXISTS ( SELECT 1
   FROM user_profiles profile
  WHERE ((profile.user_id = (select auth.uid())) AND (profile.tenant_id = aliexpress_sku_reservation_receipts.tenant_id) AND (profile.is_active IS TRUE)))))) $ddl$;
  execute $ddl$ alter policy "analytics_snapshots_tenant_isolation" on public."analytics_snapshots" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "app_files_delete" on public."app_files" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "app_files_insert" on public."app_files" with check ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "app_files_payroll_evidence_insert_guard" on public."app_files" with check (((NOT ((source_type = 'payroll_advance'::text) OR (NOT (context_type IS DISTINCT FROM 'payroll_advance_operation'::text)) OR ((storage_bucket = 'vinabike-files'::text) AND (split_part(storage_path, '/'::text, 2) = 'evidence'::text) AND (split_part(storage_path, '/'::text, 3) = 'payroll_advance'::text)))) OR ((tenant_id = (select user_tenant_id())) AND can_manage_tenant_payroll(tenant_id) AND (uploaded_by = (select auth.uid())) AND (source_type = 'payroll_advance'::text) AND (context_type = 'payroll_advance_operation'::text) AND (context_id IS NOT NULL) AND (context_id ~ '^[A-Za-z0-9:_-]{8,200}$'::text) AND (source_id = context_id) AND ((metadata ->> 'operation_key'::text) = context_id) AND (lower(COALESCE((metadata ->> 'sha256'::text), ''::text)) ~ '^[0-9a-f]{64}$'::text) AND private.employee_advance_receipt_values_allowed(size_bytes, mime_type) AND (storage_bucket = 'vinabike-files'::text) AND (split_part(storage_path, '/'::text, 1) = (tenant_id)::text) AND (split_part(storage_path, '/'::text, 2) = 'evidence'::text) AND (split_part(storage_path, '/'::text, 3) = 'payroll_advance'::text) AND (split_part(storage_path, '/'::text, 4) <> ''::text)))) $ddl$;
  execute $ddl$ alter policy "app_files_payroll_evidence_update_guard" on public."app_files" using (((NOT ((source_type = 'payroll_advance'::text) OR (NOT (context_type IS DISTINCT FROM 'payroll_advance_operation'::text)) OR ((storage_bucket = 'vinabike-files'::text) AND (split_part(storage_path, '/'::text, 2) = 'evidence'::text) AND (split_part(storage_path, '/'::text, 3) = 'payroll_advance'::text)))) OR ((tenant_id = (select user_tenant_id())) AND can_manage_tenant_payroll(tenant_id) AND (uploaded_by = (select auth.uid())) AND (source_type = 'payroll_advance'::text) AND (context_type = 'payroll_advance_operation'::text) AND (context_id IS NOT NULL) AND (context_id ~ '^[A-Za-z0-9:_-]{8,200}$'::text) AND (source_id = context_id) AND ((metadata ->> 'operation_key'::text) = context_id) AND (lower(COALESCE((metadata ->> 'sha256'::text), ''::text)) ~ '^[0-9a-f]{64}$'::text) AND private.employee_advance_receipt_values_allowed(size_bytes, mime_type) AND (storage_bucket = 'vinabike-files'::text) AND (split_part(storage_path, '/'::text, 1) = (tenant_id)::text) AND (split_part(storage_path, '/'::text, 2) = 'evidence'::text) AND (split_part(storage_path, '/'::text, 3) = 'payroll_advance'::text) AND (split_part(storage_path, '/'::text, 4) <> ''::text)))) with check (((NOT ((source_type = 'payroll_advance'::text) OR (NOT (context_type IS DISTINCT FROM 'payroll_advance_operation'::text)) OR ((storage_bucket = 'vinabike-files'::text) AND (split_part(storage_path, '/'::text, 2) = 'evidence'::text) AND (split_part(storage_path, '/'::text, 3) = 'payroll_advance'::text)))) OR ((tenant_id = (select user_tenant_id())) AND can_manage_tenant_payroll(tenant_id) AND (uploaded_by = (select auth.uid())) AND (source_type = 'payroll_advance'::text) AND (context_type = 'payroll_advance_operation'::text) AND (context_id IS NOT NULL) AND (context_id ~ '^[A-Za-z0-9:_-]{8,200}$'::text) AND (source_id = context_id) AND ((metadata ->> 'operation_key'::text) = context_id) AND (lower(COALESCE((metadata ->> 'sha256'::text), ''::text)) ~ '^[0-9a-f]{64}$'::text) AND private.employee_advance_receipt_values_allowed(size_bytes, mime_type) AND (storage_bucket = 'vinabike-files'::text) AND (split_part(storage_path, '/'::text, 1) = (tenant_id)::text) AND (split_part(storage_path, '/'::text, 2) = 'evidence'::text) AND (split_part(storage_path, '/'::text, 3) = 'payroll_advance'::text) AND (split_part(storage_path, '/'::text, 4) <> ''::text)))) $ddl$;
  execute $ddl$ alter policy "app_files_select" on public."app_files" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "app_files_update" on public."app_files" using ((tenant_id = (select user_tenant_id()))) with check ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "attendance_records_read_authorized" on public."attendance_records" using ((can_manage_tenant_hr(tenant_id) OR can_manage_tenant_payroll(tenant_id) OR ((tenant_id = (select erp_member_tenant_id())) AND (employee_id = (select current_erp_employee_id()))))) $ddl$;
  execute $ddl$ alter policy "attendances_read_authorized" on public."attendances" using ((can_manage_tenant_hr(tenant_id) OR can_manage_tenant_payroll(tenant_id) OR ((tenant_id = (select erp_member_tenant_id())) AND (employee_id = (select current_erp_employee_id()))))) $ddl$;
  execute $ddl$ alter policy "backup_schedules_delete" on public."backup_schedules" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "backup_schedules_insert" on public."backup_schedules" with check ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "backup_schedules_select" on public."backup_schedules" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "backup_schedules_update" on public."backup_schedules" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "bike_aggregate_save_operations_select" on public."bike_aggregate_save_operations" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "bike_brands_delete" on public."bike_brands" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "bike_brands_insert" on public."bike_brands" with check ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "bike_brands_select" on public."bike_brands" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "bike_brands_update" on public."bike_brands" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "bike_component_lifecycles_delete" on public."bike_component_lifecycles" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "bike_component_lifecycles_insert" on public."bike_component_lifecycles" with check ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "bike_component_lifecycles_select" on public."bike_component_lifecycles" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "bike_component_lifecycles_update" on public."bike_component_lifecycles" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "bike_events_delete" on public."bike_events" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "bike_events_insert" on public."bike_events" with check ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "bike_events_select" on public."bike_events" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "bike_events_update" on public."bike_events" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "bike_interventions_delete" on public."bike_interventions" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "bike_interventions_insert" on public."bike_interventions" with check ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "bike_interventions_select" on public."bike_interventions" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "bike_interventions_update" on public."bike_interventions" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "bike_models_delete" on public."bike_models" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "bike_models_insert" on public."bike_models" with check ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "bike_models_select" on public."bike_models" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "bike_models_update" on public."bike_models" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "bike_observations_delete" on public."bike_observations" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "bike_observations_insert" on public."bike_observations" with check ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "bike_observations_select" on public."bike_observations" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "bike_observations_update" on public."bike_observations" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "bike_profiles_delete" on public."bike_profiles" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "bike_profiles_insert" on public."bike_profiles" with check ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "bike_profiles_select" on public."bike_profiles" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "bike_profiles_update" on public."bike_profiles" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "bike_system_states_delete" on public."bike_system_states" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "bike_system_states_insert" on public."bike_system_states" with check ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "bike_system_states_select" on public."bike_system_states" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "bike_system_states_update" on public."bike_system_states" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "public_bikes_select_own" on public."bikes" using ((EXISTS ( SELECT 1
   FROM customers customer
  WHERE (is_tenant_active(customer.tenant_id) AND (customer.id = bikes.customer_id) AND (customer.tenant_id = bikes.tenant_id) AND (customer.auth_user_id = (select auth.uid())) AND (customer.is_active IS TRUE))))) $ddl$;
  execute $ddl$ alter policy "bug_reports_delete" on public."bug_reports" using ((tenant_id IN ( SELECT user_profiles.tenant_id
   FROM user_profiles
  WHERE (user_profiles.user_id = (select auth.uid()))))) $ddl$;
  execute $ddl$ alter policy "bug_reports_insert" on public."bug_reports" with check ((tenant_id IN ( SELECT user_profiles.tenant_id
   FROM user_profiles
  WHERE (user_profiles.user_id = (select auth.uid()))))) $ddl$;
  execute $ddl$ alter policy "bug_reports_select" on public."bug_reports" using ((tenant_id IN ( SELECT user_profiles.tenant_id
   FROM user_profiles
  WHERE (user_profiles.user_id = (select auth.uid()))))) $ddl$;
  execute $ddl$ alter policy "bug_reports_update" on public."bug_reports" using ((tenant_id IN ( SELECT user_profiles.tenant_id
   FROM user_profiles
  WHERE (user_profiles.user_id = (select auth.uid()))))) $ddl$;
  execute $ddl$ alter policy "campaign_metrics_tenant_isolation" on public."campaign_metrics" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "campaigns_tenant_isolation" on public."campaigns" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "categories_delete" on public."categories" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "categories_insert" on public."categories" with check ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "categories_update" on public."categories" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "category_tech_mappings_delete" on public."category_tech_mappings" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "category_tech_mappings_insert" on public."category_tech_mappings" with check ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "category_tech_mappings_select" on public."category_tech_mappings" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "category_tech_mappings_update" on public."category_tech_mappings" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "companies_tenant_isolation" on public."companies" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "company_bank_accounts_tenant_isolation" on public."company_bank_accounts" using ((tenant_id = (select user_tenant_id()))) with check ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "company_settings_delete" on public."company_settings" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "company_settings_insert" on public."company_settings" with check ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "company_settings_select" on public."company_settings" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "company_settings_update" on public."company_settings" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "content_items_tenant_isolation" on public."content_items" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "content_media_tenant_isolation" on public."content_media" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "contracts_delete" on public."contracts" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "contracts_insert" on public."contracts" with check ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "contracts_select" on public."contracts" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "contracts_update" on public."contracts" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "conversation_contexts_insert_scoped" on public."conversation_contexts" with check ((messaging_context_belongs_to_tenant(context_type, context_id, tenant_id) AND (EXISTS ( SELECT 1
   FROM conversations c
  WHERE ((c.id = conversation_contexts.conversation_id) AND (c.tenant_id = conversation_contexts.tenant_id) AND (messaging_can_manage_conversation(c.id) OR ((c.type = 'support'::text) AND (c.created_by = (select auth.uid())) AND messaging_is_conversation_participant(c.id) AND messaging_customer_can_reference_context(c.context_type, c.context_id, c.tenant_id)))))))) $ddl$;
  execute $ddl$ alter policy "conversations_insert_scoped" on public."conversations" with check ((((select auth.uid()) IS NOT NULL) AND (created_by = (select auth.uid())) AND ((messaging_is_staff_in_tenant(tenant_id) AND (((type = 'internal'::text) AND (channel = 'internal'::text)) OR ((type = 'support'::text) AND (channel = 'website_portal'::text)))) OR ((type = 'support'::text) AND (channel = 'website_portal'::text) AND (status = 'pending'::text) AND (accepted_by IS NULL) AND (accepted_at IS NULL) AND messaging_is_customer_in_tenant(tenant_id) AND ((context_type IS NULL) OR ((context_id IS NOT NULL) AND messaging_customer_can_reference_context(context_type, context_id, tenant_id))))))) $ddl$;
  execute $ddl$ alter policy "public_customer_addresses_delete_own" on public."customer_addresses" using ((EXISTS ( SELECT 1
   FROM customers customer
  WHERE (is_tenant_active(customer.tenant_id) AND (customer.id = customer_addresses.customer_id) AND (customer.tenant_id = customer_addresses.tenant_id) AND (customer.auth_user_id = (select auth.uid())) AND (customer.is_active IS TRUE))))) $ddl$;
  execute $ddl$ alter policy "public_customer_addresses_insert_own" on public."customer_addresses" with check ((EXISTS ( SELECT 1
   FROM customers customer
  WHERE (is_tenant_active(customer.tenant_id) AND (customer.id = customer_addresses.customer_id) AND (customer.tenant_id = customer_addresses.tenant_id) AND (customer.auth_user_id = (select auth.uid())) AND (customer.is_active IS TRUE))))) $ddl$;
  execute $ddl$ alter policy "public_customer_addresses_select_own" on public."customer_addresses" using ((EXISTS ( SELECT 1
   FROM customers customer
  WHERE (is_tenant_active(customer.tenant_id) AND (customer.id = customer_addresses.customer_id) AND (customer.tenant_id = customer_addresses.tenant_id) AND (customer.auth_user_id = (select auth.uid())) AND (customer.is_active IS TRUE))))) $ddl$;
  execute $ddl$ alter policy "public_customer_addresses_update_own" on public."customer_addresses" using ((EXISTS ( SELECT 1
   FROM customers customer
  WHERE (is_tenant_active(customer.tenant_id) AND (customer.id = customer_addresses.customer_id) AND (customer.tenant_id = customer_addresses.tenant_id) AND (customer.auth_user_id = (select auth.uid())) AND (customer.is_active IS TRUE))))) with check ((EXISTS ( SELECT 1
   FROM customers customer
  WHERE (is_tenant_active(customer.tenant_id) AND (customer.id = customer_addresses.customer_id) AND (customer.tenant_id = customer_addresses.tenant_id) AND (customer.auth_user_id = (select auth.uid())) AND (customer.is_active IS TRUE))))) $ddl$;
  execute $ddl$ alter policy "customers_read_staff_or_self" on public."customers" using ((is_active_tenant_member(tenant_id) OR ((auth_user_id = (select auth.uid())) AND (is_active IS TRUE) AND is_tenant_active(tenant_id)))) $ddl$;
  execute $ddl$ alter policy "customers_update_staff_or_self" on public."customers" using ((is_active_tenant_member(tenant_id) OR ((auth_user_id = (select auth.uid())) AND (is_active IS TRUE) AND is_tenant_active(tenant_id)))) with check ((is_active_tenant_member(tenant_id) OR ((auth_user_id = (select auth.uid())) AND (is_active IS TRUE) AND is_tenant_active(tenant_id)))) $ddl$;
  execute $ddl$ alter policy "departments_read_erp" on public."departments" using ((tenant_id = (select erp_member_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "document_sequences_insert" on public."document_sequences" with check ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "document_sequences_select" on public."document_sequences" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "document_sequences_update" on public."document_sequences" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "users_manage_own_push_subscriptions" on public."email_push_subscriptions" using (((select auth.uid()) = user_id)) $ddl$;
  execute $ddl$ alter policy "employee_advance_allocations_read_authorized" on public."employee_advance_allocations" using ((can_manage_tenant_payroll(tenant_id) OR ((tenant_id = (select erp_member_tenant_id())) AND ((EXISTS ( SELECT 1
   FROM employee_advances advance
  WHERE ((advance.id = employee_advance_allocations.advance_id) AND (advance.tenant_id = employee_advance_allocations.tenant_id) AND (advance.employee_id = (select current_erp_employee_id()))))) OR (EXISTS ( SELECT 1
   FROM payroll_voucher_lines voucher_line
  WHERE ((voucher_line.id = employee_advance_allocations.voucher_line_id) AND (voucher_line.tenant_id = employee_advance_allocations.tenant_id) AND (voucher_line.employee_id = (select current_erp_employee_id()))))))))) $ddl$;
  execute $ddl$ alter policy "employee_advances_read_authorized" on public."employee_advances" using ((can_manage_tenant_payroll(tenant_id) OR ((tenant_id = (select erp_member_tenant_id())) AND (employee_id = (select current_erp_employee_id()))))) $ddl$;
  execute $ddl$ alter policy "employee_contracts_read_authorized" on public."employee_contracts" using ((can_manage_tenant_hr(tenant_id) OR can_manage_tenant_payroll(tenant_id) OR ((tenant_id = (select erp_member_tenant_id())) AND (employee_id = (select current_erp_employee_id()))))) $ddl$;
  execute $ddl$ alter policy "employee_default_shift_blocks_read_authorized" on public."employee_default_shift_blocks" using ((can_manage_tenant_hr(tenant_id) OR ((tenant_id = (select erp_member_tenant_id())) AND (employee_id = (select current_erp_employee_id()))) OR ((tenant_id = (select worker_portal_tenant_id())) AND (employee_id = (select worker_portal_employee_id()))))) $ddl$;
  execute $ddl$ alter policy "employee_planning_roles_read_authorized" on public."employee_planning_roles" using ((can_manage_tenant_hr(tenant_id) OR ((tenant_id = (select erp_member_tenant_id())) AND (employee_id = (select current_erp_employee_id()))) OR ((tenant_id = (select worker_portal_tenant_id())) AND (employee_id = (select worker_portal_employee_id()))))) $ddl$;
  execute $ddl$ alter policy "employees_read_authorized" on public."employees" using ((can_manage_tenant_hr(tenant_id) OR can_manage_tenant_payroll(tenant_id) OR ((tenant_id = (select erp_member_tenant_id())) AND (id = (select current_erp_employee_id()))))) $ddl$;
  execute $ddl$ alter policy "employment_contracts_read_authorized" on public."employment_contracts" using ((can_manage_tenant_hr(tenant_id) OR can_manage_tenant_payroll(tenant_id) OR ((tenant_id = (select erp_member_tenant_id())) AND (employee_id = (select current_erp_employee_id()))))) $ddl$;
  execute $ddl$ alter policy "erp_notifications_select" on public."erp_notifications" using (((tenant_id = (select user_tenant_id())) AND ((recipient_user_id IS NULL) OR (recipient_user_id = (select auth.uid()))))) $ddl$;
  execute $ddl$ alter policy "erp_notifications_update" on public."erp_notifications" using (((tenant_id = (select user_tenant_id())) AND ((recipient_user_id IS NULL) OR (recipient_user_id = (select auth.uid()))))) $ddl$;
  execute $ddl$ alter policy "expense_aggregate_save_operations_select" on public."expense_aggregate_save_operations" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "expense_attachments_delete" on public."expense_attachments" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "expense_attachments_insert" on public."expense_attachments" with check ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "expense_attachments_select" on public."expense_attachments" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "expense_attachments_update" on public."expense_attachments" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "expense_categories_delete" on public."expense_categories" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "expense_categories_insert" on public."expense_categories" with check ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "expense_categories_select" on public."expense_categories" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "expense_categories_update" on public."expense_categories" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "expense_lines_delete" on public."expense_lines" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "expense_lines_insert" on public."expense_lines" with check ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "expense_lines_select" on public."expense_lines" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "expense_lines_update" on public."expense_lines" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "expense_links_delete" on public."expense_links" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "expense_links_insert" on public."expense_links" with check ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "expense_links_select" on public."expense_links" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "expense_links_update" on public."expense_links" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "expense_payments_delete" on public."expense_payments" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "expense_payments_insert" on public."expense_payments" with check ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "expense_payments_select" on public."expense_payments" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "expense_payments_update" on public."expense_payments" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "expense_templates_delete" on public."expense_templates" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "expense_templates_insert" on public."expense_templates" with check ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "expense_templates_select" on public."expense_templates" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "expense_templates_update" on public."expense_templates" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "expenses_delete" on public."expenses" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "expenses_insert" on public."expenses" with check ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "expenses_select" on public."expenses" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "expenses_update" on public."expenses" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "f29_delete" on public."f29_declarations" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "f29_insert" on public."f29_declarations" with check ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "f29_select" on public."f29_declarations" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "f29_update" on public."f29_declarations" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "featured_products_delete" on public."featured_products" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "featured_products_insert" on public."featured_products" with check ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "featured_products_update" on public."featured_products" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "inventory_accounting_checkpoints_select" on public."inventory_accounting_checkpoints" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "inventory_accounting_operations_select" on public."inventory_accounting_operations" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "inventory_adjustments_tenant_isolation" on public."inventory_adjustments" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "job_roles_read_erp" on public."job_roles" using ((tenant_id = (select erp_member_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "job_status_supply_capability_events_select" on public."job_status_supply_capability_events" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "job_statuses_delete" on public."job_statuses" using (((tenant_id = (select user_tenant_id())) AND (is_system = false))) $ddl$;
  execute $ddl$ alter policy "job_statuses_insert" on public."job_statuses" with check ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "job_statuses_select" on public."job_statuses" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "job_statuses_update" on public."job_statuses" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "job_subjects_delete" on public."job_subjects" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "job_subjects_insert" on public."job_subjects" with check ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "job_subjects_select" on public."job_subjects" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "job_subjects_update" on public."job_subjects" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "journal_supersession_evidence_select" on public."journal_supersession_evidence" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "leave_requests_read_authorized" on public."leave_requests" using ((can_manage_tenant_hr(tenant_id) OR ((tenant_id = (select erp_member_tenant_id())) AND (employee_id = (select current_erp_employee_id()))))) $ddl$;
  execute $ddl$ alter policy "loyalty_delete" on public."loyalty" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "loyalty_insert" on public."loyalty" with check ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "loyalty_select" on public."loyalty" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "loyalty_update" on public."loyalty" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "mechanic_job_archive_events_select" on public."mechanic_job_archive_events" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "mechanic_job_bikes_delete" on public."mechanic_job_bikes" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "mechanic_job_bikes_insert" on public."mechanic_job_bikes" with check ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "mechanic_job_bikes_select" on public."mechanic_job_bikes" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "mechanic_job_bikes_update" on public."mechanic_job_bikes" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "mechanic_job_delivery_events_select" on public."mechanic_job_delivery_events" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "mechanic_job_items_delete" on public."mechanic_job_items" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "mechanic_job_items_insert" on public."mechanic_job_items" with check ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "mechanic_job_items_select" on public."mechanic_job_items" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "mechanic_job_items_update" on public."mechanic_job_items" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "mechanic_job_mode_events_select" on public."mechanic_job_mode_events" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "mechanic_job_status_transition_events_select" on public."mechanic_job_status_transition_events" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "job_status_transitions_select" on public."mechanic_job_status_transitions" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "task_prefs_delete" on public."mechanic_job_task_preferences" using (((user_id = (select auth.uid())) AND (tenant_id = (select user_tenant_id())))) $ddl$;
  execute $ddl$ alter policy "task_prefs_insert" on public."mechanic_job_task_preferences" with check (((user_id = (select auth.uid())) AND (tenant_id = (select user_tenant_id())))) $ddl$;
  execute $ddl$ alter policy "task_prefs_select" on public."mechanic_job_task_preferences" using (((user_id = (select auth.uid())) AND (tenant_id = (select user_tenant_id())))) $ddl$;
  execute $ddl$ alter policy "task_prefs_update" on public."mechanic_job_task_preferences" using (((user_id = (select auth.uid())) AND (tenant_id = (select user_tenant_id())))) $ddl$;
  execute $ddl$ alter policy "mechanic_job_tasks_delete" on public."mechanic_job_tasks" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "mechanic_job_tasks_insert" on public."mechanic_job_tasks" with check ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "mechanic_job_tasks_select" on public."mechanic_job_tasks" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "mechanic_job_tasks_update" on public."mechanic_job_tasks" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "mechanic_job_timeline_delete" on public."mechanic_job_timeline" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "mechanic_job_timeline_insert" on public."mechanic_job_timeline" with check ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "mechanic_job_timeline_select" on public."mechanic_job_timeline" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "mechanic_job_timeline_update" on public."mechanic_job_timeline" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "mechanic_job_warranty_claim_events_select" on public."mechanic_job_warranty_claim_events" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "public_mechanic_jobs_select_own" on public."mechanic_jobs" using ((EXISTS ( SELECT 1
   FROM customers customer
  WHERE (is_tenant_active(customer.tenant_id) AND (customer.id = mechanic_jobs.customer_id) AND (customer.tenant_id = mechanic_jobs.tenant_id) AND (customer.auth_user_id = (select auth.uid())) AND (customer.is_active IS TRUE))))) $ddl$;
  execute $ddl$ alter policy "medical_leaves_read_authorized" on public."medical_leaves" using ((can_manage_tenant_hr(tenant_id) OR ((tenant_id = (select erp_member_tenant_id())) AND (employee_id = (select current_erp_employee_id()))))) $ddl$;
  execute $ddl$ alter policy "message_reactions_delete_own" on public."message_reactions" using ((reactor_user_id = (select auth.uid()))) $ddl$;
  execute $ddl$ alter policy "message_reactions_insert_own" on public."message_reactions" with check (((reactor_user_id = (select auth.uid())) AND messaging_can_read_conversation_messages(conversation_id) AND (EXISTS ( SELECT 1
   FROM conversations c
  WHERE ((c.id = message_reactions.conversation_id) AND (c.tenant_id = message_reactions.tenant_id)))))) $ddl$;
  execute $ddl$ alter policy "message_reactions_update_own" on public."message_reactions" using ((reactor_user_id = (select auth.uid()))) with check ((reactor_user_id = (select auth.uid()))) $ddl$;
  execute $ddl$ alter policy "messages_insert_scoped" on public."messages" with check (((sender_id = (select auth.uid())) AND (external_provider IS NULL) AND (external_message_id IS NULL) AND (external_status IS NULL) AND (message_direction IS NULL) AND (((type = 'text'::text) AND (NOT (COALESCE(metadata, '{}'::jsonb) ?| ARRAY['url'::text, 'media_url'::text, 'image_url'::text, 'file_url'::text, 'documentUrl'::text, 'document_url'::text, 'storage_url'::text, 'public_url'::text, 'whatsapp_media_url'::text, 'download_url'::text, 'storageBucket'::text, 'storage_bucket'::text, 'storagePath'::text, 'storage_path'::text, 'type'::text, 'action_type'::text, 'target_id'::text, 'status'::text, 'response_note'::text, 'quote_id'::text, 'quoteId'::text, 'invoice_id'::text, 'invoiceId'::text, 'job_id'::text, 'jobId'::text, 'quotation_operation_key'::text, 'quotationOperationKey'::text])) AND (jsonb_typeof(COALESCE(metadata, '{}'::jsonb)) = 'object'::text)) OR ((type = 'action_request'::text) AND messaging_is_staff_in_tenant(tenant_id))) AND messaging_can_write_conversation(conversation_id) AND (EXISTS ( SELECT 1
   FROM conversations c
  WHERE ((c.id = messages.conversation_id) AND (c.tenant_id = messages.tenant_id)))))) $ddl$;
  execute $ddl$ alter policy "messaging_context_projection_audit_owner_insert" on public."messaging_context_projection_reconciliation_audit" with check (((select current_setting('app.messaging_context_projection_reconciliation'::text, true)) = '20260719213000'::text)) $ddl$;
  execute $ddl$ alter policy "messaging_context_projection_audit_owner_read" on public."messaging_context_projection_reconciliation_audit" using (((select current_setting('app.messaging_context_projection_reconciliation'::text, true)) = '20260719213000'::text)) $ddl$;
  execute $ddl$ alter policy "online_order_correction_events_staff_read" on public."online_order_correction_events" using (((tenant_id = (select user_tenant_id())) AND (EXISTS ( SELECT 1
   FROM user_profiles profile
  WHERE ((profile.user_id = (select auth.uid())) AND (profile.tenant_id = online_order_correction_events.tenant_id) AND (profile.is_active IS TRUE) AND ((profile.role = ANY (ARRAY['admin'::text, 'manager'::text, 'accountant'::text, 'cashier'::text])) OR (COALESCE((profile.permissions -> 'access_accounting'::text), 'false'::jsonb) = 'true'::jsonb))))))) $ddl$;
  execute $ddl$ alter policy "online_order_corrections_staff_read" on public."online_order_corrections" using (((tenant_id = (select user_tenant_id())) AND (EXISTS ( SELECT 1
   FROM user_profiles profile
  WHERE ((profile.user_id = (select auth.uid())) AND (profile.tenant_id = online_order_corrections.tenant_id) AND (profile.is_active IS TRUE) AND ((profile.role = ANY (ARRAY['admin'::text, 'manager'::text, 'accountant'::text, 'cashier'::text])) OR (COALESCE((profile.permissions -> 'access_accounting'::text), 'false'::jsonb) = 'true'::jsonb))))))) $ddl$;
  execute $ddl$ alter policy "online_order_events_select" on public."online_order_events" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "online_inventory_reservation_events_select" on public."online_order_inventory_reservation_events" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "online_inventory_reservations_select" on public."online_order_inventory_reservations" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "public_online_order_items_select_authenticated" on public."online_order_items" using ((EXISTS ( SELECT 1
   FROM (online_orders customer_order
     JOIN customers customer ON (((customer.id = customer_order.customer_id) AND (customer.tenant_id = customer_order.tenant_id))))
  WHERE ((customer_order.id = online_order_items.order_id) AND (customer_order.tenant_id = online_order_items.tenant_id) AND is_tenant_active(customer.tenant_id) AND (customer.auth_user_id = (select auth.uid())) AND (customer.is_active IS TRUE))))) $ddl$;
  execute $ddl$ alter policy "online_order_payment_preferences_staff_read" on public."online_order_payment_preferences" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "public_online_orders_select_authenticated" on public."online_orders" using ((EXISTS ( SELECT 1
   FROM customers customer
  WHERE (is_tenant_active(customer.tenant_id) AND (customer.id = online_orders.customer_id) AND (customer.tenant_id = online_orders.tenant_id) AND (customer.auth_user_id = (select auth.uid())) AND (customer.is_active IS TRUE))))) $ddl$;
  execute $ddl$ alter policy "online_shipping_rate_tiers_staff_write" on public."online_shipping_rate_tiers" using ((tenant_id = (select user_tenant_id()))) with check ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "order_items_delete" on public."order_items" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "order_items_insert" on public."order_items" with check ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "order_items_select" on public."order_items" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "order_items_update" on public."order_items" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "orders_delete" on public."orders" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "orders_insert" on public."orders" with check ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "orders_select" on public."orders" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "orders_update" on public."orders" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "payment_methods_delete" on public."payment_methods" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "payment_methods_insert" on public."payment_methods" with check ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "payment_methods_select" on public."payment_methods" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "payment_methods_update" on public."payment_methods" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "payments_delete" on public."payments" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "payments_insert" on public."payments" with check ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "payments_select" on public."payments" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "payments_update" on public."payments" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "payroll_beneficiary_aliases_delete_payroll" on public."payroll_beneficiary_aliases" using (((tenant_id = (select erp_member_tenant_id())) AND can_manage_tenant_payroll(tenant_id))) $ddl$;
  execute $ddl$ alter policy "payroll_beneficiary_aliases_insert_payroll" on public."payroll_beneficiary_aliases" with check (((tenant_id = (select erp_member_tenant_id())) AND can_manage_tenant_payroll(tenant_id) AND (created_by = (select auth.uid())))) $ddl$;
  execute $ddl$ alter policy "payroll_beneficiary_aliases_read_payroll" on public."payroll_beneficiary_aliases" using (((tenant_id = (select erp_member_tenant_id())) AND can_manage_tenant_payroll(tenant_id))) $ddl$;
  execute $ddl$ alter policy "payroll_beneficiary_aliases_update_payroll" on public."payroll_beneficiary_aliases" using (((tenant_id = (select erp_member_tenant_id())) AND can_manage_tenant_payroll(tenant_id))) with check (((tenant_id = (select erp_member_tenant_id())) AND can_manage_tenant_payroll(tenant_id))) $ddl$;
  execute $ddl$ alter policy "payroll_entries_read_authorized" on public."payroll_entries" using ((can_manage_tenant_payroll(tenant_id) OR ((tenant_id = (select erp_member_tenant_id())) AND (employee_id = (select current_erp_employee_id()))))) $ddl$;
  execute $ddl$ alter policy "payroll_records_read_authorized" on public."payroll_records" using ((can_manage_tenant_payroll(tenant_id) OR ((tenant_id = (select erp_member_tenant_id())) AND (employee_id = (select current_erp_employee_id()))))) $ddl$;
  execute $ddl$ alter policy "payroll_voucher_lines_read_authorized" on public."payroll_voucher_lines" using ((can_manage_tenant_payroll(tenant_id) OR ((tenant_id = (select erp_member_tenant_id())) AND (employee_id = (select current_erp_employee_id()))))) $ddl$;
  execute $ddl$ alter policy "planned_shifts_read_authorized" on public."planned_shifts" using ((can_manage_tenant_hr(tenant_id) OR ((tenant_id = (select erp_member_tenant_id())) AND (employee_id = (select current_erp_employee_id()))) OR ((tenant_id = (select worker_portal_tenant_id())) AND (employee_id = (select worker_portal_employee_id()))))) $ddl$;
  execute $ddl$ alter policy "planning_roles_read_authorized" on public."planning_roles" using (((tenant_id = (select erp_member_tenant_id())) OR (tenant_id = (select worker_portal_tenant_id())))) $ddl$;
  execute $ddl$ alter policy "product_brands_delete" on public."product_brands" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "product_brands_insert" on public."product_brands" with check ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "product_brands_update" on public."product_brands" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "product_bulk_edit_history_delete" on public."product_bulk_edit_history" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "product_bulk_edit_history_insert" on public."product_bulk_edit_history" with check ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "product_bulk_edit_history_select" on public."product_bulk_edit_history" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "product_bulk_edit_history_update" on public."product_bulk_edit_history" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "product_catalog_sync_events_select" on public."product_catalog_sync_events" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "product_categories_delete" on public."product_categories" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "product_categories_insert" on public."product_categories" with check ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "product_categories_update" on public."product_categories" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "product_gama_overrides_tenant_write" on public."product_gama_overrides" using ((tenant_id = (select user_tenant_id()))) with check ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "product_images_delete" on public."product_images" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "product_images_insert" on public."product_images" with check ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "product_images_select" on public."product_images" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "product_images_update" on public."product_images" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "product_import_stock_commands_select" on public."product_import_stock_commands" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "product_set_components_select" on public."product_set_components" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "product_spec_member_profile_events_tenant_read" on public."product_spec_member_profile_events" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "product_spec_member_profiles_tenant_read" on public."product_spec_member_profiles" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "product_spec_values_delete" on public."product_spec_values" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "product_spec_values_insert" on public."product_spec_values" with check ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "product_spec_values_select" on public."product_spec_values" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "product_spec_values_update" on public."product_spec_values" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "product_tax_classification_batches_select" on public."product_tax_classification_batches" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "product_tax_classification_events_select" on public."product_tax_classification_events" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "products_delete" on public."products" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "products_insert" on public."products" with check ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "products_update" on public."products" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "purchase_credit_note_settings_select" on public."purchase_credit_note_control_settings" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "purchase_credit_note_lines_select" on public."purchase_credit_note_lines" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "purchase_credit_notes_select" on public."purchase_credit_notes" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "purchase_invoice_source_components_select" on public."purchase_invoice_source_components" using (((tenant_id = (select user_tenant_id())) AND (EXISTS ( SELECT 1
   FROM user_profiles profile
  WHERE ((profile.user_id = (select auth.uid())) AND (profile.tenant_id = purchase_invoice_source_components.tenant_id) AND (profile.is_active IS TRUE)))))) $ddl$;
  execute $ddl$ alter policy "purchase_invoice_source_resolutions_select" on public."purchase_invoice_source_resolutions" using (((tenant_id = (select user_tenant_id())) AND (EXISTS ( SELECT 1
   FROM user_profiles profile
  WHERE ((profile.user_id = (select auth.uid())) AND (profile.tenant_id = purchase_invoice_source_resolutions.tenant_id) AND (profile.is_active IS TRUE)))))) $ddl$;
  execute $ddl$ alter policy "purchase_invoices_delete" on public."purchase_invoices" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "purchase_invoices_insert" on public."purchase_invoices" with check ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "purchase_invoices_select" on public."purchase_invoices" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "purchase_invoices_update" on public."purchase_invoices" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "purchase_order_items_tenant_isolation" on public."purchase_order_items" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "purchase_orders_tenant_isolation" on public."purchase_orders" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "purchase_payment_edit_events_select" on public."purchase_payment_edit_events" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "purchase_payments_delete" on public."purchase_payments" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "purchase_payments_insert" on public."purchase_payments" with check ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "purchase_payments_select" on public."purchase_payments" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "purchase_payments_update" on public."purchase_payments" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "purchase_plan_events_select" on public."purchase_plan_events" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "purchase_plan_lines_select" on public."purchase_plan_lines" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "purchase_plans_select" on public."purchase_plans" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "purchase_receipt_compatibility_events_select" on public."purchase_receipt_compatibility_events" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "purchase_receipt_control_settings_select" on public."purchase_receipt_control_settings" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "purchase_receipt_line_movements_select" on public."purchase_receipt_line_movements" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "purchase_receipt_lines_select" on public."purchase_receipt_lines" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "purchase_receipt_resolution_allocations_select" on public."purchase_receipt_resolution_allocations" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "purchase_receipt_resolution_cases_select" on public."purchase_receipt_resolution_cases" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "purchase_receipts_select" on public."purchase_receipts" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "purchase_supplier_refund_control_select" on public."purchase_supplier_refund_control_settings" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "purchase_supplier_refunds_select" on public."purchase_supplier_refunds" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "purchase_supplier_return_line_movements_select" on public."purchase_supplier_return_line_movements" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "purchase_supplier_return_lines_select" on public."purchase_supplier_return_lines" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "purchase_supplier_returns_select" on public."purchase_supplier_returns" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "reset_configurations_delete" on public."reset_configurations" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "reset_configurations_insert" on public."reset_configurations" with check ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "reset_configurations_select" on public."reset_configurations" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "reset_configurations_update" on public."reset_configurations" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "sales_channel_payment_events_select" on public."sales_channel_payment_events" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "sales_channel_payment_processing_staff_read" on public."sales_channel_payment_processing" using (((tenant_id = (select user_tenant_id())) AND (EXISTS ( SELECT 1
   FROM user_profiles profile
  WHERE ((profile.user_id = (select auth.uid())) AND (profile.tenant_id = sales_channel_payment_processing.tenant_id) AND (profile.is_active IS TRUE) AND ((profile.role = ANY (ARRAY['admin'::text, 'manager'::text, 'cashier'::text, 'accountant'::text])) OR (COALESCE((profile.permissions -> 'create_invoices'::text), 'false'::jsonb) = 'true'::jsonb) OR (COALESCE((profile.permissions -> 'access_accounting'::text), 'false'::jsonb) = 'true'::jsonb))))))) $ddl$;
  execute $ddl$ alter policy "sales_channel_payment_processing_attempts_staff_read" on public."sales_channel_payment_processing_attempts" using (((tenant_id = (select user_tenant_id())) AND (EXISTS ( SELECT 1
   FROM user_profiles profile
  WHERE ((profile.user_id = (select auth.uid())) AND (profile.tenant_id = sales_channel_payment_processing_attempts.tenant_id) AND (profile.is_active IS TRUE) AND ((profile.role = ANY (ARRAY['admin'::text, 'manager'::text, 'cashier'::text, 'accountant'::text])) OR (COALESCE((profile.permissions -> 'create_invoices'::text), 'false'::jsonb) = 'true'::jsonb) OR (COALESCE((profile.permissions -> 'access_accounting'::text), 'false'::jsonb) = 'true'::jsonb))))))) $ddl$;
  execute $ddl$ alter policy "sales_credit_settings_select" on public."sales_credit_note_control_settings" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "sales_credit_lines_select" on public."sales_credit_note_lines" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "sales_credit_notes_select" on public."sales_credit_notes" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "sales_customer_refund_control_select" on public."sales_customer_refund_control_settings" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "sales_customer_refunds_select" on public."sales_customer_refunds" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "sales_invoices_delete" on public."sales_invoices" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "sales_invoices_insert" on public."sales_invoices" with check ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "sales_invoices_update" on public."sales_invoices" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "sales_order_items_tenant_isolation" on public."sales_order_items" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "sales_orders_tenant_isolation" on public."sales_orders" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "sales_payment_command_receipts_select" on public."sales_payment_command_receipts" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "sales_payment_edit_events_select" on public."sales_payment_edit_events" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "sales_payments_delete" on public."sales_payments" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "sales_payments_insert" on public."sales_payments" with check ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "sales_payments_select" on public."sales_payments" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "sales_payments_update" on public."sales_payments" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "sales_return_settings_select" on public."sales_return_control_settings" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "sales_return_movements_select" on public."sales_return_line_movements" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "sales_return_lines_select" on public."sales_return_lines" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "sales_return_quarantine_select" on public."sales_return_quarantine" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "sales_return_quarantine_resolution_movements_select" on public."sales_return_quarantine_resolution_movements" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "sales_return_quarantine_resolutions_select" on public."sales_return_quarantine_resolutions" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "sales_returns_select" on public."sales_returns" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "service_packages_delete" on public."service_packages" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "service_packages_insert" on public."service_packages" with check ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "service_packages_select" on public."service_packages" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "service_packages_update" on public."service_packages" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "svc_product_map_delete" on public."service_product_profile_mappings" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "svc_product_map_insert" on public."service_product_profile_mappings" with check ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "svc_product_map_select" on public."service_product_profile_mappings" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "svc_product_map_update" on public."service_product_profile_mappings" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "svc_profile_part_rules_delete" on public."service_profile_part_rules" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "svc_profile_part_rules_insert" on public."service_profile_part_rules" with check ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "svc_profile_part_rules_select" on public."service_profile_part_rules" using (((tenant_id IS NULL) OR (tenant_id = (select user_tenant_id())))) $ddl$;
  execute $ddl$ alter policy "svc_profile_part_rules_update" on public."service_profile_part_rules" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "svc_profile_questions_delete" on public."service_profile_questions" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "svc_profile_questions_insert" on public."service_profile_questions" with check ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "svc_profile_questions_select" on public."service_profile_questions" using (((tenant_id IS NULL) OR (tenant_id = (select user_tenant_id())))) $ddl$;
  execute $ddl$ alter policy "svc_profile_questions_update" on public."service_profile_questions" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "svc_profile_targets_delete" on public."service_profile_targets" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "svc_profile_targets_insert" on public."service_profile_targets" with check ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "svc_profile_targets_select" on public."service_profile_targets" using (((tenant_id IS NULL) OR (tenant_id = (select user_tenant_id())))) $ddl$;
  execute $ddl$ alter policy "svc_profile_targets_update" on public."service_profile_targets" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "svc_profile_task_templates_delete" on public."service_profile_task_templates" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "svc_profile_task_templates_insert" on public."service_profile_task_templates" with check ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "svc_profile_task_templates_select" on public."service_profile_task_templates" using (((tenant_id IS NULL) OR (tenant_id = (select user_tenant_id())))) $ddl$;
  execute $ddl$ alter policy "svc_profile_task_templates_update" on public."service_profile_task_templates" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "service_profiles_delete" on public."service_profiles" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "service_profiles_insert" on public."service_profiles" with check ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "service_profiles_select" on public."service_profiles" using (((tenant_id IS NULL) OR (tenant_id = (select user_tenant_id())))) $ddl$;
  execute $ddl$ alter policy "service_profiles_update" on public."service_profiles" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "shift_change_requests_read_authorized" on public."shift_change_requests" using ((can_manage_tenant_hr(tenant_id) OR ((tenant_id = (select erp_member_tenant_id())) AND (employee_id = (select current_erp_employee_id()))) OR ((tenant_id = (select worker_portal_tenant_id())) AND (employee_id = (select worker_portal_employee_id()))))) $ddl$;
  execute $ddl$ alter policy "shifts_read_authorized" on public."shifts" using ((can_manage_tenant_hr(tenant_id) OR ((tenant_id = (select erp_member_tenant_id())) AND (employee_id = (select current_erp_employee_id()))))) $ddl$;
  execute $ddl$ alter policy "smart_purchase_list_delete" on public."smart_purchase_list" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "smart_purchase_list_insert" on public."smart_purchase_list" with check ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "smart_purchase_list_select" on public."smart_purchase_list" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "smart_purchase_list_update" on public."smart_purchase_list" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "smart_task_user_state_delete" on public."smart_task_user_state" using ((user_id = (select auth.uid()))) $ddl$;
  execute $ddl$ alter policy "smart_task_user_state_insert" on public."smart_task_user_state" with check (((user_id = (select auth.uid())) AND smart_task_can_view_v1(task_id))) $ddl$;
  execute $ddl$ alter policy "smart_task_user_state_select" on public."smart_task_user_state" using ((user_id = (select auth.uid()))) $ddl$;
  execute $ddl$ alter policy "smart_task_user_state_update" on public."smart_task_user_state" using ((user_id = (select auth.uid()))) with check ((user_id = (select auth.uid()))) $ddl$;
  execute $ddl$ alter policy "smart_tasks_insert" on public."smart_tasks" with check (((tenant_id = (select user_tenant_id())) AND (created_by = (select auth.uid())))) $ddl$;
  execute $ddl$ alter policy "smart_tasks_select" on public."smart_tasks" using ((((tenant_id = (select user_tenant_id())) AND ((visibility = ANY (ARRAY['team'::text, 'company'::text])) OR (created_by = (select auth.uid())) OR (assigned_to = (select auth.uid())))) OR (assigned_to = (select auth.uid())))) $ddl$;
  execute $ddl$ alter policy "smart_tasks_update" on public."smart_tasks" using (((tenant_id = (select user_tenant_id())) AND ((created_by = (select auth.uid())) OR (assigned_to = (select auth.uid())) OR can_manage_tenant_users(tenant_id)))) with check ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "spec_definition_values_select" on public."spec_definition_values" using (((tenant_id IS NULL) OR (tenant_id = (select user_tenant_id())))) $ddl$;
  execute $ddl$ alter policy "spec_definitions_delete" on public."spec_definitions" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "spec_definitions_insert" on public."spec_definitions" with check ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "spec_definitions_select" on public."spec_definitions" using (((tenant_id IS NULL) OR (tenant_id = (select user_tenant_id())))) $ddl$;
  execute $ddl$ alter policy "spec_definitions_update" on public."spec_definitions" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "spec_fact_readings_select" on public."spec_fact_readings" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "spec_fact_values_write" on public."spec_fact_values" using ((EXISTS ( SELECT 1
   FROM spec_facts f
  WHERE ((f.id = spec_fact_values.fact_id) AND (f.tenant_id = (select user_tenant_id())))))) with check ((EXISTS ( SELECT 1
   FROM spec_facts f
  WHERE ((f.id = spec_fact_values.fact_id) AND (f.tenant_id = (select user_tenant_id())))))) $ddl$;
  execute $ddl$ alter policy "spec_facts_write" on public."spec_facts" using ((tenant_id = (select user_tenant_id()))) with check ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "spec_template_fields_delete" on public."spec_template_fields" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "spec_template_fields_insert" on public."spec_template_fields" with check ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "spec_template_fields_select" on public."spec_template_fields" using (((tenant_id IS NULL) OR (tenant_id = (select user_tenant_id())))) $ddl$;
  execute $ddl$ alter policy "spec_template_fields_update" on public."spec_template_fields" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "spec_templates_delete" on public."spec_templates" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "spec_templates_insert" on public."spec_templates" with check ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "spec_templates_select" on public."spec_templates" using (((tenant_id IS NULL) OR (tenant_id = (select user_tenant_id())))) $ddl$;
  execute $ddl$ alter policy "spec_templates_update" on public."spec_templates" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "Tenant users can delete cells" on public."spreadsheet_cells" using ((EXISTS ( SELECT 1
   FROM spreadsheets s
  WHERE ((s.id = spreadsheet_cells.spreadsheet_id) AND (s.tenant_id = (select user_tenant_id())))))) $ddl$;
  execute $ddl$ alter policy "Tenant users can insert cells" on public."spreadsheet_cells" with check ((EXISTS ( SELECT 1
   FROM spreadsheets s
  WHERE ((s.id = spreadsheet_cells.spreadsheet_id) AND (s.tenant_id = (select user_tenant_id())))))) $ddl$;
  execute $ddl$ alter policy "Tenant users can update cells" on public."spreadsheet_cells" using ((EXISTS ( SELECT 1
   FROM spreadsheets s
  WHERE ((s.id = spreadsheet_cells.spreadsheet_id) AND (s.tenant_id = (select user_tenant_id())))))) $ddl$;
  execute $ddl$ alter policy "Tenant users can view cells" on public."spreadsheet_cells" using ((EXISTS ( SELECT 1
   FROM spreadsheets s
  WHERE ((s.id = spreadsheet_cells.spreadsheet_id) AND (s.tenant_id = (select user_tenant_id())))))) $ddl$;
  execute $ddl$ alter policy "Tenant users can create spreadsheets" on public."spreadsheets" with check ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "Tenant users can delete spreadsheets" on public."spreadsheets" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "Tenant users can update spreadsheets" on public."spreadsheets" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "Tenant users can view spreadsheets" on public."spreadsheets" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "stock_adjustments_delete" on public."stock_adjustments" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "stock_adjustments_insert" on public."stock_adjustments" with check ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "stock_adjustments_select" on public."stock_adjustments" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "stock_adjustments_update" on public."stock_adjustments" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "stock_movements_insert" on public."stock_movements" with check ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "stock_movements_select" on public."stock_movements" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "supplier_availability_checks_tenant" on public."supplier_availability_checks" using ((tenant_id = (select user_tenant_id()))) with check ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "supplier_contacts_tenant" on public."supplier_contacts" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "supplier_need_portal_searches_tenant_select" on public."supplier_need_portal_searches" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "supplier_portal_probes_tenant" on public."supplier_portal_probes" using ((tenant_id = (select user_tenant_id()))) with check ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "supplier_product_aliases_select" on public."supplier_product_aliases" using (((tenant_id = (select user_tenant_id())) AND (EXISTS ( SELECT 1
   FROM user_profiles profile
  WHERE ((profile.user_id = (select auth.uid())) AND (profile.tenant_id = supplier_product_aliases.tenant_id) AND (profile.is_active IS TRUE)))))) $ddl$;
  execute $ddl$ alter policy "supplier_variant_resolution_corrections_select" on public."supplier_variant_resolution_corrections" using (((tenant_id = (select user_tenant_id())) AND (EXISTS ( SELECT 1
   FROM user_profiles profile
  WHERE ((profile.user_id = (select auth.uid())) AND (profile.tenant_id = supplier_variant_resolution_corrections.tenant_id) AND (profile.is_active IS TRUE)))))) $ddl$;
  execute $ddl$ alter policy "supplier_variant_resolution_edges_select" on public."supplier_variant_resolution_edges" using (((tenant_id = (select user_tenant_id())) AND (EXISTS ( SELECT 1
   FROM user_profiles profile
  WHERE ((profile.user_id = (select auth.uid())) AND (profile.tenant_id = supplier_variant_resolution_edges.tenant_id) AND (profile.is_active IS TRUE)))))) $ddl$;
  execute $ddl$ alter policy "supplier_variant_resolution_revisions_select" on public."supplier_variant_resolution_revisions" using (((tenant_id = (select user_tenant_id())) AND (EXISTS ( SELECT 1
   FROM user_profiles profile
  WHERE ((profile.user_id = (select auth.uid())) AND (profile.tenant_id = supplier_variant_resolution_revisions.tenant_id) AND (profile.is_active IS TRUE)))))) $ddl$;
  execute $ddl$ alter policy "suppliers_delete" on public."suppliers" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "suppliers_insert" on public."suppliers" with check ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "suppliers_select" on public."suppliers" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "suppliers_update" on public."suppliers" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "supply_need_commercial_revisions_select" on public."supply_need_commercial_revisions" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "supply_need_events_select" on public."supply_need_events" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "supply_need_interpretation_revisions_select" on public."supply_need_interpretation_revisions" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "supply_needs_select" on public."supply_needs" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "tenants_manager_update_own" on public."tenants" using (((id = (select user_tenant_id())) AND can_manage_tenant_users(id))) with check (((id = (select user_tenant_id())) AND can_manage_tenant_users(id))) $ddl$;
  execute $ddl$ alter policy "tenants_member_read_own" on public."tenants" using ((id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "transactional_email_delivery_phase_events_select" on public."transactional_email_delivery_phase_events" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "transactional_email_outbox_select" on public."transactional_email_outbox" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "transactional_email_provider_events_select" on public."transactional_email_provider_events" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "transactional_email_settings_select" on public."transactional_email_settings" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "transactional_email_suppressions_select" on public."transactional_email_suppressions" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "user_activity_log_insert" on public."user_activity_log" with check ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "user_activity_log_select" on public."user_activity_log" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "Users can manage their own FCM tokens" on public."user_fcm_tokens" using ((user_id = (select auth.uid()))) with check ((user_id = (select auth.uid()))) $ddl$;
  execute $ddl$ alter policy "user_profiles_read_own_or_managed_tenant" on public."user_profiles" using (((user_id = (select auth.uid())) OR can_manage_tenant_users(tenant_id))) $ddl$;
  execute $ddl$ alter policy "users_profiles_tenant_isolation" on public."users_profiles" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "vehicles_tenant_isolation" on public."vehicles" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "warehouses_delete" on public."warehouses" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "warehouses_insert" on public."warehouses" with check ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "warehouses_select" on public."warehouses" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "warehouses_update" on public."warehouses" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "website_backups_delete" on public."website_backups" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "website_backups_insert" on public."website_backups" with check ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "website_backups_select" on public."website_backups" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "website_backups_update" on public."website_backups" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "website_banners_delete" on public."website_banners" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "website_banners_insert" on public."website_banners" with check ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "website_banners_update" on public."website_banners" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "website_content_delete" on public."website_content" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "website_content_insert" on public."website_content" with check ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "website_content_update" on public."website_content" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "website_navigation_delete" on public."website_navigation" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "website_navigation_insert" on public."website_navigation" with check ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "website_navigation_update" on public."website_navigation" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "whatsapp_channels_delete" on public."whatsapp_channels" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "whatsapp_channels_insert" on public."whatsapp_channels" with check ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "whatsapp_channels_select" on public."whatsapp_channels" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "whatsapp_channels_update" on public."whatsapp_channels" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "whatsapp_bindings_delete" on public."whatsapp_conversation_bindings" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "whatsapp_bindings_insert" on public."whatsapp_conversation_bindings" with check ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "whatsapp_bindings_select" on public."whatsapp_conversation_bindings" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "whatsapp_bindings_update" on public."whatsapp_conversation_bindings" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "wheel_builds_delete" on public."wheel_builds" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "wheel_builds_insert" on public."wheel_builds" with check ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "wheel_builds_select" on public."wheel_builds" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "wheel_builds_update" on public."wheel_builds" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "wheel_hubs_delete" on public."wheel_hubs" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "wheel_hubs_insert" on public."wheel_hubs" with check ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "wheel_hubs_select" on public."wheel_hubs" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "wheel_hubs_update" on public."wheel_hubs" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "wheel_rims_delete" on public."wheel_rims" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "wheel_rims_insert" on public."wheel_rims" with check ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "wheel_rims_select" on public."wheel_rims" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "wheel_rims_update" on public."wheel_rims" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "wheel_spokes_delete" on public."wheel_spokes" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "wheel_spokes_insert" on public."wheel_spokes" with check ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "wheel_spokes_select" on public."wheel_spokes" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "wheel_spokes_update" on public."wheel_spokes" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "work_order_items_tenant_isolation" on public."work_order_items" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "work_orders_delete" on public."work_orders" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "work_orders_insert" on public."work_orders" with check ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "work_orders_select" on public."work_orders" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "work_orders_update" on public."work_orders" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "work_schedules_read_erp" on public."work_schedules" using ((tenant_id = (select erp_member_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "workshop_financial_backfill_rows_select" on public."workshop_financial_backfill_rows" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "workshop_financial_backfill_runs_select" on public."workshop_financial_backfill_runs" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "workshop_inventory_commitment_events_select" on public."workshop_inventory_commitment_events" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "workshop_inventory_commitments_select" on public."workshop_inventory_commitments" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "workshop_invoice_control_events_select" on public."workshop_invoice_control_events" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "workshop_invoice_control_settings_select" on public."workshop_invoice_control_settings" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "workshop_line_identity_backfill_rows_select" on public."workshop_line_identity_backfill_rows" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "workshop_line_identity_backfill_runs_select" on public."workshop_line_identity_backfill_runs" using ((tenant_id = (select user_tenant_id()))) $ddl$;
  execute $ddl$ alter policy "Users can delete own zoho tokens" on public."zoho_tokens" using (((select auth.uid()) = user_id)) $ddl$;
  execute $ddl$ alter policy "Users can insert own zoho tokens" on public."zoho_tokens" with check (((select auth.uid()) = user_id)) $ddl$;
  execute $ddl$ alter policy "Users can update own zoho tokens" on public."zoho_tokens" using (((select auth.uid()) = user_id)) $ddl$;
  execute $ddl$ alter policy "Users can view own zoho tokens" on public."zoho_tokens" using (((select auth.uid()) = user_id)) $ddl$;
end
$block$;
commit;
