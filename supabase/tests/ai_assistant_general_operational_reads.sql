begin;

select no_plan();

select has_function('public', 'assistant_find_inventory_risks_v1',
  array['text','text','integer'], 'inventory risk RPC exists');
select has_function('public', 'assistant_list_recent_expenses_v1',
  array['text','integer','text','text','text','integer'],
  'expense RPC exists');
select has_function('public', 'assistant_analyze_cash_and_receivables_v1',
  array['text','integer'], 'cash and receivables RPC exists');
select has_function('public', 'assistant_search_conversations_v1',
  array['text','text','text','text','boolean','boolean','integer','integer'],
  'conversation search RPC exists');

select ok((select count(*) = 4 and bool_and(function.prosecdef
      and function.proconfig @> array[
        'search_path=pg_catalog, public, pg_temp',
        'statement_timeout=4500ms'
      ]::text[])
  from pg_proc function
  join pg_namespace namespace on namespace.oid = function.pronamespace
  where namespace.nspname = 'public'
    and function.proname in (
      'assistant_find_inventory_risks_v1',
      'assistant_list_recent_expenses_v1',
      'assistant_analyze_cash_and_receivables_v1',
      'assistant_search_conversations_v1'
    )), 'all four reads are security definer with fixed path and timeout');

select ok((select count(*) = 4 and bool_and(
      has_function_privilege('authenticated', function.oid, 'EXECUTE')
      and not has_function_privilege('anon', function.oid, 'EXECUTE')
      and not has_function_privilege('service_role', function.oid, 'EXECUTE'))
  from pg_proc function
  join pg_namespace namespace on namespace.oid = function.pronamespace
  where namespace.nspname = 'public'
    and function.proname in (
      'assistant_find_inventory_risks_v1',
      'assistant_list_recent_expenses_v1',
      'assistant_analyze_cash_and_receivables_v1',
      'assistant_search_conversations_v1'
    )), 'all four reads are caller-JWT only');

select ok((select pg_get_functiondef(function.oid)
    not ilike all(array['%supplier_rut%','%notes%','%reference%','%tags%'])
  from pg_proc function join pg_namespace namespace
    on namespace.oid = function.pronamespace
  where namespace.nspname = 'public'
    and function.proname = 'assistant_list_recent_expenses_v1'),
  'expense projection cannot reference supplier RUT, notes, reference or tags');
select ok((select pg_get_functiondef(function.oid)
    like '%messaging_can_read_conversation_messages(conversation.id)%'
  from pg_proc function join pg_namespace namespace
    on namespace.oid = function.pronamespace
  where namespace.nspname = 'public'
    and function.proname = 'assistant_search_conversations_v1'),
  'conversation read preserves the canonical message visibility guard');
select ok((select pg_get_functiondef(function.oid)
    like all(array['%sales_credit_notes%','%sales_customer_refunds%',
      '%payment.deleted_at is null%','%journal_entry.id is not null%'])
  from pg_proc function join pg_namespace namespace
    on namespace.oid = function.pronamespace
  where namespace.nspname = 'public'
    and function.proname = 'assistant_analyze_cash_and_receivables_v1'),
  'cash and receivables recomputes credits, refunds, live payments and posted books');
select ok((select pg_get_functiondef(function.oid)
    like all(array['%find_inventory_risks%','%list_recent_expenses%',
      '%analyze_cash_and_receivables%','%search_conversations%'])
  from pg_proc function join pg_namespace namespace
    on namespace.oid = function.pronamespace
  where namespace.nspname = 'assistant_runtime'
    and function.proname = 'assistant_record_tool_receipt_v1'),
  'runtime receipts allowlist all four exact read tool names');
select is(public.assistant_capabilities_internal_v2(
    'manager', 'manager', '{}'::jsonb) ? 'ai.read.accounting', true,
  'persisted manager receives accounting capability');
select is(public.assistant_capabilities_internal_v2(
    'accountant', 'accountant', '{}'::jsonb) ? 'ai.read.accounting', true,
  'persisted accountant receives accounting capability');
select is(public.assistant_capabilities_internal_v2(
    'cashier', 'owner', '{}'::jsonb) ? 'ai.read.accounting', false,
  'presentation owner cannot widen a persisted cashier');

insert into public.tenants (id, shop_name, owner_email, timezone)
values
  ('a1740000-0000-4000-8000-000000000001', 'General reads A',
   'cashier-owner@example.invalid', 'America/Santiago'),
  ('a1740000-0000-4000-8000-000000000002', 'General reads B',
   'admin-owner@example.invalid', 'America/Santiago'),
  ('a1740000-0000-4000-8000-000000000003', 'General reads C',
   'someone-else@example.invalid', 'America/Santiago');

insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  ('a1740000-0000-4000-8000-000000000011', 'authenticated', 'authenticated',
   'cashier-owner@example.invalid', '', now(), '{}'::jsonb, '{}'::jsonb,
   now(), now()),
  ('a1740000-0000-4000-8000-000000000012', 'authenticated', 'authenticated',
   'admin-owner@example.invalid', '', now(), '{}'::jsonb, '{}'::jsonb,
   now(), now()),
  ('a1740000-0000-4000-8000-000000000013', 'authenticated', 'authenticated',
   'mechanic-accounting@example.invalid', '', now(), '{}'::jsonb, '{}'::jsonb,
   now(), now());

insert into public.user_profiles (user_id, tenant_id, role, permissions)
values
  ('a1740000-0000-4000-8000-000000000011',
   'a1740000-0000-4000-8000-000000000001', 'cashier', '{}'::jsonb),
  ('a1740000-0000-4000-8000-000000000012',
   'a1740000-0000-4000-8000-000000000002', 'admin', '{}'::jsonb),
  ('a1740000-0000-4000-8000-000000000013',
   'a1740000-0000-4000-8000-000000000003', 'mechanic',
   '{"access_accounting":true}'::jsonb);

-- Tenant bootstrap leaves its synthetic tenant claim in the transaction.
-- Attribute stock-ledger fixture effects to the real tenant-B administrator.
select set_config('request.jwt.claims', jsonb_build_object(
  'sub', 'a1740000-0000-4000-8000-000000000012',
  'role', 'authenticated'
)::text, true);
select set_config('request.jwt.claim.sub',
  'a1740000-0000-4000-8000-000000000012', true);

insert into public.products (
  id, tenant_id, name, sku, category, inventory_qty, stock_quantity,
  min_stock_level, track_stock, is_service, purchase_treatment, is_active,
  is_set
) values
  ('a1740000-0000-4000-8000-000000000101',
   'a1740000-0000-4000-8000-000000000002', 'Cadena agotada', 'RISK-OUT',
   'parts', 0, 0, 2, true, false, 'inventory', true, false),
  ('a1740000-0000-4000-8000-000000000102',
   'a1740000-0000-4000-8000-000000000002', 'Pastilla baja', 'RISK-LOW',
   'parts', 1, 1, 1, true, false, 'inventory', true, false),
  ('a1740000-0000-4000-8000-000000000103',
   'a1740000-0000-4000-8000-000000000002', 'Cubierta sana', 'RISK-OK',
   'parts', 5, 5, 2, true, false, 'inventory', true, false),
  ('a1740000-0000-4000-8000-000000000104',
   'a1740000-0000-4000-8000-000000000001', 'Vecina secreta', 'RISK-POISON',
   'parts', 0, 0, 3, true, false, 'inventory', true, false);

select public.save_product_set_aggregate(
  jsonb_build_object(
    'id', 'a1740000-0000-4000-8000-000000000105',
    'name', 'Juego sin armar',
    'sku', 'RISK-SET',
    'category', 'parts',
    'min_stock_level', 1
  ),
  jsonb_build_array(jsonb_build_object(
    'name', 'Componente del juego',
    'sku', 'RISK-COMP',
    'label', 'Único',
    'position', 1,
    'quantity_in_set', 2
  )),
  'ai-general-reads-risk-set'
);

select set_config('app.skip_stock_adjustment_trigger', 'true', true);
update public.products
set inventory_qty = 1, stock_quantity = 1
where tenant_id = 'a1740000-0000-4000-8000-000000000002'
  and sku = 'RISK-COMP';
select set_config('app.skip_stock_adjustment_trigger', '', true);

insert into public.expenses (
  id, tenant_id, expense_number, category_id, supplier_name, supplier_rut,
  document_type, document_number, issue_date, due_date, posting_status,
  payment_status, approval_status, currency, total_amount, amount_paid,
  balance, notes, reference, tags
) values (
  'a1740000-0000-4000-8000-000000000202',
  'a1740000-0000-4000-8000-000000000002', 'G-0001',
  (select category.id
   from public.expense_categories category
   where category.tenant_id = 'a1740000-0000-4000-8000-000000000002'
     and lower(category.name) = lower('Servicios Digitales')),
  'Proveedor interno secreto',
  '99.999.999-9', 'invoice', 'DOC-SECRET-7', now(), now(), 'posted',
  'paid', 'approved', 'CLP', 12000, 12000, 0,
  'nota que no sale', 'referencia que no sale', array['secreto']::text[]
);

insert into public.payment_methods (
  id, tenant_id, code, name, account_id, is_active
) values ('a1740000-0000-4000-8000-000000000302',
  'a1740000-0000-4000-8000-000000000002', 'cash-ai', 'Caja AI',
  (select account.id from public.accounts account
   where account.tenant_id = 'a1740000-0000-4000-8000-000000000002'
     and account.code = '1101'), true);
insert into public.journal_entries (
  id, tenant_id, entry_number, entry_date, description, type, status,
  total_debit, total_credit
) values
  ('a1740000-0000-4000-8000-000000000303',
   'a1740000-0000-4000-8000-000000000002', 'JE-AI-POSTED', now(),
   'posted balance', 'general', 'posted', 500, 0),
  ('a1740000-0000-4000-8000-000000000304',
   'a1740000-0000-4000-8000-000000000002', 'JE-AI-DRAFT', now(),
   'draft excluded', 'general', 'draft', 900, 0),
  ('a1740000-0000-4000-8000-000000000305',
   'a1740000-0000-4000-8000-000000000002', 'JE-AI-FUTURE',
   now() + interval '1 day', 'future excluded', 'general', 'posted', 800, 0);
insert into public.journal_lines (
  id, tenant_id, entry_id, account_id, account_code, account_name,
  debit_amount, credit_amount
) values
  (gen_random_uuid(), 'a1740000-0000-4000-8000-000000000002',
   'a1740000-0000-4000-8000-000000000303',
   (select account.id from public.accounts account
    where account.tenant_id = 'a1740000-0000-4000-8000-000000000002'
      and account.code = '1101'), '1101', 'Caja', 500, 0),
  (gen_random_uuid(), 'a1740000-0000-4000-8000-000000000002',
   'a1740000-0000-4000-8000-000000000304',
   (select account.id from public.accounts account
    where account.tenant_id = 'a1740000-0000-4000-8000-000000000002'
      and account.code = '1101'), '1101', 'Caja', 900, 0),
  (gen_random_uuid(), 'a1740000-0000-4000-8000-000000000002',
   'a1740000-0000-4000-8000-000000000305',
   (select account.id from public.accounts account
    where account.tenant_id = 'a1740000-0000-4000-8000-000000000002'
      and account.code = '1101'), '1101', 'Caja', 800, 0);

insert into public.sales_invoices (
  id, tenant_id, invoice_number, date, due_date, status, total, balance
) values ('a1740000-0000-4000-8000-000000000401',
  'a1740000-0000-4000-8000-000000000002', 'FV-AI-1', now(),
  now() - interval '2 days', 'confirmed', 1000, 1);
-- Payment command triggers intentionally write journals and cached invoice
-- settlement. This fixture isolates the read model's source recomputation.
alter table public.sales_payments disable trigger user;
insert into public.sales_payments (
  id, tenant_id, invoice_id, payment_method_id, amount, deleted_at
) values
  ('a1740000-0000-4000-8000-000000000402',
   'a1740000-0000-4000-8000-000000000002',
   'a1740000-0000-4000-8000-000000000401',
   'a1740000-0000-4000-8000-000000000302', 300, null),
  ('a1740000-0000-4000-8000-000000000403',
   'a1740000-0000-4000-8000-000000000002',
   'a1740000-0000-4000-8000-000000000401',
   'a1740000-0000-4000-8000-000000000302', 900, now());
alter table public.sales_payments enable trigger user;

insert into public.inventory_accounting_operations (
  id, tenant_id, operation_key, source_channel, action, document_type,
  document_id, actor_id, executor, outcome
) values
  ('a1740000-0000-4000-8000-000000000404',
   'a1740000-0000-4000-8000-000000000002', 'ai-test-credit',
   'pg_tap', 'create', 'sales_credit_note',
   'a1740000-0000-4000-8000-000000000406',
   'a1740000-0000-4000-8000-000000000012', 'database_command', 'completed'),
  ('a1740000-0000-4000-8000-000000000405',
   'a1740000-0000-4000-8000-000000000002', 'ai-test-refund',
   'pg_tap', 'create', 'sales_customer_refund',
   'a1740000-0000-4000-8000-000000000407',
   'a1740000-0000-4000-8000-000000000012', 'database_command', 'completed');
insert into public.sales_credit_notes (
  id, tenant_id, sales_invoice_id, credit_note_number, status, issue_date,
  reason_code, reason, net_amount, tax_amount, total_amount, idempotency_key,
  operation_id, journal_entry_id, created_by
) values (
  'a1740000-0000-4000-8000-000000000406',
  'a1740000-0000-4000-8000-000000000002',
  'a1740000-0000-4000-8000-000000000401', 'NC-AI-1', 'posted', now(),
  'test', 'credit fixture', 100, 0, 100, 'ai-test-credit-note',
  'a1740000-0000-4000-8000-000000000404',
  'a1740000-0000-4000-8000-000000000303',
  'a1740000-0000-4000-8000-000000000012'
);
insert into public.sales_customer_refunds (
  id, tenant_id, sales_invoice_id, sales_credit_note_id, refund_number,
  status, refunded_at, payment_method_id, amount, reference, reason,
  idempotency_key, operation_id, journal_entry_id, created_by
) values (
  'a1740000-0000-4000-8000-000000000407',
  'a1740000-0000-4000-8000-000000000002',
  'a1740000-0000-4000-8000-000000000401',
  'a1740000-0000-4000-8000-000000000406', 'RF-AI-1', 'posted', now(),
  'a1740000-0000-4000-8000-000000000302', 50, 'verified',
  'refund fixture', 'ai-test-customer-refund',
  'a1740000-0000-4000-8000-000000000405',
  'a1740000-0000-4000-8000-000000000303',
  'a1740000-0000-4000-8000-000000000012'
);

insert into public.conversations (
  id, tenant_id, type, channel, status, counterparty_type, is_group,
  context_type, context_id, created_by, last_message_at
) values
  ('a1740000-0000-4000-8000-000000000501',
   'a1740000-0000-4000-8000-000000000002', 'support', 'whatsapp',
   'active', 'customer', false, 'invoice',
   'a1740000-0000-4000-8000-000000000401', null, now()),
  ('a1740000-0000-4000-8000-000000000502',
   'a1740000-0000-4000-8000-000000000002', 'internal', 'internal',
   'active', 'internal', false, null, null,
   'a1740000-0000-4000-8000-000000000012', now());
insert into public.messages (
  id, conversation_id, sender_id, tenant_id, content, type,
  message_direction, created_at
) values
  ('a1740000-0000-4000-8000-000000000511',
   'a1740000-0000-4000-8000-000000000501',
   'a1740000-0000-4000-8000-000000000012',
   'a1740000-0000-4000-8000-000000000002', 'salida privada', 'text',
   'outbound', now()),
  ('a1740000-0000-4000-8000-000000000512',
   'a1740000-0000-4000-8000-000000000501', null,
   'a1740000-0000-4000-8000-000000000002', 'entrada privada única', 'text',
   'inbound', now());

select set_config('request.jwt.claims', jsonb_build_object(
  'sub', 'a1740000-0000-4000-8000-000000000011',
  'role', 'authenticated')::text, true);
select set_config('request.jwt.claim.sub',
  'a1740000-0000-4000-8000-000000000011', true);
set local role authenticated;

select is(public.assistant_get_authority_v1()->>'role', 'owner',
  'cashier matching owner email receives only presentation owner label');
select is(public.assistant_get_authority_v1()->'capabilities'
    ? 'ai.read.accounting', false,
  'cashier presentation owner does not receive accounting authority');
select throws_ok(
  $$select public.assistant_list_recent_expenses_v1(
    null, 30, 'any', 'any', 'any', 10)$$,
  '42501', 'AI tool is not available',
  'presentation owner cannot invoke accounting reads');
reset role;

select set_config('request.jwt.claims', jsonb_build_object(
  'sub', 'a1740000-0000-4000-8000-000000000012',
  'role', 'authenticated')::text, true);
select set_config('request.jwt.claim.sub',
  'a1740000-0000-4000-8000-000000000012', true);
set local role authenticated;

select is(public.assistant_get_authority_v1()->>'role', 'owner',
  'persisted admin may also carry presentation owner label');
select is(public.assistant_get_authority_v1()->'capabilities'
    ? 'ai.read.accounting', true,
  'persisted admin retains accounting capability under owner presentation');

create temp table ai_inventory_risks as
select public.assistant_find_inventory_risks_v1(null, 'any', 10) payload;
select is((
    select array_agg(item->>'sku' order by item->>'sku')
    from ai_inventory_risks,
      lateral jsonb_array_elements(payload->'items') item
  ), array['RISK-COMP','RISK-LOW','RISK-OUT','RISK-SET']::text[],
  'inventory risks include exact ordinary, component, and computed-set rows');
select is((select payload#>>'{items,0,risk}' from ai_inventory_risks),
  'out_of_stock', 'out-of-stock risk sorts before low stock');
select ok((select payload::text not like '%RISK-POISON%'
    and payload::text not like '%RISK-OK%' from ai_inventory_risks),
  'inventory risk read is tenant-bound and excludes healthy stock');
select is(public.assistant_find_inventory_risks_v1(
    'RISK SET', 'out_of_stock', 10)#>>'{items,0,isSet}', 'true',
  'set risk uses component-derived full-set availability, not parent stock');
select is((select array_agg(key order by key) from ai_inventory_risks,
    lateral jsonb_object_keys(payload#>'{items,0}') key),
  array['category','entityId','isSet','minimumStock','name','risk','sku',
    'stock','updatedAt']::text[], 'inventory risk projection is exact');

create temp table ai_expenses as
select public.assistant_list_recent_expenses_v1(
  'servicios DOC SECRET', 30, 'posted', 'paid', 'approved', 10
) payload;
select is((select payload->>'resultCount' from ai_expenses), '1',
  'expense AND-token search can use internal document and category fields');
select is((select payload#>>'{items,0,balance}' from ai_expenses), '0.00',
  'immediate-paid expense trusts stored header settlement without payment rows');
select ok((select payload::text not like '%Proveedor interno%'
    and payload::text not like '%99.999.999-9%'
    and payload::text not like '%DOC-SECRET-7%'
    and payload::text not like '%nota que no sale%'
  from ai_expenses), 'expense output omits supplier/document and free-text PII');

create temp table ai_cash as
select public.assistant_analyze_cash_and_receivables_v1(
  'next_7_days', 8
) payload;
select is((select payload#>>'{items,0,kind}' from ai_cash), 'summary',
  'cash output starts with an explicitly typed summary');
select is((select payload#>>'{items,0,bookLiquidFundsBalance}' from ai_cash),
  '500.00', 'book liquid funds excludes draft and future journal entries');
select is((select payload#>>'{items,0,receivablesTotal}' from ai_cash),
  '650', 'receivables recompute applies credits/refunds and ignores deleted payments');
select is((select payload#>>'{items,1,kind}' from ai_cash), 'receivable',
  'receivable rows carry their exact discriminator');
select is((select payload#>>'{items,1,timing}' from ai_cash), 'overdue',
  'receivable timing uses tenant business date');
select is((select payload#>>'{items,1,daysOverdue}' from ai_cash), '2',
  'days overdue is positive only for overdue receivables');

create temp table ai_conversations as
select public.assistant_search_conversations_v1(
  null, 'any', 'active', 'invoice', true, true, 30, 10
) payload;
select is((select payload->>'resultCount' from ai_conversations), '1',
  'visible inbound support conversation is unread and needs reply');
select is((select payload#>>'{items,0,contextLabel}' from ai_conversations),
  'FV-AI-1', 'conversation context emits only stable folio label');
select is((select payload#>>'{items,0,unreadCount}' from ai_conversations),
  '1', 'unread count follows exact message sequence after staff reply');
select ok((select payload::text not like '%entrada privada%'
    and payload::text not like '%salida privada%' from ai_conversations),
  'conversation projection emits no message content');
select is((select array_agg(key order by key) from ai_conversations,
    lateral jsonb_object_keys(payload#>'{items,0}') key),
  array['channel','contextEntityId','contextLabel','contextType',
    'counterpartyType','entityId','isGroup','lastMessageAt',
    'lastMessageDirection','lastMessageType','needsReply','status',
    'unreadCount']::text[], 'conversation projection is exact');

select throws_ok(
  $$select public.assistant_find_inventory_risks_v1(
    repeat('😀', 61), 'any', 10)$$,
  '22023', 'Invalid AI tool arguments', 'query cap uses UTF-8 bytes');
select throws_ok(
  $$select public.assistant_analyze_cash_and_receivables_v1(null, 8)$$,
  '22023', 'Invalid AI tool arguments', 'null cash horizon is rejected');
select throws_ok(
  $$select public.assistant_search_conversations_v1(
    null, 'email', 'any', 'any', false, false, 30, 10)$$,
  '22023', 'Invalid AI tool arguments', 'unknown conversation channel is rejected');
reset role;

select set_config('request.jwt.claims', jsonb_build_object(
  'sub', 'a1740000-0000-4000-8000-000000000013',
  'role', 'authenticated')::text, true);
select set_config('request.jwt.claim.sub',
  'a1740000-0000-4000-8000-000000000013', true);
set local role authenticated;
select is(public.assistant_get_authority_v1()->'capabilities'
    ? 'ai.read.accounting', true,
  'explicit access_accounting grants accounting to a non-manager profile');
select is(public.assistant_list_recent_expenses_v1(
    null, 30, 'any', 'any', 'any', 10)->>'status', 'verifiedEmpty',
  'valid empty accounting tenant reports verifiedEmpty');
reset role;

select * from finish();
rollback;
