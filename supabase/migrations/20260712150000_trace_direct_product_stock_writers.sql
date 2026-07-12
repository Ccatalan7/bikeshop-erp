-- Deployment status: DEPLOYED to production xzdvtzdqjeyqxnkqprtf on 2026-07-12;
-- authenticated rollback-only smoke passed and all business counts/invariants
-- remained exact before and after installation.
-- Compatibility boundary for application/service-role writers that still write
-- product stock columns directly. Supported posting commands set
-- app.skip_stock_adjustment_trigger and therefore do not enter this wrapper.

begin;

create table if not exists public.direct_product_stock_trace_pending (
  operation_id uuid primary key,
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  product_id uuid not null,
  transaction_id bigint not null,
  created_at timestamp with time zone not null default clock_timestamp(),
  unique (transaction_id, product_id),
  constraint direct_product_stock_trace_pending_tenant_operation_fkey
    foreign key (tenant_id, operation_id)
    references public.inventory_accounting_operations(tenant_id, id)
    on delete cascade
);

do $$
begin
  if not exists (
    select 1 from pg_constraint
     where conname = 'direct_product_stock_trace_pending_tenant_operation_fkey'
       and conrelid = 'public.direct_product_stock_trace_pending'::regclass
  ) then
    alter table public.direct_product_stock_trace_pending
      add constraint direct_product_stock_trace_pending_tenant_operation_fkey
      foreign key (tenant_id, operation_id)
      references public.inventory_accounting_operations(tenant_id, id)
      on delete cascade;
  end if;
end $$;

revoke all on public.direct_product_stock_trace_pending
  from public, anon, authenticated;

comment on table public.direct_product_stock_trace_pending is
  'Internal transaction-local bridge that preserves per-row operation context for multi-row legacy stock writes; rows are deleted by the finalizer in the same transaction.';

create or replace function public.prepare_direct_product_stock_trace()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_stock_before integer;
  v_stock_after integer;
  v_stock_quantity_changed boolean;
  v_inventory_qty_changed boolean;
  v_operation_id uuid;
  v_source_channel text;
  v_context text;
  v_action text;
  v_jwt_role text;
begin
  if current_setting('app.skip_stock_adjustment_trigger', true) = 'true'
     or nullif(current_setting('app.inventory_operation_id', true), '') is not null then
    return NEW;
  end if;

  -- Canonical bootstrap/pgTAP fixtures and explicit DBA maintenance run as a
  -- direct postgres session. Application and service-role traffic arrives via
  -- the PostgREST authenticator and is always covered by this boundary.
  if session_user in ('postgres', 'supabase_admin')
     and coalesce(current_setting('app.test_direct_product_stock_trace', true), '') <> 'true' then
    return NEW;
  end if;

  v_jwt_role := nullif(
    coalesce(
      nullif(current_setting('request.jwt.claim.role', true), ''),
      nullif(current_setting('request.jwt.claims', true), '')::jsonb->>'role'
    ),
    ''
  );

  if auth.uid() is not null
     and public.user_tenant_id() is distinct from NEW.tenant_id then
    raise exception 'Cross-tenant direct product stock write is not allowed'
      using errcode = 'insufficient_privilege';
  end if;

  if auth.uid() is null and coalesce(v_jwt_role, '') <> 'service_role' then
    raise exception 'Direct product stock writer has no authenticated or service identity'
      using errcode = 'insufficient_privilege';
  end if;

  if TG_OP = 'INSERT' then
    if coalesce(NEW.stock_quantity, 0) = 0
       and coalesce(NEW.inventory_qty, 0) = 0 then
      return NEW;
    end if;

    if coalesce(NEW.stock_quantity, 0) <> 0
       and coalesce(NEW.inventory_qty, 0) <> 0
       and NEW.stock_quantity is distinct from NEW.inventory_qty then
      raise exception
        'Product initial stock columns disagree (stock_quantity %, inventory_qty %)',
        NEW.stock_quantity, NEW.inventory_qty
        using errcode = 'check_violation';
    end if;

    v_stock_before := 0;
    v_stock_after := case
      when coalesce(NEW.stock_quantity, 0) <> 0 then NEW.stock_quantity
      else NEW.inventory_qty
    end;
    v_action := 'record_initial_stock';
  else
    v_stock_quantity_changed := OLD.stock_quantity is distinct from NEW.stock_quantity;
    v_inventory_qty_changed := OLD.inventory_qty is distinct from NEW.inventory_qty;

    if not v_stock_quantity_changed and not v_inventory_qty_changed then
      return NEW;
    end if;

    if v_stock_quantity_changed and v_inventory_qty_changed
       and NEW.stock_quantity is distinct from NEW.inventory_qty then
      raise exception
        'Direct stock update is ambiguous: stock_quantity % differs from inventory_qty %',
        NEW.stock_quantity, NEW.inventory_qty
        using errcode = 'check_violation';
    end if;

    v_stock_before := coalesce(OLD.stock_quantity, OLD.inventory_qty, 0);
    v_stock_after := case
      when v_stock_quantity_changed then coalesce(NEW.stock_quantity, 0)
      else coalesce(NEW.inventory_qty, 0)
    end;

    if v_stock_after = v_stock_before then
      NEW.stock_quantity := v_stock_after;
      NEW.inventory_qty := v_stock_after;
      return NEW;
    end if;
    v_action := 'record_compatibility_stock_change';
  end if;

  if v_stock_after < 0 then
    raise exception 'Direct product stock writes cannot create negative stock (%)', v_stock_after
      using errcode = 'check_violation';
  end if;

  if (coalesce(NEW.product_type, 'product') = 'service'
      or coalesce(NEW.track_stock, true) = false)
     and v_stock_after <> 0 then
    raise exception 'A service/non-stock product cannot receive stock directly'
      using errcode = 'check_violation';
  end if;

  -- Prevent the two legacy balance columns from diverging even when an old
  -- writer submits only one of them.
  NEW.stock_quantity := v_stock_after;
  NEW.inventory_qty := v_stock_after;

  v_context := nullif(current_setting('app.stock_adjustment_context', true), '');
  v_source_channel := case
    when v_context = 'import' then 'legacy_product_import'
    when v_context = 'purchase' then 'legacy_purchase_stock_writer'
    when TG_OP = 'INSERT' then 'product_creation'
    else 'direct_product_stock_write'
  end;

  insert into public.inventory_accounting_operations (
    tenant_id,
    operation_key,
    source_channel,
    action,
    document_type,
    document_id,
    actor_id,
    executor,
    before_snapshot,
    after_snapshot,
    context
  ) values (
    NEW.tenant_id,
    format(
      'product:%s:%s:%s',
      NEW.id,
      v_action,
      coalesce(nullif(current_setting('app.inventory_idempotency_key', true), ''), gen_random_uuid()::text)
    ),
    v_source_channel,
    v_action,
    'product',
    NEW.id,
    auth.uid(),
    'database_compatibility_trigger',
    jsonb_build_object(
      'product_id', NEW.id,
      'stock', v_stock_before,
      'unit_cost', coalesce(NEW.cost, 0)
    ),
    jsonb_build_object(
      'product_id', NEW.id,
      'stock', v_stock_after,
      'unit_cost', coalesce(NEW.cost, 0)
    ),
    jsonb_build_object(
      'trigger', 'trg_prepare_direct_product_stock_trace',
      'table_operation', TG_OP,
      'legacy_context', v_context,
      'reference', nullif(current_setting('app.stock_adjustment_reference', true), ''),
      'function_owner_role', current_user,
      'gateway_role', session_user,
      'jwt_role', v_jwt_role,
      'transaction_id', txid_current()::text
    )
  ) returning id into v_operation_id;

  perform set_config('app.inventory_operation_id', v_operation_id::text, true);
  perform set_config('app.inventory_source_document_type', 'product', true);
  perform set_config('app.inventory_source_document_id', NEW.id::text, true);
  perform set_config('app.inventory_source_channel', v_source_channel, true);

  perform public.append_inventory_accounting_checkpoint(
    v_operation_id,
    'accepted',
    'started',
    'product',
    NEW.id,
    jsonb_build_object('action', v_action, 'source_channel', v_source_channel)
  );
  perform public.append_inventory_accounting_checkpoint(
    v_operation_id,
    'source_snapshotted',
    'completed',
    'product',
    NEW.id,
    jsonb_build_object('stock_before', v_stock_before, 'stock_after', v_stock_after)
  );
  perform public.append_inventory_accounting_checkpoint(
    v_operation_id,
    'inventory_planned',
    'completed',
    'product',
    NEW.id,
    jsonb_build_object(
      'signed_delta', v_stock_after - v_stock_before,
      'stock_before', v_stock_before,
      'stock_after', v_stock_after
    )
  );
  perform public.append_inventory_accounting_checkpoint(
    v_operation_id,
    'accounting_planned',
    'completed',
    'product',
    NEW.id,
    jsonb_build_object(
      'inventory_value', round(abs(v_stock_after - v_stock_before) * greatest(coalesce(NEW.cost, 0), 0), 2),
      'policy', case when TG_OP = 'INSERT' then 'opening_inventory_equity' else 'inventory_difference' end
    )
  );

  insert into public.direct_product_stock_trace_pending (
    operation_id, tenant_id, product_id, transaction_id
  ) values (
    v_operation_id, NEW.tenant_id, NEW.id, txid_current()
  );

  -- AFTER ROW triggers for a multi-row statement can be deferred until all
  -- BEFORE ROW triggers have run. Restore the correct per-product context in a
  -- dedicated AFTER trigger instead of leaking the last row's operation.
  perform set_config('app.inventory_operation_id', '', true);
  perform set_config('app.inventory_source_document_type', '', true);
  perform set_config('app.inventory_source_document_id', '', true);
  perform set_config('app.inventory_source_channel', '', true);

  return NEW;
end;
$$;

revoke all on function public.prepare_direct_product_stock_trace()
  from public, anon, authenticated;

drop trigger if exists trg_prepare_direct_product_stock_trace on public.products;
create trigger trg_prepare_direct_product_stock_trace
  before insert or update of stock_quantity, inventory_qty on public.products
  for each row execute function public.prepare_direct_product_stock_trace();

create or replace function public.restore_direct_product_stock_trace_context()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_pending public.direct_product_stock_trace_pending%rowtype;
  v_source_channel text;
begin
  select * into v_pending
    from public.direct_product_stock_trace_pending pending
   where pending.transaction_id = txid_current()
     and pending.tenant_id = NEW.tenant_id
     and pending.product_id = NEW.id;

  if not found then
    return NEW;
  end if;

  select operation.source_channel into v_source_channel
    from public.inventory_accounting_operations operation
   where operation.id = v_pending.operation_id;

  perform set_config('app.inventory_operation_id', v_pending.operation_id::text, true);
  perform set_config('app.inventory_source_document_type', 'product', true);
  perform set_config('app.inventory_source_document_id', NEW.id::text, true);
  perform set_config('app.inventory_source_channel', v_source_channel, true);
  return NEW;
end;
$$;

revoke all on function public.restore_direct_product_stock_trace_context()
  from public, anon, authenticated;

drop trigger if exists trg_00_restore_direct_product_stock_trace on public.products;
create trigger trg_00_restore_direct_product_stock_trace
  after insert or update of stock_quantity, inventory_qty on public.products
  for each row execute function public.restore_direct_product_stock_trace_context();

create or replace function public.finalize_direct_product_stock_trace()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_operation_id uuid;
  v_operation public.inventory_accounting_operations%rowtype;
  v_delta integer;
  v_inventory_value numeric(14,2);
  v_inventory_account_id uuid;
  v_counterpart_account_id uuid;
  v_counterpart_code text;
  v_counterpart_name text;
  v_counterpart_type text;
  v_counterpart_subtype text;
  v_entry_id uuid;
  v_entry_number text;
  v_description text;
begin
  v_operation_id := nullif(current_setting('app.inventory_operation_id', true), '')::uuid;
  if v_operation_id is null then
    return NEW;
  end if;

  select * into v_operation
    from public.inventory_accounting_operations operation
   where operation.id = v_operation_id
     and operation.document_type = 'product'
     and operation.document_id = NEW.id
     and operation.executor = 'database_compatibility_trigger'
   for update;

  if not found or v_operation.outcome = 'completed' then
    return NEW;
  end if;

  v_delta := (v_operation.after_snapshot->>'stock')::integer
             - (v_operation.before_snapshot->>'stock')::integer;
  v_inventory_value := round(abs(v_delta) * greatest(coalesce(NEW.cost, 0), 0), 2);

  if v_inventory_value > 0 then
    v_inventory_account_id := public.ensure_account(
      NEW.tenant_id, '1105', 'Inventario de Productos', 'asset', 'currentAsset',
      'Valor de productos y repuestos en stock', null
    );

    if v_operation.action = 'record_initial_stock' then
      v_counterpart_code := '3101';
      v_counterpart_name := 'Capital - Inventario Inicial';
      v_counterpart_type := 'equity';
      v_counterpart_subtype := 'capital';
    elsif v_delta > 0 then
      v_counterpart_code := '4203';
      v_counterpart_name := 'Ajustes Positivos de Inventario';
      v_counterpart_type := 'income';
      v_counterpart_subtype := 'nonOperatingIncome';
    else
      v_counterpart_code := '6198';
      v_counterpart_name := 'Diferencias de Inventario';
      v_counterpart_type := 'expense';
      v_counterpart_subtype := 'operatingExpense';
    end if;

    v_counterpart_account_id := public.ensure_account(
      NEW.tenant_id,
      v_counterpart_code,
      v_counterpart_name,
      v_counterpart_type,
      v_counterpart_subtype,
      'Contrapartida de cambios de stock recibidos por el límite de compatibilidad',
      null
    );

    v_entry_id := gen_random_uuid();
    v_entry_number := public.get_next_document_number(NEW.tenant_id, 'journal_entry');
    v_description := format(
      '%s - %s (%s)',
      case when v_operation.action = 'record_initial_stock'
        then 'Inventario inicial trazado'
        else 'Cambio directo de inventario trazado'
      end,
      NEW.name,
      coalesce(NEW.sku, NEW.id::text)
    );

    insert into public.journal_entries (
      id, tenant_id, entry_number, entry_date, description, type,
      source_module, source_reference, status, total_debit, total_credit,
      created_at, updated_at
    ) values (
      v_entry_id, NEW.tenant_id, v_entry_number, current_date, v_description,
      'adjustment', 'product_stock_compatibility', NEW.id::text, 'posted',
      v_inventory_value, v_inventory_value, clock_timestamp(), clock_timestamp()
    );

    if v_delta > 0 then
      insert into public.journal_lines (
        id, entry_id, account_id, tenant_id, account_code, account_name,
        description, debit_amount, credit_amount, created_at, updated_at
      ) values
      (gen_random_uuid(), v_entry_id, v_inventory_account_id, NEW.tenant_id,
       '1105', 'Inventario de Productos', v_description,
       v_inventory_value, 0, clock_timestamp(), clock_timestamp()),
      (gen_random_uuid(), v_entry_id, v_counterpart_account_id, NEW.tenant_id,
       v_counterpart_code, v_counterpart_name, v_description,
       0, v_inventory_value, clock_timestamp(), clock_timestamp());
    else
      insert into public.journal_lines (
        id, entry_id, account_id, tenant_id, account_code, account_name,
        description, debit_amount, credit_amount, created_at, updated_at
      ) values
      (gen_random_uuid(), v_entry_id, v_counterpart_account_id, NEW.tenant_id,
       v_counterpart_code, v_counterpart_name, v_description,
       v_inventory_value, 0, clock_timestamp(), clock_timestamp()),
      (gen_random_uuid(), v_entry_id, v_inventory_account_id, NEW.tenant_id,
       '1105', 'Inventario de Productos', v_description,
       0, v_inventory_value, clock_timestamp(), clock_timestamp());
    end if;
  end if;

  perform public.complete_inventory_accounting_operation(
    v_operation_id,
    NEW.tenant_id,
    jsonb_build_object(
      'product_id', NEW.id,
      'signed_delta', v_delta,
      'journal_entry_id', v_entry_id,
      'compatibility_boundary', true
    )
  );

  delete from public.direct_product_stock_trace_pending
   where operation_id = v_operation_id;

  perform set_config('app.inventory_operation_id', '', true);
  perform set_config('app.inventory_source_document_type', '', true);
  perform set_config('app.inventory_source_document_id', '', true);
  perform set_config('app.inventory_source_channel', '', true);
  return NEW;
exception when others then
  perform set_config('app.inventory_operation_id', '', true);
  perform set_config('app.inventory_source_document_type', '', true);
  perform set_config('app.inventory_source_document_id', '', true);
  perform set_config('app.inventory_source_channel', '', true);
  raise;
end;
$$;

revoke all on function public.finalize_direct_product_stock_trace()
  from public, anon, authenticated;

drop trigger if exists zz_finalize_direct_product_stock_trace on public.products;
create trigger zz_finalize_direct_product_stock_trace
  after insert or update of stock_quantity, inventory_qty on public.products
  for each row execute function public.finalize_direct_product_stock_trace();

-- The legacy adjustment producer originally listened only to stock_quantity.
-- The compatibility BEFORE trigger can normalize an inventory_qty-only write,
-- but PostgreSQL UPDATE OF selection is based on the submitted SET list. Listen
-- to both columns so that normalized one-column writes still emit one movement.
drop trigger if exists trg_track_product_stock_changes on public.products;
create trigger trg_track_product_stock_changes
  after insert or update of stock_quantity, inventory_qty on public.products
  for each row execute function public.track_product_stock_changes();

commit;
