-- Structured stock adjustments with explicit reason types, accounting impact,
-- movement linkage, and audit-friendly adjustment dates.

alter table public.stock_adjustments add column if not exists adjustment_date timestamp with time zone;

update public.stock_adjustments
   set adjustment_date = created_at
 where adjustment_date is null;

alter table public.stock_adjustments alter column adjustment_date set default now();
alter table public.stock_adjustments alter column adjustment_date set not null;

alter table public.stock_adjustments drop constraint if exists stock_adjustments_adjustment_type_check;

alter table public.stock_adjustments add constraint stock_adjustments_adjustment_type_check
  check (adjustment_type in ('manual', 'correction', 'initial', 'damage', 'loss', 'found', 'import', 'purchase', 'count_gain', 'count_loss', 'theft', 'internal_use'));

create index if not exists idx_stock_adjustments_adjustment_date
  on public.stock_adjustments(adjustment_date);

create or replace function public.sync_stock_adjustment_to_movement()
returns trigger as $$
begin
  insert into public.stock_movements (
    tenant_id,
    product_id,
    date,
    type,
    movement_type,
    reference,
    quantity,
    notes,
    created_at
  ) values (
    NEW.tenant_id,
    NEW.product_id,
    coalesce(NEW.adjustment_date, NEW.created_at),
    case when NEW.quantity >= 0 then 'IN' else 'OUT' end,
    NEW.adjustment_type,
    NEW.reference,
    abs(NEW.quantity),
    NEW.reason,
    NEW.created_at
  );
  return NEW;
end;
$$ language plpgsql security definer;

drop view if exists public.stock_movements_view cascade;

create view public.stock_movements_view as
with movement_documents as (
  select
    sm.id,
    sm.product_id,
    p.name as product_name,
    p.sku as product_sku,
    sm.date as transaction_date,
    sm.type,
    sm.movement_type as raw_movement_type,
    sm.reference,
    case
      when sm.type = 'OUT' then -abs(sm.quantity)
      when sm.type = 'IN' then abs(sm.quantity)
      else sm.quantity
    end as quantity,
    sm.notes,
    null::uuid as created_by,
    sm.created_at,
    sm.tenant_id,
    case
      when coalesce(sm.reference, '') ~ '^sales_invoice:[0-9a-fA-F-]{36}$'
        then split_part(sm.reference, ':', 2)::uuid
      when coalesce(sm.reference, '') ~ '^purchase_invoice:[0-9a-fA-F-]{36}$'
        then split_part(sm.reference, ':', 2)::uuid
      when coalesce(sm.reference, '') ~ '^mechanic_job:[0-9a-fA-F-]{36}$'
        then split_part(sm.reference, ':', 2)::uuid
      else null::uuid
    end as document_id,
    case
      when coalesce(sm.reference, '') like 'sales_invoice:%' then 'sales_invoice'
      when coalesce(sm.reference, '') like 'purchase_invoice:%' then 'purchase_invoice'
      when coalesce(sm.reference, '') like 'mechanic_job:%' then 'mechanic_job'
      else null::text
    end as document_type
  from public.stock_movements sm
  left join public.products p
    on nullif(sm.product_id::text, '')::uuid = p.id
   and sm.tenant_id = p.tenant_id
),
movements_with_resolution as (
  select
    md.id,
    md.product_id,
    md.product_name,
    md.product_sku,
    md.transaction_date,
    case
      when md.document_type = 'sales_invoice' then 'sale'
      when md.document_type = 'purchase_invoice' then 'purchase'
      when md.document_type = 'mechanic_job' then 'sale'
      when coalesce(md.raw_movement_type, '') in ('purchase', 'purchase_invoice', 'manual_purchase') then 'purchase'
      when coalesce(md.raw_movement_type, '') in ('sale', 'sales_invoice', 'sales_invoice_component', 'manual_sale') then 'sale'
      when coalesce(md.raw_movement_type, '') in ('transfer', 'transfer_in', 'transfer_out') then 'transfer'
      when coalesce(md.raw_movement_type, '') in ('manual', 'correction', 'initial', 'damage', 'loss', 'found', 'import', 'adjustment', 'inventory_adjust', 'inventory_adjustment', 'count_gain', 'count_loss', 'theft', 'internal_use') then 'adjustment'
      else 'adjustment'
    end as movement_type,
    case
      when md.document_type = 'sales_invoice' then coalesce(si.source, 'sale')
      when md.document_type = 'purchase_invoice' then 'purchase_invoice'
      when md.document_type = 'mechanic_job' then 'mechanic_job'
      when nullif(trim(coalesce(md.raw_movement_type, '')), '') is not null then md.raw_movement_type
      else 'manual'
    end as source,
    case
      when md.document_type in ('sales_invoice', 'purchase_invoice', 'mechanic_job') then md.document_id
      when sa.id is not null then sa.id
      else null::uuid
    end as reference_id,
    case
      when md.document_type = 'sales_invoice' then coalesce(nullif(si.invoice_number, ''), md.reference)
      when md.document_type = 'purchase_invoice' then coalesce(nullif(pi.invoice_number, ''), md.reference)
      when md.document_type = 'mechanic_job' then coalesce(nullif(mj.job_number, ''), md.reference)
      when sa.id is not null then coalesce(
        nullif(sa.reference, ''),
        nullif(trim(coalesce(md.reference, '')), ''),
        nullif(trim(coalesce(md.notes, '')), ''),
        null::text
      )
      when nullif(trim(coalesce(md.reference, '')), '') is not null then md.reference
      when nullif(trim(coalesce(md.notes, '')), '') is not null then md.notes
      else null::text
    end as reference_number,
    md.quantity,
    md.notes,
    coalesce(md.created_by, sa.created_by) as created_by,
    md.created_at,
    md.tenant_id
  from movement_documents md
  left join public.sales_invoices si
    on md.document_type = 'sales_invoice'
   and md.document_id = si.id
   and md.tenant_id = si.tenant_id
  left join public.purchase_invoices pi
    on md.document_type = 'purchase_invoice'
   and md.document_id = pi.id
   and md.tenant_id = pi.tenant_id
  left join public.mechanic_jobs mj
    on md.document_type = 'mechanic_job'
   and md.document_id = mj.id
   and md.tenant_id = mj.tenant_id
  left join public.stock_adjustments sa
    on md.document_type is null
   and md.tenant_id = sa.tenant_id
   and md.product_id = sa.product_id
   and md.created_at = sa.created_at
   and md.quantity = sa.quantity
   and coalesce(md.raw_movement_type, '') = sa.adjustment_type
),
movements_with_running_stock as (
  select
    m.*,
    greatest(coalesce(p.stock_quantity, 0), coalesce(p.inventory_qty, 0)) as current_stock,
    greatest(coalesce(p.stock_quantity, 0), coalesce(p.inventory_qty, 0)) - coalesce(
      sum(m.quantity) over (
        partition by m.product_id, m.tenant_id
        order by m.transaction_date desc nulls last, m.created_at desc, m.id desc
        rows between unbounded preceding and 1 preceding
      ),
      0
    )::integer as calculated_stock_after
  from movements_with_resolution m
  left join public.products p
    on nullif(m.product_id::text, '')::uuid = p.id
   and m.tenant_id = p.tenant_id
)
select
  id,
  product_id,
  product_name,
  product_sku,
  transaction_date,
  movement_type,
  source,
  reference_id,
  reference_number,
  quantity,
  (calculated_stock_after - quantity)::integer as stock_before,
  calculated_stock_after as stock_after,
  notes,
  created_by,
  created_at,
  tenant_id
from movements_with_running_stock;

create or replace function public.apply_inventory_stock_adjustment(
  p_product_id uuid,
  p_quantity integer,
  p_type text,
  p_reason_type text,
  p_note text default null,
  p_effective_at timestamp with time zone default now()
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_product public.products%rowtype;
  v_delta integer;
  v_stock_before integer;
  v_stock_after integer;
  v_reason_label text;
  v_reason text;
  v_adjustment_type text;
  v_reference text;
  v_adjustment_date timestamp with time zone := coalesce(p_effective_at, now());
  v_created_at timestamp with time zone := now();
  v_adjustment_id uuid;
  v_movement_id uuid;
  v_inventory_account_id uuid;
  v_counterpart_account_id uuid;
  v_counterpart_account_code text;
  v_counterpart_account_name text;
  v_inventory_value numeric(14,2) := 0;
  v_entry_id uuid;
  v_entry_number text;
  v_description text;
begin
  if p_type not in ('IN', 'OUT') then
    raise exception 'Invalid stock adjustment type: %', p_type
      using errcode = 'check_violation';
  end if;

  if p_quantity <= 0 then
    raise exception 'Stock adjustment quantity must be positive: %', p_quantity
      using errcode = 'check_violation';
  end if;

  if p_reason_type not in ('manual', 'count', 'loss', 'damage', 'theft', 'internal_use', 'found') then
    raise exception 'Invalid stock adjustment reason type: %', p_reason_type
      using errcode = 'check_violation';
  end if;

  if p_type = 'IN' and p_reason_type in ('loss', 'damage', 'theft', 'internal_use') then
    raise exception 'Reason % is only valid for stock decreases', p_reason_type
      using errcode = 'check_violation';
  end if;

  if p_type = 'OUT' and p_reason_type = 'found' then
    raise exception 'Reason % is only valid for stock increases', p_reason_type
      using errcode = 'check_violation';
  end if;

  select *
    into v_product
    from public.products
   where id = p_product_id
     and tenant_id = public.user_tenant_id()
   for update;

  if not found then
    raise exception 'Product % not found for current tenant', p_product_id
      using errcode = 'foreign_key_violation';
  end if;

  if coalesce(v_product.product_type, 'product') = 'service'
     or coalesce(v_product.track_stock, true) = false then
    raise exception 'Product % does not track stock', coalesce(v_product.name, p_product_id::text)
      using errcode = 'check_violation';
  end if;

  v_delta := case when p_type = 'IN' then p_quantity else -p_quantity end;
  v_stock_before := greatest(coalesce(v_product.inventory_qty, 0), coalesce(v_product.stock_quantity, 0));
  v_stock_after := v_stock_before + v_delta;

  if v_stock_after < 0 then
    raise exception 'Stock cannot go negative for product %', coalesce(v_product.name, p_product_id::text)
      using errcode = 'check_violation';
  end if;

  case p_reason_type
    when 'count' then
      v_adjustment_type := case when p_type = 'IN' then 'count_gain' else 'count_loss' end;
      v_reason_label := 'Regularización por conteo';
    when 'loss' then
      v_adjustment_type := 'loss';
      v_reason_label := 'Merma';
    when 'damage' then
      v_adjustment_type := 'damage';
      v_reason_label := 'Daño';
    when 'theft' then
      v_adjustment_type := 'theft';
      v_reason_label := 'Robo / extravío';
    when 'internal_use' then
      v_adjustment_type := 'internal_use';
      v_reason_label := 'Uso interno / taller';
    when 'found' then
      v_adjustment_type := 'found';
      v_reason_label := 'Hallazgo / recuperación';
    else
      v_adjustment_type := 'manual';
      v_reason_label := 'Ajuste Manual';
  end case;

  v_reason := case
    when nullif(trim(coalesce(p_note, '')), '') is null then v_reason_label
    else format('%s: %s', v_reason_label, trim(p_note))
  end;
  v_reference := public.get_next_document_number(v_product.tenant_id, 'stock_adjustment');
  v_inventory_value := round(abs(v_delta) * greatest(coalesce(v_product.cost, 0), 0), 2);
  v_description := format('%s %s - %s', v_reason_label, v_reference, v_product.name);

  perform set_config('app.skip_stock_adjustment_trigger', 'true', true);

  update public.products
     set inventory_qty = v_stock_after,
         stock_quantity = v_stock_after,
         updated_at = v_created_at
   where id = v_product.id
     and tenant_id = v_product.tenant_id;

  insert into public.stock_adjustments (
    tenant_id,
    product_id,
    adjustment_type,
    quantity,
    stock_before,
    stock_after,
    reason,
    reference,
    adjustment_date,
    created_by,
    created_at
  ) values (
    v_product.tenant_id,
    v_product.id,
    v_adjustment_type,
    v_delta,
    v_stock_before,
    v_stock_after,
    v_reason,
    v_reference,
    v_adjustment_date,
    auth.uid(),
    v_created_at
  )
  returning id into v_adjustment_id;

  if v_inventory_value > 0 then
    v_inventory_account_id := public.ensure_account(
      v_product.tenant_id,
      '1105',
      'Inventario de Productos',
      'asset',
      'currentAsset',
      'Valor de productos y repuestos en stock',
      null
    );

    if p_type = 'OUT' then
      case p_reason_type
        when 'internal_use' then
          v_counterpart_account_code := '5101';
          v_counterpart_account_name := 'Consumibles de Taller';
        when 'damage' then
          v_counterpart_account_code := '6196';
          v_counterpart_account_name := 'Pérdidas por Daño de Inventario';
        when 'theft' then
          v_counterpart_account_code := '6197';
          v_counterpart_account_name := 'Pérdidas por Robo de Inventario';
        when 'loss' then
          v_counterpart_account_code := '6195';
          v_counterpart_account_name := 'Mermas de Inventario';
        else
          v_counterpart_account_code := '6198';
          v_counterpart_account_name := 'Diferencias de Inventario';
      end case;

      v_counterpart_account_id := public.ensure_account(
        v_product.tenant_id,
        v_counterpart_account_code,
        v_counterpart_account_name,
        'expense',
        'operatingExpense',
        'Ajustes negativos de inventario registrados manualmente',
        null
      );
    else
      case p_reason_type
        when 'found' then
          v_counterpart_account_code := '4202';
          v_counterpart_account_name := 'Recuperaciones de Inventario';
        else
          v_counterpart_account_code := '4203';
          v_counterpart_account_name := 'Ajustes Positivos de Inventario';
      end case;

      v_counterpart_account_id := public.ensure_account(
        v_product.tenant_id,
        v_counterpart_account_code,
        v_counterpart_account_name,
        'income',
        'nonOperatingIncome',
        'Ingresos no operacionales derivados de ajustes positivos de inventario',
        null
      );
    end if;

    v_entry_id := gen_random_uuid();
    v_entry_number := public.get_next_document_number(v_product.tenant_id, 'journal_entry');

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
      created_at,
      updated_at
    ) values (
      v_entry_id,
      v_product.tenant_id,
      v_entry_number,
      v_adjustment_date,
      v_description,
      'adjustment',
      'stock_adjustment',
      v_adjustment_id::text,
      'posted',
      v_inventory_value,
      v_inventory_value,
      v_created_at,
      v_created_at
    );

    if p_type = 'OUT' then
      insert into public.journal_lines (
        id,
        entry_id,
        account_id,
        tenant_id,
        account_code,
        account_name,
        description,
        debit_amount,
        credit_amount,
        created_at,
        updated_at
      ) values (
        gen_random_uuid(),
        v_entry_id,
        v_counterpart_account_id,
        v_product.tenant_id,
        v_counterpart_account_code,
        v_counterpart_account_name,
        v_description,
        v_inventory_value,
        0,
        v_created_at,
        v_created_at
      );

      insert into public.journal_lines (
        id,
        entry_id,
        account_id,
        tenant_id,
        account_code,
        account_name,
        description,
        debit_amount,
        credit_amount,
        created_at,
        updated_at
      ) values (
        gen_random_uuid(),
        v_entry_id,
        v_inventory_account_id,
        v_product.tenant_id,
        '1105',
        'Inventario de Productos',
        v_description,
        0,
        v_inventory_value,
        v_created_at,
        v_created_at
      );
    else
      insert into public.journal_lines (
        id,
        entry_id,
        account_id,
        tenant_id,
        account_code,
        account_name,
        description,
        debit_amount,
        credit_amount,
        created_at,
        updated_at
      ) values (
        gen_random_uuid(),
        v_entry_id,
        v_inventory_account_id,
        v_product.tenant_id,
        '1105',
        'Inventario de Productos',
        v_description,
        v_inventory_value,
        0,
        v_created_at,
        v_created_at
      );

      insert into public.journal_lines (
        id,
        entry_id,
        account_id,
        tenant_id,
        account_code,
        account_name,
        description,
        debit_amount,
        credit_amount,
        created_at,
        updated_at
      ) values (
        gen_random_uuid(),
        v_entry_id,
        v_counterpart_account_id,
        v_product.tenant_id,
        v_counterpart_account_code,
        v_counterpart_account_name,
        v_description,
        0,
        v_inventory_value,
        v_created_at,
        v_created_at
      );
    end if;
  end if;

  perform set_config('app.skip_stock_adjustment_trigger', '', true);

  select sm.id
    into v_movement_id
    from public.stock_movements sm
   where sm.tenant_id = v_product.tenant_id
     and sm.product_id = v_product.id
     and sm.created_at = v_created_at
     and sm.movement_type = v_adjustment_type
   order by sm.id desc
   limit 1;

  return jsonb_build_object(
    'adjustment_id', v_adjustment_id,
    'movement_id', v_movement_id,
    'reference_number', v_reference,
    'product_id', v_product.id,
    'product_name', v_product.name,
    'product_sku', v_product.sku,
    'type', p_type,
    'adjustment_type', v_adjustment_type,
    'quantity', v_delta,
    'stock_before', v_stock_before,
    'stock_after', v_stock_after,
    'reason', v_reason,
    'adjustment_date', v_adjustment_date,
    'created_at', v_created_at,
    'journal_entry_id', v_entry_id,
    'journal_entry_number', v_entry_number,
    'inventory_value', v_inventory_value
  );
exception
  when others then
    perform set_config('app.skip_stock_adjustment_trigger', '', true);
    raise;
end;
$$;

grant execute on function public.apply_inventory_stock_adjustment(uuid, integer, text, text, text, timestamp with time zone) to authenticated;

create or replace function public.apply_manual_stock_adjustment(
  p_product_id uuid,
  p_quantity integer,
  p_type text,
  p_reason text default 'Ajuste Manual'
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  return public.apply_inventory_stock_adjustment(
    p_product_id,
    p_quantity,
    p_type,
    'count',
    p_reason,
    now()
  );
end;
$$;

grant execute on function public.apply_manual_stock_adjustment(uuid, integer, text, text) to authenticated;

create or replace function public.get_stock_adjustment_details(
  p_adjustment_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_adjustment record;
  v_entry record;
  v_counterpart_account_code text;
  v_counterpart_account_name text;
  v_counterpart_debit numeric;
  v_counterpart_credit numeric;
begin
  select
    sa.id,
    sa.tenant_id,
    sa.product_id,
    sa.adjustment_type,
    sa.quantity,
    sa.stock_before,
    sa.stock_after,
    sa.reason,
    sa.reference,
    sa.adjustment_date,
    sa.created_at,
    sa.created_by,
    p.name as product_name,
    p.sku as product_sku,
    p.cost as unit_cost,
    au.email as created_by_email,
    abs(sa.quantity) * greatest(coalesce(p.cost, 0), 0) as inventory_value
  into v_adjustment
  from public.stock_adjustments sa
  join public.products p
    on p.id = sa.product_id
   and p.tenant_id = sa.tenant_id
  left join auth.users au
    on au.id = sa.created_by
  where sa.id = p_adjustment_id
    and sa.tenant_id = public.user_tenant_id();

  if not found then
    raise exception 'Stock adjustment % not found for current tenant', p_adjustment_id
      using errcode = 'foreign_key_violation';
  end if;

  select
    je.id,
    je.entry_number,
    je.entry_date,
    je.description,
    je.total_debit,
    je.total_credit
  into v_entry
  from public.journal_entries je
  where je.tenant_id = v_adjustment.tenant_id
    and je.source_module = 'stock_adjustment'
    and je.source_reference = v_adjustment.id::text
  order by je.created_at desc
  limit 1;

  if v_entry.id is not null then
    select
      jl.account_code,
      jl.account_name,
      jl.debit_amount,
      jl.credit_amount
    into v_counterpart_account_code,
         v_counterpart_account_name,
         v_counterpart_debit,
         v_counterpart_credit
    from public.journal_lines jl
    where jl.entry_id = v_entry.id
      and jl.account_code <> '1105'
    order by greatest(jl.debit_amount, jl.credit_amount) desc, jl.created_at asc
    limit 1;
  end if;

  return jsonb_build_object(
    'id', v_adjustment.id,
    'product_id', v_adjustment.product_id,
    'product_name', v_adjustment.product_name,
    'product_sku', v_adjustment.product_sku,
    'adjustment_type', v_adjustment.adjustment_type,
    'reference_number', v_adjustment.reference,
    'quantity', v_adjustment.quantity,
    'stock_before', v_adjustment.stock_before,
    'stock_after', v_adjustment.stock_after,
    'reason', v_adjustment.reason,
    'adjustment_date', v_adjustment.adjustment_date,
    'created_at', v_adjustment.created_at,
    'created_by', v_adjustment.created_by,
    'created_by_email', v_adjustment.created_by_email,
    'unit_cost', v_adjustment.unit_cost,
    'inventory_value', v_adjustment.inventory_value,
    'journal_entry_id', v_entry.id,
    'journal_entry_number', v_entry.entry_number,
    'journal_entry_date', v_entry.entry_date,
    'journal_entry_description', v_entry.description,
    'counterpart_account_code', v_counterpart_account_code,
    'counterpart_account_name', v_counterpart_account_name,
    'counterpart_debit', v_counterpart_debit,
    'counterpart_credit', v_counterpart_credit
  );
end;
$$;

grant execute on function public.get_stock_adjustment_details(uuid) to authenticated;