-- Read-back for 20260916000100. Each denominator is catalog-derived; run it before the deploy and require a failure.
select 1 / (count(*) = 0)::integer as no_per_row_stable_calls_left
from pg_policies
where schemaname = 'public'
  and (coalesce(qual, '') || ' ' || coalesce(with_check, ''))
      ~* '(?<!select )(?<![[:alnum:]_.])(public\.)?((auth\.uid|auth\.role|auth\.jwt|auth\.email|user_tenant_id|erp_member_tenant_id|current_erp_employee_id|worker_portal_tenant_id|worker_portal_employee_id)|current_setting)\(';
select 1 / (count(*) = 0)::integer as merged_policies_gone
from pg_policies where schemaname = 'public' and (tablename, policyname) in (('email_push_subscriptions', 'users_view_own_push_subscriptions'), ('product_gama_overrides', 'product_gama_overrides_tenant_read'), ('spec_facts', 'spec_facts_select'), ('spec_fact_values', 'spec_fact_values_select'), ('online_shipping_rate_tiers', 'online_shipping_rate_tiers_staff_read'), ('categories', 'public_categories_select_authenticated'), ('featured_products', 'public_featured_products_select_authenticated'), ('product_brands', 'public_product_brands_select_authenticated'), ('product_categories', 'public_product_categories_select_authenticated'), ('products', 'public_products_select_authenticated'), ('website_banners', 'public_website_banners_select_authenticated'), ('website_content', 'public_website_content_select_authenticated'), ('sales_invoices', 'Customers can view their own invoices'), ('business_sites', 'business_sites_write'), ('journal_entries', 'journal_entries_write_accounting'), ('journal_lines', 'journal_lines_write_accounting'), ('spec_definition_values', 'spec_definition_values_write'));
select 1 / (count(*) = 21)::integer as merged_policies_present
from pg_policies where schemaname = 'public' and permissive = 'PERMISSIVE'
  and (tablename, policyname, cmd, roles::text) in (('categories', 'categories_select', 'SELECT', '{authenticated}'), ('featured_products', 'featured_products_select', 'SELECT', '{authenticated}'), ('product_brands', 'product_brands_select', 'SELECT', '{authenticated}'), ('product_categories', 'product_categories_select', 'SELECT', '{authenticated}'), ('products', 'products_select', 'SELECT', '{authenticated}'), ('website_banners', 'website_banners_select', 'SELECT', '{authenticated}'), ('website_content', 'website_content_select', 'SELECT', '{authenticated}'), ('website_navigation', 'website_navigation_select', 'SELECT', '{authenticated}'), ('sales_invoices', 'sales_invoices_select', 'SELECT', '{authenticated}'), ('business_sites', 'business_sites_insert', 'INSERT', '{authenticated}'), ('business_sites', 'business_sites_update', 'UPDATE', '{authenticated}'), ('business_sites', 'business_sites_delete', 'DELETE', '{authenticated}'), ('journal_entries', 'journal_entries_insert_accounting', 'INSERT', '{authenticated}'), ('journal_entries', 'journal_entries_update_accounting', 'UPDATE', '{authenticated}'), ('journal_entries', 'journal_entries_delete_accounting', 'DELETE', '{authenticated}'), ('journal_lines', 'journal_lines_insert_accounting', 'INSERT', '{authenticated}'), ('journal_lines', 'journal_lines_update_accounting', 'UPDATE', '{authenticated}'), ('journal_lines', 'journal_lines_delete_accounting', 'DELETE', '{authenticated}'), ('spec_definition_values', 'spec_definition_values_insert', 'INSERT', '{authenticated}'), ('spec_definition_values', 'spec_definition_values_update', 'UPDATE', '{authenticated}'), ('spec_definition_values', 'spec_definition_values_delete', 'DELETE', '{authenticated}'));
select 1 / (count(*) = 1)::integer as website_navigation_public_is_anon
from pg_policies where schemaname = 'public' and tablename = 'website_navigation'
  and policyname = 'website_navigation_select_public' and roles::text = '{anon}';
select 1 / (count(*) = 1)::integer as categories_one_permissive_select_for_authenticated
from pg_policies where schemaname = 'public' and tablename = 'categories' and permissive = 'PERMISSIVE'
  and cmd in ('SELECT', 'ALL') and (roles::name[] && array['authenticated', 'public']::name[]);
select 1 / (count(*) = 1)::integer as featured_products_one_permissive_select_for_authenticated
from pg_policies where schemaname = 'public' and tablename = 'featured_products' and permissive = 'PERMISSIVE'
  and cmd in ('SELECT', 'ALL') and (roles::name[] && array['authenticated', 'public']::name[]);
select 1 / (count(*) = 1)::integer as product_brands_one_permissive_select_for_authenticated
from pg_policies where schemaname = 'public' and tablename = 'product_brands' and permissive = 'PERMISSIVE'
  and cmd in ('SELECT', 'ALL') and (roles::name[] && array['authenticated', 'public']::name[]);
select 1 / (count(*) = 1)::integer as product_categories_one_permissive_select_for_authenticated
from pg_policies where schemaname = 'public' and tablename = 'product_categories' and permissive = 'PERMISSIVE'
  and cmd in ('SELECT', 'ALL') and (roles::name[] && array['authenticated', 'public']::name[]);
select 1 / (count(*) = 1)::integer as products_one_permissive_select_for_authenticated
from pg_policies where schemaname = 'public' and tablename = 'products' and permissive = 'PERMISSIVE'
  and cmd in ('SELECT', 'ALL') and (roles::name[] && array['authenticated', 'public']::name[]);
select 1 / (count(*) = 1)::integer as website_banners_one_permissive_select_for_authenticated
from pg_policies where schemaname = 'public' and tablename = 'website_banners' and permissive = 'PERMISSIVE'
  and cmd in ('SELECT', 'ALL') and (roles::name[] && array['authenticated', 'public']::name[]);
select 1 / (count(*) = 1)::integer as website_content_one_permissive_select_for_authenticated
from pg_policies where schemaname = 'public' and tablename = 'website_content' and permissive = 'PERMISSIVE'
  and cmd in ('SELECT', 'ALL') and (roles::name[] && array['authenticated', 'public']::name[]);
select 1 / (count(*) = 1)::integer as website_navigation_one_permissive_select_for_authenticated
from pg_policies where schemaname = 'public' and tablename = 'website_navigation' and permissive = 'PERMISSIVE'
  and cmd in ('SELECT', 'ALL') and (roles::name[] && array['authenticated', 'public']::name[]);
select 1 / (count(*) = 1)::integer as sales_invoices_one_permissive_select_for_authenticated
from pg_policies where schemaname = 'public' and tablename = 'sales_invoices' and permissive = 'PERMISSIVE'
  and cmd in ('SELECT', 'ALL') and (roles::name[] && array['authenticated', 'public']::name[]);
select 1 / (count(*) = 1)::integer as email_push_subscriptions_one_permissive_select_for_authenticated
from pg_policies where schemaname = 'public' and tablename = 'email_push_subscriptions' and permissive = 'PERMISSIVE'
  and cmd in ('SELECT', 'ALL') and (roles::name[] && array['authenticated', 'public']::name[]);
select 1 / (count(*) = 1)::integer as product_gama_overrides_one_permissive_select_for_authenticated
from pg_policies where schemaname = 'public' and tablename = 'product_gama_overrides' and permissive = 'PERMISSIVE'
  and cmd in ('SELECT', 'ALL') and (roles::name[] && array['authenticated', 'public']::name[]);
select 1 / (count(*) = 1)::integer as spec_facts_one_permissive_select_for_authenticated
from pg_policies where schemaname = 'public' and tablename = 'spec_facts' and permissive = 'PERMISSIVE'
  and cmd in ('SELECT', 'ALL') and (roles::name[] && array['authenticated', 'public']::name[]);
select 1 / (count(*) = 1)::integer as spec_fact_values_one_permissive_select_for_authenticated
from pg_policies where schemaname = 'public' and tablename = 'spec_fact_values' and permissive = 'PERMISSIVE'
  and cmd in ('SELECT', 'ALL') and (roles::name[] && array['authenticated', 'public']::name[]);
select 1 / (count(*) = 1)::integer as online_shipping_rate_tiers_one_permissive_select_for_authenticated
from pg_policies where schemaname = 'public' and tablename = 'online_shipping_rate_tiers' and permissive = 'PERMISSIVE'
  and cmd in ('SELECT', 'ALL') and (roles::name[] && array['authenticated', 'public']::name[]);
select 1 / (count(*) = 1)::integer as business_sites_one_permissive_select_for_authenticated
from pg_policies where schemaname = 'public' and tablename = 'business_sites' and permissive = 'PERMISSIVE'
  and cmd in ('SELECT', 'ALL') and (roles::name[] && array['authenticated', 'public']::name[]);
select 1 / (count(*) = 1)::integer as journal_entries_one_permissive_select_for_authenticated
from pg_policies where schemaname = 'public' and tablename = 'journal_entries' and permissive = 'PERMISSIVE'
  and cmd in ('SELECT', 'ALL') and (roles::name[] && array['authenticated', 'public']::name[]);
select 1 / (count(*) = 1)::integer as journal_lines_one_permissive_select_for_authenticated
from pg_policies where schemaname = 'public' and tablename = 'journal_lines' and permissive = 'PERMISSIVE'
  and cmd in ('SELECT', 'ALL') and (roles::name[] && array['authenticated', 'public']::name[]);
select 1 / (count(*) = 1)::integer as spec_definition_values_one_permissive_select_for_authenticated
from pg_policies where schemaname = 'public' and tablename = 'spec_definition_values' and permissive = 'PERMISSIVE'
  and cmd in ('SELECT', 'ALL') and (roles::name[] && array['authenticated', 'public']::name[]);
