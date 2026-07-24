-- Deployment status: DEPLOYED AND VERIFIED in production
-- xzdvtzdqjeyqxnkqprtf on 2026-07-24.
-- Exact deployed SQL checksum before this status annotation:
-- 2eaacfe302a6f63c2af18ec9aa4cab0fbb0b176c7e8c8d9744e0319708f5fe0d.
-- Links physical purchase-receipt discrepancies to their exact resolution
-- documents without treating an economic resolution as a stock receipt.

begin;

do $$
declare
  v_missing text;
begin
  select string_agg(dependency.name, ', ' order by dependency.name)
    into v_missing
  from (
    values
      ('public.purchase_receipts', to_regclass('public.purchase_receipts') is not null),
      ('public.purchase_receipt_lines', to_regclass('public.purchase_receipt_lines') is not null),
      ('public.purchase_credit_notes', to_regclass('public.purchase_credit_notes') is not null),
      ('public.purchase_credit_note_lines', to_regclass('public.purchase_credit_note_lines') is not null),
      ('public.purchase_supplier_returns', to_regclass('public.purchase_supplier_returns') is not null),
      ('public.purchase_supplier_return_lines', to_regclass('public.purchase_supplier_return_lines') is not null),
      ('public.purchase_supplier_refunds', to_regclass('public.purchase_supplier_refunds') is not null),
      ('public.inventory_accounting_operations', to_regclass('public.inventory_accounting_operations') is not null),
      ('public.journal_entries', to_regclass('public.journal_entries') is not null),
      ('public.journal_lines', to_regclass('public.journal_lines') is not null),
      (
        'public.create_purchase_credit_note(uuid,jsonb,timestamptz,text,text,text,text)',
        to_regprocedure(
          'public.create_purchase_credit_note(uuid,jsonb,timestamp with time zone,text,text,text,text)'
        ) is not null
      )
  ) as dependency(name, is_present)
  where not dependency.is_present;

  if v_missing is not null then
    raise exception 'Purchase receipt resolution dependencies are missing: %', v_missing;
  end if;
end;
$$;

create table if not exists public.purchase_receipt_resolution_cases (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  purchase_invoice_id uuid not null
    references public.purchase_invoices(id) on delete restrict,
  purchase_receipt_id uuid not null,
  purchase_receipt_line_id uuid not null
    references public.purchase_receipt_lines(id) on delete restrict,
  case_number text not null,
  discrepancy_kind text not null
    check (discrepancy_kind in ('damaged', 'rejected', 'shortage')),
  discrepancy_quantity integer not null check (discrepancy_quantity > 0),
  discrepancy_reason text not null,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamp with time zone not null default clock_timestamp(),
  unique (tenant_id, id),
  unique (tenant_id, case_number),
  unique (tenant_id, purchase_receipt_line_id, discrepancy_kind),
  foreign key (tenant_id, purchase_receipt_id)
    references public.purchase_receipts(tenant_id, id) on delete restrict
);

create table if not exists public.purchase_receipt_resolution_allocations (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  case_id uuid not null,
  resolution_group_id uuid not null,
  outcome text not null check (
    outcome in (
      'credit_note',
      'later_delivery',
      'documented_loss',
      'documented_loss_reversal'
    )
  ),
  resolved_quantity integer not null check (resolved_quantity > 0),
  net_amount numeric(12,2) not null default 0
    check (net_amount >= 0 and net_amount = trunc(net_amount)),
  operation_id uuid not null,
  purchase_credit_note_line_id uuid
    references public.purchase_credit_note_lines(id) on delete restrict,
  later_receipt_line_id uuid
    references public.purchase_receipt_lines(id) on delete restrict,
  journal_entry_id uuid
    references public.journal_entries(id) on delete restrict,
  reversal_of_allocation_id uuid
    references public.purchase_receipt_resolution_allocations(id)
    on delete restrict,
  reason text not null,
  resolved_at timestamp with time zone not null,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamp with time zone not null default clock_timestamp(),
  unique (tenant_id, id),
  foreign key (tenant_id, case_id)
    references public.purchase_receipt_resolution_cases(tenant_id, id)
    on delete restrict,
  foreign key (tenant_id, operation_id)
    references public.inventory_accounting_operations(tenant_id, id)
    on delete restrict,
  check (
    (
      outcome = 'credit_note'
      and purchase_credit_note_line_id is not null
      and later_receipt_line_id is null
      and journal_entry_id is null
      and reversal_of_allocation_id is null
      and net_amount = 0
    )
    or (
      outcome = 'later_delivery'
      and purchase_credit_note_line_id is null
      and later_receipt_line_id is not null
      and journal_entry_id is null
      and reversal_of_allocation_id is null
      and net_amount = 0
    )
    or (
      outcome = 'documented_loss'
      and purchase_credit_note_line_id is null
      and later_receipt_line_id is null
      and journal_entry_id is not null
      and reversal_of_allocation_id is null
      and net_amount > 0
    )
    or (
      outcome = 'documented_loss_reversal'
      and purchase_credit_note_line_id is null
      and later_receipt_line_id is null
      and journal_entry_id is not null
      and reversal_of_allocation_id is not null
      and net_amount > 0
    )
  )
);

create index if not exists idx_purchase_receipt_resolution_cases_invoice
  on public.purchase_receipt_resolution_cases(
    tenant_id, purchase_invoice_id, created_at desc
  );
create index if not exists idx_purchase_receipt_resolution_cases_receipt
  on public.purchase_receipt_resolution_cases(
    tenant_id, purchase_receipt_id, created_at desc
  );
create index if not exists idx_purchase_receipt_resolution_allocations_case
  on public.purchase_receipt_resolution_allocations(
    tenant_id, case_id, created_at
  );
create index if not exists idx_purchase_receipt_resolution_allocations_group
  on public.purchase_receipt_resolution_allocations(
    tenant_id, resolution_group_id, created_at
  );
create unique index if not exists uq_purchase_receipt_resolution_credit_link
  on public.purchase_receipt_resolution_allocations(
    tenant_id, case_id, purchase_credit_note_line_id
  )
  where purchase_credit_note_line_id is not null;
create unique index if not exists uq_purchase_receipt_resolution_delivery_link
  on public.purchase_receipt_resolution_allocations(
    tenant_id, case_id, later_receipt_line_id
  )
  where later_receipt_line_id is not null;
create unique index if not exists uq_purchase_receipt_resolution_loss_reversal
  on public.purchase_receipt_resolution_allocations(reversal_of_allocation_id)
  where reversal_of_allocation_id is not null;

alter table public.purchase_receipt_resolution_cases enable row level security;
alter table public.purchase_receipt_resolution_allocations
  enable row level security;

drop policy if exists purchase_receipt_resolution_cases_select
  on public.purchase_receipt_resolution_cases;
create policy purchase_receipt_resolution_cases_select
  on public.purchase_receipt_resolution_cases
  for select to authenticated
  using (tenant_id = public.user_tenant_id());

drop policy if exists purchase_receipt_resolution_allocations_select
  on public.purchase_receipt_resolution_allocations;
create policy purchase_receipt_resolution_allocations_select
  on public.purchase_receipt_resolution_allocations
  for select to authenticated
  using (tenant_id = public.user_tenant_id());

revoke all on public.purchase_receipt_resolution_cases
  from public, anon, authenticated, service_role;
revoke all on public.purchase_receipt_resolution_allocations
  from public, anon, authenticated, service_role;
grant select on public.purchase_receipt_resolution_cases
  to authenticated, service_role;
grant select on public.purchase_receipt_resolution_allocations
  to authenticated, service_role;

create or replace function public.prevent_purchase_receipt_resolution_mutation()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  raise exception 'Purchase receipt resolution evidence is append-only'
    using errcode = 'check_violation';
end;
$$;

drop trigger if exists trg_purchase_receipt_resolution_cases_immutable
  on public.purchase_receipt_resolution_cases;
create trigger trg_purchase_receipt_resolution_cases_immutable
before update or delete on public.purchase_receipt_resolution_cases
for each row execute function
  public.prevent_purchase_receipt_resolution_mutation();

drop trigger if exists trg_purchase_receipt_resolution_allocations_immutable
  on public.purchase_receipt_resolution_allocations;
create trigger trg_purchase_receipt_resolution_allocations_immutable
before update or delete on public.purchase_receipt_resolution_allocations
for each row execute function
  public.prevent_purchase_receipt_resolution_mutation();

create or replace function public.guard_purchase_invoice_hard_delete()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if old.status <> 'draft' then
    raise exception
      'Only draft purchase invoices can be deleted; reverse downstream documents and return the invoice to draft first';
  end if;
  return old;
end;
$$;

drop trigger if exists trg_guard_purchase_invoice_hard_delete
  on public.purchase_invoices;
create trigger trg_guard_purchase_invoice_hard_delete
before delete on public.purchase_invoices
for each row execute function public.guard_purchase_invoice_hard_delete();

revoke all on function public.guard_purchase_invoice_hard_delete()
  from public, anon, authenticated, service_role;

create or replace view public.purchase_receipt_resolution_allocation_view
with (security_invoker = true)
as
select
  allocation.id,
  allocation.tenant_id,
  allocation.case_id,
  resolution_case.purchase_invoice_id,
  source_line.source_line_index,
  source_line.source_line_key,
  allocation.resolution_group_id,
  allocation.outcome,
  allocation.resolved_quantity,
  allocation.net_amount,
  allocation.operation_id,
  allocation.purchase_credit_note_line_id,
  credit_line.purchase_credit_note_id,
  credit_note.credit_note_number,
  credit_note.credit_note_number as purchase_credit_note_number,
  credit_note.supplier_credit_note_number,
  credit_note.status as credit_note_status,
  allocation.later_receipt_line_id,
  later_line.receipt_id as later_receipt_id,
  later_receipt.receipt_number as later_receipt_number,
  later_receipt.status as later_receipt_status,
  supplier_return_line.supplier_return_id,
  supplier_return.return_number as supplier_return_number,
  supplier_return.status as supplier_return_status,
  coalesce(refund_link.refunds, '[]'::jsonb) as supplier_refunds,
  allocation.journal_entry_id,
  journal.entry_number as journal_entry_number,
  journal.status as journal_status,
  allocation.reversal_of_allocation_id,
  loss_reversal.id as loss_reversal_allocation_id,
  source_receipt.status as source_receipt_status,
  case
    when allocation.outcome = 'credit_note'
      then coalesce(credit_note.status, 'missing')
    when allocation.outcome = 'later_delivery'
      then coalesce(later_receipt.status, 'missing')
    when allocation.outcome = 'documented_loss'
         and loss_reversal.id is not null
      then 'voided'
    when allocation.outcome = 'documented_loss'
      then coalesce(journal.status, 'missing')
    when allocation.outcome = 'documented_loss_reversal'
      then 'reversal'
    else 'missing'
  end as effective_status,
  (
    source_receipt.status = 'posted'
    and (
      (
        allocation.outcome = 'credit_note'
        and credit_note.status = 'posted'
      )
      or (
        allocation.outcome = 'later_delivery'
        and later_receipt.status = 'posted'
      )
      or (
        allocation.outcome = 'documented_loss'
        and journal.status = 'posted'
        and loss_reversal.id is null
      )
    )
  ) as is_effective,
  case
    when source_receipt.status = 'posted'
      and (
        (
          allocation.outcome = 'credit_note'
          and credit_note.status = 'posted'
        )
        or (
          allocation.outcome = 'later_delivery'
          and later_receipt.status = 'posted'
        )
        or (
          allocation.outcome = 'documented_loss'
          and journal.status = 'posted'
          and loss_reversal.id is null
        )
      )
      then allocation.resolved_quantity
    else 0
  end::integer as effective_quantity,
  allocation.reason,
  case
    when allocation.outcome = 'credit_note'
      then credit_note.void_reason
    when allocation.outcome = 'later_delivery'
      then later_receipt.void_reason
    when allocation.outcome = 'documented_loss'
      then loss_reversal.reason
    else null
  end as void_reason,
  allocation.resolved_at,
  allocation.created_by,
  allocation.created_at
from public.purchase_receipt_resolution_allocations allocation
join public.purchase_receipt_resolution_cases resolution_case
  on resolution_case.id = allocation.case_id
 and resolution_case.tenant_id = allocation.tenant_id
join public.purchase_receipts source_receipt
  on source_receipt.id = resolution_case.purchase_receipt_id
 and source_receipt.tenant_id = resolution_case.tenant_id
join public.purchase_receipt_lines source_line
  on source_line.id = resolution_case.purchase_receipt_line_id
 and source_line.tenant_id = resolution_case.tenant_id
left join public.purchase_credit_note_lines credit_line
  on credit_line.id = allocation.purchase_credit_note_line_id
 and credit_line.tenant_id = allocation.tenant_id
left join public.purchase_credit_notes credit_note
  on credit_note.id = credit_line.purchase_credit_note_id
 and credit_note.tenant_id = allocation.tenant_id
left join public.purchase_receipt_lines later_line
  on later_line.id = allocation.later_receipt_line_id
 and later_line.tenant_id = allocation.tenant_id
left join public.purchase_receipts later_receipt
  on later_receipt.id = later_line.receipt_id
 and later_receipt.tenant_id = allocation.tenant_id
left join public.purchase_supplier_return_lines supplier_return_line
  on supplier_return_line.id = credit_line.supplier_return_line_id
 and supplier_return_line.tenant_id = allocation.tenant_id
left join public.purchase_supplier_returns supplier_return
  on supplier_return.id = supplier_return_line.supplier_return_id
 and supplier_return.tenant_id = allocation.tenant_id
left join lateral (
  select jsonb_agg(
    jsonb_build_object(
      'id', refund.id,
      'refund_number', refund.refund_number,
      'status', refund.status,
      'amount', refund.amount,
      'refunded_at', refund.refunded_at
    )
    order by refund.created_at, refund.id
  ) as refunds
  from public.purchase_supplier_refunds refund
  where refund.tenant_id = allocation.tenant_id
    and refund.purchase_credit_note_id = credit_note.id
) refund_link on true
left join public.journal_entries journal
  on journal.id = allocation.journal_entry_id
 and journal.tenant_id = allocation.tenant_id
left join public.purchase_receipt_resolution_allocations loss_reversal
  on loss_reversal.reversal_of_allocation_id = allocation.id
 and loss_reversal.tenant_id = allocation.tenant_id;

create or replace view public.purchase_receipt_resolution_case_view
with (security_invoker = true)
as
select
  resolution_case.id,
  resolution_case.tenant_id,
  resolution_case.case_number,
  resolution_case.purchase_invoice_id,
  invoice.invoice_number,
  resolution_case.purchase_receipt_id,
  receipt.receipt_number,
  receipt.received_at,
  receipt.status as receipt_status,
  resolution_case.purchase_receipt_line_id,
  receipt_line.source_line_key,
  receipt_line.source_line_index,
  receipt_line.product_id,
  receipt_line.product_name,
  receipt_line.product_sku,
  receipt_line.purchase_treatment,
  resolution_case.discrepancy_kind,
  resolution_case.discrepancy_quantity,
  resolution_case.discrepancy_reason,
  coalesce(sum(allocation.effective_quantity), 0)::integer
    as resolved_quantity,
  greatest(
    resolution_case.discrepancy_quantity
      - coalesce(sum(allocation.effective_quantity), 0),
    0
  )::integer as open_quantity,
  case
    when receipt.status = 'voided' then 'voided'
    when coalesce(sum(allocation.effective_quantity), 0) = 0 then 'open'
    when coalesce(sum(allocation.effective_quantity), 0)
      < resolution_case.discrepancy_quantity
      then 'partially_resolved'
    when coalesce(sum(allocation.effective_quantity), 0)
      = resolution_case.discrepancy_quantity
      then 'resolved'
    else 'inconsistent'
  end as effective_status,
  coalesce(
    jsonb_agg(
      jsonb_build_object(
        'allocation_id', allocation.id,
        'resolution_group_id', allocation.resolution_group_id,
        'outcome', allocation.outcome,
        'resolved_quantity', allocation.resolved_quantity,
        'net_amount', allocation.net_amount,
        'effective_status', allocation.effective_status,
        'is_effective', allocation.is_effective,
        'purchase_credit_note_id', allocation.purchase_credit_note_id,
        'credit_note_number', allocation.credit_note_number,
        'later_receipt_id', allocation.later_receipt_id,
        'later_receipt_number', allocation.later_receipt_number,
        'supplier_return_id', allocation.supplier_return_id,
        'supplier_return_number', allocation.supplier_return_number,
        'supplier_refunds', allocation.supplier_refunds,
        'journal_entry_id', allocation.journal_entry_id,
        'journal_entry_number', allocation.journal_entry_number,
        'reason', allocation.reason,
        'resolved_at', allocation.resolved_at
      )
      order by allocation.resolved_at, allocation.id
    ) filter (where allocation.id is not null),
    '[]'::jsonb
  ) as resolution_history,
  resolution_case.created_by,
  resolution_case.created_at
from public.purchase_receipt_resolution_cases resolution_case
join public.purchase_receipts receipt
  on receipt.id = resolution_case.purchase_receipt_id
 and receipt.tenant_id = resolution_case.tenant_id
join public.purchase_receipt_lines receipt_line
  on receipt_line.id = resolution_case.purchase_receipt_line_id
 and receipt_line.tenant_id = resolution_case.tenant_id
join public.purchase_invoices invoice
  on invoice.id = resolution_case.purchase_invoice_id
 and invoice.tenant_id = resolution_case.tenant_id
left join public.purchase_receipt_resolution_allocation_view allocation
  on allocation.case_id = resolution_case.id
 and allocation.tenant_id = resolution_case.tenant_id
group by
  resolution_case.id,
  resolution_case.tenant_id,
  resolution_case.case_number,
  resolution_case.purchase_invoice_id,
  invoice.invoice_number,
  resolution_case.purchase_receipt_id,
  receipt.receipt_number,
  receipt.received_at,
  receipt.status,
  resolution_case.purchase_receipt_line_id,
  receipt_line.source_line_key,
  receipt_line.source_line_index,
  receipt_line.product_id,
  receipt_line.product_name,
  receipt_line.product_sku,
  receipt_line.purchase_treatment,
  resolution_case.discrepancy_kind,
  resolution_case.discrepancy_quantity,
  resolution_case.discrepancy_reason,
  resolution_case.created_by,
  resolution_case.created_at;

grant select on public.purchase_receipt_resolution_allocation_view
  to authenticated, service_role;
grant select on public.purchase_receipt_resolution_case_view
  to authenticated, service_role;

create or replace function
  public.ensure_purchase_receipt_resolution_cases(
    p_purchase_receipt_line_id uuid
  )
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_source record;
  v_discrepancy record;
begin
  select
    receipt_line.*,
    receipt.created_by as receipt_created_by
  into v_source
  from public.purchase_receipt_lines receipt_line
  join public.purchase_receipts receipt
    on receipt.id = receipt_line.receipt_id
   and receipt.tenant_id = receipt_line.tenant_id
  where receipt_line.id = p_purchase_receipt_line_id;

  if not found then
    return;
  end if;

  for v_discrepancy in
    select *
    from (
      values
        ('damaged'::text, v_source.damaged_quantity),
        ('rejected'::text, v_source.rejected_quantity),
        ('shortage'::text, v_source.shortage_quantity)
    ) as discrepancy(kind, quantity)
    where discrepancy.quantity > 0
  loop
    if not exists (
      select 1
      from public.purchase_receipt_resolution_cases resolution_case
      where resolution_case.tenant_id = v_source.tenant_id
        and resolution_case.purchase_receipt_line_id = v_source.id
        and resolution_case.discrepancy_kind = v_discrepancy.kind
    ) then
      insert into public.purchase_receipt_resolution_cases (
        tenant_id,
        purchase_invoice_id,
        purchase_receipt_id,
        purchase_receipt_line_id,
        case_number,
        discrepancy_kind,
        discrepancy_quantity,
        discrepancy_reason,
        created_by
      ) values (
        v_source.tenant_id,
        v_source.purchase_invoice_id,
        v_source.receipt_id,
        v_source.id,
        public.get_next_document_number(
          v_source.tenant_id,
          'purchase_receipt_resolution_case',
          'CR'
        ),
        v_discrepancy.kind,
        v_discrepancy.quantity,
        coalesce(
          nullif(btrim(v_source.discrepancy_reason), ''),
          'Diferencia documentada en recepción de compra'
        ),
        v_source.receipt_created_by
      );
    end if;
  end loop;
end;
$$;

create or replace function
  public.create_purchase_receipt_resolution_cases_from_line()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.ensure_purchase_receipt_resolution_cases(new.id);
  return new;
end;
$$;

create or replace function
  public.allocate_later_purchase_receipt_line(
    p_purchase_receipt_line_id uuid
  )
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_later_line public.purchase_receipt_lines%rowtype;
  v_later_receipt public.purchase_receipts%rowtype;
  v_case record;
  v_remaining integer;
  v_open integer;
  v_quantity integer;
begin
  select *
    into v_later_line
  from public.purchase_receipt_lines receipt_line
  where receipt_line.id = p_purchase_receipt_line_id;

  if not found or v_later_line.accepted_quantity <= 0 then
    return;
  end if;

  select *
    into v_later_receipt
  from public.purchase_receipts receipt
  where receipt.id = v_later_line.receipt_id
    and receipt.tenant_id = v_later_line.tenant_id;

  if not found or v_later_receipt.status <> 'posted' then
    return;
  end if;

  select greatest(
    v_later_line.accepted_quantity
      - coalesce(sum(allocation.resolved_quantity), 0),
    0
  )::integer
  into v_remaining
  from public.purchase_receipt_resolution_allocations allocation
  where allocation.tenant_id = v_later_line.tenant_id
    and allocation.outcome = 'later_delivery'
    and allocation.later_receipt_line_id = v_later_line.id;

  if v_remaining <= 0 then
    return;
  end if;

  for v_case in
    select
      resolution_case.id,
      resolution_case.discrepancy_kind,
      source_receipt.receipt_number as source_receipt_number
    from public.purchase_receipt_resolution_cases resolution_case
    join public.purchase_receipt_lines source_line
      on source_line.id = resolution_case.purchase_receipt_line_id
     and source_line.tenant_id = resolution_case.tenant_id
    join public.purchase_receipts source_receipt
      on source_receipt.id = resolution_case.purchase_receipt_id
     and source_receipt.tenant_id = resolution_case.tenant_id
    where resolution_case.tenant_id = v_later_line.tenant_id
      and resolution_case.purchase_invoice_id
        = v_later_line.purchase_invoice_id
      and source_line.source_line_key = v_later_line.source_line_key
      and source_line.id <> v_later_line.id
      and source_receipt.status = 'posted'
      and (
        source_receipt.received_at < v_later_receipt.received_at
        or (
          source_receipt.received_at = v_later_receipt.received_at
          and source_receipt.created_at < v_later_receipt.created_at
        )
        or (
          source_receipt.received_at = v_later_receipt.received_at
          and source_receipt.created_at = v_later_receipt.created_at
          and source_receipt.id < v_later_receipt.id
        )
      )
    order by
      source_receipt.received_at,
      source_receipt.created_at,
      case resolution_case.discrepancy_kind
        when 'shortage' then 1
        when 'rejected' then 2
        else 3
      end,
      resolution_case.created_at,
      resolution_case.id
    for update of resolution_case
  loop
    select open_quantity
      into v_open
    from public.purchase_receipt_resolution_case_view
    where id = v_case.id
      and tenant_id = v_later_line.tenant_id;

    v_quantity := least(v_remaining, coalesce(v_open, 0));
    if v_quantity <= 0 then
      continue;
    end if;

    insert into public.purchase_receipt_resolution_allocations (
      tenant_id,
      case_id,
      resolution_group_id,
      outcome,
      resolved_quantity,
      operation_id,
      later_receipt_line_id,
      reason,
      resolved_at,
      created_by
    ) values (
      v_later_line.tenant_id,
      v_case.id,
      v_later_receipt.id,
      'later_delivery',
      v_quantity,
      v_later_receipt.operation_id,
      v_later_line.id,
      format(
        'Recepción posterior %s aplicada a diferencia de %s',
        v_later_receipt.receipt_number,
        v_case.source_receipt_number
      ),
      v_later_receipt.received_at,
      v_later_receipt.created_by
    )
    on conflict (
      tenant_id, case_id, later_receipt_line_id
    ) where later_receipt_line_id is not null
    do nothing;

    v_remaining := v_remaining - v_quantity;
    exit when v_remaining <= 0;
  end loop;
end;
$$;

create or replace function
  public.allocate_later_purchase_receipt_line_from_trigger()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.allocate_later_purchase_receipt_line(new.id);
  return new;
end;
$$;

create or replace function
  public.guard_purchase_receipt_line_economic_quantity()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_expected_numeric numeric;
  v_prior_accepted integer;
  v_nonphysical_resolution integer;
begin
  -- Discrepancy-only observations create cases but do not consume the
  -- invoice's physical/economic quantity cap.
  if new.accepted_quantity <= 0 then
    return new;
  end if;

  -- All receipt, credit-note resolution, and documented-loss commands take
  -- this invoice lock before taking case locks. This makes the cap atomic and
  -- prevents the receipt/case lock-order deadlock.
  select coalesce(
    nullif(
      invoice.items -> new.source_line_index ->> 'quantity',
      ''
    )::numeric,
    0
  )
    into v_expected_numeric
  from public.purchase_invoices invoice
  where invoice.id = new.purchase_invoice_id
    and invoice.tenant_id = new.tenant_id
  for update;

  if not found then
    raise exception 'Purchase invoice line not found for receipt quantity guard';
  end if;
  if v_expected_numeric < 0
     or v_expected_numeric <> trunc(v_expected_numeric)
     or new.expected_quantity <> v_expected_numeric::integer then
    raise exception 'Purchase receipt expected quantity does not match invoice line';
  end if;

  select coalesce(sum(receipt_line.accepted_quantity), 0)::integer
    into v_prior_accepted
  from public.purchase_receipt_lines receipt_line
  join public.purchase_receipts receipt
    on receipt.id = receipt_line.receipt_id
   and receipt.tenant_id = receipt_line.tenant_id
  where receipt_line.tenant_id = new.tenant_id
    and receipt_line.purchase_invoice_id = new.purchase_invoice_id
    and receipt_line.source_line_key = new.source_line_key
    and receipt_line.id <> new.id
    and receipt.status = 'posted';

  select coalesce(sum(allocation.effective_quantity), 0)::integer
    into v_nonphysical_resolution
  from public.purchase_receipt_resolution_cases resolution_case
  join public.purchase_receipt_lines source_line
    on source_line.id = resolution_case.purchase_receipt_line_id
   and source_line.tenant_id = resolution_case.tenant_id
  join public.purchase_receipt_resolution_allocation_view allocation
    on allocation.case_id = resolution_case.id
   and allocation.tenant_id = resolution_case.tenant_id
  where resolution_case.tenant_id = new.tenant_id
    and resolution_case.purchase_invoice_id = new.purchase_invoice_id
    and source_line.source_line_key = new.source_line_key
    and allocation.outcome in ('credit_note', 'documented_loss');

  if v_prior_accepted
       + new.accepted_quantity
       + v_nonphysical_resolution
       > v_expected_numeric::integer then
    raise exception
      'Purchase receipt accepted quantity exceeds economically open invoice line %',
      new.source_line_index;
  end if;

  return new;
end;
$$;

drop trigger if exists
  trg_purchase_receipt_line_00_guard_economic_quantity
  on public.purchase_receipt_lines;
create trigger trg_purchase_receipt_line_00_guard_economic_quantity
before insert on public.purchase_receipt_lines
for each row execute function
  public.guard_purchase_receipt_line_economic_quantity();

drop trigger if exists
  trg_purchase_receipt_line_10_create_resolution_cases
  on public.purchase_receipt_lines;
create trigger trg_purchase_receipt_line_10_create_resolution_cases
after insert on public.purchase_receipt_lines
for each row execute function
  public.create_purchase_receipt_resolution_cases_from_line();

drop trigger if exists
  trg_purchase_receipt_line_20_allocate_later_delivery
  on public.purchase_receipt_lines;
create trigger trg_purchase_receipt_line_20_allocate_later_delivery
after insert on public.purchase_receipt_lines
for each row execute function
  public.allocate_later_purchase_receipt_line_from_trigger();

revoke all on function
  public.ensure_purchase_receipt_resolution_cases(uuid)
  from public, anon, authenticated, service_role;
revoke all on function
  public.create_purchase_receipt_resolution_cases_from_line()
  from public, anon, authenticated, service_role;
revoke all on function
  public.allocate_later_purchase_receipt_line(uuid)
  from public, anon, authenticated, service_role;
revoke all on function
  public.allocate_later_purchase_receipt_line_from_trigger()
  from public, anon, authenticated, service_role;
revoke all on function
  public.guard_purchase_receipt_line_economic_quantity()
  from public, anon, authenticated, service_role;

create or replace function public.resolve_purchase_receipt_with_credit_note(
  p_purchase_invoice_id uuid,
  p_cases jsonb,
  p_issue_date timestamp with time zone,
  p_reason_code text,
  p_reason text,
  p_supplier_credit_note_number text default null,
  p_idempotency_key text default null
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_tenant_id uuid := public.user_tenant_id();
  v_actor_id uuid := auth.uid();
  v_request jsonb;
  v_case_id uuid;
  v_quantity_numeric numeric;
  v_quantity integer;
  v_case record;
  v_existing_note_id uuid;
  v_existing_link_quantity integer;
  v_open_quantity integer;
  v_credit_lines jsonb;
  v_result jsonb;
  v_note public.purchase_credit_notes%rowtype;
  v_note_line public.purchase_credit_note_lines%rowtype;
  v_expected_quantity integer;
  v_existing_allocation record;
begin
  if v_actor_id is null or v_tenant_id is null then
    raise exception 'Authenticated employee tenant is required';
  end if;
  if nullif(btrim(p_idempotency_key), '') is null then
    raise exception 'Purchase receipt credit resolution idempotency key is required';
  end if;
  if jsonb_typeof(p_cases) <> 'array'
     or jsonb_array_length(p_cases) = 0 then
    raise exception 'Purchase receipt credit resolution requires cases';
  end if;

  perform 1
  from public.purchase_invoices invoice
  where invoice.id = p_purchase_invoice_id
    and invoice.tenant_id = v_tenant_id
  for update;
  if not found then
    raise exception 'Purchase invoice not found for current tenant';
  end if;

  select note.id
    into v_existing_note_id
  from public.purchase_credit_notes note
  where note.tenant_id = v_tenant_id
    and note.idempotency_key = btrim(p_idempotency_key);

  create temporary table if not exists
    pg_temp.purchase_receipt_credit_resolution_work (
      case_id uuid primary key,
      source_line_key text not null,
      source_line_index integer not null,
      requested_quantity integer not null
    ) on commit drop;
  truncate pg_temp.purchase_receipt_credit_resolution_work;

  for v_request in
    select value from jsonb_array_elements(p_cases)
  loop
    v_case_id := nullif(v_request->>'case_id', '')::uuid;
    v_quantity_numeric := nullif(v_request->>'quantity', '')::numeric;
    if v_case_id is null
       or v_quantity_numeric is null
       or v_quantity_numeric <= 0
       or v_quantity_numeric <> trunc(v_quantity_numeric) then
      raise exception 'Each credit resolution case requires a positive whole quantity';
    end if;
    v_quantity := v_quantity_numeric::integer;

    select
      resolution_case.*,
      receipt.status as source_receipt_status,
      receipt_line.source_line_key,
      receipt_line.source_line_index
    into v_case
    from public.purchase_receipt_resolution_cases resolution_case
    join public.purchase_receipts receipt
      on receipt.id = resolution_case.purchase_receipt_id
     and receipt.tenant_id = resolution_case.tenant_id
    join public.purchase_receipt_lines receipt_line
      on receipt_line.id = resolution_case.purchase_receipt_line_id
     and receipt_line.tenant_id = resolution_case.tenant_id
    where resolution_case.id = v_case_id
      and resolution_case.tenant_id = v_tenant_id
    for update of resolution_case;

    if not found
       or v_case.purchase_invoice_id <> p_purchase_invoice_id then
      raise exception 'Purchase receipt resolution case not found for invoice';
    end if;
    if v_case.source_receipt_status <> 'posted' then
      raise exception 'Voided purchase receipt discrepancies cannot be resolved';
    end if;

    select case_view.open_quantity
      into v_open_quantity
    from public.purchase_receipt_resolution_case_view case_view
    where case_view.id = v_case_id
      and case_view.tenant_id = v_tenant_id;

    select coalesce(sum(allocation.resolved_quantity), 0)::integer
      into v_existing_link_quantity
    from public.purchase_receipt_resolution_allocations allocation
    join public.purchase_credit_note_lines note_line
      on note_line.id = allocation.purchase_credit_note_line_id
     and note_line.tenant_id = allocation.tenant_id
    where allocation.tenant_id = v_tenant_id
      and allocation.case_id = v_case_id
      and note_line.purchase_credit_note_id = v_existing_note_id;

    if v_quantity
       > v_open_quantity + v_existing_link_quantity then
      raise exception 'Credit resolution quantity exceeds open case quantity';
    end if;

    insert into pg_temp.purchase_receipt_credit_resolution_work (
      case_id,
      source_line_key,
      source_line_index,
      requested_quantity
    ) values (
      v_case_id,
      v_case.source_line_key,
      v_case.source_line_index,
      v_quantity
    );
  end loop;

  select jsonb_agg(
    jsonb_build_object(
      'line_index', grouped.source_line_index,
      'credited_quantity', grouped.requested_quantity,
      'disposition', 'financial_only'
    )
    order by grouped.source_line_index
  )
  into v_credit_lines
  from (
    select
      source_line_index,
      sum(requested_quantity)::integer as requested_quantity
    from pg_temp.purchase_receipt_credit_resolution_work
    group by source_line_index
  ) grouped;

  v_result := public.create_purchase_credit_note(
    p_purchase_invoice_id,
    v_credit_lines,
    p_issue_date,
    p_reason_code,
    p_reason,
    p_supplier_credit_note_number,
    p_idempotency_key
  );

  select *
    into v_note
  from public.purchase_credit_notes note
  where note.id = (v_result->>'purchase_credit_note_id')::uuid
    and note.tenant_id = v_tenant_id;

  if not found
     or v_note.purchase_invoice_id <> p_purchase_invoice_id
     or v_note.status <> 'posted' then
    raise exception 'Posted purchase credit note was not created for resolution';
  end if;

  for v_case in
    select *
    from pg_temp.purchase_receipt_credit_resolution_work
    order by case_id
  loop
    select *
      into v_note_line
    from public.purchase_credit_note_lines note_line
    where note_line.tenant_id = v_tenant_id
      and note_line.purchase_credit_note_id = v_note.id
      and note_line.source_line_key = v_case.source_line_key;

    if not found or v_note_line.disposition <> 'financial_only' then
      raise exception 'Credit note line does not match receipt resolution case';
    end if;

    select sum(work.requested_quantity)::integer
      into v_expected_quantity
    from pg_temp.purchase_receipt_credit_resolution_work work
    where work.source_line_key = v_case.source_line_key;
    if v_note_line.credited_quantity <> v_expected_quantity then
      raise exception 'Credit note replay payload differs from resolution cases';
    end if;

    insert into public.purchase_receipt_resolution_allocations (
      tenant_id,
      case_id,
      resolution_group_id,
      outcome,
      resolved_quantity,
      operation_id,
      purchase_credit_note_line_id,
      reason,
      resolved_at,
      created_by
    ) values (
      v_tenant_id,
      v_case.case_id,
      v_note.id,
      'credit_note',
      v_case.requested_quantity,
      v_note.operation_id,
      v_note_line.id,
      btrim(p_reason),
      v_note.issue_date,
      v_actor_id
    )
    on conflict (
      tenant_id, case_id, purchase_credit_note_line_id
    ) where purchase_credit_note_line_id is not null
    do nothing;

    select
      allocation.resolved_quantity,
      allocation.resolution_group_id
    into v_existing_allocation
    from public.purchase_receipt_resolution_allocations allocation
    where allocation.tenant_id = v_tenant_id
      and allocation.case_id = v_case.case_id
      and allocation.purchase_credit_note_line_id = v_note_line.id;

    if v_existing_allocation.resolved_quantity
         <> v_case.requested_quantity
       or v_existing_allocation.resolution_group_id <> v_note.id then
      raise exception 'Credit resolution replay conflicts with existing allocation';
    end if;
  end loop;

  return v_result || jsonb_build_object(
    'resolution_group_id', v_note.id,
    'resolution_case_ids',
      (
        select jsonb_agg(case_id order by case_id)
        from pg_temp.purchase_receipt_credit_resolution_work
      )
  );
end;
$$;

revoke all on function public.resolve_purchase_receipt_with_credit_note(
  uuid, jsonb, timestamp with time zone, text, text, text, text
) from public, anon, authenticated, service_role;
grant execute on function public.resolve_purchase_receipt_with_credit_note(
  uuid, jsonb, timestamp with time zone, text, text, text, text
) to authenticated;

create or replace function public.resolve_purchase_receipt_with_documented_loss(
  p_purchase_invoice_id uuid,
  p_cases jsonb,
  p_effective_at timestamp with time zone,
  p_reason text,
  p_idempotency_key text
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_tenant_id uuid := public.user_tenant_id();
  v_actor_id uuid := auth.uid();
  v_operation_key text;
  v_request_hash text;
  v_existing_operation public.inventory_accounting_operations%rowtype;
  v_request jsonb;
  v_case_id uuid;
  v_quantity_numeric numeric;
  v_quantity integer;
  v_case record;
  v_group_id uuid := gen_random_uuid();
  v_operation_id uuid := gen_random_uuid();
  v_journal_id uuid := gen_random_uuid();
  v_loss_account_id uuid;
  v_inventory_account_id uuid;
  v_consumable_account_id uuid;
  v_total numeric(12,2);
  v_inventory_total numeric(12,2) := 0;
  v_consumable_total numeric(12,2) := 0;
  v_description text;
  v_open_quantity integer;
begin
  if v_actor_id is null or v_tenant_id is null then
    raise exception 'Authenticated employee tenant is required';
  end if;
  if p_effective_at is null
     or p_effective_at > clock_timestamp() + interval '5 minutes' then
    raise exception 'Valid documented loss date is required and cannot be in the future';
  end if;
  if nullif(btrim(p_reason), '') is null
     or nullif(btrim(p_idempotency_key), '') is null then
    raise exception 'Documented loss reason and idempotency key are required';
  end if;
  if jsonb_typeof(p_cases) <> 'array'
     or jsonb_array_length(p_cases) = 0 then
    raise exception 'Documented loss resolution requires cases';
  end if;

  perform 1
  from public.purchase_invoices invoice
  where invoice.id = p_purchase_invoice_id
    and invoice.tenant_id = v_tenant_id
  for update;
  if not found then
    raise exception 'Purchase invoice not found for current tenant';
  end if;

  v_operation_key := format(
    'purchase_receipt_resolution_loss:%s:%s',
    p_purchase_invoice_id,
    btrim(p_idempotency_key)
  );
  v_request_hash := md5(
    jsonb_build_object(
      'purchase_invoice_id', p_purchase_invoice_id,
      'cases', p_cases,
      'effective_at', p_effective_at,
      'reason', btrim(p_reason)
    )::text
  );

  select *
    into v_existing_operation
  from public.inventory_accounting_operations operation
  where operation.tenant_id = v_tenant_id
    and operation.operation_key = v_operation_key;

  if found then
    if v_existing_operation.document_type
         <> 'purchase_receipt_resolution_loss'
       or v_existing_operation.context->>'request_hash'
         is distinct from v_request_hash then
      raise exception 'Documented loss idempotency key belongs to another request';
    end if;
    return jsonb_build_object(
      'resolution_group_id', v_existing_operation.document_id,
      'operation_id', v_existing_operation.id,
      'journal_entry_id',
        (
          select allocation.journal_entry_id
          from public.purchase_receipt_resolution_allocations allocation
          where allocation.tenant_id = v_tenant_id
            and allocation.resolution_group_id
              = v_existing_operation.document_id
            and allocation.outcome = 'documented_loss'
          order by allocation.id
          limit 1
        ),
      'replayed', true
    );
  end if;

  create temporary table if not exists
    pg_temp.purchase_receipt_loss_resolution_work (
      case_id uuid primary key,
      requested_quantity integer not null,
      purchase_treatment text not null
        check (purchase_treatment in ('inventory', 'workshop_consumable')),
      net_amount numeric(12,2) not null
    ) on commit drop;
  truncate pg_temp.purchase_receipt_loss_resolution_work;

  for v_request in
    select value from jsonb_array_elements(p_cases)
  loop
    v_case_id := nullif(v_request->>'case_id', '')::uuid;
    v_quantity_numeric := nullif(v_request->>'quantity', '')::numeric;
    if v_case_id is null
       or v_quantity_numeric is null
       or v_quantity_numeric <= 0
       or v_quantity_numeric <> trunc(v_quantity_numeric) then
      raise exception 'Each loss resolution case requires a positive whole quantity';
    end if;
    v_quantity := v_quantity_numeric::integer;

    select
      resolution_case.*,
      receipt.status as source_receipt_status,
      receipt_line.purchase_treatment,
      receipt_line.unit_cost
    into v_case
    from public.purchase_receipt_resolution_cases resolution_case
    join public.purchase_receipts receipt
      on receipt.id = resolution_case.purchase_receipt_id
     and receipt.tenant_id = resolution_case.tenant_id
    join public.purchase_receipt_lines receipt_line
      on receipt_line.id = resolution_case.purchase_receipt_line_id
     and receipt_line.tenant_id = resolution_case.tenant_id
    where resolution_case.id = v_case_id
      and resolution_case.tenant_id = v_tenant_id
    for update of resolution_case;

    if not found
       or v_case.purchase_invoice_id <> p_purchase_invoice_id then
      raise exception 'Purchase receipt resolution case not found for invoice';
    end if;
    if v_case.source_receipt_status <> 'posted' then
      raise exception 'Voided purchase receipt discrepancies cannot be resolved';
    end if;
    if v_case.purchase_treatment
         not in ('inventory', 'workshop_consumable') then
      raise exception 'Unsupported purchase treatment for documented loss';
    end if;

    select case_view.open_quantity
      into v_open_quantity
    from public.purchase_receipt_resolution_case_view case_view
    where case_view.id = v_case_id
      and case_view.tenant_id = v_tenant_id;

    if v_quantity > v_open_quantity then
      raise exception 'Documented loss quantity exceeds open case quantity';
    end if;
    if public.clp_round(v_case.unit_cost * v_quantity) <= 0 then
      raise exception 'Documented loss requires a positive inventory value';
    end if;

    insert into pg_temp.purchase_receipt_loss_resolution_work (
      case_id,
      requested_quantity,
      purchase_treatment,
      net_amount
    ) values (
      v_case_id,
      v_quantity,
      v_case.purchase_treatment,
      public.clp_round(v_case.unit_cost * v_quantity)
    );
  end loop;

  select
    public.clp_round(sum(work.net_amount)),
    public.clp_round(
      coalesce(
        sum(work.net_amount)
          filter (where work.purchase_treatment = 'inventory'),
        0
      )
    ),
    public.clp_round(
      coalesce(
        sum(work.net_amount)
          filter (where work.purchase_treatment = 'workshop_consumable'),
        0
      )
    )
    into v_total, v_inventory_total, v_consumable_total
  from pg_temp.purchase_receipt_loss_resolution_work work;

  if coalesce(v_total, 0) <= 0 then
    raise exception 'Documented loss requires a positive inventory value';
  end if;

  v_description := format(
    'Pérdida documentada de recepción de compra: %s',
    btrim(p_reason)
  );
  v_loss_account_id := public.ensure_account(
    v_tenant_id,
    '5208',
    'Pérdidas por Mercadería No Recibida',
    'expense',
    'operatingExpense',
    'Mercadería facturada que no fue recibida ni recuperada del proveedor',
    null
  );
  if v_inventory_total > 0 then
    v_inventory_account_id := public.ensure_account(
      v_tenant_id,
      '1105',
      'Inventarios',
      'asset',
      'currentAsset',
      'Valor del inventario de productos',
      null
    );
  end if;
  if v_consumable_total > 0 then
    v_consumable_account_id := public.ensure_account(
      v_tenant_id,
      '5101',
      'Consumibles de Taller',
      'expense',
      'costOfGoodsSold',
      'Materiales y consumibles de taller',
      null
    );
  end if;

  insert into public.inventory_accounting_operations (
    id,
    tenant_id,
    operation_key,
    source_channel,
    action,
    document_type,
    document_id,
    actor_id,
    executor,
    context
  ) values (
    v_operation_id,
    v_tenant_id,
    v_operation_key,
    'purchase_receipt_resolution',
    'document_loss',
    'purchase_receipt_resolution_loss',
    v_group_id,
    v_actor_id,
    'database_command',
    jsonb_build_object(
      'purchase_invoice_id', p_purchase_invoice_id,
      'request_hash', v_request_hash,
      'reason', btrim(p_reason),
      'stock_effect', 'none',
      'total', v_total,
      'inventory_total', v_inventory_total,
      'workshop_consumable_total', v_consumable_total
    )
  );

  perform public.append_inventory_accounting_checkpoint(
    v_operation_id,
    'accepted',
    'started',
    'purchase_invoice',
    p_purchase_invoice_id,
    jsonb_build_object(
      'case_count',
      (select count(*) from pg_temp.purchase_receipt_loss_resolution_work)
    )
  );

  insert into public.journal_entries (
    id,
    tenant_id,
    entry_number,
    entry_date,
    description,
    type,
    source_module,
    source_reference,
    status,
    total_debit,
    total_credit,
    operation_id,
    source_document_type,
    source_document_id,
    created_by,
    created_at,
    updated_at
  ) values (
    v_journal_id,
    v_tenant_id,
    public.get_next_document_number(v_tenant_id, 'journal_entry'),
    p_effective_at,
    v_description,
    'purchase_receipt_loss',
    'purchase_receipt_resolutions',
    v_group_id::text,
    'posted',
    v_total,
    v_total,
    v_operation_id,
    'purchase_receipt_resolution_loss',
    v_group_id,
    v_actor_id,
    clock_timestamp(),
    clock_timestamp()
  );

  insert into public.journal_lines (
    id,
    tenant_id,
    entry_id,
    account_id,
    account_code,
    account_name,
    description,
    debit_amount,
    credit_amount,
    created_at,
    updated_at
  ) values (
    gen_random_uuid(),
    v_tenant_id,
    v_journal_id,
    v_loss_account_id,
    '5208',
    'Pérdidas por Mercadería No Recibida',
    v_description,
    v_total,
    0,
    clock_timestamp(),
    clock_timestamp()
  );

  if v_inventory_total > 0 then
    insert into public.journal_lines (
      id,
      tenant_id,
      entry_id,
      account_id,
      account_code,
      account_name,
      description,
      debit_amount,
      credit_amount,
      created_at,
      updated_at
    ) values (
      gen_random_uuid(),
      v_tenant_id,
      v_journal_id,
      v_inventory_account_id,
      '1105',
      'Inventarios',
      v_description,
      0,
      v_inventory_total,
      clock_timestamp(),
      clock_timestamp()
    );
  end if;

  if v_consumable_total > 0 then
    insert into public.journal_lines (
      id,
      tenant_id,
      entry_id,
      account_id,
      account_code,
      account_name,
      description,
      debit_amount,
      credit_amount,
      created_at,
      updated_at
    ) values (
      gen_random_uuid(),
      v_tenant_id,
      v_journal_id,
      v_consumable_account_id,
      '5101',
      'Consumibles de Taller',
      v_description,
      0,
      v_consumable_total,
      clock_timestamp(),
      clock_timestamp()
    );
  end if;

  insert into public.purchase_receipt_resolution_allocations (
    tenant_id,
    case_id,
    resolution_group_id,
    outcome,
    resolved_quantity,
    net_amount,
    operation_id,
    journal_entry_id,
    reason,
    resolved_at,
    created_by
  )
  select
    v_tenant_id,
    work.case_id,
    v_group_id,
    'documented_loss',
    work.requested_quantity,
    work.net_amount,
    v_operation_id,
    v_journal_id,
    btrim(p_reason),
    p_effective_at,
    v_actor_id
  from pg_temp.purchase_receipt_loss_resolution_work work;

  perform public.append_inventory_accounting_checkpoint(
    v_operation_id,
    'inventory_applied',
    'completed',
    'purchase_receipt_resolution_loss',
    v_group_id,
    jsonb_build_object('movement_count', 0, 'stock_effect', 'none')
  );
  perform public.append_inventory_accounting_checkpoint(
    v_operation_id,
    'journal_posted',
    'completed',
    'journal_entry',
    v_journal_id,
    jsonb_build_object('debit', v_total, 'credit', v_total)
  );
  perform public.append_inventory_accounting_checkpoint(
    v_operation_id,
    'invariants_verified',
    'completed',
    'purchase_receipt_resolution_loss',
    v_group_id,
    jsonb_build_object('balanced_journal', true, 'stock_effect', 'none')
  );
  update public.inventory_accounting_operations
  set
    outcome = 'completed',
    completed_at = clock_timestamp(),
    after_snapshot = jsonb_build_object(
      'resolution_group_id', v_group_id,
      'journal_entry_id', v_journal_id,
      'total', v_total
    )
  where id = v_operation_id
    and tenant_id = v_tenant_id;
  perform public.append_inventory_accounting_checkpoint(
    v_operation_id,
    'completed',
    'completed',
    'purchase_receipt_resolution_loss',
    v_group_id,
    jsonb_build_object('journal_entry_id', v_journal_id)
  );

  return jsonb_build_object(
    'resolution_group_id', v_group_id,
    'operation_id', v_operation_id,
    'journal_entry_id', v_journal_id,
    'total', v_total,
    'replayed', false
  );
end;
$$;

create or replace function public.void_purchase_receipt_documented_loss(
  p_resolution_group_id uuid,
  p_reason text,
  p_idempotency_key text
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_tenant_id uuid := public.user_tenant_id();
  v_actor_id uuid := auth.uid();
  v_operation_key text;
  v_existing_operation public.inventory_accounting_operations%rowtype;
  v_original_operation_id uuid;
  v_original_journal_id uuid;
  v_original_journal public.journal_entries%rowtype;
  v_void_group_id uuid := gen_random_uuid();
  v_operation_id uuid := gen_random_uuid();
  v_journal_id uuid := gen_random_uuid();
  v_count integer;
  v_line record;
begin
  if v_actor_id is null or v_tenant_id is null then
    raise exception 'Authenticated employee tenant is required';
  end if;
  if nullif(btrim(p_reason), '') is null
     or nullif(btrim(p_idempotency_key), '') is null then
    raise exception 'Documented loss void reason and idempotency key are required';
  end if;

  v_operation_key := format(
    'purchase_receipt_resolution_loss_void:%s:%s',
    p_resolution_group_id,
    btrim(p_idempotency_key)
  );
  select *
    into v_existing_operation
  from public.inventory_accounting_operations operation
  where operation.tenant_id = v_tenant_id
    and operation.operation_key = v_operation_key;
  if found then
    return jsonb_build_object(
      'resolution_group_id', p_resolution_group_id,
      'void_resolution_group_id', v_existing_operation.document_id,
      'operation_id', v_existing_operation.id,
      'journal_entry_id',
        (
          select allocation.journal_entry_id
          from public.purchase_receipt_resolution_allocations allocation
          where allocation.tenant_id = v_tenant_id
            and allocation.resolution_group_id
              = v_existing_operation.document_id
            and allocation.outcome = 'documented_loss_reversal'
          order by allocation.id
          limit 1
        ),
      'replayed', true
    );
  end if;

  perform 1
  from public.purchase_receipt_resolution_allocations allocation
  where allocation.tenant_id = v_tenant_id
    and allocation.resolution_group_id = p_resolution_group_id
    and allocation.outcome = 'documented_loss'
  order by allocation.id
  for update;

  select count(*)::integer
  into v_count
  from public.purchase_receipt_resolution_allocations allocation
  where allocation.tenant_id = v_tenant_id
    and allocation.resolution_group_id = p_resolution_group_id
    and allocation.outcome = 'documented_loss';

  if v_count = 0 then
    raise exception 'Documented loss resolution group not found';
  end if;

  select
    allocation.operation_id,
    allocation.journal_entry_id
  into
    v_original_operation_id,
    v_original_journal_id
  from public.purchase_receipt_resolution_allocations allocation
  where allocation.tenant_id = v_tenant_id
    and allocation.resolution_group_id = p_resolution_group_id
    and allocation.outcome = 'documented_loss'
  order by allocation.id
  limit 1;
  if exists (
    select 1
    from public.purchase_receipt_resolution_allocations reversal
    join public.purchase_receipt_resolution_allocations original
      on original.id = reversal.reversal_of_allocation_id
     and original.tenant_id = reversal.tenant_id
    where original.tenant_id = v_tenant_id
      and original.resolution_group_id = p_resolution_group_id
      and reversal.outcome = 'documented_loss_reversal'
  ) then
    raise exception 'Documented loss resolution is already voided';
  end if;
  if exists (
    select 1
    from public.purchase_receipt_resolution_allocations allocation
    where allocation.tenant_id = v_tenant_id
      and allocation.resolution_group_id = p_resolution_group_id
      and (
        allocation.operation_id <> v_original_operation_id
        or allocation.journal_entry_id <> v_original_journal_id
      )
  ) then
    raise exception 'Documented loss resolution group has inconsistent evidence';
  end if;

  select *
    into v_original_journal
  from public.journal_entries journal
  where journal.id = v_original_journal_id
    and journal.tenant_id = v_tenant_id;
  if not found or v_original_journal.status <> 'posted' then
    raise exception 'Original documented loss journal is not posted';
  end if;

  insert into public.inventory_accounting_operations (
    id,
    tenant_id,
    operation_key,
    source_channel,
    action,
    document_type,
    document_id,
    actor_id,
    executor,
    context
  ) values (
    v_operation_id,
    v_tenant_id,
    v_operation_key,
    'purchase_receipt_resolution',
    'void',
    'purchase_receipt_resolution_loss',
    v_void_group_id,
    v_actor_id,
    'database_command',
    jsonb_build_object(
      'original_resolution_group_id', p_resolution_group_id,
      'original_operation_id', v_original_operation_id,
      'reason', btrim(p_reason),
      'stock_effect', 'none'
    )
  );

  perform public.append_inventory_accounting_checkpoint(
    v_operation_id,
    'accepted',
    'started',
    'purchase_receipt_resolution_loss',
    p_resolution_group_id,
    jsonb_build_object('reason', btrim(p_reason))
  );

  insert into public.journal_entries (
    id,
    tenant_id,
    entry_number,
    entry_date,
    description,
    type,
    source_module,
    source_reference,
    status,
    total_debit,
    total_credit,
    operation_id,
    source_document_type,
    source_document_id,
    created_by,
    reversal_of_id,
    created_at,
    updated_at
  ) values (
    v_journal_id,
    v_tenant_id,
    public.get_next_document_number(v_tenant_id, 'journal_entry'),
    clock_timestamp(),
    format(
      'Anulación de pérdida documentada: %s',
      btrim(p_reason)
    ),
    'purchase_receipt_loss_void',
    'purchase_receipt_resolutions',
    v_void_group_id::text,
    'posted',
    v_original_journal.total_credit,
    v_original_journal.total_debit,
    v_operation_id,
    'purchase_receipt_resolution_loss',
    v_void_group_id,
    v_actor_id,
    v_original_journal.id,
    clock_timestamp(),
    clock_timestamp()
  );

  for v_line in
    select *
    from public.journal_lines journal_line
    where journal_line.entry_id = v_original_journal.id
    order by journal_line.id
  loop
    insert into public.journal_lines (
      id,
      tenant_id,
      entry_id,
      account_id,
      account_code,
      account_name,
      description,
      debit_amount,
      credit_amount,
      created_at,
      updated_at
    ) values (
      gen_random_uuid(),
      v_tenant_id,
      v_journal_id,
      v_line.account_id,
      v_line.account_code,
      v_line.account_name,
      format('Anulación: %s', v_line.description),
      v_line.credit_amount,
      v_line.debit_amount,
      clock_timestamp(),
      clock_timestamp()
    );
  end loop;

  insert into public.purchase_receipt_resolution_allocations (
    tenant_id,
    case_id,
    resolution_group_id,
    outcome,
    resolved_quantity,
    net_amount,
    operation_id,
    journal_entry_id,
    reversal_of_allocation_id,
    reason,
    resolved_at,
    created_by
  )
  select
    original.tenant_id,
    original.case_id,
    v_void_group_id,
    'documented_loss_reversal',
    original.resolved_quantity,
    original.net_amount,
    v_operation_id,
    v_journal_id,
    original.id,
    btrim(p_reason),
    clock_timestamp(),
    v_actor_id
  from public.purchase_receipt_resolution_allocations original
  where original.tenant_id = v_tenant_id
    and original.resolution_group_id = p_resolution_group_id
    and original.outcome = 'documented_loss'
  order by original.id;

  perform public.append_inventory_accounting_checkpoint(
    v_operation_id,
    'inventory_applied',
    'completed',
    'purchase_receipt_resolution_loss',
    p_resolution_group_id,
    jsonb_build_object('movement_count', 0, 'stock_effect', 'none')
  );
  perform public.append_inventory_accounting_checkpoint(
    v_operation_id,
    'journal_reversed',
    'completed',
    'journal_entry',
    v_journal_id,
    jsonb_build_object('reversal_of_id', v_original_journal.id)
  );
  perform public.append_inventory_accounting_checkpoint(
    v_operation_id,
    'invariants_verified',
    'completed',
    'purchase_receipt_resolution_loss',
    p_resolution_group_id,
    jsonb_build_object('balanced_journal', true, 'stock_effect', 'none')
  );
  update public.inventory_accounting_operations
  set
    outcome = 'completed',
    completed_at = clock_timestamp(),
    after_snapshot = jsonb_build_object(
      'original_resolution_group_id', p_resolution_group_id,
      'void_resolution_group_id', v_void_group_id,
      'journal_entry_id', v_journal_id
    )
  where id = v_operation_id
    and tenant_id = v_tenant_id;
  perform public.append_inventory_accounting_checkpoint(
    v_operation_id,
    'completed',
    'completed',
    'purchase_receipt_resolution_loss',
    p_resolution_group_id,
    jsonb_build_object('void_resolution_group_id', v_void_group_id)
  );

  return jsonb_build_object(
    'resolution_group_id', p_resolution_group_id,
    'void_resolution_group_id', v_void_group_id,
    'operation_id', v_operation_id,
    'journal_entry_id', v_journal_id,
    'replayed', false
  );
end;
$$;

revoke all on function
  public.resolve_purchase_receipt_with_documented_loss(
    uuid, jsonb, timestamp with time zone, text, text
  )
  from public, anon, authenticated, service_role;
grant execute on function
  public.resolve_purchase_receipt_with_documented_loss(
    uuid, jsonb, timestamp with time zone, text, text
  )
  to authenticated;

revoke all on function public.void_purchase_receipt_documented_loss(
  uuid, text, text
) from public, anon, authenticated, service_role;
grant execute on function public.void_purchase_receipt_documented_loss(
  uuid, text, text
) to authenticated;

create or replace function
  public.prevent_receipt_void_with_active_resolutions()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if old.status = 'posted'
     and new.status = 'voided'
     and exists (
       select 1
       from public.purchase_receipt_resolution_cases resolution_case
       join public.purchase_receipt_resolution_allocation_view allocation
         on allocation.case_id = resolution_case.id
        and allocation.tenant_id = resolution_case.tenant_id
       where resolution_case.tenant_id = old.tenant_id
         and resolution_case.purchase_receipt_id = old.id
         and allocation.is_effective
     ) then
    raise exception
      'Void active receipt discrepancy resolutions before voiding this purchase receipt';
  end if;
  return new;
end;
$$;

create or replace function
  public.prevent_receipt_void_operation_with_active_resolutions()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.document_type = 'purchase_receipt'
     and new.action = 'void'
     and exists (
       select 1
       from public.purchase_receipt_resolution_cases resolution_case
       join public.purchase_receipt_resolution_allocation_view allocation
         on allocation.case_id = resolution_case.id
        and allocation.tenant_id = resolution_case.tenant_id
       where resolution_case.tenant_id = new.tenant_id
         and resolution_case.purchase_receipt_id = new.document_id
         and allocation.is_effective
     ) then
    raise exception
      'Void active receipt discrepancy resolutions before voiding this purchase receipt';
  end if;
  return new;
end;
$$;

drop trigger if exists
  trg_prevent_receipt_void_with_active_resolutions
  on public.purchase_receipts;
create trigger trg_prevent_receipt_void_with_active_resolutions
before update of status on public.purchase_receipts
for each row execute function
  public.prevent_receipt_void_with_active_resolutions();

drop trigger if exists
  trg_prevent_receipt_void_operation_with_active_resolutions
  on public.inventory_accounting_operations;
create trigger trg_prevent_receipt_void_operation_with_active_resolutions
before insert on public.inventory_accounting_operations
for each row execute function
  public.prevent_receipt_void_operation_with_active_resolutions();

revoke all on function
  public.prevent_receipt_void_with_active_resolutions()
  from public, anon, authenticated, service_role;
revoke all on function
  public.prevent_receipt_void_operation_with_active_resolutions()
  from public, anon, authenticated, service_role;

do $$
declare
  v_line record;
begin
  for v_line in
    select receipt_line.id
    from public.purchase_receipt_lines receipt_line
    where receipt_line.damaged_quantity > 0
       or receipt_line.rejected_quantity > 0
       or receipt_line.shortage_quantity > 0
    order by receipt_line.created_at, receipt_line.id
  loop
    perform public.ensure_purchase_receipt_resolution_cases(v_line.id);
  end loop;

  for v_line in
    select receipt_line.id
    from public.purchase_receipt_lines receipt_line
    join public.purchase_receipts receipt
      on receipt.id = receipt_line.receipt_id
     and receipt.tenant_id = receipt_line.tenant_id
    where receipt_line.accepted_quantity > 0
      and receipt.status = 'posted'
    order by
      receipt.received_at,
      receipt.created_at,
      receipt.id,
      receipt_line.source_line_index,
      receipt_line.id
  loop
    perform public.allocate_later_purchase_receipt_line(v_line.id);
  end loop;
end;
$$;

comment on table public.purchase_receipt_resolution_cases is
  'One immutable discrepancy case per receipt line and damaged/rejected/shortage kind.';
comment on table public.purchase_receipt_resolution_allocations is
  'Append-only quantity allocations linking a discrepancy case to an exact credit note, later receipt, or zero-stock documented-loss journal.';
comment on view public.purchase_receipt_resolution_case_view is
  'Tenant-scoped effective discrepancy state. A credit-note void, later-receipt void, or documented-loss reversal automatically reopens quantity.';
comment on view public.purchase_receipt_resolution_allocation_view is
  'Typed resolution links with effective downstream status and derived supplier-return/refund documents.';
comment on function public.resolve_purchase_receipt_with_credit_note(
  uuid, jsonb, timestamp with time zone, text, text, text, text
) is
  'Atomically reuses create_purchase_credit_note and maps requested receipt discrepancy cases to the exact posted credit-note lines; zero stock effect.';
comment on function public.guard_purchase_receipt_line_economic_quantity() is
  'Serializes on the invoice and prevents accepted physical quantity plus effective credit/loss resolutions from exceeding the invoice line quantity.';
comment on function public.guard_purchase_invoice_hard_delete() is
  'Allows hard deletion only for draft purchase invoices; posted financial and inventory evidence must be reversed first and remains FK-protected.';
comment on function public.resolve_purchase_receipt_with_documented_loss(
  uuid, jsonb, timestamp with time zone, text, text
) is
  'Posts DR 5208 against CR 1105 inventory or CR 5101 workshop consumables for unresolved never-received value; creates no stock movement.';
comment on function public.void_purchase_receipt_documented_loss(
  uuid, text, text
) is
  'Appends an exact reversing journal and reversal allocations; creates no stock movement and preserves original evidence.';

commit;
