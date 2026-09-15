begin;

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);
select no_plan();

select has_table(
  'public', 'supply_need_batch_receipts',
  'reviewed AI supply batches have immutable replay receipts'
);
select has_function(
  'public', 'assistant_prepare_supply_request_v1',
  array['jsonb', 'text'],
  'the model-facing supply draft is a read projection'
);
select has_function(
  'public', 'create_supply_need_batch_v1',
  array['text', 'jsonb', 'text', 'uuid', 'text'],
  'the operator confirmation is one atomic batch command'
);
select ok(
  has_function_privilege(
    'authenticated',
    'public.assistant_prepare_supply_request_v1(jsonb,text)',
    'execute'
  ) and not has_function_privilege(
    'anon',
    'public.assistant_prepare_supply_request_v1(jsonb,text)',
    'execute'
  ),
  'only authenticated callers can request a server-validated draft'
);
select ok(
  has_function_privilege(
    'authenticated',
    'public.create_supply_need_batch_v1(text,jsonb,text,uuid,text)',
    'execute'
  ) and not has_function_privilege(
    'anon',
    'public.create_supply_need_batch_v1(text,jsonb,text,uuid,text)',
    'execute'
  ),
  'only authenticated callers can confirm a reviewed batch'
);
select ok(
  not has_table_privilege(
    'authenticated', 'public.supply_need_batch_receipts', 'select'
  ) and not has_table_privilege(
    'authenticated', 'public.supply_need_batch_receipts', 'insert'
  ),
  'clients cannot read or forge idempotency receipts directly'
);

create temporary table ai_supply_durable_card as
select jsonb_build_array(jsonb_build_object(
  'kind', 'supply_need_draft',
  'title', '2 necesidades para revisar',
  'destination', 'purchases',
  'chips', jsonb_build_array('Rentabilidad', '2 por precisar'),
  'supplyNeedDraft', jsonb_build_object(
    'profile', 'profitability',
    'lines', jsonb_build_array(
      jsonb_build_object(
        'lineRef', 'line-1',
        'description', 'Neumático 27,5 ancho mayor a 2,0',
        'productId', null,
        'productName', null,
        'productSku', null,
        'identityState', 'unresolved',
        'quantity', 2,
        'unit', 'unit',
        'technicalPredicates', jsonb_build_array(jsonb_build_object(
          'field', 'tire_width_in',
          'operator', 'gt',
          'values', jsonb_build_array(2.0)
        )),
        'preference', 'gama económica',
        'clarification', 'Confirmar la ficha del producto exacto',
        'clarificationRequired', true
      ),
      jsonb_build_object(
        'lineRef', 'line-2',
        'description', 'Rayos 27,5',
        'productId', null,
        'productName', null,
        'productSku', null,
        'identityState', 'unresolved',
        'quantity', 1,
        'unit', 'set',
        'technicalPredicates', '[]'::jsonb,
        'preference', null,
        'clarification',
          '¿Te refieres a rayos de medida 27,5 o para rueda 27,5?',
        'clarificationRequired', true
      )
    )
  )
)) as cards;

select ok(
  public.assistant_cards_valid_v1((select cards from ai_supply_durable_card)),
  'the durable assistant ledger accepts the exact structured review card'
);
select ok(
  not public.assistant_cards_valid_v1(
    jsonb_set(
      (select cards from ai_supply_durable_card),
      '{0,supplyNeedDraft,lines,0,productName}',
      '"Producto inventado"'::jsonb
    )
  ),
  'an unresolved durable line cannot claim a product identity'
);
select ok(
  not public.assistant_cards_valid_v1(
    jsonb_set(
      (select cards from ai_supply_durable_card),
      '{0,supplyNeedDraft,lines,1,technicalPredicates}',
      '[{"field":"spoke_length","operator":"eq","values":[275]},
        {"field":"spoke_length","operator":"eq","values":[276]}]'::jsonb
    )
  ),
  'duplicate technical fields are rejected at durable persistence too'
);
select ok(
  not public.assistant_cards_valid_v1(
    jsonb_set(
      (select cards from ai_supply_durable_card),
      '{0,supplyNeedDraft,lines,0,unexpected}',
      'true'::jsonb
    )
  ),
  'the durable supply draft remains a closed wire contract'
);
select ok(
  public.assistant_cards_valid_v1(jsonb_build_array(jsonb_build_object(
    'kind', 'purchase_invoice',
    'title', 'Factura de compra',
    'destination', 'purchases',
    'chips', '[]'::jsonb
  ))),
  'extending the card contract preserves the pre-existing purchase card'
);

insert into public.tenants(id, shop_name) values
  ('a1760000-0000-4000-8000-000000000001', 'AI supply draft A'),
  ('a1760000-0000-4000-8000-000000000002', 'AI supply draft B');

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);

insert into auth.users(
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  'a1760000-0000-4000-8000-000000000011',
  'authenticated', 'authenticated', 'ai-supply-draft@example.invalid', '',
  now(), '{}'::jsonb, '{}'::jsonb, now(), now()
);
insert into public.user_profiles(user_id, tenant_id, role, permissions) values (
  'a1760000-0000-4000-8000-000000000011',
  'a1760000-0000-4000-8000-000000000001',
  'admin', '{}'::jsonb
);

insert into public.products(
  id, tenant_id, name, sku, price, cost, inventory_qty,
  stock_quantity, is_active, is_service, product_type
) values
  (
    'a1760000-0000-4000-8000-000000000021',
    'a1760000-0000-4000-8000-000000000001',
    'Neumático QA 27,5', 'AI-SUPPLY-TIRE', 22000, 8990, 0, 0,
    true, false, 'product'
  ),
  (
    'a1760000-0000-4000-8000-000000000022',
    'a1760000-0000-4000-8000-000000000002',
    'Producto ajeno QA', 'AI-SUPPLY-FOREIGN', 100, 50, 0, 0,
    true, false, 'product'
  );

insert into public.spec_definitions(
  id, tenant_id, key, label, data_type, unit, is_filterable,
  is_compatibility_relevant
) values (
  'a1760000-0000-4000-8000-000000000023',
  'a1760000-0000-4000-8000-000000000001',
  'tire_width_in', 'Ancho de neumático', 'number', 'in', true, true
);
insert into public.product_spec_values(
  tenant_id, product_id, spec_definition_id, value_number, display_value
) values (
  'a1760000-0000-4000-8000-000000000001',
  'a1760000-0000-4000-8000-000000000021',
  'a1760000-0000-4000-8000-000000000023',
  2.1, '2,10 in'
);

insert into public.assistant_threads(
  id, tenant_id, actor_user_id, state, title,
  authority_role, authority_fingerprint
) values (
  'a1760000-0000-4000-8000-000000000031',
  'a1760000-0000-4000-8000-000000000001',
  'a1760000-0000-4000-8000-000000000011',
  'active', 'AI supply draft test', 'admin',
  repeat('a', 64)
);

create temporary table ai_supply_batch_input as
select jsonb_build_array(
  jsonb_build_object(
    'lineRef', 'line-1',
    'description', 'Neumático 27,5 ancho mayor a 2,0',
    'productId', 'a1760000-0000-4000-8000-000000000021',
    'quantity', 2,
    'unit', 'unit',
    'technicalPredicates', jsonb_build_array(jsonb_build_object(
      'field', 'tire_width_in',
      'operator', 'gt',
      'values', jsonb_build_array(2.0)
    )),
    'preference', 'gama económica',
    'clarification', null,
    'clarificationRequired', false
  ),
  jsonb_build_object(
    'lineRef', 'line-2',
    'description', 'Rayos 27,5',
    'productId', null,
    'quantity', 1,
    'unit', 'set',
    'technicalPredicates', '[]'::jsonb,
    'preference', null,
    'clarification',
      '¿Te refieres a rayos de medida 27,5 o para rueda 27,5?',
    'clarificationRequired', true
  )
) as items;

grant select on ai_supply_batch_input to authenticated;

create temporary table ai_supply_non_demand_baseline as
select
  (select count(*) from public.purchase_invoices) as purchase_invoices,
  (select count(*) from public.purchase_invoice_lines) as purchase_lines,
  (select count(*) from public.purchase_plans) as purchase_plans,
  (select count(*) from public.purchase_receipts) as purchase_receipts,
  (select count(*) from public.purchase_payments) as purchase_payments,
  (select count(*) from public.stock_movements) as stock_movements,
  (select count(*) from public.journal_entries) as journal_entries;

select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub', 'a1760000-0000-4000-8000-000000000011',
    'role', 'authenticated'
  )::text,
  true
);
select set_config(
  'request.jwt.claim.sub',
  'a1760000-0000-4000-8000-000000000011',
  true
);
set local role authenticated;

create temporary table ai_supply_projection as
select public.assistant_prepare_supply_request_v1(
  (select items from ai_supply_batch_input),
  'profitability'
) as payload;

create temporary table ai_supply_batch_result as
select public.create_supply_need_batch_v1(
  'Necesito dos neumáticos y un juego de rayos 27,5',
  (select items from ai_supply_batch_input),
  'profitability',
  'a1760000-0000-4000-8000-000000000031',
  'ai-supply-batch-confirm'
) as receipt;

reset role;

select is(
  (select payload->>'status' from ai_supply_projection),
  'success',
  'the read projection validates the complete structured request'
);
select is(
  (select (payload->>'resultCount')::integer from ai_supply_projection),
  2,
  'the projection preserves every decomposed line'
);
select is(
  (select payload#>>'{items,0,entityId}' from ai_supply_projection),
  'a1760000-0000-4000-8000-000000000021',
  'the server returns the exact same-tenant product only to the typed runtime'
);
select ok(
  not ((select payload#>'{items,0}' from ai_supply_projection) ? 'productId'),
  'the projection uses the private entity field consumed by the gateway sanitizer'
);
select is(
  (select payload#>>'{items,1,identityState}' from ai_supply_projection),
  'unresolved',
  'a clarification remains unresolved instead of becoming false compatibility'
);
select is(
  (select (receipt->>'need_count')::integer from ai_supply_batch_result),
  2,
  'one explicit click creates both reviewed needs'
);
select is(
  (select count(*)::integer from public.supply_needs
   where tenant_id = 'a1760000-0000-4000-8000-000000000001'),
  2,
  'the batch creates exactly two canonical demand rows'
);
select is(
  (select count(*)::integer
   from public.supply_need_interpretation_revisions revision
   join public.supply_needs need on need.id = revision.supply_need_id
   where need.tenant_id = 'a1760000-0000-4000-8000-000000000001'
     and revision.source = 'ai'),
  2,
  'every line receives one immutable AI interpretation revision'
);
select is(
  (select count(*)::integer from public.supply_need_events event
   where event.tenant_id = 'a1760000-0000-4000-8000-000000000001'
     and event.operation_key like 'ai-supply-batch-confirm:line-%'),
  2,
  'every created need receives one immutable per-line event'
);
select is(
  (select count(*)::integer from public.supply_need_batch_receipts receipt
   where receipt.tenant_id = 'a1760000-0000-4000-8000-000000000001'
     and receipt.operation_key = 'ai-supply-batch-confirm'),
  1,
  'the whole batch receives one immutable replay receipt'
);
select ok(
  exists (
    select 1
    from public.supply_need_interpretation_revisions revision
    join public.supply_needs need on need.id = revision.supply_need_id
    where need.product_id = 'a1760000-0000-4000-8000-000000000021'
      and revision.constraints @> '[{"kind":"ranking_profile","value":"profitability"}]'::jsonb
      and revision.constraints @> '[{"kind":"commercial_preference","value":"gama económica"}]'::jsonb
      and revision.constraints @> '[{"field":"tire_width_in","operator":"gt","values":[2.0]}]'::jsonb
  ),
  'technical, profitability and commercial evidence survive together'
);
select ok(
  exists (
    select 1
    from public.supply_need_interpretation_revisions revision
    join public.supply_needs need on need.id = revision.supply_need_id
    where need.original_description = 'Rayos 27,5'
      and need.identity_state = 'unresolved'
      and revision.clarifications @> '[{"blocking":true}]'::jsonb
  ),
  'the unresolved line retains its blocking technical question'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"a1760000-0000-4000-8000-000000000011","role":"authenticated"}',
  true
);
select set_config(
  'request.jwt.claim.sub',
  'a1760000-0000-4000-8000-000000000011',
  true
);
set local role authenticated;

create temporary table ai_supply_batch_replay as
select public.create_supply_need_batch_v1(
  'Necesito dos neumáticos y un juego de rayos 27,5',
  (select items from ai_supply_batch_input),
  'profitability',
  'a1760000-0000-4000-8000-000000000031',
  'ai-supply-batch-confirm'
) as receipt;

reset role;

select is(
  (select (receipt->>'replay')::boolean from ai_supply_batch_replay),
  true,
  'an uncertain transport retry replays the original success'
);
select is(
  (select count(*)::integer from public.supply_needs
   where tenant_id = 'a1760000-0000-4000-8000-000000000001'),
  2,
  'an exact replay creates no duplicate demand'
);

set local role authenticated;
select throws_ok(
  $$select public.create_supply_need_batch_v1(
    'Petición cambiada',
    (select items from ai_supply_batch_input),
    'profitability',
    'a1760000-0000-4000-8000-000000000031',
    'ai-supply-batch-confirm'
  )$$,
  '23505',
  'La clave de operación pertenece a otra petición.',
  'the same operation key cannot be reused for changed content'
);
select throws_ok(
  $$select public.create_supply_need_batch_v1(
    'Producto de otro tenant',
    jsonb_build_array(jsonb_build_object(
      'lineRef', 'line-1',
      'description', 'Producto ajeno',
      'productId', 'a1760000-0000-4000-8000-000000000022',
      'quantity', 1,
      'unit', 'unit',
      'technicalPredicates', '[]'::jsonb,
      'preference', null,
      'clarification', null,
      'clarificationRequired', false
    )),
    'balanced',
    'a1760000-0000-4000-8000-000000000031',
    'ai-supply-batch-foreign'
  )$$,
  '23514',
  'Catalog product is unavailable',
  'a foreign product fails before any line is inserted'
);
select throws_ok(
  $$select public.create_supply_need_batch_v1(
    'Criterio técnico inventado',
    jsonb_build_array(jsonb_build_object(
      'lineRef', 'line-1',
      'description', 'Producto con dato inventado',
      'productId', null,
      'quantity', 1,
      'unit', 'unit',
      'technicalPredicates', jsonb_build_array(jsonb_build_object(
        'field', 'medida_inventada',
        'operator', 'eq',
        'values', jsonb_build_array('x')
      )),
      'preference', null,
      'clarification', null,
      'clarificationRequired', false
    )),
    'balanced',
    'a1760000-0000-4000-8000-000000000031',
    'ai-supply-batch-invented-spec'
  )$$,
  '22023',
  'Unknown technical predicate',
  'a model cannot persist a technical field absent from the master schema'
);
select throws_ok(
  $$select public.create_supply_need_batch_v1(
    'Producto que contradice la ficha',
    jsonb_build_array(jsonb_build_object(
      'lineRef', 'line-1',
      'description', 'Neumático mayor a 2,20',
      'productId', 'a1760000-0000-4000-8000-000000000021',
      'quantity', 1,
      'unit', 'unit',
      'technicalPredicates', jsonb_build_array(jsonb_build_object(
        'field', 'tire_width_in',
        'operator', 'gt',
        'values', jsonb_build_array(2.2)
      )),
      'preference', null,
      'clarification', null,
      'clarificationRequired', false
    )),
    'balanced',
    'a1760000-0000-4000-8000-000000000031',
    'ai-supply-batch-conflicting-spec'
  )$$,
  '23514',
  'Catalog product does not satisfy request',
  'an exact product cannot contradict its canonical technical ficha'
);
select throws_ok(
  $$select public.create_supply_need_batch_v1(
    'Aclaración contradictoria',
    jsonb_build_array(jsonb_build_object(
      'lineRef', 'line-1',
      'description', 'Neumático exacto pero bloqueado',
      'productId', 'a1760000-0000-4000-8000-000000000021',
      'quantity', 1,
      'unit', 'unit',
      'technicalPredicates', '[]'::jsonb,
      'preference', null,
      'clarification', 'Confirma el producto',
      'clarificationRequired', true
    )),
    'balanced',
    'a1760000-0000-4000-8000-000000000031',
    'ai-supply-batch-blocking-exact'
  )$$,
  '22023',
  'Invalid blocking clarification',
  'a blocking identity question cannot coexist with an exact product'
);
reset role;

select is(
  (select count(*)::integer from public.supply_needs
   where tenant_id = 'a1760000-0000-4000-8000-000000000001'),
  2,
  'a rejected batch leaves no partial need behind'
);
select ok(
  (select row(
    (select count(*) from public.purchase_invoices),
    (select count(*) from public.purchase_invoice_lines),
    (select count(*) from public.purchase_plans),
    (select count(*) from public.purchase_receipts),
    (select count(*) from public.purchase_payments),
    (select count(*) from public.stock_movements),
    (select count(*) from public.journal_entries)
  ) = row(
    purchase_invoices,
    purchase_lines,
    purchase_plans,
    purchase_receipts,
    purchase_payments,
    stock_movements,
    journal_entries
  ) from ai_supply_non_demand_baseline),
  'draft review and confirmation create no purchase, payment, receipt, stock or accounting mutation'
);
select throws_ok(
  $$update public.supply_need_batch_receipts
    set operation_key = 'rewritten' where operation_key = 'ai-supply-batch-confirm'$$,
  '55000',
  'Supply kernel evidence is append-only',
  'batch replay evidence cannot be rewritten'
);

select * from finish();
rollback;
