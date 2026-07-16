-- Deployment status: DEPLOYED to production project xzdvtzdqjeyqxnkqprtf
-- on 2026-07-15. Batch accounting-source-identity-20260715-v1 assigned 680
-- invoice journals and 728 payment journals to stable source UUIDs, created 2
-- missing journals split from duplicate visible numbers and left 9 orphan
-- journals legacy_unresolved. Stock, payment and invoice truth were unchanged.
-- Deployed SQL SHA-256 before annotation:
-- 76a53a7fa6acb7924362d779ea12f2baa07967252b6b5a6dae9440a3f26429ab
-- Makes UUID source_document_id the accounting identity for sales invoices and
-- payments. Visible invoice numbers remain labels and may be duplicated only
-- in preserved legacy rows; new duplicates are rejected.
begin;

create table if not exists public.accounting_source_identity_backfill_runs (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  batch_key text not null,
  status text not null default 'running'
    check (status in ('running', 'completed')),
  started_at timestamptz not null default clock_timestamp(),
  completed_at timestamptz,
  summary jsonb not null default '{}'::jsonb,
  unique (tenant_id, batch_key)
);

create table if not exists public.accounting_source_identity_backfill_rows (
  id uuid primary key default gen_random_uuid(),
  run_id uuid not null
    references public.accounting_source_identity_backfill_runs(id) on delete cascade,
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  journal_entry_id uuid,
  source_module text not null,
  source_document_id uuid,
  resolution text not null check (
    resolution in (
      'unique_reference',
      'duplicate_number_exact_amount',
      'payment_uuid',
      'duplicate_reference_normalized',
      'missing_duplicate_journal_created',
      'legacy_unresolved'
    )
  ),
  before_data jsonb not null,
  after_data jsonb not null,
  created_at timestamptz not null default clock_timestamp()
);

create index if not exists idx_accounting_source_identity_rows_run
  on public.accounting_source_identity_backfill_rows(run_id, created_at, id);

alter table public.accounting_source_identity_backfill_runs enable row level security;
alter table public.accounting_source_identity_backfill_rows enable row level security;

drop policy if exists accounting_source_identity_runs_select
  on public.accounting_source_identity_backfill_runs;
create policy accounting_source_identity_runs_select
  on public.accounting_source_identity_backfill_runs
  for select to authenticated
  using (tenant_id = public.user_tenant_id());

drop policy if exists accounting_source_identity_rows_select
  on public.accounting_source_identity_backfill_rows;
create policy accounting_source_identity_rows_select
  on public.accounting_source_identity_backfill_rows
  for select to authenticated
  using (tenant_id = public.user_tenant_id());

revoke all on public.accounting_source_identity_backfill_runs,
              public.accounting_source_identity_backfill_rows
  from public, anon, authenticated, service_role;
grant select on public.accounting_source_identity_backfill_runs,
                public.accounting_source_identity_backfill_rows
  to authenticated;

create or replace function public.assign_journal_source_identity()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_requested_id uuid;
  v_resolved_id uuid;
  v_candidate_count integer := 0;
  v_duplicate_number_count integer := 0;
  v_setting text;
begin
  if NEW.tenant_id is null then
    return NEW;
  end if;

  if NEW.source_module = 'sales_invoices' then
    if NEW.source_document_id is not null then
      select invoice.id, invoice.invoice_number
        into v_resolved_id, v_setting
      from public.sales_invoices invoice
      where invoice.id = NEW.source_document_id
        and invoice.tenant_id = NEW.tenant_id;
      if v_resolved_id is null then
        raise exception 'Sales invoice journal source_document_id does not belong to its tenant.';
      end if;
    else
      v_setting := nullif(
        current_setting('app.accounting_source_document_id', true),
        ''
      );
      if v_setting is not null and v_setting ~*
        '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' then
        v_requested_id := v_setting::uuid;
      end if;

      if v_requested_id is not null then
        select invoice.id
          into v_resolved_id
        from public.sales_invoices invoice
        where invoice.id = v_requested_id
          and invoice.tenant_id = NEW.tenant_id
          and NEW.source_reference in (
            invoice.id::text,
            invoice.invoice_number
          );
      end if;

      if v_resolved_id is null then
        select
          count(*)::integer,
          (array_agg(invoice.id order by invoice.id))[1]
          into v_candidate_count, v_resolved_id
        from public.sales_invoices invoice
        where invoice.tenant_id = NEW.tenant_id
          and NEW.source_reference in (
            invoice.id::text,
            invoice.invoice_number
          )
          and public.clp_round(invoice.total)
                = public.clp_round(NEW.total_debit);

        if v_candidate_count <> 1 then
          v_resolved_id := null;
        end if;
      end if;
    end if;

    if v_resolved_id is not null then
      NEW.source_document_type := 'sales_invoice';
      NEW.source_document_id := v_resolved_id;

      select count(*)::integer
        into v_duplicate_number_count
      from public.sales_invoices invoice
      join public.sales_invoices resolved
        on resolved.id = v_resolved_id
       and resolved.tenant_id = invoice.tenant_id
       and resolved.invoice_number = invoice.invoice_number
      where invoice.tenant_id = NEW.tenant_id;

      if v_duplicate_number_count > 1 then
        NEW.source_reference := v_resolved_id::text;
      end if;
    end if;
  elsif NEW.source_module = 'sales_payments' then
    if NEW.source_document_id is not null then
      select payment.id
        into v_resolved_id
      from public.sales_payments payment
      where payment.id = NEW.source_document_id
        and payment.tenant_id = NEW.tenant_id;
    elsif coalesce(NEW.source_reference, '') ~*
      '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' then
      select payment.id
        into v_resolved_id
      from public.sales_payments payment
      where payment.id = NEW.source_reference::uuid
        and payment.tenant_id = NEW.tenant_id;
    end if;

    if v_resolved_id is not null then
      NEW.source_document_type := 'sales_payment';
      NEW.source_document_id := v_resolved_id;
      NEW.source_reference := v_resolved_id::text;
    end if;
  end if;

  return NEW;
end;
$$;

revoke all on function public.assign_journal_source_identity()
  from public, anon, authenticated, service_role;

drop trigger if exists trg_journal_entries_source_identity
  on public.journal_entries;
create trigger trg_journal_entries_source_identity
  before insert or update of tenant_id, source_module, source_reference,
    source_document_type, source_document_id, total_debit
  on public.journal_entries
  for each row execute function public.assign_journal_source_identity();

create unique index if not exists idx_journal_entries_sales_source_document_unique
  on public.journal_entries(tenant_id, source_module, source_document_id)
  where source_document_id is not null
    and source_module in ('sales_invoices', 'sales_payments');

create or replace function public.guard_sales_invoice_number_uniqueness()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if current_setting('app.allow_legacy_duplicate_invoice_number', true) = 'true' then
    return NEW;
  end if;

  if nullif(btrim(coalesce(NEW.invoice_number, '')), '') is not null
     and exists (
       select 1
       from public.sales_invoices invoice
       where invoice.tenant_id = NEW.tenant_id
         and invoice.invoice_number = NEW.invoice_number
         and invoice.id is distinct from NEW.id
     ) then
    raise exception 'El número de factura de venta ya existe para este tenant.'
      using errcode = '23505';
  end if;
  return NEW;
end;
$$;

revoke all on function public.guard_sales_invoice_number_uniqueness()
  from public, anon, authenticated, service_role;

drop trigger if exists trg_sales_invoice_number_uniqueness
  on public.sales_invoices;
create trigger trg_sales_invoice_number_uniqueness
  before insert or update of tenant_id, invoice_number
  on public.sales_invoices
  for each row execute function public.guard_sales_invoice_number_uniqueness();

create or replace function public.prepare_duplicate_invoice_journal_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if pg_trigger_depth() > 1 then
    return case when TG_OP = 'DELETE' then OLD else NEW end;
  end if;

  if exists (
    select 1
    from public.sales_invoices sibling
    where sibling.tenant_id = OLD.tenant_id
      and sibling.invoice_number = OLD.invoice_number
      and sibling.id <> OLD.id
  ) then
    delete from public.journal_entries entry
    where entry.tenant_id = OLD.tenant_id
      and entry.source_module = 'sales_invoices'
      and (
        entry.source_document_id = OLD.id
        or entry.source_reference = OLD.id::text
      );

    if TG_OP = 'UPDATE' then
      perform set_config(
        'app.accounting_source_document_id',
        NEW.id::text,
        true
      );
    end if;
  end if;
  return case when TG_OP = 'DELETE' then OLD else NEW end;
end;
$$;

revoke all on function public.prepare_duplicate_invoice_journal_change()
  from public, anon, authenticated, service_role;

drop trigger if exists trg_sales_invoice_duplicate_journal_prepare
  on public.sales_invoices;
create trigger trg_sales_invoice_duplicate_journal_prepare
  before update or delete on public.sales_invoices
  for each row execute function public.prepare_duplicate_invoice_journal_change();

create or replace view public.workshop_financial_backfill_preview
with (security_invoker = true)
as
select
  job.tenant_id,
  job.id as job_id,
  job.job_number,
  invoice.id as invoice_id,
  invoice.invoice_number,
  invoice.status as invoice_status,
  invoice.total as invoice_total,
  invoice.tax_treatment as invoice_tax_treatment,
  invoice.net_amount as invoice_net_amount,
  invoice.iva_amount as invoice_iva_amount,
  payment_stats.active_payment_count,
  payment_stats.active_payment_sum,
  payment_stats.tax_mismatch_count as payment_tax_mismatch_count,
  invoice_journal.journal_count as invoice_journal_count,
  invoice_journal.ar_debit,
  invoice_journal.sales_credit,
  invoice_journal.total_debit,
  invoice_journal.total_credit,
  job_journal.journal_count as job_journal_count,
  job.tax_treatment is distinct from invoice.tax_treatment
    or public.clp_round(job.tax_amount)
         is distinct from public.clp_round(invoice.iva_amount)
    or public.clp_round(job.total_cost)
         is distinct from public.clp_round(invoice.total)
    or job.is_paid is distinct from (
      lower(invoice.status) in ('paid', 'pagado', 'pagada')
    ) as job_financial_mirror_mismatch,
  lower(invoice.status) in ('paid', 'pagado', 'pagada')
    and public.clp_round(invoice.total) > 0
    and payment_stats.active_payment_sum = public.clp_round(invoice.total)
    and job_journal.journal_count = 0
    and invoice_journal.journal_count <= 1
    and (
      invoice_journal.journal_count = 0
      or invoice_journal.ar_debit <> public.clp_round(invoice.total)
      or invoice_journal.sales_credit <> public.clp_round(invoice.total)
      or invoice_journal.total_debit <> invoice_journal.total_credit
    ) as journal_repair_eligible,
  lower(invoice.status) in ('paid', 'pagado', 'pagada')
    and (
      invoice_journal.journal_count = 0
      or invoice_journal.ar_debit <> public.clp_round(invoice.total)
      or invoice_journal.sales_credit <> public.clp_round(invoice.total)
      or invoice_journal.total_debit <> invoice_journal.total_credit
    )
    and not (
      public.clp_round(invoice.total) > 0
      and payment_stats.active_payment_sum = public.clp_round(invoice.total)
      and job_journal.journal_count = 0
      and invoice_journal.journal_count <= 1
    ) as journal_requires_manual_review
from public.mechanic_jobs job
join public.sales_invoices invoice
  on invoice.id = job.invoice_id
 and invoice.tenant_id = job.tenant_id
left join lateral (
  select
    count(*)::integer as active_payment_count,
    public.clp_round(coalesce(sum(payment.amount), 0)) as active_payment_sum,
    count(*) filter (
      where payment.tax_treatment is distinct from invoice.tax_treatment
         or public.clp_round(payment.net_amount) is distinct from case
           when invoice.tax_treatment = 'tax_included'
             then public.clp_round(payment.amount / 1.19)
           else public.clp_round(payment.amount)
         end
         or public.clp_round(payment.iva_amount) is distinct from case
           when invoice.tax_treatment = 'tax_included'
             then public.clp_round(payment.amount)
                    - public.clp_round(payment.amount / 1.19)
           else 0
         end
    )::integer as tax_mismatch_count
  from public.sales_payments payment
  where payment.invoice_id = invoice.id
    and payment.tenant_id = invoice.tenant_id
    and payment.deleted_at is null
) payment_stats on true
left join lateral (
  select
    count(distinct entry.id)::integer as journal_count,
    public.clp_round(coalesce(sum(line.debit_amount)
      filter (where line.account_code = '1130'), 0)) as ar_debit,
    public.clp_round(coalesce(sum(line.credit_amount)
      filter (where line.account_code in ('4100', '4101', '2150', '2110')), 0))
      as sales_credit,
    public.clp_round(coalesce(sum(line.debit_amount), 0)) as total_debit,
    public.clp_round(coalesce(sum(line.credit_amount), 0)) as total_credit
  from public.journal_entries entry
  left join public.journal_lines line
    on line.entry_id = entry.id
   and line.tenant_id = entry.tenant_id
  where entry.tenant_id = invoice.tenant_id
    and entry.source_module = 'sales_invoices'
    and (
      entry.source_document_id = invoice.id
      or (
        entry.source_document_id is null
        and entry.source_reference in (
          invoice.id::text,
          invoice.invoice_number
        )
        and not exists (
          select 1
          from public.sales_invoices sibling
          where sibling.tenant_id = invoice.tenant_id
            and sibling.invoice_number = invoice.invoice_number
            and sibling.id <> invoice.id
        )
      )
    )
) invoice_journal on true
left join lateral (
  select count(*)::integer as journal_count
  from public.journal_entries entry
  where entry.tenant_id = job.tenant_id
    and entry.source_module = 'mechanic_jobs'
    and entry.source_reference in (job.id::text, job.job_number)
) job_journal on true;

grant select on public.workshop_financial_backfill_preview to authenticated;

create or replace function public.apply_accounting_source_identity_backfill(
  p_tenant_id uuid,
  p_batch_key text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_run public.accounting_source_identity_backfill_runs%rowtype;
  v_key text := btrim(coalesce(p_batch_key, ''));
  v_entry record;
  v_invoice public.sales_invoices%rowtype;
  v_before jsonb;
  v_after jsonb;
  v_summary jsonb;
  v_invoice_assigned integer := 0;
  v_payment_assigned integer := 0;
  v_duplicate_normalized integer := 0;
  v_missing_created integer := 0;
  v_unresolved integer := 0;
  v_stock_fingerprint_before text;
  v_stock_fingerprint_after text;
  v_payment_fingerprint_before text;
  v_payment_fingerprint_after text;
  v_invoice_fingerprint_before text;
  v_invoice_fingerprint_after text;
begin
  if p_tenant_id is null or not exists (
    select 1 from public.tenants where id = p_tenant_id
  ) then
    raise exception 'A valid tenant is required for accounting source identity backfill.';
  end if;
  if v_key = '' or length(v_key) > 128 then
    raise exception 'Backfill batch key is required and must be at most 128 characters.';
  end if;
  if auth.uid() is not null then
    raise exception 'Accounting source identity repair is database-admin only'
      using errcode = '42501';
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended(p_tenant_id::text || ':accounting-source:' || v_key, 0)
  );

  select * into v_run
  from public.accounting_source_identity_backfill_runs
  where tenant_id = p_tenant_id and batch_key = v_key;
  if found and v_run.status = 'completed' then
    return v_run.summary || jsonb_build_object('replayed', true);
  elsif found then
    raise exception 'Backfill batch is already running.';
  end if;

  insert into public.accounting_source_identity_backfill_runs(
    tenant_id, batch_key
  ) values (
    p_tenant_id, v_key
  ) returning * into v_run;

  select md5(coalesce(string_agg(to_jsonb(movement)::text, '|' order by movement.id), ''))
    into v_stock_fingerprint_before
  from public.stock_movements movement
  where movement.tenant_id = p_tenant_id;

  select md5(coalesce(string_agg(jsonb_build_object(
    'id', payment.id, 'invoice_id', payment.invoice_id,
    'amount', payment.amount, 'method', payment.payment_method_id,
    'date', payment.date, 'deleted_at', payment.deleted_at
  )::text, '|' order by payment.id), ''))
    into v_payment_fingerprint_before
  from public.sales_payments payment
  where payment.tenant_id = p_tenant_id;

  select md5(coalesce(string_agg(jsonb_build_object(
    'id', invoice.id, 'number', invoice.invoice_number,
    'status', invoice.status, 'tax', invoice.tax_treatment,
    'net', invoice.net_amount, 'iva', invoice.iva_amount,
    'total', invoice.total, 'paid', invoice.paid_amount,
    'balance', invoice.balance, 'items', invoice.items
  )::text, '|' order by invoice.id), ''))
    into v_invoice_fingerprint_before
  from public.sales_invoices invoice
  where invoice.tenant_id = p_tenant_id;

  for v_entry in
    with legacy as (
      select entry.*
      from public.journal_entries entry
      where entry.tenant_id = p_tenant_id
        and entry.source_module = 'sales_invoices'
        and entry.source_document_id is null
    )
    select
      legacy.*,
      candidate.invoice_count,
      case
        when candidate.invoice_count = 1 then candidate.only_invoice_id
        when candidate.amount_match_count = 1 then candidate.amount_match_id
      end as resolved_id,
      case
        when candidate.invoice_count = 1 then 'unique_reference'
        else 'duplicate_number_exact_amount'
      end as resolution
    from legacy
    join lateral (
      select
        count(invoice.id)::integer as invoice_count,
        (array_agg(invoice.id order by invoice.id))[1] as only_invoice_id,
        count(invoice.id) filter (
          where public.clp_round(invoice.total)
                  = public.clp_round(legacy.total_debit)
        )::integer as amount_match_count,
        (array_agg(invoice.id order by invoice.id) filter (
          where public.clp_round(invoice.total)
                  = public.clp_round(legacy.total_debit)
        ))[1] as amount_match_id
      from public.sales_invoices invoice
      where invoice.tenant_id = legacy.tenant_id
        and legacy.source_reference in (
          invoice.id::text,
          invoice.invoice_number
        )
    ) candidate on true
    where candidate.invoice_count = 1
       or (candidate.invoice_count > 1 and candidate.amount_match_count = 1)
    order by legacy.id
  loop
    v_before := to_jsonb(v_entry) - 'invoice_count' - 'resolved_id' - 'resolution';
    update public.journal_entries entry
    set source_document_type = 'sales_invoice',
        source_document_id = v_entry.resolved_id
    where entry.id = v_entry.id and entry.tenant_id = p_tenant_id;
    select to_jsonb(entry) into v_after
    from public.journal_entries entry where entry.id = v_entry.id;

    insert into public.accounting_source_identity_backfill_rows(
      run_id, tenant_id, journal_entry_id, source_module,
      source_document_id, resolution, before_data, after_data
    ) values (
      v_run.id, p_tenant_id, v_entry.id, 'sales_invoices',
      v_entry.resolved_id, v_entry.resolution, v_before, v_after
    );
    v_invoice_assigned := v_invoice_assigned + 1;
  end loop;

  for v_entry in
    select entry.*, payment.id as resolved_id
    from public.journal_entries entry
    join public.sales_payments payment
      on payment.tenant_id = entry.tenant_id
     and payment.id::text = entry.source_reference
    where entry.tenant_id = p_tenant_id
      and entry.source_module = 'sales_payments'
      and entry.source_document_id is null
    order by entry.id
  loop
    v_before := to_jsonb(v_entry) - 'resolved_id';
    update public.journal_entries entry
    set source_document_type = 'sales_payment',
        source_document_id = v_entry.resolved_id
    where entry.id = v_entry.id and entry.tenant_id = p_tenant_id;
    select to_jsonb(entry) into v_after
    from public.journal_entries entry where entry.id = v_entry.id;

    insert into public.accounting_source_identity_backfill_rows(
      run_id, tenant_id, journal_entry_id, source_module,
      source_document_id, resolution, before_data, after_data
    ) values (
      v_run.id, p_tenant_id, v_entry.id, 'sales_payments',
      v_entry.resolved_id, 'payment_uuid', v_before, v_after
    );
    v_payment_assigned := v_payment_assigned + 1;
  end loop;

  for v_entry in
    select entry.*, invoice.invoice_number
    from public.journal_entries entry
    join public.sales_invoices invoice
      on invoice.id = entry.source_document_id
     and invoice.tenant_id = entry.tenant_id
    where entry.tenant_id = p_tenant_id
      and entry.source_module = 'sales_invoices'
      and entry.source_reference <> entry.source_document_id::text
      and exists (
        select 1 from public.sales_invoices sibling
        where sibling.tenant_id = invoice.tenant_id
          and sibling.invoice_number = invoice.invoice_number
          and sibling.id <> invoice.id
      )
    order by entry.id
  loop
    v_before := to_jsonb(v_entry) - 'invoice_number';
    update public.journal_entries entry
    set source_reference = v_entry.source_document_id::text
    where entry.id = v_entry.id and entry.tenant_id = p_tenant_id;
    select to_jsonb(entry) into v_after
    from public.journal_entries entry where entry.id = v_entry.id;

    insert into public.accounting_source_identity_backfill_rows(
      run_id, tenant_id, journal_entry_id, source_module,
      source_document_id, resolution, before_data, after_data
    ) values (
      v_run.id, p_tenant_id, v_entry.id, 'sales_invoices',
      v_entry.source_document_id, 'duplicate_reference_normalized',
      v_before, v_after
    );
    v_duplicate_normalized := v_duplicate_normalized + 1;
  end loop;

  for v_invoice in
    select invoice.*
    from public.sales_invoices invoice
    where invoice.tenant_id = p_tenant_id
      and lower(invoice.status) in ('confirmed', 'paid')
      and public.clp_round(invoice.total) > 0
      and exists (
        select 1 from public.sales_invoices sibling
        where sibling.tenant_id = invoice.tenant_id
          and sibling.invoice_number = invoice.invoice_number
          and sibling.id <> invoice.id
      )
      and not exists (
        select 1 from public.journal_entries entry
        where entry.tenant_id = invoice.tenant_id
          and entry.source_module = 'sales_invoices'
          and entry.source_document_id = invoice.id
      )
      and not exists (
        select 1
        from public.mechanic_jobs job
        join public.journal_entries entry
          on entry.tenant_id = job.tenant_id
         and entry.source_module = 'mechanic_jobs'
         and entry.source_reference in (job.id::text, job.job_number)
        where job.invoice_id = invoice.id
          and job.tenant_id = invoice.tenant_id
      )
      and (
        (
          lower(invoice.status) = 'paid'
          and public.clp_round(coalesce((
            select sum(payment.amount)
            from public.sales_payments payment
            where payment.invoice_id = invoice.id
              and payment.tenant_id = invoice.tenant_id
              and payment.deleted_at is null
          ), 0)) = public.clp_round(invoice.total)
        )
        or (
          lower(invoice.status) = 'confirmed'
          and coalesce((
            select sum(payment.amount)
            from public.sales_payments payment
            where payment.invoice_id = invoice.id
              and payment.tenant_id = invoice.tenant_id
              and payment.deleted_at is null
          ), 0) = 0
        )
      )
    order by invoice.invoice_number, invoice.created_at
  loop
    v_before := to_jsonb(v_invoice);
    perform set_config(
      'app.accounting_source_document_id',
      v_invoice.id::text,
      true
    );
    perform public.create_sales_invoice_journal_entry(v_invoice);
    perform set_config('app.accounting_source_document_id', '', true);

    select to_jsonb(entry) into v_after
    from public.journal_entries entry
    where entry.tenant_id = p_tenant_id
      and entry.source_module = 'sales_invoices'
      and entry.source_document_id = v_invoice.id;
    if v_after is null then
      raise exception 'Missing duplicate invoice journal was not created for %.',
        v_invoice.id;
    end if;

    insert into public.accounting_source_identity_backfill_rows(
      run_id, tenant_id, journal_entry_id, source_module,
      source_document_id, resolution, before_data, after_data
    ) values (
      v_run.id, p_tenant_id, (v_after->>'id')::uuid, 'sales_invoices',
      v_invoice.id, 'missing_duplicate_journal_created', v_before, v_after
    );
    v_missing_created := v_missing_created + 1;
  end loop;

  for v_entry in
    select entry.*
    from public.journal_entries entry
    where entry.tenant_id = p_tenant_id
      and entry.source_module in ('sales_invoices', 'sales_payments')
      and entry.source_document_id is null
    order by entry.source_module, entry.id
  loop
    v_before := to_jsonb(v_entry) || jsonb_build_object(
      'reason', 'legacy_unresolved'
    );
    insert into public.accounting_source_identity_backfill_rows(
      run_id, tenant_id, journal_entry_id, source_module,
      source_document_id, resolution, before_data, after_data
    ) values (
      v_run.id, p_tenant_id, v_entry.id, v_entry.source_module,
      null, 'legacy_unresolved', v_before, v_before
    );
    v_unresolved := v_unresolved + 1;
  end loop;

  if exists (
    select 1
    from public.journal_entries entry
    where entry.tenant_id = p_tenant_id
      and entry.source_module in ('sales_invoices', 'sales_payments')
      and entry.source_document_id is not null
    group by entry.source_module, entry.source_document_id
    having count(*) > 1
  ) then
    raise exception 'Accounting source identity backfill created duplicate document ownership.';
  end if;

  if exists (
    select 1
    from public.journal_entries entry
    left join public.journal_lines line
      on line.entry_id = entry.id and line.tenant_id = entry.tenant_id
    where entry.tenant_id = p_tenant_id
      and entry.source_module in ('sales_invoices', 'sales_payments')
    group by entry.id
    having coalesce(sum(line.debit_amount), 0)
             <> coalesce(sum(line.credit_amount), 0)
  ) then
    raise exception 'Accounting source identity backfill found an unbalanced sales journal.';
  end if;

  select md5(coalesce(string_agg(to_jsonb(movement)::text, '|' order by movement.id), ''))
    into v_stock_fingerprint_after
  from public.stock_movements movement
  where movement.tenant_id = p_tenant_id;

  select md5(coalesce(string_agg(jsonb_build_object(
    'id', payment.id, 'invoice_id', payment.invoice_id,
    'amount', payment.amount, 'method', payment.payment_method_id,
    'date', payment.date, 'deleted_at', payment.deleted_at
  )::text, '|' order by payment.id), ''))
    into v_payment_fingerprint_after
  from public.sales_payments payment
  where payment.tenant_id = p_tenant_id;

  select md5(coalesce(string_agg(jsonb_build_object(
    'id', invoice.id, 'number', invoice.invoice_number,
    'status', invoice.status, 'tax', invoice.tax_treatment,
    'net', invoice.net_amount, 'iva', invoice.iva_amount,
    'total', invoice.total, 'paid', invoice.paid_amount,
    'balance', invoice.balance, 'items', invoice.items
  )::text, '|' order by invoice.id), ''))
    into v_invoice_fingerprint_after
  from public.sales_invoices invoice
  where invoice.tenant_id = p_tenant_id;

  if v_stock_fingerprint_after is distinct from v_stock_fingerprint_before then
    raise exception 'Accounting source identity backfill changed stock evidence.';
  end if;
  if v_payment_fingerprint_after is distinct from v_payment_fingerprint_before then
    raise exception 'Accounting source identity backfill changed payment truth.';
  end if;
  if v_invoice_fingerprint_after is distinct from v_invoice_fingerprint_before then
    raise exception 'Accounting source identity backfill changed invoice truth.';
  end if;

  v_summary := jsonb_build_object(
    'run_id', v_run.id,
    'tenant_id', p_tenant_id,
    'batch_key', v_key,
    'invoice_journals_assigned', v_invoice_assigned,
    'payment_journals_assigned', v_payment_assigned,
    'duplicate_references_normalized', v_duplicate_normalized,
    'missing_duplicate_journals_created', v_missing_created,
    'legacy_unresolved', v_unresolved,
    'stock_unchanged', true,
    'payment_truth_unchanged', true,
    'invoice_truth_unchanged', true,
    'replayed', false
  );

  update public.accounting_source_identity_backfill_runs
  set status = 'completed', completed_at = clock_timestamp(), summary = v_summary
  where id = v_run.id;
  return v_summary;
exception
  when others then
    perform set_config('app.accounting_source_document_id', '', true);
    raise;
end;
$$;

revoke all on function public.apply_accounting_source_identity_backfill(uuid, text)
  from public, anon, authenticated, service_role;

comment on function public.apply_accounting_source_identity_backfill(uuid, text) is
  'Database-admin-only identity repair. Assigns deterministic UUID ownership, splits exact duplicate invoice-number collisions, records unresolved orphan journals, and preserves stock/payment/invoice fingerprints.';

commit;
