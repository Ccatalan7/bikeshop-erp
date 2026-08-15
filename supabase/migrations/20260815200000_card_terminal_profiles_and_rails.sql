-- Provider-neutral card terminal profiles and separated card rails.
--
-- A payment method is the operator-facing tender selected by POS, quick sale,
-- invoice payment, workshop invoices and every other sales surface.  A
-- terminal profile owns the acquiring provider and the versioned commercial
-- terms used later by bank reconciliation.  Keeping those concerns separate
-- lets another terminal (for example Mercado Pago Point) coexist without
-- rewriting historical payments or pretending that one provider's contract
-- applies to another.

create extension if not exists pgcrypto;

alter table public.payment_methods
  add column if not exists usage_scope text not null default 'both'
    check (usage_scope in ('inbound', 'outbound', 'both'));

do $$
begin
  if exists (
    select 1
      from public.payment_methods
     group by tenant_id, code
    having count(*) > 1
  ) then
    raise exception using
      errcode = '23505',
      message = 'payment_method_codes_are_not_tenant_unique';
  end if;
end;
$$;

create unique index if not exists uq_payment_methods_tenant_code
  on public.payment_methods(tenant_id, code);

comment on column public.payment_methods.usage_scope is
  'Where the method may be selected: inbound customer collections, outbound disbursements, or both. Processor terminal rails are inbound-only.';

create table if not exists public.payment_terminal_profiles (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  provider_code text not null
    check (provider_code ~ '^[a-z][a-z0-9_]{1,39}$'),
  provider_name text not null
    check (length(btrim(provider_name)) between 2 and 80),
  terminal_name text not null
    check (length(btrim(terminal_name)) between 2 and 100),
  merchant_reference text
    check (merchant_reference is null or length(btrim(merchant_reference)) <= 120),
  clearing_account_id uuid not null,
  commission_expense_account_id uuid not null,
  settlement_account_id uuid not null,
  descriptor_patterns text[] not null default '{}'
    check (cardinality(descriptor_patterns) between 1 and 20),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (tenant_id, id),
  unique (tenant_id, provider_code, terminal_name),
  constraint payment_terminal_profiles_clearing_account_fk
    foreign key (tenant_id, clearing_account_id)
    references public.accounts(tenant_id, id) on delete restrict,
  constraint payment_terminal_profiles_commission_expense_account_fk
    foreign key (tenant_id, commission_expense_account_id)
    references public.accounts(tenant_id, id) on delete restrict,
  constraint payment_terminal_profiles_account_fk
    foreign key (tenant_id, settlement_account_id)
    references public.accounts(tenant_id, id) on delete restrict
);

alter table public.payment_methods
  add column if not exists terminal_profile_id uuid;

do $$
begin
  alter table public.payment_methods
    drop constraint if exists payment_methods_terminal_profile_fk;
  alter table public.payment_methods
    add constraint payment_methods_terminal_profile_fk
      foreign key (tenant_id, terminal_profile_id)
      references public.payment_terminal_profiles(tenant_id, id)
      on delete restrict;
end;
$$;

comment on column public.payment_methods.terminal_profile_id is
  'Optional acquiring terminal that owns settlement terms for inbound card payments.';

create table if not exists public.payment_terminal_terms (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  terminal_profile_id uuid not null,
  payment_method_id uuid not null,
  instrument text not null check (instrument in ('debit', 'credit', 'prepaid')),
  commission_rate_bps integer not null
    check (commission_rate_bps between 0 and 10000),
  commission_vat_bps integer not null default 1900
    check (commission_vat_bps between 0 and 10000),
  minimum_commission_uf numeric(12,6) not null default 0
    check (minimum_commission_uf >= 0),
  settlement_business_days smallint not null
    check (settlement_business_days between 0 and 30),
  booking_grace_business_days smallint not null default 2
    check (booking_grace_business_days between 0 and 30),
  amount_tolerance_clp integer not null default 1000
    check (amount_tolerance_clp between 0 and 1000000),
  effective_from date not null,
  effective_to date,
  source_note text check (source_note is null or length(source_note) <= 500),
  source_url text check (source_url is null or length(source_url) <= 500),
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (tenant_id, id),
  unique (terminal_profile_id, instrument, effective_from),
  constraint payment_terminal_terms_dates_check
    check (effective_to is null or effective_to >= effective_from),
  constraint payment_terminal_terms_profile_fk
    foreign key (tenant_id, terminal_profile_id)
    references public.payment_terminal_profiles(tenant_id, id)
    on delete restrict,
  constraint payment_terminal_terms_method_fk
    foreign key (tenant_id, payment_method_id)
    references public.payment_methods(tenant_id, id)
    on delete restrict
);

create table if not exists public.payment_terminal_profile_operations (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  operation_key text not null
    check (length(btrim(operation_key)) between 1 and 180),
  payload_hash text not null check (payload_hash ~ '^[0-9a-f]{64}$'),
  receipt jsonb not null check (jsonb_typeof(receipt) = 'object'),
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  unique (tenant_id, operation_key)
);

create index if not exists idx_payment_terminal_profiles_tenant_active
  on public.payment_terminal_profiles(tenant_id, is_active, provider_code);
create index if not exists idx_payment_terminal_terms_profile_effective
  on public.payment_terminal_terms(
    terminal_profile_id, instrument, effective_from desc
  );
create index if not exists idx_payment_terminal_terms_method_effective
  on public.payment_terminal_terms(payment_method_id, effective_from desc);
create index if not exists idx_payment_methods_terminal_profile
  on public.payment_methods(tenant_id, terminal_profile_id)
  where terminal_profile_id is not null;
create index if not exists idx_payment_methods_usage_scope
  on public.payment_methods(tenant_id, usage_scope, is_active, sort_order);

drop trigger if exists trg_payment_terminal_profiles_updated_at
  on public.payment_terminal_profiles;
create trigger trg_payment_terminal_profiles_updated_at
  before update on public.payment_terminal_profiles
  for each row execute function public.set_updated_at();

drop trigger if exists trg_payment_terminal_terms_updated_at
  on public.payment_terminal_terms;
create trigger trg_payment_terminal_terms_updated_at
  before update on public.payment_terminal_terms
  for each row execute function public.set_updated_at();

alter table public.payment_terminal_profiles enable row level security;
alter table public.payment_terminal_terms enable row level security;
alter table public.payment_terminal_profile_operations enable row level security;

drop policy if exists payment_terminal_profiles_accounting_read
  on public.payment_terminal_profiles;
create policy payment_terminal_profiles_accounting_read
  on public.payment_terminal_profiles for select to authenticated
  using (public.can_manage_tenant_accounting(tenant_id));

drop policy if exists payment_terminal_terms_accounting_read
  on public.payment_terminal_terms;
create policy payment_terminal_terms_accounting_read
  on public.payment_terminal_terms for select to authenticated
  using (public.can_manage_tenant_accounting(tenant_id));

drop policy if exists payment_terminal_operations_accounting_read
  on public.payment_terminal_profile_operations;
create policy payment_terminal_operations_accounting_read
  on public.payment_terminal_profile_operations for select to authenticated
  using (public.can_manage_tenant_accounting(tenant_id));

revoke all on public.payment_terminal_profiles,
  public.payment_terminal_terms,
  public.payment_terminal_profile_operations
  from public, anon, authenticated, service_role;
grant select on public.payment_terminal_profiles,
  public.payment_terminal_terms,
  public.payment_terminal_profile_operations
  to authenticated, service_role;

create or replace function public.payment_terminal_profile_snapshot(
  p_tenant_id uuid,
  p_profile_id uuid
)
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog, public, pg_temp
as $$
  select jsonb_build_object(
    'id', profile.id,
    'tenant_id', profile.tenant_id,
    'provider_code', profile.provider_code,
    'provider_name', profile.provider_name,
    'terminal_name', profile.terminal_name,
    'merchant_reference', profile.merchant_reference,
    'clearing_account_id', profile.clearing_account_id,
    'commission_expense_account_id', profile.commission_expense_account_id,
    'settlement_account_id', profile.settlement_account_id,
    'descriptor_patterns', to_jsonb(profile.descriptor_patterns),
    'is_active', profile.is_active,
    'created_at', profile.created_at,
    'updated_at', profile.updated_at,
    'terms', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', terms.id,
        'instrument', terms.instrument,
        'payment_method_id', terms.payment_method_id,
        'payment_method_code', method.code,
        'payment_method_name', method.name,
        'commission_rate_bps', terms.commission_rate_bps,
        'commission_vat_bps', terms.commission_vat_bps,
        'minimum_commission_uf', terms.minimum_commission_uf,
        'settlement_business_days', terms.settlement_business_days,
        'booking_grace_business_days', terms.booking_grace_business_days,
        'amount_tolerance_clp', terms.amount_tolerance_clp,
        'effective_from', terms.effective_from,
        'effective_to', terms.effective_to,
        'source_note', terms.source_note,
        'source_url', terms.source_url
      ) order by terms.instrument, terms.effective_from desc)
      from public.payment_terminal_terms terms
      join public.payment_methods method
        on method.tenant_id = terms.tenant_id
       and method.id = terms.payment_method_id
      where terms.tenant_id = profile.tenant_id
        and terms.terminal_profile_id = profile.id
    ), '[]'::jsonb)
  )
  from public.payment_terminal_profiles profile
  where profile.tenant_id = p_tenant_id
    and profile.id = p_profile_id
$$;

revoke all on function public.payment_terminal_profile_snapshot(uuid, uuid)
  from public, anon, authenticated, service_role;

create or replace function public.payment_terminal_is_bank_account(
  p_tenant_id uuid,
  p_account_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public, pg_temp
as $$
  with recursive lineage as (
    select account.id, account.parent_id, account.code,
           account.type, account.is_active
      from public.accounts account
     where account.tenant_id = p_tenant_id
       and account.id = p_account_id
    union all
    select parent.id, parent.parent_id, parent.code,
           parent.type, parent.is_active
      from public.accounts parent
      join lineage child on child.parent_id = parent.id
     where parent.tenant_id = p_tenant_id
  )
  select exists (
    select 1 from lineage selected
     where selected.id = p_account_id
       and selected.type = 'asset'
       and selected.is_active
  ) and exists (
    select 1 from lineage candidate
     where candidate.code in ('1110', '1115')
        or candidate.code like '1110-%'
        or candidate.code like '1115-%'
  )
$$;

revoke all on function public.payment_terminal_is_bank_account(uuid, uuid)
  from public, anon, authenticated, service_role;

create or replace function public.save_payment_terminal_profile_v1(
  p_operation_key text,
  p_profile jsonb,
  p_terms jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_tenant_id uuid := public.user_tenant_id();
  v_user_id uuid := auth.uid();
  v_payload_hash text;
  v_existing record;
  v_profile public.payment_terminal_profiles%rowtype;
  v_profile_id uuid;
  v_is_new boolean;
  v_expected_updated_at timestamptz;
  v_provider_code text;
  v_provider_name text;
  v_terminal_name text;
  v_merchant_reference text;
  v_clearing_account_id uuid;
  v_commission_expense_account_id uuid;
  v_settlement_account_id uuid;
  v_descriptor_patterns text[];
  v_is_active boolean;
  v_term jsonb;
  v_instrument text;
  v_payment_method_id uuid;
  v_method public.payment_methods%rowtype;
  v_method_code text;
  v_method_name text;
  v_provider_projection text;
  v_effective_from date;
  v_receipt jsonb;
  v_account_suffix text;
begin
  if v_user_id is null or v_tenant_id is null
     or not public.can_manage_tenant_accounting(v_tenant_id) then
    raise exception using errcode = '42501', message = 'accounting_access_required';
  end if;
  if p_operation_key is null
     or length(btrim(p_operation_key)) not between 1 and 180
     or coalesce(jsonb_typeof(p_profile), 'null') <> 'object'
     or coalesce(jsonb_typeof(p_terms), 'null') <> 'array'
     or jsonb_array_length(p_terms) not between 1 and 3 then
    raise exception using errcode = '22023', message = 'payment_terminal_payload_invalid';
  end if;

  v_payload_hash := encode(extensions.digest(convert_to(jsonb_build_object(
    'profile', p_profile,
    'terms', p_terms
  )::text, 'utf8'), 'sha256'), 'hex');

  perform pg_advisory_xact_lock(hashtextextended(
    v_tenant_id::text || ':payment-terminal-profile', 0
  ));
  select operation.payload_hash, operation.receipt
    into v_existing
    from public.payment_terminal_profile_operations operation
   where operation.tenant_id = v_tenant_id
     and operation.operation_key = btrim(p_operation_key);
  if found then
    if v_existing.payload_hash <> v_payload_hash then
      raise exception using errcode = 'P0001', message = 'payment_terminal_idempotency_conflict';
    end if;
    return v_existing.receipt || jsonb_build_object('replayed', true);
  end if;

  v_profile_id := nullif(p_profile->>'id', '')::uuid;
  v_expected_updated_at := nullif(p_profile->>'expected_updated_at', '')::timestamptz;
  v_provider_code := lower(btrim(coalesce(p_profile->>'provider_code', '')));
  v_provider_name := btrim(coalesce(p_profile->>'provider_name', ''));
  v_terminal_name := btrim(coalesce(p_profile->>'terminal_name', ''));
  v_merchant_reference := nullif(btrim(coalesce(p_profile->>'merchant_reference', '')), '');
  v_clearing_account_id := nullif(p_profile->>'clearing_account_id', '')::uuid;
  v_commission_expense_account_id :=
    nullif(p_profile->>'commission_expense_account_id', '')::uuid;
  v_settlement_account_id := nullif(p_profile->>'settlement_account_id', '')::uuid;
  v_is_active := coalesce((p_profile->>'is_active')::boolean, true);
  select coalesce(array_agg(btrim(value)), '{}'::text[])
    into v_descriptor_patterns
    from jsonb_array_elements_text(
      coalesce(p_profile->'descriptor_patterns', '[]'::jsonb)
    ) descriptor(value)
   where length(btrim(value)) between 2 and 120;

  if v_provider_code !~ '^[a-z][a-z0-9_]{1,39}$'
     or length(v_provider_name) not between 2 and 80
     or length(v_terminal_name) not between 2 and 100
     or v_settlement_account_id is null
     or cardinality(v_descriptor_patterns) not between 1 and 20
     or exists (
       select 1 from unnest(v_descriptor_patterns) pattern
       group by lower(pattern) having count(*) > 1
     ) then
    raise exception using errcode = '22023', message = 'payment_terminal_profile_invalid';
  end if;

  v_is_new := v_profile_id is null;
  if v_is_new then
    v_profile_id := gen_random_uuid();
  else
    select * into v_profile
      from public.payment_terminal_profiles profile
     where profile.tenant_id = v_tenant_id
       and profile.id = v_profile_id
     for update;
    if not found then
      raise exception using errcode = '42501', message = 'payment_terminal_profile_not_accessible';
    end if;
    if v_expected_updated_at is null
       or v_profile.updated_at is distinct from v_expected_updated_at then
      raise exception using errcode = '40001', message = 'payment_terminal_profile_conflict';
    end if;
    v_clearing_account_id := coalesce(
      v_clearing_account_id, v_profile.clearing_account_id
    );
    v_commission_expense_account_id := coalesce(
      v_commission_expense_account_id,
      v_profile.commission_expense_account_id
    );
    if v_clearing_account_id <> v_profile.clearing_account_id
       or v_commission_expense_account_id
          <> v_profile.commission_expense_account_id then
      raise exception using
        errcode = '55000',
        message = 'payment_terminal_ledger_accounts_immutable';
    end if;
    if v_settlement_account_id <> v_profile.settlement_account_id
       and exists (
         select 1
           from public.sales_payments payment
           join public.payment_methods method
             on method.tenant_id = payment.tenant_id
            and method.id = payment.payment_method_id
          where payment.tenant_id = v_tenant_id
            and method.terminal_profile_id = v_profile_id
            and payment.deleted_at is null
       ) then
      raise exception using
        errcode = '55000',
        message = 'payment_terminal_settlement_account_immutable';
    end if;
  end if;

  v_account_suffix := upper(left(replace(v_profile_id::text, '-', ''), 8));
  if v_clearing_account_id is null then
    perform public.ensure_account(
      v_tenant_id, '1140', 'Fondos por recibir de recaudadores',
      'asset', 'currentAsset',
      'Ventas cobradas por procesadores y aún no abonadas al banco', null
    );
    v_clearing_account_id := public.ensure_account(
      v_tenant_id, '1140-' || v_account_suffix,
      'Fondos por recibir · ' || v_provider_name || ' · ' || v_terminal_name,
      'asset', 'currentAsset',
      'Cuenta puente exclusiva del perfil de recaudación', '1140'
    );
  end if;
  if v_commission_expense_account_id is null then
    perform public.ensure_account(
      v_tenant_id, '6601', 'Gastos Financieros',
      'expense', 'financialExpense',
      'Intereses, comisiones bancarias y costos de recaudación', null
    );
    v_commission_expense_account_id := public.ensure_account(
      v_tenant_id, '6601-' || v_account_suffix,
      'Comisiones · ' || v_provider_name || ' · ' || v_terminal_name,
      'expense', 'financialExpense',
      'Comisiones documentadas del perfil de recaudación', '6601'
    );
  end if;

  if not public.payment_terminal_is_bank_account(
    v_tenant_id, v_settlement_account_id
  ) then
    raise exception using errcode = '23503', message = 'payment_terminal_account_invalid';
  end if;
  if not exists (
    select 1 from public.accounts account
     where account.tenant_id = v_tenant_id
       and account.id = v_clearing_account_id
       and account.type = 'asset'
       and account.is_active
  ) or not exists (
    select 1 from public.accounts account
     where account.tenant_id = v_tenant_id
       and account.id = v_commission_expense_account_id
       and account.type = 'expense'
       and account.is_active
  ) then
    raise exception using
      errcode = '23503', message = 'payment_terminal_ledger_account_invalid';
  end if;

  if v_is_new then
    insert into public.payment_terminal_profiles (
      id, tenant_id, provider_code, provider_name, terminal_name,
      merchant_reference, clearing_account_id,
      commission_expense_account_id, settlement_account_id,
      descriptor_patterns, is_active
    ) values (
      v_profile_id, v_tenant_id, v_provider_code, v_provider_name,
      v_terminal_name, v_merchant_reference, v_clearing_account_id,
      v_commission_expense_account_id, v_settlement_account_id,
      v_descriptor_patterns, v_is_active
    ) returning * into v_profile;
  else
    update public.payment_terminal_profiles
       set provider_code = v_provider_code,
           provider_name = v_provider_name,
           terminal_name = v_terminal_name,
           merchant_reference = v_merchant_reference,
           settlement_account_id = v_settlement_account_id,
           descriptor_patterns = v_descriptor_patterns,
           is_active = v_is_active
     where tenant_id = v_tenant_id and id = v_profile_id
     returning * into v_profile;
  end if;

  v_provider_projection := case
    when v_provider_code = 'transbank'
      or v_provider_code like 'transbank_%' then 'transbank'
    when v_provider_code = 'mercadopago'
      or v_provider_code like 'mercadopago_%' then 'mercadopago'
    else 'other'
  end;

  if (select count(*) from jsonb_array_elements(p_terms)) <>
     (select count(distinct item->>'instrument') from jsonb_array_elements(p_terms) item) then
    raise exception using errcode = '23505', message = 'payment_terminal_duplicate_instrument';
  end if;

  for v_term in select value from jsonb_array_elements(p_terms)
  loop
    if jsonb_typeof(v_term) <> 'object' then
      raise exception using errcode = '22023', message = 'payment_terminal_term_invalid';
    end if;
    v_instrument := lower(btrim(coalesce(v_term->>'instrument', '')));
    v_effective_from := nullif(v_term->>'effective_from', '')::date;
    v_payment_method_id := nullif(v_term->>'payment_method_id', '')::uuid;
    if v_instrument not in ('debit', 'credit', 'prepaid')
       or v_effective_from is null
       or coalesce((v_term->>'commission_rate_bps')::integer, -1) not between 0 and 10000
       or coalesce((v_term->>'commission_vat_bps')::integer, -1) not between 0 and 10000
       or coalesce((v_term->>'minimum_commission_uf')::numeric, -1) < 0
       or coalesce((v_term->>'settlement_business_days')::integer, -1) not between 0 and 30
       or coalesce((v_term->>'booking_grace_business_days')::integer, -1) not between 0 and 30
       or coalesce((v_term->>'amount_tolerance_clp')::integer, -1) not between 0 and 1000000 then
      raise exception using errcode = '22023', message = 'payment_terminal_term_invalid';
    end if;

    if v_payment_method_id is not null then
      select * into v_method
        from public.payment_methods method
       where method.tenant_id = v_tenant_id
         and method.id = v_payment_method_id
       for update;
      if not found then
        raise exception using errcode = '23503', message = 'payment_terminal_method_invalid';
      end if;
      if v_method.terminal_profile_id is distinct from v_profile_id then
        raise exception using errcode = '23514', message = 'payment_terminal_method_owner_mismatch';
      end if;
    else
      v_method_code := case
        when v_provider_code = 'transbank'
         and not exists (
           select 1 from public.payment_methods
            where tenant_id = v_tenant_id
              and code = 'card_' || v_instrument
         ) then 'card_' || v_instrument
        else left(v_provider_code || '_' || v_instrument || '_' ||
          replace(left(v_profile_id::text, 8), '-', ''), 80)
      end;
      v_method_name := 'Tarjeta ' || case v_instrument
        when 'debit' then 'de débito'
        when 'credit' then 'de crédito'
        else 'de prepago'
      end || case
        when v_method_code in ('card_debit', 'card_credit', 'card_prepaid')
          then ''
        else ' · ' || v_terminal_name
      end;
      insert into public.payment_methods (
        tenant_id, code, name, account_id, requires_reference,
        default_tax_treatment, icon, sort_order, is_active,
        settlement_provider, payment_instrument, usage_scope,
        terminal_profile_id
      ) values (
        v_tenant_id, v_method_code, v_method_name,
        v_clearing_account_id, false, 'tax_included', 'credit_card',
        coalesce((select max(sort_order) + 1 from public.payment_methods
          where tenant_id = v_tenant_id), 1),
        v_is_active, v_provider_projection, v_instrument, 'inbound',
        v_profile_id
      ) returning * into v_method;
      v_payment_method_id := v_method.id;
    end if;

    update public.payment_methods
       set account_id = v_clearing_account_id,
           settlement_provider = v_provider_projection,
           payment_instrument = v_instrument,
           usage_scope = 'inbound',
           terminal_profile_id = v_profile_id,
           is_active = v_is_active,
           updated_at = now()
     where tenant_id = v_tenant_id and id = v_payment_method_id;

    update public.payment_terminal_terms terms
       set effective_to = v_effective_from - 1,
           updated_at = now()
     where terms.tenant_id = v_tenant_id
       and terms.terminal_profile_id = v_profile_id
       and terms.instrument = v_instrument
       and terms.effective_from < v_effective_from
       and (terms.effective_to is null or terms.effective_to >= v_effective_from);

    insert into public.payment_terminal_terms (
      tenant_id, terminal_profile_id, payment_method_id, instrument,
      commission_rate_bps, commission_vat_bps, minimum_commission_uf,
      settlement_business_days, booking_grace_business_days,
      amount_tolerance_clp, effective_from, effective_to,
      source_note, source_url, created_by
    ) values (
      v_tenant_id, v_profile_id, v_payment_method_id, v_instrument,
      (v_term->>'commission_rate_bps')::integer,
      (v_term->>'commission_vat_bps')::integer,
      (v_term->>'minimum_commission_uf')::numeric,
      (v_term->>'settlement_business_days')::smallint,
      (v_term->>'booking_grace_business_days')::smallint,
      (v_term->>'amount_tolerance_clp')::integer,
      v_effective_from, null,
      nullif(btrim(coalesce(v_term->>'source_note', '')), ''),
      nullif(btrim(coalesce(v_term->>'source_url', '')), ''),
      v_user_id
    ) on conflict (terminal_profile_id, instrument, effective_from)
      do update set
        payment_method_id = excluded.payment_method_id,
        commission_rate_bps = excluded.commission_rate_bps,
        commission_vat_bps = excluded.commission_vat_bps,
        minimum_commission_uf = excluded.minimum_commission_uf,
        settlement_business_days = excluded.settlement_business_days,
        booking_grace_business_days = excluded.booking_grace_business_days,
        amount_tolerance_clp = excluded.amount_tolerance_clp,
        effective_to = null,
        source_note = excluded.source_note,
        source_url = excluded.source_url,
        updated_at = now();

    update public.payment_terminal_terms current_terms
       set effective_to = future_terms.next_effective_from - 1,
           updated_at = now()
      from lateral (
        select min(candidate.effective_from) as next_effective_from
          from public.payment_terminal_terms candidate
         where candidate.tenant_id = v_tenant_id
           and candidate.terminal_profile_id = v_profile_id
           and candidate.instrument = v_instrument
           and candidate.effective_from > v_effective_from
      ) future_terms
     where current_terms.tenant_id = v_tenant_id
       and current_terms.terminal_profile_id = v_profile_id
       and current_terms.instrument = v_instrument
       and current_terms.effective_from = v_effective_from
       and future_terms.next_effective_from is not null;
  end loop;

  if not v_is_active then
    update public.payment_methods
       set is_active = false, updated_at = now()
     where tenant_id = v_tenant_id
       and terminal_profile_id = v_profile_id;
  end if;

  v_receipt := jsonb_build_object(
    'operation', 'save_payment_terminal_profile',
    'operation_key', btrim(p_operation_key),
    'payload_hash', v_payload_hash,
    'replayed', false,
    'profile', public.payment_terminal_profile_snapshot(
      v_tenant_id, v_profile_id
    )
  );
  insert into public.payment_terminal_profile_operations (
    tenant_id, operation_key, payload_hash, receipt, created_by
  ) values (
    v_tenant_id, btrim(p_operation_key), v_payload_hash, v_receipt, v_user_id
  );
  return v_receipt;
end;
$$;

revoke all on function public.save_payment_terminal_profile_v1(
  text, jsonb, jsonb
) from public, anon, service_role;
grant execute on function public.save_payment_terminal_profile_v1(
  text, jsonb, jsonb
) to authenticated;

create or replace function public.seed_payment_terminal_profiles_for_tenant(
  p_tenant_id uuid
)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_settlement_account_id uuid;
  v_clearing_account_id uuid;
  v_commission_expense_account_id uuid;
  v_profile_id uuid;
  v_account_suffix text;
  v_debit_method_id uuid;
  v_credit_method_id uuid;
begin
  select method.account_id into v_settlement_account_id
    from public.payment_methods method
   where method.tenant_id = p_tenant_id and method.code = 'card'
     and public.payment_terminal_is_bank_account(
       p_tenant_id, method.account_id
     )
   limit 1;
  if v_settlement_account_id is null then
    select account.id into v_settlement_account_id
      from public.accounts account
     where account.tenant_id = p_tenant_id
       and account.code = '1110'
       and account.is_active
     order by account.id
     limit 1;
  end if;
  if v_settlement_account_id is null then
    return;
  end if;

  select profile.id into v_profile_id
    from public.payment_terminal_profiles profile
   where profile.tenant_id = p_tenant_id
     and profile.provider_code = 'transbank'
     and profile.terminal_name = 'Transbank POS';
  v_profile_id := coalesce(v_profile_id, gen_random_uuid());
  v_account_suffix := upper(left(replace(v_profile_id::text, '-', ''), 8));
  perform public.ensure_account(
    p_tenant_id, '1140', 'Fondos por recibir de recaudadores',
    'asset', 'currentAsset',
    'Ventas cobradas por procesadores y aún no abonadas al banco', null
  );
  v_clearing_account_id := public.ensure_account(
    p_tenant_id, '1140-' || v_account_suffix,
    'Fondos por recibir · Transbank · Transbank POS',
    'asset', 'currentAsset',
    'Cuenta puente exclusiva del perfil de recaudación', '1140'
  );
  perform public.ensure_account(
    p_tenant_id, '6601', 'Gastos Financieros',
    'expense', 'financialExpense',
    'Intereses, comisiones bancarias y costos de recaudación', null
  );
  v_commission_expense_account_id := public.ensure_account(
    p_tenant_id, '6601-' || v_account_suffix,
    'Comisiones · Transbank · Transbank POS',
    'expense', 'financialExpense',
    'Comisiones documentadas del perfil de recaudación', '6601'
  );

  insert into public.payment_terminal_profiles (
    id, tenant_id, provider_code, provider_name, terminal_name,
    clearing_account_id, commission_expense_account_id,
    settlement_account_id, descriptor_patterns, is_active
  ) values (
    v_profile_id, p_tenant_id, 'transbank', 'Transbank', 'Transbank POS',
    v_clearing_account_id, v_commission_expense_account_id,
    v_settlement_account_id,
    array['transbank', 'abonos debito y credito', 'abono debito credito'],
    true
  ) on conflict (tenant_id, provider_code, terminal_name)
    do update set
      clearing_account_id = excluded.clearing_account_id,
      commission_expense_account_id = excluded.commission_expense_account_id,
      settlement_account_id = excluded.settlement_account_id,
      descriptor_patterns = excluded.descriptor_patterns
  returning id into v_profile_id;

  insert into public.payment_methods (
    tenant_id, code, name, account_id, requires_reference,
    default_tax_treatment, icon, sort_order, is_active,
    settlement_provider, payment_instrument, usage_scope,
    terminal_profile_id
  ) values (
    p_tenant_id, 'card_debit', 'Tarjeta de débito', v_clearing_account_id,
    false, 'tax_included', 'credit_card', 4, true,
    'transbank', 'debit', 'inbound', v_profile_id
  ) on conflict (tenant_id, code) do update set
    settlement_provider = 'transbank', payment_instrument = 'debit',
    usage_scope = 'inbound', terminal_profile_id = v_profile_id,
    account_id = excluded.account_id, is_active = true,
    updated_at = now()
  returning id into v_debit_method_id;

  insert into public.payment_methods (
    tenant_id, code, name, account_id, requires_reference,
    default_tax_treatment, icon, sort_order, is_active,
    settlement_provider, payment_instrument, usage_scope,
    terminal_profile_id
  ) values (
    p_tenant_id, 'card_credit', 'Tarjeta de crédito', v_clearing_account_id,
    false, 'tax_included', 'credit_card', 5, true,
    'transbank', 'credit', 'inbound', v_profile_id
  ) on conflict (tenant_id, code) do update set
    settlement_provider = 'transbank', payment_instrument = 'credit',
    usage_scope = 'inbound', terminal_profile_id = v_profile_id,
    account_id = excluded.account_id, is_active = true,
    updated_at = now()
  returning id into v_credit_method_id;

  update public.payment_methods
     set terminal_profile_id = null,
         settlement_provider = 'transbank',
         payment_instrument = 'unknown',
         usage_scope = 'outbound',
         updated_at = now()
   where tenant_id = p_tenant_id and code = 'card';
  update public.payment_methods
     set usage_scope = 'inbound', updated_at = now()
   where tenant_id = p_tenant_id and code = 'mercadopago';

  insert into public.payment_terminal_terms (
    tenant_id, terminal_profile_id, payment_method_id, instrument,
    commission_rate_bps, commission_vat_bps, minimum_commission_uf,
    settlement_business_days, booking_grace_business_days,
    amount_tolerance_clp, effective_from, source_note, source_url
  ) values
    (
      p_tenant_id, v_profile_id, v_debit_method_id, 'debit',
      175, 1900, 0.002260, 1, 2, 1000, date '2026-05-20',
      'Tarifa pública de referencia para nuevos comercios; revisar el contrato particular.',
      'https://publico.transbank.cl/es/tarifas'
    ),
    (
      p_tenant_id, v_profile_id, v_credit_method_id, 'credit',
      235, 1900, 0.003515, 2, 2, 1000, date '2026-05-20',
      'Tarifa pública de referencia para nuevos comercios; revisar el contrato particular.',
      'https://publico.transbank.cl/es/tarifas'
    )
  on conflict (terminal_profile_id, instrument, effective_from) do nothing;
end;
$$;

revoke all on function public.seed_payment_terminal_profiles_for_tenant(uuid)
  from public, anon, authenticated, service_role;

create or replace function public.handle_legacy_card_method_terminal_seed()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
begin
  if new.code = 'card' then
    perform public.seed_payment_terminal_profiles_for_tenant(new.tenant_id);
  end if;
  return new;
end;
$$;

revoke all on function public.handle_legacy_card_method_terminal_seed()
  from public, anon, authenticated, service_role;

drop trigger if exists zz_seed_terminal_from_legacy_card
  on public.payment_methods;
create trigger zz_seed_terminal_from_legacy_card
  after insert or update of account_id on public.payment_methods
  for each row
  when (new.code = 'card')
  execute function public.handle_legacy_card_method_terminal_seed();

do $$
declare
  v_tenant record;
begin
  for v_tenant in select id from public.tenants loop
    perform public.seed_payment_terminal_profiles_for_tenant(v_tenant.id);
  end loop;
end;
$$;

create or replace function public.handle_new_tenant_payment_terminal_profile()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
begin
  perform public.seed_payment_terminal_profiles_for_tenant(new.id);
  return new;
end;
$$;

revoke all on function public.handle_new_tenant_payment_terminal_profile()
  from public, anon, authenticated, service_role;

drop trigger if exists zz_seed_payment_terminal_profile on public.tenants;
create trigger zz_seed_payment_terminal_profile
  after insert on public.tenants
  for each row execute function public.handle_new_tenant_payment_terminal_profile();

comment on table public.payment_terminal_profiles is
  'Tenant-owned acquiring terminals. Each profile keeps a dedicated clearing and commission account while naming the actual bank account that receives net settlements.';
comment on table public.payment_terminal_terms is
  'Versioned commercial terms per terminal and card rail. Historical sales resolve the revision effective on their transaction date.';
