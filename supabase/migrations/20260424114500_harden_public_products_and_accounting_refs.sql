-- Harden public product exposure and accounting reference cleanup.
--
-- Safe deployment intent:
-- - Keep internal ERP product search untouched.
-- - Add a public storefront search RPC that enforces publication flags server-side.
-- - Replace broad journal entry delete access with tenant/role-scoped access.
-- - Fix the stale sales invoice journal delete helper to use invoice_number.
-- - Keep journal entry header totals aligned with their lines.
-- - Stop obsolete helper RPCs from being callable directly from clients.

begin;

-- ---------------------------------------------------------------------------
-- Journal entry delete policy
-- ---------------------------------------------------------------------------

drop policy if exists "Authenticated users can delete journal_entries"
  on public.journal_entries;
drop policy if exists journal_entries_delete
  on public.journal_entries;

create policy journal_entries_delete
  on public.journal_entries
  for delete
  to authenticated
  using (
    tenant_id = public.user_tenant_id()
    and exists (
      select 1
      from public.user_profiles up
      where up.user_id = auth.uid()
        and up.tenant_id = journal_entries.tenant_id
        and up.role in ('admin', 'manager', 'accountant')
    )
  );

-- ---------------------------------------------------------------------------
-- Public product visibility policies
-- ---------------------------------------------------------------------------

drop policy if exists public_products_select on public.products;
drop policy if exists public_products_select_authenticated on public.products;

create policy public_products_select
  on public.products
  for select
  to anon
  using (
    is_active = true
    and coalesce(is_published, false) = true
    and coalesce(show_on_website, false) = true
  );

create policy public_products_select_authenticated
  on public.products
  for select
  to authenticated
  using (
    is_active = true
    and coalesce(is_published, false) = true
    and coalesce(show_on_website, false) = true
  );

-- ---------------------------------------------------------------------------
-- Public storefront search
-- ---------------------------------------------------------------------------

create or replace function public.search_public_products(
  p_search_term text,
  p_tenant_id uuid,
  p_limit integer default 10
)
returns setof public.products
language sql
security definer
set search_path = public
stable
as $$
  with q as (
    select
      trim(coalesce(p_search_term, '')) as term,
      regexp_split_to_array(lower(trim(coalesce(p_search_term, ''))), '\s+') as tokens
  )
  select p.*
  from public.products p
  cross join q
  where q.term <> ''
    and p.tenant_id = p_tenant_id
    and p.is_active = true
    and coalesce(p.is_published, false) = true
    and coalesce(p.show_on_website, false) = true
    and not exists (
      select 1
      from unnest(q.tokens) token
      where token <> ''
        and lower(
          concat_ws(
            ' ',
            p.name,
            p.sku,
            p.barcode,
            p.description,
            p.website_description,
            p.brand,
            p.model,
            p.manufacturer,
            p.manufacturer_sku,
            p.gtin
          )
        ) not like '%' || token || '%'
    )
  order by
    case when lower(p.sku) = lower(q.term) then 0 else 1 end,
    case when lower(p.name) = lower(q.term) then 0 else 1 end,
    case when lower(p.name) like lower(q.term) || '%' then 0 else 1 end,
    p.name asc
  limit greatest(p_limit, 0);
$$;

grant execute on function public.search_public_products(text, uuid, integer)
  to anon, authenticated;

-- ---------------------------------------------------------------------------
-- Sales invoice journal entry cleanup helper
-- ---------------------------------------------------------------------------

create or replace function public.delete_sales_invoice_journal_entry(
  p_invoice_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_invoice_number text;
  v_tenant_id uuid;
begin
  if p_invoice_id is null then
    return;
  end if;

  select si.invoice_number, si.tenant_id
    into v_invoice_number, v_tenant_id
    from public.sales_invoices si
   where si.id = p_invoice_id;

  if v_tenant_id is null then
    return;
  end if;

  delete from public.journal_entries je
   where je.tenant_id = v_tenant_id
     and je.source_module = 'sales_invoices'
     and je.source_reference in (
       coalesce(nullif(v_invoice_number, ''), p_invoice_id::text),
       p_invoice_id::text
     );
end;
$$;

grant execute on function public.delete_sales_invoice_journal_entry(uuid)
  to authenticated;

-- ---------------------------------------------------------------------------
-- Purchase invoice reversal safety
-- ---------------------------------------------------------------------------

create or replace function public.handle_purchase_invoice_reversal()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if tg_op <> 'UPDATE' then
    return new;
  end if;

  -- The active AFTER trigger handles received -> draft/confirmed inventory
  -- restoration. The old BEFORE trigger called stale helper functions that
  -- reference legacy columns and can block normal reversals.
  if old.status = 'paid' and new.status = 'draft' then
    raise exception
      'Cannot revert paid purchase invoice % directly to draft; reverse payment/receipt state first',
      coalesce(new.invoice_number, new.id::text)
      using errcode = 'check_violation';
  end if;

  return new;
end;
$$;

revoke execute on function public.reverse_purchase_invoice_inventory(uuid)
  from public, anon, authenticated;
revoke execute on function public.reverse_purchase_invoice_journal_entry(uuid)
  from public, anon, authenticated;
revoke execute on function public.create_prepaid_purchase_confirmation_entry(uuid)
  from public, anon, authenticated;
revoke execute on function public.settle_prepaid_inventory_on_order(uuid)
  from public, anon, authenticated;
revoke execute on function public.migrate_accounts_to_uuid()
  from public, anon, authenticated;
revoke execute on function public.create_sales_invoice_journal_entry(jsonb)
  from public, anon, authenticated;
revoke execute on function public.create_sales_invoice_journal_entry(
  public.sales_invoices
) from public, anon, authenticated;
revoke execute on function public.create_purchase_invoice_journal_entry(uuid)
  from public, anon, authenticated;
revoke execute on function public.create_purchase_invoice_journal_entry(
  public.purchase_invoices
) from public, anon, authenticated;
revoke execute on function public.cancel_online_order(uuid, text, numeric)
  from public, anon, authenticated;
revoke execute on function public.update_online_order_status(
  uuid, text, text, text, text, text
) from public, anon, authenticated;
revoke execute on function public.calculate_payroll(uuid, uuid, integer, integer)
  from public, anon, authenticated;
revoke execute on function public.parse_description_to_tasks(
  uuid, uuid, uuid, text
) from public, anon, authenticated;
revoke execute on function public.parse_description_to_tasks(
  uuid, uuid, uuid, uuid, text
) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Journal entry header total sync
-- ---------------------------------------------------------------------------

create or replace function public.recalculate_journal_entry_totals(
  p_entry_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if p_entry_id is null then
    return;
  end if;

  update public.journal_entries je
     set total_debit = coalesce(lines.total_debit, 0),
         total_credit = coalesce(lines.total_credit, 0),
         updated_at = now()
    from (
      select
        coalesce(sum(coalesce(jl.debit_amount, 0)), 0)::numeric(14, 2)
          as total_debit,
        coalesce(sum(coalesce(jl.credit_amount, 0)), 0)::numeric(14, 2)
          as total_credit
      from public.journal_lines jl
      where jl.entry_id = p_entry_id
    ) lines
   where je.id = p_entry_id;
end;
$$;

grant execute on function public.recalculate_journal_entry_totals(uuid)
  to authenticated;

create or replace function public.sync_journal_entry_totals_from_lines()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'DELETE' then
    perform public.recalculate_journal_entry_totals(old.entry_id);
    return old;
  end if;

  if tg_op = 'UPDATE' and old.entry_id is distinct from new.entry_id then
    perform public.recalculate_journal_entry_totals(old.entry_id);
  end if;

  perform public.recalculate_journal_entry_totals(new.entry_id);
  return new;
end;
$$;

drop trigger if exists trg_sync_journal_entry_totals_from_lines
  on public.journal_lines;

create trigger trg_sync_journal_entry_totals_from_lines
after insert or update or delete on public.journal_lines
for each row
execute function public.sync_journal_entry_totals_from_lines();

commit;
