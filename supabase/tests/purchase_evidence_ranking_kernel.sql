begin;

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);
select no_plan();

select has_view(
  'public', 'purchase_invoice_freight_components_v1',
  'structured freight evidence has a canonical read model'
);
select has_view(
  'public', 'purchase_line_landed_cost_observations_v1',
  'eligible line costs and allocations are reconstructable'
);
select has_view(
  'public', 'purchase_candidate_metrics_v1',
  'historical candidate metrics are separate from ranking'
);
select has_function(
  'public', 'rank_purchase_candidates_v1',
  array['text', 'uuid', 'uuid', 'text', 'integer', 'text'],
  'ranking is a versioned tenant-bound RPC'
);
select has_function(
  'public', 'assistant_rank_purchase_candidates_v1',
  array['text', 'uuid', 'text', 'integer'],
  'the AI gateway receives a governed ranking projection'
);
select has_table(
  'public', 'purchase_plans',
  'external purchase decisions have a durable draft owner'
);
select has_table(
  'public', 'purchase_plan_lines',
  'each planned need freezes one selected candidate'
);
select has_view(
  'public', 'purchase_plan_supplier_groups_v1',
  'draft lines have a supplier and currency grouping read model'
);
select has_function(
  'public', 'prepare_purchase_plan_line_v1',
  array['uuid', 'bigint', 'uuid', 'uuid', 'numeric', 'text', 'text'],
  'candidate selection is an idempotent versioned command'
);
select has_function(
  'public', 'remove_purchase_plan_line_v1',
  array['uuid', 'bigint', 'uuid', 'text'],
  'draft lines have an explicit idempotent removal command'
);
select has_function(
  'public', 'update_purchase_plan_line_quantity_v1',
  array['uuid', 'bigint', 'uuid', 'numeric', 'text'],
  'draft quantities have an explicit optimistic edit command'
);
select has_function(
  'public', 'prepare_purchase_plan_scenario_v1',
  array['uuid', 'bigint', 'jsonb', 'text', 'text'],
  'a basket can be adopted through one atomic review-only command'
);
select has_function(
  'public', 'build_purchase_scenarios_v1',
  array['jsonb', 'text', 'integer', 'integer'],
  'basket combinations are owned by a bounded deterministic solver'
);
select has_function(
  'public', 'assistant_build_purchase_scenarios_v1',
  array['jsonb', 'text', 'integer', 'integer'],
  'the AI gateway receives a governed basket-scenario projection'
);
select ok(
  has_function_privilege(
    'authenticated',
    'public.rank_purchase_candidates_v1(text,uuid,uuid,text,integer,text)',
    'execute'
  ) and not has_function_privilege(
    'anon',
    'public.rank_purchase_candidates_v1(text,uuid,uuid,text,integer,text)',
    'execute'
  ),
  'ranking is available to authenticated staff only'
);
select ok(
  has_function_privilege(
    'authenticated',
    'public.assistant_rank_purchase_candidates_v1(text,uuid,text,integer)',
    'execute'
  ) and not has_function_privilege(
    'anon',
    'public.assistant_rank_purchase_candidates_v1(text,uuid,text,integer)',
    'execute'
  ),
  'the assistant projection is available only through authenticated authority'
);
select ok(
  has_function_privilege(
    'authenticated',
    'public.prepare_purchase_plan_line_v1(uuid,bigint,uuid,uuid,numeric,text,text)',
    'execute'
  ) and not has_function_privilege(
    'anon',
    'public.prepare_purchase_plan_line_v1(uuid,bigint,uuid,uuid,numeric,text,text)',
    'execute'
  ),
  'only authenticated staff may prepare a purchase-plan line'
);
select ok(
  has_function_privilege(
    'authenticated',
    'public.remove_purchase_plan_line_v1(uuid,bigint,uuid,text)',
    'execute'
  ) and not has_function_privilege(
    'anon',
    'public.remove_purchase_plan_line_v1(uuid,bigint,uuid,text)',
    'execute'
  ),
  'only authenticated staff may remove a purchase-plan line'
);
select ok(
  has_function_privilege(
    'authenticated',
    'public.update_purchase_plan_line_quantity_v1(uuid,bigint,uuid,numeric,text)',
    'execute'
  ) and not has_function_privilege(
    'anon',
    'public.update_purchase_plan_line_quantity_v1(uuid,bigint,uuid,numeric,text)',
    'execute'
  ),
  'only authenticated staff may edit a purchase-plan quantity'
);
select ok(
  has_function_privilege(
    'authenticated',
    'public.prepare_purchase_plan_scenario_v1(uuid,bigint,jsonb,text,text)',
    'execute'
  ) and not has_function_privilege(
    'anon',
    'public.prepare_purchase_plan_scenario_v1(uuid,bigint,jsonb,text,text)',
    'execute'
  ),
  'only authenticated staff may adopt a basket scenario'
);
select ok(
  has_function_privilege(
    'authenticated',
    'public.build_purchase_scenarios_v1(jsonb,text,integer,integer)',
    'execute'
  ) and not has_function_privilege(
    'anon',
    'public.build_purchase_scenarios_v1(jsonb,text,integer,integer)',
    'execute'
  ),
  'basket scenarios are available to authenticated staff only'
);
select ok(
  has_table_privilege(
    'authenticated',
    'public.purchase_invoice_freight_components_v1',
    'select'
  )
  and not has_table_privilege(
    'authenticated',
    'public.purchase_invoice_freight_components_v1',
    'insert,update,delete'
  )
  and not has_table_privilege(
    'anon',
    'public.purchase_invoice_freight_components_v1',
    'select'
  )
  and not has_table_privilege(
    'service_role',
    'public.purchase_invoice_freight_components_v1',
    'select'
  ),
  'structured freight evidence is readable only by authenticated staff'
);
select ok(
  has_table_privilege(
    'authenticated',
    'public.purchase_line_landed_cost_observations_v1',
    'select'
  )
  and not has_table_privilege(
    'authenticated',
    'public.purchase_line_landed_cost_observations_v1',
    'insert,update,delete'
  )
  and not has_table_privilege(
    'anon',
    'public.purchase_line_landed_cost_observations_v1',
    'select'
  )
  and not has_table_privilege(
    'service_role',
    'public.purchase_line_landed_cost_observations_v1',
    'select'
  ),
  'landed-cost evidence is readable only by authenticated staff'
);
select ok(
  has_table_privilege(
    'authenticated',
    'public.purchase_candidate_metrics_v1',
    'select'
  )
  and not has_table_privilege(
    'authenticated',
    'public.purchase_candidate_metrics_v1',
    'insert,update,delete'
  )
  and not has_table_privilege(
    'anon',
    'public.purchase_candidate_metrics_v1',
    'select'
  )
  and not has_table_privilege(
    'service_role',
    'public.purchase_candidate_metrics_v1',
    'select'
  ),
  'candidate metrics are readable only by authenticated staff'
);

insert into public.tenants(id, shop_name) values
  ('99c10000-0000-4000-8000-000000000001', 'Purchase Evidence A'),
  ('99c10000-0000-4000-8000-000000000002', 'Purchase Evidence B');

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);

insert into auth.users(
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  '99c10000-0000-4000-8000-000000000099',
  'authenticated', 'authenticated', 'purchase-evidence@example.invalid', '',
  now(), '{}'::jsonb, '{}'::jsonb, now(), now()
);
insert into public.user_profiles(user_id, tenant_id, role) values (
  '99c10000-0000-4000-8000-000000000099',
  '99c10000-0000-4000-8000-000000000001',
  'admin'
);

insert into public.product_categories(
  id, tenant_id, name, full_path, level, is_active
) values
  ('99c10000-0000-4000-8000-000000000011', '99c10000-0000-4000-8000-000000000001', 'Transmisión QA', 'Componentes > Transmisión QA', 1, true),
  ('99c10000-0000-4000-8000-000000000012', '99c10000-0000-4000-8000-000000000001', 'Piñones QA', 'Componentes > Transmisión QA > Piñones QA', 2, true),
  ('99c10000-0000-4000-8000-000000000013', '99c10000-0000-4000-8000-000000000001', 'Cadenas QA', 'Componentes > Transmisión QA > Cadenas QA', 2, true),
  ('99c10000-0000-4000-8000-000000000021', '99c10000-0000-4000-8000-000000000002', 'Foreign QA', 'Foreign QA', 1, true);
update public.product_categories
set parent_id = '99c10000-0000-4000-8000-000000000011'
where id in (
  '99c10000-0000-4000-8000-000000000012',
  '99c10000-0000-4000-8000-000000000013'
);

insert into public.suppliers(
  id, tenant_id, name, city, comuna, website
) values
  ('99c10000-0000-4000-8000-000000000031', '99c10000-0000-4000-8000-000000000001', 'Distribuidor QA', 'Santiago', 'Santiago', 'https://distributor.invalid'),
  ('99c10000-0000-4000-8000-000000000032', '99c10000-0000-4000-8000-000000000001', 'Taller local QA', 'Viña del Mar', 'Viña del Mar', null),
  ('99c10000-0000-4000-8000-000000000033', '99c10000-0000-4000-8000-000000000002', 'Foreign supplier QA', null, null, null);

insert into public.supplier_tag_definitions(
  tenant_id, code, label, is_active, is_system
) values (
  '99c10000-0000-4000-8000-000000000001',
  'local', 'Proveedor local confirmado', true, false
) on conflict (tenant_id, code) do update set is_active = true;
insert into public.supplier_relationship_tags(
  tenant_id, supplier_id, tag_code, label, valid_from,
  assignment_source
) values (
  '99c10000-0000-4000-8000-000000000001',
  '99c10000-0000-4000-8000-000000000032',
  'local', 'Proveedor local confirmado', current_date - 30,
  'manual'
);

insert into public.products(
  id, tenant_id, name, sku, price, cost, category_id, category_name,
  tax_rate, purchase_treatment, inventory_qty, stock_quantity,
  is_active, is_service, product_type, track_stock,
  image_url_optimized, image_url, image_urls
) values
  ('99c10000-0000-4000-8000-000000000041', '99c10000-0000-4000-8000-000000000001', 'Piñón Shimano QA', 'PIN-QA', 22000, 8990, '99c10000-0000-4000-8000-000000000012', 'Piñones QA', 19, 'inventory', 0, 0, true, false, 'product', true, 'https://media.invalid/pinion-optimized.webp', 'https://media.invalid/pinion.jpg', array['https://media.invalid/pinion-alt.jpg']::text[]),
  ('99c10000-0000-4000-8000-000000000042', '99c10000-0000-4000-8000-000000000001', 'Cadena QA', 'CAD-QA', 5000, 1000, '99c10000-0000-4000-8000-000000000013', 'Cadenas QA', 19, 'inventory', 0, 0, true, false, 'product', true, null, null, array[]::text[]),
  ('99c10000-0000-4000-8000-000000000044', '99c10000-0000-4000-8000-000000000001', 'Producto sin compras QA', 'EMPTY-QA', 5000, 1000, '99c10000-0000-4000-8000-000000000013', 'Cadenas QA', 19, 'inventory', 0, 0, true, false, 'product', true, null, null, array[]::text[]),
  ('99c10000-0000-4000-8000-000000000043', '99c10000-0000-4000-8000-000000000002', 'Foreign product QA', 'FOR-QA', 100, 50, '99c10000-0000-4000-8000-000000000021', 'Foreign QA', 19, 'inventory', 0, 0, true, false, 'product', true, null, null, array[]::text[]);

-- Insert draft source documents first so the canonical legacy normalizer owns
-- the line rows without posting inventory or journals. Status is then changed
-- with triggers locally suppressed only inside this rollback-only fixture.
insert into public.purchase_invoices(
  id, tenant_id, invoice_number, supplier_id, supplier_name, date,
  status, subtotal, tax, total, tax_treatment, net_amount, items
) values
  ('99c10000-0000-4000-8000-000000000051', '99c10000-0000-4000-8000-000000000001', 'PE-QA-1', '99c10000-0000-4000-8000-000000000031', 'Distribuidor QA', now() - interval '60 days', 'draft', 10000, 1900, 11900, 'tax_included', 10000, jsonb_build_array(
    jsonb_build_object('product_id', '99c10000-0000-4000-8000-000000000041', 'product_name', 'Piñón Shimano QA', 'product_sku', 'PIN-QA', 'purchase_treatment', 'inventory', 'quantity', 1, 'unit_cost', 9000, 'iva_rate', 0.19),
    jsonb_build_object('product_id', '99c10000-0000-4000-8000-000000000042', 'product_name', 'Cadena QA', 'product_sku', 'CAD-QA', 'purchase_treatment', 'inventory', 'quantity', 1, 'unit_cost', 1000, 'iva_rate', 0.19)
  )),
  ('99c10000-0000-4000-8000-000000000052', '99c10000-0000-4000-8000-000000000001', 'PE-QA-2', '99c10000-0000-4000-8000-000000000032', 'Taller local QA', now() - interval '5 days', 'draft', 16000, 3040, 19040, 'tax_included', 16000, jsonb_build_array(
    jsonb_build_object('product_id', '99c10000-0000-4000-8000-000000000041', 'product_name', 'Piñón Shimano QA', 'product_sku', 'PIN-QA', 'purchase_treatment', 'workshop_consumable', 'quantity', 1, 'unit_cost', 16000, 'iva_rate', 0.19)
  )),
  ('99c10000-0000-4000-8000-000000000053', '99c10000-0000-4000-8000-000000000001', 'PE-QA-3', '99c10000-0000-4000-8000-000000000031', 'Distribuidor QA', now() - interval '20 days', 'draft', 8500, 1615, 10115, 'tax_included', 8500, jsonb_build_array(
    jsonb_build_object('product_id', '99c10000-0000-4000-8000-000000000041', 'product_name', 'Piñón Shimano QA', 'product_sku', 'PIN-QA', 'purchase_treatment', 'inventory', 'quantity', 1, 'unit_cost', 8500, 'iva_rate', 0.19)
  )),
  ('99c10000-0000-4000-8000-000000000054', '99c10000-0000-4000-8000-000000000001', 'PE-QA-DRAFT', '99c10000-0000-4000-8000-000000000031', 'Distribuidor QA', now(), 'draft', 1, 0, 1, 'no_tax', 1, jsonb_build_array(
    jsonb_build_object('product_id', '99c10000-0000-4000-8000-000000000041', 'product_name', 'Draft must not count', 'purchase_treatment', 'inventory', 'quantity', 1, 'unit_cost', 1, 'iva_rate', 0)
  )),
  ('99c10000-0000-4000-8000-000000000055', '99c10000-0000-4000-8000-000000000001', 'PE-QA-5', '99c10000-0000-4000-8000-000000000031', 'Distribuidor QA', now() - interval '10 days', 'draft', 12100, 0, 12100, 'no_tax', 12100, jsonb_build_array(
    jsonb_build_object('product_id', '99c10000-0000-4000-8000-000000000041', 'product_name', 'Piñón Shimano QA', 'product_sku', 'PIN-QA', 'purchase_treatment', 'inventory', 'quantity', 1, 'unit_cost', 10000, 'iva_rate', 0),
    jsonb_build_object('product_id', '99c10000-0000-4000-8000-000000000042', 'product_name', 'Cadena QA', 'product_sku', 'CAD-QA', 'purchase_treatment', 'inventory', 'quantity', 1, 'unit_cost', 1000, 'iva_rate', 0),
    jsonb_build_object('product_name', 'Flete normalizado', 'purchase_treatment', 'freight', 'quantity', 1, 'unit_cost', 1100, 'iva_rate', 0)
  ));
insert into public.purchase_invoices(
  id, tenant_id, invoice_number, supplier_id, supplier_name, date,
  status, subtotal, tax, total, tax_treatment, net_amount, items
) values
  ('99c10000-0000-4000-8000-000000000056', '99c10000-0000-4000-8000-000000000002', 'PE-QA-FOREIGN', '99c10000-0000-4000-8000-000000000033', 'Foreign supplier QA', now() - interval '1 day', 'draft', 50, 0, 50, 'no_tax', 50, jsonb_build_array(
    jsonb_build_object('product_id', '99c10000-0000-4000-8000-000000000043', 'product_name', 'Foreign product QA', 'purchase_treatment', 'inventory', 'quantity', 1, 'unit_cost', 50, 'iva_rate', 0)
  ));
set local session_replication_role = replica;
update public.purchase_invoices
set status = case id
  when '99c10000-0000-4000-8000-000000000053'::uuid then 'paid'
  else 'received'
end
where id in (
  '99c10000-0000-4000-8000-000000000051',
  '99c10000-0000-4000-8000-000000000052',
  '99c10000-0000-4000-8000-000000000053',
  '99c10000-0000-4000-8000-000000000055',
  '99c10000-0000-4000-8000-000000000056'
);
set local session_replication_role = origin;

insert into public.expense_categories(
  id, tenant_id, name, default_tax_rate
) values
  ('99c10000-0000-4000-8000-000000000071', '99c10000-0000-4000-8000-000000000001', 'Gastos por Transporte', 19),
  ('99c10000-0000-4000-8000-000000000072', '99c10000-0000-4000-8000-000000000002', 'Gastos por Transporte', 19);
-- This fixture exercises the linked-expense read contract, not the expense
-- editor. Preserve the explicit document totals while inserting the header;
-- the canonical expense editor normally writes lines before posting and its
-- header trigger otherwise recalculates an intentionally line-less fixture.
set local session_replication_role = replica;
insert into public.expenses(
  id, tenant_id, expense_number, category_id, currency,
  posting_status, approval_status, subtotal, tax_amount, total_amount,
  balance
) values
  ('99c10000-0000-4000-8000-000000000081', '99c10000-0000-4000-8000-000000000001', 'PE-FREIGHT-1', '99c10000-0000-4000-8000-000000000071', 'CLP', 'posted', 'approved', 1000, 190, 1190, 1190),
  ('99c10000-0000-4000-8000-000000000082', '99c10000-0000-4000-8000-000000000001', 'PE-FREIGHT-DUP', '99c10000-0000-4000-8000-000000000071', 'CLP', 'posted', 'approved', 500, 95, 595, 595),
  ('99c10000-0000-4000-8000-000000000083', '99c10000-0000-4000-8000-000000000002', 'PE-FREIGHT-FOREIGN', '99c10000-0000-4000-8000-000000000072', 'CLP', 'posted', 'approved', 10, 1.9, 11.9, 11.9);
set local session_replication_role = origin;
insert into public.expense_links(
  id, tenant_id, expense_id, purchase_invoice_id, link_kind,
  allocated_amount
) values
  ('99c10000-0000-4000-8000-000000000091', '99c10000-0000-4000-8000-000000000001', '99c10000-0000-4000-8000-000000000081', '99c10000-0000-4000-8000-000000000051', 'delivery', 1190),
  ('99c10000-0000-4000-8000-000000000092', '99c10000-0000-4000-8000-000000000001', '99c10000-0000-4000-8000-000000000082', '99c10000-0000-4000-8000-000000000055', 'delivery', 595),
  ('99c10000-0000-4000-8000-000000000093', '99c10000-0000-4000-8000-000000000002', '99c10000-0000-4000-8000-000000000083', '99c10000-0000-4000-8000-000000000056', 'delivery', 11.9);

select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub', '99c10000-0000-4000-8000-000000000099',
    'role', 'authenticated'
  )::text,
  true
);
select set_config(
  'request.jwt.claim.sub',
  '99c10000-0000-4000-8000-000000000099',
  true
);
set local role authenticated;

select is(
  (
    select recognized_net_amount
    from public.purchase_invoice_freight_components_v1
    where purchase_invoice_id = '99c10000-0000-4000-8000-000000000051'
  ),
  1000.0000::numeric,
  'a tax-included linked delivery is normalized to its net amount'
);
select is(
  (
    select source_kind
    from public.purchase_invoice_freight_components_v1
    where purchase_invoice_id = '99c10000-0000-4000-8000-000000000051'
  ),
  'expense_link',
  'linked delivery provenance remains visible'
);
select is(
  (
    select count(*)::integer
    from public.purchase_invoice_freight_components_v1
    where purchase_invoice_id = '99c10000-0000-4000-8000-000000000055'
  ),
  1,
  'a normalized freight line suppresses a possibly duplicate linked expense'
);
select is(
  (
    select source_kind
    from public.purchase_invoice_freight_components_v1
    where purchase_invoice_id = '99c10000-0000-4000-8000-000000000055'
  ),
  'purchase_invoice_line',
  'the normalized classified freight line wins precedence'
);
select is(
  (
    select allocated_freight_net
    from public.purchase_line_landed_cost_observations_v1
    where purchase_invoice_line_id = (
      select id
      from public.purchase_invoice_lines
      where purchase_invoice_id = '99c10000-0000-4000-8000-000000000051'
        and product_id = '99c10000-0000-4000-8000-000000000041'
    )
  ),
  900.0000::numeric,
  'freight follows the merchandise net share for the first line'
);
select is(
  (
    select allocated_freight_net
    from public.purchase_line_landed_cost_observations_v1
    where purchase_invoice_line_id = (
      select id
      from public.purchase_invoice_lines
      where purchase_invoice_id = '99c10000-0000-4000-8000-000000000051'
        and product_id = '99c10000-0000-4000-8000-000000000042'
    )
  ),
  100.0000::numeric,
  'freight follows the merchandise net share for the second line'
);
select is(
  (
    select sum(allocated_freight_net)
    from public.purchase_line_landed_cost_observations_v1
    where purchase_invoice_id = '99c10000-0000-4000-8000-000000000055'
  ),
  1100.0000::numeric,
  'line allocations reconcile exactly to normalized freight'
);
select is(
  (
    select landed_unit_cost_net
    from public.purchase_line_landed_cost_observations_v1
    where purchase_invoice_line_id = (
      select id
      from public.purchase_invoice_lines
      where purchase_invoice_id = '99c10000-0000-4000-8000-000000000055'
        and product_id = '99c10000-0000-4000-8000-000000000041'
    )
  ),
  11000.000000::numeric,
  'landed unit cost includes the proportional freight share'
);
select is(
  (
    select count(*)::integer
    from public.purchase_line_landed_cost_observations_v1
    where purchase_invoice_id = '99c10000-0000-4000-8000-000000000054'
  ),
  0,
  'draft documents never contaminate purchased-cost evidence'
);
select is(
  (
    select count(*)::integer
    from public.purchase_line_landed_cost_observations_v1
    where tenant_id = '99c10000-0000-4000-8000-000000000002'
  ),
  0,
  'security-invoker evidence views preserve tenant RLS'
);
select is(
  (
    select purchase_count
    from public.purchase_candidate_metrics_v1
    where product_id = '99c10000-0000-4000-8000-000000000041'
      and supplier_id = '99c10000-0000-4000-8000-000000000031'
  ),
  3,
  'candidate history counts only eligible purchases'
);
select is(
  (
    select latest_landed_unit_cost_net
    from public.purchase_candidate_metrics_v1
    where product_id = '99c10000-0000-4000-8000-000000000041'
      and supplier_id = '99c10000-0000-4000-8000-000000000031'
  ),
  11000.000000::numeric,
  'the most recent eligible landed cost is the candidate cost basis'
);
select is(
  (
    select catalog_sale_price_net
    from public.purchase_candidate_metrics_v1
    where product_id = '99c10000-0000-4000-8000-000000000041'
      and supplier_id = '99c10000-0000-4000-8000-000000000031'
  ),
  round(22000::numeric / 1.19, 6),
  'gross catalog price is normalized to the same tax basis as cost'
);
select is(
  (
    select supplier_availability
    from public.purchase_candidate_metrics_v1
    where product_id = '99c10000-0000-4000-8000-000000000041'
    limit 1
  ),
  'unverified',
  'historical purchase evidence never claims current supplier stock'
);
select is(
  (
    select is_confirmed_local
    from public.purchase_candidate_metrics_v1
    where product_id = '99c10000-0000-4000-8000-000000000041'
      and supplier_id = '99c10000-0000-4000-8000-000000000032'
  ),
  true,
  'local status comes only from an explicit current supplier tag'
);
select results_eq(
  $$select image_url_optimized, image_url, image_urls
    from public.purchase_candidate_metrics_v1
    where product_id = '99c10000-0000-4000-8000-000000000041'
      and supplier_id = '99c10000-0000-4000-8000-000000000031'$$,
  $$values (
    'https://media.invalid/pinion-optimized.webp'::text,
    'https://media.invalid/pinion.jpg'::text,
    array['https://media.invalid/pinion-alt.jpg']::text[]
  )$$,
  'candidate evidence publishes the canonical product media fallback chain'
);

create temporary table purchase_rank_balanced as
select public.rank_purchase_candidates_v1(
  null,
  '99c10000-0000-4000-8000-000000000041',
  null,
  'balanced',
  10
) as payload;
select is(
  (select payload ->> 'status' from purchase_rank_balanced),
  'success',
  'a known product produces ranked historical candidates'
);
select is(
  (select (payload ->> 'resultCount')::integer from purchase_rank_balanced),
  2,
  'one product can retain multiple supplier alternatives'
);
select is(
  (select payload #>> '{items,0,supplierName}' from purchase_rank_balanced),
  'Distribuidor QA',
  'balanced ranking favors the profitable supplier with stronger history'
);
select is(
  (select payload #>> '{items,0,rankingVersion}' from purchase_rank_balanced),
  'purchase-ranking-v1',
  'the scoring formula is explicitly versioned'
);
select is(
  (select payload #>> '{items,0,supplierAvailability}' from purchase_rank_balanced),
  'unverified',
  'the ranked result preserves availability semantics'
);
select is(
  (select payload #>> '{items,0,imageUrlOptimized}' from purchase_rank_balanced),
  'https://media.invalid/pinion-optimized.webp',
  'ranking exposes the optimized product photo'
);
select is(
  (select payload #>> '{items,0,imageUrl}' from purchase_rank_balanced),
  'https://media.invalid/pinion.jpg',
  'ranking preserves the raw product photo as fallback'
);
select is(
  (select payload #>> '{items,0,imageUrls,0}' from purchase_rank_balanced),
  'https://media.invalid/pinion-alt.jpg',
  'ranking preserves additional product photos as the final fallback tier'
);

create temporary table assistant_purchase_rank as
select public.assistant_rank_purchase_candidates_v1(
  null,
  '99c10000-0000-4000-8000-000000000041',
  'balanced',
  10
) as payload;
select is(
  (select payload ->> 'authorityTenantId' from assistant_purchase_rank),
  '99c10000-0000-4000-8000-000000000001',
  'the assistant envelope is bound to the caller tenant'
);
select is(
  (select payload #>> '{items,0,supplierAvailability}'
   from assistant_purchase_rank),
  'unverified',
  'the AI projection cannot turn purchase history into current supplier stock'
);
select is(
  (select payload #>> '{items,0,entityId}' from assistant_purchase_rank),
  '99c10000-0000-4000-8000-000000000041',
  'the hidden assistant entity identity is the canonical catalog product'
);
select ok(
  not (
    (select payload #> '{items,0}' from assistant_purchase_rank)
      ?| array['supplierId', 'productId', 'latestPurchaseInvoiceId']
  ),
  'the AI projection omits internal supplier, product and document identifiers'
);
reset role;
select is(
  (
    select concat_ws(':', contract.risk, contract.policy_decision,
      contract.max_result_count)
    from assistant_runtime.assistant_tool_receipt_contract_internal_v1(
      'rank_purchase_candidates'
    ) contract
  ),
  'read:allowed:10',
  'purchase ranking has a durable read receipt contract'
);
select is(
  (
    select concat_ws(':', contract.risk, contract.policy_decision,
      contract.max_result_count)
    from assistant_runtime.assistant_tool_receipt_contract_internal_v1(
      'build_purchase_scenarios'
    ) contract
  ),
  'read:allowed:3',
  'purchase basket analysis has a bounded durable read receipt contract'
);
set local role authenticated;

create temporary table purchase_rank_urgent as
select public.rank_purchase_candidates_v1(
  'piñón shimano', null, null, 'urgent_local', 10
) as payload;
select is(
  (select payload #>> '{items,0,supplierName}' from purchase_rank_urgent),
  'Taller local QA',
  'urgent/local can elevate an explicitly local recent rescue option'
);
select is(
  (select (payload #>> '{items,0,isConfirmedLocal}')::boolean
   from purchase_rank_urgent),
  true,
  'the local reason remains inspectable rather than implicit'
);

select is(
  (
    public.rank_purchase_candidates_v1(
      null, null,
      '99c10000-0000-4000-8000-000000000011',
      'balanced', 10
    ) ->> 'status'
  ),
  'success',
  'a parent category includes eligible descendant products'
);
select is(
  (
    public.rank_purchase_candidates_v1(
      'does-not-exist', null, null, 'balanced', 10
    ) ->> 'status'
  ),
  'verifiedEmpty',
  'a valid empty search is distinguishable from source failure'
);
select throws_ok(
  $$select public.rank_purchase_candidates_v1(
    null, null, null, 'balanced', 10
  )$$,
  '22023',
  'Invalid purchase ranking arguments',
  'an unconstrained whole-history dump is rejected'
);
select throws_ok(
  $$select public.rank_purchase_candidates_v1(
    null, '99c10000-0000-4000-8000-000000000043', null,
    'balanced', 10
  )$$,
  'P0002',
  'Product not found',
  'a foreign-tenant product cannot be ranked'
);
select throws_ok(
  $$select public.rank_purchase_candidates_v1(
    'piñón', null, null, 'magic', 10
  )$$,
  '22023',
  'Invalid purchase ranking arguments',
  'ranking profiles are a closed server-owned vocabulary'
);

create temporary table purchase_basket_balanced as
select public.build_purchase_scenarios_v1(
  jsonb_build_array(
    jsonb_build_object(
      'lineRef', 'pinion',
      'productId', '99c10000-0000-4000-8000-000000000041',
      'quantity', 1,
      'sourcingMode', 'stock_first'
    ),
    jsonb_build_object(
      'lineRef', 'cadena',
      'productId', '99c10000-0000-4000-8000-000000000042',
      'quantity', 1,
      'sourcingMode', 'stock_first'
    )
  ),
  'balanced', 2, 3
) as payload;
select is(
  (select payload ->> 'status' from purchase_basket_balanced),
  'success',
  'a basket with historical coverage produces a complete scenario'
);
select is(
  (select (payload #>> '{scenarios,0,complete}')::boolean
   from purchase_basket_balanced),
  true,
  'scenario completeness is explicit rather than inferred from row count'
);
select is(
  (select (payload #>> '{scenarios,0,supplierCount}')::integer
   from purchase_basket_balanced),
  1,
  'the solver finds one historical supplier that covers both products'
);
select is(
  (select payload #>> '{scenarios,0,lines,0,supplierName}'
   from purchase_basket_balanced),
  'Distribuidor QA',
  'the consolidated supplier is inspectable per basket line'
);
select is(
  (select payload #>> '{scenarios,0,freightAssumption}'
   from purchase_basket_balanced),
  'sum_historical_landed_line_costs_no_consolidation_saving',
  'basket consolidation never invents a freight discount'
);

create temporary table purchase_basket_partial as
select public.build_purchase_scenarios_v1(
  jsonb_build_array(
    jsonb_build_object(
      'lineRef', 'pinion',
      'productId', '99c10000-0000-4000-8000-000000000041',
      'quantity', 1,
      'sourcingMode', 'stock_first'
    ),
    jsonb_build_object(
      'lineRef', 'sin-historial',
      'productId', '99c10000-0000-4000-8000-000000000044',
      'quantity', 1,
      'sourcingMode', 'stock_first'
    )
  ),
  'balanced', 2, 3
) as payload;
select is(
  (select payload ->> 'status' from purchase_basket_partial),
  'partial',
  'missing historical coverage remains an honest partial scenario'
);
select is(
  (select payload #>> '{scenarios,0,lines,1,sourcing}'
   from purchase_basket_partial),
  'uncovered',
  'the exact uncovered line remains visible in the scenario'
);

create temporary table assistant_purchase_basket as
select public.assistant_build_purchase_scenarios_v1(
  jsonb_build_array(
    jsonb_build_object(
      'lineRef', 'line-1',
      'productId', '99c10000-0000-4000-8000-000000000041',
      'quantity', 1,
      'sourcingMode', 'external_only'
    ),
    jsonb_build_object(
      'lineRef', 'line-2',
      'productId', '99c10000-0000-4000-8000-000000000042',
      'quantity', 1,
      'sourcingMode', 'external_only'
    )
  ),
  'urgent_local', 2, 3
) as payload;
select is(
  (select payload ->> 'authorityTenantId' from assistant_purchase_basket),
  '99c10000-0000-4000-8000-000000000001',
  'assistant basket scenarios are bound to the caller tenant'
);
select ok(
  not (
    (select payload #> '{items,0,lines,0}' from assistant_purchase_basket)
      ?| array['productId', 'supplierId', 'candidateId']
  ),
  'the AI basket projection strips internal product, supplier and candidate IDs'
);
select is(
  (select payload #>> '{items,0,supplierAvailability}'
   from assistant_purchase_basket),
  'historical_only_unverified',
  'assistant basket scenarios preserve the supplier availability boundary'
);
select throws_ok(
  $$select public.build_purchase_scenarios_v1(
    '[{"lineRef":"foreign","productId":"99c10000-0000-4000-8000-000000000043","quantity":1,"sourcingMode":"stock_first"}]'::jsonb,
    'balanced', 1, 1
  )$$,
  'P0002',
  'Product not found',
  'a foreign-tenant catalog product cannot enter a basket scenario'
);

create temporary table purchase_plan_need as
select public.create_supply_need_v1(
  'ad_hoc', null, null, 'Piñón Shimano para plan QA',
  '99c10000-0000-4000-8000-000000000041', 2, 'unit', null,
  'purchase-plan-need-qa'
) as payload;
create temporary table purchase_plan_baseline as
select
  (select count(*) from public.purchase_orders) as order_count,
  (select count(*) from public.purchase_invoices) as invoice_count,
  (select count(*) from public.stock_movements) as movement_count;
create temporary table prepared_purchase_plan as
select public.prepare_purchase_plan_line_v1(
  null,
  null,
  (select (payload ->> 'need_id')::uuid from purchase_plan_need),
  (
    select candidate_id
    from public.purchase_candidate_metrics_v1
    where product_id = '99c10000-0000-4000-8000-000000000041'
      and supplier_id = '99c10000-0000-4000-8000-000000000031'
  ),
  1,
  'balanced',
  'purchase-plan-line-qa'
) as payload;

select is(
  (select payload #>> '{plan,state}' from prepared_purchase_plan),
  'draft',
  'selecting a candidate creates only a reviewable draft plan'
);
select is(
  (select payload #>> '{line,supplier_availability}'
   from prepared_purchase_plan),
  'unverified',
  'a frozen plan line still refuses to claim current supplier stock'
);
select is(
  (select (payload #>> '{supplier_groups,0,line_count}')::integer
   from prepared_purchase_plan),
  1,
  'the draft exposes its supplier grouping without creating an order'
);
select is(
  (select payload #>> '{supplier_groups,0,freight_assumption}'
   from prepared_purchase_plan),
  'sum_frozen_line_landed_costs_no_consolidation_saving',
  'grouping never invents a freight saving from consolidation'
);
select is(
  (
    select evidence_snapshot ->> 'ranking_version'
    from public.purchase_plan_lines
    where id = (
      select (payload #>> '{line,id}')::uuid from prepared_purchase_plan
    )
  ),
  'purchase-ranking-v1',
  'the selected line freezes the exact ranking formula version'
);
select is(
  (
    select evidence_snapshot ->> 'supplier_availability'
    from public.purchase_plan_lines
    where id = (
      select (payload #>> '{line,id}')::uuid from prepared_purchase_plan
    )
  ),
  'unverified',
  'selection-time evidence preserves the historical availability boundary'
);
select ok(
  (select order_count from purchase_plan_baseline)
    = (select count(*) from public.purchase_orders)
  and (select invoice_count from purchase_plan_baseline)
    = (select count(*) from public.purchase_invoices)
  and (select movement_count from purchase_plan_baseline)
    = (select count(*) from public.stock_movements),
  'preparing a line creates no order, invoice or inventory movement'
);
select is(
  (
    public.prepare_purchase_plan_line_v1(
      null,
      null,
      (select (payload ->> 'need_id')::uuid from purchase_plan_need),
      (
        select candidate_id
        from public.purchase_candidate_metrics_v1
        where product_id = '99c10000-0000-4000-8000-000000000041'
          and supplier_id = '99c10000-0000-4000-8000-000000000031'
      ),
      1,
      'balanced',
      'purchase-plan-line-qa'
    ) ->> 'replay'
  )::boolean,
  true,
  'an exact retry replays the frozen response without duplicating the plan'
);
select throws_ok(
  format(
    'select public.prepare_purchase_plan_line_v1(%L, 99, %L, %L, 1, %L, %L)',
    (select payload ->> 'plan_id' from prepared_purchase_plan),
    (select payload ->> 'need_id' from purchase_plan_need),
    (
      select candidate_id::text
      from public.purchase_candidate_metrics_v1
      where product_id = '99c10000-0000-4000-8000-000000000041'
        and supplier_id = '99c10000-0000-4000-8000-000000000031'
    ),
    'balanced',
    'purchase-plan-stale-version-qa'
  ),
  '40001',
  'El plan cambió; vuelve a cargarlo antes de guardar.',
  'stale plan versions cannot overwrite a newer decision'
);

create temporary table updated_purchase_plan_quantity as
select public.update_purchase_plan_line_quantity_v1(
  (select (payload ->> 'plan_id')::uuid from prepared_purchase_plan),
  (select (payload ->> 'plan_version')::bigint from prepared_purchase_plan),
  (select (payload #>> '{line,id}')::uuid from prepared_purchase_plan),
  2,
  'purchase-plan-update-quantity-qa'
) as payload;
select is(
  (select (payload ->> 'changed')::boolean
   from updated_purchase_plan_quantity),
  true,
  'editing a draft quantity records a real change'
);
select is(
  (select (payload #>> '{line,quantity}')::numeric
   from updated_purchase_plan_quantity),
  2.000::numeric,
  'the edited quantity is read back from the locked plan line'
);
select is(
  (select (payload #>> '{supplier_groups,0,historical_landed_subtotal_net}')::numeric
   from updated_purchase_plan_quantity),
  22000.0000::numeric,
  'supplier totals are recalculated from the edited quantity'
);
select is(
  (
    public.update_purchase_plan_line_quantity_v1(
      (select (payload ->> 'plan_id')::uuid from prepared_purchase_plan),
      (select (payload ->> 'plan_version')::bigint from prepared_purchase_plan),
      (select (payload #>> '{line,id}')::uuid from prepared_purchase_plan),
      2,
      'purchase-plan-update-quantity-qa'
    ) ->> 'replay'
  )::boolean,
  true,
  'an exact quantity retry replays without another version increment'
);
select throws_ok(
  format(
    'select public.update_purchase_plan_line_quantity_v1(%L, %L, %L, 3, %L)',
    (select payload ->> 'plan_id' from prepared_purchase_plan),
    (select payload ->> 'plan_version' from updated_purchase_plan_quantity),
    (select payload #>> '{line,id}' from prepared_purchase_plan),
    'purchase-plan-quantity-exceeds-need-qa'
  ),
  '23514',
  'La cantidad del plan excede la necesidad pendiente.',
  'a draft quantity cannot exceed its source need'
);

create temporary table removed_purchase_plan_line as
select public.remove_purchase_plan_line_v1(
  (select (payload ->> 'plan_id')::uuid from prepared_purchase_plan),
  (select (payload ->> 'plan_version')::bigint
   from updated_purchase_plan_quantity),
  (select (payload #>> '{line,id}')::uuid from prepared_purchase_plan),
  'purchase-plan-remove-line-qa'
) as payload;
select is(
  (select (payload ->> 'changed')::boolean from removed_purchase_plan_line),
  true,
  'removing an active draft line records a real change'
);
select is(
  (select payload #>> '{line,state}' from removed_purchase_plan_line),
  'removed',
  'the line remains auditable instead of being hard-deleted'
);
select is(
  (select jsonb_array_length(payload -> 'supplier_groups')
   from removed_purchase_plan_line),
  0,
  'supplier grouping immediately excludes a removed line'
);
select is(
  (
    public.remove_purchase_plan_line_v1(
      (select (payload ->> 'plan_id')::uuid from prepared_purchase_plan),
      (select (payload ->> 'plan_version')::bigint
       from updated_purchase_plan_quantity),
      (select (payload #>> '{line,id}')::uuid from prepared_purchase_plan),
      'purchase-plan-remove-line-qa'
    ) ->> 'replay'
  )::boolean,
  true,
  'an exact removal retry replays without another version change'
);
select ok(
  (select count(*) from public.supply_needs where id = (
    select (payload ->> 'need_id')::uuid from purchase_plan_need
  )) = 1
  and (select count(*) from public.purchase_plan_lines where id = (
    select (payload #>> '{line,id}')::uuid from prepared_purchase_plan
  )) = 1,
  'removal preserves both the source need and frozen plan evidence'
);

create temporary table purchase_plan_basket_need as
select public.create_supply_need_v1(
  'ad_hoc', null, null, 'Cadena para escenario QA',
  '99c10000-0000-4000-8000-000000000042', 1, 'unit', null,
  'purchase-plan-basket-need-qa'
) as payload;
create temporary table prepared_purchase_plan_scenario as
select public.prepare_purchase_plan_scenario_v1(
  null,
  null,
  jsonb_build_array(
    jsonb_build_object(
      'sourceNeedId',
        (select payload ->> 'need_id' from purchase_plan_need),
      'candidateId', (
        select candidate_id
        from public.purchase_candidate_metrics_v1
        where product_id = '99c10000-0000-4000-8000-000000000041'
          and supplier_id = '99c10000-0000-4000-8000-000000000031'
      ),
      'quantity', 1
    ),
    jsonb_build_object(
      'sourceNeedId',
        (select payload ->> 'need_id' from purchase_plan_basket_need),
      'candidateId', (
        select candidate_id
        from public.purchase_candidate_metrics_v1
        where product_id = '99c10000-0000-4000-8000-000000000042'
          and supplier_id = '99c10000-0000-4000-8000-000000000031'
      ),
      'quantity', 1
    )
  ),
  'balanced',
  'purchase-plan-scenario-qa'
) as payload;
select is(
  (select (payload ->> 'prepared_line_count')::integer
   from prepared_purchase_plan_scenario),
  2,
  'one scenario command prepares every selected external line'
);
select is(
  (
    select count(*)::integer
    from public.purchase_plan_lines
    where plan_id = (
      select (payload ->> 'plan_id')::uuid
      from prepared_purchase_plan_scenario
    ) and state = 'active'
  ),
  2,
  'scenario adoption commits all lines into one draft plan'
);
select is(
  (
    public.prepare_purchase_plan_scenario_v1(
      null,
      null,
      jsonb_build_array(
        jsonb_build_object(
          'sourceNeedId',
            (select payload ->> 'need_id' from purchase_plan_need),
          'candidateId', (
            select candidate_id
            from public.purchase_candidate_metrics_v1
            where product_id = '99c10000-0000-4000-8000-000000000041'
              and supplier_id = '99c10000-0000-4000-8000-000000000031'
          ),
          'quantity', 1
        ),
        jsonb_build_object(
          'sourceNeedId',
            (select payload ->> 'need_id' from purchase_plan_basket_need),
          'candidateId', (
            select candidate_id
            from public.purchase_candidate_metrics_v1
            where product_id = '99c10000-0000-4000-8000-000000000042'
              and supplier_id = '99c10000-0000-4000-8000-000000000031'
          ),
          'quantity', 1
        )
      ),
      'balanced',
      'purchase-plan-scenario-qa'
    ) ->> 'replay'
  )::boolean,
  true,
  'an exact basket retry replays every line without duplication'
);
select throws_ok(
  format(
    'select public.prepare_purchase_plan_scenario_v1(null, null, %L::jsonb, %L, %L)',
    jsonb_build_array(
      jsonb_build_object(
        'sourceNeedId',
          (select payload ->> 'need_id' from purchase_plan_need),
        'candidateId', (
          select candidate_id
          from public.purchase_candidate_metrics_v1
          where product_id = '99c10000-0000-4000-8000-000000000041'
            and supplier_id = '99c10000-0000-4000-8000-000000000031'
        ),
        'quantity', 1
      ),
      jsonb_build_object(
        'sourceNeedId',
          (select payload ->> 'need_id' from purchase_plan_basket_need),
        'candidateId', (
          select candidate_id
          from public.purchase_candidate_metrics_v1
          where product_id = '99c10000-0000-4000-8000-000000000041'
            and supplier_id = '99c10000-0000-4000-8000-000000000031'
        ),
        'quantity', 1
      )
    )::text,
    'balanced',
    'purchase-plan-scenario-rollback-qa'
  ),
  '23514',
  'El candidato no corresponde al producto confirmado.',
  'one invalid scenario line rolls back the whole basket command'
);
select is(
  (
    select count(*)::integer
    from public.purchase_plan_events
    where operation_key like 'purchase-plan-scenario-rollback-qa:%'
  ),
  0,
  'a failed basket leaves no partial plan events behind'
);

reset role;
update public.products
set stock_quantity = 2, inventory_qty = 2
where id = '99c10000-0000-4000-8000-000000000041';
set local role authenticated;
create temporary table purchase_basket_internal as
select public.build_purchase_scenarios_v1(
  jsonb_build_array(jsonb_build_object(
    'lineRef', 'pinion-en-stock',
    'productId', '99c10000-0000-4000-8000-000000000041',
    'quantity', 1,
    'sourcingMode', 'stock_first'
  )),
  'balanced', 1, 1
) as payload;
select is(
  (select payload #>> '{scenarios,0,kind}' from purchase_basket_internal),
  'internal_stock',
  'a fully assignable basket stops at internal stock before suppliers'
);
select is(
  (select (payload #>> '{scenarios,0,supplierCount}')::integer
   from purchase_basket_internal),
  0,
  'an internal-stock scenario has no external supplier'
);
create temporary table purchase_plan_stock_need as
select public.create_supply_need_v1(
  'ad_hoc', null, null, 'Piñón con stock interno QA',
  '99c10000-0000-4000-8000-000000000041', 1, 'unit', null,
  'purchase-plan-stock-need-qa'
) as payload;
select throws_ok(
  format(
    'select public.prepare_purchase_plan_line_v1(null, null, %L, %L, 1, %L, %L)',
    (select payload ->> 'need_id' from purchase_plan_stock_need),
    (
      select candidate_id::text
      from public.purchase_candidate_metrics_v1
      where product_id = '99c10000-0000-4000-8000-000000000041'
        and supplier_id = '99c10000-0000-4000-8000-000000000031'
    ),
    'balanced',
    'purchase-plan-skips-stock-qa'
  ),
  '55000',
  'Decide primero si usarás el stock interno disponible.',
  'an external draft cannot bypass assignable internal stock silently'
);

select * from finish();
rollback;
