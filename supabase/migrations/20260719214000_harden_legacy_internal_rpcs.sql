-- Legacy trigger/helper functions must never be callable through PostgREST.
-- Their definitions stay intact because database triggers and owner-controlled
-- workflows still depend on them. Only EXECUTE ACLs are reconciled here.

begin;

set local lock_timeout = '5s';
set local statement_timeout = '60s';

do $migration$
declare
  v_signature text;
  v_function regprocedure;
  v_owner oid;
  v_grantee oid;
  v_grantee_name name;
begin
  foreach v_signature in array array[
    'public.set_config(text,text,boolean)',
    'public.import_product_with_context(uuid,text,jsonb,text,text)',
    'public.create_adhoc_item_for_task(uuid)',
    'public.consume_purchase_invoice_inventory(public.purchase_invoices)',
    'public.restore_purchase_invoice_inventory(public.purchase_invoices)',
    'public.restore_sales_invoice_inventory(public.sales_invoices)'
  ]
  loop
    v_function := to_regprocedure(v_signature);

    if v_function is null then
      raise exception 'Required internal function is missing: %', v_signature
        using errcode = '42883';
    end if;

    select procedure_row.proowner
    into strict v_owner
    from pg_proc procedure_row
    where procedure_row.oid = v_function;

    -- A NULL function ACL includes the default PUBLIC EXECUTE privilege. Make
    -- the owner-only boundary explicit before enumerating named grantees.
    execute format(
      'revoke all privileges on function %s from public cascade',
      v_function
    );

    -- Hosted projects can add explicit default-privilege grantees that are not
    -- known to application migrations (for example codex_test_runner). Revoke
    -- every current non-owner grantee from the effective ACL, not only the
    -- usual API roles.
    for v_grantee in
      select distinct expanded_acl.grantee
      from pg_proc procedure_row
      cross join lateral aclexplode(
        coalesce(
          procedure_row.proacl,
          acldefault('f', procedure_row.proowner)
        )
      ) expanded_acl
      where procedure_row.oid = v_function
        and expanded_acl.grantee <> 0
        and expanded_acl.grantee <> procedure_row.proowner
    loop
      v_grantee_name := pg_get_userbyid(v_grantee);
      if v_grantee_name is null then
        raise exception 'Cannot resolve function ACL grantee OID % for %',
          v_grantee,
          v_signature
          using errcode = '42704';
      end if;

      execute format(
        'revoke all privileges on function %s from %I cascade',
        v_function,
        v_grantee_name
      );
    end loop;

    if exists (
      select 1
      from pg_proc procedure_row
      cross join lateral aclexplode(
        coalesce(
          procedure_row.proacl,
          acldefault('f', procedure_row.proowner)
        )
      ) expanded_acl
      where procedure_row.oid = v_function
        and expanded_acl.grantee <> procedure_row.proowner
    ) then
      raise exception 'Internal function did not converge to owner-only: %',
        v_signature
        using errcode = '42501';
    end if;
  end loop;

  -- The canonical, tenant-scoped and auditable import command remains the only
  -- employee stock-import entrypoint. This migration must not close it.
  if not has_function_privilege(
    'authenticated',
    'public.apply_product_import_stock(uuid,integer,text,text)',
    'EXECUTE'
  ) or has_function_privilege(
    'anon',
    'public.apply_product_import_stock(uuid,integer,text,text)',
    'EXECUTE'
  ) then
    raise exception 'Canonical product import command ACL changed unexpectedly'
      using errcode = '42501';
  end if;
end;
$migration$;

commit;
