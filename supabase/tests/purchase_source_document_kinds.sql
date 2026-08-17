begin;

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);
select no_plan();

select has_table(
  'public',
  'purchase_source_document_kinds',
  'purchase evidence kinds have one server-owned vocabulary'
);

select has_column(
  'public',
  'purchase_invoices',
  'source_document_kind',
  'every purchase document preserves its real evidence kind'
);

select is(
  (
    select count(*)::integer
    from public.purchase_source_document_kinds
    where code in (
      'tax_invoice',
      'receipt',
      'ticket',
      'no_tax_document',
      'other'
    )
  ),
  5,
  'the initial document vocabulary is complete'
);

select is(
  (
    select workflow_kind
    from public.purchase_source_document_kinds
    where code = 'tax_invoice'
  ),
  'ordered_purchase',
  'a tax invoice preserves the existing ordered purchase workflow'
);

select is(
  (
    select count(*)::integer
    from public.purchase_source_document_kinds
    where code in ('receipt', 'ticket', 'no_tax_document', 'other')
      and workflow_kind = 'direct_purchase'
  ),
  4,
  'direct evidence kinds skip the fictional supplier-send step'
);

select ok(
  not exists (
    select 1
    from public.purchase_invoices
    where source_document_kind is null
  ),
  'legacy purchase invoices receive the honest compatibility default'
);

select ok(
  exists (
    select 1
    from pg_constraint constraint_row
    where constraint_row.conrelid = 'public.purchase_invoices'::regclass
      and constraint_row.conname =
        'purchase_invoices_source_document_kind_fkey'
      and pg_get_constraintdef(constraint_row.oid) like
        '%REFERENCES purchase_source_document_kinds(code)%'
  ),
  'purchase documents cite the server vocabulary through a foreign key'
);

select has_view(
  'public',
  'purchase_invoice_list_read_model_v2',
  'the purchase list exposes document kind in the same snapshot'
);

select has_column(
  'public',
  'purchase_invoice_list_read_model_v2',
  'source_document_kind',
  'the list read model exposes the stable kind code'
);

select has_column(
  'public',
  'purchase_invoice_list_read_model_v2',
  'source_document_kind_label',
  'the list read model exposes the server-owned display label'
);

select has_column(
  'public',
  'purchase_invoice_list_read_model_v2',
  'source_document_workflow_kind',
  'the list read model exposes server-owned workflow behavior'
);

select ok(
  has_table_privilege(
    'authenticated',
    'public.purchase_source_document_kinds',
    'select'
  )
  and not has_table_privilege(
    'authenticated',
    'public.purchase_source_document_kinds',
    'insert,update,delete'
  )
  and not has_table_privilege(
    'anon',
    'public.purchase_source_document_kinds',
    'select'
  ),
  'staff can read but cannot mutate the source-document vocabulary'
);

select ok(
  has_table_privilege(
    'authenticated',
    'public.purchase_invoice_list_read_model_v2',
    'select'
  )
  and not has_table_privilege(
    'authenticated',
    'public.purchase_invoice_list_read_model_v2',
    'insert'
  )
  and not has_table_privilege(
    'authenticated',
    'public.purchase_invoice_list_read_model_v2',
    'update'
  )
  and not has_table_privilege(
    'authenticated',
    'public.purchase_invoice_list_read_model_v2',
    'delete'
  )
  and not has_table_privilege(
    'service_role',
    'public.purchase_invoice_list_read_model_v2',
    'insert'
  )
  and not has_table_privilege(
    'service_role',
    'public.purchase_invoice_list_read_model_v2',
    'update'
  )
  and not has_table_privilege(
    'service_role',
    'public.purchase_invoice_list_read_model_v2',
    'delete'
  )
  and not has_table_privilege(
    'anon',
    'public.purchase_invoice_list_read_model_v2',
    'select'
  ),
  'the document-aware list projection is authenticated-only'
);

select has_function(
  'public',
  'seed_intelligent_purchasing_supplier_tags',
  array['uuid'],
  'future tenants receive the reviewed local-supplier vocabulary'
);

select ok(
  not exists (
    select 1
    from public.tenants tenant
    where not exists (
      select 1
      from public.supplier_tag_definitions definition
      where definition.tenant_id = tenant.id
        and definition.code = 'local_workshop'
        and definition.is_active
        and definition.is_system
    )
    or not exists (
      select 1
      from public.supplier_tag_definitions definition
      where definition.tenant_id = tenant.id
        and definition.code = 'emergency_local'
        and definition.is_active
        and definition.is_system
    )
  ),
  'every current tenant can explicitly classify a local rescue supplier'
);

select * from finish();
rollback;
