-- Keep expense numbering ahead of every preserved expense journal reference.
-- Deleted legacy expenses may leave valid accounting evidence behind; those
-- journal references must never be reissued to a new expense.

create or replace function public.get_next_document_number(
  p_tenant_id uuid,
  p_document_type text,
  p_prefix text default null
) returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor_tenant_id uuid;
  v_next_number integer;
  v_max_existing integer := 0;
  v_max_journal_reference integer := 0;
  v_prefix text;
  v_table_name text;
  v_column_name text;
  v_formatted_number text;
begin
  v_actor_tenant_id := public.user_tenant_id();

  if auth.uid() is not null then
    if v_actor_tenant_id is null then
      raise exception 'Could not resolve tenant for authenticated user';
    end if;

    if p_tenant_id is null or p_tenant_id <> v_actor_tenant_id then
      raise exception 'Cross-tenant document sequence access is not allowed';
    end if;
  end if;

  v_prefix := coalesce(p_prefix, case p_document_type
    when 'sales_invoice' then 'FV'
    when 'purchase_invoice' then 'FC'
    when 'sales_payment' then 'PV'
    when 'purchase_payment' then 'PC'
    when 'journal_entry' then 'AC'
    when 'mechanic_job' then 'PG'
    when 'stock_adjustment' then 'AJ'
    when 'expense' then 'GTO'
    else 'DOC'
  end);

  case p_document_type
    when 'sales_invoice' then
      v_table_name := 'sales_invoices';
      v_column_name := 'invoice_number';
    when 'purchase_invoice' then
      v_table_name := 'purchase_invoices';
      v_column_name := 'invoice_number';
    when 'sales_payment' then
      v_table_name := 'sales_payments';
      v_column_name := 'payment_number';
    when 'purchase_payment' then
      v_table_name := 'purchase_payments';
      v_column_name := 'payment_number';
    when 'journal_entry' then
      v_table_name := 'journal_entries';
      v_column_name := 'entry_number';
    when 'mechanic_job' then
      v_table_name := 'mechanic_jobs';
      v_column_name := 'job_number';
    when 'stock_adjustment' then
      v_table_name := 'stock_adjustments';
      v_column_name := 'reference';
    when 'expense' then
      v_table_name := 'expenses';
      v_column_name := 'expense_number';
    else
      v_table_name := null;
      v_column_name := null;
  end case;

  if v_table_name is not null and v_column_name is not null then
    execute format(
      'select coalesce(max((substring(%1$I from ''([0-9]+)$''))::integer), 0)
         from public.%2$I
        where tenant_id = $1
          and %1$I ~ $2',
      v_column_name,
      v_table_name
    )
    into v_max_existing
    using p_tenant_id, '^' || v_prefix || '-[0-9]+$';
  end if;

  if p_document_type = 'expense' then
    select coalesce(
      max((substring(entry.source_reference from '([0-9]+)$'))::integer),
      0
    )
    into v_max_journal_reference
    from public.journal_entries entry
    where entry.tenant_id = p_tenant_id
      and entry.source_module = 'expenses'
      and entry.source_reference ~ ('^' || v_prefix || '-[0-9]+$');

    v_max_existing := greatest(v_max_existing, v_max_journal_reference);
  end if;

  insert into public.document_sequences (tenant_id, document_type, last_number)
  values (p_tenant_id, p_document_type, greatest(v_max_existing, 0) + 1)
  on conflict (tenant_id, document_type)
  do update set
    last_number = greatest(
      public.document_sequences.last_number,
      v_max_existing
    ) + 1,
    updated_at = now()
  returning last_number into v_next_number;

  v_formatted_number := v_prefix || '-' || lpad(v_next_number::text, 5, '0');
  return v_formatted_number;
end;
$$;

create or replace function public.preview_next_document_number(
  p_tenant_id uuid,
  p_document_type text,
  p_prefix text default null
) returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor_tenant_id uuid;
  v_current_number integer;
  v_max_existing integer := 0;
  v_max_journal_reference integer := 0;
  v_next_number integer;
  v_prefix text;
  v_table_name text;
  v_column_name text;
  v_formatted_number text;
begin
  v_actor_tenant_id := public.user_tenant_id();

  if auth.uid() is not null then
    if v_actor_tenant_id is null then
      raise exception 'Could not resolve tenant for authenticated user';
    end if;

    if p_tenant_id is null or p_tenant_id <> v_actor_tenant_id then
      raise exception 'Cross-tenant document sequence access is not allowed';
    end if;
  end if;

  v_prefix := coalesce(p_prefix, case p_document_type
    when 'sales_invoice' then 'FV'
    when 'purchase_invoice' then 'FC'
    when 'sales_payment' then 'PV'
    when 'purchase_payment' then 'PC'
    when 'journal_entry' then 'AC'
    when 'mechanic_job' then 'PG'
    when 'stock_adjustment' then 'AJ'
    when 'expense' then 'GTO'
    else 'DOC'
  end);

  case p_document_type
    when 'sales_invoice' then
      v_table_name := 'sales_invoices';
      v_column_name := 'invoice_number';
    when 'purchase_invoice' then
      v_table_name := 'purchase_invoices';
      v_column_name := 'invoice_number';
    when 'sales_payment' then
      v_table_name := 'sales_payments';
      v_column_name := 'payment_number';
    when 'purchase_payment' then
      v_table_name := 'purchase_payments';
      v_column_name := 'payment_number';
    when 'journal_entry' then
      v_table_name := 'journal_entries';
      v_column_name := 'entry_number';
    when 'mechanic_job' then
      v_table_name := 'mechanic_jobs';
      v_column_name := 'job_number';
    when 'stock_adjustment' then
      v_table_name := 'stock_adjustments';
      v_column_name := 'reference';
    when 'expense' then
      v_table_name := 'expenses';
      v_column_name := 'expense_number';
    else
      v_table_name := null;
      v_column_name := null;
  end case;

  if v_table_name is not null and v_column_name is not null then
    execute format(
      'select coalesce(max((substring(%1$I from ''([0-9]+)$''))::integer), 0)
         from public.%2$I
        where tenant_id = $1
          and %1$I ~ $2',
      v_column_name,
      v_table_name
    )
    into v_max_existing
    using p_tenant_id, '^' || v_prefix || '-[0-9]+$';
  end if;

  if p_document_type = 'expense' then
    select coalesce(
      max((substring(entry.source_reference from '([0-9]+)$'))::integer),
      0
    )
    into v_max_journal_reference
    from public.journal_entries entry
    where entry.tenant_id = p_tenant_id
      and entry.source_module = 'expenses'
      and entry.source_reference ~ ('^' || v_prefix || '-[0-9]+$');

    v_max_existing := greatest(v_max_existing, v_max_journal_reference);
  end if;

  select coalesce(last_number, 0)
  into v_current_number
  from public.document_sequences
  where tenant_id = p_tenant_id
    and document_type = p_document_type;

  v_next_number := greatest(
    coalesce(v_current_number, 0),
    coalesce(v_max_existing, 0)
  ) + 1;

  v_formatted_number := v_prefix || '-' || lpad(v_next_number::text, 5, '0');
  return v_formatted_number;
end;
$$;

-- Align existing counters immediately without deleting any preserved journal.
with journal_maximums as (
  select
    entry.tenant_id,
    max((substring(entry.source_reference from '([0-9]+)$'))::integer)
      as max_number
  from public.journal_entries entry
  where entry.source_module = 'expenses'
    and entry.source_reference ~ '^GTO-[0-9]+$'
  group by entry.tenant_id
)
update public.document_sequences sequence
set last_number = greatest(sequence.last_number, maximum.max_number),
    updated_at = now()
from journal_maximums maximum
where sequence.tenant_id = maximum.tenant_id
  and sequence.document_type = 'expense'
  and sequence.last_number < maximum.max_number;

-- Make the immutable document UUID authoritative for every legacy accrual
-- that still has an unambiguous live expense. True orphan evidence stays
-- unlinked and remains queryable by its historical text reference.
with unique_expense_matches as (
  select
    entry.id as entry_id,
    (array_agg(expense.id order by expense.id))[1] as expense_id
  from public.journal_entries entry
  join public.expenses expense
    on expense.tenant_id = entry.tenant_id
   and expense.expense_number = entry.source_reference
  where entry.source_module = 'expenses'
    and entry.source_document_id is null
  group by entry.id
  having count(*) = 1
)
update public.journal_entries entry
set source_document_type = 'expense',
    source_document_id = matches.expense_id,
    updated_at = now()
from unique_expense_matches matches
where entry.id = matches.entry_id;

-- The deployed trace originally treated expense_number as document identity.
-- Patch its three accrual predicates so an orphan GTO reference can never be
-- counted as the journal of a newly created expense.
do $$
declare
  v_definition text;
  v_old_pattern text := $pattern$entry[.]source_reference = p_expense_number[[:space:]]+or [(]p_expense_id is not null and entry[.]source_reference = p_expense_id::text[)][[:space:]]+or [(]p_expense_id is not null and entry[.]source_document_id = p_expense_id[)]$pattern$;
  v_new_predicate text := $predicate$-- Expense journal UUID identity is authoritative; text references may
      -- belong to preserved journals for deleted legacy expenses.
      (p_expense_id is not null and entry.source_document_id = p_expense_id)
      or (
        p_expense_id is null
        and entry.source_reference = p_expense_number
      )$predicate$;
  v_occurrences integer;
begin
  select pg_get_functiondef(
    'public.complete_expense_accounting_operation(uuid,uuid,uuid,uuid,integer,integer,boolean,boolean,boolean,text)'::regprocedure
  )
  into v_definition;

  if position(
    'Expense journal UUID identity is authoritative'
    in v_definition
  ) > 0 then
    return;
  end if;

  select count(*)::integer
  into v_occurrences
  from regexp_matches(v_definition, v_old_pattern, 'g');

  if v_occurrences <> 3 then
    raise exception
      'Expected three legacy expense journal predicates, found %',
      v_occurrences;
  end if;

  execute regexp_replace(v_definition, v_old_pattern, v_new_predicate, 'g');
end;
$$;

comment on function public.get_next_document_number(uuid, text, text) is
  'Issues tenant-scoped document numbers and prevents expense references from colliding with preserved expense journals.';
comment on function public.preview_next_document_number(uuid, text, text) is
  'Previews tenant-scoped document numbers, including preserved expense journal references in the high-water mark.';
