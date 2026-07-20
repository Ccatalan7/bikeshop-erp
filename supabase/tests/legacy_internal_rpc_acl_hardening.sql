begin;

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);

select plan(14);

select has_function(
  'public',
  'set_config',
  array['text', 'text', 'boolean'],
  'legacy set_config helper remains available to owner-controlled SQL'
);
select has_function(
  'public',
  'import_product_with_context',
  array['uuid', 'text', 'jsonb', 'text', 'text'],
  'legacy product import helper remains available to owner-controlled SQL'
);
select has_function(
  'public',
  'create_adhoc_item_for_task',
  array['uuid'],
  'task-item trigger helper remains installed'
);
select has_function(
  'public',
  'consume_purchase_invoice_inventory',
  array['public.purchase_invoices'],
  'purchase inventory consume helper remains installed'
);
select has_function(
  'public',
  'restore_purchase_invoice_inventory',
  array['public.purchase_invoices'],
  'purchase inventory restore helper remains installed'
);
select has_function(
  'public',
  'restore_sales_invoice_inventory',
  array['public.sales_invoices'],
  'sales inventory restore helper remains installed'
);

select is(
  (
    select count(*)::integer
    from pg_proc procedure_row
    cross join lateral aclexplode(
      coalesce(
        procedure_row.proacl,
        acldefault('f', procedure_row.proowner)
      )
    ) expanded_acl
    where procedure_row.oid =
      'public.set_config(text,text,boolean)'::regprocedure
      and expanded_acl.grantee <> procedure_row.proowner
  ),
  0,
  'set_config has no PUBLIC or named non-owner ACL entry'
);
select is(
  (
    select count(*)::integer
    from pg_proc procedure_row
    cross join lateral aclexplode(
      coalesce(
        procedure_row.proacl,
        acldefault('f', procedure_row.proowner)
      )
    ) expanded_acl
    where procedure_row.oid =
      'public.import_product_with_context(uuid,text,jsonb,text,text)'::regprocedure
      and expanded_acl.grantee <> procedure_row.proowner
  ),
  0,
  'legacy product import helper has no PUBLIC or named non-owner ACL entry'
);
select is(
  (
    select count(*)::integer
    from pg_proc procedure_row
    cross join lateral aclexplode(
      coalesce(
        procedure_row.proacl,
        acldefault('f', procedure_row.proowner)
      )
    ) expanded_acl
    where procedure_row.oid =
      'public.create_adhoc_item_for_task(uuid)'::regprocedure
      and expanded_acl.grantee <> procedure_row.proowner
  ),
  0,
  'task-item trigger helper has no PUBLIC or named non-owner ACL entry'
);
select is(
  (
    select count(*)::integer
    from pg_proc procedure_row
    cross join lateral aclexplode(
      coalesce(
        procedure_row.proacl,
        acldefault('f', procedure_row.proowner)
      )
    ) expanded_acl
    where procedure_row.oid =
      'public.consume_purchase_invoice_inventory(public.purchase_invoices)'::regprocedure
      and expanded_acl.grantee <> procedure_row.proowner
  ),
  0,
  'purchase inventory consume helper has no PUBLIC or named non-owner ACL entry'
);
select is(
  (
    select count(*)::integer
    from pg_proc procedure_row
    cross join lateral aclexplode(
      coalesce(
        procedure_row.proacl,
        acldefault('f', procedure_row.proowner)
      )
    ) expanded_acl
    where procedure_row.oid =
      'public.restore_purchase_invoice_inventory(public.purchase_invoices)'::regprocedure
      and expanded_acl.grantee <> procedure_row.proowner
  ),
  0,
  'purchase inventory restore helper has no PUBLIC or named non-owner ACL entry'
);
select is(
  (
    select count(*)::integer
    from pg_proc procedure_row
    cross join lateral aclexplode(
      coalesce(
        procedure_row.proacl,
        acldefault('f', procedure_row.proowner)
      )
    ) expanded_acl
    where procedure_row.oid =
      'public.restore_sales_invoice_inventory(public.sales_invoices)'::regprocedure
      and expanded_acl.grantee <> procedure_row.proowner
  ),
  0,
  'sales inventory restore helper has no PUBLIC or named non-owner ACL entry'
);

select ok(
  has_function_privilege(
    'authenticated',
    'public.apply_product_import_stock(uuid,integer,text,text)',
    'EXECUTE'
  ),
  'authenticated employees retain the canonical product import command'
);
select ok(
  not has_function_privilege(
    'anon',
    'public.apply_product_import_stock(uuid,integer,text,text)',
    'EXECUTE'
  ),
  'anonymous callers cannot use the canonical product import command'
);

select * from finish();

rollback;
