// Auth Screens
export '../screens/login_screen.dart';
export '../screens/reset_password_screen.dart';
export '../screens/dashboard_screen.dart';
export '../../modules/worker_portal/pages/worker_login_page.dart';
export '../../modules/worker_portal/pages/worker_home_page.dart';

// ERP / Admin Modules
export '../../modules/auth/pages/accept_invitation_page.dart';
export '../../modules/accounting/pages/account_list_page.dart';
export '../../modules/accounting/pages/account_form_page.dart';
export '../../modules/accounting/pages/journal_entry_list_page.dart';
export '../../modules/accounting/pages/journal_entry_form_page.dart';
export '../../modules/accounting/pages/financial_reports_hub_page.dart';
export '../../modules/accounting/pages/income_statement_page.dart';
export '../../modules/accounting/pages/balance_sheet_page.dart';
export '../../modules/accounting/pages/expense_list_page.dart';
export '../../modules/accounting/pages/expense_detail_page.dart';
export '../../modules/accounting/pages/expense_form_page.dart';
export '../../modules/accounting/pages/expense_categories_page.dart';
export '../../modules/tax_reports/pages/f29_dashboard_page.dart';
export '../../modules/crm/pages/customer_list_page.dart';
export '../../modules/crm/pages/customer_form_page.dart';
export '../../modules/crm/pages/customer_bike_directory_page.dart';
export '../../modules/bikeshop/pages/client_logbook_page.dart';
export '../../modules/bikeshop/pages/pegas_table_page.dart';
export '../../modules/bikeshop/pages/job_statuses_page.dart';
export '../../modules/bikeshop/pages/job_subjects_page.dart';
export '../../modules/bikeshop/pages/mechanic_job_form_page.dart';
export '../../modules/bikeshop/pages/workshop_calendar_page.dart';
export '../../modules/bikeshop/pages/bike_brands_page.dart';
export '../../modules/bikeshop/pages/wheel_hubs_page.dart';
export '../../modules/bikeshop/pages/wheel_rims_page.dart';
export '../../modules/bikeshop/pages/wheel_spokes_page.dart';
export '../../modules/bikeshop/pages/wheel_builder_wizard_page.dart';
export '../../modules/bikeshop/pages/spoke_length_calculator_page.dart';
export '../../modules/bikeshop/pages/bike_encyclopedia_page.dart';
export '../../modules/inventory/pages/product_list_page.dart';
export '../../modules/inventory/pages/product_form_page.dart';
export '../../modules/inventory/pages/product_import_page.dart';
export '../../modules/inventory/models/inventory_models.dart';
export '../../modules/inventory/pages/hierarchical_category_page.dart';
export '../../modules/inventory/pages/category_form_page.dart';
export '../../modules/inventory/pages/brand_list_page.dart';
export '../../modules/inventory/pages/brand_form_page.dart';
export '../../modules/inventory/pages/stock_movements_page.dart';
export '../../modules/sales/pages/invoice_list_page.dart';
export '../../modules/sales/pages/invoice_form_page.dart';
export '../../modules/sales/pages/invoice_payment_page.dart';
export '../../modules/sales/pages/payment_form_page.dart';
export '../../modules/sales/pages/sales_reports_page.dart';
export '../../modules/sales/pages/reports/sales_by_product_page.dart';
export '../../modules/sales/pages/reports/sales_by_product_detail_page.dart';
export '../../modules/sales/pages/reports/sales_by_customer_page.dart';
export '../../modules/purchases/pages/supplier_list_page.dart';
export '../../modules/purchases/pages/supplier_form_page.dart';
export '../../modules/purchases/pages/purchase_invoice_list_page.dart';
export '../../modules/purchases/pages/purchase_invoice_form_page.dart';
export '../../modules/purchases/pages/purchase_payment_form_page.dart';
export '../../modules/purchases/pages/purchase_payments_list_page.dart';
export '../../modules/purchases/pages/smart_purchase_list_page.dart';
export '../../modules/pos/pages/pos_dashboard_page.dart';
export '../../modules/pos/pages/pos_cart_page.dart';
export '../../modules/pos/pages/pos_payment_page.dart';
export '../../modules/pos/pages/pos_receipt_page.dart';
export '../../modules/pos/models/pos_transaction.dart';
export '../../modules/settings/pages/settings_page.dart';
export '../../modules/settings/pages/factory_reset_page_new.dart';
export '../../modules/settings/pages/backup_management_page.dart';
export '../../modules/settings/pages/appearance_settings_page.dart';
export '../../modules/settings/pages/business_hours_settings_page.dart';
export '../../modules/settings/pages/company_settings_page.dart';
export '../../modules/settings/pages/user_management_page.dart';
export '../../modules/settings/pages/payment_methods_settings_page.dart';
export '../../modules/settings/pages/whatsapp_settings_page.dart';
export '../../modules/settings/pages/bluetooth_scanner_page.dart';
export '../../modules/settings/pages/keyboard_scanner_page.dart';
export '../../modules/settings/pages/remote_scanner_page.dart';
export '../../modules/settings/pages/niimbot_settings_page.dart';
export '../../modules/settings/pages/notification_settings_page.dart';
export '../../modules/label_printer/label_printer_page.dart';
export '../../modules/hr/pages/employee_list_page.dart';
export '../../modules/hr/pages/employee_detail_page.dart';
export '../../modules/hr/pages/shift_planning_page.dart';
export '../../modules/hr/pages/attendances_page.dart';
export '../../modules/hr/pages/kiosk_mode_page.dart';
export '../../modules/hr/pages/medical_leaves_page.dart';
export '../../modules/website/pages/website_management_page.dart';
export '../../modules/website/pages/page_management_page.dart';
export '../../modules/website/pages/navigation_management_page.dart';
export '../../modules/website/pages/integrations_page.dart';
export '../../modules/website/pages/featured_products_page.dart';
export '../../modules/website/pages/product_website_visibility_page.dart';
export '../../modules/website/pages/content_management_page.dart';
export '../../modules/website/pages/online_orders_page.dart';
export '../../modules/website/pages/website_settings_page.dart';
export '../../modules/website/pages/seo_settings_page.dart';
export '../widgets/workspace_demo_page.dart';

// Messaging
export '../../modules/messaging/pages/employee_chat_page.dart';

// Mail (Zoho Integration)
export '../../modules/mail/pages/mail_inbox_page.dart';

// Debug Module
export '../../modules/debug/pages/bug_list_page.dart';

// Spreadsheets Module
export '../../modules/spreadsheets/pages/spreadsheet_dashboard_page.dart';
export '../../modules/spreadsheets/pages/spreadsheet_editor_page.dart';

// WebView Modules
export '../../modules/webview_modules/webview_modules.dart';

// Also export MainLayout since it is used by ERP pages inside the barrel context
// (Actually we don't need to export it if we use MainLayout from AppRouter,
// but AppRouter will need to access Widgets from the deferred library so it's safer to keep MainLayout separate.
// Wait, MainLayout is used IN AppRouter to wrap pages. We can keep MainLayout imported in AppRouter
// and just pass the deferred widgets as children. That works fine.)
