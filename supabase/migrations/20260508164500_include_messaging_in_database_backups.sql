-- Include messaging and WhatsApp chat data in tenant database backups.

create or replace function public.create_backup(
  p_tenant_id uuid,
  p_backup_name text,
  p_backup_type text default 'manual',
  p_notes text default null
)
returns jsonb
security definer
language plpgsql
as $$
declare
  v_backup_id uuid;
  v_backup_data jsonb;
  v_summary jsonb;
  v_product_count int;
  v_product_category_count int;
  v_customer_count int;
  v_supplier_count int;
  v_sales_invoice_count int;
  v_purchase_invoice_count int;
  v_employee_count int;
  v_journal_entry_count int;
  v_mechanic_job_count int;
  v_bike_count int;
  v_product_brand_count int;
  v_bike_brand_count int;
  v_bike_model_count int;
  v_online_order_count int;
  v_website_banner_count int;
  v_conversation_count int;
  v_message_count int;
  v_chat_attachment_count int;
  v_whatsapp_binding_count int;
  v_whatsapp_channel_count int;
  v_backup_size bigint;
begin
  select count(*) into v_product_count from products where tenant_id = p_tenant_id;
  select count(*) into v_product_category_count from product_categories where tenant_id = p_tenant_id;
  select count(*) into v_customer_count from customers where tenant_id = p_tenant_id;
  select count(*) into v_supplier_count from suppliers where tenant_id = p_tenant_id;
  select count(*) into v_sales_invoice_count from sales_invoices where tenant_id = p_tenant_id;
  select count(*) into v_purchase_invoice_count from purchase_invoices where tenant_id = p_tenant_id;
  select count(*) into v_employee_count from employees where tenant_id = p_tenant_id;
  select count(*) into v_journal_entry_count from journal_entries where tenant_id = p_tenant_id;
  select count(*) into v_mechanic_job_count from mechanic_jobs where tenant_id = p_tenant_id;
  select count(*) into v_bike_count from bikes where tenant_id = p_tenant_id;
  select count(*) into v_product_brand_count from product_brands where tenant_id = p_tenant_id;
  select count(*) into v_bike_brand_count from bike_brands where tenant_id = p_tenant_id;
  select count(*) into v_bike_model_count from bike_models where tenant_id = p_tenant_id;
  select count(*) into v_online_order_count from online_orders where tenant_id = p_tenant_id;
  select count(*) into v_website_banner_count from website_banners where tenant_id = p_tenant_id;
  select count(*) into v_conversation_count from conversations where tenant_id = p_tenant_id;
  select count(*) into v_message_count
  from messages
  where conversation_id in (select id from conversations where tenant_id = p_tenant_id);
  select count(*) into v_chat_attachment_count
  from messages
  where conversation_id in (select id from conversations where tenant_id = p_tenant_id)
    and (
      type in ('image', 'file')
      or metadata ? 'url'
      or metadata ? 'media_url'
      or metadata ? 'documentUrl'
      or metadata ? 'document_url'
    );
  select count(*) into v_whatsapp_binding_count
  from whatsapp_conversation_bindings
  where tenant_id = p_tenant_id;
  select count(*) into v_whatsapp_channel_count
  from whatsapp_channels
  where tenant_id = p_tenant_id;

  v_summary := jsonb_build_object(
    'products', v_product_count,
    'product_categories', v_product_category_count,
    'customers', v_customer_count,
    'suppliers', v_supplier_count,
    'sales_invoices', v_sales_invoice_count,
    'purchase_invoices', v_purchase_invoice_count,
    'employees', v_employee_count,
    'journal_entries', v_journal_entry_count,
    'mechanic_jobs', v_mechanic_job_count,
    'bikes', v_bike_count,
    'product_brands', v_product_brand_count,
    'bike_brands', v_bike_brand_count,
    'bike_models', v_bike_model_count,
    'online_orders', v_online_order_count,
    'website_banners', v_website_banner_count,
    'conversations', v_conversation_count,
    'messages', v_message_count,
    'chat_attachments', v_chat_attachment_count,
    'whatsapp_conversation_bindings', v_whatsapp_binding_count,
    'whatsapp_channels', v_whatsapp_channel_count,
    'captured_at', now()
  );

  v_backup_data := jsonb_build_object(
    'products', (select jsonb_agg(to_jsonb(t.*)) from products t where tenant_id = p_tenant_id),
    'product_categories', (select jsonb_agg(to_jsonb(t.*)) from product_categories t where tenant_id = p_tenant_id),
    'customers', (select jsonb_agg(to_jsonb(t.*)) from customers t where tenant_id = p_tenant_id),
    'suppliers', (select jsonb_agg(to_jsonb(t.*)) from suppliers t where tenant_id = p_tenant_id),
    'sales_invoices', (select jsonb_agg(to_jsonb(t.*)) from sales_invoices t where tenant_id = p_tenant_id),
    'sales_payments', (select jsonb_agg(to_jsonb(t.*)) from sales_payments t where tenant_id = p_tenant_id),
    'purchase_invoices', (select jsonb_agg(to_jsonb(t.*)) from purchase_invoices t where tenant_id = p_tenant_id),
    'purchase_payments', (select jsonb_agg(to_jsonb(t.*)) from purchase_payments t where tenant_id = p_tenant_id),
    'employees', (select jsonb_agg(to_jsonb(t.*)) from employees t where tenant_id = p_tenant_id),
    'employee_contracts', (select jsonb_agg(to_jsonb(t.*)) from employee_contracts t where tenant_id = p_tenant_id),
    'attendance_records', (select jsonb_agg(to_jsonb(t.*)) from attendance_records t where tenant_id = p_tenant_id),
    'accounts', (select jsonb_agg(to_jsonb(t.*)) from accounts t where tenant_id = p_tenant_id),
    'journal_entries', (select jsonb_agg(to_jsonb(t.*)) from journal_entries t where tenant_id = p_tenant_id),
    'journal_lines', (select jsonb_agg(to_jsonb(t.*)) from journal_lines t where entry_id in (select id from journal_entries where tenant_id = p_tenant_id)),
    'stock_movements', (select jsonb_agg(to_jsonb(t.*)) from stock_movements t where tenant_id = p_tenant_id),
    'company_settings', (select jsonb_agg(to_jsonb(t.*)) from company_settings t where tenant_id = p_tenant_id),
    'payment_methods', (select jsonb_agg(to_jsonb(t.*)) from payment_methods t where tenant_id = p_tenant_id),
    'bikes', (select jsonb_agg(to_jsonb(t.*)) from bikes t where tenant_id = p_tenant_id),
    'mechanic_jobs', (select jsonb_agg(to_jsonb(t.*)) from mechanic_jobs t where tenant_id = p_tenant_id),
    'mechanic_job_items', (select jsonb_agg(to_jsonb(t.*)) from mechanic_job_items t where job_id in (select id from mechanic_jobs where tenant_id = p_tenant_id)),
    'mechanic_job_timeline', (select jsonb_agg(to_jsonb(t.*)) from mechanic_job_timeline t where job_id in (select id from mechanic_jobs where tenant_id = p_tenant_id)),
    'product_brands', (select jsonb_agg(to_jsonb(t.*)) from product_brands t where tenant_id = p_tenant_id),
    'bike_brands', (select jsonb_agg(to_jsonb(t.*)) from bike_brands t where tenant_id = p_tenant_id),
    'bike_models', (select jsonb_agg(to_jsonb(t.*)) from bike_models t where tenant_id = p_tenant_id),
    'website_settings', (select jsonb_agg(to_jsonb(t.*)) from website_settings t where tenant_id = p_tenant_id),
    'website_banners', (select jsonb_agg(to_jsonb(t.*)) from website_banners t where tenant_id = p_tenant_id),
    'website_content', (select jsonb_agg(to_jsonb(t.*)) from website_content t where tenant_id = p_tenant_id),
    'website_blocks', (select jsonb_agg(to_jsonb(t.*)) from website_blocks t where tenant_id = p_tenant_id),
    'featured_products', (select jsonb_agg(to_jsonb(t.*)) from featured_products t where tenant_id = p_tenant_id),
    'online_orders', (select jsonb_agg(to_jsonb(t.*)) from online_orders t where tenant_id = p_tenant_id),
    'online_order_items', (select jsonb_agg(to_jsonb(t.*)) from online_order_items t where order_id in (select id from online_orders where tenant_id = p_tenant_id)),
    'conversations', (select jsonb_agg(to_jsonb(t.*)) from conversations t where tenant_id = p_tenant_id),
    'conversation_participants', (select jsonb_agg(to_jsonb(t.*)) from conversation_participants t where conversation_id in (select id from conversations where tenant_id = p_tenant_id)),
    'conversation_contexts', (select jsonb_agg(to_jsonb(t.*)) from conversation_contexts t where conversation_id in (select id from conversations where tenant_id = p_tenant_id)),
    'messages', (select jsonb_agg(to_jsonb(t.*) order by t.created_at) from messages t where conversation_id in (select id from conversations where tenant_id = p_tenant_id)),
    'whatsapp_channels', (select jsonb_agg(to_jsonb(t.*)) from whatsapp_channels t where tenant_id = p_tenant_id),
    'whatsapp_conversation_bindings', (select jsonb_agg(to_jsonb(t.*)) from whatsapp_conversation_bindings t where tenant_id = p_tenant_id),
    'whatsapp_webhook_events', (select jsonb_agg(to_jsonb(t.*)) from whatsapp_webhook_events t where tenant_id = p_tenant_id)
  );

  v_backup_size := length(v_backup_data::text);

  insert into database_backups (
    tenant_id,
    backup_name,
    backup_type,
    status,
    backup_data,
    summary,
    backup_size_bytes,
    notes,
    created_by
  ) values (
    p_tenant_id,
    p_backup_name,
    p_backup_type,
    'completed',
    v_backup_data,
    v_summary,
    v_backup_size,
    p_notes,
    auth.uid()
  ) returning id into v_backup_id;

  return jsonb_build_object(
    'success', true,
    'backup_id', v_backup_id,
    'summary', v_summary,
    'size_mb', round((v_backup_size / 1024.0 / 1024.0)::numeric, 2)
  );
exception
  when others then
    insert into database_backups (
      tenant_id,
      backup_name,
      backup_type,
      status,
      backup_data,
      error_message,
      created_by
    ) values (
      p_tenant_id,
      p_backup_name,
      p_backup_type,
      'failed',
      '{}'::jsonb,
      SQLERRM,
      auth.uid()
    );

    return jsonb_build_object(
      'success', false,
      'error', SQLERRM
    );
end;
$$;

grant execute on function public.create_backup(uuid, text, text, text) to authenticated;

create or replace function public.restore_backup(
  p_backup_id uuid,
  p_tenant_id uuid
)
returns jsonb
security definer
language plpgsql
as $$
declare
  v_backup_data jsonb;
  v_summary jsonb;
  v_tables_restored int := 0;
begin
  select backup_data, summary into v_backup_data, v_summary
  from database_backups
  where id = p_backup_id and tenant_id = p_tenant_id and status = 'completed';

  if not found then
    return jsonb_build_object('success', false, 'error', 'Backup not found or invalid');
  end if;

  delete from journal_lines where entry_id in (select id from journal_entries where tenant_id = p_tenant_id);
  delete from mechanic_job_items where job_id in (select id from mechanic_jobs where tenant_id = p_tenant_id);
  delete from mechanic_job_timeline where job_id in (select id from mechanic_jobs where tenant_id = p_tenant_id);
  delete from online_order_items where order_id in (select id from online_orders where tenant_id = p_tenant_id);
  delete from employee_contracts where tenant_id = p_tenant_id;
  delete from attendance_records where tenant_id = p_tenant_id;
  delete from messages where conversation_id in (select id from conversations where tenant_id = p_tenant_id);
  delete from conversation_contexts where tenant_id = p_tenant_id
    or conversation_id in (select id from conversations where tenant_id = p_tenant_id);
  delete from conversation_participants where tenant_id = p_tenant_id
    or conversation_id in (select id from conversations where tenant_id = p_tenant_id);
  delete from whatsapp_conversation_bindings where tenant_id = p_tenant_id;
  delete from whatsapp_webhook_events where tenant_id = p_tenant_id;

  delete from journal_entries where tenant_id = p_tenant_id;
  delete from sales_payments where tenant_id = p_tenant_id;
  delete from purchase_payments where tenant_id = p_tenant_id;
  delete from mechanic_jobs where tenant_id = p_tenant_id;
  delete from bikes where tenant_id = p_tenant_id;
  delete from online_orders where tenant_id = p_tenant_id;
  delete from stock_movements where tenant_id = p_tenant_id;
  delete from conversations where tenant_id = p_tenant_id;
  delete from whatsapp_channels where tenant_id = p_tenant_id;

  delete from sales_invoices where tenant_id = p_tenant_id;
  delete from purchase_invoices where tenant_id = p_tenant_id;
  delete from featured_products where tenant_id = p_tenant_id;
  delete from website_blocks where tenant_id = p_tenant_id;
  delete from website_content where tenant_id = p_tenant_id;
  delete from website_banners where tenant_id = p_tenant_id;
  delete from website_settings where tenant_id = p_tenant_id;
  delete from company_settings where tenant_id = p_tenant_id;

  delete from payment_methods where tenant_id = p_tenant_id;
  delete from products where tenant_id = p_tenant_id;
  delete from employees where tenant_id = p_tenant_id;
  delete from bike_models where tenant_id = p_tenant_id;

  delete from accounts where tenant_id = p_tenant_id;
  delete from product_categories where tenant_id = p_tenant_id;
  delete from product_brands where tenant_id = p_tenant_id;
  delete from bike_brands where tenant_id = p_tenant_id;
  delete from customers where tenant_id = p_tenant_id;
  delete from suppliers where tenant_id = p_tenant_id;

  if v_backup_data ? 'product_brands' and v_backup_data->'product_brands' is not null and jsonb_typeof(v_backup_data->'product_brands') = 'array' then
    insert into product_brands select * from jsonb_populate_recordset(null::product_brands, v_backup_data->'product_brands');
    v_tables_restored := v_tables_restored + 1;
  end if;

  if v_backup_data ? 'product_categories' and v_backup_data->'product_categories' is not null and jsonb_typeof(v_backup_data->'product_categories') = 'array' then
    insert into product_categories select * from jsonb_populate_recordset(null::product_categories, v_backup_data->'product_categories');
    v_tables_restored := v_tables_restored + 1;
  end if;

  if v_backup_data ? 'products' and v_backup_data->'products' is not null and jsonb_typeof(v_backup_data->'products') = 'array' then
    insert into products select * from jsonb_populate_recordset(null::products, v_backup_data->'products');
    v_tables_restored := v_tables_restored + 1;
  end if;

  if v_backup_data ? 'customers' and v_backup_data->'customers' is not null and jsonb_typeof(v_backup_data->'customers') = 'array' then
    insert into customers select * from jsonb_populate_recordset(null::customers, v_backup_data->'customers');
    v_tables_restored := v_tables_restored + 1;
  end if;

  if v_backup_data ? 'suppliers' and v_backup_data->'suppliers' is not null and jsonb_typeof(v_backup_data->'suppliers') = 'array' then
    insert into suppliers select * from jsonb_populate_recordset(null::suppliers, v_backup_data->'suppliers');
    v_tables_restored := v_tables_restored + 1;
  end if;

  if v_backup_data ? 'whatsapp_channels' and v_backup_data->'whatsapp_channels' is not null and jsonb_typeof(v_backup_data->'whatsapp_channels') = 'array' then
    insert into whatsapp_channels select * from jsonb_populate_recordset(null::whatsapp_channels, v_backup_data->'whatsapp_channels');
    v_tables_restored := v_tables_restored + 1;
  end if;

  if v_backup_data ? 'conversations' and v_backup_data->'conversations' is not null and jsonb_typeof(v_backup_data->'conversations') = 'array' then
    insert into conversations select * from jsonb_populate_recordset(null::conversations, v_backup_data->'conversations');
    v_tables_restored := v_tables_restored + 1;
  end if;

  if v_backup_data ? 'conversation_participants' and v_backup_data->'conversation_participants' is not null and jsonb_typeof(v_backup_data->'conversation_participants') = 'array' then
    insert into conversation_participants select * from jsonb_populate_recordset(null::conversation_participants, v_backup_data->'conversation_participants');
    v_tables_restored := v_tables_restored + 1;
  end if;

  if v_backup_data ? 'conversation_contexts' and v_backup_data->'conversation_contexts' is not null and jsonb_typeof(v_backup_data->'conversation_contexts') = 'array' then
    insert into conversation_contexts select * from jsonb_populate_recordset(null::conversation_contexts, v_backup_data->'conversation_contexts');
    v_tables_restored := v_tables_restored + 1;
  end if;

  if v_backup_data ? 'messages' and v_backup_data->'messages' is not null and jsonb_typeof(v_backup_data->'messages') = 'array' then
    insert into messages select * from jsonb_populate_recordset(null::messages, v_backup_data->'messages');
    v_tables_restored := v_tables_restored + 1;
  end if;

  if v_backup_data ? 'whatsapp_conversation_bindings' and v_backup_data->'whatsapp_conversation_bindings' is not null and jsonb_typeof(v_backup_data->'whatsapp_conversation_bindings') = 'array' then
    insert into whatsapp_conversation_bindings select * from jsonb_populate_recordset(null::whatsapp_conversation_bindings, v_backup_data->'whatsapp_conversation_bindings');
    v_tables_restored := v_tables_restored + 1;
  end if;

  if v_backup_data ? 'whatsapp_webhook_events' and v_backup_data->'whatsapp_webhook_events' is not null and jsonb_typeof(v_backup_data->'whatsapp_webhook_events') = 'array' then
    insert into whatsapp_webhook_events select * from jsonb_populate_recordset(null::whatsapp_webhook_events, v_backup_data->'whatsapp_webhook_events');
    v_tables_restored := v_tables_restored + 1;
  end if;

  if v_backup_data ? 'sales_invoices' and v_backup_data->'sales_invoices' is not null and jsonb_typeof(v_backup_data->'sales_invoices') = 'array' then
    insert into sales_invoices select * from jsonb_populate_recordset(null::sales_invoices, v_backup_data->'sales_invoices');
    v_tables_restored := v_tables_restored + 1;
  end if;

  if v_backup_data ? 'sales_payments' and v_backup_data->'sales_payments' is not null and jsonb_typeof(v_backup_data->'sales_payments') = 'array' then
    insert into sales_payments select * from jsonb_populate_recordset(null::sales_payments, v_backup_data->'sales_payments');
    v_tables_restored := v_tables_restored + 1;
  end if;

  if v_backup_data ? 'purchase_invoices' and v_backup_data->'purchase_invoices' is not null and jsonb_typeof(v_backup_data->'purchase_invoices') = 'array' then
    insert into purchase_invoices select * from jsonb_populate_recordset(null::purchase_invoices, v_backup_data->'purchase_invoices');
    v_tables_restored := v_tables_restored + 1;
  end if;

  if v_backup_data ? 'purchase_payments' and v_backup_data->'purchase_payments' is not null and jsonb_typeof(v_backup_data->'purchase_payments') = 'array' then
    insert into purchase_payments select * from jsonb_populate_recordset(null::purchase_payments, v_backup_data->'purchase_payments');
    v_tables_restored := v_tables_restored + 1;
  end if;

  if v_backup_data ? 'employees' and v_backup_data->'employees' is not null and jsonb_typeof(v_backup_data->'employees') = 'array' then
    insert into employees select * from jsonb_populate_recordset(null::employees, v_backup_data->'employees');
    v_tables_restored := v_tables_restored + 1;
  end if;

  if v_backup_data ? 'employee_contracts' and v_backup_data->'employee_contracts' is not null and jsonb_typeof(v_backup_data->'employee_contracts') = 'array' then
    insert into employee_contracts select * from jsonb_populate_recordset(null::employee_contracts, v_backup_data->'employee_contracts');
    v_tables_restored := v_tables_restored + 1;
  end if;

  if v_backup_data ? 'attendance_records' and v_backup_data->'attendance_records' is not null and jsonb_typeof(v_backup_data->'attendance_records') = 'array' then
    insert into attendance_records select * from jsonb_populate_recordset(null::attendance_records, v_backup_data->'attendance_records');
    v_tables_restored := v_tables_restored + 1;
  end if;

  if v_backup_data ? 'accounts' and v_backup_data->'accounts' is not null and jsonb_typeof(v_backup_data->'accounts') = 'array' then
    insert into accounts select * from jsonb_populate_recordset(null::accounts, v_backup_data->'accounts');
    v_tables_restored := v_tables_restored + 1;
  end if;

  if v_backup_data ? 'payment_methods' and v_backup_data->'payment_methods' is not null and jsonb_typeof(v_backup_data->'payment_methods') = 'array' then
    insert into payment_methods select * from jsonb_populate_recordset(null::payment_methods, v_backup_data->'payment_methods');
    v_tables_restored := v_tables_restored + 1;
  end if;

  if v_backup_data ? 'journal_entries' and v_backup_data->'journal_entries' is not null and jsonb_typeof(v_backup_data->'journal_entries') = 'array' then
    insert into journal_entries select * from jsonb_populate_recordset(null::journal_entries, v_backup_data->'journal_entries');
    v_tables_restored := v_tables_restored + 1;
  end if;

  if v_backup_data ? 'journal_lines' and v_backup_data->'journal_lines' is not null and jsonb_typeof(v_backup_data->'journal_lines') = 'array' then
    insert into journal_lines select * from jsonb_populate_recordset(null::journal_lines, v_backup_data->'journal_lines');
    v_tables_restored := v_tables_restored + 1;
  end if;

  if v_backup_data ? 'stock_movements' and v_backup_data->'stock_movements' is not null and jsonb_typeof(v_backup_data->'stock_movements') = 'array' then
    insert into stock_movements select * from jsonb_populate_recordset(null::stock_movements, v_backup_data->'stock_movements');
    v_tables_restored := v_tables_restored + 1;
  end if;

  if v_backup_data ? 'bike_brands' and v_backup_data->'bike_brands' is not null and jsonb_typeof(v_backup_data->'bike_brands') = 'array' then
    insert into bike_brands select * from jsonb_populate_recordset(null::bike_brands, v_backup_data->'bike_brands');
    v_tables_restored := v_tables_restored + 1;
  end if;

  if v_backup_data ? 'bike_models' and v_backup_data->'bike_models' is not null and jsonb_typeof(v_backup_data->'bike_models') = 'array' then
    insert into bike_models select * from jsonb_populate_recordset(null::bike_models, v_backup_data->'bike_models');
    v_tables_restored := v_tables_restored + 1;
  end if;

  if v_backup_data ? 'bikes' and v_backup_data->'bikes' is not null and jsonb_typeof(v_backup_data->'bikes') = 'array' then
    insert into bikes select * from jsonb_populate_recordset(null::bikes, v_backup_data->'bikes');
    v_tables_restored := v_tables_restored + 1;
  end if;

  if v_backup_data ? 'mechanic_jobs' and v_backup_data->'mechanic_jobs' is not null and jsonb_typeof(v_backup_data->'mechanic_jobs') = 'array' then
    insert into mechanic_jobs select * from jsonb_populate_recordset(null::mechanic_jobs, v_backup_data->'mechanic_jobs');
    v_tables_restored := v_tables_restored + 1;
  end if;

  if v_backup_data ? 'mechanic_job_items' and v_backup_data->'mechanic_job_items' is not null and jsonb_typeof(v_backup_data->'mechanic_job_items') = 'array' then
    insert into mechanic_job_items select * from jsonb_populate_recordset(null::mechanic_job_items, v_backup_data->'mechanic_job_items');
    v_tables_restored := v_tables_restored + 1;
  end if;

  if v_backup_data ? 'mechanic_job_timeline' and v_backup_data->'mechanic_job_timeline' is not null and jsonb_typeof(v_backup_data->'mechanic_job_timeline') = 'array' then
    insert into mechanic_job_timeline select * from jsonb_populate_recordset(null::mechanic_job_timeline, v_backup_data->'mechanic_job_timeline');
    v_tables_restored := v_tables_restored + 1;
  end if;

  if v_backup_data ? 'company_settings' and v_backup_data->'company_settings' is not null and jsonb_typeof(v_backup_data->'company_settings') = 'array' then
    insert into company_settings select * from jsonb_populate_recordset(null::company_settings, v_backup_data->'company_settings');
    v_tables_restored := v_tables_restored + 1;
  end if;

  if v_backup_data ? 'website_settings' and v_backup_data->'website_settings' is not null and jsonb_typeof(v_backup_data->'website_settings') = 'array' then
    insert into website_settings select * from jsonb_populate_recordset(null::website_settings, v_backup_data->'website_settings');
    v_tables_restored := v_tables_restored + 1;
  end if;

  if v_backup_data ? 'website_banners' and v_backup_data->'website_banners' is not null and jsonb_typeof(v_backup_data->'website_banners') = 'array' then
    insert into website_banners select * from jsonb_populate_recordset(null::website_banners, v_backup_data->'website_banners');
    v_tables_restored := v_tables_restored + 1;
  end if;

  if v_backup_data ? 'website_content' and v_backup_data->'website_content' is not null and jsonb_typeof(v_backup_data->'website_content') = 'array' then
    insert into website_content select * from jsonb_populate_recordset(null::website_content, v_backup_data->'website_content');
    v_tables_restored := v_tables_restored + 1;
  end if;

  if v_backup_data ? 'website_blocks' and v_backup_data->'website_blocks' is not null and jsonb_typeof(v_backup_data->'website_blocks') = 'array' then
    insert into website_blocks select * from jsonb_populate_recordset(null::website_blocks, v_backup_data->'website_blocks');
    v_tables_restored := v_tables_restored + 1;
  end if;

  if v_backup_data ? 'featured_products' and v_backup_data->'featured_products' is not null and jsonb_typeof(v_backup_data->'featured_products') = 'array' then
    insert into featured_products select * from jsonb_populate_recordset(null::featured_products, v_backup_data->'featured_products');
    v_tables_restored := v_tables_restored + 1;
  end if;

  if v_backup_data ? 'online_orders' and v_backup_data->'online_orders' is not null and jsonb_typeof(v_backup_data->'online_orders') = 'array' then
    insert into online_orders select * from jsonb_populate_recordset(null::online_orders, v_backup_data->'online_orders');
    v_tables_restored := v_tables_restored + 1;
  end if;

  if v_backup_data ? 'online_order_items' and v_backup_data->'online_order_items' is not null and jsonb_typeof(v_backup_data->'online_order_items') = 'array' then
    insert into online_order_items select * from jsonb_populate_recordset(null::online_order_items, v_backup_data->'online_order_items');
    v_tables_restored := v_tables_restored + 1;
  end if;

  update database_backups
  set status = 'restored',
      restored_at = now(),
      restored_by = auth.uid()
  where id = p_backup_id;

  return jsonb_build_object(
    'success', true,
    'backup_id', p_backup_id,
    'tables_restored', v_tables_restored,
    'summary', v_summary
  );
exception
  when others then
    return jsonb_build_object(
      'success', false,
      'error', SQLERRM
    );
end;
$$;

grant execute on function public.restore_backup(uuid, uuid) to authenticated;
